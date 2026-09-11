-- ============================================================================
-- Toast Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Toast notification system with auto-dismiss
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class ToastItem
---@field id number Unique toast ID
---@field message string Toast message
---@field type string "info" | "success" | "warning" | "error"
---@field duration number Duration in seconds
---@field showClose boolean Show close button
---@field progress_ number Animation progress (0-1)
---@field timeRemaining_ number Time remaining before dismiss
---@field state_ string "entering" | "visible" | "exiting" | "done"

---@class ToastProps : WidgetProps
---@field position? string "top" | "top-left" | "top-right" | "bottom" | "bottom-left" | "bottom-right"
---@field maxToasts? number Maximum visible toasts (default: 5)
---@field spacing? number Spacing between toasts (default: 8)
---@field screenWidth? number Screen width override (default: 800)
---@field screenHeight? number Screen height override (default: 600)
---@field typeColor? table Per-toast-type color { info/success/warning/error = RGBAColor }
---@field textColor? RGBAColor|string Message text color
---@field closeIconColor? RGBAColor|string Close icon color

---@class Toast : Widget
---@overload fun(props?: ToastProps): Toast
---@field props ToastProps
---@field new fun(self, props?: ToastProps): Toast
local Toast = Widget:Extend("Toast")

-- Toast type icons (simple shapes)
local TOAST_ICONS = {
    info = "i",
    success = "✓",
    warning = "!",
    error = "✕",
}

