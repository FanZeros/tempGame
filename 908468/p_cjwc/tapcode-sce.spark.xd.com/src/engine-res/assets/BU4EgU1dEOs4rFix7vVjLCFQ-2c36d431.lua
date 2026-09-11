-- LobbyControl.lua — HostSandbox 侧大厅控制（Host 侧唯一控制宿主）。
--
-- main.lua require 本文件为 `LobbyControl`，控制流程只通过本文件的门面方法触达 LobbyManager。
-- 本文件是 Host 侧唯一的大厅控制：
--   - 自持真实 `LobbyManager`（持裸 lobby）；
--   - 经 `lobbyBridge` 接 Runtime 来的 §3 动作 → 调 `LobbyManager`（action router）；
--   - `LobbyManager` 回调 / 状态 → 经桥 emit 给 Runtime（result / state / 具名事件）；
--   - main.lua 的 UI 显示类：系统通知先 Dispatch，Runtime handler 可接管；未处理时
--     由 `SystemDialog` 在 Host 侧兜底；Runtime-hide 已将旧 OnSystemDialog 适配到该 handler；
--   - 后台匹配（含重试）+ `ReturnToLobby`（裸 lobby + network）本地。
--
-- 依赖 HostSandbox 全局：lobbyBridge、cjson、lobby（裸）、cache、GetNetwork、VariantMap/Variant、
-- SubscribeToEvent/UnsubscribeFromEvent/SendEvent。

local LobbyManager = require("urhox-libs.GameLobby.HostSandbox.LobbyManager")
local SystemDialog = require("urhox-libs.GameLobby.HostSandbox.SystemDialog")
local SystemNotification = require("urhox-libs.System.SystemNotification")

local M = {}

-- Lobby 封禁错误码（game/Proto/LobbyServer/TSLobbyServer.proto），与 Lobby/LobbyUI.lua
-- 导出的同名常量保持一致（两份大厅并行维护）。注意两个枚举空间的值不同：
-- MatchErrorCode 里 11 是封禁，GameStartErrorCode 里封禁是 14（11 是查 package_type 失败）。
M.MATCH_ERROR_PLAYER_BANNED = 11      -- MatchErrorCode.M_PLAYER_BANNED
M.GAME_START_ERROR_PLAYER_BANNED = 14 -- GameStartErrorCode.SG_PLAYER_BANNED
M.PLAYER_BANNED_MESSAGE = _tr("t_8fBGgKN08EbME96K")

local lobbyMgr_ = nil
local config_ = nil
local returnHandlerInstalled_ = false
M.isReturningToLobby_ = false

local backgroundMatchState = {
    retryCount = 0,
    maxRetries = 10,
    retryDelay = 2.0,
    isMatching = false,
    retryTimerNode = nil,
    retryTimerObject = nil,
    retryTimerToken = 0,
    generation = 0,
}

-- 用 LuaScriptObject 承载 retry timer 的 Update 订阅：全局 SubscribeToEvent 返回 void、
-- 拿不到可取消句柄，取消归属在该 LuaScriptInstance 上并按事件名取消。token 自增让任何在途的
-- 旧回调即便被触发也直接返回，避免到期后逐帧重发匹配请求。
local function cancelBackgroundRetryTimer()
    backgroundMatchState.retryTimerToken = backgroundMatchState.retryTimerToken + 1
    if backgroundMatchState.retryTimerObject then
        backgroundMatchState.retryTimerObject:UnsubscribeFromEvent("Update")
        backgroundMatchState.retryTimerObject = nil
    end
    if backgroundMatchState.retryTimerNode then
        backgroundMatchState.retryTimerNode:Remove()
        backgroundMatchState.retryTimerNode = nil
    end
end

local function nextBackgroundMatchGeneration()
    backgroundMatchState.generation = backgroundMatchState.generation + 1
    return backgroundMatchState.generation
end

local function isBackgroundMatchGenerationActive(generation)
    return backgroundMatchState.isMatching and backgroundMatchState.generation == generation
end

-- ============================================================================
-- JSON / 桥 helpers
-- ============================================================================

local function decode(s)
    if s == nil or s == "" then return {} end
    local ok, v = pcall(cjson.decode, s)
    return ok and v or {}
end
local function encode(t)
    local ok, v = pcall(cjson.encode, t or {})
    return ok and v or "{}"
end
local function emit(event, data)
    if lobbyBridge then lobbyBridge:emit(event, encode(data)) end
end

