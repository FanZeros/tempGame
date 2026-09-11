---@diagnostic disable: undefined-global, undefined-field, undefined-doc-name, missing-parameter
--[[
LobbyUI.lua - Out-of-box game lobby UI component

Provides complete lobby interface including:
- Quick match
- Room browser
- Create room
- Room details
- Match waiting

Usage example:
    local LobbyUI = require("urhox-libs.Lobby.LobbyUI")

    -- Simplest usage: one line to launch complete lobby
    LobbyUI.Show()

    -- Custom configuration
    LobbyUI.Show({
        mapName = "BattleArena",
        maxPlayers = 4,
        theme = "dark",
        onGameStart = function(serverInfo)
            -- Game start callback
        end
    })
]]

local UI = require("urhox-libs.UI")
local Toast = require("urhox-libs.UI.Widgets.Toast")
local LobbyManager = require("urhox-libs.Lobby.LobbyManager")
local Widget = require("urhox-libs/UI/Core/Widget")

-- ============================================================================
-- GradientCard Widget (内嵌组件)
-- 使用 NanoVG 绘制炫酷渐变卡片效果
-- ============================================================================

---@class GradientCard : Widget
local GradientCard = Widget:Extend("GradientCard")

-- 预定义配色方案
local GradientCardColorSchemes = {
    -- 蓝紫色 (快速匹配)
    blue = {
        primary = { 80, 100, 210 },
        secondary = { 120, 70, 180 },
        accent = { 130, 180, 255 },
        glow = { 100, 130, 255, 100 },
    },
    -- 青色系 (浏览房间) - 与绿色区分
    cyan = {
        primary = { 30, 150, 160 },
        secondary = { 25, 110, 130 },
        accent = { 80, 220, 220 },
        glow = { 60, 180, 180, 100 },
    },
    -- 绿色 (保留兼容)
    green = {
        primary = { 30, 150, 160 },
        secondary = { 25, 110, 130 },
        accent = { 80, 220, 220 },
        glow = { 60, 180, 180, 100 },
    },
    -- 橙红色 (创建房间)
    orange = {
        primary = { 220, 100, 65 },
        secondary = { 180, 55, 70 },
        accent = { 255, 170, 100 },
        glow = { 255, 130, 90, 100 },
    },
    -- 紫色 (加入中途局)
    purple = {
        primary = { 140, 70, 200 },
        secondary = { 100, 40, 160 },
        accent = { 200, 150, 255 },
        glow = { 160, 100, 255, 100 },
    },
}

function GradientCard:Init(props)
    props = props or {}
    props.width = props.width or 433
    if not props.height and not props.maxHeight then
        props.height = 591
    end
    props.borderRadius = props.borderRadius or 20
    self.colorScheme_ = props.colorScheme or "blue"
    self.colors_ = GradientCardColorSchemes[self.colorScheme_] or GradientCardColorSchemes.blue
    self.animTime_ = 0
    self.hovered_ = false
    self.pressed_ = false
    Widget.Init(self, props)
end

function GradientCard:Update(dt)
    self.animTime_ = self.animTime_ + dt
end

--- 绘制闪电图标 (快速匹配) - 精致立体闪电
local function DrawGamepadIcon(nvg, cx, cy, size, alpha, time)
    local scale = 1.0 + math.sin(time * 2) * 0.03
    local offsetY = math.sin(time * 1.5) * 4
    cy = cy + offsetY
    size = size * scale
    
    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    
    local s = size * 0.45
    
    -- 辅助函数：绘制闪电路径
    local function drawLightningPath()
        nvgBeginPath(nvg)
        -- 更锋利的闪电形状
        nvgMoveTo(nvg, s * 0.15, -s * 1.1)      -- 顶部
        nvgLineTo(nvg, -s * 0.55, -s * 0.05)    -- 左上折点
        nvgLineTo(nvg, -s * 0.05, -s * 0.05)    -- 中间凹槽左
        nvgLineTo(nvg, -s * 0.35, s * 1.1)      -- 底部尖端
        nvgLineTo(nvg, s * 0.55, s * 0.0)       -- 右下折点
        nvgLineTo(nvg, s * 0.05, s * 0.0)       -- 中间凹槽右
        nvgClosePath(nvg)
    end
    
    -- 外发光效果（多层模糊）
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
    
    -- 主体闪电（渐变效果）
    drawLightningPath()
    local grad = nvgLinearGradient(nvg, 0, -s * 1.1, 0, s * 1.1, 
        nvgRGBA(255, 255, 255, alpha), 
        nvgRGBA(220, 235, 255, alpha * 0.9))
    nvgFillPaint(nvg, grad)
    nvgFill(nvg)
    
    -- 高光边缘
    drawLightningPath()
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.5))
    nvgStrokeWidth(nvg, s * 0.04)
    nvgStroke(nvg)
    
    -- 内部高光（左上角）
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, s * 0.1, -s * 0.9)
    nvgLineTo(nvg, -s * 0.35, -s * 0.1)
    nvgLineTo(nvg, -s * 0.1, -s * 0.1)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.25))
    nvgFill(nvg)
    
    nvgRestore(nvg)
end

--- 绘制放大镜图标 (浏览房间)
local function DrawMagnifierIcon(nvg, cx, cy, size, alpha, time)
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
    nvgArc(nvg, 0, 0, glassR * 0.6, -2.5, -1.0, NVG_CW)
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

--- 绘制门+箭头图标 (加入中途局)
local function DrawDoorArrowIcon(nvg, cx, cy, size, alpha, time)
    local scale = 1.0 + math.sin(time * 2.2) * 0.05
    local offsetY = math.sin(time * 1.6) * 5
    cy = cy + offsetY
    size = size * scale
    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy)
    local s = size * 0.4

    -- Door frame
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

    -- Door fill (semi-transparent)
    nvgBeginPath(nvg)
    nvgRect(nvg, -s * 0.55, -s * 0.95, s * 0.8, s * 1.9)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.1))
    nvgFill(nvg)

    -- Door handle (small circle)
    nvgBeginPath(nvg)
    nvgCircle(nvg, s * 0.1, 0, s * 0.08)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgFill(nvg)

    -- Animated arrow entering the door
    local arrowShift = math.sin(time * 3) * s * 0.15
    local arrowX = -s * 1.1 + arrowShift
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, arrowX - s * 0.4, 0)
    nvgLineTo(nvg, arrowX, 0)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, alpha * 0.9))
    nvgStrokeWidth(nvg, s * 0.09)
    nvgLineCap(nvg, NVG_ROUND)
    nvgStroke(nvg)

    -- Arrow head
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

--- 绘制加号圆圈图标 (创建房间)
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
    nvgRoundedRect(nvg, -plusSize, -plusWidth/2, plusSize * 2, plusWidth, plusWidth/2)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, -plusWidth/2, -plusSize, plusWidth, plusSize * 2, plusWidth/2)
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

function GradientCard:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local w, h = l.w, l.h
    local x, y = l.x, l.y
    local r = self.props.borderRadius or 20
    local colors = self.colors_
    local time = self.animTime_
    
    if self.hovered_ then
        local glowSize = 20
        local glowAlpha = 60 + math.sin(time * 3) * 20
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - glowSize/2, y - glowSize/2, w + glowSize, h + glowSize, r + glowSize/2)
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
    nvgScissor(nvg, x, y, w, h)
    local iconX = x + w * 0.65
    local iconY = y + h * 0.6
    local iconSize = math.min(w, h) * 0.7
    local iconAlpha = self.hovered_ and 45 or 30
    if self.colorScheme_ == "blue" then
        DrawGamepadIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    elseif self.colorScheme_ == "green" or self.colorScheme_ == "cyan" then
        DrawMagnifierIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    elseif self.colorScheme_ == "orange" then
        DrawPlusCircleIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    elseif self.colorScheme_ == "purple" then
        DrawDoorArrowIcon(nvg, iconX, iconY, iconSize, iconAlpha, time)
    end
    nvgRestore(nvg)
    
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h * 0.5, r)
    local highlightPaint = nvgLinearGradient(nvg, x, y, x, y + h * 0.5,
        nvgRGBA(255, 255, 255, 40), nvgRGBA(255, 255, 255, 0))
    nvgFillPaint(nvg, highlightPaint)
    nvgFill(nvg)
    
    -- 从左到右的倾斜光效：只在鼠标悬停时显示
    if self.hovered_ then
        local shineOffset = (time * 0.3) % 2.5 - 0.5
        local shineX = x + w * shineOffset
        local shineWidth = w * 0.3
        local skew = h * 0.3
        
        nvgSave(nvg)
        
        -- 裁剪到卡片范围，留出圆角边距
        nvgScissor(nvg, x + r * 0.3, y + r * 0.3, w - r * 0.6, h - r * 0.6)
        
        -- 绘制倾斜平行四边形
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
    local borderAlpha = self.hovered_ and 100 or 50
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, borderAlpha))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)
    
    if self.pressed_ then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, y, w, h, r)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 40))
        nvgFill(nvg)
    end
    
    nvgSave(nvg)
    nvgScissor(nvg, x, y, w, h)
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

function GradientCard:OnMouseEnter() self.hovered_ = true end
function GradientCard:OnMouseLeave() self.hovered_ = false; self.pressed_ = false end
function GradientCard:OnPointerDown(event) if event and event:IsPrimaryAction() then self.pressed_ = true end end
function GradientCard:OnPointerUp(event) if event and event:IsPrimaryAction() then self.pressed_ = false end end
function GradientCard:OnClick() if self.props.onClick then self.props.onClick(self) end end
function GradientCard:IsStateful() return true end

-- ============================================================================
-- IconWidget - NanoVG 矢量图标组件 (内嵌组件)
-- ============================================================================

---@class IconWidget : Widget
local IconWidget = Widget:Extend("IconWidget")

function IconWidget:Init(props)
    props = props or {}
    props.width = props.width or 32
    props.height = props.height or 32
    self.iconType_ = props.icon or "exit"
    self.color_ = props.color or { 255, 255, 255, 255 }
    self.strokeWidth_ = props.strokeWidth or 2
    Widget.Init(self, props)
end

function IconWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local x, y, w, h = l.x, l.y, l.w, l.h
    local cx, cy = x + w/2, y + h/2
    local size = math.min(w, h)
    local color = self.color_
    local sw = self.strokeWidth_
    if self.iconType_ == "exit" then self:DrawExitIcon(nvg, cx, cy, size, color, sw)
    elseif self.iconType_ == "search" then self:DrawSearchIcon(nvg, cx, cy, size, color, sw)
    elseif self.iconType_ == "cancel" then self:DrawCancelIcon(nvg, cx, cy, size, color, sw)
    elseif self.iconType_ == "plus" then self:DrawPlusIcon(nvg, cx, cy, size, color, sw)
    elseif self.iconType_ == "back" then self:DrawBackIcon(nvg, cx, cy, size, color, sw)
    end
end

function IconWidget:DrawExitIcon(nvg, cx, cy, size, color, sw)
    local s = size * 0.4
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, sw)
    nvgLineCap(nvg, NVG_ROUND)
    nvgLineJoin(nvg, NVG_ROUND)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx + s * 0.2, cy - s)
    nvgLineTo(nvg, cx - s, cy - s)
    nvgLineTo(nvg, cx - s, cy + s)
    nvgLineTo(nvg, cx + s * 0.2, cy + s)
    nvgStroke(nvg)
    local arrowX = cx + s * 0.1
    local arrowLen = s * 0.9
    local arrowHead = s * 0.4
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, arrowX - arrowLen * 0.3, cy)
    nvgLineTo(nvg, arrowX + arrowLen * 0.7, cy)
    nvgMoveTo(nvg, arrowX + arrowLen * 0.3, cy - arrowHead)
    nvgLineTo(nvg, arrowX + arrowLen * 0.7, cy)
    nvgLineTo(nvg, arrowX + arrowLen * 0.3, cy + arrowHead)
    nvgStroke(nvg)
end

function IconWidget:DrawSearchIcon(nvg, cx, cy, size, color, sw)
    local r = size * 0.32
    local handleLen = size * 0.3
    local handleAngle = 0.785
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, sw * 1.5)
    nvgLineCap(nvg, NVG_ROUND)
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx - size * 0.08, cy - size * 0.08, r)
    nvgStroke(nvg)
    local hx1 = cx - size * 0.08 + r * 0.7 * math.cos(handleAngle)
    local hy1 = cy - size * 0.08 + r * 0.7 * math.sin(handleAngle)
    local hx2 = hx1 + handleLen * math.cos(handleAngle)
    local hy2 = hy1 + handleLen * math.sin(handleAngle)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, hx1, hy1)
    nvgLineTo(nvg, hx2, hy2)
    nvgStrokeWidth(nvg, sw * 2)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgArc(nvg, cx - size * 0.08, cy - size * 0.08, r * 0.6, -2.3, -1.2, NVG_CW)
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], (color[4] or 255) * 0.4))
    nvgStrokeWidth(nvg, sw)
    nvgStroke(nvg)
end

function IconWidget:DrawCancelIcon(nvg, cx, cy, size, color, sw)
    local s = size * 0.35
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, sw * 1.5)
    nvgLineCap(nvg, NVG_ROUND)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - s, cy - s)
    nvgLineTo(nvg, cx + s, cy + s)
    nvgMoveTo(nvg, cx + s, cy - s)
    nvgLineTo(nvg, cx - s, cy + s)
    nvgStroke(nvg)
end

function IconWidget:DrawPlusIcon(nvg, cx, cy, size, color, sw)
    local s = size * 0.35
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, sw * 1.5)
    nvgLineCap(nvg, NVG_ROUND)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy - s)
    nvgLineTo(nvg, cx, cy + s)
    nvgMoveTo(nvg, cx - s, cy)
    nvgLineTo(nvg, cx + s, cy)
    nvgStroke(nvg)
