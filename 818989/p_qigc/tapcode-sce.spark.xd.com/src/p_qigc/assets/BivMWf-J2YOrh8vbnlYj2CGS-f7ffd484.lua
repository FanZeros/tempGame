-- ====================================================================
-- Renderer_SpellEffects.lua — 法术视觉特效绘制（从 Renderer.lua 拆分）
-- ====================================================================
-- 包含吟唱魔法阵、吟唱粒子升腾、魔法盾、冰墙创建、闪烁传送特效
-- ====================================================================

local GS = require("GameState")
local Utils = require("Renderer_Utils")
local safeProgress = Utils.safeProgress

local sub = {}

function sub.init(M)

-- ====================================================================
-- 绘制：法术吟唱魔力粒子升腾效果（持续型，GS.chanting 存在时渲染）
-- ====================================================================
-- 底部魔法阵（在棋子下方绘制，需在 drawUnits 之前调用）
function M.drawChantingCircle()
    if not GS.chanting then return end
    local p = GS.player
    if not p or p.hp <= 0 then return end
    local vg = M.vg
    local ox, oy = M.getMoveAnimOffset(p)
    local cx = GS.BOARD_X + (p.x - 0.5) * GS.CELL + ox
    local cy = GS.BOARD_Y + (p.y - 0.5) * GS.CELL + oy
    local halfCell = GS.CELL * 0.5
    local time = GetTime():GetElapsedTime()

    local skillDef = GS.SKILL_DEFS[GS.chanting.skillId]
    local element = skillDef and skillDef.element or "arcane"
    local palettes = {
        fire    = { aura1 = {255, 120, 40},  aura2 = {200, 60, 10}  },
        ice     = { aura1 = {100, 180, 255}, aura2 = {60, 140, 220} },
        thunder = { aura1 = {255, 220, 60},  aura2 = {220, 180, 20} },
        holy    = { aura1 = {255, 220, 100}, aura2 = {220, 180, 60} },
        arcane  = { aura1 = {160, 100, 255}, aura2 = {120, 60, 220} },
    }
    local pal = palettes[element] or palettes.arcane
    local a1 = pal.aura1
    local a2 = pal.aura2
    local auraPulse = (math.sin(time * 3.0) + 1) * 0.5
    local circleY = cy + halfCell * 0.8  -- 略高于棋子底部
    local circleRx = halfCell * 0.95
    local circleRy = circleRx * 0.38

    -- 底层辉光
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, circleY, circleRx * 1.3, circleRy * 1.3)
    local glowGrad = nvgRadialGradient(vg, cx, circleY, circleRx * 0.1, circleRx * 1.3,
        nvgRGBA(a1[1], a1[2], a1[3], math.floor(60 + 30 * auraPulse)),
        nvgRGBA(a2[1], a2[2], a2[3], 0))
    nvgFillPaint(vg, glowGrad)
    nvgFill(vg)

    -- 内圈填充
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, circleY, circleRx * 0.55, circleRy * 0.55)
    local innerGrad = nvgRadialGradient(vg, cx, circleY, 0, circleRx * 0.55,
        nvgRGBA(a1[1], a1[2], a1[3], math.floor(50 + 25 * auraPulse)),
        nvgRGBA(a1[1], a1[2], a1[3], math.floor(20 + 10 * auraPulse)))
    nvgFillPaint(vg, innerGrad)
    nvgFill(vg)

    -- 外圈环线
    local ringAlpha = math.floor(160 + 60 * auraPulse)
    local segments = 60
    local rotAngle = time * 0.8
    nvgBeginPath(vg)
    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2 + rotAngle
        local px = cx + math.cos(angle) * circleRx
        local py = circleY + math.sin(angle) * circleRy
        if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgStrokeColor(vg, nvgRGBA(a1[1], a1[2], a1[3], ringAlpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 内圈环线（反向）
    local innerRx = circleRx * 0.6
    local innerRy = circleRy * 0.6
    nvgBeginPath(vg)
    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2 - time * 1.2
        local px = cx + math.cos(angle) * innerRx
        local py = circleY + math.sin(angle) * innerRy
        if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgStrokeColor(vg, nvgRGBA(a1[1], a1[2], a1[3], math.floor(ringAlpha * 0.7)))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 外圈菱形符文（6个）
    local runeCount = 6
    for i = 1, runeCount do
        local angle = (i / runeCount) * math.pi * 2 + rotAngle
        local rx = cx + math.cos(angle) * circleRx
        local ry = circleY + math.sin(angle) * circleRy
        local ds = 2.5 + 0.8 * auraPulse
        nvgBeginPath(vg)
        nvgMoveTo(vg, rx, ry - ds * 0.4)
        nvgLineTo(vg, rx + ds, ry)
        nvgLineTo(vg, rx, ry + ds * 0.4)
        nvgLineTo(vg, rx - ds, ry)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(a1[1], a1[2], a1[3], ringAlpha))
        nvgFill(vg)
    end

    -- 六芒星连接线
    local starAlpha = math.floor(100 + 50 * auraPulse)
    nvgBeginPath(vg)
    for i = 1, runeCount do
        local a_from = (i / runeCount) * math.pi * 2 + rotAngle
        local a_to = ((i + 2) / runeCount) * math.pi * 2 + rotAngle
        local fx = cx + math.cos(a_from) * circleRx * 0.85
        local fy = circleY + math.sin(a_from) * circleRy * 0.85
        local tx = cx + math.cos(a_to) * circleRx * 0.85
        local ty = circleY + math.sin(a_to) * circleRy * 0.85
        nvgMoveTo(vg, fx, fy)
        nvgLineTo(vg, tx, ty)
    end
    nvgStrokeColor(vg, nvgRGBA(a1[1], a1[2], a1[3], starAlpha))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- 内圈圆点符文（4个，反向）
    for i = 1, 4 do
        local angle = (i / 4) * math.pi * 2 - time * 1.2
        local rx = cx + math.cos(angle) * innerRx
        local ry = circleY + math.sin(angle) * innerRy
        local ds2 = 1.8 + 0.5 * auraPulse
        nvgBeginPath(vg)
        nvgCircle(vg, rx, ry, ds2)
        nvgFillColor(vg, nvgRGBA(a1[1], a1[2], a1[3], math.floor(ringAlpha * 0.8)))
        nvgFill(vg)
    end
end

function M.drawChantingEffect()
    if not GS.chanting then return end
    local p = GS.player
    if not p or p.hp <= 0 then return end
    local vg = M.vg
    local ox, oy = M.getMoveAnimOffset(p)
    local cx = GS.BOARD_X + (p.x - 0.5) * GS.CELL + ox
    local cy = GS.BOARD_Y + (p.y - 0.5) * GS.CELL + oy
    local halfCell = GS.CELL * 0.5
    local time = GetTime():GetElapsedTime()

    -- 根据技能属性决定粒子颜色方案
    local skillDef = GS.SKILL_DEFS[GS.chanting.skillId]
    local element = skillDef and skillDef.element or "arcane"
    -- 每种属性5个色调变体 + 光环色 + 高亮色
    local palettes = {
        fire = {
            aura1 = {255, 120, 40}, aura2 = {200, 60, 10},
            variants = {{255, 140, 50}, {255, 100, 30}, {240, 80, 20}, {255, 170, 60}, {220, 90, 25}},
            highlight = {255, 200, 120}, glow = {255, 120, 40},
        },
        ice = {
            aura1 = {100, 180, 255}, aura2 = {60, 140, 220},
            variants = {{120, 200, 255}, {80, 170, 240}, {140, 220, 255}, {60, 150, 230}, {100, 190, 250}},
            highlight = {200, 230, 255}, glow = {100, 180, 255},
        },
        thunder = {
            aura1 = {255, 220, 60}, aura2 = {220, 180, 20},
            variants = {{255, 230, 80}, {255, 200, 40}, {240, 210, 60}, {255, 240, 100}, {220, 190, 30}},
            highlight = {255, 245, 180}, glow = {255, 220, 60},
        },
        holy = {
            aura1 = {255, 220, 100}, aura2 = {220, 180, 60},
            variants = {{255, 230, 120}, {255, 210, 80}, {240, 200, 90}, {255, 240, 140}, {230, 190, 70}},
            highlight = {255, 245, 200}, glow = {255, 220, 100},
        },
        arcane = {
            aura1 = {160, 100, 255}, aura2 = {120, 60, 220},
            variants = {{180, 120, 255}, {140, 80, 240}, {100, 140, 255}, {200, 160, 255}, {160, 100, 220}},
            highlight = {220, 200, 255}, glow = {160, 100, 255},
        },
    }
    local pal = palettes[element] or palettes.arcane

    -- ① 魔法阵已移至 drawChantingCircle()，在棋子下方绘制

    -- ② 主体粒子持续上升
    local particleCount = 175
    local cycleDuration = 2.2
    local riseHeight = GS.CELL * 1.2

    for i = 1, particleCount do
        local baseSeed = i * 137.508
        local phaseOffset = ((i - 1) / particleCount) * cycleDuration
        local localTime = (time + phaseOffset) % cycleDuration
        local t = localTime / cycleDuration
        -- 每个粒子每次重生获得不同种子（周期编号参与哈希）
        local cycle = math.floor((time + phaseOffset) / cycleDuration)
        local seed = baseSeed + cycle * 51.97

        local spawnSpread = halfCell * 0.55
        local baseX = math.sin(seed) * spawnSpread
        local baseY = math.cos(seed * 0.73) * halfCell * 0.1  -- 起点Y轻微随机
        local drift = math.sin(t * (3.0 + math.sin(seed * 0.4) * 2.0) + seed * 0.7) * halfCell * (0.2 + t * 0.4)
        local px = cx + baseX * (1 + t * 0.8) + drift

        local riseSpeed = 1.0 + math.sin(seed * 0.6) * 0.25  -- 上升速度随机 ±25%
        local rise = t * riseHeight * riseSpeed
        local py = cy + halfCell + baseY - rise

        local alpha
        if t < 0.1 then
            alpha = t / 0.1
        elseif t > 0.75 then
            alpha = 1 - (t - 0.75) / 0.25
        else
            alpha = 1.0
        end
        local flicker = 0.7 + 0.3 * math.sin(seed * 1.3 + time * 5)
        alpha = alpha * flicker

        local cv = pal.variants[(i % 5) + 1]
        local r, g, b = cv[1], cv[2], cv[3]

        local size = (0.6 + math.sin(seed * 0.5) * 0.25) * (1 - t * 0.4)

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 200)))
        nvgFill(vg)
    end

    -- ③ 高亮粒子（更慢上升，更明亮）
    local hl = pal.highlight
    local gl = pal.glow
    for i = 1, 15 do
        local baseSeed2 = i * 97.3 + 500
        local slowCycle = 3.5
        local phaseOff = ((i - 1) / 15) * slowCycle
        local lt = (time + phaseOff) % slowCycle
        local t = lt / slowCycle
        local cycle2 = math.floor((time + phaseOff) / slowCycle)
        local seed = baseSeed2 + cycle2 * 37.13

        local spawnX = math.sin(seed) * halfCell * 0.4
        local drift2 = math.sin(t * (2.0 + math.sin(seed * 0.6) * 1.5) + seed) * halfCell * (0.15 + t * 0.3)
        local px = cx + spawnX * (1 + t * 0.8) + drift2
        local riseSpeed2 = 1.0 + math.sin(seed * 0.8) * 0.2
        local py = cy + halfCell - t * riseHeight * 1.1 * riseSpeed2

        local alpha2
        if t < 0.15 then alpha2 = t / 0.15
        elseif t > 0.7 then alpha2 = 1 - (t - 0.7) / 0.3
        else alpha2 = 1.0
        end
        alpha2 = alpha2 * (0.8 + 0.2 * math.sin(time * 3 + seed))

        local bigSize = 1.2 + math.sin(seed * 0.3) * 0.3
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, bigSize)
        nvgFillColor(vg, nvgRGBA(hl[1], hl[2], hl[3], math.floor(alpha2 * 160)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, bigSize * 2.0)
        nvgFillColor(vg, nvgRGBA(gl[1], gl[2], gl[3], math.floor(alpha2 * 40)))
        nvgFill(vg)
    end

    -- ④ 顶部吟唱进度方块条（颜色跟随法术属性）
    local ch = GS.chanting
    if ch.stagesNeeded and ch.stagesAccum then
        local needed = ch.stagesNeeded
        local accum = ch.stagesAccum
        local blockSz = math.max(5, GS.CELL * 0.12)
        local blockGap = 2
        local totalW = needed * blockSz + (needed - 1) * blockGap
        local startX = cx - totalW / 2
        local blockY = cy - GS.CELL * 0.7 - blockSz / 2

        -- 属性对应的方块颜色
        local blockColors = {
            fire    = { fill = {255, 120, 40},  stroke = {255, 160, 80}  },
            ice     = { fill = {80, 170, 240},  stroke = {140, 200, 255} },
            thunder = { fill = {240, 210, 50},  stroke = {255, 235, 120} },
            holy    = { fill = {240, 210, 80},  stroke = {255, 235, 150} },
            arcane  = { fill = {160, 100, 220}, stroke = {180, 130, 240} },
        }
        local bc = blockColors[element] or blockColors.arcane

        for i = 1, needed do
            local bx = startX + (i - 1) * (blockSz + blockGap)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, blockY, blockSz, blockSz, 1.5)
            if i <= accum then
                nvgFillColor(vg, nvgRGBA(bc.fill[1], bc.fill[2], bc.fill[3], 230))
            else
                nvgFillColor(vg, nvgRGBA(30, 20, 40, 200))
            end
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(bc.stroke[1], bc.stroke[2], bc.stroke[3], 160))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
        end
    end

