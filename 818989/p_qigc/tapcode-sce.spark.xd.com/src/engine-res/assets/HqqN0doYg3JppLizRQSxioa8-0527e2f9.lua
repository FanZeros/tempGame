-- ============================================================================
-- Button Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Interactive button with hover/pressed states
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local Transition = require("urhox-libs/UI/Core/Transition")
local UI = require("urhox-libs/UI/Core/UI")

---@class ButtonProps : WidgetProps
---@field text? string Button text
---@field disabled? boolean Is button disabled
---@field variant? string "primary" | "secondary" | "danger" | "error" | "success"
---@field hoverBackgroundColor? RGBAColor|string Hover state background color
---@field pressedBackgroundColor? RGBAColor|string Pressed state background color
---@field disabledBackgroundColor? RGBAColor|string Disabled state background color
---@field hoverBackgroundImage? string Hover state background image
---@field pressedBackgroundImage? string Pressed state background image
---@field disabledBackgroundImage? string Disabled state background image
---@field backgroundImageOpacity? number Default background image opacity, 0-1
---@field hoverBackgroundImageOpacity? number Hover state background image opacity, 0-1
---@field pressedBackgroundImageOpacity? number Pressed state background image opacity, 0-1
---@field disabledBackgroundImageOpacity? number Disabled state background image opacity, 0-1
---@field textColor? RGBAColor|string Custom text color
---@field disabledTextColor? RGBAColor|string Disabled state text color
---@field variantTextColor? table Per-variant text color { variant_name = RGBAColor }
---@field variantBackgroundGradient? table Per-variant default background gradient { variant_name = gradient }
---@field variantHoverBackgroundGradient? table Per-variant hover state background gradient { variant_name = gradient }
---@field variantPressedBackgroundGradient? table Per-variant pressed state background gradient { variant_name = gradient }
---@field variantDisabledBackgroundGradient? table Per-variant disabled state background gradient { variant_name = gradient }
---@field variantBoxShadow? table Per-variant default box shadow { variant_name = boxShadow_array|false }
---@field variantHoverBoxShadow? table Per-variant hover box shadow { variant_name = boxShadow_array|false }
---@field variantPressedBoxShadow? table Per-variant pressed box shadow { variant_name = boxShadow_array|false }
---@field variantBackgroundImage? table Per-variant default background image { variant_name = imagePath }
---@field variantBackgroundImageOpacity? table Per-variant default background image opacity { variant_name = 0-1 }
---@field fontSize? number Font size
---@field minFontSize? number Auto-fit lower bound (same units as fontSize). Default when omitted under UI.defaultAutoFitText: DEFAULT_AUTOFIT_MIN_FONT_SIZE (8; box-local, not i18n bare-nvg CSS min).
---@field letterSpacing? number Letter spacing in pixels
---@field backgroundGradient? table Default gradient { direction, from, to }
---@field hoverBackgroundGradient? table Hover state gradient (auto-derived if nil)
---@field pressedBackgroundGradient? table Pressed state gradient (auto-derived if nil)
---@field disabledBackgroundGradient? table Disabled state gradient
---@field hoverBoxShadow? table|false Hover state box shadow override
---@field pressedBoxShadow? table|false Pressed state box shadow override
---@field disabledBoxShadow? table|false Disabled state box shadow override
---@field glowShadow? table Per-variant glow shadow config { alpha={default,hover}, blur={default,hover}, offset={default,hover}, inset, side, curve, pressed={color,blur,offset,inset,side,curve} }
---@field borderWidth? number|table Border width (default state): number or {top,right,bottom,left} CSS shorthand
---@field hoverBorderWidth? number|table Border width on hover (default: same as borderWidth)
---@field pressedBorderWidth? number|table Border width on press (default: same as borderWidth)
---@field padding? number|table Text inset padding (default state): number or {top,right,bottom,left}
---@field hoverPadding? number|table Text padding on hover (vertical offset only; default: same as padding)
---@field pressedPadding? number|table Text padding on press (vertical offset only; for "press-flat" recenter)

