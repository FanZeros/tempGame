-- ============================================================================
-- TimePicker Widget
-- Time selection with dropdown popup
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class TimePickerProps : WidgetProps
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field placeholder? string Placeholder text (default: "Select time")
---@field variant? string "outlined" | "filled" | "standard" (default: "outlined")
---@field disabled? boolean Disable the picker
---@field readOnly? boolean Read-only mode
---@field use24Hour? boolean Use 24-hour format (default: true)
---@field showSeconds? boolean Show seconds column
---@field minuteStep? number Minute step (1, 5, 10, 15, 30)
---@field secondStep? number Second step
---@field minTime? table Minimum time {hour, minute, second}
---@field maxTime? table Maximum time {hour, minute, second}
---@field hour? number Initial hour
---@field minute? number Initial minute
---@field second? number Initial second
---@field value? table Initial value {hour, minute, second}
---@field primaryColor? RGBAColor|string Primary color override
---@field fontSize? number Custom font size override
---@field itemHeight? number Custom item height override
---@field fieldFontSize? number Font size (pt) for field text (default: fontSize from size preset)
---@field fieldFontWeight? string Font weight for field text (default: fontWeight)
---@field fieldIdleBorderColor? RGBAColor|string Field border color when closed
---@field fieldIdleBorderWidth? number Field border width when closed
---@field fieldOpenBorderColor? RGBAColor|string Field border color when popup is open
---@field fieldOpenBorderWidth? number Field border width when popup is open
---@field fieldTextColor? RGBAColor|string Field value text color
---@field placeholderColor? RGBAColor|string Field placeholder text color
---@field iconColor? RGBAColor|string Built-in field icon color
---@field showIcon? boolean Show built-in field icon (default: false)
---@field trailing? Widget|string Custom trailing content inside the field
---@field selectedFontWeight? string Font weight for selected time item (default: fontWeight)
---@field selectedFontSize? number Font size for selected time item (default: fontSize)
---@field selectedItemBorderRadius? number Border radius for selected time item (default: borderRadius)
---@field selectedItemBoxShadow? table|false Selected time item shadow
---@field columnSelectedItemBoxShadow? table Per-column selected item shadow { hour = boxShadow, minute = boxShadow, second = boxShadow, ampm = boxShadow }
---@field itemHoverBorderRadius? number Border radius for hovered time item (default: borderRadius)
---@field itemHoverBgColor? RGBAColor|string Hovered time item background color
---@field columnDividerColor? RGBAColor|string Time column divider color
---@field columnDividerWidth? number Time column divider width
---@field popupBgColor? RGBAColor|string Popup panel background color (default: surface)
---@field popupBackgroundGradient? table Popup panel background gradient drawn over popupBgColor
---@field popupBoxShadow? table|false Popup panel shadow; false disables the default shadow
---@field popupBorderColor? RGBAColor|string Popup panel border color
---@field onChange? fun(picker: TimePicker, value: table) Value change callback
---@field onOpen? fun(picker: TimePicker) Open callback
---@field onClose? fun(picker: TimePicker) Close callback

---@class TimePicker : Widget
---@overload fun(props?: TimePickerProps): TimePicker
---@field props TimePickerProps
---@field new fun(self, props?: TimePickerProps): TimePicker
local TimePicker = Widget:Extend("TimePicker")

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { height = 28, fontSize = 12, padding = 8, itemHeight = 28 },
    md = { height = 36, fontSize = 14, padding = 12, itemHeight = 32 },
    lg = { height = 44, fontSize = 16, padding = 16, itemHeight = 40 },
}

-- ============================================================================
-- Time utilities
-- ============================================================================

local function formatTime(hour, minute, second, use24Hour, showSeconds)
    local h = hour
    local ampm = ""

    if not use24Hour then
        if h == 0 then
            h = 12
            ampm = " AM"
        elseif h < 12 then
            ampm = " AM"
        elseif h == 12 then
            ampm = " PM"
        else
            h = h - 12
            ampm = " PM"
        end
    end

    if showSeconds and second then
        return string.format("%02d:%02d:%02d%s", h, minute, second, ampm)
    else
        return string.format("%02d:%02d%s", h, minute, ampm)
    end
end

