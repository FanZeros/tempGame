-- ============================================================================
-- Slider Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Value slider with track and thumb
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class SliderProps : WidgetProps
---@field value? number Current value (default: min)
---@field min? number Minimum value (default: 0)
---@field max? number Maximum value (default: 1)
---@field step? number Step increment
---@field disabled? boolean Is slider disabled
---@field trackHeight? number Track height (default: 4)
---@field thumbSize? number Thumb size (default: 16)
---@field trackFillGradient? table Gradient fill for track { direction: string, from: {RGBA}, to: {RGBA} }
---@field thumbBorderGradient? table Gradient stroke for thumb border { direction: string, from: {RGBA}, to: {RGBA} }
---@field thumbBoxShadow? table|false Custom thumb shadow, or false to disable
---@field onChange? fun(self: Slider, value: number) Change callback
---@field onChangeEnd? fun(self: Slider, value: number) Change end callback

---@class Slider : Widget
---@overload fun(props?: SliderProps): Slider
---@field props SliderProps
---@field new fun(self, props?: SliderProps): Slider
---@field state {hovered: boolean, dragging: boolean}
---@field AddChild fun(self, child: Widget): self Add child widget
---@field RemoveChild fun(self, child: Widget): self Remove child widget
local Slider = Widget:Extend("Slider")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props SliderProps?
function Slider:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("Slider")
    Style.ApplyDefaults(props, themeStyle)
    -- Hardcoded fallbacks (only hit when theme has no entry)
    props.trackHeight = props.trackHeight or 4
    props.thumbSize = props.thumbSize or 16

    -- Default range
    props.min = props.min or 0
    props.max = props.max or 1
    props.value = props.value or props.min

    -- Set widget height based on thumb size
    props.height = props.height or math.max(props.thumbSize + 8, 24)

    -- Parse string colors in gradients before Widget.Init
    if props.trackFillGradient then
        if type(props.trackFillGradient.from) == "string" then
            props.trackFillGradient.from = Style.ParseColor(props.trackFillGradient.from)
        end
        if type(props.trackFillGradient.to) == "string" then
            props.trackFillGradient.to = Style.ParseColor(props.trackFillGradient.to)
        end
    end
    if props.thumbBorderGradient then
        if type(props.thumbBorderGradient.from) == "string" then
            props.thumbBorderGradient.from = Style.ParseColor(props.thumbBorderGradient.from)
        end
        if type(props.thumbBorderGradient.to) == "string" then
            props.thumbBorderGradient.to = Style.ParseColor(props.thumbBorderGradient.to)
        end
    end

    -- Initialize state
    self.state = {
        hovered = false,
        dragging = false,
    }

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Slider:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    local value = props.value
    local min = props.min
    local max = props.max
    local disabled = props.disabled
    local trackHeight = props.trackHeight
    local thumbSize = props.thumbSize

    -- Calculate normalized value (0-1)
    local normalizedValue = (value - min) / (max - min)
    normalizedValue = math.max(0, math.min(1, normalizedValue))

    -- Track dimensions
    local trackX = l.x + thumbSize / 2
    local trackWidth = l.w - thumbSize
    local trackY = l.y + (l.h - trackHeight) / 2
    local trackRadius = math.min(self.props.borderRadius or (trackHeight / 2), math.max(math.min(trackWidth, trackHeight), 0) / 2)

    -- Thumb position
    local thumbX = trackX + normalizedValue * trackWidth - thumbSize / 2
    local thumbY = l.y + (l.h - thumbSize) / 2

    -- Colors (props tokens override Theme defaults for per-theme customization)
    local trackBgColor = disabled and Theme.Color("disabled")
        or self.props.trackBgColor or Theme.Color("surface")
    local trackFillColor = disabled and Theme.Color("disabledText")
        or self.props.trackFillColor or Theme.Color("primary")
    local customThumbColor = self.props.thumbColor
    local baseThumbColor = customThumbColor or Theme.Color("primary")
    local thumbColor

    if disabled then
        thumbColor = Theme.Color("disabledText")
    elseif state.dragging then
        thumbColor = customThumbColor and Style.Darken(customThumbColor, 0.2)
            or (Theme.Color("primaryPressed") or Style.Darken(baseThumbColor, 0.2))
    elseif state.hovered then
        thumbColor = customThumbColor and Style.Lighten(customThumbColor, 0.1)
            or (Theme.Color("primaryHover") or Style.Lighten(baseThumbColor, 0.1))
    else
        thumbColor = baseThumbColor
    end

    -- Draw track background
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, trackX, trackY, trackWidth, trackHeight, trackRadius)
    nvgFillColor(nvg, nvgRGBA(trackBgColor[1], trackBgColor[2], trackBgColor[3], trackBgColor[4] or 255))
    nvgFill(nvg)

    -- Draw track border (only when borderWidth is set via theme)
    local trackBorderWidth = self.props.borderWidth
    if trackBorderWidth and trackBorderWidth > 0 then
        local trackBorderColor = self.props.borderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, trackX, trackY, trackWidth, trackHeight, trackRadius)
        nvgStrokeColor(nvg, nvgRGBA(trackBorderColor[1], trackBorderColor[2], trackBorderColor[3], trackBorderColor[4] or 255))
        nvgStrokeWidth(nvg, trackBorderWidth)
        nvgStroke(nvg)
    end

    -- Draw track fill (from left to thumb)
    local fillWidth = normalizedValue * trackWidth
    if fillWidth > 0 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, trackX, trackY, fillWidth, trackHeight, trackRadius)
        local trackFillGradient = not disabled and self.props.trackFillGradient or nil
        if trackFillGradient and trackFillGradient.from and trackFillGradient.to then
            local sx, sy, ex, ey = Widget.ResolveGradientDirection(
                trackFillGradient.direction or "to-right", trackX, trackY, fillWidth, trackHeight)
            local c1 = nvgRGBA(trackFillGradient.from[1], trackFillGradient.from[2], trackFillGradient.from[3], trackFillGradient.from[4] or 255)
            local c2 = nvgRGBA(trackFillGradient.to[1], trackFillGradient.to[2], trackFillGradient.to[3], trackFillGradient.to[4] or 255)
            nvgFillPaint(nvg, nvgLinearGradient(nvg, sx, sy, ex, ey, c1, c2))
        else
            nvgFillColor(nvg, nvgRGBA(trackFillColor[1], trackFillColor[2], trackFillColor[3], trackFillColor[4] or 255))
        end
        nvgFill(nvg)
    end

    -- Thumb radius: thumbBorderRadius > borderRadius > circle (thumbSize/2)
    local thumbRadius = self.props.thumbBorderRadius ~= nil and self.props.thumbBorderRadius
        or (self.props.borderRadius ~= nil and self.props.borderRadius or (thumbSize / 2))
    thumbRadius = math.min(thumbRadius, thumbSize / 2)

    -- Draw thumb shadow
    local thumbBoxShadow = self.props.thumbBoxShadow
    if not disabled and thumbBoxShadow ~= false then
        if thumbBoxShadow then
            local thumbGeom = self:GetShapeGeometry({ x = thumbX, y = thumbY, w = thumbSize, h = thumbSize }, nil, thumbRadius)
            self:RenderBoxShadows(nvg, thumbGeom, thumbBoxShadow)
        else
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, thumbX, thumbY + 1, thumbSize, thumbSize, thumbRadius)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 40))
            nvgFill(nvg)
        end
    end

    -- Draw thumb
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, thumbX, thumbY, thumbSize, thumbSize, thumbRadius)
    nvgFillColor(nvg, nvgRGBA(thumbColor[1], thumbColor[2], thumbColor[3], thumbColor[4] or 255))
    nvgFill(nvg)

    -- Draw thumb border
    local thumbBorderColor = self.props.thumbBorderColor
    local thumbBorderWidth = self.props.thumbBorderWidth
    local thumbBorderGradient = self.props.thumbBorderGradient
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, thumbX, thumbY, thumbSize, thumbSize, thumbRadius)
    if thumbBorderGradient and thumbBorderGradient.from and thumbBorderGradient.to then
        local sx, sy, ex, ey = Widget.ResolveGradientDirection(
            thumbBorderGradient.direction or "to-bottom", thumbX, thumbY, thumbSize, thumbSize)
        local c1 = nvgRGBA(thumbBorderGradient.from[1], thumbBorderGradient.from[2], thumbBorderGradient.from[3], thumbBorderGradient.from[4] or 255)
        local c2 = nvgRGBA(thumbBorderGradient.to[1], thumbBorderGradient.to[2], thumbBorderGradient.to[3], thumbBorderGradient.to[4] or 255)
        nvgStrokePaint(nvg, nvgLinearGradient(nvg, sx, sy, ex, ey, c1, c2))
    elseif thumbBorderColor then
        nvgStrokeColor(nvg, nvgRGBA(thumbBorderColor[1], thumbBorderColor[2], thumbBorderColor[3], thumbBorderColor[4] or 255))
    else
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 100))
    end
    nvgStrokeWidth(nvg, thumbBorderWidth or 1)
    nvgStroke(nvg)
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Slider:OnMouseEnter()
    if not self.props.disabled then
        self:SetState({ hovered = true })
    end
