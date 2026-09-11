-- ============================================================================
-- DatePicker Widget
-- Date selection with calendar popup
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class DatePickerProps : WidgetProps
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field placeholder? string Placeholder text (default: "Select date")
---@field format? string Date format string (default: "yyyy-mm-dd")
---@field variant? string "outlined" | "filled" | "standard" (default: "outlined")
---@field disabled? boolean Disable the picker
---@field readOnly? boolean Read-only mode
---@field minDate? table Minimum date {year, month, day}
---@field maxDate? table Maximum date {year, month, day}
---@field selectionMode? string "single" | "range" | "multiple" (default: "single")
---@field value? table Initial value {year, month, day}
---@field selectedDate? table Alias for value
---@field rangeStart? table Range start date
---@field rangeEnd? table Range end date
---@field selectedDates? table[] Multiple selected dates
---@field primaryColor? RGBAColor|string Primary color override
---@field fontSize? number Custom font size
---@field cellSize? number Calendar cell size
---@field headerSize? number Calendar header (month/year) font size in pt
---@field weekdayFontSize? number Popup weekday row font size in pt (default: field fontSize × 0.85)
---@field dayFontSize? number Popup day cell font size in pt (default: field fontSize)
---@field fieldFontSize? number Font size (pt) for field text (default: fontSize from size preset)
---@field fieldFontWeight? string Font weight for field text (default: fontWeight)
---@field fieldIdleBorderColor? RGBAColor|string Field border color when closed
---@field fieldIdleBorderWidth? number Field border width when closed
---@field fieldOpenBorderColor? RGBAColor|string Field border color when popup is open
---@field fieldOpenBorderWidth? number Field border width when popup is open
---@field fieldTextColor? RGBAColor|string Field value text color
---@field placeholderColor? RGBAColor|string Field placeholder text color
---@field iconColor? RGBAColor|string Built-in field icon color
---@field showIcon? boolean Show built-in field icon/dropdown affordance (default: false)
---@field trailing? Widget|string Custom trailing content inside the field
---@field monthTitleFormat? string Popup month title format, e.g. yyyy年m月
---@field monthNames? string[] Month names for popup title
---@field monthNamesShort? string[] Short month names for popup title
---@field weekdayNames? string[] Weekday labels for popup header
---@field monthFontWeight? string Font weight for month title (default: fontWeight)
---@field weekdayFontWeight? string Font weight for weekday labels (default: fontWeight)
---@field dayFontWeight? string Font weight for day numbers (default: fontWeight)
---@field selectedFontWeight? string Font weight for selected day (default: dayFontWeight or fontWeight)
---@field todayBtnRadius? number Today button border radius (default: 4)
---@field todayLabel? string Today button text (default: Today)
---@field todayIcon? Widget|string Today button leading icon widget or text
---@field todayIconColor? RGBAColor|string Today button icon color
---@field todayBtnBoxShadow? table|false Today button shadow; false disables shadow
---@field selectedDayBoxShadow? table|false Selected day cell shadow; false disables shadow
---@field popupBgColor? RGBAColor|string Popup panel background color (default: surface)
---@field popupBackgroundGradient? table Popup panel background gradient drawn over popupBgColor
---@field popupBoxShadow? table|false Popup panel shadow; false disables the default shadow
---@field popupBorderColor? RGBAColor|string Popup panel border color
---@field navBtnHoverBgColor? RGBAColor|string Navigation button hover background color
---@field dayHoverBgColor? RGBAColor|string Day cell hover background color
---@field onChange? fun(picker: DatePicker, value: table) Value change callback
---@field onOpen? fun(picker: DatePicker) Open callback
---@field onClose? fun(picker: DatePicker) Close callback

---@class DatePicker : Widget
---@overload fun(props?: DatePickerProps): DatePicker
---@field props DatePickerProps
---@field new fun(self, props?: DatePickerProps): DatePicker
local DatePicker = Widget:Extend("DatePicker")

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { height = 28, fontSize = 12, padding = 8, cellSize = 24, headerSize = 13 },
    md = { height = 36, fontSize = 14, padding = 12, cellSize = 32, headerSize = 15 },
    lg = { height = 44, fontSize = 16, padding = 16, cellSize = 40, headerSize = 17 },
}

-- ============================================================================
-- Date utilities
-- ============================================================================

local function getDaysInMonth(year, month)
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 then
        -- Leap year check
        if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
            return 29
        end
    end
    return days[month]
end

local function getFirstDayOfMonth(year, month)
    -- Returns 0=Sunday, 1=Monday, ..., 6=Saturday
    local t = os.time({ year = year, month = month, day = 1 })
    return tonumber(os.date("%w", t))
end

