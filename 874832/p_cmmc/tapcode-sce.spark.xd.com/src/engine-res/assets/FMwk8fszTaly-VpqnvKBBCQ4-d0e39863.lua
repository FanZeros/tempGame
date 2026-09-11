-- ============================================================================
-- Table Widget
-- Data table with sorting, selection, and pagination
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class TableColumn
---@field key string Column data key
---@field label? string Column header label
---@field width? number|string Column width (number or "XX%")
---@field align? string "left" | "center" | "right"
---@field sortable? boolean Allow sorting this column
---@field sortFn? fun(a: any, b: any): boolean|nil Custom sort function
---@field render? fun(value: any, row: table, index: number): string|nil Custom cell renderer

---@class TableProps : WidgetProps
---@field columns? TableColumn[] Column definitions
---@field data? table[] Row data array
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field variant? string "default" | "striped" | "bordered" (default: "default")
---@field sortable? boolean Enable column sorting (default: false)
---@field selectable? boolean Enable row selection (default: false)
---@field multiSelect? boolean Allow multiple row selection (default: false)
---@field headerFontWeight? string Font weight for header text (default: fontWeight)
---@field showHeader? boolean Show table header (default: true)
---@field stickyHeader? boolean Sticky header on scroll (default: false)
---@field hoverable? boolean Highlight rows on hover (default: true)
---@field sortColumn? string Initial sort column key
---@field sortDirection? string "asc" | "desc" (default: "asc")
---@field pagination? boolean Enable pagination (default: false)
---@field pageSize? number Rows per page (default: 10)
---@field currentPage? number Current page number (default: 1)
---@field rowHeight? number Custom row height
---@field fontSize? number Custom font size
---@field headerSize? number Custom header font size
---@field cellPadding? number Custom cell padding
---@field headerBorderRadius? number|table Header row radius
---@field lastRowBorderRadius? number|table Last row radius
---@field onRowClick? fun(table: Table, row: table, index: number) Row click callback
---@field onRowSelect? fun(table: Table, selectedIndices: number[]) Row selection callback
---@field onSort? fun(table: Table, column: string, direction: string) Sort callback
---@field headerTextColor? RGBAColor|string Header row text color (default: Theme.Color("text"))
---@field cellTextColor? RGBAColor|string Body cell text color (default: Theme.Color("textSecondary"))
---@field headerBorderColor? RGBAColor|string Header bottom border color
---@field rowBorderColor? RGBAColor|string Body row separator color
---@field columnBorderColor? RGBAColor|string Bordered variant column separator color
---@field onPageChange? fun(table: Table, page: number) Page change callback

---@class Table : Widget
---@overload fun(props?: TableProps): Table
---@field props TableProps
---@field new fun(self, props?: TableProps): Table
local Table = Widget:Extend("Table")

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { rowHeight = 36, fontSize = 12, headerSize = 13, padding = 8 },
    md = { rowHeight = 48, fontSize = 14, headerSize = 15, padding = 12 },
    lg = { rowHeight = 56, fontSize = 16, headerSize = 17, padding = 16 },
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props TableProps?
function Table:Init(props)
    props = props or {}

    local themeStyle = Theme.ComponentStyle("Table")
    Style.ApplyDefaults(props, themeStyle)

    -- Table props
    self.size_ = props.size or "md"
    self.columns_ = props.columns or {}
    self.data_ = props.data or {}
    self.variant_ = props.variant or "default"  -- default, striped, bordered

    -- Features
    self.sortable_ = props.sortable or false
    self.selectable_ = props.selectable or false
    self.multiSelect_ = props.multiSelect or false
    self.showHeader_ = props.showHeader ~= false  -- default true
    self.stickyHeader_ = props.stickyHeader or false
    self.hoverable_ = props.hoverable ~= false  -- default true

    -- State
    self.sortColumn_ = props.sortColumn
    self.sortDirection_ = props.sortDirection or "asc"  -- asc, desc
    self.selectedRows_ = {}
    self.hoverRow_ = nil
    self.hoverColumn_ = nil

    -- Pagination (optional)
    self.pagination_ = props.pagination or false
    self.pageSize_ = props.pageSize or 10
    self.currentPage_ = props.currentPage or 1

    -- Callbacks
    self.onRowClick_ = props.onRowClick
    self.onRowSelect_ = props.onRowSelect
    self.onSort_ = props.onSort
    self.onPageChange_ = props.onPageChange

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.rowHeight_ = props.rowHeight or sizePreset.rowHeight
    self.fontSize_ = props.fontSize and Theme.FontSize(props.fontSize) or Theme.FontSize(sizePreset.fontSize)
    self.headerSize_ = props.headerSize and Theme.FontSize(props.headerSize) or Theme.FontSize(sizePreset.headerSize)
    self.cellPadding_ = props.cellPadding or sizePreset.padding

    props.flexDirection = "column"

    -- Auto-calculate height if not specified
    if not props.height then
        props.height = self:CalculateTotalHeight()
    end

    Widget.Init(self, props)

    -- Sort data if needed
    if self.sortColumn_ then
        self:SortData()
    end