end

function Slider:OnMouseLeave()
    if not self.state.dragging then
        self:SetState({ hovered = false })
    end
end

function Slider:OnPointerDown(event)
    Widget.OnPointerDown(self, event)

    if not self.props.disabled and event:IsPrimaryAction() then
        self:SetState({ dragging = true })
        self:UpdateValueFromPosition(event.x)
    end
end

function Slider:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    if self.state.dragging then
        self:UpdateValueFromPosition(event.x)
    end
end

function Slider:OnPointerUp(event)
    Widget.OnPointerUp(self, event)

    if self.state.dragging then
        self:SetState({ dragging = false })
        if self.props.onChangeEnd then
            self.props.onChangeEnd(self, self.props.value)
        end
    end
end

-- Pan gesture support for mobile
-- Returns true if Slider handles this pan gesture (prevents ScrollView from scrolling)
function Slider:OnPanStart(event)
    if not self.props.disabled then
        self:SetState({ dragging = true })
        self:UpdateValueFromPosition(event.x)
        return true  -- We're handling this pan gesture
    end
    return false
end

function Slider:OnPanMove(event)
    if self.state.dragging then
        self:UpdateValueFromPosition(event.x)
    end
end

function Slider:OnPanEnd(event)
    if self.state.dragging then
        self:SetState({ dragging = false })
        if self.props.onChangeEnd then
            self.props.onChangeEnd(self, self.props.value)
        end
    end
