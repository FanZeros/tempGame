-- ============================================================================
-- Avatar Widget
-- UrhoX UI Library - Yoga + NanoVG
-- User avatar with image, initials, or icon fallback
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class AvatarProps : WidgetProps
---@field src? string Image source path
---@field name? string Name for generating initials
---@field initials? string Direct initials override
---@field size? string|number "xs" | "sm" | "md" | "lg" | "xl" | number (default: "md")
---@field shape? string "circle" | "rounded" | "square" (default: "circle")
---@field status? string "online" | "offline" | "away" | "busy"
---@field statusPosition? string "bottom-right" | "top-right" | "bottom-left" | "top-left"
---@field showBorder? boolean Show border ring
---@field borderColor? RGBAColor|string Custom border color
---@field backgroundColor? RGBAColor|string Custom background color
---@field shapeBackgroundColor? table Per-shape background colors { circle = color, rounded = color, square = color }
---@field shapeBorderColor? table Per-shape border colors { circle = color, rounded = color, square = color }
---@field sizeBackgroundColor? table Per-size background colors { sm = color, md = color, [40] = color }
---@field sizeBorderColor? table Per-size border colors { sm = color, md = color, [40] = color }

---@class Avatar : Widget
---@overload fun(props?: AvatarProps): Avatar
---@field props AvatarProps
---@field new fun(self, props?: AvatarProps): Avatar
local Avatar = Widget:Extend("Avatar")

-- Size presets
local SIZE_PRESETS = {
    xs = 24,
    sm = 32,
    md = 40,
    lg = 56,
    xl = 80,
}

-- Status colors
local STATUS_COLORS = {
    online = { 34, 197, 94, 255 },    -- Green
    offline = { 156, 163, 175, 255 }, -- Gray
    away = { 245, 158, 11, 255 },     -- Amber
    busy = { 239, 68, 68, 255 },      -- Red
}

-- Background colors for initials (based on name hash)
local AVATAR_COLORS = {
    { 239, 68, 68 },    -- Red
    { 249, 115, 22 },   -- Orange
    { 245, 158, 11 },   -- Amber
    { 34, 197, 94 },    -- Green
    { 20, 184, 166 },   -- Teal
    { 59, 130, 246 },   -- Blue
    { 99, 102, 241 },   -- Indigo
    { 168, 85, 247 },   -- Purple
    { 236, 72, 153 },   -- Pink
}

