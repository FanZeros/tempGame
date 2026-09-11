-- ============================================================================
-- Rating Widget
-- Star rating component with interactive and read-only modes
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class RatingProps : WidgetProps
---@field value? number Current rating value (default: 0)
---@field max? number Maximum rating value (default: 5)
---@field precision? number Rating precision: 1 = full, 0.5 = half, 0.1 = tenth (default: 1)
---@field size? string "xs" | "sm" | "md" | "lg" | "xl" (default: "md")
---@field icon? string "star" | "heart" | "circle" | "square" (default: "star")
---@field readOnly? boolean Read-only mode (default: false)
---@field disabled? boolean Disabled state (default: false)
---@field highlightSelectedOnly? boolean Only highlight the selected star (default: false)
---@field showLabel? boolean Show numeric label (default: false)
---@field labelFormat? fun(value: number, max: number): string|nil Custom label format function
---@field activeColor? RGBAColor|string Color for active stars (default: warning)
---@field inactiveColor? RGBAColor|string Color for inactive stars (default: border)
---@field hoverColor? RGBAColor|string Color for hovered stars
---@field iconSize? number Custom icon size
---@field gap? number Gap between icons
---@field onChange? fun(rating: Rating, value: number) Value change callback
---@field onHover? fun(rating: Rating, value: number) Hover value callback

---@class Rating : Widget
---@overload fun(props?: RatingProps): Rating
---@field props RatingProps
---@field new fun(self, props?: RatingProps): Rating
local Rating = Widget:Extend("Rating")

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    xs = { iconSize = 16, gap = 2 },
    sm = { iconSize = 20, gap = 4 },
    md = { iconSize = 28, gap = 6 },
    lg = { iconSize = 36, gap = 8 },
    xl = { iconSize = 48, gap = 10 },
}

-- ============================================================================
-- Icon types
-- ============================================================================

