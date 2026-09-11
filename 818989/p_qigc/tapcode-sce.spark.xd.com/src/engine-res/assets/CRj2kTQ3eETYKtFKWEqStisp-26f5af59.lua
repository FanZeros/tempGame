-- ============================================================================
-- Dropdown Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Dropdown select with options list
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class DropdownOption
---@field value any Option value
---@field label string Display text
---@field disabled? boolean Is option disabled

---@class DropdownProps : WidgetProps
---@field options? DropdownOption[] List of options
---@field value? any Currently selected value
---@field placeholder? string Placeholder text when no selection (default: "Select...")
---@field disabled? boolean Is dropdown disabled
---@field maxVisibleItems? number Max visible items in dropdown (default: 6)
---@field itemHeight? number Custom item height
---@field itemHoverBgColor? RGBAColor|string Hover item background color
---@field itemHoverTextColor? RGBAColor|string Hover item text color
---@field itemHoverInset? number Hover highlight horizontal inset (default: 4)
---@field itemHoverRadius? number|table Hover highlight border radius (default: 4)
---@field itemSelectedColor? RGBAColor|string Selected item background color (defaults to itemHoverBgColor)
---@field itemSelectedTextColor? RGBAColor|string Selected item text color (defaults to primary)
---@field itemSelectedBorderRadius? number|table Selected item background radius
---@field hoverBorderColor? RGBAColor|string Trigger hover border color (default: primary)
---@field openBorderColor? RGBAColor|string Trigger open/selected border color (default: primary)
---@field hoverBorderWidth? number Trigger hover border width
---@field openBorderWidth? number Trigger open/selected border width
---@field disabledBorderWidth? number Trigger disabled border width
---@field popupBgColor? RGBAColor|string Popup panel background color (default: surface)
---@field popupBorderColor? RGBAColor|string Popup panel border color (default: border)
---@field selectedFontWeight? string Font weight for selected item text (default: fontWeight)
---@field minFontSize? number Minimum auto-fit font size (default: 1)
---@field triggerBgColor? RGBAColor|string Trigger idle background color (default: surface)
---@field arrowColor? RGBAColor|string Arrow/chevron idle color (default: textSecondary)
---@field itemVerticalInset? number Vertical inset for items area from popup top/bottom edge (default: 4)
---@field queueOverlay? fun(callback: fun(nvg: any)) Custom overlay queue for independent UI trees
---@field onChange? fun(self: Dropdown, value: any, option: DropdownOption) Change callback

