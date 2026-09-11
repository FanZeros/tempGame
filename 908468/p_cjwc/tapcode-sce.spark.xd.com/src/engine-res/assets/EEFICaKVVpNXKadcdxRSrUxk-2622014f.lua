---@diagnostic disable: undefined-global, undefined-field, undefined-doc-name, missing-parameter
--[[
LobbyUI.lua - Out-of-box game lobby UI component

Provides complete lobby interface including:
- Quick match
- Room browser
- Create room
- Room details
- Match waiting

Runtime usage:
    -- 联机 Runtime 由 LobbyRuntimeUI 自动启动；配置由引擎平台推送一次后传给 Show(config)。
    -- 下面的手动入口用于独立测试 / 自行驱动。

Manual example:
    local LobbyUI = require("urhox-libs.GameLobby.Runtime.Template.LobbyUI")

    LobbyUI.Show()
]]

local BaseUI = require("urhox-libs.UI")
local LobbyWidgetExtension = require("urhox-libs.GameLobby.Runtime.WidgetExtension")
local UI = setmetatable({}, { __index = BaseUI })
for name, widget in pairs(LobbyWidgetExtension) do
    UI[name] = widget
end
local Toast = require("urhox-libs.UI.Widgets.Toast")
local LobbyUISandbox = require("urhox-libs.GameLobby.Runtime.Template.LobbyUISandbox")
local LobbySystemDialogs = require("urhox-libs.GameLobby.Runtime.LobbySystemDialogs")
local SystemNotification = require("urhox-libs.System.SystemNotification")

-- 项目版本号：直接取引擎全局（GetProjectVersion / -game_version 回退）。
-- 用于匹配 mode_id 的 project_version，保证不同版本玩家不进同一桶。
local function GetLobbyProjectVersion()
    if GetProjectVersion then
        local ver = GetProjectVersion()
        if ver and ver ~= "" then return ver end
    end
    if GetArguments then
        local args = GetArguments()
        for i, a in ipairs(args) do
            if a == "-game_version" or a == "--game_version" then
                return args[i + 1] or ""
            end
        end
    end
    return ""
end

-- 制作人自定义大厅 UI 沙箱实例（项目脚本固定为 lobby_ui.lua）
local lobbyUISandbox = nil

-- 统一错误日志（引擎规范 log:Write(LOG_ERROR)，不可用时回退 print）
local function LobbyLogError(msg)
    msg = "[LobbyUI] " .. tostring(msg)
    if log and LOG_ERROR then log:Write(LOG_ERROR, msg) else print(msg) end
end

-- ============================================================================
-- LobbyUI 主模块
-- ============================================================================

local LobbyUI = {}

-- ============================================================================
-- Constants and default configuration
-- ============================================================================

local PROJECT_LOBBY_UI_FILE = "lobby_ui.lua"

local DEFAULT_CONFIG = {
    mapName = nil,                -- Will use lobbyClient:GetProjectId() if not specified
    maxPlayers = nil,             -- Will use lobbyClient:GetMaxPlayers() if not specified, fallback to 4
    mode = "pvp",
    theme = "dark",               -- "light" or "dark"
    debugMode = false,
    allowCreateRoom = true,       -- Allow room creation
    allowQuickMatch = true,       -- Allow quick match
    allowBrowseRooms = true,      -- Allow browsing rooms
    autoRefresh = true,           -- Auto refresh room list
    refreshInterval = 5000,       -- Refresh interval (milliseconds)

    -- Match info configuration (for matchmaking)
    matchDescName = "free_match_with_ai", -- 匹配模式描述名
    modeId = "pvp",               -- 自定义模式 ID
}

local currentConfig = nil

-- Theme configuration (using {r, g, b, a} format for UI library compatibility)
local THEMES = {
    light = {
        primary = { 51, 153, 255, 255 },       -- rgb(0.2, 0.6, 1.0)
        secondary = { 128, 128, 128, 255 },    -- rgb(0.5, 0.5, 0.5)
        background = { 242, 242, 242, 255 },   -- rgb(0.95, 0.95, 0.95)
        surface = { 255, 255, 255, 255 },      -- rgb(1.0, 1.0, 1.0)
        text = { 26, 26, 26, 255 },            -- rgb(0.1, 0.1, 0.1)
        textSecondary = { 128, 128, 128, 255 },-- rgb(0.5, 0.5, 0.5)
        border = { 204, 204, 204, 255 },       -- rgb(0.8, 0.8, 0.8)
        success = { 51, 204, 77, 255 },        -- rgb(0.2, 0.8, 0.3)
        warning = { 255, 179, 0, 255 },        -- rgb(1.0, 0.7, 0.0)
        error = { 255, 77, 77, 255 },          -- rgb(1.0, 0.3, 0.3)
    },
    dark = {
        primary = { 77, 179, 255, 255 },       -- rgb(0.3, 0.7, 1.0)
        secondary = { 153, 153, 153, 255 },    -- rgb(0.6, 0.6, 0.6)
        background = { 38, 38, 38, 255 },      -- rgb(0.15, 0.15, 0.15)
        surface = { 51, 51, 51, 255 },         -- rgb(0.2, 0.2, 0.2)
        text = { 242, 242, 242, 255 },         -- rgb(0.95, 0.95, 0.95)
        textSecondary = { 179, 179, 179, 255 },-- rgb(0.7, 0.7, 0.7)
        border = { 77, 77, 77, 255 },          -- rgb(0.3, 0.3, 0.3)
        success = { 77, 230, 102, 255 },       -- rgb(0.3, 0.9, 0.4)
        warning = { 255, 204, 51, 255 },       -- rgb(1.0, 0.8, 0.2)
        error = { 255, 102, 102, 255 },        -- rgb(1.0, 0.4, 0.4)
    }
}

-- Input validation constants
local MIN_MAX_PLAYERS = 1
local MAX_MAX_PLAYERS = 16

-- ============================================================================
-- LobbyUI instance
-- ============================================================================

local LobbyUIInstance = {
    root = nil,
    externalRoot = false,     -- root 是否由 引擎引导层 注入（true 则 Hide 只清子树不销毁）
    lobbyClient = nil,
    config = nil,
    theme = nil,
    currentView = nil,
    currentScreenName = nil,  -- 当前界面 ID（供沙箱 OnScreenChanged 使用）
    roomListData = {},
    refreshTimer = 0,
    eventSubscriptions = {},  -- Track event subscriptions for cleanup
    autoRefreshTimer = 0,     -- Auto refresh timer
    roomListRefreshSubscription = nil,
    viewGeneration = 0,
}

-- ============================================================================
-- Helper functions
-- ============================================================================

local function Log(msg)
    if LobbyUIInstance.config and LobbyUIInstance.config.debugMode then
        print("[LobbyUI] " .. msg)
    end
end

local readOnlyConfigProxyCache = setmetatable({}, { __mode = "k" })

local function MakeReadOnlyTableView(source, label)
    if type(source) ~= "table" then
        return source
    end
    local cached = readOnlyConfigProxyCache[source]
    if cached then
        return cached
    end

    local proxy = {}
    readOnlyConfigProxyCache[source] = proxy
    setmetatable(proxy, {
        __index = function(_, key)
            return MakeReadOnlyTableView(source[key], label .. "." .. tostring(key))
        end,
        __newindex = function()
            error(label .. " is read-only", 2)
        end,
        __pairs = function()
            local function iter(_, key)
                local nextKey, value = next(source, key)
                if nextKey ~= nil then
                    value = MakeReadOnlyTableView(value, label .. "." .. tostring(nextKey))
                end
                return nextKey, value
            end
            return iter, nil, nil
        end,
        __len = function()
            return #source
        end,
        __metatable = "locked",
    })
    return proxy
end

local function MakeReadOnlyConfig(config)
    -- Lobby.config 是框架运行配置：制作人脚本可读它来适配界面，
    -- 但建房/匹配等真实动作仍必须使用框架原值，不能让沙箱脚本改内部表。
    return MakeReadOnlyTableView(config or {}, "Lobby.config")
end

local function MergeConfig(config)
    local out = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        out[k] = v
    end
    for k, v in pairs(config or {}) do
        if v ~= nil then
            out[k] = v
        end
    end
    return out
end

