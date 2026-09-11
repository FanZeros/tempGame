-- ============================================================================
-- GradientCard Widget
-- UrhoX UI Library - Yoga + NanoVG
-- 渐变卡片：线性渐变底 + 装饰图标 + 高光/内发光/浮动光点，支持 hover/press 反馈。
-- 动画由 UI.Update(dt) 逐帧驱动（自累加 animTime_）。子控件正常叠在卡片之上。
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")

---@class GradientCard : Widget
---@operator call(table?): GradientCard
local GradientCard = Widget:Extend("GradientCard")

-- 预定义配色方案
local ColorSchemes = {
    -- 蓝紫色 (快速匹配)
    blue = {
        primary = { 80, 100, 210 }, secondary = { 120, 70, 180 },
        accent = { 130, 180, 255 }, glow = { 100, 130, 255, 100 },
    },
    -- 青色系 (浏览房间) - 与绿色区分
    cyan = {
        primary = { 30, 150, 160 }, secondary = { 25, 110, 130 },
        accent = { 80, 220, 220 }, glow = { 60, 180, 180, 100 },
    },
    -- 绿色 (保留兼容)
    green = {
        primary = { 30, 150, 160 }, secondary = { 25, 110, 130 },
        accent = { 80, 220, 220 }, glow = { 60, 180, 180, 100 },
    },
    -- 橙红色 (创建房间)
    orange = {
        primary = { 220, 100, 65 }, secondary = { 180, 55, 70 },
        accent = { 255, 170, 100 }, glow = { 255, 130, 90, 100 },
    },
    -- 紫色 (加入中途局)
    purple = {
        primary = { 140, 70, 200 }, secondary = { 100, 40, 160 },
        accent = { 200, 150, 255 }, glow = { 160, 100, 255, 100 },
    },
}

-- ---- 装饰图标（卡片右下，按配色方案选）-------------------------------
local function DrawGamepadIcon(nvg, cx, cy, size, alpha, time)
    local scale = 1.0 + math.sin(time * 2) * 0.03
    local offsetY = math.sin(time * 1.5) * 4
    cy = cy + offsetY
    size = size * scale
    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    local s = size * 0.45
    local function drawLightningPath()
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, s * 0.15, -s * 1.1)
        nvgLineTo(nvg, -s * 0.55, -s * 0.05)
        nvgLineTo(nvg, -s * 0.05, -s * 0.05)
        nvgLineTo(nvg, -s * 0.35, s * 1.1)
        nvgLineTo(nvg, s * 0.55, s * 0.0)
        nvgLineTo(nvg, s * 0.05, s * 0.0)
        nvgClosePath(nvg)
    end
    for i = 3, 1, -1 do
        nvgSave(nvg)
        local glowAlpha = alpha * 0.08 * i
        local glowScale = 1.0 + i * 0.08
        nvgScale(nvg, glowScale, glowScale)
        drawLightningPath()
        nvgFillColor(nvg, nvgRGBA(200, 220, 255, glowAlpha))
        nvgFill(nvg)
        nvgRestore(nvg)
    end
    drawLightningPath()
    local grad = nvgLinearGradient(nvg, 0, -s * 1.1, 0, s * 1.1,
        nvgRGBA(255, 255, 255, alpha), nvgRGBA(220, 235, 255, alpha * 0.9))
    nvgFillPaint(nvg, grad)
    nvgFill(nvg)
    drawLightningPath()
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.5))
    nvgStrokeWidth(nvg, s * 0.04)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, s * 0.1, -s * 0.9)
    nvgLineTo(nvg, -s * 0.35, -s * 0.1)
    nvgLineTo(nvg, -s * 0.1, -s * 0.1)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.25))
    nvgFill(nvg)
    nvgRestore(nvg)
end

local function DrawMagnifierIcon(nvg, cx, cy, size, alpha, time)
    local CW = NVG_CW or 1
    local scale = 1.0 + math.sin(time * 1.8) * 0.06
    local rotation = math.sin(time * 1.2) * 0.1
    local offsetY = math.sin(time * 2.2) * 6
    cy = cy + offsetY
    size = size * scale
    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    nvgRotate(nvg, rotation)
    local glassR = size * 0.35
    local handleL = size * 0.4
    nvgBeginPath(nvg)
    nvgCircle(nvg, 0, 0, glassR)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgStrokeWidth(nvg, size * 0.08)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, 0, 0, glassR * 0.85)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.15))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgArc(nvg, 0, 0, glassR * 0.6, -2.5, -1.0, CW)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.4))
    nvgStrokeWidth(nvg, size * 0.04)
    nvgLineCap(nvg, NVG_ROUND)
    nvgStroke(nvg)
    local handleAngle = 0.785
    local handleStartX = glassR * 0.85 * math.cos(handleAngle)
    local handleStartY = glassR * 0.85 * math.sin(handleAngle)
    local handleEndX = handleStartX + handleL * math.cos(handleAngle)
    local handleEndY = handleStartY + handleL * math.sin(handleAngle)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, handleStartX, handleStartY)
    nvgLineTo(nvg, handleEndX, handleEndY)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgStrokeWidth(nvg, size * 0.12)
    nvgLineCap(nvg, NVG_ROUND)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, handleEndX, handleEndY, size * 0.12 * 0.6)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgFill(nvg)
    nvgRestore(nvg)
