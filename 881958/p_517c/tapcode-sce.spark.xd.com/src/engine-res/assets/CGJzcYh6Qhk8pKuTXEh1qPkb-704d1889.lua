-- ============================================================================
-- Carousel Widget
-- Image/content carousel with navigation and auto-play
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class CarouselProps : WidgetProps
---@field items? table[] Carousel slide items array
---@field initialIndex? number Initial slide index (default: 1)
---@field autoPlay? boolean Enable auto-play
---@field autoPlayInterval? number Auto-play interval in seconds (default: 3)
---@field pauseOnHover? boolean Pause auto-play on hover (default: true)
---@field showArrows? boolean Show navigation arrows (default: true)
---@field showIndicators? boolean Show page indicators (default: true)
---@field indicatorPosition? string "bottom" | "top" (default: "bottom")
---@field arrowStyle? string "inside" | "outside" (default: "inside")
---@field transition? string "slide" | "fade" | "none" (default: "slide")
---@field transitionDuration? number Transition duration in seconds (default: 0.3)
---@field loop? boolean Enable infinite loop (default: true)
---@field arrowSize? number Arrow button size (default: 40)
---@field indicatorSize? number Indicator dot size (default: 10)
---@field indicatorGap? number Gap between indicators (default: 8)
---@field indicatorBorderRadius? number Indicator dot corner radius (default: borderRadius or size/2)
---@field dotColor? RGBAColor|string Inactive dot color (default: {255,255,255,100})
---@field activeDotColor? RGBAColor|string Active dot color (default: {255,255,255,255})
---@field dotActiveColor? RGBAColor|string Legacy alias for activeDotColor
---@field arrowBorderColor? RGBAColor|string Arrow button border color (default: Theme.Color("border"))
---@field arrowBorderWidth? number|table Arrow button border width: number (uniform) or {top,right,bottom,left} for depth
---@field arrowPadding? number|table Arrow icon inset; vertical offset lifts the chevron for depth
---@field arrowBorderRadius? number Arrow button border radius (default: size/2 = circle)
---@field arrowBoxShadow? table Arrow button shadow
---@field arrowHoverBoxShadow? table Arrow button hover shadow
---@field arrowIconColor? RGBAColor|string Arrow icon (chevron) color (default: white)
---@field onChange? fun(carousel: Carousel, index: number) Slide change callback
---@field onSlideStart? fun(carousel: Carousel, from: number, to: number) Slide animation start callback
---@field onSlideEnd? fun(carousel: Carousel, from: number, to: number) Slide animation end callback

---@class Carousel : Widget
---@overload fun(props?: CarouselProps): Carousel
---@field props CarouselProps
---@field new fun(self, props?: CarouselProps): Carousel
local Carousel = Widget:Extend("Carousel")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props CarouselProps?
function Carousel:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Carousel")
    Style.ApplyDefaults(props, themeStyle)

    -- Carousel props
    self.items_ = props.items or {}
    self.currentIndex_ = props.initialIndex or 1

    -- Auto-play
    self.autoPlay_ = props.autoPlay or false
    self.autoPlayInterval_ = props.autoPlayInterval or 3  -- seconds
    self.pauseOnHover_ = props.pauseOnHover ~= false  -- default true
    self.autoPlayTimer_ = 0

    -- Navigation
    self.showArrows_ = props.showArrows ~= false  -- default true
    self.showIndicators_ = props.showIndicators ~= false  -- default true
    self.indicatorPosition_ = props.indicatorPosition or "bottom"  -- bottom, top
    self.arrowStyle_ = props.arrowStyle or "inside"  -- inside, outside

    -- Animation
    self.transition_ = props.transition or "slide"  -- slide, fade, none
    self.transitionDuration_ = props.transitionDuration or 0.3
    self.animating_ = false
    self.animationProgress_ = 0
    self.animationFrom_ = 1
    self.animationTo_ = 1

    -- Looping
    self.loop_ = props.loop ~= false  -- default true

    -- State
    self.isHovered_ = false
    self.hoverArrow_ = nil  -- "prev", "next"
    self.hoverIndicator_ = nil

    -- Callbacks
    self.onChange_ = props.onChange
    self.onSlideStart_ = props.onSlideStart
    self.onSlideEnd_ = props.onSlideEnd

    -- Visual
    self.arrowSize_ = props.arrowSize or 40
    self.indicatorSize_ = props.indicatorSize or 10
    self.indicatorGap_ = props.indicatorGap or 8

    Widget.Init(self, props)
