-- ============================================================================
-- ColorPicker Widget
-- Color selection with HSV picker and presets
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class ColorPickerProps : WidgetProps
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field variant? string "outlined" | "filled" (default: "outlined")
---@field disabled? boolean Disable the picker
---@field showAlpha? boolean Show alpha channel slider
---@field showInput? boolean Show hex input (default: true)
---@field showPresets? boolean Show preset colors (default: true)
---@field presets? string[] Custom preset colors array
---@field value? table Initial value {r, g, b, a} or {h, s, v, a}
---@field color? string Initial hex color
---@field fontSize? number Custom font size
---@field pickerSize? number Color picker popup size
---@field swatchSize? number Preset swatch size
---@field fieldFontSize? number Font size (pt) for field text (default: fontSize from size preset)
---@field fieldIdleBorderColor? RGBAColor|string Field border color when closed
---@field fieldIdleBorderWidth? number Field border width when closed
---@field fieldOpenBorderColor? RGBAColor|string Field border color when popup is open
---@field fieldOpenBorderWidth? number Field border width when popup is open
---@field fieldTextColor? RGBAColor|string Field value text color
---@field iconColor? RGBAColor|string Field dropdown icon color
---@field showIcon? boolean Show dropdown icon (default: true)
---@field trailing? Widget|string Custom trailing content inside the field
---@field fieldSwatchRadius? number Border radius for the color swatch inside the field (default: borderRadius)
---@field fieldSwatchBorderWidth? number Border width for the color swatch inside the field (default: 1)
---@field fieldSwatchBorderColor? RGBAColor|string Border color for the color swatch inside the field
---@field sliderRadius? number Hue/Alpha slider track radius (default: 4)
---@field presetRadius? number Preset swatch radius (default: 4)
---@field popupBgColor? RGBAColor|string Popup panel background color (default: surface)
---@field popupBackgroundGradient? table Popup panel background gradient drawn over popupBgColor
---@field popupBoxShadow? table|false Popup panel shadow array; false disables the default shadow
---@field popupBorderColor? RGBAColor|string Popup panel border color
---@field popupBorderWidth? number Popup panel border width
---@field svPickerBorderColor? RGBAColor|string Saturation/value picker border color
---@field svPickerBorderWidth? number Saturation/value picker border width
---@field svCursorFillColor? RGBAColor|string|false Saturation/value cursor fill color; false disables fill
---@field svCursorBorderColor? RGBAColor|string Saturation/value cursor border color
---@field svCursorBorderWidth? number Saturation/value cursor border width
---@field svCursorSize? number Saturation/value cursor size (default: 16)
---@field sliderBorderColor? RGBAColor|string Hue/alpha slider border color
---@field sliderBorderWidth? number Hue/alpha slider border width
---@field presetBorderColor? RGBAColor|string Preset swatch border color
---@field presetBorderWidth? number Preset swatch border width
---@field presetHoverBorderColor? RGBAColor|string Preset swatch hover border color
---@field presetHoverBorderWidth? number Preset swatch hover border width
---@field onChange? fun(picker: ColorPicker, value: table) Value change callback
---@field onOpen? fun(picker: ColorPicker) Open callback
---@field onClose? fun(picker: ColorPicker) Close callback

---@class ColorPicker : Widget
---@overload fun(props?: ColorPickerProps): ColorPicker
---@field props ColorPickerProps
---@field new fun(self, props?: ColorPickerProps): ColorPicker
local ColorPicker = Widget:Extend("ColorPicker")

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { height = 28, fontSize = 12, padding = 8, swatchSize = 20, pickerSize = 180 },
    md = { height = 36, fontSize = 14, padding = 12, swatchSize = 28, pickerSize = 220 },
    lg = { height = 44, fontSize = 16, padding = 16, swatchSize = 36, pickerSize = 260 },
}

-- ============================================================================
-- Color utilities
-- ============================================================================

local function hsvToRgb(h, s, v)
    local r, g, b

    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    local mod = i % 6
    if mod == 0 then r, g, b = v, t, p
    elseif mod == 1 then r, g, b = q, v, p
    elseif mod == 2 then r, g, b = p, v, t
    elseif mod == 3 then r, g, b = p, q, v
    elseif mod == 4 then r, g, b = t, p, v
    elseif mod == 5 then r, g, b = v, p, q
    end

    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

local function rgbToHsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255

    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local h, s, v
    v = max

    local d = max - min
    s = max == 0 and 0 or d / max

    if max == min then
        h = 0
    else
        if max == r then
            h = (g - b) / d + (g < b and 6 or 0)
        elseif max == g then
            h = (b - r) / d + 2
        elseif max == b then
            h = (r - g) / d + 4
        end
        h = h / 6
    end

    return h, s, v
end

local function rgbToHex(r, g, b, a)
    if a and a < 255 then
        return string.format("#%02X%02X%02X%02X", r, g, b, a)
    end
    return string.format("#%02X%02X%02X", r, g, b)
end

local function hexToRgb(hex)
    hex = hex:gsub("#", "")
    if #hex == 6 then
        return tonumber(hex:sub(1,2), 16),
               tonumber(hex:sub(3,4), 16),
               tonumber(hex:sub(5,6), 16),
               255
    elseif #hex == 8 then
        return tonumber(hex:sub(1,2), 16),
               tonumber(hex:sub(3,4), 16),
               tonumber(hex:sub(5,6), 16),
               tonumber(hex:sub(7,8), 16)
    end
    return 0, 0, 0, 255
end

