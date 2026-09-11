-- ============================================================================
-- WindEffect.lua — 2D 刮风效果模块（纯 NanoVG）
-- 8方向风 + 树叶/尘土粒子 + 风线条
-- 用法：
--   local WindEffect = require("WindEffect")
--   WindEffect.init(vg)         -- Start 时调用一次
--   WindEffect.update(dt)       -- HandleUpdate 中调用
--   WindEffect.draw(vg, w, h)   -- NanoVG 渲染中调用（设计坐标空间）
--   WindEffect.setEnabled(bool, dir) -- 开关控制, dir=1~8
-- ============================================================================

local GS = require("GameState")
local BoardOverlay = require("BoardOverlay")

local M = {}

-- ── 8方向映射 (1=北, 顺时针) ──
-- 方向向量 {dx, dy}，屏幕坐标 y 向下
local DIR_VECTORS = {
    [1] = { 0, -1},   -- 北（向上吹）
    [2] = { 1, -1},   -- 东北
    [3] = { 1,  0},   -- 东
    [4] = { 1,  1},   -- 东南
    [5] = { 0,  1},   -- 南（向下吹）
    [6] = {-1,  1},   -- 西南
    [7] = {-1,  0},   -- 西
    [8] = {-1, -1},   -- 西北
}

local DIR_NAMES = {
    [1] = "北风", [2] = "东北风", [3] = "东风", [4] = "东南风",
    [5] = "南风", [6] = "西南风", [7] = "西风", [8] = "西北风",
}

-- ── 配置 ──
local CFG = {
    -- 树叶/尘土粒子
    particleCount   = 60,       -- 粒子数量
    minSize         = 2,        -- 最小粒子尺寸
    maxSize         = 6,        -- 最大粒子尺寸
    minSpeed        = 120,      -- 最慢移动速度
    maxSpeed        = 320,      -- 最快移动速度
    minAlpha        = 80,       -- 最低透明度
    maxAlpha        = 200,      -- 最高透明度
    wobbleAmp       = 30,       -- 横向摆动幅度
    wobbleFreq      = 3.0,      -- 摆动频率
    -- 风线条（半透明速度线）
    lineCount       = 25,       -- 风线条数量
    lineMinLen      = 30,       -- 最短线条
    lineMaxLen      = 80,       -- 最长线条
    lineMinSpeed    = 400,      -- 最慢线速度
    lineMaxSpeed    = 700,      -- 最快线速度
    lineAlpha       = 18,       -- 线条透明度
    lineWidth       = 0.8,      -- 线条宽度
    -- 棋盘灰尘飞扬
    dustCount       = 30,       -- 地面扬尘粒子数
    dustLife         = 0.6,     -- 扬尘生命周期
    dustRate         = 25,      -- 每秒生成数
    -- 氛围遮罩
    tintAlpha       = 10,       -- 整体灰黄色遮罩
}

-- ── 叶子颜色池 ──
local LEAF_COLORS = {
    {120, 160,  60},   -- 绿叶
    {160, 140,  50},   -- 枯黄叶
    {140, 100,  40},   -- 棕叶
    {100, 130,  50},   -- 深绿叶
    {180, 150,  60},   -- 浅黄叶
}

-- ── 内部数据 ──
local particles = {}    -- {x, y, size, speed, alpha, phase, color, rot, rotSpd}
local windLines = {}    -- {x, y, len, speed, alpha}
local dusts = {}        -- {x, y, life, maxLife, vx, vy}
local screenW = 0
local screenH = 0
local initialized = false
local dustAccum = 0
local timer = 0         -- 全局时间，用于摆动

-- 当前风方向向量（归一化）
local windDX = 1
local windDY = 0

-- ── 工具函数 ──
local function randRange(lo, hi) return lo + math.random() * (hi - lo) end

local function normalizeDir(dir)
    local v = DIR_VECTORS[dir] or DIR_VECTORS[3]
    local dx, dy = v[1], v[2]
    local mag = math.sqrt(dx * dx + dy * dy)
    if mag > 0 then
        return dx / mag, dy / mag
    end
    return 1, 0
end

-- 根据风向获取粒子的垂直摆动方向
local function perpDir()
    return -windDY, windDX
end

--- 判断粒子是否超出屏幕范围，对角线风时任一轴超出即回收
--- @return boolean
local function isParticleOOB(px, py, margin, w, h)
    -- 沿风向：飞出下风侧
    if windDX > 0 and px > w + margin then return true end
    if windDX < 0 and px < -margin then return true end
    if windDY > 0 and py > h + margin then return true end
    if windDY < 0 and py < -margin then return true end
    -- 垂直于风向：飘出侧面（对角线风也需要检测侧面越界）
    if px < -margin or px > w + margin then return true end
    if py < -margin or py > h + margin then return true end
    return false
