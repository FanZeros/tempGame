-- ============================================================================
-- UIInspector - Overlay Module
-- NanoVG drawing functions for inspector overlays
-- ============================================================================

return function(ctx, Selection)

local M = {}
local isWidgetAlive = ctx.isWidgetAlive

local function getWidgetRect(widget)
    if ctx.getWidgetScreenRect then
        return ctx.getWidgetScreenRect(widget)
    end
    return widget and widget.GetAbsoluteLayout and widget:GetAbsoluteLayout() or nil
end

local function isEditorActive()
    return ctx.state == ctx.STATE_PICKING
        or ctx.state == ctx.STATE_DESCRIBING
        or ctx.state == ctx.STATE_EDITING
end

-- ============================================================================
-- Drawing Primitives
-- ============================================================================

--- Draw a highlight rectangle on a widget
local function drawHighlight(nvg, widget, fillColor, strokeColor)
    if not isWidgetAlive(widget) then return end
    local l = getWidgetRect(widget)
    if not l or l.w ~= l.w then return end  -- NaN guard

    nvgSave(nvg)

    -- Fill
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillColor(nvg, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4]))
    nvgFill(nvg)

    -- Stroke
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgStrokeColor(nvg, nvgRGBA(strokeColor[1], strokeColor[2], strokeColor[3], strokeColor[4]))
    nvgStrokeWidth(nvg, ctx.HIGHLIGHT_WIDTH)
    nvgStroke(nvg)

    nvgRestore(nvg)
end

--- Draw a tooltip label above or below a widget
local function drawPickingTooltip(nvg, widget)
    if not isWidgetAlive(widget) then return end
    local l = getWidgetRect(widget)
    if not l or l.w ~= l.w then return end

    local label = widget._className or "Widget"

    -- Position tooltip above the widget
    local tx = l.x
    local ty = l.y - 20
    if ty < 2 then ty = l.y + l.h + 4 end  -- flip below if at top edge

    -- Keep the hover tag compact so it does not collide with frame actions.
    local textW = #label * 7 + 12

    nvgSave(nvg)

    -- Background pill
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tx - 4, ty - 2, textW, 18, 3)
    nvgFillColor(nvg, nvgRGBA(30, 30, 30, 230))
    nvgFill(nvg)

    -- Text
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 12)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, tx, ty + 7, label)

    nvgRestore(nvg)
end

local function drawDirtyBadge(nvg, widget)
    if not isWidgetAlive(widget) then return end
    local dirty = false
    if ctx.QuickTweak and ctx.QuickTweak.getWidgetChangeState then
        local state = ctx.QuickTweak.getWidgetChangeState(widget)
        dirty = state and state.hasAnyChange
    end
    local prompt = ctx.widgetPrompts and ctx.widgetPrompts[widget]
    dirty = dirty or (prompt and prompt ~= "")
    if not dirty then return end

    local l = getWidgetRect(widget)
    if not l or l.w ~= l.w then return end
    nvgSave(nvg)
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 22)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 155))
    nvgText(nvg, l.x - 3, l.y - 8, "*")
    nvgFillColor(nvg, nvgRGBA(ctx.DIRTY_COLOR[1], ctx.DIRTY_COLOR[2], ctx.DIRTY_COLOR[3], ctx.DIRTY_COLOR[4]))
    nvgText(nvg, l.x - 4, l.y - 9, "*")
    nvgRestore(nvg)
end

local function truncatePrompt(prompt)
    prompt = tostring(prompt or "")
    if #prompt <= 32 then return prompt end
    return prompt:sub(1, 32) .. "..."
end

local function drawPromptAnnotation(nvg, widget)
    local prompt = ctx.widgetPrompts and ctx.widgetPrompts[widget]
    if not prompt or prompt == "" or not isWidgetAlive(widget) then return end
    local l = getWidgetRect(widget)
    if not l or l.w ~= l.w then return end

    local text = truncatePrompt(prompt)
    local tx = l.x + l.w + 12
    local ty = l.y + 14
    local textW = #text * 5 + 10

    nvgSave(nvg)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, l.x + l.w, l.y + math.min(18, l.h / 2))
    nvgLineTo(nvg, tx - 4, ty)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 70))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tx, ty - 9, textW, 18, 4)
    nvgFillColor(nvg, nvgRGBA(24, 24, 28, 125))
    nvgFill(nvg)

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 10)
    nvgFillColor(nvg, nvgRGBA(ctx.PROMPT_COLOR[1], ctx.PROMPT_COLOR[2], ctx.PROMPT_COLOR[3], ctx.PROMPT_COLOR[4]))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, tx + 5, ty, text)
    nvgRestore(nvg)
