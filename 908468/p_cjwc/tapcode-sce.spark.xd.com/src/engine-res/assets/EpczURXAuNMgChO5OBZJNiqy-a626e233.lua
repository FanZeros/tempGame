-- ============================================================================
-- UIInspector - QuickTweak Module
-- Property editing, snapshot/restore, drag-to-adjust
-- ============================================================================

return function(ctx)

local M = {}
local Schema = ctx.Schema
local isWidgetAlive = ctx.isWidgetAlive
local valuesEqual = ctx.valuesEqual
local deepCopyValue = ctx.deepCopyValue

local function getInspectedWidgets()
    return ctx.inspectedWidgets or {}
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function getWidgetGroupSignature(widgets)
    local parts = {}
    local aliveWidgets = {}
    for _, widget in ipairs(widgets or {}) do
        if isWidgetAlive(widget) then
            parts[#parts + 1] = tostring(widget)
            aliveWidgets[#aliveWidgets + 1] = widget
        end
    end
    table.sort(parts)
    return table.concat(parts, "|"), aliveWidgets
end

local function makeWidgetSet(widgets)
    local set = {}
    local count = 0
    for _, widget in ipairs(widgets or {}) do
        if isWidgetAlive(widget) and not set[widget] then
            set[widget] = true
            count = count + 1
        end
    end
    return set, count
end

function M.getGroupPromptSignature(widgets)
    local signature = getWidgetGroupSignature(widgets)
    return signature
end

function M.clearGroupPrompt()
    ctx.groupPrompt = ""
    ctx.groupPromptSignature = nil
    ctx.groupPromptWidgets = nil
end

function M.setGroupPromptForWidgets(widgets, value)
    value = trim(value)
    local signature, aliveWidgets = getWidgetGroupSignature(widgets)
    if value == "" then
        if signature ~= "" and signature == ctx.groupPromptSignature then
            M.clearGroupPrompt()
        end
        return
    end

    if #aliveWidgets <= 1 then
        return
    end

    ctx.groupPrompt = value
    ctx.groupPromptSignature = signature
    ctx.groupPromptWidgets = aliveWidgets
end

function M.getGroupPromptForWidgets(widgets)
    if trim(ctx.groupPrompt) == "" then return "" end
    local signature = getWidgetGroupSignature(widgets)
    if signature == "" or signature ~= ctx.groupPromptSignature then return "" end
    return ctx.groupPrompt
end

function M.getGroupPromptEntryForWidgets(widgets)
    local prompt = trim(ctx.groupPrompt)
    if prompt == "" then return nil end

    local groupWidgets = M.getGroupPromptWidgets()
    if #groupWidgets <= 1 then return nil end

    local selectedSet, selectedCount = makeWidgetSet(widgets)
    if selectedCount == 0 then return nil end
    for _, widget in ipairs(groupWidgets) do
        if not selectedSet[widget] then
            return nil
        end
    end

    local signature = getWidgetGroupSignature(widgets)
    return {
        prompt = prompt,
        widgets = groupWidgets,
        exact = signature == ctx.groupPromptSignature,
    }
end

function M.hasSelectionGroupPrompt(widgets)
    return M.getGroupPromptEntryForWidgets(widgets) ~= nil
end

function M.clearGroupPromptForWidgets(widgets)
    if M.getGroupPromptEntryForWidgets(widgets) then
        M.clearGroupPrompt()
    end
end

function M.getGroupPromptWidgets()
    if trim(ctx.groupPrompt) == "" then return {} end
    local widgets = {}
    for _, widget in ipairs(ctx.groupPromptWidgets or {}) do
        if isWidgetAlive(widget) then
            widgets[#widgets + 1] = widget
        end
    end
    return widgets
end

local function colorValueToHex(value)
    local parsed = value
    if type(value) == "string" then
        parsed = ctx.Style.ParseColor(value)
    end
    if type(parsed) ~= "table" then
        return "#FFFFFFFF"
    end
    return string.format("#%02X%02X%02X%02X",
        parsed[1] or parsed.r or 0,
        parsed[2] or parsed.g or 0,
        parsed[3] or parsed.b or 0,
        parsed[4] or parsed.a or 255)
end

local function getColorStatusText(same, valueText)
    if not same then return _tr("t_1HmLUkPrh1HKrUJA0V") end
    if valueText == nil or valueText == "" then return _tr("t_K1KIgS7eKRyqgDtU") end
    return ""
end

local function ensureDropdownOption(dropdown, value)
    if not dropdown or value == nil or value == "" then return end
    for _, option in ipairs(dropdown.props.options or {}) do
        if option.value == value then return end
    end
    dropdown.props.options = dropdown.props.options or {}
    dropdown.props.options[#dropdown.props.options + 1] = {
        value = value,
        label = _tr("t_3BFMoQph3bpHEclP", tostring(value)),
    }
end

-- ============================================================================
-- Editable Property Keys
-- ============================================================================

--- Get the list of editable property keys for a set of widgets (intersection)
function M.getEditableProps(widgets)
    if #widgets == 0 then return {} end
    if ctx.getEditablePropsForWidgets then
        local schemaKeys = ctx.getEditablePropsForWidgets(widgets)
        if schemaKeys and #schemaKeys > 0 then
            return schemaKeys
        end
    end
    return {}
end

-- ============================================================================
-- Parse Input
-- ============================================================================

--- Parse user input text into a property value
--- Returns value, success
function M.parsePropInput(key, text, def)
    def = def or Schema.getPropDef(key)
    if not def then return nil, false end

    text = text:match("^%s*(.-)%s*$") or text  -- trim

    if def.type == "string" then
        return ctx.unescapeStringFromInput(text), true

    elseif def.type == "path" or def.type == "enum" then
        return text, true

    elseif def.type == "number" then
        local n = tonumber(text)
        if not n then return nil, false end
        return n, true

    elseif def.type == "boolean" then
        local lowered = tostring(text):lower()
        if lowered == "true" or lowered == "1" or lowered == "yes" then return true, true end
        if lowered == "false" or lowered == "0" or lowered == "no" then return false, true end
        return nil, false

    elseif def.type == "layout" then
        if text == "" or text == "auto" then return nil, true end
        local n = tonumber(text)
        if n then return n, true end
        if text:match("^%-?[%d%.]+%%$") then return text, true end
        return text, true

    elseif def.type == "color" then
        if text == "" then return nil, true end  -- clear color
        local c = ctx.Style.ParseColor(text)
        if not c then return nil, false end
        return c, true

    elseif def.type == "spacing" then
        if text == "" then return 0, true end
        -- Single number
        local n = tonumber(text)
        if n then return n, true end
        -- Multi-value: "T R B L" or "V H"
        local parts = {}
        for num in text:gmatch("[%d%.]+") do
            parts[#parts + 1] = tonumber(num)
        end
        if #parts == 0 then return nil, false end
        if #parts == 1 then return parts[1], true end
        if #parts == 2 then return { parts[1], parts[2], parts[1], parts[2] }, true end
        if #parts == 3 then return { parts[1], parts[2], parts[3], parts[2] }, true end
        return { parts[1], parts[2], parts[3], parts[4] }, true
    end

    return nil, false
end

-- ============================================================================
-- Snapshot & Restore
-- ============================================================================

local function containsKey(keys, key)
    for _, k in ipairs(keys) do
        if k == key then return true end
    end
    return false
end

local function addSnapshotKey(entry, key)
    if containsKey(entry.keys, key) then return end
    entry.keys[#entry.keys + 1] = key
    entry.snapshot[key] = deepCopyValue(entry.widget.props[key])
    -- Preserve intrinsic sizing: its numeric width alone is not the full state.
    if key == "width" and entry.widget.autoWidth_ == true then
        entry.autoWidthKeys = entry.autoWidthKeys or {}
        entry.autoWidthKeys[key] = true
    end
end

local function snapshotKeyChanged(entry, key)
    if not valuesEqual(entry.snapshot[key], entry.widget.props[key]) then
        return true
    end
    return entry.autoWidthKeys and entry.autoWidthKeys[key]
        and entry.widget.autoWidth_ ~= true
end

local function findSnapshotEntry(widget)
    for _, entry in ipairs(ctx.propsSnapshots) do
        if entry.widget == widget then return entry end
    end
    return nil
end

local function removeSnapshotEntry(list, widget)
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].widget == widget then
            table.remove(list, i)
        end
    end
end

local function clearYogaValue(widget, key)
    if not widget.node then return end
    if key == "width" and widget.SetWidthAuto then
        widget:SetWidthAuto()
    elseif key == "width" and YGNodeStyleSetWidthAuto then
        YGNodeStyleSetWidthAuto(widget.node)
    elseif key == "height" and widget.SetHeightAuto then
        widget:SetHeightAuto()
    elseif key == "height" and YGNodeStyleSetHeightAuto then
        YGNodeStyleSetHeightAuto(widget.node)
    elseif key == "flexBasis" and YGNodeStyleSetFlexBasisAuto then
        YGNodeStyleSetFlexBasisAuto(widget.node)
    elseif key == "aspectRatio" and YGNodeStyleSetAspectRatio then
        YGNodeStyleSetAspectRatio(widget.node, YGUndefined)
    elseif key == "flexGrow" and YGNodeStyleSetFlexGrow then
        YGNodeStyleSetFlexGrow(widget.node, 0)
    elseif key == "flexShrink" and YGNodeStyleSetFlexShrink then
        YGNodeStyleSetFlexShrink(widget.node, 0)
    elseif key == "alignSelf" and YGNodeStyleSetAlignSelf then
        YGNodeStyleSetAlignSelf(widget.node, ctx.Style.AlignSelfToYoga("auto"))
    elseif key == "position" and YGNodeStyleSetPositionType then
        YGNodeStyleSetPositionType(widget.node, ctx.Style.PositionTypeToYoga("relative"))
    elseif key == "left" and YGNodeStyleSetPosition then
        YGNodeStyleSetPosition(widget.node, YGEdgeLeft, YGUndefined)
    elseif key == "top" and YGNodeStyleSetPosition then
        YGNodeStyleSetPosition(widget.node, YGEdgeTop, YGUndefined)
    elseif key == "right" and YGNodeStyleSetPosition then
        YGNodeStyleSetPosition(widget.node, YGEdgeRight, YGUndefined)
    elseif key == "bottom" and YGNodeStyleSetPosition then
        YGNodeStyleSetPosition(widget.node, YGEdgeBottom, YGUndefined)
    elseif key == "marginLeft" and YGNodeStyleSetMargin then
        YGNodeStyleSetMargin(widget.node, YGEdgeLeft, YGUndefined)
    elseif key == "marginTop" and YGNodeStyleSetMargin then
        YGNodeStyleSetMargin(widget.node, YGEdgeTop, YGUndefined)
    elseif key == "marginRight" and YGNodeStyleSetMargin then
        YGNodeStyleSetMargin(widget.node, YGEdgeRight, YGUndefined)
    elseif key == "marginBottom" and YGNodeStyleSetMargin then
        YGNodeStyleSetMargin(widget.node, YGEdgeBottom, YGUndefined)
    elseif key == "paddingLeft" and YGNodeStyleSetPadding then
        YGNodeStyleSetPadding(widget.node, YGEdgeLeft, 0)
    elseif key == "paddingTop" and YGNodeStyleSetPadding then
        YGNodeStyleSetPadding(widget.node, YGEdgeTop, 0)
    elseif key == "paddingRight" and YGNodeStyleSetPadding then
        YGNodeStyleSetPadding(widget.node, YGEdgeRight, 0)
    elseif key == "paddingBottom" and YGNodeStyleSetPadding then
        YGNodeStyleSetPadding(widget.node, YGEdgeBottom, 0)
    elseif key == "gap" and YGNodeStyleSetGap then
        YGNodeStyleSetGap(widget.node, YGGutterAll, 0)
    elseif key == "rowGap" and YGNodeStyleSetGap then
        YGNodeStyleSetGap(widget.node, YGGutterRow, 0)
    elseif key == "columnGap" and YGNodeStyleSetGap then
        YGNodeStyleSetGap(widget.node, YGGutterColumn, 0)
    end
end

local function restoreSnapshotEntry(entry)
    local w = entry.widget
    if not isWidgetAlive(w) then return end
    M.restoreWidgetProps(w, entry.snapshot, entry.keys, entry.autoWidthKeys)
end

--- Restore specific props on one widget, including nil values that need Yoga clearing.
function M.restoreWidgetProps(widget, props, keys, autoWidthKeys)
    if not isWidgetAlive(widget) then return false end

    local styleTable = {}
    local changed = false
    local restoreAutoWidth = false
    for _, key in ipairs(keys) do
        local value = props[key]
        local valueChanged = not valuesEqual(value, widget.props[key])
        local modeChanged = autoWidthKeys and autoWidthKeys[key]
            and widget.autoWidth_ ~= true
        if valueChanged or modeChanged then
            changed = true
            if autoWidthKeys and autoWidthKeys[key] and widget.SetWidthAuto then
                restoreAutoWidth = true
            else
                widget.props[key] = deepCopyValue(value)
                if value ~= nil then
                    styleTable[key] = deepCopyValue(value)
                else
                    clearYogaValue(widget, key)
                end
            end
        end
    end

    if changed then
        M.applyTweakValue(widget, styleTable)
        if restoreAutoWidth then
            widget:SetWidthAuto()
        end
    end
    return changed
end

--- Take snapshots of current values for all widgets x keys
function M.takeSnapshots(widgets, keys)
    ctx.propsSnapshots = {}
    M.ensureSnapshots(widgets, keys)
end

--- Ensure snapshots exist without overwriting earlier baselines.
--- Used when selection-box edits happen before the panel is opened.
function M.ensureSnapshots(widgets, keys)
    for _, w in ipairs(widgets) do
        local entry = findSnapshotEntry(w)
        if not entry then
            entry = { widget = w, snapshot = {}, keys = {} }
            ctx.propsSnapshots[#ctx.propsSnapshots + 1] = entry
        end
        for _, k in ipairs(keys) do
            addSnapshotKey(entry, k)
            -- Also snapshot per-side spacing overrides
            local kDef = Schema.getWidgetPropDef(k, w)
            if kDef and kDef.type == "spacing" then
                local sides = { "Top", "Right", "Bottom", "Left" }
                for _, side in ipairs(sides) do
                    local sk = k .. side
                    addSnapshotKey(entry, sk)
                end
            end
        end
    end
end

--- Apply a style table to widget, suppressing transitions
function M.applyTweakValue(widget, styleTable)
    local keys = {}
    for key in pairs(styleTable or {}) do
        keys[#keys + 1] = key
    end
    if #keys > 0 then
        M.ensureSnapshots({ widget }, keys)
    end

    local saved = widget.transitionConfig_
    widget.transitionConfig_ = nil
    widget:SetStyle(styleTable)
    widget.transitionConfig_ = saved
end

local function getMainAxis(widget)
    local parent = widget and widget.parent
    local direction = parent and parent.props and parent.props.flexDirection
    if direction == "row" or direction == "row-reverse" then
        return "x"
    end
    return "y"
end

local function getLayoutAxisForKey(widget, key)
    if key == "left" or key == "right" or key == "marginLeft" or key == "marginRight" then
        return "x"
    elseif key == "top" or key == "bottom" or key == "marginTop" or key == "marginBottom" then
        return "y"
    elseif key == "width" then
        return "w"
    elseif key == "height" then
        return "h"
    elseif key == "flexBasis" then
        return getMainAxis(widget) == "x" and "w" or "h"
    end
    return nil
end

local function rectAxisChanged(beforeRect, afterRect, axis)
    if not beforeRect or not afterRect or not axis then return true end
    return math.abs((beforeRect[axis] or 0) - (afterRect[axis] or 0)) > 0.5
end

local function copyRect(rect)
    if not rect then return nil end
    return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

local function addLayoutConstraintDirection(directions, direction, amount)
    if direction and amount and amount > 0.5 then
        directions[direction] = math.max(directions[direction] or 0, amount)
    end
end

function M.getLayoutConstraintDirectionsFromRects(desired, actual)
    local directions = {}
    if not desired or not actual then return nil end

    addLayoutConstraintDirection(directions, "left", actual.x - desired.x)
    addLayoutConstraintDirection(directions, "right", desired.x + desired.w - (actual.x + actual.w))
    addLayoutConstraintDirection(directions, "up", actual.y - desired.y)
    addLayoutConstraintDirection(directions, "down", desired.y + desired.h - (actual.y + actual.h))

    if directions.left or directions.right or directions.up or directions.down then
        return directions
    end
    return nil
end

local function copyConstraintDirections(info)
    if type(info) ~= "table" then return nil end
    local directions = {}
    if info.left then directions.left = info.left end
    if info.right then directions.right = info.right end
    if info.up then directions.up = info.up end
    if info.down then directions.down = info.down end

    if directions.left or directions.right or directions.up or directions.down then
        return directions
    end
    return nil
end

M.CONSTRAINT_VISIBLE_THRESHOLD = 10
local CONSTRAINT_DIRECTIONS = { "left", "right", "up", "down" }

local function constraintDirectionVisible(value)
    if type(value) == "number" then return value >= M.CONSTRAINT_VISIBLE_THRESHOLD end
    return value ~= nil and value ~= false
end

local function updateConstraintShakes(hint, nextDirections, now)
    local previousDirections = hint.directions or {}
    hint.shakes = hint.shakes or {}
    local started = false
    for _, direction in ipairs(CONSTRAINT_DIRECTIONS) do
        if constraintDirectionVisible(nextDirections and nextDirections[direction])
            and not constraintDirectionVisible(previousDirections[direction]) then
            hint.shakes[direction] = now
            started = true
        end
    end
    return started
end

function M.showLayoutConstraintHint(widget, directionInfo, options)
    if not isWidgetAlive(widget) then return end

    options = options or {}
    local directions = copyConstraintDirections(directionInfo)
    if not directions then return end

    ctx.layoutConstraintHints = ctx.layoutConstraintHints or {}
    local now = ctx.nowSeconds()
    local duration = options.duration or 1
    local expiresAt = options.persistent and math.huge or (now + duration)
    for _, hint in ipairs(ctx.layoutConstraintHints) do
        if hint.widget == widget then
            if not hint.keepUntilClear and hint.expiresAt and hint.expiresAt <= now then
                hint.directions = nil
                hint.shakes = nil
            end
            local started = updateConstraintShakes(hint, directions, now)
            hint.directions = directions
            hint.startedAt = now
            hint.persistent = options.persistent == true
            hint.keepUntilClear = options.keepUntilClear == true
            if options.refreshExpires == false and not started then
                hint.expiresAt = hint.expiresAt or expiresAt
            else
                hint.expiresAt = expiresAt
            end
            return
        end
    end
    local hint = {
        widget = widget,
        startedAt = now,
        persistent = options.persistent == true,
        keepUntilClear = options.keepUntilClear == true,
        expiresAt = expiresAt,
    }
    updateConstraintShakes(hint, directions, now)
    hint.directions = directions
    ctx.layoutConstraintHints[#ctx.layoutConstraintHints + 1] = hint
end

function M.clearLayoutConstraintHint(widget)
    local hints = ctx.layoutConstraintHints
    if not hints then return end
    for i = #hints, 1, -1 do
        if hints[i].widget == widget then
            table.remove(hints, i)
        end
    end
end

local function getDesiredLayoutRectForKeys(widget, keys, beforeProps, beforeRect)
    local desired = copyRect(beforeRect)
    if not desired then return nil end

    for _, key in ipairs(keys or {}) do
        local beforeValue = beforeProps and beforeProps[key]
        local beforeNumber = tonumber(beforeValue) or 0
        local afterNumber = tonumber(widget.props[key])
        local delta = afterNumber and (afterNumber - beforeNumber) or nil

        if not delta then
            -- Keep walking other keys.
        elseif key == "left" or key == "marginLeft" then
            desired.x = desired.x + delta
        elseif key == "right" or key == "marginRight" then
            desired.x = desired.x - delta
        elseif key == "top" or key == "marginTop" then
            desired.y = desired.y + delta
        elseif key == "bottom" or key == "marginBottom" then
            desired.y = desired.y - delta
        elseif key == "width" then
            desired.w = math.max(0, afterNumber)
        elseif key == "height" then
            desired.h = math.max(0, afterNumber)
        elseif key == "flexBasis" then
            if getMainAxis(widget) == "x" then
                desired.w = math.max(0, afterNumber)
            else
                desired.h = math.max(0, afterNumber)
            end
        end
    end

    return desired
end

function M.showLayoutConstraintHintForKeys(widget, keys, beforeProps, beforeRect, actualRect)
    local desired = getDesiredLayoutRectForKeys(widget, keys, beforeProps, beforeRect)
    local directions = M.getLayoutConstraintDirectionsFromRects(desired, actualRect)
    if directions then
        M.showLayoutConstraintHint(widget, directions, {
            duration = 0.75,
        })
    end
end

function M.verifyAppliedLayoutEffect(widget, beforeProps, beforeRect, keys)
    if not isWidgetAlive(widget) then
        return { changed = false, rolledBack = false, rollbackKeys = {} }
    end

    beforeProps = beforeProps or {}
    keys = keys or {}

    if ctx.uiModule and ctx.uiModule.Layout then
        ctx.uiModule.Layout()
    end
    local afterRect = ctx.getWidgetScreenRect and ctx.getWidgetScreenRect(widget) or nil

    local rollbackKeys = {}
    for _, key in ipairs(keys) do
        local axis = getLayoutAxisForKey(widget, key)
        if axis and not valuesEqual(beforeProps[key], widget.props[key]) and not rectAxisChanged(beforeRect, afterRect, axis) then
            rollbackKeys[#rollbackKeys + 1] = key
        end
    end

    if #rollbackKeys > 0 then
        M.showLayoutConstraintHintForKeys(widget, rollbackKeys, beforeProps, beforeRect, afterRect)
        M.restoreWidgetProps(widget, beforeProps, rollbackKeys)
        if ctx.uiModule and ctx.uiModule.Layout then
            ctx.uiModule.Layout()
        end
    end

    return {
        changed = #rollbackKeys < #keys,
        rolledBack = #rollbackKeys > 0,
        rollbackKeys = rollbackKeys,
    }
end

function M.verifyAppliedLayoutEffects(entries)
    entries = entries or {}
    if #entries == 0 then
        return { rolledBack = false }
    end

    if ctx.uiModule and ctx.uiModule.Layout then
        ctx.uiModule.Layout()
    end

    local rolledBack = false
    for _, entry in ipairs(entries) do
        local widget = entry.widget
        if isWidgetAlive(widget) then
            local beforeProps = entry.beforeProps or {}
            local beforeRect = entry.beforeRect
            local keys = entry.keys or {}
            local afterRect = ctx.getWidgetScreenRect and ctx.getWidgetScreenRect(widget) or nil
            local rollbackKeys = {}

            for _, key in ipairs(keys) do
                local axis = getLayoutAxisForKey(widget, key)
                if axis and not valuesEqual(beforeProps[key], widget.props[key]) and not rectAxisChanged(beforeRect, afterRect, axis) then
                    rollbackKeys[#rollbackKeys + 1] = key
                end
            end

            if #rollbackKeys > 0 then
                M.showLayoutConstraintHintForKeys(widget, rollbackKeys, beforeProps, beforeRect, afterRect)
                M.restoreWidgetProps(widget, beforeProps, rollbackKeys)
                rolledBack = true
            end
        end
    end

    if rolledBack and ctx.uiModule and ctx.uiModule.Layout then
        ctx.uiModule.Layout()
    end

    return { rolledBack = rolledBack }
end

function M.applyVerifiedTweakValue(widget, styleTable)
    if not isWidgetAlive(widget) then
        return { touched = false, changed = false, rolledBack = false }
    end

    styleTable = styleTable or {}
    local keys = {}
    local beforeProps = {}
    for key in pairs(styleTable) do
        keys[#keys + 1] = key
        beforeProps[key] = deepCopyValue(widget.props[key])
    end

    local beforeRect = ctx.getWidgetScreenRect and ctx.getWidgetScreenRect(widget) or nil
    M.applyTweakValue(widget, styleTable)
    local verified = M.verifyAppliedLayoutEffect(widget, beforeProps, beforeRect, keys)

    return {
        touched = #keys > 0,
        changed = verified.changed,
        rolledBack = verified.rolledBack,
        rollbackKeys = verified.rollbackKeys,
    }
end

local function getClearPropKeys(key, def)
    local keys = { key }
    def = def or Schema.getPropDef(key)
    if def and def.type == "spacing" then
        local sides = { "Top", "Right", "Bottom", "Left" }
        for _, side in ipairs(sides) do
            keys[#keys + 1] = key .. side
        end
    end
    return keys
end

--- Clear a prop back to its implicit/default value by removing explicit props.
function M.clearPropToDefault(widgets, key, def)
    if not key then return false end
    widgets = widgets or getInspectedWidgets()
    if #widgets == 0 then return false end

    local keys = getClearPropKeys(key, def)
    M.ensureSnapshots(widgets, keys)

    local changed = false
    for _, widget in ipairs(widgets) do
        if isWidgetAlive(widget) then
            local widgetChanged = false
            for _, clearKey in ipairs(keys) do
                if widget.props[clearKey] ~= nil then
                    widget.props[clearKey] = nil
                    widgetChanged = true
                    changed = true
                end
                clearYogaValue(widget, clearKey)
            end
            if widgetChanged then
                M.applyTweakValue(widget, {})
            end
        end
    end

    return changed
end

--- Restore all widgets to their snapshotted values
function M.restoreSnapshots()
    for _, entry in ipairs(ctx.propsSnapshots) do
        restoreSnapshotEntry(entry)
    end
    ctx.propsSnapshots = {}
    ctx.copiedSnapshots = nil
    ctx.editRecords = {}
    ctx.copiedEditRecordCount = 0
end

--- Get temporary edit state for one widget.
function M.getWidgetChangeState(widget)
    local state = {
        hasRuntimeChange = false,
        hasEditIntent = false,
    }

    local entry = findSnapshotEntry(widget)
    if entry and isWidgetAlive(widget) then
        for _, k in ipairs(entry.keys) do
            if snapshotKeyChanged(entry, k) then
                state.hasRuntimeChange = true
                break
            end
        end
    end
    for _, record in ipairs(ctx.editRecords or {}) do
        if record.widget == widget and record.changed then
            state.hasEditIntent = true
            if not record.desiredOnly then
                state.hasRuntimeChange = true
            end
        end
    end
    state.hasAnyChange = state.hasRuntimeChange or state.hasEditIntent
    state.hasIntentOnly = state.hasEditIntent and not state.hasRuntimeChange
    return state
end

--- Check whether a specific widget has temporary edits or edit intent.
function M.hasWidgetRuntimeChanges(widget)
    return M.getWidgetChangeState(widget).hasAnyChange
end

--- Check whether a widget has anything that can be reverted from the inspector.
function M.hasWidgetRestorableChanges(widget)
    if not isWidgetAlive(widget) then return false end
    if M.getWidgetChangeState(widget).hasAnyChange then return true end

    local prompt = ctx.widgetPrompts and ctx.widgetPrompts[widget]
    return prompt ~= nil and prompt ~= ""
end

--- Check whether any widget in a selection can be reverted.
function M.hasSelectionRestorableChanges(widgets)
    if M.hasSelectionGroupPrompt(widgets) then
        return true
    end
    for _, widget in ipairs(widgets or {}) do
        if M.hasWidgetRestorableChanges(widget) then
            return true
        end
    end
    return false
end

--- Restore one widget and remove its temporary edit bookkeeping.
function M.restoreWidgetSnapshot(widget)
    local entry = findSnapshotEntry(widget)
    if entry then
        restoreSnapshotEntry(entry)
    end
    removeSnapshotEntry(ctx.propsSnapshots, widget)
    removeSnapshotEntry(ctx.copiedSnapshots, widget)
    for i = #(ctx.editRecords or {}), 1, -1 do
        if ctx.editRecords[i].widget == widget then
            table.remove(ctx.editRecords, i)
        end
    end
    ctx.copiedEditRecordCount = math.min(ctx.copiedEditRecordCount or 0, #(ctx.editRecords or {}))
    if ctx.widgetPrompts then
        ctx.widgetPrompts[widget] = nil
    end
end

--- Restore all tracked changes for a widget list.
function M.restoreWidgetSnapshots(widgets)
    for _, widget in ipairs(widgets or {}) do
        M.restoreWidgetSnapshot(widget)
    end
    M.clearGroupPromptForWidgets(widgets)
end

-- ============================================================================
-- Consensus & Field Management
-- ============================================================================

--- Check if all selected widgets have the same value for a property
--- Returns isSame, displayValue
function M.getConsensusValue(key)
    local widgets = getInspectedWidgets()
    if #widgets == 0 then return true, "" end
    local first = widgets[1]
    if not isWidgetAlive(first) then return true, "" end
    local firstVal = first.props[key]
    for i = 2, #widgets do
        local w = widgets[i]
        if isWidgetAlive(w) and not valuesEqual(firstVal, w.props[key]) then
            return false, nil
        end
    end
    return true, ctx.formatPropValue(first, key)
end

--- Check if all selected widgets have the same raw value for a property.
function M.getConsensusRawValue(key)
    local widgets = getInspectedWidgets()
    if #widgets == 0 then return true, nil end
    local first = widgets[1]
    if not isWidgetAlive(first) then return true, nil end
    local firstVal = first.props[key]
    for i = 2, #widgets do
        local w = widgets[i]
        if isWidgetAlive(w) and not valuesEqual(firstVal, w.props[key]) then
            return false, nil
        end
    end
    return true, firstVal
end

--- Update tweak field label colors to show modified state
function M.updateTweakFieldMarkers()
    local inspectedSet = {}
    for _, widget in ipairs(getInspectedWidgets()) do
        inspectedSet[widget] = true
    end

    local function fieldKeyModified(entry, field)
        if not entry or not inspectedSet[entry.widget] then return false end

        local key = field.key
        local def = field.def or Schema.getWidgetPropDef(key, entry.widget)
        local hasTrackedKey = containsKey(entry.keys, key)
        if hasTrackedKey and snapshotKeyChanged(entry, key) then
            return true
        end

        if def and def.type == "spacing" then
            local sides = { "Top", "Right", "Bottom", "Left" }
            for _, side in ipairs(sides) do
                local sideKey = key .. side
                if containsKey(entry.keys, sideKey)
                    and not valuesEqual(entry.snapshot[sideKey], entry.widget.props[sideKey]) then
                    return true
                end
            end
        end

        return false
    end

    for _, field in ipairs(ctx.tweakFields) do
        local modified = false
        for _, entry in ipairs(ctx.propsSnapshots) do
            if fieldKeyModified(entry, field) then
                modified = true
                break
            end
        end
        if field.label then
            local labelColor = modified and ctx.TWEAK_LABEL_MODIFIED or ctx.TWEAK_LABEL_NORMAL
            if field.label.SetFontColor then
                field.label:SetFontColor(labelColor)
            else
                field.label.fontColor = labelColor
            end
        end
    end
end

--- Refresh all TextField fields with current widget values
function M.refreshTweakFields()
    if #getInspectedWidgets() == 0 then return end
    for _, field in ipairs(ctx.tweakFields) do
        local same, val = M.getConsensusValue(field.key)
        if field.textField then
            field.textField.props.value = same and (val or "") or ""
        elseif field.colorPicker then
            field.colorPicker:SetHex(same and colorValueToHex(val) or "#FFFFFFFF")
            if field.colorStatusLabel then
                local statusText = getColorStatusText(same, val)
                field.colorStatusLabel:SetText(statusText)
                field.colorStatusLabel:SetStyle({ width = statusText ~= "" and 42 or 0 })
            end
        elseif field.dropdown then
            local rawSame, rawVal = M.getConsensusRawValue(field.key)
            ensureDropdownOption(field.dropdown, rawSame and rawVal or nil)
            field.dropdown.props.value = rawSame and rawVal or nil
            field.dropdown.props.placeholder = rawSame and _tr("t_K1KIgS7eKRyqgDtU") or _tr("t_1HmLUkPrh1HKrUJA0V")
        end
    end
    M.updateTweakFieldMarkers()
    if ctx.updateInspectorRestoreButtonState then
        ctx.updateInspectorRestoreButtonState()
    end
end

-- ============================================================================
-- Modification Tracking
-- ============================================================================

--- Check if there are modifications since the last copy (or since snapshot if never copied)
function M.hasTweakModifications()
    if #(ctx.editRecords or {}) > 0 then
        return true
    end

    for _, entry in ipairs(ctx.propsSnapshots) do
        if isWidgetAlive(entry.widget) then
            for _, k in ipairs(entry.keys) do
                if snapshotKeyChanged(entry, k) then
                    return true
                end
            end
        end
    end
    if #M.getGroupPromptWidgets() > 0 then
        return true
    end
    for widget, prompt in pairs(ctx.widgetPrompts or {}) do
        if prompt ~= "" and isWidgetAlive(widget) then
            return true
        end
    end
    return false
end

--- Return widgets with runtime edits or AI prompts.
function M.getDirtyWidgets()
    local byWidget = {}
    local ordered = {}

    local function add(widget)
        if isWidgetAlive(widget) and not byWidget[widget] then
            byWidget[widget] = true
            ordered[#ordered + 1] = widget
        end
    end

    for _, entry in ipairs(ctx.propsSnapshots or {}) do
        if isWidgetAlive(entry.widget) then
            for _, k in ipairs(entry.keys) do
                if snapshotKeyChanged(entry, k) then
                    add(entry.widget)
                    break
                end
            end
        end
    end

    for _, record in ipairs(ctx.editRecords or {}) do
        if record.changed then add(record.widget) end
    end

    local groupPromptWidgets = M.getGroupPromptWidgets()
    if #groupPromptWidgets > 0 then
        for _, widget in ipairs(groupPromptWidgets) do
            add(widget)
        end
    end

    for widget, prompt in pairs(ctx.widgetPrompts or {}) do
        if prompt ~= "" then add(widget) end
    end

    return ordered
end

--- Take a snapshot of current state (for "modified since last copy" tracking)
function M.takeCopiedSnapshot()
    ctx.copiedEditRecordCount = #(ctx.editRecords or {})
    ctx.copiedSnapshots = {}
    for _, entry in ipairs(ctx.propsSnapshots) do
        local snap = {}
        for _, k in ipairs(entry.keys) do
            snap[k] = deepCopyValue(entry.widget.props[k])
        end
        ctx.copiedSnapshots[#ctx.copiedSnapshots + 1] = {
            widget = entry.widget,
            keys = entry.keys,
            snapshot = snap,
        }
    end
end

--- Get current numeric value for drag-to-adjust
function M.getCurrentNumericValue(key, def)
    local widgets = getInspectedWidgets()
    if #widgets == 0 then return 0 end
    local w = widgets[1]
    if not isWidgetAlive(w) then return 0 end
    local v = w.props[key]
    if def.type == "number" or def.type == "layout" then
        return tonumber(v) or 0
    elseif def.type == "spacing" then
        if type(v) == "number" then return v end
        if type(v) == "table" and #v > 0 then return v[1] end
        return 0
    end
    return 0
end

local function getRestorePropKeys(key, def)
    local restoreKeys = { key }
    def = def or Schema.getPropDef(key)
    if def and def.type == "spacing" then
        local sides = { "Top", "Right", "Bottom", "Left" }
        for _, side in ipairs(sides) do
            restoreKeys[#restoreKeys + 1] = key .. side
        end
    end
    return restoreKeys
end

function M.hasSelectedPropChange(key, def)
    local restoreKeys = getRestorePropKeys(key, def)
    for _, entry in ipairs(ctx.propsSnapshots or {}) do
        if isWidgetAlive(entry.widget) then
            local selected = false
            for _, w in ipairs(getInspectedWidgets()) do
                if w == entry.widget then
                    selected = true
                    break
                end
            end
            if selected and containsKey(entry.keys, key) then
                for _, restoreKey in ipairs(restoreKeys) do
                    if snapshotKeyChanged(entry, restoreKey) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Restore a single property for the current selection.
function M.restoreSelectedProp(key, def)
    local restoreKeys = getRestorePropKeys(key, def)
    local changed = false
    for _, entry in ipairs(ctx.propsSnapshots or {}) do
        if isWidgetAlive(entry.widget) then
            local selected = false
            for _, w in ipairs(getInspectedWidgets()) do
                if w == entry.widget then
                    selected = true
                    break
                end
            end
            if selected and containsKey(entry.keys, key) then
                if M.restoreWidgetProps(
                    entry.widget,
                    entry.snapshot,
                    restoreKeys,
                    entry.autoWidthKeys
                ) then
                    changed = true
                end
            end
        end
    end
    if changed then
        M.refreshTweakFields()
    end
    return changed
end

return M
end