local function resolveMapValue(map, key)
    if type(map) ~= "table" then return nil end
    return map[key] or map[tostring(key)]
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props AvatarProps?
function Avatar:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Avatar")
    Style.ApplyDefaults(props, themeStyle)

    -- Default settings
    props.size = props.size or "md"
    props.shape = props.shape or "circle"
    props.statusPosition = props.statusPosition or "bottom-right"
    props.showBorder = props.showBorder or false

    -- Set size from preset or direct number
    local avatarSize = type(props.size) == "number" and props.size or (SIZE_PRESETS[props.size] or SIZE_PRESETS.md)
    props.width = props.width or avatarSize
    props.height = props.height or avatarSize

    -- State
    self.state = {
        hovered = false,
        imageLoaded = false,
        imageError = false,
    }

    -- Cached image handle
    self.imageHandle_ = nil

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Avatar:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    -- Calculate size (no scale needed - nvgScale handles it)
    local size = props.size
    if type(size) == "string" then
        size = SIZE_PRESETS[size] or SIZE_PRESETS.md
    end

    -- Position (centered in layout)
    local x = l.x + (l.w - size) / 2
    local y = l.y + (l.h - size) / 2

    -- Border radius based on shape
    local borderRadius
    if props.shape == "circle" then
        borderRadius = size / 2
    elseif props.shape == "rounded" then
        borderRadius = size * 0.2
    else -- square
        borderRadius = 0
    end

    -- Draw border ring (if enabled)
    if props.showBorder then
        local avatarBg = self:GetResolvedBackgroundColor(self:GetColorFromName(props.name or props.initials or "?"))
        local borderColor = self:GetResolvedBorderColor(Style.Darken(avatarBg, 0.3))
        local borderWidth = math.max(2, size * 0.05)

        nvgBeginPath(nvg)
        if props.shape == "circle" then
            nvgCircle(nvg, x + size / 2, y + size / 2, size / 2 + borderWidth)
        else
            nvgRoundedRect(nvg, x - borderWidth, y - borderWidth,
                size + borderWidth * 2, size + borderWidth * 2,
                borderRadius + borderWidth)
        end
        nvgFillColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgFill(nvg)
    end

    -- Determine what to render: image, initials, or fallback icon
    local hasImage = props.src and not state.imageError
    local hasInitials = props.initials or props.name

    if hasImage and state.imageLoaded and self.imageHandle_ then
        -- Render image
        self:RenderImage(nvg, x, y, size, borderRadius)
    elseif hasInitials then
        -- Render initials
        self:RenderInitials(nvg, x, y, size, borderRadius)
    else
        -- Render fallback icon
        self:RenderFallback(nvg, x, y, size, borderRadius)
    end

    -- Draw hover overlay
    if state.hovered and props.onClick then
        nvgBeginPath(nvg)
        if props.shape == "circle" then
            nvgCircle(nvg, x + size / 2, y + size / 2, size / 2)
        else
            nvgRoundedRect(nvg, x, y, size, size, borderRadius)
        end
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 30))
        nvgFill(nvg)
    end

    -- Draw status indicator
    if props.status then
        self:RenderStatus(nvg, x, y, size)
    end
end

--- Render image avatar
function Avatar:RenderImage(nvg, x, y, size, borderRadius)
    -- Create image pattern
    local imgPaint = nvgImagePattern(nvg, x, y, size, size, 0, self.imageHandle_, 1)

    nvgBeginPath(nvg)
    if self.props.shape == "circle" then
        nvgCircle(nvg, x + size / 2, y + size / 2, size / 2)
    else
        nvgRoundedRect(nvg, x, y, size, size, borderRadius)
    end
    nvgFillPaint(nvg, imgPaint)
    nvgFill(nvg)
end

--- Render initials avatar
function Avatar:RenderInitials(nvg, x, y, size, borderRadius)
    -- Get initials
    local initials = self.props.initials
    if not initials and self.props.name then
        initials = self:GenerateInitials(self.props.name)
    end
    initials = initials or "?"

    -- Get background color (based on name hash or custom)
    local bgColor = self:GetResolvedBackgroundColor(self:GetColorFromName(self.props.name or initials))

    -- Draw background
    nvgBeginPath(nvg)
    if self.props.shape == "circle" then
        nvgCircle(nvg, x + size / 2, y + size / 2, size / 2)
    else
        nvgRoundedRect(nvg, x, y, size, size, borderRadius)
    end
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    -- Draw initials text
    local fontFamily = Theme.FontFamily()
    local fontSize = size * 0.4
    local textColor = { 255, 255, 255, 255 }

    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, fontSize)
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4]))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgText(nvg, x + size / 2, y + size / 2, initials, nil)
end

--- Render fallback icon
function Avatar:RenderFallback(nvg, x, y, size, borderRadius)
    local bgColor = self:GetResolvedBackgroundColor(Theme.Color("surface"))

    -- Draw background
    nvgBeginPath(nvg)
    if self.props.shape == "circle" then
        nvgCircle(nvg, x + size / 2, y + size / 2, size / 2)
    else
        nvgRoundedRect(nvg, x, y, size, size, borderRadius)
    end
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    -- Draw user icon (simple silhouette)
    local iconColor = Theme.Color("textSecondary")
    local cx = x + size / 2
    local cy = y + size / 2
    local iconScale = size / 40  -- Normalized to 40px base

    -- Head
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy - 4 * iconScale, 6 * iconScale)
    nvgFillColor(nvg, nvgRGBA(iconColor[1], iconColor[2], iconColor[3], iconColor[4] or 255))
    nvgFill(nvg)

    -- Body
    nvgBeginPath(nvg)
    nvgEllipse(nvg, cx, cy + 10 * iconScale, 10 * iconScale, 8 * iconScale)
    nvgFillColor(nvg, nvgRGBA(iconColor[1], iconColor[2], iconColor[3], iconColor[4] or 255))
    nvgFill(nvg)
