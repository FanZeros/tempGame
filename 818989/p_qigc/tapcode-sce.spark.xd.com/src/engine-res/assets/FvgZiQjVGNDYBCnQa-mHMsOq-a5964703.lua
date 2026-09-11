-- ============================================================================
-- Alert Widget
-- Notification banners for displaying important messages
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class AlertAction
---@field text string Action button text
---@field onClick? fun(alert: Alert) Action click callback

---@class AlertProps : WidgetProps
---@field severity? string "info" | "success" | "warning" | "error" (default: "info")
---@field title? string Alert title
---@field message? string Alert message
---@field text? string Alias for message
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field variant? string "filled" | "outlined" | "standard" (default: "filled")
---@field closable? boolean Show close button
---@field closeable? boolean Alias for closable
---@field dismissible? boolean Alias for closable
---@field showIcon? boolean Show severity icon (default: true)
---@field icon? string Custom icon
---@field iconSize? number Custom icon size
---@field fontSize? number Custom font size
---@field titleSize? number Custom title font size
---@field standardBgColor? RGBAColor|string Standard variant background color
---@field standardSeverityBgColor? table Standard variant per-severity background color { severity = RGBAColor }
---@field standardSeverityIconColor? table Standard variant per-severity icon color { severity = RGBAColor }
---@field standardSeverityTitleColor? table Standard variant per-severity title color { severity = RGBAColor }
---@field standardSeverityTextColor? table Standard variant per-severity message color { severity = RGBAColor }
---@field standardSeverityBorderColor? table Standard variant per-severity border color { severity = RGBAColor }
---@field action? AlertAction Action button {text, onClick}
---@field onClose? fun(self: Alert) Close callback

---@class Alert : Widget
---@overload fun(props?: AlertProps): Alert
---@field props AlertProps
---@field new fun(self, props?: AlertProps): Alert
local Alert = Widget:Extend("Alert")

-- ============================================================================
-- Severity colors
-- ============================================================================

local SEVERITY_COLORS = {
    info = "info",
    success = "success",
    warning = "warning",
    error = "error",
}

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { padding = 8, iconSize = 16, fontSize = 12, titleSize = 13, gap = 8 },
    md = { padding = 12, iconSize = 20, fontSize = 14, titleSize = 15, gap = 10 },
    lg = { padding = 16, iconSize = 24, fontSize = 16, titleSize = 18, gap = 12 },
}

local function toNvgColor(color)
    if color == false then
        return nvgRGBA(0, 0, 0, 0)
    end
    local parsed = Style.ParseColor(color) or { 0, 0, 0, 0 }
    return nvgRGBA(parsed[1], parsed[2], parsed[3], parsed[4] or 255)
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props AlertProps?
function Alert:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Alert")
    Style.ApplyDefaults(props, themeStyle)

    -- Alert props
    self.severity_ = props.severity or "info"  -- info, success, warning, error
    self.variant_ = props.variant or "standard"  -- standard, filled, outlined
    self.size_ = props.size or "md"
    self.title_ = props.title
    self.message_ = props.message or props.text or ""
    self.showIcon_ = props.showIcon ~= false  -- default true
    self.icon_ = props.icon  -- custom icon text
    self.closeable_ = props.closeable or props.dismissible or false
    self.action_ = props.action  -- { text, onClick }
    self.onClose_ = props.onClose

    -- State
    self.isHoverClose_ = false
    self.isHoverAction_ = false

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.padding_ = props.padding or sizePreset.padding
    self.iconSize_ = props.iconSize or sizePreset.iconSize
    -- fontSize/titleSize are point values (like the preset): scale both override and default
    -- through Theme.FontSize so the theme control value stays in pt (consistent with Badge/Chip).
    self.fontSize_ = props.fontSize and Theme.FontSize(props.fontSize) or Theme.FontSize(sizePreset.fontSize)
    self.titleSize_ = props.titleSize and Theme.FontSize(props.titleSize) or Theme.FontSize(sizePreset.titleSize)
    self.gap_ = props.gap or sizePreset.gap
    -- Vertical spacing between the title row and the message row.
    self.titleGap_ = props.titleGap or 4

    -- Calculate height based on content
    local contentHeight = self.padding_ * 2
    if self.title_ then
        contentHeight = contentHeight + self.titleSize_ + self.titleGap_
    end
    contentHeight = contentHeight + self.fontSize_

    props.width = props.width or "100%"
    props.height = props.height or contentHeight
    props.borderRadius = props.borderRadius or 6

    Widget.Init(self, props)