---@class Button : Widget
---@overload fun(props?: ButtonProps): Button
---@field props ButtonProps
---@field new fun(self, props?: ButtonProps): Button
---@field state {hovered: boolean, pressed: boolean}
---@field AddChild fun(self, child: Widget): self Add child widget
---@field RemoveChild fun(self, child: Widget): self Remove child widget
local Button = Widget:Extend("Button")

-- Match Label: a zero/negative content box is not a meaningful fit target.
-- Common with large paddingVertical on the default height=44 capsule buttons —
-- fit would otherwise collapse toward the autofit min and hide the label.
local FIT_RECT_EPSILON = 0.001
-- Auto-fit only. Box-local floor — separate from bare-nvg CSS-logical min
-- in Engine/i18n.lua (currently 7).
-- TODO: align both floors to the same CSS-logical visual-pixel scale.
local DEFAULT_AUTOFIT_MIN_FONT_SIZE = 8

local VARIANT_THEME_COLORS = {
    primary = { base = "primary", hover = "primaryHover", pressed = "primaryPressed", shadow = "primaryShadow" },
    secondary = { base = "secondary", hover = "secondaryHover", pressed = "secondaryPressed", shadow = "secondaryShadow" },
    danger = { base = "error", hover = "errorHover", pressed = "errorPressed", shadow = "errorShadow" },
    error = { base = "error", hover = "errorHover", pressed = "errorPressed", shadow = "errorShadow" },
    success = { base = "success", hover = "successHover", pressed = "successPressed", shadow = "successShadow" },
}

local DEFAULT_VARIANT_THEME_COLORS = VARIANT_THEME_COLORS.primary

-- Expand a number or CSS shorthand table into top, right, bottom, left.
-- {all} / {vert,horiz} / {top,horiz,bottom} / {top,right,bottom,left}
local function expand4(v)
    if v == nil then return nil end
    if type(v) == "number" then return v, v, v, v end
    local n = #v
    if n == 1 then return v[1], v[1], v[1], v[1]
    elseif n == 2 then return v[1], v[2], v[1], v[2]
    elseif n == 3 then return v[1], v[2], v[3], v[2]
    else return v[1], v[2], v[3], v[4] end
end

local function resolveVariantValue(map, variant)
    if type(map) ~= "table" then return nil end
    return map[variant]
end

local function normalizeGradient(gradient)
    if type(gradient) ~= "table" then return gradient end
    -- Fast path: colors already parsed to RGBA tables — return as-is (no copy).
    if type(gradient.from) ~= "string" and type(gradient.to) ~= "string" then
        return gradient
    end
    -- String colors present: parse into a shallow copy so the caller's gradient
    -- table (often shared across Button instances via theme/props) is never
    -- mutated as a side-effect of rendering.
    local out = {}
    for k, v in pairs(gradient) do out[k] = v end
    if type(out.from) == "string" then out.from = Style.ParseColor(out.from) or out.from end
    if type(out.to) == "string" then out.to = Style.ParseColor(out.to) or out.to end
    return out
end

local function resolveVariantGradient(map, variant)
    return normalizeGradient(resolveVariantValue(map, variant))
end

local function measureIntrinsicWidth(props)
    local textWidth = UI.MeasureTextWidth(
        props.text or "",
        Theme.FontSize(props.fontSize),
        Theme.FontFace(props.fontFamily, props.fontWeight),
        props.letterSpacing
    )
    local padding = (props.paddingLeft or 0) + (props.paddingRight or 0)
    return math.max(64, textWidth + padding)
end