---@class Dropdown : Widget
---@overload fun(props?: DropdownProps): Dropdown
---@field props DropdownProps
---@field new fun(self, props?: DropdownProps): Dropdown
---@field state {isOpen: boolean, hovered: boolean, hoveredIndex: number|nil}
local Dropdown = Widget:Extend("Dropdown")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props DropdownProps?
function Dropdown:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("Dropdown")
    Style.ApplyDefaults(props, themeStyle)
    -- Hardcoded fallbacks (only hit when theme has no entry)
    props.height = props.height or 36
    props.minWidth = props.minWidth or 120
    props.borderRadius = props.borderRadius or 6

    -- Default values
    props.options = props.options or {}
    props.placeholder = props.placeholder or "Select..."

    -- Initialize state
    -- Note: isDragging MUST be in self.state because UI.lua gesture dispatcher
    -- checks target.state.isDragging to route OnPanMove/OnPanEnd events
    self.state = {
        isOpen = false,
        hovered = false,
        hoveredIndex = nil,
        isDragging = false,
    }

    -- Internal state (does not need to trigger re-render)
    self.dropdownHeight_ = 0
    self.maxVisibleItems_ = props.maxVisibleItems or 6
    self.itemHeight_ = props.itemHeight or 32
    self.scrollOffset_ = 0
    self.dragStartScrollOffset_ = 0
    self.wasDragging_ = false
    self.autoFitOptionCaches_ = {}

    Widget.Init(self, props)
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Dropdown:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local state = self.state

    local disabled = props.disabled
    local borderRadius = props.borderRadius
    local isOpen = state.isOpen
    local hovered = state.hovered

    -- Get current selection
    local selectedOption = self:GetSelectedOption()
    local displayText = selectedOption and selectedOption.label or props.placeholder
    local hasSelection = selectedOption ~= nil

    -- Colors
    local bgColor, borderColor, borderWidth, textColor, arrowColor

    if disabled then
        bgColor = Theme.Color("disabled")
        borderColor = Theme.Color("border")
        borderWidth = props.disabledBorderWidth
        textColor = Theme.Color("disabledText")
        arrowColor = Theme.Color("disabledText")
    else
        local baseBg = props.triggerBgColor or Theme.Color("surface")
        local baseArrow = props.arrowColor or Theme.Color("textSecondary")
        if isOpen then
            bgColor = baseBg
            borderColor = props.openBorderColor or Theme.Color("primary")
            borderWidth = props.openBorderWidth
            textColor = hasSelection and Theme.Color("text") or Theme.Color("textSecondary")
            arrowColor = props.arrowColor or Theme.Color("primary")
        elseif hovered then
            bgColor = props.triggerBgColor or Theme.Color("surfaceHover") or Style.Lighten(Theme.Color("surface"), 0.05)
            borderColor = props.hoverBorderColor or Theme.Color("primary")
            borderWidth = props.hoverBorderWidth
            textColor = hasSelection and Theme.Color("text") or Theme.Color("textSecondary")
            arrowColor = props.arrowColor or Theme.Color("text")
        else
            bgColor = baseBg
            borderColor = props.borderColor or Theme.Color("border")
            borderWidth = props.borderWidth
            textColor = hasSelection and Theme.Color("text") or Theme.Color("textSecondary")
            arrowColor = baseArrow
        end
    end
    if borderWidth == nil then
        borderWidth = props.borderWidth or 1
    end

    -- Draw trigger background
    self:CreateShapePath(nvg, self:GetShapeGeometry(l, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(nvg)

    -- Draw border
    self:CreateShapePath(nvg, self:GetShapeGeometry(l, nil, borderRadius))
    nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
    nvgStrokeWidth(nvg, borderWidth)
    nvgStroke(nvg)

    -- Draw text
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    local baseFontSize = Theme.FontSizeOf("body")
    local padding = 12
    local arrowSize = 8
    local textWidth = math.max(0, l.w - padding * 2 - arrowSize - 8)
    local renderFontSize = baseFontSize

    if UI.defaultAutoFitText then
        local fitResult = UI.MeasureTextFit(displayText, {
            fontSize = baseFontSize,
            fontFace = fontFamily,
            width = textWidth,
            height = math.max(0, l.h),
            multiline = false,
            minFontSize = props.minFontSize and Theme.FontSize(props.minFontSize) or 1,
            cache = self.autoFitTriggerCache_,
        })
        self.autoFitTriggerCache_ = fitResult
        renderFontSize = fitResult.fontSize or baseFontSize
    end

    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, renderFontSize)
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- Clip text to available width
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x + padding, l.y, textWidth, l.h)
    if UI.defaultAutoFitText then
        nvgText(nvg, l.x + padding, l.y + l.h / 2,
            displayText, nil, false)
    else
        nvgText(nvg, l.x + padding, l.y + l.h / 2, displayText, nil)
    end
    nvgRestore(nvg)

    -- Draw dropdown arrow
    local arrowX = l.x + l.w - padding - arrowSize / 2
    local arrowY = l.y + l.h / 2

    nvgBeginPath(nvg)
    if isOpen then
        -- Up arrow
        nvgMoveTo(nvg, arrowX - arrowSize / 2, arrowY + arrowSize / 4)
        nvgLineTo(nvg, arrowX, arrowY - arrowSize / 4)
        nvgLineTo(nvg, arrowX + arrowSize / 2, arrowY + arrowSize / 4)
    else
        -- Down arrow
        nvgMoveTo(nvg, arrowX - arrowSize / 2, arrowY - arrowSize / 4)
        nvgLineTo(nvg, arrowX, arrowY + arrowSize / 4)
        nvgLineTo(nvg, arrowX + arrowSize / 2, arrowY - arrowSize / 4)
    end
    nvgStrokeColor(nvg, nvgRGBA(arrowColor[1], arrowColor[2], arrowColor[3], arrowColor[4] or 255))
    nvgStrokeWidth(nvg, 2)
    nvgLineCap(nvg, NVG_ROUND)
    nvgLineJoin(nvg, NVG_ROUND)
    nvgStroke(nvg)

    -- Queue dropdown panel to render as overlay (on top of everything)
    if isOpen then
        local queueOverlay = self.props.queueOverlay or UI.QueueOverlay
        queueOverlay(function(nvg_)
            self:RenderDropdownPanel(nvg_)
        end)
    end