end

-- ============================================================================
-- Navigation
-- ============================================================================

function Carousel:GetCurrentIndex()
    return self.currentIndex_
end

function Carousel:GetItemCount()
    return #self.items_
end

function Carousel:GoTo(index, animate)
    local count = #self.items_
    if count == 0 then return end

    -- Handle looping
    if self.loop_ then
        if index < 1 then
            index = count
        elseif index > count then
            index = 1
        end
    else
        index = math.max(1, math.min(index, count))
    end

    if index == self.currentIndex_ and not self.animating_ then
        return
    end

    if animate ~= false and self.transition_ ~= "none" then
        self.animating_ = true
        self.animationProgress_ = 0
        self.animationFrom_ = self.currentIndex_
        self.animationTo_ = index

        if self.onSlideStart_ then
            self.onSlideStart_(self, self.animationFrom_, self.animationTo_)
        end
    else
        self.currentIndex_ = index
        self:DispatchEvent("change", self, index)
        if self.onChange_ then
            self.onChange_(self, index)
        end
    end

    self.currentIndex_ = index
end

function Carousel:Next()
    self:GoTo(self.currentIndex_ + 1)
end

function Carousel:Prev()
    self:GoTo(self.currentIndex_ - 1)
end

function Carousel:First()
    self:GoTo(1)
end

function Carousel:Last()
    self:GoTo(#self.items_)
end

-- ============================================================================
-- Items Management
-- ============================================================================

function Carousel:GetItems()
    return self.items_
end

function Carousel:SetItems(items)
    self.items_ = items or {}
    self.currentIndex_ = 1
end

function Carousel:AddItem(item)
    table.insert(self.items_, item)
end

function Carousel:RemoveItem(index)
    table.remove(self.items_, index)
    if self.currentIndex_ > #self.items_ then
        self.currentIndex_ = math.max(1, #self.items_)
    end
end

-- ============================================================================
-- Auto-play
-- ============================================================================

function Carousel:StartAutoPlay()
    self.autoPlay_ = true
    self.autoPlayTimer_ = 0
end

function Carousel:StopAutoPlay()
    self.autoPlay_ = false
end

function Carousel:ToggleAutoPlay()
    if self.autoPlay_ then
        self:StopAutoPlay()
    else
        self:StartAutoPlay()
    end
end

-- ============================================================================
-- Update
-- ============================================================================

function Carousel:Update(dt)
    -- Handle animation
    if self.animating_ then
        self.animationProgress_ = self.animationProgress_ + dt / self.transitionDuration_

        if self.animationProgress_ >= 1 then
            self.animating_ = false
            self.animationProgress_ = 0

            self:DispatchEvent("change", self, self.currentIndex_)
            if self.onChange_ then
                self.onChange_(self, self.currentIndex_)
            end

            if self.onSlideEnd_ then
                self.onSlideEnd_(self, self.animationFrom_, self.animationTo_)
            end
        end
    end

    -- Handle auto-play
    if self.autoPlay_ and not self.animating_ then
        if not (self.pauseOnHover_ and self.isHovered_) then
            self.autoPlayTimer_ = self.autoPlayTimer_ + dt

            if self.autoPlayTimer_ >= self.autoPlayInterval_ then
                self.autoPlayTimer_ = 0
                self:Next()
            end
        end
    end
end

-- ============================================================================
-- Render
-- ============================================================================

function Carousel:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()
    local props = self.props

    -- Store bounds
    self.bounds_ = { x = x, y = y, w = w, h = h }

    -- Suppress the container border during the base pass: slides fill the rounded
    -- shape and would cover it (and a translucent border would double-composite).
    -- We redraw it once, on top of the slides, below.
    local sBW, sBT, sBR, sBB, sBL = props.borderWidth, props.borderTopWidth,
        props.borderRightWidth, props.borderBottomWidth, props.borderLeftWidth
    props.borderWidth, props.borderTopWidth, props.borderRightWidth,
        props.borderBottomWidth, props.borderLeftWidth = nil, nil, nil, nil, nil

    -- Clip content (bg/gradient/image + slides)
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)
    Widget.Render(self, nvg)
    self:RenderSlides(nvg, x, y, w, h)
    nvgRestore(nvg)

    -- Restore border props and draw the container border ON TOP of slides.
    props.borderWidth, props.borderTopWidth, props.borderRightWidth,
        props.borderBottomWidth, props.borderLeftWidth = sBW, sBT, sBR, sBB, sBL

    local hasPerSide = props.borderTopWidth or props.borderBottomWidth
        or props.borderLeftWidth or props.borderRightWidth
    if hasPerSide then
        local radius = Widget.ResolveCornerRadius(props.borderRadius or 0, props)
        self:RenderPerSideBorders(nvg, { x = x, y = y, w = w, h = h }, radius)
    elseif type(props.borderWidth) == "number" and props.borderWidth > 0 then
        -- Uniform: build the stroke path via GetShapeGeometry so its corner radius is clamped
        -- to min(w,h)/2 exactly like the background — otherwise a huge borderRadius (e.g. 999 for
        -- a pill) leaves the border unclamped and it renders as an ellipse over a rounded-rect bg.
        local cbw = props.borderWidth
        local bc = props.borderColor or Theme.Color("border")
        local inset = cbw / 2
        local geom = self:GetShapeGeometry(
            { x = x + inset, y = y + inset, w = w - cbw, h = h - cbw }, nil, props.borderRadius or 0)
        self:CreateShapePath(nvg, geom)
        nvgStrokeColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], bc[4] or 255))
        nvgStrokeWidth(nvg, cbw)
        nvgStroke(nvg)
    end

    -- Render navigation arrows
    if self.showArrows_ and #self.items_ > 1 then
        self:RenderArrows(nvg, x, y, w, h)
    end

    -- Render indicators
    if self.showIndicators_ and #self.items_ > 1 then
        self:RenderIndicators(nvg, x, y, w, h)
    end