end

--- Draw a filled rect strip (helper for box model bands)
local function drawBand(nvg, x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4]))
    nvgFill(nvg)
end

--- Draw a pixel value label centered in a rect (helper for box model)
local function drawBandLabel(nvg, x, y, w, h, value)
    if value <= 0 then return end
    local label = tostring(math.floor(value))
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 10)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvg, x + w / 2, y + h / 2, label)
end

local function getActiveConstraintDirections(widget)
    local hints = ctx.layoutConstraintHints
    if not hints then return nil end
    local now = ctx.nowSeconds()
    for _, hint in ipairs(hints) do
        if hint.widget == widget and hint.expiresAt > now then
            local directions = hint.directions or {}
            if directions.left or directions.right or directions.up or directions.down then
                return directions
            end
        end
    end
    return nil
end

--- Draw box model visualization on a widget (margin/padding/content)
local function drawBoxModel(nvg, widget)
    if not isWidgetAlive(widget) then return end
    local l = getWidgetRect(widget)
    if not l or l.w ~= l.w then return end

    local node = widget.node

    -- Computed padding (pixels)
    local pT = YGNodeLayoutGetPadding(node, YGEdgeTop)
    local pR = YGNodeLayoutGetPadding(node, YGEdgeRight)
    local pB = YGNodeLayoutGetPadding(node, YGEdgeBottom)
    local pL = YGNodeLayoutGetPadding(node, YGEdgeLeft)

    -- Computed margin (pixels)
    local mT = YGNodeLayoutGetMargin(node, YGEdgeTop)
    local mR = YGNodeLayoutGetMargin(node, YGEdgeRight)
    local mB = YGNodeLayoutGetMargin(node, YGEdgeBottom)
    local mL = YGNodeLayoutGetMargin(node, YGEdgeLeft)

    -- Border-box (layout rect)
    local bx, by, bw, bh = l.x, l.y, l.w, l.h

    nvgSave(nvg)

    -- === Margin bands (outside border-box) ===
    drawBand(nvg, bx - mL, by - mT, bw + mL + mR, mT, ctx.MARGIN_COLOR)          -- top
    drawBand(nvg, bx - mL, by + bh, bw + mL + mR, mB, ctx.MARGIN_COLOR)          -- bottom
    drawBand(nvg, bx - mL, by,      mL,            bh, ctx.MARGIN_COLOR)          -- left
    drawBand(nvg, bx + bw, by,      mR,            bh, ctx.MARGIN_COLOR)          -- right

    -- === Padding bands (inside border-box) ===
    drawBand(nvg, bx,      by,           bw,            pT, ctx.PADDING_COLOR)    -- top
    drawBand(nvg, bx,      by + bh - pB, bw,            pB, ctx.PADDING_COLOR)    -- bottom
    drawBand(nvg, bx,      by + pT,      pL, bh - pT - pB, ctx.PADDING_COLOR)    -- left
    drawBand(nvg, bx + bw - pR, by + pT, pR, bh - pT - pB, ctx.PADDING_COLOR)   -- right

    -- === Content area ===
    drawBand(nvg, bx + pL, by + pT, bw - pL - pR, bh - pT - pB, ctx.CONTENT_COLOR)

    -- === Value labels ===
    -- Margin labels
    drawBandLabel(nvg, bx - mL, by - mT, bw + mL + mR, mT, mT)
    drawBandLabel(nvg, bx - mL, by + bh, bw + mL + mR, mB, mB)
    drawBandLabel(nvg, bx - mL, by,      mL,            bh, mL)
    drawBandLabel(nvg, bx + bw, by,      mR,            bh, mR)

    -- Padding labels
    drawBandLabel(nvg, bx,      by,           bw,            pT, pT)
    drawBandLabel(nvg, bx,      by + bh - pB, bw,            pB, pB)
    drawBandLabel(nvg, bx,      by + pT,      pL, bh - pT - pB, pL)
    drawBandLabel(nvg, bx + bw - pR, by + pT, pR, bh - pT - pB, pR)

    -- Border-box outline
    nvgBeginPath(nvg)
    nvgRect(nvg, bx, by, bw, bh)
    nvgStrokeColor(nvg, nvgRGBA(100, 160, 240, 180))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgRestore(nvg)