end

function IconWidget:DrawBackIcon(nvg, cx, cy, size, color, sw)
    local s = size * 0.35
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, sw * 1.5)
    nvgLineCap(nvg, NVG_ROUND)
    nvgLineJoin(nvg, NVG_ROUND)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx + s * 0.5, cy - s)
    nvgLineTo(nvg, cx - s * 0.5, cy)
    nvgLineTo(nvg, cx + s * 0.5, cy + s)
    nvgStroke(nvg)
end

-- ============================================================================
-- ImageWidget - NanoVG 图片组件 (内嵌组件)
-- ============================================================================

---@class ImageWidget : Widget
local ImageWidget = Widget:Extend("ImageWidget")

-- 图片缓存（避免重复加载）
local imageCache_ = {}

function ImageWidget:Init(props)
    props = props or {}
    props.width = props.width or 200
    props.height = props.height or 50
    self.src_ = props.src or ""
    self.imageHandle_ = nil
    self.imageLoaded_ = false
    Widget.Init(self, props)
end

function ImageWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local x, y, w, h = l.x, l.y, l.w, l.h
    
    -- 尝试加载图片（只加载一次）
    if not self.imageLoaded_ and self.src_ ~= "" then
        -- 检查缓存
        if imageCache_[self.src_] then
            self.imageHandle_ = imageCache_[self.src_]
            self.imageLoaded_ = true
        else
            -- 尝试加载图片
            local handle = nvgCreateImage(nvg, self.src_, 0)
            if handle and handle > 0 then
                self.imageHandle_ = handle
                imageCache_[self.src_] = handle
                self.imageLoaded_ = true
            else
                self.imageLoaded_ = true  -- 标记已尝试加载，避免重复尝试
            end
        end
    end
    
    -- 渲染图片
    if self.imageHandle_ and self.imageHandle_ > 0 then
        local imgPaint = nvgImagePattern(nvg, x, y, w, h, 0, self.imageHandle_, 1)
        nvgBeginPath(nvg)
        nvgRect(nvg, x, y, w, h)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    end
end

-- ============================================================================
-- PulsingCircles Widget (内嵌组件)
-- 简洁的同心圆向外扩散效果
-- ============================================================================

---@class PulsingCircles : Widget
local PulsingCircles = Widget:Extend("PulsingCircles")

function PulsingCircles:Init(props)
    props = props or {}
    props.width = props.width or 280
    props.height = props.height or 280
    self.color_ = props.color or { 51, 153, 255 }
    self.ringCount_ = props.ringCount or 3
    self.animTime_ = 0
    Widget.Init(self, props)
end

function PulsingCircles:Update(dt)
    self.animTime_ = self.animTime_ + dt
end

function PulsingCircles:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local cx, cy = l.x + l.w / 2, l.y + l.h / 2
    local maxRadius = math.min(l.w, l.h) / 2
    local time = self.animTime_
    local color = self.color_
    
    -- 向外扩散的同心圆（慢节奏）
    for i = 1, self.ringCount_ do
        local phase = (i - 1) / self.ringCount_
        local progress = (time * 0.15 + phase) % 1.0  -- 更慢的速度
        local radius = maxRadius * 0.3 + maxRadius * 0.7 * progress
        local alpha = (1.0 - progress) * 0.6
        
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, radius)
        nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], alpha * 255))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end
end

function PulsingCircles:IsStateful() return true end

-- ============================================================================
-- AnimatedSearchIcon Widget (内嵌组件)
-- 简洁的放大镜图标（呼吸动画）
-- ============================================================================

---@class AnimatedSearchIcon : Widget
local AnimatedSearchIcon = Widget:Extend("AnimatedSearchIcon")

function AnimatedSearchIcon:Init(props)
    props = props or {}
    props.width = props.width or 86
    props.height = props.height or 86
    self.color_ = props.color or { 255, 255, 255, 255 }
    self.strokeWidth_ = props.strokeWidth or 4
    self.animTime_ = 0
    Widget.Init(self, props)
end

function AnimatedSearchIcon:Update(dt)
    self.animTime_ = self.animTime_ + dt
end

function AnimatedSearchIcon:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local cx, cy = l.x + l.w/2, l.y + l.h/2
    local size = math.min(l.w, l.h)
    local color = self.color_
    local sw = self.strokeWidth_
    local time = self.animTime_
    
    -- 放大镜绕圆心公转（自身不旋转）
    local orbitAngle = time * 0.8  -- 公转速度
    local orbitRadius = size * 0.08  -- 公转半径（小幅度）
    local offsetX = math.cos(orbitAngle) * orbitRadius
    local offsetY = math.sin(orbitAngle) * orbitRadius
    
    -- 放大镜中心位置
    local magCx = cx + offsetX
    local magCy = cy + offsetY
    
    -- 放大镜参数
    local r = size * 0.3
    local handleLen = size * 0.28
    local handleAngle = 0.785  -- 45度（手柄方向固定）
    
    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgLineCap(nvg, NVG_ROUND)
    
    -- 圆圈
    nvgBeginPath(nvg)
    nvgCircle(nvg, magCx, magCy, r)
    nvgStrokeWidth(nvg, sw * 1.5)
    nvgStroke(nvg)
    
    -- 手柄（方向固定为45度）
    local hx1 = magCx + r * 0.75 * math.cos(handleAngle)
    local hy1 = magCy + r * 0.75 * math.sin(handleAngle)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, hx1, hy1)
    nvgLineTo(nvg, hx1 + handleLen * math.cos(handleAngle), hy1 + handleLen * math.sin(handleAngle))
    nvgStrokeWidth(nvg, sw * 2)
    nvgStroke(nvg)
end

function AnimatedSearchIcon:IsStateful() return true end

-- ============================================================================
-- LobbyUI 主模块
-- ============================================================================

local LobbyUI = {}

-- ============================================================================
-- Constants and default configuration
-- ============================================================================

-- 服务端封禁错误码（Lobby 的 MatchErrorCode.M_PLAYER_BANNED / GameStartErrorCode.SG_PLAYER_BANNED）。
-- 玩家被游戏运维后台封禁后，匹配 / 开局 / 中途加入都会收到对应码。
LobbyUI.MATCH_ERROR_PLAYER_BANNED = 11
LobbyUI.GAME_START_ERROR_PLAYER_BANNED = 14
LobbyUI.PLAYER_BANNED_MESSAGE = _tr("t_8fBGgKN08EbME96K")

local DEFAULT_CONFIG = {
    mapName = nil,                -- Will use LobbyManager:GetProjectId() if not specified
    maxPlayers = nil,             -- Will use LobbyManager:GetMaxPlayers() if not specified, fallback to 4
    mode = "pvp",
    theme = "light",              -- "light" or "dark"
    debugMode = false,
    allowCreateRoom = true,       -- Allow room creation
    allowQuickMatch = true,       -- Allow quick match
    allowBrowseRooms = true,      -- Allow browsing rooms
    autoRefresh = true,           -- Auto refresh room list
    refreshInterval = 5000,       -- Refresh interval (milliseconds)

    -- Match info configuration (for matchmaking)
    matchDescName = "free_match_with_ai", -- 匹配模式描述名
    modeId = "pvp",               -- 自定义模式 ID
}

-- Theme configuration (using {r, g, b, a} format for UI library compatibility)
local THEMES = {
    light = {
        primary = { 51, 153, 255, 255 },       -- rgb(0.2, 0.6, 1.0)
        secondary = { 128, 128, 128, 255 },    -- rgb(0.5, 0.5, 0.5)
        background = { 242, 242, 242, 255 },   -- rgb(0.95, 0.95, 0.95)
        surface = { 255, 255, 255, 255 },      -- rgb(1.0, 1.0, 1.0)
        text = { 26, 26, 26, 255 },            -- rgb(0.1, 0.1, 0.1)
        textSecondary = { 128, 128, 128, 255 },-- rgb(0.5, 0.5, 0.5)
        border = { 204, 204, 204, 255 },       -- rgb(0.8, 0.8, 0.8)
        success = { 51, 204, 77, 255 },        -- rgb(0.2, 0.8, 0.3)
        warning = { 255, 179, 0, 255 },        -- rgb(1.0, 0.7, 0.0)
        error = { 255, 77, 77, 255 },          -- rgb(1.0, 0.3, 0.3)
    },
    dark = {
        primary = { 77, 179, 255, 255 },       -- rgb(0.3, 0.7, 1.0)
        secondary = { 153, 153, 153, 255 },    -- rgb(0.6, 0.6, 0.6)
        background = { 38, 38, 38, 255 },      -- rgb(0.15, 0.15, 0.15)
        surface = { 51, 51, 51, 255 },         -- rgb(0.2, 0.2, 0.2)
        text = { 242, 242, 242, 255 },         -- rgb(0.95, 0.95, 0.95)
        textSecondary = { 179, 179, 179, 255 },-- rgb(0.7, 0.7, 0.7)
        border = { 77, 77, 77, 255 },          -- rgb(0.3, 0.3, 0.3)
        success = { 77, 230, 102, 255 },       -- rgb(0.3, 0.9, 0.4)
        warning = { 255, 204, 51, 255 },       -- rgb(1.0, 0.8, 0.2)
        error = { 255, 102, 102, 255 },        -- rgb(1.0, 0.4, 0.4)
    }
}

-- Input validation constants
local MIN_MAX_PLAYERS = 1
local MAX_MAX_PLAYERS = 16

-- ============================================================================
-- LobbyUI instance
-- ============================================================================

local LobbyUIInstance = {
    root = nil,
    lobbyMgr = nil,
    config = nil,
    theme = nil,
    currentView = nil,
    roomListData = {},
    refreshTimer = 0,
    eventSubscriptions = {},  -- Track event subscriptions for cleanup
    autoRefreshTimer = 0,     -- Auto refresh timer
}

-- ============================================================================
-- Helper functions
-- ============================================================================

local function Log(msg)
    if LobbyUIInstance.config and LobbyUIInstance.config.debugMode then
        print("[LobbyUI] " .. msg)
    end
end

--- Simple JSON decoder for parsing JSON strings to Lua tables
--- @param str string JSON string to decode
--- @return any Decoded value
local function jsonDecode(str)
    if not str or str == "" then
        return nil
    end

    local pos = 1
    local len = #str

    local function skipWhitespace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
                pos = pos + 1
            else
                break
            end
        end
    end

    local function parseValue()
        skipWhitespace()
        if pos > len then return nil end

        local c = str:sub(pos, pos)

        if c == '"' then
            -- Parse string
            pos = pos + 1
            local startPos = pos
            local result = ""
            while pos <= len do
                local ch = str:sub(pos, pos)
                if ch == '"' then
                    pos = pos + 1
                    return result
                elseif ch == '\\' then
                    pos = pos + 1
                    local escaped = str:sub(pos, pos)
                    if escaped == 'n' then result = result .. '\n'
                    elseif escaped == 'r' then result = result .. '\r'
                    elseif escaped == 't' then result = result .. '\t'
                    elseif escaped == '"' then result = result .. '"'
                    elseif escaped == '\\' then result = result .. '\\'
                    else result = result .. escaped
                    end
                    pos = pos + 1
                else
                    result = result .. ch
                    pos = pos + 1
                end
            end
            return result
        elseif c == '{' then
            -- Parse object
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            while pos <= len do
                skipWhitespace()
                local key = parseValue()
                skipWhitespace()
                if str:sub(pos, pos) == ':' then
                    pos = pos + 1
                end
                local value = parseValue()
                obj[key] = value
                skipWhitespace()
                local sep = str:sub(pos, pos)
                if sep == ',' then
                    pos = pos + 1
                elseif sep == '}' then
                    pos = pos + 1
                    return obj
                else
                    break
                end
            end
            return obj
        elseif c == '[' then
            -- Parse array
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while pos <= len do
                local value = parseValue()
                table.insert(arr, value)
                skipWhitespace()
                local sep = str:sub(pos, pos)
                if sep == ',' then
                    pos = pos + 1
                elseif sep == ']' then
                    pos = pos + 1
                    return arr
                else
                    break
                end
            end
            return arr
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif c == '-' or (c >= '0' and c <= '9') then
            -- Parse number
            local numStr = ""
            while pos <= len do
                local ch = str:sub(pos, pos)
                if ch == '-' or ch == '+' or ch == '.' or ch == 'e' or ch == 'E' or (ch >= '0' and ch <= '9') then
                    numStr = numStr .. ch
                    pos = pos + 1
                else
                    break
                end
            end
            return tonumber(numStr)
        end

        return nil
    end

    return parseValue()
end

