--[[
完整的开箱即用游戏大厅示例

展示如何使用 LobbyUI 一行代码启动完整的游戏大厅界面
]]

-- 导入库
local LobbyUI = require("urhox-libs.Lobby.LobbyUI")

-- 全局场景（用于连接游戏服务器）
local gameScene = nil

-- 主函数
function Start()
    print("==============================================")
    print("  Lobby Library - Complete UI Example")
    print("==============================================")

    -- 创建用于游戏连接的场景
    gameScene = Scene()

    -- 方式1: 最简单用法，使用默认配置
    -- LobbyUI.Show()

    -- 方式2: 自定义配置
    LobbyUI.Show({
        -- 场景（用于连接游戏服务器）
        scene = gameScene,
        -- 游戏配置
        mapName = "p_lstest_1",          -- 默认地图
        maxPlayers = 4,              -- 默认最大玩家数（用于匹配的 player_number）
        mode = "pvp",                -- 默认游戏模式

        -- 匹配配置（matchInfo）
        matchDescName = "free_match", -- 匹配模式描述名（desc_name）
        modeId = "custom_mode_001",   -- 自定义模式 ID（mode_id）

        -- UI 配置
        theme = "dark",              -- 主题："light" 或 "dark"
        debugMode = true,            -- 启用调试日志

        -- 功能开关
        allowCreateRoom = true,      -- 允许创建房间
        allowQuickMatch = true,      -- 允许快速匹配
        allowBrowseRooms = true,     -- 允许浏览房间列表

        -- 自动刷新
        autoRefresh = true,          -- 自动刷新房间列表
        refreshInterval = 5000,      -- 刷新间隔（毫秒）

        -- 游戏开始回调
        onGameStart = function(serverInfo)
            print("Game starting!")
            print("Server: " .. serverInfo.ip .. ":" .. serverInfo.port)
            print("Session ID: " .. serverInfo.sessionId)
            print("Map: " .. serverInfo.mapName)

            -- 在这里可以：
            -- 1. 加载游戏场景
            -- 2. 显示加载界面
            -- 3. 连接到游戏服务器（LobbyUI 会自动调用 ConnectToGame）

            -- 示例：加载游戏场景
            -- local scene = LoadGameScene(serverInfo.mapName)
            -- ShowLoadingScreen()
        end
    })

    print("LobbyUI initialized")
    print("The complete lobby interface is now active!")
    print("")
    print("Features available:")
    print("  • Quick Match - Find a match automatically")
    print("  • Browse Rooms - View and join available rooms")
    print("  • Create Room - Host your own game room")
    print("")
    print("All UI interactions are handled automatically!")
end

-- 可选：退出游戏时隐藏 UI
function Stop()
    if LobbyUI.IsVisible() then
        LobbyUI.Hide()
    end
end
