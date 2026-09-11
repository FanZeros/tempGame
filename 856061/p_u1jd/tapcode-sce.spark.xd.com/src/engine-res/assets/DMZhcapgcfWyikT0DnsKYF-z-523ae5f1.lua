-- ============================================================================
-- UIInspector - Panel Module
-- Inspector Yoga panel building, confirm dialog, clipboard copy
-- ============================================================================

return function(ctx, QuickTweak, Report, Overlay)

local M = {}
local isWidgetAlive = ctx.isWidgetAlive
local formatSource = ctx.formatSource
local Theme = require("urhox-libs/UI/Core/Theme")
local unpackList = table.unpack or unpack
local defaultColors = Theme.defaultTheme.colors
local inspectorColors = {
    overlay = { 0, 0, 0, 190 },
    background = { 27, 27, 32, 210 },
    border = { 255, 255, 255, 46 },
    borderFocus = { 255, 255, 255, 120 },
    text = { 255, 255, 255, 245 },
    textSecondary = { 255, 255, 255, 170 },
    inputBg = { 38, 38, 46, 255 },
    inputBorder = { 255, 255, 255, 42 },
    inputSelection = { 255, 255, 255, 72 },
    buttonBg = { 50, 50, 58, 255 },
    buttonHoverBg = { 62, 62, 70, 255 },
    buttonPressedBg = { 42, 42, 48, 255 },
    primaryBg = { 255, 255, 255, 245 },
    primaryHoverBg = { 238, 238, 242, 255 },
    primaryPressedBg = { 218, 218, 224, 255 },
    primaryText = { 24, 24, 28, 255 },
}
local PICKING_TIPS_HEIGHT = 34
local PICKING_TIPS_MARGIN = 8
local PICKING_TIPS_FONT_SIZE = 12
local PICKING_TIPS_HANDLE_WIDTH = 12
local PICKING_TIPS_BUTTON_HINT_FONT_SIZE = 7
local PICKING_TIPS_BUTTON_HINT_MARGIN_TOP = 5
local PICKING_TIPS_PADDING_LEFT = 12
local PICKING_TIPS_PADDING_RIGHT = 12
local PICKING_TIPS_GAP = 8
local PICKING_TIPS_MIN_VISIBLE_RATIO = 0.3
local PICKING_TIPS_ACTION_TEXT = _tr("t_xsDsr9UFxRZK1gW1")
local RESULT_TOAST_MIN_WIDTH = 180
local RESULT_TOAST_PADDING_X = 16
local RESULT_TOAST_FONT_SIZE = 12
local RESULT_TOAST_HEIGHT = 34
local RESULT_TOAST_TOP = 48
local RESULT_TOAST_DURATION = 2.4
local INSPECTOR_WIDTH = 430
local INSPECTOR_TOP = 54
local INSPECTOR_MARGIN = 12
local INSPECTOR_COLLAPSED_HEIGHT = 50
local INSPECTOR_RESIZE_HANDLE_HEIGHT = 14
local INSPECTOR_MIN_HEIGHT_RATIO = 0.5
local SELECTED_WIDGET_INFO_COLLAPSED_COUNT = 2
local SELECTED_WIDGET_INFO_ROW_GAP = 2
local SELECTED_WIDGET_INFO_ENTRY_GAP = 3

local function fixedButtonProps(props)
    props.textColor = props.textColor or defaultColors.text
    props.backgroundColor = props.backgroundColor or defaultColors.secondary
    if props.paddingLeft == nil and props.paddingRight == nil and props.paddingHorizontal == nil then
        props.paddingHorizontal = 12
    end
    props.hoverBackgroundColor = props.hoverBackgroundColor or defaultColors.secondaryHover
    props.pressedBackgroundColor = props.pressedBackgroundColor or defaultColors.secondaryPressed
    props.disabledBackgroundColor = props.disabledBackgroundColor or defaultColors.disabled
    props.borderRadius = props.borderRadius or 4
    props.borderWidth = 0
    return props
end

local function primaryButtonProps(props)
    props = props or {}
    props.backgroundColor = props.backgroundColor or inspectorColors.primaryBg
    props.hoverBackgroundColor = props.hoverBackgroundColor or inspectorColors.primaryHoverBg
    props.pressedBackgroundColor = props.pressedBackgroundColor or inspectorColors.primaryPressedBg
    props.textColor = props.textColor or inspectorColors.primaryText
    return fixedButtonProps(props)
end

local function secondaryButtonProps(props)
    props = props or {}
    props.backgroundColor = props.backgroundColor or inspectorColors.buttonBg
    props.hoverBackgroundColor = props.hoverBackgroundColor or inspectorColors.buttonHoverBg
    props.pressedBackgroundColor = props.pressedBackgroundColor or inspectorColors.buttonPressedBg
    props.textColor = props.textColor or inspectorColors.text
    return fixedButtonProps(props)
end

local function overlayPanelProps()
    return {
        position = "absolute",
        left = 0,
        top = 0,
        width = "100%",
        height = "100%",
        zIndex = 1500,
        backgroundColor = inspectorColors.overlay,
        borderWidth = 0,
        justifyContent = "center",
        alignItems = "center",
    }
end

local function dialogPanelProps(width)
    return {
        width = width,
        position = "relative",
        padding = 20,
        gap = 12,
        backgroundColor = inspectorColors.background,
        borderColor = inspectorColors.border,
        borderWidth = 1,
        borderRadius = 8,
        alignItems = "center",
    }
end

local function pickingTipsButton(Button, Label, props, text, hint, hintColor)
    props = fixedButtonProps(props)
    local textColor = props.textColor
    local fontSize = props.fontSize or 11

    local textLabel = Label {
        text = text,
        fontSize = fontSize,
        fontColor = textColor,
        flexShrink = 0,
    }
    local hintLabel = nil
    if hint and hint ~= "" then
        hintLabel = Label {
            text = hint,
            fontSize = PICKING_TIPS_BUTTON_HINT_FONT_SIZE,
            fontColor = hintColor,
            marginTop = PICKING_TIPS_BUTTON_HINT_MARGIN_TOP,
            flexShrink = 0,
        }
    end

    props.text = nil
    props.paddingHorizontal = nil
    props.paddingLeft = props.paddingLeft or 6
    props.paddingRight = props.paddingRight or 6
    props.flexDirection = "row"
    props.alignItems = "center"
    props.justifyContent = "center"
    props.gap = props.gap or 3
    props.children = hintLabel and { textLabel, hintLabel } or { textLabel }

    return Button(props), textLabel, hintLabel
end

local function getViewportSize()
    local scale = ctx.uiModule.GetScale()
    return graphics.width / scale, graphics.height / scale
end

local function getHairlineBorderWidth()
    local scale = ctx.uiModule.GetScale()
    if not scale or scale <= 0 then return 1 end
    return 0.5 / scale
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getDefaultInspectorPanelHeight(panelTop, viewportHeight)
    local availableHeight = math.max(120, viewportHeight - panelTop - INSPECTOR_MARGIN)
    return math.max(120, math.min(math.floor(viewportHeight * 0.9), availableHeight))
end

local function getInspectorPanelHeightBounds(panelTop, viewportHeight)
    local defaultHeight = getDefaultInspectorPanelHeight(panelTop, viewportHeight)
    local minHeight = math.max(
        INSPECTOR_COLLAPSED_HEIGHT,
        math.floor(defaultHeight * INSPECTOR_MIN_HEIGHT_RATIO + 0.5)
    )
    return minHeight, defaultHeight
end

local function getSavedInspectorPanelHeight(panelTop, viewportHeight)
    local minHeight, defaultHeight = getInspectorPanelHeightBounds(panelTop, viewportHeight)
    local minRatio = minHeight / defaultHeight
    local ratio = tonumber(ctx.inspectorPanelHeightRatio) or 1
    ratio = clamp(ratio, minRatio, 1)
    local height = clamp(math.floor(defaultHeight * ratio + 0.5), minHeight, defaultHeight)
    ctx.inspectorPanelHeightRatio = height / defaultHeight
    ctx.inspectorPanelHeight = height
    ctx.inspectorPanelDefaultHeight = defaultHeight
    return height
end

local function measurePickingTipsText(text, fontWeight, fontSize)
    if not text or text == "" then return 0 end

    local size = fontSize or PICKING_TIPS_FONT_SIZE
    local measure = ctx.uiModule and ctx.uiModule.MeasureTextWidth
    if measure then
        local width = measure(
            text,
            Theme.FontSize(size),
            Theme.FontFace(nil, fontWeight),
            0
        )
        if width and width > 0 then
            return math.ceil(width + 1)
        end
    end

    local _, charCount = text:gsub("[^\128-\193]", "")
    return math.ceil(charCount * size)
end

local function closeButtonProps(props)
    props = props or {}
    props = secondaryButtonProps(props)
    props.width = props.width or 24
    props.height = props.height or 24
    props.paddingHorizontal = 0
    props.backgroundColor = { 255, 255, 255, 12 }
    props.hoverBackgroundColor = { 255, 255, 255, 28 }
    props.pressedBackgroundColor = { 255, 255, 255, 42 }
    props.borderColor = { 255, 255, 255, 62 }
    props.borderWidth = getHairlineBorderWidth()
    props.borderRadius = props.borderRadius or 5
    props.textColor = { 255, 255, 255, 210 }
    props.fontSize = props.fontSize or 12
    props.fontWeight = props.fontWeight or "bold"
    return props
end

local function measurePickingTipsButtonWidth(text, hint, fontSize)
    local width = measurePickingTipsText(text, nil, fontSize or 11)
    if hint and hint ~= "" then
        width = width + measurePickingTipsText(hint, nil, PICKING_TIPS_BUTTON_HINT_FONT_SIZE) + 3
    end
    return width + 12
end

local function fixedTextFieldProps(props)
    props.borderRadius = props.borderRadius or 4
    props.paddingLeft = props.paddingLeft or 12
    props.paddingRight = props.paddingRight or 12
    props.backgroundColor = inspectorColors.inputBg
    props.borderColor = inspectorColors.inputBorder
    props.borderWidth = 1
    props.focusBorderColor = inspectorColors.borderFocus
    props.textColor = inspectorColors.text
    props.placeholderColor = inspectorColors.textSecondary
    props.selectionColor = inspectorColors.inputSelection
    props.cursorColor = inspectorColors.text
    return props
end

local function withInspectorTheme(fn)
    local oldColor = Theme.Color
    Theme.Color = function(name)
        return defaultColors[name] or oldColor(name)
    end

    local results = { pcall(fn) }
    Theme.Color = oldColor

    if not results[1] then
        error(results[2], 0)
    end
    return unpackList(results, 2)
end

local function wrapInspectorThemeMethod(widget, methodName)
    local method = widget[methodName]
    if not method then return end
    widget[methodName] = function(self, ...)
        local args = { ... }
        return withInspectorTheme(function()
            return method(self, unpackList(args))
        end)
    end
end

local hidePropKeyTooltip
local selectPropRow

local function createInspectorTextField(TextField, props)
    local field = TextField(fixedTextFieldProps(props or {}))
    wrapInspectorThemeMethod(field, "Render")
    return field
end

local function createNumericInspectorTextField(TextField, key, def, props)
    props = props or {}
    props.paddingRight = props.paddingRight or 34

    local field = createInspectorTextField(TextField, props)
    local baseRender = field.Render
    local baseOnPointerDown = field.OnPointerDown

    function field:Render(nvg)
        baseRender(self, nvg)

        local l = self:GetAbsoluteLayout()
        if not l or l.x ~= l.x then return end

        local iconColor = (ctx.dragState and ctx.dragState.key == key)
            and { 255, 255, 255, 220 }
            or { 255, 255, 255, 120 }
        local cx = l.x + l.w - 18
        local cy = l.y + l.h / 2

        nvgSave(nvg)
        nvgStrokeColor(nvg, nvgRGBA(iconColor[1], iconColor[2], iconColor[3], iconColor[4]))
        nvgStrokeWidth(nvg, 1.25)
        nvgLineCap(nvg, NVG_ROUND)
        nvgLineJoin(nvg, NVG_ROUND)

        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - 8, cy)
        nvgLineTo(nvg, cx + 8, cy)
        nvgStroke(nvg)

        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx - 8, cy)
        nvgLineTo(nvg, cx - 4, cy - 4)
        nvgMoveTo(nvg, cx - 8, cy)
        nvgLineTo(nvg, cx - 4, cy + 4)
        nvgMoveTo(nvg, cx + 8, cy)
        nvgLineTo(nvg, cx + 4, cy - 4)
        nvgMoveTo(nvg, cx + 8, cy)
        nvgLineTo(nvg, cx + 4, cy + 4)
        nvgStroke(nvg)
        nvgRestore(nvg)
    end

    function field:OnPointerDown(event)
        local l = self:GetLayout()
        local x = event and event.x
        local w = l and l.w
        if x and w and w > 0 and x >= w * 2 / 3 then
            if event and event.IsPrimaryAction and not event:IsPrimaryAction() then return end
            selectPropRow(key, def, self.inspectorPropRow_)
            local numVal = QuickTweak.getCurrentNumericValue(key, def)
            ctx.dragState = { startX = nil, startValue = numVal, key = key, def = def }
            hidePropKeyTooltip()
            return
        end

        return baseOnPointerDown(self, event)
    end

    return field
end

