-- ============================================================================
-- Badge Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Badge/indicator overlay for notifications, counts, status
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class BadgeProps : WidgetProps
---@field content? string|number Badge content (number or text)
---@field variant? string "primary" | "secondary" | "success" | "warning" | "error"
---@field variantBgColor? table Per-variant background color { variant_name = RGBAColor }
---@field variantTextColor? table Per-variant text color { variant_name = RGBAColor }
---@field variantBorderColor? table Per-variant border color { variant_name = RGBAColor }
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field dot? boolean Show as dot indicator only
---@field max? number Maximum count before showing "max+"
---@field showZero? boolean Show badge when count is 0
---@field position? string "top-right" | "top-left" | "bottom-right" | "bottom-left"
---@field standalone? boolean Render as standalone (not overlay)
---@field pulse? boolean Enable pulse animation

---@class Badge : Widget
---@overload fun(props?: BadgeProps): Badge
---@field props BadgeProps
---@field new fun(self, props?: BadgeProps): Badge
local Badge = Widget:Extend("Badge")

-- Size presets
-- paddingX drives width (text width + paddingX*2), paddingY drives height (fontSize + paddingY*2).
-- Default paddingY reproduces the preset height: sm 10+3*2=16, md 12+4*2=20, lg 14+5*2=24.
local SIZE_PRESETS = {
    sm = { height = 16, fontSize = 10, minWidth = 16, dotSize = 6, paddingX = 4, paddingY = 3 },
    md = { height = 20, fontSize = 12, minWidth = 20, dotSize = 8, paddingX = 5, paddingY = 4 },
    lg = { height = 24, fontSize = 14, minWidth = 24, dotSize = 10, paddingX = 6, paddingY = 5 },
}