end

--- 从逆风侧重新生成粒子位置
--- 对角线风：从逆风角的一条边随机进入（随机选X边或Y边），保证均匀分布
--- @return number, number
local function respawnUpwind(margin, w, h)
    local isDiag = (windDX ~= 0 and windDY ~= 0)
    if isDiag then
        -- 对角线风：随机选择从X边还是Y边进入，保证覆盖整个逆风侧L形区域
        if math.random() < 0.5 then
            -- 从X边进入（逆风侧的竖直边）
            local x = windDX > 0 and (-margin * math.random()) or (w + margin * math.random())
            local y = math.random() * (h + 2 * margin) - margin
            return x, y
        else
            -- 从Y边进入（逆风侧的水平边）
            local x = math.random() * (w + 2 * margin) - margin
            local y = windDY > 0 and (-margin * math.random()) or (h + margin * math.random())
            return x, y
        end
    elseif math.abs(windDX) > 0 then
        -- 纯水平风
        local x = windDX > 0 and (-margin * math.random()) or (w + margin * math.random())
        local y = math.random() * h
        return x, y
    else
        -- 纯垂直风
        local x = math.random() * w
        local y = windDY > 0 and (-margin * math.random()) or (h + margin * math.random())
        return x, y
    end
end

-- ── 初始化 ──
function M.init(vg)
    initialized = true
end

