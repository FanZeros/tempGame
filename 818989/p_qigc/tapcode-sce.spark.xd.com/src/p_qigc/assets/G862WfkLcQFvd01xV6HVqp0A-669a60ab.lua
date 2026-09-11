-- ============================================================================
-- ScorchEffect.lua — 2D 暴晒效果模块（纯 NanoVG）
-- 阳光光晕 + 暖色遮罩 + 热气微粒升腾
-- 用法：
--   local ScorchEffect = require("ScorchEffect")
--   ScorchEffect.init(vg)         -- Start 时调用一次
--   ScorchEffect.update(dt)       -- HandleUpdate 中调用
--   ScorchEffect.draw(vg, w, h)   -- NanoVG 渲染中调用（设计坐标空间）
--   ScorchEffect.setEnabled(bool) -- 开关控制
-- ============================================================================

local GS = require("GameState")
local BoardOverlay = require("BoardOverlay")

local M = {}

-- ── 配置 ──
local CFG = {
    -- 阳光光晕（右上角太阳）
    sunGlowAlpha    = 30,       -- 太阳光晕最大透明度
    sunPulseSpeed   = 1.2,      -- 光晕脉动速度
    sunPulseAmp     = 0.15,     -- 光晕脉动幅度（0~1）
    sunRayCount     = 8,        -- 光线条数
    sunRayAlpha     = 22,       -- 光线透明度
    sunRayLen       = 1.0,      -- 光线长度（相对屏幕宽度）
    -- 整体暖色遮罩（泛黄滤镜）
    warmAlpha       = 40,       -- 暖色遮罩透明度
    -- 热气粒子（地面上升的透明小点）
    shimmerCount    = 35,       -- 热气微粒数量
    shimmerSpeed    = 15,       -- 上升速度
    shimmerAlpha    = 35,       -- 微粒透明度
    shimmerSize     = 2.5,      -- 微粒半径
}

-- ── 内部数据 ──
local shimmers = {}     -- {x, y, life, maxLife, phase}
local screenW = 0
local screenH = 0
local initialized = false
local timer = 0

-- ── 工具函数 ──
local function randRange(lo, hi) return lo + math.random() * (hi - lo) end

-- ── 初始化 ──
function M.init(vg)
    initialized = true
end

local function initEffects(w, h)
    screenW = w
    screenH = h
    shimmers = {}
    for i = 1, CFG.shimmerCount do
        shimmers[i] = {
            x = 0, y = 0,
            life = 0, maxLife = randRange(1.5, 3.0),
            phase = math.random() * math.pi * 2,
        }
    end
end

-- ── 开关 ──
function M.setEnabled(enabled)
    GS.isScorching = enabled
end

function M.isEnabled()
    return GS.isScorching
end

--- 判断是否室内（与 RainEffect 共享逻辑）
function M.isIndoor()
    if BoardOverlay.active and BoardOverlay.overlayType == "town" then
        return BoardOverlay.inSubScene()
    end
    return GS.isIndoorStage() or BoardOverlay.inSubScene()
end

--- 世界天气是否暴晒且玩家在室外
function M.isActivelyScorching()
    return GS.isScorching and not M.isIndoor()
end

-- ── 更新 ──
function M.update(dt)
    if not GS.isScorching or not initialized then return end
    if M.isIndoor() then return end

    timer = timer + dt

    local w = screenW
    local h = screenH
    if w <= 0 or h <= 0 then return end

    -- 棋盘上生成热气微粒
    local bx = GS.BOARD_X or 0
    local by = GS.BOARD_Y or 0
    local cell = GS.CELL or 0
    local bsize = GS.BOARD_SIZE or 12
    local boardW = cell * bsize
    local boardH = cell * bsize

    -- 更新/生成微粒
    for i = 1, CFG.shimmerCount do
        local s = shimmers[i]
        if s then
            if s.life > 0 then
                s.life = s.life - dt
                s.y = s.y - CFG.shimmerSpeed * dt
                s.x = s.x + math.sin(timer * 3 + s.phase) * 8 * dt
            else
                -- 重新生成
                if cell > 0 and boardW > 0 then
                    s.x = bx + math.random() * boardW
                    s.y = by + math.random() * boardH
                else
                    s.x = math.random() * w
                    s.y = h * 0.5 + math.random() * h * 0.5
                end
                s.maxLife = randRange(1.5, 3.0)
                s.life = s.maxLife
                s.phase = math.random() * math.pi * 2
            end
        end
    end
