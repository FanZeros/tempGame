-- LobbyClient.lua — Runtime 侧大厅客户端：把异步桥（lobbyBridge）包成「动作带内联回调」的 API 供大厅脚本调用。
--
-- 设计：一个动作会引发的后续事件，回调写进这个动作的 opts（内联），不做全局订阅。
--   - 动作回执（改状态用到达态命名 onCreated/onJoined/onLeft/onStarted；纯查询用 onSuccess + onError）
--     → lobbyBridge:call(action, argsJson)，结果按 reqId 经 "result" 事件回执；
--   - 匹配流程事件（onMatchFound/onProgress）→ StartMatch/StartGame 时存进 _match，
--     由 "matchFound"/"serverProgress" 喂；
--   - 房间流程事件（onPlayersChanged/onKicked）→ CreateRoom/JoinRoom 时存进 _room，
--     由 "teamStatus"/"roomLeft" 喂；
--   - 只读（GetMyUserId/GetProjectId/GetMaxPlayers/IsOnline）→ lobbyBridge:getX()（C++ 同步直取）；
--     IsInRoom/IsMatching → 缓存（由 host 推来的 "state" 事件更新）；
--   - 无触发动作的平台主动推送 → 独立订阅：OnError；
--     系统弹窗由 SystemNotification 兼容层直喂旧 OnSystemDialog，新版走 RegisterHandler。
--
-- 桥由构造时注入（Client.New(bridge)，LobbyBootstrap 传入私有桥），不读全局 lobbyBridge。依赖 Runtime 全局：cjson。

local Client = {}
Client.__index = Client

local SystemNotification = require("urhox-libs.System.SystemNotification")

local function Decode(s)
    if s == nil or s == "" then return {} end
    local ok, v = pcall(cjson.decode, s)
    return ok and v or {}
end
local function Encode(t)
    local ok, v = pcall(cjson.encode, t or {})
    if ok then return v end
    return nil, v
end