local function formatDate(year, month, day, format)
    format = format or "yyyy-mm-dd"
    local result = format
    result = result:gsub("yyyy", string.format("%04d", year))
    result = result:gsub("yy", string.format("%02d", year % 100))
    result = result:gsub("mm", string.format("%02d", month))
    result = result:gsub("m", tostring(month))
    result = result:gsub("dd", string.format("%02d", day))
    result = result:gsub("d", tostring(day))
    return result
end

local function parseDate(dateStr)
    local year, month, day = dateStr:match("(%d+)-(%d+)-(%d+)")
    if year and month and day then
        return tonumber(year), tonumber(month), tonumber(day)
    end
    return nil, nil, nil
end

local function compareDates(y1, m1, d1, y2, m2, d2)
    if y1 ~= y2 then return y1 - y2 end
    if m1 ~= m2 then return m1 - m2 end
    return d1 - d2
end

local MONTH_NAMES = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
}

local MONTH_NAMES_SHORT = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
}

local WEEKDAY_NAMES = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }

local function formatMonthTitle(year, month, format, monthNames, monthNamesShort)
    monthNames = monthNames or MONTH_NAMES
    monthNamesShort = monthNamesShort or MONTH_NAMES_SHORT
    if not format then
        return (monthNames[month] or tostring(month)) .. " " .. tostring(year)
    end

    local fullToken = "{MONTH_FULL}"
    local shortToken = "{MONTH_SHORT}"
    local result = format
    result = result:gsub("MMMM", fullToken)
    result = result:gsub("MMM", shortToken)
    result = result:gsub("yyyy", string.format("%04d", year))
    result = result:gsub("yy", string.format("%02d", year % 100))
    result = result:gsub("mm", string.format("%02d", month))
    result = result:gsub("m", tostring(month))
    result = result:gsub(fullToken, monthNames[month] or tostring(month))
    result = result:gsub(shortToken, monthNamesShort[month] or monthNames[month] or tostring(month))
    return result
end

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props DatePickerProps?
function DatePicker:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("DatePicker")
    Style.ApplyDefaults(props, themeStyle)

    -- DatePicker props
    self.size_ = props.size or "md"
    self.placeholder_ = props.placeholder or "Select date"
    self.format_ = props.format or "yyyy-mm-dd"
    self.variant_ = props.variant or "outlined"  -- outlined, filled, standard
    self.disabled_ = props.disabled or false
    self.readOnly_ = props.readOnly or false

    -- Date constraints
    self.minDate_ = props.minDate  -- { year, month, day }
    self.maxDate_ = props.maxDate

    -- Selection mode
    self.selectionMode_ = props.selectionMode or "single"  -- single, range, multiple
    -- 选中日期后是否自动关闭弹层（默认 true）；false 时选完不收起，靠再次点输入框 toggle 收回。
    self.closeOnSelect_ = props.closeOnSelect ~= false

    -- Initial value
    self.selectedDate_ = props.value or props.selectedDate  -- { year, month, day }
    self.rangeStart_ = props.rangeStart
    self.rangeEnd_ = props.rangeEnd
    self.selectedDates_ = props.selectedDates or {}  -- For multiple mode

    -- Display state
    local now = os.date("*t")
    self.viewYear_ = self.selectedDate_ and self.selectedDate_.year or now.year
    self.viewMonth_ = self.selectedDate_ and self.selectedDate_.month or now.month

    -- UI state
    self.isOpen_ = false
    self.hoverDay_ = nil
    self.hoverNav_ = nil  -- "prev", "next", "month", "year"

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
    self.cellSize_ = props.cellSize or sizePreset.cellSize
    self.headerSize_ = props.headerSize or sizePreset.headerSize

    -- Popup border radius
    self.popupBorderRadius_ = props.popupBorderRadius or themeStyle.borderRadius or 8

    -- Calendar dimensions
    self.calendarWidth_ = self.cellSize_ * 7 + 16
    local todayH = props.todayBtnHeight or 40
    local todayG = 4  -- cellPadding * 2
    self.calendarHeight_ = 44 + self.cellSize_ * 7 + todayG + todayH + todayG

    props.width = props.width or 200
    props.height = self.inputHeight_

    Widget.Init(self, props)
end

-- ============================================================================
-- Date Management
-- ============================================================================

function DatePicker:GetValue()
    if self.selectionMode_ == "range" then
        return { start = self.rangeStart_, ["end"] = self.rangeEnd_ }
    elseif self.selectionMode_ == "multiple" then
        return self.selectedDates_
    else
        return self.selectedDate_
    end
end