end

local function DrawDoorArrowIcon(nvg, cx, cy, size, alpha, time)
    local scale = 1.0 + math.sin(time * 2.2) * 0.05
    local offsetY = math.sin(time * 1.6) * 5
    cy = cy + offsetY
    size = size * scale
    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    local s = size * 0.4
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, -s * 0.6, -s * 1.0)
    nvgLineTo(nvg, s * 0.3, -s * 1.0)
    nvgLineTo(nvg, s * 0.3, s * 1.0)
    nvgLineTo(nvg, -s * 0.6, s * 1.0)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgStrokeWidth(nvg, s * 0.1)
    nvgLineCap(nvg, NVG_ROUND)
    nvgLineJoin(nvg, NVG_ROUND)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgRect(nvg, -s * 0.55, -s * 0.95, s * 0.8, s * 1.9)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.1))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, s * 0.1, 0, s * 0.08)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgFill(nvg)
    local arrowShift = math.sin(time * 3) * s * 0.15
    local arrowX = -s * 1.1 + arrowShift
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, arrowX - s * 0.4, 0)
    nvgLineTo(nvg, arrowX, 0)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.9))
    nvgStrokeWidth(nvg, s * 0.09)
    nvgLineCap(nvg, NVG_ROUND)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, arrowX - s * 0.15, -s * 0.12)
    nvgLineTo(nvg, arrowX, 0)
    nvgLineTo(nvg, arrowX - s * 0.15, s * 0.12)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.9))
    nvgStrokeWidth(nvg, s * 0.08)
    nvgLineCap(nvg, NVG_ROUND)
    nvgLineJoin(nvg, NVG_ROUND)
    nvgStroke(nvg)
    nvgRestore(nvg)
end

local function DrawPlusCircleIcon(nvg, cx, cy, size, alpha, time)
    local scale = 1.0 + math.sin(time * 2.0) * 0.08
    local rotation = time * 0.3
    local offsetY = math.sin(time * 1.8) * 7
    cy = cy + offsetY
    size = size * scale
    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    local circleR = size * 0.42
    local plusSize = size * 0.28
    local plusWidth = size * 0.08
    local outerAlpha = alpha * (0.3 + math.sin(time * 3) * 0.15)
    nvgBeginPath(nvg)
    nvgCircle(nvg, 0, 0, circleR * 1.15)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, outerAlpha))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, 0, 0, circleR)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgStrokeWidth(nvg, size * 0.06)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgCircle(nvg, 0, 0, circleR * 0.9)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.1))
    nvgFill(nvg)
    nvgSave(nvg)
    nvgRotate(nvg, rotation)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, -plusSize, -plusWidth / 2, plusSize * 2, plusWidth, plusWidth / 2)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, -plusWidth / 2, -plusSize, plusWidth, plusSize * 2, plusWidth / 2)
    nvgFill(nvg)
    nvgRestore(nvg)
    local dotCount = 4
    local dotR = size * 0.03
    local dotOrbit = circleR * 1.3
    for i = 1, dotCount do
        local angle = rotation * 0.5 + (i - 1) * (math.pi * 2 / dotCount)
        local dotX = math.cos(angle) * dotOrbit
        local dotY = math.sin(angle) * dotOrbit
        local dotAlpha = alpha * (0.3 + math.sin(time * 4 + i) * 0.2)
        nvgBeginPath(nvg)
        nvgCircle(nvg, dotX, dotY, dotR)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, dotAlpha))
        nvgFill(nvg)
    end
    nvgRestore(nvg)
end