local function parseTime(timeStr)
    local h, m, s = timeStr:match("(%d+):(%d+):?(%d*)")
    if h and m then
        return tonumber(h), tonumber(m), tonumber(s) or 0
    end
    return nil, nil, nil
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props TimePickerProps?
function TimePicker:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("TimePicker")
    Style.ApplyDefaults(props, themeStyle)

    -- TimePicker props
    self.size_ = props.size or "md"
    self.placeholder_ = props.placeholder or "Select time"
    self.variant_ = props.variant or "outlined"  -- outlined, filled, standard
    self.disabled_ = props.disabled or false
    self.readOnly_ = props.readOnly or false

    -- Time format options
    self.use24Hour_ = props.use24Hour ~= false  -- default true (24-hour)
    self.showSeconds_ = props.showSeconds or false
    self.minuteStep_ = props.minuteStep or 1  -- 1, 5, 10, 15, 30
    self.secondStep_ = props.secondStep or 1

    -- Time constraints
    self.minTime_ = props.minTime  -- { hour, minute, second }
    self.maxTime_ = props.maxTime

    -- Initial value
    self.hour_ = props.hour or (props.value and props.value.hour)
    self.minute_ = props.minute or (props.value and props.value.minute)
    self.second_ = props.second or (props.value and props.value.second) or 0

    -- UI state
    self.isOpen_ = false
    self.activeColumn_ = "hour"  -- hour, minute, second, ampm
    self.hoverHour_ = nil
    self.hoverMinute_ = nil
    self.hoverSecond_ = nil
    self.hoverAmPm_ = nil
    self.scrollOffsets_ = { hour = 0, minute = 0, second = 0, ampm = 0 }
    self.velocities_ = { hour = 0, minute = 0, second = 0, ampm = 0 }
    self.dragColumn_ = nil
    self.dragStartOffset_ = 0
    self.lastPointerX_ = 0
    self.lastPointerY_ = 0

    -- Callbacks
    self.onChange_ = props.onChange
    self.onOpen_ = props.onOpen
    self.onClose_ = props.onClose

    -- Colors
    self.primaryColor_ = props.primaryColor or Theme.Color("primary")

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.inputHeight_ = props.height or sizePreset.height
    self.fontSize_ = props.fontSize or Theme.FontSize(sizePreset.fontSize)
    self.padding_ = props.padding or sizePreset.padding
    self.itemHeight_ = props.itemHeight or sizePreset.itemHeight

    -- Popup dimensions
    self.popupBorderRadius_ = props.popupBorderRadius or themeStyle.borderRadius or 8
    self.columnWidth_ = 60
    local numColumns = self.showSeconds_ and 3 or 2
    if not self.use24Hour_ then
        numColumns = numColumns + 1  -- AM/PM column
    end
    self.popupWidth_ = self.columnWidth_ * numColumns + 16
    self.popupHeight_ = self.itemHeight_ * 7 + 16  -- Show 7 items

    props.width = props.width or 150
    props.height = self.inputHeight_

    Widget.Init(self, props)
end

-- ============================================================================
-- Value Management
-- ============================================================================

function TimePicker:GetValue()
    if self.hour_ == nil or self.minute_ == nil then
        return nil
    end
    return {
        hour = self.hour_,
        minute = self.minute_,
        second = self.second_ or 0,
    }
end

function TimePicker:SetValue(value)
    if value then
        self.hour_ = value.hour
        self.minute_ = value.minute
        self.second_ = value.second or 0
    else
        self.hour_ = nil
        self.minute_ = nil
        self.second_ = 0
    end
end

function TimePicker:Clear()
    self.hour_ = nil
    self.minute_ = nil
    self.second_ = 0
end

function TimePicker:SetHour(hour)
    self.hour_ = hour
    self:NotifyChange()
end

function TimePicker:SetMinute(minute)
    self.minute_ = minute
    self:NotifyChange()
end

function TimePicker:SetSecond(second)
    self.second_ = second
    self:NotifyChange()
end

function TimePicker:NotifyChange()
    local value = self:GetValue()
    self:DispatchEvent("change", self, value)
    if self.onChange_ then
        self.onChange_(self, value)
    end
end

-- ============================================================================
-- Scroll Helpers
-- ============================================================================

function TimePicker:GetOptionsForColumn(col)
    if col == "hour" then return self:GetHourOptions()
    elseif col == "minute" then return self:GetMinuteOptions()
    elseif col == "second" then return self:GetSecondOptions()
    elseif col == "ampm" then return { "AM", "PM" }
    end
    return {}
end

function TimePicker:GetColumnForPoint(px, py)
    if not self.columnBounds_ then return nil end
    for colType, bounds in pairs(self.columnBounds_) do
        if px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h then
            return colType
        end
    end
    return nil
end