local function clampRadius(radius, w, h)
    radius = tonumber(radius) or 0
    return math.max(0, math.min(radius, math.max(0, math.min(w, h) * 0.5)))
end

local function roundedRectVerticalInset(localX, w, h, radius)
    local r = clampRadius(radius, w, h)
    if r <= 0 then return 0 end

    local dx = 0
    if localX < r then
        dx = r - localX
    elseif localX > w - r then
        dx = localX - (w - r)
    else
        return 0
    end

    return r - math.sqrt(math.max(0, r * r - dx * dx))
end

local function drawHueGradientRect(nvg, x, y, h, localX0, localX1, totalW)
    if localX1 <= localX0 then return end

    local r1, g1, b1 = hsvToRgb(localX0 / totalW, 1, 1)
    local r2, g2, b2 = hsvToRgb(localX1 / totalW, 1, 1)
    local grad = nvgLinearGradient(nvg, x + localX0, y, x + localX1, y,
        nvgRGBA(r1, g1, b1, 255),
        nvgRGBA(r2, g2, b2, 255))

    nvgBeginPath(nvg)
    nvgRect(nvg, x + localX0, y, localX1 - localX0, h)
    nvgFillPaint(nvg, grad)
    nvgFill(nvg)
end

local function drawHueEdgeStrip(nvg, x, y, w, h, radius, localX, stripW)
    local midX = localX + stripW * 0.5
    local inset = roundedRectVerticalInset(midX, w, h, radius)
    local stripH = h - inset * 2
    if stripH <= 0 then return end

    local r, g, b = hsvToRgb(midX / w, 1, 1)
    nvgBeginPath(nvg)
    nvgRect(nvg, x + localX, y + inset, stripW, stripH)
    nvgFillColor(nvg, nvgRGBA(r, g, b, 255))
    nvgFill(nvg)
end

local function drawCheckerRect(nvg, x, y, w, h, checkSize, originX, originY)
    if w <= 0 or h <= 0 then return end

    local cy = 0
    while cy < h do
        local cellH = math.min(checkSize, h - cy)
        local cx = 0
        while cx < w do
            local cellW = math.min(checkSize, w - cx)
            local localX = x - originX + cx
            local localY = y - originY + cy
            local isLight = (math.floor(localX / checkSize) + math.floor(localY / checkSize)) % 2 == 0
            nvgBeginPath(nvg)
            nvgRect(nvg, x + cx, y + cy, cellW, cellH)
            nvgFillColor(nvg, isLight and nvgRGBA(255, 255, 255, 255) or nvgRGBA(200, 200, 200, 255))
            nvgFill(nvg)
            cx = cx + checkSize
        end
        cy = cy + checkSize
    end
end

local function drawCheckerEdgeStrip(nvg, x, y, w, h, radius, localX, stripW, checkSize)
    local midX = localX + stripW * 0.5
    local inset = roundedRectVerticalInset(midX, w, h, radius)
    local y0 = inset
    local y1 = h - inset
    if y1 <= y0 then return end

    local cy = math.floor(y0 / checkSize) * checkSize
    while cy < y1 do
        local segY0 = math.max(y0, cy)
        local segY1 = math.min(y1, cy + checkSize)
        local isLight = (math.floor(localX / checkSize) + math.floor(cy / checkSize)) % 2 == 0
        nvgBeginPath(nvg)
        nvgRect(nvg, x + localX, y + segY0, stripW, segY1 - segY0)
        nvgFillColor(nvg, isLight and nvgRGBA(255, 255, 255, 255) or nvgRGBA(200, 200, 200, 255))
        nvgFill(nvg)
        cy = cy + checkSize
    end
end