local function refreshIntrinsicWidth(button)
    if not button.autoWidth_ or button.props.text == nil then
        return
    end
    Widget.SetWidth(button, measureIntrinsicWidth(button.props))
    button.fontVersion_ = UI.GetFontVersion()
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ButtonProps?
function Button:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("Button")
    Style.ApplyDefaults(props, themeStyle)
    -- Hardcoded fallbacks (only hit when theme has no entry)
    props.height = props.height or 44
    props.borderRadius = props.borderRadius or 8
    -- fontSize stored in pt, converted to px at render time
    props.fontSize = props.fontSize or Theme.BaseFontSize("bodyLarge")
    props.paddingHorizontal = props.paddingHorizontal or 16

    -- Expand padding shorthand before reading padding values
    -- (Widget.Init calls this again, but it's idempotent)
    Widget.ExpandPaddingShorthand(props)

    -- Default variant
    props.variant = props.variant or "primary"

    -- In translated mode, Buttons in normal flow participate in flex
    -- sizing just like Labels: Yoga may allocate less width, and Render() then
    -- fits the text into that final content box. Keep the historical no-shrink
    -- default for source-language UIs and non-flow-positioned Buttons;
    -- preserve an explicit user value.
    local isFlowButton = props.position == nil
        or props.position == "relative"
        or props.position == "sticky"
    if props.flexShrink == nil then
        props.flexShrink = UI.defaultAutoFitText and isFlowButton and 1 or 0
    end

    -- Calculate width based on text using precise measurement
    local isIntrinsicButton = not props.width
    local userSetMinWidth = props.minWidth ~= nil
    self.autoWidth_ = isIntrinsicButton and props.text ~= nil
    if isIntrinsicButton and props.text then
        props.width = measureIntrinsicWidth(props)
        self.fontVersion_ = UI.GetFontVersion()
    elseif isIntrinsicButton and not userSetMinWidth then
        -- No text prop: Button may be used with children (Icon + Label).
        -- Use minWidth instead of fixed width so Yoga can size from children.
        -- Translated shrink path below may replace this with 0.
        props.minWidth = 64
    end

    -- Intrinsic and composite Buttons alike must stay within a parent's
    -- content width in translated flow. flexShrink only affects the main flex
    -- axis; this max-width cap also covers a column parent or child content.
    -- Yoga's default min-width is content-sized and blocks shrink, so allow
    -- minWidth=0 when we opted into shrink (unless the author set minWidth).
    -- An explicit flexShrink=0 remains an opt-out from the translated default.
    if UI.defaultAutoFitText and isFlowButton and props.flexShrink ~= 0 then
        if isIntrinsicButton and not props.maxWidth then
            props.maxWidth = "100%"
        end
        if not userSetMinWidth then
            props.minWidth = 0
        end
    end

    -- Initialize state
    self.state = {
        hovered = false,
        pressed = false,
    }

    Widget.Init(self, props)

    -- Auto-generate hover/pressed colors from backgroundColor if not specified
    -- (after Widget.Init, because it normalizes color props to RGBA table format)
    if props.backgroundColor then
        if not props.hoverBackgroundColor then
            props.hoverBackgroundColor = Style.Lighten(props.backgroundColor, 0.15)
        end
        if not props.pressedBackgroundColor then
            props.pressedBackgroundColor = Style.Darken(props.backgroundColor, 0.2)
        end
    end

    -- Auto-generate hover/pressed gradients from backgroundGradient if not specified
    if props.backgroundGradient then
        local grad = props.backgroundGradient
        -- Ensure gradient colors are RGBA tables (may be hex strings from JSON)
        if type(grad.from) == "string" then grad.from = Style.ParseColor(grad.from) or grad.from end
        if type(grad.to) == "string" then grad.to = Style.ParseColor(grad.to) or grad.to end
        if not props.hoverBackgroundGradient then
            props.hoverBackgroundGradient = {
                direction = grad.direction,
                from = Style.Lighten(grad.from, 0.15),
                to = Style.Lighten(grad.to, 0.15),
            }
        end
        if not props.pressedBackgroundGradient then
            props.pressedBackgroundGradient = {
                direction = grad.direction,
                from = Style.Darken(grad.from, 0.2),
                to = Style.Darken(grad.to, 0.2),
            }
        end
    end

    -- Cache initial background color for transition "from" value
    self.lastStateBgColor_ = self:ResolveStateBgColor()

    -- Pre-allocate reusable tables for Render (avoid per-frame allocations)
    self.bgOverrides_ = {
        backgroundColor = nil,
        backgroundGradient = nil,
        backgroundImage = nil,
        backgroundImageOpacity = nil,
        backgroundFit = nil,
        backgroundSlice = nil,
        borderRadius = nil,
        borderColor = nil,
        borderWidth = nil,
        boxShadow = nil,
    }
    self.glowShadowEntry_ = { x = 0, y = 0, blur = 0, color = { 0, 0, 0, 0 } }
    self.glowShadowArray_ = { self.glowShadowEntry_ }
end

-- ============================================================================
-- State Color Resolution
-- ============================================================================

--- Resolve the target background color based on current state (hovered/pressed/disabled/normal).
--- Does NOT consider renderProps_ (transition interpolation) — returns the raw target.
---@return table|nil RGBA color table
function Button:ResolveStateBgColor()
    local props = self.props
    local state = self.state

    -- When button has backgroundImage but no explicit backgroundColor,
    -- don't fall back to variant theme color (would overlay image with solid color)
    local hasImage = props.backgroundImage ~= nil
        or resolveVariantValue(props.variantBackgroundImage, props.variant) ~= nil

    if props.disabled then
        local c = props.disabledBackgroundColor or props.backgroundColor
        if c then
            return c
        end
        if props.disabledBackgroundImage or hasImage then
            return nil
        end
        return Theme.Color("disabled")
    elseif state.pressed then
        local c = props.pressedBackgroundColor
        if c then
            return c
        end
        if props.pressedBackgroundImage or hasImage then
            return nil
        end
        local variantColors = self:GetVariantThemeColors()
        return Theme.TryColor(variantColors.pressed) or Style.Darken(Theme.Color(variantColors.base), 0.2)
    elseif state.hovered then
        local c = props.hoverBackgroundColor
        if c then
            return c
        end
        if props.hoverBackgroundImage or hasImage then
            return nil
        end
        local variantColors = self:GetVariantThemeColors()
        return Theme.TryColor(variantColors.hover) or Style.Lighten(Theme.Color(variantColors.base), 0.1)
    else
        local c = props.backgroundColor
        if c then
            return c
        end
        if hasImage then
            return nil
        end
        return Theme.Color(self:GetVariantThemeColors().base)
    end
end

--- Start a background color transition to the current state's target color.
--- Only triggers when the widget has a transition config that includes backgroundColor.
--- Does NOT modify props — writes to transitions_/renderProps_ only.
function Button:TransitionToStateBgColor()
    local config = self.transitionConfig_
    if not config then return end
    if not Transition.ConfigIncludesProperty(config, "backgroundColor") then return end

    local targetColor = self:ResolveStateBgColor()
    if not targetColor then return end

    -- Use current rendered color as "from" (ongoing transition or last resolved)
    local currentColor = self.renderProps_.backgroundColor or self.lastStateBgColor_
    if not currentColor then
        currentColor = targetColor  -- First time: no transition needed
    end

    -- Store resolved target so next transition can use it as "from" after renderProps_ clears
    self.lastStateBgColor_ = targetColor

    -- Skip if same color (avoid unnecessary transition)
    if currentColor[1] == targetColor[1] and currentColor[2] == targetColor[2]
        and currentColor[3] == targetColor[3] and (currentColor[4] or 255) == (targetColor[4] or 255) then
        return
    end

    local wasEmpty = #self.transitions_ == 0
    local dur, eas = Transition.GetPropertyConfig(config, "backgroundColor")
    Transition.Start(self.transitions_, "backgroundColor", currentColor, targetColor, dur, eas)

    -- Notify UI.lua to track this widget for BaseUpdate
    if wasEmpty and #self.transitions_ > 0 then
        local onStart = Widget.GetTransitionStartCallback()
        if onStart then onStart(self) end
    end
end

-- ============================================================================
-- Glow Shadow Resolution
-- ============================================================================

--- Resolve per-variant glow shadow based on current state.
--- Returns the pre-allocated boxShadow array or nil.
--- Reuses self.glowShadowEntry_/glowShadowArray_ to avoid per-frame allocations.
---@return table|nil
function Button:ResolveGlowShadow()
    local cfg = self.props.glowShadow
    if not cfg or self.props.disabled then return nil end

    local entry = self.glowShadowEntry_
    local state = self.state
    local variantColors = self:GetVariantThemeColors()
    if state.pressed then
        local p = cfg.pressed
        if not p then return nil end
        local ofs = p.offset
        entry.x = ofs and ofs[1] or 0
        entry.y = ofs and ofs[2] or 0
        entry.blur = p.blur or 6
        entry.spread = p.spread or 0
        entry.inset = p.inset or cfg.inset or false
        entry.side = p.side or cfg.side
        entry.curve = p.curve or cfg.curve
        local variantShadowColor = Theme.TryColor(variantColors.shadow)
            or Theme.TryColor(variantColors.pressed)
            or Theme.Color(variantColors.base)
        local explicitPressedColor = entry.inset or p.side or cfg.side or (p.color and (p.color[4] or 255) <= 0)
        local shadowColor = explicitPressedColor and (p.color or variantShadowColor) or (variantShadowColor or p.color)
        local shadowAlpha = p.color and p.color[4] or shadowColor and shadowColor[4] or 64
        entry.color[1] = shadowColor and shadowColor[1] or 0; entry.color[2] = shadowColor and shadowColor[2] or 0
        entry.color[3] = shadowColor and shadowColor[3] or 0; entry.color[4] = shadowAlpha
    else
        local cfgColor = cfg.color
        if type(cfgColor) == "string" then
            cfgColor = Theme.TryColor(cfgColor)
        end
        local baseColor = Theme.TryColor(variantColors.shadow)
            or Theme.TryColor(variantColors.pressed)
            or Theme.Color(variantColors.base)
        baseColor = cfgColor or baseColor
        local a = cfg.alpha
        local b = cfg.blur
        local o = cfg.offset
        local s = cfg.spread
        local alpha = state.hovered and (a and a.hover or 128) or (a and a.default or (cfgColor and cfgColor[4]) or 96)
        local blur = state.hovered and (b and b.hover or 16) or (b and b.default or 12)
        local ofs = state.hovered and (o and o.hover or o and o.default) or (o and o.default)
        local spread = state.hovered and (s and s.hover or s and s.default or 0) or (s and s.default or 0)
        entry.x = ofs and ofs[1] or 0
        entry.y = ofs and ofs[2] or 0
        entry.blur = blur
        entry.spread = spread
        entry.inset = cfg.inset or false
        entry.side = cfg.side
        entry.curve = cfg.curve
        entry.color[1] = baseColor[1]; entry.color[2] = baseColor[2]
        entry.color[3] = baseColor[3]; entry.color[4] = alpha
    end
    return self.glowShadowArray_
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Button:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    -- DWP font reload: re-measure text width when font version changes
    if self.autoWidth_ and props.text then
        local curFontVer = UI.GetFontVersion()
        if self.fontVersion_ ~= curFontVer then
            refreshIntrinsicWidth(self)
        end
    end

    local disabled = props.disabled
    local variant = props.variant
    -- No scale needed - nvgScale in UI.Render handles it
    local borderRadius = props.borderRadius or Theme.BaseRadius("md")

    -- Update decoration state
    local decorState = disabled and "disabled" or (state.pressed and "pressed" or (state.hovered and "hover" or "default"))
    self:UpdateDecorationState(decorState)

    -- Determine background color: prefer transition interpolated value, then state-based
    local bgColor = self.renderProps_.backgroundColor
    local bgImage, bgImageOpacity, textColor

    if not bgColor then
        -- No active transition: resolve from state as before
        bgColor = self:ResolveStateBgColor()
    end

    -- Resolve per-variant text/image defaults
    local variantText = props.variantTextColor and props.variantTextColor[variant]
    local variantBgImage = resolveVariantValue(props.variantBackgroundImage, variant)
    local variantBgImageOpacity = resolveVariantValue(props.variantBackgroundImageOpacity, variant)

    -- Resolve background image and text color based on state
    if disabled then
        bgImage = props.disabledBackgroundImage or props.backgroundImage or variantBgImage
        bgImageOpacity = props.disabledBackgroundImageOpacity or props.backgroundImageOpacity or variantBgImageOpacity
        textColor = props.disabledTextColor or Theme.Color("disabledText")
    elseif state.pressed then
        bgImage = props.pressedBackgroundImage or props.backgroundImage or variantBgImage
        bgImageOpacity = props.pressedBackgroundImageOpacity or props.backgroundImageOpacity or variantBgImageOpacity
        textColor = props.textColor or variantText or Theme.Color("text")
    elseif state.hovered then
        bgImage = props.hoverBackgroundImage or props.backgroundImage or variantBgImage
        bgImageOpacity = props.hoverBackgroundImageOpacity or props.backgroundImageOpacity or variantBgImageOpacity
        textColor = props.textColor or variantText or Theme.Color("text")
    else
        bgImage = props.backgroundImage or variantBgImage
        bgImageOpacity = props.backgroundImageOpacity or variantBgImageOpacity
        textColor = props.textColor or variantText or Theme.Color("text")
    end

    -- Resolve state-specific shadow first. A state shadow set to false
    -- intentionally disables shadows for that state.
    local variantDefaultShadow = resolveVariantValue(props.variantBoxShadow, variant)
    local variantHoverShadow = resolveVariantValue(props.variantHoverBoxShadow, variant)
    local variantPressedShadow = resolveVariantValue(props.variantPressedBoxShadow, variant)
    local defaultShadow = props.boxShadow
    if defaultShadow == nil then
        defaultShadow = variantDefaultShadow
    end

    local boxShadow
    if disabled and props.disabledBoxShadow ~= nil then
        boxShadow = props.disabledBoxShadow
    elseif state.pressed and props.pressedBoxShadow ~= nil then
        boxShadow = props.pressedBoxShadow
    elseif state.pressed and variantPressedShadow ~= nil then
        boxShadow = variantPressedShadow
    elseif state.hovered and props.hoverBoxShadow ~= nil then
        boxShadow = props.hoverBoxShadow
    elseif state.hovered and variantHoverShadow ~= nil then
        boxShadow = variantHoverShadow
    elseif defaultShadow ~= nil then
        boxShadow = defaultShadow
    else
        boxShadow = self:ResolveGlowShadow()
    end

    -- Resolve background gradient based on state
    local bgGradient
    local defaultBgGradient = props.backgroundGradient or resolveVariantGradient(props.variantBackgroundGradient, variant)
    if defaultBgGradient then
        if disabled then
            bgGradient = props.disabledBackgroundGradient
                or resolveVariantGradient(props.variantDisabledBackgroundGradient, variant)
                or defaultBgGradient
        elseif state.pressed then
            bgGradient = props.pressedBackgroundGradient
                or resolveVariantGradient(props.variantPressedBackgroundGradient, variant)
                or defaultBgGradient
        elseif state.hovered then
            bgGradient = props.hoverBackgroundGradient
                or resolveVariantGradient(props.variantHoverBackgroundGradient, variant)
                or defaultBgGradient
        else
            bgGradient = defaultBgGradient
        end
    end

    -- Tristate border width: hover/pressed override the default per-side widths.
    -- Read fresh from props each frame (dynamic-safe); default state is whatever
    -- Widget.Init already expanded (uniform borderWidth or per-side props).
    -- savedBorder_ holds the default per-side to restore after RenderFullBackground.
    local borderOverride = nil
    if not disabled then
        if state.pressed and props.pressedBorderWidth ~= nil then
            borderOverride = props.pressedBorderWidth
        elseif state.hovered and props.hoverBorderWidth ~= nil then
            borderOverride = props.hoverBorderWidth
        end
    end
    local sBW, sBT, sBR, sBB, sBL
    if borderOverride ~= nil then
        sBW, sBT, sBR, sBB, sBL = props.borderWidth, props.borderTopWidth,
            props.borderRightWidth, props.borderBottomWidth, props.borderLeftWidth
        local t, r, b, l = expand4(borderOverride)
        props.borderWidth = nil
        props.borderTopWidth = t or 0
        props.borderRightWidth = r or 0
        props.borderBottomWidth = b or 0
        props.borderLeftWidth = l or 0
    end

    -- Border color: use the explicit prop only. nil lets RenderFullBackground /
    -- RenderPerSideBorders fall back to Theme.Color("border"). A variant-tinted
    -- border must be opted into via an explicit borderColor (Default Dark/TapTap do
    -- this); themes without one (e.g. BrawlForge) keep the theme border token.
    local resolvedBorderColor = props.borderColor

    -- Render background using Widget base class method (reuse pre-allocated table)
    local ov = self.bgOverrides_
    ov.backgroundColor = bgColor
    ov.backgroundGradient = bgGradient
    ov.backgroundImage = bgImage
    ov.backgroundImageOpacity = bgImageOpacity
    ov.backgroundFit = props.backgroundFit
    ov.backgroundSlice = props.backgroundSlice
    ov.borderRadius = borderRadius
    ov.borderColor = resolvedBorderColor
    ov.borderWidth = nil
    ov.boxShadow = boxShadow
    self:RenderFullBackground(nvg, ov)

    -- Restore default border props (override was transient for this frame only)
    if borderOverride ~= nil then
        props.borderWidth = sBW
        props.borderTopWidth = sBT
        props.borderRightWidth = sBR
        props.borderBottomWidth = sBB
        props.borderLeftWidth = sBL
    end

    -- Draw text (clipped to button border-box bounds, not content area).
    -- CSS clips at border-box edge, text can visually extend into padding.
    local text = props.text or ""
    if text ~= "" then
        local pT = props.paddingTop or 0
        local pR = props.paddingRight or 0
        local pB = props.paddingBottom or 0
        local pL = props.paddingLeft or 0
        -- Tristate padding (read fresh from props): hover/pressed override the
        -- VERTICAL text offset only ("press-flat" recenter). Horizontal stays
        -- from layout padding so button width is unaffected.
        local padOverride = nil
        if not disabled then
            if state.pressed and props.pressedPadding ~= nil then
                padOverride = props.pressedPadding
            elseif state.hovered and props.hoverPadding ~= nil then
                padOverride = props.hoverPadding
            end
        end
        if padOverride ~= nil then
            local t, _, b = expand4(padOverride)
            if t then pT = t end
            if b then pB = b end
        end

        local fontFace = Theme.FontFace(props.fontFamily, props.fontWeight)
        local baseFontSize = Theme.FontSize(props.fontSize)
        local renderFontSize = baseFontSize
        local contentW = l.w - pL - pR
        local contentH = l.h - pT - pB
        -- Invalid content box (padding ate the interior): skip fit and keep the
        -- configured font size, matching source-language drawing. Fitting into a
        -- 0×0 box only drives the autofit min and makes the label invisible.
        local canFitText = UI.defaultAutoFitText
            and contentW > FIT_RECT_EPSILON
            and contentH > FIT_RECT_EPSILON
        if canFitText then
            local minFontSize = props.minFontSize ~= nil
                and Theme.FontSize(props.minFontSize)
                or Theme.FontSize(DEFAULT_AUTOFIT_MIN_FONT_SIZE)
            local fitResult = UI.MeasureTextFit(text, {
                fontSize = baseFontSize,
                fontFace = fontFace,
                letterSpacing = props.letterSpacing or 0,
                width = contentW,
                height = contentH,
                multiline = false,
                minFontSize = minFontSize,
                cache = self.autoFitCache_,
            })
            self.autoFitCache_ = fitResult
            renderFontSize = fitResult.fontSize or baseFontSize
        elseif UI.defaultAutoFitText then
            self.autoFitCache_ = nil
        end

        nvgSave(nvg)
        nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)
        nvgFontFace(nvg, fontFace)
        nvgFontSize(nvg, renderFontSize)  -- Convert pt to px
        if UI.defaultAutoFitText or props.letterSpacing ~= nil then
            nvgTextLetterSpacing(nvg, props.letterSpacing or 0)
        end
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        if UI.defaultAutoFitText then
            nvgText(nvg, l.x + pL + contentW / 2,
                l.y + pT + contentH / 2, text, nil, false)
        else
            nvgText(nvg, l.x + pL + contentW / 2,
                l.y + pT + contentH / 2, text, nil)
        end
        nvgRestore(nvg)
    end
