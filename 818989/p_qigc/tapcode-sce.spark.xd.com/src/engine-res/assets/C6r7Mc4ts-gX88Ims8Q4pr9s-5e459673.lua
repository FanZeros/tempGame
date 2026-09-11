-- ============================================================================
-- Gesture Recognition System
-- UrhoX UI Library - Yoga + NanoVG
-- Recognizes tap, long-press, swipe, pan, pinch gestures
-- ============================================================================

local GestureEvent = require("urhox-libs/UI/Core/GestureEvent")
local Input = require("urhox-libs/UI/Core/Input")

local Gesture = {}

-- ============================================================================
-- Time Helper
-- ============================================================================

--- Get current time in milliseconds (wall time, not CPU time)
--- os.clock() returns CPU time which is unreliable on Web/WASM
--- Use engine's time:GetElapsedTime() for accurate wall time
local function getTimeMs()
    if time and time.GetElapsedTime then
        -- Urho3D engine time (seconds) -> milliseconds
        return time:GetElapsedTime() * 1000
    elseif time and time.elapsedTime then
        -- Alternative property access
        return time.elapsedTime * 1000
    else
        -- Fallback to os.clock() (may be inaccurate on some platforms)
        return os.clock() * 1000
    end
end

-- ============================================================================
-- Configuration
-- ============================================================================

Gesture.Config = {
    -- Tap settings
    tapMaxDuration = 300,           -- Max ms for a tap
    tapMaxDistance = 10,            -- Max pixels moved for a tap
    doubleTapMaxInterval = 300,     -- Max ms between taps for double-tap
    doubleTapMaxDistance = 30,      -- Max distance between double-tap locations

    -- Long press settings
    longPressMinDuration = 500,     -- Min ms to trigger long press
    longPressMaxDistance = 10,      -- Max pixels moved during long press

    -- Swipe settings
    swipeMinDistance = 50,          -- Min pixels for a swipe
    swipeMaxDuration = 500,         -- Max ms for a swipe
    swipeMinVelocity = 0.3,         -- Min pixels/ms velocity

    -- Pan settings
    panMinDistance = 5,             -- Min pixels to start pan

    -- Pinch settings
    pinchMinDistance = 10,          -- Min finger distance change to trigger
}

-- ============================================================================
-- Internal State
-- ============================================================================

-- Pointer tracking: { pointerId = { startX, startY, startTime, lastX, lastY, ... } }
local pointers_ = {}

-- Last tap info for double-tap detection
local lastTap_ = nil

-- Long press timer simulation (using update check)
local longPressPointers_ = {}  -- { pointerId = { triggered, startTime } }

-- Active gestures
local activeGestures_ = {}  -- { pointerId = "pan" | "longpress" | nil }

-- Event callback
local eventCallback_ = nil

-- Global listeners: { gestureType = { { handler, priority, id } } }
local listeners_ = {}
local listenerId_ = 0

-- ============================================================================
-- Initialization
-- ============================================================================

--- Initialize gesture recognition
---@param callback function Callback for gesture events
function Gesture.Init(callback)
    eventCallback_ = callback

    -- Subscribe to pointer events
    Input.On(Input.PointerDown, function(event)
        Gesture.HandlePointerDown(event)
    end)

    Input.On(Input.PointerMove, function(event)
        Gesture.HandlePointerMove(event)
    end)

    Input.On(Input.PointerUp, function(event)
        Gesture.HandlePointerUp(event)
    end)

    Input.On(Input.PointerCancel, function(event)
        Gesture.HandlePointerCancel(event)
    end)
end

-- ============================================================================
-- Event Subscription
-- ============================================================================

--- Subscribe to a gesture type globally
---@param gestureType string Gesture type (e.g., "Tap", "Swipe")
---@param handler function Callback function(event)
---@param priority number|nil Priority (higher = called first)
---@return number Listener ID
function Gesture.On(gestureType, handler, priority)
    if not listeners_[gestureType] then
        listeners_[gestureType] = {}
    end

    listenerId_ = listenerId_ + 1
    local id = listenerId_

    table.insert(listeners_[gestureType], {
        handler = handler,
        priority = priority or 0,
        id = id,
    })

    -- Sort by priority (descending)
    table.sort(listeners_[gestureType], function(a, b)
        return a.priority > b.priority
    end)

    return id