-- Default preset colors
local DEFAULT_PRESETS = {
    -- Row 1: Reds/Pinks
    "#F44336", "#E91E63", "#9C27B0", "#673AB7",
    -- Row 2: Blues/Cyans
    "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4",
    -- Row 3: Greens/Limes
    "#009688", "#4CAF50", "#8BC34A", "#CDDC39",
    -- Row 4: Yellows/Oranges
    "#FFEB3B", "#FFC107", "#FF9800", "#FF5722",
    -- Row 5: Grays
    "#795548", "#9E9E9E", "#607D8B", "#000000",
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props ColorPickerProps?
function ColorPicker:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("ColorPicker")
    Style.ApplyDefaults(props, themeStyle)

    -- ColorPicker props
    self.size_ = props.size or "md"
    self.variant_ = props.variant or "outlined"  -- outlined, filled
    self.disabled_ = props.disabled or false
    self.showAlpha_ = props.showAlpha or false
    self.showInput_ = props.showInput ~= false  -- default true
    self.showPresets_ = props.showPresets ~= false  -- default true
    self.presets_ = props.presets or DEFAULT_PRESETS

    -- Initial color (HSV internally)
    self.hue_ = 0
    self.saturation_ = 1
    self.value_ = 1
    self.alpha_ = 255

    if props.value then
        self:SetValue(props.value)
    elseif props.color then
        self:SetHex(props.color)
    end

    -- Colors
    self.primaryColor_ = props.primaryColor or Theme.Color("primary")

    -- UI state
    self.isOpen_ = false
    self.dragging_ = nil  -- "sv", "hue", "alpha"
    self.hoverPreset_ = nil

    -- Callbacks
    self.onChange_ = props.onChange
    self.onOpen_ = props.onOpen
    self.onClose_ = props.onClose

    -- Custom overlay queue function (for Inspector panel rendering order)
    self.queueOverlay_ = props.queueOverlay

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.fontSize_ = props.fontSize or Theme.FontSize(sizePreset.fontSize)
    self.padding_ = props.padding or sizePreset.padding
    self.pickerSize_ = props.pickerSize or sizePreset.pickerSize
    self.swatchSize_ = props.swatchSize or sizePreset.swatchSize
    self.inputHeight_ = props.height or sizePreset.height

    -- Popup dimensions
    self.popupBorderRadius_ = props.popupBorderRadius or themeStyle.borderRadius or 8
    self.sliderHeight_ = 16
    self.sliderGap_ = 12
    self.presetSize_ = 24
    self.presetGap_ = 4

    props.width = props.width or 160
    props.height = self.inputHeight_

    Widget.Init(self, props)
end

-- ============================================================================
-- Color Management
-- ============================================================================

function ColorPicker:GetValue()
    local r, g, b = hsvToRgb(self.hue_, self.saturation_, self.value_)
    return {
        r = r, g = g, b = b, a = self.alpha_,
        h = self.hue_, s = self.saturation_, v = self.value_,
        hex = rgbToHex(r, g, b, self.showAlpha_ and self.alpha_ or nil),
    }
end

function ColorPicker:SetValue(value)
    if value.h ~= nil then
        self.hue_ = value.h
        self.saturation_ = value.s
        self.value_ = value.v
        self.alpha_ = value.a or 255
    elseif value.r ~= nil then
        self.hue_, self.saturation_, self.value_ = rgbToHsv(value.r, value.g, value.b)
        self.alpha_ = value.a or 255
    end
end

function ColorPicker:GetRGB()
    local r, g, b = hsvToRgb(self.hue_, self.saturation_, self.value_)
    return r, g, b, self.alpha_
end

function ColorPicker:SetRGB(r, g, b, a)
    self.hue_, self.saturation_, self.value_ = rgbToHsv(r, g, b)
    self.alpha_ = a or 255
    self:NotifyChange()
end

function ColorPicker:GetHex()
    local r, g, b = hsvToRgb(self.hue_, self.saturation_, self.value_)
    return rgbToHex(r, g, b, self.showAlpha_ and self.alpha_ or nil)
end

function ColorPicker:SetHex(hex)
    local r, g, b, a = hexToRgb(hex)
    self.hue_, self.saturation_, self.value_ = rgbToHsv(r, g, b)
    self.alpha_ = a
end

function ColorPicker:GetNvgColor()
    local r, g, b = hsvToRgb(self.hue_, self.saturation_, self.value_)
    return nvgRGBA(r, g, b, self.alpha_)
end

function ColorPicker:NotifyChange()
    local value = self:GetValue()
    self:DispatchEvent("change", self, value)
    if self.onChange_ then
        self.onChange_(self, value)
    end
end

-- ============================================================================
-- Popup Control
-- ============================================================================

function ColorPicker:Open()
    if self.disabled_ then return end
    self.isOpen_ = true
    UI.PushOverlay(self)
    self:DispatchEvent("open", self)
    if self.onOpen_ then self.onOpen_(self) end
end

function ColorPicker:Close()
    self.isOpen_ = false
    self.dragging_ = nil
    UI.PopOverlay(self)
    self:DispatchEvent("close", self)
    if self.onClose_ then self.onClose_(self) end
end

function ColorPicker:Toggle()
    if self.isOpen_ then
        self:Close()
    else
        self:Open()
    end
end

-- ============================================================================
-- Render
-- ============================================================================

function ColorPicker:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()

    -- Store positions for hit testing (use HitTest coords for consistency with overlay)
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    self.inputBounds_ = { x = hitTest.x, y = hitTest.y, w = hitTest.w, h = hitTest.h }

    local fieldBg = self.props.fieldBgColor or Theme.Color("surface")
    local bgColor = nvgRGBA(fieldBg[1], fieldBg[2], fieldBg[3], fieldBg[4] or 255)
    local borderColor, borderWidth
    local hasIdleBorderOverride = self.props.fieldIdleBorderColor ~= nil
        or self.props.fieldIdleBorderWidth ~= nil
        or self.props.fieldBorderColor ~= nil

    if self.isOpen_ then
        local openBorder = self.props.fieldOpenBorderColor or self.primaryColor_
        borderColor = nvgRGBA(openBorder[1], openBorder[2], openBorder[3], openBorder[4] or 255)
        borderWidth = self.props.fieldOpenBorderWidth or 2
    else
        local fieldBorder = self.props.fieldIdleBorderColor or self.props.fieldBorderColor or Theme.Color("border")
        borderColor = nvgRGBA(fieldBorder[1], fieldBorder[2], fieldBorder[3], fieldBorder[4] or 255)
        borderWidth = self.props.fieldIdleBorderWidth
        if borderWidth == nil then borderWidth = 1 end
    end

    if self.disabled_ then
        borderColor = Theme.NvgColor("disabledBorder")
        bgColor = Theme.NvgColor("disabled")
        borderWidth = self.props.fieldIdleBorderWidth or 1
    end

    local fieldRadius = self.props.fieldBorderRadius or Theme.Radius("sm")
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, fieldRadius)

    if self.variant_ == "filled" and not self.props.fieldBgColor then
        nvgFillColor(nvg, Theme.NvgColor("surfaceAlt"))
        nvgFill(nvg)
        if borderWidth > 0 and (self.isOpen_ or hasIdleBorderOverride) then
            nvgStrokeColor(nvg, borderColor)
            nvgStrokeWidth(nvg, borderWidth)
            nvgStroke(nvg)
        end
    elseif self.variant_ == "outlined" or self.props.fieldBgColor then
        nvgFillColor(nvg, bgColor)
        nvgFill(nvg)
        if borderWidth > 0 then
            nvgStrokeColor(nvg, borderColor)
            nvgStrokeWidth(nvg, borderWidth)
            nvgStroke(nvg)
        end
    else
        if borderWidth > 0 then
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x, y + h)
            nvgLineTo(nvg, x + w, y + h)
            nvgStrokeColor(nvg, borderColor)
            nvgStrokeWidth(nvg, borderWidth)
            nvgStroke(nvg)
        end
    end

    -- Draw color swatch
    local swatchX = x + self.padding_
    local swatchY = y + (h - self.swatchSize_) / 2
    local swatchW = self.swatchSize_
    local swatchH = self.swatchSize_

    if self.showAlpha_ and self.alpha_ < 255 then
        local checkSize = 4
        for cy = 0, swatchH - 1, checkSize do
            for cx = 0, swatchW - 1, checkSize do
                local isLight = ((cx / checkSize) + (cy / checkSize)) % 2 == 0
                nvgBeginPath(nvg)
                nvgRect(nvg, swatchX + cx, swatchY + cy, checkSize, checkSize)
                nvgFillColor(nvg, isLight and nvgRGBA(255, 255, 255, 255) or nvgRGBA(200, 200, 200, 255))
                nvgFill(nvg)
            end
        end
    end

    nvgBeginPath(nvg)
    local fieldSwatchRadius = self.props.fieldSwatchRadius
        or (self.props.borderRadius ~= nil and self.props.borderRadius or 4)
    nvgRoundedRect(nvg, swatchX, swatchY, swatchW, swatchH, fieldSwatchRadius)
    nvgFillColor(nvg, self:GetNvgColor())
    nvgFill(nvg)
    local fieldSwatchBorderWidth = self.props.fieldSwatchBorderWidth
    if fieldSwatchBorderWidth == nil then fieldSwatchBorderWidth = 1 end
    if fieldSwatchBorderWidth > 0 then
        local fieldSwatchBorderColor = self.props.fieldSwatchBorderColor or Theme.Color("border")
        nvgStrokeColor(nvg, nvgRGBA(fieldSwatchBorderColor[1], fieldSwatchBorderColor[2], fieldSwatchBorderColor[3], fieldSwatchBorderColor[4] or 255))
        nvgStrokeWidth(nvg, fieldSwatchBorderWidth)
        nvgStroke(nvg)
    end

    local hexText = self:GetHex()
    local textX = swatchX + swatchW + 8
    local fieldFontSize = self.props.fieldFontSize and Theme.FontSize(self.props.fieldFontSize) or self.fontSize_
    local fieldFontFace = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    local fieldTextColor = self.disabled_ and Theme.Color("textDisabled") or (self.props.fieldTextColor or Theme.Color("text"))
    nvgFontSize(nvg, fieldFontSize)
    nvgFontFace(nvg, fieldFontFace)
    nvgFillColor(nvg, nvgRGBA(fieldTextColor[1], fieldTextColor[2], fieldTextColor[3], fieldTextColor[4] or 255))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, textX, y + h / 2, hexText)

    local iconColor = self.disabled_ and Theme.Color("textDisabled") or (self.props.iconColor or Theme.Color("textSecondary"))
    local iconNvgColor = nvgRGBA(iconColor[1], iconColor[2], iconColor[3], iconColor[4] or 255)
    local trailing = self.props.trailing
    if trailing ~= nil then
        local trailingWidth = self.props.trailingWidth or 24
        local trailingX = x + w - self.padding_ - trailingWidth
        if type(trailing) == "string" then
            nvgFontSize(nvg, self.fontSize_)
            nvgFontFace(nvg, fieldFontFace)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, iconNvgColor)
            nvgText(nvg, trailingX + trailingWidth / 2, y + h / 2, trailing)
        elseif type(trailing) == "table" and trailing.Render then
            trailing.renderOffsetX_ = trailingX
            local trailingLayout = trailing:GetLayout()
            local trailingHeight = trailingLayout and trailingLayout.h or h
            trailing.renderOffsetY_ = y + (h - trailingHeight) / 2
            trailing.renderWidth_ = trailingWidth
            trailing:Render(nvg)
        end
    elseif self.props.showIcon ~= false then
        local arrowX = x + w - self.padding_
        local arrowY = y + h / 2
        nvgBeginPath(nvg)
        if self.isOpen_ then
            nvgMoveTo(nvg, arrowX - 4, arrowY + 2)
            nvgLineTo(nvg, arrowX, arrowY - 2)
            nvgLineTo(nvg, arrowX + 4, arrowY + 2)
        else
            nvgMoveTo(nvg, arrowX - 4, arrowY - 2)
            nvgLineTo(nvg, arrowX, arrowY + 2)
            nvgLineTo(nvg, arrowX + 4, arrowY - 2)
        end
        nvgStrokeColor(nvg, iconNvgColor)
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end

    -- Queue popup to render as overlay (on top of everything)
    if self.isOpen_ then
        local queueFn = self.queueOverlay_ or UI.QueueOverlay
        queueFn(function(nvg_)
            self:RenderPopup(nvg_)
        end)
    end
