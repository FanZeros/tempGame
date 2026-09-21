-- ============================================================================
-- Drawer Widget
-- Sliding panel from screen edge
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class DrawerProps : WidgetProps
---@field position? string "left" | "right" | "top" | "bottom" (default: "left")
---@field size? number Width for left/right, height for top/bottom (default: 300)
---@field variant? string "temporary" | "permanent" | "persistent" (default: "temporary")
---@field showOverlay? boolean Show overlay background for temporary variant (default: true)
---@field overlayOpacity? number Overlay opacity 0-1 (default: 0.5)
---@field elevation? number Shadow elevation (default: 16)
---@field animationDuration? number Open/close animation duration in seconds (default: 0.25)
---@field isOpen? boolean Initial open state
---@field onOpen? fun(drawer: Drawer) Called when drawer opens
---@field onClose? fun(drawer: Drawer) Called when drawer closes
---@field onChange? fun(drawer: Drawer, isOpen: boolean) Called when open state changes
---@field content? Widget|fun(nvg: any, x: number, y: number, w: number, h: number) Drawer content
---@field header? string|Widget|fun(nvg: any, x: number, y: number, w: number, h: number) Header content
---@field footer? string|Widget|fun(nvg: any, x: number, y: number, w: number, h: number) Footer content
---@field backgroundColor? RGBAColor|string Background color (default: surface)
---@field headerBgColor? RGBAColor|string Header background color
---@field headerBackgroundImage? string Header background image
---@field headerBackgroundImageOpacity? number Header background image opacity, 0-1
---@field titleTextColor? RGBAColor|string String header title text color
---@field contentTextColor? RGBAColor|string Built-in navigation item text color
---@field footerTextColor? RGBAColor|string String footer text color
---@field closeIconColor? RGBAColor|string Close icon color
---@field closeButtonBgColor? RGBAColor|string Close button background color
---@field closeButtonHoverBgColor? RGBAColor|string Close button hover background color
---@field itemBgColor? RGBAColor|string Built-in navigation item background color
---@field itemHoverBgColor? RGBAColor|string Built-in navigation item hover background color
---@field itemSelectedBgColor? RGBAColor|string Built-in navigation item selected background color
---@field headerHeight? number Header height (default: 56)
---@field contentPadding? number|table Content area padding: number or {vertical, horizontal} (default: 0)
---@field headerPadding? number|table Header padding: number or {vertical, horizontal} (default: {14, 16})
---@field showCloseButton? boolean Show close button (default: false)
---@field screenWidth? number Screen width for positioning
---@field screenHeight? number Screen height for positioning

---@class Drawer : Widget
---@overload fun(props?: DrawerProps): Drawer
---@field props DrawerProps
---@field new fun(self, props?: DrawerProps): Drawer
local Drawer = Widget:Extend("Drawer")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props DrawerProps?
function Drawer:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Drawer")
    Style.ApplyDefaults(props, themeStyle)

    -- Drawer props
    self.position_ = props.position or "left"  -- left, right, top, bottom
    self.size_ = props.size or 300  -- Width for left/right, height for top/bottom
    self.variant_ = props.variant or "temporary"  -- temporary, permanent, persistent

    -- Visual
    self.showOverlay_ = props.showOverlay ~= false  -- default true (for temporary)
    self.overlayOpacity_ = props.overlayOpacity or 0.5
    self.elevation_ = props.elevation or 16

    -- Animation
    self.animationDuration_ = props.animationDuration or 0.25

    -- State
    self.isOpen_ = props.isOpen or (self.variant_ == "permanent")
    self.animating_ = false
    self.animationProgress_ = self.isOpen_ and 1 or 0
    self.animationTarget_ = self.animationProgress_

    -- Callbacks
    self.onOpen_ = props.onOpen
    self.onClose_ = props.onClose
    self.onChange_ = props.onChange

    -- Content
    self.content_ = props.content  -- Child widget or render function
    if self.content_ and type(self.content_) ~= "function" then
        self.content_.parent = self
    end
    self.header_ = props.header
    self.footer_ = props.footer

    -- Styling
    self.backgroundColor_ = props.backgroundColor or Theme.Color("surface")
    self.headerHeight_ = props.headerHeight or 56
    self.showCloseButton_ = props.showCloseButton or false

    -- Screen size (will be set during render)
    self.screenWidth_ = props.screenWidth or 800
    self.screenHeight_ = props.screenHeight or 600

    -- Drawer needs absolute positioning to overlay content
    -- HitTest is overridden to only intercept events when open
    props.position = "absolute"
    props.left = 0
    props.top = 0
    props.width = "100%"
    props.height = "100%"

    Widget.Init(self, props)