local function ParseRoomList(data)
    -- Parse room list data
    if not data or data == "" then
        return {}
    end

    -- Debug: print raw data
    print("[LobbyUI] ParseRoomList raw data: " .. tostring(data):sub(1, 200))

    local success, rooms = pcall(function()
        return jsonDecode(data)
    end)

    if not success then
        Log("Failed to parse room list: " .. tostring(rooms))
        return {}
    end

    -- Ensure we always return a table (array)
    if type(rooms) ~= "table" then
        print("[LobbyUI] ParseRoomList: result is not a table, got " .. type(rooms))
        return {}
    end

    print("[LobbyUI] ParseRoomList: got " .. #rooms .. " rooms")
    return rooms
end

-- Validate max players input
local function ValidateMaxPlayers(value)
    local num = tonumber(value)
    if not num then
        return false, "Invalid number"
    end
    if num < MIN_MAX_PLAYERS or num > MAX_MAX_PLAYERS then
        return false, string.format("Must be between %d and %d", MIN_MAX_PLAYERS, MAX_MAX_PLAYERS)
    end
    return true, num
end

-- Format number as integer string (removes .0 suffix)
local function FormatInt(num)
    if num == nil then return "0" end
    return string.format("%d", math.floor(num))
end

-- Clean up event subscriptions
local function CleanupEventSubscriptions()
    for _, subscription in ipairs(LobbyUIInstance.eventSubscriptions) do
        if subscription then
            UnsubscribeFromEvent(subscription)
        end
    end
    LobbyUIInstance.eventSubscriptions = {}
end

-- Subscribe to event and track it
local function TrackEventSubscription(eventName, callback)
    local subscription = SubscribeToEvent(eventName, callback)
    table.insert(LobbyUIInstance.eventSubscriptions, subscription)
    return subscription
end

-- ============================================================================
-- UI building functions
-- ============================================================================

-- Forward declarations
local CreateMainView
local CreateMatchingView
local CreateRoomBrowserView
local CreateRoomDetailView
local CreateCreateRoomDialog
local CreateServerProgressView
local ShowMatchFoundDialog
local ShowErrorDialog
local StartGameFromRoom
local ConnectToGameServer
local CreateTopBar

-- Server progress view state
local serverProgressState = {
    view = nil,
    progressBar = nil,
    progressLabel = nil,
    statusLabel = nil,
}

--- 创建通用顶部栏（与大厅一致）
--- @param options table|nil 配置选项
---   - showBackButton: boolean 是否显示返回按钮（默认 false）
---   - onBack: function 返回按钮点击回调
---   - rightContent: Widget 右侧自定义内容（替代退出按钮）
--- @return Widget topBar, function updateStatus
CreateTopBar = function(options)
    options = options or {}

    -- 顶部条
    local topBar = UI.Panel {
        width = "100%",
        height = 190,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "flex-start",
        paddingLeft = 43,
        paddingRight = 43,
        paddingTop = 34,
        paddingBottom = 34,
    }

    -- 左侧：根据配置决定内容（退出/返回按钮）
    if options.hideRightButton then
        -- 添加占位符保持布局（与右侧占位一致）
        topBar:AddChild(UI.Panel {
            width = 120,
            height = 50,
        })
    elseif options.showBackButton then
        -- 返回按钮样式选择
        local buttonText = options.buttonText or _tr("t_qNlgG5bPpwC8vWgM")
        local useGhostStyle = options.ghostStyle ~= false  -- 默认使用幽灵样式
        local useOutlinedStyle = options.outlinedStyle == true  -- 描边样式（用于"离开"）
        
        local backBtn
        if useOutlinedStyle then
            -- 描边样式（用于"离开房间"等）
            backBtn = UI.Button {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 8,
                paddingLeft = 20,
                paddingRight = 20,
                paddingTop = 12,
                paddingBottom = 12,
                backgroundColor = { 0, 0, 0, 0 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 200, 120, 120, 100 },
                onClick = function()
                    if options.onBack then
                        options.onBack()
                    else
                        CreateMainView()
                    end
                end
            }
            topBar:AddChild(backBtn)

            backBtn:AddChild(IconWidget {
                width = 20,
                height = 20,
                icon = "exit",
                color = { 200, 120, 120, 200 },
                strokeWidth = 2,
            })

            backBtn:AddChild(UI.Label {
                text = buttonText,
                fontSize = 18,
                fontColor = { 200, 120, 120, 200 },
            })
        elseif useGhostStyle then
            -- 幽灵样式（低调返回按钮，放大尺寸）
            backBtn = UI.Button {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 10,
                paddingLeft = 16,
                paddingRight = 24,
                paddingTop = 12,
                paddingBottom = 12,
                minWidth = 120,
                minHeight = 50,
                backgroundColor = { 0, 0, 0, 0 },
                borderRadius = 12,
                onClick = function()
                    Log("Back button clicked")
                    if options.onBack then
                        options.onBack()
                    else
                        CreateMainView()
                    end
                end
            }
            topBar:AddChild(backBtn)

            backBtn:AddChild(IconWidget {
                width = 24,
                height = 24,
                icon = "back",
                color = { 180, 180, 200, 220 },
                strokeWidth = 3,
            })

            backBtn:AddChild(UI.Label {
                text = buttonText,
                fontSize = 20,
                fontColor = { 180, 180, 200, 220 },
            })
        else
            -- 原红色样式
            backBtn = UI.Button {
                width = 221,
                height = 72,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 2,
                backgroundColor = '#A71B0051',
                borderRadius = 36,
                borderWidth = 3,
                borderColor = '#BF878722',
                onClick = function()
                    if options.onBack then
                        options.onBack()
                    else
                        CreateMainView()
                    end
                end
            }
            topBar:AddChild(backBtn)

            backBtn:AddChild(IconWidget {
                width = 38,
                height = 38,
                icon = "exit",
                color = { 255, 61, 61, 255 },
                strokeWidth = 2.5,
            })

            backBtn:AddChild(UI.Label {
                text = buttonText,
                fontSize = 32,
                fontWeight = "bold",
                fontColor = '#FF3D3D',
            })
        end
    else
        -- 默认退出按钮
        local exit_ui = UI.Button {
            width = 221,
            height = 72,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 2,
            backgroundColor = '#A71B0051',
            borderRadius = 36,
            borderWidth = 3,
            borderColor = '#BF878722',
            onClick = function()
                LobbyUI.Hide()
            end
        }
        topBar:AddChild(exit_ui)

        exit_ui:AddChild(IconWidget {
            width = 38,
            height = 38,
            icon = "exit",
            color = { 255, 61, 61, 255 },
            strokeWidth = 2.5,
        })

        exit_ui:AddChild(UI.Label {
            text = _tr("t_10lhwdNB510ct1Qukc"),
            fontSize = 32,
            fontWeight = "bold",
            fontColor = '#FF3D3D',
        })
    end

    -- 中间区域：用于居中显示页面标题或玩家信息
    local centerArea = UI.Panel {
        flexGrow = 1,
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
    }
    topBar:AddChild(centerArea)

    -- 如果有页面标题，在 centerArea 中显示
    if options.pageTitle then
        centerArea:AddChild(UI.Label {
            text = options.pageTitle,
            fontSize = 24,
            fontWeight = "bold",
            fontColor = { 255, 255, 255, 255 },
        })
    end

    -- 用户信息卡片（如果没有页面标题则显示）
    local userCard = UI.Panel {
        flexDirection = "row",
        minWidth = 400,
        height = 104,
        alignItems = "center",
        backgroundColor = '#292B30',
        borderColor = '#FFFFFF21',
        borderWidth = 1,
        borderRadius = 52,
        paddingLeft = 15,
        paddingRight = 20,
        paddingTop = 15,
        paddingBottom = 15,
        gap = 15,
    }

    -- 头像容器（圆形）
    local avatarContainer = UI.Panel {
        width = 74,
        height = 74,
        borderRadius = 37,
        backgroundColor = { 200, 220, 240, 255 },
        alignItems = "center",
        justifyContent = "center",
        overflow = "hidden",
    }
    avatarContainer:AddChild(UI.Label {
        text = " ",
        fontSize = 32,
        fontWeight = "bold",
    })
    userCard:AddChild(avatarContainer)

    -- 用户信息（昵称、ID、状态）
    local userInfo = UI.Panel {
        flexDirection = "column",
        gap = 2,
        height = 104,
    }

    local userId = LobbyUIInstance.lobbyMgr:GetMyUserId()

    -- 昵称行（最上面）
    local nicknameLabel = UI.Label {
        height = 36,
        text = _tr("t_19DCzy20319fRYubAY"),
        fontSize = 28,
        fontWeight = "bold",
        color = { 255, 255, 255, 255 },
    }
    userInfo:AddChild(nicknameLabel)

    -- 异步查询昵称
    LobbyUIInstance.lobbyMgr:GetUserNickname({
        userIds = { userId },
        onSuccess = function(nicknames)
            if nicknames and #nicknames > 0 then
                local nickname = nicknames[1].nickname or ""
                if nickname == "" then
                    nickname = _tr("t_18zuRw7Pt18rnE6t2m")
                end
                nicknameLabel:SetText(nickname)
            end
        end,
        onError = function(errorCode)
            nicknameLabel:SetText(_tr("t_18zuRw7Pt18rnE6t2m"))
        end
    })

    -- ID行（中间）
    userInfo:AddChild(UI.Label {
        height = 28,
        text = "ID: " .. FormatInt(userId),
        fontSize = 20,
        color = { 180, 180, 200, 255 },
    })

    -- 在线状态行（最下面）
    local statusRow = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 3,
        height = 26,
    }

    local statusDot = UI.Panel {
        width = 14,
        height = 14,
        borderRadius = 7,
        backgroundColor = { 76, 217, 100, 255 },
        borderColor = '#ffffff',
        borderWidth = 1,
    }
    statusRow:AddChild(statusDot)

    local statusLabel = UI.Label {
        text = _tr("t_TC8HGd5dSlEt59E0"),
        fontSize = 18,
        color = { 76, 217, 100, 255 },
    }
    statusRow:AddChild(statusLabel)

    userInfo:AddChild(statusRow)
    userCard:AddChild(userInfo)
    
    -- 只在没有页面标题时显示用户信息卡片
    if not options.pageTitle then
        centerArea:AddChild(userCard)
    end

    -- 右侧占位（与左侧按钮宽度匹配，保持标题居中）
    topBar:AddChild(UI.Panel {
        width = 120,
        height = 50,
    })

    -- 更新状态函数
    local function updateStatus()
        local isOnline = LobbyUIInstance.lobbyMgr:IsOnline()
        local isInRoom = LobbyUIInstance.lobbyMgr:IsInRoom()
        local isMatching = LobbyUIInstance.lobbyMgr:IsMatching()

        if isOnline then
            statusDot.backgroundColor = { 76, 217, 100, 255 }
            statusLabel.color = { 76, 217, 100, 255 }
        else
            statusDot.backgroundColor = { 255, 80, 80, 255 }
            statusLabel.color = { 255, 80, 80, 255 }
        end

        local statusTexts = {}
        if isOnline then
            table.insert(statusTexts, _tr("t_QXpKdJYYQPYgvCTz"))
        else
            table.insert(statusTexts, _tr("t_Rr1DCfnQRgKalIOL"))
        end

        if isInRoom then
            table.insert(statusTexts, _tr("t_oaiAoxPHp4i2BKLK"))
        end

        if isMatching then
            table.insert(statusTexts, _tr("t_WP2RNoJGVwrMSVxD"))
        end

        statusLabel:SetText(table.concat(statusTexts, " | "))
    end

    return topBar, updateStatus
end

