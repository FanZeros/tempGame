-- ============================================================================
-- Divider Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Horizontal or vertical divider line with optional label
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class DividerProps : WidgetProps
---@field orientation? string "horizontal" | "vertical" (default: "horizontal")
---@field variant? string "solid" | "dashed" | "dotted" (default: "solid")
---@field thickness? number Line thickness in pixels (default: 1)
---@field color? RGBAColor|string Custom color (default: border color)
---@field inset? string|number "none" | "left" | "right" | "both" | number
---@field label? string Text label in the middle
---@field labelPosition? string "center" | "left" | "right" (default: "center")
---@field spacing? number Spacing around the divider (default: 0)

---@class Divider : Widget
---@overload fun(props?: DividerProps): Divider
---@field props DividerProps
---@field new fun(self, props?: DividerProps): Divider
local Divider = Widget:Extend("Divider")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props DividerProps?
function Divider:Init(props)
    props = props or {}

    -- Default settings
    props.orientation = props.orientation or "horizontal"
    props.variant = props.variant or "solid"
    props.thickness = props.thickness or 1
    props.inset = props.inset or "none"
    props.labelPosition = props.labelPosition or "center"
    props.spacing = props.spacing or 0

    -- Set default dimensions based on orientation
    if props.orientation == "horizontal" then
        props.width = props.width or "100%"
        props.height = props.height or (props.thickness + props.spacing * 2)
    else
        props.width = props.width or (props.thickness + props.spacing * 2)
        props.height = props.height or "100%"
    end

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Divider:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props

    local orientation = props.orientation
    local variant = props.variant
    local thickness = props.thickness
    local color = props.color or Theme.Color("border")
    local inset = props.inset
    local label = props.label
    local spacing = props.spacing

    -- Calculate inset values
    local insetLeft = 0
    local insetRight = 0

    if type(inset) == "number" then
        insetLeft = inset
        insetRight = inset
    elseif inset == "left" then
        insetLeft = 16
    elseif inset == "right" then
        insetRight = 16
    elseif inset == "both" then
        insetLeft = 16
        insetRight = 16
    end

    if orientation == "horizontal" then
        self:RenderHorizontal(nvg, l, color, thickness, variant, insetLeft, insetRight, label, spacing)
    else
        self:RenderVertical(nvg, l, color, thickness, variant, insetLeft, insetRight, spacing)
    end
end

--- Render horizontal divider
function Divider:RenderHorizontal(nvg, l, color, thickness, variant, insetLeft, insetRight, label, spacing)
    local props = self.props
    local y = l.y + l.h / 2
    local startX = l.x + insetLeft
    local endX = l.x + l.w - insetRight

    if label and #label > 0 then
        -- Render divider with label
        local fontFamily = Theme.FontFamily()
        local fontSize = Theme.FontSizeOf("small")
        local labelPadding = 12

        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, fontSize)

        local textWidth = nvgTextBounds(nvg, 0, 0, label, nil, nil)
        local totalWidth = endX - startX

        local labelX
        if props.labelPosition == "left" then
            labelX = startX + labelPadding + textWidth / 2
        elseif props.labelPosition == "right" then
            labelX = endX - labelPadding - textWidth / 2
        else -- center
            labelX = startX + totalWidth / 2
        end

        -- Draw left line
        local leftLineEnd = labelX - textWidth / 2 - labelPadding
        if leftLineEnd > startX then
            self:DrawLine(nvg, startX, y, leftLineEnd, y, color, thickness, variant)
        end

        -- Draw right line
        local rightLineStart = labelX + textWidth / 2 + labelPadding
        if rightLineStart < endX then
            self:DrawLine(nvg, rightLineStart, y, endX, y, color, thickness, variant)
        end

        -- Draw label
        local textColor = Theme.Color("textSecondary")
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, labelX, y, label, nil)
    else
        -- Render simple line
        self:DrawLine(nvg, startX, y, endX, y, color, thickness, variant)
    end
end

--- Render vertical divider
function Divider:RenderVertical(nvg, l, color, thickness, variant, insetTop, insetBottom, spacing)
    local x = l.x + l.w / 2
    local startY = l.y + insetTop
    local endY = l.y + l.h - insetBottom

    self:DrawLine(nvg, x, startY, x, endY, color, thickness, variant)
end

