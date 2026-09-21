-- ============================================================================
-- Accordion Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Expandable/collapsible content sections
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")

---@class AccordionItem
---@field id string|number Unique item identifier
---@field title string Header title
---@field subtitle? string Optional subtitle
---@field icon? string Leading icon
---@field content? Widget|string Content widget or text (can be assigned later with SetItemContent)
---@field disabled? boolean Is item disabled
---@field defaultExpanded? boolean Start expanded

---@class AccordionProps : WidgetProps
---@field items? AccordionItem[] Accordion items
---@field variant? string "default" | "outlined" | "separated" (default: "default")
---@field allowMultiple? boolean Allow multiple items expanded
---@field expandedItems? table List of expanded item ids
---@field bgColor? RGBAColor|string Container background fill color
---@field headerExpandedBgColor? RGBAColor|string Expanded header background color
---@field collapsedHeaderBgColor? RGBAColor|string Collapsed header background color
---@field hoverBgColor? RGBAColor|string Header hover background color
---@field expandedHeaderBorderRadius? number|table Radius for expanded header background
---@field lastHeaderBorderRadius? number|table Radius for bottom header/content background
---@field headerFontSize? number Header text font size in pt (default: Theme.FontSizeOf("body"))
---@field headerFontWeight? string Font weight for header text (default: fontWeight)
---@field indicatorCollapsedColor? RGBAColor|string Indicator color when item is collapsed
---@field indicatorExpandedColor? RGBAColor|string Indicator color when item is expanded
---@field contentTextColor? RGBAColor|string Text color for string content
---@field contentFontSize? number Font size for string content
---@field contentFontWeight? string Font weight for string content
---@field headerHeight? number Height of header (default: 48)
---@field animationDuration? number Animation duration in seconds (default: 0.2)
---@field showDividers? boolean Show dividers between items (default: true)
---@field itemDividerColor? RGBAColor|string Divider color between accordion items
---@field headerDividerColor? RGBAColor|string Divider color below expanded header
---@field contentDividerColor? RGBAColor|string Divider color at top of expanded content
---@field dividerWidth? number Divider line width
---@field onChange? fun(self: Accordion, expandedItems: table) Expansion change callback
---@class Accordion : Widget
---@overload fun(props?: AccordionProps): Accordion
---@field props AccordionProps
---@field new fun(self, props?: AccordionProps): Accordion
local Accordion = Widget:Extend("Accordion")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props AccordionProps?
function Accordion:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Accordion")
    Style.ApplyDefaults(props, themeStyle)
    props.borderRadius = props.borderRadius or 8

    -- Default settings
    props.items = props.items or {}
    props.variant = props.variant or "default"
    props.allowMultiple = props.allowMultiple or false
    props.expandedItems = props.expandedItems or {}
    props.headerHeight = props.headerHeight or 48
    props.animationDuration = props.animationDuration or 0.2
    props.showDividers = props.showDividers ~= false

    -- Default flex layout
    props.flexDirection = props.flexDirection or "column"

    -- State
    self.state = {
        hoveredItem = nil,
        expandedItems = {},
        animatingItems = {}, -- { [id] = { progress, targetExpanded } }
        contentHeights = {}, -- Cached content heights
    }

    -- Initialize expanded state from items
    for _, item in ipairs(props.items) do
        if item.defaultExpanded then
            self.state.expandedItems[item.id] = true
        end
    end

    -- Also respect initial expandedItems prop
    for _, id in ipairs(props.expandedItems) do
        self.state.expandedItems[id] = true
    end

    -- Content widgets cache
    self.contentWidgets_ = {}

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Accordion:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state
    local variant = props.variant

    -- Container shadow
    local boxShadow = props.boxShadow
    if boxShadow == false then
        -- Explicitly disabled.
    elseif boxShadow then
        local geom = self:GetShapeGeometry(l, nil, props.borderRadius or 0)
        self:RenderBoxShadows(nvg, geom, boxShadow)
    end

    -- Container background fill
    local bgColor = props.bgColor
    if bgColor then
        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry(l, nil, props.borderRadius or 0))
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
        nvgFill(nvg)
    end

    -- Render items
    local y = l.y
    local itemCount = #props.items

    for i, item in ipairs(props.items) do
        local isExpanded = state.expandedItems[item.id] == true
        local isAnimating = state.animatingItems[item.id] ~= nil
        local animProgress = isExpanded and 1 or 0  -- Default to 0 when collapsed, 1 when expanded

        if isAnimating then
            local anim = state.animatingItems[item.id]
            animProgress = anim.progress
            if not anim.targetExpanded then
                animProgress = 1 - animProgress
            end
        end

        local itemHeight = self:RenderItem(nvg, item, l.x, y, l.w, i, itemCount, isExpanded, animProgress)
        y = y + itemHeight

        -- Draw divider
        if props.showDividers and i < itemCount and variant ~= "separated" then
            self:RenderDivider(nvg, l.x, y, l.w, props.itemDividerColor, props.dividerWidth)
        end
    end

    -- Draw container border after items (so hover/content don't cover it)
    if variant == "outlined" then
        local borderColor = props.borderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry(l, nil, props.borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, props.borderWidth or 1)
        nvgStroke(nvg)
    elseif props.borderWidth and props.borderWidth > 0 then
        -- Theme-driven border for default variant
        local borderColor = props.borderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry(l, nil, props.borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, props.borderWidth)
        nvgStroke(nvg)
    end
end

--- Render a single accordion item
function Accordion:RenderItem(nvg, item, x, y, width, index, total, isExpanded, animProgress)
    local props = self.props
    local state = self.state
    local variant = props.variant
    local headerHeight = props.headerHeight

    local isHovered = state.hoveredItem == item.id
    local isDisabled = item.disabled == true

    -- Calculate content height
    local contentHeight = state.contentHeights[item.id] or 0
    local visibleContentHeight = contentHeight * animProgress

    local totalHeight = headerHeight + visibleContentHeight

    -- Item background for separated variant
    if variant == "separated" then
        local bgColor = props.bgColor or Theme.Color("surface")
        local borderRadius = self.props.borderRadius

        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = totalHeight }, nil, borderRadius))
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
        nvgFill(nvg)

        -- Border
        local borderColor = self.props.borderColor or Theme.Color("border")
        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = totalHeight }, nil, borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
    end

    -- Render header
    self:RenderHeader(nvg, item, x, y, width, headerHeight, isExpanded, isHovered, isDisabled, animProgress, index, total)

    -- Render content if expanded or animating
    if animProgress > 0 then
        self:RenderContent(nvg, item, x, y + headerHeight, width, visibleContentHeight, animProgress, index, total)
        if props.headerDividerColor then
            self:RenderDivider(nvg, x, y + headerHeight, width, props.headerDividerColor, props.dividerWidth)
        end
    end
    return totalHeight
