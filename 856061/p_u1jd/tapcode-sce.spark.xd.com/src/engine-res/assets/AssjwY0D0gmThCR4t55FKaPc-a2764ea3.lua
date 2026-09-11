-- ============================================================================
-- Calendar Widget
-- Full calendar display with event support
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class CalendarProps : WidgetProps
---@field variant? string "default" | "compact" | "full" (default: "default")
---@field showWeekNumbers? boolean Show week numbers column
---@field firstDayOfWeek? number 0 = Sunday, 1 = Monday (default: 0)
---@field year? number Initial year
---@field month? number Initial month
---@field selectedDate? table Initial selected date {year, month, day}
---@field events? table[] Calendar events array
---@field cellSize? number Cell size in pixels (default: 40)
---@field headerHeight? number Header height (default: 48)
---@field weekdayHeight? number Weekday row height (default: 32)
---@field monthFontWeight? string Font weight for month title (default: fontWeight)
---@field weekdayFontWeight? string Font weight for weekday labels (default: fontWeight)
---@field dayFontWeight? string Font weight for day numbers (default: fontWeight)
---@field selectedFontWeight? string Font weight for selected day (default: dayFontWeight or fontWeight)
---@field selectedDayBoxShadow? table|false Selected day cell shadow; false disables shadow
---@field monthTitleFormat? string Month title format, e.g. yyyy年m月
---@field monthNames? string[] Month names for title formatting
---@field weekdayNames? string[] Weekday labels for header
---@field cellBorderRadius? number Day cell border radius (default: circle)
---@field onDateSelect? fun(calendar: Calendar, date: table) Date selection callback
---@field onMonthChange? fun(calendar: Calendar, year: number, month: number) Month change callback
---@field onEventClick? fun(calendar: Calendar, events: table[], date: table) Event click callback

---@class Calendar : Widget
---@overload fun(props?: CalendarProps): Calendar
---@field props CalendarProps
---@field new fun(self, props?: CalendarProps): Calendar
local Calendar = Widget:Extend("Calendar")

-- ============================================================================
-- Date utilities
-- ============================================================================

local function getDaysInMonth(year, month)
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 then
        if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
            return 29
        end
    end
    return days[month]
end

local function getFirstDayOfMonth(year, month)
    local t = os.time({ year = year, month = month, day = 1 })
    return tonumber(os.date("%w", t))
end

local MONTH_NAMES = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
}

local function formatMonthTitle(year, month, format, monthNames)
    monthNames = monthNames or MONTH_NAMES
    if not format then
        return (monthNames[month] or tostring(month)) .. " " .. tostring(year)
    end

    local fullToken = "{FULL}"
    local result = format:gsub("MMMM", fullToken)
    result = result:gsub("yyyy", tostring(year))
    result = result:gsub("yy", string.format("%02d", year % 100))
    result = result:gsub("MM", string.format("%02d", month))
    result = result:gsub("M", tostring(month))
    result = result:gsub("mm", string.format("%02d", month))
    result = result:gsub("m", tostring(month))
    result = result:gsub(fullToken, monthNames[month] or tostring(month))
    return result
end

local WEEKDAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local WEEKDAY_SHORT = { "S", "M", "T", "W", "T", "F", "S" }

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props CalendarProps?
function Calendar:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Calendar")
    Style.ApplyDefaults(props, themeStyle)

    -- Calendar props
    self.variant_ = props.variant or "default"  -- default, compact, full
    self.showWeekNumbers_ = props.showWeekNumbers or false
    self.firstDayOfWeek_ = props.firstDayOfWeek or 0  -- 0 = Sunday, 1 = Monday

    -- Initial date
    local now = os.date("*t")
    self.year_ = props.year or now.year
    self.month_ = props.month or now.month
    self.selectedDate_ = props.selectedDate

    -- Events
    self.events_ = props.events or {}  -- { date = "2025-01-15", title = "Event", color = "primary" }

    -- Visual
    self.cellSize_ = props.cellSize or 40
    self.headerHeight_ = props.headerHeight or 48
    self.weekdayHeight_ = props.weekdayHeight or 32

    -- State
    self.hoverDay_ = nil
    self.hoverNav_ = nil

    -- Callbacks
    self.onDateSelect_ = props.onDateSelect
    self.onMonthChange_ = props.onMonthChange
    self.onEventClick_ = props.onEventClick

    -- Calculate dimensions
    local cols = self.showWeekNumbers_ and 8 or 7
    props.width = props.width or (self.cellSize_ * cols)
    props.height = props.height or (self.headerHeight_ + self.weekdayHeight_ + self.cellSize_ * 6)

    Widget.Init(self, props)