-- Toast type colors
local TOAST_COLORS = {
    info = { 59, 130, 246 },      -- Blue
    success = { 34, 197, 94 },    -- Green
    warning = { 245, 158, 11 },   -- Amber
    error = { 239, 68, 68 },      -- Red
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ToastProps?
function Toast:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Toast")
    Style.ApplyDefaults(props, themeStyle)

    -- Default settings
    props.borderRadius = props.borderRadius or 8
    props.position = props.position or "top-right"
    props.maxToasts = props.maxToasts or 5
    props.spacing = props.spacing or 10

    -- Toast container is overlay
    props.position_ = "absolute"

    -- Toast queue
    self.toasts_ = {}
    self.nextId_ = 1

    -- Screen dimensions
    self.screenWidth_ = props.screenWidth or 800
    self.screenHeight_ = props.screenHeight or 600

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Toast:Render(nvg)
    if #self.toasts_ == 0 then
        return
    end

    local position = self.props.position
    local spacing = self.props.spacing
    local toastWidth = 320
    local toastHeight = 56
    local margin = 20
    local borderRadius = self.props.borderRadius
    local slideOffset = 50
    local slideOffsetSmall = 30

    -- Get screen size from UI
    local screenWidth = UI.GetWidth() or 800
    local screenHeight = UI.GetHeight() or 600

    -- Calculate base position
    local baseX, baseY, direction

    if position == "top" then
        baseX = (screenWidth - toastWidth) / 2
        baseY = margin
        direction = 1
    elseif position == "top-left" then
        baseX = margin
        baseY = margin
        direction = 1
    elseif position == "top-right" then
        baseX = screenWidth - toastWidth - margin
        baseY = margin
        direction = 1
    elseif position == "bottom" then
        baseX = (screenWidth - toastWidth) / 2
        baseY = screenHeight - toastHeight - margin
        direction = -1
    elseif position == "bottom-left" then
        baseX = margin
        baseY = screenHeight - toastHeight - margin
        direction = -1
    elseif position == "bottom-right" then
        baseX = screenWidth - toastWidth - margin
        baseY = screenHeight - toastHeight - margin
        direction = -1
    else
        -- Default to top-right
        baseX = screenWidth - toastWidth - margin
        baseY = margin
        direction = 1
    end

    -- Render each toast
    local offsetY = 0
    for i, toast in ipairs(self.toasts_) do
        if toast.state_ ~= "done" then
            local toastY = baseY + offsetY * direction

            -- Animation offset
            local animOffset = 0
            local alpha = 1

            if toast.state_ == "entering" then
                local t = toast.progress_
                -- Slide in from side
                if position:find("right") then
                    animOffset = (1 - t) * slideOffset
                elseif position:find("left") then
                    animOffset = (t - 1) * slideOffset
                else
                    animOffset = (t - 1) * slideOffsetSmall * direction
                end
                alpha = t
            elseif toast.state_ == "exiting" then
                local t = toast.progress_
                -- Fade out and slide
                if position:find("right") then
                    animOffset = t * slideOffset
                elseif position:find("left") then
                    animOffset = -t * slideOffset
                end
                alpha = 1 - t
            end

            self:RenderToast(nvg, toast, baseX + animOffset, toastY, toastWidth, toastHeight, borderRadius, alpha)

            offsetY = offsetY + toastHeight + spacing
        end
    end
end

--- Render a single toast
function Toast:RenderToast(nvg, toast, x, y, width, height, borderRadius, alpha)
    local toastType = toast.type or "info"
    local message = toast.message or ""
    local showClose = toast.showClose

    -- Store toast layout for hit testing
    toast.layout_ = { x = x, y = y, w = width, h = height }

    -- Get colors
    local typeColor = (self.props.typeColor and self.props.typeColor[toastType]) or TOAST_COLORS[toastType] or TOAST_COLORS.info
    local bgColor = self.props.toastBgColor or Theme.Color("surface")
    local textColor = self.props.textColor or Theme.Color("text")

    -- Layout values
    local shadowOffset = 2
    local accentBarWidth = self.props.accentBarWidth or 4

    -- Draw shadow
    local boxShadow = self.props.boxShadow
    if boxShadow == false then
        -- Explicitly disabled.
    elseif boxShadow then
        nvgSave(nvg)
        nvgGlobalAlpha(nvg, alpha)
        local geom = self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, borderRadius)
        self:RenderBoxShadows(nvg, geom, boxShadow)
        nvgRestore(nvg)
    else
        self:CreateShapePath(nvg, self:GetShapeGeometry(
            { x = x - shadowOffset, y = y + shadowOffset, w = width + shadowOffset * 2, h = height + shadowOffset },
            nil,
            Widget.OffsetRadius(borderRadius, shadowOffset)
        ))
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(40 * alpha)))
        nvgFill(nvg)
    end

    -- Draw background
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], math.floor(250 * alpha)))
    nvgFill(nvg)

    if self.props.backgroundImage then
        self:RenderBackgroundImage(
            nvg,
            self.props.backgroundImage,
            { x = x, y = y, w = width, h = height },
            self.props.backgroundFit or "fill",
            self.props.backgroundSlice,
            borderRadius,
            self.props.imageTint,
            (self.props.backgroundImageOpacity or 1) * alpha
        )
    end

    -- Draw left accent bar (skip when accentBarWidth = 0)
    local accentBarHeight = self.props.accentBarHeight or height
    local accentBarY = y + (height - accentBarHeight) / 2
    local accentBarInset = self.props.accentBarInset or 0
    if accentBarWidth > 0 then
        nvgBeginPath(nvg)
        if accentBarHeight < height then
            nvgRect(nvg, x + accentBarInset, accentBarY, accentBarWidth, accentBarHeight)
        else
            local leftRadius = type(borderRadius) == "table"
                and { borderRadius[1] or 0, 0, 0, borderRadius[4] or 0 }
                or { borderRadius or 0, 0, 0, borderRadius or 0 }
            self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = accentBarWidth, h = height }, nil, leftRadius))
        end
        nvgFillColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
        nvgFill(nvg)
    end

    -- Draw border (props.borderColor > variant typeColor with borderOpacity > Theme border)
    local borderColor = self.props.borderColor
    local borderBaseAlpha
    if borderColor then
        borderBaseAlpha = borderColor[4] or 255
    elseif self.props.borderOpacity then
        -- Variant-colored border with opacity
        borderColor = typeColor
        borderBaseAlpha = math.floor((typeColor[4] or 255) * self.props.borderOpacity)
    else
        borderColor = Theme.Color("border")
        borderBaseAlpha = self.props.borderWidth and (borderColor[4] or 255) or math.min(borderColor[4] or 255, 100)
    end
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, borderRadius))
    nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], math.floor(borderBaseAlpha * alpha)))
    nvgStrokeWidth(nvg, self.props.borderWidth or 1)
    nvgStroke(nvg)

    -- Font family (needed for both icon and text)
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)

    -- Draw icon circle and icon (optional)
    local showIcon = self.props.showIcon ~= false  -- default true
    if showIcon then
        local iconX = x + 20
        local iconY = y + height / 2
        local iconRadius = 12

        nvgBeginPath(nvg)
        nvgCircle(nvg, iconX, iconY, iconRadius)
        nvgFillColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(30 * alpha)))
        nvgFill(nvg)

        -- Draw icon
        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, Theme.FontSizeOf("body"))
        nvgFillColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)

        local icon = TOAST_ICONS[toastType] or "i"
        if toastType == "success" then
            -- Draw checkmark
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, iconX - 5, iconY)
            nvgLineTo(nvg, iconX - 1, iconY + 4)
            nvgLineTo(nvg, iconX + 5, iconY - 4)
            nvgStrokeColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
            nvgStrokeWidth(nvg, 2)
            nvgLineCap(nvg, NVG_ROUND)
            nvgLineJoin(nvg, NVG_ROUND)
            nvgStroke(nvg)
        elseif toastType == "error" then
            -- Draw X
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, iconX - 4, iconY - 4)
            nvgLineTo(nvg, iconX + 4, iconY + 4)
            nvgMoveTo(nvg, iconX + 4, iconY - 4)
            nvgLineTo(nvg, iconX - 4, iconY + 4)
            nvgStrokeColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
            nvgStrokeWidth(nvg, 2)
            nvgLineCap(nvg, NVG_ROUND)
            nvgStroke(nvg)
        elseif toastType == "warning" then
            -- Draw exclamation
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, iconX, iconY - 6)
            nvgLineTo(nvg, iconX, iconY + 1)
            nvgStrokeColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
            nvgStrokeWidth(nvg, 2.5)
            nvgLineCap(nvg, NVG_ROUND)
            nvgStroke(nvg)
            nvgBeginPath(nvg)
            nvgCircle(nvg, iconX, iconY + 5, 1.5)
            nvgFillColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
            nvgFill(nvg)
        else
            -- Draw info "i"
            nvgBeginPath(nvg)
            nvgCircle(nvg, iconX, iconY - 5, 1.5)
            nvgFillColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, iconX, iconY - 1)
            nvgLineTo(nvg, iconX, iconY + 6)
            nvgStrokeColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(255 * alpha)))
            nvgStrokeWidth(nvg, 2.5)
            nvgLineCap(nvg, NVG_ROUND)
            nvgStroke(nvg)
        end
    end

    -- Draw message text
    local textX = showIcon and (x + 44) or (x + accentBarInset + accentBarWidth + 8)
    local textMaxWidth = width - (textX - x) - (showClose and 36 or 16)

    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, Theme.FontSizeOf("body"))
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], math.floor(255 * alpha)))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- Clip text
    nvgSave(nvg)
    nvgIntersectScissor(nvg, textX, y, textMaxWidth, height)
    nvgText(nvg, textX, y + height / 2, message, nil)
    nvgRestore(nvg)

    -- Draw close button
    if showClose then
        local closeX = x + width - 28
        local closeY = y + height / 2
        local closeSize = 8
        local closeHitSize = 20

        -- Store hit area
        toast.closeButtonLayout_ = {
            x = closeX - closeHitSize / 2,
            y = closeY - closeHitSize / 2,
            w = closeHitSize,
            h = closeHitSize,
        }

        -- Hover effect
        if toast.closeHovered_ then
            nvgBeginPath(nvg)
            nvgCircle(nvg, closeX, closeY, 12)
            nvgFillColor(nvg, nvgRGBA(128, 128, 128, math.floor(30 * alpha)))
            nvgFill(nvg)
        end

        -- X icon
        local closeColor = self.props.closeIconColor or Theme.Color("textSecondary")
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, closeX - closeSize / 2, closeY - closeSize / 2)
        nvgLineTo(nvg, closeX + closeSize / 2, closeY + closeSize / 2)
        nvgMoveTo(nvg, closeX + closeSize / 2, closeY - closeSize / 2)
        nvgLineTo(nvg, closeX - closeSize / 2, closeY + closeSize / 2)
        nvgStrokeColor(nvg, nvgRGBA(closeColor[1], closeColor[2], closeColor[3], math.floor(200 * alpha)))
        nvgStrokeWidth(nvg, 1.5)
        nvgLineCap(nvg, NVG_ROUND)
        nvgStroke(nvg)
    end

    -- Draw progress bar (time remaining)
    if toast.duration and toast.duration > 0 and toast.state_ == "visible" then
        local progressPadding = 4
        local progressWidth = width - progressPadding * 2
        local progressHeight = 2
        local progressX = x + progressPadding
        local progressY = y + height - progressPadding
        local progress = toast.timeRemaining_ / toast.duration

        -- Background
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, progressX, progressY, progressWidth, progressHeight, 1)
        nvgFillColor(nvg, nvgRGBA(128, 128, 128, math.floor(30 * alpha)))
        nvgFill(nvg)

        -- Progress
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, progressX, progressY, progressWidth * progress, progressHeight, 1)
        nvgFillColor(nvg, nvgRGBA(typeColor[1], typeColor[2], typeColor[3], math.floor(150 * alpha)))
        nvgFill(nvg)
    end