-- ============================================================================
-- 匹配参数构建（平台固定，§3.1/§3.5）
-- mode_id 用 string.format 固定字段顺序（Lua 表遍历序不固定）+ 含 project_version（不同版本不进同桶）。
-- ============================================================================

local function buildMatchParams(mp, projectVersion, opts)
    mp = mp or {}
    opts = opts or {}
    projectVersion = projectVersion or ""

    local maxPlayers = mp.max_players
    if not maxPlayers or maxPlayers <= 0 then maxPlayers = 4 end

    local ext = mp.match_info or {}
    local descName = ext.desc_name or "free_match_with_ai"
    local playerNumber = ext.player_number or maxPlayers
    local immediatelyStart = ext.immediately_start ~= nil and ext.immediately_start or false
    local matchTimeout = ext.match_timeout or 60

    local modeId = string.format(
        '{"desc_name":"%s","immediately_start":%s,"match_timeout":%d,"player_number":%d,"project_version":"%s"}',
        descName, tostring(immediatelyStart), matchTimeout, playerNumber, projectVersion)

    return {
        mapName = opts.mapName,
        mode = opts.mode,
        matchInfo = {
            desc_name = descName,
            player_number = playerNumber,
            immediately_start = immediatelyStart,
            match_timeout = matchTimeout,
            mode_id = modeId,
        },
    }
end
M._buildMatchParams = buildMatchParams -- 暴露给自测

-- 读 settings.json 的 multiplayer 块
local function readMultiplayer()
    if cache and cache.GetFile then
        local f = cache:GetFile("settings.json")
        if f then
            local s = f:ReadString(); f:Close()
            local ok, j = pcall(cjson.decode, s)
            if ok and j and j.multiplayer then return j.multiplayer end
        end
    end
    return {}
end

local function projectVersion()
    return (LobbyManager.GetProjectVersion and LobbyManager.GetProjectVersion()) or ""
end

-- 交互快速匹配（经桥）：mapName 优先用 UI 框架算好的（桥 a）→ Host GetProjectId → DefaultMap
local function resolveMatchParams(a)
    local mapName = a and a.mapName
    if (not mapName or mapName == "") and lobbyMgr_ then
        local okId, id = pcall(function() return lobbyMgr_:GetProjectId() end)
        if okId then mapName = id end
    end
    if not mapName or mapName == "" then mapName = "DefaultMap" end
    return buildMatchParams(readMultiplayer(), projectVersion(), { mapName = mapName, mode = a and a.mode })
end

-- 房间动作（createRoom/getRoomList/startGame）的程序决定参数兜底——与 resolveMatchParams 同口径。
-- 这些参数模板里本就是程序算好的（mapName=projectId、maxPlayers=settings、mode），不该让制作人手传，
-- 更不该因缺 mapName 丢个 -10003 给制作人。这里 Host 统一补：mapName 用 GetProjectId（空回退 DefaultMap），
-- maxPlayers 用 settings.max_players（空回退 4），mode 默认 "default"；保留 a 的其它字段（如 modes/roomId）。
local function resolveRoomParams(a)
    a = a or {}
    local out = {}
    for k, v in pairs(a) do out[k] = v end
    if not out.mapName or out.mapName == "" then
        local okId, id = pcall(function() return lobbyMgr_:GetProjectId() end)
        out.mapName = (okId and id and id ~= "") and id or "DefaultMap"
    end
    if not out.maxPlayers or out.maxPlayers <= 0 then
        local mp = readMultiplayer().max_players
        out.maxPlayers = (type(mp) == "number" and mp > 0) and mp or 4
    end
    if not out.mode or out.mode == "" then out.mode = "default" end
    return out
end

-- Runtime UI 只需要纯数据配置；不要把 onGameStart 这类 Host 回调函数跨桥传过去。
local function buildRuntimeUIConfig(config)
    config = config or {}
    return {
        debugMode = config.debugMode,
        theme = config.theme,
        allowCreateRoom = config.allowCreateRoom,
        allowQuickMatch = config.allowQuickMatch,
        allowBrowseRooms = config.allowBrowseRooms,
        skipMainView = config.skipMainView,
        matchInfo = config.matchInfo,
        backgroundMatch = config.backgroundMatch,
    }
end
M._buildRuntimeUIConfig = buildRuntimeUIConfig -- 暴露给自测

-- ============================================================================
-- 桥回执 / 状态 / 事件
-- ============================================================================

local function emitResult(reqId, ok, payload)
    payload = payload or {}
    payload.reqId = reqId
    payload.ok = ok and true or false
    emit("result", payload)
