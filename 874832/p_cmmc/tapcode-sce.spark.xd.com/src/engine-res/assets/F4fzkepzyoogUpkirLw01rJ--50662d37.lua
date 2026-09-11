-- ============================================================================
-- Breadcrumb Widget
-- Navigation breadcrumb trail component
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class BreadcrumbProps : WidgetProps
---@field items? table[] Breadcrumb items array {label, icon, onClick}
---@field separator? string "slash" | "arrow" | "chevron" | "dot" | "dash" (default: "slash")
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field fontSize? number Custom font size
---@field maxItems? number Max items before collapse (0 = no limit)
---@field itemsBeforeCollapse? number Items to show before collapse (default: 1)
---@field itemsAfterCollapse? number Items to show after collapse (default: 2)
---@field showHomeIcon? boolean Show home icon on first item (default: true)
---@field linkColor? RGBAColor|string Clickable link text color (default: textSecondary)
---@field hoverColor? RGBAColor|string Hovered link text color (default: primary)
---@field currentColor? RGBAColor|string Current page text color (default: text)
---@field separatorColor? RGBAColor|string Separator text color (default: textSecondary)
---@field onItemClick? fun(breadcrumb: Breadcrumb, item: table, index: number) Item click callback

---@class Breadcrumb : Widget
---@overload fun(props?: BreadcrumbProps): Breadcrumb
---@field props BreadcrumbProps
---@field new fun(self, props?: BreadcrumbProps): Breadcrumb
local Breadcrumb = Widget:Extend("Breadcrumb")

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { fontSize = 12, height = 24, iconSize = 12, gap = 4 },
    md = { fontSize = 14, height = 32, iconSize = 14, gap = 6 },
    lg = { fontSize = 16, height = 40, iconSize = 16, gap = 8 },
}

-- ============================================================================
-- Separator types
-- ============================================================================

local SEPARATORS = {
    slash = "/",
    arrow = ">",
    chevron = "chevron",  -- Special: drawn as icon
    dot = ".",
    dash = "-",
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props BreadcrumbProps?
function Breadcrumb:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Breadcrumb")
    Style.ApplyDefaults(props, themeStyle)

    -- Breadcrumb props
    self.items_ = props.items or {}
    self.separator_ = props.separator or "slash"
    self.size_ = props.size or "md"
    self.maxItems_ = props.maxItems or 0  -- 0 = no limit
    self.itemsBeforeCollapse_ = props.itemsBeforeCollapse or 1
    self.itemsAfterCollapse_ = props.itemsAfterCollapse or 2
    self.showHomeIcon_ = props.showHomeIcon ~= false  -- default true for first item

    -- Callbacks
    self.onItemClick_ = props.onItemClick

    -- State
    self.hoverIndex_ = nil
    self.isExpanded_ = false  -- for collapsed mode

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.fontSize_ = props.fontSize and Theme.FontSize(props.fontSize) or Theme.FontSize(sizePreset.fontSize)
    self.itemHeight_ = sizePreset.height
    self.iconSize_ = sizePreset.iconSize
    self.gap_ = sizePreset.gap

    props.height = props.height or self.itemHeight_
    props.flexDirection = "row"
    props.alignItems = "center"

    Widget.Init(self, props)
end

-- ============================================================================
-- Items Management
-- ============================================================================

function Breadcrumb:GetItems()
    return self.items_
end

function Breadcrumb:SetItems(items)
    self.items_ = items or {}
    self.isExpanded_ = false
end

function Breadcrumb:AddItem(item)
    table.insert(self.items_, item)
end

function Breadcrumb:RemoveItem(index)
    table.remove(self.items_, index)
end

function Breadcrumb:GetVisibleItems()
    local items = self.items_
    local count = #items

    -- No collapse needed
    if self.maxItems_ <= 0 or count <= self.maxItems_ or self.isExpanded_ then
        return items, false
    end

    -- Collapse middle items
    local result = {}
    local hasCollapsed = false

    -- Items before collapse
    for i = 1, self.itemsBeforeCollapse_ do
        if items[i] then
            table.insert(result, items[i])
        end
    end

    -- Collapsed indicator
    table.insert(result, { collapsed = true, count = count - self.itemsBeforeCollapse_ - self.itemsAfterCollapse_ })
    hasCollapsed = true

    -- Items after collapse
    for i = count - self.itemsAfterCollapse_ + 1, count do
        if items[i] then
            table.insert(result, items[i])
        end
    end

    return result, hasCollapsed
end

function Breadcrumb:Expand()
    self.isExpanded_ = true
end

function Breadcrumb:Collapse()
    self.isExpanded_ = false
end

-- ============================================================================
-- Drawing Helpers
-- ============================================================================

function Breadcrumb:DrawSeparator(nvg, x, y, height)
    local sep = self.separator_
    local sepColorTable = self.props.separatorColor or Theme.Color("textSecondary")
    local sepColor = nvgRGBA(sepColorTable[1], sepColorTable[2], sepColorTable[3], sepColorTable[4] or 255)

    if sep == "chevron" then
        -- Draw chevron arrow
        local size = self.iconSize_ * 0.6
        local cx = x + self.gap_
        local cy = y + height / 2

        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - size * 0.3, cy - size * 0.5)
        nvgLineTo(nvg, cx + size * 0.3, cy)
        nvgLineTo(nvg, cx - size * 0.3, cy + size * 0.5)
        nvgStrokeColor(nvg, sepColor)
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)

        return self.gap_ * 2 + size
    else
        -- Draw text separator
        local sepText = SEPARATORS[sep] or sep

        nvgFontSize(nvg, self.fontSize_)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, sepColor)

        local sepX = x + self.gap_
        nvgText(nvg, sepX, y + height / 2, sepText)

        local sepWidth = nvgTextBounds(nvg, 0, 0, sepText, nil, nil)

        return self.gap_ * 2 + sepWidth
    end