end

--- Unsubscribe by listener ID
---@param gestureType string Gesture type
---@param listenerId number Listener ID
function Gesture.Off(gestureType, listenerId)
    local list = listeners_[gestureType]
    if not list then return end

    for i = #list, 1, -1 do
        if list[i].id == listenerId then
            table.remove(list, i)
            break
        end
    end
end

--- Remove all gesture listeners
---@param gestureType string|nil Gesture type (nil = all)
function Gesture.RemoveAllListeners(gestureType)
    if gestureType then
        listeners_[gestureType] = {}
    else
        listeners_ = {}
    end
end

-- ============================================================================
-- Internal: Dispatch Gesture Event
-- ============================================================================

local function dispatchGesture(event)
    -- Dispatch to global listeners
    local list = listeners_[event.type]
    if list then
        for _, listener in ipairs(list) do
            if event:IsPropagationStopped() then break end
            listener.handler(event)
        end
    end

    -- Also dispatch generic gesture type
    -- e.g., SwipeLeft also dispatches to "Swipe" listeners
    if event:IsSwipe() and event.type ~= GestureEvent.Types.Swipe then
        local swipeList = listeners_[GestureEvent.Types.Swipe]
        if swipeList then
            for _, listener in ipairs(swipeList) do
                if event:IsPropagationStopped() then break end
                listener.handler(event)
            end
        end
    end

    -- Dispatch to callback
    if eventCallback_ then
        eventCallback_(event)
    end
end

-- ============================================================================
-- Pointer Event Handlers
-- ============================================================================

--- Handle pointer down
---@param event PointerEvent
function Gesture.HandlePointerDown(event)
    local id = event.pointerId
    local now = getTimeMs()

    pointers_[id] = {
        startX = event.x,
        startY = event.y,
        startTime = now,
        lastX = event.x,
        lastY = event.y,
        lastTime = now,
        pointerType = event.pointerType,
        target = event.target,
        moved = false,
        totalDistance = 0,
    }

    -- Start long press tracking
    longPressPointers_[id] = {
        triggered = false,
        startTime = now,
    }

    activeGestures_[id] = nil
end

--- Handle pointer move
---@param event PointerEvent
function Gesture.HandlePointerMove(event)
    local id = event.pointerId
    local pointer = pointers_[id]
    if not pointer then return end

    local now = getTimeMs()
    local dx = event.x - pointer.lastX
    local dy = event.y - pointer.lastY
    local distFromStart = math.sqrt(
        (event.x - pointer.startX)^2 +
        (event.y - pointer.startY)^2
    )

    pointer.totalDistance = pointer.totalDistance + math.sqrt(dx*dx + dy*dy)
    pointer.lastX = event.x
    pointer.lastY = event.y
    pointer.lastTime = now

    -- Check if moved beyond tap threshold
    if distFromStart > Gesture.Config.tapMaxDistance then
        pointer.moved = true
    end

    -- Check if moved beyond long press threshold (cancel long press)
    if distFromStart > Gesture.Config.longPressMaxDistance then
        local lpInfo = longPressPointers_[id]
        if lpInfo and lpInfo.triggered then
            -- End long press due to movement
            local gestureEvent = GestureEvent.new(GestureEvent.Types.LongPressEnd, {
                x = event.x,
                y = event.y,
                pointerId = id,
                pointerType = pointer.pointerType,
                target = pointer.target,
                duration = now - pointer.startTime,
            })
            dispatchGesture(gestureEvent)
            longPressPointers_[id] = nil
            activeGestures_[id] = nil
        end
    end

    -- Start pan if moved enough and no other gesture active
    if not activeGestures_[id] and distFromStart > Gesture.Config.panMinDistance then
        activeGestures_[id] = "pan"

        local gestureEvent = GestureEvent.new(GestureEvent.Types.PanStart, {
            x = event.x,
            y = event.y,
            pointerId = id,
            pointerType = pointer.pointerType,
            target = pointer.target,
            deltaX = event.x - pointer.startX,
            deltaY = event.y - pointer.startY,
            totalDeltaX = event.x - pointer.startX,
            totalDeltaY = event.y - pointer.startY,
        })
        dispatchGesture(gestureEvent)
    end

    -- Continue pan
    if activeGestures_[id] == "pan" then
        local gestureEvent = GestureEvent.new(GestureEvent.Types.PanMove, {
            x = event.x,
            y = event.y,
            pointerId = id,
            pointerType = pointer.pointerType,
            target = pointer.target,
            deltaX = dx,
            deltaY = dy,
            totalDeltaX = event.x - pointer.startX,
            totalDeltaY = event.y - pointer.startY,
        })
        dispatchGesture(gestureEvent)
    end