end

function ColorPicker:RenderPopup(nvg)
    -- Use GetAbsoluteLayoutForHitTest because overlay renders outside ScrollView's nvgTranslate
    local l = self:GetAbsoluteLayoutForHitTest()
    local px = l.x
    local py = l.y + l.h + 4  -- Position below input field

    local theme = Theme.GetTheme()

    -- Dimensions (no scale needed - nvgScale handles it)
    local pickerSize = self.pickerSize_
    local sliderHeight = self.sliderHeight_
    local sliderGap = self.sliderGap_
    local presetSize = self.presetSize_
    local presetGap = self.presetGap_
    local contentPadding = 16
    local borderRadius = self.popupBorderRadius_

    -- Calculate popup size (must match contentY layout exactly)
    local popW = pickerSize + contentPadding * 2
    -- Start with top padding (contentY starts at py + contentPadding)
    local popH = contentPadding
    -- SV picker + gap (contentY += pickerSize + sliderGap)
    popH = popH + pickerSize + sliderGap
    -- Hue slider + gap (contentY += sliderHeight + sliderGap, always adds gap)
    popH = popH + sliderHeight + sliderGap

    if self.showAlpha_ then
        -- Alpha slider + gap (contentY += sliderHeight + sliderGap)
        popH = popH + sliderHeight + sliderGap
    end

    if self.showPresets_ then
        local presetsPerRow = math.floor((popW - contentPadding) / (presetSize + presetGap))
        local presetRows = math.ceil(#self.presets_ / presetsPerRow)
        -- contentY += presetRows * (presetSize + presetGap) + 8
        popH = popH + presetRows * (presetSize + presetGap) + 8
    end

    if self.showInput_ then
        -- Get actual font height using nvgTextMetrics
        nvgFontSize(nvg, self.fontSize_)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        local ascender, descender, lineh = nvgTextMetrics(nvg)
        -- HexInput needs: lineh for text + padding
        local hexInputHeight = lineh + self.padding_
        popH = popH + hexInputHeight
        -- Store for RenderHexInput to use
        self.hexInputHeight_ = hexInputHeight
    end

    -- Bottom padding
    popH = popH + 8

    self.popupBounds_ = { x = px, y = py, w = popW, h = popH }
    local popupGeom = self:GetShapeGeometry({ x = px, y = py, w = popW, h = popH }, nil, borderRadius)

    -- Shadow
    local popupBoxShadow = self.props.popupBoxShadow
    if popupBoxShadow == false then
        -- Explicitly disabled.
    elseif popupBoxShadow then
        self:RenderBoxShadows(nvg, popupGeom, popupBoxShadow)
    else
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px + 2, py + 2, popW, popH, borderRadius)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 40))
        nvgFill(nvg)
    end

    -- Background
    local popupBg = self.props.popupBgColor or Theme.Color("surface")
    self:CreateShapePath(nvg, popupGeom)
    nvgFillColor(nvg, nvgRGBA(popupBg[1], popupBg[2], popupBg[3], popupBg[4] or 255))
    nvgFill(nvg)
    if self.props.popupBackgroundGradient then
        self:RenderGradientBackground(nvg, popupGeom, self.props.popupBackgroundGradient)
    end
    local popupBorderWidth = self.props.popupBorderWidth
    if popupBorderWidth == nil then popupBorderWidth = 1 end
    if popupBorderWidth > 0 then
        local popupBorderColor = self.props.popupBorderColor or Theme.Color("border")
        self:CreateShapePath(nvg, popupGeom)
        nvgStrokeColor(nvg, nvgRGBA(popupBorderColor[1], popupBorderColor[2], popupBorderColor[3], popupBorderColor[4] or 255))
        nvgStrokeWidth(nvg, popupBorderWidth)
        nvgStroke(nvg)
    end

    local contentX = px + contentPadding
    local contentY = py + contentPadding

    -- Saturation/Value picker
    self:RenderSVPicker(nvg, contentX, contentY, pickerSize)
    contentY = contentY + pickerSize + sliderGap

    -- Hue slider
    self:RenderHueSlider(nvg, contentX, contentY, pickerSize, sliderHeight)
    contentY = contentY + sliderHeight + sliderGap

    -- Alpha slider (optional)
    if self.showAlpha_ then
        self:RenderAlphaSlider(nvg, contentX, contentY, pickerSize, sliderHeight)
        contentY = contentY + sliderHeight + sliderGap
    end

    -- Presets (optional)
    if self.showPresets_ then
        self:RenderPresets(nvg, contentX, contentY, pickerSize, presetSize, presetGap)
        local presetsPerRow = math.floor(pickerSize / (presetSize + presetGap))
        local presetRows = math.ceil(#self.presets_ / presetsPerRow)
        contentY = contentY + presetRows * (presetSize + presetGap) + 8
    end

    -- Hex input display (optional)
    if self.showInput_ then
        self:RenderHexInput(nvg, contentX, contentY, popW - contentPadding * 2)
    end
end

function ColorPicker:RenderSVPicker(nvg, x, y, size)
    self.svBounds_ = { x = x, y = y, w = size, h = size }

    -- Draw saturation gradient (white to hue color)
    local hueR, hueG, hueB = hsvToRgb(self.hue_, 1, 1)

    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, size, size)

    -- Horizontal gradient: white to hue color
    local gradH = nvgLinearGradient(nvg, x, y, x + size, y,
        nvgRGBA(255, 255, 255, 255),
        nvgRGBA(hueR, hueG, hueB, 255))
    nvgFillPaint(nvg, gradH)
    nvgFill(nvg)

    -- Vertical gradient: transparent to black
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, size, size)
    local gradV = nvgLinearGradient(nvg, x, y, x, y + size,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 0, 0, 255))
    nvgFillPaint(nvg, gradV)
    nvgFill(nvg)

    -- Border
    local svPickerBorderWidth = self.props.svPickerBorderWidth
    if svPickerBorderWidth == nil then svPickerBorderWidth = 1 end
    if svPickerBorderWidth > 0 then
        local svPickerBorderColor = self.props.svPickerBorderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, size, size)
        nvgStrokeColor(nvg, nvgRGBA(svPickerBorderColor[1], svPickerBorderColor[2], svPickerBorderColor[3], svPickerBorderColor[4] or 255))
        nvgStrokeWidth(nvg, svPickerBorderWidth)
        nvgStroke(nvg)
    end

    -- Draw cursor
    local cursorX = x + self.saturation_ * size
    local cursorY = y + (1 - self.value_) * size
    local svCursorSize = self.props.svCursorSize or 16
    local svCursorHalf = svCursorSize / 2
    local svCursorRadius = self.props.svCursorSize and svCursorHalf
        or (self.props.borderRadius ~= nil and self.props.borderRadius or 8)
    local customCursor = self.props.svCursorFillColor ~= nil
        or self.props.svCursorBorderColor ~= nil
        or self.props.svCursorBorderWidth ~= nil

    if customCursor then
        local cursorFill = self.props.svCursorFillColor
        if cursorFill and cursorFill ~= false then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cursorX - svCursorHalf, cursorY - svCursorHalf, svCursorSize, svCursorSize, svCursorRadius)
            nvgFillColor(nvg, nvgRGBA(cursorFill[1], cursorFill[2], cursorFill[3], cursorFill[4] or 255))
            nvgFill(nvg)
        end
        local cursorBorderWidth = self.props.svCursorBorderWidth
        if cursorBorderWidth == nil then cursorBorderWidth = 1 end
        if cursorBorderWidth > 0 then
            local cursorBorderColor = self.props.svCursorBorderColor or Theme.Color("border")
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cursorX - svCursorHalf, cursorY - svCursorHalf, svCursorSize, svCursorSize, svCursorRadius)
            nvgStrokeColor(nvg, nvgRGBA(cursorBorderColor[1], cursorBorderColor[2], cursorBorderColor[3], cursorBorderColor[4] or 255))
            nvgStrokeWidth(nvg, cursorBorderWidth)
            nvgStroke(nvg)
        end
    else
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cursorX - svCursorHalf, cursorY - svCursorHalf, svCursorSize, svCursorSize, svCursorRadius)
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)

        local innerInset = math.min(2, svCursorHalf)
        local innerSize = math.max(0, svCursorSize - innerInset * 2)
        if innerSize > 0 then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cursorX - innerSize / 2, cursorY - innerSize / 2, innerSize, innerSize, math.max(0, svCursorRadius - innerInset))
            nvgStrokeColor(nvg, nvgRGBA(0, 0, 0, 255))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end
    end