end

function Breadcrumb:DrawHomeIcon(nvg, x, y, size)
    local cx = x + size / 2
    local cy = y + size / 2
    local s = size * 0.4

    nvgBeginPath(nvg)
    -- Roof
    nvgMoveTo(nvg, cx - s, cy - s * 0.2)
    nvgLineTo(nvg, cx, cy - s)
    nvgLineTo(nvg, cx + s, cy - s * 0.2)
    -- Walls
    nvgLineTo(nvg, cx + s * 0.7, cy - s * 0.2)
    nvgLineTo(nvg, cx + s * 0.7, cy + s * 0.8)
    nvgLineTo(nvg, cx - s * 0.7, cy + s * 0.8)
    nvgLineTo(nvg, cx - s * 0.7, cy - s * 0.2)
    nvgClosePath(nvg)

    nvgFill(nvg)
end

-- ============================================================================
-- Render
-- ============================================================================

function Breadcrumb:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()

    -- Render background (if any)
    Widget.Render(self, nvg)

    local theme = Theme.GetTheme()
    local visibleItems, hasCollapsed = self:GetVisibleItems()
    local itemCount = #visibleItems

    local currentX = x

    -- Store item positions for hit testing
    self.itemPositions_ = {}

    for i, item in ipairs(visibleItems) do
        local isFirst = (i == 1)
        local isLast = (i == itemCount)
        local isHovered = (self.hoverIndex_ == i)
        local isCollapsed = item.collapsed

        -- Draw separator (except before first item)
        if not isFirst then
            local sepWidth = self:DrawSeparator(nvg, currentX, y, h)
            currentX = currentX + sepWidth
        end

        local itemStartX = currentX

        -- Determine text color
        local textColorTable
        if isCollapsed then
            textColorTable = self.props.linkColor or Theme.Color("textSecondary")
        elseif isLast then
            textColorTable = self.props.currentColor or Theme.Color("text")
        elseif isHovered then
            textColorTable = self.props.hoverColor or Theme.Color("primary")
        else
            textColorTable = self.props.linkColor or Theme.Color("textSecondary")
        end
        local textColor = Theme.ToNvgColor(textColorTable)

        nvgFontSize(nvg, self.fontSize_)
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        if isCollapsed then
            -- Draw ellipsis for collapsed items
            nvgFillColor(nvg, textColor)
            nvgText(nvg, currentX, y + h / 2, "...")

            local ellipsisWidth = nvgTextBounds(nvg, 0, 0, "...", nil, nil)
            currentX = currentX + ellipsisWidth
        else
            -- Draw home icon for first item if enabled
            if isFirst and self.showHomeIcon_ and item.icon == nil then
                nvgFillColor(nvg, textColor)
                self:DrawHomeIcon(nvg, currentX, y + (h - self.iconSize_) / 2, self.iconSize_)
                currentX = currentX + self.iconSize_ + self.gap_ * 0.5
            end

            -- Draw custom icon if provided
            if item.icon then
                nvgFillColor(nvg, textColor)
                nvgText(nvg, currentX, y + h / 2, item.icon)
                local iconWidth = nvgTextBounds(nvg, 0, 0, item.icon, nil, nil)
                currentX = currentX + iconWidth + self.gap_ * 0.5
            end

            -- Draw label
            local label = item.label or item.text or ""
            nvgFillColor(nvg, textColor)
            nvgText(nvg, currentX, y + h / 2, label)

            local labelWidth = nvgTextBounds(nvg, 0, 0, label, nil, nil)
            currentX = currentX + labelWidth

            -- Draw underline on hover (for clickable items)
            if isHovered and not isLast then
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, itemStartX, y + h / 2 + self.fontSize_ * 0.5)
                nvgLineTo(nvg, currentX, y + h / 2 + self.fontSize_ * 0.5)
                nvgStrokeColor(nvg, textColor)
                nvgStrokeWidth(nvg, self.props.borderWidth or 1)
                nvgStroke(nvg)
            end
        end

        -- Store position for hit testing
        self.itemPositions_[i] = {
            x1 = itemStartX,
            x2 = currentX,
            y1 = y,
            y2 = y + h,
            item = item,
            index = i,
            isLast = isLast,
            isCollapsed = isCollapsed,
        }
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Breadcrumb:GetItemAtPosition(screenX, screenY)
    if not self.itemPositions_ then return nil end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y

    -- Convert screen coords to render coords
    local renderPosX = screenX + offsetX
    local renderPosY = screenY + offsetY

    -- itemPositions_ stores absolute render coordinates
    for i, pos in ipairs(self.itemPositions_) do
        if renderPosX >= pos.x1 and renderPosX <= pos.x2 and renderPosY >= pos.y1 and renderPosY <= pos.y2 then
            return pos
        end
    end

    return nil