function TimePicker:ClampScrollOffset(col)
    local options = self:GetOptionsForColumn(col)
    local maxOffset = (#options - 1) * self.itemHeight_
    self.scrollOffsets_[col] = math.max(0, math.min(self.scrollOffsets_[col], maxOffset))
end

function TimePicker:ScrollOffsetToIndex(col, offset)
    local options = self:GetOptionsForColumn(col)
    local idx = math.floor(offset / self.itemHeight_ + 0.5) + 1
    return math.max(1, math.min(idx, #options))
end

function TimePicker:ApplyScrollSelection(col)
    local options = self:GetOptionsForColumn(col)
    local idx = self:ScrollOffsetToIndex(col, self.scrollOffsets_[col])
    local value = options[idx]
    if value == nil then return end

    if col == "hour" then
        if not self.use24Hour_ then
            local currentAmPm = (self.hour_ and self.hour_ >= 12) and "PM" or "AM"
            if currentAmPm == "PM" then
                self.hour_ = (value == 12) and 12 or (value + 12)
            else
                self.hour_ = (value == 12) and 0 or value
            end
        else
            self.hour_ = value
        end
        self:NotifyChange()
    elseif col == "minute" then
        self.minute_ = value
        self:NotifyChange()
    elseif col == "second" then
        self.second_ = value
        self:NotifyChange()
    elseif col == "ampm" then
        if self.hour_ ~= nil then
            if value == "AM" and self.hour_ >= 12 then
                self.hour_ = self.hour_ - 12
            elseif value == "PM" and self.hour_ < 12 then
                self.hour_ = self.hour_ + 12
            end
            self:NotifyChange()
        end
    end
end

function TimePicker:SyncScrollOffsetsFromValues()
    local itemH = self.itemHeight_

    -- hour
    local hourOpts = self:GetHourOptions()
    for i, v in ipairs(hourOpts) do
        local displayHour = self.hour_
        if not self.use24Hour_ and self.hour_ ~= nil then
            if self.hour_ == 0 then displayHour = 12
            elseif self.hour_ > 12 then displayHour = self.hour_ - 12
            end
        end
        if v == displayHour then
            self.scrollOffsets_.hour = (i - 1) * itemH
            break
        end
    end

    -- minute
    local minOpts = self:GetMinuteOptions()
    for i, v in ipairs(minOpts) do
        if v == self.minute_ then
            self.scrollOffsets_.minute = (i - 1) * itemH
            break
        end
    end

    -- second
    local secOpts = self:GetSecondOptions()
    for i, v in ipairs(secOpts) do
        if v == self.second_ then
            self.scrollOffsets_.second = (i - 1) * itemH
            break
        end
    end

    -- ampm
    if not self.use24Hour_ and self.hour_ ~= nil then
        self.scrollOffsets_.ampm = (self.hour_ >= 12) and itemH or 0
    end

    -- reset velocities
    self.velocities_ = { hour = 0, minute = 0, second = 0, ampm = 0 }
end

-- ============================================================================
-- Time Validation
-- ============================================================================

function TimePicker:IsTimeDisabled(hour, minute, second)
    second = second or 0

    local timeValue = hour * 3600 + minute * 60 + second

    if self.minTime_ then
        local minValue = self.minTime_.hour * 3600 + self.minTime_.minute * 60 + (self.minTime_.second or 0)
        if timeValue < minValue then
            return true
        end
    end

    if self.maxTime_ then
        local maxValue = self.maxTime_.hour * 3600 + self.maxTime_.minute * 60 + (self.maxTime_.second or 0)
        if timeValue > maxValue then
            return true
        end
    end

    return false
end

-- ============================================================================
-- Popup Control
-- ============================================================================

function TimePicker:Open()
    if self.disabled_ or self.readOnly_ then return end
    self.isOpen_ = true
    UI.PushOverlay(self)
    self:SyncScrollOffsetsFromValues()
    self:DispatchEvent("open", self)
    if self.onOpen_ then self.onOpen_(self) end
end

function TimePicker:Close()
    self.isOpen_ = false
    UI.PopOverlay(self)
    self:DispatchEvent("close", self)
    if self.onClose_ then self.onClose_(self) end
end

function TimePicker:Toggle()
    if self.isOpen_ then
        self:Close()
    else
        self:Open()
    end
end

function TimePicker:IsOpen()
    return self.isOpen_
end

-- ============================================================================
-- Display Text
-- ============================================================================

function TimePicker:GetDisplayText()
    if self.hour_ ~= nil and self.minute_ ~= nil then
        return formatTime(self.hour_, self.minute_, self.second_, self.use24Hour_, self.showSeconds_)
    end
    return nil
end

-- ============================================================================
-- Generate Options
-- ============================================================================

function TimePicker:GetHourOptions()
    local options = {}
    local maxHour = self.use24Hour_ and 23 or 11
    local startHour = self.use24Hour_ and 0 or 1

    if not self.use24Hour_ then
        -- 12-hour format: 12, 1, 2, ..., 11
        table.insert(options, 12)
        for i = 1, 11 do
            table.insert(options, i)
        end
    else
        for i = startHour, maxHour do
            table.insert(options, i)
        end
    end

    return options
end

function TimePicker:GetMinuteOptions()
    local options = {}
    for i = 0, 59, self.minuteStep_ do
        table.insert(options, i)
    end
    return options
end

function TimePicker:GetSecondOptions()
    local options = {}
    for i = 0, 59, self.secondStep_ do
        table.insert(options, i)
    end
    return options
end

-- ============================================================================
-- Render
-- ============================================================================

function TimePicker:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()

    -- Store positions for hit testing (use HitTest coords for consistency with overlay)
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    self.inputBounds_ = { x = hitTest.x, y = hitTest.y, w = hitTest.w, h = hitTest.h }

    local bgColor, borderColor, textColor, placeholderColor, borderWidth
    local hasIdleBorderOverride = self.props.fieldIdleBorderColor ~= nil
        or self.props.fieldIdleBorderWidth ~= nil
        or self.props.fieldBorderColor ~= nil

    if self.disabled_ then
        bgColor = Theme.NvgColor("disabled")
        borderColor = Theme.NvgColor("disabledBorder")
        textColor = Theme.NvgColor("textDisabled")
        placeholderColor = textColor
        borderWidth = self.props.fieldIdleBorderWidth or 1
    else
        local fieldBg = self.props.fieldBgColor or Theme.Color("surface")
        bgColor = nvgRGBA(fieldBg[1], fieldBg[2], fieldBg[3], fieldBg[4] or 255)
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
        local fieldText = self.props.fieldTextColor or Theme.Color("text")
        local ph = self.props.placeholderColor or Theme.Color("textSecondary")
        textColor = nvgRGBA(fieldText[1], fieldText[2], fieldText[3], fieldText[4] or 255)
        placeholderColor = nvgRGBA(ph[1], ph[2], ph[3], ph[4] or 255)
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

    local displayText = self:GetDisplayText()
    local fieldFontSize = self.props.fieldFontSize and Theme.FontSize(self.props.fieldFontSize) or self.fontSize_
    local fieldFontFace = Theme.FontFace(self.props.fontFamily, self.props.fieldFontWeight or self.props.fontWeight)
    nvgFontSize(nvg, fieldFontSize)
    nvgFontFace(nvg, fieldFontFace)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    if displayText then
        nvgFillColor(nvg, textColor)
        nvgText(nvg, x + self.padding_, y + h / 2, displayText)
    else
        nvgFillColor(nvg, placeholderColor)
        nvgText(nvg, x + self.padding_, y + h / 2, self.placeholder_)
    end

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
    elseif self.props.showIcon == true then
        local iconX = x + w - self.padding_ - 8
        local iconY = y + h / 2
        nvgFontSize(nvg, self.fontSize_)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, iconNvgColor)
        nvgText(nvg, iconX, iconY, self.props.icon or "🕐")
    end

    -- Queue popup to render as overlay (on top of everything)
    if self.isOpen_ then
        UI.QueueOverlay(function(nvg_)
            self:RenderPopup(nvg_)
        end)
    end
end

function TimePicker:RenderPopup(nvg)
    -- Use GetAbsoluteLayoutForHitTest because overlay renders outside ScrollView's nvgTranslate
    local l = self:GetAbsoluteLayoutForHitTest()
    local px = l.x
    local py = l.y + l.h + 4  -- Position below input field

    local theme = Theme.GetTheme()
    local popW = self.popupWidth_
    local popH = self.popupHeight_
    local columnWidth = self.columnWidth_
    local itemHeight = self.itemHeight_
    local borderRadius = self.popupBorderRadius_
    local contentPadding = 8

    -- Store popup bounds
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
    local popupBorderColor = self.props.popupBorderColor or Theme.Color("border")
    self:CreateShapePath(nvg, popupGeom)
    nvgStrokeColor(nvg, nvgRGBA(popupBorderColor[1], popupBorderColor[2], popupBorderColor[3], popupBorderColor[4] or 255))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    local contentX = px + contentPadding
    local contentY = py + contentPadding
    local colIndex = 0

    -- Hour column (convert to display hour for 12h mode)
    local displayHour = self.hour_
    if not self.use24Hour_ and self.hour_ ~= nil then
        if self.hour_ == 0 then displayHour = 12
        elseif self.hour_ > 12 then displayHour = self.hour_ - 12
        end
    end
    self:RenderColumn(nvg, contentX + colIndex * columnWidth, contentY,
                      "hour", self:GetHourOptions(), displayHour, self.hoverHour_, columnWidth, itemHeight, true)
    colIndex = colIndex + 1

    -- Minute column
    self:RenderColumn(nvg, contentX + colIndex * columnWidth, contentY,
                      "minute", self:GetMinuteOptions(), self.minute_, self.hoverMinute_, columnWidth, itemHeight, self.showSeconds_ or not self.use24Hour_)
    colIndex = colIndex + 1

    -- Second column (optional)
    if self.showSeconds_ then
        self:RenderColumn(nvg, contentX + colIndex * columnWidth, contentY,
                          "second", self:GetSecondOptions(), self.second_, self.hoverSecond_, columnWidth, itemHeight, not self.use24Hour_)
        colIndex = colIndex + 1
    end

    -- AM/PM column (for 12-hour format)
    if not self.use24Hour_ then
        self:RenderAmPmColumn(nvg, contentX + colIndex * columnWidth, contentY, columnWidth, itemHeight)
    end
end

function TimePicker:RenderColumn(nvg, x, y, columnType, options, selectedValue, hoverValue, columnWidth, itemHeight, hasNextColumn)
    local visibleItems = 7
    local centerIndex = math.floor(visibleItems / 2)  -- 3 (0-based center slot)
    local borderRadius = self.props.borderRadius ~= nil and self.props.borderRadius or 4
    local selectedRadius = self.props.selectedItemBorderRadius ~= nil
        and self.props.selectedItemBorderRadius
        or borderRadius
    local itemPadding = 2
    local columnH = itemHeight * visibleItems

    -- Store column bounds for hit testing
    self.columnBounds_ = self.columnBounds_ or {}
    self.columnBounds_[columnType] = { x = x, y = y, w = columnWidth, h = columnH }

    -- Scroll-based positioning
    local scrollOffset = self.scrollOffsets_[columnType] or 0
    local centerItemFloat = scrollOffset / itemHeight  -- 0-based float index of center item
    local firstVisible = math.floor(centerItemFloat) - centerIndex
    local fractionalOffset = scrollOffset - math.floor(centerItemFloat) * itemHeight

    -- Clip to column area
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, columnWidth, columnH)

    -- Draw items (one extra on each side for partial visibility)
    self.columnItems_ = self.columnItems_ or {}
    self.columnItems_[columnType] = {}

    for i = 0, visibleItems + 1 do
        local optIndex = firstVisible + i + 1  -- 1-based Lua index
        local itemY = y + i * itemHeight - fractionalOffset

        if optIndex >= 1 and optIndex <= #options then
            local value = options[optIndex]
            local isSelected = value == selectedValue
            local isHovered = value == hoverValue

            -- Distance from center in pixels for alpha calculation
            local itemCenter = itemY + itemHeight / 2
            local columnCenter = y + columnH / 2
            local distFromCenter = math.abs(itemCenter - columnCenter) / itemHeight

            -- Store item bounds (only if visible in column area)
            if itemY + itemHeight > y and itemY < y + columnH then
                self.columnItems_[columnType][value] = {
                    x = x, y = itemY, w = columnWidth, h = itemHeight
                }
            end

            -- Draw selection/hover background
            if isSelected then
                local selBg = self.props.selectedBgColor
                local selBorder = self.props.selectedBorderColor
                local rx, ry, rw, rh = x + itemPadding, itemY + itemPadding, columnWidth - itemPadding * 2, itemHeight - itemPadding * 2
                local columnSelectedShadows = self.props.columnSelectedItemBoxShadow
                local selectedItemBoxShadow = columnSelectedShadows and columnSelectedShadows[columnType]
                if selectedItemBoxShadow == nil then
                    selectedItemBoxShadow = self.props.selectedItemBoxShadow
                end
                if selectedItemBoxShadow and selectedItemBoxShadow ~= false then
                    local geom = self:GetShapeGeometry({ x = rx, y = ry, w = rw, h = rh }, nil, selectedRadius)
                    self:RenderBoxShadows(nvg, geom, selectedItemBoxShadow)
                end
                if selBg ~= nil and selBg ~= false then
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, rx, ry, rw, rh, selectedRadius)
                    nvgFillColor(nvg, nvgRGBA(selBg[1], selBg[2], selBg[3], selBg[4] or 255))
                    nvgFill(nvg)
                elseif selBg == nil and not selBorder then
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, rx, ry, rw, rh, selectedRadius)
                    nvgFillColor(nvg, Theme.ToNvgColor(self.primaryColor_))
                    nvgFill(nvg)
                end
                if selBorder then
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, rx, ry, rw, rh, selectedRadius)
                    nvgStrokeColor(nvg, nvgRGBA(selBorder[1], selBorder[2], selBorder[3], selBorder[4] or 255))
                    nvgStrokeWidth(nvg, self.props.selectedBorderWidth or 2)
                    nvgStroke(nvg)
                end
            elseif isHovered then
                local hoverRadius = self.props.itemHoverBorderRadius ~= nil
                    and self.props.itemHoverBorderRadius
                    or borderRadius
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, x + itemPadding, itemY + itemPadding, columnWidth - itemPadding * 2, itemHeight - itemPadding * 2, hoverRadius)
                local hc = self.props.itemHoverBgColor or Theme.Color("surfaceHover")
                nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4] or 255))
                nvgFill(nvg)
            end

            -- Draw text
            local itemFontSize = isSelected and (self.props.selectedFontSize and Theme.FontSize(self.props.selectedFontSize) or self.fontSize_) or self.fontSize_
            local itemFontWeight = isSelected and (self.props.selectedFontWeight or self.props.fontWeight) or self.props.fontWeight
            nvgFontSize(nvg, itemFontSize)
            nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, itemFontWeight))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)

            local alpha = math.max(100, math.floor(255 - distFromCenter * 50))

            if isSelected then
                local hasBgFill = self.props.selectedBgColor ~= nil and self.props.selectedBgColor ~= false
                    or (self.props.selectedBgColor == nil and not self.props.selectedBorderColor)
                local selText = self.props.selectedTextColor
                    or (hasBgFill and {255, 255, 255, 255} or self.props.selectedBorderColor)
                    or {255, 255, 255, 255}
                nvgFillColor(nvg, nvgRGBA(selText[1], selText[2], selText[3], selText[4] or 255))
            else
                local textColor = Theme.Color("text")
                nvgFillColor(nvg, nvgRGBA(textColor[1] or 0, textColor[2] or 0, textColor[3] or 0, alpha))
            end

            nvgText(nvg, x + columnWidth / 2, itemY + itemHeight / 2, string.format("%02d", value))
        end
    end

    nvgRestore(nvg)

    -- Draw separator
    local dividerWidth = self.props.columnDividerWidth
    if dividerWidth == nil then dividerWidth = 1 end
    if dividerWidth > 0 and hasNextColumn then
        local dividerColor = self.props.columnDividerColor or Theme.Color("border")
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x + columnWidth - dividerWidth / 2, y)
        nvgLineTo(nvg, x + columnWidth - dividerWidth / 2, y + columnH)
        nvgStrokeColor(nvg, nvgRGBA(dividerColor[1], dividerColor[2], dividerColor[3], dividerColor[4] or 255))
        nvgStrokeWidth(nvg, dividerWidth)
        nvgStroke(nvg)
    end