end

--- Draw a dimension label (W×H) near a widget
local function drawDimensionLabel(nvg, widget)
    if not isWidgetAlive(widget) then return end
    local l = getWidgetRect(widget)
    if not l or l.w ~= l.w then return end

    local label = string.format("%.0f\xC3\x97%.0f", l.w, l.h)  -- UTF-8 ×
    local tx = l.x + l.w / 2
    local ty = l.y + l.h + 14
    local showBelow = true
    -- If too close to bottom edge, show above
    local scale = ctx.uiModule.GetScale()
    local sh = graphics.height / scale
    if ty + 8 > sh then
        ty = l.y - 10
        showBelow = false
    end

    local directions = getActiveConstraintDirections(widget)
    if directions then
        if showBelow and directions.down then return end
        if not showBelow and directions.up then return end
    end

    nvgSave(nvg)

    -- Measure text for background
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 11)
    local textW = #label * 6 + 10

    -- Background pill
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, tx - textW / 2, ty - 8, textW, 16, 3)
    nvgFillColor(nvg, nvgRGBA(30, 30, 30, 210))
    nvgFill(nvg)

    -- Text
    nvgFillColor(nvg, nvgRGBA(255, 200, 100, 240))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvg, tx, ty, label)

    nvgRestore(nvg)
end

--- Draw layout flow direction arrows on a container widget
local function drawFlowArrows(nvg, widget)
    if not isWidgetAlive(widget) then return end
    if #widget.children == 0 then return end  -- not a container
    local l = getWidgetRect(widget)
    if not l or l.w ~= l.w then return end

    local dir = widget.props.flexDirection or "column"
    local cx, cy = l.x + l.w / 2, l.y + l.h / 2

    nvgSave(nvg)

    -- Arrow style
    nvgStrokeColor(nvg, nvgRGBA(255, 220, 100, 180))
    nvgStrokeWidth(nvg, 1.5)
    nvgFillColor(nvg, nvgRGBA(255, 220, 100, 180))

    local arrowLen = math.min(30, math.min(l.w, l.h) * 0.3)
    local headSize = 5

    -- Main axis arrow
    local ax1, ay1, ax2, ay2
    if dir == "row" then
        ax1, ay1 = cx - arrowLen / 2, cy
        ax2, ay2 = cx + arrowLen / 2, cy
    elseif dir == "row-reverse" then
        ax1, ay1 = cx + arrowLen / 2, cy
        ax2, ay2 = cx - arrowLen / 2, cy
    elseif dir == "column-reverse" then
        ax1, ay1 = cx, cy + arrowLen / 2
        ax2, ay2 = cx, cy - arrowLen / 2
    else  -- column (default)
        ax1, ay1 = cx, cy - arrowLen / 2
        ax2, ay2 = cx, cy + arrowLen / 2
    end

    -- Draw arrow line
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, ax1, ay1)
    nvgLineTo(nvg, ax2, ay2)
    nvgStroke(nvg)

    -- Draw arrowhead (triangle)
    local dx, dy = ax2 - ax1, ay2 - ay1
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
        dx, dy = dx / len, dy / len
        local px, py = -dy, dx  -- perpendicular
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, ax2, ay2)
        nvgLineTo(nvg, ax2 - dx * headSize + px * headSize * 0.5, ay2 - dy * headSize + py * headSize * 0.5)
        nvgLineTo(nvg, ax2 - dx * headSize - px * headSize * 0.5, ay2 - dy * headSize - py * headSize * 0.5)
        nvgClosePath(nvg)
        nvgFill(nvg)
    end

    -- Label: direction + alignItems + justifyContent (compact)
    local parts = { dir }
    if widget.props.justifyContent then
        parts[#parts + 1] = "J:" .. widget.props.justifyContent
    end
    if widget.props.alignItems then
        parts[#parts + 1] = "A:" .. widget.props.alignItems
    end
    local infoLabel = table.concat(parts, "  ")

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 9)
    local labelW = #infoLabel * 5 + 8
    local lx = l.x + 2
    local ly = l.y + 2

    -- Background
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, lx, ly, labelW, 13, 2)
    nvgFillColor(nvg, nvgRGBA(40, 40, 40, 200))
    nvgFill(nvg)

    -- Text
    nvgFillColor(nvg, nvgRGBA(255, 220, 100, 230))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, lx + 3, ly + 7, infoLabel)

    nvgRestore(nvg)
