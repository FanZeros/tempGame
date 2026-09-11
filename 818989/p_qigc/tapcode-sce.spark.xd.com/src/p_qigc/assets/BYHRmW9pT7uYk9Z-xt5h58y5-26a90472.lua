-- ====================================================================
-- Renderer.lua - NanoVG 绘制、动画、UI
-- ====================================================================
-- 为联机做准备：渲染逻辑独立，联机时仅在客户端运行
-- ====================================================================

local GS = require("GameState")
local Combat = require("Combat")
local ImageManager = require("ImageManager")
local BoardOverlay = require("BoardOverlay")
local Utils = require("Renderer_Utils")

local M = {}

-- ====================================================================
-- NanoVG 资源引用（由 main.lua 注入）
-- ====================================================================
M.vg = nil
M.fontNormal = -1
M.bgImage = -1
M.swordImage = -1
M.bowImage = -1
M.daggerImage = -1
M.maceImage = -1
M.staffImage = -1
M.arrowImage = -1
M.slimeImage = -1
M.monsterImages = {}  -- 怪物专属图片表，key=image路径, value=nvgImage句柄
M.playerAvatar = -1
M.classAvatars = {}  -- 职业 → NanoVG图片句柄映射
M.tombstoneImage = -1
M.characterIcon = -1
M.backpackIcon = -1
M.mapIcon = -1
M.skillIcon = -1
M.bookIcon = -1
M.charPanelBg = -1
M.parchmentBg = -1
M.worldMapImg = -1
M.mapTowerBg = -1
M.mapAbyssBg = -1
M.mapSlimeRevengeBg = -1
M.charAvatarImg = -1
M.moneyBagImg = -1
M.lockClosedImg = -1
M.lockOpenImg = -1

--- 判断玩家当前是否装备弓
local function playerHasBow()
    local wr = GS.equipment and GS.equipment["weapon_r"]
    return wr and wr.weaponTag == "弓"
end

--- 判断玩家当前是否装备锤
local function playerHasMace()
    local wr = GS.equipment and GS.equipment["weapon_r"]
    return wr and wr.weaponTag == "锤"
end

--- 判断玩家当前是否装备法杖
local function playerHasStaff()
    local wr = GS.equipment and GS.equipment["weapon_r"]
    return wr and wr.weaponTag == "法杖"
end

--- 判断玩家是否赤手空拳（左右武器栏都没装备）
local function playerIsBareHanded()
    local wr = GS.equipment and GS.equipment["weapon_r"]
    local wl = GS.equipment and GS.equipment["weapon_l"]
    return not wr and not wl
end

--- 获取当前武器图片句柄（弓/锤/剑，赤手空拳时返回-1）
function M.getWeaponImage()
    if playerIsBareHanded() then
        return -1, false  -- 赤手空拳，不显示悬浮武器
    end
    if playerHasBow() and M.bowImage ~= -1 then
        return M.bowImage, true  -- image, isBow
    end
    if playerHasMace() and M.maceImage ~= -1 then
        return M.maceImage, false  -- image, isBow=false
    end
    if playerHasStaff() and M.staffImage ~= -1 then
        return M.staffImage, false  -- image, isBow=false
    end
    return M.swordImage, false
end

-- ====================================================================
-- 面板文字辅助函数（从 Renderer_Utils.lua 引入）
-- ====================================================================
local OFFSETS_4 = Utils.OFFSETS_4
local OFFSETS_8 = Utils.OFFSETS_8
local safeProgress = Utils.safeProgress
local drawTextOutlined = Utils.drawTextOutlined
local isHovered = Utils.isHovered
local drawHoverHighlight = Utils.drawHoverHighlight

-- ====================================================================
-- 路径绘制五角星（金属质感）
-- cx, cy: 中心坐标; r: 外半径; mode: "slot"(格子角标) / "btn"(按钮图标)
-- active: 是否激活状态(金色/灰色)
-- ====================================================================
function M.drawStarPath(vg, cx, cy, r, mode, active)
    if active == nil then active = true end
    local innerR = r * 0.38
    -- 构建五角星路径（顶点朝上，-90度起始）
    local function buildStar()
        nvgBeginPath(vg)
        for i = 0, 9 do
            local angle = math.rad(-90 + i * 36)
            local radius = (i % 2 == 0) and r or innerR
            local px = cx + radius * math.cos(angle)
            local py = cy + radius * math.sin(angle)
            if i == 0 then
                nvgMoveTo(vg, px, py)
            else
                nvgLineTo(vg, px, py)
            end
        end
        nvgClosePath(vg)
    end
    if active then
        -- 1) 阴影层
        nvgSave(vg)
        buildStar()
        -- 用偏移模拟阴影不容易，直接画一个偏移的深色星
        nvgBeginPath(vg)
        local shOff = math.max(1, r * 0.1)
        for i = 0, 9 do
            local angle = math.rad(-90 + i * 36)
            local radius = (i % 2 == 0) and r or innerR
            local px = cx + shOff + radius * math.cos(angle)
            local py = cy + shOff + radius * math.sin(angle)
            if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
        end
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(60, 40, 0, 160))
        nvgFill(vg)
        nvgRestore(vg)
        -- 2) 主体：金色渐变填充
        buildStar()
        local grad = nvgLinearGradient(vg, cx, cy - r, cx, cy + r,
            nvgRGBA(255, 240, 100, 255),   -- 顶部：亮金
            nvgRGBA(200, 140, 20, 255))    -- 底部：深金
        nvgFillPaint(vg, grad)
        nvgFill(vg)
        -- 3) 高光层：上半部分叠加亮色
        buildStar()
        local highlightGrad = nvgLinearGradient(vg, cx, cy - r, cx, cy,
            nvgRGBA(255, 255, 220, 140),   -- 顶部高光
            nvgRGBA(255, 255, 220, 0))     -- 中部透明
        nvgFillPaint(vg, highlightGrad)
        nvgFill(vg)
        -- 4) 描边
        buildStar()
        nvgStrokeColor(vg, nvgRGBA(160, 110, 10, 200))
        nvgStrokeWidth(vg, math.max(0.5, r * 0.08))
        nvgStroke(vg)
    else
        -- 灰色未激活状态（仅按钮模式用）
        buildStar()
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 160))
        nvgFill(vg)
        buildStar()
        nvgStrokeColor(vg, nvgRGBA(100, 100, 100, 120))
        nvgStrokeWidth(vg, math.max(0.5, r * 0.08))
        nvgStroke(vg)
    end
end

-- ====================================================================
-- 布局计算
-- ====================================================================
function M.updateLayout()
    local g = GetGraphics()
    local physW, physH = g:GetWidth(), g:GetHeight()
    GS.dpr = g:GetDPR()
    local logicalW, logicalH = physW / GS.dpr, physH / GS.dpr

    -- 启动保护期：前 0.5 秒内只看 forceLandscape，避免手机端系统旋转延迟导致横屏闪烁
    -- 保护期结束后恢复物理尺寸检测，PC 端拖动窗口仍可自动切换布局
    if GS.startupElapsed < 0.5 then
        GS.startupElapsed = GS.startupElapsed + (1.0 / 60.0)
        GS.isLandscape = GS.forceLandscape
    else
        GS.isLandscape = logicalW > logicalH or GS.forceLandscape
    end

    if GS.isLandscape then
        local DESIGN_H_LAND = 450
        GS.S = logicalH / DESIGN_H_LAND
        GS.SCREEN_W = logicalW / GS.S
        GS.SCREEN_H = DESIGN_H_LAND
    else
        GS.S = logicalW / GS.DESIGN_W
        GS.SCREEN_W = GS.DESIGN_W
        GS.SCREEN_H = logicalH / GS.S
    end

    -- 获取安全区域（灵动岛/刘海屏/状态栏），转换到设计坐标系
    local safeTop = 0
    if GetSafeAreaInsets then
        local ok, rect = pcall(GetSafeAreaInsets, false)
        if ok and rect then
            safeTop = rect.min.y / (GS.dpr * GS.S)
        end
    end
    GS.safeTop = safeTop

    -- TOP_BAR_H = 基础高度 + 安全区域顶部
    local BASE_TOP_BAR = 44
    GS.TOP_BAR_H = BASE_TOP_BAR + safeTop
    -- 顶栏内容的垂直中心（安全区域下方的中间位置）
    GS.TOP_BAR_CONTENT_MID_Y = safeTop + BASE_TOP_BAR / 2

    GS.INFO_H = 36

    if GS.isLandscape then
        GS.BOTTOM_H = 0
        local boardPad = 8
        local bottomBarH = GS.EXP_BAR_H + GS.EXP_GAP + GS.INFO_H
        local availH = GS.SCREEN_H - GS.TOP_BAR_H - bottomBarH - boardPad * 3
        local gap = boardPad * 2  -- 棋盘与面板之间的间距
        -- 水平约束：确保棋盘和面板能保持等宽（两侧各 boardPad + 中间 gap）
        local maxBoardW = math.floor((GS.SCREEN_W - gap - boardPad * 2) / 2)
        GS.CELL = math.floor(math.min(availH, maxBoardW) / GS.BOARD_SIZE)
        local boardPixel = GS.CELL * GS.BOARD_SIZE

        -- 右侧面板宽度限制为棋盘宽度，保持左右大体相等
        local maxPanelW = boardPixel
        local panelW = GS.SCREEN_W - boardPad - boardPixel - gap - boardPad
        if panelW > maxPanelW then
            panelW = maxPanelW
        end
        -- 内容总宽度 = 棋盘 + 间距 + 面板
        local contentW = boardPixel + gap + panelW
        -- 居中偏移
        local offsetX = math.floor((GS.SCREEN_W - contentW) / 2)
        if offsetX < boardPad then offsetX = boardPad end

        GS.BOARD_X = offsetX
        GS.BOARD_Y = GS.TOP_BAR_H + math.floor((availH - boardPixel) / 2) + boardPad

        GS.RIGHT_PANEL_X = GS.BOARD_X + boardPixel + gap
        GS.RIGHT_PANEL_W = panelW
    else
        GS.BOTTOM_H = math.floor(GS.SCREEN_H * 0.48)
        local availH = GS.SCREEN_H - GS.TOP_BAR_H - GS.BOTTOM_H - GS.INFO_H - GS.EXP_BAR_H - GS.EXP_GAP - 10
        local availW = GS.SCREEN_W - 16
        local boardArea = math.min(availW, availH)
        GS.CELL = math.floor(boardArea / GS.BOARD_SIZE)
        local boardPixel = GS.CELL * GS.BOARD_SIZE
        GS.BOARD_X = math.floor((GS.SCREEN_W - boardPixel) / 2)
        GS.BOARD_Y = GS.TOP_BAR_H + math.floor((availH - boardPixel) / 2) + 4
    end

    return logicalW, logicalH
end

-- ====================================================================
-- 动画偏移计算
-- ====================================================================
function M.getMoveAnimOffset(unit)
    if not unit.moveAnim then return 0, 0, 1.0 end
    local anim = unit.moveAnim
    local t = safeProgress(anim.timer, anim.duration)
    local ease = t * t * (3 - 2 * t)

    if anim.path and #anim.path >= 2 then
        -- 多段路径：沿 waypoints 逐段插值
        local totalSegs = #anim.path - 1
        local pos = ease * totalSegs  -- 0 ~ totalSegs
        local segIdx = math.floor(pos)
        local segT = pos - segIdx
        if segIdx >= totalSegs then
            segIdx = totalSegs - 1
            segT = 1.0
        end
        local p1 = anim.path[segIdx + 1]
        local p2 = anim.path[segIdx + 2]
        local curX = p1[1] + (p2[1] - p1[1]) * segT
        local curY = p1[2] + (p2[2] - p1[2]) * segT
        local dx = (curX - unit.x) * GS.CELL
        local dy = (curY - unit.y) * GS.CELL
        return dx, dy, t
    else
        -- 单段直线（击退等）
        local dx = (anim.fromX - unit.x) * GS.CELL * (1 - ease)
        local dy = (anim.fromY - unit.y) * GS.CELL * (1 - ease)
        return dx, dy, t
    end
end

--- 计算路径动画在 ease 进度处的像素坐标（用于轨迹/残影）
--- @return number px, number py
local function getPathPixelPos(anim, ease, cellSize, boardX, boardY, halfCell, unitX, unitY)
    if anim.path and #anim.path >= 2 then
        local totalSegs = #anim.path - 1
        local pos = ease * totalSegs
        local segIdx = math.floor(pos)
        local segT = pos - segIdx
        if segIdx >= totalSegs then segIdx = totalSegs - 1; segT = 1.0 end
        local p1 = anim.path[segIdx + 1]
        local p2 = anim.path[segIdx + 2]
        local gx = p1[1] + (p2[1] - p1[1]) * segT
        local gy = p1[2] + (p2[2] - p1[2]) * segT
        return boardX + (gx - 1) * cellSize + halfCell,
               boardY + (gy - 1) * cellSize + halfCell
    else
        -- 单段直线 fallback（击退等）
        local fromPx = boardX + (anim.fromX - 1) * cellSize + halfCell
        local fromPy = boardY + (anim.fromY - 1) * cellSize + halfCell
        local toUX = unitX or anim.fromX
        local toUY = unitY or anim.fromY
        local toPx = boardX + (toUX - 1) * cellSize + halfCell
        local toPy = boardY + (toUY - 1) * cellSize + halfCell
        return fromPx + (toPx - fromPx) * ease, fromPy + (toPy - fromPy) * ease
    end
end

function M.getSlamAnimOffset(unit)
    if not unit.slamAnim then return 0, 0, 1.0 end
    local anim = unit.slamAnim
    local t = safeProgress(anim.timer, anim.duration)
    local slamProgress = math.sin(math.pi * t)
    local ox = anim.dirX * anim.slamDist * slamProgress
    local oy = anim.dirY * anim.slamDist * slamProgress
    return ox, oy, t
end

-- ====================================================================
-- 绘制：背景
-- ====================================================================
function M.drawBackground()
    local vg = M.vg
    -- 动态获取当前关卡背景（懒加载+缓存）
    -- 夜间替换（18:00~5:00）
    local bgPath = GS.currentBattleBg
    local NIGHT_BG_MAP = {
        ["image/bg_grass.png"]     = "image/bg_grass_night.png",
        ["image/bg_sea.png"]       = "image/bg_sea_night.png",
        ["image/bg_beach.png"]     = "image/bg_beach_night.png",
        ["image/bg_graveyard.png"] = "image/bg_graveyard_night.png",
        ["image/bg_crypt.png"]     = "image/bg_crypt_night.png",
        ["image/bg_forest.png"]    = "image/bg_forest_night.png",
        ["image/bg_manor.png"]     = "image/bg_manor_night.png",
        ["image/bg_mine_entrance.png"] = "image/bg_mine_entrance_night.png",
        ["image/bg_forest_cave.png"]   = "image/bg_forest_cave_night.png",
        ["image/bg_sea_cave.png"]      = "image/bg_sea_cave_night.png",
        ["image/bg_mount_cave.png"]    = "image/bg_mount_cave_night.png",
        ["image/bg_gather_plain.png"]  = "image/bg_gather_plain_night.png",
        ["image/bg_gather_forest.png"] = "image/bg_gather_forest_night.png",
        ["image/bg_gather_sea.png"]    = "image/bg_gather_sea_night.png",
        ["image/bg_gather_manor.png"]  = "image/bg_gather_manor_night.png",
        ["image/bg_gather_fort.png"]   = "image/bg_gather_fort_night.png",
        ["image/bg_fort_bridge_day.png"] = "image/bg_fort_bridge_night.png",
        ["image/bg_forest_deep.png"]   = "image/bg_forest_deep_glow.png",
        ["image/bg_training.png"]      = "image/bg_training_night.png",
    }
    local nightBg = NIGHT_BG_MAP[bgPath]
    if nightBg then
        local hour = BoardOverlay.getGameHour()
        if hour >= 18 or hour < 5 then
            bgPath = nightBg
        end
    end
    local bgHandle = ImageManager.lazyGet("bg", bgPath)
    if bgHandle ~= -1 then
        local imgW, imgH = nvgImageSize(vg, bgHandle)
        -- 竖屏战斗时底部面板会遮挡，背景只需填满面板上方可见区域（菜单界面不受影响）
        local visibleBottom = GS.SCREEN_H
        if not GS.isLandscape and GS.BOTTOM_H > 0 and GS.gameState ~= GS.STATE_MENU and GS.gameState ~= GS.STATE_GAMEOVER
           and GS.gameState ~= GS.STATE_CHAR_SELECT and GS.gameState ~= GS.STATE_CHAR_CREATE then
            visibleBottom = GS.SCREEN_H - GS.BOTTOM_H
        end
        local scaleX = GS.SCREEN_W / imgW
        local scaleY = visibleBottom / imgH
        local scale = math.max(scaleX, scaleY)
        local drawW = imgW * scale
        local drawH = imgH * scale
        local ox = (GS.SCREEN_W - drawW) / 2
        local oy = visibleBottom - drawH  -- 底部对齐可见区域底部

        -- 背景渐变过渡动画（仅昼夜切换时渐变，切换地图/关卡直接硬切）
        local BG_FADE_DUR = 1.5
        local baseBg = GS.currentBattleBg or ""  -- 原始背景路径（不含昼夜替换）
        -- 场景标识：bg路径+关卡，避免同bg不同地点误判为昼夜切换
        local sceneKey = baseBg .. "|" .. tostring(GS.currentStage or 0)
        if not M._fieldBgSceneKey then M._fieldBgSceneKey = sceneKey end
        if not M._fieldBgOldHandle then M._fieldBgOldHandle = bgHandle end
        if not M._fieldBgFadeProgress then M._fieldBgFadeProgress = 1.0 end
        if sceneKey ~= M._fieldBgSceneKey then
            -- 切换了地图或关卡：直接硬切
            M._fieldBgSceneKey = sceneKey
            M._fieldBgOldHandle = bgHandle
            M._fieldBgFadePrev = nil
            M._fieldBgFadeProgress = 1.0
        elseif bgHandle ~= M._fieldBgOldHandle then
            -- 同一地图内图片变了（昼夜切换）：启动渐变
            if M._fieldBgFadeProgress >= 1.0 then
                M._fieldBgFadePrev = M._fieldBgOldHandle
                M._fieldBgFadeProgress = 0.0
            end
            M._fieldBgOldHandle = bgHandle
        end
        if M._fieldBgFadeProgress < 1.0 then
            local frameDt = time and time.timeStep or (1.0 / 60.0)
            M._fieldBgFadeProgress = math.min(1.0, M._fieldBgFadeProgress + frameDt / BG_FADE_DUR)
        end

        if M._fieldBgFadePrev and M._fieldBgFadeProgress < 1.0 then
            -- 先画旧背景
            local oldW, oldH = nvgImageSize(vg, M._fieldBgFadePrev)
            local oScaleX = GS.SCREEN_W / oldW
            local oScaleY = visibleBottom / oldH
            local oScale = math.max(oScaleX, oScaleY)
            local oDW, oDH = oldW * oScale, oldH * oScale
            local oOx = (GS.SCREEN_W - oDW) / 2
            local oOy = visibleBottom - oDH
            local patOld = nvgImagePattern(vg, oOx, oOy, oDW, oDH, 0, M._fieldBgFadePrev, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
            nvgFillPaint(vg, patOld)
            nvgFill(vg)
            -- 叠加新背景（alpha 渐入）
            local patNew = nvgImagePattern(vg, ox, oy, drawW, drawH, 0, bgHandle, M._fieldBgFadeProgress)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
            nvgFillPaint(vg, patNew)
            nvgFill(vg)
        else
            M._fieldBgFadePrev = nil
            local imgPaint = nvgImagePattern(vg, ox, oy, drawW, drawH, 0, bgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        end

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
        nvgFillColor(vg, nvgRGBA(10, 15, 25, 90))
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
        local bg = nvgLinearGradient(vg, 0, 0, 0, GS.SCREEN_H,
            nvgRGBA(20, 25, 40, 255), nvgRGBA(15, 18, 30, 255))
        nvgFillPaint(vg, bg)
        nvgFill(vg)
    end
end

-- ====================================================================
-- 绘制：棋盘
-- ====================================================================
function M.drawBoardFrame()
    local vg = M.vg
    nvgBeginPath(vg)
    nvgRoundedRect(vg, GS.BOARD_X - 4, GS.BOARD_Y - 4, GS.CELL * GS.BOARD_SIZE + 8, GS.CELL * GS.BOARD_SIZE + 8, 6)
    nvgFillColor(vg, nvgRGBA(20, 25, 35, 120))
    nvgFill(vg)
end

function M.drawBoardCells(extraRowsAbove)
    local vg = M.vg
    local startY = 1 - (extraRowsAbove or 0)
    for y = startY, GS.BOARD_SIZE do
        for x = 1, GS.BOARD_SIZE do
            local px = GS.BOARD_X + (x - 1) * GS.CELL
            local py = GS.BOARD_Y + (y - 1) * GS.CELL

            local light = (x + y) % 2 == 0
            nvgBeginPath(vg)
            nvgRect(vg, px, py, GS.CELL, GS.CELL)
            if light then
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 18))
            else
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 18))
            end
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRect(vg, px, py, GS.CELL, GS.CELL)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 30))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
        end
    end
end

function M.drawBoard()
    M.drawBoardFrame()
    M.drawBoardCells()
end

--- 训练场调试：显示方向攻击判定区域（黄色=侧方，红色=背后）


-- ====================================================================
-- 绘制：家场景房间（地板+墙壁）
-- ====================================================================
function M.drawHomeRoom()
    if not GS.homeMode then return end
    local vg = M.vg
    local cell = GS.CELL

    -- 根据家园类型获取房间参数
    local rp = GS.getHomeRoomParams(GS.homeType)
    local HOME_ROOM_X1 = rp.fx1
    local HOME_ROOM_Y1 = rp.fy1
    local HOME_ROOM_X2 = rp.fx2
    local HOME_ROOM_Y2 = rp.fy2
    local HOME_DOOR_X1 = rp.doorX1
    local HOME_DOOR_X2 = rp.doorX2
    local HOME_DOOR_Y  = rp.doorY

    -- 加载贴图
    local floorImg = ImageManager.lazyGet("home_floor", "tile_pine_floor_20260310125537.png")
    local wallImg  = ImageManager.lazyGet("home_wall",  "image/tile_stone_wall.png")

    local wx1, wy1 = HOME_ROOM_X1 - 1, HOME_ROOM_Y1 - 1
    local wx2, wy2 = HOME_ROOM_X2 + 1, HOME_ROOM_Y2 + 1

    -- 坐标计算
    local halfCell = cell * 0.5
    local leftPx   = GS.BOARD_X + (wx1 - 1) * cell
    local rightPx  = GS.BOARD_X + (wx2 - 1) * cell
    local topPy    = GS.BOARD_Y + (wy1 - 1) * cell
    local botPy    = GS.BOARD_Y + (wy2 - 1) * cell
    local innerL   = leftPx + halfCell
    local innerR   = rightPx + halfCell
    local innerT   = topPy + halfCell
    local innerB   = botPy + halfCell

    local floorL = innerL + halfCell
    local floorR = innerR - halfCell
    local floorT = innerT + halfCell
    local floorB = botPy

    local doorLeftPx  = GS.BOARD_X + (HOME_DOOR_X1 - 1) * cell
    local doorRightPx = GS.BOARD_X + HOME_DOOR_X2 * cell

    -- === 第1步：用一个大矩形填充整个区域（墙壁色），内部无任何边界 ===
    nvgBeginPath(vg)
    nvgRect(vg, innerL, innerT, innerR - innerL, innerB - innerT)
    nvgFillColor(vg, nvgRGBA(50, 50, 50, 255))
    nvgFill(vg)

    -- === 第2步：在中心绘制木地板（不透明贴图覆盖墙壁色） ===
    if floorImg ~= -1 then
        for y = HOME_ROOM_Y1, HOME_ROOM_Y2 do
            for x = HOME_ROOM_X1, HOME_ROOM_X2 do
                local px = GS.BOARD_X + (x - 1) * cell
                local py = GS.BOARD_Y + (y - 1) * cell
                local pat = nvgImagePattern(vg, px, py, cell, cell, 0, floorImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, px, py, cell, cell)
                nvgFillPaint(vg, pat)
                nvgFill(vg)
            end
        end
    end

    -- === 第3步：描边（只画外轮廓和内轮廓） ===
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgStrokeWidth(vg, 1.5)

    -- 外轮廓（含门洞缺口）
    nvgBeginPath(vg)
    nvgMoveTo(vg, innerL, innerT)
    nvgLineTo(vg, innerR, innerT)
    nvgLineTo(vg, innerR, innerB)
    nvgLineTo(vg, doorRightPx, innerB)
    nvgLineTo(vg, doorRightPx, floorB)
    nvgLineTo(vg, doorLeftPx, floorB)
    nvgLineTo(vg, doorLeftPx, innerB)
    nvgLineTo(vg, innerL, innerB)
    nvgClosePath(vg)
    nvgStroke(vg)

    -- 内轮廓（面向地板的边缘）
    nvgBeginPath(vg)
    nvgMoveTo(vg, floorL, floorT)
    nvgLineTo(vg, floorR, floorT)
    nvgLineTo(vg, floorR, floorB)
    nvgMoveTo(vg, floorR, floorB)
    nvgLineTo(vg, doorRightPx, floorB)
    nvgMoveTo(vg, doorLeftPx, floorB)
    nvgLineTo(vg, floorL, floorB)
    nvgLineTo(vg, floorL, floorT)
    nvgStroke(vg)

    -- 绘制门（下墙中间2格：通道纵深效果 + 门框 + 呼吸光效）
    do
        local doorPx = GS.BOARD_X + (HOME_DOOR_X1 - 1) * cell
        local doorPy = GS.BOARD_Y + (HOME_DOOR_Y - 1) * cell
        local doorW = cell * 2  -- 2格宽
        local doorH = cell      -- 整格高
        local t = os.clock()

        -- 透明度渐变遮罩：上方完全不透明 → 下方微微透明
        -- 先用全局透明度控制整个门区域
        nvgSave(vg)

        -- 多层渐变模拟通道纵深（铺满整个2格）
        -- 第一层：整体暗色覆盖（上方浓 → 下方淡）
        local grad1 = nvgLinearGradient(vg, doorPx, doorPy, doorPx, doorPy + doorH,
            nvgRGBA(5, 3, 2, 240), nvgRGBA(20, 15, 10, 30))
        nvgBeginPath(vg)
        nvgRect(vg, doorPx, doorPy, doorW, doorH)
        nvgFillPaint(vg, grad1)
        nvgFill(vg)
        -- 第二层：出口强光（铺满底部）
        local exitGrad = nvgLinearGradient(vg, doorPx, doorPy + doorH * 0.3,
            doorPx, doorPy + doorH,
            nvgRGBA(0, 0, 0, 0), nvgRGBA(255, 245, 220, 220))
        nvgBeginPath(vg)
        nvgRect(vg, doorPx, doorPy, doorW, doorH)
        nvgFillPaint(vg, exitGrad)
        nvgFill(vg)

        -- 呼吸光效（缓慢脉冲的强暖光，铺满整格）
        local pulse = 0.4 + 0.3 * math.sin(t * 2.0)
        local glowGrad = nvgLinearGradient(vg, doorPx, doorPy + doorH * 0.15,
            doorPx, doorPy + doorH,
            nvgRGBA(0, 0, 0, 0), nvgRGBA(255, 240, 180, math.floor(pulse * 255)))
        nvgBeginPath(vg)
        nvgRect(vg, doorPx, doorPy, doorW, doorH)
        nvgFillPaint(vg, glowGrad)
        nvgFill(vg)

        nvgRestore(vg)

        -- 4) 门框（左右两侧黑色柱 + 灰色描边，与墙体统一风格）
        local frameW = cell * 0.15
        local frameH = doorH + 2
        -- 左门框：深灰填充 + 黑色描边
        nvgBeginPath(vg)
        nvgRect(vg, doorPx - frameW, doorPy - 1, frameW, frameH)
        nvgFillColor(vg, nvgRGBA(50, 50, 50, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, doorPx - frameW, doorPy - 1, frameW, frameH)
        nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 右门框：深灰填充 + 黑色描边
        nvgBeginPath(vg)
        nvgRect(vg, doorPx + doorW, doorPy - 1, frameW, frameH)
        nvgFillColor(vg, nvgRGBA(50, 50, 50, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, doorPx + doorW, doorPy - 1, frameW, frameH)
        nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 门框高光（内侧边缘，柔和灰色）
        nvgStrokeWidth(vg, 1.0)
        nvgBeginPath(vg)
        nvgMoveTo(vg, doorPx, doorPy - 1)
        nvgLineTo(vg, doorPx, doorPy + doorH)
        nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 60))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, doorPx + doorW, doorPy - 1)
        nvgLineTo(vg, doorPx + doorW, doorPy + doorH)
        nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 60))
        nvgStroke(vg)
        -- 门框顶部横梁
        nvgBeginPath(vg)
        nvgMoveTo(vg, doorPx - frameW, doorPy - 1)
        nvgLineTo(vg, doorPx + doorW + frameW, doorPy - 1)
        nvgStrokeColor(vg, nvgRGBA(80, 80, 80, 120))
        nvgStroke(vg)
    end

    -- 墙壁立体感：内侧阴影线（只在墙壁厚度内画，不穿越其他墙面）
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 80))
    -- 上墙底边阴影（只画上墙宽度范围）
    nvgBeginPath(vg)
    nvgMoveTo(vg, floorL, floorT)
    nvgLineTo(vg, floorR, floorT)
    nvgStroke(vg)
    -- 下墙顶边阴影（左段 + 右段，跳过门洞）
    nvgBeginPath(vg)
    nvgMoveTo(vg, floorL, floorB)
    nvgLineTo(vg, doorLeftPx, floorB)
    nvgMoveTo(vg, doorRightPx, floorB)
    nvgLineTo(vg, floorR, floorB)
    nvgStroke(vg)
    -- 左墙右边阴影（只画左墙高度范围）
    nvgBeginPath(vg)
    nvgMoveTo(vg, floorL, floorT)
    nvgLineTo(vg, floorL, floorB)
    nvgStroke(vg)
    -- 右墙左边阴影（只画右墙高度范围）
    nvgBeginPath(vg)
    nvgMoveTo(vg, floorR, floorT)
    nvgLineTo(vg, floorR, floorB)
    nvgStroke(vg)

    -- ================================================================
    -- 绘制内墙（中型/大型家园的隔墙）
    -- 中型：整格填充，与外墙贯通，只在面向地板侧描边
    -- 大型：居中 halfCell 宽度，独立描边
    -- ================================================================
    local innerWalls = GS.HOME_INNER_WALLS[GS.homeType]
    if innerWalls and #innerWalls > 0 then
        local p = GS.getHomeRoomParams(GS.homeType)

        -- 构建内墙坐标集合（用于判断相邻格是否也是内墙/外墙）
        local wallSet = {}
        local wallDirMap = {}  -- 记录每个内墙格的方向 ("h"/"v"/"hv")
        for _, w in ipairs(innerWalls) do
            wallSet[w.x .. "," .. w.y] = true
            wallDirMap[w.x .. "," .. w.y] = w.d or "h"
        end
        local function isWallOrOuter(x, y)
            -- 外墙范围
            if x >= p.wx1 and x <= p.wx2 and y >= p.wy1 and y <= p.wy2 then
                if x == p.wx1 or x == p.wx2 or y == p.wy1 or y == p.wy2 then
                    return true  -- 外墙格
                end
            end
            return wallSet[x .. "," .. y] or false
        end

        if GS.homeType == "medium" or GS.homeType == "large" then
            -- ── 中型/大型：按连续段合并成单个矩形（halfCell 高，与外墙等厚） ──
            -- 按方向和行/列分组，找出连续段
            local hSegments = {}  -- 横向连续段 { {minX, maxX, y}, ... }
            local vSegments = {}  -- 纵向连续段 { {x, minY, maxY}, ... }
            -- 收集横向墙和纵向墙
            local hWalls, vWalls = {}, {}
            for _, w in ipairs(innerWalls) do
                local d = w.d or "h"
                if d == "h" or d == "hv" then table.insert(hWalls, w) end
                if d == "v" or d == "hv" then table.insert(vWalls, w) end
            end
            -- 横向：按 y 分组，合并同行连续 x
            local hByY = {}
            for _, w in ipairs(hWalls) do
                hByY[w.y] = hByY[w.y] or {}
                table.insert(hByY[w.y], w.x)
            end
            for y, xs in pairs(hByY) do
                table.sort(xs)
                local startX = xs[1]
                local endX = xs[1]
                for i = 2, #xs do
                    if xs[i] == endX + 1 then
                        endX = xs[i]
                    else
                        table.insert(hSegments, {startX, endX, y})
                        startX = xs[i]; endX = xs[i]
                    end
                end
                table.insert(hSegments, {startX, endX, y})
            end
            -- 纵向：按 x 分组，合并同列连续 y
            local vByX = {}
            for _, w in ipairs(vWalls) do
                vByX[w.x] = vByX[w.x] or {}
                table.insert(vByX[w.x], w.y)
            end
            for x, ys in pairs(vByX) do
                table.sort(ys)
                local startY = ys[1]
                local endY = ys[1]
                for i = 2, #ys do
                    if ys[i] == endY + 1 then
                        endY = ys[i]
                    else
                        table.insert(vSegments, {x, startY, endY})
                        startY = ys[i]; endY = ys[i]
                    end
                end
                table.insert(vSegments, {x, startY, endY})
            end

            -- 外墙内边缘坐标（用于限制描边范围）
            local iwFloorL = GS.BOARD_X + (p.fx1 - 1) * cell
            local iwFloorR = GS.BOARD_X + p.fx2 * cell
            local iwFloorT = GS.BOARD_Y + (p.fy1 - 1) * cell
            local iwFloorB = GS.BOARD_Y + p.fy2 * cell

            -- 绘制横向段（halfCell 高，居中在格子纵向中心）
            -- 策略：填充只覆盖内墙自身的格子范围（不向外墙延伸），
            -- 因为外墙已经是同色深灰大矩形，自然无缝衔接。
            -- 描边只画面向地板的边，且到外墙内边缘截断。
            -- 横向段和纵向段的长边需要逐格检查邻居，分段画描边。
            for _, seg in ipairs(hSegments) do
                local sx, ex, sy = seg[1], seg[2], seg[3]
                local rx = GS.BOARD_X + (sx - 1) * cell
                local segW = (ex - sx + 1) * cell
                local ry = GS.BOARD_Y + (sy - 1) * cell + (cell - halfCell) * 0.5
                local leftTouchWall = isWallOrOuter(sx - 1, sy)
                local rightTouchWall = isWallOrOuter(ex + 1, sy)
                -- 填充（单个矩形，无接缝）
                nvgBeginPath(vg)
                nvgRect(vg, rx, ry, segW, halfCell)
                nvgFillColor(vg, nvgRGBA(50, 50, 50, 255))
                nvgFill(vg)
                -- 描边
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
                nvgStrokeWidth(vg, 1.5)
                -- 上边和下边：逐格检查，合并连续开放段画线
                for _, side in ipairs({"top", "bot"}) do
                    local dy = (side == "top") and (sy - 1) or (sy + 1)
                    local lineY = (side == "top") and ry or (ry + halfCell)
                    local runStart = nil
                    for ix = sx, ex + 1 do
                        local open = (ix <= ex) and (not isWallOrOuter(ix, dy))
                        if open then
                            if not runStart then runStart = ix end
                        else
                            if runStart then
                                local lx = GS.BOARD_X + (runStart - 1) * cell
                                local lxEnd = GS.BOARD_X + (ix - 1) * cell
                                -- 首格靠外墙时截断到外墙内边缘
                                if runStart == sx and leftTouchWall then lx = iwFloorL end
                                -- 末格靠外墙时截断
                                if ix - 1 == ex and rightTouchWall then lxEnd = iwFloorR end
                                nvgBeginPath(vg)
                                nvgMoveTo(vg, lx, lineY); nvgLineTo(vg, lxEnd, lineY)
                                nvgStroke(vg)
                                runStart = nil
                            end
                        end
                    end
                end
                -- 左端封口（不靠墙时画）
                if not leftTouchWall then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, rx, ry); nvgLineTo(vg, rx, ry + halfCell)
                    nvgStroke(vg)
                end
                -- 右端封口（不靠墙时画）
                if not rightTouchWall then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, rx + segW, ry); nvgLineTo(vg, rx + segW, ry + halfCell)
                    nvgStroke(vg)
                end
            end

            -- 绘制纵向段（halfCell 宽，居中在格子横向中心）
            for _, seg in ipairs(vSegments) do
                local sx, sy, ey = seg[1], seg[2], seg[3]
                local ry = GS.BOARD_Y + (sy - 1) * cell
                local segH = (ey - sy + 1) * cell
                local rx = GS.BOARD_X + (sx - 1) * cell + (cell - halfCell) * 0.5
                local topTouchWall = isWallOrOuter(sx, sy - 1)
                local botTouchWall = isWallOrOuter(sx, ey + 1)
                -- 填充
                nvgBeginPath(vg)
                nvgRect(vg, rx, ry, halfCell, segH)
                nvgFillColor(vg, nvgRGBA(50, 50, 50, 255))
                nvgFill(vg)
                -- 描边
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
                nvgStrokeWidth(vg, 1.5)
                -- 左边和右边：逐格检查，合并连续开放段画线
                for _, side in ipairs({"left", "right"}) do
                    local dx = (side == "left") and (sx - 1) or (sx + 1)
                    local lineX = (side == "left") and rx or (rx + halfCell)
                    local runStart = nil
                    for iy = sy, ey + 1 do
                        local open = (iy <= ey) and (not isWallOrOuter(dx, iy))
                        if open then
                            if not runStart then runStart = iy end
                        else
                            if runStart then
                                local ly = GS.BOARD_Y + (runStart - 1) * cell
                                local lyEnd = GS.BOARD_Y + (iy - 1) * cell
                                -- 首格靠外墙时截断
                                if runStart == sy and topTouchWall then ly = iwFloorT end
                                -- 末格靠外墙时截断
                                if iy - 1 == ey and botTouchWall then lyEnd = iwFloorB end
                                nvgBeginPath(vg)
                                nvgMoveTo(vg, lineX, ly); nvgLineTo(vg, lineX, lyEnd)
                                nvgStroke(vg)
                                runStart = nil
                            end
                        end
                    end
                end
                -- 上端封口
                if not topTouchWall then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, rx, ry); nvgLineTo(vg, rx + halfCell, ry)
                    nvgStroke(vg)
                end
                -- 下端封口
                if not botTouchWall then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, rx, ry + segH); nvgLineTo(vg, rx + halfCell, ry + segH)
                    nvgStroke(vg)
                end
            end

            -- 阴影：逐格检查邻居，分段画
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 80))
            nvgStrokeWidth(vg, 1.5)
            for _, seg in ipairs(hSegments) do
                local sx, ex, sy = seg[1], seg[2], seg[3]
                local ry = GS.BOARD_Y + (sy - 1) * cell + (cell - halfCell) * 0.5
                local leftTouchWall = isWallOrOuter(sx - 1, sy)
                local rightTouchWall = isWallOrOuter(ex + 1, sy)
                for _, side in ipairs({"top", "bot"}) do
                    local dy = (side == "top") and (sy - 1) or (sy + 1)
                    local lineY = (side == "top") and ry or (ry + halfCell)
                    local runStart = nil
                    for ix = sx, ex + 1 do
                        local open = (ix <= ex) and (not isWallOrOuter(ix, dy))
                        if open then
                            if not runStart then runStart = ix end
                        else
                            if runStart then
                                local lx = GS.BOARD_X + (runStart - 1) * cell
                                local lxEnd = GS.BOARD_X + (ix - 1) * cell
                                if runStart == sx and leftTouchWall then lx = iwFloorL end
                                if ix - 1 == ex and rightTouchWall then lxEnd = iwFloorR end
                                nvgBeginPath(vg)
                                nvgMoveTo(vg, lx, lineY); nvgLineTo(vg, lxEnd, lineY)
                                nvgStroke(vg)
                                runStart = nil
                            end
                        end
                    end
                end
            end
            for _, seg in ipairs(vSegments) do
                local sx, sy, ey = seg[1], seg[2], seg[3]
                local rx = GS.BOARD_X + (sx - 1) * cell + (cell - halfCell) * 0.5
                local topTouchWall = isWallOrOuter(sx, sy - 1)
                local botTouchWall = isWallOrOuter(sx, ey + 1)
                for _, side in ipairs({"left", "right"}) do
                    local dx = (side == "left") and (sx - 1) or (sx + 1)
                    local lineX = (side == "left") and rx or (rx + halfCell)
                    local runStart = nil
                    for iy = sy, ey + 1 do
                        local open = (iy <= ey) and (not isWallOrOuter(dx, iy))
                        if open then
                            if not runStart then runStart = iy end
                        else
                            if runStart then
                                local ly = GS.BOARD_Y + (runStart - 1) * cell
                                local lyEnd = GS.BOARD_Y + (iy - 1) * cell
                                if runStart == sy and topTouchWall then ly = iwFloorT end
                                if iy - 1 == ey and botTouchWall then lyEnd = iwFloorB end
                                nvgBeginPath(vg)
                                nvgMoveTo(vg, lineX, ly); nvgLineTo(vg, lineX, lyEnd)
                                nvgStroke(vg)
                                runStart = nil
                            end
                        end
                    end
                end
            end

            -- ── hv 交叉格：在所有段渲染之后绘制，覆盖内部线条 ──
            -- hv 格填充整格，但相邻内墙只是 halfCell 宽/高的条带，
            -- 所以描边需要画出条带未覆盖的露出部分。
            local hvOffset = (cell - halfCell) * 0.5  -- 条带到格子边缘的间距
            for _, w in ipairs(innerWalls) do
                if w.d == "hv" then
                    local cx = GS.BOARD_X + (w.x - 1) * cell
                    local cy = GS.BOARD_Y + (w.y - 1) * cell
                    -- 填充整个格子，覆盖段描边产生的内部分隔线
                    nvgBeginPath(vg)
                    nvgRect(vg, cx, cy, cell, cell)
                    nvgFillColor(vg, nvgRGBA(50, 50, 50, 255))
                    nvgFill(vg)

                    -- 辅助：判断是否外墙
                    local function isOuter(ax, ay)
                        if ax >= p.wx1 and ax <= p.wx2 and ay >= p.wy1 and ay <= p.wy2 then
                            if ax == p.wx1 or ax == p.wx2 or ay == p.wy1 or ay == p.wy2 then
                                return true
                            end
                        end
                        return false
                    end

                    -- 描边和阴影：两遍（pass1=黑色描边, pass2=阴影）
                    for pass = 1, 2 do
                        if pass == 1 then
                            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
                        else
                            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 80))
                        end
                        nvgStrokeWidth(vg, 1.5)

                        -- 左边 (x = cx, 纵向线)
                        if not isOuter(w.x - 1, w.y) then
                            local adjDir = wallDirMap[(w.x-1) .. "," .. w.y]
                            if adjDir == "hv" then
                                -- 相邻也是整格填充，不画
                            elseif adjDir and adjDir == "h" then
                                -- 相邻横向条带：画上下露出部分
                                nvgBeginPath(vg); nvgMoveTo(vg, cx, cy); nvgLineTo(vg, cx, cy + hvOffset); nvgStroke(vg)
                                nvgBeginPath(vg); nvgMoveTo(vg, cx, cy + hvOffset + halfCell); nvgLineTo(vg, cx, cy + cell); nvgStroke(vg)
                            else
                                -- 无墙或纵向墙：画整边
                                nvgBeginPath(vg); nvgMoveTo(vg, cx, cy); nvgLineTo(vg, cx, cy + cell); nvgStroke(vg)
                            end
                        end

                        -- 右边 (x = cx + cell, 纵向线)
                        if not isOuter(w.x + 1, w.y) then
                            local adjDir = wallDirMap[(w.x+1) .. "," .. w.y]
                            if adjDir == "hv" then
                                -- skip
                            elseif adjDir and adjDir == "h" then
                                nvgBeginPath(vg); nvgMoveTo(vg, cx+cell, cy); nvgLineTo(vg, cx+cell, cy + hvOffset); nvgStroke(vg)
                                nvgBeginPath(vg); nvgMoveTo(vg, cx+cell, cy + hvOffset + halfCell); nvgLineTo(vg, cx+cell, cy + cell); nvgStroke(vg)
                            else
                                nvgBeginPath(vg); nvgMoveTo(vg, cx+cell, cy); nvgLineTo(vg, cx+cell, cy + cell); nvgStroke(vg)
                            end
                        end

                        -- 上边 (y = cy, 横向线)
                        if not isOuter(w.x, w.y - 1) then
                            local adjDir = wallDirMap[w.x .. "," .. (w.y-1)]
                            if adjDir == "hv" then
                                -- skip
                            elseif adjDir and adjDir == "v" then
                                -- 相邻纵向条带：画左右露出部分
                                nvgBeginPath(vg); nvgMoveTo(vg, cx, cy); nvgLineTo(vg, cx + hvOffset, cy); nvgStroke(vg)
                                nvgBeginPath(vg); nvgMoveTo(vg, cx + hvOffset + halfCell, cy); nvgLineTo(vg, cx + cell, cy); nvgStroke(vg)
                            else
                                nvgBeginPath(vg); nvgMoveTo(vg, cx, cy); nvgLineTo(vg, cx + cell, cy); nvgStroke(vg)
                            end
                        end

                        -- 下边 (y = cy + cell, 横向线)
                        if not isOuter(w.x, w.y + 1) then
                            local adjDir = wallDirMap[w.x .. "," .. (w.y+1)]
                            if adjDir == "hv" then
                                -- skip
                            elseif adjDir and adjDir == "v" then
                                nvgBeginPath(vg); nvgMoveTo(vg, cx, cy+cell); nvgLineTo(vg, cx + hvOffset, cy+cell); nvgStroke(vg)
                                nvgBeginPath(vg); nvgMoveTo(vg, cx + hvOffset + halfCell, cy+cell); nvgLineTo(vg, cx + cell, cy+cell); nvgStroke(vg)
                            else
                                nvgBeginPath(vg); nvgMoveTo(vg, cx, cy+cell); nvgLineTo(vg, cx + cell, cy+cell); nvgStroke(vg)
                            end
                        end
                    end
                end
            end
        end
    end

    -- ================================================================
    -- 绘制家具（通用，所有家园类型）
    -- ================================================================
    local furnitures = GS.HOME_FURNITURE[GS.homeType]
    if furnitures then
        local t = os.clock()
        for fi, furn in ipairs(furnitures) do
            local furnPx = GS.BOARD_X + (furn.x - 1) * cell
            local furnPy = GS.BOARD_Y + (furn.y - 1) * cell
            local totalW = cell * furn.w
            local totalH = cell * furn.h

            local margin = cell * 0.08
            local bodyX = furnPx + margin
            local bodyY = furnPy + margin
            local bodyW = totalW - margin * 2
            local bodyH = totalH - margin * 2
            local cornerR = cell * 0.18
            local cx = furnPx + totalW / 2
            local cy = furnPy + totalH / 2

            local br, bg2, bb = 200, 200, 200
            local borR, borG, borB = 140, 140, 140

            -- 呼吸动画（每个家具相位不同）
            local breathe = math.sin(t * 1.8 + fi * 1.7) * 1.5

            -- 阴影
            nvgBeginPath(vg)
            nvgEllipse(vg, cx, furnPy + totalH - margin + 2, bodyW * 0.35, 3)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
            nvgFill(vg)

            -- 外发光光晕
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX - 2, bodyY - 2 + breathe * 0.2, bodyW + 4, bodyH + 4, cornerR + 2)
            nvgFillColor(vg, nvgRGBA(br, bg2, bb, 35))
            nvgFill(vg)

            -- 身体背景（暗灰色渐变）
            local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
                nvgRGBA(50, 50, 55, 230), nvgRGBA(35, 35, 40, 240))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY + breathe * 0.2, bodyW, bodyH, cornerR)
            nvgFillPaint(vg, bodyGrad)
            nvgFill(vg)

            -- 图片/灰色占位
            if furn.imgKey and furn.imgFile then
                local img = ImageManager.lazyGet(furn.imgKey, furn.imgFile)
                if img ~= -1 then
                    if furn.rotate then
                        -- 旋转整个家具绘制（如小型书桌左旋90°）
                        nvgSave(vg)
                        nvgTranslate(vg, cx, cy + breathe * 0.2)
                        nvgRotate(vg, furn.rotate * math.pi / 180)
                        local imgPaint = nvgImagePattern(vg, -bodyH / 2, -bodyW / 2, bodyH, bodyW,
                            0, img, 1.0)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, -bodyH / 2, -bodyW / 2, bodyH, bodyW, cornerR)
                        nvgFillPaint(vg, imgPaint)
                        nvgFill(vg)
                        nvgRestore(vg)
                    else
                        local imgPaint = nvgImagePattern(vg, bodyX, bodyY + breathe * 0.2, bodyW, bodyH,
                            0, img, 1.0)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, bodyX, bodyY + breathe * 0.2, bodyW, bodyH, cornerR)
                        nvgFillPaint(vg, imgPaint)
                        nvgFill(vg)
                    end
                end
            else
                -- 无图片：灰色占位填充
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX, bodyY + breathe * 0.2, bodyW, bodyH, cornerR)
                nvgFillColor(vg, nvgRGBA(120, 120, 120, 180))
                nvgFill(vg)
            end

            -- 边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY + breathe * 0.2, bodyW, bodyH, cornerR)
            nvgStrokeColor(vg, nvgRGBA(borR, borG, borB, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 名字标签
            local nameSize = math.max(9, cell * 0.22)
            local nameY = bodyY + bodyH + breathe * 0.2
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, nameSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
            for _, off in ipairs(OFFSETS_4) do
                nvgText(vg, cx + off[1], nameY + off[2], furn.name, nil)
            end
            nvgFillColor(vg, nvgRGBA(br, bg2, bb, 255))
            nvgText(vg, cx, nameY, furn.name, nil)
        end
    end

    -- 家园升级按钮已移至顶栏 drawTopBar()
end

-- ====================================================================
-- 绘制：高亮格子
-- ====================================================================
function M.drawHighlights()
    local vg = M.vg
    for key, _ in pairs(GS.movableCells) do
        local cy = math.floor(key / 100)
        local cx = key - cy * 100
        local px = GS.BOARD_X + (cx - 1) * GS.CELL
        local py = GS.BOARD_Y + (cy - 1) * GS.CELL
        nvgBeginPath(vg)
        nvgRect(vg, px + 2, py + 2, GS.CELL - 4, GS.CELL - 4)
        nvgFillColor(vg, nvgRGBA(60, 140, 255, 80))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 160, 255, 160))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 施法范围颜色规则：攻击=红色，BUFF(selfSkill)=绿色
    local isBuff = (GS.actionChoice == "selfSkill")

    for key, _ in pairs(GS.attackableCells) do
        local cy = math.floor(key / 100)
        local cx = key - cy * 100
        local px = GS.BOARD_X + (cx - 1) * GS.CELL
        local py = GS.BOARD_Y + (cy - 1) * GS.CELL

        if isBuff then
            -- BUFF/支援技能：绿色范围（亮度与攻击范围一致）
            nvgBeginPath(vg)
            nvgRect(vg, px + 2, py + 2, GS.CELL - 4, GS.CELL - 4)
            nvgFillColor(vg, nvgRGBA(60, 200, 60, 45))
            nvgFill(vg)
        else
            -- 攻击/伤害技能 & 普通攻击：红色范围
            local target = GS.getUnitAt(cx, cy)
            if target and target.isMonster then
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py + 2, GS.CELL - 4, GS.CELL - 4)
                nvgFillColor(vg, nvgRGBA(255, 60, 60, 80))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 180))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            else
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py + 2, GS.CELL - 4, GS.CELL - 4)
                nvgFillColor(vg, nvgRGBA(255, 100, 100, 45))
                nvgFill(vg)
            end
        end
    end

    -- 单体技能选目标时：鼠标悬停的 AOE 范围预览（雷云术、落雷术等）
    if GS.actionChoice == "skill" and GS.actionChosenSkillId then
        local skDef = GS.SKILL_DEFS[GS.actionChosenSkillId]
        if skDef then
            local hmx, hmy = GS.hoverX or 0, GS.hoverY or 0
            local hcx = math.floor((hmx - GS.BOARD_X) / GS.CELL) + 1
            local hcy = math.floor((hmy - GS.BOARD_Y) / GS.CELL) + 1
            local hKey = GS.cellKey(hcx, hcy)
            if GS.attackableCells[hKey] then
                local hTarget = GS.getUnitAt(hcx, hcy)
                if hTarget and hTarget.isMonster then
                    if skDef.thunderCloud then
                        -- 雷云术：显示目标周围 AOE 范围（攻击=红色），含深渊词缀加成
                        local tcBonus = 0
                        if GS.equipment then
                            for _, slot in pairs(GS.equipment) do
                                if slot and slot.abyssAffix and slot.abyssAffix.mechanic == "skill_aoe_range" then
                                    tcBonus = tcBonus + 1
                                end
                                if slot and slot.gemSlots then
                                    for _, gs in ipairs(slot.gemSlots) do
                                        if gs.abyssAffix and gs.abyssAffix.mechanic == "skill_aoe_range" then
                                            tcBonus = tcBonus + 1
                                        end
                                    end
                                end
                            end
                        end
                        local tcR = 1 + tcBonus
                        for dy = -tcR, tcR do
                            for dx = -tcR, tcR do
                                local ax, ay = hcx + dx, hcy + dy
                                if ax >= 1 and ax <= GS.BOARD_SIZE and ay >= 1 and ay <= GS.BOARD_SIZE then
                                    local apx = GS.BOARD_X + (ax - 1) * GS.CELL
                                    local apy = GS.BOARD_Y + (ay - 1) * GS.CELL
                                    nvgBeginPath(vg)
                                    nvgRect(vg, apx + 1, apy + 1, GS.CELL - 2, GS.CELL - 2)
                                    nvgFillColor(vg, nvgRGBA(255, 60, 60, 60))
                                    nvgFill(vg)
                                    nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 200))
                                    nvgStrokeWidth(vg, 2)
                                    nvgStroke(vg)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 点选目标型自我施放技能：高亮玩家自身格子（呼吸闪烁）
    if GS.actionChoice == "selfSkill" and GS.selectedUnit then
        local su = GS.selectedUnit
        local spx = GS.BOARD_X + (su.x - 1) * GS.CELL
        local spy = GS.BOARD_Y + (su.y - 1) * GS.CELL
        local pulse = 0.55 + 0.45 * math.sin((GS.globalTimer or 0) * 4.0)  -- 呼吸闪烁
        local skillCol = {220, 200, 60}
        if GS.actionChosenSkillId then
            local sd = GS.SKILL_DEFS[GS.actionChosenSkillId]
            if sd and sd.col then skillCol = sd.col end
        end
        -- 高亮填充
        nvgBeginPath(vg)
        nvgRect(vg, spx + 2, spy + 2, GS.CELL - 4, GS.CELL - 4)
        nvgFillColor(vg, nvgRGBA(skillCol[1], skillCol[2], skillCol[3], math.floor(50 * pulse)))
        nvgFill(vg)
        -- 边框
        nvgStrokeColor(vg, nvgRGBA(skillCol[1], skillCol[2], skillCol[3], math.floor(200 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        -- 提示文字 "点击自身"
        nvgFontFace(vg, "sans")
        local ps = GS.pScale or 1
        nvgFontSize(vg, 11 * ps)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 220, math.floor(200 * pulse)))
        nvgText(vg, spx + GS.CELL * 0.5, spy - 6 * ps, "请选择目标")
    end

    -- 地面目标技能可放置范围高亮
    if GS.actionChoice == "groundSkill" and GS.groundTargetCells then
        local chosenDef = GS.SKILL_DEFS[GS.actionChosenSkillId]
        local isAttackSkill = chosenDef and chosenDef.dmgMul
        -- AOE 悬停预览用
        local isIceRing = chosenDef and chosenDef.iceRingAoe
        local isFireball = chosenDef and chosenDef.fireballAoe
        local isMeteor = chosenDef and chosenDef.meteorAoe
        local isBlizzard = chosenDef and chosenDef.blizzardAoe
        -- 可选择范围高亮
        for key, _ in pairs(GS.groundTargetCells) do
            local gy = math.floor(key / 100)
            local gx = key - gy * 100
            -- 攻击技能：所有范围内格子；支援技能（圣树、冰墙等）：仅空地
            if isAttackSkill or GS.isCellEmpty(gx, gy) then
                local gpx = GS.BOARD_X + (gx - 1) * GS.CELL
                local gpy = GS.BOARD_Y + (gy - 1) * GS.CELL
                nvgBeginPath(vg)
                nvgRect(vg, gpx + 2, gpy + 2, GS.CELL - 4, GS.CELL - 4)
                if chosenDef.dmgMul or chosenDef.iceWallSkill then
                    -- 攻击/伤害/削弱敌方技能：红色范围
                    nvgFillColor(vg, nvgRGBA(255, 100, 100, 45))
                    nvgFill(vg)
                else
                    -- 纯辅助技能（圣树、闪烁等）：绿色范围（亮度与攻击范围一致）
                    nvgFillColor(vg, nvgRGBA(60, 200, 60, 45))
                    nvgFill(vg)
                end
            end
        end
        -- AOE 技能悬停预览：鼠标指向范围内格子时显示作用范围
        -- 深渊词缀：技能范围+1 加成 + 装备条件加成（如托马斯）
        local aoeBonus = 0
        if GS.equipment then
            for _, slot in pairs(GS.equipment) do
                if slot and slot.abyssAffix and slot.abyssAffix.mechanic == "skill_aoe_range" then
                    aoeBonus = aoeBonus + 1
                end
                if slot and slot.gemSlots then
                    for _, gs in ipairs(slot.gemSlots) do
                        if gs.abyssAffix and gs.abyssAffix.mechanic == "skill_aoe_range" then
                            aoeBonus = aoeBonus + 1
                        end
                    end
                end
            end
        end
        if GS.player and (GS.player.equipAoeBonus or 0) > 0 then
            aoeBonus = aoeBonus + GS.player.equipAoeBonus
        end
        -- 统一颜色规则：攻击=红色
        local aoeRadius = nil
        if isIceRing then
            aoeRadius = 1 + aoeBonus
        elseif isFireball then
            aoeRadius = (chosenDef.fireballRadius or 2) + aoeBonus
        elseif isMeteor then
            aoeRadius = (chosenDef.meteorRadius or 2) + aoeBonus
        elseif isBlizzard then
            aoeRadius = (chosenDef.blizzardRadius or 2) + aoeBonus
        elseif chosenDef and chosenDef.thunderAoe then
            aoeRadius = (chosenDef.thunderAoeRadius or 1) + aoeBonus
        end

        if aoeRadius then
            local hmx, hmy = GS.hoverX or 0, GS.hoverY or 0
            local hcx = math.floor((hmx - GS.BOARD_X) / GS.CELL) + 1
            local hcy = math.floor((hmy - GS.BOARD_Y) / GS.CELL) + 1
            local hKey = GS.cellKey(hcx, hcy)
            if GS.groundTargetCells[hKey] then
                for dy = -aoeRadius, aoeRadius do
                    for dx = -aoeRadius, aoeRadius do
                        -- 冰环术用切比雪夫距离（3×3正方形），其他用欧几里得距离（匹配圆形，+0.5匹配视觉）
                        local r = aoeRadius + 0.5
                        local inRange = isIceRing
                            or (dx * dx + dy * dy <= r * r)
                        if inRange then
                            local ax, ay = hcx + dx, hcy + dy
                            if ax >= 1 and ax <= GS.BOARD_SIZE and ay >= 1 and ay <= GS.BOARD_SIZE then
                                local apx = GS.BOARD_X + (ax - 1) * GS.CELL
                                local apy = GS.BOARD_Y + (ay - 1) * GS.CELL
                                nvgBeginPath(vg)
                                nvgRect(vg, apx + 1, apy + 1, GS.CELL - 2, GS.CELL - 2)
                                nvgFillColor(vg, nvgRGBA(255, 60, 60, 60))
                                nvgFill(vg)
                                nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 200))
                                nvgStrokeWidth(vg, 2)
                                nvgStroke(vg)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 范围化 AOE 技能（强击系/祝福超度）悬停预览
    if GS.actionChoice == "skill" and GS.aoeGroundMode and GS.actionChosenSkillId then
        -- 悬停预览：鼠标指向攻击范围内格子时显示 AOE 作用范围
        local hmx, hmy = GS.hoverX or 0, GS.hoverY or 0
        local hcx = math.floor((hmx - GS.BOARD_X) / GS.CELL) + 1
        local hcy = math.floor((hmy - GS.BOARD_Y) / GS.CELL) + 1
        local hKey = GS.cellKey(hcx, hcy)
        if GS.attackableCells[hKey] and GS.player then
            local previewCells = Combat.getAoePreviewCells(
                GS.actionChosenSkillId, GS.player.x, GS.player.y, hcx, hcy)
            for _, c in ipairs(previewCells) do
                local ax, ay = c[1], c[2]
                if ax >= 1 and ax <= GS.BOARD_SIZE and ay >= 1 and ay <= GS.BOARD_SIZE then
                    local apx = GS.BOARD_X + (ax - 1) * GS.CELL
                    local apy = GS.BOARD_Y + (ay - 1) * GS.CELL
                    nvgBeginPath(vg)
                    nvgRect(vg, apx + 1, apy + 1, GS.CELL - 2, GS.CELL - 2)
                    nvgFillColor(vg, nvgRGBA(255, 60, 60, 55))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 180))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end
            end
        end
    end

    -- 冰墙方向选择阶段预览
    if GS.actionChoice == "iceWallDir" and GS.iceWallStartX then
        local sx, sy = GS.iceWallStartX, GS.iceWallStartY
        -- 起点标记（亮蓝色边框）
        local spx = GS.BOARD_X + (sx - 1) * GS.CELL
        local spy = GS.BOARD_Y + (sy - 1) * GS.CELL
        nvgBeginPath(vg)
        nvgRect(vg, spx + 1, spy + 1, GS.CELL - 2, GS.CELL - 2)
        nvgFillColor(vg, nvgRGBA(60, 160, 240, 60))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 255))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)

        -- 四个相邻方向提示（小箭头标记）
        local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
        for _, d in ipairs(dirs) do
            local ax, ay = sx + d[1], sy + d[2]
            if ax >= 1 and ax <= GS.BOARD_SIZE and ay >= 1 and ay <= GS.BOARD_SIZE then
                local apx = GS.BOARD_X + (ax - 1) * GS.CELL
                local apy = GS.BOARD_Y + (ay - 1) * GS.CELL
                nvgBeginPath(vg)
                nvgRect(vg, apx + 3, apy + 3, GS.CELL - 6, GS.CELL - 6)
                nvgStrokeColor(vg, nvgRGBA(80, 180, 240, 140))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end
        end

        -- 鼠标悬停方向预览：显示将要生成的冰墙
        local hmx, hmy = GS.hoverX or 0, GS.hoverY or 0
        local hcx = math.floor((hmx - GS.BOARD_X) / GS.CELL) + 1
        local hcy = math.floor((hmy - GS.BOARD_Y) / GS.CELL) + 1
        local ddx, ddy = hcx - sx, hcy - sy
        if math.abs(ddx) + math.abs(ddy) == 1 then
            local wallDef = GS.SKILL_DEFS[GS.actionChosenSkillId]
            if wallDef then
                local lv = GS.skillLevels[GS.actionChosenSkillId] or 1
                local maxLen = wallDef.iceWallBaseLen or 3
                local breaks = wallDef.iceWallLenBreaks or {3, 6, 10}
                for _, brk in ipairs(breaks) do
                    if lv >= brk then maxLen = maxLen + 1 end
                end
                for i = 0, maxLen - 1 do
                    local wx, wy = sx + ddx * i, sy + ddy * i
                    if not GS.isInBoard(wx, wy) then break end
                    if not GS.isCellEmpty(wx, wy) then break end
                    local wpx = GS.BOARD_X + (wx - 1) * GS.CELL
                    local wpy = GS.BOARD_Y + (wy - 1) * GS.CELL
                    nvgBeginPath(vg)
                    nvgRect(vg, wpx + 2, wpy + 2, GS.CELL - 4, GS.CELL - 4)
                    nvgFillColor(vg, nvgRGBA(80, 180, 255, 70))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 220))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end
            end
        end
    end

    if GS.selectedUnit then
        local selS = GS.unitSize(GS.selectedUnit)
        local selTotalCell = selS * GS.CELL
        local px = GS.BOARD_X + (GS.selectedUnit.x - 1) * GS.CELL
        local py = GS.BOARD_Y + (GS.selectedUnit.y - 1) * GS.CELL
        nvgBeginPath(vg)
        nvgRect(vg, px + 1, py + 1, selTotalCell - 2, selTotalCell - 2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 100, 220))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    -- 鼠标悬停格子高亮（攻击=红色，BUFF=绿色，其他=默认黄色）
    local mx, my = GS.hoverX or 0, GS.hoverY or 0
    local hcx = math.floor((mx - GS.BOARD_X) / GS.CELL) + 1
    local hcy = math.floor((my - GS.BOARD_Y) / GS.CELL) + 1
    if hcx >= 1 and hcx <= GS.BOARD_SIZE and hcy >= 1 and hcy <= GS.BOARD_SIZE
       and not (GS.homeMode and GS.warehouseMode) then
        local hpx = GS.BOARD_X + (hcx - 1) * GS.CELL
        local hpy = GS.BOARD_Y + (hcy - 1) * GS.CELL
        -- 根据当前行动模式决定悬停颜色
        local hR, hG, hB = 255, 210, 80  -- 默认金色
        local ac = GS.actionChoice
        if ac == "attack" or ac == "skill" then
            hR, hG, hB = 255, 80, 80  -- 攻击=红色
        elseif ac == "groundSkill" and GS.actionChosenSkillId then
            local gsDef = GS.SKILL_DEFS[GS.actionChosenSkillId]
            if gsDef and (gsDef.dmgMul or gsDef.iceWallSkill) then
                hR, hG, hB = 255, 80, 80  -- 攻击/削弱类地面技能=红色
            end
            -- 辅助类地面技能（圣树、闪烁）保持默认金色
        end
        -- selfSkill（火焰护盾、治疗等）保持默认金色
        nvgBeginPath(vg)
        nvgRect(vg, hpx + 1, hpy + 1, GS.CELL - 2, GS.CELL - 2)
        nvgStrokeColor(vg, nvgRGBA(hR, hG, hB, 140))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgRect(vg, hpx + 1, hpy + 1, GS.CELL - 2, GS.CELL - 2)
        nvgFillColor(vg, nvgRGBA(hR, hG, hB, 30))
        nvgFill(vg)
    end
end

-- ====================================================================
-- 绘制：残影辅助
-- ====================================================================
local function drawPlayerGhost(vg, cx, cy, radius, alpha)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgFillColor(vg, nvgRGBA(80, 160, 255, alpha))
    nvgFill(vg)
end

local function drawMonsterGhost(vg, cx, cy, bodyW, cornerR, alpha, gr, gg, gb)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - bodyW / 2, cy - bodyW / 2, bodyW, bodyW, cornerR)
    nvgFillColor(vg, nvgRGBA(gr or 60, gg or 180, gb or 100, alpha))
    nvgFill(vg)
end

-- ====================================================================
-- 绘制：朝向箭头（通用，类似 > 的 chevron）
-- ====================================================================
--- @param cx number 单位中心X
--- @param cy number 单位中心Y（含呼吸偏移）
--- @param cellSize number 格子尺寸（用于计算箭头大小）
--- @param facing string "up"/"down"/"left"/"right"
--- @param r number 红
--- @param g number 绿
--- @param b number 蓝
--- @param alpha number 透明度(0-255)
local function drawFacingArrow(vg, cx, cy, cellSize, facing, r, g, b, alpha)
    if not facing then return end
    local arrLen = cellSize * 0.13   -- 箭头臂长
    local thick = math.max(1.5, cellSize * 0.04)
    -- 偏移量：箭头放在单位身体边缘外侧
    local offset = cellSize * 0.42
    -- 箭头中心点
    local ax, ay = cx, cy
    if facing == "right" then
        ax = cx + offset
    elseif facing == "left" then
        ax = cx - offset
    elseif facing == "up" then
        ay = cy - offset
    elseif facing == "down" then
        ay = cy + offset
    end
    -- 构建箭头路径的辅助函数
    local function buildArrowPath()
        nvgBeginPath(vg)
        if facing == "right" then
            nvgMoveTo(vg, ax - arrLen, ay - arrLen)
            nvgLineTo(vg, ax, ay)
            nvgLineTo(vg, ax - arrLen, ay + arrLen)
        elseif facing == "left" then
            nvgMoveTo(vg, ax + arrLen, ay - arrLen)
            nvgLineTo(vg, ax, ay)
            nvgLineTo(vg, ax + arrLen, ay + arrLen)
        elseif facing == "up" then
            nvgMoveTo(vg, ax - arrLen, ay + arrLen)
            nvgLineTo(vg, ax, ay)
            nvgLineTo(vg, ax + arrLen, ay + arrLen)
        elseif facing == "down" then
            nvgMoveTo(vg, ax - arrLen, ay - arrLen)
            nvgLineTo(vg, ax, ay)
            nvgLineTo(vg, ax + arrLen, ay - arrLen)
        end
    end
    -- 第一层：深色描边轮廓
    buildArrowPath()
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgStrokeWidth(vg, thick + math.max(2, cellSize * 0.03))
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)
    -- 第二层：主色箭头
    buildArrowPath()
    nvgStrokeColor(vg, nvgRGBA(r, g, b, alpha))
    nvgStrokeWidth(vg, thick)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)
end

-- ====================================================================
-- 绘制：玩家
-- ====================================================================
function M.drawPlayer(unit, time)
    local vg = M.vg
    local offX, offY, animT = M.getMoveAnimOffset(unit)
    local margin = GS.CELL * 0.12
    local radius = (GS.CELL - margin * 2) / 2

    -- 移动轨迹线 + 残影
    if unit.moveAnim and animT < 1.0 then
        local anim = unit.moveAnim
        local halfCell = GS.CELL / 2
        local curEase = animT * animT * (3 - 2 * animT)
        local curX, curY = getPathPixelPos(anim, curEase, GS.CELL, GS.BOARD_X, GS.BOARD_Y, halfCell, unit.x, unit.y)

        local trailAlpha = math.floor(160 * (1 - animT))
        -- 冲锋拖尾使用橙金色，普通移动使用蓝色
        local isCharge = anim.chargeTrail
        local trailR1, trailG1, trailB1 = 100, 180, 255   -- 宽轨迹（普通蓝）
        local trailR2, trailG2, trailB2 = 180, 220, 255   -- 细轨迹（普通蓝）
        local ghostR, ghostG, ghostB = 150, 200, 255       -- 起点标记（普通蓝）
        if isCharge then
            trailR1, trailG1, trailB1 = 220, 150, 30       -- 宽轨迹（橙金色）
            trailR2, trailG2, trailB2 = 255, 200, 80       -- 细轨迹（亮金色）
            ghostR, ghostG, ghostB = 255, 180, 50           -- 起点标记（金色）
        end

        -- 绘制轨迹线（沿路径各 waypoint 连线）
        if anim.path and #anim.path >= 2 then
            -- 宽轨迹
            nvgBeginPath(vg)
            local sp = anim.path[1]
            nvgMoveTo(vg, GS.BOARD_X + (sp[1]-1)*GS.CELL + halfCell, GS.BOARD_Y + (sp[2]-1)*GS.CELL + halfCell)
            -- 只画到当前位置所在的段
            local totalSegs = #anim.path - 1
            local posOnPath = curEase * totalSegs
            local fullSegs = math.floor(posOnPath)
            for si = 2, math.min(fullSegs + 1, #anim.path) do
                local wp = anim.path[si]
                nvgLineTo(vg, GS.BOARD_X + (wp[1]-1)*GS.CELL + halfCell, GS.BOARD_Y + (wp[2]-1)*GS.CELL + halfCell)
            end
            nvgLineTo(vg, curX, curY)
            nvgStrokeColor(vg, nvgRGBA(trailR1, trailG1, trailB1, math.floor(trailAlpha * 0.4)))
            nvgStrokeWidth(vg, radius * (isCharge and 1.0 or 0.8))
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)

            -- 细轨迹
            nvgBeginPath(vg)
            nvgMoveTo(vg, GS.BOARD_X + (sp[1]-1)*GS.CELL + halfCell, GS.BOARD_Y + (sp[2]-1)*GS.CELL + halfCell)
            for si = 2, math.min(fullSegs + 1, #anim.path) do
                local wp = anim.path[si]
                nvgLineTo(vg, GS.BOARD_X + (wp[1]-1)*GS.CELL + halfCell, GS.BOARD_Y + (wp[2]-1)*GS.CELL + halfCell)
            end
            nvgLineTo(vg, curX, curY)
            nvgStrokeColor(vg, nvgRGBA(trailR2, trailG2, trailB2, trailAlpha))
            nvgStrokeWidth(vg, radius * (isCharge and 0.45 or 0.3))
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)
        else
            -- 单段直线（兜底）
            local fromPx = GS.BOARD_X + (anim.fromX - 1) * GS.CELL + halfCell
            local fromPy = GS.BOARD_Y + (anim.fromY - 1) * GS.CELL + halfCell
            nvgBeginPath(vg)
            nvgMoveTo(vg, fromPx, fromPy)
            nvgLineTo(vg, curX, curY)
            nvgStrokeColor(vg, nvgRGBA(trailR1, trailG1, trailB1, math.floor(trailAlpha * 0.4)))
            nvgStrokeWidth(vg, radius * (isCharge and 1.0 or 0.8))
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)

            nvgBeginPath(vg)
            nvgMoveTo(vg, fromPx, fromPy)
            nvgLineTo(vg, curX, curY)
            nvgStrokeColor(vg, nvgRGBA(trailR2, trailG2, trailB2, trailAlpha))
            nvgStrokeWidth(vg, radius * (isCharge and 0.45 or 0.3))
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)
        end
        nvgLineCap(vg, NVG_BUTT)  -- 恢复默认，防止状态泄漏

        -- 起点标记
        local startPx, startPy
        if anim.path and #anim.path >= 2 then
            startPx = GS.BOARD_X + (anim.path[1][1]-1)*GS.CELL + halfCell
            startPy = GS.BOARD_Y + (anim.path[1][2]-1)*GS.CELL + halfCell
        else
            startPx = GS.BOARD_X + (anim.fromX - 1) * GS.CELL + halfCell
            startPy = GS.BOARD_Y + (anim.fromY - 1) * GS.CELL + halfCell
        end
        nvgBeginPath(vg)
        nvgCircle(vg, startPx, startPy, radius * (isCharge and 0.35 or 0.25))
        nvgFillColor(vg, nvgRGBA(ghostR, ghostG, ghostB, trailAlpha))
        nvgFill(vg)

        -- 残影
        local ghostCount = 3
        for gi = 1, ghostCount do
            local gp = (animT - gi * 0.08)
            if gp > 0 and gp < 1 then
                local gEase = gp * gp * (3 - 2 * gp)
                local gx, gy = getPathPixelPos(anim, gEase, GS.CELL, GS.BOARD_X, GS.BOARD_Y, halfCell, unit.x, unit.y)
                local gAlpha = math.floor(100 * (1 - gi / (ghostCount + 1)))
                drawPlayerGhost(vg, gx, gy, radius * (1 - gi * 0.05), gAlpha)
            end
        end
    end

    -- 跳跃动画 Y 偏移（事件中受惊跳跃）
    local playerJumpOffY = 0
    if unit.jumpAnim then
        local jt = unit.jumpAnim.timer / unit.jumpAnim.duration
        if jt > 1 then jt = 1 end
        playerJumpOffY = -math.sin(math.pi * jt) * GS.CELL * 0.6
    end

    local px = GS.BOARD_X + (unit.x - 1) * GS.CELL + offX
    local py = GS.BOARD_Y + (unit.y - 1) * GS.CELL + offY + playerJumpOffY
    local cx = px + GS.CELL / 2
    local cy = py + GS.CELL / 2
    -- 静神状态：停止呼吸效果，表现屏息凝神
    local breathe = 0
    if GS.focusBuffTurns <= 0 then
        breathe = math.sin(time * 2.5 + unit.x * 0.7 + unit.y * 1.3) * 2
    end
    local drawCy = cy + breathe * 0.3

    -- 隐匿状态：整体半透明（事件期间隐匿不做视觉半透明）
    local isStealth = GS.stealthActive and GS.stealthTurns ~= 999
    if isStealth then
        nvgSave(vg)
        nvgGlobalAlpha(vg, 0.4)
    end

    -- 玩家攻击光环：排除猎犬攻击（isCompanion），仅玩家自身攻击时显示
    local playerAtkFx = nil
    for _, ef in ipairs(GS.attackEffects) do
        if not ef.isCompanion then playerAtkFx = ef; break end
    end
    local isAttacking = playerAtkFx ~= nil or #GS.strikeEffects > 0 or #GS.blessEffects > 0 or #GS.powerShotEffects > 0 or #GS.stunShotEffects > 0 or #GS.swordQiEffects > 0
    if isAttacking then
        local ae = playerAtkFx or GS.strikeEffects[1] or GS.blessEffects[1] or GS.powerShotEffects[1] or GS.stunShotEffects[1] or GS.swordQiEffects[1]
        local at = ae.timer / ae.duration
        -- 将脉冲限制在视觉动画有效区间内，避免动画结束后棋子仍在"抖动"
        -- 双匕首/剑匕双持视觉内容在 t≈0.6 结束，其他武器更短
        local visualEnd = 0.6
        local clampedAt = math.min(at, visualEnd) / visualEnd  -- 映射到 0~1
        local scalePulse = math.sin(math.pi * clampedAt)
        local isStrike = GS.strikeEffects[1] ~= nil and #GS.attackEffects == 0 and #GS.powerShotEffects == 0 and #GS.stunShotEffects == 0 and #GS.blessEffects == 0
        local isBless = GS.blessEffects[1] ~= nil and #GS.attackEffects == 0 and #GS.strikeEffects == 0 and #GS.powerShotEffects == 0 and #GS.stunShotEffects == 0
        local isPowerShot = GS.powerShotEffects[1] ~= nil and #GS.attackEffects == 0 and #GS.strikeEffects == 0 and #GS.stunShotEffects == 0 and #GS.blessEffects == 0
        local isStunShot = GS.stunShotEffects[1] ~= nil and #GS.attackEffects == 0 and #GS.strikeEffects == 0 and #GS.powerShotEffects == 0 and #GS.blessEffects == 0
        local isSwordQi = GS.swordQiEffects[1] ~= nil and #GS.attackEffects == 0 and #GS.strikeEffects == 0 and #GS.powerShotEffects == 0 and #GS.stunShotEffects == 0 and #GS.blessEffects == 0
        local isSpecial = isStrike or isBless or isPowerShot or isStunShot or isSwordQi
        local scaleFactor = 1.0 + scalePulse * (isSpecial and 0.22 or 0.15)

        nvgSave(vg)
        nvgTranslate(vg, cx, drawCy)
        nvgScale(vg, scaleFactor, scaleFactor)
        nvgTranslate(vg, -cx, -drawCy)

        local glowAlpha = math.floor((isSpecial and 160 or 120) * scalePulse)
        local glowRadius = radius + (isSpecial and 12 or 8) * scalePulse
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, glowRadius)
        if isStrike then
            local sid = ae.skillId
            if sid == "strike" then
                nvgFillColor(vg, nvgRGBA(240, 245, 255, glowAlpha))
            elseif sid == "sup_stk" then
                nvgFillColor(vg, nvgRGBA(80, 160, 255, glowAlpha))
            else
                nvgFillColor(vg, nvgRGBA(255, 200, 60, glowAlpha))
            end
        elseif isPowerShot then
            nvgFillColor(vg, nvgRGBA(120, 220, 80, glowAlpha))
        elseif isStunShot then
            nvgFillColor(vg, nvgRGBA(230, 200, 50, glowAlpha))
        elseif isSwordQi then
            nvgFillColor(vg, nvgRGBA(180, 80, 255, glowAlpha))
        else
            nvgFillColor(vg, nvgRGBA(160, 210, 255, glowAlpha))
        end
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, radius + 3 * scalePulse)
        if isStrike then
            local sid = ae.skillId
            if sid == "strike" then
                nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(100 * scalePulse)))
            elseif sid == "sup_stk" then
                nvgFillColor(vg, nvgRGBA(140, 200, 255, math.floor(100 * scalePulse)))
            else
                nvgFillColor(vg, nvgRGBA(255, 240, 180, math.floor(100 * scalePulse)))
            end
        elseif isPowerShot then
            nvgFillColor(vg, nvgRGBA(180, 240, 140, math.floor(100 * scalePulse)))
        elseif isStunShot then
            nvgFillColor(vg, nvgRGBA(240, 230, 140, math.floor(100 * scalePulse)))
        elseif isSwordQi then
            nvgFillColor(vg, nvgRGBA(220, 160, 255, math.floor(100 * scalePulse)))
        else
            nvgFillColor(vg, nvgRGBA(220, 240, 255, math.floor(80 * scalePulse)))
        end
        nvgFill(vg)
    end

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + GS.CELL - margin + 2, radius * 0.7, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)

    -- 外圈光晕
    nvgBeginPath(vg)
    nvgCircle(vg, cx, drawCy, radius + 3)
    nvgFillColor(vg, nvgRGBA(100, 180, 255, 60))
    nvgFill(vg)

    -- 蓝色圆形主体
    local bodyGrad = nvgLinearGradient(vg, cx, drawCy - radius, cx, drawCy + radius,
        nvgRGBA(80, 160, 255, 255), nvgRGBA(30, 90, 200, 255))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, drawCy, radius)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    nvgStrokeColor(vg, nvgRGBA(140, 200, 255, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 主角头像（优先使用职业头像）
    local avatarImg = M.classAvatars[GS.currentClass] or M.playerAvatar
    if avatarImg and avatarImg ~= -1 then
        local imgSize = radius * 2
        local imgPat = nvgImagePattern(vg, cx - radius, drawCy - radius, imgSize, imgSize, 0, avatarImg, 1.0)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, radius - 1)
        nvgFillPaint(vg, imgPat)
        nvgFill(vg)
    else
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(10, GS.CELL * 0.28))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, cx, drawCy, "你", nil)
    end

    -- 悬浮武器（右手 / 左手 / 双持）—— 仅玩家自身攻击特效时隐藏
    local hasPlayerAttackFx = false
    for _, ef in ipairs(GS.attackEffects) do
        if not ef.isCompanion then hasPlayerAttackFx = true; break end
    end
    if not hasPlayerAttackFx then
        local wr = GS.equipment and GS.equipment["weapon_r"]
        local wl = GS.equipment and GS.equipment["weapon_l"]

        --- 绘制单把悬浮武器
        local function drawFloatingWeapon(img, side, isDagger, isBowWpn, isMaceWpn, isStaffWpn)
            local wSize = GS.CELL * (isDagger and 0.55 or (isStaffWpn and 0.7 or 0.65))
            local sign = (side == "right") and 1 or -1
            local wX = cx + sign * radius * 0.7
            local wY = drawCy - radius * 0.7 + (isDagger and 15 or (isStaffWpn and 6 or 0))
            local phase = (side == "right") and 1.0 or 2.5
            local wBob = GS.focusBuffTurns > 0 and 0 or (math.sin(time * 3.0 + phase) * 1.5)

            nvgSave(vg)
            nvgTranslate(vg, wX, wY + wBob)
            if isBowWpn then
                nvgRotate(vg, math.rad(130))
            elseif isDagger then
                nvgScale(vg, sign, 1)
                local daggerAngle = (side == "right") and (40 + 90 + 180) or (40 - 90)
                nvgRotate(vg, math.rad(daggerAngle))
            elseif isMaceWpn then
                nvgScale(vg, -1, 1)
                nvgRotate(vg, math.rad(-30))
            elseif isStaffWpn then
                nvgScale(vg, -1, 1)
                nvgRotate(vg, math.rad(-45))
            else
                nvgScale(vg, -1, 1)
                nvgRotate(vg, math.rad(30))
            end

            local imgPaint = nvgImagePattern(vg,
                -wSize / 2, -wSize / 2,
                wSize, wSize,
                0, img, 0.95)
            nvgBeginPath(vg)
            nvgRect(vg, -wSize / 2, -wSize / 2, wSize, wSize)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
            nvgRestore(vg)
        end

        -- 右手武器（弓必须同时装备箭袋才显示，否则不显示武器）
        if wr then
            local isDagger = wr.weaponTag == "匕首"
            local isBowWpn = wr.weaponTag == "弓"
            -- 弓没有箭袋时不显示
            local bowHidden = isBowWpn and (not wl or wl.category ~= "箭袋")
            if not bowHidden then
                local img
                local isMace = wr.weaponTag == "锤"
                local isStaff = wr.weaponTag == "法杖"
                if isDagger and M.daggerImage ~= -1 then
                    img = M.daggerImage
                elseif isBowWpn and M.bowImage ~= -1 then
                    img = M.bowImage
                elseif isMace and M.maceImage ~= -1 then
                    img = M.maceImage
                elseif isStaff and M.staffImage ~= -1 then
                    img = M.staffImage
                elseif M.swordImage ~= -1 then
                    img = M.swordImage
                end
                if img then drawFloatingWeapon(img, "right", isDagger, isBowWpn, isMace, isStaff) end
            end
        end

        -- 左手武器（匕首等可悬浮的武器类型）
        if wl and wl.weaponTag == "匕首" and M.daggerImage ~= -1 then
            drawFloatingWeapon(M.daggerImage, "left", true, false)
        end
    end

    -- HP 条（边框上沿）
    local bodyW = GS.CELL - margin * 2
    local barW = bodyW * 0.8
    local barH = math.max(3, GS.CELL * 0.06)
    local barX = px + (GS.CELL - barW) / 2
    local barY = drawCy - radius - barH

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    local hpRatio = math.max(0, math.min(1, unit.hp / math.max(1, unit.maxHp)))
    local hpColor = unit.isMonster and nvgRGBA(160, 20, 20, 255) or nvgRGBA(80, 220, 80, 255)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 2)
    nvgFillColor(vg, hpColor)
    nvgFill(vg)



    -- 吟唱段数气泡（法师/牧师专属，右下角，避免遮挡朝向箭头）
    if (GS.currentClass == "mage" or GS.currentClass == "priest") then
        local bubbleX = cx + radius * 0.7
        local bubbleY = drawCy + radius * 0.7
        local bubbleR = math.max(6, GS.CELL * 0.12)
        -- 背景圆
        nvgBeginPath(vg)
        nvgCircle(vg, bubbleX, bubbleY, bubbleR)
        nvgFillColor(vg, nvgRGBA(100, 60, 180, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 180, 255, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 段数文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(8, bubbleR * 1.4))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, bubbleX, bubbleY, tostring(GS.chantStages), nil)
    end

    -- 受伤闪红
    if unit.hurtTimer and unit.hurtTimer >= 0 and unit.hurtDuration and unit.hurtDuration > 0 then
        local ht = unit.hurtTimer / unit.hurtDuration
        local redAlpha = math.floor(180 * (1 - ht))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, radius)
        nvgFillColor(vg, nvgRGBA(255, 30, 30, redAlpha))
        nvgFill(vg)
    end

    -- 冻伤debuff：周期性蓝色闪烁覆盖棋子（类似怪物中毒的绿色闪烁）
    do
        local hasIceDebuff = false
        for _, db in ipairs(GS.playerDebuffs) do
            if db.source == "ice" then hasIceDebuff = true; break end
        end
        if hasIceDebuff then
            local pulse = math.sin(time * 4) * 0.5 + 0.5
            local glowA = math.floor(90 * pulse)
            nvgBeginPath(vg)
            nvgCircle(vg, cx, drawCy, radius)
            nvgFillColor(vg, nvgRGBA(80, 160, 240, glowA))
            nvgFill(vg)
        end
    end

    -- 魔法盾护罩（紫色透明球状护罩，与法师普攻同色系）
    if GS.magicShieldActive then
        local shieldR = radius + GS.CELL * 0.12
        local pulse = (math.sin(time * 3.0) + 1) * 0.5
        -- 外层半透明紫色球罩
        local shieldAlpha = math.floor(40 + 25 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgFillColor(vg, nvgRGBA(120, 80, 200, shieldAlpha))
        nvgFill(vg)
        -- 球罩边缘发光描边
        local edgeAlpha = math.floor(140 + 60 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgStrokeColor(vg, nvgRGBA(160, 120, 240, edgeAlpha))
        nvgStrokeWidth(vg, math.max(1.5, GS.CELL * 0.03))
        nvgStroke(vg)
        -- 内层紫色光晕
        local innerGlow = nvgRadialGradient(vg, cx, drawCy, shieldR * 0.5, shieldR,
            nvgRGBA(180, 140, 255, 0),
            nvgRGBA(140, 100, 220, math.floor(50 + 30 * pulse)))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgFillPaint(vg, innerGlow)
        nvgFill(vg)
        -- 六角形纹理暗示能量场（6个小光点沿圆周分布）
        for i = 1, 6 do
            local dotAngle = (i / 6) * math.pi * 2 + time * 1.5
            local dotX = cx + math.cos(dotAngle) * shieldR * 0.85
            local dotY = drawCy + math.sin(dotAngle) * shieldR * 0.85
            local dotAlpha = math.floor(100 + 60 * math.sin(dotAngle * 2 + time * 4))
            nvgBeginPath(vg)
            nvgCircle(vg, dotX, dotY, math.max(1.5, GS.CELL * 0.025))
            nvgFillColor(vg, nvgRGBA(170, 130, 255, dotAlpha))
            nvgFill(vg)
        end
    end

    -- 火焰护盾（橙红色燃烧护罩 + 大量逃逸火焰粒子）
    if GS.fireShieldTurns and GS.fireShieldTurns > 0 then
        local shieldR = radius + GS.CELL * 0.14
        local pulse = (math.sin(time * 4.0) + 1) * 0.5
        local flicker = (math.sin(time * 11.3) + math.sin(time * 17.7)) * 0.25 + 0.5

        -- 第1层：外层橙红色半透明球罩（燃烧底色）
        local baseAlpha = math.floor(35 + 30 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgFillColor(vg, nvgRGBA(220, 80, 20, baseAlpha))
        nvgFill(vg)

        -- 第2层：内层径向渐变（中心暗红 → 边缘亮橙，模拟内焰）
        local innerGlow = nvgRadialGradient(vg, cx, drawCy, shieldR * 0.3, shieldR,
            nvgRGBA(180, 40, 10, 0),
            nvgRGBA(255, 120, 30, math.floor(60 + 40 * flicker)))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgFillPaint(vg, innerGlow)
        nvgFill(vg)

        -- 第3层：边缘发光描边（明亮的橙黄色火焰轮廓）
        local edgeAlpha = math.floor(160 + 70 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgStrokeColor(vg, nvgRGBA(255, 160, 40, edgeAlpha))
        nvgStrokeWidth(vg, math.max(2.0, GS.CELL * 0.04))
        nvgStroke(vg)

        -- 第4层：外圈热浪辉光（更大范围的淡橙光晕）
        local heatGlow = nvgRadialGradient(vg, cx, drawCy, shieldR * 0.8, shieldR * 1.4,
            nvgRGBA(255, 100, 20, math.floor(30 + 20 * pulse)),
            nvgRGBA(255, 60, 10, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR * 1.4)
        nvgFillPaint(vg, heatGlow)
        nvgFill(vg)

        -- 第5层：8个沿护盾边缘流动的火焰光团（模拟表面燃烧纹理）
        for i = 1, 8 do
            local baseAngle = (i / 8) * math.pi * 2
            local orbAngle = baseAngle + time * 2.5
            local wobble = math.sin(time * 6.0 + i * 1.7) * shieldR * 0.08
            local orbR = shieldR * 0.92 + wobble
            local orbX = cx + math.cos(orbAngle) * orbR
            local orbY = drawCy + math.sin(orbAngle) * orbR
            local orbSize = math.max(2.0, GS.CELL * 0.045) * (0.7 + 0.3 * math.sin(time * 8 + i * 2.3))
            -- 每个光团颜色在黄→橙→红之间变化
            local cPhase = (math.sin(time * 5.0 + i * 1.1) + 1) * 0.5
            local oR = math.floor(255 - 40 * cPhase)
            local oG = math.floor(180 - 100 * cPhase)
            local oB = math.floor(40 - 20 * cPhase)
            local orbAlpha = math.floor(140 + 80 * math.sin(time * 7 + i * 0.9))
            nvgBeginPath(vg)
            nvgCircle(vg, orbX, orbY, orbSize)
            nvgFillColor(vg, nvgRGBA(oR, oG, oB, orbAlpha))
            nvgFill(vg)
        end

        -- 第6层：大量逃逸火花粒子（20个，从护盾表面飞散到外围）
        -- 使用确定性伪随机：每个粒子有固定的角度种子、速度种子，位置随 time 周期循环
        for i = 1, 20 do
            -- 每个粒子的基础参数（确定性，不用 math.random 避免闪烁）
            local seed1 = i * 137.508        -- 黄金角分布
            local seed2 = i * 73.137 + 5.91
            local seed3 = i * 41.723 + 2.17
            -- 粒子生命周期：每个粒子以不同的周期循环飞出
            local period = 1.2 + (seed2 % 10) * 0.08   -- 周期 1.2~2.0 秒
            local life = (time + seed1 * 0.1) % period  -- 当前生命阶段
            local t = life / period                      -- 0→1 归一化进度
            -- 飞出方向
            local angle = seed1 % (math.pi * 2)
            -- 飞出轨迹：从护盾表面出发，向外飞出 + 轻微上飘
            local dist = shieldR * (1.0 + t * 0.8)      -- 从护盾边缘飞到 1.8 倍半径
            local sparkX = cx + math.cos(angle) * dist
            local sparkY = drawCy + math.sin(angle) * dist - t * GS.CELL * 0.15  -- 上飘
            -- 横向扰动
            local drift = math.sin(time * 4.0 + seed3) * GS.CELL * 0.04
            sparkX = sparkX + drift
            -- 尺寸：初始较大，逐渐缩小消失
            local maxSize = math.max(1.5, GS.CELL * 0.035) * (0.6 + (seed3 % 5) * 0.12)
            local pSize = maxSize * (1.0 - t * 0.7)
            -- 透明度：中间亮两头暗（淡入→全亮→淡出）
            local alphaT = 1.0
            if t < 0.15 then
                alphaT = t / 0.15
            elseif t > 0.5 then
                alphaT = 1.0 - (t - 0.5) / 0.5
            end
            local pAlpha = math.floor(200 * alphaT * (0.7 + 0.3 * flicker))
            -- 颜色：飞出时从亮黄 → 橙 → 暗红
            local pR = math.floor(255 - 60 * t)
            local pG = math.floor(200 - 160 * t)
            local pB = math.floor(60 - 50 * t)
            if pAlpha > 5 and pSize > 0.5 then
                nvgBeginPath(vg)
                nvgCircle(vg, sparkX, sparkY, pSize)
                nvgFillColor(vg, nvgRGBA(pR, pG, pB, pAlpha))
                nvgFill(vg)
            end
        end

        -- 第7层：8个大型火焰舌（模拟护盾表面窜出的火舌）
        for i = 1, 8 do
            local tongueAngle = (i / 8) * math.pi * 2 + time * 1.2
            local tonguePhase = math.sin(time * 5.5 + i * 2.5)
            local tongueLen = GS.CELL * (0.06 + 0.05 * math.max(0, tonguePhase))
            if tongueLen > GS.CELL * 0.03 then
                -- 火舌起点在护盾边缘
                local tx1 = cx + math.cos(tongueAngle) * shieldR
                local ty1 = drawCy + math.sin(tongueAngle) * shieldR
                -- 火舌终点向外延伸
                local tx2 = cx + math.cos(tongueAngle) * (shieldR + tongueLen)
                local ty2 = drawCy + math.sin(tongueAngle) * (shieldR + tongueLen) - tongueLen * 0.3
                local tongueAlpha = math.floor(180 + 60 * tonguePhase)
                nvgBeginPath(vg)
                nvgMoveTo(vg, tx1, ty1)
                nvgLineTo(vg, tx2, ty2)
                nvgStrokeColor(vg, nvgRGBA(255, 140, 30, tongueAlpha))
                nvgStrokeWidth(vg, math.max(2.0, GS.CELL * 0.03))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
                -- 火舌尖端小亮点
                nvgBeginPath(vg)
                nvgCircle(vg, tx2, ty2, math.max(1.5, GS.CELL * 0.02))
                nvgFillColor(vg, nvgRGBA(255, 220, 80, tongueAlpha))
                nvgFill(vg)
            end
        end

        nvgLineCap(vg, NVG_BUTT)  -- 恢复默认线帽
    end


    if isAttacking then
        nvgRestore(vg)
    end

    -- 恢复隐匿半透明
    if isStealth then
        nvgRestore(vg)
    end

    -- 事件感叹号标记（showAlert，用于苏醒事件等）
    if unit.showAlert then
        local tagSize = math.max(14, GS.CELL * 0.45)
        local margin2 = GS.CELL * 0.12
        local bodyY2 = py + margin2 + breathe * 0.3
        local tagY = bodyY2 - tagSize * 0.6
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, tagSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        for _, off in ipairs(OFFSETS_4) do
            nvgText(vg, cx + off[1], tagY + off[2], "!", nil)
        end
        nvgFillColor(vg, nvgRGBA(230, 30, 30, 255))
        nvgText(vg, cx, tagY, "!", nil)
    end

    -- 朝向箭头（红色）
    drawFacingArrow(vg, cx, drawCy, GS.CELL, unit.facing, 230, 60, 60, 200)
end

-- ====================================================================
-- 绘制：怪物
-- ====================================================================
function M.drawMonster(unit, time)
    if unit.blinkHidden then return end
    local vg = M.vg
    local offX, offY, animT = M.getMoveAnimOffset(unit)
    local s = GS.unitSize(unit)
    local totalCell = s * GS.CELL
    local margin = totalCell * 0.10
    local bodyW = totalCell - margin * 2
    local cornerR = totalCell * 0.22

    local slamOX, slamOY, slamT = M.getSlamAnimOffset(unit)
    offX = offX + slamOX
    offY = offY + slamOY

    -- 稀有度颜色（残影/边框共用）
    local rarityDef = unit.rarity and GS.RARITY[unit.rarity]
    local br, bg2, bb = 140, 140, 140
    if rarityDef then
        br, bg2, bb = rarityDef.border[1], rarityDef.border[2], rarityDef.border[3]
    end

    -- 移动残影
    if unit.moveAnim and animT < 1.0 then
        local anim = unit.moveAnim
        local halfTC = totalCell / 2
        -- 大型怪物的 halfCell 偏移补正：path 坐标是左上角格子，中心需加 halfTC
        local halfCellForPath = GS.CELL / 2
        local largeOffset = halfTC - halfCellForPath  -- 大型单位额外偏移
        local ghostCount = 3
        for gi = 1, ghostCount do
            local gp = (animT - gi * 0.08)
            if gp > 0 and gp < 1 then
                local gEase = gp * gp * (3 - 2 * gp)
                local gx, gy = getPathPixelPos(anim, gEase, GS.CELL, GS.BOARD_X, GS.BOARD_Y, halfCellForPath, unit.x, unit.y)
                gx = gx + largeOffset
                gy = gy + largeOffset
                local gAlpha = math.floor(100 * (1 - gi / (ghostCount + 1)))
                drawMonsterGhost(vg, gx, gy, bodyW * (1 - gi * 0.05), cornerR, gAlpha, br, bg2, bb)
            end
        end
    end

    -- 撞击残影
    if unit.slamAnim and slamT < 1.0 then
        local basePx = GS.BOARD_X + (unit.x - 1) * GS.CELL + totalCell / 2
        local basePy = GS.BOARD_Y + (unit.y - 1) * GS.CELL + totalCell / 2
        for gi = 1, 2 do
            local delay = gi * 0.06
            local gt = math.max(0, slamT - delay)
            local gProgress = math.sin(math.pi * gt)
            local gx = basePx + unit.slamAnim.dirX * unit.slamAnim.slamDist * gProgress
            local gy = basePy + unit.slamAnim.dirY * unit.slamAnim.slamDist * gProgress
            local gAlpha = math.floor(80 * (1 - gi / 3))
            drawMonsterGhost(vg, gx, gy, bodyW * (1 - gi * 0.08), cornerR, gAlpha, br, bg2, bb)
        end
    end

    -- 跳跃动画 Y 偏移（受惊跳跃效果）
    local jumpOffY = 0
    if unit.jumpAnim then
        local jt = unit.jumpAnim.timer / unit.jumpAnim.duration
        if jt > 1 then jt = 1 end
        -- sin 曲线：向上跳起再落下，最大高度为 CELL * 0.6
        jumpOffY = -math.sin(math.pi * jt) * GS.CELL * 0.6
    end

    local px = GS.BOARD_X + (unit.x - 1) * GS.CELL + offX
    local py = GS.BOARD_Y + (unit.y - 1) * GS.CELL + offY + jumpOffY
    local cx = px + totalCell / 2
    local breathe = math.sin(time * 2.5 + unit.x * 0.7 + unit.y * 1.3) * 2
    local bodyX = px + margin
    local bodyY = py + margin + breathe * 0.3
    local bodyH = totalCell - margin * 2
    local drawCy = py + totalCell / 2 + breathe * 0.3

    -- 撞击挤压
    local slamSquash = false
    if unit.slamAnim and slamT < 1.0 then
        local slamProgress = math.sin(math.pi * slamT)
        local stretchFactor = 1.0 + slamProgress * 0.2
        local squashFactor = 1.0 - slamProgress * 0.12
        nvgSave(vg)
        nvgTranslate(vg, cx, drawCy)
        local absDX = math.abs(unit.slamAnim.dirX)
        local absDY = math.abs(unit.slamAnim.dirY)
        if absDX > absDY then
            nvgScale(vg, stretchFactor, squashFactor)
        else
            nvgScale(vg, squashFactor, stretchFactor)
        end
        nvgTranslate(vg, -cx, -drawCy)
        slamSquash = true
    end

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + totalCell - margin + 2, bodyW * 0.35, 3 * s)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)

    -- 外发光光晕
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX - 3, bodyY - 3, bodyW + 6, bodyH + 6, cornerR + 3)
    nvgFillColor(vg, nvgRGBA(br, bg2, bb, 50))
    nvgFill(vg)

    local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
        nvgRGBA(30, 55, 35, 240), nvgRGBA(20, 40, 25, 250))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 怪物图片（按需加载，回退到通用史莱姆图片）
    local monsterImg = -1
    if unit.image then
        monsterImg = ImageManager.lazyGet("monster", unit.image)
    end
    if monsterImg == -1 and M.slimeImage ~= -1 then
        monsterImg = M.slimeImage
    end
    if monsterImg ~= -1 then
        local imgSize = bodyW * 1.15
        local imgX = cx - imgSize / 2
        local imgY = drawCy - imgSize / 2

        local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
            0, monsterImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 边框使用稀有度颜色（图片之后绘制，保证可见）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(br, bg2, bb, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 怪物悬浮匕首（守门人等双匕首怪物）
    if unit.weaponTag and (unit.weaponTag == "双匕首" or unit.weaponTag == "匕首") and M.daggerImage ~= -1 then
        local radius = totalCell / 2
        local wSize = GS.CELL * 0.55
        -- 右匕首
        local rX = cx + radius * 0.7
        local rY = drawCy - radius * 0.7 + 15
        local rBob = math.sin(time * 3.0 + 1.0) * 1.5
        nvgSave(vg)
        nvgTranslate(vg, rX, rY + rBob)
        nvgScale(vg, 1, 1)
        nvgRotate(vg, math.rad(40 + 90 + 180))
        local rPaint = nvgImagePattern(vg, -wSize/2, -wSize/2, wSize, wSize, 0, M.daggerImage, 0.95)
        nvgBeginPath(vg)
        nvgRect(vg, -wSize/2, -wSize/2, wSize, wSize)
        nvgFillPaint(vg, rPaint)
        nvgFill(vg)
        nvgRestore(vg)
        -- 左匕首
        if unit.weaponTag == "双匕首" then
            local lX = cx - radius * 0.7
            local lY = drawCy - radius * 0.7 + 15
            local lBob = math.sin(time * 3.0 + 2.5) * 1.5
            nvgSave(vg)
            nvgTranslate(vg, lX, lY + lBob)
            nvgScale(vg, -1, 1)
            nvgRotate(vg, math.rad(40 + 90 + 180))
            local lPaint = nvgImagePattern(vg, -wSize/2, -wSize/2, wSize, wSize, 0, M.daggerImage, 0.95)
            nvgBeginPath(vg)
            nvgRect(vg, -wSize/2, -wSize/2, wSize, wSize)
            nvgFillPaint(vg, lPaint)
            nvgFill(vg)
            nvgRestore(vg)
        end
    end

    -- HP 条（边框上沿）— immortal 怪物不显示血条
    if not unit.immortal then
        local barW = bodyW * 0.8
        local barH = math.max(3, GS.CELL * 0.06)
        local barX = px + (totalCell - barW) / 2
        local barY = bodyY - barH

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 2)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)

        local hpRatio = math.max(0, math.min(1, unit.hp / math.max(1, unit.maxHp)))
        local hpColor = unit.isMonster and nvgRGBA(160, 20, 20, 255) or nvgRGBA(80, 220, 80, 255)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 2)
        nvgFillColor(vg, hpColor)
        nvgFill(vg)
    end

    -- 名字
    local nameSize = math.max(9, GS.CELL * 0.24)
    local nameY = bodyY + bodyH
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, nameSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local displayName = unit.name
    if unit.isTrainingDummy and unit.level then
        displayName = unit.name .. " Lv." .. unit.level
    end
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    for _, off in ipairs(OFFSETS_4) do
        nvgText(vg, cx + off[1], nameY + off[2], displayName, nil)
    end
    -- 名字颜色跟随稀有度
    local nr, ng, nb = 255, 255, 255
    if rarityDef and rarityDef.color then
        nr, ng, nb = rarityDef.color[1], rarityDef.color[2], rarityDef.color[3]
    end
    nvgFillColor(vg, nvgRGBA(nr, ng, nb, 255))
    nvgText(vg, cx, nameY, displayName, nil)

    -- 嘲讽标记
    if unit.taunted and unit.taunted > 0 then
        local tagSize = math.max(8, GS.CELL * 0.20)
        local tagY = bodyY - tagSize * 0.6
        -- 感叹号图标背景
        nvgBeginPath(vg)
        nvgCircle(vg, cx, tagY, tagSize * 0.55)
        nvgFillColor(vg, nvgRGBA(255, 60, 30, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 80, 220))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 感叹号文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, tagSize * 0.9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 220, 255))
        nvgText(vg, cx, tagY, "!", nil)
        -- 嘲讽边框闪烁
        local pulse = math.sin(time * 4) * 0.3 + 0.7
        local pulseAlpha = math.floor(120 * pulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX - 1, bodyY - 1, bodyW + 2, bodyH + 2, cornerR + 1)
        nvgStrokeColor(vg, nvgRGBA(255, 160, 40, pulseAlpha))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 事件感叹号标记（showAlert，用于苏醒事件等）
    if unit.showAlert then
        local tagSize = math.max(14, GS.CELL * 0.45)
        local tagY = bodyY - tagSize * 0.6
        local tagX = cx
        if unit.taunted and unit.taunted > 0 then
            tagX = cx - tagSize * 1.2
        end
        -- 红色感叹号（无背景）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, tagSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 黑色描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        for _, off in ipairs(OFFSETS_4) do
            nvgText(vg, tagX + off[1], tagY + off[2], "!", nil)
        end
        nvgFillColor(vg, nvgRGBA(230, 30, 30, 255))
        nvgText(vg, tagX, tagY, "!", nil)
    end

    -- 晕眩标记（黄色旋涡）
    if unit.stunned and unit.stunned > 0 then
        local tagSize = math.max(10, GS.CELL * 0.24)
        local tagY = bodyY - tagSize * 0.5
        -- 如果同时有嘲讽标记，往右偏移
        local tagX = cx
        if unit.taunted and unit.taunted > 0 then
            tagX = cx + tagSize * 1.2
        end
        -- 旋涡底部光晕
        local glowR = tagSize * 0.7
        local pulse = math.sin(time * 4) * 0.15 + 0.85
        local glowAlpha = math.floor(80 * pulse)
        local vortexGrad = nvgRadialGradient(vg, tagX, tagY, 0, glowR,
            nvgRGBA(240, 210, 50, glowAlpha),
            nvgRGBA(200, 170, 30, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, tagX, tagY, glowR)
        nvgFillPaint(vg, vortexGrad)
        nvgFill(vg)
        -- 旋涡螺旋臂（3条）
        nvgSave(vg)
        nvgTranslate(vg, tagX, tagY)
        for arm = 1, 3 do
            local baseAngle = (arm / 3) * math.pi * 2 + time * 6
            local segments = 6
            nvgBeginPath(vg)
            for si = 0, segments do
                local st = si / segments
                local sAngle = baseAngle + st * math.pi * 1.8
                local sR = tagSize * 0.55 * (1 - st * 0.75) * pulse
                local sx = math.cos(sAngle) * sR
                local sy = math.sin(sAngle) * sR * 0.50
                if si == 0 then
                    nvgMoveTo(vg, sx, sy)
                else
                    nvgLineTo(vg, sx, sy)
                end
            end
            local armAlpha = math.floor(220 * pulse)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 50, armAlpha))
            nvgStrokeWidth(vg, math.max(1.2, tagSize * 0.12))
            nvgStroke(vg)
        end
        -- 旋涡中心亮点
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, tagSize * 0.10)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, math.floor(240 * pulse)))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 冰冻效果：怪物下半部分被冰覆盖
    if unit.frozen and unit.frozen > 0 then
        local iceH = bodyH * 0.55  -- 冰覆盖下半部分
        local iceY = bodyY + bodyH - iceH
        -- 冰层底色（半透明冰蓝）
        local iceGrad = nvgLinearGradient(vg, bodyX, iceY, bodyX, bodyY + bodyH,
            nvgRGBA(120, 200, 255, 40),
            nvgRGBA(80, 160, 240, 130))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, iceY, bodyW, iceH, cornerR * 0.5)
        nvgFillPaint(vg, iceGrad)
        nvgFill(vg)
        -- 冰霜纹理：锯齿状上缘
        nvgBeginPath(vg)
        local teeth = 6
        nvgMoveTo(vg, bodyX, iceY + iceH * 0.25)
        for ti = 0, teeth do
            local tx = bodyX + (ti / teeth) * bodyW
            local peakOff = math.sin(ti * 2.3 + time * 1.5) * iceH * 0.12
            if ti % 2 == 0 then
                nvgLineTo(vg, tx, iceY - iceH * 0.08 + peakOff)
            else
                nvgLineTo(vg, tx, iceY + iceH * 0.10 + peakOff)
            end
        end
        nvgLineTo(vg, bodyX + bodyW, iceY + iceH * 0.25)
        nvgLineTo(vg, bodyX + bodyW, bodyY + bodyH)
        nvgLineTo(vg, bodyX, bodyY + bodyH)
        nvgClosePath(vg)
        local frostGrad = nvgLinearGradient(vg, bodyX, iceY, bodyX, bodyY + bodyH,
            nvgRGBA(160, 220, 255, 60),
            nvgRGBA(100, 180, 240, 100))
        nvgFillPaint(vg, frostGrad)
        nvgFill(vg)
        -- 冰晶高光点缀
        for ci = 1, 3 do
            local sparkX = bodyX + bodyW * (0.2 + ci * 0.25)
            local sparkY = iceY + iceH * (0.3 + math.sin(time * 2 + ci) * 0.2)
            local sparkA = math.floor(180 * (math.sin(time * 3 + ci * 1.7) * 0.3 + 0.7))
            local sparkR = math.max(1.5, bodyW * 0.03)
            nvgBeginPath(vg)
            nvgCircle(vg, sparkX, sparkY, sparkR)
            nvgFillColor(vg, nvgRGBA(220, 240, 255, sparkA))
            nvgFill(vg)
        end
        -- 冰冻边框闪烁
        local frostPulse = math.sin(time * 3) * 0.3 + 0.7
        local frostBorderA = math.floor(100 * frostPulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX - 1, bodyY - 1, bodyW + 2, bodyH + 2, cornerR + 1)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, frostBorderA))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 冻僵效果：周期性蓝色闪烁覆盖整个棋子（层数越高越亮）
    if unit.chilled and unit.chilledTurns and unit.chilledTurns > 0 and not (unit.frozen and unit.frozen > 0) then
        local cStacks = unit.chillStacks or 1
        local pulse = math.sin(time * 4) * 0.5 + 0.5
        local glowA = math.floor(math.min(200, 60 + cStacks * 25) * pulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(80, 160, 240, glowA))
        nvgFill(vg)
    end

    -- 中毒：周期性紫色闪烁覆盖整个棋子
    if unit.poisoned and unit.poisoned > 0 then
        local pulse = math.sin(time * 4) * 0.5 + 0.5  -- 0~1 周期闪烁
        local glowA = math.floor(90 * pulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(180, 80, 220, glowA))
        nvgFill(vg)
    end

    -- 破甲：周期性深灰色闪烁覆盖整个棋子
    if unit.armorBroken and unit.armorBrokenTurns and unit.armorBrokenTurns > 0 then
        local pulse = math.sin(time * 3.5 + 1.0) * 0.5 + 0.5
        local glowA = math.floor(90 * pulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(40, 40, 40, glowA))
        nvgFill(vg)
    end

    -- 灼伤：周期性橙红色闪烁覆盖整个棋子（叠层越多越亮）
    if unit.burned and unit.burnStacks and #unit.burnStacks > 0 then
        local stacks = #unit.burnStacks
        local pulse = math.sin(time * 5 + 0.5) * 0.5 + 0.5
        local glowA = math.floor(math.min(200, 60 + stacks * 10) * pulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(255, 100, 30, glowA))
        nvgFill(vg)
    end

    -- 致盲：周期性土黄色闪烁覆盖整个棋子
    if unit.sandBlinded and unit.sandBlindedTurns and unit.sandBlindedTurns > 0 then
        local pulse = math.sin(time * 3 + 2.0) * 0.5 + 0.5
        local glowA = math.floor(90 * pulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(200, 180, 80, glowA))
        nvgFill(vg)
    end

    -- 标记目标准心动画（呼吸缩放，不旋转）
    if GS.markedTarget == unit and unit.hp > 0 then
        local markR = math.max(10, GS.CELL * 0.35)
        local pulse = math.sin(time * 3) * 0.15 + 0.85
        local alpha = math.floor(200 * pulse)
        nvgSave(vg)
        nvgTranslate(vg, cx, drawCy)
        -- 准心圆环
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, markR * pulse)
        nvgStrokeColor(vg, nvgRGBA(255, 40, 40, alpha))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 十字线
        local lineLen = markR * 0.55 * pulse
        local gapR = markR * 0.25 * pulse
        nvgStrokeColor(vg, nvgRGBA(255, 60, 50, alpha))
        nvgStrokeWidth(vg, 1.5)
        for i = 0, 3 do
            local angle = i * math.pi / 2
            local cos_a = math.cos(angle)
            local sin_a = math.sin(angle)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cos_a * gapR, sin_a * gapR)
            nvgLineTo(vg, cos_a * (gapR + lineLen), sin_a * (gapR + lineLen))
            nvgStroke(vg)
        end
        -- 中心红点
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, 2)
        nvgFillColor(vg, nvgRGBA(255, 50, 40, alpha))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 受伤闪红
    if unit.hurtTimer and unit.hurtTimer >= 0 and unit.hurtDuration and unit.hurtDuration > 0 then
        local ht = unit.hurtTimer / unit.hurtDuration
        local redAlpha = math.floor(180 * (1 - ht))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(255, 30, 30, redAlpha))
        nvgFill(vg)
    end

    -- 反击/复仇发光
    if unit.counterGlow then
        local cg = unit.counterGlow
        local t = cg.timer / cg.duration
        -- 快速亮起，缓慢消退
        local intensity = t < 0.2 and (t / 0.2) or (1 - (t - 0.2) / 0.8)
        intensity = math.max(0, math.min(1, intensity))
        local glowA = math.floor(200 * intensity)
        -- 内层强光
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX - 2, bodyY - 2, bodyW + 4, bodyH + 4, cornerR + 2)
        nvgFillColor(vg, nvgRGBA(cg.r, cg.g, cg.b, glowA))
        nvgFill(vg)
        -- 外层光晕
        local outerA = math.floor(120 * intensity)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX - 5, bodyY - 5, bodyW + 10, bodyH + 10, cornerR + 4)
        nvgFillColor(vg, nvgRGBA(cg.r, cg.g, cg.b, outerA))
        nvgFill(vg)
    end

    -- 朝向箭头（红色，敌人标识）
    drawFacingArrow(vg, cx, drawCy, totalCell, unit.facing, 230, 60, 60, 200)



    if slamSquash then
        nvgRestore(vg)
    end
end

-- ====================================================================
-- 绘制：怪物死亡特效（缩小 + 变红 + 淡出 + 粒子飘散）
-- ====================================================================
function M.drawDeathEffects()
    local vg = M.vg
    for _, e in ipairs(GS.deathEffects) do
        -- delay/pendingHit 期间：绘制单位静态形象（等伤害数字显示后再播放死亡动画）
        if e.pendingHit or (e.delay and e.delay > 0) then
            local s = e.unitScale or 1
            local totalCell = s * GS.CELL
            local margin = totalCell * 0.10
            local bodyW = totalCell - margin * 2
            local bodyH = bodyW
            local cornerR = totalCell * 0.22
            local px = GS.BOARD_X + (e.x - 1) * GS.CELL
            local py = GS.BOARD_Y + (e.y - 1) * GS.CELL
            local bodyX = px + margin
            local bodyY = py + margin
            if e.isPlayer then
                -- 玩家：圆形蓝色
                local pMargin = GS.CELL * 0.12
                local pRadius = (GS.CELL - pMargin * 2) / 2
                local pcx = px + GS.CELL / 2
                local pcy = py + GS.CELL / 2
                nvgBeginPath(vg)
                nvgCircle(vg, pcx, pcy, pRadius)
                nvgFillColor(vg, nvgRGBA(80, 160, 255, 255))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(180, 220, 255, 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            else
                -- 怪物：方形
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
                nvgFillColor(vg, nvgRGBA(30, 55, 35, 255))
                nvgFill(vg)
                if e.image then
                    local monsterImg = ImageManager.lazyGet("monster", e.image)
                    if monsterImg >= 0 then
                        local imgPaint = nvgImagePattern(vg, bodyX, bodyY, bodyW, bodyH, 0, monsterImg, 1.0)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
                        nvgFillPaint(vg, imgPaint)
                        nvgFill(vg)
                    end
                end
            end
            goto continueDeathFx
        end
        local t = safeProgress(e.timer, e.duration)  -- 0→1 进度
        if t >= 1 then goto continueDeathFx end

        local s = e.unitScale or 1
        local totalCell = s * GS.CELL
        local margin = totalCell * 0.10
        local bodyW = totalCell - margin * 2
        local bodyH = bodyW
        local cornerR = totalCell * 0.22

        local px = GS.BOARD_X + (e.x - 1) * GS.CELL
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL
        local cx = px + totalCell / 2
        local cy = py + totalCell / 2

        -- 缩放曲线：先微胀再快速缩小消失
        local scale
        if t < 0.15 then
            scale = 1.0 + t / 0.15 * 0.12  -- 前15%: 1.0→1.12 微胀
        else
            local st = (t - 0.15) / 0.85
            scale = 1.12 * (1 - st * st)   -- 后85%: 1.12→0 平方加速缩小
        end

        -- 总透明度
        local alpha
        if t < 0.3 then
            alpha = 255
        else
            alpha = math.floor(255 * (1 - (t - 0.3) / 0.7))
        end
        if alpha <= 0 then goto continueDeathFx end

        -- 红色叠加强度（越到后面越红）
        local redTint = math.min(1.0, t * 1.5)

        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgScale(vg, scale, scale)
        nvgTranslate(vg, -cx, -cy)

        local bodyX = px + margin
        local bodyY = py + margin

        if e.isPlayer then
            -- 玩家死亡动画：圆形蓝色→红色渐变
            local pMargin = GS.CELL * 0.12
            local pRadius = (GS.CELL - pMargin * 2) / 2
            local pr = math.floor(80 + 140 * redTint)
            local pg = math.floor(160 * (1 - redTint * 0.8))
            local pb = math.floor(255 * (1 - redTint * 0.9))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, pRadius)
            nvgFillColor(vg, nvgRGBA(pr, pg, pb, alpha))
            nvgFill(vg)
            -- 边框（蓝→红）
            local bdr = math.floor(180 + 40 * redTint)
            local bdg = math.floor(220 * (1 - redTint * 0.7))
            local bdb = math.floor(255 * (1 - redTint * 0.7))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, pRadius)
            nvgStrokeColor(vg, nvgRGBA(bdr, bdg, bdb, alpha))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        else
            -- 怪物死亡动画：方形
            -- 身体底色（逐渐变红变暗）
            local gr = math.floor(30 + 180 * redTint)
            local gg = math.floor(55 * (1 - redTint * 0.8))
            local gb = math.floor(35 * (1 - redTint * 0.9))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
            nvgFillColor(vg, nvgRGBA(gr, gg, gb, alpha))
            nvgFill(vg)

            -- 怪物图片（带红色调和透明度）
            local monsterImg = -1
            if e.image then
                monsterImg = ImageManager.lazyGet("monster", e.image)
            end
            if monsterImg == -1 and M.slimeImage ~= -1 then
                monsterImg = M.slimeImage
            end
            if monsterImg ~= -1 then
                local imgSize = bodyW * 1.15
                local imgX = cx - imgSize / 2
                local imgY = cy - imgSize / 2
                local imgAlpha = alpha / 255
                local imgPat = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize, 0, monsterImg, imgAlpha)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
                nvgFillPaint(vg, imgPat)
                nvgFill(vg)
                -- 红色叠加层
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
                nvgFillColor(vg, nvgRGBA(220, 30, 20, math.floor(redTint * 120 * (alpha / 255))))
                nvgFill(vg)
            end

            -- 边框（变红）
            local rarityDef = e.rarity and GS.RARITY[e.rarity]
            local br, bg2, bb = 140, 140, 140
            if rarityDef then br, bg2, bb = rarityDef.border[1], rarityDef.border[2], rarityDef.border[3] end
            local borderR = math.floor(br + (220 - br) * redTint)
            local borderG = math.floor(bg2 * (1 - redTint * 0.7))
            local borderB = math.floor(bb * (1 - redTint * 0.7))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
            nvgStrokeColor(vg, nvgRGBA(borderR, borderG, borderB, alpha))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        nvgRestore(vg)

        -- 粒子（在变换外绘制，不受缩放影响）
        -- 基于 timer 计算位置（匀加速运动公式，避免帧率依赖）
        if e.particles then
            local pt = e.timer
            for _, p in ipairs(e.particles) do
                local pox = p.vx * pt
                local poy = p.vy * pt + 0.5 * 60 * pt * pt  -- vy*t + 0.5*g*t^2
                local pAlpha = math.floor(alpha * (1 - t))
                local pSize = p.size * (1 - t * 0.6)
                if pAlpha > 0 and pSize > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, cx + pox, cy + poy, pSize)
                    if e.isPlayer then
                        nvgFillColor(vg, nvgRGBA(80, 140, 255, pAlpha))
                    else
                        nvgFillColor(vg, nvgRGBA(220, 80, 30, pAlpha))
                    end
                    nvgFill(vg)
                end
            end
        end

        ::continueDeathFx::
    end
end

-- ====================================================================
-- 绘制：玩家复活光芒特效（从光柱中诞生）
-- ====================================================================
function M.drawReviveEffect()
    local vg = M.vg
    local e = GS.reviveEffect
    if not e then return end

    local t = safeProgress(e.timer, e.duration)
    if t >= 1 then return end

    local cx = GS.BOARD_X + (e.x - 1) * GS.CELL + GS.CELL / 2
    local cy = GS.BOARD_Y + (e.y - 1) * GS.CELL + GS.CELL / 2
    local radius = (GS.CELL - GS.CELL * 0.12 * 2) / 2

    -- === 阶段划分 ===
    -- 0.0~0.3: 光柱从天而降 + 中心白光膨胀
    -- 0.3~0.6: 光柱最亮 + 光环扩散 + 光线射出
    -- 0.6~1.0: 光芒渐弱消散 + 粒子上升

    -- 光柱（垂直光束）
    local beamAlpha, beamW
    if t < 0.3 then
        -- 光柱从细到粗出现
        local bt = t / 0.3
        beamW = radius * 0.3 + radius * 1.2 * bt * bt
        beamAlpha = math.floor(180 * bt)
    elseif t < 0.6 then
        beamW = radius * 1.5
        beamAlpha = 180
    else
        -- 光柱逐渐消散
        local bt = (t - 0.6) / 0.4
        beamW = radius * 1.5 * (1 - bt * 0.5)
        beamAlpha = math.floor(180 * (1 - bt))
    end

    if beamAlpha > 0 then
        -- 光柱主体（上方延伸到棋盘顶部）
        local beamTop = GS.BOARD_Y
        local beamBot = cy + radius
        local beamGrad = nvgLinearGradient(vg, cx, beamTop, cx, beamBot,
            nvgRGBA(200, 230, 255, 0),
            nvgRGBA(180, 220, 255, beamAlpha))
        nvgBeginPath(vg)
        nvgRect(vg, cx - beamW / 2, beamTop, beamW, beamBot - beamTop)
        nvgFillPaint(vg, beamGrad)
        nvgFill(vg)

        -- 光柱中心高亮线
        local coreW = beamW * 0.25
        local coreGrad = nvgLinearGradient(vg, cx, beamTop, cx, beamBot,
            nvgRGBA(255, 255, 255, 0),
            nvgRGBA(255, 255, 255, math.floor(beamAlpha * 0.6)))
        nvgBeginPath(vg)
        nvgRect(vg, cx - coreW / 2, beamTop, coreW, beamBot - beamTop)
        nvgFillPaint(vg, coreGrad)
        nvgFill(vg)
    end

    -- 中心白光球（膨胀→收缩到角色大小）
    local glowR, glowAlpha
    if t < 0.15 then
        -- 快速膨胀
        local gt = t / 0.15
        glowR = radius * 0.2 + radius * 2.5 * gt
        glowAlpha = math.floor(200 * gt)
    elseif t < 0.5 then
        -- 最亮状态，微微脉动
        local gt = (t - 0.15) / 0.35
        local pulse = 1.0 + 0.1 * math.sin(gt * math.pi * 4)
        glowR = radius * 2.7 * pulse
        glowAlpha = 200
    else
        -- 收缩消散
        local gt = (t - 0.5) / 0.5
        glowR = radius * 2.7 * (1 - gt * 0.85)
        glowAlpha = math.floor(200 * (1 - gt))
    end

    if glowAlpha > 0 then
        local glowPaint = nvgRadialGradient(vg, cx, cy, glowR * 0.1, glowR,
            nvgRGBA(255, 255, 255, glowAlpha),
            nvgRGBA(120, 180, 255, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, glowR)
        nvgFillPaint(vg, glowPaint)
        nvgFill(vg)
    end

    -- 光环扩散（t=0.2~0.7 期间多圈扩散）
    local ringCount = 3
    for ri = 1, ringCount do
        local ringStart = 0.15 + (ri - 1) * 0.1
        local ringEnd = ringStart + 0.5
        if t >= ringStart and t < ringEnd then
            local rt = (t - ringStart) / (ringEnd - ringStart)
            local ringR = radius * (0.5 + 3.5 * rt)
            local ringA = math.floor(160 * (1 - rt) * (1 - rt))
            local ringW = math.max(1, 2.5 * (1 - rt))
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, ringR)
            nvgStrokeColor(vg, nvgRGBA(180, 220, 255, ringA))
            nvgStrokeWidth(vg, ringW)
            nvgStroke(vg)
        end
    end

    -- 放射光线（t=0.2~0.8）
    if t >= 0.2 and t < 0.8 then
        local lt = (t - 0.2) / 0.6
        local rayCount = 8
        local rayAlpha = math.floor(140 * (1 - lt * lt))
        local rayLen = radius * (1.5 + 3.0 * lt)
        local rayW = math.max(0.5, 1.5 * (1 - lt))
        nvgStrokeWidth(vg, rayW)
        for ri = 0, rayCount - 1 do
            local angle = math.rad(ri * (360 / rayCount) + t * 60)
            local x1 = cx + math.cos(angle) * radius * 0.5
            local y1 = cy + math.sin(angle) * radius * 0.5
            local x2 = cx + math.cos(angle) * rayLen
            local y2 = cy + math.sin(angle) * rayLen
            nvgBeginPath(vg)
            nvgMoveTo(vg, x1, y1)
            nvgLineTo(vg, x2, y2)
            nvgStrokeColor(vg, nvgRGBA(200, 230, 255, rayAlpha))
            nvgStroke(vg)
        end
    end

    -- 上升粒子（t=0.3~1.0 期间光点上升消散）
    if t >= 0.3 then
        local pt = (t - 0.3) / 0.7
        local sparkCount = 12
        for si = 1, sparkCount do
            local seed = si * 137.5
            local angle = math.rad(seed)
            local dist = radius * (0.3 + 0.7 * ((si % 3 + 1) / 3))
            local sx = cx + math.cos(angle) * dist * (1 - pt * 0.3)
            local sy = cy + math.sin(angle) * dist * 0.4 - radius * 2.5 * pt * ((si % 4 + 2) / 4)
            local sAlpha = math.floor(200 * (1 - pt))
            local sSize = (1.5 + (si % 3) * 0.8) * (1 - pt * 0.5)
            if sAlpha > 0 and sSize > 0 then
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, sSize)
                nvgFillColor(vg, nvgRGBA(200, 230, 255, sAlpha))
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：幻影消散特效（紫色主题缩小+淡出+粒子散射）
-- ====================================================================
function M.drawPhantomDissolveEffects()
    local vg = M.vg
    for _, e in ipairs(GS.phantomDissolveEffects) do
        local t = safeProgress(e.timer, e.duration)
        if t >= 1 then goto continuePhantomFx end

        local totalCell = GS.CELL
        local margin = totalCell * 0.10
        local bodyW = totalCell - margin * 2
        local bodyH = bodyW
        local cornerR = totalCell * 0.22

        local px = GS.BOARD_X + (e.x - 1) * GS.CELL
        local py = GS.BOARD_Y + (e.y - 1) * GS.CELL
        local cx = px + totalCell / 2
        local cy = py + totalCell / 2
        local bodyX = px + margin
        local bodyY = py + margin

        -- 缩放：先微胀再缩小消失
        local scale
        if t < 0.12 then
            scale = 1.0 + t / 0.12 * 0.1
        else
            local st = (t - 0.12) / 0.88
            scale = 1.1 * (1 - st * st)
        end

        -- 透明度
        local alpha
        if t < 0.2 then
            alpha = 255
        else
            alpha = math.floor(255 * (1 - (t - 0.2) / 0.8))
        end
        if alpha <= 0 then goto continuePhantomFx end

        -- 紫色调强度
        local purpleTint = math.min(1.0, t * 2.0)

        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgScale(vg, scale, scale)
        nvgTranslate(vg, -cx, -cy)

        -- 紫色底色（逐渐变亮变透明）
        local gr = math.floor(80 + 100 * purpleTint)
        local gg = math.floor(40 * (1 - purpleTint * 0.5))
        local gb = math.floor(120 + 80 * purpleTint)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(gr, gg, gb, alpha))
        nvgFill(vg)

        -- 玩家头像（半透明消散）
        local avatarImg = M.classAvatars[GS.currentClass] or M.playerAvatar
        if avatarImg and avatarImg ~= -1 then
            local imgSize = bodyW * 1.0
            local imgX = cx - imgSize / 2
            local imgY = cy - imgSize / 2
            local imgPat = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize, 0, avatarImg, alpha / 255)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
            nvgFillPaint(vg, imgPat)
            nvgFill(vg)
        end

        -- 紫色叠加层
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(160, 80, 255, math.floor(purpleTint * 100 * (alpha / 255))))
        nvgFill(vg)

        -- 紫色边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgStrokeColor(vg, nvgRGBA(180, 120, 255, alpha))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgRestore(vg)

        -- 紫色粒子（在变换外绘制）
        if e.particles then
            local pt = e.timer
            for _, p in ipairs(e.particles) do
                local pox = p.vx * pt
                local poy = p.vy * pt + 0.5 * 40 * pt * pt
                local pAlpha = math.floor(alpha * (1 - t * 0.8))
                local pSize = p.size * (1 - t * 0.5)
                if pAlpha > 0 and pSize > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, cx + pox, cy + poy, pSize)
                    nvgFillColor(vg, nvgRGBA(180, 120, 255, pAlpha))
                    nvgFill(vg)
                end
            end
        end

        ::continuePhantomFx::
    end
end

-- ====================================================================
-- 绘制：圣树
-- ====================================================================
function M.drawHolyTree(tree, time)
    local vg = M.vg
    local totalCell = GS.CELL
    local margin = totalCell * 0.10
    local bodyW = totalCell - margin * 2
    local bodyH = bodyW
    local cornerR = totalCell * 0.22

    local px = GS.BOARD_X + (tree.x - 1) * totalCell
    local py = GS.BOARD_Y + (tree.y - 1) * totalCell
    local cx = px + totalCell / 2
    local cy = py + totalCell / 2
    local bodyX = px + margin
    local bodyY = py + margin

    -- 治疗范围光圈（神圣金色）
    local rangeRadius = (tree.healRange + 0.5) * totalCell
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, rangeRadius)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 18))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, 50))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 呼吸动画
    local breathe = math.sin(time * 1.5 + tree.x * 0.5) * 1.5
    local drawCy = cy + breathe * 0.3

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + totalCell - margin + 2, bodyW * 0.35, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)

    -- 外发光光晕（神圣金色）
    local glow = math.sin(time * 3.0) * 0.3 + 0.7
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX - 3, bodyY - 3, bodyW + 6, bodyH + 6, cornerR + 3)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, math.floor(50 * glow)))
    nvgFill(vg)

    -- 身体背景（深金褐色）
    local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
        nvgRGBA(50, 40, 15, 240), nvgRGBA(35, 28, 10, 250))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 圣树图片
    local treeImg = -1
    if tree.image then
        treeImg = ImageManager.lazyGet("holytree", tree.image)
    end
    if treeImg ~= -1 then
        local imgSize = bodyW * 1.15
        local imgX = cx - imgSize / 2
        local imgY = drawCy - imgSize / 2
        local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
            0, treeImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 神圣金色边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(255, 210, 100, 220))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- HP 条（神圣金色）
    local barW = bodyW * 0.8
    local barH = math.max(3, totalCell * 0.06)
    local barX = px + (totalCell - barW) / 2
    local barY = bodyY - barH

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    local hpRatio = math.max(0, math.min(1, tree.hitsLeft / math.max(1, tree.maxHp)))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 2)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 255))
    nvgFill(vg)

    -- 剩余回合数（已隐藏）
    -- local infoText = tree.turnsLeft .. "T"
    -- nvgFontFace(vg, "sans")
    -- nvgFontSize(vg, math.max(8, totalCell * 0.18))
    -- nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    -- nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    -- nvgText(vg, cx + 1, barY - 1, infoText, nil)
    -- nvgFillColor(vg, nvgRGBA(255, 230, 160, 255))
    -- nvgText(vg, cx, barY - 1, infoText, nil)

    -- 名字（神圣金色，底部）
    local nameSize = math.max(9, totalCell * 0.24)
    local nameY = bodyY + bodyH
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, nameSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    for _, off in ipairs(OFFSETS_4) do
        nvgText(vg, cx + off[1], nameY + off[2], "圣树", nil)
    end
    nvgFillColor(vg, nvgRGBA(255, 230, 140, 255))
    nvgText(vg, cx, nameY, "圣树", nil)
end

-- ====================================================================
-- 绘制：友军（猎犬等）
-- ====================================================================
function M.drawCompanion(unit, time)
    local vg = M.vg
    local offX, offY, animT = M.getMoveAnimOffset(unit)
    local slamOX, slamOY, slamT = M.getSlamAnimOffset(unit)
    offX = offX + slamOX
    offY = offY + slamOY

    local totalCell = GS.CELL
    local margin = totalCell * 0.10
    local bodyW = totalCell - margin * 2
    local cornerR = totalCell * 0.22

    -- 友军颜色：幻影紫色，其他绿色
    local br, bg2, bb
    local isPhantom = unit.isPhantom
    if isPhantom then
        br, bg2, bb = 140, 80, 200
    else
        br, bg2, bb = 60, 200, 80
    end

    -- 移动残影
    if unit.moveAnim and animT < 1.0 then
        local anim = unit.moveAnim
        local halfCell = GS.CELL / 2
        local ghostCount = 3
        for gi = 1, ghostCount do
            local gp = (animT - gi * 0.08)
            if gp > 0 and gp < 1 then
                local gEase = gp * gp * (3 - 2 * gp)
                local gx, gy = getPathPixelPos(anim, gEase, GS.CELL, GS.BOARD_X, GS.BOARD_Y, halfCell, unit.x, unit.y)
                local gAlpha = math.floor(100 * (1 - gi / (ghostCount + 1)))
                drawMonsterGhost(vg, gx, gy, bodyW * (1 - gi * 0.05), cornerR, gAlpha, br, bg2, bb)
            end
        end
    end

    local px = GS.BOARD_X + (unit.x - 1) * GS.CELL + offX
    local py = GS.BOARD_Y + (unit.y - 1) * GS.CELL + offY
    local cx = px + totalCell / 2
    local breathe = math.sin(time * 2.5 + unit.x * 0.7 + unit.y * 1.3) * 2
    local bodyX = px + margin
    local bodyY = py + margin + breathe * 0.3
    local bodyH = totalCell - margin * 2
    local drawCy = py + totalCell / 2 + breathe * 0.3

    -- 撞击挤压
    local slamSquash = false
    if unit.slamAnim and slamT < 1.0 then
        local slamProgress = math.sin(math.pi * slamT)
        local stretchFactor = 1.0 + slamProgress * 0.2
        local squashFactor = 1.0 - slamProgress * 0.12
        nvgSave(vg)
        nvgTranslate(vg, cx, drawCy)
        local absDX = math.abs(unit.slamAnim.dirX)
        local absDY = math.abs(unit.slamAnim.dirY)
        if absDX > absDY then
            nvgScale(vg, stretchFactor, squashFactor)
        else
            nvgScale(vg, squashFactor, stretchFactor)
        end
        nvgTranslate(vg, -cx, -drawCy)
        slamSquash = true
    end

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + totalCell - margin + 2, bodyW * 0.35, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)

    -- 外发光光晕（绿色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX - 3, bodyY - 3, bodyW + 6, bodyH + 6, cornerR + 3)
    nvgFillColor(vg, nvgRGBA(br, bg2, bb, 50))
    nvgFill(vg)

    -- 身体背景
    local bodyGrad
    if isPhantom then
        bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
            nvgRGBA(50, 20, 80, 180), nvgRGBA(30, 10, 60, 190))
    else
        bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
            nvgRGBA(25, 60, 30, 240), nvgRGBA(15, 45, 20, 250))
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 幻影：绘制半透明玩家头像 + 闪烁效果
    if isPhantom then
        local pulse = 0.5 + 0.5 * math.sin(time * 3)
        local silAlpha = math.floor(160 + 60 * pulse)
        local avatarImg = M.classAvatars[GS.currentClass] or M.playerAvatar
        if avatarImg and avatarImg ~= -1 then
            local imgSize = bodyW * 1.0
            local imgX = cx - imgSize / 2
            local imgY = drawCy - imgSize / 2
            nvgGlobalAlpha(vg, silAlpha / 255)
            local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
                0, avatarImg, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
            nvgGlobalAlpha(vg, 1.0)
        else
            nvgFontFace(vg, "emoji")
            nvgFontSize(vg, bodyW * 0.65)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 120, 255, silAlpha))
            nvgText(vg, cx, drawCy, "👤", nil)
        end
    end

    -- 猎犬图片
    local compImg = -1
    if unit.image then
        compImg = ImageManager.lazyGet("companion", unit.image)
    end
    if compImg ~= -1 then
        local imgSize = bodyW * 1.15
        local imgX = cx - imgSize / 2
        local imgY = drawCy - imgSize / 2
        local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
            0, compImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 绿色边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(br, bg2, bb, 220))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- HP 条（绿色）
    local barW = bodyW * 0.8
    local barH = math.max(3, GS.CELL * 0.06)
    local barX = px + (totalCell - barW) / 2
    local barY = bodyY - barH

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    local hpRatio = math.max(0, math.min(1, unit.hp / math.max(1, unit.maxHp)))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 2)
    if isPhantom then
        nvgFillColor(vg, nvgRGBA(160, 100, 240, 255))
    else
        nvgFillColor(vg, nvgRGBA(80, 220, 80, 255))
    end
    nvgFill(vg)

    -- 幻影：HP条上方显示剩余次数
    if isPhantom then
        local hitsText = unit.hp .. "/" .. unit.maxHp
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(8, GS.CELL * 0.18))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        nvgText(vg, cx, barY - 1, hitsText, nil)
        nvgFillColor(vg, nvgRGBA(200, 160, 255, 255))
        nvgText(vg, cx, barY - 1, hitsText, nil)
    end

    -- 名字（根据稀有度颜色显示，不显示等级）
    local nameSize = math.max(9, GS.CELL * 0.24)
    local nameY = bodyY + bodyH
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, nameSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    local displayName = unit.name
    for _, off in ipairs(OFFSETS_4) do
        nvgText(vg, cx + off[1], nameY + off[2], displayName, nil)
    end
    local companionRarity = unit.rarity and GS.RARITY[unit.rarity]
    if isPhantom then
        nvgFillColor(vg, nvgRGBA(180, 140, 255, 255))
    elseif companionRarity and companionRarity.color then
        nvgFillColor(vg, nvgRGBA(companionRarity.color[1], companionRarity.color[2], companionRarity.color[3], 255))
    else
        nvgFillColor(vg, nvgRGBA(100, 255, 120, 255))
    end
    nvgText(vg, cx, nameY, displayName, nil)

    -- 受伤闪红
    if unit.hurtTimer and unit.hurtTimer >= 0 and unit.hurtDuration and unit.hurtDuration > 0 then
        local ht = unit.hurtTimer / unit.hurtDuration
        local redAlpha = math.floor(180 * (1 - ht))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillColor(vg, nvgRGBA(255, 30, 30, redAlpha))
        nvgFill(vg)
    end

    -- 朝向箭头（红色）
    drawFacingArrow(vg, cx, drawCy, totalCell, unit.facing, 230, 60, 60, 200)

    -- 浮空剑（事件友军专属）—— 攻击特效播放时隐藏
    local hasCompAttackFx = unit.slamAnim ~= nil
    if not hasCompAttackFx then
        for _, ef in ipairs(GS.attackEffects) do
            if ef.isCompanion then hasCompAttackFx = true; break end
        end
    end
    if unit.hasFloatingSword and M.swordImage and M.swordImage ~= -1 and not hasCompAttackFx then
        local wSize = GS.CELL * 0.65
        local radius = bodyW * 0.5
        local wX = cx + radius * 0.7
        local wY = drawCy - radius * 0.7
        local wBob = math.sin(time * 3.0 + 1.0) * 1.5

        nvgSave(vg)
        nvgTranslate(vg, wX, wY + wBob)
        nvgScale(vg, -1, 1)
        nvgRotate(vg, math.rad(30))
        local imgPaint = nvgImagePattern(vg,
            -wSize / 2, -wSize / 2,
            wSize, wSize,
            0, M.swordImage, 0.95)
        nvgBeginPath(vg)
        nvgRect(vg, -wSize / 2, -wSize / 2, wSize, wSize)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 浮动文本（如芙蕾雅战后"呼……"）
    -- 浮动文本已移至 drawFloatingTexts()，在顶部栏之后独立绘制

    if slamSquash then
        nvgRestore(vg)
    end
end

-- ====================================================================
-- 绘制：浮动文本（独立于 drawUnits，在顶部栏之后绘制以确保可见）
-- ====================================================================
function M.drawFloatingTexts()
    local vg = M.vg

    -- 绘制单个单位的浮动文本
    local function drawUnitFloatingText(unit, unitCellSize)
        local ft = unit.floatingText
        if not ft then return end

        local totalCell = unitCellSize
        local margin = totalCell * 0.10

        local cx = GS.BOARD_X + (unit.x - 1) * GS.CELL + totalCell / 2
        local bodyY = GS.BOARD_Y + (unit.y - 1) * GS.CELL + margin

        -- 透明度（渐隐）
        local ftAlpha = 255
        if ft.timer >= ft.fadeStart then
            local fadeProgress = (ft.timer - ft.fadeStart) / (ft.duration - ft.fadeStart)
            if fadeProgress > 1 then fadeProgress = 1 end
            ftAlpha = math.floor(255 * (1 - fadeProgress))
        end
        -- 向上漂浮效果
        local floatUp = ft.timer * 12
        local ftSize = math.max(14, GS.CELL * 0.38)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, ftSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local ftY = bodyY - ftSize * 0.5 - floatUp
        -- 黑色描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(ftAlpha * 0.7)))
        for _, off in ipairs(OFFSETS_4) do
            nvgText(vg, cx + off[1], ftY + off[2], ft.text, nil)
        end
        local ftCol = ft.color or {255, 255, 255}
        nvgFillColor(vg, nvgRGBA(ftCol[1], ftCol[2], ftCol[3], ftAlpha))
        nvgText(vg, cx, ftY, ft.text, nil)
    end

    -- 遍历所有怪物
    for _, unit in ipairs(GS.monsters) do
        if unit.floatingText then
            drawUnitFloatingText(unit, GS.unitSize(unit) * GS.CELL)
        end
    end
    -- 遍历所有友军（如芙蕾雅）
    for _, unit in ipairs(GS.companions) do
        if unit.floatingText then
            drawUnitFloatingText(unit, GS.CELL)
        end
    end
    -- 玩家浮动文本
    if GS.player and GS.player.floatingText then
        drawUnitFloatingText(GS.player, GS.CELL)
    end
end

-- ====================================================================
-- 绘制：家中猎犬（固定位置，呼吸动画，使用猎犬图片）
-- ====================================================================
function M.drawHomeHound(hound, time)
    local vg = M.vg
    local totalCell = GS.CELL
    local margin = totalCell * 0.10
    local bodyW = totalCell - margin * 2
    local bodyH = bodyW
    local cornerR = totalCell * 0.22

    local px = GS.BOARD_X + (hound.x - 1) * totalCell
    local py = GS.BOARD_Y + (hound.y - 1) * totalCell
    local cx = px + totalCell / 2
    local cy = py + totalCell / 2
    -- 呼吸动画
    local breathe = math.sin(time * 1.5 + 1.0) * 2
    local bodyX = px + margin
    local bodyY = py + margin + breathe * 0.3

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + totalCell - margin + 2, bodyW * 0.35, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
    nvgFill(vg)

    -- 身体背景
    local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
        nvgRGBA(80, 70, 50, 240), nvgRGBA(50, 40, 30, 250))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 猎犬图片
    local houndImg = ImageManager.lazyGet("companion", "image/hound.png")
    if houndImg ~= -1 then
        local imgSize = bodyW * 1.15
        local drawCy = cy + breathe * 0.3
        local imgX = cx - imgSize / 2
        local imgY = drawCy - imgSize / 2
        local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
            0, houndImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 绿色边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(60, 200, 80, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 浮动文本（汪汪，渲染在猎犬上方）
    local ft = hound.floatingText
    if ft then
        local ftAlpha = 255
        if ft.timer >= ft.fadeStart then
            local fp = (ft.timer - ft.fadeStart) / (ft.duration - ft.fadeStart)
            ftAlpha = math.floor(255 * (1 - math.min(fp, 1)))
        end
        local floatUp = ft.timer * 28
        local ftSize = math.max(14, totalCell * 0.32)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, ftSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local ftY = bodyY - ftSize * 0.5 - floatUp
        -- 黑色描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(ftAlpha * 0.7)))
        for _, off in ipairs(OFFSETS_4) do
            nvgText(vg, cx + off[1], ftY + off[2], ft.text, nil)
        end
        -- 白色主体
        nvgFillColor(vg, nvgRGBA(255, 255, 255, ftAlpha))
        nvgText(vg, cx, ftY, ft.text, nil)
    end
end

-- ====================================================================
-- 绘制：家中伴侣NPC（方形边框+头像图片，与事件companion同款）
-- ====================================================================
function M.drawHomeNpc(npc, time)
    local vg = M.vg
    local offX, offY = 0, 0
    if npc.moveAnim then
        offX, offY = M.getMoveAnimOffset(npc)
    end

    local totalCell = GS.CELL
    local margin = totalCell * 0.10
    local bodyW = totalCell - margin * 2
    local bodyH = bodyW
    local cornerR = totalCell * 0.22

    local px = GS.BOARD_X + (npc.x - 1) * totalCell + offX
    local py = GS.BOARD_Y + (npc.y - 1) * totalCell + offY
    local cx = px + totalCell / 2
    local cy = py + totalCell / 2
    -- 呼吸动画（与玩家错相）
    local breathe = math.sin(time * 2.0 + 3.14) * 2
    local bodyX = px + margin
    local bodyY = py + margin + breathe * 0.3
    local drawCy = cy + breathe * 0.3

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + totalCell - margin + 2, bodyW * 0.35, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
    nvgFill(vg)

    -- 身体背景（深色底，防止图片未加载时透明）
    local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
        nvgRGBA(60, 50, 50, 240), nvgRGBA(40, 30, 30, 250))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 头像图片
    local portrait = M.partnerPortraits and M.partnerPortraits[npc.npcKey]
    if portrait and portrait ~= -1 and portrait ~= 0 then
        local imgSize = bodyW * 1.15
        local imgX = cx - imgSize / 2
        local imgY = drawCy - imgSize / 2
        local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
            0, portrait, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 深灰色边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 80, 220))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- NPC 名字（下方）
    local npcInfo = GS.NPC_REGISTRY[npc.npcKey]
    local name = (npcInfo and GS.knownNPCs[npc.npcKey]) and npcInfo.name or "？？？"
    local nameSize = math.max(9, totalCell * 0.24)
    local nameY = bodyY + bodyH
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, nameSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 文字描边
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    local outOff = 1
    for _, off in ipairs({{outOff,0},{-outOff,0},{0,outOff},{0,-outOff}}) do
        nvgText(vg, cx + off[1], nameY + off[2], name, nil)
    end
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, cx, nameY, name, nil)

    -- 睡眠动画："睡眠中zZ" 浮动文本
    if npc.state == "sleeping" then
        local topY = bodyY + bodyH * 0.15
        local bob = math.sin(time * 1.8) * 4
        local baseSize = math.max(13, totalCell * 0.32)
        -- "睡眠中"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, baseSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        local txtY = topY + bob
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
        for _, off in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            nvgText(vg, cx + off[1], txtY + off[2], "睡眠中", nil)
        end
        nvgFillColor(vg, nvgRGBA(200, 210, 255, 220))
        nvgText(vg, cx, txtY, "睡眠中", nil)
        -- "z Z" 飘起气泡
        local zCycle = (time * 0.8) % 1.0
        for zi = 0, 2 do
            local zPhase = (zCycle + zi * 0.33) % 1.0
            local zAlpha = math.floor(200 * (1 - zPhase))
            local zSize = baseSize * (0.5 + zPhase * 0.6)
            local zOffX = 8 + zi * 6
            local zOffY = -zPhase * totalCell * 0.6
            nvgFontSize(vg, zSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(zAlpha * 0.5)))
            nvgText(vg, cx + zOffX + 1, txtY + zOffY + 1, "z", nil)
            nvgFillColor(vg, nvgRGBA(180, 200, 255, zAlpha))
            nvgText(vg, cx + zOffX, txtY + zOffY, "z", nil)
        end
    end
end

-- ====================================================================
-- 绘制：所有单位
-- ====================================================================
function M.drawUnits()
    local vg = M.vg
    local time = GetTime():GetElapsedTime()

    -- 深渊二层毒雾（四角区域，在所有单位下方绘制）
    if GS.getAbyssFloorIndex() == 2 then
        M.drawCornerPoisonFog(time)
    end

    -- 深渊三层毒雾（外两圈常驻绿色毒雾，在所有单位下方绘制）
    if GS.getAbyssFloorIndex() == 3 then
        M.drawPoisonFog(time)
    end

    -- 燃烧地面（在所有单位下方绘制）
    for _, bg in ipairs(GS.burningGrounds) do
        M.drawBurningGround(bg, time)
    end

    -- 暴风雪区域（在所有单位下方绘制）
    for _, bz in ipairs(GS.blizzardZones) do
        M.drawBlizzardZone(bz, time)
    end

    -- 夸迪引雷标记：仅在目标格中心画一个金色圆点（脉动）
    if #GS.lightningWarnings > 0 then
        local cell = GS.CELL
        for _, w in ipairs(GS.lightningWarnings) do
            local ccx = GS.BOARD_X + (w.x - 1) * cell + cell / 2
            local ccy = GS.BOARD_Y + (w.y - 1) * cell + cell / 2
            local pulse = (math.sin(time * 4.0 + w.x * 3.7 + w.y * 5.3) + 1) * 0.5
            local dotR = cell * 0.12 + cell * 0.04 * pulse
            local dotAlpha = math.floor(160 + 80 * pulse)
            nvgBeginPath(vg)
            nvgCircle(vg, ccx, ccy, dotR)
            nvgFillColor(vg, nvgRGBA(255, 210, 50, dotAlpha))
            nvgFill(vg)
        end
    end

    -- 火史莱姆精锐尸体（在单位下方绘制，保留自身外观 + 发红发光效果）
    for _, corpse in ipairs(GS.fireCorpses) do
        local cx = GS.BOARD_X + (corpse.x - 1) * GS.CELL + GS.CELL / 2
        local cy = GS.BOARD_Y + (corpse.y - 1) * GS.CELL + GS.CELL / 2
        local margin = GS.CELL * 0.10
        local bodyW = GS.CELL - margin * 2
        local cornerR = GS.CELL * 0.22
        local bodyX = cx - bodyW / 2
        local bodyY = cy - bodyW / 2

        -- 脉动闪烁
        local pulse = 0.5 + 0.5 * math.sin(time * 4)

        -- 外层火焰光晕（较大的模糊圈）
        local glowR = bodyW * 0.85
        local glowAlpha = math.floor(50 + 40 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, glowR)
        nvgFillColor(vg, nvgRGBA(255, 80, 20, glowAlpha))
        nvgFill(vg)

        -- 绘制怪物自身图片
        local corpseImg = -1
        if corpse.image then
            corpseImg = ImageManager.lazyGet("monster", corpse.image)
        end
        if corpseImg ~= -1 then
            local imgSize = bodyW * 1.15
            local imgX = cx - imgSize / 2
            local imgY = cy - imgSize / 2
            local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
                0, corpseImg, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            -- 无图片时回退到色块
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
            nvgFillColor(vg, nvgRGBA(corpse.color[1], corpse.color[2], corpse.color[3], 200))
            nvgFill(vg)
        end

        -- 发红发亮叠加层（在图片上方）
        local redAlpha = math.floor(100 + 80 * pulse)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
        nvgFillColor(vg, nvgRGBA(255, 30, 10, redAlpha))
        nvgFill(vg)

        -- 边框发光
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
        nvgStrokeColor(vg, nvgRGBA(255, 120, 40, math.floor(160 + 60 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 倒计时文字（已隐藏）
        -- nvgFontFace(vg, "sans")
        -- nvgFontSize(vg, GS.CELL * 0.28)
        -- nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- nvgFillColor(vg, nvgRGBA(255, 220, 100, 230))
        -- nvgText(vg, cx, cy, corpse.turns .. "T", nil)

        -- 危险标记：闪烁的爆炸范围指示（周围8格）
        if corpse.turns <= 1 then
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        local wx = GS.BOARD_X + (corpse.x + dx - 1) * GS.CELL
                        local wy = GS.BOARD_Y + (corpse.y + dy - 1) * GS.CELL
                        if corpse.x + dx >= 1 and corpse.x + dx <= GS.BOARD_SIZE
                           and corpse.y + dy >= 1 and corpse.y + dy <= GS.BOARD_SIZE then
                            nvgBeginPath(vg)
                            nvgRect(vg, wx, wy, GS.CELL, GS.CELL)
                            nvgFillColor(vg, nvgRGBA(255, 60, 20, math.floor(30 + 25 * pulse)))
                            nvgFill(vg)
                        end
                    end
                end
            end
        end
    end

    if GS.player and GS.player.hp > 0 and not GS.player.blinkHidden then
        local pAlpha = GS.player.drawAlpha
        if pAlpha and pAlpha <= 0 then
            -- 完全透明，跳过绘制
        elseif pAlpha and pAlpha < 1 then
            nvgSave(vg)
            nvgGlobalAlpha(vg, pAlpha)
            M.drawPlayer(GS.player, time)
            nvgRestore(vg)
        else
            M.drawPlayer(GS.player, time)
        end
        -- 睡眠浮动文本 "睡眠中zZ"
        if GS.homeMode and GS.isPlayerOnBed() and (GS.bedTimeAccum or 0) > 3 and not GS.homePartnerTalkActive then
            local p = GS.player
            local px = GS.BOARD_X + (p.x - 1) * GS.CELL
            local py = GS.BOARD_Y + (p.y - 1) * GS.CELL
            local cx = px + GS.CELL / 2
            local topY = py + GS.CELL * 0.15
            -- 上下浮动
            local bob = math.sin(time * 1.8) * 4
            local baseSize = math.max(13, GS.CELL * 0.32)
            -- "睡眠中" 主文本
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, baseSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            local txtY = topY + bob
            -- 描边
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
            for _, off in ipairs(OFFSETS_4) do
                nvgText(vg, cx + off[1], txtY + off[2], "睡眠中", nil)
            end
            nvgFillColor(vg, nvgRGBA(200, 210, 255, 220))
            nvgText(vg, cx, txtY, "睡眠中", nil)
            -- "z Z" 逐渐飘起的气泡字，循环动画
            local zCycle = (time * 0.8) % 1.0  -- 0~1 循环
            for zi = 0, 2 do
                local zPhase = (zCycle + zi * 0.33) % 1.0
                local zAlpha = math.floor(200 * (1 - zPhase))
                local zSize = baseSize * (0.5 + zPhase * 0.6)
                local zOffX = 8 + zi * 6
                local zOffY = -zPhase * GS.CELL * 0.6
                nvgFontSize(vg, zSize)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(zAlpha * 0.5)))
                nvgText(vg, cx + zOffX + 1, txtY + zOffY + 1, "z", nil)
                nvgFillColor(vg, nvgRGBA(180, 200, 255, zAlpha))
                nvgText(vg, cx + zOffX, txtY + zOffY, "z", nil)
            end
        end

    end

    -- 绘制家中伴侣NPC
    if GS.homeMode and GS.homeNpc then
        local npcAlpha = GS.homeNpc.drawAlpha
        if npcAlpha and npcAlpha <= 0 then
            -- 完全透明，跳过
        elseif npcAlpha and npcAlpha < 1 then
            nvgSave(vg)
            nvgGlobalAlpha(vg, npcAlpha)
            M.drawHomeNpc(GS.homeNpc, time)
            nvgRestore(vg)
        else
            M.drawHomeNpc(GS.homeNpc, time)
        end
    end

    -- 绘制家中猎犬
    if GS.homeMode and GS.homeHound then
        M.drawHomeHound(GS.homeHound, time)
    end

    local enragedKing = nil
    for _, m in ipairs(GS.monsters) do
        -- 暴怒史莱姆王延后绘制，确保覆盖在被踩踏对象上方
        if m.defId == "slime_king_enraged" then
            enragedKing = m
        else
            -- hp<=0 的怪物仍需绘制，直到 removeDeadMonsters 移除并生成死亡特效
            M.drawMonster(m, time)
        end
    end
    if enragedKing then
        M.drawMonster(enragedKing, time)
    end
    -- 绘制怪物死亡特效
    M.drawDeathEffects()
    -- 绘制幻影消散特效
    M.drawPhantomDissolveEffects()
    -- 绘制玩家复活光芒特效
    M.drawReviveEffect()

    -- 绘制友军（猎犬等）
    for _, c in ipairs(GS.companions) do
        if c.hp > 0 or c.isPhantom then
            local cAlpha = c.drawAlpha
            if cAlpha and cAlpha <= 0 then
                -- 完全透明，跳过绘制
            elseif cAlpha and cAlpha < 1 then
                nvgSave(vg)
                nvgGlobalAlpha(vg, cAlpha)
                M.drawCompanion(c, time)
                nvgRestore(vg)
            else
                M.drawCompanion(c, time)
            end
        end
    end
    -- 绘制圣树
    for _, tree in ipairs(GS.holyTrees) do
        M.drawHolyTree(tree, time)
    end
    -- 绘制冰墙
    for _, wall in ipairs(GS.iceWalls) do
        M.drawIceWall(wall, time)
    end
    -- 绘制采集物（含消失动画更新）
    local dt = GS.dt or 0.016
    for i = #GS.gatherables, 1, -1 do
        local g = GS.gatherables[i]
        if g.vanishing then
            g.vanishTimer = g.vanishTimer + dt
            if g.vanishTimer >= g.vanishDuration then
                table.remove(GS.gatherables, i)
                goto continueGather
            end
        end
        M.drawGatherable(g, time)
        ::continueGather::
    end
    -- 绘制采集进度条
    if GS.gatheringState then
        M.drawGatheringProgressBar()
    end
    -- 绘制家具交互进度条
    if GS.furnitureInteract then
        M.drawFurnitureInteractBar()
    end
    -- 绘制采集结果动画
    if GS.gatherResultAnim then
        M.drawGatherResultAnim()
    end
    -- 绘制雷云（在怪物上方或固定位置）
    for _, tc in ipairs(GS.thunderClouds) do
        if (tc.target and tc.target.hp > 0) or tc.fixedX then
            M.drawThunderCloud(tc, time)
        end
    end
end

-- ====================================================================
-- 绘制：采集物（植物/矿石等可采集单位）
-- ====================================================================
function M.drawGatherable(g, time)
    local vg = M.vg
    local cell = GS.CELL
    local px = GS.BOARD_X + (g.x - 1) * cell
    local py = GS.BOARD_Y + (g.y - 1) * cell
    local cx = px + cell / 2
    local cy = py + cell / 2

    local margin = cell * 0.08
    local bodyW = cell - margin * 2
    local cornerR = cell * 0.18

    -- 消失动画：缩小 + 淡出 + 粒子扩散
    if g.vanishing then
        local t = math.min(1.0, g.vanishTimer / g.vanishDuration)
        local easeT = 1 - (1 - t) * (1 - t)  -- ease-out
        local scale = 1.0 - easeT
        local alpha = math.floor(255 * (1 - easeT))

        -- 缩小的采集物本体
        if scale > 0.01 then
            nvgSave(vg)
            nvgTranslate(vg, cx, cy)
            nvgScale(vg, scale, scale)
            nvgTranslate(vg, -cx, -cy)

            -- 简化绘制：背景 + 图片
            local bodyX = px + margin
            local bodyY = py + margin
            local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyW,
                nvgRGBA(30, 50, 25, alpha), nvgRGBA(20, 35, 18, alpha))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
            nvgFillPaint(vg, bodyGrad)
            nvgFill(vg)

            local gatherImg = -1
            if g.image then
                local cacheKey = "gather_" .. g.defId .. "_" .. (g.areaTag or "default")
                gatherImg = ImageManager.lazyGet(cacheKey, g.image)
            end
            if gatherImg ~= -1 then
                local imgSize = bodyW * 1.15
                local imgX = cx - imgSize / 2
                local imgY = cy - imgSize / 2
                local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize, 0, gatherImg, alpha / 255)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            end
            nvgRestore(vg)
        end

        -- 扩散粒子
        if g.vanishParticles then
            for _, p in ipairs(g.vanishParticles) do
                local dist = p.speed * easeT
                local pAlpha = math.floor(255 * (1 - t))
                local pSize = p.size * (1 - easeT * 0.5)
                local ppx = cx + math.cos(p.angle) * dist
                local ppy = cy + math.sin(p.angle) * dist - easeT * 10
                nvgBeginPath(vg)
                nvgCircle(vg, ppx, ppy, pSize)
                nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, pAlpha))
                nvgFill(vg)
            end
        end
        return
    end

    -- 呼吸动画
    local breathe = math.sin(time * 1.8 + g.x * 1.1 + g.y * 0.9) * 1.5
    local bodyX = px + margin
    local bodyY = py + margin + breathe * 0.3

    -- 正在被采集时的脉动光效
    local isBeingGathered = GS.gatheringState and GS.gatheringState.target == g
    local pulse = math.sin(time * 5) * 0.5 + 0.5

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + cell - margin + 2, bodyW * 0.3, 2.5)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
    nvgFill(vg)

    -- 外发光（颜色跟随稀有度）
    local rarityDef = g.rarity and GS.RARITY[g.rarity]
    local gc = (rarityDef and rarityDef.border) or g.color
    local glowAlpha = isBeingGathered and math.floor(60 + 40 * pulse) or 30
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX - 3, bodyY - 3, bodyW + 6, bodyW + 6, cornerR + 3)
    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], glowAlpha))
    nvgFill(vg)

    -- 身体背景（草绿色渐变）
    local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyW,
        nvgRGBA(30, 50, 25, 230), nvgRGBA(20, 35, 18, 245))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 采集物图片（区域感知缓存 key）
    local gatherImg = -1
    if g.image then
        local cacheKey = "gather_" .. g.defId .. "_" .. (g.areaTag or "default")
        gatherImg = ImageManager.lazyGet(cacheKey, g.image)
    end
    if gatherImg ~= -1 then
        local imgSize = bodyW * 1.15
        local imgX = cx - imgSize / 2
        local imgY = (py + cell / 2 + breathe * 0.3) - imgSize / 2
        local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize, 0, gatherImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 采集中叠加层（闪烁高亮）
    if isBeingGathered then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], math.floor(30 + 30 * pulse)))
        nvgFill(vg)
    end

    -- 边框（绿色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, cornerR)
    local borderAlpha = isBeingGathered and math.floor(180 + 60 * pulse) or 160
    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], borderAlpha))
    nvgStrokeWidth(vg, isBeingGathered and 2.0 or 1.2)
    nvgStroke(vg)

    -- 名称标签（底部）—— 与怪物名字风格保持一致
    local nameSize = math.max(9, cell * 0.24)
    local nameY = bodyY + bodyW
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, nameSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 黑色描边
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    for _, off in ipairs(OFFSETS_4) do
        nvgText(vg, cx + off[1], nameY + off[2], g.name, nil)
    end
    -- 名字颜色跟随稀有度
    local nr, ng, nb = 255, 255, 255
    if rarityDef and rarityDef.color then
        nr, ng, nb = rarityDef.color[1], rarityDef.color[2], rarityDef.color[3]
    end
    nvgFillColor(vg, nvgRGBA(nr, ng, nb, 255))
    nvgText(vg, cx, nameY, g.name, nil)
end

-- ====================================================================
-- 绘制：家具交互进度条（在目标家具上方显示，风格类似采集但无失败）
-- ====================================================================
function M.drawFurnitureInteractBar()
    local vg = M.vg
    local fi = GS.furnitureInteract
    if not fi then return end

    -- 平滑显示进度
    fi._displayProgress = fi._displayProgress or 0
    local targetP = math.min(1.0, fi.progress or 0)
    if fi._displayProgress < targetP then
        fi._displayProgress = math.min(targetP, fi._displayProgress + GS.dt * 2.0)
    end
    local progress = fi._displayProgress

    local cell = GS.CELL
    local fw = fi.furnW or 1
    local fh = fi.furnH or 1
    -- 家具左上角像素坐标
    local fx = GS.BOARD_X + (fi.targetX - (fw - 1) * 0.5 - 1) * cell
    local fy = GS.BOARD_Y + (fi.targetY - (fh - 1) * 0.5 - 1) * cell
    -- 家具像素中心
    local cx = fx + fw * cell / 2

    -- 进度条尺寸（与采集一致）
    local barW = cell * 1.2
    local barH = math.max(6, cell * 0.12)
    local barX = cx - barW / 2
    -- 进度条在家具中间偏上
    local barY = fy + fh * cell * 0.35 - barH / 2

    -- 背景条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, barH / 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 填充条：金色渐变（与采集一致）
    if progress > 0.01 then
        local fillW = barW * progress
        local fillGrad = nvgLinearGradient(vg, barX, barY, barX + barW, barY,
            nvgRGBA(150, 115, 20, 230), nvgRGBA(200, 160, 40, 230))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, fillW, barH, barH / 2)
        nvgFillPaint(vg, fillGrad)
        nvgFill(vg)
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, barH / 2)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 30, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

end

-- ====================================================================
-- 绘制：竞技场绿色出口格子 + 文本提示
-- ====================================================================
function M.drawArenaExitTiles()
    if not GS.arenaWaitForExit or not GS.arenaExitTiles then return end
    local vg = M.vg
    local cell = GS.CELL
    local time = GetTime():GetElapsedTime()
    local pulse = math.sin(time * 3) * 0.15 + 0.85  -- 0.7~1.0 脉冲

    -- 副本通关：显示金色"恭喜您通关！"文本，不再绘制绿色出口格子
    if GS.arenaDungeonCleared then
        local boardPixel = GS.BOARD_SIZE * cell
        -- "恭喜您通关！"共6字，NVG_ALIGN_CENTER居中在第3与第4字之间
        -- 要让第3字"您"落在水平中心，需向右偏移半个字宽
        local fontSize = math.max(14, cell * 0.38)
        local midX = GS.BOARD_X + boardPixel / 2 + fontSize * 0.5
        -- 垂直：出口格子（第1行）的垂直中心
        local midY = GS.BOARD_Y + cell * 0.5
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        for _, off in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
            nvgText(vg, midX + off[1], midY + off[2], "恭喜您通关！", nil)
        end
        -- 金色脉冲文本
        nvgFillColor(vg, nvgRGBA(255, 215, 0, math.floor(255 * pulse)))
        nvgText(vg, midX, midY, "恭喜您通关！", nil)
        return
    end

    for _, tile in ipairs(GS.arenaExitTiles) do
        local px = GS.BOARD_X + (tile.x - 1) * cell
        local py = GS.BOARD_Y + (tile.y - 1) * cell

        -- 绿色高亮格子
        nvgBeginPath(vg)
        nvgRect(vg, px, py, cell, cell)
        nvgFillColor(vg, nvgRGBA(0, 200, 80, math.floor(80 * pulse)))
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRect(vg, px + 1, py + 1, cell - 2, cell - 2)
        nvgStrokeColor(vg, nvgRGBA(0, 255, 100, math.floor(180 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 文本提示（中线对齐格子上边缘）
    local midX = GS.BOARD_X + (6 - 1) * cell + cell  -- (6,1) 和 (7,1) 之间
    local topY = GS.BOARD_Y  -- 第1行格子上边缘
    local fontSize = math.max(11, cell * 0.28)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 描边
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    for _, off in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
        nvgText(vg, midX + off[1], topY + off[2], "移动到此处进入下一关", nil)
    end
    nvgFillColor(vg, nvgRGBA(100, 255, 130, math.floor(255 * pulse)))
    nvgText(vg, midX, topY, "移动到此处进入下一关", nil)
end

-- ====================================================================
-- 绘制：竞技场BOSS宝箱
-- ====================================================================
function M.drawArenaChests()
    GS.arenaChestBtnRects = {}
    if #GS.arenaChests == 0 then return end
    local vg = M.vg
    local cell = GS.CELL
    local time = GetTime():GetElapsedTime()
    local player = GS.player

    for i, chest in ipairs(GS.arenaChests) do
        if not chest.opened then
            local px = GS.BOARD_X + (chest.x - 1) * cell
            local py = GS.BOARD_Y + (chest.y - 1) * cell

            -- 呼吸动画
            local breathe = math.sin(time * 2.0 + chest.x * 1.3) * 1.5

            -- 宝箱图片
            local chestImg = ImageManager.lazyGet("arena_chest", "image/chest_arena.png")
            if chestImg ~= -1 then
                local margin = cell * 0.08
                local bodyW = cell - margin * 2
                local bodyX = px + margin
                local bodyY = py + margin + breathe * 0.3

                local imgPaint = nvgImagePattern(vg, bodyX, bodyY, bodyW, bodyW, 0, chestImg, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, 3)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)

                -- 黑色边框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyW, 3)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 金色光芒脉动
                local glowPulse = math.sin(time * 2.5) * 0.3 + 0.5
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bodyX - 1, bodyY - 1, bodyW + 2, bodyW + 2, 4)
                nvgStrokeColor(vg, nvgRGBA(255, 215, 0, math.floor(100 * glowPulse)))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end

            -- 名字"宝箱"（卓越稀有度颜色，底部显示）
            local nameSize = math.max(9, cell * 0.24)
            local nameCx = px + cell / 2
            local nameY = py + cell - cell * 0.08 + breathe * 0.3
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, nameSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 描边
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
            for _, off in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                nvgText(vg, nameCx + off[1], nameY + off[2], "宝箱", nil)
            end
            -- 卓越稀有度颜色：{255, 185, 15}
            nvgFillColor(vg, nvgRGBA(255, 185, 15, 255))
            nvgText(vg, nameCx, nameY, "宝箱", nil)
        end
    end
end

-- ====================================================================
-- 绘制：竞技场宝箱交互进度条
-- ====================================================================
function M.drawArenaChestInteractBar()
    local vg = M.vg
    local ci = GS.arenaChestInteract
    if not ci then return end

    local chest = GS.arenaChests[ci.chestIdx]
    if not chest then return end

    -- 平滑显示进度
    ci._displayProgress = ci._displayProgress or 0
    local targetP = math.min(1.0, ci.progress or 0)
    if ci._displayProgress < targetP then
        ci._displayProgress = math.min(targetP, ci._displayProgress + GS.dt * 2.0)
    end
    local progress = ci._displayProgress

    local cell = GS.CELL
    local px = GS.BOARD_X + (chest.x - 1) * cell
    local py = GS.BOARD_Y + (chest.y - 1) * cell
    local cx = px + cell / 2

    -- 进度条尺寸
    local barW = cell * 1.2
    local barH = math.max(6, cell * 0.12)
    local barX = cx - barW / 2
    local barY = py - barH - 2

    -- 背景条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, barH / 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 填充条：金色渐变
    if progress > 0.01 then
        local fillW = barW * progress
        local fillGrad = nvgLinearGradient(vg, barX, barY, barX + barW, barY,
            nvgRGBA(150, 115, 20, 230), nvgRGBA(200, 160, 40, 230))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, fillW, barH, barH / 2)
        nvgFillPaint(vg, fillGrad)
        nvgFill(vg)
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, barH / 2)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 30, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

-- ====================================================================
-- 绘制：采集进度条（在采集物上方显示）
-- ====================================================================
function M.drawGatheringProgressBar()
    local vg = M.vg
    local gs = GS.gatheringState
    if not gs then return end
    local target = gs.target
    -- 显示进度平滑追赶实际进度（填充速度随每回合进度比例加快）
    local targetProgress = math.min(1.0, gs.progress or 0)
    gs._displayProgress = gs._displayProgress or 0
    local ppt = gs.progressPerTurn or 0.34
    local fillSpeed = ppt >= 1.0 and 3.0 or (ppt >= 0.50 and 1.5 or 0.8)
    if gs._displayProgress < targetProgress then
        gs._displayProgress = math.min(targetProgress, gs._displayProgress + GS.dt * fillSpeed)
    end
    local progress = gs._displayProgress

    local cell = GS.CELL
    local px = GS.BOARD_X + (target.x - 1) * cell
    local py = GS.BOARD_Y + (target.y - 1) * cell
    local cx = px + cell / 2
    local pScale = GS.pScale or 1

    -- 进度条尺寸
    local barW = cell * 1.2
    local barH = math.max(6, cell * 0.12)
    local barX = cx - barW / 2
    local barY = py - barH - 2

    -- 背景条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, barH / 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 闪烁阶段颜色参数
    local flashPhase = gs._flashPhase
    local flashT = gs._flashTimer or 0
    local r1, g1, b1 = 150, 115, 20   -- 渐变起始色（默认金色）
    local r2, g2, b2 = 200, 160, 40   -- 渐变结束色
    local br, bg, bb = 180, 140, 30   -- 边框色
    local fillAlpha = 230

    if flashPhase then
        if gs._zeroRate then
            -- 等级不足：直接红色满条闪烁（不经过金色阶段）
            r1, g1, b1 = 200, 50, 30
            r2, g2, b2 = 230, 60, 40
            br, bg, bb = 220, 50, 30
            local pulse = math.sin(flashT * 14)
            fillAlpha = math.floor(180 + 75 * pulse)
        else
            -- 颜色渐变插值：金色 → 绿/红
            local blend = math.min(1.0, flashT / 0.25)  -- 0.25秒完成变色
            if gs._result then
                -- 成功：金→绿
                r1 = math.floor(150 + (60 - 150) * blend)
                g1 = math.floor(115 + (200 - 115) * blend)
                b1 = math.floor(20 + (60 - 20) * blend)
                r2 = math.floor(200 + (80 - 200) * blend)
                g2 = math.floor(160 + (230 - 160) * blend)
                b2 = math.floor(40 + (80 - 40) * blend)
                br = math.floor(180 + (60 - 180) * blend)
                bg = math.floor(140 + (210 - 140) * blend)
                bb = math.floor(30 + (60 - 30) * blend)
            else
                -- 失败：金→红
                r1 = math.floor(150 + (200 - 150) * blend)
                g1 = math.floor(115 + (50 - 115) * blend)
                b1 = math.floor(20 + (30 - 20) * blend)
                r2 = math.floor(200 + (230 - 200) * blend)
                g2 = math.floor(160 + (60 - 160) * blend)
                b2 = math.floor(40 + (40 - 40) * blend)
                br = math.floor(180 + (220 - 180) * blend)
                bg = math.floor(140 + (50 - 140) * blend)
                bb = math.floor(30 + (30 - 30) * blend)
            end
            -- 闪烁：变色完成后 alpha 脉冲
            if flashT > 0.25 then
                local pulse = math.sin((flashT - 0.25) * 14)  -- 快速闪烁
                fillAlpha = math.floor(180 + 75 * pulse)
            end
        end
    end

    -- 填充条
    if progress > 0.01 then
        local fillW = barW * progress
        local fillGrad = nvgLinearGradient(vg, barX, barY, barX + barW, barY,
            nvgRGBA(r1, g1, b1, fillAlpha), nvgRGBA(r2, g2, b2, fillAlpha))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, fillW, barH, barH / 2)
        nvgFillPaint(vg, fillGrad)
        nvgFill(vg)
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, barH / 2)
    nvgStrokeColor(vg, nvgRGBA(br, bg, bb, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 进度条上方显示成功率
    if not flashPhase and gs.successRate then
        local ratePct = math.floor(gs.successRate * 100 + 0.5)
        local rateStr = "成功率:" .. ratePct .. "%"
        local fontSize = math.max(10, cell * 0.22)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        -- 描边
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        nvgText(vg, cx, barY - 2, rateStr)
        nvgText(vg, cx + 1, barY - 2, rateStr)
        nvgText(vg, cx - 1, barY - 2, rateStr)
        nvgText(vg, cx, barY - 1, rateStr)
        nvgText(vg, cx, barY - 3, rateStr)
        -- 正文
        local rc, gc, bc = 255, 220, 80
        if ratePct <= 30 then
            rc, gc, bc = 255, 100, 80
        elseif ratePct <= 60 then
            rc, gc, bc = 255, 180, 60
        end
        nvgFillColor(vg, nvgRGBA(rc, gc, bc, 240))
        nvgText(vg, cx, barY - 2, rateStr)
    end
end

-- ====================================================================
-- 绘制：采集结果动画（成功/失败提示）
-- ====================================================================
function M.drawGatherResultAnim()
    local vg = M.vg
    local anim = GS.gatherResultAnim
    if not anim then return end

    local t = safeProgress(anim.timer, anim.duration)
    local alpha = math.floor(255 * (1 - t))
    local rise = t * 30

    local cell = GS.CELL
    local px = GS.BOARD_X + (anim.x - 1) * cell + cell / 2
    local py = GS.BOARD_Y + (anim.y - 1) * cell - rise
    local pScale = GS.pScale or 1

    if anim.success then
        -- 成功：绿色上浮图标 + 物品名
        local itemImg = -1
        if anim.itemId then
            local tpl = GS.itemTemplates[anim.itemId]
            if tpl and tpl.icon then
                itemImg = ImageManager.lazyGet("item_" .. anim.itemId, tpl.icon)
            end
        end
        if itemImg ~= -1 then
            local iconSz = 20 * pScale
            local imgPat = nvgImagePattern(vg, px - iconSz / 2, py - iconSz / 2, iconSz, iconSz, 0, itemImg, alpha / 255)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px - iconSz / 2, py - iconSz / 2, iconSz, iconSz, 3)
            nvgFillPaint(vg, imgPat)
            nvgFill(vg)
            -- "+1" 标签
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 12 * pScale)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(80, 240, 80, alpha))
            nvgText(vg, px + iconSz / 2 + 3, py, "+1", nil)
        end
    end
end

-- ====================================================================
-- 绘制：雷云（多层立体云体+大量粒子+电弧，跟随目标或固定位置）
-- ====================================================================
function M.drawThunderCloud(tc, time)
    local vg = M.vg
    local cell = GS.CELL

    -- 确定雷云中心坐标
    local gx, gy
    if tc.target and tc.target.hp > 0 then
        gx, gy = tc.target.x, tc.target.y
    elseif tc.fixedX then
        gx, gy = tc.fixedX, tc.fixedY
    else
        return
    end

    local cx = GS.BOARD_X + (gx - 1) * cell + cell / 2
    local cy = GS.BOARD_Y + (gy - 1) * cell - cell * 0.8  -- 在怪物上方（抬高云层）

    -- 3×3 作用范围高亮提示
    for dy = -1, 1 do
        for dx = -1, 1 do
            local ax, ay = gx + dx, gy + dy
            if ax >= 1 and ax <= GS.BOARD_SIZE and ay >= 1 and ay <= GS.BOARD_SIZE then
                local apx = GS.BOARD_X + (ax - 1) * cell
                local apy = GS.BOARD_Y + (ay - 1) * cell
                nvgBeginPath(vg)
                nvgRect(vg, apx + 1, apy + 1, cell - 2, cell - 2)
                nvgFillColor(vg, nvgRGBA(255, 220, 40, 18))
                nvgFill(vg)
            end
        end
    end

    -- 云的整体尺寸（覆盖 3×3 区域）
    local cloudW = cell * 2.8
    local cloudH = cell * 1.4  -- 大幅增加纵向高度
    local pulse = (math.sin(time * 2.5) + 1) * 0.5

    -- ① 地面投影
    local groundY = GS.BOARD_Y + (gy - 1) * cell + cell * 0.85
    local groundPaint = nvgRadialGradient(vg, cx, groundY, 0, cloudW * 0.45,
        nvgRGBA(10, 5, 20, 55),
        nvgRGBA(10, 5, 20, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, groundY, cloudW * 0.45, cell * 0.18)
    nvgFillPaint(vg, groundPaint)
    nvgFill(vg)

    -- ② 用多个大小不一、位置交错的圆形团块构成凹凸不平的云体
    -- 定义云团块：{相对x, 相对y, 半径比例, 亮度, 层级(越大越上层)}
    local blobs = {
        -- 底层（最暗，铺底）
        { dx = 0,     dy = 0.2,   rx = 0.48, ry = 0.30, shade = 12, alpha = 170 },
        { dx = -0.15, dy = 0.25,  rx = 0.35, ry = 0.25, shade = 10, alpha = 150 },
        { dx = 0.18,  dy = 0.22,  rx = 0.32, ry = 0.24, shade = 14, alpha = 150 },
        -- 中层（稍亮，主体）
        { dx = -0.08, dy = 0.0,   rx = 0.42, ry = 0.32, shade = 22, alpha = 185 },
        { dx = 0.12,  dy = 0.02,  rx = 0.38, ry = 0.30, shade = 25, alpha = 180 },
        { dx = -0.25, dy = 0.05,  rx = 0.22, ry = 0.24, shade = 28, alpha = 160 },
        { dx = 0.28,  dy = 0.06,  rx = 0.20, ry = 0.22, shade = 26, alpha = 155 },
        -- 上层凸起（更亮，突出的团块，制造凹凸感）
        { dx = -0.12, dy = -0.22, rx = 0.28, ry = 0.26, shade = 38, alpha = 175 },
        { dx = 0.08,  dy = -0.18, rx = 0.32, ry = 0.28, shade = 35, alpha = 180 },
        { dx = -0.30, dy = -0.10, rx = 0.18, ry = 0.20, shade = 40, alpha = 150 },
        { dx = 0.32,  dy = -0.08, rx = 0.16, ry = 0.18, shade = 42, alpha = 145 },
        -- 顶部小凸起（最亮，受光面）
        { dx = -0.05, dy = -0.38, rx = 0.20, ry = 0.18, shade = 52, alpha = 155 },
        { dx = 0.15,  dy = -0.32, rx = 0.16, ry = 0.15, shade = 55, alpha = 140 },
        { dx = -0.22, dy = -0.28, rx = 0.14, ry = 0.14, shade = 48, alpha = 135 },
    }

    for i, b in ipairs(blobs) do
        local bx = cx + b.dx * cloudW
        local by = cy + b.dy * cloudH
        -- 微微浮动，每个团块有自己的节奏
        by = by + cell * 0.02 * math.sin(time * (1.2 + i * 0.15) + i * 1.7)
        bx = bx + cell * 0.01 * math.sin(time * (0.8 + i * 0.1) + i * 2.3)
        local brx = b.rx * cloudW
        local bry = b.ry * cloudH
        local bPaint = nvgRadialGradient(vg, bx, by, brx * 0.15, brx,
            nvgRGBA(b.shade, b.shade - 2, b.shade + 8, b.alpha),
            nvgRGBA(b.shade - 5, b.shade - 5, b.shade, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, bx, by, brx, bry)
        nvgFillPaint(vg, bPaint)
        nvgFill(vg)
    end

    -- ③ 大量粒子填充云体纹理（分布在整个云体高度范围内）
    local particleCount = 55
    for k = 1, particleCount do
        local seed = k * 137.508
        local angle = math.rad(seed) + time * (0.12 + (k % 4) * 0.05)
        -- 椭圆分布，纵向范围大
        local distX = cloudW * 0.42 * (0.2 + ((seed * 3.7) % 1.0) * 0.8)
        local distY = cloudH * 0.40 * (0.15 + ((seed * 5.3) % 1.0) * 0.85)
        local px = cx + math.cos(angle) * distX
        local py = cy + math.sin(angle) * distY
        py = py + cell * 0.03 * math.sin(time * 1.6 + k * 0.7)

        local pr = cell * (0.03 + 0.035 * ((seed * 2.1) % 1.0))
        local pPulse = (math.sin(time * 2.5 + k * 1.1) + 1) * 0.5

        -- 上方粒子偏亮，下方偏暗（模拟光照）
        local heightFactor = 1.0 - ((py - (cy - cloudH * 0.4)) / (cloudH * 0.8))
        heightFactor = math.max(0, math.min(1, heightFactor))
        local baseShade = math.floor(10 + 35 * heightFactor + 10 * ((seed * 1.3) % 1.0))

        local isElectric = (k % 7 == 0)
        local cr, cg, cb, ca
        if isElectric then
            if k % 14 == 0 then
                cr = math.floor(160 + 80 * pPulse)
                cg = math.floor(100 + 80 * pPulse)
                cb = 255
                ca = math.floor(80 + 100 * pPulse)
            else
                cr = 255
                cg = math.floor(210 + 40 * pPulse)
                cb = math.floor(40 + 50 * pPulse)
                ca = math.floor(80 + 100 * pPulse)
            end
        else
            cr = baseShade
            cg = baseShade
            cb = baseShade + math.floor(8 * pPulse)
            ca = math.floor(130 + 60 * pPulse)
        end

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pr + cell * 0.006 * pPulse)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, ca))
        nvgFill(vg)
    end

    -- ④ 云底部翻涌粒子（从云底下沉再回升）
    for k = 1, 12 do
        local seed = k * 61.7
        local phase = (time * 0.5 + seed * 0.01) % 1.0
        local spreadX = cloudW * 0.35 * math.sin(seed * 2.3)
        local px = cx + spreadX * (0.3 + 0.7 * math.sin(time * 0.4 + k))
        local dropDist = cell * 0.25 * math.sin(phase * 3.14159)
        local py = cy + cloudH * 0.35 + dropDist
        local pr = cell * (0.022 + 0.018 * phase)
        local ca = math.floor(90 * (1.0 - phase * 0.5))

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pr)
        nvgFillColor(vg, nvgRGBA(18, 14, 28, ca))
        nvgFill(vg)
    end

    -- ⑤ 云体内部电弧
    local arcCount = 6
    for k = 1, arcCount do
        local seed = k * 97.3
        local arcPhase = (time * (3.5 + k * 0.6) + seed) % 2.0
        if arcPhase < 0.1 or (arcPhase > 0.8 and arcPhase < 0.88) or (arcPhase > 1.5 and arcPhase < 1.56) then
            local startA = math.rad(seed + time * 35)
            local sx = cx + math.cos(startA) * cloudW * 0.22
            local sy = cy + math.sin(startA) * cloudH * 0.2
            local endA = startA + math.rad(50 + ((seed * 1.7) % 1.0) * 90)
            local ex = cx + math.cos(endA) * cloudW * 0.28
            local ey = cy + math.sin(endA) * cloudH * 0.25

            local mx1 = sx + (ex - sx) * 0.33 + cell * 0.05 * math.sin(time * 25 + k)
            local my1 = sy + (ey - sy) * 0.33 + cell * 0.04 * math.cos(time * 18 + k * 2)
            local mx2 = sx + (ex - sx) * 0.66 + cell * 0.04 * math.cos(time * 22 + k * 3)
            local my2 = sy + (ey - sy) * 0.66 + cell * 0.05 * math.sin(time * 20 + k)

            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy)
            nvgLineTo(vg, mx1, my1)
            nvgLineTo(vg, mx2, my2)
            nvgLineTo(vg, ex, ey)
            nvgStrokeWidth(vg, cell * 0.022)
            nvgStrokeColor(vg, nvgRGBA(255, 240, 80, math.floor(160 + 80 * pulse)))
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy)
            nvgLineTo(vg, mx1, my1)
            nvgLineTo(vg, mx2, my2)
            nvgLineTo(vg, ex, ey)
            nvgStrokeWidth(vg, cell * 0.008)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgStroke(vg)
        end
    end

    -- ⑥ 云底部闪光脉冲
    local flashPhase = (time * 5.0 + gx * 2.3) % 2.0
    if flashPhase < 0.12 then
        local flashT = flashPhase / 0.12
        local flashA = math.floor(100 * (1.0 - flashT))
        local flashPaint = nvgRadialGradient(vg, cx, cy + cloudH * 0.3, 0, cloudW * 0.4,
            nvgRGBA(255, 235, 120, flashA),
            nvgRGBA(200, 180, 60, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, cx, cy + cloudH * 0.3, cloudW * 0.4, cloudH * 0.25)
        nvgFillPaint(vg, flashPaint)
        nvgFill(vg)
    end
    local flashPhase2 = (time * 4.2 + gx * 3.1 + 0.7) % 2.5
    if flashPhase2 < 0.1 then
        local flashT2 = flashPhase2 / 0.1
        local flashA2 = math.floor(70 * (1.0 - flashT2))
        local fOff = cloudW * 0.12 * math.sin(time * 1.5)
        local flashPaint2 = nvgRadialGradient(vg, cx + fOff, cy + cloudH * 0.15, 0, cloudW * 0.25,
            nvgRGBA(200, 180, 255, flashA2),
            nvgRGBA(120, 100, 200, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, cx + fOff, cy + cloudH * 0.15, cloudW * 0.25, cloudH * 0.2)
        nvgFillPaint(vg, flashPaint2)
        nvgFill(vg)
    end

    -- ⑦ 云底悬垂雾丝
    for k = 1, 6 do
        local seed = k * 47.7
        local wx = cx + cloudW * 0.25 * math.sin(seed + time * 0.6)
        local wy1 = cy + cloudH * 0.35
        local wy2 = wy1 + cell * (0.18 + 0.08 * math.sin(time * 1.2 + k))
        nvgBeginPath(vg)
        nvgMoveTo(vg, wx, wy1)
        local midWx = wx + cell * 0.03 * math.sin(time * 2.5 + k * 1.5)
        nvgQuadTo(vg, midWx, (wy1 + wy2) * 0.5, wx + cell * 0.01 * math.sin(time * 1.8 + k), wy2)
        nvgStrokeWidth(vg, cell * (0.015 + 0.008 * math.sin(time + k)))
        nvgStrokeColor(vg, nvgRGBA(20, 15, 30, math.floor(50 + 30 * pulse)))
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    end

    -- ⑧ 顶部高光（受光面边缘亮带）
    local highlightPaint = nvgRadialGradient(vg, cx - cloudW * 0.06, cy - cloudH * 0.38, cloudW * 0.02, cloudW * 0.18,
        nvgRGBA(85, 75, 105, math.floor(50 + 20 * pulse)),
        nvgRGBA(50, 40, 65, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, cx - cloudW * 0.06, cy - cloudH * 0.38, cloudW * 0.2, cloudH * 0.12)
    nvgFillPaint(vg, highlightPaint)
    nvgFill(vg)
end

-- ====================================================================
-- 绘制：深渊二层毒雾（四角曼哈顿距离≤2 常驻绿色毒雾）
-- ====================================================================
function M.drawCornerPoisonFog(time)
    local vg = M.vg
    local cell = GS.CELL
    local bx, by = GS.BOARD_X, GS.BOARD_Y
    local bs = GS.BOARD_SIZE

    local corners = {{1,1},{bs,1},{1,bs},{bs,bs}}
    for y = 1, bs do
        for x = 1, bs do
            local inFog = false
            for _, c in ipairs(corners) do
                if math.abs(x - c[1]) + math.abs(y - c[2]) <= 2 then
                    inFog = true
                    break
                end
            end
            if inFog then
                local px = bx + (x - 1) * cell
                local py = by + (y - 1) * cell
                local cx = px + cell / 2
                local cy = py + cell / 2

                -- 离最近角的曼哈顿距离，用于浓度衰减
                local minDist = bs
                for _, c in ipairs(corners) do
                    local d = math.abs(x - c[1]) + math.abs(y - c[2])
                    if d < minDist then minDist = d end
                end

                local phase = x * 1.7 + y * 2.3
                -- 角上(dist=0)最浓，dist=1较浓，dist=2最淡
                local baseAlpha = minDist == 0 and 60 or (minDist == 1 and 45 or 30)
                local pulse = math.sin(time * 1.2 + phase) * 0.3 + 0.7
                local alpha = math.floor(baseAlpha * pulse)

                -- 底色渲染
                nvgBeginPath(vg)
                nvgRect(vg, px, py, cell, cell)
                nvgFillColor(vg, nvgRGBA(40, 140, 30, alpha))
                nvgFill(vg)

                -- 雾气团（径向渐变）
                local fogR = cell * (0.5 + 0.1 * math.sin(time * 0.8 + phase * 0.5))
                local fogPaint = nvgRadialGradient(vg, cx, cy, fogR * 0.2, fogR,
                    nvgRGBA(60, 180, 50, math.floor(alpha * 0.8)),
                    nvgRGBA(40, 120, 30, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy, fogR)
                nvgFillPaint(vg, fogPaint)
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：深渊三层毒雾（外两圈常驻绿色毒雾）
-- ====================================================================
function M.drawPoisonFog(time)
    local vg = M.vg
    local cell = GS.CELL
    local bx, by = GS.BOARD_X, GS.BOARD_Y
    local bs = GS.BOARD_SIZE

    for y = 1, bs do
        for x = 1, bs do
            local edgeDist = math.min(x - 1, bs - x, y - 1, bs - y)
            if edgeDist < 2 then
                local px = bx + (x - 1) * cell
                local py = by + (y - 1) * cell
                local cx = px + cell / 2
                local cy = py + cell / 2

                -- 每格独有相位，产生流动感
                local phase = x * 1.7 + y * 2.3
                -- 外圈(edgeDist=0)更浓，内圈(edgeDist=1)较淡
                local baseAlpha = edgeDist == 0 and 55 or 35
                local pulse = math.sin(time * 1.2 + phase) * 0.3 + 0.7
                local alpha = math.floor(baseAlpha * pulse)

                -- 底色渲染
                nvgBeginPath(vg)
                nvgRect(vg, px, py, cell, cell)
                nvgFillColor(vg, nvgRGBA(40, 140, 30, alpha))
                nvgFill(vg)

                -- 雾气团（径向渐变，从中心向外扩散）
                local fogR = cell * (0.5 + 0.1 * math.sin(time * 0.8 + phase * 0.5))
                local fogPaint = nvgRadialGradient(vg, cx, cy, fogR * 0.2, fogR,
                    nvgRGBA(60, 180, 50, math.floor(alpha * 0.8)),
                    nvgRGBA(40, 120, 30, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy, fogR)
                nvgFillPaint(vg, fogPaint)
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制：暴风雪区域（蓝色光圈 + 密集寒气粒子）
-- ====================================================================
function M.drawBlizzardZone(bz, time)
    local vg = M.vg
    local cell = GS.CELL
    local radius = bz.radius or 2

    -- 区域中心像素坐标
    local ccx = GS.BOARD_X + (bz.cx - 1) * cell + cell / 2
    local ccy = GS.BOARD_Y + (bz.cy - 1) * cell + cell / 2
    -- 区域像素半径（菱形半径转圆形近似）
    local pixR = (radius + 0.6) * cell

    -- ① 区域内冰蓝半透明底色（柔和径向渐变）
    local basePulse = (math.sin(time * 2.0) + 1) * 0.5
    local baseAlpha = math.floor(22 + 18 * basePulse)
    local basePaint = nvgRadialGradient(vg, ccx, ccy, pixR * 0.1, pixR,
        nvgRGBA(50, 130, 255, baseAlpha + 15),
        nvgRGBA(30, 80, 220, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, ccx, ccy, pixR)
    nvgFillPaint(vg, basePaint)
    nvgFill(vg)

    -- ② 蓝色光圈边界（双层发光描边）
    local ringPulse = (math.sin(time * 3.0 + 1.0) + 1) * 0.5
    -- 外层柔光
    nvgBeginPath(vg)
    nvgCircle(vg, ccx, ccy, pixR)
    nvgStrokeWidth(vg, cell * 0.12)
    nvgStrokeColor(vg, nvgRGBA(60, 150, 255, math.floor(35 + 25 * ringPulse)))
    nvgStroke(vg)
    -- 内层亮线
    nvgBeginPath(vg)
    nvgCircle(vg, ccx, ccy, pixR)
    nvgStrokeWidth(vg, cell * 0.04)
    nvgStrokeColor(vg, nvgRGBA(120, 200, 255, math.floor(120 + 60 * ringPulse)))
    nvgStroke(vg)

    -- ③ 密集寒气粒子（在区域内飘动）
    local particleCount = math.max(12, radius * 8)
    for k = 1, particleCount do
        local seed = k * 137.508
        -- 极坐标分布（随时间缓慢旋转漂移）
        local baseAngle = math.rad(seed) + time * (0.3 + (k % 3) * 0.15)
        local baseDist = pixR * (0.15 + ((seed * 7.3) % 1.0) * 0.75)
        -- 添加上下浮动
        local floatY = cell * 0.12 * math.sin(time * 2.5 + k * 0.8)
        local px = ccx + math.cos(baseAngle) * baseDist
        local py = ccy + math.sin(baseAngle) * baseDist + floatY

        -- 粒子大小和透明度随脉冲变化
        local pPulse = (math.sin(time * 3.0 + k * 1.3) + 1) * 0.5
        local pr = cell * (0.03 + 0.025 * pPulse)
        local pa = math.floor(80 + 70 * pPulse)
        -- 颜色在冰蓝和白之间变化
        local cr = math.floor(140 + 80 * pPulse)
        local cg = math.floor(200 + 40 * pPulse)

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pr)
        nvgFillColor(vg, nvgRGBA(cr, cg, 255, pa))
        nvgFill(vg)
    end

    -- ④ 寒气雾带（几条缓慢飘动的弧线模拟风雪流）
    for k = 1, 3 do
        local arcAngle = time * 0.6 + k * 2.094  -- 120度间隔
        local arcR = pixR * (0.4 + 0.2 * math.sin(time * 1.2 + k))
        local arcCx = ccx + math.cos(arcAngle) * arcR * 0.3
        local arcCy = ccy + math.sin(arcAngle) * arcR * 0.3
        local arcLen = math.pi * 0.6
        local segments = 8
        nvgBeginPath(vg)
        for s = 0, segments do
            local t = s / segments
            local a = arcAngle - arcLen / 2 + arcLen * t
            local r = arcR + cell * 0.15 * math.sin(t * math.pi * 2 + time * 3)
            local sx = arcCx + math.cos(a) * r
            local sy = arcCy + math.sin(a) * r
            if s == 0 then
                nvgMoveTo(vg, sx, sy)
            else
                nvgLineTo(vg, sx, sy)
            end
        end
        local fogAlpha = math.floor(30 + 20 * math.sin(time * 2 + k * 1.5))
        nvgStrokeWidth(vg, cell * 0.06)
        nvgStrokeColor(vg, nvgRGBA(160, 210, 255, fogAlpha))
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    end

end

-- ====================================================================
-- 绘制：燃烧地面
-- ====================================================================
function M.drawBurningGround(bg, time)
    local vg = M.vg
    local px = GS.BOARD_X + (bg.x - 1) * GS.CELL
    local py = GS.BOARD_Y + (bg.y - 1) * GS.CELL
    local cell = GS.CELL
    local cx = px + cell / 2
    local cy = py + cell / 2
    local seed = bg.x * 7.3 + bg.y * 13.7

    -- ① 地面熔岩底色（2层径向渐变）
    local pulse1 = (math.sin(time * 2.5 + seed) + 1) * 0.5
    local pulse2 = (math.sin(time * 3.8 + seed * 1.7) + 1) * 0.5
    -- 外层暗红光晕
    local glow1 = nvgRadialGradient(vg, cx, cy, cell * 0.05, cell * 0.6,
        nvgRGBA(200, 40, 0, math.floor(60 + 30 * pulse1)),
        nvgRGBA(120, 20, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, px, py, cell, cell)
    nvgFillPaint(vg, glow1)
    nvgFill(vg)
    -- 内层橙黄炽热核心
    local coreOx = math.sin(time * 1.3 + seed) * cell * 0.08
    local coreOy = math.cos(time * 1.7 + seed) * cell * 0.06
    local glow2 = nvgRadialGradient(vg, cx + coreOx, cy + coreOy, cell * 0.02, cell * 0.35,
        nvgRGBA(255, 180, 40, math.floor(70 + 40 * pulse2)),
        nvgRGBA(255, 80, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, px, py, cell, cell)
    nvgFillPaint(vg, glow2)
    nvgFill(vg)

    -- ② 熔岩裂纹（3条合并为单个路径）
    local crackA = math.floor(90 + 60 * pulse1)
    nvgBeginPath(vg)
    for k = 1, 3 do
        local kseed = seed + k * 3.17
        local x1 = cx + math.sin(kseed * 1.7) * cell * 0.38
        local y1 = cy + math.cos(kseed * 2.3) * cell * 0.35
        local x2 = cx + math.sin(kseed * 3.1) * cell * 0.36
        local y2 = cy + math.cos(kseed * 2.7) * cell * 0.38
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 200, 60, crackA))
    nvgStrokeWidth(vg, 0.6 + 0.4 * pulse1)
    nvgStroke(vg)

    -- ③ 火星粒子（6颗，合并同色粒子为单个路径）
    nvgBeginPath(vg)
    local sparkVisible = 0
    for k = 1, 6 do
        local kseed = seed + k * 2.13
        local phase = (time * 5 + kseed) % 1.0
        local sparkX = cx + math.sin(kseed * 2.3) * cell * 0.4
        local sparkY = cy + math.cos(kseed * 1.9) * cell * 0.38
        sparkY = sparkY - phase * cell * 0.06
        local sparkR = cell * (0.014 + 0.010 * (1 - phase))
        nvgCircle(vg, sparkX, sparkY, sparkR)
        sparkVisible = sparkVisible + 1
    end
    if sparkVisible > 0 then
        nvgFillColor(vg, nvgRGBA(255, 200, 30, 180))
        nvgFill(vg)
    end

    -- ④ 升腾火焰粒子（8颗，略增大半径补偿密度）
    for k = 1, 8 do
        local kseed = seed + k * 1.37
        local period = 1.0 + (kseed % 100) / 100
        local life = ((time + kseed) % period) / period
        local baseX = px + cell * (0.08 + (kseed * 17 % 84) / 100)
        local swayX = math.sin(time * 3 + kseed) * cell * 0.04 * life
        local fx = baseX + swayX
        local fy = py + cell * (0.9 - life * 1.1)
        local fr = cell * (0.030 + 0.022 * (1 - life))
        local fadeIn = math.min(1, life * 5)
        local fadeOut = math.max(0, 1 - (life - 0.4) / 0.6)
        local fa = math.floor(170 * fadeIn * fadeOut)
        if fa > 2 then
            local g = math.floor(220 - 180 * life)
            local b = math.floor(60 - 50 * life)
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, fr)
            nvgFillColor(vg, nvgRGBA(255, g, b, fa))
            nvgFill(vg)
        end
    end

    -- ⑤ 偶发大火花（2颗，带外发光）
    for k = 1, 2 do
        local kseed = seed + k * 11.3
        local period = 2.5 + (kseed % 50) / 50
        local life = ((time + kseed) % period) / period
        local baseX = cx + math.sin(kseed) * cell * 0.25
        local swayX = math.sin(time * 2 + kseed) * cell * 0.08 * life
        local fx = baseX + swayX
        local fy = py + cell * (0.85 - life * 1.2)
        local fr = cell * (0.032 + 0.020 * (1 - life))
        local fadeOut = math.max(0, 1 - life / 0.8)
        local fa = math.floor(210 * fadeOut)
        if fa > 5 then
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, fr * 2.2)
            nvgFillColor(vg, nvgRGBA(255, 160, 30, math.floor(fa * 0.2)))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, fr)
            nvgFillColor(vg, nvgRGBA(255, 240, 100, fa))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 绘制：冰墙
-- ====================================================================
function M.drawIceWall(wall, time)
    local vg = M.vg
    local totalCell = GS.CELL
    local margin = totalCell * 0.10
    local bodyW = totalCell - margin * 2
    local bodyH = bodyW
    local cornerR = totalCell * 0.22

    local px = GS.BOARD_X + (wall.x - 1) * totalCell
    local py = GS.BOARD_Y + (wall.y - 1) * totalCell
    local cx = px + totalCell / 2
    local cy = py + totalCell / 2
    local bodyX = px + margin
    local bodyY = py + margin

    -- 冰冻光圈（半透明蓝色）
    local rangeRadius = 1.5 * totalCell
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, rangeRadius)
    nvgFillColor(vg, nvgRGBA(60, 140, 220, 15))
    nvgFill(vg)

    -- 呼吸动画
    local breathe = math.sin(time * 1.5 + wall.x * 0.5) * 1.5
    local drawCy = cy + breathe * 0.3

    -- 阴影
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, py + totalCell - margin + 2, bodyW * 0.35, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)

    -- 外发光光晕（冰蓝色）
    local glow = math.sin(time * 3.0) * 0.3 + 0.7
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX - 3, bodyY - 3, bodyW + 6, bodyH + 6, cornerR + 3)
    nvgFillColor(vg, nvgRGBA(100, 180, 255, math.floor(50 * glow)))
    nvgFill(vg)

    -- 身体背景（深蓝色）
    local bodyGrad = nvgLinearGradient(vg, bodyX, bodyY, bodyX, bodyY + bodyH,
        nvgRGBA(20, 40, 70, 240), nvgRGBA(10, 25, 50, 250))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 冰墙图片
    local wallImg = -1
    if wall.image then
        wallImg = ImageManager.lazyGet("icewall", wall.image)
    end
    if wallImg ~= -1 then
        local imgSize = bodyW * 1.15
        local imgX = cx - imgSize / 2
        local imgY = drawCy - imgSize / 2
        local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
            0, wallImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 冰蓝色边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bodyX, bodyY, bodyW, bodyH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 220))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- HP 条（冰蓝色）
    local barW = bodyW * 0.8
    local barH = math.max(3, totalCell * 0.06)
    local barX = px + (totalCell - barW) / 2
    local barY = bodyY - barH

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    local hpRatio = math.max(0, math.min(1, wall.hitsLeft / math.max(1, wall.maxHp)))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 2)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
    nvgFill(vg)

    -- 剩余回合数（已隐藏）
    -- local infoText = wall.turnsLeft .. "T"
    -- nvgFontFace(vg, "sans")
    -- nvgFontSize(vg, math.max(8, totalCell * 0.18))
    -- nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    -- nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    -- nvgText(vg, cx + 1, barY - 1, infoText, nil)
    -- nvgFillColor(vg, nvgRGBA(180, 230, 255, 255))
    -- nvgText(vg, cx, barY - 1, infoText, nil)

    -- 火焰护盾（橙红色燃烧护罩 + 大量逃逸火焰粒子，与玩家完全一致）
    if wall.fireShieldTurns and wall.fireShieldTurns > 0 then
        local shieldR = bodyW * 0.6
        local pulse = (math.sin(time * 4.0) + 1) * 0.5
        local flicker = (math.sin(time * 11.3) + math.sin(time * 17.7)) * 0.25 + 0.5

        -- 第1层：外层橙红色半透明球罩（燃烧底色）
        local baseAlpha = math.floor(35 + 30 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgFillColor(vg, nvgRGBA(220, 80, 20, baseAlpha))
        nvgFill(vg)

        -- 第2层：内层径向渐变（中心暗红 → 边缘亮橙，模拟内焰）
        local innerGlow = nvgRadialGradient(vg, cx, drawCy, shieldR * 0.3, shieldR,
            nvgRGBA(180, 40, 10, 0),
            nvgRGBA(255, 120, 30, math.floor(60 + 40 * flicker)))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgFillPaint(vg, innerGlow)
        nvgFill(vg)

        -- 第3层：边缘发光描边（明亮的橙黄色火焰轮廓）
        local edgeAlpha = math.floor(160 + 70 * pulse)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR)
        nvgStrokeColor(vg, nvgRGBA(255, 160, 40, edgeAlpha))
        nvgStrokeWidth(vg, math.max(2.0, GS.CELL * 0.04))
        nvgStroke(vg)

        -- 第4层：外圈热浪辉光（更大范围的淡橙光晕）
        local heatGlow = nvgRadialGradient(vg, cx, drawCy, shieldR * 0.8, shieldR * 1.4,
            nvgRGBA(255, 100, 20, math.floor(30 + 20 * pulse)),
            nvgRGBA(255, 60, 10, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, drawCy, shieldR * 1.4)
        nvgFillPaint(vg, heatGlow)
        nvgFill(vg)

        -- 第5层：8个沿护盾边缘流动的火焰光团（模拟表面燃烧纹理）
        for i = 1, 8 do
            local baseAngle = (i / 8) * math.pi * 2
            local orbAngle = baseAngle + time * 2.5
            local wobble = math.sin(time * 6.0 + i * 1.7) * shieldR * 0.08
            local orbR = shieldR * 0.92 + wobble
            local orbX = cx + math.cos(orbAngle) * orbR
            local orbY = drawCy + math.sin(orbAngle) * orbR
            local orbSize = math.max(2.0, GS.CELL * 0.045) * (0.7 + 0.3 * math.sin(time * 8 + i * 2.3))
            -- 每个光团颜色在黄→橙→红之间变化
            local cPhase = (math.sin(time * 5.0 + i * 1.1) + 1) * 0.5
            local oR = math.floor(255 - 40 * cPhase)
            local oG = math.floor(180 - 100 * cPhase)
            local oB = math.floor(40 - 20 * cPhase)
            local orbAlpha = math.floor(140 + 80 * math.sin(time * 7 + i * 0.9))
            nvgBeginPath(vg)
            nvgCircle(vg, orbX, orbY, orbSize)
            nvgFillColor(vg, nvgRGBA(oR, oG, oB, orbAlpha))
            nvgFill(vg)
        end

        -- 第6层：大量逃逸火花粒子（20个，从护盾表面飞散到外围）
        for i = 1, 20 do
            local seed1 = i * 137.508
            local seed2 = i * 73.137 + 5.91
            local seed3 = i * 41.723 + 2.17
            local period = 1.2 + (seed2 % 10) * 0.08
            local life = (time + seed1 * 0.1) % period
            local t = life / period
            local angle = seed1 % (math.pi * 2)
            local dist = shieldR * (1.0 + t * 0.8)
            local sparkX = cx + math.cos(angle) * dist
            local sparkY = drawCy + math.sin(angle) * dist - t * GS.CELL * 0.15
            local drift = math.sin(time * 4.0 + seed3) * GS.CELL * 0.04
            sparkX = sparkX + drift
            local maxSize = math.max(1.5, GS.CELL * 0.035) * (0.6 + (seed3 % 5) * 0.12)
            local pSize = maxSize * (1.0 - t * 0.7)
            local alphaT = 1.0
            if t < 0.15 then
                alphaT = t / 0.15
            elseif t > 0.5 then
                alphaT = 1.0 - (t - 0.5) / 0.5
            end
            local pAlpha = math.floor(200 * alphaT * (0.7 + 0.3 * flicker))
            local pR = math.floor(255 - 60 * t)
            local pG = math.floor(200 - 160 * t)
            local pB = math.floor(60 - 50 * t)
            if pAlpha > 5 and pSize > 0.5 then
                nvgBeginPath(vg)
                nvgCircle(vg, sparkX, sparkY, pSize)
                nvgFillColor(vg, nvgRGBA(pR, pG, pB, pAlpha))
                nvgFill(vg)
            end
        end

        -- 第7层：8个大型火焰舌（模拟护盾表面窜出的火舌）
        for i = 1, 8 do
            local tongueAngle = (i / 8) * math.pi * 2 + time * 1.2
            local tonguePhase = math.sin(time * 5.5 + i * 2.5)
            local tongueLen = GS.CELL * (0.06 + 0.05 * math.max(0, tonguePhase))
            if tongueLen > GS.CELL * 0.03 then
                local tx1 = cx + math.cos(tongueAngle) * shieldR
                local ty1 = drawCy + math.sin(tongueAngle) * shieldR
                local tx2 = cx + math.cos(tongueAngle) * (shieldR + tongueLen)
                local ty2 = drawCy + math.sin(tongueAngle) * (shieldR + tongueLen) - tongueLen * 0.3
                local tongueAlpha = math.floor(180 + 60 * tonguePhase)
                nvgBeginPath(vg)
                nvgMoveTo(vg, tx1, ty1)
                nvgLineTo(vg, tx2, ty2)
                nvgStrokeColor(vg, nvgRGBA(255, 140, 30, tongueAlpha))
                nvgStrokeWidth(vg, math.max(2.0, GS.CELL * 0.03))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, tx2, ty2, math.max(1.5, GS.CELL * 0.02))
                nvgFillColor(vg, nvgRGBA(255, 220, 80, tongueAlpha))
                nvgFill(vg)
            end
        end

        nvgLineCap(vg, NVG_BUTT)
    end

    -- 名字（冰蓝色，底部）
    local nameSize = math.max(9, totalCell * 0.24)
    local nameY = bodyY + bodyH
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, nameSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    for _, off in ipairs(OFFSETS_4) do
        nvgText(vg, cx + off[1], nameY + off[2], "冰墙", nil)
    end
    nvgFillColor(vg, nvgRGBA(180, 230, 255, 255))
    nvgText(vg, cx, nameY, "冰墙", nil)
end

-- ====================================================================
-- 绘制：墓碑
-- ====================================================================
function M.drawTombstone()
    local vg = M.vg
    if M.tombstoneImage == -1 then return end

    local alpha = 255
    local dropOffset = 0
    local flyOffset = 0
    local scale = 1.0

    if GS.tombstoneDropAnim then
        local t = math.min(1.0, GS.tombstoneDropAnim.timer / GS.tombstoneDropAnim.duration)
        local easeOut = 1 - (1 - t) * (1 - t)
        local bounce = math.sin(t * math.pi) * (1 - t) * 0.15
        dropOffset = -(1 - easeOut) * GS.CELL * 6
        scale = 1.0 + bounce
        alpha = math.floor(255 * math.min(1.0, t * 3))
    end

    if GS.tombstoneAnim then
        local t = GS.tombstoneAnim.timer / GS.tombstoneAnim.duration
        local ease = t * t
        flyOffset = -ease * GS.CELL * 2.5
        alpha = math.floor(255 * (1 - t))
    end

    if alpha <= 0 then return end

    local cellCx = GS.BOARD_X + (GS.deathX - 1) * GS.CELL + GS.CELL / 2
    local cellCy = GS.BOARD_Y + (GS.deathY - 1) * GS.CELL + GS.CELL / 2 + dropOffset + flyOffset
    local imgSize = GS.CELL * 1.1
    local imgX = cellCx - imgSize / 2
    local imgY = cellCy - imgSize * 0.55

    nvgSave(vg)
    if scale ~= 1.0 then
        nvgTranslate(vg, cellCx, cellCy)
        nvgScale(vg, scale, scale)
        nvgTranslate(vg, -cellCx, -cellCy)
    end

    local imgPaint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize,
        0, M.tombstoneImage, alpha / 255.0)
    nvgBeginPath(vg)
    nvgRect(vg, imgX, imgY, imgSize, imgSize)
    nvgFillPaint(vg, imgPaint)
    nvgFill(vg)
    nvgRestore(vg)
end

-- ====================================================================
-- 绘制：卓越装备掉落橙光闪烁特效
-- ====================================================================
function M.drawSuperiorDropFlash()
    local flash = GS.superiorDropFlash
    if not flash then return end

    local vg = M.vg
    local sw, sh = GS.SCREEN_W, GS.SCREEN_H  -- 整个屏幕（设计坐标）
    local t = flash.timer / flash.duration  -- 0→1 进度

    if t >= 1.0 then
        GS.superiorDropFlash = nil
        return
    end

    -- 三段式效果：
    -- 阶段1 (0~0.15): 快速闪入，整体橙色覆盖
    -- 阶段2 (0.15~0.5): 闪烁脉动
    -- 阶段3 (0.5~1.0): 缓慢消退
    local alpha = 0
    if t < 0.15 then
        -- 快速闪入
        local p = t / 0.15
        alpha = p * 180
    elseif t < 0.5 then
        -- 脉动闪烁（2~3次闪烁）
        local p = (t - 0.15) / 0.35
        local flicker = math.sin(p * math.pi * 5) * 0.4 + 0.6
        local decay = 1.0 - p * 0.3
        alpha = 180 * flicker * decay
    else
        -- 缓慢消退
        local p = (t - 0.5) / 0.5
        local ease = 1.0 - p * p  -- ease-out
        alpha = 180 * 0.5 * ease
    end

    alpha = math.max(0, math.min(255, math.floor(alpha)))
    if alpha <= 0 then return end

    nvgSave(vg)

    -- 底层：橙色全屏覆盖
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(255, 140, 0, math.floor(alpha * 0.4)))
    nvgFill(vg)

    -- 中层：中心向外的径向渐变光晕
    local cx = sw / 2
    local cy = sh / 2
    local radius = math.max(sw, sh) * 0.6
    local innerPaint = nvgRadialGradient(vg, cx, cy, 0, radius,
        nvgRGBA(255, 200, 50, math.floor(alpha * 0.6)),
        nvgRGBA(255, 120, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillPaint(vg, innerPaint)
    nvgFill(vg)

    -- 上层：边缘高光（上下边缘扫光效果）
    if t < 0.6 then
        local scanProgress = t / 0.6
        local scanAlpha = math.floor(alpha * 0.5 * (1.0 - scanProgress))
        -- 上边缘光
        local topGrad = nvgLinearGradient(vg, 0, 0, 0, sh * 0.12,
            nvgRGBA(255, 220, 100, scanAlpha),
            nvgRGBA(255, 180, 50, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, sw, sh * 0.12)
        nvgFillPaint(vg, topGrad)
        nvgFill(vg)
        -- 下边缘光
        local botGrad = nvgLinearGradient(vg, 0, sh * 0.88, 0, sh,
            nvgRGBA(255, 180, 50, 0),
            nvgRGBA(255, 220, 100, scanAlpha))
        nvgBeginPath(vg)
        nvgRect(vg, 0, sh * 0.88, sw, sh * 0.12)
        nvgFillPaint(vg, botGrad)
        nvgFill(vg)
        -- 左边缘光
        local leftGrad = nvgLinearGradient(vg, 0, 0, sw * 0.1, 0,
            nvgRGBA(255, 220, 100, math.floor(scanAlpha * 0.7)),
            nvgRGBA(255, 180, 50, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, sw * 0.1, sh)
        nvgFillPaint(vg, leftGrad)
        nvgFill(vg)
        -- 右边缘光
        local rightGrad = nvgLinearGradient(vg, sw * 0.9, 0, sw, 0,
            nvgRGBA(255, 180, 50, 0),
            nvgRGBA(255, 220, 100, math.floor(scanAlpha * 0.7)))
        nvgBeginPath(vg)
        nvgRect(vg, sw * 0.9, 0, sw * 0.1, sh)
        nvgFillPaint(vg, rightGrad)
        nvgFill(vg)
    end

    nvgRestore(vg)
end

-- ====================================================================
-- 绘制：复活遮罩
-- ====================================================================
function M.drawRespawnOverlay()
    local vg = M.vg
    local boardPixel = GS.CELL * GS.BOARD_SIZE

    nvgBeginPath(vg)
    nvgRect(vg, GS.BOARD_X, GS.BOARD_Y, boardPixel, boardPixel)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    local centerX = GS.BOARD_X + boardPixel / 2
    local centerY = GS.BOARD_Y + boardPixel / 2

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE then
        -- 史莱姆国王大反击死亡：深红"你 死 了" + 返回清水镇按钮
        nvgFontSize(vg, 32)
        nvgTextLetterSpacing(vg, 8)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgText(vg, centerX + 1.5, centerY - 30 + 1.5, "你 死 了", nil)
        nvgFillColor(vg, nvgRGBA(220, 60, 50, 255))
        nvgText(vg, centerX, centerY - 30, "你 死 了", nil)
        nvgTextLetterSpacing(vg, 0)

        -- 显示本次累积伤害
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(240, 200, 100, 220))
        local accDmg = GS.slimeRevengeAccDmg or 0
        local dmgStr = accDmg >= 100000000 and string.format("%.1f亿", accDmg / 100000000)
                    or accDmg >= 10000 and string.format("%.1f万", accDmg / 10000)
                    or tostring(accDmg)
        nvgText(vg, centerX, centerY - 2, "本次累积伤害：" .. dmgStr, nil)

        -- 返回清水镇按钮
        local btnW, btnH = 120, 32
        local btnX = centerX - btnW / 2
        local btnY = centerY + 18
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
        nvgFillColor(vg, nvgRGBA(160, 40, 40, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 5)
        nvgStrokeColor(vg, nvgRGBA(220, 80, 70, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 230, 220, 255))
        nvgText(vg, centerX, btnY + btnH / 2, "返回清水镇", nil)
        GS.slimeRevengeReturnBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    elseif GS.currentStage == GS.STAGE_DIHATA_REVENGE then
        -- 迪哈塔大反击死亡：橙色"你 死 了" + 返回清水镇按钮
        nvgFontSize(vg, 32)
        nvgTextLetterSpacing(vg, 8)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgText(vg, centerX + 1.5, centerY - 30 + 1.5, "你 死 了", nil)
        nvgFillColor(vg, nvgRGBA(200, 140, 40, 255))
        nvgText(vg, centerX, centerY - 30, "你 死 了", nil)
        nvgTextLetterSpacing(vg, 0)

        -- 显示本次累积伤害
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(240, 200, 100, 220))
        local accDmg = GS.dihataRevengeAccDmg or 0
        local dmgStr = accDmg >= 100000000 and string.format("%.1f亿", accDmg / 100000000)
                    or accDmg >= 10000 and string.format("%.1f万", accDmg / 10000)
                    or tostring(accDmg)
        nvgText(vg, centerX, centerY - 2, "本次累积伤害：" .. dmgStr, nil)

        -- 返回清水镇按钮
        local btnW, btnH = 120, 32
        local btnX = centerX - btnW / 2
        local btnY = centerY + 18
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
        nvgFillColor(vg, nvgRGBA(160, 100, 20, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 5)
        nvgStrokeColor(vg, nvgRGBA(220, 160, 40, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 240, 210, 255))
        nvgText(vg, centerX, btnY + btnH / 2, "返回清水镇", nil)
        GS.dihataRevengeReturnBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    elseif GS.isAbyssWorld and GS.abyssWorldLives <= 0 then
        -- 异世深渊模式（生命耗尽）：深红"你 死 了" + 返回清水镇按钮
        nvgFontSize(vg, 32)
        nvgTextLetterSpacing(vg, 8)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgText(vg, centerX + 1.5, centerY - 30 + 1.5, "你 死 了", nil)
        nvgFillColor(vg, nvgRGBA(220, 60, 50, 255))
        nvgText(vg, centerX, centerY - 30, "你 死 了", nil)
        nvgTextLetterSpacing(vg, 0)

        -- 返回清水镇按钮
        local btnW, btnH = 120, 32
        local btnX = centerX - btnW / 2
        local btnY = centerY + 10
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
        nvgFillColor(vg, nvgRGBA(160, 40, 40, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 5)
        nvgStrokeColor(vg, nvgRGBA(220, 80, 70, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 230, 220, 255))
        nvgText(vg, centerX, btnY + btnH / 2, "返回清水镇", nil)
        GS.abyssWorldReturnBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    elseif GS.isDungeon then
        -- 副本模式：深红"你 死 了" + 再战按钮
        nvgFontSize(vg, 32)
        nvgTextLetterSpacing(vg, 8)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgText(vg, centerX + 1.5, centerY - 30 + 1.5, "你 死 了", nil)
        nvgFillColor(vg, nvgRGBA(180, 30, 30, 255))
        nvgText(vg, centerX, centerY - 30, "你 死 了", nil)
        nvgTextLetterSpacing(vg, 0)

        -- 再战按钮
        local btnW, btnH = 90, 32
        local btnX = centerX - btnW / 2
        local btnY = centerY + 10
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
        nvgFillColor(vg, nvgRGBA(160, 40, 30, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 5)
        nvgStrokeColor(vg, nvgRGBA(220, 80, 60, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 240, 220, 255))
        nvgText(vg, centerX, btnY + btnH / 2, "再战", nil)
        GS.dungeonRetryBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    else
        -- 普通模式：倒计时复活
        local countdown = math.ceil(math.max(0, GS.respawnTimer))
        local frac = GS.respawnTimer - math.floor(GS.respawnTimer)
        local pulse = 1.0 + math.max(0, 1.0 - frac * 3) * 0.15

        nvgSave(vg)
        nvgTranslate(vg, centerX, centerY)
        nvgScale(vg, pulse, pulse)
        nvgTranslate(vg, -centerX, -centerY)

        nvgFontSize(vg, 72)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgText(vg, centerX + 2, centerY + 2, tostring(countdown), nil)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, centerX, centerY, tostring(countdown), nil)

        nvgRestore(vg)

        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 200))
        nvgText(vg, centerX, centerY - 52, "复活中...", nil)

        -- 异世深渊：显示剩余复活次数
        if GS.isAbyssWorld and GS.abyssWorldLives > 0 then
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(220, 60, 50, 220))
            local livesText = "剩余生命：" .. GS.abyssWorldLives .. "/" .. GS.ABYSS_WORLD_MAX_LIVES
            nvgText(vg, centerX, centerY + 72, livesText, nil)
        end

        local barW = boardPixel * 0.4
        local barH = 6
        local barX = centerX - barW / 2
        local barY = centerY + 42
        local progress = 1.0 - safeProgress(GS.respawnTimer, GS.RESPAWN_TIME)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(50, 50, 60, 200))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
        nvgFill(vg)
    end
end

-- ====================================================================
-- 绘制：顶部栏
-- ====================================================================
--- 右上角游戏内时间显示（供 drawTopBar 内部调用）
local MONTH_DAYS = {30,30,30,30,30,30,30,30,30,30,30,30}
function M.drawTopBarTime(vg, midY)
    -- 苏醒事件未完成前不显示日期时间
    if not GS.awakeningCompleted then return end
    local totalMin = ((GS.weatherTime or 1) - 1)  -- 0-based
    local dayOfYear = math.floor(totalMin / 1440)  -- 0~364
    local minuteOfDay = totalMin % 1440
    local hour = math.floor(minuteOfDay / 60)
    local minute = minuteOfDay % 60
    local month, day = 1, dayOfYear + 1
    for m = 1, 12 do
        if day <= MONTH_DAYS[m] then
            month = m
            break
        end
        day = day - MONTH_DAYS[m]
    end
    local timeLabel = string.format("%d月%d日 %02d:%02d", month, day, hour, minute)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(230, 200, 100, 230))
    local timeEdgeInset = GS.isLandscape and 40 or 0
    nvgText(vg, GS.SCREEN_W - 10 - timeEdgeInset, midY, timeLabel, nil)
end

function M.drawTopBar()
    local vg = M.vg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GS.SCREEN_W, GS.TOP_BAR_H)
    nvgFillColor(vg, nvgRGBA(20, 25, 45, 240))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, GS.TOP_BAR_H)
    nvgLineTo(vg, GS.SCREEN_W, GS.TOP_BAR_H)
    nvgStrokeColor(vg, nvgRGBA(60, 70, 100, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    local midY = GS.TOP_BAR_CONTENT_MID_Y or (GS.TOP_BAR_H / 2)

    -- 顶栏按钮区域
    -- 布局顺序（从左到右）：⚙(设置) → 监 → 管
    -- 监/管 仅管理员 + 清水镇主场景时显示
    local sBtnW = 32
    local sBtnH = 24
    local edgeInset = GS.isLandscape and 40 or 0
    local isGMUser = GS.isGM()
    local gmBtnW = 24
    local monBtnW = 24
    local gmBtnGap = 4
    local baseX = 8 + edgeInset
    -- 判断是否在清水镇主场景（非训练场、无子场景）
    local inClearwater = BoardOverlay.isActive()
        and BoardOverlay.overlayId == "clearwater"
        and not BoardOverlay.subScene
        and not GS.homeMode
    local showGMBtns = isGMUser and (inClearwater or GS.homeMode)
    -- 设置按钮始终在最左
    local sBtnX = baseX
    local sBtnY = midY - sBtnH / 2

    -- 设置按钮
    GS.settingsBtnRect = { x = sBtnX, y = sBtnY, w = sBtnW, h = sBtnH }

    if showGMBtns then
        local MonitorPanel = require("MonitorPanel")

        -- "监"按钮（设置按钮右侧，红色色调）
        local monBtnX = sBtnX + sBtnW + gmBtnGap
        local monBtnY = sBtnY
        GS.monitorPanelBtnRect = { x = monBtnX, y = monBtnY, w = monBtnW, h = sBtnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, monBtnX, monBtnY, monBtnW, sBtnH, 4)
        if MonitorPanel.showPanel then
            nvgFillColor(vg, nvgRGBA(140, 50, 50, 230))
        else
            nvgFillColor(vg, nvgRGBA(80, 30, 30, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(220, 100, 80, MonitorPanel.showPanel and 255 or 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if not MonitorPanel.showPanel and isHovered(monBtnX, monBtnY, monBtnW, sBtnH) then
            drawHoverHighlight(vg, monBtnX, monBtnY, monBtnW, sBtnH, 4)
        end
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 160, 140, MonitorPanel.showPanel and 255 or 180))
        nvgText(vg, monBtnX + monBtnW / 2, monBtnY + sBtnH / 2, "监", nil)

        -- "管"按钮（在"监"右侧）
        local gmBtnX = monBtnX + monBtnW + gmBtnGap
        local gmBtnY = sBtnY
        GS.gmPanelBtnRect = { x = gmBtnX, y = gmBtnY, w = gmBtnW, h = sBtnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, gmBtnX, gmBtnY, gmBtnW, sBtnH, 4)
        if GS.showGMPanel then
            nvgFillColor(vg, nvgRGBA(120, 80, 40, 230))
        else
            nvgFillColor(vg, nvgRGBA(70, 50, 30, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 160, 60, GS.showGMPanel and 255 or 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if not GS.showGMPanel and isHovered(gmBtnX, gmBtnY, gmBtnW, sBtnH) then
            drawHoverHighlight(vg, gmBtnX, gmBtnY, gmBtnW, sBtnH, 4)
        end
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 120, GS.showGMPanel and 255 or 180))
        nvgText(vg, gmBtnX + gmBtnW / 2, gmBtnY + sBtnH / 2, "管", nil)

        -- "令"按钮（在"管"右侧，GM指令面板）
        local BanManager = require("BanManager")
        local banBtnX = gmBtnX + gmBtnW + gmBtnGap
        local banBtnY = sBtnY
        local banBtnW = 24
        GS.gmBanBtnRect = { x = banBtnX, y = banBtnY, w = banBtnW, h = sBtnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, banBtnX, banBtnY, banBtnW, sBtnH, 4)
        if BanManager.isGMPanelOpen() then
            nvgFillColor(vg, nvgRGBA(140, 40, 40, 230))
        else
            nvgFillColor(vg, nvgRGBA(80, 30, 30, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(220, 80, 80, BanManager.isGMPanelOpen() and 255 or 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if not BanManager.isGMPanelOpen() and isHovered(banBtnX, banBtnY, banBtnW, sBtnH) then
            drawHoverHighlight(vg, banBtnX, banBtnY, banBtnW, sBtnH, 4)
        end
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 140, 140, BanManager.isGMPanelOpen() and 255 or 180))
        nvgText(vg, banBtnX + banBtnW / 2, banBtnY + sBtnH / 2, "令", nil)
    else
        GS.gmPanelBtnRect = nil
        GS.monitorPanelBtnRect = nil
        GS.gmBanBtnRect = nil
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, sBtnX, sBtnY, sBtnW, sBtnH, 4)
    if GS.showSettings then
        nvgFillColor(vg, nvgRGBA(80, 90, 130, 230))
    else
        nvgFillColor(vg, nvgRGBA(50, 55, 80, 200))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(120, 130, 170, GS.showSettings and 255 or 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    if not GS.showSettings and isHovered(sBtnX, sBtnY, sBtnW, sBtnH) then
        drawHoverHighlight(vg, sBtnX, sBtnY, sBtnW, sBtnH, 4)
    end

    -- 齿轮图标（平滑参数曲线）
    local gx = sBtnX + sBtnW / 2
    local gy = midY
    local gearAlpha = GS.showSettings and 255 or 180
    local gearColor = nvgRGBA(200, 210, 240, gearAlpha)
    local bgColor
    if GS.showSettings then
        bgColor = nvgRGBA(80, 90, 130, 230)
    else
        bgColor = nvgRGBA(50, 55, 80, 200)
    end

    local baseR = 6.2       -- 齿谷半径
    local toothAmp = 2.8    -- 齿高
    local teethN = 8
    local segments = 128

    nvgBeginPath(vg)
    for s = 0, segments - 1 do
        local angle = s * math.pi * 2 / segments
        -- 平滑方波：cos 值乘以系数后截断，产生平顶平谷+圆润过渡
        local cosVal = math.cos(teethN * angle)
        local t = cosVal * 2.5
        if t > 1 then t = 1 elseif t < -1 then t = -1 end
        t = (t + 1) * 0.5  -- 归一化 0~1
        local r = baseR + toothAmp * t
        local px = gx + math.cos(angle) * r
        local py = gy + math.sin(angle) * r
        if s == 0 then
            nvgMoveTo(vg, px, py)
        else
            nvgLineTo(vg, px, py)
        end
    end
    nvgClosePath(vg)
    nvgFillColor(vg, gearColor)
    nvgFill(vg)

    -- 中心孔
    nvgBeginPath(vg)
    nvgCircle(vg, gx, gy, 2.8)
    nvgFillColor(vg, bgColor)
    nvgFill(vg)

    -- 覆盖层模式：隐藏战斗按钮，显示场景标题
    if BoardOverlay.isActive() then
        GS.autoBattleSettingsBtnRect = nil
        GS.autoBtnRect = nil
        local title = BoardOverlay.title or ""
        -- 子场景时显示建筑标题（舞池视角有独立标题）
        if BoardOverlay.subScene then
            local bDef = BoardOverlay.buildingInteriors[BoardOverlay.subScene.id]
            if BoardOverlay.tavernDanceView and bDef and bDef.dancefloor then
                title = bDef.dancefloor.title or title
            else
                title = BoardOverlay.subScene.title or title
            end
        end
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 230, 200, 240))
        nvgText(vg, GS.SCREEN_W / 2, midY, title, nil)
        -- BoardOverlay 场景也显示时间
        M.drawTopBarTime(vg, midY)
        return
    end

    -- 自动按钮的右边界（用于后续 barLeftX 定位）
    local autoBtnRightX = sBtnX + sBtnW

    -- 家场景：隐藏自动战斗按钮，显示升级按钮
    if GS.homeMode then
        GS.autoBattleSettingsBtnRect = nil
        GS.autoBtnRect = nil
        GS.autoMode = false

        -- 家园升级按钮（设置按钮右侧，非大型时显示）
        if GS.homeType ~= "large" then
            local ubW = 46
            local ubH = sBtnH
            local ubX = sBtnX + sBtnW + 6
            local ubY = sBtnY
            GS.homeUpgradeBtnRect = { x = ubX, y = ubY, w = ubW, h = ubH }
            autoBtnRightX = ubX + ubW

            -- 绿色渐变背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ubX, ubY, ubW, ubH, 4)
            local gGrad = nvgLinearGradient(vg, ubX, ubY, ubX, ubY + ubH,
                nvgRGBA(40, 150, 50, 230), nvgRGBA(25, 110, 30, 230))
            nvgFillPaint(vg, gGrad)
            nvgFill(vg)

            -- 边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ubX + 0.5, ubY + 0.5, ubW - 1, ubH - 1, 4)
            nvgStrokeColor(vg, nvgRGBA(120, 220, 120, 200))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 文字
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(230, 255, 230, 255))
            nvgText(vg, ubX + ubW / 2, midY, "升级", nil)

            if isHovered(ubX, ubY, ubW, ubH) then
                drawHoverHighlight(vg, ubX, ubY, ubW, ubH, 4)
            end
        else
            GS.homeUpgradeBtnRect = nil
        end
    else
        -- 自动设置按钮（设置按钮右侧）
        local absBtnW = 60
        local absBtnH = sBtnH
        local absBtnX = sBtnX + sBtnW + 6
        local absBtnY = sBtnY
        GS.autoBattleSettingsBtnRect = { x = absBtnX, y = absBtnY, w = absBtnW, h = absBtnH }

        nvgBeginPath(vg)
        nvgRoundedRect(vg, absBtnX, absBtnY, absBtnW, absBtnH, 4)
        nvgFillColor(vg, nvgRGBA(60, 65, 90, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(150, 160, 190, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if isHovered(absBtnX, absBtnY, absBtnW, absBtnH) then
            drawHoverHighlight(vg, absBtnX, absBtnY, absBtnW, absBtnH, 4)
        end

        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
        nvgText(vg, absBtnX + absBtnW / 2, midY, "自动设置", nil)

        -- 自动按钮（自动设置按钮右侧）
        local btnW = 46
        local btnH = sBtnH
        local btnX = absBtnX + absBtnW + 6
        local btnY = sBtnY
        GS.autoBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        autoBtnRightX = btnX + btnW

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        if GS.autoMode then
            nvgFillColor(vg, nvgRGBA(40, 160, 80, 230))
        else
            nvgFillColor(vg, nvgRGBA(60, 65, 90, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(150, 160, 190, GS.autoMode and 255 or 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if not GS.autoMode and isHovered(btnX, btnY, btnW, btnH) then
            drawHoverHighlight(vg, btnX, btnY, btnW, btnH, 4)
        end

        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, GS.autoMode and 255 or 180))
        nvgText(vg, btnX + btnW / 2, midY, GS.autoMode and "自动中" or "自动", nil)
    end

    -- 目标怪物：优先鼠标悬停，其次点击锁定，最后最近怪物
    local targetMonster = nil
    -- 1) 鼠标悬停检测
    if GS.hoverX and GS.hoverY and GS.BOARD_X and GS.CELL and GS.CELL > 0 then
        local cx = math.floor((GS.hoverX - GS.BOARD_X) / GS.CELL) + 1
        local cy = math.floor((GS.hoverY - GS.BOARD_Y) / GS.CELL) + 1
        if cx >= 1 and cx <= GS.BOARD_SIZE and cy >= 1 and cy <= GS.BOARD_SIZE then
            local unit = GS.getUnitAt(cx, cy)
            if unit and unit.isMonster and unit.hp > 0 then
                targetMonster = unit
            end
        end
    end
    -- 2) 点击锁定的目标（清除已死亡或不在当前场景的锁定目标）
    if not targetMonster and GS.topBarLockedTarget then
        local lockedAlive = GS.topBarLockedTarget.hp and GS.topBarLockedTarget.hp > 0
        local lockedInScene = false
        if lockedAlive then
            for _, m in ipairs(GS.monsters) do
                if m == GS.topBarLockedTarget then lockedInScene = true; break end
            end
        end
        if lockedAlive and lockedInScene then
            targetMonster = GS.topBarLockedTarget
        else
            GS.topBarLockedTarget = nil
        end
    end
    -- 3) 无悬停无锁定时回退到最近怪物
    if not targetMonster and GS.player and GS.player.hp > 0 then
        local bestDist = 9999
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 then
                local d = GS.manhattan(GS.player.x, GS.player.y, m.x, m.y)
                if d < bestDist then
                    bestDist = d
                    targetMonster = m
                end
            end
        end
    end

    -- 顶栏右侧：目标怪物生命条 / 关卡名回退
    local barLeftX = autoBtnRightX + 10
    local barRightX = barLeftX + (GS.SCREEN_W - 10 - barLeftX) / 2
    if targetMonster then
        local iconSize = math.min(34, GS.TOP_BAR_H - GS.safeTop - 10)
        local iconX = barLeftX
        local iconY = midY - iconSize / 2

        -- 怪物头像
        local mImg = targetMonster.image and ImageManager.lazyGet("monster", targetMonster.image)
        if mImg then
            -- 头像背景圆
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 4)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
            nvgFill(vg)
            -- 头像图片
            local imgPaint = nvgImagePattern(vg, iconX + 1, iconY + 1,
                iconSize - 2, iconSize - 2, 0, mImg, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX + 1, iconY + 1, iconSize - 2, iconSize - 2, 3)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
            -- 头像边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 4)
            nvgStrokeColor(vg, nvgRGBA(80, 90, 130, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 名称和血条区域
        local infoX = iconX + iconSize + 8
        local infoW = barRightX - infoX

        -- 怪物名称
        local nameFontSize = 12
        local nameCenterY = midY - 1 - nameFontSize / 2  -- 名称行垂直中心
        nvgFontSize(vg, nameFontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 220, 240, 230))
        nvgText(vg, infoX, nameCenterY, targetMonster.name, nil)
        local nameW = nvgTextBounds(vg, 0, 0, targetMonster.name, nil)

        -- "增益&减益" 按钮（名称右侧，点击展开面板）
        do
            local btnLabel = "增益&减益"
            local btnFs = 9
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, btnFs)
            local btnTw = nvgTextBounds(vg, 0, 0, btnLabel, nil, nil)
            local btnPadX = 4
            local btnW = btnTw + btnPadX * 2
            local btnH2 = 14
            local btnX = infoX + nameW + 6
            local btnY = nameCenterY - btnH2 / 2
            local mx, my = GS.mouseX or 0, GS.mouseY or 0
            local btnHovered = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH2

            -- 统计当前怪物身上的状态数量（用于显示计数）
            local activeCount = 0
            if targetMonster.taunted and targetMonster.taunted > 0 then activeCount = activeCount + 1 end
            if targetMonster.stunned and targetMonster.stunned > 0 then activeCount = activeCount + 1 end
            if targetMonster.poisoned and targetMonster.poisoned > 0 then activeCount = activeCount + 1 end
            if targetMonster.armorBroken and targetMonster.armorBrokenTurns and targetMonster.armorBrokenTurns > 0 then activeCount = activeCount + 1 end
            if targetMonster.sandBlinded and targetMonster.sandBlindedTurns and targetMonster.sandBlindedTurns > 0 then activeCount = activeCount + 1 end
            if targetMonster.prayerHealPct and targetMonster.prayerHealPct > 0 then activeCount = activeCount + 1 end
            if targetMonster.holySpringTurns and targetMonster.holySpringTurns > 0 then activeCount = activeCount + 1 end
            if targetMonster.conquerTurns and targetMonster.conquerTurns > 0 then activeCount = activeCount + 1 end
            if targetMonster.shelterTurns and targetMonster.shelterTurns > 0 then activeCount = activeCount + 1 end
            if targetMonster.miracleTurns and targetMonster.miracleTurns > 0 then activeCount = activeCount + 1 end
            if targetMonster.noticeCritDmgTurns and targetMonster.noticeCritDmgTurns > 0 then activeCount = activeCount + 1 end
            if GS.markedTarget == targetMonster then activeCount = activeCount + 1 end
            if targetMonster.frozen and targetMonster.frozen > 0 then activeCount = activeCount + 1 end
            if targetMonster.chilled and targetMonster.chilledTurns and targetMonster.chilledTurns > 0 then activeCount = activeCount + 1 end
            if targetMonster.burned and targetMonster.burnStacks and #targetMonster.burnStacks > 0 then activeCount = activeCount + 1 end

            -- 按钮背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH2, 3)
            if GS.showMonsterBuffSummary then
                nvgFillColor(vg, nvgRGBA(80, 160, 60, 200))
            elseif btnHovered then
                nvgFillColor(vg, nvgRGBA(100, 80, 50, 200))
            else
                nvgFillColor(vg, nvgRGBA(70, 55, 35, 180))
            end
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(140, 120, 80, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 按钮文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, btnFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(230, 210, 170, 255))
            local displayLabel = activeCount > 0 and (btnLabel .. "(" .. activeCount .. ")") or btnLabel
            nvgText(vg, btnX + btnW / 2, btnY + btnH2 / 2, displayLabel, nil)

            GS.monsterBuffBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH2 }
            GS._monsterBuffTarget = targetMonster  -- 记录当前目标怪物供面板使用
        end

        -- 血条 / 累计伤害显示
        local barH = 8
        local barY = midY + 2
        local barW = infoW

        if (GS.currentStage == GS.STAGE_SLIME_KING_REVENGE or GS.currentStage == GS.STAGE_DIHATA_REVENGE) and targetMonster.immortal then
            -- 大反击关卡：显示累计伤害（替代血条）
            local accDmg, rageLayer
            if GS.currentStage == GS.STAGE_DIHATA_REVENGE then
                accDmg = GS.dihataRevengeAccDmg or 0
                rageLayer = GS.dihataRevengeRageLayer or 0
            else
                accDmg = GS.slimeRevengeAccDmg or 0
                rageLayer = GS.slimeRevengeRageLayer or 0
            end
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, 240))
            -- 千分位格式化
            local dmgStr = tostring(math.floor(accDmg))
            dmgStr = dmgStr:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
            local rageStr = ""
            if rageLayer > 0 then
                rageStr = "  暴怒x" .. rageLayer
            end
            nvgText(vg, infoX, barY + barH / 2,
                "累计伤害 " .. dmgStr .. rageStr, nil)
        else
            local hpRatio = math.max(0, math.min(1, targetMonster.hp / math.max(1, targetMonster.maxHp)))

            -- 血条背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, infoX, barY, barW, barH, 3)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
            nvgFill(vg)

            -- 血条填充（固定红色）
            if hpRatio > 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, infoX, barY, barW * hpRatio, barH, 3)
                nvgFillColor(vg, nvgRGBA(200, 50, 40, 230))
                nvgFill(vg)
            end

            -- 血条边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, infoX, barY, barW, barH, 3)
            nvgStrokeColor(vg, nvgRGBA(80, 90, 130, 150))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- HP 数值（血条上居中）
            nvgFontSize(vg, 8)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgText(vg, infoX + barW / 2, barY + barH / 2,
                math.floor(hpRatio * 100) .. "%", nil)
        end
    else
        -- 无怪物时清除按钮/面板状态
        GS.monsterBuffBtnRect = nil
        GS._monsterBuffTarget = nil
        if GS.showMonsterBuffSummary then
            GS.showMonsterBuffSummary = false
        end
        -- 无怪物时显示当前位置名
        local stageName = GS.currentStageName
        if not stageName then
            local stageDef = GS.STAGE_DEFS[GS.currentStage]
            stageName = stageDef and stageDef.name or ("关卡" .. GS.currentStage)
        end
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 210, 240, 220))
        nvgText(vg, (barLeftX + barRightX) / 2, midY, stageName, nil)
    end

    -- 右上角：游戏内时间显示
    M.drawTopBarTime(vg, midY)

    -- 怪物增益&减益面板移至 main.lua 顶层绘制（避免被底部面板遮挡）

end

-- ====================================================================
-- 绘制：怪物增益&减益面板（顶栏下方弹出）
-- ====================================================================
function M.drawMonsterBuffPanel(vg)
    local m = GS._monsterBuffTarget
    if not m then return end

    -- 面板位置：按钮下方弹出
    local btnR = GS.monsterBuffBtnRect
    if not btnR then return end
    local panelW = 200
    local panelMaxH = 220
    local panelX = math.max(4, btnR.x)
    local panelY = btnR.y + btnR.h + 4
    -- 确保不超出屏幕右侧
    if panelX + panelW > GS.SCREEN_W - 4 then
        panelX = GS.SCREEN_W - 4 - panelW
    end

    -- 收集怪物所有状态效果
    local entries = {}

    -- 增益效果：暴怒（史莱姆国王大反击专属）
    if m._rageLayer and m._rageLayer > 0 then
        local mult = math.floor(m._rageLayer * 20)
        entries[#entries+1] = {
            name = "暴怒 x" .. m._rageLayer,
            desc = "全属性+" .. mult .. "%",
            color = {255, 100, 40}, isBuff = true,
        }
    end

    -- 增益效果：散射（迪哈塔暴怒散射）
    if m.rageScatter and m.rageScatter > 0 then
        entries[#entries+1] = {
            name = "散射 +" .. m.rageScatter,
            desc = "每次攻击额外打击" .. m.rageScatter .. "个目标",
            color = {255, 160, 40}, isBuff = true,
        }
    end

    -- 增益效果：战斗意志（迪哈塔专属）
    if m._dihataWillStacks and m._dihataWillStacks > 0 then
        entries[#entries+1] = {
            name = "战斗意志 x" .. m._dihataWillStacks,
            desc = "攻击速度+" .. m._dihataWillStacks,
            color = {60, 200, 255}, isBuff = true,
        }
    end

    -- 增益效果
    if m.prayerHealPct and m.prayerHealPct > 0 then
        entries[#entries+1] = {
            name = "祈祷", desc = "每回合回复" .. string.format("%.1f", m.prayerHealPct) .. "%HP",
            color = {220, 200, 60}, isBuff = true,
        }
    end
    if m.holySpringTurns and m.holySpringTurns > 0 then
        entries[#entries+1] = {
            name = "圣泉祝福", desc = "HP/MP回复 [" .. m.holySpringTurns .. "回合]",
            color = {60, 180, 200}, isBuff = true,
        }
    end
    if m.conquerTurns and m.conquerTurns > 0 then
        entries[#entries+1] = {
            name = "征服祝福", desc = "攻击力提升 [" .. m.conquerTurns .. "回合]",
            color = {200, 140, 40}, isBuff = true,
        }
    end
    if m.shelterTurns and m.shelterTurns > 0 then
        entries[#entries+1] = {
            name = "庇护祝福", desc = "防御力提升 [" .. m.shelterTurns .. "回合]",
            color = {120, 180, 60}, isBuff = true,
        }
    end
    if m.miracleTurns and m.miracleTurns > 0 then
        entries[#entries+1] = {
            name = "奇迹祝福", desc = "全属性提升 [" .. m.miracleTurns .. "回合]",
            color = {220, 220, 60}, isBuff = true,
        }
    end

    -- 减益效果
    if m.taunted and m.taunted > 0 then
        entries[#entries+1] = {
            name = "嘲讽", desc = "被嘲讽 [" .. m.taunted .. "回合]",
            color = {255, 80, 40}, isBuff = false,
        }
    end
    if m.stunned and m.stunned > 0 then
        entries[#entries+1] = {
            name = "眩晕", desc = "无法行动 [" .. m.stunned .. "回合]",
            color = {220, 190, 40}, isBuff = false,
        }
    end
    if m.poisoned and m.poisoned > 0 then
        entries[#entries+1] = {
            name = "中毒", desc = "持续受到毒素伤害 [" .. m.poisoned .. "回合]",
            color = {180, 80, 220}, isBuff = false,
        }
    end
    if m.armorBroken and m.armorBrokenTurns and m.armorBrokenTurns > 0 then
        entries[#entries+1] = {
            name = "破甲", desc = "防御力大幅降低 [" .. m.armorBrokenTurns .. "回合]",
            color = {40, 40, 40}, isBuff = false,
        }
    end
    if m.sandBlinded and m.sandBlindedTurns and m.sandBlindedTurns > 0 then
        entries[#entries+1] = {
            name = "致盲", desc = "命中率降低 [" .. m.sandBlindedTurns .. "回合]",
            color = {180, 160, 80}, isBuff = false,
        }
    end
    if m.noticeCritDmgTurns and m.noticeCritDmgTurns > 0 then
        entries[#entries+1] = {
            name = "暴击易伤", desc = "受到暴击伤害增加 [" .. m.noticeCritDmgTurns .. "回合]",
            color = {220, 180, 60}, isBuff = false,
        }
    end
    if GS.markedTarget == m then
        entries[#entries+1] = {
            name = "标记", desc = "被标记为优先目标",
            color = {240, 50, 40}, isBuff = false,
        }
    end
    if m.frozen and m.frozen > 0 then
        entries[#entries+1] = {
            name = "冰冻", desc = "无法行动 [" .. m.frozen .. "回合]",
            color = {80, 160, 240}, isBuff = false,
        }
    end
    if m.chilled and m.chilledTurns and m.chilledTurns > 0 then
        local csc = m.chillStacks or 1
        entries[#entries+1] = {
            name = "冻僵" .. (csc > 1 and (" x" .. csc) or ""),
            desc = "移速降低 [" .. m.chilledTurns .. "回合]" .. (csc > 1 and ("，共" .. csc .. "层，蒸腾+" .. (csc * 20) .. "%") or ""),
            color = {100, 190, 240}, isBuff = false,
        }
    end
    if m.burned and m.burnStacks and #m.burnStacks > 0 then
        local maxTurns = 0
        for _, st in ipairs(m.burnStacks) do if st.turns > maxTurns then maxTurns = st.turns end end
        local sc = #m.burnStacks
        entries[#entries+1] = {
            name = "灼烧" .. (sc > 1 and (" x" .. sc) or ""),
            desc = "持续受到火焰伤害 [最长" .. maxTurns .. "回合]" .. (sc > 1 and ("，共" .. sc .. "层") or ""),
            color = {255, 120, 40}, isBuff = false,
        }
    end

    -- 按增益/减益分类
    local buffEntries = {}
    local debuffEntries = {}
    for _, e in ipairs(entries) do
        if e.isBuff then buffEntries[#buffEntries+1] = e
        else debuffEntries[#debuffEntries+1] = e end
    end

    -- 计算面板实际高度
    local pad = 6
    local lineH = 15
    local titleH = 18
    local sepH = 6
    local contentH = titleH + sepH
    local function sectionH(title, list)
        if #list == 0 then return 0 end
        return lineH + 2 + #list * lineH  -- 小节标题 + 分隔线 + 条目
    end
    contentH = contentH + sectionH("增益", buffEntries)
    if #debuffEntries > 0 and #buffEntries > 0 then contentH = contentH + 4 end
    contentH = contentH + sectionH("减益", debuffEntries)
    if #entries == 0 then contentH = contentH + 30 end
    contentH = contentH + pad * 2

    local panelH = math.min(panelMaxH, contentH)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 6)
    nvgFillColor(vg, nvgRGBA(25, 18, 10, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 80, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 记录面板区域供点击检测
    GS.monsterBuffPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

    nvgFontFace(vg, "sans")

    -- 裁剪区域
    local clipY = panelY + titleH + sepH
    local clipH = panelH - titleH - sepH - pad
    nvgSave(vg)

    -- 标题（裁剪外绘制）
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 230, 170, 255))
    nvgText(vg, panelX + panelW / 2, panelY + pad + 6, (m.name or "怪物") .. " 状态效果", nil)

    -- 分隔线
    local sepY2 = panelY + titleH + 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 5, sepY2)
    nvgLineTo(vg, panelX + panelW - 5, sepY2)
    nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 内容裁剪
    nvgIntersectScissor(vg, panelX, clipY, panelW, clipH)

    local scrollOff = GS.monsterBuffScrollY or 0
    local drawY = clipY - scrollOff
    local contentX = panelX + pad
    local contentW = panelW - pad * 2

    if #entries == 0 then
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 130, 100, 180))
        nvgText(vg, panelX + panelW / 2, drawY + 15, "当前没有任何状态效果", nil)
        drawY = drawY + 30
    else
        local function drawSection(title, titleColor, list)
            if #list == 0 then return end
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(titleColor[1], titleColor[2], titleColor[3], 220))
            nvgText(vg, contentX, drawY + lineH / 2, "- " .. title, nil)
            drawY = drawY + lineH

            nvgBeginPath(vg)
            nvgMoveTo(vg, contentX, drawY)
            nvgLineTo(vg, contentX + contentW, drawY)
            nvgStrokeColor(vg, nvgRGBA(titleColor[1], titleColor[2], titleColor[3], 60))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
            drawY = drawY + 2

            for _, e in ipairs(list) do
                local nameColor = e.isBuff and {80, 200, 80} or {220, 70, 70}
                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                local midY2 = drawY + lineH / 2

                nvgFillColor(vg, nvgRGBA(nameColor[1], nameColor[2], nameColor[3], 255))
                nvgText(vg, contentX + 4, midY2, e.name, nil)

                if e.desc and e.desc ~= "" then
                    local nw = nvgTextBounds(vg, 0, 0, e.name, nil)
                    nvgFontSize(vg, 8)
                    nvgFillColor(vg, nvgRGBA(200, 190, 170, 230))
                    nvgText(vg, contentX + 4 + nw + 4, midY2, e.desc, nil)
                end
                drawY = drawY + lineH
            end
        end

        drawSection("增益效果", {120, 220, 100}, buffEntries)
        if #debuffEntries > 0 then
            if #buffEntries > 0 then drawY = drawY + 4 end
            drawSection("减益效果", {240, 80, 80}, debuffEntries)
        end
    end

    nvgRestore(vg)

    -- 滚动范围
    local totalH = drawY + scrollOff - clipY
    local maxScroll = math.max(0, totalH - clipH)
    GS.monsterBuffScrollY = math.max(0, math.min(GS.monsterBuffScrollY or 0, maxScroll))
    GS.monsterBuffMaxScroll = maxScroll

    -- 滚动条
    if maxScroll > 0 then
        local sbW = 3
        local sbX = panelX + panelW - sbW - 2
        local sbH = math.max(16, clipH * (clipH / totalH))
        local sbY = clipY + (clipH - sbH) * (scrollOff / maxScroll)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbX, sbY, sbW, sbH, sbW / 2)
        nvgFillColor(vg, nvgRGBA(60, 55, 50, 140))
        nvgFill(vg)
    end
end

-- ====================================================================
-- 绘制：训练场 DPT 统计面板
-- ====================================================================
function M.drawTrainingStats()
    local vg = M.vg
    local expanded = GS.trainingStatsExpanded

    -- 千分位格式化
    local function fmtNum(n)
        local s = tostring(n)
        local len = #s
        if len <= 3 then return s end
        local parts = {}
        local r = len % 3
        if r > 0 then parts[#parts + 1] = s:sub(1, r) end
        for i = r + 1, len, 3 do
            parts[#parts + 1] = s:sub(i, i + 2)
        end
        return table.concat(parts, ",")
    end

    -- 计算 DPT / DPL5T / DPL30T
    local turnCount = GS.trainingTurnCount
    local totalDmg = GS.trainingTotalDmg
    local log = GS.trainingDmgLog

    local dpt = 0
    if turnCount > 0 then
        dpt = math.floor(totalDmg / turnCount)
    end

    -- 面板尺寸根据展开/收起状态决定
    local pw = 170
    local ph = expanded and 122 or 60
    local px = GS.BOARD_X + 4
    local py = GS.BOARD_Y + 4

    -- 半透明背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 6)
    nvgFillColor(vg, nvgRGBA(15, 20, 40, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(220, 160, 60, 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 展开/收起按钮（面板左上角）
    local tbtnS = 16
    local tbtnX = px + 3
    local tbtnY = py + 3
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tbtnX, tbtnY, tbtnS, tbtnS, 3)
    nvgFillColor(vg, nvgRGBA(80, 60, 40, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 140, 50, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 240))
    nvgText(vg, tbtnX + tbtnS / 2, tbtnY + tbtnS / 2, expanded and "-" or "+", nil)
    GS.trainingToggleBtnRect = { x = tbtnX, y = tbtnY, w = tbtnS, h = tbtnS }

    -- 标题
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 160, 60, 240))
    nvgText(vg, px + pw / 2, py + 4, "伤害统计", nil)

    local goldColor = nvgRGBA(255, 220, 100, 240)
    local lx = px + 10
    local ly = py + 22

    -- DPT（始终显示）
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    nvgText(vg, lx, ly, "DPT      ", nil)
    nvgFillColor(vg, goldColor)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgText(vg, px + pw - 10, ly, fmtNum(dpt), nil)

    if expanded then
        -- DPL5T
        local dpl5t = 0
        if #log > 0 then
            local sum, cnt = 0, 0
            for i = math.max(1, #log - 4), #log do
                sum = sum + log[i]
                cnt = cnt + 1
            end
            dpl5t = math.floor(sum / cnt)
        end

        -- DPL30T
        local dpl30t = 0
        if #log > 0 then
            local sum, cnt = 0, 0
            for i = math.max(1, #log - 29), #log do
                sum = sum + log[i]
                cnt = cnt + 1
            end
            dpl30t = math.floor(sum / cnt)
        end

        ly = ly + 18
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        nvgText(vg, lx, ly, "DPL5T    ", nil)
        nvgFillColor(vg, goldColor)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgText(vg, px + pw - 10, ly, fmtNum(dpl5t), nil)

        ly = ly + 18
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        nvgText(vg, lx, ly, "DPL30T   ", nil)
        nvgFillColor(vg, goldColor)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgText(vg, px + pw - 10, ly, fmtNum(dpl30t), nil)

        -- 底部回合数
        ly = ly + 18
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(150, 150, 150, 180))
        nvgText(vg, px + pw / 2, ly, "回合: " .. turnCount .. "  总伤害: " .. fmtNum(totalDmg), nil)

        -- 重置按钮
        ly = ly + 16
    else
        -- 收起模式：DPT 下方直接放重置按钮
        ly = ly + 16
    end

    -- 重置按钮（展开/收起都显示）
    local btnW, btnH = 60, 18
    local btnX = px + pw / 2 - btnW / 2
    local btnY = ly
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
    nvgFillColor(vg, nvgRGBA(80, 60, 40, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(220, 160, 60, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 240))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "重置", nil)
    GS.trainingResetBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
end

-- ====================================================================
-- 绘制：训练假人等级面板（伤害统计面板正下方，左对齐，跟随展开/收起自适应）
-- ====================================================================
function M.drawTrainingLevelPanel()
    local vg = M.vg
    local tierIdx = GS.trainingDummyTierIdx or 1
    local tier = GS.TRAINING_DUMMY_TIERS[tierIdx]
    local tierMax = #GS.TRAINING_DUMMY_TIERS

    local pw, ph = 110, 46
    local statsPh = GS.trainingStatsExpanded and 122 or 60
    local px = GS.BOARD_X + 4
    local py = GS.BOARD_Y + 4 + statsPh + 4

    -- 半透明背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 6)
    nvgFillColor(vg, nvgRGBA(15, 20, 40, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(220, 160, 60, 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 160, 60, 240))
    nvgText(vg, px + pw / 2, py + 4, "假人等级", nil)

    -- ▼ | Lv## | ▲（水平排列）
    local ly = py + 20
    local arrowW, arrowH = 22, 20
    local lvDisplayW = 50
    local totalW = arrowW + lvDisplayW + arrowW
    local startX = px + (pw - totalW) / 2

    -- ▼ 降低等级
    local downX = startX
    local canDown = tierIdx > 1
    nvgBeginPath(vg)
    nvgRoundedRect(vg, downX, ly, arrowW, arrowH, 3)
    nvgFillColor(vg, canDown and nvgRGBA(80, 60, 40, 200) or nvgRGBA(60, 50, 40, 120))
    nvgFill(vg)
    nvgStrokeColor(vg, canDown and nvgRGBA(200, 140, 50, 180) or nvgRGBA(100, 80, 50, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, canDown and nvgRGBA(220, 200, 160, 240) or nvgRGBA(130, 120, 100, 150))
    nvgText(vg, downX + arrowW / 2, ly + arrowH / 2, "\xe2\x96\xbc", nil)
    GS.trainingLevelDownBtnRect = canDown and { x = downX, y = ly, w = arrowW, h = arrowH } or nil

    -- 等级数字
    local lvX = startX + arrowW
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 240, 180, 255))
    nvgText(vg, lvX + lvDisplayW / 2, ly + arrowH / 2, "Lv" .. (tier and tier.level or "?"), nil)

    -- ▲ 升高等级
    local upX = startX + arrowW + lvDisplayW
    local canUp = tierIdx < tierMax
    nvgBeginPath(vg)
    nvgRoundedRect(vg, upX, ly, arrowW, arrowH, 3)
    nvgFillColor(vg, canUp and nvgRGBA(80, 60, 40, 200) or nvgRGBA(60, 50, 40, 120))
    nvgFill(vg)
    nvgStrokeColor(vg, canUp and nvgRGBA(200, 140, 50, 180) or nvgRGBA(100, 80, 50, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, canUp and nvgRGBA(220, 200, 160, 240) or nvgRGBA(130, 120, 100, 150))
    nvgText(vg, upX + arrowW / 2, ly + arrowH / 2, "\xe2\x96\xb2", nil)
    GS.trainingLevelUpBtnRect = canUp and { x = upX, y = ly, w = arrowW, h = arrowH } or nil


end

-- ====================================================================
-- 绘制：设置面板
-- ====================================================================
function M.drawSettingsPanel()
    local vg = M.vg
    local px, py, pw, ph = GS.getSettingsPanelRect()

    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 8)
    nvgFillColor(vg, nvgRGBA(25, 30, 55, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 130, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    nvgText(vg, px + GS.SLIDER_TRACK_MARGIN_X, py + 18, "音量", nil)

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 170, 220, 200))
    local pct = math.floor(GS.masterVolume * 100)
    nvgText(vg, px + pw - GS.SLIDER_TRACK_MARGIN_X, py + 18, pct .. "%", nil)

    local trackX, trackY, trackW, trackH = GS.getSliderTrackRect()

    nvgBeginPath(vg)
    nvgRoundedRect(vg, trackX, trackY - trackH / 2, trackW, trackH, trackH / 2)
    nvgFillColor(vg, nvgRGBA(50, 55, 80, 200))
    nvgFill(vg)

    local fillW = trackW * GS.masterVolume
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, trackX, trackY - trackH / 2, fillW, trackH, trackH / 2)
        nvgFillColor(vg, nvgRGBA(80, 160, 255, 220))
        nvgFill(vg)
    end

    local knobX = trackX + fillW
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, trackY, GS.SLIDER_KNOB_R)
    nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 160, 255, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- ── 横竖屏开关（音量滑条下方） ──
    local orientToggleY = trackY + 18
    local toggleW = 36
    local toggleH = 18
    local toggleR = toggleH / 2
    local toggleX = px + pw - GS.SLIDER_TRACK_MARGIN_X - toggleW

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    nvgText(vg, px + GS.SLIDER_TRACK_MARGIN_X, orientToggleY + toggleH / 2, "横屏", nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, toggleX, orientToggleY, toggleW, toggleH, toggleR)
    if GS.forceLandscape then
        nvgFillColor(vg, nvgRGBA(80, 160, 255, 220))
    else
        nvgFillColor(vg, nvgRGBA(60, 65, 90, 220))
    end
    nvgFill(vg)

    local orientKnobR = toggleH / 2 - 2
    local orientKnobCX = GS.forceLandscape and (toggleX + toggleW - toggleR) or (toggleX + toggleR)
    nvgBeginPath(vg)
    nvgCircle(vg, orientKnobCX, orientToggleY + toggleH / 2, orientKnobR)
    nvgFillColor(vg, nvgRGBA(240, 245, 255, 255))
    nvgFill(vg)

    GS.orientToggleRect = { x = toggleX, y = orientToggleY, w = toggleW, h = toggleH }

    -- ── 动画开关（横屏开关下方） ──
    local animToggleY = orientToggleY + toggleH + 10

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    nvgText(vg, px + GS.SLIDER_TRACK_MARGIN_X, animToggleY + toggleH / 2, "动画", nil)

    -- 开关轨道
    nvgBeginPath(vg)
    nvgRoundedRect(vg, toggleX, animToggleY, toggleW, toggleH, toggleR)
    if GS.animationEnabled then
        nvgFillColor(vg, nvgRGBA(80, 160, 255, 220))
    else
        nvgFillColor(vg, nvgRGBA(60, 65, 90, 220))
    end
    nvgFill(vg)

    -- 开关圆形滑块
    local knobR2 = toggleH / 2 - 2
    local knobCX = GS.animationEnabled and (toggleX + toggleW - toggleR) or (toggleX + toggleR)
    nvgBeginPath(vg)
    nvgCircle(vg, knobCX, animToggleY + toggleH / 2, knobR2)
    nvgFillColor(vg, nvgRGBA(240, 245, 255, 255))
    nvgFill(vg)

    -- 存储开关热区供点击检测
    GS.animToggleRect = { x = toggleX, y = animToggleY, w = toggleW, h = toggleH }

    -- ── 伤害飘字开关（动画开关下方） ──
    local dmgToggleY = animToggleY + toggleH + 10

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    nvgText(vg, px + GS.SLIDER_TRACK_MARGIN_X, dmgToggleY + toggleH / 2, "伤害飘字", nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, toggleX, dmgToggleY, toggleW, toggleH, toggleR)
    if GS.showDamageNumbers then
        nvgFillColor(vg, nvgRGBA(80, 160, 255, 220))
    else
        nvgFillColor(vg, nvgRGBA(60, 65, 90, 220))
    end
    nvgFill(vg)

    local dmgKnobCX = GS.showDamageNumbers and (toggleX + toggleW - toggleR) or (toggleX + toggleR)
    nvgBeginPath(vg)
    nvgCircle(vg, dmgKnobCX, dmgToggleY + toggleH / 2, knobR2)
    nvgFillColor(vg, nvgRGBA(240, 245, 255, 255))
    nvgFill(vg)

    GS.dmgNumbersToggleRect = { x = toggleX, y = dmgToggleY, w = toggleW, h = toggleH }

    -- ── 屏幕震动开关（伤害飘字开关下方） ──
    local shakeToggleY = dmgToggleY + toggleH + 10

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    nvgText(vg, px + GS.SLIDER_TRACK_MARGIN_X, shakeToggleY + toggleH / 2, "屏幕震动", nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, toggleX, shakeToggleY, toggleW, toggleH, toggleR)
    if GS.enableScreenShake then
        nvgFillColor(vg, nvgRGBA(80, 160, 255, 220))
    else
        nvgFillColor(vg, nvgRGBA(60, 65, 90, 220))
    end
    nvgFill(vg)

    local shakeKnobCX = GS.enableScreenShake and (toggleX + toggleW - toggleR) or (toggleX + toggleR)
    nvgBeginPath(vg)
    nvgCircle(vg, shakeKnobCX, shakeToggleY + toggleH / 2, knobR2)
    nvgFillColor(vg, nvgRGBA(240, 245, 255, 255))
    nvgFill(vg)

    GS.shakeToggleRect = { x = toggleX, y = shakeToggleY, w = toggleW, h = toggleH }

    -- 按钮通用参数
    local btnMargin = GS.SLIDER_TRACK_MARGIN_X
    local nextBtnY = shakeToggleY + toggleH + 10
    local btnH2 = 24
    local btnR = 4
    local saveBtnX = px + btnMargin
    local testBtnW = pw - btnMargin * 2

    -- ── 手动保存按钮 ──
    local bigBtnH = 30
    do
        local sbY = nextBtnY
        GS._manualSaveBtnRect = { x = saveBtnX, y = sbY, w = testBtnW, h = bigBtnH }
        local isSaving = GS.cloudSaveStatus == "saving"
        local now = GetTime():GetElapsedTime()
        local saveCd = 3 - (now - (GS._lastManualSaveTime or 0))
        local onCooldown = saveCd > 0 and not isSaving
        local sbDisabled = isSaving or onCooldown
        local sbHovered = not sbDisabled and isHovered(saveBtnX, sbY, testBtnW, bigBtnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, sbY, testBtnW, bigBtnH, btnR)
        if sbDisabled then
            nvgFillColor(vg, nvgRGBA(40, 40, 50, 220))
        else
            nvgFillColor(vg, sbHovered and nvgRGBA(30, 65, 50, 240) or nvgRGBA(25, 50, 40, 220))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, sbY, testBtnW, bigBtnH, btnR)
        nvgStrokeColor(vg, sbDisabled and nvgRGBA(80, 80, 80, 150) or nvgRGBA(80, 180, 120, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if sbHovered then
            drawHoverHighlight(vg, saveBtnX, sbY, testBtnW, bigBtnH, btnR)
        end
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isSaving then
            nvgFillColor(vg, nvgRGBA(150, 150, 150, 200))
            nvgText(vg, saveBtnX + testBtnW / 2, sbY + bigBtnH / 2, "保存中...", nil)
        elseif onCooldown then
            nvgFillColor(vg, nvgRGBA(180, 160, 80, 200))
            nvgText(vg, saveBtnX + testBtnW / 2, sbY + bigBtnH / 2, "冷却 " .. math.ceil(saveCd) .. "s", nil)
        else
            nvgFillColor(vg, nvgRGBA(140, 220, 170, 255))
            nvgText(vg, saveBtnX + testBtnW / 2, sbY + bigBtnH / 2, "手动保存", nil)
        end
        nextBtnY = sbY + bigBtnH + 6
    end

    -- ── 兑换码按钮（所有用户可见） ──
    do
        local rbY = nextBtnY
        GS._redeemCodeBtnRect = { x = saveBtnX, y = rbY, w = testBtnW, h = bigBtnH }
        local rbHovered = isHovered(saveBtnX, rbY, testBtnW, bigBtnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, rbY, testBtnW, bigBtnH, btnR)
        nvgFillColor(vg, rbHovered and nvgRGBA(60, 50, 80, 240) or nvgRGBA(45, 38, 60, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, rbY, testBtnW, bigBtnH, btnR)
        nvgStrokeColor(vg, nvgRGBA(160, 140, 200, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if rbHovered then
            drawHoverHighlight(vg, saveBtnX, rbY, testBtnW, bigBtnH, btnR)
        end
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(210, 200, 240, 255))
        nvgText(vg, saveBtnX + testBtnW / 2, rbY + bigBtnH / 2, "兑换码", nil)
        nextBtnY = rbY + bigBtnH + 6
    end

    -- ── 修改姓名按钮 ──
    do
        local rnY = nextBtnY
        GS._renameBtnRect = { x = saveBtnX, y = rnY, w = testBtnW, h = bigBtnH }
        local rnHovered = isHovered(saveBtnX, rnY, testBtnW, bigBtnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, rnY, testBtnW, bigBtnH, btnR)
        nvgFillColor(vg, rnHovered and nvgRGBA(50, 60, 40, 240) or nvgRGBA(38, 48, 30, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, rnY, testBtnW, bigBtnH, btnR)
        nvgStrokeColor(vg, nvgRGBA(140, 180, 100, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if rnHovered then
            drawHoverHighlight(vg, saveBtnX, rnY, testBtnW, bigBtnH, btnR)
        end
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 220, 140, 255))
        nvgText(vg, saveBtnX + testBtnW / 2, rnY + bigBtnH / 2, "修改姓名", nil)
        nextBtnY = rnY + bigBtnH + 6
    end

    -- ── 息屏挂机按钮 ──
    do
        local soY = nextBtnY
        GS._screenOffBtnRect = { x = saveBtnX, y = soY, w = testBtnW, h = bigBtnH }
        local soHovered = isHovered(saveBtnX, soY, testBtnW, bigBtnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, soY, testBtnW, bigBtnH, btnR)
        nvgFillColor(vg, soHovered and nvgRGBA(40, 40, 60, 240) or nvgRGBA(30, 30, 50, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, soY, testBtnW, bigBtnH, btnR)
        nvgStrokeColor(vg, nvgRGBA(140, 140, 180, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if soHovered then
            drawHoverHighlight(vg, saveBtnX, soY, testBtnW, bigBtnH, btnR)
        end
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 220, 255))
        nvgText(vg, saveBtnX + testBtnW / 2, soY + bigBtnH / 2, "息屏挂机", nil)
        nextBtnY = soY + bigBtnH + 6
    end

    -- ── 脱离卡死按钮（仅副本中显示） ──
    if GS.isDungeon then
        local ubY = nextBtnY
        GS._unstuckBtnRect = { x = saveBtnX, y = ubY, w = testBtnW, h = bigBtnH }
        local ubHovered = isHovered(saveBtnX, ubY, testBtnW, bigBtnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, ubY, testBtnW, bigBtnH, btnR)
        nvgFillColor(vg, ubHovered and nvgRGBA(80, 60, 30, 240) or nvgRGBA(60, 45, 20, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, saveBtnX, ubY, testBtnW, bigBtnH, btnR)
        nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if ubHovered then
            drawHoverHighlight(vg, saveBtnX, ubY, testBtnW, bigBtnH, btnR)
        end
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 220, 140, 255))
        nvgText(vg, saveBtnX + testBtnW / 2, ubY + bigBtnH / 2, "脱离卡死", nil)
        nextBtnY = ubY + bigBtnH + 6
    else
        GS._unstuckBtnRect = nil
    end

    -- 返回角色选择界面按钮（所有玩家可见）
    local charSelBtnY = nextBtnY
    GS.charSelectBtnRect = { x = saveBtnX, y = charSelBtnY, w = testBtnW, h = bigBtnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, saveBtnX, charSelBtnY, testBtnW, bigBtnH, btnR)
    nvgFillColor(vg, nvgRGBA(80, 40, 40, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 100, 80, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    if isHovered(saveBtnX, charSelBtnY, testBtnW, bigBtnH) then
        drawHoverHighlight(vg, saveBtnX, charSelBtnY, testBtnW, bigBtnH, btnR)
    end
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 180, 160, 255))
    nvgText(vg, saveBtnX + testBtnW / 2, charSelBtnY + bigBtnH / 2, "返回角色选择界面", nil)

    -- 用户 ID 显示（设置面板最底部）
    local uid = clientCloud and clientCloud.userId or 0
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 120))
    nvgText(vg, saveBtnX + testBtnW / 2, charSelBtnY + bigBtnH + 12, "id：" .. tostring(uid), nil)


end

-- ====================================================================
-- 绘制：GM 管理面板（独立于设置面板）
-- ====================================================================
function M.drawGMPanel()
    local vg = M.vg
    local px, py, pw, ph = GS.getGMPanelRect()

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 8)
    nvgFillColor(vg, nvgRGBA(30, 25, 20, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")

    -- 标题
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 230))
    nvgText(vg, px + pw / 2, py + 14, "GM 管理面板", nil)

    -- 按钮通用参数：统一2列布局
    local btnMargin = GS.SLIDER_TRACK_MARGIN_X
    local btnH = 24
    local btnR = 4
    local btnGap = 4
    local leftX = px + btnMargin
    local totalW = pw - btnMargin * 2
    local halfW = (totalW - btnGap) / 2
    local rowY = py + 28

    -- 辅助函数：绘制GM按钮
    local function drawBtn(bx, by, bw, label, baseColor, textColor)
        local hovered = isHovered(bx, by, bw, btnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, btnH, btnR)
        local r, g, b = baseColor[1], baseColor[2], baseColor[3]
        nvgFillColor(vg, hovered and nvgRGBA(r + 20, g + 20, b + 20, 240) or nvgRGBA(r, g, b, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, btnH, btnR)
        nvgStrokeColor(vg, nvgRGBA(r + 60, g + 60, b + 30, 160))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        if hovered then
            drawHoverHighlight(vg, bx, by, bw, btnH, btnR)
        end
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(textColor[1], textColor[2], textColor[3], 255))
        nvgText(vg, bx + bw / 2, by + btnH / 2, label, nil)
        return { x = bx, y = by, w = bw, h = btnH }
    end

    local rightX = leftX + halfW + btnGap
    local baseGold = { 80, 60, 30 }
    local textGold = { 255, 220, 140 }
    local baseTeal = { 30, 60, 60 }
    local textTeal = { 140, 220, 220 }
    local baseRed  = { 80, 30, 30 }
    local textRed  = { 255, 160, 140 }
    local basePurp = { 50, 30, 60 }
    local textPurp = { 200, 160, 240 }
    local baseGreen = { 30, 60, 30 }
    local textGreen = { 140, 220, 140 }

    -- Row 1: 测试关卡 | 测试道具
    GS.testStageBtnRect = drawBtn(leftX, rowY, halfW, "测试关卡", baseGold, textGold)
    GS.testItemBtnRect  = drawBtn(rightX, rowY, halfW, "测试道具", baseGold, textGold)
    rowY = rowY + btnH + btnGap

    -- Row 2: 天气 | 职业
    local wLabel = "天气"
    if GS.isRaining then wLabel = "天气:雨"
    elseif GS.isWindy then wLabel = "天气:风"
    elseif GS.isScorching then wLabel = "天气:晒"
    end
    GS.testWeatherBtnRect = drawBtn(leftX, rowY, halfW, wLabel, baseTeal, textTeal)
    local classLabel = "职业:" .. (GS.currentClass and string.sub(GS.currentClass, 1, 6) or "?")
    GS.classSwitchBtnRect = drawBtn(rightX, rowY, halfW, classLabel, baseTeal, textTeal)
    rowY = rowY + btnH + btnGap

    -- Row 3: 家园 | 等级
    local homeLabel = "家:" .. (GS.homeType == "small" and "S" or GS.homeType == "medium" and "M" or "L")
    GS.testHomeBtnRect = drawBtn(leftX, rowY, halfW, homeLabel, baseTeal, textTeal)
    local rankLetters = { "F", "E", "D", "C", "B", "A", "S", "G" }
    local rankLabel = "等级:" .. (rankLetters[GS.adventurerRank or 1] or "?")
    GS.testRankBtnRect = drawBtn(rightX, rowY, halfW, rankLabel, basePurp, textPurp)
    rowY = rowY + btnH + btnGap

    -- Row 4: 签到模式 | 清任务
    local signLabel = GS.debugForceDay6 and "签到:日常" or "签到:5天"
    GS.testSignInModeBtnRect = drawBtn(leftX, rowY, halfW, signLabel, basePurp, textPurp)
    GS.testBrawlBtnRect     = drawBtn(rightX, rowY, halfW, "清任务", baseRed, textRed)
    rowY = rowY + btnH + btnGap

    -- Row 5: 伴侣 | 精灵
    local partnerLabel = "伴侣"
    if GS.partnerNpcKey then
        local pInfo = GS.NPC_REGISTRY and GS.NPC_REGISTRY[GS.partnerNpcKey]
        partnerLabel = "伴:" .. (pInfo and string.sub(pInfo.name, 1, 6) or "?")
    end
    GS.testPartnerBtnRect = drawBtn(leftX, rowY, halfW, partnerLabel, basePurp, textPurp)
    local elfLabel = GS.debugElfUnlimitedRolls and "精灵:无限" or "精灵:1/日"
    GS.testElfBtnRect = drawBtn(rightX, rowY, halfW, elfLabel, baseGreen, textGreen)
    rowY = rowY + btnH + btnGap

    -- Row 6: LV- | LV+
    GS.testLvDownBtnRect = drawBtn(leftX, rowY, halfW, "LV-", baseRed, textRed)
    GS.testLvUpBtnRect   = drawBtn(rightX, rowY, halfW, "LV+", baseGreen, textGreen)
    rowY = rowY + btnH + btnGap

    -- Row 7: +1h | 红龙
    GS.testTimeBtnRect   = drawBtn(leftX, rowY, halfW, "+1h", baseTeal, textTeal)
    local dragonKilled = GS.monsterKillCounts and (GS.monsterKillCounts["red_dragon_young"] or 0) > 0
    local dragonLabel = dragonKilled and "龙:已杀" or "龙:未杀"
    GS.testDragonBtnRect = drawBtn(rightX, rowY, halfW, dragonLabel, baseRed, textRed)
    rowY = rowY + btnH + btnGap

    -- Row 8: 背包+10 | 解锁深渊/塔
    local bagLabel = "背包+" .. 10 .. " (" .. GS.bagSlots .. "格)"
    GS.testBagExpandBtnRect = drawBtn(leftX, rowY, halfW, bagLabel, baseGreen, textGreen)
    local unlockLabel = (GS.abyssUnlocked and GS.infiniteTowerUnlocked) and "深渊/塔:已开" or "解锁深渊/塔"
    GS.testUnlockAbyssBtnRect = drawBtn(rightX, rowY, halfW, unlockLabel, basePurp, textPurp)
    rowY = rowY + btnH + btnGap

    -- Row 9: 生活技能等级切换（全宽按钮）
    local curLifeHLv = GS.getLifeSkillHiddenLevel("gathering")
    local lifeLabel = "生活技能:" .. curLifeHLv
    GS.testLifeSkillBtnRect = drawBtn(leftX, rowY, totalW, lifeLabel, baseTeal, textTeal)
    rowY = rowY + btnH + btnGap

    -- Row 10: 上传反作弊时间（全宽按钮，显示当前时间戳）
    local SignInSystem = require("SignInSystem")
    local adminT = SignInSystem._adminTime
    local adminLabel = "上传时间:" .. (adminT and os.date("%m/%d %H:%M", adminT) or "未加载")
    GS.testUploadTimeBtnRect = drawBtn(leftX, rowY, totalW, adminLabel, baseTeal, textTeal)
    rowY = rowY + btnH + btnGap

    -- Row 11: 上传版本号到排行榜（全宽，橙色警示）
    local baseOrange = { 90, 50, 10 }
    local textOrange = { 255, 200, 100 }
    local curVer = GS.APP_VERSION or "ver0.126"
    local uploadStatus = GS.gmVersionUploadStatus  -- nil / "uploading" / "ok" / "fail"
    local verLabel
    if uploadStatus == "uploading" then
        verLabel = "上传版本号…"
    elseif uploadStatus == "ok" then
        verLabel = "已上传: " .. curVer
    elseif uploadStatus == "fail" then
        verLabel = "上传失败，重试"
    else
        verLabel = "上传版本号: " .. curVer
    end
    GS.testUploadVersionBtnRect = drawBtn(leftX, rowY, totalW, verLabel, baseOrange, textOrange)
    rowY = rowY + btnH + btnGap

end

-- ====================================================================
-- 绘制：测试关卡选择面板
-- ====================================================================
function M.drawTestStagePanel()
    local vg = M.vg
    nvgFontFace(vg, "sans")

    local settingsRect = { GS.getGMPanelRect() }
    local spx, spy, spw, sph = settingsRect[1], settingsRect[2], settingsRect[3], settingsRect[4]

    -- 面板在GM面板右侧
    local pw = 160
    local maxVisibleItems = 8
    local itemH = 26
    local gap = 3
    local pad = 6
    local totalStages = #GS.MONSTER_ORDER  -- 只显示怪物测试关卡（不含地图关卡/采集/副本）
    local contentH = totalStages * (itemH + gap) + pad * 2
    local ph = math.min(contentH + pad * 2, maxVisibleItems * (itemH + gap) + pad * 2)

    local px = spx + spw + 4
    local py = spy

    -- 如果右侧空间不够，放到设置面板下方
    if px + pw > GS.SCREEN_W - 4 then
        px = spx
        py = spy + sph + 4
    end
    if py + ph > GS.SCREEN_H - 4 then
        ph = GS.SCREEN_H - 4 - py
    end

    GS.testStagePanelRect = { x = px, y = py, w = pw, h = ph }

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 6)
    nvgFillColor(vg, nvgRGBA(25, 30, 50, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 60, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 裁剪绘制内容区域
    local clipX = px + pad
    local clipY = py + pad
    local clipW = pw - pad * 2
    local clipH = ph - pad * 2

    local scrollMax = math.max(0, contentH - clipH)
    GS.testStageScrollY = math.max(0, math.min(GS.testStageScrollY, scrollMax))

    nvgSave(vg)
    nvgScissor(vg, clipX, clipY, clipW, clipH)

    local startY = clipY - GS.testStageScrollY
    GS.testStageBtnRects = {}

    for i = 1, totalStages do
        local stage = GS.STAGE_DEFS[i]
        local mdef = stage.monsters[1] and stage.monsters[1].def
        local btnY = startY + (i - 1) * (itemH + gap)

        if btnY + itemH >= clipY and btnY <= clipY + clipH then
            local btnX = clipX
            local btnW = clipW
            local isCurrent = (i == GS.currentStage)
            local mc = mdef and mdef.color or {150, 150, 150}

            -- 按钮背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, itemH, 4)
            if isCurrent then
                nvgFillColor(vg, nvgRGBA(80, 100, 60, 200))
            else
                nvgFillColor(vg, nvgRGBA(50, 40, 30, 160))
            end
            nvgFill(vg)

            if isCurrent then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX, btnY, btnW, itemH, 4)
                nvgStrokeColor(vg, nvgRGBA(150, 200, 100, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end

            -- 怪物小图标
            local iconX = btnX + 3
            local iconY = btnY + 2
            local iconSize = itemH - 4
            local mImg = mdef and mdef.image and ImageManager.lazyGet("monster", mdef.image) or nil
            if mImg == -1 then mImg = nil end
            if mImg then
                local imgPaint = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, mImg, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 3)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX + 2, iconY + 2, iconSize - 4, iconSize - 4, 3)
                nvgFillColor(vg, nvgRGBA(mc[1], mc[2], mc[3], 220))
                nvgFill(vg)
            end

            local midY = btnY + itemH / 2

            -- 怪物名称
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            drawTextOutlined(vg, btnX + itemH, midY, stage.name, 50, 30, 10, 230)

            -- 等级
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            local lvText = mdef and ("Lv." .. mdef.level) or ""
            if isCurrent then
                drawTextOutlined(vg, btnX + btnW - 4, midY, lvText .. " ●", 20, 120, 20, 220)
            else
                drawTextOutlined(vg, btnX + btnW - 4, midY, lvText, 80, 60, 35, 180)
            end

            GS.testStageBtnRects[#GS.testStageBtnRects + 1] = { x = btnX, y = btnY, w = btnW, h = itemH, stageIdx = i }
        end
    end

    -- 滚动条
    if scrollMax > 0 then
        local barW = 3
        local barX = clipX + clipW - barW - 1
        local barAreaH = clipH - 4
        local thumbH = math.max(12, barAreaH * clipH / contentH)
        local thumbY = clipY + 2 + (barAreaH - thumbH) * (GS.testStageScrollY / scrollMax)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, clipY + 2, barW, barAreaH, 1.5)
        nvgFillColor(vg, nvgRGBA(40, 30, 20, 80))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, barW, thumbH, 1.5)
        nvgFillColor(vg, nvgRGBA(160, 140, 60, 180))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

-- ====================================================================
-- 绘制：测试道具面板（列出所有稀有装备，点击可发放到背包）
-- ====================================================================
function M.drawTestItemPanel()
    local vg = M.vg
    nvgFontFace(vg, "sans")

    -- 构建测试道具列表（缓存）
    if not GS.testItemList then
        GS.testItemList = {}
        -- 材料 ID 集合（锭 + 精炼石 + 矿石）
        local materialIds = {
            -- 锭
            iron_ingot = true, copper_ingot = true, silver_ingot = true,
            gold_ingot = true, blue_silver_ingot = true,
            radiant_gold_ingot = true, black_steel_ingot = true,
            mithril_ingot = true, true_silver_ingot = true, true_gold_ingot = true,
            -- 精炼石
            refine_stone_2 = true, refine_stone_3 = true, refine_stone_4 = true,
            refine_stone_5 = true, refine_stone_6 = true, refine_stone_7 = true,
            refine_stone_8 = true, refine_stone_9 = true, refine_stone_10 = true,
            -- 金属矿石
            crude_iron_ore = true, tongkuang = true, yinkuang = true,
            jinkuangshi = true, lanyinkuangshi = true, huijinkuangshi = true,
            heigangkuangshi = true, miyinkuangshi = true,
            zhenyinkuangshi = true, zhenjinkuangshi = true,
            -- 碎裂晶矿
            zishuijing_cujing = true, hongshuijing_cujing = true,
            huangshuijing_cujing = true, lanshuijing_cujing = true,
            lvshuijing_cujing = true, heishuijing_cujing = true,
            baishuijing_cujing = true, fenshuijing_cujing = true,
            -- 完整晶矿
            fenshuijing_wanzheng = true, hongshuijing_wanzheng = true,
            huangshuijing_wanzheng = true, lanshuijing_wanzheng = true,
            lvshuijing_wanzheng = true, heishuijing_wanzheng = true,
            baishuijing_wanzheng = true, zishuijing_wanzheng = true,
            -- 纯净晶矿
            zishuijing_chunjing = true, fenshuijing_chunjing = true,
            hongshuijing_chunjing = true, huangshuijing_chunjing = true,
            lanshuijing_chunjing = true, lvshuijing_chunjing = true,
            heishuijing_chunjing = true, baishuijing_chunjing = true,
            -- 闪耀晶矿
            hongshuijing_shanyao = true, huangshuijing_shanyao = true,
            lanshuijing_shanyao = true, lvshuijing_shanyao = true,
            heishuijing_shanyao = true, baishuijing_shanyao = true,
            zishuijing_shanyao = true, fenshuijing_shanyao = true,
        }
        -- 分类收集
        local materials = {}  -- 锭 + 精炼石
        local equips = {}     -- 装备
        local gems = {}       -- 宝石
        for id, tpl in pairs(GS.itemTemplates) do
            if materialIds[id] then
                materials[#materials + 1] = { id = id, name = tpl.name, icon = tpl.icon, level = tpl.level or 0 }
            elseif tpl.category == "宝石" then
                gems[#gems + 1] = { id = id, name = tpl.name, icon = tpl.icon, level = tpl.level or 0 }
            elseif (tpl.rarity == "rare" or tpl.rarity == "fine" or tpl.rarity == "superior") and tpl.slot then
                equips[#equips + 1] = { id = id, name = tpl.name, icon = tpl.icon, level = tpl.level or 0, rarity = tpl.rarity or "common" }
            end
        end
        -- 烹饪产成品
        local cookItems = {}
        for _, recipe in ipairs(GS.COOKING_RECIPES) do
            local tpl = GS.itemTemplates[recipe.outputId]
            if tpl then
                cookItems[#cookItems + 1] = { id = recipe.outputId, name = tpl.name, icon = tpl.icon, level = recipe.cookingLevel or 0 }
            end
        end
        -- 材料按等级排序
        table.sort(materials, function(a, b) return a.level < b.level end)
        -- 宝石按等级排序
        table.sort(gems, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            return a.name < b.name
        end)
        -- 烹饪产成品按烹饪等级排序
        table.sort(cookItems, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            return a.name < b.name
        end)
        -- 装备按稀有度>等级排序（稀有度高的在下面）
        local RARITY_RANK = { common = 1, uncommon = 2, rare = 3, fine = 4, superior = 5, epic = 6, legendary = 7, divine = 8 }
        table.sort(equips, function(a, b)
            local ra = RARITY_RANK[a.rarity] or 0
            local rb = RARITY_RANK[b.rarity] or 0
            if ra ~= rb then return ra < rb end
            if a.level ~= b.level then return a.level < b.level end
            return a.name < b.name
        end)

        -- 金币条目
        GS.testItemList[#GS.testItemList + 1] = {
            id = "@gold_100k",
            name = "获取10万金币",
            icon = nil,
            special = "gold_100k",
        }
        -- 深渊积分条目
        GS.testItemList[#GS.testItemList + 1] = {
            id = "@abyss_points_100",
            name = "100深渊积分",
            icon = nil,
            special = "abyss_points_100",
        }
        -- 感恩礼券条目
        GS.testItemList[#GS.testItemList + 1] = {
            id = "gratitude_ticket",
            name = "感恩礼券 ×99",
            icon = GS.itemTemplates["gratitude_ticket"] and GS.itemTemplates["gratitude_ticket"].icon or nil,
        }
        -- 卓越宝石自选箱
        local gemPackTpl = GS.itemTemplates["superior_gem_pack"]
        if gemPackTpl then
            GS.testItemList[#GS.testItemList + 1] = { id = "superior_gem_pack", name = gemPackTpl.name, icon = gemPackTpl.icon, level = 0 }
        end
        -- 冒险英雄副手自选包
        local offhandPackTpl = GS.itemTemplates["hero_offhand_pack"]
        if offhandPackTpl then
            GS.testItemList[#GS.testItemList + 1] = { id = "hero_offhand_pack", name = offhandPackTpl.name, icon = offhandPackTpl.icon, level = 0 }
        end
        -- 雕刻工具
        for _, toolId in ipairs({"refine_slot_tool", "socket_drill_tool"}) do
            local toolTpl = GS.itemTemplates[toolId]
            if toolTpl then
                GS.testItemList[#GS.testItemList + 1] = { id = toolId, name = toolTpl.name, icon = toolTpl.icon, level = 0 }
            end
        end
        -- 神炼系列
        for _, agentId in ipairs({"divine_enchant_agent", "divine_catalyst", "divine_repair_agent", "divine_toughness_agent"}) do
            local agentTpl = GS.itemTemplates[agentId]
            if agentTpl then
                GS.testItemList[#GS.testItemList + 1] = { id = agentId, name = agentTpl.name, icon = agentTpl.icon, level = 0 }
            end
        end
        -- 幼年果冻戒指
        local jellyRingTpl = GS.itemTemplates["jelly_ring_young"]
        if jellyRingTpl then
            GS.testItemList[#GS.testItemList + 1] = { id = "jelly_ring_young", name = jellyRingTpl.name, icon = jellyRingTpl.icon, level = 0 }
        end
        -- 阅读物
        for _, bookId in ipairs({"elfvah_language_book_1", "elfvah_language_book_2", "elfvah_language_book_3"}) do
            local tpl = GS.itemTemplates[bookId]
            if tpl then
                GS.testItemList[#GS.testItemList + 1] = { id = bookId, name = tpl.name, icon = tpl.icon, level = tpl.level or 0 }
            end
        end
        -- 材料（锭+精炼石）
        for _, v in ipairs(materials) do
            GS.testItemList[#GS.testItemList + 1] = v
        end
        -- 宝石
        for _, v in ipairs(gems) do
            GS.testItemList[#GS.testItemList + 1] = v
        end
        -- "朱莉"的面纱 × 10种深渊词缀变体
        local veilTpl = GS.itemTemplates["gem_rainbow_masterwork"]
        if veilTpl and GS.ABYSS_AFFIX_POOL then
            for _, affix in ipairs(GS.ABYSS_AFFIX_POOL) do
                GS.testItemList[#GS.testItemList + 1] = {
                    id = "gem_rainbow_masterwork",
                    name = "面纱[" .. affix.name .. "]",
                    icon = veilTpl.icon,
                    level = veilTpl.level or 100,
                    abyssAffixOverride = affix,
                }
            end
        end
        -- 烹饪产成品
        for _, v in ipairs(cookItems) do
            GS.testItemList[#GS.testItemList + 1] = v
        end
        -- 装备
        for _, v in ipairs(equips) do
            GS.testItemList[#GS.testItemList + 1] = v
        end
    end

    local settingsRect = { GS.getGMPanelRect() }
    local spx, spy, spw, sph = settingsRect[1], settingsRect[2], settingsRect[3], settingsRect[4]

    local pw = 160
    local maxVisibleItems = 8
    local itemH = 26
    local gap = 3
    local pad = 6
    local totalItems = #GS.testItemList
    local contentH = totalItems * (itemH + gap) + pad * 2
    local ph = math.min(contentH + pad * 2, maxVisibleItems * (itemH + gap) + pad * 2)

    local px = spx + spw + 4
    local py = spy

    if px + pw > GS.SCREEN_W - 4 then
        px = spx
        py = spy + sph + 4
    end
    if py + ph > GS.SCREEN_H - 4 then
        ph = GS.SCREEN_H - 4 - py
    end

    GS.testItemPanelRect = { x = px, y = py, w = pw, h = ph }

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 6)
    nvgFillColor(vg, nvgRGBA(25, 35, 50, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 160, 180, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 裁剪绘制内容区域
    local clipX = px + pad
    local clipY = py + pad
    local clipW = pw - pad * 2
    local clipH = ph - pad * 2

    GS.testItemScrollY = GS.testItemScrollY or 0
    local scrollMax = math.max(0, contentH - clipH)
    GS.testItemScrollY = math.max(0, math.min(GS.testItemScrollY, scrollMax))

    nvgSave(vg)
    nvgScissor(vg, clipX, clipY, clipW, clipH)

    local startY = clipY - GS.testItemScrollY
    GS.testItemBtnRects = {}

    for i = 1, totalItems do
        local entry = GS.testItemList[i]
        local btnY = startY + (i - 1) * (itemH + gap)

        if btnY + itemH >= clipY and btnY <= clipY + clipH then
            local btnX = clipX
            local btnW = clipW

            -- 按钮背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, itemH, 4)
            nvgFillColor(vg, nvgRGBA(50, 50, 60, 160))
            nvgFill(vg)

            -- hover 效果
            if isHovered(btnX, btnY, btnW, itemH) then
                drawHoverHighlight(vg, btnX, btnY, btnW, itemH, 4)
            end

            -- 图标
            local iconX = btnX + 3
            local iconY2 = btnY + 2
            local iconSize = itemH - 4
            local img = entry.icon and ImageManager.lazyGet("item", entry.icon) or nil
            if img == -1 then img = nil end
            if img then
                local imgPaint = nvgImagePattern(vg, iconX, iconY2, iconSize, iconSize, 0, img, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX, iconY2, iconSize, iconSize, 3)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX + 2, iconY2 + 2, iconSize - 4, iconSize - 4, 3)
                nvgFillColor(vg, nvgRGBA(60, 160, 180, 200))
                nvgFill(vg)
            end

            -- 名称
            local midY = btnY + itemH / 2
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            drawTextOutlined(vg, btnX + itemH, midY, entry.name, 60, 180, 220, 230)

            GS.testItemBtnRects[#GS.testItemBtnRects + 1] = { x = btnX, y = btnY, w = btnW, h = itemH, itemId = entry.id, special = entry.special, abyssAffixOverride = entry.abyssAffixOverride }
        end
    end

    -- 滚动条（可拖动）
    if scrollMax > 0 then
        local barW = 6
        local barX = clipX + clipW - barW - 1
        local barAreaH = clipH - 4
        local barAreaY = clipY + 2
        local thumbH = math.max(16, barAreaH * clipH / contentH)
        local thumbY = barAreaY + (barAreaH - thumbH) * (GS.testItemScrollY / scrollMax)
        -- 存储滚动条几何信息供拖动使用
        GS.testItemScrollbar = {
            x = barX, y = barAreaY, w = barW, h = barAreaH,
            thumbY = thumbY, thumbH = thumbH, scrollMax = scrollMax,
        }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barAreaY, barW, barAreaH, 3)
        nvgFillColor(vg, nvgRGBA(40, 30, 20, 80))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, barW, thumbH, 3)
        nvgFillColor(vg, nvgRGBA(60, 160, 180, GS.testItemScrollbarDragging and 255 or 180))
        nvgFill(vg)
    else
        GS.testItemScrollbar = nil
    end

    nvgRestore(vg)
end

-- ====================================================================
-- 绘制：自动战斗设置面板
-- ====================================================================
function M.drawAutoBattleSettingsPanel()
    local vg = M.vg
    nvgFontFace(vg, "sans")

    -- 面板定位：在自动设置按钮下方
    local btnRect = GS.autoBattleSettingsBtnRect
    if not btnRect then return end

    local slotSize = 36
    local slotGap = 6
    local padX = 14
    local padTop = 12
    local padBot = 18
    local sectionGap = 10
    local labelH = 18

    -- 面板宽度：容纳5个技能槽，但不超过屏幕
    local pw = padX * 2 + slotSize * 5 + slotGap * 4
    if pw > GS.SCREEN_W - 8 then
        -- 屏幕太窄时缩小槽位
        slotSize = math.floor((GS.SCREEN_W - 8 - padX * 2 - slotGap * 4) / 5)
        pw = padX * 2 + slotSize * 5 + slotGap * 4
    end
    -- 面板高度
    local titleH = 26
    local skillNameH = 12
    local consLabelH = 16
    local thresholdH = 16
    local ph = padTop + titleH + labelH + slotSize + skillNameH + sectionGap
             + labelH + slotSize + consLabelH + thresholdH + sectionGap
             + labelH + slotSize + consLabelH + padBot

    -- 面板左对齐到自动设置按钮左侧
    local px = btnRect.x
    local py = btnRect.y + btnRect.h + 4
    if px + pw > GS.SCREEN_W - 4 then px = GS.SCREEN_W - 4 - pw end
    if px < 4 then px = 4 end

    GS.autoBattleSettingsPanelRect = { x = px, y = py, w = pw, h = ph }

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 6)
    nvgFillColor(vg, nvgRGBA(20, 25, 45, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 140, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    local curY = py + padTop
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 210, 180, 240))
    nvgText(vg, px + pw / 2, curY + titleH / 2, "自动战斗设置", nil)
    curY = curY + titleH

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 8, curY)
    nvgLineTo(vg, px + pw - 8, curY)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 140, 100))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- ---- 自动技能区域 ----
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 170, 210, 200))
    nvgText(vg, px + padX, curY + labelH / 2, "自动技能", nil)
    -- 补充说明
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, px + pw - padX, curY + labelH / 2, "从左向右依次检索施展", nil)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(160, 170, 210, 200))
    curY = curY + labelH

    local skillStartX = px + padX
    GS.activeSkillSlotAreas = {}
    for i = 1, GS.ACTIVE_SKILL_SLOTS do
        local sx = skillStartX + (i - 1) * (slotSize + slotGap)
        local sy = curY
        GS.activeSkillSlotAreas[i] = { x = sx, y = sy, w = slotSize, h = slotSize }

        local sr = math.max(2, math.floor(slotSize * 0.12))

        -- 外框描边
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - 1, sy - 1, slotSize + 2, slotSize + 2, sr + 1)
        nvgStrokeColor(vg, nvgRGBA(90, 65, 30, 220))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 内凹底色
        local slotGrad = nvgLinearGradient(vg, sx, sy, sx, sy + slotSize,
            nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, slotSize, sr)
        nvgFillPaint(vg, slotGrad)
        nvgFill(vg)

        -- 上边内阴影
        local shadowH = math.max(2, math.floor(slotSize * 0.2))
        local topShadow = nvgLinearGradient(vg, sx, sy, sx, sy + shadowH,
            nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, shadowH, sr)
        nvgFillPaint(vg, topShadow)
        nvgFill(vg)

        -- 底部微光
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + sr, sy + slotSize - 1)
        nvgLineTo(vg, sx + slotSize - sr, sy + slotSize - 1)
        nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 技能图标或编号
        local skillId = GS.activeSkills[i]
        local def = skillId and GS.SKILL_DEFS[skillId]
        if def then
            local sImg = M.skillImages and M.skillImages[skillId]
            if sImg and sImg ~= -1 then
                local imgPat = nvgImagePattern(vg, sx + 2, sy + 2, slotSize - 4, slotSize - 4, 0, sImg, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + 2, sy + 2, slotSize - 4, slotSize - 4, sr)
                nvgFillPaint(vg, imgPat)
                nvgFill(vg)
            else
                local c = def.col
                nvgBeginPath(vg)
                nvgCircle(vg, sx + slotSize / 2, sy + slotSize / 2, slotSize * 0.32)
                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 200))
                nvgFill(vg)
            end
            -- 检查已装备技能是否满足施展条件（武器/装备需求）
            local slotDisabled = false
            if def.reqWeaponTag then
                local weaponR = GS.equipment and GS.equipment["weapon_r"]
                local weaponL = GS.equipment and GS.equipment["weapon_l"]
                local curTag = weaponR and weaponR.weaponTag
                if not curTag and weaponL and weaponL.weaponTag then
                    curTag = weaponL.weaponTag
                end
                if curTag ~= def.reqWeaponTag then slotDisabled = true end
                if not slotDisabled and def.reqWeaponTag == "弓" then
                    if not weaponL or weaponL.category ~= "箭袋" then slotDisabled = true end
                end
            end
            if not slotDisabled and def.reqLeftCategory then
                local weaponL = GS.equipment and GS.equipment["weapon_l"]
                if not weaponL or weaponL.category ~= def.reqLeftCategory then slotDisabled = true end
            end

            if slotDisabled then
                -- 半透明黑色遮罩
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + 2, sy + 2, slotSize - 4, slotSize - 4, sr)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
                nvgFill(vg)
                -- 红色叉号
                local cx = sx + slotSize / 2
                local cy = sy + slotSize / 2
                local cr = slotSize * 0.28
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx - cr, cy - cr)
                nvgLineTo(vg, cx + cr, cy + cr)
                nvgMoveTo(vg, cx + cr, cy - cr)
                nvgLineTo(vg, cx - cr, cy + cr)
                nvgStrokeColor(vg, nvgRGBA(220, 60, 50, 230))
                nvgStrokeWidth(vg, math.max(2, slotSize * 0.07))
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            end

            -- 技能名（槽位下方）— 冲锋技能根据模式显示不同名称
            local displayName = def.name
            if def.charge then
                local cm = GS.autoChargeMode or "flank"
                displayName = cm == "front" and "正面冲锋" or "侧翼冲锋"
            end
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 190, 160, slotDisabled and 100 or 200))
            nvgText(vg, sx + slotSize / 2, sy + slotSize + 1, displayName, nil)
        else
            -- 空槽显示编号
            nvgFontSize(vg, math.max(10, slotSize * 0.3))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(100, 95, 85, 100))
            nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, i .. "", nil)
        end

        -- 悬停高亮
        if isHovered(sx, sy, slotSize, slotSize) then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, slotSize, slotSize, sr)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 30))
            nvgFill(vg)
        end
    end

    curY = curY + slotSize + skillNameH + sectionGap

    -- ---- 自动消耗品区域 ----
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 170, 210, 200))
    nvgText(vg, px + padX, curY + labelH / 2, "自动消耗品", nil)
    curY = curY + labelH

    -- 消耗品槽位：槽位1对齐技能槽1，槽位2对齐技能槽3
    local consSlotLabels = { "生命药水", "魔法药水" }
    local consAlignTo = { 1, 3 }
    GS.autoConsumableSlotAreas = {}
    GS.autoConsumableThresholdBtnAreas = {}
    for i = 1, GS.AUTO_CONSUMABLE_SLOTS do
        local alignIdx = consAlignTo[i]
        local sx = skillStartX + (alignIdx - 1) * (slotSize + slotGap)
        local sy = curY
        GS.autoConsumableSlotAreas[i] = { x = sx, y = sy, w = slotSize, h = slotSize }

        local sr = math.max(2, math.floor(slotSize * 0.12))

        -- 外框描边
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - 1, sy - 1, slotSize + 2, slotSize + 2, sr + 1)
        nvgStrokeColor(vg, nvgRGBA(90, 65, 30, 220))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 内凹底色
        local slotGrad = nvgLinearGradient(vg, sx, sy, sx, sy + slotSize,
            nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, slotSize, sr)
        nvgFillPaint(vg, slotGrad)
        nvgFill(vg)

        -- 上边内阴影
        local shadowH = math.max(2, math.floor(slotSize * 0.2))
        local topShadow = nvgLinearGradient(vg, sx, sy, sx, sy + shadowH,
            nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, shadowH, sr)
        nvgFillPaint(vg, topShadow)
        nvgFill(vg)

        -- 底部微光
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + sr, sy + slotSize - 1)
        nvgLineTo(vg, sx + slotSize - sr, sy + slotSize - 1)
        nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 消耗品图标
        local templateId = GS.autoConsumables[i]
        local tmpl = templateId and GS.itemTemplates[templateId]
        if tmpl then
            local imgHandle = tmpl.icon and GS.itemImages[tmpl.icon]
            if imgHandle then
                local pad = 2
                local imgPaint = nvgImagePattern(vg,
                    sx + pad, sy + pad,
                    slotSize - pad * 2, slotSize - pad * 2,
                    0, imgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + pad, sy + pad, slotSize - pad * 2, slotSize - pad * 2, sr)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgFontSize(vg, math.max(10, slotSize * 0.4))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 190, 160, 220))
                local firstChar = tmpl.name and string.sub(tmpl.name, 1, 3) or "?"
                nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, firstChar, nil)
            end
        end

        -- 剩余数量角标
        if templateId then
            local totalQty = 0
            for si = 1, GS.bagSlots do
                local inv = GS.inventory[si]
                if inv and (inv.templateId or inv.name) == templateId then
                    totalQty = totalQty + (inv.quantity or 1)
                end
            end
            local qtyFs = math.max(7, math.floor(slotSize * 0.28))
            local qtyText = tostring(totalQty)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, qtyFs)
            local tw = nvgTextBounds(vg, 0, 0, qtyText, nil, nil)
            local qPad = 2
            local bgW = tw + qPad * 2
            local bgH = qtyFs + 3
            local bgX = sx + slotSize - bgW
            local bgY = sy + slotSize - bgH
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 3)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
            nvgFill(vg)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, bgX + bgW / 2, bgY + bgH / 2, qtyText, nil)
        end

        -- 槽位下方固定标签（生命药水/魔法药水）
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(140, 150, 180, 180))
        nvgText(vg, sx + slotSize / 2, sy + slotSize + 2, consSlotLabels[i], nil)

        -- 阈值按钮（槽位右侧）
        local threshold = GS.autoConsumableThresholds[i] or 50
        local tbW = 36
        local tbH = 16
        local tbX = sx + slotSize + 4
        local tbY = sy + (slotSize - tbH) / 2
        GS.autoConsumableThresholdBtnAreas[i] = { x = tbX, y = tbY, w = tbW, h = tbH }

        local tbHov = isHovered(tbX, tbY, tbW, tbH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tbX, tbY, tbW, tbH, 3)
        nvgFillColor(vg, tbHov and nvgRGBA(60, 70, 120, 200) or nvgRGBA(40, 45, 70, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 90, 140, 150))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 180, 220))
        nvgText(vg, tbX + tbW / 2, tbY + tbH / 2, "<" .. threshold .. "%", nil)

        -- 悬停高亮
        if isHovered(sx, sy, slotSize, slotSize) then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, slotSize, slotSize, sr)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 30))
            nvgFill(vg)
        end
    end

    curY = curY + slotSize + consLabelH + thresholdH + sectionGap

    -- ---- 自动食物和增强药剂区域 ----
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 170, 210, 200))
    nvgText(vg, px + padX, curY + labelH / 2, "自动食物和增强药剂", nil)
    curY = curY + labelH

    local fbSlots = {
        { key = "autoFood",       label = "食物",     templateId = GS.autoFood },
        { key = "autoBuffPotion",  label = "增强药剂", templateId = GS.autoBuffPotion },
    }
    local fbAlignTo = { 1, 3 }  -- 对齐到技能槽1和技能槽3

    for si = 1, 2 do
        local slot = fbSlots[si]
        local alignIdx = fbAlignTo[si]
        local sx = skillStartX + (alignIdx - 1) * (slotSize + slotGap)
        local sy = curY

        -- 记录槽位区域
        if si == 1 then
            GS.autoFoodSlotArea = { x = sx, y = sy, w = slotSize, h = slotSize }
        else
            GS.autoBuffPotionSlotArea = { x = sx, y = sy, w = slotSize, h = slotSize }
        end

        local sr = math.max(2, math.floor(slotSize * 0.12))

        -- 外框描边
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - 1, sy - 1, slotSize + 2, slotSize + 2, sr + 1)
        nvgStrokeColor(vg, nvgRGBA(90, 65, 30, 220))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 内凹底色
        local slotGrad = nvgLinearGradient(vg, sx, sy, sx, sy + slotSize,
            nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, slotSize, sr)
        nvgFillPaint(vg, slotGrad)
        nvgFill(vg)

        -- 上边内阴影
        local shadowH = math.max(2, math.floor(slotSize * 0.2))
        local topShadow = nvgLinearGradient(vg, sx, sy, sx, sy + shadowH,
            nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, shadowH, sr)
        nvgFillPaint(vg, topShadow)
        nvgFill(vg)

        -- 底部微光
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + sr, sy + slotSize - 1)
        nvgLineTo(vg, sx + slotSize - sr, sy + slotSize - 1)
        nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 物品图标
        local templateId = slot.templateId
        local tmpl = templateId and GS.itemTemplates[templateId]
        if tmpl then
            local imgHandle = tmpl.icon and GS.itemImages[tmpl.icon]
            if imgHandle then
                local pad2 = 2
                local imgPaint = nvgImagePattern(vg,
                    sx + pad2, sy + pad2,
                    slotSize - pad2 * 2, slotSize - pad2 * 2,
                    0, imgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + pad2, sy + pad2, slotSize - pad2 * 2, slotSize - pad2 * 2, sr)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgFontSize(vg, math.max(10, slotSize * 0.4))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 190, 160, 220))
                local firstChar = tmpl.name and string.sub(tmpl.name, 1, 3) or "?"
                nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, firstChar, nil)
            end
        end

        -- 剩余数量角标
        if templateId then
            local totalQty = 0
            for bi = 1, GS.bagSlots do
                local inv = GS.inventory[bi]
                if inv and (inv.templateId or inv.name) == templateId then
                    totalQty = totalQty + (inv.quantity or 1)
                end
            end
            local qtyFs = math.max(7, math.floor(slotSize * 0.28))
            local qtyText = tostring(totalQty)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, qtyFs)
            local tw = nvgTextBounds(vg, 0, 0, qtyText, nil, nil)
            local qPad2 = 2
            local bgW = tw + qPad2 * 2
            local bgH = qtyFs + 3
            local bgX = sx + slotSize - bgW
            local bgY = sy + slotSize - bgH
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 3)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
            nvgFill(vg)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, bgX + bgW / 2, bgY + bgH / 2, qtyText, nil)
        end

        -- 槽位下方标签
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(140, 150, 180, 180))
        nvgText(vg, sx + slotSize / 2, sy + slotSize + 2, slot.label, nil)

        -- BUFF状态指示（槽位右侧显示剩余时间）
        local remainText = nil
        if si == 1 and GS.foodBuff then
            local remain = (GS.foodBuff.expireTime or 0) - (GS.weatherTime or 0)
            if remain > 0 then
                local hours = math.floor(remain / 60)
                local mins = remain % 60
                remainText = string.format("%dh%dm", hours, mins)
            end
        elseif si == 2 and GS.autoBuffPotion and GS.potionBuffs then
            -- 查找该增强药剂对应的buff stat
            local bpTmpl = GS.itemTemplates[GS.autoBuffPotion]
            local bpStat = bpTmpl and bpTmpl.consumable and bpTmpl.consumable.stat
            if bpStat and GS.potionBuffs[bpStat] then
                local remain = (GS.potionBuffs[bpStat].expireTime or 0) - (GS.weatherTime or 0)
                if remain > 0 then
                    local hours = math.floor(remain / 60)
                    local mins = remain % 60
                    remainText = string.format("%dh%dm", hours, mins)
                end
            end
        end
        if remainText then
            local tbW = 36
            local tbH = 16
            local tbX = sx + slotSize + 4
            local tbY = sy + (slotSize - tbH) / 2
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tbX, tbY, tbW, tbH, 3)
            nvgFillColor(vg, nvgRGBA(30, 60, 30, 200))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(80, 140, 80, 150))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(140, 220, 140, 220))
            nvgText(vg, tbX + tbW / 2, tbY + tbH / 2, remainText, nil)
        end

        -- 悬停高亮
        if isHovered(sx, sy, slotSize, slotSize) then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, slotSize, slotSize, sr)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 30))
            nvgFill(vg)
        end
    end

    -- ---- 消耗品选择弹窗 ----
    if GS.autoConsumablePopupSlot then
        M.drawAutoConsumablePopup()
    end

    -- ---- 食物/增强药剂选择弹窗 ----
    if GS.autoFoodBuffPopupSlot then
        M.drawAutoFoodBuffPopup()
    end
end

-- ====================================================================
-- 绘制：自动消耗品选择弹窗（技能装备弹窗风格）
-- ====================================================================
function M.drawAutoConsumablePopup()
    local vg = M.vg
    local slotIdx = GS.autoConsumablePopupSlot
    local items = GS.autoConsumablePopupItems
    if not slotIdx then return end

    local W = GS.SCREEN_W
    local H = GS.SCREEN_H
    local hasEquipped = GS.autoConsumables[slotIdx] ~= nil
    local slotLabels = { "生命药水", "魔法药水" }

    -- 手机竖屏模式放大
    local pScale = (H > W) and 1.8 or 1.0

    -- 布局参数（网格，每行放4个）
    local gridCols = 4
    local iconSize = math.floor(28 * pScale)
    local iconGap = math.floor(6 * pScale)
    local labelH = math.floor(12 * pScale)
    local cellH = iconSize + labelH + 2
    local cellGap = math.floor(4 * pScale)
    local pad = math.floor(12 * pScale)
    local titleH = math.floor(22 * pScale)
    local removeBtnH = math.floor(22 * pScale)

    local gridRows = math.max(1, math.ceil(#items / gridCols))
    local gridW = gridCols * iconSize + (gridCols - 1) * iconGap
    local gridH = gridRows * cellH + (gridRows - 1) * cellGap

    local dlgW = math.max(gridW + pad * 2, math.floor(170 * pScale))
    local dlgH = titleH + pad + gridH + pad
        + (hasEquipped and (removeBtnH + 8) or 0)
        + (#items == 0 and math.floor(30 * pScale) or 0)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 6

    GS.autoConsumablePopupRect = { x = dlgX, y = dlgY, w = dlgW, h = dlgH }

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13 * pScale)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    local titleText = "选择" .. (slotLabels[slotIdx] or "消耗品") .. " — 槽位 " .. slotIdx
    nvgText(vg, dlgX + dlgW / 2, dlgY + math.floor(6 * pScale), titleText, nil)

    -- 物品网格
    GS.autoConsumablePopupItemRects = {}
    local startX = dlgX + (dlgW - gridW) / 2
    local startY = dlgY + titleH + pad

    if #items == 0 then
        nvgFontSize(vg, 11 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 160, 120, 255))
        nvgText(vg, dlgX + dlgW / 2, startY + math.floor(15 * pScale), "无可用药水", nil)
    else
        for idx, item in ipairs(items) do
            local col = ((idx - 1) % gridCols)
            local row = math.floor((idx - 1) / gridCols)
            local ix = startX + col * (iconSize + iconGap)
            local iy = startY + row * (cellH + cellGap)

            GS.autoConsumablePopupItemRects[idx] = {
                x = ix, y = iy, w = iconSize, h = cellH,
                item = item,
            }

            -- 图标背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
            local imgHandle = item.icon and GS.itemImages[item.icon]
            if imgHandle then
                local imgPat = nvgImagePattern(vg, ix, iy, iconSize, iconSize, 0, imgHandle, 1.0)
                nvgFillPaint(vg, imgPat)
            else
                nvgFillColor(vg, nvgRGBA(100, 80, 60, 160))
            end
            nvgFill(vg)

            -- 图标边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix + 0.5, iy + 0.5, iconSize - 1, iconSize - 1, 3)
            nvgStrokeColor(vg, nvgRGBA(80, 60, 30, 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 物品名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 7 * pScale)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 200, 160, 220))
            nvgText(vg, ix + iconSize / 2, iy + iconSize + 1, (item.name or ""):gsub(" %+%d+$", ""), nil)

            -- 数量角标
            if item.quantity and item.quantity > 1 then
                nvgFontSize(vg, 7 * pScale)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
                nvgText(vg, ix + iconSize - 1, iy + iconSize - 1, "x" .. item.quantity, nil)
            end

            -- Hover 高亮
            if isHovered(ix, iy, iconSize, cellH) then
                drawHoverHighlight(vg, ix, iy, iconSize, iconSize, 3)
            end
        end
    end

    -- "取消装备"按钮
    if hasEquipped then
        local btnW = math.floor(70 * pScale)
        local btnH = removeBtnH
        local btnX = dlgX + (dlgW - btnW) / 2
        local btnY = dlgY + dlgH - pad - btnH

        GS.autoConsumablePopupItemRects[#items + 1] = {
            x = btnX, y = btnY, w = btnW, h = btnH, unequip = true,
        }

        local hov = isHovered(btnX, btnY, btnW, btnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, hov and nvgRGBA(180, 60, 50, 220) or nvgRGBA(140, 50, 40, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 80, 60, 200))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 240, 220, 240))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "取消装备", nil)
    end
end

-- ====================================================================
-- 绘制：自动食物/增强药剂选择弹窗
-- ====================================================================
function M.drawAutoFoodBuffPopup()
    local vg = M.vg
    local slotType = GS.autoFoodBuffPopupSlot  -- "food" or "buffPotion"
    local items = GS.autoFoodBuffPopupItems
    if not slotType then return end

    local W = GS.SCREEN_W
    local H = GS.SCREEN_H
    local hasEquipped = (slotType == "food" and GS.autoFood ~= nil)
                     or (slotType == "buffPotion" and GS.autoBuffPotion ~= nil)
    local titleLabel = slotType == "food" and "食物" or "增强药剂"

    -- 手机竖屏模式放大
    local pScale = (H > W) and 1.8 or 1.0

    -- 布局参数（网格，每行放4个）
    local gridCols = 4
    local iconSize = math.floor(28 * pScale)
    local iconGap = math.floor(6 * pScale)
    local labelH = math.floor(12 * pScale)
    local cellH = iconSize + labelH + 2
    local cellGap = math.floor(4 * pScale)
    local pad = math.floor(12 * pScale)
    local titleH = math.floor(22 * pScale)
    local removeBtnH = math.floor(22 * pScale)

    local gridRows = math.max(1, math.ceil(#items / gridCols))
    local gridW = gridCols * iconSize + (gridCols - 1) * iconGap
    local gridH = gridRows * cellH + (gridRows - 1) * cellGap

    local dlgW = math.max(gridW + pad * 2, math.floor(170 * pScale))
    local dlgH = titleH + pad + gridH + pad
        + (hasEquipped and (removeBtnH + 8) or 0)
        + (#items == 0 and math.floor(30 * pScale) or 0)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 6

    GS.autoFoodBuffPopupRect = { x = dlgX, y = dlgY, w = dlgW, h = dlgH }

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13 * pScale)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + math.floor(6 * pScale), "选择" .. titleLabel, nil)

    -- 物品网格
    GS.autoFoodBuffPopupItemRects = {}
    local startX = dlgX + (dlgW - gridW) / 2
    local startY = dlgY + titleH + pad

    if #items == 0 then
        nvgFontSize(vg, 11 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 160, 120, 255))
        local emptyText = slotType == "food" and "无可用食物" or "无可用增强药剂"
        nvgText(vg, dlgX + dlgW / 2, startY + math.floor(15 * pScale), emptyText, nil)
    else
        for idx, item in ipairs(items) do
            local col = ((idx - 1) % gridCols)
            local row = math.floor((idx - 1) / gridCols)
            local ix = startX + col * (iconSize + iconGap)
            local iy = startY + row * (cellH + cellGap)

            GS.autoFoodBuffPopupItemRects[idx] = {
                x = ix, y = iy, w = iconSize, h = cellH,
                item = item,
            }

            -- 图标背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
            local imgHandle = item.icon and GS.itemImages[item.icon]
            if imgHandle then
                local imgPat = nvgImagePattern(vg, ix, iy, iconSize, iconSize, 0, imgHandle, 1.0)
                nvgFillPaint(vg, imgPat)
            else
                nvgFillColor(vg, nvgRGBA(100, 80, 60, 160))
            end
            nvgFill(vg)

            -- 图标边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix + 0.5, iy + 0.5, iconSize - 1, iconSize - 1, 3)
            nvgStrokeColor(vg, nvgRGBA(80, 60, 30, 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 物品名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 7 * pScale)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 200, 160, 220))
            nvgText(vg, ix + iconSize / 2, iy + iconSize + 1, (item.name or ""):gsub(" %+%d+$", ""), nil)

            -- 数量角标
            if item.quantity and item.quantity > 1 then
                nvgFontSize(vg, 7 * pScale)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
                nvgText(vg, ix + iconSize - 1, iy + iconSize - 1, "x" .. item.quantity, nil)
            end

            -- Hover 高亮
            if isHovered(ix, iy, iconSize, cellH) then
                drawHoverHighlight(vg, ix, iy, iconSize, iconSize, 3)
            end
        end
    end

    -- "取消装备"按钮
    if hasEquipped then
        local btnW = math.floor(70 * pScale)
        local btnH = removeBtnH
        local btnX = dlgX + (dlgW - btnW) / 2
        local btnY = dlgY + dlgH - pad - btnH

        GS.autoFoodBuffPopupItemRects[#items + 1] = {
            x = btnX, y = btnY, w = btnW, h = btnH, unequip = true,
        }

        local hov = isHovered(btnX, btnY, btnW, btnH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, hov and nvgRGBA(180, 60, 50, 220) or nvgRGBA(140, 50, 40, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 80, 60, 200))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 240, 220, 240))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "取消装备", nil)
    end
end

-- ====================================================================
-- 绘制：信息栏（HP/MP/经验条）
-- ====================================================================
function M.drawInfoBar()
    local vg = M.vg
    local barX, barY, barW, barH

    if GS.isLandscape then
        local boardPixel = GS.CELL * GS.BOARD_SIZE
        barX = GS.BOARD_X
        barY = GS.SCREEN_H - 8 - GS.INFO_H
        barW = boardPixel
        barH = GS.INFO_H
    else
        local panelY = GS.SCREEN_H - GS.BOTTOM_H
        barX = 8
        barY = panelY - GS.INFO_H - 4
        barW = GS.SCREEN_W - 16
        barH = GS.INFO_H
    end

    -- 经验条
    if GS.player and GS.player.exp ~= nil then
        local expY = barY - GS.EXP_GAP - GS.EXP_BAR_H
        local needed = GS.expToNextLevel(GS.player.level or 1)
        local expRatio = math.min(1.0, (GS.displayExp or 0) / math.max(1, needed))

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, expY, barW, GS.EXP_BAR_H, 3)
        nvgFillColor(vg, nvgRGBA(15, 18, 30, 200))
        nvgFill(vg)

        if expRatio > 0 then
            local expGrad = nvgLinearGradient(vg, barX, expY, barX + barW * expRatio, expY,
                nvgRGBA(255, 200, 60, 255), nvgRGBA(255, 160, 30, 255))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, expY, barW * expRatio, GS.EXP_BAR_H, 3)
            nvgFillPaint(vg, expGrad)
            nvgFill(vg)
        end

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, expY, barW, GS.EXP_BAR_H, 3)
        nvgStrokeColor(vg, nvgRGBA(180, 150, 60, 80))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        -- 居中 "EXP" 文字（描边 + 填充）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, GS.EXP_BAR_H + 6)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local expTx = barX + barW / 2
        local expTy = expY + GS.EXP_BAR_H / 2
        -- 黑色描边（多方向偏移绘制）
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        local ofs = 1.0
        for _, od in ipairs({{-ofs,0},{ofs,0},{0,-ofs},{0,ofs},{-ofs,-ofs},{ofs,-ofs},{-ofs,ofs},{ofs,ofs}}) do
            nvgText(vg, expTx + od[1], expTy + od[2], "EXP", nil)
        end
        -- 白色正文
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgText(vg, expTx, expTy, "EXP", nil)
    end

    -- 状态栏背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 6)
    nvgFillColor(vg, nvgRGBA(25, 30, 50, 200))
    nvgFill(vg)

    if not GS.player then return end

    nvgFontFace(vg, "sans")
    local midY = barY + barH / 2
    local pad = 10
    local statBarW = math.min(120, (barW - 100) / 2)
    local statBarH = 10
    local labelSize = 11
    local numSize = 10

    -- HP 条
    local hpX = barX + pad
    local hpBarY = midY - statBarH / 2 + 6

    nvgFontSize(vg, labelSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 220, 120, 230))
    nvgText(vg, hpX, midY - 7, "HP", nil)

    nvgFontSize(vg, numSize)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 230, 200))
    local hpDisplayText = math.floor(GS.player.hp) .. "/" .. math.floor(GS.player.maxHp)
    if (GS.bloodShield or 0) > 0 then
        hpDisplayText = hpDisplayText .. "(+" .. GS.bloodShield .. ")"
    end
    nvgText(vg, hpX + statBarW, midY - 7, hpDisplayText, nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, hpX, hpBarY, statBarW, statBarH, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 130))
    nvgFill(vg)

    local hpRatio = (GS.displayHp or GS.player.hp) / math.max(1, GS.player.maxHp)
    local hpColor = nvgRGBA(80, 220, 80, 255)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, hpX, hpBarY, statBarW * math.max(0, math.min(1, hpRatio)), statBarH, 3)
    nvgFillColor(vg, hpColor)
    nvgFill(vg)

    -- 饮血护甲值：在HP条上叠加金色护甲条
    if (GS.bloodShield or 0) > 0 then
        local bloodDrinkLv = GS.skillLevels["w_blood_drink"] or 0
        local shieldCap = math.floor(GS.player.maxHp * 0.02 * math.max(1, bloodDrinkLv))
        local shieldRatio = math.min(1, GS.bloodShield / math.max(1, shieldCap))
        local shieldBarW = statBarW * shieldRatio
        nvgBeginPath(vg)
        nvgRoundedRect(vg, hpX, hpBarY - 3, shieldBarW, 3, 1)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
        nvgFill(vg)
    end

    -- 角色名 + 等级
    local centerX = barX + barW / 2
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, centerX, midY, GS.player.name .. "  Lv." .. (GS.player.level or 1), nil)

    -- MP 条
    local mpX = barX + barW - pad - statBarW
    local mpBarY = hpBarY

    nvgFontSize(vg, labelSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 160, 255, 230))
    nvgText(vg, mpX, midY - 7, "MP", nil)

    local curMp = GS.player.mp or 0
    local maxMp = GS.player.maxMp or 1
    nvgFontSize(vg, numSize)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 230, 200))
    nvgText(vg, mpX + statBarW, midY - 7, math.floor(curMp) .. "/" .. math.floor(maxMp), nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, mpX, mpBarY, statBarW, statBarH, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 130))
    nvgFill(vg)

    local displayMp = GS.displayMp or curMp
    local mpRatio = displayMp / math.max(1, maxMp)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mpX, mpBarY, statBarW * math.min(1, mpRatio), statBarH, 3)
    nvgFillColor(vg, nvgRGBA(70, 130, 255, 255))
    nvgFill(vg)

    -- 吟唱段数方块指示（法师/牧师专属）
    if GS.currentClass == "mage" or GS.currentClass == "priest" then
        local stages = GS.chantStages or 0
        local stagesMax = GS.chantStagesMax or 0
        local totalBlocks = math.max(stages, stagesMax)

        if totalBlocks > 0 then
            local blockSz = 7
            local blockGap = 2
            local totalW = totalBlocks * blockSz + (totalBlocks - 1) * blockGap
            local blockStartX = centerX - totalW / 2
            local blockY = midY + 9

            for i = 1, totalBlocks do
                local bx = blockStartX + (i - 1) * (blockSz + blockGap)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, blockY, blockSz, blockSz, 1.5)
                if i <= stages then
                    -- 可用段数：紫色填充
                    nvgFillColor(vg, nvgRGBA(160, 100, 220, 230))
                else
                    -- 已使用：黑色填充
                    nvgFillColor(vg, nvgRGBA(30, 20, 40, 200))
                end
                nvgFill(vg)
                -- 方块边框
                nvgStrokeColor(vg, nvgRGBA(180, 130, 240, 160))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)
            end
        end

        -- 吟唱中提示（暂时隐藏，观察特效表现）
        -- if GS.chanting then
        --     local ch = GS.chanting
        --     local skillDef = GS.SKILL_DEFS[ch.skillId]
        --     local sName = skillDef and skillDef.name or ch.skillId
        --     local chantingLabel = "吟唱中:" .. sName .. "(" .. ch.stagesAccum .. "/" .. ch.stagesNeeded .. ")"
        --     nvgFontSize(vg, 9)
        --     nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        --     nvgFillColor(vg, nvgRGBA(180, 160, 220, 200))
        --     nvgText(vg, centerX, midY + 21, chantingLabel, nil)
        -- end
    end

end
-- ====================================================================
-- 绘制：底部面板（公共外壳 + Tab按钮 + 内容分发）
-- ====================================================================
function M.drawInventoryBar()
    local vg = M.vg
    local panelX, panelY, panelW, panelH

    if GS.isLandscape then
        panelX = GS.RIGHT_PANEL_X
        panelY = GS.TOP_BAR_H + 4
        panelW = GS.RIGHT_PANEL_W
        panelH = GS.SCREEN_H - panelY - 8
    else
        panelX = 0
        panelY = GS.SCREEN_H - GS.BOTTOM_H
        panelW = GS.SCREEN_W
        panelH = GS.BOTTOM_H
    end

    -- 羊皮纸纹理底板（放大铺满，让纸张撕裂边缘顶到黑框）
    local cornerR = GS.isLandscape and 8 or 0
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    if M.parchmentBg and M.parchmentBg ~= 0 then
        -- cover 模式：保持正方形比例铺满，居中裁剪，避免不同设备拉伸变形
        local expand = 0.08
        local coverSize = math.max(panelW, panelH) * (1 + expand * 2)
        local patX = panelX + (panelW - coverSize) / 2
        local patY = panelY + (panelH - coverSize) / 2
        local pat = nvgImagePattern(vg, patX, patY, coverSize, coverSize, 0, M.parchmentBg, 1.0)
        nvgFillPaint(vg, pat)
    else
        nvgFillColor(vg, nvgRGBA(180, 155, 120, 255))
    end
    nvgFill(vg)

    -- 纯黑外边线
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 金色装饰性边框
    do
        local bm = 4
        local fdx, fdy = panelX + bm, panelY + bm
        local fdw, fdh = panelW - bm * 2, panelH - bm * 2
        local fcr = math.max(2, cornerR - 2)
        -- 外线
        nvgBeginPath(vg)
        nvgRoundedRect(vg, fdx, fdy, fdw, fdh, fcr)
        nvgStrokeColor(vg, nvgRGBA(200, 170, 90, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 内线
        nvgBeginPath(vg)
        nvgRoundedRect(vg, fdx + 3, fdy + 3, fdw - 6, fdh - 6, math.max(1, fcr - 1))
        nvgStrokeColor(vg, nvgRGBA(180, 150, 70, 120))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
        -- 四角装饰（小菱形）
        local dotR = 3
        local corners = {
            { fdx + 1, fdy + 1 },
            { fdx + fdw - 1, fdy + 1 },
            { fdx + 1, fdy + fdh - 1 },
            { fdx + fdw - 1, fdy + fdh - 1 },
        }
        for _, c in ipairs(corners) do
            nvgBeginPath(vg)
            nvgMoveTo(vg, c[1], c[2] - dotR)
            nvgLineTo(vg, c[1] + dotR, c[2])
            nvgLineTo(vg, c[1], c[2] + dotR)
            nvgLineTo(vg, c[1] - dotR, c[2])
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(210, 180, 90, 200))
            nvgFill(vg)
        end
        -- 边线中点小装饰（短横线）
        local decoLen = 8
        nvgStrokeColor(vg, nvgRGBA(220, 190, 100, 200))
        nvgStrokeWidth(vg, 2)
        -- 上中
        nvgBeginPath(vg)
        nvgMoveTo(vg, fdx + fdw / 2 - decoLen, fdy)
        nvgLineTo(vg, fdx + fdw / 2 + decoLen, fdy)
        nvgStroke(vg)
        -- 下中
        nvgBeginPath(vg)
        nvgMoveTo(vg, fdx + fdw / 2 - decoLen, fdy + fdh)
        nvgLineTo(vg, fdx + fdw / 2 + decoLen, fdy + fdh)
        nvgStroke(vg)
        -- 左中
        nvgBeginPath(vg)
        nvgMoveTo(vg, fdx, fdy + fdh / 2 - decoLen)
        nvgLineTo(vg, fdx, fdy + fdh / 2 + decoLen)
        nvgStroke(vg)
        -- 右中
        nvgBeginPath(vg)
        nvgMoveTo(vg, fdx + fdw, fdy + fdh / 2 - decoLen)
        nvgLineTo(vg, fdx + fdw, fdy + fdh / 2 + decoLen)
        nvgStroke(vg)
    end

    -- 底部按钮区域
    local tabLabels = { "角色", "背包", "待定", "待定", "待定" }
    local tabCount = #tabLabels
    local pad = 10
    local tabGap = 6
    local slotGap = 3

    -- 先计算格子大小，按钮高度 = 2 格高
    local titleH = 22
    local contentPadTop = 6  -- 内容底板上沿与标题区的间距
    local contentTop = panelY + titleH + contentPadTop
    local gridAreaW = panelW - pad * 2

    -- 固定槽位大小，所有设备一致（与 drawInventoryGrid 同步）
    local slotSize = 28
    local tabBtnH = slotSize * 2 + slotGap

    -- 统一基准：从金边反推标签区域位置
    local goldBottom = panelY + panelH - 5
    local tabBarY = goldBottom - tabBtnH
    local tabGapAbove = 6  -- 内容面板与按钮栏之间的间距
    local tabContainerTop = tabBarY - 3  -- 按钮容器底板上沿

    local totalGridW = GS.INV_COLS * slotSize + (GS.INV_COLS - 1) * slotGap
    local totalGridH = GS.INV_ROWS * slotSize + (GS.INV_ROWS - 1) * slotGap
    local gridX = panelX + math.floor((panelW - totalGridW) / 2)
    local contentAreaH = tabContainerTop - contentTop - tabGapAbove
    local gridY = contentTop + math.floor((contentAreaH - totalGridH) / 2)

    -- 标题（根据当前Tab切换，基于金边定位）
    local playerDisplayName = (GS.charName and GS.charName ~= "") and GS.charName or "旅人"
    local tabTitles = { playerDisplayName, "背 包", "技 能", "日 志", "地 图" }
    local goldTop = panelY + 4  -- 金边外线上沿
    local titleCenterY = goldTop + (contentTop - goldTop) / 2 + 1

    -- 辅助：绘制指定tab的标题文字
    local function drawTabTitle(tabIdx)
        local titleText = tabTitles[tabIdx] or "背 包"
        if tabIdx ~= 5 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 15)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
            for _, off in ipairs(OFFSETS_8) do
                nvgText(vg, panelX + panelW / 2 + off[1], titleCenterY + off[2], titleText, nil)
            end
            nvgFillColor(vg, nvgRGBA(255, 220, 130, 255))
            nvgText(vg, panelX + panelW / 2, titleCenterY, titleText, nil)
        end
    end

    -- 内容区域参数（使用完整面板可用区域，各tab内部自行布局）
    local contentX = panelX + 6
    local contentY = contentTop + 2
    local contentW = panelW - 12
    local contentH = contentAreaH - 4

    -- 统一内容底板（填满整个羊皮纸区域）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(40, 28, 15, 70))
    nvgFill(vg)

    -- 辅助：根据 tab 索引绘制对应面板
    local function drawTabContent(tab, cx2, cy2, cw2, ch2)
        if tab == 1 then
            M.drawCharacterPanel(cx2, cy2, cw2, ch2)
        elseif tab == 2 then
            M.drawInventoryGrid(cx2, cy2, cw2, ch2)
        elseif tab == 3 then
            M.drawSkillPanel(cx2, cy2, cw2, ch2)
        elseif tab == 4 then
            M.drawJournalPanel(cx2, cy2, cw2, ch2)
        elseif tab == 5 then
            -- 地图使用更大区域：宽度填满面板，顶部顶到面板黑色边框内侧
            local mapX = panelX + 1
            local mapY = panelY + 1
            local mapW = panelW - 2
            local availableH = tabContainerTop - mapY + 8
            local mapH = math.min(mapW, availableH)  -- 锁定正方形宽高比，取可用高度和宽度的较小值
            local mapCornerR = math.max(0, cornerR - 1)
            M.drawMapPanel(mapX, mapY, mapW, mapH, mapCornerR)
        end
    end

    -- 辅助：绘制指定tab的金币（仅背包tab=2显示）
    local function drawTabGold(tabIdx)
        if tabIdx ~= 2 then return end
        local goldStr = Utils.fmtNum(GS.gold or 0) .. " G"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local goldTextW = nvgTextBounds(vg, 0, 0, goldStr, nil)

        local bagSize = 20
        local barH = 22
        local innerPad = 4
        local iconTextGap = 3
        local barW = innerPad + bagSize + iconTextGap + goldTextW + innerPad + 2
        local barX = panelX + panelW - barW - 8
        local barY = tabContainerTop - tabGapAbove - barH - 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 5)
        local barGrad = nvgLinearGradient(vg, barX, barY, barX, barY + barH,
            nvgRGBA(50, 35, 15, 220), nvgRGBA(30, 20, 8, 240))
        nvgFillPaint(vg, barGrad)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 5)
        nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX + 1, barY + 1, barW - 2, barH - 2, 4)
        nvgStrokeColor(vg, nvgRGBA(220, 180, 80, 40))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        local iconX = barX + innerPad
        local iconY = barY + (barH - bagSize) / 2
        if M.moneyBagImg and M.moneyBagImg > 0 then
            local imgPat = nvgImagePattern(vg, iconX, iconY, bagSize, bagSize, 0, M.moneyBagImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, iconX, iconY, bagSize, bagSize)
            nvgFillPaint(vg, imgPat)
            nvgFill(vg)
        end

        local textX = iconX + bagSize + iconTextGap
        local textY = barY + barH / 2
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgText(vg, textX + 1, textY + 1, goldStr, nil)
        nvgFillColor(vg, nvgRGBA(255, 215, 50, 255))
        nvgText(vg, textX, textY, goldStr, nil)
    end

    -- 绘制面板内容（带滑动切换动画），裁剪区域扩大到包含标题和金币
    nvgSave(vg)
    nvgScissor(vg, panelX + 1, panelY + 1, panelW - 2, tabContainerTop - panelY - 1 - tabGapAbove)

    if GS.tabAnimTimer > 0 and GS.tabAnimFrom > 0 then
        -- 动画进行中：同时绘制旧面板滑出 + 新面板滑入
        local t = 1 - safeProgress(GS.tabAnimTimer, GS.tabAnimDuration)
        local ease = t * t * (3 - 2 * t)  -- smoothstep 缓动

        -- 旧面板：从 0 滑到 -contentW*dir（滑出屏幕）
        local oldOffX = -contentW * GS.tabAnimDir * ease
        nvgSave(vg)
        nvgTranslate(vg, oldOffX, 0)
        drawTabTitle(GS.tabAnimFrom)
        drawTabContent(GS.tabAnimFrom, contentX, contentY, contentW, contentH)
        drawTabGold(GS.tabAnimFrom)
        nvgRestore(vg)

        -- 新面板：从 +contentW*dir 滑到 0（滑入屏幕）
        local newOffX = contentW * GS.tabAnimDir * (1 - ease)
        nvgSave(vg)
        nvgTranslate(vg, newOffX, 0)
        drawTabTitle(GS.activeBottomTab)
        drawTabContent(GS.activeBottomTab, contentX, contentY, contentW, contentH)
        drawTabGold(GS.activeBottomTab)
        nvgRestore(vg)
    else
        -- 无动画，正常绘制
        drawTabTitle(GS.activeBottomTab)
        drawTabContent(GS.activeBottomTab, contentX, contentY, contentW, contentH)
        drawTabGold(GS.activeBottomTab)
    end

    nvgRestore(vg)

    -- 底部 5 个标签按钮（tabBarY 已在前面统一计算）
    local tabIcons = nil  -- emoji 已移除，使用 tabLabels 显示文字
    local goldLeft = panelX + 5
    local goldRight = panelX + panelW - 5
    local totalTabW = goldRight - goldLeft
    local tabBtnW_raw = math.floor((totalTabW - (tabCount - 1) * tabGap) / tabCount)
    -- 按钮强制正方形：取宽高中较小值
    local tabBtnSq = math.min(tabBtnW_raw, tabBtnH)
    local tabBtnW = tabBtnSq
    tabBtnH = tabBtnSq
    local usedTabW = tabCount * tabBtnW + (tabCount - 1) * tabGap
    local tabStartX = goldLeft + math.floor((totalTabW - usedTabW) / 2)
    local tabR = 6

    -- 按钮容器底板（贴着金色边框左右下三边）
    local bgLeft = panelX + 4
    local bgRight = panelX + panelW - 4
    local bgBottom = panelY + panelH - 4

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bgLeft, tabBarY - 3, bgRight - bgLeft, bgBottom - (tabBarY - 3), tabR + 2)
    nvgFillColor(vg, nvgRGBA(25, 15, 5, 180))
    nvgFill(vg)

    GS.bottomTabBtnRects = {}

    -- 未选中按钮缩放比例（底边对齐）
    local inactiveScale = 0.82
    local activeBottom = tabBarY + tabBtnH  -- 选中按钮的底边 Y

    for i = 1, tabCount do
        local isActive = (GS.activeBottomTab == i)

        -- 计算实际绘制尺寸
        local drawW, drawH
        if isActive then
            drawW = tabBtnW
            drawH = tabBtnH
        else
            drawW = math.floor(tabBtnW * inactiveScale)
            drawH = math.floor(tabBtnH * inactiveScale)
        end

        -- X：在原始格子内居中
        local cellX = tabStartX + (i - 1) * (tabBtnW + tabGap)
        local bx = cellX + math.floor((tabBtnW - drawW) / 2)
        -- Y：底边对齐
        local by = activeBottom - drawH

        GS.bottomTabBtnRects[i] = { x = bx, y = by, w = drawW, h = drawH }

        nvgSave(vg)

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, drawW, drawH, tabR)
        if isActive then
            local activeGrad = nvgLinearGradient(vg, bx, by, bx, by + drawH,
                nvgRGBA(200, 155, 75, 255), nvgRGBA(155, 110, 50, 255))
            nvgFillPaint(vg, activeGrad)
        else
            local inactiveGrad = nvgLinearGradient(vg, bx, by, bx, by + drawH,
                nvgRGBA(90, 62, 32, 240), nvgRGBA(65, 42, 20, 240))
            nvgFillPaint(vg, inactiveGrad)
        end
        nvgFill(vg)

        -- 顶部高光线（凸起感）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + 1, by + 1, drawW - 2, drawH * 0.45, tabR - 1)
        if isActive then
            nvgFillColor(vg, nvgRGBA(255, 230, 160, 50))
        else
            nvgFillColor(vg, nvgRGBA(180, 140, 90, 30))
        end
        nvgFill(vg)

        -- 内阴影（底部加深，增加立体感）
        local shadowGrad = nvgLinearGradient(vg, bx, by + drawH * 0.7, bx, by + drawH,
            nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, isActive and 40 or 60))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, drawW, drawH, tabR)
        nvgFillPaint(vg, shadowGrad)
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + 0.5, by + 0.5, drawW - 1, drawH - 1, tabR)
        if isActive then
            nvgStrokeColor(vg, nvgRGBA(255, 220, 140, 200))
            nvgStrokeWidth(vg, 1.5)
        else
            nvgStrokeColor(vg, nvgRGBA(110, 80, 45, 150))
            nvgStrokeWidth(vg, 1)
        end
        nvgStroke(vg)

        -- 选中态外发光
        if isActive then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx - 1, by - 1, drawW + 2, drawH + 2, tabR + 1)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 100, 60))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 图标
        local iconSize = math.max(14, drawH * 0.35)
        local centerX = bx + drawW / 2
        local iconY = by + drawH * 0.35

        -- 按钮图标映射
        local btnIcon = nil
        if i == 1 and M.characterIcon ~= -1 then btnIcon = M.characterIcon end
        if i == 2 and M.backpackIcon ~= -1 then btnIcon = M.backpackIcon end
        if i == 3 and M.skillIcon ~= -1 then btnIcon = M.skillIcon end
        if i == 4 and M.bookIcon ~= -1 then btnIcon = M.bookIcon end
        if i == 5 and M.mapIcon ~= -1 then btnIcon = M.mapIcon end

        if btnIcon then
            local imgPad = 2
            local availW = drawW - imgPad * 2
            local availH = drawH - imgPad * 2
            -- 保持正方形宽高比，居中
            local iconSz = math.min(availW, availH)
            local imgX = bx + imgPad + (availW - iconSz) / 2
            local imgY = by + imgPad + (availH - iconSz) / 2
            local alpha = isActive and 255 or 140
            local imgPaint = nvgImagePattern(vg, imgX, imgY, iconSz, iconSz, 0, btnIcon, alpha / 255.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, imgX, imgY, iconSz, iconSz, tabR - 1)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            -- 无图标时显示文字标签居中
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, drawH * 0.28))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if isActive then
                nvgFillColor(vg, nvgRGBA(255, 245, 215, 255))
            else
                nvgFillColor(vg, nvgRGBA(200, 180, 150, 160))
            end
            nvgText(vg, centerX, by + drawH / 2, tabLabels[i], nil)
        end

        -- 选中指示点
        if isActive then
            nvgBeginPath(vg)
            nvgCircle(vg, centerX, by + drawH - 4, 2)
            nvgFillColor(vg, nvgRGBA(255, 230, 160, 220))
            nvgFill(vg)
        end

        -- hover 高亮（非选中态）
        if not isActive and isHovered(bx, by, drawW, drawH) then
            drawHoverHighlight(vg, bx, by, drawW, drawH, tabR)
        end

        nvgRestore(vg)
    end


end

-- ====================================================================
-- 街头睡觉弹窗（全屏覆盖，独立于drawUnits）
-- ====================================================================
function M.drawStreetSleepOverlay()
    if not GS.streetSleepActive then return end
    local vg = M.vg
    local time = GetTime():GetElapsedTime()
    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
    nvgFill(vg)
    -- 弹窗尺寸
    local dlgW = math.min(sw * 0.7, 260)
    local dlgH = math.min(sh * 0.2, 70)
    local dlgX = (sw - dlgW) / 2
    local dlgY = (sh - dlgH) / 2
    local cornerR = 6
    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 2, dlgY + 2, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)
    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    local bgGrad = nvgLinearGradient(vg, dlgX, dlgY, dlgX, dlgY + dlgH,
        nvgRGBA(40, 40, 70, 240), nvgRGBA(25, 25, 50, 240))
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)
    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(120, 140, 200, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    -- 文本（带轻微浮动）
    local bob = math.sin(time * 1.5) * 2
    local fontSize = math.max(15, math.min(dlgW * 0.07, 20))
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 255, 230))
    nvgText(vg, sw / 2, sh / 2 + bob, "你睡着了……时间过得飞快", nil)
    -- zZ 气泡
    local zBase = math.max(12, fontSize * 0.7)
    local zCycle = (time * 0.8) % 1.0
    for zi = 0, 2 do
        local zPhase = (zCycle + zi * 0.33) % 1.0
        local zAlpha = math.floor(180 * (1 - zPhase))
        local zSize = zBase * (0.5 + zPhase * 0.5)
        local zOffX = dlgW * 0.3 + zi * 8
        local zOffY = -zPhase * dlgH * 0.4
        nvgFontSize(vg, zSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 180, 255, zAlpha))
        nvgText(vg, sw / 2 + zOffX, sh / 2 + zOffY + bob, "z", nil)
    end
end

-- ====================================================================
-- 息屏挂机遮罩（覆盖全屏，仅在 screenOffMode 时绘制）
-- ====================================================================
function M.drawScreenOffOverlay()
    if not GS.screenOffMode then return end
    local vg = M.vg
    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    local time = GetTime():GetElapsedTime()

    -- 90% 不透明度黑色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 230))
    nvgFill(vg)

    -- 上滑解锁提示（底部居中，带轻微浮动动画）
    local bob = math.sin(time * 2.0) * 3
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 160))
    nvgText(vg, sw / 2, sh * 0.75 + bob, "向上滑动解锁", nil)

    -- 上滑箭头提示
    local arrowY = sh * 0.70 + bob
    nvgBeginPath(vg)
    nvgMoveTo(vg, sw / 2, arrowY - 6)
    nvgLineTo(vg, sw / 2 - 8, arrowY + 4)
    nvgLineTo(vg, sw / 2 + 8, arrowY + 4)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 120))
    nvgFill(vg)

    -- 显示上滑进度反馈（用户正在上滑时）
    if GS._screenOffSwipeStartY and GS._screenOffSwipeCurrentY then
        local dy = GS._screenOffSwipeStartY - GS._screenOffSwipeCurrentY
        local threshold = sh * 0.15
        if dy > 5 then
            local progress = math.min(dy / threshold, 1.0)
            -- 进度条
            local barW = 80
            local barH = 4
            local barX = (sw - barW) / 2
            local barY = sh * 0.60
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW, barH, 2)
            nvgFillColor(vg, nvgRGBA(80, 80, 100, 150))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW * progress, barH, 2)
            nvgFillColor(vg, nvgRGBA(140, 180, 255, 220))
            nvgFill(vg)
        end
    end
end

-- ====================================================================
-- 拖拽浮动物品（独立于面板，始终渲染）
-- ====================================================================
function M.drawDragFloatingItem()
    if not GS.itemDragActive and not GS.lostItemDragActive then return end

    local vg = M.vg
    local dragItem = nil
    if GS.lostItemDragActive and GS.dragLostItemIdx then
        dragItem = GS.lostItems[GS.dragLostItemIdx]
    elseif GS.dragSlotIdx then
        dragItem = GS.inventory[GS.dragSlotIdx]
    elseif GS.dragEquipSlotId then
        dragItem = GS.equipment[GS.dragEquipSlotId]
    elseif GS.dragWarehouseIdx then
        dragItem = GS.warehouse[GS.dragWarehouseIdx]
    elseif GS.dragSharedStorageIdx then
        dragItem = GS.sharedStorage[GS.dragSharedStorageIdx]
    end
    if not dragItem then return end

    local ds = GS.invSlotSize or 28
    local dx = GS.dragOffsetX - ds / 2
    local dy = GS.dragOffsetY - ds / 2

    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx + 2, dy + 2, ds, ds, 3)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx, dy, ds, ds, 3)
    nvgFillColor(vg, nvgRGBA(155, 110, 60, 230))
    nvgFill(vg)

    -- 图标
    local imgHandle = dragItem.icon and GS.itemImages[dragItem.icon]
    if imgHandle then
        local pad = 2
        local imgPaint = nvgImagePattern(vg,
            dx + pad, dy + pad,
            ds - pad * 2, ds - pad * 2,
            0, imgHandle, 0.9)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dx + pad, dy + pad, ds - pad * 2, ds - pad * 2, 2)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 稀有度边框
    local rarityDef = GS.RARITY[dragItem.rarity]
    if rarityDef then
        local bc = rarityDef.border
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dx + 0.5, dy + 0.5, ds - 1, ds - 1, 3)
        nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 220))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
end


-- ====================================================================
-- ====================================================================
-- 统一对话框绘制（名字方格 + 好感度方格 + 对话正文 + 选项/提示）
-- ====================================================================

--- 统一对话框绘制函数，供事件对话和建筑对话共用
---@param vg userdata NanoVG context
---@param line table 当前对话行 { speaker, text, choices? }
---@param bx number 棋盘左上角X
---@param by number 棋盘左上角Y
---@param boardSize number 棋盘边长
---@param opts? table { showChoices:boolean, isLastLine:boolean }
function M._drawDialogueBox(vg, line, bx, by, boardSize, opts)
    opts = opts or {}
    local margin = boardSize * 0.05
    local dlgH = boardSize * 0.28
    local dlgX = bx + margin
    local dlgW = boardSize - margin * 2
    local dlgR = 8

    -- 名字标签尺寸
    local tagH = boardSize * 0.055
    local tagR = 5
    local tagPadX = tagH * 0.5
    local tagFontSize = math.max(11, tagH * 0.6)
    local tagGap = boardSize * 0.012  -- 名字标签与好感度标签间距

    -- 对话框Y位置（给标签留空间）
    local dlgY = by + boardSize - dlgH - margin
    local tagY = dlgY - tagH - 3  -- 标签紧贴对话框上方

    -- ---- 名字标签 ----
    nvgFontSize(vg, tagFontSize)
    nvgFontFace(vg, "sans")
    local nameW = nvgTextBounds(vg, 0, 0, line.speaker or "???", nil)
    local nameTagW = nameW + tagPadX * 2

    -- 名字标签背景（半透明）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, tagY, nameTagW, tagH, tagR)
    nvgFillColor(vg, nvgRGBA(30, 25, 15, 190))
    nvgFill(vg)
    -- 名字标签边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, tagY, nameTagW, tagH, tagR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    -- 名字文字
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 210, 120, 255))
    nvgText(vg, dlgX + tagPadX, tagY + tagH * 0.5, line.speaker or "???", nil)

    -- ---- 好感度标签（旁白/系统等非NPC说话人不显示）----
    local skipAffinity = (line.speaker == "旁白" or line.speaker == "系统")
    local affTagX = dlgX + nameTagW
    local affTagW = 0
    if not skipAffinity then
        local affinityLabel, ar, ag, ab = GS.getAffinityLabel(line.speaker)
        local affinityText = affinityLabel
        local affinityW = nvgTextBounds(vg, 0, 0, affinityText, nil)
        affTagW = affinityW + tagPadX * 2
        affTagX = dlgX + nameTagW + tagGap

        -- 好感度标签背景（半透明）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, affTagX, tagY, affTagW, tagH, tagR)
        nvgFillColor(vg, nvgRGBA(25, 20, 12, 180))
        nvgFill(vg)
        -- 好感度标签边框（使用好感度颜色）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, affTagX, tagY, affTagW, tagH, tagR)
        nvgStrokeColor(vg, nvgRGBA(ar, ag, ab, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 好感度文字
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(ar, ag, ab, 255))
        nvgText(vg, affTagX + tagPadX, tagY + tagH * 0.5, affinityText, nil)

        -- ---- 好感度上限锁图标（冒险者等级不足时） ----
        local curAff = GS.getAffinity(line.speaker)
        local rankCap = GS.getAffinityCapByRank()
        if curAff >= rankCap and rankCap < 500 and M.lockClosedImg and M.lockClosedImg > 0 then
            local lockSz = math.max(10, tagH * 0.6)
            local lx = affTagX + affTagW - lockSz * 0.65
            local ly = tagY - lockSz * 0.3
            local paint = nvgImagePattern(vg, lx, ly, lockSz, lockSz, 0, M.lockClosedImg, 0.9)
            nvgBeginPath(vg)
            nvgRect(vg, lx, ly, lockSz, lockSz)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end

        -- ---- 好感度提升动画：普通=绿色加号，伴侣=粉色爱心 ----
        if GS.affinityAnim then
            local elapsed = time.elapsedTime - GS.affinityAnim.startTime
            local totalDur = 1.5  -- 动画总时长（秒）
            local isPartnerAnim = GS.affinityAnim.isPartner
            if elapsed > totalDur then
                GS.affinityAnim = nil
            else
                nvgFontFace(vg, "sans")
                nvgFontBlur(vg, 0)
                local symbol = "+"
                -- 三个符号字号（递增），伴侣爱心整体缩小
                local plusFontSizes = isPartnerAnim
                    and { tagH * 0.8, tagH * 1.0, tagH * 1.2 }
                    or  { tagH * 0.9, tagH * 1.15, tagH * 1.4 }
                local plusDelays    = { 0.0, 0.18, 0.36 }
                -- 测量每个符号在 scale=1.0 时的字符宽度，用于计算重叠布局
                local plusWidths = {}
                for i, fs in ipairs(plusFontSizes) do
                    nvgFontSize(vg, fs)
                    plusWidths[i] = nvgTextBounds(vg, 0, 0, symbol, nil)
                end
                local offX = { 0, plusWidths[2] * 0.5, plusWidths[2] * 0.5 + plusWidths[3] * 0.5 }
                local baseX = affTagX + affTagW + plusWidths[1] * 0.5 + 2
                local baseY = tagY + tagH
                local outlineOffsets = {
                    {-1,0},{1,0},{0,-1},{0,1},
                    {-0.7,-0.7},{0.7,-0.7},{-0.7,0.7},{0.7,0.7},
                    {-1,-0.5},{1,-0.5},{-1,0.5},{1,0.5},
                }
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                for i = 1, 3 do
                    local t = elapsed - plusDelays[i]
                    if t > 0 then
                        local lifeDur = totalDur - plusDelays[i]
                        local progress = t / lifeDur  -- 0~1
                        -- 弹性缩放
                        local scale
                        if progress < 0.12 then
                            scale = 0.2 + 0.95 * (progress / 0.12)
                        elseif progress < 0.25 then
                            scale = 1.15 - 0.15 * ((progress - 0.12) / 0.13)
                        else
                            scale = 1.0
                        end
                        -- 上浮位移
                        local floatY = -tagH * 0.6 * progress
                        -- 透明度
                        local alpha
                        if progress < 0.1 then
                            alpha = progress / 0.1
                        elseif progress < 0.5 then
                            alpha = 1.0
                        else
                            alpha = 1.0 - (progress - 0.5) / 0.5
                        end
                        alpha = math.max(0, math.min(1, alpha))
                        local a8 = math.floor(alpha * 255)
                        local sz = plusFontSizes[i] * scale
                        local dx = baseX + offX[i]
                        local dy = baseY + floatY
                        local olW = math.max(1.5, sz * 0.08)
                        nvgFontSize(vg, sz)
                        if isPartnerAnim then
                            -- 伴侣风格：NanoVG 路径绘制粉色爱心（避免 emoji fallback）
                            local hs = sz * 0.45  -- 爱心半径
                            -- 爱心中心偏上（ALIGN_BOTTOM 基线上方）
                            local hx, hy = dx, dy - hs * 0.8
                            -- 绘制爱心路径的闭包
                            local function heartPath(cx, cy, s)
                                local w, h = s * 0.8, s * 0.6
                                nvgBeginPath(vg)
                                nvgMoveTo(vg, cx, cy + h)
                                nvgBezierTo(vg, cx - w * 0.6, cy + h * 0.4, cx - w, cy - h * 0.2, cx - w * 0.5, cy - h * 0.6)
                                nvgBezierTo(vg, cx - w * 0.1, cy - h, cx, cy - h * 0.6, cx, cy - h * 0.2)
                                nvgBezierTo(vg, cx, cy - h * 0.6, cx + w * 0.1, cy - h, cx + w * 0.5, cy - h * 0.6)
                                nvgBezierTo(vg, cx + w, cy - h * 0.2, cx + w * 0.6, cy + h * 0.4, cx, cy + h)
                                nvgClosePath(vg)
                            end
                            -- 层1：白色描边（缩小描边宽度）
                            local heartOlW = math.max(1.0, sz * 0.04)
                            nvgFillColor(vg, nvgRGBA(255, 255, 255, a8))
                            local heartOutline = {
                                {-1,0},{1,0},{0,-1},{0,1},
                                {-0.7,-0.7},{0.7,-0.7},{-0.7,0.7},{0.7,0.7},
                            }
                            for _, off in ipairs(heartOutline) do
                                heartPath(hx + off[1] * heartOlW, hy + off[2] * heartOlW, hs)
                                nvgFill(vg)
                            end
                            -- 层2：阴影
                            local shOff = math.max(1, hs * 0.06)
                            nvgFillColor(vg, nvgRGBA(180, 60, 100, math.floor(a8 * 0.6)))
                            heartPath(hx + shOff, hy + shOff, hs)
                            nvgFill(vg)
                            -- 层3：粉色主体
                            nvgFillColor(vg, nvgRGBA(255, 130, 170, a8))
                            heartPath(hx, hy, hs)
                            nvgFill(vg)
                            -- 层4：高光（缩小高光面积）
                            nvgFillColor(vg, nvgRGBA(255, 210, 230, math.floor(a8 * 0.4)))
                            heartPath(hx, hy - hs * 0.08, hs * 0.4)
                            nvgFill(vg)
                        else
                            -- 普通风格：绿色加号
                            -- 层1：外发光
                            nvgFontBlur(vg, sz * 0.4)
                            nvgFillColor(vg, nvgRGBA(30, 255, 30, math.floor(a8 * 0.5)))
                            nvgText(vg, dx, dy, symbol, nil)
                            nvgText(vg, dx, dy, symbol, nil)
                            nvgFontBlur(vg, 0)
                            -- 层2：白色描边（12方向偏移）
                            nvgFillColor(vg, nvgRGBA(255, 255, 255, a8))
                            for _, off in ipairs(outlineOffsets) do
                                nvgText(vg, dx + off[1] * olW, dy + off[2] * olW, symbol, nil)
                            end
                            -- 层3：深绿内阴影
                            local shOff = math.max(1, sz * 0.04)
                            nvgFillColor(vg, nvgRGBA(10, 100, 10, math.floor(a8 * 0.7)))
                            nvgText(vg, dx + shOff, dy + shOff, symbol, nil)
                            -- 层4：实心亮绿主体
                            nvgFillColor(vg, nvgRGBA(40, 235, 40, a8))
                            nvgText(vg, dx, dy, symbol, nil)
                            -- 层5：顶部高光
                            nvgFontSize(vg, sz * 0.65)
                            local hlOff = math.max(0.5, sz * 0.025)
                            nvgFillColor(vg, nvgRGBA(200, 255, 200, math.floor(a8 * 0.55)))
                            nvgText(vg, dx, dy - hlOff, symbol, nil)
                        end
                    end
                end
            end
        end

        -- ---- 好感度下降动画：三个红色减号依次出现、变大、下沉消失 ----
        if GS.affinityDownAnim then
            local elapsed = time.elapsedTime - GS.affinityDownAnim.startTime
            local totalDur = 1.5
            if elapsed > totalDur then
                GS.affinityDownAnim = nil
            else
                nvgFontFace(vg, "sans")
                nvgFontBlur(vg, 0)
                local minusFontSizes = { tagH * 0.9, tagH * 1.15, tagH * 1.4 }
                local minusDelays    = { 0.0, 0.18, 0.36 }
                local minusWidths = {}
                for i, fs in ipairs(minusFontSizes) do
                    nvgFontSize(vg, fs)
                    minusWidths[i] = nvgTextBounds(vg, 0, 0, "-", nil)
                end
                local offX = { 0, minusWidths[2] * 0.5, minusWidths[2] * 0.5 + minusWidths[3] * 0.5 }
                local baseX = affTagX + affTagW + minusWidths[1] * 0.5 + 2
                local baseY = tagY - tagH * 0.5  -- 上边缘高于好感度框顶部
                local outlineOffsets = {
                    {-1,0},{1,0},{0,-1},{0,1},
                    {-0.7,-0.7},{0.7,-0.7},{-0.7,0.7},{0.7,0.7},
                    {-1,-0.5},{1,-0.5},{-1,0.5},{1,0.5},
                }
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                for i = 1, 3 do
                    local t = elapsed - minusDelays[i]
                    if t > 0 then
                        local lifeDur = totalDur - minusDelays[i]
                        local progress = t / lifeDur
                        -- 弹性缩放（与提升动画对称）
                        local scale
                        if progress < 0.12 then
                            scale = 0.2 + 0.95 * (progress / 0.12)
                        elseif progress < 0.25 then
                            scale = 1.15 - 0.15 * ((progress - 0.12) / 0.13)
                        else
                            scale = 1.0
                        end
                        -- 向下位移（与提升动画的向上对称）
                        local floatY = tagH * 0.6 * progress
                        -- 透明度
                        local alpha
                        if progress < 0.1 then
                            alpha = progress / 0.1
                        elseif progress < 0.5 then
                            alpha = 1.0
                        else
                            alpha = 1.0 - (progress - 0.5) / 0.5
                        end
                        alpha = math.max(0, math.min(1, alpha))
                        local a8 = math.floor(alpha * 255)
                        local sz = minusFontSizes[i] * scale
                        local dx = baseX + offX[i]
                        local dy = baseY + floatY
                        local olW = math.max(1.5, sz * 0.08)
                        nvgFontSize(vg, sz)
                        -- 层1：外发光（红色）
                        nvgFontBlur(vg, sz * 0.4)
                        nvgFillColor(vg, nvgRGBA(255, 30, 30, math.floor(a8 * 0.5)))
                        nvgText(vg, dx, dy, "-", nil)
                        nvgText(vg, dx, dy, "-", nil)
                        nvgFontBlur(vg, 0)
                        -- 层2：白色描边
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, a8))
                        for _, off in ipairs(outlineOffsets) do
                            nvgText(vg, dx + off[1] * olW, dy + off[2] * olW, "-", nil)
                        end
                        -- 层3：深红内阴影
                        local shOff = math.max(1, sz * 0.04)
                        nvgFillColor(vg, nvgRGBA(100, 10, 10, math.floor(a8 * 0.7)))
                        nvgText(vg, dx + shOff, dy + shOff, "-", nil)
                        -- 层4：实心亮红主体
                        nvgFillColor(vg, nvgRGBA(235, 40, 40, a8))
                        nvgText(vg, dx, dy, "-", nil)
                        -- 层5：顶部高光
                        nvgFontSize(vg, sz * 0.65)
                        local hlOff = math.max(0.5, sz * 0.025)
                        nvgFillColor(vg, nvgRGBA(255, 200, 200, math.floor(a8 * 0.55)))
                        nvgText(vg, dx, dy + hlOff, "-", nil)
                    end
                end
            end
        end


    end

    -- ---- 对话框正文区域 ----
    -- 半透明背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, dlgR)
    nvgFillColor(vg, nvgRGBA(20, 15, 8, 200))
    nvgFill(vg)
    -- 金色边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, dlgR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    local padX = dlgW * 0.06
    local padY = dlgH * 0.12

    -- 对话文本（白色，自动换行）
    local textFontSize = math.max(11, dlgH * 0.15)
    local textY = dlgY + padY
    local textW = dlgW - padX * 2
    nvgFontSize(vg, textFontSize)
    nvgFillColor(vg, nvgRGBA(230, 225, 210, 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgTextBox(vg, dlgX + padX, textY, textW, line.text, nil)

    -- 选项按钮或提示
    local DialogueManager = require("DialogueManager")
    if line.choices and DialogueManager.waitingForChoice then
        -- 左侧标签右边缘 = 好感度标签右边缘
        local leftTagsRight = affTagX + affTagW
        M._drawDialogueChoices(vg, line.choices, dlgX, dlgW, tagH, tagY, tagR, tagFontSize, leftTagsRight)
    else
        -- 右下角提示（闪烁）
        local elapsed = GetTime():GetElapsedTime()
        local blinkAlpha = math.floor(math.abs(math.sin(elapsed * 2.5)) * 180 + 50)
        local hintFontSize = math.max(10, dlgH * 0.11)
        nvgFontSize(vg, hintFontSize)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 180, 130, blinkAlpha))
        local isLast = opts.isLastLine
        if isLast == nil then isLast = DialogueManager.isLastLine() end
        local hintText = isLast and "结束对话" or "点击继续  ▶"
        nvgText(vg, dlgX + dlgW - padX, dlgY + dlgH - padY * 0.6, hintText, nil)
    end

    return { x = dlgX, y = dlgY, w = dlgW, h = dlgH }
end

-- ====================================================================
-- 事件对话框渲染（不依赖 BoardOverlay，事件期间独立绘制）
-- ====================================================================
function M.drawEventDialogue()
    local DialogueManager = require("DialogueManager")
    if not DialogueManager.active then return end
    -- 仅在事件期间、竞技场过场、酒馆肉搏时绘制
    -- （BoardOverlay 激活时由 BoardOverlay 自行绘制）
    if not GS.isEvent and not GS.arenaTransition and not GS.homePartnerTalkActive
       and not GS.tavernBrawlState and not GS.brawlCinematic then return end

    local line = DialogueManager.getCurrentLine()
    if not line then return end

    local vg = M.vg
    if not vg then return end

    local boardSize = GS.CELL * GS.BOARD_SIZE
    local bx = GS.BOARD_X
    local by = GS.BOARD_Y

    M._drawDialogueBox(vg, line, bx, by, boardSize)
end

--- 绘制对话选项按钮（右对齐，底部与名字标签对齐，等宽自适应，文本过长自动换行）
---@param vg userdata
---@param choices string[]
---@param dlgX number 对话框左边X
---@param dlgW number 对话框宽度
---@param tagH number 名字标签高度（选项同高）
---@param tagY number 名字标签Y位置（最底部选项对齐此行）
---@param tagR number 标签圆角
---@param tagFontSize number 标签字号
---@param leftTagsRight number 左侧标签（名字+好感度）的右边缘X坐标
function M._drawDialogueChoices(vg, choices, dlgX, dlgW, tagH, tagY, tagR, tagFontSize, leftTagsRight)
    local count = #choices
    if count == 0 then return end

    local btnH = tagH  -- 与名字标签同高（单行）
    local gap = 3      -- 选项间距（紧凑）
    local btnPadX = tagH * 0.5  -- 按钮内边距
    local safeGap = tagH * 0.3  -- 选项与左侧标签的最小安全间距

    nvgFontSize(vg, tagFontSize)
    nvgFontFace(vg, "sans")

    -- 先测量数字前缀"1."的宽度，用于换行时第二行的文字对齐偏移
    local numPrefixSampleW = nvgTextBounds(vg, 0, 0, "1.", nil)

    -- 测量最宽的序号数字宽度（用于按"."对齐）
    local dotW = nvgTextBounds(vg, 0, 0, ".", nil)
    local maxDigitW = 0
    for i = 1, #choices do
        local dw = nvgTextBounds(vg, 0, 0, tostring(i), nil)
        if dw > maxDigitW then maxDigitW = dw end
    end
    local alignedPrefixW = maxDigitW + dotW  -- 对齐后的序号总宽度

    -- 计算等宽：找最宽的选项文字（含数字前缀）
    local maxTextW = 0
    for i, label in ipairs(choices) do
        local displayLabel = i .. "." .. label
        local tw = nvgTextBounds(vg, 0, 0, displayLabel, nil)
        if tw > maxTextW then maxTextW = tw end
    end
    local btnW = maxTextW + btnPadX * 2

    -- 右对齐：按钮右边缘与对话框右边缘对齐
    local btnX = dlgX + dlgW - btnW

    -- 检测是否会与左侧标签重叠（仅当最底行选项需要检查）
    local leftBound = (leftTagsRight or dlgX) + safeGap
    -- 可用的最大按钮宽度（不超过左侧标签右边缘）
    local maxBtnW = dlgX + dlgW - leftBound

    -- 预计算每个选项是否需要换行，以及换行信息
    ---@type {label:string, numPrefix:string, needWrap:boolean, line1:string, line2:string}[]
    local choiceInfos = {}
    for i, label in ipairs(choices) do
        local numPrefix = i .. "."
        local fullText = numPrefix .. label
        local fullW = nvgTextBounds(vg, 0, 0, fullText, nil)
        local singleBtnW = fullW + btnPadX * 2
        local info = { label = label, numPrefix = numPrefix, needWrap = false, line1 = "", line2 = "" }

        if singleBtnW > maxBtnW and #label > 2 then
            -- 需要换行：找到合适的断点，使第一行不超过 maxBtnW
            -- 第一行包含数字前缀 + 部分文本，第二行仅文本（与第一行文本左对齐）
            info.needWrap = true
            -- 第二行的可用文本区域宽度 = maxBtnW - 两侧内边距
            local availTextW = maxBtnW - btnPadX * 2
            -- 第一行可用宽度（包含数字前缀）
            local line1AvailW = availTextW
            -- 逐字符查找断点（从后往前找到第一行能容纳的最大字符数）
            local labelBytes = label
            local bestBreak = #labelBytes  -- 默认不拆分
            local accText = numPrefix
            -- 遍历 UTF-8 字符
            local pos = 1
            local charPositions = {}  -- 记录每个字符结束后的字节位置
            while pos <= #labelBytes do
                local byte = string.byte(labelBytes, pos)
                local charLen = 1
                if byte >= 0xF0 then charLen = 4
                elseif byte >= 0xE0 then charLen = 3
                elseif byte >= 0xC0 then charLen = 2
                end
                local nextPos = pos + charLen
                charPositions[#charPositions + 1] = nextPos
                pos = nextPos
            end
            -- 从前往后找到第一行能容纳的最多字符
            bestBreak = #labelBytes  -- 如果全部放得下就不拆
            for ci, endPos in ipairs(charPositions) do
                local partial = numPrefix .. string.sub(labelBytes, 1, endPos - 1)
                local pw = nvgTextBounds(vg, 0, 0, partial, nil)
                if pw > line1AvailW then
                    -- 这个字符放不下了，断在上一个字符
                    if ci > 1 then
                        bestBreak = charPositions[ci - 1]
                    else
                        bestBreak = charPositions[1]  -- 至少放一个字符
                    end
                    break
                end
            end
            if bestBreak >= #labelBytes then
                -- 实际上放得下，不需要换行（安全回退）
                info.needWrap = false
            else
                info.line1 = string.sub(labelBytes, 1, bestBreak - 1)
                info.line2 = string.sub(labelBytes, bestBreak)
            end
        end
        choiceInfos[i] = info
    end

    -- 重新计算等宽 btnW：对于换行的选项，取 maxBtnW 和最宽单行选项的较大值
    local hasAnyWrap = false
    for _, info in ipairs(choiceInfos) do
        if info.needWrap then hasAnyWrap = true; break end
    end
    if hasAnyWrap then
        -- 当存在换行选项时，按钮宽度取 maxBtnW（填满可用空间）
        btnW = maxBtnW
        btnX = dlgX + dlgW - btnW
    end

    -- 计算每个选项的实际高度（换行的双倍高度）
    local totalH = 0
    for i, info in ipairs(choiceInfos) do
        local h = info.needWrap and (btnH * 2) or btnH
        if i > 1 then totalH = totalH + gap end
        totalH = totalH + h
    end

    -- 底部对齐：最后一个选项底边 = tagY + tagH
    local bottomEdge = tagY + tagH
    local startY = bottomEdge - totalH

    -- 保存选项按钮区域供点击检测
    GS._choiceRects = {}

    local curY = startY
    for i, info in ipairs(choiceInfos) do
        local curBtnH = info.needWrap and (btnH * 2) or btnH
        local btnY = curY

        -- 悬停检测
        local hovered = GS.hoverX and GS.hoverY
            and GS.hoverX >= btnX and GS.hoverX <= btnX + btnW
            and GS.hoverY >= btnY and GS.hoverY <= btnY + curBtnH

        -- 按钮背景（半透明）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, curBtnH, tagR)
        if hovered then
            nvgFillColor(vg, nvgRGBA(55, 45, 25, 200))
        else
            nvgFillColor(vg, nvgRGBA(30, 25, 15, 180))
        end
        nvgFill(vg)

        -- 按钮边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, curBtnH, tagR)
        nvgStrokeColor(vg, hovered and nvgRGBA(255, 220, 120, 240) or nvgRGBA(180, 150, 80, 180))
        nvgStrokeWidth(vg, hovered and 2 or 1.5)
        nvgStroke(vg)

        -- 按钮文字
        nvgFontSize(vg, tagFontSize)
        nvgFontFace(vg, "sans")
        local textColor = hovered and nvgRGBA(255, 230, 150, 255) or nvgRGBA(220, 200, 150, 240)
        nvgFillColor(vg, textColor)

        -- 计算数字前缀宽度（badge 和文字都需要用到）
        local numPrefixW = nvgTextBounds(vg, 0, 0, info.numPrefix, nil)

        -- 任务 badge（替代序号，放在序号位置）
        local badgeInfo = GS._choiceBadges and GS._choiceBadges[i]  -- { type, category }
        local hasBadge = badgeInfo ~= nil
        if hasBadge then
            local badgeR = btnH * 0.28
            -- badge 放在序号位置（左侧居中）
            local badgeCX = btnX + btnPadX * 0.4 + badgeR
            local badgeCY = btnY + (info.needWrap and (btnH * 0.5) or (curBtnH * 0.5))
            -- 填充色：主线金色 / 支线蓝色
            local isMain = badgeInfo.category == "main"
            local fr, fg, fb = 50, 100, 200     -- 支线：蓝色
            if isMain then fr, fg, fb = 200, 165, 40 end  -- 主线：金色
            -- 圆形底板
            nvgBeginPath(vg)
            nvgCircle(vg, badgeCX, badgeCY, badgeR)
            nvgFillColor(vg, nvgRGBA(fr, fg, fb, 230))
            nvgFill(vg)
            -- 白色外圈
            nvgStrokeWidth(vg, math.max(1.5, badgeR * 0.14))
            nvgStrokeColor(vg, nvgRGBA(245, 240, 230, 230))
            nvgStroke(vg)
            -- 白色符号
            local sym = badgeInfo.type == "accept" and "!" or "★"
            nvgFontSize(vg, tagFontSize * 0.75)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, badgeCX, badgeCY, sym, nil)
            -- 恢复字号和颜色
            nvgFontSize(vg, tagFontSize)
            nvgFillColor(vg, textColor)
        end

        -- 文本起始位置
        local leftEdge = btnX + btnPadX * 0.4
        local contentStartX
        if hasBadge then
            local badgeR = btnH * 0.28
            contentStartX = leftEdge + badgeR * 2 + 4
        else
            contentStartX = leftEdge + alignedPrefixW
        end

        if info.needWrap then
            local row1Y = btnY + btnH * 0.5
            local row2Y = btnY + btnH * 1.5
            if not hasBadge then
                -- 数字右对齐到 maxDigitW 位置，"."紧随其后
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgText(vg, leftEdge + maxDigitW, row1Y, tostring(i), nil)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgText(vg, leftEdge + maxDigitW, row1Y, ".", nil)
            end
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, contentStartX, row1Y, info.line1, nil)
            nvgText(vg, contentStartX, row2Y, info.line2, nil)
        else
            if not hasBadge then
                -- 数字右对齐到 maxDigitW 位置，"."紧随其后
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgText(vg, leftEdge + maxDigitW, btnY + btnH * 0.5, tostring(i), nil)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgText(vg, leftEdge + maxDigitW, btnY + btnH * 0.5, ".", nil)
            end
            -- 文本右对齐
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgText(vg, btnX + btnW - btnPadX * 0.4, btnY + btnH * 0.5, info.label, nil)
        end

        GS._choiceRects[i] = { x = btnX, y = btnY, w = btnW, h = curBtnH }
        curY = curY + curBtnH + gap
    end
end

--- 绘制名字输入框覆盖层
function M.drawNameInput()
    local ni = GS.eventNameInput
    if not ni or not ni.active then return end

    local vg = M.vg
    if not vg then return end

    local boardSize = GS.CELL * GS.BOARD_SIZE
    local bx = GS.BOARD_X
    local by = GS.BOARD_Y
    local centerX = bx + boardSize * 0.5
    local centerY = by + boardSize * 0.4

    -- 面板尺寸
    local panelW = boardSize * 0.7
    local panelH = boardSize * 0.35
    local panelX = centerX - panelW * 0.5
    local panelY = centerY - panelH * 0.5
    local panelR = 10

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, bx, by, boardSize, boardSize)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgFillColor(vg, nvgRGBA(30, 25, 15, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    local titleSize = math.max(14, panelH * 0.14)
    nvgFontSize(vg, titleSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(240, 210, 120, 255))
    nvgText(vg, centerX, panelY + panelH * 0.1, "请输入你的名字", nil)

    -- 输入框
    local inputW = panelW * 0.75
    local inputH = panelH * 0.22
    local inputX = centerX - inputW * 0.5
    local inputY = panelY + panelH * 0.35
    local inputR = 6

    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgFillColor(vg, nvgRGBA(50, 45, 30, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 80, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 输入文字或占位符
    local inputFontSize = math.max(13, inputH * 0.5)
    nvgFontSize(vg, inputFontSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textPad = inputW * 0.06
    local displayText = ni.text or ""
    if #displayText == 0 then
        nvgFillColor(vg, nvgRGBA(120, 110, 80, 150))
        nvgText(vg, inputX + textPad, inputY + inputH * 0.5, ni.placeholder or "请输入名字...", nil)
    else
        nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
        nvgText(vg, inputX + textPad, inputY + inputH * 0.5, displayText, nil)
    end

    -- 光标闪烁
    local elapsed = GetTime():GetElapsedTime()
    if math.floor(elapsed * 2) % 2 == 0 then
        -- 计算光标位置
        nvgFontSize(vg, inputFontSize)
        local textEndX
        if #displayText > 0 then
            local tw = nvgTextBounds(vg, 0, 0, displayText, nil)
            textEndX = inputX + textPad + tw + 2
        else
            textEndX = inputX + textPad
        end
        nvgBeginPath(vg)
        nvgRect(vg, textEndX, inputY + inputH * 0.2, 2, inputH * 0.6)
        nvgFillColor(vg, nvgRGBA(240, 210, 120, 200))
        nvgFill(vg)
    end

    -- 确定按钮
    local btnW = panelW * 0.35
    local btnH = panelH * 0.18
    local btnX = centerX - btnW * 0.5
    local btnY = panelY + panelH * 0.72
    local btnR = 6

    local canConfirm = displayText and #displayText > 0
    local hovered = canConfirm and GS.hoverX and GS.hoverY
        and GS.hoverX >= btnX and GS.hoverX <= btnX + btnW
        and GS.hoverY >= btnY and GS.hoverY <= btnY + btnH

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, btnR)
    if not canConfirm then
        nvgFillColor(vg, nvgRGBA(40, 35, 25, 200))
    elseif hovered then
        nvgFillColor(vg, nvgRGBA(80, 65, 30, 240))
    else
        nvgFillColor(vg, nvgRGBA(50, 42, 22, 230))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, btnR)
    nvgStrokeColor(vg, canConfirm and nvgRGBA(210, 180, 100, 240) or nvgRGBA(100, 90, 60, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local btnFontSize = math.max(11, btnH * 0.5)
    nvgFontSize(vg, btnFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, canConfirm and nvgRGBA(240, 220, 150, 255) or nvgRGBA(100, 90, 60, 150))
    nvgText(vg, centerX, btnY + btnH * 0.5, "确  定", nil)

    -- 保存按钮区域供点击检测
    GS._nameInputConfirmRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    GS._nameInputRect = { x = inputX, y = inputY, w = inputW, h = inputH }
end

--- 绘制改名输入框覆盖层（设置面板触发）
function M.drawRenameInput()
    local ri = GS.renameInput
    if not ri or not ri.active then return end

    local vg = M.vg
    if not vg then return end

    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩覆盖全屏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    -- 面板尺寸
    local panelW = math.min(320, W * 0.75)
    local panelH = 160
    local panelX = (W - panelW) * 0.5
    local panelY = (H - panelH) * 0.4
    local panelR = 10
    local centerX = W * 0.5

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgFillColor(vg, nvgRGBA(30, 25, 15, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgStrokeColor(vg, nvgRGBA(140, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontSize(vg, 16)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 140, 255))
    nvgText(vg, centerX, panelY + 14, "修改姓名", nil)

    -- 当前名字提示
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(160, 155, 130, 180))
    nvgText(vg, centerX, panelY + 36, "当前: " .. (GS.charName or ""), nil)

    -- 输入框
    local inputW = panelW * 0.75
    local inputH = 30
    local inputX = centerX - inputW * 0.5
    local inputY = panelY + 56
    local inputR = 6

    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgFillColor(vg, nvgRGBA(50, 45, 30, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgStrokeColor(vg, nvgRGBA(140, 180, 100, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 输入文字或占位符
    local inputFontSize = 14
    nvgFontSize(vg, inputFontSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textPad = 10
    local displayText = ri.text or ""
    -- IME 组合中显示组合文本
    if ri.imeComposing and ri.imeComposition and #ri.imeComposition > 0 then
        displayText = displayText .. ri.imeComposition
    end
    if #displayText == 0 then
        nvgFillColor(vg, nvgRGBA(120, 110, 80, 150))
        nvgText(vg, inputX + textPad, inputY + inputH * 0.5, "请输入新名字...", nil)
    else
        nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
        nvgText(vg, inputX + textPad, inputY + inputH * 0.5, displayText, nil)
    end

    -- 光标闪烁
    local elapsed = GetTime():GetElapsedTime()
    if math.floor(elapsed * 2) % 2 == 0 then
        nvgFontSize(vg, inputFontSize)
        local textEndX
        if #displayText > 0 then
            local tw = nvgTextBounds(vg, 0, 0, displayText, nil)
            textEndX = inputX + textPad + tw + 2
        else
            textEndX = inputX + textPad
        end
        nvgBeginPath(vg)
        nvgRect(vg, textEndX, inputY + inputH * 0.2, 2, inputH * 0.6)
        nvgFillColor(vg, nvgRGBA(180, 220, 140, 200))
        nvgFill(vg)
    end

    -- 按钮行：取消 + 确定
    local btnW = panelW * 0.3
    local btnH2 = 30
    local btnGap = 16
    local btnY = inputY + inputH + 18
    local cancelBtnX = centerX - btnGap / 2 - btnW
    local confirmBtnX = centerX + btnGap / 2
    local bR = 6

    -- 取消按钮
    local cancelHovered = GS.hoverX and GS.hoverY
        and GS.hoverX >= cancelBtnX and GS.hoverX <= cancelBtnX + btnW
        and GS.hoverY >= btnY and GS.hoverY <= btnY + btnH2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, btnY, btnW, btnH2, bR)
    nvgFillColor(vg, cancelHovered and nvgRGBA(70, 60, 50, 240) or nvgRGBA(50, 42, 35, 230))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, btnY, btnW, btnH2, bR)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 120, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 170, 255))
    nvgText(vg, cancelBtnX + btnW / 2, btnY + btnH2 / 2, "取消", nil)

    -- 确定按钮
    local canConfirm = ri.text and #ri.text > 0
    local confirmHovered = canConfirm and GS.hoverX and GS.hoverY
        and GS.hoverX >= confirmBtnX and GS.hoverX <= confirmBtnX + btnW
        and GS.hoverY >= btnY and GS.hoverY <= btnY + btnH2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmBtnX, btnY, btnW, btnH2, bR)
    if not canConfirm then
        nvgFillColor(vg, nvgRGBA(40, 35, 25, 200))
    elseif confirmHovered then
        nvgFillColor(vg, nvgRGBA(60, 80, 40, 240))
    else
        nvgFillColor(vg, nvgRGBA(40, 60, 25, 230))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmBtnX, btnY, btnW, btnH2, bR)
    nvgStrokeColor(vg, canConfirm and nvgRGBA(140, 200, 100, 240) or nvgRGBA(80, 80, 60, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, canConfirm and nvgRGBA(180, 240, 140, 255) or nvgRGBA(80, 80, 60, 150))
    nvgText(vg, confirmBtnX + btnW / 2, btnY + btnH2 / 2, "确定", nil)

    -- 保存区域供点击检测
    GS._renameInputRect = { x = inputX, y = inputY, w = inputW, h = inputH }
    GS._renameCancelRect = { x = cancelBtnX, y = btnY, w = btnW, h = btnH2 }
    GS._renameConfirmRect = { x = confirmBtnX, y = btnY, w = btnW, h = btnH2 }
end

--- 绘制爱称修改输入框覆盖层（家中与伴侣交谈时使用）
function M.drawPetNameInput()
    local ni = GS.petNameInput
    if not ni or not ni.active then return end

    local vg = M.vg
    if not vg then return end

    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩覆盖全屏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 130))
    nvgFill(vg)

    -- 面板尺寸（自适应屏幕）
    local panelW = math.min(W * 0.75, 280)
    local panelH = math.min(H * 0.32, 130)
    local panelX = (W - panelW) / 2
    local panelY = (H - panelH) / 2
    local panelR = 10

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgFillColor(vg, nvgRGBA(30, 25, 15, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    local centerX = panelX + panelW / 2

    -- 标题
    local titleSize = math.max(14, panelH * 0.13)
    nvgFontSize(vg, titleSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(240, 210, 120, 255))
    nvgText(vg, centerX, panelY + panelH * 0.1, "你希望她怎么称呼你？", nil)

    -- 输入框
    local inputW = panelW * 0.75
    local inputH = panelH * 0.20
    local inputX = centerX - inputW / 2
    local inputY = panelY + panelH * 0.35
    local inputR = 6

    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgFillColor(vg, nvgRGBA(50, 45, 30, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 80, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 输入文字或占位符
    local inputFontSize = math.max(13, inputH * 0.5)
    nvgFontSize(vg, inputFontSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textPad = inputW * 0.06
    local displayText = ni.text or ""
    local imeComp = ni.imeComposition or ""

    if #displayText == 0 and #imeComp == 0 then
        nvgFillColor(vg, nvgRGBA(120, 110, 80, 150))
        nvgText(vg, inputX + textPad, inputY + inputH * 0.5, ni.placeholder or "请输入爱称...", nil)
    else
        -- 已确认文字
        if #displayText > 0 then
            nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
            nvgText(vg, inputX + textPad, inputY + inputH * 0.5, displayText, nil)
        end
        -- IME 组合预览（拼音）
        if #imeComp > 0 then
            nvgFontSize(vg, inputFontSize)
            local compX = inputX + textPad
            if #displayText > 0 then
                compX = compX + nvgTextBounds(vg, 0, 0, displayText, nil)
            end
            nvgFillColor(vg, nvgRGBA(180, 170, 120, 200))
            nvgText(vg, compX, inputY + inputH * 0.5, imeComp, nil)
            -- 组合文字下划线
            local compW = nvgTextBounds(vg, 0, 0, imeComp, nil)
            nvgBeginPath(vg)
            nvgRect(vg, compX, inputY + inputH * 0.75, compW, 1.5)
            nvgFillColor(vg, nvgRGBA(210, 180, 100, 180))
            nvgFill(vg)
        end
    end

    -- 光标闪烁（IME 组合期间不闪烁）
    if #imeComp == 0 then
        local elapsed = GetTime():GetElapsedTime()
        if math.floor(elapsed * 2) % 2 == 0 then
            nvgFontSize(vg, inputFontSize)
            local textEndX
            if #displayText > 0 then
                local tw = nvgTextBounds(vg, 0, 0, displayText, nil)
                textEndX = inputX + textPad + tw + 2
            else
                textEndX = inputX + textPad
            end
            nvgBeginPath(vg)
            nvgRect(vg, textEndX, inputY + inputH * 0.2, 2, inputH * 0.6)
            nvgFillColor(vg, nvgRGBA(240, 210, 120, 200))
            nvgFill(vg)
        end
    end

    -- 按钮行：取消（左）+ 确定（右）
    local btnW = panelW * 0.30
    local btnH2 = panelH * 0.18
    local btnGap = panelW * 0.05
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = centerX - totalBtnW / 2
    local btnY = panelY + panelH * 0.72
    local btnR = 6

    local cancelBtnX = btnStartX
    local confirmBtnX = btnStartX + btnW + btnGap

    -- 取消按钮
    local cancelHovered = GS.hoverX and GS.hoverY
        and GS.hoverX >= cancelBtnX and GS.hoverX <= cancelBtnX + btnW
        and GS.hoverY >= btnY and GS.hoverY <= btnY + btnH2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, btnY, btnW, btnH2, btnR)
    nvgFillColor(vg, cancelHovered and nvgRGBA(70, 55, 30, 240) or nvgRGBA(45, 38, 22, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, btnY, btnW, btnH2, btnR)
    nvgStrokeColor(vg, nvgRGBA(150, 130, 80, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local btnFontSize = math.max(11, btnH2 * 0.5)
    nvgFontSize(vg, btnFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 165, 120, 230))
    nvgText(vg, cancelBtnX + btnW / 2, btnY + btnH2 * 0.5, "取  消", nil)

    -- 确定按钮
    local canConfirm = displayText and #displayText > 0
    local confirmHovered = canConfirm and GS.hoverX and GS.hoverY
        and GS.hoverX >= confirmBtnX and GS.hoverX <= confirmBtnX + btnW
        and GS.hoverY >= btnY and GS.hoverY <= btnY + btnH2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmBtnX, btnY, btnW, btnH2, btnR)
    if not canConfirm then
        nvgFillColor(vg, nvgRGBA(40, 35, 25, 200))
    elseif confirmHovered then
        nvgFillColor(vg, nvgRGBA(80, 65, 30, 240))
    else
        nvgFillColor(vg, nvgRGBA(50, 42, 22, 230))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmBtnX, btnY, btnW, btnH2, btnR)
    nvgStrokeColor(vg, canConfirm and nvgRGBA(210, 180, 100, 240) or nvgRGBA(100, 90, 60, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontSize(vg, btnFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, canConfirm and nvgRGBA(240, 220, 150, 255) or nvgRGBA(100, 90, 60, 150))
    nvgText(vg, confirmBtnX + btnW / 2, btnY + btnH2 * 0.5, "确  定", nil)

    -- 保存按钮区域供点击检测
    GS._petNameInputConfirmRect = { x = confirmBtnX, y = btnY, w = btnW, h = btnH2 }
    GS._petNameInputCancelRect = { x = cancelBtnX, y = btnY, w = btnW, h = btnH2 }
    GS._petNameInputRect = { x = inputX, y = inputY, w = inputW, h = inputH }
end

-- ====================================================================
-- 兑换码输入弹窗
-- ====================================================================
function M.drawRedeemCodeDialog()
    local ri = GS.redeemCodeInput
    if not ri or not ri.active then return end

    local vg = M.vg
    if not vg then return end

    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 130))
    nvgFill(vg)

    -- 面板
    local panelW = math.min(W * 0.75, 280)
    local panelH = math.min(H * 0.32, 130)
    local panelX = (W - panelW) / 2
    local panelY = (H - panelH) / 2
    local panelR = 10

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgFillColor(vg, nvgRGBA(25, 20, 35, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 200, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    local centerX = panelX + panelW / 2

    -- 标题
    local titleSize = math.max(14, panelH * 0.13)
    nvgFontSize(vg, titleSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 180, 240, 255))
    nvgText(vg, centerX, panelY + panelH * 0.1, "输入兑换码", nil)

    -- 输入框
    local inputW = panelW * 0.80
    local inputH = panelH * 0.20
    local inputX = centerX - inputW / 2
    local inputY = panelY + panelH * 0.35
    local inputR = 6

    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgFillColor(vg, nvgRGBA(40, 35, 50, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, inputR)
    nvgStrokeColor(vg, nvgRGBA(130, 120, 170, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 输入文字或占位符
    local inputFontSize = math.max(13, inputH * 0.5)
    nvgFontSize(vg, inputFontSize)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textPad = inputW * 0.06
    local displayText = ri.text or ""
    local imeComp = ri.imeComposition or ""

    if #displayText == 0 and #imeComp == 0 then
        nvgFillColor(vg, nvgRGBA(100, 90, 130, 150))
        nvgText(vg, inputX + textPad, inputY + inputH * 0.5, "请输入兑换码...", nil)
    else
        if #displayText > 0 then
            nvgFillColor(vg, nvgRGBA(230, 225, 240, 255))
            nvgText(vg, inputX + textPad, inputY + inputH * 0.5, displayText, nil)
        end
        if #imeComp > 0 then
            nvgFontSize(vg, inputFontSize)
            local compX = inputX + textPad
            if #displayText > 0 then
                compX = compX + nvgTextBounds(vg, 0, 0, displayText, nil)
            end
            nvgFillColor(vg, nvgRGBA(160, 150, 200, 200))
            nvgText(vg, compX, inputY + inputH * 0.5, imeComp, nil)
            local compW = nvgTextBounds(vg, 0, 0, imeComp, nil)
            nvgBeginPath(vg)
            nvgRect(vg, compX, inputY + inputH * 0.75, compW, 1.5)
            nvgFillColor(vg, nvgRGBA(160, 140, 200, 180))
            nvgFill(vg)
        end
    end

    -- 光标闪烁
    if #imeComp == 0 then
        local elapsed = GetTime():GetElapsedTime()
        if math.floor(elapsed * 2) % 2 == 0 then
            nvgFontSize(vg, inputFontSize)
            local textEndX
            if #displayText > 0 then
                local tw = nvgTextBounds(vg, 0, 0, displayText, nil)
                textEndX = inputX + textPad + tw + 2
            else
                textEndX = inputX + textPad
            end
            nvgBeginPath(vg)
            nvgRect(vg, textEndX, inputY + inputH * 0.2, 2, inputH * 0.6)
            nvgFillColor(vg, nvgRGBA(200, 180, 240, 200))
            nvgFill(vg)
        end
    end

    -- 按钮行
    local btnW = panelW * 0.30
    local btnH3 = panelH * 0.18
    local btnGap = panelW * 0.05
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = centerX - totalBtnW / 2
    local btnY = panelY + panelH * 0.72
    local btnR2 = 6

    local cancelBtnX = btnStartX
    local confirmBtnX = btnStartX + btnW + btnGap

    -- 取消按钮
    local cancelHovered = GS.hoverX and GS.hoverY
        and GS.hoverX >= cancelBtnX and GS.hoverX <= cancelBtnX + btnW
        and GS.hoverY >= btnY and GS.hoverY <= btnY + btnH3
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, btnY, btnW, btnH3, btnR2)
    nvgFillColor(vg, cancelHovered and nvgRGBA(60, 50, 70, 240) or nvgRGBA(40, 35, 50, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, btnY, btnW, btnH3, btnR2)
    nvgStrokeColor(vg, nvgRGBA(130, 120, 170, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    local btnFontSize = math.max(11, btnH3 * 0.5)
    nvgFontSize(vg, btnFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(170, 160, 200, 230))
    nvgText(vg, cancelBtnX + btnW / 2, btnY + btnH3 * 0.5, "取  消", nil)

    -- 确定按钮
    local canConfirm = displayText and #displayText > 0
    local confirmHovered = canConfirm and GS.hoverX and GS.hoverY
        and GS.hoverX >= confirmBtnX and GS.hoverX <= confirmBtnX + btnW
        and GS.hoverY >= btnY and GS.hoverY <= btnY + btnH3
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmBtnX, btnY, btnW, btnH3, btnR2)
    if not canConfirm then
        nvgFillColor(vg, nvgRGBA(35, 30, 45, 200))
    elseif confirmHovered then
        nvgFillColor(vg, nvgRGBA(70, 55, 90, 240))
    else
        nvgFillColor(vg, nvgRGBA(45, 38, 60, 230))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmBtnX, btnY, btnW, btnH3, btnR2)
    nvgStrokeColor(vg, canConfirm and nvgRGBA(180, 160, 220, 240) or nvgRGBA(90, 80, 110, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontSize(vg, btnFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, canConfirm and nvgRGBA(220, 200, 255, 255) or nvgRGBA(90, 80, 110, 150))
    nvgText(vg, confirmBtnX + btnW / 2, btnY + btnH3 * 0.5, "确  定", nil)

    -- 保存区域供点击检测
    GS._redeemCodeConfirmRect = { x = confirmBtnX, y = btnY, w = btnW, h = btnH3 }
    GS._redeemCodeCancelRect = { x = cancelBtnX, y = btnY, w = btnW, h = btnH3 }
    GS._redeemCodeInputRect = { x = inputX, y = inputY, w = inputW, h = inputH }
end

-- 子模块加载（将函数挂载到 M 上，外部调用接口不变）
-- ====================================================================
require("Renderer_SkillEffects").init(M)
require("Renderer_BuffEffects").init(M)
require("Renderer_SpellEffects").init(M)
require("Renderer_Menus").init(M)
require("Renderer_Panels").init(M)

return M