end

function Carousel:RenderSlides(nvg, x, y, w, h)
    local count = #self.items_
    if count == 0 then return end

    local theme = Theme.GetTheme()

    if self.transition_ == "slide" and self.animating_ then
        -- Sliding animation
        local progress = self:EaseOutCubic(self.animationProgress_)
        local direction = self.animationTo_ > self.animationFrom_ and 1 or -1

        -- Handle wrap-around
        if self.loop_ then
            if self.animationFrom_ == count and self.animationTo_ == 1 then
                direction = 1
            elseif self.animationFrom_ == 1 and self.animationTo_ == count then
                direction = -1
            end
        end

        local offset = progress * w * direction

        -- Render from slide
        self:RenderSlide(nvg, x - offset, y, w, h, self.items_[self.animationFrom_], self.animationFrom_)

        -- Render to slide
        self:RenderSlide(nvg, x + w * direction - offset, y, w, h, self.items_[self.animationTo_], self.animationTo_)

    elseif self.transition_ == "fade" and self.animating_ then
        -- Fade animation
        local progress = self:EaseOutCubic(self.animationProgress_)

        -- Render from slide (fading out)
        nvgGlobalAlpha(nvg, 1 - progress)
        self:RenderSlide(nvg, x, y, w, h, self.items_[self.animationFrom_], self.animationFrom_)

        -- Render to slide (fading in)
        nvgGlobalAlpha(nvg, progress)
        self:RenderSlide(nvg, x, y, w, h, self.items_[self.animationTo_], self.animationTo_)

        nvgGlobalAlpha(nvg, 1)
    else
        -- No animation or static
        local item = self.items_[self.currentIndex_]
        if item then
            self:RenderSlide(nvg, x, y, w, h, item, self.currentIndex_)
        end
    end
end

