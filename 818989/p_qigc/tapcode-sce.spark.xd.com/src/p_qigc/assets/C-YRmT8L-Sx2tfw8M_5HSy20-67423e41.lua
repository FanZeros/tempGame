-- ============================================================
-- Renderer_SkillEffects.lua  —— 技能攻击视觉特效
-- 由 Renderer.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================
local GS = require("GameState")
local Utils = require("Renderer_Utils")
local safeProgress = Utils.safeProgress

local sub = {}

function sub.init(M)

-- ====================================================================
-- 绘制：攻击特效
-- ====================================================================
function M.drawAttackEffects()
    local vg = M.vg
    for _, e in ipairs(GS.attackEffects) do
        -- 每个特效独立 save/restore，防止单个特效的 NanoVG 状态泄漏
        nvgSave(vg)
        local px = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local fpx = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fpy = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2

        local t = safeProgress(e.timer, e.duration)
        local r = GS.CELL * 0.6
        local dirAngle = math.atan(py - fpy, px - fpx)

        local isBowAtk = (e.weaponTag == "弓")
        local isStaffAtk = (e.weaponTag == "法杖")
        local isThrowAtk = (e.skillStyle == "throw")
        local isLittleZeusAtk = e.isLittleZeus

        if isThrowAtk then
            -- ============================================================
            -- 武器投掷：匕首旋转飞出 + 技能专属特效
            -- ============================================================
            local tid = e.throwSkillId or "a_weapon_throw"
            -- 技能配色方案
            local fxR, fxG, fxB  -- 主色
            if tid == "a_poison_throw" then
                fxR, fxG, fxB = 60, 220, 80       -- 绿色
            elseif tid == "a_armor_break" then
                fxR, fxG, fxB = 180, 80, 220      -- 紫色
            elseif tid == "a_notice" then
                fxR, fxG, fxB = 255, 60, 40       -- 红色
            else
                fxR, fxG, fxB = 100, 160, 255     -- 蓝色（武器投掷）
            end
            local hasTrail = true  -- 所有投掷技能都有拖尾
            local hasExplosion = (tid == "a_notice")
            local flyEnd = hasExplosion and 0.50 or 0.58
            local hitT = hasExplosion and 0.48 or 0.55

            -- 匕首飞行阶段
            if t < flyEnd then
                local flyT = math.min(t / hitT, 1.0)
                local ease = flyT * flyT
                local dx = fpx + (px - fpx) * ease
                local dy = fpy + (py - fpy) * ease
                local flyAlpha = flyT < 0.92 and 255 or math.floor(255 * (1 - (flyT - 0.92) / 0.08))
                local ddx = math.cos(dirAngle)
                local ddy = math.sin(dirAngle)

                -- 闪光光晕（所有投掷技能都有）
                local time = GetTime():GetElapsedTime()
                local flicker = 0.6 + 0.4 * math.sin(time * 24)
                local glowR = GS.CELL * (0.25 + 0.10 * flicker)
                local glowA = math.floor(220 * flicker * (flyAlpha / 255))
                local glow = nvgRadialGradient(vg, dx, dy, 0, glowR,
                    nvgRGBA(fxR, fxG, fxB, glowA),
                    nvgRGBA(fxR, fxG, fxB, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, dx, dy, glowR)
                nvgFillPaint(vg, glow)
                nvgFill(vg)

                -- 拖尾（长度按技能分级）
                if hasTrail and flyT > 0.05 then
                    local traveledDist = math.sqrt((dx - fpx)^2 + (dy - fpy)^2)
                    local trailMul = (tid == "a_notice") and 2.0
                        or (tid == "a_armor_break") and 1.4
                        or 1.0  -- 武器投掷/带毒投掷
                    local trailLen = math.min(GS.CELL * trailMul * math.min(1, flyT * 4), traveledDist)
                    local tx2 = dx - ddx * trailLen
                    local ty2 = dy - ddy * trailLen
                    local trailA = math.floor(160 * (flyAlpha / 255))
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, dx, dy)
                    nvgLineTo(vg, tx2, ty2)
                    nvgStrokeColor(vg, nvgRGBA(fxR, fxG, fxB, trailA))
                    nvgStrokeWidth(vg, math.max(2.5, GS.CELL * 0.05))
                    nvgStroke(vg)
                    -- 亮芯
                    local tx3 = dx - ddx * trailLen * 0.6
                    local ty3 = dy - ddy * trailLen * 0.6
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, dx, dy)
                    nvgLineTo(vg, tx3, ty3)
                    local coreR2 = math.min(255, fxR + 60)
                    local coreG2 = math.min(255, fxG + 60)
                    local coreB2 = math.min(255, fxB + 60)
                    nvgStrokeColor(vg, nvgRGBA(coreR2, coreG2, coreB2, math.floor(trailA * 0.6)))
                    nvgStrokeWidth(vg, math.max(1.2, GS.CELL * 0.025))
                    nvgStroke(vg)
                end

                -- 匕首本体（旋转飞行）
                if M.daggerImage ~= -1 then
                    local dSize = GS.CELL * 0.5
                    local spinAngle = dirAngle + flyT * math.pi * 6
                    local imgBaseAngle = math.rad(135)
                    nvgSave(vg)
                    nvgTranslate(vg, dx, dy)
                    nvgRotate(vg, spinAngle - imgBaseAngle)
                    nvgGlobalAlpha(vg, flyAlpha / 255)
                    local dPaint = nvgImagePattern(vg,
                        -dSize / 2, -dSize / 2, dSize, dSize,
                        0, M.daggerImage, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, -dSize / 2, -dSize / 2, dSize, dSize)
                    nvgFillPaint(vg, dPaint)
                    nvgFill(vg)
                    nvgGlobalAlpha(vg, 1.0)
                    nvgRestore(vg)
                else
                    local bLen = GS.CELL * 0.25
                    local spinAngle = dirAngle + flyT * math.pi * 6
                    nvgSave(vg)
                    nvgTranslate(vg, dx, dy)
                    nvgRotate(vg, spinAngle)
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, bLen, 0)
                    nvgLineTo(vg, -bLen * 0.4, -bLen * 0.35)
                    nvgLineTo(vg, -bLen * 0.4, bLen * 0.35)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(220, 210, 220, flyAlpha))
                    nvgFill(vg)
                    nvgRestore(vg)
                end
            end

            -- 预告信爆炸效果 (t 0.48~1.0)
            if hasExplosion and t >= 0.48 then
                local ht = (t - 0.48) / 0.52
                -- 第一层冲击波（红色）
                local impactR1 = GS.CELL * (0.15 + 0.6 * ht)
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, impactR1)
                nvgStrokeColor(vg, nvgRGBA(255, 60, 40, math.floor(240 * (1 - ht))))
                nvgStrokeWidth(vg, 3.5 * (1 - ht * 0.5))
                nvgStroke(vg)
                -- 第二层冲击波（橙色，延迟）
                if ht > 0.12 then
                    local ht2 = (ht - 0.12) / 0.88
                    local impactR2 = GS.CELL * (0.10 + 0.5 * ht2)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, impactR2)
                    nvgStrokeColor(vg, nvgRGBA(255, 140, 40, math.floor(180 * (1 - ht2))))
                    nvgStrokeWidth(vg, 2.5 * (1 - ht2 * 0.5))
                    nvgStroke(vg)
                end
                -- 中心闪光
                if ht < 0.3 then
                    local flashT = ht / 0.3
                    local flashR = GS.CELL * (0.05 + 0.2 * flashT)
                    local flashA = math.floor(255 * (1 - flashT))
                    local flashGlow = nvgRadialGradient(vg, px, py, 0, flashR,
                        nvgRGBA(255, 220, 180, flashA),
                        nvgRGBA(255, 100, 40, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, flashR)
                    nvgFillPaint(vg, flashGlow)
                    nvgFill(vg)
                end
                -- 碎片飞散
                for i = 1, 8 do
                    local angle = (i / 8) * math.pi * 2 + dirAngle
                    local fd = GS.CELL * 0.6 * ht * ht
                    local fragAlpha = math.floor(220 * (1 - ht))
                    local fragSize = 2.2 * (1 - ht * 0.6)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + math.cos(angle) * fd, py + math.sin(angle) * fd, fragSize)
                    nvgFillColor(vg, nvgRGBA(255, 80 + i * 10, 30, fragAlpha))
                    nvgFill(vg)
                end
            end

        elseif isLittleZeusAtk then
            -- ============================================================
            -- 小宙斯雷锤弹道：锤子飞向目标 + 雷电粒子环绕
            -- ============================================================
            local hammerImg = M.maceImage
            local flyEnd = 0.55
            local hitT = 0.50
            if t < flyEnd then
                local flyT = math.min(t / hitT, 1.0)
                local ease = flyT * flyT * (3 - 2 * flyT)
                local hx = fpx + (px - fpx) * ease
                local hy = fpy + (py - fpy) * ease
                local hammerAlpha = flyT < 0.88 and 255 or math.floor(255 * (1 - (flyT - 0.88) / 0.12))
                local time = GetTime():GetElapsedTime()

                -- 锤子旋转飞行
                local hammerSize = GS.CELL * 0.7
                local spinAngle = dirAngle + t * 18  -- 持续旋转
                if hammerImg and hammerImg ~= -1 then
                    nvgSave(vg)
                    nvgTranslate(vg, hx, hy)
                    nvgRotate(vg, spinAngle)
                    nvgGlobalAlpha(vg, hammerAlpha / 255)
                    local hPaint = nvgImagePattern(vg,
                        -hammerSize / 2, -hammerSize / 2,
                        hammerSize, hammerSize,
                        0, hammerImg, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, -hammerSize / 2, -hammerSize / 2, hammerSize, hammerSize)
                    nvgFillPaint(vg, hPaint)
                    nvgFill(vg)
                    nvgGlobalAlpha(vg, 1.0)
                    nvgRestore(vg)
                else
                    -- 无图片回退：程序化绘制锤头
                    nvgSave(vg)
                    nvgTranslate(vg, hx, hy)
                    nvgRotate(vg, spinAngle)
                    local hs = GS.CELL * 0.15
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, -hs * 1.2, -hs * 1.8, hs * 2.4, hs * 1.6, hs * 0.3)
                    nvgFillColor(vg, nvgRGBA(160, 160, 180, hammerAlpha))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRect(vg, -hs * 0.2, -hs * 0.2, hs * 0.4, hs * 2.2)
                    nvgFillColor(vg, nvgRGBA(120, 80, 40, hammerAlpha))
                    nvgFill(vg)
                    nvgRestore(vg)
                end

                -- 雷电粒子环绕弹道
                local ddx = math.cos(dirAngle)
                local ddy = math.sin(dirAngle)
                local nnx = -ddy
                local nny = ddx
                for i = 1, 8 do
                    local seed = i * 137.5
                    local angle = seed + time * 12 + flyT * 20
                    local orbitR = GS.CELL * (0.18 + 0.08 * math.sin(seed + time * 8))
                    local lpx = hx + math.cos(angle) * orbitR
                    local lpy = hy + math.sin(angle) * orbitR
                    local sparkSize = math.max(1.0, GS.CELL * 0.04 * (0.5 + 0.5 * math.sin(seed + time * 15)))
                    local lAlpha = math.floor((180 + 75 * math.sin(seed + time * 20)) * (hammerAlpha / 255))
                    nvgBeginPath(vg)
                    nvgCircle(vg, lpx, lpy, sparkSize)
                    nvgFillColor(vg, nvgRGBA(120, 180, 255, lAlpha))
                    nvgFill(vg)
                end

                -- 电弧闪烁（随机小闪电线段）
                for i = 1, 3 do
                    local seed = i * 97.3
                    local flicker = math.sin(time * 25 + seed)
                    if flicker > 0.2 then
                        local aLen = GS.CELL * (0.12 + 0.08 * math.sin(seed + time * 13))
                        local aAngle = seed + time * 7
                        local ax1 = hx + math.cos(aAngle) * GS.CELL * 0.06
                        local ay1 = hy + math.sin(aAngle) * GS.CELL * 0.06
                        local ax2 = ax1 + math.cos(aAngle + 0.8) * aLen
                        local ay2 = ay1 + math.sin(aAngle + 0.8) * aLen
                        local aMid = 0.5 + 0.3 * math.sin(seed + time * 30)
                        local mx = (ax1 + ax2) / 2 + math.sin(time * 40 + seed) * GS.CELL * 0.04
                        local my = (ay1 + ay2) / 2 + math.cos(time * 35 + seed) * GS.CELL * 0.04
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, ax1, ay1)
                        nvgLineTo(vg, mx, my)
                        nvgLineTo(vg, ax2, ay2)
                        nvgStrokeColor(vg, nvgRGBA(160, 200, 255, math.floor(200 * flicker * (hammerAlpha / 255))))
                        nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.015))
                        nvgStroke(vg)
                    end
                end

                -- 锤头闪烁光晕
                local glowFlicker = 0.6 + 0.4 * math.sin(time * 20)
                local glowR = GS.CELL * (0.2 + 0.06 * glowFlicker)
                local glowA = math.floor(180 * glowFlicker * (hammerAlpha / 255))
                local glow = nvgRadialGradient(vg, hx, hy, 0, glowR,
                    nvgRGBA(100, 160, 255, glowA),
                    nvgRGBA(80, 120, 255, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, hx, hy, glowR)
                nvgFillPaint(vg, glow)
                nvgFill(vg)
            end

            -- 命中雷电爆炸效果
            if t >= 0.45 and t < 0.85 then
                local expT = (t - 0.45) / 0.40
                local expAlpha = math.floor(255 * (1 - expT))
                -- 雷电扩散环
                local ringR = GS.CELL * (0.2 + 0.6 * expT)
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, ringR)
                nvgStrokeColor(vg, nvgRGBA(120, 180, 255, expAlpha))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.06 * (1 - expT * 0.5)))
                nvgStroke(vg)
                -- 内圈闪光
                local innerR = GS.CELL * 0.15 * (1 - expT * 0.5)
                local innerGlow = nvgRadialGradient(vg, px, py, 0, innerR,
                    nvgRGBA(200, 230, 255, math.floor(expAlpha * 0.8)),
                    nvgRGBA(100, 160, 255, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, innerR)
                nvgFillPaint(vg, innerGlow)
                nvgFill(vg)
                -- 爆炸电火花
                local time = GetTime():GetElapsedTime()
                for i = 1, 6 do
                    local seed = i * 60
                    local sparkAngle = math.rad(seed) + expT * 3
                    local sparkDist = ringR * (0.5 + 0.5 * math.sin(seed + time * 15))
                    local sx = px + math.cos(sparkAngle) * sparkDist
                    local sy = py + math.sin(sparkAngle) * sparkDist
                    local sSize = math.max(1, GS.CELL * 0.03 * (1 - expT))
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, sSize)
                    nvgFillColor(vg, nvgRGBA(180, 220, 255, math.floor(expAlpha * 0.7)))
                    nvgFill(vg)
                end
            end

        elseif isBowAtk and M.bowImage ~= -1 then
            -- ============================================================
            -- 弓攻击：拉弓 + 箭矢飞行
            -- ============================================================

            -- 弓始终显示在攻击者位置，朝向目标
            do
                local bowSize = GS.CELL * 0.75
                local bowRot = dirAngle + math.rad(135)
                local bowAlpha = t < 0.05 and (t / 0.05) or (t > 0.85 and (1 - (t - 0.85) / 0.15) or 1.0)
                -- 拉弦阶段：t 0~0.18 弓身微压缩，发射后恢复
                local pullT = t < 0.18 and (t / 0.18) or 1.0
                local scaleX = t < 0.2 and (1.0 - pullT * 0.15) or 1.0

                nvgSave(vg)
                nvgTranslate(vg, fpx, fpy)
                nvgRotate(vg, bowRot)
                nvgScale(vg, scaleX, 1.0)

                local bowPaint = nvgImagePattern(vg,
                    -bowSize / 2, -bowSize / 2,
                    bowSize, bowSize,
                    0, M.bowImage, bowAlpha)
                nvgBeginPath(vg)
                nvgRect(vg, -bowSize / 2, -bowSize / 2, bowSize, bowSize)
                nvgFillPaint(vg, bowPaint)
                nvgFill(vg)

                -- 弦拉回效果（拉弓阶段显示）
                if t < 0.2 and pullT > 0.3 then
                    local stringPull = (pullT - 0.3) / 0.7 * bowSize * 0.2
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, 0, -bowSize * 0.3)
                    nvgLineTo(vg, -stringPull, 0)
                    nvgLineTo(vg, 0, bowSize * 0.3)
                    nvgStrokeColor(vg, nvgRGBA(200, 180, 140, math.floor(200 * bowAlpha)))
                    nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.02))
                    nvgStroke(vg)
                end

                nvgRestore(vg)
            end

            -- 阶段2：箭矢飞行 (t 0.15~0.55)
            if t >= 0.15 and t < 0.55 then
                local arrowT = (t - 0.15) / 0.40
                local ease = arrowT * arrowT * (3 - 2 * arrowT)
                local ax = fpx + (px - fpx) * ease
                local ay = fpy + (py - fpy) * ease
                local traveledDist = math.sqrt((ax - fpx)^2 + (ay - fpy)^2)
                local arrowAlpha = arrowT < 0.8 and 255 or math.floor(255 * (1 - (arrowT - 0.8) / 0.2))

                if M.arrowImage ~= -1 then
                    -- 使用箭矢图片渲染
                    local arrowSize = GS.CELL * 0.55
                    -- 原图箭头朝左下（约-135度），需要修正到 dirAngle 方向
                    local imgBaseAngle = math.rad(135)
                    local arrowRot = dirAngle - imgBaseAngle

                    nvgSave(vg)
                    nvgTranslate(vg, ax, ay)
                    nvgRotate(vg, arrowRot)
                    nvgGlobalAlpha(vg, arrowAlpha / 255)

                    local aPaint = nvgImagePattern(vg,
                        -arrowSize * 0.5, -arrowSize * 0.5,
                        arrowSize, arrowSize, 0, M.arrowImage, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, -arrowSize * 0.5, -arrowSize * 0.5, arrowSize, arrowSize)
                    nvgFillPaint(vg, aPaint)
                    nvgFill(vg)

                    nvgGlobalAlpha(vg, 1.0)
                    nvgRestore(vg)
                else
                    -- 无图片时的回退：程序化绘制箭矢
                    local arrowLen = GS.CELL * 0.35
                    local arrowW = math.max(2, GS.CELL * 0.04)
                    nvgSave(vg)
                    nvgTranslate(vg, ax, ay)
                    nvgRotate(vg, dirAngle)
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, -arrowLen, 0)
                    nvgLineTo(vg, arrowLen * 0.3, 0)
                    nvgStrokeColor(vg, nvgRGBA(160, 120, 60, arrowAlpha))
                    nvgStrokeWidth(vg, arrowW)
                    nvgStroke(vg)
                    local headLen = arrowLen * 0.35
                    local headW = arrowW * 2.5
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, arrowLen * 0.3 + headLen, 0)
                    nvgLineTo(vg, arrowLen * 0.3, -headW)
                    nvgLineTo(vg, arrowLen * 0.3, headW)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(180, 180, 190, arrowAlpha))
                    nvgFill(vg)
                    nvgRestore(vg)
                end

                -- 箭矢拖尾光迹
                if arrowT > 0.1 then
                    local trailAlpha = math.floor(120 * (1 - arrowT))
                    local trailBase = (e.skillStyle == "snipe") and (GS.CELL * 4.5)
                        or (e.skillStyle == "stun_shot") and (GS.CELL * 1.5)
                        or (GS.CELL * 0.5)
                    local trailLen = math.min(trailBase * math.min(1, arrowT * 3), traveledDist)
                    local tx2 = ax - math.cos(dirAngle) * trailLen
                    local ty2 = ay - math.sin(dirAngle) * trailLen
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, ax, ay)
                    nvgLineTo(vg, tx2, ty2)
                    -- 技能箭矢：拖尾颜色强化
                    if e.skillStyle == "snipe" then
                        nvgStrokeColor(vg, nvgRGBA(80, 255, 120, math.floor(trailAlpha * 1.5)))
                        nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.06))
                    elseif e.skillStyle == "power_shot" then
                        nvgStrokeColor(vg, nvgRGBA(100, 240, 80, math.floor(trailAlpha * 1.3)))
                        nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.05))
                    elseif e.skillStyle == "stun_shot" then
                        nvgStrokeColor(vg, nvgRGBA(255, 200, 60, math.floor(trailAlpha * 1.3)))
                        nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.05))
                    else
                        nvgStrokeColor(vg, nvgRGBA(255, 220, 140, trailAlpha))
                        nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.03))
                    end
                    nvgStroke(vg)
                end

                -- 技能增强粒子：附着在箭矢周围
                if e.skillStyle and arrowT > 0.05 then
                    local ddx = math.cos(dirAngle)
                    local ddy = math.sin(dirAngle)
                    local nnx = -ddy
                    local nny = ddx

                    if e.skillStyle == "snipe" then
                        -- 狙击：密集绿色粒子拖尾 + 能量外壳
                        local time = GetTime():GetElapsedTime()
                        for i = 1, 24 do
                            local seed = i * 137.5
                            local tailOff = math.min((i - 1) / 24 * GS.CELL * 5.4, traveledDist)
                            local sideOff = math.sin(seed + arrowT * 15) * GS.CELL * 0.1
                            local ppx = ax - ddx * tailOff + nnx * sideOff
                            local ppy = ay - ddy * tailOff + nny * sideOff
                            local fade = 1 - (i - 1) / 24
                            local pAlpha = math.floor(220 * fade)
                            local pSize = 2.2 * (0.3 + fade * 0.7)
                            nvgBeginPath(vg)
                            nvgCircle(vg, ppx, ppy, pSize)
                            nvgFillColor(vg, nvgRGBA(100, 255, 140, pAlpha))
                            nvgFill(vg)
                        end
                        -- 弹头强烈闪烁绿色光芒
                        local flicker = 0.6 + 0.4 * math.sin(time * 25)
                        local flicker2 = 0.5 + 0.5 * math.sin(time * 37 + 1.7)
                        local glowAlpha = math.floor(240 * flicker)
                        local glowR = GS.CELL * (0.2 + 0.08 * flicker2)
                        local headGlow = nvgRadialGradient(vg, ax, ay, 0, glowR,
                            nvgRGBA(180, 255, 200, glowAlpha), nvgRGBA(80, 255, 120, 0))
                        nvgBeginPath(vg)
                        nvgCircle(vg, ax, ay, glowR)
                        nvgFillPaint(vg, headGlow)
                        nvgFill(vg)
                        -- 内核亮点
                        local coreAlpha = math.floor(255 * flicker2)
                        local coreR = GS.CELL * 0.06 * (0.8 + 0.2 * flicker)
                        nvgBeginPath(vg)
                        nvgCircle(vg, ax, ay, coreR)
                        nvgFillColor(vg, nvgRGBA(220, 255, 230, coreAlpha))
                        nvgFill(vg)
                    elseif e.skillStyle == "power_shot" then
                        -- 劲射：风元素螺旋粒子
                        for i = 1, 10 do
                            local seed = i * 137.5
                            local tailOff = (i - 1) / 10 * GS.CELL * 0.5
                            local spiralAngle = seed + arrowT * 20
                            local spiralR = GS.CELL * 0.06 * (1 - (i - 1) / 12)
                            local ppx = ax - ddx * tailOff + math.cos(spiralAngle) * spiralR
                            local ppy = ay - ddy * tailOff + math.sin(spiralAngle) * spiralR
                            local pAlpha = math.floor(180 * (1 - (i - 1) / 10))
                            nvgBeginPath(vg)
                            nvgCircle(vg, ppx, ppy, 1.5)
                            nvgFillColor(vg, nvgRGBA(120, 240, 100, pAlpha))
                            nvgFill(vg)
                        end
                    elseif e.skillStyle == "stun_shot" then
                        -- 晕眩射击：黄色粒子拖尾 + 弹头闪烁
                        local time = GetTime():GetElapsedTime()
                        for i = 1, 12 do
                            local seed = i * 137.5
                            local tailOff = math.min((i - 1) / 12 * GS.CELL * 1.8, traveledDist)
                            local sideOff = math.sin(seed + arrowT * 20) * GS.CELL * 0.08
                            local ppx = ax - ddx * tailOff + nnx * sideOff
                            local ppy = ay - ddy * tailOff + nny * sideOff
                            local fade = 1 - (i - 1) / 12
                            local pAlpha = math.floor(210 * fade)
                            local pSize = 1.8 * (0.3 + fade * 0.7)
                            nvgBeginPath(vg)
                            nvgCircle(vg, ppx, ppy, pSize)
                            nvgFillColor(vg, nvgRGBA(255, 220, 60, pAlpha))
                            nvgFill(vg)
                        end
                        -- 弹头闪烁黄色光芒
                        local flicker = 0.6 + 0.4 * math.sin(time * 22)
                        local flicker2 = 0.5 + 0.5 * math.sin(time * 31 + 1.3)
                        local glowAlpha = math.floor(220 * flicker)
                        local glowR = GS.CELL * (0.14 + 0.05 * flicker2)
                        local headGlow = nvgRadialGradient(vg, ax, ay, 0, glowR,
                            nvgRGBA(255, 230, 100, glowAlpha), nvgRGBA(255, 200, 60, 0))
                        nvgBeginPath(vg)
                        nvgCircle(vg, ax, ay, glowR)
                        nvgFillPaint(vg, headGlow)
                        nvgFill(vg)
                        -- 内核亮点
                        local coreAlpha = math.floor(240 * flicker2)
                        local coreR = GS.CELL * 0.04 * (0.8 + 0.2 * flicker)
                        nvgBeginPath(vg)
                        nvgCircle(vg, ax, ay, coreR)
                        nvgFillColor(vg, nvgRGBA(255, 255, 200, coreAlpha))
                        nvgFill(vg)
                    end
                end
            end

            -- 技能命中冲击效果
            if e.skillStyle and t >= 0.55 then
                local ht = (t - 0.55) / 0.45
                if e.skillStyle == "snipe" then
                    -- 狙击：绿色冲击波 + 碎片
                    local impactR = GS.CELL * (0.15 + 0.55 * ht)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, impactR)
                    nvgStrokeColor(vg, nvgRGBA(100, 255, 130, math.floor(220 * (1 - ht))))
                    nvgStrokeWidth(vg, 3.0 * (1 - ht * 0.6))
                    nvgStroke(vg)
                    for i = 1, 8 do
                        local angle = (i / 8) * math.pi * 2 + dirAngle
                        local fd = GS.CELL * 0.6 * ht * ht
                        local fragAlpha = math.floor(180 * (1 - ht))
                        nvgBeginPath(vg)
                        nvgCircle(vg, px + math.cos(angle) * fd, py + math.sin(angle) * fd, 2.0 * (1 - ht * 0.5))
                        nvgFillColor(vg, nvgRGBA(120, 255, 140, fragAlpha))
                        nvgFill(vg)
                    end
                elseif e.skillStyle == "power_shot" then
                    -- 劲射：绿色风压冲击
                    local impactR = GS.CELL * (0.1 + 0.45 * ht)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, impactR)
                    nvgStrokeColor(vg, nvgRGBA(80, 230, 80, math.floor(200 * (1 - ht))))
                    nvgStrokeWidth(vg, 2.5 * (1 - ht * 0.5))
                    nvgStroke(vg)
                elseif e.skillStyle == "stun_shot" then
                    -- 晕眩射击：黄色眩晕星
                    local starAlpha = math.floor(200 * (1 - ht))
                    for i = 1, 5 do
                        local angle = (i / 5) * math.pi * 2 + ht * 3
                        local sd = GS.CELL * 0.25 * (0.5 + ht * 0.5)
                        nvgBeginPath(vg)
                        nvgCircle(vg, px + math.cos(angle) * sd, py + math.sin(angle) * sd, 2.0 * (1 - ht * 0.3))
                        nvgFillColor(vg, nvgRGBA(255, 220, 60, starAlpha))
                        nvgFill(vg)
                    end
                end
            end

        elseif e.weaponTag == "拳" then

        -- ============================================================
        -- 赤手空拳：拳头冲刺 + 冲击波纹
        -- ============================================================

        -- 拳头冲刺（从攻击者飞向目标）
        if t < 0.45 then
            local fistSize = GS.CELL * 0.4

            -- 拳头位置：沿方向从攻击者到目标
            local moveT
            if t < 0.12 then
                -- 蓄力阶段：微微后拉
                moveT = -0.08 * (t / 0.12)
            elseif t < 0.28 then
                -- 冲刺阶段：快速前冲
                local st = (t - 0.12) / 0.16
                local ease = st * st * (3 - 2 * st)
                moveT = -0.08 + 1.08 * ease
            else
                -- 收回阶段
                local st = (t - 0.28) / 0.17
                moveT = 1.0
                fistSize = fistSize * (1 - st * 0.3)
            end

            local fistX = fpx + (px - fpx) * math.max(0, moveT)
            local fistY = fpy + (py - fpy) * math.max(0, moveT)
            local fistAlpha = t < 0.05 and (t / 0.05) or (t > 0.35 and math.max(0, 1 - (t - 0.35) / 0.1) or 1.0)

            -- 速度线（冲刺阶段）
            if t >= 0.12 and t < 0.30 then
                local lineAlpha = math.floor(180 * (1 - (t - 0.12) / 0.18))
                local lineCount = 4
                for li = 1, lineCount do
                    local offset = (li - 2.5) * fistSize * 0.35
                    local perpX = -math.sin(dirAngle) * offset
                    local perpY = math.cos(dirAngle) * offset
                    local tailLen = GS.CELL * 0.5
                    local lx1 = fistX + perpX
                    local ly1 = fistY + perpY
                    local lx2 = lx1 - math.cos(dirAngle) * tailLen
                    local ly2 = ly1 - math.sin(dirAngle) * tailLen
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, lx1, ly1)
                    nvgLineTo(vg, lx2, ly2)
                    nvgStrokeColor(vg, nvgRGBA(255, 240, 200, lineAlpha))
                    nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.025))
                    nvgStroke(vg)
                end
            end

            -- 拳头本体（圆形 + 高光）
            nvgSave(vg)
            nvgTranslate(vg, fistX, fistY)

            -- 拳头阴影
            nvgBeginPath(vg)
            nvgCircle(vg, fistSize * 0.05, fistSize * 0.05, fistSize * 0.5)
            nvgFillColor(vg, nvgRGBA(60, 30, 10, math.floor(120 * fistAlpha)))
            nvgFill(vg)

            -- 拳头主体（肤色渐变）
            local fistGrad = nvgRadialGradient(vg, -fistSize * 0.1, -fistSize * 0.1,
                fistSize * 0.1, fistSize * 0.45,
                nvgRGBA(255, 220, 180, math.floor(255 * fistAlpha)),
                nvgRGBA(220, 170, 120, math.floor(255 * fistAlpha)))
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, fistSize * 0.45)
            nvgFillPaint(vg, fistGrad)
            nvgFill(vg)

            -- 拳头轮廓
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, fistSize * 0.45)
            nvgStrokeColor(vg, nvgRGBA(180, 130, 80, math.floor(200 * fistAlpha)))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.03))
            nvgStroke(vg)

            -- 指节高光
            local knuckleCount = 3
            for ki = 1, knuckleCount do
                local kAngle = dirAngle + (ki - 2) * 0.4
                local kx = math.cos(kAngle) * fistSize * 0.25
                local ky = math.sin(kAngle) * fistSize * 0.25
                nvgBeginPath(vg)
                nvgCircle(vg, kx, ky, fistSize * 0.1)
                nvgFillColor(vg, nvgRGBA(255, 235, 200, math.floor(180 * fistAlpha)))
                nvgFill(vg)
            end

            nvgRestore(vg)
        end

        -- 拳击冲击环（命中时扩散）
        if t >= 0.22 and t < 0.50 then
            local rt = (t - 0.22) / 0.28
            local ringR = r * 0.2 + r * 0.6 * rt
            local ringAlpha = math.floor(200 * (1 - rt))

            -- 双环
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, ringR)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 100, ringAlpha))
            nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.07 * (1 - rt * 0.6)))
            nvgStroke(vg)

            nvgBeginPath(vg)
            nvgCircle(vg, px, py, ringR * 0.6)
            nvgStrokeColor(vg, nvgRGBA(255, 240, 180, math.floor(ringAlpha * 0.6)))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.05 * (1 - rt * 0.5)))
            nvgStroke(vg)
        end

        -- 星形碎片（拳击命中飞溅）
        if t >= 0.24 and t < 0.55 then
            local st = (t - 0.24) / 0.31
            local starAlpha = math.floor(220 * (1 - st))
            local starCount = 5
            for si = 1, starCount do
                local sAngle = (si / starCount) * math.pi * 2 + dirAngle + 0.3
                local sDist = r * 0.15 + r * 0.7 * st
                local sx = px + math.cos(sAngle) * sDist
                local sy = py + math.sin(sAngle) * sDist
                local starSize = math.max(2, GS.CELL * 0.06 * (1 - st * 0.5))

                -- 四角星
                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgRotate(vg, sAngle + st * 2)
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -starSize)
                nvgLineTo(vg, starSize * 0.3, 0)
                nvgLineTo(vg, 0, starSize)
                nvgLineTo(vg, -starSize * 0.3, 0)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 230, 150, starAlpha))
                nvgFill(vg)
                nvgRestore(vg)
            end
        end

        elseif e.weaponTag == "剑匕双持" then

        -- ============================================================
        -- 剑匕双持：先剑挥砍，再匕首突刺
        -- ============================================================

        -- 第一击：剑挥砍（t: 0~0.45）复用默认剑斩逻辑
        if M.swordImage ~= -1 and t < 0.45 then
            local swordSize = GS.CELL * 0.85
            local hiltOffX = swordSize * 0.35
            local hiltOffY = swordSize * 0.35
            local orbitR = GS.CELL * 0.15
            local restAngle = math.rad(-55)
            local swingStart = dirAngle - math.rad(70)
            local swingEnd   = dirAngle + math.rad(60)

            local curAngle, swordAlpha

            if t < 0.08 then
                local st = t / 0.08
                curAngle = restAngle + (swingStart - restAngle) * (st * st)
                swordAlpha = 0.7 + 0.3 * st
            elseif t < 0.26 then
                local st = (t - 0.08) / 0.18
                local ease = st * st * (3 - 2 * st)
                curAngle = swingStart + (swingEnd - swingStart) * ease
                swordAlpha = 1.0
            else
                local st = (t - 0.26) / 0.19
                curAngle = swingEnd
                swordAlpha = 1.0 - st * st
            end

            local hiltX = fpx + math.cos(curAngle) * orbitR
            local hiltY = fpy + math.sin(curAngle) * orbitR
            local swordRot = curAngle + math.rad(135)

            -- 残影
            if t >= 0.08 and t < 0.32 then
                local st = math.min(1.0, (t - 0.08) / 0.18)
                for gi = 3, 1, -1 do
                    local delay = gi * 0.04
                    local gt = math.max(0, st - delay / 0.18)
                    if gt > 0 then
                        local gEase = gt * gt * (3 - 2 * gt)
                        local gAngle = swingStart + (swingEnd - swingStart) * gEase
                        local gx = fpx + math.cos(gAngle) * orbitR
                        local gy = fpy + math.sin(gAngle) * orbitR
                        local gRot = gAngle + math.rad(135)
                        local gAlpha = (0.18 - gi * 0.04)
                        nvgSave(vg)
                        nvgTranslate(vg, gx, gy)
                        nvgRotate(vg, gRot)
                        local ghostPaint = nvgImagePattern(vg,
                            -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                            swordSize, swordSize, 0, M.swordImage, math.max(0.02, gAlpha))
                        nvgBeginPath(vg)
                        nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                        nvgFillPaint(vg, ghostPaint)
                        nvgFill(vg)
                        nvgRestore(vg)
                    end
                end
            end

            -- 剑本体
            nvgSave(vg)
            nvgTranslate(vg, hiltX, hiltY)
            nvgRotate(vg, swordRot)
            local imgPaint = nvgImagePattern(vg,
                -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                swordSize, swordSize, 0, M.swordImage, swordAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
            nvgRestore(vg)

            -- 剑弧光
            if t >= 0.12 and t < 0.34 then
                local st = (t - 0.12) / 0.22
                local alpha = math.floor(200 * (1 - st))
                local arcR = GS.CELL * 0.5
                local trailEase = math.min(1, st * 1.3)
                local trailEnd = swingStart + (swingEnd - swingStart) * trailEase
                local trailStart = swingStart + (swingEnd - swingStart) * math.max(0, trailEase - 0.4)
                nvgSave(vg)
                nvgTranslate(vg, fpx, fpy)
                nvgBeginPath(vg)
                nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, NVG_CW)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, alpha))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.06 * (1 - st * 0.6)))
                nvgStroke(vg)
                nvgRestore(vg)
            end
        end

        -- 第二击：匕首突刺（t: 0.22~0.58），复用双匕首第二刀的时序
        if M.daggerImage ~= -1 and t >= 0.22 and t < 0.58 then
            local lt = t - 0.22
            local dSize = GS.CELL * 0.55
            local offsetDist = GS.CELL * 0.4
            local dpx = px - math.cos(dirAngle) * offsetDist
            local dpy = py - math.sin(dirAngle) * offsetDist
            local rotAngle = dirAngle + math.rad(270)
            local orbitR = GS.CELL * 0.2

            -- 从反方向挥入（镜像方向：dirAngle+100° → dirAngle-40°）
            local slashT
            if lt < 0.06 then
                slashT = 0
            elseif lt < 0.22 then
                local st = (lt - 0.06) / 0.16
                slashT = st * st * (3 - 2 * st)
            else
                slashT = 1.0
            end

            local swingStart = dirAngle + math.rad(100)
            local swingEnd   = dirAngle - math.rad(40)
            local curAngle = swingStart + (swingEnd - swingStart) * slashT
            local dAlpha = lt < 0.03 and (lt / 0.03) or (lt > 0.26 and math.max(0, 1 - (lt - 0.26) / 0.10) or 1.0)

            nvgSave(vg)
            nvgTranslate(vg, dpx + math.cos(curAngle) * orbitR, dpy + math.sin(curAngle) * orbitR)
            nvgRotate(vg, rotAngle)
            nvgScale(vg, -1, 1)  -- 镜像
            local imgPaint = nvgImagePattern(vg, -dSize / 2, -dSize / 2, dSize, dSize, 0, M.daggerImage, dAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -dSize / 2, -dSize / 2, dSize, dSize)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
            nvgRestore(vg)

            -- 匕首弧光（逆时针）
            if lt >= 0.08 and lt < 0.28 then
                local arcT = (lt - 0.08) / 0.20
                local arcAlpha = math.floor(180 * (1 - arcT))
                local arcStart = swingStart + (swingEnd - swingStart) * 0.2
                local arcEnd = swingStart + (swingEnd - swingStart) * math.min(1, arcT * 1.5 + 0.2)
                local arcR = orbitR + dSize * 0.35
                nvgBeginPath(vg)
                nvgArc(vg, dpx, dpy, arcR, arcStart, arcEnd, NVG_CCW)
                nvgStrokeColor(vg, nvgRGBA(200, 180, 255, arcAlpha))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                nvgStroke(vg)
            end
        end

        -- 命中火花（双武器交汇后）
        if t >= 0.32 and t < 0.52 then
            local st = (t - 0.32) / 0.20
            local sparkAlpha = math.floor(255 * (1 - st))
            local offsetDist = GS.CELL * 0.4
            local dpx = px - math.cos(dirAngle) * offsetDist
            local dpy = py - math.sin(dirAngle) * offsetDist
            local fragCount = 5
            for fi = 1, fragCount do
                local fAngle = (fi / fragCount) * math.pi * 2 + dirAngle + 0.5
                local fDist = GS.CELL * 0.05 + GS.CELL * 0.35 * st
                local fx = dpx + math.cos(fAngle) * fDist
                local fy = dpy + math.sin(fAngle) * fDist
                local fSize = math.max(1.5, GS.CELL * 0.03 * (1 - st * 0.6))
                nvgBeginPath(vg)
                nvgCircle(vg, fx, fy, fSize)
                nvgFillColor(vg, nvgRGBA(255, 200, 160, math.floor(sparkAlpha * 0.7)))
                nvgFill(vg)
            end
        end

        elseif e.weaponTag == "匕首" then

        -- ============================================================
        -- 单持匕首：快速突刺 + 弧光
        -- ============================================================
        if M.daggerImage ~= -1 then
            local dSize = GS.CELL * 0.55
            local offsetDist = GS.CELL * 0.4
            local dpx = px - math.cos(dirAngle) * offsetDist
            local dpy = py - math.sin(dirAngle) * offsetDist
            local rotAngle = dirAngle + math.rad(270)
            local orbitR = GS.CELL * 0.2

            -- 突刺动作（t: 0~0.35）：匕首从后方快速刺向前方
            if t < 0.35 then
                local stabT
                if t < 0.05 then
                    stabT = 0
                elseif t < 0.18 then
                    local st = (t - 0.05) / 0.13
                    stabT = st * st * (3 - 2 * st)
                else
                    stabT = 1.0
                end

                -- 匕首沿攻击方向突刺
                local stabDist = GS.CELL * 0.35
                local stabOff = -stabDist * 0.3 + stabDist * stabT
                local cx = dpx + math.cos(dirAngle) * stabOff
                local cy = dpy + math.sin(dirAngle) * stabOff
                local dAlpha = t < 0.03 and (t / 0.03) or (t > 0.26 and math.max(0, 1 - (t - 0.26) / 0.09) or 1.0)

                nvgSave(vg)
                nvgTranslate(vg, cx, cy)
                nvgRotate(vg, rotAngle)
                local imgPaint = nvgImagePattern(vg, -dSize / 2, -dSize / 2, dSize, dSize, 0, M.daggerImage, dAlpha)
                nvgBeginPath(vg)
                nvgRect(vg, -dSize / 2, -dSize / 2, dSize, dSize)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
                nvgRestore(vg)

                -- 突刺轨迹线
                if t >= 0.06 and t < 0.25 then
                    local trailT = (t - 0.06) / 0.19
                    local trailAlpha = math.floor(180 * (1 - trailT))
                    local trailLen = stabDist * 0.6 * math.min(1, trailT * 2)
                    local tx1 = cx - math.cos(dirAngle) * trailLen
                    local ty1 = cy - math.sin(dirAngle) * trailLen
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, tx1, ty1)
                    nvgLineTo(vg, cx, cy)
                    nvgStrokeColor(vg, nvgRGBA(220, 240, 255, trailAlpha))
                    nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                    nvgStroke(vg)
                end
            end

            -- 命中火花
            if t >= 0.20 and t < 0.45 then
                local st = (t - 0.20) / 0.25
                local sparkAlpha = math.floor(255 * (1 - st))
                local fragCount = 3
                for fi = 1, fragCount do
                    local fAngle = (fi / fragCount) * math.pi * 2 + dirAngle + 0.8
                    local fDist = GS.CELL * 0.05 + GS.CELL * 0.3 * st
                    local fx = dpx + math.cos(dirAngle) * GS.CELL * 0.15 + math.cos(fAngle) * fDist
                    local fy = dpy + math.sin(dirAngle) * GS.CELL * 0.15 + math.sin(fAngle) * fDist
                    local fSize = math.max(1.5, GS.CELL * 0.025 * (1 - st * 0.5))
                    nvgBeginPath(vg)
                    nvgCircle(vg, fx, fy, fSize)
                    nvgFillColor(vg, nvgRGBA(255, 220, 140, math.floor(sparkAlpha * 0.7)))
                    nvgFill(vg)
                end
            end
        end

        elseif e.weaponTag == "双匕首" then

        -- ============================================================
        -- 双持匕首：两把匕首交替挥砍
        -- ============================================================
        if M.daggerImage ~= -1 then
            local dSize = GS.CELL * 0.55
            local orbitR = GS.CELL * 0.2
            -- 整体朝玩家方向偏移
            local offsetDist = GS.CELL * 0.4
            local dpx = px - math.cos(dirAngle) * offsetDist
            local dpy = py - math.sin(dirAngle) * offsetDist
            local rotAngle = dirAngle + math.rad(270)

            -- 第一刀（t: 0~0.40），从 dirAngle-100° 挥到 dirAngle+40°
            if t < 0.40 then
                local slashT
                if t < 0.06 then
                    slashT = 0
                elseif t < 0.22 then
                    local st = (t - 0.06) / 0.16
                    slashT = st * st * (3 - 2 * st)
                else
                    slashT = 1.0
                end

                local swingStart = dirAngle - math.rad(100)
                local swingEnd   = dirAngle + math.rad(40)
                local curAngle = swingStart + (swingEnd - swingStart) * slashT
                local dAlpha = t < 0.03 and (t / 0.03) or (t > 0.30 and math.max(0, 1 - (t - 0.30) / 0.10) or 1.0)

                nvgSave(vg)
                nvgTranslate(vg, dpx + math.cos(curAngle) * orbitR, dpy + math.sin(curAngle) * orbitR)
                nvgRotate(vg, rotAngle)
                local imgPaint = nvgImagePattern(vg, -dSize / 2, -dSize / 2, dSize, dSize, 0, M.daggerImage, dAlpha)
                nvgBeginPath(vg)
                nvgRect(vg, -dSize / 2, -dSize / 2, dSize, dSize)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
                nvgRestore(vg)

                -- 第一刀刀光弧线
                if t >= 0.08 and t < 0.28 then
                    local arcT = (t - 0.08) / 0.20
                    local arcAlpha = math.floor(200 * (1 - arcT))
                    local arcStart = swingStart + (swingEnd - swingStart) * 0.2
                    local arcEnd = swingStart + (swingEnd - swingStart) * math.min(1, arcT * 1.5 + 0.2)
                    local arcR = orbitR + dSize * 0.35
                    nvgBeginPath(vg)
                    nvgArc(vg, dpx, dpy, arcR, arcStart, arcEnd, NVG_CW)
                    nvgStrokeColor(vg, nvgRGBA(220, 240, 255, arcAlpha))
                    nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                    nvgStroke(vg)
                end
            end

            -- 第二刀（t: 0.18~0.58），镜像方向：从 dirAngle+100° 挥到 dirAngle-40°
            if t >= 0.18 and t < 0.58 then
                local lt = t - 0.18
                local slashT
                if lt < 0.06 then
                    slashT = 0
                elseif lt < 0.22 then
                    local st = (lt - 0.06) / 0.16
                    slashT = st * st * (3 - 2 * st)
                else
                    slashT = 1.0
                end

                local swingStart = dirAngle + math.rad(100)
                local swingEnd   = dirAngle - math.rad(40)
                local curAngle = swingStart + (swingEnd - swingStart) * slashT
                local dAlpha = lt < 0.03 and (lt / 0.03) or (lt > 0.30 and math.max(0, 1 - (lt - 0.30) / 0.10) or 1.0)

                nvgSave(vg)
                nvgTranslate(vg, dpx + math.cos(curAngle) * orbitR, dpy + math.sin(curAngle) * orbitR)
                nvgRotate(vg, rotAngle)
                nvgScale(vg, -1, 1)  -- 水平镜像
                local imgPaint = nvgImagePattern(vg, -dSize / 2, -dSize / 2, dSize, dSize, 0, M.daggerImage, dAlpha)
                nvgBeginPath(vg)
                nvgRect(vg, -dSize / 2, -dSize / 2, dSize, dSize)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
                nvgRestore(vg)

                -- 第二刀刀光弧线（逆时针）
                if lt >= 0.08 and lt < 0.28 then
                    local arcT = (lt - 0.08) / 0.20
                    local arcAlpha = math.floor(200 * (1 - arcT))
                    local arcStart = swingStart + (swingEnd - swingStart) * 0.2
                    local arcEnd = swingStart + (swingEnd - swingStart) * math.min(1, arcT * 1.5 + 0.2)
                    local arcR = orbitR + dSize * 0.35
                    nvgBeginPath(vg)
                    nvgArc(vg, dpx, dpy, arcR, arcStart, arcEnd, NVG_CCW)
                    nvgStrokeColor(vg, nvgRGBA(220, 240, 255, arcAlpha))
                    nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                    nvgStroke(vg)
                end
            end

            -- 命中火花（两刀交汇后）
            if t >= 0.28 and t < 0.50 then
                local st = (t - 0.28) / 0.22
                local sparkAlpha = math.floor(255 * (1 - st))

                local fragCount = 4
                for fi = 1, fragCount do
                    local fAngle = (fi / fragCount) * math.pi * 2 + dirAngle + 0.5
                    local fDist = GS.CELL * 0.05 + GS.CELL * 0.35 * st
                    local fx = dpx + math.cos(fAngle) * fDist
                    local fy = dpy + math.sin(fAngle) * fDist
                    local fSize = math.max(1.5, GS.CELL * 0.03 * (1 - st * 0.6))
                    nvgBeginPath(vg)
                    nvgCircle(vg, fx, fy, fSize)
                    nvgFillColor(vg, nvgRGBA(255, 220, 140, math.floor(sparkAlpha * 0.7)))
                    nvgFill(vg)
                end
            end
        end

        elseif e.weaponTag == "爪" then

        -- ============================================================
        -- 猎犬爪击：三道抓痕直接出现在怪物身上 + 碎片飞溅
        -- ============================================================

        -- 三道爪痕（从怪物图标左边划到右边）
        if t >= 0.16 and t < 0.60 then
            local halfCell = GS.CELL * 0.5
            local slashAngle = math.rad(-15 + 180)  -- 旋转180度
            local scratchGap = halfCell * 0.35  -- 三道痕纵向间距

            for ci = -1, 1 do
                local delay = (ci + 1) * 0.08
                local localT = t - 0.16 - delay
                if localT < 0 then goto continue_claw end
                local ct = math.min(1, localT / 0.20)

                -- 从左侧划到右侧
                local startX = -halfCell * 0.85
                local endX   =  halfCell * 0.85
                local curEndX = startX + (endX - startX) * ct

                -- 纵向偏移
                local offsetY = ci * scratchGap

                -- 透明度：出现→保持→淡出
                local fadeT = (t - 0.16) / 0.44
                local alpha = fadeT < 0.6 and 255 or math.floor(255 * (1 - (fadeT - 0.6) / 0.4))

                nvgSave(vg)
                nvgTranslate(vg, px, py)
                nvgRotate(vg, slashAngle)

                -- 爪痕（锥形+向下弧度）
                local thickW = math.max(3, GS.CELL * 0.07)  -- 起始半宽
                local tipW   = math.max(0.5, GS.CELL * 0.008) -- 尾端半宽
                local midX = (startX + curEndX) * 0.5
                local sag  = halfCell * 0.3  -- 向下弯曲量

                nvgBeginPath(vg)
                -- 上边缘（向下弯的弧线）
                nvgMoveTo(vg, startX, offsetY - thickW)
                nvgQuadTo(vg, midX, offsetY - tipW + sag, curEndX, offsetY - tipW)
                -- 下边缘（反向回来，弧度更大一点）
                nvgLineTo(vg, curEndX, offsetY + tipW)
                nvgQuadTo(vg, midX, offsetY + thickW + sag, startX, offsetY + thickW)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 50, 30, alpha))
                nvgFill(vg)

                -- 高光（沿上边缘弧线）
                if ct > 0.3 then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, startX, offsetY - thickW + 1)
                    nvgQuadTo(vg, midX, offsetY - tipW + sag + 1, curEndX, offsetY - tipW)
                    nvgStrokeColor(vg, nvgRGBA(255, 220, 200, math.floor(alpha * 0.5)))
                    nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.015))
                    nvgStroke(vg)
                end

                nvgRestore(vg)
                ::continue_claw::
            end
        end

        -- 碎片飞溅（命中飞散的毛发/碎片）
        if t >= 0.20 and t < 0.50 then
            local st = (t - 0.20) / 0.30
            local fragAlpha = math.floor(200 * (1 - st))
            local fragCount = 6
            for fi = 1, fragCount do
                local fAngle = (fi / fragCount) * math.pi * 2 + dirAngle
                local fDist = r * 0.1 + r * 0.6 * st
                local fx = px + math.cos(fAngle) * fDist
                local fy = py + math.sin(fAngle) * fDist
                local fragSize = math.max(1.5, GS.CELL * 0.04 * (1 - st * 0.5))

                nvgBeginPath(vg)
                nvgCircle(vg, fx, fy, fragSize)
                nvgFillColor(vg, nvgRGBA(255, 180, 100, fragAlpha))
                nvgFill(vg)
            end
        end

        elseif isStaffAtk then
            -- ============================================================
            -- 法杖攻击：按 skillId 分发不同弹道特效
            -- ============================================================
            local time = GetTime():GetElapsedTime()
            local staffSkillId = e.skillId  -- nil = 普攻蓝色飞弹

            if staffSkillId == "m_spark" then
            -- ============================================================
            -- 火花术：燃烧火焰飞弹 + 命中火焰爆炸
            -- ============================================================
            local flyEnd = 0.55
            local hitT = 0.50

            -- 阶段1：火焰飞弹飞行
            if t >= 0.05 and t < flyEnd then
                local flyT = (t - 0.05) / (hitT - 0.05)
                flyT = math.min(flyT, 1.0)
                local ease = flyT * flyT * (3 - 2 * flyT)
                local mx = fpx + (px - fpx) * ease
                local my = fpy + (py - fpy) * ease
                local flyAlpha = flyT < 0.85 and 255 or math.floor(255 * (1 - (flyT - 0.85) / 0.15))
                local ddx = math.cos(dirAngle)
                local ddy = math.sin(dirAngle)

                -- 外层火焰光晕（橙红色）
                local flicker = 0.6 + 0.4 * math.sin(time * 32)
                local glowR = GS.CELL * (0.32 + 0.10 * flicker)
                local glowA = math.floor(220 * flicker * (flyAlpha / 255))
                local glow = nvgRadialGradient(vg, mx, my, 0, glowR,
                    nvgRGBA(255, 140, 30, glowA),
                    nvgRGBA(255, 60, 10, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, glowR)
                nvgFillPaint(vg, glow)
                nvgFill(vg)

                -- 火焰核心（亮黄色）
                local coreR = GS.CELL * 0.11 * (0.8 + 0.2 * flicker)
                local coreA = math.floor(255 * (flyAlpha / 255))
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, coreR)
                nvgFillColor(vg, nvgRGBA(255, 220, 80, coreA))
                nvgFill(vg)

                -- 内核白点
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, coreR * 0.45)
                nvgFillColor(vg, nvgRGBA(255, 255, 200, coreA))
                nvgFill(vg)

                -- 火焰拖尾（橙→暗红渐变）
                if flyT > 0.08 then
                    local traveledDist = math.sqrt((mx - fpx)^2 + (my - fpy)^2)
                    local trailLen = math.min(GS.CELL * 1.4 * math.min(1, flyT * 3), traveledDist)
                    local tx2 = mx - ddx * trailLen
                    local ty2 = my - ddy * trailLen
                    local trailA = math.floor(160 * (flyAlpha / 255))

                    nvgBeginPath(vg)
                    nvgMoveTo(vg, mx, my)
                    nvgLineTo(vg, tx2, ty2)
                    nvgStrokeColor(vg, nvgRGBA(255, 100, 20, trailA))
                    nvgStrokeWidth(vg, math.max(3, GS.CELL * 0.06))
                    nvgStroke(vg)

                    -- 亮芯拖尾
                    local tx3 = mx - ddx * trailLen * 0.5
                    local ty3 = my - ddy * trailLen * 0.5
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, mx, my)
                    nvgLineTo(vg, tx3, ty3)
                    nvgStrokeColor(vg, nvgRGBA(255, 200, 60, math.floor(trailA * 0.7)))
                    nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.03))
                    nvgStroke(vg)
                end

                -- 火花粒子群（16个，模拟燃烧散落的火星）
                for i = 1, 16 do
                    local seed = i * 97.3 + time * 5
                    local pAngle = seed + flyT * 12
                    local pDist = GS.CELL * (0.08 + 0.14 * math.abs(math.sin(seed * 0.7)))
                    -- 粒子向后方偏移，模拟火星脱落
                    local backOff = flyT * GS.CELL * 0.15 * (0.5 + 0.5 * math.sin(seed))
                    local ppx = mx + math.cos(pAngle) * pDist - ddx * backOff
                    local ppy = my + math.sin(pAngle) * pDist - ddy * backOff
                    local pLife = (math.sin(seed * 1.3 + time * 8) + 1) * 0.5
                    local pAlpha = math.floor(200 * pLife * (flyAlpha / 255))
                    local pSize = math.max(1, GS.CELL * 0.025 * (0.5 + pLife * 0.5))
                    -- 颜色在黄→橙→红之间变化
                    local cR = 255
                    local cG = math.floor(100 + 150 * pLife)
                    local cB = math.floor(20 + 40 * pLife)
                    nvgBeginPath(vg)
                    nvgCircle(vg, ppx, ppy, pSize)
                    nvgFillColor(vg, nvgRGBA(cR, cG, cB, pAlpha))
                    nvgFill(vg)
                end

                -- 飞行方向前端的跳跃火苗（4个小火焰形状）
                for i = 1, 4 do
                    local fSeed = i * 47.1
                    local fAngle = dirAngle + (math.sin(fSeed + time * 10) * 0.6)
                    local fDist = coreR * (1.0 + 0.5 * math.sin(fSeed + time * 12))
                    local fx = mx + math.cos(fAngle) * fDist
                    local fy = my + math.sin(fAngle) * fDist
                    local fSize = GS.CELL * 0.04 * (0.6 + 0.4 * math.sin(fSeed + time * 15))
                    local fA = math.floor(180 * (flyAlpha / 255))
                    nvgBeginPath(vg)
                    nvgCircle(vg, fx, fy, fSize)
                    nvgFillColor(vg, nvgRGBA(255, 180, 40, fA))
                    nvgFill(vg)
                end
            end

            -- 阶段2：火焰命中爆炸
            if t >= hitT and t < 0.85 then
                local expT = (t - hitT) / 0.35
                -- 火焰爆炸扩散环
                local ringR = GS.CELL * (0.15 + expT * 0.6)
                local ringA = math.floor(240 * (1 - expT))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, ringR)
                nvgStrokeColor(vg, nvgRGBA(255, 120, 20, ringA))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.07 * (1 - expT * 0.5)))
                nvgStroke(vg)

                -- 火焰爆炸填充光晕
                local fillR = GS.CELL * (0.12 + expT * 0.45)
                local fillA = math.floor(180 * (1 - expT * expT))
                local expGlow = nvgRadialGradient(vg, px, py, 0, fillR,
                    nvgRGBA(255, 180, 40, fillA),
                    nvgRGBA(255, 60, 10, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, fillR)
                nvgFillPaint(vg, expGlow)
                nvgFill(vg)

                -- 内核闪光（亮白黄色）
                if expT < 0.3 then
                    local flashA = math.floor(255 * (1 - expT / 0.3))
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, GS.CELL * 0.13 * (1 - expT))
                    nvgFillColor(vg, nvgRGBA(255, 250, 200, flashA))
                    nvgFill(vg)
                end

                -- 燃烧碎片火星（16个）
                for i = 1, 16 do
                    local fAngle = (i / 16) * math.pi * 2 + expT * 3
                    local fDist = GS.CELL * (0.1 + expT * 0.55) * (0.6 + 0.4 * math.sin(i * 3.1))
                    local fragAlpha = math.floor(220 * (1 - expT))
                    local fx = px + math.cos(fAngle) * fDist
                    local fy = py + math.sin(fAngle) * fDist
                    -- 重力下坠效果
                    fy = fy + expT * expT * GS.CELL * 0.3 * ((i % 3) * 0.3 + 0.1)
                    local fragSize = math.max(1.0, GS.CELL * 0.03 * (1 - expT * 0.4))
                    local cG = math.floor(80 + 120 * (1 - expT))
                    nvgBeginPath(vg)
                    nvgCircle(vg, fx, fy, fragSize)
                    nvgFillColor(vg, nvgRGBA(255, cG, 20, fragAlpha))
                    nvgFill(vg)
                end
            end

            elseif staffSkillId == "m_ice_spike" then
            -- ============================================================
            -- 冰锥术：菱形冰锥弹道 + 命中冰碎
            -- ============================================================
            local flyEnd = 0.55
            local hitT = 0.50

            -- 阶段1：冰锥飞行
            if t >= 0.05 and t < flyEnd then
                local flyT = (t - 0.05) / (hitT - 0.05)
                flyT = math.min(flyT, 1.0)
                local ease = flyT * flyT * (3 - 2 * flyT)
                local mx = fpx + (px - fpx) * ease
                local my = fpy + (py - fpy) * ease
                local flyAlpha = flyT < 0.85 and 255 or math.floor(255 * (1 - (flyT - 0.85) / 0.15))

                -- 冰锥寒气光晕
                local flicker = 0.7 + 0.3 * math.sin(time * 20)
                local glowR = GS.CELL * (0.24 + 0.06 * flicker)
                local glowA = math.floor(140 * flicker * (flyAlpha / 255))
                local glow = nvgRadialGradient(vg, mx, my, 0, glowR,
                    nvgRGBA(140, 210, 255, glowA),
                    nvgRGBA(80, 160, 240, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, glowR)
                nvgFillPaint(vg, glow)
                nvgFill(vg)

                -- 菱形冰锥主体（旋转的菱形，沿飞行方向对齐）
                nvgSave(vg)
                nvgTranslate(vg, mx, my)
                nvgRotate(vg, dirAngle)
                -- 菱形：前端尖锐，后端略宽
                local spikeLen = GS.CELL * 0.30  -- 半长轴（前后）
                local spikeW = GS.CELL * 0.10    -- 半短轴（上下）
                -- 外层冰晶轮廓光（浅蓝半透明）
                nvgBeginPath(vg)
                nvgMoveTo(vg, spikeLen * 1.1, 0)             -- 前端尖
                nvgLineTo(vg, 0, -spikeW * 1.2)              -- 上
                nvgLineTo(vg, -spikeLen * 0.7, 0)            -- 后端
                nvgLineTo(vg, 0, spikeW * 1.2)               -- 下
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(120, 200, 255, math.floor(60 * (flyAlpha / 255))))
                nvgFill(vg)

                -- 菱形冰锥填充（蓝白渐变）
                nvgBeginPath(vg)
                nvgMoveTo(vg, spikeLen, 0)                   -- 前端尖
                nvgLineTo(vg, 0, -spikeW)                    -- 上
                nvgLineTo(vg, -spikeLen * 0.6, 0)            -- 后端
                nvgLineTo(vg, 0, spikeW)                     -- 下
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(180, 230, 255, math.floor(230 * (flyAlpha / 255))))
                nvgFill(vg)

                -- 冰锥中心亮线（高光棱线）
                nvgBeginPath(vg)
                nvgMoveTo(vg, spikeLen * 0.9, 0)
                nvgLineTo(vg, -spikeLen * 0.4, 0)
                nvgStrokeColor(vg, nvgRGBA(230, 245, 255, math.floor(200 * (flyAlpha / 255))))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.02))
                nvgStroke(vg)

                -- 冰锥边缘描边
                nvgBeginPath(vg)
                nvgMoveTo(vg, spikeLen, 0)
                nvgLineTo(vg, 0, -spikeW)
                nvgLineTo(vg, -spikeLen * 0.6, 0)
                nvgLineTo(vg, 0, spikeW)
                nvgClosePath(vg)
                nvgStrokeColor(vg, nvgRGBA(200, 240, 255, math.floor(180 * (flyAlpha / 255))))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)

                nvgRestore(vg)

                -- 冰碎粒子拖尾（沿飞行路径散落的冰晶碎片）
                local ddx = math.cos(dirAngle)
                local ddy = math.sin(dirAngle)
                for i = 1, 8 do
                    local seed = i * 83.7
                    local backDist = (0.1 + 0.3 * math.abs(math.sin(seed))) * GS.CELL * flyT
                    local lateralOff = math.sin(seed * 2.1 + time * 6) * GS.CELL * 0.06
                    local ipx = mx - ddx * backDist + (-ddy) * lateralOff
                    local ipy = my - ddy * backDist + ddx * lateralOff
                    local iAlpha = math.floor(140 * (1 - flyT * 0.6) * (flyAlpha / 255))
                    local iSize = math.max(1, GS.CELL * 0.02 * (1 - flyT * 0.3))
                    nvgBeginPath(vg)
                    nvgCircle(vg, ipx, ipy, iSize)
                    nvgFillColor(vg, nvgRGBA(180, 230, 255, iAlpha))
                    nvgFill(vg)
                end
            end

            -- 阶段2：命中冰碎爆发
            if t >= hitT and t < 0.85 then
                local expT = (t - hitT) / 0.35
                -- 冰碎扩散环
                local ringR = GS.CELL * (0.12 + expT * 0.50)
                local ringA = math.floor(200 * (1 - expT))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, ringR)
                nvgStrokeColor(vg, nvgRGBA(140, 220, 255, ringA))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.05 * (1 - expT * 0.5)))
                nvgStroke(vg)

                -- 冰霜填充
                local fillR = GS.CELL * (0.10 + expT * 0.35)
                local fillA = math.floor(140 * (1 - expT * expT))
                local iceGlow = nvgRadialGradient(vg, px, py, 0, fillR,
                    nvgRGBA(180, 230, 255, fillA),
                    nvgRGBA(100, 180, 240, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, fillR)
                nvgFillPaint(vg, iceGlow)
                nvgFill(vg)

                -- 白光闪烁
                if expT < 0.25 then
                    local flashA = math.floor(220 * (1 - expT / 0.25))
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, GS.CELL * 0.10 * (1 - expT))
                    nvgFillColor(vg, nvgRGBA(240, 250, 255, flashA))
                    nvgFill(vg)
                end

                -- 冰碎片（12个小菱形碎片向外飞散）
                for i = 1, 12 do
                    local fAngle = (i / 12) * math.pi * 2 + expT * 1.5
                    local fDist = GS.CELL * (0.08 + expT * 0.50) * (0.7 + 0.3 * math.sin(i * 2.3))
                    local fragAlpha = math.floor(200 * (1 - expT))
                    local fx = px + math.cos(fAngle) * fDist
                    local fy = py + math.sin(fAngle) * fDist
                    local fragSize = math.max(1, GS.CELL * 0.025 * (1 - expT * 0.3))
                    -- 绘制小菱形碎片
                    nvgSave(vg)
                    nvgTranslate(vg, fx, fy)
                    nvgRotate(vg, fAngle + expT * 4)
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, fragSize * 1.5, 0)
                    nvgLineTo(vg, 0, -fragSize)
                    nvgLineTo(vg, -fragSize * 1.5, 0)
                    nvgLineTo(vg, 0, fragSize)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(180, 230, 255, fragAlpha))
                    nvgFill(vg)
                    nvgRestore(vg)
                end
            end

            elseif staffSkillId == "m_lightning" then
            -- ============================================================
            -- 电击术：闪电弧线从玩家劈向敌人
            -- ============================================================
            -- 闪电不用飞弹，而是直接连线，快速出现再消失
            local flashIn = 0.08    -- 闪电出现时间
            local holdEnd = 0.45    -- 闪电保持
            local fadeEnd = 0.80    -- 淡出结束

            if t < fadeEnd then
                local boltAlpha = 255
                if t < flashIn then
                    boltAlpha = math.floor(255 * (t / flashIn))
                elseif t > holdEnd then
                    boltAlpha = math.floor(255 * (1 - (t - holdEnd) / (fadeEnd - holdEnd)))
                end

                -- 生成锯齿形闪电路径（使用确定性种子保持稳定）
                local segments = 8
                local boltPoints = {}
                local baseSeed = e.fx * 7.3 + e.fy * 13.7 + e.x * 3.1 + e.y * 5.9
                -- 闪电在 hold 期间微微抖动，用 time 的整数部分做种子切换
                local jitterSeed = math.floor(time * 12)

                for si = 0, segments do
                    local st = si / segments
                    local bx = fpx + (px - fpx) * st
                    local by = fpy + (py - fpy) * st
                    if si > 0 and si < segments then
                        -- 垂直于飞行方向的偏移
                        local perpX = -(py - fpy)
                        local perpY = (px - fpx)
                        local perpLen = math.sqrt(perpX * perpX + perpY * perpY)
                        if perpLen > 0.01 then
                            perpX = perpX / perpLen
                            perpY = perpY / perpLen
                        end
                        local offsetMag = GS.CELL * 0.18 * math.sin(baseSeed + si * 2.7 + jitterSeed * 0.3)
                        -- 中间段偏移更大，两端收拢
                        local envelop = math.sin(st * math.pi)
                        bx = bx + perpX * offsetMag * envelop
                        by = by + perpY * offsetMag * envelop
                    end
                    boltPoints[si + 1] = { bx, by }
                end

                -- 外层光晕线（宽，低透明度，模拟电光弥散）
                nvgBeginPath(vg)
                nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
                for si = 2, #boltPoints do
                    nvgLineTo(vg, boltPoints[si][1], boltPoints[si][2])
                end
                nvgStrokeColor(vg, nvgRGBA(200, 200, 255, math.floor(boltAlpha * 0.25)))
                nvgStrokeWidth(vg, math.max(6, GS.CELL * 0.14))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)

                -- 中层电弧（主体，亮黄色）
                nvgBeginPath(vg)
                nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
                for si = 2, #boltPoints do
                    nvgLineTo(vg, boltPoints[si][1], boltPoints[si][2])
                end
                nvgStrokeColor(vg, nvgRGBA(255, 240, 100, boltAlpha))
                nvgStrokeWidth(vg, math.max(2.5, GS.CELL * 0.05))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)

                -- 内核亮线（白色）
                nvgBeginPath(vg)
                nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
                for si = 2, #boltPoints do
                    nvgLineTo(vg, boltPoints[si][1], boltPoints[si][2])
                end
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(boltAlpha * 0.8)))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.02))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)

                -- 分支闪电（从主线中间段分叉出去的小闪电）
                for bi = 1, 3 do
                    local branchIdx = math.floor(1 + (bi / 4) * segments)
                    branchIdx = math.min(branchIdx, #boltPoints)
                    local bp = boltPoints[branchIdx]
                    local branchAngle = baseSeed + bi * 1.9 + jitterSeed * 0.5
                    local branchLen = GS.CELL * (0.12 + 0.08 * math.sin(branchAngle))
                    local bex = bp[1] + math.cos(branchAngle) * branchLen
                    local bey = bp[2] + math.sin(branchAngle) * branchLen
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, bp[1], bp[2])
                    -- 小锯齿
                    local midBx = (bp[1] + bex) / 2 + math.sin(branchAngle * 3) * GS.CELL * 0.05
                    local midBy = (bp[2] + bey) / 2 + math.cos(branchAngle * 3) * GS.CELL * 0.05
                    nvgLineTo(vg, midBx, midBy)
                    nvgLineTo(vg, bex, bey)
                    nvgStrokeColor(vg, nvgRGBA(255, 240, 140, math.floor(boltAlpha * 0.5)))
                    nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.025))
                    nvgLineCap(vg, NVG_ROUND)
                    nvgLineJoin(vg, NVG_ROUND)
                    nvgStroke(vg)
                end

                -- 起点电弧光球（玩家端）
                local startGlowR = GS.CELL * 0.15
                local startGlowA = math.floor(boltAlpha * 0.5)
                local sg = nvgRadialGradient(vg, fpx, fpy, 0, startGlowR,
                    nvgRGBA(255, 240, 100, startGlowA),
                    nvgRGBA(255, 200, 60, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, fpx, fpy, startGlowR)
                nvgFillPaint(vg, sg)
                nvgFill(vg)

                -- 终点电击光球（敌人端）
                local endGlowR = GS.CELL * 0.20
                local endGlowA = math.floor(boltAlpha * 0.6)
                local eg = nvgRadialGradient(vg, px, py, 0, endGlowR,
                    nvgRGBA(255, 250, 150, endGlowA),
                    nvgRGBA(255, 220, 60, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, endGlowR)
                nvgFillPaint(vg, eg)
                nvgFill(vg)

                -- 终点电花粒子
                for i = 1, 6 do
                    local spAngle = (i / 6) * math.pi * 2 + time * 8
                    local spDist = GS.CELL * 0.12 * (0.5 + 0.5 * math.sin(i * 1.7 + time * 10))
                    local spx = px + math.cos(spAngle) * spDist
                    local spy = py + math.sin(spAngle) * spDist
                    local spA = math.floor(boltAlpha * 0.6)
                    nvgBeginPath(vg)
                    nvgCircle(vg, spx, spy, math.max(1, GS.CELL * 0.02))
                    nvgFillColor(vg, nvgRGBA(255, 255, 200, spA))
                    nvgFill(vg)
                end
            end

            -- 恢复 lineCap 默认值
            nvgLineCap(vg, NVG_BUTT)

            else
            -- ============================================================
            -- 默认：魔法飞弹（按 monsterProjectile 选色，默认紫色）
            -- ============================================================
            -- 颜色方案: {光晕外, 光晕内边, 核心, 内核亮点, 拖尾, 亮芯拖尾, 螺旋粒子, 爆炸环, 爆炸光晕外, 爆炸光晕内边, 闪光, 碎片}
            local mp = e.monsterProjectile

            -- ============================================================
            -- 火球术弹道（红龙幼龙专属）：巨大火球 + 热浪光晕 + 拖尾火焰粒子
            -- ============================================================
            if mp == "fireball" then
                local flyEnd = 0.55
                local hitT = 0.50
                -- 阶段1：巨大火球飞行 (t 0.05~0.55)
                if t >= 0.05 and t < flyEnd then
                    local flyT = (t - 0.05) / (hitT - 0.05)
                    flyT = math.min(flyT, 1.0)
                    local ease = flyT * flyT * (3 - 2 * flyT)
                    local mx = fpx + (px - fpx) * ease
                    local my = fpy + (py - fpy) * ease
                    local flyAlpha = flyT < 0.85 and 255 or math.floor(255 * (1 - (flyT - 0.85) / 0.15))
                    local flicker = (math.sin(time * 18) + math.sin(time * 27)) * 0.15 + 0.85

                    -- 火球大小：从中等到很大
                    local ballR = GS.CELL * (0.22 + 0.12 * flyT)

                    -- 外层炽热光晕（大范围橙色辉光）
                    local heatR = ballR * 2.5
                    local heatA = math.floor(70 * flicker * (flyAlpha / 255))
                    local heatGlow = nvgRadialGradient(vg, mx, my, ballR * 0.5, heatR,
                        nvgRGBA(255, 100, 20, heatA),
                        nvgRGBA(255, 40, 0, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, mx, my, heatR)
                    nvgFillPaint(vg, heatGlow)
                    nvgFill(vg)

                    -- 火球主体（橙红渐变球体）
                    local ballA = math.floor(255 * (flyAlpha / 255))
                    local ballGrad = nvgRadialGradient(vg, mx - ballR * 0.2, my - ballR * 0.2,
                        ballR * 0.15, ballR,
                        nvgRGBA(255, 240, 160, ballA),
                        nvgRGBA(230, 60, 10, math.floor(220 * flicker * (flyAlpha / 255))))
                    nvgBeginPath(vg)
                    nvgCircle(vg, mx, my, ballR)
                    nvgFillPaint(vg, ballGrad)
                    nvgFill(vg)

                    -- 火球核心高光
                    local coreR = ballR * 0.4
                    nvgBeginPath(vg)
                    nvgCircle(vg, mx - ballR * 0.15, my - ballR * 0.15, coreR)
                    nvgFillColor(vg, nvgRGBA(255, 255, 220, math.floor(200 * flicker * (flyAlpha / 255))))
                    nvgFill(vg)

                    -- 火球边缘轮廓
                    nvgBeginPath(vg)
                    nvgCircle(vg, mx, my, ballR)
                    nvgStrokeColor(vg, nvgRGBA(255, 120, 20, math.floor(160 * flicker * (flyAlpha / 255))))
                    nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.02))
                    nvgStroke(vg)

                    -- 飞行拖尾火焰粒子（12个）
                    local ddx = math.cos(dirAngle)
                    local ddy = math.sin(dirAngle)
                    for i = 1, 12 do
                        local seed1 = i * 137.508
                        local seed2 = i * 73.137 + 4.21
                        local trailT = math.max(0, flyT - (seed2 % 6) * 0.015 - 0.02)
                        if trailT > 0 then
                            local tx = fpx + (px - fpx) * (trailT * trailT * (3 - 2 * trailT))
                            local ty = fpy + (py - fpy) * (trailT * trailT * (3 - 2 * trailT))
                            local spread = GS.CELL * 0.12 * (flyT - trailT + 0.05)
                            tx = tx + math.sin(seed1) * spread
                            ty = ty + math.cos(seed1) * spread - (flyT - trailT) * GS.CELL * 0.25
                            local tSize = math.max(1.0, ballR * 0.25 * (1.0 - (flyT - trailT) * 4))
                            local tAlpha = math.floor(160 * math.max(0, 1.0 - (flyT - trailT) * 5) * (flyAlpha / 255))
                            local age = (flyT - trailT) * 5
                            local tR = math.floor(255 - 30 * math.min(1, age))
                            local tG = math.floor(200 - 150 * math.min(1, age))
                            local tB = math.floor(60 - 50 * math.min(1, age))
                            if tAlpha > 5 and tSize > 0.5 then
                                nvgBeginPath(vg)
                                nvgCircle(vg, tx, ty, tSize)
                                nvgFillColor(vg, nvgRGBA(tR, tG, tB, tAlpha))
                                nvgFill(vg)
                            end
                        end
                    end
                end

                -- 阶段2：命中爆炸（火焰冲击波，3x3 范围视觉提示）
                if t >= hitT and t < 0.90 then
                    local expT = (t - hitT) / 0.40
                    -- 爆炸闪光（短暂）
                    if expT < 0.15 then
                        local flashR = GS.CELL * 0.5 + GS.CELL * 1.5 * (expT / 0.15)
                        local flashA = math.floor(220 * (1.0 - expT / 0.15))
                        local flashGrad = nvgRadialGradient(vg, px, py, 0, flashR,
                            nvgRGBA(255, 255, 200, flashA),
                            nvgRGBA(255, 160, 40, math.floor(flashA * 0.5)))
                        nvgBeginPath(vg)
                        nvgCircle(vg, px, py, flashR)
                        nvgFillPaint(vg, flashGrad)
                        nvgFill(vg)
                    end
                    -- 火焰冲击波扩散环（暗示 3x3 范围）
                    local waveR = GS.CELL * (0.3 + 1.5 * math.min(1, expT))
                    local waveA = math.floor(200 * math.max(0, 1.0 - expT))
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, waveR)
                    nvgStrokeColor(vg, nvgRGBA(255, 140, 40, waveA))
                    nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.06 * (1 - expT * 0.5)))
                    nvgStroke(vg)
                    -- 爆炸填充光晕
                    local fillR = GS.CELL * (0.2 + 1.2 * math.min(1, expT * 1.5))
                    local fillA = math.floor(140 * math.max(0, 1.0 - expT * expT))
                    local expGlow = nvgRadialGradient(vg, px, py, 0, fillR,
                        nvgRGBA(255, 160, 60, fillA),
                        nvgRGBA(200, 60, 10, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, fillR)
                    nvgFillPaint(vg, expGlow)
                    nvgFill(vg)
                    -- 爆炸碎片粒子
                    for i = 1, 16 do
                        local fAngle = (i / 16) * math.pi * 2 + expT * 2
                        local fDist = GS.CELL * (0.15 + expT * 0.8) * (0.7 + 0.3 * math.sin(i * 2.7))
                        local fragA = math.floor(180 * math.max(0, 1.0 - expT))
                        local fx = px + math.cos(fAngle) * fDist
                        local fy = py + math.sin(fAngle) * fDist
                        local fragSize = math.max(1.2, GS.CELL * 0.04 * (1 - expT * 0.5))
                        nvgBeginPath(vg)
                        nvgCircle(vg, fx, fy, fragSize)
                        nvgFillColor(vg, nvgRGBA(255, 150, 40, fragA))
                        nvgFill(vg)
                    end
                end

            else -- 非 fireball：原有魔法飞弹渲染

            local cGlowOut, cGlowIn, cCore, cBright, cTrail, cTrailBright, cParticle, cRing, cExpOut, cExpIn, cFlash, cFrag
            if mp == "fire" then
                -- 火焰：橙红色系
                cGlowOut     = {255, 120, 30}
                cGlowIn      = {255, 60, 10}
                cCore        = {255, 200, 80}
                cBright       = {255, 240, 180}
                cTrail       = {255, 120, 30}
                cTrailBright = {255, 200, 80}
                cParticle    = {255, 150, 40}
                cRing        = {255, 140, 40}
                cExpOut      = {255, 160, 60}
                cExpIn       = {200, 80, 10}
                cFlash       = {255, 230, 180}
                cFrag        = {255, 150, 40}
            elseif mp == "nature" then
                -- 自然：翠绿色系
                cGlowOut     = {60, 200, 80}
                cGlowIn      = {30, 160, 50}
                cCore        = {140, 240, 140}
                cBright       = {200, 255, 210}
                cTrail       = {60, 200, 80}
                cTrailBright = {140, 240, 140}
                cParticle    = {80, 220, 100}
                cRing        = {80, 210, 90}
                cExpOut      = {120, 230, 120}
                cExpIn       = {40, 150, 50}
                cFlash       = {210, 255, 220}
                cFrag        = {80, 220, 100}
            elseif mp == "ice" then
                -- 冰冻：冰蓝色系
                cGlowOut     = {80, 180, 255}
                cGlowIn      = {40, 120, 220}
                cCore        = {160, 220, 255}
                cBright       = {220, 240, 255}
                cTrail       = {80, 180, 255}
                cTrailBright = {160, 220, 255}
                cParticle    = {100, 200, 255}
                cRing        = {100, 190, 250}
                cExpOut      = {140, 210, 255}
                cExpIn       = {60, 130, 210}
                cFlash       = {230, 245, 255}
                cFrag        = {100, 200, 255}
            elseif mp == "dark" then
                -- 暗黑：深紫+暗红色系
                cGlowOut     = {120, 40, 180}
                cGlowIn      = {80, 20, 140}
                cCore        = {180, 80, 220}
                cBright       = {220, 160, 255}
                cTrail       = {120, 40, 180}
                cTrailBright = {180, 80, 220}
                cParticle    = {140, 60, 200}
                cRing        = {140, 50, 200}
                cExpOut      = {160, 80, 220}
                cExpIn       = {90, 30, 150}
                cFlash       = {210, 170, 255}
                cFrag        = {140, 60, 200}
            elseif mp == "thunder" then
                -- 雷电：亮黄+电光蓝色系
                cGlowOut     = {255, 240, 80}
                cGlowIn      = {220, 200, 40}
                cCore        = {255, 255, 180}
                cBright       = {255, 255, 230}
                cTrail       = {255, 240, 80}
                cTrailBright = {255, 255, 180}
                cParticle    = {200, 230, 255}
                cRing        = {255, 240, 100}
                cExpOut      = {255, 245, 140}
                cExpIn       = {200, 180, 40}
                cFlash       = {255, 255, 240}
                cFrag        = {220, 230, 255}
            elseif mp == "light" then
                -- 神圣：金白色系
                cGlowOut     = {255, 220, 120}
                cGlowIn      = {240, 200, 80}
                cCore        = {255, 245, 200}
                cBright       = {255, 255, 240}
                cTrail       = {255, 220, 120}
                cTrailBright = {255, 245, 200}
                cParticle    = {255, 230, 150}
                cRing        = {255, 225, 130}
                cExpOut      = {255, 240, 170}
                cExpIn       = {220, 180, 60}
                cFlash       = {255, 250, 230}
                cFrag        = {255, 230, 150}
            else
                -- 默认 / arcane：经典紫色（奥术）
                cGlowOut     = {140, 100, 220}
                cGlowIn      = {100, 60, 200}
                cCore        = {200, 170, 255}
                cBright       = {240, 220, 255}
                cTrail       = {140, 100, 220}
                cTrailBright = {200, 170, 255}
                cParticle    = {170, 130, 255}
                cRing        = {160, 120, 240}
                cExpOut      = {180, 140, 255}
                cExpIn       = {120, 80, 200}
                cFlash       = {230, 210, 255}
                cFrag        = {170, 130, 255}
            end

            local flyEnd = 0.55
            local hitT = 0.50

            -- 阶段1：魔法飞弹飞行 (t 0.05~0.55)
            if t >= 0.05 and t < flyEnd then
                local flyT = (t - 0.05) / (hitT - 0.05)
                flyT = math.min(flyT, 1.0)
                local ease = flyT * flyT * (3 - 2 * flyT)
                local mx = fpx + (px - fpx) * ease
                local my = fpy + (py - fpy) * ease
                local flyAlpha = flyT < 0.85 and 255 or math.floor(255 * (1 - (flyT - 0.85) / 0.15))
                local ddx = math.cos(dirAngle)
                local ddy = math.sin(dirAngle)

                -- 外层光晕
                local flicker = 0.6 + 0.4 * math.sin(time * 28)
                local glowR = GS.CELL * (0.28 + 0.08 * flicker)
                local glowA = math.floor(200 * flicker * (flyAlpha / 255))
                local glow = nvgRadialGradient(vg, mx, my, 0, glowR,
                    nvgRGBA(cGlowOut[1], cGlowOut[2], cGlowOut[3], glowA),
                    nvgRGBA(cGlowIn[1], cGlowIn[2], cGlowIn[3], 0))
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, glowR)
                nvgFillPaint(vg, glow)
                nvgFill(vg)

                -- 核心光球
                local coreR = GS.CELL * 0.10 * (0.8 + 0.2 * flicker)
                local coreA = math.floor(255 * (flyAlpha / 255))
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, coreR)
                nvgFillColor(vg, nvgRGBA(cCore[1], cCore[2], cCore[3], coreA))
                nvgFill(vg)

                -- 内核亮点
                nvgBeginPath(vg)
                nvgCircle(vg, mx, my, coreR * 0.5)
                nvgFillColor(vg, nvgRGBA(cBright[1], cBright[2], cBright[3], coreA))
                nvgFill(vg)

                -- 拖尾
                if flyT > 0.08 then
                    local traveledDist = math.sqrt((mx - fpx)^2 + (my - fpy)^2)
                    local trailLen = math.min(GS.CELL * 1.2 * math.min(1, flyT * 3), traveledDist)
                    local tx2 = mx - ddx * trailLen
                    local ty2 = my - ddy * trailLen
                    local trailA = math.floor(140 * (flyAlpha / 255))

                    nvgBeginPath(vg)
                    nvgMoveTo(vg, mx, my)
                    nvgLineTo(vg, tx2, ty2)
                    nvgStrokeColor(vg, nvgRGBA(cTrail[1], cTrail[2], cTrail[3], trailA))
                    nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.05))
                    nvgStroke(vg)

                    -- 亮芯拖尾
                    local tx3 = mx - ddx * trailLen * 0.5
                    local ty3 = my - ddy * trailLen * 0.5
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, mx, my)
                    nvgLineTo(vg, tx3, ty3)
                    nvgStrokeColor(vg, nvgRGBA(cTrailBright[1], cTrailBright[2], cTrailBright[3], math.floor(trailA * 0.6)))
                    nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.025))
                    nvgStroke(vg)
                end

                -- 螺旋粒子
                for i = 1, 8 do
                    local seed = i * 137.5
                    local spiralAngle = seed + flyT * 18
                    local spiralR = GS.CELL * 0.12 * (1 - flyT * 0.3)
                    local ppx = mx + math.cos(spiralAngle) * spiralR
                    local ppy = my + math.sin(spiralAngle) * spiralR
                    local pAlpha = math.floor(160 * (1 - flyT * 0.5) * (flyAlpha / 255))
                    nvgBeginPath(vg)
                    nvgCircle(vg, ppx, ppy, 1.5)
                    nvgFillColor(vg, nvgRGBA(cParticle[1], cParticle[2], cParticle[3], pAlpha))
                    nvgFill(vg)
                end
            end

            -- 阶段2：命中爆炸 (t 0.50~0.85)
            if t >= hitT and t < 0.85 then
                local expT = (t - hitT) / 0.35
                -- 爆炸扩散环
                local ringR = GS.CELL * (0.15 + expT * 0.55)
                local ringA = math.floor(220 * (1 - expT))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, ringR)
                nvgStrokeColor(vg, nvgRGBA(cRing[1], cRing[2], cRing[3], ringA))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.06 * (1 - expT * 0.5)))
                nvgStroke(vg)

                -- 爆炸填充光晕
                local fillR = GS.CELL * (0.1 + expT * 0.4)
                local fillA = math.floor(160 * (1 - expT * expT))
                local expGlow = nvgRadialGradient(vg, px, py, 0, fillR,
                    nvgRGBA(cExpOut[1], cExpOut[2], cExpOut[3], fillA),
                    nvgRGBA(cExpIn[1], cExpIn[2], cExpIn[3], 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, fillR)
                nvgFillPaint(vg, expGlow)
                nvgFill(vg)

                -- 内核闪光（短暂）
                if expT < 0.3 then
                    local flashA = math.floor(255 * (1 - expT / 0.3))
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, GS.CELL * 0.12 * (1 - expT))
                    nvgFillColor(vg, nvgRGBA(cFlash[1], cFlash[2], cFlash[3], flashA))
                    nvgFill(vg)
                end

                -- 爆炸碎片粒子
                for i = 1, 12 do
                    local fAngle = (i / 12) * math.pi * 2 + expT * 2
                    local fDist = GS.CELL * (0.1 + expT * 0.5) * (0.7 + 0.3 * math.sin(i * 2.7))
                    local fragAlpha = math.floor(200 * (1 - expT))
                    local fx = px + math.cos(fAngle) * fDist
                    local fy = py + math.sin(fAngle) * fDist
                    local fragSize = math.max(1.2, GS.CELL * 0.035 * (1 - expT * 0.5))

                    nvgBeginPath(vg)
                    nvgCircle(vg, fx, fy, fragSize)
                    nvgFillColor(vg, nvgRGBA(cFrag[1], cFrag[2], cFrag[3], fragAlpha))
                    nvgFill(vg)
                end
            end

            end -- fireball / 通用魔法飞弹分支结束
            end -- staffSkillId 分支结束

        elseif not isBowAtk and not isStaffAtk and not isLittleZeusAtk then

        -- 根据武器类型选择图片（锤用锤图片，其他用剑图片）
        local isMaceAtk = (e.weaponTag == "锤")
        local meleeImg = (isMaceAtk and M.maceImage ~= -1) and M.maceImage or M.swordImage

        -- ============================================================
        -- 近战挥砍 + 残影（旋转轴心在柄位置）
        -- ============================================================
        if meleeImg ~= -1 and t < 0.55 then
            local swordSize = GS.CELL * 0.85
            local hiltOffX = swordSize * 0.35
            local hiltOffY = swordSize * 0.35
            local orbitR = GS.CELL * 0.15
            local restAngle = math.rad(-55)
            local swingStart = dirAngle - math.rad(70)
            local swingEnd   = dirAngle + math.rad(60)

            local curAngle, swordAlpha, swordRot

            if t < 0.1 then
                local st = t / 0.1
                local ease = st * st
                curAngle = restAngle + (swingStart - restAngle) * ease
                swordAlpha = 0.7 + 0.3 * st
            elseif t < 0.32 then
                local st = (t - 0.1) / 0.22
                local ease = st * st * (3 - 2 * st)
                curAngle = swingStart + (swingEnd - swingStart) * ease
                swordAlpha = 1.0
            else
                local st = (t - 0.32) / 0.23
                curAngle = swingEnd
                swordAlpha = 1.0 - st * st
            end

            local hiltX = fpx + math.cos(curAngle) * orbitR
            local hiltY = fpy + math.sin(curAngle) * orbitR
            swordRot = curAngle + math.rad(135)

            if t >= 0.1 and t < 0.4 then
                local st = math.min(1.0, (t - 0.1) / 0.22)
                local ghostCount = 5
                for gi = ghostCount, 1, -1 do
                    local delay = gi * 0.035
                    local gt = math.max(0, st - delay / 0.22)
                    if gt > 0 then
                        local gEase = gt * gt * (3 - 2 * gt)
                        local gAngle = swingStart + (swingEnd - swingStart) * gEase
                        local gx = fpx + math.cos(gAngle) * orbitR
                        local gy = fpy + math.sin(gAngle) * orbitR
                        local gRot = gAngle + math.rad(135)
                        local gAlpha = (0.22 - gi * 0.04)

                        nvgSave(vg)
                        nvgTranslate(vg, gx, gy)
                        nvgRotate(vg, gRot)
                        local ghostPaint = nvgImagePattern(vg,
                            -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                            swordSize, swordSize,
                            0, meleeImg, math.max(0.02, gAlpha))
                        nvgBeginPath(vg)
                        nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                        nvgFillPaint(vg, ghostPaint)
                        nvgFill(vg)
                        nvgRestore(vg)
                    end
                end
            end

            nvgSave(vg)
            nvgTranslate(vg, hiltX, hiltY)
            nvgRotate(vg, swordRot)

            local imgPaint = nvgImagePattern(vg,
                -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                swordSize, swordSize,
                0, meleeImg, swordAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)

            nvgRestore(vg)
        end

        -- 弧形斩击光痕
        if t >= 0.15 and t < 0.42 then
            local st = (t - 0.15) / 0.27
            local alpha = math.floor(220 * (1 - st))
            local arcR = GS.CELL * 0.55
            local swingStart = dirAngle - math.rad(70)
            local swingEnd   = dirAngle + math.rad(60)
            local trailEase = math.min(1, st * 1.3)
            local trailEnd = swingStart + (swingEnd - swingStart) * trailEase
            local trailStart = swingStart + (swingEnd - swingStart) * math.max(0, trailEase - 0.4)

            nvgSave(vg)
            nvgTranslate(vg, fpx, fpy)

            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, alpha))
            nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.08 * (1 - st * 0.6)))
            nvgStroke(vg)

            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(180, 220, 255, math.floor(alpha * 0.35)))
            nvgStrokeWidth(vg, math.max(4, GS.CELL * 0.18 * (1 - st * 0.5)))
            nvgStroke(vg)

            nvgRestore(vg)
        end

        end -- elseif melee

        -- 冲击波（近战和弓箭专用，法杖和小宙斯有自己的爆炸特效）
        if not isStaffAtk and not isLittleZeusAtk and t >= 0.2 and t < 0.65 then
            local wt = (t - 0.2) / 0.45
            local waveR = r * 0.3 + r * 0.9 * wt
            local alpha = math.floor(180 * (1 - wt))
            local ringW = math.max(1.5, GS.CELL * 0.06 * (1 - wt * 0.7))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(200, 30, 30, alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 击中闪光
        if t >= 0.2 and t < 0.4 then
            local ft = (t - 0.2) / 0.2
            local flashR = r * 0.6 * (0.5 + ft * 0.5)
            local alpha = math.floor(220 * (1 - ft))
            local flashGrad = nvgRadialGradient(vg, px, py, 0, flashR,
                nvgRGBA(255, 200, 200, alpha),
                nvgRGBA(200, 30, 30, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)
        end

        -- 飞溅碎片
        if t >= 0.2 and t < 0.6 then
            local pt = (t - 0.2) / 0.4
            local alpha = math.floor(200 * (1 - pt))
            local sparkCount = 6
            for i = 1, sparkCount do
                local angle = (i / sparkCount) * math.pi * 2 + dirAngle
                local dist = r * 0.2 + r * 0.8 * pt
                local sx = px + math.cos(angle) * dist
                local sy = py + math.sin(angle) * dist
                local sparkSize = math.max(1, GS.CELL * 0.04 * (1 - pt))
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, sparkSize)
                nvgFillColor(vg, nvgRGBA(220, 60, 60, alpha))
                nvgFill(vg)
            end
        end
        nvgRestore(vg) -- 对应循环开头的 nvgSave，隔离每个特效的渲染状态
    end
end

-- ====================================================================
-- 绘制：强击系技能特效（白色/蓝色/金琥珀色，4阶段动画，0.8秒）
-- ====================================================================
function M.drawStrikeEffects()
    local vg = M.vg
    for _, e in ipairs(GS.strikeEffects) do
        local px = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local fpx = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fpy = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2

        local t = safeProgress(e.timer, e.duration)
        local r = GS.CELL * 0.6
        local dirAngle = math.atan(py - fpy, px - fpx)

        -- 根据技能ID选择颜色方案
        local cMain, cDark, cBright, cTint, cParticle, cCore
        if e.skillId == "strike" then
            -- 强击：白色系
            cMain   = {255, 255, 255}   -- 主色（纯白）
            cDark   = {200, 210, 230}   -- 暗部（冷白）
            cBright = {255, 250, 240}   -- 亮部（暖白）
            cTint   = {230, 240, 255}   -- 色调叠加（冰白）
            cParticle = {240, 245, 255} -- 粒子（亮白）
            cCore   = {255, 255, 255}   -- 核心高光
        elseif e.skillId == "sup_stk" then
            -- 超强击：蓝色系
            cMain   = {80, 160, 255}    -- 主色（亮蓝）
            cDark   = {40, 100, 200}    -- 暗部（深蓝）
            cBright = {140, 200, 255}   -- 亮部（浅蓝）
            cTint   = {60, 130, 240}    -- 色调叠加
            cParticle = {100, 180, 255} -- 粒子
            cCore   = {180, 220, 255}   -- 核心高光
        else
            -- 碎星：金琥珀色（原版配色）
            cMain   = {255, 200, 80}    -- 主色
            cDark   = {220, 160, 60}    -- 暗部
            cBright = {255, 220, 100}   -- 亮部
            cTint   = {255, 180, 40}    -- 色调叠加
            cParticle = {255, 220, 100} -- 粒子
            cCore   = {255, 240, 180}   -- 核心高光
        end

        -- ============================================================
        -- 阶段1：蓄力光环 + 聚能粒子 (t: 0.0 - 0.18)
        -- ============================================================
        if t < 0.18 then
            local ct = t / 0.18
            -- 扩散光环
            local auraR = GS.CELL * 0.3 + GS.CELL * 0.5 * ct
            local auraAlpha = math.floor(180 * ct)
            local auraGrad = nvgRadialGradient(vg, fpx, fpy, 0, auraR,
                nvgRGBA(cMain[1], cMain[2], cMain[3], auraAlpha),
                nvgRGBA(cDark[1], cDark[2], cDark[3], 0))
            nvgBeginPath(vg)
            nvgCircle(vg, fpx, fpy, auraR)
            nvgFillPaint(vg, auraGrad)
            nvgFill(vg)

            -- 6颗聚能粒子向攻击者汇聚
            for i = 1, 6 do
                local angle = (i / 6) * math.pi * 2 + 0.5
                local startDist = GS.CELL * 1.2
                local dist = startDist * (1 - ct * ct)
                local px2 = fpx + math.cos(angle) * dist
                local py2 = fpy + math.sin(angle) * dist
                local pAlpha = math.floor(200 * ct)
                local pSize = math.max(1.5, GS.CELL * 0.04)
                nvgBeginPath(vg)
                nvgCircle(vg, px2, py2, pSize)
                nvgFillColor(vg, nvgRGBA(cParticle[1], cParticle[2], cParticle[3], pAlpha))
                nvgFill(vg)
            end
        end

        -- ============================================================
        -- 阶段2：大号金色剑挥砍 + 残影（旋转轴心在剑柄）
        -- ============================================================
        if M.swordImage ~= -1 and t >= 0.05 and t < 0.58 then
            local swordSize = GS.CELL * 1.1
            local hiltOffX = swordSize * 0.35
            local hiltOffY = swordSize * 0.35
            local orbitR = GS.CELL * 0.15
            local restAngle = math.rad(-55)
            local swingStart = dirAngle - math.rad(90)
            local swingEnd   = dirAngle + math.rad(80)

            local swingT = (t - 0.05) / 0.53
            local curAngle, swordAlpha

            if swingT < 0.12 then
                local st = swingT / 0.12
                local ease = st * st
                curAngle = restAngle + (swingStart - restAngle) * ease
                swordAlpha = 0.7 + 0.3 * st
            elseif swingT < 0.55 then
                local st = (swingT - 0.12) / 0.43
                local ease = st * st * (3 - 2 * st)
                curAngle = swingStart + (swingEnd - swingStart) * ease
                swordAlpha = 1.0
            else
                local st = (swingT - 0.55) / 0.45
                curAngle = swingEnd
                swordAlpha = 1.0 - st * st
            end

            local hiltX = fpx + math.cos(curAngle) * orbitR
            local hiltY = fpy + math.sin(curAngle) * orbitR
            local swordRot = curAngle + math.rad(135)

            -- 7个金色残影
            if swingT >= 0.12 and swingT < 0.65 then
                local st = math.min(1.0, (swingT - 0.12) / 0.43)
                local ghostCount = 7
                for gi = ghostCount, 1, -1 do
                    local delay = gi * 0.03
                    local gt = math.max(0, st - delay / 0.43)
                    if gt > 0 then
                        local gEase = gt * gt * (3 - 2 * gt)
                        local gAngle = swingStart + (swingEnd - swingStart) * gEase
                        local gx = fpx + math.cos(gAngle) * orbitR
                        local gy = fpy + math.sin(gAngle) * orbitR
                        local gRot = gAngle + math.rad(135)
                        local gAlpha = (0.24 - gi * 0.03)

                        nvgSave(vg)
                        nvgTranslate(vg, gx, gy)
                        nvgRotate(vg, gRot)
                        local ghostPaint = nvgImagePattern(vg,
                            -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                            swordSize, swordSize,
                            0, M.swordImage, math.max(0.02, gAlpha))
                        nvgBeginPath(vg)
                        nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                        nvgFillPaint(vg, ghostPaint)
                        nvgFill(vg)

                        -- 剑刃发光（沿刃身的窄长方形）
                        local gbAlpha = math.floor(50 * gAlpha)
                        if gbAlpha > 1 then
                            local bladeLen2 = swordSize * 0.82
                            local bladeW2 = swordSize * 0.07
                            local bmx = -swordSize * 0.30
                            local bmy = -swordSize * 0.30
                            nvgSave(vg)
                            nvgTranslate(vg, bmx, bmy)
                            nvgRotate(vg, math.rad(-135) + math.rad(90))
                            nvgBeginPath(vg)
                            nvgRoundedRect(vg, -bladeW2 * 2.5, -bladeLen2 / 2, bladeW2 * 5, bladeLen2, bladeW2 * 2)
                            nvgFillColor(vg, nvgRGBA(cTint[1], cTint[2], cTint[3], gbAlpha))
                            nvgFill(vg)
                            nvgRestore(vg)
                        end

                        nvgRestore(vg)
                    end
                end
            end

            -- 主剑
            nvgSave(vg)
            nvgTranslate(vg, hiltX, hiltY)
            nvgRotate(vg, swordRot)

            local imgPaint = nvgImagePattern(vg,
                -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                swordSize, swordSize,
                0, M.swordImage, swordAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)

            -- 剑刃发光（沿刃身的窄长方形）
            local bladeAlpha = math.floor(70 * swordAlpha)
            if bladeAlpha > 1 then
                local bladeLen2 = swordSize * 0.82
                local bladeW2 = swordSize * 0.07
                local bmx = -swordSize * 0.30
                local bmy = -swordSize * 0.30
                nvgSave(vg)
                nvgTranslate(vg, bmx, bmy)
                nvgRotate(vg, math.rad(-135) + math.rad(90))
                -- 外层柔光
                nvgBeginPath(vg)
                nvgRoundedRect(vg, -bladeW2 * 3, -bladeLen2 / 2, bladeW2 * 6, bladeLen2, bladeW2 * 2.5)
                nvgFillColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], math.floor(bladeAlpha * 0.45)))
                nvgFill(vg)
                -- 内层亮芯
                nvgBeginPath(vg)
                nvgRoundedRect(vg, -bladeW2, -bladeLen2 / 2, bladeW2 * 2, bladeLen2, bladeW2 * 0.8)
                nvgFillColor(vg, nvgRGBA(cCore[1], cCore[2], cCore[3], bladeAlpha))
                nvgFill(vg)
                nvgRestore(vg)
            end

            nvgRestore(vg)
        end

        -- ============================================================
        -- 金色弧形斩击光痕 (t: 0.18 - 0.48)
        -- ============================================================
        if t >= 0.18 and t < 0.48 then
            local st = (t - 0.18) / 0.30
            local alpha = math.floor(240 * (1 - st))
            local arcR = GS.CELL * 0.65
            local swingStart = dirAngle - math.rad(90)
            local swingEnd   = dirAngle + math.rad(80)
            local trailEase = math.min(1, st * 1.3)
            local trailEnd = swingStart + (swingEnd - swingStart) * trailEase
            local trailStart = swingStart + (swingEnd - swingStart) * math.max(0, trailEase - 0.4)

            nvgSave(vg)
            nvgTranslate(vg, fpx, fpy)

            -- 外发光（粗）
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(cDark[1], cDark[2], cDark[3], math.floor(alpha * 0.25)))
            nvgStrokeWidth(vg, math.max(5, GS.CELL * 0.25 * (1 - st * 0.5)))
            nvgStroke(vg)

            -- 主光痕
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], alpha))
            nvgStrokeWidth(vg, math.max(2.5, GS.CELL * 0.14 * (1 - st * 0.6)))
            nvgStroke(vg)

            -- 亮核心
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(cCore[1], cCore[2], cCore[3], math.floor(alpha * 0.5)))
            nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.04))
            nvgStroke(vg)

            nvgRestore(vg)
        end

        -- ============================================================
        -- 阶段3：冲击 - 大号闪光 (t: 0.30 - 0.50)
        -- ============================================================
        if t >= 0.30 and t < 0.50 then
            local ft = (t - 0.30) / 0.20
            local flashR = r * 0.9 * (0.5 + ft * 0.5)
            local alpha = math.floor(240 * (1 - ft))
            local flashGrad = nvgRadialGradient(vg, px, py, 0, flashR,
                nvgRGBA(cCore[1], cCore[2], cCore[3], alpha),
                nvgRGBA(cDark[1], cDark[2], cDark[3], 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)
        end

        -- 双层冲击波环
        -- 内环 (t: 0.30 - 0.62)
        if t >= 0.30 and t < 0.62 then
            local wt = (t - 0.30) / 0.32
            local waveR = r * 0.3 + r * 1.2 * wt
            local alpha = math.floor(220 * (1 - wt))
            local ringW = math.max(2, GS.CELL * 0.08 * (1 - wt * 0.6))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 外环 (t: 0.35 - 0.65)
        if t >= 0.35 and t < 0.65 then
            local wt = (t - 0.35) / 0.30
            local waveR = r * 0.2 + r * 1.5 * wt
            local alpha = math.floor(160 * (1 - wt))
            local ringW = math.max(1.5, GS.CELL * 0.05 * (1 - wt * 0.7))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(cDark[1], cDark[2], cDark[3], alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 地面裂纹放射线 (t: 0.32 - 0.60)
        if t >= 0.32 and t < 0.60 then
            local gt = (t - 0.32) / 0.28
            local lineLen = GS.CELL * 0.7 * math.min(1, gt * 1.5)
            local alpha = math.floor(180 * (1 - gt))
            local lineW = math.max(1, 3 * (1 - gt))
            for i = 1, 8 do
                local angle = (i / 8) * math.pi * 2 + dirAngle * 0.3
                local ex = px + math.cos(angle) * lineLen
                local ey = py + math.sin(angle) * lineLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, py)
                nvgLineTo(vg, ex, ey)
                nvgStrokeColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], alpha))
                nvgStrokeWidth(vg, lineW)
                nvgStroke(vg)
            end
        end

        -- ============================================================
        -- 阶段4：余波 - 带重力碎片 (t: 0.35 - 0.70)
        -- ============================================================
        if t >= 0.35 and t < 0.70 then
            local pt = (t - 0.35) / 0.35
            local alpha = math.floor(220 * (1 - pt))
            for i = 1, 8 do
                local angle = (i / 8) * math.pi * 2 + dirAngle
                local dist = r * 0.2 + r * 1.2 * pt
                local gravity = GS.CELL * 0.3 * pt * pt
                local sx2 = px + math.cos(angle) * dist
                local sy2 = py + math.sin(angle) * dist + gravity
                local sparkSize = math.max(1.5, GS.CELL * 0.055 * (1 - pt * 0.5))
                nvgBeginPath(vg)
                nvgCircle(vg, sx2, sy2, sparkSize)
                nvgFillColor(vg, nvgRGBA(cBright[1], cBright[2], cBright[3], alpha))
                nvgFill(vg)
            end
        end

        -- 残留地面余辉 (t: 0.50 - 0.80)
        if t >= 0.50 and t < 0.80 then
            local gt2 = (t - 0.50) / 0.30
            local glowAlpha = math.floor(60 * (1 - gt2))
            local glowR = GS.CELL * 0.5
            local glowGrad = nvgRadialGradient(vg, px, py, 0, glowR,
                nvgRGBA(cMain[1], cMain[2], cMain[3], glowAlpha),
                nvgRGBA(cDark[1], cDark[2], cDark[3], 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：祝福术特效（神圣金白色，锤挥砍+十字光芒+神圣冲击波，0.8秒）
-- ====================================================================
function M.drawBlessEffects()
    local vg = M.vg
    local weaponImg = (M.maceImage and M.maceImage ~= -1) and M.maceImage or M.swordImage

    for _, e in ipairs(GS.blessEffects) do
        local enhanced = e.enhanced  -- 超度=true, 祝福术=false
        local px = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local fpx = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fpy = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2

        local t = safeProgress(e.timer, e.duration)
        -- 技能扩展词缀：每层放大 25%
        local rbScale = 1.0 + (e.rangeBonus or 0) * 0.25
        local r = GS.CELL * (enhanced and 0.8 or 0.6) * rbScale
        local dirAngle = math.atan(py - fpy, px - fpx)

        -- 色系：超度更亮更白，偏神圣纯白光
        local cMain, cDark, cBright, cTint, cParticle, cCore
        if enhanced then
            cMain     = {255, 240, 160}   -- 主色（亮圣金）
            cDark     = {220, 190, 80}    -- 暗部
            cBright   = {255, 252, 220}   -- 亮部（近纯白）
            cTint     = {255, 230, 120}   -- 色调叠加
            cParticle = {255, 248, 200}   -- 粒子（白金）
            cCore     = {255, 255, 245}   -- 核心高光（几乎纯白）
        else
            cMain     = {255, 220, 100}
            cDark     = {200, 170, 60}
            cBright   = {255, 245, 180}
            cTint     = {255, 200, 80}
            cParticle = {255, 240, 160}
            cCore     = {255, 255, 230}
        end

        -- ============================================================
        -- 阶段1：神圣蓄力光环 + 十字聚能 (t: 0.0 - 0.18)
        -- ============================================================
        if t < 0.18 then
            local ct = t / 0.18
            -- 扩散神圣光环（超度更大，技能扩展放大）
            local auraR = (GS.CELL * (enhanced and 0.4 or 0.3) + GS.CELL * (enhanced and 0.7 or 0.5) * ct) * rbScale
            local auraAlpha = math.floor((enhanced and 220 or 180) * ct)
            local auraGrad = nvgRadialGradient(vg, fpx, fpy, 0, auraR,
                nvgRGBA(cMain[1], cMain[2], cMain[3], auraAlpha),
                nvgRGBA(cDark[1], cDark[2], cDark[3], 0))
            nvgBeginPath(vg)
            nvgCircle(vg, fpx, fpy, auraR)
            nvgFillPaint(vg, auraGrad)
            nvgFill(vg)

            -- 超度：额外一层外扩光晕
            if enhanced then
                local outerR = auraR * 1.4
                local outerGrad = nvgRadialGradient(vg, fpx, fpy, auraR * 0.6, outerR,
                    nvgRGBA(cCore[1], cCore[2], cCore[3], math.floor(80 * ct)),
                    nvgRGBA(cDark[1], cDark[2], cDark[3], 0))
                nvgBeginPath(vg)
                nvgCircle(vg, fpx, fpy, outerR)
                nvgFillPaint(vg, outerGrad)
                nvgFill(vg)
            end

            -- 聚能粒子（超度8颗含对角线，祝福术4颗十字）
            local pCount = enhanced and 8 or 4
            for i = 1, pCount do
                local angle = (i - 1) * (math.pi * 2 / pCount)
                local startDist = GS.CELL * (enhanced and 1.5 or 1.2) * rbScale
                local dist = startDist * (1 - ct * ct)
                local px2 = fpx + math.cos(angle) * dist
                local py2 = fpy + math.sin(angle) * dist
                local pAlpha = math.floor((enhanced and 240 or 220) * ct)
                local pSize = math.max(2, GS.CELL * (enhanced and 0.065 or 0.05))
                nvgBeginPath(vg)
                nvgCircle(vg, px2, py2, pSize)
                nvgFillColor(vg, nvgRGBA(cCore[1], cCore[2], cCore[3], pAlpha))
                nvgFill(vg)
            end
        end

        -- ============================================================
        -- 阶段2：锤挥砍 + 金色残影（旋转轴心在锤柄）
        -- ============================================================
        if weaponImg ~= -1 and t >= 0.05 and t < 0.58 then
            local swordSize = GS.CELL * (enhanced and 1.35 or 1.1) * rbScale
            local hiltOffX = swordSize * 0.35
            local hiltOffY = swordSize * 0.35
            local orbitR = GS.CELL * 0.15 * rbScale
            local restAngle = math.rad(-55)
            local swingStart = dirAngle - math.rad(90)
            local swingEnd   = dirAngle + math.rad(80)

            local swingT = (t - 0.05) / 0.53
            local curAngle, swordAlpha

            if swingT < 0.12 then
                local st = swingT / 0.12
                local ease = st * st
                curAngle = restAngle + (swingStart - restAngle) * ease
                swordAlpha = 0.7 + 0.3 * st
            elseif swingT < 0.55 then
                local st = (swingT - 0.12) / 0.43
                local ease = st * st * (3 - 2 * st)
                curAngle = swingStart + (swingEnd - swingStart) * ease
                swordAlpha = 1.0
            else
                local st = (swingT - 0.55) / 0.45
                curAngle = swingEnd
                swordAlpha = 1.0 - st * st
            end

            local hiltX = fpx + math.cos(curAngle) * orbitR
            local hiltY = fpy + math.sin(curAngle) * orbitR
            local swordRot = curAngle + math.rad(135)

            -- 残影（超度10个更密集，祝福术7个）
            local ghostCount = enhanced and 10 or 7
            if swingT >= 0.12 and swingT < 0.65 then
                local st = math.min(1.0, (swingT - 0.12) / 0.43)
                for gi = ghostCount, 1, -1 do
                    local delay = gi * (enhanced and 0.022 or 0.03)
                    local gt = math.max(0, st - delay / 0.43)
                    if gt > 0 then
                        local gEase = gt * gt * (3 - 2 * gt)
                        local gAngle = swingStart + (swingEnd - swingStart) * gEase
                        local gx = fpx + math.cos(gAngle) * orbitR
                        local gy = fpy + math.sin(gAngle) * orbitR
                        local gRot = gAngle + math.rad(135)
                        local gAlpha = enhanced and (0.32 - gi * 0.028) or (0.24 - gi * 0.03)

                        nvgSave(vg)
                        nvgTranslate(vg, gx, gy)
                        nvgRotate(vg, gRot)
                        local ghostPaint = nvgImagePattern(vg,
                            -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                            swordSize, swordSize,
                            0, weaponImg, math.max(0.02, gAlpha))
                        nvgBeginPath(vg)
                        nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                        nvgFillPaint(vg, ghostPaint)
                        nvgFill(vg)

                        -- 神圣色调叠加
                        nvgBeginPath(vg)
                        nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                        nvgFillColor(vg, nvgRGBA(cTint[1], cTint[2], cTint[3], math.floor((enhanced and 90 or 70) * gAlpha)))
                        nvgFill(vg)

                        nvgRestore(vg)
                    end
                end
            end

            -- 主锤
            nvgSave(vg)
            nvgTranslate(vg, hiltX, hiltY)
            nvgRotate(vg, swordRot)

            local imgPaint = nvgImagePattern(vg,
                -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                swordSize, swordSize,
                0, weaponImg, swordAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)

            -- 主锤神圣色调叠加
            nvgBeginPath(vg)
            nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
            nvgFillColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], math.floor((enhanced and 110 or 90) * swordAlpha)))
            nvgFill(vg)

            nvgRestore(vg)
        end

        -- ============================================================
        -- 神圣弧形光痕 (t: 0.18 - 0.48)
        -- ============================================================
        if t >= 0.18 and t < 0.48 then
            local st = (t - 0.18) / 0.30
            local alpha = math.floor((enhanced and 255 or 240) * (1 - st))
            local arcR = GS.CELL * (enhanced and 0.85 or 0.65) * rbScale
            local swingStart = dirAngle - math.rad(90)
            local swingEnd   = dirAngle + math.rad(80)
            local trailEase = math.min(1, st * 1.3)
            local trailEnd = swingStart + (swingEnd - swingStart) * trailEase
            local trailStart = swingStart + (swingEnd - swingStart) * math.max(0, trailEase - 0.4)

            nvgSave(vg)
            nvgTranslate(vg, fpx, fpy)

            -- 外发光（粗）
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(cDark[1], cDark[2], cDark[3], math.floor(alpha * 0.25)))
            nvgStrokeWidth(vg, math.max(5, GS.CELL * (enhanced and 0.32 or 0.25) * (1 - st * 0.5)))
            nvgStroke(vg)

            -- 主光痕
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], alpha))
            nvgStrokeWidth(vg, math.max(2.5, GS.CELL * (enhanced and 0.18 or 0.14) * (1 - st * 0.6)))
            nvgStroke(vg)

            -- 亮核心
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, arcR, trailStart, trailEnd, 1)
            nvgStrokeColor(vg, nvgRGBA(cCore[1], cCore[2], cCore[3], math.floor(alpha * (enhanced and 0.65 or 0.5))))
            nvgStrokeWidth(vg, math.max(1, GS.CELL * (enhanced and 0.06 or 0.04)))
            nvgStroke(vg)

            nvgRestore(vg)
        end

        -- ============================================================
        -- 阶段3：神圣冲击 - 十字闪光 (t: 0.30 - 0.55)
        -- ============================================================
        if t >= 0.30 and t < 0.55 then
            local ft = (t - 0.30) / 0.25
            -- 中心闪光（超度更大）
            local flashR = r * (enhanced and 1.1 or 0.9) * (0.5 + ft * 0.5)
            local alpha = math.floor((enhanced and 255 or 240) * (1 - ft))
            local flashGrad = nvgRadialGradient(vg, px, py, 0, flashR,
                nvgRGBA(cCore[1], cCore[2], cCore[3], alpha),
                nvgRGBA(cDark[1], cDark[2], cDark[3], 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)

            -- 十字光芒（超度8方向，祝福术4方向）
            local crossCount = enhanced and 8 or 4
            local crossLen = GS.CELL * (enhanced and 1.2 or 0.8) * rbScale * (0.3 + ft * 0.7)
            local crossW = math.max(2, GS.CELL * (enhanced and 0.13 or 0.1) * (1 - ft * 0.6))
            local crossAlpha = math.floor((enhanced and 240 or 200) * (1 - ft))
            for i = 1, crossCount do
                local angle = (i - 1) * (math.pi * 2 / crossCount)
                local ex = px + math.cos(angle) * crossLen
                local ey = py + math.sin(angle) * crossLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, py)
                nvgLineTo(vg, ex, ey)
                nvgStrokeColor(vg, nvgRGBA(cCore[1], cCore[2], cCore[3], crossAlpha))
                nvgStrokeWidth(vg, crossW)
                nvgStroke(vg)
            end
        end

        -- 神圣冲击波环
        -- 内环 (t: 0.30 - 0.62)
        if t >= 0.30 and t < 0.62 then
            local wt = (t - 0.30) / 0.32
            local waveR = r * 0.3 + r * (enhanced and 1.5 or 1.2) * wt
            local alpha = math.floor((enhanced and 240 or 220) * (1 - wt))
            local ringW = math.max(2, GS.CELL * (enhanced and 0.11 or 0.08) * (1 - wt * 0.6))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 外环 (t: 0.35 - 0.65)
        if t >= 0.35 and t < 0.65 then
            local wt = (t - 0.35) / 0.30
            local waveR = r * 0.2 + r * (enhanced and 1.8 or 1.5) * wt
            local alpha = math.floor((enhanced and 200 or 160) * (1 - wt))
            local ringW = math.max(1.5, GS.CELL * (enhanced and 0.07 or 0.05) * (1 - wt * 0.7))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(cDark[1], cDark[2], cDark[3], alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 超度专属：第三层冲击波 (t: 0.38 - 0.70)
        if enhanced and t >= 0.38 and t < 0.70 then
            local wt = (t - 0.38) / 0.32
            local waveR = r * 0.1 + r * 2.1 * wt
            local alpha = math.floor(120 * (1 - wt))
            local ringW = math.max(1, GS.CELL * 0.04 * (1 - wt * 0.8))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(cCore[1], cCore[2], cCore[3], alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 超度专属：地面裂纹放射线 (t: 0.32 - 0.58)
        if enhanced and t >= 0.32 and t < 0.58 then
            local gt = (t - 0.32) / 0.26
            local lineLen = GS.CELL * 0.9 * rbScale * math.min(1, gt * 1.5)
            local alpha = math.floor(160 * (1 - gt))
            local lineW = math.max(1.5, 3.5 * (1 - gt))
            for i = 1, 8 do
                local angle = (i / 8) * math.pi * 2 + dirAngle * 0.3
                local ex = px + math.cos(angle) * lineLen
                local ey = py + math.sin(angle) * lineLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, py)
                nvgLineTo(vg, ex, ey)
                nvgStrokeColor(vg, nvgRGBA(cMain[1], cMain[2], cMain[3], alpha))
                nvgStrokeWidth(vg, lineW)
                nvgStroke(vg)
            end
        end

        -- ============================================================
        -- 阶段4：神圣余辉 - 金色光粒上升 (t: 0.35 - 0.75)
        -- ============================================================
        if t >= 0.35 and t < 0.75 then
            local pt = (t - 0.35) / 0.40
            local alpha = math.floor((enhanced and 230 or 200) * (1 - pt))
            local sparkCount = enhanced and 16 or 10
            for i = 1, sparkCount do
                local angle = (i / sparkCount) * math.pi * 2 + dirAngle
                local dist = r * 0.2 + r * (enhanced and 1.2 or 0.9) * pt
                local rise = GS.CELL * (enhanced and 0.7 or 0.5) * pt * pt
                local sx2 = px + math.cos(angle) * dist
                local sy2 = py + math.sin(angle) * dist - rise
                local sparkSize = math.max(1.5, GS.CELL * (enhanced and 0.065 or 0.05) * (1 - pt * 0.5))
                local sparkGrad = nvgRadialGradient(vg, sx2, sy2, 0, sparkSize * 2,
                    nvgRGBA(cBright[1], cBright[2], cBright[3], alpha),
                    nvgRGBA(cParticle[1], cParticle[2], cParticle[3], 0))
                nvgBeginPath(vg)
                nvgCircle(vg, sx2, sy2, sparkSize * 2)
                nvgFillPaint(vg, sparkGrad)
                nvgFill(vg)
            end
        end

        -- 超度专属：带重力碎片飞溅 (t: 0.40 - 0.72)
        if enhanced and t >= 0.40 and t < 0.72 then
            local dt2 = (t - 0.40) / 0.32
            local dAlpha = math.floor(200 * (1 - dt2))
            for i = 1, 8 do
                local angle = (i / 8) * math.pi * 2 + dirAngle
                local dist = r * 0.3 + r * 1.4 * dt2
                local gravity = GS.CELL * 0.35 * dt2 * dt2
                local sx2 = px + math.cos(angle) * dist
                local sy2 = py + math.sin(angle) * dist + gravity
                local sparkSize = math.max(1.5, GS.CELL * 0.055 * (1 - dt2 * 0.5))
                nvgBeginPath(vg)
                nvgCircle(vg, sx2, sy2, sparkSize)
                nvgFillColor(vg, nvgRGBA(cBright[1], cBright[2], cBright[3], dAlpha))
                nvgFill(vg)
            end
        end

        -- 残留地面圣光 (t: 0.50 - 0.85/0.95)
        local glowEnd = enhanced and 0.95 or 0.85
        if t >= 0.50 and t < glowEnd then
            local gt2 = (t - 0.50) / (glowEnd - 0.50)
            local glowAlpha = math.floor((enhanced and 90 or 70) * (1 - gt2))
            local glowR = GS.CELL * (enhanced and 0.7 or 0.55) * rbScale
            local glowGrad = nvgRadialGradient(vg, px, py, 0, glowR,
                nvgRGBA(cMain[1], cMain[2], cMain[3], glowAlpha),
                nvgRGBA(cDark[1], cDark[2], cDark[3], 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：劲射技能特效（翠绿色，弓蓄力+强力箭矢飞行+命中冲击，0.75秒）
-- ====================================================================
function M.drawPowerShotEffects()
    local vg = M.vg
    for _, e in ipairs(GS.powerShotEffects) do
        local px = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local fpx = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fpy = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2

        local t = safeProgress(e.timer, e.duration)
        local r = GS.CELL * 0.6
        local dirAngle = math.atan(py - fpy, px - fpx)
        local dist = math.sqrt((px - fpx) * (px - fpx) + (py - fpy) * (py - fpy))

        -- ============================================================
        -- 阶段1：蓄力光环 + 聚能粒子 (t: 0.0 - 0.20)
        -- ============================================================
        if t < 0.20 then
            local ct = t / 0.20
            -- 扩散绿色光环
            local auraR = GS.CELL * 0.25 + GS.CELL * 0.45 * ct
            local auraAlpha = math.floor(180 * ct)
            local auraGrad = nvgRadialGradient(vg, fpx, fpy, 0, auraR,
                nvgRGBA(120, 230, 80, auraAlpha),
                nvgRGBA(80, 180, 50, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, fpx, fpy, auraR)
            nvgFillPaint(vg, auraGrad)
            nvgFill(vg)

            -- 4颗风元素粒子向弓手汇聚
            for i = 1, 4 do
                local angle = (i / 4) * math.pi * 2 + t * 8
                local startDist = GS.CELL * 1.0
                local d = startDist * (1 - ct * ct)
                local px2 = fpx + math.cos(angle) * d
                local py2 = fpy + math.sin(angle) * d
                local pAlpha = math.floor(200 * ct)
                local pSize = math.max(1.5, GS.CELL * 0.04)
                nvgBeginPath(vg)
                nvgCircle(vg, px2, py2, pSize)
                nvgFillColor(vg, nvgRGBA(160, 240, 120, pAlpha))
                nvgFill(vg)
            end
        end

        -- ============================================================
        -- 阶段2：弓身拉弦蓄力 (t: 0.0 - 0.22)
        -- ============================================================
        if M.bowImage ~= -1 and t < 0.22 then
            local bowSize = GS.CELL * 0.85
            local bowRot = dirAngle + math.rad(135)
            local pullT = math.min(1, t / 0.18)
            local scaleX = 1.0 - pullT * 0.18
            local bowAlpha = t < 0.05 and (t / 0.05) or 1.0
            -- 蓄力时弓身发光
            local glowInt = pullT * pullT

            nvgSave(vg)
            nvgTranslate(vg, fpx, fpy)
            nvgRotate(vg, bowRot)
            nvgScale(vg, scaleX, 1.0)

            local bowPaint = nvgImagePattern(vg,
                -bowSize / 2, -bowSize / 2,
                bowSize, bowSize,
                0, M.bowImage, bowAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -bowSize / 2, -bowSize / 2, bowSize, bowSize)
            nvgFillPaint(vg, bowPaint)
            nvgFill(vg)

            -- 绿色蓄力叠加
            nvgBeginPath(vg)
            nvgRect(vg, -bowSize / 2, -bowSize / 2, bowSize, bowSize)
            nvgFillColor(vg, nvgRGBA(100, 220, 60, math.floor(80 * glowInt)))
            nvgFill(vg)

            -- 弦拉回
            if pullT > 0.3 then
                local stringPull = (pullT - 0.3) / 0.7 * bowSize * 0.25
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -bowSize * 0.3)
                nvgLineTo(vg, -stringPull, 0)
                nvgLineTo(vg, 0, bowSize * 0.3)
                nvgStrokeColor(vg, nvgRGBA(180, 240, 120, math.floor(220 * bowAlpha)))
                nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.025))
                nvgStroke(vg)
            end

            nvgRestore(vg)
        end

        -- ============================================================
        -- 阶段3：强力箭矢飞行 + 绿色气焰拖尾 (t: 0.18 - 0.50)
        -- ============================================================
        if t >= 0.18 and t < 0.50 then
            local arrowT = (t - 0.18) / 0.32
            local ease = arrowT * arrowT * (3 - 2 * arrowT)
            local ax = fpx + (px - fpx) * ease
            local ay = fpy + (py - fpy) * ease
            local arrowAlpha = arrowT < 0.85 and 255 or math.floor(255 * (1 - (arrowT - 0.85) / 0.15))

            -- 气焰拖尾（6段残影）
            for gi = 6, 1, -1 do
                local delay = gi * 0.04
                local gt = math.max(0, arrowT - delay / 0.32)
                if gt > 0 then
                    local gEase = gt * gt * (3 - 2 * gt)
                    local gx = fpx + (px - fpx) * gEase
                    local gy = fpy + (py - fpy) * gEase
                    local gAlpha = math.floor((180 - gi * 25) * (1 - arrowT * 0.5))
                    local trailR = math.max(1.5, GS.CELL * (0.08 - gi * 0.008))
                    nvgBeginPath(vg)
                    nvgCircle(vg, gx, gy, trailR)
                    nvgFillColor(vg, nvgRGBA(140, 240, 100, math.max(0, gAlpha)))
                    nvgFill(vg)
                end
            end

            -- 箭矢前方聚能光芒
            local flareR = GS.CELL * 0.12
            local flareGrad = nvgRadialGradient(vg, ax, ay, 0, flareR,
                nvgRGBA(200, 255, 160, arrowAlpha),
                nvgRGBA(120, 220, 80, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, ax, ay, flareR)
            nvgFillPaint(vg, flareGrad)
            nvgFill(vg)

            -- 箭矢本体
            if M.arrowImage ~= -1 then
                local arrowSize = GS.CELL * 0.6
                local imgBaseAngle = math.rad(135)
                local arrowRot = dirAngle - imgBaseAngle

                nvgSave(vg)
                nvgTranslate(vg, ax, ay)
                nvgRotate(vg, arrowRot)
                nvgGlobalAlpha(vg, arrowAlpha / 255)

                local aPaint = nvgImagePattern(vg,
                    -arrowSize * 0.5, -arrowSize * 0.5,
                    arrowSize, arrowSize, 0, M.arrowImage, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, -arrowSize * 0.5, -arrowSize * 0.5, arrowSize, arrowSize)
                nvgFillPaint(vg, aPaint)
                nvgFill(vg)

                -- 绿色强化叠加
                nvgBeginPath(vg)
                nvgRect(vg, -arrowSize * 0.5, -arrowSize * 0.5, arrowSize, arrowSize)
                nvgFillColor(vg, nvgRGBA(100, 230, 60, math.floor(90 * arrowAlpha / 255)))
                nvgFill(vg)

                nvgGlobalAlpha(vg, 1.0)
                nvgRestore(vg)
            else
                -- 无图片：程序化箭矢
                local arrowLen = GS.CELL * 0.4
                nvgSave(vg)
                nvgTranslate(vg, ax, ay)
                nvgRotate(vg, dirAngle)
                nvgBeginPath(vg)
                nvgMoveTo(vg, -arrowLen, 0)
                nvgLineTo(vg, arrowLen * 0.3, 0)
                nvgStrokeColor(vg, nvgRGBA(120, 220, 80, arrowAlpha))
                nvgStrokeWidth(vg, math.max(2.5, GS.CELL * 0.05))
                nvgStroke(vg)
                -- 箭头
                nvgBeginPath(vg)
                nvgMoveTo(vg, arrowLen * 0.3, 0)
                nvgLineTo(vg, arrowLen * 0.1, -GS.CELL * 0.06)
                nvgLineTo(vg, arrowLen * 0.1, GS.CELL * 0.06)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(160, 240, 100, arrowAlpha))
                nvgFill(vg)
                nvgRestore(vg)
            end
        end

        -- ============================================================
        -- 阶段4：命中闪光 + 冲击波 (t: 0.42 - 0.65)
        -- ============================================================
        if t >= 0.42 and t < 0.58 then
            local ft = (t - 0.42) / 0.16
            local flashR = r * 0.8 * (0.5 + ft * 0.5)
            local alpha = math.floor(230 * (1 - ft))
            local flashGrad = nvgRadialGradient(vg, px, py, 0, flashR,
                nvgRGBA(200, 255, 160, alpha),
                nvgRGBA(100, 200, 60, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)
        end

        -- 冲击波环 (t: 0.44 - 0.68)
        if t >= 0.44 and t < 0.68 then
            local wt = (t - 0.44) / 0.24
            local waveR = r * 0.25 + r * 1.2 * wt
            local alpha = math.floor(200 * (1 - wt))
            local ringW = math.max(2, GS.CELL * 0.07 * (1 - wt * 0.6))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(120, 230, 80, alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 方向性风刃线 (t: 0.44 - 0.62)
        if t >= 0.44 and t < 0.62 then
            local gt = (t - 0.44) / 0.18
            local lineLen = GS.CELL * 0.6 * math.min(1, gt * 1.5)
            local alpha = math.floor(180 * (1 - gt))
            local lineW = math.max(1, 2.5 * (1 - gt))
            -- 以箭矢飞行方向为主轴扩散
            for i = -2, 2 do
                local angle = dirAngle + math.rad(i * 25)
                local ex = px + math.cos(angle) * lineLen
                local ey = py + math.sin(angle) * lineLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, py)
                nvgLineTo(vg, ex, ey)
                nvgStrokeColor(vg, nvgRGBA(140, 230, 80, alpha))
                nvgStrokeWidth(vg, lineW)
                nvgStroke(vg)
            end
        end

        -- ============================================================
        -- 阶段5：余波碎片 (t: 0.48 - 0.72)
        -- ============================================================
        if t >= 0.48 and t < 0.72 then
            local pt = (t - 0.48) / 0.24
            local alpha = math.floor(200 * (1 - pt))
            for i = 1, 6 do
                local angle = (i / 6) * math.pi * 2 + dirAngle * 0.5
                local d = r * 0.15 + r * 1.0 * pt
                local gravity = GS.CELL * 0.2 * pt * pt
                local sx2 = px + math.cos(angle) * d
                local sy2 = py + math.sin(angle) * d + gravity
                local sparkSize = math.max(1.5, GS.CELL * 0.045 * (1 - pt * 0.5))
                nvgBeginPath(vg)
                nvgCircle(vg, sx2, sy2, sparkSize)
                nvgFillColor(vg, nvgRGBA(160, 240, 100, alpha))
                nvgFill(vg)
            end
        end

        -- 残留余辉 (t: 0.55 - 0.80)
        if t >= 0.55 and t < 0.80 then
            local gt2 = (t - 0.55) / 0.25
            local glowAlpha = math.floor(50 * (1 - gt2))
            local glowR = GS.CELL * 0.45
            local glowGrad = nvgRadialGradient(vg, px, py, 0, glowR,
                nvgRGBA(140, 230, 80, glowAlpha),
                nvgRGBA(100, 180, 60, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：晕眩射击专属特效（黄色主题，0.70秒）
-- ====================================================================
function M.drawStunShotEffects()
    local vg = M.vg
    for _, e in ipairs(GS.stunShotEffects) do
        local px = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local fpx = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fpy = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2

        local t = safeProgress(e.timer, e.duration)
        local r = GS.CELL * 0.6
        local dirAngle = math.atan(py - fpy, px - fpx)
        local dist = math.sqrt((px - fpx) * (px - fpx) + (py - fpy) * (py - fpy))

        -- ============================================================
        -- 阶段1：蓄力闪电光环 + 聚能粒子 (t: 0.0 - 0.20)
        -- ============================================================
        if t < 0.20 then
            local ct = t / 0.20
            -- 扩散黄色光环
            local auraR = GS.CELL * 0.25 + GS.CELL * 0.40 * ct
            local auraAlpha = math.floor(160 * ct)
            local auraGrad = nvgRadialGradient(vg, fpx, fpy, 0, auraR,
                nvgRGBA(240, 210, 60, auraAlpha),
                nvgRGBA(200, 170, 30, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, fpx, fpy, auraR)
            nvgFillPaint(vg, auraGrad)
            nvgFill(vg)

            -- 3颗电火花粒子向弓手汇聚
            for i = 1, 3 do
                local angle = (i / 3) * math.pi * 2 + t * 10
                local startDist = GS.CELL * 0.9
                local d = startDist * (1 - ct * ct)
                local px2 = fpx + math.cos(angle) * d
                local py2 = fpy + math.sin(angle) * d
                local pAlpha = math.floor(200 * ct)
                local pSize = math.max(1.5, GS.CELL * 0.04)
                nvgBeginPath(vg)
                nvgCircle(vg, px2, py2, pSize)
                nvgFillColor(vg, nvgRGBA(255, 240, 100, pAlpha))
                nvgFill(vg)
            end
        end

        -- ============================================================
        -- 阶段2：弓身拉弦蓄力（黄色电弧） (t: 0.0 - 0.22)
        -- ============================================================
        if M.bowImage ~= -1 and t < 0.22 then
            local bowSize = GS.CELL * 0.85
            local bowRot = dirAngle + math.rad(135)
            local pullT = math.min(1, t / 0.18)
            local scaleX = 1.0 - pullT * 0.15
            local bowAlpha = t < 0.05 and (t / 0.05) or 1.0
            local glowInt = pullT * pullT

            nvgSave(vg)
            nvgTranslate(vg, fpx, fpy)
            nvgRotate(vg, bowRot)
            nvgScale(vg, scaleX, 1.0)

            local bowPaint = nvgImagePattern(vg,
                -bowSize / 2, -bowSize / 2,
                bowSize, bowSize,
                0, M.bowImage, bowAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -bowSize / 2, -bowSize / 2, bowSize, bowSize)
            nvgFillPaint(vg, bowPaint)
            nvgFill(vg)

            -- 黄色电弧蓄力叠加
            nvgBeginPath(vg)
            nvgRect(vg, -bowSize / 2, -bowSize / 2, bowSize, bowSize)
            nvgFillColor(vg, nvgRGBA(240, 220, 60, math.floor(70 * glowInt)))
            nvgFill(vg)

            -- 弦拉回
            if pullT > 0.3 then
                local stringPull = (pullT - 0.3) / 0.7 * bowSize * 0.22
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -bowSize * 0.3)
                nvgLineTo(vg, -stringPull, 0)
                nvgLineTo(vg, 0, bowSize * 0.3)
                nvgStrokeColor(vg, nvgRGBA(255, 230, 80, math.floor(220 * bowAlpha)))
                nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.025))
                nvgStroke(vg)
            end

            nvgRestore(vg)
        end

        -- ============================================================
        -- 阶段3：箭矢飞行 + 黄色螺旋拖尾 (t: 0.18 - 0.48)
        -- ============================================================
        if t >= 0.18 and t < 0.48 then
            local arrowT = (t - 0.18) / 0.30
            local ease = arrowT * arrowT * (3 - 2 * arrowT)
            local ax = fpx + (px - fpx) * ease
            local ay = fpy + (py - fpy) * ease
            local arrowAlpha = arrowT < 0.85 and 255 or math.floor(255 * (1 - (arrowT - 0.85) / 0.15))

            -- 螺旋拖尾（6段残影，绕飞行轴螺旋）
            for gi = 6, 1, -1 do
                local delay = gi * 0.04
                local gt = math.max(0, arrowT - delay / 0.30)
                if gt > 0 then
                    local gEase = gt * gt * (3 - 2 * gt)
                    local gx = fpx + (px - fpx) * gEase
                    local gy = fpy + (py - fpy) * gEase
                    -- 螺旋偏移
                    local spiralAngle = gt * math.pi * 6 + gi * 1.0
                    local perpX = -math.sin(dirAngle)
                    local perpY = math.cos(dirAngle)
                    local spiralR = GS.CELL * 0.1 * (1 - gt * 0.5)
                    gx = gx + perpX * math.sin(spiralAngle) * spiralR
                    gy = gy + perpY * math.sin(spiralAngle) * spiralR
                    local gAlpha = math.floor((170 - gi * 22) * (1 - arrowT * 0.5))
                    local trailR = math.max(1.5, GS.CELL * (0.07 - gi * 0.007))
                    nvgBeginPath(vg)
                    nvgCircle(vg, gx, gy, trailR)
                    nvgFillColor(vg, nvgRGBA(255, 230, 60, math.max(0, gAlpha)))
                    nvgFill(vg)
                end
            end

            -- 箭矢前方聚能光芒
            local flareR = GS.CELL * 0.11
            local flareGrad = nvgRadialGradient(vg, ax, ay, 0, flareR,
                nvgRGBA(255, 240, 120, arrowAlpha),
                nvgRGBA(230, 200, 50, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, ax, ay, flareR)
            nvgFillPaint(vg, flareGrad)
            nvgFill(vg)

            -- 箭矢本体
            if M.arrowImage ~= -1 then
                local arrowSize = GS.CELL * 0.6
                local imgBaseAngle = math.rad(135)
                local arrowRot = dirAngle - imgBaseAngle

                nvgSave(vg)
                nvgTranslate(vg, ax, ay)
                nvgRotate(vg, arrowRot)
                nvgGlobalAlpha(vg, arrowAlpha / 255)

                local aPaint = nvgImagePattern(vg,
                    -arrowSize * 0.5, -arrowSize * 0.5,
                    arrowSize, arrowSize, 0, M.arrowImage, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, -arrowSize * 0.5, -arrowSize * 0.5, arrowSize, arrowSize)
                nvgFillPaint(vg, aPaint)
                nvgFill(vg)

                -- 黄色强化叠加
                nvgBeginPath(vg)
                nvgRect(vg, -arrowSize * 0.5, -arrowSize * 0.5, arrowSize, arrowSize)
                nvgFillColor(vg, nvgRGBA(240, 220, 40, math.floor(80 * arrowAlpha / 255)))
                nvgFill(vg)

                nvgGlobalAlpha(vg, 1.0)
                nvgRestore(vg)
            else
                -- 无图片：程序化箭矢
                local arrowLen = GS.CELL * 0.35
                nvgSave(vg)
                nvgTranslate(vg, ax, ay)
                nvgRotate(vg, dirAngle)
                nvgBeginPath(vg)
                nvgMoveTo(vg, -arrowLen, 0)
                nvgLineTo(vg, arrowLen * 0.3, 0)
                nvgStrokeColor(vg, nvgRGBA(240, 210, 50, arrowAlpha))
                nvgStrokeWidth(vg, math.max(2.5, GS.CELL * 0.05))
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, arrowLen * 0.3, 0)
                nvgLineTo(vg, arrowLen * 0.1, -GS.CELL * 0.06)
                nvgLineTo(vg, arrowLen * 0.1, GS.CELL * 0.06)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 240, 80, arrowAlpha))
                nvgFill(vg)
                nvgRestore(vg)
            end
        end

        -- ============================================================
        -- 阶段4：命中闪光 + 晕眩旋涡 (t: 0.40 - 0.65)
        -- ============================================================
        -- 命中闪光
        if t >= 0.40 and t < 0.55 then
            local ft = (t - 0.40) / 0.15
            local flashR = r * 0.7 * (0.5 + ft * 0.5)
            local alpha = math.floor(220 * (1 - ft))
            local flashGrad = nvgRadialGradient(vg, px, py, 0, flashR,
                nvgRGBA(255, 240, 120, alpha),
                nvgRGBA(220, 180, 40, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)
        end

        -- 冲击波环
        if t >= 0.42 and t < 0.62 then
            local wt = (t - 0.42) / 0.20
            local waveR = r * 0.2 + r * 1.0 * wt
            local alpha = math.floor(180 * (1 - wt))
            local ringW = math.max(2, GS.CELL * 0.06 * (1 - wt * 0.6))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, waveR)
            nvgStrokeColor(vg, nvgRGBA(240, 210, 60, alpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- 命中处旋涡（晕眩主题）
        if t >= 0.42 and t < 0.70 then
            local vt = (t - 0.42) / 0.28
            local vortexAlpha = math.floor(200 * (1 - vt * vt))
            local vortexY = py - GS.CELL * 0.3 - GS.CELL * 0.15 * vt
            -- 旋涡螺旋线
            local spiralSpeed = 12
            for arm = 1, 3 do
                local baseAngle = (arm / 3) * math.pi * 2 + t * spiralSpeed
                local segments = 8
                nvgBeginPath(vg)
                for si = 0, segments do
                    local st = si / segments
                    local sAngle = baseAngle + st * math.pi * 1.5
                    local sR = GS.CELL * 0.22 * (1 - st * 0.7) * (0.6 + 0.4 * (1 - vt))
                    local sx = px + math.cos(sAngle) * sR
                    local sy = vortexY + math.sin(sAngle) * sR * 0.45
                    if si == 0 then
                        nvgMoveTo(vg, sx, sy)
                    else
                        nvgLineTo(vg, sx, sy)
                    end
                end
                nvgStrokeColor(vg, nvgRGBA(255, 220, 50, vortexAlpha))
                nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.03 * (1 - vt * 0.5)))
                nvgStroke(vg)
            end
            -- 旋涡中心亮点
            local centerAlpha = math.floor(160 * (1 - vt))
            nvgBeginPath(vg)
            nvgCircle(vg, px, vortexY, GS.CELL * 0.06 * (1 - vt * 0.5))
            nvgFillColor(vg, nvgRGBA(255, 255, 180, centerAlpha))
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段5：电弧碎片 + 余辉 (t: 0.50 - 0.75)
        -- ============================================================
        if t >= 0.50 and t < 0.72 then
            local pt = (t - 0.50) / 0.22
            local alpha = math.floor(180 * (1 - pt))
            for i = 1, 5 do
                local angle = (i / 5) * math.pi * 2 + dirAngle * 0.5
                local d = r * 0.15 + r * 0.9 * pt
                local gravity = GS.CELL * 0.15 * pt * pt
                local sx2 = px + math.cos(angle) * d
                local sy2 = py + math.sin(angle) * d + gravity
                local sparkSize = math.max(1.5, GS.CELL * 0.04 * (1 - pt * 0.5))
                nvgBeginPath(vg)
                nvgCircle(vg, sx2, sy2, sparkSize)
                nvgFillColor(vg, nvgRGBA(255, 230, 80, alpha))
                nvgFill(vg)
            end
        end

        -- 残留余辉
        if t >= 0.55 and t < 0.78 then
            local gt2 = (t - 0.55) / 0.23
            local glowAlpha = math.floor(40 * (1 - gt2))
            local glowR = GS.CELL * 0.40
            local glowGrad = nvgRadialGradient(vg, px, py, 0, glowR,
                nvgRGBA(240, 210, 60, glowAlpha),
                nvgRGBA(200, 170, 30, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：狙击专属特效（绿色拖尾，力量感）
-- ====================================================================
function M.drawSnipeEffects()
    local vg = M.vg
    for _, e in ipairs(GS.snipeEffects) do
        local tx = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local ty = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local fx = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fy = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2

        local t = safeProgress(e.timer, e.duration)
        local dirAngle = math.atan(ty - fy, tx - fx)
        local dist = math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy))
        local dx = math.cos(dirAngle)
        local dy = math.sin(dirAngle)
        -- 垂直于弹道方向
        local nx = -dy
        local ny = dx

        -- ============================================================
        -- 阶段1：蓄力瞄准线 (t: 0.0 - 0.25)
        -- ============================================================
        if t < 0.25 then
            local ct = t / 0.25
            -- 瞄准线从射手延伸到目标
            local lineLen = dist * ct
            local endX = fx + dx * lineLen
            local endY = fy + dy * lineLen
            local lineAlpha = math.floor(180 * ct)
            nvgBeginPath(vg)
            nvgMoveTo(vg, fx, fy)
            nvgLineTo(vg, endX, endY)
            nvgStrokeColor(vg, nvgRGBA(80, 220, 100, lineAlpha))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 射手处聚能光点
            local glowR = GS.CELL * 0.3 * ct
            local glowGrad = nvgRadialGradient(vg, fx, fy, 0, glowR,
                nvgRGBA(120, 255, 130, math.floor(150 * ct)),
                nvgRGBA(80, 200, 80, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段2：弹道飞行 + 绿色拖尾 (t: 0.25 - 0.60)
        -- ============================================================
        if t >= 0.20 and t < 0.65 then
            local ft = (t - 0.20) / 0.40  -- 0→1 飞行进度
            ft = math.min(ft, 1.0)
            -- 弹头位置
            local headX = fx + (tx - fx) * ft
            local headY = fy + (ty - fy) * ft

            -- 拖尾：多条绿色线段，越靠后越淡
            local tailLen = math.min(ft, 0.4) * dist
            for i = 1, 12 do
                local tailT = (i - 1) / 12
                local tpx = headX - dx * tailLen * tailT
                local tpy = headY - dy * tailLen * tailT
                -- 拖尾宽度：头部粗尾部细
                local width = (1 - tailT) * GS.CELL * 0.15
                local alpha = math.floor(220 * (1 - tailT) * (1 - tailT))
                -- 两侧偏移制造宽度
                nvgBeginPath(vg)
                nvgMoveTo(vg, tpx + nx * width, tpy + ny * width)
                nvgLineTo(vg, tpx - nx * width, tpy - ny * width)
                nvgStrokeColor(vg, nvgRGBA(100, 255, 120, alpha))
                nvgStrokeWidth(vg, 2.5 * (1 - tailT * 0.7))
                nvgStroke(vg)
            end

            -- 弹头：明亮的绿色光球
            local headR = GS.CELL * 0.12
            local headGrad = nvgRadialGradient(vg, headX, headY, 0, headR,
                nvgRGBA(200, 255, 200, 255),
                nvgRGBA(80, 230, 100, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, headX, headY, headR)
            nvgFillPaint(vg, headGrad)
            nvgFill(vg)

            -- 弹头周围散射粒子
            for i = 1, 6 do
                local seed = i * 137.5
                local pAngle = seed + ft * 20
                local pDist = GS.CELL * 0.08 * math.sin(seed + ft * 10)
                local ppx = headX + math.cos(pAngle) * pDist - dx * GS.CELL * 0.05 * i
                local ppy = headY + math.sin(pAngle) * pDist - dy * GS.CELL * 0.05 * i
                local pAlpha = math.floor(180 * (1 - i / 7))
                nvgBeginPath(vg)
                nvgCircle(vg, ppx, ppy, 1.5)
                nvgFillColor(vg, nvgRGBA(140, 255, 160, pAlpha))
                nvgFill(vg)
            end
        end

        -- ============================================================
        -- 阶段3：命中冲击波 (t: 0.55 - 1.0)
        -- ============================================================
        if t >= 0.55 then
            local ht = (t - 0.55) / 0.45  -- 0→1
            -- 冲击波扩散环
            local impactR = GS.CELL * (0.15 + 0.55 * ht)
            local impactAlpha = math.floor(200 * (1 - ht))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, impactR)
            nvgStrokeColor(vg, nvgRGBA(100, 255, 130, impactAlpha))
            nvgStrokeWidth(vg, 3.0 * (1 - ht * 0.6))
            nvgStroke(vg)

            -- 内部绿色闪光
            local flashR = GS.CELL * 0.25 * (1 - ht)
            local flashGrad = nvgRadialGradient(vg, tx, ty, 0, flashR,
                nvgRGBA(180, 255, 180, math.floor(220 * (1 - ht))),
                nvgRGBA(100, 230, 100, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)

            -- 碎片粒子向外飞散
            for i = 1, 8 do
                local angle = (i / 8) * math.pi * 2 + dirAngle
                local fragDist = GS.CELL * 0.6 * ht * ht
                local fragX = tx + math.cos(angle) * fragDist
                local fragY = ty + math.sin(angle) * fragDist
                local fragAlpha = math.floor(180 * (1 - ht))
                local fragSize = 2.0 * (1 - ht * 0.5)
                nvgBeginPath(vg)
                nvgCircle(vg, fragX, fragY, fragSize)
                nvgFillColor(vg, nvgRGBA(120, 255, 140, fragAlpha))
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：旋风斩AOE特效（红色旋转刀风，0.7秒）
-- ====================================================================
function M.drawWhirlwindEffects()
    local vg = M.vg
    for _, e in ipairs(GS.whirlwindEffects) do
        local cx = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local cy = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local t = safeProgress(e.timer, e.duration)
        local R = GS.CELL * ((e.radius or 1) + 0.4)  -- 覆盖周围格的范围

        -- ============================================================
        -- 阶段1：中心聚气光环 (0.0 - 0.15)
        -- ============================================================
        if t < 0.15 then
            local ct = t / 0.15
            local auraR = GS.CELL * 0.2 + GS.CELL * 0.6 * ct
            local auraAlpha = math.floor(160 * ct)
            local auraGrad = nvgRadialGradient(vg, cx, cy, 0, auraR,
                nvgRGBA(230, 80, 60, auraAlpha),
                nvgRGBA(180, 50, 40, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, auraR)
            nvgFillPaint(vg, auraGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段2：旋转刀风弧线 + 单手剑旋转 (0.08 - 0.65)
        -- ============================================================
        if t >= 0.08 and t < 0.65 then
            local st = (t - 0.08) / 0.57
            -- 2圈旋转（720度）
            local baseAngle = st * math.pi * 4
            -- 扩展半径
            local curR = R * 0.3 + R * 0.7 * math.min(1, st * 1.5)
            -- 透明度：进入淡入，后期淡出
            local alpha
            if st < 0.2 then
                alpha = st / 0.2
            elseif st > 0.7 then
                alpha = (1 - st) / 0.3
            else
                alpha = 1.0
            end
            alpha = math.floor(alpha * 200)

            -- 3条旋转弧线（120度间隔）
            for blade = 0, 2 do
                local bladeOffset = blade * (math.pi * 2 / 3)
                local startAngle = baseAngle + bladeOffset
                local arcLen = math.rad(100)  -- 每条弧100度

                nvgSave(vg)
                nvgTranslate(vg, cx, cy)

                -- 主弧线（亮红色）
                nvgBeginPath(vg)
                nvgArc(vg, 0, 0, curR, startAngle, startAngle + arcLen, 1)
                nvgStrokeColor(vg, nvgRGBA(255, 100, 80, alpha))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.1 * (1 - st * 0.4)))
                nvgStroke(vg)

                -- 光晕弧线（柔和红色）
                nvgBeginPath(vg)
                nvgArc(vg, 0, 0, curR, startAngle, startAngle + arcLen, 1)
                nvgStrokeColor(vg, nvgRGBA(200, 60, 40, math.floor(alpha * 0.3)))
                nvgStrokeWidth(vg, math.max(4, GS.CELL * 0.22 * (1 - st * 0.3)))
                nvgStroke(vg)

                -- 刀风尖端亮点
                local tipAngle = startAngle + arcLen
                local tipX = math.cos(tipAngle) * curR
                local tipY = math.sin(tipAngle) * curR
                local tipR = math.max(2, GS.CELL * 0.08 * (1 - st * 0.5))
                local tipGrad = nvgRadialGradient(vg, tipX, tipY, 0, tipR,
                    nvgRGBA(255, 200, 180, alpha),
                    nvgRGBA(255, 100, 80, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, tipX, tipY, tipR)
                nvgFillPaint(vg, tipGrad)
                nvgFill(vg)

                nvgRestore(vg)
            end

            -- 单手剑围绕角色旋转一圈（带残影）
            if M.swordImage ~= -1 then
                local swordSize = GS.CELL * 1.0
                local hiltOffX = swordSize * 0.35
                local hiltOffY = swordSize * 0.35
                local swordOrbitR = GS.CELL * 0.6  -- 剑柄绕角色中心的轨道半径
                -- 剑旋转一整圈（360度），与弧线同步
                local swordAngle = st * math.pi * 2
                local swordAlpha = alpha / 200  -- 归一化到 0~1

                -- 残影（5个绿色残影）
                if st > 0.1 then
                    local ghostCount = 5
                    for gi = ghostCount, 1, -1 do
                        local delay = gi * 0.04
                        local gt = math.max(0, st - delay / 0.57)
                        if gt > 0 then
                            local gAngle = gt * math.pi * 2
                            local gx = cx + math.cos(gAngle) * swordOrbitR
                            local gy = cy + math.sin(gAngle) * swordOrbitR
                            local gRot = gAngle + math.rad(135)
                            local gAlpha = math.max(0.02, (0.20 - gi * 0.035) * swordAlpha)

                            nvgSave(vg)
                            nvgTranslate(vg, gx, gy)
                            nvgRotate(vg, gRot)
                            local ghostPaint = nvgImagePattern(vg,
                                -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                                swordSize, swordSize,
                                0, M.swordImage, gAlpha)
                            nvgBeginPath(vg)
                            nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                            nvgFillPaint(vg, ghostPaint)
                            nvgFill(vg)

                            -- 红色色调叠加
                            nvgBeginPath(vg)
                            nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                            nvgFillColor(vg, nvgRGBA(230, 70, 50, math.floor(50 * gAlpha)))
                            nvgFill(vg)

                            nvgRestore(vg)
                        end
                    end
                end

                -- 主剑
                local hiltX = cx + math.cos(swordAngle) * swordOrbitR
                local hiltY = cy + math.sin(swordAngle) * swordOrbitR
                local swordRot = swordAngle + math.rad(135)

                nvgSave(vg)
                nvgTranslate(vg, hiltX, hiltY)
                nvgRotate(vg, swordRot)

                local imgPaint = nvgImagePattern(vg,
                    -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY,
                    swordSize, swordSize,
                    0, M.swordImage, swordAlpha)
                nvgBeginPath(vg)
                nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)

                -- 红色色调叠加
                nvgBeginPath(vg)
                nvgRect(vg, -swordSize / 2 - hiltOffX, -swordSize / 2 - hiltOffY, swordSize, swordSize)
                nvgFillColor(vg, nvgRGBA(240, 80, 60, math.floor(70 * swordAlpha)))
                nvgFill(vg)

                nvgRestore(vg)
            end
        end

        -- ============================================================
        -- 阶段3：扩散冲击波 (0.20 - 0.55)
        -- ============================================================
        if t >= 0.20 and t < 0.55 then
            local wt = (t - 0.20) / 0.35
            local waveR = R * 0.2 + R * 1.0 * wt
            local waveAlpha = math.floor(160 * (1 - wt))
            local ringW = math.max(1.5, GS.CELL * 0.06 * (1 - wt * 0.6))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, waveR)
            nvgStrokeColor(vg, nvgRGBA(240, 100, 70, waveAlpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段4：飞散风刃碎片 (0.15 - 0.60)
        -- ============================================================
        if t >= 0.15 and t < 0.60 then
            local pt = (t - 0.15) / 0.45
            local sparkAlpha = math.floor(180 * (1 - pt))
            local sparkCount = 8
            for i = 1, sparkCount do
                local angle = (i / sparkCount) * math.pi * 2 + t * 5
                local dist = R * 0.3 + R * 0.9 * pt
                local sx = cx + math.cos(angle) * dist
                local sy = cy + math.sin(angle) * dist
                local sparkSize = math.max(1.5, GS.CELL * 0.045 * (1 - pt))
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, sparkSize)
                nvgFillColor(vg, nvgRGBA(255, 150, 100, sparkAlpha))
                nvgFill(vg)
            end
        end

        -- ============================================================
        -- 阶段5：残留光晕 (0.45 - 1.0)
        -- ============================================================
        if t >= 0.45 then
            local gt = (t - 0.45) / 0.55
            local glowR = R * 0.8 * (1 - gt * 0.3)
            local glowAlpha = math.floor(80 * (1 - gt))
            local glowGrad = nvgRadialGradient(vg, cx, cy, 0, glowR,
                nvgRGBA(200, 70, 50, glowAlpha),
                nvgRGBA(180, 50, 30, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：冰环术AOE特效（寒气扩散冰环，1.2秒）
-- ====================================================================
function M.drawIceRingEffects()
    local vg = M.vg
    for _, e in ipairs(GS.iceRingEffects) do
        local cx = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local cy = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local t = safeProgress(e.timer, e.duration)
        local time = e.timer  -- 用于粒子动画
        -- 冰环最大半径覆盖区域（动态范围）
        local maxR = GS.CELL * ((e.radius or 1) + 0.5)

        -- ============================================================
        -- 阶段1：中心凝聚冰核 (0.0 - 0.20)
        -- ============================================================
        if t < 0.20 then
            local ct = t / 0.20
            local coreR = GS.CELL * 0.08 + GS.CELL * 0.3 * ct
            -- 冰核亮白蓝光点
            local coreAlpha = math.floor(220 * ct)
            local coreGrad = nvgRadialGradient(vg, cx, cy, 0, coreR,
                nvgRGBA(220, 240, 255, coreAlpha),
                nvgRGBA(100, 180, 240, math.floor(coreAlpha * 0.4)))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, coreR)
            nvgFillPaint(vg, coreGrad)
            nvgFill(vg)
            -- 中心十字闪光
            local crossLen = coreR * 1.5 * ct
            local crossAlpha = math.floor(180 * ct)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx - crossLen, cy)
            nvgLineTo(vg, cx + crossLen, cy)
            nvgMoveTo(vg, cx, cy - crossLen)
            nvgLineTo(vg, cx, cy + crossLen)
            nvgStrokeColor(vg, nvgRGBA(200, 230, 255, crossAlpha))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.025))
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段2：冰环扩散（主体） (0.10 - 0.70)
        -- ============================================================
        if t >= 0.10 and t < 0.70 then
            local rt = (t - 0.10) / 0.60
            local curR = maxR * 0.1 + maxR * 0.9 * rt
            -- 透明度：扩散中保持亮度，后期渐弱
            local ringAlpha
            if rt < 0.3 then
                ringAlpha = math.floor(200 * (rt / 0.3))
            elseif rt > 0.7 then
                ringAlpha = math.floor(200 * (1.0 - (rt - 0.7) / 0.3))
            else
                ringAlpha = 200
            end

            -- 主冰环描边（亮冰蓝色，较粗）
            local ringW = math.max(2.5, GS.CELL * 0.08 * (1.0 - rt * 0.5))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, curR)
            nvgStrokeColor(vg, nvgRGBA(140, 210, 255, ringAlpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)

            -- 外层冰环辉光（稍大、柔和的淡蓝光晕）
            local glowW = ringW * 2.5
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, curR)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 240, math.floor(ringAlpha * 0.25)))
            nvgStrokeWidth(vg, glowW)
            nvgStroke(vg)

            -- 内侧第二道冰环（略小，白色调）
            local innerR = curR * 0.75
            local innerAlpha = math.floor(ringAlpha * 0.6)
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, innerR)
            nvgStrokeColor(vg, nvgRGBA(200, 230, 255, innerAlpha))
            nvgStrokeWidth(vg, math.max(1.5, ringW * 0.5))
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段3：地面寒霜覆盖区 (0.15 - 0.90)
        -- ============================================================
        if t >= 0.15 and t < 0.90 then
            local ft = (t - 0.15) / 0.75
            local frostR = maxR * math.min(1.0, ft * 1.3)
            -- 淡入→保持→淡出
            local frostAlpha
            if ft < 0.2 then
                frostAlpha = math.floor(50 * (ft / 0.2))
            elseif ft > 0.7 then
                frostAlpha = math.floor(50 * (1.0 - (ft - 0.7) / 0.3))
            else
                frostAlpha = 50
            end
            local frostGrad = nvgRadialGradient(vg, cx, cy, 0, frostR,
                nvgRGBA(160, 210, 240, frostAlpha),
                nvgRGBA(100, 170, 220, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, frostR)
            nvgFillPaint(vg, frostGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段4：寒气冰晶粒子飞散 (0.08 - 0.85)
        -- 24个冰晶粒子从中心向外扩散，模拟寒气逼人
        -- ============================================================
        if t >= 0.08 and t < 0.85 then
            local pt = (t - 0.08) / 0.77
            for i = 1, 24 do
                local seed1 = i * 137.508
                local seed2 = i * 73.137 + 3.71
                local seed3 = i * 41.723 + 1.29
                -- 粒子发射角度（黄金角均匀分布 + 轻微偏移）
                local angle = seed1 % (math.pi * 2)
                -- 每个粒子有不同的延迟和速度
                local delay = (seed2 % 8) * 0.03
                local localT = math.max(0, pt - delay)
                if localT > 0 and localT < 1.0 then
                    -- 速度变化：先快后慢（减速运动）
                    local easeT = 1.0 - (1.0 - localT) * (1.0 - localT)
                    local dist = maxR * (0.05 + 0.95 * easeT)
                    -- 径向位置 + 轻微切向偏移（螺旋感）
                    local spiralOff = math.sin(localT * math.pi * 2 + seed3) * maxR * 0.08
                    local perpAngle = angle + math.pi * 0.5
                    local ix = cx + math.cos(angle) * dist + math.cos(perpAngle) * spiralOff
                    local iy = cy + math.sin(angle) * dist + math.sin(perpAngle) * spiralOff
                    -- 上飘效果
                    iy = iy - localT * GS.CELL * 0.12
                    -- 尺寸：中间大两头小
                    local sizeMul = math.sin(localT * math.pi) -- 0→1→0
                    local iceSize = math.max(1.2, GS.CELL * 0.04) * (0.4 + 0.8 * sizeMul)
                    -- 透明度
                    local iceAlpha
                    if localT < 0.15 then
                        iceAlpha = math.floor(200 * (localT / 0.15))
                    elseif localT > 0.6 then
                        iceAlpha = math.floor(200 * (1.0 - (localT - 0.6) / 0.4))
                    else
                        iceAlpha = 200
                    end
                    -- 颜色：白蓝色调变化
                    local cPhase = (seed3 % 3) / 3.0
                    local icR = math.floor(160 + 60 * cPhase)
                    local icG = math.floor(210 + 30 * cPhase)
                    local icB = 255
                    nvgBeginPath(vg)
                    nvgCircle(vg, ix, iy, iceSize)
                    nvgFillColor(vg, nvgRGBA(icR, icG, icB, iceAlpha))
                    nvgFill(vg)
                end
            end
        end

        -- ============================================================
        -- 阶段5：持续逃逸的寒冷气息雾气 (0.05 - 0.95)
        -- 16个雾气团从扩散前沿不断向外逸散
        -- ============================================================
        if t >= 0.05 and t < 0.95 then
            for i = 1, 16 do
                local seed1 = i * 97.31 + 7.13
                local seed2 = i * 53.71 + 2.89
                local seed3 = i * 31.17 + 5.43
                -- 每个雾气团以不同速率循环
                local period = 0.6 + (seed2 % 6) * 0.08
                local life = (time + seed1 * 0.13) % period
                local lt = life / period
                -- 发射角度
                local fogAngle = seed1 % (math.pi * 2)
                -- 当前冰环前沿半径
                local frontR
                if t < 0.70 then
                    local rt2 = math.max(0, (t - 0.10) / 0.60)
                    frontR = maxR * 0.1 + maxR * 0.9 * rt2
                else
                    frontR = maxR
                end
                -- 从前沿附近出发，向外飘散
                local fogDist = frontR * (0.7 + 0.3 * lt) + maxR * 0.3 * lt
                local fogX = cx + math.cos(fogAngle) * fogDist
                local fogY = cy + math.sin(fogAngle) * fogDist
                -- 上飘 + 横向扰动
                fogY = fogY - lt * GS.CELL * 0.18
                fogX = fogX + math.sin(time * 3.0 + seed3) * GS.CELL * 0.05
                -- 尺寸：较大的雾气团
                local fogSize = math.max(2.0, GS.CELL * 0.06) * (0.5 + 0.5 * math.sin(lt * math.pi))
                -- 透明度：淡入淡出
                local fogAlpha
                if lt < 0.2 then
                    fogAlpha = math.floor(80 * (lt / 0.2))
                elseif lt > 0.5 then
                    fogAlpha = math.floor(80 * (1.0 - (lt - 0.5) / 0.5))
                else
                    fogAlpha = 80
                end
                if fogAlpha > 3 then
                    local fogGrad = nvgRadialGradient(vg, fogX, fogY, 0, fogSize,
                        nvgRGBA(180, 220, 255, fogAlpha),
                        nvgRGBA(140, 200, 240, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, fogX, fogY, fogSize)
                    nvgFillPaint(vg, fogGrad)
                    nvgFill(vg)
                end
            end
        end

        -- ============================================================
        -- 阶段6：冰环边缘冰碴闪烁 (0.20 - 0.75)
        -- 12个菱形冰碴沿扩散环边缘分布
        -- ============================================================
        if t >= 0.20 and t < 0.75 then
            local st = (t - 0.20) / 0.55
            local edgeR
            if t < 0.70 then
                local rt3 = (t - 0.10) / 0.60
                edgeR = maxR * 0.1 + maxR * 0.9 * rt3
            else
                edgeR = maxR
            end
            local shardAlpha
            if st < 0.2 then
                shardAlpha = math.floor(220 * (st / 0.2))
            elseif st > 0.7 then
                shardAlpha = math.floor(220 * (1.0 - (st - 0.7) / 0.3))
            else
                shardAlpha = 220
            end
            for i = 1, 12 do
                local shardAngle = (i / 12) * math.pi * 2 + st * 2.0
                local sx = cx + math.cos(shardAngle) * edgeR
                local sy = cy + math.sin(shardAngle) * edgeR
                -- 菱形冰碴
                local shardSize = math.max(1.5, GS.CELL * 0.04)
                local flickAlpha = math.floor(shardAlpha * (0.6 + 0.4 * math.sin(time * 8 + i * 2.1)))
                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgRotate(vg, shardAngle + math.pi * 0.25)
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -shardSize)
                nvgLineTo(vg, shardSize * 0.5, 0)
                nvgLineTo(vg, 0, shardSize)
                nvgLineTo(vg, -shardSize * 0.5, 0)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(200, 235, 255, flickAlpha))
                nvgFill(vg)
                nvgRestore(vg)
            end
        end

        -- ============================================================
        -- 阶段7：最终扩散冲击波 (0.55 - 0.80)
        -- ============================================================
        if t >= 0.55 and t < 0.80 then
            local wt = (t - 0.55) / 0.25
            local waveR = maxR * 0.6 + maxR * 0.6 * wt
            local waveAlpha = math.floor(140 * (1.0 - wt))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, waveR)
            nvgStrokeColor(vg, nvgRGBA(180, 230, 255, waveAlpha))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.04 * (1.0 - wt * 0.6)))
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段8：残留寒霜光晕消散 (0.70 - 1.0)
        -- ============================================================
        if t >= 0.70 then
            local gt = (t - 0.70) / 0.30
            local glowR = maxR * (1.0 - gt * 0.2)
            local glowAlpha = math.floor(60 * (1.0 - gt))
            local glowGrad = nvgRadialGradient(vg, cx, cy, 0, glowR,
                nvgRGBA(120, 190, 240, glowAlpha),
                nvgRGBA(80, 160, 220, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：火球术AOE特效（巨大火球弹道 + 落地火焰冲击波，1.5秒）
-- 弹道阶段 0.0-0.40，落地爆炸 0.35-1.0
-- ====================================================================
function M.drawFireballEffects()
    local vg = M.vg
    for _, e in ipairs(GS.fireballEffects) do
        local t = safeProgress(e.timer, e.duration)
        local time = e.timer
        -- 起点和终点像素坐标
        local fxP = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fyP = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2
        local txP = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local tyP = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        -- 爆炸范围（动态半径）
        local maxR = GS.CELL * (e.radius or 2)
        -- 弹道命中时刻
        local hitT = 0.30

        -- ============================================================
        -- 阶段A：巨大火球弹道 (0.0 - hitT)
        -- ============================================================
        if t < hitT then
            local bt = t / hitT
            -- 火球当前位置（直线飞行）
            local bx = fxP + (txP - fxP) * bt
            local by = fyP + (tyP - fyP) * bt
            -- 火球大小：从中等到很大
            local ballR = GS.CELL * (0.25 + 0.15 * bt)
            local flicker = (math.sin(time * 18) + math.sin(time * 27)) * 0.15 + 0.85

            -- 外层炽热光晕（大范围橙色辉光）
            local heatR = ballR * 2.8
            local heatGlow = nvgRadialGradient(vg, bx, by, ballR * 0.5, heatR,
                nvgRGBA(255, 100, 20, math.floor(80 * flicker)),
                nvgRGBA(255, 40, 0, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, heatR)
            nvgFillPaint(vg, heatGlow)
            nvgFill(vg)

            -- 火球主体（橙红渐变球体）
            local ballGrad = nvgRadialGradient(vg, bx - ballR * 0.2, by - ballR * 0.2,
                ballR * 0.15, ballR,
                nvgRGBA(255, 240, 160, 255),
                nvgRGBA(230, 60, 10, math.floor(220 * flicker)))
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, ballR)
            nvgFillPaint(vg, ballGrad)
            nvgFill(vg)

            -- 火球核心高光
            local coreR = ballR * 0.4
            nvgBeginPath(vg)
            nvgCircle(vg, bx - ballR * 0.15, by - ballR * 0.15, coreR)
            nvgFillColor(vg, nvgRGBA(255, 255, 220, math.floor(200 * flicker)))
            nvgFill(vg)

            -- 火球边缘轮廓
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, ballR)
            nvgStrokeColor(vg, nvgRGBA(255, 120, 20, math.floor(180 * flicker)))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.025))
            nvgStroke(vg)

            -- 飞行拖尾火焰粒子（16个，沿弹道后方散布）
            for i = 1, 16 do
                local seed1 = i * 137.508
                local seed2 = i * 73.137 + 4.21
                local seed3 = i * 41.723 + 2.89
                local trailT = math.max(0, bt - (seed2 % 6) * 0.015 - 0.02)
                if trailT > 0 then
                    local tx = fxP + (txP - fxP) * trailT
                    local ty = fyP + (tyP - fyP) * trailT
                    -- 散开偏移
                    local spread = GS.CELL * 0.15 * (bt - trailT + 0.05)
                    tx = tx + math.sin(seed1) * spread
                    ty = ty + math.cos(seed1) * spread - (bt - trailT) * GS.CELL * 0.3
                    local tSize = math.max(1.2, ballR * 0.3 * (1.0 - (bt - trailT) * 4))
                    local tAlpha = math.floor(180 * math.max(0, 1.0 - (bt - trailT) * 5))
                    -- 颜色随距离：亮黄→橙→暗红
                    local age = (bt - trailT) * 5
                    local tR = math.floor(255 - 30 * math.min(1, age))
                    local tG = math.floor(200 - 150 * math.min(1, age))
                    local tB = math.floor(60 - 50 * math.min(1, age))
                    if tAlpha > 5 and tSize > 0.5 then
                        nvgBeginPath(vg)
                        nvgCircle(vg, tx, ty, tSize)
                        nvgFillColor(vg, nvgRGBA(tR, tG, tB, tAlpha))
                        nvgFill(vg)
                    end
                end
            end
        end

        -- ============================================================
        -- 阶段B：落地火焰爆炸闪光 (hitT - hitT+0.08)
        -- ============================================================
        if t >= hitT and t < hitT + 0.08 then
            local ft = (t - hitT) / 0.08
            local flashR = GS.CELL * 0.5 + maxR * 0.6 * ft
            local flashAlpha = math.floor(255 * (1.0 - ft))
            local flashGrad = nvgRadialGradient(vg, txP, tyP, 0, flashR,
                nvgRGBA(255, 255, 200, flashAlpha),
                nvgRGBA(255, 160, 40, math.floor(flashAlpha * 0.5)))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段C：火焰冲击波扩散 (hitT - 0.75)
        -- ============================================================
        if t >= hitT and t < 0.75 then
            local wt = (t - hitT) / (0.75 - hitT)
            local waveR = maxR * 0.15 + maxR * 0.85 * wt
            local waveAlpha
            if wt < 0.3 then
                waveAlpha = math.floor(220 * (wt / 0.3))
            elseif wt > 0.6 then
                waveAlpha = math.floor(220 * (1.0 - (wt - 0.6) / 0.4))
            else
                waveAlpha = 220
            end

            -- 主冲击波环（明亮橙红）
            local ringW = math.max(2.5, GS.CELL * 0.1 * (1.0 - wt * 0.5))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, waveR)
            nvgStrokeColor(vg, nvgRGBA(255, 120, 30, waveAlpha))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)

            -- 外层冲击波辉光
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, waveR)
            nvgStrokeColor(vg, nvgRGBA(255, 80, 10, math.floor(waveAlpha * 0.25)))
            nvgStrokeWidth(vg, ringW * 3.0)
            nvgStroke(vg)

            -- 内侧第二道冲击波（略小，亮黄色调）
            local innerR = waveR * 0.7
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, innerR)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 80, math.floor(waveAlpha * 0.5)))
            nvgStrokeWidth(vg, math.max(1.5, ringW * 0.5))
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段D：燃烧地面覆盖区 (hitT+0.05 - 0.90)
        -- ============================================================
        if t >= hitT + 0.05 and t < 0.90 then
            local gt = (t - hitT - 0.05) / (0.90 - hitT - 0.05)
            local groundR = maxR * math.min(1.0, gt * 1.8)
            local gAlpha
            if gt < 0.15 then
                gAlpha = math.floor(60 * (gt / 0.15))
            elseif gt > 0.6 then
                gAlpha = math.floor(60 * (1.0 - (gt - 0.6) / 0.4))
            else
                gAlpha = 60
            end
            local flicker2 = (math.sin(time * 9.3) + math.sin(time * 13.7)) * 0.15 + 0.85
            gAlpha = math.floor(gAlpha * flicker2)
            local groundGrad = nvgRadialGradient(vg, txP, tyP, 0, groundR,
                nvgRGBA(220, 80, 20, gAlpha),
                nvgRGBA(180, 40, 10, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, groundR)
            nvgFillPaint(vg, groundGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段E：大量燃烧火焰粒子飞散 (hitT - 0.90)
        -- 30个粒子从爆心向外扩散
        -- ============================================================
        if t >= hitT and t < 0.90 then
            local pt = (t - hitT) / (0.90 - hitT)
            for i = 1, 30 do
                local seed1 = i * 137.508
                local seed2 = i * 73.137 + 6.31
                local seed3 = i * 41.723 + 3.57
                local angle = seed1 % (math.pi * 2)
                local delay = (seed2 % 8) * 0.025
                local localT = math.max(0, pt - delay)
                if localT > 0 and localT < 1.0 then
                    -- 减速飞散
                    local easeT = 1.0 - (1.0 - localT) * (1.0 - localT)
                    local speed = 0.5 + (seed3 % 5) * 0.15
                    local dist = maxR * easeT * speed
                    local sparkX = txP + math.cos(angle) * dist
                    local sparkY = tyP + math.sin(angle) * dist
                    -- 上飘 + 重力弧线
                    sparkY = sparkY - localT * GS.CELL * 0.25 + localT * localT * GS.CELL * 0.1
                    -- 横向扰动
                    sparkX = sparkX + math.sin(time * 5.0 + seed1) * GS.CELL * 0.04
                    -- 尺寸
                    local sizeMul = math.sin(localT * math.pi)
                    local sSize = math.max(1.2, GS.CELL * 0.04) * (0.4 + 0.8 * sizeMul)
                    -- 透明度
                    local sAlpha
                    if localT < 0.1 then
                        sAlpha = math.floor(220 * (localT / 0.1))
                    elseif localT > 0.5 then
                        sAlpha = math.floor(220 * (1.0 - (localT - 0.5) / 0.5))
                    else
                        sAlpha = 220
                    end
                    -- 颜色：亮黄→橙→暗红
                    local sR = math.floor(255 - 50 * localT)
                    local sG = math.floor(220 - 180 * localT)
                    local sB = math.floor(60 - 50 * localT)
                    if sAlpha > 5 and sSize > 0.5 then
                        nvgBeginPath(vg)
                        nvgCircle(vg, sparkX, sparkY, sSize)
                        nvgFillColor(vg, nvgRGBA(sR, sG, sB, sAlpha))
                        nvgFill(vg)
                    end
                end
            end
        end

        -- ============================================================
        -- 阶段F：持续冒出的燃烧余烬 (hitT+0.08 - 0.95)
        -- 12个循环粒子从地面不断上升
        -- ============================================================
        if t >= hitT + 0.08 and t < 0.95 then
            for i = 1, 12 do
                local seed1 = i * 97.31 + 11.7
                local seed2 = i * 53.71 + 7.3
                local period = 0.5 + (seed2 % 5) * 0.1
                local life = (time + seed1 * 0.17) % period
                local lt = life / period
                local emAngle = seed1 % (math.pi * 2)
                local emDist = maxR * (0.2 + 0.6 * ((seed2 % 8) / 8))
                local emX = txP + math.cos(emAngle) * emDist
                local emY = tyP + math.sin(emAngle) * emDist
                -- 上升
                emY = emY - lt * GS.CELL * 0.3
                -- 横向飘动
                emX = emX + math.sin(time * 3.5 + seed1) * GS.CELL * 0.04
                local emSize = math.max(1.5, GS.CELL * 0.035) * (0.5 + 0.5 * math.sin(lt * math.pi))
                local emAlpha
                if lt < 0.2 then
                    emAlpha = math.floor(140 * (lt / 0.2))
                elseif lt > 0.5 then
                    emAlpha = math.floor(140 * (1.0 - (lt - 0.5) / 0.5))
                else
                    emAlpha = 140
                end
                if emAlpha > 3 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, emX, emY, emSize)
                    nvgFillColor(vg, nvgRGBA(255, math.floor(160 - 100 * lt), math.floor(40 - 30 * lt), emAlpha))
                    nvgFill(vg)
                end
            end
        end

        -- ============================================================
        -- 阶段G：残留火焰光晕消散 (0.75 - 1.0)
        -- ============================================================
        if t >= 0.75 then
            local gt2 = (t - 0.75) / 0.25
            local glowR = maxR * (1.0 - gt2 * 0.2)
            local glowAlpha = math.floor(50 * (1.0 - gt2))
            local glowGrad = nvgRadialGradient(vg, txP, tyP, 0, glowR,
                nvgRGBA(200, 60, 20, glowAlpha),
                nvgRGBA(160, 30, 10, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：陨石术AOE特效（燃烧陨石从天降落 + 巨大爆炸，1.8秒）
-- 下落阶段 0.0-0.35，撞击爆炸 0.30-1.0
-- ====================================================================
function M.drawMeteorEffects()
    local vg = M.vg
    for _, e in ipairs(GS.meteorEffects) do
        local t = safeProgress(e.timer, e.duration)
        local time = e.timer
        local txP = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local tyP = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        -- 爆炸范围（动态半径）
        local maxR = GS.CELL * (e.radius or 2)
        local impactT = 0.33

        -- ============================================================
        -- 阶段A：预警光圈 (0.0 - impactT)
        -- ============================================================
        if t < impactT then
            local wt = t / impactT
            -- 地面预警圆圈（红色脉冲）
            local warnR = maxR * (0.3 + 0.7 * wt)
            local warnPulse = (math.sin(time * 12) + 1) * 0.5
            local warnAlpha = math.floor((40 + 40 * warnPulse) * wt)
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, warnR)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 20, warnAlpha))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.03))
            nvgStroke(vg)
            -- 中心十字准星
            local crossR = GS.CELL * 0.3 * wt
            local crossA = math.floor(120 * wt)
            nvgBeginPath(vg)
            nvgMoveTo(vg, txP - crossR, tyP)
            nvgLineTo(vg, txP + crossR, tyP)
            nvgMoveTo(vg, txP, tyP - crossR)
            nvgLineTo(vg, txP, tyP + crossR)
            nvgStrokeColor(vg, nvgRGBA(255, 80, 30, crossA))
            nvgStrokeWidth(vg, math.max(1.0, GS.CELL * 0.02))
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段B：陨石从天降落 (0.05 - impactT)
        -- ============================================================
        if t >= 0.05 and t < impactT then
            local dt2 = (t - 0.05) / (impactT - 0.05)
            -- 加速下落（easeIn）
            local fallEase = dt2 * dt2
            -- 从右上方 45° 角坠入
            local startX = txP + GS.CELL * 4.0
            local startY = tyP - GS.CELL * 5.0
            local meteorX = startX + (txP - startX) * fallEase
            local meteorY = startY + (tyP - startY) * fallEase
            -- 陨石大小（很大）
            local meteorR = GS.CELL * (0.3 + 0.15 * dt2)
            local flicker = (math.sin(time * 20) + math.sin(time * 31)) * 0.12 + 0.88

            -- 下落尾迹（长长的火焰拖尾）
            local trailLen = 12
            for i = trailLen, 1, -1 do
                local trailT = math.max(0, fallEase - i * 0.03)
                local ttx = startX + (txP - startX) * trailT
                local tty = startY + (tyP - startY) * trailT
                local trailAge = i / trailLen
                local trailR = meteorR * (0.8 - 0.5 * trailAge)
                local trailAlpha = math.floor(160 * (1.0 - trailAge))
                if trailR > 0.5 and trailAlpha > 5 then
                    local trR = math.floor(255 - 40 * trailAge)
                    local trG = math.floor(160 - 120 * trailAge)
                    local trB = math.floor(40 - 30 * trailAge)
                    nvgBeginPath(vg)
                    nvgCircle(vg, ttx, tty, trailR)
                    nvgFillColor(vg, nvgRGBA(trR, trG, trB, trailAlpha))
                    nvgFill(vg)
                end
            end

            -- 陨石外层炽热光晕
            local mHeatR = meteorR * 3.0
            local mHeatGrad = nvgRadialGradient(vg, meteorX, meteorY, meteorR * 0.5, mHeatR,
                nvgRGBA(255, 120, 30, math.floor(100 * flicker)),
                nvgRGBA(255, 40, 0, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, meteorX, meteorY, mHeatR)
            nvgFillPaint(vg, mHeatGrad)
            nvgFill(vg)

            -- 陨石主体（暗棕红色岩石 + 表面火焰）
            local rockGrad = nvgRadialGradient(vg, meteorX - meteorR * 0.2, meteorY - meteorR * 0.2,
                meteorR * 0.1, meteorR,
                nvgRGBA(180, 80, 30, 255),
                nvgRGBA(120, 40, 15, 240))
            nvgBeginPath(vg)
            nvgCircle(vg, meteorX, meteorY, meteorR)
            nvgFillPaint(vg, rockGrad)
            nvgFill(vg)

            -- 陨石表面燃烧纹理（6个流动火焰光团）
            for i = 1, 6 do
                local fAngle = (i / 6) * math.pi * 2 + time * 4.0
                local fDist = meteorR * 0.6
                local fsx = meteorX + math.cos(fAngle) * fDist
                local fsy = meteorY + math.sin(fAngle) * fDist
                local fsSize = meteorR * 0.25 * (0.7 + 0.3 * math.sin(time * 10 + i * 1.5))
                nvgBeginPath(vg)
                nvgCircle(vg, fsx, fsy, fsSize)
                nvgFillColor(vg, nvgRGBA(255, 180, 60, math.floor(180 * flicker)))
                nvgFill(vg)
            end

            -- 陨石轮廓
            nvgBeginPath(vg)
            nvgCircle(vg, meteorX, meteorY, meteorR)
            nvgStrokeColor(vg, nvgRGBA(255, 100, 20, math.floor(200 * flicker)))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.025))
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段C：撞击白色闪光 (impactT - impactT+0.06)
        -- ============================================================
        if t >= impactT and t < impactT + 0.06 then
            local ft = (t - impactT) / 0.06
            local flashR = GS.CELL * 0.3 + maxR * 1.0 * ft
            local flashAlpha = math.floor(255 * (1.0 - ft * ft))
            -- 白色核心闪光
            local flashGrad = nvgRadialGradient(vg, txP, tyP, 0, flashR,
                nvgRGBA(255, 255, 240, flashAlpha),
                nvgRGBA(255, 200, 100, math.floor(flashAlpha * 0.4)))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段D：巨大火焰爆炸冲击波 (impactT - 0.70)
        -- 三层冲击波
        -- ============================================================
        if t >= impactT and t < 0.70 then
            local wt = (t - impactT) / (0.70 - impactT)
            local waveAlpha
            if wt < 0.2 then
                waveAlpha = math.floor(240 * (wt / 0.2))
            elseif wt > 0.5 then
                waveAlpha = math.floor(240 * (1.0 - (wt - 0.5) / 0.5))
            else
                waveAlpha = 240
            end

            -- 第一层：主冲击波（橙红，最大）
            local wave1R = maxR * 0.1 + maxR * 1.1 * wt
            local wave1W = math.max(3.0, GS.CELL * 0.12 * (1.0 - wt * 0.5))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, wave1R)
            nvgStrokeColor(vg, nvgRGBA(255, 100, 20, waveAlpha))
            nvgStrokeWidth(vg, wave1W)
            nvgStroke(vg)

            -- 第二层：内冲击波（亮黄）
            local wave2R = wave1R * 0.65
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, wave2R)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(waveAlpha * 0.7)))
            nvgStrokeWidth(vg, math.max(2.0, wave1W * 0.6))
            nvgStroke(vg)

            -- 第三层：外辉光
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, wave1R)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 10, math.floor(waveAlpha * 0.2)))
            nvgStrokeWidth(vg, wave1W * 4.0)
            nvgStroke(vg)
        end

        -- ============================================================
        -- 阶段E：爆炸地面焦痕 (impactT+0.03 - 0.95)
        -- ============================================================
        if t >= impactT + 0.03 and t < 0.95 then
            local gt = (t - impactT - 0.03) / (0.95 - impactT - 0.03)
            local scorchR = maxR * math.min(1.0, gt * 2.0)
            local sAlpha
            if gt < 0.1 then
                sAlpha = math.floor(70 * (gt / 0.1))
            elseif gt > 0.5 then
                sAlpha = math.floor(70 * (1.0 - (gt - 0.5) / 0.5))
            else
                sAlpha = 70
            end
            local flicker3 = (math.sin(time * 7.7) + math.sin(time * 11.3)) * 0.12 + 0.88
            sAlpha = math.floor(sAlpha * flicker3)
            local scorchGrad = nvgRadialGradient(vg, txP, tyP, 0, scorchR,
                nvgRGBA(200, 50, 10, sAlpha),
                nvgRGBA(100, 20, 5, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, scorchR)
            nvgFillPaint(vg, scorchGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段F：大量爆炸碎片和火焰粒子 (impactT - 0.85)
        -- 36个粒子（大量），模拟剧烈爆炸
        -- ============================================================
        if t >= impactT and t < 0.85 then
            local pt = (t - impactT) / (0.85 - impactT)
            for i = 1, 36 do
                local seed1 = i * 137.508
                local seed2 = i * 73.137 + 8.91
                local seed3 = i * 41.723 + 4.17
                local angle = seed1 % (math.pi * 2)
                local delay = (seed2 % 10) * 0.015
                local localT = math.max(0, pt - delay)
                if localT > 0 and localT < 1.0 then
                    local speed = 0.5 + (seed3 % 6) * 0.18
                    -- 爆炸飞散（先快后慢）
                    local easeT = 1.0 - (1.0 - localT) * (1.0 - localT)
                    local dist = maxR * 1.2 * easeT * speed
                    local debX = txP + math.cos(angle) * dist
                    local debY = tyP + math.sin(angle) * dist
                    -- 抛物线轨迹（先上后下）
                    debY = debY - math.sin(localT * math.pi) * GS.CELL * 0.4 * speed
                    -- 尺寸：岩石碎片（较大）
                    local isRock = (i % 3 == 0)
                    local debSize
                    if isRock then
                        debSize = math.max(2.0, GS.CELL * 0.05) * (1.0 - localT * 0.6)
                    else
                        debSize = math.max(1.2, GS.CELL * 0.035) * math.sin(localT * math.pi)
                    end
                    -- 透明度
                    local debAlpha
                    if localT < 0.08 then
                        debAlpha = math.floor(240 * (localT / 0.08))
                    elseif localT > 0.5 then
                        debAlpha = math.floor(240 * (1.0 - (localT - 0.5) / 0.5))
                    else
                        debAlpha = 240
                    end
                    -- 颜色：岩石碎片(暗棕) vs 火焰粒子(亮橙)
                    local debR, debG, debB
                    if isRock then
                        debR = math.floor(140 - 40 * localT)
                        debG = math.floor(70 - 30 * localT)
                        debB = math.floor(30 - 15 * localT)
                    else
                        debR = math.floor(255 - 50 * localT)
                        debG = math.floor(200 - 160 * localT)
                        debB = math.floor(50 - 40 * localT)
                    end
                    if debAlpha > 5 and debSize > 0.5 then
                        nvgBeginPath(vg)
                        nvgCircle(vg, debX, debY, debSize)
                        nvgFillColor(vg, nvgRGBA(debR, debG, debB, debAlpha))
                        nvgFill(vg)
                    end
                end
            end
        end

        -- ============================================================
        -- 阶段G：持续上升的火焰烟柱 (impactT+0.06 - 0.95)
        -- 14个循环粒子模拟蘑菇云/烟柱
        -- ============================================================
        if t >= impactT + 0.06 and t < 0.95 then
            for i = 1, 14 do
                local seed1 = i * 97.31 + 13.7
                local seed2 = i * 53.71 + 9.1
                local period = 0.5 + (seed2 % 5) * 0.1
                local life = (time + seed1 * 0.19) % period
                local lt = life / period
                -- 从爆心附近上升
                local colAngle = seed1 % (math.pi * 2)
                local colDist = maxR * (0.1 + 0.3 * ((seed2 % 7) / 7))
                local colX = txP + math.cos(colAngle) * colDist
                local colY = tyP + math.sin(colAngle) * colDist
                -- 强烈上升
                colY = colY - lt * GS.CELL * 0.5
                -- 横向扩散
                colX = colX + math.sin(time * 2.5 + seed1) * GS.CELL * 0.08
                local colSize = math.max(2.5, GS.CELL * 0.06) * (0.4 + 0.6 * math.sin(lt * math.pi))
                local colAlpha
                if lt < 0.15 then
                    colAlpha = math.floor(120 * (lt / 0.15))
                elseif lt > 0.4 then
                    colAlpha = math.floor(120 * (1.0 - (lt - 0.4) / 0.6))
                else
                    colAlpha = 120
                end
                if colAlpha > 3 then
                    -- 底部火焰色，上方变暗烟色
                    local smokeT = math.min(1, lt * 1.5)
                    local smR = math.floor(255 - 155 * smokeT)
                    local smG = math.floor(140 - 100 * smokeT)
                    local smB = math.floor(40 + 20 * smokeT)
                    local smokeGrad = nvgRadialGradient(vg, colX, colY, 0, colSize,
                        nvgRGBA(smR, smG, smB, colAlpha),
                        nvgRGBA(smR, smG, smB, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, colX, colY, colSize)
                    nvgFillPaint(vg, smokeGrad)
                    nvgFill(vg)
                end
            end
        end

        -- ============================================================
        -- 阶段H：残留焦痕光晕消散 (0.80 - 1.0)
        -- ============================================================
        if t >= 0.80 then
            local gt2 = (t - 0.80) / 0.20
            local glowR = maxR * (1.0 - gt2 * 0.15)
            local glowAlpha = math.floor(40 * (1.0 - gt2))
            local glowGrad = nvgRadialGradient(vg, txP, tyP, 0, glowR,
                nvgRGBA(160, 40, 10, glowAlpha),
                nvgRGBA(80, 20, 5, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：闪电链特效（多段链式粗壮闪电依次传递）
-- ====================================================================
function M.drawLightningChainEffects()
    local vg = M.vg
    local time = M.time or 0
    for _, e in ipairs(GS.lightningChainEffects) do
        local chain = e.chain
        local numSegs = #chain
        if numSegs == 0 then goto continue_chain end

        -- 每段闪电的时间分配
        local segDur = 0.22       -- 每段持续时间
        local segFade = 0.18      -- 段淡出持续
        local totalAnimTime = e.duration

        for si = 1, numSegs do
            local seg = chain[si]
            -- 该段的起始时间
            local segStart = (si - 1) * segDur
            -- 该段的生命期
            local segLife = e.timer - segStart
            if segLife < 0 then goto continue_seg end
            -- 超过段时长+淡出时间则不再绘制
            if segLife > segDur + segFade then goto continue_seg end

            -- 透明度：快速出现 → 保持 → 淡出
            local boltAlpha = 255
            local flashIn = 0.04
            if segLife < flashIn then
                boltAlpha = math.floor(255 * (segLife / flashIn))
            elseif segLife > segDur then
                boltAlpha = math.floor(255 * (1.0 - (segLife - segDur) / segFade))
            end
            if boltAlpha < 3 then goto continue_seg end

            -- 起终点像素坐标
            local fx = GS.BOARD_X + (seg.fx - 0.5) * GS.CELL
            local fy = GS.BOARD_Y + (seg.fy - 0.5) * GS.CELL
            local tx = GS.BOARD_X + (seg.tx - 0.5) * GS.CELL
            local ty = GS.BOARD_Y + (seg.ty - 0.5) * GS.CELL

            -- 确定性种子（每段不同）
            local baseSeed = seg.fx * 7.3 + seg.fy * 13.7 + seg.tx * 3.1 + seg.ty * 5.9 + si * 17.3
            local jitterSeed = math.floor(time * 14)

            -- 生成锯齿形闪电主路径（12段，比电击术的8段更多）
            local segments = 12
            local boltPoints = {}
            local perpX = -(ty - fy)
            local perpY = (tx - fx)
            local perpLen = math.sqrt(perpX * perpX + perpY * perpY)
            if perpLen > 0.01 then
                perpX = perpX / perpLen
                perpY = perpY / perpLen
            end
            for pi = 0, segments do
                local st = pi / segments
                local bx = fx + (tx - fx) * st
                local by = fy + (ty - fy) * st
                if pi > 0 and pi < segments then
                    local offsetMag = GS.CELL * 0.25 * math.sin(baseSeed + pi * 2.3 + jitterSeed * 0.4)
                    local envelop = math.sin(st * math.pi)
                    bx = bx + perpX * offsetMag * envelop
                    by = by + perpY * offsetMag * envelop
                end
                boltPoints[pi + 1] = { bx, by }
            end

            -- 外层宽光晕（蓝紫色弥散）
            nvgBeginPath(vg)
            nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
            for pi = 2, #boltPoints do
                nvgLineTo(vg, boltPoints[pi][1], boltPoints[pi][2])
            end
            nvgStrokeColor(vg, nvgRGBA(160, 180, 255, math.floor(boltAlpha * 0.3)))
            nvgStrokeWidth(vg, math.max(10, GS.CELL * 0.22))
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)

            -- 中层主体电弧（亮黄色，粗壮）
            nvgBeginPath(vg)
            nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
            for pi = 2, #boltPoints do
                nvgLineTo(vg, boltPoints[pi][1], boltPoints[pi][2])
            end
            nvgStrokeColor(vg, nvgRGBA(255, 240, 80, boltAlpha))
            nvgStrokeWidth(vg, math.max(4.5, GS.CELL * 0.09))
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)

            -- 内核白线
            nvgBeginPath(vg)
            nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
            for pi = 2, #boltPoints do
                nvgLineTo(vg, boltPoints[pi][1], boltPoints[pi][2])
            end
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(boltAlpha * 0.85)))
            nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.03))
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)

            -- 6条分支闪电（比电击术的3条更多）
            for bi = 1, 6 do
                local branchIdx = math.floor(1 + (bi / 7) * segments)
                branchIdx = math.min(branchIdx, #boltPoints)
                local bp = boltPoints[branchIdx]
                local branchAngle = baseSeed + bi * 2.1 + jitterSeed * 0.6
                local branchLen = GS.CELL * (0.18 + 0.12 * math.sin(branchAngle * 1.7))
                local bex = bp[1] + math.cos(branchAngle) * branchLen
                local bey = bp[2] + math.sin(branchAngle) * branchLen
                -- 分支中点偏移
                local midBx = (bp[1] + bex) / 2 + math.sin(branchAngle * 3.3) * GS.CELL * 0.07
                local midBy = (bp[2] + bey) / 2 + math.cos(branchAngle * 3.3) * GS.CELL * 0.07
                nvgBeginPath(vg)
                nvgMoveTo(vg, bp[1], bp[2])
                nvgLineTo(vg, midBx, midBy)
                nvgLineTo(vg, bex, bey)
                nvgStrokeColor(vg, nvgRGBA(255, 240, 120, math.floor(boltAlpha * 0.55)))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)
                -- 分支二级分叉（更细的小电弧）
                local subAngle = branchAngle + 0.8
                local subLen = branchLen * 0.5
                local subEx = bex + math.cos(subAngle) * subLen
                local subEy = bey + math.sin(subAngle) * subLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, bex, bey)
                nvgLineTo(vg, subEx, subEy)
                nvgStrokeColor(vg, nvgRGBA(255, 230, 150, math.floor(boltAlpha * 0.35)))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.02))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            end

            -- 起点电弧光球
            local startGlowR = GS.CELL * 0.22
            local startGlowA = math.floor(boltAlpha * 0.6)
            local sg = nvgRadialGradient(vg, fx, fy, 0, startGlowR,
                nvgRGBA(255, 240, 100, startGlowA),
                nvgRGBA(200, 180, 60, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, startGlowR)
            nvgFillPaint(vg, sg)
            nvgFill(vg)

            -- 终点命中电击光球（更大更亮）
            local endGlowR = GS.CELL * 0.30
            local endGlowA = math.floor(boltAlpha * 0.7)
            local eg = nvgRadialGradient(vg, tx, ty, 0, endGlowR,
                nvgRGBA(255, 250, 180, endGlowA),
                nvgRGBA(255, 220, 60, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, endGlowR)
            nvgFillPaint(vg, eg)
            nvgFill(vg)

            -- 终点电花粒子（8颗，比电击术的6颗更多）
            for i = 1, 8 do
                local spAngle = (i / 8) * math.pi * 2 + time * 10
                local spDist = GS.CELL * (0.12 + 0.08 * math.sin(time * 15 + i * 1.8))
                local spX = tx + math.cos(spAngle) * spDist
                local spY = ty + math.sin(spAngle) * spDist
                local spSize = math.max(1.5, GS.CELL * 0.025)
                nvgBeginPath(vg)
                nvgCircle(vg, spX, spY, spSize)
                nvgFillColor(vg, nvgRGBA(255, 240, 140, math.floor(boltAlpha * 0.6)))
                nvgFill(vg)
            end

            ::continue_seg::
        end
        ::continue_chain::
    end
end

-- ====================================================================
-- 绘制：落雷术特效（天降粗壮雷柱 + 冲击爆炸）
-- ====================================================================
function M.drawThunderStrikeEffects()
    local vg = M.vg
    local time = M.time or 0
    for _, e in ipairs(GS.thunderStrikeEffects) do
        local t = safeProgress(e.timer, e.duration)
        -- 目标中心像素坐标
        local txP = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local tyP = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local maxR = GS.CELL * ((e.radius or 1) + 0.5)

        -- 雷柱从画面顶部略偏落下
        local skyX = txP + GS.CELL * 0.3
        local skyY = tyP - GS.CELL * 8

        -- 确定性种子
        local baseSeed = e.x * 11.3 + e.y * 7.9

        -- ============================================================
        -- 阶段A：落雷预警光柱 (0.0 - 0.28)
        -- 目标位置出现跳动的电弧预警圈
        -- ============================================================
        if t < 0.28 then
            local at = t / 0.28
            -- 脉冲闪烁预警圈
            local pulse = 0.5 + 0.5 * math.sin(at * math.pi * 6)
            local warnAlpha = math.floor(120 * at * pulse)
            local warnR = GS.CELL * 0.5 * (0.6 + 0.4 * at)
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, warnR)
            nvgStrokeColor(vg, nvgRGBA(255, 240, 60, warnAlpha))
            nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
            nvgStroke(vg)

            -- 小电弧在预警圈上跳动（4条）
            for i = 1, 4 do
                local arcAngle = (i / 4) * math.pi * 2 + at * math.pi * 3
                local ax1 = txP + math.cos(arcAngle) * warnR
                local ay1 = tyP + math.sin(arcAngle) * warnR
                local arcLen = GS.CELL * 0.15
                local ax2 = ax1 + math.cos(arcAngle + 0.8) * arcLen
                local ay2 = ay1 + math.sin(arcAngle + 0.8) * arcLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, ax1, ay1)
                nvgLineTo(vg, ax2, ay2)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 180, math.floor(warnAlpha * 0.7)))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.02))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            end
        end

        -- ============================================================
        -- 阶段B：雷柱劈下 (0.20 - 0.35)
        -- 粗壮闪电从天空直劈地面，瞬间出现
        -- ============================================================
        local strikeT = 0.28   -- 雷击时刻
        if t >= 0.20 and t < 0.65 then
            -- 雷柱出现进度（快速出现）
            local boltLife
            if t < strikeT then
                -- 预现阶段：逐渐显现
                boltLife = (t - 0.20) / (strikeT - 0.20)
            else
                boltLife = 1.0
            end
            -- 淡出
            local boltAlpha = 255
            if t < strikeT then
                boltAlpha = math.floor(255 * boltLife * boltLife)
            elseif t > 0.45 then
                boltAlpha = math.floor(255 * (1.0 - (t - 0.45) / 0.20))
            end
            if boltAlpha < 3 then goto skip_bolt end

            local jitterSeed = math.floor(time * 16)

            -- 生成粗壮锯齿形雷柱路径（16段，非常密集）
            local segments = 16
            local boltPoints = {}
            local perpX = -(tyP - skyY)
            local perpY = (txP - skyX)
            local perpLen = math.sqrt(perpX * perpX + perpY * perpY)
            if perpLen > 0.01 then
                perpX = perpX / perpLen
                perpY = perpY / perpLen
            end
            -- 雷柱从天到地延伸进度
            local extendT = math.min(1.0, boltLife * 2.5)
            for pi = 0, segments do
                local st = pi / segments
                if st > extendT and t < strikeT then goto skip_point end
                local bx = skyX + (txP - skyX) * st
                local by = skyY + (tyP - skyY) * st
                if pi > 0 and pi < segments then
                    -- 越靠近底部偏移越小（呈锥形收束）
                    local offsetScale = 1.0 - st * 0.4
                    local offsetMag = GS.CELL * 0.35 * math.sin(baseSeed + pi * 2.7 + jitterSeed * 0.35) * offsetScale
                    local envelop = math.sin(st * math.pi)
                    bx = bx + perpX * offsetMag * envelop
                    by = by + perpY * offsetMag * envelop
                end
                boltPoints[#boltPoints + 1] = { bx, by }
                ::skip_point::
            end

            if #boltPoints >= 2 then
                -- 最外层超宽辉光（蓝紫色弥散）
                nvgBeginPath(vg)
                nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
                for pi = 2, #boltPoints do
                    nvgLineTo(vg, boltPoints[pi][1], boltPoints[pi][2])
                end
                nvgStrokeColor(vg, nvgRGBA(140, 160, 255, math.floor(boltAlpha * 0.2)))
                nvgStrokeWidth(vg, math.max(18, GS.CELL * 0.40))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)

                -- 外层光晕（宽，电紫色）
                nvgBeginPath(vg)
                nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
                for pi = 2, #boltPoints do
                    nvgLineTo(vg, boltPoints[pi][1], boltPoints[pi][2])
                end
                nvgStrokeColor(vg, nvgRGBA(200, 200, 255, math.floor(boltAlpha * 0.35)))
                nvgStrokeWidth(vg, math.max(12, GS.CELL * 0.25))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)

                -- 中层主体（亮黄色粗壮雷柱）
                nvgBeginPath(vg)
                nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
                for pi = 2, #boltPoints do
                    nvgLineTo(vg, boltPoints[pi][1], boltPoints[pi][2])
                end
                nvgStrokeColor(vg, nvgRGBA(255, 245, 80, boltAlpha))
                nvgStrokeWidth(vg, math.max(6, GS.CELL * 0.12))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)

                -- 内核（纯白）
                nvgBeginPath(vg)
                nvgMoveTo(vg, boltPoints[1][1], boltPoints[1][2])
                for pi = 2, #boltPoints do
                    nvgLineTo(vg, boltPoints[pi][1], boltPoints[pi][2])
                end
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(boltAlpha * 0.9)))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)

                -- 8条分支闪电从主雷柱分叉
                for bi = 1, 8 do
                    local branchIdx = math.floor(1 + (bi / 9) * #boltPoints)
                    branchIdx = math.min(branchIdx, #boltPoints)
                    local bp = boltPoints[branchIdx]
                    local branchAngle = baseSeed + bi * 2.5 + jitterSeed * 0.4
                    local branchLen = GS.CELL * (0.25 + 0.15 * math.sin(branchAngle * 1.3))
                    local bex = bp[1] + math.cos(branchAngle) * branchLen
                    local bey = bp[2] + math.sin(branchAngle) * branchLen
                    local midBx = (bp[1] + bex) / 2 + math.sin(branchAngle * 2.7) * GS.CELL * 0.08
                    local midBy = (bp[2] + bey) / 2 + math.cos(branchAngle * 2.7) * GS.CELL * 0.08
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, bp[1], bp[2])
                    nvgLineTo(vg, midBx, midBy)
                    nvgLineTo(vg, bex, bey)
                    nvgStrokeColor(vg, nvgRGBA(255, 235, 120, math.floor(boltAlpha * 0.5)))
                    nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                    nvgLineCap(vg, NVG_ROUND)
                    nvgLineJoin(vg, NVG_ROUND)
                    nvgStroke(vg)
                end
            end
            ::skip_bolt::
        end

        -- ============================================================
        -- 阶段C：落地白色冲击闪光 (strikeT - strikeT+0.08)
        -- ============================================================
        if t >= strikeT and t < strikeT + 0.08 then
            local ct = (t - strikeT) / 0.08
            local flashR = maxR * (0.5 + 0.5 * ct)
            local flashAlpha = math.floor(220 * (1.0 - ct))
            local flashGrad = nvgRadialGradient(vg, txP, tyP, 0, flashR,
                nvgRGBA(255, 255, 240, flashAlpha),
                nvgRGBA(255, 240, 100, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, flashR)
            nvgFillPaint(vg, flashGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段D：电击冲击波环扩散 (strikeT - 0.65)
        -- 两层电弧冲击波
        -- ============================================================
        if t >= strikeT and t < 0.65 then
            local dt2 = (t - strikeT) / (0.65 - strikeT)
            -- 主冲击波环（亮黄色）
            local ringR = maxR * 0.2 + maxR * 0.8 * dt2
            local ringAlpha = math.floor(200 * (1.0 - dt2 * dt2))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, ringR)
            nvgStrokeColor(vg, nvgRGBA(255, 240, 60, ringAlpha))
            nvgStrokeWidth(vg, math.max(3, GS.CELL * 0.07) * (1.0 - dt2 * 0.5))
            nvgStroke(vg)

            -- 内层冲击波（白色，稍快）
            local innerR = maxR * 0.15 + maxR * 0.9 * math.min(1.0, dt2 * 1.3)
            local innerAlpha = math.floor(150 * math.max(0, 1.0 - dt2 * 1.5))
            if innerAlpha > 3 then
                nvgBeginPath(vg)
                nvgCircle(vg, txP, tyP, innerR)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, innerAlpha))
                nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.04))
                nvgStroke(vg)
            end

            -- 冲击波上的跳动电弧（6条）
            for i = 1, 6 do
                local arcAngle = (i / 6) * math.pi * 2 + time * 12 + baseSeed
                local a1x = txP + math.cos(arcAngle) * ringR
                local a1y = tyP + math.sin(arcAngle) * ringR
                local arcLen = GS.CELL * 0.2 * (1.0 - dt2)
                local a2x = a1x + math.cos(arcAngle + 1.2) * arcLen
                local a2y = a1y + math.sin(arcAngle + 1.2) * arcLen
                local arcMx = (a1x + a2x) / 2 + math.sin(time * 20 + i) * GS.CELL * 0.05
                local arcMy = (a1y + a2y) / 2 + math.cos(time * 20 + i) * GS.CELL * 0.05
                nvgBeginPath(vg)
                nvgMoveTo(vg, a1x, a1y)
                nvgLineTo(vg, arcMx, arcMy)
                nvgLineTo(vg, a2x, a2y)
                nvgStrokeColor(vg, nvgRGBA(255, 240, 140, math.floor(ringAlpha * 0.5)))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.02))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            end
        end

        -- ============================================================
        -- 阶段E：地面焦灼电弧痕迹 (strikeT - 0.85)
        -- ============================================================
        if t >= strikeT and t < 0.85 then
            local et = (t - strikeT) / (0.85 - strikeT)
            local scorchR = GS.CELL * 0.4
            local scorchAlpha = math.floor(80 * (1.0 - et))
            local scorchGrad = nvgRadialGradient(vg, txP, tyP, 0, scorchR,
                nvgRGBA(255, 220, 60, scorchAlpha),
                nvgRGBA(200, 160, 40, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, scorchR)
            nvgFillPaint(vg, scorchGrad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段F：飞散电弧粒子 (strikeT - 0.80)
        -- 20颗带电粒子从落点飞散
        -- ============================================================
        if t >= strikeT and t < 0.80 then
            local ft = (t - strikeT) / (0.80 - strikeT)
            for i = 1, 20 do
                local seed1 = i * 137.508
                local seed2 = i * 73.137 + baseSeed
                local angle = seed1 % (math.pi * 2)
                local delay = (seed2 % 8) * 0.012
                local localT = math.max(0, ft - delay)
                if localT > 0 and localT < 1.0 then
                    local speed = 0.4 + (seed2 % 5) * 0.15
                    local easeT = 1.0 - (1.0 - localT) * (1.0 - localT)
                    local dist = maxR * 0.8 * easeT * speed
                    local pX = txP + math.cos(angle) * dist
                    local pY = tyP + math.sin(angle) * dist
                    -- 带电粒子微微跳跃
                    pY = pY - math.sin(localT * math.pi) * GS.CELL * 0.15
                    local pSize = math.max(1.5, GS.CELL * 0.03) * (1.0 - localT * 0.5)
                    local pAlpha = math.floor(200 * (1.0 - localT))
                    -- 黄白交替
                    if i % 2 == 0 then
                        nvgBeginPath(vg)
                        nvgCircle(vg, pX, pY, pSize)
                        nvgFillColor(vg, nvgRGBA(255, 245, 120, pAlpha))
                        nvgFill(vg)
                    else
                        nvgBeginPath(vg)
                        nvgCircle(vg, pX, pY, pSize * 0.8)
                        nvgFillColor(vg, nvgRGBA(255, 255, 220, pAlpha))
                        nvgFill(vg)
                    end

                    -- 粒子拖尾小电弧
                    if localT < 0.6 then
                        local tailLen = GS.CELL * 0.08 * (1.0 - localT)
                        local tailAngle = angle + math.pi + math.sin(time * 15 + i) * 0.5
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, pX, pY)
                        nvgLineTo(vg, pX + math.cos(tailAngle) * tailLen, pY + math.sin(tailAngle) * tailLen)
                        nvgStrokeColor(vg, nvgRGBA(255, 240, 100, math.floor(pAlpha * 0.4)))
                        nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.015))
                        nvgLineCap(vg, NVG_ROUND)
                        nvgStroke(vg)
                    end
                end
            end
        end

        -- ============================================================
        -- 阶段G：残留电弧辉光消散 (0.70 - 1.0)
        -- ============================================================
        if t >= 0.70 then
            local gt2 = (t - 0.70) / 0.30
            local glowR = GS.CELL * 0.35 * (1.0 - gt2 * 0.3)
            local glowAlpha = math.floor(60 * (1.0 - gt2))
            local glowGrad = nvgRadialGradient(vg, txP, tyP, 0, glowR,
                nvgRGBA(255, 240, 80, glowAlpha),
                nvgRGBA(200, 180, 40, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, glowR)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)

            -- 残留跳动小电弧（3条，逐渐消失）
            for i = 1, 3 do
                local arcAngle = (i / 3) * math.pi * 2 + time * 5 + baseSeed
                local arcDist = GS.CELL * 0.2 * (1.0 - gt2)
                local arcX = txP + math.cos(arcAngle) * arcDist
                local arcY = tyP + math.sin(arcAngle) * arcDist
                local arcLen = GS.CELL * 0.1 * (1.0 - gt2)
                local arcEx = arcX + math.cos(arcAngle + 1.5) * arcLen
                local arcEy = arcY + math.sin(arcAngle + 1.5) * arcLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, arcX, arcY)
                nvgLineTo(vg, arcEx, arcEy)
                nvgStrokeColor(vg, nvgRGBA(255, 240, 120, math.floor(glowAlpha * 0.6)))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.015))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：暴风雪冰锥坠落特效（大量冰锥从天而降，微倾斜，落地寒气+震动）
