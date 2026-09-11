--[[
urhox-libs/GameLobby/HostSandbox/main.lua - Lobby 入口脚本

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

local useLegacyLobby = false
do
    -- 与 Runtime 侧共用 LegacyGate 读取（裸读文件、只认显式 true），避免 require 把
    -- 无返回值的开关文件塌缩成 true，导致 Host/Runtime 判定分裂。
    local ok, enabled = pcall(function()
        return require("urhox-libs.GameLobby.Runtime-hide.LegacyGate").IsLegacyEnabled()
    end)
    useLegacyLobby = ok and enabled == true
end

if useLegacyLobby then
    -- 旧版大厅整体跑在 HostSandbox：此 state 持有裸 lobby 与完整 UI 能力。
    -- 旧版入口定义全局 Start/Stop，加载后由 HostSandbox 生命周期直接驱动，不走新版 LobbyControl。
    require("urhox-libs.Lobby.main")
    return
end
-- 拆 state（设计文档 §9 步 4e）：main.lua 跑在 HostSandbox（控制层）。UI 已迁 Runtime，
-- 这里用 Host 侧大厅控制（自持 LobbyManager + 桥路由）；main 只调用 LobbyControl 门面方法。
local LobbyControl = require("urhox-libs.GameLobby.HostSandbox.LobbyControl")
local SystemNotification = require("urhox-libs.System.SystemNotification")

-- 全局状态
local isConnecting_ = false
local isBackgroundMatch_ = false  -- 后台匹配模式标志
local isMiddleGame_ = false      -- 中途局模式标志

-- 事件订阅用的 Node 和 ScriptObject（避免全局订阅覆盖）
local eventNode_ = nil
local eventScriptObject_ = nil
local pendingReconnect_ = false
-- 本次进入游戏是否由 Lobby 级重连触发。pendingReconnect_ 在 ConnectToServer 前
-- 就被清掉，无法带到 OnServerReady，因此单独保留一份供会话元数据使用。
local isReconnectSession_ = false
local isKickedByServer_ = false  -- 被服务器踢出（顶号等），不重连
local pendingKickReturn_ = false -- 延迟到下一帧处理踢出返回 Lobby
local kickedReason_ = ""         -- 踢出原因（用于返回 Lobby 后显示提示）
local pendingDeadEndPrompt_ = nil -- 普通模式：先回大厅，大厅 UI 就绪后再弹
local lobbyRuntimeReady_ = false  -- Runtime 大厅入口已完成同步初始化

-- 服务器踢人 reason 枚举（UrhoXServer 的 SendKick / KickAll 系列调用点下发）。
-- 不在枚举里的 reason 是运维后台踢人时开发者填的自定义原因，原文展示给玩家。
-- 枚举值来自服务端踢人协议；旧版大厅已冻结，本表以 GameLobby 当前行为为准。
local KickReason = {
    DUPLICATE_LOGIN = "DuplicateLogin",             -- 顶号，同账号别处登录
    GIVE_UP_RECONNECT = "GiveUpReconnect",          -- 放弃重连，被服务端踢下时回大厅并提示
    GAME_OPS_KICK = "GameOpsKick",                  -- 运维后台踢人（未填原因时的默认值）
    RESOURCE_EXCEEDED_PREFIX = "ResourceExceeded:", -- 资源超阈整局结束，后缀 memory / cpu
}

-- 封禁错误码从 LobbyControl 取，文案在 SystemNotification.Default
local GAME_START_ERROR_PLAYER_BANNED = LobbyControl.GAME_START_ERROR_PLAYER_BANNED

-- 运维自定义踢人原因原文展示给玩家，超长会撑破弹窗
local MAX_KICK_REASON_BYTES = 96
local function TruncateReason(reason)
    if #reason <= MAX_KICK_REASON_BYTES then return reason end
    -- utf8.offset(s, 0, i) 回退到含第 i 字节的字符起点，天然对齐 UTF-8 边界；
    -- or 兜非法 UTF-8（正常到不了，上游 Go json.Marshal 会先换成 U+FFFD）
    local charStart = utf8.offset(reason, 0, MAX_KICK_REASON_BYTES + 1) or (MAX_KICK_REASON_BYTES + 1)
    return string.sub(reason, 1, charStart - 1) .. "…"
end

local function RequestReturnToLobby()
    -- Ready 只对当前 Runtime 实例有效。
    lobbyRuntimeReady_ = false
    SendEvent("ReturnToLobby", VariantMap())
end

local function TryShowDeadEndPrompt(notificationId, reason)
    if notificationId == SystemNotification.Id.PlayerBanned then
        return LobbyControl.ShowDialog(notificationId) == true
    end
    return LobbyControl.ShowKickedDialog(notificationId, reason) == true
end

-- 终态提示（踢/封）的统一入口，按人现在在哪决定弹在哪、关了去哪。
-- • 已经在大厅：马上弹
-- • 中途局：就地弹，关掉退出进程
-- • 后台匹配：就地弹，不能回大厅
-- • 只有已进游戏：才先拆 Game Runtime（ReturnToLobby），大厅起来后再弹
local function ShowDeadEndPrompt(notificationId, reason)
    if isMiddleGame_ then
        LobbyControl.ShowDialog(notificationId, function()
            engine:Exit()
        end, reason)
        return
    end

    if lobbyRuntimeReady_ and TryShowDeadEndPrompt(notificationId, reason) then
        return
    end

    -- 后台匹配没有大厅可回，ReturnToLobby 会直接再开一局；只就地提示。
    if isBackgroundMatch_ then
        TryShowDeadEndPrompt(notificationId, reason)
        return
    end

    -- 局内大厅 UI 已随脚本切换回收：先切回大厅，等 Runtime 就绪后再弹。
    pendingDeadEndPrompt_ = { id = notificationId, reason = reason }
    if not lobbyRuntimeReady_ then
        RequestReturnToLobby()
    end
end

-- 前置声明（定义在 ConnectToServer 之后，因为回调中引用了它）
local StartMiddleGameFlow

-- Lobby -> Runtime 的会话元数据桥接。
-- ⚠️ 本函数与 urhox-libs/Lobby/main.lua 的同名函数**必须逐字保持一致**（仅取
-- LobbyManager 的那一行因门面不同而不同）：两份大厅在 GameLobby 上线前需并行
-- 维护且支持一键回退，一旦分叉，同一玩家在回退前后会拿到相反的 IsReconnect。
-- 检查清单见 docs/plans/issue-2210-session-lifecycle.md §9。
-- Runtime 据此在游戏脚本 Start() 之前写入 Network（供 IsReconnectSession() /
-- GetSessionId() 同步查询），并在 Start() 返回后发送 GameSessionStarted。
local function RequestGameScriptSwitch(isReconnect)
    local eventData = VariantMap()
    eventData["IsReconnect"] = isReconnect == true

    lobbyRuntimeReady_ = false

    -- SessionId 以字符串传递，避免 64 位 ID 在 Lua/JS 边界发生精度损失。
    -- 「无会话 ID」统一表示为空字符串：LobbyManager 在缺字段时会填 0
    -- （`info.session_id or 0`），直接 tostring 会得到 "0"，游戏侧判空就要写两种
    -- 情况。此处收敛为 ""。
    local sessionId = ""
    local lobbyMgr = LobbyControl.GetLobbyManager()
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

    -- 如果是后台匹配模式，不需要发送切换事件（已经在启动时发送过了）
    if isBackgroundMatch_ then
        print("[Lobby] Background match mode, skip RequestSwitchToGameScript")
        return
    end

    local reconnect = isReconnectSession_ == true
    isReconnectSession_ = false

    -- 发送事件请求切换到游戏脚本
    -- C++ UrhoXRuntime 会处理此事件，使用保存的 gameScriptPath_ 切换脚本
    RequestGameScriptSwitch(reconnect)
end

-- 服务器进度更新处理
local function OnServerProgress(eventType, eventData)
    local progress = eventData["Progress"]:GetFloat()
    local status = eventData["Status"]:GetString()
    local progressPercent = math.floor(progress * 100)

    print(string.format("[Lobby] Server progress: %d%% - %s", progressPercent, status))

    -- 更新 UI 显示服务器加载进度
    LobbyControl.UpdateServerProgress(progress, status)
end

-- 连接成功处理
local function OnServerConnected()
    print("[Lobby] Connected to game server, waiting for server ready...")
    isConnecting_ = false

    -- 历史遗留的「客户端本地重连标记」，与 urhox-libs/Lobby/main.lua 保持一致。
    -- ⚠️ 该字段**服务端收不到**：Network::OnTransportServerConnected 先把 identity
    -- 序列化发出（Network.cpp:1431），再触发 E_SERVERCONNECTED（:1435），此处写的是
    -- 已发送后的本端副本；全引擎 MSG_IDENTITY 只有那一个发送点。它唯一的作用是让
    -- 客户端脚本仍能通过
    --   GetServerConnection():GetIdentity():GetBool("is_reconnect")
    -- 读到（Connection 比 Lua VM 活得久，切脚本后仍可读）——不写会让读该字段的存量
    -- 游戏在迁到新大厅后恒得 false。
    -- 新代码请用 Network:IsReconnectSession() / GameSessionStarted；直连模式
    -- （不走 Lobby）该字段根本不存在。
    local network = GetNetwork()
    if network then
        local serverConnection = network:GetServerConnection()
        if serverConnection then
            local identity = serverConnection:GetIdentity()
            identity:SetBool("is_reconnect", isReconnectSession_ == true)
        end
    end

    -- 切换到服务器进度显示视图
    LobbyControl.SwitchToServerProgressView()

    -- 注意：不在这里切换脚本，等待 ServerReady 事件
    -- 服务器可能还在下载资源，需要等待服务器准备就绪
end

-- 游戏局已结束，返回大厅或重新匹配
local function GameSessionEnded()
    -- 本局已结束：之后进入的都是新会话，重连标记必须失效，否则重连失败
    -- 回退到新匹配/中途局时会把新局误报为 IsReconnect=true
    isReconnectSession_ = false
    if isBackgroundMatch_ then
        -- 后台匹配模式：重新发起匹配
        print("[Lobby] Game session ended in background match mode, restarting match")
        LobbyControl.RestartBackgroundMatch()
    elseif isMiddleGame_ then
        -- 中途局模式：重新查找/加入中途局
        print("[Lobby] Game session ended in middle game mode, restarting middle game flow")
        StartMiddleGameFlow()
    else
        -- 普通模式：返回大厅主界面
        print("[Lobby] Game session ended, returning to lobby")
        RequestReturnToLobby()
    end
end

-- 查询可重连游戏局，根据结果决定重连或返回大厅
local function QueryAndHandleReconnect(onHasReconnect)
    local started = LobbyControl.QueryCanReconnect(function(sessions)
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

    if not started then
        print("[Lobby] LobbyControl not ready, returning to lobby")
        GameSessionEnded()
    end
end

-- 连接失败处理
local function OnConnectFailed()
    print("[Lobby] Failed to connect to game server!")
    isConnecting_ = false

    -- 查询是否还有可重连的游戏局
    QueryAndHandleReconnect(function(sessions)
        -- 有可重连的局，延迟到下一帧重连
        LobbyControl.ShowError(SystemNotification.Id.ConnectFailedRetry)
        pendingReconnect_ = true
        -- 注意：这里**不能**置 isReconnectSession_。首连失败后查到的"可重连局"
        -- 就是刚分配给本玩家、他还没连上的那一局，服务端 tracker 里没有该
        -- user_id 记录、会发 PlayerSessionJoined；此处置 true 会造成
        -- 「客户端说重连 / 服务端说首次加入」互相矛盾，也与旧大厅
        -- （Lobby/main.lua 的 OnConnectFailed 同样不置位）行为分叉。
        -- 真正的重连链路在 HandleServerDisconnected 里已经置好了。
    end)
end

-- 连接到服务器
local function ConnectToServer()
    if isConnecting_ then
        print("[Lobby] Already connecting, ignore duplicate callback")
        return
    end

    isConnecting_ = true

    print("[Lobby] Connecting to game server...")
    local success = LobbyControl.ConnectToGame()
    if not success then
        print("[Lobby] Failed to initiate connection")
        isConnecting_ = false
        LobbyControl.ShowError(SystemNotification.Id.ConnectInitiateFailed)
    end
end

-- 服务器断线处理
local function HandleServerDisconnected()
    print("[Lobby] Server disconnected!")
    isConnecting_ = false

    -- 主动返回大厅时不重连（ReturnToLobby 触发的断线是预期行为）
    if LobbyControl.ConsumeReturningToLobbyFlag() then
        print("[Lobby] Disconnected due to ReturnToLobby, skip reconnect")
        isReconnectSession_ = false
        return
    end

    -- 被服务器踢出（顶号等）：延迟到下一帧返回 Lobby UI，避免在事件回调中切换脚本导致崩溃
    if isKickedByServer_ then
        isKickedByServer_ = false
        print("[Lobby] Kicked by server (reason=" .. kickedReason_ .. "), will return to lobby next frame")
        pendingKickReturn_ = true
        isReconnectSession_ = false
        return
    end

    -- 查询是否还有可重连的游戏局
    LobbyControl.ShowError(SystemNotification.Id.DisconnectChecking)
    QueryAndHandleReconnect(function(sessions)
        -- 有可重连的局，下一帧重连
        LobbyControl.ShowError(SystemNotification.Id.Reconnecting)
        pendingReconnect_ = true
        isReconnectSession_ = true
    end)
end

-- 启动中途局流程（查找房间 → 加入/创建 → 连接游戏服务器）
-- 首次启动和重连失败后复用此流程
StartMiddleGameFlow = function()
    if not LobbyControl.IsReady() then
        print("[Lobby] LobbyControl not ready for middle game")
        return
    end

    -- 切换到进度视图
    LobbyControl.SwitchToServerProgressView()
    LobbyControl.UpdateServerProgress(0.1, _tr("t_1ERDZYoLB1EaYO4R1c"))

    local mapName = LobbyControl.GetProjectId("DefaultMap")

    -- 清除快速匹配设置的 onMatchFound 回调，避免重复触发 ConnectToServer
    LobbyControl.ClearMatchFoundHandler()

    -- 设置游戏开始回调
    LobbyControl.SetOnGameStarted(function(serverInfo)
        print("[Lobby] Middle game: NotifyGameStart received, connecting...")
        LobbyControl.UpdateServerProgress(0.8, _tr("t_2dHP2wdR36aDuO9n"))
        ConnectToServer()
    end)

    local function onJoinFailed(errorCode)
        print("[Lobby] Create middle game also failed: " .. tostring(errorCode))
        if errorCode == GAME_START_ERROR_PLAYER_BANNED then
            ShowDeadEndPrompt(SystemNotification.Id.PlayerBanned)
        else
            LobbyControl.ShowError(SystemNotification.Id.MiddleGameJoinFailed)
        end
    end

    local function joinMiddleGame(middleKey)
        LobbyControl.UpdateServerProgress(0.4, _tr("t_AGYSNYE2ASSzx3zY"))
        LobbyControl.JoinMiddleGame({
            mapName = mapName,
            middleGameKey = middleKey,
            onSuccess = function(key)
                print("[Lobby] Middle join accepted, middleKey=" .. tostring(key))
                LobbyControl.UpdateServerProgress(0.6, _tr("t_rdBDhvaxrBg4aFN7"))
            end,
            onError = function(errorCode)
                -- 被封禁时创建新局也必然被拒，直接提示，不再 fallback
                if errorCode == GAME_START_ERROR_PLAYER_BANNED then
                    print("[Lobby] Middle join blocked by player ban")
                    ShowDeadEndPrompt(SystemNotification.Id.PlayerBanned)
                    return
                end
                print("[Lobby] Middle join failed: " .. tostring(errorCode) .. ", fallback to create")
                LobbyControl.UpdateServerProgress(0.3, _tr("t_1DtxP6pKr1DifXXE8p"))
                LobbyControl.JoinMiddleGame({
                    mapName = mapName,
                    onSuccess = function(key2)
                        print("[Lobby] New middle game created, middleKey=" .. tostring(key2))
                        LobbyControl.UpdateServerProgress(0.6, _tr("t_tcZqe6q7u7A2wo85"))
                    end,
                    onError = onJoinFailed,
                })
            end,
        })
    end

    -- 查找可加入的中途局
    print("[Lobby] Querying middle room: gameName=" .. mapName)
    LobbyControl.QueryMiddleRoom({
        gameName = mapName,
        onSuccess = function(middleKey)
            print("[Lobby] Found middle room: " .. tostring(middleKey))
            LobbyControl.UpdateServerProgress(0.3, _tr("t_YuykTIHdYQwFKJSx"))
            joinMiddleGame(middleKey)
        end,
        onError = function(errorCode)
            print("[Lobby] No middle room available (code=" .. tostring(errorCode) .. "), creating new game")
            LobbyControl.UpdateServerProgress(0.2, _tr("t_pcAf26kXpS3kMFJX"))
            LobbyControl.JoinMiddleGame({
                mapName = mapName,
                onSuccess = function(key)
                    print("[Lobby] New middle game created, middleKey=" .. tostring(key))
                    LobbyControl.UpdateServerProgress(0.6, _tr("t_tcZqe6q7u7A2wo85"))
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
    local multiDebugNum = LobbyControl.GetMultiDebugNum()
    if multiDebugNum <= 0 then
        return false
    end

    print(string.format("[Lobby] Multi-debug mode detected! playerCount=%d", multiDebugNum))

    -- 清空快速匹配设置的 onMatchFound 回调（多开调试不是匹配模式）
    LobbyControl.ClearMatchFoundHandler()

    -- 设置游戏开始回调，收到 NotifyGameStart 时连接游戏
    LobbyControl.SetOnGameStarted(function(serverInfo)
        print("[Lobby] Multi-debug: NotifyGameStart received, connecting to game...")
        ConnectToServer()
    end)

    -- 使用 project_id 作为 mapName
    local mapName = LobbyControl.GetProjectId("DefaultMap")

    print(string.format("[Lobby] Multi-debug: creating game with mapName=%s, playerCount=%d", mapName, multiDebugNum))

    -- 创建多开调试游戏（会自动通知 JS 打开调试窗口）
    LobbyControl.CreateMultiDebugGame({
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
    lobbyRuntimeReady_ = false

    SubscribeToEvent("LobbyRuntimeReady", function()
        lobbyRuntimeReady_ = true
        print("[Lobby] Runtime lobby initialization completed")
    end)

    print("==============================================")
    print("  Lobby Main Script")
    print("==============================================")

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
    LobbyControl.Show({
        debugMode = false,
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

            if reason == KickReason.GIVE_UP_RECONNECT then
                -- 还在对局里被取消重连踢下：回大厅并提示。
                -- 本人点回大厅不会到这里（HandleServerDisconnected 已吃掉返回标记）。
                ShowDeadEndPrompt(SystemNotification.Id.Kicked)
            elseif reason == KickReason.DUPLICATE_LOGIN then
                ShowDeadEndPrompt(SystemNotification.Id.DuplicateLogin)
            elseif string.find(reason, KickReason.RESOURCE_EXCEEDED_PREFIX, 1, true) == 1 then
                ShowDeadEndPrompt(SystemNotification.Id.ResourceExceeded)
            elseif reason == KickReason.GAME_OPS_KICK then
                ShowDeadEndPrompt(SystemNotification.Id.GameOpsKick)
            elseif reason == "" then
                ShowDeadEndPrompt(SystemNotification.Id.Kicked)
            else
                -- 运维手填的原因，原文给玩家看
                ShowDeadEndPrompt(SystemNotification.Id.Kicked, TruncateReason(reason))
            end
        end

        -- 处理延迟弹窗（ShowDeadEndPrompt 时若在对局里，等退回大厅后再弹）
        if pendingDeadEndPrompt_ and lobbyRuntimeReady_ then
            local prompt = pendingDeadEndPrompt_

            -- 没有真实消费回执时保留 pending，下一帧继续尝试。
            if TryShowDeadEndPrompt(prompt.id, prompt.reason) then
                pendingDeadEndPrompt_ = nil
            end
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
        LobbyControl.StartQuickMatch()

        -- 立即切换到游戏脚本（游戏先运行，匹配在后台进行）
        -- 此时匹配尚未返回，SessionId 必然为空——游戏脚本判断重连请用
        -- IsReconnect，勿用 SessionId 是否为空（见 docs/plans/issue-2210-*.md §8）
        RequestGameScriptSwitch(false)

        print("[Lobby] Background match started, switched to game script")
    end

    -- 中途局模式：显示加入状态 UI，立即查找房间加入
    if enabledMiddleGame then
        print("[Lobby] Middle game mode enabled!")
        isMiddleGame_ = true

        if not LobbyControl.SupportsMiddleGame() then
            print("[Lobby] Middle game C++ API not available, runtime version too old")
            LobbyControl.ShowDialog(SystemNotification.Id.VersionTooLow, function()
                engine:Exit()
            end)
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
    lobbyRuntimeReady_ = false

    -- 清理事件订阅 Node
    if eventNode_ then
        eventNode_:Remove()
        eventNode_ = nil
        eventScriptObject_ = nil
    end
end
