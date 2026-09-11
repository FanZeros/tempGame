-- ====================================================================
-- Renderer_BuffEffects.lua — 治疗/Buff特效与伤害飘字（从 Renderer.lua 拆分）
-- ====================================================================
-- 包含治疗、神佑、圣树冲击波、静神/风暴/祈祷/祝福Buff特效、伤害飘字
-- ====================================================================

local GS = require("GameState")
local Utils = require("Renderer_Utils")
local safeProgress = Utils.safeProgress

local sub = {}

function sub.init(M)

-- ====================================================================
-- 绘制：治疗特效（羁绊链接）
-- ====================================================================
function M.drawHealEffects()
    local vg = M.vg
    for _, e in ipairs(GS.healEffects) do
        local hasUnit = e.unit and e.unit.hp and e.unit.hp > 0
        local ex = hasUnit and e.unit.x or e.x
        local ey = hasUnit and e.unit.y or e.y
        local ox, oy = 0, 0
        if hasUnit then ox, oy = M.getMoveAnimOffset(e.unit) end
        local cx = GS.BOARD_X + (ex - 0.5) * GS.CELL + ox
        local cy = GS.BOARD_Y + (ey - 0.5) * GS.CELL + oy
        local t = safeProgress(e.timer, e.duration)  -- 0→1
        local halfCell = GS.CELL * 0.5

        -- 大量绿色粒子从底部升腾向上消散
        for i = 1, 140 do
            -- 每颗粒子有不同的相位，错开出现时间
            local phase = (i - 1) / 140
            local pt = t - phase * 0.35  -- 延迟出生
            if pt > 0 and pt < 1 then
                -- 水平散布：围绕角色中心，随上升逐渐向外扩散
                local seed = i * 137.5  -- 黄金角散布
                local spread = halfCell * (0.5 + pt * 0.4)  -- 上升时扩散
                local xOff = math.sin(seed) * spread
                -- 从底部升起，越高越淡
                local rise = pt * GS.CELL * 1.2
                local px = cx + xOff + math.sin(pt * 3 + seed) * 3  -- 微微飘动
                local py = cy + halfCell - rise  -- 从棋子底部往上升

                -- 透明度：出现时淡入，上升后淡出
                local fadeIn = math.min(pt * 5, 1.0)
                local fadeOut = math.max(1.0 - pt, 0)
                local alpha = math.floor(200 * fadeIn * fadeOut)

                -- 粒子大小：淡入后保持稳定，只在最后阶段缩小
                local baseSize = 2.0 + math.sin(seed * 0.7) * 1.5
                local size = baseSize * fadeIn * (0.6 + fadeOut * 0.4)

                local pGrad = nvgRadialGradient(vg, px, py, 0, size,
                    nvgRGBA(120, 255, 150, alpha),
                    nvgRGBA(80, 220, 100, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, size)
                nvgFillPaint(vg, pGrad)
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：神佑特效（神圣金色粒子自下而上升腾）
-- ====================================================================
function M.drawDivineGraceEffects()
    local vg = M.vg
    for _, e in ipairs(GS.divineGraceEffects) do
        local ox, oy = 0, 0
        if e.unit then ox, oy = M.getMoveAnimOffset(e.unit) end
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL + ox
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL + oy
        local t = safeProgress(e.timer, e.duration)  -- 0→1
        local halfCell = GS.CELL * 0.5

        -- 神圣金色粒子从底部升腾
        for i = 1, 140 do
            local phase = (i - 1) / 140
            local pt = t - phase * 0.35
            if pt > 0 and pt < 1 then
                local seed = i * 137.5
                local spread = halfCell * (0.5 + pt * 0.4)
                local xOff = math.sin(seed) * spread
                local rise = pt * GS.CELL * 1.2
                local px = cx + xOff + math.sin(pt * 3 + seed) * 3
                local py = cy + halfCell - rise

                local fadeIn = math.min(pt * 5, 1.0)
                local fadeOut = math.max(1.0 - pt, 0)
                local alpha = math.floor(200 * fadeIn * fadeOut)

                local baseSize = 2.0 + math.sin(seed * 0.7) * 1.5
                local size = baseSize * fadeIn * (0.6 + fadeOut * 0.4)

                -- 神圣色：金黄色核心 → 暖白色外圈
                local pGrad = nvgRadialGradient(vg, px, py, 0, size,
                    nvgRGBA(255, 220, 100, alpha),
                    nvgRGBA(255, 200, 60, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, size)
                nvgFillPaint(vg, pGrad)
                nvgFill(vg)
            end
        end

        -- 十字光芒闪烁（神圣标识）
        if t > 0.1 and t < 0.7 then
            local flashT = (t - 0.1) / 0.6
            local flashAlpha = math.floor(180 * math.sin(flashT * math.pi))
            local crossLen = halfCell * 0.6 * math.sin(flashT * math.pi)
            local crossW = math.max(1.5, GS.CELL * 0.03)

            nvgSave(vg)
            nvgTranslate(vg, cx, cy - halfCell * 0.3)
            -- 竖线
            nvgBeginPath(vg)
            nvgRect(vg, -crossW / 2, -crossLen / 2, crossW, crossLen)
            nvgFillColor(vg, nvgRGBA(255, 240, 180, flashAlpha))
            nvgFill(vg)
            -- 横线
            nvgBeginPath(vg)
            nvgRect(vg, -crossLen / 2, -crossW / 2, crossLen, crossW)
            nvgFillColor(vg, nvgRGBA(255, 240, 180, flashAlpha))
            nvgFill(vg)
            nvgRestore(vg)
        end
    end
end

-- ====================================================================
-- 绘制：圣树冲击波特效（神圣金色圆环向外扩散）
-- ====================================================================
function M.drawHolyTreeWaveEffects()
    local vg = M.vg
    for _, e in ipairs(GS.holyTreeWaveEffects) do
        local ox, oy = 0, 0
        if e.unit then ox, oy = M.getMoveAnimOffset(e.unit) end
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL + ox
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL + oy
        local t = safeProgress(e.timer, e.duration)  -- 0→1
        local maxRadius = (e.healRange + 0.5) * GS.CELL

        -- 圆环从圣树中心向外扩散
        local radius = t * maxRadius
        local ringWidth = GS.CELL * 0.15 * (1 - t * 0.5)  -- 环宽度逐渐变窄

        -- 淡出：前半段不透明，后半段渐隐
        local fadeIn = math.min(t * 4, 1.0)
        local fadeOut = math.max(1.0 - (t - 0.5) * 2, 0)
        local alpha = fadeIn * fadeOut

        -- 外环光晕（宽扩散）
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius + ringWidth)
        nvgCircle(vg, cx, cy, math.max(0, radius - ringWidth))
        nvgPathWinding(vg, NVG_HOLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 100, math.floor(60 * alpha)))
        nvgFill(vg)

        -- 核心亮环（细线）
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius)
        nvgStrokeColor(vg, nvgRGBA(255, 230, 140, math.floor(200 * alpha)))
        nvgStrokeWidth(vg, math.max(1, ringWidth * 0.4))
        nvgStroke(vg)

        -- 环上散布金色光点
        local dotCount = math.floor(20 + e.healRange * 10)
        for i = 1, dotCount do
            local angle = (i - 1) / dotCount * math.pi * 2 + t * 2
            local dotR = radius + math.sin(angle * 3 + t * 5) * ringWidth * 0.5
            local dx = cx + math.cos(angle) * dotR
            local dy = cy + math.sin(angle) * dotR
            local dotAlpha = math.floor(180 * alpha * (0.5 + 0.5 * math.sin(i * 2.3 + t * 8)))
            local dotSize = 1.0 + math.sin(i * 1.7) * 0.5
            nvgBeginPath(vg)
            nvgCircle(vg, dx, dy, dotSize)
            nvgFillColor(vg, nvgRGBA(255, 240, 180, dotAlpha))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：辉光扩散特效（神圣色光圈从玩家向外扩散至范围边界，带粒子）
