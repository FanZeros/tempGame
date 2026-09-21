print("[InputAdaptor] Loading input event adaptor...")

if not SubscribeToEvent then
    print("[InputAdaptor] SubscribeToEvent not found, skipping.")
    return
end

-- Event mappings: Mouse events -> Touch events
-- This allows code that subscribes to mouse events to also receive touch events
local EventMappings = {
    ['MouseButtonDown'] = 'TouchBegin',
    ['MouseButtonUp']   = 'TouchEnd',
    ['MouseMove']       = 'TouchMove',
}

-- Reverse mappings for lookup
local ReverseMappings = {}
for k, v in pairs(EventMappings) do
    ReverseMappings[v] = k
end

-- Events that have ever been subscribed, to avoid overriding existing handlers
-- Key: "eventName" or "sender:eventName", Value: true
local EverSubscribedEvents = {}

-- Helper to generate registration key
local function GetRegistrationKey(sender, eventName)
    if sender then
        return tostring(sender) .. ":" .. eventName
    end
    return eventName
end

-- Save the original SubscribeToEvent function
local ___SubscribeToEvent___ = _G.SubscribeToEvent

-- Hook SubscribeToEvent to auto-register mapped events
print("[InputAdaptor] Hooked SubscribeToEvent for event mapping.")

_G.SubscribeToEvent = function(...)
    local args = {...}
    local numArgs = select('#', ...)

    -- Determine event name position based on argument count
    -- SubscribeToEvent("EventName", "Handler") - 2 args, event is arg 1
    -- SubscribeToEvent(sender, "EventName", "Handler") - 3 args, event is arg 2
    local eventName = nil
    local eventArgIndex = nil
    local sender = nil

    if numArgs >= 2 then
        if type(args[1]) == 'string' then
            -- SubscribeToEvent("EventName", handler)
            eventName = args[1]
            eventArgIndex = 1
        elseif numArgs >= 3 and type(args[2]) == 'string' then
            -- SubscribeToEvent(sender, "EventName", handler)
            sender = args[1]
            eventName = args[2]
            eventArgIndex = 2
        end
    end

    -- Mark this event as subscribed
    if eventName then
        local regKey = GetRegistrationKey(sender, eventName)
        EverSubscribedEvents[regKey] = true
    end

    -- Call original function
    ___SubscribeToEvent___(...)

    -- Check if this event has a mapping
    if eventName and EventMappings[eventName] then
        local mappedEvent = EventMappings[eventName]
        local mappedKey = GetRegistrationKey(sender, mappedEvent)

        -- Only auto-subscribe if the mapped event has never been subscribed
        if not EverSubscribedEvents[mappedKey] then
            -- Get the original handler (last argument)
            local originalHandler = args[numArgs]

            -- Create new args with the mapped event name
            local mappedArgs = {}
            for i = 1, numArgs do
                if i == eventArgIndex then
                    mappedArgs[i] = mappedEvent
                else
                    mappedArgs[i] = args[i]
                end
            end

            -- Wrap handler to inject Button/Qualifiers fields for touch events
            -- Touch events don't have these fields, but MouseButton handlers expect them
            if type(originalHandler) == 'function' then
                mappedArgs[numArgs] = function(eventType, eventData)
                    if mappedEvent == 'TouchBegin' or mappedEvent == 'TouchEnd' then
                        eventData["Button"] = Variant(MOUSEB_LEFT)
                        eventData["Qualifiers"] = Variant(0)
                    end
                    return originalHandler(eventType, eventData)
                end
            elseif type(originalHandler) == 'string' then
                local handlerName = originalHandler
                mappedArgs[numArgs] = function(eventType, eventData)
                    if mappedEvent == 'TouchBegin' or mappedEvent == 'TouchEnd' then
                        eventData["Button"] = Variant(MOUSEB_LEFT)
                        eventData["Qualifiers"] = Variant(0)
                    end
                    local fn = _G[handlerName]
                    if fn then
                        return fn(eventType, eventData)
                    end
                end
            end

            -- Subscribe to the mapped event as well
            ___SubscribeToEvent___(table.unpack(mappedArgs))
        end
    end
end

-- ============================================================================
-- Input Method Hook: Mouse -> Touch fallback when touchEmulation is enabled
-- ============================================================================

local inputObj = GetInput()
if not inputObj then
    print("[InputAdaptor] Input subsystem not found, skipping method hook.")
    return
end

local inputMeta = getmetatable(inputObj)
if not inputMeta then
    print("[InputAdaptor] Input metatable not found, skipping method hook.")
    return
