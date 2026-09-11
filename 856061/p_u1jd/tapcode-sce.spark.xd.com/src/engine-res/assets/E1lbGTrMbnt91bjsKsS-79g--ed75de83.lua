-- ============================================================================
-- DragDropContext Component
-- UrhoX UI Library - Drag and Drop management
--
-- Manages drag state and renders dragging item at highest z-order.
-- Usage:
--   local dragCtx = DragDropContext { }
--   dragCtx:StartDrag(itemData, iconWidget, sourceSlot)
--   dragCtx:EndDrag(targetSlot)
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Panel = require("urhox-libs/UI/Widgets/Panel")
local Label = require("urhox-libs/UI/Widgets/Label")
local UI = require("urhox-libs/UI/Core/UI")
local Theme = require("urhox-libs/UI/Core/Theme")

---@class DragDropContextProps : WidgetProps
---@field onDragStart? fun(itemData: any, sourceSlot: any) Called when drag starts
---@field onDragEnd? fun(itemData: any, sourceSlot: any, targetSlot: any, success: boolean) Called when drag ends
---@field onDragCancel? fun(itemData: any, sourceSlot: any) Called when drag is cancelled
---@field canDrop? fun(itemData: any, sourceSlot: any, targetSlot: any): boolean|nil Validates drop target

---@class DragDropContext : Widget
---@overload fun(props?: DragDropContextProps): DragDropContext
---@field props DragDropContextProps
---@field new fun(self, props?: DragDropContextProps): DragDropContext
local DragDropContext = Widget:Extend("DragDropContext")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props DragDropContextProps?
function DragDropContext:Init(props)
    props = props or {}

    -- Internal drag state
    self.isDragging_ = false
    self.dragData_ = nil        -- The item being dragged
    self.sourceSlot_ = nil      -- Where the drag started
    self.dragIcon_ = nil        -- Visual representation during drag
    self.dragOffsetX_ = 0       -- Offset from cursor to icon center
    self.dragOffsetY_ = 0
    self.cursorX_ = 0
    self.cursorY_ = 0

    -- Registered drop targets
    self.dropTargets_ = {}

    -- Store reference globally for slots to access
    self.props = props

    Widget.Init(self, props)

    -- Create drag layer (rendered on top)
    self:BuildDragLayer()
end

-- ============================================================================
-- Drag Layer
-- ============================================================================

