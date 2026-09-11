-- ============================================================================
-- UI Inspector
-- Runtime widget inspection tool for AI-assisted UI debugging
-- ============================================================================
--
-- Usage:
--   UI_INSPECTOR_ENABLED = true  -- enable source tracking (before building UI)
--   UI.Init({ ... })
--   UI.Inspector.Init(UI, { hotkey = KEY_F9 })
--
-- Press F9 (or configured hotkey) to enter edit mode:
--   - Game freezes (scene + UI updates stop, rendering continues)
--   - Hover over widgets to highlight them
--   - Click widgets to select or cancel the current inspector target
--   - Inspector opens immediately; no Enter step
--   - Esc exits, with confirm if there are runtime edits
--
-- Explicit selection: hold Ctrl or use the target button to include widgets in the inspector context.
-- "交给嗒啦啦改源码" exports only the current selection.
--
-- ============================================================================

local UIInspector = {}

-- Load shared context and sub-modules
local ctx = require("urhox-libs/UI/Core/UIInspector/Context")
ctx.UIInspector = UIInspector  -- cross-module reference for Panel callbacks

local Selection = require("urhox-libs/UI/Core/UIInspector/Selection")(ctx)
local Overlay   = require("urhox-libs/UI/Core/UIInspector/Overlay")(ctx, Selection)
local Report    = require("urhox-libs/UI/Core/UIInspector/Report")(ctx, Selection)
local QuickTweak = require("urhox-libs/UI/Core/UIInspector/QuickTweak")(ctx)
local EditTool  = require("urhox-libs/UI/Core/UIInspector/EditTool")(ctx, QuickTweak)
local Panel     = require("urhox-libs/UI/Core/UIInspector/Panel")(ctx, QuickTweak, Report, Overlay)
ctx.EditTool = EditTool
ctx.QuickTweak = QuickTweak

-- ============================================================================
-- Freeze / Unfreeze
-- ============================================================================

-- 进入 Inspector 时临时释放鼠标锁定，退出时恢复（suppressEvent=true 不污染游戏期望状态）
local savedMouseMode_, savedMouseVisible_

local function releaseMouseForEdit()
    if not input then return end
    if savedMouseMode_ ~= nil then return end
    savedMouseMode_ = input:GetMouseMode()
    savedMouseVisible_ = input:IsMouseVisible()
    input:SetMouseMode(MM_ABSOLUTE, true)
    input:SetMouseVisible(true, true)
end

local function restoreMouseAfterEdit()
    if not input then return end
    if savedMouseMode_ == nil then return end
    input:SetMouseMode(savedMouseMode_, true)
    input:SetMouseVisible(savedMouseVisible_, true)
    savedMouseMode_ = nil
    savedMouseVisible_ = nil
end

local function freezeGame()
    -- Stop UI updates (transitions, gestures, widget:Update)
    ctx.uiModule.DisableAutoEventsUpdate()

    -- Pause scene updates (if scene_ global exists)
    if scene_ and scene_.SetUpdateEnabled then
        scene_:SetUpdateEnabled(false)
    end

    -- Release captured mouse so the user can pick/tweak widgets
    releaseMouseForEdit()

    -- Keep AutoEventsRender (frozen frame still displays)
    -- Keep AutoEventsInput (we need mouse/keyboard events for picking)
end

local function unfreezeGame()
    -- Restore UI updates
    ctx.uiModule.EnableAutoEventsUpdate()

    -- Resume scene
    if scene_ and scene_.SetUpdateEnabled then
        scene_:SetUpdateEnabled(true)
    end

    -- Restore the mouse lock state the game had before editing
    restoreMouseAfterEdit()
end

-- ============================================================================
-- State Transitions
-- ============================================================================

local function isInspectorTreeHit(x, y)
    if not ctx.inspectorPanelRoot then return false end
    local hit = ctx.uiModule.FindWidgetAt(x, y)
    local w = hit
    while w do
        if w == ctx.inspectorPanelRoot then return true end
        w = w.parent
    end
    return false
end

local function clearComponentPointerFocus()
    ctx.hoveredWidget = nil
    ctx.hoverEditWidget = nil
    ctx.editToolHoverTip = nil
    ctx.pointerOverInspectorChrome = true
end

local function setPointerOutsideInspectorChrome()
    ctx.pointerOverInspectorChrome = false
end