end

-- ============================================================================
-- Open/Close
-- ============================================================================

function Drawer:Open()
    if self.isOpen_ then return end

    self.isOpen_ = true
    self.animating_ = true
    self.animationTarget_ = 1

    -- Register as active overlay to receive events
    UI.PushOverlay(self)

    self:DispatchEvent("open", self)
    if self.onOpen_ then
        self.onOpen_(self)
    end

    self:DispatchEvent("change", self, true)
    if self.onChange_ then
        self.onChange_(self, true)
    end
end

function Drawer:Close()
    if not self.isOpen_ then return end
    if self.variant_ == "permanent" then return end

    self.isOpen_ = false
    self.animating_ = true
    self.animationTarget_ = 0

    -- Clear active overlay
    UI.PopOverlay(self)

    self:DispatchEvent("close", self)
    if self.onClose_ then
        self.onClose_(self)
    end

    self:DispatchEvent("change", self, false)
    if self.onChange_ then
        self.onChange_(self, false)
    end
end

function Drawer:Toggle()
    if self.isOpen_ then
        self:Close()
    else
        self:Open()
    end
end

function Drawer:IsOpen()
    return self.isOpen_
end

-- ============================================================================
-- Content
-- ============================================================================

function Drawer:SetContent(content)
    self.content_ = content
    if content and type(content) ~= "function" then
        content.parent = self
    end
end

function Drawer:SetHeader(header)
    self.header_ = header
end

function Drawer:SetFooter(footer)
    self.footer_ = footer
end

-- ============================================================================
-- Update
-- ============================================================================

function Drawer:Update(dt)
    if self.animating_ then
        local speed = 1 / self.animationDuration_
        local diff = self.animationTarget_ - self.animationProgress_

        if math.abs(diff) < 0.01 then
            self.animationProgress_ = self.animationTarget_
            self.animating_ = false
        else
            self.animationProgress_ = self.animationProgress_ + diff * speed * dt * 4
        end
    end
end

-- ============================================================================
-- Render
-- ============================================================================

function Drawer:Render(nvg)
    -- Don't render if completely closed and not animating
    if self.animationProgress_ <= 0 and not self.animating_ then
        return
    end

    -- Queue drawer rendering as overlay to avoid parent transform issues
    UI.QueueOverlay(function(overlayNvg)
        self:RenderDrawerContent(overlayNvg)
    end)
end