-- ---- 卡片本体绘制 ------------------------------------------------------
local function drawCard(nvg, x, y, w, h, r, colors, time, hovered, pressed, colorScheme)
    if hovered then
        local glowSize = 20
        local glowAlpha = 60 + math.sin(time * 3) * 20
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - glowSize / 2, y - glowSize / 2, w + glowSize, h + glowSize, r + glowSize / 2)
        local glowPaint = nvgBoxGradient(nvg, x, y, w, h, r, glowSize * 2,
            nvgRGBA(colors.accent[1], colors.accent[2], colors.accent[3], glowAlpha),
            nvgRGBA(colors.accent[1], colors.accent[2], colors.accent[3], 0))
        nvgFillPaint(nvg, glowPaint)
        nvgFill(nvg)
    end

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, r)
    local gradientPaint = nvgLinearGradient(nvg, x, y, x + w, y + h,
        nvgRGBA(colors.primary[1], colors.primary[2], colors.primary[3], 255),
        nvgRGBA(colors.secondary[1], colors.secondary[2], colors.secondary[3], 255))
    nvgFillPaint(nvg, gradientPaint)
    nvgFill(nvg)

    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)
    local iconX = x + w * 0.65
    local iconY = y + h * 0.6
    local iconSize = math.min(w, h) * 0.7
    local iconAlpha = hovered and 45 or 30
    if colorScheme == "blue" then
        DrawGamepadIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    elseif colorScheme == "green" or colorScheme == "cyan" then
        DrawMagnifierIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    elseif colorScheme == "orange" then
        DrawPlusCircleIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    elseif colorScheme == "purple" then
        DrawDoorArrowIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    end
    nvgRestore(nvg)

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h * 0.5, r)
    local highlightPaint = nvgLinearGradient(nvg, x, y, x, y + h * 0.5,
        nvgRGBA(255, 255, 255, 40), nvgRGBA(255, 255, 255, 0))
    nvgFillPaint(nvg, highlightPaint)
    nvgFill(nvg)

    if hovered then
        local shineOffset = (time * 0.3) % 2.5 - 0.5
        local shineX = x + w * shineOffset
        local shineWidth = w * 0.3
        local skew = h * 0.3
        nvgSave(nvg)
        nvgIntersectScissor(nvg, x + r * 0.3, y + r * 0.3, w - r * 0.6, h - r * 0.6)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, shineX, y)
        nvgLineTo(nvg, shineX + shineWidth, y)
        nvgLineTo(nvg, shineX + shineWidth - skew, y + h)
        nvgLineTo(nvg, shineX - skew, y + h)
        nvgClosePath(nvg)
        local shinePaint = nvgLinearGradient(nvg, shineX, y, shineX + shineWidth, y,
            nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, 30))
        nvgFillPaint(nvg, shinePaint)
        nvgFill(nvg)
        nvgRestore(nvg)
    end

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 2, y + 2, w - 4, h - 4, r - 2)
    local innerGlow = nvgBoxGradient(nvg, x + 2, y + 2, w - 4, h - 4, r - 2, 15,
        nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, 30))
    nvgStrokePaint(nvg, innerGlow)
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 0.5, y + 0.5, w - 1, h - 1, r)
    local borderAlpha = hovered and 100 or 50
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, borderAlpha))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    if pressed then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, r)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 40))
        nvgFill(nvg)
    end

    nvgSave(nvg)
    nvgIntersectScissor(nvg, x, y, w, h)
    for i = 1, 5 do
        local dotX = x + w * (0.1 + 0.15 * i) + math.sin(time * 0.5 + i) * 10
        local dotY = y + h * 0.75 + math.cos(time * 0.7 + i * 1.5) * 15
        local dotSize = 3 + math.sin(time * 2 + i) * 1.5
        local dotAlpha = 30 + math.sin(time * 1.5 + i) * 15
        nvgBeginPath(nvg)
        nvgCircle(nvg, dotX, dotY, dotSize)
        nvgFillColor(nvg, nvgRGBA(colors.accent[1], colors.accent[2], colors.accent[3], dotAlpha))
        nvgFill(nvg)
    end
    nvgRestore(nvg)
end

function GradientCard:Init(props)
    props = props or {}
    props.width = props.width or 433
    if not props.height and not props.maxHeight then
        props.height = 591
    end
    props.borderRadius = props.borderRadius or 20
    self.colorScheme_ = props.colorScheme or "blue"
    self.colors_ = ColorSchemes[self.colorScheme_] or ColorSchemes.blue
    self.animTime_ = 0
    self.hovered_ = false
    self.pressed_ = false
    Widget.Init(self, props)
end

function GradientCard:Update(dt)
    self.animTime_ = self.animTime_ + dt
end

function GradientCard:Render(nvg)
    local l = self:GetAbsoluteLayout()
    drawCard(nvg, l.x, l.y, l.w, l.h, self.props.borderRadius or 20,
        self.colors_, self.animTime_, self.hovered_, self.pressed_, self.colorScheme_)
end

function GradientCard:OnMouseEnter() self.hovered_ = true end
function GradientCard:OnMouseLeave() self.hovered_ = false; self.pressed_ = false end
function GradientCard:OnPointerDown(event) if event and event:IsPrimaryAction() then self.pressed_ = true end end
function GradientCard:OnPointerUp(event) if event and event:IsPrimaryAction() then self.pressed_ = false end end
function GradientCard:OnClick() if self.props.onClick then self.props.onClick(self) end end
function GradientCard:IsStateful() return true end

return GradientCard