function DragDropContext:BuildDragLayer()
    -- Drag icon container (invisible until dragging)
    -- pointerEvents = "none" so it doesn't block hover detection on drop targets
    self.dragIcon_ = Panel {
        position = "absolute",
        left = 0,
        top = 0,
        width = 64,
        height = 64,
        backgroundColor = { 60, 60, 80, 200 },
        borderRadius = 8,
        borderWidth = 2,
        borderColor = { 100, 150, 255, 255 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "none",
    }

    self.dragIconLabel_ = Label {
        text = "",
        fontSize = 32,
        textAlign = "center",
        pointerEvents = "none",
    }
    self.dragIcon_:AddChild(self.dragIconLabel_)
    self.dragIcon_:SetVisible(false)

    Widget.AddChild(self, self.dragIcon_)
end

-- ============================================================================
-- Drag Operations
-- ============================================================================

--- Start dragging an item
---@param itemData table The item data being dragged
---@param sourceSlot table The slot where drag started
---@param icon string Icon to display (emoji or path)
---@param cursorX number Current cursor X position
---@param cursorY number Current cursor Y position
function DragDropContext:StartDrag(itemData, sourceSlot, icon, cursorX, cursorY)
    if self.isDragging_ then return end

    self.isDragging_ = true
    self.dragData_ = itemData
    self.sourceSlot_ = sourceSlot
    self.cursorX_ = cursorX
    self.cursorY_ = cursorY

    -- Set drag icon
    self.dragIconLabel_:SetText(icon or "📦")
    self.dragIcon_:SetVisible(true)

    -- Position at cursor
    self:UpdateDragPosition(cursorX, cursorY)

    -- Callback
    if self.props.onDragStart then
        self.props.onDragStart(itemData, sourceSlot)
    end
end

--- Update drag position (call on mouse move)
---@param x number Cursor X (screen coordinates)
---@param y number Cursor Y (screen coordinates)
function DragDropContext:UpdateDragPosition(x, y)
    if not self.isDragging_ then return end

    self.cursorX_ = x
    self.cursorY_ = y

    -- Get DragDropContext's absolute position to convert to local coords
    local contextLayout = self:GetAbsoluteLayout()

    -- x, y and contextLayout are all in base pixels now
    -- left/top are in base pixels (will be scaled by layout system)
    local iconSize = 64  -- base pixels
    self.dragIcon_:SetStyle({
        left = (x - contextLayout.x) - iconSize / 2,
        top = (y - contextLayout.y) - iconSize / 2,
    })
end

--- End drag and attempt drop
---@param targetSlot table|nil The slot where item was dropped
---@return boolean success Whether the drop was successful
function DragDropContext:EndDrag(targetSlot)
    if not self.isDragging_ then return false end

    local success = false
    local itemData = self.dragData_
    local sourceSlot = self.sourceSlot_

    -- Check if drop is valid
    if targetSlot and targetSlot ~= sourceSlot then
        local canDrop = true
        if self.props.canDrop then
            canDrop = self.props.canDrop(itemData, sourceSlot, targetSlot)
        end

        if canDrop then
            success = true
        end
    end

    -- Reset drag state
    self.isDragging_ = false
    self.dragIcon_:SetVisible(false)

    -- Callback
    if self.props.onDragEnd then
        self.props.onDragEnd(itemData, sourceSlot, targetSlot, success)
    end

    -- Clear references
    self.dragData_ = nil
    self.sourceSlot_ = nil

    return success
end

--- Cancel drag operation
function DragDropContext:CancelDrag()
    if not self.isDragging_ then return end

    local itemData = self.dragData_
    local sourceSlot = self.sourceSlot_

    -- Reset drag state
    self.isDragging_ = false
    self.dragIcon_:SetVisible(false)

    -- Callback
    if self.props.onDragCancel then
        self.props.onDragCancel(itemData, sourceSlot)
    end

    -- Clear references
    self.dragData_ = nil
    self.sourceSlot_ = nil
end

-- ============================================================================
-- Drop Target Registration
-- ============================================================================

--- Register a widget as a drop target
---@param slot table The slot widget
function DragDropContext:RegisterDropTarget(slot)
    self.dropTargets_[slot] = true
end

--- Unregister a drop target
---@param slot table The slot widget
function DragDropContext:UnregisterDropTarget(slot)
    self.dropTargets_[slot] = nil
end

--- Find drop target at position
---@param x number
---@param y number
---@return table|nil The slot at position, or nil
function DragDropContext:FindDropTargetAt(x, y)
    for slot, _ in pairs(self.dropTargets_) do
        if slot:IsVisible() then
            local layout = slot:GetAbsoluteLayout()
            if layout and
               x >= layout.x and x <= layout.x + layout.w and
               y >= layout.y and y <= layout.y + layout.h then
                return slot
            end
        end
    end
    return nil
end

-- ============================================================================
-- State Queries
-- ============================================================================

--- Check if currently dragging
---@return boolean
function DragDropContext:IsDragging()
    return self.isDragging_
end

--- Get current drag data
---@return table|nil
function DragDropContext:GetDragData()
    return self.dragData_
end

--- Get source slot
---@return table|nil
function DragDropContext:GetSourceSlot()
    return self.sourceSlot_
end

-- ============================================================================
-- Rendering
-- ============================================================================

function DragDropContext:Render(nvg)
    -- Only render drag icon, positioned absolutely
    if self.isDragging_ and self.dragIcon_ then
        -- Render at cursor position (overlay mode)
        local l = self.dragIcon_:GetLayout()
        if l then
            -- Use overlay rendering to ensure highest z-order
            UI.QueueOverlay(function()
                self.dragIcon_:Render(nvg)
            end)
        end
    end
end

return DragDropContext
