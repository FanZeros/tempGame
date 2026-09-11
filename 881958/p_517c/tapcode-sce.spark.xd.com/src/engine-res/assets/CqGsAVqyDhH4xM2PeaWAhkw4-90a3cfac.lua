-- ============================================================================
-- Popover Widget
-- Floating content panel anchored to an element
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class PopoverProps : WidgetProps
---@field placement? string "top" | "bottom" | "left" | "right" | "top-start" | "top-end" | "bottom-start" | "bottom-end" (default: "bottom")
---@field trigger? string "click" | "hover" | "focus" | "manual" (default: "click")
---@field offset? number Distance from anchor element (default: 8)
---@field content? string|fun(nvg: any, x: number, y: number, w: number, h: number) Popover content
---@field title? string Popover title
---@field backgroundColor? RGBAColor|string Popover background color
---@field backgroundImage? string Popover background image
---@field backgroundImageOpacity? number Popover background image opacity, 0-1
---@field titleTextColor? RGBAColor|string Title text color
---@field contentTextColor? RGBAColor|string Content text color
---@field arrowColor? RGBAColor|string Arrow color (defaults to backgroundColor)
---@field showArrow? boolean Show arrow pointing to anchor (default: true)
---@field arrowSize? number Arrow size in pixels (default: 8)
---@field maxWidth? number Maximum popover width (default: 300)
---@field elevation? number Shadow elevation (default: 8)
---@field animationDuration? number Open/close animation duration (default: 0.15)
---@field closeOnClickOutside? boolean Close when clicking outside (default: true)
---@field closeOnEsc? boolean Close on Escape key (default: true)
---@field onOpen? fun(popover: Popover) Called when popover opens
---@field onClose? fun(popover: Popover) Called when popover closes

---@class Popover : Widget
---@overload fun(props?: PopoverProps): Popover
---@field props PopoverProps
---@field new fun(self, props?: PopoverProps): Popover
local Popover = Widget:Extend("Popover")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props PopoverProps?
function Popover:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Popover")
    Style.ApplyDefaults(props, themeStyle)
    props.borderRadius = props.borderRadius or 8

    -- Popover props
    self.placement_ = props.placement or "bottom"  -- top, bottom, left, right, top-start, top-end, etc.
    self.trigger_ = props.trigger or "click"  -- click, hover, focus, manual
    self.offset_ = props.offset or 8

    -- Content
    self.content_ = props.content
    self.title_ = props.title

    -- Visual
    self.showArrow_ = props.showArrow ~= false  -- default true
    self.arrowSize_ = props.arrowSize or 8
    self.maxWidth_ = props.maxWidth or 300
    self.elevation_ = props.elevation or 8

    -- State
    self.isOpen_ = false
    self.anchorBounds_ = nil  -- { x, y, w, h }

    -- Animation
    self.animationDuration_ = props.animationDuration or 0.15
    self.animating_ = false
    self.animationProgress_ = 0

    -- Behavior
    self.closeOnClickOutside_ = props.closeOnClickOutside ~= false
    self.closeOnEsc_ = props.closeOnEsc ~= false

    -- Callbacks
    self.onOpen_ = props.onOpen
    self.onClose_ = props.onClose

    -- Trigger child widget
    self.triggerChild_ = nil

    Widget.Init(self, props)

    -- Handle children prop (trigger element) - add as real child for layout
    if props.children and #props.children > 0 then
        self.triggerChild_ = props.children[1]
        self:AddChild(self.triggerChild_)

        -- Wrap trigger's onClick to toggle popover
        if self.trigger_ == "click" and self.triggerChild_.props then
            local originalOnClick = self.triggerChild_.props.onClick
            self.triggerChild_.props.onClick = function(widget, event)
                -- Get trigger bounds for positioning
                local l = self.triggerChild_:GetAbsoluteLayoutForHitTest()
                if l and l.w > 0 then
                    self.triggerBounds_ = { x = l.x, y = l.y, w = l.w, h = l.h }
                    self:Toggle(self.triggerBounds_)
                end
                -- Call original onClick if exists
                if originalOnClick then
                    originalOnClick(widget, event)
                end
            end
        end
    end
end

-- ============================================================================
-- Open/Close
-- ============================================================================

function Popover:Open(anchorBounds)
    if self.isOpen_ then return end

    self.anchorBounds_ = anchorBounds
    self.isOpen_ = true
    self.animating_ = true
    self.animationProgress_ = 0

    UI.PushOverlay(self)

    if self.onOpen_ then
        self.onOpen_(self)
    end
end

function Popover:Close()
    if not self.isOpen_ then return end

    self.isOpen_ = false
    self.animating_ = false
    self.animationProgress_ = 0

    UI.PopOverlay(self)

    if self.onClose_ then
        self.onClose_(self)
    end