end

--- Calculate total height needed to display the table
function Table:CalculateTotalHeight()
    local height = 0

    -- Header height
    if self.showHeader_ then
        height = height + self.rowHeight_
    end

    -- Row heights
    local rowCount
    if self.pagination_ then
        rowCount = math.min(self.pageSize_, #self.data_)
    else
        rowCount = #self.data_
    end
    height = height + rowCount * self.rowHeight_

    -- Pagination height
    if self.pagination_ and #self.data_ > self.pageSize_ then
        height = height + 40  -- pagination bar height
    end

    return math.max(height, self.rowHeight_)  -- minimum one row height
end

--- Update height after data change
function Table:UpdateHeight()
    local newHeight = self:CalculateTotalHeight()
    self:SetHeight(newHeight)
end

-- ============================================================================
-- Data Management
-- ============================================================================

function Table:GetData()
    return self.data_
end

function Table:SetData(data)
    self.data_ = data or {}
    self.selectedRows_ = {}
    self.currentPage_ = 1
    if self.sortColumn_ then
        self:SortData()
    end
    self:UpdateHeight()
end

function Table:GetColumns()
    return self.columns_
end

function Table:SetColumns(columns)
    self.columns_ = columns or {}
end

function Table:GetDisplayData()
    local data = self.data_

    if self.pagination_ then
        local startIdx = (self.currentPage_ - 1) * self.pageSize_ + 1
        local endIdx = math.min(startIdx + self.pageSize_ - 1, #data)
        local pageData = {}
        for i = startIdx, endIdx do
            table.insert(pageData, data[i])
        end
        return pageData
    end

    return data
end

function Table:GetTotalPages()
    return math.ceil(#self.data_ / self.pageSize_)
end

-- ============================================================================
-- Sorting
-- ============================================================================

function Table:Sort(columnKey, direction)
    self.sortColumn_ = columnKey
    self.sortDirection_ = direction or (self.sortDirection_ == "asc" and "desc" or "asc")
    self:SortData()

    if self.onSort_ then
        self.onSort_(self, columnKey, self.sortDirection_)
    end
end

function Table:SortData()
    if not self.sortColumn_ then return end

    local column = nil
    for _, col in ipairs(self.columns_) do
        if col.key == self.sortColumn_ then
            column = col
            break
        end
    end

    if not column then return end

    local sortFn = column.sortFn or function(a, b)
        local va = a[self.sortColumn_]
        local vb = b[self.sortColumn_]

        if type(va) == "string" and type(vb) == "string" then
            return va:lower() < vb:lower()
        end

        return va < vb
    end

    table.sort(self.data_, function(a, b)
        if self.sortDirection_ == "asc" then
            return sortFn(a, b)
        else
            return sortFn(b, a)
        end
    end)
end

-- ============================================================================
-- Selection
-- ============================================================================

function Table:GetSelectedRows()
    return self.selectedRows_
end

function Table:SelectRow(rowIndex)
    if not self.selectable_ then return end

    if self.multiSelect_ then
        -- Toggle selection
        if self.selectedRows_[rowIndex] then
            self.selectedRows_[rowIndex] = nil
        else
            self.selectedRows_[rowIndex] = true
        end
    else
        -- Single selection
        self.selectedRows_ = { [rowIndex] = true }
    end

    if self.onRowSelect_ then
        local selectedIndices = {}
        for idx in pairs(self.selectedRows_) do
            table.insert(selectedIndices, idx)
        end
        self.onRowSelect_(self, selectedIndices)
    end
end

function Table:SelectAll()
    if not self.multiSelect_ then return end

    self.selectedRows_ = {}
    for i = 1, #self.data_ do
        self.selectedRows_[i] = true
    end

    if self.onRowSelect_ then
        local selectedIndices = {}
        for i = 1, #self.data_ do
            table.insert(selectedIndices, i)
        end
        self.onRowSelect_(self, selectedIndices)
    end
end

function Table:ClearSelection()
    self.selectedRows_ = {}
    if self.onRowSelect_ then
        self.onRowSelect_(self, {})
    end
end

function Table:IsRowSelected(rowIndex)
    return self.selectedRows_[rowIndex] == true
end

-- ============================================================================
-- Pagination
-- ============================================================================

function Table:SetPage(page)
    local totalPages = self:GetTotalPages()
    self.currentPage_ = math.max(1, math.min(page, totalPages))

    if self.onPageChange_ then
        self.onPageChange_(self, self.currentPage_)
    end
end

function Table:NextPage()
    self:SetPage(self.currentPage_ + 1)
end

function Table:PrevPage()
    self:SetPage(self.currentPage_ - 1)
end

function Table:FirstPage()
    self:SetPage(1)
end

function Table:LastPage()
    self:SetPage(self:GetTotalPages())
end

-- ============================================================================
-- Column Width Calculation
-- ============================================================================

function Table:CalculateColumnWidths(totalWidth)
    local widths = {}
    local fixedWidth = 0
    local flexCount = 0

    -- First pass: count fixed and flex columns
    for _, col in ipairs(self.columns_) do
        if col.width then
            if type(col.width) == "number" then
                widths[col.key] = col.width
                fixedWidth = fixedWidth + col.width
            elseif type(col.width) == "string" and col.width:match("%%$") then
                local percent = tonumber(col.width:match("(%d+)%%"))
                widths[col.key] = totalWidth * percent / 100
                fixedWidth = fixedWidth + widths[col.key]
            end
        else
            flexCount = flexCount + 1
        end
    end

    -- Second pass: distribute remaining width
    if flexCount > 0 then
        local flexWidth = (totalWidth - fixedWidth) / flexCount
        for _, col in ipairs(self.columns_) do
            if not widths[col.key] then
                widths[col.key] = flexWidth
            end
        end
    end

    return widths
end

-- ============================================================================
-- Render
-- ============================================================================

function Table:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()
    local theme = Theme.GetTheme()

    -- Sizes (no scale needed - nvgScale handles it)
    local rowHeight = self.rowHeight_
    local cellPadding = self.cellPadding_
    local fontSize = self.fontSize_
    local headerSize = self.headerSize_

    Widget.Render(self, nvg)

    -- Calculate column widths
    local columnWidths = self:CalculateColumnWidths(w)

    local currentY = y

    -- Render header
    if self.showHeader_ then
        self:RenderHeader(nvg, x, currentY, w, columnWidths, rowHeight, headerSize, cellPadding)
        currentY = currentY + rowHeight
    end

    -- Render rows
    local displayData = self:GetDisplayData()
    self.rowBounds_ = {}

    for i, row in ipairs(displayData) do
        -- Calculate actual row index for selection
        local actualIndex = i
        if self.pagination_ then
            actualIndex = (self.currentPage_ - 1) * self.pageSize_ + i
        end

        local isLastRow = (i == #displayData)
        self:RenderRow(nvg, x, currentY, w, columnWidths, row, actualIndex, i, rowHeight, fontSize, cellPadding, isLastRow)
        self.rowBounds_[i] = { x = x, y = currentY, w = w, h = rowHeight, actualIndex = actualIndex }
        currentY = currentY + rowHeight
    end

    -- Render pagination
    if self.pagination_ and #self.data_ > self.pageSize_ then
        self:RenderPagination(nvg, x, currentY + 8, w, fontSize, cellPadding)
    end

    -- Draw container border on top (only when borderWidth is set)
    local tableBorderWidth = self.props.borderWidth
    if tableBorderWidth and tableBorderWidth > 0 then
        local tableRadius = self.props.borderRadius or 0
        local tableBorderColor = self.props.borderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, tableRadius))
        nvgStrokeColor(nvg, nvgRGBA(tableBorderColor[1], tableBorderColor[2], tableBorderColor[3], tableBorderColor[4] or 255))
        nvgStrokeWidth(nvg, tableBorderWidth)
        nvgStroke(nvg)
    end
end

function Table:RenderHeader(nvg, x, y, w, columnWidths, rowHeight, headerSize, cellPadding)
    local theme = Theme.GetTheme()

    -- Header background
    nvgBeginPath(nvg)
    local tableRadius = self.props.borderRadius or 0
    local headerRadius = self.props.headerBorderRadius or Widget.TopRadius(tableRadius)
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = w, h = rowHeight }, nil, headerRadius))
    local headerBgColor = self.props.headerBgColor
    if headerBgColor then
        nvgFillColor(nvg, nvgRGBA(headerBgColor[1], headerBgColor[2], headerBgColor[3], headerBgColor[4] or 255))
    else
        nvgFillColor(nvg, Theme.NvgColor("surfaceAlt"))
    end
    nvgFill(nvg)

    -- Header bottom border
    local headerBorderColor = self.props.headerBorderColor or self.props.borderColor or Theme.Color("border")
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x, y + rowHeight)
    nvgLineTo(nvg, x + w, y + rowHeight)
    nvgStrokeColor(nvg, nvgRGBA(headerBorderColor[1], headerBorderColor[2], headerBorderColor[3], headerBorderColor[4] or 255))
    nvgStrokeWidth(nvg, self.props.headerBorderWidth or self.props.borderWidth or 1)
    nvgStroke(nvg)

    -- Column headers
    local currentX = x
    self.headerBounds_ = {}

    for _, col in ipairs(self.columns_) do
        local colWidth = columnWidths[col.key] or 100

        self.headerBounds_[col.key] = { x = currentX, y = y, w = colWidth, h = rowHeight }

        -- Header text
        nvgFontSize(nvg, headerSize)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.headerFontWeight or self.props.fontWeight))

        -- 有效对齐：列级 col.align 优先，否则用主题级 headerAlign，再默认 left。
        local colAlign = col.align or self.props.headerAlign or "left"
        local align = NVG_ALIGN_MIDDLE
        if colAlign == "center" then
            align = align + NVG_ALIGN_CENTER_VISUAL
        elseif colAlign == "right" then
            align = align + NVG_ALIGN_RIGHT
        else
            align = align + NVG_ALIGN_LEFT
        end
        nvgTextAlign(nvg, align)

        local headerTextColor = self.props.headerTextColor
        if headerTextColor then
            nvgFillColor(nvg, nvgRGBA(headerTextColor[1], headerTextColor[2], headerTextColor[3], headerTextColor[4] or 255))
        else
            nvgFillColor(nvg, Theme.NvgColor("text"))
        end

        local textX = currentX + cellPadding
        if colAlign == "center" then
            textX = currentX + colWidth / 2
        elseif colAlign == "right" then
            textX = currentX + colWidth - cellPadding
        end

        nvgText(nvg, textX, y + rowHeight / 2, col.label or col.key)

        -- Sort indicator
        if self.sortable_ and col.sortable ~= false and self.sortColumn_ == col.key then
            local arrowX = currentX + colWidth - cellPadding - 8
            nvgFontSize(nvg, Theme.FontSizeOf("tiny"))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, Theme.NvgColor("primary"))
            nvgText(nvg, arrowX, y + rowHeight / 2, self.sortDirection_ == "asc" and "▲" or "▼")
        end

        -- Column separator (for bordered variant)
        if self.variant_ == "bordered" then
            local columnBorderColor = self.props.columnBorderColor or self.props.headerBorderColor or Theme.Color("border")
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, currentX + colWidth, y)
            nvgLineTo(nvg, currentX + colWidth, y + rowHeight)
            nvgStrokeColor(nvg, nvgRGBA(columnBorderColor[1], columnBorderColor[2], columnBorderColor[3], columnBorderColor[4] or 255))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end

        currentX = currentX + colWidth
    end
