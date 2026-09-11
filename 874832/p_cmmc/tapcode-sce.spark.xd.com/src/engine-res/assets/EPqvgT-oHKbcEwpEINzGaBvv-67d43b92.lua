--[[
LobbyManager.lua - 游戏大厅管理器

提供开箱即用的游戏大厅功能，包括房间管理、匹配系统、游戏启动等。
设计原则：AI Agent 友好，最小化配置，最大化易用性。

用法示例:
    local LobbyManager = require("urhox-libs.Lobby.LobbyManager")

    -- 初始化大厅管理器
    local lobbyMgr = LobbyManager.new()

    -- 创建房间
    lobbyMgr:CreateRoom({
        mapName = "BattleArena",
        maxPlayers = 4,
        mode = "pvp",
        onSuccess = function(roomId)
            print("Room created: " .. roomId)
        end,
        onError = function(errorCode)
            print("Failed to create room: " .. errorCode)
        end
    })

    -- 开始匹配
    lobbyMgr:StartMatch({
        mapName = "BattleArena",
        mode = "ranked",
        onMatchFound = function(serverInfo)
            print("Match found! Connecting to server...")
            lobbyMgr:ConnectToGame()
        end
    })
]]

local LobbyManager = {}
LobbyManager.__index = LobbyManager

-- ============================================================================
-- 常量定义
-- ============================================================================

-- 响应类型（与 C++ LobbyResponseType 对应）
local ResponseType = {
    CREATE_ROOM = 1,
    JOIN_ROOM = 2,
    LEAVE_ROOM = 3,
    START_GAME = 4,
    ROOM_LIST = 5,
    TEAM_STATUS = 6,      -- 房间玩家列表更新
    PLAYER_JOIN = 7,      -- 有玩家加入房间
    PLAYER_LEAVE = 8,     -- 有玩家离开房间
    MASTER_CHANGED = 9,   -- 房主变更
    KICKED = 10,          -- 被踢出房间/后台
    CANCEL_MATCH = 11,    -- 取消匹配响应
    TEAM_INVITED = 12,    -- 收到房间邀请
    MATCH_STATUS_CHANGED = 13,  -- 匹配状态变更通知
    MIDDLE_JOIN = 14,           -- 中途局加入响应
    QUICK_QUERY_MIDDLE_ROOM = 15, -- 快速查询中途局房间响应
}

-- 匹配事件类型（与 C++ MatchEvent 对应）
local MatchEvent = {
    MATCH_PENDING = 0,
    MATCH_START = 1,
    MATCH_SUCCESS = 2,
    MATCH_CANCELED = 3,
    MATCH_FAILED = 4,
}