end

-- ============================================================================
-- Navigation
-- ============================================================================

function Calendar:GetYear()
    return self.year_
end

function Calendar:GetMonth()
    return self.month_
end

function Calendar:SetMonth(year, month)
    if month < 1 then
        month = 12
        year = year - 1
    elseif month > 12 then
        month = 1
        year = year + 1
    end

    self.year_ = year
    self.month_ = month

    if self.onMonthChange_ then
        self.onMonthChange_(self, year, month)
    end
end

function Calendar:PrevMonth()
    self:SetMonth(self.year_, self.month_ - 1)
end

function Calendar:NextMonth()
    self:SetMonth(self.year_, self.month_ + 1)
end

function Calendar:PrevYear()
    self:SetMonth(self.year_ - 1, self.month_)
end

function Calendar:NextYear()
    self:SetMonth(self.year_ + 1, self.month_)
end

function Calendar:GoToToday()
    local now = os.date("*t")
    self:SetMonth(now.year, now.month)
end

-- ============================================================================
-- Selection
-- ============================================================================

function Calendar:GetSelectedDate()
    return self.selectedDate_
end

function Calendar:SetSelectedDate(date)
    self.selectedDate_ = date
end

function Calendar:SelectDate(year, month, day)
    self.selectedDate_ = { year = year, month = month, day = day }

    if self.onDateSelect_ then
        self.onDateSelect_(self, self.selectedDate_)
    end
end

-- ============================================================================
-- Events
-- ============================================================================

function Calendar:GetEvents()
    return self.events_
end

function Calendar:SetEvents(events)
    self.events_ = events or {}
end

function Calendar:AddEvent(event)
    table.insert(self.events_, event)
end

function Calendar:GetEventsForDate(year, month, day)
    local dateStr = string.format("%04d-%02d-%02d", year, month, day)
    local result = {}

    for _, event in ipairs(self.events_) do
        if event.date == dateStr then
            table.insert(result, event)
        end
    end

    return result
end

-- ============================================================================
-- Render
-- ============================================================================

function Calendar:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()
    local theme = Theme.GetTheme()

    -- No scale needed - nvgScale handles it
    local cellSize = self.cellSize_
    local headerHeight = self.headerHeight_
    local weekdayHeight = self.weekdayHeight_

    Widget.Render(self, nvg)

    -- Render header
    self:RenderHeader(nvg, x, y, w, headerHeight)

    -- Render weekday names
    local weekdayY = y + headerHeight
    self:RenderWeekdays(nvg, x, weekdayY, w, cellSize, weekdayHeight)

    -- Render calendar grid
    local gridY = weekdayY + weekdayHeight
    self:RenderGrid(nvg, x, gridY, w, cellSize)
end