end

--- Draw distance line between two widgets
local function drawDistanceBetween(nvg, w1, w2)
    if not isWidgetAlive(w1) or not isWidgetAlive(w2) then return end
    local l1 = getWidgetRect(w1)
    local l2 = getWidgetRect(w2)
    if not l1 or not l2 or l1.w ~= l1.w or l2.w ~= l2.w then return end

    -- Horizontal gap
    local hGap
    if l2.x >= l1.x + l1.w then
        hGap = l2.x - (l1.x + l1.w)
    elseif l1.x >= l2.x + l2.w then
        hGap = l1.x - (l2.x + l2.w)
    end
    -- Vertical gap
    local vGap
    if l2.y >= l1.y + l1.h then
        vGap = l2.y - (l1.y + l1.h)
    elseif l1.y >= l2.y + l2.h then
        vGap = l1.y - (l2.y + l2.h)
    end

    nvgSave(nvg)
    nvgStrokeColor(nvg, nvgRGBA(255, 100, 100, 200))
    nvgStrokeWidth(nvg, 1)
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 10)
    nvgFillColor(nvg, nvgRGBA(255, 100, 100, 240))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- Draw horizontal distance if applicable
    if hGap and hGap >= 0 then
        local y = math.max(l1.y, l2.y) + math.min(l1.h, l2.h) / 2
        local x1 = math.min(l1.x + l1.w, l2.x + l2.w)
        local x2 = math.max(l1.x, l2.x)
        if x2 > x1 then x1, x2 = x2 - hGap, x2 end
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x1, y)
        nvgLineTo(nvg, x1 + hGap, y)
        nvgStroke(nvg)
        -- End ticks
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x1, y - 4)
        nvgLineTo(nvg, x1, y + 4)
        nvgMoveTo(nvg, x1 + hGap, y - 4)
        nvgLineTo(nvg, x1 + hGap, y + 4)
        nvgStroke(nvg)
        -- Label
        if hGap > 0 then
            nvgText(nvg, x1 + hGap / 2, y - 8, tostring(math.floor(hGap)))
        end
    end

    -- Draw vertical distance if applicable
    if vGap and vGap >= 0 then
        local x = math.max(l1.x, l2.x) + math.min(l1.w, l2.w) / 2
        local y1 = math.min(l1.y + l1.h, l2.y + l2.h)
        local y2 = math.max(l1.y, l2.y)
        if y2 > y1 then y1, y2 = y2 - vGap, y2 end
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x, y1)
        nvgLineTo(nvg, x, y1 + vGap)
        nvgStroke(nvg)
        -- End ticks
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x - 4, y1)
        nvgLineTo(nvg, x + 4, y1)
        nvgMoveTo(nvg, x - 4, y1 + vGap)
        nvgLineTo(nvg, x + 4, y1 + vGap)
        nvgStroke(nvg)
        -- Label
        if vGap > 0 then
            nvgText(nvg, x + 10, y1 + vGap / 2, tostring(math.floor(vGap)))
        end
    end

    nvgRestore(nvg)
end

local function getConstraintAlpha(amount)
    amount = type(amount) == "number" and amount or 24
    if amount < (ctx.QuickTweak.CONSTRAINT_VISIBLE_THRESHOLD or 10) then return 0 end
    return 235
end

local function mixConstraintColor(pulse, from, to)
    local t = math.max(0, math.min(1, pulse or 0))
    return {
        math.floor(from[1] + (to[1] - from[1]) * t),
        math.floor(from[2] + (to[2] - from[2]) * t),
        math.floor(from[3] + (to[3] - from[3]) * t),
    }
end

