-- ============================================================================
-- UIInspector - Edit Tool
-- Drag selected widgets by their selection box and record layout intent.
-- ============================================================================

return function(ctx, QuickTweak)

local M = {}
local isWidgetAlive = ctx.isWidgetAlive

local HANDLE_SIZE = 8
local HANDLE_HIT_SIZE = 14
local FRAME_HIT_PADDING = 6
local PARENT_BUTTON_SIZE = 18
local FOCUS_BUTTON_SIZE = 18
local TOOL_BUTTON_GAP = 4
local TOOL_BUTTON_HIT_PADDING = 5
local DRAG_START_DISTANCE = 3
local MIN_SIZE = 4

local SNAPSHOT_KEYS = {
    "width", "height", "flexBasis",
    "position", "left", "top", "right", "bottom",
    "marginLeft", "marginTop", "marginRight", "marginBottom",
}

local HANDLE_ORDER = { "nw", "n", "ne", "e", "se", "s", "sw", "w" }

local function round(v)
    return math.floor(v + 0.5)
end

local function rectFromLayout(l)
    if not l or l.w ~= l.w or l.h ~= l.h then return nil end
    return { x = l.x, y = l.y, w = l.w, h = l.h }
end

local function getWidgetScreenRect(widget)
    if ctx.getWidgetScreenRect then
        return ctx.getWidgetScreenRect(widget)
    end
    return rectFromLayout(widget and widget.GetAbsoluteLayoutForHitTest and widget:GetAbsoluteLayoutForHitTest()
        or widget and widget.GetAbsoluteLayout and widget:GetAbsoluteLayout()
        or nil)
end

local function getWidgetLayoutRect(widget)
    if ctx.getWidgetLayoutRect then
        return ctx.getWidgetLayoutRect(widget)
    end
    return rectFromLayout(widget and widget.GetAbsoluteLayout and widget:GetAbsoluteLayout() or nil)
end

local function copyRect(r)
    return { x = r.x, y = r.y, w = r.w, h = r.h }
end

local function rectChanged(a, b)
    if not a or not b then return false end
    return math.abs(a.x - b.x) > 0.5
        or math.abs(a.y - b.y) > 0.5
        or math.abs(a.w - b.w) > 0.5
        or math.abs(a.h - b.h) > 0.5
end

local function copyProps(widget)
    local props = {}
    for _, key in ipairs(SNAPSHOT_KEYS) do
        props[key] = ctx.deepCopyValue(widget.props[key])
    end
    return props
end

local function getScreenLayout()
    local scale = ctx.uiModule and ctx.uiModule.GetScale and ctx.uiModule.GetScale() or 1
    local w = graphics and graphics.width or 0
    local h = graphics and graphics.height or 0
    return { x = 0, y = 0, w = w / scale, h = h / scale }
end

local function getParentLayout(widget)
    if widget.parent and isWidgetAlive(widget.parent) then
        return getWidgetLayoutRect(widget.parent) or getScreenLayout()
    end
    return getScreenLayout()
end

local function getMainAxis(widget)
    local parent = widget.parent
    local dir = parent and parent.props and parent.props.flexDirection or "column"
    if dir == "row" or dir == "row-reverse" then
        return "x"
    end
    return "y"
end

local function parsePercent(value)
    if type(value) ~= "string" then return nil end
    return tonumber(value:match("^%s*([%-%d%.]+)%%%s*$"))
end

local function formatPercent(value)
    if math.abs(value - round(value)) < 0.05 then
        return tostring(round(value)) .. "%"
    end
    return string.format("%.1f%%", value)
end

local function valueToPixels(value, base, fallback)
    if type(value) == "number" then return value end
    local percent = parsePercent(value)
    if percent and base and base > 0 then
        return base * percent / 100
    end
    local numeric = tonumber(value)
    if numeric then return numeric end
    return fallback or 0
end

local function makeSizeValueLike(oldValue, pixels, base)
    pixels = math.max(MIN_SIZE, pixels)
    local percent = parsePercent(oldValue)
    if percent and base and base > 0 then
        return formatPercent(math.max(0, pixels / base * 100))
    end
    return round(pixels)
