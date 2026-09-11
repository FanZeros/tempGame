-- ============================================================================
-- Checkbox Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Checkbox with label
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class CheckboxProps : WidgetProps
---@field checked? boolean Is checkbox checked
---@field label? string Label text
---@field disabled? boolean Is checkbox disabled
---@field size? number Checkbox size (default: 20)
---@field uncheckedBorderColor? RGBAColor|string Unchecked border color
---@field uncheckedHoverBorderColor? RGBAColor|string Unchecked hover border color
---@field checkedBorderColor? RGBAColor|string Checked border color
---@field checkedHoverBorderColor? RGBAColor|string Checked hover border color
---@field uncheckedBgColor? RGBAColor|string Unchecked background color
---@field uncheckedHoverBgColor? RGBAColor|string Unchecked hover background color
---@field checkedHoverBgColor? RGBAColor|string Checked hover background color
---@field checkedPressedBgColor? RGBAColor|string Checked pressed background color
---@field disabledBorderColor? RGBAColor|string Disabled border color
---@field onChange? fun(self: Checkbox, checked: boolean) Change callback

---@class Checkbox : Widget
---@overload fun(props?: CheckboxProps): Checkbox
---@field props CheckboxProps
---@field new fun(self, props?: CheckboxProps): Checkbox
---@field state {hovered: boolean, pressed: boolean}
local Checkbox = Widget:Extend("Checkbox")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props CheckboxProps?
function Checkbox:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("Checkbox")
    Style.ApplyDefaults(props, themeStyle)
    -- Hardcoded fallbacks (only hit when theme has no entry)
    props.size = props.size or 20
    props.borderRadius = props.borderRadius or 4

    -- Default flex direction for label layout
    props.flexDirection = "row"
    props.alignItems = "center"
    props.gap = props.gap or 8

    -- Default height based on checkbox size
    props.height = props.height or math.max(props.size + 4, 28)

    -- Default width: checkbox + gap + label estimate
    if not props.width then
        local labelWidth = 0
        if props.label and #props.label > 0 then
            labelWidth = #props.label * 14 * 0.55 + (props.gap or 8)
        end
        props.width = props.size + labelWidth
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

function Checkbox:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    local checked = props.checked
    local disabled = props.disabled
    local size = props.size
    local borderRadius = props.borderRadius
    local label = props.label

    -- Box position
    local boxX = l.x
    local boxY = l.y + (l.h - size) / 2

    -- Colors
    local boxBgColor, borderColor, checkColor

    if disabled then
        boxBgColor = Theme.Color("disabled")
        borderColor = self.props.disabledBorderColor or Theme.Color("border")
        checkColor = Theme.Color("disabledText")
    else
        if checked then
            local checkedBase = self.props.checkedBgColor
            if state.pressed then
                boxBgColor = self.props.checkedPressedBgColor
                    or (checkedBase and Style.Darken(checkedBase, 0.2))
                    or (Theme.Color("primaryPressed") or Style.Darken(Theme.Color("primary"), 0.2))
            elseif state.hovered then
                boxBgColor = self.props.checkedHoverBgColor
                    or (checkedBase and Style.Lighten(checkedBase, 0.1))
                    or (Theme.Color("primaryHover") or Style.Lighten(Theme.Color("primary"), 0.1))
            else
                boxBgColor = checkedBase or Theme.Color("primary")
            end
            borderColor = state.hovered
                and (self.props.checkedHoverBorderColor or self.props.checkedBorderColor or boxBgColor)
                or (self.props.checkedBorderColor or boxBgColor)
            checkColor = self.props.checkmarkColor or { 255, 255, 255, 255 }
        else
            boxBgColor = state.hovered
                and (self.props.uncheckedHoverBgColor or Theme.Color("surfaceHover"))
                or (self.props.uncheckedBgColor or Theme.Color("surface"))
            borderColor = state.hovered
                and (self.props.uncheckedHoverBorderColor or self.props.hoverBorderColor or Theme.Color("primary"))
                or (self.props.uncheckedBorderColor or Theme.Color("border"))
            checkColor = Theme.Color("text")
        end
    end

    -- Draw box background
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, boxX, boxY, size, size, borderRadius)
    nvgFillColor(nvg, nvgRGBA(boxBgColor[1], boxBgColor[2], boxBgColor[3], boxBgColor[4] or 255))
    nvgFill(nvg)

    -- Draw border
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, boxX, boxY, size, size, borderRadius)
    nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
    nvgStrokeWidth(nvg, self.props.borderWidth or 1.5)
    nvgStroke(nvg)

    -- Draw checkmark if checked
    if checked then
        nvgBeginPath(nvg)
        -- Checkmark path
        local cx = boxX + size / 2
        local cy = boxY + size / 2
        local s = size * 0.3

        nvgMoveTo(nvg, cx - s, cy)
        nvgLineTo(nvg, cx - s * 0.3, cy + s * 0.7)
        nvgLineTo(nvg, cx + s, cy - s * 0.6)

        nvgStrokeColor(nvg, nvgRGBA(checkColor[1], checkColor[2], checkColor[3], checkColor[4] or 255))
        nvgStrokeWidth(nvg, 2)
        nvgLineCap(nvg, NVG_ROUND)
        nvgLineJoin(nvg, NVG_ROUND)
        nvgStroke(nvg)
    end

    -- Draw label
    if label and #label > 0 then
        local fontFamily = Theme.FontFamily()
        local textColor = disabled and Theme.Color("disabledText") or Theme.Color("text")
        local gap = props.gap or 8

        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, Theme.FontSizeOf("body"))
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, boxX + size + gap, l.y + l.h / 2, label, nil)
    end
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Checkbox:OnMouseEnter()
    if not self.props.disabled then
        self:SetState({ hovered = true })
    end
end

function Checkbox:OnMouseLeave()
    self:SetState({ hovered = false, pressed = false })
end

function Checkbox:OnPointerDown(event)
    if not event then return end
    if not self.props.disabled and event:IsPrimaryAction() then
        self:SetState({ pressed = true })
    end
end

function Checkbox:OnPointerUp(event)
    if not event then return end
    if event:IsPrimaryAction() then
        self:SetState({ pressed = false })
    end
end

function Checkbox:OnClick()
    if not self.props.disabled then
        self:Toggle()
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Toggle checked state
---@return Checkbox self
function Checkbox:Toggle()
    local newChecked = not self.props.checked
    self.props.checked = newChecked

    self:DispatchEvent("change", self, newChecked)
    if self.props.onChange then
        self.props.onChange(self, newChecked)
    end

    return self
end

--- Set checked state
---@param checked boolean
---@return Checkbox self
function Checkbox:SetChecked(checked)
    if self.props.checked ~= checked then
        self.props.checked = checked
        self:DispatchEvent("change", self, checked)
        if self.props.onChange then
            self.props.onChange(self, checked)
        end
    end
    return self
end

--- Get checked state
---@return boolean
function Checkbox:IsChecked()
    return self.props.checked == true
end

--- Set label text
---@param label string
---@return Checkbox self
function Checkbox:SetLabel(label)
    self.props.label = label
    return self
end

--- Set disabled state
---@param disabled boolean
---@return Checkbox self
function Checkbox:SetDisabled(disabled)
    self.props.disabled = disabled
    if disabled then
        self:SetState({ hovered = false, pressed = false })
    end
    return self
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Checkbox:IsStateful()
    return true
end

return Checkbox