local function drawConstraintBlocker(nvg, cx, cy, vertical, alpha, pulse)
    if alpha <= 0 then return end

    local haloAlpha = math.floor(alpha * 0.16)
    local lineAlpha = math.floor(alpha * 0.88)
    local crossAlpha = math.floor(alpha * 0.98)
    local shadowAlpha = math.floor(alpha * 0.32)
    local haloColor = mixConstraintColor(pulse, { 255, 70, 34 }, { 255, 130, 130 })
    local lineColor = mixConstraintColor(pulse, { 255, 86, 42 }, { 255, 145, 145 })
    local crossHaloColor = mixConstraintColor(pulse, { 255, 70, 34 }, { 255, 130, 130 })
    local crossColor = mixConstraintColor(pulse, { 255, 100, 52 }, { 255, 165, 165 })

    local function drawSegments(width, color)
        nvgStrokeWidth(nvg, width)
        nvgStrokeColor(nvg, color)
        nvgBeginPath(nvg)
        if vertical then
            nvgMoveTo(nvg, cx, cy - 28)
            nvgLineTo(nvg, cx, cy - 5.8)
            nvgMoveTo(nvg, cx, cy + 5.8)
            nvgLineTo(nvg, cx, cy + 28)
        else
            nvgMoveTo(nvg, cx - 38, cy)
            nvgLineTo(nvg, cx - 5.8, cy)
            nvgMoveTo(nvg, cx + 5.8, cy)
            nvgLineTo(nvg, cx + 38, cy)
        end
        nvgStroke(nvg)
    end

    nvgLineCap(nvg, NVG_ROUND)
    drawSegments(4.4, nvgRGBA(18, 8, 5, shadowAlpha))
    drawSegments(2.8, nvgRGBA(haloColor[1], haloColor[2], haloColor[3], haloAlpha))
    drawSegments(1.3, nvgRGBA(lineColor[1], lineColor[2], lineColor[3], lineAlpha))

    nvgStrokeWidth(nvg, 2.9)
    nvgStrokeColor(nvg, nvgRGBA(18, 8, 5, shadowAlpha))
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - 3.8, cy - 3.8)
    nvgLineTo(nvg, cx + 3.8, cy + 3.8)
    nvgMoveTo(nvg, cx + 3.8, cy - 3.8)
    nvgLineTo(nvg, cx - 3.8, cy + 3.8)
    nvgStroke(nvg)

    nvgStrokeWidth(nvg, 1.45)
    nvgStrokeColor(nvg, nvgRGBA(crossHaloColor[1], crossHaloColor[2], crossHaloColor[3], haloAlpha))
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - 4.3, cy - 4.3)
    nvgLineTo(nvg, cx + 4.3, cy + 4.3)
    nvgMoveTo(nvg, cx + 4.3, cy - 4.3)
    nvgLineTo(nvg, cx - 4.3, cy + 4.3)
    nvgStroke(nvg)

    nvgStrokeWidth(nvg, 1.08)
    nvgStrokeColor(nvg, nvgRGBA(crossColor[1], crossColor[2], crossColor[3], crossAlpha))
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - 3.7, cy - 3.7)
    nvgLineTo(nvg, cx + 3.7, cy + 3.7)
    nvgMoveTo(nvg, cx + 3.7, cy - 3.7)
    nvgLineTo(nvg, cx - 3.7, cy + 3.7)
    nvgStroke(nvg)
    nvgLineCap(nvg, NVG_BUTT)
end

local function getConstraintShakeOffset(direction, shakeAt, now)
    if not shakeAt then return 0, 0 end
    local elapsed = now - shakeAt
    if elapsed < 0 or elapsed > 0.24 then return 0, 0 end

    local decay = 1 - elapsed / 0.24
    local distance = math.sin(elapsed * 140) * 7.5 * decay
    -- Shake along the blocker line itself: top/bottom blockers are horizontal,
    -- left/right blockers are vertical.
    if direction == "up" or direction == "down" then
        return distance, 0
    elseif direction == "left" or direction == "right" then
        return 0, distance
    end
    return 0, 0
end