function DatePicker:SetValue(value)
    if self.selectionMode_ == "range" then
        self.rangeStart_ = value and value.start
        self.rangeEnd_ = value and value["end"]
    elseif self.selectionMode_ == "multiple" then
        self.selectedDates_ = value or {}
    else
        self.selectedDate_ = value
        if value then
            self.viewYear_ = value.year
            self.viewMonth_ = value.month
        end
    end
end

function DatePicker:Clear()
    self.selectedDate_ = nil
    self.rangeStart_ = nil
    self.rangeEnd_ = nil
    self.selectedDates_ = {}
end

function DatePicker:IsDateDisabled(year, month, day)
    if self.minDate_ then
        if compareDates(year, month, day, self.minDate_.year, self.minDate_.month, self.minDate_.day) < 0 then
            return true
        end
    end
    if self.maxDate_ then
        if compareDates(year, month, day, self.maxDate_.year, self.maxDate_.month, self.maxDate_.day) > 0 then
            return true
        end
    end
    return false
end

function DatePicker:IsDateSelected(year, month, day)
    if self.selectionMode_ == "single" then
        if self.selectedDate_ then
            return self.selectedDate_.year == year and
                   self.selectedDate_.month == month and
                   self.selectedDate_.day == day
        end
    elseif self.selectionMode_ == "range" then
        if self.rangeStart_ and self.rangeEnd_ then
            local cmpStart = compareDates(year, month, day, self.rangeStart_.year, self.rangeStart_.month, self.rangeStart_.day)
            local cmpEnd = compareDates(year, month, day, self.rangeEnd_.year, self.rangeEnd_.month, self.rangeEnd_.day)
            return cmpStart >= 0 and cmpEnd <= 0
        elseif self.rangeStart_ then
            return self.rangeStart_.year == year and
                   self.rangeStart_.month == month and
                   self.rangeStart_.day == day
        end
    elseif self.selectionMode_ == "multiple" then
        for _, date in ipairs(self.selectedDates_) do
            if date.year == year and date.month == month and date.day == day then
                return true
            end
        end
    end
    return false
end

function DatePicker:IsRangeEdge(year, month, day)
    if self.selectionMode_ ~= "range" then return false, false end

    local isStart = self.rangeStart_ and
                    self.rangeStart_.year == year and
                    self.rangeStart_.month == month and
                    self.rangeStart_.day == day
    local isEnd = self.rangeEnd_ and
                  self.rangeEnd_.year == year and
                  self.rangeEnd_.month == month and
                  self.rangeEnd_.day == day

    return isStart, isEnd
end

function DatePicker:SelectDate(year, month, day)
    if self:IsDateDisabled(year, month, day) then return end

    if self.selectionMode_ == "single" then
        self.selectedDate_ = { year = year, month = month, day = day }
        if self.closeOnSelect_ then
            self.isOpen_ = false
            self:DispatchEvent("close", self)
            if self.onClose_ then self.onClose_(self) end
        end
    elseif self.selectionMode_ == "range" then
        if not self.rangeStart_ or (self.rangeStart_ and self.rangeEnd_) then
            -- Start new range
            self.rangeStart_ = { year = year, month = month, day = day }
            self.rangeEnd_ = nil
        else
            -- Complete range
            local cmp = compareDates(year, month, day, self.rangeStart_.year, self.rangeStart_.month, self.rangeStart_.day)
            if cmp < 0 then
                -- Selected before start, swap
                self.rangeEnd_ = self.rangeStart_
                self.rangeStart_ = { year = year, month = month, day = day }
            else
                self.rangeEnd_ = { year = year, month = month, day = day }
            end
            if self.closeOnSelect_ then
                self.isOpen_ = false
                self:DispatchEvent("close", self)
                if self.onClose_ then self.onClose_(self) end
            end
        end
    elseif self.selectionMode_ == "multiple" then
        -- Toggle selection
        local found = false
        for i, date in ipairs(self.selectedDates_) do
            if date.year == year and date.month == month and date.day == day then
                table.remove(self.selectedDates_, i)
                found = true
                break
            end
        end
        if not found then
            table.insert(self.selectedDates_, { year = year, month = month, day = day })
        end
    end

    local value = self:GetValue()
    self:DispatchEvent("change", self, value)
    if self.onChange_ then
        self.onChange_(self, value)
    end
end

-- ============================================================================
-- Navigation
-- ============================================================================

function DatePicker:PrevMonth()
    self.viewMonth_ = self.viewMonth_ - 1
    if self.viewMonth_ < 1 then
        self.viewMonth_ = 12
        self.viewYear_ = self.viewYear_ - 1
    end
end

function DatePicker:NextMonth()
    self.viewMonth_ = self.viewMonth_ + 1
    if self.viewMonth_ > 12 then
        self.viewMonth_ = 1
        self.viewYear_ = self.viewYear_ + 1
    end
