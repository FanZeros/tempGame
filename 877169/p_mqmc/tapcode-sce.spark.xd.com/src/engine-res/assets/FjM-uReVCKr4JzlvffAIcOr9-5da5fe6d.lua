-- ============================================================================
-- Toggle Widget (Switch)
-- UrhoX UI Library - Yoga + NanoVG
-- iOS-style toggle switch
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class ToggleProps : WidgetProps
---@field value? boolean Is toggle on
---@field disabled? boolean Is toggle disabled
---@field label? string Label text
---@field trackWidth? number Track width (default: 48)
---@field trackHeight? number Track height (default: 26)
---@field thumbSize? number Thumb size (default: 22)
---@field trackCheckedHoverBorderColor? RGBAColor|string Checked hover track border color
---@field trackDisabledBorderColor? RGBAColor|string Disabled track border color
---@field onChange? fun(self: Toggle, value: boolean) Change callback

---@class Toggle : Widget
---@overload fun(props?: ToggleProps): Toggle
---@field props ToggleProps
---@field new fun(self, props?: ToggleProps): Toggle
---@field state {hovered: boolean, pressed: boolean}
local Toggle = Widget:Extend("Toggle")

-- Constant fallback color (avoid per-frame allocation)
local WHITE = { 255, 255, 255, 255 }

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ToggleProps?
function Toggle:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("Toggle")
    -- Extract track dimensions first (support both new "trackWidth" and legacy "width" key names)
    props.trackWidth = props.trackWidth or themeStyle.trackWidth or themeStyle.width or 48
    props.trackHeight = props.trackHeight or themeStyle.trackHeight or themeStyle.height or 26
    props.thumbSize = props.thumbSize or themeStyle.thumbSize or 22
    -- Remove legacy width/height from themeStyle to prevent them from becoming widget layout dimensions
    themeStyle.width = nil
    themeStyle.height = nil
    Style.ApplyDefaults(props, themeStyle)

    -- Layout for label
    props.flexDirection = "row"
    props.alignItems = "center"
    props.gap = props.gap or 8

    -- Set widget size
    props.height = props.height or props.trackHeight

    -- Default width: track + gap + label estimate
    if not props.width then
        local labelWidth = 0
        if props.label and #props.label > 0 then
            labelWidth = #props.label * 14 * 0.55 + (props.gap or 8)
        end
        props.width = props.trackWidth + labelWidth
    end

    -- Initialize state
    self.state = {
        hovered = false,
        pressed = false,
    }

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Toggle:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    local value = props.value
    local disabled = props.disabled
    local trackWidth = props.trackWidth
    local trackHeight = props.trackHeight
    local thumbSize = props.thumbSize
    local label = props.label

    -- Track position (vertically centered)
    local trackX = l.x
    local trackY = l.y + (l.h - trackHeight) / 2
    local trackRadius = math.min(self.props.borderRadius or (trackHeight / 2), math.min(trackWidth, trackHeight) / 2)

    -- Thumb position
    local thumbPadding = (trackHeight - thumbSize) / 2
    local thumbX = value
        and (trackX + trackWidth - thumbSize - thumbPadding)
        or (trackX + thumbPadding)
    local thumbY = trackY + thumbPadding

    -- Colors (read state tokens directly from props to avoid per-frame table allocation)
    local trackColor, borderColor, thumbColor

    if disabled then
        trackColor = Theme.Color("disabled")
        borderColor = props.trackDisabledBorderColor or Theme.Color("border")
        thumbColor = Theme.Color("disabledText")
    else
        if value then
            if state.pressed then
                if props.trackCheckedBgColor then
                    trackColor = Style.Darken(props.trackCheckedBgColor, 0.2)
                else
                    trackColor = Theme.TryColor("primaryPressed") or Style.Darken(Theme.Color("primary"), 0.2)
                end
            elseif state.hovered then
                trackColor = props.trackCheckedHoverBgColor or Theme.Color("primaryHover") or Style.Lighten(Theme.Color("primary"), 0.1)
            else
                trackColor = props.trackCheckedBgColor or Theme.Color("primary")
            end
            borderColor = (state.hovered and (props.trackCheckedHoverBorderColor or props.trackHoverBorderColor))
                or props.trackCheckedBorderColor
                or nil
            -- on+hover: keep thumbCheckedColor (don't override with thumbHoverColor)
            thumbColor = props.thumbCheckedColor or WHITE
        else
            if state.hovered then
                trackColor = props.trackHoverBgColor or Theme.Color("surfaceHover") or Style.Lighten(Theme.Color("surface"), 0.1)
            else
                trackColor = props.trackBg or Theme.Color("surface")
            end
            borderColor = (state.hovered and props.trackHoverBorderColor) or props.trackBorderColor or Theme.Color("border")
            -- off+hover: use thumbHoverColor
            thumbColor = (state.hovered and props.thumbHoverColor) or props.thumbColor or WHITE
        end
    end

    -- Draw track
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, trackX, trackY, trackWidth, trackHeight, trackRadius)
    nvgFillColor(nvg, nvgRGBA(trackColor[1], trackColor[2], trackColor[3], trackColor[4] or 255))
    nvgFill(nvg)

    -- Draw track border
    if borderColor then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, trackX, trackY, trackWidth, trackHeight, trackRadius)
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, self.props.borderWidth or 1)
        nvgStroke(nvg)
    end

    -- Draw thumb shadow
    local thumbRadius = trackRadius and math.min(trackRadius, thumbSize / 2) or (thumbSize / 2)
    if not disabled then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, thumbX, thumbY + 1, thumbSize, thumbSize, thumbRadius)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 30))
        nvgFill(nvg)
    end

    -- Draw thumb
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, thumbX, thumbY, thumbSize, thumbSize, thumbRadius)
    nvgFillColor(nvg, nvgRGBA(thumbColor[1], thumbColor[2], thumbColor[3], thumbColor[4] or 255))
    nvgFill(nvg)

    -- Draw label
    if label and #label > 0 then
        local fontFamily = Theme.FontFamily()
        local textColor = disabled and Theme.Color("disabledText") or Theme.Color("text")
        local gap = props.gap or 8

        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, Theme.FontSizeOf("body"))
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, trackX + trackWidth + gap, l.y + l.h / 2, label, nil)
    end
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Toggle:OnMouseEnter()
    if not self.props.disabled then
        self:SetState({ hovered = true })
    end
