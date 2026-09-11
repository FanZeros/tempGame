-- ============================================================================
-- ProgressBar Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Progress bar with optional label
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

--- Apply fill to current NanoVG path: gradient or solid color.
---@param nvg NVGContextWrapper
---@param fillColor table|nil RGBA color
---@param fillGradient table|nil { direction, from, to }
---@param x number Fill area x
---@param y number Fill area y
---@param w number Fill area width
---@param h number Fill area height
local function applyFill(nvg, fillColor, fillGradient, x, y, w, h)
    if fillGradient and fillGradient.from and fillGradient.to then
        local sx, sy, ex, ey = Widget.ResolveGradientDirection(fillGradient.direction or "to-right", x, y, w, h)
        local c1 = nvgRGBA(fillGradient.from[1], fillGradient.from[2], fillGradient.from[3], fillGradient.from[4] or 255)
        local c2 = nvgRGBA(fillGradient.to[1], fillGradient.to[2], fillGradient.to[3], fillGradient.to[4] or 255)
        local paint = nvgLinearGradient(nvg, sx, sy, ex, ey, c1, c2)
        nvgFillPaint(nvg, paint)
    elseif fillColor then
        nvgFillColor(nvg, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 255))
    end
end

---@class ProgressBarProps : WidgetProps
---@field value? number Current value (default: 0)
---@field max? number Maximum value (default: 1)
---@field showLabel? boolean Show percentage label
---@field variant? string "primary" | "success" | "warning" | "error"
---@field indeterminate? boolean Indeterminate (loading) mode
---@field fillColor? RGBAColor|string Custom fill color (overrides variant)
---@field fillGradient? table Gradient fill { direction: string, from: {RGBA}, to: {RGBA} }

---@class ProgressBar : Widget
---@overload fun(props?: ProgressBarProps): ProgressBar
---@field props ProgressBarProps
---@field new fun(self, props?: ProgressBarProps): ProgressBar
local ProgressBar = Widget:Extend("ProgressBar")

-- Class-level extra transitionable props (shared by all instances)
ProgressBar.transitionableProps_ = { value = "number" }

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ProgressBarProps?
function ProgressBar:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("ProgressBar")
    Style.ApplyDefaults(props, themeStyle)
    -- Hardcoded fallbacks (only hit when theme has no entry)
    props.height = props.height or 8
    props.borderRadius = props.borderRadius or 4

    -- Default values
    props.value = props.value or 0
    props.max = props.max or 1
    props.variant = props.variant or "primary"

    -- Indeterminate animation state
    self.animOffset_ = 0

    -- Parse nested color fields in fillGradient before Widget.Init
    -- (NormalizeColorProps only auto-parses top-level *Color props, not nested tables)
    if props.fillGradient then
        if type(props.fillGradient.from) == "string" then
            props.fillGradient.from = Style.ParseColor(props.fillGradient.from)
        end
        if type(props.fillGradient.to) == "string" then
            props.fillGradient.to = Style.ParseColor(props.fillGradient.to)
        end
    end

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function ProgressBar:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props

    -- Use transition-interpolated value if available, otherwise props.value
    local value = self.renderProps_.value or props.value
    local max = props.max
    local borderRadius = math.min(props.borderRadius or 4, math.min(l.w, l.h) / 2)
    local indeterminate = props.indeterminate
    local showLabel = props.showLabel
    local variant = props.variant

    -- Calculate progress (0-1)
    local progress = math.max(0, math.min(1, value / max))

    -- Get colors based on variant (fillColor prop overrides variant)
    local bgColor = Theme.Color("surface")
    local fillColor = props.fillColor
    local fillGradient = props.fillGradient

    if not fillColor and not fillGradient then
        if variant == "success" then
            fillColor = Theme.Color("success")
        elseif variant == "warning" then
            fillColor = Theme.Color("warning")
        elseif variant == "error" then
            fillColor = Theme.Color("error")
        else
            fillColor = Theme.Color("primary")
        end
    end

    -- Draw track background
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, borderRadius)
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    if indeterminate then
        -- Indeterminate animation
        local barWidth = l.w * 0.3
        local offset = self.animOffset_
        local barX = l.x + (l.w + barWidth) * offset - barWidth

        -- Clip to track bounds
        nvgSave(nvg)
        nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, barX, l.y, barWidth, l.h, borderRadius)
        applyFill(nvg, fillColor, fillGradient, barX, l.y, barWidth, l.h)
        nvgFill(nvg)

        nvgRestore(nvg)
    else
        -- Determinate progress fill
        local fillWidth = l.w * progress
        if fillWidth > 0 then
            nvgBeginPath(nvg)
            if fillWidth < l.w then
                -- Partial fill - only round left corners
                nvgRoundedRectVarying(nvg, l.x, l.y, fillWidth, l.h,
                    borderRadius, 0, 0, borderRadius)
            else
                -- Full fill - round all corners
                nvgRoundedRect(nvg, l.x, l.y, fillWidth, l.h, borderRadius)
            end
            applyFill(nvg, fillColor, fillGradient, l.x, l.y, fillWidth, l.h)
            nvgFill(nvg)
        end
    end

    -- Draw track border on top of fill (only when borderWidth is set via theme)
    local trackBorderWidth = props.borderWidth
    if trackBorderWidth and trackBorderWidth > 0 then
        local trackBorderColor = props.borderColor
        if not trackBorderColor then
            trackBorderColor = fillColor and Style.Darken(fillColor, 0.3) or Theme.Color("border")
        end
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, borderRadius)
        nvgStrokeColor(nvg, nvgRGBA(trackBorderColor[1], trackBorderColor[2], trackBorderColor[3], trackBorderColor[4] or 255))
        nvgStrokeWidth(nvg, trackBorderWidth)
        nvgStroke(nvg)
    end

    -- Draw label
    if showLabel and not indeterminate then
        local percent = math.floor(progress * 100)
        local labelText = string.format("%d%%", percent)

        local fontFamily = Theme.FontFamily()
        local textColor = Theme.Color("text")

        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, Theme.FontSizeOf("small"))
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, l.x + l.w / 2, l.y + l.h / 2, labelText, nil)
    end