function Carousel:RenderSlide(nvg, x, y, w, h, item, index)
    local theme = Theme.GetTheme()

    if not item then return end

    local slideGeom

    -- Background color
    local bgColor = item.backgroundColor or item.color
    if bgColor then
        slideGeom = slideGeom or self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, self.props.borderRadius or 0)
        self:CreateShapePath(nvg, slideGeom)
        if type(bgColor) == "string" then
            bgColor = Theme.Color(bgColor)
        end
        nvgFillColor(nvg, bgColor)
        nvgFill(nvg)
    end

    -- Image (if provided)
    if item.image then
        -- In a real implementation, this would render an actual image
        -- For now, we draw a placeholder
        slideGeom = slideGeom or self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, self.props.borderRadius or 0)
        self:CreateShapePath(nvg, slideGeom)
        nvgFillColor(nvg, nvgRGBA(200, 200, 200, 255))
        nvgFill(nvg)

        nvgFontSize(nvg, Theme.FontSizeOf("body"))
        nvgFontFace(nvg, Theme.FontFamily())
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
        nvgText(nvg, x + w / 2, y + h / 2, "Image: " .. tostring(item.image))
    end

    -- Title
    if item.title then
        local titleY = y + h * 0.4

        nvgFontSize(nvg, item.titleSize and Theme.FontSize(item.titleSize) or Theme.FontSizeOf("headline"))
        nvgFontFace(nvg, Theme.FontFamily())
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, item.titleColor or nvgRGBA(255, 255, 255, 255))
        nvgText(nvg, x + w / 2, titleY, item.title)
    end

    -- Description
    if item.description then
        local descY = y + h * 0.55

        nvgFontSize(nvg, item.descriptionSize and Theme.FontSize(item.descriptionSize) or Theme.FontSizeOf("body"))
        nvgFontFace(nvg, Theme.FontFamily())
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, item.descriptionColor or nvgRGBA(255, 255, 255, 200))
        nvgText(nvg, x + w / 2, descY, item.description)
    end

    -- Custom render function
    if item.render then
        item.render(nvg, x, y, w, h, item, index)
    end
end

function Carousel:RenderArrows(nvg, x, y, w, h)
    local theme = Theme.GetTheme()
    local btnSize = self.arrowSize_
    -- Distance of the arrow buttons from the left/right edges (inside style) or gap (outside style).
    local padding = self.props.arrowInset or 16

    -- Calculate positions
    local prevX, nextX
    if self.arrowStyle_ == "outside" then
        prevX = x - btnSize - padding
        nextX = x + w + padding
    else
        prevX = x + padding
        nextX = x + w - btnSize - padding
    end

    local btnY = y + (h - btnSize) / 2

    -- Store button bounds
    self.prevBtnBounds_ = { x = prevX, y = btnY, w = btnSize, h = btnSize }
    self.nextBtnBounds_ = { x = nextX, y = btnY, w = btnSize, h = btnSize }

    -- Check if buttons should be enabled
    local canPrev = self.loop_ or self.currentIndex_ > 1
    local canNext = self.loop_ or self.currentIndex_ < #self.items_

    -- Prev button
    if canPrev then
        self:RenderArrowButton(nvg, prevX, btnY, btnSize, "prev", self.hoverArrow_ == "prev")
    end

    -- Next button
    if canNext then
        self:RenderArrowButton(nvg, nextX, btnY, btnSize, "next", self.hoverArrow_ == "next")
    end
end