end

-- ── 绘制 ──
function M.draw(vg, w, h)
    if not GS.isScorching or not initialized or not vg then return end
    if M.isIndoor() then return end

    -- 首次或尺寸变化时初始化
    if w ~= screenW or h ~= screenH or #shimmers == 0 then
        initEffects(w, h)
    end

    -- 1) 暖色调整体遮罩（模拟烈日下的暖色调）
    if CFG.warmAlpha > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, CFG.warmAlpha))
        nvgFill(vg)
    end

    -- 2) 太阳光晕（左上角放射状，横屏竖屏均可见）
    local sunX = w * 0.15
    local sunY = h * 0.08
    local pulse = 1.0 + math.sin(timer * CFG.sunPulseSpeed) * CFG.sunPulseAmp
    local glowR = math.min(w, h) * 0.35 * pulse

    -- 光晕圆（径向渐变）
    local innerA = math.floor(CFG.sunGlowAlpha * pulse)
    local grad = nvgRadialGradient(vg, sunX, sunY, glowR * 0.1, glowR,
        nvgRGBA(255, 240, 180, innerA),
        nvgRGBA(255, 200, 80, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, sunX, sunY, glowR)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 光线条（从太阳中心向外放射，带呼吸闪烁 + 粗细随机）
    if CFG.sunRayAlpha > 0 then
        local rayLen = w * CFG.sunRayLen
        for i = 1, CFG.sunRayCount do
            local angle = (i - 1) * (math.pi * 2 / CFG.sunRayCount) + timer * 0.1
            -- 每条光线独立的呼吸节奏（不同频率 + 相位偏移）
            local breathFreq = 1.8 + (i % 3) * 0.7    -- 1.8 / 2.5 / 3.2 Hz
            local breathPhase = i * 1.37               -- 黄金角偏移，避免同步
            local breath = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(timer * breathFreq + breathPhase))
            -- 粗细随机：基础粗细 + 缓慢变化的随机扰动
            local widthBase = 2.5 + (i % 4) * 0.8     -- 2.5 / 3.3 / 4.1 / 4.9
            local widthWobble = 0.8 + 0.4 * math.sin(timer * 1.1 + i * 2.3)
            local strokeW = widthBase * widthWobble * breath
            -- 透明度跟随呼吸
            local rayA = math.floor(CFG.sunRayAlpha * breath)
            local rx = sunX + math.cos(angle) * rayLen
            local ry = sunY + math.sin(angle) * rayLen
            nvgBeginPath(vg)
            nvgMoveTo(vg, sunX + math.cos(angle) * 20, sunY + math.sin(angle) * 20)
            nvgLineTo(vg, rx, ry)
            nvgStrokeColor(vg, nvgRGBA(255, 240, 180, rayA))
            nvgStrokeWidth(vg, math.max(0.5, strokeW))
            nvgStroke(vg)
        end
    end

    -- 3) 热气微粒（缓慢上升的半透明小点）
    for i = 1, CFG.shimmerCount do
        local s = shimmers[i]
        if s and s.life > 0 then
            local t = s.life / s.maxLife  -- 1→0
            -- 中间最亮，开头和结尾淡出
            local fadeIn  = math.min(1, (1 - t) * 4)  -- 刚出现时渐显
            local fadeOut = math.min(1, t * 3)          -- 消失前渐隐
            local a = math.floor(CFG.shimmerAlpha * fadeIn * fadeOut)
            if a > 0 then
                local r = CFG.shimmerSize * (0.5 + 0.5 * math.sin(timer * 5 + s.phase))
                nvgBeginPath(vg)
                nvgCircle(vg, s.x, s.y, math.max(1, r))
                nvgFillColor(vg, nvgRGBA(255, 250, 220, a))
                nvgFill(vg)
            end
        end
    end

    -- 4) 底部热气遮罩（地面附近的热浪雾气）
    local heatFogH = h * 0.12
    local fogGrad = nvgLinearGradient(vg, 0, h - heatFogH, 0, h,
        nvgRGBA(255, 230, 180, 0),
        nvgRGBA(255, 230, 180, 12))
    nvgBeginPath(vg)
    nvgRect(vg, 0, h - heatFogH, w, heatFogH)
    nvgFillPaint(vg, fogGrad)
    nvgFill(vg)
end

return M