end

function DatePicker:PrevYear()
    self.viewYear_ = self.viewYear_ - 1
end

function DatePicker:NextYear()
    self.viewYear_ = self.viewYear_ + 1
end

function DatePicker:GoToToday()
    local now = os.date("*t")
    self.viewYear_ = now.year
    self.viewMonth_ = now.month
end

-- ============================================================================
-- Popup Control
-- ============================================================================

function DatePicker:Open()
    if self.disabled_ or self.readOnly_ then return end
    self.isOpen_ = true
    UI.PushOverlay(self)
    self:DispatchEvent("open", self)
    if self.onOpen_ then self.onOpen_(self) end
end

function DatePicker:Close()
    self.isOpen_ = false
    self.hoverDay_ = nil
    UI.PopOverlay(self)
    self:DispatchEvent("close", self)
    if self.onClose_ then self.onClose_(self) end
end

function DatePicker:Toggle()
    if self.isOpen_ then
        self:Close()
    else
        self:Open()
    end
end

function DatePicker:IsOpen()
    return self.isOpen_
end

-- ============================================================================
-- Display Text
-- ============================================================================

function DatePicker:GetDisplayText()
    if self.selectionMode_ == "single" then
        if self.selectedDate_ then
            return formatDate(self.selectedDate_.year, self.selectedDate_.month, self.selectedDate_.day, self.format_)
        end
    elseif self.selectionMode_ == "range" then
        if self.rangeStart_ and self.rangeEnd_ then
            local startStr = formatDate(self.rangeStart_.year, self.rangeStart_.month, self.rangeStart_.day, self.format_)
            local endStr = formatDate(self.rangeEnd_.year, self.rangeEnd_.month, self.rangeEnd_.day, self.format_)
            return startStr .. " - " .. endStr
        elseif self.rangeStart_ then
            return formatDate(self.rangeStart_.year, self.rangeStart_.month, self.rangeStart_.day, self.format_) .. " - ..."
        end
    elseif self.selectionMode_ == "multiple" then
        local count = #self.selectedDates_
        if count > 0 then
            return count .. " date" .. (count > 1 and "s" or "") .. " selected"
        end
    end
    return nil
end

-- ============================================================================
-- Render
-- ============================================================================

function DatePicker:Render(nvg)
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
        local iconX = x + w - self.padding_ - 12
        local iconY = y + h / 2
        nvgFontSize(nvg, self.fontSize_)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, iconNvgColor)
        nvgText(nvg, iconX, iconY, self.props.icon or "📅")

        local arrowX = x + w - self.padding_ / 2
        nvgBeginPath(nvg)
        if self.isOpen_ then
            nvgMoveTo(nvg, arrowX - 4, iconY + 2)
            nvgLineTo(nvg, arrowX, iconY - 2)
            nvgLineTo(nvg, arrowX + 4, iconY + 2)
        else
            nvgMoveTo(nvg, arrowX - 4, iconY - 2)
            nvgLineTo(nvg, arrowX, iconY + 2)
            nvgLineTo(nvg, arrowX + 4, iconY - 2)
        end
        nvgStrokeColor(nvg, iconNvgColor)
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end

    -- Queue calendar popup to render as overlay (on top of everything)
    if self.isOpen_ then
        UI.QueueOverlay(function(nvg_)
            self:RenderCalendar(nvg_)
        end)
    end
end