end

--- Handle pointer up
---@param event PointerEvent
function Gesture.HandlePointerUp(event)
    local id = event.pointerId
    local pointer = pointers_[id]
    if not pointer then return end

    local now = getTimeMs()
    local duration = now - pointer.startTime

    local dx = event.x - pointer.startX
    local dy = event.y - pointer.startY
    local distance = math.sqrt(dx*dx + dy*dy)

    -- End pan gesture if active
    if activeGestures_[id] == "pan" then
        local gestureEvent = GestureEvent.new(GestureEvent.Types.PanEnd, {
            x = event.x,
            y = event.y,
            pointerId = id,
            pointerType = pointer.pointerType,
            target = pointer.target,
            deltaX = event.x - pointer.lastX,
            deltaY = event.y - pointer.lastY,
            totalDeltaX = dx,
            totalDeltaY = dy,
        })
        dispatchGesture(gestureEvent)

        -- Check for swipe (fast pan)
        local velocity = distance / duration
        if distance >= Gesture.Config.swipeMinDistance and
           duration <= Gesture.Config.swipeMaxDuration and
           velocity >= Gesture.Config.swipeMinVelocity then

            local direction, specificType = Gesture.DetermineSwipeDirection(dx, dy)
            local swipeEvent = GestureEvent.new(specificType, {
                x = event.x,
                y = event.y,
                pointerId = id,
                pointerType = pointer.pointerType,
                target = pointer.target,
                direction = direction,
                velocity = velocity,
                distance = distance,
                deltaX = dx,
                deltaY = dy,
            })
            dispatchGesture(swipeEvent)
        end

    -- End long press if active
    elseif activeGestures_[id] == "longpress" then
        local gestureEvent = GestureEvent.new(GestureEvent.Types.LongPressEnd, {
            x = event.x,
            y = event.y,
            pointerId = id,
            pointerType = pointer.pointerType,
            target = pointer.target,
            duration = duration,
        })
        dispatchGesture(gestureEvent)

    -- Check for tap
    elseif not pointer.moved and duration <= Gesture.Config.tapMaxDuration then
        -- Check for double tap
        local isDoubleTap = false
        if lastTap_ then
            local timeSinceLastTap = now - lastTap_.time
            local distFromLastTap = math.sqrt(
                (event.x - lastTap_.x)^2 +
                (event.y - lastTap_.y)^2
            )

            if timeSinceLastTap <= Gesture.Config.doubleTapMaxInterval and
               distFromLastTap <= Gesture.Config.doubleTapMaxDistance then
                isDoubleTap = true
            end
        end

        if isDoubleTap then
            local gestureEvent = GestureEvent.new(GestureEvent.Types.DoubleTap, {
                x = event.x,
                y = event.y,
                pointerId = id,
                pointerType = pointer.pointerType,
                target = pointer.target,
                tapCount = 2,
            })
            dispatchGesture(gestureEvent)
            lastTap_ = nil
        else
            local gestureEvent = GestureEvent.new(GestureEvent.Types.Tap, {
                x = event.x,
                y = event.y,
                pointerId = id,
                pointerType = pointer.pointerType,
                target = pointer.target,
                tapCount = 1,
            })
            dispatchGesture(gestureEvent)

            lastTap_ = {
                x = event.x,
                y = event.y,
                time = now,
            }
        end
    end

    -- Cleanup
    pointers_[id] = nil
    longPressPointers_[id] = nil
    activeGestures_[id] = nil
end