end

function ColorPicker:RenderHueSlider(nvg, x, y, w, h)
    self.hueBounds_ = { x = x, y = y, w = w, h = h }
    local borderRadius = self.props.sliderRadius or self.props.borderRadius or 4
    local radius = clampRadius(borderRadius, w, h)

    -- Draw hue gradient inside the rounded track shape. Drawing full-height
    -- rectangular segments only leaks at rounded end caps, so only caps use strips.
    local centerStart = radius
    local centerEnd = w - radius
    if centerEnd > centerStart then
        local segments = 6
        for i = 0, segments - 1 do
            local segStart = i * w / segments
            local segEnd = (i + 1) * w / segments
            drawHueGradientRect(nvg, x, y, h,
                math.max(segStart, centerStart),
                math.min(segEnd, centerEnd),
                w)
        end
    end

    local edgeStep = 1
    local leftEnd = math.min(radius, w)
    local lx = 0
    while lx < leftEnd do
        local stripW = math.min(edgeStep, leftEnd - lx)
        drawHueEdgeStrip(nvg, x, y, w, h, radius, lx, stripW)
        lx = lx + stripW
    end

    lx = math.max(w - radius, leftEnd)
    while lx < w do
        local stripW = math.min(edgeStep, w - lx)
        drawHueEdgeStrip(nvg, x, y, w, h, radius, lx, stripW)
        lx = lx + stripW
    end

    -- Border
    local sliderBorderWidth = self.props.sliderBorderWidth
    if sliderBorderWidth == nil then sliderBorderWidth = 1 end
    if sliderBorderWidth > 0 then
        local sliderBorderColor = self.props.sliderBorderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, borderRadius)
        nvgStrokeColor(nvg, nvgRGBA(sliderBorderColor[1], sliderBorderColor[2], sliderBorderColor[3], sliderBorderColor[4] or 255))
        nvgStrokeWidth(nvg, sliderBorderWidth)
        nvgStroke(nvg)
    end
    -- Draw cursor
    local cursorX = x + self.hue_ * w
    local cursorW = self.props.cursorWidth or 8
    local cursorPad = 2
    local cursorRadius = self.props.cursorRadius or 2
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, cursorX - cursorW / 2, y - cursorPad, cursorW, h + cursorPad * 2, cursorRadius)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgFill(nvg)
    local cursorBorder = self.props.cursorBorderColor or {0, 0, 0, 128}
    nvgStrokeColor(nvg, nvgRGBA(cursorBorder[1], cursorBorder[2], cursorBorder[3], cursorBorder[4] or 255))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
