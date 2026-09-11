--[[
urhox-libs/Lobby/main.lua - Lobby 入口脚本

当 settings.json 中包含 max_players 字段时，UrhoXRuntime 会自动加载此脚本。
此脚本负责：
1. 显示 Lobby UI（快速匹配、房间浏览、创建房间）
2. 处理匹配/开局流程
3. 连接到游戏服务器
4. 收到服务器准备就绪事件后切换到游戏脚本

使用的事件：
- ServerConnected: 连接游戏服务器成功（但服务器可能还在加载资源）
- ServerProgress: 服务器加载进度（包含 Progress 和 Status 字段）
- ServerReady: 服务器准备就绪（资源加载完成，可以开始游戏）
- ConnectFailed: 连接游戏服务器失败
- RequestSwitchToGameScript: 请求切换到游戏脚本（C++ 处理）
]]

-- iOS calling GetArguments crashes, replace with empty table
if GetPlatform() == "iOS" then
    function GetArguments()
        return {}
    end
end

pcall(require, 'LuaScripts.Utilities.EnginePreview')
local LobbyUI = require("urhox-libs.Lobby.LobbyUI")

-- 全局状态
local isConnecting_ = false
local isServerConnected_ = false
local isBackgroundMatch_ = false  -- 后台匹配模式标志
local isMiddleGame_ = false      -- 中途局模式标志
local isMultiDebugMode_ = false  -- 多开调试模式标志

-- 事件订阅用的 Node 和 ScriptObject（避免全局订阅覆盖）
local eventNode_ = nil
local eventScriptObject_ = nil
local pendingReconnect_ = false
local isReconnecting_ = false    -- 当前连接是否为断线重连
local isKickedByServer_ = false  -- 被服务器踢出（顶号等），不重连
local pendingKickReturn_ = false -- 延迟到下一帧处理踢出返回 Lobby
local kickedReason_ = ""         -- 踢出原因（用于返回 Lobby 后显示提示）

-- 服务器踢人 reason 枚举（UrhoXServer 的 SendKick / KickAll 系列调用点下发）。
-- 不在枚举里的 reason 是运维后台踢人时开发者填的自定义原因，原文展示给玩家。
local KickReason = {
    DUPLICATE_LOGIN = "DuplicateLogin",             -- 顶号，同账号别处登录
    GIVE_UP_RECONNECT = "GiveUpReconnect",          -- 放弃重连，静默不提示
    GAME_OPS_KICK = "GameOpsKick",                  -- 运维后台踢人（未填原因时的默认值）
    RESOURCE_EXCEEDED_PREFIX = "ResourceExceeded:", -- 资源超阈整局结束，后缀 memory / cpu
}

-- 运维自定义踢人原因原文展示给玩家，超长会撑破弹窗
local MAX_KICK_REASON_BYTES = 96
local function TruncateReason(reason)
    if #reason <= MAX_KICK_REASON_BYTES then return reason end
    -- utf8.offset(s, 0, i) 回退到含第 i 字节的字符起点，天然对齐 UTF-8 边界；
    -- or 兜非法 UTF-8（正常到不了，上游 Go json.Marshal 会先换成 U+FFFD）
    local charStart = utf8.offset(reason, 0, MAX_KICK_REASON_BYTES + 1) or (MAX_KICK_REASON_BYTES + 1)
    return string.sub(reason, 1, charStart - 1) .. "…"
end

-- 终态提示（被踢 / 被封）：中途局模式没有主界面可回，普通弹窗关掉后玩家会卡在
-- 进度页，必须用常驻弹窗并在关闭时退出游戏；其他模式弹普通踢出弹窗、可回大厅
local function ShowDeadEndPrompt(title, message)
    if isMiddleGame_ then
        LobbyUI.ShowDialog({
            title = title,
            message = message,
            onClose = function()
                engine:Exit()
            end,
        })
    else
        LobbyUI.ShowKickedDialog(title, message)
    end
end

