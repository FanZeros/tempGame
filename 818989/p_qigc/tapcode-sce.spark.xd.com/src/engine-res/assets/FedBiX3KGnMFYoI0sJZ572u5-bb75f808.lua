-- ============================================================================
-- Skeleton Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Placeholder loading skeleton with shimmer animation
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class SkeletonProps : WidgetProps
---@field variant? string "text" | "rectangular" | "circular" | "rounded" (default: "text")
---@field animation? string "pulse" | "wave" | "none" (default: "pulse")
---@field width? number|string Width (default: 40 for circular, "100%" for others)
---@field height? number|string Height (default: 40 for circular, auto-calculated for text)
---@field lines? number Number of text lines for text variant (default: 1)
---@field lineHeight? number Height of each text line (default: 16)
---@field lineSpacing? number Spacing between text lines (default: 8)
---@field lastLineWidth? string|number Width of the last line e.g. "60%" (default: "80%")
---@field baseColor? RGBAColor|string Skeleton block base color
---@field highlightColor? RGBAColor|string Skeleton animation highlight color

---@class Skeleton : Widget
---@overload fun(props?: SkeletonProps): Skeleton
---@field props SkeletonProps
---@field new fun(self, props?: SkeletonProps): Skeleton
local Skeleton = Widget:Extend("Skeleton")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props SkeletonProps?
function Skeleton:Init(props)
    props = props or {}

    -- Default settings
    props.variant = props.variant or "text"
    props.animation = props.animation or "pulse"
    props.lines = props.lines or 1
    props.lineHeight = props.lineHeight or 16
    props.lineSpacing = props.lineSpacing or 8
    props.lastLineWidth = props.lastLineWidth or "80%"

    -- Default dimensions based on variant
    if props.variant == "circular" then
        props.width = props.width or 40
        props.height = props.height or 40
    elseif props.variant == "text" then
        props.width = props.width or "100%"
        local totalHeight = props.lines * props.lineHeight + (props.lines - 1) * props.lineSpacing
        props.height = props.height or totalHeight
    else
        props.width = props.width or "100%"
        props.height = props.height or 100
    end

    -- Animation state
    self.animationPhase_ = 0
    self.wavePosition_ = -1

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Skeleton:Render(nvg)
    Widget.Render(self, nvg)

    local l = self:GetAbsoluteLayout()
    local props = self.props

    local variant = props.variant

    if variant == "text" then
        self:RenderTextSkeleton(nvg, l)
    elseif variant == "circular" then
        self:RenderCircularSkeleton(nvg, l)
    elseif variant == "rounded" then
        self:RenderRoundedSkeleton(nvg, l)
    else -- rectangular
        self:RenderRectangularSkeleton(nvg, l)
    end
end

--- Render text skeleton (multiple lines)
function Skeleton:RenderTextSkeleton(nvg, l)
    local props = self.props
    local lines = props.lines
    local lineHeight = props.lineHeight
    local lineSpacing = props.lineSpacing
    local lastLineWidth = props.lastLineWidth

    local y = l.y

    for i = 1, lines do
        local lineWidth = l.w
        if i == lines and lines > 1 then
            -- Last line is shorter
            if type(lastLineWidth) == "string" and string.match(lastLineWidth, "%%$") then
                local percent = tonumber(string.match(lastLineWidth, "(%d+)")) or 80
                lineWidth = l.w * percent / 100
            elseif type(lastLineWidth) == "number" then
                lineWidth = lastLineWidth
            end
        end

        self:RenderSkeletonRect(nvg, l.x, y, lineWidth, lineHeight, lineHeight / 2)
        y = y + lineHeight + lineSpacing
    end
end

--- Render circular skeleton
function Skeleton:RenderCircularSkeleton(nvg, l)
    local radius = math.min(l.w, l.h) / 2
    local cx = l.x + l.w / 2
    local cy = l.y + l.h / 2

    local baseColor = self:GetBaseColor()
    local highlightColor = self:GetHighlightColor()

    -- Draw base circle
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, radius)
    nvgFillColor(nvg, nvgRGBA(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 255))
    nvgFill(nvg)

    -- Draw animation overlay
    self:RenderAnimationOverlayCircle(nvg, cx, cy, radius, highlightColor)
end

--- Render rectangular skeleton
function Skeleton:RenderRectangularSkeleton(nvg, l)
    local borderRadius = self.props.borderRadius ~= nil and self.props.borderRadius or 0
    self:RenderSkeletonRect(nvg, l.x, l.y, l.w, l.h, borderRadius)
end

--- Render rounded skeleton
function Skeleton:RenderRoundedSkeleton(nvg, l)
    local borderRadius = self.props.borderRadius ~= nil and self.props.borderRadius or math.min(l.h / 4, 8)
    self:RenderSkeletonRect(nvg, l.x, l.y, l.w, l.h, borderRadius)
end