end

local function makeOffsetValueLike(oldValue, pixels, base)
    local percent = parsePercent(oldValue)
    if percent and base and base > 0 then
        return formatPercent(pixels / base * 100)
    end
    return round(pixels)
end

local function setStyleValue(style, appliedKeys, key, value)
    if value == nil then return end
    style[key] = value
    appliedKeys[key] = true
end

local function sizeKeyForAxis(state, axis)
    local props = state.startProps
    if props.flexBasis ~= nil and getMainAxis(state.widget) == axis then
        return "flexBasis"
    end
    if axis == "x" then
        return "width"
    end
    return "height"
end

local function sizeBaseForAxis(state, axis)
    if axis == "x" then
        return state.parentLayout.w
    end
    return state.parentLayout.h
end

local function axisKeys(axis)
    if axis == "x" then
        return "left", "right", "marginLeft", "marginRight", "w"
    end
    return "top", "bottom", "marginTop", "marginBottom", "h"
end

local function applyMoveAxis(state, axis, delta, style, appliedKeys, notes)
    if math.abs(delta) <= 0.5 then return true end

    local startKey, endKey = axisKeys(axis)
    local props = state.startProps
    local base = sizeBaseForAxis(state, axis)
    local hasStart = props[startKey] ~= nil
    local hasEnd = props[endKey] ~= nil
    local hasAnchor = hasStart or hasEnd
    local isAbsolute = props.position == "absolute"

    if isAbsolute or hasAnchor then
        if hasStart then
            local oldPx = valueToPixels(props[startKey], base, 0)
            setStyleValue(style, appliedKeys, startKey, makeOffsetValueLike(props[startKey], oldPx + delta, base))
        end
        if hasEnd then
            local oldPx = valueToPixels(props[endKey], base, 0)
            setStyleValue(style, appliedKeys, endKey, makeOffsetValueLike(props[endKey], oldPx - delta, base))
        end
        if not hasStart and not hasEnd then
            local parentLayout = state.parentLayout
            local startLayout = state.sourceStartLayout
            if not parentLayout or not startLayout then
                notes[#notes + 1] = axis == "x"
                    and "horizontal move skipped; source layout coordinates are unavailable"
                    or "vertical move skipped; source layout coordinates are unavailable"
                return false
            end
            local parentOffset = axis == "x" and parentLayout.x or parentLayout.y
            local startOffset = axis == "x" and startLayout.x or startLayout.y
            setStyleValue(style, appliedKeys, startKey, round(startOffset - parentOffset + delta))
        end
        return true
    end

    setStyleValue(style, appliedKeys, startKey, round(delta))
    return true
end

local function applyStartEdgeOffset(state, axis, delta, style, appliedKeys, notes)
    if math.abs(delta) <= 0.5 then return true end

    local startKey, endKey = axisKeys(axis)
    local props = state.startProps
    local base = sizeBaseForAxis(state, axis)
    local isAbsolute = props.position == "absolute"

    if props[startKey] ~= nil then
        local oldPx = valueToPixels(props[startKey], base, 0)
        setStyleValue(style, appliedKeys, startKey, makeOffsetValueLike(props[startKey], oldPx + delta, base))
        return true
    end
    if props[endKey] ~= nil then
        return true
    end
    if isAbsolute then
        local parentLayout = state.parentLayout
        local startLayout = state.sourceStartLayout
        if not parentLayout or not startLayout then
            notes[#notes + 1] = axis == "x"
                and "left edge skipped; source layout coordinates are unavailable"
                or "top edge skipped; source layout coordinates are unavailable"
            return false
        end
        local parentOffset = axis == "x" and parentLayout.x or parentLayout.y
        local startOffset = axis == "x" and startLayout.x or startLayout.y
        setStyleValue(style, appliedKeys, startKey, round(startOffset - parentOffset + delta))
        return true
    end
    setStyleValue(style, appliedKeys, startKey, round(delta))
    return true
end

local function applyEndEdgeOffset(state, axis, delta, style, appliedKeys)
    if math.abs(delta) <= 0.5 then return true end

    local _, endKey = axisKeys(axis)
    local props = state.startProps
    if props[endKey] == nil then return false end

    local base = sizeBaseForAxis(state, axis)
    local oldPx = valueToPixels(props[endKey], base, 0)
    setStyleValue(style, appliedKeys, endKey, makeOffsetValueLike(props[endKey], oldPx - delta, base))
    return true
end

local function applySizeAxis(state, axis, pixels, style, appliedKeys)
    local key = sizeKeyForAxis(state, axis)
    local base = sizeBaseForAxis(state, axis)
    setStyleValue(style, appliedKeys, key, makeSizeValueLike(state.startProps[key], pixels, base))
end

local function computeDesiredRect(state, x, y)
    local dx = x - state.startX
    local dy = y - state.startY
    local start = state.startLayout

    if state.mode == "move" then
        return { x = start.x + dx, y = start.y + dy, w = start.w, h = start.h }
    end

    local left = start.x
    local top = start.y
    local right = start.x + start.w
    local bottom = start.y + start.h
    local handle = state.handle

    if handle:find("w", 1, true) then
        left = math.min(right - MIN_SIZE, start.x + dx)
    elseif handle:find("e", 1, true) then
        right = math.max(left + MIN_SIZE, start.x + start.w + dx)
    end

    if handle:find("n", 1, true) then
        top = math.min(bottom - MIN_SIZE, start.y + dy)
    elseif handle:find("s", 1, true) then
        bottom = math.max(top + MIN_SIZE, start.y + start.h + dy)
    end

    return { x = left, y = top, w = right - left, h = bottom - top }
end

local function updateRecord(state, desired, appliedKeys, notes)
    local record = state.record
    record.afterRect = copyRect(desired)
    record.applied = {}
    record.note = #notes > 0 and table.concat(notes, "; ") or nil

    for key in pairs(appliedKeys) do
        local oldVal = state.startProps[key]
        local newVal = state.widget.props[key]
        if not ctx.valuesEqual(oldVal, newVal) then
            record.applied[#record.applied + 1] = { key = key, old = oldVal, new = newVal }
        end
    end

    record.desiredOnly = #record.applied == 0
    record.changed = rectChanged(record.beforeRect, record.afterRect) or #record.applied > 0
end

local function hasStyleValues(style)
    for _ in pairs(style) do return true end
    return false
end

local function getHandleCenters(rect)
    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
    local cx = x + w / 2
    local cy = y + h / 2
    return {
        nw = { x = x, y = y },
        n  = { x = cx, y = y },
        ne = { x = x + w, y = y },
        e  = { x = x + w, y = cy },
        se = { x = x + w, y = y + h },
        s  = { x = cx, y = y + h },
        sw = { x = x, y = y + h },
        w  = { x = x, y = cy },
    }
end

local function pointInHandle(x, y, center)
    local r = HANDLE_HIT_SIZE / 2
    return x >= center.x - r and x <= center.x + r
        and y >= center.y - r and y <= center.y + r
end

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function pointInExpandedRect(x, y, rect, padding)
    padding = padding or 0
    return x >= rect.x - padding and x <= rect.x + rect.w + padding
        and y >= rect.y - padding and y <= rect.y + rect.h + padding
end

local function pointOnRectEdge(x, y, rect, padding)
    padding = padding or 0
    if not pointInExpandedRect(x, y, rect, padding) then
        return false
    end
    return x <= rect.x + padding
        or x >= rect.x + rect.w - padding
        or y <= rect.y + padding
        or y >= rect.y + rect.h - padding
end

local getFocusButtonRect
local getParentButtonRect
local getToolButtonTop
local pointInAnyHandle

local function getActiveTarget()
    if isWidgetAlive(ctx.activeWidget) then return ctx.activeWidget end
    if isWidgetAlive(ctx.selectedWidget) then return ctx.selectedWidget end
    return nil
end

local function getHoverTarget()
    if isWidgetAlive(ctx.hoverEditWidget) then return ctx.hoverEditWidget end
    if isWidgetAlive(ctx.hoveredWidget) then return ctx.hoveredWidget end
    return nil
end

local function getEditTarget()
    if ctx.pointerOverInspectorChrome and not ctx.editState then
        return getActiveTarget()
    end
    return getHoverTarget() or getActiveTarget()
end

function M.getActiveTarget()
    return getActiveTarget()
end

function M.getHoverTarget()
    return getHoverTarget()
end

local function addUniqueTarget(targets, seen, widget)
    if isWidgetAlive(widget) and not seen[widget] then
        targets[#targets + 1] = widget
        seen[widget] = true
    end
end

local function getTargetCandidates()
    local targets = {}
    local seen = {}
    addUniqueTarget(targets, seen, ctx.hoverEditWidget)
    addUniqueTarget(targets, seen, ctx.hoveredWidget)
    addUniqueTarget(targets, seen, ctx.activeWidget)
    addUniqueTarget(targets, seen, ctx.selectedWidget)
    for _, widget in ipairs(ctx.selectedWidgets or {}) do
        addUniqueTarget(targets, seen, widget)
    end
    return targets
end

local function isPointOnWidgetChrome(widget, x, y)
    if not isWidgetAlive(widget) then return false end
    local rect = getWidgetScreenRect(widget)
    if not rect then return false end
    local toolbarTop = getToolButtonTop(rect)
    local focusRect = getFocusButtonRect(rect)
    local parentRect = widget.parent and getParentButtonRect(rect) or focusRect
    local minX = math.min(rect.x, focusRect.x, parentRect.x) - HANDLE_HIT_SIZE
    local maxX = math.max(rect.x + rect.w, focusRect.x + focusRect.w, parentRect.x + parentRect.w) + HANDLE_HIT_SIZE
    local keepAliveRect = {
        x = minX,
        y = toolbarTop - HANDLE_HIT_SIZE,
        w = maxX - minX,
        h = rect.y - toolbarTop + HANDLE_HIT_SIZE * 2,
    }
    if pointInRect(x, y, keepAliveRect) then
        return true
    end
    if pointOnRectEdge(x, y, rect, FRAME_HIT_PADDING) then
        return true
    end
    if pointInAnyHandle(x, y, rect) then
        return true
    end
    if pointInExpandedRect(x, y, focusRect, TOOL_BUTTON_HIT_PADDING) then
        return true
    end
    if widget.parent and pointInExpandedRect(x, y, parentRect, TOOL_BUTTON_HIT_PADDING) then
        return true
    end
    return false
end

function M.getEditTarget()
    return getEditTarget()
end

pointInAnyHandle = function(x, y, rect)
    local centers = getHandleCenters(rect)
    for _, handle in ipairs(HANDLE_ORDER) do
        if pointInHandle(x, y, centers[handle]) then
            return true
        end
    end
    return false
end

function M.isPointOnCurrentTarget(x, y)
    return M.hitChromeWidget(x, y) ~= nil
end

function M.hitChromeWidget(x, y)
    for _, widget in ipairs(getTargetCandidates()) do
        if isPointOnWidgetChrome(widget, x, y) then
            return widget
        end
    end
    return nil
end

function M.hitTest(x, y)
    local topHit = ctx.uiModule.FindWidgetAt(x, y)
    local activeWidget = getEditTarget()

    if isWidgetAlive(activeWidget) then
        local rect = getWidgetScreenRect(activeWidget)
        if rect then
            local centers = getHandleCenters(rect)
            for _, handle in ipairs(HANDLE_ORDER) do
                if pointInHandle(x, y, centers[handle]) then
                    return { widget = activeWidget, mode = "resize", handle = handle, rect = rect }
                end
            end
        end
    end

    if isWidgetAlive(activeWidget) then
        local rect = getWidgetScreenRect(activeWidget)
        if rect and pointInRect(x, y, rect)
            and (topHit == activeWidget
                or (activeWidget.props and activeWidget.props.pointerEvents == "none")) then
            return { widget = activeWidget, mode = "move", rect = rect }
        end
    end

    return nil
end

getToolButtonTop = function(rect)
    return math.max(0, rect.y - FOCUS_BUTTON_SIZE - TOOL_BUTTON_GAP)
end

getFocusButtonRect = function(rect)
    return {
        x = math.max(0, rect.x + rect.w - FOCUS_BUTTON_SIZE),
        y = getToolButtonTop(rect),
        w = FOCUS_BUTTON_SIZE,
        h = FOCUS_BUTTON_SIZE,
    }
end

getParentButtonRect = function(rect)
    return {
        x = math.max(0, rect.x + rect.w - FOCUS_BUTTON_SIZE - TOOL_BUTTON_GAP - PARENT_BUTTON_SIZE),
        y = getToolButtonTop(rect),
        w = PARENT_BUTTON_SIZE,
        h = PARENT_BUTTON_SIZE,
    }
end

local function isExplicitlySelected(widget)
    if ctx.UIInspector and ctx.UIInspector.IsWidgetSelected then
        return ctx.UIInspector.IsWidgetSelected(widget)
    end
    if ctx.UIInspector and ctx.UIInspector.IsWidgetFocused then
        return ctx.UIInspector.IsWidgetFocused(widget)
    end
    return ctx.UIInspector and ctx.UIInspector.IsWidgetPinned and ctx.UIInspector.IsWidgetPinned(widget)
end

local function drawToolButton(nvg, buttonRect, active)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, buttonRect.x, buttonRect.y, buttonRect.w, buttonRect.h, 4)
    if active then
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 235))
    else
        nvgFillColor(nvg, nvgRGBA(24, 24, 28, 220))
    end
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, active and 235 or 210))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
end

