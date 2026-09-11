-- ============================================================================
-- RainEffect.lua — 2D 雨天效果模块（纯 NanoVG）
-- 用法：
--   local RainEffect = require("RainEffect")
--   RainEffect.init(vg)         -- Start 时调用一次
--   RainEffect.update(dt)       -- HandleUpdate 中调用
--   RainEffect.draw(vg, w, h)   -- NanoVG 渲染中调用（设计坐标空间）
--   RainEffect.setEnabled(bool) -- 开关控制
-- ============================================================================

local GS = require("GameState")
local BoardOverlay = require("BoardOverlay")

local M = {}

-- ── 配置 ──
local CFG = {
    -- 雨丝
    rainCount     = 120,      -- 雨丝数量
    minLen        = 18,       -- 最短雨丝长度
    maxLen        = 45,       -- 最长雨丝长度
    minSpeed      = 500,      -- 最慢下落速度
    maxSpeed      = 900,      -- 最快下落速度
    minAlpha      = 15,       -- 最低透明度
    maxAlpha      = 50,       -- 最高透明度
    windAngleDeg  = 8,        -- 风偏角（度）
    strokeWidth   = 1.0,      -- 线条宽度
    colorR        = 180,
    colorG        = 200,
    colorB        = 220,
    -- 飞溅（随机散布在棋盘上）
    splashCount   = 40,       -- 同时存在的最大飞溅数
    splashLife    = 0.3,      -- 飞溅生命周期（秒）
    splashRadius  = 3,        -- 飞溅初始半径
    splashRate    = 60,       -- 每秒生成飞溅数
    -- 氛围遮罩
    fogAlpha      = 20,       -- 底部雾遮罩透明度
    cloudAlpha    = 35,       -- 顶部乌云遮罩透明度
}

-- ── 内部数据 ──
local rainLines = {}      -- {x, y, len, speed, alpha}
local splashes = {}       -- {x, y, life, maxLife}
local windRad = 0
local screenW = 0
local screenH = 0
local initialized = false
local splashAccum = 0         -- 飞溅生成累计器

-- ── 初始化 ──
function M.init(vg)
    initialized = true
    windRad = math.rad(CFG.windAngleDeg)
end

-- 初始化/重置雨丝（在知道屏幕尺寸后）
local function initRainLines(w, h)
    screenW = w
    screenH = h
    rainLines = {}
    for i = 1, CFG.rainCount do
        rainLines[i] = {
            x     = math.random() * w,
            y     = math.random() * h,
            len   = CFG.minLen + math.random() * (CFG.maxLen - CFG.minLen),
            speed = CFG.minSpeed + math.random() * (CFG.maxSpeed - CFG.minSpeed),
            alpha = CFG.minAlpha + math.random() * (CFG.maxAlpha - CFG.minAlpha),
        }
    end
    -- 初始化飞溅池
    splashes = {}
    for i = 1, CFG.splashCount do
        splashes[i] = { x = 0, y = 0, life = 0, maxLife = CFG.splashLife }
    end
end

-- ── 开关（读写 GS.isRaining，天气状态由 GameState 统一管理并持久化） ──
function M.setEnabled(enabled)
    GS.isRaining = enabled
end

function M.isEnabled()
    return GS.isRaining
end

--- 判断当前是否处于室内（综合关卡 + 家 + 清风镇建筑物）
function M.isIndoor()
    -- 城镇视图下，玩家不在任何战斗关卡，不应使用 currentStage 判断
    -- （currentStage 可能仍保留上次存档的战斗关卡值）
    -- 此时仅当进入了建筑物子场景才算室内
    if BoardOverlay.active and BoardOverlay.overlayType == "town" then
        return BoardOverlay.inSubScene()
    end
    return GS.isIndoorStage() or BoardOverlay.inSubScene()
end

--- 世界天气是否正在下雨且玩家在室外
function M.isActivelyRaining()
    return GS.isRaining and not M.isIndoor()
end