--- Simple JSON decoder for parsing JSON strings to Lua tables
--- @param str string JSON string to decode
--- @return any Decoded value
local function jsonDecode(str)
    if not str or str == "" then
        return nil
    end

    local pos = 1
    local len = #str

    local function skipWhitespace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
                pos = pos + 1
            else
                break
            end
        end
    end

    local function parseValue()
        skipWhitespace()
        if pos > len then return nil end

        local c = str:sub(pos, pos)

        if c == '"' then
            -- Parse string
            pos = pos + 1
            local startPos = pos
            local result = ""
            while pos <= len do
                local ch = str:sub(pos, pos)
                if ch == '"' then
                    pos = pos + 1
                    return result
                elseif ch == '\\' then
                    pos = pos + 1
                    local escaped = str:sub(pos, pos)
                    if escaped == 'n' then result = result .. '\n'
                    elseif escaped == 'r' then result = result .. '\r'
                    elseif escaped == 't' then result = result .. '\t'
                    elseif escaped == '"' then result = result .. '"'
                    elseif escaped == '\\' then result = result .. '\\'
                    else result = result .. escaped
                    end
                    pos = pos + 1
                else
                    result = result .. ch
                    pos = pos + 1
                end
            end
            return result
        elseif c == '{' then
            -- Parse object
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            while pos <= len do
                skipWhitespace()
                local key = parseValue()
                skipWhitespace()
                if str:sub(pos, pos) == ':' then
                    pos = pos + 1
                end
                local value = parseValue()
                obj[key] = value
                skipWhitespace()
                local sep = str:sub(pos, pos)
                if sep == ',' then
                    pos = pos + 1
                elseif sep == '}' then
                    pos = pos + 1
                    return obj
                else
                    break
                end
            end
            return obj
        elseif c == '[' then
            -- Parse array
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while pos <= len do
                local value = parseValue()
                table.insert(arr, value)
                skipWhitespace()
                local sep = str:sub(pos, pos)
                if sep == ',' then
                    pos = pos + 1
                elseif sep == ']' then
                    pos = pos + 1
                    return arr
                else
                    break
                end
            end
            return arr
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif c == '-' or (c >= '0' and c <= '9') then
            -- Parse number
            local numStr = ""
            while pos <= len do
                local ch = str:sub(pos, pos)
                if ch == '-' or ch == '+' or ch == '.' or ch == 'e' or ch == 'E' or (ch >= '0' and ch <= '9') then
                    numStr = numStr .. ch
                    pos = pos + 1
                else
                    break
                end
            end
            return tonumber(numStr)
        end

        return nil
    end

    return parseValue()
end

local function ParseRoomList(data)
    -- Parse room list data
    if type(data) == "table" then
        return data
    end
    if not data or data == "" then
        return {}
    end

    Log("ParseRoomList raw data: " .. tostring(data):sub(1, 200))

    local success, rooms = pcall(function()
        return jsonDecode(data)
    end)

    if not success then
        Log("Failed to parse room list: " .. tostring(rooms))
        return {}
    end

    -- Ensure we always return a table (array)
    if type(rooms) ~= "table" then
        Log("ParseRoomList: result is not a table, got " .. type(rooms))
        return {}
    end

    Log("ParseRoomList: got " .. #rooms .. " rooms")
    return rooms
end

-- Validate max players input
local function ValidateMaxPlayers(value)
    local num = tonumber(value)
    if not num then
        return false, "Invalid number"
    end
    if num < MIN_MAX_PLAYERS or num > MAX_MAX_PLAYERS then
        return false, string.format("Must be between %d and %d", MIN_MAX_PLAYERS, MAX_MAX_PLAYERS)
    end
    return true, num
end

-- Format number as integer string (removes .0 suffix)
local function FormatInt(num)
    if num == nil then return "0" end
    return string.format("%d", math.floor(num))
end

-- Clean up event subscriptions
local function CleanupEventSubscriptions()
    for _, subscription in ipairs(LobbyUIInstance.eventSubscriptions) do
        if subscription then
            UnsubscribeFromEvent(subscription)
        end
    end
    LobbyUIInstance.eventSubscriptions = {}
    LobbyUIInstance.roomListRefreshSubscription = nil
end

-- Subscribe to event and track it
local function TrackEventSubscription(eventName, callback)
    local subscription = SubscribeToEvent(eventName, callback)
    table.insert(LobbyUIInstance.eventSubscriptions, subscription)
    return subscription
end

local function UntrackEventSubscription(subscription)
    if not subscription then
        return
    end
    UnsubscribeFromEvent(subscription)
    for i = #LobbyUIInstance.eventSubscriptions, 1, -1 do
        if LobbyUIInstance.eventSubscriptions[i] == subscription then
            table.remove(LobbyUIInstance.eventSubscriptions, i)
            break
        end
    end
end

local function StopRoomListAutoRefresh()
    if LobbyUIInstance.roomListRefreshSubscription then
        UntrackEventSubscription(LobbyUIInstance.roomListRefreshSubscription)
        LobbyUIInstance.roomListRefreshSubscription = nil
    end
end

local function AdvanceViewGeneration()
    LobbyUIInstance.viewGeneration = (LobbyUIInstance.viewGeneration or 0) + 1
    return LobbyUIInstance.viewGeneration
end

local function IsViewGenerationActive(generation)
    return LobbyUIInstance.viewGeneration == generation
end

local function CleanupRoomWaitingHandlers()
    -- 房间流程回调挂在 LobbyUIInstance 上，由 CreateRoom/JoinRoom 的内联 onPlayersChanged/onKicked 委派；
    -- 离开 / 切屏时清掉即停止接收（client 侧 _room 也会在 LeaveRoom/roomLeft 时清）。
    LobbyUIInstance.onRoomPlayers = nil
    LobbyUIInstance.onRoomKicked = nil
end

local function PrepareScreenSwitch(prevScreen)
    AdvanceViewGeneration()
    if prevScreen == "room_waiting" then
        CleanupRoomWaitingHandlers()
    end
end

-- ============================================================================
-- UI building functions
-- ============================================================================

-- Forward declarations
local CreateMainView
local CreateMatchingView
local CreateRoomBrowserView
local CreateRoomDetailView
local CreateCreateRoomDialog
local CreateServerProgressView
local CreateConnectingView
local ShowMatchFoundDialog
local ShowErrorDialog
local StartGameFromRoom
local ConnectToGameServer
local CreateTopBar
local RefreshRoomListGlobal   -- 房间列表刷新（提为文件级 local，供 CreateRoomBrowserView 与 Lobby.RefreshRoomList 共用）

-- Server progress view state
local serverProgressState = {
    view = nil,
    progressBar = nil,
    progressLabel = nil,
    statusLabel = nil,
}

--- 创建通用顶部栏（与大厅一致）
--- @param options table|nil 配置选项
---   - showBackButton: boolean 是否显示返回按钮（默认 false）
---   - onBack: function 返回按钮点击回调
---   - rightContent: Widget 右侧自定义内容（替代退出按钮）
--- @return Widget topBar, function updateStatus
CreateTopBar = function(options)
    options = options or {}

    -- 顶部条
    local topBar = UI.Panel {
        width = "100%",
        height = 190,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "flex-start",
        paddingLeft = 43,
        paddingRight = 43,
        paddingTop = 34,
        paddingBottom = 34,
    }

    -- 左侧：根据配置决定内容（退出/返回按钮）
    if options.hideRightButton then
        -- 添加占位符保持布局（与右侧占位一致）
        topBar:AddChild(UI.Panel {
            width = 120,
            height = 50,
        })
    elseif options.showBackButton then
        -- 返回按钮样式选择
        local buttonText = options.buttonText or _tr("t_qNlgG5bPpwC8vWgM")
        local useGhostStyle = options.ghostStyle ~= false  -- 默认使用幽灵样式
        local useOutlinedStyle = options.outlinedStyle == true  -- 描边样式（用于"离开"）

        local backBtn
        if useOutlinedStyle then
            -- 描边样式（用于"离开房间"等）
            backBtn = UI.Button {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 8,
                paddingLeft = 20,
                paddingRight = 20,
                paddingTop = 12,
                paddingBottom = 12,
                backgroundColor = { 0, 0, 0, 0 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 200, 120, 120, 100 },
                onClick = function()
                    if options.onBack then
                        options.onBack()
                    else
                        CreateMainView()
                    end
                end
            }
            topBar:AddChild(backBtn)

            backBtn:AddChild(UI.Icon { variant = "line",
                width = 20,
                height = 20,
                icon = "exit",
                color = { 200, 120, 120, 200 },
                strokeWidth = 2,
            })

            backBtn:AddChild(UI.Label {
                text = buttonText,
                fontSize = 18,
                fontColor = { 200, 120, 120, 200 },
            })
        elseif useGhostStyle then
            -- 幽灵样式（低调返回按钮，放大尺寸）
            backBtn = UI.Button {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 10,
                paddingLeft = 16,
                paddingRight = 24,
                paddingTop = 12,
                paddingBottom = 12,
                minWidth = 120,
                minHeight = 50,
                backgroundColor = { 0, 0, 0, 0 },
                borderRadius = 12,
                onClick = function()
                    Log("Back button clicked")
                    if options.onBack then
                        options.onBack()
                    else
                        CreateMainView()
                    end
                end
            }
            topBar:AddChild(backBtn)

            backBtn:AddChild(UI.Icon { variant = "line",
                width = 24,
                height = 24,
                icon = "back",
                color = { 180, 180, 200, 220 },
                strokeWidth = 3,
            })

            backBtn:AddChild(UI.Label {
                text = buttonText,
                fontSize = 20,
                fontColor = { 180, 180, 200, 220 },
            })
        else
            -- 原红色样式
            backBtn = UI.Button {
                width = 221,
                height = 72,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 2,
                backgroundColor = '#A71B0051',
                borderRadius = 36,
                borderWidth = 3,
                borderColor = '#BF878722',
                onClick = function()
                    if options.onBack then
                        options.onBack()
                    else
                        CreateMainView()
                    end
                end
            }
            topBar:AddChild(backBtn)

            backBtn:AddChild(UI.Icon { variant = "line",
                width = 38,
                height = 38,
                icon = "exit",
                color = { 255, 61, 61, 255 },
                strokeWidth = 2.5,
            })

            backBtn:AddChild(UI.Label {
                text = buttonText,
                fontSize = 32,
                fontWeight = "bold",
                fontColor = '#FF3D3D',
            })
        end
    else
        -- 默认退出按钮
        local exit_ui = UI.Button {
            width = 221,
            height = 72,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 2,
            backgroundColor = '#A71B0051',
            borderRadius = 36,
            borderWidth = 3,
            borderColor = '#BF878722',
            onClick = function()
                LobbyUI.Hide()
            end
        }
        topBar:AddChild(exit_ui)

        exit_ui:AddChild(UI.Icon { variant = "line",
            width = 38,
            height = 38,
            icon = "exit",
            color = { 255, 61, 61, 255 },
            strokeWidth = 2.5,
        })

        exit_ui:AddChild(UI.Label {
            text = _tr("t_10lhwdNB510ct1Qukc"),
            fontSize = 32,
            fontWeight = "bold",
            fontColor = '#FF3D3D',
        })
    end

    -- 中间区域：用于居中显示页面标题或玩家信息
    local centerArea = UI.Panel {
        flexGrow = 1,
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
    }
    topBar:AddChild(centerArea)

    -- 如果有页面标题，在 centerArea 中显示
    if options.pageTitle then
        centerArea:AddChild(UI.Label {
            text = options.pageTitle,
            fontSize = 24,
            fontWeight = "bold",
            fontColor = { 255, 255, 255, 255 },
        })
    end

    -- 用户信息卡片（如果没有页面标题则显示）
    local userCard = UI.Panel {
        flexDirection = "row",
        minWidth = 400,
        height = 104,
        alignItems = "center",
        backgroundColor = '#292B30',
        borderColor = '#FFFFFF21',
        borderWidth = 1,
        borderRadius = 52,
        paddingLeft = 15,
        paddingRight = 20,
        paddingTop = 15,
        paddingBottom = 15,
        gap = 15,
    }

    -- 头像容器（圆形）
    local avatarContainer = UI.Panel {
        width = 74,
        height = 74,
        borderRadius = 37,
        backgroundColor = { 200, 220, 240, 255 },
        alignItems = "center",
        justifyContent = "center",
        overflow = "hidden",
    }
    avatarContainer:AddChild(UI.Label {
        text = " ",
        fontSize = 32,
        fontWeight = "bold",
    })
    userCard:AddChild(avatarContainer)

    -- 用户信息（昵称、ID、状态）
    local userInfo = UI.Panel {
        flexDirection = "column",
        gap = 2,
        height = 104,
    }

    local userId = LobbyUIInstance.lobbyClient:GetMyUserId()

    -- 昵称行（最上面）
    local nicknameLabel = UI.Label {
        height = 36,
        text = _tr("t_19DCzy20319fRYubAY"),
        fontSize = 28,
        fontWeight = "bold",
        color = { 255, 255, 255, 255 },
    }
    userInfo:AddChild(nicknameLabel)

    -- 异步查询昵称
    local nicknameGeneration = LobbyUIInstance.viewGeneration
    LobbyUIInstance.lobbyClient:GetUserNickname({
        userIds = { userId },
        onSuccess = function(nicknames)
            if not IsViewGenerationActive(nicknameGeneration) or not nicknameLabel.node then return end
            if nicknames and #nicknames > 0 then
                local nickname = nicknames[1].nickname or ""
                if nickname == "" then
                    nickname = _tr("t_18zuRw7Pt18rnE6t2m")
                end
                nicknameLabel:SetText(nickname)
            end
        end,
        onError = function(errorCode)
            if not IsViewGenerationActive(nicknameGeneration) or not nicknameLabel.node then return end
            nicknameLabel:SetText(_tr("t_18zuRw7Pt18rnE6t2m"))
        end
    })

    -- ID行（中间）
    userInfo:AddChild(UI.Label {
        height = 28,
        text = "ID: " .. FormatInt(userId),
        fontSize = 20,
        color = { 180, 180, 200, 255 },
    })

    -- 在线状态行（最下面）
    local statusRow = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 3,
        height = 26,
    }

    local statusDot = UI.Panel {
        width = 14,
        height = 14,
        borderRadius = 7,
        backgroundColor = { 76, 217, 100, 255 },
        borderColor = '#ffffff',
        borderWidth = 1,
    }
    statusRow:AddChild(statusDot)

    local statusLabel = UI.Label {
        text = _tr("t_TC8HGd5dSlEt59E0"),
        fontSize = 18,
        color = { 76, 217, 100, 255 },
    }
    statusRow:AddChild(statusLabel)

    userInfo:AddChild(statusRow)
    userCard:AddChild(userInfo)

    -- 只在没有页面标题时显示用户信息卡片
    if not options.pageTitle then
        centerArea:AddChild(userCard)
    end

    -- 右侧占位（与左侧按钮宽度匹配，保持标题居中）
    topBar:AddChild(UI.Panel {
        width = 120,
        height = 50,
    })

    -- 更新状态函数
    local function updateStatus()
        local isOnline = LobbyUIInstance.lobbyClient:IsOnline()
        local isInRoom = LobbyUIInstance.lobbyClient:IsInRoom()
        local isMatching = LobbyUIInstance.lobbyClient:IsMatching()

        if isOnline then
            statusDot.backgroundColor = { 76, 217, 100, 255 }
            statusLabel.color = { 76, 217, 100, 255 }
        else
            statusDot.backgroundColor = { 255, 80, 80, 255 }
            statusLabel.color = { 255, 80, 80, 255 }
        end

        local statusTexts = {}
        if isOnline then
            table.insert(statusTexts, _tr("t_QXpKdJYYQPYgvCTz"))
        else
            table.insert(statusTexts, _tr("t_Rr1DCfnQRgKalIOL"))
        end

        if isInRoom then
            table.insert(statusTexts, _tr("t_oaiAoxPHp4i2BKLK"))
        end

        if isMatching then
            table.insert(statusTexts, _tr("t_WP2RNoJGVwrMSVxD"))
        end

        statusLabel:SetText(table.concat(statusTexts, " | "))
    end

    return topBar, updateStatus