end

function Table:RenderRow(nvg, x, y, w, columnWidths, rowData, actualIndex, displayIndex, rowHeight, fontSize, cellPadding, isLastRow)
    local theme = Theme.GetTheme()
    local isSelected = self:IsRowSelected(actualIndex)
    local isHovered = self.hoverRow_ == displayIndex

    -- Row background
    nvgBeginPath(nvg)
    local tableRadius = self.props.borderRadius or 0
    if isLastRow then
        local lastRowRadius = self.props.lastRowBorderRadius or Widget.BottomRadius(tableRadius)
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = w, h = rowHeight }, nil, lastRowRadius))
    else
        nvgRect(nvg, x, y, w, rowHeight)
    end

    if isSelected then
        local primaryColor = Theme.Color("primary")
        nvgFillColor(nvg, nvgRGBA(primaryColor[1], primaryColor[2], primaryColor[3], 30))
    elseif isHovered and self.hoverable_ then
        local hoverColor = self.props.rowHoverBgColor
        if hoverColor then
            nvgFillColor(nvg, nvgRGBA(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4] or 255))
        else
            nvgFillColor(nvg, Theme.NvgColor("surfaceHover"))
        end
    elseif self.variant_ == "striped" and displayIndex % 2 == 0 then
        local evenColor = self.props.rowEvenBgColor
        if evenColor then
            nvgFillColor(nvg, nvgRGBA(evenColor[1], evenColor[2], evenColor[3], evenColor[4] or 255))
        else
            nvgFillColor(nvg, Theme.NvgColor("surfaceAlt"))
        end
    else
        local oddColor = self.props.rowOddBgColor
        if oddColor then
            nvgFillColor(nvg, nvgRGBA(oddColor[1], oddColor[2], oddColor[3], oddColor[4] or 255))
        else
            nvgFillColor(nvg, Theme.NvgColor("surface"))
        end
    end
    nvgFill(nvg)

    -- Row bottom border
    -- Row separator line (between rows). Skip on the last row: there is no row
    -- below it, and a full-width line would poke past the container's rounded corners.
    local rowBorderWidth = self.props.rowBorderWidth
    if rowBorderWidth == nil then
        rowBorderWidth = 0.5
    end
    if rowBorderWidth > 0 and not isLastRow then
        local rowBorderColor = self.props.rowBorderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x, y + rowHeight)
        nvgLineTo(nvg, x + w, y + rowHeight)
        nvgStrokeColor(nvg, nvgRGBA(rowBorderColor[1], rowBorderColor[2], rowBorderColor[3], rowBorderColor[4] or 255))
        nvgStrokeWidth(nvg, rowBorderWidth)
        nvgStroke(nvg)
    end

    -- Cells
    local currentX = x

    for _, col in ipairs(self.columns_) do
        local colWidth = columnWidths[col.key] or 100
        local value = rowData[col.key]

        -- Format value
        local displayValue = ""
        if col.render then
            displayValue = col.render(value, rowData, actualIndex)
        elseif value ~= nil then
            displayValue = tostring(value)
        end

        -- Cell text
        nvgFontSize(nvg, fontSize)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))

        -- 有效对齐：列级 col.align 优先，否则用主题级 cellAlign，再默认 left。
        local colAlign = col.align or self.props.cellAlign or "left"
        local align = NVG_ALIGN_MIDDLE
        if colAlign == "center" then
            align = align + NVG_ALIGN_CENTER_VISUAL
        elseif colAlign == "right" then
            align = align + NVG_ALIGN_RIGHT
        else
            align = align + NVG_ALIGN_LEFT
        end
        nvgTextAlign(nvg, align)

        local cellTextColor = self.props.cellTextColor
        if cellTextColor then
            nvgFillColor(nvg, nvgRGBA(cellTextColor[1], cellTextColor[2], cellTextColor[3], cellTextColor[4] or 255))
        else
            nvgFillColor(nvg, Theme.NvgColor("text"))
        end

        local textX = currentX + cellPadding
        if colAlign == "center" then
            textX = currentX + colWidth / 2
        elseif colAlign == "right" then
            textX = currentX + colWidth - cellPadding
        end

        nvgText(nvg, textX, y + rowHeight / 2, displayValue)

        -- Column separator (for bordered variant)
        if self.variant_ == "bordered" then
            local columnBorderColor = self.props.columnBorderColor or Theme.Color("border")
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, currentX + colWidth, y)
            nvgLineTo(nvg, currentX + colWidth, y + rowHeight)
            nvgStrokeColor(nvg, nvgRGBA(columnBorderColor[1], columnBorderColor[2], columnBorderColor[3], columnBorderColor[4] or 255))
            nvgStrokeWidth(nvg, 0.5)
            nvgStroke(nvg)
        end

        currentX = currentX + colWidth
    end