end

local function emitImmediateError(reqId, errorCode, message)
    if reqId ~= nil then
        emitResult(reqId, false, { errorCode = errorCode, message = message })
    else
        emit("error", { errorType = "BRIDGE_ACTION", errorCode = errorCode, message = message })
    end
end

local function emitState()
    emit("state", {
        isInRoom = lobbyMgr_:IsInRoom() and true or false,
        isMatching = lobbyMgr_:IsMatching() and true or false,
    })
end

-- 合并桥来的数据字段 + 回执回调，组成 LobbyManager 的 options
local function withResult(reqId, args, extraPayloadFn)
    local opts = {}
    for k, v in pairs(args or {}) do opts[k] = v end
    opts.onSuccess = function(...)
        emitResult(reqId, true, extraPayloadFn and extraPayloadFn(...) or {})
        emitState()
    end
    opts.onError = function(errorCode)
        emitResult(reqId, false, { errorCode = errorCode })
        emitState()
    end
    return opts
end

-- 接桥动作 → LobbyManager；LobbyManager 事件 → 桥
local function attachBridge()
    local function runAction(reqId, action, fn, allowZero)
        local ok, requestId = pcall(fn)
        if not ok then
            local msg = _tr("t_I4sLuHSlHZSRYIDt", tostring(action), tostring(requestId))
            log:Write(LOG_ERROR, msg)
            emitImmediateError(reqId, -10002, msg)
            emitState()
            return
        end
        if requestId == nil or requestId == false
            or (type(requestId) == "number" and requestId < 0)
            or (type(requestId) == "number" and requestId == 0 and not allowZero) then
            local msg = _tr("t_15MqkNEpW14wGpw9UC", tostring(action))
            log:Write(LOG_ERROR, msg)
            emitImmediateError(reqId, -10003, msg)
            emitState()
        end
    end

    lobbyBridge:setCallHandler(function(action, argsJson, _bridgeReqId)
        local a = decode(argsJson)
        local rid = a.__reqId
        a.__reqId = nil
        if action == "requestUIConfig" then
            emit("uiConfig", { config = buildRuntimeUIConfig(config_) })
        elseif action == "startMatch" then
            runAction(rid, action, function()
                return lobbyMgr_:StartMatch(withResult(rid, resolveMatchParams(a)))
            end)
        elseif action == "cancelMatch" then
            lobbyMgr_:CancelMatch(); emitState()
        elseif action == "createRoom" then
            -- 回执带回 roomId（标量），供 Runtime 的 onSuccess(roomId) 切到房间详情屏
            runAction(rid, action, function()
                return lobbyMgr_:CreateRoom(withResult(rid, resolveRoomParams(a), function(roomId) return { roomId = roomId } end))
            end)
        elseif action == "joinRoom" then
            -- roomId 是真·用户输入（必填）：缺失 / 无效时给明确错误，而不是丢通用 -10003
            if not a.roomId or a.roomId == 0 then
                emitImmediateError(rid, -10005, _tr("t_2vVdraaF2jRrQwwT"))
                emitState()
            else
                runAction(rid, action, function()
                    return lobbyMgr_:JoinRoom(withResult(rid, a))
                end, true)
            end
        elseif action == "leaveRoom" then
            runAction(rid, action, function()
                return lobbyMgr_:LeaveRoom(withResult(rid, a))
            end)
        elseif action == "startGame" then
            runAction(rid, action, function()
                return lobbyMgr_:StartGame(withResult(rid, resolveRoomParams(a)))
            end)
        elseif action == "getRoomList" then
            runAction(rid, action, function()
                local params = resolveRoomParams(a)
                -- 建房写入 mode_id，查房过滤读 modes。未传 modes 时用同一个 mode，避免空过滤回空列表。
                if (not params.modes or #params.modes == 0) and params.mode and params.mode ~= "" then
                    params.modes = { params.mode }
                end
                return lobbyMgr_:GetRoomList(withResult(rid, params, function(rooms) return { rooms = rooms } end))
            end)
        elseif action == "getUserNickname" then
            runAction(rid, action, function()
                return lobbyMgr_:GetUserNickname(withResult(rid, a, function(nicknames) return { nicknames = nicknames } end))
            end)
        else
            local msg = _tr("t_S4RXej9IRZ1dSqSY", tostring(action))
            log:Write(LOG_ERROR, msg)
            emitImmediateError(rid, -10004, msg)
        end
    end)

    lobbyMgr_:OnError(function(errorType, errorCode)
        emit("error", { errorType = errorType, errorCode = errorCode })
    end)
    lobbyMgr_:OnMatchFound(function(serverInfo)
        emit("matchFound", { serverInfo = serverInfo }); emitState()
    end)
    lobbyMgr_:OnRoomLeft(function()
        emit("roomLeft", {}); emitState()
    end)
    lobbyMgr_:OnTeamStatusChanged(function(teamStatus)
        emit("teamStatus", { teamStatus = teamStatus })
    end)

    emitState() -- 初始状态推一次
end

-- ============================================================================
-- 门面（main.lua 的调用面）
-- ============================================================================

-- 基础状态 / 兼容入口
function M.IsReady() return lobbyMgr_ ~= nil end

-- 兼容 / 自测逃生口：main.lua 不再直接依赖这个对象。
function M.GetLobbyManager() return lobbyMgr_ end

function M.ConsumeReturningToLobbyFlag()
    if not M.isReturningToLobby_ then return false end
    M.isReturningToLobby_ = false
    return true
end

-- main.lua：连接 / 重连主流程
function M.QueryCanReconnect(callback)
    if not lobbyMgr_ then return false end
    lobbyMgr_:QueryCanReconnect(callback)
    return true
end

function M.ConnectToGame(scene)
    if not lobbyMgr_ then return false end
    return lobbyMgr_:ConnectToGame(scene)
end

function M.ClearMatchFoundHandler()
    if lobbyMgr_ then lobbyMgr_:OnMatchFound(nil) end
end

function M.SetOnGameStarted(callback)
    if lobbyMgr_ then lobbyMgr_:OnGameStarted(callback) end
end

-- main.lua：中途局 / 多开调试
function M.GetProjectId(fallback)
    if not lobbyMgr_ then return fallback end
    local ok, projectId = pcall(function() return lobbyMgr_:GetProjectId() end)
    if ok and projectId and projectId ~= "" then return projectId end
    return fallback
end

function M.SupportsMiddleGame()
    return lobbyMgr_ ~= nil and lobbyMgr_:SupportsMiddleGame()
end

function M.JoinMiddleGame(options)
    if not lobbyMgr_ then return nil end
    return lobbyMgr_:JoinMiddleGame(options)
end

function M.QueryMiddleRoom(options)
    if not lobbyMgr_ then return nil end
    return lobbyMgr_:QueryMiddleRoom(options)
end

function M.GetMultiDebugNum()
    if not lobbyMgr_ then return 0 end
    return lobbyMgr_:GetMultiDebugNum()
end

function M.CreateMultiDebugGame(options)
    if not lobbyMgr_ then return nil end
    return lobbyMgr_:CreateMultiDebugGame(options)
end

-- Runtime UI emit：连服进度（方案 B：Runtime 渲染连服屏）
function M.UpdateServerProgress(progress, status)
    emit("serverProgress", { progress = progress or 0, status = status or "" })
end
function M.SwitchToServerProgressView()
    emit("serverProgress", { progress = 0, status = _tr("t_Ct5iRUWzClnJxieR") })
end

local function dispatchNotification(info)
    local dispatchOk, handled = pcall(SystemNotification.Dispatch, info)
    if dispatchOk then
        return handled == true
    end
    print("[Lobby] SystemNotification dispatch failed: " .. tostring(handled))
    return false
end

-- Host 弹系统提示的统一顺序：
--   1. Dispatch 只传 id（Kicked 自定义原因另传 reason）；
--   2. Runtime handler 未接管：Host SystemDialog 兜底。
local function showHostDialog(options)
    local ok, consumed = pcall(SystemDialog.Show, options)
    if not ok then
        print("[Lobby] Host SystemDialog failed: " .. tostring(consumed))
        -- Host 渲染异常通常是结构性错误，按帧重试不会恢复；日志作为最终降级回执。
        return true
    end
    return consumed == true
end

function M.ShowError(notificationId)
    if dispatchNotification({ id = notificationId }) then
        return true
    end
    local view = SystemNotification.Resolve({ id = notificationId })
    local ok, consumed = pcall(SystemDialog.ShowError, view.message)
    if not ok then
        print("[Lobby] Host SystemDialog.ShowError failed: " .. tostring(consumed))
        return true
    end
    return consumed == true
end

function M.ShowKickedDialog(notificationId, reason)
    local info = { id = notificationId }
    if type(reason) == "string" and reason ~= "" then
        info.reason = reason
    end
    -- 先尝试 Dispatch（大厅/游戏阶段的 handler 可接管）
    if dispatchNotification(info) then
        return true
    end

    -- 旧 OnSystemDialog 已由 Runtime-hide 适配为 SystemNotification handler。
    -- 到这里说明没有旧回调或回调执行失败，直接由 Host 兜底。
    local view = SystemNotification.Resolve(info)
    return showHostDialog({
        title = view.title,
        message = info.reason or view.message,
    })
end

function M.ShowDialog(notificationId, onClose, reason)
    local info = {
        id = notificationId,
        exitOnClose = onClose ~= nil,
    }
    if type(reason) == "string" and reason ~= "" then
        info.reason = reason
    end
    if dispatchNotification(info) then
        return true
    end

    local view = SystemNotification.Resolve(info)
    return showHostDialog({
        title = view.title,
        message = info.reason or view.message,
        onClose = onClose,
    })
end

-- UI 生命周期由脚本切换治理（§5.5.C），此处 noop
function M.SetEnabled(_enabled) end
function M.Hide() end

-- ReturnToLobby：游戏结束返回大厅（裸 lobby + network；Host 本地）
local function installReturnToLobbyHandler()
    if returnHandlerInstalled_ then return end
    returnHandlerInstalled_ = true
    SubscribeToEvent("ReturnToLobby", function()
        local network = GetNetwork()
        local serverConnection = network and network:GetServerConnection()

        -- 该标志只用于抑制 PlayerLeaving 引发的那次断线的重连，消费方是 ServerDisconnected 里的
        -- ConsumeReturningToLobbyFlag。已断线时没有那次断线可抑制，置了便无人消费，会漏到下一局
        -- 把真实掉线误判成主动返回大厅、静默跳过重连。
        M.isReturningToLobby_ = serverConnection ~= nil

        if lobby and lobby.CancelAllReconnects then
            lobby:CancelAllReconnects()
        end

        if serverConnection then
            serverConnection:SendRemoteEvent("PlayerLeaving", true, VariantMap())
        end

        -- 后台匹配：发 PlayerLeaving 后立即重新匹配并切回游戏脚本
        if config_ and config_.backgroundMatch then
            M.StartQuickMatch()
            -- 主动返回大厅后重新匹配是新会话，不是重连；此刻匹配未返回，
            -- SessionId 必然为空（判断重连请用 IsReconnect）
            local switchData = VariantMap()
            switchData["IsReconnect"] = false
            switchData["SessionId"] = ""
            SendEvent("RequestSwitchToGameScript", switchData)
            return
        end

        -- 普通模式：切回大厅锁死引导（C++ SwitchScript 重建 Runtime VM + 跑其全局 Start → 重走引导选入口、重载大厅）
        local switchEventData = VariantMap()
        switchEventData["ScriptPath"] = Variant("urhox-libs/GameLobby/Runtime-hide/LobbyBootstrap.lua")
        SendEvent("RequestSwitchScript", switchEventData)
    end)
end

-- Show：建 mgr + 挂桥 + 存 config + 接连服回调
function M.Show(config)
    config_ = config or {}

    if not lobbyMgr_ then
        lobbyMgr_ = LobbyManager.new({ debugMode = config_.debugMode })
        attachBridge()
    end

    -- 连服触发：任何 onGameStarted → main 的 onGameStart（→ ConnectToServer，幂等）
    if config_.onGameStart then
        lobbyMgr_:OnGameStarted(config_.onGameStart)
    end

    installReturnToLobbyHandler()
end

-- ============================================================================
-- 后台匹配（含自动重试，属于 Host 侧控制流程）
-- ============================================================================

function M.StartQuickMatch()
    if not lobbyMgr_ then
        log:Write(LOG_ERROR, "[LobbyControl] LobbyManager not initialized")
        return false
    end
    local config = config_ or {}

    if backgroundMatchState.isMatching then
        log:Write(LOG_INFO, "[LobbyControl] Background match already in progress")
        return true
    end
    local generation = nextBackgroundMatchGeneration()
    backgroundMatchState.retryCount = 0
    backgroundMatchState.isMatching = true

    local matchMaxPlayers = config.maxPlayers
    if not matchMaxPlayers or matchMaxPlayers <= 0 then
        local fromMgr = lobbyMgr_:GetMaxPlayers()
        matchMaxPlayers = (fromMgr and fromMgr > 0) and fromMgr or 4
    end

    -- mapName 解析（拆 state 后由 Host 侧自解析；config 未必带 mapName）：config → GetProjectId → DefaultMap
    local mapName = config.mapName
    if not mapName or mapName == "" then
        local okId, id = pcall(function() return lobbyMgr_:GetProjectId() end)
        if okId and id and id ~= "" then mapName = id end
    end
    if not mapName or mapName == "" then mapName = "DefaultMap" end

    local mp = { max_players = matchMaxPlayers, match_info = config.matchInfo }
    local params = buildMatchParams(mp, projectVersion(), { mapName = mapName, mode = config.mode })

    local function delayedCall(delay, callback)
        local elapsed = 0
        local fired = false
        cancelBackgroundRetryTimer()
        local token = backgroundMatchState.retryTimerToken
        backgroundMatchState.retryTimerNode = Node()
        backgroundMatchState.retryTimerObject = backgroundMatchState.retryTimerNode:CreateScriptObject("LuaScriptObject")
        backgroundMatchState.retryTimerObject:SubscribeToEvent("Update", function(self, eventType, eventData)
            if fired or token ~= backgroundMatchState.retryTimerToken then return end
            elapsed = elapsed + eventData["TimeStep"]:GetFloat()
            if elapsed >= delay then
                fired = true
                cancelBackgroundRetryTimer()
                if isBackgroundMatchGenerationActive(generation) then
                    callback()
                end
            end
        end)
    end

    local doStartMatch, createRoomAndMatch, doStartMatchWithRetry

    local function retryMatch()
        if not isBackgroundMatchGenerationActive(generation) then return end
        backgroundMatchState.retryCount = backgroundMatchState.retryCount + 1
        if backgroundMatchState.retryCount > backgroundMatchState.maxRetries then
            log:Write(LOG_WARNING, "[LobbyControl] Background match failed after " .. backgroundMatchState.maxRetries .. " retries, giving up")
            backgroundMatchState.isMatching = false
            return
        end
        log:Write(LOG_INFO, "[LobbyControl] Background match retry " .. backgroundMatchState.retryCount .. "/" .. backgroundMatchState.maxRetries)
        delayedCall(backgroundMatchState.retryDelay, function() doStartMatchWithRetry() end)
    end

    doStartMatchWithRetry = function()
        if not isBackgroundMatchGenerationActive(generation) then return end
        if lobbyMgr_:IsInRoom() then
            lobbyMgr_:LeaveRoom({
                onSuccess = function()
                    if isBackgroundMatchGenerationActive(generation) then createRoomAndMatch() end
                end,
                onError = function()
                    if isBackgroundMatchGenerationActive(generation) then createRoomAndMatch() end
                end,
            })
        else
            createRoomAndMatch()
        end
    end

    createRoomAndMatch = function()
        if not isBackgroundMatchGenerationActive(generation) then return end
        lobbyMgr_:CreateRoom({
            mapName = mapName,
            maxPlayers = matchMaxPlayers,
            mode = config.mode,
            onSuccess = function(_roomId)
                if isBackgroundMatchGenerationActive(generation) then doStartMatch() end
            end,
            onError = function(_errorCode)
                if isBackgroundMatchGenerationActive(generation) then retryMatch() end
            end,
        })
    end

    doStartMatch = function()
        if not isBackgroundMatchGenerationActive(generation) then return end
        lobbyMgr_:StartMatch({
            mapName = params.mapName,
            mode = params.mode,
            matchInfo = params.matchInfo,
            onMatchFound = function(serverInfo)
                if not isBackgroundMatchGenerationActive(generation) then return end
                backgroundMatchState.isMatching = false
                backgroundMatchState.retryCount = 0
                if config.onGameStart then config.onGameStart(serverInfo) end
            end,
            onError = function(errorCode)
                if not isBackgroundMatchGenerationActive(generation) then return end
                -- 封禁是终态，重试只会拿到同一个码
                if errorCode == M.MATCH_ERROR_PLAYER_BANNED then
                    log:Write(LOG_WARNING, "[LobbyControl] Background match blocked by player ban, stop retrying")
                    backgroundMatchState.isMatching = false
                    return
                end
                retryMatch()
            end,
        })
    end

    if not lobbyMgr_:IsInRoom() then
        createRoomAndMatch()
    else
        doStartMatch()
    end
    return true
end

function M.RestartBackgroundMatch()
    nextBackgroundMatchGeneration()
    backgroundMatchState.isMatching = false
    backgroundMatchState.retryCount = 0
    cancelBackgroundRetryTimer()
    M.StartQuickMatch()
end

return M