function DatePicker:RenderCalendar(nvg)
    -- Use GetAbsoluteLayoutForHitTest because overlay renders outside ScrollView's nvgTranslate
    local l = self:GetAbsoluteLayoutForHitTest()
    local px = l.x
    local py = l.y + l.h + 4  -- Position below input field

    local theme = Theme.GetTheme()

    -- Dimensions (no scale needed - nvgScale handles it)
    local cellSize = self.cellSize_
    local calW = cellSize * 7 + 16
    local borderRadius = self.popupBorderRadius_
    local contentPadding = 8
    local headerH = 32
    local navBtnSize = 24
    local calH = self.calendarHeight_

    -- Store calendar bounds
    self.calendarBounds_ = { x = px, y = py, w = calW, h = calH }

    local popupGeom = self:GetShapeGeometry({ x = px, y = py, w = calW, h = calH }, nil, borderRadius)

    -- Shadow
    local popupBoxShadow = self.props.popupBoxShadow
    if popupBoxShadow == false then
        -- Explicitly disabled.
    elseif popupBoxShadow then
        self:RenderBoxShadows(nvg, popupGeom, popupBoxShadow)
    else
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px + 2, py + 2, calW, calH, borderRadius)
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

    -- Header: Month Year navigation
    local headerY = contentY

    -- Nav button layout (aligned with Calendar: simple btnSize-based rect)
    local btnSize = navBtnSize
    local prevX = contentX
    local prevBtnY = headerY + (headerH - btnSize) / 2
    local nextX = px + calW - 32
    local navRadius = self.props.navBtnRadius or (btnSize / 2)
    local navBtnBg = self.props.navBtnBgColor

    self.prevBtnBounds_ = { x = prevX, y = prevBtnY, w = btnSize, h = btnSize }
    self.nextBtnBounds_ = { x = nextX, y = prevBtnY, w = btnSize, h = btnSize }

    -- Prev button：圆角描边框（默认白色，替代原来 navBtnBgColor 的填底色）
    local navBtnBorderColor = self.props.navBtnBorderColor or { 255, 255, 255, 255 }
    local navBtnBorderWidth = self.props.navBtnBorderWidth or 1
    if navBtnBorderWidth > 0 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, prevX, prevBtnY, btnSize, btnSize, navRadius)
        nvgStrokeColor(nvg, nvgRGBA(navBtnBorderColor[1], navBtnBorderColor[2], navBtnBorderColor[3], navBtnBorderColor[4] or 255))
        nvgStrokeWidth(nvg, navBtnBorderWidth)
        nvgStroke(nvg)
    end
    if self.hoverNav_ == "prev" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, prevX, prevBtnY, btnSize, btnSize, navRadius)
        local hc = self.props.navBtnHoverBgColor or Theme.Color("surfaceHover")
        nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4] or 255))
        nvgFill(nvg)
    end
    local arrowSize = btnSize * 0.25
    local cx, cy = prevX + btnSize / 2, prevBtnY + btnSize / 2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx + arrowSize * 0.3, cy - arrowSize)
    nvgLineTo(nvg, cx - arrowSize * 0.7, cy)
    nvgLineTo(nvg, cx + arrowSize * 0.3, cy + arrowSize)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgFill(nvg)

    -- Next button：圆角描边框（默认白色）
    if navBtnBorderWidth > 0 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, nextX, prevBtnY, btnSize, btnSize, navRadius)
        nvgStrokeColor(nvg, nvgRGBA(navBtnBorderColor[1], navBtnBorderColor[2], navBtnBorderColor[3], navBtnBorderColor[4] or 255))
        nvgStrokeWidth(nvg, navBtnBorderWidth)
        nvgStroke(nvg)
    end
    if self.hoverNav_ == "next" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, nextX, prevBtnY, btnSize, btnSize, navRadius)
        local hc = self.props.navBtnHoverBgColor or Theme.Color("surfaceHover")
        nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4] or 255))
        nvgFill(nvg)
    end
    cx, cy = nextX + btnSize / 2, prevBtnY + btnSize / 2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - arrowSize * 0.3, cy - arrowSize)
    nvgLineTo(nvg, cx + arrowSize * 0.7, cy)
    nvgLineTo(nvg, cx - arrowSize * 0.3, cy + arrowSize)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgFill(nvg)

    -- Month Year text
    local monthYearText = formatMonthTitle(self.viewYear_, self.viewMonth_, self.props.monthTitleFormat, self.props.monthNames, self.props.monthNamesShort)
    nvgFontSize(nvg, Theme.FontSize(self.headerSize_))
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.monthFontWeight or self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgText(nvg, px + calW / 2, headerY + headerH / 2, monthYearText)

    -- Weekday headers
    local weekdayY = headerY + headerH + 4
    nvgFontSize(nvg, self.props.weekdayFontSize and Theme.FontSize(self.props.weekdayFontSize) or self.fontSize_ * 0.85)
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.weekdayFontWeight or self.props.fontWeight))
    nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)

    local weekdayNames = self.props.weekdayNames or WEEKDAY_NAMES
    for i, dayName in ipairs(weekdayNames) do
        local dayX = contentX + (i - 1) * cellSize + cellSize / 2
        nvgText(nvg, dayX, weekdayY + cellSize / 2, dayName)
    end

    -- Calendar grid
    local gridY = weekdayY + cellSize
    local daysInMonth = getDaysInMonth(self.viewYear_, self.viewMonth_)
    local firstDay = getFirstDayOfMonth(self.viewYear_, self.viewMonth_)
    local today = os.date("*t")
    local cellPadding = 2

    self.dayCells_ = {}
    local day = 1
    local row = 0

    while day <= daysInMonth do
        for col = 0, 6 do
            if row == 0 and col < firstDay then
                -- Empty cell before month starts
            elseif day <= daysInMonth then
                local cellX = contentX + col * cellSize
                local cellY = gridY + row * cellSize
                local centerX = cellX + cellSize / 2
                local centerY = cellY + cellSize / 2

                local isSelected = self:IsDateSelected(self.viewYear_, self.viewMonth_, day)
                local isDisabled = self:IsDateDisabled(self.viewYear_, self.viewMonth_, day)
                local isToday = today.year == self.viewYear_ and today.month == self.viewMonth_ and today.day == day
                local isHovered = self.hoverDay_ == day
                local isStart, isEnd = self:IsRangeEdge(self.viewYear_, self.viewMonth_, day)

                -- Store cell bounds
                self.dayCells_[day] = { x = cellX, y = cellY, w = cellSize, h = cellSize }

                -- Draw range highlight (between start and end)
                if self.selectionMode_ == "range" and isSelected and not isStart and not isEnd then
                    nvgBeginPath(nvg)
                    nvgRect(nvg, cellX, cellY + cellPadding, cellSize, cellSize - cellPadding * 2)
                    local pc = self.primaryColor_
                    if type(pc) == "table" then
                        nvgFillColor(nvg, nvgRGBA(pc[1] or 0, pc[2] or 0, pc[3] or 0, 50))
                    else
                        nvgFillColor(nvg, nvgTransRGBAf(pc, 0.2))
                    end
                    nvgFill(nvg)
                end

                -- Draw selection/hover highlight
                local dayCellR = cellSize / 2 - cellPadding
                local dayCellRadius = self.props.cellBorderRadius or self.props.borderRadius or dayCellR
                if isSelected then
                    local selBg = self.props.selectedBgColor
                    local selBorder = self.props.selectedBorderColor
                    local selectedDayBoxShadow = self.props.selectedDayBoxShadow
                    if selectedDayBoxShadow and selectedDayBoxShadow ~= false then
                        local selectedDayGeom = self:GetShapeGeometry({
                            x = centerX - dayCellR,
                            y = centerY - dayCellR,
                            w = dayCellR * 2,
                            h = dayCellR * 2,
                        }, nil, dayCellRadius)
                        self:RenderBoxShadows(nvg, selectedDayGeom, selectedDayBoxShadow)
                    end
                    if selBg ~= nil and selBg ~= false then
                        nvgBeginPath(nvg)
                        nvgRoundedRect(nvg, centerX - dayCellR, centerY - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
                        nvgFillColor(nvg, nvgRGBA(selBg[1], selBg[2], selBg[3], selBg[4] or 255))
                        nvgFill(nvg)
                    elseif selBg == nil and not selBorder then
                        nvgBeginPath(nvg)
                        nvgRoundedRect(nvg, centerX - dayCellR, centerY - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
                        nvgFillColor(nvg, Theme.ToNvgColor(self.primaryColor_))
                        nvgFill(nvg)
                    end
                    if selBorder then
                        nvgBeginPath(nvg)
                        nvgRoundedRect(nvg, centerX - dayCellR, centerY - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
                        nvgStrokeColor(nvg, nvgRGBA(selBorder[1], selBorder[2], selBorder[3], selBorder[4] or 255))
                        nvgStrokeWidth(nvg, self.props.selectedBorderWidth or 2)
                        nvgStroke(nvg)
                    end
                elseif isHovered then
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, centerX - dayCellR, centerY - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
                    local hc = self.props.dayHoverBgColor or Theme.Color("surfaceHover")
                    nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4] or 255))
                    nvgFill(nvg)
                end

                -- Draw today indicator
                if isToday and not isSelected then
                    local todayBorder = self.props.todayBorderColor or self.primaryColor_
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, centerX - dayCellR, centerY - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
                    nvgStrokeColor(nvg, nvgRGBA(todayBorder[1], todayBorder[2], todayBorder[3], todayBorder[4] or 255))
                    nvgStrokeWidth(nvg, 1)
                    nvgStroke(nvg)
                end

                -- Draw day number
                local dayWeight = isSelected
                    and (self.props.selectedFontWeight or self.props.dayFontWeight or self.props.fontWeight)
                    or (self.props.dayFontWeight or self.props.fontWeight)
                nvgFontSize(nvg, self.props.dayFontSize and Theme.FontSize(self.props.dayFontSize) or self.fontSize_)
                nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, dayWeight))
                nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)

                if isDisabled then
                    nvgFillColor(nvg, Theme.NvgColor("textDisabled"))
                elseif isSelected then
                    local hasBgFill = self.props.selectedBgColor ~= nil and self.props.selectedBgColor ~= false
                        or (self.props.selectedBgColor == nil and not self.props.selectedBorderColor)
                    local selText = self.props.selectedTextColor
                        or (hasBgFill and {255, 255, 255, 255} or self.props.selectedBorderColor)
                        or {255, 255, 255, 255}
                    nvgFillColor(nvg, nvgRGBA(selText[1], selText[2], selText[3], selText[4] or 255))
                elseif isToday then
                    local todayText = self.props.todayTextColor or self.primaryColor_
                    nvgFillColor(nvg, nvgRGBA(todayText[1], todayText[2], todayText[3], todayText[4] or 255))
                else
                    nvgFillColor(nvg, Theme.NvgColor("text"))
                end

                nvgText(nvg, centerX, centerY, tostring(day))

                day = day + 1
            end
        end
        row = row + 1
    end

    -- Today button (right-aligned, centered between actual grid bottom and panel bottom)
    local todayBtnW = self.props.todayBtnWidth or 88
    local todayBtnH = self.props.todayBtnHeight or 40
    local actualGridBottom = gridY + row * cellSize
    local availableSpace = (py + calH) - actualGridBottom
    local todayMargin = (availableSpace - todayBtnH) / 2
    local todayBtnX = px + calW - todayBtnW - todayMargin
    local todayBtnY = actualGridBottom + todayMargin
    local todayBtnRadius = self.props.todayBtnRadius or 12

    local todayBgColor = self.props.todayBtnBgColor or self.props.navBtnBgColor or Theme.Color("surfaceAlt")
    local todayHover = self.hoverNav_ == "today"
    local todayGeom = self:GetShapeGeometry({ x = todayBtnX, y = todayBtnY, w = todayBtnW, h = todayBtnH }, nil, todayBtnRadius)
    local todayBtnBoxShadow = self.props.todayBtnBoxShadow
    if todayBtnBoxShadow and todayBtnBoxShadow ~= false then
        self:RenderBoxShadows(nvg, todayGeom, todayBtnBoxShadow)
    end
    self:CreateShapePath(nvg, todayGeom)
    if todayHover then
        local hc = Style.Lighten(todayBgColor, 0.15)
        nvgFillColor(nvg, nvgRGBA(hc[1], hc[2], hc[3], hc[4] or 255))
    else
        nvgFillColor(nvg, nvgRGBA(todayBgColor[1], todayBgColor[2], todayBgColor[3], todayBgColor[4] or 255))
    end
    nvgFill(nvg)

    local todayBtnBorderColor = self.props.todayBtnBorderColor
    local todayBtnBorderWidth = self.props.todayBtnBorderWidth
    if todayBtnBorderColor and todayBtnBorderWidth and todayBtnBorderWidth > 0 then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, todayBtnX, todayBtnY, todayBtnW, todayBtnH, todayBtnRadius)
        nvgStrokeColor(nvg, nvgRGBA(todayBtnBorderColor[1], todayBtnBorderColor[2], todayBtnBorderColor[3], todayBtnBorderColor[4] or 255))
        nvgStrokeWidth(nvg, todayBtnBorderWidth)
        nvgStroke(nvg)
    end

    local todayFontSize = self.props.todayBtnFontSize and Theme.FontSize(self.props.todayBtnFontSize) or Theme.FontSize(12)
    local todayFontFace = Theme.FontFace(self.props.fontFamily, "bold")
    local todayLabel = self.props.todayLabel or "Today"
    local todayIcon = self.props.todayIcon
    nvgFontSize(nvg, todayFontSize)
    nvgFontFace(nvg, todayFontFace)
    nvgFillColor(nvg, Theme.ToNvgColor(self.props.todayBtnTextColor or self.primaryColor_))
    if todayIcon then
        local labelWidth = UI.MeasureTextWidth(todayLabel, todayFontSize, todayFontFace)
        local gap = 4
        if type(todayIcon) == "table" and todayIcon.Render then
            local iconLayout = todayIcon.GetLayout and todayIcon:GetLayout()
            local iconWidth = (iconLayout and iconLayout.w and iconLayout.w > 0 and iconLayout.w)
                or (todayIcon.props and todayIcon.props.width)
                or todayFontSize
            local iconHeight = (iconLayout and iconLayout.h and iconLayout.h > 0 and iconLayout.h)
                or (todayIcon.props and todayIcon.props.height)
                or todayFontSize
            local startX = todayBtnX + (todayBtnW - iconWidth - gap - labelWidth) / 2
            todayIcon.renderOffsetX_ = startX
            todayIcon.renderOffsetY_ = todayBtnY + (todayBtnH - iconHeight) / 2
            todayIcon.renderWidth_ = iconWidth
            todayIcon.renderHeight_ = iconHeight
            todayIcon:Render(nvg)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, Theme.ToNvgColor(self.props.todayBtnTextColor or self.primaryColor_))
            nvgText(nvg, startX + iconWidth + gap, todayBtnY + todayBtnH / 2, todayLabel)
        else
            local iconText = tostring(todayIcon)
            local iconWidth = UI.MeasureTextWidth(iconText, todayFontSize, todayFontFace)
            local startX = todayBtnX + (todayBtnW - iconWidth - gap - labelWidth) / 2
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, Theme.ToNvgColor(self.props.todayIconColor or self.props.todayBtnTextColor or self.primaryColor_))
            nvgText(nvg, startX, todayBtnY + todayBtnH / 2, iconText)
            nvgFillColor(nvg, Theme.ToNvgColor(self.props.todayBtnTextColor or self.primaryColor_))
            nvgText(nvg, startX + iconWidth + gap, todayBtnY + todayBtnH / 2, todayLabel)
        end
    else
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, todayBtnX + todayBtnW / 2, todayBtnY + todayBtnH / 2, todayLabel)
    end

    self.todayBtnBounds_ = { x = todayBtnX, y = todayBtnY, w = todayBtnW, h = todayBtnH }
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function DatePicker:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function DatePicker:HitTest(x, y)
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