end

function Table:RenderPagination(nvg, x, y, w, fontSize, cellPadding)
    local theme = Theme.GetTheme()
    local totalPages = self:GetTotalPages()

    -- Info text
    local startItem = (self.currentPage_ - 1) * self.pageSize_ + 1
    local endItem = math.min(self.currentPage_ * self.pageSize_, #self.data_)
    local infoText = string.format("%d-%d of %d", startItem, endItem, #self.data_)

    nvgFontSize(nvg, fontSize * 0.9)
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
    nvgText(nvg, x + cellPadding, y + 16, infoText)

    -- Page buttons
    local btnSize = 28
    local btnGap = 4
    local buttonsX = x + w - cellPadding - (btnSize * 4 + btnGap * 3)

    -- Store button bounds
    self.paginationBounds_ = {
        first = { x = buttonsX, y = y + 4, w = btnSize, h = btnSize },
        prev = { x = buttonsX + btnSize + btnGap, y = y + 4, w = btnSize, h = btnSize },
        next = { x = buttonsX + (btnSize + btnGap) * 2, y = y + 4, w = btnSize, h = btnSize },
        last = { x = buttonsX + (btnSize + btnGap) * 3, y = y + 4, w = btnSize, h = btnSize },
    }

    local buttons = {
        { key = "first", text = "«", disabled = self.currentPage_ <= 1 },
        { key = "prev", text = "‹", disabled = self.currentPage_ <= 1 },
        { key = "next", text = "›", disabled = self.currentPage_ >= totalPages },
        { key = "last", text = "»", disabled = self.currentPage_ >= totalPages },
    }

    for _, btn in ipairs(buttons) do
        local bounds = self.paginationBounds_[btn.key]

        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bounds.x, bounds.y, bounds.w, bounds.h, 4)

        if btn.disabled then
            nvgFillColor(nvg, Theme.NvgColor("disabled"))
        else
            nvgFillColor(nvg, Theme.NvgColor("surfaceAlt"))
        end
        nvgFill(nvg)

        nvgFontSize(nvg, Theme.FontSizeOf("bodyLarge"))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)

        if btn.disabled then
            nvgFillColor(nvg, Theme.NvgColor("textDisabled"))
        else
            nvgFillColor(nvg, Theme.NvgColor("text"))
        end
        nvgText(nvg, bounds.x + bounds.w / 2, bounds.y + bounds.h / 2, btn.text)
    end

    -- Page indicator
    local pageText = string.format("Page %d of %d", self.currentPage_, totalPages)
    nvgFontSize(nvg, fontSize * 0.9)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Theme.NvgColor("text"))
    nvgText(nvg, buttonsX - 60, y + 16, pageText)
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Table:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function Table:HitTest(x, y)
    -- Convert screen coords to render coords
    local l = self:GetAbsoluteLayout()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local px = x + (l.x - hitTest.x)
    local py = y + (l.y - hitTest.y)

    -- Check if within horizontal bounds
    if px < l.x or px > l.x + l.w then
        return false
    end

    -- Check header bounds
    if self.headerBounds_ then
        for _, bounds in pairs(self.headerBounds_) do
            if self:PointInBounds(px, py, bounds) then
                return true
            end
        end
    end

    -- Check row bounds
    if self.rowBounds_ then
        for _, bounds in ipairs(self.rowBounds_) do
            if self:PointInBounds(px, py, bounds) then
                return true
            end
        end
    end

    -- Check pagination bounds
    if self.paginationBounds_ then
        for _, bounds in pairs(self.paginationBounds_) do
            if self:PointInBounds(px, py, bounds) then
                return true
            end
        end
    end

    -- Fallback to layout bounds
    if py >= l.y and py <= l.y + l.h then
        return true
    end

    return false