end

-- ============================================================================
-- 业务动作：创建房间（框架层和默认模板共用）
-- ============================================================================

local function createRoomAction(config)
    local mapName = config.mapName
    if not mapName or mapName == "" then
        local projectId = LobbyUIInstance.lobbyClient:GetProjectId()
        mapName = (projectId and projectId ~= "") and projectId or "DefaultMap"
    end
    local maxPlayers = config.maxPlayers
    if not maxPlayers or maxPlayers <= 0 then
        local fromLobbyMgr = LobbyUIInstance.lobbyClient:GetMaxPlayers()
        maxPlayers = (fromLobbyMgr and fromLobbyMgr > 0) and fromLobbyMgr or 4
    end
    LobbyUIInstance.lobbyClient:CreateRoom({
        mapName = mapName, maxPlayers = maxPlayers, mode = config.mode,
        onCreated = function(roomId) CreateRoomDetailView(roomId, nil, maxPlayers) end,
        onError   = function(errorCode) ShowErrorDialog("Failed to create room: " .. FormatInt(errorCode)) end,
        onPlayersChanged = function(players, masterId) if LobbyUIInstance.onRoomPlayers then LobbyUIInstance.onRoomPlayers(players, masterId) end end,
        onKicked = function() if LobbyUIInstance.onRoomKicked then LobbyUIInstance.onRoomKicked() end end,
    })
end

-- ============================================================================
-- 框架层：功能骨架（自定义模式）
-- 只建透明 Panel + 透明功能 Button，不渲染任何视觉内容。
-- 制作人通过 style.left/top/width/height 定位，并挂载视觉子控件。
-- ============================================================================

local function createFunctionalSkeleton(config)
    -- 全屏透明画布，视觉子控件挂载在其上
    local view = UI.Panel {
        width  = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
    }

    -- 透明功能 Button（初始 0×0；不预设 left/top，制作人可用 left 或 right 自由锚定）
    local function makeInvisibleBtn(onClick)
        return UI.Button {
            position        = "absolute",
            width = 0, height = 0,
            text            = "",
            backgroundColor = { 0, 0, 0, 0 },
            onClick         = onClick,
        }
    end

    local quickBtn  = makeInvisibleBtn(config.allowQuickMatch  and CreateMatchingView or nil)
    local browseBtn = makeInvisibleBtn(config.allowBrowseRooms and CreateRoomBrowserView or nil)
    local createBtn = makeInvisibleBtn(config.allowCreateRoom  and function() createRoomAction(config) end or nil)
    -- 退出按钮：退出整个程序（与默认模板 Lobby.Exit 行为一致）。
    local exitBtn   = makeInvisibleBtn(function() engine:Exit() end)

    view:AddChild(quickBtn)
    view:AddChild(browseBtn)
    view:AddChild(createBtn)
    view:AddChild(exitBtn)

    return view, quickBtn, browseBtn, createBtn, exitBtn
end

-- ============================================================================
-- 默认模板（无项目大厅脚本时生效）
-- 视觉代码集中于此，框架层不含任何外观逻辑。
-- ============================================================================