end

function Popover:Toggle(anchorBounds)
    if self.isOpen_ then
        self:Close()
    else
        self:Open(anchorBounds)
    end
end

function Popover:IsOpen()
    return self.isOpen_
end

function Popover:SetAnchor(bounds)
    self.anchorBounds_ = bounds
end

-- ============================================================================
-- Content
-- ============================================================================

function Popover:SetContent(content)
    self.content_ = content
end

function Popover:SetTitle(title)
    self.title_ = title
end

-- ============================================================================
-- Update
-- ============================================================================

function Popover:Update(dt)
    if self.animating_ then
        self.animationProgress_ = self.animationProgress_ + dt / self.animationDuration_
        if self.animationProgress_ >= 1 then
            self.animationProgress_ = 1
            self.animating_ = false
        end
    end
end

-- ============================================================================
-- Position Calculation
-- ============================================================================

function Popover:CalculatePosition(contentWidth, contentHeight)
    if not self.anchorBounds_ then
        return 0, 0
    end

    local anchor = self.anchorBounds_
    local x, y = 0, 0
    local placement = self.placement_
    local offset = self.offset_
    local arrowSize = self.arrowSize_

    -- Parse placement
    local mainPos, align = placement:match("^(%w+)-?(%w*)$")
    align = align ~= "" and align or "center"

    -- Calculate main position
    if mainPos == "top" then
        x = anchor.x + anchor.w / 2 - contentWidth / 2
        y = anchor.y - contentHeight - offset - (self.showArrow_ and arrowSize or 0)
    elseif mainPos == "bottom" then
        x = anchor.x + anchor.w / 2 - contentWidth / 2
        y = anchor.y + anchor.h + offset + (self.showArrow_ and arrowSize or 0)
    elseif mainPos == "left" then
        x = anchor.x - contentWidth - offset - (self.showArrow_ and arrowSize or 0)
        y = anchor.y + anchor.h / 2 - contentHeight / 2
    elseif mainPos == "right" then
        x = anchor.x + anchor.w + offset + (self.showArrow_ and arrowSize or 0)
        y = anchor.y + anchor.h / 2 - contentHeight / 2
    end

    -- Apply alignment
    if mainPos == "top" or mainPos == "bottom" then
        if align == "start" then
            x = anchor.x
        elseif align == "end" then
            x = anchor.x + anchor.w - contentWidth
        end
    elseif mainPos == "left" or mainPos == "right" then
        if align == "start" then
            y = anchor.y
        elseif align == "end" then
            y = anchor.y + anchor.h - contentHeight
        end
    end

    -- Clamp to viewport bounds (with padding)
    local viewportPadding = 8
    local viewportWidth, viewportHeight = UI.GetViewportSize()

    -- Clamp X to prevent left/right overflow
    if x < viewportPadding then
        x = viewportPadding
    elseif x + contentWidth > viewportWidth - viewportPadding then
        x = viewportWidth - viewportPadding - contentWidth
    end

    -- Clamp Y to prevent top/bottom overflow
    if y < viewportPadding then
        y = viewportPadding
    elseif y + contentHeight > viewportHeight - viewportPadding then
        y = viewportHeight - viewportPadding - contentHeight
    end

    return x, y
end

-- ============================================================================
-- Render
-- ============================================================================

function Popover:Render(nvg)
    -- Update trigger bounds from trigger child (use HitTest coords)
    if self.triggerChild_ then
        local l = self.triggerChild_:GetAbsoluteLayoutForHitTest()
        if l and l.w > 0 then
            self.triggerBounds_ = { x = l.x, y = l.y, w = l.w, h = l.h }
            -- Also update anchor bounds if open (for scroll tracking)
            if self.isOpen_ then
                self.anchorBounds_ = self.triggerBounds_
            end
        end
    end

    -- Queue popover content as overlay
    if self.isOpen_ and self.anchorBounds_ then
        UI.QueueOverlay(function(overlayNvg)
            self:RenderPopoverContent(overlayNvg)
        end)
    end
end

