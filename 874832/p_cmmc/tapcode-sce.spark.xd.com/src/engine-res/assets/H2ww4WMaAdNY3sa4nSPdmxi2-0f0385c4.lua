-- ============================================================================
-- Input Adapter
-- UrhoX UI Library - Yoga + NanoVG
-- Platform-specific input handling -> Unified Pointer Events
-- ============================================================================

local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")
local Input = require("urhox-libs/UI/Core/Input")

local InputAdapter = {}

-- ============================================================================
-- Internal State
-- ============================================================================

-- Platform type
local platform_ = "unknown"

-- Mouse button state (for buttons bitmask)
local mouseButtons_ = 0

-- Touch state: { touchId = { pointerId, x, y } }
local activeTouches_ = {}

-- Pointer ID counter for touch
local nextTouchPointerId_ = 1

-- Event callback (set by UI manager)
local eventCallback_ = nil

-- ============================================================================
-- Platform Detection
-- ============================================================================

--- Detect current platform
---@return string "desktop" | "mobile" | "web"
local function detectPlatform()
    -- Check for platform globals (Urho3D specific)
    if GetPlatform then
        local p = GetPlatform()
        if p == "Android" or p == "iOS" or p == "HarmonyOS" then
            return "mobile"
        elseif p == "Web" then
            return "web"
        else
            return "desktop"
        end
    end

    -- Fallback: check for touch support
    if input and input.numTouches ~= nil then
        return "mobile"
    end

    return "desktop"
end

-- ============================================================================
-- Initialization
-- ============================================================================

--- Initialize the input adapter
---@param callback function Event callback function(event)
function InputAdapter.Init(callback)
    eventCallback_ = callback
    platform_ = detectPlatform()

    -- Register with Input module
    Input.SetAdapter(InputAdapter)

    return InputAdapter
end

--- Get detected platform
---@return string
function InputAdapter.GetPlatform()
    return platform_
end

--- Check if on mobile platform
---@return boolean
function InputAdapter.IsMobile()
    return platform_ == "mobile"
end

--- Check if on desktop platform
---@return boolean
function InputAdapter.IsDesktop()
    return platform_ == "desktop"
end

-- ============================================================================
-- Internal: Dispatch Event
-- ============================================================================

local function dispatchEvent(event)
    -- Dispatch to global Input listeners
    Input.DispatchGlobal(event)

    -- Dispatch to UI callback
    if eventCallback_ then
        eventCallback_(event)
    end
end

-- ============================================================================
-- Mouse Event Handlers (Desktop)
-- ============================================================================

--- Handle mouse move event from engine
---@param x number
---@param y number
function InputAdapter.HandleMouseMove(x, y)
    local deltaX, deltaY = Input.CalculateDelta(0, x, y)

    local event = PointerEvent.new(PointerEvent.Types.PointerMove, {
        pointerId = 0,
        pointerType = PointerEvent.PointerTypes.Mouse,
        x = x,
        y = y,
        pressure = mouseButtons_ > 0 and 0.5 or 0,
        button = -1,  -- No button change
        buttons = mouseButtons_,
        isPrimary = true,
        deltaX = deltaX,
        deltaY = deltaY,
    })

    Input.UpdatePointer(0, x, y)
    dispatchEvent(event)
end

--- Handle mouse button down event from engine
---@param x number
---@param y number
---@param button number 0=left, 1=middle, 2=right
function InputAdapter.HandleMouseDown(x, y, button)
    -- Update button bitmask
    local buttonBit = 1 << button
    mouseButtons_ = mouseButtons_ | buttonBit

    local event = PointerEvent.new(PointerEvent.Types.PointerDown, {
        pointerId = 0,
        pointerType = PointerEvent.PointerTypes.Mouse,
        x = x,
        y = y,
        pressure = 0.5,
        button = button,
        buttons = mouseButtons_,
        isPrimary = true,
    })

    Input.RegisterPointer(0, {
        x = x,
        y = y,
        pointerType = PointerEvent.PointerTypes.Mouse,
        buttons = mouseButtons_,
    })

    dispatchEvent(event)
end

--- Handle mouse button up event from engine
---@param x number
---@param y number
---@param button number 0=left, 1=middle, 2=right
function InputAdapter.HandleMouseUp(x, y, button)
    -- Update button bitmask
    local buttonBit = 1 << button
    mouseButtons_ = mouseButtons_ & ~buttonBit

    local event = PointerEvent.new(PointerEvent.Types.PointerUp, {
        pointerId = 0,
        pointerType = PointerEvent.PointerTypes.Mouse,
        x = x,
        y = y,
        pressure = 0,
        button = button,
        buttons = mouseButtons_,
        isPrimary = true,
    })

    if mouseButtons_ == 0 then
        Input.UnregisterPointer(0)
    end

    dispatchEvent(event)
end

-- ============================================================================
-- Touch Event Handlers (Mobile)
-- ============================================================================

