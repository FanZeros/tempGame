-- ============================================================================
-- Icon Widget
-- UrhoX UI Library - Yoga + NanoVG
-- 矢量图标控件：在控件区域内用 NanoVG 路径绘制图标。
-- variant = "solid"（默认，填充风格）| "line"（线条风格）。
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")

---@class Icon : Widget
---@operator call(table?): Icon
local Icon = Widget:Extend("Icon")

local function rgba(c)
    return nvgRGBA(c[1], c[2], c[3], c[4] or 255)
end

-- ---- 填充风格（区域 (x,y,size,size)，内部自算中心）----------------------
-- kinds: lightning / search / plus / exit / back / cancel / refresh
local function drawSolid(vg, kind, x, y, size, color)
    local col = rgba(color or { 255, 255, 255, 200 })
    local cx, cy = x + size * 0.5, y + size * 0.5
    local CW = NVG_CW or 1
    nvgLineCap(vg, NVG_ROUND) nvgLineJoin(vg, NVG_ROUND)

    if kind == "lightning" then
        local s = size * 0.42
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 0.08, cy - s)   nvgLineTo(vg, cx - s * 0.55, cy + s * 0.02)
        nvgLineTo(vg, cx - s * 0.08, cy + s * 0.02) nvgLineTo(vg, cx - s * 0.32, cy + s)
        nvgLineTo(vg, cx + s * 0.55, cy - s * 0.14) nvgLineTo(vg, cx + s * 0.08, cy - s * 0.14)
        nvgClosePath(vg) nvgFillColor(vg, col) nvgFill(vg)

    elseif kind == "search" then
        local r = size * 0.24
        nvgBeginPath(vg) nvgCircle(vg, cx - size * 0.05, cy - size * 0.05, r)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.4) nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + r * 0.55, cy + r * 0.55) nvgLineTo(vg, x + size * 0.82, y + size * 0.82)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.5) nvgStroke(vg)

    elseif kind == "plus" then
        local r = size * 0.30
        nvgBeginPath(vg) nvgCircle(vg, cx, cy, r)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.16) nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - r * 0.55, cy) nvgLineTo(vg, cx + r * 0.55, cy)
        nvgMoveTo(vg, cx, cy - r * 0.55) nvgLineTo(vg, cx, cy + r * 0.55)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.18) nvgStroke(vg)

    elseif kind == "exit" or kind == "back" then
        local s = size * 0.42
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, math.max(2, size * 0.07))
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 0.12, cy - s) nvgLineTo(vg, cx - s, cy - s)
        nvgLineTo(vg, cx - s, cy + s)        nvgLineTo(vg, cx + s * 0.12, cy + s)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s * 0.15, cy)        nvgLineTo(vg, cx + s * 0.82, cy)
        nvgMoveTo(vg, cx + s * 0.42, cy - s * 0.35) nvgLineTo(vg, cx + s * 0.82, cy)
        nvgLineTo(vg, cx + s * 0.42, cy + s * 0.35)
        nvgStroke(vg)

    elseif kind == "cancel" then
        local s = size * 0.30
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, math.max(2, size * 0.09))
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s, cy - s) nvgLineTo(vg, cx + s, cy + s)
        nvgMoveTo(vg, cx + s, cy - s) nvgLineTo(vg, cx - s, cy + s)
        nvgStroke(vg)

    elseif kind == "refresh" then
        local r = size * 0.30
        nvgBeginPath(vg) nvgArc(vg, cx, cy, r, -math.pi * 0.2, math.pi * 1.5, CW)
        nvgStrokeColor(vg, col) nvgStrokeWidth(vg, r * 0.22) nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + r * 0.55, cy - r * 0.75) nvgLineTo(vg, cx + r * 0.55, cy - r * 0.2)
        nvgLineTo(vg, cx + r * 1.05, cy - r * 0.5)
        nvgFillColor(vg, col) nvgFill(vg)
    end
end

