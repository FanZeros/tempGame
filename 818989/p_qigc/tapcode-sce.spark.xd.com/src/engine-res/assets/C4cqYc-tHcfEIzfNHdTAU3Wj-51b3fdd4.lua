--[[
房间列表示例

展示如何实现房间浏览和加入功能
]]

-- 导入库
local Lobby = require("urhox-libs.Lobby")

-- 全局变量
local lobbyMgr = nil
local scene_ = nil
local roomListContainer = nil
local roomData = {}

-- 解析房间列表数据
local function ParseRoomList(data)
    -- data 是 MsgPack 或 JSON 格式的房间列表
    -- 这里需要根据实际服务器返回格式解析

    -- 示例解析（假设返回的是 JSON 格式）
    local success, rooms = pcall(function()
        return cjson.decode(data)
    end)

    if not success then
        print("Failed to parse room list: " .. tostring(rooms))
        return {}
    end

    return rooms or {}
end

-- 刷新房间列表显示
local function RefreshRoomListUI()
    if not roomListContainer then
        return
    end

    -- 清空旧内容
    roomListContainer:RemoveAllChildren()

    if #roomData == 0 then
        local emptyText = roomListContainer:CreateChild("Text")
        emptyText:SetFont(GetCache():GetResource("Font", "Fonts/MiSans-Regular.ttf"), 14)
        emptyText.text = "No rooms available. Create one!"
        emptyText:SetPosition(10, 10)
        emptyText:SetColor(Color(0.7, 0.7, 0.7))
        return
    end

    local yPos = 10

    for i, room in ipairs(roomData) do
        -- 房间容器
        local roomItem = roomListContainer:CreateChild("UIElement")
        roomItem:SetSize(540, 60)
        roomItem:SetPosition(10, yPos)

        -- 背景
        local bg = roomItem:CreateChild("BorderImage")
        bg:SetSize(540, 60)
        bg:SetStyle("Button")

        -- 房间名称
        local nameText = bg:CreateChild("Text")
        nameText:SetFont(GetCache():GetResource("Font", "Fonts/MiSans-Regular.ttf"), 14)
        nameText.text = string.format("Room #%d - %s", room.id or i, room.mapName or "Unknown")
        nameText:SetPosition(10, 5)
        nameText:SetColor(Color(1, 1, 1))

        -- 玩家数量
        local playersText = bg:CreateChild("Text")
        playersText:SetFont(GetCache():GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)
        playersText.text = string.format("Players: %d/%d", room.playerCount or 0, room.maxPlayers or 4)
        playersText:SetPosition(10, 25)
        playersText:SetColor(Color(0.8, 0.8, 0.8))

        -- 模式
        local modeText = bg:CreateChild("Text")
        modeText:SetFont(GetCache():GetResource("Font", "Fonts/MiSans-Regular.ttf"), 12)
        modeText.text = "Mode: " .. (room.mode or "unknown")
        modeText:SetPosition(10, 40)
        modeText:SetColor(Color(0.7, 0.9, 1.0))

        -- 加入按钮
        local joinBtn = bg:CreateChild("Button")
        joinBtn:SetStyle("Button")
        joinBtn:SetSize(100, 40)
        joinBtn:SetPosition(430, 10)

        local joinText = joinBtn:CreateChild("Text")
        joinText:SetFont(GetCache():GetResource("Font", "Fonts/MiSans-Regular.ttf"), 14)
        joinText.text = "Join"
        joinText:SetAlignment(HA_CENTER, VA_CENTER)

        -- 加入按钮点击事件
        SubscribeToEvent(joinBtn, "Released", function()
            print("Joining room " .. (room.id or i))
            lobbyMgr:JoinRoom({
                roomId = room.id or 0,
                onSuccess = function(data)
                    print("Joined room successfully!")
                end,
                onError = function(errorCode)
                    print("Failed to join room. Error: " .. errorCode)
                end
            })
        end)

        yPos = yPos + 65
    end
end