-- ====================================================================
function M.drawBlizzardIceEffects()
    local vg = M.vg
    local cell = GS.CELL
    for _, e in ipairs(GS.blizzardIceEffects) do
        local t = safeProgress(e.timer, e.duration)
        local radius = e.radius or 2
        -- 区域中心像素坐标
        local ccx = GS.BOARD_X + (e.cx - 1) * cell + cell / 2
        local ccy = GS.BOARD_Y + (e.cy - 1) * cell + cell / 2
        local pixR = (radius + 0.5) * cell

        -- Phase A (0.0~0.5): 冰锥从天空坠落
        -- Phase B (0.35~0.8): 落地冲击寒气扩散
        -- Phase C (0.6~1.0): 残留冰雾消散

        local iceCount = 30

        -- ======== Phase A: 冰锥坠落 ========
        if t < 0.65 then
            for k = 1, iceCount do
                local seed = k * 137.508
                -- 每根冰锥随机目标位置（在区域圆内）
                local angSeed = math.rad(seed)
                local distSeed = pixR * (((seed * 3.7) % 1.0) * 0.85 + 0.05)
                local destX = ccx + math.cos(angSeed) * distSeed
                local destY = ccy + math.sin(angSeed) * distSeed

                -- 从上方坠落（稍微偏斜，从左上到右下方向）
                local tiltX = cell * 0.8
                local fallHeight = cell * 5.0
                -- 每根冰锥有不同延迟（0~0.25）
                local delay = ((seed * 2.3) % 1.0) * 0.25
                local localT = math.max(0, (e.timer - delay) / (e.duration * 0.45))
                localT = math.min(1.0, localT)
                -- 缓入加速坠落
                local easeT = localT * localT

                local curX = destX - tiltX * (1.0 - easeT)
                local curY = destY - fallHeight * (1.0 - easeT)

                -- 冰锥透明度（坠落中逐渐变实，落地后淡出）
                local alpha
                if localT < 1.0 then
                    alpha = math.floor(60 + 180 * localT)
                else
                    local fadeT = math.max(0, (t - 0.5) / 0.15)
                    alpha = math.floor(240 * math.max(0, 1.0 - fadeT))
                end
                if alpha <= 0 then goto continueIce end

                -- 冰锥尺寸（菱形体：上半短钝，下半长尖朝地面）
                local iceLen = cell * (0.20 + ((seed * 5.1) % 1.0) * 0.14)
                local iceW = cell * 0.045
                -- 旋转角度：让菱形尖端（Y+方向）对齐坠落方向（偏右下）
                -- NanoVG 正角度使底端偏左，需取负值使尖端偏右对齐坠落方向
                local iceAngle = -math.atan(tiltX, fallHeight) + ((seed * 1.9) % 1.0) * math.rad(10) - math.rad(5)

                -- 坠落方向向量（用于拖尾）
                local dirX = tiltX
                local dirY = fallHeight
                local dirLen = math.sqrt(dirX * dirX + dirY * dirY)
                dirX = dirX / dirLen
                dirY = dirY / dirLen

                -- ======== 寒气拖尾（坠落中显示） ========
                if localT < 1.0 and localT > 0.05 then
                    local tailLen = iceLen * (1.8 + ((seed * 2.7) % 1.0) * 1.2)
                    local tailAlpha = math.floor(alpha * 0.5 * (1.0 - localT * 0.6))
                    -- 拖尾起点 = 冰锥当前位置，终点 = 冰锥后方（坠落反方向）
                    local tailX = curX - dirX * tailLen
                    local tailY = curY - dirY * tailLen
                    -- 渐变拖尾线（粗→细）
                    local trailGrad = nvgLinearGradient(vg, curX, curY, tailX, tailY,
                        nvgRGBA(140, 210, 255, tailAlpha),
                        nvgRGBA(100, 180, 255, 0))
                    nvgBeginPath(vg)
                    -- 拖尾用细长梯形表示寒气流
                    local perpX = -dirY
                    local perpY = dirX
                    local w1 = iceW * 0.8   -- 靠近冰锥的宽度
                    local w2 = iceW * 0.1   -- 尾端的宽度
                    nvgMoveTo(vg, curX + perpX * w1, curY + perpY * w1)
                    nvgLineTo(vg, curX - perpX * w1, curY - perpY * w1)
                    nvgLineTo(vg, tailX - perpX * w2, tailY - perpY * w2)
                    nvgLineTo(vg, tailX + perpX * w2, tailY + perpY * w2)
                    nvgClosePath(vg)
                    nvgFillPaint(vg, trailGrad)
                    nvgFill(vg)
                end

                -- ======== 绘制冰锥（菱形体：四顶点，上钝下尖） ========
                nvgSave(vg)
                nvgTranslate(vg, curX, curY)
                nvgRotate(vg, iceAngle)

                -- 菱形体：上端钝（短），下端尖（长，朝地面）
                local topLen = iceLen * 0.3   -- 上半部分短
                local botLen = iceLen * 0.7   -- 下半部分长（尖端朝地面）
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -topLen)         -- 上顶点（钝端）
                nvgLineTo(vg, -iceW, 0)           -- 左腰
                nvgLineTo(vg, 0, botLen)           -- 下顶点（尖端，朝地面）
                nvgLineTo(vg, iceW, 0)             -- 右腰
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(160, 220, 255, alpha))
                nvgFill(vg)

                -- 冰锥边缘
                nvgStrokeWidth(vg, cell * 0.008)
                nvgStrokeColor(vg, nvgRGBA(200, 240, 255, math.floor(alpha * 0.4)))
                nvgStroke(vg)

                -- 中心高光线（从上端到中部）
                nvgBeginPath(vg)
                nvgMoveTo(vg, 0, -topLen)
                nvgLineTo(vg, 0, botLen * 0.3)
                nvgStrokeWidth(vg, cell * 0.012)
                nvgStrokeColor(vg, nvgRGBA(220, 245, 255, math.floor(alpha * 0.6)))
                nvgStroke(vg)

                nvgRestore(vg)
                ::continueIce::
            end
        end

        -- ======== Phase B: 落地冲击寒气 ========
        if t > 0.35 and t < 0.85 then
            local impactT = (t - 0.35) / 0.5
            -- 中心冲击波环
            local ringR = pixR * 0.3 + pixR * 0.8 * impactT
            local ringAlpha = math.floor(140 * math.max(0, 1.0 - impactT))
            nvgBeginPath(vg)
            nvgCircle(vg, ccx, ccy, ringR)
            nvgStrokeWidth(vg, cell * 0.06 * (1.0 - impactT * 0.5))
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, ringAlpha))
            nvgStroke(vg)

            -- 地面寒霜扩散（径向渐变填充）
            local frostAlpha = math.floor(60 * math.max(0, 1.0 - impactT * 1.2))
            if frostAlpha > 0 then
                local frostPaint = nvgRadialGradient(vg, ccx, ccy, 0, pixR * (0.5 + 0.5 * impactT),
                    nvgRGBA(80, 160, 255, frostAlpha),
                    nvgRGBA(40, 100, 220, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, ccx, ccy, pixR * (0.5 + 0.5 * impactT))
                nvgFillPaint(vg, frostPaint)
                nvgFill(vg)
            end

            -- 飞溅碎冰粒子
            local splashCount = 12
            for k = 1, splashCount do
                local sa = math.rad(k * 137.508 + 30)
                local sd = pixR * (0.2 + 0.7 * impactT) * (0.6 + ((k * 3.7) % 1.0) * 0.4)
                local sx = ccx + math.cos(sa) * sd
                local sy = ccy + math.sin(sa) * sd - cell * 0.2 * math.max(0, 1.0 - impactT * 2)
                local sr = cell * 0.025 * math.max(0, 1.0 - impactT)
                local salpha = math.floor(160 * math.max(0, 1.0 - impactT * 1.3))
                if salpha > 0 and sr > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, sr)
                    nvgFillColor(vg, nvgRGBA(180, 230, 255, salpha))
                    nvgFill(vg)
                end
            end
        end

        -- ======== Phase C: 残留冰雾消散 ========
        if t > 0.6 then
            local fadeT = (t - 0.6) / 0.4
            local fogAlpha = math.floor(35 * math.max(0, 1.0 - fadeT))
            if fogAlpha > 0 then
                for k = 1, 6 do
                    local fa = math.rad(k * 60 + e.timer * 40)
                    local fd = pixR * (0.3 + 0.3 * fadeT)
                    local fx = ccx + math.cos(fa) * fd
                    local fy = ccy + math.sin(fa) * fd
                    local fr = cell * (0.15 + 0.1 * fadeT)
                    local fogPaint = nvgRadialGradient(vg, fx, fy, 0, fr,
                        nvgRGBA(140, 200, 255, fogAlpha),
                        nvgRGBA(100, 160, 255, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, fx, fy, fr)
                    nvgFillPaint(vg, fogPaint)
                    nvgFill(vg)
                end
            end
        end
    end
end

-- ====================================================================
-- 绘制：火焰护盾烧伤特效（怪物身上火焰灼烧动画）
-- ====================================================================
function M.drawBurnEffects()
    local vg = M.vg
    local cell = GS.CELL
    for _, e in ipairs(GS.burnEffects) do
        local t = safeProgress(e.timer, e.duration)
        -- 怪物中心坐标
        local cx = GS.BOARD_X + (e.x - 1) * cell + cell / 2
        local cy = GS.BOARD_Y + (e.y - 1) * cell + cell / 2

        -- 整体透明度包络（淡入→持续→淡出）
        local envelope
        if t < 0.1 then
            envelope = t / 0.1
        elseif t > 0.7 then
            envelope = math.max(0, (1.0 - t) / 0.3)
        else
            envelope = 1.0
        end

        -- ① 身体发红发光底色
        local glowAlpha = math.floor(50 * envelope)
        if glowAlpha > 0 then
            local glowPaint = nvgRadialGradient(vg, cx, cy, cell * 0.05, cell * 0.45,
                nvgRGBA(255, 80, 20, glowAlpha),
                nvgRGBA(255, 40, 0, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, cell * 0.45)
            nvgFillPaint(vg, glowPaint)
            nvgFill(vg)
        end

        -- ② 火焰粒子（从身体各处升起）
        local flameCount = 8
        for k = 1, flameCount do
            local seed = k * 137.508
            -- 基础位置（围绕身体）
            local baseAngle = math.rad(seed) + e.timer * 2.0
            local baseDist = cell * (0.08 + ((seed * 3.1) % 1.0) * 0.22)
            local fx = cx + math.cos(baseAngle) * baseDist
            -- 火焰上升
            local riseSpeed = cell * (0.6 + ((seed * 2.7) % 1.0) * 0.4)
            local risePhase = (e.timer * riseSpeed / cell + (seed * 0.1)) % 1.0
            local fy = cy + cell * 0.15 - risePhase * cell * 0.5

            -- 火焰大小随上升逐渐缩小
            local fSize = cell * (0.06 + 0.04 * (1.0 - risePhase)) * envelope
            if fSize <= 0 then goto continueBurn end

            -- 颜色从黄→橙→红随上升变化
            local cr = 255
            local cg = math.floor(200 - 150 * risePhase)
            local cb = math.floor(40 * (1.0 - risePhase))
            local fa = math.floor((160 + 60 * (1.0 - risePhase)) * envelope)

            -- 火焰形状（泪滴形：圆 + 顶部尖角）
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, fSize)
            nvgFillColor(vg, nvgRGBA(cr, cg, cb, fa))
            nvgFill(vg)
            -- 火焰尖端
            nvgBeginPath(vg)
            nvgMoveTo(vg, fx - fSize * 0.6, fy)
            nvgLineTo(vg, fx, fy - fSize * 2.2)
            nvgLineTo(vg, fx + fSize * 0.6, fy)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(cr, cg + 30, cb + 20, math.floor(fa * 0.7)))
            nvgFill(vg)
            ::continueBurn::
        end

        -- ③ 灼烧火花（快速向外飞溅的小点）
        if t < 0.6 then
            local sparkCount = 6
            for k = 1, sparkCount do
                local sa = math.rad(k * 60 + e.timer * 200)
                local sparkT = (e.timer * 3 + k * 0.15) % 1.0
                local sd = cell * (0.1 + 0.35 * sparkT)
                local sx = cx + math.cos(sa) * sd
                local sy = cy + math.sin(sa) * sd - cell * 0.15 * sparkT
                local sr = cell * 0.018 * (1.0 - sparkT) * envelope
                local salpha = math.floor(200 * (1.0 - sparkT) * envelope)
                if sr > 0 and salpha > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, sr)
                    nvgFillColor(vg, nvgRGBA(255, 220, 80, salpha))
                    nvgFill(vg)
                end
            end
        end

        -- ④ 烟雾尾迹（后半段）
        if t > 0.4 then
            local smokeT = (t - 0.4) / 0.6
            local smokeCount = 4
            for k = 1, smokeCount do
                local sa = math.rad(k * 90 + 20)
                local sd = cell * 0.1
                local sx = cx + math.cos(sa) * sd
                local sy = cy - cell * 0.15 - cell * 0.25 * smokeT
                local sr = cell * (0.06 + 0.08 * smokeT)
                local salpha = math.floor(40 * math.max(0, 1.0 - smokeT * 1.3))
                if salpha > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, sr)
                    nvgFillColor(vg, nvgRGBA(80, 60, 50, salpha))
                    nvgFill(vg)
                end
            end
        end
    end