end

-- ============================================================================
-- Close
-- ============================================================================

function Alert:Close()
    self:Hide()
    if self.onClose_ then
        self.onClose_(self)
    end
end

-- ============================================================================
-- Content Management
-- ============================================================================

function Alert:GetTitle()
    return self.title_
end

function Alert:SetTitle(title)
    self.title_ = title
end

function Alert:GetMessage()
    return self.message_
end

function Alert:SetMessage(message)
    self.message_ = message
end

function Alert:GetSeverity()
    return self.severity_
end

function Alert:SetSeverity(severity)
    self.severity_ = severity
end

-- ============================================================================
-- Color Helpers
-- ============================================================================

function Alert:GetColors()
    local severity = self.severity_
    local variant = self.variant_

    local baseColorTable = Theme.Color(SEVERITY_COLORS[severity] or "info")
    local baseColor = nvgRGBA(baseColorTable[1], baseColorTable[2], baseColorTable[3], baseColorTable[4] or 255)

    local textColorTable = Theme.Color("text")
    local textColor = nvgRGBA(textColorTable[1], textColorTable[2], textColorTable[3], textColorTable[4] or 255)

    local textSecondaryTable = Theme.Color("textSecondary")
    local textSecondary = nvgRGBA(textSecondaryTable[1], textSecondaryTable[2], textSecondaryTable[3], textSecondaryTable[4] or 255)

    if variant == "filled" then
        return {
            background = baseColor,
            border = baseColor,
            icon = nvgRGBA(255, 255, 255, 255),
            title = nvgRGBA(255, 255, 255, 255),
            text = nvgRGBA(255, 255, 255, 230),
            action = nvgRGBA(255, 255, 255, 255),
            close = nvgRGBA(255, 255, 255, 200),
        }
    elseif variant == "outlined" then
        return {
            background = nvgRGBA(0, 0, 0, 0),  -- transparent
            border = baseColor,
            icon = baseColor,
            title = textColor,
            text = textSecondary,
            action = baseColor,
            close = textSecondary,
        }
    else  -- standard
        local standardBg = self.props.standardSeverityBgColor and self.props.standardSeverityBgColor[severity]
        if standardBg == nil then
            standardBg = self.props.standardBgColor
        end
        if standardBg == nil then
            standardBg = self.props.backgroundColor
        end
        local standardIcon = self.props.standardSeverityIconColor and self.props.standardSeverityIconColor[severity]
        local standardTitle = self.props.standardSeverityTitleColor and self.props.standardSeverityTitleColor[severity]
        local standardText = self.props.standardSeverityTextColor and self.props.standardSeverityTextColor[severity]
        local standardBorder = self.props.standardSeverityBorderColor and self.props.standardSeverityBorderColor[severity]
        return {
            background = standardBg ~= nil and toNvgColor(standardBg) or nvgTransRGBAf(baseColor, 0.12),
            border = standardBorder ~= nil and toNvgColor(standardBorder) or nvgRGBA(0, 0, 0, 0),
            icon = standardIcon ~= nil and toNvgColor(standardIcon) or baseColor,
            title = standardTitle ~= nil and toNvgColor(standardTitle) or textColor,
            text = standardText ~= nil and toNvgColor(standardText) or textSecondary,
            action = standardIcon ~= nil and toNvgColor(standardIcon) or baseColor,
            close = textSecondary,
        }
    end
end

-- ============================================================================
-- Icon Drawing
-- ============================================================================