--- Render a skeleton rectangle with animation
function Skeleton:RenderSkeletonRect(nvg, x, y, width, height, borderRadius)
    local props = self.props
    local baseColor = self:GetBaseColor()
    local highlightColor = self:GetHighlightColor()

    -- Draw base rectangle
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 255))
    nvgFill(nvg)

    -- Draw animation overlay
    if props.animation == "pulse" then
        self:RenderPulseAnimation(nvg, x, y, width, height, borderRadius, highlightColor)
    elseif props.animation == "wave" then
        self:RenderWaveAnimation(nvg, x, y, width, height, borderRadius, highlightColor)
    end
end

--- Render pulse animation
function Skeleton:RenderPulseAnimation(nvg, x, y, width, height, borderRadius, color)
    local alpha = math.abs(math.sin(self.animationPhase_)) * 0.4
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], math.floor(255 * alpha)))
    nvgFill(nvg)
end

--- Render wave/shimmer animation
function Skeleton:RenderWaveAnimation(nvg, x, y, width, height, borderRadius, color)
    local waveWidth = width * 0.5
    local waveX = x + self.wavePosition_ * (width + waveWidth) - waveWidth

    -- Create gradient effect using multiple rectangles
    local steps = 10
    local stepWidth = waveWidth / steps

    nvgSave(nvg)

    -- Clip to skeleton bounds
    nvgIntersectScissor(nvg, x, y, width, height)

    for i = 0, steps - 1 do
        local stepX = waveX + i * stepWidth
        local alpha = math.sin((i / steps) * math.pi) * 0.6

        nvgBeginPath(nvg)
        nvgRect(nvg, stepX, y, stepWidth + 1, height)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], math.floor(255 * alpha)))
        nvgFill(nvg)
    end

    nvgRestore(nvg)
end

--- Render animation overlay for circle
function Skeleton:RenderAnimationOverlayCircle(nvg, cx, cy, radius, color)
    local props = self.props

    if props.animation == "pulse" then
        local alpha = math.abs(math.sin(self.animationPhase_)) * 0.4
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, radius)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], math.floor(255 * alpha)))
        nvgFill(nvg)
    elseif props.animation == "wave" then
        -- Simplified wave for circles
        local alpha = math.abs(math.sin(self.animationPhase_ * 2)) * 0.4
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, radius)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], math.floor(255 * alpha)))
        nvgFill(nvg)
    end
end

--- Get base color for skeleton
function Skeleton:GetBaseColor()
    if self.props.baseColor then
        return self.props.baseColor
    end

    local surface = Theme.Color("surface")
    -- Slightly darker than surface
    return {
        math.max(0, surface[1] - 15),
        math.max(0, surface[2] - 15),
        math.max(0, surface[3] - 15),
        surface[4] or 255
    }
end

--- Get highlight color for animation
function Skeleton:GetHighlightColor()
    if self.props.highlightColor then
        return self.props.highlightColor
    end

    local surface = Theme.Color("surface")
    -- Lighter than surface
    return {
        math.min(255, surface[1] + 30),
        math.min(255, surface[2] + 30),
        math.min(255, surface[3] + 30),
        255
    }
end

-- ============================================================================
-- Update
-- ============================================================================

function Skeleton:Update(dt)
    local props = self.props

    if props.animation == "pulse" then
        self.animationPhase_ = self.animationPhase_ + dt * 3
        if self.animationPhase_ > math.pi * 2 then
            self.animationPhase_ = self.animationPhase_ - math.pi * 2
        end
    elseif props.animation == "wave" then
        self.wavePosition_ = self.wavePosition_ + dt * 0.8
        if self.wavePosition_ > 1.5 then
            self.wavePosition_ = -0.5
        end
        -- Also update phase for fallback
        self.animationPhase_ = self.animationPhase_ + dt * 3
        if self.animationPhase_ > math.pi * 2 then
            self.animationPhase_ = self.animationPhase_ - math.pi * 2
        end
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set variant
---@param variant string "text" | "rectangular" | "circular" | "rounded"
---@return Skeleton self
function Skeleton:SetVariant(variant)
    self.props.variant = variant
    return self
end

--- Set animation type
---@param animation string "pulse" | "wave" | "none"
---@return Skeleton self
function Skeleton:SetAnimation(animation)
    self.props.animation = animation
    return self
end

--- Set number of text lines
---@param lines number
---@return Skeleton self
function Skeleton:SetLines(lines)
    self.props.lines = lines
    return self
end

--- Set line height
---@param height number
---@return Skeleton self
function Skeleton:SetLineHeight(height)
    self.props.lineHeight = height
    return self
end

--- Set line spacing
---@param spacing number
---@return Skeleton self
function Skeleton:SetLineSpacing(spacing)
    self.props.lineSpacing = spacing
    return self
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Skeleton:IsStateful()
    return self.props.animation ~= "none"
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a text skeleton
---@param lines number Number of lines
---@param options table|nil
---@return Skeleton
function Skeleton.Text(lines, options)
    options = options or {}
    options.variant = "text"
    options.lines = lines or 3
    return Skeleton:new(options)
end