end

-- ====================================================================
-- 绘制：雷云攻击闪电特效（从云底劈下大量闪电+地面静电）
-- ====================================================================
function M.drawThunderCloudStrikeEffects()
    local vg = M.vg
    local cell = GS.CELL
    for _, e in ipairs(GS.thunderCloudStrikeEffects) do
        local t = safeProgress(e.timer, e.duration)
        -- 目标格中心坐标
        local gx = GS.BOARD_X + (e.x - 1) * cell + cell / 2
        local gy = GS.BOARD_Y + (e.y - 1) * cell + cell / 2
        -- 雷云位置（在格子上方）
        local cloudY = gy - cell * 0.2
        -- AOE 区域半径（像素，动态范围）
        local aoeSpread = cell * ((e.radius or 1) + 0.3)

        -- Phase A (0.0~0.08): 云底闪光预警
        -- Phase B (0.06~0.5): 多条闪电从云底劈向地面（覆盖3×3）
        -- Phase C (0.15~0.7): 地面静电效果（覆盖3×3）
        -- Phase D (0.5~1.0): 残留电弧消散

        local boltCount = 9

        -- ======== Phase A: 云底闪光 ========
        if t < 0.15 then
            local flashT = t / 0.15
            local flashA = math.floor(160 * (1.0 - flashT * 0.5))
            local flashPaint = nvgRadialGradient(vg, gx, cloudY + cell * 0.15, 0, aoeSpread,
                nvgRGBA(255, 240, 100, flashA),
                nvgRGBA(200, 180, 50, 0))
            nvgBeginPath(vg)
            nvgEllipse(vg, gx, cloudY + cell * 0.15, aoeSpread, cell * 0.5)
            nvgFillPaint(vg, flashPaint)
            nvgFill(vg)
        end

        -- ======== Phase B: 闪电劈下（散布到3×3区域） ========
        if t > 0.05 and t < 0.55 then
            local boltT = (t - 0.05) / 0.45
            for k = 1, boltCount do
                local seed = k * 137.508
                -- 每条闪电有不同延迟
                local delay = ((seed * 2.1) % 1.0) * 0.15
                local localT = math.max(0, (e.timer - e.duration * 0.05 - delay) / (e.duration * 0.35))
                localT = math.min(1.0, localT)
                if localT <= 0 then goto continueBolt end

                -- 闪电起点（云底，扩散范围内）
                local boltSX = gx + aoeSpread * 0.5 * math.sin(seed + k * 1.1)
                local boltSY = cloudY + cell * 0.15
                -- 闪电终点（地面附近，散布在3×3区域内）
                local boltEX = gx + aoeSpread * math.sin(seed * 2.3 + k * 0.7) * 0.8
                local boltEY = gy + cell * 0.35 + cell * 0.3 * math.cos(seed * 1.5)

                -- 闪电延伸进度
                local extendT = math.min(1.0, localT * 3.0)
                local curEX = boltSX + (boltEX - boltSX) * extendT
                local curEY = boltSY + (boltEY - boltSY) * extendT

                -- 闪电透明度
                local boltAlpha
                if localT < 0.5 then
                    boltAlpha = math.floor(220 + 35 * localT)
                else
                    boltAlpha = math.floor(255 * math.max(0, 1.0 - (localT - 0.5) / 0.5))
                end
                if boltAlpha <= 0 then goto continueBolt end

                -- 绘制多段折线闪电（6段）
                local segments = 6
                local prevX, prevY = boltSX, boltSY
                nvgBeginPath(vg)
                nvgMoveTo(vg, prevX, prevY)
                for s = 1, segments do
                    local st = s / segments
                    local baseX = boltSX + (curEX - boltSX) * st
                    local baseY = boltSY + (curEY - boltSY) * st
                    -- 锯齿偏移（中间段偏移大，两端小）
                    local jitter = cell * 0.08 * math.sin(st * math.pi) * math.sin(seed * 3 + s * 7.7 + e.timer * 30)
                    local nx = baseX + jitter
                    local ny = baseY
                    nvgLineTo(vg, nx, ny)
                    prevX, prevY = nx, ny
                end
                -- 外层发光
                nvgStrokeWidth(vg, cell * 0.06)
                nvgStrokeColor(vg, nvgRGBA(100, 80, 255, math.floor(boltAlpha * 0.35)))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)
                -- 黄色主体
                nvgBeginPath(vg)
                prevX, prevY = boltSX, boltSY
                nvgMoveTo(vg, prevX, prevY)
                for s = 1, segments do
                    local st = s / segments
                    local baseX = boltSX + (curEX - boltSX) * st
                    local baseY = boltSY + (curEY - boltSY) * st
                    local jitter = cell * 0.08 * math.sin(st * math.pi) * math.sin(seed * 3 + s * 7.7 + e.timer * 30)
                    nvgLineTo(vg, baseX + jitter, baseY)
                end
                nvgStrokeWidth(vg, cell * 0.03)
                nvgStrokeColor(vg, nvgRGBA(255, 240, 80, boltAlpha))
                nvgLineCap(vg, NVG_ROUND)
                nvgLineJoin(vg, NVG_ROUND)
                nvgStroke(vg)
                -- 白色核心
                nvgBeginPath(vg)
                prevX, prevY = boltSX, boltSY
                nvgMoveTo(vg, prevX, prevY)
                for s = 1, segments do
                    local st = s / segments
                    local baseX = boltSX + (curEX - boltSX) * st
                    local baseY = boltSY + (curEY - boltSY) * st
                    local jitter = cell * 0.08 * math.sin(st * math.pi) * math.sin(seed * 3 + s * 7.7 + e.timer * 30)
                    nvgLineTo(vg, baseX + jitter, baseY)
                end
                nvgStrokeWidth(vg, cell * 0.012)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(boltAlpha * 0.8)))
                nvgStroke(vg)

                -- 闪电落点火花（当延伸完成后）
                if extendT >= 0.95 then
                    local sparkA = math.floor(boltAlpha * 0.8)
                    nvgBeginPath(vg)
                    nvgCircle(vg, curEX, curEY, cell * 0.04)
                    nvgFillColor(vg, nvgRGBA(255, 255, 200, sparkA))
                    nvgFill(vg)
                end
                ::continueBolt::
            end
        end

        -- ======== Phase C: 地面静电效果（覆盖3×3区域） ========
        if t > 0.12 and t < 0.75 then
            local staticT = (t - 0.12) / 0.63
            local staticAlpha = math.floor(180 * math.max(0, 1.0 - staticT * 1.2))

            -- 静电环扩散（覆盖3×3）
            local staticR = aoeSpread * (0.3 + 0.7 * staticT)
            if staticAlpha > 0 then
                nvgBeginPath(vg)
                nvgCircle(vg, gx, gy + cell * 0.3, staticR)
                nvgStrokeWidth(vg, cell * 0.03 * (1.0 - staticT * 0.5))
                nvgStrokeColor(vg, nvgRGBA(200, 200, 255, staticAlpha))
                nvgStroke(vg)
            end

            -- 地面电弧跳跃（散布在3×3区域内）
            local arcCount = 12
            for k = 1, arcCount do
                local seed = k * 97.3
                local arcPhase = (e.timer * (6.0 + k * 1.3) + seed) % 1.5
                if arcPhase < 0.1 then
                    local sa = math.rad(seed * 5 + e.timer * 80)
                    local sd = aoeSpread * (0.2 + 0.6 * ((seed * 1.7) % 1.0))
                    local sx = gx + math.cos(sa) * sd
                    local sy = gy + cell * 0.3 + math.sin(sa) * sd * 0.3
                    local ea = sa + math.rad(30 + ((seed * 2.3) % 1.0) * 50)
                    local ed = sd * 0.7
                    local ex = gx + math.cos(ea) * ed
                    local ey = gy + cell * 0.3 + math.sin(ea) * ed * 0.3

                    local arcA = math.floor(staticAlpha * 0.9)
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, sx, sy)
                    nvgLineTo(vg, (sx + ex) * 0.5 + cell * 0.03 * math.sin(e.timer * 50 + k), (sy + ey) * 0.5)
                    nvgLineTo(vg, ex, ey)
                    nvgStrokeWidth(vg, cell * 0.015)
                    nvgStrokeColor(vg, nvgRGBA(180, 200, 255, arcA))
                    nvgLineCap(vg, NVG_ROUND)
                    nvgStroke(vg)
                end
            end

            -- 静电火花粒子（散布在3×3区域内）
            local sparkCount = 15
            for k = 1, sparkCount do
                local seed = k * 137.508 + 50
                local sparkPhase = (e.timer * 4 + seed * 0.1) % 1.0
                local sa = math.rad(seed * 3)
                local sd = aoeSpread * (0.15 + 0.6 * sparkPhase) * (0.5 + ((seed * 2.7) % 1.0) * 0.5)
                local sx = gx + math.cos(sa) * sd
                local sy = gy + cell * 0.3 + math.sin(sa) * sd * 0.3 - cell * 0.1 * sparkPhase
                local sr = cell * 0.015 * (1.0 - sparkPhase)
                local spa = math.floor(staticAlpha * (1.0 - sparkPhase))
                if sr > 0 and spa > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, sr)
                    nvgFillColor(vg, nvgRGBA(220, 230, 255, spa))
                    nvgFill(vg)
                end
            end
        end

        -- ======== Phase D: 残留电弧消散 ========
        if t > 0.55 then
            local fadeT = (t - 0.55) / 0.45
            local fadeAlpha = math.floor(60 * math.max(0, 1.0 - fadeT))
            if fadeAlpha > 0 then
                for k = 1, 3 do
                    local seed = k * 73.1
                    local sa = math.rad(seed + e.timer * 15)
                    local sx = gx + cell * 0.12 * math.cos(sa)
                    local sy = gy + cell * 0.1
                    local ey = cloudY + cell * 0.2
                    local arcH = sy - ey
                    -- 简单的残留弧线
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, sx, sy)
                    nvgLineTo(vg, sx + cell * 0.04 * math.sin(e.timer * 10 + k), (sy + ey) * 0.5)
                    nvgLineTo(vg, sx - cell * 0.02, ey)
                    nvgStrokeWidth(vg, cell * 0.012)
                    nvgStrokeColor(vg, nvgRGBA(200, 200, 255, fadeAlpha))
                    nvgLineCap(vg, NVG_ROUND)
                    nvgStroke(vg)
                end
            end
        end
    end
