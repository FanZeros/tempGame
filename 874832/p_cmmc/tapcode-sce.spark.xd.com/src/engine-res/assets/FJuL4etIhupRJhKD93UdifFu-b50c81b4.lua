-- ============================================================================
-- ItemSlot Component
-- UrhoX UI Library - Inventory/Equipment slot
--
-- A single slot that can hold an item, supports drag and drop.
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Panel = require("urhox-libs/UI/Widgets/Panel")
local Label = require("urhox-libs/UI/Widgets/Label")

---@class ItemSlotProps : WidgetProps
---@field slotId string|number Unique slot identifier
---@field slotCategory? string Slot category: "equipment" or "inventory" (default: "inventory")
---@field slotType? string Slot type for validation
---@field slotTypeIcon? string Icon to show when slot is empty
---@field inventoryManager? InventoryManager Reference to InventoryManager
---@field size? number Slot size in pixels (default: 64)
---@field item? table Current item data { id, name, icon, type, ... }
---@field dragContext? DragDropContext Reference to DragDropContext
---@field onSlotClick? fun(slot: ItemSlot, item: table) Click callback
---@field showTypeIcon? boolean Show slot type icon when empty (default: true)

---@class ItemSlot : Widget
---@overload fun(props?: ItemSlotProps): ItemSlot
---@field props ItemSlotProps
---@field new fun(self, props?: ItemSlotProps): ItemSlot
local ItemSlot = Widget:Extend("ItemSlot")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ItemSlotProps?
function ItemSlot:Init(props)
    props = props or {}

    -- Defaults
    props.size = props.size or 64
    props.slotCategory = props.slotCategory or "inventory"
    props.showTypeIcon = props.showTypeIcon ~= false

    -- Resolve slotType: prefer explicit prop, otherwise fetch from inventoryManager
    if not props.slotType then
        if props.inventoryManager and props.slotCategory == "equipment" then
            props.slotType = props.inventoryManager:GetEquipmentSlotType(props.slotId)
        else
            props.slotType = "any"
        end
    end

    -- Styling
    props.width = props.size
    props.height = props.size
    props.backgroundColor = props.backgroundColor or { 40, 45, 55, 255 }
    props.borderRadius = props.borderRadius or 8
    props.borderWidth = props.borderWidth or 2
    props.borderColor = props.borderColor or { 60, 65, 75, 255 }
    props.justifyContent = "center"
    props.alignItems = "center"

    -- Internal state
    self.isHovered_ = false
    self.isDragOver_ = false

    Widget.Init(self, props)

    -- Build slot UI
    self:BuildSlotUI()

    -- Register as drop target
    if props.dragContext then
        props.dragContext:RegisterDropTarget(self)
    end

    -- Update display
    self:UpdateDisplay()
end

-- ============================================================================
-- UI Structure
-- ============================================================================