end

-- ============================================================================
-- Update (for indeterminate animation)
-- ============================================================================

function ProgressBar:Update(dt)
    if self.props.indeterminate then
        self.animOffset_ = self.animOffset_ + dt * 0.5  -- Speed
        if self.animOffset_ > 1 then
            self.animOffset_ = 0
        end
    end
end

-- ============================================================================
-- SetStyle override (parse nested fillGradient colors)
-- ============================================================================

function ProgressBar:SetStyle(style)
    if style.fillGradient then
        if type(style.fillGradient.from) == "string" then
            style.fillGradient.from = Style.ParseColor(style.fillGradient.from)
        end
        if type(style.fillGradient.to) == "string" then
            style.fillGradient.to = Style.ParseColor(style.fillGradient.to)
        end
    end
    Widget.SetStyle(self, style)
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set progress value (with optional transition animation).
--- Delegates to SetStyle to reuse existing transition infrastructure.
---@param value number
---@return ProgressBar self
function ProgressBar:SetValue(value)
    local clamped = math.max(0, math.min(self.props.max, value))
    self:SetStyle({ value = clamped })
    return self
end

--- Get progress value
---@return number
function ProgressBar:GetValue()
    return self.props.value
end

--- Get progress as percentage (0-100)
---@return number
function ProgressBar:GetPercent()
    return (self.props.value / self.props.max) * 100
end

--- Set maximum value
---@param max number
---@return ProgressBar self
function ProgressBar:SetMax(max)
    self.props.max = max
    return self
end

--- Set variant
---@param variant string "primary" | "success" | "warning" | "error"
---@return ProgressBar self
function ProgressBar:SetVariant(variant)
    self.props.variant = variant
    return self
end

--- Set indeterminate mode
---@param indeterminate boolean
---@return ProgressBar self
function ProgressBar:SetIndeterminate(indeterminate)
    self.props.indeterminate = indeterminate
    if indeterminate then
        self.animOffset_ = 0
    end
    return self
end

--- Show/hide label
---@param show boolean
---@return ProgressBar self
function ProgressBar:SetShowLabel(show)
    self.props.showLabel = show
    return self
end

-- ============================================================================
-- Stateless (unless indeterminate)
-- ============================================================================

function ProgressBar:IsStateful()
    return self.props.indeterminate == true
end

return ProgressBar