--- Create a circular skeleton (avatar placeholder)
---@param size number|nil Diameter
---@param options table|nil
---@return Skeleton
function Skeleton.Circle(size, options)
    options = options or {}
    options.variant = "circular"
    options.width = size or 40
    options.height = size or 40
    return Skeleton:new(options)
end

--- Create a rectangular skeleton
---@param width number|string
---@param height number
---@param options table|nil
---@return Skeleton
function Skeleton.Rect(width, height, options)
    options = options or {}
    options.variant = "rectangular"
    options.width = width
    options.height = height
    return Skeleton:new(options)
end

--- Create a rounded skeleton
---@param width number|string
---@param height number
---@param options table|nil
---@return Skeleton
function Skeleton.Rounded(width, height, options)
    options = options or {}
    options.variant = "rounded"
    options.width = width
    options.height = height
    return Skeleton:new(options)
end

--- Create a card skeleton
---@param options table|nil { width, imageHeight, lines }
---@return Widget
function Skeleton.Card(options)
    local Panel = require("urhox-libs/UI/Widgets/Panel")

    options = options or {}
    local width = options.width or 300
    local imageHeight = options.imageHeight or 140
    local lines = options.lines or 2

    local card = Panel:new({
        width = width,
        flexDirection = "column",
        backgroundColor = Theme.Color("surface"),
        borderRadius = 8,
        overflow = "hidden",
    })

    -- Image placeholder
    card:AddChild(Skeleton:new({
        variant = "rectangular",
        width = "100%",
        height = imageHeight,
        animation = options.animation or "wave",
    }))

    -- Content area
    local content = Panel:new({
        width = "100%",
        padding = 16,
        flexDirection = "column",
        gap = 12,
    })
    card:AddChild(content)

    -- Title
    content:AddChild(Skeleton:new({
        variant = "text",
        lines = 1,
        lineHeight = 20,
        width = "60%",
        animation = options.animation or "wave",
    }))

    -- Description lines
    content:AddChild(Skeleton:new({
        variant = "text",
        lines = lines,
        lineHeight = 14,
        lineSpacing = 6,
        lastLineWidth = "80%",
        animation = options.animation or "wave",
    }))

    return card
end

--- Create a list item skeleton
---@param options table|nil { hasAvatar, hasSecondary, trailing }
---@return Widget
function Skeleton.ListItem(options)
    local Panel = require("urhox-libs/UI/Widgets/Panel")

    options = options or {}
    local hasAvatar = options.hasAvatar ~= false
    local hasSecondary = options.hasSecondary ~= false
    local hasTrailing = options.trailing == true

    local item = Panel:new({
        width = "100%",
        height = hasSecondary and 72 or 56,
        flexDirection = "row",
        alignItems = "center",
        padding = 16,
        gap = 16,
    })

    -- Avatar
    if hasAvatar then
        item:AddChild(Skeleton.Circle(40, { animation = options.animation }))
    end

    -- Text content
    local textContent = Panel:new({
        flexGrow = 1,
        flexDirection = "column",
        gap = 6,
    })
    item:AddChild(textContent)

    -- Primary text
    textContent:AddChild(Skeleton:new({
        variant = "text",
        lines = 1,
        lineHeight = 16,
        width = "70%",
        animation = options.animation or "wave",
    }))

    -- Secondary text
    if hasSecondary then
        textContent:AddChild(Skeleton:new({
            variant = "text",
            lines = 1,
            lineHeight = 14,
            width = "50%",
            animation = options.animation or "wave",
        }))
    end

    -- Trailing
    if hasTrailing then
        item:AddChild(Skeleton:new({
            variant = "text",
            lines = 1,
            lineHeight = 14,
            width = 40,
            animation = options.animation or "wave",
        }))
    end

    return item
end

--- Create an avatar with text skeleton
---@param options table|nil
---@return Widget
function Skeleton.AvatarWithText(options)
    local Panel = require("urhox-libs/UI/Widgets/Panel")

    options = options or {}

    local container = Panel:new({
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
    })

    -- Avatar
    container:AddChild(Skeleton.Circle(options.avatarSize or 48, { animation = options.animation }))

    -- Text
    local textContainer = Panel:new({
        flexDirection = "column",
        gap = 6,
    })
    container:AddChild(textContainer)

    textContainer:AddChild(Skeleton:new({
        variant = "text",
        lines = 1,
        lineHeight = 16,
        width = options.nameWidth or 120,
        animation = options.animation or "wave",
    }))

    textContainer:AddChild(Skeleton:new({
        variant = "text",
        lines = 1,
        lineHeight = 12,
        width = options.subWidth or 80,
        animation = options.animation or "wave",
    }))

    return container
end

--- Create a paragraph skeleton
---@param lines number
---@param options table|nil
---@return Skeleton
function Skeleton.Paragraph(lines, options)
    options = options or {}
    options.variant = "text"
    options.lines = lines or 4
    options.lineHeight = options.lineHeight or 14
    options.lineSpacing = options.lineSpacing or 8
    options.lastLineWidth = options.lastLineWidth or "60%"
    return Skeleton:new(options)
end

return Skeleton