end

-- ============================================================================
-- Update
-- ============================================================================

function Toast:Update(dt)
    local animSpeed = 6

    for i = #self.toasts_, 1, -1 do
        local toast = self.toasts_[i]

        if toast.state_ == "entering" then
            toast.progress_ = math.min(1, toast.progress_ + dt * animSpeed)
            if toast.progress_ >= 1 then
                toast.state_ = "visible"
                toast.progress_ = 0
            end
        elseif toast.state_ == "visible" then
            if toast.duration and toast.duration > 0 then
                toast.timeRemaining_ = toast.timeRemaining_ - dt
                if toast.timeRemaining_ <= 0 then
                    toast.state_ = "exiting"
                    toast.progress_ = 0
                end
            end
        elseif toast.state_ == "exiting" then
            toast.progress_ = math.min(1, toast.progress_ + dt * animSpeed)
            if toast.progress_ >= 1 then
                toast.state_ = "done"
                table.remove(self.toasts_, i)
            end
        end
    end
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Toast:OnPointerDown(event)
    for _, toast in ipairs(self.toasts_) do
        if toast.showClose and toast.closeButtonLayout_ then
            local cbl = toast.closeButtonLayout_
            if event.x >= cbl.x and event.x <= cbl.x + cbl.w
                and event.y >= cbl.y and event.y <= cbl.y + cbl.h then
                self:Dismiss(toast.id)
                return true
            end
        end
    end
    return false