end

--- Render item header
function Accordion:RenderHeader(nvg, item, x, y, width, height, isExpanded, isHovered, isDisabled, animProgress, index, total)
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.headerFontWeight or self.props.fontWeight)
    local containerR = self.props.borderRadius or 0
    local textColor
    if isDisabled then
        textColor = Theme.Color("textDisabled")
    elseif isExpanded then
        textColor = self.props.expandedTextColor or Theme.Color("text")
    else
        textColor = self.props.collapsedTextColor or Theme.Color("text")
    end
    local secondaryColor = isDisabled and Theme.Color("textDisabled") or Theme.Color("textSecondary")

    -- Expanded header background (theme token) — only expanded items get rounded corners
    if (isExpanded or animProgress > 0) and not isDisabled then
        local expandedHeaderBg = self.props.headerExpandedBgColor
        if expandedHeaderBg then
            local headerRadius = self.props.expandedHeaderBorderRadius
            if headerRadius == nil then
                headerRadius = (index == 1) and Widget.TopRadius(containerR) or 0
            end
            nvgBeginPath(nvg)
            self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, headerRadius))
            nvgFillColor(nvg, nvgRGBA(expandedHeaderBg[1], expandedHeaderBg[2], expandedHeaderBg[3], expandedHeaderBg[4] or 255))
            nvgFill(nvg)
        end
    end

    -- Collapsed header background must sit below hover overlay.
    if not isExpanded and animProgress <= 0 then
        local collapsedHeaderBg = self.props.collapsedHeaderBgColor
        if collapsedHeaderBg then
            local headerRadius = 0
            if index == 1 and index == total then
                headerRadius = containerR
            elseif index == 1 then
                headerRadius = Widget.TopRadius(containerR)
            elseif index == total then
                headerRadius = self.props.lastHeaderBorderRadius or Widget.BottomRadius(containerR)
            end

            nvgBeginPath(nvg)
            self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, headerRadius))
            nvgFillColor(nvg, nvgRGBA(collapsedHeaderBg[1], collapsedHeaderBg[2], collapsedHeaderBg[3], collapsedHeaderBg[4] or 255))
            nvgFill(nvg)
        end
    end
    -- Hover background — collapsed items use plain rect (no rounding)
    if isHovered and not isDisabled then
        local hoverColor = self.props.hoverBgColor
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, width, height)
        if hoverColor then
            nvgFillColor(nvg, nvgRGBA(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4] or 255))
        else
            nvgFillColor(nvg, nvgRGBA(128, 128, 128, 15))
        end
        nvgFill(nvg)
    end

    local padding = 16
    local contentX = x + padding
    local centerY = y + height / 2

    -- Icon
    if item.icon then
        local iconSize = 20
        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, Theme.FontSize(iconSize))
        nvgFillColor(nvg, nvgRGBA(secondaryColor[1], secondaryColor[2], secondaryColor[3], secondaryColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, contentX + iconSize / 2, centerY, string.sub(item.icon, 1, 1), nil)
        contentX = contentX + iconSize + 12
    end

    -- Title
    local titleY = centerY
    if item.subtitle then
        titleY = centerY - 8
    end

    local headerFontSize = self.props.headerFontSize and Theme.FontSize(self.props.headerFontSize) or Theme.FontSizeOf("body")
    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, headerFontSize)
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, contentX, titleY, item.title, nil)

    -- Subtitle
    if item.subtitle then
        nvgFontSize(nvg, Theme.FontSizeOf("small"))
        nvgFillColor(nvg, nvgRGBA(secondaryColor[1], secondaryColor[2], secondaryColor[3], secondaryColor[4] or 255))
        nvgText(nvg, contentX, centerY + 8, item.subtitle, nil)
    end

    -- Expand/collapse indicator (chevron)
    local indicatorSize = 12
    local indicatorX = x + width - padding - indicatorSize
    local indicatorY = centerY

    -- Rotate indicator based on expansion
    local rotation = animProgress * math.pi / 2 -- 0 to 90 degrees

    nvgSave(nvg)
    nvgTranslate(nvg, indicatorX + indicatorSize / 2, indicatorY)
    nvgRotate(nvg, rotation)

    -- Draw chevron (>)
    local chevronSize = 4
    local chevronHeight = 6
    local indicatorColor = isExpanded
        and (self.props.indicatorExpandedColor or secondaryColor)
        or (self.props.indicatorCollapsedColor or secondaryColor)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, -chevronSize, -chevronHeight)
    nvgLineTo(nvg, chevronSize, 0)
    nvgLineTo(nvg, -chevronSize, chevronHeight)
    nvgStrokeColor(nvg, nvgRGBA(indicatorColor[1], indicatorColor[2], indicatorColor[3], indicatorColor[4] or 255))
    nvgStrokeWidth(nvg, 2)
    nvgLineCap(nvg, NVG_ROUND)
    nvgLineJoin(nvg, NVG_ROUND)
    nvgStroke(nvg)

    nvgRestore(nvg)
