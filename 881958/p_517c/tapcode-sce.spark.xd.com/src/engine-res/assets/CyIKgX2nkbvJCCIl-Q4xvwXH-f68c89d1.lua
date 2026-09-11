--[[
    InventoryExample.lua

    Demo of RPG equipment and inventory system with drag-and-drop.

    Features:
    - Drag items from inventory to equipment slots
    - Type checking (helmet -> helmet slot only)
    - Swap items if target slot is occupied
    - Drag icon follows cursor at highest z-order
    - Data/View separation via InventoryManager

    Usage:
        require("LuaScripts/InventoryExample")
        -- Just call Start() or run directly via UrhoX runtime
]]

local UI = require("urhox-libs/UI/init")

local InventoryExample = {}

--------------------------------------------------------------------------------
-- Sample Item Data
--------------------------------------------------------------------------------

local function CreateSampleItems()
    return {
        -- Helmets
        { id = 1, name = "Iron Helmet", icon = "🪖", type = "helmet", rarity = "common" },
        { id = 2, name = "Golden Crown", icon = "👑", type = "helmet", rarity = "legendary" },

        -- Weapons
        { id = 3, name = "Iron Sword", icon = "⚔️", type = "weapon", rarity = "common" },
        { id = 4, name = "Magic Staff", icon = "🪄", type = "weapon", rarity = "rare" },
        { id = 5, name = "Dragon Blade", icon = "🗡️", type = "weapon", rarity = "epic" },

        -- Armor
        { id = 6, name = "Leather Armor", icon = "🛡️", type = "armor", rarity = "common" },
        { id = 7, name = "Dragon Scale", icon = "🐉", type = "armor", rarity = "legendary" },

        -- Boots
        { id = 8, name = "Travel Boots", icon = "👢", type = "boots", rarity = "common" },
        { id = 9, name = "Speed Boots", icon = "👟", type = "boots", rarity = "rare" },

        -- Misc (can only go in inventory)
        { id = 10, name = "Health Potion", icon = "🧪", type = "consumable", quantity = 5 },
        { id = 11, name = "Mana Crystal", icon = "💎", type = "consumable", quantity = 3 },
        { id = 12, name = "Gold Coins", icon = "🪙", type = "currency", quantity = 100 },
    }
end

--------------------------------------------------------------------------------
-- Global State
--------------------------------------------------------------------------------

local inventoryManager = nil
local dragContext = nil
local equipmentSlots = {}   -- { slotId = ItemSlot widget }
local inventorySlots = {}   -- { [index] = ItemSlot widget }
local statusLabel = nil
local root = nil

--------------------------------------------------------------------------------
-- UI Update
--------------------------------------------------------------------------------

local function UpdateAllSlots()
    -- Update equipment slots
    for slotId, slotWidget in pairs(equipmentSlots) do
        local item = inventoryManager:GetEquipmentItem(slotId)
        slotWidget:SetItem(item)
    end

    -- Update inventory slots
    for i, slotWidget in ipairs(inventorySlots) do
        local item = inventoryManager:GetInventoryItem(i)
        slotWidget:SetItem(item)
    end
end

local function SetStatus(text)
    if statusLabel then
        statusLabel:SetText(text)
    end
    print("[Inventory] " .. text)
end

--------------------------------------------------------------------------------
-- Drag and Drop Handlers
--------------------------------------------------------------------------------

local function OnDragStart(itemData, sourceSlot)
    SetStatus("Dragging: " .. (itemData.name or "Unknown"))
end

local function OnDragEnd(itemData, sourceSlot, targetSlot, success)
    if not targetSlot then
        SetStatus("Drop cancelled - no target")
        return
    end

    if not success then
        SetStatus("Cannot drop here!")
        return
    end

    -- Get slot category and ID directly from slots
    local fromType = sourceSlot:GetSlotCategory()
    local fromId = sourceSlot:GetSlotId()
    local toType = targetSlot:GetSlotCategory()
    local toId = targetSlot:GetSlotId()

    -- Perform move via InventoryManager
    local moveSuccess, err = inventoryManager:MoveItem(fromType, fromId, toType, toId)

    if moveSuccess then
        local targetItem = targetSlot:GetItem()
        if targetItem then
            SetStatus("Swapped: " .. itemData.name .. " <-> " .. targetItem.name)
        else
            SetStatus("Moved: " .. itemData.name)
        end
        UpdateAllSlots()
    else
        SetStatus("Failed: " .. (err or "Unknown error"))
    end
end

local function OnDragCancel(itemData, sourceSlot)
    SetStatus("Drag cancelled")
end

local function CanDrop(itemData, sourceSlot, targetSlot)
    local targetType = targetSlot:GetSlotType()

    -- Check type compatibility
    if targetType == "any" or targetType == "inventory" then
        return true
    end

    return itemData.type == targetType
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