local function drawConstraintDirection(nvg, rect, direction, amount, swidth, sheight, pulse, shakeAt, now)
    local alpha = getConstraintAlpha(amount)
    if alpha <= 0 then return end

    local cx = rect.x + rect.w / 2
    local cy = rect.y + rect.h / 2
    local vertical = direction == "left" or direction == "right"
    local offset = 14
    if direction == "left" then
        cx = rect.x - offset
    elseif direction == "right" then
        cx = rect.x + rect.w + offset
    elseif direction == "up" then
        cy = rect.y - offset
    elseif direction == "down" then
        cy = rect.y + rect.h + offset
    end

    cx = math.max(26, math.min(swidth - 26, cx))
    cy = math.max(18, math.min(sheight - 18, cy))
    local sx, sy = getConstraintShakeOffset(direction, shakeAt, now)
    cx = cx + sx
    cy = cy + sy
    drawConstraintBlocker(nvg, cx, cy, vertical, alpha, pulse)
end

local function getConstraintDirections(hint)
    return hint.directions or {}
end

local function drawLayoutConstraintHints(nvg)
    local hints = ctx.layoutConstraintHints
    if not hints or #hints == 0 then return end

    local scale = ctx.uiModule.GetScale()
    local swidth = graphics.width / scale
    local sheight = graphics.height / scale
    local now = ctx.nowSeconds()

    nvgSave(nvg)

    for i = #hints, 1, -1 do
        local hint = hints[i]
        local expired = hint and not hint.persistent and hint.expiresAt <= now
        if not hint or (expired and not hint.keepUntilClear) or not isWidgetAlive(hint.widget) then
            table.remove(hints, i)
        elseif not expired then
            -- keepUntilClear hints intentionally become invisible after one short flash;
            -- keeping them suppresses repeated flashes while the same drag remains blocked.
            local l = getWidgetRect(hint.widget)
            if l and l.w == l.w then
                local pulse = 0.15 + 0.85 * math.abs(math.sin(now * 18))
                local directions = getConstraintDirections(hint)
                local shakes = hint.shakes or {}
                if directions.left then drawConstraintDirection(nvg, l, "left", directions.left, swidth, sheight, pulse, shakes.left, now) end
                if directions.right then drawConstraintDirection(nvg, l, "right", directions.right, swidth, sheight, pulse, shakes.right, now) end
                if directions.up then drawConstraintDirection(nvg, l, "up", directions.up, swidth, sheight, pulse, shakes.up, now) end
                if directions.down then drawConstraintDirection(nvg, l, "down", directions.down, swidth, sheight, pulse, shakes.down, now) end
            end
        end
    end

    nvgRestore(nvg)
end

-- ============================================================================
-- Main Overlay Render
-- ============================================================================