--- Draw a line with the specified variant
function Divider:DrawLine(nvg, x1, y1, x2, y2, color, thickness, variant)
    if variant == "dashed" then
        self:DrawDashedLine(nvg, x1, y1, x2, y2, color, thickness, 8, 4)
    elseif variant == "dotted" then
        self:DrawDottedLine(nvg, x1, y1, x2, y2, color, thickness, 2)
    else -- solid
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x1, y1)
        nvgLineTo(nvg, x2, y2)
        nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
        nvgStrokeWidth(nvg, thickness)
        nvgStroke(nvg)
    end
end

--- Draw a dashed line
function Divider:DrawDashedLine(nvg, x1, y1, x2, y2, color, thickness, dashLength, gapLength)
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)

    if length == 0 then return end

    local unitX = dx / length
    local unitY = dy / length

    local segmentLength = dashLength + gapLength
    local currentPos = 0

    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, thickness)

    while currentPos < length do
        local dashEnd = math.min(currentPos + dashLength, length)

        local startX = x1 + unitX * currentPos
        local startY = y1 + unitY * currentPos
        local endX = x1 + unitX * dashEnd
        local endY = y1 + unitY * dashEnd

        nvgBeginPath(nvg)
        nvgMoveTo(nvg, startX, startY)
        nvgLineTo(nvg, endX, endY)
        nvgStroke(nvg)

        currentPos = currentPos + segmentLength
    end
end

--- Draw a dotted line
function Divider:DrawDottedLine(nvg, x1, y1, x2, y2, color, thickness, dotSpacing)
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)

    if length == 0 then return end

    local unitX = dx / length
    local unitY = dy / length

    local dotRadius = thickness
    local segmentLength = dotRadius * 2 + dotSpacing
    local currentPos = 0

    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))

    while currentPos < length do
        local dotX = x1 + unitX * currentPos
        local dotY = y1 + unitY * currentPos

        nvgBeginPath(nvg)
        nvgCircle(nvg, dotX, dotY, dotRadius)
        nvgFill(nvg)

        currentPos = currentPos + segmentLength
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set orientation
---@param orientation string "horizontal" | "vertical"
---@return Divider self
function Divider:SetOrientation(orientation)
    self.props.orientation = orientation
    return self
end

--- Set variant
---@param variant string "solid" | "dashed" | "dotted"
---@return Divider self
function Divider:SetVariant(variant)
    self.props.variant = variant
    return self
end

--- Set thickness
---@param thickness number
---@return Divider self
function Divider:SetThickness(thickness)
    self.props.thickness = thickness
    return self
end

--- Set color
--- Supports multiple formats: RGBA table, hex string, or CSS rgb/rgba
---@param color table|string RGBA table or color string (e.g., "#ff0000", "rgba(255,0,0,1)")
---@return Divider self
function Divider:SetColor(color)
    self.props.color = Style.ParseColor(color) or color
    return self
end

--- Set inset
---@param inset string|number "none" | "left" | "right" | "both" | number
---@return Divider self
function Divider:SetInset(inset)
    self.props.inset = inset
    return self
end

--- Set label
---@param label string|nil
---@return Divider self
function Divider:SetLabel(label)
    self.props.label = label
    return self
end

--- Set label position
---@param position string "center" | "left" | "right"
---@return Divider self
function Divider:SetLabelPosition(position)
    self.props.labelPosition = position
    return self
end

--- Set spacing
---@param spacing number
---@return Divider self
function Divider:SetSpacing(spacing)
    self.props.spacing = spacing
    return self
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Divider:IsStateful()
    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a horizontal divider
---@param options table|nil
---@return Divider
function Divider.Horizontal(options)
    options = options or {}
    options.orientation = "horizontal"
    return Divider:new(options)
end

--- Create a vertical divider
---@param options table|nil
---@return Divider
function Divider.Vertical(options)
    options = options or {}
    options.orientation = "vertical"
    return Divider:new(options)
end

--- Create a divider with label
---@param label string
---@param options table|nil
---@return Divider
function Divider.WithLabel(label, options)
    options = options or {}
    options.label = label
    options.orientation = options.orientation or "horizontal"
    return Divider:new(options)
end

--- Create a section divider (thicker, with more spacing)
---@param label string|nil
---@param options table|nil
---@return Divider
function Divider.Section(label, options)
    options = options or {}
    options.label = label
    options.thickness = options.thickness or 2
    options.spacing = options.spacing or 16
    options.orientation = "horizontal"
    return Divider:new(options)
end

return Divider