-- ---- 线条风格（中心 cx,cy）---------------------------------------------
-- kinds: exit / search / cancel / plus / back
local function drawLine(vg, kind, cx, cy, size, color, sw)
    color = color or { 255, 255, 255, 255 }
    sw = sw or 2
    local function stroke() nvgStrokeColor(vg, rgba(color)) nvgStrokeWidth(vg, sw) end

    if kind == "exit" then
        local s = size * 0.4
        nvgStrokeColor(vg, rgba(color)) nvgStrokeWidth(vg, sw)
        nvgLineCap(vg, NVG_ROUND) nvgLineJoin(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 0.2, cy - s)
        nvgLineTo(vg, cx - s, cy - s)
        nvgLineTo(vg, cx - s, cy + s)
        nvgLineTo(vg, cx + s * 0.2, cy + s)
        nvgStroke(vg)
        local arrowX = cx + s * 0.1
        local arrowLen = s * 0.9
        local arrowHead = s * 0.4
        nvgBeginPath(vg)
        nvgMoveTo(vg, arrowX - arrowLen * 0.3, cy)
        nvgLineTo(vg, arrowX + arrowLen * 0.7, cy)
        nvgMoveTo(vg, arrowX + arrowLen * 0.3, cy - arrowHead)
        nvgLineTo(vg, arrowX + arrowLen * 0.7, cy)
        nvgLineTo(vg, arrowX + arrowLen * 0.3, cy + arrowHead)
        nvgStroke(vg)

    elseif kind == "search" then
        local r = size * 0.32
        local handleLen = size * 0.3
        local handleAngle = 0.785
        nvgStrokeColor(vg, rgba(color)) nvgStrokeWidth(vg, sw * 1.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgCircle(vg, cx - size * 0.08, cy - size * 0.08, r)
        nvgStroke(vg)
        local hx1 = cx - size * 0.08 + r * 0.7 * math.cos(handleAngle)
        local hy1 = cy - size * 0.08 + r * 0.7 * math.sin(handleAngle)
        local hx2 = hx1 + handleLen * math.cos(handleAngle)
        local hy2 = hy1 + handleLen * math.sin(handleAngle)
        nvgBeginPath(vg)
        nvgMoveTo(vg, hx1, hy1)
        nvgLineTo(vg, hx2, hy2)
        nvgStrokeWidth(vg, sw * 2)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgArc(vg, cx - size * 0.08, cy - size * 0.08, r * 0.6, -2.3, -1.2, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], (color[4] or 255) * 0.4))
        nvgStrokeWidth(vg, sw)
        nvgStroke(vg)

    elseif kind == "cancel" then
        local s = size * 0.35
        nvgStrokeColor(vg, rgba(color)) nvgStrokeWidth(vg, sw * 1.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s, cy - s)
        nvgLineTo(vg, cx + s, cy + s)
        nvgMoveTo(vg, cx + s, cy - s)
        nvgLineTo(vg, cx - s, cy + s)
        nvgStroke(vg)

    elseif kind == "plus" then
        local s = size * 0.35
        nvgStrokeColor(vg, rgba(color)) nvgStrokeWidth(vg, sw * 1.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - s)
        nvgLineTo(vg, cx, cy + s)
        nvgMoveTo(vg, cx - s, cy)
        nvgLineTo(vg, cx + s, cy)
        nvgStroke(vg)

    elseif kind == "back" then
        local s = size * 0.35
        nvgStrokeColor(vg, rgba(color)) nvgStrokeWidth(vg, sw * 1.5)
        nvgLineCap(vg, NVG_ROUND) nvgLineJoin(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 0.5, cy - s)
        nvgLineTo(vg, cx - s * 0.5, cy)
        nvgLineTo(vg, cx + s * 0.5, cy + s)
        nvgStroke(vg)
    end
end

function Icon:Init(props)
    props = props or {}
    props.width = props.width or props.size or 32
    props.height = props.height or props.size or 32
    self.kind_ = props.name or props.kind or props.icon or "exit"
    self.color_ = props.color or { 255, 255, 255, 255 }
    self.strokeWidth_ = props.strokeWidth or 2
    self.variant_ = props.variant or "solid"
    self.size_ = props.size
    Widget.Init(self, props)
end

function Icon:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local size = self.size_ or math.min(l.w, l.h)
    if self.variant_ == "line" then
        drawLine(nvg, self.kind_, l.x + l.w / 2, l.y + l.h / 2, size, self.color_, self.strokeWidth_)
    else
        drawSolid(nvg, self.kind_, l.x + (l.w - size) * 0.5, l.y + (l.h - size) * 0.5, size, self.color_)
    end
end

return Icon