end

-- ====================================================================
-- 绘制：泼沙致盲特效（沙粒从攻击者飞向目标，0.7秒）
-- ====================================================================
function M.drawSandBlindEffects()
    local vg = M.vg
    for _, e in ipairs(GS.sandBlindEffects) do
        local t = safeProgress(e.timer, e.duration)
        -- 攻击者中心坐标
        local fxP = GS.BOARD_X + (e.fx - 0.5) * GS.CELL
        local fyP = GS.BOARD_Y + (e.fy - 0.5) * GS.CELL
        -- 目标中心坐标
        local txP = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local tyP = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local dx = txP - fxP
        local dy = tyP - fyP

        -- ============================================================
        -- 阶段1：手部扬沙动作（0.0 - 0.2）
        -- ============================================================
        if t < 0.2 then
            local ct = t / 0.2
            local burstR = GS.CELL * 0.15 + GS.CELL * 0.3 * ct
            local burstA = math.floor(180 * ct)
            local grad = nvgRadialGradient(vg, fxP, fyP, 0, burstR,
                nvgRGBA(210, 190, 130, burstA),
                nvgRGBA(180, 160, 100, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, fxP, fyP, burstR)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end

        -- ============================================================
        -- 阶段2：沙粒飞行（0.1 - 0.7）
        -- ============================================================
        if t >= 0.1 then
            local st = (t - 0.1) / 0.9
            local particleCount = 20
            for i = 1, particleCount do
                local seed = i * 73.7
                -- 每个沙粒有不同的飞行进度（前后错开）
                local delay = (i / particleCount) * 0.3
                local pt = (st - delay) / (1 - delay)
                if pt > 0 and pt <= 1 then
                    -- 沙粒沿方向飞行，加上随机散布
                    local spread = GS.CELL * 0.3 * math.sin(seed * 2.1)
                    local perpX = -dy  -- 垂直于飞行方向的散布
                    local perpY = dx
                    local len = math.sqrt(perpX * perpX + perpY * perpY)
                    if len > 0 then perpX = perpX / len; perpY = perpY / len end
                    local px = fxP + dx * pt + perpX * spread * (1 - pt * 0.5)
                    local py = fyP + dy * pt + perpY * spread * (1 - pt * 0.5)
                    -- 重力微下坠
                    py = py - GS.CELL * 0.15 * math.sin(pt * math.pi)
                    -- 透明度：飞行中浓，到达后淡出
                    local alpha
                    if pt < 0.3 then
                        alpha = pt / 0.3
                    elseif pt > 0.7 then
                        alpha = (1 - pt) / 0.3
                    else
                        alpha = 1.0
                    end
                    alpha = math.floor(alpha * 200)
                    -- 沙粒大小（随机变化）
                    local size = 1.2 + math.sin(seed * 0.6) * 0.8
                    -- 沙土色系（黄褐色随机偏移）
                    local cr = math.floor(190 + math.sin(seed * 1.3) * 30)
                    local cg = math.floor(170 + math.sin(seed * 0.9) * 25)
                    local cb = math.floor(100 + math.sin(seed * 1.7) * 30)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px, py, size)
                    nvgFillColor(vg, nvgRGBA(cr, cg, cb, alpha))
                    nvgFill(vg)
                end
            end
        end

        -- ============================================================
        -- 阶段3：目标处沙尘爆散（0.4 - 1.0）
        -- ============================================================
        if t >= 0.4 then
            local et = (t - 0.4) / 0.6
            -- 沙尘云团
            local cloudR = GS.CELL * 0.25 + GS.CELL * 0.2 * et
            local cloudA = math.floor(140 * (1 - et))
            local cloudGrad = nvgRadialGradient(vg, txP, tyP, 0, cloudR,
                nvgRGBA(200, 180, 120, cloudA),
                nvgRGBA(180, 160, 100, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, txP, tyP, cloudR)
            nvgFillPaint(vg, cloudGrad)
            nvgFill(vg)
            -- 散落小沙粒
            local sparkCount = 8
            for i = 1, sparkCount do
                local angle = (i / sparkCount) * math.pi * 2 + i * 1.2
                local dist = GS.CELL * 0.15 + GS.CELL * 0.3 * et
                local sx = txP + math.cos(angle) * dist
                local sy = tyP + math.sin(angle) * dist
                local sa = math.floor(160 * (1 - et))
                local ss = 1.0 + math.sin(i * 2.3) * 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, ss * (1 - et * 0.5))
                nvgFillColor(vg, nvgRGBA(210, 190, 130, sa))
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：顺劈溅射特效（朝攻击方向的半圆扩散弧，一粗一细）
-- ====================================================================
function M.drawCleaveEffects()
    local vg = M.vg
    for _, e in ipairs(GS.cleaveEffects) do
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local t = safeProgress(e.timer, e.duration)

        -- 攻击方向角度（fdx,fdy 是格子方向，屏幕坐标 y 向下）
        local dirAngle = math.atan(e.fdy, e.fdx)

        -- 扩散半径：从小到大
        local maxR = GS.CELL * 1.5
        local curR = maxR * 0.2 + maxR * 0.8 * t

        -- 透明度：快速出现，后半段淡出
        local alpha
        if t < 0.25 then
            alpha = t / 0.25
        elseif t > 0.5 then
            alpha = (1 - t) / 0.5
        else
            alpha = 1.0
        end

        -- 半圆弧角度范围（以攻击方向为中心，左右各90度 = 180度半圆）
        local halfArc = math.pi * 0.5
        local startA = dirAngle - halfArc
        local endA = dirAngle + halfArc

        nvgSave(vg)
        nvgTranslate(vg, cx, cy)

        -- 粗弧线（外层光晕，柔和红色）
        local thickAlpha = math.floor(alpha * 140)
        local thickW = math.max(4, GS.CELL * 0.14 * (1 - t * 0.4))
        nvgBeginPath(vg)
        nvgArc(vg, 0, 0, curR, startA, endA, 2)
        nvgStrokeColor(vg, nvgRGBA(220, 70, 50, thickAlpha))
        nvgStrokeWidth(vg, thickW)
        nvgStroke(vg)

        -- 细弧线（内层亮线，更亮的红色，半径稍小）
        local innerR = curR * 0.7
        local thinAlpha = math.floor(alpha * 200)
        local thinW = math.max(1.5, GS.CELL * 0.05 * (1 - t * 0.3))
        nvgBeginPath(vg)
        nvgArc(vg, 0, 0, innerR, startA, endA, 2)
        nvgStrokeColor(vg, nvgRGBA(255, 120, 80, thinAlpha))
        nvgStrokeWidth(vg, thinW)
        nvgStroke(vg)

        nvgRestore(vg)
    end
