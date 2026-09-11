-- ============================================================================
-- Menu Widget
-- Context menu, dropdown menu, and navigation menu component
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class MenuItem
---@field id? string|number Item identifier
---@field label? string Item label
---@field text? string Alias for label
---@field icon? string Icon name
---@field shortcut? string Keyboard shortcut text
---@field disabled? boolean Is item disabled
---@field checked? boolean Show checkmark
---@field type? string "item" | "divider" | "header" | "submenu"
---@field items? MenuItem[] Submenu items

---@class MenuProps : WidgetProps
---@field items? MenuItem[] Menu items
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field variant? string "elevated" | "outlined" | "flat" (default: "elevated")
---@field backgroundGradient? table Menu panel gradient { direction, from, to }
---@field dense? boolean Use dense layout
---@field showIcons? boolean Show icons (default: true)
---@field showShortcuts? boolean Show shortcuts (default: true)
---@field isOpen? boolean Menu open state
---@field anchorX? number Anchor X position
---@field anchorY? number Anchor Y position
---@field anchorOrigin? string Anchor origin "top-left" | "top-right" | "bottom-left" | "bottom-right"
---@field fontSize? number Custom font size
---@field iconSize? number Custom icon size
---@field itemBgColor? RGBAColor|string|false Normal item background color; false disables fill
---@field itemBoxShadow? table|false Normal item shadow; false disables shadow
---@field itemHoverFontWeight? string Font weight for hovered/active menu item (default: fontWeight)
---@field itemDisabledTextColor? RGBAColor|string Disabled item text color
---@field itemVerticalInset? number Vertical inset for items area from panel top/bottom edge (default: padding)
---@field itemMargin? number|table Item outer margin: number for all sides or {top,right,bottom,left}
---@field itemMarginX? number Item horizontal outer margin
---@field itemMarginY? number Item vertical outer margin
---@field itemGap? number Gap between item/header rows
---@field headerItemGap? number Gap after a header row before following items
---@field onItemClick? fun(self: Menu, item: MenuItem) Item click callback
---@field onClose? fun(self: Menu) Close callback

---@class Menu : Widget
---@overload fun(props?: MenuProps): Menu
---@field props MenuProps
---@field new fun(self, props?: MenuProps): Menu
---@field AddChild fun(self, child: Widget): self Add child widget
---@field RemoveChild fun(self, child: Widget): self Remove child widget
local Menu = Widget:Extend("Menu")

local function hasAnyPaddingProp(props)
    return props.padding ~= nil
        or props.paddingTop ~= nil
        or props.paddingRight ~= nil
        or props.paddingBottom ~= nil
        or props.paddingLeft ~= nil
        or props.paddingHorizontal ~= nil
        or props.paddingVertical ~= nil
end

local function parseBox(value)
    local top, right, bottom, left = 0, 0, 0, 0
    if type(value) == "number" then
        top, right, bottom, left = value, value, value, value
    elseif type(value) == "table" then
        if #value == 1 then
            top, right, bottom, left = value[1], value[1], value[1], value[1]
        elseif #value == 2 then
            top, bottom = value[1], value[1]
            right, left = value[2], value[2]
        elseif #value == 3 then
            top = value[1]
            right, left = value[2], value[2]
            bottom = value[3]
        elseif #value >= 4 then
            top, right, bottom, left = value[1], value[2], value[3], value[4]
        end
        if value.vertical then top, bottom = value.vertical, value.vertical end
        if value.horizontal then right, left = value.horizontal, value.horizontal end
        if value.top then top = value.top end
        if value.right then right = value.right end
        if value.bottom then bottom = value.bottom end
        if value.left then left = value.left end
    end
    return top or 0, right or 0, bottom or 0, left or 0
end

local function getGapBetweenItems(menu, previousItem, item)
    if not previousItem then
        return 0
    end
    if previousItem.type == "header" then
        return menu.headerItemGap_ or 0
    end
    if previousItem.type ~= "divider" and item.type ~= "divider" then
        return menu.itemGap_ or 0
    end
    return 0
end

-- ============================================================================
-- Size presets
-- ============================================================================