local function createDefaultLayout(config)
    local view = UI.Panel {
        width           = "100%",
        height          = "100%",
        flexDirection   = "row",
        backgroundColor = { 20, 22, 35, 255 },
    }

    -- 左栏：Logo
    local leftPanel = UI.Panel {
        flexGrow        = 1,
        height          = "100%",
        flexDirection   = "column",
        justifyContent  = "flex-end",
        alignItems      = "flex-start",
        paddingLeft     = 60,
        paddingBottom   = 60,
    }
    view:AddChild(leftPanel)

    local hasIntl     = HasAppArgv and HasAppArgv("intl")
    local revisionArg = GetAppArgv and GetAppArgv("game_revision") or ""
    local useIntlLogo = hasIntl or revisionArg == "intl"
    leftPanel:AddChild(UI.Panel {
        width  = 360,
        height = 180,
        backgroundImage = useIntlLogo and "Textures/LogoLargeIntl.png" or "Textures/LogoLarge.png",
        backgroundFit = "fill",
    })

    -- 右栏：卡片列
    local rightPanel = UI.Panel {
        width          = 480,
        height         = "100%",
        flexDirection  = "column",
        justifyContent = "center",
        paddingRight   = 60,
        gap            = 14,
    }
    view:AddChild(rightPanel)

    local function makeCard(titleText, descText, portraitColor, onClickFn)
        local card = UI.Button {
            height          = 88,
            text            = "",
            flexDirection   = "row",
            alignItems      = "center",
            backgroundColor = { 12, 18, 38, 210 },
            borderRadius    = 14,
            borderWidth     = 1,
            borderColor     = { 60, 80, 140, 100 },
            paddingLeft     = 16,
            paddingRight    = 20,
            gap             = 14,
            onClick         = onClickFn,
        }
        card:AddChild(UI.Panel {
            width = 58, height = 58, borderRadius = 29,
            backgroundColor = portraitColor, flexShrink = 0,
        })
        local textArea = UI.Panel { flexGrow = 1, flexDirection = "column", gap = 5 }
        textArea:AddChild(UI.Label { text = titleText, fontSize = 20, fontWeight = "bold", color = { 240, 245, 255, 255 } })
        textArea:AddChild(UI.Label { text = descText,  fontSize = 13, color = { 160, 175, 210, 200 } })
        card:AddChild(textArea)
        card:AddChild(UI.Panel {
            width = 44, height = 44, borderRadius = 22,
            backgroundColor = portraitColor, flexShrink = 0,
        })
        return card
    end

    if config.allowQuickMatch  then rightPanel:AddChild(makeCard(_tr("t_3oLGvfnU4GMMCbw1"), _tr("t_a4k9RVz3Zc3QWCtY"), { 40, 80, 200, 220 }, CreateMatchingView)) end
    if config.allowBrowseRooms then rightPanel:AddChild(makeCard(_tr("t_oOFMYbK1oFxYSyYu"), _tr("t_YLzALCVKYpx0Vx95"),    { 20, 130, 140, 220 }, CreateRoomBrowserView)) end
    if config.allowCreateRoom  then rightPanel:AddChild(makeCard(_tr("t_1DSgBSUmlo9AcDt"), _tr("t_XaPZdHvhX6y0KoVY"),    { 170, 80, 20, 220 },  function() createRoomAction(config) end)) end

    local exitArea = UI.Panel { width = "100%", alignItems = "center", marginTop = 10 }
    exitArea:AddChild(UI.Button {
        width = 180, height = 44, text = _tr("t_lQr2vOEgkyF2NQ6R"), fontSize = 15,
        color = { 180, 185, 210, 200 }, backgroundColor = { 0, 0, 0, 70 },
        borderRadius = 22, borderWidth = 1, borderColor = { 80, 90, 130, 80 },
        onClick = function() LobbyUI.Hide() end,
    })
    rightPanel:AddChild(exitArea)

    return view
end

-- ============================================================================
-- CreateMainView：串联框架层与模板层
-- ============================================================================

--- Create main interface
CreateMainView = function()
    Log("Creating main view")
    StopRoomListAutoRefresh()
    local config     = LobbyUIInstance.config
    local prevScreen = LobbyUIInstance.currentScreenName
    PrepareScreenSwitch(prevScreen)

    -- 异步获取昵称，写入沙箱 LobbyState
    local userId = LobbyUIInstance.lobbyClient:GetMyUserId()
    local nicknameGeneration = LobbyUIInstance.viewGeneration
    LobbyUIInstance.lobbyClient:GetUserNickname({
        userIds   = { userId },
        onSuccess = function(nicknames)
            if lobbyUISandbox and IsViewGenerationActive(nicknameGeneration) and nicknames and #nicknames > 0 then
                lobbyUISandbox:SetSelfNickname(nicknames[1].nickname or "")
            end
        end,
        onError = function() end,
    })

    -- 框架层：功能骨架（沙箱始终存在，由 LobbyUI.Show 保证）
    local view, quickBtn, browseBtn, createBtn, exitBtn = createFunctionalSkeleton(config)

    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
        if lobbyUISandbox then lobbyUISandbox:UnregisterScreen(prevScreen) end
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView       = view
    LobbyUIInstance.currentScreenName = "main"

    if lobbyUISandbox then
        lobbyUISandbox:RegisterScreen("main", {
            background         = view,
            quick_match_button = quickBtn,
            browse_button      = browseBtn,
            create_button      = createBtn,
            exit_button        = exitBtn,
        })
        lobbyUISandbox:OnScreenChanged(prevScreen, "main")
    end

    return view
end

--- Create matching waiting interface
CreateMatchingView = function()
    Log("Starting quick match")

    local config = LobbyUIInstance.config
    local matchStartTime = os.time()  -- 记录开始时间

    -- 透明全屏背景
    local view = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
    }

    -- 透明取消按钮（沙箱负责定位和绘制）
    local cancelBtn = UI.Button {
        position = "absolute",
        width = 0, height = 0,
        text = "",
        backgroundColor = { 0, 0, 0, 0 },
        onClick = function()
            Log("Canceling match")
            LobbyUIInstance.lobbyClient:CancelMatch()
            CreateMainView()
        end
    }
    view:AddChild(cancelBtn)

    -- 不可见状态文本（沙箱可读写）
    local statusLabel = UI.Label { visible = false, text = "" }
    view:AddChild(statusLabel)

    -- Switch to matching view
    local prevScreen = LobbyUIInstance.currentScreenName
    PrepareScreenSwitch(prevScreen)
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
        if lobbyUISandbox and prevScreen then
            lobbyUISandbox:UnregisterScreen(prevScreen)
        end
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view
    LobbyUIInstance.currentScreenName = "quick_match_waiting"

    -- 沙箱：注册 quick_match_waiting 界面控件 + 触发 onScreenChanged + 设置匹配状态
    if lobbyUISandbox then
        lobbyUISandbox:RegisterScreen("quick_match_waiting", {
            background    = view,
            status_text   = statusLabel,
            cancel_button = cancelBtn,
        })
        lobbyUISandbox:OnScreenChanged(prevScreen, "quick_match_waiting")
        lobbyUISandbox:OnMatchmakingChanged("searching")
    end

    -- Get max players: config.maxPlayers -> lobbyClient:GetMaxPlayers() -> 4
    local matchMaxPlayers = config.maxPlayers
    if not matchMaxPlayers or matchMaxPlayers <= 0 then
        local fromLobbyMgr = LobbyUIInstance.lobbyClient:GetMaxPlayers()
        matchMaxPlayers = (fromLobbyMgr and fromLobbyMgr > 0) and fromLobbyMgr or 4
    end

    -- Start matching with matchInfo
    local extMatchInfo = config.matchInfo or {}
    local descName = extMatchInfo.desc_name or config.matchDescName or "free_match_with_ai"
    local playerNumber = extMatchInfo.player_number or matchMaxPlayers
    local immediatelyStart = extMatchInfo.immediately_start ~= nil and extMatchInfo.immediately_start or false
    local matchTimeout = extMatchInfo.match_timeout or config.matchTimeout or 60
    -- 手动构建固定顺序的 mode_id（Lua 表遍历顺序不固定）
    -- 补齐 project_version，保证不同版本的玩家不会被匹配到同一桶。
    local projectVersion = GetLobbyProjectVersion()
    local modeId = string.format(
        '{"desc_name":"%s","immediately_start":%s,"match_timeout":%d,"player_number":%d,"project_version":"%s"}',
        descName, tostring(immediatelyStart), matchTimeout, playerNumber, projectVersion)
    local matchInfo = {
        desc_name = descName,
        player_number = playerNumber,
        immediately_start = immediatelyStart,
        match_timeout = matchTimeout,
        mode_id = modeId,
    }

    local matchParams = {
        mapName = config.mapName,
        mode = config.mode,
        matchInfo = matchInfo,
    }

    Log("StartMatch params: mapName=" .. tostring(matchParams.mapName)
        .. ", mode=" .. tostring(matchParams.mode)
        .. ", player_number=" .. tostring(matchParams.matchInfo.player_number)
        .. ", mode_id=" .. tostring(matchParams.matchInfo.mode_id)
        .. ", desc_name=" .. tostring(matchParams.matchInfo.desc_name)
        .. ", match_timeout=" .. tostring(matchParams.matchInfo.match_timeout))

    -- 定义开始匹配的函数
    local function doStartMatch()
        local requestId = LobbyUIInstance.lobbyClient:StartMatch({
            mapName = matchParams.mapName,
            mode = matchParams.mode,
            matchInfo = matchParams.matchInfo,
            onMatchFound = function(serverInfo)
                Log("Match found!")
                Log("Match found: " .. tostring(serverInfo))
                if lobbyUISandbox then lobbyUISandbox:OnMatchmakingChanged("found") end
                ShowMatchFoundDialog(serverInfo)
            end,
            onProgress = function(progress, status)
                LobbyUI.DriveServerProgress(progress, status)
            end,
            onError = function(errorCode)
                Log("Match failed: " .. FormatInt(errorCode))
                Log("Match error: " .. FormatInt(errorCode))
                if lobbyUISandbox then lobbyUISandbox:OnMatchmakingChanged("idle") end
                ShowErrorDialog("Match failed with error code: " .. FormatInt(errorCode))
                CreateMainView()
            end
        })
        Log("StartMatch requestId: " .. tostring(requestId))
    end

    -- 检查是否已在房间中，如果没有则先创建房间
    if not LobbyUIInstance.lobbyClient:IsInRoom() then
        Log("Not in room, creating temporary room first...")
        LobbyUIInstance.lobbyClient:CreateRoom({
            mapName = config.mapName,
            maxPlayers = config.maxPlayers,
            mode = config.mode,
            onCreated = function(roomId)
                Log("Temporary room created: " .. tostring(roomId) .. ", starting match...")
                doStartMatch()
            end,
            onError = function(errorCode)
                Log("Failed to create room: " .. FormatInt(errorCode))
                ShowErrorDialog("Failed to create room: " .. FormatInt(errorCode))
                CreateMainView()
            end
        })
    else
        Log("Already in room, starting match directly...")
        doStartMatch()
    end