-- ── 更新 ──
function M.update(dt)
    if not GS.isRaining or not initialized then return end
    if M.isIndoor() then return end

    local w = screenW
    local h = screenH
    if w <= 0 or h <= 0 then return end

    -- 更新雨丝位置（正常落到画面底部）
    local sinW = math.sin(windRad)
    local cosW = math.cos(windRad)
    for i = 1, CFG.rainCount do
        local line = rainLines[i]
        if line then
            line.y = line.y + line.speed * cosW * dt
            line.x = line.x + line.speed * sinW * dt

            -- 超出底部：回收到顶部
            if line.y > h + line.len then
                line.y = -line.len - math.random() * 80
                line.x = math.random() * w
                line.len = CFG.minLen + math.random() * (CFG.maxLen - CFG.minLen)
                line.speed = CFG.minSpeed + math.random() * (CFG.maxSpeed - CFG.minSpeed)
                line.alpha = CFG.minAlpha + math.random() * (CFG.maxAlpha - CFG.minAlpha)
            end
            -- 超出右侧
            if line.x > w + 20 then
                line.x = -20
            end
        end
    end

    -- 在棋盘上随机生成飞溅
    local bx = GS.BOARD_X or 0
    local by = GS.BOARD_Y or 0
    local cell = GS.CELL or 0
    local bsize = GS.BOARD_SIZE or 12
    local boardW = cell * bsize
    local boardH = cell * bsize

    if cell > 0 and boardW > 0 then
        splashAccum = splashAccum + CFG.splashRate * dt
        while splashAccum >= 1 do
            splashAccum = splashAccum - 1
            local sx = bx + math.random() * boardW
            local sy = by + math.random() * boardH
            M._spawnSplash(sx, sy)
        end
    end

    -- 更新飞溅生命
    for i = 1, CFG.splashCount do
        local sp = splashes[i]
        if sp and sp.life > 0 then
            sp.life = sp.life - dt
        end
    end
end

-- 生成飞溅
function M._spawnSplash(x, y)
    for i = 1, CFG.splashCount do
        local sp = splashes[i]
        if sp and sp.life <= 0 then
            sp.x = x
            sp.y = y
            sp.life = CFG.splashLife
            sp.maxLife = CFG.splashLife
            return
        end
    end
end

-- ── 绘制（在设计坐标空间中调用） ──
function M.draw(vg, w, h)
    if not GS.isRaining or not initialized or not vg then return end
    if M.isIndoor() then return end

    -- 首次或尺寸变化时重新初始化
    if w ~= screenW or h ~= screenH or #rainLines == 0 then
        initRainLines(w, h)
    end

    local sinW = math.sin(windRad)
    local cosW = math.cos(windRad)

    -- 1) 顶部乌云遮罩
    if CFG.cloudAlpha > 0 then
        local grad = nvgLinearGradient(vg, 0, 0, 0, h * 0.25,
            nvgRGBA(30, 35, 45, CFG.cloudAlpha),
            nvgRGBA(30, 35, 45, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h * 0.25)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    -- 2) 底部雨雾遮罩
    if CFG.fogAlpha > 0 then
        local grad = nvgLinearGradient(vg, 0, h * 0.75, 0, h,
            nvgRGBA(80, 90, 105, 0),
            nvgRGBA(80, 90, 105, CFG.fogAlpha))
        nvgBeginPath(vg)
        nvgRect(vg, 0, h * 0.75, w, h * 0.25)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    -- 3) 雨丝
    for i = 1, CFG.rainCount do
        local line = rainLines[i]
        if line then
            local endX = line.x + sinW * line.len
            local endY = line.y + cosW * line.len

            nvgBeginPath(vg)
            nvgMoveTo(vg, line.x, line.y)
            nvgLineTo(vg, endX, endY)
            nvgStrokeColor(vg, nvgRGBA(CFG.colorR, CFG.colorG, CFG.colorB, math.floor(line.alpha)))
            nvgStrokeWidth(vg, CFG.strokeWidth)
            nvgStroke(vg)
        end
    end

    -- 4) 飞溅（小圆环扩散淡出）
    for i = 1, CFG.splashCount do
        local sp = splashes[i]
        if sp and sp.life > 0 then
            local t = sp.life / sp.maxLife  -- 1→0
            local r = CFG.splashRadius * (1.0 + (1.0 - t) * 2.0)  -- 扩大
            local alpha = math.floor(40 * t)
            if alpha > 0 then
                nvgBeginPath(vg)
                nvgEllipse(vg, sp.x, sp.y, r * 1.5, r * 0.5)  -- 扁平椭圆模拟水花
                nvgStrokeColor(vg, nvgRGBA(180, 200, 220, alpha))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            end
        end
    end
end

return M