local function drawFocusIcon(nvg, buttonRect, focused)
    local cx = buttonRect.x + buttonRect.w / 2
    local cy = buttonRect.y + buttonRect.h / 2
    local r = focused and 24 or 255
    local g = focused and 24 or 255
    local b = focused and 28 or 255

    nvgStrokeColor(nvg, nvgRGBA(r, g, b, 245))
    nvgStrokeWidth(nvg, 1.25)

    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, 4.8)
    nvgStroke(nvg)

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - 7, cy)
    nvgLineTo(nvg, cx - 5.6, cy)
    nvgMoveTo(nvg, cx + 5.6, cy)
    nvgLineTo(nvg, cx + 7, cy)
    nvgMoveTo(nvg, cx, cy - 7)
    nvgLineTo(nvg, cx, cy - 5.6)
    nvgMoveTo(nvg, cx, cy + 5.6)
    nvgLineTo(nvg, cx, cy + 7)
    nvgStroke(nvg)

    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, 1.45)
    nvgFillColor(nvg, nvgRGBA(r, g, b, 245))
    nvgFill(nvg)
end

local function drawFocusButton(nvg, widget)
    if not isWidgetAlive(widget) then return end
    local rect = getWidgetScreenRect(widget)
    if not rect then return end
    local focused = isExplicitlySelected(widget)
    local focusButton = getFocusButtonRect(rect)
    drawToolButton(nvg, focusButton, focused)
    drawFocusIcon(nvg, focusButton, focused)