--- Create main interface
CreateMainView = function()
    Log("Creating main view")

    local theme = LobbyUIInstance.theme
    local config = LobbyUIInstance.config

    -- ========== 渐变背景 ==========
    local view = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        -- 渐变深色背景
        backgroundColor = { 32, 36, 48, 255 },  -- 基础深色
    }

    -- ========== 顶部区域（Logo + 用户信息）==========
    local topSection = UI.Panel {
        width = "100%",
        maxHeight = "40%",
        minHeight = 220,
        flexShrink = 1,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "flex-end",
        paddingTop = 60,
        gap = 4,
    }

    -- TapTapMaker Logo（图片版本 - 保持原始宽高比 2:1）
    local hasIntl = HasAppArgv and HasAppArgv("intl")
    local revisionArg = GetAppArgv and GetAppArgv("game_revision") or ""
    local useIntlLogo = hasIntl or revisionArg == "intl"
    local logoImage = ImageWidget {
        width = 400,
        height = 200,
        src = useIntlLogo and "Textures/LogoLargeIntl.png" or "Textures/LogoLarge.png",
    }
    topSection:AddChild(logoImage)

    -- 用户信息卡片（胶囊形）
    local userCard = UI.Panel {
        flexDirection = "row",
        width = 280,
        height = 80,
        alignItems = "center",
        backgroundColor = { 40, 45, 60, 180 },
        borderColor = { 80, 100, 140, 80 },
        borderWidth = 1,
        borderRadius = 40,
        paddingLeft = 10,
        paddingRight = 16,
        gap = 12,
    }

    -- 头像容器（圆形，蓝色发光边框）
    local avatarContainer = UI.Panel {
        width = 56,
        height = 56,
        borderRadius = 28,
        backgroundColor = { 200, 220, 240, 255 },
        borderColor = { 80, 160, 255, 255 },  -- 蓝色发光边框
        borderWidth = 3,
        alignItems = "center",
        justifyContent = "center",
        overflow = "hidden",
    }
    avatarContainer:AddChild(UI.Label {
        text = " ",
        fontSize = 28,
        fontWeight = "bold",
    })
    userCard:AddChild(avatarContainer)

    -- 用户信息（昵称、ID、状态）
    local userInfo = UI.Panel {
        flexDirection = "column",
        gap = 1,
    }

    local userId = LobbyUIInstance.lobbyMgr:GetMyUserId()

    -- 昵称行（最上面）
    local nicknameLabel = UI.Label {
        text = _tr("t_19DCzy20319fRYubAY"),
        fontSize = 15,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
    }
    userInfo:AddChild(nicknameLabel)

    -- 异步查询昵称
    LobbyUIInstance.lobbyMgr:GetUserNickname({
        userIds = { userId },
        onSuccess = function(nicknames)
            if nicknames and #nicknames > 0 then
                local nickname = nicknames[1].nickname or ""
                if nickname == "" then
                    nickname = _tr("t_18zuRw7Pt18rnE6t2m")
                end
                nicknameLabel:SetText(nickname)
            end
        end,
        onError = function(errorCode)
            nicknameLabel:SetText(_tr("t_18zuRw7Pt18rnE6t2m"))
        end
    })

    -- ID行（中间）
    userInfo:AddChild(UI.Label {
        text = "ID: " .. FormatInt(userId),
        fontSize = 12,
        fontColor = { 180, 180, 200, 255 },
    })

    -- 在线状态行（最下面）
    local statusRow = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
    }

    local statusDot = UI.Panel {
        width = 8,
        height = 8,
        borderRadius = 4,
        backgroundColor = { 50, 220, 100, 255 },
    }
    statusRow:AddChild(statusDot)

    local statusLabel = UI.Label {
        text = _tr("t_QXpKdJYYQPYgvCTz"),
        fontSize = 11,
        fontColor = { 80, 220, 130, 255 },
    }
    statusRow:AddChild(statusLabel)

    userInfo:AddChild(statusRow)
    userCard:AddChild(userInfo)
    topSection:AddChild(userCard)

    view:AddChild(topSection)

    -- 卡片配置（使用 NanoVG 渐变绘制）
    local cardConfigs = {
        {
            text = _tr("t_3oLGvfnU4GMMCbw1"),
            description = _tr("t_a4k9RVz3Zc3QWCtY"),
            icon = " ",
            colorScheme = "blue",
            decorIcon = " ",
            enabled = config.allowQuickMatch,
            onClick = CreateMatchingView,
            isRecommended = false,  -- 不显示推荐标签
        },
        {
            text = _tr("t_oOFMYbK1oFxYSyYu"),
            description = _tr("t_YLzALCVKYpx0Vx95"),
            icon = " ",
            colorScheme = "cyan",  -- 使用青色系
            decorIcon = " ",
            enabled = config.allowBrowseRooms,
            onClick = CreateRoomBrowserView,
            isRecommended = false,
        },
        {
            text = _tr("t_1DSgBSUmlo9AcDt"),
            description = _tr("t_XaPZdHvhX6y0KoVY"),
            icon = " ",
            colorScheme = "orange",
            decorIcon = " ",
            enabled = config.allowCreateRoom,
            onClick = function()
                -- 直接使用默认值创建房间，不弹框
                local mapName = config.mapName
                if not mapName or mapName == "" then
                    local projectId = LobbyUIInstance.lobbyMgr:GetProjectId()
                    mapName = (projectId and projectId ~= "") and projectId or "DefaultMap"
                end

                local maxPlayers = config.maxPlayers
                if not maxPlayers or maxPlayers <= 0 then
                    local fromLobbyMgr = LobbyUIInstance.lobbyMgr:GetMaxPlayers()
                    maxPlayers = (fromLobbyMgr and fromLobbyMgr > 0) and fromLobbyMgr or 4
                end

                Log("Creating room with defaults: " .. mapName .. ", max players: " .. maxPlayers)

                LobbyUIInstance.lobbyMgr:CreateRoom({
                    mapName = mapName,
                    maxPlayers = maxPlayers,
                    mode = config.mode,
                    onSuccess = function(roomId)
                        Log("Room created: " .. roomId .. ", maxPlayers: " .. maxPlayers)
                        CreateRoomDetailView(roomId, nil, maxPlayers)
                    end,
                    onError = function(errorCode)
                        Log("Failed to create room: " .. FormatInt(errorCode))
                        ShowErrorDialog("Failed to create room: " .. FormatInt(errorCode))
                    end
                })
            end,
            isRecommended = false,
        },
    }

    -- 统计启用的卡片数量，动态计算容器 maxWidth
    local cardWidth = 300
    local cardGap = 30
    local containerPaddingH = 144
    local enabledCount = 0
    for _, c in ipairs(cardConfigs) do
        if c.enabled then enabledCount = enabledCount + 1 end
    end
    -- maxWidth = N×卡片宽 + (N-1)×gap + 左右padding，一行刚好放下所有卡片
    local containerMaxWidth = enabledCount * cardWidth + math.max(0, enabledCount - 1) * cardGap + containerPaddingH * 2

    -- ========== 主内容区域（卡片容器，填充剩余空间）==========
    local cardSection = UI.Panel {
        width = "100%",
        flexGrow = 1,
        alignItems = "center",
        justifyContent = "center",
    }

    -- 卡片容器
    local contentArea = UI.Panel {
        width = "100%",
        maxWidth = containerMaxWidth,
        minHeight = 100,
        maxHeight = 400,
        flexGrow = 1,
        flexDirection = "row",
        flexWrap = "wrap",
        alignItems = "stretch",   -- wrapper 撑满行高
        justifyContent = "center",
        alignContent = "stretch", -- 行撑满容器高度
        gap = cardGap,
        paddingLeft = containerPaddingH,
        paddingRight = containerPaddingH,
        paddingTop = cardGap * 0.5,
        paddingBottom = cardGap * 0.5,
    }

    cardSection:AddChild(contentArea)

    for _, cardConfig in ipairs(cardConfigs) do
        if cardConfig.enabled then
            -- wrapper：撑满行高，内部居中卡片
            local cardWrapper = UI.Panel {
                width = 300,
                minWidth = 300,
                flexGrow = 1,
                flexShrink = 1,
                justifyContent = "center", -- 卡片超过 maxHeight 时垂直居中
            }

            -- 卡片：flexGrow 撑满 wrapper，maxHeight 封顶，flexShrink 可压缩
            local card = GradientCard {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                maxHeight = 360,
                colorScheme = cardConfig.colorScheme,
                borderRadius = 24,
                flexDirection = "column",
                alignItems = "flex-start",
                paddingLeft = 24,
                paddingRight = 24,
                overflow = "hidden",
                onClick = cardConfig.onClick,
            }

            -- "推荐" 角标
            if cardConfig.isRecommended then
                local badge = UI.Panel {
                    position = "absolute",
                    top = 16,
                    right = 16,
                    backgroundColor = { 255, 200, 60, 255 },
                    borderRadius = 10,
                    paddingLeft = 10,
                    paddingRight = 10,
                    paddingTop = 4,
                    paddingBottom = 4,
                }
                badge:AddChild(UI.Label {
                    text = _tr("t_kbDI3wUOkTbzppAb"),
                    fontSize = 11,
                    fontWeight = "bold",
                    color = { 40, 35, 20, 255 },
                })
                card:AddChild(badge)
            end

            -- 顶部弹性空间（代替 padding + justifyContent=flex-end，可被压缩）
            card:AddChild(UI.Panel {
                minHeight = 4,
                flexGrow = 1,
                flexShrink = 1,
            })

            -- 底部内容区
            card:AddChild(UI.Label {
                text = cardConfig.text,
                fontSize = 22,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 }
            })

            -- 标题与描述之间的间距（最大8，可被压缩）
            card:AddChild(UI.Panel {
                minHeight = 2,
                maxHeight = 8,
                flexGrow = 1,
                flexShrink = 1,
            })

            card:AddChild(UI.Label {
                text = cardConfig.description,
                fontSize = 13,
                fontColor = { 255, 255, 255, 160 }
            })

            -- 底部间距（最大24，可被压缩）
            card:AddChild(UI.Panel {
                minHeight = 4,
                maxHeight = 24,
                flexGrow = 1,
                flexShrink = 1,
            })

            cardWrapper:AddChild(card)
            contentArea:AddChild(cardWrapper)
        end
    end

    view:AddChild(cardSection)

    -- ========== 底部区域（退出按钮，固定高度，底部对齐）==========
    local bottomSection = UI.Panel {
        width = "100%",
        -- flexGrow = 1,
        flexShrink = 1,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "flex-end",
        paddingTop = 8,
        paddingBottom = 32,
    }

    -- 低调的退出按钮（文字样式）
    local exitButton = UI.Button {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 8,
        paddingLeft = 24,
        paddingRight = 24,
        paddingTop = 0,
        paddingBottom = 12,
        borderRadius = 8,
        backgroundColor = { 0, 0, 0, 0 },  -- 透明
        onClick = function()
            engine:Exit()
        end
    }

    exitButton:AddChild(IconWidget {
        width = 18,
        height = 18,
        icon = "exit",
        color = { 255, 80, 80, 255 },  -- 红色图标
        strokeWidth = 2,
    })

    exitButton:AddChild(UI.Label {
        text = _tr("t_lQr2vOEgkyF2NQ6R"),
        fontSize = 14,
        fontColor = { 255, 255, 255, 255 },  -- 白色文字
    })

    bottomSection:AddChild(exitButton)
    view:AddChild(bottomSection)

    -- Update status
    local function UpdateStatus()
        local isOnline = LobbyUIInstance.lobbyMgr:IsOnline()
        local isInRoom = LobbyUIInstance.lobbyMgr:IsInRoom()
        local isMatching = LobbyUIInstance.lobbyMgr:IsMatching()

        -- 更新状态点颜色
        if isOnline then
            statusDot.backgroundColor = { 50, 220, 100, 255 }
            statusLabel.color = { 80, 220, 130, 255 }
        else
            statusDot.backgroundColor = { 255, 80, 80, 255 }
            statusLabel.color = { 255, 80, 80, 255 }
        end

        -- 更新状态文字
        local statusTexts = {}
        if isOnline then
            table.insert(statusTexts, _tr("t_QXpKdJYYQPYgvCTz"))
        else
            table.insert(statusTexts, _tr("t_Rr1DCfnQRgKalIOL"))
        end

        if isInRoom then
            table.insert(statusTexts, _tr("t_oaiAoxPHp4i2BKLK"))
        end

        if isMatching then
            table.insert(statusTexts, _tr("t_WP2RNoJGVwrMSVxD"))
        end

        statusLabel:SetText(table.concat(statusTexts, " | "))
    end

    -- Subscribe to Update event and track it
    TrackEventSubscription("Update", function()
        UpdateStatus()
    end)

    -- Switch to main view
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view

    return view
end