end

--- Render status indicator
function Avatar:RenderStatus(nvg, x, y, size)
    local status = self.props.status
    local statusColor = STATUS_COLORS[status] or STATUS_COLORS.offline
    local statusSize = math.max(8, size * 0.25)
    local statusPos = self.props.statusPosition

    -- Calculate status position
    local sx, sy
    local offset = statusSize * 0.2

    if statusPos == "bottom-right" then
        sx = x + size - statusSize / 2 - offset
        sy = y + size - statusSize / 2 - offset
    elseif statusPos == "top-right" then
        sx = x + size - statusSize / 2 - offset
        sy = y + statusSize / 2 + offset
    elseif statusPos == "bottom-left" then
        sx = x + statusSize / 2 + offset
        sy = y + size - statusSize / 2 - offset
    elseif statusPos == "top-left" then
        sx = x + statusSize / 2 + offset
        sy = y + statusSize / 2 + offset
    end

    -- Draw status border (background color)
    local borderWidth = math.max(2, statusSize * 0.2)
    nvgBeginPath(nvg)
    nvgCircle(nvg, sx, sy, statusSize / 2 + borderWidth)
    nvgFillColor(nvg, nvgRGBA(Theme.Color("background")[1], Theme.Color("background")[2], Theme.Color("background")[3], 255))
    nvgFill(nvg)

    -- Draw status indicator
    nvgBeginPath(nvg)
    nvgCircle(nvg, sx, sy, statusSize / 2)
    nvgFillColor(nvg, nvgRGBA(statusColor[1], statusColor[2], statusColor[3], statusColor[4]))
    nvgFill(nvg)
end

-- ============================================================================
-- Helper Methods
-- ============================================================================

function Avatar:GetResolvedBackgroundColor(fallback)
    local props = self.props
    return props.backgroundColor
        or resolveMapValue(props.shapeBackgroundColor, props.shape)
        or resolveMapValue(props.sizeBackgroundColor, props.size)
        or fallback
end

function Avatar:GetResolvedBorderColor(fallback)
    local props = self.props
    return props.borderColor
        or resolveMapValue(props.shapeBorderColor, props.shape)
        or resolveMapValue(props.sizeBorderColor, props.size)
        or fallback
end

