-- ============================================================================
-- InventoryManager
-- UrhoX UI Library - Inventory data management (Model)
--
-- Manages inventory and equipment data, handles item movement logic.
-- This is a pure data model, no UI dependency.
-- ============================================================================

---@class InventoryManager
---@field equipmentSlots table Equipment slot definitions { slotId = { type, item } }
---@field inventoryItems table Inventory grid items { [index] = item }
---@field inventorySize number Number of inventory slots
---@field onChange function|nil General change notification callback
---@field onItemMoved function|nil Callback when item is moved: function(fromSlot, toSlot, item)
---@field onItemSwapped function|nil Callback when items are swapped: function(slot1, slot2, item1, item2)
local InventoryManager = {}
InventoryManager.__index = InventoryManager

-- ============================================================================
-- Constructor
-- ============================================================================

---@param config table { inventorySize, equipmentSlots }
---@return InventoryManager
function InventoryManager.new(config)
    local self = setmetatable({}, InventoryManager)

    config = config or {}

    -- Equipment slots definition
    self.equipmentSlots = config.equipmentSlots or {
        helmet = { type = "helmet", item = nil },
        weapon = { type = "weapon", item = nil },
        armor = { type = "armor", item = nil },
        boots = { type = "boots", item = nil },
    }

    -- Inventory grid
    self.inventorySize = config.inventorySize or 20
    self.inventoryItems = {}
    for i = 1, self.inventorySize do
        self.inventoryItems[i] = nil
    end

    -- Event callbacks
    self.onItemMoved = nil      -- function(fromSlot, toSlot, item)
    self.onItemSwapped = nil    -- function(slot1, slot2, item1, item2)
    self.onChange = nil         -- function() - general change notification

    return self
end

-- ============================================================================
-- Type Checking
-- ============================================================================

--- Check if an item can be placed in a slot
---@param item table The item to check
---@param slotType string The target slot type
---@return boolean canPlace
---@return string|nil reason Error message if cannot place
function InventoryManager:CanPlaceItem(item, slotType)
    if not item then
        return true, nil  -- Empty item can go anywhere
    end

    if slotType == "any" or slotType == "inventory" then
        return true, nil  -- Inventory accepts any type
    end

    if item.type == slotType then
        return true, nil
    end

    return false, string.format("Cannot place %s in %s slot", item.type or "item", slotType)
end

-- ============================================================================
-- Slot Operations
-- ============================================================================

--- Get item from equipment slot
---@param slotId string
---@return table|nil item
function InventoryManager:GetEquipmentItem(slotId)
    local slot = self.equipmentSlots[slotId]
    return slot and slot.item or nil
end

--- Set item in equipment slot
---@param slotId string
---@param item table|nil
---@return boolean success
---@return string|nil error
function InventoryManager:SetEquipmentItem(slotId, item)
    local slot = self.equipmentSlots[slotId]
    if not slot then
        return false, "Invalid equipment slot: " .. tostring(slotId)
    end

    local canPlace, reason = self:CanPlaceItem(item, slot.type)
    if not canPlace then
        return false, reason
    end

    slot.item = item

    if self.onChange then
        self.onChange()
    end

    return true, nil
end

--- Get item from inventory slot
---@param index number 1-based index
---@return table|nil item
function InventoryManager:GetInventoryItem(index)
    return self.inventoryItems[index]
end

--- Set item in inventory slot
---@param index number 1-based index
---@param item table|nil
---@return boolean success
function InventoryManager:SetInventoryItem(index, item)
    if index < 1 or index > self.inventorySize then
        return false
    end

    self.inventoryItems[index] = item

    if self.onChange then
        self.onChange()
    end

    return true
end

-- ============================================================================
-- Move / Swap Operations
-- ============================================================================

--- Move item from one slot to another
---@param fromType string "equipment" or "inventory"
---@param fromId string|number Slot ID or inventory index
---@param toType string "equipment" or "inventory"
---@param toId string|number Target slot ID or inventory index
---@return boolean success
---@return string|nil error
function InventoryManager:MoveItem(fromType, fromId, toType, toId)
    -- Get source item
    local sourceItem
    local sourceSlotType = "any"

    if fromType == "equipment" then
        sourceItem = self:GetEquipmentItem(fromId)
        local slot = self.equipmentSlots[fromId]
        sourceSlotType = slot and slot.type or "any"
    else
        sourceItem = self:GetInventoryItem(fromId)
        sourceSlotType = "inventory"
    end

    if not sourceItem then
        return false, "No item to move"
    end

    -- Get target slot info
    local targetItem
    local targetSlotType = "any"

    if toType == "equipment" then
        targetItem = self:GetEquipmentItem(toId)
        local slot = self.equipmentSlots[toId]
        targetSlotType = slot and slot.type or "any"
    else
        targetItem = self:GetInventoryItem(toId)
        targetSlotType = "inventory"
    end

    -- Type check for target
    local canPlace, reason = self:CanPlaceItem(sourceItem, targetSlotType)
    if not canPlace then
        return false, reason
    end

    -- If target has item, check if source can accept it (for swap)
    if targetItem then
        local canSwap, swapReason = self:CanPlaceItem(targetItem, sourceSlotType)
        if not canSwap then
            return false, "Cannot swap: " .. (swapReason or "incompatible types")
        end
    end

    -- Perform move/swap
    if toType == "equipment" then
        self.equipmentSlots[toId].item = sourceItem
    else
        self.inventoryItems[toId] = sourceItem
    end

    if fromType == "equipment" then
        self.equipmentSlots[fromId].item = targetItem
    else
        self.inventoryItems[fromId] = targetItem
    end

    -- Callbacks
    if targetItem then
        if self.onItemSwapped then
            self.onItemSwapped(
                { type = fromType, id = fromId },
                { type = toType, id = toId },
                sourceItem, targetItem
            )
        end
    else
        if self.onItemMoved then
            self.onItemMoved(
                { type = fromType, id = fromId },
                { type = toType, id = toId },
                sourceItem
            )
        end
    end

    if self.onChange then
        self.onChange()
    end

    return true, nil
end

-- ============================================================================
-- Inventory Queries
-- ============================================================================

--- Find first empty inventory slot
---@return number|nil index
function InventoryManager:FindEmptyInventorySlot()
    for i = 1, self.inventorySize do
        if not self.inventoryItems[i] then
            return i
        end
    end
    return nil
end

--- Add item to first empty inventory slot
---@param item table
---@return boolean success
---@return number|nil slotIndex
function InventoryManager:AddToInventory(item)
    local slot = self:FindEmptyInventorySlot()
    if not slot then
        return false, nil
    end

    self.inventoryItems[slot] = item

    if self.onChange then
        self.onChange()
    end

    return true, slot
end

--- Get all equipment as table
---@return table { slotId = item }
function InventoryManager:GetAllEquipment()
    local result = {}
    for slotId, slotData in pairs(self.equipmentSlots) do
        result[slotId] = slotData.item
    end
    return result
end

--- Get all inventory items
---@return table { [index] = item }
function InventoryManager:GetAllInventory()
    return self.inventoryItems
end

--- Get equipment slot type
---@param slotId string
---@return string|nil
function InventoryManager:GetEquipmentSlotType(slotId)
    local slot = self.equipmentSlots[slotId]
    return slot and slot.type or nil
end

return InventoryManager