function Alert:DrawIcon(nvg, x, y, color)
    local size = self.iconSize_
    local cx = x + size / 2
    local cy = y + size / 2
    local r = size * 0.4

    nvgFillColor(nvg, color)
    nvgStrokeColor(nvg, color)
    nvgStrokeWidth(nvg, 1.5)

    local iconRadius = type(self.props.borderRadius) == "number" and self.props.borderRadius or r

    if self.icon_ then
        -- Custom icon (text)
        local theme = Theme.GetTheme()
        nvgFontSize(nvg, size * 0.8)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, cx, cy, self.icon_)
    elseif self.severity_ == "info" then
        -- Info icon: rounded rect with "i"
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - r, cy - r, r * 2, r * 2, iconRadius)
        nvgStroke(nvg)

        local theme = Theme.GetTheme()
        nvgFontSize(nvg, size * 0.6)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, cx, cy + 1, "i")
    elseif self.severity_ == "success" then
        -- Checkmark icon
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - r, cy - r, r * 2, r * 2, iconRadius)
        nvgStroke(nvg)

        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - r * 0.5, cy)
        nvgLineTo(nvg, cx - r * 0.1, cy + r * 0.4)
        nvgLineTo(nvg, cx + r * 0.5, cy - r * 0.3)
        nvgStroke(nvg)
    elseif self.severity_ == "warning" then
        -- Warning triangle with "!"
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy - r)
        nvgLineTo(nvg, cx + r, cy + r * 0.7)
        nvgLineTo(nvg, cx - r, cy + r * 0.7)
        nvgClosePath(nvg)
        nvgStroke(nvg)

        local theme = Theme.GetTheme()
        nvgFontSize(nvg, size * 0.5)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, cx, cy + r * 0.15, "!")
    elseif self.severity_ == "error" then
        -- Error icon with "x"
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - r, cy - r, r * 2, r * 2, iconRadius)
        nvgStroke(nvg)

        local cross = r * 0.4
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - cross, cy - cross)
        nvgLineTo(nvg, cx + cross, cy + cross)
        nvgMoveTo(nvg, cx + cross, cy - cross)
        nvgLineTo(nvg, cx - cross, cy + cross)
        nvgStroke(nvg)
    end
end

function Alert:DrawCloseButton(nvg, x, y, color, isHovered)
    local size = self.iconSize_ * 0.8
    local cx = x + size / 2
    local cy = y + size / 2
    local cross = size * 0.3

    -- Hover background
    if isHovered then
        local hoverR = size * 0.5
        local closeRadius = type(self.props.borderRadius) == "number" and self.props.borderRadius or hoverR
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - hoverR, cy - hoverR, hoverR * 2, hoverR * 2, closeRadius)
        nvgFillColor(nvg, nvgTransRGBAf(color, 0.2))
        nvgFill(nvg)
    end

    -- X icon
    nvgStrokeColor(nvg, color)
    nvgStrokeWidth(nvg, 1.5)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - cross, cy - cross)
    nvgLineTo(nvg, cx + cross, cy + cross)
    nvgMoveTo(nvg, cx + cross, cy - cross)
    nvgLineTo(nvg, cx - cross, cy + cross)
    nvgStroke(nvg)

    return size
end

-- ============================================================================
-- Render
-- ============================================================================