function Calendar:RenderHeader(nvg, x, y, w, headerHeight)
    local theme = Theme.GetTheme()

    -- Month/Year text
    local monthYear = formatMonthTitle(self.year_, self.month_, self.props.monthTitleFormat, self.props.monthNames)
    nvgFontSize(nvg, Theme.FontSizeOf("subtitle"))
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.monthFontWeight or self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgText(nvg, x + w / 2, y + headerHeight / 2, monthYear)

    -- Navigation buttons
    local btnSize = 32
    local margin = 8
    local prevX = x + margin
    local nextX = x + w - btnSize - margin
    local btnY = y + (headerHeight - btnSize) / 2

    self.prevBtnBounds_ = { x = prevX, y = btnY, w = btnSize, h = btnSize }
    self.nextBtnBounds_ = { x = nextX, y = btnY, w = btnSize, h = btnSize }

    -- Nav button radius: independent from day cell borderRadius
    local navRadius = self.props.navBtnRadius or (btnSize / 2)
    local navBtnBg = self.props.navBtnBgColor

    -- Prev button
    if navBtnBg then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, prevX, btnY, btnSize, btnSize, navRadius)
        nvgFillColor(nvg, nvgRGBA(navBtnBg[1], navBtnBg[2], navBtnBg[3], navBtnBg[4] or 255))
        nvgFill(nvg)
    end
    if self.hoverNav_ == "prev" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, prevX, btnY, btnSize, btnSize, navRadius)
        nvgFillColor(nvg, Theme.NvgColor("surfaceHover"))
        nvgFill(nvg)
    end
    -- Arrow triangle (geometric, replaces emoji)
    local arrowSize = btnSize * 0.25
    local cx, cy = prevX + btnSize / 2, btnY + btnSize / 2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx + arrowSize * 0.3, cy - arrowSize)
    nvgLineTo(nvg, cx - arrowSize * 0.7, cy)
    nvgLineTo(nvg, cx + arrowSize * 0.3, cy + arrowSize)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgFill(nvg)

    -- Next button
    if navBtnBg then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, nextX, btnY, btnSize, btnSize, navRadius)
        nvgFillColor(nvg, nvgRGBA(navBtnBg[1], navBtnBg[2], navBtnBg[3], navBtnBg[4] or 255))
        nvgFill(nvg)
    end
    if self.hoverNav_ == "next" then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, nextX, btnY, btnSize, btnSize, navRadius)
        nvgFillColor(nvg, Theme.NvgColor("surfaceHover"))
        nvgFill(nvg)
    end
    cx, cy = nextX + btnSize / 2, btnY + btnSize / 2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - arrowSize * 0.3, cy - arrowSize)
    nvgLineTo(nvg, cx + arrowSize * 0.7, cy)
    nvgLineTo(nvg, cx - arrowSize * 0.3, cy + arrowSize)
    nvgClosePath(nvg)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgFill(nvg)
end

function Calendar:RenderWeekdays(nvg, x, y, w, cellSize, weekdayHeight)
    local theme = Theme.GetTheme()
    local startCol = self.showWeekNumbers_ and 1 or 0

    nvgFontSize(nvg, Theme.FontSizeOf("small"))
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.weekdayFontWeight or self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Theme.NvgColor("textSecondary"))

    -- Week number header
    if self.showWeekNumbers_ then
        nvgText(nvg, x + cellSize / 2, y + weekdayHeight / 2, "Wk")
    end

    -- Weekday names
    local weekdayNames = self.props.weekdayNames or (self.variant_ == "compact" and WEEKDAY_SHORT or WEEKDAY_NAMES)
    for i = 0, 6 do
        local dayIndex = (i + self.firstDayOfWeek_) % 7 + 1
        local dayName = weekdayNames[dayIndex] or ""
        local cellX = x + (startCol + i) * cellSize
        nvgText(nvg, cellX + cellSize / 2, y + weekdayHeight / 2, dayName)
    end
end

function Calendar:RenderGrid(nvg, x, y, w, cellSize)
    local theme = Theme.GetTheme()
    local daysInMonth = getDaysInMonth(self.year_, self.month_)
    local firstDay = getFirstDayOfMonth(self.year_, self.month_)
    local startCol = self.showWeekNumbers_ and 1 or 0

    -- Adjust for first day of week
    firstDay = (firstDay - self.firstDayOfWeek_ + 7) % 7

    local today = os.date("*t")
    self.dayCells_ = {}

    local day = 1
    local row = 0

    while day <= daysInMonth do
        -- Week number
        if self.showWeekNumbers_ then
            local weekNum = self:GetWeekNumber(self.year_, self.month_, day)
            nvgFontSize(nvg, Theme.FontSizeOf("tiny"))
            nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
            nvgText(nvg, x + cellSize / 2, y + row * cellSize + cellSize / 2, tostring(weekNum))
        end

        for col = 0, 6 do
            if row == 0 and col < firstDay then
                -- Empty cell
            elseif day <= daysInMonth then
                local cellX = x + (startCol + col) * cellSize
                local cellY = y + row * cellSize

                self.dayCells_[day] = { x = cellX, y = cellY, w = cellSize, h = cellSize }

                local isToday = today.year == self.year_ and today.month == self.month_ and today.day == day
                local isSelected = self.selectedDate_ and
                                   self.selectedDate_.year == self.year_ and
                                   self.selectedDate_.month == self.month_ and
                                   self.selectedDate_.day == day
                local isHovered = self.hoverDay_ == day
                local events = self:GetEventsForDate(self.year_, self.month_, day)

                self:RenderDay(nvg, cellX, cellY, day, isToday, isSelected, isHovered, events, cellSize)

                day = day + 1
            end
        end
        row = row + 1
    end