end

function TimePicker:RenderAmPmColumn(nvg, x, y, columnWidth, itemHeight)
    local theme = Theme.GetTheme()
    local options = { "AM", "PM" }
    local borderRadius = self.props.borderRadius ~= nil and self.props.borderRadius or 4
    local selectedRadius = self.props.selectedItemBorderRadius ~= nil
        and self.props.selectedItemBorderRadius
        or borderRadius
    local itemPadding = 2

    -- Determine current AM/PM
    local currentAmPm = (self.hour_ and self.hour_ >= 12) and "PM" or "AM"

    self.columnBounds_ = self.columnBounds_ or {}
    self.columnBounds_["ampm"] = { x = x, y = y, w = columnWidth, h = itemHeight * 2 }

    self.columnItems_ = self.columnItems_ or {}
    self.columnItems_["ampm"] = {}

    for i, option in ipairs(options) do
        local itemY = y + (i - 1) * itemHeight + itemHeight * 2.5  -- Center vertically

        local isSelected = option == currentAmPm
        local isHovered = option == self.hoverAmPm_

        self.columnItems_["ampm"][option] = {
            x = x, y = itemY, w = columnWidth, h = itemHeight
        }

        -- Draw selection/hover background
        if isSelected then
            local selBg = self.props.selectedBgColor
            local selBorder = self.props.selectedBorderColor
            local rx, ry, rw, rh = x + itemPadding, itemY + itemPadding, columnWidth - itemPadding * 2, itemHeight - itemPadding * 2
            local columnSelectedShadows = self.props.columnSelectedItemBoxShadow
            local selectedItemBoxShadow = columnSelectedShadows and columnSelectedShadows.ampm
            if selectedItemBoxShadow == nil then
                selectedItemBoxShadow = self.props.selectedItemBoxShadow
            end
            if selectedItemBoxShadow and selectedItemBoxShadow ~= false then
                local geom = self:GetShapeGeometry({ x = rx, y = ry, w = rw, h = rh }, nil, selectedRadius)
                self:RenderBoxShadows(nvg, geom, selectedItemBoxShadow)
            end
            if selBg ~= nil and selBg ~= false then
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, rx, ry, rw, rh, selectedRadius)
                nvgFillColor(nvg, nvgRGBA(selBg[1], selBg[2], selBg[3], selBg[4] or 255))
                nvgFill(nvg)
            elseif selBg == nil and not selBorder then
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, rx, ry, rw, rh, selectedRadius)
                nvgFillColor(nvg, Theme.ToNvgColor(self.primaryColor_))
                nvgFill(nvg)
            end
            if selBorder then
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, rx, ry, rw, rh, selectedRadius)
                nvgStrokeColor(nvg, nvgRGBA(selBorder[1], selBorder[2], selBorder[3], selBorder[4] or 255))
                nvgStrokeWidth(nvg, self.props.selectedBorderWidth or 2)
                nvgStroke(nvg)
            end
        elseif isHovered then
            local hoverRadius = self.props.itemHoverBorderRadius ~= nil
                and self.props.itemHoverBorderRadius
                or borderRadius
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x + itemPadding, itemY + itemPadding, columnWidth - itemPadding * 2, itemHeight - itemPadding * 2, hoverRadius)
            local hc = self.props.itemHoverBgColor or Theme.Color("surfaceHover")
            nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4] or 255))
            nvgFill(nvg)
        end

        -- Draw text
        local itemFontSize = isSelected and (self.props.selectedFontSize and Theme.FontSize(self.props.selectedFontSize) or self.fontSize_) or self.fontSize_
        local itemFontWeight = isSelected and (self.props.selectedFontWeight or self.props.fontWeight) or self.props.fontWeight
        nvgFontSize(nvg, itemFontSize)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, itemFontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)

        if isSelected then
            local selText = self.props.selectedTextColor or {255, 255, 255, 255}
            nvgFillColor(nvg, nvgRGBA(selText[1], selText[2], selText[3], selText[4] or 255))
        else
            nvgFillColor(nvg, Theme.NvgColor("text"))
        end

        nvgText(nvg, x + columnWidth / 2, itemY + itemHeight / 2, option)
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function TimePicker:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function TimePicker:HitTest(x, y)
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