local ICON_TYPES = {
    star = "star",
    heart = "heart",
    circle = "circle",
    square = "square",
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props RatingProps?
function Rating:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Rating")
    Style.ApplyDefaults(props, themeStyle)

    -- Rating props
    self.value_ = props.value or 0
    self.max_ = props.max or 5
    self.precision_ = props.precision or 1  -- 1 = full, 0.5 = half, 0.1 = tenth
    self.size_ = props.size or "md"
    self.icon_ = props.icon or "star"
    self.readOnly_ = props.readOnly or false
    self.disabled_ = props.disabled or false
    self.highlightSelectedOnly_ = props.highlightSelectedOnly or false
    self.showLabel_ = props.showLabel or false
    self.labelFormat_ = props.labelFormat or nil  -- function(value, max) return string end

    -- Colors
    self.activeColor_ = props.activeColor or Theme.Color("warning")
    self.inactiveColor_ = props.inactiveColor or Theme.Color("border")
    self.hoverColor_ = props.hoverColor or nil  -- defaults to activeColor with opacity

    -- Callbacks
    self.onChange_ = props.onChange
    self.onHover_ = props.onHover

    -- State
    self.hoverValue_ = nil
    self.isHovering_ = false

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.iconSize_ = props.iconSize or sizePreset.iconSize
    self.gap_ = props.gap or sizePreset.gap

    -- Shape params: corner rounding (star only) + outline (unlit border) width.
    self.cornerRadius_ = props.cornerRadius or 0
    self.outlineWidth_ = props.outlineWidth or 1.5

    -- Set dimensions
    local totalWidth = (self.iconSize_ * self.max_) + (self.gap_ * (self.max_ - 1))
    if self.showLabel_ then
        totalWidth = totalWidth + 50  -- space for label
    end

    props.width = props.width or totalWidth
    props.height = props.height or self.iconSize_

    Widget.Init(self, props)
end

-- ============================================================================
-- Value Management
-- ============================================================================

function Rating:GetValue()
    return self.value_
end

function Rating:SetValue(value)
    value = math.max(0, math.min(self.max_, value))
    -- Round to precision
    value = math.floor(value / self.precision_ + 0.5) * self.precision_

    if self.value_ ~= value then
        self.value_ = value
        self:DispatchEvent("change", self, value)
        if self.onChange_ then
            self.onChange_(self, value)
        end
    end
end

function Rating:GetMax()
    return self.max_
end

function Rating:SetMax(max)
    self.max_ = math.max(1, max)
    if self.value_ > self.max_ then
        self:SetValue(self.max_)
    end
end

function Rating:GetPrecision()
    return self.precision_
end

function Rating:SetPrecision(precision)
    self.precision_ = precision
end

function Rating:IsReadOnly()
    return self.readOnly_
end

function Rating:SetReadOnly(readOnly)
    self.readOnly_ = readOnly
end

function Rating:IsDisabled()
    return self.disabled_
end

function Rating:SetDisabled(disabled)
    self.disabled_ = disabled
end

-- ============================================================================
-- Icon Drawing Helpers
-- ============================================================================

local function drawStar(nvg, cx, cy, outerRadius, innerRadius, fill, cornerRadius)
    local points = 5
    local angleOffset = -math.pi / 2  -- Start from top
    local n = points * 2

    nvgBeginPath(nvg)

    if not cornerRadius or cornerRadius <= 0 then
        -- Sharp corners: straight segments between the 10 vertices.
        for i = 0, n - 1 do
            local radius = (i % 2 == 0) and outerRadius or innerRadius
            local angle = angleOffset + (i * math.pi / points)
            local x = cx + radius * math.cos(angle)
            local y = cy + radius * math.sin(angle)
            if i == 0 then
                nvgMoveTo(nvg, x, y)
            else
                nvgLineTo(nvg, x, y)
            end
        end
    else
        -- Rounded corners: precompute vertices, then arc through each one with nvgArcTo.
        -- Same path serves fill and stroke, so lit/unlit share one corner radius.
        local vx, vy = {}, {}
        for i = 0, n - 1 do
            local radius = (i % 2 == 0) and outerRadius or innerRadius
            local angle = angleOffset + (i * math.pi / points)
            vx[i] = cx + radius * math.cos(angle)
            vy[i] = cy + radius * math.sin(angle)
        end
        local r = math.min(cornerRadius, innerRadius)
        -- Begin on an edge midpoint so arcTo always has a valid current point.
        nvgMoveTo(nvg, (vx[n - 1] + vx[0]) * 0.5, (vy[n - 1] + vy[0]) * 0.5)
        for i = 0, n - 1 do
            local nxt = (i + 1) % n
            nvgArcTo(nvg, vx[i], vy[i], vx[nxt], vy[nxt], r)
        end
    end

    nvgClosePath(nvg)

    if fill then
        nvgFill(nvg)
    else
        nvgStroke(nvg)
    end
end

local function drawHeart(nvg, cx, cy, size, fill)
    local w = size * 0.9
    local h = size * 0.8

    nvgBeginPath(nvg)

    -- Heart shape using bezier curves
    local topY = cy - h * 0.3
    local bottomY = cy + h * 0.5

    nvgMoveTo(nvg, cx, bottomY)

    -- Left curve
    nvgBezierTo(nvg,
        cx - w * 0.5, cy + h * 0.1,
        cx - w * 0.5, topY,
        cx, topY + h * 0.2
    )

    -- Right curve
    nvgBezierTo(nvg,
        cx + w * 0.5, topY,
        cx + w * 0.5, cy + h * 0.1,
        cx, bottomY
    )

    nvgClosePath(nvg)

    if fill then
        nvgFill(nvg)
    else
        nvgStroke(nvg)
    end
end

local function drawCircle(nvg, cx, cy, radius, fill)
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, radius)

    if fill then
        nvgFill(nvg)
    else
        nvgStroke(nvg)
    end
end

local function drawSquare(nvg, cx, cy, size, fill)
    local half = size * 0.4

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, cx - half, cy - half, half * 2, half * 2, 2)

    if fill then
        nvgFill(nvg)
    else
        nvgStroke(nvg)
    end
end

-- ============================================================================
-- Draw Icon
-- ============================================================================