end

function Toast:OnPointerMove(event)
    for _, toast in ipairs(self.toasts_) do
        if toast.showClose and toast.closeButtonLayout_ then
            local cbl = toast.closeButtonLayout_
            local hovered = event.x >= cbl.x and event.x <= cbl.x + cbl.w
                and event.y >= cbl.y and event.y <= cbl.y + cbl.h
            toast.closeHovered_ = hovered
        end
    end
end

-- ============================================================================
-- Hit Test
-- ============================================================================

function Toast:HitTest(x, y)
    -- Check if point is in any toast area (for hover and click)
    for _, toast in ipairs(self.toasts_) do
        if toast.layout_ then
            local l = toast.layout_
            if x >= l.x and x <= l.x + l.w
                and y >= l.y and y <= l.y + l.h then
                return true
            end
        end
    end
    return false
end

function Toast:OnClick(event)
    local x, y = event.x, event.y

    -- Check close button clicks
    for i, toast in ipairs(self.toasts_) do
        if toast.showClose and toast.closeButtonLayout_ then
            local cbl = toast.closeButtonLayout_
            if x >= cbl.x and x <= cbl.x + cbl.w
                and y >= cbl.y and y <= cbl.y + cbl.h then
                -- Dismiss this toast
                self:Dismiss(toast.id)
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Show a toast message (instance method)
---@param message string The message to display
---@param options table|nil { type, duration, showClose }
---@return number toastId
function Toast:ShowInstance(message, options)
    options = options or {}

    local toast = {
        id = self.nextId_,
        message = message,
        type = options.type or "info",
        duration = options.duration or 3,  -- seconds, 0 for no auto-dismiss
        showClose = options.showClose ~= false,  -- default true
        progress_ = 0,
        timeRemaining_ = options.duration or 3,
        state_ = "entering",
    }

    self.nextId_ = self.nextId_ + 1

    -- Limit max toasts
    while #self.toasts_ >= self.props.maxToasts do
        -- Remove oldest
        table.remove(self.toasts_, 1)
    end

    table.insert(self.toasts_, toast)

    return toast.id
end