local SIZE_PRESETS = {
    sm = { itemHeight = 28, fontSize = 12, iconSize = 14, padding = 6, minWidth = 120 },
    md = { itemHeight = 36, fontSize = 14, iconSize = 18, padding = 8, minWidth = 160 },
    lg = { itemHeight = 44, fontSize = 16, iconSize = 22, padding = 10, minWidth = 200 },
}

-- ============================================================================
-- Item types
-- ============================================================================

local ITEM_TYPES = {
    item = "item",
    divider = "divider",
    header = "header",
    submenu = "submenu",
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props MenuProps?
function Menu:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Menu")
    Style.ApplyDefaults(props, themeStyle)

    -- Menu props
    self.items_ = props.items or {}
    self.size_ = props.size or "md"
    self.variant_ = props.variant or "elevated"  -- elevated, outlined, flat
    self.dense_ = props.dense or false
    self.showIcons_ = props.showIcons ~= false  -- default true
    self.showShortcuts_ = props.showShortcuts ~= false  -- default true

    -- Position (for popup menus)
    self.anchorX_ = props.anchorX or 0
    self.anchorY_ = props.anchorY or 0
    self.anchorOrigin_ = props.anchorOrigin or "top-left"  -- top-left, top-right, bottom-left, bottom-right

    -- Callbacks
    self.onItemClick_ = props.onItemClick
    self.onClose_ = props.onClose

    -- State
    self.isOpen_ = props.isOpen or true
    self.hoverIndex_ = nil
    self.activeSubmenu_ = nil
    self.submenuWidget_ = nil

    -- Calculate dimensions
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    self.itemHeight_ = self.dense_ and (sizePreset.itemHeight * 0.8) or sizePreset.itemHeight
    self.fontSize_ = props.fontSize and Theme.FontSize(props.fontSize) or Theme.FontSize(sizePreset.fontSize)
    self.iconSize_ = props.iconSize or sizePreset.iconSize
    if not hasAnyPaddingProp(props) then
        props.padding = sizePreset.padding
    end
    Widget.ExpandPaddingShorthand(props)
    self.paddingTop_ = props.paddingTop or 0
    self.paddingRight_ = props.paddingRight or 0
    self.paddingBottom_ = props.paddingBottom or 0
    self.paddingLeft_ = props.paddingLeft or 0
    -- Keep the old uniform padding field as a left-padding alias for legacy formulas.
    self.padding_ = self.paddingLeft_
    self.itemVerticalInset_ = props.itemVerticalInset
    self.itemsTopInset_ = self.itemVerticalInset_ ~= nil and self.itemVerticalInset_ or self.paddingTop_
    self.itemsBottomInset_ = self.itemVerticalInset_ ~= nil and self.itemVerticalInset_ or self.paddingBottom_
    self.hasItemMargin_ = props.itemMargin ~= nil or props.itemMarginX ~= nil or props.itemMarginY ~= nil
    self.itemMarginTop_, self.itemMarginRight_, self.itemMarginBottom_, self.itemMarginLeft_ = parseBox(props.itemMargin)
    if props.itemMarginX ~= nil then
        self.itemMarginLeft_ = props.itemMarginX
        self.itemMarginRight_ = props.itemMarginX
    end
    if props.itemMarginY ~= nil then
        self.itemMarginTop_ = props.itemMarginY
        self.itemMarginBottom_ = props.itemMarginY
    end
    self.itemGap_ = props.itemGap or 0
    self.headerItemGap_ = props.headerItemGap ~= nil and props.headerItemGap or self.itemGap_
    self.minWidth_ = props.minWidth or sizePreset.minWidth

    -- Auto-calculate minWidth from item labels to prevent text overflow
    if not props.width then
        local hasIcons = false
        local hasSubmenu = false
        for _, item in ipairs(self.items_) do
            if item.icon or item.checked ~= nil then hasIcons = true end
            if item.items then hasSubmenu = true end
        end
        local iconColW = hasIcons and (self.iconSize_ + self.paddingLeft_) or 0
        local arrowColW = hasSubmenu and self.iconSize_ or 0
        local marginW = self.hasItemMargin_ and (self.itemMarginLeft_ + self.itemMarginRight_) or 0
        local extraPadding = self.paddingLeft_ + self.paddingRight_ + marginW + iconColW + self.paddingLeft_ + arrowColW + self.paddingRight_
        if arrowColW > 0 then extraPadding = extraPadding + self.paddingRight_ end

        for _, item in ipairs(self.items_) do
            if item.type ~= "divider" then
                local label = item.label or item.text or ""
                local labelW = UI.MeasureTextWidth(label, self.fontSize_, props.fontFamily)
                local shortcutW = 0
                if item.shortcut then
                    shortcutW = UI.MeasureTextWidth(item.shortcut, self.fontSize_ * 0.85, props.fontFamily) + self.paddingRight_ * 2
                end
                local needed = extraPadding + labelW + shortcutW
                if needed > self.minWidth_ then
                    self.minWidth_ = needed
                end
            end
        end
    end

    -- Calculate height based on items
    local totalHeight = self.itemsTopInset_ + self.itemsBottomInset_
    local previousItem = nil
    for _, item in ipairs(self.items_) do
        totalHeight = totalHeight + getGapBetweenItems(self, previousItem, item)
        if item.type == "divider" then
            totalHeight = totalHeight + (props.dividerSpacing or 4) * 2 + (props.dividerWidth or 1)
        elseif item.type == "header" then
            totalHeight = totalHeight + self.itemHeight_ * 0.8
        else
            totalHeight = totalHeight + self.itemMarginTop_ + self.itemHeight_ + self.itemMarginBottom_
        end
        previousItem = item
    end

    props.width = props.width or self.minWidth_
    props.height = props.height or totalHeight
    props.borderRadius = props.borderRadius or 8

    Widget.Init(self, props)
end

-- ============================================================================
-- Menu State
-- ============================================================================

--- Check if Menu is visible
---@return boolean
function Menu:IsVisible()
    return self.props.visible ~= false and self.isOpen_
end

function Menu:IsOpen()
    return self.isOpen_
end

function Menu:Open(x, y)
    self.isOpen_ = true
    if x then self.anchorX_ = x end
    if y then self.anchorY_ = y end
end

function Menu:Close()
    self.isOpen_ = false
    self.hoverIndex_ = nil
    self:CloseSubmenu()
    if self.onClose_ then
        self.onClose_(self)
    end
end

function Menu:Toggle()
    if self.isOpen_ then
        self:Close()
    else
        self:Open()
    end
end

-- ============================================================================
-- Items Management
-- ============================================================================

function Menu:GetItems()
    return self.items_
end

function Menu:SetItems(items)
    self.items_ = items or {}
end

function Menu:AddItem(item)
    table.insert(self.items_, item)
end

function Menu:RemoveItem(index)
    table.remove(self.items_, index)
end

-- ============================================================================
-- Submenu Management
-- ============================================================================

function Menu:OpenSubmenu(item, x, y)
    self:CloseSubmenu()

    if item.items and #item.items > 0 then
        self.activeSubmenu_ = item
        self.submenuWidget_ = Menu {
            items = item.items,
            size = self.size_,
            variant = self.variant_,
            dense = self.dense_,
            anchorX = x,
            anchorY = y,
            onItemClick = function(menu, clickedItem, index)
                if self.onItemClick_ then
                    self.onItemClick_(self, clickedItem, index)
                end
                self:Close()
            end,
        }
    end
end

function Menu:CloseSubmenu()
    self.activeSubmenu_ = nil
    self.submenuWidget_ = nil
end

-- ============================================================================
-- Drawing Helpers
-- ============================================================================

function Menu:DrawIcon(nvg, x, y, icon, color, iconSize)
    nvgFontSize(nvg, iconSize)
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, color)
    nvgText(nvg, x, y, icon)