--- Render widget selection overlays below the inspector panel/dialog.
function M.renderInspectorSelectionOverlay(nvg)
    if not isEditorActive() then
        return
    end

    local scale = ctx.uiModule.GetScale()
    local swidth = graphics.width / scale
    local sheight = graphics.height / scale
    nvgSave(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, swidth, sheight)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 18))
    nvgFill(nvg)
    nvgRestore(nvg)

    -- Draw ancestor chain outlines for all selected widgets
    for _, sw in ipairs(ctx.selectedWidgets) do
        if isWidgetAlive(sw) then
            local p = sw.parent
            while p do
                if isWidgetAlive(p) then
                    drawHighlight(nvg, p, { 0, 0, 0, 0 }, ctx.ANCESTOR_STROKE)
                end
                p = p.parent
            end
        end
    end

    local activeWidget = ctx.EditTool and ctx.EditTool.getActiveTarget and ctx.EditTool.getActiveTarget()
        or (isWidgetAlive(ctx.activeWidget) and ctx.activeWidget or nil)
        or (isWidgetAlive(ctx.selectedWidget) and ctx.selectedWidget or nil)
    local editWidget = ctx.EditTool and ctx.EditTool.getEditTarget and ctx.EditTool.getEditTarget()
        or activeWidget

    -- Draw hovered widget. The current edit target gets the full editable frame below.
    if ctx.hoveredWidget and isWidgetAlive(ctx.hoveredWidget) then
        if ctx.hoveredWidget ~= editWidget and ctx.hoveredWidget ~= activeWidget and not Selection.isWidgetSelected(ctx.hoveredWidget) then
            drawDimensionLabel(nvg, ctx.hoveredWidget)
            drawHighlight(nvg, ctx.hoveredWidget, ctx.HOVER_FILL, ctx.HOVER_STROKE)
        end
        drawPickingTooltip(nvg, ctx.hoveredWidget)
    end

    -- Draw selected widgets softly; only active gets detailed affordances.
    local selectedMap = {}
    for i, selected in ipairs(ctx.selectedWidgets) do
        if isWidgetAlive(selected) then
            selectedMap[selected] = true
            local isActive = selected == activeWidget
            drawHighlight(
                nvg,
                selected,
                isActive and ctx.SELECT_FILL or ctx.SELECT2_FILL,
                isActive and ctx.ACTIVE_STROKE or ctx.SELECT2_STROKE
            )
            if isActive then
                drawBoxModel(nvg, selected)
                drawDimensionLabel(nvg, selected)
                drawFlowArrows(nvg, selected)
            end
            drawDirtyBadge(nvg, selected)
            drawPromptAnnotation(nvg, selected)
        end
    end

    if isWidgetAlive(activeWidget) and not selectedMap[activeWidget] then
        drawHighlight(nvg, activeWidget, ctx.SELECT_FILL, ctx.ACTIVE_STROKE)
        drawBoxModel(nvg, activeWidget)
        drawDimensionLabel(nvg, activeWidget)
        drawFlowArrows(nvg, activeWidget)
        drawDirtyBadge(nvg, activeWidget)
        drawPromptAnnotation(nvg, activeWidget)
        selectedMap[activeWidget] = true
    end

    if isWidgetAlive(editWidget) and editWidget ~= activeWidget then
        drawHighlight(nvg, editWidget, ctx.HOVER_FILL, ctx.HOVER_STROKE)
        drawBoxModel(nvg, editWidget)
        drawDimensionLabel(nvg, editWidget)
        drawFlowArrows(nvg, editWidget)
        drawDirtyBadge(nvg, editWidget)
        drawPromptAnnotation(nvg, editWidget)
        selectedMap[editWidget] = true
    end

    if ctx.QuickTweak and ctx.QuickTweak.getDirtyWidgets then
        for _, dirtyWidget in ipairs(ctx.QuickTweak.getDirtyWidgets()) do
            if not selectedMap[dirtyWidget] then
                drawDirtyBadge(nvg, dirtyWidget)
                drawPromptAnnotation(nvg, dirtyWidget)
            end
        end
    end

    if ctx.EditTool and ctx.EditTool.drawHandles then
        ctx.EditTool.drawHandles(nvg)
    end

    -- Draw distance lines based on hover + selection
    if ctx.hoveredWidget and isWidgetAlive(ctx.hoveredWidget) and #ctx.selectedWidgets > 0 then
        if Selection.isWidgetSelected(ctx.hoveredWidget) then
            -- Hovered is selected: show distances to all other selected
            for _, sw in ipairs(ctx.selectedWidgets) do
                if sw ~= ctx.hoveredWidget and isWidgetAlive(sw) then
                    drawDistanceBetween(nvg, ctx.hoveredWidget, sw)
                end
            end
        else
            -- Hovered is not selected: show distance to nearest selected
            local nearest, nearestDist = nil, math.huge
            for _, sw in ipairs(ctx.selectedWidgets) do
                if isWidgetAlive(sw) then
                    local l1 = getWidgetRect(ctx.hoveredWidget)
                    local l2 = getWidgetRect(sw)
                    if l1 and l2 and l1.w == l1.w and l2.w == l2.w then
                        local dx = (l1.x + l1.w / 2) - (l2.x + l2.w / 2)
                        local dy = (l1.y + l1.h / 2) - (l2.y + l2.h / 2)
                        local dist = dx * dx + dy * dy
                        if dist < nearestDist then
                            nearestDist = dist
                            nearest = sw
                        end
                    end
                end
            end
            if nearest then
                drawDistanceBetween(nvg, ctx.hoveredWidget, nearest)
            end
        end
    end

    drawLayoutConstraintHints(nvg)

end

--- Render inspector widget overlays (called above inspectorRoot_).
function M.renderInspectorOverlay(nvg)
    -- Render queued overlay callbacks from inspector widgets (e.g. ColorPicker popup)
    for _, cb in ipairs(ctx.inspectorOverlayCallbacks) do
        cb(nvg)
    end
    ctx.inspectorOverlayCallbacks = {}
end

return M
end