-- 前置声明（定义在 ConnectToServer 之后，因为回调中引用了它）
local StartMiddleGameFlow

-- Lobby -> Runtime 的会话元数据桥接。
-- ⚠️ 本函数与 urhox-libs/GameLobby/HostSandbox/main.lua 的同名函数**必须逐字保持
-- 一致**（仅取 LobbyManager 的那一行因门面不同而不同）：两份大厅在 GameLobby 上线
-- 前需并行维护且支持一键回退，一旦分叉，同一玩家在回退前后会拿到相反的
-- IsReconnect。检查清单见 docs/plans/issue-2210-session-lifecycle.md §9。
-- Runtime 据此在游戏脚本 Start() 之前写入 Network（供 IsReconnectSession() /
-- GetSessionId() 同步查询），并在 Start() 返回后发送 GameSessionStarted。
local function RequestGameScriptSwitch(isReconnect)
    local eventData = VariantMap()
    eventData["IsReconnect"] = isReconnect == true

    -- SessionId 以字符串传递，避免 64 位 ID 在 Lua/JS 边界发生精度损失。
    -- 「无会话 ID」统一表示为空字符串：LobbyManager 在缺字段时会填 0
    -- （`info.session_id or 0`），直接 tostring 会得到 "0"，游戏侧判空就要写两种
    -- 情况。此处收敛为 ""。
    local sessionId = ""
    local lobbyMgr = LobbyUI.GetLobbyManager()
    local serverInfo = lobbyMgr and lobbyMgr.GetGameServerInfo and lobbyMgr:GetGameServerInfo()
    if serverInfo and serverInfo.sessionId ~= nil and serverInfo.sessionId ~= 0
        and tostring(serverInfo.sessionId) ~= "0" then
        sessionId = tostring(serverInfo.sessionId)
    end
    eventData["SessionId"] = sessionId

    SendEvent("RequestSwitchToGameScript", eventData)
end

-- 服务器准备就绪处理
local function OnServerReady()
    print("[Lobby] Server is ready!")

    -- 禁用 Lobby UI（停止渲染和事件处理，但保留在内存中）
    LobbyUI.SetEnabled(false)

    -- 如果是后台匹配模式，不需要发送切换事件（已经在启动时发送过了）
    if isBackgroundMatch_ then
        print("[Lobby] Background match mode, skip RequestSwitchToGameScript")
        return
    end

    local reconnect = isReconnecting_ == true
    isReconnecting_ = false

    -- C++ UrhoXRuntime 会在游戏脚本 Start() 返回后发送 GameSessionStarted。
    RequestGameScriptSwitch(reconnect)
end

-- 服务器进度更新处理
local function OnServerProgress(eventType, eventData)
    local progress = eventData["Progress"]:GetFloat()
    local status = eventData["Status"]:GetString()
    local progressPercent = math.floor(progress * 100)

    print(string.format("[Lobby] Server progress: %d%% - %s", progressPercent, status))

    -- 更新 UI 显示服务器加载进度
    LobbyUI.UpdateServerProgress(progress, status)
end

-- 连接成功处理
local function OnServerConnected()
    print("[Lobby] Connected to game server, waiting for server ready...")
    isConnecting_ = false
    isServerConnected_ = true

    -- 历史遗留的「客户端本地重连标记」，与 urhox-libs/GameLobby 保持一致。
    -- ⚠️ 该字段**服务端收不到**：Network::OnTransportServerConnected 先把 identity
    -- 序列化发出（Network.cpp:1431），再触发 E_SERVERCONNECTED（:1435），此处写的是
    -- 已发送后的本端副本；全引擎 MSG_IDENTITY 只有那一个发送点。它唯一的作用是让
    -- 客户端脚本仍能通过
    --   GetServerConnection():GetIdentity():GetBool("is_reconnect")
    -- 读到（Connection 比 Lua VM 活得久，切脚本后仍可读）。
    -- 新代码请用 Network:IsReconnectSession() / GameSessionStarted；直连模式
    -- （不走 Lobby）该字段根本不存在。
    local network = GetNetwork()
    if network then
        local serverConnection = network:GetServerConnection()
        if serverConnection then
            local identity = serverConnection:GetIdentity()
            identity:SetBool("is_reconnect", isReconnecting_ == true)
        end
    end

    -- 切换到服务器进度显示视图
    LobbyUI.SwitchToServerProgressView()

    -- 注意：不在这里切换脚本，等待 ServerReady 事件
    -- 服务器可能还在下载资源，需要等待服务器准备就绪
