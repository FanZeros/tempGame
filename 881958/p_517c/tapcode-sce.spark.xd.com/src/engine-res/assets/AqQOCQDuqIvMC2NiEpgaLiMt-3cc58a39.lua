-- ============================================================================
-- Input Module
-- UrhoX UI Library - Yoga + NanoVG
-- Global event subscription and dispatch system
-- ============================================================================

local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")

local Input = {}

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

-- ============================================================================
-- Internal State
-- ============================================================================

-- Event listeners: { eventType = { { handler, priority, id } } }
local listeners_ = {}

-- Listener ID counter
local listenerId_ = 0

-- Active pointers: { pointerId = { x, y, pointerType, buttons, target } }
local activePointers_ = {}

-- Last pointer position (for delta calculation)
local lastPointerPositions_ = {}

-- Platform adapter reference
local adapter_ = nil

-- ============================================================================
-- Event Subscription (Global Level)
-- ============================================================================

--- Subscribe to a pointer event globally
--- Events bubble from widget to root, global listeners receive all events
---@param eventType string Event type (e.g., "PointerDown", "PointerMove")
---@param handler function Callback function(event)
---@param priority number|nil Priority (higher = called first, default 0)
---@return number Listener ID for unsubscription
function Input.On(eventType, handler, priority)
    if not listeners_[eventType] then
        listeners_[eventType] = {}
    end

    listenerId_ = listenerId_ + 1
    local id = listenerId_

    table.insert(listeners_[eventType], {
        handler = handler,
        priority = priority or 0,
        id = id,
    })

    -- Sort by priority (descending)
    table.sort(listeners_[eventType], function(a, b)
        return a.priority > b.priority
    end)

    return id
end

--- Unsubscribe by listener ID
---@param eventType string Event type
---@param listenerId number Listener ID returned by On()
function Input.Off(eventType, listenerId)
    local list = listeners_[eventType]
    if not list then return end

    for i = #list, 1, -1 do
        if list[i].id == listenerId then
            table.remove(list, i)
            break
        end
    end
end

--- Subscribe to event, auto-unsubscribe after first call
---@param eventType string Event type
---@param handler function Callback function(event)
---@return number Listener ID
function Input.Once(eventType, handler)
    local id
    id = Input.On(eventType, function(event)
        Input.Off(eventType, id)
        handler(event)
    end)
    return id
end

--- Remove all listeners for an event type
---@param eventType string|nil Event type (nil = all)
function Input.RemoveAllListeners(eventType)
    if eventType then
        listeners_[eventType] = {}
    else
        listeners_ = {}
    end
end

-- ============================================================================
-- Event Dispatch
-- ============================================================================

--- Dispatch event to global listeners
---@param event PointerEvent
function Input.DispatchGlobal(event)
    local list = listeners_[event.type]
    if not list then return end

    for _, listener in ipairs(list) do
        if event:IsPropagationStopped() then
            break
        end
        listener.handler(event)
    end
end

--- Create and dispatch a pointer event
---@param eventType string Event type
---@param data table Event data
---@return PointerEvent The created event
function Input.Emit(eventType, data)
    local event = PointerEvent.new(eventType, data)
    Input.DispatchGlobal(event)
    return event
end

-- ============================================================================
-- Pointer State Tracking
-- ============================================================================

--- Register a pointer as active (called on PointerDown)
---@param pointerId number
---@param data table { x, y, pointerType, buttons, target }
function Input.RegisterPointer(pointerId, data)
    activePointers_[pointerId] = {
        x = data.x,
        y = data.y,
        pointerType = data.pointerType,
        buttons = data.buttons or 1,
        target = data.target,
        startX = data.x,
        startY = data.y,
        startTime = getTimeMs(),
    }
    lastPointerPositions_[pointerId] = { x = data.x, y = data.y }
end

--- Update pointer position (called on PointerMove)
---@param pointerId number
---@param x number
---@param y number
function Input.UpdatePointer(pointerId, x, y)
    local pointer = activePointers_[pointerId]
    if pointer then
        pointer.x = x
        pointer.y = y
    end
    lastPointerPositions_[pointerId] = { x = x, y = y }
end

--- Unregister a pointer (called on PointerUp/Cancel)
---@param pointerId number
function Input.UnregisterPointer(pointerId)
    activePointers_[pointerId] = nil
end

--- Get active pointer by ID
---@param pointerId number
---@return table|nil
function Input.GetPointer(pointerId)
    return activePointers_[pointerId]
end

--- Get all active pointers
---@return table
function Input.GetActivePointers()
    return activePointers_
end

--- Get number of active pointers (useful for multi-touch)
---@return number
function Input.GetPointerCount()
    local count = 0
    for _ in pairs(activePointers_) do
        count = count + 1
    end
    return count
end

--- Check if any pointer is active
---@return boolean
function Input.HasActivePointer()
    return next(activePointers_) ~= nil
end

--- Get last known position for a pointer
---@param pointerId number
---@return number # x
---@return number # y
function Input.GetLastPosition(pointerId)
    local pos = lastPointerPositions_[pointerId]
    if pos then
        return pos.x, pos.y
    end
    return 0, 0
end

--- Calculate delta from last position
---@param pointerId number
---@param x number
---@param y number
---@return number # deltaX
---@return number # deltaY
function Input.CalculateDelta(pointerId, x, y)
    local lastX, lastY = Input.GetLastPosition(pointerId)
    return x - lastX, y - lastY
end

-- ============================================================================
-- Platform Adapter
-- ============================================================================

--- Set the platform input adapter
---@param adapter table InputAdapter instance
function Input.SetAdapter(adapter)
    adapter_ = adapter
end

--- Get the current platform adapter
---@return table|nil
function Input.GetAdapter()
    return adapter_
end

-- ============================================================================
-- Convenience Shortcuts
-- ============================================================================

--- Check if primary pointer (mouse/first touch) is down
---@return boolean
function Input.IsPointerDown()
    return activePointers_[0] ~= nil
end

--- Get primary pointer position
---@return number # x
---@return number # y
function Input.GetPointerPosition()
    local pointer = activePointers_[0]
    if pointer then
        return pointer.x, pointer.y
    end
    local pos = lastPointerPositions_[0]
    if pos then
        return pos.x, pos.y
    end
    return 0, 0
end

-- ============================================================================
-- Event Type Constants (re-export for convenience)
-- ============================================================================

Input.PointerDown = PointerEvent.Types.PointerDown
Input.PointerUp = PointerEvent.Types.PointerUp
Input.PointerMove = PointerEvent.Types.PointerMove
Input.PointerEnter = PointerEvent.Types.PointerEnter
Input.PointerLeave = PointerEvent.Types.PointerLeave
Input.PointerCancel = PointerEvent.Types.PointerCancel

return Input