local function CreateEquipmentPanel()
    local panel = UI.Panel {
        width = 200,
        backgroundColor = { 35, 38, 48, 255 },
        borderRadius = 12,
        padding = 16,
        flexDirection = "column",
        gap = 12,
    }

    -- Title
    panel:AddChild(UI.Label {
        text = "Equipment",
        fontSize = 18,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
    })

    -- Equipment grid (2x2)
    local grid = UI.Panel {
        flexDirection = "column",
        gap = 8,
        alignItems = "center",
    }

    -- Row 1: Helmet, Weapon
    local row1 = UI.Panel {
        flexDirection = "row",
        gap = 8,
    }

    equipmentSlots.helmet = UI.ItemSlot {
        slotId = "helmet",
        slotCategory = "equipment",
        inventoryManager = inventoryManager,  -- slotType auto-fetched
        slotTypeIcon = "🪖",
        size = 72,
        dragContext = dragContext,
    }
    row1:AddChild(equipmentSlots.helmet)

    equipmentSlots.weapon = UI.ItemSlot {
        slotId = "weapon",
        slotCategory = "equipment",
        inventoryManager = inventoryManager,  -- slotType auto-fetched
        slotTypeIcon = "⚔️",
        size = 72,
        dragContext = dragContext,
    }
    row1:AddChild(equipmentSlots.weapon)

    grid:AddChild(row1)

    -- Row 2: Armor, Boots
    local row2 = UI.Panel {
        flexDirection = "row",
        gap = 8,
    }

    equipmentSlots.armor = UI.ItemSlot {
        slotId = "armor",
        slotCategory = "equipment",
        inventoryManager = inventoryManager,  -- slotType auto-fetched
        slotTypeIcon = "🛡️",
        size = 72,
        dragContext = dragContext,
    }
    row2:AddChild(equipmentSlots.armor)

    equipmentSlots.boots = UI.ItemSlot {
        slotId = "boots",
        slotCategory = "equipment",
        inventoryManager = inventoryManager,  -- slotType auto-fetched
        slotTypeIcon = "👢",
        size = 72,
        dragContext = dragContext,
    }
    row2:AddChild(equipmentSlots.boots)

    grid:AddChild(row2)

    panel:AddChild(grid)

    -- Type hint
    panel:AddChild(UI.Label {
        text = "Drag matching items here",
        fontSize = 10,
        fontColor = { 100, 100, 120, 255 },
        textAlign = "center",
    })

    return panel
end

local function CreateInventoryPanel()
    local panel = UI.Panel {
        width = 340,
        backgroundColor = { 35, 38, 48, 255 },
        borderRadius = 12,
        padding = 16,
        flexDirection = "column",
        gap = 12,
    }

    -- Title
    panel:AddChild(UI.Label {
        text = "Inventory",
        fontSize = 18,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
    })

    -- Inventory grid (5x4)
    local grid = UI.Panel {
        flexDirection = "column",
        gap = 4,
        alignItems = "center",
    }

    local cols = 5
    local rows = 4
    local slotIndex = 1

    for r = 1, rows do
        local row = UI.Panel {
            flexDirection = "row",
            gap = 4,
        }

        for c = 1, cols do
            local slot = UI.ItemSlot {
                slotId = slotIndex,
                slotCategory = "inventory",  -- explicit category
                -- slotType defaults to "any" for inventory
                size = 56,
                showTypeIcon = false,
                dragContext = dragContext,
            }
            inventorySlots[slotIndex] = slot
            row:AddChild(slot)
            slotIndex = slotIndex + 1
        end

        grid:AddChild(row)
    end

    panel:AddChild(grid)

    return panel
end

local function CreateUI()
    -- Initialize InventoryManager
    inventoryManager = UI.InventoryManager.new({
        inventorySize = 20,
        equipmentSlots = {
            helmet = { type = "helmet", item = nil },
            weapon = { type = "weapon", item = nil },
            armor = { type = "armor", item = nil },
            boots = { type = "boots", item = nil },
        },
    })

    -- Add sample items to inventory
    local sampleItems = CreateSampleItems()
    for i, item in ipairs(sampleItems) do
        if i <= 20 then
            inventoryManager:SetInventoryItem(i, item)
        end
    end

    -- Create root container
    root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 25, 28, 35, 255 },
        flexDirection = "column",
        alignItems = "center",
        padding = 20,
        gap = 16,
    }

    -- Title
    root:AddChild(UI.Label {
        text = "RPG Inventory System",
        fontSize = 24,
        fontColor = { 255, 255, 255, 255 },
    })

    -- Status label
    statusLabel = UI.Label {
        text = "Drag items to equip them",
        fontSize = 12,
        fontColor = { 150, 150, 180, 255 },
    }
    root:AddChild(statusLabel)

    -- Create drag context first
    dragContext = UI.DragDropContext {
        onDragStart = OnDragStart,
        onDragEnd = OnDragEnd,
        onDragCancel = OnDragCancel,
        canDrop = CanDrop,
    }

    -- Main content area (flexWrap 让小屏自动换行)
    local contentArea = UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 20,
        alignItems = "flex-start",
        justifyContent = "center",
    }

    contentArea:AddChild(CreateEquipmentPanel())
    contentArea:AddChild(CreateInventoryPanel())

    root:AddChild(contentArea)

    -- Add drag context to root (renders drag icon on top)
    root:AddChild(dragContext)

    -- Footer
    local footer = UI.Panel {
        flexDirection = "column",
        alignItems = "center",
        gap = 4,
    }
    footer:AddChild(UI.Label {
        text = "Helmet->Helmet slot, Weapon->Weapon slot, etc.",
        fontSize = 11,
        fontColor = { 100, 100, 130, 255 },
    })
    footer:AddChild(UI.Label {
        text = "Wrong type will show red border and bounce back",
        fontSize = 10,
        fontColor = { 80, 80, 100, 255 },
    })
    root:AddChild(footer)

    -- Initial UI update
    UpdateAllSlots()

    return root
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function InventoryExample.Init()
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

    print("[InventoryExample] Initialized")
    print("[InventoryExample] Drag items from inventory to equipment slots")
end

function InventoryExample.Shutdown()
    UI.Shutdown()
end

-- Direct execution
function Start()
    InventoryExample.Init()
end

return InventoryExample