--- Handle pointer cancel
---@param event PointerEvent
function Gesture.HandlePointerCancel(event)
    local id = event.pointerId
    local pointer = pointers_[id]

    -- Cancel any active gestures
    if pointer and activeGestures_[id] == "pan" then
        local gestureEvent = GestureEvent.new(GestureEvent.Types.PanEnd, {
            x = event.x,
            y = event.y,
            pointerId = id,
            pointerType = pointer.pointerType,
            target = pointer.target,
            deltaX = 0,
            deltaY = 0,
            totalDeltaX = event.x - pointer.startX,
            totalDeltaY = event.y - pointer.startY,
        })
        dispatchGesture(gestureEvent)
    end

    if pointer and activeGestures_[id] == "longpress" then
        local gestureEvent = GestureEvent.new(GestureEvent.Types.LongPressEnd, {
            x = pointer.lastX,
            y = pointer.lastY,
            pointerId = id,
            pointerType = pointer.pointerType,
            target = pointer.target,
            duration = (getTimeMs()) - pointer.startTime,
        })
        dispatchGesture(gestureEvent)
    end

    -- Cleanup
    pointers_[id] = nil
    longPressPointers_[id] = nil
    activeGestures_[id] = nil
end

-- ============================================================================
-- Update (for long press detection)
-- ============================================================================

--- Call this every frame to check for long press
---@param dt number Delta time in seconds (optional, not used)
function Gesture.Update(dt)
    local now = getTimeMs()

    for id, lpInfo in pairs(longPressPointers_) do
        if not lpInfo.triggered then
            local pointer = pointers_[id]
            if pointer then
                local elapsed = now - pointer.startTime
                local distFromStart = math.sqrt(
                    (pointer.lastX - pointer.startX)^2 +
                    (pointer.lastY - pointer.startY)^2
                )

                -- Check if long press should trigger
                if elapsed >= Gesture.Config.longPressMinDuration and
                   distFromStart <= Gesture.Config.longPressMaxDistance and
                   not activeGestures_[id] then

                    lpInfo.triggered = true
                    activeGestures_[id] = "longpress"

                    local gestureEvent = GestureEvent.new(GestureEvent.Types.LongPressStart, {
                        x = pointer.lastX,
                        y = pointer.lastY,
                        pointerId = id,
                        pointerType = pointer.pointerType,
                        target = pointer.target,
                        duration = elapsed,
                    })
                    dispatchGesture(gestureEvent)
                end
            end
        end
    end

    -- Clear old lastTap_ if expired
    if lastTap_ and (now - lastTap_.time) > Gesture.Config.doubleTapMaxInterval then
        lastTap_ = nil
    end
end

-- ============================================================================
-- Utilities
-- ============================================================================

--- Determine swipe direction from delta
---@param dx number
---@param dy number
---@return string direction, string specificType
function Gesture.DetermineSwipeDirection(dx, dy)
    local absDx = math.abs(dx)
    local absDy = math.abs(dy)

    if absDx > absDy then
        -- Horizontal swipe
        if dx > 0 then
            return GestureEvent.Directions.Right, GestureEvent.Types.SwipeRight
        else
            return GestureEvent.Directions.Left, GestureEvent.Types.SwipeLeft
        end
    else
        -- Vertical swipe
        if dy > 0 then
            return GestureEvent.Directions.Down, GestureEvent.Types.SwipeDown
        else
            return GestureEvent.Directions.Up, GestureEvent.Types.SwipeUp
        end
    end
end

--- Get currently active gesture for a pointer
---@param pointerId number
---@return string|nil Gesture type or nil
function Gesture.GetActiveGesture(pointerId)
    return activeGestures_[pointerId]
end

--- Check if any pointer has an active gesture
---@return boolean
function Gesture.HasActiveGesture()
    return next(activeGestures_) ~= nil
end

--- Reset all gesture tracking
function Gesture.Reset()
    pointers_ = {}
    longPressPointers_ = {}
    activeGestures_ = {}
    lastTap_ = nil
end

-- ============================================================================
-- Re-export GestureEvent for convenience
-- ============================================================================

Gesture.Event = GestureEvent
Gesture.Types = GestureEvent.Types
Gesture.Directions = GestureEvent.Directions

return Gesture
