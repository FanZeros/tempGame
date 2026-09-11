-- ============================================================================
-- Transition System
-- UrhoX UI Library - CSS-like property transitions
-- ============================================================================
--
-- Provides duration-based property transitions with easing functions.
-- Used by Widget.lua to animate property changes smoothly.
--
-- Usage:
--   local pool = {}
--   Transition.Start(pool, "opacity", 1.0, 0.5, 0.3, "easeOut")
--   -- In update loop:
--   local hasActive = Transition.Update(pool, dt)
--   local value = Transition.GetValue(pool, "opacity")
--
-- ============================================================================

local Transition = {}

-- ============================================================================
-- Easing Functions
-- ============================================================================
-- All easing functions take t in [0, 1] and return a value in [0, 1]
-- (some functions like easeInBack/easeOutBack may overshoot slightly)

local Easing = {}

function Easing.linear(t)
    return t
end

function Easing.easeIn(t)
    return t * t
end

function Easing.easeOut(t)
    return 1 - (1 - t) * (1 - t)
end

function Easing.easeInOut(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - (-2 * t + 2) * (-2 * t + 2) / 2
    end
end

function Easing.easeInCubic(t)
    return t * t * t
end

function Easing.easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

function Easing.easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local u = -2 * t + 2
        return 1 - u * u * u / 2
    end
end

function Easing.easeInExpo(t)
    if t <= 0 then return 0 end
    return math.pow(2, 10 * t - 10)
end

function Easing.easeOutExpo(t)
    if t >= 1 then return 1 end
    return 1 - math.pow(2, -10 * t)
end

function Easing.easeInBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return c3 * t * t * t - c1 * t * t
end

function Easing.easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

function Easing.easeInOutBack(t)
    local c1 = 1.70158
    local c2 = c1 * 1.525
    if t < 0.5 then
        return (2 * t) * (2 * t) * ((c2 + 1) * 2 * t - c2) / 2
    else
        local u = 2 * t - 2
        return (u * u * ((c2 + 1) * u + c2) + 2) / 2
    end
end

function Easing.spring(t)
    -- Damped spring oscillation
    local d = 0.6  -- damping ratio
    return 1 - math.exp(-6 * t) * math.cos(12 * t * (1 - d))
end

-- Lookup table for resolving easing names
local easingMap = {
    ["linear"]        = Easing.linear,
    ["easeIn"]        = Easing.easeIn,
    ["easeOut"]       = Easing.easeOut,
    ["easeInOut"]     = Easing.easeInOut,
    ["easeInCubic"]   = Easing.easeInCubic,
    ["easeOutCubic"]  = Easing.easeOutCubic,
    ["easeInOutCubic"] = Easing.easeInOutCubic,
    ["easeInExpo"]    = Easing.easeInExpo,
    ["easeOutExpo"]   = Easing.easeOutExpo,
    ["easeInBack"]    = Easing.easeInBack,
    ["easeOutBack"]   = Easing.easeOutBack,
    ["easeInOutBack"] = Easing.easeInOutBack,
    ["spring"]        = Easing.spring,
}

--- Resolve an easing name to a function. Falls back to linear with a warning.
---@param name string|function
---@return function
function Transition.ResolveEasing(name)
    if type(name) == "function" then
        return name
    end
    local fn = easingMap[name or "linear"]
    if fn then
        return fn
    end
    -- Invalid easing name: warn and fallback to linear
    print("[UI Transition] Unknown easing '" .. tostring(name) .. "', falling back to 'linear'")
    return Easing.linear
end

-- Export easing functions for external use (e.g., Keyframe animation)
Transition.Easing = Easing

-- ============================================================================
-- Interpolators
-- ============================================================================

--- Linearly interpolate between two numbers.
---@param a number
---@param b number
---@param t number Progress in [0, 1]
---@return number
function Transition.Lerp(a, b, t)
    return a + (b - a) * t
end

--- Linearly interpolate between two RGBA color tables.
---@param a table {R, G, B, A}
---@param b table {R, G, B, A}
---@param t number Progress in [0, 1]
---@return table {R, G, B, A}
function Transition.LerpColor(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        (a[4] or 255) + ((b[4] or 255) - (a[4] or 255)) * t,
    }
end

-- ============================================================================
-- Property Classification
-- ============================================================================

-- Properties that can be transitioned (and their type)
local transitionableProps = {
    -- Numeric properties
    opacity         = "number",
    scale           = "number",
    rotate          = "number",
    translateX      = "number",
    translateY      = "number",
    borderRadius    = "number",
    borderWidth     = "number",
    shadowBlur      = "number",
    shadowOffsetX   = "number",
    shadowOffsetY   = "number",
    -- Color properties
    backgroundColor = "color",
    borderColor     = "color",
    shadowColor     = "color",
    fontColor       = "color",
}

--- Check if a property name is transitionable.
---@param propName string
---@return string|nil Type string ("number" or "color"), or nil if not transitionable
function Transition.GetPropertyType(propName)
    return transitionableProps[propName]
end

-- ============================================================================
-- Transition Pool Management
-- ============================================================================
-- A pool is a simple table (array part) of ActiveTransition entries.
-- Each widget has its own pool (widget.transitions_).
--
-- ActiveTransition structure (compact array for performance):
--   [1] = property name (string)
--   [2] = from value (number or color table)
--   [3] = to value (number or color table)
--   [4] = duration (seconds)
--   [5] = elapsed (seconds)
--   [6] = easing function
--   [7] = property type ("number" or "color")
--   [8] = current interpolated value

local IDX_PROP     = 1
local IDX_FROM     = 2
local IDX_TO       = 3
local IDX_DURATION = 4
local IDX_ELAPSED  = 5
local IDX_EASING   = 6
local IDX_TYPE     = 7
local IDX_VALUE    = 8

--- Start or redirect a transition for a property.
--- If a transition for the same property already exists, it is redirected
--- (from = current interpolated value, to = new target, elapsed reset to 0).
---@param pool table The transition pool (widget.transitions_)
---@param prop string Property name
---@param from any Start value (number or color table)
---@param to any End value (number or color table)
---@param duration number Duration in seconds
---@param easingName string|function Easing name or function
---@return table The ActiveTransition entry
function Transition.Start(pool, prop, from, to, duration, easingName)
    local easingFn = Transition.ResolveEasing(easingName)
    local propType = transitionableProps[prop]

    -- Check if there's already a running transition for this property
    for i = 1, #pool do
        local entry = pool[i]
        if entry[IDX_PROP] == prop then
            -- Redirect: use current interpolated value as new "from"
            entry[IDX_FROM] = entry[IDX_VALUE] or from
            entry[IDX_TO] = to
            entry[IDX_DURATION] = duration
            entry[IDX_ELAPSED] = 0
            entry[IDX_EASING] = easingFn
            return entry
        end
    end

    -- Create new transition entry
    local entry = {
        prop,       -- [1] property name
        from,       -- [2] from value
        to,         -- [3] to value
        duration,   -- [4] duration
        0,          -- [5] elapsed
        easingFn,   -- [6] easing function
        propType,   -- [7] property type
        from,       -- [8] current value (starts at from)
    }
    pool[#pool + 1] = entry
    return entry
end

--- Update all transitions in a pool. Returns true if any transitions are still active.
---@param pool table The transition pool
---@param dt number Delta time in seconds
---@return boolean hasActive True if at least one transition is still running
function Transition.Update(pool, dt)
    local i = 1
    local n = #pool
    while i <= n do
        local entry = pool[i]
        local elapsed = entry[IDX_ELAPSED] + dt
        local duration = entry[IDX_DURATION]

        if elapsed >= duration then
            -- Transition completed: snap to final value
            entry[IDX_VALUE] = entry[IDX_TO]
            entry[IDX_ELAPSED] = duration

            -- Remove completed entry by swapping with last
            pool[i] = pool[n]
            pool[n] = nil
            n = n - 1
            -- Don't increment i, re-check swapped entry
        else
            -- In progress: interpolate
            entry[IDX_ELAPSED] = elapsed
            local t = elapsed / duration
            local easedT = entry[IDX_EASING](t)

            if entry[IDX_TYPE] == "color" then
                entry[IDX_VALUE] = Transition.LerpColor(entry[IDX_FROM], entry[IDX_TO], easedT)
            else
                entry[IDX_VALUE] = Transition.Lerp(entry[IDX_FROM], entry[IDX_TO], easedT)
            end
            i = i + 1
        end
    end
    return n > 0
end

--- Get the current interpolated value for a property, or nil if no transition.
---@param pool table The transition pool
---@param prop string Property name
---@return any|nil Current interpolated value, or nil if no active transition
function Transition.GetValue(pool, prop)
    for i = 1, #pool do
        if pool[i][IDX_PROP] == prop then
            return pool[i][IDX_VALUE]
        end
    end
    return nil
end

--- Cancel a specific property's transition.
---@param pool table The transition pool
---@param prop string Property name
function Transition.Cancel(pool, prop)
    for i = #pool, 1, -1 do
        if pool[i][IDX_PROP] == prop then
            pool[i] = pool[#pool]
            pool[#pool] = nil
            return
        end
    end
end

--- Cancel all transitions in a pool.
---@param pool table The transition pool
function Transition.CancelAll(pool)
    for i = #pool, 1, -1 do
        pool[i] = nil
    end
end

--- Check if a pool has any active transitions.
---@param pool table The transition pool
---@return boolean
function Transition.HasActive(pool)
    return #pool > 0
end

-- ============================================================================
-- Transition Config Parsing
-- ============================================================================
-- Parses the user-facing `transition` prop into a normalized config table.
--
-- Accepted formats:
--   1. Table format:
--      { properties = {"opacity", "scale"}, duration = 0.3, easing = "easeOut" }
--
--   2. Shorthand string:
--      "all 0.3s easeOut"
--      "opacity 0.2s easeInOut"
--      "backgroundColor 0.5s"
--
-- Returns normalized config:
--   { properties = {"opacity", "scale", ...} or "all",
--     duration = 0.3,
--     easing = "easeOut" }

local warnedShorthands_ = {}

--- Parse a single "property duration [easing]" segment.
--- Returns property name, duration (seconds), easing name, or nil on error.
---@param segment string
---@return string|nil, number|nil, string|nil
local function parseSegment(segment)
    local parts = {}
    for part in segment:gmatch("%S+") do
        parts[#parts + 1] = part
    end

    if #parts < 2 then
        if not warnedShorthands_[segment] then
            warnedShorthands_[segment] = true
            print("[UI Transition] Invalid shorthand '" .. segment .. "', expected format: 'property duration [easing]'")
        end
        return nil
    end

    local prop = parts[1]
    local durationStr = parts[2]
    local easing = parts[3] or "easeOut"

    -- Parse duration: "0.3s" or "0.3" or "300ms"
    local duration
    if durationStr:match("ms$") then
        duration = tonumber(durationStr:match("^(.+)ms$"))
        if duration then duration = duration / 1000 end
    elseif durationStr:match("s$") then
        duration = tonumber(durationStr:match("^(.+)s$"))
    else
        duration = tonumber(durationStr)
    end

    if not duration or duration <= 0 then
        if not warnedShorthands_[segment] then
            warnedShorthands_[segment] = true
            print("[UI Transition] Invalid duration in '" .. segment .. "'")
        end
        return nil
    end

    return prop, duration, easing
end

--- Parse a transition prop value into a normalized config.
--- Supports CSS comma-separated format: "scale 0.8s easeInOut, opacity 0.3s linear"
---@param value table|string|nil
---@return table|nil Normalized config, or nil if invalid
function Transition.ParseConfig(value)
    if not value then return nil end

    if type(value) == "table" then
        -- Table format: validate and normalize
        return {
            properties = value.properties or "all",
            duration = value.duration or 0.3,
            easing = value.easing or "easeOut",
        }
    end

    if type(value) == "string" then
        -- Check for comma-separated multi-property format
        if value:find(",") then
            local properties = {}
            local perProperty = {}
            local firstDuration, firstEasing

            for segment in value:gmatch("[^,]+") do
                segment = segment:match("^%s*(.-)%s*$")  -- trim
                local prop, duration, easing = parseSegment(segment)
                if prop then
                    if prop == "all" then
                        -- "all" in comma-separated: use as default for all properties
                        firstDuration = firstDuration or duration
                        firstEasing = firstEasing or easing
                        return {
                            properties = "all",
                            duration = duration,
                            easing = easing,
                        }
                    end
                    properties[#properties + 1] = prop
                    perProperty[prop] = { duration = duration, easing = easing }
                    firstDuration = firstDuration or duration
                    firstEasing = firstEasing or easing
                end
            end

            if #properties == 0 then return nil end

            return {
                properties = properties,
                duration = firstDuration,
                easing = firstEasing,
                perProperty = perProperty,
            }
        end

        -- Single property shorthand: "all 0.3s easeOut" or "opacity 0.2s easeInOut"
        local prop, duration, easing = parseSegment(value)
        if not prop then return nil end

        local properties
        if prop == "all" then
            properties = "all"
        else
            properties = { prop }
        end

        return {
            properties = properties,
            duration = duration,
            easing = easing,
        }
    end

    return nil
end

--- Check if a property is included in a transition config.
---@param config table Normalized transition config
---@param propName string Property name to check
---@param extraProps table|nil Per-widget extra transitionable props (e.g. { value = "number" })
---@return boolean
function Transition.ConfigIncludesProperty(config, propName, extraProps)
    if not config then return false end
    if not transitionableProps[propName] and not (extraProps and extraProps[propName]) then return false end

    local props = config.properties
    if props == "all" then return true end
    if type(props) == "table" then
        for i = 1, #props do
            if props[i] == propName then return true end
        end
    end
    return false
end

--- Get duration and easing for a specific property from a transition config.
--- For comma-separated configs, each property may have its own duration/easing.
---@param config table Normalized transition config
---@param propName string Property name
---@return number duration
---@return string easing
function Transition.GetPropertyConfig(config, propName)
    if config.perProperty then
        local pc = config.perProperty[propName]
        if pc then
            return pc.duration, pc.easing
        end
    end
    return config.duration, config.easing
end

-- ============================================================================
-- Keyframe Animation
-- ============================================================================
-- Multi-keyframe animations with loop, direction, and onComplete support.
--
-- KeyframeAnimation structure:
--   keyframes: sorted array of { t = 0..1, props = { opacity = 0, ... } }
--   duration: total duration in seconds
--   easingFn: easing function applied to global progress
--   elapsed: current time
--   loop: boolean or number (iteration count)
--   direction: "normal" | "reverse" | "alternate"
--   iterations: completed iteration count
--   onComplete: callback when animation finishes
--   active: boolean

--- Normalize and sort keyframe definitions
---@param keyframes table { [0] = { opacity = 0 }, [0.5] = { ... }, [1] = { ... } }
---@return table Sorted array of { t, props }
local function normalizeKeyframes(keyframes)
    local sorted = {}
    for t, props in pairs(keyframes) do
        sorted[#sorted + 1] = { t = t, props = props }
    end
    table.sort(sorted, function(a, b) return a.t < b.t end)
    return sorted
end

--- Create a new keyframe animation
---@param config table { keyframes, duration, easing, loop, direction, onComplete }
---@return table KeyframeAnimation
function Transition.CreateKeyframeAnimation(config)
    local keyframes = normalizeKeyframes(config.keyframes)
    local easingFn = Transition.ResolveEasing(config.easing or "linear")

    return {
        keyframes = keyframes,
        duration = config.duration or 1.0,
        easingFn = easingFn,
        elapsed = 0,
        loop = config.loop or false,
        direction = config.direction or "normal",
        iterations = 0,
        onComplete = config.onComplete,
        fillMode = config.fillMode or "none",
        active = true,
    }
end

--- Interpolate keyframe properties at a given progress t (0..1)
---@param keyframes table Sorted keyframe array
---@param t number Progress 0..1
---@return table Interpolated property values
function Transition.InterpolateKeyframes(keyframes, t)
    local n = #keyframes
    if n == 0 then return {} end
    if n == 1 then return keyframes[1].props end

    -- Clamp t
    if t <= keyframes[1].t then return keyframes[1].props end
    if t >= keyframes[n].t then return keyframes[n].props end

    -- Find the two keyframes to interpolate between
    local kfA, kfB
    for i = 1, n - 1 do
        if t >= keyframes[i].t and t <= keyframes[i + 1].t then
            kfA = keyframes[i]
            kfB = keyframes[i + 1]
            break
        end
    end

    if not kfA or not kfB then return keyframes[n].props end

    -- Local progress between the two keyframes
    local range = kfB.t - kfA.t
    local localT = range > 0 and (t - kfA.t) / range or 1

    -- Interpolate each property
    local result = {}
    -- Collect all property names from both keyframes
    local allProps = {}
    for k in pairs(kfA.props) do allProps[k] = true end
    for k in pairs(kfB.props) do allProps[k] = true end

    for propName in pairs(allProps) do
        local fromVal = kfA.props[propName]
        local toVal = kfB.props[propName]
        if fromVal ~= nil and toVal ~= nil then
            local propType = transitionableProps[propName]
            if propType == "color" then
                result[propName] = Transition.LerpColor(fromVal, toVal, localT)
            elseif propType == "number" then
                result[propName] = Transition.Lerp(fromVal, toVal, localT)
            else
                -- Non-transitionable: snap to B at t >= 0.5
                result[propName] = localT >= 0.5 and toVal or fromVal
            end
        else
            result[propName] = toVal or fromVal
        end
    end

    return result
end

--- Update a keyframe animation
---@param anim table KeyframeAnimation
---@param dt number Delta time
---@return table|nil Interpolated props if active, nil if finished
function Transition.UpdateKeyframeAnimation(anim, dt)
    if not anim.active then return nil end

    anim.elapsed = anim.elapsed + dt
    local duration = anim.duration

    if anim.elapsed >= duration then
        anim.iterations = anim.iterations + 1

        if anim.loop == true or (type(anim.loop) == "number" and anim.iterations < anim.loop) then
            -- Loop: reset elapsed
            anim.elapsed = anim.elapsed - duration
        else
            -- Animation complete
            anim.active = false
            -- Return final frame
            local finalT = (anim.direction == "reverse") and 0 or 1
            local result = Transition.InterpolateKeyframes(anim.keyframes, finalT)
            if anim.onComplete then
                anim.onComplete()
            end
            return result
        end
    end

    -- Calculate progress
    local t = anim.elapsed / duration

    -- Apply direction
    local dir = anim.direction
    if dir == "reverse" then
        t = 1 - t
    elseif dir == "alternate" then
        if anim.iterations % 2 == 1 then
            t = 1 - t
        end
    end

    -- Apply easing to global progress
    t = anim.easingFn(t)

    return Transition.InterpolateKeyframes(anim.keyframes, t)
end

return Transition
