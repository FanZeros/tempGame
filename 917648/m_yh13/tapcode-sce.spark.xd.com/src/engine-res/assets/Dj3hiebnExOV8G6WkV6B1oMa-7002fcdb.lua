-- ============================================================================
-- VirtualList Component
-- UrhoX UI Library - High-performance virtualized list
--
-- Features:
-- - Object Pooling: Reuses item widgets instead of creating/destroying
-- - View Recycling: Only renders items visible in the viewport
-- - Custom item rendering via createItem/renderItem callbacks
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local ScrollView = require("urhox-libs/UI/Widgets/ScrollView")
local Panel = require("urhox-libs/UI/Widgets/Panel")

---@class VirtualListProps : WidgetProps
---@field data? table Array of data items (default: empty)
---@field itemHeight number Height of each item row (required)
---@field itemGap? number Gap between items (default: 0)
---@field viewportHeight? number Viewport height in pixels (required if height is percentage) TODO: auto-delay pool init, remove this requirement
---@field createItem fun(): Widget Creates a new item widget for the pool
---@field bindItem fun(widget: Widget, data: any, index: integer) Binds data to item widget
---@field tickItem? fun(widget: Widget, data: any, index: integer, dt: number) Updates dynamic content each frame
---@field onItemClick? fun(data: any, index: integer, widget: Widget) Item click callback
---@field poolBuffer? number Extra items in pool beyond visible (default: 3)
---@field showScrollbar? boolean Show scrollbar (default: true)
---@field bounces? boolean Enable bounce effect (default: true)

---@class VirtualList : Widget
---@overload fun(props?: VirtualListProps): VirtualList
---@field props VirtualListProps
---@field new fun(self, props?: VirtualListProps): VirtualList
---@field scrollView_ ScrollView Internal scroll view
---@field contentContainer_ Panel Internal content container
local VirtualList = Widget:Extend("VirtualList")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props VirtualListProps?
function VirtualList:Init(props)
    props = props or {}

    -- Validate required props
    if not props.itemHeight or props.itemHeight <= 0 then
        error("VirtualList requires 'itemHeight' prop (positive number)")
    end
    if not props.createItem or type(props.createItem) ~= "function" then
        error("VirtualList requires 'createItem' prop (function)")
    end
    if not props.bindItem or type(props.bindItem) ~= "function" then
        error("VirtualList requires 'bindItem' prop (function)")
    end

    -- Default values
    props.data = props.data or {}
    props.itemGap = props.itemGap or 0
    props.poolBuffer = props.poolBuffer or 3
    props.showScrollbar = props.showScrollbar ~= false
    props.bounces = props.bounces ~= false

    -- Internal state
    self.pool_ = {
        available = {},  -- Pool of unused item widgets
        inUse = {},      -- Currently visible items { [dataIndex] = widget }
    }
    self.scrollOffset_ = 0
    self.visibleRange_ = { first = 0, last = 0 }
    self.rowHeight_ = props.itemHeight + props.itemGap
    self.contentContainer_ = nil
    self.scrollView_ = nil

    Widget.Init(self, props)

    -- Build internal structure
    self:BuildStructure()

    -- Pre-warm pool and initial render
    self:PrewarmPool()
    self:UpdateVisibleItems()
end

-- ============================================================================
-- Internal Structure
-- ============================================================================

function VirtualList:BuildStructure()
    local props = self.props

    -- Create ScrollView
    self.scrollView_ = ScrollView {
        width = "100%",
        height = "100%",
        scrollY = true,
        scrollX = false,
        showScrollbar = props.showScrollbar,
        scrollbarInteractive = true,
        bounces = props.bounces,
        onScroll = function(sv, x, y)
            self:OnScroll(x, y)
        end,
    }
    Widget.AddChild(self, self.scrollView_)

    -- Create content container with virtual height
    local totalHeight = #props.data * self.rowHeight_
    self.contentContainer_ = Panel {
        width = "100%",
        height = totalHeight,
    }
    self.scrollView_:AddChild(self.contentContainer_)

    -- Override UpdateContentSize to use known virtual height.
    -- Default implementation dynamically calculates from Yoga layout, but:
    -- 1) It runs in Update (before Yoga recalculates), so layout values may be stale
    -- 2) VirtualList knows the exact total height: dataCount * rowHeight
    -- This eliminates the dependency on Yoga layout timing.
    local vlist = self
    self.scrollView_.UpdateContentSize = function(sv)
        local l = sv:GetLayout()
        sv.contentWidth_ = l.w > 0 and l.w or 0
        sv.contentHeight_ = #vlist.props.data * vlist.rowHeight_
    end