function TimePicker:OnPointerMove(event)
    if not event then return end

    -- Cache pointer position for OnWheel (which has no coords)
    self.lastPointerX_ = event.x
    self.lastPointerY_ = event.y

    if not self.isOpen_ then return end

    -- Use event coords directly (all bounds are in HitTest coords)
    local px = event.x
    local py = event.y

    -- Reset hover states
    self.hoverHour_ = nil
    self.hoverMinute_ = nil
    self.hoverSecond_ = nil
    self.hoverAmPm_ = nil

    -- Check column items
    if self.columnItems_ then
        for colType, items in pairs(self.columnItems_) do
            for value, bounds in pairs(items) do
                if self:PointInBounds(px, py, bounds) then
                    if colType == "hour" then
                        self.hoverHour_ = value
                    elseif colType == "minute" then
                        self.hoverMinute_ = value
                    elseif colType == "second" then
                        self.hoverSecond_ = value
                    elseif colType == "ampm" then
                        self.hoverAmPm_ = value
                    end
                    return
                end
            end
        end
    end
end

function TimePicker:OnMouseLeave(event)
    self.hoverHour_ = nil
    self.hoverMinute_ = nil
    self.hoverSecond_ = nil
    self.hoverAmPm_ = nil
end

function TimePicker:OnWheel(dx, dy)
    if not self.isOpen_ then return end
    if not self.columnBounds_ then return end

    local col = self:GetColumnForPoint(self.lastPointerX_, self.lastPointerY_)
    if not col then return end
    -- AM/PM column: only 2 items, skip scroll for it
    if col == "ampm" then return end

    local itemH = self.itemHeight_
    -- 每次滚轮一格 = 一个 item：用 dy 符号归一，避免 Web/WASM 的大 delta（~100+）一下滚到底。
    local dir = dy > 0 and 1 or (dy < 0 and -1 or 0)
    local scrollDelta = -dir * itemH

    self.scrollOffsets_[col] = self.scrollOffsets_[col] + scrollDelta
    self.velocities_[col] = 0
    self:ClampScrollOffset(col)
    self:ApplyScrollSelection(col)