function Rating:DrawIcon(nvg, index, x, y, fillAmount, size)
    size = size or self.iconSize_  -- fallback for backwards compatibility
    local cx = x + size / 2
    local cy = y + size / 2
    local radius = size * 0.4
    local innerRadius = radius * 0.4

    local isActive = fillAmount > 0
    local isPartial = fillAmount > 0 and fillAmount < 1

    -- Determine color (as table)
    local colorTable
    if self.disabled_ then
        colorTable = Theme.Color("textDisabled")
    elseif self.isHovering_ and self.hoverValue_ and not self.readOnly_ then
        local hoverIndex = math.ceil(self.hoverValue_)
        if index <= hoverIndex then
            colorTable = self.hoverColor_ or self.activeColor_
        else
            colorTable = self.inactiveColor_
        end
    elseif isActive then
        colorTable = self.activeColor_
    else
        colorTable = self.inactiveColor_
    end

    -- Convert to NVGcolor
    local color = Theme.ToNvgColor(colorTable)
    local inactiveColor = Theme.ToNvgColor(self.inactiveColor_)

    -- Draw based on icon type
    local drawFunc
    if self.icon_ == "heart" then
        drawFunc = function(fill) drawHeart(nvg, cx, cy, size, fill) end
    elseif self.icon_ == "circle" then
        drawFunc = function(fill) drawCircle(nvg, cx, cy, radius, fill) end
    elseif self.icon_ == "square" then
        drawFunc = function(fill) drawSquare(nvg, cx, cy, size, fill) end
    else
        drawFunc = function(fill) drawStar(nvg, cx, cy, radius, innerRadius, fill, self.cornerRadius_) end
    end

    if isPartial then
        -- Draw partial fill using clipping
        -- First draw inactive background
        nvgFillColor(nvg, inactiveColor)
        drawFunc(true)

        -- Then draw partial active
        nvgSave(nvg)
        nvgIntersectScissor(nvg, x, y, size * fillAmount, size)
        nvgFillColor(nvg, color)
        drawFunc(true)
        nvgRestore(nvg)
    else
        nvgFillColor(nvg, color)
        if isActive then
            drawFunc(true)
        else
            -- Draw outline for inactive (border color + width)
            nvgStrokeColor(nvg, color)
            nvgStrokeWidth(nvg, self.outlineWidth_ or 1.5)
            drawFunc(false)
        end
    end
end

-- ============================================================================
-- Render
-- ============================================================================

function Rating:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()

    -- Render background (if any)
    Widget.Render(self, nvg)

    -- Get display value (hover value takes precedence when hovering)
    local displayValue = self.value_
    if self.isHovering_ and self.hoverValue_ and not self.readOnly_ and not self.disabled_ then
        displayValue = self.hoverValue_
    end

    -- Icon dimensions (no scale needed - nvgScale handles it)
    local iconSize = self.iconSize_
    local gap = self.gap_

    -- Draw icons
    local iconX = x
    local iconY = y + (h - iconSize) / 2

    for i = 1, self.max_ do
        local fillAmount = 0
        if i <= math.floor(displayValue) then
            fillAmount = 1
        elseif i == math.ceil(displayValue) and displayValue % 1 > 0 then
            fillAmount = displayValue % 1
        end

        self:DrawIcon(nvg, i, iconX, iconY, fillAmount, iconSize)
        iconX = iconX + iconSize + gap
    end

    -- Draw label if enabled
    if self.showLabel_ then
        local labelText
        if self.labelFormat_ then
            labelText = self.labelFormat_(displayValue, self.max_)
        else
            labelText = string.format("%.1f", displayValue)
        end

        local fontSize = Theme.FontSize(SIZE_PRESETS[self.size_].iconSize * 0.5)

        nvgFontSize(nvg, fontSize)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        local labelColor = self.disabled_ and Theme.Color("textDisabled") or Theme.Color("text")
        nvgFillColor(nvg, Theme.ToNvgColor(labelColor))
        nvgText(nvg, iconX + 8, y + h / 2, labelText)
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Rating:OnMouseEnter(event)
    if self.readOnly_ or self.disabled_ then return end
    self.isHovering_ = true
end

function Rating:OnMouseLeave(event)
    self.isHovering_ = false
    self.hoverValue_ = nil
end

function Rating:OnPointerMove(event)
    if self.readOnly_ or self.disabled_ then return end

    self.isHovering_ = true

    local x, y = self:GetAbsolutePosition()
    local localX = event.x - x

    -- Calculate which star is being hovered (no scale - coords are in base pixels)
    local starWidth = self.iconSize_ + self.gap_
    local hoverValue = localX / starWidth

    -- Round to precision
    hoverValue = math.ceil(hoverValue / self.precision_) * self.precision_
    hoverValue = math.max(0, math.min(self.max_, hoverValue))

    if self.hoverValue_ ~= hoverValue then
        self.hoverValue_ = hoverValue
        if self.onHover_ then
            self.onHover_(self, hoverValue)
        end
    end
end