-- 在知道屏幕尺寸后初始化粒子（全屏范围）
local function initParticles(w, h)
    screenW = w
    screenH = h
    particles = {}
    for i = 1, CFG.particleCount do
        local col = LEAF_COLORS[math.random(#LEAF_COLORS)]
        particles[i] = {
            x     = math.random() * w,
            y     = math.random() * h,
            size  = randRange(CFG.minSize, CFG.maxSize),
            speed = randRange(CFG.minSpeed, CFG.maxSpeed),
            alpha = randRange(CFG.minAlpha, CFG.maxAlpha),
            phase = math.random() * math.pi * 2,
            color = col,
            rot   = math.random() * 360,
            rotSpd = randRange(-360, 360),   -- 旋转速度（度/秒）
        }
    end
    windLines = {}
    for i = 1, CFG.lineCount do
        windLines[i] = {
            x     = math.random() * w,
            y     = math.random() * h,
            len   = randRange(CFG.lineMinLen, CFG.lineMaxLen),
            speed = randRange(CFG.lineMinSpeed, CFG.lineMaxSpeed),
            alpha = CFG.lineAlpha,
        }
    end
    dusts = {}
    for i = 1, CFG.dustCount do
        dusts[i] = { x = 0, y = 0, life = 0, maxLife = CFG.dustLife, vx = 0, vy = 0 }
    end
end

-- ── 开关 ──
function M.setEnabled(enabled, direction)
    GS.isWindy = enabled
    if direction then
        GS.windDirection = math.max(1, math.min(8, direction))
    end
end

function M.isEnabled()
    return GS.isWindy
end

function M.getDirectionName()
    return DIR_NAMES[GS.windDirection] or "东风"
end

--- 判断是否室内（与 RainEffect 共享逻辑）
function M.isIndoor()
    if BoardOverlay.active and BoardOverlay.overlayType == "town" then
        return BoardOverlay.inSubScene()
    end
    return GS.isIndoorStage() or BoardOverlay.inSubScene()
end

--- 世界天气是否刮风且玩家在室外
function M.isActivelyWindy()
    return GS.isWindy and not M.isIndoor()
end

-- ── 更新 ──
function M.update(dt)
    if not GS.isWindy or not initialized then return end
    if M.isIndoor() then return end

    timer = timer + dt
    windDX, windDY = normalizeDir(GS.windDirection)
    local perpX, perpY = perpDir()

    local w = screenW
    local h = screenH
    if w <= 0 or h <= 0 then return end

    -- 扩展区域边界（让粒子从屏幕外飞入）
    local margin = 100

    -- 更新粒子
    for i = 1, CFG.particleCount do
        local p = particles[i]
        if p then
            -- 主方向移动
            local spd = p.speed * dt
            p.x = p.x + windDX * spd
            p.y = p.y + windDY * spd
            -- 垂直方向摆动
            local wobble = math.sin(timer * CFG.wobbleFreq + p.phase) * CFG.wobbleAmp * dt
            p.x = p.x + perpX * wobble
            p.y = p.y + perpY * wobble
            -- 旋转
            p.rot = p.rot + p.rotSpd * dt

            -- 超出屏幕：从逆风方向重新进入
            if isParticleOOB(p.x, p.y, margin, w, h) then
                p.x, p.y = respawnUpwind(margin, w, h)
                p.speed = randRange(CFG.minSpeed, CFG.maxSpeed)
                p.phase = math.random() * math.pi * 2
                local col = LEAF_COLORS[math.random(#LEAF_COLORS)]
                p.color = col
                p.size = randRange(CFG.minSize, CFG.maxSize)
                p.alpha = randRange(CFG.minAlpha, CFG.maxAlpha)
                p.rotSpd = randRange(-360, 360)
            end
        end
    end

    -- 更新风线条
    for i = 1, CFG.lineCount do
        local ln = windLines[i]
        if ln then
            local spd = ln.speed * dt
            ln.x = ln.x + windDX * spd
            ln.y = ln.y + windDY * spd

            if isParticleOOB(ln.x, ln.y, ln.len, w, h) then
                ln.x, ln.y = respawnUpwind(50, w, h)
                ln.len = randRange(CFG.lineMinLen, CFG.lineMaxLen)
                ln.speed = randRange(CFG.lineMinSpeed, CFG.lineMaxSpeed)
            end
        end
    end

    -- 棋盘上扬尘
    local bx = GS.BOARD_X or 0
    local by = GS.BOARD_Y or 0
    local cell = GS.CELL or 0
    local bsize = GS.BOARD_SIZE or 12
    local boardW = cell * bsize
    local boardH = cell * bsize

    if cell > 0 and boardW > 0 then
        dustAccum = dustAccum + CFG.dustRate * dt
        while dustAccum >= 1 do
            dustAccum = dustAccum - 1
            local sx = bx + math.random() * boardW
            local sy = by + math.random() * boardH
            M._spawnDust(sx, sy)
        end
    end

    -- 更新扬尘
    for i = 1, CFG.dustCount do
        local d = dusts[i]
        if d and d.life > 0 then
            d.life = d.life - dt
            d.x = d.x + d.vx * dt
            d.y = d.y + d.vy * dt
            d.vy = d.vy - 15 * dt  -- 轻微上升
        end
    end
end

function M._spawnDust(x, y)
    for i = 1, CFG.dustCount do
        local d = dusts[i]
        if d and d.life <= 0 then
            d.x = x
            d.y = y
            d.life = CFG.dustLife
            d.maxLife = CFG.dustLife
            d.vx = windDX * randRange(40, 100)
            d.vy = windDY * randRange(40, 100) - randRange(10, 30)
            return
        end
    end
end

-- ── 绘制 ──
function M.draw(vg, w, h)
    if not GS.isWindy or not initialized or not vg then return end
    if M.isIndoor() then return end

    -- 首次或尺寸变化时初始化
    if w ~= screenW or h ~= screenH or #particles == 0 then
        initParticles(w, h)
    end

    -- 1) 整体灰黄色调遮罩（模拟沙尘感）
    if CFG.tintAlpha > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(160, 150, 120, CFG.tintAlpha))
        nvgFill(vg)
    end

    -- 2) 风线条（半透明高速线，表示风流方向）
    for i = 1, CFG.lineCount do
        local ln = windLines[i]
        if ln then
            local endX = ln.x + windDX * ln.len
            local endY = ln.y + windDY * ln.len

            -- 渐变：起点透明→中段不透明→终点透明
            nvgBeginPath(vg)
            nvgMoveTo(vg, ln.x, ln.y)
            nvgLineTo(vg, endX, endY)
            nvgStrokeColor(vg, nvgRGBA(200, 200, 190, ln.alpha))
            nvgStrokeWidth(vg, CFG.lineWidth)
            nvgStroke(vg)
        end
    end

    -- 3) 树叶/碎屑粒子
    for i = 1, CFG.particleCount do
        local p = particles[i]
        if p then
            local a = math.floor(p.alpha)
            nvgSave(vg)
            nvgTranslate(vg, p.x, p.y)
            nvgRotate(vg, math.rad(p.rot))

            -- 椭圆形叶片
            nvgBeginPath(vg)
            nvgEllipse(vg, 0, 0, p.size, p.size * 0.5)
            nvgFillColor(vg, nvgRGBA(p.color[1], p.color[2], p.color[3], a))
            nvgFill(vg)

            nvgRestore(vg)
        end
    end

    -- 4) 棋盘扬尘
    for i = 1, CFG.dustCount do
        local d = dusts[i]
        if d and d.life > 0 then
            local t = d.life / d.maxLife  -- 1→0
            local a = math.floor(50 * t)
            local r = 1.5 + (1 - t) * 2
            if a > 0 then
                nvgBeginPath(vg)
                nvgCircle(vg, d.x, d.y, r)
                nvgFillColor(vg, nvgRGBA(180, 170, 140, a))
                nvgFill(vg)
            end
        end
    end
end

return M
