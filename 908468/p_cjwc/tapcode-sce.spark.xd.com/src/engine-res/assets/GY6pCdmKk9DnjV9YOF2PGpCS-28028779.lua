-- ============================================================================
-- Pointer Event
-- UrhoX UI Library - Yoga + NanoVG
-- Unified pointer event (mouse + touch + pen)
-- Inspired by W3C Pointer Events specification
-- ============================================================================

-- Time helper: use engine time instead of os.clock() for accurate wall time
local function getTimeMs()
    if time and time.GetElapsedTime then
        return time:GetElapsedTime() * 1000
    elseif time and time.elapsedTime then
        return time.elapsedTime * 1000
    else
        return os.clock() * 1000
    end
end

---@class PointerEvent
---@field type string Event type: "PointerDown" | "PointerUp" | "PointerMove" | "PointerEnter" | "PointerLeave" | "PointerCancel"
---@field pointerId number Unique pointer identifier (mouse=0, touch=finger id)
---@field pointerType string "mouse" | "touch" | "pen"
---@field x number X coordinate in screen space
---@field y number Y coordinate in screen space
---@field pressure number Pressure (0.0-1.0, mouse always 0.5 when pressed)
---@field button number Button that triggered event (0=left/primary, 1=middle, 2=right)
---@field buttons number Bitmask of currently pressed buttons
---@field isPrimary boolean Is this the primary pointer
---@field timestamp number Event timestamp in milliseconds
---@field target Widget|nil Target widget (set during dispatch)
---@field currentTarget Widget|nil Current widget in propagation chain
---@field deltaX number Movement delta X (for PointerMove)
---@field deltaY number Movement delta Y (for PointerMove)
---@field _propagationStopped boolean Internal: stop propagation flag
---@field _defaultPrevented boolean Internal: prevent default flag
local PointerEvent = {}
PointerEvent.__index = PointerEvent

-- ============================================================================
-- Event Types
-- ============================================================================

PointerEvent.Types = {
    PointerDown = "PointerDown",
    PointerUp = "PointerUp",
    PointerMove = "PointerMove",
    PointerEnter = "PointerEnter",
    PointerLeave = "PointerLeave",
    PointerCancel = "PointerCancel",
}

-- ============================================================================
-- Pointer Types
-- ============================================================================

PointerEvent.PointerTypes = {
    Mouse = "mouse",
    Touch = "touch",
    Pen = "pen",
}

-- ============================================================================
-- Mouse Buttons
-- ============================================================================

-- Button index for 'button' field (which button was pressed/released)
-- Directly use Urho3D engine constants
PointerEvent.Button = {
    Left = MOUSEB_LEFT,      -- 0
    Middle = MOUSEB_MIDDLE,  -- 1
    Right = MOUSEB_RIGHT,    -- 2
}

-- Buttons bitmask for 'buttons' field (which buttons are currently pressed)
-- Calculated from engine constants
PointerEvent.Buttons = {
    None = 0,
    Primary = 1 << MOUSEB_LEFT,      -- Left mouse / touch
    Auxiliary = 1 << MOUSEB_MIDDLE,  -- Middle mouse
    Secondary = 1 << MOUSEB_RIGHT,   -- Right mouse
    -- TODO: Back = 8,     -- Mouse back (need engine support)
    -- TODO: Forward = 16, -- Mouse forward (need engine support)
}

-- ============================================================================
-- Constructor
-- ============================================================================

--- Create a new PointerEvent
---@param eventType string Event type
---@param data table Event data
---@return PointerEvent
function PointerEvent.new(eventType, data)
    data = data or {}

    local event = setmetatable({}, PointerEvent)

    event.type = eventType
    event.pointerId = data.pointerId or 0
    event.pointerType = data.pointerType or PointerEvent.PointerTypes.Mouse
    event.x = data.x or 0
    event.y = data.y or 0
    event.pressure = data.pressure or 0
    event.button = data.button or 0
    event.buttons = data.buttons or 0
    event.isPrimary = data.isPrimary ~= false  -- Default true
    event.timestamp = data.timestamp or getTimeMs()
    event.target = data.target
    event.currentTarget = nil
    event.deltaX = data.deltaX or 0
    event.deltaY = data.deltaY or 0

    -- Internal flags
    event._propagationStopped = false
    event._defaultPrevented = false

    return event
end

-- ============================================================================
-- Event Control Methods
-- ============================================================================

--- Stop event propagation (prevent bubbling to parent)
function PointerEvent:StopPropagation()
    self._propagationStopped = true
end

--- Check if propagation is stopped
---@return boolean
function PointerEvent:IsPropagationStopped()
    return self._propagationStopped
end

--- Prevent default behavior
function PointerEvent:PreventDefault()
    self._defaultPrevented = true
end

--- Check if default is prevented
---@return boolean
function PointerEvent:IsDefaultPrevented()
    return self._defaultPrevented
end

-- ============================================================================
-- Convenience Methods
-- ============================================================================

--- Check if left/primary button is pressed (mouse only)
---@return boolean
function PointerEvent:IsPrimaryButton()
    return self.button == PointerEvent.Button.Left
end

--- Check if this is a primary action that UI should respond to
--- Touch events are always primary actions (multi-touch support)
--- Mouse events only respond to left button
---@return boolean
function PointerEvent:IsPrimaryAction()
    -- Touch is always a primary action (supports multi-touch scenarios
    -- like holding joystick with left hand while tapping button with right)
    if self.pointerType == PointerEvent.PointerTypes.Touch then
        return true
    end
    -- For mouse, only left button triggers primary action
    return self.button == PointerEvent.Button.Left
end

--- Check if right/secondary button is pressed
---@return boolean
function PointerEvent:IsSecondaryButton()
    return self.button == PointerEvent.Button.Right
end

--- Check if middle button is pressed
---@return boolean
function PointerEvent:IsMiddleButton()
    return self.button == PointerEvent.Button.Middle
end

--- Check if this is a touch event
---@return boolean
function PointerEvent:IsTouch()
    return self.pointerType == PointerEvent.PointerTypes.Touch
end

--- Check if this is a mouse event
---@return boolean
function PointerEvent:IsMouse()
    return self.pointerType == PointerEvent.PointerTypes.Mouse
end

--- Check if this is a pen event
---@return boolean
function PointerEvent:IsPen()
    return self.pointerType == PointerEvent.PointerTypes.Pen
end

-- ============================================================================
-- Clone
-- ============================================================================

--- Create a copy of this event
---@return PointerEvent
function PointerEvent:Clone()
    return PointerEvent.new(self.type, {
        pointerId = self.pointerId,
        pointerType = self.pointerType,
        x = self.x,
        y = self.y,
        pressure = self.pressure,
        button = self.button,
        buttons = self.buttons,
        isPrimary = self.isPrimary,
        timestamp = self.timestamp,
        target = self.target,
        deltaX = self.deltaX,
        deltaY = self.deltaY,
    })
end

-- ============================================================================
-- Debug
-- ============================================================================

--- Get string representation
---@return string
function PointerEvent:ToString()
    return string.format(
        "PointerEvent{type=%s, id=%d, pointerType=%s, x=%.1f, y=%.1f, button=%d}",
        self.type, self.pointerId, self.pointerType, self.x, self.y, self.button
    )
end

return PointerEvent