end

-- Save original methods
local ___GetMouseButtonDown___    = inputMeta.GetMouseButtonDown
local ___GetMouseButtonPress___   = inputMeta.GetMouseButtonPress
local ___GetMouseButtonRelease___ = inputMeta.GetMouseButtonRelease
local ___GetMousePosition___      = inputMeta.GetMousePosition
local ___SetMousePosition___    = inputMeta.SetMousePosition
local ___GetMouseMove___        = inputMeta.GetMouseMove
local ___GetMouseMoveX___       = inputMeta.GetMouseMoveX
local ___GetMouseMoveY___       = inputMeta.GetMouseMoveY
local ___GetNumTouches___       = inputMeta.GetNumTouches
local ___GetTouch___            = inputMeta.GetTouch
local ___GetTouchEmulation___   = inputMeta.GetTouchEmulation
local ___SetScreenKeyboardVisible___ = inputMeta.SetScreenKeyboardVisible

-- Save original __index and __newindex for property access
local ___index___ = inputMeta.__index
local ___newindex___ = inputMeta.__newindex

-- Platform detection
local platform = GetPlatform()
local isTouchPlatform = (platform == "Android" or platform == "iOS")
print("[InputAdaptor] Platform: " .. platform .. ", isTouchPlatform: " .. tostring(isTouchPlatform))

-- Helper function: should use touch input?
local function ShouldUseTouch(self)
    return isTouchPlatform or self.touchEmulation
end

-- State tracking for edge detection
local lastTouchCount = 0
-- Cached touch position: survives 1 frame after release so mousePosition
-- still returns the lift-off point on the release frame.
local cachedTouchPosition = nil

-- Hook GetMouseButtonDown
if ___GetMouseButtonDown___ then
    inputMeta.GetMouseButtonDown = function(self, button)
        if ShouldUseTouch(self) and self:GetNumTouches() > 0 then
            -- Touch is active, treat as mouse button down (only for left button)
            return button == MOUSEB_LEFT
        end
        return ___GetMouseButtonDown___(self, button)
    end
end

-- Hook GetMouseButtonPress
if ___GetMouseButtonPress___ then
    inputMeta.GetMouseButtonPress = function(self, button)
        if ShouldUseTouch(self) then
            local currentTouchCount = self:GetNumTouches()
            -- Edge detection: no touch last frame, has touch this frame = just pressed
            local pressed = (lastTouchCount == 0 and currentTouchCount > 0)
            if button == MOUSEB_LEFT then
                return pressed
            end
            return false
        end
        return ___GetMouseButtonPress___(self, button)
    end
end

-- Hook GetMouseButtonRelease
if ___GetMouseButtonRelease___ then
    inputMeta.GetMouseButtonRelease = function(self, button)
        if ShouldUseTouch(self) then
            local currentTouchCount = self:GetNumTouches()
            -- Edge detection: has touch last frame, no touch this frame = just released
            local released = (lastTouchCount > 0 and currentTouchCount == 0)
            if button == MOUSEB_LEFT then
                return released
            end
            return false
        end
        return ___GetMouseButtonRelease___(self, button)
    end
end

-- Update lastTouchCount and cachedTouchPosition at end of each frame.
-- Use a ScriptObject with self:SubscribeToEvent() so the subscription is
-- isolated to this instance and won't conflict with global EndFrame handlers.
---@class InputAdaptor_EventReceiver : LuaScriptObject
InputAdaptor_EventReceiver = ScriptObject()

function InputAdaptor_EventReceiver:Start()
    self:SubscribeToEvent("EndFrame", function()
        local currentTouchCount = inputObj:GetNumTouches()
        if currentTouchCount > 0 then
            local touch = inputObj:GetTouch(0)
            if touch then
                cachedTouchPosition = touch.position
            end
        else
            -- EndFrame runs after Update, so the release frame's Update
            -- has already consumed the cache. Safe to clear now.
            cachedTouchPosition = nil
        end
        lastTouchCount = currentTouchCount
    end)
end

local inputAdaptorNode_ = Node()
inputAdaptorNode_:CreateScriptObject("InputAdaptor_EventReceiver")

-- Hook GetMousePosition
if ___GetMousePosition___ then
    inputMeta.GetMousePosition = function(self)
        if ShouldUseTouch(self) then
            if self:GetNumTouches() > 0 then
                local touch = self:GetTouch(0)
                if touch then
                    return touch.position
                end
            elseif lastTouchCount > 0 and cachedTouchPosition then
                return cachedTouchPosition
            end
        end
        return ___GetMousePosition___(self)
    end