end

local function drawToolTooltip(nvg)
    local tip = ctx.editToolHoverTip
    if not tip or not isWidgetAlive(tip.widget) then return end

    local rect = getWidgetScreenRect(tip.widget)
    if not rect then return end

    local buttonRect
    local text
    local width
    if tip.kind == "parent" then
        if not tip.widget.parent then return end
        buttonRect = getParentButtonRect(rect)
        text = _tr("t_6u9V6LeA7Pe6QH8S")
        width = 64
    else
        buttonRect = getFocusButtonRect(rect)
        text = _tr("t_txArL5Z4tl74z7ky")
        width = 168
    end

    local screen = getScreenLayout()
    local x = math.max(4, math.min(buttonRect.x + buttonRect.w / 2 - width / 2, screen.w - width - 4))
    local y = buttonRect.y - 25
    if y < 4 then
        y = buttonRect.y + buttonRect.h + 6
    end

    nvgSave(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, width, 20, 5)
    nvgFillColor(nvg, nvgRGBA(18, 18, 22, 232))
    nvgFill(nvg)

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, width, 20, 5)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 58))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 11)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 232))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvg, x + width / 2, y + 10, text)
    nvgRestore(nvg)
end

function M.beginAt(x, y)
    local hit = M.hitTest(x, y)
    if not hit then return false end

    ctx.editPending = {
        widget = hit.widget,
        mode = hit.mode,
        handle = hit.handle,
        rect = copyRect(hit.rect),
        startX = x,
        startY = y,
    }
    return true, hit.widget