--- Show info toast
---@param message string
---@param duration number|nil
---@return number toastId
function Toast:Info(message, duration)
    return self:ShowInstance(message, { type = "info", duration = duration })
end

--- Show success toast
---@param message string
---@param duration number|nil
---@return number toastId
function Toast:Success(message, duration)
    return self:ShowInstance(message, { type = "success", duration = duration })
end

--- Show warning toast
---@param message string
---@param duration number|nil
---@return number toastId
function Toast:Warning(message, duration)
    return self:ShowInstance(message, { type = "warning", duration = duration })
end

--- Show error toast
---@param message string
---@param duration number|nil
---@return number toastId
function Toast:Error(message, duration)
    return self:ShowInstance(message, { type = "error", duration = duration or 5 })  -- Error shows longer
end

--- Dismiss a toast by ID
---@param toastId number
function Toast:Dismiss(toastId)
    for _, toast in ipairs(self.toasts_) do
        if toast.id == toastId and toast.state_ ~= "exiting" and toast.state_ ~= "done" then
            toast.state_ = "exiting"
            toast.progress_ = 0
            break
        end
    end
end

--- Dismiss all toasts
function Toast:DismissAll()
    for _, toast in ipairs(self.toasts_) do
        if toast.state_ ~= "exiting" and toast.state_ ~= "done" then
            toast.state_ = "exiting"
            toast.progress_ = 0
        end
    end
end

--- Set screen dimensions
---@param width number
---@param height number
---@return Toast self
function Toast:SetScreenSize(width, height)
    self.screenWidth_ = width
    self.screenHeight_ = height
    return self
end

--- Set position
---@param position string "top" | "top-left" | "top-right" | "bottom" | "bottom-left" | "bottom-right"
---@return Toast self
function Toast:SetPosition(position)
    self.props.position = position
    return self
end

--- Get active toast count
---@return number
function Toast:GetCount()
    local count = 0
    for _, toast in ipairs(self.toasts_) do
        if toast.state_ ~= "done" then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Toast:IsStateful()
    return true
end

-- ============================================================================
-- Global Instance (Singleton pattern for convenience)
-- ============================================================================

local globalInstance = nil

--- Get or create global toast instance
---@param props table|nil
---@return Toast
function Toast.GetGlobal(props)
    if not globalInstance then
        globalInstance = Toast:new(props or {})
    end
    return globalInstance
end

--- Show toast using global instance (static method)
--- Supports both: Toast.Show("message", options) and Toast.Show({ message = "...", variant = "..." })
---@param messageOrProps string|table
---@param options table|nil
---@return number toastId
function Toast.Show(messageOrProps, options)
    local message, opts
    if type(messageOrProps) == "table" then
        -- Called as Toast.Show({ message = "...", variant = "..." })
        message = messageOrProps.message or ""
        opts = {
            type = messageOrProps.variant or messageOrProps.type or "info",
            duration = messageOrProps.duration,
            showClose = messageOrProps.showClose,
        }
    else
        -- Called as Toast.Show("message", options)
        message = messageOrProps
        opts = options
    end

    -- Register global Toast instance on first use
    local instance = Toast.GetGlobal()
    if not instance.registered_ then
        UI.RegisterGlobalComponent("Toast", instance)
        instance.registered_ = true
    end

    return instance:ShowInstance(message, opts)
end

--- Show toast using global instance (legacy)
---@param message string
---@param options table|nil
---@return number toastId
function Toast.ShowGlobal(message, options)
    return Toast.GetGlobal():ShowInstance(message, options)
end

--- Show info toast using global instance
---@param message string
---@param duration number|nil
---@return number toastId
function Toast.InfoGlobal(message, duration)
    return Toast.GetGlobal():Info(message, duration)
end

--- Show success toast using global instance
---@param message string
---@param duration number|nil
---@return number toastId
function Toast.SuccessGlobal(message, duration)
    return Toast.GetGlobal():Success(message, duration)
end

--- Show warning toast using global instance
---@param message string
---@param duration number|nil
---@return number toastId
function Toast.WarningGlobal(message, duration)
    return Toast.GetGlobal():Warning(message, duration)
end

--- Show error toast using global instance
---@param message string
---@param duration number|nil
---@return number toastId
function Toast.ErrorGlobal(message, duration)
    return Toast.GetGlobal():Error(message, duration)
end

return Toast