end

function TimePicker:OnPanStart(event)
    if not self.isOpen_ then return false end

    local col = self:GetColumnForPoint(event.x, event.y)
    if not col then return false end
    if col == "ampm" then return false end

    self:SetState({ isDragging = true })
    self.dragColumn_ = col
    self.dragStartOffset_ = self.scrollOffsets_[col]
    self.velocities_[col] = 0
    return true
end

function TimePicker:OnPanMove(event)
    if not self.state.isDragging then return end
    local col = self.dragColumn_
    if not col then return end

    -- Finger up = totalDeltaY < 0 = offset increases = list scrolls up
    self.scrollOffsets_[col] = self.dragStartOffset_ - event.totalDeltaY
    self:ClampScrollOffset(col)
    self:ApplyScrollSelection(col)
    -- Track velocity for momentum
    self.velocities_[col] = -event.deltaY
end

function TimePicker:OnPanEnd(event)
    if not self.state.isDragging then return end
    self:SetState({ isDragging = false })
    self.dragColumn_ = nil
end

function TimePicker:Update(dt)
    if not self.isOpen_ then return end

    local friction = 0.92
    local snapSpeed = 0.15
    local itemH = self.itemHeight_
    local cols = { "hour", "minute", "second" }

    for _, col in ipairs(cols) do
        local vel = self.velocities_[col]

        if self.state.isDragging and self.dragColumn_ == col then
            -- Dragging, skip momentum
        elseif math.abs(vel) > 0.5 then
            -- Momentum phase
            self.velocities_[col] = vel * friction
            self.scrollOffsets_[col] = self.scrollOffsets_[col] + vel * dt * 60
            self:ClampScrollOffset(col)
            self:ApplyScrollSelection(col)
        else
            -- Snap to nearest item
            self.velocities_[col] = 0
            local offset = self.scrollOffsets_[col]
            local target = math.floor(offset / itemH + 0.5) * itemH
            if math.abs(offset - target) > 0.5 then
                self.scrollOffsets_[col] = offset + (target - offset) * snapSpeed
            else
                self.scrollOffsets_[col] = target
            end
        end
    end
