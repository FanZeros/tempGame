-- ============================================================================
-- Widget Base Class
-- UrhoX UI Library - Yoga + NanoVG
-- ============================================================================
--
-- ⚠️ IMPORTANT: Layout uses Yoga engine (like React Native), NOT CSS Flexbox!
--
-- ============================================================================
-- 📦 BOX MODEL: Yoga uses BORDER-BOX (like CSS box-sizing: border-box)
-- ============================================================================
--
-- When you set width/height explicitly:
--   - Padding is INSIDE the width/height (does NOT add to total size)
--   - width = content + padding + border
--
-- When width/height is "auto":
--   - Padding INCREASES the total size
--   - Total size = content + padding + border
--
-- Example:
--   { width = 100, paddingHorizontal = 20 }
--   → Total width = 100 (explicit)
--   → Content area = 100 - 20 - 20 = 60
--
--   { paddingHorizontal = 20, children = { {width = 60} } }
--   → Total width = 60 + 20 + 20 = 100 (auto-sized)
--
-- YGNodeLayoutGetWidth() returns border-box width (includes padding)
-- See: 3rd/yoga/website/docs/styling/width-height.mdx
--
-- ============================================================================
-- 🔄 FLEXBOX DIFFERENCES FROM CSS
-- ============================================================================
--
-- Key differences from CSS:
--   ┌─────────────┬─────────────┬─────────────┐
--   │ Property    │ CSS Default │ Yoga Default│
--   ├─────────────┼─────────────┼─────────────┤
--   │ flexShrink  │ 1 (shrink)  │ 0 (no shrink)│
--   │ flexDirection│ row        │ column      │
--   └─────────────┴─────────────┴─────────────┘
--
-- Common issue: Children overflow parent container
--   - Yoga elements do NOT shrink by default (flexShrink = 0)
--   - If total children size > container size, content will overflow
--
-- Solutions:
--   1. Set flexShrink = 1 on children that should shrink
--   2. Increase container size
--   3. Remove fixed height from container (let it grow)
--   4. Use ScrollView for scrollable content
--
-- ============================================================================

local Style = require("urhox-libs/UI/Core/Style")
local Theme = require("urhox-libs/UI/Core/Theme")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")
local Transition = require("urhox-libs/UI/Core/Transition")

-- Layout dirty callback (set by UI.lua to avoid circular dependency)
local onLayoutDirty_ = nil

-- Transition system callback (set by UI.lua to track widgets with active transitions)
local onTransitionStart_ = nil
local onTransitionEnd_ = nil

-- 旧引擎没有 nvgBoxGradientGaussian（热更 Lua 先于引擎二进制更新），回退线性 falloff。
local _hasBoxGradientGaussian = type(nvgBoxGradientGaussian) == "function"
local _nvgBoxGradientGaussian = _hasBoxGradientGaussian and nvgBoxGradientGaussian
    or nvgBoxGradient

-- ============================================================================
-- Props Type Definition
-- ============================================================================

--- RGBA color as array {r, g, b, a} where values are 0-255
---@alias RGBAColor {[1]: number, [2]: number, [3]: number, [4]: number?}

---@class WidgetProps
---@field [string] any Allow custom extension properties
---@field id? string Widget identifier
---@field visible? boolean Visibility (default: true)
---@field children? Widget[] Child widgets
--- Layout - Size
---@field width? number|string Width (number, "auto", or "XX%")
---@field height? number|string Height (number, "auto", or "XX%")
---@field minWidth? number|string Minimum width
---@field maxWidth? number|string Maximum width
---@field minHeight? number|string Minimum height
---@field maxHeight? number|string Maximum height
--- Layout - Flexbox
---@field flexDirection? string "row" | "column" | "row-reverse" | "column-reverse"
---@field justifyContent? string "flex-start" | "center" | "flex-end" | "space-between" | "space-around" | "space-evenly"
---@field alignItems? string "flex-start" | "center" | "flex-end" | "stretch" | "baseline"
---@field alignSelf? string "auto" | "flex-start" | "center" | "flex-end" | "stretch" | "baseline"
---@field alignContent? string Align content for wrapped lines
---@field flexWrap? string "no-wrap" | "wrap" | "wrap-reverse"
---@field flexGrow? number Flex grow factor
---@field flexShrink? number Flex shrink factor
---@field flexBasis? number|string Flex basis
---@field flex? number Shorthand for flex grow/shrink/basis
--- Layout - Gap
---@field gap? number|string Gap between children
---@field rowGap? number|string Row gap
---@field columnGap? number|string Column gap
--- Layout - Margin
---@field margin? number|string|table Margin: number (all sides), "X%" (percent), "auto", or table
---  Table forms: { left=N, right=N, top=N, bottom=N, horizontal=N, vertical=N } (named keys, values can be number/"X%"/"auto")
---  CSS shorthand: { all }, { vert, horiz }, { top, horiz, bottom }, { top, right, bottom, left }
---@field marginTop? number|string Top margin
---@field marginRight? number|string Right margin
---@field marginBottom? number|string Bottom margin
---@field marginLeft? number|string Left margin
---@field marginHorizontal? number|string Horizontal margin
---@field marginVertical? number|string Vertical margin
--- Layout - Padding
---@field padding? number|string|table Padding: number (all sides), "X%" (percent), or table
---  Table forms: { left=N, right=N, top=N, bottom=N, horizontal=N, vertical=N } (named keys, values can be number/"X%")
---  CSS shorthand: { all }, { vert, horiz }, { top, horiz, bottom }, { top, right, bottom, left }
---@field paddingTop? number|string Top padding
---@field paddingRight? number|string Right padding
---@field paddingBottom? number|string Bottom padding
---@field paddingLeft? number|string Left padding
---@field paddingHorizontal? number|string Horizontal padding
---@field paddingVertical? number|string Vertical padding
--- Layout - Position
---@field position? string "relative" | "absolute"
---@field top? number|string Top position
---@field right? number|string Right position
---@field bottom? number|string Bottom position
---@field left? number|string Left position
---@field overflow? string "visible" | "hidden" | "scroll"
---@field aspectRatio? number Aspect ratio (e.g. 16/9), Yoga calculates the other dimension
--- Appearance
---@field backgroundColor? RGBAColor|string|false Background color or false to disable
---@field backgroundImage? string Background image path
---@field backgroundImageOpacity? number Background image opacity, 0-1 (default: 1)
---@field clipDecorations? boolean Clip theme-injected decoration children to this widget border-box
---@field backgroundFit? string "fill" | "contain" | "cover"
---@field backgroundSlice? table 9-slice {left, top, right, bottom}
---@field imageTint? RGBAColor|string Tint color for background image (multiplicative blend)
---@field borderRadius? number|table Border radius: number (uniform) or {TL, TR, BR, BL} (per-corner)
---@field borderRadiusTopLeft? number Top-left corner radius (overrides borderRadius)
---@field borderRadiusTopRight? number Top-right corner radius (overrides borderRadius)
---@field borderRadiusBottomRight? number Bottom-right corner radius (overrides borderRadius)
---@field borderRadiusBottomLeft? number Bottom-left corner radius (overrides borderRadius)
---@field borderColor? RGBAColor|string Border color (uniform)
---@field borderWidth? number|table Border width: number (uniform) or table
---@field borderAlign? "center"|"inside"|"outside" Border stroke alignment. Visual only; does not affect Yoga layout.
---  Table forms: { top=N, bottom=N, left=N, right=N, horizontal=N, vertical=N } (named keys)
---  CSS shorthand: { all }, { vert, horiz }, { top, horiz, bottom }, { top, right, bottom, left }
---@field borderTopWidth? number Top border width
---@field borderTopColor? RGBAColor|string Top border color
---@field borderBottomWidth? number Bottom border width
---@field borderBottomColor? RGBAColor|string Bottom border color
---@field borderLeftWidth? number Left border width
---@field borderLeftColor? RGBAColor|string Left border color
---@field borderRightWidth? number Right border width
---@field borderRightColor? RGBAColor|string Right border color
---@field shape? string "rect" | "circle"
---@field backgroundGradient? table { type="linear"|"radial", direction, from={RGBA}, to={RGBA} }
--- Shadow
---@field backdropBlur? number Backdrop blur intensity (visual approximation, not true Gaussian)
---@field boxShadow? table|false Enhanced shadow array of NAMED-field entries: { {x=0, y=4, blur=12, spread=0, color={0,0,0,60}, inset=false, side="bottom", curve="microVolume"}, ... }; positional arrays and "#hex" color strings are auto-normalized at prop ingestion (#2090); false disables fallback shadow
---@field shadowBlur? number Shadow blur radius (legacy, use boxShadow for advanced)
---@field shadowX? number Shadow X offset
---@field shadowY? number Shadow Y offset
---@field shadowColor? RGBAColor|string Shadow color
--- Pointer Events
---@field onPointerEnter? fun(event: PointerEvent, widget: Widget)
---@field onPointerLeave? fun(event: PointerEvent, widget: Widget)
---@field onPointerDown? fun(event: PointerEvent, widget: Widget)
---@field onPointerUp? fun(event: PointerEvent, widget: Widget)
---@field onPointerMove? fun(event: PointerEvent, widget: Widget)
---@field onPointerCancel? fun(event: PointerEvent, widget: Widget)
--- Gesture Events
---@field onClick? fun(widget: Widget, event?: PointerEvent)
---@field onTap? fun(event: GestureEvent, widget: Widget)
---@field onDoubleTap? fun(event: GestureEvent, widget: Widget)
---@field onLongPress? fun(event: GestureEvent, widget: Widget)
---@field onLongPressStart? fun(event: GestureEvent, widget: Widget)
---@field onLongPressEnd? fun(event: GestureEvent, widget: Widget)
---@field onSwipe? fun(event: GestureEvent, widget: Widget)
---@field onSwipeLeft? fun(event: GestureEvent, widget: Widget)
---@field onSwipeRight? fun(event: GestureEvent, widget: Widget)
---@field onSwipeUp? fun(event: GestureEvent, widget: Widget)
---@field onSwipeDown? fun(event: GestureEvent, widget: Widget)
---@field onPan? fun(event: GestureEvent, widget: Widget)
---@field onPanStart? fun(event: GestureEvent, widget: Widget)
---@field onPanMove? fun(event: GestureEvent, widget: Widget)
---@field onPanEnd? fun(event: GestureEvent, widget: Widget)
---@field onPinch? fun(event: GestureEvent, widget: Widget)
---@field onPinchStart? fun(event: GestureEvent, widget: Widget)
---@field onPinchMove? fun(event: GestureEvent, widget: Widget)
---@field onPinchEnd? fun(event: GestureEvent, widget: Widget)
--- Focus Events
---@field onFocus? fun(widget: Widget)
---@field onBlur? fun(widget: Widget)
--- Behavior
---@field pointerEvents? string "auto" | "none" | "box-none" | "box-only"
---@field allowOverflow? boolean Allow content to overflow bounds
--- Typography
---@field fontFamily? string Font family name
--- Transitions & Transforms
---@field transition? table|string Transition config: { properties, duration, easing } or "all 0.3s easeOut"
---@field opacity? number Opacity 0.0~1.0 (default: 1.0, affects entire subtree)
---@field scale? number Uniform scale (default: 1.0)
---@field rotate? number Rotation in degrees (default: 0)
---@field translateX? number X translation in base pixels (default: 0)
---@field translateY? number Y translation in base pixels (default: 0)
---@field transformOrigin? string|table "center" | "top-left" | { x, y } (default: "center")
---@field visibility? string "visible" | "hidden" (default: "visible", hidden keeps layout space)
---@field cursor? string Cursor style: "default"|"pointer"|"text"|"move"|"not-allowed"|"crosshair"
---@field position? string "sticky" for sticky positioning in ScrollView (vertical only)
---@field stickyOffset? number Offset from top when sticky (default: 0)
---@field clipPath? string|table Clip shape: "circle"|"ellipse"|{type="circle",radius=N}|{type="ellipse",rx=N,ry=N}

---@class Widget
---@overload fun(props?: WidgetProps): Widget
---@field node YGNodeRef Yoga layout node
---@field parent Widget|nil Parent widget
---@field children Widget[] Child widgets
---@field props WidgetProps Widget properties
---@field new fun(self, props?: WidgetProps): self Constructor
---@field _virtualListIndex integer|nil VirtualList item index (set by VirtualList)
---@field state table Internal state (for stateful widgets)
---@field id string|nil Optional ID for lookup
---@field _className string Widget class name
---@field absoluteLayout table|nil Override absolute layout {x, y, w, h}
---@field renderOffsetX_ number|nil Render offset X (set by ScrollView)
---@field renderOffsetY_ number|nil Render offset Y (set by ScrollView)
---@field renderWidth_ number|nil Render width override
---@field renderHeight_ number|nil Render height override
---@field bodyChildren_ Widget[]|nil Body children (for Card-like widgets)
---@field borderRadius_ number|nil Border radius
---@field GetScroll fun(self): number, number|nil Get scroll position (ScrollView)
---@field GetHitTestChildren fun(self): Widget[]|nil Get children for hit testing
---@field GetPriorityHitAreas fun(self): table[]|nil Get priority hit areas
---@field CustomRenderChildren fun(self, nvg: NVGContextWrapper, renderFn: function)|nil Custom children render
---@field Update fun(self, dt: number)|nil Update callback (for animated widgets)
---@field AddChild fun(self, child: Widget): self Add child widget (overrides UIElement:AddChild)
---@field RemoveChild fun(self, child: Widget): self Remove child widget (overrides UIElement:RemoveChild)
---@field Remove fun(self): Widget Remove widget from parent (can be re-added later)
---@field Destroy fun(self): nil Destroy widget and release resources
local Widget = {}
Widget.__index = Widget
Widget._className = "Widget"

-- Widget types that can be safely auto-upgraded to ScrollView when overflow="scroll".
-- Only "pure containers" qualify — widgets whose Init() adds no structural logic beyond
-- theme defaults and background rendering. Complex widgets (Card, Tabs, etc.) are excluded
-- because their Init() sets up internal structure that would be lost in the upgrade.
local SCROLL_UPGRADEABLE_ = { Widget = true, Panel = true }

-- ============================================================================
-- Class Inheritance
-- ============================================================================

--- Create a new widget class that extends the receiving class.
--- Derived classes should declare their own class, props, and added fields for strict type checking.
---@generic T
---@param self T Base widget class
---@param name string Class name
---@return T New widget class
function Widget:Extend(name)
    local class = {}
    class.__index = class
    class._className = name
    class._super = self
    setmetatable(class, {
        __index = self,
        __call = function(cls, props)
            return cls:new(props)
        end
    })
    return class
end

-- ============================================================================
-- Setter Map (property routing optimization)
-- ============================================================================

--- Pre-build setter map for a class: { propName = setterFn, ... }
--- Walks the full inheritance chain; subclass setters take priority.
--- Called once per class on first instantiation, shared across all instances.
local function buildSetterMap(class)
    local map = {}
    local current = class
    while current do
        for key, val in pairs(current) do
            if type(val) == "function" and #key > 3 and key:sub(1, 3) == "Set" then
                local prop = key:sub(4, 4):lower() .. key:sub(5)
                if map[prop] == nil then
                    map[prop] = val
                end
            end
        end
        local mt = getmetatable(current)
        current = mt and type(mt.__index) == "table" and mt.__index or nil
    end
    return map
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

--- Create a new widget instance
---@param props WidgetProps? Properties
---@return self
function Widget:new(props)
    props = props or {}

    -- ========================================================================
    -- L0 Defense: overflow="scroll"|"auto" → transparent ScrollView upgrade
    -- ========================================================================
    -- AI models trained on CSS naturally write overflow="scroll" or overflow="auto"
    -- to make containers scrollable. In Yoga, overflow only controls clipping
    -- (visible/hidden/scroll), and "auto" isn't even a valid Yoga value (falls
    -- through to YGOverflowVisible). For simple container types (Panel, Widget),
    -- transparently return a ScrollView instead.
    -- Complex widgets (Card, Tabs, etc.) are excluded to preserve their Init() logic.
    if (props.overflow == "scroll" or props.overflow == "auto")
        and SCROLL_UPGRADEABLE_[self._className] then
        local ScrollView = require("urhox-libs/UI/Widgets/ScrollView")
        local originalClass = self._className or "Widget"
        local originalOverflow = props.overflow
        props.overflow = nil  -- ScrollView.Init sets overflow="hidden" internally
        if props.scrollY == nil then
            props.scrollY = true
        end
        print(string.format(
            '[UI] %s{overflow="%s"} → auto-upgraded to ScrollView. '
            .. "Use UI.ScrollView directly to suppress this message.",
            originalClass, originalOverflow
        ))
        return ScrollView:new(props)
    end

    -- Normalize color prop strings ("#rrggbbaa", "rgba(...)", etc.) once, here,
    -- before any Init()/Build() logic runs. Placed after the ScrollView-upgrade
    -- return above so it never runs twice for the same props table (Style.NormalizeColorProps
    -- is itself idempotent, but this avoids the redundant re-scan on upgrade).
    -- Subclasses that snapshot props.xxxColor before calling Widget.Init — or bare
    -- Widget instances that never call Init at all — now see the converted RGBA
    -- table instead of the raw string.
    Style.NormalizeColorProps(props)

    -- ========================================================================
    -- Transparent Property Routing
    -- ========================================================================
    -- Widget instances support property-style access:
    --   widget.text = "Hello"   →  routes to widget:SetText("Hello")
    --   print(widget.text)      →  reads from widget.props.text
    --
    -- This works via __index/__newindex metatable hooks with naming convention:
    --   prop "foo" → looks for "SetFoo" method on the class
    --   If found: writes route to setter, reads route to self.props
    --   If not found: normal rawset/rawget behavior
    --
    -- IMPORTANT: Basic field initialization happens BEFORE setmetatable,
    -- so constructor assignments (props, state, children, etc.) go through
    -- rawset and are NOT intercepted by __newindex.
    -- ========================================================================

    -- Step 1: Initialize all internal fields BEFORE setting metatable.
    -- These assignments are plain table sets, no __newindex interception.
    local instance = {}
    instance._className = self._className or "Widget"
    instance.props = props
    instance.state = {}
    instance.children = {}
    instance.parent = nil
    instance.id = props.id
    -- Normalize visible to boolean (nil → true, false → false)
    -- Single source of truth: props.visible (consistent with all other props)
    props.visible = props.visible ~= false

    -- Create Yoga node
    instance.node = YGNodeNew()

    -- Transition system fields (compact: empty table = no allocation overhead)
    instance.transitions_ = {}     -- Active transition pool
    instance.renderProps_ = {}     -- Interpolated values for rendering
    instance.transitionConfig_ = nil  -- Parsed transition config (lazy)
    instance.initialized_ = false  -- Suppress transitions during construction
    instance.animation_ = nil      -- Active keyframe animation (nil = none)
    instance.eventListeners_ = nil -- Lazy: created on first OnEvent() call

    -- Step 2: Set metatable with property routing.
    -- From this point on, assignments to instance go through __newindex.
    local class = self

    -- Lazy-build setter map (once per class, shared across all instances).
    -- Maps property names to setter functions: { text = SetText, visible = SetVisible, ... }
    -- Eliminates per-access string operations (sub/upper/concat).
    local setterMap = rawget(class, '_setterMap')
    if not setterMap then
        setterMap = buildSetterMap(class)
        rawset(class, '_setterMap', setterMap)
    end

    -- Lazy-init negative cache (once per class, shared across all instances).
    -- Records keys that are neither methods nor properties → O(1) return nil.
    local noMethod = rawget(class, '_noMethod')
    if not noMethod then
        noMethod = {}
        rawset(class, '_noMethod', noMethod)
    end

    local mt = {
        __index = function(t, key)
            -- 1. Fast path: known non-existent key (no method, no property)
            if noMethod[key] then return nil end

            -- 2. Class lookup (methods, class fields)
            local v = class[key]
            if v ~= nil then
                -- Cache functions on instance: next access is C-level rawget,
                -- bypasses __index entirely.
                if type(v) == "function" then
                    rawset(t, key, v)
                end
                return v
            end

            -- 3. Property read routing (O(1) map lookup, zero string allocation)
            --    e.g. widget.text → props.text (because SetText exists)
            if setterMap[key] then
                return rawget(t, "props")[key]
            end

            -- 4. Not found anywhere → record in negative cache
            noMethod[key] = true
            return nil
        end,

        __newindex = function(t, key, value)
            -- 1. Key exists on instance (construction fields, cached methods)
            --    → direct rawset, never route through setters.
            --    Preserves: self.state = {} → rawset (not SetState merge)
            if rawget(t, key) ~= nil then
                rawset(t, key, value)
                return
            end

            -- 2. Property routing: setter exists → call it directly
            --    e.g. widget.text = "Hello" → SetText(widget, "Hello")
            local setter = setterMap[key]
            if setter then
                setter(t, value)
                return
            end

            -- 3. No matching setter → normal rawset
            rawset(t, key, value)
        end,
    }

    -- Propagate __gc from class to instance metatable (__gc is not
    -- resolved through __index, it must live directly on the metatable).
    if class.__gc then
        mt.__gc = class.__gc
    end

    setmetatable(instance, mt)

    -- Step 3: Init / Build (metatable is active, method calls work normally)

    -- Call Init if subclass overrides it (this will chain to Widget.Init)
    if class.Init ~= Widget.Init then
        instance:Init(props)
    else
        -- No subclass Init override, do base init directly
        instance:ApplyStyleToYoga(props)
        instance:ProcessChildren(props)
    end

    -- Auto-process Build() if subclass implements it
    -- Build() returns an array of child widgets to be added
    -- This enables declarative UI composition (like React/Flutter)
    local hasBuild = instance.Build ~= nil
    local buildDifferent = instance.Build ~= Widget.Build
    if hasBuild and buildDifferent then
        local buildChildren = instance:Build()
        if buildChildren then
            for _, child in ipairs(buildChildren) do
                if child then
                    instance:AddChild(child)
                end
            end
        end
    end

    -- Parse transition config from initial props (lazy)
    if props.transition then
        instance.transitionConfig_ = Transition.ParseConfig(props.transition)
    end

    -- Mark as initialized: from now on, SetStyle changes may trigger transitions
    instance.initialized_ = true

    return instance