end

-- 房间列表刷新：拉取 → ParseRoomList → 若沙箱存在则下发 onRoomList。
-- 框架层不再渲染列表，视觉交给模板层（DefaultLobbyUI / 项目大厅脚本）。
RefreshRoomListGlobal = function()
    local mapName = LobbyUIInstance.config.mapName or ""
    local mode = LobbyUIInstance.config.mode or "pvp"
    Log("RefreshRoomList: mapName = '" .. mapName .. "', mode = '" .. mode .. "'")

    if mapName == "" then
        Log("WARNING: mapName is empty! Room list may not work correctly.")
    end

    LobbyUIInstance.lobbyClient:GetRoomList({
        mapName = mapName,  -- 必须传入 mapName 才能看到房间
        modes = { mode },   -- 传入 mode 过滤
        limit = 20,
        includePrivate = false,
        onSuccess = function(data)
            Log("GetRoomList success, data type: " .. type(data))
            local rooms = ParseRoomList(data)
            LobbyUIInstance.roomListData = rooms
            Log("Parsed room count: " .. tostring(#rooms))
            if lobbyUISandbox then
                lobbyUISandbox:OnRoomList(rooms)
            end
        end,
        onError = function(errorCode)
            Log("Failed to get room list: " .. FormatInt(errorCode))
            ShowErrorDialog("Failed to load rooms: " .. FormatInt(errorCode))
        end
    })
end

--- Create room browser
CreateRoomBrowserView = function()
    Log("Opening room browser")
    StopRoomListAutoRefresh()

    local config = LobbyUIInstance.config

    -- 透明全屏背景
    local view = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
    }

    -- 透明返回按钮（沙箱负责定位和绘制）
    local backBtn = UI.Button {
        position = "absolute",
        width = 0, height = 0,
        text = "",
        backgroundColor = { 0, 0, 0, 0 },
        onClick = function()
            CreateMainView()
        end
    }
    view:AddChild(backBtn)

    -- 透明刷新按钮（沙箱负责定位和绘制）
    local refreshBtn = UI.Button {
        position = "absolute",
        width = 0, height = 0,
        text = "",
        backgroundColor = { 0, 0, 0, 0 },
        onClick = function()
            RefreshRoomListGlobal()
        end
    }
    view:AddChild(refreshBtn)

    -- Switch to room browser view
    local prevScreen = LobbyUIInstance.currentScreenName
    PrepareScreenSwitch(prevScreen)
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
        if lobbyUISandbox and prevScreen then
            lobbyUISandbox:UnregisterScreen(prevScreen)
        end
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view
    LobbyUIInstance.currentScreenName = "room_list"

    -- 沙箱：注册 room_list 界面控件 + 触发 onScreenChanged
    if lobbyUISandbox then
        lobbyUISandbox:RegisterScreen("room_list", {
            background      = view,
            back_button     = backBtn,
            refresh_button  = refreshBtn,
        })
        lobbyUISandbox:OnScreenChanged(prevScreen, "room_list")
    end

    -- Immediate refresh
    RefreshRoomListGlobal()

    -- Auto refresh if enabled
    if config.autoRefresh then
        LobbyUIInstance.autoRefreshTimer = 0
        LobbyUIInstance.roomListRefreshSubscription = TrackEventSubscription("Update", function(eventType, eventData)
            LobbyUIInstance.autoRefreshTimer = LobbyUIInstance.autoRefreshTimer + eventData["TimeStep"]:GetFloat() * 1000
            if LobbyUIInstance.autoRefreshTimer >= config.refreshInterval then
                LobbyUIInstance.autoRefreshTimer = 0
                RefreshRoomListGlobal()
            end
        end)
    end
end

--- Create room detail view
--- @param roomId string 房间ID
--- @param roomName string|nil 房间名称
--- @param roomMaxPlayers number|nil 房间最大玩家数（如果不传则使用config默认值）
CreateRoomDetailView = function(roomId, roomName, roomMaxPlayers)
    Log("Opening room detail: " .. roomId)
    StopRoomListAutoRefresh()
    local prevScreen = LobbyUIInstance.currentScreenName
    PrepareScreenSwitch(prevScreen)

    local config = LobbyUIInstance.config
    local roomViewGeneration = LobbyUIInstance.viewGeneration
    roomName = roomName or _tr("t_dKPVAF3ecqMQG9od")
    roomMaxPlayers = roomMaxPlayers or config.maxPlayers or 4  -- 使用传入的值或默认值

    -- 透明全屏背景
    local view = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
    }

    -- 透明离开按钮（沙箱负责定位和绘制）
    local leaveBtn = UI.Button {
        position = "absolute",
        width = 0, height = 0,
        text = "",
        backgroundColor = { 0, 0, 0, 0 },
        onClick = function()
            -- 先尝试离开房间，然后返回主界面
            LobbyUIInstance.lobbyClient:LeaveRoom({})
            -- 立即返回，不等待回调
            CreateMainView()
        end
    }
    view:AddChild(leaveBtn)

    -- ========== 房间业务状态（视觉交给模板层）==========
    local myUserId = LobbyUIInstance.lobbyClient:GetMyUserId()
    local maxPlayers = roomMaxPlayers  -- 使用传入的房间最大玩家数

    -- 开始按钮引用（只有房主可见）
    local startBtn = nil

    -- 更新开始按钮的可见性（只有房主可以看到）
    local function updateStartButtonVisibility(masterId)
        if startBtn then
            local isMaster = (masterId == nil) or (masterId == myUserId)
            startBtn:SetVisible(isMaster)
        end
    end

    -- 初始：没有数据时默认当前用户为房主
    updateStartButtonVisibility(nil)

    -- 房间人员变化：CreateRoom/JoinRoom 的内联 onPlayersChanged 委派到此（client 已整理成展示字段 {userId,nickname,avatar}）。
    LobbyUIInstance.onRoomPlayers = function(players, masterId)
        if not IsViewGenerationActive(roomViewGeneration) then return end
        players = players or {}
        Log("Team status updated: " .. tostring(#players) .. " players")
        updateStartButtonVisibility(masterId)
        if lobbyUISandbox then
            lobbyUISandbox:OnRoomPlayers(players, masterId)
        end
    end

    -- 透明开始游戏按钮（沙箱负责定位和绘制）
    startBtn = UI.Button {
        position = "absolute",
        width = 0, height = 0,
        text = "",
        backgroundColor = { 0, 0, 0, 0 },
        onClick = function()
            StartGameFromRoom()
        end
    }
    view:AddChild(startBtn)

    -- Switch view
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
        if lobbyUISandbox and prevScreen then
            lobbyUISandbox:UnregisterScreen(prevScreen)
        end
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view
    LobbyUIInstance.currentScreenName = "room_waiting"

    -- 沙箱：注册 room_waiting 界面控件 + 写入房间标题 + 触发 onScreenChanged
    if lobbyUISandbox then
        -- 房间标题（# + ID + 名称）写入只读状态，供模板渲染
        lobbyUISandbox:SetRoomTitle("#" .. FormatInt(roomId) .. " " .. roomName)
        lobbyUISandbox:RegisterScreen("room_waiting", {
            background   = view,
            start_button = startBtn,
            leave_button = leaveBtn,
        })
        lobbyUISandbox:OnScreenChanged(prevScreen, "room_waiting")
    end

    -- 房间非主动结束（被踢 / 解散）：CreateRoom/JoinRoom 的内联 onKicked 委派到此（主动离开走 LeaveRoom、不经此）。
    LobbyUIInstance.onRoomKicked = function()
        if IsViewGenerationActive(roomViewGeneration) then
            CleanupRoomWaitingHandlers()
            -- 必须导航回主界面，否则玩家卡死在 room_waiting（回调已清空、无任何 UI 反馈）。
            CreateMainView()
            -- 给出提示：这是非主动结束（被踢 / 房间解散），Host 的 roomLeft 不带原因，
            -- 故用兼顾两种情况、不暗示主动离开的中性文案；走与系统弹窗被踢一致的通道
            -- （制作人 DefineDialog 皮肤优先、平台模板兜底）。
            LobbyUI.ShowKickedDialog(_tr("t_ltGtwAablhD9royJ"), _tr("t_uMe6eKnuuYmXASDo"))
        end
    end
end

--- Create "create room" dialog
CreateCreateRoomDialog = function()
    Log("Opening create room dialog")

    local theme = LobbyUIInstance.theme
    local config = LobbyUIInstance.config

    -- Get default max players: config.maxPlayers -> lobbyClient:GetMaxPlayers() -> 4
    local defaultMaxPlayers = config.maxPlayers
    if not defaultMaxPlayers or defaultMaxPlayers <= 0 then
        local fromLobbyMgr = LobbyUIInstance.lobbyClient:GetMaxPlayers()
        defaultMaxPlayers = (fromLobbyMgr and fromLobbyMgr > 0) and fromLobbyMgr or 4
    end

    -- Overlay
    local overlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = { 0, 0, 0, 128 },
        justifyContent = "center",
        alignItems = "center",
    }

    -- Dialog（更圆润的弹窗）
    local dialog = UI.Panel {
        width = 560,
        flexDirection = "column",
        backgroundColor = { 50, 55, 70, 250 },
        borderRadius = 24,  -- 更大的圆角
        borderWidth = 1,
        borderColor = { 80, 90, 110, 150 },
        padding = 36,
        gap = 20,
    }

    -- Title
    dialog:AddChild(UI.Label {
        text = _tr("t_1DSgBSUmlo9AcDt"),
        fontSize = 26,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
        marginBottom = 12,
    })

    -- Map name input
    dialog:AddChild(UI.Label {
        text = _tr("t_4jmxglkE4aNkgIch"),
        fontSize = 16,
        fontColor = { 180, 190, 210, 255 },
    })

    local mapInput = UI.TextField {
        width = "100%",
        height = 56,
        fontSize = 18,
        placeholder = config.mapName,
        backgroundColor = { 40, 45, 60, 255 },
        borderRadius = 14,
        borderWidth = 1,
        borderColor = { 70, 80, 100, 150 },
        padding = 14,
    }
    dialog:AddChild(mapInput)

    -- Max players input
    dialog:AddChild(UI.Label {
        text = string.format(_tr("t_ntAIq14pnR4mnC8U"), MIN_MAX_PLAYERS, defaultMaxPlayers),
        fontSize = 16,
        fontColor = { 180, 190, 210, 255 },
    })

    local maxPlayersInput = UI.TextField {
        width = "100%",
        height = 56,
        fontSize = 18,
        placeholder = tostring(defaultMaxPlayers),
        backgroundColor = { 40, 45, 60, 255 },
        borderRadius = 14,
        borderWidth = 1,
        borderColor = { 70, 80, 100, 150 },
        padding = 14,
    }
    dialog:AddChild(maxPlayersInput)

    -- Error message label
    local errorLabel = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = { 255, 100, 100, 255 },
        visible = false,
    }
    dialog:AddChild(errorLabel)

    -- Button row
    local buttonRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 20,
        marginTop = 16,
    }

    -- Cancel button（灰色）
    buttonRow:AddChild(UI.Button {
        text = _tr("t_HXqnawyqI0cE2KuT"),
        width = 180,
        height = 52,
        fontSize = 18,
        backgroundColor = { 70, 75, 90, 255 },
        fontColor = { 200, 200, 210, 255 },
        borderRadius = 26,
        onClick = function()
            overlay:Destroy()
        end
    })

    -- Create button（绿色）
    buttonRow:AddChild(UI.Button {
        text = _tr("t_vkVwvaGXvt9hF4G8"),
        width = 180,
        height = 52,
        fontSize = 18,
        fontWeight = "bold",
        backgroundColor = { 80, 200, 120, 255 },
        fontColor = { 255, 255, 255, 255 },
        borderRadius = 26,
        onClick = function()
            local mapText = mapInput:GetText()
            local mapName = mapText ~= "" and mapText or config.mapName

            -- Validate max players
            local maxPlayersText = maxPlayersInput:GetText()
            maxPlayersText = maxPlayersText ~= "" and maxPlayersText or tostring(defaultMaxPlayers)
            local num = tonumber(maxPlayersText)
            if not num then
                errorLabel:SetText(_tr("t_J1xGbb8NJAkOoh4s"))
                errorLabel:SetVisible(true)
                return
            end
            if num < MIN_MAX_PLAYERS or num > defaultMaxPlayers then
                errorLabel:SetText(string.format(_tr("t_r9NDn1PxraLGNUXE"), MIN_MAX_PLAYERS, defaultMaxPlayers))
                errorLabel:SetVisible(true)
                return
            end

            local finalMaxPlayers = num  -- 保存到局部变量

            Log("Creating room: " .. mapName .. ", max players: " .. finalMaxPlayers)

            -- 保存到临时变量供回调使用
            local savedMaxPlayers = finalMaxPlayers

            LobbyUIInstance.lobbyClient:CreateRoom({
                mapName = mapName,
                maxPlayers = finalMaxPlayers,
                mode = config.mode,
                onCreated = function(roomId)
                    Log("Room created: " .. roomId .. ", maxPlayers: " .. savedMaxPlayers)
                    overlay:Destroy()
                    CreateRoomDetailView(roomId, nil, savedMaxPlayers)
                end,
                onError = function(errorCode)
                    Log("Failed to create room: " .. FormatInt(errorCode))
                    ShowErrorDialog("Failed to create room: " .. FormatInt(errorCode))
                    overlay:Destroy()
                end,
                onPlayersChanged = function(players, masterId) if LobbyUIInstance.onRoomPlayers then LobbyUIInstance.onRoomPlayers(players, masterId) end end,
                onKicked = function() if LobbyUIInstance.onRoomKicked then LobbyUIInstance.onRoomKicked() end end,
            })
        end
    })

    dialog:AddChild(buttonRow)
    overlay:AddChild(dialog)

    LobbyUIInstance.root:AddChild(overlay)