-- Variant colors
local VARIANT_COLORS = {
    primary = "primary",
    secondary = "secondary",
    success = "success",
    warning = "warning",
    error = "error",
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props BadgeProps?
function Badge:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Badge")
    Style.ApplyDefaults(props, themeStyle)

    -- Default settings
    props.variant = props.variant or "error"
    props.size = props.size or "md"
    props.max = props.max or 99
    props.showZero = props.showZero or false
    props.position = props.position or "top-right"
    props.standalone = props.standalone or false
    props.dot = props.dot or false
    props.pulse = props.pulse or false

    -- Set default size based on size preset
    local sizePreset = SIZE_PRESETS[props.size] or SIZE_PRESETS.md
    props.height = props.height or ((self.props.fontSize or sizePreset.fontSize) + (self.props.badgePaddingY or sizePreset.paddingY) * 2)

    -- Calculate width based on content
    if not props.width then
        if props.dot then
            props.width = sizePreset.dotSize
        else
            local content = props.content
            local textLen = 0
            if content then
                if type(content) == "number" then
                    if content > (props.max or 99) then
                        textLen = #tostring(props.max or 99) + 1
                    else
                        textLen = #tostring(content)
                    end
                else
                    textLen = #tostring(content)
                end
            end
            -- Estimate width: minWidth or text width + horizontal padding
            local estimatedWidth = textLen * (self.props.fontSize or sizePreset.fontSize) * 0.6 + (self.props.badgePaddingX or sizePreset.paddingX) * 2
            props.width = math.max(sizePreset.minWidth, estimatedWidth)
        end
    end

    -- Animation state
    self.pulsePhase_ = 0

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Badge:Render(nvg)
    local props = self.props

    -- Determine if badge should be shown
    local content = props.content
    local showBadge = true

    if props.dot then
        -- Dot mode always shows (unless explicitly hidden)
        showBadge = true
    elseif content == nil then
        showBadge = false
    elseif type(content) == "number" then
        if content == 0 and not props.showZero then
            showBadge = false
        end
    elseif type(content) == "string" then
        if #content == 0 then
            showBadge = false
        end
    end

    if not showBadge then
        return
    end

    -- Get layout
    local l = self:GetAbsoluteLayout()

    -- Get size preset (no scale needed - nvgScale handles it)
    local sizePreset = SIZE_PRESETS[props.size] or SIZE_PRESETS.md
    local baseFontSize = self.props.fontSize or sizePreset.fontSize
    local fontSize = Theme.FontSize(baseFontSize)
    local minWidth = sizePreset.minWidth
    local dotSize = sizePreset.dotSize
    local paddingX = self.props.badgePaddingX or sizePreset.paddingX
    local paddingY = self.props.badgePaddingY or sizePreset.paddingY
    -- Height driven by vertical padding around the base font size (dot mode overrides to dotSize below).
    local badgeHeight = baseFontSize + paddingY * 2

    -- Format content
    local displayText = ""
    if not props.dot then
        if type(content) == "number" then
            if content > props.max then
                displayText = tostring(props.max) .. "+"
            else
                displayText = tostring(content)
            end
        else
            displayText = tostring(content)
        end
    end

    -- Calculate badge dimensions
    local badgeWidth, badgeX, badgeY

    if props.dot then
        badgeWidth = dotSize
        badgeHeight = dotSize
    else
        -- Measure text width
        local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, fontSize)
        local textWidth = nvgTextBounds(nvg, 0, 0, displayText, nil, nil)
        badgeWidth = math.max(minWidth, textWidth + paddingX * 2)
    end

    -- Calculate position
    -- Known badge overlay positions (distinct from Yoga position values like "absolute"/"relative")
    local BADGE_POSITIONS = { ["top-right"] = true, ["top-left"] = true, ["bottom-right"] = true, ["bottom-left"] = true }
    local isBadgePosition = BADGE_POSITIONS[props.position]

    if props.standalone or not isBadgePosition then
        -- Standalone badge or unrecognized position (e.g. Yoga "absolute") renders at widget position
        badgeX = l.x
        badgeY = l.y
    else
        -- Overlay badge positions relative to parent
        local offsetX = badgeWidth / 2 - 4
        local offsetY = badgeHeight / 2 - 4
        -- Use badgePosition (preferred) or position, but ignore Yoga position values
        local pos = props.badgePosition or props.position
        if pos == "relative" or pos == "absolute" then pos = "top-right" end

        if pos == "top-right" then
            badgeX = l.x + l.w - badgeWidth / 2 - offsetX
            badgeY = l.y - badgeHeight / 2 + offsetY
        elseif pos == "top-left" then
            badgeX = l.x - badgeWidth / 2 + offsetX
            badgeY = l.y - badgeHeight / 2 + offsetY
        elseif pos == "bottom-right" then
            badgeX = l.x + l.w - badgeWidth / 2 - offsetX
            badgeY = l.y + l.h - badgeHeight / 2 - offsetY
        elseif pos == "bottom-left" then
            badgeX = l.x - badgeWidth / 2 + offsetX
            badgeY = l.y + l.h - badgeHeight / 2 - offsetY
        else
            -- Fallback to top-right for unknown position values
            badgeX = l.x + l.w - badgeWidth / 2 - offsetX
            badgeY = l.y - badgeHeight / 2 + offsetY
        end
    end

    -- Get badge color
    local variant = props.variant
    local colorKey = VARIANT_COLORS[variant] or "error"
    local variantBg = props.variantBgColor and props.variantBgColor[variant]
    local variantText = props.variantTextColor and props.variantTextColor[variant]
    local variantBorder = props.variantBorderColor and props.variantBorderColor[variant]
    local bgColor = variantBg or Theme.Color(colorKey)
    local textColor = variantText or { 255, 255, 255, 255 }

    -- Pulse animation
    local pulseScale = 1
    local pulseAlpha = 0
    if props.pulse then
        pulseScale = 1 + math.sin(self.pulsePhase_) * 0.15
        pulseAlpha = math.max(0, math.sin(self.pulsePhase_)) * 100
    end

    local borderRadius = math.min(self.props.borderRadius or (badgeHeight / 2), math.min(badgeWidth, badgeHeight) / 2)

    -- Draw pulse effect
    if props.pulse and pulseAlpha > 0 then
        local pulseSize = props.dot and dotSize or badgeHeight
        nvgBeginPath(nvg)
        nvgCircle(nvg,
            badgeX + badgeWidth / 2,
            badgeY + badgeHeight / 2,
            pulseSize / 2 * (1 + pulseScale * 0.5)
        )
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], math.floor(pulseAlpha)))
        nvgFill(nvg)
    end

    -- Draw badge background
    nvgBeginPath(nvg)
    if props.dot then
        nvgCircle(nvg, badgeX + dotSize / 2, badgeY + dotSize / 2, dotSize / 2 * pulseScale)
    else
        nvgRoundedRect(nvg, badgeX, badgeY, badgeWidth * pulseScale, badgeHeight * pulseScale, borderRadius)
    end
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    -- Draw border
    local badgeBorderWidth = self.props.borderWidth or 1
    local badgeBorderColor = self.props.borderColor or variantBorder
    nvgBeginPath(nvg)
    if props.dot then
        nvgCircle(nvg, badgeX + dotSize / 2, badgeY + dotSize / 2, dotSize / 2 * pulseScale)
    else
        nvgRoundedRect(nvg, badgeX, badgeY, badgeWidth * pulseScale, badgeHeight * pulseScale, borderRadius)
    end
    if badgeBorderColor then
        nvgStrokeColor(nvg, nvgRGBA(badgeBorderColor[1], badgeBorderColor[2], badgeBorderColor[3], badgeBorderColor[4] or 255))
    else
        local darkened = Style.Darken(bgColor, 0.3)
        nvgStrokeColor(nvg, nvgRGBA(darkened[1], darkened[2], darkened[3], darkened[4] or 255))
    end
    nvgStrokeWidth(nvg, badgeBorderWidth)
    nvgStroke(nvg)

    -- Draw text (if not dot)
    if not props.dot and #displayText > 0 then
        local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, fontSize)
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4]))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, badgeX + badgeWidth / 2, badgeY + badgeHeight / 2, displayText, nil)
    end