end

--- Build child widgets (override in subclasses for declarative composition)
--- Return an array of child widgets to be automatically added.
--- This is called after Init() during widget construction.
---
--- Usage:
---   function MyWidget:Build()
---       return {
---           UI.Panel { ... },
---           UI.Label { text = "Hello" },
---       }
---   end
---
---@return Widget[]|nil Array of child widgets, or nil
function Widget:Build()
    return nil
end

--- Expand borderWidth table shorthand into per-side properties.
--- Supports named keys: { top=N, bottom=N, left=N, right=N, horizontal=N, vertical=N }
--- CSS array shorthand: {all}, {vert, horiz}, {top, horiz, bottom}, {top, right, bottom, left}
---@param style table Props or style table to expand in-place
local function expandBorderWidthTable(style)
    local bw = style.borderWidth
    if type(bw) ~= "table" then return end

    -- CSS array shorthand
    if #bw > 0 then
        if #bw == 1 then
            style.borderTopWidth = style.borderTopWidth or bw[1]
            style.borderRightWidth = style.borderRightWidth or bw[1]
            style.borderBottomWidth = style.borderBottomWidth or bw[1]
            style.borderLeftWidth = style.borderLeftWidth or bw[1]
        elseif #bw == 2 then
            style.borderTopWidth = style.borderTopWidth or bw[1]
            style.borderBottomWidth = style.borderBottomWidth or bw[1]
            style.borderRightWidth = style.borderRightWidth or bw[2]
            style.borderLeftWidth = style.borderLeftWidth or bw[2]
        elseif #bw == 3 then
            style.borderTopWidth = style.borderTopWidth or bw[1]
            style.borderRightWidth = style.borderRightWidth or bw[2]
            style.borderLeftWidth = style.borderLeftWidth or bw[2]
            style.borderBottomWidth = style.borderBottomWidth or bw[3]
        elseif #bw >= 4 then
            style.borderTopWidth = style.borderTopWidth or bw[1]
            style.borderRightWidth = style.borderRightWidth or bw[2]
            style.borderBottomWidth = style.borderBottomWidth or bw[3]
            style.borderLeftWidth = style.borderLeftWidth or bw[4]
        end
    end

    -- Named keys (override array values)
    if bw.top then style.borderTopWidth = bw.top end
    if bw.right then style.borderRightWidth = bw.right end
    if bw.bottom then style.borderBottomWidth = bw.bottom end
    if bw.left then style.borderLeftWidth = bw.left end
    if bw.horizontal then
        style.borderLeftWidth = style.borderLeftWidth or bw.horizontal
        style.borderRightWidth = style.borderRightWidth or bw.horizontal
    end
    if bw.vertical then
        style.borderTopWidth = style.borderTopWidth or bw.vertical
        style.borderBottomWidth = style.borderBottomWidth or bw.vertical
    end

    -- Clear the table value — per-side props now hold the data
    style.borderWidth = nil
end

