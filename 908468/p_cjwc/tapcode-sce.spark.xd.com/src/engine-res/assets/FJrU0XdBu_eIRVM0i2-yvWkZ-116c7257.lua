--[[
Example_StartGame.lua - 使用 LobbyProto 发送开局协议的测试样例

本文件展示如何使用 LobbyProto 模块发送房间内开局协议 (RequestMatchStart)。

协议信息:
- 协议 ID: 0x3080 (REQUEST_MATCH_START)
- 消息类型: CEProto.TSLobbyServer.RequestMatchStart
- 用途: 房主在房间内调用，发起开局请求

注意: 这是一个测试样例，实际使用时请通过 LobbyManager:StartGame() 调用，
      除非你需要完全自定义协议内容。
]]

local LobbyProto = require("urhox-libs.Lobby.LobbyProto")
local LobbyManager = require("urhox-libs.Lobby.LobbyManager")

--------------------------------------------------------------------------------
-- 协议常量
--------------------------------------------------------------------------------

local PROTO_ID = {
    REQUEST_MATCH_START = 0x3080,       -- 开局请求
    RESPONSE_MATCH_START = 0x3080,      -- 开局响应（同ID）
    NOTIFY_GAME_START = 0x3012,         -- 游戏开始通知
    NOTIFY_MATCH_STATUS_CHANGED = 0x3014, -- 匹配状态变更
}

local MSG_TYPE = {
    REQUEST_MATCH_START = "CEProto.TSLobbyServer.RequestMatchStart",
    RESPONSE_MATCH_START = "CEProto.TSLobbyServer.ResponseMatchStart",
    NOTIFY_GAME_START = "CEProto.TSLobbyServer.NotifyGameStart",
    NOTIFY_MATCH_STATUS_CHANGED = "CEProto.TSLobbyServer.NotifyMatchStatusChanged",
}

--------------------------------------------------------------------------------
-- 初始化
--------------------------------------------------------------------------------

local isInitialized = false

local function Init()
    if isInitialized then
        return true
    end

    -- 初始化 LobbyProto
    if not LobbyProto.IsReady() then
        local success = LobbyProto.Init()
        if not success then
            print("[Example_StartGame] Failed to initialize LobbyProto")
            return false
        end
    end

    -- 注册消息类型映射（用于接收响应）
    LobbyProto.AddMessageType(PROTO_ID.RESPONSE_MATCH_START, MSG_TYPE.RESPONSE_MATCH_START)
    LobbyProto.AddMessageType(PROTO_ID.NOTIFY_GAME_START, MSG_TYPE.NOTIFY_GAME_START)
    LobbyProto.AddMessageType(PROTO_ID.NOTIFY_MATCH_STATUS_CHANGED, MSG_TYPE.NOTIFY_MATCH_STATUS_CHANGED)

    -- 注册响应处理器
    LobbyProto.RegisterHandler(PROTO_ID.RESPONSE_MATCH_START, function(messageId, msg)
        print("[Example_StartGame] Received ResponseMatchStart:")
        print("  error_code: " .. tostring(msg.error_code))
        if msg.error_code == 0 then
            print("  -> Match request accepted, waiting for game start...")
        else
            print("  -> Match request failed!")
        end
    end)

    LobbyProto.RegisterHandler(PROTO_ID.NOTIFY_GAME_START, function(messageId, msg)
        print("[Example_StartGame] Received NotifyGameStart:")
        print("  server_ip: " .. tostring(msg.server_ip))
        print("  server_port: " .. tostring(msg.server_port))
        print("  session_id: " .. tostring(msg.session_id))
        print("  -> Game is ready to connect!")
    end)

    LobbyProto.RegisterHandler(PROTO_ID.NOTIFY_MATCH_STATUS_CHANGED, function(messageId, msg)
        print("[Example_StartGame] Received NotifyMatchStatusChanged:")
        print("  match_event: " .. tostring(msg.match_event))
        -- match_event: 0=PENDING, 1=START, 2=SUCCESS, 3=CANCELED, 4=FAILED
        local eventNames = { [0]="PENDING", [1]="START", [2]="SUCCESS", [3]="CANCELED", [4]="FAILED" }
        print("  -> Event: " .. (eventNames[msg.match_event] or "UNKNOWN"))
    end)

    isInitialized = true
    print("[Example_StartGame] Initialized successfully")
    return true
end

--------------------------------------------------------------------------------
-- 发送开局协议
--------------------------------------------------------------------------------