end

-- ====================================================================
-- 绘制：深渊溅射特效（半圆扩散弧，橙色系，范围随 rangeBonus 扩大）
-- ====================================================================
function M.drawMeleeSplashEffects()
    local vg = M.vg
    for _, e in ipairs(GS.meleeSplashEffects) do
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local t = safeProgress(e.timer, e.duration)

        -- 攻击方向角度
        local dirAngle = math.atan(e.fdy, e.fdx)

        local rb = e.rangeBonus or 0
        local radius = (1.5 + rb * 0.75) * GS.CELL  -- 纵深+宽度同时扩展，半径增幅加大

        -- 透明度：快速出现，后半段淡出
        local alpha
        if t < 0.2 then
            alpha = t / 0.2
        elseif t > 0.45 then
            alpha = (1 - t) / 0.55
        else
            alpha = 1.0
        end

        -- 扩散进度
        local spread = 0.3 + 0.7 * t
        local curR = radius * spread

        -- 半圆弧：以攻击方向为中心，左右各展开 π/2（共 π，即半圆）
        local halfArc = math.pi * 0.5
        local startAngle = dirAngle - halfArc
        local endAngle   = dirAngle + halfArc

        -- 外层弧线光波（暖橙色）
        local outerAlpha = math.floor(alpha * 120)
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, curR, startAngle, endAngle, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(255, 160, 40, outerAlpha))
        nvgStrokeWidth(vg, math.max(3, GS.CELL * 0.12 * (1 - t * 0.4)))
        nvgStroke(vg)

        -- 内层填充扇形（半透明暖橙）
        local fillAlpha = math.floor(alpha * 50)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy)
        nvgArc(vg, cx, cy, curR * 0.85, startAngle, endAngle, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 180, 60, fillAlpha))
        nvgFill(vg)

        -- 扩散粒子点（在半圆范围内分布）
        local particleCount = 4 + rb * 2
        local particleAlpha = math.floor(alpha * 160)
        for i = 1, particleCount do
            local pAngle = startAngle + (endAngle - startAngle) * ((i - 0.5) / particleCount)
            local pDist = curR * (0.3 + 0.6 * math.abs(math.sin(t * math.pi + i * 2.3)))
            local px = cx + math.cos(pAngle) * pDist
            local py = cy + math.sin(pAngle) * pDist
            local dotR = math.max(1.5, GS.CELL * 0.04 * (1 - t * 0.5))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, dotR)
            nvgFillColor(vg, nvgRGBA(255, 220, 120, particleAlpha))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：哈雷努拉祝福/超度 AOE 区域特效（金色矩形光域，范围随技能扩展放大）