end

function ColorPicker:RenderAlphaSlider(nvg, x, y, w, h)
    self.alphaBounds_ = { x = x, y = y, w = w, h = h }
    local borderRadius = self.props.sliderRadius or self.props.borderRadius or 4
    local radius = clampRadius(borderRadius, w, h)

    -- Checkerboard background inside the rounded track shape.
    local checkSize = 4
    local centerW = w - radius * 2
    if centerW > 0 then
        drawCheckerRect(nvg, x + radius, y, centerW, h, checkSize, x, y)
    end

    local edgeStep = 1
    local leftEnd = math.min(radius, w)
    local lx = 0
    while lx < leftEnd do
        local stripW = math.min(edgeStep, leftEnd - lx)
        drawCheckerEdgeStrip(nvg, x, y, w, h, radius, lx, stripW, checkSize)
        lx = lx + stripW
    end

    lx = math.max(w - radius, leftEnd)
    while lx < w do
        local stripW = math.min(edgeStep, w - lx)
        drawCheckerEdgeStrip(nvg, x, y, w, h, radius, lx, stripW, checkSize)
        lx = lx + stripW
    end

    -- Alpha gradient
    local r, g, b = hsvToRgb(self.hue_, self.saturation_, self.value_)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, borderRadius)
    local grad = nvgLinearGradient(nvg, x, y, x + w, y,
        nvgRGBA(r, g, b, 0),
        nvgRGBA(r, g, b, 255))
    nvgFillPaint(nvg, grad)
    nvgFill(nvg)

    -- Border
    local sliderBorderWidth = self.props.sliderBorderWidth
    if sliderBorderWidth == nil then sliderBorderWidth = 1 end
    if sliderBorderWidth > 0 then
        local sliderBorderColor = self.props.sliderBorderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, borderRadius)
        nvgStrokeColor(nvg, nvgRGBA(sliderBorderColor[1], sliderBorderColor[2], sliderBorderColor[3], sliderBorderColor[4] or 255))
        nvgStrokeWidth(nvg, sliderBorderWidth)
        nvgStroke(nvg)
    end
    -- Draw cursor
    local cursorX = x + (self.alpha_ / 255) * w
    local cursorW = self.props.cursorWidth or 8
    local cursorPad = 2
    local alphaCursorRadius = self.props.cursorRadius or 2
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, cursorX - cursorW / 2, y - cursorPad, cursorW, h + cursorPad * 2, alphaCursorRadius)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    nvgFill(nvg)
    local cursorBorder = self.props.cursorBorderColor or {0, 0, 0, 128}
    nvgStrokeColor(nvg, nvgRGBA(cursorBorder[1], cursorBorder[2], cursorBorder[3], cursorBorder[4] or 255))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