function Popover:RenderPopoverContent(nvg)
    local alpha = self.animating_ and self.animationProgress_ or 1

    -- Calculate content size (no scale needed - nvgScale handles it)
    local contentWidth = self.maxWidth_
    local paddingLeft = self.props.paddingLeft or 16
    local paddingRight = self.props.paddingRight or 16
    local paddingTop = self.props.paddingTop or 12
    local paddingBottom = self.props.paddingBottom or 12
    local titleGap = self.props.titleGap or 8
    local contentMaxWidth = math.max(1, contentWidth - paddingLeft - paddingRight)

    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    local titleFontFamily = Theme.FontFace(self.props.fontFamily, self.props.titleFontWeight or self.props.fontWeight)
    local titleFontSize = self.props.titleFontSize and Theme.FontSize(self.props.titleFontSize) or Theme.FontSizeOf("body")
    local contentFontSize = self.props.fontSize and Theme.FontSize(self.props.fontSize) or Theme.FontSizeOf("body")

    local contentHeight = paddingTop + paddingBottom

    if self.title_ then
        nvgFontFace(nvg, titleFontFamily)
        nvgFontSize(nvg, titleFontSize)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local _, _, titleLineHeight = nvgTextMetrics(nvg)
        contentHeight = contentHeight + (titleLineHeight or titleFontSize) + titleGap
    end

    if type(self.content_) == "string" then
        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, contentFontSize)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local bounds = nvgTextBoxBounds(nvg, 0, 0, contentMaxWidth, self.content_)
        if bounds and bounds[2] and bounds[4] then
            contentHeight = contentHeight + math.max(contentFontSize, bounds[4] - bounds[2])
        else
            contentHeight = contentHeight + contentFontSize
        end
    elseif type(self.content_) == "function" then
        contentHeight = contentHeight + (self.props.contentHeight or 36)
    end

    local minHeight = self.props.minHeight or (self.title_ and 88 or 60)
    contentHeight = math.max(contentHeight, minHeight)

    -- Calculate position
    local x, y = self:CalculatePosition(contentWidth, contentHeight)

    -- Store bounds for hit testing
    self.popoverBounds_ = { x = x, y = y, w = contentWidth, h = contentHeight }

    local borderRadius = self.props.borderRadius
    nvgSave(nvg)
    nvgGlobalAlpha(nvg, alpha)

    -- Shadow
    local boxShadow = self.props.boxShadow
    if boxShadow == false then
        -- Explicitly disabled.
    elseif boxShadow then
        local geom = self:GetShapeGeometry({ x = x, y = y, w = contentWidth, h = contentHeight }, nil, borderRadius)
        self:RenderBoxShadows(nvg, geom, boxShadow)
    else
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x + 2, y = y + 2, w = contentWidth, h = contentHeight }, nil, borderRadius))
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 30))
        nvgFill(nvg)
    end

    -- Background
    local borderColor = self.props.borderColor or Theme.Color("border")
    local backgroundColor = self.props.backgroundColor or Theme.Color("surface")
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = contentWidth, h = contentHeight }, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4] or 255))
    nvgFill(nvg)
    if self.props.backgroundImage then
        self:RenderBackgroundImage(
            nvg,
            self.props.backgroundImage,
            { x = x, y = y, w = contentWidth, h = contentHeight },
            self.props.backgroundFit or "fill",
            self.props.backgroundSlice,
            borderRadius,
            self.props.imageTint,
            self.props.backgroundImageOpacity
        )
    end
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = contentWidth, h = contentHeight }, nil, borderRadius))
    nvgStrokeColor(nvg, Theme.ToNvgColor(borderColor))
    nvgStrokeWidth(nvg, self.props.borderWidth or 1)
    nvgStroke(nvg)

    -- Arrow
    if self.showArrow_ then
        self:RenderArrow(nvg, x, y, contentWidth, contentHeight)
    end

    -- Title
    local contentY = y + paddingTop
    if self.title_ then
        nvgFontSize(nvg, titleFontSize)
        nvgFontFace(nvg, titleFontFamily)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local titleTextColor = self.props.titleTextColor or Theme.Color("text")
        nvgFillColor(nvg, nvgRGBA(titleTextColor[1], titleTextColor[2], titleTextColor[3], titleTextColor[4] or 255))
        nvgText(nvg, x + paddingLeft, contentY, self.title_)
        local _, _, titleLineHeight = nvgTextMetrics(nvg)
        contentY = contentY + (titleLineHeight or titleFontSize) + titleGap
    end

    -- Content
    if self.content_ then
        if type(self.content_) == "string" then
            nvgFontSize(nvg, contentFontSize)
            nvgFontFace(nvg, fontFamily)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local contentTextColor = self.props.contentTextColor or Theme.Color("textSecondary")
            nvgFillColor(nvg, nvgRGBA(contentTextColor[1], contentTextColor[2], contentTextColor[3], contentTextColor[4] or 255))

            -- Simple text wrapping
            nvgTextBox(nvg, x + paddingLeft, contentY, contentMaxWidth, self.content_)
        elseif type(self.content_) == "function" then
            self.content_(nvg, x + paddingLeft, contentY,
                contentWidth - paddingLeft - paddingRight,
                contentHeight - (contentY - y) - paddingBottom)
        end
    end

    nvgRestore(nvg)
end