--- Handle touch begin event from engine
---@param touchId number Engine touch ID
---@param x number
---@param y number
---@param pressure number|nil
function InputAdapter.HandleTouchBegin(touchId, x, y, pressure)
    pressure = pressure or 1.0

    -- Assign a pointer ID
    local pointerId = nextTouchPointerId_
    nextTouchPointerId_ = nextTouchPointerId_ + 1

    -- Track touch
    activeTouches_[touchId] = {
        pointerId = pointerId,
        x = x,
        y = y,
    }

    local isPrimary = Input.GetPointerCount() == 0

    local event = PointerEvent.new(PointerEvent.Types.PointerDown, {
        pointerId = pointerId,
        pointerType = PointerEvent.PointerTypes.Touch,
        x = x,
        y = y,
        pressure = pressure,
        button = PointerEvent.Button.Left,  -- Touch is primary button
        buttons = PointerEvent.Buttons.Primary,  -- Buttons bitmask: 1 = primary pressed
        isPrimary = isPrimary,
    })

    Input.RegisterPointer(pointerId, {
        x = x,
        y = y,
        pointerType = PointerEvent.PointerTypes.Touch,
        buttons = 1,
    })

    dispatchEvent(event)
end

--- Handle touch move event from engine
---@param touchId number Engine touch ID
---@param x number
---@param y number
---@param pressure number|nil
function InputAdapter.HandleTouchMove(touchId, x, y, pressure)
    local touch = activeTouches_[touchId]
    if not touch then return end

    pressure = pressure or 1.0
    local pointerId = touch.pointerId

    local deltaX, deltaY = Input.CalculateDelta(pointerId, x, y)

    local event = PointerEvent.new(PointerEvent.Types.PointerMove, {
        pointerId = pointerId,
        pointerType = PointerEvent.PointerTypes.Touch,
        x = x,
        y = y,
        pressure = pressure,
        button = -1,
        buttons = 1,
        isPrimary = pointerId == 1,
        deltaX = deltaX,
        deltaY = deltaY,
    })

    touch.x = x
    touch.y = y
    Input.UpdatePointer(pointerId, x, y)

    dispatchEvent(event)
end

--- Handle touch end event from engine
---@param touchId number Engine touch ID
---@param x number
---@param y number
function InputAdapter.HandleTouchEnd(touchId, x, y)
    local touch = activeTouches_[touchId]
    if not touch then return end

    local pointerId = touch.pointerId

    local event = PointerEvent.new(PointerEvent.Types.PointerUp, {
        pointerId = pointerId,
        pointerType = PointerEvent.PointerTypes.Touch,
        x = x,
        y = y,
        pressure = 0,
        button = PointerEvent.Button.Left,  -- Touch release is primary button
        buttons = 0,  -- No buttons pressed after release
        isPrimary = pointerId == 1,
    })

    Input.UnregisterPointer(pointerId)
    activeTouches_[touchId] = nil

    dispatchEvent(event)
end

--- Handle touch cancel event from engine (e.g., incoming call)
---@param touchId number Engine touch ID
function InputAdapter.HandleTouchCancel(touchId)
    local touch = activeTouches_[touchId]
    if not touch then return end

    local pointerId = touch.pointerId

    local event = PointerEvent.new(PointerEvent.Types.PointerCancel, {
        pointerId = pointerId,
        pointerType = PointerEvent.PointerTypes.Touch,
        x = touch.x,
        y = touch.y,
        pressure = 0,
        button = PointerEvent.Button.Left,  -- Touch cancel is primary button
        buttons = 0,
        isPrimary = pointerId == 1,
    })

    Input.UnregisterPointer(pointerId)
    activeTouches_[touchId] = nil

    dispatchEvent(event)
end

-- ============================================================================
-- Unified Handlers (Auto-detect platform)
-- ============================================================================

--- Universal pointer down handler
--- Call this from engine event, it will route to correct handler
---@param x number
---@param y number
---@param buttonOrTouchId number Mouse button (desktop) or touch ID (mobile)
---@param pressure number|nil Pressure (touch only)
function InputAdapter.OnPointerDown(x, y, buttonOrTouchId, pressure)
    if platform_ == "mobile" then
        InputAdapter.HandleTouchBegin(buttonOrTouchId, x, y, pressure)
    else
        InputAdapter.HandleMouseDown(x, y, buttonOrTouchId)
    end
end

--- Universal pointer move handler
---@param x number
---@param y number
---@param touchId number|nil Touch ID (mobile only, nil for mouse)
---@param pressure number|nil Pressure (touch only)
function InputAdapter.OnPointerMove(x, y, touchId, pressure)
    if platform_ == "mobile" and touchId then
        InputAdapter.HandleTouchMove(touchId, x, y, pressure)
    else
        InputAdapter.HandleMouseMove(x, y)
    end
end

--- Universal pointer up handler
---@param x number
---@param y number
---@param buttonOrTouchId number Mouse button (desktop) or touch ID (mobile)
function InputAdapter.OnPointerUp(x, y, buttonOrTouchId)
    if platform_ == "mobile" then
        InputAdapter.HandleTouchEnd(buttonOrTouchId, x, y)
    else
        InputAdapter.HandleMouseUp(x, y, buttonOrTouchId)
    end
end

-- ============================================================================
-- Reset
-- ============================================================================

--- Reset all input state (e.g., when app loses focus)
function InputAdapter.Reset()
    -- Cancel all active touches
    for touchId, touch in pairs(activeTouches_) do
        InputAdapter.HandleTouchCancel(touchId)
    end

    -- Reset mouse
    mouseButtons_ = 0
    Input.UnregisterPointer(0)

    activeTouches_ = {}
end

return InputAdapter