end

-- ====================================================================
-- 绘制：魔法盾激活/关闭特效（紫色护盾波纹扩散，与法师普攻同色系）
-- ====================================================================
function M.drawMagicShieldEffects()
    if #GS.magicShieldEffects == 0 then return end
    local vg = M.vg
    for _, e in ipairs(GS.magicShieldEffects) do
        local t = safeProgress(e.timer, e.duration)
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local halfCell = GS.CELL * 0.5

        if e.isActivate then
            -- 开启：从中心扩散的护盾球 + 六芒旋转符文
            local expandT = math.min(1, t / 0.5)
            local shieldR = halfCell * 0.3 + halfCell * 0.8 * expandT
            local fadeAlpha = t < 0.7 and 1.0 or (1 - (t - 0.7) / 0.3)

            -- 护盾球体（紫色渐变）
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, shieldR)
            local shieldGrad = nvgRadialGradient(vg, cx, cy, shieldR * 0.2, shieldR,
                nvgRGBA(120, 80, 200, math.floor(120 * fadeAlpha)),
                nvgRGBA(100, 60, 200, math.floor(40 * fadeAlpha)))
            nvgFillPaint(vg, shieldGrad)
            nvgFill(vg)

            -- 护盾边缘光环
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, shieldR)
            nvgStrokeColor(vg, nvgRGBA(160, 120, 240, math.floor(200 * fadeAlpha)))
            nvgStrokeWidth(vg, 2.0)
            nvgStroke(vg)

            -- 6条旋转符文弧线
            local time = GetTime():GetElapsedTime()
            local arcAngle = time * 3.0
            for a = 1, 6 do
                local aOff = (a - 1) * math.pi / 3 + arcAngle
                nvgBeginPath(vg)
                nvgArc(vg, cx, cy, shieldR * 0.7, aOff, aOff + math.pi * 0.25, 1)
                nvgStrokeColor(vg, nvgRGBA(180, 140, 255, math.floor(140 * fadeAlpha)))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end

            -- 20个紫色粒子向外扩散
            for i = 1, 20 do
                local seed = i * 137.5
                local angle = seed + t * 2
                local dist = shieldR * (0.5 + t * 0.6)
                local px = cx + math.cos(angle) * dist
                local py = cy + math.sin(angle) * dist
                local pAlpha = fadeAlpha * (0.6 + 0.4 * math.sin(seed * 0.9))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, 1.5 + math.sin(seed) * 0.5)
                nvgFillColor(vg, nvgRGBA(170, 130, 255, math.floor(pAlpha * 180)))
                nvgFill(vg)
            end
        else
            -- 关闭：护盾收缩碎裂
            local shrinkT = math.min(1, t / 0.4)
            local shieldR = halfCell * 1.0 * (1 - shrinkT * 0.8)
            local fadeAlpha = 1 - t

            -- 收缩的护盾
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, shieldR)
            nvgStrokeColor(vg, nvgRGBA(140, 100, 220, math.floor(150 * fadeAlpha)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 12个碎片向外飞散
            for i = 1, 12 do
                local seed = i * 137.5
                local angle = seed
                local dist = halfCell * 0.3 + t * halfCell * 1.2
                local px = cx + math.cos(angle) * dist
                local py = cy + math.sin(angle) * dist
                local fAlpha = fadeAlpha * (0.5 + 0.5 * math.sin(seed * 0.7))
                local fSize = (2.0 - t * 1.5)
                if fSize > 0.3 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, fSize)
                    nvgFillColor(vg, nvgRGBA(170, 130, 255, math.floor(fAlpha * 160)))
                    nvgFill(vg)
                end
            end
        end
    end
end

-- ====================================================================
-- 绘制：冰墙术创建特效（冰晶从地面升起 + 寒气扩散）
-- ====================================================================
function M.drawIceWallCreateEffects()
    if #GS.iceWallCreateEffects == 0 then return end
    local vg = M.vg
    for _, e in ipairs(GS.iceWallCreateEffects) do
        local t = safeProgress(e.timer, e.duration)

        for ci, c in ipairs(e.cells) do
            -- 每个冰墙格子有错开延迟
            local delay = (ci - 1) * 0.08
            local denom = e.duration - delay * #e.cells * 0.3
            local localT = denom > 0 and ((e.timer - delay) / denom) or 1
            if localT < 0 then localT = 0 end
            if localT > 1 then localT = 1 end

            local cx = GS.BOARD_X + (c.x - 0.5) * GS.CELL
            local cy = GS.BOARD_Y + (c.y - 0.5) * GS.CELL
            local halfCell = GS.CELL * 0.5

            -- 冰晶从地面升起的效果
            local riseT = math.min(1, localT / 0.5)
            local riseEase = 1 - (1 - riseT) * (1 - riseT)  -- easeOutQuad
            local fadeAlpha = localT < 0.6 and 1.0 or (1 - (localT - 0.6) / 0.4)

            -- 地面冰霜扩散圆
            local frostR = halfCell * 0.4 + halfCell * 0.6 * riseEase
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy + halfCell * 0.3, frostR)
            local frostGrad = nvgRadialGradient(vg, cx, cy + halfCell * 0.3, 0, frostR,
                nvgRGBA(100, 200, 255, math.floor(80 * fadeAlpha)),
                nvgRGBA(60, 160, 240, 0))
            nvgFillPaint(vg, frostGrad)
            nvgFill(vg)

            -- 3根冰锥从底部升起
            for spike = 1, 3 do
                local sAngle = (spike - 1) * 0.4 - 0.4 + math.sin(ci * 2.7) * 0.2
                local sHeight = halfCell * (0.6 + spike * 0.15) * riseEase
                local sWidth = halfCell * (0.12 + math.sin(ci + spike) * 0.04)
                local baseY = cy + halfCell * 0.3
                local sX = cx + sAngle * halfCell * 0.6

                -- 冰锥三角形
                nvgBeginPath(vg)
                nvgMoveTo(vg, sX - sWidth, baseY)
                nvgLineTo(vg, sX, baseY - sHeight)
                nvgLineTo(vg, sX + sWidth, baseY)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(140, 210, 255, math.floor(180 * fadeAlpha)))
                nvgFill(vg)

                -- 冰锥高光
                nvgBeginPath(vg)
                nvgMoveTo(vg, sX - sWidth * 0.3, baseY)
                nvgLineTo(vg, sX, baseY - sHeight * 0.9)
                nvgLineTo(vg, sX + sWidth * 0.1, baseY)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(200, 240, 255, math.floor(120 * fadeAlpha)))
                nvgFill(vg)
            end

            -- 8个寒气粒子向外飘散
            for i = 1, 8 do
                local seed = i * 137.5 + ci * 50
                local angle = seed + localT * 1.5
                local dist = halfCell * (0.3 + localT * 0.8)
                local px = cx + math.cos(angle) * dist
                local py = cy + math.sin(angle) * dist * 0.6 - localT * halfCell * 0.3
                local pAlpha = fadeAlpha * (0.5 + 0.5 * math.sin(seed * 0.8))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, 1.0 + math.sin(seed * 0.5) * 0.4)
                nvgFillColor(vg, nvgRGBA(160, 220, 255, math.floor(pAlpha * 150)))
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：闪烁传送特效（起点紫色消散 + 终点紫色凝聚，与法师普攻同色系）
-- ====================================================================
function M.drawBlinkEffects()
    if #GS.blinkEffects == 0 then return end
    local vg = M.vg
    for _, e in ipairs(GS.blinkEffects) do
        local t = safeProgress(e.timer, e.duration)
        local halfCell = GS.CELL * 0.5

        -- 起点坐标
        local fromCx = GS.BOARD_X + (e.fx - 0.5) * GS.CELL
        local fromCy = GS.BOARD_Y + (e.fy - 0.5) * GS.CELL
        -- 终点坐标
        local toCx = GS.BOARD_X + (e.tx - 0.5) * GS.CELL
        local toCy = GS.BOARD_Y + (e.ty - 0.5) * GS.CELL

        -- === 起点：紫色粒子向外消散 ===
        local fromAlpha = t < 0.5 and (1 - t * 2) or 0

        if fromAlpha > 0 then
            -- 残影轮廓（收缩淡出）
            local ghostR = halfCell * (0.8 - t * 0.6)
            nvgBeginPath(vg)
            nvgCircle(vg, fromCx, fromCy, ghostR)
            nvgFillColor(vg, nvgRGBA(120, 80, 200, math.floor(100 * fromAlpha)))
            nvgFill(vg)

            -- 30个粒子向四周爆散
            for i = 1, 30 do
                local seed = i * 137.5
                local angle = seed
                local speed = 0.8 + math.sin(seed * 0.3) * 0.4
                local dist = halfCell * t * 2.5 * speed
                local px = fromCx + math.cos(angle) * dist
                local py = fromCy + math.sin(angle) * dist
                local pSize = (1.5 - t * 2.0)
                if pSize > 0.2 then
                    local pAlpha = fromAlpha * (0.6 + 0.4 * math.sin(seed * 0.7))
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, pSize)
                    local ci = i % 3
                    if ci == 0 then
                        nvgFillColor(vg, nvgRGBA(140, 100, 220, math.floor(pAlpha * 200)))
                    elseif ci == 1 then
                        nvgFillColor(vg, nvgRGBA(100, 60, 200, math.floor(pAlpha * 200)))
                    else
                        nvgFillColor(vg, nvgRGBA(180, 140, 255, math.floor(pAlpha * 200)))
                    end
                    nvgFill(vg)
                end
            end
        end

        -- === 终点：粒子从外部汇聚凝实 ===
        local toStart = 0.25
        if t > toStart then
            local toT = (t - toStart) / (1 - toStart)
            local toAlpha = toT < 0.3 and (toT / 0.3) or (toT > 0.7 and (1 - (toT - 0.7) / 0.3) or 1.0)

            -- 汇聚粒子：从远到近
            for i = 1, 30 do
                local seed = i * 137.5 + 200
                local angle = seed
                local maxDist = halfCell * 2.0
                local dist = maxDist * (1 - toT)
                local px = toCx + math.cos(angle) * dist
                local py = toCy + math.sin(angle) * dist
                local pSize = 0.5 + toT * 1.2
                local pAlpha = toAlpha * (0.5 + 0.5 * math.sin(seed * 0.9))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, pSize)
                local ci = i % 3
                if ci == 0 then
                    nvgFillColor(vg, nvgRGBA(140, 100, 220, math.floor(pAlpha * 200)))
                elseif ci == 1 then
                    nvgFillColor(vg, nvgRGBA(100, 60, 200, math.floor(pAlpha * 200)))
                else
                    nvgFillColor(vg, nvgRGBA(180, 140, 255, math.floor(pAlpha * 200)))
                end
                nvgFill(vg)
            end

            -- 终点凝聚光环
            if toT > 0.4 then
                local ringT = (toT - 0.4) / 0.6
                local ringR = halfCell * (0.8 - ringT * 0.3)
                local ringAlpha = ringT < 0.5 and (ringT / 0.5) or (1 - (ringT - 0.5) / 0.5)
                nvgBeginPath(vg)
                nvgCircle(vg, toCx, toCy, ringR)
                nvgStrokeColor(vg, nvgRGBA(160, 120, 240, math.floor(ringAlpha * 180)))
                nvgStrokeWidth(vg, 2.0)
                nvgStroke(vg)

                -- 内部紫色光晕
                nvgBeginPath(vg)
                nvgCircle(vg, toCx, toCy, ringR * 0.6)
                local cGrad = nvgRadialGradient(vg, toCx, toCy, 0, ringR * 0.6,
                    nvgRGBA(140, 100, 220, math.floor(ringAlpha * 80)),
                    nvgRGBA(100, 60, 200, 0))
                nvgFillPaint(vg, cGrad)
                nvgFill(vg)
            end
        end

        -- === 起点到终点的能量连线 ===
        if t > 0.1 and t < 0.6 then
            local lineAlpha = t < 0.3 and ((t - 0.1) / 0.2) or ((0.6 - t) / 0.3)
            nvgBeginPath(vg)
            nvgMoveTo(vg, fromCx, fromCy)
            nvgLineTo(vg, toCx, toCy)
            nvgStrokeColor(vg, nvgRGBA(140, 100, 220, math.floor(lineAlpha * 100)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end
end


end -- sub.init

return sub