function DatePicker:OnPointerMove(event)
    if not event then return end
    if not self.isOpen_ then return end

    -- Use event coords directly (all bounds are in HitTest coords)
    local px = event.x
    local py = event.y

    -- Check navigation buttons
    self.hoverNav_ = nil
    if self:PointInBounds(px, py, self.prevBtnBounds_) then
        self.hoverNav_ = "prev"
    elseif self:PointInBounds(px, py, self.nextBtnBounds_) then
        self.hoverNav_ = "next"
    elseif self:PointInBounds(px, py, self.todayBtnBounds_) then
        self.hoverNav_ = "today"
    end

    -- Check day cells
    self.hoverDay_ = nil
    if self.dayCells_ then
        for day, bounds in pairs(self.dayCells_) do
            if self:PointInBounds(px, py, bounds) then
                self.hoverDay_ = day
                break
            end
        end
    end
end

function DatePicker:OnMouseLeave(event)
    self.hoverDay_ = nil
    self.hoverNav_ = nil
end

function DatePicker:OnClick(event)
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

    -- Check today button first (may be outside strict calendar grid area)
    if self:PointInBounds(px, py, self.todayBtnBounds_) then
        self:GoToToday()
        return true
    end

    -- Check if clicking outside calendar
    if not self:PointInBounds(px, py, self.calendarBounds_) then
        -- closeOnSelect=false 时点空白也不收起（只靠再次点输入框 toggle 收回）
        if self.closeOnSelect_ then self:Close() end
        return true
    end

    -- Check navigation buttons
    if self:PointInBounds(px, py, self.prevBtnBounds_) then
        self:PrevMonth()
        return true
    elseif self:PointInBounds(px, py, self.nextBtnBounds_) then
        self:NextMonth()
        return true
    end

    -- Check day cells
    if self.dayCells_ then
        for day, bounds in pairs(self.dayCells_) do
            if self:PointInBounds(px, py, bounds) then
                self:SelectDate(self.viewYear_, self.viewMonth_, day)
                return true
            end
        end
    end

    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a basic date picker