--- Calculate rating value from event position
function Rating:GetValueFromEvent(event)
    local x, y = self:GetAbsolutePosition()
    local localX = event.x - x

    -- No scale - coords are in base pixels
    local starWidth = self.iconSize_ + self.gap_
    local value = localX / starWidth

    -- Round to precision
    value = math.ceil(value / self.precision_) * self.precision_
    value = math.max(0, math.min(self.max_, value))

    return value
end

function Rating:OnClick(event)
    if self.readOnly_ or self.disabled_ then return end
    if not event then return end

    -- Calculate value from click position (don't rely on hoverValue_)
    local value = self:GetValueFromEvent(event)
    self:SetValue(value)
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a simple star rating
---@param value number Initial value
---@param props table|nil Additional props
---@return Rating
function Rating.Stars(value, props)
    props = props or {}
    props.value = value
    props.icon = "star"
    return Rating(props)
end

--- Create a heart rating
---@param value number Initial value
---@param props table|nil Additional props
---@return Rating
function Rating.Hearts(value, props)
    props = props or {}
    props.value = value
    props.icon = "heart"
    props.activeColor = props.activeColor or Theme.Color("error")
    return Rating(props)
end

--- Create a read-only rating display
---@param value number The rating value
---@param max number|nil Maximum value (default 5)
---@param props table|nil Additional props
---@return Rating
function Rating.Display(value, max, props)
    props = props or {}
    props.value = value
    props.max = max or 5
    props.readOnly = true
    return Rating(props)
end

--- Create a rating with label
---@param value number Initial value
---@param props table|nil Additional props
---@return Rating
function Rating.WithLabel(value, props)
    props = props or {}
    props.value = value
    props.showLabel = true
    return Rating(props)
end

--- Create a product rating display (common e-commerce pattern)
---@param rating number The rating value
---@param reviewCount number|nil Number of reviews
---@param props table|nil Additional props
---@return Widget Container with rating and review count
function Rating.Product(rating, reviewCount, props)
    props = props or {}

    local container = Widget {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
    }

    local ratingWidget = Rating {
        value = rating,
        max = 5,
        precision = 0.1,
        readOnly = true,
        size = props.size or "sm",
        activeColor = props.activeColor,
    }
    container:AddChild(ratingWidget)

    -- Rating text
    local Label = require("urhox-libs/UI/Widgets/Label")
    container:AddChild(Label {
        text = string.format("%.1f", rating),
        fontSize = SIZE_PRESETS[props.size or "sm"].iconSize * 0.6,
        fontWeight = "bold",
        color = Theme.Color("text"),
    })

    -- Review count
    if reviewCount then
        container:AddChild(Label {
            text = string.format("(%d reviews)", reviewCount),
            fontSize = SIZE_PRESETS[props.size or "sm"].iconSize * 0.5,
            color = Theme.Color("textSecondary"),
        })
    end

    return container
end

--- Create an emoji-based rating
---@param emojis table Array of emoji strings for each level
---@param props table|nil Additional props
---@return Rating Custom rating with emoji rendering
function Rating.Emoji(emojis, props)
    props = props or {}
    -- Emoji ratings would need custom rendering - for now return standard
    props.max = #emojis
    props.icon = "circle"
    return Rating(props)
end

--- Create a feedback rating (1-5 with descriptions)
---@param props table|nil Additional props
---@return Widget Container with rating and description
function Rating.Feedback(props)
    props = props or {}

    local descriptions = props.descriptions or {
        "Very Poor",
        "Poor",
        "Average",
        "Good",
        "Excellent",
    }

    local container = Widget {
        flexDirection = "column",
        alignItems = "center",
        gap = 8,
    }

    local Label = require("urhox-libs/UI/Widgets/Label")
    local descLabel = Label {
        text = descriptions[props.value or 0] or "Select a rating",
        fontSize = Theme.BaseFontSize("body"),
        color = Theme.Color("textSecondary"),
    }

    local ratingWidget = Rating {
        value = props.value or 0,
        max = #descriptions,
        size = props.size or "lg",
        activeColor = props.activeColor,
        onChange = function(self, value)
            local desc = descriptions[math.floor(value)] or ""
            descLabel:SetText(desc)
            if props.onChange then
                props.onChange(self, value, desc)
            end
        end,
    }

    container:AddChild(ratingWidget)
    container:AddChild(descLabel)

    -- Store reference for external access
    container.rating = ratingWidget
    container.descLabel = descLabel

    return container
end

return Rating