end

function Calendar:RenderDay(nvg, x, y, day, isToday, isSelected, isHovered, events, cellSize)
    local theme = Theme.GetTheme()
    local centerX = x + cellSize / 2
    local centerY = y + cellSize / 2
    local offset = 4
    local padding = 4

    -- Day cell radius: cellBorderRadius > borderRadius > circle (default)
    local dayCellR = cellSize / 2 - padding
    local dayCellRadius = self.props.cellBorderRadius ~= nil and self.props.cellBorderRadius
        or (self.props.borderRadius ~= nil and self.props.borderRadius or dayCellR)

    -- Selection/hover background
    if isSelected then
        local selectedDayBoxShadow = self.props.selectedDayBoxShadow
        if selectedDayBoxShadow and selectedDayBoxShadow ~= false then
            local selectedGeom = self:GetShapeGeometry({
                x = centerX - dayCellR,
                y = centerY - offset - dayCellR,
                w = dayCellR * 2,
                h = dayCellR * 2,
            }, nil, dayCellRadius)
            self:RenderBoxShadows(nvg, selectedGeom, selectedDayBoxShadow)
        end

        local selBg = self.props.selectedBgColor
        local selBorder = self.props.selectedBorderColor
        -- Background fill: false=no fill, table=custom, nil+no border=original primary fill
        if selBg ~= nil and selBg ~= false then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, centerX - dayCellR, centerY - offset - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
            nvgFillColor(nvg, nvgRGBA(selBg[1], selBg[2], selBg[3], selBg[4] or 255))
            nvgFill(nvg)
        elseif selBg == nil and not selBorder then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, centerX - dayCellR, centerY - offset - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
            nvgFillColor(nvg, Theme.NvgColor("primary"))
            nvgFill(nvg)
        end
        if selBorder then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, centerX - dayCellR, centerY - offset - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
            nvgStrokeColor(nvg, nvgRGBA(selBorder[1], selBorder[2], selBorder[3], selBorder[4] or 255))
            nvgStrokeWidth(nvg, self.props.selectedBorderWidth or 2)
            nvgStroke(nvg)
        end
    elseif isHovered then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, centerX - dayCellR, centerY - offset - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
        nvgFillColor(nvg, Theme.NvgColor("surfaceHover"))
        nvgFill(nvg)
    end

    -- Today indicator
    if isToday and not isSelected then
        local todayBorder = self.props.todayBorderColor or Theme.Color("primary")
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, centerX - dayCellR, centerY - offset - dayCellR, dayCellR * 2, dayCellR * 2, dayCellRadius)
        nvgStrokeColor(nvg, nvgRGBA(todayBorder[1], todayBorder[2], todayBorder[3], todayBorder[4] or 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end

    -- Day number
    local dayWeight = isSelected
        and (self.props.selectedFontWeight or self.props.dayFontWeight or self.props.fontWeight)
        or (self.props.dayFontWeight or self.props.fontWeight)
    nvgFontSize(nvg, Theme.FontSizeOf("body"))
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, dayWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)

    if isSelected then
        local hasBgFill = self.props.selectedBgColor ~= nil and self.props.selectedBgColor ~= false
            or (self.props.selectedBgColor == nil and not self.props.selectedBorderColor)
        local selText = self.props.selectedTextColor
            or (hasBgFill and {255, 255, 255, 255} or self.props.selectedBorderColor)
            or {255, 255, 255, 255}
        nvgFillColor(nvg, nvgRGBA(selText[1], selText[2], selText[3], selText[4] or 255))
    elseif isToday then
        local todayText = self.props.todayTextColor or Theme.Color("primary")
        nvgFillColor(nvg, nvgRGBA(todayText[1], todayText[2], todayText[3], todayText[4] or 255))
    else
        nvgFillColor(nvg, Theme.NvgColor("text"))
    end

    nvgText(nvg, centerX, centerY - offset, tostring(day))

    -- Event indicators
    if #events > 0 then
        local dotY = centerY + cellSize / 2 - 10
        local dotSize = 4
        local dotSpacing = 2
        local totalWidth = #events * (dotSize + dotSpacing) - dotSpacing
        local startX = centerX - totalWidth / 2

        for i, event in ipairs(events) do
            local dotX = startX + (i - 1) * (dotSize + dotSpacing)
            nvgBeginPath(nvg)
            nvgCircle(nvg, dotX + dotSize / 2, dotY, dotSize / 2)

            local color = event.color
            if type(color) == "string" then
                color = Theme.Color(color)
            end
            nvgFillColor(nvg, Theme.ToNvgColor(color) or Theme.NvgColor("primary"))
            nvgFill(nvg)
        end
    end
end

function Calendar:GetWeekNumber(year, month, day)
    local t = os.time({ year = year, month = month, day = day })
    return tonumber(os.date("%W", t)) + 1
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Calendar:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function Calendar:OnPointerMove(event)
    if not event then return end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y

    -- Convert screen coords to render coords
    local px = event.x + offsetX
    local py = event.y + offsetY

    -- Check navigation hover
    self.hoverNav_ = nil
    if self:PointInBounds(px, py, self.prevBtnBounds_) then
        self.hoverNav_ = "prev"
    elseif self:PointInBounds(px, py, self.nextBtnBounds_) then
        self.hoverNav_ = "next"
    end

    -- Check day hover
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

function Calendar:OnMouseLeave()
    self.hoverNav_ = nil
    self.hoverDay_ = nil
end

function Calendar:OnClick(event)
    if not event then return end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y

    -- Convert screen coords to render coords
    local px = event.x + offsetX
    local py = event.y + offsetY

    -- Navigation
    if self:PointInBounds(px, py, self.prevBtnBounds_) then
        self:PrevMonth()
        return true
    elseif self:PointInBounds(px, py, self.nextBtnBounds_) then
        self:NextMonth()
        return true
    end

    -- Day selection
    if self.dayCells_ then
        for day, bounds in pairs(self.dayCells_) do
            if self:PointInBounds(px, py, bounds) then
                self:SelectDate(self.year_, self.month_, day)

                -- Check for event click
                local events = self:GetEventsForDate(self.year_, self.month_, day)
                if #events > 0 and self.onEventClick_ then
                    self.onEventClick_(self, events, { year = self.year_, month = self.month_, day = day })
                end

                return true
            end
        end
    end

    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a basic calendar
---@param props table|nil
---@return Calendar
function Calendar.Basic(props)
    return Calendar(props)
end

--- Create a compact calendar
---@param props table|nil
---@return Calendar
function Calendar.Compact(props)
    props = props or {}
    props.variant = "compact"
    props.cellSize = 32
    return Calendar(props)
end

--- Create a calendar with week numbers
---@param props table|nil
---@return Calendar
function Calendar.WithWeekNumbers(props)
    props = props or {}
    props.showWeekNumbers = true
    return Calendar(props)
end

--- Create a calendar with events
---@param events table[]
---@param props table|nil
---@return Calendar
function Calendar.WithEvents(events, props)
    props = props or {}
    props.events = events
    return Calendar(props)
end

--- Create a calendar starting on Monday
---@param props table|nil
---@return Calendar
function Calendar.MondayFirst(props)
    props = props or {}
    props.firstDayOfWeek = 1
    return Calendar(props)
end

return Calendar