end

function Toggle:OnMouseLeave()
    self:SetState({ hovered = false, pressed = false })
end

function Toggle:OnPointerDown(event)
    if not event then return end
    if not self.props.disabled and event:IsPrimaryButton() then
        self:SetState({ pressed = true })
    end
end

function Toggle:OnPointerUp(event)
    if not event then return end
    if event:IsPrimaryButton() then
        self:SetState({ pressed = false })
    end
end

function Toggle:OnClick()
    if not self.props.disabled then
        self:Toggle()
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Toggle the value
---@return Toggle self
function Toggle:Toggle()
    local newValue = not self.props.value
    self.props.value = newValue

    self:DispatchEvent("change", self, newValue)
    if self.props.onChange then
        self.props.onChange(self, newValue)
    end

    return self
end

--- Set value
---@param value boolean
---@return Toggle self
function Toggle:SetValue(value)
    if self.props.value ~= value then
        self.props.value = value
        self:DispatchEvent("change", self, value)
        if self.props.onChange then
            self.props.onChange(self, value)
        end
    end
    return self
end

--- Get value
---@return boolean
function Toggle:GetValue()
    return self.props.value == true
end

--- Set label text
---@param label string
---@return Toggle self
function Toggle:SetLabel(label)
    self.props.label = label
    return self
end

--- Set disabled state
---@param disabled boolean
---@return Toggle self
function Toggle:SetDisabled(disabled)
    self.props.disabled = disabled
    if disabled then
        self:SetState({ hovered = false, pressed = false })
    end
    return self
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Toggle:IsStateful()
    return true
end

return Toggle