end

function ColorPicker:RenderPresets(nvg, x, y, pickerSize, presetSize, presetGap)
    local presetsPerRow = math.floor(pickerSize / (presetSize + presetGap))
    local borderRadius = self.props.presetRadius or self.props.borderRadius or 4

    self.presetBounds_ = {}

    for i, preset in ipairs(self.presets_) do
        local row = math.floor((i - 1) / presetsPerRow)
        local col = (i - 1) % presetsPerRow

        local px = x + col * (presetSize + presetGap)
        local py = y + row * (presetSize + presetGap)

        self.presetBounds_[i] = { x = px, y = py, w = presetSize, h = presetSize }

        local r, g, b = hexToRgb(preset)

        -- Draw preset swatch
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px, py, presetSize, presetSize, borderRadius)
        nvgFillColor(nvg, nvgRGBA(r, g, b, 255))
        nvgFill(nvg)

        -- Hover effect
        if self.hoverPreset_ == i then
            local presetHoverBorderColor = self.props.presetHoverBorderColor or Theme.Color("primary")
            local presetHoverBorderWidth = self.props.presetHoverBorderWidth
            if presetHoverBorderWidth == nil then presetHoverBorderWidth = 2 end
            if presetHoverBorderWidth > 0 then
                nvgStrokeColor(nvg, nvgRGBA(presetHoverBorderColor[1], presetHoverBorderColor[2], presetHoverBorderColor[3], presetHoverBorderColor[4] or 255))
                nvgStrokeWidth(nvg, presetHoverBorderWidth)
                nvgStroke(nvg)
            end
        else
            local presetBorderColor = self.props.presetBorderColor or Theme.Color("border")
            local presetBorderWidth = self.props.presetBorderWidth
            if presetBorderWidth == nil then presetBorderWidth = 1 end
            if presetBorderWidth > 0 then
                nvgStrokeColor(nvg, nvgRGBA(presetBorderColor[1], presetBorderColor[2], presetBorderColor[3], presetBorderColor[4] or 255))
                nvgStrokeWidth(nvg, presetBorderWidth)
                nvgStroke(nvg)
            end
        end
    end
end

function ColorPicker:RenderHexInput(nvg, x, y, w)
    local theme = Theme.GetTheme()

    -- Use the pre-calculated height from RenderPopup
    local allocatedHeight = self.hexInputHeight_ or (self.fontSize_ * 1.5 + self.padding_)
    local textY = y + allocatedHeight / 2

    -- Label
    nvgFontSize(nvg, self.fontSize_ * 0.85)
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
    nvgText(nvg, x, textY, "HEX:")

    -- Value
    nvgFontSize(nvg, self.fontSize_)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgText(nvg, x + 40, textY, self:GetHex())
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function ColorPicker:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function ColorPicker:HitTest(x, y)
    -- Use GetAbsoluteLayoutForHitTest for proper scroll offset handling
    local l = self:GetAbsoluteLayoutForHitTest()

    -- Check input area
    if x >= l.x and x <= l.x + l.w and y >= l.y and y <= l.y + l.h then
        return true
    end

    -- When open, capture ALL clicks (for closing on click outside)
    if self.isOpen_ then
        return true
    end

    return false
