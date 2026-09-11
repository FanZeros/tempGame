-- ============================================================================
-- Gesture Event
-- UrhoX UI Library - Yoga + NanoVG
-- Gesture event data structure
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

---@class GestureEvent
---@field type string Gesture type
---@field x number X coordinate where gesture occurred
---@field y number Y coordinate where gesture occurred
---@field target Widget|nil Target widget
---@field pointerId number Pointer that triggered the gesture
---@field pointerType string "mouse" | "touch"
---@field timestamp number Event timestamp
---@field tapCount number Tap count (for tap gestures)
---@field direction string Swipe direction (for swipe gestures)
---@field velocity number Swipe velocity (for swipe gestures)
---@field distance number Swipe distance (for swipe gestures)
---@field deltaX number Delta X (for pan gestures)
---@field deltaY number Delta Y (for pan gestures)
---@field totalDeltaX number Total delta X (for pan gestures)
---@field totalDeltaY number Total delta Y (for pan gestures)
---@field scale number Scale factor (for pinch gestures)
---@field centerX number Center X (for pinch gestures)
---@field centerY number Center Y (for pinch gestures)
---@field duration number Duration in ms (for long press gestures)
local GestureEvent = {}
GestureEvent.__index = GestureEvent

-- ============================================================================
-- Gesture Types
-- ============================================================================

GestureEvent.Types = {
    -- Tap gestures
    Tap = "Tap",
    DoubleTap = "DoubleTap",

    -- Long press
    LongPressStart = "LongPressStart",
    LongPressEnd = "LongPressEnd",

    -- Swipe gestures
    Swipe = "Swipe",
    SwipeLeft = "SwipeLeft",
    SwipeRight = "SwipeRight",
    SwipeUp = "SwipeUp",
    SwipeDown = "SwipeDown",

    -- Pan (drag) gestures
    PanStart = "PanStart",
    PanMove = "PanMove",
    PanEnd = "PanEnd",

    -- Pinch (zoom) gesture - multi-touch
    PinchStart = "PinchStart",
    PinchMove = "PinchMove",
    PinchEnd = "PinchEnd",
}

-- ============================================================================
-- Swipe Directions
-- ============================================================================

GestureEvent.Directions = {
    Left = "left",
    Right = "right",
    Up = "up",
    Down = "down",
    None = "none",
}

-- ============================================================================
-- Constructor
-- ============================================================================

--- Create a new GestureEvent
---@param gestureType string Gesture type
---@param data table Event data
---@return GestureEvent
function GestureEvent.new(gestureType, data)
    data = data or {}

    local event = setmetatable({}, GestureEvent)

    event.type = gestureType
    event.x = data.x or 0
    event.y = data.y or 0
    event.target = data.target
    event.pointerId = data.pointerId or 0
    event.pointerType = data.pointerType or "mouse"
    event.timestamp = data.timestamp or getTimeMs()

    -- Tap specific
    event.tapCount = data.tapCount or 1

    -- Swipe specific
    event.direction = data.direction or GestureEvent.Directions.None
    event.velocity = data.velocity or 0
    event.distance = data.distance or 0

    -- Pan specific
    event.deltaX = data.deltaX or 0
    event.deltaY = data.deltaY or 0
    event.totalDeltaX = data.totalDeltaX or 0
    event.totalDeltaY = data.totalDeltaY or 0

    -- Pinch specific
    event.scale = data.scale or 1.0
    event.centerX = data.centerX or 0
    event.centerY = data.centerY or 0

    -- Long press specific
    event.duration = data.duration or 0

    -- Internal flags
    event._propagationStopped = false

    return event
end

-- ============================================================================
-- Event Control Methods
-- ============================================================================

--- Stop event propagation
function GestureEvent:StopPropagation()
    self._propagationStopped = true
end

--- Check if propagation is stopped
---@return boolean
function GestureEvent:IsPropagationStopped()
    return self._propagationStopped
end

-- ============================================================================
-- Convenience Methods
-- ============================================================================

--- Check if this is a tap gesture
---@return boolean
function GestureEvent:IsTap()
    return self.type == GestureEvent.Types.Tap or self.type == GestureEvent.Types.DoubleTap
end

--- Check if this is a swipe gesture
---@return boolean
function GestureEvent:IsSwipe()
    return self.type == GestureEvent.Types.Swipe or
           self.type == GestureEvent.Types.SwipeLeft or
           self.type == GestureEvent.Types.SwipeRight or
           self.type == GestureEvent.Types.SwipeUp or
           self.type == GestureEvent.Types.SwipeDown
end

--- Check if this is a pan gesture
---@return boolean
function GestureEvent:IsPan()
    return self.type == GestureEvent.Types.PanStart or
           self.type == GestureEvent.Types.PanMove or
           self.type == GestureEvent.Types.PanEnd
end

--- Check if this is a long press gesture
---@return boolean
function GestureEvent:IsLongPress()
    return self.type == GestureEvent.Types.LongPressStart or
           self.type == GestureEvent.Types.LongPressEnd
end

--- Check if this is a pinch gesture
---@return boolean
function GestureEvent:IsPinch()
    return self.type == GestureEvent.Types.PinchStart or
           self.type == GestureEvent.Types.PinchMove or
           self.type == GestureEvent.Types.PinchEnd
end

--- Check if swipe is horizontal
---@return boolean
function GestureEvent:IsHorizontalSwipe()
    return self.direction == GestureEvent.Directions.Left or
           self.direction == GestureEvent.Directions.Right
end

--- Check if swipe is vertical
---@return boolean
function GestureEvent:IsVerticalSwipe()
    return self.direction == GestureEvent.Directions.Up or
           self.direction == GestureEvent.Directions.Down
end

-- ============================================================================
-- Debug
-- ============================================================================

--- Get string representation
---@return string
function GestureEvent:ToString()
    if self:IsSwipe() then
        return string.format("GestureEvent{type=%s, direction=%s, velocity=%.1f}",
            self.type, self.direction, self.velocity)
    elseif self:IsTap() then
        return string.format("GestureEvent{type=%s, tapCount=%d, x=%.1f, y=%.1f}",
            self.type, self.tapCount, self.x, self.y)
    else
        return string.format("GestureEvent{type=%s, x=%.1f, y=%.1f}",
            self.type, self.x, self.y)
    end
end

return GestureEvent
