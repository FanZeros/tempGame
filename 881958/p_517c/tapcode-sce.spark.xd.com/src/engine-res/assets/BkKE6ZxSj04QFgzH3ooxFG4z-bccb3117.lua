--[[
    VirtualListExample.lua

    Demo of UI.VirtualList component - displaying 10,000 inventory items
    with object pooling and view recycling.

    Usage:
        require("LuaScripts/VirtualListExample")
        -- Just call Start() or run directly via UrhoX runtime
]]

local UI = require("urhox-libs/UI/init")

local VirtualListExample = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local CONFIG = {
    TOTAL_ITEMS = 10000,
    ITEM_HEIGHT = 80,
    ITEM_GAP = 4,
    ICON_SIZE = 56,
    LIST_WIDTH = 400,
}

--------------------------------------------------------------------------------
-- Data Generation
--------------------------------------------------------------------------------

local globalElapsedTime = 0

local function GenerateInventoryData(count)
    local items = {}
    local itemTypes = {
        { name = "Health Potion",   icon = "🧪", rarity = "common" },
        { name = "Mana Crystal",    icon = "💎", rarity = "rare" },
        { name = "Dragon Scale",    icon = "🐉", rarity = "epic" },
        { name = "Phoenix Feather", icon = "🔥", rarity = "legendary" },
        { name = "Iron Sword",      icon = "⚔️", rarity = "common" },
        { name = "Magic Staff",     icon = "🪄", rarity = "rare" },
        { name = "Ancient Scroll",  icon = "📜", rarity = "epic" },
        { name = "Golden Crown",    icon = "👑", rarity = "legendary" },
        { name = "Silver Ring",     icon = "💍", rarity = "rare" },
        { name = "Emerald Stone",   icon = "💚", rarity = "epic" },
    }

    local rarityColors = {
        common    = { 180, 180, 180, 255 },
        rare      = { 80, 160, 255, 255 },
        epic      = { 180, 80, 255, 255 },
        legendary = { 255, 200, 80, 255 },
    }

    math.randomseed(os.time())

    for i = 1, count do
        local template = itemTypes[((i - 1) % #itemTypes) + 1]
        local countdownDuration = math.random(60, 7200) + i * 0.5

        items[i] = {
            id = i,
            name = template.name .. " #" .. i,
            icon = template.icon,
            rarity = template.rarity,
            rarityColor = rarityColors[template.rarity],
            countdownDuration = countdownDuration,
            quantity = math.random(1, 99),
        }
    end

    return items
end

--------------------------------------------------------------------------------
-- Countdown Helpers
--------------------------------------------------------------------------------

local function GetRemainingTime(item)
    return math.max(0, item.countdownDuration - globalElapsedTime)
end

local function FormatCountdown(seconds)
    if seconds <= 0 then return "EXPIRED" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

--------------------------------------------------------------------------------
-- Item Widget Factory
--------------------------------------------------------------------------------

local function CreateItemWidget()
    local item = UI.Panel {
        width = CONFIG.LIST_WIDTH - 20,
        height = CONFIG.ITEM_HEIGHT,
        flexDirection = "row",
        alignItems = "center",
        padding = 8,
        gap = 12,
        backgroundColor = { 40, 45, 55, 255 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 60, 65, 75, 255 },
    }

    -- Icon container
    local iconContainer = UI.Panel {
        width = CONFIG.ICON_SIZE,
        height = CONFIG.ICON_SIZE,
        backgroundColor = { 30, 35, 45, 255 },
        borderRadius = 8,
        justifyContent = "center",
        alignItems = "center",
    }
    local iconLabel = UI.Label {
        id = "icon",
        text = "📦",
        fontSize = 28,
        textAlign = "center",
    }
    iconContainer:AddChild(iconLabel)
    item:AddChild(iconContainer)

    -- Info container
    local infoContainer = UI.Panel {
        flexGrow = 1,
        flexShrink = 1,
        flexDirection = "column",
        justifyContent = "center",
        gap = 4,
    }
    local nameLabel = UI.Label {
        id = "name",
        text = "Item Name",
        fontSize = 14,
        fontColor = { 240, 240, 240, 255 },
        maxLines = 1,
    }
    local countdownLabel = UI.Label {
        id = "countdown",
        text = "00:00:00",
        fontSize = 12,
        fontColor = { 150, 200, 255, 255 },
    }
    infoContainer:AddChild(nameLabel)
    infoContainer:AddChild(countdownLabel)
    item:AddChild(infoContainer)

    -- Quantity badge
    local quantityBadge = UI.Panel {
        width = 36,
        height = 24,
        backgroundColor = { 60, 120, 200, 255 },
        borderRadius = 12,
        justifyContent = "center",
        alignItems = "center",
    }
    local quantityLabel = UI.Label {
        id = "quantity",
        text = "x1",
        fontSize = 11,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
    }
    quantityBadge:AddChild(quantityLabel)
    item:AddChild(quantityBadge)

    -- Store references
    item._iconLabel = iconLabel
    item._nameLabel = nameLabel
    item._countdownLabel = countdownLabel
    item._quantityLabel = quantityLabel

    return item
end

-- Called when item enters visible area (binds static data)
local function BindItemWidget(widget, data, index)
    widget._iconLabel:SetText(data.icon)
    widget._nameLabel:SetText(data.name)
    widget._nameLabel.props.fontColor = data.rarityColor
    widget._quantityLabel:SetText("x" .. data.quantity)
    widget.props.borderColor = {
        data.rarityColor[1],
        data.rarityColor[2],
        data.rarityColor[3],
        100
    }
end

-- Called every frame for visible items (updates dynamic content)
local function TickItemWidget(widget, data, index, dt)
    local remaining = GetRemainingTime(data)
    widget._countdownLabel:SetText(FormatCountdown(remaining))

    if remaining <= 0 then
        widget._countdownLabel.props.fontColor = { 255, 100, 100, 255 }
    elseif remaining < 60 then
        widget._countdownLabel.props.fontColor = { 255, 180, 80, 255 }
    else
        widget._countdownLabel.props.fontColor = { 150, 200, 255, 255 }
    end
end

--------------------------------------------------------------------------------
-- Main UI
--------------------------------------------------------------------------------

local root = nil
local statsLabel = nil
local virtualList = nil
local inventoryData = nil

local function CreateUI()
    inventoryData = GenerateInventoryData(CONFIG.TOTAL_ITEMS)

    root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 25, 28, 35, 255 },
        flexDirection = "column",
        alignItems = "center",
        padding = 20,
        gap = 16,
        overflow = "hidden",
    }

    -- Title
    root:AddChild(UI.Label {
        text = "Virtual Inventory List",
        fontSize = 24,
        fontColor = { 255, 255, 255, 255 },
    })

    -- Stats
    statsLabel = UI.Label {
        text = "Items: " .. CONFIG.TOTAL_ITEMS .. " | Rendered: 0",
        fontSize = 12,
        fontColor = { 150, 150, 180, 255 },
    }
    root:AddChild(statsLabel)

    -- VirtualList container (填充剩余空间)
    local listContainer = UI.Panel {
        width = CONFIG.LIST_WIDTH,
        flexGrow = 1,            -- 填充剩余空间
        flexBasis = 0,           -- 防止内容撑开尺寸
        backgroundColor = { 30, 33, 42, 255 },
        borderRadius = 12,
        borderWidth = 2,
        borderColor = { 50, 55, 70, 255 },
        overflow = "hidden",
    }
    root:AddChild(listContainer)

    -- Create VirtualList
    virtualList = UI.VirtualList {
        width = "100%",
        height = "100%",
        viewportHeight = UI.GetHeight(),  -- 当 height 不固定时提供初始预估，组件内部会在布局稳定后自动用 layout.h
        data = inventoryData,
        itemHeight = CONFIG.ITEM_HEIGHT,
        itemGap = CONFIG.ITEM_GAP,
        poolBuffer = 5,
        createItem = CreateItemWidget,
        bindItem = BindItemWidget,      -- Static data (icon, name, quantity)
        tickItem = TickItemWidget,      -- Dynamic data (countdown) - called every frame
        onItemClick = function(data, index, widget)
            print("[VirtualList] Clicked: " .. data.name)
        end,
    }
    listContainer:AddChild(virtualList)

    -- Footer
    local footer = UI.Panel {
        flexDirection = "column",
        alignItems = "center",
        gap = 4,
    }
    footer:AddChild(UI.Label {
        text = "Scroll to view items • Only visible items are rendered",
        fontSize = 11,
        fontColor = { 100, 100, 130, 255 },
    })
    footer:AddChild(UI.Label {
        text = "UI.VirtualList Component Demo",
        fontSize = 10,
        fontColor = { 80, 80, 100, 255 },
    })
    root:AddChild(footer)

    -- Custom Update for global time and stats display
    root.Update = function(self, dt)
        globalElapsedTime = globalElapsedTime + dt

        -- Update stats display (tickItem is called automatically by VirtualList)
        if virtualList then
            local stats = virtualList:GetPoolStats()
            local first, last = virtualList:GetVisibleRange()
            statsLabel:SetText(string.format(
                "Items: %d | Rendered: %d | Pool: %d | Range: %d-%d",
                CONFIG.TOTAL_ITEMS,
                stats.inUse,
                stats.available,
                first, last
            ))
        end
    end

    return root
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function VirtualListExample.Init()
    UI.Init({
        fonts = {
            { name = "sans", path = "Fonts/MiSans-Regular.ttf" },
        },
        autoEvents = true,
        -- 推荐! DPR 缩放 + 小屏密度自适应（见 ui.md §10）
        -- 1 基准像素 ≈ 1 CSS 像素，尺寸遵循 CSS/Web 常识
        scale = UI.Scale.DEFAULT,
    })

    UI.SetRoot(CreateUI())

    print("[VirtualListExample] Initialized with " .. CONFIG.TOTAL_ITEMS .. " items")
    if virtualList then
        local stats = virtualList:GetPoolStats()
        print("[VirtualListExample] Pool size: " .. stats.total .. " widgets")
    end
end

function VirtualListExample.Shutdown()
    UI.Shutdown()
end

-- Direct execution
function Start()
    VirtualListExample.Init()
end

return VirtualListExample