local function createInspectorColorPicker(ColorPicker, props)
    props = props or {}
    props.variant = props.variant or "outlined"
    props.borderRadius = props.borderRadius or 4
    props.popupBorderRadius = props.popupBorderRadius or 8
    props.sliderRadius = props.sliderRadius or 4
    props.presetRadius = props.presetRadius or 4
    props.fieldBgColor = props.fieldBgColor or inspectorColors.inputBg
    props.fieldBorderColor = props.fieldBorderColor or inspectorColors.inputBorder
    props.primaryColor = props.primaryColor or inspectorColors.borderFocus
    props.cursorBorderColor = props.cursorBorderColor or inspectorColors.overlay

    local picker = ColorPicker(props)
    wrapInspectorThemeMethod(picker, "Render")
    wrapInspectorThemeMethod(picker, "RenderPopup")
    return picker
end

local function createInspectorDropdown(Dropdown, props)
    props = props or {}
    props.height = props.height or 28
    props.borderRadius = props.borderRadius or 4
    props.triggerBgColor = props.triggerBgColor or inspectorColors.inputBg
    props.hoverBorderColor = props.hoverBorderColor or inspectorColors.borderFocus
    props.openBorderColor = props.openBorderColor or inspectorColors.borderFocus
    props.popupBorderColor = props.popupBorderColor or inspectorColors.border
    props.itemHoverBgColor = props.itemHoverBgColor or inspectorColors.primaryHoverBg
    props.itemHoverTextColor = props.itemHoverTextColor or inspectorColors.primaryText
    props.itemSelectedColor = props.itemSelectedColor or inspectorColors.primaryBg
    props.itemSelectedTextColor = props.itemSelectedTextColor or inspectorColors.primaryText
    props.selectedFontWeight = props.selectedFontWeight or "bold"
    props.arrowColor = props.arrowColor or inspectorColors.textSecondary
    props.itemHeight = props.itemHeight or 24
    props.maxVisibleItems = props.maxVisibleItems or 6
    props.queueOverlay = props.queueOverlay or function(callback)
        ctx.inspectorOverlayCallbacks[#ctx.inspectorOverlayCallbacks + 1] = callback
    end

    local dropdown = Dropdown(props)
    wrapInspectorThemeMethod(dropdown, "Render")
    wrapInspectorThemeMethod(dropdown, "RenderDropdownPanel")
    return dropdown
end

local function toInspectorColorValue(value)
    local parsed = value
    if type(value) == "string" then
        parsed = ctx.Style.ParseColor(value)
    end
    if type(parsed) ~= "table" then
        return { r = 255, g = 255, b = 255, a = 255 }
    end
    return {
        r = parsed[1] or parsed.r or 0,
        g = parsed[2] or parsed.g or 0,
        b = parsed[3] or parsed.b or 0,
        a = parsed[4] or parsed.a or 255,
    }
end

local function getInspectorColorStatusText(same, value)
    if not same then return _tr("t_1HmLUkPrh1HKrUJA0V") end
    if value == nil then return _tr("t_K1KIgS7eKRyqgDtU") end
    if type(value) == "string" and not ctx.Style.ParseColor(value) then return _tr("t_K1KIgS7eKRyqgDtU") end
    return ""
end

local function getInspectorEnumOptions(key, def, value)
    local options = {}
    local exists = false
    if def.defaultLabel then
        options[#options + 1] = { value = nil, label = def.defaultLabel }
        if value == nil or value == "" then
            exists = true
        end
    end
    for _, option in ipairs(def.options or {}) do
        options[#options + 1] = option
        if option.value == value then
            exists = true
        end
    end
    if value ~= nil and value ~= "" and not exists then
        options[#options + 1] = { value = value, label = _tr("t_3BFMoQph3bpHEclP", tostring(value)) }
    end
    return options
end

local function getInspectorBooleanOptions(key)
    if key == "visible" then
        return {
            { value = true, label = _tr("t_16xQwGT5i179Ui8jcG") },
            { value = false, label = _tr("t_R0nuwFL0RCwLl3oi") },
        }
    end
    return {
        { value = true, label = _tr("t_qvtXqIuHqVEz1ap5") },
        { value = false, label = _tr("t_YLie7muaYrDHXVkg") },
    }
end

-- ============================================================================
-- Widget Info Formatting
-- ============================================================================

local function formatWidgetBriefInfo(widget, maxTextLen)
    if not isWidgetAlive(widget) then return _tr("t_2ckqi18Q33PRTRx2") end
    local className = widget._className or "Widget"
    local src = formatSource(widget)
    local idStr = widget.props.id and (' #' .. widget.props.id) or ""
    local textProp = ""
    if widget.props.text then
        local t = tostring(widget.props.text)
        maxTextLen = maxTextLen or 30
        if #t > maxTextLen then t = t:sub(1, maxTextLen) .. "..." end
        textProp = ' "' .. t .. '"'
    end
    return className .. idStr .. textProp .. src
end

local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$") or ""
end

local function isPromptDirty(prompt)
    return trim(prompt) ~= ""
end

local function formatPromptSummary(prompt)
    prompt = trim(prompt)
    if prompt == "" then return "" end
    if #prompt > 72 then
        return prompt:sub(1, 72) .. "..."
    end
    return prompt
end

local function getWidgetPrompt(widget)
    return (ctx.widgetPrompts and ctx.widgetPrompts[widget]) or ""
end

local function setWidgetPrompt(widget, value)
    if not widget then return end
    value = value or ""
    ctx.widgetPrompts = ctx.widgetPrompts or {}
    if value == "" then
        ctx.widgetPrompts[widget] = nil
    else
        ctx.widgetPrompts[widget] = value
    end
end

local function getSelectedPromptWidget()
    if isWidgetAlive(ctx.activeWidget) then return ctx.activeWidget end
    if isWidgetAlive(ctx.selectedWidget) then return ctx.selectedWidget end
    return ctx.inspectedWidgets and ctx.inspectedWidgets[1] or ctx.selectedWidgets[1]
end

local function getInspectorEditWidgets()
    if ctx.inspectedWidgets and #ctx.inspectedWidgets > 0 then return ctx.inspectedWidgets end
    if isWidgetAlive(ctx.selectedWidget) then return { ctx.selectedWidget } end
    return {}
end

local function getActiveGroupPrompt(widgets)
    if QuickTweak.getGroupPromptForWidgets then
        return QuickTweak.getGroupPromptForWidgets(widgets or getInspectorEditWidgets())
    end
    return ""
end

local function getContainedGroupPromptEntry(widgets)
    if QuickTweak.getGroupPromptEntryForWidgets then
        return QuickTweak.getGroupPromptEntryForWidgets(widgets or getInspectorEditWidgets())
    end
    return nil
end

local function setActiveGroupPrompt(widgets, value)
    if QuickTweak.setGroupPromptForWidgets then
        QuickTweak.setGroupPromptForWidgets(widgets or getInspectorEditWidgets(), value)
    end
end

local function clearActiveGroupPrompt(widgets)
    if QuickTweak.clearGroupPromptForWidgets then
        QuickTweak.clearGroupPromptForWidgets(widgets or getInspectorEditWidgets())
    end
end

local Schema = ctx.Schema

local PROP_TABS = {
    { key = "common", label = _tr("t_JOpYi5YaJpU9nagM") },
    { key = "layout", label = _tr("t_19szraAM51AJePTLDz") },
    { key = "content", label = _tr("t_FK3AdDjRFCpR7RJL") },
    { key = "appearance", label = _tr("t_qcj4gCAJqorVVHxB") },
    { key = "interaction", label = _tr("t_cBoTHrAPchENwGgZ") },
    { key = "all", label = _tr("t_m6LmVXGEmbqPE9ga") },
}

local function propMatchesTab(tabKey, key, def)
    if tabKey == "all" then return true end
    if not def then return false end
    if def.tab then
        for _, t in ipairs(def.tab) do
            if t == tabKey then return true end
        end
    else
        -- 兜底推断：未声明 tab 的运行时属性
        if tabKey == "layout" and (def.type == "layout" or def.type == "spacing") then return true end
        if tabKey == "appearance" and type(key) == "string" and key:sub(-5):lower() == "color" then return true end
        if tabKey == "interaction" and def.type == "boolean" and key ~= "visible" then return true end
    end
    return false
end

local function filterPropKeysForTab(propKeys, propDefs, tabKey)
    if tabKey == "all" then return propKeys end

    local filtered = {}
    for _, key in ipairs(propKeys or {}) do
        if propMatchesTab(tabKey, key, propDefs and propDefs[key]) then
            filtered[#filtered + 1] = key
        end
    end
    return filtered
end

local function getVisiblePropTabs(propKeys, propDefs)
    local tabs = {}
    for _, tab in ipairs(PROP_TABS) do
        if tab.key == "all" or #filterPropKeysForTab(propKeys, propDefs, tab.key) > 0 then
            tabs[#tabs + 1] = tab
        end
    end
    return tabs
end

local function getActivePropTab(propKeys, propDefs)
    local visibleTabs = getVisiblePropTabs(propKeys, propDefs)
    local visibleSet = {}
    for _, tab in ipairs(visibleTabs) do
        visibleSet[tab.key] = true
    end

    local preferred = ctx.inspectorPropTab or "common"
    if visibleSet[preferred] then
        return preferred, visibleTabs
    end
    if visibleSet.common then
        return "common", visibleTabs
    end
    for _, tab in ipairs(visibleTabs) do
        if tab.key ~= "all" then
            return tab.key, visibleTabs
        end
    end
    return "all", visibleTabs
end

local function addPropTabs(parent, tabs, activeTab)
    local Panel = ctx.uiModule.Panel
    local Button = ctx.uiModule.Button
    if not Panel or not Button or not tabs or #tabs <= 1 then return end

    local tabRow = Panel {
        flexDirection = "row",
        flexWrap = "nowrap",
        alignItems = "center",
        gap = 4,
        alignSelf = "stretch",
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
    }
    parent:AddChild(tabRow)

    for _, tab in ipairs(tabs) do
        local isActive = tab.key == activeTab
        local tabKey = tab.key
        local tabButtonProps = isActive and primaryButtonProps({
            text = tab.label,
            fontSize = 11,
            height = 24,
            width = 50,
            paddingHorizontal = 0,
            flexShrink = 0,
        }) or secondaryButtonProps({
            text = tab.label,
            fontSize = 11,
            height = 24,
            width = 50,
            paddingHorizontal = 0,
            flexShrink = 0,
            backgroundColor = { 44, 44, 50, 210 },
            hoverBackgroundColor = { 58, 58, 66, 235 },
            pressedBackgroundColor = { 38, 38, 44, 240 },
        })
        tabButtonProps.onClick = function()
            if ctx.inspectorPropTab == tabKey then return end
            ctx.inspectorPropTab = tabKey
            M.refreshNativePanel()
        end
        tabRow:AddChild(Button(tabButtonProps))
    end
end

function hidePropKeyTooltip()
    if ctx.propKeyTooltip then
        ctx.propKeyTooltip:Destroy()
        ctx.propKeyTooltip = nil
    end
end

local function hidePropContextMenu()
    if ctx.propContextMenu then
        ctx.propContextMenu:Destroy()
        ctx.propContextMenu = nil
    end
end

function M.hidePropContextMenu()
    hidePropContextMenu()
end

function selectPropRow(key, def, row)
    if ctx.selectedPropRow and ctx.selectedPropRow ~= row and isWidgetAlive(ctx.selectedPropRow) then
        ctx.selectedPropRow:SetStyle({ backgroundColor = defaultColors.transparent })
    end
    ctx.selectedPropKey = key
    ctx.selectedPropDef = def
    ctx.selectedPropRow = row
    if row then
        row:SetStyle({ backgroundColor = { 255, 255, 255, 18 } })
    end
end

local function isSecondaryPointer(event)
    if not event then return false end
    if event.IsSecondaryButton and event:IsSecondaryButton() then return true end
    return event.button == MOUSEB_RIGHT
end

local function restoreSelectedPropFromMenu(key, def)
    if not QuickTweak.restoreSelectedProp or not QuickTweak.restoreSelectedProp(key, def) then
        return false
    end
    if QuickTweak.updateTweakFieldMarkers then
        QuickTweak.updateTweakFieldMarkers()
    end
    if ctx.updateInspectorRestoreButtonState then
        ctx.updateInspectorRestoreButtonState()
    end
    return true
end

local function getWidgetVisualRect(widget)
    if not widget then return nil end
    if widget.GetAbsoluteLayoutForHitTest then
        return widget:GetAbsoluteLayoutForHitTest()
    elseif ctx.uiModule.GetVisualRect then
        return ctx.uiModule.GetVisualRect(widget)
    elseif widget.GetAbsoluteLayout then
        return widget:GetAbsoluteLayout()
    end
    return nil
end

local function getPointerScreenPosition(event, widget)
    if event and event.x and event.y then
        return event.x, event.y
    end
    local layout = getWidgetVisualRect(widget)
    if layout then
        return layout.x, layout.y
    end
    return nil, nil
end

local function showPropContextMenu(key, def, row, event, sourceWidget)
    hidePropContextMenu()

    local root = ctx.uiModule.GetInspectorRoot and ctx.uiModule.GetInspectorRoot()
    local Panel = ctx.uiModule.Panel
    local Button = ctx.uiModule.Button
    if not root or not Panel or not Button then return end

    local layout = getWidgetVisualRect(row)

    local sw, sh = getViewportSize()
    local menuPadding = 2
    local menuWidth = 112
    local menuHeight = 28 + menuPadding * 2
    local x, y = getPointerScreenPosition(event, sourceWidget)
    if not x or not y then
        x = layout and (layout.x + layout.w - menuWidth) or 8
        y = layout and (layout.y + layout.h + 2) or 8
    end
    if y + menuHeight > sh - 8 then
        y = y - menuHeight
    end
    x = clamp(x, 8, math.max(8, sw - menuWidth - 8))
    y = clamp(y, 8, math.max(8, sh - menuHeight - 8))

    local canRestore = QuickTweak.hasSelectedPropChange
        and QuickTweak.hasSelectedPropChange(key, def)

    local menu = Panel {
        position = "absolute",
        left = x,
        top = y,
        width = menuWidth,
        padding = menuPadding,
        zIndex = 2200,
        backgroundColor = { 34, 34, 40, 246 },
        borderWidth = 0,
        borderRadius = 6,
        pointerEvents = "auto",
    }

    local restoreButton = Button {
        text = _tr("t_JgVQ7Fk1JZHiMIQZ"),
        width = menuWidth - menuPadding * 2,
        height = 28,
        fontSize = 12,
        disabled = not canRestore,
        backgroundColor = { 255, 255, 255, 0 },
        hoverBackgroundColor = { 255, 255, 255, 24 },
        pressedBackgroundColor = { 255, 255, 255, 34 },
        disabledBackgroundColor = { 255, 255, 255, 0 },
        borderWidth = 0,
        borderRadius = 4,
        paddingHorizontal = 10,
        textColor = canRestore and inspectorColors.text or { 255, 255, 255, 86 },
        onClick = function()
            if canRestore then
                restoreSelectedPropFromMenu(key, def)
            end
            hidePropContextMenu()
        end,
    }
    menu:AddChild(restoreButton)

    ctx.propContextMenu = menu
    root:AddChild(menu)
end

local function handlePropPointerDown(event, key, def, row, sourceWidget)
    if isSecondaryPointer(event) then
        selectPropRow(key, def, row)
        hidePropKeyTooltip()
        showPropContextMenu(key, def, row, event, sourceWidget or row)
        return true
    end
    hidePropContextMenu()
    selectPropRow(key, def, row)
    return false
end

local function showPropKeyTooltip(key, labelWidget)
    hidePropKeyTooltip()
    if not key or not labelWidget then return end
    local root = ctx.uiModule.GetInspectorRoot and ctx.uiModule.GetInspectorRoot()
    if not root then return end

    local layout = nil
    if ctx.uiModule.GetVisualRect then
        layout = ctx.uiModule.GetVisualRect(labelWidget)
    elseif labelWidget.GetAbsoluteLayoutForHitTest then
        layout = labelWidget:GetAbsoluteLayoutForHitTest()
    elseif labelWidget.GetAbsoluteLayout then
        layout = labelWidget:GetAbsoluteLayout()
    end
    if not layout or layout.x ~= layout.x then return end

    local Panel = ctx.uiModule.Panel
    local Label = ctx.uiModule.Label
    local sw, sh = getViewportSize()
    local width = math.ceil(math.max(72, measurePickingTipsText(key, "normal", 10) + 20))
    local x = clamp(layout.x, 8, math.max(8, sw - width - 8))
    local y = layout.y - 24
    if y < 8 then
        y = layout.y + layout.h + 4
    end
    y = clamp(y, 8, math.max(8, sh - 24))

    local tooltip = Panel {
        position = "absolute",
        left = x,
        top = y,
        width = width,
        height = 22,
        paddingLeft = 8,
        paddingRight = 8,
        backgroundColor = { 14, 14, 18, 225 },
        borderColor = { 255, 255, 255, 32 },
        borderWidth = 1,
        borderRadius = 5,
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "none",
        zIndex = 1300,
    }
    tooltip:AddChild(Label {
        text = key,
        fontSize = 10,
        fontColor = inspectorColors.text,
        whiteSpace = "nowrap",
        flexShrink = 0,
    })
    ctx.propKeyTooltip = tooltip
    root:AddChild(tooltip)
end

local function shouldShowProp(key, value)
    if type(key) ~= "string" then return false end
    if key:sub(1, 1) == "_" or key:sub(-1) == "_" then return false end
    if key == "children" then return false end
    if type(value) == "function" or type(value) == "userdata" then return false end
    if #key > 2 and key:sub(1, 2) == "on" and key:sub(3, 3):match("[A-Z]") then
        return false
    end
    return true
end

local function formatAnyValue(value)
    local valueType = type(value)
    if value == nil then return "" end
    if valueType == "string" then return ctx.escapeStringForInput(value) end
    if valueType == "number" or valueType == "boolean" then return tostring(value) end
    if valueType == "table" then
        local parts = {}
        for i = 1, #value do parts[#parts + 1] = tostring(value[i]) end
        if #parts > 0 then return "{" .. table.concat(parts, ", ") .. "}" end
        for k, v in pairs(value) do
            if type(k) == "string" and type(v) ~= "function" and type(v) ~= "userdata" then
                parts[#parts + 1] = k .. "=" .. tostring(v)
            end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end

local function getPropKeysForSelection(widgets)
    widgets = widgets or getInspectorEditWidgets()
    if #widgets == 0 then return {} end

    local keyMap = {}
    for i, widget in ipairs(widgets) do
        local current = {}
        if isWidgetAlive(widget) then
            for key, value in pairs(widget.props or {}) do
                if shouldShowProp(key, value) then
                    current[key] = true
                end
            end
        end
        if i == 1 then
            keyMap = current
        else
            for key in pairs(keyMap) do
                if not current[key] then keyMap[key] = nil end
            end
        end
    end

    local keys = {}
    for key in pairs(keyMap) do keys[#keys + 1] = key end
    return ctx.sortPropKeys(keys)
end

local function getPropConsensusDisplay(key, widgets)
    widgets = widgets or getInspectorEditWidgets()
    if #widgets == 0 then return "", true end
    local first = widgets[1]
    if not isWidgetAlive(first) then return "", true end
    local firstValue = first.props[key]
    for i = 2, #widgets do
        local widget = widgets[i]
        if isWidgetAlive(widget) and not ctx.valuesEqual(firstValue, widget.props[key]) then
            return "", false
        end
    end
    return formatAnyValue(firstValue), true
end

local function isColorPropName(key)
    return type(key) == "string" and key:sub(-5):lower() == "color"
end

local function getGenericEditablePropDef(key, widgets)
    local propType = nil
    widgets = widgets or getInspectorEditWidgets()
    for _, widget in ipairs(widgets or {}) do
        if isWidgetAlive(widget) then
            local value = widget.props[key]
            local valueType = type(value)
            local currentType = nil
            if valueType == "number" then
                currentType = "number"
            elseif valueType == "boolean" then
                currentType = "boolean"
            elseif valueType == "string" then
                currentType = isColorPropName(key) and "color" or "string"
            elseif valueType == "table" and isColorPropName(key) and #value >= 3 then
                currentType = "color"
            else
                return nil
            end
            if propType and propType ~= currentType then
                return nil
            end
            propType = currentType
        end
    end
    if not propType then return nil end
    return { label = ctx.getPropLabel(key), type = propType, generic = true }
end

local function updateInspectorPanelPosition(panel)
    if not panel then return end
    local sw, sh = getViewportSize()
    local pos = ctx.inspectorPanelPos
    if not pos then
        pos = { x = math.max(INSPECTOR_MARGIN, sw - INSPECTOR_WIDTH - INSPECTOR_MARGIN), y = INSPECTOR_TOP }
        ctx.inspectorPanelPos = pos
    end
    local panelTop = pos.y or INSPECTOR_TOP
    local panelHeight = ctx.inspectorPanelCollapsed
        and INSPECTOR_COLLAPSED_HEIGHT
        or getSavedInspectorPanelHeight(panelTop, sh)
    pos.x = clamp(pos.x, INSPECTOR_MARGIN, math.max(INSPECTOR_MARGIN, sw - 80))
    pos.y = clamp(pos.y, INSPECTOR_MARGIN, math.max(INSPECTOR_MARGIN, sh - panelHeight - INSPECTOR_MARGIN))
    panel:SetStyle({ left = pos.x, top = pos.y, height = panelHeight })
end

local function closeInspectorFieldOverlays()
    hidePropContextMenu()
    for _, field in ipairs(ctx.tweakFields or {}) do
        local dropdown = field.dropdown
        if dropdown and dropdown.SetOpen and dropdown.state and dropdown.state.isOpen then
            dropdown:SetOpen(false)
        end

        local colorPicker = field.colorPicker
        if colorPicker and colorPicker.Close and colorPicker.isOpen_ then
            colorPicker:Close()
        end
    end
end

local function destroyWidgetChildren(widget)
    if not widget or not widget.children then return end
    for i = #widget.children, 1, -1 do
        widget.children[i]:Destroy()
    end
end

-- ============================================================================
-- Destroy Panel
-- ============================================================================

function M.destroyNativePanel()
    closeInspectorFieldOverlays()
    hidePropKeyTooltip()
    hidePropContextMenu()
    if ctx.inspectorPanelRoot then
        ctx.inspectorPanelRoot:Destroy()
        ctx.uiModule.SetInspectorRoot(nil)
        ctx.inspectorPanelRoot = nil
    end
    ctx.inspectorPanel = nil
    ctx.pickingTipsPanel = nil
    ctx.pickingTipsCount = nil
    ctx.pickingTipsActionHint = nil
    ctx.pickingTipsConfirmButton = nil
    ctx.pickingTipsConfirmButtonText = nil
    ctx.pickingTipsConfirmButtonHint = nil
    ctx.pickingTipsDrag = nil
    ctx.resultToast = nil
    ctx.descTextField = nil
    ctx.groupDescTextField = nil
    ctx.inspectorPanelDrag = nil
    ctx.inspectorPanelResizeDrag = nil
    ctx.inspectorPanelHeight = nil
    ctx.inspectorPanelDefaultHeight = nil
    ctx.propKeyTooltip = nil
    ctx.propContextMenu = nil
    ctx.selectedPropRow = nil
    ctx.updateInspectorRestoreButtonState = nil
end

function M.closeFieldOverlays()
    closeInspectorFieldOverlays()
end

local function getPickingTipsWidth(count)
    count = count or #(ctx.inspectedWidgets or {})

    local countText = _tr("t_9o1tS8229by9gTjc", count)
    local contentWidth = PICKING_TIPS_PADDING_LEFT + PICKING_TIPS_PADDING_RIGHT
        + PICKING_TIPS_HANDLE_WIDTH
        + measurePickingTipsText(PICKING_TIPS_ACTION_TEXT, "bold")
        + measurePickingTipsText(countText, "bold")
        + measurePickingTipsButtonWidth(_tr("t_10lhwdNB510ct1Qukc"), "Esc", 11)
        + PICKING_TIPS_GAP * 3

    return math.ceil(contentWidth)
end

local function getPickingTipsCurrentWidth(count)
    local panel = ctx.pickingTipsPanel
    if panel and panel.GetAbsoluteLayout then
        local l = panel:GetAbsoluteLayout()
        if l and l.w == l.w and l.w > 0 then
            return l.w
        end
    end
    return getPickingTipsWidth(count)
end

local function clampPickingTipsPosition(x, y, count)
    local sw = getViewportSize()
    local width = getPickingTipsCurrentWidth(count)
    local visibleWidth = math.min(width * PICKING_TIPS_MIN_VISIBLE_RATIO, math.max(0, sw - PICKING_TIPS_MARGIN))
    local minX = visibleWidth - width
    local maxX = sw - width - PICKING_TIPS_MARGIN
    if maxX < minX then
        maxX = minX
    end
    return {
        x = clamp(x, minX, maxX),
        y = PICKING_TIPS_MARGIN,
    }
end

local function getCurrentPointerBasePosition(event)
    if input then
        local pos
        if input.GetMousePosition then
            pos = input:GetMousePosition()
        else
            pos = input.mousePosition
        end
        if pos then
            local scale = ctx.uiModule.GetScale()
            return pos.x / scale, pos.y / scale
        end
    end

    local target = event and event.target
    local layout = target and target.GetAbsoluteLayout and target:GetAbsoluteLayout()
    if not layout or layout.x ~= layout.x then
        return nil
    end
    return layout.x + (event.x or 0), layout.y + (event.y or 0)
end

function M.ensureNativeRoot()
    if ctx.inspectorPanelRoot then
        return ctx.inspectorPanelRoot
    end

    local Panel = ctx.uiModule.Panel

    local panelRoot = Panel {
        width = "100%",
        height = "100%",
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
        pointerEvents = "box-none",
        justifyContent = "flex-end",
        alignItems = "center",
        paddingBottom = 30,
    }
    ctx.inspectorPanelRoot = panelRoot
    ctx.uiModule.SetInspectorRoot(panelRoot)

    local selectionOverlay = Panel {
        position = "absolute",
        left = 0,
        top = 0,
        width = "100%",
        height = "100%",
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
        pointerEvents = "none",
    }
    function selectionOverlay:Render(nvg)
        Overlay.renderInspectorSelectionOverlay(nvg)
    end
    panelRoot:AddChild(selectionOverlay)

    return panelRoot
end

local function updateFloatingViewportState(sw, sh)
    if ctx.inspectorViewportW == sw and ctx.inspectorViewportH == sh then
        return
    end
    ctx.inspectorViewportW = sw
    ctx.inspectorViewportH = sh

    if not ctx.inspectorPanelUserMoved then
        ctx.inspectorPanelPos = nil
    end
    if not ctx.pickingTipsUserMoved then
        ctx.pickingTipsPos = nil
    end
    if ctx.inspectorPanel then
        updateInspectorPanelPosition(ctx.inspectorPanel)
    end
end

function M.updatePickingTips()
    local panel = ctx.pickingTipsPanel
    if not panel then return end

    local count = #(ctx.inspectedWidgets or {})
    local sw, sh = getViewportSize()
    updateFloatingViewportState(sw, sh)
    local pos = ctx.pickingTipsPos
    if not pos then
        local width = getPickingTipsCurrentWidth(count)
        pos = clampPickingTipsPosition((sw - width) / 2, PICKING_TIPS_MARGIN)
        ctx.pickingTipsPos = pos
    else
        pos = clampPickingTipsPosition(pos.x, pos.y, count)
        ctx.pickingTipsPos = pos
    end

    local now = time and time.elapsedTime or 0
    local pulseElapsed = ctx.selectionLimitPulseTime and (now - ctx.selectionLimitPulseTime) or 999
    local pulseActive = ctx.selectionLimitPulseTime and pulseElapsed >= 0 and pulseElapsed < 0.55
    local pulseT = pulseActive and (pulseElapsed / 0.55) or 1
    local shakeX = pulseActive and math.sin(pulseElapsed * 70) * 7 * (1 - pulseT) or 0

    panel:SetStyle({
        left = pos.x + shakeX,
        top = pos.y,
        width = "auto",
        borderWidth = getHairlineBorderWidth(),
    })

    local countText = _tr("t_9o1tS8229by9gTjc", count)

    if ctx.pickingTipsActionHint then
        ctx.pickingTipsActionHint:SetStyle({
            text = PICKING_TIPS_ACTION_TEXT,
        })
    end
    if ctx.pickingTipsCount then
        ctx.pickingTipsCount:SetStyle({
            text = countText,
            fontColor = pulseActive and ctx.TWEAK_LABEL_MODIFIED or inspectorColors.text,
        })
    end
end

function M.movePickingTipsTo(x, y)
    if not ctx.pickingTipsPanel then return end
    ctx.pickingTipsPos = clampPickingTipsPosition(x, PICKING_TIPS_MARGIN)
    M.updatePickingTips()
end

function M.updatePickingTipsDrag(x, y)
    local drag = ctx.pickingTipsDrag
    if not drag then return false end
    ctx.pickingTipsUserMoved = true
    M.movePickingTipsTo(x - drag.offsetX, PICKING_TIPS_MARGIN)
    return true
end

function M.endPickingTipsDrag()
    if not ctx.pickingTipsDrag then return false end
    ctx.pickingTipsDrag = nil
    return true
end

function M.updateInspectorPanelDrag(x, y)
    local resize = ctx.inspectorPanelResizeDrag
    if resize and ctx.inspectorPanel then
        local _, sh = getViewportSize()
        local pos = ctx.inspectorPanelPos or {
            x = INSPECTOR_MARGIN,
            y = INSPECTOR_TOP,
        }
        local panelTop = pos.y or INSPECTOR_TOP
        local minHeight, defaultHeight = getInspectorPanelHeightBounds(panelTop, sh)
        local desiredHeight = clamp(y - panelTop, minHeight, defaultHeight)
        ctx.inspectorPanelHeightRatio = desiredHeight / defaultHeight
        ctx.inspectorPanelUserResized = true
        updateInspectorPanelPosition(ctx.inspectorPanel)
        return true
    end

    local drag = ctx.inspectorPanelDrag
    if not drag or not ctx.inspectorPanel then return false end
    local sw, sh = getViewportSize()
    local nx = clamp(x - drag.offsetX, INSPECTOR_MARGIN, math.max(INSPECTOR_MARGIN, sw - 80))
    local ny = clamp(y - drag.offsetY, INSPECTOR_MARGIN, math.max(INSPECTOR_MARGIN, sh - 80))
    ctx.inspectorPanelUserMoved = true
    ctx.inspectorPanelPos = { x = nx, y = ny }
    updateInspectorPanelPosition(ctx.inspectorPanel)
    return true
end

function M.endInspectorPanelDrag()
    if ctx.inspectorPanelResizeDrag then
        ctx.inspectorPanelResizeDrag = nil
        return true
    end
    if not ctx.inspectorPanelDrag then return false end
    ctx.inspectorPanelDrag = nil
    return true
end

function M.hidePickingTips()
    if ctx.pickingTipsPanel then
        ctx.pickingTipsPanel:Destroy()
    end
    ctx.pickingTipsPanel = nil
    ctx.pickingTipsCount = nil
    ctx.pickingTipsActionHint = nil
    ctx.pickingTipsConfirmButton = nil
    ctx.pickingTipsConfirmButtonText = nil
    ctx.pickingTipsConfirmButtonHint = nil
    ctx.pickingTipsDrag = nil
end

function M.showPickingTips(onSelectDirty)
    M.hidePickingTips()

    local root = M.ensureNativeRoot()
    local Panel = ctx.uiModule.Panel
    local Label = ctx.uiModule.Label
    local Button = ctx.uiModule.Button

    local sw = getViewportSize()
    local width = getPickingTipsWidth()
    ctx.pickingTipsPos = ctx.pickingTipsPos or clampPickingTipsPosition((sw - width) / 2, PICKING_TIPS_MARGIN)

    local tips = Panel {
        position = "absolute",
        left = ctx.pickingTipsPos.x,
        top = ctx.pickingTipsPos.y,
        width = "auto",
        height = PICKING_TIPS_HEIGHT,
        paddingLeft = PICKING_TIPS_PADDING_LEFT,
        paddingRight = PICKING_TIPS_PADDING_RIGHT,
        gap = PICKING_TIPS_GAP,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 24, 24, 28, 198 },
        borderColor = { 255, 255, 255, 118 },
        borderWidth = getHairlineBorderWidth(),
        borderRadius = 17,
        cursor = "move",
        onPointerDown = function(event, widget)
            if event and not event:IsPrimaryAction() then return end
            local px, py = getCurrentPointerBasePosition(event)
            local layout = widget:GetAbsoluteLayout()
            if not px or not layout or layout.x ~= layout.x then return end
            ctx.pickingTipsDrag = {
                startX = px,
                startY = py,
                offsetX = px - layout.x,
            }
        end,
    }
    ctx.pickingTipsPanel = tips

    local baseRender = tips.Render
    function tips:Render(nvg)
        M.updatePickingTips()
        baseRender(self, nvg)
    end

    local dragHandle = Panel {
        width = PICKING_TIPS_HANDLE_WIDTH,
        height = 18,
        flexShrink = 0,
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
        pointerEvents = "none",
    }
    function dragHandle:Render(nvg)
        local l = self:GetAbsoluteLayout()
        if not l or l.x ~= l.x then return end
        local cx = l.x + l.w / 2
        local cy = l.y + l.h / 2
        nvgSave(nvg)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 115))
        for dx = -3, 3, 6 do
            for dy = -3, 3, 6 do
                nvgBeginPath(nvg)
                nvgCircle(nvg, cx + dx, cy + dy, 1.35)
                nvgFill(nvg)
            end
        end
        nvgRestore(nvg)
    end
    tips:AddChild(dragHandle)

    ctx.pickingTipsActionHint = Label {
        text = PICKING_TIPS_ACTION_TEXT,
        fontSize = PICKING_TIPS_FONT_SIZE,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 245 },
        flexShrink = 0,
    }
    tips:AddChild(ctx.pickingTipsActionHint)

    ctx.pickingTipsCount = Label {
        text = _tr("t_1n7wGY111HdKsQWn"),
        fontSize = PICKING_TIPS_FONT_SIZE,
        fontColor = { 255, 255, 255, 245 },
        fontWeight = "bold",
        flexShrink = 0,
    }
    tips:AddChild(ctx.pickingTipsCount)

    local cancelButton = pickingTipsButton(Button, Label, {
        fontSize = 11,
        height = 24,
        minWidth = 52,
        flexShrink = 0,
        backgroundColor = { 255, 255, 255, 245 },
        hoverBackgroundColor = { 238, 238, 242, 255 },
        pressedBackgroundColor = { 218, 218, 224, 255 },
        textColor = { 24, 24, 28, 255 },
        onClick = function()
            M.tryClose()
        end,
    }, _tr("t_10lhwdNB510ct1Qukc"), "Esc", { 24, 24, 28, 150 })
    tips:AddChild(cancelButton)

    root:AddChild(tips)
    M.updatePickingTips()
end

-- ============================================================================
-- Clipboard Copy
-- ============================================================================

--- Copy report + diff to clipboard
function M.doCopyToClipboard()
    local widgets = { unpackList(getInspectorEditWidgets()) }
    local report = Report.generateCompactReport(widgets, {
        widgetPrompts = ctx.widgetPrompts,
        groupPrompt = getActiveGroupPrompt(widgets),
        groupPromptEntry = getContainedGroupPromptEntry(widgets),
    })

    ui.useSystemClipboard = true
    ui:SetClipboardText(report)
    print("[UIInspector] 已拷贝到剪贴板 (" .. #report .. " 字符, " .. #widgets .. " 个控件)")
end

function M.restoreAndExit()
    QuickTweak.restoreSnapshots()
    ctx.widgetPrompts = {}
    if QuickTweak.clearGroupPrompt then
        QuickTweak.clearGroupPrompt()
    end
    ctx.UIInspector.Exit()
end

function M.applyAndExit()
    ctx.UIInspector.Exit()
end

-- ============================================================================
-- Confirm Overlay
-- ============================================================================

--- Hide the confirm-close overlay
function M.hideConfirmOverlay()
    if not ctx.confirmOverlay then return end
    local root = ctx.uiModule.GetInspectorRoot()
    if root then
        root:RemoveChild(ctx.confirmOverlay)
    end
    ctx.confirmOverlay = nil
end

function M.hideResultToast()
    if not ctx.resultToast then return end
    local root = ctx.uiModule.GetInspectorRoot()
    if root then
        root:RemoveChild(ctx.resultToast)
    end
    ctx.resultToast = nil
end

function M.showResultToast(message, onDone)
    local root = M.ensureNativeRoot()
    local Panel = ctx.uiModule.Panel
    local Label = ctx.uiModule.Label
    local sw = getViewportSize()
    local textWidth = measurePickingTipsText(message, "bold", RESULT_TOAST_FONT_SIZE)
    local maxWidth = math.max(RESULT_TOAST_MIN_WIDTH, sw - 16)
    local toastWidth = math.min(math.max(RESULT_TOAST_MIN_WIDTH, textWidth + RESULT_TOAST_PADDING_X * 2), maxWidth)

    M.hideResultToast()

    local toast = Panel {
        position = "absolute",
        left = math.max(8, (sw - toastWidth) / 2),
        top = RESULT_TOAST_TOP,
        width = toastWidth,
        height = RESULT_TOAST_HEIGHT,
        paddingLeft = RESULT_TOAST_PADDING_X,
        paddingRight = RESULT_TOAST_PADDING_X,
        backgroundColor = { 24, 24, 28, 205 },
        borderColor = { 255, 255, 255, 44 },
        borderWidth = 1,
        borderRadius = 17,
        alignItems = "center",
        justifyContent = "center",
        zIndex = 1200,
        pointerEvents = "none",
    }
    toast:AddChild(Label {
        text = message,
        fontSize = RESULT_TOAST_FONT_SIZE,
        fontWeight = "bold",
        fontColor = inspectorColors.text,
        textAlign = "center",
        whiteSpace = "nowrap",
        flexShrink = 0,
    })

    local elapsed = 0
    local done = false
    function toast:Update(dt)
        if done then return end
        if ctx.resultToast ~= toast then
            done = true
            return
        end
        elapsed = elapsed + (dt or 0)
        if elapsed < RESULT_TOAST_DURATION then return end
        done = true
        M.hideResultToast()
        if onDone then onDone() end
    end

    ctx.resultToast = toast
    root:AddChild(toast)
end

function M.showCopyResult()
    M.doCopyToClipboard()
    M.showResultToast(_tr("t_lLPgd7JlkpzkWRUp"))
end

--- Show the confirm-close overlay (Yoga widgets on inspectorRoot_)
function M.showConfirmOverlay()
    if ctx.confirmOverlay then return end  -- already showing

    local Panel = ctx.uiModule.Panel
    local Label = ctx.uiModule.Label
    local Button = ctx.uiModule.Button

    -- Full-screen backdrop (semi-transparent)
    ctx.confirmOverlay = Panel(overlayPanelProps())

    local dialog = Panel(dialogPanelProps(nil))
    ctx.confirmOverlay:AddChild(dialog)

    local titleRow = Panel {
        position = "relative",
        alignSelf = "stretch",
        height = 24,
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
    }
    dialog:AddChild(titleRow)
    titleRow:AddChild(Label {
        text = _tr("t_hhR13ndehBwOEeZE"),
        position = "absolute",
        left = 0,
        top = 0,
        width = "100%",
        height = 24,
        fontSize = 14,
        fontWeight = "bold",
        fontColor = inspectorColors.text,
        textAlign = "center",
        verticalAlign = "middle",
        pointerEvents = "none",
    })

    local closeIconColor = { 255, 255, 255, 218 }
    dialog:AddChild(Button(closeButtonProps({
        position = "absolute",
        right = 10,
        top = 10,
        zIndex = 1,
        children = {
            Panel {
                position = "absolute",
                left = 7,
                top = 11,
                width = 10,
                height = 1.4,
                rotate = 45,
                backgroundColor = closeIconColor,
                borderWidth = 0,
                borderRadius = 1,
            },
            Panel {
                position = "absolute",
                left = 7,
                top = 11,
                width = 10,
                height = 1.4,
                rotate = -45,
                backgroundColor = closeIconColor,
                borderWidth = 0,
                borderRadius = 1,
            },
        },
        onClick = function()
            M.hideConfirmOverlay()
        end,
    })))

    dialog:AddChild(Label {
        text = _tr("t_FymqLf2dFmj3fpRp"),
        fontSize = 11,
        fontColor = inspectorColors.textSecondary,
        whiteSpace = "nowrap",
        textAlign = "center",
        flexShrink = 0,
    })

    local btnRow = Panel {
        flexDirection = "row",
        gap = 8,
        alignSelf = "stretch",
        marginTop = 4,
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
        justifyContent = "center",
    }
    dialog:AddChild(btnRow)

    btnRow:AddChild(Button(secondaryButtonProps({
        text = _tr("t_HXqnawyqI0cE2KuT"),
        fontSize = 11,
        height = 30,
        width = 72,
        flexShrink = 0,
        onClick = function()
            M.hideConfirmOverlay()
        end,
    })))

    btnRow:AddChild(Button(primaryButtonProps({
        text = _tr("t_dEb9fpK2cj6Wb0SW"),
        fontSize = 11,
        height = 30,
        width = 92,
        flexShrink = 0,
        onClick = function()
            M.restoreAndExit()
        end,
    })))

    -- Add to inspector root (renders on top of inspector panel)
    ctx.uiModule.GetInspectorRoot():AddChild(ctx.confirmOverlay)
end

--- Try to close the inspector. Shows confirm overlay if there are preview modifications.
function M.tryClose()
    if QuickTweak.hasTweakModifications() then
        M.showConfirmOverlay()
    else
        M.applyAndExit()
    end
end

-- ============================================================================
-- Create Inspector Panel
-- ============================================================================

function M.createNativePanel()
    local Panel = ctx.uiModule.Panel
    local Label = ctx.uiModule.Label
    local Button = ctx.uiModule.Button
    local TextField = ctx.uiModule.TextField
    local Dropdown = ctx.uiModule.Dropdown
    local ScrollView = ctx.uiModule.ScrollView

    local panelRoot = M.ensureNativeRoot()
    closeInspectorFieldOverlays()
    hidePropKeyTooltip()
    ctx.descTextField = nil
    ctx.groupDescTextField = nil
    ctx.tweakFields = {}

    panelRoot:SetStyle({
        backgroundColor = defaultColors.transparent,
        pointerEvents = "box-none",
        justifyContent = "flex-start",
        alignItems = "flex-start",
        paddingBottom = 0,
    })

    local _, viewportHeight = getViewportSize()
    local panelTop = ctx.inspectorPanelPos and ctx.inspectorPanelPos.y or INSPECTOR_TOP
    local actualPanelHeight = ctx.inspectorPanelCollapsed
        and INSPECTOR_COLLAPSED_HEIGHT
        or getSavedInspectorPanelHeight(panelTop, viewportHeight)

    local panel = ctx.inspectorPanel
    local panelStyle = {
        position = "absolute",
        left = 0,
        top = 0,
        width = INSPECTOR_WIDTH,
        height = actualPanelHeight,
        paddingLeft = 12,
        paddingRight = 12,
        paddingTop = 0,
        paddingBottom = 0,
        gap = 8,
        backgroundColor = inspectorColors.background,
        borderColor = inspectorColors.border,
        borderWidth = 1,
        borderRadius = 8,
        overflow = "hidden",
        zIndex = 1100,
    }
    if panel and panel.node then
        destroyWidgetChildren(panel)
        panel:SetStyle(panelStyle)
    else
        panel = Panel(panelStyle)
        ctx.inspectorPanel = panel
        panelRoot:AddChild(panel)
    end
    updateInspectorPanelPosition(panel)

    local function addSectionTitle(parent, text)
        parent:AddChild(Label {
            text = text,
            fontSize = 12,
            fontWeight = "bold",
            fontColor = inspectorColors.text,
            marginTop = 4,
        })
    end

    local function addInfoLine(parent, text, color)
        parent:AddChild(Label {
            text = text,
            fontSize = 11,
            fontColor = color or inspectorColors.textSecondary,
            whiteSpace = "normal",
            alignSelf = "stretch",
        })
    end

    local function addPreviewEditNotice(parent)
        -- 给定 minHeight >= 实际两行渲染高度，否则重建时一帧单行→两行跳变
        parent:AddChild(Panel {
            minHeight = 58,
            alignSelf = “stretch”,
            flexShrink = 0,
            paddingLeft = 10,
            paddingRight = 10,
            paddingTop = 7,
            paddingBottom = 7,
            marginBottom = 4,
            justifyContent = “center”,
            backgroundColor = { 245, 166, 35, 24 },
            borderColor = { 245, 166, 35, 76 },
            borderWidth = getHairlineBorderWidth(),
            borderRadius = 5,
            children = {
                Label {
                    text = _tr("t_17ql33X8j17LGSFm6R"),
                    fontSize = 11,
                    fontColor = { 255, 220, 176, 235 },
                    lineHeight = 1.15,
                    alignSelf = “stretch”,
                    whiteSpace = “normal”,
                },
            },
        })
    end

    local function addIndentedInfoLine(parent, text, indent, color)
        local row = Panel {
            flexDirection = "row",
            alignItems = "flex-start",
            alignSelf = "stretch",
            paddingLeft = indent or 0,
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
            pointerEvents = "none",
        }
        row:AddChild(Label {
            text = text,
            fontSize = 11,
            fontColor = color or inspectorColors.textSecondary,
            whiteSpace = "normal",
            flexGrow = 1,
            flexShrink = 1,
        })
        parent:AddChild(row)
    end

    local function addWidgetDetailLine(parent, label, text, color)
        if not text or text == "" then return end
        local row = Panel {
            flexDirection = "row",
            alignItems = "flex-start",
            alignSelf = "stretch",
            gap = 7,
            paddingLeft = 2,
            paddingRight = 2,
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
            pointerEvents = "none",
        }
        row:AddChild(Label {
            text = label,
            width = 34,
            fontSize = 10,
            fontColor = { 255, 255, 255, 105 },
            textAlign = "right",
            whiteSpace = "nowrap",
            flexShrink = 0,
        })
        row:AddChild(Label {
            text = text,
            fontSize = 11,
            fontColor = color or inspectorColors.textSecondary,
            whiteSpace = "normal",
            flexGrow = 1,
            flexShrink = 1,
        })
        parent:AddChild(row)
    end

    local function addSoftDivider(parent)
        parent:AddChild(Panel {
            height = getHairlineBorderWidth(),
            alignSelf = "stretch",
            marginTop = 2,
            marginBottom = 2,
            backgroundColor = { 255, 255, 255, 28 },
            borderWidth = 0,
            pointerEvents = "none",
        })
    end

    local function addChangeGroupTitle(parent, text)
        parent:AddChild(Label {
            text = text,
            fontSize = 11,
            fontWeight = "bold",
            fontColor = inspectorColors.text,
            whiteSpace = "normal",
            alignSelf = "stretch",
            marginTop = 2,
        })
    end

    local function getActiveWidget()
        return getSelectedPromptWidget()
    end

    local function buildBreadcrumb(widget)
        if not isWidgetAlive(widget) then return _tr("t_12osHFFzv12ODgCE3B") end
        local parts = {}
        local w = widget
        while w do
            table.insert(parts, 1, w._className or "Widget")
            w = w.parent
        end
        return table.concat(parts, " > ")
    end

    local function ellipsize(text, limit)
        text = tostring(text or "")
        limit = limit or 32
        if #text <= limit then return text end
        return text:sub(1, limit) .. "..."
    end

    local function formatWidgetTagSummary(widget)
        local parts = {}
        if widget.props.id then
            parts[#parts + 1] = "#" .. tostring(widget.props.id)
        end
        if widget.props.text then
            parts[#parts + 1] = "\"" .. ellipsize(widget.props.text, 28) .. "\""
        elseif widget.props.label then
            parts[#parts + 1] = "label=\"" .. ellipsize(widget.props.label, 24) .. "\""
        elseif widget.props.value ~= nil then
            parts[#parts + 1] = "value=" .. ellipsize(widget.props.value, 24)
        end

        local l = widget:GetAbsoluteLayout()
        if l and l.w == l.w then
            parts[#parts + 1] = string.format("%.0f×%.0f", l.w, l.h)
        end

        if #parts == 0 then
            return _tr("t_yZHWVnCfy3mvirZr")
        end
        return table.concat(parts, " · ")
    end

    local function makeWidgetTag(widget)
        local tag = Panel {
            height = 20,
            paddingLeft = 8,
            paddingRight = 8,
            flexShrink = 0,
            alignItems = "center",
            justifyContent = "center",
            backgroundColor = { 255, 255, 255, 232 },
            borderColor = { 255, 255, 255, 54 },
            borderWidth = getHairlineBorderWidth(),
            borderRadius = 10,
            pointerEvents = "none",
        }
        tag:AddChild(Label {
            text = widget._className or "Widget",
            fontSize = 11,
            fontWeight = "bold",
            fontColor = { 24, 24, 28, 255 },
            whiteSpace = "nowrap",
            flexShrink = 0,
        })
        return tag
    end

    local function addWidgetInfoTagRow(parent, widget, expanded, includePrompt)
        local row = Button(secondaryButtonProps({
            height = 30,
            width = "100%",
            alignSelf = "stretch",
            paddingHorizontal = 8,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "flex-start",
            gap = 6,
            backgroundColor = { 255, 255, 255, 8 },
            hoverBackgroundColor = { 255, 255, 255, 16 },
            pressedBackgroundColor = { 255, 255, 255, 24 },
            borderColor = { 255, 255, 255, 24 },
            borderWidth = getHairlineBorderWidth(),
            borderRadius = 5,
            overflow = "hidden",
            onClick = function()
                ctx.selectedWidgetInfoExpanded[widget] = not expanded
                M.refreshNativePanel()
            end,
        }))
        row:AddChild(makeWidgetTag(widget))
        row:AddChild(Label {
            text = formatWidgetTagSummary(widget),
            width = 0,
            minWidth = 0,
            height = 18,
            fontSize = 11,
            fontColor = inspectorColors.textSecondary,
            whiteSpace = "nowrap",
            overflow = "hidden",
            flexGrow = 1,
            flexShrink = 1,
        })
        row:AddChild(Label {
            text = expanded and _tr("t_Xm6jcsJQYClHWOUE") or _tr("t_1E9DrfXqk1Ddnv1wQW"),
            fontSize = 10,
            fontColor = { 255, 255, 255, 135 },
            width = 28,
            textAlign = "right",
            flexShrink = 0,
        })
        parent:AddChild(row)
    end

    local function addWidgetInfoEntry(parent, widget, includePrompt)
        if not isWidgetAlive(widget) then return end

        local expanded = ctx.selectedWidgetInfoExpanded[widget] == true
        addWidgetInfoTagRow(parent, widget, expanded, includePrompt)
        if not expanded then return end

        local detailHost = Panel {
            gap = 2,
            alignSelf = "stretch",
            marginTop = 1,
            paddingTop = 1,
            paddingBottom = 1,
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
        }
        parent:AddChild(detailHost)

        addWidgetDetailLine(detailHost, _tr("t_136wOAW6F13J07ixmX"), buildBreadcrumb(widget), inspectorColors.textSecondary)
        addWidgetDetailLine(detailHost, _tr("t_LpTsMGzrLJzFFSGT"), formatWidgetBriefInfo(widget, 30), inspectorColors.textSecondary)

        local l = widget:GetAbsoluteLayout()
        if l and l.w == l.w then
            addWidgetDetailLine(detailHost, _tr("t_19szraAM51AJePTLDz"), string.format(
                "x=%.0f, y=%.0f, w=%.0f, h=%.0f",
                l.x, l.y, l.w, l.h
            ), inspectorColors.textSecondary)
        end

        if includePrompt then
            local prompt = formatPromptSummary(getWidgetPrompt(widget))
            if prompt ~= "" then
                addWidgetDetailLine(detailHost, _tr("t_67vdWwQr5cR0BcN5"), prompt, ctx.PROMPT_COLOR)
            end
        end
    end

    local function addWidgetInfoEntries(parent, activeWidgetForFallback, widgets)
        widgets = widgets or {}
        local host = Panel {
            gap = SELECTED_WIDGET_INFO_ROW_GAP,
            alignSelf = "stretch",
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
        }
        parent:AddChild(host)

        if #widgets == 0 and isWidgetAlive(activeWidgetForFallback) then
            widgets = { activeWidgetForFallback }
        end
        if #widgets == 0 then
            addIndentedInfoLine(host, _tr("t_2ckqi18Q33PRTRx2"), 0, inspectorColors.textSecondary)
            return
        end

        if #widgets > 1 then
            addIndentedInfoLine(host, _tr("t_DDLbUTPtDilVx7p9"), 0, inspectorColors.textSecondary)
        end

        local showWidgetPrompt = #widgets == 1
        local hasOverflow = #widgets > SELECTED_WIDGET_INFO_COLLAPSED_COUNT
        local listExpanded = ctx.selectedWidgetListExpanded == true
        if #widgets == 1 and not ctx.selectedWidgetInfoExpanded[widgets[1]] then
            host:SetStyle({
                height = 30,
                overflow = "hidden",
            })
        end
        local visibleCount = hasOverflow and not listExpanded
            and SELECTED_WIDGET_INFO_COLLAPSED_COUNT
            or #widgets

        for i = 1, visibleCount do
            local widget = widgets[i]
            addWidgetInfoEntry(host, widget, showWidgetPrompt)
            if #widgets > 1 and i < visibleCount then
                host:AddChild(Panel {
                    height = SELECTED_WIDGET_INFO_ENTRY_GAP,
                    alignSelf = "stretch",
                    backgroundColor = defaultColors.transparent,
                    borderWidth = 0,
                    pointerEvents = "none",
                })
            end
        end

        if hasOverflow and not listExpanded then
            addIndentedInfoLine(
                host,
                _tr("t_12Tq8ba3M12ftsO3Uc", tostring(#widgets - visibleCount)),
                0,
                inspectorColors.textSecondary
            )
        end

        if hasOverflow then
            local triangleColor = { 255, 255, 255, 135 }
            local triangle = Panel {
                width = 14,
                height = 8,
                backgroundColor = defaultColors.transparent,
                borderWidth = 0,
                pointerEvents = "none",
            }
            function triangle:Render(nvg)
                local l = self:GetAbsoluteLayout()
                if not l or l.x ~= l.x then return end
                local cx = l.x + l.w / 2
                local cy = l.y + l.h / 2
                local halfW = 5
                local halfH = 3
                nvgSave(nvg)
                nvgBeginPath(nvg)
                if listExpanded then
                    nvgMoveTo(nvg, cx - halfW, cy + halfH)
                    nvgLineTo(nvg, cx, cy - halfH)
                    nvgLineTo(nvg, cx + halfW, cy + halfH)
                else
                    nvgMoveTo(nvg, cx - halfW, cy - halfH)
                    nvgLineTo(nvg, cx + halfW, cy - halfH)
                    nvgLineTo(nvg, cx, cy + halfH)
                end
                nvgClosePath(nvg)
                nvgFillColor(nvg, nvgRGBA(triangleColor[1], triangleColor[2], triangleColor[3], triangleColor[4]))
                nvgFill(nvg)
                nvgRestore(nvg)
            end
            host:AddChild(Button(secondaryButtonProps({
                height = 18,
                alignSelf = "stretch",
                marginTop = 1,
                backgroundColor = { 255, 255, 255, 6 },
                hoverBackgroundColor = { 255, 255, 255, 14 },
                pressedBackgroundColor = { 255, 255, 255, 22 },
                borderColor = { 255, 255, 255, 18 },
                borderWidth = getHairlineBorderWidth(),
                borderRadius = 3,
                alignItems = "center",
                justifyContent = "center",
                children = { triangle },
                onClick = function()
                    ctx.selectedWidgetListExpanded = not listExpanded
                    M.refreshNativePanel()
                end,
            })))
        end
    end

    local function beginPanelDrag(event, widget)
        if event and event.IsPrimaryAction and not event:IsPrimaryAction() then return end
        local px, py = getCurrentPointerBasePosition(event)
        local panelWidget = ctx.inspectorPanel or widget
        local layout = panelWidget and panelWidget.GetAbsoluteLayout and panelWidget:GetAbsoluteLayout()
        if not px or not py or not layout or layout.x ~= layout.x then return end
        ctx.inspectorPanelDrag = {
            offsetX = px - layout.x,
            offsetY = py - layout.y,
        }
    end

    local function beginPanelResizeDrag(event, widget)
        if event and event.IsPrimaryAction and not event:IsPrimaryAction() then return end
        local px, py = getCurrentPointerBasePosition(event)
        if not px or not py then return end
        ctx.inspectorPanelDrag = nil
        ctx.inspectorPanelResizeDrag = {
            startY = py,
        }
        hidePropKeyTooltip()
        hidePropContextMenu()
    end

    local panelResizeHandleAdded = false
    local function addPanelResizeHandle(parent)
        if panelResizeHandleAdded then return end
        panelResizeHandleAdded = true
        local handle = Panel {
            height = INSPECTOR_RESIZE_HANDLE_HEIGHT,
            alignSelf = "stretch",
            flexShrink = 0,
            marginTop = -2,
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
            cursor = "ns-resize",
            alignItems = "center",
            justifyContent = "center",
            onPointerDown = beginPanelResizeDrag,
        }
        local grip = Panel {
            width = 72,
            height = 3,
            borderRadius = 2,
            backgroundColor = { 255, 255, 255, 64 },
            borderWidth = 0,
            pointerEvents = "none",
        }
        handle:AddChild(grip)
        parent:AddChild(handle)
    end

    local activeWidget = getActiveWidget()
    local inspectedWidgets = getInspectorEditWidgets()
    local inspectedCount = #inspectedWidgets
    local titleText = "Inspector"
    if inspectedCount == 1 and activeWidget then
        titleText = (activeWidget._className or "Widget")
    elseif inspectedCount > 1 then
        titleText = _tr("t_12y1SRpEV13TRP4fVZ", tostring(inspectedCount))
    end

    local header = Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        paddingTop = 12,
        alignSelf = "stretch",
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
        cursor = "move",
        onPointerDown = beginPanelDrag,
    }
    panel:AddChild(header)

    local headerDragHandle = Panel {
        width = 14,
        height = 18,
        flexShrink = 0,
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
        pointerEvents = "none",
    }
    function headerDragHandle:Render(nvg)
        local l = self:GetAbsoluteLayout()
        if not l or l.x ~= l.x then return end
        local cx = l.x + l.w / 2
        local cy = l.y + l.h / 2
        nvgSave(nvg)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 115))
        for dx = -3, 3, 6 do
            for dy = -3, 3, 6 do
                nvgBeginPath(nvg)
                nvgCircle(nvg, cx + dx, cy + dy, 1.25)
                nvgFill(nvg)
            end
        end
        nvgRestore(nvg)
    end
    header:AddChild(headerDragHandle)

    header:AddChild(Label {
        text = titleText,
        fontSize = 14,
        fontWeight = "bold",
        fontColor = inspectorColors.text,
        flexGrow = 1,
    })

    header:AddChild(Button(secondaryButtonProps({
        text = ctx.inspectorPanelCollapsed and _tr("t_1E9DrfXqk1Ddnv1wQW") or _tr("t_Xm6jcsJQYClHWOUE"),
        fontSize = 11,
        height = 26,
        width = 48,
        paddingHorizontal = 0,
        onClick = function()
            ctx.inspectorPanelCollapsed = not ctx.inspectorPanelCollapsed
            M.refreshNativePanel()
        end,
    })))

    if ctx.inspectorPanelCollapsed then
        return
    end

    local actionRow = Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        alignSelf = "stretch",
        backgroundColor = defaultColors.transparent,
        borderWidth = 0,
    }
    panel:AddChild(actionRow)

    local restoreButton = nil
    local selectDirtyButton, selectDirtyButtonText = nil, nil
    local function computeCanRestoreSelection()
        local canRestore = inspectedCount > 0
            and QuickTweak.hasSelectionRestorableChanges
            and QuickTweak.hasSelectionRestorableChanges(inspectedWidgets)
        if inspectedCount > 1 and getActiveGroupPrompt(inspectedWidgets) ~= "" then
            canRestore = true
        end
        return canRestore
    end

    local function getRestoreButtonColors(canRestore)
        return {
            text = canRestore and { 255, 255, 255, 245 } or { 255, 255, 255, 95 },
            bg = canRestore and { 58, 58, 66, 255 } or { 44, 44, 50, 180 },
            hoverBg = canRestore and { 72, 72, 82, 255 } or { 44, 44, 50, 180 },
            pressedBg = canRestore and { 46, 46, 54, 255 } or { 44, 44, 50, 180 },
        }
    end

    local function getDirtyWidgetCount()
        local dirtyWidgets = QuickTweak.getDirtyWidgets and QuickTweak.getDirtyWidgets() or {}
        return #dirtyWidgets
    end

    local function formatDirtyButtonText(count)
        if count and count > 0 then
            return _tr("t_RdTCXRMTRpbdHr3b", tostring(count))
        end
        return _tr("t_qXCvyk5Lr2hZ0Kcf")
    end

    local function computeCanSelectDirty()
        return getDirtyWidgetCount() > 0
    end

    local function updateRestoreButtonState()
        local canRestore = computeCanRestoreSelection()
        if restoreButton then
            local colors = getRestoreButtonColors(canRestore)
            restoreButton.props.disabled = not canRestore
            restoreButton.props.backgroundColor = colors.bg
            restoreButton.props.hoverBackgroundColor = colors.hoverBg
            restoreButton.props.pressedBackgroundColor = colors.pressedBg
            restoreButton.props.disabledBackgroundColor = colors.bg
            restoreButton.props.textColor = colors.text
        end
        return canRestore
    end
    ctx.updateInspectorRestoreButtonState = updateRestoreButtonState

    local function updateSelectDirtyButtonState()
        local dirtyCount = getDirtyWidgetCount()
        local canSelect = dirtyCount > 0
        if selectDirtyButton then
            local colors = getRestoreButtonColors(canSelect)
            selectDirtyButton.props.disabled = not canSelect
            selectDirtyButton.props.backgroundColor = colors.bg
            selectDirtyButton.props.hoverBackgroundColor = colors.hoverBg
            selectDirtyButton.props.pressedBackgroundColor = colors.pressedBg
            selectDirtyButton.props.disabledBackgroundColor = colors.bg
            selectDirtyButton.props.textColor = colors.text
            if selectDirtyButtonText then
                selectDirtyButtonText:SetText(formatDirtyButtonText(dirtyCount))
                selectDirtyButtonText:SetStyle({ fontColor = colors.text })
            end
        end
        return canSelect
    end

    local LAYOUT_ASSISTANT_KEYS = {
        flexDirection = true, flexWrap = true, justifyContent = true,
        alignItems = true, alignContent = true, position = true,
    }

    local function refreshEditIndicators(changedKey)
        QuickTweak.updateTweakFieldMarkers()
        updateRestoreButtonState()
        updateSelectDirtyButtonState()
        if changedKey and LAYOUT_ASSISTANT_KEYS[changedKey] then
            M.refreshNativePanel()
        end
    end

    local canRestoreSelection = computeCanRestoreSelection()
    local restoreColors = getRestoreButtonColors(canRestoreSelection)

    restoreButton = Button(secondaryButtonProps({
        text = inspectedCount > 1 and _tr("t_11NEIU3Pg11UWgvHr8") or _tr("t_AUlQzeTKA4BZ7qiC"),
        fontSize = 11,
        height = 26,
        width = 78,
        paddingHorizontal = 0,
        disabled = not canRestoreSelection,
        backgroundColor = restoreColors.bg,
        hoverBackgroundColor = restoreColors.hoverBg,
        pressedBackgroundColor = restoreColors.pressedBg,
        disabledBackgroundColor = restoreColors.bg,
        textColor = restoreColors.text,
        onClick = function()
            if not updateRestoreButtonState() then return end
            QuickTweak.restoreWidgetSnapshots(inspectedWidgets)
            if inspectedCount > 1 then clearActiveGroupPrompt(inspectedWidgets) end
            M.refreshNativePanel()
        end,
    }))
    actionRow:AddChild(restoreButton)

    local dirtyWidgetCount = getDirtyWidgetCount()
    local canSelectDirty = dirtyWidgetCount > 0
    local selectDirtyColors = getRestoreButtonColors(canSelectDirty)
    selectDirtyButton, selectDirtyButtonText = pickingTipsButton(Button, Label, secondaryButtonProps({
        fontSize = 11,
        height = 26,
        minWidth = 78,
        flexShrink = 0,
        disabled = not canSelectDirty,
        backgroundColor = selectDirtyColors.bg,
        hoverBackgroundColor = selectDirtyColors.hoverBg,
        pressedBackgroundColor = selectDirtyColors.pressedBg,
        disabledBackgroundColor = selectDirtyColors.bg,
        textColor = selectDirtyColors.text,
        onClick = function()
            if not updateSelectDirtyButtonState() then return end
            if ctx.UIInspector and ctx.UIInspector.SelectDirtyWidgets then
                ctx.UIInspector.SelectDirtyWidgets()
            end
        end,
    }), formatDirtyButtonText(dirtyWidgetCount), nil, nil)
    actionRow:AddChild(selectDirtyButton)

    actionRow:AddChild(Button(primaryButtonProps({
        text = _tr("t_1HkU4LxmF1HYQKoY29"),
        fontSize = 11,
        height = 26,
        paddingHorizontal = 10,
        flexShrink = 0,
        disabled = inspectedCount == 0,
        onClick = function()
            if inspectedCount == 0 then return end
            M.showCopyResult()
        end,
    })))

    addSoftDivider(panel)

    local contentHost = panel
    if ScrollView then
        local scroll = ScrollView {
            flexGrow = 1,
            flexShrink = 1,
            flexBasis = 0,
            minHeight = 0,
            alignSelf = "stretch",
            scrollY = true,
            scrollX = false,
            showScrollbar = true,
            scrollbarInteractive = true,
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
        }
        panel:AddChild(scroll)
        local content = Panel {
            gap = 8,
            alignSelf = "stretch",
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
            paddingRight = 20,
        }
        scroll:AddChild(content)
        contentHost = content
        addPanelResizeHandle(panel)
    end

    if inspectedCount == 0 then
        addInfoLine(contentHost, _tr("t_6k7jcvdA6JT9NT14"), inspectorColors.textSecondary)
        addInfoLine(contentHost, _tr("t_16lwm4Okw17HRPQcDo"), inspectorColors.textSecondary)
        addInfoLine(contentHost, _tr("t_1H8mvH2681GwjAs3oA"), inspectorColors.textSecondary)
        addInfoLine(contentHost, _tr("t_17VIRUdnl17hMB3ytD"), inspectorColors.textSecondary)
        addInfoLine(contentHost, _tr("t_T4IEhesbSx4VEu0F"), inspectorColors.textSecondary)
        addPanelResizeHandle(panel)
        return
    end

    addPreviewEditNotice(contentHost)

    addWidgetInfoEntries(contentHost, activeWidget, inspectedWidgets)
    addSoftDivider(contentHost)

    -- ================================================================
    -- Change Notes Section
    -- ================================================================
    if inspectedCount > 1 then
        addSectionTitle(contentHost, _tr("t_1psJ0LyZ1KNfKPVh"))
        ctx.groupDescTextField = createInspectorTextField(TextField, {
            height = 28,
            fontSize = 12,
            value = getActiveGroupPrompt(inspectedWidgets),
            placeholder = _tr("t_rTbJ9yKHrMNZs9PT"),
            alignSelf = "stretch",
            onChange = function(_, value)
                setActiveGroupPrompt(inspectedWidgets, value or "")
                updateRestoreButtonState()
                updateSelectDirtyButtonState()
            end,
            onBlur = function(tf)
                setActiveGroupPrompt(inspectedWidgets, tf.props.value or "")
                updateRestoreButtonState()
                updateSelectDirtyButtonState()
            end,
        })
        contentHost:AddChild(ctx.groupDescTextField)
    else
        addSectionTitle(contentHost, _tr("t_mlExeyB5nBorFBrd"))
        local promptWidget = getSelectedPromptWidget()
        local descField = createInspectorTextField(TextField, {
            height = 28,
            fontSize = 12,
            value = getWidgetPrompt(promptWidget),
            placeholder = _tr("t_tcKu26ePu2unXAg3"),
            alignSelf = "stretch",
            onChange = function(_, value)
                setWidgetPrompt(promptWidget, value or "")
                updateRestoreButtonState()
                updateSelectDirtyButtonState()
            end,
            onBlur = function(tf)
                setWidgetPrompt(promptWidget, tf.props.value or "")
                updateRestoreButtonState()
                updateSelectDirtyButtonState()
            end,
        })
        contentHost:AddChild(descField)
        ctx.descTextField = descField
    end

    -- ================================================================
    -- Props
    -- ================================================================
    local editableKeys = QuickTweak.getEditableProps(inspectedWidgets)
    ctx.tweakFields = {}

    local propKeys = getPropKeysForSelection()
    local propKeySet = {}
    for _, key in ipairs(propKeys) do
        propKeySet[key] = true
    end
    for _, key in ipairs(editableKeys) do
        if not propKeySet[key] then
            propKeys[#propKeys + 1] = key
            propKeySet[key] = true
        end
    end
    ctx.sortPropKeys(propKeys)

    local propDefs = {}
    local visiblePropKeys = {}
    for _, key in ipairs(propKeys) do
        local schemaDef, schemaConflict = nil, false
        if ctx.getPropDefForSelection then
            schemaDef, schemaConflict = ctx.getPropDefForSelection(key, inspectedWidgets)
        end
        if not schemaConflict then
            local def = schemaDef or getGenericEditablePropDef(key)
            propDefs[key] = def
            visiblePropKeys[#visiblePropKeys + 1] = key
        end
    end
    propKeys = visiblePropKeys
    local allPropKeys = propKeys
    local activePropTab, visiblePropTabs = getActivePropTab(allPropKeys, propDefs)
    ctx.inspectorPropTab = activePropTab
    propKeys = filterPropKeysForTab(allPropKeys, propDefs, activePropTab)

    local selectedPropVisible = false
    for _, key in ipairs(propKeys) do
        if key == ctx.selectedPropKey then
            selectedPropVisible = true
            ctx.selectedPropDef = propDefs[key]
            break
        end
    end
    if not selectedPropVisible then
        ctx.selectedPropKey = nil
        ctx.selectedPropDef = nil
        ctx.selectedPropRow = nil
    end

    local function spacingValueEquals(widget, key, value)
        if widget.props[key] ~= nil then
            return ctx.valuesEqual(widget.props[key], value)
        end

        local sides = { "Top", "Right", "Bottom", "Left" }
        local desired = {}
        if type(value) == "number" or type(value) == "string" then
            desired = { value, value, value, value }
        elseif type(value) == "table" then
            if #value == 1 then
                desired = { value[1], value[1], value[1], value[1] }
            elseif #value == 2 then
                desired = { value[1], value[2], value[1], value[2] }
            elseif #value == 3 then
                desired = { value[1], value[2], value[3], value[2] }
            else
                desired = { value[1], value[2], value[3], value[4] }
            end
        else
            return false
        end

        local hasSideValue = false
        for i, side in ipairs(sides) do
            local current = widget.props[key .. side]
            if current ~= nil then hasSideValue = true end
            if not ctx.valuesEqual(current or 0, desired[i] or 0) then
                return false
            end
        end
        return hasSideValue
    end

    local function canDragInspectorField(key, def)
        if not def then return false end
        if def.type == "number" or def.type == "spacing" then
            return true
        end
        if def.type ~= "layout" then
            return false
        end

        for _, widget in ipairs(inspectedWidgets) do
            if isWidgetAlive(widget) then
                local value = widget.props[key]
                if value ~= nil and type(value) ~= "number" then
                    return false
                end
            end
        end
        return true
    end

    local function commitTweakField(tf, text, key, def, same)
        local normalizedText = tostring(text or ""):match("^%s*(.-)%s*$") or ""
        if normalizedText == "" then
            local cleared = QuickTweak.clearPropToDefault(inspectedWidgets, key, def)
            if cleared then
                refreshEditIndicators(key)
            end
            tf.props.value = ""
            return
        end
        local pval, ok = QuickTweak.parsePropInput(key, normalizedText, def)
        if not ok then
            local s, v = QuickTweak.getConsensusValue(key)
            tf.props.value = s and (v or "") or ""
            return
        end
        local appliedAny = false
        for _, w in ipairs(inspectedWidgets) do
            if isWidgetAlive(w) then
                local shouldApply
                if def.type == "spacing" then
                    shouldApply = not spacingValueEquals(w, key, pval)
                else
                    shouldApply = not ctx.valuesEqual(w.props[key], pval)
                end
                if shouldApply then
                    appliedAny = true
                    QuickTweak.ensureSnapshots({ w }, { key })
                    local styleTable = {}
                    if def.type == "spacing" then
                        local sides = { "Top", "Right", "Bottom", "Left" }
                        for _, side in ipairs(sides) do
                            styleTable[key .. side] = nil
                            w.props[key .. side] = nil
                        end
                    end
                    styleTable[key] = pval
                    if QuickTweak.applyVerifiedTweakValue then
                        QuickTweak.applyVerifiedTweakValue(w, styleTable)
                    else
                        QuickTweak.applyTweakValue(w, styleTable)
                    end
                end
            end
        end
        if appliedAny then
            refreshEditIndicators(key)
        end
        local s, v = QuickTweak.getConsensusValue(key)
        tf.props.value = s and (v or "") or ""
    end

    local function getConsensusRawOrDefault(key, defaultValue)
        local same, value = QuickTweak.getConsensusRawValue(key)
        if not same then return nil, false end
        if value == nil then return defaultValue, true end
        return value, true
    end

    local function addUniqueKey(list, seen, key)
        if not key or seen[key] then return end
        seen[key] = true
        list[#list + 1] = key
    end

    local function applyLayoutHelper(styleOrFactory, keys, clearKeys)
        local snapshotKeys = {}
        local seen = {}
        for _, key in ipairs(keys or {}) do
            addUniqueKey(snapshotKeys, seen, key)
        end
        for _, key in ipairs(clearKeys or {}) do
            addUniqueKey(snapshotKeys, seen, key)
        end
        if #snapshotKeys > 0 then
            QuickTweak.ensureSnapshots(inspectedWidgets, snapshotKeys)
        end

        for _, key in ipairs(clearKeys or {}) do
            QuickTweak.clearPropToDefault(inspectedWidgets, key, propDefs[key])
        end

        for _, widget in ipairs(inspectedWidgets) do
            if isWidgetAlive(widget) then
                local styleTable = type(styleOrFactory) == "function"
                    and styleOrFactory(widget)
                    or styleOrFactory
                if styleTable and next(styleTable) then
                    QuickTweak.applyTweakValue(widget, styleTable)
                end
            end
        end

        if ctx.uiModule and ctx.uiModule.Layout then
            ctx.uiModule.Layout()
        end
        refreshEditIndicators()
        M.refreshNativePanel()
    end

    local function makeLayoutHelperButton(text, active, onClick, width)
        local props = active and primaryButtonProps({
            text = text,
            fontSize = 11,
            height = 24,
            width = width,
            paddingHorizontal = 0,
            flexShrink = 0,
        }) or secondaryButtonProps({
            text = text,
            fontSize = 11,
            height = 24,
            width = width,
            paddingHorizontal = 0,
            flexShrink = 0,
            backgroundColor = { 44, 44, 50, 210 },
            hoverBackgroundColor = { 58, 58, 66, 235 },
            pressedBackgroundColor = { 38, 38, 44, 240 },
        })
        props.onClick = onClick
        return Button(props)
    end

    local function addLayoutHelperButtonRow(parent, labelText, buttons)
        local row = Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            alignSelf = "stretch",
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
        }
        row:AddChild(Label {
            text = labelText,
            width = 34,
            fontSize = 10,
            fontColor = { 255, 255, 255, 115 },
            textAlign = "right",
            whiteSpace = "nowrap",
            flexShrink = 0,
        })
        local buttonHost = Panel {
            flexDirection = "row",
            flexWrap = "wrap",
            alignItems = "center",
            gap = 4,
            flexGrow = 1,
            flexShrink = 1,
            backgroundColor = defaultColors.transparent,
            borderWidth = 0,
        }
        for _, button in ipairs(buttons or {}) do
            buttonHost:AddChild(button)
        end
        row:AddChild(buttonHost)
        parent:AddChild(row)
    end

    local function makeAlignmentCell(xIndex, yIndex, active, onClick)
        local cell = makeLayoutHelperButton("", active, onClick, 26)
        cell:SetStyle({ height = 28, minWidth = 30, paddingHorizontal = 0 })
        local baseRender = cell.Render
        function cell:Render(nvg)
            if baseRender then baseRender(self, nvg) end
            local l = self:GetAbsoluteLayout()
            if not l or l.x ~= l.x then return end

            local color = active
                and { 24, 24, 28, 220 }
                or { 255, 255, 255, 150 }
            local boxX = l.x + 5
            local boxY = l.y + 4
            local boxW = l.w - 10
            local boxH = l.h - 8

            -- 容器轮廓
            nvgSave(nvg)
            nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], active and 100 or 60))
            nvgStrokeWidth(nvg, 1)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, boxX, boxY, boxW, boxH, 2)
            nvgStroke(nvg)

            -- 3 条短横线代表子元素，按对齐位置排列
            local barW = 7
            local barH = 1
            local barGap = 3
            local groupH = barH * 3 + barGap * 2
            local groupW = barW

            -- xIndex/yIndex: 1=start, 2=center, 3=end
            local gx, gy
            if xIndex == 1 then gx = boxX + 2
            elseif xIndex == 2 then gx = boxX + (boxW - groupW) / 2
            else gx = boxX + boxW - groupW - 2
            end
            if yIndex == 1 then gy = boxY + 2
            elseif yIndex == 2 then gy = boxY + (boxH - groupH) / 2
            else gy = boxY + boxH - groupH - 2
            end

            nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4]))
            gx = math.floor(gx + 0.5)
            gy = math.floor(gy + 0.5)
            for i = 0, 2 do
                nvgBeginPath(nvg)
                nvgRect(nvg, gx, gy + math.floor(i * (barH + barGap) + 0.5), barW, barH)
                nvgFill(nvg)
            end
            nvgRestore(nvg)
        end
        return cell
    end

    local POS_KEYS = { "position", "left", "top", "right", "bottom" }

    local function switchPositionPreserving(targetPosition)
        QuickTweak.ensureSnapshots(inspectedWidgets, POS_KEYS)

        -- 1. 记录当前视觉位置和原有定位字段
        local records = {}
        for _, w in ipairs(inspectedWidgets) do
            if isWidgetAlive(w) then
                local l = w:GetAbsoluteLayout()
                if l and l.x == l.x then
                    records[w] = {
                        x = l.x, y = l.y,
                        useRight = w.props.right ~= nil and w.props.left == nil,
                        useBottom = w.props.bottom ~= nil and w.props.top == nil,
                    }
                end
            end
        end

        -- 2. 先切 position，清除偏移，layout 一次得到新基准
        for _, key in ipairs(POS_KEYS) do
            QuickTweak.clearPropToDefault(inspectedWidgets, key)
        end
        if targetPosition == "absolute" then
            for _, w in ipairs(inspectedWidgets) do
                if isWidgetAlive(w) then
                    QuickTweak.applyTweakValue(w, { position = "absolute" })
                end
            end
        end
        if ctx.uiModule and ctx.uiModule.Layout then ctx.uiModule.Layout() end

        -- 3. 从新基准算偏移
        for _, w in ipairs(inspectedWidgets) do
            if isWidgetAlive(w) and records[w] then
                local rec = records[w]
                local base = w:GetAbsoluteLayout()
                local parent = w.parent
                local parentLayout = parent and parent.GetAbsoluteLayout and parent:GetAbsoluteLayout()
                if base and base.x == base.x then
                    local style = {}
                    if targetPosition == "absolute" and parentLayout then
                        if rec.useRight then
                            style.right = math.floor((parentLayout.x + parentLayout.w) - (rec.x + base.w) + 0.5)
                        else
                            style.left = math.floor(rec.x - parentLayout.x + 0.5)
                        end
                        if rec.useBottom then
                            style.bottom = math.floor((parentLayout.y + parentLayout.h) - (rec.y + base.h) + 0.5)
                        else
                            style.top = math.floor(rec.y - parentLayout.y + 0.5)
                        end
                    else
                        if rec.useRight then
                            local ox = math.floor(base.x - rec.x + 0.5)
                            if ox ~= 0 then style.right = ox end
                        else
                            local ox = math.floor(rec.x - base.x + 0.5)
                            if ox ~= 0 then style.left = ox end
                        end
                        if rec.useBottom then
                            local oy = math.floor(base.y - rec.y + 0.5)
                            if oy ~= 0 then style.bottom = oy end
                        else
                            local oy = math.floor(rec.y - base.y + 0.5)
                            if oy ~= 0 then style.top = oy end
                        end
                    end
                    if next(style) then
                        QuickTweak.applyTweakValue(w, style)
                    end
                end
            end
        end

        if ctx.uiModule and ctx.uiModule.Layout then ctx.uiModule.Layout() end
        refreshEditIndicators("position")
        M.refreshNativePanel()
    end

    local function addLayoutAssistant(parent)
        if activePropTab ~= "layout" or inspectedCount == 0 then return end

        local hasContainerWidget = false
        for _, w in ipairs(inspectedWidgets) do
            if isWidgetAlive(w) and w.children and #w.children > 0 then
                hasContainerWidget = true
                break
            end
        end

        local position, positionSame = getConsensusRawOrDefault("position", nil)

        local helper = Panel {
            gap = 7,
            padding = 8,
            alignSelf = "stretch",
            backgroundColor = { 255, 255, 255, 6 },
            borderColor = { 255, 255, 255, 22 },
            borderWidth = getHairlineBorderWidth(),
            borderRadius = 5,
        }
        parent:AddChild(helper)

        helper:AddChild(Label {
            text = _tr("t_LR2WYBPaLYKwjH16"),
            fontSize = 11,
            fontWeight = "bold",
            fontColor = inspectorColors.text,
            whiteSpace = "nowrap",
        })

        -- 排列/对齐/分布：仅容器（有子节点）显示
        if hasContainerWidget then
            local direction, directionSame = getConsensusRawOrDefault("flexDirection", "column")
            local wrap, wrapSame = getConsensusRawOrDefault("flexWrap", "nowrap")
            local justify, justifySame = getConsensusRawOrDefault("justifyContent", "flex-start")
            local align, alignSame = getConsensusRawOrDefault("alignItems", nil)
            local isRow = direction == "row" or direction == "row-reverse"
            local function alignmentStyle(xValue, yValue)
                if isRow then
                    return { justifyContent = xValue, alignItems = yValue }
                end
                return { alignItems = xValue, justifyContent = yValue }
            end
            local function alignmentActive(xValue, yValue)
                if not justifySame or not alignSame or not directionSame then return false end
                local expected = alignmentStyle(xValue, yValue)
                return justify == expected.justifyContent and align == expected.alignItems
            end

            addLayoutHelperButtonRow(helper, _tr("t_yjeuGe8pyvnL3GEH"), {
                makeLayoutHelperButton(_tr("t_16chbxD9116C33mAMf"), directionSame and wrapSame and direction == "column" and wrap ~= "wrap", function()
                    applyLayoutHelper({ flexDirection = "column", flexWrap = "nowrap" }, { "flexDirection", "flexWrap" })
                end, 48),
                makeLayoutHelperButton(_tr("t_uHdRYbKJun3Lg0hd"), directionSame and wrapSame and direction == "row" and wrap ~= "wrap", function()
                    applyLayoutHelper({ flexDirection = "row", flexWrap = "nowrap" }, { "flexDirection", "flexWrap" })
                end, 48),
                makeLayoutHelperButton(_tr("t_15nWC7wQb15bNj5dV9"), directionSame and wrapSame and direction == "row" and wrap == "wrap", function()
                    applyLayoutHelper({ flexDirection = "row", flexWrap = "wrap" }, { "flexDirection", "flexWrap" })
                end, 48),
            })

            local alignButtons = {}
            local alignValues = { "flex-start", "center", "flex-end" }
            for yIndex, yValue in ipairs(alignValues) do
                for xIndex, xValue in ipairs(alignValues) do
                    local style = alignmentStyle(xValue, yValue)
                    alignButtons[#alignButtons + 1] = makeAlignmentCell(
                        xIndex,
                        yIndex,
                        alignmentActive(xValue, yValue),
                        function()
                            applyLayoutHelper(style, { "justifyContent", "alignItems" })
                        end
                    )
                end
            end
            addLayoutHelperButtonRow(helper, _tr("t_19DV8BTpu19izihumu"), alignButtons)

            addLayoutHelperButtonRow(helper, _tr("t_8tfTD9Jc9KFMnRGU"), {
                makeLayoutHelperButton(_tr("t_HGEktMdZH8wN1GCB"), justifySame and justify == "space-between", function()
                    applyLayoutHelper({ justifyContent = "space-between" }, { "justifyContent" })
                end, 48),
                makeLayoutHelperButton(_tr("t_UoJHM2LEUvX0wYqo"), justifySame and justify == "space-around", function()
                    applyLayoutHelper({ justifyContent = "space-around" }, { "justifyContent" })
                end, 48),
                makeLayoutHelperButton(_tr("t_qOGqjuBapxcIoBcO"), justifySame and justify == "space-evenly", function()
                    applyLayoutHelper({ justifyContent = "space-evenly" }, { "justifyContent" })
                end, 48),
            })
        end

        -- 定位：所有组件都可用
        addLayoutHelperButtonRow(helper, _tr("t_ufgLFiwVuF1mWr9R"), {
            makeLayoutHelperButton(_tr("t_u9E3I46VtiZUikUn"), positionSame and (position == nil or position == "relative"), function()
                switchPositionPreserving(nil)
            end, 64),
            makeLayoutHelperButton(_tr("t_iuu4vsKLiUFU78ux"), positionSame and position == "absolute", function()
                switchPositionPreserving("absolute")
            end, 64),
        })
    end

    addSectionTitle(contentHost, _tr("t_2yMGFmvC2XmOOGD2"))
    addPropTabs(contentHost, visiblePropTabs, activePropTab)
    addLayoutAssistant(contentHost)

    if #propKeys == 0 then
        addInfoLine(contentHost, _tr("t_5jJZ9xd36EjTslex"), inspectorColors.textSecondary)
    else
        for i = 1, #propKeys do
            local key = propKeys[i]
            local def = propDefs[key]
            local editable = def ~= nil
            local propSelected = ctx.selectedPropKey == key
            local row = Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                minHeight = 28,
                backgroundColor = propSelected and { 255, 255, 255, 18 } or defaultColors.transparent,
                borderWidth = 0,
                borderRadius = 4,
                pointerEvents = "auto",
                onPointerDown = function(event, widget)
                    handlePropPointerDown(event, key, def, widget, widget)
                end,
            }
            contentHost:AddChild(row)
            if propSelected then
                ctx.selectedPropRow = row
            end

            local isDraggable = editable and canDragInspectorField(key, def)
            local label = Label {
                text = def and def.label or ctx.getPropLabel(key),
                fontSize = 11,
                fontColor = editable and ctx.TWEAK_LABEL_NORMAL or inspectorColors.textSecondary,
                width = 126,
                flexShrink = 0,
                whiteSpace = "nowrap",
                pointerEvents = "auto",
                onPointerDown = function(event, widget)
                    handlePropPointerDown(event, key, def, row, widget)
                end,
                onPointerEnter = function(_, widget)
                    showPropKeyTooltip(key, widget)
                end,
                onPointerLeave = function()
                    hidePropKeyTooltip()
                end,
            }
            row:AddChild(label)

            local displayValue, same = getPropConsensusDisplay(key)
            local displayText = same and (displayValue or "") or _tr("t_1HmLUkPrh1HKrUJA0V")

            if editable then
                if def.type == "color" then
                    local rgba = same and inspectedWidgets[1] and inspectedWidgets[1].props[key] or nil
                    local colorStatusLabel = nil
                    local picker = createInspectorColorPicker(ctx.ColorPicker, {
                        flexGrow = 1,
                        flexShrink = 1,
                        height = 28,
                        size = "sm",
                        showAlpha = true,
                        value = toInspectorColorValue(rgba),
                        queueOverlay = function(callback)
                            ctx.inspectorOverlayCallbacks[#ctx.inspectorOverlayCallbacks + 1] = callback
                        end,
                        onChange = function(cp, value)
                            local newColor = { value.r, value.g, value.b, value.a }
                            for _, w in ipairs(inspectedWidgets) do
                                if isWidgetAlive(w) then
                                    QuickTweak.applyTweakValue(w, { [key] = newColor })
                                end
                            end
                            if colorStatusLabel then
                                colorStatusLabel:SetText("")
                                colorStatusLabel:SetStyle({ width = 0 })
                            end
                            refreshEditIndicators()
                        end,
                    })
                    local baseColorPointerDown = picker.OnPointerDown
                    function picker:OnPointerDown(event)
                        if handlePropPointerDown(event, key, def, row, self) then return true end
                        if baseColorPointerDown then
                            return baseColorPointerDown(self, event)
                        end
                        return false
                    end
                    row:AddChild(picker)
                    local colorStatusText = getInspectorColorStatusText(same, rgba)
                    colorStatusLabel = Label {
                        text = colorStatusText,
                        fontSize = 10,
                        fontColor = inspectorColors.textSecondary,
                        width = colorStatusText ~= "" and 42 or 0,
                        flexShrink = 0,
                        textAlign = "center",
                    }
                    row:AddChild(colorStatusLabel)
                    ctx.tweakFields[#ctx.tweakFields + 1] = {
                        key = key,
                        colorPicker = picker,
                        colorStatusLabel = colorStatusLabel,
                        def = def,
                        label = label,
                        isDraggable = false,
                    }
                elseif def.type == "boolean" and Dropdown then
                    local boolValue = same and inspectedWidgets[1] and inspectedWidgets[1].props[key] or nil
                    local dropdown = createInspectorDropdown(Dropdown, {
                        flexGrow = 1,
                        flexShrink = 1,
                        height = 26,
                        options = getInspectorBooleanOptions(key),
                        value = boolValue,
                        placeholder = same and _tr("t_K1KIgS7eKRyqgDtU") or _tr("t_1HmLUkPrh1HKrUJA0V"),
                        onPointerDown = function(event, widget)
                            handlePropPointerDown(event, key, def, row, widget)
                        end,
                        onChange = function(_, value)
                            for _, w in ipairs(inspectedWidgets) do
                                if isWidgetAlive(w) then
                                    QuickTweak.applyTweakValue(w, { [key] = value })
                                end
                            end
                            refreshEditIndicators(key)
                        end,
                    })
                    row:AddChild(dropdown)
                    ctx.tweakFields[#ctx.tweakFields + 1] = {
                        key = key,
                        dropdown = dropdown,
                        def = def,
                        label = label,
                        isDraggable = false,
                    }
                elseif def.type == "enum" and Dropdown then
                    local enumValue = same and inspectedWidgets[1] and inspectedWidgets[1].props[key] or nil
                    local dropdownValue = enumValue
                    local dropdown = createInspectorDropdown(Dropdown, {
                        flexGrow = 1,
                        flexShrink = 1,
                        height = 26,
                        options = getInspectorEnumOptions(key, def, enumValue),
                        onPointerDown = function(event, widget)
                            handlePropPointerDown(event, key, def, row, widget)
                        end,
                        value = dropdownValue,
                        placeholder = same and _tr("t_K1KIgS7eKRyqgDtU") or _tr("t_1HmLUkPrh1HKrUJA0V"),
                        onChange = function(_, value)
                            if value == nil and def.defaultLabel then
                                QuickTweak.clearPropToDefault(inspectedWidgets, key, def)
                                refreshEditIndicators(key)
                                return
                            end
                            for _, w in ipairs(inspectedWidgets) do
                                if isWidgetAlive(w) then
                                    QuickTweak.applyTweakValue(w, { [key] = value })
                                end
                            end
                            refreshEditIndicators(key)
                        end,
                    })
                    row:AddChild(dropdown)
                    ctx.tweakFields[#ctx.tweakFields + 1] = {
                        key = key,
                        dropdown = dropdown,
                        enumDef = def,
                        def = def,
                        label = label,
                        isDraggable = false,
                    }
                else
                    local inputProps = {
                        flexGrow = 1,
                        flexShrink = 1,
                        height = 24,
                        fontSize = 11,
                        value = same and (displayValue or "") or "",
                        placeholder = same and "" or _tr("t_1HmLUkPrh1HKrUJA0V"),
                        onSubmit = function(tf, text)
                            commitTweakField(tf, text, key, def, same)
                        end,
                        onBlur = function(tf)
                            commitTweakField(tf, tf.props.value or "", key, def, same)
                        end,
                    }
                    local inputField = isDraggable
                        and createNumericInspectorTextField(TextField, key, def, inputProps)
                        or createInspectorTextField(TextField, inputProps)
                    inputField.inspectorPropRow_ = row
                    local baseInputPointerDown = inputField.OnPointerDown
                    function inputField:OnPointerDown(event)
                        if handlePropPointerDown(event, key, def, row, self) then return true end
                        if baseInputPointerDown then
                            return baseInputPointerDown(self, event)
                        end
                        return false
                    end
                    row:AddChild(inputField)
                    ctx.tweakFields[#ctx.tweakFields + 1] = {
                        key = key,
                        textField = inputField,
                        def = def,
                        label = label,
                        isDraggable = isDraggable,
                    }
                end
            else
                row:AddChild(Label {
                    text = displayText,
                    fontSize = 10,
                    fontColor = inspectorColors.text,
                    whiteSpace = "normal",
                    flexGrow = 1,
                })
            end
        end
        refreshEditIndicators()
    end
    addPanelResizeHandle(panel)
end

-- TODO: refreshNativePanel 每次全量销毁并重建面板子组件。
-- 当前属性行数（30-50）下性能可接受，但若面板内容增长应考虑局部更新。
function M.refreshNativePanel()
    if not ctx.inspectorPanelRoot then return end
    M.createNativePanel()
    M.updatePickingTips()
end

return M
end