end

-- 游戏局已结束，返回大厅或重新匹配
local function GameSessionEnded()
    isReconnecting_ = false
    if isBackgroundMatch_ then
        -- 后台匹配模式：重新发起匹配
        print("[Lobby] Game session ended in background match mode, restarting match")
        LobbyUI.RestartBackgroundMatch()
    elseif isMiddleGame_ then
        -- 中途局模式：重新查找/加入中途局
        print("[Lobby] Game session ended in middle game mode, restarting middle game flow")
        StartMiddleGameFlow()
    else
        -- 普通模式：返回大厅主界面
        print("[Lobby] Game session ended, returning to lobby")
        LobbyUI.SetEnabled(true)
        SendEvent("ReturnToLobby", VariantMap())
    end
end

-- 查询可重连游戏局，根据结果决定重连或返回大厅
local function QueryAndHandleReconnect(onHasReconnect)
    local lobbyMgr = LobbyUI.GetLobbyManager()
    if not lobbyMgr then
        print("[Lobby] LobbyManager not available, returning to lobby")
        GameSessionEnded()
        return
    end

    lobbyMgr:QueryCanReconnect(function(sessions)
        if sessions then
            -- 有可重连的局
            print("[Lobby] Found " .. #sessions .. " reconnectable session(s), attempting reconnect")
            if onHasReconnect then
                onHasReconnect(sessions)
            end
        else
            -- 无可重连的局，游戏已结束
            print("[Lobby] No reconnectable sessions, game session ended")
            GameSessionEnded()
        end
    end)
end

-- 连接失败处理
local function OnConnectFailed()
    print("[Lobby] Failed to connect to game server!")
    isConnecting_ = false
    isServerConnected_ = false

    -- 查询是否还有可重连的游戏局
    QueryAndHandleReconnect(function(sessions)
        -- 有可重连的局，延迟到下一帧重连
        LobbyUI.ShowError(_tr("t_1BjsfhBO01CDKZQdPZ"))
        pendingReconnect_ = true
    end)
end

-- 连接到服务器
local function ConnectToServer()
    if isConnecting_ then
        print("[Lobby] Already connecting, ignore duplicate callback")
        return
    end

    isConnecting_ = true

    -- 连接到游戏服务器
    local lobbyMgr = LobbyUI.GetLobbyManager()
    if lobbyMgr then
        print("[Lobby] Connecting to game server...")
        local success = lobbyMgr:ConnectToGame()
        if not success then
            print("[Lobby] Failed to initiate connection")
            isConnecting_ = false
            LobbyUI.ShowError("Failed to initiate connection to game server.")
        end
    else
        print("[Lobby] LobbyManager not available!")
        isConnecting_ = false
    end
end

-- 服务器断线处理
local function HandleServerDisconnected()
    print("[Lobby] Server disconnected!")
    isServerConnected_ = false
    isConnecting_ = false

    -- 主动返回大厅时不重连（ReturnToLobby 触发的断线是预期行为）
    if LobbyUI.isReturningToLobby_ then
        print("[Lobby] Disconnected due to ReturnToLobby, skip reconnect")
        LobbyUI.isReturningToLobby_ = false
        isReconnecting_ = false
        return
    end

    -- 被服务器踢出（顶号等）：延迟到下一帧返回 Lobby UI，避免在事件回调中切换脚本导致崩溃
    if isKickedByServer_ then
        isKickedByServer_ = false
        isReconnecting_ = false
        print("[Lobby] Kicked by server (reason=" .. kickedReason_ .. "), will return to lobby next frame")
        pendingKickReturn_ = true
        return
    end

    -- 查询是否还有可重连的游戏局；若后续连接成功，会写入连接 identity 的 is_reconnect 标记
    isReconnecting_ = true
    LobbyUI.ShowError(_tr("t_16fskayFN16BpvrdU8"))
    QueryAndHandleReconnect(function(sessions)
        -- 有可重连的局，下一帧重连
        LobbyUI.ShowError(_tr("t_4t4FTKWN4R42yEb8"))
        pendingReconnect_ = true
    end)
end

-- 启动中途局流程（查找房间 → 加入/创建 → 连接游戏服务器）
-- 首次启动和重连失败后复用此流程
StartMiddleGameFlow = function()
    local lobbyMgr = LobbyUI.GetLobbyManager()
    if not lobbyMgr then
        print("[Lobby] LobbyManager not available for middle game")
        return
    end

    -- 切换到进度视图
    LobbyUI.SwitchToServerProgressView()
    LobbyUI.UpdateServerProgress(0.1, _tr("t_1ERDZYoLB1EaYO4R1c"))

    local mapName = lobbyMgr:GetProjectId()
    if not mapName or mapName == "" then
        mapName = "DefaultMap"
    end

    -- 清除 LobbyUI 设置的 onMatchFound 回调，避免重复触发 ConnectToServer
    lobbyMgr:OnMatchFound(nil)

    -- 设置游戏开始回调
    lobbyMgr:OnGameStarted(function(serverInfo)
        print("[Lobby] Middle game: NotifyGameStart received, connecting...")
        LobbyUI.UpdateServerProgress(0.8, _tr("t_2dHP2wdR36aDuO9n"))
        ConnectToServer()
    end)

    local function onJoinFailed(errorCode)
        print("[Lobby] Create middle game also failed: " .. tostring(errorCode))
        if errorCode == LobbyUI.GAME_START_ERROR_PLAYER_BANNED then
            ShowDeadEndPrompt(_tr("t_169MBn8PQ16em6Gp1K"), LobbyUI.PLAYER_BANNED_MESSAGE)
        else
            LobbyUI.ShowError(_tr("t_axnZJO1PbSNSsWfN"))
        end
    end

    local function joinMiddleGame(middleKey)
        LobbyUI.UpdateServerProgress(0.4, _tr("t_AGYSNYE2ASSzx3zY"))
        lobbyMgr:JoinMiddleGame({
            mapName = mapName,
            middleGameKey = middleKey,
            onSuccess = function(key)
                print("[Lobby] Middle join accepted, middleKey=" .. tostring(key))
                LobbyUI.UpdateServerProgress(0.6, _tr("t_rdBDhvaxrBg4aFN7"))
            end,
            onError = function(errorCode)
                -- 被封禁时创建新局也必然被拒，直接提示，不再 fallback
                if errorCode == LobbyUI.GAME_START_ERROR_PLAYER_BANNED then
                    print("[Lobby] Middle join blocked by player ban")
                    ShowDeadEndPrompt(_tr("t_169MBn8PQ16em6Gp1K"), LobbyUI.PLAYER_BANNED_MESSAGE)
                    return
                end
                print("[Lobby] Middle join failed: " .. tostring(errorCode) .. ", fallback to create")
                LobbyUI.UpdateServerProgress(0.3, _tr("t_1DtxP6pKr1DifXXE8p"))
                lobbyMgr:JoinMiddleGame({
                    mapName = mapName,
                    onSuccess = function(key2)
                        print("[Lobby] New middle game created, middleKey=" .. tostring(key2))
                        LobbyUI.UpdateServerProgress(0.6, _tr("t_tcZqe6q7u7A2wo85"))
                    end,
                    onError = onJoinFailed,
                })
            end,
        })
    end

    -- 查找可加入的中途局
    print("[Lobby] Querying middle room: gameName=" .. mapName)
    lobbyMgr:QueryMiddleRoom({
        gameName = mapName,
        onSuccess = function(middleKey)
            print("[Lobby] Found middle room: " .. tostring(middleKey))
            LobbyUI.UpdateServerProgress(0.3, _tr("t_YuykTIHdYQwFKJSx"))
            joinMiddleGame(middleKey)
        end,
        onError = function(errorCode)
            print("[Lobby] No middle room available (code=" .. tostring(errorCode) .. "), creating new game")
            LobbyUI.UpdateServerProgress(0.2, _tr("t_pcAf26kXpS3kMFJX"))
            lobbyMgr:JoinMiddleGame({
                mapName = mapName,
                onSuccess = function(key)
                    print("[Lobby] New middle game created, middleKey=" .. tostring(key))
                    LobbyUI.UpdateServerProgress(0.6, _tr("t_tcZqe6q7u7A2wo85"))
                end,
                onError = onJoinFailed,
            })
        end,
    })
end

-- 游戏开始回调（收到服务器信息后触发）
local function OnGameStart(serverInfo)
    print(string.format("[Lobby] Game start! Server: %s:%d", serverInfo.ip, serverInfo.port))

    ConnectToServer()
end

-- 启动多开调试模式
local function tryStartMultiDebugMode()
    local lobbyMgr = LobbyUI.GetLobbyManager()
    local multiDebugNum = lobbyMgr:GetMultiDebugNum()
    if multiDebugNum <= 0 then
        return false
    end

    print(string.format("[Lobby] Multi-debug mode detected! playerCount=%d", multiDebugNum))
    isMultiDebugMode_ = true

    -- 隐藏 UI
    LobbyUI.SetEnabled(false)

    -- 清空 LobbyUI 设置的 onMatchFound 回调（多开调试不是匹配模式）
    lobbyMgr:OnMatchFound(nil)

    -- 设置游戏开始回调，收到 NotifyGameStart 时连接游戏
    lobbyMgr:OnGameStarted(function(serverInfo)
        print("[Lobby] Multi-debug: NotifyGameStart received, connecting to game...")
        ConnectToServer()
    end)

    -- 使用 project_id 作为 mapName
    local mapName = lobbyMgr:GetProjectId()
    if not mapName or mapName == "" then
        mapName = "DefaultMap"
    end

    print(string.format("[Lobby] Multi-debug: creating game with mapName=%s, playerCount=%d", mapName, multiDebugNum))

    -- 创建多开调试游戏（会自动通知 JS 打开调试窗口）
    lobbyMgr:CreateMultiDebugGame({
        mapName = mapName,
        playerCount = multiDebugNum,
        tag = "test",
        onSuccess = function(debugConnectInfo)
            print("[Lobby] Multi-debug: game created, debug clients can connect")
        end,
        onError = function(errorCode)
            print("[Lobby] Multi-debug: create game failed with error: " .. tostring(errorCode))
        end
    })

    -- 不立即切换脚本，等 NotifyGameStart → ConnectToServer() → ServerReady 后再切换
    print("[Lobby] Multi-debug mode started, waiting for NotifyGameStart...")
    return true
end

function Start()
    print("==============================================")
    print("  Lobby Main Script")
    print("==============================================")

    -- 初始化协议解析模块（用于在 Lua 端解析 protobuf 协议）
    -- local LobbyProto = require("urhox-libs.Lobby.LobbyProto")
    -- LobbyProto.Init()
    -- LobbyProto.RegisterHandler(0x3040, function(messageId, msg)
    --     -- 处理 ResponseUserCurrentStatus
    -- end)

    -- 注册远端事件（允许从服务器接收事件）
    local network = GetNetwork()
    if network then
        network:RegisterRemoteEvent("ServerProgress")
        network:RegisterRemoteEvent("ServerReady")
        network:RegisterRemoteEvent("IdentityUpdated")
        network:RegisterRemoteEvent("KickedByServer")
        print("[Lobby] Registered remote events: ServerProgress, ServerReady, KickedByServer")
    else
        print("[Lobby] Warning: Network subsystem not available")
    end

    -- 订阅网络连接事件
    SubscribeToEvent("ServerConnected", function()
        -- 发送认证协议
        if not NETWORK_AUTO_SEND_IDENTITY then
            local network = GetNetwork()
            if network then
                local serverConnection = network:GetServerConnection()
                if serverConnection then
                    local msg = VectorBuffer()
                    msg:WriteVariantMap(serverConnection:GetIdentity())
                    serverConnection:SendMessage(135, true, true, msg)
                end
            end
        end

        OnServerConnected()
    end)

    SubscribeToEvent("ConnectFailed", function()
        OnConnectFailed()
    end)

    SubscribeToEvent("ServerDisconnected", function()
        HandleServerDisconnected()
    end)

    SubscribeToEvent("KickedByServer", function(eventType, eventData)
        local reason = ""
        if eventData and eventData["Reason"] then
            reason = eventData["Reason"]:GetString()
        end
        print("[Lobby] Kicked by server, reason: " .. reason)
        isKickedByServer_ = true
        kickedReason_ = reason
        -- 客户端主动断开，触发 ServerDisconnected → HandleServerDisconnected 中处理返回 Lobby
        local network = GetNetwork()
        if network then
            network:Disconnect()
        end
    end)

    -- 订阅服务器进度事件（远端事件）
    SubscribeToEvent("ServerProgress", function(eventType, eventData)
        OnServerProgress(eventType, eventData)
    end)

    -- 订阅服务器准备就绪事件（远端事件）
    SubscribeToEvent("ServerReady", function()
        OnServerReady()
    end)

    -- 订阅身份信息更新事件（服务端发送，同步 nick_name 到客户端 identity）
    SubscribeToEvent("IdentityUpdated", function(eventType, eventData)
        local network = GetNetwork()
        if network then
            local serverConnection = network:GetServerConnection()
            if serverConnection then
                local identity = serverConnection:GetIdentity()
                local nickName = eventData:GetString("nick_name") or ""
                identity:SetString("nick_name", nickName)
                print(string.format("[Lobby] Identity updated from server: nick_name=%s", nickName))
            end
        end
    end)

    -- 读取 settings.json 获取配置
    local matchInfo = nil
    local middleGameInfo = nil
    -- 中途局是否启用
    local enabledMiddleGame = false
    local backgroundMatch = false
    local cache = GetCache()
    if cache then
        local file = cache:GetFile("settings.json")
        if file then
            local content = file:ReadString()
            file:Close()

            if content and content ~= "" then
                local success, settings = pcall(cjson.decode, content)
                if success and settings then
                    local multiplayer = settings.multiplayer
                    if multiplayer then
                        print("[Lobby] multiplayer config: " .. cjson.encode(multiplayer))
                        matchInfo = multiplayer.match_info
                        backgroundMatch = multiplayer.background_match == true
                        middleGameInfo =multiplayer.persistent_world
                        enabledMiddleGame = middleGameInfo and middleGameInfo.enabled == true

                        -- persistent_world 与 background_match 互斥，persistent_world 优先
                        -- 文档约定：两者同时开启时，persistent_world 生效，background_match 强制关闭
                        if enabledMiddleGame and backgroundMatch then
                            print("[Lobby] persistent_world and background_match are mutually exclusive, persistent_world takes priority, backgroundMatch forced to false")
                            backgroundMatch = false
                        end
                    end
                else
                    print("[Lobby] Failed to parse settings.json")
                end
            end
        else
            print("[Lobby] settings.json not found")
        end
    end

    -- 显示 Lobby UI（中途局模式下跳过卡片主界面，只用进度视图和弹窗）
    LobbyUI.Show({
        debugMode = true,
        theme = "dark",

        -- 功能开关
        allowCreateRoom = true,
        allowQuickMatch = true,
        allowBrowseRooms = true,

        -- 中途局模式下不创建卡片主视图
        skipMainView = enabledMiddleGame,

        -- 匹配配置（从 settings.json 读取）
        matchInfo = matchInfo,
        backgroundMatch = backgroundMatch,

        -- 游戏开始回调
        onGameStart = OnGameStart
    })

    print("[Lobby] Lobby UI initialized")

    -- 创建事件订阅用的 ScriptObject（避免全局订阅覆盖）
    eventNode_ = Node()
    eventScriptObject_ = eventNode_:CreateScriptObject("LuaScriptObject")
    eventScriptObject_:SubscribeToEvent("Update", function(self, eventType, eventData)
        if pendingKickReturn_ then
            pendingKickReturn_ = false
            local reason = kickedReason_
            kickedReason_ = ""
            print("[Lobby] Processing kick return, reason=" .. reason)

            -- 只重新启用 UI，不做脚本切换（lobby 脚本仍在运行）
            LobbyUI.SetEnabled(true)

            if reason == KickReason.DUPLICATE_LOGIN then
                ShowDeadEndPrompt(_tr("t_hF2C5hH2hQxc9Z1y"), _tr("t_OGvsHNbNNlsLKYwt"))
            elseif string.find(reason, KickReason.RESOURCE_EXCEEDED_PREFIX, 1, true) == 1 then
                ShowDeadEndPrompt(_tr("t_tX3RnT6dt6Otrp4D"), _tr("t_h9xNSvRqhabw0roi"))
            elseif reason == KickReason.GAME_OPS_KICK then
                ShowDeadEndPrompt(_tr("t_BKCWQCBWBpcQJeb6"), _tr("t_1fuqLApu1Yh8UVlE"))
            elseif reason == "" then
                ShowDeadEndPrompt(_tr("t_TPUpz0Q6TsBETGpE"), _tr("t_QPwrRVA0QXOnlh98"))
            elseif reason ~= KickReason.GIVE_UP_RECONNECT then
                -- 运维踢人时开发者填的自定义原因
                ShowDeadEndPrompt(_tr("t_BKCWQCBWBpcQJeb6"), _tr("t_Lo69xEfaLNWIRMpI", TruncateReason(reason)))
            end
            return
        end
        if pendingReconnect_ then
            pendingReconnect_ = false
            ConnectToServer()
        end
    end)

    -- 后台匹配模式
    if backgroundMatch then
        print("[Lobby] Background match mode enabled!")
        isBackgroundMatch_ = true

        -- 立即开始匹配
        LobbyUI.StartQuickMatch()

        -- 禁用 UI（后台匹配，不显示界面）
        LobbyUI.SetEnabled(false)

        -- 立即切换到游戏脚本（游戏先运行，匹配在后台进行）
        RequestGameScriptSwitch(false)

        print("[Lobby] Background match started, switched to game script")
    end

    -- 中途局模式：显示加入状态 UI，立即查找房间加入
    if enabledMiddleGame then
        print("[Lobby] Middle game mode enabled!")
        isMiddleGame_ = true

        local lobbyMgr = LobbyUI.GetLobbyManager()

        if not lobbyMgr:SupportsMiddleGame() then
            print("[Lobby] Middle game C++ API not available, runtime version too old")
            LobbyUI.ShowDialog({
                title = _tr("t_nWNYw5ZIndv2Qass"),
                message = _tr("t_15flMrxkP15rgSmPjH"),
                onClose = function()
                    engine:Exit()
                end,
            })
            return
        end

        StartMiddleGameFlow()
        print("[Lobby] Middle game query started")
    end

    -- 多开调试模式（?multiDebugNum=N）
    tryStartMultiDebugMode()
end

function Stop()
    print("[Lobby] Stopping...")

    -- 清理事件订阅 Node
    if eventNode_ then
        eventNode_:Remove()
        eventNode_ = nil
        eventScriptObject_ = nil
    end

    -- 隐藏 UI
    LobbyUI.Hide()
end