function Alert:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()
    local colors = self:GetColors()
    local theme = Theme.GetTheme()

    -- Calculate content height
    local contentHeight = self.padding_ * 2
    if self.title_ then
        contentHeight = contentHeight + self.titleSize_ + self.titleGap_
    end
    contentHeight = contentHeight + self.fontSize_

    -- Update height if auto
    if h < contentHeight then
        h = contentHeight
    end

    -- Background
    local rootGeom = self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, self.props.borderRadius or 6)
    self:CreateShapePath(nvg, rootGeom)
    nvgFillColor(nvg, colors.background)
    nvgFill(nvg)

    -- Border: always draw for outlined variant; for other variants only when borderWidth is explicitly set
    local alertBorderWidth = self.props.borderWidth
    local borderOpacity = self.props.borderOpacity
    if self.variant_ == "outlined" then
        local bc
        if self.props.borderColor then
            local c = self.props.borderColor
            local opacity = borderOpacity or 1.0
            bc = nvgRGBA(c[1], c[2], c[3], math.floor((c[4] or 255) * opacity))
        elseif borderOpacity then
            local severityColor = Theme.Color(SEVERITY_COLORS[self.severity_] or "info")
            bc = nvgRGBA(severityColor[1], severityColor[2], severityColor[3],
                math.floor((severityColor[4] or 255) * borderOpacity))
        else
            bc = colors.border
        end
        self:CreateShapePath(nvg, rootGeom)
        nvgStrokeColor(nvg, bc)
        nvgStrokeWidth(nvg, alertBorderWidth or 1)
        nvgStroke(nvg)
    elseif alertBorderWidth and alertBorderWidth > 0 then
        -- Theme-driven border for standard/filled variants (e.g. PixelForge)
        local borderColor = self.props.borderColor
        if not borderColor and self.variant_ == "standard" then
            borderColor = self.props.standardSeverityBorderColor and self.props.standardSeverityBorderColor[self.severity_]
        end
        if not borderColor then
            local severityColor = Theme.Color(SEVERITY_COLORS[self.severity_] or "info")
            local opacity = borderOpacity or 1.0
            borderColor = nvgRGBA(severityColor[1], severityColor[2], severityColor[3],
                math.floor((severityColor[4] or 255) * opacity))
        else
            local opacity = borderOpacity or 1.0
            borderColor = nvgRGBA(borderColor[1], borderColor[2], borderColor[3],
                math.floor((borderColor[4] or 255) * opacity))
        end
        self:CreateShapePath(nvg, rootGeom)
        nvgStrokeColor(nvg, borderColor)
        nvgStrokeWidth(nvg, alertBorderWidth)
        nvgStroke(nvg)
    end

    local contentX = x + self.padding_
    local contentY = y + self.padding_
    local contentWidth = w - self.padding_ * 2

    -- Icon
    if self.showIcon_ then
        local iconY = contentY
        if self.title_ then
            iconY = y + (h - self.iconSize_) / 2
        end
        self:DrawIcon(nvg, contentX, iconY, colors.icon)
        contentX = contentX + self.iconSize_ + self.gap_
        contentWidth = contentWidth - self.iconSize_ - self.gap_
    end

    -- Close button (reserve space)
    local closeButtonSize = 0
    if self.closeable_ then
        closeButtonSize = self.iconSize_ * 0.8 + self.gap_
        contentWidth = contentWidth - closeButtonSize
    end

    -- Action button (reserve space)
    local actionWidth = 0
    if self.action_ then
        nvgFontSize(nvg, self.fontSize_)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        local textWidth = nvgTextBounds(nvg, 0, 0, self.action_.text or "Action") or 0
        actionWidth = textWidth + self.gap_ * 2
        contentWidth = contentWidth - actionWidth
    end

    -- Title
    local textY = contentY
    if self.title_ then
        nvgFontSize(nvg, self.titleSize_)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(nvg, colors.title)
        nvgText(nvg, contentX, textY, self.title_)
        textY = textY + self.titleSize_ + self.titleGap_
    end

    -- Message
    if self.message_ and self.message_ ~= "" then
        nvgFontSize(nvg, self.fontSize_)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(nvg, colors.text)
        nvgText(nvg, contentX, textY, self.message_)
    end

    -- Action button
    if self.action_ then
        local actionX = x + w - self.padding_ - closeButtonSize - actionWidth + self.gap_
        local actionY = y + (h - self.fontSize_) / 2

        nvgFontSize(nvg, self.fontSize_)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        local actionColor = colors.action
        if self.isHoverAction_ then
            -- Underline on hover
            local underlineWidth = nvgTextBounds(nvg, actionX, actionY, self.action_.text) or 0
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, actionX, actionY + self.fontSize_ * 0.4)
            nvgLineTo(nvg, actionX + underlineWidth, actionY + self.fontSize_ * 0.4)
            nvgStrokeColor(nvg, actionColor)
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end

        nvgFillColor(nvg, actionColor)
        nvgText(nvg, actionX, actionY, self.action_.text)

        -- Store action button bounds
        local actionTextWidth = nvgTextBounds(nvg, actionX, actionY, self.action_.text) or 0
        self.actionBounds_ = {
            x1 = actionX,
            y1 = y + self.padding_,
            x2 = actionX + actionTextWidth,
            y2 = y + h - self.padding_,
        }
    end

    -- Close button
    if self.closeable_ then
        local closeX = x + w - self.padding_ - self.iconSize_ * 0.8
        local closeY = y + (h - self.iconSize_ * 0.8) / 2
        self:DrawCloseButton(nvg, closeX, closeY, colors.close, self.isHoverClose_)

        -- Store close button bounds
        self.closeBounds_ = {
            x1 = closeX,
            y1 = closeY,
            x2 = closeX + self.iconSize_ * 0.8,
            y2 = closeY + self.iconSize_ * 0.8,
        }
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Alert:IsPointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x1 and px <= bounds.x2 and py >= bounds.y1 and py <= bounds.y2
end