end

--- Get variant color name
---@return string
function Button:GetVariantColorName()
    return self:GetVariantThemeColors().base
end

--- Get variant theme color token names
---@return table
function Button:GetVariantThemeColors()
    return VARIANT_THEME_COLORS[self.props.variant] or DEFAULT_VARIANT_THEME_COLORS
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Button:OnMouseEnter()
    if not self.props.disabled then
        self:SetState({ hovered = true })
        self:TransitionToStateBgColor()
    end
end

function Button:OnMouseLeave()
    self:SetState({ hovered = false, pressed = false })
    self:TransitionToStateBgColor()
end

function Button:OnPointerDown(event)
    if not event then return end
    if not self.props.disabled and event:IsPrimaryAction() then
        self:SetState({ pressed = true })
        self:TransitionToStateBgColor()
    end
end

function Button:OnPointerUp(event)
    if not event then return end
    if event:IsPrimaryAction() then
        self:SetState({ pressed = false })
        self:TransitionToStateBgColor()
    end
end

function Button:OnPointerCancel(event)
    self:SetState({ pressed = false })
    self:TransitionToStateBgColor()
    Widget.OnPointerCancel(self, event)
end

function Button:OnClick(event)
    if not self.props.disabled then
        self:DispatchEvent("click", self, event)
        if self.props.onClick then
            self.props.onClick(self, event)
        end
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set button text
---@param text string
---@return Button self
function Button:SetText(text)
    if self.props.text == text then
        return self
    end
    self.props.text = text
    refreshIntrinsicWidth(self)
    return self
