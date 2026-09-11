-- ============================================================================
-- UI Manager
-- UrhoX UI Library - Yoga + NanoVG
-- ============================================================================

local Theme = require("urhox-libs/UI/Core/Theme")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")
local Input = require("urhox-libs/UI/Core/Input")
local InputAdapter = require("urhox-libs/UI/Core/InputAdapter")
local Gesture = require("urhox-libs/UI/Core/Gesture")
local GestureEvent = require("urhox-libs/UI/Core/GestureEvent")
local Widget = require("urhox-libs/UI/Core/Widget")

local UI = {}

-- Global text fitting switch. UI.Init() enables it when a translated target
-- language is active; it remains disabled for source-language launches.
UI.defaultAutoFitText = false

-- ============================================================================
-- Scale Presets (AI-friendly)
-- ============================================================================

---@class UI.Scale
---@field DEFAULT fun(): number Alias for DPR_DENSITY_ADAPTIVE (recommended)
---@field DPR fun(): number Pure DPR mode, 1 base pixel = 1 CSS pixel
---@field DPR_DENSITY_ADAPTIVE fun(): number DPR + small screen density adaptation
---@field DESIGN_RESOLUTION fun(w: number, h: number): fun(): number Design resolution mode
---@field DESIGN_SHORT_SIDE fun(shortSide: number): fun(): number Short-side design resolution
---@overload fun(value: number): number Scale a value by current scale factor

--- Scale presets and scale utility function.
--- As table: UI.Scale.DEFAULT, UI.Scale.DPR, etc.
--- As function: UI.Scale(value) returns value * current_scale
---@type UI.Scale
UI.Scale = {
    --- Pure DPR mode: 1 base pixel = 1 CSS pixel
    --- Best for: PC-only apps, or when density adaptation is handled elsewhere
    DPR = function()
        return graphics:GetDPR()
    end,

    --- DPR + Density-adaptive mode (recommended for cross-platform)
    --- AI designs for PC, engine automatically adapts for small screens
    --- Small screens get larger logical resolution → UI elements take less screen percentage
    DPR_DENSITY_ADAPTIVE = function()
        local dpr = graphics:GetDPR()
        local shortSide = math.min(graphics.width, graphics.height) / dpr

        local PC_REF = 720  -- PC desktop reference short side (CSS pixels)
        local densityFactor = math.sqrt(shortSide / PC_REF)
        densityFactor = math.max(0.625, math.min(densityFactor, 1.0))  -- clamp [0.625, 1.0]
        local scale = dpr * densityFactor
        return scale
    end,

    --- Design resolution mode (for pixel-art or games with fixed design spec)
    --- Returns a function that calculates scale based on design size
    DESIGN_RESOLUTION = function(designWidth, designHeight)
        return function()
            return math.min(graphics.width / designWidth, graphics.height / designHeight)
        end
    end,

    --- Short-side design resolution
    DESIGN_SHORT_SIDE = function(shortSide)
        return function()
            return math.min(graphics.width, graphics.height) / shortSide
        end
    end,
}

--- Default scale mode (alias for DPR_DENSITY_ADAPTIVE)
UI.Scale.DEFAULT = UI.Scale.DPR_DENSITY_ADAPTIVE

-- ============================================================================
-- Internal State
-- ============================================================================

local nvg_ = nil              -- NanoVG context
local root_ = nil             -- Root widget
local screenWidth_ = 0
local screenHeight_ = 0

-- Interaction state (per pointer)
local hoveredWidgets_ = {}    -- { pointerId = widget }
local pressedWidgets_ = {}    -- { pointerId = widget }
local focusedWidget_ = nil    -- Currently focused widget

-- Layout dirty flag
local layoutDirty_ = true

-- Font version counter: incremented when a font resource finishes DWP reload.
-- Widgets that cache text measurements compare against this to know when to re-measure.
local fontVersion_ = 0

-- Overlay render queue (for dropdowns, tooltips, etc.)
local overlayQueue_ = {}

-- Overlay stack (for hit testing priority, supports nested overlays)
local overlayStack_ = {}

-- Global components (Toast, etc.) that need Update/Render but aren't in widget tree
local globalComponents_ = {}

-- Auto events state
---@type Node|nil
local eventNode_ = nil           -- Node for event subscription
---@type LuaScriptObject|nil
local eventScriptObject_ = nil   -- ScriptObject for event subscription (avoids global function override)
local autoEventsEnabled_ = false
local autoEventsInputEnabled_ = false   -- Input events (mouse, touch, keyboard)
local autoEventsUpdateEnabled_ = false  -- Update event
local autoEventsRenderEnabled_ = false  -- Render event
local fontSubCount_ = 0                 -- Active font DWP reload subscriptions (guards eventNode cleanup)
local ensureEventNode                   -- Forward declaration (defined after UI.Init)

-- UI enabled state (when disabled, all events and rendering are skipped)
local enabled_ = true

-- UI scaling for resolution adaptation
local scale_ = 1.0               -- Computed scale value (final result)
local scaleFunc_ = nil           -- Scale function (no params), nil = use fixed scale_
local designSize_ = nil          -- Design size config (used to build scaleFunc_ if scale option not set)

-- Make UI.Scale callable: UI.Scale(value) returns value * scale_
setmetatable(UI.Scale, {
    __call = function(_, value)
        return value * scale_
    end
})

-- Transition system: set of widgets with active transitions (for efficient per-frame updates)
-- Only widgets in this set get BaseUpdate() called — zero overhead for non-transitioning widgets
local activeTransitionWidgets_ = {}  -- { [widget] = true }
local activeTransitionCount_ = 0     -- Fast count to skip loop when 0

-- NanoVG save/restore depth tracking (defensive against stack overflow)
local saveDepth_ = 0
-- NanoVG has 32 total state slots, including its base state. Cap framework-
-- managed pushes at 28 so widget-local clipping/effects retain three slots.
-- Known consumers: renderWidgetTree() for transform/opacity/blend mode, and
-- UI.MeasureTextFit() for temporary text-measurement state.
local MAX_SAVE_DEPTH = 28

local function trySaveNVGState(nvg)
    if saveDepth_ >= MAX_SAVE_DEPTH then
        return false
    end
    nvgSave(nvg)
    saveDepth_ = saveDepth_ + 1
    return true
end

local function restoreNVGState(nvg)
    nvgRestore(nvg)
    saveDepth_ = saveDepth_ - 1
end

-- Fixed-position widgets: collected during render, rendered on top of normal tree
local fixedWidgets_ = {}       -- Widgets with position="fixed" collected this frame
local renderingFixed_ = false  -- True during fixed widget render pass

-- Inspector hooks (set by UIInspector module)
local inspectorRenderHook_ = nil   -- function(nvg)|nil
local inspectorInputHook_ = nil    -- function(x, y)|nil  returns true to consume
local inspectorMoveHook_ = nil     -- function(x, y)|nil  returns true to consume
local inspectorPointerUpHook_ = nil -- function(x, y)|nil  returns true to consume

-- Inspector independent widget tree (isolated from main root_)
local inspectorRoot_ = nil

-- JSON instances tracking (for GC lifecycle management)
local jsonInstances_ = {}

-- Cursor style mapping: CSS cursor name → Urho3D CursorShape constant
-- DISABLED: SDL_SetCursor does not visually change the OS cursor in current engine build.
-- The mapping and SetShape calls reach SDL but have no visible effect.
-- TODO: Investigate SDL cursor issue (possibly SDL version or platform-specific bug).
-- To re-enable: set cursorEnabled_ = true
local cursorEnabled_ = false
local cursorShapeMap_ = nil
local currentCursorStyle_ = "default"
local function initCursorMap()
    if not cursorEnabled_ then return end
    if cursorShapeMap_ then return end
    -- Check if Urho3D cursor constants are available in global scope
    if CS_NORMAL ~= nil then
        cursorShapeMap_ = {
            ["default"]     = CS_NORMAL,
            ["pointer"]     = CS_ACCEPTDROP,  -- SDL_SYSTEM_CURSOR_HAND
            ["text"]        = CS_IBEAM,
            ["move"]        = CS_RESIZE_ALL,
            ["not-allowed"] = CS_REJECTDROP,
            ["crosshair"]   = CS_CROSS,
            ["ew-resize"]   = CS_RESIZEHORIZONTAL,
            ["ns-resize"]   = CS_RESIZEVERTICAL,
            ["grab"]        = CS_ACCEPTDROP,  -- SDL_SYSTEM_CURSOR_HAND
            ["wait"]        = CS_BUSY,
        }
    end

    -- Auto-create Cursor object if not already set, so cursor styles work out of the box
    if cursorShapeMap_ and ui and not ui.cursor then
        local cursor = Cursor:new()
        cursor:SetUseSystemShapes(true)
        ui.cursor = cursor
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