end

function Table:OnPointerMove(event)
    if not event then return end

    -- Coordinate conversion
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    -- Check row hover
    self.hoverRow_ = nil
    if self.rowBounds_ then
        for i, bounds in ipairs(self.rowBounds_) do
            if self:PointInBounds(px, py, bounds) then
                self.hoverRow_ = i
                break
            end
        end
    end
end

function Table:OnPointerLeave(event)
    self.hoverRow_ = nil
end

function Table:OnClick(event)
    if not event then return false end

    -- Coordinate conversion
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    -- Check header clicks (sorting)
    if self.sortable_ and self.headerBounds_ then
        for key, bounds in pairs(self.headerBounds_) do
            if self:PointInBounds(px, py, bounds) then
                -- Check if column is sortable
                local column = nil
                for _, col in ipairs(self.columns_) do
                    if col.key == key then
                        column = col
                        break
                    end
                end

                if column and column.sortable ~= false then
                    self:Sort(key)
                    return true
                end
            end
        end
    end

    -- Check row clicks
    if self.rowBounds_ then
        for i, bounds in ipairs(self.rowBounds_) do
            if self:PointInBounds(px, py, bounds) then
                local actualIndex = bounds.actualIndex

                if self.selectable_ then
                    self:SelectRow(actualIndex)
                end

                if self.onRowClick_ then
                    local displayData = self:GetDisplayData()
                    self.onRowClick_(self, displayData[i], actualIndex)
                end

                return true
            end
        end
    end

    -- Check pagination buttons
    if self.pagination_ and self.paginationBounds_ then
        if self:PointInBounds(px, py, self.paginationBounds_.first) then
            self:FirstPage()
            return true
        elseif self:PointInBounds(px, py, self.paginationBounds_.prev) then
            self:PrevPage()
            return true
        elseif self:PointInBounds(px, py, self.paginationBounds_.next) then
            self:NextPage()
            return true
        elseif self:PointInBounds(px, py, self.paginationBounds_.last) then
            self:LastPage()
            return true
        end
    end

    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a simple table from data