end

--- Override SetStyle to keep fixed and intrinsic width modes distinct.
function Button:SetStyle(style)
    local hasExplicitWidth = style.width ~= nil
    local affectsIntrinsicWidth = style.text ~= nil
        or style.fontSize ~= nil
        or style.fontFamily ~= nil
        or style.fontWeight ~= nil
        or style.letterSpacing ~= nil
        or style.padding ~= nil
        or style.paddingHorizontal ~= nil
        or style.paddingLeft ~= nil
        or style.paddingRight ~= nil

    Widget.SetStyle(self, style)
    if hasExplicitWidth then
        self.autoWidth_ = false
    elseif affectsIntrinsicWidth then
        refreshIntrinsicWidth(self)
    end
    return self
end

--- Set an explicit width and disable intrinsic text sizing.
---@param width number Width in base pixels
---@return Button self
function Button:SetWidth(width)
    self.autoWidth_ = false
    return Widget.SetWidth(self, width)
end

--- Clear an explicit width and restore text + padding intrinsic sizing.
---@return Button self
function Button:SetWidthAuto()
    Widget.SetWidthAuto(self)
    self.autoWidth_ = self.props.text ~= nil
    if self.autoWidth_ then
        refreshIntrinsicWidth(self)
    elseif self.props.minWidth == nil then
        Widget.SetStyle(self, { minWidth = 64 })
    end
    return self
end

--- Set disabled state
---@param disabled boolean
---@return Button self
function Button:SetDisabled(disabled)
    self.props.disabled = disabled
    if disabled then
        self:SetState({ hovered = false, pressed = false })
    end
    return self
end

--- Check if button is disabled
---@return boolean
function Button:IsDisabled()
    return self.props.disabled == true
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Button:IsStateful()
    return true
end

return Button