end

-- Hook SetMousePosition (ignored in touch mode)
if ___SetMousePosition___ then
    inputMeta.SetMousePosition = function(self, position)
        if ShouldUseTouch(self) then
            -- Ignore SetMousePosition in touch mode
            return
        end
        return ___SetMousePosition___(self, position)
    end
end

-- Hook GetMouseMove
if ___GetMouseMove___ then
    inputMeta.GetMouseMove = function(self)
        if ShouldUseTouch(self) and self:GetNumTouches() > 0 then
            local touch = self:GetTouch(0)
            if touch then
                return touch.delta
            end
        end
        return ___GetMouseMove___(self)
    end
end

-- Hook GetMouseMoveX
if ___GetMouseMoveX___ then
    inputMeta.GetMouseMoveX = function(self)
        if ShouldUseTouch(self) and self:GetNumTouches() > 0 then
            local touch = self:GetTouch(0)
            if touch then
                return touch.delta.x
            end
        end
        return ___GetMouseMoveX___(self)
    end
end

-- Hook GetMouseMoveY
if ___GetMouseMoveY___ then
    inputMeta.GetMouseMoveY = function(self)
        if ShouldUseTouch(self) and self:GetNumTouches() > 0 then
            local touch = self:GetTouch(0)
            if touch then
                return touch.delta.y
            end
        end
        return ___GetMouseMoveY___(self)
    end
end

-- AI hallucination aliases (Unity/SDL API → Urho3D API)
-- Must use rawset: normal assignment triggers metatable chains → C stack overflow.
rawset(inputMeta, 'GetMouseButtonUp', inputMeta.GetMouseButtonRelease)
-- AI 常把 "MoveWheel" 词序写反成 "WheelMove"，别名映射回真实方法
rawset(inputMeta, 'GetMouseWheelMove', inputMeta.GetMouseMoveWheel)
if ___SetScreenKeyboardVisible___ then
    rawset(inputMeta, 'StartTextInput', function(self) ___SetScreenKeyboardVisible___(self, true) end)
    rawset(inputMeta, 'StopTextInput', function(self) ___SetScreenKeyboardVisible___(self, false) end)
end

-- Helper to get original property value (avoid recursion)
local function GetOriginalProperty(self, key)
    if type(___index___) == "function" then
        return ___index___(self, key)
    elseif type(___index___) == "table" then
        return ___index___[key]
    end
    return nil
end

-- Hook __index for property access (mousePosition, mouseMove, mouseMoveX, mouseMoveY)
inputMeta.__index = function(self, key)
    -- AI hallucination: 词序颠倒 mouseWheelMove → mouseMoveWheel
    if key == "mouseWheelMove" then key = "mouseMoveWheel" end

    -- Check if we should use touch (use saved methods to avoid recursion)
    local touchEmulation = ___GetTouchEmulation___(self)
    local shouldUseTouch = isTouchPlatform or touchEmulation

    if shouldUseTouch then
        if ___GetNumTouches___(self) > 0 then
            local touch = ___GetTouch___(self, 0)
            if touch then
                if key == "mousePosition" then
                    return touch.position
                elseif key == "mouseMove" then
                    return touch.delta
                elseif key == "mouseMoveX" then
                    return touch.delta.x
                elseif key == "mouseMoveY" then
                    return touch.delta.y
                end
            end
        elseif lastTouchCount > 0 and cachedTouchPosition then
            -- Release frame: finger just lifted, return cached position
            if key == "mousePosition" then
                return cachedTouchPosition
            end
        end
    end

    -- Fallback to original __index
    return GetOriginalProperty(self, key)
end

-- Helper to set original property value (avoid recursion)
local function SetOriginalProperty(self, key, value)
    if type(___newindex___) == "function" then
        return ___newindex___(self, key, value)
    elseif type(___newindex___) == "table" then
        ___newindex___[key] = value
    else
        rawset(self, key, value)
    end
end

-- Hook __newindex for property setter (mousePosition)
inputMeta.__newindex = function(self, key, value)
    -- Check if we should use touch (use saved methods to avoid recursion)
    local touchEmulation = ___GetTouchEmulation___(self)
    local shouldUseTouch = isTouchPlatform or touchEmulation

    if shouldUseTouch then
        if key == "mousePosition" then
            -- Ignore mousePosition setter in touch mode
            return
        end
    end

    -- Fallback to original __newindex
    return SetOriginalProperty(self, key, value)
end

print("[InputAdaptor] Hooked Input methods for touch emulation fallback.")