end

--- Render item content
function Accordion:RenderContent(nvg, item, x, y, width, height, animProgress, index, total)
    local padding = 16
    local containerR = self.props.borderRadius or 0
    local contentRadius = 0
    if index == total then
        contentRadius = self.props.lastHeaderBorderRadius or Widget.BottomRadius(containerR)
    end

    -- Clip content during animation
    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, width, height)

    -- Content background
    local contentBgColor = self.props.contentBgColor
    if contentBgColor then
        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, contentRadius))
        nvgFillColor(nvg, nvgRGBA(contentBgColor[1], contentBgColor[2], contentBgColor[3], contentBgColor[4] or 255))
        nvgFill(nvg)
    else
        local bgColor = Theme.Color("background")
        nvgBeginPath(nvg)
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = width, h = height }, nil, contentRadius))
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], 20))
        nvgFill(nvg)
    end

    if self.props.contentDividerColor then
        self:RenderDivider(nvg, x, y, width, self.props.contentDividerColor, self.props.dividerWidth)
    end

    -- Render content
    local contentWidget = self.contentWidgets_[item.id]
    if contentWidget then
        contentWidget.renderOffsetX_ = x + padding
        contentWidget.renderOffsetY_ = y + padding
        contentWidget:Render(nvg)
    elseif type(item.content) == "string" then
        -- Render text content
        local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.contentFontWeight or self.props.fontWeight)
        local textColor = self.props.contentTextColor or Theme.Color("textSecondary")

        nvgFontFace(nvg, fontFamily)
        if self.props.contentFontSize then
            nvgFontSize(nvg, Theme.FontSize(self.props.contentFontSize))
        else
            nvgFontSize(nvg, Theme.FontSizeOf("body"))
        end
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

        -- Word wrap
        local textX = x + padding
        local textY = y + padding
        local maxWidth = width - padding * 2

        nvgTextBox(nvg, textX, textY, maxWidth, item.content, nil)
    end

    nvgRestore(nvg)