--- Create matching waiting interface
CreateMatchingView = function()
    Log("Starting quick match")

    local theme = LobbyUIInstance.theme
    local config = LobbyUIInstance.config
    local matchStartTime = os.time()  -- 记录开始时间

    -- 设计分辨率（在此尺寸下内容布局完美）
    local designW = 600
    local designH = 850

    -- 外层容器：撑满屏幕，居中显示缩放后的 view
    local wrapper = UI.Panel {
        width = "100%",
        height = "100%",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 45, 47, 53, 255 },
    }

    -- 内层 view：固定设计尺寸，通过 scale contain 到屏幕内
    local view = UI.Panel {
        width = designW,
        height = designH,
        flexDirection = "column",
        backgroundColor = { 45, 47, 53, 255 },
    }
    wrapper:AddChild(view)

    -- ========== 顶部栏（带页面标题）==========
    local topBar, updateStatus = CreateTopBar({
        hideRightButton = true,
        pageTitle = _tr("t_3oLGvfnU4GMMCbw1"),
    })
    view:AddChild(topBar)

    -- 订阅 Update 事件更新状态
    TrackEventSubscription("Update", function()
        updateStatus()
    end)

    -- ========== 主内容区域 ==========
    local contentArea = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        padding = 20,
    }

    -- 搜索图标容器（包含动画圆形背景）
    local searchContainer = UI.Panel {
        width = 280,
        height = 280,
        alignItems = "center",
        justifyContent = "center",
        marginBottom = 30,
    }

    -- 动态脉冲圆圈背景（规则的同心圆扩散效果）
    searchContainer:AddChild(PulsingCircles {
        position = "absolute",
        width = 280,
        height = 280,
        color = { 51, 153, 255 },
        ringCount = 4,
    })

    -- 搜索图标（带动画效果）
    searchContainer:AddChild(AnimatedSearchIcon {
        width = 86,
        height = 86,
        color = { 255, 255, 255, 255 },
        strokeWidth = 4,
    })

    contentArea:AddChild(searchContainer)

    -- 搜索文字（稍微减小字号）
    local searchLabel = UI.Label {
        text = _tr("t_NFfPZLRDNh5KF8qw"),
        fontSize = 28,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
        marginBottom = 12,
    }
    contentArea:AddChild(searchLabel)

    -- 提示文字
    contentArea:AddChild(UI.Label {
        text = _tr("t_1H7XjE0OC1GykZJnzZ"),
        fontSize = 14,
        fontColor = { 180, 180, 200, 200 },
        marginBottom = 16,
    })

    -- 等待计时器
    local timerLabel = UI.Label {
        text = _tr("t_eyO5PiGSemgl2xkz"),
        fontSize = 13,
        fontColor = { 150, 150, 170, 180 },
        marginBottom = 50,
    }
    contentArea:AddChild(timerLabel)

    -- 取消按钮（柔和的红色）
    local cancelBtn = UI.Button {
        width = 260,
        height = 60,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 10,
        backgroundColor = { 200, 70, 70, 255 },  -- 更柔和的红色
        borderRadius = 30,
        borderWidth = 2,
        borderColor = { 160, 50, 50, 200 },
        onClick = function()
            Log("Canceling match")
            LobbyUIInstance.lobbyMgr:CancelMatch()
            CreateMainView()
        end
    }
    contentArea:AddChild(cancelBtn)

    -- 取消图标（NanoVG 绘制）
    cancelBtn:AddChild(IconWidget {
        width = 22,
        height = 22,
        icon = "cancel",
        color = { 255, 255, 255, 255 },
        strokeWidth = 2.5,
    })

    -- 取消文字
    cancelBtn:AddChild(UI.Label {
        text = _tr("t_An9ovnM5AwRAZ5y8"),
        fontSize = 18,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
    })


    view:AddChild(contentArea)

    -- Switch to matching view
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
    end
    LobbyUIInstance.root:AddChild(wrapper)
    LobbyUIInstance.currentView = wrapper

    -- 动态文字动画和计时器更新（必须在视图切换后订阅）
    local dotCount = 1
    local dotTimer = 0
    local dots = { ".", "..", "..." }
    local lastTimerUpdate = 0
    SubscribeToEvent("Update", function(eventType, eventData)
        -- 检查视图是否仍然是当前视图
        if LobbyUIInstance.currentView ~= wrapper then
            return
        end

        local dt = eventData["TimeStep"]:GetFloat()

        -- contain 缩放：保持设计比例，完整显示在屏幕内
        local baseW = UI.GetWidth()
        local baseH = UI.GetHeight()
        local currentScale = math.min(baseW / designW, baseH / designH, 1.0)
        view:SetStyle({ scale = currentScale })

        dotTimer = dotTimer + dt
        lastTimerUpdate = lastTimerUpdate + dt

        -- 点点动画
        if dotTimer >= 0.5 then  -- 每0.5秒切换
            dotTimer = 0
            dotCount = dotCount + 1
            if dotCount > 3 then
                dotCount = 0
            end
            if dots[dotCount] then
                searchLabel:SetText(_tr("t_GlBMWTKsGIQXGTgh", dots[dotCount]))
            else
                searchLabel:SetText(_tr("t_Yn2lXZK0YdiUERd7"))
            end
        end

        -- 更新计时器（每秒更新一次）
        if lastTimerUpdate >= 1.0 then
            lastTimerUpdate = 0
            local elapsed = os.time() - matchStartTime
            local minutes = math.floor(elapsed / 60)
            local seconds = elapsed % 60
            timerLabel:SetText(string.format(_tr("t_14uJHLlOS15NfcD7LV"), minutes, seconds))
        end
    end)

    -- Get max players: config.maxPlayers -> LobbyManager:GetMaxPlayers() -> 4
    local matchMaxPlayers = config.maxPlayers
    if not matchMaxPlayers or matchMaxPlayers <= 0 then
        local fromLobbyMgr = LobbyUIInstance.lobbyMgr:GetMaxPlayers()
        matchMaxPlayers = (fromLobbyMgr and fromLobbyMgr > 0) and fromLobbyMgr or 4
    end

    -- Start matching with matchInfo
    local extMatchInfo = config.matchInfo or {}
    local descName = extMatchInfo.desc_name or config.matchDescName or "free_match_with_ai"
    local playerNumber = extMatchInfo.player_number or matchMaxPlayers
    local immediatelyStart = extMatchInfo.immediately_start ~= nil and extMatchInfo.immediately_start or false
    local matchTimeout = extMatchInfo.match_timeout or config.matchTimeout or 60
    -- 手动构建固定顺序的 mode_id（Lua 表遍历顺序不固定）
    -- 补齐 project_version，保证不同版本的玩家不会被匹配到同一桶。
    local projectVersion = LobbyManager.GetProjectVersion()
    local modeId = string.format(
        '{"desc_name":"%s","immediately_start":%s,"match_timeout":%d,"player_number":%d,"project_version":"%s"}',
        descName, tostring(immediatelyStart), matchTimeout, playerNumber, projectVersion)
    local matchInfo = {
        desc_name = descName,
        player_number = playerNumber,
        immediately_start = immediatelyStart,
        match_timeout = matchTimeout,
        mode_id = modeId,
    }

    local matchParams = {
        mapName = config.mapName,
        mode = config.mode,
        matchInfo = matchInfo,
    }

    print("[LobbyUI] StartMatch params: mapName=" .. tostring(matchParams.mapName)
        .. ", mode=" .. tostring(matchParams.mode)
        .. ", player_number=" .. tostring(matchParams.matchInfo.player_number)
        .. ", mode_id=" .. tostring(matchParams.matchInfo.mode_id)
        .. ", desc_name=" .. tostring(matchParams.matchInfo.desc_name)
        .. ", match_timeout=" .. tostring(matchParams.matchInfo.match_timeout))
    
    -- 定义开始匹配的函数
    local function doStartMatch()
        local requestId = LobbyUIInstance.lobbyMgr:StartMatch({
            mapName = matchParams.mapName,
            mode = matchParams.mode,
            matchInfo = matchParams.matchInfo,
            onMatchFound = function(serverInfo)
                Log("Match found!")
                print("[LobbyUI] Match found: " .. tostring(serverInfo))
                ShowMatchFoundDialog(serverInfo)
            end,
            onError = function(errorCode)
                Log("Match failed: " .. FormatInt(errorCode))
                print("[LobbyUI] Match error: " .. FormatInt(errorCode))
                if errorCode == LobbyUI.MATCH_ERROR_PLAYER_BANNED then
                    ShowErrorDialog(LobbyUI.PLAYER_BANNED_MESSAGE)
                else
                    ShowErrorDialog("Match failed with error code: " .. FormatInt(errorCode))
                end
                CreateMainView()
            end
        })
        print("[LobbyUI] StartMatch requestId: " .. tostring(requestId))
    end
    
    -- 检查是否已在房间中，如果没有则先创建房间
    if not LobbyUIInstance.lobbyMgr:IsInRoom() then
        print("[LobbyUI] Not in room, creating temporary room first...")
        LobbyUIInstance.lobbyMgr:CreateRoom({
            mapName = config.mapName,
            maxPlayers = config.maxPlayers,
            mode = config.mode,
            onSuccess = function(roomId)
                print("[LobbyUI] Temporary room created: " .. tostring(roomId) .. ", starting match...")
                doStartMatch()
            end,
            onError = function(errorCode)
                print("[LobbyUI] Failed to create room: " .. FormatInt(errorCode))
                ShowErrorDialog("Failed to create room: " .. FormatInt(errorCode))
                CreateMainView()
            end
        })
    else
        print("[LobbyUI] Already in room, starting match directly...")
        doStartMatch()
    end
end