---@param columns table[] Column definitions
---@param data table[] Row data
---@param props table|nil Additional props
---@return Table
function Table.FromData(columns, data, props)
    props = props or {}
    props.columns = columns
    props.data = data
    return Table(props)
end

--- Create a sortable table
---@param columns table[]
---@param data table[]
---@param props table|nil
---@return Table
function Table.Sortable(columns, data, props)
    props = props or {}
    props.columns = columns
    props.data = data
    props.sortable = true
    return Table(props)
end

--- Create a selectable table
---@param columns table[]
---@param data table[]
---@param props table|nil
---@return Table
function Table.Selectable(columns, data, props)
    props = props or {}
    props.columns = columns
    props.data = data
    props.selectable = true
    return Table(props)
end

--- Create a paginated table
---@param columns table[]
---@param data table[]
---@param pageSize number
---@param props table|nil
---@return Table
function Table.Paginated(columns, data, pageSize, props)
    props = props or {}
    props.columns = columns
    props.data = data
    props.pagination = true
    props.pageSize = pageSize or 10
    return Table(props)
end

--- Create a striped table
---@param columns table[]
---@param data table[]
---@param props table|nil
---@return Table
function Table.Striped(columns, data, props)
    props = props or {}
    props.columns = columns
    props.data = data
    props.variant = "striped"
    return Table(props)
end

--- Create a bordered table
---@param columns table[]
---@param data table[]
---@param props table|nil
---@return Table
function Table.Bordered(columns, data, props)
    props = props or {}
    props.columns = columns
    props.data = data
    props.variant = "bordered"
    return Table(props)
end

return Table