-- 创建 UI
local function CreateUI()
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
    container:SetSize(600, 600)

    -- 背景
    local bg = container:CreateChild("BorderImage")
    bg:SetSize(600, 600)
    bg:SetStyle("Window")

    -- 标题
    local title = bg:CreateChild("Text")
    title:SetFont(font, 20)
    title.text = "Room Browser"
    title:SetPosition(20, 10)
    title:SetColor(Color(0.3, 0.8, 1.0))

    -- 刷新按钮
    local refreshBtn = bg:CreateChild("Button")
    refreshBtn:SetStyle("Button")
    refreshBtn:SetSize(120, 35)
    refreshBtn:SetPosition(350, 10)

    local refreshText = refreshBtn:CreateChild("Text")
    refreshText:SetFont(font, 14)
    refreshText.text = "Refresh"
    refreshText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(refreshBtn, "Released", function()
        print("Refreshing room list...")
        lobbyMgr:GetRoomList({
            limit = 10,
            includePrivate = false,
            onSuccess = function(data)
                print("Room list received")
                roomData = ParseRoomList(data)
                RefreshRoomListUI()
            end,
            onError = function(errorCode)
                print("Failed to get room list. Error: " .. errorCode)
            end
        })
    end)

    -- 创建房间按钮
    local createBtn = bg:CreateChild("Button")
    createBtn:SetStyle("Button")
    createBtn:SetSize(100, 35)
    createBtn:SetPosition(480, 10)

    local createText = createBtn:CreateChild("Text")
    createText:SetFont(font, 14)
    createText.text = "Create"
    createText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(createBtn, "Released", function()
        print("Creating new room...")
        lobbyMgr:CreateRoom({
            mapName = "p_ogma",
            maxPlayers = 4,
            mode = "pvp",
            onSuccess = function(roomId)
                print("Room created! ID: " .. roomId)
                -- 刷新房间列表
                refreshBtn:SendEvent("Released")
            end,
            onError = function(errorCode)
                print("Failed to create room. Error: " .. errorCode)
            end
        })
    end)

    -- 房间列表容器（滚动区域）
    local scrollView = bg:CreateChild("ScrollView")
    scrollView:SetStyle("ScrollView")
    scrollView:SetSize(560, 480)
    scrollView:SetPosition(20, 60)
    scrollView:SetScrollBarsVisible(false, true)

    roomListContainer = scrollView:CreateChild("UIElement")
    roomListContainer:SetSize(540, 2000)
    roomListContainer:SetLayout(LM_VERTICAL, 5, IntRect(5, 5, 5, 5))

    -- 底部状态栏
    local statusBar = bg:CreateChild("UIElement")
    statusBar:SetSize(560, 30)
    statusBar:SetPosition(20, 560)

    local statusText = statusBar:CreateChild("Text")
    statusText:SetFont(font, 12)
    statusText:SetColor(Color(0.7, 0.7, 0.7))

    -- 定时更新状态
    SubscribeToEvent("Update", function(eventType, eventData)
        local status = string.format("Online: %s | In Room: %s | Rooms: %d",
            tostring(lobbyMgr:IsOnline()),
            tostring(lobbyMgr:IsInRoom()),
            #roomData)
        statusText.text = status
    end)
end

-- 主函数
function Start()
    print("==============================================")
    print("  Lobby Library - Room List Example")
    print("==============================================")

    -- 创建场景
    scene_ = Scene()

    -- 创建 LobbyManager
    lobbyMgr = Lobby.new({
        debugMode = true,
        defaultRegion = "cn-east",
    })

    -- 设置全局回调
    lobbyMgr:OnRoomJoined(function(data)
        print("Successfully joined a room!")
    end)

    lobbyMgr:OnError(function(operation, errorCode)
        print(string.format("ERROR: %s failed with code %d", operation, errorCode))
    end)

    -- 创建 UI
    CreateUI()

    -- 自动刷新房间列表
    print("Auto-refreshing room list...")
    lobbyMgr:GetRoomList({
        limit = 10,
        includePrivate = false,
        onSuccess = function(data)
            print("Initial room list received")
            roomData = ParseRoomList(data)
            RefreshRoomListUI()
        end,
        onError = function(errorCode)
            print("Failed to get initial room list. Error: " .. errorCode)
        end
    })
end