end

--- Calculate dropdown panel geometry. Flips upward when there is not enough room below.
function Dropdown:GetPanelMetrics(layout)
    local options = self.props.options or {}
    local itemHeight = self.itemHeight_
    if #options == 0 then
        return {
            y = layout.y + layout.h + 4,
            height = 0,
            visibleItems = 0,
            itemHeight = itemHeight,
            vertInset = 0,
        }
    end

    local maxVisibleItems = math.min(#options, self.maxVisibleItems_)
    local vertInset = self.props.itemVerticalInset ~= nil and self.props.itemVerticalInset or 4
    local panelHeight = maxVisibleItems * itemHeight + vertInset * 2
    local gap = 4
    local viewportPadding = 8
    local _, viewportHeight = UI.GetViewportSize()
    local belowY = layout.y + layout.h + gap
    local belowSpace = viewportHeight - viewportPadding - belowY
    local aboveSpace = layout.y - gap - viewportPadding
    local openAbove = belowSpace < panelHeight and aboveSpace > belowSpace
    local availableSpace = openAbove and aboveSpace or belowSpace
    local visibleItems = maxVisibleItems

    if availableSpace < panelHeight then
        local fitItems = math.floor((math.max(0, availableSpace) - vertInset * 2) / itemHeight)
        visibleItems = math.max(1, math.min(maxVisibleItems, fitItems))
        panelHeight = visibleItems * itemHeight + vertInset * 2
    end

    local panelY = openAbove and (layout.y - gap - panelHeight) or belowY
    if panelY < viewportPadding then
        panelY = viewportPadding
    elseif panelY + panelHeight > viewportHeight - viewportPadding then
        panelY = math.max(viewportPadding, viewportHeight - viewportPadding - panelHeight)
    end

    return {
        y = panelY,
        height = panelHeight,
        visibleItems = visibleItems,
        itemHeight = itemHeight,
        vertInset = vertInset,
    }
end

function Dropdown:ApplyPanelMetrics(metrics)
    self.dropdownHeight_ = metrics.height
    self.dropdownVisibleItems_ = metrics.visibleItems
    self.dropdownPanelY_ = metrics.y
    self:ClampScrollOffset(metrics.visibleItems)
end

--- Render the dropdown options panel
function Dropdown:RenderDropdownPanel(nvg)
    -- Use GetVisualRect because overlay renders outside the widget tree's NanoVG transform stack,
    -- so we need the actual on-screen position/size (accounting for ancestor scale/rotate/translate).
    local l = UI.GetVisualRect(self)
    local props = self.props
    local state = self.state
    local options = props.options
    local borderRadius = props.borderRadius

    if #options == 0 then
        return
    end

    -- Calculate panel dimensions. Flip upward near the bottom edge.
    local metrics = self:GetPanelMetrics(l)
    self:ApplyPanelMetrics(metrics)
    local itemHeight = metrics.itemHeight
    local visibleItems = metrics.visibleItems
    local vertInset = metrics.vertInset
    local panelHeight = metrics.height
    local panelY = metrics.y

    -- Panel background with shadow
    local boxShadow = props.boxShadow
    if boxShadow == false then
        -- Explicitly disabled.
    elseif boxShadow then
        local geom = self:GetShapeGeometry({ x = l.x, y = panelY, w = l.w, h = panelHeight }, nil, borderRadius)
        self:RenderBoxShadows(nvg, geom, boxShadow)
    else
        self:CreateShapePath(nvg, self:GetShapeGeometry(
            { x = l.x - 2, y = panelY - 2, w = l.w + 4, h = panelHeight + 4 },
            nil,
            Widget.OffsetRadius(borderRadius, 2)
        ))
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 40))
        nvgFill(nvg)
    end

    local popupBg = props.popupBgColor or Theme.Color("surface")
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = l.x, y = panelY, w = l.w, h = panelHeight }, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(popupBg[1], popupBg[2], popupBg[3], popupBg[4] or 255))
    nvgFill(nvg)

    -- Render options (with scroll offset support)
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    local baseFontSize = Theme.FontSizeOf("body")
    local padding = 12
    local scrollOffset = self.scrollOffset_
    local totalOptions = #options
    local hasScroll = totalOptions > visibleItems

    -- Clip options to panel (shrink right side when scrollbar is present)
    local scrollbarReserve = hasScroll and 12 or 0  -- scrollbarWidth(4) + margin(4) + gap(4)
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, panelY + vertInset, l.w - scrollbarReserve, panelHeight - vertInset * 2)

    local startIdx = scrollOffset + 1
    local endIdx = math.min(startIdx + visibleItems - 1, totalOptions)

    for i = startIdx, endIdx do
        local option = options[i]
        local displayIdx = i - startIdx  -- 0-based display position
        local itemY = panelY + vertInset + displayIdx * itemHeight
        local isHovered = state.hoveredIndex == i
        local isSelected = props.value == option.value
        local isDisabled = option.disabled

        -- Item background (hover/selected)
        local itemHoverInset = self.props.itemHoverInset ~= nil and self.props.itemHoverInset or 4
        local itemRadius = self.props.itemHoverRadius ~= nil and self.props.itemHoverRadius or 4
        -- Auto-round corners for items near panel edges
        local maxBorderRadius = type(borderRadius) == "table"
            and math.max(borderRadius[1] or 0, borderRadius[2] or 0, borderRadius[3] or 0, borderRadius[4] or 0)
            or borderRadius
        local touchesTop = itemY - panelY < maxBorderRadius
        local touchesBottom = panelY + panelHeight - (itemY + itemHeight) < maxBorderRadius
        if touchesTop and touchesBottom then
            itemRadius = borderRadius
        elseif touchesTop then
            local top = Widget.TopRadius(borderRadius)
            local bottom = Widget.BottomRadius(itemRadius)
            itemRadius = { top[1], top[2], bottom[3], bottom[4] }
        elseif touchesBottom then
            local top = Widget.TopRadius(itemRadius)
            local bottom = Widget.BottomRadius(borderRadius)
            itemRadius = { top[1], top[2], bottom[3], bottom[4] }
        end
        if isHovered and not isDisabled then
            self:CreateShapePath(nvg, self:GetShapeGeometry(
                { x = l.x + itemHoverInset, y = itemY, w = l.w - itemHoverInset * 2, h = itemHeight },
                nil,
                itemRadius
            ))
            local ddHoverColor = self.props.itemHoverBgColor
            if ddHoverColor then
                nvgFillColor(nvg, nvgRGBA(ddHoverColor[1], ddHoverColor[2], ddHoverColor[3], ddHoverColor[4] or 255))
            else
                nvgFillColor(nvg, nvgRGBA(Theme.Color("primary")[1], Theme.Color("primary")[2], Theme.Color("primary")[3], 30))
            end
            nvgFill(nvg)
        elseif isSelected then
            local selectedRadius = self.props.itemSelectedBorderRadius or itemRadius
            self:CreateShapePath(nvg, self:GetShapeGeometry(
                { x = l.x + itemHoverInset, y = itemY, w = l.w - itemHoverInset * 2, h = itemHeight },
                nil,
                selectedRadius
            ))
            local ddSelectedColor = self.props.itemSelectedColor or self.props.itemHoverBgColor
            if ddSelectedColor then
                nvgFillColor(nvg, nvgRGBA(ddSelectedColor[1], ddSelectedColor[2], ddSelectedColor[3], ddSelectedColor[4] or 255))
            else
                nvgFillColor(nvg, nvgRGBA(Theme.Color("primary")[1], Theme.Color("primary")[2], Theme.Color("primary")[3], 20))
            end
            nvgFill(nvg)
        end

        -- Item text
        local itemTextColor
        if isDisabled then
            itemTextColor = Theme.Color("disabledText")
        elseif isSelected then
            itemTextColor = self.props.itemSelectedTextColor or Theme.Color("primary")
        elseif isHovered then
            local hoverTextColor = self.props.itemHoverTextColor
            itemTextColor = hoverTextColor or Theme.Color("text")
        else
            itemTextColor = Theme.Color("text")
        end

        local itemFontFamily = fontFamily
        if isSelected and self.props.selectedFontWeight then
            itemFontFamily = Theme.FontFace(self.props.fontFamily, self.props.selectedFontWeight)
        end
        local checkmarkReserve = isSelected and 20 or 0
        local itemTextWidth = math.max(0,
            l.w - padding * 2 - scrollbarReserve - checkmarkReserve)
        local renderFontSize = baseFontSize
        if UI.defaultAutoFitText then
            local fitResult = UI.MeasureTextFit(option.label, {
                fontSize = baseFontSize,
                fontFace = itemFontFamily,
                width = itemTextWidth,
                height = math.max(0, itemHeight),
                multiline = false,
                minFontSize = props.minFontSize and Theme.FontSize(props.minFontSize) or 1,
                cache = self.autoFitOptionCaches_[i],
            })
            self.autoFitOptionCaches_[i] = fitResult
            renderFontSize = fitResult.fontSize or baseFontSize
        end
        nvgFontFace(nvg, itemFontFamily)
        nvgFontSize(nvg, renderFontSize)
        nvgFillColor(nvg, nvgRGBA(itemTextColor[1], itemTextColor[2], itemTextColor[3], itemTextColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if UI.defaultAutoFitText then
            nvgSave(nvg)
            nvgIntersectScissor(nvg, l.x + padding, itemY, itemTextWidth, itemHeight)
        end
        if UI.defaultAutoFitText then
            nvgText(nvg, l.x + padding, itemY + itemHeight / 2,
                option.label, nil, false)
        else
            nvgText(nvg, l.x + padding, itemY + itemHeight / 2, option.label, nil)
        end
        if UI.defaultAutoFitText then
            nvgRestore(nvg)
        end

        -- Checkmark for selected item
        if isSelected then
            local checkX = l.x + l.w - padding - 8
            local checkY = itemY + itemHeight / 2

            nvgBeginPath(nvg)
            nvgMoveTo(nvg, checkX - 4, checkY)
            nvgLineTo(nvg, checkX - 1, checkY + 3)
            nvgLineTo(nvg, checkX + 4, checkY - 3)
            local checkColor = self.props.itemSelectedTextColor or Theme.Color("primary")
            nvgStrokeColor(nvg, nvgRGBA(checkColor[1], checkColor[2], checkColor[3], checkColor[4] or 255))
            nvgStrokeWidth(nvg, 2)
            nvgLineCap(nvg, NVG_ROUND)
            nvgLineJoin(nvg, NVG_ROUND)
            nvgStroke(nvg)
        end
    end

    nvgRestore(nvg)

    -- Draw panel border on top of items (so hover doesn't cover it)
    self:CreateShapePath(nvg, self:GetShapeGeometry({ x = l.x, y = panelY, w = l.w, h = panelHeight }, nil, borderRadius))
    local popupBC = props.popupBorderColor or Theme.Color("border")
    nvgStrokeColor(nvg, nvgRGBA(popupBC[1], popupBC[2], popupBC[3], popupBC[4] or 255))
    nvgStrokeWidth(nvg, self.props.borderWidth or 1)
    nvgStroke(nvg)

    -- Draw scrollbar indicator when there are more items than visible
    if hasScroll then
        self:RenderScrollbar(nvg, l, panelY, panelHeight, scrollOffset, visibleItems, totalOptions)
    end
end

--- Render scrollbar indicator for the dropdown panel
---@param nvg NVGContextWrapper
---@param l table Absolute layout of the trigger
---@param panelY number Y position of the dropdown panel
---@param panelHeight number Height of the dropdown panel
---@param scrollOffset number Current scroll offset
---@param visibleItems number Number of visible items
---@param totalOptions number Total number of options
function Dropdown:RenderScrollbar(nvg, l, panelY, panelHeight, scrollOffset, visibleItems, totalOptions)
    local scrollbarWidth = 4
    local scrollbarX = l.x + l.w - scrollbarWidth - 4
    local vertInset = self.props.itemVerticalInset ~= nil and self.props.itemVerticalInset or 4
    local trackY = panelY + vertInset
    local trackHeight = panelHeight - vertInset * 2
    local maxOffset = totalOptions - visibleItems

    -- Scrollbar track (subtle background)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, scrollbarX, trackY, scrollbarWidth, trackHeight, scrollbarWidth / 2)
    nvgFillColor(nvg, nvgRGBA(Theme.Color("border")[1], Theme.Color("border")[2], Theme.Color("border")[3], 60))
    nvgFill(nvg)

    -- Scrollbar thumb
    local thumbRatio = visibleItems / totalOptions
    local thumbHeight = math.max(20, trackHeight * thumbRatio)
    local thumbRange = trackHeight - thumbHeight
    local thumbY = trackY + (maxOffset > 0 and (scrollOffset / maxOffset * thumbRange) or 0)

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, scrollbarX, thumbY, scrollbarWidth, thumbHeight, scrollbarWidth / 2)
    nvgFillColor(nvg, nvgRGBA(Theme.Color("textSecondary")[1], Theme.Color("textSecondary")[2], Theme.Color("textSecondary")[3], 150))
    nvgFill(nvg)
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Dropdown:OnMouseEnter()
    if not self.props.disabled then
        self:SetState({ hovered = true })
    end
end

function Dropdown:OnMouseLeave()
    self:SetState({ hovered = false, hoveredIndex = nil })
end

function Dropdown:OnClick(event)
    if self.props.disabled then
        return
    end

    -- Check if click is in dropdown panel
    if self.state.isOpen and event then
        local l = self:GetAbsoluteLayoutForHitTest()
        local metrics = self:GetPanelMetrics(l)
        local panelY = metrics.y
        local panelHeight = metrics.height

        if event.x >= l.x and event.x <= l.x + l.w and event.y >= panelY and event.y <= panelY + panelHeight then
            -- If we just finished a drag in the panel, skip selection
            if self.wasDragging_ then
                self.wasDragging_ = false
                return
            end

            -- Click in panel - select option (account for scroll offset)
            local itemHeight = metrics.itemHeight
            local displayIndex = math.floor((event.y - panelY - metrics.vertInset) / itemHeight)  -- 0-based display position
            local clickIndex = displayIndex + self.scrollOffset_ + 1  -- 1-based actual option index

            if clickIndex >= 1 and clickIndex <= #self.props.options then
                local option = self.props.options[clickIndex]
                if not option.disabled then
                    self:SelectOption(option)
                end
            end
            return
        end
    end

    -- Click on trigger area - always handle (wasDragging_ does not block trigger clicks)
    self.wasDragging_ = false
    self:SetOpen(not self.state.isOpen)
end

function Dropdown:OnPointerDown(event)
    -- When dropdown is open, consume the event to prevent bubbling to parent.
    -- Without this, Widget.OnPointerDown bubbles up the parent chain and reaches
    -- Modal:OnPointerDown, which interprets panel clicks (below modal bounds)
    -- as outside-modal clicks and closes the modal.
    if self.state.isOpen then
        if self.props.onPointerDown then
            self.props.onPointerDown(event, self)
        end
        return
    end
    Widget.OnPointerDown(self, event)
end

function Dropdown:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    if self.state.isOpen then
        -- Use GetAbsoluteLayoutForHitTest for proper scroll offset handling
        local l = self:GetAbsoluteLayoutForHitTest()
        local metrics = self:GetPanelMetrics(l)
        local panelY = metrics.y
        local panelHeight = metrics.height

        if event.x >= l.x and event.x <= l.x + l.w and event.y >= panelY and event.y <= panelY + panelHeight then
            local itemHeight = metrics.itemHeight
            local displayIndex = math.floor((event.y - panelY - metrics.vertInset) / itemHeight)  -- 0-based display position
            local hoverIndex = displayIndex + self.scrollOffset_ + 1  -- 1-based actual option index

            if hoverIndex >= 1 and hoverIndex <= #self.props.options then
                if self.state.hoveredIndex ~= hoverIndex then
                    self:SetState({ hoveredIndex = hoverIndex })
                end
            else
                self:SetState({ hoveredIndex = nil })
            end
        else
            self:SetState({ hoveredIndex = nil })
        end
    end
end

function Dropdown:OnBlur()
    if self.state.isOpen then
        self:SetOpen(false)
    end
end

function Dropdown:OnWheel(dx, dy)
    local visibleItems = self.dropdownVisibleItems_ or self.maxVisibleItems_
    if self.state.isOpen and #self.props.options > visibleItems then
        -- dy > 0 means scroll up (show earlier items), dy < 0 means scroll down
        self.scrollOffset_ = self.scrollOffset_ - dy
        self:ClampScrollOffset(visibleItems)
    end
end

-- ============================================================================
-- Pan Gesture (Touch Drag Scrolling)
-- ============================================================================

function Dropdown:OnPanStart(event)
    -- Only handle pan when dropdown is open and has scrollable content
    if not self.state.isOpen then
        return false
    end
    local visibleItems = self.dropdownVisibleItems_ or self.maxVisibleItems_
    if #self.props.options <= visibleItems then
        return false
    end

    -- Check if pan starts inside the dropdown panel area
    local l = self:GetAbsoluteLayoutForHitTest()
    local metrics = self:GetPanelMetrics(l)
    local panelY = metrics.y
    local panelHeight = metrics.height

    if event.x >= l.x and event.x <= l.x + l.w and
       event.y >= panelY and event.y <= panelY + panelHeight then
        -- Start dragging
        self.state.isDragging = true
        self.dragStartScrollOffset_ = self.scrollOffset_
        return true  -- We're handling this pan gesture
    end

    return false
end

function Dropdown:OnPanMove(event)
    if not self.state.isDragging then return end

    -- Convert pixel drag to scroll offset (items), snap to nearest integer
    local itemHeight = self.itemHeight_
    local deltaItems = -event.totalDeltaY / itemHeight
    self.scrollOffset_ = math.floor(self.dragStartScrollOffset_ + deltaItems + 0.5)
    self:ClampScrollOffset(self.dropdownVisibleItems_)
end

function Dropdown:OnPanEnd(event)
    if not self.state.isDragging then return end
    self.state.isDragging = false
    -- Mark that we just finished dragging, to prevent OnClick from selecting
    self.wasDragging_ = true
end

-- ============================================================================
-- Hit Test Override
-- ============================================================================

function Dropdown:HitTest(x, y)
    -- Use GetAbsoluteLayoutForHitTest for proper scroll offset handling
    local l = self:GetAbsoluteLayoutForHitTest()

    -- Check trigger area
    if x >= l.x and x <= l.x + l.w and y >= l.y and y <= l.y + l.h then
        return true
    end

    -- Check dropdown panel area if open
    if self.state.isOpen then
        local metrics = self:GetPanelMetrics(l)
        local panelY = metrics.y
        local panelHeight = metrics.height

        if x >= l.x and x <= l.x + l.w and y >= panelY and y <= panelY + panelHeight then
            return true
        end
    end

    return false
end

-- ============================================================================
-- Internal
-- ============================================================================

--- Unified open/close logic. All open/close paths go through here.
---@param open boolean Whether to open or close the dropdown
function Dropdown:SetOpen(open)
    if open then
        self:ScrollToSelected()
        self:SetState({ isOpen = true })
        UI.SetActiveOverlay(self)
    else
        self:SetState({ isOpen = false, hoveredIndex = nil })
        UI.ClearActiveOverlay()
        -- Intentionally bypass SetState for isDragging (no re-render needed)
        self.state.isDragging = false
        self.wasDragging_ = false
    end
end

--- Clamp scroll offset to valid range
function Dropdown:ClampScrollOffset(visibleItems)
    visibleItems = visibleItems or self.dropdownVisibleItems_ or self.maxVisibleItems_
    local maxOffset = math.max(0, #self.props.options - visibleItems)
    self.scrollOffset_ = math.max(0, math.min(self.scrollOffset_, maxOffset))
end

--- Scroll to show the currently selected item when opening
function Dropdown:ScrollToSelected()
    local value = self.props.value
    if value == nil then
        self.scrollOffset_ = 0
        return
    end

    -- Find index of selected option
    for i, option in ipairs(self.props.options) do
        if option.value == value then
            local visibleItems = self.dropdownVisibleItems_ or self.maxVisibleItems_
            -- Ensure selected item is visible
            if i <= self.scrollOffset_ then
                -- Selected item is above visible area
                self.scrollOffset_ = math.max(0, i - 1)
            elseif i > self.scrollOffset_ + visibleItems then
                -- Selected item is below visible area
                self.scrollOffset_ = i - visibleItems
            end
            -- else: already visible, keep current offset
            self:ClampScrollOffset(visibleItems)
            return
        end
    end

    -- Value not found in options, reset
    self.scrollOffset_ = 0
end

--- Get currently selected option
---@return DropdownOption|nil
function Dropdown:GetSelectedOption()
    local value = self.props.value
    if value == nil then
        return nil
    end

    for _, option in ipairs(self.props.options) do
        if option.value == value then
            return option
        end
    end

    return nil
end

--- Select an option
---@param option DropdownOption
function Dropdown:SelectOption(option)
    if option.disabled then
        return
    end

    self.props.value = option.value
    self:SetOpen(false)

    self:DispatchEvent("change", self, option.value, option)
    if self.props.onChange then
        self.props.onChange(self, option.value, option)
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set selected value
---@param value any
---@return Dropdown self
function Dropdown:SetValue(value)
    if self.props.value ~= value then
        self.props.value = value
        local option = self:GetSelectedOption()
        self:DispatchEvent("change", self, value, option)
        if self.props.onChange then
            self.props.onChange(self, value, option)
        end
    end
    return self
end

--- Get selected value
---@return any
function Dropdown:GetValue()
    return self.props.value
end

--- Get selected option
---@return DropdownOption|nil
function Dropdown:GetSelected()
    return self:GetSelectedOption()
end

--- Set options
---@param options DropdownOption[]
---@return Dropdown self
function Dropdown:SetOptions(options)
    self.props.options = options or {}
    self.scrollOffset_ = 0
    self.autoFitOptionCaches_ = {}
    -- Clear selection if current value not in new options
    if self.props.value ~= nil then
        local found = false
        for _, opt in ipairs(self.props.options) do
            if opt.value == self.props.value then
                found = true
                break
            end
        end
        if not found then
            self.props.value = nil
        end
    end
    return self
end

--- Add an option
---@param option DropdownOption
---@return Dropdown self
function Dropdown:AddOption(option)
    table.insert(self.props.options, option)
    return self
end

--- Remove option by value
---@param value any
---@return Dropdown self
function Dropdown:RemoveOption(value)
    for i, opt in ipairs(self.props.options) do
        if opt.value == value then
            table.remove(self.props.options, i)
            if self.props.value == value then
                self.props.value = nil
            end
            self.autoFitOptionCaches_ = {}
            break
        end
    end
    return self
end

--- Open dropdown
---@return Dropdown self
function Dropdown:Open()
    if not self.props.disabled then
        self:SetOpen(true)
    end
    return self
end

--- Close dropdown
---@return Dropdown self
function Dropdown:Close()
    self:SetOpen(false)
    return self
end

--- Toggle dropdown
---@return Dropdown self
function Dropdown:Toggle()
    if not self.props.disabled then
        self:SetOpen(not self.state.isOpen)
    end
    return self
end

--- Set disabled state
---@param disabled boolean
---@return Dropdown self
function Dropdown:SetDisabled(disabled)
    self.props.disabled = disabled
    if disabled then
        self:SetState({ isOpen = false, hovered = false, hoveredIndex = nil })
    end
    return self
end

--- Check if dropdown is open
---@return boolean
function Dropdown:IsOpen()
    return self.state.isOpen == true
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Dropdown:IsStateful()
    return true
end

return Dropdown