end

--- Create server progress view (shown while waiting for server to be ready)
CreateServerProgressView = function()
    Log("Creating server progress view")

    local theme = LobbyUIInstance.theme

    local view = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = theme.background,
        padding = 20,
    }

    -- Loading icon
    view:AddChild(UI.Label {
        text = " ",
        fontSize = 64,
        color = theme.primary,
        marginBottom = 20,
    })

    -- Title
    view:AddChild(UI.Label {
        text = _tr("t_mROCphnumJBiIlbn"),
        fontSize = 24,
        fontWeight = "bold",
        color = theme.text,
        marginBottom = 10,
    })

    -- Status label
    local statusLabel = UI.Label {
        text = _tr("t_1Um2bSV91fOJ5pZS"),
        fontSize = 14,
        color = theme.textSecondary,
        marginBottom = 30,
    }
    view:AddChild(statusLabel)

    -- Store references for updates
    serverProgressState.view = view
    serverProgressState.statusLabel = statusLabel

    -- Switch to server progress view
    local prevScreen = LobbyUIInstance.currentScreenName
    PrepareScreenSwitch(prevScreen)
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view

    return view
end

--- 连服屏框架建屏（沙箱驱动的第 5 个可定制屏）：建背景容器 + 注册沙箱屏 + 触发 enter。
--- 与 main/quick_match_waiting 等同模式；沙箱 connecting.enter 在 background 内渲染默认/自定义视觉。
CreateConnectingView = function()
    Log("Creating connecting view")
    local prevScreen = LobbyUIInstance.currentScreenName
    PrepareScreenSwitch(prevScreen)

    -- 透明全屏背景（沙箱 connecting 屏在其内渲染）
    local view = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
    }

    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
        if lobbyUISandbox then lobbyUISandbox:UnregisterScreen(prevScreen) end
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView       = view
    LobbyUIInstance.currentScreenName = "connecting"

    if lobbyUISandbox then
        lobbyUISandbox:RegisterScreen("connecting", { background = view })
        lobbyUISandbox:OnScreenChanged(prevScreen, "connecting")
    end

    return view
end

--- Show match found dialog
ShowMatchFoundDialog = function(serverInfo)
    Log("Match found dialog")

    local theme = LobbyUIInstance.theme

    local overlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = { 0, 0, 0, 179 },
        justifyContent = "center",
        alignItems = "center",
    }

    local dialog = UI.Panel {
        width = "90%",
        maxWidth = 400,
        flexDirection = "column",
        backgroundColor = theme.surface,
        borderRadius = 12,
        padding = 30,
        gap = 20,
        alignItems = "center",
    }

    dialog:AddChild(UI.Label {
        text = "✓",
        fontSize = 64,
        color = theme.success,
    })

    dialog:AddChild(UI.Label {
        text = _tr("t_w7PF2Jh5wc3WonMw"),
        fontSize = 24,
        fontWeight = "bold",
        color = theme.text,
    })

    dialog:AddChild(UI.Label {
        text = _tr("t_KEghPkfTKO2P03WM"),
        fontSize = 14,
        color = theme.textSecondary,
    })

    overlay:AddChild(dialog)
    LobbyUIInstance.root:AddChild(overlay)

    -- Delayed connection with proper cleanup
    local timer = 0
    local connected = false
    local subscription
    subscription = TrackEventSubscription("Update", function(eventType, eventData)
        if connected then
            return
        end

        timer = timer + eventData["TimeStep"]:GetFloat()
        if timer > 1.5 then
            connected = true
            UntrackEventSubscription(subscription)
            subscription = nil
            ConnectToGameServer(serverInfo)
            overlay:Destroy()
        end
    end)