-- 默认配置
local DEFAULT_CONFIG = {
    autoReconnect = false,          -- 断线后自动重连
    reconnectAttempts = 3,          -- 重连尝试次数
    reconnectDelay = 2000,          -- 重连延迟（毫秒）
    debugMode = false,              -- 调试模式
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

local function Log(msg, level)
    level = level or "INFO"
    print(string.format("[LobbyManager][%s] %s", level, msg))
end

local function LogDebug(msg, debugMode)
    if debugMode then
        Log(msg, "DEBUG")
    end
end

local function LogError(msg)
    Log(msg, "ERROR")
end

--- 获取项目版本号
--- @return string 版本号，未找到返回空字符串
local function getProjectVersion()
    -- 1. 优先使用新 API（新二进制）
    if GetProjectVersion then
        local ver = GetProjectVersion()
        if ver and ver ~= "" then
            return ver
        end
    end
    -- 2. 回退到命令行参数（兼容旧二进制）
    if GetArguments then
        local args = GetArguments()
        for i, arg in ipairs(args) do
            if arg == "-game_version" or arg == "--game_version" then
                if args[i + 1] then
                    return args[i + 1]
                end
            elseif string.sub(arg, 1, 14) == "-game_version=" then
                return string.sub(arg, 15)
            elseif string.sub(arg, 1, 15) == "--game_version=" then
                return string.sub(arg, 16)
            end
        end
    end
    return ""
end

--- 获取修订标签（i18n/intl 等）
--- 优先 -game_revision=<tag>，否则若 -intl 存在则映射为 "intl"
--- @return string 修订标签，未启用返回空字符串
local function getRevision()
    if GetAppArgv then
        local rev = GetAppArgv("game_revision")
        if rev and rev ~= "" then
            return rev
        end
    end
    if HasAppArg and HasAppArg("intl") then
        return "intl"
    end
    return ""
end

--- 获取 TapMaker 环境字符串
--- @return string 环境名 (preview/share)，未找到返回空字符串
local function getTapMakerEnvString()
    if GetTapMakerEnvString then
        local env = GetTapMakerEnvString()
        if env and env ~= "" then
            return env
        end
    end
    return ""
end

--- 获取当前运行环境对应的 tag 值
--- preview → "debug", share → "test", -tag=xxx → xxx, 其余 → "formal"
--- @return string tag
local function getGameEnvTag()
    local env = getTapMakerEnvString()
    if env == "preview" then return "debug" end
    if env == "share" then return "test" end
    if GetAppArgv then
        local tag = GetAppArgv("tag")
        if tag and tag ~= "" then
            return tag
        end
    end
    return "formal"
end

--- 构建 modeArgs（MsgPack 编码），自动带入 project_version / revision / tapmaker_env
--- @param modeArgs string|table|nil 用户传入的 modeArgs（MsgPack string 或 table）
--- @return string MsgPack 编码后的 modeArgs
local function buildModeArgs(modeArgs)
    local t = modeArgs or {}
    if type(t) == "string" then
        if t ~= "" then
            local unpacked = cmsg_pack.unpack(t)
            if unpacked then
                t = unpacked
            else
                LogError("Failed to unpack modeArgs, using empty table")
                t = {}
            end
        else
            t = {}
        end
    end

    local projectVersion = getProjectVersion()
    if projectVersion ~= "" then
        t.project_version = projectVersion
    end

    local revision = getRevision()
    if revision ~= "" then
        t.project_revision = revision
    end

    local tapMakerEnv = getTapMakerEnvString()
    if tapMakerEnv ~= "" then
        t.tapmaker_env = tapMakerEnv
    end

    return cmsg_pack.pack(t)
end

--- Simple JSON encoder for Lua tables (supports basic types)
--- @param value any Value to encode
--- @return string JSON string
local function jsonEncode(value)
    local valueType = type(value)

    if value == nil then
        return "null"
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "number" then
        return tostring(value)
    elseif valueType == "string" then
        -- Escape special characters
        local escaped = value:gsub('\\', '\\\\')
                             :gsub('"', '\\"')
                             :gsub('\n', '\\n')
                             :gsub('\r', '\\r')
                             :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif valueType == "table" then
        -- Check if it's an array (sequential integer keys starting from 1)
        local isArray = true
        local maxIndex = 0
        for k, _ in pairs(value) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArray = false
                break
            end
            if k > maxIndex then
                maxIndex = k
            end
        end
        -- Also check for holes in the array
        if isArray and maxIndex > 0 then
            for i = 1, maxIndex do
                if value[i] == nil then
                    isArray = false
                    break
                end
            end
        end

        if isArray and maxIndex > 0 then
            -- Encode as array
            local parts = {}
            for i = 1, maxIndex do
                parts[i] = jsonEncode(value[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- Encode as object
            local parts = {}
            for k, v in pairs(value) do
                local keyStr = type(k) == "string" and k or tostring(k)
                table.insert(parts, '"' .. keyStr .. '":' .. jsonEncode(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        -- Unsupported type, return null
        return "null"
    end
end

-- ============================================================================
-- LobbyManager 类实现
-- ============================================================================

--- 创建新的 LobbyManager 实例
--- @param config table 配置选项
--- @return LobbyManager
function LobbyManager.new(config)
    local self = setmetatable({}, LobbyManager)

    -- 配置
    self.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        self.config[k] = v
    end
    if config then
        for k, v in pairs(config) do
            self.config[k] = v
        end
    end

    -- 状态
    self.currentRoomId = nil
    self.currentRoomInfo = nil
    self.isInRoom = false
    self.isMatching = false
    self.gameServerInfo = nil

    -- 回调映射（requestId -> callbacks）
    self.pendingRequests = {}
    self.nextRequestId = 1

    -- 全局回调
    self.onRoomCreated = nil
    self.onRoomJoined = nil
    self.onRoomLeft = nil
    self.onMatchFound = nil
    self.onMatchFailed = nil
    self.onGameStarted = nil
    self.onError = nil

    -- 多开调试信息
    self.pendingMultiDebugPlayerCount = 0  -- CreateMultiDebugGame 时保存的 playerCount

    -- 订阅事件
    self:_subscribeEvents()

    LogDebug("LobbyManager initialized", self.config.debugMode)

    return self
end

--- 订阅 Lobby 事件
function LobbyManager:_subscribeEvents()
    -- 订阅 Lobby 响应事件
    SubscribeToEvent("LobbyResponse", function(eventType, eventData)
        self:_handleLobbyResponse(eventData)
    end)

    -- 订阅游戏开始通知事件
    SubscribeToEvent("NotifyGameStartEvent", function(eventType, eventData)
        self:_handleGameStartNotification(eventData)
    end)

    -- 订阅多开调试游戏创建事件（ResponseCreateGame）
    SubscribeToEvent("MultiDebugGameCreatedEvent", function(eventType, eventData)
        self:_handleMultiDebugGameCreated(eventData)
    end)

    -- UserNicknameResponse event is handled by _G.GetUserNickname (UserInfo.lua)
end

--- 处理 Lobby 响应
function LobbyManager:_handleLobbyResponse(eventData)
    local respType = eventData["Type"]:GetInt()
    local requestId = eventData["RequestId"]:GetInt()
    local success = eventData["Success"]:GetBool()
    local errorCode = eventData["ErrorCode"]:GetInt()
    local data = eventData["Data"]:GetString()

    LogDebug(string.format("Response: type=%d, requestId=%d, success=%s, data=%s",
        respType, requestId, tostring(success), data), self.config.debugMode)

    -- 查找对应的回调
    local callbacks = self.pendingRequests[requestId]

    if respType == ResponseType.CREATE_ROOM then
        if success then
            self.currentRoomId = tonumber(data) or 0
            self.isInRoom = true

            if callbacks and callbacks.onSuccess then
                callbacks.onSuccess(self.currentRoomId)
            end
            if self.onRoomCreated then
                self.onRoomCreated(self.currentRoomId)
            end
        else
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
            if self.onError then
                self.onError("CREATE_ROOM", errorCode)
            end
        end
    elseif respType == ResponseType.JOIN_ROOM then
        if success then
            self.isInRoom = true

            if callbacks and callbacks.onSuccess then
                callbacks.onSuccess(data)
            end
            if self.onRoomJoined then
                self.onRoomJoined(data)
            end
        else
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
            if self.onError then
                self.onError("JOIN_ROOM", errorCode)
            end
        end
    elseif respType == ResponseType.LEAVE_ROOM then
        if success then
            self.currentRoomId = nil
            self.isInRoom = false
            self.cachedTeamStatus = nil  -- 清除缓存

            if callbacks and callbacks.onSuccess then
                callbacks.onSuccess()
            end
            if self.onRoomLeft then
                self.onRoomLeft()
            end
        else
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
        end
    elseif respType == ResponseType.ROOM_LIST then
        if success then
            -- data 包含房间列表（JSON 或其他格式）
            if callbacks and callbacks.onSuccess then
                callbacks.onSuccess(data)
            end
        else
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
        end
    elseif respType == ResponseType.START_GAME then
        print("[LobbyManager] START_GAME response: success=" .. tostring(success) .. ", errorCode=" .. tostring(errorCode))
        if success then
            -- 匹配/游戏启动请求被服务器接受，等待 NotifyGameStartEvent
            LogDebug("Match/Game start request accepted, waiting for server info...", self.config.debugMode)
            print("[LobbyManager] Waiting for NotifyGameStartEvent...")
        else
            print("[LobbyManager] START_GAME failed with errorCode: " .. tostring(errorCode))
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
            if self.onError then
                self.onError("START_GAME", errorCode)
            end
        end
    elseif respType == ResponseType.TEAM_STATUS then
        -- 房间玩家列表更新（服务器主动推送）
        if success then
            print("[LobbyManager] TEAM_STATUS update received, data=" .. tostring(data):sub(1, 100))
            local teamStatus = nil
            if data and data ~= "" then
                local ok, parsed = pcall(function()
                    return cjson.decode(data)
                end)
                print("[LobbyManager] JSON parse result: ok=" .. tostring(ok) .. ", parsed=" .. tostring(parsed))
                if ok and parsed then
                    teamStatus = parsed
                    print("[LobbyManager] Team status: teamId=" .. tostring(teamStatus.teamId) .. ", players=" .. tostring(#(teamStatus.players or {})))
                end
            else
                print("[LobbyManager] TEAM_STATUS data is empty or nil")
            end
            -- 缓存 teamStatus
            self.cachedTeamStatus = teamStatus
            -- 触发回调
            if self.onTeamStatusChanged then
                self.onTeamStatusChanged(teamStatus)
            end
        end
    elseif respType == ResponseType.PLAYER_JOIN then
        -- 有玩家加入房间
        local userId = tonumber(data) or 0
        print("[LobbyManager] PLAYER_JOIN: userId=" .. tostring(userId))
        if self.onPlayerJoin then
            self.onPlayerJoin(userId)
        end
    elseif respType == ResponseType.PLAYER_LEAVE then
        -- 有玩家离开房间
        local userId = tonumber(data) or 0
        print("[LobbyManager] PLAYER_LEAVE: userId=" .. tostring(userId))
        if self.onPlayerLeave then
            self.onPlayerLeave(userId)
        end

    elseif respType == ResponseType.MASTER_CHANGED then
        -- 房主变更
        if success then
            local masterInfo = nil
            if data and data ~= "" then
                local ok, parsed = pcall(function()
                    return cjson.decode(data)
                end)
                if ok and parsed then
                    masterInfo = parsed
                    print("[LobbyManager] MASTER_CHANGED: oldMaster=" .. tostring(masterInfo.oldMasterId) ..
                        ", newMaster=" .. tostring(masterInfo.newMasterId))
                end
            end
            if self.onMasterChanged then
                self.onMasterChanged(masterInfo)
            end
        end

    elseif respType == ResponseType.KICKED then
        -- 被踢出房间/后台
        local kickInfo = nil
        if data and data ~= "" then
            local ok, parsed = pcall(function()
                return cjson.decode(data)
            end)
            if ok and parsed then
                kickInfo = parsed
                print("[LobbyManager] KICKED: canReconnect=" .. tostring(kickInfo.canReconnect))
            end
        end
        self.currentRoomId = nil
        self.isInRoom = false
        self.cachedTeamStatus = nil
        if self.onKicked then
            self.onKicked(kickInfo)
        end

    elseif respType == ResponseType.CANCEL_MATCH then
        -- 取消匹配响应
        print("[LobbyManager] CANCEL_MATCH: success=" .. tostring(success) .. ", errorCode=" .. tostring(errorCode))
        self.isMatching = false
        if success then
            if callbacks and callbacks.onSuccess then
                callbacks.onSuccess()
            end
            if self.onMatchCanceled then
                self.onMatchCanceled()
            end
        else
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
            if self.onError then
                self.onError("CANCEL_MATCH", errorCode)
            end
        end

    elseif respType == ResponseType.TEAM_INVITED then
        -- 收到房间邀请
        if success then
            local inviteInfo = nil
            if data and data ~= "" then
                local ok, parsed = pcall(function()
                    return cjson.decode(data)
                end)
                if ok and parsed then
                    inviteInfo = parsed
                    print("[LobbyManager] TEAM_INVITED: fromUserId=" .. tostring(inviteInfo.fromUserId) ..
                        ", inviteKey=" .. tostring(inviteInfo.inviteKey))
                end
            end
            if self.onTeamInvited then
                self.onTeamInvited(inviteInfo)
            end
        end

    elseif respType == ResponseType.MATCH_STATUS_CHANGED then
        -- 匹配状态变更通知
        local matchEvent = nil
        local matchErrorCode = errorCode
        if data and data ~= "" then
            local ok, parsed = pcall(function()
                return cjson.decode(data)
            end)
            if ok and parsed then
                matchEvent = parsed.match_event
                if parsed.error_code then
                    matchErrorCode = parsed.error_code
                end
            end
        end
        print("[LobbyManager] MATCH_STATUS_CHANGED: match_event=" .. tostring(matchEvent) .. ", error_code=" .. tostring(matchErrorCode))

        -- match_event: 0=PENDING, 1=START, 2=SUCCESS, 3=CANCELED, 4=FAILED
        if matchEvent == MatchEvent.MATCH_FAILED or matchEvent == MatchEvent.MATCH_CANCELED then
            self.isMatching = false
            -- 触发匹配失败回调
            if self.onMatchFailed then
                self.onMatchFailed(matchEvent, matchErrorCode)
            end
            if self.onError then
                self.onError("MATCH_STATUS_CHANGED", matchErrorCode)
            end
        elseif matchEvent == MatchEvent.MATCH_SUCCESS then
            -- 匹配成功，等待 NotifyGameStart
            print("[LobbyManager] Match success, waiting for game start...")
        end

    elseif respType == ResponseType.MIDDLE_JOIN then
        print("[LobbyManager] MIDDLE_JOIN: success=" .. tostring(success) .. ", errorCode=" .. tostring(errorCode) .. ", middleKey=" .. tostring(data))
        if success then
            LogDebug("Middle join request accepted, waiting for NotifyGameStartEvent...", self.config.debugMode)
            if callbacks and callbacks.onSuccess then
                callbacks.onSuccess(data)
            end
            if self.onMiddleJoinAccepted then
                self.onMiddleJoinAccepted(data)
            end
        else
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
            if self.onError then
                self.onError("MIDDLE_JOIN", errorCode)
            end
        end

    elseif respType == ResponseType.QUICK_QUERY_MIDDLE_ROOM then
        print("[LobbyManager] QUICK_QUERY_MIDDLE_ROOM: success=" .. tostring(success) .. ", errorCode=" .. tostring(errorCode) .. ", middleKey=" .. tostring(data))
        if success then
            if callbacks and callbacks.onSuccess then
                callbacks.onSuccess(data)
            end
        else
            if callbacks and callbacks.onError then
                callbacks.onError(errorCode)
            end
            if self.onError then
                self.onError("QUICK_QUERY_MIDDLE_ROOM", errorCode)
            end
        end
    end

    -- 清理已处理的回调
    if callbacks then
        self.pendingRequests[requestId] = nil
    end
end

--- 处理多开调试游戏创建事件（ResponseCreateGame）
--- 主端收到此事件后，应通知父页面打开调试客户端
function LobbyManager:_handleMultiDebugGameCreated(eventData)
    local success = eventData["Success"]:GetBool()
    local errorCode = eventData["ErrorCode"]:GetInt()

    if success then
        local podIp = eventData["PodIP"]:GetString()
        local serverPort = eventData["ServerPort"]:GetInt()
        local wsPort = eventData["WSPort"]:GetInt()
        local loginKey = eventData["LoginKey"]:GetString()

        Log(string.format("[MultiDebug] Game created: podIp=%s, serverPort=%d, wsPort=%d",
            podIp, serverPort, wsPort))

        -- 保存调试客户端用的连接信息
        self.debugConnectInfo = {
            pod_ip = podIp,
            server_port = serverPort,
            ws_port = wsPort,
            login_key = loginKey
        }

        -- 通知父页面打开调试窗口（playerCount - 1 个额外窗口）
        local playerCount = self.pendingMultiDebugPlayerCount or 0
        if playerCount > 1 then
            local extraWindows = playerCount - 1
            Log("[MultiDebug] Notifying parent to open " .. extraWindows .. " debug windows")
            local connectInfoJson = jsonEncode(self.debugConnectInfo)
            if lobby and lobby.NotifyMultiDebugCreatedToJS then
                lobby:NotifyMultiDebugCreatedToJS(connectInfoJson, extraWindows)
            end
        end

        -- 触发回调
        if self.onMultiDebugGameCreated then
            self.onMultiDebugGameCreated(self.debugConnectInfo)
        end
    else
        LogError("[MultiDebug] Game creation failed, errorCode=" .. tostring(errorCode))
        if self.onError then
            self.onError("CREATE_GAME", errorCode)
        end
    end
end


--- 处理游戏开始通知
function LobbyManager:_handleGameStartNotification(eventData)
    local success = eventData["Success"]:GetBool()
    local errorCode = eventData["ErrorCode"]:GetInt()
    local serverIP = eventData["ServerIP"]:GetString()
    local serverPort = eventData["ServerPort"]:GetInt()
    local authKey = eventData["AuthKey"]:GetString()
    local sessionId = eventData["SessionId"]:GetInt64()
    local mapName = eventData["MapName"]:GetString()

    if success then
        self.gameServerInfo = {
            ip = serverIP,
            port = serverPort,
            authKey = authKey,
            sessionId = sessionId,
            mapName = mapName,
        }

        self.isMatching = false

        LogDebug(string.format("Game server ready: %s:%d, session=%d",
            serverIP, serverPort, sessionId), self.config.debugMode)

        if self.onMatchFound then
            self.onMatchFound(self.gameServerInfo)
        end
        if self.onGameStarted then
            self.onGameStarted(self.gameServerInfo)
        end
    else
        LogError("Game start notification failed: " .. errorCode)
        if self.onError then
            self.onError("GAME_START", errorCode)
        end
    end
end

--- 注册一个待处理的请求
function LobbyManager:_registerRequest(requestId, callbacks)
    if requestId and requestId > 0 then
        self.pendingRequests[requestId] = callbacks
    end
end

-- ============================================================================
-- 公共 API - 房间管理
-- ============================================================================

--- 创建房间
--- @param options table 房间配置
---   - mapName: string 地图名称（必填）
---   - maxPlayers: number 最大玩家数（默认4）
---   - mode: string 游戏模式（如 "pvp", "coop"）
---   - isPrivate: boolean 是否私密房间（默认false）
---   - password: string 房间密码（可选）
---   - onSuccess: function(roomId) 成功回调
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:CreateRoom(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    local mapName = options.mapName or ""
    if mapName == "" then
        LogError("CreateRoom: mapName is required")
        return -1
    end

    local maxPlayers = options.maxPlayers or 4
    local mode = options.mode or "default"
    local isPrivate = options.isPrivate or false
    local password = options.password or ""

    -- 构建 roomData（使用 MsgPack 编码）
    local roomDataTable = {
        map_name = mapName,
        mode_id = mode
    }
    local roomData = cmsg_pack.pack(roomDataTable)

    LogDebug(string.format("Creating room: map=%s, maxPlayers=%d, mode=%s",
        mapName, maxPlayers, mode), self.config.debugMode)

    local requestId = lobby:CreateRoom({
        maxPlayers = maxPlayers,
        roomData = roomData,
        isPrivate = isPrivate,
        password = password
    })

    self:_registerRequest(requestId, {
        onSuccess = options.onSuccess,
        onError = options.onError
    })

    return requestId
end

--- 加入房间
--- @param options table 加入配置
---   - roomId: number 房间ID（必填）
---   - ownerId: number 房主ID（可选）
---   - password: string 密码（可选）
---   - onSuccess: function(data) 成功回调
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:JoinRoom(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    local roomId = options.roomId
    if not roomId or roomId == 0 then
        LogError("JoinRoom: roomId is required")
        return -1
    end

    -- If already in a room, leave first then join the new one
    if self.isInRoom then
        LogDebug(string.format("Already in room, leaving before joining roomId=%d", roomId),
            self.config.debugMode)
        self:LeaveRoom({
            onSuccess = function()
                LogDebug("Left previous room, now joining new room", self.config.debugMode)
                self:_doJoinRoom(options)
            end,
            onError = function(errorCode)
                LogError(string.format("Failed to leave room (error=%d), joining anyway", errorCode))
                self:_doJoinRoom(options)
            end
        })
        return 0
    end

    return self:_doJoinRoom(options)
end

function LobbyManager:_doJoinRoom(options)
    local roomId = options.roomId
    local ownerId = options.ownerId or 0
    local password = options.password or ""

    LogDebug(string.format("Joining room: roomId=%d, ownerId=%d", roomId, ownerId),
        self.config.debugMode)

    local requestId = lobby:JoinRoom({
        roomId = roomId,
        ownerId = ownerId,
        password = password
    })

    self:_registerRequest(requestId, {
        onSuccess = options.onSuccess,
        onError = options.onError
    })

    return requestId
end

--- 离开房间
--- @param options table 回调配置（可选）
---   - onSuccess: function() 成功回调
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:LeaveRoom(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    options = options or {}

    LogDebug("Leaving room", self.config.debugMode)

    local requestId = lobby:LeaveRoom()

    self:_registerRequest(requestId, {
        onSuccess = options.onSuccess,
        onError = options.onError
    })

    return requestId
end

--- 获取房间列表
--- @param options table 查询配置
---   - mapName: string 过滤地图名称（可选）
---   - modes: table 过滤模式列表（可选）
---   - limit: number 返回数量限制（默认10）
---   - includePrivate: boolean 包含私密房间（默认false）
---   - onSuccess: function(data) 成功回调
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:GetRoomList(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    options = options or {}
    
    -- Debug: print modes
    local modesStr = ""
    if options.modes then
        for i, m in ipairs(options.modes) do
            if i > 1 then modesStr = modesStr .. ", " end
            modesStr = modesStr .. tostring(m)
        end
    end
    print("[LobbyManager] GetRoomList: mapName=" .. tostring(options.mapName) .. ", modes=[" .. modesStr .. "], limit=" .. tostring(options.limit))

    local requestId = lobby:GetRoomList({
        mapName = options.mapName or "",
        modes = options.modes or {},
        limit = options.limit or 10,
        includePrivate = options.includePrivate or false
    })

    self:_registerRequest(requestId, {
        onSuccess = options.onSuccess,
        onError = options.onError
    })

    return requestId
end

-- ============================================================================
-- 公共 API - 匹配系统
-- ============================================================================

--- 开始匹配
--- @param options table 匹配配置
---   - mapName: string 地图名称（必填）
---   - mode: string 游戏模式（可选）
---   - matchInfo: table 匹配信息（可选，会转为JSON）
---   - modeArgs: table 模式参数（可选，会自动带入 project_version）
---   - onMatchFound: function(serverInfo) 匹配成功回调
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:StartMatch(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    local mapName = options.mapName or ""
    if mapName == "" then
        LogError("StartMatch: mapName is required")
        return -1
    end

    local mode = options.mode or "default"

    -- 构建 matchInfo（JSON 格式）
    local matchInfo = options.matchInfo or {}
    if type(matchInfo) == "table" then
        matchInfo.mode = mode
        matchInfo = jsonEncode(matchInfo)
    end

    local modeArgs = buildModeArgs(options.modeArgs)

    LogDebug(string.format("Starting match: map=%s, mode=%s",
        mapName, mode), self.config.debugMode)

    if common and common.send_user_stat then
        common.send_user_stat("StartMatch", mapName)
    end

    self.isMatching = true

    local requestId = lobby:FindMatch({
        mapName = mapName,
        matchInfo = matchInfo,
        modeArgs = modeArgs,
        tag = getGameEnvTag(),
    })

    -- 保存匹配回调（游戏开始通知时触发）
    if options.onMatchFound then
        self.onMatchFound = options.onMatchFound
    end

    self:_registerRequest(requestId, {
        onError = options.onError
    })

    return requestId
end

--- 取消匹配
--- @return number requestId
function LobbyManager:CancelMatch()
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    LogDebug("Canceling match", self.config.debugMode)

    self.isMatching = false

    return lobby:CancelMatch()
end

-- LobbyProto 兜底：用 Lua protobuf 直接发 RequestGameCanReconnect 协议
-- 适用于旧二进制没有 lobby:QueryCanReconnect C++ 接口的情况
function LobbyManager:queryCanReconnectViaProto_(callback)
    local ok, LobbyProto = pcall(require, "urhox-libs.Lobby.LobbyProto")
    if not ok or not LobbyProto then
        LogDebug("LobbyProto not available, assuming reconnectable (fallback)", self.config.debugMode)
        if callback then callback({}) end
        return
    end

    -- 确保 LobbyProto 已初始化（幂等）
    if not LobbyProto.IsReady() then
        if not LobbyProto.Init() then
            LogDebug("LobbyProto init failed, assuming reconnectable (fallback)", self.config.debugMode)
            if callback then callback({}) end
            return
        end
    end

    -- 注册 0x3060 消息类型（幂等）
    LobbyProto.AddMessageType(0x3060, "CEProto.TSLobbyServer.ResponseGameCanReconnect")

    -- 注册响应处理器（一次性，收到后立即取消注册）
    LobbyProto.RegisterHandler(0x3060, function(messageId, msg)
        LobbyProto.UnregisterHandler(0x3060)

        if not msg or msg.error_code ~= 0 or not msg.info_list or #msg.info_list == 0 then
            LogDebug("LobbyProto: no reconnectable sessions", self.config.debugMode)
            if callback then callback(nil) end
        else
            -- 转换字段名与 C++ API 返回格式一致
            local sessions = {}
            for i, info in ipairs(msg.info_list) do
                sessions[i] = {
                    mapName = info.map_name or "",
                    mapType = info.map_kind or 0,
                    sessionId = info.session_id or 0,
                    tag = info.tag or "",
                }
            end
            LogDebug("LobbyProto: found " .. #sessions .. " reconnectable session(s)", self.config.debugMode)
            if callback then callback(sessions) end
        end
    end)

    -- 发送请求（RequestGameCanReconnect 是空消息体）
    local requestId = LobbyProto.EncodeAndSend(0x3060, "CEProto.TSLobbyServer.RequestGameCanReconnect", {})
    if requestId < 0 then
        LobbyProto.UnregisterHandler(0x3060)
        LogDebug("LobbyProto: send failed, assuming reconnectable (fallback)", self.config.debugMode)
        if callback then callback({}) end
    end
end

--- 查询是否有可重连的游戏局
--- @param callback function callback(sessions) sessions 为 nil 表示无可重连，否则为 { {mapName, mapType, sessionId, tag}, ... }
function LobbyManager:QueryCanReconnect(callback)
    if not lobby then
        LogError("lobby global object not found!")
        if callback then callback(nil) end
        return
    end

    if not lobby.QueryCanReconnect then
        -- 旧引擎没有此 C++ 接口，尝试用 LobbyProto（Lua protobuf）直接发协议
        LogDebug("lobby:QueryCanReconnect not available, trying LobbyProto fallback", self.config.debugMode)
        self:queryCanReconnectViaProto_(callback)
        return
    end

    LogDebug("Querying reconnectable sessions", self.config.debugMode)

    lobby:QueryCanReconnect(function(result)
        if not result or result.errorCode ~= 0 or not result.sessions or #result.sessions == 0 then
            LogDebug("No reconnectable sessions found", self.config.debugMode)
            if callback then callback(nil) end
        else
            LogDebug("Found " .. #result.sessions .. " reconnectable session(s)", self.config.debugMode)
            if callback then callback(result.sessions) end
        end
    end)
end

-- ============================================================================
-- 公共 API - 中途局加入
-- ============================================================================

--- 加入中途局（通过 middle_game_key 加入正在进行的游戏）
--- 成功后 Lobby 服务器会下发 NotifyGameStartEvent，再调用 ConnectToGame() 连接游戏服
--- @param options table 加入配置
---   - mapName: string 地图名称（必填）
---   - middleGameKey: string 中途局房间号（可选，为空时由 Lobby 服务器分配）
---   - regions: table 服务器区域列表（可选）
---   - onSuccess: function(middleKey) 请求被接受回调（之后等 NotifyGameStartEvent）
---   - onGameStarted: function(serverInfo) 游戏启动回调（服务器就绪）
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:JoinMiddleGame(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    if not lobby.JoinMiddleGame then
        LogError("JoinMiddleGame: lobby.JoinMiddleGame not found! "
            .. "This API requires mid-game join support.")
        if options and options.onError then
            options.onError(-2)
        end
        return -1
    end

    options = options or {}

    local mapName = options.mapName or ""
    if mapName == "" then
        LogError("JoinMiddleGame: mapName is required")
        return -1
    end

    local middleGameKey = options.middleGameKey or ""

    local modeArgsTable = {}
    if middleGameKey ~= "" then
        modeArgsTable.middle_game_key = middleGameKey
    end
    local modeArgs = buildModeArgs(modeArgsTable)
    options.tag = options.tag or getGameEnvTag()
    local regions = options.regions or { self.config.defaultRegion }
    LogDebug(string.format("Joining middle game: map=%s, key=%s, modeArgs=%s",
        mapName, middleGameKey, modeArgs), self.config.debugMode)

    if common and common.send_user_stat then
        common.send_user_stat("JoinMiddleGame", mapName)
    end

    local requestId = lobby:JoinMiddleGame({
        mapName = mapName,
        modeArgs = modeArgs,
        middleGameKey = middleGameKey,
        regions = regions,
        tag = options.tag,
    })

    -- 保存游戏启动回调（NotifyGameStartEvent 触发时使用）
    if options.onGameStarted then
        self.onGameStarted = options.onGameStarted
    end

    self:_registerRequest(requestId, {
        onSuccess = options.onSuccess,
        onError = options.onError,
    })

    return requestId
end

--- 快速查询一个可加入的中途局房间
--- 发送 REQUEST_QUICK_QUERY_MIDDLE_ROOM (0x3107) 请求
--- @param options table 查询配置
---   - gameName: string 游戏名（必填，对应 RoomQueryer 的 game_name）
---   - extra: table 额外筛选字段（可选，会自动注入 game_version 并序列化为 JSON 传给 C++）
---   - onSuccess: function(middleKey) 查到可加入房间回调，middleKey 为房间号
---   - onError: function(errorCode) 失败回调（无可加入房间或服务端错误）
--- @return number requestId
function LobbyManager:QueryMiddleRoom(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    if not lobby.QueryMiddleRoom then
        LogError("QueryMiddleRoom: lobby.QueryMiddleRoom not found! "
            .. "This API requires quick query middle room support.")
        if options and options.onError then
            options.onError(-2)
        end
        return -1
    end

    options = options or {}

    local gameName = options.gameName or ""
    if gameName == "" then
        LogError("QueryMiddleRoom: gameName is required")
        return -1
    end

    local extraTable = (type(options.extra) == "table") and options.extra or {}
    extraTable.game_version = getProjectVersion()
    extraTable.tag = extraTable.tag or getGameEnvTag()
    local extraJson = cjson.encode(extraTable)

    LogDebug(string.format("QueryMiddleRoom: gameName=%s, extra=%s",
        gameName, extraJson), self.config.debugMode)

    local requestId = lobby:QueryMiddleRoom({
        gameName = gameName,
        extra = extraJson,
    })

    self:_registerRequest(requestId, {
        onSuccess = options.onSuccess,
        onError = options.onError,
    })

    return requestId
end

-- ============================================================================
-- 公共 API - 游戏启动
-- ============================================================================

--- 创建多开调试游戏（主端调用）
--- 发送 REQUEST_CREATE_GAME (0x3105) 请求，创建游戏后服务器返回 connect_info
--- 收到 MultiDebugGameCreatedEvent 事件后，可获取调试客户端使用的连接信息
--- @param options table 创建配置
---   - mapName: string 地图名称（必填）
---   - playerCount: number 玩家数量（必填）
---   - regions: table 服务器区域列表（可选）
---   - tag: string 服务器环境标签（可选，默认 "formal"，调试时可用 "test"）
---   - onSuccess: function(debugConnectInfo) 成功回调（收到 MultiDebugGameCreatedEvent 时触发）
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:CreateMultiDebugGame(options)
    if not lobby then
        LogError("CreateMultiDebugGame: lobby global object not found!")
        return -1
    end

    if not lobby.CreateMultiDebugGame then
        LogError("CreateMultiDebugGame: lobby.CreateMultiDebugGame not found! "
            .. "This API requires multi-debug support.")
        return -1
    end

    options = options or {}

    local mapName = options.mapName or self:GetProjectId()
    if mapName == "" then
        LogError("CreateMultiDebugGame: mapName is required")
        return -1
    end

    local playerCount = options.playerCount or self:GetMaxPlayers() or 4
    local regions = options.regions or { self.config.defaultRegion }
    local tag = options.tag or "test"  -- 默认使用 test 环境

    local modeArgs = buildModeArgs(options.modeArgs)

    Log(string.format("[MultiDebug] Creating game: mapName=%s, playerCount=%d, tag=%s",
        mapName, playerCount, tag))

    -- 保存 playerCount 和回调（在 _handleMultiDebugGameCreated 中使用）
    self.pendingMultiDebugPlayerCount = playerCount
    if options.onSuccess then
        self.onMultiDebugGameCreated = options.onSuccess
    end

    local requestId = lobby:CreateMultiDebugGame({
        mapName = mapName,
        playerCount = playerCount,
        regions = regions,
        tag = tag,
        modeArgs = modeArgs,
    })

    return requestId
end

--- 开始游戏（房主在房间内调用）
--- @param options table 游戏配置
---   - mapName: string 地图名称（可选，默认使用创建房间时的地图）
---   - mode: string 游戏模式（可选）
---   - matchInfo: table 游戏信息（可选）
---   - modeArgs: table 模式参数（可选，会自动带入 project_version）
---   - onGameStarted: function(serverInfo) 游戏启动回调
---   - onError: function(errorCode) 失败回调
--- @return number requestId
function LobbyManager:StartGame(options)
    if not lobby then
        LogError("lobby global object not found!")
        return -1
    end

    options = options or {}

    local mapName = options.mapName or self.currentRoomInfo and self.currentRoomInfo.mapName or ""
    if mapName == "" then
        LogError("StartGame: mapName is required")
        return -1
    end

    local mode = options.mode or "default"

    -- 构建 matchInfo（JSON 格式）
    local matchInfo = options.matchInfo or {}
    if type(matchInfo) == "table" then
        matchInfo.mode = mode
        matchInfo.immediately_start = true
        matchInfo = jsonEncode(matchInfo)
    end

    local modeArgs = buildModeArgs(options.modeArgs)

    LogDebug(string.format("Starting game: map=%s, mode=%s",
        mapName, mode), self.config.debugMode)

    if common and common.send_user_stat then
        common.send_user_stat("StartGame", mapName)
    end

    local requestId = lobby:StartGame({
        mapName = mapName,
        matchInfo = matchInfo,
        modeArgs = modeArgs,
        tag = getGameEnvTag(),
    })

    -- 保存游戏启动回调（游戏开始通知时触发）
    if options.onGameStarted then
        self.onGameStarted = options.onGameStarted
    end

    self:_registerRequest(requestId, {
        onError = options.onError
    })

    return requestId
end

--- 连接到游戏服务器
--- @param scene Scene 要同步的场景对象（可选）
--- @return boolean 是否连接成功
function LobbyManager:ConnectToGame(scene)
    if not lobby then
        LogError("lobby global object not found!")
        return false
    end

    if not lobby:HasGameServerInfo() then
        LogError("No game server info available. Did you receive NotifyGameStartEvent?")
        return false
    end

    LogDebug("Connecting to game server...", self.config.debugMode)

    local success = lobby:ConnectToGameServer(scene)

    if success then
        LogDebug("Connection request sent", self.config.debugMode)
    else
        LogError("Failed to connect to game server")
    end

    return success
end

-- ============================================================================
-- 公共 API - 状态查询
-- ============================================================================

--- 获取用户ID
--- @return number
function LobbyManager:GetMyUserId()
    if not lobby then
        return 0
    end
    return lobby:GetMyUserId()
end

--- 是否支持中途局加入（C++ 层是否有 JoinMiddleGame / QueryMiddleRoom 接口）
--- @return boolean
function LobbyManager:SupportsMiddleGame()
    return lobby ~= nil and lobby.JoinMiddleGame ~= nil and lobby.QueryMiddleRoom ~= nil
end

--- 是否在线
--- @return boolean
function LobbyManager:IsOnline()
    if not lobby then
        return false
    end
    return lobby:IsOnline()
end

--- 是否在房间中
--- @return boolean
function LobbyManager:IsInRoom()
    return self.isInRoom
end

--- 是否正在匹配
--- @return boolean
function LobbyManager:IsMatching()
    return self.isMatching
end

--- 获取当前房间ID
--- @return number|nil
function LobbyManager:GetCurrentRoomId()
    return self.currentRoomId
end

--- 获取游戏服务器信息
--- @return table|nil
function LobbyManager:GetGameServerInfo()
    return self.gameServerInfo
end

--- 获取项目ID（从 project.json 的 project_id 字段，用作默认 MapName）
--- @return string
function LobbyManager:GetProjectId()
    if not lobby then
        return ""
    end
    if not lobby.GetProjectId then
        return ""
    end
    return lobby:GetProjectId() or ""
end

--- 检查是否为多人游戏模式（settings.json 中定义了 max_players）
--- @return boolean
function LobbyManager:IsMultiplayerMode()
    if not lobby then
        return false
    end
    if not lobby.IsMultiplayerMode then
        return false
    end
    return lobby:IsMultiplayerMode()
end

--- 获取最大玩家数（多人游戏模式时有效，从 settings.json 的 max_players 字段）
--- @return number
function LobbyManager:GetMaxPlayers()
    if not lobby then
        return 0
    end
    if not lobby.GetMaxPlayers then
        return 0
    end
    return lobby:GetMaxPlayers()
end

--- 批量查询用户昵称（委托给 _G.GetUserNickname 统一实现）
--- @param options table 查询配置
---   - userIds: table 用户ID列表（必填），例如 {12345, 67890}
---   - onSuccess: function(nicknames) 成功回调，nicknames 为数组，每个元素包含:
---     - userId: number 用户ID
---     - nickname: string 昵称（查不到则为空字符串）
---   - onError: function(errorCode) 失败回调
function LobbyManager:GetUserNickname(options)
    if not _G.GetUserNickname then
        -- UserInfo.lua not loaded yet, load it now
        pcall(require, "LuaScripts/Utilities/Previews/UserInfo")
    end
    if not _G.GetUserNickname then
        LogError("GetUserNickname: _G.GetUserNickname not available")
        return
    end
    _G.GetUserNickname(options)
end

-- ============================================================================
-- 内部辅助函数 - 命令行参数解析
-- ============================================================================

--- 获取多开调试玩家数量（主端参数 --multiDebugNum N）
--- 从命令行参数读取，所有平台统一
--- @return number 玩家数量，0 表示未启用多开调试
function LobbyManager:GetMultiDebugNum()
    if self.cachedMultiDebugNum_ then
        return self.cachedMultiDebugNum_
    end

    local result = 0
    local arguments = GetArguments()
    local i = 1
    while i <= #arguments do
        local arg = arguments[i]
        if arg == "--multiDebugNum" or arg == "-multiDebugNum" then
            if arguments[i + 1] then
                result = tonumber(arguments[i + 1]) or 0
                break
            end
        elseif string.match(arg, "^%-%-?multiDebugNum=(.+)$") then
            local value = string.match(arg, "^%-%-?multiDebugNum=(.+)$")
            result = tonumber(value) or 0
            break
        end
        i = i + 1
    end

    self.cachedMultiDebugNum_ = result
    return result
end

-- ============================================================================
-- 公共 API - 事件回调设置
-- ============================================================================

--- 设置房间创建回调
function LobbyManager:OnRoomCreated(callback)
    self.onRoomCreated = callback
end

--- 设置房间加入回调
function LobbyManager:OnRoomJoined(callback)
    self.onRoomJoined = callback
end

--- 设置房间离开回调
function LobbyManager:OnRoomLeft(callback)
    self.onRoomLeft = callback
end

--- 设置匹配成功回调
function LobbyManager:OnMatchFound(callback)
    self.onMatchFound = callback
end

--- 设置游戏启动回调
function LobbyManager:OnGameStarted(callback)
    self.onGameStarted = callback
end

--- 设置错误回调
function LobbyManager:OnError(callback)
    self.onError = callback
end

--- 设置匹配失败回调
--- @param callback function(matchEvent, errorCode) 回调函数
---   matchEvent: 3=CANCELED, 4=FAILED
function LobbyManager:OnMatchFailed(callback)
    self.onMatchFailed = callback
end

--- 设置中途局请求被接受回调（之后还需等待 NotifyGameStartEvent）
--- @param callback function(middleKey) 回调函数，middleKey 为 Lobby 返回的中途局密钥
function LobbyManager:OnMiddleJoinAccepted(callback)
    self.onMiddleJoinAccepted = callback
end

--- 设置房间玩家列表更新回调
--- @param callback function(teamStatus) 回调函数
---   teamStatus 包含:
---   - teamId: number 房间ID
---   - masterId: number 房主ID
---   - isPrivate: boolean 是否私密房间
---   - players: table 玩家列表，每个玩家包含:
---     - userId: number 玩家ID
---     - online: boolean 是否在线
---     - inMatching: boolean 是否在匹配中
---     - inGaming: boolean 是否在游戏中
function LobbyManager:OnTeamStatusChanged(callback)
    self.onTeamStatusChanged = callback
    -- 如果有缓存的 teamStatus，立即触发回调
    if callback and self.cachedTeamStatus then
        print("[LobbyManager] Triggering cached team status")
        callback(self.cachedTeamStatus)
    end
end

--- 设置玩家加入房间回调
--- @param callback function(userId) 回调函数，userId 为加入的玩家ID
function LobbyManager:OnPlayerJoin(callback)
    self.onPlayerJoin = callback
end

--- 设置玩家离开房间回调
--- @param callback function(userId) 回调函数，userId 为离开的玩家ID
function LobbyManager:OnPlayerLeave(callback)
    self.onPlayerLeave = callback
end

--- 获取项目版本号（模块级静态方法，便于外部构建 mode_id）
--- @return string 版本号，未找到返回空字符串
function LobbyManager.GetProjectVersion()
    return getProjectVersion()
end

return LobbyManager