function Carousel:RenderArrowButton(nvg, x, y, size, direction, isHovered)
    -- Default is a rounded-RECT frame (not a circle): radius defaults to 8.
    -- Independent of the container borderRadius, driven only by arrowBorderRadius.
    local arrowRadius = self.props.arrowBorderRadius or 8

    local arrowShadow = isHovered and (self.props.arrowHoverBoxShadow or self.props.arrowBoxShadow) or self.props.arrowBoxShadow
    if arrowShadow then
        local geom = self:GetShapeGeometry({ x = x, y = y, w = size, h = size }, nil, arrowRadius)
        self:RenderBoxShadows(nvg, geom, arrowShadow)
    end

    -- Optional solid fill: only when an arrow bg color is set. Default = hollow (empty center).
    local fillColor = (isHovered and self.props.arrowHoverBgColor) or self.props.arrowBgColor
    if fillColor then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, size, size, arrowRadius)
        nvgFillColor(nvg, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 255))
        nvgFill(nvg)
    end

    -- Rounded-rect border (the frame). Hollow → default 2 so the empty-center frame is visible;
    -- with a fill set (themed solid arrows) → default 0 to keep the themed look. number = uniform;
    -- {top,right,bottom,left} = per-side depth.
    local bw = self.props.arrowBorderWidth or (fillColor and 0 or 2)
    if bw then
        local bc = self.props.arrowBorderColor or { 255, 255, 255, 255 }
        local col = nvgRGBA(bc[1], bc[2], bc[3], bc[4] or 255)
        if type(bw) == "table" then
            local tw = bw[1] or 0
            local rw = bw[2] or 0
            local bbw = bw[3] or 0
            local lw = bw[4] or 0
            if (tw > 0 or rw > 0 or bbw > 0 or lw > 0) and size - lw - rw > 0 and size - tw - bbw > 0 then
                -- Per-side donut over bg (outer shape minus inset hole)
                local rTL = math.max(0, arrowRadius - math.max(tw, lw))
                local rTR = math.max(0, arrowRadius - math.max(tw, rw))
                local rBR = math.max(0, arrowRadius - math.max(bbw, rw))
                local rBL = math.max(0, arrowRadius - math.max(bbw, lw))
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x, y, size, size, arrowRadius)
                nvgRoundedRectVarying(nvg, x + lw, y + tw, size - lw - rw, size - tw - bbw, rTL, rTR, rBR, rBL)
                nvgPathWinding(nvg, NVG_HOLE)
                nvgFillColor(nvg, col)
                nvgFill(nvg)
            end
        elseif bw > 0 then
            -- Uniform: inset stroke so it stays inside button bounds
            local inset = bw / 2
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x + inset, y + inset, size - bw, size - bw, math.max(0, arrowRadius - inset))
            nvgStrokeColor(nvg, col)
            nvgStrokeWidth(nvg, bw)
            nvgStroke(nvg)
        end
    end

    -- Arrow chevron (arrowPadding vertical offset lifts the icon for depth)
    local centerX = x + size / 2
    local centerY = y + size / 2
    local ap = self.props.arrowPadding
    if ap then
        local pt, pb
        if type(ap) == "table" then
            pt, pb = ap[1] or 0, ap[3] or 0
        else
            pt, pb = ap, ap
        end
        centerY = centerY + (pt - pb) / 2
    end
    local arrowSize = size * 0.3

    nvgBeginPath(nvg)
    if direction == "prev" then
        nvgMoveTo(nvg, centerX + arrowSize * 0.3, centerY - arrowSize)
        nvgLineTo(nvg, centerX - arrowSize * 0.5, centerY)
        nvgLineTo(nvg, centerX + arrowSize * 0.3, centerY + arrowSize)
    else
        nvgMoveTo(nvg, centerX - arrowSize * 0.3, centerY - arrowSize)
        nvgLineTo(nvg, centerX + arrowSize * 0.5, centerY)
        nvgLineTo(nvg, centerX - arrowSize * 0.3, centerY + arrowSize)
    end

    local iconColor = self.props.arrowIconColor
    if iconColor then
        nvgStrokeColor(nvg, nvgRGBA(iconColor[1], iconColor[2], iconColor[3], iconColor[4] or 255))
    else
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 255))
    end
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
end