end

function TimePicker:OnClick(event)
    if not event then return end

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

    -- Check column items
    if self.columnItems_ then
        for colType, items in pairs(self.columnItems_) do
            for value, bounds in pairs(items) do
                if self:PointInBounds(px, py, bounds) then
                    if colType == "hour" then
                        if not self.use24Hour_ then
                            -- Convert to 24-hour for internal storage
                            local currentAmPm = (self.hour_ and self.hour_ >= 12) and "PM" or "AM"
                            if currentAmPm == "PM" then
                                self.hour_ = (value == 12) and 12 or (value + 12)
                            else
                                self.hour_ = (value == 12) and 0 or value
                            end
                        else
                            self.hour_ = value
                        end
                        self:NotifyChange()
                    elseif colType == "minute" then
                        self.minute_ = value
                        self:NotifyChange()
                    elseif colType == "second" then
                        self.second_ = value
                        self:NotifyChange()
                    elseif colType == "ampm" then
                        -- Toggle AM/PM
                        if self.hour_ ~= nil then
                            if value == "AM" and self.hour_ >= 12 then
                                self.hour_ = self.hour_ - 12
                            elseif value == "PM" and self.hour_ < 12 then
                                self.hour_ = self.hour_ + 12
                            end
                            self:NotifyChange()
                        end
                    end
                    -- Sync scroll offset to clicked item
                    self:SyncScrollOffsetsFromValues()
                    return true
                end
            end
        end
    end

    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a basic 24-hour time picker