end

-- ============================================================================
-- Object Pool
-- ============================================================================

function VirtualList:PrewarmPool()
    local props = self.props
    local layout = self:GetLayout()

    -- Get viewport height: prefer layout, then numeric prop, then default
    -- All values are in base pixels
    local viewportHeight = 400
    if layout.h > 0 then
        viewportHeight = layout.h
    elseif type(props.height) == "number" then
        viewportHeight = props.height
    elseif props.viewportHeight and type(props.viewportHeight) == "number" then
        viewportHeight = props.viewportHeight
    end

    local visibleCount = math.ceil(viewportHeight / self.rowHeight_) + props.poolBuffer * 2

    for i = 1, visibleCount do
        local widget = self:CreatePoolItem()
        widget:SetVisible(false)
        table.insert(self.pool_.available, widget)
    end
end

function VirtualList:CreatePoolItem()
    local widget = self.props.createItem()

    -- Ensure absolute positioning for virtual list items
    widget:SetStyle({
        position = "absolute",
        left = 0,
        top = 0,
    })

    -- Store reference for tracking
    widget._virtualListIndex = nil

    -- Add click handler if onItemClick is provided
    if self.props.onItemClick then
        local originalOnClick = widget.OnClick
        widget.OnClick = function(w, event)
            if originalOnClick then
                originalOnClick(w, event)
            end
            local idx = w._virtualListIndex
            if idx and self.props.data[idx] then
                self.props.onItemClick(self.props.data[idx], idx, w)
            end
        end
    end

    return widget
end

function VirtualList:AcquireItem()
    local widget
    if #self.pool_.available > 0 then
        widget = table.remove(self.pool_.available)
    else
        widget = self:CreatePoolItem()
    end
    widget:SetVisible(true)
    return widget
end

function VirtualList:ReleaseItem(widget)
    local idx = widget._virtualListIndex
    if idx and self.pool_.inUse[idx] then
        self.pool_.inUse[idx] = nil
    end
    widget._virtualListIndex = nil
    widget:SetVisible(false)
    table.insert(self.pool_.available, widget)
end

-- ============================================================================
-- Visible Range Calculation
-- ============================================================================

function VirtualList:CalculateVisibleRange()
    local layout = self:GetLayout()
    local props = self.props

    -- Get viewport height: prefer layout, then numeric prop, then default
    -- All values are in base pixels
    local viewportHeight = 400
    if layout.h > 0 then
        viewportHeight = layout.h
    elseif type(props.height) == "number" then
        viewportHeight = props.height
    elseif props.viewportHeight and type(props.viewportHeight) == "number" then
        viewportHeight = props.viewportHeight
    end

    local dataCount = #self.props.data

    if dataCount == 0 then
        return 0, 0
    end

    -- scrollOffset_ is in base pixels
    local scrollOffsetDesign = self.scrollOffset_

    -- Item at index i: top = (i-1)*rowHeight, bottom = i*rowHeight
    -- First visible: smallest i where bottom > scrollOffset
    local firstVisible = math.floor(scrollOffsetDesign / self.rowHeight_) + 1

    -- Last visible: largest i where top < scrollOffset + viewportHeight
    local lastVisible = math.ceil((scrollOffsetDesign + viewportHeight) / self.rowHeight_)

    -- Clamp to valid range
    firstVisible = math.max(1, firstVisible)
    lastVisible = math.min(dataCount, lastVisible)

    return firstVisible, lastVisible
end