--- Expand padding shorthand into per-side properties (paddingTop/Right/Bottom/Left).
--- Handles: padding (number/string/table), paddingHorizontal, paddingVertical.
--- Priority matches Yoga's internal resolution: per-side > axis > all.
--- Must process highest priority first so `or` preserves existing values.
---@param style table Props or style table to expand in-place
local function expandPaddingShorthand(style)
    -- Step 1: Expand paddingHorizontal/paddingVertical (medium priority)
    -- Process before padding (lowest priority) so their values take precedence.
    if style.paddingHorizontal ~= nil then
        style.paddingLeft = style.paddingLeft or style.paddingHorizontal
        style.paddingRight = style.paddingRight or style.paddingHorizontal
        style.paddingHorizontal = nil
    end
    if style.paddingVertical ~= nil then
        style.paddingTop = style.paddingTop or style.paddingVertical
        style.paddingBottom = style.paddingBottom or style.paddingVertical
        style.paddingVertical = nil
    end

    -- Step 2: Expand padding shorthand (lowest priority)
    local p = style.padding
    if p == nil then return end

    if type(p) == "table" then
        -- Resolve CSS array shorthand within the table
        local top, right, bottom, left
        if #p == 1 then
            top, right, bottom, left = p[1], p[1], p[1], p[1]
        elseif #p == 2 then
            top, bottom = p[1], p[1]
            right, left = p[2], p[2]
        elseif #p == 3 then
            top = p[1]
            right, left = p[2], p[2]
            bottom = p[3]
        elseif #p >= 4 then
            top, right, bottom, left = p[1], p[2], p[3], p[4]
        end
        -- Named keys override array values (within the table's own scope)
        if p.vertical then top, bottom = p.vertical, p.vertical end
        if p.horizontal then right, left = p.horizontal, p.horizontal end
        if p.top then top = p.top end
        if p.right then right = p.right end
        if p.bottom then bottom = p.bottom end
        if p.left then left = p.left end
        -- Apply to per-side props (don't override existing higher-priority values)
        if top ~= nil then style.paddingTop = style.paddingTop or top end
        if right ~= nil then style.paddingRight = style.paddingRight or right end
        if bottom ~= nil then style.paddingBottom = style.paddingBottom or bottom end
        if left ~= nil then style.paddingLeft = style.paddingLeft or left end
    elseif type(p) == "number" or type(p) == "string" then
        -- number or "N%" — expand to four per-side values
        style.paddingTop = style.paddingTop or p
        style.paddingRight = style.paddingRight or p
        style.paddingBottom = style.paddingBottom or p
        style.paddingLeft = style.paddingLeft or p
    end

    -- Clear the shorthand — per-side props now hold the data
    style.padding = nil
end

--- Base initialization (called by subclasses via Widget.Init(self, props))
---@param props WidgetProps Properties
function Widget:Init(props)
    -- Idempotent second pass: Widget:new() already normalized props before Init
    -- ran, but subclasses may add their own *Color fields to props inside their
    -- own Init (e.g. via theme defaults) before calling Widget.Init(self, props).
    Style.NormalizeColorProps(props)

    -- Expand borderWidth table shorthand into per-side properties
    expandBorderWidthTable(props)

    -- Expand padding shorthand into per-side properties
    expandPaddingShorthand(props)

    -- Apply style from props
    self:ApplyStyleToYoga(props)

    -- Process children
    self:ProcessChildren(props)

    -- Decoration: minimal Widget subclass that triggers full Init path
    -- (plain Widget(d) skips Init when class.Init == Widget.Init, see :new() line 451)
    if not Widget._Decoration then
        Widget._Decoration = Widget:Extend("Decoration")
        function Widget._Decoration:Init(props)
            Widget.Init(self, props)
        end
    end

    -- Theme-injected decorations: auto-create child widgets from theme config
    -- Supports two formats:
    --   Array: decorations = { {props1}, {props2} }  -- all variants
    --   Table: decorations = { primary = { {props1} }, danger = { {props2} } }  -- per-variant
    -- Each decoration can have state colors: hoverBackgroundColor, pressedBackgroundColor
    if props.decorations then
        local decorList = props.decorations
        -- Check if keyed by variant (first key is not a number)
        if decorList[1] == nil and props.variant then
            decorList = decorList[props.variant] or {}
        end
        self.decorations_ = {}
        for _, decor in ipairs(decorList) do
            -- Shallow copy to avoid mutating shared theme config
            local d = {}
            for k, v in pairs(decor) do d[k] = v end
            -- deriveBorderColor(props): theme-defined function that derives decoration
            -- border colors from parent props. The function decides which props to read
            -- (backgroundColor, backgroundGradient, etc.) and returns {borderColor,
            -- hoverBorderColor, pressedBorderColor} or nil to keep static values.
            local deriveFn = d.deriveBorderColor
            if deriveFn then
                local derived = deriveFn(props)
                if derived then
                    d.borderColor = derived.borderColor or d.borderColor
                    d.hoverBorderColor = derived.hoverBorderColor or d.hoverBorderColor
                    d.pressedBorderColor = derived.pressedBorderColor or d.pressedBorderColor
                end
            end
            d.deriveBorderColor = nil  -- consumed, not a widget prop
            -- Extract state colors before creating widget
            local stateColors = nil
            if d.hoverBackgroundColor or d.pressedBackgroundColor
                or d.hoverBorderColor or d.pressedBorderColor then
                stateColors = {
                    default = d.backgroundColor,
                    hover = d.hoverBackgroundColor,
                    pressed = d.pressedBackgroundColor,
                    defaultBorder = d.borderColor,
                    hoverBorder = d.hoverBorderColor,
                    pressedBorder = d.pressedBorderColor,
                }
                d.hoverBackgroundColor = nil
                d.pressedBackgroundColor = nil
                d.hoverBorderColor = nil
                d.pressedBorderColor = nil
            end
            d.pointerEvents = "none"
            d.position = d.position or "absolute"
            local child = Widget._Decoration(d)
            child.isThemeDecoration_ = true
            if stateColors then
                child._decorStateColors = stateColors
            end
            self.decorations_[#self.decorations_ + 1] = child
            self:AddChild(child)
        end
        props.decorations = nil  -- consumed, don't persist
    end
end

--- Update decoration children's appearance based on parent state.
--- Call from Render() of stateful widgets (Button, Toggle, etc.)
---@param stateName string "default" | "hover" | "pressed" | "disabled"
function Widget:UpdateDecorationState(stateName)
    if not self.decorations_ then return end
    for _, child in ipairs(self.decorations_) do
        if stateName == "disabled" then
            child:SetVisible(false)
        else
            child:SetVisible(true)
            if child._decorStateColors then
                -- Unconditional assignment: nil clears the previous value,
                -- preventing stale hover/pressed colors from lingering.
                child.props.backgroundColor = child._decorStateColors[stateName] or child._decorStateColors.default
                local borderKey = stateName .. "Border"
                child.props.borderColor = child._decorStateColors[borderKey] or child._decorStateColors.defaultBorder
            end
        end
    end
end

--- Process children from props
---@param props WidgetProps Properties
function Widget:ProcessChildren(props)
    -- Process children from props.children
    if props.children then
        for i, child in ipairs(props.children) do
            self:AddChild(child)
        end
    end

    -- Also process array part of props as children
    for i = 1, #props do
        if props[i] then
            self:AddChild(props[i])
        end
    end
end

--- Destroy widget and release resources
function Widget:Destroy()
    -- Cancel all active transitions/animations and unregister from update loop
    local hadActive = #self.transitions_ > 0 or (self.animation_ and self.animation_.active)
    if #self.transitions_ > 0 then
        Transition.CancelAll(self.transitions_)
    end
    self.animation_ = nil
    if hadActive and onTransitionEnd_ then
        onTransitionEnd_(self)
    end

    -- Destroy children first
    for i = #self.children, 1, -1 do
        self.children[i]:Destroy()
    end
    self.children = {}

    -- Remove from parent
    if self.parent then
        self.parent:RemoveChild(self)
    end

    -- Free Yoga node
    if self.node then
        YGNodeFree(self.node)
        self.node = nil
    end
end

--- Remove widget from parent (can be re-added to another parent later)
---@return Widget self for chaining
function Widget:Remove()
    if self.parent then
        self.parent:RemoveChild(self)
    end
    return self
end

-- ============================================================================
-- Visibility
-- ============================================================================

--- Check if widget is visible
---@return boolean
function Widget:IsVisible()
    return self.props.visible ~= false
end

--- Set widget visibility
---@param visible boolean
---@return Widget self for chaining
function Widget:SetVisible(visible)
    if self.props.visible == visible then return self end  -- no-op guard
    self.props.visible = visible
    -- Sync with Yoga: invisible widgets should not occupy layout space
    if self.node then
        YGNodeStyleSetDisplay(self.node, visible and YGDisplayFlex or YGDisplayNone)
    end
    if onLayoutDirty_ then onLayoutDirty_() end
    return self
end

--- Show widget
---@return Widget self for chaining
function Widget:Show()
    return self:SetVisible(true)
end

--- Hide widget
---@return Widget self for chaining
function Widget:Hide()
    return self:SetVisible(false)
end

-- ============================================================================
-- Transition System
-- ============================================================================

--- Update active transitions. Called by UI.lua for widgets with active transitions.
---@param dt number Delta time in seconds
function Widget:BaseUpdate(dt)
    local hasTransitions = false
    local hasAnimation = false

    -- Update property transitions
    local pool = self.transitions_
    if #pool > 0 then
        hasTransitions = Transition.Update(pool, dt)
        -- Copy interpolated values to renderProps_ for rendering
        for i = 1, #pool do
            local entry = pool[i]
            self.renderProps_[entry[1]] = entry[8]  -- [1]=prop name, [8]=current value
        end
    end

    -- Update keyframe animation
    local anim = self.animation_
    if anim and anim.active then
        local interpolated = Transition.UpdateKeyframeAnimation(anim, dt)
        if interpolated then
            -- Write interpolated keyframe values to renderProps_
            for k, v in pairs(interpolated) do
                self.renderProps_[k] = v
            end
            hasAnimation = true
        end
        if not anim.active then
            -- fillMode "forwards" or "both": persist final values to props
            local fm = anim.fillMode
            if (fm == "forwards" or fm == "both") and interpolated then
                for k, v in pairs(interpolated) do
                    self.props[k] = v
                end
            end
            -- Animation finished: clear reference
            self.animation_ = nil
        end
    end

    if not hasTransitions and not hasAnimation then
        -- All transitions/animations completed: clean up renderProps_
        for k in pairs(self.renderProps_) do
            self.renderProps_[k] = nil
        end
        -- Notify UI.lua to stop tracking this widget
        if onTransitionEnd_ then
            onTransitionEnd_(self)
        end
    end
end

--- Get the current render value for a property.
--- Returns the interpolated transition value if a transition is active,
--- otherwise falls back to the prop value.
---@param propName string Property name
---@return any Current value for rendering
function Widget:GetRenderProp(propName)
    local rv = self.renderProps_[propName]
    if rv ~= nil then return rv end
    return self.props[propName]
end

--- Check if this widget has any active transitions or animations
---@return boolean
function Widget:HasActiveTransitions()
    return #self.transitions_ > 0 or (self.animation_ ~= nil and self.animation_.active)
end

--- Set transition system callbacks (called by UI.lua)
---@param onStart function(widget) Called when a widget starts its first transition
---@param onEnd function(widget) Called when all transitions on a widget complete
function Widget.SetTransitionCallbacks(onStart, onEnd)
    onTransitionStart_ = onStart
    onTransitionEnd_ = onEnd
end

--- Get the onTransitionStart callback.
--- Used by subclasses (e.g. Button) that start transitions directly via Transition.Start()
--- instead of going through SetStyle(), so they can notify UI.lua for tracking.
---@return function|nil
function Widget.GetTransitionStartCallback()
    return onTransitionStart_
end

-- ============================================================================
-- Keyframe Animation
-- ============================================================================

--- Start a keyframe animation on this widget.
--- Animates multiple properties through keyframe stops over a duration.
--- Keyframe values are written to renderProps_ and take priority over transitions.
---
--- Example:
---   widget:Animate({
---       keyframes = {
---           [0]   = { opacity = 0, translateY = 20 },
---           [0.5] = { opacity = 1, translateY = 5 },
---           [1]   = { opacity = 1, translateY = 0 },
---       },
---       duration = 0.5,
---       easing = "easeOut",
---       loop = true,
---       direction = "alternate",
---       onComplete = function() end,
---   })
---
---@param config table Animation config { keyframes, duration, easing, loop, direction, fillMode, onComplete }
---@return Widget self for chaining
function Widget:Animate(config)
    if not config or not config.keyframes then return self end

    -- Stop any existing animation
    self.animation_ = nil

    -- Create the keyframe animation
    self.animation_ = Transition.CreateKeyframeAnimation(config)

    -- fillMode "backwards" or "both": apply first keyframe to renderProps_ immediately
    -- (prevents one-frame flash of prop values before first BaseUpdate)
    local fm = self.animation_.fillMode
    if fm == "backwards" or fm == "both" then
        local initT = (self.animation_.direction == "reverse") and 1 or 0
        local firstFrame = Transition.InterpolateKeyframes(self.animation_.keyframes, initT)
        if firstFrame then
            for k, v in pairs(firstFrame) do
                self.renderProps_[k] = v
            end
        end
    end

    -- Register with UI.lua for update tracking (same mechanism as transitions)
    if onTransitionStart_ then
        onTransitionStart_(self)
    end

    return self
end

--- Stop the current keyframe animation.
--- Clears renderProps_ for animated properties (snaps to current prop values).
---@return Widget self for chaining
function Widget:StopAnimation()
    if self.animation_ then
        self.animation_.active = false
        self.animation_ = nil

        -- If no transitions either, clean up and unregister
        if #self.transitions_ == 0 then
            for k in pairs(self.renderProps_) do
                self.renderProps_[k] = nil
            end
            if onTransitionEnd_ then
                onTransitionEnd_(self)
            end
        end
    end
    return self
end

-- ============================================================================
-- Child Management
-- ============================================================================

-- ====================================================================
-- Internal: auto-fix maxHeight/maxWidth parent when flexGrow+flexBasis=0 child is added
-- ====================================================================
-- When a child with flexGrow + flexBasis=0 is added to a parent that has
-- maxHeight/maxWidth but no explicit height/width on the MAIN axis, Yoga
-- can't distribute flex space (parent size is indefinite).
-- Fix: convert maxHeight→height (column) or maxWidth→width (row).
--
-- Direction-aware: only fixes the main axis.
-- - column/column-reverse: flexGrow distributes height → fix maxHeight
-- - row/row-reverse: flexGrow distributes width → fix maxWidth
-- Cross-axis max* is left untouched (it doesn't block flex distribution).
--
-- Trade-off: parent always occupies its max size (no longer auto-shrinks).
-- This is acceptable: "always at max size" >> "content invisible (zero size)".
local function autoFixMaxSizeParent(parent, child)
    if not child.props then return end
    -- flex is a shorthand: flex=1 → flexGrow=1, flexShrink=1, flexBasis=0 in Yoga.
    -- But in Lua props, only props.flex is set (flexGrow/flexBasis stay nil).
    -- Must check both props.flexGrow and props.flex.
    local hasFlexGrow = (child.props.flexGrow and child.props.flexGrow > 0)
                     or (child.props.flex and child.props.flex > 0)
    if not hasFlexGrow then return end
    -- flex=N implies flexBasis=0 at Yoga level, so treat it as flexBasis==0
    local hasFlexBasis0 = child.props.flexBasis == 0
                       or (child.props.flex and child.props.flex > 0 and child.props.flexBasis == nil)
    if not hasFlexBasis0 then return end

    -- Determine main axis from parent's flexDirection (default: column)
    local dir = parent.props.flexDirection or "column"
    local isVertical = (dir == "column" or dir == "column-reverse")

    local maxProp, sizeProp, setPercent, setAbsolute
    if isVertical then
        maxProp = "maxHeight"
        sizeProp = "height"
        setPercent = YGNodeStyleSetHeightPercent
        setAbsolute = YGNodeStyleSetHeight
    else
        maxProp = "maxWidth"
        sizeProp = "width"
        setPercent = YGNodeStyleSetWidthPercent
        setAbsolute = YGNodeStyleSetWidth
    end

    -- Only fix if parent has max* but no explicit size on the main axis
    if not parent.props[maxProp] then return end
    if parent.props[sizeProp] then return end

    local maxVal = parent.props[maxProp]
    parent.props[sizeProp] = maxVal

    -- Apply to Yoga node immediately
    if type(maxVal) == "string" and maxVal:match("%%$") then
        setPercent(parent.node, tonumber(maxVal:match("([%d%.]+)")) or 100)
    elseif maxVal == "auto" then
        -- max*="auto" is a no-op, don't convert
        parent.props[sizeProp] = nil
    else
        setAbsolute(parent.node, maxVal)
    end

    -- Keep max* as-is (redundant but harmless; Yoga has no "unset" API)
    if parent.props[sizeProp] then
        local flexVal = child.props.flexGrow or child.props.flex or 0
        print(string.format(
            "[UI] Auto-fix: '%s' %s=%s → %s=%s "
            .. "(child '%s' has flex/flexGrow=%g + flexBasis=0, needs parent with definite size). "
            .. "Set %s explicitly to suppress.",
            parent.props.id or parent._className or "parent",
            maxProp, tostring(maxVal), sizeProp, tostring(maxVal),
            child.props.id or child._className or "child",
            flexVal,
            sizeProp
        ))
    end
end

--- Add a child widget
---@param child Widget
---@return Widget self for chaining
function Widget:AddChild(child)
    if not child then return self end

    -- Type check: must be a Widget object
    local childType = type(child)
    if childType ~= "table" or not child.Render then
        local hint = childType == "table" and " (table without Render method - did you forget table.unpack(children)?)" or ""
        error("Widget:AddChild() expects a Widget object, got " .. childType .. hint, 2)
    end

    -- Remove from previous parent
    if child.parent then
        child.parent:RemoveChild(child)
    end

    -- Add to children array
    table.insert(self.children, child)
    child.parent = self

    -- Source tracking for UI Inspector
    -- Record where this widget was added to the tree (user code location)
    if UI_INSPECTOR_ENABLED then
        for level = 2, 10 do
            local info = debug.getinfo(level, "Sl")
            if not info then break end
            local src = info.source or ""
            if not src:find("urhox%-libs/UI/Core/", 1, false)
               and not src:find("urhox%-libs/UI/Widgets/", 1, false)
               and not src:find("^%[") and not src:find("^=") then
                child._sourceFile = src:sub(1, 1) == "@" and src:sub(2) or src
                child._sourceLine = info.currentline
                break
            end
        end
    end

    -- Add to Yoga tree
    YGNodeInsertChild(self.node, child.node, #self.children - 1)

    -- Auto-fix maxHeight parent for flex distribution
    autoFixMaxSizeParent(self, child)

    -- Invalidate z-index sort cache:
    -- Must re-sort if new child has zIndex, OR if cache exists (new child missing from cache)
    if child.props.zIndex or self.sortedChildren_ then
        self.needsZSort_ = true
    end

    -- Notify layout system
    if onLayoutDirty_ then onLayoutDirty_() end

    return self
end

--- Remove a child widget
---@param child Widget
---@return Widget self for chaining
function Widget:RemoveChild(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            self:ClearChildOverrides(child)
            YGNodeRemoveChild(self.node, child.node)
            -- Invalidate z-index sort cache
            if self.sortedChildren_ then
                self.needsZSort_ = true
            end
            -- Notify layout system
            if onLayoutDirty_ then onLayoutDirty_() end
            break
        end
    end
    return self
end

--- Insert a child widget at specific index
---@param child Widget
---@param index number 1-based index
---@return Widget self for chaining
function Widget:InsertChild(child, index)
    -- Type check: must be a Widget object
    local childType = type(child)
    if childType ~= "table" or not child.Render then
        local hint = childType == "table" and " (table without Render method - did you forget table.unpack(children)?)" or ""
        error("Widget:InsertChild() expects a Widget object, got " .. childType .. hint, 2)
    end

    -- Remove from previous parent (same as AddChild)
    if child.parent then
        child.parent:RemoveChild(child)
    end

    index = math.max(1, math.min(index, #self.children + 1))
    table.insert(self.children, index, child)
    child.parent = self

    -- Add to Yoga tree at correct position (0-based)
    YGNodeInsertChild(self.node, child.node, index - 1)

    -- Auto-fix maxHeight parent for flex distribution
    autoFixMaxSizeParent(self, child)

    -- Invalidate z-index sort cache:
    -- Must re-sort if new child has zIndex, OR if cache exists (new child missing from cache)
    if child.props.zIndex or self.sortedChildren_ then
        self.needsZSort_ = true
    end

    -- Notify layout system
    if onLayoutDirty_ then onLayoutDirty_() end

    return self
end

--- Remove all children
---@return Widget self for chaining
function Widget:ClearChildren()
    if #self.children == 0 then return self end

    for i = #self.children, 1, -1 do
        local child = self.children[i]
        child.parent = nil
        YGNodeRemoveChild(self.node, child.node)
        table.remove(self.children, i)
    end
    -- Parent-set per-child overrides are meaningless once all children are gone.
    self.childOverrides_ = nil

    -- Notify layout system
    if onLayoutDirty_ then onLayoutDirty_() end

    return self
end

--- Alias for ClearChildren
Widget.RemoveAllChildren = Widget.ClearChildren

-- ============================================================================
-- Per-child overrides
-- A parent stores field overrides for specific children, keyed by the child
-- object. The child's own props are never touched; the child pulls values via
-- GetParentOverride. Removing the child (RemoveChild/ClearChildren) drops the
-- override automatically, so nothing leaks when a widget is reused elsewhere.
-- ============================================================================

--- Set (or clear, when value is nil) one field override a parent applies to a child.
---@param child Widget
---@param field string
---@param value any|nil
function Widget:SetChildOverride(child, field, value)
    if not child then return end
    local all = self.childOverrides_
    if not all then
        if value == nil then return end
        all = {}
        self.childOverrides_ = all
    end
    local entry = all[child]
    if not entry then
        if value == nil then return end
        entry = {}
        all[child] = entry
    end
    entry[field] = value
    -- Reclaim an emptied entry so GetParentOverride falls through cleanly.
    if value == nil and next(entry) == nil then
        all[child] = nil
    end
end

--- Drop every override this parent set on a child (called on detach).
---@param child Widget
function Widget:ClearChildOverrides(child)
    if self.childOverrides_ then
        self.childOverrides_[child] = nil
    end
end

--- Apply the overrides an ancestor set for this widget onto props.
--- Without a field: returns a copy of props with all overrides applied, or props
---   unchanged when there is no override.
--- With a field: returns that field's override value (or nil).
--- deep=false (default): only the direct parent. deep=true: resolve up the whole
---   parent chain; when the same field is set at multiple levels the OUTERMOST
---   ancestor wins. Overrides are keyed by direct child, so multi-level follows the path node.
---@param props table
---@param field string|nil
---@param deep boolean|nil
---@return any
function Widget:GetParentOverride(props, field, deep)
    -- Resolve the effective override table for this widget.
    local ov
    if not deep then
        local p = self.parent
        ov = p and p.childOverrides_ and p.childOverrides_[self]
    else
        -- Merge every level inner→outer so the outermost level overwrites.
        local node, p = self, self.parent
        local first, merged = nil, nil
        while p do
            local entry = p.childOverrides_ and p.childOverrides_[node]
            if entry then
                if merged then
                    for k, v in pairs(entry) do merged[k] = v end
                elseif first then
                    merged = {}
                    for k, v in pairs(first) do merged[k] = v end
                    for k, v in pairs(entry) do merged[k] = v end
                else
                    first = entry
                end
            end
            node, p = p, p.parent
        end
        ov = merged or first
    end

    if field ~= nil then
        if ov then return ov[field] end
        return nil
    end

    if not ov then return props end
    local out = {}
    for k, v in pairs(props) do out[k] = v end
    for k, v in pairs(ov) do out[k] = v end
    return out
end

--- Find child by ID recursively
---@param id string
---@return Widget|any|nil 使用 --[[@as T?]] 精确指定返回类型
function Widget:FindById(id)
    if self.id == id then
        return self
    end
    for _, child in ipairs(self.children) do
        local found = child:FindById(id)
        if found then
            return found
        end
    end
    return nil
end

--- Get number of children
---@return number
function Widget:GetNumChildren()
    return #self.children
end

--- Get child at index (1-based)
---@param index number 1-based index
---@return Widget|nil
function Widget:GetChildAt(index)
    return self.children[index]
end

--- Get children array (returns the internal table directly, do not modify)
---@return Widget[]
function Widget:GetChildren()
    return self.children
end

-- ============================================================================
-- Style & Layout
-- ============================================================================

--- Apply a single margin value (handles number, percentage string, and "auto")
--- Warns on invalid value types (aligned with project "proactive feedback" principle)
---@param node YGNodeRef
---@param edge number YGEdge constant
---@param value number|string The margin value
local function applyMarginValue(node, edge, value)
    if value == "auto" then
        YGNodeStyleSetMarginAuto(node, edge)
    elseif type(value) == "string" and value:match("%%$") then
        YGNodeStyleSetMarginPercent(node, edge, tonumber(value:match("([%d%.]+)")) or 0)
    elseif type(value) == "number" then
        YGNodeStyleSetMargin(node, edge, value)
    else
        print("[UI Warning] Invalid margin value: " .. tostring(value) .. " (" .. type(value) .. "). Expected number, \"N%\", or \"auto\".")
    end
end

--- Apply style properties to Yoga node
--- All values are in base pixels (Yoga works in base pixel space)
---@param style table
function Widget:ApplyStyleToYoga(style)
    if not style or not self.node then return end

    local node = self.node

    -- Size
    local width = style.width
    if width then
        if type(width) == "string" and width:match("%%$") then
            YGNodeStyleSetWidthPercent(node, tonumber(width:match("([%d%.]+)")) or 100)
        elseif width == "auto" then
            YGNodeStyleSetWidthAuto(node)
        else
            YGNodeStyleSetWidth(node, width)
        end
    end
    local height = style.height
    if height then
        if type(height) == "string" and height:match("%%$") then
            YGNodeStyleSetHeightPercent(node, tonumber(height:match("([%d%.]+)")) or 100)
        elseif height == "auto" then
            YGNodeStyleSetHeightAuto(node)
        else
            YGNodeStyleSetHeight(node, height)
        end
    end
    if style.minWidth ~= nil then
        if style.minWidth == "max-content" then
            YGNodeStyleSetMinWidthMaxContent(node)
        elseif style.minWidth == "fit-content" then
            YGNodeStyleSetMinWidthFitContent(node)
        elseif style.minWidth == "stretch" then
            YGNodeStyleSetMinWidthStretch(node)
        elseif type(style.minWidth) == "string" and style.minWidth:match("%%$") then
            YGNodeStyleSetMinWidthPercent(node, tonumber(style.minWidth:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMinWidth(node, style.minWidth)
        end
    end
    if style.maxWidth ~= nil then
        if style.maxWidth == "max-content" then
            YGNodeStyleSetMaxWidthMaxContent(node)
        elseif style.maxWidth == "fit-content" then
            YGNodeStyleSetMaxWidthFitContent(node)
        elseif style.maxWidth == "stretch" then
            YGNodeStyleSetMaxWidthStretch(node)
        elseif type(style.maxWidth) == "string" and style.maxWidth:match("%%$") then
            YGNodeStyleSetMaxWidthPercent(node, tonumber(style.maxWidth:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMaxWidth(node, style.maxWidth)
        end
    end
    if style.minHeight ~= nil then
        if style.minHeight == "max-content" then
            YGNodeStyleSetMinHeightMaxContent(node)
        elseif style.minHeight == "fit-content" then
            YGNodeStyleSetMinHeightFitContent(node)
        elseif style.minHeight == "stretch" then
            YGNodeStyleSetMinHeightStretch(node)
        elseif type(style.minHeight) == "string" and style.minHeight:match("%%$") then
            YGNodeStyleSetMinHeightPercent(node, tonumber(style.minHeight:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMinHeight(node, style.minHeight)
        end
    end
    if style.maxHeight ~= nil then
        if style.maxHeight == "max-content" then
            YGNodeStyleSetMaxHeightMaxContent(node)
        elseif style.maxHeight == "fit-content" then
            YGNodeStyleSetMaxHeightFitContent(node)
        elseif style.maxHeight == "stretch" then
            YGNodeStyleSetMaxHeightStretch(node)
        elseif type(style.maxHeight) == "string" and style.maxHeight:match("%%$") then
            YGNodeStyleSetMaxHeightPercent(node, tonumber(style.maxHeight:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMaxHeight(node, style.maxHeight)
        end
    end

    -- Flex direction
    if style.flexDirection then
        YGNodeStyleSetFlexDirection(node, Style.FlexDirectionToYoga(style.flexDirection))
    end

    -- Justify content
    if style.justifyContent then
        YGNodeStyleSetJustifyContent(node, Style.JustifyContentToYoga(style.justifyContent))
    end

    -- Align items
    if style.alignItems then
        YGNodeStyleSetAlignItems(node, Style.AlignItemsToYoga(style.alignItems))
    end

    -- Align self
    if style.alignSelf then
        YGNodeStyleSetAlignSelf(node, Style.AlignSelfToYoga(style.alignSelf))
    end

    -- Align content (default to stretch like CSS, only affects flexWrap multiline)
    YGNodeStyleSetAlignContent(node, Style.AlignContentToYoga(style.alignContent or "stretch"))

    -- Flex properties
    if style.flexWrap then
        YGNodeStyleSetFlexWrap(node, Style.WrapToYoga(style.flexWrap))
    end
    if style.flexGrow ~= nil then YGNodeStyleSetFlexGrow(node, style.flexGrow) end
    if style.flexShrink ~= nil then YGNodeStyleSetFlexShrink(node, style.flexShrink) end
    if style.flexBasis ~= nil then
        if style.flexBasis == "auto" then
            YGNodeStyleSetFlexBasisAuto(node)
        elseif style.flexBasis == "max-content" then
            YGNodeStyleSetFlexBasisMaxContent(node)
        elseif style.flexBasis == "fit-content" then
            YGNodeStyleSetFlexBasisFitContent(node)
        elseif style.flexBasis == "stretch" then
            YGNodeStyleSetFlexBasisStretch(node)
        elseif type(style.flexBasis) == "string" and style.flexBasis:match("%%$") then
            YGNodeStyleSetFlexBasisPercent(node, tonumber(style.flexBasis:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetFlexBasis(node, style.flexBasis)
        end
    end
    if style.flex ~= nil then YGNodeStyleSetFlex(node, style.flex) end

    -- Gap
    if style.gap then
        if type(style.gap) == "string" and style.gap:match("%%$") then
            YGNodeStyleSetGapPercent(node, YGGutterAll, tonumber(style.gap:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetGap(node, YGGutterAll, style.gap)
        end
    end
    if style.rowGap then
        if type(style.rowGap) == "string" and style.rowGap:match("%%$") then
            YGNodeStyleSetGapPercent(node, YGGutterRow, tonumber(style.rowGap:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetGap(node, YGGutterRow, style.rowGap)
        end
    end
    if style.columnGap then
        if type(style.columnGap) == "string" and style.columnGap:match("%%$") then
            YGNodeStyleSetGapPercent(node, YGGutterColumn, tonumber(style.columnGap:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetGap(node, YGGutterColumn, style.columnGap)
        end
    end

    -- Margin
    if style.margin then
        if type(style.margin) == "table" then
            local m = style.margin
            -- CSS array shorthand: {all}, {vert, horiz}, {top, horiz, bottom}, {top, right, bottom, left}
            if #m > 0 then
                if #m == 1 then
                    applyMarginValue(node, YGEdgeAll, m[1])
                elseif #m == 2 then
                    applyMarginValue(node, YGEdgeVertical, m[1])
                    applyMarginValue(node, YGEdgeHorizontal, m[2])
                elseif #m == 3 then
                    applyMarginValue(node, YGEdgeTop, m[1])
                    applyMarginValue(node, YGEdgeHorizontal, m[2])
                    applyMarginValue(node, YGEdgeBottom, m[3])
                elseif #m >= 4 then
                    applyMarginValue(node, YGEdgeTop, m[1])
                    applyMarginValue(node, YGEdgeRight, m[2])
                    applyMarginValue(node, YGEdgeBottom, m[3])
                    applyMarginValue(node, YGEdgeLeft, m[4])
                end
            end
            -- Named keys (can coexist with or override array values)
            if m.top then applyMarginValue(node, YGEdgeTop, m.top) end
            if m.right then applyMarginValue(node, YGEdgeRight, m.right) end
            if m.bottom then applyMarginValue(node, YGEdgeBottom, m.bottom) end
            if m.left then applyMarginValue(node, YGEdgeLeft, m.left) end
            if m.horizontal then applyMarginValue(node, YGEdgeHorizontal, m.horizontal) end
            if m.vertical then applyMarginValue(node, YGEdgeVertical, m.vertical) end
        elseif style.margin == "auto" then
            YGNodeStyleSetMarginAuto(node, YGEdgeAll)
        elseif type(style.margin) == "string" and style.margin:match("%%$") then
            YGNodeStyleSetMarginPercent(node, YGEdgeAll, tonumber(style.margin:match("([%d%.]+)")) or 0)
        elseif type(style.margin) == "number" then
            YGNodeStyleSetMargin(node, YGEdgeAll, style.margin)
        end
    end
    if style.marginTop then
        if style.marginTop == "auto" then
            YGNodeStyleSetMarginAuto(node, YGEdgeTop)
        elseif type(style.marginTop) == "string" and style.marginTop:match("%%$") then
            YGNodeStyleSetMarginPercent(node, YGEdgeTop, tonumber(style.marginTop:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMargin(node, YGEdgeTop, style.marginTop)
        end
    end
    if style.marginRight then
        if style.marginRight == "auto" then
            YGNodeStyleSetMarginAuto(node, YGEdgeRight)
        elseif type(style.marginRight) == "string" and style.marginRight:match("%%$") then
            YGNodeStyleSetMarginPercent(node, YGEdgeRight, tonumber(style.marginRight:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMargin(node, YGEdgeRight, style.marginRight)
        end
    end
    if style.marginBottom then
        if style.marginBottom == "auto" then
            YGNodeStyleSetMarginAuto(node, YGEdgeBottom)
        elseif type(style.marginBottom) == "string" and style.marginBottom:match("%%$") then
            YGNodeStyleSetMarginPercent(node, YGEdgeBottom, tonumber(style.marginBottom:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMargin(node, YGEdgeBottom, style.marginBottom)
        end
    end
    if style.marginLeft then
        if style.marginLeft == "auto" then
            YGNodeStyleSetMarginAuto(node, YGEdgeLeft)
        elseif type(style.marginLeft) == "string" and style.marginLeft:match("%%$") then
            YGNodeStyleSetMarginPercent(node, YGEdgeLeft, tonumber(style.marginLeft:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMargin(node, YGEdgeLeft, style.marginLeft)
        end
    end
    if style.marginHorizontal then
        if style.marginHorizontal == "auto" then
            YGNodeStyleSetMarginAuto(node, YGEdgeHorizontal)
        elseif type(style.marginHorizontal) == "string" and style.marginHorizontal:match("%%$") then
            YGNodeStyleSetMarginPercent(node, YGEdgeHorizontal, tonumber(style.marginHorizontal:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMargin(node, YGEdgeHorizontal, style.marginHorizontal)
        end
    end
    if style.marginVertical then
        if style.marginVertical == "auto" then
            YGNodeStyleSetMarginAuto(node, YGEdgeVertical)
        elseif type(style.marginVertical) == "string" and style.marginVertical:match("%%$") then
            YGNodeStyleSetMarginPercent(node, YGEdgeVertical, tonumber(style.marginVertical:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetMargin(node, YGEdgeVertical, style.marginVertical)
        end
    end

    -- Padding (per-side only — shorthand/axis forms already expanded by expandPaddingShorthand)
    if style.paddingTop then
        if type(style.paddingTop) == "string" and style.paddingTop:match("%%$") then
            YGNodeStyleSetPaddingPercent(node, YGEdgeTop, tonumber(style.paddingTop:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPadding(node, YGEdgeTop, style.paddingTop)
        end
    end
    if style.paddingRight then
        if type(style.paddingRight) == "string" and style.paddingRight:match("%%$") then
            YGNodeStyleSetPaddingPercent(node, YGEdgeRight, tonumber(style.paddingRight:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPadding(node, YGEdgeRight, style.paddingRight)
        end
    end
    if style.paddingBottom then
        if type(style.paddingBottom) == "string" and style.paddingBottom:match("%%$") then
            YGNodeStyleSetPaddingPercent(node, YGEdgeBottom, tonumber(style.paddingBottom:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPadding(node, YGEdgeBottom, style.paddingBottom)
        end
    end
    if style.paddingLeft then
        if type(style.paddingLeft) == "string" and style.paddingLeft:match("%%$") then
            YGNodeStyleSetPaddingPercent(node, YGEdgeLeft, tonumber(style.paddingLeft:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPadding(node, YGEdgeLeft, style.paddingLeft)
        end
    end

    -- Position
    if style.position then
        YGNodeStyleSetPositionType(node, Style.PositionTypeToYoga(style.position))
    end
    if style.top then
        if type(style.top) == "string" and style.top:match("%%$") then
            YGNodeStyleSetPositionPercent(node, YGEdgeTop, tonumber(style.top:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPosition(node, YGEdgeTop, style.top)
        end
    end
    if style.right then
        if type(style.right) == "string" and style.right:match("%%$") then
            YGNodeStyleSetPositionPercent(node, YGEdgeRight, tonumber(style.right:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPosition(node, YGEdgeRight, style.right)
        end
    end
    if style.bottom then
        if type(style.bottom) == "string" and style.bottom:match("%%$") then
            YGNodeStyleSetPositionPercent(node, YGEdgeBottom, tonumber(style.bottom:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPosition(node, YGEdgeBottom, style.bottom)
        end
    end
    if style.left then
        if type(style.left) == "string" and style.left:match("%%$") then
            YGNodeStyleSetPositionPercent(node, YGEdgeLeft, tonumber(style.left:match("([%d%.]+)")) or 0)
        else
            YGNodeStyleSetPosition(node, YGEdgeLeft, style.left)
        end
    end

    -- Aspect ratio
    if style.aspectRatio then
        YGNodeStyleSetAspectRatio(node, style.aspectRatio)

        -- Yoga workaround: Yoga computes aspectRatio from unconstrained percentage
        -- width/height BEFORE applying maxWidth/maxHeight. CSS applies aspect-ratio
        -- AFTER max constraints. To match CSS behavior, we add the missing reverse
        -- constraint: percentage width + maxWidth → add maxHeight = maxWidth / aspectRatio
        --             percentage height + maxHeight → add maxWidth = maxHeight * aspectRatio
        -- This lets Yoga's maxHeight/maxWidth cap the oversized dimension.
        local ar = style.aspectRatio
        local w = style.width
        local h = style.height
        if type(w) == "string" and w:match("%%$") and style.maxWidth and not style.maxHeight then
            YGNodeStyleSetMaxHeight(node, style.maxWidth / ar)
        end
        if type(h) == "string" and h:match("%%$") and style.maxHeight and not style.maxWidth then
            YGNodeStyleSetMaxWidth(node, style.maxHeight * ar)
        end
    end

    -- Display (visible=false → YGDisplayNone, no layout space)
    if style.visible ~= nil then
        YGNodeStyleSetDisplay(node, style.visible ~= false and YGDisplayFlex or YGDisplayNone)
    end

    -- Overflow (critical for ScrollView)
    if style.overflow then
        -- Warn about overflow="scroll"/"auto" misuse:
        -- Yoga's overflow only controls clipping, NOT scrolling behavior.
        -- ScrollView.Init forces overflow="hidden" before reaching here,
        -- so this warning only fires for non-ScrollView widgets (not in whitelist).
        if style.overflow == "scroll" or style.overflow == "auto" then
            print(string.format(
                '[UI Warning] overflow="%s" on %s has no scrolling effect. '
                .. "Yoga overflow only controls clipping. Use UI.ScrollView for scrollable content.",
                style.overflow, self._className or "Widget"
            ))
        end

        local overflowMap = {
            ["visible"] = YGOverflowVisible,
            ["hidden"] = YGOverflowHidden,
            ["scroll"] = YGOverflowScroll,
        }
        local overflow = overflowMap[style.overflow] or YGOverflowVisible
        YGNodeStyleSetOverflow(node, overflow)
    end
end

--- Set style and update Yoga node
---@param style table
---@return Widget self
function Widget:SetStyle(style)
    -- Normalize color properties (convert string formats to RGBA tables)
    Style.NormalizeColorProps(style)
    -- Expand borderWidth table shorthand into per-side properties
    expandBorderWidthTable(style)
    -- Expand padding shorthand into per-side properties
    expandPaddingShorthand(style)
    self:ApplyStyleToYoga(style)

    -- Update transition config if provided
    if style.transition ~= nil then
        self.transitionConfig_ = Transition.ParseConfig(style.transition)
    end

    -- Check for transitionable property changes
    local config = self.transitionConfig_
    if config and self.initialized_ then
        local wasEmpty = #self.transitions_ == 0
        for k, v in pairs(style) do
            -- Skip non-transitionable props and the transition config itself
            if k ~= "transition" and Transition.ConfigIncludesProperty(config, k, self.transitionableProps_) then
                local oldVal = self.props[k]
                if oldVal ~= nil and oldVal ~= v then
                    -- Start or redirect transition (from current rendered value to new value)
                    local currentVal = self.renderProps_[k] or oldVal
                    local dur, eas = Transition.GetPropertyConfig(config, k)
                    Transition.Start(self.transitions_, k, currentVal, v, dur, eas)
                end
            end
        end
        -- Notify UI.lua to track this widget for updates (only on first transition)
        if wasEmpty and #self.transitions_ > 0 and onTransitionStart_ then
            onTransitionStart_(self)
        end
    end

    -- Merge style props (always update props to the target value)
    for k, v in pairs(style) do
        self.props[k] = v
    end

    -- Invalidate parent's z-index sort cache if zIndex changed
    if style.zIndex and self.parent then
        self.parent.needsZSort_ = true
    end

    -- Notify layout system (style changes may affect layout)
    if onLayoutDirty_ then onLayoutDirty_() end
    return self
end

--- Set width in base pixels
---@param width number Width in base pixels
---@return Widget self
function Widget:SetWidth(width)
    YGNodeStyleSetWidth(self.node, width)
    self.props.width = width
    if onLayoutDirty_ then onLayoutDirty_() end
    return self
end

--- Clear the explicit width and return Yoga to automatic width resolution.
--- Components with intrinsic sizing may override this to restore their own
--- measurement state before resolving the final Yoga width.
---@return Widget self
function Widget:SetWidthAuto()
    YGNodeStyleSetWidthAuto(self.node)
    self.props.width = nil
    if onLayoutDirty_ then onLayoutDirty_() end
    return self
end

--- Set height in base pixels
---@param height number Height in base pixels
---@return Widget self
function Widget:SetHeight(height)
    YGNodeStyleSetHeight(self.node, height)
    self.props.height = height
    if onLayoutDirty_ then onLayoutDirty_() end
    return self
end

--- Set minimum height (CSS min-height equivalent)
---@param minHeight number|string Minimum height (number for pixels, string for "N%", or "max-content"/"fit-content"/"stretch")
---@return Widget self
function Widget:SetMinHeight(minHeight)
    if type(minHeight) == "string" then
        if minHeight == "max-content" then
            YGNodeStyleSetMinHeightMaxContent(self.node)
        elseif minHeight == "fit-content" then
            YGNodeStyleSetMinHeightFitContent(self.node)
        elseif minHeight == "stretch" then
            YGNodeStyleSetMinHeightStretch(self.node)
        elseif minHeight:match("%%$") then
            YGNodeStyleSetMinHeightPercent(self.node, tonumber(minHeight:match("([%d%.]+)")) or 0)
        end
    else
        YGNodeStyleSetMinHeight(self.node, minHeight)
    end
    self.props.minHeight = minHeight
    if onLayoutDirty_ then onLayoutDirty_() end
    return self
end

--- Set background color (AI-friendly alias for SetStyle)
---@param color RGBAColor|string|false
---@return Widget self
function Widget:SetBackgroundColor(color)
    self:SetStyle({ backgroundColor = color })
    return self
end

--- Set border color (AI-friendly alias for SetStyle)
---@param color RGBAColor|string
---@return Widget self
function Widget:SetBorderColor(color)
    self:SetStyle({ borderColor = color })
    return self
end

--- Set opacity (AI-friendly alias for SetStyle)
---@param opacity number 0.0~1.0
---@return Widget self
function Widget:SetOpacity(opacity)
    self:SetStyle({ opacity = opacity })
    return self
end

--- Set a single prop by name (AI-friendly alias for SetStyle)
---@param key string Property name
---@param value any Property value
---@return Widget self
function Widget:SetProp(key, value)
    self:SetStyle({ [key] = value })
    return self
end

-- ============================================================================
-- Appearance Setters (AI-friendly aliases for SetStyle)
-- These exist because AI agents frequently hallucinate these method names.
-- All delegate to SetStyle for proper Yoga sync and transition support.
-- ============================================================================

---@param image string|table Background image resource path or config
---@return Widget self
function Widget:SetBackgroundImage(image)
    self:SetStyle({ backgroundImage = image })
    return self
end

---@param gradient table Gradient config { direction, colors }
---@return Widget self
function Widget:SetBackgroundGradient(gradient)
    self:SetStyle({ backgroundGradient = gradient })
    return self
end

---@param fit string "cover" | "contain" | "fill" | "none"
---@return Widget self
function Widget:SetBackgroundFit(fit)
    self:SetStyle({ backgroundFit = fit })
    return self
end

---@param tint RGBAColor|string Tint color applied to background image
---@return Widget self
function Widget:SetImageTint(tint)
    self:SetStyle({ imageTint = tint })
    return self
end

---@param radius number|table Border radius (number for all corners, or per-corner table)
---@return Widget self
function Widget:SetBorderRadius(radius)
    self:SetStyle({ borderRadius = radius })
    return self
end

---@param width number|table Border width (number for all sides, or per-side table)
---@return Widget self
function Widget:SetBorderWidth(width)
    self:SetStyle({ borderWidth = width })
    return self
end

---@param shadow table|table[] Box shadow config or array of shadows
---@return Widget self
function Widget:SetBoxShadow(shadow)
    self:SetStyle({ boxShadow = shadow })
    return self
end

---@param blur number Backdrop blur radius
---@return Widget self
function Widget:SetBackdropBlur(blur)
    self:SetStyle({ backdropBlur = blur })
    return self
end

---@param cursor string Cursor style name
---@return Widget self
function Widget:SetCursor(cursor)
    self:SetStyle({ cursor = cursor })
    return self
end

---@param zIndex number Z-ordering index
---@return Widget self
function Widget:SetZIndex(zIndex)
    self:SetStyle({ zIndex = zIndex })
    return self
end

---@param variant string Component variant (subclasses define valid values)
---@return Widget self
function Widget:SetVariant(variant)
    self:SetStyle({ variant = variant })
    return self
end

--- Get layout result (relative to parent)
--- Returns coordinates in BASE PIXELS (design-time units)
--- Yoga works in base pixel space, returns base pixels directly
---@return table { x, y, w, h }
function Widget:GetLayout()
    return {
        x = YGNodeLayoutGetLeft(self.node),
        y = YGNodeLayoutGetTop(self.node),
        w = YGNodeLayoutGetWidth(self.node),
        h = YGNodeLayoutGetHeight(self.node),
    }
end

--- Get absolute layout (accumulated from root)
--- Note: This returns the RENDER position (used by NanoVG after nvgTranslate)
--- For HitTest, use GetAbsoluteLayoutForHitTest which accounts for scroll offset
---@return table { x, y, w, h }
function Widget:GetAbsoluteLayout()
    -- Use manually set absolute layout if available (for custom positioning)
    -- This allows widgets to bypass Yoga layout for manual positioning
    if self.absoluteLayout then
        return self.absoluteLayout
    end

    -- Fixed positioning: viewport-relative coordinates set by UI.Render
    if self.fixedOffset_ then
        local layout = self:GetLayout()
        return { x = self.fixedOffset_[1], y = self.fixedOffset_[2], w = layout.w, h = layout.h }
    end

    local layout = self:GetLayout()
    local x, y = layout.x, layout.y

    -- Apply render offset/size if set (for manually positioned children like Tab content)
    if self.renderOffsetX_ then
        return {
            x = self.renderOffsetX_,
            y = self.renderOffsetY_ or y,
            w = self.renderWidth_ or layout.w,
            h = self.renderHeight_ or layout.h
        }
    end

    local p = self.parent
    while p do
        -- Fixed parent: use fixed position as absolute base, stop walking
        if p.fixedOffset_ then
            x = x + p.fixedOffset_[1]
            y = y + p.fixedOffset_[2]
            break
        end
        -- If parent has render offset, use it directly and stop traversal
        if p.renderOffsetX_ then
            x = x + p.renderOffsetX_
            y = y + (p.renderOffsetY_ or 0)
            break
        end
        local pl = p:GetLayout()
        x = x + pl.x
        y = y + pl.y
        p = p.parent
    end

    return { x = x, y = y, w = layout.w, h = layout.h }
end

--- Get absolute layout for HitTest (accounts for scroll offset)
--- This returns the VISUAL position on screen
---@return table { x, y, w, h }
function Widget:GetAbsoluteLayoutForHitTest()
    -- Use manually set absolute layout if available (for custom positioning)
    if self.absoluteLayout then
        return self.absoluteLayout
    end

    -- Fixed positioning: viewport-relative coordinates (no scroll offset applies)
    if self.fixedOffset_ then
        local layout = self:GetLayout()
        return { x = self.fixedOffset_[1], y = self.fixedOffset_[2], w = layout.w, h = layout.h }
    end

    local layout = self:GetLayout()
    local x, y = layout.x, layout.y
    local w, h = layout.w, layout.h

    -- Apply render offset/size if set
    if self.renderOffsetX_ then
        x = self.renderOffsetX_
        y = self.renderOffsetY_ or y
        w = self.renderWidth_ or w
        h = self.renderHeight_ or h
        -- Still need to account for scroll offset from ancestors
        local p = self.parent
        while p do
            if p.GetScroll then
                local sx, sy = p:GetScroll()
                x = x - sx
                y = y - sy
            end
            p = p.parent
        end
        return { x = x, y = y, w = w, h = h }
    end

    local p = self.parent
    while p do
        -- Fixed parent: use fixed position as absolute base, stop walking
        -- No scroll offset applies (fixed is relative to viewport, not scroll container)
        if p.fixedOffset_ then
            x = x + p.fixedOffset_[1]
            y = y + p.fixedOffset_[2]
            return { x = x, y = y, w = w, h = h }
        end
        -- If parent has render offset, use it directly and stop traversal
        if p.renderOffsetX_ then
            x = x + p.renderOffsetX_
            y = y + (p.renderOffsetY_ or 0)
            -- Check if THIS parent also has scroll offset (e.g., ScrollView as tab content)
            if p.GetScroll then
                local sx, sy = p:GetScroll()
                x = x - sx
                y = y - sy
            end
            -- Still need to continue for scroll offset from ancestors
            p = p.parent
            while p do
                if p.GetScroll then
                    local sx, sy = p:GetScroll()
                    x = x - sx
                    y = y - sy
                end
                p = p.parent
            end
            break
        end
        local pl = p:GetLayout()
        x = x + pl.x
        y = y + pl.y
        -- Account for scroll offset if parent is scrollable
        if p.GetScroll then
            local sx, sy = p:GetScroll()
            x = x - sx
            y = y - sy
        end
        p = p.parent
    end

    return { x = x, y = y, w = w, h = h }
end

--- Get absolute position (x, y)
---@return number x, number y
function Widget:GetAbsolutePosition()
    local l = self:GetAbsoluteLayout()
    return l.x, l.y
end

--- Get computed size (w, h)
---@return number w, number h
function Widget:GetComputedSize()
    local l = self:GetLayout()
    return l.w, l.h
end

-- ============================================================================
-- Rendering
-- ============================================================================

--- Render the widget (override in subclasses)
--- NOTE: Framework handles child rendering automatically via UI.Render().
--- Only implement self-drawing here. Children are rendered automatically.
---@param nvg NVGContextWrapper
function Widget:Render(nvg)
    -- Default: render background (shadow + color + image + border)
    -- Children are rendered by framework automatically
    self:RenderFullBackground(nvg)
end

--- Custom child rendering hook (optional override)
--- Implement this if your widget needs special handling before/after rendering children.
--- Examples: ScrollView (scroll offset + clipping), Panel with overflow="hidden"
---
--- Usage:
---   function MyWidget:CustomRenderChildren(nvg, renderFn)
---       nvgSave(nvg)
---       nvgIntersectScissor(nvg, ...)  -- IMPORTANT: use IntersectScissor (not nvgScissor) to preserve parent clipping
---       nvgTranslate(nvg, ...)  -- Apply transform
---
---       for _, child in ipairs(self.children) do
---           renderFn(child, nvg)  -- Recursively render each child
---       end
---
---       nvgRestore(nvg)
---       self:RenderOverlays(nvg)  -- Render things on top of children
---   end
---
-- ---@param nvg NVGContextWrapper
-- ---@param renderFn function(widget, nvg) The recursive render function to call for each child
-- function Widget:CustomRenderChildren(nvg, renderFn)
--     -- Default implementation (not defined = framework handles it)
-- end

--- Get children list in correct render order (respecting z-index).
--- Use this in CustomRenderChildren instead of self.children directly
--- to ensure z-index sorting works for widgets with custom render logic.
---@return Widget[] Children list (sorted by zIndex if needed, or self.children)
function Widget:GetRenderChildren()
    local children = self.children
    if self.needsZSort_ then
        local sorted = {}
        for i = 1, #children do
            sorted[i] = children[i]
        end
        table.sort(sorted, function(a, b)
            return (a.props.zIndex or 0) < (b.props.zIndex or 0)
        end)
        self.sortedChildren_ = sorted
        self.needsZSort_ = false
    end
    return self.sortedChildren_ or children
end

--- Return a radius expanded by delta without mutating props/theme data.
---@param radius number|table|nil Border radius
---@param delta number|nil Offset added to each corner
---@return number|table
function Widget.OffsetRadius(radius, delta)
    delta = delta or 0
    if type(radius) == "table" then
        return {
            math.max(0, (radius[1] or 0) + delta),
            math.max(0, (radius[2] or 0) + delta),
            math.max(0, (radius[3] or 0) + delta),
            math.max(0, (radius[4] or 0) + delta),
        }
    end
    return math.max(0, (radius or 0) + delta)
end

--- Resolve per-corner radius props over a base radius for rendering only.
---@param radius number|table|nil Base radius
---@param props table|nil Props or style table with borderRadiusTopLeft/Right/Bottom*
---@return number|table
function Widget.ResolveCornerRadius(radius, props)
    props = props or {}
    local hasTL = props.borderRadiusTopLeft
    local hasTR = props.borderRadiusTopRight
    local hasBR = props.borderRadiusBottomRight
    local hasBL = props.borderRadiusBottomLeft
    if hasTL ~= nil or hasTR ~= nil or hasBR ~= nil or hasBL ~= nil then
        local base = type(radius) == "number" and radius or 0
        local baseTL = type(radius) == "table" and (radius[1] or 0) or base
        local baseTR = type(radius) == "table" and (radius[2] or 0) or base
        local baseBR = type(radius) == "table" and (radius[3] or 0) or base
        local baseBL = type(radius) == "table" and (radius[4] or 0) or base
        return {
            hasTL ~= nil and hasTL or baseTL,
            hasTR ~= nil and hasTR or baseTR,
            hasBR ~= nil and hasBR or baseBR,
            hasBL ~= nil and hasBL or baseBL,
        }
    end
    return radius or 0
end

--- Return a radius that keeps only top corners.
---@param radius number|table|nil Border radius
---@return table
function Widget.TopRadius(radius)
    if type(radius) == "table" then
        return { radius[1] or 0, radius[2] or 0, 0, 0 }
    end
    radius = radius or 0
    return { radius, radius, 0, 0 }
end

--- Return a radius that keeps only bottom corners.
---@param radius number|table|nil Border radius
---@return table
function Widget.BottomRadius(radius)
    if type(radius) == "table" then
        return { 0, 0, radius[3] or 0, radius[4] or 0 }
    end
    radius = radius or 0
    return { 0, 0, radius, radius }
end

local function borderAlignedRect(rect, radius, borderWidth, borderAlign)
    local half = (borderWidth or 0) / 2
    if borderAlign == "inside" then
        return {
            x = rect.x + half,
            y = rect.y + half,
            w = math.max(0, rect.w - borderWidth),
            h = math.max(0, rect.h - borderWidth),
        }, Widget.OffsetRadius(radius, -half)
    elseif borderAlign == "outside" then
        return {
            x = rect.x - half,
            y = rect.y - half,
            w = rect.w + borderWidth,
            h = rect.h + borderWidth,
        }, Widget.OffsetRadius(radius, half)
    end
    return rect, radius
end

--- Render a style box with background, image, shadow, border and border alignment.
--- All values are in BASE PIXELS. nvgScale in UI.Render handles screen scaling.
---@param nvg NVGContextWrapper
---@param rect table|nil Rect { x, y, w, h }. Defaults to widget absolute layout.
---@param style table|nil StyleBox { backgroundColor, backgroundGradient, borderColor, borderWidth, borderAlign, borderRadius, boxShadow, shape, ... }
function Widget:RenderStyleBox(nvg, rect, style)
    style = style or {}

    local l = rect or self:GetAbsoluteLayout()

    local radius = style.borderRadius or 0
    local shape = style.shape

    radius = Widget.ResolveCornerRadius(radius, style)

    local geom = self:GetShapeGeometry(l, shape, radius)

    local boxShadow = style.boxShadow
    if boxShadow == false then
        -- Explicitly disabled.
    elseif boxShadow then
        self:RenderBoxShadows(nvg, geom, boxShadow)
    end

    local backdropBlur = style.backdropBlur
    if backdropBlur and backdropBlur > 0 then
        self:RenderBackdropBlur(nvg, geom, backdropBlur)
    end

    local bgColor = style.backgroundColor
    if bgColor then
        self:CreateShapePath(nvg, geom)
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
        nvgFill(nvg)
    end

    local gradient = style.backgroundGradient
    if gradient then
        self:RenderGradientBackground(nvg, geom, gradient)
    end

    local bgImage = style.backgroundImage
    if bgImage then
        local fit = style.backgroundFit or "fill"
        local slice = style.backgroundSlice
        local tint = style.imageTint
        local opacity = style.backgroundImageOpacity
        if geom.shape == "circle" then
            self:RenderBackgroundImage(nvg, bgImage, geom, fit, slice, geom.radius, tint, opacity)
        else
            self:RenderBackgroundImage(nvg, bgImage, l, fit, slice, geom.radius, tint, opacity)
        end
    end

    local borderColor = style.borderColor
    local borderWidth = style.borderWidth or 0
    if not borderColor and borderWidth > 0 then
        borderColor = Theme.Color("border")
    end
    if borderColor and borderWidth > 0 then
        local borderRect, borderRadius = borderAlignedRect(
            l,
            radius,
            borderWidth,
            style.borderAlign or "center"
        )
        local borderGeom = self:GetShapeGeometry(borderRect, shape, borderRadius)
        self:CreateShapePath(nvg, borderGeom)
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, borderWidth)
        nvgStroke(nvg)
    end
end

--- Render background with color and border radius
---@param nvg NVGContextWrapper
---@param color RGBAColor|nil RGBA color
---@param radius number|table|nil Border radius
function Widget:RenderBackground(nvg, color, radius)
    if not color then return end
    self:RenderStyleBox(nvg, nil, {
        backgroundColor = color,
        borderRadius = radius or self.props.borderRadius or 0,
        boxShadow = false,
        borderWidth = 0,
    })
end

--- Render border
---@param nvg NVGContextWrapper
---@param color RGBAColor|nil RGBA color
---@param width number|nil Border width
---@param radius number|table|nil Border radius
function Widget:RenderBorder(nvg, color, width, radius)
    if not color or not width or width <= 0 then return end

    local l = self:GetAbsoluteLayout()
    radius = radius or self.props.borderRadius or 0

    local geom = self:GetShapeGeometry(l, nil, radius)
    self:CreateShapePath(nvg, geom)
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, width)
    nvgStroke(nvg)
end

-- ============================================================================
-- Shape Support
-- ============================================================================

--- Calculate shape geometry for rendering
--- For "circle" shape, returns centered circle geometry
---@param l table Layout { x, y, w, h }
---@param shape string|nil Shape type: "square", "rounded", "circle" (default: "rounded")
---@param radius number|table Scaled border radius (used for "rounded" shape)
---@return table { shape, x, y, w, h, radius, centerX, centerY, circleRadius }
function Widget:GetShapeGeometry(l, shape, radius)
    shape = shape or "rounded"

    if shape == "circle" then
        -- Circle: use min(width, height) as diameter, centered
        local diameter = math.min(l.w, l.h)
        local circleRadius = diameter / 2
        local offsetX = (l.w - diameter) / 2
        local offsetY = (l.h - diameter) / 2
        return {
            shape = "circle",
            x = l.x + offsetX,
            y = l.y + offsetY,
            w = diameter,
            h = diameter,
            radius = circleRadius,
            centerX = l.x + l.w / 2,
            centerY = l.y + l.h / 2,
            circleRadius = circleRadius,
        }
    elseif shape == "ellipse" then
        -- Ellipse: fill the widget bounds (rx = w/2, ry = h/2)
        return {
            shape = "ellipse",
            x = l.x,
            y = l.y,
            w = l.w,
            h = l.h,
            radius = math.min(l.w, l.h) / 2,
            centerX = l.x + l.w / 2,
            centerY = l.y + l.h / 2,
            rx = l.w / 2,
            ry = l.h / 2,
        }
    elseif shape == "square" then
        -- Square: no border radius
        return {
            shape = "square",
            x = l.x,
            y = l.y,
            w = l.w,
            h = l.h,
            radius = 0,
        }
    else
        -- Rounded (default): use borderRadius
        -- radius can be a number (uniform) or table {TL, TR, BR, BL} (per-corner)
        -- Clamp radius to min(w,h)/2 to prevent elliptical corners (CSS-compatible behavior)
        local maxR = math.min(l.w, l.h) / 2
        if type(radius) == "table" then
            local cr = {
                math.min(radius[1] or 0, maxR),
                math.min(radius[2] or 0, maxR),
                math.min(radius[3] or 0, maxR),
                math.min(radius[4] or 0, maxR),
            }
            return {
                shape = "rounded",
                x = l.x,
                y = l.y,
                w = l.w,
                h = l.h,
                radius = math.max(cr[1], cr[2], cr[3], cr[4]),
                cornerRadii = cr,
            }
        else
            return {
                shape = "rounded",
                x = l.x,
                y = l.y,
                w = l.w,
                h = l.h,
                radius = math.min(radius, maxR),
            }
        end
    end
end

--- Create NVG path for shape
---@param nvg NVGContextWrapper
---@param geom table Shape geometry from GetShapeGeometry
function Widget:CreateShapePath(nvg, geom)
    nvgBeginPath(nvg)
    if geom.shape == "circle" then
        nvgCircle(nvg, geom.centerX, geom.centerY, geom.circleRadius)
    elseif geom.shape == "ellipse" then
        nvgEllipse(nvg, geom.centerX, geom.centerY, geom.rx, geom.ry)
    elseif geom.cornerRadii then
        -- Per-corner radius: {TL, TR, BR, BL}
        local cr = geom.cornerRadii
        nvgRoundedRectVarying(nvg, geom.x, geom.y, geom.w, geom.h,
            cr[1], cr[2], cr[3], cr[4])
    elseif geom.radius > 0 then
        nvgRoundedRect(nvg, geom.x, geom.y, geom.w, geom.h, geom.radius)
    else
        nvgRect(nvg, geom.x, geom.y, geom.w, geom.h)
    end
end

-- ============================================================================
-- Gradient Background Rendering
-- ============================================================================

--- Resolve gradient direction to start/end coordinates
---@param direction string|number Direction spec
---@param x number Layout x
---@param y number Layout y
---@param w number Layout width
---@param h number Layout height
---@return number sx, number sy, number ex, number ey
function Widget.ResolveGradientDirection(direction, x, y, w, h)
    if type(direction) == "number" then
        -- Angle in degrees (0 = to-top, 90 = to-right, 180 = to-bottom)
        local rad = direction * math.pi / 180
        local cx, cy = x + w * 0.5, y + h * 0.5
        local dx = math.sin(rad) * w * 0.5
        local dy = -math.cos(rad) * h * 0.5
        return cx - dx, cy - dy, cx + dx, cy + dy
    end
    -- String presets
    if direction == "to-right" then return x, y + h * 0.5, x + w, y + h * 0.5 end
    if direction == "to-left" then return x + w, y + h * 0.5, x, y + h * 0.5 end
    if direction == "to-top" then return x + w * 0.5, y + h, x + w * 0.5, y end
    if direction == "to-bottom-right" then return x, y, x + w, y + h end
    if direction == "to-bottom-left" then return x + w, y, x, y + h end
    if direction == "to-top-right" then return x, y + h, x + w, y end
    if direction == "to-top-left" then return x + w, y + h, x, y end
    -- Default: "to-bottom"
    return x + w * 0.5, y, x + w * 0.5, y + h
end

--- Render gradient background
---@param nvg NVGContextWrapper
---@param geom table Shape geometry
---@param gradient table { type, direction, from, to }
function Widget:RenderGradientBackground(nvg, geom, gradient)
    local fromColor = gradient.from
    local toColor = gradient.to
    if not fromColor or not toColor then return end

    local c1 = nvgRGBA(fromColor[1], fromColor[2], fromColor[3], fromColor[4] or 255)
    local c2 = nvgRGBA(toColor[1], toColor[2], toColor[3], toColor[4] or 255)

    local paint
    if gradient.type == "radial" then
        local cx = geom.x + geom.w * 0.5
        local cy = geom.y + geom.h * 0.5
        local innerR = gradient.innerRadius or 0
        local outerR = gradient.outerRadius or math.max(geom.w, geom.h) * 0.5
        paint = nvgRadialGradient(nvg, cx, cy, innerR, outerR, c1, c2)
    else
        -- Linear gradient (default)
        local sx, sy, ex, ey = Widget.ResolveGradientDirection(
            gradient.direction or "to-bottom", geom.x, geom.y, geom.w, geom.h)
        paint = nvgLinearGradient(nvg, sx, sy, ex, ey, c1, c2)
    end

    self:CreateShapePath(nvg, geom)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

-- ============================================================================
-- Backdrop Blur Approximation
-- ============================================================================

--- Render backdrop blur visual approximation
--- Uses a semi-transparent frosted overlay effect (not true Gaussian blur).
--- True backdrop-blur requires render-to-texture + shader pipeline.
---@param nvg NVGContextWrapper
---@param geom table Shape geometry
---@param blurAmount number Blur intensity (higher = more opaque frost)
function Widget:RenderBackdropBlur(nvg, geom, blurAmount)
    -- Frosted glass approximation: layered semi-transparent fills
    -- Layer 1: dark overlay to desaturate
    local alpha1 = math.min(255, blurAmount * 3)
    self:CreateShapePath(nvg, geom)
    nvgFillColor(nvg, nvgRGBA(128, 128, 128, math.floor(alpha1 * 0.3)))
    nvgFill(nvg)

    -- Layer 2: box gradient for soft edge blur effect
    local feather = blurAmount * 2
    local paint = nvgBoxGradient(nvg,
        geom.x + feather * 0.1, geom.y + feather * 0.1,
        geom.w - feather * 0.2, geom.h - feather * 0.2,
        geom.radius, feather,
        nvgRGBA(200, 200, 200, math.floor(math.min(255, blurAmount * 2.5))),
        nvgRGBA(220, 220, 220, math.floor(math.min(255, blurAmount * 1.5)))
    )
    self:CreateShapePath(nvg, geom)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

-- ============================================================================
-- Per-Side Border Rendering
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Single-side rounded-border builder helpers (used by RenderPerSideBorders)
-- ----------------------------------------------------------------------------
-- These were previously closures re-created on every RenderPerSideBorders call;
-- hoisting them to module scope removes that per-frame allocation. Immediate-mode
-- render is single-threaded and non-reentrant (UI.Render → renderWidgetTree runs
-- one widget at a time, no yield), so a single shared scratch context (SB_) is
-- safe and keeps the geometry emitters allocation-free.

local SB_HALF_PI = math.pi * 0.5
local SB_W_MIN = 0.9      -- solid fill stops where transverse band width falls to this (px)
local SB_W_TAIL_END = 0.2 -- faint tail stops where transverse band width falls below this (px)
local SB_DIVE = 0.5       -- cut vertex dives this far inside the silhouette (px)

-- Shared scratch: nvg handle, uniform color, and the per-side affine map
-- (screen U = oU + aU*u + bU*v, screen V = oV + aV*u + bV*v). Canonical band
-- space is u along the edge, v inward from the outer edge.
local SB_ = { nvg = nil, color = nil, oU = 0, aU = 0, bU = 0, oV = 0, aV = 0, bV = 0 }

-- Compare two border colors (RGBA arrays) for equality; nil-safe.
local function sbColorsEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and (a[4] or 255) == (b[4] or 255)
end

local function sbU(u, v) return SB_.oU + SB_.aU * u + SB_.bU * v end
local function sbV(u, v) return SB_.oV + SB_.aV * u + SB_.bV * v end

local function sbMoveTo(u, v) nvgMoveTo(SB_.nvg, sbU(u, v), sbV(u, v)) end
local function sbLineTo(u, v) nvgLineTo(SB_.nvg, sbU(u, v), sbV(u, v)) end

-- Partial-arc cubic bezier around corner center (cu, cv):
-- point(δ) = (cu + su·R·sinδ, cv − RV·cosδ). RV = R gives the outer circle,
-- RV = e the inner ellipse. su = ±1 selects the corner side.
local function sbArcTo(cu, cv, su, R, RV, dFrom, dTo)
    -- Skip only when BOTH axes are degenerate (true zero-radius corner). A
    -- single degenerate axis (e.g. shared-corner inner ellipse with
    -- adjacentWidth >= radius, so Eu == 0) must still emit: the bezier formula
    -- collapses to the straight segment along the live axis, which IS the CSS
    -- inner boundary there. Early-returning instead let ClosePath cut a
    -- diagonal across the whole band (visible slanted inner edge).
    if R <= 0 and RV <= 0 then return end
    local k = 4 / 3 * math.tan((dTo - dFrom) / 4)
    local s0, c0 = math.sin(dFrom), math.cos(dFrom)
    local s1, c1 = math.sin(dTo), math.cos(dTo)
    local p0u, p0v = cu + su * R * s0, cv - RV * c0
    local p3u, p3v = cu + su * R * s1, cv - RV * c1
    local p1u, p1v = p0u + k * su * R * c0, p0v + k * RV * s0
    local p2u, p2v = p3u - k * su * R * c1, p3v - k * RV * s1
    nvgBezierTo(SB_.nvg,
        sbU(p1u, p1v), sbV(p1u, p1v),
        sbU(p2u, p2v), sbV(p2u, p2v),
        sbU(p3u, p3v), sbV(p3u, p3v))
end

-- Transverse band width at depth dy from the corner center: outer circle radius
-- minus inner-ellipse radius. See sbCutAngle for why the cut criterion is this
-- transverse width rather than the radial thickness.
local function sbWidth(dy, r, e)
    return math.sqrt(math.max(0, r * r - dy * dy))
        - r * math.sqrt(math.max(0, 1 - (dy / e) ^ 2))
end

-- Taper cut angle (only meaningful when e > 0). The cut criterion must be the
-- band's NARROW-axis width, not its radial thickness: near the far tangent the
-- outer circle and inner ellipse nearly coincide laterally, so pixel coverage
-- (what the browser renders) is governed by the transverse width. Cutting by
-- radial thickness paints solid ink where Chromium is at <10% coverage (measured:
-- our band went solid ~7px earlier along the arc than the reference). Solve
-- width(dy) = wTarget by bisection: outer u = r - sqrt(r^2 - dy^2), inner
-- u = r - r*sqrt(1 - (dy/e)^2), dy = distance from corner center toward the tangent.
local function sbCutAngle(r, e, wTarget)
    if e <= 0 or r <= 0 then return SB_HALF_PI end
    local lo, hi = 0, e * 0.999 -- dy: 0 = tangent, larger = deeper
    if sbWidth(hi, r, e) <= wTarget then return 0 end -- band never that wide
    for _ = 1, 18 do
        local mid = (lo + hi) * 0.5
        if sbWidth(mid, r, e) < wTarget then lo = mid else hi = mid end
    end
    local dy = (lo + hi) * 0.5
    return math.acos(math.min(1, dy / r))
end

-- Matching INNER-ellipse cut angle: at the same parametric angle the ellipse
-- point sits (r-e)·cosδ px higher than the circle point, so a same-angle cut is
-- a tall vertical face of solid ink poking into the zone the browser leaves at
-- low coverage. Return the angle with the SAME height as the outer cut point.
local function sbInnerCut(d, R, E)
    if E <= 0 or d >= SB_HALF_PI then return d end
    return math.acos(math.min(1, (R / E) * math.cos(d)))
end

-- Tail fade: beyond the width cut the band is sub-pixel wide all the way to the
-- tangent, exactly the zone the browser renders as a faint fading hairline
-- (<30% coverage). One fill of the EXACT remaining wedge at 22% alpha reproduces
-- that: the geometry contributes almost no solid area, so what shows is its AA
-- footprint — the same faint line, with no stepped seams and no solid stub.
-- Reads SB_.nvg / SB_.color set by the caller.
local function sbTailFade(cu, cv, su, R, E, dFrom, fIn)
    if R <= 0 or dFrom <= 0 or dFrom >= SB_HALF_PI then return end
    -- End angle: where the band narrows to W_TAIL_END (browser coverage <8%
    -- there — it draws nothing, and neither should our fringe).
    local dEnd = sbCutAngle(R, E, SB_W_TAIL_END)
    if dEnd <= dFrom then return end
    local fEnd = math.acos(math.min(1, (R / E) * math.cos(dEnd)))
    local s0, c0 = math.sin(dFrom), math.cos(dFrom)
    local nvg = SB_.nvg
    nvgBeginPath(nvg)
    -- NOTE: outer edge must stay exactly on R — insetting it makes the outer arc
    -- cross the inner ellipse near the tangent (self-intersecting bowtie) and
    -- deposits solid artifacts.
    nvgMoveTo(nvg,
        sbU(cu + su * R * s0, cv - R * c0),
        sbV(cu + su * R * s0, cv - R * c0))
    sbArcTo(cu, cv, su, R, R, dFrom, dEnd)      -- outer arc to end cut
    nvgLineTo(nvg,
        sbU(cu + su * R * math.sin(fEnd), cv - E * math.cos(fEnd)),
        sbV(cu + su * R * math.sin(fEnd), cv - E * math.cos(fEnd))) -- level end cut
    sbArcTo(cu, cv, su, R, E, fEnd, fIn)        -- inner ellipse back to level cut
    nvgClosePath(nvg)
    local c = SB_.color
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor((c[4] or 255) * 0.22)))
    nvgFill(nvg)
end

-- Set the per-side affine map into the shared scratch context.
local function sbSetSide(side, x, y, w, h)
    if side == 'bottom' then
        SB_.oU, SB_.aU, SB_.bU = x, 1, 0
        SB_.oV, SB_.aV, SB_.bV = y + h, 0, -1
    elseif side == 'top' then
        SB_.oU, SB_.aU, SB_.bU = x, 1, 0
        SB_.oV, SB_.aV, SB_.bV = y, 0, 1
    elseif side == 'left' then
        SB_.oU, SB_.aU, SB_.bU = x, 0, 1
        SB_.oV, SB_.aV, SB_.bV = y, 1, 0
    else -- right
        SB_.oU, SB_.aU, SB_.bU = x + w, 0, -1
        SB_.oV, SB_.aV, SB_.bV = y, 1, 0
    end
end

-- Adjacent-corner mode for one end of a side band: 'taper' when the adjacent
-- side is inactive; otherwise horizontal sides own the corner (full ring
-- sector) and vertical sides stop flush at the seam (issue #2100).
-- NOTE: the and...or ternary below relies on both result values being truthy
-- ('ring'/'flush' are non-empty string constants). Keep it that way if the
-- mode tokens are ever changed.
local function sbModeFor(side, adj)
    if adj <= 0 then return 'taper' end
    return (side == 'top' or side == 'bottom') and 'ring' or 'flush'
end

-- Build and fill one side's rounded band. m1/m2: corner mode at the u=0 / u=L
-- end ('taper' | 'ring' | 'flush'); a1/a2: adjacent side widths there.
-- Module-level so the hot path allocates NO closures (#2108): geometry, color
-- and nvg arrive as explicit params, and the local aliases below are plain
-- reference copies of the module-level emitters.
-- Deferred taper tail-fades: sbRenderSide records requests into this flat
-- module-level scratch (8 slots per fade: side + 7 numbers), flushed by the
-- caller AFTER the single merged fill. Reused across calls - zero alloc.
local SB_FADES = {}
local SB_FADES_N = 0

local function sbRenderSide(nvg, uniformColor, side, sww, m1, a1, m2, a2, x, y, w, h, oTL, oTR, oBR, oBL)
    -- Set up the shared per-side scratch context (nvg + affine map + color)
    -- and alias the hoisted module-level emitters to local names.
    SB_.nvg = nvg
    SB_.color = uniformColor
    sbSetSide(side, x, y, w, h)
    local moveTo, lineTo, arcTo = sbMoveTo, sbLineTo, sbArcTo
    local innerCut, tailFade = sbInnerCut, sbTailFade
    local HALF_PI, DIVE = SB_HALF_PI, SB_DIVE

    -- Per-side edge length L and corner radii (r1 at u=0, r2 at u=L)
    local L, r1, r2
    if side == 'bottom' then
        L, r1, r2 = w, oBL, oBR
    elseif side == 'top' then
        L, r1, r2 = w, oTL, oTR
    elseif side == 'left' then
        L, r1, r2 = h, oTL, oBL
    else
        L, r1, r2 = h, oTR, oBR
    end

    -- Clamp radii so the two corners cannot overlap along the edge
    local maxR = L * 0.5
    if r1 > maxR then r1 = maxR end
    if r2 > maxR then r2 = maxR end
    local e1 = math.max(0, r1 - sww)
    local e2 = math.max(0, r2 - sww)
    local capV = math.min(sww, maxR)
    -- Shared-corner inner ellipse radii (u-axis shrinks by the ADJACENT
    -- side's width, v-axis by our own width — CSS padding-box corner)
    local Eu1, Ev1 = math.max(0, r1 - a1), e1
    local Eu2, Ev2 = math.max(0, r2 - a2), e2

    -- Taper cut angles (only used at taper corners)
    local d1 = e1 > 0 and sbCutAngle(r1, e1, SB_W_MIN) or HALF_PI
    local d2 = e2 > 0 and sbCutAngle(r2, e2, SB_W_MIN) or HALF_PI
    local f1 = e1 > 0 and innerCut(d1, r1, e1) or d1
    local f2 = e2 > 0 and innerCut(d2, r2, e2) or d2

    -- Corner centers in canonical space
    local c1u, c1v = r1, r1
    local c2u, c2v = L - r2, r2

    -- #2102: translucent flush seams extend the band ~1px under the ring-owned
    -- corner. Butt-to-butt AA fringes at an exact seam are deduped first-wins
    -- for translucent fills, which would leave a visibly lighter row; the
    -- overlap stays single-composited under the engine dedup. Opaque paints
    -- keep the exact seam (fringe accumulation fills it).
    -- Extension length: min(1, r*0.35). One fringe (1px) fully re-covers the
    -- seam row, so more never helps; the r-proportional term shrinks it for
    -- tiny radii, where the arc silhouette bends away from the band edge as
    -- ~delta^2/(2r) and a fixed 1px extension would poke visibly outside
    -- (0.35 keeps the protrusion under ~0.13px for r >= 2). Not tied to the
    -- fringe width - it is a silhouette-containment bound, not an AA bound.
    local ext1, ext2 = 0, 0
    if (uniformColor[4] or 255) < 255 then
        if m1 == 'flush' then ext1 = math.min(1, r1 * 0.35) end
        if m2 == 'flush' then ext2 = math.min(1, r2 * 0.35) end
    end

    -- ---- corner 1, outer side ---- (path opened by the caller: all same-color
    -- bands are sub-paths of ONE fill so the engine dedup covers seam overlaps)
    if m1 == 'flush' then
        -- adjacent side owns this corner: start at the corner seam
        -- (translucent: overlapped by ext1 into the ring-owned zone)
        moveTo(r1 - ext1, 0)
    elseif m1 == 'ring' then
        if r1 > 0 and (Eu1 > 0 or Ev1 > 0) then
            moveTo(0, r1) -- tangent point on the perpendicular silhouette
            arcTo(c1u, c1v, -1, r1, r1, HALF_PI, 0)
        else
            -- tiny radius: square regime, cap along the silhouette
            moveTo(0, math.max(r1, capV))
            if r1 > 0 then
                lineTo(0, r1)
                arcTo(c1u, c1v, -1, r1, r1, HALF_PI, 0)
            else
                lineTo(0, 0)
            end
        end
    elseif e1 > 0 then
        -- taper: start at the dived cut vertex, ramp onto the arc
        local dd1 = math.min(d1, 1.5 / r1)
        moveTo(c1u - (r1 - DIVE) * math.sin(d1), c1v - (r1 - DIVE) * math.cos(d1))
        lineTo(c1u - r1 * math.sin(d1 - dd1), c1v - r1 * math.cos(d1 - dd1))
        arcTo(c1u, c1v, -1, r1, r1, d1 - dd1, 0)
    else
        -- taper corner in the square regime: cap along the silhouette
        moveTo(0, math.max(r1, capV))
        if r1 > 0 then lineTo(0, r1) end
        arcTo(c1u, c1v, -1, r1, r1, HALF_PI, 0)
        if r1 <= 0 then lineTo(0, 0) end
    end
    -- ---- outer straight edge ----
    lineTo(c2u, 0)
    -- ---- corner 2, outer side, and return to the inner edge ----
    if m2 == 'flush' then
        -- flush cut at the corner seam (translucent: overlapped by ext2)
        lineTo(c2u + ext2, 0)
        lineTo(c2u + ext2, capV)
    elseif m2 == 'ring' then
        if r2 > 0 and (Eu2 > 0 or Ev2 > 0) then
            arcTo(c2u, c2v, 1, r2, r2, 0, HALF_PI) -- full outer arc to tangent
            lineTo(c2u + Eu2, r2)                  -- seam to the inner ellipse
            arcTo(c2u, c2v, 1, Eu2, Ev2, HALF_PI, 0) -- inner ellipse back
        else
            arcTo(c2u, c2v, 1, r2, r2, 0, HALF_PI)
            if r2 <= 0 then lineTo(L, 0) end
            lineTo(L, math.max(r2, capV))
            lineTo(c2u, capV)
        end
    elseif e2 > 0 then
        local dd2 = math.min(d2, 1.5 / r2)
        arcTo(c2u, c2v, 1, r2, r2, 0, d2 - dd2) -- outer arc
        lineTo(c2u + (r2 - DIVE) * math.sin(d2), c2v - (r2 - DIVE) * math.cos(d2)) -- dive
        lineTo(c2u + r2 * math.sin(f2), c2v - e2 * math.cos(f2)) -- level cut
        arcTo(c2u, c2v, 1, r2, e2, f2, 0) -- inner ellipse back
    else
        arcTo(c2u, c2v, 1, r2, r2, 0, d2)
        if r2 <= 0 then lineTo(L, 0) end
        lineTo(L, math.max(r2, capV))
        lineTo(c2u, capV)
    end
    -- ---- inner straight edge ----
    lineTo(c1u - ext1, Ev1 > 0 and (c1v - Ev1) or capV)
    -- ---- corner 1, inner side ----
    if m1 == 'flush' then
        -- straight run to the flush cut; ClosePath seals u = r1
    elseif m1 == 'ring' then
        if r1 > 0 and (Eu1 > 0 or Ev1 > 0) then
            arcTo(c1u, c1v, -1, Eu1, Ev1, 0, HALF_PI) -- ends at (r1-Eu1, r1)
            -- ClosePath seals the seam back to (0, r1)
        else
            lineTo(0, capV)
        end
    elseif e1 > 0 then
        arcTo(c1u, c1v, -1, r1, e1, 0, f1)
    else
        lineTo(0, capV)
    end
    nvgClosePath(nvg)

    -- Tail fade only at taper corners; deferred until after the single merged
    -- fill (they are separate gradient fills and must not split the shared
    -- border path). Recorded into the flat module scratch - no allocation.
    if m1 ~= 'ring' and m1 ~= 'flush' and e1 > 0 then
        local n = SB_FADES_N
        SB_FADES[n + 1], SB_FADES[n + 2], SB_FADES[n + 3] = side, c1u, c1v
        SB_FADES[n + 4], SB_FADES[n + 5], SB_FADES[n + 6] = -1, r1, e1
        SB_FADES[n + 7], SB_FADES[n + 8], SB_FADES_N = d1, f1, n + 8
    end
    if m2 ~= 'ring' and m2 ~= 'flush' and e2 > 0 then
        local n = SB_FADES_N
        SB_FADES[n + 1], SB_FADES[n + 2], SB_FADES[n + 3] = side, c2u, c2v
        SB_FADES[n + 4], SB_FADES[n + 5], SB_FADES[n + 6] = 1, r2, e2
        SB_FADES[n + 7], SB_FADES[n + 8], SB_FADES_N = d2, f2, n + 8
    end
end

--- Render individual side borders
---@param nvg NVGContextWrapper
---@param l table Layout { x, y, w, h }
function Widget:RenderPerSideBorders(nvg, l, radius, overrideColor)
    local props = self.props
    -- Default color: caller override > uniform borderColor prop > theme fallback
    local defaultColor = overrideColor or props.borderColor or Theme.Color("border")

    local x, y, w, h = l.x, l.y, l.w, l.h
    local tw = props.borderTopWidth or 0
    local bw = props.borderBottomWidth or 0
    local lw = props.borderLeftWidth or 0
    local rw = props.borderRightWidth or 0

    -- Resolve per-side colors
    local cT = tw > 0 and (props.borderTopColor or defaultColor) or nil
    local cB = bw > 0 and (props.borderBottomColor or defaultColor) or nil
    local cL = lw > 0 and (props.borderLeftColor or defaultColor) or nil
    local cR = rw > 0 and (props.borderRightColor or defaultColor) or nil

    -- Determine if we have a borderRadius that needs to be followed
    local hasRadius = radius and ((type(radius) == "number" and radius > 0) or (type(radius) == "table"))

    if hasRadius then
        -- Rounded per-side border: compound path (outer solid + inner hole)
        local uniformColor = cT or cB or cL or cR
        local isUniform = true
        if cT and not sbColorsEqual(cT, uniformColor) then isUniform = false end
        if cB and not sbColorsEqual(cB, uniformColor) then isUniform = false end
        if cL and not sbColorsEqual(cL, uniformColor) then isUniform = false end
        if cR and not sbColorsEqual(cR, uniformColor) then isUniform = false end

        if isUniform and uniformColor then
            -- Get outer radius per corner
            local oTL = type(radius) == "table" and (radius[1] or 0) or radius
            local oTR = type(radius) == "table" and (radius[2] or 0) or radius
            local oBR = type(radius) == "table" and (radius[3] or 0) or radius
            local oBL = type(radius) == "table" and (radius[4] or 0) or radius

            -- Clamp to min(w,h)/2, matching GetShapeGeometry's background clamp
            -- (CSS-equivalent for uniform radii). Without this, pill-style radii
            -- (e.g. 999) reach nvgRoundedRectVarying, whose per-axis clamp yields
            -- ELLIPTICAL corners while the background renders circular caps.
            local maxCornerR = math.min(w, h) / 2
            if oTL > maxCornerR then oTL = maxCornerR end
            if oTR > maxCornerR then oTR = maxCornerR end
            if oBR > maxCornerR then oBR = maxCornerR end
            if oBL > maxCornerR then oBL = maxCornerR end

            -- #2102: with all four sides active, the uniform border is EXACTLY the
            -- CSS donut: the border-box rounded rect minus the padding-box contour
            -- with per-corner ELLIPTICAL radii (rx = r - adjacent horizontal width,
            -- ry = r - adjacent vertical width). One continuous silhouette, zero
            -- band-to-band seams: splitting into per-side bands leaves butt-cap AA
            -- fringes on the silhouette that read as darker "joint" pixels on
            -- translucent borders. (This is NOT the old concentric-circle donut that
            -- #2100 removed - the inner corners here are the true CSS ellipses.)
            -- Partial-side combinations fall through to the band builder below.
            if tw > 0 and bw > 0 and lw > 0 and rw > 0 then
                local ix, iy = x + lw, y + tw
                local iw, ih = w - lw - rw, h - tw - bw
                nvgBeginPath(nvg)
                nvgRoundedRectVarying(nvg, x, y, w, h, oTL, oTR, oBR, oBL)
                if iw > 0 and ih > 0 then
                    -- Inner padding-box contour with elliptical corners, clamped so
                    -- adjacent corners cannot overlap along an edge
                    local rTLx, rTLy = math.max(0, oTL - lw), math.max(0, oTL - tw)
                    local rTRx, rTRy = math.max(0, oTR - rw), math.max(0, oTR - tw)
                    local rBRx, rBRy = math.max(0, oBR - rw), math.max(0, oBR - bw)
                    local rBLx, rBLy = math.max(0, oBL - lw), math.max(0, oBL - bw)
                    local kx = math.min(1,
                        iw / math.max(1e-6, rTLx + rTRx), iw / math.max(1e-6, rBLx + rBRx))
                    local ky = math.min(1,
                        ih / math.max(1e-6, rTLy + rBLy), ih / math.max(1e-6, rTRy + rBRy))
                    if kx < 1 then rTLx, rTRx, rBLx, rBRx = rTLx * kx, rTRx * kx, rBLx * kx, rBRx * kx end
                    if ky < 1 then rTLy, rTRy, rBLy, rBRy = rTLy * ky, rTRy * ky, rBLy * ky, rBRy * ky end
                    local K = 0.5522847493
                    nvgMoveTo(nvg, ix + rTLx, iy)
                    nvgLineTo(nvg, ix + iw - rTRx, iy)
                    if rTRx > 0 or rTRy > 0 then
                        nvgBezierTo(nvg, ix + iw - rTRx + K * rTRx, iy,
                            ix + iw, iy + rTRy - K * rTRy, ix + iw, iy + rTRy)
                    end
                    nvgLineTo(nvg, ix + iw, iy + ih - rBRy)
                    if rBRx > 0 or rBRy > 0 then
                        nvgBezierTo(nvg, ix + iw, iy + ih - rBRy + K * rBRy,
                            ix + iw - rBRx + K * rBRx, iy + ih, ix + iw - rBRx, iy + ih)
                    end
                    nvgLineTo(nvg, ix + rBLx, iy + ih)
                    if rBLx > 0 or rBLy > 0 then
                        nvgBezierTo(nvg, ix + rBLx - K * rBLx, iy + ih,
                            ix, iy + ih - rBLy + K * rBLy, ix, iy + ih - rBLy)
                    end
                    nvgLineTo(nvg, ix, iy + rTLy)
                    if rTLx > 0 or rTLy > 0 then
                        nvgBezierTo(nvg, ix, iy + rTLy - K * rTLy,
                            ix + rTLx - K * rTLx, iy, ix + rTLx, iy)
                    end
                    nvgClosePath(nvg)
                    nvgPathWinding(nvg, NVG_HOLE)
                end
                nvgFillColor(nvg, nvgRGBA(uniformColor[1], uniformColor[2], uniformColor[3], uniformColor[4] or 255))
                -- #2102: opt into engine-side fringe dedup for this fill (no-op for
                -- opaque colors; guards against older runtimes without the API)
                if nvgFillThinDedup then nvgFillThinDedup(nvg, 1) end
                nvgFill(nvg)
                if nvgFillThinDedup then nvgFillThinDedup(nvg, 0) end
                return
            end

            -- A single-side stroke (e.g. a {0,0,3,0} "depth" border) cannot use the
            -- concentric reduced-radius donut: the reduced inner-corner radius no longer
            -- matches the outer corner, so the donut pinches to sub-pixel width mid-arc
            -- (a visible break at the rounded corners) and the coincident inner/outer
            -- edges on the zero-width sides leak a ~1px AA fringe whose presence flips
            -- with sub-pixel phase (platform/DPR dependent).
            --
            -- CSS corner-ownership semantics (issue #2095): when the adjacent sides
            -- have zero width, the single active side owns BOTH neighbouring corners —
            -- the band wraps each corner arc. Its inner edge through a corner is
            -- ELLIPTICAL (CSS padding-box corner: full radius on the free axis,
            -- max(0, r - width) on the side axis, same corner center as the outer arc).
            --
            -- Two deliberate deviations from the ideal CSS shape, both AA-driven:
            -- * CSS tapers the band to zero exactly at the far tangent point, but a
            --   zero-thickness tip is a degenerate sliver for NanoVG — its AA fringe
            --   (extruded ~0.5px outward along edge normals) folds past the tip and
            --   deposits dark pixels OUTSIDE the silhouette. We stop the solid fill
            --   where the band is still ~W_MIN px wide (the width-based cut) and close
            --   with a tiny radial cut, invisible at 1x.
            -- * When a corner radius <= the border width (inner radius degenerates to
            --   0), the CSS inner corner is square; the band there is simply the shape
            --   clipped to the side strip (v <= width), capped along the silhouette.
            --
            -- Geometry is emitted in a canonical space (u along the edge, v inward from
            -- the outer edge) and mapped per side, so all four sides share one builder.
            -- Corner ownership (issue #2100): every rounded uniform-color combination
            -- routes through the single-side builder. A corner shared by two active
            -- sides is drawn ONCE, by the horizontal side, as the full 0-90° ring
            -- sector whose inner edge is the CSS padding-box ellipse (u-radius
            -- r - adjacentWidth, v-radius r - ownWidth, same center as the outer
            -- arc); the vertical side ends FLUSH at the corner start. Exclusive
            -- corners (adjacent side inactive) keep the wrap+taper machinery.
            -- Same-color full-alpha overlap at the seams is invisible, so the
            -- horizontal-owns-corners convention needs no sector split.

            -- #2102: all same-color bands are emitted as sub-paths of ONE fill, so
            -- the engine-side fringe dedup also covers band-to-band seam overlaps
            -- (translucent borders would otherwise composite twice at the corner
            -- seams). Vertical sides are emitted FIRST: dedup is first-wins in
            -- emission order, and at a flush seam the vertical band's long-edge
            -- fringe carries the real coverage for the outermost column, while the
            -- ring segment only grazes it with ~zero-alpha boundary fragments that
            -- must not claim the marker first.
            SB_FADES_N = 0
            nvgBeginPath(nvg)
            if lw > 0 then
                sbRenderSide(nvg, uniformColor, 'left', lw, sbModeFor('left', tw), tw,
                    sbModeFor('left', bw), bw, x, y, w, h, oTL, oTR, oBR, oBL)
            end
            if rw > 0 then
                sbRenderSide(nvg, uniformColor, 'right', rw, sbModeFor('right', tw), tw,
                    sbModeFor('right', bw), bw, x, y, w, h, oTL, oTR, oBR, oBL)
            end
            if tw > 0 then
                sbRenderSide(nvg, uniformColor, 'top', tw, sbModeFor('top', lw), lw,
                    sbModeFor('top', rw), rw, x, y, w, h, oTL, oTR, oBR, oBL)
            end
            if bw > 0 then
                sbRenderSide(nvg, uniformColor, 'bottom', bw, sbModeFor('bottom', lw), lw,
                    sbModeFor('bottom', rw), rw, x, y, w, h, oTL, oTR, oBR, oBL)
            end
            nvgFillColor(nvg, nvgRGBA(uniformColor[1], uniformColor[2], uniformColor[3], uniformColor[4] or 255))
            -- #2102: opt into engine-side fringe dedup (tail fades below run with
            -- the flag off - they rely on fringe accumulation)
            if nvgFillThinDedup then nvgFillThinDedup(nvg, 1) end
            nvgFill(nvg)
            if nvgFillThinDedup then nvgFillThinDedup(nvg, 0) end
            -- Flush deferred taper tail-fades (each re-establishes its side ctx)
            local n = 0
            while n < SB_FADES_N do
                sbSetSide(SB_FADES[n + 1], x, y, w, h)
                sbTailFade(SB_FADES[n + 2], SB_FADES[n + 3], SB_FADES[n + 4],
                    SB_FADES[n + 5], SB_FADES[n + 6], SB_FADES[n + 7], SB_FADES[n + 8])
                n = n + 8
            end
        else
            -- Multi-color: fallback to rect
            self:RenderPerSideBordersRect(nvg, x, y, w, h, tw, bw, lw, rw, cT, cB, cL, cR)
        end
    else
        -- No radius: use simple rect fills (original behavior)
        self:RenderPerSideBordersRect(nvg, x, y, w, h, tw, bw, lw, rw, cT, cB, cL, cR)
    end
end

--- Fallback: per-side borders using plain rects (no radius)
function Widget:RenderPerSideBordersRect(nvg, x, y, w, h, tw, bw, lw, rw, cT, cB, cL, cR)
    if tw > 0 and cT then
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, tw)
        nvgFillColor(nvg, nvgRGBA(cT[1], cT[2], cT[3], cT[4] or 255))
        nvgFill(nvg)
    end
    if bw > 0 and cB then
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y + h - bw, w, bw)
        nvgFillColor(nvg, nvgRGBA(cB[1], cB[2], cB[3], cB[4] or 255))
        nvgFill(nvg)
    end
    if lw > 0 and cL then
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y + tw, lw, h - tw - bw)
        nvgFillColor(nvg, nvgRGBA(cL[1], cL[2], cL[3], cL[4] or 255))
        nvgFill(nvg)
    end
    if rw > 0 and cR then
        nvgBeginPath(nvg)
        nvgRect(nvg, x + w - rw, y + tw, rw, h - tw - bw)
        nvgFillColor(nvg, nvgRGBA(cR[1], cR[2], cR[3], cR[4] or 255))
        nvgFill(nvg)
    end
end

-- ============================================================================
-- Shadow Rendering
-- ============================================================================

local function appendShapePath(nvg, geom)
    if geom.shape == "circle" then
        nvgCircle(nvg, geom.centerX, geom.centerY, geom.circleRadius)
    elseif geom.shape == "ellipse" then
        nvgEllipse(nvg, geom.centerX, geom.centerY, geom.rx, geom.ry)
    elseif geom.cornerRadii then
        local cr = geom.cornerRadii
        nvgRoundedRectVarying(nvg, geom.x, geom.y, geom.w, geom.h,
            cr[1], cr[2], cr[3], cr[4])
    elseif geom.radius > 0 then
        nvgRoundedRect(nvg, geom.x, geom.y, geom.w, geom.h, geom.radius)
    else
        nvgRect(nvg, geom.x, geom.y, geom.w, geom.h)
    end
end

local function getShadowShapeGeometry(geom, shadowX, shadowY, shadowW, shadowH, spread)
    local shadowGeom = {
        shape = geom.shape,
        x = shadowX,
        y = shadowY,
        w = shadowW,
        h = shadowH,
    }

    if geom.shape == "circle" then
        local diameter = math.min(shadowW, shadowH)
        local radius = diameter / 2
        shadowGeom.radius = radius
        shadowGeom.centerX = shadowX + shadowW / 2
        shadowGeom.centerY = shadowY + shadowH / 2
        shadowGeom.circleRadius = radius
    elseif geom.shape == "ellipse" then
        shadowGeom.radius = math.min(shadowW, shadowH) / 2
        shadowGeom.centerX = shadowX + shadowW / 2
        shadowGeom.centerY = shadowY + shadowH / 2
        shadowGeom.rx = shadowW / 2
        shadowGeom.ry = shadowH / 2
    elseif geom.cornerRadii then
        local cr = geom.cornerRadii
        shadowGeom.cornerRadii = {
            math.max(0, (cr[1] or 0) + spread),
            math.max(0, (cr[2] or 0) + spread),
            math.max(0, (cr[3] or 0) + spread),
            math.max(0, (cr[4] or 0) + spread),
        }
        shadowGeom.radius = math.max(
            shadowGeom.cornerRadii[1],
            shadowGeom.cornerRadii[2],
            shadowGeom.cornerRadii[3],
            shadowGeom.cornerRadii[4]
        )
    else
        shadowGeom.radius = math.max(0, (geom.radius or 0) + spread)
    end

    return shadowGeom
end

local function getShadowQuadrantScissor(geom, outerX, outerY, outerW, outerH, cornerIndex)
    local splitX = geom.x + geom.w * 0.5
    local splitY = geom.y + geom.h * 0.5
    local outerRight = outerX + outerW
    local outerBottom = outerY + outerH

    if cornerIndex == 1 then
        return outerX, outerY, math.max(0, splitX - outerX), math.max(0, splitY - outerY)
    elseif cornerIndex == 2 then
        return splitX, outerY, math.max(0, outerRight - splitX), math.max(0, splitY - outerY)
    elseif cornerIndex == 3 then
        return splitX, splitY, math.max(0, outerRight - splitX), math.max(0, outerBottom - splitY)
    end
    return outerX, splitY, math.max(0, splitX - outerX), math.max(0, outerBottom - splitY)
end

local function fillOuterShadow(nvg, geom, outerX, outerY, outerW, outerH, shadowPaint)
    nvgBeginPath(nvg)
    nvgRect(nvg, outerX, outerY, outerW, outerH)
    appendShapePath(nvg, geom)
    nvgPathWinding(nvg, NVG_HOLE)
    nvgFillPaint(nvg, shadowPaint)
    nvgFill(nvg)
end

local function fillHardOuterShadowRegion(nvg, geom, shadowGeom, color, x, y, w, h)
    if w <= 0 or h <= 0 then return end
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)
    nvgBeginPath(nvg)
    appendShapePath(nvg, shadowGeom)
    appendShapePath(nvg, geom)
    nvgPathWinding(nvg, NVG_HOLE)
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 50))
    nvgFill(nvg)
    nvgRestore(nvg)
end

local function renderHardOuterShadow(nvg, geom, shadowGeom, color)
    local geomCX = geom.x + geom.w / 2
    local geomCY = geom.y + geom.h / 2
    local shadowCX = shadowGeom.x + shadowGeom.w / 2
    local shadowCY = shadowGeom.y + shadowGeom.h / 2
    local dx = shadowCX - geomCX
    local dy = shadowCY - geomCY

    local clipX = math.min(geom.x, shadowGeom.x)
    local clipY = math.min(geom.y, shadowGeom.y)
    local clipRight = math.max(geom.x + geom.w, shadowGeom.x + shadowGeom.w)
    local clipBottom = math.max(geom.y + geom.h, shadowGeom.y + shadowGeom.h)

    if dy > 0 then
        fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
            clipX, geomCY, clipRight - clipX, clipBottom - geomCY)
    elseif dy < 0 then
        fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
            clipX, clipY, clipRight - clipX, geomCY - clipY)
    elseif dx > 0 then
        fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
            geomCX, clipY, clipRight - geomCX, clipBottom - clipY)
    elseif dx < 0 then
        fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
            clipX, clipY, geomCX - clipX, clipBottom - clipY)
    else
        fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
            clipX, clipY, clipRight - clipX, clipBottom - clipY)
        return
    end

    if dy ~= 0 then
        local sideY = math.max(clipY, geom.y)
        local sideBottom = math.min(clipBottom, geom.y + geom.h)
        if dy > 0 then
            sideBottom = math.min(sideBottom, geomCY)
        else
            sideY = math.max(sideY, geomCY)
        end
        local sideH = sideBottom - sideY

        if sideH > 0 then
            if clipX < geom.x then
                fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
                    clipX, sideY, geom.x - clipX, sideH)
            end

            if clipRight > geom.x + geom.w then
                fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
                    geom.x + geom.w, sideY, clipRight - (geom.x + geom.w), sideH)
            end
        end
    elseif dx ~= 0 then
        local capX = clipX
        local capRight = clipRight
        if dx > 0 then
            capRight = math.min(capRight, geomCX)
        else
            capX = math.max(capX, geomCX)
        end
        local capW = capRight - capX

        if capW > 0 then
            if clipY < geom.y then
                fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
                    capX, clipY, capW, geom.y - clipY)
            end

            if clipBottom > geom.y + geom.h then
                fillHardOuterShadowRegion(nvg, geom, shadowGeom, color,
                    capX, geom.y + geom.h, capW, clipBottom - (geom.y + geom.h))
            end
        end
    end
end

local function renderOuterShadow(nvg, geom, shadowX, shadowY, shadowW, shadowH, spread, sblur, color)
    local outerX = shadowX - sblur * 2
    local outerY = shadowY - sblur * 2
    local outerW = shadowW + sblur * 4
    local outerH = shadowH + sblur * 4

    if sblur <= 0 then
        local shadowGeom = getShadowShapeGeometry(geom, shadowX, shadowY, shadowW, shadowH, spread)
        renderHardOuterShadow(nvg, geom, shadowGeom, color)
        return
    end

    -- Gaussian (erf) falloff derives the edge from the true SDF, so it takes the real corner
    -- radius. The linear fallback needs +sblur*0.5 to match that visual rounding.
    local radiusFudge = _hasBoxGradientGaussian and 0 or sblur * 0.5

    if geom.cornerRadii then
        for cornerIndex = 1, 4 do
            local cornerRadius = math.max(0, (geom.cornerRadii[cornerIndex] or 0) + spread)
            local shadowPaint = _nvgBoxGradientGaussian(nvg,
                shadowX, shadowY, shadowW, shadowH,
                cornerRadius + radiusFudge, sblur,
                nvgRGBA(color[1], color[2], color[3], color[4] or 50),
                nvgRGBA(0, 0, 0, 0)
            )
            local scissorX, scissorY, scissorW, scissorH = getShadowQuadrantScissor(
                geom, outerX, outerY, outerW, outerH, cornerIndex)
            if scissorW > 0 and scissorH > 0 then
                nvgSave(nvg)
                nvgIntersectScissor(nvg, scissorX, scissorY, scissorW, scissorH)
                fillOuterShadow(nvg, geom, outerX, outerY, outerW, outerH, shadowPaint)
                nvgRestore(nvg)
            end
        end
        return
    end

    local shadowR = math.max(0, (geom.radius or 0) + spread)
    local shadowPaint = _nvgBoxGradientGaussian(nvg,
        shadowX, shadowY, shadowW, shadowH,
        shadowR + radiusFudge, sblur,
        nvgRGBA(color[1], color[2], color[3], color[4] or 50),
        nvgRGBA(0, 0, 0, 0)
    )
    fillOuterShadow(nvg, geom, outerX, outerY, outerW, outerH, shadowPaint)
end

--- Render box shadow
--- NOTE: All values are in BASE PIXELS - nvgScale handles conversion to screen pixels
---@param nvg NVGContextWrapper
---@param l table|nil Layout { x, y, w, h }, uses GetAbsoluteLayout if nil
---@param shapeOverride string|nil Shape override
function Widget:RenderShadow(nvg, l, shapeOverride)
    local props = self.props
    local rp = self.renderProps_
    local blur = rp.shadowBlur or props.shadowBlur
    if not blur or blur <= 0 then return end

    l = l or self:GetAbsoluteLayout()
    -- No scale multiplication needed - nvgScale in UI.Render handles it

    local sx = rp.shadowOffsetX or props.shadowX or 0
    local sy = rp.shadowOffsetY or props.shadowY or 0
    local sblur = blur
    local color = rp.shadowColor or props.shadowColor or {0, 0, 0, 50}
    local radius = rp.borderRadius or props.borderRadius or 0
    local shape = shapeOverride or props.shape

    -- Check for per-corner border radius
    local hasTL = props.borderRadiusTopLeft
    local hasTR = props.borderRadiusTopRight
    local hasBR = props.borderRadiusBottomRight
    local hasBL = props.borderRadiusBottomLeft
    if hasTL or hasTR or hasBR or hasBL then
        local base = type(radius) == "number" and radius or 0
        radius = { hasTL or base, hasTR or base, hasBR or base, hasBL or base }
    end

    -- Get shape geometry
    local geom = self:GetShapeGeometry(l, shape, radius)

    renderOuterShadow(nvg, geom, geom.x + sx, geom.y + sy, geom.w, geom.h, 0, sblur, color)
end

-- ============================================================================
-- Enhanced Box Shadow Rendering
-- ============================================================================

--- Render enhanced box shadows (spread / inset / multiple)
---@param nvg NVGContextWrapper
---@param geom table Shape geometry
---@param shadows table Array of shadow definitions { x, y, blur, spread, color, inset }
---@param insetFilter boolean|nil nil draws all; false draws outer only; true draws inset only
function Widget:RenderBoxShadows(nvg, geom, shadows, insetFilter)
    for i = 1, #shadows do
        local s = shadows[i]
        local sx = s.x or 0
        local sy = s.y or 0
        local sblur = s.blur or 0
        local spread = s.spread or 0
        local color = s.color or {0, 0, 0, 50}
        local inset = s.inset
        local shouldDraw = insetFilter == nil
            or (insetFilter == true and inset)
            or (insetFilter == false and not inset)

        if shouldDraw and inset then
            -- Draw inset shadow using inverted box gradient
            local innerX = geom.x + sx + spread
            local innerY = geom.y + sy + spread
            local innerW = geom.w - spread * 2
            local innerH = geom.h - spread * 2

            if innerW > 0 and innerH > 0 then
                local sideClipped = false
                if s.side == "bottom" then
                    local sideRadius = geom.radius or 0
                    if geom.cornerRadii then
                        sideRadius = math.max(geom.cornerRadii[3] or 0, geom.cornerRadii[4] or 0)
                    end
                    local extent = math.max(math.abs(sy) + math.abs(spread) + sblur * 2, sideRadius + math.abs(sy))
                    nvgSave(nvg)
                    nvgIntersectScissor(nvg, geom.x, geom.y + geom.h - extent, geom.w, extent)
                    sideClipped = true
                end

                if geom.cornerRadii then
                    for cornerIndex = 1, 4 do
                        local innerR = math.max(0, (geom.cornerRadii[cornerIndex] or 0) - spread)
                        local shadowPaint = nvgBoxGradient(nvg,
                            innerX, innerY, innerW, innerH,
                            innerR + sblur * 0.5, sblur,
                            nvgRGBA(0, 0, 0, 0),
                            nvgRGBA(color[1], color[2], color[3], color[4] or 50)
                        )
                        local scissorX, scissorY, scissorW, scissorH = getShadowQuadrantScissor(
                            geom, geom.x, geom.y, geom.w, geom.h, cornerIndex)
                        if scissorW > 0 and scissorH > 0 then
                            nvgSave(nvg)
                            nvgIntersectScissor(nvg, scissorX, scissorY, scissorW, scissorH)
                            nvgBeginPath(nvg)
                            appendShapePath(nvg, geom)
                            nvgFillPaint(nvg, shadowPaint)
                            nvgFill(nvg)
                            nvgRestore(nvg)
                        end
                    end
                else
                    local innerR = math.max(0, (geom.radius or 0) - spread)
                    local shadowPaint = nvgBoxGradient(nvg,
                        innerX, innerY, innerW, innerH,
                        innerR + sblur * 0.5, sblur,
                        nvgRGBA(0, 0, 0, 0),
                        nvgRGBA(color[1], color[2], color[3], color[4] or 50)
                    )
                    nvgBeginPath(nvg)
                    appendShapePath(nvg, geom)
                    nvgFillPaint(nvg, shadowPaint)
                    nvgFill(nvg)
                end

                if sideClipped then
                    nvgRestore(nvg)
                end
            end
        elseif shouldDraw then
            -- Outer shadow: expanded box gradient with hole cutout
            local shadowX = geom.x + sx - spread
            local shadowY = geom.y + sy - spread
            local shadowW = geom.w + spread * 2
            local shadowH = geom.h + spread * 2
            renderOuterShadow(nvg, geom, shadowX, shadowY, shadowW, shadowH, spread, sblur, color)
        end
    end
end

local function findBottomHardInsetShadow(shadows)
    if not shadows then return nil end
    for i = 1, #shadows do
        local s = shadows[i]
        if s.curve == "microVolume" and s.inset and s.side == "bottom" and (s.blur or 0) <= 0 then
            local depth = math.abs(s.y or 0) + math.abs(s.spread or 0)
            local color = s.color or {0, 0, 0, 50}
            if depth > 0 and (color[4] or 255) > 0 then
                return { depth = depth, color = color }
            end
        end
    end
    return nil
end

local function blendColorOver(base, over)
    local alpha = (over[4] or 255) / 255
    local inv = 1 - alpha
    return {
        math.floor((over[1] or 0) * alpha + (base[1] or 0) * inv + 0.5),
        math.floor((over[2] or 0) * alpha + (base[2] or 0) * inv + 0.5),
        math.floor((over[3] or 0) * alpha + (base[3] or 0) * inv + 0.5),
        base[4] or 255,
    }
end

local function renderBottomHardInsetTopPlate(nvg, l, geom, depth, color)
    if geom.shape ~= "rounded" and geom.shape ~= "square" then return false end

    local x, y, w, h = l.x, l.y, l.w, l.h
    if w <= 0 or h <= 0 then return false end

    local bottom = y + h
    local topY = bottom - depth
    local rTL, rTR, rBR, rBL
    if geom.cornerRadii then
        rTL = geom.cornerRadii[1] or 0
        rTR = geom.cornerRadii[2] or 0
        rBR = geom.cornerRadii[3] or 0
        rBL = geom.cornerRadii[4] or 0
    else
        local r = geom.radius or 0
        rTL, rTR, rBR, rBL = r, r, r, r
    end

    if rTL <= 0 and rTR <= 0 and rBR <= 0 and rBL <= 0 then
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, math.max(0, h - depth))
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
        nvgFill(nvg)
        return true
    end

    local maxTopRadius = math.max(0, math.min(w, h - depth) / 2)
    rTL = math.min(rTL, maxTopRadius)
    rTR = math.min(rTR, maxTopRadius)

    local leftEnd = math.max(0, math.min(rBL, w / 2))
    local rightEnd = math.max(0, math.min(rBR, w / 2))
    local leftStartY = math.min(topY, bottom - rBL + depth / 6)
    local rightStartY = math.min(topY, bottom - rBR + depth / 6)
    local leftDelta = math.max(0, topY - leftStartY)
    local rightDelta = math.max(0, topY - rightStartY)
    local k = 0.5522847498

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x + rTL, y)
    nvgLineTo(nvg, x + w - rTR, y)
    if rTR > 0 then
        nvgBezierTo(nvg,
            x + w - rTR + k * rTR, y,
            x + w, y + rTR - k * rTR,
            x + w, y + rTR)
    else
        nvgLineTo(nvg, x + w, y)
    end
    nvgLineTo(nvg, x + w, rightStartY)
    if rightEnd > 0 then
        nvgBezierTo(nvg,
            x + w, rightStartY + rightDelta * 0.45,
            x + w - rightEnd * 0.36, topY - depth / 12,
            x + w - rightEnd, topY)
    else
        nvgLineTo(nvg, x + w, topY)
    end
    nvgLineTo(nvg, x + leftEnd, topY)
    if leftEnd > 0 then
        nvgBezierTo(nvg,
            x + leftEnd * 0.36, topY - depth / 12,
            x, leftStartY + leftDelta * 0.45,
            x, leftStartY)
    else
        nvgLineTo(nvg, x, topY)
    end
    nvgLineTo(nvg, x, y + rTL)
    if rTL > 0 then
        nvgBezierTo(nvg,
            x, y + rTL - k * rTL,
            x + rTL - k * rTL, y,
            x + rTL, y)
    else
        nvgLineTo(nvg, x, y)
    end
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgFill(nvg)
    return true
end

-- ============================================================================
-- Background Image Rendering
-- ============================================================================

--- Render background image with fit mode
---@param nvg NVGContextWrapper
---@param imagePath string Image file path
---@param l table|nil Layout { x, y, w, h }
---@param fit string|nil "cover", "contain", "fill", "sliced"
---@param slice table|nil Nine-slice insets {top, right, bottom, left}
---@param radius number|nil Border radius
---@param tint RGBAColor|nil Tint color (multiplicative blend)
---@param opacity number|nil Image opacity, 0-1
function Widget:RenderBackgroundImage(nvg, imagePath, l, fit, slice, radius, tint, opacity)
    if not imagePath or imagePath == "" then return end

    l = l or self:GetAbsoluteLayout()
    fit = fit or "fill"
    radius = radius or 0
    opacity = opacity ~= nil and opacity or 1

    -- Get image handle from cache
    local imgHandle = ImageCache.Get(imagePath)
    if not imgHandle or imgHandle <= 0 then return end

    local imgW, imgH = ImageCache.GetSize(imagePath)
    if imgW <= 0 or imgH <= 0 then return end

    if fit == "sliced" and slice then
        self:RenderSlicedImage(nvg, imgHandle, imgW, imgH, l, slice, radius, tint, opacity)
    else
        self:RenderFitImage(nvg, imgHandle, imgW, imgH, l, fit, radius, tint, opacity)
    end
end

--- Render image with cover/contain/fill fit
---@param nvg NVGContextWrapper
---@param imgHandle number Image handle
---@param imgW number Image width
---@param imgH number Image height
---@param l table Layout { x, y, w, h }
---@param fit string "cover", "contain", "fill"
---@param radius number|table Border radius
---@param tint RGBAColor|nil Tint color (multiplicative blend)
---@param opacity number|nil Image opacity, 0-1
function Widget:RenderFitImage(nvg, imgHandle, imgW, imgH, l, fit, radius, tint, opacity)
    local drawX, drawY, drawW, drawH = l.x, l.y, l.w, l.h
    local imgRatio = imgW / imgH
    local boxRatio = l.w / l.h

    if fit == "cover" then
        -- Fill container, may crop
        if imgRatio > boxRatio then
            -- Image is wider, fit height
            drawH = l.h
            drawW = l.h * imgRatio
            drawX = l.x - (drawW - l.w) / 2
            drawY = l.y
        else
            -- Image is taller, fit width
            drawW = l.w
            drawH = l.w / imgRatio
            drawX = l.x
            drawY = l.y - (drawH - l.h) / 2
        end
    elseif fit == "contain" then
        -- Fit inside container, may have empty space
        if imgRatio > boxRatio then
            -- Image is wider, fit width
            drawW = l.w
            drawH = l.w / imgRatio
            drawX = l.x
            drawY = l.y + (l.h - drawH) / 2
        else
            -- Image is taller, fit height
            drawH = l.h
            drawW = l.h * imgRatio
            drawX = l.x + (l.w - drawW) / 2
            drawY = l.y
        end
    end
    -- fit == "fill": use l.x, l.y, l.w, l.h directly (stretch)

    -- Create image pattern (with optional tint for multiplicative color blend)
    local imgPaint
    opacity = opacity ~= nil and opacity or 1
    if tint then
        imgPaint = nvgImagePatternTinted(nvg, drawX, drawY, drawW, drawH, 0, imgHandle,
            nvgRGBA(tint[1], tint[2], tint[3], math.floor((tint[4] or 255) * opacity)))
    else
        imgPaint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, imgHandle, opacity)
    end

    if l.shape or type(radius) == "table" then
        local geom = l.shape and l or self:GetShapeGeometry(l, nil, radius)
        self:CreateShapePath(nvg, geom)
    else
        radius = radius or 0
        nvgBeginPath(nvg)
        if radius > 0 then
            nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, radius)
        else
            nvgRect(nvg, l.x, l.y, l.w, l.h)
        end
    end
    nvgFillPaint(nvg, imgPaint)
    nvgFill(nvg)
end

--- Render nine-sliced image
--- NOTE: All values are in BASE PIXELS - nvgScale handles conversion to screen pixels
---@param nvg NVGContextWrapper
---@param imgHandle number Image handle
---@param imgW number Image width
---@param imgH number Image height
---@param l table Layout { x, y, w, h }
---@param slice table Nine-slice insets {top, right, bottom, left}
---@param radius number Border radius (ignored for sliced)
---@param tint RGBAColor|nil Tint color (multiplicative blend)
---@param opacity number|nil Image opacity, 0-1
function Widget:RenderSlicedImage(nvg, imgHandle, imgW, imgH, l, slice, radius, tint, opacity)
    -- No scale multiplication needed - nvgScale in UI.Render handles it
    local top = slice[1] or 0
    local right = slice[2] or 0
    local bottom = slice[3] or 0
    local left = slice[4] or 0

    -- Source slice sizes (in image pixels)
    local srcTop = slice[1] or 0
    local srcRight = slice[2] or 0
    local srcBottom = slice[3] or 0
    local srcLeft = slice[4] or 0

    -- Calculate regions
    local x, y, w, h = l.x, l.y, l.w, l.h
    local centerW = w - left - right
    local centerH = h - top - bottom
    local srcCenterW = imgW - srcLeft - srcRight
    local srcCenterH = imgH - srcTop - srcBottom

    -- Pre-compute tint color once (outside loop for 9 draw calls)
    opacity = opacity ~= nil and opacity or 1
    local tintColor = tint and nvgRGBA(tint[1], tint[2], tint[3], math.floor((tint[4] or 255) * opacity)) or nil

    -- Helper to draw a slice
    local function drawSlice(dx, dy, dw, dh, sx, sy, sw, sh)
        if dw <= 0 or dh <= 0 or sw <= 0 or sh <= 0 then return end

        -- Calculate UV coordinates
        local u0 = sx / imgW
        local v0 = sy / imgH
        local u1 = (sx + sw) / imgW
        local v1 = (sy + sh) / imgH

        -- Create pattern for this slice
        -- Map source region to destination region
        local scaleX = dw / sw
        local scaleY = dh / sh
        local ox = dx - sx * scaleX
        local oy = dy - sy * scaleY

        local imgPaint
        if tintColor then
            imgPaint = nvgImagePatternTinted(nvg, ox, oy, imgW * scaleX, imgH * scaleY, 0, imgHandle, tintColor)
        else
            imgPaint = nvgImagePattern(nvg, ox, oy, imgW * scaleX, imgH * scaleY, 0, imgHandle, opacity)
        end

        nvgBeginPath(nvg)
        nvgRect(nvg, dx, dy, dw, dh)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    end

    -- Draw 9 slices
    -- Top-left corner
    drawSlice(x, y, left, top, 0, 0, srcLeft, srcTop)
    -- Top edge
    drawSlice(x + left, y, centerW, top, srcLeft, 0, srcCenterW, srcTop)
    -- Top-right corner
    drawSlice(x + left + centerW, y, right, top, imgW - srcRight, 0, srcRight, srcTop)

    -- Left edge
    drawSlice(x, y + top, left, centerH, 0, srcTop, srcLeft, srcCenterH)
    -- Center
    drawSlice(x + left, y + top, centerW, centerH, srcLeft, srcTop, srcCenterW, srcCenterH)
    -- Right edge
    drawSlice(x + left + centerW, y + top, right, centerH, imgW - srcRight, srcTop, srcRight, srcCenterH)

    -- Bottom-left corner
    drawSlice(x, y + top + centerH, left, bottom, 0, imgH - srcBottom, srcLeft, srcBottom)
    -- Bottom edge
    drawSlice(x + left, y + top + centerH, centerW, bottom, srcLeft, imgH - srcBottom, srcCenterW, srcBottom)
    -- Bottom-right corner
    drawSlice(x + left + centerW, y + top + centerH, right, bottom, imgW - srcRight, imgH - srcBottom, srcRight, srcBottom)
end

--- Render complete background (shadow + color + image + border)
--- Convenience method for subclasses
--- NOTE: All values are in BASE PIXELS - nvgScale handles conversion to screen pixels
---@param nvg NVGContextWrapper
---@param overrides table|nil Override props { backgroundColor, backgroundImage, shape, ... }
function Widget:RenderFullBackground(nvg, overrides)
    local props = self.props
    local rp = self.renderProps_
    overrides = overrides or {}

    local l = self:GetAbsoluteLayout()
    -- No scale multiplication needed - nvgScale in UI.Render handles it
    -- Use transition-aware values: renderProps_ (interpolated) > overrides > props
    local radius = overrides.borderRadius or (rp.borderRadius or props.borderRadius) or 0
    local shape = overrides.shape or props.shape

    -- clipPath overrides shape for the widget's own content rendering
    -- Supports: "circle", "ellipse", { type = "circle", radius = N }, { type = "ellipse", rx = N, ry = N }
    local clipPath = props.clipPath
    if clipPath then
        if clipPath == "circle" then
            shape = "circle"
        elseif clipPath == "ellipse" then
            shape = "ellipse"
        elseif type(clipPath) == "table" then
            if clipPath.type == "circle" then
                shape = "circle"
            elseif clipPath.type == "ellipse" then
                shape = "ellipse"
            end
        end
    end

    radius = Widget.ResolveCornerRadius(radius, props)

    -- Get shape geometry
    local geom = self:GetShapeGeometry(l, shape, radius)

    -- Apply custom clipPath dimensions if specified
    if clipPath and type(clipPath) == "table" then
        if clipPath.type == "circle" and clipPath.radius and geom.shape == "circle" then
            geom.circleRadius = clipPath.radius
            geom.radius = clipPath.radius
        elseif clipPath.type == "ellipse" and geom.shape == "ellipse" then
            if clipPath.rx then geom.rx = clipPath.rx end
            if clipPath.ry then geom.ry = clipPath.ry end
        end
    end

    -- Precompute background inputs so shadow rendering can skip inset shadows
    -- that are handled by the specialized background layering below.
    local bgColor = overrides.backgroundColor or rp.backgroundColor or props.backgroundColor
    local gradient = overrides.backgroundGradient or props.backgroundGradient
    local bottomHardInset = nil
    local renderBottomHardInsetAsLayer = false

    -- 1. Shadow (boxShadow array takes precedence over legacy shadowBlur props)
    local boxShadow = nil
    if not overrides.skipShadow then
        boxShadow = overrides.boxShadow
        if boxShadow == nil then
            boxShadow = props.boxShadow
        end
        bottomHardInset = boxShadow and boxShadow ~= false and findBottomHardInsetShadow(boxShadow) or nil
        renderBottomHardInsetAsLayer = bottomHardInset and bgColor and not gradient
        if boxShadow == false then
            -- Explicitly disabled.
        elseif boxShadow then
            self:RenderBoxShadows(nvg, geom, boxShadow, renderBottomHardInsetAsLayer and false or nil)
        else
            self:RenderShadow(nvg, l, shape)
        end
    end

    -- 1b. Backdrop blur approximation (renders before background color)
    local backdropBlur = props.backdropBlur
    if backdropBlur and backdropBlur > 0 then
        self:RenderBackdropBlur(nvg, geom, backdropBlur)
    end

    -- Render order: bg → gradient → image → border (border on top = CSS border-box).
    -- A semi-transparent border thus composites over the widget's own fill, not the
    -- page behind it. Per-side borders with radius are drawn as a compound donut
    -- (RenderPerSideBorders), so there is no padding-box/inset special case.
    local hasPerSide = (props.borderTopWidth or 0) > 0 or (props.borderBottomWidth or 0) > 0
        or (props.borderLeftWidth or 0) > 0 or (props.borderRightWidth or 0) > 0

    if bgColor then
        if renderBottomHardInsetAsLayer then
            local depth = math.min(bottomHardInset.depth, l.h)
            local baseColor = blendColorOver(bgColor, bottomHardInset.color)
            self:CreateShapePath(nvg, geom)
            nvgFillColor(nvg, nvgRGBA(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 255))
            nvgFill(nvg)

            if not renderBottomHardInsetTopPlate(nvg, l, geom, depth, bgColor) then
                local plateRect = {
                    x = l.x,
                    y = l.y,
                    w = l.w,
                    h = math.max(0, l.h - depth),
                }
                local plateGeom = self:GetShapeGeometry(plateRect, shape, radius)
                self:CreateShapePath(nvg, plateGeom)
                nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
                nvgFill(nvg)
            end
        else
            self:CreateShapePath(nvg, geom)
            nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
            nvgFill(nvg)
        end
    end

    -- 2b. Background gradient (renders on top of solid color)
    if gradient then
        self:RenderGradientBackground(nvg, geom, gradient)
    end

    -- 3. Background image
    local bgImage = overrides.backgroundImage or props.backgroundImage
    if bgImage then
        local fit = overrides.backgroundFit or props.backgroundFit or "fill"
        local slice = overrides.backgroundSlice or props.backgroundSlice
        local tint = overrides.imageTint or rp.imageTint or props.imageTint
        local imageOpacity = overrides.backgroundImageOpacity
        if imageOpacity == nil then
            imageOpacity = rp.backgroundImageOpacity or props.backgroundImageOpacity
        end
        if geom.shape == "circle" then
            self:RenderBackgroundImage(nvg, bgImage, geom, fit, slice, geom.radius, tint, imageOpacity)
        else
            self:RenderBackgroundImage(nvg, bgImage, l, fit, slice, geom.radius, tint, imageOpacity)
        end
    end

    -- 4. Border (on top of bg/gradient/image)
    if hasPerSide then
        -- Per-side: rounded → compound donut; no-radius → rect fills.
        self:RenderPerSideBorders(nvg, l, radius, overrides.borderColor)
    else
        -- Uniform border
        local borderColor = overrides.borderColor or rp.borderColor or props.borderColor
        local borderWidth = overrides.borderWidth or rp.borderWidth or props.borderWidth or 0
        if not borderColor and borderWidth > 0 then
            borderColor = Theme.Color("border")
        end
        if borderColor and borderWidth > 0 then
            local borderRect, borderRadius = borderAlignedRect(
                l,
                radius,
                borderWidth,
                overrides.borderAlign or props.borderAlign or "center"
            )
            local borderGeom = self:GetShapeGeometry(borderRect, shape, borderRadius)
            self:CreateShapePath(nvg, borderGeom)
            nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
            nvgStrokeWidth(nvg, borderWidth)
            nvgStroke(nvg)
        end
    end
end

-- ============================================================================
-- Hit Testing
-- ============================================================================

--- Hit test - check if point is inside widget
--- Respects shape property for accurate hit detection
---@param x number
---@param y number
---@return boolean
function Widget:HitTest(x, y)
    local l = self:GetAbsoluteLayoutForHitTest()

    -- Guard against NaN dimensions (uncalculated Yoga nodes)
    -- Must be checked before any arithmetic to avoid NaN propagation
    if l.w ~= l.w or l.h ~= l.h or l.x ~= l.x or l.y ~= l.y then
        return false
    end

    -- For circle shape, use distance-based hit test
    if self.props.shape == "circle" then
        local diameter = math.min(l.w, l.h)
        local radius = diameter / 2
        local centerX = l.x + l.w / 2
        local centerY = l.y + l.h / 2
        local dx = x - centerX
        local dy = y - centerY
        return (dx * dx + dy * dy) <= (radius * radius)
    end

    -- Default: rectangular hit test
    return x >= l.x and x <= l.x + l.w and y >= l.y and y <= l.y + l.h
end

--- Dispatch event to registered listeners (via OnEvent).
---@param eventName string
---@param ... any Arguments to pass to handlers
local function dispatchEvent(self, eventName, ...)
    local listeners = self.eventListeners_
    if not listeners then return end
    local list = listeners[eventName]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

-- ============================================================================
-- Pointer Events (Unified - cross-platform)
-- ============================================================================

--- Called when pointer enters the widget
---@param event PointerEvent
function Widget:OnPointerEnter(event)
    if self.props.onPointerEnter then
        self.props.onPointerEnter(event, self)
    end
    dispatchEvent(self, "pointerenter", event, self)
    self:OnMouseEnter()
end

--- Called when pointer leaves the widget
---@param event PointerEvent
function Widget:OnPointerLeave(event)
    if self.props.onPointerLeave then
        self.props.onPointerLeave(event, self)
    end
    dispatchEvent(self, "pointerleave", event, self)
    self:OnMouseLeave()
end

--- Called when pointer is pressed down
---@param event PointerEvent
function Widget:OnPointerDown(event)
    dispatchEvent(self, "pointerdown", event, self)
    self:OnMouseDown(event.x, event.y, event.button)
    if self.props.onPointerDown then
        self.props.onPointerDown(event, self)
    elseif self.parent then
        self.parent:OnPointerDown(event)
    end
end

--- Called when pointer is released
---@param event PointerEvent
function Widget:OnPointerUp(event)
    dispatchEvent(self, "pointerup", event, self)
    self:OnMouseUp(event.x, event.y, event.button)
    if self.props.onPointerUp then
        self.props.onPointerUp(event, self)
    elseif self.parent then
        self.parent:OnPointerUp(event)
    end
end

--- Called when pointer moves over widget
---@param event PointerEvent
function Widget:OnPointerMove(event)
    if self.props.onPointerMove then
        self.props.onPointerMove(event, self)
    end
    dispatchEvent(self, "pointermove", event, self)
end

--- Called when pointer interaction is cancelled
---@param event PointerEvent
function Widget:OnPointerCancel(event)
    if self.state and self.state.pressed then
        self:SetState({ pressed = false })
    end
    if self.props.onPointerCancel then
        self.props.onPointerCancel(event, self)
    end
    dispatchEvent(self, "pointercancel", event, self)
end

-- ============================================================================
-- Legacy Mouse Events (for backward compatibility)
-- ============================================================================

--- Called when mouse enters the widget (legacy)
function Widget:OnMouseEnter()
    -- Override in subclass
end

--- Called when mouse leaves the widget (legacy)
function Widget:OnMouseLeave()
    -- Override in subclass
end

--- Called when mouse button is pressed (legacy)
---@param x number
---@param y number
---@param button number
function Widget:OnMouseDown(x, y, button)
    -- Override in subclass
end

--- Called when mouse button is released (legacy)
---@param x number
---@param y number
---@param button number
function Widget:OnMouseUp(x, y, button)
    -- Override in subclass
end

-- ============================================================================
-- Click Event
-- ============================================================================

--- Called when widget is clicked/tapped
---@param event PointerEvent|nil
function Widget:OnClick(event)
    dispatchEvent(self, "click", self, event)
    if self.props.onClick then
        self.props.onClick(self, event)
    elseif self.parent then
        self.parent:OnClick(event)
    end
end

--- Dispatch event to all listeners registered via OnEvent().
--- Exposed as a method so subclasses can call it without accessing the local dispatchEvent.
---@param eventName string
---@param ... any Arguments passed to listeners
function Widget:DispatchEvent(eventName, ...)
    dispatchEvent(self, eventName, ...)
end

-- ============================================================================
-- Gesture Events
-- ============================================================================

--- Called on tap gesture
---@param event GestureEvent
function Widget:OnTap(event)
    dispatchEvent(self, "tap", event, self)
    if self.props.onTap then
        self.props.onTap(event, self)
    elseif self.parent then
        self.parent:OnTap(event)
    end
end

--- Called on double tap gesture
---@param event GestureEvent
function Widget:OnDoubleTap(event)
    dispatchEvent(self, "doubletap", event, self)
    if self.props.onDoubleTap then
        self.props.onDoubleTap(event, self)
    elseif self.parent then
        self.parent:OnDoubleTap(event)
    end
end

--- Called when long press starts
---@param event GestureEvent
function Widget:OnLongPressStart(event)
    dispatchEvent(self, "longpressstart", event, self)
    if self.props.onLongPressStart or self.props.onLongPress then
        if self.props.onLongPressStart then
            self.props.onLongPressStart(event, self)
        end
        if self.props.onLongPress then
            self.props.onLongPress(event, self)
        end
    elseif self.parent then
        self.parent:OnLongPressStart(event)
    end
end

--- Called when long press ends
---@param event GestureEvent
function Widget:OnLongPressEnd(event)
    dispatchEvent(self, "longpressend", event, self)
    if self.props.onLongPressEnd then
        self.props.onLongPressEnd(event, self)
    elseif self.parent then
        self.parent:OnLongPressEnd(event)
    end
end

--- Called on swipe gesture
---@param event GestureEvent
function Widget:OnSwipe(event)
    dispatchEvent(self, "swipe", event, self)
    local hasHandler = self.props.onSwipe
        or (event.direction == "left" and self.props.onSwipeLeft)
        or (event.direction == "right" and self.props.onSwipeRight)
        or (event.direction == "up" and self.props.onSwipeUp)
        or (event.direction == "down" and self.props.onSwipeDown)

    if hasHandler then
        if self.props.onSwipe then
            self.props.onSwipe(event, self)
        end
        -- Call direction-specific handlers
        if event.direction == "left" and self.props.onSwipeLeft then
            self.props.onSwipeLeft(event, self)
        elseif event.direction == "right" and self.props.onSwipeRight then
            self.props.onSwipeRight(event, self)
        elseif event.direction == "up" and self.props.onSwipeUp then
            self.props.onSwipeUp(event, self)
        elseif event.direction == "down" and self.props.onSwipeDown then
            self.props.onSwipeDown(event, self)
        end
    elseif self.parent then
        self.parent:OnSwipe(event)
    end
end

--- Called when pan gesture starts
---@param event GestureEvent
function Widget:OnPanStart(event)
    if self.props.onPanStart then
        self.props.onPanStart(event, self)
    end
    dispatchEvent(self, "panstart", event, self)
end

--- Called during pan gesture
---@param event GestureEvent
function Widget:OnPanMove(event)
    if self.props.onPanMove then
        self.props.onPanMove(event, self)
    end
    if self.props.onPan then
        self.props.onPan(event, self)
    end
    dispatchEvent(self, "panmove", event, self)
end

--- Called when pan gesture ends
---@param event GestureEvent
function Widget:OnPanEnd(event)
    if self.props.onPanEnd then
        self.props.onPanEnd(event, self)
    end
    dispatchEvent(self, "panend", event, self)
end

--- Called when pinch gesture starts (multi-touch)
---@param event GestureEvent
function Widget:OnPinchStart(event)
    if self.props.onPinchStart then
        self.props.onPinchStart(event, self)
    end
    dispatchEvent(self, "pinchstart", event, self)
end

--- Called during pinch gesture
---@param event GestureEvent
function Widget:OnPinchMove(event)
    if self.props.onPinchMove then
        self.props.onPinchMove(event, self)
    end
    if self.props.onPinch then
        self.props.onPinch(event, self)
    end
    dispatchEvent(self, "pinchmove", event, self)
end

--- Called when pinch gesture ends
---@param event GestureEvent
function Widget:OnPinchEnd(event)
    if self.props.onPinchEnd then
        self.props.onPinchEnd(event, self)
    end
    dispatchEvent(self, "pinchend", event, self)
end

-- ============================================================================
-- Focus Events
-- ============================================================================

--- Called when widget receives focus
function Widget:OnFocus()
    if self.props.onFocus then
        self.props.onFocus(self)
    end
    dispatchEvent(self, "focus", self)
end

--- Called when widget loses focus
function Widget:OnBlur()
    if self.props.onBlur then
        self.props.onBlur(self)
    end
    dispatchEvent(self, "blur", self)
end

-- ============================================================================
-- Event Listener API (imperative, post-construction)
-- ============================================================================

--- Register an event listener.
--- Event names: "pointerenter", "pointerleave", "pointerdown", "pointerup",
--- "pointermove", "pointercancel", "click", "tap", "doubletap",
--- "longpressstart", "longpressend", "swipe", "panstart", "panmove", "panend",
--- "pinchstart", "pinchmove", "pinchend", "focus", "blur"
---@param eventName string Event name (lowercase)
---@param handler function Callback function (receives same args as the OnXxx method)
---@return Widget self for chaining
function Widget:OnEvent(eventName, handler)
    if not self.eventListeners_ then
        self.eventListeners_ = {}
    end
    local list = self.eventListeners_[eventName]
    if not list then
        list = {}
        self.eventListeners_[eventName] = list
    end
    list[#list + 1] = handler
    return self
end

--- Remove an event listener. If handler is nil, removes all listeners for the event.
---@param eventName string Event name (lowercase)
---@param handler function|nil Specific handler to remove, or nil to remove all
---@return Widget self for chaining
function Widget:OffEvent(eventName, handler)
    if not self.eventListeners_ then return self end
    if not handler then
        self.eventListeners_[eventName] = nil
        return self
    end
    local list = self.eventListeners_[eventName]
    if list then
        for i = #list, 1, -1 do
            if list[i] == handler then
                table.remove(list, i)
            end
        end
    end
    return self
end

-- ============================================================================
-- State (for Stateful widgets)
-- ============================================================================

--- Update state and trigger re-render
---@param newState table
function Widget:SetState(newState)
    for k, v in pairs(newState) do
        self.state[k] = v
    end
    -- Note: actual re-render is handled by UI manager
end

--- Get current state
---@return table
function Widget:GetState()
    return self.state
end

-- ============================================================================
-- Utility
-- ============================================================================

--- Get prop value with default
---@param key string
---@param default any
---@return any
function Widget:GetProp(key, default)
    local value = self.props[key]
    if value == nil then
        return default
    end
    return value
end

--- Check if widget is stateful (has internal state that changes)
---@return boolean
function Widget:IsStateful()
    return false  -- Override in stateful widgets
end

-- ============================================================================
-- Layout Overflow Detection (Development Aid)
-- ============================================================================

-- Global flag to enable/disable overflow warnings
Widget.OverflowWarningsEnabled = true

-- Track warned widgets to avoid spam (reset each layout cycle)
local warnedWidgets_ = {}

--- Reset overflow warnings (call before each layout check)
function Widget.ResetOverflowWarnings()
    warnedWidgets_ = {}
end

--- Check if children overflow this widget's bounds
--- Call after layout calculation to detect potential issues
---@param recursive boolean|nil Check children recursively (default true)
function Widget:CheckOverflow(recursive)
    if not Widget.OverflowWarningsEnabled then return end
    if recursive == nil then recursive = true end

    local l = self:GetLayout()
    if not l or l.w <= 0 or l.h <= 0 then return end

    -- Skip widgets that are designed to overflow (ScrollView content, etc.)
    if self.props.allowOverflow then return end

    -- Calculate children bounds (only in-flow children)
    local childrenHeight = 0
    local childrenWidth = 0
    local isColumn = (self.props.flexDirection or "column") == "column"
    local visibleChildren = 0

    for _, child in ipairs(self.children) do
        if child:IsVisible() then
            -- Skip absolutely positioned children: they are out of normal flex flow
            -- (e.g. Modal, Drawer, Popover) and don't contribute to overflow
            if child.props.position == "absolute" then
                -- still recurse into them below, but don't count their size
            else
                visibleChildren = visibleChildren + 1
                local cl = child:GetLayout()
                if cl then
                    if isColumn then
                        childrenHeight = childrenHeight + cl.h
                        childrenWidth = math.max(childrenWidth, cl.w)
                    else
                        childrenWidth = childrenWidth + cl.w
                        childrenHeight = math.max(childrenHeight, cl.h)
                    end
                end
            end
        end
    end

    -- Add gap spacing
    local gap = self.props.gap or 0
    if visibleChildren > 1 then
        local totalGap = gap * (visibleChildren - 1)
        if isColumn then
            childrenHeight = childrenHeight + totalGap
        else
            childrenWidth = childrenWidth + totalGap
        end
    end

    -- Check for overflow
    local widgetId = self.props.id or self._className or "Widget"
    local overflowH = childrenHeight > l.h + 1  -- +1 for float tolerance
    local overflowW = childrenWidth > l.w + 1

    if (overflowH or overflowW) and not warnedWidgets_[self] then
        warnedWidgets_[self] = true
        local msg = string.format(
            "[Layout Warning] Overflow in '%s': children=%dx%d, container=%dx%d. " ..
            "Consider: flexShrink=1 on children, or increase container size.",
            widgetId,
            math.floor(childrenWidth), math.floor(childrenHeight),
            math.floor(l.w), math.floor(l.h)
        )
        print(msg)
    end

    -- Recursively check children (including absolute-positioned ones)
    if recursive then
        for _, child in ipairs(self.children) do
            child:CheckOverflow(true)
        end
    end
end

-- Make Widget callable: Widget { props }
setmetatable(Widget, {
    __call = function(cls, props)
        return cls:new(props)
    end
})

-- ============================================================================
-- Static Methods for Layout Callback
-- ============================================================================

--- Set layout dirty callback (called by UI.lua)
---@param callback function|nil
function Widget.SetLayoutDirtyCallback(callback)
    onLayoutDirty_ = callback
end

--- Notify layout changed (internal use)
local function notifyLayoutDirty()
    if onLayoutDirty_ then
        onLayoutDirty_()
    end
end

-- Expose for internal use
Widget._notifyLayoutDirty = notifyLayoutDirty
Widget.ExpandPaddingShorthand = expandPaddingShorthand

return Widget