end

function Menu:DrawCheckmark(nvg, x, y, color, iconSize)
    local size = iconSize * 0.5

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x - size * 0.5, y)
    nvgLineTo(nvg, x - size * 0.1, y + size * 0.4)
    nvgLineTo(nvg, x + size * 0.5, y - size * 0.3)
    nvgStrokeColor(nvg, color)
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
end

function Menu:DrawSubmenuArrow(nvg, x, y, color, fontSize)
    local size = fontSize * 0.3

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x - size * 0.3, y - size)
    nvgLineTo(nvg, x + size * 0.5, y)
    nvgLineTo(nvg, x - size * 0.3, y + size)
    nvgStrokeColor(nvg, color)
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

-- ============================================================================
-- Render
-- ============================================================================

function Menu:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()
    local theme = Theme.GetTheme()

    -- Size values (no scale needed - nvgScale handles it)
    local itemHeight = self.itemHeight_
    -- Use the Init-computed font size so props.fontSize (theme override) applies to drawn text,
    -- not just the width/height measurement.
    local fontSize = self.fontSize_
    local iconSize = self.iconSize_
    local paddingLeft = self.paddingLeft_
    local paddingRight = self.paddingRight_
    local padding = paddingLeft
    local borderRadius = self.props.borderRadius

    -- Apply anchor position
    x = x + self.anchorX_
    y = y + self.anchorY_

    -- Draw shadow
    local boxShadow = self.props.boxShadow
    if boxShadow == false then
        -- Explicitly disabled.
    elseif boxShadow then
        local geom = self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, borderRadius)
        self:RenderBoxShadows(nvg, geom, boxShadow)
    elseif self.variant_ == "elevated" then
        -- Shadow layers
        for i = 3, 1, -1 do
            local shadowOffset = i
            self:CreateShapePath(nvg, self:GetShapeGeometry(
                { x = x - shadowOffset, y = y + shadowOffset * 2, w = w + shadowOffset * 2, h = h + shadowOffset * 2 },
                nil,
                Widget.OffsetRadius(borderRadius, shadowOffset)
            ))
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 15 * i))
            nvgFill(nvg)
        end
    end

    -- Draw background
    local backgroundColor = self.props.backgroundColor or Theme.Color("surface")
    local menuGeom = self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, borderRadius)
    self:CreateShapePath(nvg, menuGeom)
    nvgFillColor(nvg, nvgRGBA(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4] or 255))
    nvgFill(nvg)
    if self.props.backgroundGradient then
        self:RenderGradientBackground(nvg, menuGeom, self.props.backgroundGradient)
    end

    -- Store item positions for hit testing
    self.itemPositions_ = {}

    local currentY = y + self.itemsTopInset_
    local contentX = x + paddingLeft
    local contentWidth = w - paddingLeft - paddingRight

    -- Calculate icon column width
    local hasIcons = false
    local hasCheckable = false
    local hasSubmenu = false

    for _, item in ipairs(self.items_) do
        if item.icon then hasIcons = true end
        if item.checked ~= nil then hasCheckable = true end
        if item.items then hasSubmenu = true end
    end

    local iconColWidth = (hasIcons or hasCheckable) and (iconSize + paddingLeft) or 0
    local arrowColWidth = hasSubmenu and (iconSize) or 0
    local previousItem = nil

    for i, item in ipairs(self.items_) do
        currentY = currentY + getGapBetweenItems(self, previousItem, item)

        if item.type == "divider" then
            -- Draw divider: inset shortens the line from both content edges, spacing is the
            -- vertical gap above/below, width is the stroke thickness. Footprint = 2*spacing + width.
            local dividerSpacing = self.props.dividerSpacing or 4
            local dividerWidth = self.props.dividerWidth or 1
            local dividerInset = self.props.dividerInset or 0
            local dividerColor = self.props.dividerColor or Theme.Color("border")
            currentY = currentY + dividerSpacing
            nvgBeginPath(nvg)
            -- Inset measured from the panel edges (not the content/padding area), so dividerInset=0
            -- spans the full panel width edge-to-edge; increasing it shrinks symmetrically from both sides.
            nvgMoveTo(nvg, x + dividerInset, currentY)
            nvgLineTo(nvg, x + w - dividerInset, currentY)
            nvgStrokeColor(nvg, nvgRGBA(dividerColor[1], dividerColor[2], dividerColor[3], dividerColor[4] or 255))
            nvgStrokeWidth(nvg, dividerWidth)
            nvgStroke(nvg)
            currentY = currentY + dividerWidth + dividerSpacing
        elseif item.type == "header" then
            -- Draw header
            local headerHeight = itemHeight * 0.8
            nvgFontSize(nvg, fontSize * 0.85)
            nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
            nvgText(nvg, contentX + iconColWidth, currentY + headerHeight / 2, item.label or item.text or "")
            currentY = currentY + headerHeight
        else
            -- Draw menu item
            local itemY = currentY + self.itemMarginTop_
            local itemH = itemHeight
            local isHovered = self.hoverIndex_ == i
            local isDisabled = item.disabled
            local isActive = item == self.activeSubmenu_

            local legacyItemInset = self.props.itemHoverInset ~= nil and self.props.itemHoverInset or padding
            local itemX, itemW
            if self.hasItemMargin_ then
                itemX = x + self.itemMarginLeft_
                itemW = w - self.itemMarginLeft_ - self.itemMarginRight_
            else
                itemX = x + legacyItemInset
                itemW = w - legacyItemInset * 2
            end
            itemW = math.max(0, itemW)

            local maxBorderRadius = type(borderRadius) == "table"
                and math.max(borderRadius[1] or 0, borderRadius[2] or 0, borderRadius[3] or 0, borderRadius[4] or 0)
                or borderRadius
            local itemHoverRadius = self.props.itemHoverRadius ~= nil and self.props.itemHoverRadius or math.floor(maxBorderRadius / 2)
            -- Auto-round corners for items near container edges.
            local touchesTop = itemY - y < maxBorderRadius
            local touchesBottom = y + h - (itemY + itemH) < maxBorderRadius
            local itemRadius = itemHoverRadius
            if touchesTop and touchesBottom then
                itemRadius = borderRadius
            elseif touchesTop then
                local top = Widget.TopRadius(borderRadius)
                local bottom = Widget.BottomRadius(itemHoverRadius)
                itemRadius = { top[1], top[2], bottom[3], bottom[4] }
            elseif touchesBottom then
                local top = Widget.TopRadius(itemHoverRadius)
                local bottom = Widget.BottomRadius(borderRadius)
                itemRadius = { top[1], top[2], bottom[3], bottom[4] }
            end
            local itemGeom = self:GetShapeGeometry(
                { x = itemX, y = itemY, w = itemW, h = itemH },
                nil,
                itemRadius
            )

            local itemBoxShadow = self.props.itemBoxShadow
            if itemBoxShadow and itemBoxShadow ~= false then
                self:RenderBoxShadows(nvg, itemGeom, itemBoxShadow)
            end

            local itemBgColor = self.props.itemBgColor
            if itemBgColor and itemBgColor ~= false then
                self:CreateShapePath(nvg, itemGeom)
                nvgFillColor(nvg, nvgRGBA(itemBgColor[1], itemBgColor[2], itemBgColor[3], itemBgColor[4] or 255))
                nvgFill(nvg)
            end

            -- Hover/active background
            if (isHovered or isActive) and not isDisabled then
                self:CreateShapePath(nvg, itemGeom)
                local itemHoverBgColor = self.props.itemHoverBgColor
                if itemHoverBgColor then
                    nvgFillColor(nvg, nvgRGBA(itemHoverBgColor[1], itemHoverBgColor[2], itemHoverBgColor[3], itemHoverBgColor[4] or 255))
                else
                    local primaryColor = Theme.Color("primary")
                    nvgFillColor(nvg, nvgTransRGBAf(nvgRGBA(primaryColor[1], primaryColor[2], primaryColor[3], primaryColor[4] or 255), 0.1))
                end
                nvgFill(nvg)
            end

            -- Text color
            local textColor
            if isDisabled then
                local disabledText = self.props.itemDisabledTextColor or Theme.Color("textDisabled")
                textColor = nvgRGBA(disabledText[1], disabledText[2], disabledText[3], disabledText[4] or 255)
            elseif isHovered or isActive then
                local htc = self.props.itemHoverTextColor
                textColor = htc and nvgRGBA(htc[1], htc[2], htc[3], htc[4] or 255)
                    or Theme.NvgColor("primary")
            else
                textColor = Theme.NvgColor("text")
            end

            local itemContentX = self.hasItemMargin_ and itemX or contentX
            local itemRight = self.hasItemMargin_ and (itemX + itemW) or (x + w - paddingRight)
            local textX = itemContentX + iconColWidth + paddingLeft
            local centerY = itemY + itemH / 2

            -- Draw check mark or icon
            if item.checked then
                self:DrawCheckmark(nvg, itemContentX + iconColWidth / 2, centerY, textColor, iconSize)
            elseif item.icon and self.showIcons_ then
                self:DrawIcon(nvg, itemContentX + iconColWidth / 2, centerY, item.icon, textColor, iconSize)
            end

            -- Draw label
            local itemFontWeight = (isHovered or isActive) and (self.props.itemHoverFontWeight or self.props.fontWeight) or self.props.fontWeight
            nvgFontSize(nvg, fontSize)
            nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, itemFontWeight))
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, textColor)
            nvgText(nvg, textX, centerY, item.label or item.text or "")

            -- Draw shortcut
            if item.shortcut and self.showShortcuts_ then
                nvgFontSize(nvg, fontSize * 0.85)
                nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, isDisabled and textColor or Theme.NvgColor("textSecondary"))
                nvgText(nvg, itemRight - arrowColWidth - paddingRight, centerY, item.shortcut)
            end

            -- Draw submenu arrow
            if item.items and #item.items > 0 then
                self:DrawSubmenuArrow(nvg, itemRight - arrowColWidth / 2, centerY, textColor, fontSize)
            end

            -- Store position for hit testing
            local hitX1 = self.hasItemMargin_ and itemX or contentX
            local hitX2 = self.hasItemMargin_ and (itemX + itemW) or (contentX + contentWidth)
            self.itemPositions_[i] = {
                x1 = hitX1,
                x2 = hitX2,
                y1 = itemY,
                y2 = itemY + itemH,
                item = item,
                index = i,
            }

            currentY = currentY + self.itemMarginTop_ + itemHeight + self.itemMarginBottom_
        end

        previousItem = item
    end

    -- Draw border on top of items (so hover doesn't cover it)
    if self.variant_ == "outlined" then
        local borderColor = self.props.borderColor or Theme.Color("border")
        self:CreateShapePath(nvg, self:GetShapeGeometry({ x = x, y = y, w = w, h = h }, nil, borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, self.props.borderWidth or 1)
        nvgStroke(nvg)
    end

    -- Render submenu
    if self.submenuWidget_ then
        self.submenuWidget_:Render(nvg)
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function Menu:GetItemAtPosition(screenX, screenY)
    if not self.itemPositions_ then return nil end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y

    -- Convert screen coords to render coords
    local px = screenX + offsetX
    local py = screenY + offsetY

    -- Use pairs instead of ipairs because itemPositions_ may have gaps (dividers/headers don't store positions)
    for i, pos in pairs(self.itemPositions_) do
        if px >= pos.x1 and px <= pos.x2 and py >= pos.y1 and py <= pos.y2 then
            return pos
        end
    end

    return nil
end

function Menu:OnPointerMove(event)
    if not event then return end
    if not self.isOpen_ then return end

    -- Check submenu first
    if self.submenuWidget_ then
        self.submenuWidget_:OnPointerMove(event)
    end

    local itemPos = self:GetItemAtPosition(event.x, event.y)

    if itemPos and not itemPos.item.disabled and itemPos.item.type ~= "divider" and itemPos.item.type ~= "header" then
        self.hoverIndex_ = itemPos.index

        -- Open submenu on hover
        if itemPos.item.items and #itemPos.item.items > 0 then
            local x, y = self:GetAbsolutePosition()
            local w = self:GetComputedSize()
            self:OpenSubmenu(itemPos.item, x + w + self.anchorX_, itemPos.y1 - y)
        else
            self:CloseSubmenu()
        end
    else
        self.hoverIndex_ = nil
    end
end

function Menu:OnMouseLeave()
    -- Don't clear hover if moving to submenu
    if not self.submenuWidget_ then
        self.hoverIndex_ = nil
    end
end

function Menu:OnClick(event)
    if not event then return end
    if not self.isOpen_ then return end

    -- Check submenu first
    if self.submenuWidget_ then
        self.submenuWidget_:OnClick(event)
        return
    end

    local itemPos = self:GetItemAtPosition(event.x, event.y)

    if itemPos and not itemPos.item.disabled then
        local item = itemPos.item

        -- Skip dividers and headers
        if item.type == "divider" or item.type == "header" then
            return
        end

        -- Handle checkable items
        if item.checked ~= nil then
            item.checked = not item.checked
        end

        -- Skip if has submenu (handled by hover)
        if item.items and #item.items > 0 then
            return
        end

        -- Call item onClick
        if item.onClick then
            item.onClick(item, itemPos.index)
        end

        -- Call menu onItemClick
        if self.onItemClick_ then
            self.onItemClick_(self, item, itemPos.index)
        end

        -- Close menu after selection (unless specified otherwise)
        if item.keepOpen ~= true then
            self:Close()
        end
    end
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a simple menu from labels
---@param labels string[] Array of labels
---@param onClick function Click handler
---@param props table|nil Additional props
---@return Menu
function Menu.FromLabels(labels, onClick, props)
    props = props or {}

    local items = {}
    for i, label in ipairs(labels) do
        if label == "-" or label == "---" then
            table.insert(items, { type = "divider" })
        else
            table.insert(items, {
                label = label,
                onClick = function(item, index)
                    if onClick then onClick(label, index) end
                end,
            })
        end
    end

    props.items = items
    return Menu(props)
end

--- Create a context menu
---@param items table[] Menu items
---@param x number X position
---@param y number Y position
---@param props table|nil Additional props
---@return Menu
function Menu.Context(items, x, y, props)
    props = props or {}
    props.items = items
    props.anchorX = x
    props.anchorY = y
    props.variant = props.variant or "elevated"
    return Menu(props)
end

--- Create an action menu (common actions)
---@param actions table Action handlers { onCut, onCopy, onPaste, onDelete, ... }
---@param props table|nil Additional props
---@return Menu
function Menu.Actions(actions, props)
    props = props or {}

    local items = {}

    if actions.onUndo then
        table.insert(items, { label = "Undo", icon = "U", shortcut = "Ctrl+Z", onClick = actions.onUndo })
    end
    if actions.onRedo then
        table.insert(items, { label = "Redo", icon = "R", shortcut = "Ctrl+Y", onClick = actions.onRedo })
    end
    if actions.onUndo or actions.onRedo then
        table.insert(items, { type = "divider" })
    end

    if actions.onCut then
        table.insert(items, { label = "Cut", icon = "X", shortcut = "Ctrl+X", onClick = actions.onCut })
    end
    if actions.onCopy then
        table.insert(items, { label = "Copy", icon = "C", shortcut = "Ctrl+C", onClick = actions.onCopy })
    end
    if actions.onPaste then
        table.insert(items, { label = "Paste", icon = "V", shortcut = "Ctrl+V", onClick = actions.onPaste })
    end
    if actions.onCut or actions.onCopy or actions.onPaste then
        table.insert(items, { type = "divider" })
    end

    if actions.onSelectAll then
        table.insert(items, { label = "Select All", shortcut = "Ctrl+A", onClick = actions.onSelectAll })
    end
    if actions.onDelete then
        table.insert(items, { label = "Delete", icon = "D", shortcut = "Del", onClick = actions.onDelete })
    end

    props.items = items
    return Menu(props)
end

--- Create a navigation menu
---@param routes table[] Array of { label, path, icon, children }
---@param onNavigate function Navigation handler
---@param props table|nil Additional props
---@return Menu
function Menu.Navigation(routes, onNavigate, props)
    props = props or {}

    local function buildItems(routeList)
        local items = {}
        for _, route in ipairs(routeList) do
            local item = {
                label = route.label,
                icon = route.icon,
                onClick = function()
                    if onNavigate then onNavigate(route.path, route) end
                end,
            }

            if route.children and #route.children > 0 then
                item.items = buildItems(route.children)
            end

            table.insert(items, item)
        end
        return items
    end

    props.items = buildItems(routes)
    return Menu(props)
end

--- Create a select menu (single selection)
---@param options table[] Array of { label, value }
---@param selectedValue any Currently selected value
---@param onSelect function Selection handler
---@param props table|nil Additional props
---@return Menu
function Menu.Select(options, selectedValue, onSelect, props)
    props = props or {}

    local items = {}
    for _, opt in ipairs(options) do
        table.insert(items, {
            label = opt.label,
            checked = opt.value == selectedValue,
            onClick = function()
                if onSelect then onSelect(opt.value, opt) end
            end,
        })
    end

    props.items = items
    return Menu(props)
end

return Menu