function Carousel:RenderIndicators(nvg, x, y, w, h)
    local count = #self.items_
    local indicatorSize = self.indicatorSize_
    local indicatorGap = self.indicatorGap_
    local totalWidth = count * indicatorSize + (count - 1) * indicatorGap
    local startX = x + (w - totalWidth) / 2

    local indicatorY
    if self.indicatorPosition_ == "top" then
        indicatorY = y + 20
    else
        indicatorY = y + h - 20 - indicatorSize
    end

    self.indicatorBounds_ = {}

    for i = 1, count do
        local dotX = startX + (i - 1) * (indicatorSize + indicatorGap)
        local isActive = i == self.currentIndex_
        local isHovered = self.hoverIndicator_ == i

        self.indicatorBounds_[i] = { x = dotX, y = indicatorY, w = indicatorSize, h = indicatorSize }

        -- Independent of the container borderRadius, driven only by indicatorBorderRadius
        -- (default = half the dot size = full circle).
        local dotRadius = self.props.indicatorBorderRadius or (indicatorSize / 2)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, dotX, indicatorY, indicatorSize, indicatorSize, dotRadius)

        local dotActive = self.props.activeDotColor or self.props.dotActiveColor or {255, 255, 255, 255}
        local dotInactive = self.props.dotColor or {255, 255, 255, 100}
        if isActive then
            nvgFillColor(nvg, nvgRGBA(dotActive[1], dotActive[2], dotActive[3], dotActive[4] or 255))
        elseif isHovered then
            -- Blend between inactive and active for hover
            local ha = math.floor((dotInactive[4] or 100) * 0.5 + (dotActive[4] or 255) * 0.5)
            nvgFillColor(nvg, nvgRGBA(dotInactive[1], dotInactive[2], dotInactive[3], ha))
        else
            nvgFillColor(nvg, nvgRGBA(dotInactive[1], dotInactive[2], dotInactive[3], dotInactive[4] or 100))
        end
        nvgFill(nvg)
    end
end

-- ============================================================================
-- Easing
-- ============================================================================

function Carousel:EaseOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Carousel:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function Carousel:OnPointerMove(event)
    if not event then return end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    -- Check if hovering carousel
    self.isHovered_ = self:PointInBounds(px, py, self.bounds_)

    -- Check arrow hover
    self.hoverArrow_ = nil
    if self:PointInBounds(px, py, self.prevBtnBounds_) then
        self.hoverArrow_ = "prev"
    elseif self:PointInBounds(px, py, self.nextBtnBounds_) then
        self.hoverArrow_ = "next"
    end

    -- Check indicator hover
    self.hoverIndicator_ = nil
    if self.indicatorBounds_ then
        for i, bounds in ipairs(self.indicatorBounds_) do
            if self:PointInBounds(px, py, bounds) then
                self.hoverIndicator_ = i
                break
            end
        end
    end
end

function Carousel:OnMouseLeave()
    self.isHovered_ = false
    self.hoverArrow_ = nil
    self.hoverIndicator_ = nil
end

function Carousel:OnClick(event)
    if not event then return end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    -- Check arrow clicks
    if self:PointInBounds(px, py, self.prevBtnBounds_) then
        self:Prev()
        return true
    elseif self:PointInBounds(px, py, self.nextBtnBounds_) then
        self:Next()
        return true
    end

    -- Check indicator clicks
    if self.indicatorBounds_ then
        for i, bounds in ipairs(self.indicatorBounds_) do
            if self:PointInBounds(px, py, bounds) then
                self:GoTo(i)
                return true
            end
        end
    end

    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a basic carousel
---@param items table[] Array of slide items
---@param props table|nil Additional props
---@return Carousel
function Carousel.FromItems(items, props)
    props = props or {}
    props.items = items
    return Carousel(props)
end

--- Create an auto-playing carousel
---@param items table[]
---@param interval number Auto-play interval in seconds
---@param props table|nil
---@return Carousel
function Carousel.AutoPlay(items, interval, props)
    props = props or {}
    props.items = items
    props.autoPlay = true
    props.autoPlayInterval = interval or 3
    return Carousel(props)
end

--- Create a carousel with fade transition
---@param items table[]
---@param props table|nil
---@return Carousel
function Carousel.Fade(items, props)
    props = props or {}
    props.items = items
    props.transition = "fade"
    return Carousel(props)
end

--- Create a simple image carousel (placeholder)
---@param images string[] Array of image paths
---@param props table|nil
---@return Carousel
function Carousel.Images(images, props)
    props = props or {}
    local items = {}
    for i, img in ipairs(images) do
        table.insert(items, { image = img })
    end
    props.items = items
    return Carousel(props)
end

--- Create a banner carousel with title/description
---@param banners table[] Array of banner data
---@param props table|nil
---@return Carousel
function Carousel.Banners(banners, props)
    props = props or {}
    props.items = banners
    props.autoPlay = true
    return Carousel(props)
end

return Carousel