end

function M.hitParentButton(x, y)
    for _, widget in ipairs(getTargetCandidates()) do
        if widget.parent then
            local rect = getWidgetScreenRect(widget)
            if rect and pointInExpandedRect(x, y, getParentButtonRect(rect), TOOL_BUTTON_HIT_PADDING) then
                return widget.parent, widget
            end
        end
    end
    return nil
end

function M.hitToolButton(x, y)
    for _, widget in ipairs(getTargetCandidates()) do
        local rect = getWidgetScreenRect(widget)
        if rect then
            if widget.parent and pointInExpandedRect(x, y, getParentButtonRect(rect), TOOL_BUTTON_HIT_PADDING) then
                return "parent", widget
            end
            if pointInExpandedRect(x, y, getFocusButtonRect(rect), TOOL_BUTTON_HIT_PADDING) then
                return "focus", widget
            end
        end
    end
    return nil
end

function M.hitFocusButton(x, y)
    for _, widget in ipairs(getTargetCandidates()) do
        local rect = getWidgetScreenRect(widget)
        if rect and pointInExpandedRect(x, y, getFocusButtonRect(rect), TOOL_BUTTON_HIT_PADDING) then
            return widget
        end
    end

    return nil
end

function M.hitPinButton(x, y)
    return M.hitFocusButton(x, y)