--- Initialize the UI system
---@param options table { fonts, theme, fontSizeMethod, autoEvents, scale, designSize, replaceFonts }
--- fonts: { { name, path } } - Font definitions
--- theme: table or string - Theme configuration
--- fontSizeMethod: "pixel" (default) or "char"
---   "pixel": nvgFontSize uses pixels, Theme.FontSize converts pt to px
---   "char": nvgFontSize uses points directly, Theme.FontSize passes pt as-is
--- autoEvents: boolean or table - automatically subscribe to engine events and forward to UI
---   true (default): enable all events (input, update, render)
---   false: disable all automatic event forwarding
---   { input = bool, update = bool, render = bool }: fine-grained control
---     input: mouse, touch, keyboard events (default: true)
---     update: Update event for UI.Update() (default: true)
---     render: NanoVGRender event for UI.Render() (default: true)
--- scale: number or function (optional) - Resolution scale
---   AI should default to: graphics:GetDPR() (DPR logical pixels, 1 base pixel = 1 CSS pixel)
---   number: fixed scale value
---   function: dynamic calculation for design resolution or complex scaling
---   Not set: physical pixels (scale = 1)
--- designSize: number (optional, legacy) - Only use when user explicitly specifies design resolution
---   Equivalent to: scale = function() return math.min(graphics.width, graphics.height) / designSize end
---   When set (number > 0): design resolution mode, for pixel-art/2D games with design spec
---   When set (number <= 0): DPR-aware logical pixels
--- replaceFonts: boolean (optional) - explicitly delete an existing font name before creating it
function UI.Init(options)
    if nvg_ then
        log:Write(LOG_WARNING, "UI.Init() called twice without UI.Shutdown(), ignored")
        return
    end

    options = options or {}

    UI.defaultAutoFitText = i18n and i18n.IsActive() or false

    -- Create NanoVG context
    nvg_ = nvgCreate(1)  -- 1 = antialias

    -- Set NanoVG render order
    nvgSetRenderOrder(nvg_, 999990)

    -- Set ImageCache context (once, nvg_ is stable for entire lifetime)
    ImageCache.SetContext(nvg_)

    -- Set Widget layout dirty callback (auto-trigger layout on AddChild/RemoveChild)
    Widget.SetLayoutDirtyCallback(function()
        layoutDirty_ = true
    end)

    -- Set Widget transition callbacks (track active transitions for efficient updates)
    Widget.SetTransitionCallbacks(
        function(widget)  -- onStart
            if not activeTransitionWidgets_[widget] then
                activeTransitionWidgets_[widget] = true
                activeTransitionCount_ = activeTransitionCount_ + 1
            end
        end,
        function(widget)  -- onEnd
            if activeTransitionWidgets_[widget] then
                activeTransitionWidgets_[widget] = nil
                activeTransitionCount_ = activeTransitionCount_ - 1
            end
        end
    )

    -- Initialize cursor shape mapping (if engine cursor is available)
    initCursorMap()

    -- Calculate UI scale
    screenWidth_ = graphics.width
    screenHeight_ = graphics.height
    designSize_ = options.designSize

    -- Build scaleFunc_ (priority: scale > designSize > default)
    if options.scale ~= nil then
        if type(options.scale) == "function" then
            scaleFunc_ = options.scale
        else
            -- Fixed scale value
            scale_ = options.scale
            scaleFunc_ = nil
        end
    elseif designSize_ and designSize_ > 0 then
        -- Design resolution mode
        scaleFunc_ = function()
            return math.min(screenWidth_, screenHeight_) / designSize_
        end
    elseif designSize_ and designSize_ <= 0 then
        -- DPR mode (legacy, fixed value)
        scale_ = graphics:GetDPR()
        scaleFunc_ = nil
    else
        -- Default: physical pixels
        scale_ = 1
        scaleFunc_ = nil
    end

    -- Compute scale_ if scaleFunc_ exists
    if scaleFunc_ then
        scale_ = scaleFunc_()
    end
    Theme.SetScale(scale_)

    -- Ensure YGUndefined global (NaN) is available for unconstrained Yoga layout
    -- Normally set by UIGuard.lua; this is a safety net
    if YGUndefined == nil then
        YGUndefined = YGGetUndefined and YGGetUndefined() or (0.0 / 0.0)
    end

    -- Set Yoga point scale factor for pixel-perfect layout rounding
    -- This allows Yoga to work in base pixels while ensuring proper pixel alignment
    local config = YGConfigGetDefault()
    YGConfigSetPointScaleFactor(config, scale_)

    -- Set font size method (must be set before loading fonts for consistent behavior)
    -- Default: "pixel" (NVG_SIZE_PIXEL = 0), alternative: "char" (NVG_SIZE_CHAR = 1)
    local sizeMethod = options.fontSizeMethod or "pixel"
    if sizeMethod == "char" then
        nvgFontSizeMethod(nvg_, NVG_SIZE_CHAR)
        Theme.SetFontSizeMethod("char")
    else
        nvgFontSizeMethod(nvg_, NVG_SIZE_PIXEL)
        Theme.SetFontSizeMethod("pixel")
    end

    -- Resolve theme early (before fonts) so theme.fonts can serve as default
    local resolvedTheme = nil
    if options.theme then
        if type(options.theme) == "table" then
            resolvedTheme = options.theme
        elseif type(options.theme) == "string" then
            resolvedTheme = Theme.GetRegisteredTheme(options.theme)
        end
    end

    -- Fonts: user-provided > theme.fonts > built-in default
    local fonts = options.fonts or (resolvedTheme and resolvedTheme.fonts) or nil

    -- Create a font by name, honoring the replaceFonts option. NanoVG keeps
    -- duplicate-name font IDs independent by default (game code relies on that);
    -- the theme plugin opts into replacement so switching themes rebinds a name to
    -- its new file instead of stacking a shadowed second font under the same name.
    local function createFont(name, path)
        if options.replaceFonts then
            local oldFontId = nvgFindFont(nvg_, name)
            if oldFontId >= 0 and type(nvgDeleteFont) == "function" then
                nvgDeleteFont(nvg_, oldFontId)
            end
        end
        return nvgCreateFont(nvg_, name, path)
    end

    -- Load fonts
    -- Supports two formats:
    -- New format (recommended):
    --   { family = "sans", weights = { normal = "path/regular.ttf", bold = "path/bold.ttf" } }
    -- Legacy format (for backward compatibility):
    --   { name = "sans", path = "path/font.ttf" }
    --
    -- Design note (issue #2092): nvgFindFont() returns the FIRST font registered under
    -- a name, so registering the same name twice makes the earlier one win forever.
    -- The old code created fonts while iterating, which let the auto-generated "-bold"
    -- fallback of a legacy entry occupy a name the user meant to register explicitly
    -- (e.g. { name = "sans" } auto-made "sans-bold"=Regular, silently beating a later
    -- { name = "sans-bold" }=Bold). Instead we RESOLVE every entry into a name→path
    -- table first, then create each font exactly once. Single order-independent rule:
    --   * explicit registration (a name the user actually wrote) always wins over an
    --     engine-generated fallback, regardless of entry order;
    --   * two explicit registrations of the same name with different paths is a real
    --     collision → warn (no more silent failure), later one wins;
    --   * a fallback never overrides an explicit registration.
    -- The "-bold" string only appears when WE build our own fallback name — we never
    -- parse the user's font name for a suffix, so no new naming convention is imposed.
    local fontPaths = {}
    local resolved = {}   -- name -> { path = string, explicit = bool }
    local order = {}      -- registration order, for deterministic single-pass creation
    local function registerFont(name, path, explicit)
        local existing = resolved[name]
        if not existing then
            resolved[name] = { path = path, explicit = explicit }
            order[#order + 1] = name
        elseif explicit and not existing.explicit then
            -- Explicit user intent replaces an engine-generated fallback.
            existing.path = path
            existing.explicit = true
        elseif explicit and existing.explicit and existing.path ~= path then
            -- Genuine collision between two explicit registrations: warn (the historic
            -- bug was this failing silently), keep the later one.
            log:Write(LOG_WARNING, string.format(
                "UI.Init: font \"%s\" registered twice with different paths "
                .. "(\"%s\" then \"%s\"); using the later one.",
                name, existing.path, path))
            existing.path = path
        end
        -- fallback-over-anything or identical path: keep existing (no-op)
    end

    if fonts then
        local hasSansFont = false
        local firstNormalPath = nil
        local firstBoldPath = nil
        for _, font in ipairs(fonts) do
            if font.family and font.weights then
                -- New format: family with multiple weights (all explicit)
                local normalPath = nil
                local hasBold = false
                for weight, path in pairs(font.weights) do
                    local fontName
                    if weight == "normal" or weight == "regular" or weight == "400" then
                        fontName = font.family
                        normalPath = path
                    else
                        fontName = font.family .. "-" .. weight
                        if weight == "bold" then hasBold = true end
                    end
                    registerFont(fontName, path, true)
                    fontPaths[path] = true
                end
                -- Auto-fill "-bold" as a FALLBACK when no explicit bold weight was given.
                -- Theme.FontFace maps bold/500-900/medium/semibold/black all to "-bold".
                if normalPath and not hasBold then
                    local boldPath = font.weights["700"] or normalPath
                    registerFont(font.family .. "-bold", boldPath, false)
                end
                if font.family == "sans" then hasSansFont = true end
                if not firstNormalPath and normalPath then
                    firstNormalPath = normalPath
                    firstBoldPath = font.weights["bold"] or font.weights["700"] or normalPath
                end
            elseif font.name and font.path then
                -- Legacy format: the given name is explicit; "-bold" is auto-generated
                -- as a FALLBACK only. If the user also registers "<name>-bold" explicitly
                -- (the intuitive way to add a bold face), that explicit entry wins and the
                -- Regular-as-bold fallback is dropped — fixing the silent bug in #2092.
                registerFont(font.name, font.path, true)
                registerFont(font.name .. "-bold", font.path, false)
                fontPaths[font.path] = true
                if font.name == "sans" then hasSansFont = true end
                if not firstNormalPath then
                    firstNormalPath = font.path
                    firstBoldPath = font.path
                end
            end
        end
        -- 兜底：Theme/MeasureText 等多处 fallback 默认使用 "sans"，
        -- 如果用户注册的字体都不叫 "sans"，把第一个字体额外注册为 "sans" 别名，
        -- 避免自定义字体名导致全部文字静默消失。（别名是兜底，永不覆盖显式注册）
        if not hasSansFont and firstNormalPath then
            registerFont("sans", firstNormalPath, false)
            registerFont("sans-bold", firstBoldPath, false)
        end
        -- Create each resolved font exactly once. Because every name is now unique,
        -- nvgFindFont's first-match semantics resolve to the intended weight.
        for _, name in ipairs(order) do
            createFont(name, resolved[name].path)
        end
    else
        -- Load default fonts (regular and bold)
        -- TODO: Replace bold with actual bold font when available
        createFont("sans", "Fonts/MiSans-Regular.ttf")
        createFont("sans-bold", "Fonts/MiSans-Regular.ttf")  -- Placeholder: use Regular until Bold is available
        fontPaths["Fonts/MiSans-Regular.ttf"] = true
    end

    -- Subscribe to font DWP reload events (one-shot per font).
    -- Only subscribe for fonts not yet on disk (DWP pending download).
    -- Already-loaded fonts have correct metrics from Init — no subscription needed.
    for path in pairs(fontPaths) do
        if not cache:Exists(path) then
            local fontRes = cache:GetResource("Font", path)
            if fontRes then
                ensureEventNode()
                fontSubCount_ = fontSubCount_ + 1
                eventScriptObject_:SubscribeToEvent(fontRes, "ReloadFinished", function()
                    fontVersion_ = fontVersion_ + 1
                    fontSubCount_ = fontSubCount_ - 1
                    eventScriptObject_:UnsubscribeFromEvent(fontRes, "ReloadFinished")
                    -- Ideally: cleanupEventNodeIfEmpty()
                end)
            end
        end
    end

    -- Set theme (already resolved above for font fallback)
    if resolvedTheme then
        Theme.SetTheme(resolvedTheme)
    end

    -- nvgCreate starts with devicePixelRatio = 1.  Intrinsic Label/Button
    -- widths are commonly measured immediately after UI.Init, before the first
    -- UI.Render calls nvgBeginFrame with the configured UI scale.  Prime the
    -- context now so startup measurements use the same rasterized font metrics
    -- as rendering at non-1 scales (for example a resized remote desktop).
    if scale_ and scale_ > 0 and screenWidth_ > 0 and screenHeight_ > 0 then
        nvgBeginFrame(nvg_, screenWidth_ / scale_, screenHeight_ / scale_, scale_)
        nvgEndFrame(nvg_)
    end

    -- Initialize input adapter
    InputAdapter.Init(function(event)
        UI.HandlePointerEvent(event)
    end)

    -- Initialize gesture recognition
    Gesture.Init(function(event)
        UI.HandleGestureEvent(event)
    end)

    -- Enable auto events by default (simple mode)
    -- Set autoEvents = false to handle event forwarding manually
    -- Set autoEvents = { input = bool, update = bool, render = bool } for fine-grained control
    local autoEvents = options.autoEvents
    if autoEvents == nil then
        -- Default: enable all
        autoEvents = { input = true, update = true, render = true }
    elseif autoEvents == true then
        -- Legacy: true means enable all
        autoEvents = { input = true, update = true, render = true }
    elseif autoEvents == false then
        -- Legacy: false means disable all
        autoEvents = { input = false, update = false, render = false }
    end
    -- Now autoEvents is a table with { input, update, render }

    -- Enable requested auto events
    if autoEvents.input ~= false then
        UI.EnableAutoEventsInput()
    end
    if autoEvents.update ~= false then
        UI.EnableAutoEventsUpdate()
    end
    if autoEvents.render ~= false then
        UI.EnableAutoEventsRender()
    end

    local defaultUseInspector = GetTapMakerEnvString and GetTapMakerEnvString() == "preview"
    if options.useInspector or defaultUseInspector then
        if UI.Inspector and UI.Inspector.Init then
            UI.Inspector.Init(UI, { hotkey = KEY_F9 })
        elseif log then
            log:Write(LOG_ERROR, "UI Inspector requested but failed to load")
        end
    end

    return UI
end

--- Shutdown the UI system
function UI.Shutdown()
    UI.Inspector.Shutdown()

    -- Disable auto events first
    UI.DisableAutoEventsInput()
    UI.DisableAutoEventsUpdate()
    UI.DisableAutoEventsRender()

    -- Clear Widget layout callback
    Widget.SetLayoutDirtyCallback(nil)

    -- Destroy root widget
    if root_ then
        root_:Destroy()
        root_ = nil
    end

    -- Clear ImageCache before destroying NanoVG context
    ImageCache.Clear()
    ImageCache.SetContext(nil)

    -- Destroy NanoVG context
    if nvg_ then
        nvgDelete(nvg_)
        nvg_ = nil
    end

    -- Clear inspector hooks
    inspectorRenderHook_ = nil
    inspectorInputHook_ = nil
    inspectorMoveHook_ = nil
    inspectorPointerUpHook_ = nil

    -- Clear state
    hoveredWidgets_ = {}
    pressedWidgets_ = {}
    focusedWidget_ = nil
    overlayStack_ = {}
    fixedWidgets_ = {}
    overlayQueue_ = {}
    globalComponents_ = {}
    activeTransitionWidgets_ = {}
    activeTransitionCount_ = 0
    saveDepth_ = 0
    layoutDirty_ = true

    -- Reset input and gestures
    InputAdapter.Reset()
    Gesture.Reset()
end

-- ============================================================================
-- Auto Events (Fine-grained Control)
-- ============================================================================

-- Internal: ensure event node exists (forward-declared above for use in UI.Init)
ensureEventNode = function()
    if not eventNode_ then
        eventNode_ = Node()
        eventScriptObject_ = eventNode_:CreateScriptObject("LuaScriptObject")
    end
end

-- Internal: cleanup event node if no events are enabled
local function cleanupEventNodeIfEmpty()
    if not autoEventsInputEnabled_ and not autoEventsUpdateEnabled_ and not autoEventsRenderEnabled_
        and fontSubCount_ <= 0 then
        if eventNode_ then
            eventNode_:Remove()
            eventNode_ = nil
            eventScriptObject_ = nil
        end
        autoEventsEnabled_ = false
    end
end

--- Enable automatic input event forwarding (mouse, touch, keyboard)
function UI.EnableAutoEventsInput()
    if autoEventsInputEnabled_ then return end
    if not nvg_ then
        error("UI.EnableAutoEventsInput: UI.Init() must be called first")
    end

    ensureEventNode()

    -- Mouse events
    eventScriptObject_:SubscribeToEvent("MouseMove", function(self, eventType, eventData)
        local x = eventData["X"]:GetInt()
        local y = eventData["Y"]:GetInt()
        UI.HandleMouseMove(x, y)
    end)

    eventScriptObject_:SubscribeToEvent("MouseButtonDown", function(self, eventType, eventData)
        local x = eventData["X"]:GetInt()
        local y = eventData["Y"]:GetInt()
        local button = eventData["Button"]:GetInt()
        UI.HandleMouseDown(x, y, button)
    end)

    eventScriptObject_:SubscribeToEvent("MouseButtonUp", function(self, eventType, eventData)
        local x = eventData["X"]:GetInt()
        local y = eventData["Y"]:GetInt()
        local button = eventData["Button"]:GetInt()
        UI.HandleMouseUp(x, y, button)
    end)

    eventScriptObject_:SubscribeToEvent("MouseWheel", function(self, eventType, eventData)
        local wheel = eventData["Wheel"]:GetInt()
        UI.HandleWheel(0, wheel)
    end)

    -- Touch events
    eventScriptObject_:SubscribeToEvent("TouchBegin", function(self, eventType, eventData)
        local x = eventData["X"]:GetInt()
        local y = eventData["Y"]:GetInt()
        local touchId = eventData["TouchID"]:GetInt()
        local pressure = eventData["Pressure"] and eventData["Pressure"]:GetFloat() or 1.0
        UI.HandleTouchBegin(touchId, x, y, pressure)
    end)

    eventScriptObject_:SubscribeToEvent("TouchEnd", function(self, eventType, eventData)
        local x = eventData["X"]:GetInt()
        local y = eventData["Y"]:GetInt()
        local touchId = eventData["TouchID"]:GetInt()
        UI.HandleTouchEnd(touchId, x, y)
    end)

    eventScriptObject_:SubscribeToEvent("TouchMove", function(self, eventType, eventData)
        local x = eventData["X"]:GetInt()
        local y = eventData["Y"]:GetInt()
        local touchId = eventData["TouchID"]:GetInt()
        local pressure = eventData["Pressure"] and eventData["Pressure"]:GetFloat() or 1.0
        UI.HandleTouchMove(touchId, x, y, pressure)
    end)

    -- Keyboard events
    eventScriptObject_:SubscribeToEvent("KeyDown", function(self, eventType, eventData)
        local key = eventData["Key"]:GetInt()
        UI.HandleKeyDown(key)
    end)

    eventScriptObject_:SubscribeToEvent("KeyUp", function(self, eventType, eventData)
        local key = eventData["Key"]:GetInt()
        UI.HandleKeyUp(key)
    end)

    eventScriptObject_:SubscribeToEvent("TextInput", function(self, eventType, eventData)
        local text = eventData["Text"]:GetString()
        UI.HandleTextInput(text)
    end)

    -- Window focus event
    eventScriptObject_:SubscribeToEvent("InputFocus", function(self, eventType, eventData)
        local focus = eventData["Focus"]:GetBool()
        if not focus then
            UI.ClearFocus()
        end
    end)

    autoEventsInputEnabled_ = true
    autoEventsEnabled_ = true
end

--- Disable automatic input event forwarding
function UI.DisableAutoEventsInput()
    if not autoEventsInputEnabled_ then return end

    if eventScriptObject_ then
        eventScriptObject_:UnsubscribeFromEvent("MouseMove")
        eventScriptObject_:UnsubscribeFromEvent("MouseButtonDown")
        eventScriptObject_:UnsubscribeFromEvent("MouseButtonUp")
        eventScriptObject_:UnsubscribeFromEvent("MouseWheel")
        eventScriptObject_:UnsubscribeFromEvent("TouchBegin")
        eventScriptObject_:UnsubscribeFromEvent("TouchEnd")
        eventScriptObject_:UnsubscribeFromEvent("TouchMove")
        eventScriptObject_:UnsubscribeFromEvent("KeyDown")
        eventScriptObject_:UnsubscribeFromEvent("KeyUp")
        eventScriptObject_:UnsubscribeFromEvent("TextInput")
        eventScriptObject_:UnsubscribeFromEvent("InputFocus")
    end

    autoEventsInputEnabled_ = false
    cleanupEventNodeIfEmpty()
end

--- Enable automatic Update event forwarding
function UI.EnableAutoEventsUpdate()
    if autoEventsUpdateEnabled_ then return end
    if not nvg_ then
        error("UI.EnableAutoEventsUpdate: UI.Init() must be called first")
    end

    ensureEventNode()

    -- Update event
    eventScriptObject_:SubscribeToEvent("Update", function(self, eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()
        UI.Update(dt)
    end)

    autoEventsUpdateEnabled_ = true
    autoEventsEnabled_ = true
end

--- Disable automatic Update event forwarding
function UI.DisableAutoEventsUpdate()
    if not autoEventsUpdateEnabled_ then return end

    if eventScriptObject_ then
        eventScriptObject_:UnsubscribeFromEvent("Update")
    end

    autoEventsUpdateEnabled_ = false
    cleanupEventNodeIfEmpty()
end

--- Enable automatic Render event forwarding
function UI.EnableAutoEventsRender()
    if autoEventsRenderEnabled_ then return end
    if not nvg_ then
        error("UI.EnableAutoEventsRender: UI.Init() must be called first")
    end

    ensureEventNode()

    -- Render event - subscribe to NVG context's NanoVGRender event
    eventScriptObject_:SubscribeToEvent(nvg_, "NanoVGRender", function(self, eventType, eventData)
        UI.Render()
    end)

    autoEventsRenderEnabled_ = true
    autoEventsEnabled_ = true
end

--- Disable automatic Render event forwarding
function UI.DisableAutoEventsRender()
    if not autoEventsRenderEnabled_ then return end

    if eventScriptObject_ and nvg_ then
        eventScriptObject_:UnsubscribeFromEvent(nvg_, "NanoVGRender")
    end

    autoEventsRenderEnabled_ = false
    cleanupEventNodeIfEmpty()
end

--- Enable all automatic event forwarding (legacy API, kept for compatibility)
function UI.EnableAutoEvents()
    UI.EnableAutoEventsInput()
    UI.EnableAutoEventsUpdate()
    UI.EnableAutoEventsRender()
end

--- Disable all automatic event forwarding (legacy API, kept for compatibility)
function UI.DisableAutoEvents()
    UI.DisableAutoEventsInput()
    UI.DisableAutoEventsUpdate()
    UI.DisableAutoEventsRender()
end

--- Check if any auto events are enabled
---@return boolean
function UI.IsAutoEventsEnabled()
    return autoEventsEnabled_
end

--- Check if auto input events are enabled
---@return boolean
function UI.IsAutoEventsInputEnabled()
    return autoEventsInputEnabled_
end

--- Check if auto update events are enabled
---@return boolean
function UI.IsAutoEventsUpdateEnabled()
    return autoEventsUpdateEnabled_
end

--- Check if auto render events are enabled
---@return boolean
function UI.IsAutoEventsRenderEnabled()
    return autoEventsRenderEnabled_
end

-- ============================================================================
-- UI Enabled State
-- When disabled, all input events, update, and rendering are skipped.
-- The UI remains in memory but becomes completely inactive.
-- ============================================================================

--- Enable or disable the entire UI system
--- When disabled:
---   - All pointer/gesture events are ignored
---   - Update() does nothing
---   - Render() does nothing (UI becomes invisible)
--- The UI tree remains intact and can be re-enabled at any time.
---@param enabled boolean
function UI.SetEnabled(enabled)
    enabled_ = enabled
end

--- Check if the UI system is enabled
---@return boolean
function UI.IsEnabled()
    return enabled_
end

-- ============================================================================
-- Root Node Management
-- ============================================================================

--- Set the root widget
---@param widget Widget
---@param destroyOld boolean|nil If true, destroy the old root (default: false)
function UI.SetRoot(widget, destroyOld)
    -- Optionally destroy old root (default: false for UI switching scenarios)
    -- Set destroyOld = true when you want to replace and cleanup the old UI
    if destroyOld and root_ then
        root_:Destroy()
    end

    -- Auto-set pointerEvents = "box-none" on root container.
    -- Root containers are almost always pure layout wrappers (100% x 100%).
    -- Without box-none, the root intercepts ALL hit tests, blocking game input
    -- (UI.GetHoveredWidget() always returns non-nil, game input never reaches).
    -- Only apply if user didn't explicitly set pointerEvents.
    if widget and widget.props and widget.props.pointerEvents == nil then
        widget.props.pointerEvents = "box-none"
        print(
            "[UI] Root widget pointerEvents auto-set to \"box-none\" "
            .. "(prevents root from blocking game input). "
            .. "Set pointerEvents explicitly to suppress this message."
        )
    end

    root_ = widget
    layoutDirty_ = true
end

--- Get the root widget
---@return Widget|nil
function UI.GetRoot()
    return root_
end

--- Find a widget by ID from the current root widget.
---@param id string
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function UI.FindById(id)
    if id == nil or not root_ or not root_.FindById then
        return nil
    end
    return root_:FindById(id)
end

--- Load a UI tree from a .ui.json file.
--- Returns an Instance object with GetRoot/Find/FindAll/Serialize methods.
--- The instance is tracked for automatic GC when root widget is destroyed.
--- If props is provided, the JSON is treated as a template with $prop expansion.
---@param resourceId string Resource identifier (relative path or uuid://)
---@param props table|nil Optional props for template $prop expansion
---@return table|nil instance Instance object, or nil on error
---@return string|nil error Error message if loading failed
function UI.LoadJSON(resourceId, props)
    local UILoader = UI.UILoader
    if not UILoader then
        UILoader = require("urhox-libs/UI/Core/UILoader")
    end
    local instance, err = UILoader.LoadFromFile(resourceId, props)
    if not instance then
        return nil, err
    end
    jsonInstances_[#jsonInstances_ + 1] = instance
    return instance
end

-- ============================================================================
-- Layout
-- ============================================================================

-- Overflow check flag (enable/disable via UI.SetOverflowWarnings)
-- Default to true: overflow warnings help AI detect and fix layout issues
local overflowWarningsEnabled_ = true

--- Calculate layout for the entire UI tree
function UI.Layout()
    if not root_ then return end

    -- Update screen size
    screenWidth_ = graphics.width
    screenHeight_ = graphics.height

    -- Calculate layout from root (always use base pixels)
    -- YGConfigSetPointScaleFactor ensures pixel-perfect alignment when available
    local baseWidth = screenWidth_ / scale_
    local baseHeight = screenHeight_ / scale_
    YGNodeCalculateLayout(root_.node, baseWidth, baseHeight, YGDirectionLTR)

    layoutDirty_ = false

    -- Check for overflow (development aid)
    -- Note: warnedWidgets_ tracks by widget reference, so each widget is warned at most
    -- once. If the widget is destroyed and recreated, the new instance gets a fresh check.
    -- We do NOT reset warnings every layout cycle to avoid spamming the console.
    if overflowWarningsEnabled_ and root_.CheckOverflow then
        root_:CheckOverflow(true)
    end
end

--- Enable or disable overflow warnings
---@param enabled boolean
function UI.SetOverflowWarnings(enabled)
    overflowWarningsEnabled_ = enabled
    -- Also set the Widget-level flag
    Widget.OverflowWarningsEnabled = enabled
end

--- Check if overflow warnings are enabled
---@return boolean
function UI.GetOverflowWarnings()
    return overflowWarningsEnabled_
end

--- Mark layout as dirty (needs recalculation)
function UI.MarkLayoutDirty()
    layoutDirty_ = true
end

--- Check if layout needs recalculation
---@return boolean
function UI.IsLayoutDirty()
    return layoutDirty_
end

--- Get font version counter (incremented on font DWP reload).
--- Widgets compare against this to detect font changes and re-measure text.
---@return number
function UI.GetFontVersion()
    return fontVersion_
end

-- ============================================================================
-- Rendering
-- ============================================================================

--- Recursively reapply styles to all widgets (for scale change)
---@param widget Widget
local function reapplyStyles(widget)
    if widget and widget.props and widget.ApplyStyleToYoga then
        widget:ApplyStyleToYoga(widget.props)
    end
    for _, child in ipairs(widget.children or {}) do
        reapplyStyles(child)
    end
end

local function updateScreenMetrics()
    local newWidth = graphics.width
    local newHeight = graphics.height
    if newWidth ~= screenWidth_ or newHeight ~= screenHeight_ then
        screenWidth_ = newWidth
        screenHeight_ = newHeight
        -- Recalculate scale
        if scaleFunc_ then
            scale_ = scaleFunc_()
        end
        Theme.SetScale(scale_)
        -- Update Yoga point scale factor for pixel-perfect alignment
        local config = YGConfigGetDefault()
        YGConfigSetPointScaleFactor(config, scale_)
        -- Mark layout dirty to recalculate
        layoutDirty_ = true
    end
end

--- Update UI (call every frame for gesture detection)
---@param dt number Delta time in seconds
function UI.Update(dt)
    -- Skip if UI is disabled
    if not enabled_ then return end

    -- Check for screen size change and update scale
    updateScreenMetrics()

    -- Update gesture recognition (for long press detection)
    Gesture.Update(dt)

    -- Update active transitions (only widgets with active transitions, zero overhead otherwise)
    if activeTransitionCount_ > 0 then
        for widget in pairs(activeTransitionWidgets_) do
            widget:BaseUpdate(dt)
        end
    end

    -- Recursively update all widgets
    local function updateWidget(widget)
        if widget.Update then
            widget:Update(dt)
        end
        for _, child in ipairs(widget.children or {}) do
            updateWidget(child)
        end
    end

    if root_ then
        updateWidget(root_)
    end

    -- Update global components (Toast, etc.)
    for _, component in pairs(globalComponents_) do
        if component.Update then
            component:Update(dt)
        end
    end

    -- GC check: remove JSON instances whose root widget has been destroyed/collected
    if #jsonInstances_ > 0 then
        for i = #jsonInstances_, 1, -1 do
            if jsonInstances_[i]:GetRoot() == nil then
                table.remove(jsonInstances_, i)
            end
        end
    end
end

--- Update inspector widget tree independently.
--- Runs on its own Update subscription, unaffected by DisableAutoEventsUpdate().
function UI.UpdateInspector(dt)
    if not inspectorRoot_ then return end
    updateScreenMetrics()
    local function updateWidget(widget)
        if widget.BaseUpdate then widget:BaseUpdate(dt) end
        if widget.Update then widget:Update(dt) end
        for _, child in ipairs(widget.children or {}) do
            updateWidget(child)
        end
    end
    updateWidget(inspectorRoot_)
end

-- Inspector update event subscription (independent of main auto events)
local inspectorEventNode_ = nil
local inspectorEventSO_ = nil

--- Start inspector update loop (independent of main UI auto events)
function UI.EnableInspectorUpdate()
    if inspectorEventNode_ then return end
    inspectorEventNode_ = Node()
    inspectorEventSO_ = inspectorEventNode_:CreateScriptObject("LuaScriptObject")
    inspectorEventSO_:SubscribeToEvent("Update", function(self, eventType, eventData)
        local dt = eventData["TimeStep"]:GetFloat()
        UI.UpdateInspector(dt)
    end)
end

--- Stop inspector update loop
function UI.DisableInspectorUpdate()
    if not inspectorEventNode_ then return end
    inspectorEventNode_:Remove()
    inspectorEventNode_ = nil
    inspectorEventSO_ = nil
end

-- ============================================================================
-- Widget Tree Rendering (Framework-controlled recursion)
-- ============================================================================

--- Resolve transform origin to absolute coordinates
---@param origin string|table|nil Transform origin spec
---@param l table Layout { x, y, w, h }
---@return number originX, number originY
local function resolveTransformOrigin(origin, l)
    if type(origin) == "table" then
        -- { x, y } as fractions 0.0-1.0
        return l.x + (origin[1] or 0.5) * l.w, l.y + (origin[2] or 0.5) * l.h
    end
    -- String presets
    if origin == "top-left" then return l.x, l.y end
    if origin == "top-right" then return l.x + l.w, l.y end
    if origin == "bottom-left" then return l.x, l.y + l.h end
    if origin == "bottom-right" then return l.x + l.w, l.y + l.h end
    if origin == "top" then return l.x + l.w * 0.5, l.y end
    if origin == "bottom" then return l.x + l.w * 0.5, l.y + l.h end
    if origin == "left" then return l.x, l.y + l.h * 0.5 end
    if origin == "right" then return l.x + l.w, l.y + l.h * 0.5 end
    -- Default: "center"
    return l.x + l.w * 0.5, l.y + l.h * 0.5
end

--- Check if a widget has any visual transform applied
---@param widget Widget
---@return boolean
local function hasTransform(widget)
    local rp = widget.renderProps_
    local props = widget.props
    local scale = rp.scale or props.scale
    if scale and scale ~= 1.0 then return true end
    local rotate = rp.rotate or props.rotate
    if rotate and rotate ~= 0 then return true end
    local tx = rp.translateX or props.translateX
    if tx and tx ~= 0 then return true end
    local ty = rp.translateY or props.translateY
    if ty and ty ~= 0 then return true end
    return false
end

--- Apply inverse transform to convert screen coordinates back to layout space.
--- Forward (NanoVG render): T(origin) · R · S · T(-origin) · T(tx,ty)
--- screen = T(origin) · R · S · T(-origin) · T(tx,ty) · P
--- Inverse:  P = T(-tx,-ty) · T(origin) · S^-1 · R^-1 · T(-origin) · screen
---@param widget Widget
---@param x number Screen x in base pixels
---@param y number Screen y in base pixels
---@return number localX, number localY
local function inverseTransformPoint(widget, x, y)
    local rp = widget.renderProps_
    local props = widget.props
    local s = rp.scale or props.scale
    local r = rp.rotate or props.rotate
    local tx = rp.translateX or props.translateX
    local ty = rp.translateY or props.translateY

    -- Early out if no effective transform
    if not ((s and s ~= 1.0) or (r and r ~= 0) or
            (tx and tx ~= 0) or (ty and ty ~= 0)) then
        return x, y
    end

    local l = widget:GetAbsoluteLayoutForHitTest()
    local ox, oy = resolveTransformOrigin(props.transformOrigin, l)

    -- 1. T(-origin): subtract origin
    x = x - ox
    y = y - oy

    -- 2. R^-1: inverse rotate
    if r and r ~= 0 then
        local angle = -r * math.pi / 180
        local ca = math.cos(angle)
        local sa = math.sin(angle)
        x, y = x * ca - y * sa, x * sa + y * ca
    end

    -- 3. S^-1: inverse scale (guard against zero to avoid division by zero)
    if s and s ~= 1.0 and s ~= 0 then
        x = x / s
        y = y / s
    end

    -- 4. T(origin): restore origin
    x = x + ox
    y = y + oy

    -- 5. T(-tx,-ty): undo translate
    if tx or ty then
        x = x - (tx or 0)
        y = y - (ty or 0)
    end

    return x, y
end

--- Convert screen coordinates to widget-local coordinates by accumulating
--- inverse transforms from root down to the target widget.
---@param widget Widget
---@param x number Screen x in base pixels
---@param y number Screen y in base pixels
---@return number localX, number localY
local function screenToWidgetLocal(widget, x, y)
    -- Build ancestor chain (widget → root)
    local chain = {}
    local w = widget
    while w do
        chain[#chain + 1] = w
        w = w.parent
    end
    -- Apply inverse transforms from root (last) down to widget (first)
    for i = #chain, 1, -1 do
        x, y = inverseTransformPoint(chain[i], x, y)
    end
    return x, y
end

local findWidgetAt

-- Cancel pointer press once it is no longer a click candidate.
local function cancelPointer(pointerId, pointerType, x, y)
    local pressedWidget = pressedWidgets_[pointerId]
    if not pressedWidget then return end

    if not x then
        local sx, sy = Input.GetLastPosition(pointerId)
        x, y = sx / scale_, sy / scale_
    end

    local cancelEvent = PointerEvent.new(PointerEvent.Types.PointerCancel, {
        pointerId = pointerId,
        pointerType = pointerType or PointerEvent.PointerTypes.Touch,
        x = 0, y = 0,
        button = -1,
        buttons = PointerEvent.Buttons.None,
        isPrimary = pointerId == 0,
    })
    cancelEvent.target = pressedWidget
    cancelEvent.currentTarget = pressedWidget
    cancelEvent.x, cancelEvent.y = screenToWidgetLocal(pressedWidget, x, y)
    pressedWidgets_[pointerId] = nil
    pressedWidget:OnPointerCancel(cancelEvent)
end

local function clearHoveredPointer(pointerId, event, x, y)
    local hoveredWidget = hoveredWidgets_[pointerId]
    if not hoveredWidget then return end

    local w = hoveredWidget
    while w do
        local leaveEvent = event:Clone()
        leaveEvent.type = PointerEvent.Types.PointerLeave
        leaveEvent.target = w
        leaveEvent.currentTarget = w
        leaveEvent.x, leaveEvent.y = screenToWidgetLocal(w, x, y)
        w:OnPointerLeave(leaveEvent)
        w = w.parent
    end

    hoveredWidgets_[pointerId] = nil
end

local function updateMouseHover(pointerId, event, x, y)
    local widget = findWidgetAt(x, y)
    local previousHovered = hoveredWidgets_[pointerId]
    if widget == previousHovered then return widget end

    -- Handle hover state changes (CSS mouseenter/mouseleave semantics)
    -- Moving from parent to child does NOT fire PointerLeave on parent.
    -- Only fire Enter/Leave when the pointer crosses a widget's subtree boundary.
    local newAncestors = {}
    local w = widget
    while w do
        newAncestors[w] = true
        w = w.parent
    end

    -- PointerLeave: walk from previous up to LCA (not including)
    if previousHovered then
        w = previousHovered
        while w do
            if newAncestors[w] then break end  -- reached common ancestor
            local leaveEvent = event:Clone()
            leaveEvent.type = PointerEvent.Types.PointerLeave
            leaveEvent.target = w
            leaveEvent.currentTarget = w
            w:OnPointerLeave(leaveEvent)
            w = w.parent
        end
    end

    -- PointerEnter: collect widgets from new up to LCA, fire top-down
    if widget then
        local prevAncestors = {}
        w = previousHovered
        while w do
            prevAncestors[w] = true
            w = w.parent
        end

        local toEnter = {}
        w = widget
        while w do
            if prevAncestors[w] then break end  -- reached common ancestor
            toEnter[#toEnter + 1] = w
            w = w.parent
        end
        -- Fire top-down (outermost ancestor first, like CSS mouseenter)
        for i = #toEnter, 1, -1 do
            local ew = toEnter[i]
            local enterEvent = event:Clone()
            enterEvent.type = PointerEvent.Types.PointerEnter
            enterEvent.target = ew
            enterEvent.currentTarget = ew
            ew:OnPointerEnter(enterEvent)
        end
    end

    hoveredWidgets_[pointerId] = widget

    -- Update cursor style (only for primary pointer on desktop)
    if pointerId == 0 and cursorShapeMap_ then
        local cursorStyle = "default"
        if widget then
            -- Walk up ancestors to find nearest cursor prop
            w = widget
            while w do
                if w.props.cursor then
                    cursorStyle = w.props.cursor
                    break
                end
                w = w.parent
            end
        end
        if cursorStyle ~= currentCursorStyle_ then
            currentCursorStyle_ = cursorStyle
            local shape = cursorShapeMap_[cursorStyle] or cursorShapeMap_["default"]
            if shape and ui and ui.cursor then
                ui.cursor:SetShape(shape)
            end
        end
    end

    return widget
end

--- Apply forward transform (layout space to parent space).
--- Mirrors the NanoVG render transform: T(origin) -> R -> S -> T(-origin) -> T(tx,ty) -> P
---@param widget Widget
---@param x number Layout x in base pixels
---@param y number Layout y in base pixels
---@return number screenX, number screenY
local function forwardTransformPoint(widget, x, y)
    local rp = widget.renderProps_
    local props = widget.props
    local s = rp.scale or props.scale
    local r = rp.rotate or props.rotate
    local tx = rp.translateX or props.translateX
    local ty = rp.translateY or props.translateY

    if not ((s and s ~= 1.0) or (r and r ~= 0) or
            (tx and tx ~= 0) or (ty and ty ~= 0)) then
        return x, y
    end

    local l = widget:GetAbsoluteLayoutForHitTest()
    local ox, oy = resolveTransformOrigin(props.transformOrigin, l)

    -- Forward: T(origin) · R · S · T(-origin) · T(tx,ty) · P
    -- 1. T(tx,ty)
    if tx or ty then
        x = x + (tx or 0)
        y = y + (ty or 0)
    end

    -- 2. T(-origin)
    x = x - ox
    y = y - oy

    -- 3. S
    if s and s ~= 1.0 and s ~= 0 then
        x = x * s
        y = y * s
    end

    -- 4. R
    if r and r ~= 0 then
        local angle = r * math.pi / 180
        local ca = math.cos(angle)
        local sa = math.sin(angle)
        x, y = x * ca - y * sa, x * sa + y * ca
    end

    -- 5. T(origin)
    return x + ox, y + oy
end

--- Convert widget layout coordinates to screen coordinates by accumulating
--- forward transforms from widget up to root.
---@param widget Widget
---@param x number Layout x in base pixels
---@param y number Layout y in base pixels
---@return number screenX, number screenY
local function widgetLayoutToScreen(widget, x, y)
    local w = widget
    while w do
        x, y = forwardTransformPoint(w, x, y)
        w = w.parent
    end
    return x, y
end

-- Blend mode mapping: CSS name → NanoVG composite operation constant
local blendModeMap = {
    ["normal"]           = NVG_SOURCE_OVER,
    ["lighter"]          = NVG_LIGHTER,
    ["copy"]             = NVG_COPY,
    ["xor"]              = NVG_XOR,
    ["destination-over"] = NVG_DESTINATION_OVER,
    ["source-in"]        = NVG_SOURCE_IN,
    ["source-out"]       = NVG_SOURCE_OUT,
    ["destination-in"]   = NVG_DESTINATION_IN,
    ["destination-out"]  = NVG_DESTINATION_OUT,
}

--- Recursively render widget tree
--- Framework handles the tree traversal, widgets only need to implement Render() for self-drawing
---@param widget Widget
---@param nvg NVGContextWrapper
local function renderWidgetTree(widget, nvg)
    if not widget:IsVisible() then return end

    -- Check visibility: "hidden" (keeps layout space but skips rendering)
    local visibility = widget.props.visibility
    if visibility == "hidden" then return end

    -- Skip fixed-position widgets during normal render (collected for separate pass on top)
    if not renderingFixed_ and widget.props.position == "fixed" then
        fixedWidgets_[#fixedWidgets_ + 1] = widget
        return
    end

    -- Determine if we need save/restore for opacity, transform, or blend mode
    local rp = widget.renderProps_
    local props = widget.props
    local opacity = rp.opacity or props.opacity
    local needsOpacity = opacity and opacity < 1.0
    local needsTransform = hasTransform(widget)
    local blendMode = rp.blendMode or props.blendMode
    local needsSaveRestore = needsOpacity or needsTransform or blendMode

    if needsSaveRestore then
        if not trySaveNVGState(nvg) then
            -- Defensive: skip save/restore to prevent NanoVG stack overflow
            -- Still render, just without transform/opacity
            needsSaveRestore = false
            needsOpacity = false
            needsTransform = false
            blendMode = nil
        end
    end

    -- Apply opacity (NanoVG globalAlpha is multiplicative within save/restore stack)
    if needsOpacity then
        nvgGlobalAlpha(nvg, math.max(0, math.min(1, opacity)))
    end

    -- Apply blend mode (composite operation, auto-restored by nvgRestore)
    if blendMode then
        nvgGlobalCompositeOperation(nvg, blendModeMap[blendMode] or NVG_SOURCE_OVER)
    end

    -- Apply transform (scale, rotate, translate around transform origin)
    if needsTransform then
        local l = widget:GetAbsoluteLayout()
        local originX, originY = resolveTransformOrigin(props.transformOrigin, l)
        local scale = rp.scale or props.scale
        local rotate = rp.rotate or props.rotate
        local tx = rp.translateX or props.translateX
        local ty = rp.translateY or props.translateY

        -- Translate to origin, apply transforms, translate back
        nvgTranslate(nvg, originX, originY)
        if rotate and rotate ~= 0 then
            nvgRotate(nvg, rotate * math.pi / 180)
        end
        if scale and scale ~= 1.0 then
            nvgScale(nvg, scale, scale)
        end
        nvgTranslate(nvg, -originX, -originY)
        if tx or ty then
            nvgTranslate(nvg, tx or 0, ty or 0)
        end

        -- Use DPR-only text scale during transform to prevent font jitter.
        -- nvgRestore will automatically revert to NVG_TEXT_SCALE_FULL.
        nvgTextScaleMode(nvg, NVG_TEXT_SCALE_DPR_ONLY)
    end

    -- 1. Render the widget itself (background, content, etc.)
    widget:Render(nvg)

    -- 2. Render children
    -- If widget has CustomRenderChildren, let it control child rendering (for scroll, clipping, etc.)
    -- Otherwise, framework handles recursion
    if widget.CustomRenderChildren then
        widget:CustomRenderChildren(nvg, renderWidgetTree)
    else
        -- z-index: use GetRenderChildren() for sorted children list
        local renderList = widget:GetRenderChildren()
        if props.clipDecorations and widget.decorations_ then
            local l = widget:GetAbsoluteLayout()
            for i = 1, #renderList do
                local child = renderList[i]
                if child.isThemeDecoration_ then
                    nvgSave(nvg)
                    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)
                    renderWidgetTree(child, nvg)
                    nvgRestore(nvg)
                else
                    renderWidgetTree(child, nvg)
                end
            end
        else
            for i = 1, #renderList do
                renderWidgetTree(renderList[i], nvg)
            end
        end
    end

    -- Restore NanoVG state (undo opacity + transform)
    if needsSaveRestore then
        restoreNVGState(nvg)
    end
end

--- Render a widget subtree (public API for overlay content rendering)
--- Used by Modal and other overlay widgets to render their Yoga-managed content trees.
---@param widget Widget The root widget of the subtree to render
---@param nvg NVGContextWrapper NanoVG context
function UI.RenderWidgetSubtree(widget, nvg)
    renderWidgetTree(widget, nvg)
end

--- Render the UI
--- All widget rendering uses BASE PIXELS (design-time coordinates)
--- nvgScale(scale) converts base pixels → screen pixels for final display
function UI.Render()
    -- Skip if UI is disabled
    if not enabled_ then return end

    if not nvg_ or not root_ then return end

    -- Recalculate layout if dirty
    if layoutDirty_ then
        UI.Layout()
    end

    -- Clear overlay queue for this frame
    overlayQueue_ = {}

    -- Clear previous frame's fixed offsets and prepare for new collection
    for _, widget in ipairs(fixedWidgets_) do
        widget.fixedOffset_ = nil
    end
    fixedWidgets_ = {}

    -- Update screen size
    local W = graphics.width
    local H = graphics.height

    -- Begin NanoVG frame with logical dimensions
    -- Use scale_ as devicePixelRatio for proper pixel alignment (avoids blurry text)
    local logicalW = W / scale_
    local logicalH = H / scale_
    nvgBeginFrame(nvg_, logicalW, logicalH, scale_)

    -- Reset save depth tracking for this frame
    saveDepth_ = 0

    -- Render widget tree (framework-controlled recursion)
    renderWidgetTree(root_, nvg_)

    -- Render fixed-position widgets on top of normal tree (below overlays)
    if #fixedWidgets_ > 0 then
        local viewW, viewH = screenWidth_ / scale_, screenHeight_ / scale_
        renderingFixed_ = true
        for _, widget in ipairs(fixedWidgets_) do
            if widget:IsVisible() then
                local l = widget:GetLayout()
                local props = widget.props

                -- Compute viewport position from left/top/right/bottom
                local fx, fy
                if props.left ~= nil then
                    fx = props.left
                elseif props.right ~= nil then
                    fx = viewW - l.w - props.right
                else
                    fx = 0
                end
                if props.top ~= nil then
                    fy = props.top
                elseif props.bottom ~= nil then
                    fy = viewH - l.h - props.bottom
                else
                    fy = 0
                end

                -- Set fixedOffset for correct GetAbsoluteLayout and hit testing
                local fo = widget.fixedOffset_
                if fo then fo[1] = fx; fo[2] = fy
                else widget.fixedOffset_ = { fx, fy } end

                renderWidgetTree(widget, nvg_)
            end
        end
        renderingFixed_ = false
    end

    -- Render overlays (dropdowns, tooltips, etc.) on top
    for _, callback in ipairs(overlayQueue_) do
        callback(nvg_)
    end

    -- Render global components (Toast, etc.) on top of everything
    for _, component in pairs(globalComponents_) do
        if component.Render then
            component:Render(nvg_)
        end
    end

    -- Inspector independent widget tree (layout + render every frame)
    if inspectorRoot_ then
        local baseW = screenWidth_ / scale_
        local baseH = screenHeight_ / scale_
        YGNodeCalculateLayout(inspectorRoot_.node, baseW, baseH, YGDirectionLTR)
        renderWidgetTree(inspectorRoot_, nvg_)
    end

    -- Inspector render hook (highlight overlay, tooltip, etc.)
    if inspectorRenderHook_ then
        inspectorRenderHook_(nvg_)
    end

    -- End NanoVG frame
    nvgEndFrame(nvg_)
end

--- Queue a render callback to be executed after all widgets render (for overlays)
---@param callback function(nvg) Render callback
function UI.QueueOverlay(callback)
    table.insert(overlayQueue_, callback)
end

--- Push an overlay widget onto the stack (gets priority in hit testing)
--- Prevents duplicate entries: if widget is already in the stack, it won't be added again.
---@param widget Widget
function UI.PushOverlay(widget)
    -- Prevent duplicate entries
    for _, w in ipairs(overlayStack_) do
        if w == widget then return end
    end
    table.insert(overlayStack_, widget)
end

--- Pop a specific overlay widget from the stack
--- Removes by identity (not blind stack-top pop), safe even if close order is abnormal.
---@param widget Widget|nil If nil, pops the top overlay
function UI.PopOverlay(widget)
    if widget == nil then
        -- Pop top
        if #overlayStack_ > 0 then
            table.remove(overlayStack_)
        end
        return
    end
    -- Find and remove the specific widget
    for i = #overlayStack_, 1, -1 do
        if overlayStack_[i] == widget then
            table.remove(overlayStack_, i)
            return
        end
    end
end

--- Get the topmost overlay widget
---@return Widget|nil
function UI.GetTopOverlay()
    if #overlayStack_ > 0 then
        return overlayStack_[#overlayStack_]
    end
    return nil
end

--- Get the overlay stack (read-only access)
---@return Widget[]
function UI.GetOverlayStack()
    return overlayStack_
end

-- ============================================================================
-- Deprecated Overlay API (forwards to stack-based API)
-- ============================================================================

--- @deprecated Use UI.PushOverlay(widget) instead
---@param widget Widget|nil
function UI.SetActiveOverlay(widget)
    if widget then
        UI.PushOverlay(widget)
    else
        UI.PopOverlay(nil)
    end
end

--- @deprecated Use UI.GetTopOverlay() instead
---@return Widget|nil
function UI.GetActiveOverlay()
    return UI.GetTopOverlay()
end

--- @deprecated Use UI.PopOverlay(widget) instead
function UI.ClearActiveOverlay()
    UI.PopOverlay(nil)
end

--- Register a global component (Toast, etc.) for automatic Update/Render
---@param name string Unique name for the component
---@param component table Component with Update and/or Render methods
function UI.RegisterGlobalComponent(name, component)
    globalComponents_[name] = component
end

--- Unregister a global component
---@param name string
function UI.UnregisterGlobalComponent(name)
    globalComponents_[name] = nil
end

--- Get NanoVG context
---@return NVGContextWrapper
function UI.GetNVGContext()
    return nvg_
end

--- Get UI width in BASE PIXELS (design-time coordinates)
--- Use this for widget positioning calculations
---@return number
function UI.GetWidth()
    return screenWidth_ / scale_
end

--- Get UI height in BASE PIXELS (design-time coordinates)
--- Use this for widget positioning calculations
---@return number
function UI.GetHeight()
    return screenHeight_ / scale_
end

--- Measure text width using NanoVG
--- Recommended for non-Render contexts (Init, event handlers, etc.) - saves/restores NanoVG state.
--- In Render(), prefer nvgTextBounds(nvg, x, y, text) directly for better performance.
---@param text string Text to measure
---@param fontSize number Font size (in NanoVG pixels, use Theme.FontSize() to convert from pt)
---@param fontFamily string|nil Font family (default "sans")
---@param letterSpacing number|nil Letter spacing in pixels (default 0)
---@return number width Width in BASE pixels (nvgTextBounds already applies invscale internally)
function UI.MeasureTextWidth(text, fontSize, fontFamily, letterSpacing)
    if not nvg_ or not text or text == "" then
        return 0
    end

    fontFamily = fontFamily or "sans"

    -- Save current state
    nvgSave(nvg_)

    -- Reset transform to identity (coordinate system is already logical via nvgBeginFrame)
    nvgResetTransform(nvg_)

    -- Set font for measurement
    nvgFontSize(nvg_, fontSize)
    nvgFontFace(nvg_, fontFamily)
    if letterSpacing then
        nvgTextLetterSpacing(nvg_, letterSpacing)
    end

    -- Measure text bounds (nvgTextBounds returns width, bounds_table)
    -- With nvgScale set, nvgTextBounds applies invscale internally
    local width = nvgTextBounds(nvg_, 0, 0, text, nil, nil, false)
    width = width or 0

    -- Restore state
    nvgRestore(nvg_)

    return width
end

--- Measure text and find the largest font size that fits the supplied bounds.
--- The measurement uses the same NanoVG APIs as widget rendering, so font
--- fallback, letter spacing, line height, and the i18n text hook are reflected.
--- This function never changes layout; it only returns a render-time font size.
---
---@param text string Text to measure
---@param options table {
---   fontSize: number, fontFace: string|nil, letterSpacing: number|nil,
---   lineHeight: number|nil, width: number|nil, height: number|nil,
---   multiline: boolean|nil, minFontSize: number|nil, cache: table|nil
--- }
---@return table { fontSize, width, height }
function UI.MeasureTextFit(text, options)
    if type(options) ~= "table" then
        options = {}
    end

    local baseFontSize = tonumber(options.fontSize) or 0
    if baseFontSize ~= baseFontSize or math.abs(baseFontSize) == math.huge then
        baseFontSize = 0
    end
    local fontFace = options.fontFace or "sans"
    local letterSpacing = tonumber(options.letterSpacing) or 0
    if letterSpacing ~= letterSpacing or math.abs(letterSpacing) == math.huge then
        letterSpacing = 0
    end
    local lineHeight = tonumber(options.lineHeight) or 1
    if lineHeight ~= lineHeight or math.abs(lineHeight) == math.huge then
        lineHeight = 1
    end
    if lineHeight <= 0 then lineHeight = 1 end

    local availableWidth = tonumber(options.width)
    local availableHeight = tonumber(options.height)
    -- Treat NaN/infinity as an unconstrained dimension. Passing either through
    -- the Lua-to-C binding can produce undefined line-breaking behavior.
    if availableWidth and (availableWidth ~= availableWidth or math.abs(availableWidth) == math.huge) then
        availableWidth = nil
    end
    if availableHeight and (availableHeight ~= availableHeight or math.abs(availableHeight) == math.huge) then
        availableHeight = nil
    end
    if availableWidth and availableWidth < 0 then availableWidth = 0 end
    if availableHeight and availableHeight < 0 then availableHeight = 0 end

    local multiline = options.multiline == true
    local minFontSize = tonumber(options.minFontSize) or 1
    if minFontSize ~= minFontSize or math.abs(minFontSize) == math.huge then
        minFontSize = 1
    end
    minFontSize = math.max(1, minFontSize)
    if baseFontSize > 0 then
        minFontSize = math.min(minFontSize, baseFontSize)
    end

    local cache = options.cache
    if type(cache) ~= "table" then
        cache = nil
    end
    local fontVersion = fontVersion_
    local uiScale = Theme.GetScale()
    local sameMeasurementContext = cache
        and cache.baseFontSize == baseFontSize
        and cache.fontFace == fontFace
        and cache.letterSpacing == letterSpacing
        and cache.lineHeight == lineHeight
        and cache.availableWidth == availableWidth
        and cache.availableHeight == availableHeight
        and cache.multiline == multiline
        and cache.minFontSize == minFontSize
        and cache.fontVersion == fontVersion
        and cache.uiScale == uiScale
        and cache.context == nvg_
    if sameMeasurementContext and cache.text == text then
        return cache
    end

    local result = cache or {}
    result.text = text
    result.baseFontSize = baseFontSize
    result.fontFace = fontFace
    result.letterSpacing = letterSpacing
    result.lineHeight = lineHeight
    result.availableWidth = availableWidth
    result.availableHeight = availableHeight
    result.multiline = multiline
    result.minFontSize = minFontSize
    result.fontVersion = fontVersion
    result.uiScale = uiScale
    result.context = nvg_

    -- No finite constraint means there is nothing to fit. Avoid touching the
    -- NanoVG state in this common path (auto-width labels and buttons).
    local hasWidthConstraint = availableWidth ~= nil
    local hasHeightConstraint = availableHeight ~= nil
    if not nvg_ or not text or text == "" or baseFontSize <= 0
        or (not hasWidthConstraint and not hasHeightConstraint) then
        result.fontSize = baseFontSize
        result.width = 0
        result.height = 0
        return result
    end

    local function measureAt(fontSize)
        nvgFontFace(nvg_, fontFace)
        nvgFontSize(nvg_, fontSize)
        nvgTextLetterSpacing(nvg_, letterSpacing)
        nvgTextLineHeight(nvg_, lineHeight)
        nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        if multiline then
            -- A large finite break width represents an unconstrained width and
            -- avoids passing infinity through the C binding.
            local breakWidth = hasWidthConstraint and math.max(1, availableWidth) or 1000000
            local bounds = nvgTextBoxBounds(nvg_, 0, 0, breakWidth, text, nil, nil, false)
            if not bounds or not bounds[1] or not bounds[2] or not bounds[3] or not bounds[4] then
                return 0, 0
            end
            return math.max(0, bounds[3] - bounds[1]), math.max(0, bounds[4] - bounds[2])
        end

        local advance, bounds = nvgTextBounds(
            nvg_, 0, 0, text, nil, nil, false)
        local width = tonumber(advance) or 0
        local height = 0
        if bounds and bounds[1] and bounds[2] and bounds[3] and bounds[4] then
            width = math.max(width, bounds[3] - bounds[1])
            height = math.max(0, bounds[4] - bounds[2])
        end

        -- Use the line box as the vertical constraint. Glyph bounds alone can
        -- under-report accents/descenders when the line is vertically centered.
        local _, _, measuredLineHeight = nvgTextMetrics(nvg_)
        if measuredLineHeight and measuredLineHeight > 0 then
            height = math.max(height, measuredLineHeight * lineHeight)
        end
        return math.max(0, width), height
    end

    if not trySaveNVGState(nvg_) then
        -- Do not let a failed native save pair with a successful restore. A
        -- deferred result is deliberately not cache-valid, so a shallower
        -- render can retry the real measurement later.
        result.fontSize = baseFontSize
        result.width = 0
        result.height = 0
        result.context = nil
        return result
    end
    nvgResetTransform(nvg_)

    local function fits(width, height)
        -- nvgTextBox already wraps multiline content to breakRowWidth. Its
        -- reported horizontal bounds can transiently include the character
        -- that triggered a line break, producing a false overflow for exactly
        -- one text prefix. Rechecking that box width here caused the isolated
        -- "tiny font, then normal again" jump at 3 -> 4 lines. For multiline,
        -- only the resulting total height is a fit constraint.
        local widthFits = multiline
            or not hasWidthConstraint
            or width <= availableWidth + 0.25
        local heightFits = not hasHeightConstraint or height <= availableHeight + 0.25
        return widthFits and heightFits
    end

    local measuredWidth, measuredHeight = measureAt(baseFontSize)
    local fittedFontSize = baseFontSize

    if not fits(measuredWidth, measuredHeight) then
        local minWidth, minHeight = measureAt(minFontSize)
        if fits(minWidth, minHeight) then
            fittedFontSize = minFontSize
            measuredWidth, measuredHeight = minWidth, minHeight

            if multiline then
                -- nvgTextBoxBounds changes line breaks at discrete font sizes,
                -- so its fit predicate is not monotonic. Binary search can land
                -- on a much smaller passing branch and then jump back up after
                -- one character is appended. Scan downward instead and select
                -- the first stable passing size. Half-pixel steps deliberately
                -- ignore narrower rasterization islands that would cause jitter.
                local scanStep = 0.5
                local failedSize = baseFontSize
                local candidate = baseFontSize
                while candidate > minFontSize do
                    candidate = math.max(minFontSize, candidate - scanStep)
                    local width, height = measureAt(candidate)
                    if fits(width, height) then
                        fittedFontSize = candidate
                        measuredWidth, measuredHeight = width, height

                        -- Refine only the adjacent half-pixel interval, scanning
                        -- from large to small without assuming monotonicity.
                        local refineStep = scanStep / 8
                        for probe = failedSize - refineStep,
                                candidate + refineStep, -refineStep do
                            local probeWidth, probeHeight = measureAt(probe)
                            if fits(probeWidth, probeHeight) then
                                fittedFontSize = probe
                                measuredWidth, measuredHeight = probeWidth, probeHeight
                                break
                            end
                        end
                        break
                    end
                    failedSize = candidate
                end
            else
                -- Single-line width and line-box height are monotonic, so a
                -- bounded binary search remains both correct and inexpensive.
                local low = minFontSize
                local high = baseFontSize
                for _ = 1, 12 do
                    local middle = (low + high) * 0.5
                    local width, height = measureAt(middle)
                    if fits(width, height) then
                        fittedFontSize = middle
                        low = middle
                    else
                        high = middle
                    end
                end
                measuredWidth, measuredHeight = measureAt(fittedFontSize)
            end
        else
            -- The available box is smaller than the configured floor. Keep the
            -- floor as the least destructive fallback; the caller still clips
            -- to its normal component scissor.
            fittedFontSize = minFontSize
            measuredWidth, measuredHeight = minWidth, minHeight
        end
    end

    restoreNVGState(nvg_)

    result.fontSize = fittedFontSize
    result.width = measuredWidth
    result.height = measuredHeight
    return result
end

--- Measure text baseline (ascender) for baseline alignment.
--- Returns the ascender value: the distance from the top of the text to the baseline.
--- Used by Label to set Yoga baseline values for alignItems="baseline".
---@param fontSize number Font size (in NanoVG pixels, use Theme.FontSize() to convert from pt)
---@param fontFace string|nil Font face (default "sans")
---@return number ascender Distance from top to baseline (positive downward)
function UI.MeasureTextBaseline(fontSize, fontFace)
    if not nvg_ then return 0 end

    fontFace = fontFace or "sans"

    nvgSave(nvg_)
    nvgResetTransform(nvg_)
    nvgFontSize(nvg_, fontSize)
    nvgFontFace(nvg_, fontFace)

    local ascender = nvgTextMetrics(nvg_)  -- returns ascender, descender, lineHeight

    nvgRestore(nvg_)

    return ascender
end

-- ============================================================================
-- Widget Hit Testing
-- ============================================================================

--- Find the topmost widget at given coordinates
---@param x number
---@param y number
---@param widget Widget|nil Starting widget (nil = root)
---@param skipOverlay boolean|nil Skip overlay check (for recursive calls)
---@return Widget|nil
findWidgetAt = function(x, y, widget, skipOverlay)
    -- Inspector independent widget tree (highest priority — rendered last, tested first)
    if not skipOverlay and inspectorRoot_ then
        local found = findWidgetAt(x, y, inspectorRoot_, true)
        if found then return found end
    end

    -- Check overlay stack (top-to-bottom), recurse into overlay subtree
    if not skipOverlay then
        for i = #overlayStack_, 1, -1 do
            local overlay = overlayStack_[i]
            local ox, oy = inverseTransformPoint(overlay, x, y)
            if overlay:HitTest(ox, oy) then
                -- Recurse into overlay's subtree to find deepest hit child
                local deepHit = findWidgetAt(x, y, overlay, true)
                return deepHit or overlay
            end
        end
    end

    -- Check global components (Toast, etc.) - they render on top
    if not skipOverlay then
        for _, component in pairs(globalComponents_) do
            if component.HitTest and component:HitTest(x, y) then
                return component
            end
        end
    end

    -- Check fixed-position widgets (above normal tree, below overlays)
    if not skipOverlay and #fixedWidgets_ > 0 then
        for i = #fixedWidgets_, 1, -1 do
            local fw = fixedWidgets_[i]
            if fw:IsVisible() and fw.fixedOffset_ then
                local pe = fw.props.pointerEvents
                if pe ~= "none" then
                    local fx, fy = inverseTransformPoint(fw, x, y)
                    if fw:HitTest(fx, fy) then
                        local deepHit = findWidgetAt(x, y, fw, true)
                        return deepHit or fw
                    end
                end
            end
        end
    end

    widget = widget or root_
    if not widget then return nil end

    -- Apply inverse transform: convert screen coords to widget-local coords
    -- so that HitTest (which uses un-transformed layout rects) matches visual position.
    -- For widgets without transform, this is a no-op (returns x, y unchanged).
    local lx, ly = inverseTransformPoint(widget, x, y)

    -- Scrollable containers clip children: skip subtree if point is outside bounds
    if widget.GetScroll and not widget:HitTest(lx, ly) then
        return nil
    end

    -- Absolute-positioned overlays (Modal, Drawer, etc.) that reject HitTest:
    -- skip entire subtree to avoid traversing ghost children with stale renderOffset
    if widget.props and widget.props.position == "absolute" and not widget:HitTest(lx, ly) then
        return nil
    end

    -- Check if widget has priority hit areas (e.g., scrollbars) that should be checked before children
    if widget.GetPriorityHitAreas then
        local priorityAreas = widget:GetPriorityHitAreas()
        if priorityAreas then
            for _, area in ipairs(priorityAreas) do
                if lx >= area.x and lx <= area.x + area.w and
                   ly >= area.y and ly <= area.y + area.h then
                    -- Return the widget itself for priority area hits
                    return widget
                end
            end
        end
    end

    -- Check children first (reverse render order so top-most z-index is tested first)
    -- Pass local coords so children's layout rects match the transformed coordinate space
    local hitList = widget:GetRenderChildren()
    for i = #hitList, 1, -1 do
        local child = hitList[i]
        -- Skip invisible widgets and widgets with pointerEvents = "none"
        if not child:IsVisible() then
            -- Skip invisible widgets
        elseif child.props and child.props.pointerEvents == "none" then
            -- Skip this child entirely
        elseif child.props and child.props.position == "fixed" then
            -- Skip: fixed widgets are handled separately in the fixed pass
        else
            local found = findWidgetAt(lx, ly, child, true)
            if found then
                return found
            end
        end
    end

    -- Check special children (bodyChildren_ for Card, etc.)
    if widget.bodyChildren_ then
        for i = #widget.bodyChildren_, 1, -1 do
            local child = widget.bodyChildren_[i]
            -- Skip invisible widgets and widgets with pointerEvents = "none"
            if not child:IsVisible() then
                -- Skip invisible widgets
            elseif child.props and child.props.pointerEvents == "none" then
                -- Skip this child entirely
            else
                local found = findWidgetAt(lx, ly, child, true)
                if found then
                    return found
                end
            end
        end
    end

    -- Check extra hit test children (for widgets with special content like Tabs)
    if widget.GetHitTestChildren then
        local extraChildren = widget:GetHitTestChildren()
        if extraChildren then
            for i = #extraChildren, 1, -1 do
                local child = extraChildren[i]
                -- Skip invisible widgets and widgets with pointerEvents = "none"
                if not child:IsVisible() then
                    -- Skip invisible widgets
                elseif child.props and child.props.pointerEvents == "none" then
                    -- Skip this child entirely
                else
                    local found = findWidgetAt(lx, ly, child, true)
                    if found then
                        return found
                    end
                end
            end
        end
    end

    -- Check self (skip if pointerEvents = "box-none")
    local pointerEvents = widget.props and widget.props.pointerEvents
    if pointerEvents ~= "box-none" and widget:HitTest(lx, ly) then
        return widget
    end

    return nil
end

--- Find the deepest widget at given BASE PIXEL coordinates (public API for Inspector)
---@param x number X in base pixels
---@param y number Y in base pixels
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function UI.FindWidgetAt(x, y)
    return findWidgetAt(x, y)
end

-- ============================================================================
-- Unified Pointer Event Handler
-- ============================================================================

--- Handle a pointer event from InputAdapter
---@param event PointerEvent
function UI.HandlePointerEvent(event)
    -- Skip if UI is disabled
    if not enabled_ then return end

    local pointerId = event.pointerId

    if event.type == PointerEvent.Types.PointerMove then
        UI.HandlePointerMove(event)
    elseif event.type == PointerEvent.Types.PointerDown then
        UI.HandlePointerDown(event)
    elseif event.type == PointerEvent.Types.PointerUp then
        UI.HandlePointerUp(event)
    elseif event.type == PointerEvent.Types.PointerCancel then
        UI.HandlePointerCancel(event)
    end
end

--- Handle pointer move
---@param event PointerEvent
function UI.HandlePointerMove(event)
    local pointerId = event.pointerId
    -- Convert screen pixels to base pixels for hit testing and event coordinates
    local x, y = event.x / scale_, event.y / scale_
    event.x, event.y = x, y  -- Update event coordinates to base pixels

    -- Inspector intercept (picking mode hover)
    if inspectorMoveHook_ and inspectorMoveHook_(x, y) then return end

    -- Find widget under pointer
    local widget
    local trackHover = event.pointerType == PointerEvent.PointerTypes.Mouse
    if trackHover then
        widget = updateMouseHover(pointerId, event, x, y)
    else
        widget = findWidgetAt(x, y)
    end

    -- Notify hovered widget of move
    if widget then
        event.target = widget
        event.currentTarget = widget
        event.x, event.y = screenToWidgetLocal(widget, x, y)
        widget:OnPointerMove(event)
    end

    -- Also notify the pressed widget if different from hovered (for drag operations)
    local pressedWidget = pressedWidgets_[pointerId]
    if pressedWidget and pressedWidget ~= widget then
        local dragEvent = event:Clone()
        dragEvent.target = pressedWidget
        dragEvent.currentTarget = pressedWidget
        dragEvent.x, dragEvent.y = screenToWidgetLocal(pressedWidget, x, y)
        pressedWidget:OnPointerMove(dragEvent)
    end
end

--- Handle pointer down
---@param event PointerEvent
function UI.HandlePointerDown(event)
    local pointerId = event.pointerId
    -- Convert screen pixels to base pixels for hit testing and event coordinates
    local x, y = event.x / scale_, event.y / scale_
    event.x, event.y = x, y  -- Update event coordinates to base pixels

    -- Inspector intercept (picking mode click)
    if inspectorInputHook_ and inspectorInputHook_(x, y) then return end

    -- Find widget under pointer
    local widget = findWidgetAt(x, y)

    if widget then
        event.target = widget
        event.currentTarget = widget
        event.x, event.y = screenToWidgetLocal(widget, x, y)

        pressedWidgets_[pointerId] = widget
        widget:OnPointerDown(event)

        -- Update focus (only for primary pointer, skip non-focusable widgets like EditMenu)
        if event.isPrimary and widget ~= focusedWidget_ and widget.focusable ~= false then
            if focusedWidget_ then
                focusedWidget_:OnBlur()
            end
            focusedWidget_ = widget
            widget:OnFocus()
        end
    else
        -- Click outside - clear focus (only for primary pointer)
        if event.isPrimary and focusedWidget_ then
            focusedWidget_:OnBlur()
            focusedWidget_ = nil
        end
        pressedWidgets_[pointerId] = nil
    end
end

--- Handle pointer up
---@param event PointerEvent
function UI.HandlePointerUp(event)
    local pointerId = event.pointerId
    -- Convert screen pixels to base pixels for hit testing and event coordinates
    local x, y = event.x / scale_, event.y / scale_
    event.x, event.y = x, y  -- Update event coordinates to base pixels

    -- Inspector intercept (selection box drag end)
    if inspectorPointerUpHook_ and inspectorPointerUpHook_(x, y) then return end

    local widget = findWidgetAt(x, y)
    local pressedWidget = pressedWidgets_[pointerId]

    if pressedWidget then
        event.target = pressedWidget
        event.currentTarget = pressedWidget
        event.x, event.y = screenToWidgetLocal(pressedWidget, x, y)
        pressedWidget:OnPointerUp(event)

        -- Click: pressed and released on same widget
        if widget == pressedWidget then
            pressedWidget:OnClick(event)
        end
    end

    if event.pointerType ~= PointerEvent.PointerTypes.Mouse then
        clearHoveredPointer(pointerId, event, x, y)
    end

    pressedWidgets_[pointerId] = nil
end

--- Handle pointer cancel
---@param event PointerEvent
function UI.HandlePointerCancel(event)
    local pointerId = event.pointerId
    local pressedWidget = pressedWidgets_[pointerId]
    local x, y = event.x / scale_, event.y / scale_
    event.x, event.y = x, y

    if pressedWidget then
        event.target = pressedWidget
        event.currentTarget = pressedWidget
        event.x, event.y = screenToWidgetLocal(pressedWidget, x, y)
        pressedWidget:OnPointerCancel(event)
    end
    clearHoveredPointer(pointerId, event, x, y)

    pressedWidgets_[pointerId] = nil
    hoveredWidgets_[pointerId] = nil
end

-- ============================================================================
-- Gesture Event Handler
-- ============================================================================

--- Handle a gesture event from Gesture module
---@param event GestureEvent
function UI.HandleGestureEvent(event)
    -- Skip if UI is disabled
    if not enabled_ then return end

    -- Convert screen pixels to base pixels for event coordinates
    local baseX, baseY = event.x / scale_, event.y / scale_

    -- Normalize delta/distance/velocity from screen pixels to base pixels
    -- (Gesture module computes these in screen pixels because it receives
    -- PointerEvents before UI.HandlePointerEvent normalizes coordinates)
    event.deltaX = event.deltaX / scale_
    event.deltaY = event.deltaY / scale_
    event.totalDeltaX = event.totalDeltaX / scale_
    event.totalDeltaY = event.totalDeltaY / scale_
    event.distance = event.distance / scale_
    event.velocity = event.velocity / scale_
    event.centerX = event.centerX / scale_
    event.centerY = event.centerY / scale_

    -- Use the target from gesture system (set at gesture start)
    -- For Pan/Pinch gestures, the target should remain the same widget throughout
    local widget = event.target
    if not widget then
        -- Fallback: find widget at gesture location (for tap, etc.)
        widget = findWidgetAt(baseX, baseY)
        if not widget then return end
        event.target = widget
    end

    -- Transform event coordinates to widget-local space
    event.x, event.y = screenToWidgetLocal(widget, baseX, baseY)

    -- Dispatch to appropriate widget handler based on gesture type
    local gestureType = event.type

    if gestureType == GestureEvent.Types.Tap then
        widget:OnTap(event)
    elseif gestureType == GestureEvent.Types.DoubleTap then
        widget:OnDoubleTap(event)
    elseif gestureType == GestureEvent.Types.LongPressStart then
        widget:OnLongPressStart(event)
    elseif gestureType == GestureEvent.Types.LongPressEnd then
        widget:OnLongPressEnd(event)
    elseif gestureType == GestureEvent.Types.Swipe or
           gestureType == GestureEvent.Types.SwipeLeft or
           gestureType == GestureEvent.Types.SwipeRight or
           gestureType == GestureEvent.Types.SwipeUp or
           gestureType == GestureEvent.Types.SwipeDown then
        widget:OnSwipe(event)
    elseif gestureType == GestureEvent.Types.PanStart or
           gestureType == GestureEvent.Types.PanMove or
           gestureType == GestureEvent.Types.PanEnd then
        -- Pan gestures: let target widget handle first, bubble up if not handled
        -- A widget handles pan by having OnPanStart return true (or be in dragging state)
        local target = widget
        while target do
            if target.OnPanStart then
                event.target = target
                -- Re-transform coords for the bubble target
                event.x, event.y = screenToWidgetLocal(target, baseX, baseY)
                local handled = false
                if gestureType == GestureEvent.Types.PanStart then
                    -- OnPanStart returns true if widget wants to handle this pan gesture
                    handled = target:OnPanStart(event)
                elseif gestureType == GestureEvent.Types.PanMove then
                    -- For move/end, check if this widget is currently dragging
                    -- Use both 'isDragging' and 'dragging' for compatibility
                    local isDragging = target.state and (target.state.isDragging or target.state.dragging)
                    if isDragging then
                        target:OnPanMove(event)
                        handled = true
                    end
                else -- PanEnd
                    local isDragging = target.state and (target.state.isDragging or target.state.dragging)
                    if isDragging then
                        target:OnPanEnd(event)
                        handled = true
                    end
                end
                -- If this widget handled the gesture, stop bubbling
                if handled then
                    return
                end
            end
            target = target.parent
        end
    elseif gestureType == GestureEvent.Types.PinchStart then
        widget:OnPinchStart(event)
    elseif gestureType == GestureEvent.Types.PinchMove then
        widget:OnPinchMove(event)
    elseif gestureType == GestureEvent.Types.PinchEnd then
        widget:OnPinchEnd(event)
    end
end

-- ============================================================================
-- Legacy Event Handlers (for backward compatibility)
-- ============================================================================

--- Handle mouse move event (legacy - routes to InputAdapter)
---@param x number
---@param y number
function UI.HandleMouseMove(x, y)
    InputAdapter.HandleMouseMove(x, y)
end

--- Handle mouse button down event (legacy - routes to InputAdapter)
---@param x number
---@param y number
---@param button number
function UI.HandleMouseDown(x, y, button)
    InputAdapter.HandleMouseDown(x, y, button)
end

--- Handle mouse button up event (legacy - routes to InputAdapter)
---@param x number
---@param y number
---@param button number
function UI.HandleMouseUp(x, y, button)
    InputAdapter.HandleMouseUp(x, y, button)
end

-- ============================================================================
-- Touch Event Handlers (for mobile platforms)
-- ============================================================================

--- Handle touch begin event
---@param touchId number
---@param x number
---@param y number
---@param pressure number|nil
function UI.HandleTouchBegin(touchId, x, y, pressure)
    InputAdapter.HandleTouchBegin(touchId, x, y, pressure)
end

--- Handle touch move event
---@param touchId number
---@param x number
---@param y number
---@param pressure number|nil
function UI.HandleTouchMove(touchId, x, y, pressure)
    InputAdapter.HandleTouchMove(touchId, x, y, pressure)
end

--- Handle touch end event
---@param touchId number
---@param x number
---@param y number
function UI.HandleTouchEnd(touchId, x, y)
    InputAdapter.HandleTouchEnd(touchId, x, y)
end

--- Handle touch cancel event
---@param touchId number
function UI.HandleTouchCancel(touchId)
    InputAdapter.HandleTouchCancel(touchId)
end

-- ============================================================================
-- Keyboard Event Handlers
-- ============================================================================

--- Handle key down event
---@param key number Key code
function UI.HandleKeyDown(key)
    -- Skip if UI is disabled
    if not enabled_ then return end

    if focusedWidget_ and focusedWidget_.OnKeyDown then
        focusedWidget_:OnKeyDown(key)
    end
end

--- Handle key up event
---@param key number Key code
function UI.HandleKeyUp(key)
    -- Skip if UI is disabled
    if not enabled_ then return end

    if focusedWidget_ and focusedWidget_.OnKeyUp then
        focusedWidget_:OnKeyUp(key)
    end
end

--- Handle text input event
---@param text string Input text
function UI.HandleTextInput(text)
    -- Skip if UI is disabled
    if not enabled_ then return end

    if focusedWidget_ and focusedWidget_.OnTextInput then
        focusedWidget_:OnTextInput(text)
    end
end

--- Handle mouse wheel event
---@param dx number Horizontal scroll
---@param dy number Vertical scroll
function UI.HandleWheel(dx, dy)
    -- Skip if UI is disabled
    if not enabled_ then return end

    local sx, sy = Input.GetLastPosition(0)
    local x, y = sx / scale_, sy / scale_

    local handled = false

    -- Find scrollable widget under primary pointer
    local widget = hoveredWidgets_[0]

    -- Fallback: if no hovered widget, try to find ScrollView in root
    if not widget and root_ then
        widget = root_
    end

    while widget do
        if widget.OnWheel then
            widget:OnWheel(dx, dy)
            handled = true
            break
        end
        widget = widget.parent
    end

    -- Last resort: find first child with OnWheel
    if not handled and root_ then
        for _, child in ipairs(root_.children) do
            if child.OnWheel then
                child:OnWheel(dx, dy)
                handled = true
                break
            end
        end
    end

    if handled then
        local hoverEvent = PointerEvent.new(PointerEvent.Types.PointerMove, {
            pointerId = 0,
            pointerType = PointerEvent.PointerTypes.Mouse,
            x = x,
            y = y,
            pressure = 0,
            button = -1,
            buttons = PointerEvent.Buttons.None,
            isPrimary = true,
        })
        updateMouseHover(0, hoverEvent, x, y)
    end
end

-- ============================================================================
-- Focus Management
-- ============================================================================

--- Set focus to a widget
---@param widget Widget|nil
function UI.SetFocus(widget)
    if focusedWidget_ == widget then return end

    if focusedWidget_ then
        focusedWidget_:OnBlur()
    end

    focusedWidget_ = widget

    if widget then
        widget:OnFocus()
    end
end

--- Get the currently focused widget
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function UI.GetFocus()
    return focusedWidget_
end

--- Clear focus
function UI.ClearFocus()
    UI.SetFocus(nil)
end

-- ============================================================================
-- Convenience: Get current hovered/pressed widget
-- ============================================================================

--- Get hovered widget for primary pointer
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function UI.GetHoveredWidget()
    return hoveredWidgets_[0]
end

--- Check if pointer is over any interactive UI widget.
--- Convenience wrapper for game input coordination.
--- Usage in game code:
---   if UI.IsPointerOverUI() then return end  -- Skip game input
---@return boolean
function UI.IsPointerOverUI()
    return hoveredWidgets_[0] ~= nil
end

--- Get pressed widget for primary pointer
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function UI.GetPressedWidget()
    return pressedWidgets_[0]
end

--- Get hovered widget for specific pointer
---@param pointerId number
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function UI.GetHoveredWidgetForPointer(pointerId)
    return hoveredWidgets_[pointerId]
end

--- Get pressed widget for specific pointer
---@param pointerId number
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function UI.GetPressedWidgetForPointer(pointerId)
    return pressedWidgets_[pointerId]
end

-- ============================================================================
-- Theme Access (convenience)
-- ============================================================================

UI.theme = setmetatable({}, {
    __index = function(_, key)
        local theme = Theme.GetTheme()
        return theme and theme[key]
    end
})

UI.SetTheme = Theme.SetTheme
UI.GetTheme = Theme.GetTheme

-- ============================================================================
-- Screen Size
-- ============================================================================

function UI.GetScreenWidth()
    return graphics.width
end

function UI.GetScreenHeight()
    return graphics.height
end

--- Get viewport size in BASE PIXELS (design-time coordinates)
--- Use this for widget positioning calculations
---@return number width, number height
function UI.GetViewportSize()
    return screenWidth_ / scale_, screenHeight_ / scale_
end

-- ============================================================================
-- Safe Area
-- ============================================================================

--- Get safe area insets for notch/cutout displays in BASE PIXELS
--- Use this to avoid UI elements being hidden by notches, rounded corners, etc.
---@return table { left, top, right, bottom } insets in base pixels
function UI.GetSafeAreaInsets()
    -- GetSafeAreaInsets returns Rect with min.x=left, min.y=top, max.x=right, max.y=bottom
    local rect = GetSafeAreaInsets(false)  -- false = don't apply engine's view scale
    -- Convert screen pixels to base pixels
    return {
        left = rect.min.x / scale_,
        top = rect.min.y / scale_,
        right = rect.max.x / scale_,
        bottom = rect.max.y / scale_
    }
end

--- Get safe content area (viewport minus safe area insets) in BASE PIXELS
--- Use this to get the usable content area that avoids notches/cutouts
---@return number x, number y, number width, number height
function UI.GetSafeContentArea()
    local insets = UI.GetSafeAreaInsets()
    local viewW, viewH = UI.GetViewportSize()
    local x = insets.left
    local y = insets.top
    local w = viewW - insets.left - insets.right
    local h = viewH - insets.top - insets.bottom
    return x, y, w, h
end

-- ============================================================================
-- UI Scaling
-- ============================================================================

--- Get the current UI scale factor
---@return number scale
function UI.GetScale()
    return scale_
end

--- Get the visual (on-screen) bounding rect of a widget, accounting for all
--- ancestor transforms (scale, rotate, translate). Useful for overlay positioning
--- (e.g., Dropdown popup, Popover, Tooltip) that render outside the transform stack.
---@param widget Widget
---@return table { x, y, w, h } Visual AABB in base pixels
function UI.GetVisualRect(widget)
    local l = widget:GetAbsoluteLayoutForHitTest()
    -- Transform 4 corners to screen space, take AABB
    local x1, y1 = widgetLayoutToScreen(widget, l.x, l.y)
    local x2, y2 = widgetLayoutToScreen(widget, l.x + l.w, l.y)
    local x3, y3 = widgetLayoutToScreen(widget, l.x, l.y + l.h)
    local x4, y4 = widgetLayoutToScreen(widget, l.x + l.w, l.y + l.h)
    local minX = math.min(x1, x2, x3, x4)
    local minY = math.min(y1, y2, y3, y4)
    local maxX = math.max(x1, x2, x3, x4)
    local maxY = math.max(y1, y2, y3, y4)
    return { x = minX, y = minY, w = maxX - minX, h = maxY - minY }
end

--- Set the UI scale (number, function, or nil)
--- number: fixed scale value
--- function: dynamic calculation (no params)
--- nil: physical pixels (scale = 1)
---@param value number|function|nil
function UI.SetScale(value)
    if value == nil then
        scale_ = 1
        scaleFunc_ = nil
    elseif type(value) == "function" then
        scaleFunc_ = value
        scale_ = scaleFunc_()
    else
        scale_ = value
        scaleFunc_ = nil
    end
    Theme.SetScale(scale_)
end

--- Get the design base size
---@return number|nil
function UI.GetDesignSize()
    return designSize_
end

--- Scale multiple values by the current UI scale factor
---@vararg number
---@return number ...
function UI.ScaleMultiple(...)
    local args = {...}
    local results = {}
    for i, v in ipairs(args) do
        results[i] = v * scale_
    end
    return table.unpack(results)
end

-- ============================================================================
-- Inspector Hook API (used by UIInspector module)
-- ============================================================================

--- Set inspector render hook (called after all widgets render, before nvgEndFrame)
---@param hook function(nvg)|nil
function UI.SetInspectorRenderHook(hook)
    inspectorRenderHook_ = hook
end

--- Set inspector input hook for pointer down (returns true to consume event)
---@param hook function(x: number, y: number): boolean|nil
function UI.SetInspectorInputHook(hook)
    inspectorInputHook_ = hook
end

--- Set inspector move hook for pointer move (returns true to consume event)
---@param hook function(x: number, y: number): boolean|nil
function UI.SetInspectorMoveHook(hook)
    inspectorMoveHook_ = hook
end

--- Set inspector pointer-up hook (returns true to consume event)
---@param hook function(x: number, y: number): boolean|nil
function UI.SetInspectorPointerUpHook(hook)
    inspectorPointerUpHook_ = hook
end

--- Cancel the pressed widget for a given pointer.
--- Used by ScrollView to cancel child pressed state when scroll gesture starts,
--- without affecting other widgets' drag operations.
---@param pointerId number
---@param pointerType string|nil Pointer type (default: Touch)
---@param x number|nil Screen x in base pixels (default: last known position)
---@param y number|nil Screen y in base pixels (default: last known position)
UI.CancelPointer = cancelPointer

--- Set inspector independent widget tree root.
--- This tree is layouted and rendered every frame, independent of main root_.
--- Hit testing checks this tree above main tree but below overlays/fixed.
---@param widget Widget|nil
function UI.SetInspectorRoot(widget)
    inspectorRoot_ = widget
end

--- Get inspector independent widget tree root.
---@return Widget|nil
function UI.GetInspectorRoot()
    return inspectorRoot_
end

-- ============================================================================
-- Input Module Access (for global event subscription)
-- ============================================================================

UI.Input = Input
UI.InputAdapter = InputAdapter
UI.PointerEvent = PointerEvent

-- ============================================================================
-- Gesture Module Access
-- ============================================================================

UI.Gesture = Gesture
UI.GestureEvent = GestureEvent

return UI