end

-- ============================================================================
-- Update
-- ============================================================================

function Badge:Update(dt)
    -- Update pulse animation
    if self.props.pulse then
        self.pulsePhase_ = self.pulsePhase_ + dt * 4
        if self.pulsePhase_ > math.pi * 2 then
            self.pulsePhase_ = self.pulsePhase_ - math.pi * 2
        end
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set badge content
---@param content string|number|nil
---@return Badge self
function Badge:SetContent(content)
    self.props.content = content
    return self
end

--- Get badge content
---@return string|number|nil
function Badge:GetContent()
    return self.props.content
end

--- Set count (alias for SetContent with number)
---@param count number
---@return Badge self
function Badge:SetCount(count)
    self.props.content = count
    return self
end

--- Increment count
---@param amount number|nil Amount to add (default 1)
---@return Badge self
function Badge:Increment(amount)
    amount = amount or 1
    local current = self.props.content or 0
    if type(current) == "number" then
        self.props.content = current + amount
    end
    return self
end

--- Decrement count
---@param amount number|nil Amount to subtract (default 1)
---@return Badge self
function Badge:Decrement(amount)
    amount = amount or 1
    local current = self.props.content or 0
    if type(current) == "number" then
        self.props.content = math.max(0, current - amount)
    end
    return self
end

--- Clear badge (set content to nil)
---@return Badge self
function Badge:Clear()
    self.props.content = nil
    return self
end

--- Set variant
---@param variant string "primary" | "secondary" | "success" | "warning" | "error"
---@return Badge self
function Badge:SetVariant(variant)
    self.props.variant = variant
    return self
end

--- Set size
---@param size string "sm" | "md" | "lg"
---@return Badge self
function Badge:SetSize(size)
    self.props.size = size
    return self
end

--- Set as dot indicator
---@param isDot boolean
---@return Badge self
function Badge:SetDot(isDot)
    self.props.dot = isDot
    return self
end

--- Set position
---@param position string "top-right" | "top-left" | "bottom-right" | "bottom-left"
---@return Badge self
function Badge:SetPosition(position)
    self.props.position = position
    return self
end

--- Set max count
---@param max number
---@return Badge self
function Badge:SetMax(max)
    self.props.max = max
    return self
end

--- Set pulse animation
---@param pulse boolean
---@return Badge self
function Badge:SetPulse(pulse)
    self.props.pulse = pulse
    if pulse then
        self.pulsePhase_ = 0
    end
    return self
end

--- Check if badge is visible (has content to show)
---@return boolean
function Badge:IsVisible()
    local content = self.props.content

    if self.props.dot then
        return true
    end

    if content == nil then
        return false
    end

    if type(content) == "number" then
        return content > 0 or self.props.showZero
    end

    return type(content) == "string" and #content > 0
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Badge:IsStateful()
    return self.props.pulse == true
end

-- ============================================================================
-- Static Helper: Create Badge with child
-- ============================================================================

--- Wrap a widget with a badge
---@param child Widget The widget to wrap
---@param content string|number|nil Badge content
---@param options table|nil Badge options
---@return Badge
function Badge.Wrap(child, content, options)
    options = options or {}
    options.content = content

    local badge = Badge:new(options)
    badge:AddChild(child)

    return badge
end

return Badge