function Drawer:RenderDrawerContent(nvg)
    -- Get screen size from UI
    local screenWidth = UI.GetWidth() or 800
    local screenHeight = UI.GetHeight() or 600
    self.screenWidth_ = screenWidth
    self.screenHeight_ = screenHeight

    local progress = self:EaseOutCubic(self.animationProgress_)

    -- Render overlay (for temporary variant)
    if self.showOverlay_ and self.variant_ == "temporary" then
        self:RenderOverlay(nvg, progress)
    end

    -- Calculate drawer position
    local x, y, w, h = self:CalculateDrawerBounds(progress)

    -- Store bounds for hit testing (now in screen coordinates)
    self.drawerBounds_ = { x = x, y = y, w = w, h = h }

    local borderRadius = self.props.borderRadius or 0

    -- Shadow
    local boxShadow = self.props.boxShadow
    if boxShadow == false then
        -- Explicitly disabled.
    elseif boxShadow then
        local geom = self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, borderRadius)
        self:RenderBoxShadows(nvg, geom, boxShadow)
    elseif self.elevation_ > 0 then
        local shadowBlur = self.elevation_

        if self.position_ == "left" then
            nvgBeginPath(nvg)
            nvgRect(nvg, x + w, y, shadowBlur, h)
            local grad = nvgLinearGradient(nvg, x + w, y, x + w + shadowBlur, y,
                nvgRGBA(0, 0, 0, 40), nvgRGBA(0, 0, 0, 0))
            nvgFillPaint(nvg, grad)
            nvgFill(nvg)
        elseif self.position_ == "right" then
            nvgBeginPath(nvg)
            nvgRect(nvg, x - shadowBlur, y, shadowBlur, h)
            local grad = nvgLinearGradient(nvg, x - shadowBlur, y, x, y,
                nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 40))
            nvgFillPaint(nvg, grad)
            nvgFill(nvg)
        elseif self.position_ == "top" then
            nvgBeginPath(nvg)
            nvgRect(nvg, x, y + h, w, shadowBlur)
            local grad = nvgLinearGradient(nvg, x, y + h, x, y + h + shadowBlur,
                nvgRGBA(0, 0, 0, 40), nvgRGBA(0, 0, 0, 0))
            nvgFillPaint(nvg, grad)
            nvgFill(nvg)
        elseif self.position_ == "bottom" then
            nvgBeginPath(nvg)
            nvgRect(nvg, x, y - shadowBlur, w, shadowBlur)
            local grad = nvgLinearGradient(nvg, x, y - shadowBlur, x, y,
                nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 40))
            nvgFillPaint(nvg, grad)
            nvgFill(nvg)
        end
    end

    -- Set render offset for hit testing (Drawer renders as overlay, not in Yoga tree position)
    self.renderOffsetX_ = x
    self.renderOffsetY_ = y

    -- Background
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, borderRadius))
    nvgFillColor(nvg, Theme.ToNvgColor(self.backgroundColor_))
    nvgFill(nvg)

    if self.props.backgroundImage then
        self:RenderBackgroundImage(
            nvg,
            self.props.backgroundImage,
            { x = x, y = y, w = w, h = h },
            self.props.backgroundFit or "fill",
            self.props.backgroundSlice,
            borderRadius,
            self.props.imageTint,
            self.props.backgroundImageOpacity
        )
    end

    -- Container border
    local borderWidth = self.props.borderWidth or 0
    if borderWidth > 0 then
        local borderColor = self.props.borderColor or Theme.Color("border")
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, borderWidth)
        nvgStroke(nvg)
    end

    -- Clip content
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)

    local contentY = y

    -- Header
    if self.header_ then
        self:RenderHeader(nvg, x, contentY, w)
        contentY = contentY + self.headerHeight_

        -- Divider
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x, contentY)
        nvgLineTo(nvg, x + w, contentY)
        nvgStrokeColor(nvg, Theme.NvgColor("border"))
        nvgStrokeWidth(nvg, self.props.borderWidth or 1)
        nvgStroke(nvg)
    end

    -- Content padding
    local cp = self.props.contentPadding or 0
    local cpV, cpH
    if type(cp) == "table" then
        cpV, cpH = cp[1], cp[2]
    else
        cpV, cpH = cp, cp
    end

    -- Content
    local contentHeight = h - (self.header_ and self.headerHeight_ or 0) - (self.footer_ and self.headerHeight_ or 0) - cpV * 2
    local contentX = x + cpH
    local contentW = w - cpH * 2
    contentY = contentY + cpV
    if self.content_ then
        if type(self.content_) == "function" then
            self.content_(nvg, contentX, contentY, contentW, contentHeight)
        elseif self.content_.Render then
            -- Widget content: calculate Yoga layout and render via framework
            YGNodeCalculateLayout(self.content_.node, contentW, contentHeight, YGDirectionLTR)
            self.content_.renderOffsetX_ = contentX
            self.content_.renderOffsetY_ = contentY
            self.content_.renderWidth_ = contentW
            self.content_.renderHeight_ = contentHeight
            UI.RenderWidgetSubtree(self.content_, nvg)
        end
    end

    -- Footer
    if self.footer_ then
        local footerY = y + h - self.headerHeight_

        -- Divider
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x, footerY)
        nvgLineTo(nvg, x + w, footerY)
        nvgStrokeColor(nvg, Theme.NvgColor("border"))
        nvgStrokeWidth(nvg, self.props.borderWidth or 1)
        nvgStroke(nvg)

        self:RenderFooter(nvg, x, footerY, w)
    end

    nvgRestore(nvg)

    -- Close button
    if self.showCloseButton_ then
        self:RenderCloseButton(nvg, x, y, w)
    end
end

function Drawer:RenderOverlay(nvg, progress)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, self.screenWidth_, self.screenHeight_)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(255 * self.overlayOpacity_ * progress)))
    nvgFill(nvg)

    self.overlayBounds_ = { x = 0, y = 0, w = self.screenWidth_, h = self.screenHeight_ }
end