end

function Breadcrumb:OnPointerMove(event)
    if not event then return end

    local itemPos = self:GetItemAtPosition(event.x, event.y)

    if itemPos and not itemPos.isLast then
        self.hoverIndex_ = itemPos.index
    else
        self.hoverIndex_ = nil
    end
end

function Breadcrumb:OnMouseLeave(event)
    self.hoverIndex_ = nil
end

function Breadcrumb:OnClick(event)
    if not event then return end

    local itemPos = self:GetItemAtPosition(event.x, event.y)

    if itemPos then
        if itemPos.isCollapsed then
            -- Expand collapsed items
            self:Expand()
        elseif not itemPos.isLast then
            -- Navigate to item
            if self.onItemClick_ then
                self.onItemClick_(self, itemPos.item, itemPos.index)
            end

            -- Call item's onClick if provided
            if itemPos.item.onClick then
                itemPos.item.onClick(itemPos.item, itemPos.index)
            end
        end
    end
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create breadcrumb from string array
---@param labels string[] Array of labels
---@param props table|nil Additional props
---@return Breadcrumb
function Breadcrumb.FromLabels(labels, props)
    props = props or {}

    local items = {}
    for i, label in ipairs(labels) do
        table.insert(items, { label = label })
    end

    props.items = items
    return Breadcrumb(props)
end

--- Create breadcrumb from path string
---@param path string Path like "home/documents/file.txt"
---@param props table|nil Additional props
---@return Breadcrumb
function Breadcrumb.FromPath(path, props)
    props = props or {}

    local items = {}
    for segment in string.gmatch(path, "([^/\\]+)") do
        table.insert(items, { label = segment })
    end

    props.items = items
    return Breadcrumb(props)
end

--- Create a website-style breadcrumb
---@param items table[] Array of {label, href}
---@param props table|nil Additional props
---@return Breadcrumb
function Breadcrumb.Navigation(items, props)
    props = props or {}
    props.items = items
    props.separator = props.separator or "chevron"
    return Breadcrumb(props)
end

--- Create a file explorer breadcrumb
---@param path string File path
---@param props table|nil Additional props
---@return Breadcrumb
function Breadcrumb.FilePath(path, props)
    props = props or {}

    local items = {}

    -- Add root/drive
    if path:match("^/") then
        table.insert(items, { label = "/", icon = "" })
    elseif path:match("^%a:") then
        local drive = path:match("^(%a:)")
        table.insert(items, { label = drive, icon = "" })
    end

    -- Add path segments
    for segment in string.gmatch(path, "([^/\\]+)") do
        if not segment:match("^%a:$") then  -- Skip drive letter if already added
            table.insert(items, { label = segment })
        end
    end

    props.items = items
    props.separator = props.separator or "chevron"
    props.showHomeIcon = false
    return Breadcrumb(props)
end

--- Create a collapsible breadcrumb for long paths
---@param items table[] Array of items
---@param maxVisible number Maximum visible items before collapse
---@param props table|nil Additional props
---@return Breadcrumb
function Breadcrumb.Collapsible(items, maxVisible, props)
    props = props or {}
    props.items = items
    props.maxItems = maxVisible or 4
    props.itemsBeforeCollapse = props.itemsBeforeCollapse or 1
    props.itemsAfterCollapse = props.itemsAfterCollapse or 2
    return Breadcrumb(props)
end

return Breadcrumb