-- ====================================================================
function M.drawHolyAoeEffects()
    local vg = M.vg
    for _, e in ipairs(GS.holyAoeEffects) do
        local t = safeProgress(e.timer, e.duration)

        -- 攻击者中心坐标
        local ax = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local ay = GS.BOARD_Y + (e.y - 0.5) * GS.CELL

        local fdx, fdy = e.fdx, e.fdy
        local maxPerp  = e.maxPerp
        local maxDepth = e.maxDepth
        local enhanced = e.enhanced  -- 超度=true

        -- 垂直方向
        local ldx, ldy = -fdy, fdx

        -- 透明度：快速出现，后半段缓慢淡出
        local alpha
        if t < 0.15 then
            alpha = t / 0.15
        elseif t > 0.5 then
            alpha = (1 - t) / 0.5
        else
            alpha = 1.0
        end

        -- 扩散进度
        local spread = 0.3 + 0.7 * math.min(1, t / 0.3)

        -- 色系：超度更亮更白
        local cR, cG, cB
        if enhanced then
            cR, cG, cB = 255, 245, 200  -- 亮圣金偏白
        else
            cR, cG, cB = 255, 220, 100  -- 标准圣金
        end

        -- 绘制每个 AOE 格子的光域
        for depth = 1, maxDepth do
            for p = -maxPerp, maxPerp do
                local cx = e.x + fdx * depth + ldx * p
                local cy = e.y + fdy * depth + ldy * p

                local cellPx = GS.BOARD_X + (cx - 0.5) * GS.CELL
                local cellPy = GS.BOARD_Y + (cy - 0.5) * GS.CELL

                -- 距离衰减：越远越淡
                local dist = math.max(math.abs(depth), math.abs(p))
                local distFade = 1.0 - dist * 0.08

                -- 格子填充光域（半透明金色矩形）
                local cellSize = GS.CELL * spread
                local fillAlpha = math.floor(alpha * distFade * (enhanced and 55 or 40))
                nvgBeginPath(vg)
                nvgRect(vg, cellPx - cellSize / 2, cellPy - cellSize / 2, cellSize, cellSize)
                nvgFillColor(vg, nvgRGBA(cR, cG, cB, fillAlpha))
                nvgFill(vg)

                -- 格子边框发光
                local borderAlpha = math.floor(alpha * distFade * (enhanced and 100 or 70))
                nvgBeginPath(vg)
                nvgRect(vg, cellPx - cellSize / 2, cellPy - cellSize / 2, cellSize, cellSize)
                nvgStrokeColor(vg, nvgRGBA(cR, cG, cB, borderAlpha))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.03))
                nvgStroke(vg)
            end
        end

        -- 外层光晕：覆盖整个 AOE 区域的径向渐变
        local totalW = (2 * maxPerp + 1) * GS.CELL * spread
        local totalH = maxDepth * GS.CELL * spread
        -- AOE 区域中心
        local centerDepth = (1 + maxDepth) / 2
        local areaCx = ax + fdx * centerDepth * GS.CELL
        local areaCy = ay + fdy * centerDepth * GS.CELL
        local glowR = math.max(totalW, totalH) * 0.6
        local glowAlpha = math.floor(alpha * (enhanced and 50 or 35))
        local grad = nvgRadialGradient(vg, areaCx, areaCy, 0, glowR,
            nvgRGBA(cR, cG, cB, glowAlpha),
            nvgRGBA(cR, cG, cB, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, areaCx, areaCy, glowR)
        nvgFillPaint(vg, grad)
        nvgFill(vg)

        -- 神圣粒子：在 AOE 区域内随机分布上升的光点
        local particleCount = 3 + maxPerp * 2 + maxDepth
        local particleAlpha = math.floor(alpha * (enhanced and 180 or 140))
        for i = 1, particleCount do
            local seed = i * 1.618 + t * 2.0
            -- 粒子位置在 AOE 范围内
            local pDepth = 1 + (maxDepth - 1) * (math.abs(math.sin(seed * 3.7)) )
            local pPerp  = (math.sin(seed * 5.3)) * maxPerp
            local ppx = ax + fdx * pDepth * GS.CELL + ldx * pPerp * GS.CELL
            local ppy = ay + fdy * pDepth * GS.CELL + ldy * pPerp * GS.CELL
            -- 上升偏移
            local rise = math.fmod(t * 1.5 + i * 0.13, 1.0)
            ppy = ppy - rise * GS.CELL * 0.5
            local pAlpha = math.floor(particleAlpha * (1 - rise))
            local dotR = math.max(1.5, GS.CELL * (enhanced and 0.05 or 0.04))
            nvgBeginPath(vg)
            nvgCircle(vg, ppx, ppy, dotR)
            nvgFillColor(vg, nvgRGBA(255, 252, 230, pAlpha))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：银色狮子强击系 AOE 冲击波特效（银色水平冲击波往前推）
-- ====================================================================
function M.drawStrikeAoeEffects()
    local vg = M.vg
    for _, e in ipairs(GS.strikeAoeEffects) do
        local t = safeProgress(e.timer, e.duration)

        -- 攻击者中心坐标
        local ax = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local ay = GS.BOARD_Y + (e.y - 0.5) * GS.CELL

        local fdx, fdy = e.fdx, e.fdy
        local maxPerp  = e.maxPerp
        local maxDepth = e.maxDepth
        local enhanced = e.enhanced  -- 碎星=true

        -- 垂直方向
        local ldx, ldy = -fdy, fdx

        -- 总体透明度
        local alpha
        if t < 0.1 then
            alpha = t / 0.1
        elseif t > 0.55 then
            alpha = (1 - t) / 0.45
        else
            alpha = 1.0
        end

        -- 色系：银白色
        local cR, cG, cB
        if enhanced then
            cR, cG, cB = 230, 240, 255  -- 碎星：冷白偏蓝
        else
            cR, cG, cB = 200, 210, 225  -- 强击/超强击：标准银色
        end

        -- ==========================================
        -- 冲击波前沿：一条亮线从近到远推进
        -- ==========================================
        local waveFront = t * (maxDepth + 1)  -- 波前位置（格数）
        local waveWidth = 1.2  -- 波前宽度（格数）

        -- 在 AOE 区域上绘制每格淡银底色
        for depth = 1, maxDepth do
            for p = -maxPerp, maxPerp do
                local cx = e.x + fdx * depth + ldx * p
                local cy = e.y + fdy * depth + ldy * p
                local cellPx = GS.BOARD_X + (cx - 0.5) * GS.CELL
                local cellPy = GS.BOARD_Y + (cy - 0.5) * GS.CELL

                -- 波前已扫过的区域才显示残余痕迹
                local depthDist = depth
                if depthDist <= waveFront then
                    -- 残余亮度：波前刚过时最亮，越早扫过越暗
                    local trail = 1.0 - (waveFront - depthDist) / (maxDepth + 1)
                    trail = math.max(0, trail)
                    local fillA = math.floor(alpha * trail * (enhanced and 45 or 30))
                    local cs = GS.CELL * 0.95
                    nvgBeginPath(vg)
                    nvgRect(vg, cellPx - cs / 2, cellPy - cs / 2, cs, cs)
                    nvgFillColor(vg, nvgRGBA(cR, cG, cB, fillA))
                    nvgFill(vg)
                end
            end
        end

        -- ==========================================
        -- 主冲击波线：横跨整个宽度的亮白弧线
        -- ==========================================
        if waveFront >= 0.5 and waveFront <= maxDepth + 0.5 then
            local wavePx = ax + fdx * waveFront * GS.CELL
            local wavePy = ay + fdy * waveFront * GS.CELL
            local halfW  = (maxPerp + 0.5) * GS.CELL

            -- 波前亮线（横向）
            local lineAlpha = math.floor(alpha * (enhanced and 220 or 180))
            nvgBeginPath(vg)
            nvgMoveTo(vg, wavePx + ldx * halfW, wavePy + ldy * halfW)
            nvgLineTo(vg, wavePx - ldx * halfW, wavePy - ldy * halfW)
            nvgStrokeColor(vg, nvgRGBA(240, 245, 255, lineAlpha))
            nvgStrokeWidth(vg, math.max(2, GS.CELL * (enhanced and 0.12 or 0.08)))
            nvgStroke(vg)

            -- 波前光晕（沿线扩散）
            local glowH = GS.CELL * (enhanced and 0.6 or 0.4)
            local glowAlpha = math.floor(alpha * (enhanced and 80 or 55))
            -- 横向渐变矩形
            nvgBeginPath(vg)
            local x1 = wavePx + ldx * halfW
            local y1 = wavePy + ldy * halfW
            local x2 = wavePx - ldx * halfW
            local y2 = wavePy - ldy * halfW
            -- 用径向渐变沿波前绘制光晕
            local grad = nvgRadialGradient(vg, wavePx, wavePy, 0, halfW * 1.2,
                nvgRGBA(cR, cG, cB, glowAlpha),
                nvgRGBA(cR, cG, cB, 0))
            nvgBeginPath(vg)
            nvgRect(vg, wavePx - halfW * 1.2, wavePy - halfW * 1.2, halfW * 2.4, halfW * 2.4)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end

        -- ==========================================
        -- 银色拖尾粒子：沿冲击波方向飞散
        -- ==========================================
        local particleCount = 4 + maxPerp * 2 + maxDepth
        local pAlphaBase = alpha * (enhanced and 200 or 150)
        for i = 1, particleCount do
            local seed = i * 2.137 + t * 3.0
            -- 粒子在波前附近产生
            local pDepth = waveFront - math.abs(math.sin(seed * 4.1)) * 1.5
            if pDepth >= 0.5 and pDepth <= maxDepth + 0.5 then
                local pPerp = math.sin(seed * 6.7) * (maxPerp + 0.3)
                local ppx = ax + fdx * pDepth * GS.CELL + ldx * pPerp * GS.CELL
                local ppy = ay + fdy * pDepth * GS.CELL + ldy * pPerp * GS.CELL
                -- 微小抖动
                ppx = ppx + math.sin(seed * 11.3) * GS.CELL * 0.1
                ppy = ppy + math.cos(seed * 13.7) * GS.CELL * 0.1
                local fade = 1.0 - math.abs(pDepth - waveFront) / 1.5
                local pA = math.floor(pAlphaBase * math.max(0, fade))
                local dotR = math.max(1.5, GS.CELL * (enhanced and 0.045 or 0.035))
                nvgBeginPath(vg)
                nvgCircle(vg, ppx, ppy, dotR)
                nvgFillColor(vg, nvgRGBA(230, 240, 255, pA))
                nvgFill(vg)
            end
        end

        -- ==========================================
        -- 碎星额外效果：地面裂痕线
        -- ==========================================
        if enhanced and t > 0.15 then
            local crackAlpha = math.floor(alpha * 120 * math.max(0, 1 - (t - 0.15) / 0.55))
            local crackCount = 3 + maxPerp
            for i = 1, crackCount do
                local seed = i * 3.71
                local cDepth = 1 + (maxDepth - 1) * math.abs(math.sin(seed * 2.3))
                local cPerp  = math.sin(seed * 4.9) * maxPerp * 0.8
                local cx1 = ax + fdx * cDepth * GS.CELL + ldx * cPerp * GS.CELL
                local cy1 = ay + fdy * cDepth * GS.CELL + ldy * cPerp * GS.CELL
                local cLen = GS.CELL * (0.3 + 0.4 * math.abs(math.sin(seed * 7.1)))
                local cAng = seed * 5.3
                local cx2 = cx1 + math.cos(cAng) * cLen
                local cy2 = cy1 + math.sin(cAng) * cLen
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx1, cy1)
                nvgLineTo(vg, cx2, cy2)
                nvgStrokeColor(vg, nvgRGBA(200, 215, 240, crackAlpha))
                nvgStrokeWidth(vg, math.max(1, GS.CELL * 0.02))
                nvgStroke(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：爆炸信爆炸特效（红色爆炸圈扩散，以目标为中心）
-- ====================================================================
function M.drawRangedExplosionEffects()
    local vg = M.vg
    for _, e in ipairs(GS.rangedExplosionEffects) do
        local cx = GS.BOARD_X + (e.x - 0.5) * GS.CELL
        local cy = GS.BOARD_Y + (e.y - 0.5) * GS.CELL
        local t = safeProgress(e.timer, e.duration)

        local range = e.range or 1
        local radius = (range + 0.5) * GS.CELL  -- 基础1格=1.5*CELL，每层+1*CELL

        -- 透明度：快速出现，后半段淡出
        local alpha
        if t < 0.15 then
            alpha = t / 0.15
        elseif t > 0.4 then
            alpha = (1 - t) / 0.6
        else
            alpha = 1.0
        end

        -- 扩散进度
        local spread = 0.2 + 0.8 * t
        local curR = radius * spread

        -- 外层爆炸光环（亮红色）
        local outerAlpha = math.floor(alpha * 150)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, curR)
        nvgStrokeColor(vg, nvgRGBA(255, 60, 20, outerAlpha))
        nvgStrokeWidth(vg, math.max(3, GS.CELL * 0.15 * (1 - t * 0.5)))
        nvgStroke(vg)

        -- 内层第二道光环（暗红偏橙）
        local innerAlpha = math.floor(alpha * 100)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, curR * 0.7)
        nvgStrokeColor(vg, nvgRGBA(255, 100, 30, innerAlpha))
        nvgStrokeWidth(vg, math.max(2, GS.CELL * 0.1 * (1 - t * 0.3)))
        nvgStroke(vg)

        -- 中心填充（半透明红橙渐变）
        local fillAlpha = math.floor(alpha * 60 * (1 - t))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, curR * 0.5)
        nvgFillColor(vg, nvgRGBA(255, 80, 20, fillAlpha))
        nvgFill(vg)

        -- 爆炸粒子（星形飞溅），范围越大粒子越多
        local particleCount = 6 + range * 2
        local particleAlpha = math.floor(alpha * 180)
        for i = 1, particleCount do
            local pAngle = (i - 1) / particleCount * math.pi * 2 + t * 1.5
            local pDist = curR * (0.4 + 0.5 * t)
            local px = cx + math.cos(pAngle) * pDist
            local py = cy + math.sin(pAngle) * pDist
            local dotR = math.max(1.5, GS.CELL * 0.05 * (1 - t * 0.6))
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, dotR)
            nvgFillColor(vg, nvgRGBA(255, 180, 40, particleAlpha))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：嘲讽技能特效（目标怪物红色怒气粒子升腾）