function Alert:OnPointerMove(event)
    if not event then return end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    self.isHoverClose_ = self:IsPointInBounds(px, py, self.closeBounds_)
    self.isHoverAction_ = self:IsPointInBounds(px, py, self.actionBounds_)
end

function Alert:OnMouseLeave()
    self.isHoverClose_ = false
    self.isHoverAction_ = false
end

function Alert:OnClick(event)
    if not event then return end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    if self:IsPointInBounds(px, py, self.closeBounds_) then
        self:Close()
    elseif self:IsPointInBounds(px, py, self.actionBounds_) then
        if self.action_ and self.action_.onClick then
            self.action_.onClick(self)
        end
    end
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create an info alert
---@param message string Alert message
---@param props table|nil Additional props
---@return Alert
function Alert.Info(message, props)
    props = props or {}
    props.message = message
    props.severity = "info"
    return Alert(props)
end

--- Create a success alert
---@param message string Alert message
---@param props table|nil Additional props
---@return Alert
function Alert.Success(message, props)
    props = props or {}
    props.message = message
    props.severity = "success"
    return Alert(props)
end

--- Create a warning alert
---@param message string Alert message
---@param props table|nil Additional props
---@return Alert
function Alert.Warning(message, props)
    props = props or {}
    props.message = message
    props.severity = "warning"
    return Alert(props)
end

--- Create an error alert
---@param message string Alert message
---@param props table|nil Additional props
---@return Alert
function Alert.Error(message, props)
    props = props or {}
    props.message = message
    props.severity = "error"
    return Alert(props)
end

--- Create an alert with title
---@param title string Alert title
---@param message string Alert message
---@param severity string|nil Severity type
---@param props table|nil Additional props
---@return Alert
function Alert.WithTitle(title, message, severity, props)
    props = props or {}
    props.title = title
    props.message = message
    props.severity = severity or "info"
    return Alert(props)
end

--- Create a closeable alert
---@param message string Alert message
---@param severity string|nil Severity type
---@param props table|nil Additional props
---@return Alert
function Alert.Closeable(message, severity, props)
    props = props or {}
    props.message = message
    props.severity = severity or "info"
    props.closeable = true
    return Alert(props)
end

--- Create an alert with action button
---@param message string Alert message
---@param actionText string Action button text
---@param onAction function Action callback
---@param props table|nil Additional props
---@return Alert
function Alert.WithAction(message, actionText, onAction, props)
    props = props or {}
    props.message = message
    props.action = {
        text = actionText,
        onClick = onAction,
    }
    return Alert(props)
end

--- Create a banner-style alert (full width, filled)
---@param message string Alert message
---@param severity string|nil Severity type
---@param props table|nil Additional props
---@return Alert
function Alert.Banner(message, severity, props)
    props = props or {}
    props.message = message
    props.severity = severity or "info"
    props.variant = "filled"
    props.width = "100%"
    props.borderRadius = 0
    return Alert(props)
end

return Alert