end

--- Render divider
function Accordion:RenderDivider(nvg, x, y, width, color, lineWidth)
    local dividerWidth = lineWidth or self.props.dividerWidth or 1
    if dividerWidth <= 0 then return end

    local borderColor = color or Theme.Color("border")
    local alpha = borderColor[4]
    if alpha == nil then
        alpha = color and 255 or 50
    end

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x, y)
    nvgLineTo(nvg, x + width, y)
    nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], alpha))
    nvgStrokeWidth(nvg, dividerWidth)
    nvgStroke(nvg)
end

-- ============================================================================
-- Content Height Calculation
-- ============================================================================

--- Calculate content height for an item
function Accordion:CalculateContentHeight(item)
    local padding = 16
    local contentWidget = self.contentWidgets_[item.id]

    if contentWidget then
        local cl = contentWidget:GetLayout()
        return cl.h + padding * 2
    elseif type(item.content) == "string" then
        -- Estimate text height (rough calculation)
        local lineHeight = 20
        if self.props.contentFontSize then
            lineHeight = math.max(lineHeight, Theme.FontSize(self.props.contentFontSize) * 1.35)
        end
        local charsPerLine = 60
        local lines = math.ceil(#item.content / charsPerLine)
        return lines * lineHeight + padding * 2
    end

    return 100 -- Default height
end

-- ============================================================================
-- Update
-- ============================================================================

function Accordion:Update(dt)
    local props = self.props
    local state = self.state
    local animDuration = props.animationDuration

    -- Update animations
    local completed = {}
    for id, anim in pairs(state.animatingItems) do
        anim.progress = anim.progress + dt / animDuration

        if anim.progress >= 1 then
            anim.progress = 1
            table.insert(completed, id)

            -- Update expanded state
            if anim.targetExpanded then
                state.expandedItems[id] = true
            else
                state.expandedItems[id] = nil
            end
        end
    end

    -- Remove completed animations
    for _, id in ipairs(completed) do
        state.animatingItems[id] = nil
    end
end

-- ============================================================================
-- Hit Testing
-- ============================================================================

--- Find item header at position (base pixel coordinates)
function Accordion:FindHeaderAt(baseX, baseY)
    local props = self.props
    local state = self.state

    -- Get offset between render coords and hit test coords
    local renderLayout = self:GetAbsoluteLayout()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderLayout.x - hitTest.x
    local offsetY = renderLayout.y - hitTest.y

    -- Convert to render coords
    local x = baseX + offsetX
    local y = baseY + offsetY

    if x < renderLayout.x or x > renderLayout.x + renderLayout.w or y < renderLayout.y then
        return nil
    end

    local currentY = renderLayout.y

    for _, item in ipairs(props.items) do
        local headerHeight = props.headerHeight
        local isExpanded = state.expandedItems[item.id] == true
        local isAnimating = state.animatingItems[item.id] ~= nil
        local animProgress = isExpanded and 1 or 0  -- Default to 0 when collapsed, 1 when expanded

        if isAnimating then
            local anim = state.animatingItems[item.id]
            animProgress = anim.progress
            if not anim.targetExpanded then
                animProgress = 1 - animProgress
            end
        end

        local contentHeight = (state.contentHeights[item.id] or 0) * animProgress
        local totalHeight = headerHeight + contentHeight

        -- Check if in header region
        if y >= currentY and y < currentY + headerHeight then
            return item
        end

        currentY = currentY + totalHeight
    end

    return nil
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Accordion:OnPointerMove(event)
    if not event then return end

    local item = self:FindHeaderAt(event.x, event.y)
    local hoveredId = item and item.id or nil

    if hoveredId ~= self.state.hoveredItem then
        self:SetState({ hoveredItem = hoveredId })
    end
end

function Accordion:OnMouseLeave()
    self:SetState({ hoveredItem = nil })
end

function Accordion:OnClick(event)
    if not event then return end

    local item = self:FindHeaderAt(event.x, event.y)
    if not item or item.disabled then
        return
    end

    self:ToggleItem(item.id)
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Toggle item expansion
---@param itemId string|number
---@return Accordion self
function Accordion:ToggleItem(itemId)
    local props = self.props
    local state = self.state

    local isCurrentlyExpanded = state.expandedItems[itemId] == true
    local targetExpanded = not isCurrentlyExpanded

    -- If not allowing multiple, collapse others
    if targetExpanded and not props.allowMultiple then
        for id, _ in pairs(state.expandedItems) do
            if id ~= itemId then
                -- Start collapse animation
                state.animatingItems[id] = { progress = 0, targetExpanded = false }
            end
        end
    end

    -- Calculate content height if needed
    if not state.contentHeights[itemId] then
        for _, item in ipairs(props.items) do
            if item.id == itemId then
                state.contentHeights[itemId] = self:CalculateContentHeight(item)
                break
            end
        end
    end

    -- Start animation
    state.animatingItems[itemId] = { progress = 0, targetExpanded = targetExpanded }

    -- Fire callback
    local expandedList = {}
    for id, _ in pairs(state.expandedItems) do
        if id ~= itemId or targetExpanded then
            table.insert(expandedList, id)
        end
    end
    if targetExpanded and not state.expandedItems[itemId] then
        table.insert(expandedList, itemId)
    end
    self:DispatchEvent("change", self, expandedList)
    if props.onChange then
        props.onChange(self, expandedList)
    end

    return self
end

--- Expand item
---@param itemId string|number
---@return Accordion self
function Accordion:ExpandItem(itemId)
    if not self.state.expandedItems[itemId] then
        self:ToggleItem(itemId)
    end
    return self
end

--- Collapse item
---@param itemId string|number
---@return Accordion self
function Accordion:CollapseItem(itemId)
    if self.state.expandedItems[itemId] then
        self:ToggleItem(itemId)
    end
    return self
end

--- Expand all items
---@return Accordion self
function Accordion:ExpandAll()
    for _, item in ipairs(self.props.items) do
        if not item.disabled then
            self:ExpandItem(item.id)
        end
    end
    return self
end

--- Collapse all items
---@return Accordion self
function Accordion:CollapseAll()
    for id, _ in pairs(self.state.expandedItems) do
        self:CollapseItem(id)
    end
    return self
end

--- Set items
---@param items AccordionItem[]
---@return Accordion self
function Accordion:SetItems(items)
    self.props.items = items
    self.state.expandedItems = {}
    self.state.animatingItems = {}
    self.state.contentHeights = {}
    self.contentWidgets_ = {}

    -- Initialize expanded state
    for _, item in ipairs(items) do
        if item.defaultExpanded then
            self.state.expandedItems[item.id] = true
        end
    end

    return self
end

--- Add item
---@param item AccordionItem
---@return Accordion self
function Accordion:AddItem(item)
    table.insert(self.props.items, item)
    if item.defaultExpanded then
        self.state.expandedItems[item.id] = true
    end
    return self
end

--- Remove item
---@param itemId string|number
---@return Accordion self
function Accordion:RemoveItem(itemId)
    local items = self.props.items
    for i = #items, 1, -1 do
        if items[i].id == itemId then
            table.remove(items, i)
            self.state.expandedItems[itemId] = nil
            self.state.animatingItems[itemId] = nil
            self.state.contentHeights[itemId] = nil
            self.contentWidgets_[itemId] = nil
            break
        end
    end
    return self
end

--- Set content widget for an item
---@param itemId string|number
---@param widget Widget
---@return Accordion self
function Accordion:SetItemContent(itemId, widget)
    self.contentWidgets_[itemId] = widget
    widget.parent = self

    -- Recalculate content height
    for _, item in ipairs(self.props.items) do
        if item.id == itemId then
            self.state.contentHeights[itemId] = self:CalculateContentHeight(item)
            break
        end
    end

    return self
end

--- Set variant
---@param variant string "default" | "outlined" | "separated"
---@return Accordion self
function Accordion:SetVariant(variant)
    self.props.variant = variant
    return self
end

--- Set allow multiple
---@param allow boolean
---@return Accordion self
function Accordion:SetAllowMultiple(allow)
    self.props.allowMultiple = allow
    return self
end

--- Is item expanded
---@param itemId string|number
---@return boolean
function Accordion:IsExpanded(itemId)
    return self.state.expandedItems[itemId] == true
end

--- Get expanded items
---@return table
function Accordion:GetExpandedItems()
    local result = {}
    for id, _ in pairs(self.state.expandedItems) do
        table.insert(result, id)
    end
    return result
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Accordion:IsStateful()
    return true
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create accordion from simple data
---@param data table[] Array of { title, content, [subtitle], [icon] }
---@param options table|nil Accordion options
---@return Accordion
function Accordion.FromData(data, options)
    options = options or {}

    local items = {}
    for i, d in ipairs(data) do
        table.insert(items, {
            id = d.id or i,
            title = d.title,
            subtitle = d.subtitle,
            icon = d.icon,
            content = d.content,
            disabled = d.disabled,
            defaultExpanded = d.defaultExpanded,
        })
    end

    options.items = items
    return Accordion:new(options)
end

--- Create FAQ accordion
---@param faqs table[] Array of { question, answer }
---@param options table|nil
---@return Accordion
function Accordion.FAQ(faqs, options)
    options = options or {}

    local items = {}
    for i, faq in ipairs(faqs) do
        table.insert(items, {
            id = faq.id or i,
            title = faq.question,
            content = faq.answer,
            icon = "?",
        })
    end

    options.items = items
    options.variant = options.variant or "separated"
    return Accordion:new(options)
end

--- Create settings accordion
---@param sections table[] Array of { title, subtitle, content }
---@param options table|nil
---@return Accordion
function Accordion.Settings(sections, options)
    options = options or {}

    local items = {}
    for i, section in ipairs(sections) do
        table.insert(items, {
            id = section.id or i,
            title = section.title,
            subtitle = section.subtitle,
            icon = section.icon,
            content = section.content,
            defaultExpanded = section.defaultExpanded,
        })
    end

    options.items = items
    options.allowMultiple = options.allowMultiple ~= false
    options.variant = options.variant or "outlined"
    return Accordion:new(options)
end

return Accordion