--- Create room browser
CreateRoomBrowserView = function()
    Log("Opening room browser")

    local theme = LobbyUIInstance.theme
    local config = LobbyUIInstance.config

    local view = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 45, 47, 53, 255 },  -- 深灰背景，与大厅一致
    }

    -- ========== 顶部栏（幽灵样式返回按钮 + 页面标题）==========
    local topBar, updateStatus = CreateTopBar({
        showBackButton = true,
        buttonText = _tr("t_qNlgG5bPpwC8vWgM"),
        ghostStyle = true,  -- 使用幽灵样式
        pageTitle = _tr("t_oOFMYbK1oFxYSyYu"),  -- 添加页面标题
        onBack = function()
            CreateMainView()
        end
    })
    view:AddChild(topBar)

    -- 订阅 Update 事件更新状态
    TrackEventSubscription("Update", function()
        updateStatus()
    end)

    -- ========== 房间列表区域 ==========
    local scrollView = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        backgroundColor = { 45, 47, 53, 255 },
        paddingLeft = 50,
        paddingRight = 50,
        paddingTop = 20,
        paddingBottom = 83,
    }

    local roomListContainer = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 35,
        justifyContent = "flex-start",  -- 从左开始平铺
        alignContent = "flex-start",
    }

    scrollView:AddChild(roomListContainer)
    view:AddChild(scrollView)

    -- Local helper functions (properly scoped)
    local UpdateRoomList
    local CreateRoomCard
    local JoinRoom
    local RefreshRoomList

    -- Update room list UI
    UpdateRoomList = function(container)
        container:ClearChildren()

        if #LobbyUIInstance.roomListData == 0 then
            local emptyPanel = UI.Panel {
                width = "100%",
                height = 300,
                flexDirection = "column",
                alignItems = "center",
                justifyContent = "center",
                backgroundColor = { 50, 55, 65, 200 },
                borderRadius = 20,
                gap = 16,
            }
            
            -- 搜索图标
            emptyPanel:AddChild(IconWidget {
                width = 60,
                height = 60,
                icon = "search",
                color = { 100, 110, 130, 120 },
                strokeWidth = 3,
            })
            
            -- 主文字
            emptyPanel:AddChild(UI.Label {
                text = _tr("t_YN7UjUprYp7Pv13W"),
                fontSize = 20,
                fontWeight = "bold",
                fontColor = { 180, 185, 200, 255 },
            })
            
            container:AddChild(emptyPanel)
            return
        end

        for i, room in ipairs(LobbyUIInstance.roomListData) do
            local roomCard = CreateRoomCard(room)
            container:AddChild(roomCard)
        end
    end

    -- Create room card
    CreateRoomCard = function(room)
        -- Status: 1=Ready, 2=Matching, 3=InGame
        local status = room.status or 1
        local statusText = status == 1 and _tr("t_vwj0n2iavS7u0c7B") or (status == 2 and _tr("t_WP2RNoJGVwrMSVxD") or _tr("t_GXG2Rc9bGg458sW2"))
        local statusBgColor = status == 1 and { 52, 168, 83, 255 } or { 234, 67, 53, 255 }

        local card = UI.Button {
            flexBasis = "31%",
            flexGrow = 1,
            minWidth = 400,
            maxWidth = "32%",
            height = 248,
            flexDirection = "column",
            backgroundColor = { 35, 37, 42, 255 },
            borderRadius = 16,
            borderWidth = 1,
            borderColor = { 60, 62, 68, 255 },
            padding = 30,
            alignItems = 'center',
            onClick = function()
                if status == 1 then
                    JoinRoom(room.id or 0, room.maxPlayers)
                end
            end
        }

        -- 第一行：房间ID+名称 和 状态标签
        local headerRow = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            marginBottom = 12,
            pointerEvents = "none",
        }

        -- 房间ID和名称
        headerRow:AddChild(UI.Label {
            text = string.format("#%d %s", room.id or 0, room.name or _tr("t_dKPVAF3ecqMQG9od")),
            fontSize = 32,
            fontWeight = "bold",
            color = { 255, 255, 255, 255 },
            marginLeft = 32,
        })

        -- 状态标签
        headerRow:AddChild(UI.Panel {
            backgroundColor = '#174245',
            width = 120,
            height = 36,
            borderRadius = 18,
            alignItems = "center",
            justifyContent = "center",
            marginRight = 32,
        }:AddChild(UI.Label {
            text = statusText,
            fontSize = 22,
            fontWeight = "bold",
            fontColor = '#10B67E',
        }))

        card:AddChild(headerRow)

        -- 第二行：房主信息
        local hostRow = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "left",
            gap = 10,
            marginBottom = 16,
            pointerEvents = "none",
            marginLeft = 32,
        }

        -- 房主头像（简单圆形）
        hostRow:AddChild(UI.Panel {
            width = 32,
            height = 32,
            borderRadius = 16,
            backgroundColor = { 255, 180, 100, 255 },
            alignItems = "center",
            justifyContent = "center",
        }:AddChild(UI.Label {
            text = " ",
            fontSize = 16,
        }))

        -- 房主ID
        hostRow:AddChild(UI.Label {
            text = _tr("t_nLTVGjzcnomcrqp7", FormatInt(room.ownerId or 0)),
            fontSize = 22,
            fontColor = '#7E86B5',
        })

        card:AddChild(hostRow)

        -- 分隔线
        card:AddChild(UI.Panel {
            width = "100%",
            height = 1,
            backgroundColor = { 80, 82, 88, 255 },
            marginBottom = 16,
            pointerEvents = "none",
        })

        -- 第三行：玩家数量和延迟
        local footerRow = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            pointerEvents = "none",
        }

        -- 玩家数量
        local playerInfo = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            pointerEvents = "none",
            marginLeft = 32,
        }
        playerInfo:AddChild(UI.Label {
            text = "👥",
            fontSize = 20,
        })
        playerInfo:AddChild(UI.Label {
            text = string.format("%d/%d", room.playerCount or 0, room.maxPlayers or 4),
            fontSize = 22,
            fontColor = '#7E86B5',
        })
        footerRow:AddChild(playerInfo)

        -- 延迟信息
        local latency = room.latency or math.random(10, 60)
        footerRow:AddChild(UI.Label {
            text = string.format(_tr("t_sMsIN5drss0VPyyQ"), latency),
            fontSize = 20,
            fontColor = '#7E86B5',
            marginRight = 32,
        })

        card:AddChild(footerRow)

        return card
    end

    -- Join room
    JoinRoom = function(roomId, roomMaxPlayers)
        Log("Joining room: " .. roomId)
        LobbyUIInstance.lobbyMgr:JoinRoom({
            roomId = roomId,
            onSuccess = function(data)
                Log("Joined room successfully")
                CreateRoomDetailView(roomId, nil, roomMaxPlayers)
            end,
            onError = function(errorCode)
                Log("Failed to join room: " .. FormatInt(errorCode))
                ShowErrorDialog("Failed to join room: " .. FormatInt(errorCode))
            end
        })
    end

    -- Refresh room list
    RefreshRoomList = function()
        local mapName = LobbyUIInstance.config.mapName or ""
        local mode = LobbyUIInstance.config.mode or "pvp"
        print("[LobbyUI] RefreshRoomList: mapName = '" .. mapName .. "', mode = '" .. mode .. "'")
        
        if mapName == "" then
            print("[LobbyUI] WARNING: mapName is empty! Room list may not work correctly.")
        end
        
        LobbyUIInstance.lobbyMgr:GetRoomList({
            mapName = mapName,  -- 必须传入 mapName 才能看到房间
            modes = { mode },   -- 传入 mode 过滤
            limit = 20,
            includePrivate = false,
            onSuccess = function(data)
                print("[LobbyUI] GetRoomList success, data length: " .. tostring(string.len(tostring(data))))
                LobbyUIInstance.roomListData = ParseRoomList(data)
                print("[LobbyUI] Parsed room count: " .. tostring(#LobbyUIInstance.roomListData))
                UpdateRoomList(roomListContainer)
            end,
            onError = function(errorCode)
                Log("Failed to get room list: " .. FormatInt(errorCode))
                ShowErrorDialog("Failed to load rooms: " .. FormatInt(errorCode))
            end
        })
    end

    -- Refresh button event
    if refreshBtn then
        refreshBtn.onClick = RefreshRoomList
    end

    -- Switch to room browser view
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view

    -- Immediate refresh
    RefreshRoomList()

    -- Auto refresh if enabled
    if config.autoRefresh then
        LobbyUIInstance.autoRefreshTimer = 0
        TrackEventSubscription("Update", function(eventType, eventData)
            LobbyUIInstance.autoRefreshTimer = LobbyUIInstance.autoRefreshTimer + eventData["TimeStep"]:GetFloat() * 1000
            if LobbyUIInstance.autoRefreshTimer >= config.refreshInterval then
                LobbyUIInstance.autoRefreshTimer = 0
                RefreshRoomList()
            end
        end)
    end
end

--- Create room detail view
--- @param roomId string 房间ID
--- @param roomName string|nil 房间名称
--- @param roomMaxPlayers number|nil 房间最大玩家数（如果不传则使用config默认值）
CreateRoomDetailView = function(roomId, roomName, roomMaxPlayers)
    Log("Opening room detail: " .. roomId)

    local theme = LobbyUIInstance.theme
    local config = LobbyUIInstance.config
    roomName = roomName or _tr("t_dKPVAF3ecqMQG9od")
    roomMaxPlayers = roomMaxPlayers or config.maxPlayers or 4  -- 使用传入的值或默认值

    local view = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 45, 47, 53, 255 },  -- 深灰背景
    }

    -- ========== 顶部栏（与其他页面保持一致）==========
    local header = UI.Panel {
        width = "100%",
        height = 120,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingLeft = 43,
        paddingRight = 43,
        paddingTop = 34,
    }

    -- 左侧：离开按钮（与返回按钮大小一致）
    local exitBtn = UI.Button {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 10,
        paddingLeft = 16,
        paddingRight = 24,
        paddingTop = 12,
        paddingBottom = 12,
        minWidth = 120,
        minHeight = 50,
        backgroundColor = { 0, 0, 0, 0 },
        borderRadius = 12,
        onClick = function()
            -- 先尝试离开房间，然后返回主界面
            LobbyUIInstance.lobbyMgr:LeaveRoom({
                onSuccess = function()
                    CreateMainView()
                end,
                onError = function()
                    CreateMainView()  -- 即使失败也返回
                end
            })
            -- 立即返回，不等待回调
            CreateMainView()
        end
    }
    exitBtn:AddChild(IconWidget {
        width = 24,
        height = 24,
        icon = "back",
        color = { 180, 180, 200, 220 },
        strokeWidth = 3,
    })
    exitBtn:AddChild(UI.Label {
        text = _tr("t_1FeXFS4xM1FnFysAo5"),
        fontSize = 20,
        fontColor = { 180, 180, 200, 220 },
    })
    header:AddChild(exitBtn)

    -- 中间：房间标题（使用 flexGrow 居中）
    local centerArea = UI.Panel {
        flexGrow = 1,
        height = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 12,
    }
    -- 房间图标
    local roomIcon = UI.Panel {
        width = 30,
        height = 34,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 3,
    }
    roomIcon:AddChild(UI.Panel {
        width = 6,
        height = 34,
        backgroundColor = { 100, 180, 255, 255 },
        borderRadius = 2,
    })
    roomIcon:AddChild(UI.Panel {
        width = 6,
        height = 24,
        backgroundColor = { 100, 180, 255, 255 },
        borderRadius = 2,
    })
    centerArea:AddChild(roomIcon)
    centerArea:AddChild(UI.Label {
        text = "#" .. FormatInt(roomId) .. " " .. roomName,
        fontSize = 24,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
    })
    header:AddChild(centerArea)

    -- 右侧：占位（保持布局平衡，与左侧按钮宽度匹配）
    header:AddChild(UI.Panel {
        width = 120,
        height = 50,
    })

    view:AddChild(header)

    -- ========== 玩家卡片区域（支持1-16人，使用滚动网格）==========
    local myUserId = LobbyUIInstance.lobbyMgr:GetMyUserId()
    local maxPlayers = roomMaxPlayers  -- 使用传入的房间最大玩家数
    
    -- 根据人数计算布局：每行4个卡片
    local cardsPerRow = 4
    local cardWidth = 220
    local cardHeight = 200
    local cardGap = 20
    
    -- 滚动容器
    local scrollView = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        backgroundColor = { 45, 47, 53, 255 },
        paddingLeft = 40,
        paddingRight = 40,
        paddingTop = 20,
        paddingBottom = 20,
    }
    
    -- 网格容器（使用 flex wrap）
    local playerGrid = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        gap = cardGap,
    }

    -- 创建玩家卡片的函数（更紧凑的设计）
    local function CreatePlayerCard(playerData, isHost, slotIndex)
        if playerData then
            -- 有玩家的卡片
            local card = UI.Panel {
                width = cardWidth,
                height = cardHeight,
                flexDirection = "column",
                alignItems = "center",
                justifyContent = "center",
                backgroundColor = { 40, 50, 70, 255 },
                borderRadius = 14,
                borderWidth = 2,
                borderColor = isHost and { 200, 160, 100, 200 } or { 80, 130, 200, 150 },  -- 房主金色，普通蓝色
                gap = 12,
            }

            -- 房主标签
            if isHost then
                local hostBadge = UI.Panel {
                    position = "absolute",
                    top = 10,
                    left = 10,
                    backgroundColor = { 255, 180, 50, 255 },  -- 金色
                    borderRadius = 4,
                    paddingLeft = 8,
                    paddingRight = 8,
                    paddingTop = 3,
                    paddingBottom = 3,
                }
                hostBadge:AddChild(UI.Label {
                    text = _tr("t_7hcHOnaS7rhgP4E5"),
                    fontSize = 11,
                    fontWeight = "bold",
                    fontColor = { 40, 35, 20, 255 },
                })
                card:AddChild(hostBadge)
            end

            -- 头像
            local avatarSize = 70
            local avatarContainer = UI.Panel {
                width = avatarSize,
                height = avatarSize,
                borderRadius = avatarSize / 2,
                backgroundColor = { 200, 180, 160, 255 },
                borderWidth = isHost and 3 or 2,
                borderColor = isHost and { 200, 160, 100, 200 } or { 100, 150, 200, 150 },
                alignItems = "center",
                justifyContent = "center",
                overflow = "hidden",
            }
            avatarContainer:AddChild(UI.Label {
                text = "👤",
                fontSize = 36,
            })
            card:AddChild(avatarContainer)

            -- 玩家昵称（截断长名称）
            local displayName = playerData.nickname or _tr("t_19DCzy20319fRYubAY")
            if #displayName > 12 then
                displayName = string.sub(displayName, 1, 10) .. ".."
            end
            local nameLabel = UI.Label {
                text = displayName,
                fontSize = 14,
                fontColor = { 255, 255, 255, 255 },
            }
            card:AddChild(nameLabel)

            -- 如果没有昵称，异步查询
            if not playerData.nickname and playerData.userId then
                LobbyUIInstance.lobbyMgr:GetUserNickname({
                    userIds = { playerData.userId },
                    onSuccess = function(nicknames)
                        if nicknames and #nicknames > 0 then
                            local nickname = nicknames[1].nickname or ""
                            if nickname == "" then
                                nickname = "Player_" .. FormatInt(playerData.userId)
                            end
                            -- 缓存昵称到 playerData
                            playerData.nickname = nickname
                            -- 截断长名称
                            if #nickname > 12 then
                                nickname = string.sub(nickname, 1, 10) .. ".."
                            end
                            nameLabel:SetText(nickname)
                        end
                    end,
                    onError = function(errorCode)
                        nameLabel:SetText("Player_" .. FormatInt(playerData.userId))
                    end
                })
            end

            -- 槽位编号
            card:AddChild(UI.Label {
                text = _tr("t_AuY7uRNnB3u9vugo", FormatInt(slotIndex)),
                fontSize = 11,
                fontColor = { 130, 140, 160, 180 },
            })

            return card
        else
            -- 空槽位卡片
            local card = UI.Panel {
                width = cardWidth,
                height = cardHeight,
                flexDirection = "column",
                alignItems = "center",
                justifyContent = "center",
                backgroundColor = { 35, 40, 50, 200 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 70, 80, 100, 120 },
                borderStyle = "dashed",
                gap = 10,
            }

            -- 加号圆圈
            local plusCircle = UI.Panel {
                width = 50,
                height = 50,
                borderRadius = 25,
                borderWidth = 2,
                borderColor = { 100, 115, 140, 150 },
                backgroundColor = { 0, 0, 0, 0 },
                alignItems = "center",
                justifyContent = "center",
            }
            plusCircle:AddChild(UI.Label {
                text = "+",
                fontSize = 28,
                fontColor = { 100, 115, 140, 150 },
            })
            card:AddChild(plusCircle)

            -- 等待文字
            card:AddChild(UI.Label {
                text = _tr("t_bruDxYVibjAKQly3"),
                fontSize = 12,
                fontColor = { 110, 120, 145, 180 },
            })

            -- 槽位编号
            card:AddChild(UI.Label {
                text = _tr("t_Cj6I0g85CulbTpu0", FormatInt(slotIndex)),
                fontSize = 10,
                fontColor = { 90, 100, 120, 140 },
            })

            return card
        end
    end

    -- 当前房主 ID（用于标记房主）
    local currentMasterId = nil
    -- 开始按钮引用（用于动态更新可见性）
    local startBtn = nil

    -- 更新开始按钮的可见性（只有房主可以看到）
    local function updateStartButtonVisibility(masterId)
        if startBtn then
            local isMaster = (masterId == nil) or (masterId == myUserId)
            startBtn:SetVisible(isMaster)
        end
    end

    -- 动态更新玩家卡片列表的函数
    local function updatePlayerGrid(players, masterId)
        playerGrid:ClearChildren()
        currentMasterId = masterId

        if not players or #players == 0 then
            -- 没有玩家数据时，显示当前用户为房主
            local hostCard = CreatePlayerCard({ userId = myUserId, name = "Player_" .. FormatInt(myUserId) }, true, 1)
            playerGrid:AddChild(hostCard)
            for i = 2, maxPlayers do
                local emptyCard = CreatePlayerCard(nil, false, i)
                playerGrid:AddChild(emptyCard)
            end
            updateStartButtonVisibility(nil)  -- 没有数据时默认是房主
            return
        end

        -- 根据实际玩家数据创建卡片
        local slotIndex = 1
        for _, player in ipairs(players) do
            local isHost = masterId and player.userId == masterId
            local card = CreatePlayerCard(player, isHost, slotIndex)
            playerGrid:AddChild(card)
            slotIndex = slotIndex + 1
        end

        -- 填充剩余空槽位
        for i = slotIndex, maxPlayers do
            local emptyCard = CreatePlayerCard(nil, false, i)
            playerGrid:AddChild(emptyCard)
        end

        -- 更新开始按钮可见性
        updateStartButtonVisibility(masterId)
    end

    -- 初始显示（只有当前用户）
    updatePlayerGrid(nil, nil)

    -- 订阅队伍状态更新（实时显示玩家加入/离开）
    LobbyUIInstance.lobbyMgr:OnTeamStatusChanged(function(teamStatus)
        print("[LobbyUI] OnTeamStatusChanged callback triggered")
        if teamStatus then
            print("[LobbyUI] Team status updated: " .. tostring(#(teamStatus.players or {})) .. " players")
            updatePlayerGrid(teamStatus.players, teamStatus.masterId)
        else
            print("[LobbyUI] Team status is nil")
        end
    end)

    scrollView:AddChild(playerGrid)
    view:AddChild(scrollView)

    -- ========== 底部按钮区域 ==========
    local bottomArea = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        paddingTop = 20,
        paddingBottom = 50,
    }

    -- 开始游戏按钮（干净的绿色按钮，只有房主可见）
    startBtn = UI.Button {
        width = 320,
        height = 60,
        fontSize = 20,
        fontWeight = "bold",
        backgroundColor = { 80, 200, 120, 255 },  -- 清新绿色
        fontColor = { 255, 255, 255, 255 },
        borderRadius = 30,
        text = _tr("t_OAaPAePAO1rLaxpB"),
        onClick = function()
            StartGameFromRoom()
        end
    }
    bottomArea:AddChild(startBtn)

    view:AddChild(bottomArea)

    -- Switch view
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view

    -- 离开房间时清理回调
    local originalLeaveRoom = LobbyUIInstance.lobbyMgr.onRoomLeft
    LobbyUIInstance.lobbyMgr:OnRoomLeft(function()
        LobbyUIInstance.lobbyMgr:OnTeamStatusChanged(nil)  -- 清理回调
        if originalLeaveRoom then
            originalLeaveRoom()
        end
    end)
end

--- Create "create room" dialog
CreateCreateRoomDialog = function()
    Log("Opening create room dialog")

    local theme = LobbyUIInstance.theme
    local config = LobbyUIInstance.config

    -- Get default max players: config.maxPlayers -> LobbyManager:GetMaxPlayers() -> 4
    local defaultMaxPlayers = config.maxPlayers
    if not defaultMaxPlayers or defaultMaxPlayers <= 0 then
        local fromLobbyMgr = LobbyUIInstance.lobbyMgr:GetMaxPlayers()
        defaultMaxPlayers = (fromLobbyMgr and fromLobbyMgr > 0) and fromLobbyMgr or 4
    end

    -- Overlay
    local overlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = { 0, 0, 0, 128 },
        justifyContent = "center",
        alignItems = "center",
    }

    -- Dialog（更圆润的弹窗）
    local dialog = UI.Panel {
        width = 560,
        flexDirection = "column",
        backgroundColor = { 50, 55, 70, 250 },
        borderRadius = 24,  -- 更大的圆角
        borderWidth = 1,
        borderColor = { 80, 90, 110, 150 },
        padding = 36,
        gap = 20,
    }

    -- Title
    dialog:AddChild(UI.Label {
        text = _tr("t_1DSgBSUmlo9AcDt"),
        fontSize = 26,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
        marginBottom = 12,
    })

    -- Map name input
    dialog:AddChild(UI.Label {
        text = _tr("t_4jmxglkE4aNkgIch"),
        fontSize = 16,
        fontColor = { 180, 190, 210, 255 },
    })

    local mapInput = UI.TextField {
        width = "100%",
        height = 56,
        fontSize = 18,
        placeholder = config.mapName,
        backgroundColor = { 40, 45, 60, 255 },
        borderRadius = 14,
        borderWidth = 1,
        borderColor = { 70, 80, 100, 150 },
        padding = 14,
    }
    dialog:AddChild(mapInput)

    -- Max players input
    dialog:AddChild(UI.Label {
        text = string.format(_tr("t_ntAIq14pnR4mnC8U"), MIN_MAX_PLAYERS, defaultMaxPlayers),
        fontSize = 16,
        fontColor = { 180, 190, 210, 255 },
    })

    local maxPlayersInput = UI.TextField {
        width = "100%",
        height = 56,
        fontSize = 18,
        placeholder = tostring(defaultMaxPlayers),
        backgroundColor = { 40, 45, 60, 255 },
        borderRadius = 14,
        borderWidth = 1,
        borderColor = { 70, 80, 100, 150 },
        padding = 14,
    }
    dialog:AddChild(maxPlayersInput)

    -- Error message label
    local errorLabel = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = { 255, 100, 100, 255 },
        visible = false,
    }
    dialog:AddChild(errorLabel)

    -- Button row
    local buttonRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 20,
        marginTop = 16,
    }

    -- Cancel button（灰色）
    buttonRow:AddChild(UI.Button {
        text = _tr("t_HXqnawyqI0cE2KuT"),
        width = 180,
        height = 52,
        fontSize = 18,
        backgroundColor = { 70, 75, 90, 255 },
        fontColor = { 200, 200, 210, 255 },
        borderRadius = 26,
        onClick = function()
            overlay:Destroy()
        end
    })

    -- Create button（绿色）
    buttonRow:AddChild(UI.Button {
        text = _tr("t_vkVwvaGXvt9hF4G8"),
        width = 180,
        height = 52,
        fontSize = 18,
        fontWeight = "bold",
        backgroundColor = { 80, 200, 120, 255 },
        fontColor = { 255, 255, 255, 255 },
        borderRadius = 26,
        onClick = function()
            local mapText = mapInput:GetText()
            local mapName = mapText ~= "" and mapText or config.mapName

            -- Validate max players
            local maxPlayersText = maxPlayersInput:GetText()
            maxPlayersText = maxPlayersText ~= "" and maxPlayersText or tostring(defaultMaxPlayers)
            local num = tonumber(maxPlayersText)
            if not num then
                errorLabel:SetText(_tr("t_J1xGbb8NJAkOoh4s"))
                errorLabel:SetVisible(true)
                return
            end
            if num < MIN_MAX_PLAYERS or num > defaultMaxPlayers then
                errorLabel:SetText(string.format(_tr("t_r9NDn1PxraLGNUXE"), MIN_MAX_PLAYERS, defaultMaxPlayers))
                errorLabel:SetVisible(true)
                return
            end

            local finalMaxPlayers = num  -- 保存到局部变量

            Log("Creating room: " .. mapName .. ", max players: " .. finalMaxPlayers)

            -- 保存到临时变量供回调使用
            local savedMaxPlayers = finalMaxPlayers

            LobbyUIInstance.lobbyMgr:CreateRoom({
                mapName = mapName,
                maxPlayers = finalMaxPlayers,
                mode = config.mode,
                onSuccess = function(roomId)
                    Log("Room created: " .. roomId .. ", maxPlayers: " .. savedMaxPlayers)
                    overlay:Destroy()
                    CreateRoomDetailView(roomId, nil, savedMaxPlayers)
                end,
                onError = function(errorCode)
                    Log("Failed to create room: " .. FormatInt(errorCode))
                    ShowErrorDialog("Failed to create room: " .. FormatInt(errorCode))
                    overlay:Destroy()
                end
            })
        end
    })

    dialog:AddChild(buttonRow)
    overlay:AddChild(dialog)

    LobbyUIInstance.root:AddChild(overlay)