---@param props table|nil
---@return DatePicker
function DatePicker.Basic(props)
    return DatePicker(props)
end

--- Create a date range picker
---@param props table|nil
---@return DatePicker
function DatePicker.Range(props)
    props = props or {}
    props.selectionMode = "range"
    props.placeholder = props.placeholder or "Select date range"
    return DatePicker(props)
end

--- Create a multi-date picker
---@param props table|nil
---@return DatePicker
function DatePicker.Multiple(props)
    props = props or {}
    props.selectionMode = "multiple"
    props.placeholder = props.placeholder or "Select dates"
    return DatePicker(props)
end

--- Create a birthday picker
---@param props table|nil
---@return DatePicker
function DatePicker.Birthday(props)
    props = props or {}
    props.placeholder = props.placeholder or "Select birthday"
    props.format = props.format or "mm/dd/yyyy"
    -- Max date is today
    local now = os.date("*t")
    props.maxDate = props.maxDate or { year = now.year, month = now.month, day = now.day }
    return DatePicker(props)
end

--- Create a future date picker (for scheduling)
---@param props table|nil
---@return DatePicker
function DatePicker.Future(props)
    props = props or {}
    props.placeholder = props.placeholder or "Select future date"
    -- Min date is today
    local now = os.date("*t")
    props.minDate = props.minDate or { year = now.year, month = now.month, day = now.day }
    return DatePicker(props)
end

--- Create with specific date format
---@param format string Date format string
---@param props table|nil
---@return DatePicker
function DatePicker.WithFormat(format, props)
    props = props or {}
    props.format = format
    return DatePicker(props)
end

return DatePicker