---@param props table|nil
---@return TimePicker
function TimePicker.Time24(props)
    props = props or {}
    props.use24Hour = true
    return TimePicker(props)
end

--- Create a 12-hour time picker with AM/PM
---@param props table|nil
---@return TimePicker
function TimePicker.Time12(props)
    props = props or {}
    props.use24Hour = false
    return TimePicker(props)
end

--- Create a time picker with seconds
---@param props table|nil
---@return TimePicker
function TimePicker.WithSeconds(props)
    props = props or {}
    props.showSeconds = true
    return TimePicker(props)
end

--- Create a time picker with minute intervals
---@param step number Minute step (5, 10, 15, 30)
---@param props table|nil
---@return TimePicker
function TimePicker.WithStep(step, props)
    props = props or {}
    props.minuteStep = step
    return TimePicker(props)
end

--- Create a working hours time picker (9:00 - 18:00)
---@param props table|nil
---@return TimePicker
function TimePicker.WorkingHours(props)
    props = props or {}
    props.minTime = { hour = 9, minute = 0 }
    props.maxTime = { hour = 18, minute = 0 }
    props.placeholder = props.placeholder or "Working hours"
    return TimePicker(props)
end

--- Create a duration picker (starting from 00:00)
---@param props table|nil
---@return TimePicker
function TimePicker.Duration(props)
    props = props or {}
    props.placeholder = props.placeholder or "Duration"
    props.value = { hour = 0, minute = 0 }
    return TimePicker(props)
end

return TimePicker