end

--- Create server progress view (shown while waiting for server to be ready)
CreateServerProgressView = function()
    Log("Creating server progress view")

    local theme = LobbyUIInstance.theme

    local view = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = theme.background,
        padding = 20,
    }

    -- Loading icon
    view:AddChild(UI.Label {
        text = " ",
        fontSize = 64,
        color = theme.primary,
        marginBottom = 20,
    })

    -- Title
    view:AddChild(UI.Label {
        text = _tr("t_mROCphnumJBiIlbn"),
        fontSize = 24,
        fontWeight = "bold",
        color = theme.text,
        marginBottom = 10,
    })

    -- Status label
    local statusLabel = UI.Label {
        text = _tr("t_1Um2bSV91fOJ5pZS"),
        fontSize = 14,
        color = theme.textSecondary,
        marginBottom = 30,
    }
    view:AddChild(statusLabel)

    -- Store references for updates
    serverProgressState.view = view
    serverProgressState.statusLabel = statusLabel

    -- Switch to server progress view
    if LobbyUIInstance.currentView then
        LobbyUIInstance.currentView:Destroy()
    end
    LobbyUIInstance.root:AddChild(view)
    LobbyUIInstance.currentView = view

    return view
end

--- Show match found dialog
ShowMatchFoundDialog = function(serverInfo)
    Log("Match found dialog")

    local theme = LobbyUIInstance.theme

    local overlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = { 0, 0, 0, 179 },
        justifyContent = "center",
        alignItems = "center",
    }

    local dialog = UI.Panel {
        width = "90%",
        maxWidth = 400,
        flexDirection = "column",
        backgroundColor = theme.surface,
        borderRadius = 12,
        padding = 30,
        gap = 20,
        alignItems = "center",
    }

    dialog:AddChild(UI.Label {
        text = "✓",
        fontSize = 64,
        color = theme.success,
    })

    dialog:AddChild(UI.Label {
        text = _tr("t_w7PF2Jh5wc3WonMw"),
        fontSize = 24,
        fontWeight = "bold",
        color = theme.text,
    })

    dialog:AddChild(UI.Label {
        text = _tr("t_KEghPkfTKO2P03WM"),
        fontSize = 14,
        color = theme.textSecondary,
    })

    overlay:AddChild(dialog)
    LobbyUIInstance.root:AddChild(overlay)

    -- Delayed connection with proper cleanup
    local timer = 0
    local connected = false
    local subscription = TrackEventSubscription("Update", function(eventType, eventData)
        if connected then
            return
        end

        timer = timer + eventData["TimeStep"]:GetFloat()
        if timer > 1.5 then
            connected = true
            ConnectToGameServer(serverInfo)
            overlay:Destroy()
        end
    end)
end

--- Show error toast using UI library Toast component
ShowErrorDialog = function(message)
    -- Use the UI library's Toast component
    Toast.Show({
        message = message,
        variant = "error",
        duration = 4,  -- Show for 4 seconds
        showClose = true,
    })
    print("[LobbyUI] Toast shown: " .. message)
end

--- Start game from room
StartGameFromRoom = function()
    Log("Starting game from room")

    local config = LobbyUIInstance.config

    LobbyUIInstance.lobbyMgr:StartGame({
        mapName = config.mapName,
        mode = config.mode,
        onGameStarted = function(serverInfo)
            Log("Game started!")
            ShowMatchFoundDialog(serverInfo)
        end,
        onError = function(errorCode)
            Log("Failed to start game: " .. FormatInt(errorCode))
            if errorCode == LobbyUI.GAME_START_ERROR_PLAYER_BANNED then
                ShowErrorDialog(LobbyUI.PLAYER_BANNED_MESSAGE)
            else
                ShowErrorDialog("Failed to start game: " .. FormatInt(errorCode))
            end
        end
    })
end

--- Connect to game server
ConnectToGameServer = function(serverInfo)
    Log("Connecting to game server: " .. serverInfo.ip .. ":" .. serverInfo.port)

    -- Call user callback
    if LobbyUIInstance.config.onGameStart then
        LobbyUIInstance.config.onGameStart(serverInfo)
    end

    -- 注意：不在这里隐藏 UI，因为连接可能失败
    -- UI 会在脚本切换时由 main.lua 的 Stop() 函数隐藏
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Show game lobby UI
--- @param config table Configuration options (optional)
function LobbyUI.Show(config)
    -- Merge configuration
    LobbyUIInstance.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        LobbyUIInstance.config[k] = v
    end
    if config then
        for k, v in pairs(config) do
            LobbyUIInstance.config[k] = v
        end
    end

    -- Set theme
    LobbyUIInstance.theme = THEMES[LobbyUIInstance.config.theme] or THEMES.light

    -- Create LobbyManager
    if not LobbyUIInstance.lobbyMgr then
        LobbyUIInstance.lobbyMgr = LobbyManager.new({
            debugMode = LobbyUIInstance.config.debugMode,
        })
        
        -- Set global error callback for game start failures
        LobbyUIInstance.lobbyMgr:OnError(function(errorType, errorCode)
            print("[LobbyUI] Global error: type=" .. tostring(errorType) .. ", code=" .. FormatInt(errorCode))
            if errorType == "GAME_START" then
                if errorCode == LobbyUI.GAME_START_ERROR_PLAYER_BANNED then
                    ShowErrorDialog(LobbyUI.PLAYER_BANNED_MESSAGE)
                else
                    ShowErrorDialog("Game start failed with error code: " .. FormatInt(errorCode))
                end
                CreateMainView()
            end
        end)
        
        -- Set global match found callback
        LobbyUIInstance.lobbyMgr:OnMatchFound(function(serverInfo)
            print("[LobbyUI] Match found via global callback!")
            ShowMatchFoundDialog(serverInfo)
        end)
    end

    -- Use project ID as default mapName if not specified (must be after LobbyManager creation)
    if not LobbyUIInstance.config.mapName or LobbyUIInstance.config.mapName == "" then
        local projectId = LobbyUIInstance.lobbyMgr:GetProjectId()
        if projectId and projectId ~= "" then
            LobbyUIInstance.config.mapName = projectId
            Log("Using project ID as mapName: " .. projectId)
        else
            LobbyUIInstance.config.mapName = "DefaultMap"
            Log("Warning: Project ID not available, using fallback mapName: DefaultMap")
        end
    end

    -- Initialize UI system if not already initialized
    if not UI.GetNVGContext() then
        UI.Init({
            scale = function()
                return math.max(graphics.height / 1080, 0.4)
            end,
        })
    end

    -- Initialize UI (SafeAreaView as root ensures all views have safe area insets)
    if not LobbyUIInstance.root then
        LobbyUIInstance.root = UI.SafeAreaView {
            position = "absolute",
            top = 0,
            left = 0,
            right = 0,
            bottom = 0,
            edges = "all",
        }

        -- Add to existing root or set as root
        local uiRoot = UI.GetRoot()
        if uiRoot then
            uiRoot:AddChild(LobbyUIInstance.root)
        else
            -- No root exists, set LobbyUI as root
            UI.SetRoot(LobbyUIInstance.root)
        end
    end

    -- Show mouse
    local input = GetInput()
    if input then
        input.mouseVisible = true
    end

    -- Create main interface (skip in middle-game / headless modes)
    if not LobbyUIInstance.config.skipMainView then
        CreateMainView()
    end

    Log("LobbyUI shown")
end


-- 全局事件订阅（不会被 Hide 清理）
SubscribeToEvent("ReturnToLobby", function(eventType, eventData)
    print("[LobbyUI] ReturnToLobby event received")

    -- 标记主动返回大厅（main.lua 的 HandleServerDisconnected 读取此标志，抑制重连）
    LobbyUI.isReturningToLobby_ = true

    -- 放弃所有可重连的游戏会话（通知 Lobby 服务器取消重连）
    if lobby and lobby.CancelAllReconnects then
        lobby:CancelAllReconnects()
    end

    -- 通知服务器玩家离开
    local network = GetNetwork()
    if network then
        local serverConnection = network:GetServerConnection()
        if serverConnection then
            serverConnection:SendRemoteEvent("PlayerLeaving", true, VariantMap())
            print("[LobbyUI] Sent PlayerLeaving remote event to server")
        end
    end

    -- 后台匹配模式：发送 PlayerLeaving 后立即开始匹配并切换回游戏脚本
    if LobbyUIInstance.config and LobbyUIInstance.config.backgroundMatch then
        print("[LobbyUI] Background match mode, starting quick match and switching back to game script")
        LobbyUI.StartQuickMatch()
        -- 主动返回大厅后重新匹配是新会话，不是重连；此刻匹配未返回，
        -- SessionId 必然为空（判断重连请用 IsReconnect）
        local switchData = VariantMap()
        switchData["IsReconnect"] = false
        switchData["SessionId"] = ""
        SendEvent("RequestSwitchToGameScript", switchData)
        return
    end

    LobbyUI.SetEnabled(true)

    -- 重置到主界面
    CreateMainView()

    local switchEventData = VariantMap()
    switchEventData["ScriptPath"] = Variant("")
    SendEvent("RequestSwitchScript", switchEventData)
end)