--- Generate initials from name
---@param name string
---@return string
function Avatar:GenerateInitials(name)
    if not name or #name == 0 then
        return "?"
    end

    local parts = {}
    for part in string.gmatch(name, "%S+") do
        table.insert(parts, part)
    end

    if #parts >= 2 then
        -- First letter of first and last name
        return string.upper(string.sub(parts[1], 1, 1) .. string.sub(parts[#parts], 1, 1))
    else
        -- First two letters of single name
        return string.upper(string.sub(name, 1, math.min(2, #name)))
    end
end

--- Get consistent color based on name
---@param name string
---@return table
function Avatar:GetColorFromName(name)
    if not name or #name == 0 then
        return AVATAR_COLORS[1]
    end

    -- Simple hash based on character codes
    local hash = 0
    for i = 1, #name do
        hash = hash + string.byte(name, i)
    end

    local index = (hash % #AVATAR_COLORS) + 1
    return AVATAR_COLORS[index]
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Avatar:OnMouseEnter()
    if self.props.onClick then
        self:SetState({ hovered = true })
    end
end

function Avatar:OnMouseLeave()
    self:SetState({ hovered = false })
end

function Avatar:OnClick()
    if self.props.onClick then
        self.props.onClick(self)
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set image source
---@param src string|nil
---@return Avatar self
function Avatar:SetSrc(src)
    self.props.src = src
    self.state.imageLoaded = false
    self.state.imageError = false
    self.imageHandle_ = nil
    -- Note: Actual image loading would be handled by engine integration
    return self
end

--- Set name (for initials)
---@param name string
---@return Avatar self
function Avatar:SetName(name)
    self.props.name = name
    return self
end

--- Set initials directly
---@param initials string
---@return Avatar self
function Avatar:SetInitials(initials)
    self.props.initials = initials
    return self
end

--- Set size
---@param size string|number
---@return Avatar self
function Avatar:SetSize(size)
    self.props.size = size
    return self
end

--- Set shape
---@param shape string "circle" | "rounded" | "square"
---@return Avatar self
function Avatar:SetShape(shape)
    self.props.shape = shape
    return self
end

--- Set status
---@param status string|nil "online" | "offline" | "away" | "busy" | nil
---@return Avatar self
function Avatar:SetStatus(status)
    self.props.status = status
    return self
end

--- Set status position
---@param position string
---@return Avatar self
function Avatar:SetStatusPosition(position)
    self.props.statusPosition = position
    return self
end

--- Set border visibility
---@param show boolean
---@return Avatar self
function Avatar:SetShowBorder(show)
    self.props.showBorder = show
    return self
end

--- Set border color
--- Supports multiple formats: RGBA table, hex string, or CSS rgb/rgba
---@param color table|string RGBA table or color string (e.g., "#ff0000", "rgba(255,0,0,1)")
---@return Avatar self
function Avatar:SetBorderColor(color)
    self.props.borderColor = Style.ParseColor(color) or color
    return self
end

--- Set background color
--- Supports multiple formats: RGBA table, hex string, or CSS rgb/rgba
---@param color table|string RGBA table or color string (e.g., "#ff0000", "rgba(255,0,0,1)")
---@return Avatar self
function Avatar:SetBackgroundColor(color)
    self.props.backgroundColor = Style.ParseColor(color) or color
    return self
end

--- Get initials string
---@return string
function Avatar:GetInitials()
    if self.props.initials then
        return self.props.initials
    elseif self.props.name then
        return self:GenerateInitials(self.props.name)
    end
    return "?"
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Avatar:IsStateful()
    return true
end

-- ============================================================================
-- Static Helper: Avatar Group
-- ============================================================================

--- Create an avatar group (stacked avatars)
---@param avatars Avatar[] Array of avatars
---@param options table|nil { max, size, overlap }
---@return Widget
function Avatar.Group(avatars, options)
    local Panel = require("urhox-libs/UI/Widgets/Panel")

    options = options or {}
    local max = options.max or 5
    local size = options.size or "md"
    local overlap = options.overlap or 0.3

    local sizeNum = type(size) == "string" and (SIZE_PRESETS[size] or 40) or size
    local offsetX = sizeNum * (1 - overlap)

    local group = Panel:new({
        flexDirection = "row",
        alignItems = "center",
    })

    local count = math.min(#avatars, max)
    for i = 1, count do
        local avatar = avatars[i]
        avatar:SetSize(size)
        avatar:SetShowBorder(true)
        avatar.props.marginLeft = i == 1 and 0 or -offsetX
        group:AddChild(avatar)
    end

    -- Show remaining count
    if #avatars > max then
        local remaining = #avatars - max
        local countAvatar = Avatar:new({
            initials = "+" .. remaining,
            size = size,
            backgroundColor = Theme.Color("surface"),
            showBorder = true,
        })
        countAvatar.props.marginLeft = -offsetX
        group:AddChild(countAvatar)
    end

    return group
end

return Avatar