function VirtualList:UpdateVisibleItems()
    local firstVisible, lastVisible = self:CalculateVisibleRange()

    -- Check if range changed
    if firstVisible == self.visibleRange_.first and lastVisible == self.visibleRange_.last then
        return
    end

    -- Release items that are no longer visible
    local toRelease = {}
    for dataIndex, widget in pairs(self.pool_.inUse) do
        if dataIndex < firstVisible or dataIndex > lastVisible then
            table.insert(toRelease, widget)
        end
    end

    for _, widget in ipairs(toRelease) do
        self.contentContainer_:RemoveChild(widget)
        self:ReleaseItem(widget)
    end

    -- Add newly visible items
    for i = firstVisible, lastVisible do
        if not self.pool_.inUse[i] and self.props.data[i] then
            local widget = self:AcquireItem()
            self.pool_.inUse[i] = widget
            widget._virtualListIndex = i

            -- Position the widget
            local yPos = (i - 1) * self.rowHeight_
            widget:SetStyle({ top = yPos })

            -- Bind data to widget
            self.props.bindItem(widget, self.props.data[i], i)

            -- Add to content container
            self.contentContainer_:AddChild(widget)
        end
    end

    self.visibleRange_.first = firstVisible
    self.visibleRange_.last = lastVisible
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function VirtualList:OnScroll(scrollX, scrollY)
    self.scrollOffset_ = scrollY
    self:UpdateVisibleItems()
end

--- Called every frame by UI system
--- Invokes tickItem callback for visible items only
function VirtualList:Update(dt)
    if not self.props.tickItem then return end

    for dataIndex, widget in pairs(self.pool_.inUse) do
        local data = self.props.data[dataIndex]
        if data then
            self.props.tickItem(widget, data, dataIndex, dt)
        end
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Set new data and refresh the list
---@param data table Array of data items
function VirtualList:SetData(data)
    self.props.data = data or {}

    -- Update content height
    local totalHeight = #self.props.data * self.rowHeight_
    self.contentContainer_:SetStyle({ height = totalHeight })

    -- Reset scroll position
    self.scrollOffset_ = 0
    self.scrollView_:SetScroll(0, 0)

    -- Release all items and re-render
    self:ReleaseAllItems()
    self.visibleRange_ = { first = 0, last = 0 }
    self:UpdateVisibleItems()
end

--- Get current data
---@return table
function VirtualList:GetData()
    return self.props.data
end

--- Get item count
---@return number
function VirtualList:GetItemCount()
    return #self.props.data
end

--- Scroll to specific item index
---@param index number 1-based index
function VirtualList:ScrollToIndex(index)
    local yPos = (index - 1) * self.rowHeight_
    self.scrollView_:SetScroll(0, yPos)
end

--- Scroll to top
function VirtualList:ScrollToTop()
    self.scrollView_:ScrollToTop()
end

--- Scroll to bottom
function VirtualList:ScrollToBottom()
    self.scrollView_:ScrollToBottom()
end

--- Refresh visible items (re-bindItem all visible items)
--- Call this after data mutation to update displayed content
function VirtualList:Refresh()
    for dataIndex, widget in pairs(self.pool_.inUse) do
        local data = self.props.data[dataIndex]
        if data then
            self.props.bindItem(widget, data, dataIndex)
        end
    end
end

--- Get visible range
---@return number firstIndex First visible index
---@return number lastIndex Last visible index
function VirtualList:GetVisibleRange()
    return self.visibleRange_.first, self.visibleRange_.last
end

--- Get pool statistics
---@return table { inUse, available, total }
function VirtualList:GetPoolStats()
    local inUseCount = 0
    for _ in pairs(self.pool_.inUse) do
        inUseCount = inUseCount + 1
    end
    return {
        inUse = inUseCount,
        available = #self.pool_.available,
        total = inUseCount + #self.pool_.available,
    }
end

--- Release all items back to pool
function VirtualList:ReleaseAllItems()
    for dataIndex, widget in pairs(self.pool_.inUse) do
        self.contentContainer_:RemoveChild(widget)
        widget._virtualListIndex = nil
        widget:SetVisible(false)
        table.insert(self.pool_.available, widget)
    end
    self.pool_.inUse = {}
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function VirtualList:Destroy()
    self:ReleaseAllItems()
    self.pool_.available = {}
    Widget.Destroy(self)
end

return VirtualList