end

local function startEditFromPending(pending)
    QuickTweak.ensureSnapshots({ pending.widget }, SNAPSHOT_KEYS)
    local record = {
        widget = pending.widget,
        mode = pending.mode,
        handle = pending.handle,
        beforeRect = copyRect(pending.rect),
        afterRect = copyRect(pending.rect),
        applied = {},
        desiredOnly = true,
        changed = false,
    }
    ctx.editRecords[#ctx.editRecords + 1] = record

    ctx.editState = {
        widget = pending.widget,
        mode = pending.mode,
        handle = pending.handle,
        startX = pending.startX,
        startY = pending.startY,
        startLayout = copyRect(pending.rect),
        parentLayout = getParentLayout(pending.widget),
        sourceStartLayout = getWidgetLayoutRect(pending.widget),
        startProps = copyProps(pending.widget),
        record = record,
    }
end

local updateRealtimeConstraintFeedback

function M.update(x, y)
    if ctx.editPending and not ctx.editState then
        local dx = x - ctx.editPending.startX
        local dy = y - ctx.editPending.startY
        if dx * dx + dy * dy < DRAG_START_DISTANCE * DRAG_START_DISTANCE then
            return true
        end
        local pending = ctx.editPending
        ctx.editPending = nil
        startEditFromPending(pending)
    end

    local state = ctx.editState
    if not state then return false end
    if not isWidgetAlive(state.widget) then
        ctx.editState = nil
        return true
    end

    local desired = computeDesiredRect(state, x, y)
    local style = {}
    local appliedKeys = {}
    local notes = {}

    if state.mode == "move" then
        local dx = desired.x - state.startLayout.x
        local dy = desired.y - state.startLayout.y
        applyMoveAxis(state, "x", dx, style, appliedKeys, notes)
        applyMoveAxis(state, "y", dy, style, appliedKeys, notes)
    else
        local startRight = state.startLayout.x + state.startLayout.w
        local startBottom = state.startLayout.y + state.startLayout.h
        local desiredRight = desired.x + desired.w
        local desiredBottom = desired.y + desired.h
        local handle = state.handle

        if handle:find("w", 1, true) or handle:find("e", 1, true) then
            applySizeAxis(state, "x", desired.w, style, appliedKeys)
            if handle:find("w", 1, true) then
                applyStartEdgeOffset(state, "x", desired.x - state.startLayout.x, style, appliedKeys, notes)
            elseif handle:find("e", 1, true) then
                applyEndEdgeOffset(state, "x", desiredRight - startRight, style, appliedKeys)
            end
        end

        if handle:find("n", 1, true) or handle:find("s", 1, true) then
            applySizeAxis(state, "y", desired.h, style, appliedKeys)
            if handle:find("n", 1, true) then
                applyStartEdgeOffset(state, "y", desired.y - state.startLayout.y, style, appliedKeys, notes)
            elseif handle:find("s", 1, true) then
                applyEndEdgeOffset(state, "y", desiredBottom - startBottom, style, appliedKeys)
            end
        end
    end

    local styleApplied = hasStyleValues(style)
    if styleApplied then
        QuickTweak.applyTweakValue(state.widget, style)
        QuickTweak.refreshTweakFields()
        updateRealtimeConstraintFeedback(state, desired)
    end

    updateRecord(state, desired, appliedKeys, notes)
    return true
end

local function removeRecord(record)
    for i = #ctx.editRecords, 1, -1 do
        if ctx.editRecords[i] == record then
            table.remove(ctx.editRecords, i)
            return
        end
    end
end

local function getAppliedKeys(record)
    local keys = {}
    for _, change in ipairs(record.applied or {}) do
        keys[#keys + 1] = change.key
    end
    return keys
end

local function dimensionChanged(before, after, key)
    if not before or not after then return false end
    return math.abs((before[key] or 0) - (after[key] or 0)) > 0.5
end

local function appliedKeyIsEffective(state, actual, key)
    if key == "width" then
        return dimensionChanged(state.startLayout, actual, "w")
    elseif key == "height" then
        return dimensionChanged(state.startLayout, actual, "h")
    elseif key == "flexBasis" then
        local axis = getMainAxis(state.widget)
        return dimensionChanged(state.startLayout, actual, axis == "x" and "w" or "h")
    elseif key == "left" or key == "right" or key == "marginLeft" or key == "marginRight" then
        return dimensionChanged(state.startLayout, actual, "x")
    elseif key == "top" or key == "bottom" or key == "marginTop" or key == "marginBottom" then
        return dimensionChanged(state.startLayout, actual, "y")
    end
    return true
end

updateRealtimeConstraintFeedback = function(state, desired)
    if not QuickTweak.getLayoutConstraintDirectionsFromRects
        or not QuickTweak.showLayoutConstraintHint
        or not QuickTweak.clearLayoutConstraintHint then
        return
    end
    if ctx.uiModule and ctx.uiModule.Layout then
        ctx.uiModule.Layout()
    end

    local actual = isWidgetAlive(state.widget) and getWidgetScreenRect(state.widget) or nil
    local directions = QuickTweak.getLayoutConstraintDirectionsFromRects(desired, actual)
    if directions then
        QuickTweak.showLayoutConstraintHint(state.widget, directions, {
            duration = 0.75,
            keepUntilClear = true,
            refreshExpires = false,
        })
    else
        QuickTweak.clearLayoutConstraintHint(state.widget)
    end
end

local function pruneIneffectiveChanges(state, actual)
    local record = state.record
    local keptChanges = {}
    local rollbackKeys = {}

    for _, change in ipairs(record.applied or {}) do
        if appliedKeyIsEffective(state, actual, change.key) then
            keptChanges[#keptChanges + 1] = change
        else
            rollbackKeys[#rollbackKeys + 1] = change.key
        end
    end

    if #rollbackKeys > 0 and QuickTweak.restoreWidgetProps then
        QuickTweak.restoreWidgetProps(state.widget, state.startProps, rollbackKeys)
        if ctx.uiModule and ctx.uiModule.Layout then
            ctx.uiModule.Layout()
        end
        QuickTweak.refreshTweakFields()
        actual = isWidgetAlive(state.widget) and getWidgetScreenRect(state.widget) or actual
    end

    record.applied = keptChanges
    record.afterRect = actual or record.afterRect
    record.desiredOnly = #record.applied == 0
    record.changed = rectChanged(record.beforeRect, record.afterRect) and #record.applied > 0

    if not record.changed then
        removeRecord(record)
    end
end

local function finalizeRecord(state)
    local record = state.record
    if not record.changed then
        removeRecord(record)
        return
    end

    if ctx.uiModule and ctx.uiModule.Layout then
        ctx.uiModule.Layout()
    end

    local actual = isWidgetAlive(state.widget) and getWidgetScreenRect(state.widget) or nil
    local actualChanged = rectChanged(record.beforeRect, actual)
    if actualChanged then
        pruneIneffectiveChanges(state, actual)
        return
    end

    local appliedKeys = getAppliedKeys(record)
    if #appliedKeys > 0 and QuickTweak.restoreWidgetProps then
        QuickTweak.restoreWidgetProps(state.widget, state.startProps, appliedKeys)
        if ctx.uiModule and ctx.uiModule.Layout then
            ctx.uiModule.Layout()
        end
        QuickTweak.refreshTweakFields()
    end

    removeRecord(record)
end

function M.endAt(x, y)
    if ctx.editPending and not ctx.editState then
        local widget = ctx.editPending.widget
        ctx.editPending = nil
        return true, widget, false
    end

    local state = ctx.editState
    if not state then return false end
    local widget = state.widget

    if x and y then
        M.update(x, y)
    end

    finalizeRecord(state)
    if QuickTweak.clearLayoutConstraintHint then
        QuickTweak.clearLayoutConstraintHint(widget)
    end
    ctx.editState = nil
    return true, widget, true
end

function M.cancel()
    ctx.editPending = nil
    if ctx.editState then
        if QuickTweak.clearLayoutConstraintHint then
            QuickTweak.clearLayoutConstraintHint(ctx.editState.widget)
        end
        removeRecord(ctx.editState.record)
    end
    ctx.editState = nil
end

function M.isDragging()
    return ctx.editState ~= nil
end

function M.drawHandles(nvg)
    local activeWidget = getEditTarget()
    if #ctx.selectedWidgets == 0 and not isWidgetAlive(activeWidget) then return end

    nvgSave(nvg)
    for _, widget in ipairs(ctx.selectedWidgets or {}) do
        if widget ~= activeWidget and isExplicitlySelected(widget) then
            drawFocusButton(nvg, widget)
        end
    end

    if not isWidgetAlive(activeWidget) then
        nvgRestore(nvg)
        return
    end

    local rect = getWidgetScreenRect(activeWidget)
    if rect then
        local focused = isExplicitlySelected(activeWidget)
        local focusButton = getFocusButtonRect(rect)
        drawToolButton(nvg, focusButton, focused)
        drawFocusIcon(nvg, focusButton, focused)

        if activeWidget.parent then
            local parentButton = getParentButtonRect(rect)
            drawToolButton(nvg, parentButton, false)

            local cx = parentButton.x + parentButton.w / 2
            local cy = parentButton.y + parentButton.h / 2
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, cx, cy - 5)
            nvgLineTo(nvg, cx - 4, cy - 1)
            nvgMoveTo(nvg, cx, cy - 5)
            nvgLineTo(nvg, cx + 4, cy - 1)
            nvgMoveTo(nvg, cx, cy - 5)
            nvgLineTo(nvg, cx, cy + 5)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 235))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)
        end

        local centers = getHandleCenters(rect)
        for _, handle in ipairs(HANDLE_ORDER) do
            local c = centers[handle]
            local x = c.x - HANDLE_SIZE / 2
            local y = c.y - HANDLE_SIZE / 2
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y, HANDLE_SIZE, HANDLE_SIZE, 2)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 235))
            nvgFill(nvg)
            nvgStrokeColor(nvg, nvgRGBA(ctx.ACTIVE_STROKE[1], ctx.ACTIVE_STROKE[2], ctx.ACTIVE_STROKE[3], 255))
            nvgStrokeWidth(nvg, 1.2)
            nvgStroke(nvg)
        end
    end

    if ctx.editState and ctx.editState.record and ctx.editState.record.afterRect then
        local r = ctx.editState.record.afterRect
        nvgBeginPath(nvg)
        nvgRect(nvg, r.x, r.y, r.w, r.h)
        nvgStrokeColor(nvg, nvgRGBA(66, 135, 245, 230))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end
    drawToolTooltip(nvg)
    nvgRestore(nvg)
end

return M
end