--- 发送开局请求（房间内开局）
--- @param options table 配置选项
---   - mapName: string 地图名称（必填）
---   - matchInfo: string 匹配信息 JSON（可选）
---   - modeArgs: string 模式参数（可选）
---   - tag: string 环境标签（可选）
--- @return number requestId 请求ID（用于匹配响应），失败返回 -1
local function SendStartGame(options)
    if not Init() then
        return false
    end

    options = options or {}

    local mapName = options.mapName or ""
    if mapName == "" then
        print("[Example_StartGame] Error: mapName is required")
        return false
    end

    -- 构建请求消息
    local request = {
        map_name = mapName,
        match_info = options.matchInfo or '{"immediately_start":true}',
    }

    -- 可选字段
    if options.modeArgs and options.modeArgs ~= "" then
        request.mode_args = options.modeArgs
    end

    if options.tag and options.tag ~= "" then
        request.tag = options.tag
    end

    print("[Example_StartGame] Sending RequestMatchStart:")
    print("  map_name: " .. request.map_name)
    print("  match_info: " .. request.match_info)

    -- 使用 LobbyProto 发送，返回 requestId
    local requestId = LobbyProto.EncodeAndSend(
        PROTO_ID.REQUEST_MATCH_START,
        MSG_TYPE.REQUEST_MATCH_START,
        request
    )

    if requestId > 0 then
        print("[Example_StartGame] Request sent successfully, requestId=" .. requestId)
    else
        print("[Example_StartGame] Failed to send request")
    end

    return requestId
end

--------------------------------------------------------------------------------
-- 快捷方法
--------------------------------------------------------------------------------

--- 带 AI 开局
--- @param mapName string 地图名称
--- @param playerNumber number 玩家数量
--- @param matchTimeout number 匹配超时时间（可选，默认60秒）
local function StartWithAI(mapName, playerNumber, matchTimeout)
    playerNumber = playerNumber or 2
    matchTimeout = matchTimeout or 60
    local descName = "free_match_with_ai"
    local immediatelyStart = true

    -- 用 table 构造 mode_id 内容
    -- 补齐 project_version，保证不同版本的玩家不会被匹配到同一桶。
    local modeIdTable = {
        desc_name = descName,
        immediately_start = immediatelyStart,
        match_timeout = matchTimeout,
        player_number = playerNumber,
        project_version = LobbyManager.GetProjectVersion(),
    }

    -- 用 table 构造 matchInfo
    local matchInfoTable = {
        desc_name = descName,
        immediately_start = immediatelyStart,
        match_timeout = matchTimeout,
        player_number = playerNumber,
        mode_id = cjson.encode(modeIdTable),  -- mode_id 是 JSON 字符串
    }

    return SendStartGame({
        mapName = mapName,
        matchInfo = cjson.encode(matchInfoTable),
    })
end

--- 快速开局（使用默认配置）
--- @param mapName string 地图名称
local function QuickStart(mapName)
    -- 使用默认参数：2人局，60秒超时
    return StartWithAI(mapName, 2, 60)
end

--------------------------------------------------------------------------------
-- 测试入口
--------------------------------------------------------------------------------

--- 快速匹配测试（立即开局，AI 补齐）
--- @param mapName string 地图名称（可选，默认使用 projectId）
--- @param playerNumber number 玩家数量（可选，默认1）
local function TestQuickMatch(mapName, playerNumber)
    print("==================== Quick Match Test ====================")

    -- 初始化
    if not Init() then
        print("[Test] Init failed, abort")
        return -1
    end

    -- 获取地图名称（从 lobby 获取项目 ID 作为默认地图名）
    if not mapName or mapName == "" then
        mapName = "TestMap"
        if lobby and lobby.GetProjectId then
            local projectId = lobby:GetProjectId()
            if projectId and projectId ~= "" then
                mapName = projectId
            end
        end
    end

    playerNumber = playerNumber or 1

    print("[Test] mapName: " .. mapName)
    print("[Test] playerNumber: " .. playerNumber)

    -- 发送快速匹配请求（immediately_start=true, 会立即开局并用 AI 补齐）
    local requestId = StartWithAI(mapName, playerNumber, 60)

    if requestId > 0 then
        print("[Test] Quick match request sent, requestId=" .. requestId)
        print("[Test] Waiting for server response...")
    else
        print("[Test] Failed to send quick match request")
    end

    print("========================================================")
    return requestId
end

--- 运行测试（只打印帮助信息）
local function RunTest()
    print("==================== StartGame Test ====================")

    -- 初始化
    if not Init() then
        print("[Test] Init failed, abort")
        return
    end

    -- 获取地图名称（从 lobby 获取项目 ID 作为默认地图名）
    local mapName = "TestMap"
    if lobby and lobby.GetProjectId then
        local projectId = lobby:GetProjectId()
        if projectId and projectId ~= "" then
            mapName = projectId
        end
    end

    print("[Test] Default mapName: " .. mapName)
    print("")
    print("[Test] Available functions:")
    print("  Example.TestQuickMatch()                -- 快速匹配测试（自动获取mapName，1人局）")
    print("  Example.TestQuickMatch('MapName')       -- 指定地图")
    print("  Example.TestQuickMatch('MapName', 2)    -- 指定地图和人数")
    print("  Example.QuickStart('MapName')           -- 快速开局（2人局）")
    print("  Example.StartWithAI('MapName', 4, 120)  -- 自定义参数")
    print("========================================================")
end

--------------------------------------------------------------------------------
-- 导出
--------------------------------------------------------------------------------

return {
    -- 初始化
    Init = Init,

    -- 发送方法
    SendStartGame = SendStartGame,
    QuickStart = QuickStart,
    StartWithAI = StartWithAI,

    -- 常量（供外部使用）
    PROTO_ID = PROTO_ID,
    MSG_TYPE = MSG_TYPE,

    -- 测试
    RunTest = RunTest,
    TestQuickMatch = TestQuickMatch,
}