local function isRootWidget(widget)
    return ctx.uiModule.GetRoot and widget == ctx.uiModule.GetRoot()
end

local function hitWidgetBounds(widget, x, y)
    if not widget or not widget.GetAbsoluteLayoutForHitTest then return false end
    local l = widget:GetAbsoluteLayoutForHitTest()
    if not l or l.x ~= l.x or l.y ~= l.y or l.w ~= l.w or l.h ~= l.h then
        return false
    end
    if l.w <= 0 or l.h <= 0 then return false end
    if widget.HitTest then
        return widget:HitTest(x, y)
    end
    return x >= l.x and x <= l.x + l.w and y >= l.y and y <= l.y + l.h
end

local function collectInspectorHitChildren(widget)
    local children = {}
    if widget.GetRenderChildren then
        local renderChildren = widget:GetRenderChildren()
        for i = 1, #renderChildren do
            children[#children + 1] = renderChildren[i]
        end
    elseif widget.children then
        for i = 1, #widget.children do
            children[#children + 1] = widget.children[i]
        end
    end
    if widget.bodyChildren_ then
        for i = 1, #widget.bodyChildren_ do
            children[#children + 1] = widget.bodyChildren_[i]
        end
    end
    if widget.GetHitTestChildren then
        local extraChildren = widget:GetHitTestChildren()
        if extraChildren then
            for i = 1, #extraChildren do
                children[#children + 1] = extraChildren[i]
            end
        end
    end
    return children
end

local function findInspectableWidgetAtIn(widget, x, y)
    if not ctx.isWidgetAlive(widget) or not widget:IsVisible() then return nil end
    if not hitWidgetBounds(widget, x, y) then return nil end

    local children = collectInspectorHitChildren(widget)
    for i = #children, 1, -1 do
        local found = findInspectableWidgetAtIn(children[i], x, y)
        if found then return found end
    end

    if not isRootWidget(widget) then
        return widget
    end
    return nil
end

local function findInspectableWidgetAt(x, y)
    local normalHit = ctx.uiModule.FindWidgetAt(x, y)
    if normalHit and not isRootWidget(normalHit) then
        return findInspectableWidgetAtIn(normalHit, x, y) or normalHit
    end

    local root = ctx.uiModule.GetRoot and ctx.uiModule.GetRoot()
    if not root then return nil end
    return findInspectableWidgetAtIn(root, x, y)
end

local function isCtrlDown()
    if not input then return false end
    if input.GetQualifierDown and QUAL_CTRL then
        return input:GetQualifierDown(QUAL_CTRL)
    end
    if input.GetKeyDown then
        local lctrl = KEY_LCTRL and input:GetKeyDown(KEY_LCTRL)
        local rctrl = KEY_RCTRL and input:GetKeyDown(KEY_RCTRL)
        local ctrl = KEY_CTRL and input:GetKeyDown(KEY_CTRL)
        return lctrl or rctrl or ctrl or false
    end
    return false
end

local function isAKey(key)
    return (KEY_A and key == KEY_A) or key == 65 or key == 97
end

local function isDeleteKey(key)
    return (KEY_DELETE and key == KEY_DELETE) or key == 127
end

local function isTextInputFocused()
    if not ctx.uiModule.GetFocus then return false end
    local focused = ctx.uiModule.GetFocus()
    return focused
        and focused._className == "TextField"
        and focused.state
        and focused.state.focused
end

local function isNonNegativeDragKey(key)
    return key == "width" or key == "height"
        or key == "minWidth" or key == "maxWidth" or key == "minHeight" or key == "maxHeight"
        or key == "padding" or key == "paddingTop" or key == "paddingRight"
        or key == "paddingBottom" or key == "paddingLeft"
        or key == "borderWidth" or key == "borderRadius"
        or key == "fontSize" or key == "lineHeight" or key == "letterSpacing"
        or key == "gap" or key == "rowGap" or key == "columnGap"
        or key == "scale" or key == "opacity"
end

local function getNumericDragStep(key, def)
    if key == "opacity" or key == "scale" or key == "lineHeight"
        or key == "flexGrow" or key == "flexShrink" or key == "aspectRatio" then
        return 0.01
    end
    return 0.25
end

local function roundNumericDragValue(value, step)
    if step <= 0.01 then
        return math.floor(value * 100 + 0.5) / 100
    end
    if step < 1 then
        return math.floor(value + 0.5)
    end
    return math.floor(value / step + 0.5) * step
end

local function normalizeNumericDragValue(key, def, value)
    local step = getNumericDragStep(key, def)
    if isNonNegativeDragKey(key) then
        value = math.max(0, value)
    end
    if key == "opacity" then
        value = math.max(0, math.min(1, value))
    end
    return roundNumericDragValue(value, step)
end

local function canApplyNumericDragState(dragState)
    if not dragState or not dragState.def or dragState.def.type ~= "layout" then
        return true
    end
    for _, widget in ipairs(ctx.inspectedWidgets or {}) do
        if ctx.isWidgetAlive(widget) then
            local value = widget.props[dragState.key]
            if value ~= nil and type(value) ~= "number" then
                return false
            end
        end
    end
    return true
end

local function beginNumericDragVerification(dragState)
    if not dragState or dragState.verifyStart then return end
    dragState.verifyStart = {}
    for _, widget in ipairs(ctx.inspectedWidgets or {}) do
        if ctx.isWidgetAlive(widget) then
            dragState.verifyStart[widget] = {
                props = { [dragState.key] = ctx.deepCopyValue(widget.props[dragState.key]) },
                rect = ctx.getWidgetScreenRect and ctx.getWidgetScreenRect(widget) or nil,
            }
        end
    end
end

local function finishNumericDragVerification(dragState)
    if not dragState or not dragState.verifyStart then
        return
    end

    if QuickTweak.verifyAppliedLayoutEffects then
        local entries = {}
        for _, widget in ipairs(ctx.inspectedWidgets or {}) do
            local start = dragState.verifyStart[widget]
            if start and ctx.isWidgetAlive(widget) then
                entries[#entries + 1] = {
                    widget = widget,
                    beforeProps = start.props,
                    beforeRect = start.rect,
                    keys = { dragState.key },
                }
            end
        end
        local result = QuickTweak.verifyAppliedLayoutEffects(entries)
        if result and result.rolledBack then
            QuickTweak.refreshTweakFields()
        end
        return
    end

    if not QuickTweak.verifyAppliedLayoutEffect then
        return
    end

    local rolledBack = false
    for _, widget in ipairs(ctx.inspectedWidgets or {}) do
        local start = dragState.verifyStart[widget]
        if start and ctx.isWidgetAlive(widget) then
            local result = QuickTweak.verifyAppliedLayoutEffect(widget, start.props, start.rect, { dragState.key })
            rolledBack = rolledBack or (result and result.rolledBack)
        end
    end
    if rolledBack then
        QuickTweak.refreshTweakFields()
    end
end

local function isWidgetExplicitlySelected(widget)
    return Selection.isWidgetSelected(widget)
end

local function syncInspectedWidgets()
    local list = {}
    local seen = {}
    local active = ctx.isWidgetAlive(ctx.activeWidget) and ctx.activeWidget
        or (ctx.isWidgetAlive(ctx.selectedWidget) and ctx.selectedWidget or nil)

    ctx.activeWidget = active
    ctx.selectedWidget = active -- compatibility alias

    if active then
        list[#list + 1] = active
        seen[active] = true
    end

    local compactSelected = {}
    for _, widget in ipairs(ctx.selectedWidgets or {}) do
        if ctx.isWidgetAlive(widget) and not compactSelected[widget] then
            compactSelected[#compactSelected + 1] = widget
            compactSelected[widget] = true
            if not seen[widget] then
                list[#list + 1] = widget
                seen[widget] = true
            end
        end
    end

    ctx.selectedWidgets = compactSelected
    ctx.inspectedWidgets = list
    local signatureParts = {}
    for _, widget in ipairs(list) do
        signatureParts[#signatureParts + 1] = tostring(widget)
    end
    local signature = table.concat(signatureParts, "|")
    if ctx.selectedWidgetInfoSignature ~= signature then
        ctx.selectedWidgetInfoSignature = signature
        ctx.selectedWidgetInfoExpanded = {}
        ctx.selectedWidgetListExpanded = false
    end
    return list
end
ctx.syncInspectedWidgets = syncInspectedWidgets

local function setActiveWidget(widget)
    local active = ctx.isWidgetAlive(widget) and widget or nil
    ctx.activeWidget = active
    ctx.selectedWidget = active -- compatibility alias
    ctx.lastActiveWidget = active
    if active then
        ctx.hoverEditWidget = active
    end
    syncInspectedWidgets()
end

local function activateWidget(widget)
    if not ctx.isWidgetAlive(widget) then return end
    setActiveWidget(widget)
    Panel.updatePickingTips()
    Panel.refreshNativePanel()
end

local function clearActiveWidget()
    if ctx.selectedWidget == nil and ctx.activeWidget == nil and ctx.lastActiveWidget == nil
        and ctx.hoveredWidget == nil and ctx.hoverEditWidget == nil
        and #ctx.selectedWidgets == 0 and #ctx.inspectedWidgets == 0 then return end
    ctx.hoveredWidget = nil
    ctx.hoverEditWidget = nil
    ctx.editToolHoverTip = nil
    ctx.activeWidget = nil
    ctx.selectedWidget = nil
    ctx.lastActiveWidget = nil
    ctx.skipNextClickToggleWidget = nil
    ctx.selectedWidgets = {}
    syncInspectedWidgets()
    Panel.updatePickingTips()
    Panel.refreshNativePanel()
end

local function clearActiveOnly()
    if ctx.activeWidget == nil and ctx.selectedWidget == nil and ctx.lastActiveWidget == nil then return end
    ctx.activeWidget = nil
    ctx.selectedWidget = nil
    ctx.lastActiveWidget = nil
    ctx.skipNextClickToggleWidget = nil
    syncInspectedWidgets()
    Panel.updatePickingTips()
    Panel.refreshNativePanel()
end

local function setWidgetExplicitlySelected(widget, selected)
    if not ctx.isWidgetAlive(widget) then return false end
    for i, selectedWidget in ipairs(ctx.selectedWidgets) do
        if selectedWidget == widget then
            if not selected then
                local wasCurrentVisual = widget == ctx.activeWidget
                    or widget == ctx.selectedWidget
                    or widget == ctx.hoverEditWidget
                    or widget == ctx.hoveredWidget
                table.remove(ctx.selectedWidgets, i)
                if wasCurrentVisual then
                    ctx.hoveredWidget = nil
                    ctx.hoverEditWidget = nil
                    local nextActive = ctx.selectedWidgets[i] or ctx.selectedWidgets[i - 1]
                    if ctx.isWidgetAlive(nextActive) then
                        setActiveWidget(nextActive)
                    else
                        ctx.activeWidget = nil
                        ctx.selectedWidget = nil
                        ctx.lastActiveWidget = nil
                        ctx.skipNextClickToggleWidget = nil
                        syncInspectedWidgets()
                    end
                else
                    syncInspectedWidgets()
                end
            end
            return true
        end
    end
    if selected then
        ctx.selectedWidgets[#ctx.selectedWidgets + 1] = widget
        syncInspectedWidgets()
        return true
    end
    return false
end

local function toggleWidgetSelection(widget)
    if not ctx.isWidgetAlive(widget) then return end

    if isWidgetExplicitlySelected(widget) then
        setWidgetExplicitlySelected(widget, false)
    else
        setWidgetExplicitlySelected(widget, true)
    end

    Panel.updatePickingTips()
    Panel.refreshNativePanel()
end

local function promoteActiveToExplicitSelection(exceptWidget)
    local active = ctx.isWidgetAlive(ctx.activeWidget) and ctx.activeWidget
        or (ctx.isWidgetAlive(ctx.selectedWidget) and ctx.selectedWidget or nil)
    if active and active ~= exceptWidget and not isWidgetExplicitlySelected(active) then
        setWidgetExplicitlySelected(active, true)
    end
end

local function replaceExplicitSelection(oldWidget, newWidget)
    if not ctx.isWidgetAlive(oldWidget) or not ctx.isWidgetAlive(newWidget) or oldWidget == newWidget then return end

    local hadOld = false
    local hasNew = false
    for i = #ctx.selectedWidgets, 1, -1 do
        local widget = ctx.selectedWidgets[i]
        if widget == oldWidget then
            table.remove(ctx.selectedWidgets, i)
            hadOld = true
        elseif widget == newWidget then
            hasNew = true
        end
    end

    if hadOld and not hasNew then
        ctx.selectedWidgets[#ctx.selectedWidgets + 1] = newWidget
    end
    if hadOld then
        syncInspectedWidgets()
    end
end

local function selectWidgets(widgets, selectAll)
    if selectAll == nil then selectAll = true end
    ctx.selectedWidgets = {}
    local first = nil
    for _, widget in ipairs(widgets or {}) do
        if ctx.isWidgetAlive(widget) then
            first = first or widget
            if selectAll then
                ctx.selectedWidgets[#ctx.selectedWidgets + 1] = widget
            end
        end
    end
    setActiveWidget(first)
    syncInspectedWidgets()
    Panel.updatePickingTips()
    Panel.refreshNativePanel()
end

local function handleSelectionClick(widget)
    if not widget then return end
    local additive = isCtrlDown()

    if additive then
        promoteActiveToExplicitSelection(widget)
        setActiveWidget(widget)
        toggleWidgetSelection(widget)
        return
    end

    if #ctx.selectedWidgets > 1 and isWidgetExplicitlySelected(widget) then
        activateWidget(widget)
        return
    end

    ctx.selectedWidgets = {}
    if widget == ctx.activeWidget or widget == ctx.selectedWidget then
        clearActiveOnly()
        return
    end

    activateWidget(widget)
end

local function selectDirtyWidgets()
    if ctx.UIInspector and ctx.UIInspector.SelectDirtyWidgets then
        ctx.UIInspector.SelectDirtyWidgets()
    end
end

local function enterPicking()
    ctx.state = ctx.STATE_EDITING
    freezeGame()
    ctx.hoveredWidget = nil
    ctx.hoverEditWidget = nil
    ctx.activeWidget = nil
    ctx.selectedWidget = nil
    ctx.pointerOverInspectorChrome = false
    ctx.inspectedWidgets = {}
    ctx.selectedWidgets = {}
    ctx.skipNextClickToggleWidget = nil
    ctx.multiSelect = false
    ctx.lastActiveWidget = nil
    ctx.selectionLimitPulseTime = nil
    ctx.layoutConstraintHints = {}
    ctx.inspectorPointerDownOnChrome = nil
    ctx.editPending = nil
    ctx.editState = nil
    ctx.inspectorPanelDrag = nil
    ctx.inspectorPanelResizeDrag = nil
    ctx.inspectorPanelUserResized = false
    ctx.inspectorPanelPos = nil
    ctx.pickingTipsPos = nil
    ctx.inspectorPanelUserMoved = false
    ctx.pickingTipsUserMoved = false
    ctx.inspectorViewportW = nil
    ctx.inspectorViewportH = nil
    ctx.editRecords = {}
    ctx.copiedEditRecordCount = 0
    ctx.widgetPrompts = {}
    QuickTweak.clearGroupPrompt()
    ctx.selectedPropKey = nil
    ctx.selectedPropDef = nil
    ctx.selectedPropRow = nil
    Panel.ensureNativeRoot()
    Panel.showPickingTips(selectDirtyWidgets)
    Panel.createNativePanel()

    -- Install input hooks
    ctx.uiModule.SetInspectorInputHook(function(x, y)
        if ctx.confirmOverlay and isInspectorTreeHit(x, y) then
            ctx.inspectorPointerDownOnChrome = true
            clearComponentPointerFocus()
            return false
        end
        if isInspectorTreeHit(x, y) then
            ctx.inspectorPointerDownOnChrome = true
            clearComponentPointerFocus()
            return false
        end
        ctx.inspectorPointerDownOnChrome = nil
        if Panel.hidePropContextMenu then
            Panel.hidePropContextMenu()
        end
        setPointerOutsideInspectorChrome()
        local selectableWidget = (EditTool.hitFocusButton and EditTool.hitFocusButton(x, y))
            or (EditTool.hitPinButton and EditTool.hitPinButton(x, y))
        if selectableWidget then
            setActiveWidget(selectableWidget)
            toggleWidgetSelection(selectableWidget)
            return true
        end
        local parentWidget, childWidget = nil, nil
        if EditTool.hitParentButton then
            parentWidget, childWidget = EditTool.hitParentButton(x, y)
        end
        if parentWidget then
            if isWidgetExplicitlySelected(childWidget) then
                replaceExplicitSelection(childWidget, parentWidget)
            end
            activateWidget(parentWidget)
            return true
        end
        if isCtrlDown() then
            local widget = findInspectableWidgetAt(x, y)
            if widget then
                ctx.hoverEditWidget = widget
                promoteActiveToExplicitSelection(widget)
                setActiveWidget(widget)
                toggleWidgetSelection(widget)
            else
                clearActiveWidget()
            end
            return true
        end
        local beganEdit, editWidget = EditTool.beginAt(x, y)
        if beganEdit then
            local wasActive = editWidget and (editWidget == ctx.activeWidget or editWidget == ctx.selectedWidget)
            local keepMultiSelection = editWidget
                and #ctx.selectedWidgets > 1
                and isWidgetExplicitlySelected(editWidget)
            if not keepMultiSelection then
                ctx.selectedWidgets = {}
            end
            setActiveWidget(editWidget)
            ctx.skipNextClickToggleWidget = wasActive and nil or editWidget
            Panel.updatePickingTips()
            Panel.refreshNativePanel()
            return true
        end
        -- Click in editing mode -> toggle widget selection, or clear active on blank.
        local widget = findInspectableWidgetAt(x, y)
        if widget then
            ctx.hoverEditWidget = widget
            handleSelectionClick(widget)
        else
            clearActiveWidget()
        end
        return true  -- consume event
    end)

    ctx.uiModule.SetInspectorMoveHook(function(x, y)
        if Panel.updateInspectorPanelDrag(x, y) then
            clearComponentPointerFocus()
            return true
        end
        if Panel.updatePickingTipsDrag(x, y) then
            clearComponentPointerFocus()
            return true
        end
        if EditTool.update(x, y) then
            ctx.editToolHoverTip = nil
            return true
        end
        -- Handle drag-to-adjust from Inspector numeric labels
        if ctx.dragState then
            if not canApplyNumericDragState(ctx.dragState) then
                ctx.dragState = nil
                return true
            end
            if not input:GetMouseButtonDown(MOUSEB_LEFT) then
                finishNumericDragVerification(ctx.dragState)
                ctx.dragState = nil
                if ctx.updateInspectorRestoreButtonState then
                    ctx.updateInspectorRestoreButtonState()
                end
                return true
            end
            if not ctx.dragState.startX then
                ctx.dragState.startX = x
                return true
            end
            local rawDelta = x - ctx.dragState.startX
            local step = getNumericDragStep(ctx.dragState.key, ctx.dragState.def)
            local newVal = normalizeNumericDragValue(
                ctx.dragState.key,
                ctx.dragState.def,
                ctx.dragState.startValue + rawDelta * step
            )
            if not ctx.dragState.snapshotsReady then
                QuickTweak.ensureSnapshots(ctx.inspectedWidgets or {}, { ctx.dragState.key })
                ctx.dragState.snapshotsReady = true
            end
            beginNumericDragVerification(ctx.dragState)
            for _, w in ipairs(ctx.inspectedWidgets or {}) do
                if ctx.isWidgetAlive(w) then
                    local styleTable = {}
                    if ctx.dragState.def.type == "spacing" then
                        local sides = { "Top", "Right", "Bottom", "Left" }
                        for _, side in ipairs(sides) do
                            styleTable[ctx.dragState.key .. side] = nil
                            w.props[ctx.dragState.key .. side] = nil
                        end
                    end
                    styleTable[ctx.dragState.key] = newVal
                    QuickTweak.applyTweakValue(w, styleTable)
                end
            end
            for _, field in ipairs(ctx.tweakFields) do
                if field.key == ctx.dragState.key and field.textField then
                    field.textField.props.value = tostring(newVal)
                end
            end
            QuickTweak.updateTweakFieldMarkers()
            if ctx.updateInspectorRestoreButtonState then
                ctx.updateInspectorRestoreButtonState()
            end
            return true
        end
        if isInspectorTreeHit(x, y) then
            clearComponentPointerFocus()
            return false
        end
        setPointerOutsideInspectorChrome()
        local toolKind, toolWidget = nil, nil
        if EditTool.hitToolButton then
            toolKind, toolWidget = EditTool.hitToolButton(x, y)
        end
        if toolWidget then
            ctx.editToolHoverTip = { kind = toolKind, widget = toolWidget }
            ctx.hoveredWidget = toolWidget
            ctx.hoverEditWidget = toolWidget
            return true
        end
        ctx.editToolHoverTip = nil
        local chromeWidget = EditTool.hitChromeWidget and EditTool.hitChromeWidget(x, y)
        if chromeWidget then
            ctx.hoveredWidget = chromeWidget
            ctx.hoverEditWidget = chromeWidget
            return true
        end
        local hoverWidget = findInspectableWidgetAt(x, y)
        ctx.hoveredWidget = hoverWidget
        if hoverWidget then
            ctx.hoverEditWidget = hoverWidget
        else
            ctx.hoverEditWidget = nil
        end
        return true
    end)

    if ctx.uiModule.SetInspectorPointerUpHook then
        ctx.uiModule.SetInspectorPointerUpHook(function(x, y)
            if Panel.endInspectorPanelDrag() then
                ctx.inspectorPointerDownOnChrome = nil
                return false
            end
            if Panel.endPickingTipsDrag() then
                ctx.inspectorPointerDownOnChrome = nil
                return false
            end
            if ctx.inspectorPointerDownOnChrome or (isInspectorTreeHit(x, y) and not ctx.editState and not ctx.editPending) then
                ctx.inspectorPointerDownOnChrome = nil
                clearComponentPointerFocus()
                return false
            end
            ctx.inspectorPointerDownOnChrome = nil
            local consumed, clickedWidget, edited = EditTool.endAt(x, y)
            if clickedWidget and ctx.state ~= ctx.STATE_IDLE and edited then
                ctx.skipNextClickToggleWidget = nil
                setActiveWidget(clickedWidget)
                Panel.refreshNativePanel()
            elseif clickedWidget and ctx.state ~= ctx.STATE_IDLE then
                if ctx.skipNextClickToggleWidget == clickedWidget then
                    ctx.skipNextClickToggleWidget = nil
                    return consumed
                end
                ctx.skipNextClickToggleWidget = nil
                handleSelectionClick(clickedWidget)
            end
            return consumed
        end)
    end

    ctx.uiModule.SetInspectorRenderHook(Overlay.renderInspectorOverlay)
    ctx.uiModule.EnableInspectorUpdate()

    print("[UIInspector] 编辑模式：点击控件选取/取消，Ctrl 多选，Esc 退出")
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Exit inspector and return to normal state
function UIInspector.Exit()
    -- Stop inspector update loop
    ctx.uiModule.DisableInspectorUpdate()

    -- Clean up hooks
    ctx.uiModule.SetInspectorRenderHook(nil)
    ctx.uiModule.SetInspectorInputHook(nil)
    ctx.uiModule.SetInspectorMoveHook(nil)
    if ctx.uiModule.SetInspectorPointerUpHook then
        ctx.uiModule.SetInspectorPointerUpHook(nil)
    end

    -- Destroy native panel
    Panel.destroyNativePanel()

    -- Clear state
    ctx.hoveredWidget = nil
    ctx.hoverEditWidget = nil
    ctx.editToolHoverTip = nil
    ctx.pointerOverInspectorChrome = false
    ctx.inspectorPointerDownOnChrome = nil
    ctx.activeWidget = nil
    ctx.selectedWidget = nil
    ctx.inspectedWidgets = {}
    ctx.selectedWidgets = {}
    ctx.skipNextClickToggleWidget = nil
    ctx.multiSelect = false
    ctx.lastActiveWidget = nil
    ctx.selectionLimitPulseTime = nil
    ctx.layoutConstraintHints = {}
    ctx.propsSnapshots = {}
    ctx.copiedSnapshots = nil
    ctx.tweakFields = {}
    ctx.dragState = nil
    ctx.editPending = nil
    ctx.editState = nil
    ctx.inspectorPanelDrag = nil
    ctx.inspectorPanelResizeDrag = nil
    ctx.editRecords = {}
    ctx.copiedEditRecordCount = 0
    ctx.widgetPrompts = {}
    QuickTweak.clearGroupPrompt()
    ctx.expandedPromptWidget = nil
    ctx.selectedPropKey = nil
    ctx.selectedPropDef = nil
    ctx.selectedPropRow = nil
    Panel.hideConfirmOverlay()

    -- Unfreeze
    unfreezeGame()

    ctx.state = ctx.STATE_IDLE
    print("[UIInspector] 已退出")
end

-- ============================================================================
-- Keyboard Listener
-- ============================================================================

local function setupHotkeyListener()
    if ctx.eventNode then return end

    ctx.eventNode = Node()
    ctx.eventScriptObject = ctx.eventNode:CreateScriptObject("LuaScriptObject")

    ctx.eventScriptObject:SubscribeToEvent("KeyDown", function(self, eventType, eventData)
        local key = eventData["Key"]:GetInt()

        -- Dismiss confirm overlay first
        if ctx.confirmOverlay and (key == KEY_ESCAPE or key == ctx.HOTKEY) then
            Panel.hideConfirmOverlay()
            return
        end

        if ctx.state ~= ctx.STATE_IDLE and isDeleteKey(key) and ctx.selectedPropKey and not isTextInputFocused() then
            local cleared = QuickTweak.clearPropToDefault(ctx.inspectedWidgets or {}, ctx.selectedPropKey, ctx.selectedPropDef)
            if cleared then
                QuickTweak.refreshTweakFields()
            end
            return
        end

        if ctx.state ~= ctx.STATE_IDLE and isCtrlDown() and isAKey(key) then
            selectDirtyWidgets()
            return
        end

        if key == ctx.HOTKEY then
            if ctx.state == ctx.STATE_IDLE then
                enterPicking()
            else
                Panel.tryClose()
            end
        elseif key == KEY_ESCAPE then
            if ctx.state ~= ctx.STATE_IDLE then
                Panel.tryClose()
            end
        end
    end)
end

local function teardownHotkeyListener()
    if ctx.eventNode then
        ctx.eventNode:Remove()
        ctx.eventNode = nil
        ctx.eventScriptObject = nil
    end
end

--- Initialize the UI Inspector
--- Must be called after UI.Init()
---@param uiMod table The UI module reference
---@param options table|nil { hotkey = KEY_F9 }
function UIInspector.Init(uiMod, options)
    ctx.uiModule = uiMod
    options = options or {}
    ctx.HOTKEY = options.hotkey or KEY_F9

    -- Enable source tracking globally
    UI_INSPECTOR_ENABLED = true

    -- Set up keyboard listener for hotkey
    setupHotkeyListener()

    print("[UIInspector] 已初始化（快捷键: F9）")
end

--- Shutdown the inspector, clean up resources
function UIInspector.Shutdown()
    if ctx.state ~= ctx.STATE_IDLE then
        UIInspector.Exit()
    end
    teardownHotkeyListener()
    UI_INSPECTOR_ENABLED = nil
end

--- Toggle the inspector (for programmatic use, e.g., touch devices)
function UIInspector.Toggle()
    if ctx.state == ctx.STATE_IDLE then
        enterPicking()
    else
        Panel.tryClose()
    end
end

--- Select one widget as the current inspector target.
function UIInspector.SelectWidget(widget, replace)
    if not ctx.isWidgetAlive(widget) then return end
    if replace ~= false then
        ctx.selectedWidgets = {}
    end
    setActiveWidget(widget)
    Panel.updatePickingTips()
    Panel.refreshNativePanel()
end

--- Replace the current selection with the given widgets.
function UIInspector.SelectWidgets(widgets)
    selectWidgets(widgets or {}, true)
end

function UIInspector.IsWidgetPinned(widget)
    return isWidgetExplicitlySelected(widget)
end

function UIInspector.IsWidgetFocused(widget)
    return isWidgetExplicitlySelected(widget)
end

function UIInspector.IsWidgetSelected(widget)
    return isWidgetExplicitlySelected(widget)
end

--- Enable or disable explicit multi-select mode.
--- Kept for compatibility; visible UI uses the target button and Ctrl-click instead.
function UIInspector.SetMultiSelect(enabled)
    ctx.multiSelect = enabled and true or false
    if not ctx.multiSelect and #ctx.selectedWidgets > 1 then
        ctx.selectedWidgets = {}
        syncInspectedWidgets()
    end
    if not ctx.multiSelect then
        QuickTweak.clearGroupPrompt()
    end
    Panel.updatePickingTips()
    Panel.refreshNativePanel()
end

function UIInspector.ToggleMultiSelect()
    UIInspector.SetMultiSelect(not ctx.multiSelect)
end

--- Select all dirty widgets in this editor session.
function UIInspector.SelectDirtyWidgets()
    local dirty = QuickTweak.getDirtyWidgets and QuickTweak.getDirtyWidgets() or {}
    if #dirty == 0 then
        Panel.showResultToast(_tr("t_F3Dyg7cTFTnsRgJ9"))
        return
    end
    selectWidgets(dirty, true)
end

--- Check if inspector is currently active
---@return boolean
function UIInspector.IsActive()
    return ctx.state ~= ctx.STATE_IDLE
end

--- Get current state
---@return string "idle"|"editing"
function UIInspector.GetState()
    return ctx.state
end

return UIInspector