function Drawer:RenderHeader(nvg, x, y, w)
    local hp = self.props.headerPadding or {14, 16}
    local hpV, hpH
    if type(hp) == "table" then
        hpV, hpH = hp[1], hp[2]
    else
        hpV, hpH = hp, hp
    end

    local headerBgColor = self.props.headerBgColor
    if headerBgColor then
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, self.headerHeight_)
        nvgFillColor(nvg, nvgRGBA(headerBgColor[1], headerBgColor[2], headerBgColor[3], headerBgColor[4] or 255))
        nvgFill(nvg)
    end
    if self.props.headerBackgroundImage then
        self:RenderBackgroundImage(
            nvg,
            self.props.headerBackgroundImage,
            { x = x, y = y, w = w, h = self.headerHeight_ },
            self.props.headerBackgroundFit or self.props.backgroundFit or "fill",
            self.props.headerBackgroundSlice or self.props.backgroundSlice,
            0,
            self.props.headerImageTint or self.props.imageTint,
            self.props.headerBackgroundImageOpacity
        )
    end

    if type(self.header_) == "string" then
        -- Simple title
        nvgFontSize(nvg, Theme.FontSizeOf("subtitle"))
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local titleTextColor = self.props.titleTextColor or Theme.Color("text")
        nvgFillColor(nvg, nvgRGBA(titleTextColor[1], titleTextColor[2], titleTextColor[3], titleTextColor[4] or 255))
        nvgText(nvg, x + hpH, y + self.headerHeight_ / 2, self.header_)
    elseif type(self.header_) == "function" then
        self.header_(nvg, x, y, w, self.headerHeight_)
    elseif self.header_.Render then
        nvgSave(nvg)
        nvgTranslate(nvg, x, y)
        self.header_:Render(nvg)
        nvgRestore(nvg)
    end
end

function Drawer:RenderFooter(nvg, x, y, w)
    local theme = Theme.GetTheme()

    if type(self.footer_) == "string" then
        nvgFontSize(nvg, Theme.FontSizeOf("body"))
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local footerTextColor = self.props.footerTextColor or Theme.Color("textSecondary")
        nvgFillColor(nvg, nvgRGBA(footerTextColor[1], footerTextColor[2], footerTextColor[3], footerTextColor[4] or 255))
        nvgText(nvg, x + 16, y + self.headerHeight_ / 2, self.footer_)
    elseif type(self.footer_) == "function" then
        self.footer_(nvg, x, y, w, self.headerHeight_)
    elseif self.footer_.Render then
        nvgSave(nvg)
        nvgTranslate(nvg, x, y)
        self.footer_:Render(nvg)
        nvgRestore(nvg)
    end
end

function Drawer:RenderCloseButton(nvg, x, y, w)
    local btnSize = 32
    local btnX, btnY

    if self.position_ == "left" then
        btnX = x + w - btnSize - 8
        btnY = y + 12
    elseif self.position_ == "right" then
        btnX = x + 8
        btnY = y + 12
    else
        btnX = x + w - btnSize - 8
        btnY = y + 12
    end

    self.closeButtonBounds_ = { x = btnX, y = btnY, w = btnSize, h = btnSize }

    -- Button background
    local closeBgColor = self.props.closeButtonBgColor
    if self.hoverCloseButton_ then
        closeBgColor = self.props.closeButtonHoverBgColor or closeBgColor or Theme.Color("surfaceHover")
    end
    if closeBgColor then
        nvgBeginPath(nvg)
        nvgCircle(nvg, btnX + btnSize / 2, btnY + btnSize / 2, btnSize / 2)
        nvgFillColor(nvg, nvgRGBA(closeBgColor[1], closeBgColor[2], closeBgColor[3], closeBgColor[4] or 255))
        nvgFill(nvg)
    end

    -- X icon
    local centerX = btnX + btnSize / 2
    local centerY = btnY + btnSize / 2
    local iconSize = 8

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, centerX - iconSize, centerY - iconSize)
    nvgLineTo(nvg, centerX + iconSize, centerY + iconSize)
    nvgMoveTo(nvg, centerX + iconSize, centerY - iconSize)
    nvgLineTo(nvg, centerX - iconSize, centerY + iconSize)
    local closeIconColor = self.props.closeIconColor or Theme.Color("text")
    nvgStrokeColor(nvg, nvgRGBA(closeIconColor[1], closeIconColor[2], closeIconColor[3], closeIconColor[4] or 255))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
end

function Drawer:CalculateDrawerBounds(progress)
    local x, y, w, h

    if self.position_ == "left" then
        w = self.size_
        h = self.screenHeight_
        x = -w + (w * progress)
        y = 0
    elseif self.position_ == "right" then
        w = self.size_
        h = self.screenHeight_
        x = self.screenWidth_ - (w * progress)
        y = 0
    elseif self.position_ == "top" then
        w = self.screenWidth_
        h = self.size_
        x = 0
        y = -h + (h * progress)
    elseif self.position_ == "bottom" then
        w = self.screenWidth_
        h = self.size_
        x = 0
        y = self.screenHeight_ - (h * progress)
    end

    return x, y, w, h
end

-- ============================================================================
-- Easing
-- ============================================================================

function Drawer:EaseOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

-- ============================================================================
-- Hit Testing
-- ============================================================================