-- 整理 teamStatus.players：只透出展示字段，过滤业务 / 敏感字段
local function DigestPlayers(ts)
    local players = {}
    for _, p in ipairs((ts and ts.players) or {}) do
        players[#players + 1] = { userId = p.userId, nickname = p.nickname or "", avatar = p.avatar or "" }
    end
    return players, ts and ts.masterId
end

-- 装唯一事件分发器：result(按 reqId 回执) / state(更新缓存) / 流程事件(喂 _match·_room) / 平台推送(独立订阅)
local function InstallEventHandler(self)
    self._bridge:setEventHandler(function(event, dataJson)
        local d = Decode(dataJson)
        if event == "result" then
            local p = self._pending[d.reqId]
            if p then
                self._pending[d.reqId] = nil
                if d.ok then
                    if p.onSuccess then p.onSuccess(d) end
                else
                    -- 把 host 的可读原因（message）一并透出，制作人不必去猜 errorCode 是什么
                    if p.onError then p.onError(d.errorCode, d.message) end
                end
            end
        elseif event == "state" then
            self._state.isInRoom = d.isInRoom and true or false
            self._state.isMatching = d.isMatching and true or false
        elseif event == "matchFound" then
            if self._match and self._match.onMatchFound then self._match.onMatchFound(d.serverInfo) end
        elseif event == "serverProgress" then
            if self._match and self._match.onProgress then self._match.onProgress(d.progress or 0, d.status or "") end
        elseif event == "teamStatus" then
            if self._room and self._room.onPlayersChanged then
                local players, masterId = DigestPlayers(d.teamStatus)
                self._room.onPlayersChanged(players, masterId)
            end
        elseif event == "roomLeft" then
            -- 房间会话结束。主动 leaveRoom 由其回执 onLeft 处理（_leaving 抑制 onKicked，规避两端时序）；
            -- 被踢 / 房间解散等非主动结束 → 触发房间流程的 onKicked。
            local r = self._room
            self._room = nil
            if self._leaving then
                self._leaving = false
            elseif r and r.onKicked then
                r.onKicked()
            end
        elseif event == "error" then
            if self._onError then self._onError(d.errorType, d.errorCode) end
        elseif event == "uiConfig" then
            -- 引导握手回应（非制作人面）：见 RequestUIConfig。
            if self._onUIConfig then self._onUIConfig(d.config) end
        end
    end)
end

function Client.New(bridge)
    local self = setmetatable({}, Client)
    self._bridge = bridge  -- 私有桥（由 LobbyBootstrap 注入；不读全局 lobbyBridge）
    self._pending = {}    -- reqId -> { onSuccess, onError }（动作回执）
    self._match = nil     -- 当前匹配流程：{ onMatchFound, onProgress }
    self._room = nil      -- 当前房间流程：{ onPlayersChanged, onKicked }
    self._leaving = false -- 主动离开标记：抑制随后 roomLeft 的 onKicked
    self._onError = nil
    self._onSystemDialog = nil
    self._onUIConfig = nil
    self._state = { isInRoom = false, isMatching = false }
    self._seq = 0         -- 自有关联 id（不依赖桥的 reqId，避免同步回执时序问题）
    InstallEventHandler(self)
    return self
end

-- 发起带回执的动作：**先**存回调（防同步回执丢失），再经桥发出；id 随 args 以 __reqId 传给 host、由其回显。
local function Call(self, action, args, onSuccess, onError)
    self._seq = self._seq + 1
    local id = self._seq
    if onSuccess or onError then
        self._pending[id] = { onSuccess = onSuccess, onError = onError }
    end
    local a = {}
    for k, v in pairs(args or {}) do a[k] = v end
    a.__reqId = id
    local payload, err = Encode(a)
    if not payload then
        self._pending[id] = nil
        if onError then onError(-10001) end
        if log and log.Write then
            log:Write(LOG_ERROR, "[LobbyClient] encode action failed: " .. tostring(action) .. ", error=" .. tostring(err))
        end
        return id
    end
    self._bridge:call(action, payload)
    return id
end

-- 取 opts 里除回调外的数据字段（回调都是 function，天然被过滤）
local function DataOnly(opts)
    local t = {}
    for k, v in pairs(opts or {}) do
        if type(v) ~= "function" then t[k] = v end
    end
    return t
end

-- ---- 只读（lobbyBridge 同步 / 缓存状态）----
function Client:GetMyUserId()   return self._bridge:getMyUserId() end
function Client:GetMaxPlayers() return self._bridge:getMaxPlayers() end
function Client:GetProjectId()  return self._bridge:getProjectId() end
function Client:IsOnline()      return self._bridge:isOnline() end
function Client:IsInRoom()      return self._state.isInRoom end
function Client:IsMatching()    return self._state.isMatching end

-- ---- 平台主动推送（独立订阅，cb=nil 即注销）----
function Client:OnError(cb)        self._onError = cb end
function Client:OnSystemDialog(cb) self._onSystemDialog = cb end

-- Runtime-hide 用新版 SystemNotification 兼容旧版 OnSystemDialog。
-- 旧回调没有返回值契约；只要回调正常执行就视为已接管。
function Client:_DispatchLegacySystemDialog(info)
    if type(self._onSystemDialog) ~= "function" then
        return false
    end

    local view = SystemNotification.Resolve(info)
    local dialog = {
        kind = view.kind,
        title = view.title,
        message = view.reason or view.message,
        exitOnClose = view.exitOnClose,
    }

    local ok, handled = pcall(self._onSystemDialog, dialog)
    if not ok then
        print("[LobbyClient] legacy OnSystemDialog failed: " .. tostring(handled))
        return false
    end
    return true
end

-- ---- 引导握手（非制作人面：由 LobbyRuntimeUI 调，取一次 UI 配置）----
function Client:RequestUIConfig(onConfig)
    self._onUIConfig = onConfig
    Call(self, "requestUIConfig", {})
end

-- ---- 动作（内联回调）----

-- 快速匹配：onStarted 回执（已开始）；匹配成功 onMatchFound；随后平台自动连服 onProgress。
function Client:StartMatch(opts)
    opts = opts or {}
    self._match = { onMatchFound = opts.onMatchFound, onProgress = opts.onProgress }
    return Call(self, "startMatch", DataOnly(opts), opts.onStarted, opts.onError)
end

-- 房主开始游戏：链路同 StartMatch（开始 → 分配服务器 → 连服）。
function Client:StartGame(opts)
    opts = opts or {}
    self._match = { onMatchFound = opts.onMatchFound, onProgress = opts.onProgress }
    return Call(self, "startGame", DataOnly(opts), opts.onStarted, opts.onError)
end

-- 创建房间：onCreated(roomId) 回执；进房后房内人员变化走 onPlayersChanged，房间非主动结束走 onKicked。
function Client:CreateRoom(opts)
    opts = opts or {}
    self._room = { onPlayersChanged = opts.onPlayersChanged, onKicked = opts.onKicked }
    Call(self, "createRoom", DataOnly(opts),
        function(d) if opts.onCreated then opts.onCreated(d.roomId) end end,
        opts.onError)
end

-- 加入房间：onJoined 回执；房间流程回调同 CreateRoom。
function Client:JoinRoom(opts)
    opts = opts or {}
    self._room = { onPlayersChanged = opts.onPlayersChanged, onKicked = opts.onKicked }
    Call(self, "joinRoom", DataOnly(opts), opts.onJoined, opts.onError)
end

-- 离开房间：onLeft 回执（主动离开，抑制 onKicked）。
function Client:LeaveRoom(opts)
    opts = opts or {}
    self._leaving = true
    -- 失败路径必须复位 _leaving：若 leaveRoom 以 onError 结束（没有 roomLeft 事件来消费它），
    -- _leaving 会一直为 true，导致此后被踢/解散的 roomLeft 误入抑制分支、onKicked 被永久静默。
    Call(self, "leaveRoom", {}, opts.onLeft, function(errorCode, message)
        self._leaving = false
        if opts.onError then opts.onError(errorCode, message) end
    end)
end

-- 取消匹配：协议无回执，发起即忘；IsMatching() 缓存由随后的 "state" 事件转 false。
function Client:CancelMatch()
    self._match = nil
    Call(self, "cancelMatch", {})
end

-- 房间列表（纯查询）：onSuccess(rooms) 回执。
function Client:GetRoomList(opts)
    opts = opts or {}
    Call(self, "getRoomList", DataOnly(opts),
        function(d) if opts.onSuccess then opts.onSuccess(d.rooms or {}) end end,
        opts.onError)
end

-- 昵称（纯查询）：onSuccess(nicknames) 回执。
function Client:GetUserNickname(opts)
    opts = opts or {}
    Call(self, "getUserNickname", { userIds = opts.userIds },
        function(d) if opts.onSuccess then opts.onSuccess(d.nicknames or {}) end end,
        opts.onError)
end

return Client
