--[[
简单的游戏大厅使用示例

展示如何使用 LobbyManager 快速实现游戏大厅功能
]]

-- 导入库
local Lobby = require("urhox-libs.Lobby")

-- 全局变量
local lobbyMgr = nil
local scene_ = nil

-- 创建简单的 UI
local function CreateSimpleUI()
    local ui = GetUI()
    local cache = GetCache()
    local root = ui.root

    -- 显示鼠标
    local input = GetInput()
    if input then
        input.mouseVisible = true
    end

    -- 加载字体
    local font = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")
    if not font then
        font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    end

    -- 主容器
    local container = root:CreateChild("UIElement")
    container:SetAlignment(HA_CENTER, VA_CENTER)
    container:SetSize(600, 500)

    -- 背景
    local bg = container:CreateChild("BorderImage")
    bg:SetSize(600, 500)
    bg:SetStyle("Window")

    -- 标题
    local title = bg:CreateChild("Text")
    title:SetFont(font, 20)
    title.text = "Game Lobby Example"
    title:SetPosition(20, 10)
    title:SetColor(Color(0.3, 0.8, 1.0))

    local yPos = 50

    -- 创建房间按钮
    local createBtn = bg:CreateChild("Button")
    createBtn:SetStyle("Button")
    createBtn:SetSize(280, 40)
    createBtn:SetPosition(20, yPos)

    local createText = createBtn:CreateChild("Text")
    createText:SetFont(font, 14)
    createText.text = "Create Room"
    createText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(createBtn, "Released", function()
        print("Creating room...")
        lobbyMgr:CreateRoom({
            mapName = "p_ogma",
            maxPlayers = 4,
            mode = "pvp",
            onSuccess = function(roomId)
                print("Room created successfully! ID: " .. roomId)
            end,
            onError = function(errorCode)
                print("Failed to create room. Error: " .. errorCode)
            end
        })
    end)

    -- 快速匹配按钮
    local matchBtn = bg:CreateChild("Button")
    matchBtn:SetStyle("Button")
    matchBtn:SetSize(280, 40)
    matchBtn:SetPosition(310, yPos)

    local matchText = matchBtn:CreateChild("Text")
    matchText:SetFont(font, 14)
    matchText.text = "Quick Match"
    matchText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(matchBtn, "Released", function()
        print("Starting quick match...")
        lobbyMgr:StartMatch({
            mapName = "p_ogma",
            mode = "ranked",
            onMatchFound = function(serverInfo)
                print("Match found! Server: " .. serverInfo.ip .. ":" .. serverInfo.port)
                print("Connecting to game server...")
                lobbyMgr:ConnectToGame(scene_)
            end,
            onError = function(errorCode)
                print("Match failed. Error: " .. errorCode)
            end
        })
    end)

    yPos = yPos + 50

    -- 取消匹配按钮
    local cancelBtn = bg:CreateChild("Button")
    cancelBtn:SetStyle("Button")
    cancelBtn:SetSize(280, 40)
    cancelBtn:SetPosition(20, yPos)

    local cancelText = cancelBtn:CreateChild("Text")
    cancelText:SetFont(font, 14)
    cancelText.text = "Cancel Match"
    cancelText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(cancelBtn, "Released", function()
        print("Canceling match...")
        lobbyMgr:CancelMatch()
    end)

    -- 离开房间按钮
    local leaveBtn = bg:CreateChild("Button")
    leaveBtn:SetStyle("Button")
    leaveBtn:SetSize(280, 40)
    leaveBtn:SetPosition(310, yPos)

    local leaveText = leaveBtn:CreateChild("Text")
    leaveText:SetFont(font, 14)
    leaveText.text = "Leave Room"
    leaveText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(leaveBtn, "Released", function()
        print("Leaving room...")
        lobbyMgr:LeaveRoom({
            onSuccess = function()
                print("Left room successfully")
            end
        })
    end)

    yPos = yPos + 50

    -- 开始游戏按钮（房主）
    local startBtn = bg:CreateChild("Button")
    startBtn:SetStyle("Button")
    startBtn:SetSize(570, 40)
    startBtn:SetPosition(20, yPos)

    local startText = startBtn:CreateChild("Text")
    startText:SetFont(font, 14)
    startText.text = "Start Game (Room Owner)"
    startText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(startBtn, "Released", function()
        print("Starting game...")
        lobbyMgr:StartGame({
            mapName = "p_ogma",
            mode = "pvp",
            onGameStarted = function(serverInfo)
                print("Game started! Server: " .. serverInfo.ip .. ":" .. serverInfo.port)
                print("Connecting to game server...")
                lobbyMgr:ConnectToGame(scene_)
            end,
            onError = function(errorCode)
                print("Failed to start game. Error: " .. errorCode)
            end
        })
    end)

    yPos = yPos + 60

    -- 状态显示
    local statusLabel = bg:CreateChild("Text")
    statusLabel:SetFont(font, 12)
    statusLabel.text = "Status:"
    statusLabel:SetPosition(20, yPos)
    statusLabel:SetColor(Color(0.7, 0.7, 0.7))

    yPos = yPos + 20

    local statusText = bg:CreateChild("Text")
    statusText:SetFont(font, 12)
    statusText:SetPosition(20, yPos)
    statusText:SetColor(Color(0.9, 0.9, 0.9))

    -- 定时更新状态
    SubscribeToEvent("Update", function(eventType, eventData)
        local status = {}
        table.insert(status, "User ID: " .. tostring(lobbyMgr:GetMyUserId()))
        table.insert(status, "Online: " .. tostring(lobbyMgr:IsOnline()))
        table.insert(status, "In Room: " .. tostring(lobbyMgr:IsInRoom()))
        table.insert(status, "Matching: " .. tostring(lobbyMgr:IsMatching()))

        if lobbyMgr:GetCurrentRoomId() then
            table.insert(status, "Room ID: " .. tostring(lobbyMgr:GetCurrentRoomId()))
        end

        statusText.text = table.concat(status, "\n")
    end)

    yPos = yPos + 120

    -- 说明文本
    local helpText = bg:CreateChild("Text")
    helpText:SetFont(font, 11)
    helpText.text = [[Instructions:
1. Create Room - Create a new game room
2. Quick Match - Find a match automatically
3. Leave Room - Exit current room
4. Start Game - (Room owner only) Start the game]]
    helpText:SetPosition(20, yPos)
    helpText:SetColor(Color(0.6, 0.6, 0.6))
end

-- 主函数
function Start()
    print("==============================================")
    print("  Lobby Library - Simple Example")
    print("==============================================")

    -- 创建场景（用于连接游戏服务器）
    scene_ = Scene()

    -- 创建 LobbyManager 实例
    lobbyMgr = Lobby.new({
        debugMode = true,           -- 启用调试输出
        defaultRegion = "cn-east",  -- 默认区域
    })

    -- 设置全局回调
    lobbyMgr:OnError(function(operation, errorCode)
        print(string.format("ERROR: %s failed with code %d", operation, errorCode))
    end)

    -- 创建 UI
    CreateSimpleUI()

    print("Lobby Manager initialized. User ID: " .. lobbyMgr:GetMyUserId())
end