end

function ColorPicker:OnPointerMove(event)
    if not event then return end

    -- Use event coords directly (all bounds are in HitTest coords)
    local px = event.x
    local py = event.y

    -- Handle dragging
    if self.dragging_ then
        if self.dragging_ == "sv" then
            local s = math.max(0, math.min(1, (px - self.svBounds_.x) / self.svBounds_.w))
            local v = math.max(0, math.min(1, 1 - (py - self.svBounds_.y) / self.svBounds_.h))
            self.saturation_ = s
            self.value_ = v
            self:NotifyChange()
        elseif self.dragging_ == "hue" then
            local h = math.max(0, math.min(1, (px - self.hueBounds_.x) / self.hueBounds_.w))
            self.hue_ = h
            self:NotifyChange()
        elseif self.dragging_ == "alpha" then
            local a = math.max(0, math.min(1, (px - self.alphaBounds_.x) / self.alphaBounds_.w))
            self.alpha_ = math.floor(a * 255)
            self:NotifyChange()
        end
        return
    end

    -- Hover detection for presets
    self.hoverPreset_ = nil
    if self.presetBounds_ then
        for i, bounds in ipairs(self.presetBounds_) do
            if self:PointInBounds(px, py, bounds) then
                self.hoverPreset_ = i
                break
            end
        end
    end
end

function ColorPicker:OnPointerLeave(event)
    self.hoverPreset_ = nil
end

function ColorPicker:OnPointerDown(event)
    if not event then return false end

    -- Use event coords directly (all bounds are in HitTest coords)
    local px = event.x
    local py = event.y

    -- Check if clicking on input field
    if self:PointInBounds(px, py, self.inputBounds_) then
        self:Toggle()
        return true
    end

    -- If not open, nothing else to check
    if not self.isOpen_ then return false end

    -- Check if clicking outside popup
    if not self:PointInBounds(px, py, self.popupBounds_) then
        self:Close()
        return true
    end

    -- Check SV picker
    if self:PointInBounds(px, py, self.svBounds_) then
        self.dragging_ = "sv"
        local s = math.max(0, math.min(1, (px - self.svBounds_.x) / self.svBounds_.w))
        local v = math.max(0, math.min(1, 1 - (py - self.svBounds_.y) / self.svBounds_.h))
        self.saturation_ = s
        self.value_ = v
        self:NotifyChange()
        return true
    end

    -- Check Hue slider
    if self:PointInBounds(px, py, self.hueBounds_) then
        self.dragging_ = "hue"
        local h = math.max(0, math.min(1, (px - self.hueBounds_.x) / self.hueBounds_.w))
        self.hue_ = h
        self:NotifyChange()
        return true
    end

    -- Check Alpha slider
    if self.showAlpha_ and self:PointInBounds(px, py, self.alphaBounds_) then
        self.dragging_ = "alpha"
        local a = math.max(0, math.min(1, (px - self.alphaBounds_.x) / self.alphaBounds_.w))
        self.alpha_ = math.floor(a * 255)
        self:NotifyChange()
        return true
    end

    -- Check presets
    if self.presetBounds_ then
        for i, bounds in ipairs(self.presetBounds_) do
            if self:PointInBounds(px, py, bounds) then
                self:SetHex(self.presets_[i])
                self:NotifyChange()
                return true
            end
        end
    end

    return false
end

function ColorPicker:OnPointerUp(event)
    self.dragging_ = nil
end

function ColorPicker:OnClick(event)
    -- Handled by OnPointerDown for drag support
    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a basic color picker
---@param props table|nil
---@return ColorPicker
function ColorPicker.Basic(props)
    return ColorPicker(props)
end

--- Create a color picker with alpha channel
---@param props table|nil
---@return ColorPicker
function ColorPicker.WithAlpha(props)
    props = props or {}
    props.showAlpha = true
    return ColorPicker(props)
end

--- Create a compact color picker (no presets)
---@param props table|nil
---@return ColorPicker
function ColorPicker.Compact(props)
    props = props or {}
    props.showPresets = false
    props.showInput = false
    props.size = "sm"
    return ColorPicker(props)
end

--- Create a color picker with custom presets
---@param presets string[] Array of hex colors
---@param props table|nil
---@return ColorPicker
function ColorPicker.WithPresets(presets, props)
    props = props or {}
    props.presets = presets
    return ColorPicker(props)
end

--- Create a grayscale color picker
---@param props table|nil
---@return ColorPicker
function ColorPicker.Grayscale(props)
    props = props or {}
    props.presets = {
        "#000000", "#1A1A1A", "#333333", "#4D4D4D",
        "#666666", "#808080", "#999999", "#B3B3B3",
        "#CCCCCC", "#E6E6E6", "#F2F2F2", "#FFFFFF",
    }
    return ColorPicker(props)
end

--- Create a material design color picker
---@param props table|nil
---@return ColorPicker
function ColorPicker.Material(props)
    props = props or {}
    props.presets = {
        "#F44336", "#E91E63", "#9C27B0", "#673AB7",
        "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4",
        "#009688", "#4CAF50", "#8BC34A", "#CDDC39",
        "#FFEB3B", "#FFC107", "#FF9800", "#FF5722",
    }
    return ColorPicker(props)
end

return ColorPicker