-- ====================================================================
function M.drawRadianceWaveEffects()
    local vg = M.vg
    for _, e in ipairs(GS.radianceWaveEffects) do
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local t = safeProgress(e.timer, e.duration)  -- 0→1
        -- 扩散至辉光作用范围（格数 * 格子尺寸）
        local rangeInCells = e.range or 2
        local maxRadius = (rangeInCells + 0.5) * GS.CELL
        local radius = t * maxRadius

        -- 淡入淡出
        local fadeIn  = math.min(t * 6, 1.0)
        local fadeOut = math.max(1.0 - (t - 0.4) * 1.7, 0)
        local alpha   = fadeIn * fadeOut

        -- === 外层柔和光晕环 ===
        local ringW = GS.CELL * 0.25 * (1 - t * 0.6)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius + ringW)
        nvgCircle(vg, cx, cy, math.max(0, radius - ringW))
        nvgPathWinding(vg, NVG_HOLE)
        -- 神圣暖金色外晕
        nvgFillColor(vg, nvgRGBA(255, 220, 140, math.floor(50 * alpha)))
        nvgFill(vg)

        -- === 核心亮环（细线） ===
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius)
        nvgStrokeColor(vg, nvgRGBA(255, 235, 180, math.floor(210 * alpha)))
        nvgStrokeWidth(vg, math.max(1.5, ringW * 0.5))
        nvgStroke(vg)

        -- === 内侧辉光渐变填充（中心→环半径，淡金色） ===
        if t < 0.5 then
            local innerAlpha = math.floor(40 * (1 - t * 2) * alpha)
            local grad = nvgRadialGradient(vg, cx, cy, 0, radius,
                nvgRGBA(255, 240, 200, innerAlpha),
                nvgRGBA(255, 220, 140, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end

        -- === 环上运动粒子（数量随范围缩放） ===
        local dotCount = math.floor(12 + rangeInCells * 6 + t * 10)
        for i = 1, dotCount do
            -- 每个粒子以不同速度沿环运动
            local seed = i * 137.5
            local speed = 1.5 + math.sin(seed * 0.3) * 0.8
            local angle = seed + t * speed * math.pi * 2
            -- 粒子在环的法线方向上微小偏移
            local wobble = math.sin(seed * 2.1 + t * 8) * ringW * 0.6
            local dotR = radius + wobble
            local dx = cx + math.cos(angle) * dotR
            local dy = cy + math.sin(angle) * dotR

            -- 粒子脉冲闪烁
            local pulse = 0.4 + 0.6 * math.sin(seed * 0.9 + t * 10)
            local dotAlpha = math.floor(200 * alpha * pulse)
            local dotSize = 1.5 + math.sin(seed * 1.7) * 0.8

            -- 粒子核心（暖白/淡金）
            local pGrad = nvgRadialGradient(vg, dx, dy, 0, dotSize * 1.5,
                nvgRGBA(255, 245, 210, dotAlpha),
                nvgRGBA(255, 210, 120, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, dx, dy, dotSize * 1.5)
            nvgFillPaint(vg, pGrad)
            nvgFill(vg)
        end

        -- === 十字光芒闪烁（中心神圣标识，短暂） ===
        if t < 0.35 then
            local flashT = t / 0.35
            local flashAlpha = math.floor(180 * math.sin(flashT * math.pi))
            local crossLen = GS.CELL * 0.5 * math.sin(flashT * math.pi)
            local crossW2 = math.max(1.5, GS.CELL * 0.04)
            nvgSave(vg)
            nvgTranslate(vg, cx, cy)
            nvgBeginPath(vg)
            nvgRect(vg, -crossW2 / 2, -crossLen / 2, crossW2, crossLen)
            nvgFillColor(vg, nvgRGBA(255, 245, 200, flashAlpha))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRect(vg, -crossLen / 2, -crossW2 / 2, crossLen, crossW2)
            nvgFillColor(vg, nvgRGBA(255, 245, 200, flashAlpha))
            nvgFill(vg)
            nvgRestore(vg)
        end
    end
end

-- ====================================================================
-- 绘制：静神buff持续光芒
-- ====================================================================
function M.drawFocusBuffEffect()
    if GS.focusBuffTurns <= 0 then return end
    local p = GS.player
    if not p or p.hp <= 0 then return end
    local vg = M.vg
    local ox, oy = M.getMoveAnimOffset(p)
    local cx = GS.BOARD_X + (p.x - 0.5) * GS.CELL + ox
    local cy = GS.BOARD_Y + (p.y - 0.5) * GS.CELL + oy
    local halfCell = GS.CELL * 0.5
    local time = GetTime():GetElapsedTime()

    -- 100个绿色粒子环绕在玩家棋子外围旋转
    for i = 1, 100 do
        local seed = i * 137.5
        local speed = 0.6 + math.sin(seed * 0.3) * 0.3
        local angle = seed + time * speed
        local baseR = halfCell * 0.85
        local radius = baseR + math.sin(seed * 0.5 + time * 2) * halfCell * 0.1
        local px = cx + math.cos(angle) * radius
        local py = cy + math.sin(angle) * radius
        local pulse = 0.4 + 0.6 * math.sin(seed * 0.9 + time * 3)
        local alpha = math.floor(180 * pulse)
        local size = 1.0 + math.sin(seed * 0.7) * 0.4
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(120, 255, 150, alpha))
        nvgFill(vg)
    end
end

-- ====================================================================
-- 绘制：风暴buff持续红色粒子（参考静神，红色色调）
-- ====================================================================
function M.drawStormBuffEffect()
    if GS.stormBuffTurns <= 0 then return end
    local p = GS.player
    if not p or p.hp <= 0 then return end
    local vg = M.vg
    local ox, oy = M.getMoveAnimOffset(p)
    local cx = GS.BOARD_X + (p.x - 0.5) * GS.CELL + ox
    local cy = GS.BOARD_Y + (p.y - 0.5) * GS.CELL + oy
    local halfCell = GS.CELL * 0.5
    local time = GetTime():GetElapsedTime()

    -- 100个红色粒子环绕在玩家棋子外围旋转
    for i = 1, 100 do
        local seed = i * 137.5
        local speed = 0.8 + math.sin(seed * 0.3) * 0.4
        local angle = seed + time * speed
        local baseR = halfCell * 0.85
        local radius = baseR + math.sin(seed * 0.5 + time * 2.5) * halfCell * 0.12
        local px = cx + math.cos(angle) * radius
        local py = cy + math.sin(angle) * radius
        local pulse = 0.4 + 0.6 * math.sin(seed * 0.9 + time * 3.5)
        local alpha = math.floor(180 * pulse)
        local size = 1.0 + math.sin(seed * 0.7) * 0.4
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(255, 90, 60, alpha))
        nvgFill(vg)
    end
end

-- ====================================================================
-- 绘制：祈祷术BUFF特效（神圣光环环绕旋转）
-- ====================================================================
function M.drawPrayerBuffEffect()
    local p = GS.player
    if not p or p.hp <= 0 then return end
    if not p.prayerTurns or p.prayerTurns <= 0 then return end
    local vg = M.vg
    local ox, oy = M.getMoveAnimOffset(p)
    local cx = GS.BOARD_X + (p.x - 0.5) * GS.CELL + ox
    local cy = GS.BOARD_Y + (p.y - 0.5) * GS.CELL + oy
    local halfCell = GS.CELL * 0.5
    local time = GetTime():GetElapsedTime()

    -- 三圈神圣光环，彼此倾斜交叠，粒子小而密
    -- 每圈的倾斜轴：用不同的 tiltX/tiltY 让环面朝不同方向
    local ringDefs = {
        { speed = 1.4, radius = halfCell * 0.75, tiltX = 0.25,  tiltY = 0.85, phase = 0 },
        { speed = 1.9, radius = halfCell * 0.80, tiltX = -0.70, tiltY = 0.55, phase = 2.094 },
        { speed = 1.1, radius = halfCell * 0.72, tiltX = 0.60,  tiltY = -0.65, phase = 4.189 },
    }
    for ring = 1, 3 do
        local rd = ringDefs[ring]
        local baseAngle = time * rd.speed + rd.phase

        -- 每圈 80~100 个光点（原 8~12 的 10 倍）
        local dotCount = 80 + ring * 10
        for i = 1, dotCount do
            local angle = baseAngle + (i - 1) / dotCount * math.pi * 2
            -- 3D 圆环上的点：先在 XZ 平面画圆，再用倾斜系数投影到 2D
            local rx = math.cos(angle) * rd.radius
            local ry = math.sin(angle) * rd.radius
            -- 倾斜投影：tiltX 控制环面的左右倾斜，tiltY 控制前后倾斜
            local px = cx + rx
            local py = cy + ry * rd.tiltX + rx * rd.tiltY * 0.3

            -- 深度感：用 angle 模拟前后关系
            local depth = math.sin(angle + rd.phase * 0.5)
            local depthAlpha = 0.45 + 0.55 * depth
            local pulse = 0.7 + 0.3 * math.sin(time * 3.5 + i * 0.5)
            local alpha = math.floor(140 * depthAlpha * pulse)

            -- 粒子大小缩小一半
            local size = (0.75 + 0.25 * depth) * (0.4 + ring * 0.05)

            -- 神圣金色光点
            local grad = nvgRadialGradient(vg, px, py, 0, size * 1.5,
                nvgRGBA(255, 230, 120, alpha),
                nvgRGBA(255, 200, 60, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, size * 1.5)
            nvgFillPaint(vg, grad)
            nvgFill(vg)

            -- 核心亮点
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, size * 0.3)
            nvgFillColor(vg, nvgRGBA(255, 255, 220, math.floor(alpha * 0.7)))
            nvgFill(vg)
        end
    end

    -- 底部柔和的圆形光晕
    local glowPulse = 0.6 + 0.4 * math.sin(time * 2.0)
    local glowR = halfCell * 0.9
    local glowGrad = nvgRadialGradient(vg, cx, cy + halfCell * 0.1, 0, glowR,
        nvgRGBA(255, 220, 100, math.floor(30 * glowPulse)),
        nvgRGBA(255, 200, 60, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy + halfCell * 0.1, glowR)
    nvgFillPaint(vg, glowGrad)
    nvgFill(vg)
end

-- ====================================================================
-- 绘制：祝福BUFF粒子环效果（圣泉/征服/庇护/奇迹）
-- ====================================================================
---@param turnsField string 回合数字段名
---@param r number 红
---@param g number 绿
---@param b number 蓝
---@param speedMul number 速度倍率
local function drawBlessingParticleRing(turnsField, r, g, b, speedMul)
    local p = GS.player
    if not p or p.hp <= 0 then return end
    if not p[turnsField] or p[turnsField] <= 0 then return end
    local vg = M.vg
    local ox, oy = M.getMoveAnimOffset(p)
    local cx = GS.BOARD_X + (p.x - 0.5) * GS.CELL + ox
    local cy = GS.BOARD_Y + (p.y - 0.5) * GS.CELL + oy
    local halfCell = GS.CELL * 0.5
    local time = GetTime():GetElapsedTime()

    for i = 1, 60 do
        local seed = i * 137.5 + r * 0.1
        local speed = (0.5 + math.sin(seed * 0.3) * 0.25) * speedMul
        local angle = seed + time * speed
        local baseR = halfCell * 0.90
        local radius = baseR + math.sin(seed * 0.5 + time * 1.8) * halfCell * 0.08
        local px = cx + math.cos(angle) * radius
        local py = cy + math.sin(angle) * radius
        local pulse = 0.3 + 0.7 * math.sin(seed * 0.9 + time * 2.5)
        local alpha = math.floor(160 * pulse)
        local size = 0.8 + math.sin(seed * 0.7) * 0.3
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
        nvgFill(vg)
    end
end

function M.drawHolySpringBuffEffect()
    drawBlessingParticleRing("holySpringTurns", 80, 180, 255, 0.7)
end

function M.drawConquerBuffEffect()
    drawBlessingParticleRing("conquerTurns", 255, 70, 50, 0.9)
end

function M.drawShelterBuffEffect()
    drawBlessingParticleRing("shelterTurns", 40, 40, 50, 0.6)
end

function M.drawMiracleBuffEffect()
    drawBlessingParticleRing("miracleTurns", 255, 220, 100, 0.8)
end

-- ====================================================================
-- 绘制：伤害飘字
-- ====================================================================
function M.drawDamageTexts()
    if not GS.showDamageNumbers then return end
    local vg = M.vg
    for _, d in ipairs(GS.damageTexts) do
        if d.pendingHit then goto continueDmgText end  -- 弹道未命中，不显示
        if d.delay and d.delay > 0 then goto continueDmgText end  -- 延迟未结束，不显示
        local alpha = math.floor(255 * (1 - d.timer / d.duration))
        if alpha <= 0 then goto continueDmgText end
        local yOff = -d.timer * 40 + (d.yOffset or 0)
        local xOff = d.xOffset or 0
        local px = GS.BOARD_X + (d.x - 0.5) * GS.CELL + xOff
        local py = GS.BOARD_Y + (d.y - 0.5) * GS.CELL + yOff

        local baseScale = d.scale or 1.0
        local isCritText = baseScale > 1.0
        local isBlock = d.style == "block"
        local finalScale = baseScale

        -- 暴击弹出缩放：前0.15秒从2.5倍缩到目标倍数
        if isCritText then
            local popDur = 0.15
            if d.timer < popDur then
                local t = d.timer / popDur
                -- ease-out: 快速收缩
                t = 1 - (1 - t) * (1 - t)
                finalScale = baseScale + (2.5 - baseScale) * (1 - t)
            end
        end

        -- 格挡碰撞感：倾斜弹入 + 震动 + 放大回弹
        if isBlock then
            local impactDur = 0.12  -- 碰撞阶段
            local settleDur = 0.2   -- 回稳阶段
            local angle, scaleBoost, shakeX = 0, 0, 0
            if d.timer < impactDur then
                -- 碰撞阶段：大角度倾斜 + 放大
                local t = d.timer / impactDur
                local easeT = 1 - (1 - t) * (1 - t)  -- ease-out
                angle = -15 * (1 - easeT)  -- 从-15度快速回正
                scaleBoost = 0.6 * (1 - easeT)  -- 从1.6倍缩回
                shakeX = (1 - easeT) * 4 * math.sin(t * 3.14159 * 4)  -- 水平震动
            elseif d.timer < impactDur + settleDur then
                -- 回稳阶段：微小角度残留 + 衰减
                local t2 = (d.timer - impactDur) / settleDur
                angle = 5 * (1 - t2) * math.sin(t2 * 3.14159 * 2)  -- 小幅左右摆动衰减
            end
            finalScale = finalScale + scaleBoost
            px = px + shakeX
            nvgSave(vg)
            nvgTranslate(vg, px, py)
            nvgRotate(vg, angle * 3.14159 / 180)
            nvgScale(vg, finalScale, finalScale)

            local fontSize = 20
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 粗描边轮廓
            local ol = 2
            nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
            nvgText(vg, -ol, 0, d.text, nil)
            nvgText(vg, ol, 0, d.text, nil)
            nvgText(vg, 0, -ol, d.text, nil)
            nvgText(vg, 0, ol, d.text, nil)
            nvgFillColor(vg, nvgRGBA(d.color[1], d.color[2], d.color[3], alpha))
            nvgText(vg, 0, 0, d.text, nil)
            nvgRestore(vg)
            goto continueDmgText
        end

        local fontSize = 20 * finalScale
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        if isCritText then
            -- 暴击描边：4方向偏移绘制黑色轮廓，比普通阴影更粗
            local ol = 2
            nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
            nvgText(vg, px - ol, py, d.text, nil)
            nvgText(vg, px + ol, py, d.text, nil)
            nvgText(vg, px, py - ol, d.text, nil)
            nvgText(vg, px, py + ol, d.text, nil)
        else
            -- 普通伤害：单方向阴影
            nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
            nvgText(vg, px + 1, py + 1, d.text, nil)
        end
        nvgFillColor(vg, nvgRGBA(d.color[1], d.color[2], d.color[3], alpha))
        nvgText(vg, px, py, d.text, nil)
        ::continueDmgText::
    end
end

-- ====================================================================
-- 绘制：默示录 奥术紫色爆炸光环
-- ====================================================================
function M.drawApocalypseAoeEffects()
    local vg = M.vg
    for _, e in ipairs(GS.apocalypseAoeEffects) do
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local t = safeProgress(e.timer, e.duration)  -- 0→1

        -- 基于 range 的最大扩散半径（格子级别）
        local maxRadius = (e.range + 0.6) * GS.CELL

        -- 爆炸式扩散：先快后慢（easeOutQuad）
        local easeT = 1 - (1 - t) * (1 - t)
        local radius = easeT * maxRadius

        -- 淡入淡出
        local fadeIn  = math.min(t * 8, 1.0)
        local fadeOut = math.max(1.0 - (t - 0.3) * 1.5, 0)
        local alpha   = fadeIn * fadeOut

        -- === 外层柔和紫色光晕环 ===
        local ringW = GS.CELL * 0.3 * (1 - t * 0.5)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius + ringW)
        nvgCircle(vg, cx, cy, math.max(0, radius - ringW))
        nvgPathWinding(vg, NVG_HOLE)
        nvgFillColor(vg, nvgRGBA(160, 60, 240, math.floor(60 * alpha)))
        nvgFill(vg)

        -- === 核心亮环（细线，亮紫） ===
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius)
        nvgStrokeColor(vg, nvgRGBA(200, 130, 255, math.floor(230 * alpha)))
        nvgStrokeWidth(vg, math.max(2.0, ringW * 0.6))
        nvgStroke(vg)

        -- === 第二层内环（稍小，深紫色） ===
        if t < 0.7 then
            local innerR = radius * 0.7
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, innerR)
            nvgStrokeColor(vg, nvgRGBA(140, 40, 220, math.floor(120 * alpha * (1 - t))))
            nvgStrokeWidth(vg, math.max(1.0, ringW * 0.3))
            nvgStroke(vg)
        end

        -- === 内侧辐射渐变填充（中心→环半径，暗紫） ===
        if t < 0.5 then
            local innerAlpha = math.floor(45 * (1 - t * 2) * alpha)
            local grad = nvgRadialGradient(vg, cx, cy, 0, radius,
                nvgRGBA(180, 100, 255, innerAlpha),
                nvgRGBA(120, 30, 200, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end

        -- === 环上运动粒子（奥术紫色） ===
        local dotCount = math.floor(20 + t * 25)
        for i = 1, dotCount do
            local seed = i * 137.5
            local speed = 2.0 + math.sin(seed * 0.3) * 1.0
            local angle = seed + t * speed * math.pi * 2
            -- 粒子在环内外摆动
            local wobble = math.sin(seed * 2.1 + t * 10) * ringW * 0.8
            local dotR = radius + wobble
            local dx = cx + math.cos(angle) * dotR
            local dy = cy + math.sin(angle) * dotR

            -- 脉冲闪烁
            local pulse = 0.3 + 0.7 * math.sin(seed * 0.9 + t * 12)
            local dotAlpha = math.floor(220 * alpha * pulse)
            local dotSize = 1.8 + math.sin(seed * 1.7) * 1.0

            -- 粒子核心（亮紫/白紫渐变）
            local pGrad = nvgRadialGradient(vg, dx, dy, 0, dotSize * 1.8,
                nvgRGBA(220, 180, 255, dotAlpha),
                nvgRGBA(140, 40, 220, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, dx, dy, dotSize * 1.8)
            nvgFillPaint(vg, pGrad)
            nvgFill(vg)
        end

        -- === 中心六芒星闪烁（奥术标识） ===
        if t < 0.4 then
            local flashT = t / 0.4
            local flashAlpha = math.floor(200 * math.sin(flashT * math.pi))
            local starLen = GS.CELL * 0.45 * math.sin(flashT * math.pi)
            nvgSave(vg)
            nvgTranslate(vg, cx, cy)
            -- 三条交叉线（0°、60°、120°）形成六芒星
            for a = 0, 2 do
                local rot = a * math.pi / 3
                nvgSave(vg)
                nvgRotate(vg, rot)
                nvgBeginPath(vg)
                nvgRect(vg, -1.0, -starLen / 2, 2.0, starLen)
                nvgFillColor(vg, nvgRGBA(200, 160, 255, flashAlpha))
                nvgFill(vg)
                nvgRestore(vg)
            end
            nvgRestore(vg)
        end

        -- === 径向爆裂线条（从中心向外的短线，强化爆炸感） ===
        if t < 0.55 then
            local burstAlpha = math.floor(150 * alpha * (1 - t / 0.55))
            local lineCount = 12
            for i = 1, lineCount do
                local angle = (i / lineCount) * math.pi * 2 + t * 0.5
                local r1 = radius * 0.3
                local r2 = radius * 0.65
                local x1 = cx + math.cos(angle) * r1
                local y1 = cy + math.sin(angle) * r1
                local x2 = cx + math.cos(angle) * r2
                local y2 = cy + math.sin(angle) * r2
                nvgBeginPath(vg)
                nvgMoveTo(vg, x1, y1)
                nvgLineTo(vg, x2, y2)
                nvgStrokeColor(vg, nvgRGBA(180, 100, 255, burstAlpha))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end
        end
    end
end

end -- sub.init

return sub