end

-- ============================================================================
-- Internal
-- ============================================================================

--- Update value from pointer X position
---@param x number
function Slider:UpdateValueFromPosition(x)
    -- Use GetAbsoluteLayoutForHitTest for proper scroll offset handling
    local l = self:GetAbsoluteLayoutForHitTest()
    local thumbSize = self.props.thumbSize

    local trackX = l.x + thumbSize / 2
    local trackWidth = l.w - thumbSize

    -- Calculate normalized value
    local normalizedValue = (x - trackX) / trackWidth
    normalizedValue = math.max(0, math.min(1, normalizedValue))

    -- Convert to actual value
    local min = self.props.min
    local max = self.props.max
    local newValue = min + normalizedValue * (max - min)

    -- Apply step if defined
    local step = self.props.step
    if step and step > 0 then
        newValue = math.floor(newValue / step + 0.5) * step
    end

    -- Clamp to range
    newValue = math.max(min, math.min(max, newValue))

    self:SetValue(newValue)
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set value
---@param value number
---@return Slider self
function Slider:SetValue(value)
    local min = self.props.min
    local max = self.props.max
    value = math.max(min, math.min(max, value))

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
---@return number
function Slider:GetValue()
    return self.props.value
end

--- Set range
---@param min number
---@param max number
---@return Slider self
function Slider:SetRange(min, max)
    self.props.min = min
    self.props.max = max
    -- Clamp current value to new range
    self.props.value = math.max(min, math.min(max, self.props.value))
    return self
end

--- Set disabled state
---@param disabled boolean
---@return Slider self
function Slider:SetDisabled(disabled)
    self.props.disabled = disabled
    if disabled then
        self:SetState({ hovered = false, dragging = false })
    end
    return self
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Slider:IsStateful()
    return true
end

return Slider