--- Override HitTest - only intercept events when open or animating
function Drawer:HitTest(x, y)
    -- Don't intercept events when closed
    if self.animationProgress_ <= 0 and not self.animating_ then
        return false
    end

    -- When open, check if click is on overlay or drawer
    return true
end

--- Return content widget for findWidgetAt to recurse into (hit testing)
function Drawer:GetHitTestChildren()
    if self.content_ and type(self.content_) ~= "function" then
        return { self.content_ }
    end
    return nil
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Drawer:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function Drawer:OnPointerMove(event)
    if not event then return end
    if not self.isOpen_ and not self.animating_ then return end

    -- Drawer is a full-screen overlay, use event coords directly
    local px, py = event.x, event.y

    -- Check close button hover
    local wasHover = self.hoverCloseButton_
    self.hoverCloseButton_ = self.showCloseButton_ and
                             self.closeButtonBounds_ and
                             self:PointInBounds(px, py, self.closeButtonBounds_)
end

function Drawer:OnClick(event)
    if not event then return end

    -- Drawer is a full-screen overlay, use event coords directly
    local px, py = event.x, event.y

    -- Check close button
    if self.showCloseButton_ and self:PointInBounds(px, py, self.closeButtonBounds_) then
        self:Close()
        return true
    end

    -- Check click outside drawer (close for temporary variant)
    if self.variant_ == "temporary" then
        if not self:PointInBounds(px, py, self.drawerBounds_) then
            self:Close()
            return true
        end
    end

    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a left drawer
---@param props table|nil
---@return Drawer
function Drawer.Left(props)
    props = props or {}
    props.position = "left"
    return Drawer(props)
end

--- Create a right drawer
---@param props table|nil
---@return Drawer
function Drawer.Right(props)
    props = props or {}
    props.position = "right"
    return Drawer(props)
end

--- Create a top drawer
---@param props table|nil
---@return Drawer
function Drawer.Top(props)
    props = props or {}
    props.position = "top"
    return Drawer(props)
end

--- Create a bottom drawer
---@param props table|nil
---@return Drawer
function Drawer.Bottom(props)
    props = props or {}
    props.position = "bottom"
    return Drawer(props)
end

--- Create a navigation drawer
---@param title string
---@param items table[] Menu items
---@param props table|nil
---@return Drawer
function Drawer.Navigation(title, items, props)
    props = props or {}
    props.header = title
    props.position = "left"
    props.size = props.size or 280
    props.showCloseButton = true

    -- Content will be rendered as menu items
    props.content = function(nvg, x, y, w, h)
        local theme = Theme.GetTheme()
        local itemHeight = 48
        local currentY = y + 8

        for i, item in ipairs(items) do
            local itemY = currentY + (i - 1) * itemHeight
            local itemSelected = item.selected or item.active or item.isSelected
            local itemHovered = item.hovered or item.isHovered
            local itemBgColor = item.bgColor or props.itemBgColor
            if itemSelected then
                itemBgColor = item.selectedBgColor or props.itemSelectedBgColor or itemBgColor
            elseif itemHovered then
                itemBgColor = item.hoverBgColor or props.itemHoverBgColor or itemBgColor
            end
            if itemBgColor then
                local itemRadius = props.itemBorderRadius or 6
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x + 8, itemY + 4, w - 16, itemHeight - 8, itemRadius)
                nvgFillColor(nvg, nvgRGBA(itemBgColor[1], itemBgColor[2], itemBgColor[3], itemBgColor[4] or 255))
                nvgFill(nvg)
            end

            nvgFontSize(nvg, Theme.FontSizeOf("body"))
            nvgFontFace(nvg, Theme.FontFamily())
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

            -- Icon
            if item.icon then
                local itemIconColor = props.contentTextColor or Theme.Color("textSecondary")
                nvgFillColor(nvg, nvgRGBA(itemIconColor[1], itemIconColor[2], itemIconColor[3], itemIconColor[4] or 255))
                nvgText(nvg, x + 16, itemY + itemHeight / 2, item.icon)
            end

            -- Label
            local itemTextColor = props.contentTextColor or Theme.Color("text")
            nvgFillColor(nvg, nvgRGBA(itemTextColor[1], itemTextColor[2], itemTextColor[3], itemTextColor[4] or 255))
            nvgText(nvg, x + 56, itemY + itemHeight / 2, item.label or item.text or "")
        end
    end

    return Drawer(props)
end

--- Create a bottom sheet drawer
---@param props table|nil
---@return Drawer
function Drawer.BottomSheet(props)
    props = props or {}
    props.position = "bottom"
    props.size = props.size or 400
    return Drawer(props)
end

return Drawer