--- Hide game lobby UI
function LobbyUI.Hide()
    -- Clean up event subscriptions
    CleanupEventSubscriptions()

    if LobbyUIInstance.root then
        LobbyUIInstance.root:Destroy()
        LobbyUIInstance.root = nil
        LobbyUIInstance.currentView = nil
    end

    Log("LobbyUI hidden")
end

--- Check if UI is visible
--- @return boolean
function LobbyUI.IsVisible()
    return LobbyUIInstance.root ~= nil
end

--- Get LobbyManager instance
--- @return LobbyManager
function LobbyUI.GetLobbyManager()
    return LobbyUIInstance.lobbyMgr
end

--- Show kicked alert dialog (full-screen overlay with message and confirm button)
--- Show a full-screen blocking dialog (overlay + centered card + single button).
--- @param options table { title, message, icon, buttonText, onClose }
---   - title: string Dialog title (required)
---   - message: string Dialog body text (required)
---   - icon: string Icon text (default "⚠")
---   - buttonText: string Button label (default "我知道了")
---   - onClose: function|nil Callback after user dismisses the dialog
function LobbyUI.ShowDialog(options)
    options = options or {}

    if not LobbyUIInstance.root then
        print("[LobbyUI] ShowDialog (UI not ready): " .. tostring(options.message))
        return
    end

    local theme = LobbyUIInstance.theme

    local overlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
    }

    local dialog = UI.Panel {
        width = "85%",
        maxWidth = 380,
        flexDirection = "column",
        backgroundColor = theme.surface,
        borderRadius = 16,
        padding = 32,
        gap = 16,
        alignItems = "center",
    }

    dialog:AddChild(UI.Label {
        text = options.icon or "⚠",
        fontSize = 48,
        color = theme.error,
    })

    dialog:AddChild(UI.Label {
        text = options.title or "",
        fontSize = 22,
        fontWeight = "bold",
        color = theme.text,
        textAlign = "center",
    })

    dialog:AddChild(UI.Label {
        text = options.message or "",
        fontSize = 14,
        color = theme.textSecondary,
        textAlign = "center",
        marginBottom = 8,
    })

    local btn = UI.Button {
        width = "100%",
        height = 44,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = theme.primary,
        borderRadius = 8,
        onClick = function()
            overlay:Destroy()
            if options.onClose then
                options.onClose()
            end
        end,
    }
    btn:AddChild(UI.Label {
        text = options.buttonText or _tr("t_JJMNFId6IoqaIkhF"),
        fontSize = 16,
        fontWeight = "bold",
        color = { 255, 255, 255, 255 },
    })
    dialog:AddChild(btn)

    overlay:AddChild(dialog)
    LobbyUIInstance.root:AddChild(overlay)
    print("[LobbyUI] ShowDialog: " .. tostring(options.title) .. " - " .. tostring(options.message))
end

--- @param title string Dialog title
--- @param message string Dialog message
function LobbyUI.ShowKickedDialog(title, message)
    LobbyUI.ShowDialog({ title = title, message = message })
end

--- Show error dialog
--- @param message string Error message to display
function LobbyUI.ShowError(message)
    -- 检查 UI 是否已初始化
    if not LobbyUIInstance.root then
        print("[LobbyUI] Error (UI not ready): " .. message)
        return
    end

    if ShowErrorDialog then
        ShowErrorDialog(message)
    else
        print("[LobbyUI] Error: " .. message)
    end
end

--- Enable or disable the Lobby UI
--- When disabled, the UI stops rendering and responding to events but remains in memory.
--- @param enabled boolean
function LobbyUI.SetEnabled(enabled)
    UI.SetEnabled(enabled)
    Log("LobbyUI " .. (enabled and "enabled" or "disabled"))
end

--- Check if the Lobby UI is enabled
--- @return boolean
function LobbyUI.IsEnabled()
    return UI.IsEnabled()
end

--- Switch to server progress view
--- Call this when connected to server and waiting for server to be ready
function LobbyUI.SwitchToServerProgressView()
    if not LobbyUIInstance.root then
        print("[LobbyUI] Cannot switch to server progress view: UI not initialized")
        return
    end
    CreateServerProgressView()
end

--- Update server progress display
--- @param progress number Progress value (0.0 - 1.0)
--- @param status string Status description
function LobbyUI.UpdateServerProgress(progress, status)
    if not serverProgressState.view then
        -- View not created yet, ignore
        return
    end

    local progressPercent = math.floor(progress * 100)

    -- Update progress bar width
    if serverProgressState.progressBar then
        serverProgressState.progressBar:SetWidth(tostring(progressPercent) .. "%")
    end

    -- Update progress label
    if serverProgressState.progressLabel then
        serverProgressState.progressLabel:SetText(tostring(progressPercent) .. "%")
    end

    -- Update status label
    if serverProgressState.statusLabel and status and status ~= "" then
        serverProgressState.statusLabel:SetText(status)
    end

    Log("Server progress: " .. progressPercent .. "% - " .. (status or ""))
end

-- 后台匹配状态
local backgroundMatchState = {
    retryCount = 0,
    maxRetries = 10,        -- 最大重试次数
    retryDelay = 2.0,       -- 重试延迟（秒）
    isMatching = false,
    retryTimerNode = nil,
    retryTimerObject = nil,
    retryTimerToken = 0,
}

local function cancelBackgroundRetryTimer()
    backgroundMatchState.retryTimerToken = backgroundMatchState.retryTimerToken + 1
    if backgroundMatchState.retryTimerObject then
        backgroundMatchState.retryTimerObject:UnsubscribeFromEvent("Update")
        backgroundMatchState.retryTimerObject = nil
    end
    if backgroundMatchState.retryTimerNode then
        backgroundMatchState.retryTimerNode:Remove()
        backgroundMatchState.retryTimerNode = nil
    end
end

--- Start quick match directly (for background match mode)
--- This starts the matching process without showing the matching UI
--- Includes automatic retry on failure
function LobbyUI.StartQuickMatch()
    if not LobbyUIInstance.lobbyMgr then
        print("[LobbyUI] ERROR: LobbyManager not initialized")
        return false
    end

    local config = LobbyUIInstance.config
    if not config then
        print("[LobbyUI] ERROR: Config not initialized")
        return false
    end

    -- 如果已经在匹配中，不重复启动
    if backgroundMatchState.isMatching then
        print("[LobbyUI] Background match already in progress")
        return true
    end

    -- 重置重试计数
    backgroundMatchState.retryCount = 0
    backgroundMatchState.isMatching = true

    -- Get max players: config.maxPlayers -> LobbyManager:GetMaxPlayers() -> 4
    local matchMaxPlayers = config.maxPlayers
    if not matchMaxPlayers or matchMaxPlayers <= 0 then
        local fromLobbyMgr = LobbyUIInstance.lobbyMgr:GetMaxPlayers()
        matchMaxPlayers = (fromLobbyMgr and fromLobbyMgr > 0) and fromLobbyMgr or 4
    end

    -- Match parameters
    local extMatchInfo = config.matchInfo or {}
    local descName = extMatchInfo.desc_name or config.matchDescName or "free_match_with_ai"
    local playerNumber = extMatchInfo.player_number or matchMaxPlayers
    local immediatelyStart = extMatchInfo.immediately_start ~= nil and extMatchInfo.immediately_start or false
    local matchTimeout = extMatchInfo.match_timeout or config.matchTimeout or 60
    -- 手动构建固定顺序的 mode_id（Lua 表遍历顺序不固定）
    -- 补齐 project_version，保证不同版本的玩家不会被匹配到同一桶。
    local projectVersion = LobbyManager.GetProjectVersion()
    local modeId = string.format(
        '{"desc_name":"%s","immediately_start":%s,"match_timeout":%d,"player_number":%d,"project_version":"%s"}',
        descName, tostring(immediatelyStart), matchTimeout, playerNumber, projectVersion)
    local matchInfo = {
        desc_name = descName,
        player_number = playerNumber,
        immediately_start = immediatelyStart,
        match_timeout = matchTimeout,
        mode_id = modeId,
    }

    local matchParams = {
        mapName = config.mapName,
        mode = config.mode,
        matchInfo = matchInfo,
    }

    print("[LobbyUI] StartQuickMatch params: mapName=" .. tostring(matchParams.mapName)
        .. ", mode=" .. tostring(matchParams.mode)
        .. ", player_number=" .. tostring(matchParams.matchInfo.player_number)
        .. ", mode_id=" .. tostring(matchParams.matchInfo.mode_id)
        .. ", desc_name=" .. tostring(matchParams.matchInfo.desc_name)
        .. ", match_timeout=" .. tostring(matchParams.matchInfo.match_timeout))

    -- 延迟执行函数
    local function delayedCall(delay, callback)
        local elapsed = 0
        local fired = false
        cancelBackgroundRetryTimer()
        local token = backgroundMatchState.retryTimerToken
        backgroundMatchState.retryTimerNode = Node()
        backgroundMatchState.retryTimerObject = backgroundMatchState.retryTimerNode:CreateScriptObject("LuaScriptObject")
        backgroundMatchState.retryTimerObject:SubscribeToEvent("Update", function(self, eventType, eventData)
            if fired or token ~= backgroundMatchState.retryTimerToken then return end
            elapsed = elapsed + eventData["TimeStep"]:GetFloat()
            if elapsed >= delay then
                fired = true
                cancelBackgroundRetryTimer()
                callback()
            end
        end)
    end

    -- 重试匹配的函数
    local function retryMatch()
        backgroundMatchState.retryCount = backgroundMatchState.retryCount + 1
        if backgroundMatchState.retryCount > backgroundMatchState.maxRetries then
            print("[LobbyUI] Background match failed after " .. backgroundMatchState.maxRetries .. " retries, giving up")
            backgroundMatchState.isMatching = false
            cancelBackgroundRetryTimer()
            return
        end

        print("[LobbyUI] Background match retry " .. backgroundMatchState.retryCount .. "/" .. backgroundMatchState.maxRetries .. " in " .. backgroundMatchState.retryDelay .. "s...")

        delayedCall(backgroundMatchState.retryDelay, function()
            doStartMatchWithRetry()
        end)
    end

    -- Function to start match (forward declaration for recursive call)
    local doStartMatch

    -- 带重试的匹配启动函数
    function doStartMatchWithRetry()
        -- 先离开当前房间（如果有的话），然后重新创建
        if LobbyUIInstance.lobbyMgr:IsInRoom() then
            print("[LobbyUI] Leaving current room before retry...")
            LobbyUIInstance.lobbyMgr:LeaveRoom({
                onSuccess = function()
                    print("[LobbyUI] Left room, creating new room for retry...")
                    createRoomAndMatch()
                end,
                onError = function()
                    print("[LobbyUI] Failed to leave room, trying to create new room anyway...")
                    createRoomAndMatch()
                end
            })
        else
            createRoomAndMatch()
        end
    end

    -- 创建房间并开始匹配
    function createRoomAndMatch()
        LobbyUIInstance.lobbyMgr:CreateRoom({
            mapName = config.mapName,
            maxPlayers = matchMaxPlayers,
            mode = config.mode,
            onSuccess = function(roomId)
                print("[LobbyUI] Room created: " .. tostring(roomId) .. ", starting match...")
                doStartMatch()
            end,
            onError = function(errorCode)
                print("[LobbyUI] Failed to create room: " .. FormatInt(errorCode) .. ", will retry...")
                retryMatch()
            end
        })
    end

    -- Function to start match
    doStartMatch = function()
        local requestId = LobbyUIInstance.lobbyMgr:StartMatch({
            mapName = matchParams.mapName,
            mode = matchParams.mode,
            matchInfo = matchParams.matchInfo,
            onMatchFound = function(serverInfo)
                print("[LobbyUI] Background match found!")
                backgroundMatchState.isMatching = false
                backgroundMatchState.retryCount = 0
                -- Trigger the onGameStart callback if set
                if config.onGameStart then
                    config.onGameStart(serverInfo)
                end
            end,
            onError = function(errorCode)
                -- 封禁是终态，重试只会拿到同一个码，直接停
                if errorCode == LobbyUI.MATCH_ERROR_PLAYER_BANNED then
                    print("[LobbyUI] Background match blocked by player ban, stop retrying")
                    backgroundMatchState.isMatching = false
                    return
                end
                print("[LobbyUI] Background match error: " .. FormatInt(errorCode) .. ", will retry...")
                retryMatch()
            end
        })
        print("[LobbyUI] StartQuickMatch requestId: " .. tostring(requestId))
    end

    -- Check if already in room, create one if not
    if not LobbyUIInstance.lobbyMgr:IsInRoom() then
        print("[LobbyUI] Not in room, creating temporary room for background match...")
        createRoomAndMatch()
    else
        print("[LobbyUI] Already in room, starting background match directly...")
        doStartMatch()
    end

    return true
end

--- Restart background match after game session ended
--- Resets state and re-initiates quick match flow
function LobbyUI.RestartBackgroundMatch()
    print("[LobbyUI] Restarting background match after game session ended")

    -- Reset background match state for fresh retry cycle
    backgroundMatchState.isMatching = false
    backgroundMatchState.retryCount = 0
    cancelBackgroundRetryTimer()

    -- Re-initiate quick match
    LobbyUI.StartQuickMatch()
end

return LobbyUI