-- ====================================================================
function M.drawTauntEffects()
    local vg = M.vg
    for _, e in ipairs(GS.tauntEffects) do
        local t = safeProgress(e.timer, e.duration)
        -- 从目标引用实时读取坐标（跟随怪物移动）
        local target = e.target
        if not target then goto continueTaunt end
        local cx = GS.BOARD_X + (target.x - 0.5) * GS.CELL
        local cy = GS.BOARD_Y + (target.y - 0.5) * GS.CELL
        local halfCell = GS.CELL * 0.5

        -- ============================================================
        -- 红色怒气粒子从底部升腾向上消散
        -- ============================================================
        for i = 1, 100 do
            local phase = (i - 1) / 100
            local pt = t - phase * 0.35
            if pt > 0 and pt < 1 then
                -- 水平散布：围绕怪物中心
                local seed = i * 137.5
                local spread = halfCell * (0.4 + pt * 0.35)
                local xOff = math.sin(seed) * spread
                -- 从底部升起
                local rise = pt * GS.CELL * 1.3
                local px = cx + xOff + math.sin(pt * 4 + seed) * 3
                local py = cy + halfCell - rise

                -- 透明度：淡入→淡出
                local fadeIn = math.min(pt * 5, 1.0)
                local fadeOut = math.max(1.0 - pt, 0)
                local alpha = math.floor(210 * fadeIn * fadeOut)

                -- 粒子大小
                local baseSize = 2.0 + math.sin(seed * 0.7) * 1.2
                local size = baseSize * fadeIn * (0.6 + fadeOut * 0.4)

                -- 红色系怒气（深红→橙红随机偏移）
                local cr = math.floor(255 - math.sin(seed * 1.3) * 30)
                local cg = math.floor(50 + math.sin(seed * 0.9) * 40)
                local cb = math.floor(20 + math.sin(seed * 1.7) * 15)

                local pGrad = nvgRadialGradient(vg, px, py, 0, size,
                    nvgRGBA(cr, cg, cb, alpha),
                    nvgRGBA(cr, cg, cb, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, size)
                nvgFillPaint(vg, pGrad)
                nvgFill(vg)
            end
        end

        -- ============================================================
        -- 底部红色光晕（怒气聚集感）
        -- ============================================================
        if t < 0.7 then
            local glowT = math.min(t / 0.3, 1.0)
            local glowFade = t > 0.5 and (0.7 - t) / 0.2 or 1.0
            local glowR = halfCell * 0.8
            local glowA = math.floor(100 * glowT * glowFade)
            local grad = nvgRadialGradient(vg, cx, cy + halfCell * 0.3, 0, glowR,
                nvgRGBA(255, 60, 20, glowA),
                nvgRGBA(200, 30, 10, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy + halfCell * 0.3, glowR)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end
        ::continueTaunt::
    end
end

-- ====================================================================
-- 绘制：隐匿烟雾弹特效（烟雾扩散，1.0秒）
-- ====================================================================
function M.drawStealthSmokeEffect()
    local e = GS.stealthSmokeEffect
    if not e then return end
    local vg = M.vg
    local cx = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
    local cy = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
    local t = safeProgress(e.timer, e.duration)
    local R = GS.CELL * 1.2  -- 烟雾最大扩散半径

    -- ============================================================
    -- 阶段1：中心爆发闪光 (0.0 - 0.15)
    -- ============================================================
    if t < 0.15 then
        local ct = t / 0.15
        local flashR = GS.CELL * 0.1 + GS.CELL * 0.8 * ct
        local flashA = math.floor(200 * (1 - ct))
        local flashGrad = nvgRadialGradient(vg, cx, cy, 0, flashR,
            nvgRGBA(180, 220, 240, flashA),
            nvgRGBA(120, 180, 200, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, flashR)
        nvgFillPaint(vg, flashGrad)
        nvgFill(vg)
    end

    -- ============================================================
    -- 阶段2：烟雾团扩散 (0.05 - 0.85)
    -- ============================================================
    if t >= 0.05 and t < 0.85 then
        local st = (t - 0.05) / 0.80
        -- 烟雾透明度：先浓后淡
        local smokeAlpha
        if st < 0.25 then
            smokeAlpha = st / 0.25
        elseif st > 0.55 then
            smokeAlpha = (1 - st) / 0.45
        else
            smokeAlpha = 1.0
        end

        -- 多层烟雾云团，大小和位置各异
        local cloudCount = 8
        for i = 1, cloudCount do
            local angle = (i / cloudCount) * math.pi * 2 + i * 1.37
            local distRatio = 0.2 + 0.8 * st
            local dist = R * distRatio * (0.5 + 0.5 * math.sin(i * 2.3))
            local cloudX = cx + math.cos(angle) * dist
            local cloudY = cy + math.sin(angle) * dist * 0.75  -- 椭圆形扩散
            local cloudR = GS.CELL * (0.25 + 0.35 * st) * (0.7 + 0.3 * math.sin(i * 3.7))
            local a = math.floor(120 * smokeAlpha * (0.6 + 0.4 * math.sin(i * 1.9)))

            -- 烟雾使用径向渐变模拟自然感
            local cGrad = nvgRadialGradient(vg, cloudX, cloudY, cloudR * 0.1, cloudR,
                nvgRGBA(140, 170, 190, a),
                nvgRGBA(100, 130, 150, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, cloudX, cloudY, cloudR)
            nvgFillPaint(vg, cGrad)
            nvgFill(vg)
        end

        -- 中心浓烟（较大、较密）
        local coreR = GS.CELL * 0.6 * (1 - st * 0.5)
        local coreA = math.floor(160 * smokeAlpha * (1 - st * 0.7))
        local coreGrad = nvgRadialGradient(vg, cx, cy, 0, coreR,
            nvgRGBA(160, 190, 210, coreA),
            nvgRGBA(120, 150, 170, math.floor(coreA * 0.3)))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, coreR)
        nvgFillPaint(vg, coreGrad)
        nvgFill(vg)
    end

    -- ============================================================
    -- 阶段3：飘散烟丝 (0.2 - 0.95)
    -- ============================================================
    if t >= 0.2 and t < 0.95 then
        local wt = (t - 0.2) / 0.75
        local wisps = 6
        for i = 1, wisps do
            local angle = (i / wisps) * math.pi * 2 + i * 0.83 + t * 1.5
            local dist = R * (0.4 + 0.9 * wt)
            -- 烟丝向上飘散
            local wx = cx + math.cos(angle) * dist
            local wy = cy + math.sin(angle) * dist * 0.6 - GS.CELL * 0.3 * wt
            local wR = GS.CELL * 0.12 * (1 - wt * 0.6)
            local wA = math.floor(100 * (1 - wt))

            nvgBeginPath(vg)
            nvgCircle(vg, wx, wy, wR)
            nvgFillColor(vg, nvgRGBA(150, 180, 200, wA))
            nvgFill(vg)
        end
    end

    -- ============================================================
    -- 阶段4：残留薄雾 (0.6 - 1.0)
    -- ============================================================
    if t >= 0.6 then
        local ft = (t - 0.6) / 0.4
        local mistR = R * 0.5 * (1 - ft * 0.3)
        local mistA = math.floor(50 * (1 - ft))
        local mistGrad = nvgRadialGradient(vg, cx, cy, 0, mistR,
            nvgRGBA(130, 160, 180, mistA),
            nvgRGBA(100, 130, 150, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, mistR)
        nvgFillPaint(vg, mistGrad)
        nvgFill(vg)
    end

    -- 特效结束后自动清除
    if t >= 1.0 then
        GS.stealthSmokeEffect = nil
    end
end

-- ====================================================================
-- 绘制：幻影攻击特效（深渊词缀：近战普通攻击幻影+1）
-- 只绘制幻影棋子的出现/消散，武器攻击动画由 addAttackEffect 处理
-- 动画：渐显(0~0.2) → 驻留(0.2~0.6) → 消散(0.6~0.8)
-- ====================================================================
function M.drawPhantomAttackEffects()
    local vg = M.vg
    local cell = GS.CELL

    for _, e in ipairs(GS.phantomAttackEffects) do
        local t = safeProgress(e.timer, e.duration)

        -- 幻影像素位置（棋盘格→屏幕坐标）
        local cx = GS.BOARD_X + (e.px - 1) * cell + cell / 2
        local cy = GS.BOARD_Y + (e.py - 1) * cell + cell / 2

        -- 整体透明度
        local alpha
        if t <= 0.2 then
            alpha = t / 0.2
        elseif t <= 0.6 then
            alpha = 1.0
        else
            alpha = 1.0 - (t - 0.6) / 0.2
        end
        alpha = math.max(0, math.min(1, alpha))

        -- 缩放：出现时从0.5放大到1.0，消散时从1.0缩小到0.4
        local scale
        if t <= 0.2 then
            scale = 0.5 + 0.5 * (t / 0.2)
        elseif t <= 0.6 then
            scale = 1.0
        else
            scale = 1.0 - 0.6 * ((t - 0.6) / 0.2)
        end

        local bodyW = cell * 0.8 * scale
        local bodyH = bodyW
        local cornerR = cell * 0.18 * scale
        local bodyX = cx - bodyW / 2
        local bodyY = cy - bodyH / 2

        nvgSave(vg)
        nvgGlobalAlpha(vg, alpha)

        -- 外发光（紫色光晕）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX - 4, bodyY - 4, bodyW + 8, bodyH + 8, cornerR + 4)
        nvgFillColor(vg, nvgRGBA(140, 80, 200, math.floor(80 * alpha)))
        nvgFill(vg)

        -- 身体背景（深紫渐变）
        local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
            nvgRGBA(50, 20, 80, 200), nvgRGBA(30, 10, 60, 220))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillPaint(vg, bodyGrad)
        nvgFill(vg)

        -- 紫色边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgStrokeColor(vg, nvgRGBA(180, 100, 255, math.floor(220 * alpha)))
        nvgStrokeWidth(vg, 2.0 * scale)
        nvgStroke(vg)

        -- 玩家职业头像
        local avatarImg = M.classAvatars and M.classAvatars[GS.currentClass]
            or M.playerAvatar
        if avatarImg and avatarImg ~= -1 then
            local imgSize = bodyW * 0.9
            local imgPaint = nvgImagePattern(vg, cx - imgSize / 2, cy - imgSize / 2,
                imgSize, imgSize, 0, avatarImg, 0.85)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX + bodyW * 0.05, bodyY + bodyH * 0.05,
                bodyW * 0.9, bodyH * 0.9, cornerR * 0.8)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        end

        -- 黑色半透明遮罩
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(60 * alpha)))
        nvgFill(vg)

        -- 消散阶段：紫色粒子散射
        if t > 0.6 then
            local dissT = (t - 0.6) / 0.2
            for p = 1, 6 do
                local angle = (p / 6) * math.pi * 2 + e.px * 0.5
                local dist = cell * 0.5 * dissT
                local pAlpha = math.floor(180 * (1 - dissT) * alpha)
                local pSize = 3 * scale * (1 - dissT * 0.5)
                nvgBeginPath(vg)
                nvgCircle(vg, cx + math.cos(angle) * dist, cy + math.sin(angle) * dist, pSize)
                nvgFillColor(vg, nvgRGBA(180, 120, 255, pAlpha))
                nvgFill(vg)
            end
        end

        nvgGlobalAlpha(vg, 1.0)
        nvgRestore(vg)
    end