end

local function TryCustomDialog(kinds, context)
    if not lobbyUISandbox or not LobbyUIInstance.root then
        return false
    end

    local mountedWidgets = {}
    local onClose = context and context.onClose
    local closed = false
    local ctx = {}
    for k, v in pairs(context or {}) do ctx[k] = v end
    ctx.sourceKind = ctx.sourceKind or ctx.kind or kinds[1]
    ctx.onClose = nil
    ctx.mount = function(widget)
        if widget then
            mountedWidgets[#mountedWidgets + 1] = widget
            LobbyUIInstance.root:AddChild(widget)
        end
        return widget
    end
    ctx.close = function()
        if closed then return end
        closed = true
        for _, w in ipairs(mountedWidgets) do
            if w.Destroy then w:Destroy() end
        end
        if onClose then
            onClose()
        end
    end

    for _, kind in ipairs(kinds or {}) do
        ctx.kind = kind
        -- 每个 kind 独立记账：失败（返回 false 或抛错被 pcall 捕获）时销毁它挂载的全部 widget，
        -- 避免残留遮罩挡输入或泄漏 Timer 回调，再进入下一个 kind / fallback。
        local startIdx = #mountedWidgets + 1
        if lobbyUISandbox:ShowDialog(kind, ctx) then
            return true
        end
        for i = #mountedWidgets, startIdx, -1 do
            local w = mountedWidgets[i]
            if w and w.Destroy then w:Destroy() end
            mountedWidgets[i] = nil
        end
    end
    return false
end

--- Show error toast using UI library Toast component
ShowErrorDialog = function(message)
    if TryCustomDialog({ "error" }, {
        message = message,
        title = _tr("t_fde7XWjkfWLhL3cA"),
        buttonText = _tr("t_JJMNFId6IoqaIkhF"),
    }) then
        Log("Custom error dialog shown: " .. message)
        return
    end

    -- Use the UI library's Toast component
    Toast.Show({
        message = message,
        variant = "error",
        duration = 4,  -- Show for 4 seconds
        showClose = true,
    })
    Log("Toast shown: " .. message)
end

--- Start game from room
StartGameFromRoom = function()
    Log("Starting game from room")

    local config = LobbyUIInstance.config

    LobbyUIInstance.lobbyClient:StartGame({
        mapName = config.mapName,
        mode = config.mode,
        onMatchFound = function(serverInfo)
            Log("Game started!")
            if lobbyUISandbox then lobbyUISandbox:OnMatchmakingChanged("found") end
            ShowMatchFoundDialog(serverInfo)
        end,
        onProgress = function(progress, status)
            LobbyUI.DriveServerProgress(progress, status)
        end,
        onError = function(errorCode)
            Log("Failed to start game: " .. FormatInt(errorCode))
            ShowErrorDialog("Failed to start game: " .. FormatInt(errorCode))
        end
    })
end

--- Connect to game server
ConnectToGameServer = function(serverInfo)
    Log("Connecting to game server: " .. serverInfo.ip .. ":" .. serverInfo.port)

    -- Call user callback
    if LobbyUIInstance.config.onGameStart then
        LobbyUIInstance.config.onGameStart(serverInfo)
    end

    -- 注意：不在这里隐藏 UI，因为连接可能失败
    -- UI 会在脚本切换时由引擎在 Stop() 时隐藏
end

-- ============================================================================
-- Public API
-- ============================================================================

--- 注入大厅客户端 LobbyClient。须在 Show() 之前调用（由 Runtime 入口 LobbyRuntimeUI 注入）。
--- 把桥驱动的客户端与 UI 解耦——不经 config，
--- 故不会经沙箱 Lobby.config 暴露给制作人。
--- @param client table LobbyClient 实例（桥驱动的大厅客户端）
function LobbyUI.SetLobbyClient(client)
    LobbyUIInstance.lobbyClient = client
end

--- 注入引擎托管的专属大厅 UI 根（由引擎引导层建并挂在 UI 根下）。须在 Show() 之前调用。
--- 注入后 Show() 跳过自建 root、直接挂在此根下；Hide() 只清子树、不销毁此根（根由引擎引导层回收）。
--- 未注入时（如独立测试）Show() 自建 SafeAreaView root。
--- @param node table 引擎专属大厅 UI 根节点
function LobbyUI.SetRoot(node)
    LobbyUIInstance.root = node
    LobbyUIInstance.externalRoot = true
end

--- Render one system notification with the template or project-defined dialog skin.
--- @param d table SystemNotification payload
local function RenderSystemDialog(d)
    d = d or {}
    local view = d.id and SystemNotification.Resolve(d) or {
        kind = d.kind,
        title = d.title,
        message = d.message,
        exitOnClose = d.exitOnClose,
    }
    local message = view.message
    if view.reason then
        message = _tr("t_Lo69xEfaLNWIRMpI", view.reason)
    end

    local mustExitOnClose = view.exitOnClose == true
        or (LobbyUIInstance.config and LobbyUIInstance.config.skipMainView == true)
    local exitCallback = nil
    if mustExitOnClose then
        exitCallback = function()
            engine:Exit()
        end
    end

    if view.kind == "error" then
        LobbyUI.ShowError(message or "")
    elseif view.kind == "kicked" then
        LobbyUI.ShowKickedDialog(view.title or "", message or "", exitCallback)
    else
        LobbyUI.ShowDialog({
            title = view.title,
            message = message,
            onClose = exitCallback,
        })
    end
    return true
end

-- 生产注册与 Validate 共用同一入口，避免测试复制系统通知分流逻辑。
LobbyUI._renderSystemDialog = RenderSystemDialog

--- Show game lobby UI
--- @param config table Configuration options (optional)
function LobbyUI.Show(config)
    -- 有 config（引擎平台推送或手动传入）则合并刷新；都没有时首次用默认配置。
    if config or not currentConfig then
        currentConfig = MergeConfig(config)
    end
    LobbyUIInstance.config = currentConfig

    -- Set theme
    LobbyUIInstance.theme = THEMES[LobbyUIInstance.config.theme] or THEMES.light

    -- 全局回调：client 由 Runtime 入口注入（SetLobbyClient），具名事件经引擎触发。
    LobbyUIInstance.lobbyClient:OnError(function(errorType, errorCode)
        Log("Global error: type=" .. tostring(errorType) .. ", code=" .. FormatInt(errorCode))
        if errorType == "GAME_START" then
            ShowErrorDialog("Game start failed with error code: " .. FormatInt(errorCode))
            CreateMainView()
        end
    end)

    -- 系统弹窗只走 SystemNotification；制作人 DefineDialog 皮肤优先，模板兜底。
    SystemNotification.RegisterHandler(RenderSystemDialog)

    -- Use project ID as default mapName if not specified
    if not LobbyUIInstance.config.mapName or LobbyUIInstance.config.mapName == "" then
        local projectId = LobbyUIInstance.lobbyClient:GetProjectId()
        if projectId and projectId ~= "" then
            LobbyUIInstance.config.mapName = projectId
            Log("Using project ID as mapName: " .. projectId)
        else
            LobbyUIInstance.config.mapName = "DefaultMap"
            Log("Warning: Project ID not available, using fallback mapName: DefaultMap")
        end
    end

    -- Initialize UI system if not already initialized
    if not UI.GetNVGContext() then
        UI.Init({
            scale = function()
                return math.max(graphics.height / 1080, 0.4)
            end,
        })
    end

    -- Initialize UI (SafeAreaView as root ensures all views have safe area insets)
    if not LobbyUIInstance.root then
        LobbyUIInstance.root = UI.SafeAreaView {
            position = "absolute",
            top = 0,
            left = 0,
            right = 0,
            bottom = 0,
            edges = "all",
        }

        -- Add to existing root or set as root
        local uiRoot = UI.GetRoot()
        if uiRoot then
            uiRoot:AddChild(LobbyUIInstance.root)
        else
            -- No root exists, set LobbyUI as root
            UI.SetRoot(LobbyUIInstance.root)
        end
    end

    -- Show mouse
    local input = GetInput()
    if input then
        input.mouseVisible = true
    end

    -- 加载大厅 UI 脚本：默认模板始终作为基底，项目大厅脚本在其上增量覆盖
    if not lobbyUISandbox then
        -- LobbyUI.lua 的 local 变量：全部显式传入沙箱（它们是 local，不在全局环境里）
        local widgetExtras = {
            UI                = UI,                -- urhox-libs/UI 控件库（local，非全局）
            FormatInt         = FormatInt,
            CreateTopBar      = CreateTopBar,
            ParseRoomList     = ParseRoomList,
        }

        local sandbox = LobbyUISandbox.New()
        sandbox:Init(widgetExtras)

        -- 填充完整 Lobby 动作集（在跑模板前就绪，模板可随时引用）
        do
            local L = sandbox._env.Lobby
            L.config           = MakeReadOnlyConfig(LobbyUIInstance.config)
            L.GetMyUserId      = function() return LobbyUIInstance.lobbyClient:GetMyUserId() end
            L.GetUserNickname  = function(opts) return LobbyUIInstance.lobbyClient:GetUserNickname(opts) end
            L.GetMaxPlayers    = function() return LobbyUIInstance.lobbyClient:GetMaxPlayers() end
            L.GetProjectId     = function() return LobbyUIInstance.lobbyClient:GetProjectId() end
            L.IsOnline         = function() return LobbyUIInstance.lobbyClient:IsOnline() end
            L.IsInRoom         = function() return LobbyUIInstance.lobbyClient:IsInRoom() end
            L.IsMatching       = function() return LobbyUIInstance.lobbyClient:IsMatching() end
            L.QuickMatch       = function() CreateMatchingView() end
            L.CancelMatch      = function() LobbyUIInstance.lobbyClient:CancelMatch(); CreateMainView() end
            L.BrowseRooms      = function() CreateRoomBrowserView() end
            L.CreateRoom       = function() createRoomAction(LobbyUIInstance.config) end
            L.JoinRoom         = function(roomId, maxPlayers)
                LobbyUIInstance.lobbyClient:JoinRoom({
                    roomId = roomId,
                    onJoined = function() CreateRoomDetailView(roomId, nil, maxPlayers) end,
                    onError = function(ec) ShowErrorDialog("Failed to join room: " .. FormatInt(ec)) end,
                    onPlayersChanged = function(players, masterId) if LobbyUIInstance.onRoomPlayers then LobbyUIInstance.onRoomPlayers(players, masterId) end end,
                    onKicked = function() if LobbyUIInstance.onRoomKicked then LobbyUIInstance.onRoomKicked() end end,
                })
            end
            L.LeaveRoom        = function()
                -- 离开无论成功/失败都回主界面（保留原设计）；视图重建只在回调里发生一次，不再同步预调
                LobbyUIInstance.lobbyClient:LeaveRoom({ onLeft = function() CreateMainView() end, onError = function() CreateMainView() end })
            end
            L.StartGame        = function() StartGameFromRoom() end
            L.RefreshRoomList  = function() if RefreshRoomListGlobal then RefreshRoomListGlobal() end end
            L.GotoMain         = function() CreateMainView() end
            L.Exit             = function() engine:Exit() end
        end

        -- 默认模板：总是先加载，为全部 5 个界面注册默认 def（基底兜底）
        if not sandbox:RunFile("urhox-libs/GameLobby/Runtime/Template/DefaultLobbyUI.lua") then
            LobbyLogError(sandbox._loadError or "Failed to load DefaultLobbyUI.lua")
        end

        -- 制作人脚本：固定加载项目 scripts/lobby_ui.lua（ResourceCache 中为 lobby_ui.lua）。
        if cache and cache:Exists(PROJECT_LOBBY_UI_FILE) then
            if not sandbox:RunFile(PROJECT_LOBBY_UI_FILE) then
                LobbyLogError(sandbox._loadError or "Failed to load " .. PROJECT_LOBBY_UI_FILE)
            end
        end

        lobbyUISandbox = sandbox

        TrackEventSubscription("Update", function(eventType, eventData)
            if lobbyUISandbox then
                lobbyUISandbox:OnUpdate(eventData["TimeStep"]:GetFloat())
            end
        end)
    end

    -- Create main interface (skip in middle-game / headless modes)
    if not LobbyUIInstance.config.skipMainView then
        CreateMainView()
    end

    Log("LobbyUI shown")
end


-- 控制逻辑（`ReturnToLobby`、后台匹配）由引擎平台侧处理，不在模板内。

--- Hide game lobby UI
function LobbyUI.Hide()
    AdvanceViewGeneration()
    CleanupRoomWaitingHandlers()

    -- Clean up event subscriptions
    CleanupEventSubscriptions()
    SystemNotification.UnregisterHandler()

    -- 清理沙箱（注销所有界面，释放实例）
    if lobbyUISandbox then
        for _, sname in ipairs({ "main", "room_list", "room_waiting", "quick_match_waiting", "connecting" }) do
            lobbyUISandbox:UnregisterScreen(sname)
        end
        lobbyUISandbox = nil
    end
    LobbyUIInstance.currentScreenName = nil

    if LobbyUIInstance.root then
        -- 外部注入的专属 root 归 引擎引导层 回收，这里只清子树；自建 root 才整树销毁。
        if LobbyUIInstance.externalRoot then
            LobbyUIInstance.root:ClearChildren()
        else
            LobbyUIInstance.root:Destroy()
        end
        LobbyUIInstance.root = nil
        LobbyUIInstance.externalRoot = nil
        LobbyUIInstance.currentView = nil
    end

    Log("LobbyUI hidden")
end

--- Check if UI is visible
--- @return boolean
function LobbyUI.IsVisible()
    return LobbyUIInstance.root ~= nil
end

--- Get the injected LobbyClient instance
--- @return table LobbyClient
function LobbyUI.GetLobbyClient()
    return LobbyUIInstance.lobbyClient
end

--- Show kicked alert dialog (full-screen overlay with message and confirm button)
--- Show a full-screen blocking dialog (overlay + centered card + single button).
--- @param options table { title, message, icon, buttonText, onClose }
---   - title: string Dialog title (required)
---   - message: string Dialog body text (required)
---   - icon: string Icon text (default "⚠")
---   - buttonText: string Button label (default "我知道了")
---   - onClose: function|nil Callback after user dismisses the dialog
function LobbyUI.ShowDialog(options)
    options = options or {}
    if TryCustomDialog({ "dialog", "system" }, options) then
        return
    end
    return LobbySystemDialogs.showDialog({
        UI    = UI,
        root  = LobbyUIInstance.root,
        theme = LobbyUIInstance.theme,
    }, options)
end

--- @param title string Dialog title
--- @param message string Dialog message
--- @param onClose function|nil Callback after user dismisses the dialog
function LobbyUI.ShowKickedDialog(title, message, onClose)
    if TryCustomDialog({ "kicked", "dialog", "system" }, {
        title = title,
        message = message,
        icon = "⚠",
        buttonText = _tr("t_JJMNFId6IoqaIkhF"),
        onClose = onClose,
    }) then
        return
    end
    return LobbySystemDialogs.showKickedDialog({
        UI    = UI,
        root  = LobbyUIInstance.root,
        theme = LobbyUIInstance.theme,
    }, title, message, onClose)
end

--- Show error toast
--- @param message string Error message to display
function LobbyUI.ShowError(message)
    -- 检查 UI 是否已初始化
    if not LobbyUIInstance.root then
        LobbyLogError("Error (UI not ready): " .. message)
        return
    end
    ShowErrorDialog(message)
end

--- Enable or disable the Lobby UI
--- When disabled, the UI stops rendering and responding to events but remains in memory.
--- @param enabled boolean
function LobbyUI.SetEnabled(enabled)
    UI.SetEnabled(enabled)
    Log("LobbyUI " .. (enabled and "enabled" or "disabled"))
end

--- Check if the Lobby UI is enabled
--- @return boolean
function LobbyUI.IsEnabled()
    return UI.IsEnabled()
end

--- Switch to server progress view
--- Call this when connected to server and waiting for server to be ready
function LobbyUI.SwitchToServerProgressView()
    if not LobbyUIInstance.root then
        LobbyLogError("Cannot switch to server progress view: UI not initialized")
        return
    end
    CreateServerProgressView()
end

--- 驱动连服屏（沙箱第 5 屏）：切到 connecting 屏（若不在）+ 喂进度给沙箱。
--- 由 Runtime 入口在收到连服进度事件后调用。
--- @param progress number 0..1
--- @param status string
function LobbyUI.DriveServerProgress(progress, status)
    if not LobbyUIInstance.root then
        LobbyLogError("DriveServerProgress (UI not ready): " .. tostring(status))
        return
    end
    if LobbyUIInstance.currentScreenName ~= "connecting" then
        CreateConnectingView()
    end
    if lobbyUISandbox then
        lobbyUISandbox:OnServerProgress(progress, status)
    end
end

--- Update server progress display
--- @param progress number Progress value (0.0 - 1.0)
--- @param status string Status description
function LobbyUI.UpdateServerProgress(progress, status)
    if not serverProgressState.view then
        -- View not created yet, ignore
        return
    end

    local progressPercent = math.floor(progress * 100)

    -- Update progress bar width
    if serverProgressState.progressBar then
        serverProgressState.progressBar:SetWidth(tostring(progressPercent) .. "%")
    end

    -- Update progress label
    if serverProgressState.progressLabel then
        serverProgressState.progressLabel:SetText(tostring(progressPercent) .. "%")
    end

    -- Update status label
    if serverProgressState.statusLabel and status and status ~= "" then
        serverProgressState.statusLabel:SetText(status)
    end

    Log("Server progress: " .. progressPercent .. "% - " .. (status or ""))
end

return LobbyUI