function ItemSlot:BuildSlotUI()
    -- Item icon (pointerEvents = "none" to not interfere with parent's hover/drag)
    self.iconLabel_ = Label {
        text = "",
        fontSize = math.floor(self.props.size * 0.5),
        textAlign = "center",
        pointerEvents = "none",
    }
    Widget.AddChild(self, self.iconLabel_)

    -- Quantity badge (bottom-right corner)
    self.quantityBadge_ = Panel {
        position = "absolute",
        right = 2,
        bottom = 2,
        width = 20,
        height = 16,
        backgroundColor = { 30, 30, 40, 200 },
        borderRadius = 4,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "none",
    }
    self.quantityLabel_ = Label {
        text = "",
        fontSize = 10,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
        pointerEvents = "none",
    }
    self.quantityBadge_:AddChild(self.quantityLabel_)
    self.quantityBadge_:SetVisible(false)
    Widget.AddChild(self, self.quantityBadge_)
end

-- ============================================================================
-- Display
-- ============================================================================

function ItemSlot:UpdateDisplay()
    local item = self.props.item

    if item then
        -- Show item icon
        self.iconLabel_:SetText(item.icon or "📦")
        self.iconLabel_.props.fontColor = { 255, 255, 255, 255 }

        -- Show quantity if > 1
        if item.quantity and item.quantity > 1 then
            self.quantityLabel_:SetText(tostring(item.quantity))
            self.quantityBadge_:SetVisible(true)
        else
            self.quantityBadge_:SetVisible(false)
        end

        -- Normal background
        self.props.backgroundColor = { 50, 55, 70, 255 }
    else
        -- Show slot type icon when empty (use props.slotTypeIcon if provided)
        if self.props.showTypeIcon and self.props.slotTypeIcon then
            self.iconLabel_:SetText(self.props.slotTypeIcon)
            self.iconLabel_.props.fontColor = { 80, 85, 100, 255 }
        else
            self.iconLabel_:SetText("")
        end
        self.quantityBadge_:SetVisible(false)

        -- Dimmed background for empty slot
        self.props.backgroundColor = { 40, 45, 55, 255 }
    end
end

--- Set item in this slot
---@param item table|nil
function ItemSlot:SetItem(item)
    self.props.item = item
    self:UpdateDisplay()
end

--- Get item in this slot
---@return table|nil
function ItemSlot:GetItem()
    return self.props.item
end

--- Get slot ID
---@return string|number
function ItemSlot:GetSlotId()
    return self.props.slotId
end

--- Get slot type
---@return string
function ItemSlot:GetSlotType()
    return self.props.slotType
end

--- Get slot category
---@return string "equipment" or "inventory"
function ItemSlot:GetSlotCategory()
    return self.props.slotCategory
end

--- Check if this slot can accept an item type
--- Validation rules:
---   - slotType = "any": accepts any item type (used for inventory grid)
---   - slotType = "helmet": only accepts items with item.type = "helmet"
---   - slotType must match item.type exactly for equipment slots
---@param itemType string The item's type field (e.g., "helmet", "weapon", "armor")
---@return boolean True if this slot can accept the item type
function ItemSlot:CanAcceptType(itemType)
    -- "any" type accepts all items (typically used for inventory slots)
    if self.props.slotType == "any" then
        return true
    end
    -- Equipment slots require exact type match
    return self.props.slotType == itemType
end

-- ============================================================================
-- Drag and Drop
-- ============================================================================

function ItemSlot:OnPointerDown(event)
    Widget.OnPointerDown(self, event)

    local item = self.props.item
    local dragCtx = self.props.dragContext

    if item and dragCtx then
        -- Start dragging
        dragCtx:StartDrag(item, self, item.icon, event.x, event.y)
        return true
    end
end

function ItemSlot:OnPointerMove(event)
    local dragCtx = self.props.dragContext
    if dragCtx and dragCtx:IsDragging() then
        dragCtx:UpdateDragPosition(event.x, event.y)
    end
end

function ItemSlot:OnPointerUp(event)
    Widget.OnPointerUp(self, event)

    local dragCtx = self.props.dragContext
    if dragCtx and dragCtx:IsDragging() then
        -- Find drop target at cursor position
        local targetSlot = dragCtx:FindDropTargetAt(event.x, event.y)
        dragCtx:EndDrag(targetSlot)
    end
end

function ItemSlot:OnPointerEnter(event)
    Widget.OnPointerEnter(self, event)
    self.isHovered_ = true

    local dragCtx = self.props.dragContext
    if dragCtx and dragCtx:IsDragging() then
        self.isDragOver_ = true
        -- Highlight valid/invalid drop
        local dragData = dragCtx:GetDragData()
        if dragData and self:CanAcceptType(dragData.type) then
            self.props.borderColor = { 100, 200, 100, 255 }  -- Green: valid
        else
            self.props.borderColor = { 200, 100, 100, 255 }  -- Red: invalid
        end
    else
        self.props.borderColor = { 100, 150, 255, 255 }  -- Blue: hover
    end
end

function ItemSlot:OnPointerLeave(event)
    Widget.OnPointerLeave(self, event)
    self.isHovered_ = false
    self.isDragOver_ = false
    self.props.borderColor = { 60, 65, 75, 255 }  -- Default
end

function ItemSlot:OnClick(event)
    if self.props.onSlotClick then
        self.props.onSlotClick(self, self.props.item)
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function ItemSlot:Destroy()
    -- Unregister from drag context
    if self.props.dragContext then
        self.props.dragContext:UnregisterDropTarget(self)
    end
    Widget.Destroy(self)
end

return ItemSlot