end

-- ====================================================================
-- 绘制：远程反击剑气飞行特效（天蝎座盾牌 · 紫色剑气）
-- ====================================================================
function M.drawSwordQiEffects()
    local vg = M.vg
    for _, e in ipairs(GS.swordQiEffects) do
        -- delay 期间不绘制
        if e.delay and e.delay > 0 then goto continue_sword_qi end

        nvgSave(vg)

        local px = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
        local fpx = GS.BOARD_X + (e.fx - 1) * GS.CELL + GS.CELL / 2
        local fpy = GS.BOARD_Y + (e.fy - 1) * GS.CELL + GS.CELL / 2

        local t = safeProgress(e.timer, e.duration)
        local dirAngle = math.atan(py - fpy, px - fpx)
        local ddx = math.cos(dirAngle)
        local ddy = math.sin(dirAngle)

        -- 阶段1：剑气飞行 (t 0~0.60)
        local flyEnd = 0.60
        local hitT = 0.55
        if t < flyEnd then
            local flyT = math.min(t / hitT, 1.0)
            -- 加速缓动
            local ease = flyT * flyT * (3 - 2 * flyT)
            local dx = fpx + (px - fpx) * ease
            local dy = fpy + (py - fpy) * ease
            local flyAlpha = flyT < 0.85 and 255 or math.floor(255 * (1 - (flyT - 0.85) / 0.15))

            -- 紫色光晕
            local time = GetTime():GetElapsedTime()
            local flicker = 0.7 + 0.3 * math.sin(time * 20)
            local glowR = GS.CELL * (0.30 + 0.08 * flicker)
            local glowA = math.floor(200 * flicker * (flyAlpha / 255))
            local glow = nvgRadialGradient(vg, dx, dy, 0, glowR,
                nvgRGBA(180, 80, 255, glowA),
                nvgRGBA(120, 40, 200, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, dx, dy, glowR)
            nvgFillPaint(vg, glow)
            nvgFill(vg)

            -- 剑气本体（菱形剑刃）
            local bladeLen = GS.CELL * 0.35
            local bladeW = GS.CELL * 0.10
            nvgSave(vg)
            nvgTranslate(vg, dx, dy)
            nvgRotate(vg, dirAngle)
            nvgBeginPath(vg)
            nvgMoveTo(vg, bladeLen, 0)
            nvgLineTo(vg, 0, -bladeW)
            nvgLineTo(vg, -bladeLen * 0.5, 0)
            nvgLineTo(vg, 0, bladeW)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(220, 180, 255, flyAlpha))
            nvgFill(vg)
            -- 亮芯
            nvgBeginPath(vg)
            nvgMoveTo(vg, bladeLen * 0.8, 0)
            nvgLineTo(vg, 0, -bladeW * 0.4)
            nvgLineTo(vg, -bladeLen * 0.3, 0)
            nvgLineTo(vg, 0, bladeW * 0.4)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(255, 240, 255, flyAlpha))
            nvgFill(vg)
            nvgRestore(vg)

            -- 拖尾光迹
            if flyT > 0.08 then
                local traveledDist = math.sqrt((dx - fpx)^2 + (dy - fpy)^2)
                local trailLen = math.min(GS.CELL * 1.2 * math.min(1, flyT * 3), traveledDist)
                local tx2 = dx - ddx * trailLen
                local ty2 = dy - ddy * trailLen
                local trailA = math.floor(140 * (flyAlpha / 255))
                -- 外层紫色拖尾
                nvgBeginPath(vg)
                nvgMoveTo(vg, dx, dy)
                nvgLineTo(vg, tx2, ty2)
                nvgStrokeColor(vg, nvgRGBA(160, 80, 240, trailA))
                nvgStrokeWidth(vg, math.max(3, GS.CELL * 0.06))
                nvgStroke(vg)
                -- 内层亮芯
                local tx3 = dx - ddx * trailLen * 0.6
                local ty3 = dy - ddy * trailLen * 0.6
                nvgBeginPath(vg)
                nvgMoveTo(vg, dx, dy)
                nvgLineTo(vg, tx3, ty3)
                nvgStrokeColor(vg, nvgRGBA(220, 200, 255, math.floor(trailA * 0.7)))
                nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.03))
                nvgStroke(vg)
            end
        end

        -- 阶段2：命中爆发 (t 0.55~1.0)
        if t >= 0.55 then
            local ht = (t - 0.55) / 0.45
            -- 紫色冲击波
            local impactR = GS.CELL * (0.10 + 0.45 * ht)
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, impactR)
            nvgStrokeColor(vg, nvgRGBA(180, 80, 255, math.floor(200 * (1 - ht))))
            nvgStrokeWidth(vg, 2.5 * (1 - ht * 0.5))
            nvgStroke(vg)
            -- 中心闪光
            if ht < 0.25 then
                local flashT = ht / 0.25
                local flashR = GS.CELL * (0.05 + 0.15 * flashT)
                local flashA = math.floor(220 * (1 - flashT))
                local flashGlow = nvgRadialGradient(vg, px, py, 0, flashR,
                    nvgRGBA(230, 200, 255, flashA),
                    nvgRGBA(160, 80, 240, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, flashR)
                nvgFillPaint(vg, flashGlow)
                nvgFill(vg)
            end
            -- 紫色碎片飞散
            for i = 1, 6 do
                local angle = (i / 6) * math.pi * 2 + dirAngle
                local fd = GS.CELL * 0.4 * ht * ht
                local fragAlpha = math.floor(180 * (1 - ht))
                local fragSize = 2.0 * (1 - ht * 0.5)
                nvgBeginPath(vg)
                nvgCircle(vg, px + math.cos(angle) * fd, py + math.sin(angle) * fd, fragSize)
                nvgFillColor(vg, nvgRGBA(180, 100 + i * 15, 255, fragAlpha))
                nvgFill(vg)
            end
        end

        nvgRestore(vg)
        ::continue_sword_qi::
    end
end

end  -- sub.init

return sub