function Popover:RenderArrow(nvg, x, y, w, h)
    local anchor = self.anchorBounds_
    local size = self.arrowSize_
    local mainPos = self.placement_:match("^(%w+)")

    nvgBeginPath(nvg)

    if mainPos == "top" then
        local arrowX = anchor.x + anchor.w / 2
        nvgMoveTo(nvg, arrowX - size, y + h)
        nvgLineTo(nvg, arrowX, y + h + size)
        nvgLineTo(nvg, arrowX + size, y + h)
    elseif mainPos == "bottom" then
        local arrowX = anchor.x + anchor.w / 2
        nvgMoveTo(nvg, arrowX - size, y)
        nvgLineTo(nvg, arrowX, y - size)
        nvgLineTo(nvg, arrowX + size, y)
    elseif mainPos == "left" then
        local arrowY = anchor.y + anchor.h / 2
        nvgMoveTo(nvg, x + w, arrowY - size)
        nvgLineTo(nvg, x + w + size, arrowY)
        nvgLineTo(nvg, x + w, arrowY + size)
    elseif mainPos == "right" then
        local arrowY = anchor.y + anchor.h / 2
        nvgMoveTo(nvg, x, arrowY - size)
        nvgLineTo(nvg, x - size, arrowY)
        nvgLineTo(nvg, x, arrowY + size)
    end

    nvgClosePath(nvg)
    local arrowColor = self.props.arrowColor or self.props.backgroundColor or Theme.Color("surface")
    nvgFillColor(nvg, nvgRGBA(arrowColor[1], arrowColor[2], arrowColor[3], arrowColor[4] or 255))
    nvgFill(nvg)
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Popover:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function Popover:HitTest(x, y)
    -- Check trigger bounds
    if self.triggerBounds_ and self:PointInBounds(x, y, self.triggerBounds_) then
        return true
    end

    -- When open, also capture clicks on popover or outside (for closing)
    if self.isOpen_ then
        return true
    end

    return false
end

function Popover:OnClick(event)
    local px, py = event.x, event.y

    -- Check if clicking on trigger
    if self.trigger_ == "click" and self.triggerBounds_ then
        if self:PointInBounds(px, py, self.triggerBounds_) then
            if self.isOpen_ then
                self:Close()
            else
                self:Open(self.triggerBounds_)
            end
            return true
        end
    end

    -- Check if clicking outside popover (close it)
    if self.closeOnClickOutside_ and self.isOpen_ then
        if not self:PointInBounds(px, py, self.popoverBounds_) and
           not self:PointInBounds(px, py, self.triggerBounds_) then
            self:Close()
            return true
        end
    end

    return false
end

function Popover:OnPointerEnter(event)
    if self.trigger_ == "hover" and self.triggerBounds_ then
        local px, py = event.x, event.y
        if self:PointInBounds(px, py, self.triggerBounds_) then
            self:Open(self.triggerBounds_)
        end
    end
end

function Popover:OnPointerLeave(event)
    if self.trigger_ == "hover" and self.isOpen_ then
        self:Close()
    end
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a simple popover with text
---@param content string
---@param props table|nil
---@return Popover
function Popover.Text(content, props)
    props = props or {}
    props.content = content
    return Popover(props)
end

--- Create a popover with title and content
---@param title string
---@param content string
---@param props table|nil
---@return Popover
function Popover.WithTitle(title, content, props)
    props = props or {}
    props.title = title
    props.content = content
    return Popover(props)
end

--- Create a confirmation popover
---@param message string
---@param onConfirm function
---@param props table|nil
---@return Popover
function Popover.Confirm(message, onConfirm, props)
    props = props or {}
    props.content = message
    props.title = props.title or "Confirm"
    -- Note: In a real implementation, this would include confirm/cancel buttons
    return Popover(props)
end

--- Create a menu popover
---@param items table[] Menu items
---@param props table|nil
---@return Popover
function Popover.Menu(items, props)
    props = props or {}
    props.showArrow = false
    props.content = function(nvg, x, y, w, h)
        local theme = Theme.GetTheme()
        local itemHeight = 36

        for i, item in ipairs(items) do
            local itemY = y + (i - 1) * itemHeight

            nvgFontSize(nvg, Theme.FontSizeOf("body"))
            nvgFontFace(nvg, Theme.FontFamily())
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local menuTextColor = props.contentTextColor
            if menuTextColor then
                nvgFillColor(nvg, nvgRGBA(menuTextColor[1], menuTextColor[2], menuTextColor[3], menuTextColor[4] or 255))
            else
                nvgFillColor(nvg, Theme.NvgColor("text"))
            end
            nvgText(nvg, x, itemY + itemHeight / 2, item.label or item.text or "")
        end
    end
    return Popover(props)
end

return Popover
