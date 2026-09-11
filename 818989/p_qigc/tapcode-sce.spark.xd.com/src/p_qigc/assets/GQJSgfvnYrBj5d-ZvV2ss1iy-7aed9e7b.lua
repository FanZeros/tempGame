-- ====================================================================
-- BoardOverlay.lua - 战斗棋盘覆盖层管理器
-- ====================================================================
-- 统一管理棋盘区域的非战斗内容展示
-- 使用场景：城镇画面、商店界面、剧情过场等
--
-- 用法:
--   BoardOverlay.register("town", "clearwater", imgHandle)
--   BoardOverlay.show("town", "clearwater", "清水镇")
--   BoardOverlay.hide()
--   if BoardOverlay.isActive() then ... end
-- ====================================================================

local GS = require "GameState"
local BulletinBoard = require "BulletinBoard"
local SSLog = require "SharedStorageLog"

local M = {}

-- 印章动画状态
M._stampAnim = nil  -- { questIdx, progress, duration }
M._stampSfx = nil   -- 盖章音效资源

-- 当前覆盖层状态
M.active = false
M.overlayType = nil     -- "town" | "shop" | "cutscene" | ...
M.overlayId = nil       -- 具体标识（如 "clearwater"）
M.imageHandle = nil     -- NanoVG 图片句柄
M.title = nil           -- 展示标题

-- 子场景状态（建筑内部）
M.subScene = nil        -- nil=无子场景, { id, imageHandle, title, buttons }
M.tavernDanceView = false -- 酒馆舞池视角切换

-- 图片注册表 { [type] = { [id] = handle } }
M.registry = {}

-- ====================================================================
-- 辅助：在指定槽位区域上绘制物品装饰（精炼/附魔/强化等级/锁定/收藏）
-- 与 Renderer.lua 中背包栏的装饰层保持一致
-- ====================================================================
local Renderer -- 延迟引用，避免循环依赖

local function drawItemDecorations(vg, item, sx, sy, slotSize)
    if not item then return end
    if not Renderer then Renderer = require "Renderer" end

    -- 按槽位尺寸比例计算装饰大小
    local iconOff = slotSize * 0.16   -- 图标中心距角落偏移
    local iconArm = slotSize * 0.10   -- 精炼十字臂长
    local iconVal = slotSize * 0.05   -- 精炼十字谷距
    local iconStar = slotSize * 0.10  -- 附魔星半径
    local iconStk = math.max(0.6, slotSize * 0.025) -- 描边宽度

    -- 深渊词缀标识：深紫色垂直缎带（与附魔星水平居中，限定在图片区域内使槽位边框自然压住缎带）
    if item.abyssAffix then
        local pad = 2
        local rW = slotSize * 0.15
        nvgSave(vg)
        nvgIntersectScissor(vg, sx + pad, sy + pad, slotSize - pad * 2, slotSize - pad * 2)
        nvgBeginPath(vg)
        nvgRect(vg, sx + iconOff - rW / 2, sy + pad, rW, slotSize - pad * 2)
        nvgFillColor(vg, nvgRGBA(90, 0, 155, 230))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 精炼槽标识（十字飞镖）
    if item.refineSlots and #item.refineSlots > 0 then
        local rfCx = sx + iconOff
        local rfCy = sy + iconOff
        local armD = iconArm
        local valD = iconVal
        local tips = {
            { rfCx - armD, rfCy - armD }, { rfCx + armD, rfCy - armD },
            { rfCx + armD, rfCy + armD }, { rfCx - armD, rfCy + armD },
        }
        local vals = {
            { rfCx - valD, rfCy }, { rfCx, rfCy - valD },
            { rfCx + valD, rfCy }, { rfCx, rfCy + valD },
        }
        for ri, rslot in ipairs(item.refineSlots) do
            if ri > 4 then break end
            local vi1 = ri
            local vi2 = (ri % 4) + 1
            nvgBeginPath(vg)
            nvgMoveTo(vg, rfCx, rfCy)
            nvgLineTo(vg, vals[vi1][1], vals[vi1][2])
            nvgLineTo(vg, tips[ri][1], tips[ri][2])
            nvgLineTo(vg, vals[vi2][1], vals[vi2][2])
            nvgClosePath(vg)
            if rslot.attr then
                local rt = rslot.rolledTier or 0
                local rr = (rt <= 1 and "common") or (rt <= 3 and "uncommon") or (rt <= 5 and "rare") or (rt <= 7 and "fine") or "superior"
                local rc = GS.RARITY[rr] and GS.RARITY[rr].color or {200,200,200}
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1]+50), math.min(255, rc[2]+50), math.min(255, rc[3]+50), 255))
            else
                nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 120))
            end
            nvgStrokeWidth(vg, iconStk)
            nvgStroke(vg)
        end
    end

    -- 附魔标识（四芒星）
    if item.enchantment then
        local ert = GS.getItemTier(item)
        local err = (ert <= 1 and "common") or (ert <= 3 and "uncommon") or (ert <= 5 and "rare") or (ert <= 7 and "fine") or "superior"
        local erc = GS.RARITY[err] and GS.RARITY[err].color or {80,160,255}
        local starCx = sx + iconOff
        local starCy = sy + iconOff
        local starR = iconStar
        nvgBeginPath(vg)
        nvgMoveTo(vg, starCx, starCy - starR)
        nvgLineTo(vg, starCx + starR * 0.3, starCy - starR * 0.3)
        nvgLineTo(vg, starCx + starR, starCy)
        nvgLineTo(vg, starCx + starR * 0.3, starCy + starR * 0.3)
        nvgLineTo(vg, starCx, starCy + starR)
        nvgLineTo(vg, starCx - starR * 0.3, starCy + starR * 0.3)
        nvgLineTo(vg, starCx - starR, starCy)
        nvgLineTo(vg, starCx - starR * 0.3, starCy - starR * 0.3)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(erc[1], erc[2], erc[3], 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(math.min(255, erc[1]+60), math.min(255, erc[2]+60), math.min(255, erc[3]+60), 255))
        nvgStrokeWidth(vg, math.max(iconStk, iconStk * 1.2))
        nvgStroke(vg)
    end

    -- 宝石插槽标识（圆形，叠于附魔标识上方，居中）
    if item.gemSlots and #item.gemSlots > 0 then
        local gemCx = sx + iconOff
        local gemCy = sy + iconOff
        local gemR = slotSize * 0.04
        local rarityRank = { common=1, uncommon=2, rare=3, fine=4, superior=5, epic=6, legendary=7, divine=8 }
        -- 找到已镶嵌宝石中最高稀有度
        local hasGem = false
        local bestRarity = nil
        for _, gs in ipairs(item.gemSlots) do
            if gs.gemId then
                hasGem = true
                local gemTpl = GS.itemTemplates[gs.gemId]
                if gemTpl then
                    local gr = gemTpl.rarity or "common"
                    if not bestRarity or (rarityRank[gr] or 0) > (rarityRank[bestRarity] or 0) then
                        bestRarity = gr
                    end
                end
            end
        end
        local gc
        if hasGem and bestRarity then
            gc = GS.RARITY[bestRarity] and GS.RARITY[bestRarity].color or {80, 200, 255}
        else
            gc = {160, 160, 160}  -- 未镶嵌：灰色
        end
        -- 深色底衬（增强可见度）
        nvgBeginPath(vg)
        nvgCircle(vg, gemCx, gemCy, gemR + slotSize * 0.01)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
        nvgFill(vg)
        -- 主体圆
        nvgBeginPath(vg)
        nvgCircle(vg, gemCx, gemCy, gemR)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], hasGem and 245 or 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(math.min(255, gc[1]+60), math.min(255, gc[2]+60), math.min(255, gc[3]+60), hasGem and 255 or 200))
        nvgStrokeWidth(vg, iconStk * 1.2)
        nvgStroke(vg)
    end

    -- 强化等级（右下角）
    if item.enhanceLevel and item.enhanceLevel > 0 then
        local enhText = "+" .. item.enhanceLevel
        local enhFs = math.max(7, math.floor(slotSize * 0.28))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, enhFs)
        local etw = nvgTextBounds(vg, 0, 0, enhText, nil, nil)
        local ePad = 2
        local eBgW = etw + ePad * 2
        local eBgH = enhFs + 3
        local eBgX = sx + slotSize - eBgW
        local eBgY = sy + slotSize - eBgH
        nvgBeginPath(vg)
        nvgRoundedRect(vg, eBgX, eBgY, eBgW, eBgH, 3)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
        nvgFill(vg)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local _, enhC = GS.getEnhanceRarity(item.enhanceLevel)
        nvgFillColor(vg, nvgRGBA(enhC[1], enhC[2], enhC[3], 255))
        nvgText(vg, eBgX + eBgW * 0.5, eBgY + eBgH * 0.5, enhText, nil)
    end

    -- 锁定标识（右上角）
    if item.locked and Renderer.lockClosedImg > 0 then
        local lockSz = math.max(10, slotSize * 0.32)
        local lx = sx + slotSize - lockSz - 1
        local ly = sy + 1
        local paint = nvgImagePattern(vg, lx, ly, lockSz, lockSz, 0, Renderer.lockClosedImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, lx, ly, lockSz, lockSz)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- 书籍已读标记（左上角绿色√，圆角矩形底板）
    if item.templateId and GS.elfvahBooksRead and GS.elfvahBooksRead[item.templateId] then
        local checkSz = math.max(8, slotSize * 0.30)   -- 底板尺寸
        local checkX = sx + 1
        local checkY = sy + 1
        local checkR = math.max(1.5, slotSize * 0.06)  -- 圆角半径
        -- 圆角矩形底板
        nvgBeginPath(vg)
        nvgRoundedRect(vg, checkX, checkY, checkSz, checkSz, checkR)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 170))
        nvgFill(vg)
        -- 绿色 √
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(7, checkSz * 0.75))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(80, 220, 80, 255))
        nvgText(vg, checkX + checkSz * 0.5, checkY + checkSz * 0.5, "✓", nil)
    end

    -- 收藏标识（左下角）
    if item.starred then
        local starR = math.max(4, slotSize * 0.15)
        local stcx = sx + 1 + starR
        local stcy = sy + slotSize - 1 - starR
        Renderer.drawStarPath(vg, stcx, stcy, starR, "slot", true)
    end
end

-- ====================================================================
-- 注册
-- ====================================================================

--- 注册覆盖层图片
---@param overlayType string
---@param id string
---@param handle integer NanoVG 图片句柄
function M.register(overlayType, id, handle)
    if not M.registry[overlayType] then
        M.registry[overlayType] = {}
    end
    M.registry[overlayType][id] = handle
end

--- 批量注册
---@param overlayType string
---@param entries table { [id] = handle, ... }
function M.registerBatch(overlayType, entries)
    for id, handle in pairs(entries) do
        M.register(overlayType, id, handle)
    end
end

-- ====================================================================
-- 状态控制
-- ====================================================================

--- 显示覆盖层
---@param overlayType string
---@param id string
---@param title? string
---@return boolean success
function M.show(overlayType, id, title)
    local img = M.registry[overlayType] and M.registry[overlayType][id]
    if not img or img == -1 then
        return false
    end
    -- 切换场景时清理残留的视频播放器和状态机
    M.cleanupVideoState()
    M.active = true
    M.overlayType = overlayType
    M.overlayId = id
    M.imageHandle = img
    M.title = title
    M.subScene = nil  -- 清除子场景（工坊/公会/酒馆等），确保从顶层城镇开始
    M.subSceneBtnRects = {}

    -- 切换场景时清理所有建筑内面板状态（归还赠送槽/提交槽物品）
    GS.cancelGift()
    GS.cancelQuestSubmit()
    GS.repairMode = false
    GS.shopMode = false
    GS.enhanceMode = false
    GS.forgeMode = false
    GS.alchemyMode = false
    GS.homeAlchemyMode = false
    GS.homeCookingMode = false
    GS.homeSmithySelectMode = false
    GS.homeSmithySelectRects = nil
    GS.homeForgeMode = false
    GS.homeCraftMode = false
    GS.homeEnchantMode = false
    GS.enchantMode = false
    GS.enchantSlotItem = nil
    GS.enchantSlotSource = nil
    GS.enchantSlotSourceId = nil
    GS.enchantResult = nil
    GS.homeSocketMode = false
    GS.refineMode = false
    GS.craftMode = false
    GS.socketMode = false

    -- 进入场景时清除棋盘所有单位和战斗状态
    -- 肉搏任务未完成时切换地图 → 中断任务（避免清空怪物后误判胜利）
    if GS.tavernBrawlState and not GS.tavernBrawlState.done then
        print("[酒馆肉搏] 战斗中切换地图，任务中断")
        GS.tavernBrawlState = nil
        GS.brawlCinematic = nil
    end
    GS.lastPlayerTarget = nil
    GS.monsters = {}
    GS.companions = {}
    GS.fireCorpses = {}
    GS.playerDebuffs = {}
    GS.autoMode = false
    GS.showAutoBattleSettings = false
    GS.selectedUnit = nil
    GS.movableCells = {}
    GS.attackableCells = {}
    GS.flushPendingMpRestores()
    GS.damageTexts = {}
    GS.attackEffects = {}
    GS.strikeEffects = {}
    GS.whirlwindEffects = {}
    GS.stealthSmokeEffect = nil
    GS.pendingEndPlayerTurn = false
    GS._pendingEndTurnTimer = nil
    GS.screenShake = nil
    GS.tombstoneAnim = nil
    GS.tombstoneDropAnim = nil
    GS.stormBuffTurns = 0
    GS.closeActionMenu()
    GS.regenTimer = 0

    -- 重置背景渐变状态（避免从家等非覆盖层场景返回时触发虚假的昼夜过渡动画）
    M._bgFadeSceneKey = nil
    M._bgFadeOldImg = nil
    M._bgFadePrevImg = nil
    M._bgFadeProgress = 1.0

    -- 重置玩家行动状态
    if GS.player then
        GS.player.acted = false
    end

    return true
end

--- 隐藏覆盖层
function M.hide()
    -- 隐藏覆盖层时清理残留的视频播放器和状态机
    M.cleanupVideoState()
    M.active = false
    M.dialogueBoxRect = nil  -- 防止残留值影响下次进入建筑
    -- 强制关闭残留对话，防止 DM.active 泄漏到下次 enterSubScene
    do
        local DM = require("DialogueManager")
        if DM.active then
            DM._dynamicOnComplete = nil
            DM.active = false
            DM.waitingForChoice = false
            DM.choiceResult = nil
            DM.currentId = nil
            DM.currentLines = nil
            DM.lineIndex = 0
        end
    end
    M.overlayType = nil
    M.overlayId = nil
    M.imageHandle = nil
    M.title = nil
    M.subScene = nil
    GS.exitShopMode()
    GS.confessConfirmPopup = nil
    -- 重置强化模式
    GS.enhanceMode = false
    GS.enhanceResult = nil
    GS.enhanceSlotItem = nil
    GS.enhanceSlotSource = nil
    GS.enhanceSlotSourceId = nil
    GS.enhanceDropRect = nil
    GS.enhanceBtnRect = nil
    GS.enhanceUseCatalyst = false
    GS.enhanceCatalystCheckRect = nil
    GS.refineBtnRect = nil
    -- 重置锻造模式
    GS.forgeMode = false
    GS.homeForgeMode = false
    GS.forgeResult = nil
    GS.forgeScrollY = 0
    GS.forgeBtnRects = {}
    -- 重置铁匠台选择弹窗
    GS.homeSmithySelectMode = false
    GS.homeSmithySelectRects = nil
    GS.homeCraftMode = false
    GS.homeEnchantMode = false
    GS.enchantMode = false
    GS.enchantSlotItem = nil
    GS.enchantSlotSource = nil
    GS.enchantSlotSourceId = nil
    GS.enchantResult = nil
    GS.homeSocketMode = false
    -- 重置烹饪模式
    GS.cookingMode = false
    GS.homeCookingMode = false
    GS.cookingResult = nil
    -- 重置炼金模式
    GS.alchemyMode = false
    GS.homeAlchemyMode = false
    GS.alchemyResult = nil
    GS.alchemyScrollY = 0
    GS.alchemyBtnRects = {}
    -- 重置镶嵌模式
    GS.socketMode = false
    GS.socketResult = nil
    GS.socketScrollY = 0
    GS.socketEquipItem = nil
    GS.socketEquipSource = nil
    GS.socketEquipSourceId = nil
    GS.socketSelectedGemSlot = nil
    GS.socketSelectedGemBag = nil
    GS.socketGemBtnRects = {}
    GS.socketDrillBtnRect = nil
    GS.refineDrillBtnRect = nil
    -- 重置委托加工模式
    GS.craftMode = false
    GS.craftSlotItem = nil
    GS.craftSlotSource = nil
    GS.craftSlotSourceId = nil
    GS.craftEnhanceResult = nil
    GS.craftRefineResult = nil
    GS.craftRepairResult = nil
    GS.craftTabRects = {}
    GS.craftRefineSlotBtnRects = {}
    GS.craftRefineDrillBtnRect = nil
    -- 重置赠送/提交模式（归还槽中物品）
    GS.cancelGift()
    GS.cancelQuestSubmit()
    GS.repairMode = false
    -- 重置深渊兑换模式
    if GS.exitAbyssExchangeMode then GS.exitAbyssExchangeMode() end
    -- 重置兑换模式
    if GS.exitExchangeMode then GS.exitExchangeMode() end
end

--- 检查是否有覆盖层激活
---@return boolean
function M.isActive()
    return M.active
end

--- 清理所有视频播放器和状态机（切换场景/隐藏覆盖层时调用）
function M.cleanupVideoState()
    if M._guildVideoPlayer then
        M._guildVideoPlayer:Stop()
    end
    if M._guildVideoPrevPlayer then
        M._guildVideoPrevPlayer:Stop()
    end
    M._guildVideoPlayer = nil
    M._guildVideoPrevPlayer = nil
    M._guildVideoNvgHandle = nil
    M._guildVideoPrevNvgHandle = nil
    M._guildVideoReady = false
    M._guildVideoPhase = nil
    M._guildVideoPendingLoad = nil
    M._guildVideoPendingVol = nil
    M._guildVideoPendingLoop = nil
    M._guildVideoLoadDelay = nil
    M._dancerPendingReveal = nil
    M._dancerTransitionPending = nil
    M._dancerDialogueDone = nil
    M._dancerAfterRevealCb = nil
    M._forestElfLeaveCb = nil
    M._forestElfVideoEnded = nil
    M._forestElfDialogueDone = nil
    M.tavernDanceView = false
    -- 重置淡入淡出状态
    M._fadeAlpha = nil
    M._fadeTarget = nil
    M._fadeDoneCallback = nil
    M._fadeSpeed = nil
end

-- ====================================================================
-- 羊皮纸面板公共绘制（底板 + 标题 + 关闭按钮 + 分隔线）
-- ====================================================================
--- 绘制羊皮纸底板框架，返回布局信息
---@param vg userdata NanoVG上下文
---@param bx number 棋盘X
---@param by number 棋盘Y
---@param boardSize number 棋盘尺寸
---@param title string 面板标题
---@return table { panelX, panelY, panelW, panelH, titleH, contentY, contentH, innerPad, closeRect }
local function drawParchmentPanel(vg, bx, by, boardSize, title, opts)
    local panelPad = boardSize * 0.04
    local panelX = bx + panelPad
    local panelY = by + panelPad
    local panelW = boardSize - panelPad * 2
    local panelH = (opts and opts.height) or (boardSize - panelPad * 2)
    local panelR = 6

    -- 底板填充（支持 opts.bgColor 自定义底色）
    local bgColor = (opts and opts.bgColor) or {215, 190, 140, 240}
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgFillColor(vg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 240))
    nvgFill(vg)

    -- 上下边缘渐变
    local isDark = (opts and opts.bgColor) and (bgColor[1] < 100)
    local edgeR, edgeG, edgeB = 180, 155, 105
    if isDark then edgeR, edgeG, edgeB = 30, 30, 30 end
    local edgeGrad = nvgLinearGradient(vg, panelX, panelY, panelX, panelY + panelH * 0.08,
        nvgRGBA(edgeR, edgeG, edgeB, 80), nvgRGBA(edgeR, edgeG, edgeB, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH * 0.08, panelR)
    nvgFillPaint(vg, edgeGrad)
    nvgFill(vg)
    local edgeGradB = nvgLinearGradient(vg, panelX, panelY + panelH * 0.92, panelX, panelY + panelH,
        nvgRGBA(edgeR, edgeG, edgeB, 0), nvgRGBA(edgeR, edgeG, edgeB, 80))
    nvgBeginPath(vg)
    nvgRect(vg, panelX, panelY + panelH * 0.92, panelW, panelH * 0.08)
    nvgFillPaint(vg, edgeGradB)
    nvgFill(vg)

    -- 描边边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX + 0.5, panelY + 0.5, panelW - 1, panelH - 1, panelR)
    if isDark then
        nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    else
        nvgStrokeColor(vg, nvgRGBA(30, 20, 10, 230))
    end
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    local titleH = math.max(26, panelH * 0.09)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(13, titleH * 0.6))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if isDark then
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    else
        nvgFillColor(vg, nvgRGBA(60, 45, 30, 255))
    end
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, title, nil)

    -- 关闭按钮（左上角 X）
    local closeBtnSize = math.max(18, titleH * 0.7)
    local closeBtnX = panelX + 6
    local closeBtnY = panelY + (titleH - closeBtnSize) / 2
    local closeCx = closeBtnX + closeBtnSize / 2
    local closeCy = closeBtnY + closeBtnSize / 2
    local crossR = closeBtnSize * 0.28

    nvgBeginPath(vg)
    nvgCircle(vg, closeCx, closeCy, closeBtnSize / 2)
    if isDark then
        nvgFillColor(vg, nvgRGBA(80, 80, 80, 150))
    else
        nvgFillColor(vg, nvgRGBA(160, 130, 90, 120))
    end
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, closeCx - crossR, closeCy - crossR)
    nvgLineTo(vg, closeCx + crossR, closeCy + crossR)
    nvgMoveTo(vg, closeCx + crossR, closeCy - crossR)
    nvgLineTo(vg, closeCx - crossR, closeCy + crossR)
    nvgStrokeColor(vg, nvgRGBA(200, 50, 40, 230))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    local closeRect = { x = closeBtnX, y = closeBtnY, w = closeBtnSize, h = closeBtnSize }

    -- 标题分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, panelY + titleH)
    nvgLineTo(vg, panelX + panelW - 12, panelY + titleH)
    if isDark then
        nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 150))
    else
        nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 150))
    end
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local innerPad = math.max(6, panelW * 0.025)
    local contentY = panelY + titleH + 6
    local contentH = panelH - titleH - 6 - innerPad

    return {
        panelX = panelX, panelY = panelY, panelW = panelW, panelH = panelH,
        titleH = titleH, contentY = contentY, contentH = contentH,
        innerPad = innerPad, closeRect = closeRect, isDark = isDark,
    }
end

-- ====================================================================
-- 布告栏：在建筑背景图上直接绘制当前委托卡片 + 左右箭头
-- ====================================================================
function M.drawBulletinQuestOnBoard(vg, bx, by, boardSize)
    local quests = BulletinBoard.quests
    if not quests or #quests == 0 then return end

    local idx = GS.bulletinQuestIndex or 1
    if idx < 1 then idx = 1 end
    if idx > #quests then idx = #quests end
    GS.bulletinQuestIndex = idx

    local quest = quests[idx]
    if not quest then return end

    -- ---- 卡片区域（居中偏上，留出底部按钮空间）----
    -- 宽度减少1/4: 0.72*0.75=0.54, 高度增加1/5: 0.52*1.2=0.624
    local cardW = boardSize * 0.54
    local cardH = boardSize * 0.624
    local cardX = bx + (boardSize - cardW) / 2
    local cardY = by + boardSize * 0.18

    -- 卡片底板（羊皮纸图片）
    local ImageManager = require("ImageManager")
    local parchImg = ImageManager.lazyGet("parchment_board", "image/parchment_board.png")
    if parchImg and parchImg ~= -1 then
        local paint = nvgImagePattern(vg, cardX, cardY, cardW, cardH, 0, parchImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, cardX, cardY, cardW, cardH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- 图片未加载时的降级：纯色底板
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 6)
        nvgFillColor(vg, nvgRGBA(225, 200, 155, 235))
        nvgFill(vg)
    end

    -- ---- 页码指示 (1/5) ----
    local pageText = idx .. " / " .. #quests
    local pageFontSize = math.max(10, boardSize * 0.032)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, pageFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(140, 110, 70, 180))
    nvgText(vg, cardX + cardW / 2, cardY + 5, pageText, nil)

    -- ---- 类型标签 ----
    local typeLabel = BulletinBoard.getQuestTypeLabel(quest)
    local tagFontSize = math.max(10, boardSize * 0.035)
    local tagW = math.max(60, cardW * 0.28)
    local tagH = math.max(18, cardH * 0.08)
    local tagX = cardX + (cardW - tagW) / 2
    local tagY = cardY + 5 + pageFontSize + 6

    nvgFontSize(vg, math.max(9, tagH * 0.65))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(30, 20, 10, 240))
    nvgText(vg, tagX + tagW / 2, tagY + tagH / 2, typeLabel, nil)

    -- ---- 第二行：动作 + 图标 + 名称 ----
    local line2Y = tagY + tagH + math.max(6, cardH * 0.03)
    local descFontSize = math.max(10, boardSize * 0.034)
    local iconSize = math.max(16, descFontSize * 1.5)
    local iconPad = 2  -- 图标内边距（图片离边框的距离）
    local cardPadX = math.max(8, cardW * 0.08)  -- 卡片内左右边距
    local contentW = cardW - cardPadX * 2  -- 可用内容宽度

    local iconCategory, iconPath = BulletinBoard.getQuestIconInfo(quest)

    -- 计算动作前缀文本
    local actionText = ""
    local nameText = ""
    local levelText = ""
    local qtype = quest.type
    if qtype == BulletinBoard.QUEST_TYPES.RARE_KILL or qtype == BulletinBoard.QUEST_TYPES.NORMAL_KILL then
        actionText = "击杀 "
        nameText = quest.targetName
        levelText = " (Lv." .. quest.targetLevel .. ")"
    elseif qtype == BulletinBoard.QUEST_TYPES.DROP_SUBMIT then
        actionText = "提交 "
        nameText = quest.targetName
    elseif qtype == BulletinBoard.QUEST_TYPES.PLANT_GATHER or qtype == BulletinBoard.QUEST_TYPES.MINE_GATHER then
        actionText = "提交 "
        nameText = quest.targetName
    end

    -- 绘制第二行：动作文本 + 图标 + 名称 + 等级（居中排列）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, descFontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 测量各部分宽度
    local actionW = nvgTextBounds(vg, 0, 0, actionText, nil)
    local nameW = nvgTextBounds(vg, 0, 0, nameText, nil)
    local levelW = #levelText > 0 and nvgTextBounds(vg, 0, 0, levelText, nil) or 0
    local iconGap = 3  -- 图标与文字的间距
    local totalW = actionW + iconSize + iconGap + nameW + levelW

    -- 如果总宽度超过可用宽度，缩小字体
    if totalW > contentW then
        descFontSize = math.max(8, descFontSize * contentW / totalW * 0.95)
        nvgFontSize(vg, descFontSize)
        iconSize = math.max(14, descFontSize * 1.5)
        actionW = nvgTextBounds(vg, 0, 0, actionText, nil)
        nameW = nvgTextBounds(vg, 0, 0, nameText, nil)
        levelW = #levelText > 0 and nvgTextBounds(vg, 0, 0, levelText, nil) or 0
        totalW = actionW + iconSize + iconGap + nameW + levelW
    end

    local line2MidY = line2Y + iconSize / 2
    local startX = cardX + (cardW - totalW) / 2

    -- 动作文本
    nvgFillColor(vg, nvgRGBA(50, 35, 15, 240))
    nvgText(vg, startX, line2MidY, actionText, nil)

    -- 图标（带黑色边框）
    local iconX = startX + actionW
    local iconY = line2Y
    if iconCategory and iconPath then
        local imgHandle = ImageManager.lazyGet(iconCategory, iconPath)
        if imgHandle and imgHandle ~= -1 then
            -- 黑色边框背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 3)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
            nvgFill(vg)
            -- 图标图片
            local imgPat = nvgImagePattern(vg, iconX + iconPad, iconY + iconPad,
                iconSize - iconPad * 2, iconSize - iconPad * 2, 0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX + iconPad, iconY + iconPad,
                iconSize - iconPad * 2, iconSize - iconPad * 2, 2)
            nvgFillPaint(vg, imgPat)
            nvgFill(vg)
            -- 黑色边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 3)
            nvgStrokeColor(vg, nvgRGBA(30, 20, 10, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end

    -- 名称文本
    local afterIconX = iconX + iconSize + iconGap
    nvgFillColor(vg, nvgRGBA(50, 35, 15, 240))
    nvgText(vg, afterIconX, line2MidY, nameText, nil)

    -- 等级文本
    if #levelText > 0 then
        nvgFillColor(vg, nvgRGBA(100, 75, 40, 200))
        nvgText(vg, afterIconX + nameW, line2MidY, levelText, nil)
    end

    -- ---- 第三行：目标数量（黑色文本） ----
    local line3Y = line2Y + iconSize + math.max(4, cardH * 0.02)
    local reqFontSize = math.max(10, boardSize * 0.034)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, reqFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(30, 20, 10, 230))
    local reqText = "目标: " .. quest.required
    nvgText(vg, cardX + cardW / 2, line3Y, reqText, nil)

    -- ---- 第四行：提示文本（深灰色） ----
    local line4Y = line3Y + reqFontSize + math.max(3, cardH * 0.015)
    local hintFontSize = math.max(9, boardSize * 0.028)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, hintFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 85, 65, 180))
    local hintText = BulletinBoard.getLocationHint(quest)
    -- 计算提示文本实际高度（用于后续奖励居中）
    local hintBottomY = line4Y
    if #hintText > 0 then
        nvgTextBox(vg, cardX + cardPadX, line4Y, contentW, hintText, nil)
        -- 估算 textBox 行数来得到底部 Y
        local hintCharPerLine = math.max(1, math.floor(contentW / hintFontSize))
        local hintLen = utf8.len(hintText) or #hintText
        local hintLines = math.ceil(hintLen / hintCharPerLine)
        hintBottomY = line4Y + hintLines * (hintFontSize * 1.2)
    end

    -- ---- 操作按钮（居中，卡片中下部）----
    local btnW = math.max(60, cardW * 0.60)
    local btnH2 = math.max(22, cardH * 0.08)
    local btnX = cardX + (cardW - btnW) / 2
    local btnY = cardY + cardH - btnH2 - math.max(8, cardH * 0.14)

    -- ---- 奖励（提示文本和按钮之间居中，加大字体+黑色描边）----
    -- 两行布局：「委托奖励：XXX金币」/「XXX经验值」，首位数字左对齐
    local rewardFontSize = math.max(12, boardSize * 0.038)
    local rewardCenterY = (hintBottomY + btnY) / 2
    local rewardMaxW = cardW - cardPadX * 2

    local prefixStr  = "委托奖励："
    local goldStr    = tostring(quest.reward) .. "金币"
    local expStr     = tostring(quest.expReward or 0) .. "经验值"

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, rewardFontSize)

    -- 测量各部分宽度
    local prefixW = nvgTextBounds(vg, 0, 0, prefixStr, nil)
    local goldW   = nvgTextBounds(vg, 0, 0, goldStr, nil)
    local expW    = nvgTextBounds(vg, 0, 0, expStr, nil)

    -- 整体块宽 = 前缀 + 两行数值部分的较宽者
    local numColW = math.max(goldW, expW)
    local blockW  = prefixW + numColW

    -- 如果超出可用宽度，等比缩小字体
    if blockW > rewardMaxW then
        rewardFontSize = math.max(9, math.floor(rewardFontSize * rewardMaxW / blockW))
        nvgFontSize(vg, rewardFontSize)
        prefixW = nvgTextBounds(vg, 0, 0, prefixStr, nil)
        goldW   = nvgTextBounds(vg, 0, 0, goldStr, nil)
        expW    = nvgTextBounds(vg, 0, 0, expStr, nil)
        numColW = math.max(goldW, expW)
        blockW  = prefixW + numColW
    end

    -- 水平居中：数字列左边缘对齐
    local blockStartX = cardX + (cardW - blockW) / 2
    local numStartX   = blockStartX + prefixW
    local lineGap     = rewardFontSize * 1.35
    local rwLine1Y    = rewardCenterY - lineGap / 2
    local rwLine2Y    = rewardCenterY + lineGap / 2

    -- 描边绘制辅助函数（左对齐版）
    local function drawStrokedTextL(x, y, txt)
        nvgFontSize(vg, rewardFontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local sOff = math.max(1, rewardFontSize * 0.06)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        nvgText(vg, x - sOff, y, txt, nil)
        nvgText(vg, x + sOff, y, txt, nil)
        nvgText(vg, x, y - sOff, txt, nil)
        nvgText(vg, x, y + sOff, txt, nil)
        nvgFillColor(vg, nvgRGBA(200, 160, 30, 255))
        nvgText(vg, x, y, txt, nil)
    end

    -- 第一行：「委托奖励：」+「XXX金币」
    drawStrokedTextL(blockStartX, rwLine1Y, prefixStr)
    drawStrokedTextL(numStartX, rwLine1Y, goldStr)
    -- 第二行：数字对齐位置绘制「XXX经验值」
    drawStrokedTextL(numStartX, rwLine2Y, expStr)

    GS.bulletinQuestBtnRect = nil

    GS.bulletinQuestRerollBtnRect = nil

    if not quest.accepted then
        -- 未接取：左侧"换一个"按钮 + 右侧"接取"按钮
        local gap = math.max(4, btnW * 0.06)
        local halfW = math.floor((btnW - gap) / 2)
        local rerollX = btnX
        local acceptX = btnX + halfW + gap
        local rerollW = halfW
        local acceptW = btnW - halfW - gap

        -- 换一个按钮（橙色，左侧）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rerollX, btnY, rerollW, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(200, 130, 30, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(160, 100, 20, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- "换一个"主文本
        local rerollFontSize = math.max(9, btnH2 * 0.45)
        nvgFontSize(vg, rerollFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 245))
        nvgText(vg, rerollX + rerollW / 2, btnY + btnH2 * 0.38, "换一个", nil)
        -- "（看广告）"小字
        local subFontSize = math.max(7, btnH2 * 0.28)
        nvgFontSize(vg, subFontSize)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, 200))
        nvgText(vg, rerollX + rerollW / 2, btnY + btnH2 * 0.72, "（看广告）", nil)
        GS.bulletinQuestRerollBtnRect = { x = rerollX, y = btnY, w = rerollW, h = btnH2 }

        -- 接取按钮（绿色，右侧）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, acceptX, btnY, acceptW, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(50, 160, 50, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(30, 120, 30, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, math.max(10, btnH2 * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 245))
        nvgText(vg, acceptX + acceptW / 2, btnY + btnH2 / 2, "接取", nil)
        GS.bulletinQuestBtnRect = { x = acceptX, y = btnY, w = acceptW, h = btnH2, action = "accept" }
    elseif quest.rewarded then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 100))
        nvgFill(vg)
        nvgFontSize(vg, math.max(10, btnH2 * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 100, 100, 180))
        nvgText(vg, btnX + btnW / 2, btnY + btnH2 / 2, "已完成", nil)
    elseif quest.ready and not quest.completed then
        -- 目标达成，待提交
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(200, 160, 40, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(160, 120, 20, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, math.max(10, btnH2 * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, btnX + btnW / 2, btnY + btnH2 / 2, "提交任务", nil)
        GS.bulletinQuestBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH2, action = "submitComplete" }
    elseif quest.completed then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(50, 160, 50, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(30, 120, 30, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, math.max(10, btnH2 * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, btnX + btnW / 2, btnY + btnH2 / 2, "领取奖励", nil)
        GS.bulletinQuestBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH2, action = "claim" }
    elseif quest.type == BulletinBoard.QUEST_TYPES.DROP_SUBMIT
        or quest.type == BulletinBoard.QUEST_TYPES.PLANT_GATHER
        or quest.type == BulletinBoard.QUEST_TYPES.MINE_GATHER then
        local held = BulletinBoard.getHeldCount(quest)
        local canSubmit = held > 0
        -- 左侧"换一个"按钮 + 右侧提交按钮
        local gap2 = math.max(4, btnW * 0.06)
        local rerollW2 = math.floor((btnW - gap2) * 0.4)
        local actionW2 = btnW - rerollW2 - gap2
        local rerollX2 = btnX
        local actionX2 = btnX + rerollW2 + gap2
        -- 换一个按钮（橙色，左侧）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rerollX2, btnY, rerollW2, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(200, 130, 30, 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(160, 100, 20, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, math.max(9, btnH2 * 0.45))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 245))
        nvgText(vg, rerollX2 + rerollW2 / 2, btnY + btnH2 * 0.38, "换一个", nil)
        nvgFontSize(vg, math.max(7, btnH2 * 0.28))
        nvgFillColor(vg, nvgRGBA(255, 255, 200, 200))
        nvgText(vg, rerollX2 + rerollW2 / 2, btnY + btnH2 * 0.72, "（看广告）", nil)
        GS.bulletinQuestRerollBtnRect = { x = rerollX2, y = btnY, w = rerollW2, h = btnH2 }
        -- 提交按钮（右侧）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, actionX2, btnY, actionW2, btnH2, 4)
        nvgFillColor(vg, canSubmit and nvgRGBA(180, 140, 40, 220) or nvgRGBA(160, 150, 130, 120))
        nvgFill(vg)
        if canSubmit then
            nvgStrokeColor(vg, nvgRGBA(140, 100, 20, 255))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
        nvgFontSize(vg, math.max(10, btnH2 * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, canSubmit and nvgRGBA(255, 255, 255, 240) or nvgRGBA(120, 110, 100, 160))
        nvgText(vg, actionX2 + actionW2 / 2, btnY + btnH2 / 2,
            canSubmit and ("提交(" .. held .. ")") or "提交(0)", nil)
        if canSubmit then
            GS.bulletinQuestBtnRect = { x = actionX2, y = btnY, w = actionW2, h = btnH2, action = "submit" }
        end
    else
        -- 击杀类已接取进行中：左侧"换一个"按钮 + 右侧"进行中"
        local gap3 = math.max(4, btnW * 0.06)
        local rerollW3 = math.floor((btnW - gap3) * 0.4)
        local actionW3 = btnW - rerollW3 - gap3
        local rerollX3 = btnX
        local actionX3 = btnX + rerollW3 + gap3
        -- 换一个按钮（橙色，左侧）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rerollX3, btnY, rerollW3, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(200, 130, 30, 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(160, 100, 20, 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, math.max(9, btnH2 * 0.45))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 245))
        nvgText(vg, rerollX3 + rerollW3 / 2, btnY + btnH2 * 0.38, "换一个", nil)
        nvgFontSize(vg, math.max(7, btnH2 * 0.28))
        nvgFillColor(vg, nvgRGBA(255, 255, 200, 200))
        nvgText(vg, rerollX3 + rerollW3 / 2, btnY + btnH2 * 0.72, "（看广告）", nil)
        GS.bulletinQuestRerollBtnRect = { x = rerollX3, y = btnY, w = rerollW3, h = btnH2 }
        -- 进行中（右侧）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, actionX3, btnY, actionW3, btnH2, 4)
        nvgFillColor(vg, nvgRGBA(160, 150, 130, 100))
        nvgFill(vg)
        nvgFontSize(vg, math.max(10, btnH2 * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
        nvgText(vg, actionX3 + actionW3 / 2, btnY + btnH2 / 2, "进行中...", nil)
    end

    -- ---- 已完成印章（盖在羊皮纸上） ----
    if quest.rewarded then
        local stampImg = ImageManager.lazyGet("stamp", "image/stamp_finished.png")
        if stampImg and stampImg ~= -1 then
            local stampSize = cardW * 0.55
            local stampCx = cardX + cardW / 2
            local stampCy = cardY + cardH * 0.48

            -- 动画状态
            local anim = M._stampAnim
            local scale = 1.0
            local alpha = 1.0
            if anim and anim.questIdx == idx and anim.progress < 1.0 then
                -- 从大缩小：3.0x -> 1.0x，使用 easeOutBack 缓动
                local t = anim.progress
                -- easeOutBack: 略微超过再回弹
                local c1 = 1.70158
                local c3 = c1 + 1
                local easedT = 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
                scale = 3.0 - 2.0 * easedT  -- 3.0 -> 1.0
                alpha = math.min(1.0, t * 2.0)  -- 快速淡入
            end

            local drawSize = stampSize * scale
            local drawX = stampCx - drawSize / 2
            local drawY = stampCy - drawSize / 2
            -- 印章原图是接近正方形(1536x2048)，这里保持正方形显示
            local stampDrawH = drawSize * (2048 / 1536)

            nvgSave(vg)
            nvgGlobalAlpha(vg, alpha * 0.92)
            -- 轻微旋转让印章更自然
            nvgTranslate(vg, stampCx, stampCy)
            nvgRotate(vg, math.rad(-8))
            nvgTranslate(vg, -stampCx, -stampCy)

            local paint = nvgImagePattern(vg,
                stampCx - drawSize / 2, stampCy - stampDrawH / 2,
                drawSize, stampDrawH, 0, stampImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, stampCx - drawSize / 2, stampCy - stampDrawH / 2, drawSize, stampDrawH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
            nvgRestore(vg)
        end
    end

    -- ---- 左右箭头 ----
    local arrowSize = math.max(24, boardSize * 0.07)
    local arrowY = cardY + cardH / 2 - arrowSize / 2
    local arrowPad = math.max(6, boardSize * 0.02)

    GS.bulletinArrowLeftRect = nil
    GS.bulletinArrowRightRect = nil

    -- 左箭头
    if idx > 1 then
        local ax = cardX - arrowSize - arrowPad
        local ay = arrowY
        -- 圆形背景
        local acx, acy = ax + arrowSize / 2, ay + arrowSize / 2
        nvgBeginPath(vg)
        nvgCircle(vg, acx, acy, arrowSize / 2)
        nvgFillColor(vg, nvgRGBA(60, 60, 60, 180))
        nvgFill(vg)
        -- 箭头 <
        local aw = arrowSize * 0.22
        local ah = arrowSize * 0.28
        nvgBeginPath(vg)
        nvgMoveTo(vg, acx + aw * 0.3, acy - ah)
        nvgLineTo(vg, acx - aw, acy)
        nvgLineTo(vg, acx + aw * 0.3, acy + ah)
        nvgStrokeColor(vg, nvgRGBA(230, 210, 160, 240))
        nvgStrokeWidth(vg, math.max(2, arrowSize * 0.08))
        nvgLineCap(vg, NVG_ROUND)
        nvgLineJoin(vg, NVG_ROUND)
        nvgStroke(vg)
        GS.bulletinArrowLeftRect = { x = ax, y = ay, w = arrowSize, h = arrowSize }
    end

    -- 右箭头
    if idx < #quests then
        local ax = cardX + cardW + arrowPad
        local ay = arrowY
        local acx, acy = ax + arrowSize / 2, ay + arrowSize / 2
        nvgBeginPath(vg)
        nvgCircle(vg, acx, acy, arrowSize / 2)
        nvgFillColor(vg, nvgRGBA(60, 60, 60, 180))
        nvgFill(vg)
        local aw = arrowSize * 0.22
        local ah = arrowSize * 0.28
        nvgBeginPath(vg)
        nvgMoveTo(vg, acx - aw * 0.3, acy - ah)
        nvgLineTo(vg, acx + aw, acy)
        nvgLineTo(vg, acx - aw * 0.3, acy + ah)
        nvgStrokeColor(vg, nvgRGBA(230, 210, 160, 240))
        nvgStrokeWidth(vg, math.max(2, arrowSize * 0.08))
        nvgLineCap(vg, NVG_ROUND)
        nvgLineJoin(vg, NVG_ROUND)
        nvgStroke(vg)
        GS.bulletinArrowRightRect = { x = ax, y = ay, w = arrowSize, h = arrowSize }
    end
end

-- ====================================================================
-- 附魔面板渲染（放入未附魔装备 + 消耗神炼附魔剂 → 随机词缀）
-- ====================================================================
function M.drawEnchantPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 深色底板（暖棕色调，与加工面板一致） ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 附魔 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.enchantCloseRect = p.closeRect

    -- ============ 装备放置槽 ============
    local slotSize = math.min(math.floor(panelW * 0.22), math.floor(contentH * 0.22))
    local slotY = contentY + 8
    local slotX = panelX + (panelW - slotSize) / 2
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    GS.enchantDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

    local item = GS.enchantSlotItem

    -- 外框描边（暖金色调，与加工面板一致）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(150, 130, 80, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    if item then
        -- 有物品：显示图标
        local tpl = GS.itemTemplates[item.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰
        drawItemDecorations(vg, item, slotX, slotY, slotSize)

        -- 名称（槽位下方居中）
        local nameFs = math.max(9, math.floor(slotSize * 0.2))
        local displayName = (item.name or ""):gsub(" %+%d+$", "")
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd2 = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc2 = rd2.color
        nvgFillColor(vg, nvgRGBA(rc2[1], rc2[2], rc2[3], 255))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize + 3, displayName, nil)
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "装备", nil)
    end

    -- ============ 分隔线 ============
    local nameAreaH = math.max(16, math.floor(slotSize * 0.25))
    local dividerY = slotY + slotSize + nameAreaH + 8
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + innerPad + 10, dividerY)
    nvgLineTo(vg, panelX + panelW - innerPad - 10, dividerY)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 下方详情区域 ============
    local detailAreaY = dividerY + 6
    local detailAreaH = (panelY + panelH - innerPad) - detailAreaY
    local detailAreaX = panelX + innerPad
    local detailAreaW = panelW - innerPad * 2

    if item then
        -- 神炼附魔剂数量
        local agentCount = GS.countInventoryItem("divine_enchant_agent")
        local lineH = math.max(12, detailAreaH * 0.08)
        local fs = math.max(10, lineH * 0.85)

        -- 检查装备是否已有附魔
        local hasEnchant = item.enchantment ~= nil
        -- 检查是否是装备（有slot属性）
        local isEquip = item.slot ~= nil

        local infoY = detailAreaY + 4

        -- 装备T级显示
        local tier = GS.getItemTier(item)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        nvgText(vg, detailAreaX + detailAreaW / 2, infoY, "需要以下消耗品：", nil)
        infoY = infoY + lineH + 2

        -- 附魔剂图标+数量
        local agentIconH = ImageManager.lazyGet("item", "image/item_divine_enchant.png")
        local iconSz = math.floor(lineH * 1.2)
        local agentLabelX = detailAreaX + detailAreaW / 2
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fs)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local agentText = "神炼附魔剂 × " .. agentCount
        local textW = nvgTextBounds(vg, 0, 0, agentText, nil)
        local totalW2 = iconSz + 4 + textW
        local startX2 = agentLabelX - totalW2 / 2

        -- 图标
        if agentIconH and agentIconH ~= -1 then
            local ip = nvgImagePattern(vg, startX2, infoY + lineH / 2 - iconSz / 2,
                iconSz, iconSz, 0, agentIconH, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, startX2, infoY + lineH / 2 - iconSz / 2, iconSz, iconSz, 2)
            nvgFillPaint(vg, ip)
            nvgFill(vg)
        end

        -- 数量文字
        if agentCount >= 1 then
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        else
            nvgFillColor(vg, nvgRGBA(200, 80, 80, 220))
        end
        nvgText(vg, startX2 + iconSz + 4, infoY + lineH / 2, agentText, nil)
        infoY = infoY + lineH + 6

        -- 已有附魔词缀显示
        if hasEnchant then
            local ench = item.enchantment
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
            nvgText(vg, detailAreaX + detailAreaW / 2, infoY,
                "当前词缀: " .. (ench.name or "") .. " +" .. (ench.value or 0) .. (ench.suffix or ""), nil)
            infoY = infoY + lineH + 4
        end

        -- 附魔按钮
        local btnW = math.max(80, detailAreaW * 0.5)
        local btnH = math.max(26, detailAreaH * 0.14)
        local btnX = detailAreaX + (detailAreaW - btnW) / 2
        local btnY2 = infoY + 4

        local canEnchant = isEquip and (agentCount >= 1)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY2, btnW, btnH, 4)
        if canEnchant then
            nvgFillColor(vg, nvgRGBA(60, 120, 40, 230))
        else
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
        end
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY2 + 0.5, btnW - 1, btnH - 1, 4)
        if canEnchant then
            nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 220))
        else
            nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 100))
        end
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(12, btnH * 0.5))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if canEnchant then
            nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 120, 120, 180))
        end
        nvgText(vg, btnX + btnW / 2, btnY2 + btnH / 2, hasEnchant and "重新附魔" or "附魔", nil)

        if canEnchant then
            GS.enchantBtnRect = { x = btnX, y = btnY2, w = btnW, h = btnH }
        else
            GS.enchantBtnRect = nil
        end

        -- 不可附魔的原因提示
        if not canEnchant then
            local reason = ""
            if not isEquip then
                reason = "该物品不是装备"
            elseif agentCount < 1 then
                reason = "需要神炼附魔剂"
            end
            if reason ~= "" then
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(9, fs * 0.85))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 80, 60, 200))
                nvgText(vg, detailAreaX + detailAreaW / 2, btnY2 + btnH + 4, reason, nil)
            end
        end
    else
        -- 未放入装备，显示提示
        GS.enchantBtnRect = nil
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.3,
            "从装备栏或背包拖入装备到上方格子", nil)
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.5,
            "消耗神炼附魔剂为装备附魔", nil)
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.7,
            "随机赋予对应T级的词缀", nil)
    end

    -- ============ 结果提示 ============
    if GS.enchantResult then
        local er = GS.enchantResult
        if er.timer and er.timer > 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(12, panelH * 0.04))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            if er.success then
                nvgFillColor(vg, nvgRGBA(100, 220, 140, 255))
            else
                nvgFillColor(vg, nvgRGBA(220, 80, 60, 255))
            end
            nvgText(vg, panelX + panelW / 2, panelY + panelH - innerPad - 2, er.msg or "", nil)
        end
    end
end

-- ====================================================================
-- 委托加工面板渲染（合并强化/精炼/修复为标签页）
-- ====================================================================
function M.drawCraftPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 羊皮纸底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 委托加工 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.craftCloseRect = p.closeRect

    -- ============ 标签栏 ============
    local tabH = math.max(22, contentH * 0.065)
    local tabs = {
        { label = "强化", tab = "enhance" },
        { label = "精炼", tab = "refine" },
        { label = "修复", tab = "repair" },
        { label = "萃取", tab = "extract" },
    }
    local tabW = (panelW - innerPad * 2) / #tabs
    local tabY = contentY

    GS.craftTabRects = {}
    for i, t in ipairs(tabs) do
        local tx = panelX + innerPad + (i - 1) * tabW
        local isActive = (GS.craftTab == t.tab)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx + 1, tabY + 1, tabW - 2, tabH - 2, 3)
        if isActive then
            nvgFillColor(vg, nvgRGBA(50, 40, 25, 240))
        else
            nvgFillColor(vg, nvgRGBA(80, 70, 55, 200))
        end
        nvgFill(vg)

        -- 标签边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx + 1, tabY + 1, tabW - 2, tabH - 2, 3)
        if isActive then
            nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
            nvgStrokeWidth(vg, 1.5)
        else
            nvgStrokeColor(vg, nvgRGBA(140, 120, 80, 180))
            nvgStrokeWidth(vg, 1)
        end
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(10, tabH * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
        else
            nvgFillColor(vg, nvgRGBA(220, 210, 190, 230))
        end
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, t.label, nil)

        GS.craftTabRects[i] = { x = tx, y = tabY, w = tabW, h = tabH, tab = t.tab }
    end

    -- 标签栏下方开始内容
    local slotContentY = tabY + tabH + 4

    -- ============ 上方：放置槽 ============
    local slotSize = math.min(math.floor(panelW * 0.22), math.floor(contentH * 0.22))
    local slotY = slotContentY + 8
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    local item  -- 当前标签页的主物品引用
    local slotX -- 主槽位X坐标（用于分隔线计算）

    if GS.craftTab == "extract" then
        -- ---- 萃取双槽模式 ----
        local dualSlotSize = math.min(math.floor(panelW * 0.20), math.floor(contentH * 0.20))
        local dualSlotR = math.max(3, math.floor(dualSlotSize * 0.08))
        local gap = math.max(24, math.floor(panelW * 0.14))
        local totalW = dualSlotSize * 2 + gap
        local startX = panelX + (panelW - totalW) / 2
        local srcSlotX = startX
        local tgtSlotX = startX + dualSlotSize + gap

        GS.extractSourceDropRect = { x = srcSlotX, y = slotY, w = dualSlotSize, h = dualSlotSize }
        GS.extractTargetDropRect = { x = tgtSlotX, y = slotY, w = dualSlotSize, h = dualSlotSize }
        GS.craftDropRect = nil  -- 禁用单槽

        -- 绘制双槽的辅助函数
        local function drawExtractSlot(sx, sy, sz, sr, slotItem, hintText)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx - 1, sy - 1, sz + 2, sz + 2, sr + 1)
            nvgStrokeColor(vg, nvgRGBA(150, 130, 80, 220))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
            local sg = nvgLinearGradient(vg, sx, sy, sx, sy + sz,
                nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, sz, sz, sr)
            nvgFillPaint(vg, sg)
            nvgFill(vg)
            local shH = math.max(2, math.floor(sz * 0.2))
            local ts = nvgLinearGradient(vg, sx, sy, sx, sy + shH,
                nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, sz, shH, sr)
            nvgFillPaint(vg, ts)
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + sr, sy + sz - 1)
            nvgLineTo(vg, sx + sz - sr, sy + sz - 1)
            nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            if slotItem then
                local tpl = GS.itemTemplates[slotItem.templateId]
                local imgH = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
                if imgH and imgH ~= -1 then
                    local pad = 3
                    local ip = nvgImagePattern(vg, sx + pad, sy + pad,
                        sz - pad * 2, sz - pad * 2, 0, imgH, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx + pad, sy + pad, sz - pad * 2, sz - pad * 2, sr)
                    nvgFillPaint(vg, ip)
                    nvgFill(vg)
                end
                if tpl then
                    local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
                    local rc = rd.border
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx + 1, sy + 1, sz - 2, sz - 2, sr)
                    nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end
                drawItemDecorations(vg, slotItem, sx, sy, sz)
                -- 名称
                local nFs = math.max(8, math.floor(sz * 0.18))
                local dn = (slotItem.name or ""):gsub(" %+%d+$", "")
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, nFs)
                local labelY2 = sy + sz + 2
                local tw = nvgTextBounds(vg, 0, 0, dn, nil)
                local fW = 4
                local bgW2 = tw + fW * 2
                local bgCX = sx + sz / 2
                local bgX2 = bgCX - bgW2 / 2
                local mX = bgX2 + fW
                local gL = nvgLinearGradient(vg, bgX2, labelY2, mX, labelY2,
                    nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 100))
                nvgBeginPath(vg)
                nvgRect(vg, bgX2, labelY2, fW, nFs + 2)
                nvgFillPaint(vg, gL)
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, mX, labelY2, tw, nFs + 2)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
                nvgFill(vg)
                local gR = nvgLinearGradient(vg, mX + tw, labelY2, mX + tw + fW, labelY2,
                    nvgRGBA(0, 0, 0, 100), nvgRGBA(0, 0, 0, 0))
                nvgBeginPath(vg)
                nvgRect(vg, mX + tw, labelY2, fW, nFs + 2)
                nvgFillPaint(vg, gR)
                nvgFill(vg)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
                local rc = rd.color
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
                nvgText(vg, bgCX, labelY2, dn, nil)
            else
                nvgFontFace(vg, "sans")
                local hFs = math.max(8, math.floor(sz * 0.16))
                nvgFontSize(vg, hFs)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
                nvgText(vg, sx + sz / 2, sy + sz / 2, hintText, nil)
            end
        end

        drawExtractSlot(srcSlotX, slotY, dualSlotSize, dualSlotR, GS.extractSourceItem, "源装备")
        -- 箭头 →
        local arrowX = srcSlotX + dualSlotSize + gap / 2
        local arrowY2 = slotY + dualSlotSize / 2
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(16, dualSlotSize * 0.35))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        nvgText(vg, arrowX, arrowY2, "→", nil)

        drawExtractSlot(tgtSlotX, slotY, dualSlotSize, dualSlotR, GS.extractTargetItem, "目标装备")

        slotX = startX
        slotSize = dualSlotSize
        item = nil  -- 萃取tab不使用单一item变量
    else
        -- ---- 单槽模式（强化/精炼/修复） ----
        slotX = panelX + (panelW - slotSize) / 2

        GS.craftDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

        item = GS.craftSlotItem

    -- 外框描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(150, 130, 80, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    -- 底部微光
    nvgBeginPath(vg)
    nvgMoveTo(vg, slotX + slotR, slotY + slotSize - 1)
    nvgLineTo(vg, slotX + slotSize - slotR, slotY + slotSize - 1)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if item then
        -- 有物品：显示图标
        local tpl = GS.itemTemplates[item.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰
        drawItemDecorations(vg, item, slotX, slotY, slotSize)

        -- 名称（槽位下方居中，带衬底底板）
        local nameFs = math.max(9, math.floor(slotSize * 0.2))
        local displayName = (item.name or ""):gsub(" %+%d+$", "")
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        -- 衬底底板（与装备栏风格一致）
        local labelY = slotY + slotSize + 3
        local bgH = nameFs + 2
        local bgTopY = labelY
        local textW = nvgTextBounds(vg, 0, 0, displayName, nil)
        local fadeW = 6
        local bgW = textW + fadeW * 2
        local bgCenterX = slotX + slotSize / 2
        local bgX = bgCenterX - bgW / 2
        local midX = bgX + fadeW
        -- 左渐变
        local gradL = nvgLinearGradient(vg, bgX, labelY, midX, labelY,
            nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 100))
        nvgBeginPath(vg)
        nvgRect(vg, bgX, bgTopY, fadeW, bgH)
        nvgFillPaint(vg, gradL)
        nvgFill(vg)
        -- 中间实色
        nvgBeginPath(vg)
        nvgRect(vg, midX, bgTopY, textW, bgH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
        nvgFill(vg)
        -- 右渐变
        local gradR = nvgLinearGradient(vg, midX + textW, labelY, midX + textW + fadeW, labelY,
            nvgRGBA(0, 0, 0, 100), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRect(vg, midX + textW, bgTopY, fadeW, bgH)
        nvgFillPaint(vg, gradR)
        nvgFill(vg)
        -- 名字文本
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, bgCenterX, labelY, displayName, nil)
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "装备", nil)
    end
    end  -- end if extract/else

    -- ============ 分隔线 ============
    local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
    local sepY = slotY + slotSize + nameAreaH
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, sepY)
    nvgLineTo(vg, panelX + panelW - 12, sepY)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 下方：标签页内容 ============
    local detailAreaX = panelX + innerPad
    local detailAreaY = sepY + 6
    local detailAreaW = panelW - innerPad * 2
    local detailAreaH = panelY + panelH - innerPad - detailAreaY

    -- ======== 强化标签页 ========
    if GS.craftTab == "enhance" then

        local effectNames = {
            atk = "物理攻击力", def = "物理防御力", hp = "生命值", mp = "魔法值",
            spd = "速度", crit = "暴击率",
            str = "力量", wis = "智慧", agi = "敏捷", con = "体质",
            foc = "专注", per = "感知", wil = "意念",
            hpRegen = "HP自然回复", hpDrain = "HP流失", critVal = "暴击值", dodge = "闪避值",
            hit = "命中值", maxMonsters = "怪物出现上限", spawnCount = "怪物出现数量",
            critDmg = "暴击伤害", lifesteal = "吸血",
            batFangLifesteal = "吸血",
            physLifesteal = "物理吸血", magLifesteal = "法术吸血",
            manaLeech = "魔力回收",
            moveRange = "移动距离", atkSpeed = "攻速",
            mAtk = "魔法攻击力", mDef = "魔法防御力",
            mpRegen = "MP自然回复",
            mCritVal = "魔法暴击值", mCritDmg = "魔法暴击伤害",
            luk = "幸运", cha = "魅力",
            fireDmgBonus = "火焰伤害", iceDmgBonus = "冰冻伤害",
            elecDmgBonus = "雷电伤害", lightDmgBonus = "神圣伤害",
            ragingFireBonus = "燃火",
            radianceDmgBonus = "辉光伤害", radianceNearDmgBonus = "辉光近处增伤", radianceStunChance = "辉光晕眩",
            rangedDefRate = "远程减伤", rangedDefCap = "远程减伤上限",
            cstarAgiL = "伴随星敏捷", cstarAtkSpdL = "伴随星攻速",
            cstarStrR = "伴随星力量", cstarWisR = "伴随星智慧",
            cstarCritDmgR = "伴随星物暴伤", cstarMCritDmgR = "伴随星法暴伤",
            swordDmgBonus = "剑类伤害", daggerDmgBonus = "匕首伤害",
            maceDmgBonus = "钉锤伤害", bowDmgBonus = "弓类伤害",
            staffDmgBonus = "法杖伤害", physDmgBonus = "物理伤害",
            magDmgBonus = "魔法伤害",
            eleFlowBonus = "元素流转增伤",
            arsenalScatter = "散射",
            healStoreRate = "治疗存储", healReleaseRate = "存储释放",
            furyStackPerCrit = "狂怒叠加", furyMaxStacks = "狂怒上限", furyDecayOnNonCrit = "狂怒衰减",
            distDmgPctPerGrid = "距离伤害",
            dodgeRateBonus1 = "闪避率额外提高", dodgeRateBonus2 = "闪避率额外提高",
        }
        local hiddenAttrs = { batFangCount = true }

        if item then
            local tpl = GS.itemTemplates[item.templateId]
            local maxLv = GS.getMaxEnhance(item)
            local enhLv = item.enhanceLevel or 0
            local cost = GS.getEnhanceCost(item)
            local gain = GS.getEnhanceGain(item, enhLv)
            local matId, matQty, matOwned = GS.getEnhanceMaterialInfo(item)
            local matName = ""
            if matId then
                local matTpl = GS.itemTemplates[matId]
                matName = matTpl and matTpl.name or matId
            end
            local successRate = GS.getEnhanceSuccessRate(item)
            local canAfford = GS.gold >= cost and (not matId or matOwned >= matQty)
            local isMaxed = enhLv >= maxLv

            -- 统一字体大小和行间距
            local lineH = math.max(14, detailAreaH * 0.09)
            local fs = math.max(9, lineH * 0.82)

            local leftW = detailAreaW * 0.55
            local rightW = detailAreaW - leftW - 6
            local rightX = detailAreaX + leftW + 6

            -- ---- 左半区 ----
            local curY = detailAreaY + 2

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
            nvgText(vg, detailAreaX, curY, "强化等级: ", nil)
            local lvTextX = detailAreaX + nvgTextBounds(vg, 0, 0, "强化等级: ", nil)
            local _, enhDispC = GS.getEnhanceRarity(enhLv)
            if isMaxed then
                nvgFillColor(vg, nvgRGBA(enhDispC[1], enhDispC[2], enhDispC[3], 255))
                nvgText(vg, lvTextX, curY, enhLv .. "/" .. maxLv .. " (满)", nil)
            else
                nvgFillColor(vg, nvgRGBA(enhDispC[1], enhDispC[2], enhDispC[3], 255))
                nvgText(vg, lvTextX, curY, enhLv .. "/" .. maxLv, nil)
            end
            curY = curY + lineH

            -- 当前属性（白色文本，不含括号强化信息）
            if item.effects then
                local hasBlock = item.effects.block_chance ~= nil
                for k, v in pairs(item.effects) do
                    if k ~= "block_chance" and k ~= "block_amount" then
                        local label = effectNames[k] or k
                        local enhBonus = 0
                        if enhLv > 0 and gain[k] then
                            enhBonus = gain[k]
                        end
                        local totalVal = v + enhBonus
                        nvgFontSize(vg, fs)
                        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                        nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
                        local sign = totalVal >= 0 and "+" or ""
                        nvgText(vg, detailAreaX, curY, label .. " " .. sign .. totalVal, nil)
                        curY = curY + lineH
                    end
                end
                if hasBlock then
                    local pct = math.floor(item.effects.block_chance * 100)
                    local baseBA = item.effects.block_amount or 1
                    local enhBonus = 0
                    if enhLv > 0 and gain.block_amount then
                        enhBonus = gain.block_amount
                    end
                    nvgFontSize(vg, fs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
                    nvgText(vg, detailAreaX, curY, pct .. "%概率格挡" .. (baseBA + enhBonus) .. "点物理伤害", nil)
                    curY = curY + lineH
                end
            end

            -- 强化成功后预览（显示总数值，绿色）
            if not isMaxed then
                curY = curY + 2
                local nextGain = GS.getEnhanceGain(item, enhLv + 1)
                for k, nv in pairs(nextGain) do
                    if k ~= "block_chance" and k ~= "block_amount" then
                        local label = effectNames[k] or k
                        local baseVal = item.effects and item.effects[k] or 0
                        local nextTotal = baseVal + nv
                        nvgFontSize(vg, fs)
                        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                        nvgFillColor(vg, nvgRGBA(80, 180, 60, 255))
                        local sign = nextTotal >= 0 and "+" or ""
                        nvgText(vg, detailAreaX, curY, "强化成功后: " .. label .. " " .. sign .. nextTotal, nil)
                        curY = curY + lineH
                    end
                end
                if nextGain.block_amount then
                    local baseBA = item.effects and item.effects.block_amount or 1
                    local nextTotal = baseBA + nextGain.block_amount
                    nvgFontSize(vg, fs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(80, 180, 60, 255))
                    nvgText(vg, detailAreaX, curY, "强化成功后: 格挡伤害 " .. nextTotal, nil)
                    curY = curY + lineH
                end
            end

            -- ---- 右半区：费用与强化按钮 ----
            if not isMaxed then
                local rY = detailAreaY + 2

                -- 费用拆分为燃料费和加工费
                local fuelCost, processingFee = GS.getEnhanceCostBreakdown(item)
                local goldEnough = GS.gold >= cost
                local costColor = nvgRGBA(180, 140, 40, 255)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, fs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, rightX, rY, "燃料费: ", nil)
                local fuelLabelW = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
                nvgFillColor(vg, costColor)
                nvgText(vg, rightX + fuelLabelW, rY, fuelCost .. " G", nil)
                rY = rY + lineH

                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, rightX, rY, "加工费: ", nil)
                local procLabelW = nvgTextBounds(vg, 0, 0, "加工费: ", nil)
                nvgFillColor(vg, costColor)
                nvgText(vg, rightX + procLabelW, rY, processingFee .. " G", nil)
                rY = rY + lineH

                -- 分隔线（加工费和总费用之间）
                rY = rY + 2
                nvgBeginPath(vg)
                nvgMoveTo(vg, rightX, rY)
                nvgLineTo(vg, rightX + rightW, rY)
                nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 100))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                rY = rY + 4

                -- 总费用
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, rightX, rY, "总费用: ", nil)
                local totalLabelW = nvgTextBounds(vg, 0, 0, "总费用: ", nil)
                nvgFillColor(vg, goldEnough and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, rightX + totalLabelW, rY, cost .. " G", nil)
                rY = rY + lineH

                -- 材料（标签 + 图标 + 名称 + 持有/消耗 同行）
                if matId then
                    nvgFontSize(vg, fs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                    nvgText(vg, rightX, rY, "材料: ", nil)
                    local matLabelW = nvgTextBounds(vg, 0, 0, "材料: ", nil)

                    -- 材料图标（黑色边框）
                    local matTpl = GS.itemTemplates[matId]
                    local matIconSize = math.max(12, math.floor(lineH * 0.9))
                    local matIconX = rightX + matLabelW
                    local matIconY = rY + (lineH - matIconSize) / 2
                    local matImgHandle = matTpl and matTpl.icon and ImageManager.lazyGet("item", matTpl.icon)
                    if matImgHandle and matImgHandle ~= -1 then
                        local matIconPat = nvgImagePattern(vg, matIconX, matIconY, matIconSize, matIconSize, 0, matImgHandle, 1.0)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, matIconX, matIconY, matIconSize, matIconSize, 2)
                        nvgFillPaint(vg, matIconPat)
                        nvgFill(vg)
                    end
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, matIconX, matIconY, matIconSize, matIconSize, 2)
                    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    -- 材料名称
                    local matTextX = matIconX + matIconSize + 3
                    nvgFontSize(vg, fs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
                    nvgText(vg, matTextX, rY, matName, nil)
                    local matNameW = nvgTextBounds(vg, 0, 0, matName, nil)

                    -- 持有/消耗 放在材料名字右边（同一行）
                    local matCountX = matTextX + matNameW + 4
                    if matOwned >= matQty then
                        nvgFillColor(vg, nvgRGBA(100, 180, 80, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(220, 80, 60, 255))
                    end
                    local ownedStr = tostring(matOwned)
                    nvgText(vg, matCountX, rY, ownedStr, nil)
                    local ownedStrW = nvgTextBounds(vg, 0, 0, ownedStr, nil)
                    nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
                    nvgText(vg, matCountX + ownedStrW, rY, "/" .. matQty, nil)
                    rY = rY + lineH + 4
                end

                -- ---- 底部并排：催化剂(左) | 成功率(中) | 强化按钮(右) ----
                local btnH = math.max(24, lineH * 1.6)
                local btnW = math.max(50, detailAreaW * 0.22)
                local btnBottomY = detailAreaY + detailAreaH - 4
                local btnY = btnBottomY - btnH
                local btnX = detailAreaX + detailAreaW - btnW
                local btnMidY = btnY + btnH / 2

                -- 催化剂勾选框（左侧，与按钮垂直居中）
                local catCount = GS.countInventoryItem("divine_catalyst")
                local cbSize = math.max(12, lineH * 0.8)
                local cbX = detailAreaX
                local cbY = btnMidY - cbSize / 2
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cbX, cbY, cbSize, cbSize, 2)
                if GS.enhanceUseCatalyst and catCount >= 1 then
                    nvgFillColor(vg, nvgRGBA(60, 140, 60, 230))
                else
                    nvgFillColor(vg, nvgRGBA(180, 170, 150, 100))
                end
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cbX + 0.5, cbY + 0.5, cbSize - 1, cbSize - 1, 2)
                nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                if GS.enhanceUseCatalyst and catCount >= 1 then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, cbSize * 0.9)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                    nvgText(vg, cbX + cbSize / 2, cbY + cbSize / 2, "✓", nil)
                end
                local catLabelX = cbX + cbSize + 4
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, fs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                if catCount >= 1 then
                    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                else
                    nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
                end
                local catLabel = "催化剂（剩余" .. catCount .. "个）"
                nvgText(vg, catLabelX, btnMidY, catLabel, nil)
                GS.enhanceCatalystCheckRect = { x = cbX, y = cbY, w = cbSize + 4 + nvgTextBounds(vg, 0, 0, catLabel, nil), h = cbSize }

                -- 成功率（催化剂和按钮之间，右对齐到按钮左边）
                local ratePct = math.floor(successRate * 100)
                local catBonusPct = 0
                if GS.enhanceUseCatalyst and catCount >= 1 then
                    catBonusPct = 5
                end
                local displayPct = math.min(100, ratePct + catBonusPct)
                local rateStr = "成功率: " .. displayPct .. "%"
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, fs)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                if displayPct >= 100 then
                    nvgFillColor(vg, nvgRGBA(100, 180, 80, 255))
                elseif displayPct >= 50 then
                    nvgFillColor(vg, nvgRGBA(200, 160, 30, 255))
                else
                    nvgFillColor(vg, nvgRGBA(200, 80, 30, 255))
                end
                nvgText(vg, btnX - 6, btnMidY, rateStr, nil)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
                if canAfford then
                    nvgFillColor(vg, nvgRGBA(60, 120, 40, 230))
                else
                    nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
                end
                nvgFill(vg)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 4)
                if canAfford then
                    nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 220))
                else
                    nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 100))
                end
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(12, btnH * 0.5))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if canAfford then
                    nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
                else
                    nvgFillColor(vg, nvgRGBA(180, 120, 120, 180))
                end
                nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "强化", nil)

                GS.craftEnhanceBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
            else
                GS.craftEnhanceBtnRect = nil
            end

            -- 不可强化的物品提示
            if maxLv <= 0 then
                GS.craftEnhanceBtnRect = nil
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(10, detailAreaH * 0.1))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(180, 60, 40, 200))
                nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH / 2,
                    "该装备无法强化", nil)
            end
        else
            -- 未放入装备，显示提示
            GS.craftEnhanceBtnRect = nil
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
                "从装备栏或背包拖入装备到上方格子", nil)
            nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.6,
                "即可进行强化", nil)
        end

    -- ======== 精炼标签页 ========
    elseif GS.craftTab == "refine" then

        local lineH = math.max(14, detailAreaH * 0.08)
        local titleFs = math.max(11, lineH * 0.9)
        local bodyFs = math.max(9, lineH * 0.78)

        GS.craftRefineSlotBtnRects = {}
        GS.craftRefineDrillBtnRect = nil

        if item then
            local refineSlots = item.refineSlots
            if refineSlots and #refineSlots > 0 then
                local curY = detailAreaY + 2

                local filledCount = 0
                for _, rslot in ipairs(refineSlots) do
                    if rslot.attr then filledCount = filledCount + 1 end
                end

                -- 标题行
                local craftItemTier = GS.getItemTier(item)
                local craftMaxRefSlots = GS.getMaxRefineSlots(craftItemTier)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
                local rtSlotTitle = "精炼槽" .. #refineSlots .. "/" .. craftMaxRefSlots
                nvgText(vg, detailAreaX, curY, rtSlotTitle, nil)

                -- 剩余韧性（紧跟标题行右侧）
                do
                    local rtItem = GS.craftSlotItem
                    if rtItem then
                        GS.ensureRefineToughness(rtItem)
                        local rtCur = rtItem.refineToughness or 0
                        local rtMax = GS.getMaxRefineToughness(rtItem)
                        local rtTitleW = nvgTextBounds(vg, 0, 0, rtSlotTitle, nil)
                        local rtGap = 8
                        local rtLbl = "剩余韧性:"
                        local rtLblW = nvgTextBounds(vg, 0, 0, rtLbl, nil)
                        local rtCurS = tostring(rtCur)
                        local rtDivS = "/" .. tostring(rtMax)
                        local rtCurW = nvgTextBounds(vg, 0, 0, rtCurS, nil)
                        local rtX = detailAreaX + rtTitleW + rtGap
                        nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
                        nvgText(vg, rtX, curY, rtLbl, nil)
                        if rtCur >= rtMax then
                            nvgFillColor(vg, nvgRGBA(80, 200, 80, 255))
                        else
                            nvgFillColor(vg, nvgRGBA(230, 80, 80, 255))
                        end
                        nvgText(vg, rtX + rtLblW, curY, rtCurS, nil)
                        nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
                        nvgText(vg, rtX + rtLblW + rtCurW, curY, rtDivS, nil)
                    end
                end

                -- 精炼石信息（标题行右侧：图标 + 稀有度颜色名称 + 持有/消耗）
                local refItem = GS.craftSlotItem
                -- 显示实际将消耗的精炼石（优先低阶），无库存时回退到所需阶数
                local actualTier = refItem and GS.findAvailableStoneTier(refItem)
                local stoneTier = actualTier or (refItem and GS.getRequiredStoneTier(refItem) or 2)
                local stoneId = "refine_stone_" .. stoneTier
                -- 显示当前预备消耗阶数的持有数量
                local stoneCount = refItem and GS.countInventoryItem(stoneId) or 0
                local stoneTpl = GS.itemTemplates[stoneId]
                local stoneName = stoneTpl and stoneTpl.name or (stoneTier .. "阶精炼石")
                local stoneRarity = stoneTpl and stoneTpl.rarity or "common"
                local stoneRc = GS.RARITY[stoneRarity] and GS.RARITY[stoneRarity].color or {200, 200, 200}

                -- 从右往左布局精炼石信息
                local stoneIconSize = math.max(12, math.floor(lineH * 0.85))
                local stoneIconY = curY + (lineH - stoneIconSize) / 2

                -- 先测量文本宽度以从右往左排列
                nvgFontSize(vg, bodyFs)
                local countStr = tostring(stoneCount)
                local slashStr = "/1"
                local countW = nvgTextBounds(vg, 0, 0, countStr, nil)
                local slashW = nvgTextBounds(vg, 0, 0, slashStr, nil)
                local nameW = nvgTextBounds(vg, 0, 0, stoneName, nil)

                local rightEdge = detailAreaX + detailAreaW
                -- 持有/消耗数量（最右）
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
                nvgText(vg, rightEdge, curY, slashStr, nil)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, stoneCount >= 1 and nvgRGBA(80, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, rightEdge - slashW, curY, countStr, nil)

                -- 精炼石名称（稀有度颜色）
                local nameX = rightEdge - slashW - countW - 4
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(stoneRc[1], stoneRc[2], stoneRc[3], 255))
                nvgText(vg, nameX, curY, stoneName, nil)

                -- 精炼石图标（名称左侧）
                local stoneIconX = nameX - nameW - stoneIconSize - 2
                local stoneImgHandle = stoneTpl and stoneTpl.icon and ImageManager.lazyGet("item", stoneTpl.icon)
                if stoneImgHandle and stoneImgHandle ~= -1 then
                    local stoneIconPat = nvgImagePattern(vg, stoneIconX, stoneIconY, stoneIconSize, stoneIconSize, 0, stoneImgHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, stoneIconX, stoneIconY, stoneIconSize, stoneIconSize, 2)
                    nvgFillPaint(vg, stoneIconPat)
                    nvgFill(vg)
                end
                nvgBeginPath(vg)
                nvgRoundedRect(vg, stoneIconX, stoneIconY, stoneIconSize, stoneIconSize, 2)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                curY = curY + lineH

                -- 燃料费(左) + 加工费(中) + 总费用(右)，数字金色
                local refineFuel, refineProc = GS.getRefineCostBreakdown(refItem)
                local refineTotal = refineFuel + refineProc
                local costColor = nvgRGBA(180, 140, 40, 255)
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, detailAreaX, curY, "燃料费: ", nil)
                local fuelLabelW = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
                nvgFillColor(vg, costColor)
                nvgText(vg, detailAreaX + fuelLabelW, curY, refineFuel .. " G", nil)

                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                local procLabel = "加工费: "
                local procLabelW = nvgTextBounds(vg, 0, 0, procLabel, nil)
                local procValStr = refineProc .. " G"
                local procValW = nvgTextBounds(vg, 0, 0, procValStr, nil)
                local procTotalW = procLabelW + procValW
                local procMidX = detailAreaX + detailAreaW / 2
                local procStartX = procMidX - procTotalW / 2
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, procStartX, curY, procLabel, nil)
                nvgFillColor(vg, costColor)
                nvgText(vg, procStartX + procLabelW, curY, procValStr, nil)

                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                local totalLabel = "总费用: "
                local totalLabelW = nvgTextBounds(vg, 0, 0, totalLabel, nil)
                local totalValStr = refineTotal .. " G"
                nvgText(vg, detailAreaX + detailAreaW - nvgTextBounds(vg, 0, 0, totalValStr, nil), curY, totalLabel, nil)
                nvgFillColor(vg, GS.gold >= refineTotal and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                nvgText(vg, detailAreaX + detailAreaW, curY, totalValStr, nil)
                curY = curY + lineH

                -- 分隔细线
                nvgBeginPath(vg)
                nvgMoveTo(vg, detailAreaX, curY)
                nvgLineTo(vg, detailAreaX + detailAreaW, curY)
                nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 80))
                nvgStrokeWidth(vg, 0.5)
                nvgStroke(vg)
                curY = curY + 4

                -- 逐行显示每个精炼槽
                local canAfford = GS.gold >= GS.getRefineCost(refItem) and stoneCount > 0
                local btnW = math.max(48, detailAreaW * 0.28)
                local btnH = math.max(20, lineH * 1.3)
                GS.craftRefineLockBtnRects = GS.craftRefineLockBtnRects or {}
                for ci = 1, #refineSlots do GS.craftRefineLockBtnRects[ci] = nil end

                for i, rslot in ipairs(refineSlots) do
                    local rowY = curY
                    local isFilled = rslot.attr ~= nil

                    -- 深灰色内容底板
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, detailAreaX, rowY, detailAreaW, btnH, 3)
                    nvgFillColor(vg, nvgRGBA(30, 30, 30, 220))
                    nvgFill(vg)

                    if isFilled then
                        local isLocked = rslot.locked == true
                        -- 已填充：锁定按钮 + 菱形标记 + 词缀名 + 数值 + 重铸按钮
                        local lockSz = math.max(12, btnH * 0.55)
                        local lockX = detailAreaX + 2
                        local lockY = rowY + (btnH - lockSz) / 2
                        local lockImg = isLocked and Renderer.lockClosedImg or Renderer.lockOpenImg
                        if lockImg and lockImg > 0 then
                            local lockPat = nvgImagePattern(vg, lockX, lockY, lockSz, lockSz, 0, lockImg, isLocked and 1.0 or 0.5)
                            nvgBeginPath(vg)
                            nvgRect(vg, lockX, lockY, lockSz, lockSz)
                            nvgFillPaint(vg, lockPat)
                            nvgFill(vg)
                        end
                        GS.craftRefineLockBtnRects[i] = { x = lockX, y = lockY, w = lockSz, h = lockSz }

                        local diamR = bodyFs * 0.3
                        local diamCx = lockX + lockSz + 4 + diamR
                        local diamCy = rowY + btnH / 2

                        local rt = rslot.rolledTier or 0
                        local rr = (rt <= 1 and "common") or (rt <= 3 and "uncommon") or (rt <= 5 and "rare") or (rt <= 7 and "fine") or "superior"
                        local rc = GS.RARITY[rr] and GS.RARITY[rr].color or {200,200,200}

                        -- 阴影
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, diamCx + 1, diamCy - diamR + 1)
                        nvgLineTo(vg, diamCx + diamR + 1, diamCy + 1)
                        nvgLineTo(vg, diamCx + 1, diamCy + diamR + 1)
                        nvgLineTo(vg, diamCx - diamR + 1, diamCy + 1)
                        nvgClosePath(vg)
                        nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
                        nvgFill(vg)
                        -- 主体填充
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, diamCx, diamCy - diamR)
                        nvgLineTo(vg, diamCx + diamR, diamCy)
                        nvgLineTo(vg, diamCx, diamCy + diamR)
                        nvgLineTo(vg, diamCx - diamR, diamCy)
                        nvgClosePath(vg)
                        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 220))
                        nvgFill(vg)
                        -- 高光
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, diamCx, diamCy - diamR)
                        nvgLineTo(vg, diamCx + diamR, diamCy)
                        nvgLineTo(vg, diamCx - diamR, diamCy)
                        nvgClosePath(vg)
                        nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
                        nvgFill(vg)
                        -- 描边
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, diamCx, diamCy - diamR)
                        nvgLineTo(vg, diamCx + diamR, diamCy)
                        nvgLineTo(vg, diamCx, diamCy + diamR)
                        nvgLineTo(vg, diamCx - diamR, diamCy)
                        nvgClosePath(vg)
                        nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1] + 50), math.min(255, rc[2] + 50), math.min(255, rc[3] + 50), 255))
                        nvgStrokeWidth(vg, 0.8)
                        nvgStroke(vg)

                        -- 词缀文本
                        local textX = diamCx + diamR + 6
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, bodyFs)
                        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
                        local valStr = rslot.name .. " +" .. rslot.value .. (rslot.suffix or "")
                        nvgText(vg, textX, diamCy, valStr, nil)

                        -- 重铸按钮（锁定时灰色不可按）
                        local rBtnX = detailAreaX + detailAreaW - btnW
                        local rBtnY = rowY
                        local canReforge = canAfford and not isLocked

                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, rBtnX, rBtnY, btnW, btnH, 3)
                        if canReforge then
                            nvgFillColor(vg, nvgRGBA(140, 100, 20, 220))
                        else
                            nvgFillColor(vg, nvgRGBA(160, 160, 160, 140))
                        end
                        nvgFill(vg)

                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, rBtnX + 0.5, rBtnY + 0.5, btnW - 1, btnH - 1, 3)
                        if canReforge then
                            nvgStrokeColor(vg, nvgRGBA(200, 160, 40, 200))
                        else
                            nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 80))
                        end
                        nvgStrokeWidth(vg, 1)
                        nvgStroke(vg)

                        nvgFontSize(vg, math.max(9, btnH * 0.5))
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        if canReforge then
                            nvgFillColor(vg, nvgRGBA(255, 230, 160, 255))
                        else
                            nvgFillColor(vg, nvgRGBA(130, 110, 80, 140))
                        end
                        nvgText(vg, rBtnX + btnW / 2, rBtnY + btnH / 2, "重铸", nil)

                        -- T级文本
                        nvgFontSize(vg, math.max(9, bodyFs * 0.85))
                        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                        nvgText(vg, rBtnX - 4, diamCy, "T" .. rt, nil)

                        if canReforge then
                            GS.craftRefineSlotBtnRects[i] = { x = rBtnX, y = rBtnY, w = btnW, h = btnH }
                        end
                    else
                        -- 空槽：空心菱形 + "空槽" + 精炼按钮
                        local diamR = bodyFs * 0.3
                        local diamCx = detailAreaX + diamR + 2
                        local diamCy = rowY + btnH / 2

                        nvgBeginPath(vg)
                        nvgMoveTo(vg, diamCx, diamCy - diamR)
                        nvgLineTo(vg, diamCx + diamR, diamCy)
                        nvgLineTo(vg, diamCx, diamCy + diamR)
                        nvgLineTo(vg, diamCx - diamR, diamCy)
                        nvgClosePath(vg)
                        nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 150))
                        nvgStrokeWidth(vg, 1)
                        nvgStroke(vg)

                        local textX = diamCx + diamR + 6
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, bodyFs)
                        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(160, 160, 160, 160))
                        nvgText(vg, textX, diamCy, "空槽", nil)

                        -- 精炼按钮
                        local rBtnX = detailAreaX + detailAreaW - btnW
                        local rBtnY = rowY

                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, rBtnX, rBtnY, btnW, btnH, 3)
                        if canAfford then
                            nvgFillColor(vg, nvgRGBA(60, 120, 40, 220))
                        else
                            nvgFillColor(vg, nvgRGBA(160, 160, 160, 140))
                        end
                        nvgFill(vg)

                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, rBtnX + 0.5, rBtnY + 0.5, btnW - 1, btnH - 1, 3)
                        if canAfford then
                            nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 200))
                        else
                            nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 80))
                        end
                        nvgStrokeWidth(vg, 1)
                        nvgStroke(vg)

                        nvgFontSize(vg, math.max(9, btnH * 0.5))
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        if canAfford then
                            nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
                        else
                            nvgFillColor(vg, nvgRGBA(130, 110, 80, 140))
                        end
                        nvgText(vg, rBtnX + btnW / 2, rBtnY + btnH / 2, "精炼", nil)

                        if canAfford then
                            GS.craftRefineSlotBtnRects[i] = { x = rBtnX, y = rBtnY, w = btnW, h = btnH }
                        end
                    end

                    curY = curY + btnH + 4
                end

                -- 开槽按钮（精炼槽未达上限时显示）
                if #refineSlots < craftMaxRefSlots then
                    curY = curY + 4
                    local toolCount = GS.countInventoryItem("refine_slot_tool")
                    local canDrill = toolCount >= 1

                    nvgBeginPath(vg)
                    nvgMoveTo(vg, detailAreaX, curY)
                    nvgLineTo(vg, detailAreaX + detailAreaW, curY)
                    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 80))
                    nvgStrokeWidth(vg, 0.5)
                    nvgStroke(vg)
                    curY = curY + 6

                    local drillBtnFs = math.max(9, lineH * 0.5)
                    local drillBtnText = "开凿精炼槽（雕刻工具剩余" .. toolCount .. "个）"
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, drillBtnFs)
                    local drillTextW = nvgTextBounds(vg, 0, 0, drillBtnText, nil)
                    local drillBtnPadX = 16
                    local drillBtnW = math.max(80, drillTextW + drillBtnPadX * 2)
                    local drillBtnH = math.max(22, lineH * 1.4)
                    local drillBtnX = detailAreaX + (detailAreaW - drillBtnW) / 2
                    local drillBtnY = curY

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, drillBtnX, drillBtnY, drillBtnW, drillBtnH, 4)
                    nvgFillColor(vg, canDrill and nvgRGBA(40, 100, 140, 220) or nvgRGBA(100, 100, 100, 140))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, drillBtnX + 0.5, drillBtnY + 0.5, drillBtnW - 1, drillBtnH - 1, 4)
                    nvgStrokeColor(vg, canDrill and nvgRGBA(80, 160, 220, 200) or nvgRGBA(160, 160, 160, 80))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    nvgFontSize(vg, drillBtnFs)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, canDrill and nvgRGBA(200, 230, 255, 255) or nvgRGBA(130, 110, 80, 140))
                    nvgText(vg, drillBtnX + drillBtnW / 2, drillBtnY + drillBtnH / 2, drillBtnText, nil)

                    GS.craftRefineDrillBtnRect = { x = drillBtnX, y = drillBtnY, w = drillBtnW, h = drillBtnH }
                    curY = curY + drillBtnH + 4
                end
            else
                -- 没有精炼槽 —— 检查能否用工具开槽
                do
                    local tier2 = GS.getItemTier(item)
                    local maxSlots2 = GS.getMaxRefineSlots(tier2)
                    if maxSlots2 > 0 then
                        local curY = detailAreaY + 10
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, math.max(11, detailAreaH * 0.09))
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                        nvgFillColor(vg, nvgRGBA(180, 60, 40, 200))
                        nvgText(vg, detailAreaX + detailAreaW / 2, curY,
                            "该装备没有精炼槽", nil)
                        curY = curY + lineH + 4
                        nvgFontSize(vg, math.max(10, detailAreaH * 0.08))
                        nvgFillColor(vg, nvgRGBA(150, 150, 150, 200))
                        nvgText(vg, detailAreaX + detailAreaW / 2, curY,
                            "可使用雕刻工具开凿精炼槽(上限" .. maxSlots2 .. "槽)", nil)
                        curY = curY + lineH + 10

                        local toolCount = GS.countInventoryItem("refine_slot_tool")
                        local canDrill = toolCount >= 1

                        local drillBtnW = math.max(80, detailAreaW * 0.5)
                        local drillBtnH = math.max(22, lineH * 1.4)
                        local drillBtnX = detailAreaX + (detailAreaW - drillBtnW) / 2
                        local drillBtnY = curY

                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, drillBtnX, drillBtnY, drillBtnW, drillBtnH, 4)
                        nvgFillColor(vg, canDrill and nvgRGBA(40, 100, 140, 220) or nvgRGBA(100, 100, 100, 140))
                        nvgFill(vg)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, drillBtnX + 0.5, drillBtnY + 0.5, drillBtnW - 1, drillBtnH - 1, 4)
                        nvgStrokeColor(vg, canDrill and nvgRGBA(80, 160, 220, 200) or nvgRGBA(160, 160, 160, 80))
                        nvgStrokeWidth(vg, 1)
                        nvgStroke(vg)

                        nvgFontSize(vg, math.max(9, drillBtnH * 0.5))
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, canDrill and nvgRGBA(200, 230, 255, 255) or nvgRGBA(130, 110, 80, 140))
                        nvgText(vg, drillBtnX + drillBtnW / 2, drillBtnY + drillBtnH / 2,
                            "开凿精炼槽 (0/" .. maxSlots2 .. ")", nil)

                        GS.craftRefineDrillBtnRect = { x = drillBtnX, y = drillBtnY, w = drillBtnW, h = drillBtnH }
                        curY = curY + drillBtnH + 4

                        nvgFontSize(vg, math.max(8, bodyFs * 0.8))
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                        nvgFillColor(vg, canDrill and nvgRGBA(160, 200, 240, 200) or nvgRGBA(200, 80, 60, 200))
                        nvgText(vg, detailAreaX + detailAreaW / 2, curY,
                            "雕刻工具持有: " .. toolCount .. "个", nil)
                    else
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(180, 60, 40, 200))
                        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
                            "该装备没有精炼槽", nil)
                        nvgFontSize(vg, math.max(9, detailAreaH * 0.08))
                        nvgFillColor(vg, nvgRGBA(160, 160, 160, 160))
                        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.55,
                            "(T0装备无法拥有精炼槽)", nil)
                    end
                end
            end
        else
            -- 未放入装备
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
                "从装备栏或背包拖入装备到上方格子", nil)
            nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.6,
                "即可进行精炼", nil)
        end

    -- ======== 修复标签页 ========
    elseif GS.craftTab == "repair" then

        if item then
            local lineH = math.max(14, detailAreaH * 0.09)
            local titleFs = math.max(11, lineH * 0.9)
            local bodyFs = math.max(9, lineH * 0.78)

            local colGap = 8
            local leftW = (detailAreaW - colGap) / 2
            local rightW = leftW
            local leftX = detailAreaX
            local rightX = detailAreaX + leftW + colGap

            -- ---- 左栏：脆化修复 ----
            local lY = detailAreaY + 2

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
            nvgText(vg, leftX + leftW / 2, lY, "-- 脆化修复 --", nil)
            lY = lY + lineH + 2

            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, leftX, lY, "状态: ", nil)
            local stX = leftX + nvgTextBounds(vg, 0, 0, "状态: ", nil)
            if item.brittle then
                nvgFillColor(vg, nvgRGBA(200, 60, 40, 255))
                nvgText(vg, stX, lY, "已脆化", nil)
            else
                nvgFillColor(vg, nvgRGBA(80, 160, 60, 255))
                nvgText(vg, stX, lY, "正常", nil)
            end
            lY = lY + lineH

            if item.brittle then
                local fuelCost, processingFee = GS.getRepairCostBreakdown(item)
                local totalCost = fuelCost + processingFee
                local repairAgentCount = GS.countInventoryItem("divine_repair_agent")
                local canAfford = GS.gold >= totalCost and repairAgentCount >= 1

                nvgFontSize(vg, bodyFs)
                -- 燃料费（标签深棕 + 数字金色）
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, leftX, lY, "燃料费: ", nil)
                local fuelLW = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
                nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
                nvgText(vg, leftX + fuelLW, lY, fuelCost .. " G", nil)
                lY = lY + lineH
                -- 加工费（标签深棕 + 数字金色）
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, leftX, lY, "加工费: ", nil)
                local procLW = nvgTextBounds(vg, 0, 0, "加工费: ", nil)
                nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
                nvgText(vg, leftX + procLW, lY, processingFee .. " G", nil)
                lY = lY + lineH
                -- 总费用（标签深棕 + 数字绿/红）
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, leftX, lY, "总费用: ", nil)
                local totalLW = nvgTextBounds(vg, 0, 0, "总费用: ", nil)
                nvgFillColor(vg, GS.gold >= totalCost and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, leftX + totalLW, lY, totalCost .. " G", nil)
                lY = lY + lineH
                -- 神炼修复剂（图标 + 全名 + 数量）
                local repairIconSz = math.max(14, bodyFs * 1.2)
                local repairIconPad = 1
                local repairTpl = GS.ITEM_TEMPLATES and GS.ITEM_TEMPLATES["divine_repair_agent"]
                local repairIconPath = repairTpl and repairTpl.icon or "image/item_divine_repair.png"
                local repairImg = ImageManager.lazyGet("item", repairIconPath)
                if repairImg and repairImg ~= -1 then
                    local iy = lY
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, leftX, iy, repairIconSz, repairIconSz, 2)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                    local ip = nvgImagePattern(vg, leftX + repairIconPad, iy + repairIconPad, repairIconSz - repairIconPad * 2, repairIconSz - repairIconPad * 2, 0, repairImg, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, leftX + repairIconPad, iy + repairIconPad, repairIconSz - repairIconPad * 2, repairIconSz - repairIconPad * 2, 2)
                    nvgFillPaint(vg, ip)
                    nvgFill(vg)
                end
                local repairTextX = leftX + repairIconSz + 4
                local repairTextY = lY + repairIconSz / 2
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, repairTextX, repairTextY, "神炼修复剂 ", nil)
                local repairNameW = nvgTextBounds(vg, 0, 0, "神炼修复剂 ", nil)
                nvgFillColor(vg, repairAgentCount >= 1 and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, repairTextX + repairNameW, repairTextY, tostring(repairAgentCount), nil)
                local cntW = nvgTextBounds(vg, 0, 0, tostring(repairAgentCount), nil)
                nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
                nvgText(vg, repairTextX + repairNameW + cntW, repairTextY, "/1", nil)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                lY = lY + math.max(lineH, repairIconSz + 2)

                -- 按钮位置：靠近底部
                local btnW = math.min(leftW, 100)
                local btnH = math.max(22, lineH * 1.4)
                local btnX = leftX + (leftW - btnW) / 2
                local btnBottomY = detailAreaY + detailAreaH - lineH - 8
                local btnY = btnBottomY - btnH

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
                nvgFillColor(vg, canAfford and nvgRGBA(60, 120, 40, 230) or nvgRGBA(160, 160, 160, 150))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 4)
                nvgStrokeColor(vg, canAfford and nvgRGBA(100, 180, 60, 220) or nvgRGBA(160, 160, 160, 100))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(11, btnH * 0.5))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, canAfford and nvgRGBA(220, 240, 200, 255) or nvgRGBA(180, 120, 120, 180))
                nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "脆化修复", nil)

                GS.craftRepairBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
            else
                GS.craftRepairBtnRect = nil
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(100, 180, 80, 180))
                nvgText(vg, leftX + leftW / 2, lY, "状态正常", nil)
            end

            -- ---- 右栏：韧性修复 ----
            local rY = detailAreaY + 2

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
            nvgText(vg, rightX + rightW / 2, rY, "-- 韧性修复 --", nil)
            rY = rY + lineH + 2

            GS.ensureRefineToughness(item)
            local curTough = item.refineToughness or 0
            local maxTough = GS.getMaxRefineToughness(item)

            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, rightX, rY, "韧性: ", nil)
            local tX = rightX + nvgTextBounds(vg, 0, 0, "韧性: ", nil)
            if curTough >= maxTough then
                nvgFillColor(vg, nvgRGBA(80, 160, 60, 255))
            else
                nvgFillColor(vg, nvgRGBA(200, 60, 40, 255))
            end
            nvgText(vg, tX, rY, tostring(curTough), nil)
            local tX2 = tX + nvgTextBounds(vg, 0, 0, tostring(curTough), nil)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
            nvgText(vg, tX2, rY, "/" .. maxTough, nil)
            rY = rY + lineH

            if curTough < maxTough then
                local fuelCost2, processingFee2 = GS.getRepairCostBreakdown(item)
                local totalCost2 = fuelCost2 + processingFee2
                local toughAgentCount = GS.countInventoryItem("divine_toughness_agent")
                local canAfford2 = GS.gold >= totalCost2 and toughAgentCount >= 1

                nvgFontSize(vg, bodyFs)
                -- 燃料费（标签深棕 + 数字金色）
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, rightX, rY, "燃料费: ", nil)
                local fuelLW2 = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
                nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
                nvgText(vg, rightX + fuelLW2, rY, fuelCost2 .. " G", nil)
                rY = rY + lineH
                -- 加工费（标签深棕 + 数字金色）
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, rightX, rY, "加工费: ", nil)
                local procLW2 = nvgTextBounds(vg, 0, 0, "加工费: ", nil)
                nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
                nvgText(vg, rightX + procLW2, rY, processingFee2 .. " G", nil)
                rY = rY + lineH
                -- 总费用（标签深棕 + 数字绿/红）
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, rightX, rY, "总费用: ", nil)
                local totalLW2 = nvgTextBounds(vg, 0, 0, "总费用: ", nil)
                nvgFillColor(vg, GS.gold >= totalCost2 and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, rightX + totalLW2, rY, totalCost2 .. " G", nil)
                rY = rY + lineH
                -- 神炼增韧剂（图标 + 全名 + 数量）
                local toughIconSz = math.max(14, bodyFs * 1.2)
                local toughIconPad = 1
                local toughTpl = GS.ITEM_TEMPLATES and GS.ITEM_TEMPLATES["divine_toughness_agent"]
                local toughIconPath = toughTpl and toughTpl.icon or "image/item_divine_toughness.png"
                local toughImg = ImageManager.lazyGet("item", toughIconPath)
                if toughImg and toughImg ~= -1 then
                    local iy = rY
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, rightX, iy, toughIconSz, toughIconSz, 2)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                    local ip2 = nvgImagePattern(vg, rightX + toughIconPad, iy + toughIconPad, toughIconSz - toughIconPad * 2, toughIconSz - toughIconPad * 2, 0, toughImg, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, rightX + toughIconPad, iy + toughIconPad, toughIconSz - toughIconPad * 2, toughIconSz - toughIconPad * 2, 2)
                    nvgFillPaint(vg, ip2)
                    nvgFill(vg)
                end
                local toughTextX = rightX + toughIconSz + 4
                local toughTextY = rY + toughIconSz / 2
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, toughTextX, toughTextY, "神炼增韧剂 ", nil)
                local toughNameW = nvgTextBounds(vg, 0, 0, "神炼增韧剂 ", nil)
                nvgFillColor(vg, toughAgentCount >= 1 and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, toughTextX + toughNameW, toughTextY, tostring(toughAgentCount), nil)
                local cntW2 = nvgTextBounds(vg, 0, 0, tostring(toughAgentCount), nil)
                nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
                nvgText(vg, toughTextX + toughNameW + cntW2, toughTextY, "/1", nil)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                rY = rY + math.max(lineH, toughIconSz + 2)

                -- 按钮位置：靠近底部
                local btnW2 = math.min(rightW, 100)
                local btnH2 = math.max(22, lineH * 1.4)
                local btnX2 = rightX + (rightW - btnW2) / 2
                local btnBottomY2 = detailAreaY + detailAreaH - lineH - 8
                local btnY2 = btnBottomY2 - btnH2

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 4)
                nvgFillColor(vg, canAfford2 and nvgRGBA(60, 120, 40, 230) or nvgRGBA(160, 160, 160, 150))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX2 + 0.5, btnY2 + 0.5, btnW2 - 1, btnH2 - 1, 4)
                nvgStrokeColor(vg, canAfford2 and nvgRGBA(100, 180, 60, 220) or nvgRGBA(160, 160, 160, 100))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(11, btnH2 * 0.5))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, canAfford2 and nvgRGBA(220, 240, 200, 255) or nvgRGBA(180, 120, 120, 180))
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "韧性修复", nil)

                GS.craftToughnessBtnRect = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }
            else
                GS.craftToughnessBtnRect = nil
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(100, 180, 80, 180))
                nvgText(vg, rightX + rightW / 2, rY, "韧性已满", nil)
            end

        else
            -- 未放入装备
            GS.craftRepairBtnRect = nil
            GS.craftToughnessBtnRect = nil
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
                "从装备栏或背包拖入装备到上方格子", nil)
            nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.6,
                "即可进行修复", nil)
        end

    -- ======== 萃取标签页 ========
    elseif GS.craftTab == "extract" then

        local srcItem = GS.extractSourceItem
        local tgtItem = GS.extractTargetItem

        if srcItem and tgtItem then
            local lineH = math.max(14, detailAreaH * 0.09)
            local titleFs = math.max(11, lineH * 0.9)
            local bodyFs = math.max(9, lineH * 0.78)

            local lY = detailAreaY + 2

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
            local descFs = math.max(8, lineH * 0.7)
            nvgFontSize(vg, descFs)
            nvgText(vg, detailAreaX + detailAreaW / 2, lY, "萃取可以将低等级装备的强化等级转移到高等级装备上", nil)
            lY = lY + lineH + 2

            -- 转移信息
            local srcEnhLv = srcItem.enhanceLevel or 0
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, detailAreaX, lY, "转移: ", nil)
            local trW = nvgTextBounds(vg, 0, 0, "转移: ", nil)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
            nvgText(vg, detailAreaX + trW, lY, "+" .. srcEnhLv .. " 强化等级", nil)
            lY = lY + lineH

            -- 费用明细
            local goldDiff, fuelCost, processingFee = GS.getExtractCostBreakdown(srcItem, tgtItem)
            local totalCost = goldDiff + fuelCost + processingFee
            local extractAgentCount = GS.countInventoryItem("divine_extract_agent")
            local canDo = GS.canExtract(srcItem, tgtItem)

            -- 差额
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, detailAreaX, lY, "差额: ", nil)
            local dLW = nvgTextBounds(vg, 0, 0, "差额: ", nil)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
            nvgText(vg, detailAreaX + dLW, lY, goldDiff .. " G", nil)
            lY = lY + lineH
            -- 燃料费
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, detailAreaX, lY, "燃料费: ", nil)
            local fLW = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
            nvgText(vg, detailAreaX + fLW, lY, fuelCost .. " G", nil)
            lY = lY + lineH
            -- 加工费
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, detailAreaX, lY, "加工费: ", nil)
            local pLW = nvgTextBounds(vg, 0, 0, "加工费: ", nil)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
            nvgText(vg, detailAreaX + pLW, lY, processingFee .. " G", nil)
            lY = lY + lineH
            -- 总费用
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, detailAreaX, lY, "总费用: ", nil)
            local tLW = nvgTextBounds(vg, 0, 0, "总费用: ", nil)
            nvgFillColor(vg, GS.gold >= totalCost and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgText(vg, detailAreaX + tLW, lY, totalCost .. " G", nil)
            lY = lY + lineH

            -- 神炼萃取剂（图标 + 名称 + 数量）
            local agentIconSz = math.max(14, bodyFs * 1.2)
            local agentIconPad = 1
            local agentTpl = GS.ITEM_TEMPLATES and GS.ITEM_TEMPLATES["divine_extract_agent"]
            local agentIconPath = agentTpl and agentTpl.icon or "image/item_divine_extract.png"
            local agentImg = ImageManager.lazyGet("item", agentIconPath)
            if agentImg and agentImg ~= -1 then
                local iy = lY
                nvgBeginPath(vg)
                nvgRoundedRect(vg, detailAreaX, iy, agentIconSz, agentIconSz, 2)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                local ip = nvgImagePattern(vg, detailAreaX + agentIconPad, iy + agentIconPad,
                    agentIconSz - agentIconPad * 2, agentIconSz - agentIconPad * 2, 0, agentImg, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, detailAreaX + agentIconPad, iy + agentIconPad,
                    agentIconSz - agentIconPad * 2, agentIconSz - agentIconPad * 2, 2)
                nvgFillPaint(vg, ip)
                nvgFill(vg)
            end
            local agentTextX = detailAreaX + agentIconSz + 4
            local agentTextY = lY + agentIconSz / 2
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, agentTextX, agentTextY, "神炼萃取剂 ", nil)
            local agentNameW = nvgTextBounds(vg, 0, 0, "神炼萃取剂 ", nil)
            local agentNeed = GS.getExtractAgentCost((srcItem and srcItem.enhanceLevel or 0))
            nvgFillColor(vg, extractAgentCount >= agentNeed and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgText(vg, agentTextX + agentNameW, agentTextY, tostring(extractAgentCount), nil)
            local cntW = nvgTextBounds(vg, 0, 0, tostring(extractAgentCount), nil)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
            nvgText(vg, agentTextX + agentNameW + cntW, agentTextY, "/" .. agentNeed, nil)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            lY = lY + math.max(lineH, agentIconSz + 2)

            -- 萃取按钮（居中于最后一行文本 lY 与面板底部之间）
            local btnW = math.min(detailAreaW, 100)
            local btnH = math.max(22, lineH * 1.4)
            local btnX = detailAreaX + (detailAreaW - btnW) / 2
            local panelBottom = detailAreaY + detailAreaH
            local btnY = lY + (panelBottom - lY - btnH) / 2

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
            nvgFillColor(vg, canDo and nvgRGBA(60, 80, 140, 230) or nvgRGBA(160, 160, 160, 150))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 4)
            nvgStrokeColor(vg, canDo and nvgRGBA(80, 120, 200, 220) or nvgRGBA(160, 160, 160, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, btnH * 0.5))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, canDo and nvgRGBA(200, 220, 255, 255) or nvgRGBA(180, 120, 120, 180))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "萃取", nil)

            GS.craftExtractBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        else
            -- 提示放入装备
            GS.craftExtractBtnRect = nil
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            if not srcItem and not tgtItem then
                nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.3,
                    "将有强化等级的低级装备放入左侧", nil)
                nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.5,
                    "将强化等级较低的高级装备放入右侧", nil)
                nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.7,
                    "即可进行强化等级转移", nil)
            elseif not srcItem then
                nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
                    "请放入源装备（有强化等级）", nil)
            else
                nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
                    "请放入目标装备（强化等级较低的高级装备）", nil)
            end
        end

    end  -- end craftTab switch

    -- ============ 结果消息（所有标签页共享位置） ============
    local activeResult = nil
    if GS.craftTab == "enhance" then activeResult = GS.craftEnhanceResult
    elseif GS.craftTab == "refine" then activeResult = GS.craftRefineResult
    elseif GS.craftTab == "repair" then activeResult = GS.craftRepairResult
    elseif GS.craftTab == "extract" then activeResult = GS.craftExtractResult
    end

    if activeResult and activeResult.timer and activeResult.timer > 0 then
        local res = activeResult
        local alpha = res.pending and 1 or math.min(1, res.timer / 0.3)
        local msgFs = math.max(12, panelH * 0.04)
        local msgY = panelY + panelH - innerPad - 14
        local msgColor
        if res.pending then
            msgColor = {220, 200, 80}   -- 处理中：黄色
        elseif res.success then
            msgColor = {50, 200, 80}
        else
            msgColor = {200, 60, 40}
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgTw = nvgTextBounds(vg, 0, 0, res.msg or "", nil)
        local msgBgW = msgTw + 20
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end
end

-- ====================================================================
-- 装备强化面板渲染
-- ====================================================================
function M.drawEnhancePanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 羊皮纸底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 装备强化 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.enhanceCloseRect = p.closeRect

    -- ============ 上方：单放置槽（居中） ============
    local slotSize = math.min(math.floor(panelW * 0.22), math.floor(contentH * 0.25))
    local slotX = panelX + (panelW - slotSize) / 2
    local slotY = contentY + 8
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    -- 注册放置槽区域（供 Input.lua 检测拖拽落点）
    GS.enhanceDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

    local item = GS.enhanceSlotItem

    -- 外框描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    -- 底部微光
    nvgBeginPath(vg)
    nvgMoveTo(vg, slotX + slotR, slotY + slotSize - 1)
    nvgLineTo(vg, slotX + slotSize - slotR, slotY + slotSize - 1)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if item then
        -- 有物品：显示图标
        local tpl = GS.itemTemplates[item.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰（精炼/附魔/强化等级/锁定/收藏，与背包栏一致）
        drawItemDecorations(vg, item, slotX, slotY, slotSize)

        -- 名称（槽位下方居中）
        local nameFs = math.max(9, math.floor(slotSize * 0.2))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize + 3, (item.name or ""):gsub(" %+%d+$", ""), nil)
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "装备", nil)
    end

    -- ============ 分隔线 ============
    local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
    local sepY = slotY + slotSize + nameAreaH
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, sepY)
    nvgLineTo(vg, panelX + panelW - 12, sepY)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 下方：强化详情 ============
    local detailAreaX = panelX + innerPad
    local detailAreaY = sepY + 6
    local detailAreaW = panelW - innerPad * 2
    local detailAreaH = panelY + panelH - innerPad - detailAreaY

    local effectNames = {
        atk = "物理攻击力", def = "物理防御力", hp = "生命值", mp = "魔法值",
        spd = "速度", crit = "暴击率",
        str = "力量", wis = "智慧", agi = "敏捷", con = "体质",
        foc = "专注", per = "感知", wil = "意念",
        hpRegen = "HP自然回复", hpDrain = "HP流失", critVal = "暴击值", dodge = "闪避值",
        hit = "命中值", maxMonsters = "怪物出现上限", spawnCount = "怪物出现数量",
        critDmg = "暴击伤害", lifesteal = "吸血",
        batFangLifesteal = "吸血",
        physLifesteal = "物理吸血", magLifesteal = "法术吸血",
        manaLeech = "魔力回收",
        moveRange = "移动距离", atkSpeed = "攻速",
        mAtk = "魔法攻击力", mDef = "魔法防御力",
        mpRegen = "MP自然回复",
        mCritVal = "魔法暴击值", mCritDmg = "魔法暴击伤害",
        luk = "幸运", cha = "魅力",
        fireDmgBonus = "火焰伤害", iceDmgBonus = "冰冻伤害",
        elecDmgBonus = "雷电伤害", lightDmgBonus = "神圣伤害",
        ragingFireBonus = "燃火",
        radianceDmgBonus = "辉光伤害", radianceNearDmgBonus = "辉光近处增伤", radianceStunChance = "辉光晕眩",
        rangedDefRate = "远程减伤", rangedDefCap = "远程减伤上限",
        cstarAgiL = "伴随星敏捷", cstarAtkSpdL = "伴随星攻速",
        cstarStrR = "伴随星力量", cstarWisR = "伴随星智慧",
        cstarCritDmgR = "伴随星物暴伤", cstarMCritDmgR = "伴随星法暴伤",
        swordDmgBonus = "剑类伤害", daggerDmgBonus = "匕首伤害",
        maceDmgBonus = "钉锤伤害", bowDmgBonus = "弓类伤害",
        staffDmgBonus = "法杖伤害", physDmgBonus = "物理伤害",
        magDmgBonus = "魔法伤害",
        eleFlowBonus = "元素流转增伤",
        arsenalScatter = "散射",
        healStoreRate = "治疗存储", healReleaseRate = "存储释放",
        furyStackPerCrit = "狂怒叠加", furyMaxStacks = "狂怒上限", furyDecayOnNonCrit = "狂怒衰减",
        distDmgPctPerGrid = "距离伤害",
        dodgeRateBonus1 = "闪避率额外提高", dodgeRateBonus2 = "闪避率额外提高",
        killExpBonus = "击杀怪物经验值获取",
    }
    local hiddenAttrs2 = { batFangCount = true }

    if item then
        local tpl = GS.itemTemplates[item.templateId]
        local maxLv = GS.getMaxEnhance(item)
        local enhLv = item.enhanceLevel or 0
        local cost = GS.getEnhanceCost(item)
        local gain = GS.getEnhanceGain(item, enhLv)
        local matId, matQty, matOwned = GS.getEnhanceMaterialInfo(item)
        local matName = ""
        if matId then
            local matTpl = GS.itemTemplates[matId]
            matName = matTpl and matTpl.name or matId
        end
        local successRate = GS.getEnhanceSuccessRate(item)
        local canAfford = GS.gold >= cost and (not matId or matOwned >= matQty)
        local isMaxed = enhLv >= maxLv

        local lineH = math.max(14, detailAreaH * 0.09)
        local titleFs = math.max(11, lineH * 0.9)
        local bodyFs = math.max(9, lineH * 0.78)

        -- 左半区：属性信息，右半区：强化操作
        local leftW = detailAreaW * 0.55
        local rightW = detailAreaW - leftW - 6
        local rightX = detailAreaX + leftW + 6

        -- ---- 左半区 ----
        local curY = detailAreaY + 2

        -- 强化等级
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, bodyFs)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
        nvgText(vg, detailAreaX, curY, "强化等级: ", nil)
        local lvTextX = detailAreaX + nvgTextBounds(vg, 0, 0, "强化等级: ", nil)
        local _, enhDispC = GS.getEnhanceRarity(enhLv)
        if isMaxed then
            nvgFillColor(vg, nvgRGBA(enhDispC[1], enhDispC[2], enhDispC[3], 255))
            nvgText(vg, lvTextX, curY, enhLv .. "/" .. maxLv .. " (满)", nil)
        else
            nvgFillColor(vg, nvgRGBA(enhDispC[1], enhDispC[2], enhDispC[3], 255))
            nvgText(vg, lvTextX, curY, enhLv .. "/" .. maxLv, nil)
        end
        curY = curY + lineH + 2

        -- 当前属性（含强化加成）
        if item.effects then
            local hasBlock = item.effects.block_chance ~= nil
            for k, v in pairs(item.effects) do
                if k ~= "block_chance" and k ~= "block_amount" then
                    local label = effectNames[k] or k
                    local enhBonus = 0
                    if enhLv > 0 and gain[k] then
                        enhBonus = gain[k]
                    end
                    local totalVal = v + enhBonus
                    nvgFontSize(vg, bodyFs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(50, 100, 50, 255))
                    local sign = totalVal >= 0 and "+" or ""
                    local baseStr = label .. " " .. sign .. totalVal
                    if enhBonus ~= 0 then
                        local enhSign = enhBonus > 0 and "+" or ""
                        baseStr = baseStr .. " (强化" .. enhSign .. enhBonus .. ")"
                    end
                    nvgText(vg, detailAreaX, curY, baseStr, nil)
                    curY = curY + lineH
                end
            end
            if hasBlock then
                local pct = math.floor(item.effects.block_chance * 100)
                local baseBA = item.effects.block_amount or 1
                local enhBonus = 0
                if enhLv > 0 and gain.block_amount then
                    enhBonus = gain.block_amount
                end
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(50, 100, 50, 255))
                local blockStr = pct .. "%概率格挡" .. (baseBA + enhBonus) .. "点物理伤害"
                if enhBonus ~= 0 then
                    local enhSign = enhBonus > 0 and "+" or ""
                    blockStr = blockStr .. " (强化" .. enhSign .. enhBonus .. ")"
                end
                nvgText(vg, detailAreaX, curY, blockStr, nil)
                curY = curY + lineH
            end
        end

        -- 下次强化预览
        if not isMaxed then
            curY = curY + 2
            local nextGain = GS.getEnhanceGain(item, enhLv + 1)
            for k, nv in pairs(nextGain) do
                if k ~= "block_chance" and k ~= "block_amount" then
                    local label = effectNames[k] or k
                    local curBonus = gain[k] or 0
                    local delta = nv - curBonus
                    nvgFontSize(vg, bodyFs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(30, 140, 200, 255))
                    if delta > 0 then
                        nvgText(vg, detailAreaX, curY, "下次强化: " .. label .. " +" .. delta, nil)
                    else
                        nvgText(vg, detailAreaX, curY, "下次强化: " .. label .. " 不变", nil)
                    end
                    curY = curY + lineH
                end
            end
            -- 格挡伤害强化预览
            if nextGain.block_amount then
                local curBA = gain.block_amount or 0
                local delta = nextGain.block_amount - curBA
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(30, 140, 200, 255))
                if delta > 0 then
                    nvgText(vg, detailAreaX, curY, "下次强化: 格挡伤害 +" .. delta, nil)
                else
                    nvgText(vg, detailAreaX, curY, "下次强化: 格挡伤害 不变", nil)
                end
                curY = curY + lineH
            end
        end

        -- ---- 右半区：费用与强化按钮 ----
        if not isMaxed then
            local rY = detailAreaY + 2

            -- 费用标题
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, rightX, rY, "强化费用:", nil)
            rY = rY + lineH

            -- 费用金额
            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, canAfford and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgText(vg, rightX, rY, cost .. " G", nil)
            rY = rY + lineH + 4

            -- 材料需求
            if matId then
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                nvgText(vg, rightX, rY, "材料:", nil)
                rY = rY + lineH

                nvgFontSize(vg, titleFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                if matOwned >= matQty then
                    nvgFillColor(vg, nvgRGBA(80, 140, 60, 255))
                else
                    nvgFillColor(vg, nvgRGBA(200, 60, 40, 255))
                end
                nvgText(vg, rightX, rY, matName .. " x" .. matQty, nil)
                rY = rY + lineH

                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 160))
                nvgText(vg, rightX, rY, "持有: " .. matOwned .. "个", nil)
                rY = rY + lineH + 4
            end

            -- 成功率
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, rightX, rY, "成功率:", nil)
            rY = rY + lineH

            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local ratePct = math.floor(successRate * 100)
            if ratePct >= 100 then
                nvgFillColor(vg, nvgRGBA(80, 140, 60, 255))
            elseif ratePct >= 50 then
                nvgFillColor(vg, nvgRGBA(200, 160, 30, 255))
            else
                nvgFillColor(vg, nvgRGBA(200, 80, 30, 255))
            end
            -- 催化剂加成显示
            local catBonusPct2 = 0
            if GS.enhanceUseCatalyst then
                local catOwned2 = GS.countInventoryItem("divine_catalyst")
                if catOwned2 >= 1 then
                    catBonusPct2 = 5
                end
            end
            local displayPct2 = math.min(100, ratePct + catBonusPct2)
            nvgText(vg, rightX, rY, displayPct2 .. "%", nil)
            if catBonusPct2 > 0 then
                local pctW2 = nvgTextBounds(vg, 0, 0, displayPct2 .. "%", nil)
                nvgFontSize(vg, bodyFs)
                nvgFillColor(vg, nvgRGBA(50, 180, 50, 220))
                nvgText(vg, rightX + pctW2 + 4, rY, "(+5%)", nil)
            end
            rY = rY + lineH + 4

            -- 催化剂勾选框
            do
                local catCount2 = GS.countInventoryItem("divine_catalyst")
                local cbSize2 = math.max(12, lineH * 0.8)
                local cbX2 = rightX
                local cbY2 = rY
                -- 勾选框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cbX2, cbY2, cbSize2, cbSize2, 2)
                if GS.enhanceUseCatalyst and catCount2 >= 1 then
                    nvgFillColor(vg, nvgRGBA(60, 140, 60, 230))
                else
                    nvgFillColor(vg, nvgRGBA(180, 170, 150, 100))
                end
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cbX2 + 0.5, cbY2 + 0.5, cbSize2 - 1, cbSize2 - 1, 2)
                nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                -- 勾选标记
                if GS.enhanceUseCatalyst and catCount2 >= 1 then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, cbSize2 * 0.9)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                    nvgText(vg, cbX2 + cbSize2 / 2, cbY2 + cbSize2 / 2, "✓", nil)
                end
                -- 文字标签
                local labelX2 = cbX2 + cbSize2 + 4
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                if catCount2 >= 1 then
                    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
                else
                    nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
                end
                nvgText(vg, labelX2, cbY2, "催化剂 x" .. catCount2 .. " (成功率+5%)", nil)
                -- 点击区域
                GS.enhanceCatalystCheckRect = { x = cbX2, y = cbY2, w = rightW, h = cbSize2 }
                rY = rY + cbSize2 + 6
            end

            -- 强化按钮
            local btnW = rightW
            local btnH = math.max(24, lineH * 1.6)
            local btnX = rightX
            local btnY = rY

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
            if canAfford then
                nvgFillColor(vg, nvgRGBA(60, 120, 40, 230))
            else
                nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
            end
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 4)
            if canAfford then
                nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 220))
            else
                nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 100))
            end
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(12, btnH * 0.5))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if canAfford then
                nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
            else
                nvgFillColor(vg, nvgRGBA(180, 120, 120, 180))
            end
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "强化", nil)

            GS.enhanceBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        else
            GS.enhanceBtnRect = nil
        end

        -- 不可强化的物品提示
        if maxLv <= 0 then
            GS.enhanceBtnRect = nil
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(10, detailAreaH * 0.1))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 60, 40, 200))
            nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH / 2,
                "该装备无法强化", nil)
        end
    else
        -- 未放入装备，显示提示
        GS.enhanceBtnRect = nil
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 180))
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
            "从装备栏或背包拖入装备到上方格子", nil)
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.6,
            "即可进行强化", nil)
    end

    -- ============ 强化结果消息 ============
    if GS.enhanceResult and GS.enhanceResult.timer and GS.enhanceResult.timer > 0 then
        local res = GS.enhanceResult
        local alpha = res.pending and 1 or math.min(1, res.timer / 0.3)
        local msgFs = math.max(12, panelH * 0.04)
        local msgY = panelY + panelH - innerPad - 14
        local msgColor
        if res.pending then
            msgColor = {220, 200, 80}   -- 处理中：黄色
        elseif res.success then
            msgColor = {50, 200, 80}
        else
            msgColor = {200, 60, 40}
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgTw = nvgTextBounds(vg, 0, 0, res.msg or "", nil)
        local msgBgW = msgTw + 20
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end
end

-- ====================================================================
-- 铁匠台选择弹窗（锻造 / 加工 / 附魔）
-- ====================================================================
function M.drawSmithySelectPopup(vg, bx, by, boardSize)
    -- 弹窗尺寸自适应
    local btnSize = math.floor(boardSize * 0.16)   -- 正方形按钮边长
    local gap = math.floor(btnSize * 0.30)          -- 按钮间距
    local pad = math.floor(btnSize * 0.30)          -- 内边距
    local popW = pad * 2 + btnSize * 3 + gap * 2
    local popH = pad * 2 + btnSize
    local popX = bx + (boardSize - popW) / 2
    local popY = by + (boardSize - popH) / 2

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, bx, by, boardSize, boardSize)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popX, popY, popW, popH, 8)
    nvgFillColor(vg, nvgRGBA(45, 35, 25, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 120, 60, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 关闭按钮（右上角）
    local closeSize = math.floor(btnSize * 0.22)
    local closeX = popX + popW - closeSize - 4
    local closeY = popY + 4
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeSize, closeSize, 4)
    nvgFillColor(vg, nvgRGBA(80, 30, 30, 200))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(closeSize * 0.7))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 60, 60, 255))
    nvgText(vg, closeX + closeSize / 2, closeY + closeSize / 2, "✕", nil)

    -- 三个正方形按钮（纯文字居中）
    local btnY = popY + pad
    local btn1X = popX + pad
    local btn2X = btn1X + btnSize + gap
    local btn3X = btn2X + btnSize + gap
    local labelFs = math.floor(btnSize * 0.32)

    local buttons = {
        { x = btn1X, label = "锻造", key = "forgeBtn" },
        { x = btn2X, label = "加工", key = "craftBtn" },
        { x = btn3X, label = "附魔", key = "enchantBtn" },
    }
    local rects = { closeBtn = { x = closeX, y = closeY, w = closeSize, h = closeSize } }

    for _, b in ipairs(buttons) do
        local bgR, bgG, bgB = 70, 55, 35
        local brR, brG, brB = 180, 140, 70
        local txR, txG, txB = 230, 200, 140

        nvgBeginPath(vg)
        nvgRoundedRect(vg, b.x, btnY, btnSize, btnSize, 6)
        nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(brR, brG, brB, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, labelFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(txR, txG, txB, 255))
        nvgText(vg, b.x + btnSize / 2, btnY + btnSize / 2, b.label, nil)

        rects[b.key] = { x = b.x, y = btnY, w = btnSize, h = btnSize }
    end

    GS.homeSmithySelectRects = rects
end

-- ====================================================================
-- 锻造面板渲染（配方列表 + 锻造按钮）
-- ====================================================================
function M.drawForgePanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 深灰底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 锻造 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.forgeCloseRect = p.closeRect

    -- 玩家锻造等级
    local playerHLv = GS.getLifeSkillHiddenLevel("forging")
    local curTier = GS.lifeSkillTiers["forging"] or 1
    local curExp = GS.lifeSkillExp["forging"] or 0
    local tierDef = GS.LIFE_SKILL_TIERS[curTier]
    local tierName = tierDef and tierDef.name or "入门"
    local tierCol = tierDef and tierDef.col or {120, 100, 70}

    -- 锻造等级显示
    local headerH = math.max(16, contentH * 0.06)
    local headerFs = math.max(9, headerH * 0.75)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, headerFs)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    nvgText(vg, panelX + innerPad, contentY, "锻造等级: ", nil)
    local lx = panelX + innerPad + nvgTextBounds(vg, 0, 0, "锻造等级: ", nil)
    if tierName == "入门" then
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    else
        nvgFillColor(vg, nvgRGBA(tierCol[1], tierCol[2], tierCol[3], 255))
    end
    nvgText(vg, lx, contentY, tierName .. " Lv" .. curExp, nil)

    -- 右侧显示金币
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 190, 60, 220))
    nvgText(vg, panelX + panelW - innerPad, contentY, "金币: " .. (GS.gold or 0) .. " G", nil)

    -- 分隔线
    local listY = contentY + headerH + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, listY - 2)
    nvgLineTo(vg, panelX + panelW - 12, listY - 2)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 配方列表（可滚动） ============
    local listH = panelY + panelH - innerPad - listY
    local rowH = math.max(36, listH / 6.5)  -- 每行高度
    local iconSize = math.floor(rowH * 0.75)
    local recipes = GS.FORGE_RECIPES
    local totalH = #recipes * rowH

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, panelX + 2, listY, panelW - 4, listH)

    GS.forgeBtnRects = {}
    GS.forgeIconRects = {}  -- 产出物品图标区域（用于悬停tooltip）
    local scrollY = GS.forgeScrollY or 0
    -- 限制滚动范围
    local maxScroll = math.max(0, totalH - listH)
    if scrollY < 0 then scrollY = 0 end
    if scrollY > maxScroll then scrollY = maxScroll end
    GS.forgeScrollY = scrollY

    for i, recipe in ipairs(recipes) do
        local ry = listY + (i - 1) * rowH - scrollY
        -- 跳过不可见行
        if ry + rowH > listY and ry < listY + listH then
            local inputTpl = GS.itemTemplates[recipe.inputId]
            local isCrystalCut = recipe.type == "crystal_cut"
            local outputTpl = recipe.outputId and GS.itemTemplates[recipe.outputId] or nil
            -- 切选行：图标显示输入晶矿
            local iconTpl = isCrystalCut and inputTpl or outputTpl
            if inputTpl then
                local levelDeficit = math.max(0, recipe.forgingLevel - playerHLv)
                local failRate = math.min(levelDeficit * 0.04, 1.0)
                local isRisky = levelDeficit > 0  -- 等级不足，有失败率

                -- 交替行底色
                if i % 2 == 0 then
                    nvgBeginPath(vg)
                    nvgRect(vg, panelX + 4, ry, panelW - 8, rowH)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 15))
                    nvgFill(vg)
                end

                -- 图标（切选显示输入晶矿，锻造显示产出锭）
                local ix = panelX + innerPad
                local iy = ry + (rowH - iconSize) / 2
                if iconTpl then
                    local imgHandle = iconTpl.icon and ImageManager.lazyGet("item", iconTpl.icon)
                    if imgHandle and imgHandle ~= -1 then
                        local iconPat = nvgImagePattern(vg, ix, iy, iconSize, iconSize, 0, imgHandle, 1.0)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
                        nvgFillPaint(vg, iconPat)
                        nvgFill(vg)
                    end
                else
                    -- 产出未定：绘制 ? 占位
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
                    nvgFillColor(vg, nvgRGBA(80, 80, 80, 60))
                    nvgFill(vg)
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, iconSize * 0.7)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(180, 150, 100, 200))
                    nvgText(vg, ix + iconSize / 2, iy + iconSize / 2, "?", nil)
                end
                -- 图标边框
                local rd = iconTpl and (GS.RARITY[iconTpl.rarity or "common"] or GS.RARITY.common) or GS.RARITY.common
                local rc = rd.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
                nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 保存图标区域（用于悬停tooltip）
                if iconTpl then
                    local tplId = isCrystalCut and recipe.inputId or recipe.outputId
                    if tplId then
                        GS.forgeIconRects[#GS.forgeIconRects + 1] = {
                            x = ix, y = iy, w = iconSize, h = iconSize,
                            templateId = tplId,
                            listY = listY, listH = listH,
                        }
                    end
                end

                -- 文字区域
                local textX = ix + iconSize + 6
                local textW = panelW - innerPad * 2 - iconSize - 6 - 52  -- 留按钮空间
                local nameFs = math.max(9, rowH * 0.28)
                local detailFs = math.max(8, rowH * 0.22)

                -- 第一行：名称
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, nameFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                local nameCol = rd.color
                local alpha = 255
                if isCrystalCut then
                    -- 切选：显示 "晶矿名 → 切选"
                    nvgFillColor(vg, nvgRGBA(nameCol[1], nameCol[2], nameCol[3], alpha))
                    nvgText(vg, textX, ry + 3, inputTpl.name .. " → 切选", nil)
                else
                    nvgFillColor(vg, nvgRGBA(nameCol[1], nameCol[2], nameCol[3], alpha))
                    nvgText(vg, textX, ry + 3, outputTpl and outputTpl.name or "？（未开放）", nil)
                end

                -- 第二行：消耗/持有 或 切选概率
                local ownCount = 0
                for si = 1, GS.bagSlots do
                    local item = GS.inventory[si]
                    if item and item.templateId == recipe.inputId then
                        ownCount = ownCount + (item.quantity or 1)
                    end
                end
                nvgFontSize(vg, detailFs)
                if isCrystalCut then
                    -- 切选行第二行：概率信息
                    local inputTier = GS.getCrystalTierFromId(recipe.inputId)
                    local odds = inputTier and GS.CRYSTAL_CUT_ODDS[inputTier]
                    -- tier → rarity 映射
                    local tierRarity = { cujing = "uncommon", wanzheng = "rare", chunjing = "fine", shanyao = "superior" }
                    local oddsY = ry + 3 + nameFs + 1
                    local ox = textX
                    if odds then
                        for oi, entry in ipairs(odds) do
                            if oi > 1 then
                                nvgFillColor(vg, nvgRGBA(180, 180, 180, 160))
                                nvgText(vg, ox, oddsY, " ", nil)
                                ox = ox + nvgTextBounds(vg, 0, 0, " ", nil)
                            end
                            local pct = math.floor(entry.chance * 100 + 0.5)
                            local tName = GS.CRYSTAL_CUT_TIER_NAMES[entry.tier] or entry.tier
                            local segStr = pct .. "%" .. tName
                            local trd = GS.RARITY[tierRarity[entry.tier] or "common"] or GS.RARITY.common
                            local trc = trd.color
                            nvgFillColor(vg, nvgRGBA(trc[1], trc[2], trc[3], 230))
                            nvgText(vg, ox, oddsY, segStr, nil)
                            ox = ox + nvgTextBounds(vg, 0, 0, segStr, nil)
                        end
                    end
                    -- 持有数量（在概率后面）
                    local ownStr = " (持有" .. ownCount .. ")"
                    nvgFillColor(vg, nvgRGBA(ownCount > 0 and 80 or 200, ownCount > 0 and 200 or 80, ownCount > 0 and 80 or 60, 220))
                    nvgText(vg, ox, oddsY, ownStr, nil)
                else
                    local detailY = ry + 3 + nameFs + 1
                    nvgFillColor(vg, nvgRGBA(190, 190, 190, 200))
                    local prefix = "消耗: "
                    nvgText(vg, textX, detailY, prefix, nil)
                    local cx = textX + nvgTextBounds(vg, 0, 0, prefix, nil)
                    -- 材料名用稀有度颜色
                    local inputRd = GS.RARITY[inputTpl.rarity or "common"] or GS.RARITY.common
                    local inputRc = inputRd.color
                    local matStr = inputTpl.name .. " ×1"
                    nvgFillColor(vg, nvgRGBA(inputRc[1], inputRc[2], inputRc[3], 230))
                    nvgText(vg, cx, detailY, matStr, nil)
                    cx = cx + nvgTextBounds(vg, 0, 0, matStr, nil)
                    local enough = ownCount > 0
                    local ownStr = "(持有" .. ownCount .. ")"
                    nvgFillColor(vg, nvgRGBA(enough and 80 or 200, enough and 200 or 80, enough and 80 or 60, 220))
                    nvgText(vg, cx + 4, detailY, ownStr, nil)
                end

                -- 第三行：费用信息
                local matValue = inputTpl.value or 0
                local fuelCost = math.ceil(matValue * GS.FORGE_FUEL_RATE)
                local commCost = GS.homeForgeMode and 0 or math.ceil(matValue * GS.FORGE_COMMISSION_RATE)
                local totalCost = fuelCost + commCost
                local costY = ry + 3 + nameFs + detailFs + 3
                local costStr = "费用: " .. totalCost .. " G"
                nvgFillColor(vg, nvgRGBA(190, 190, 190, 200))
                nvgText(vg, textX, costY, costStr, nil)
                -- 等级不足时用彩色标注成功率
                if isRisky then
                    local costW = nvgTextBounds(vg, 0, 0, costStr .. "  ", nil)
                    local successPct = math.floor((1.0 - failRate) * 100 + 0.5)
                    local rateStr = "成功率" .. successPct .. "%"
                    local rateCol = successPct < 50 and nvgRGBA(200, 50, 30, 230) or nvgRGBA(200, 150, 30, 230)
                    nvgFillColor(vg, rateCol)
                    nvgText(vg, textX + costW, costY, rateStr, nil)
                end

                -- 右侧：按钮或锁定标记（留出滚动条空间）
                local scrollBarMargin = 12
                local btnW = math.max(40, math.min(50, panelW * 0.12))
                local btnH = math.max(20, rowH * 0.55)
                local btnX = panelX + panelW - innerPad - btnW - scrollBarMargin
                local btnY = ry + (rowH - btnH) / 2

                do
                    -- 锻造/切选按钮（等级不足时也可点击，但有失败率）
                    local canForge = ownCount > 0 and GS.gold >= totalCost
                    local btnLabel = isCrystalCut and "切选" or "锻造"
                    -- 切选用紫色调，锻造用橙色调
                    local btnFillOn  = isCrystalCut and nvgRGBA(100, 50, 140, 220) or nvgRGBA(140, 70, 20, 220)
                    local btnFillOff = isCrystalCut and nvgRGBA(70, 50, 90, 130)   or nvgRGBA(160, 160, 160, 130)
                    local btnStrkOn  = isCrystalCut and nvgRGBA(160, 100, 200, 200) or nvgRGBA(200, 130, 50, 200)
                    local btnStrkOff = isCrystalCut and nvgRGBA(90, 70, 100, 80)    or nvgRGBA(160, 160, 160, 80)
                    local btnTextOn  = isCrystalCut and nvgRGBA(230, 210, 255, 255) or nvgRGBA(255, 230, 180, 255)
                    local btnTextOff = isCrystalCut and nvgRGBA(120, 100, 130, 150) or nvgRGBA(180, 120, 120, 180)

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 3)
                    nvgFillColor(vg, canForge and btnFillOn or btnFillOff)
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 3)
                    nvgStrokeColor(vg, canForge and btnStrkOn or btnStrkOff)
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, math.max(9, btnH * 0.45))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, canForge and btnTextOn or btnTextOff)
                    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, btnLabel, nil)

                    GS.forgeBtnRects[#GS.forgeBtnRects + 1] = { x = btnX, y = btnY, w = btnW, h = btnH, idx = i }
                end
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条（如果内容超出）
    if totalH > listH then
        local scrollBarW = 8
        local scrollBarX = panelX + panelW - innerPad - 2
        local scrollBarH = math.max(20, listH * (listH / totalH))
        local scrollBarY = listY + (listH - scrollBarH) * (scrollY / maxScroll)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, scrollBarX, scrollBarY, scrollBarW, scrollBarH, 4)
        nvgFillColor(vg, nvgRGBA(120, 120, 120, 120))
        nvgFill(vg)
        GS.forgeScrollBarRect = { x = scrollBarX, y = scrollBarY, w = scrollBarW, h = scrollBarH }
    else
        GS.forgeScrollBarRect = nil
    end

    -- ============ 锻造结果消息 ============
    if GS.forgeResult and GS.forgeResult.timer and GS.forgeResult.timer > 0 then
        local res = GS.forgeResult
        local alpha = math.min(1, res.timer / 0.3)
        local msgFs = math.max(11, panelH * 0.035)
        local msgY = panelY + panelH - innerPad - 10
        local msgColor = res.success and {50, 200, 80} or {200, 60, 40}

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgTw = nvgTextBounds(vg, 0, 0, res.msg or "", nil)
        local msgBgW = msgTw + 20
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end

    -- 存储面板区域用于滚动事件
    GS.forgePanelRect = { x = panelX, y = listY, w = panelW, h = listH, maxScroll = maxScroll or 0 }
end

-- ====================================================================
-- 炼金面板渲染（配方列表 + 炼金按钮）
-- ====================================================================
function M.drawAlchemyPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 深灰底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 炼金 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.alchemyCloseRect = p.closeRect

    -- 玩家炼金等级
    local playerHLv = GS.getLifeSkillHiddenLevel("alchemy")
    local curTier = GS.lifeSkillTiers["alchemy"] or 1
    local curExp = GS.lifeSkillExp["alchemy"] or 0
    local tierDef = GS.LIFE_SKILL_TIERS[curTier]
    local tierName = tierDef and tierDef.name or "入门"
    local tierCol = tierDef and tierDef.col or {120, 60, 160}

    -- 炼金等级显示
    local headerH = math.max(16, contentH * 0.06)
    local headerFs = math.max(9, headerH * 0.75)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, headerFs)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    nvgText(vg, panelX + innerPad, contentY, "炼金等级: ", nil)
    local lx = panelX + innerPad + nvgTextBounds(vg, 0, 0, "炼金等级: ", nil)
    if tierName == "入门" then
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    else
        nvgFillColor(vg, nvgRGBA(tierCol[1], tierCol[2], tierCol[3], 255))
    end
    nvgText(vg, lx, contentY, tierName .. " Lv" .. curExp, nil)

    -- 右侧显示金币
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 190, 60, 220))
    nvgText(vg, panelX + panelW - innerPad, contentY, "金币: " .. (GS.gold or 0) .. " G", nil)

    -- 分隔线
    local listY = contentY + headerH + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, listY - 2)
    nvgLineTo(vg, panelX + panelW - 12, listY - 2)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 配方列表（可滚动） ============
    local listH = panelY + panelH - innerPad - listY
    local rowH = math.max(36, listH / 6.5)
    local iconSize = math.floor(rowH * 0.75)
    local recipes = GS.ALCHEMY_RECIPES
    local totalH = #recipes * rowH

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, panelX + 2, listY, panelW - 4, listH)

    GS.alchemyBtnRects = {}
    GS.alchemyIconRects = {}  -- 产出物品图标区域（用于悬停tooltip）
    local scrollY = GS.alchemyScrollY or 0
    local maxScroll = math.max(0, totalH - listH)
    if scrollY < 0 then scrollY = 0 end
    if scrollY > maxScroll then scrollY = maxScroll end
    GS.alchemyScrollY = scrollY

    for i, recipe in ipairs(recipes) do
        local ry = listY + (i - 1) * rowH - scrollY
        if ry + rowH > listY and ry < listY + listH then
            local inputTpl = GS.itemTemplates[recipe.inputId]
            local outputTpl = GS.itemTemplates[recipe.outputId]
            if inputTpl and outputTpl then
                local levelDeficit = math.max(0, recipe.alchemyLevel - playerHLv)
                local failRate = math.min(levelDeficit * 0.04, 1.0)
                local isRisky = levelDeficit > 0

                -- 交替行底色
                if i % 2 == 0 then
                    nvgBeginPath(vg)
                    nvgRect(vg, panelX + 4, ry, panelW - 8, rowH)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 15))
                    nvgFill(vg)
                end

                -- 图标（显示产出物品）
                local ix = panelX + innerPad
                local iy = ry + (rowH - iconSize) / 2
                local imgHandle = outputTpl.icon and ImageManager.lazyGet("item", outputTpl.icon)
                if imgHandle and imgHandle ~= -1 then
                    local iconPat = nvgImagePattern(vg, ix, iy, iconSize, iconSize, 0, imgHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
                    nvgFillPaint(vg, iconPat)
                    nvgFill(vg)
                end
                -- 图标边框
                local rd = GS.RARITY[outputTpl.rarity or "common"] or GS.RARITY.common
                local rc = rd.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
                nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 保存产出物品图标区域（用于悬停tooltip）
                GS.alchemyIconRects[#GS.alchemyIconRects + 1] = {
                    x = ix, y = iy, w = iconSize, h = iconSize,
                    templateId = recipe.outputId,
                    listY = listY, listH = listH,  -- 裁剪区域信息
                }

                -- 文字区域
                local textX = ix + iconSize + 6
                local nameFs = math.max(9, rowH * 0.28)
                local detailFs = math.max(8, rowH * 0.22)

                -- 第一行：产出名称
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, nameFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                local nameCol = rd.color
                nvgFillColor(vg, nvgRGBA(nameCol[1], nameCol[2], nameCol[3], 255))
                local outCount = recipe.outputCount or 1
                local outLabel = outputTpl.name .. (outCount > 1 and (" ×" .. outCount) or "")
                nvgText(vg, textX, ry + 3, outLabel, nil)

                -- 第二行：消耗/持有
                local ownCount = 0
                for si = 1, GS.bagSlots do
                    local item = GS.inventory[si]
                    if item and item.templateId == recipe.inputId then
                        ownCount = ownCount + (item.quantity or 1)
                    end
                end
                nvgFontSize(vg, detailFs)
                local detailY = ry + 3 + nameFs + 1
                nvgFillColor(vg, nvgRGBA(190, 190, 190, 200))
                local prefix = "消耗: "
                nvgText(vg, textX, detailY, prefix, nil)
                local cx = textX + nvgTextBounds(vg, 0, 0, prefix, nil)
                -- 材料名用稀有度颜色
                local inputRd = GS.RARITY[inputTpl.rarity or "common"] or GS.RARITY.common
                local inputRc = inputRd.color
                local needCount = recipe.inputCount or 1
                local matStr = inputTpl.name .. "×" .. needCount
                nvgFillColor(vg, nvgRGBA(inputRc[1], inputRc[2], inputRc[3], 230))
                nvgText(vg, cx, detailY, matStr, nil)
                cx = cx + nvgTextBounds(vg, 0, 0, matStr, nil)
                -- 持有数量
                local enough = ownCount >= needCount
                local ownStr = "(持有" .. ownCount .. ")"
                nvgFillColor(vg, nvgRGBA(enough and 80 or 200, enough and 200 or 80, enough and 80 or 60, 220))
                nvgText(vg, cx, detailY, ownStr, nil)

                -- 第三行：费用信息（家用炼金台免委托费；莉娜伴侣免委托费）
                local fuelCost = recipe.fuelCost or 0
                local partnerAlchMul = GS.getPartnerDiscount("alchemy_commission")
                local commCost = GS.homeAlchemyMode and 0 or math.ceil((recipe.commissionCost or 0) * partnerAlchMul)
                local totalCost = fuelCost + commCost
                local costY = ry + 3 + nameFs + detailFs + 3
                local costStr = "费用: " .. totalCost .. " G"
                nvgFillColor(vg, nvgRGBA(190, 190, 190, 200))
                nvgText(vg, textX, costY, costStr, nil)
                if isRisky then
                    local costW = nvgTextBounds(vg, 0, 0, costStr .. "  ", nil)
                    local successPct = math.floor((1.0 - failRate) * 100 + 0.5)
                    local rateStr = "成功率" .. successPct .. "%"
                    local rateCol = successPct < 50 and nvgRGBA(200, 50, 30, 230) or nvgRGBA(200, 150, 30, 230)
                    nvgFillColor(vg, rateCol)
                    nvgText(vg, textX + costW, costY, rateStr, nil)
                end

                -- 右侧：炼金按钮（留出滚动条空间）
                local scrollBarMargin = 12
                local btnW = math.max(40, math.min(50, panelW * 0.12))
                local btnH = math.max(20, rowH * 0.55)
                local btnX = panelX + panelW - innerPad - btnW - scrollBarMargin
                local btnY = ry + (rowH - btnH) / 2

                local canAlchemy = ownCount >= needCount and GS.gold >= totalCost
                -- 炼金用紫绿色调
                local btnFillOn  = nvgRGBA(60, 120, 80, 220)
                local btnFillOff = nvgRGBA(60, 80, 60, 130)
                local btnStrkOn  = nvgRGBA(100, 200, 120, 200)
                local btnStrkOff = nvgRGBA(80, 90, 70, 80)
                local btnTextOn  = nvgRGBA(200, 255, 210, 255)
                local btnTextOff = nvgRGBA(100, 120, 90, 150)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 3)
                nvgFillColor(vg, canAlchemy and btnFillOn or btnFillOff)
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 3)
                nvgStrokeColor(vg, canAlchemy and btnStrkOn or btnStrkOff)
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(9, btnH * 0.45))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, canAlchemy and btnTextOn or btnTextOff)
                nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "炼金", nil)

                GS.alchemyBtnRects[#GS.alchemyBtnRects + 1] = { x = btnX, y = btnY, w = btnW, h = btnH, idx = i }
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条
    if totalH > listH then
        local scrollBarW = 8
        local scrollBarX = panelX + panelW - innerPad - 2
        local scrollBarH = math.max(20, listH * (listH / totalH))
        local scrollBarY = listY + (listH - scrollBarH) * (scrollY / maxScroll)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, scrollBarX, scrollBarY, scrollBarW, scrollBarH, 4)
        nvgFillColor(vg, nvgRGBA(80, 140, 90, 120))
        nvgFill(vg)
        GS.alchemyScrollBarRect = { x = scrollBarX, y = scrollBarY, w = scrollBarW, h = scrollBarH }
    else
        GS.alchemyScrollBarRect = nil
    end

    -- ============ 炼金结果消息 ============
    if GS.alchemyResult and GS.alchemyResult.timer and GS.alchemyResult.timer > 0 then
        local res = GS.alchemyResult
        local alpha = math.min(1, res.timer / 0.3)
        local msgFs = math.max(11, panelH * 0.035)
        local msgY = panelY + panelH - innerPad - 10
        local msgColor = res.success and {50, 200, 80} or {200, 60, 40}

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgTw = nvgTextBounds(vg, 0, 0, res.msg or "", nil)
        local msgBgW = msgTw + 20
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end

    -- 存储面板区域用于滚动事件
    GS.alchemyPanelRect = { x = panelX, y = listY, w = panelW, h = listH, maxScroll = maxScroll or 0 }
end

-- ====================================================================
-- 烹饪面板渲染（多材料配方）
-- ====================================================================
function M.drawCookingPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 深灰底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 烹饪 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.cookingCloseRect = p.closeRect

    -- 玩家烹饪等级
    local playerHLv = GS.getLifeSkillHiddenLevel("cooking")
    local curTier = GS.lifeSkillTiers["cooking"] or 1
    local curExp = GS.lifeSkillExp["cooking"] or 0
    local tierDef = GS.LIFE_SKILL_TIERS[curTier]
    local tierName = tierDef and tierDef.name or "入门"
    local tierCol = tierDef and tierDef.col or {120, 60, 160}

    -- 烹饪等级显示
    local headerH = math.max(16, contentH * 0.06)
    local headerFs = math.max(9, headerH * 0.75)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, headerFs)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    nvgText(vg, panelX + innerPad, contentY, "烹饪等级: ", nil)
    local lx = panelX + innerPad + nvgTextBounds(vg, 0, 0, "烹饪等级: ", nil)
    if tierName == "入门" then
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    else
        nvgFillColor(vg, nvgRGBA(tierCol[1], tierCol[2], tierCol[3], 255))
    end
    nvgText(vg, lx, contentY, tierName .. " Lv" .. curExp, nil)

    -- 右侧显示金币
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 190, 60, 220))
    nvgText(vg, panelX + panelW - innerPad, contentY, "金币: " .. (GS.gold or 0) .. " G", nil)

    -- 分隔线
    local listY = contentY + headerH + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, listY - 2)
    nvgLineTo(vg, panelX + panelW - 12, listY - 2)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 配方列表（可滚动） ============
    local listH = panelY + panelH - innerPad - listY
    local rowH = math.max(42, listH / 5.5)  -- 烹饪行稍高（多材料需要更多空间）
    local iconSize = math.floor(rowH * 0.65)
    local recipes = GS.COOKING_RECIPES
    local totalH = #recipes * rowH

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, panelX + 2, listY, panelW - 4, listH)

    GS.cookingBtnRects = {}
    GS.cookingIconRects = {}
    local scrollY = GS.cookingScrollY or 0
    local maxScroll = math.max(0, totalH - listH)
    if scrollY < 0 then scrollY = 0 end
    if scrollY > maxScroll then scrollY = maxScroll end
    GS.cookingScrollY = scrollY

    for i, recipe in ipairs(recipes) do
        local ry = listY + (i - 1) * rowH - scrollY
        if ry + rowH > listY and ry < listY + listH then
            local outputTpl = GS.itemTemplates[recipe.outputId]
            if outputTpl then
                local levelDeficit = math.max(0, recipe.cookingLevel - playerHLv)
                local failRate = math.min(levelDeficit * 0.04, 1.0)
                local isRisky = levelDeficit > 0

                -- 交替行底色
                if i % 2 == 0 then
                    nvgBeginPath(vg)
                    nvgRect(vg, panelX + 4, ry, panelW - 8, rowH)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 15))
                    nvgFill(vg)
                end

                -- 图标（显示产出物品）
                local ix = panelX + innerPad
                local iy = ry + (rowH - iconSize) / 2
                local imgHandle = outputTpl.icon and ImageManager.lazyGet("item", outputTpl.icon)
                if imgHandle and imgHandle ~= -1 then
                    local iconPat = nvgImagePattern(vg, ix, iy, iconSize, iconSize, 0, imgHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
                    nvgFillPaint(vg, iconPat)
                    nvgFill(vg)
                end
                -- 图标边框
                local rd = GS.RARITY[outputTpl.rarity or "common"] or GS.RARITY.common
                local rc = rd.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, ix, iy, iconSize, iconSize, 3)
                nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 保存产出物品图标区域（用于悬停tooltip）
                GS.cookingIconRects[#GS.cookingIconRects + 1] = {
                    x = ix, y = iy, w = iconSize, h = iconSize,
                    templateId = recipe.outputId,
                    listY = listY, listH = listH,
                }

                -- 文字区域
                local textX = ix + iconSize + 6
                local nameFs = math.max(9, rowH * 0.24)
                local detailFs = math.max(7, rowH * 0.18)

                -- 第一行：产出名称
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, nameFs)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                local nameCol = rd.color
                nvgFillColor(vg, nvgRGBA(nameCol[1], nameCol[2], nameCol[3], 255))
                local outCount = recipe.outputCount or 1
                local outLabel = outputTpl.name .. (outCount > 1 and (" ×" .. outCount) or "")
                nvgText(vg, textX, ry + 2, outLabel, nil)

                -- 第二行：消耗材料列表（多材料）
                nvgFontSize(vg, detailFs)
                local detailY = ry + 2 + nameFs + 1
                nvgFillColor(vg, nvgRGBA(190, 190, 190, 200))
                local prefix = "消耗: "
                nvgText(vg, textX, detailY, prefix, nil)
                local cx = textX + nvgTextBounds(vg, 0, 0, prefix, nil)

                -- 检查所有材料是否充足（用于烹饪按钮状态）
                local allEnough = true
                local maxTextX = panelX + panelW - innerPad - math.max(40, math.min(50, panelW * 0.12)) - 16
                for _, inp in ipairs(recipe.inputs) do
                    local matId = inp[1]
                    local matCount = inp[2]
                    local matTpl = nil
                    local ownCount = 0

                    if matId == "any_raw_meat" then
                        -- 任意生肉：统计所有生肉总数
                        matTpl = { name = "任意生肉", rarity = "common" }
                        for _, mid in ipairs(GS.ANY_RAW_MEAT_IDS) do
                            ownCount = ownCount + GS.countInventoryItem(mid)
                        end
                    else
                        matTpl = GS.itemTemplates[matId]
                        ownCount = GS.countInventoryItem(matId)
                    end

                    if matTpl then
                        local enough = ownCount >= matCount
                        if not enough then allEnough = false end

                        -- 材料名×数量(持有)
                        local matStr = matTpl.name .. "×" .. matCount
                        local ownStr = "(" .. ownCount .. ") "
                        local segW = nvgTextBounds(vg, 0, 0, matStr .. ownStr, nil)
                        -- 超出可用宽度时换行
                        if cx + segW > maxTextX and cx > textX + nvgTextBounds(vg, 0, 0, prefix, nil) + 2 then
                            detailY = detailY + detailFs + 1
                            cx = textX + nvgTextBounds(vg, 0, 0, prefix, nil)
                        end

                        local inputRd = GS.RARITY[(matTpl.rarity or "common")] or GS.RARITY.common
                        local inputRc = inputRd.color
                        nvgFillColor(vg, nvgRGBA(inputRc[1], inputRc[2], inputRc[3], 230))
                        nvgText(vg, cx, detailY, matStr, nil)
                        cx = cx + nvgTextBounds(vg, 0, 0, matStr, nil)

                        nvgFillColor(vg, nvgRGBA(enough and 80 or 200, enough and 200 or 80, enough and 80 or 60, 220))
                        nvgText(vg, cx, detailY, ownStr, nil)
                        cx = cx + nvgTextBounds(vg, 0, 0, ownStr, nil)
                    end
                end

                -- 第三行：费用信息（家用灶台免委托费）
                local fuelCost = recipe.fuelCost or 0
                local commCost = GS.homeCookingMode and 0 or (recipe.commissionCost or 0)
                local totalCost = fuelCost + commCost
                local costY = detailY + detailFs + 2
                local costStr = "费用: " .. totalCost .. " G"
                nvgFillColor(vg, nvgRGBA(190, 190, 190, 200))
                nvgText(vg, textX, costY, costStr, nil)
                if isRisky then
                    local costW = nvgTextBounds(vg, 0, 0, costStr .. "  ", nil)
                    local successPct = math.floor((1.0 - failRate) * 100 + 0.5)
                    local rateStr = "成功率" .. successPct .. "%"
                    local rateCol = successPct < 50 and nvgRGBA(200, 50, 30, 230) or nvgRGBA(200, 150, 30, 230)
                    nvgFillColor(vg, rateCol)
                    nvgText(vg, textX + costW, costY, rateStr, nil)
                end

                -- 右侧：烹饪按钮（留出滚动条空间）
                local scrollBarMargin = 12
                local btnW = math.max(40, math.min(50, panelW * 0.12))
                local btnH = math.max(20, rowH * 0.50)
                local btnX = panelX + panelW - innerPad - btnW - scrollBarMargin
                local btnY = ry + (rowH - btnH) / 2

                local canCook = allEnough and GS.gold >= totalCost
                -- 烹饪用暖橙色调
                local btnFillOn  = nvgRGBA(160, 90, 30, 220)
                local btnFillOff = nvgRGBA(100, 70, 50, 130)
                local btnStrkOn  = nvgRGBA(220, 150, 60, 200)
                local btnStrkOff = nvgRGBA(100, 100, 100, 80)
                local btnTextOn  = nvgRGBA(255, 230, 180, 255)
                local btnTextOff = nvgRGBA(120, 100, 80, 150)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 3)
                nvgFillColor(vg, canCook and btnFillOn or btnFillOff)
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 3)
                nvgStrokeColor(vg, canCook and btnStrkOn or btnStrkOff)
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(9, btnH * 0.45))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, canCook and btnTextOn or btnTextOff)
                nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "烹饪", nil)

                GS.cookingBtnRects[#GS.cookingBtnRects + 1] = { x = btnX, y = btnY, w = btnW, h = btnH, idx = i }
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条
    if totalH > listH then
        local scrollBarW = 8
        local scrollBarX = panelX + panelW - innerPad - 2
        local scrollBarH = math.max(20, listH * (listH / totalH))
        local scrollBarY = listY + (listH - scrollBarH) * (scrollY / maxScroll)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, scrollBarX, scrollBarY, scrollBarW, scrollBarH, 4)
        nvgFillColor(vg, nvgRGBA(160, 100, 40, 120))
        nvgFill(vg)
        GS.cookingScrollBarRect = { x = scrollBarX, y = scrollBarY, w = scrollBarW, h = scrollBarH }
    else
        GS.cookingScrollBarRect = nil
    end

    -- ============ 烹饪结果消息 ============
    if GS.cookingResult and GS.cookingResult.timer and GS.cookingResult.timer > 0 then
        local res = GS.cookingResult
        local alpha = math.min(1, res.timer / 0.3)
        local msgFs = math.max(11, panelH * 0.035)
        local msgY = panelY + panelH - innerPad - 10
        local msgColor = res.success and {50, 200, 80} or {200, 60, 40}

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgTw = nvgTextBounds(vg, 0, 0, res.msg or "", nil)
        local msgBgW = msgTw + 20
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end

    -- 存储面板区域用于滚动事件
    GS.cookingPanelRect = { x = panelX, y = listY, w = panelW, h = listH, maxScroll = maxScroll or 0 }
end

-- ====================================================================
-- 宝石镶嵌面板渲染
-- ====================================================================
function M.drawSocketPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 羊皮纸底板 ============
    local darkBg = {20, 15, 8, 255}
    local QM = require("QuestManager")
    -- 判断是否显示重铸分页：非家用手工桌 且 巧作天工二已完成
    local showReforgeTab = (not GS.homeSocketMode) and
        (QM.questStates["side_julie_gem_6"] and QM.questStates["side_julie_gem_6"].status == QM.STATUS_COMPLETED)

    local panelTitle = showReforgeTab and "- 宝石工坊 -" or "- 宝石镶嵌 -"
    local p = drawParchmentPanel(vg, bx, by, boardSize, panelTitle, { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.socketCloseRect = p.closeRect

    -- ============ 分页标签（仅朱莉NPC且完成巧作天工二后显示） ============
    GS.socketTabRects = {}
    if showReforgeTab then
        local tabH = math.max(22, contentH * 0.065)
        local tabs = {
            { label = "宝石镶嵌", tab = "socket" },
            { label = "面纱重铸", tab = "reforge" },
        }
        local tabW = (panelW - innerPad * 2) / #tabs
        local tabY = contentY

        for i, t in ipairs(tabs) do
            local tx = panelX + innerPad + (i - 1) * tabW
            local isActive = (GS.socketTab == t.tab)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx + 1, tabY + 1, tabW - 2, tabH - 2, 3)
            if isActive then
                nvgFillColor(vg, nvgRGBA(50, 40, 25, 240))
            else
                nvgFillColor(vg, nvgRGBA(80, 70, 55, 200))
            end
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx + 1, tabY + 1, tabW - 2, tabH - 2, 3)
            if isActive then
                nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
                nvgStrokeWidth(vg, 1.5)
            else
                nvgStrokeColor(vg, nvgRGBA(140, 120, 80, 180))
                nvgStrokeWidth(vg, 1)
            end
            nvgStroke(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(10, tabH * 0.55))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if isActive then
                nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
            else
                nvgFillColor(vg, nvgRGBA(220, 210, 190, 230))
            end
            nvgText(vg, tx + tabW / 2, tabY + tabH / 2, t.label, nil)

            GS.socketTabRects[i] = { x = tx, y = tabY, w = tabW, h = tabH, tab = t.tab }
        end

        contentY = tabY + tabH + 4
        contentH = contentH - tabH - 4
    else
        -- 没有分页时确保 tab 为 socket
        GS.socketTab = "socket"
    end

    -- ============ 属性名映射 ============
    local attrName = {}
    for _, sd in ipairs(GS.STAT_DEFS) do attrName[sd.key] = sd.name end
    -- 战斗属性 & 元素伤害映射
    local extraAttrNames = {
        pAtk = "物理攻击力", mAtk = "魔法攻击力",
        def = "物理防御力", mDef = "魔法防御力",
        hp = "生命值", mp = "魔法值",
        hpRegen = "HP自然回复", mpRegen = "MP自然回复",
        critVal = "暴击值", critDmg = "暴击伤害",
        mCritVal = "魔法暴击值", mCritDmg = "魔法暴击伤害",
        hit = "命中值", dodge = "闪避值",
        atkSpeed = "攻速", moveRange = "移动距离",
        lifesteal = "吸血", physLifesteal = "物理吸血", magLifesteal = "法术吸血",
        manaLeech = "魔力回收",
        fireDmgBonus = "火焰伤害", iceDmgBonus = "冰冻伤害",
        elecDmgBonus = "雷电伤害", lightDmgBonus = "神圣伤害",
        ragingFireBonus = "燃火",
        radianceDmgBonus = "辉光伤害", radianceNearDmgBonus = "辉光近处增伤", radianceStunChance = "辉光晕眩",
        rangedDefRate = "远程减伤", rangedDefCap = "远程减伤上限",
        cstarAgiL = "伴随星敏捷", cstarAtkSpdL = "伴随星攻速",
        cstarStrR = "伴随星力量", cstarWisR = "伴随星智慧",
        cstarCritDmgR = "伴随星物暴伤", cstarMCritDmgR = "伴随星法暴伤",
        swordDmgBonus = "剑类伤害", daggerDmgBonus = "匕首伤害",
        maceDmgBonus = "钉锤伤害", bowDmgBonus = "弓类伤害",
        staffDmgBonus = "法杖伤害", physDmgBonus = "物理伤害",
        magDmgBonus = "魔法伤害",
        eleFlowBonus = "元素流转增伤",
        arsenalScatter = "散射",
        healStoreRate = "治疗存储", healReleaseRate = "存储释放",
        furyStackPerCrit = "狂怒叠加", furyMaxStacks = "狂怒上限", furyDecayOnNonCrit = "狂怒衰减",
        distDmgPctPerGrid = "距离伤害",
        dodgeRateBonus1 = "闪避率额外提高", dodgeRateBonus2 = "闪避率额外提高",
    }
    for k, v in pairs(extraAttrNames) do attrName[k] = v end

  if GS.socketTab == "socket" then
    -- ============ 上方：装备放置槽（居中） ============
    local slotSize = math.min(math.floor(panelW * 0.20), math.floor(contentH * 0.22))
    local slotX = panelX + (panelW - slotSize) / 2
    local slotY = contentY + 4
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    GS.socketDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

    local equip = GS.socketEquipItem

    -- 外框描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    if equip then
        -- 有装备：显示图标
        local tpl = GS.itemTemplates[equip.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰
        drawItemDecorations(vg, equip, slotX, slotY, slotSize)

        -- 装备名称（槽下方）
        local nameFs = math.max(9, math.floor(slotSize * 0.22))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize + 3, (equip.name or ""):gsub(" %+%d+$", ""), nil)
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入装备", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "镶嵌或开槽", nil)
    end

    -- ============ 分隔线 ============
    local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
    local sepY = slotY + slotSize + nameAreaH
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, sepY)
    nvgLineTo(vg, panelX + panelW - 12, sepY)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 下方详情区域 ============
    local detailAreaX = panelX + innerPad
    local detailAreaY = sepY + 6
    local detailAreaW = panelW - innerPad * 2
    local detailAreaH = panelY + panelH - innerPad - detailAreaY

    local lineH = math.max(14, detailAreaH * 0.065)
    local titleFs = math.max(11, lineH * 0.9)
    local bodyFs = math.max(9, lineH * 0.78)

    -- 重置按钮区域
    GS.socketGemBtnRects = {}
    GS.socketDrillBtnRect = nil

    if equip then
        local gemSlots = equip.gemSlots
        if gemSlots and #gemSlots > 0 then
            local curY = detailAreaY + 2

            -- 持有金币（右上角）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 200))
            nvgText(vg, detailAreaX + detailAreaW, curY, "持有: " .. GS.gold .. " G", nil)

            -- 标题行：宝石槽
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
            nvgText(vg, detailAreaX, curY, "宝石槽:", nil)
            curY = curY + lineH + 4

            -- ---- 宝石槽列表 ----
            local gemSlotSize = math.min(math.floor(detailAreaW * 0.12), math.floor(lineH * 2.2))
            local gemSlotGap = math.max(4, gemSlotSize * 0.15)
            local gemSlotR = math.max(2, gemSlotSize * 0.1)

            for gi, gs in ipairs(gemSlots) do
                local gsx = detailAreaX + (gi - 1) * (gemSlotSize + gemSlotGap)
                local gsy = curY
                local isSelected = (GS.socketSelectedGemSlot == gi)
                local isFilled = gs.gemId ~= nil

                -- 槽底色
                nvgBeginPath(vg)
                nvgRoundedRect(vg, gsx, gsy, gemSlotSize, gemSlotSize, gemSlotR)
                if isSelected then
                    nvgFillColor(vg, nvgRGBA(200, 200, 200, 250))
                else
                    nvgFillColor(vg, nvgRGBA(35, 28, 18, 240))
                end
                nvgFill(vg)

                if isFilled then
                    -- 显示已镶嵌宝石图标
                    local gemTpl = GS.itemTemplates[gs.gemId]
                    local gemImg = gemTpl and gemTpl.icon and ImageManager.lazyGet("item", gemTpl.icon)
                    if gemImg and gemImg ~= -1 then
                        local pad = 2
                        local pat = nvgImagePattern(vg, gsx + pad, gsy + pad,
                            gemSlotSize - pad * 2, gemSlotSize - pad * 2, 0, gemImg, 1.0)
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, gsx + pad, gsy + pad, gemSlotSize - pad * 2, gemSlotSize - pad * 2, gemSlotR)
                        nvgFillPaint(vg, pat)
                        nvgFill(vg)
                    end
                    -- 稀有度边框
                    if gemTpl then
                        local rd = GS.RARITY[gemTpl.rarity or "common"] or GS.RARITY.common
                        local rc = rd.border
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, gsx + 1, gsy + 1, gemSlotSize - 2, gemSlotSize - 2, gemSlotR)
                        nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                        nvgStrokeWidth(vg, 1.5)
                        nvgStroke(vg)
                    end
                else
                    -- 空槽：菱形标记
                    local cx = gsx + gemSlotSize / 2
                    local cy = gsy + gemSlotSize / 2
                    local dr = gemSlotSize * 0.22
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, cx, cy - dr)
                    nvgLineTo(vg, cx + dr, cy)
                    nvgLineTo(vg, cx, cy + dr)
                    nvgLineTo(vg, cx - dr, cy)
                    nvgClosePath(vg)
                    nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 160))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end

                -- 选中高亮边框
                if isSelected then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, gsx - 1, gsy - 1, gemSlotSize + 2, gemSlotSize + 2, gemSlotR + 1)
                    nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 220))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end

                -- 记录点击区域
                GS.socketGemBtnRects[#GS.socketGemBtnRects + 1] = {
                    x = gsx, y = gsy, w = gemSlotSize, h = gemSlotSize,
                    type = "gemSlot", idx = gi, filled = isFilled,
                }
            end

            -- ============ 镶嵌按钮（正方形，与宝石槽同行靠右） ============
            local selSlot2 = GS.socketSelectedGemSlot and gemSlots[GS.socketSelectedGemSlot]
            local canSocket = selSlot2 and not selSlot2.gemId and GS.socketSelectedGemBag
            if canSocket then
                local gemItem2 = GS.inventory[GS.socketSelectedGemBag]
                local gemTpl2 = gemItem2 and GS.itemTemplates[gemItem2.templateId]
                local socketCostBase = gemTpl2 and math.ceil((gemTpl2.value or 0) * 0.50) or 0
                local partnerMul = GS.getPartnerDiscount("socket")
                local socketCost = GS.homeSocketMode and math.ceil(socketCostBase * 0.3) or math.ceil(socketCostBase * partnerMul)
                local afford = GS.gold >= socketCost

                local sBtnSz = gemSlotSize  -- 正方形，与宝石槽等大
                local sBtnR = gemSlotR
                local sBtnX = detailAreaX + detailAreaW - sBtnSz  -- 靠右对齐
                local sBtnY = curY  -- 与宝石槽同行

                -- 按钮背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sBtnX, sBtnY, sBtnSz, sBtnSz, sBtnR)
                nvgFillColor(vg, afford and nvgRGBA(60, 120, 60, 230) or nvgRGBA(100, 100, 100, 180))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sBtnX, sBtnY, sBtnSz, sBtnSz, sBtnR)
                nvgStrokeColor(vg, afford and nvgRGBA(120, 200, 100, 200) or nvgRGBA(120, 120, 120, 150))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 按钮文字：上"镶嵌"下"费用"
                nvgFontFace(vg, "sans")
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local mainFs = math.max(8, sBtnSz * 0.32)
                local subFs = math.max(6, sBtnSz * 0.22)
                nvgFontSize(vg, mainFs)
                nvgFillColor(vg, afford and nvgRGBA(255, 240, 200, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, sBtnX + sBtnSz / 2, sBtnY + sBtnSz * 0.38, "镶嵌", nil)
                nvgFontSize(vg, subFs)
                nvgFillColor(vg, afford and nvgRGBA(220, 200, 140, 200) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, sBtnX + sBtnSz / 2, sBtnY + sBtnSz * 0.68, socketCost .. "G", nil)

                GS.socketGemBtnRects[#GS.socketGemBtnRects + 1] = {
                    x = sBtnX, y = sBtnY, w = sBtnSz, h = sBtnSz,
                    type = "socket", gemSlotIdx = GS.socketSelectedGemSlot, gemBagSlot = GS.socketSelectedGemBag,
                }
            elseif selSlot2 and selSlot2.gemId then
                -- 拆卸按钮（正方形，与宝石槽同行靠右，红色）
                local gemTplR = GS.itemTemplates[selSlot2.gemId]
                local gemValueR = gemTplR and gemTplR.value or 0
                local partnerMulR = GS.getPartnerDiscount("socket")
                local removeCost = GS.homeSocketMode and math.ceil(gemValueR * 0.3) or math.ceil(gemValueR * partnerMulR)
                local canRemove = GS.gold >= removeCost

                local rBtnSz = gemSlotSize
                local rBtnR = gemSlotR
                local rBtnX = detailAreaX + detailAreaW - rBtnSz
                local rBtnY = curY

                -- 按钮背景（保留原有红色配色）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, rBtnX, rBtnY, rBtnSz, rBtnSz, rBtnR)
                nvgFillColor(vg, canRemove and nvgRGBA(140, 60, 40, 220) or nvgRGBA(100, 100, 100, 180))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, rBtnX, rBtnY, rBtnSz, rBtnSz, rBtnR)
                nvgStrokeColor(vg, canRemove and nvgRGBA(200, 100, 80, 200) or nvgRGBA(170, 170, 170, 150))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 按钮文字：上"拆卸"下"费用"
                nvgFontFace(vg, "sans")
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local mainFs = math.max(8, rBtnSz * 0.32)
                local subFs = math.max(6, rBtnSz * 0.22)
                nvgFontSize(vg, mainFs)
                nvgFillColor(vg, canRemove and nvgRGBA(255, 220, 180, 255) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, rBtnX + rBtnSz / 2, rBtnY + rBtnSz * 0.38, "拆卸", nil)
                nvgFontSize(vg, subFs)
                nvgFillColor(vg, canRemove and nvgRGBA(220, 180, 140, 200) or nvgRGBA(200, 60, 40, 255))
                nvgText(vg, rBtnX + rBtnSz / 2, rBtnY + rBtnSz * 0.68, removeCost .. "G", nil)

                GS.socketGemBtnRects[#GS.socketGemBtnRects + 1] = {
                    x = rBtnX, y = rBtnY, w = rBtnSz, h = rBtnSz,
                    type = "remove", idx = GS.socketSelectedGemSlot,
                }
            end

            -- 选中的宝石槽详情文字
            curY = curY + gemSlotSize + 6
            if GS.socketSelectedGemSlot then
                local selSlot = gemSlots[GS.socketSelectedGemSlot]
                if selSlot then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, bodyFs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    if selSlot.gemId then
                        local gemTpl = GS.itemTemplates[selSlot.gemId]
                        local grd = gemTpl and GS.RARITY[gemTpl.rarity or "common"] or GS.RARITY.common
                        local grc = grd.color
                        nvgFillColor(vg, nvgRGBA(grc[1], grc[2], grc[3], 255))
                        nvgText(vg, detailAreaX, curY, "已镶嵌: " .. (gemTpl and gemTpl.name or selSlot.gemId), nil)
                        curY = curY + lineH
                        -- 显示宝石属性
                        if selSlot.gemEffect then
                            for k, v in pairs(selSlot.gemEffect) do
                                nvgFillColor(vg, nvgRGBA(100, 200, 100, 230))
                                nvgText(vg, detailAreaX + 8, curY, (attrName[k] or k) .. " +" .. v, nil)
                                curY = curY + lineH
                            end
                        end
                        curY = curY + 2
                    else
                        nvgFillColor(vg, nvgRGBA(140, 140, 140, 180))
                        nvgText(vg, detailAreaX, curY, "空宝石槽 - 请在下方选择宝石镶嵌", nil)
                        curY = curY + lineH + 2
                    end
                end
            end

            -- ---- 分隔线 ----
            nvgBeginPath(vg)
            nvgMoveTo(vg, detailAreaX, curY)
            nvgLineTo(vg, detailAreaX + detailAreaW, curY)
            nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 80))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
            curY = curY + 4

            -- ---- 背包宝石列表标题 ----
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
            nvgText(vg, detailAreaX, curY, "背包中的宝石:", nil)
            curY = curY + lineH + 2

            -- 收集背包中的宝石
            local bagGems = {}
            for i = 1, GS.bagSlots do
                local inv = GS.inventory[i]
                if inv then
                    local tpl2 = GS.itemTemplates[inv.templateId]
                    if tpl2 and tpl2.gemEffect then
                        bagGems[#bagGems + 1] = { bagSlot = i, item = inv, tpl = tpl2 }
                    end
                end
            end

            if #bagGems == 0 then
                nvgFontSize(vg, bodyFs)
                nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
                nvgText(vg, detailAreaX, curY, "背包中没有宝石", nil)
            else
                -- 可滚动宝石列表区域
                local listTop = curY
                local listBottom = panelY + panelH - innerPad
                local listH = listBottom - listTop
                local rowH = math.max(20, lineH * 1.5)
                local rowGap = 3

                -- 裁剪区域
                nvgSave(vg)
                nvgScissor(vg, detailAreaX, listTop, detailAreaW, listH)

                local scrollY = GS.socketScrollY or 0
                local drawnY = listTop - scrollY

                for gi, gInfo in ipairs(bagGems) do
                    local rowY = drawnY + (gi - 1) * (rowH + rowGap)
                    -- 跳过可视区外的行
                    if rowY + rowH >= listTop and rowY <= listBottom then
                        local isGemSelected = (GS.socketSelectedGemBag == gInfo.bagSlot)

                        -- 深灰色内容底板
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, detailAreaX, rowY, detailAreaW, rowH, 3)
                        nvgFillColor(vg, nvgRGBA(40, 40, 40, 100))
                        nvgFill(vg)

                        -- 行底色（选中高亮）
                        if isGemSelected then
                            nvgBeginPath(vg)
                            nvgRect(vg, detailAreaX, rowY, detailAreaW, rowH)
                            nvgFillColor(vg, nvgRGBA(120, 100, 40, 80))
                            nvgFill(vg)
                        end

                        -- 宝石小图标
                        local iconSz = math.floor(rowH * 0.85)
                        local iconX = detailAreaX + 2
                        local iconY2 = rowY + (rowH - iconSz) / 2
                        local gemImg2 = gInfo.tpl.icon and ImageManager.lazyGet("item", gInfo.tpl.icon)
                        if gemImg2 and gemImg2 ~= -1 then
                            local pat = nvgImagePattern(vg, iconX, iconY2, iconSz, iconSz, 0, gemImg2, 1.0)
                            nvgBeginPath(vg)
                            nvgRoundedRect(vg, iconX, iconY2, iconSz, iconSz, 2)
                            nvgFillPaint(vg, pat)
                            nvgFill(vg)
                        end

                        -- 宝石名称
                        local textX = iconX + iconSz + 6
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, bodyFs)
                        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                        local grd2 = GS.RARITY[gInfo.tpl.rarity or "common"] or GS.RARITY.common
                        local grc2 = grd2.color
                        nvgFillColor(vg, nvgRGBA(grc2[1], grc2[2], grc2[3], 255))
                        local qty = gInfo.item.quantity or 1
                        local displayName = gInfo.tpl.name
                        if qty > 1 then displayName = displayName .. " x" .. qty end
                        nvgText(vg, textX, rowY + rowH / 2, displayName, nil)

                        -- 属性加成（右侧）
                        if gInfo.item.abyssAffix then
                            -- 深渊词缀：紫色显示
                            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                            nvgFillColor(vg, nvgRGBA(180, 120, 255, 230))
                            nvgText(vg, detailAreaX + detailAreaW - 4, rowY + rowH / 2, gInfo.item.abyssAffix.name, nil)
                        elseif gInfo.tpl.gemEffect then
                            local effectStr = ""
                            for k, v in pairs(gInfo.tpl.gemEffect) do
                                effectStr = (attrName[k] or k) .. "+" .. v
                            end
                            if effectStr ~= "" then
                                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                                nvgFillColor(vg, nvgRGBA(100, 200, 100, 200))
                                nvgText(vg, detailAreaX + detailAreaW - 4, rowY + rowH / 2, effectStr, nil)
                            end
                        end

                        -- 选中边框
                        if isGemSelected then
                            nvgBeginPath(vg)
                            nvgRect(vg, detailAreaX, rowY, detailAreaW, rowH)
                            nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 200))
                            nvgStrokeWidth(vg, 1.5)
                            nvgStroke(vg)
                        end

                        -- 记录点击区域（在裁剪坐标系中）
                        GS.socketGemBtnRects[#GS.socketGemBtnRects + 1] = {
                            x = detailAreaX, y = rowY, w = detailAreaW, h = rowH,
                            type = "gem", bagSlot = gInfo.bagSlot,
                        }
                    end
                end

                nvgRestore(vg)

                -- 记录最大滚动量
                local totalH = #bagGems * (rowH + rowGap)
                GS.socketMaxScrollY = math.max(0, totalH - listH)
            end

        else
            -- 装备没有宝石槽
            local curY = detailAreaY + 10
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, titleFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(180, 80, 60, 220))
            nvgText(vg, panelX + panelW / 2, curY, "该装备没有宝石槽", nil)
            curY = curY + lineH + 4
            nvgFontSize(vg, bodyFs)
            nvgFillColor(vg, nvgRGBA(140, 140, 140, 180))
            nvgText(vg, panelX + panelW / 2, curY, "可使用开孔工具为其添加一个宝石槽", nil)
            curY = curY + lineH + 10

            -- 开槽按钮
            do
                local toolCount = GS.countInventoryItem("socket_drill_tool")
                local canDrill = toolCount >= 1
                local btnW2 = math.min(detailAreaW * 0.7, 180)
                local btnH2 = math.max(28, lineH * 1.8)
                local btnX2 = panelX + (panelW - btnW2) / 2
                local btnY2 = curY

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 4)
                if canDrill then
                    nvgFillColor(vg, nvgRGBA(60, 120, 40, 230))
                else
                    nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
                end
                nvgFill(vg)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, btnX2 + 0.5, btnY2 + 0.5, btnW2 - 1, btnH2 - 1, 4)
                if canDrill then
                    nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 220))
                else
                    nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 100))
                end
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(11, btnH2 * 0.4))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if canDrill then
                    nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
                else
                    nvgFillColor(vg, nvgRGBA(180, 120, 120, 180))
                end
                nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "开凿宝石槽", nil)

                GS.socketDrillBtnRect = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }

                curY = curY + btnH2 + 8

                -- 工具持有数量
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, bodyFs)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                if canDrill then
                    nvgFillColor(vg, nvgRGBA(200, 200, 200, 160))
                else
                    nvgFillColor(vg, nvgRGBA(200, 60, 40, 200))
                end
                nvgText(vg, panelX + panelW / 2, curY, "开孔工具持有: " .. toolCount .. "个", nil)
            end
        end
    else
        -- 没放入装备时的提示
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, titleFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 180))
        nvgText(vg, panelX + panelW / 2, detailAreaY + 10, "将有宝石槽的装备拖入上方槽位", nil)
        nvgFontSize(vg, bodyFs)
        nvgText(vg, panelX + panelW / 2, detailAreaY + 10 + lineH + 6, "即可进行宝石镶嵌或拆卸", nil)
    end

    -- ============ 操作结果提示 ============
    local res = GS.socketResult
    if res and res.timer and res.timer > 0 then
        local alpha = math.min(1.0, res.timer / 0.3)
        local msgFs = math.max(11, titleFs)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgColor = res.success and {80, 220, 80} or {255, 100, 80}
        local msgY = panelY + panelH * 0.5

        local msgBgW = panelW * 0.85
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end

    -- 存储面板区域用于滚动事件
    GS.socketPanelRect = { x = panelX, y = detailAreaY, w = panelW, h = detailAreaH }

  else -- GS.socketTab == "reforge"
    -- ============ 面纱重铸分页 ============
    GS.reforgeVeilDropRect = nil
    GS.reforgeGemDropRect = nil
    GS.reforgeBtnRect = nil
    GS.reforgeCollectBtnRect = nil

    local lineH = math.max(14, contentH * 0.065)
    local titleFs = math.max(11, lineH * 0.9)
    local bodyFs = math.max(9, lineH * 0.78)

    if GS.veilReforgeTime then
        -- ---- 重铸中 / 可领取 ----
        local now = GS._getTrustedTime()
        local elapsed = now - GS.veilReforgeTime
        local remaining = 86400 - elapsed  -- 24h = 86400s

        local curY = contentY + 10
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

        if remaining > 0 then
            -- 重铸中：显示倒计时
            nvgFontSize(vg, titleFs)
            nvgFillColor(vg, nvgRGBA(220, 180, 100, 255))
            nvgText(vg, panelX + panelW / 2, curY, "面纱正在重铸中...", nil)
            curY = curY + lineH + 8

            -- 倒计时显示
            local hours = math.floor(remaining / 3600)
            local mins = math.floor((remaining % 3600) / 60)
            local secs = math.floor(remaining % 60)
            local timeStr = string.format("%02d:%02d:%02d", hours, mins, secs)

            nvgFontSize(vg, titleFs * 1.5)
            nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
            nvgText(vg, panelX + panelW / 2, curY, timeStr, nil)
            curY = curY + lineH * 2 + 10

            nvgFontSize(vg, bodyFs)
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
            nvgText(vg, panelX + panelW / 2, curY, "重铸完成后即可领取新的面纱", nil)
        else
            -- 可领取
            nvgFontSize(vg, titleFs)
            nvgFillColor(vg, nvgRGBA(100, 220, 100, 255))
            nvgText(vg, panelX + panelW / 2, curY, "面纱重铸完成！", nil)
            curY = curY + lineH + 16

            -- 领取按钮
            local btnW = math.min(panelW * 0.6, 160)
            local btnH = math.max(32, lineH * 2)
            local btnX = panelX + (panelW - btnW) / 2
            local btnY = curY

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
            nvgFillColor(vg, nvgRGBA(60, 140, 60, 230))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
            nvgStrokeColor(vg, nvgRGBA(120, 220, 100, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            nvgFontSize(vg, math.max(12, btnH * 0.4))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "领取面纱", nil)

            GS.reforgeCollectBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        end
    else
        -- ---- 未重铸：显示双放置槽 ----
        local slotSize = math.min(math.floor(panelW * 0.20), math.floor(contentH * 0.20))
        local slotR = math.max(3, math.floor(slotSize * 0.08))
        local gap = math.max(24, math.floor(panelW * 0.14))
        local totalW = slotSize * 2 + gap
        local startX = panelX + (panelW - totalW) / 2

        local slotY = contentY + 8

        -- ---- 左槽：面纱 ----
        local veilX = startX
        GS.reforgeVeilDropRect = { x = veilX, y = slotY, w = slotSize, h = slotSize }

        -- 外框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, veilX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
        nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 内凹底色
        local slotGrad = nvgLinearGradient(vg, veilX, slotY, veilX, slotY + slotSize,
            nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, veilX, slotY, slotSize, slotSize, slotR)
        nvgFillPaint(vg, slotGrad)
        nvgFill(vg)

        local veil = GS.reforgeVeilItem
        if veil then
            local tpl = GS.itemTemplates[veil.templateId]
            local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
            if imgHandle and imgHandle ~= -1 then
                local pad = 3
                local iconPat = nvgImagePattern(vg,
                    veilX + pad, slotY + pad,
                    slotSize - pad * 2, slotSize - pad * 2,
                    0, imgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, veilX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
                nvgFillPaint(vg, iconPat)
                nvgFill(vg)
            end
            if tpl then
                local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
                local rc = rd.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, veilX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
                nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end
        else
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(8, slotSize * 0.16))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
            nvgText(vg, veilX + slotSize / 2, slotY + slotSize / 2, "放入面纱", nil)
        end

        -- 左槽标签
        local nameFs = math.max(8, math.floor(slotSize * 0.20))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if veil then
            nvgFillColor(vg, nvgRGBA(180, 120, 255, 255))
            nvgText(vg, veilX + slotSize / 2, slotY + slotSize + 3, "朱莉的面纱", nil)
        else
            nvgFillColor(vg, nvgRGBA(140, 140, 140, 160))
            nvgText(vg, veilX + slotSize / 2, slotY + slotSize + 3, "面纱", nil)
        end

        -- ---- 中间箭头 ----
        local arrowCx = startX + slotSize + gap / 2
        local arrowCy = slotY + slotSize / 2
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(14, slotSize * 0.35))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 160, 120, 200))
        nvgText(vg, arrowCx, arrowCy, "+", nil)

        -- ---- 右槽：卓越宝石 ----
        local gemX = startX + slotSize + gap
        GS.reforgeGemDropRect = { x = gemX, y = slotY, w = slotSize, h = slotSize }

        -- 外框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, gemX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
        nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 内凹底色
        local slotGrad2 = nvgLinearGradient(vg, gemX, slotY, gemX, slotY + slotSize,
            nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, gemX, slotY, slotSize, slotSize, slotR)
        nvgFillPaint(vg, slotGrad2)
        nvgFill(vg)

        local gem = GS.reforgeGemItem
        if gem then
            local tpl = GS.itemTemplates[gem.templateId]
            local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
            if imgHandle and imgHandle ~= -1 then
                local pad = 3
                local iconPat = nvgImagePattern(vg,
                    gemX + pad, slotY + pad,
                    slotSize - pad * 2, slotSize - pad * 2,
                    0, imgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, gemX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
                nvgFillPaint(vg, iconPat)
                nvgFill(vg)
            end
            if tpl then
                local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
                local rc = rd.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, gemX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
                nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end
        else
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(8, slotSize * 0.16))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
            nvgText(vg, gemX + slotSize / 2, slotY + slotSize / 2, "放入宝石", nil)
        end

        -- 右槽标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if gem then
            local tpl = GS.itemTemplates[gem.templateId]
            local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.color
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            nvgText(vg, gemX + slotSize / 2, slotY + slotSize + 3, tpl and tpl.name or "宝石", nil)
        else
            nvgFillColor(vg, nvgRGBA(140, 140, 140, 160))
            nvgText(vg, gemX + slotSize / 2, slotY + slotSize + 3, "卓越宝石", nil)
        end

        -- ---- 分隔线 ----
        local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
        local sepY = slotY + slotSize + nameAreaH
        nvgBeginPath(vg)
        nvgMoveTo(vg, panelX + 12, sepY)
        nvgLineTo(vg, panelX + panelW - 12, sepY)
        nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- ---- 下方区域 ----
        local detailY = sepY + 8
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

        if veil and gem then
            -- 两个槽都有物品：显示重铸按钮
            nvgFontSize(vg, bodyFs)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, panelX + panelW / 2, detailY, "重铸将消耗面纱和宝石", nil)
            detailY = detailY + lineH + 2
            nvgText(vg, panelX + panelW / 2, detailY, "24小时后可领取新的面纱", nil)
            detailY = detailY + lineH + 12

            local btnW = math.min(panelW * 0.6, 160)
            local btnH = math.max(32, lineH * 2)
            local btnX = panelX + (panelW - btnW) / 2
            local btnY = detailY

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
            nvgFillColor(vg, nvgRGBA(140, 80, 40, 230))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
            nvgStrokeColor(vg, nvgRGBA(220, 150, 60, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            nvgFontSize(vg, math.max(12, btnH * 0.4))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "开始重铸", nil)

            GS.reforgeBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        else
            -- 提示放入物品
            nvgFontSize(vg, bodyFs)
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 180))
            if not veil and not gem then
                nvgText(vg, panelX + panelW / 2, detailY, "将面纱和一颗卓越宝石", nil)
                detailY = detailY + lineH + 2
                nvgText(vg, panelX + panelW / 2, detailY, "拖入上方槽位开始重铸", nil)
            elseif not veil then
                nvgText(vg, panelX + panelW / 2, detailY, "请将\"朱莉\"的面纱拖入左侧槽位", nil)
            else
                nvgText(vg, panelX + panelW / 2, detailY, "请将一颗卓越宝石拖入右侧槽位", nil)
            end
            detailY = detailY + lineH + 12
            nvgFontSize(vg, bodyFs * 0.9)
            nvgFillColor(vg, nvgRGBA(140, 120, 90, 160))
            nvgText(vg, panelX + panelW / 2, detailY, "重铸后面纱将获得新的随机词缀", nil)
        end
    end

    -- ============ 操作结果提示（重铸分页） ============
    local res = GS.socketResult
    if res and res.timer and res.timer > 0 then
        local alpha = math.min(1.0, res.timer / 0.3)
        local msgFs = math.max(11, titleFs)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgColor = res.success and {80, 220, 80} or {255, 100, 80}
        local msgY = panelY + panelH * 0.5

        local msgBgW = panelW * 0.85
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end

  end -- socket/reforge tab end
end

-- ====================================================================
-- 赠送礼物面板渲染
-- ====================================================================
function M.drawGiftPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 自适应小面板（居中，紧凑尺寸） ============
    local panelPad = boardSize * 0.04
    local panelW = boardSize - panelPad * 2
    -- 计算紧凑高度：标题 + NPC名 + 槽位 + 物品名 + 按钮 + 间距
    local slotSize = math.min(math.floor(panelW * 0.22), 64)
    local titleH = math.max(26, panelW * 0.09)
    local npcNameFs = math.max(10, panelW * 0.04)
    local btnH = math.max(24, 28)
    local compactH = titleH + npcNameFs + 14 + slotSize + 22 + btnH + 20
    local panelH = compactH
    local panelX = bx + panelPad
    local panelY = by + (boardSize - panelH) / 2  -- 垂直居中
    local panelR = 6

    -- 羊皮纸填充
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgFillColor(vg, nvgRGBA(215, 190, 140, 240))
    nvgFill(vg)

    -- 上下边缘做旧渐变
    local edgeGrad = nvgLinearGradient(vg, panelX, panelY, panelX, panelY + panelH * 0.1,
        nvgRGBA(180, 155, 105, 80), nvgRGBA(180, 155, 105, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH * 0.1, panelR)
    nvgFillPaint(vg, edgeGrad)
    nvgFill(vg)

    -- 黑色描边边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX + 0.5, panelY + 0.5, panelW - 1, panelH - 1, panelR)
    nvgStrokeColor(vg, nvgRGBA(30, 20, 10, 230))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(13, titleH * 0.6))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, "- 赠送礼物 -", nil)

    -- 关闭按钮（左上角 X）
    local closeBtnSize = math.max(18, titleH * 0.7)
    local closeBtnX = panelX + 6
    local closeBtnY = panelY + (titleH - closeBtnSize) / 2
    local closeCx = closeBtnX + closeBtnSize / 2
    local closeCy = closeBtnY + closeBtnSize / 2
    local crossR = closeBtnSize * 0.28
    nvgBeginPath(vg)
    nvgCircle(vg, closeCx, closeCy, closeBtnSize / 2)
    nvgFillColor(vg, nvgRGBA(180, 50, 40, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, closeCx - crossR, closeCy - crossR)
    nvgLineTo(vg, closeCx + crossR, closeCy + crossR)
    nvgMoveTo(vg, closeCx + crossR, closeCy - crossR)
    nvgLineTo(vg, closeCx - crossR, closeCy + crossR)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    GS.giftCloseRect = { x = closeBtnX, y = closeBtnY, w = closeBtnSize, h = closeBtnSize }

    local contentY = panelY + titleH + 2

    -- ============ 赠送对象名称 ============
    npcNameFs = math.max(10, panelW * 0.04)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, npcNameFs)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 70, 30, 180))
    nvgText(vg, panelX + panelW / 2, contentY + 2, "赠送给 " .. (GS.giftNpcName or "NPC"), nil)

    -- ============ 拖入放置槽（居中） ============
    -- slotSize 已在面板顶部计算
    local slotX = panelX + (panelW - slotSize) / 2
    local slotY = contentY + npcNameFs + 12
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    GS.giftDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

    local item = GS.giftSlotItem

    -- 外框描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    -- 底部微光
    nvgBeginPath(vg)
    nvgMoveTo(vg, slotX + slotR, slotY + slotSize - 1)
    nvgLineTo(vg, slotX + slotSize - slotR, slotY + slotSize - 1)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if item then
        -- 有物品：显示图标
        local tpl = GS.itemTemplates[item.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰
        drawItemDecorations(vg, item, slotX, slotY, slotSize)

        -- 右下角堆叠数量
        if item.quantity and item.quantity > 1 then
            local qtyText = tostring(item.quantity)
            local lvFs = math.max(7, math.floor(slotSize * 0.28))
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, lvFs)
            local tw = nvgTextBounds(vg, 0, 0, qtyText, nil, nil)
            local lPad = 3
            local bgW = tw + lPad * 2
            local bgH = lvFs + 4
            local bgX = slotX + slotSize - bgW
            local bgY = slotY + slotSize - bgH
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 3)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
            nvgFill(vg)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, bgX + bgW * 0.5, bgY + bgH * 0.5, qtyText, nil)
        end

        -- 物品名称
        local nameFs = math.max(9, math.floor(slotSize * 0.2))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize + 3, (item.name or ""):gsub(" %+%d+$", ""), nil)

        -- ============ 确认赠送 / 取消 按钮 ============
        local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
        local btnAreaY = slotY + slotSize + nameAreaH + 10
        local btnW = math.min(panelW * 0.35, 100)
        btnH = math.max(24, panelH * 0.065)
        local btnGap = math.max(10, panelW * 0.04)
        local totalBtnW = btnW * 2 + btnGap
        local btnStartX = panelX + (panelW - totalBtnW) / 2

        -- 取消按钮（左）
        local cnlX = btnStartX
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cnlX, btnAreaY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(120, 80, 40, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cnlX + 0.5, btnAreaY + 0.5, btnW - 1, btnH - 1, 4)
        nvgStrokeColor(vg, nvgRGBA(160, 120, 70, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, btnH * 0.5))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 200, 170, 255))
        nvgText(vg, cnlX + btnW / 2, btnAreaY + btnH / 2, "取消", nil)
        GS.giftCancelRect = { x = cnlX, y = btnAreaY, w = btnW, h = btnH }

        -- 确认赠送按钮（右）
        local cfmX = btnStartX + btnW + btnGap
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cfmX, btnAreaY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(60, 120, 40, 230))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cfmX + 0.5, btnAreaY + 0.5, btnW - 1, btnH - 1, 4)
        nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 220))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, math.max(11, btnH * 0.5))
        nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
        nvgText(vg, cfmX + btnW / 2, btnAreaY + btnH / 2, "确认赠送", nil)
        GS.giftConfirmRect = { x = cfmX, y = btnAreaY, w = btnW, h = btnH }
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "物品", nil)

        -- 提示信息
        local tipFs = math.max(9, panelW * 0.035)
        nvgFontSize(vg, tipFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
        nvgText(vg, panelX + panelW / 2, slotY + slotSize + 12, "从背包拖入想要赠送的物品", nil)

        GS.giftConfirmRect = nil
        GS.giftCancelRect = nil

        -- 取消按钮（空槽时也可取消返回交谈）
        local btnW = math.min(panelW * 0.35, 100)
        btnH = math.max(24, panelH * 0.065)
        local btnX = panelX + (panelW - btnW) / 2
        local btnY = slotY + slotSize + 40

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(120, 80, 40, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 4)
        nvgStrokeColor(vg, nvgRGBA(160, 120, 70, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, btnH * 0.5))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 200, 170, 255))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "取消", nil)
        GS.giftCancelRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    end

    -- 赠送拒绝提示（红色描边渐隐文本，垂直居中）
    if GS.giftRejectMsg then
        local msg = GS.giftRejectMsg
        msg.timer = msg.timer - (GS.dt or 0.016)
        if msg.timer <= 0 then
            GS.giftRejectMsg = nil
        else
            local alpha = math.min(255, math.floor(msg.timer / 0.3 * 255))
            local cx = panelX + panelW / 2
            local cy = panelY + panelH / 2
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(12, panelW * 0.045))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 黑色描边
            nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
            for _, off in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do
                nvgText(vg, cx + off[1], cy + off[2], msg.text, nil)
            end
            -- 红色正文
            nvgFillColor(vg, nvgRGBA(220, 50, 40, alpha))
            nvgText(vg, cx, cy, msg.text, nil)
        end
    end
end

-- ====================================================================
-- 任务物品提交面板渲染
-- ====================================================================
function M.drawQuestSubmitPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 自适应小面板（居中，紧凑尺寸） ============
    local panelPad = boardSize * 0.04
    local panelW = boardSize - panelPad * 2
    local slotSize = math.min(math.floor(panelW * 0.22), 64)
    local titleH = math.max(26, panelW * 0.09)
    local npcNameFs = math.max(10, panelW * 0.04)
    local btnH = math.max(24, 28)
    local compactH = titleH + npcNameFs + 14 + slotSize + 22 + btnH + 20
    local panelH = compactH
    local panelX = bx + panelPad
    local panelY = by + (boardSize - panelH) / 2
    local panelR = 6

    -- 羊皮纸填充
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, panelR)
    nvgFillColor(vg, nvgRGBA(215, 190, 140, 240))
    nvgFill(vg)

    -- 上边缘做旧渐变
    local edgeGrad = nvgLinearGradient(vg, panelX, panelY, panelX, panelY + panelH * 0.1,
        nvgRGBA(180, 155, 105, 80), nvgRGBA(180, 155, 105, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH * 0.1, panelR)
    nvgFillPaint(vg, edgeGrad)
    nvgFill(vg)

    -- 描边边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX + 0.5, panelY + 0.5, panelW - 1, panelH - 1, panelR)
    nvgStrokeColor(vg, nvgRGBA(30, 20, 10, 230))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(13, titleH * 0.6))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, "- 提交物品 -", nil)

    -- 关闭按钮（左上角 X）
    local closeBtnSize = math.max(18, titleH * 0.7)
    local closeBtnX = panelX + 6
    local closeBtnY = panelY + (titleH - closeBtnSize) / 2
    local closeCx = closeBtnX + closeBtnSize / 2
    local closeCy = closeBtnY + closeBtnSize / 2
    local crossR = closeBtnSize * 0.28
    nvgBeginPath(vg)
    nvgCircle(vg, closeCx, closeCy, closeBtnSize / 2)
    nvgFillColor(vg, nvgRGBA(180, 50, 40, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, closeCx - crossR, closeCy - crossR)
    nvgLineTo(vg, closeCx + crossR, closeCy + crossR)
    nvgMoveTo(vg, closeCx + crossR, closeCy - crossR)
    nvgLineTo(vg, closeCx - crossR, closeCy + crossR)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    GS.questSubmitCloseRect = { x = closeBtnX, y = closeBtnY, w = closeBtnSize, h = closeBtnSize }

    local contentY = panelY + titleH + 2

    -- ============ 任务名称 ============
    npcNameFs = math.max(10, panelW * 0.04)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, npcNameFs)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 70, 30, 180))
    -- 显示需要提交的物品名称
    local def = GS.questSubmitDef
    local requireDesc = ""
    if def and def.submitPrompt then
        -- 自定义提交提示（requireItemFilter 模式）
        -- 支持 %d 占位符显示剩余数量（用于多次提交任务）
        if def.submitPrompt:find("%%d") and def.progress then
            local cur, total = def.progress(GS)
            requireDesc = string.format(def.submitPrompt, total - cur)
        else
            requireDesc = def.submitPrompt
        end
    elseif def and def.requireItems and #def.requireItems > 0 then
        local ri = def.requireItems[1]
        local tpl = GS.itemTemplates and GS.itemTemplates[ri.templateId]
        local itemName = tpl and tpl.name or ri.templateId
        requireDesc = "请提交: " .. itemName .. " x" .. (ri.count or 1)
    end
    nvgText(vg, panelX + panelW / 2, contentY + 2, requireDesc, nil)

    -- ============ 拖入放置槽（居中） ============
    local slotX = panelX + (panelW - slotSize) / 2
    local slotY = contentY + npcNameFs + 12
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    GS.questSubmitDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

    local item = GS.questSubmitSlotItem

    -- 外框描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    -- 底部微光
    nvgBeginPath(vg)
    nvgMoveTo(vg, slotX + slotR, slotY + slotSize - 1)
    nvgLineTo(vg, slotX + slotSize - slotR, slotY + slotSize - 1)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if item then
        -- 有物品：显示图标
        local tpl = GS.itemTemplates[item.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰
        drawItemDecorations(vg, item, slotX, slotY, slotSize)

        -- 物品名称
        local nameFs = math.max(9, math.floor(slotSize * 0.2))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize + 3, (item.name or ""):gsub(" %+%d+$", ""), nil)

        -- ============ 确认提交 / 取消按钮 ============
        local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
        local btnAreaY = slotY + slotSize + nameAreaH + 10
        local btnW = math.min(panelW * 0.35, 100)
        btnH = math.max(24, panelH * 0.065)
        local btnGap = math.max(10, panelW * 0.04)
        local totalBtnW = btnW * 2 + btnGap
        local btnStartX = panelX + (panelW - totalBtnW) / 2

        -- 取消按钮（左）
        local cnlX = btnStartX
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cnlX, btnAreaY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(120, 80, 40, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cnlX + 0.5, btnAreaY + 0.5, btnW - 1, btnH - 1, 4)
        nvgStrokeColor(vg, nvgRGBA(160, 120, 70, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, btnH * 0.5))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 200, 170, 255))
        nvgText(vg, cnlX + btnW / 2, btnAreaY + btnH / 2, "取消", nil)
        GS.questSubmitCancelRect = { x = cnlX, y = btnAreaY, w = btnW, h = btnH }

        -- 确认提交按钮（右）
        local cfmX = btnStartX + btnW + btnGap
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cfmX, btnAreaY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(60, 120, 40, 230))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cfmX + 0.5, btnAreaY + 0.5, btnW - 1, btnH - 1, 4)
        nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 220))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, math.max(11, btnH * 0.5))
        nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
        nvgText(vg, cfmX + btnW / 2, btnAreaY + btnH / 2, "确认提交", nil)
        GS.questSubmitConfirmRect = { x = cfmX, y = btnAreaY, w = btnW, h = btnH }
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "物品", nil)

        -- 提示信息
        local tipFs = math.max(9, panelW * 0.035)
        nvgFontSize(vg, tipFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
        nvgText(vg, panelX + panelW / 2, slotY + slotSize + 12, "从背包拖入任务所需物品", nil)

        GS.questSubmitConfirmRect = nil
        GS.questSubmitCancelRect = nil

        -- 取消按钮（空槽时也可取消返回交谈）
        local btnW = math.min(panelW * 0.35, 100)
        btnH = math.max(24, panelH * 0.065)
        local btnX = panelX + (panelW - btnW) / 2
        local btnY = slotY + slotSize + 40

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(120, 80, 40, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 4)
        nvgStrokeColor(vg, nvgRGBA(160, 120, 70, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, btnH * 0.5))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 200, 170, 255))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "取消", nil)
        GS.questSubmitCancelRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    end

    -- 拒绝提示（红色描边渐隐文本，垂直居中）
    if GS.questSubmitRejectMsg then
        local msg = GS.questSubmitRejectMsg
        msg.timer = msg.timer - (GS.dt or 0.016)
        if msg.timer <= 0 then
            GS.questSubmitRejectMsg = nil
        else
            local alpha = math.min(255, math.floor(msg.timer / 0.3 * 255))
            local cx = panelX + panelW / 2
            local cy = panelY + panelH / 2
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(12, panelW * 0.045))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 黑色描边
            nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
            for _, off in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do
                nvgText(vg, cx + off[1], cy + off[2], msg.text, nil)
            end
            -- 红色正文
            nvgFillColor(vg, nvgRGBA(220, 50, 40, alpha))
            nvgText(vg, cx, cy, msg.text, nil)
        end
    end
end

-- ====================================================================
-- 装备修复面板渲染（脆化修复）
-- ====================================================================
function M.drawRepairPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 羊皮纸底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 装备修复 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.repairCloseRect = p.closeRect

    -- ============ 上方：单放置槽（居中） ============
    local slotSize = math.min(math.floor(panelW * 0.22), math.floor(contentH * 0.25))
    local slotX = panelX + (panelW - slotSize) / 2
    local slotY = contentY + 8
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    GS.repairDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

    local item = GS.repairSlotItem

    -- 外框描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    -- 底部微光
    nvgBeginPath(vg)
    nvgMoveTo(vg, slotX + slotR, slotY + slotSize - 1)
    nvgLineTo(vg, slotX + slotSize - slotR, slotY + slotSize - 1)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if item then
        -- 有物品：显示图标
        local tpl = GS.itemTemplates[item.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰
        drawItemDecorations(vg, item, slotX, slotY, slotSize)

        -- 名称
        local nameFs = math.max(9, math.floor(slotSize * 0.2))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize + 3, (item.name or ""):gsub(" %+%d+$", ""), nil)
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "装备", nil)
    end

    -- ============ 分隔线 ============
    local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
    local sepY = slotY + slotSize + nameAreaH
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, sepY)
    nvgLineTo(vg, panelX + panelW - 12, sepY)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 下方：修复详情 ============
    local detailAreaX = panelX + innerPad
    local detailAreaY = sepY + 6
    local detailAreaW = panelW - innerPad * 2
    local detailAreaH = panelY + panelH - innerPad - detailAreaY

    if item then
        local lineH = math.max(14, detailAreaH * 0.09)
        local titleFs = math.max(11, lineH * 0.9)
        local bodyFs = math.max(9, lineH * 0.78)

        -- 左右分栏：左=脆化修复，右=韧性修复
        local colGap = 8
        local leftW = (detailAreaW - colGap) / 2
        local rightW = leftW
        local leftX = detailAreaX
        local rightX = detailAreaX + leftW + colGap

        -- ---- 左栏：脆化修复 ----
        local lY = detailAreaY + 2

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, titleFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
        nvgText(vg, leftX + leftW / 2, lY, "-- 脆化修复 --", nil)
        lY = lY + lineH + 2

        nvgFontSize(vg, bodyFs)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
        nvgText(vg, leftX, lY, "状态: ", nil)
        local stX = leftX + nvgTextBounds(vg, 0, 0, "状态: ", nil)
        if item.brittle then
            nvgFillColor(vg, nvgRGBA(200, 60, 40, 255))
            nvgText(vg, stX, lY, "已脆化", nil)
        else
            nvgFillColor(vg, nvgRGBA(80, 160, 60, 255))
            nvgText(vg, stX, lY, "正常", nil)
        end
        lY = lY + lineH + 4

        if item.brittle then
            local fuelCost, processingFee = GS.getRepairCostBreakdown(item)
            local totalCost = fuelCost + processingFee
            local repairAgentCount = GS.countInventoryItem("divine_repair_agent")
            local canAfford = GS.gold >= totalCost and repairAgentCount >= 1

            nvgFontSize(vg, bodyFs)
            -- 燃料费（标签深棕 + 数字金色）
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, leftX, lY, "燃料费: ", nil)
            local fuelLW = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
            nvgText(vg, leftX + fuelLW, lY, fuelCost .. " G", nil)
            lY = lY + lineH
            -- 加工费（标签深棕 + 数字金色）
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, leftX, lY, "加工费: ", nil)
            local procLW = nvgTextBounds(vg, 0, 0, "加工费: ", nil)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
            nvgText(vg, leftX + procLW, lY, processingFee .. " G", nil)
            lY = lY + lineH
            -- 总费用（标签深棕 + 数字绿/红）
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, leftX, lY, "总费用: ", nil)
            local totalLW = nvgTextBounds(vg, 0, 0, "总费用: ", nil)
            nvgFillColor(vg, GS.gold >= totalCost and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgText(vg, leftX + totalLW, lY, totalCost .. " G", nil)
            lY = lY + lineH
            -- 神炼修复剂（图标 + 全名 + 数量）
            local repairIconSz = math.max(14, bodyFs * 1.2)
            local repairIconPad = 1
            local repairTpl = GS.ITEM_TEMPLATES and GS.ITEM_TEMPLATES["divine_repair_agent"]
            local repairIconPath = repairTpl and repairTpl.icon or "image/item_divine_repair.png"
            local repairImg = ImageManager.lazyGet("item", repairIconPath)
            if repairImg and repairImg ~= -1 then
                local iy = lY
                nvgBeginPath(vg)
                nvgRoundedRect(vg, leftX, iy, repairIconSz, repairIconSz, 2)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                local ip = nvgImagePattern(vg, leftX + repairIconPad, iy + repairIconPad, repairIconSz - repairIconPad * 2, repairIconSz - repairIconPad * 2, 0, repairImg, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, leftX + repairIconPad, iy + repairIconPad, repairIconSz - repairIconPad * 2, repairIconSz - repairIconPad * 2, 2)
                nvgFillPaint(vg, ip)
                nvgFill(vg)
            end
            local repairTextX = leftX + repairIconSz + 4
            local repairTextY = lY + repairIconSz / 2
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, repairTextX, repairTextY, "神炼修复剂 ", nil)
            local repairNameW = nvgTextBounds(vg, 0, 0, "神炼修复剂 ", nil)
            nvgFillColor(vg, repairAgentCount >= 1 and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgText(vg, repairTextX + repairNameW, repairTextY, tostring(repairAgentCount), nil)
            local cntW = nvgTextBounds(vg, 0, 0, tostring(repairAgentCount), nil)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
            nvgText(vg, repairTextX + repairNameW + cntW, repairTextY, "/1", nil)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            lY = lY + math.max(lineH, repairIconSz + 2) + 6

            -- 脆化修复按钮
            local btnW = math.min(leftW, 100)
            local btnH = math.max(22, lineH * 1.4)
            local btnX = leftX + (leftW - btnW) / 2
            local btnY = lY

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
            nvgFillColor(vg, canAfford and nvgRGBA(60, 120, 40, 230) or nvgRGBA(160, 160, 160, 150))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 4)
            nvgStrokeColor(vg, canAfford and nvgRGBA(100, 180, 60, 220) or nvgRGBA(160, 160, 160, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, btnH * 0.5))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, canAfford and nvgRGBA(220, 240, 200, 255) or nvgRGBA(180, 120, 120, 180))
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "脆化修复", nil)

            GS.repairBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        else
            GS.repairBtnRect = nil
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(80, 140, 60, 180))
            nvgText(vg, leftX + leftW / 2, lY, "状态正常", nil)
        end

        -- ---- 右栏：韧性修复 ----
        local rY = detailAreaY + 2

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, titleFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
        nvgText(vg, rightX + rightW / 2, rY, "-- 韧性修复 --", nil)
        rY = rY + lineH + 2

        GS.ensureRefineToughness(item)
        local curTough = item.refineToughness or 0
        local maxTough = GS.getMaxRefineToughness(item)

        nvgFontSize(vg, bodyFs)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
        nvgText(vg, rightX, rY, "韧性: ", nil)
        local tX = rightX + nvgTextBounds(vg, 0, 0, "韧性: ", nil)
        if curTough >= maxTough then
            nvgFillColor(vg, nvgRGBA(80, 160, 60, 255))
        else
            nvgFillColor(vg, nvgRGBA(200, 60, 40, 255))
        end
        nvgText(vg, tX, rY, tostring(curTough), nil)
        local tX2 = tX + nvgTextBounds(vg, 0, 0, tostring(curTough), nil)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgText(vg, tX2, rY, "/" .. maxTough, nil)
        rY = rY + lineH + 4

        if curTough < maxTough then
            local fuelCost2, processingFee2 = GS.getRepairCostBreakdown(item)
            local totalCost2 = fuelCost2 + processingFee2
            local toughAgentCount = GS.countInventoryItem("divine_toughness_agent")
            local canAfford2 = GS.gold >= totalCost2 and toughAgentCount >= 1

            nvgFontSize(vg, bodyFs)
            -- 燃料费（标签深棕 + 数字金色）
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, rightX, rY, "燃料费: ", nil)
            local fuelLW2 = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
            nvgText(vg, rightX + fuelLW2, rY, fuelCost2 .. " G", nil)
            rY = rY + lineH
            -- 加工费（标签深棕 + 数字金色）
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, rightX, rY, "加工费: ", nil)
            local procLW2 = nvgTextBounds(vg, 0, 0, "加工费: ", nil)
            nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
            nvgText(vg, rightX + procLW2, rY, processingFee2 .. " G", nil)
            rY = rY + lineH
            -- 总费用（标签深棕 + 数字绿/红）
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, rightX, rY, "总费用: ", nil)
            local totalLW2 = nvgTextBounds(vg, 0, 0, "总费用: ", nil)
            nvgFillColor(vg, GS.gold >= totalCost2 and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgText(vg, rightX + totalLW2, rY, totalCost2 .. " G", nil)
            rY = rY + lineH
            -- 神炼增韧剂（图标 + 全名 + 数量）
            local toughIconSz = math.max(14, bodyFs * 1.2)
            local toughIconPad = 1
            local toughTpl = GS.ITEM_TEMPLATES and GS.ITEM_TEMPLATES["divine_toughness_agent"]
            local toughIconPath = toughTpl and toughTpl.icon or "image/item_divine_toughness.png"
            local toughImg = ImageManager.lazyGet("item", toughIconPath)
            if toughImg and toughImg ~= -1 then
                local iy = rY
                nvgBeginPath(vg)
                nvgRoundedRect(vg, rightX, iy, toughIconSz, toughIconSz, 2)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                local ip2 = nvgImagePattern(vg, rightX + toughIconPad, iy + toughIconPad, toughIconSz - toughIconPad * 2, toughIconSz - toughIconPad * 2, 0, toughImg, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, rightX + toughIconPad, iy + toughIconPad, toughIconSz - toughIconPad * 2, toughIconSz - toughIconPad * 2, 2)
                nvgFillPaint(vg, ip2)
                nvgFill(vg)
            end
            local toughTextX = rightX + toughIconSz + 4
            local toughTextY = rY + toughIconSz / 2
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, toughTextX, toughTextY, "神炼增韧剂 ", nil)
            local toughNameW = nvgTextBounds(vg, 0, 0, "神炼增韧剂 ", nil)
            nvgFillColor(vg, toughAgentCount >= 1 and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgText(vg, toughTextX + toughNameW, toughTextY, tostring(toughAgentCount), nil)
            local cntW2 = nvgTextBounds(vg, 0, 0, tostring(toughAgentCount), nil)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
            nvgText(vg, toughTextX + toughNameW + cntW2, toughTextY, "/1", nil)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            rY = rY + math.max(lineH, toughIconSz + 2) + 6

            -- 韧性修复按钮
            local btnW2 = math.min(rightW, 100)
            local btnH2 = math.max(22, lineH * 1.4)
            local btnX2 = rightX + (rightW - btnW2) / 2
            local btnY2 = rY

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX2, btnY2, btnW2, btnH2, 4)
            nvgFillColor(vg, canAfford2 and nvgRGBA(60, 120, 40, 230) or nvgRGBA(160, 160, 160, 150))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX2 + 0.5, btnY2 + 0.5, btnW2 - 1, btnH2 - 1, 4)
            nvgStrokeColor(vg, canAfford2 and nvgRGBA(100, 180, 60, 220) or nvgRGBA(160, 160, 160, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(11, btnH2 * 0.5))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, canAfford2 and nvgRGBA(220, 240, 200, 255) or nvgRGBA(180, 120, 120, 180))
            nvgText(vg, btnX2 + btnW2 / 2, btnY2 + btnH2 / 2, "韧性修复", nil)

            GS.toughnessBtnRect = { x = btnX2, y = btnY2, w = btnW2, h = btnH2 }
        else
            GS.toughnessBtnRect = nil
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(80, 140, 60, 180))
            nvgText(vg, rightX + rightW / 2, rY, "韧性已满", nil)
        end

    else
        -- 未放入装备
        GS.repairBtnRect = nil
        GS.toughnessBtnRect = nil
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 180))
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
            "从装备栏或背包拖入装备到上方格子", nil)
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.6,
            "即可进行修复", nil)
    end

    -- ============ 修复结果消息 ============
    if GS.repairResult and GS.repairResult.timer and GS.repairResult.timer > 0 then
        local res = GS.repairResult
        local alpha = math.min(1, res.timer / 0.3)
        local msgFs = math.max(12, panelH * 0.04)
        local msgY = panelY + panelH - innerPad - 14
        local msgColor
        if res.success then
            msgColor = {50, 200, 80}
        else
            msgColor = {200, 60, 40}
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgTw = nvgTextBounds(vg, 0, 0, res.msg or "", nil)
        local msgBgW = msgTw + 20
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end
end

-- ====================================================================
-- 装备精炼面板渲染（独立面板）
-- ====================================================================
function M.drawRefinePanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 羊皮纸底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 装备精炼 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local innerPad = p.innerPad
    local contentY = p.contentY
    local contentH = p.contentH
    GS.refineCloseRect = p.closeRect

    -- ============ 上方：单放置槽（居中） ============
    local slotSize = math.min(math.floor(panelW * 0.22), math.floor(contentH * 0.25))
    local slotX = panelX + (panelW - slotSize) / 2
    local slotY = contentY + 8
    local slotR = math.max(3, math.floor(slotSize * 0.08))

    GS.refineDropRect = { x = slotX, y = slotY, w = slotSize, h = slotSize }

    local item = GS.refineSlotItem

    -- 外框描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX - 1, slotY - 1, slotSize + 2, slotSize + 2, slotR + 1)
    nvgStrokeColor(vg, nvgRGBA(130, 100, 50, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内凹底色
    local slotGrad = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + slotSize,
        nvgRGBA(25, 20, 15, 240), nvgRGBA(50, 40, 28, 240))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, slotSize, slotR)
    nvgFillPaint(vg, slotGrad)
    nvgFill(vg)

    -- 上边内阴影
    local shadowH = math.max(2, math.floor(slotSize * 0.2))
    local topShadow = nvgLinearGradient(vg, slotX, slotY, slotX, slotY + shadowH,
        nvgRGBA(0, 0, 0, 120), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, slotX, slotY, slotSize, shadowH, slotR)
    nvgFillPaint(vg, topShadow)
    nvgFill(vg)

    -- 底部微光
    nvgBeginPath(vg)
    nvgMoveTo(vg, slotX + slotR, slotY + slotSize - 1)
    nvgLineTo(vg, slotX + slotSize - slotR, slotY + slotSize - 1)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    if item then
        -- 有物品：显示图标
        local tpl = GS.itemTemplates[item.templateId]
        local imgHandle = tpl and tpl.icon and ImageManager.lazyGet("item", tpl.icon)
        if imgHandle and imgHandle ~= -1 then
            local pad = 3
            local iconPat = nvgImagePattern(vg,
                slotX + pad, slotY + pad,
                slotSize - pad * 2, slotSize - pad * 2,
                0, imgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + pad, slotY + pad, slotSize - pad * 2, slotSize - pad * 2, slotR)
            nvgFillPaint(vg, iconPat)
            nvgFill(vg)
        end

        -- 稀有度边框
        if tpl then
            local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
            local rc = rd.border
            nvgBeginPath(vg)
            nvgRoundedRect(vg, slotX + 1, slotY + 1, slotSize - 2, slotSize - 2, slotR)
            nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 物品装饰（精炼/附魔/强化等级/锁定/收藏，与背包栏一致）
        drawItemDecorations(vg, item, slotX, slotY, slotSize)

        -- 装备名称（槽下方）
        local nameFs = math.max(9, math.floor(slotSize * 0.22))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, nameFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local rd = tpl and GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize + 3, (item.name or ""):gsub(" %+%d+$", ""), nil)
    else
        -- 空槽位：提示文字
        nvgFontFace(vg, "sans")
        local hintFs = math.max(9, math.floor(slotSize * 0.18))
        nvgFontSize(vg, hintFs)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 - hintFs * 0.3, "拖入", nil)
        nvgText(vg, slotX + slotSize / 2, slotY + slotSize / 2 + hintFs * 0.7, "装备", nil)
    end

    -- ============ 分隔线 ============
    local nameAreaH = math.max(14, math.floor(slotSize * 0.22)) + 6
    local sepY = slotY + slotSize + nameAreaH
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + 12, sepY)
    nvgLineTo(vg, panelX + panelW - 12, sepY)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 130))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 下方：精炼槽详情 ============
    local detailAreaX = panelX + innerPad
    local detailAreaY = sepY + 6
    local detailAreaW = panelW - innerPad * 2
    local detailAreaH = panelY + panelH - innerPad - detailAreaY

    local lineH = math.max(14, detailAreaH * 0.08)
    local titleFs = math.max(11, lineH * 0.9)
    local bodyFs = math.max(9, lineH * 0.78)

    -- 重置按钮区域
    GS.refineSlotBtnRects = {}
    GS.refineDrillBtnRect = nil

    if item then
        local refineSlots = item.refineSlots
        if refineSlots and #refineSlots > 0 then
            local curY = detailAreaY + 2

            -- 统计已填充槽
            local filledCount = 0
            for _, rslot in ipairs(refineSlots) do
                if rslot.attr then filledCount = filledCount + 1 end
            end

            -- 标题行：精炼槽X/Y + 精炼石信息（右侧）
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local itemTier = GS.getItemTier(item)
            local maxRefSlots = GS.getMaxRefineSlots(itemTier)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
            local rtSlotTitle2 = "精炼槽" .. #refineSlots .. "/" .. maxRefSlots
            nvgText(vg, detailAreaX, curY, rtSlotTitle2, nil)

            -- 剩余韧性（紧跟标题行右侧）
            do
                local rtItem2 = GS.refineSlotItem
                if rtItem2 then
                    GS.ensureRefineToughness(rtItem2)
                    local rtCur2 = rtItem2.refineToughness or 0
                    local rtMax2 = GS.getMaxRefineToughness(rtItem2)
                    local rtTitleW2 = nvgTextBounds(vg, 0, 0, rtSlotTitle2, nil)
                    local rtGap2 = 8
                    local rtLbl2 = "剩余韧性:"
                    local rtLblW2 = nvgTextBounds(vg, 0, 0, rtLbl2, nil)
                    local rtCurS2 = tostring(rtCur2)
                    local rtDivS2 = "/" .. tostring(rtMax2)
                    local rtCurW2 = nvgTextBounds(vg, 0, 0, rtCurS2, nil)
                    local rtX2 = detailAreaX + rtTitleW2 + rtGap2
                    nvgFillColor(vg, nvgRGBA(200, 200, 200, 230))
                    nvgText(vg, rtX2, curY, rtLbl2, nil)
                    if rtCur2 >= rtMax2 then
                        nvgFillColor(vg, nvgRGBA(50, 180, 50, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(210, 50, 50, 255))
                    end
                    nvgText(vg, rtX2 + rtLblW2, curY, rtCurS2, nil)
                    nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
                    nvgText(vg, rtX2 + rtLblW2 + rtCurW2, curY, rtDivS2, nil)
                end
            end

            -- 精炼石信息（标题行右侧：图标 + 稀有度颜色名称 + 持有/消耗数量）
            local refItem = GS.refineSlotItem
            -- 显示实际将消耗的精炼石（优先低阶），无库存时回退到所需阶数
            local actualTier = refItem and GS.findAvailableStoneTier(refItem)
            local stoneTier = actualTier or (refItem and GS.getRequiredStoneTier(refItem) or 2)
            local stoneId = "refine_stone_" .. stoneTier
            -- 显示当前预备消耗阶数的持有数量
            local stoneCount = refItem and GS.countInventoryItem(stoneId) or 0
            local stoneTpl = GS.itemTemplates[stoneId]
            local stoneName = stoneTpl and stoneTpl.name or (stoneTier .. "阶精炼石")

            -- 精炼石稀有度颜色
            local stoneRarity = stoneTpl and stoneTpl.rarity or "common"
            local stoneRc = GS.RARITY[stoneRarity] and GS.RARITY[stoneRarity].color or {60, 40, 15}

            -- 从右向左布局：消耗数量"/1" + 持有数量 + 名称 + 图标
            nvgFontSize(vg, bodyFs)
            local rightEdge = detailAreaX + detailAreaW
            local consumeStr = "/1"
            local consumeW = nvgTextBounds(vg, 0, 0, consumeStr, nil)
            local countStr = tostring(stoneCount)
            local countW = nvgTextBounds(vg, 0, 0, countStr, nil)
            local nameW = nvgTextBounds(vg, 0, 0, stoneName, nil)
            local slashW = nvgTextBounds(vg, 0, 0, " ", nil)
            local stoneIconSize = math.max(12, bodyFs)
            local stoneIconY = curY + (bodyFs - stoneIconSize) / 2

            -- 绘制消耗数量 "/1" 白色
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
            nvgText(vg, rightEdge, curY, consumeStr, nil)

            -- 绘制持有数量（满足绿色，不满足红色）
            local heldColor = stoneCount >= 1 and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, heldColor)
            nvgText(vg, rightEdge - consumeW, curY, countStr, nil)

            -- 绘制精炼石名称（稀有度颜色）
            local nameX = rightEdge - consumeW - countW - 4
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(stoneRc[1], stoneRc[2], stoneRc[3], 255))
            nvgText(vg, nameX, curY, stoneName, nil)

            -- 精炼石图标（名称左侧）
            local stoneIconX = nameX - nameW - stoneIconSize - 2
            local stoneImgHandle = stoneTpl and stoneTpl.icon and ImageManager.lazyGet("item", stoneTpl.icon)
            if stoneImgHandle and stoneImgHandle ~= -1 then
                local stoneIconPat = nvgImagePattern(vg, stoneIconX, stoneIconY, stoneIconSize, stoneIconSize, 0, stoneImgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, stoneIconX, stoneIconY, stoneIconSize, stoneIconSize, 2)
                nvgFillPaint(vg, stoneIconPat)
                nvgFill(vg)
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, stoneIconX, stoneIconY, stoneIconSize, stoneIconSize, 2)
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 200))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            curY = curY + lineH

            -- 燃料费(左) + 加工费(中) + 总费用(右)，数字金色
            local refineFuel, refineProc = GS.getRefineCostBreakdown(refItem)
            local refineTotal = refineFuel + refineProc
            local costColor = nvgRGBA(180, 140, 40, 255)
            nvgFontSize(vg, bodyFs)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, detailAreaX, curY, "燃料费: ", nil)
            local fuelLabelW = nvgTextBounds(vg, 0, 0, "燃料费: ", nil)
            nvgFillColor(vg, costColor)
            nvgText(vg, detailAreaX + fuelLabelW, curY, refineFuel .. " G", nil)

            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            local procLabel = "加工费: "
            local procLabelW = nvgTextBounds(vg, 0, 0, procLabel, nil)
            local procValStr = refineProc .. " G"
            local procValW = nvgTextBounds(vg, 0, 0, procValStr, nil)
            local procTotalW = procLabelW + procValW
            local procMidX = detailAreaX + detailAreaW / 2
            local procStartX = procMidX - procTotalW / 2
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgText(vg, procStartX, curY, procLabel, nil)
            nvgFillColor(vg, costColor)
            nvgText(vg, procStartX + procLabelW, curY, procValStr, nil)

            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            local totalLabel = "总费用: "
            local totalLabelW = nvgTextBounds(vg, 0, 0, totalLabel, nil)
            local totalValStr = refineTotal .. " G"
            nvgText(vg, detailAreaX + detailAreaW - nvgTextBounds(vg, 0, 0, totalValStr, nil), curY, totalLabel, nil)
            nvgFillColor(vg, GS.gold >= refineTotal and nvgRGBA(60, 180, 60, 255) or nvgRGBA(200, 60, 40, 255))
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgText(vg, detailAreaX + detailAreaW, curY, totalValStr, nil)
            curY = curY + lineH

            -- 分隔细线
            nvgBeginPath(vg)
            nvgMoveTo(vg, detailAreaX, curY)
            nvgLineTo(vg, detailAreaX + detailAreaW, curY)
            nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 80))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
            curY = curY + 4

            -- 逐行显示每个精炼槽
            local canAfford = GS.gold >= GS.getRefineCost(refItem) and stoneCount > 0
            local btnW = math.max(48, detailAreaW * 0.28)
            local btnH = math.max(20, lineH * 1.3)
            GS.refineLockBtnRects = GS.refineLockBtnRects or {}
            for ci = 1, #refineSlots do GS.refineLockBtnRects[ci] = nil end

            for i, rslot in ipairs(refineSlots) do
                local rowY = curY
                local isFilled = rslot.attr ~= nil

                -- 深灰色内容底板
                nvgBeginPath(vg)
                nvgRoundedRect(vg, detailAreaX, rowY, detailAreaW, btnH, 3)
                nvgFillColor(vg, nvgRGBA(30, 30, 30, 220))
                nvgFill(vg)

                if isFilled then
                    local isLocked = rslot.locked == true
                    -- 已填充：锁定按钮 + 菱形标记 + 词缀名 + 数值 + 重铸按钮
                    local lockSz = math.max(12, btnH * 0.55)
                    local lockX = detailAreaX + 2
                    local lockY = rowY + (btnH - lockSz) / 2
                    local lockImg = isLocked and Renderer.lockClosedImg or Renderer.lockOpenImg
                    if lockImg and lockImg > 0 then
                        local lockPat = nvgImagePattern(vg, lockX, lockY, lockSz, lockSz, 0, lockImg, isLocked and 1.0 or 0.5)
                        nvgBeginPath(vg)
                        nvgRect(vg, lockX, lockY, lockSz, lockSz)
                        nvgFillPaint(vg, lockPat)
                        nvgFill(vg)
                    end
                    GS.refineLockBtnRects[i] = { x = lockX, y = lockY, w = lockSz, h = lockSz }

                    local diamR = bodyFs * 0.3
                    local diamCx = lockX + lockSz + 4 + diamR
                    local diamCy = rowY + btnH / 2

                    -- 稀有度颜色（与全局统一）
                    local rt = rslot.rolledTier or 0
                    local rr = (rt <= 1 and "common") or (rt <= 3 and "uncommon") or (rt <= 5 and "rare") or (rt <= 7 and "fine") or "superior"
                    local rc = GS.RARITY[rr] and GS.RARITY[rr].color or {200,200,200}

                    -- 实心菱形（带阴影和高光）
                    -- 阴影（向右下偏移）
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, diamCx + 1, diamCy - diamR + 1)
                    nvgLineTo(vg, diamCx + diamR + 1, diamCy + 1)
                    nvgLineTo(vg, diamCx + 1, diamCy + diamR + 1)
                    nvgLineTo(vg, diamCx - diamR + 1, diamCy + 1)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
                    nvgFill(vg)
                    -- 主体填充
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, diamCx, diamCy - diamR)
                    nvgLineTo(vg, diamCx + diamR, diamCy)
                    nvgLineTo(vg, diamCx, diamCy + diamR)
                    nvgLineTo(vg, diamCx - diamR, diamCy)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 220))
                    nvgFill(vg)
                    -- 高光（上半部分三角）
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, diamCx, diamCy - diamR)
                    nvgLineTo(vg, diamCx + diamR, diamCy)
                    nvgLineTo(vg, diamCx - diamR, diamCy)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
                    nvgFill(vg)
                    -- 描边
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, diamCx, diamCy - diamR)
                    nvgLineTo(vg, diamCx + diamR, diamCy)
                    nvgLineTo(vg, diamCx, diamCy + diamR)
                    nvgLineTo(vg, diamCx - diamR, diamCy)
                    nvgClosePath(vg)
                    nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1] + 50), math.min(255, rc[2] + 50), math.min(255, rc[3] + 50), 255))
                    nvgStrokeWidth(vg, 0.8)
                    nvgStroke(vg)

                    -- 词缀文本（稀有度颜色）
                    local textX = diamCx + diamR + 6
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, bodyFs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
                    local valStr = rslot.name .. " +" .. rslot.value .. (rslot.suffix or "")
                    nvgText(vg, textX, diamCy, valStr, nil)

                    -- 重铸按钮（锁定时灰色不可按）
                    local rBtnX = detailAreaX + detailAreaW - btnW
                    local rBtnY = rowY
                    local canReforge = canAfford and not isLocked

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, rBtnX, rBtnY, btnW, btnH, 3)
                    if canReforge then
                        nvgFillColor(vg, nvgRGBA(140, 100, 20, 220))
                    else
                        nvgFillColor(vg, nvgRGBA(160, 160, 160, 140))
                    end
                    nvgFill(vg)

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, rBtnX + 0.5, rBtnY + 0.5, btnW - 1, btnH - 1, 3)
                    if canReforge then
                        nvgStrokeColor(vg, nvgRGBA(200, 160, 40, 200))
                    else
                        nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 80))
                    end
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    nvgFontSize(vg, math.max(9, btnH * 0.5))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    if canReforge then
                        nvgFillColor(vg, nvgRGBA(255, 230, 160, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(130, 110, 80, 140))
                    end
                    nvgText(vg, rBtnX + btnW / 2, rBtnY + btnH / 2, "重铸", nil)

                    -- T级文本（重铸按钮左侧，右对齐）
                    nvgFontSize(vg, math.max(9, bodyFs * 0.85))
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                    nvgText(vg, rBtnX - 4, diamCy, "T" .. rt, nil)

                    if canReforge then
                        GS.refineSlotBtnRects[i] = { x = rBtnX, y = rBtnY, w = btnW, h = btnH }
                    end
                else
                    -- 空槽：空心菱形 + "空槽" + 精炼按钮
                    local diamR = bodyFs * 0.3
                    local diamCx = detailAreaX + diamR + 2
                    local diamCy = rowY + btnH / 2

                    nvgBeginPath(vg)
                    nvgMoveTo(vg, diamCx, diamCy - diamR)
                    nvgLineTo(vg, diamCx + diamR, diamCy)
                    nvgLineTo(vg, diamCx, diamCy + diamR)
                    nvgLineTo(vg, diamCx - diamR, diamCy)
                    nvgClosePath(vg)
                    nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 150))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    local textX = diamCx + diamR + 6
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, bodyFs)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(160, 160, 160, 160))
                    nvgText(vg, textX, diamCy, "空槽", nil)

                    -- 精炼按钮
                    local rBtnX = detailAreaX + detailAreaW - btnW
                    local rBtnY = rowY

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, rBtnX, rBtnY, btnW, btnH, 3)
                    if canAfford then
                        nvgFillColor(vg, nvgRGBA(60, 120, 40, 220))
                    else
                        nvgFillColor(vg, nvgRGBA(160, 160, 160, 140))
                    end
                    nvgFill(vg)

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, rBtnX + 0.5, rBtnY + 0.5, btnW - 1, btnH - 1, 3)
                    if canAfford then
                        nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 200))
                    else
                        nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 80))
                    end
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    nvgFontSize(vg, math.max(9, btnH * 0.5))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    if canAfford then
                        nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(130, 110, 80, 140))
                    end
                    nvgText(vg, rBtnX + btnW / 2, rBtnY + btnH / 2, "精炼", nil)

                    if canAfford then
                        GS.refineSlotBtnRects[i] = { x = rBtnX, y = rBtnY, w = btnW, h = btnH }
                    end
                end

                curY = curY + btnH + 4
            end

            -- 开槽按钮（精炼槽未达上限时显示）
            do
                local tier = GS.getItemTier(item)
                local maxSlots = GS.getMaxRefineSlots(tier)
                if #refineSlots < maxSlots then
                    curY = curY + 4
                    local toolCount = GS.countInventoryItem("refine_slot_tool")
                    local canDrill = toolCount >= 1

                    -- 分隔线
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, detailAreaX, curY)
                    nvgLineTo(vg, detailAreaX + detailAreaW, curY)
                    nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 80))
                    nvgStrokeWidth(vg, 0.5)
                    nvgStroke(vg)
                    curY = curY + 6

                    -- 开槽按钮（自适应宽度）
                    local drillBtnFs = math.max(9, lineH * 0.5)
                    local drillBtnText = "开凿精炼槽（雕刻工具剩余" .. toolCount .. "个）"
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, drillBtnFs)
                    local drillTextW = nvgTextBounds(vg, 0, 0, drillBtnText, nil)
                    local drillBtnPadX = 16
                    local drillBtnW = math.max(80, drillTextW + drillBtnPadX * 2)
                    local drillBtnH = math.max(22, lineH * 1.4)
                    local drillBtnX = detailAreaX + (detailAreaW - drillBtnW) / 2
                    local drillBtnY = curY

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, drillBtnX, drillBtnY, drillBtnW, drillBtnH, 4)
                    if canDrill then
                        nvgFillColor(vg, nvgRGBA(40, 100, 140, 220))
                    else
                        nvgFillColor(vg, nvgRGBA(100, 100, 100, 140))
                    end
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, drillBtnX + 0.5, drillBtnY + 0.5, drillBtnW - 1, drillBtnH - 1, 4)
                    if canDrill then
                        nvgStrokeColor(vg, nvgRGBA(80, 160, 220, 200))
                    else
                        nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 80))
                    end
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    nvgFontSize(vg, drillBtnFs)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    if canDrill then
                        nvgFillColor(vg, nvgRGBA(200, 230, 255, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(130, 110, 80, 140))
                    end
                    nvgText(vg, drillBtnX + drillBtnW / 2, drillBtnY + drillBtnH / 2, drillBtnText, nil)

                    GS.refineDrillBtnRect = { x = drillBtnX, y = drillBtnY, w = drillBtnW, h = drillBtnH }
                    curY = curY + drillBtnH + 4
                end
            end
        else
            -- 没有精炼槽 —— 检查能否用工具开槽
            do
                local tier = GS.getItemTier(item)
                local maxSlots = GS.getMaxRefineSlots(tier)
                if maxSlots > 0 then
                    -- 该T级可以拥有精炼槽，显示开槽功能
                    local curY = detailAreaY + 10
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, math.max(11, detailAreaH * 0.09))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(180, 60, 40, 200))
                    nvgText(vg, detailAreaX + detailAreaW / 2, curY,
                        "该装备没有精炼槽", nil)
                    curY = curY + lineH + 4
                    nvgFontSize(vg, math.max(10, detailAreaH * 0.08))
                    nvgFillColor(vg, nvgRGBA(150, 150, 150, 200))
                    nvgText(vg, detailAreaX + detailAreaW / 2, curY,
                        "可使用雕刻工具开凿一个精炼槽(上限" .. maxSlots .. "槽)", nil)
                    curY = curY + lineH + 10

                    local toolCount = GS.countInventoryItem("refine_slot_tool")
                    local canDrill = toolCount >= 1

                    local drillBtnW = math.max(80, detailAreaW * 0.5)
                    local drillBtnH = math.max(22, lineH * 1.4)
                    local drillBtnX = detailAreaX + (detailAreaW - drillBtnW) / 2
                    local drillBtnY = curY

                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, drillBtnX, drillBtnY, drillBtnW, drillBtnH, 4)
                    if canDrill then
                        nvgFillColor(vg, nvgRGBA(40, 100, 140, 220))
                    else
                        nvgFillColor(vg, nvgRGBA(100, 100, 100, 140))
                    end
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, drillBtnX + 0.5, drillBtnY + 0.5, drillBtnW - 1, drillBtnH - 1, 4)
                    if canDrill then
                        nvgStrokeColor(vg, nvgRGBA(80, 160, 220, 200))
                    else
                        nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 80))
                    end
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

                    nvgFontSize(vg, math.max(9, drillBtnH * 0.5))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    if canDrill then
                        nvgFillColor(vg, nvgRGBA(200, 230, 255, 255))
                    else
                        nvgFillColor(vg, nvgRGBA(130, 110, 80, 140))
                    end
                    nvgText(vg, drillBtnX + drillBtnW / 2, drillBtnY + drillBtnH / 2,
                        "开凿精炼槽 (0/" .. maxSlots .. ")", nil)

                    GS.refineDrillBtnRect = { x = drillBtnX, y = drillBtnY, w = drillBtnW, h = drillBtnH }
                    curY = curY + drillBtnH + 4

                    nvgFontSize(vg, math.max(8, bodyFs * 0.8))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                    local tcol = canDrill and nvgRGBA(160, 200, 240, 200) or nvgRGBA(200, 80, 60, 200)
                    nvgFillColor(vg, tcol)
                    nvgText(vg, detailAreaX + detailAreaW / 2, curY,
                        "雕刻工具持有: " .. toolCount .. "个", nil)
                else
                    -- T级过低，不可能拥有精炼槽
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(180, 60, 40, 200))
                    nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
                        "该装备没有精炼槽", nil)
                    nvgFontSize(vg, math.max(9, detailAreaH * 0.08))
                    nvgFillColor(vg, nvgRGBA(140, 120, 80, 160))
                    nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.55,
                        "(T0装备无法拥有精炼槽)", nil)
                end
            end
        end
    else
        -- 未放入装备
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(11, detailAreaH * 0.1))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 180))
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.4,
            "从装备栏或背包拖入装备到上方格子", nil)
        nvgText(vg, detailAreaX + detailAreaW / 2, detailAreaY + detailAreaH * 0.6,
            "即可进行精炼", nil)
    end

    -- ============ 精炼结果消息 ============
    if GS.refineResult and GS.refineResult.timer and GS.refineResult.timer > 0 then
        local res = GS.refineResult
        local alpha = res.pending and 1 or math.min(1, res.timer / 0.3)
        local msgFs = math.max(12, panelH * 0.04)
        local msgY = panelY + panelH - innerPad - 14
        local msgColor
        if res.pending then
            msgColor = {220, 200, 80}
        elseif res.success then
            msgColor = {50, 200, 80}
        else
            msgColor = {200, 60, 40}
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, msgFs)
        local msgTw = nvgTextBounds(vg, 0, 0, res.msg or "", nil)
        local msgBgW = msgTw + 20
        local msgBgH = msgFs + 10
        local msgBgX = panelX + (panelW - msgBgW) / 2
        local msgBgY2 = msgY - msgBgH / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, msgBgX, msgBgY2, msgBgW, msgBgH, 4)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(msgColor[1], msgColor[2], msgColor[3], math.floor(255 * alpha)))
        nvgText(vg, panelX + panelW / 2, msgY, res.msg or "", nil)
    end
end

--- 检查指定覆盖层是否已注册
---@param overlayType string
---@param id string
---@return boolean
function M.hasImage(overlayType, id)
    local img = M.registry[overlayType] and M.registry[overlayType][id]
    return img ~= nil and img ~= -1
end

-- ====================================================================
-- 城镇建筑按钮定义（比例坐标，相对于覆盖层图片区域）
-- ====================================================================
-- 每个按钮: { rx, ry = 中心点比例坐标(0~1), label = 显示文字 }
M.townBuildings = {
    clearwater = {
        { rx = 0.18, ry = 0.18, label = "铁匠铺", ox = 70, oy = 0 },
        { rx = 0.75, ry = 0.13, label = "冒险者公会" },
        { rx = 0.42, ry = 0.38, label = "布告栏", ox = 35, oy = 0 },
        { rx = 0.82, ry = 0.40, label = "首饰店", ox = 5, oy = 0 },
        { rx = 0.15, ry = 0.62, label = "盔甲铺", ox = 0, oy = -100 },
        { rx = 0.55, ry = 0.65, label = "药剂店", ox = 77, oy = 0 },
        { rx = 0.38, ry = 0.88, label = "酒馆", ox = -30, oy = -95 },
        { rx = 0.42, ry = 0.92, label = "家", ox = 25, oy = -15 },
    },
}

-- 存储当前帧的按钮点击区域
M.buildingBtnRects = {}

-- 子场景按钮点击区域（每帧重建）
M.subSceneBtnRects = {}

-- 建筑内部定义 { [buildingId] = { image, title, buttons } }
--- 获取当前游戏时间的小时数（0~23）
---@return number
function M.getGameHour()
    local totalMin = ((GS.weatherTime or 1) - 1)
    local minuteOfDay = totalMin % 1440
    return minuteOfDay / 60   -- 返回浮点数（如 10.6 表示 10:36）
end

--- 检查建筑是否在营业时间内
---@param buildingKey string
---@return boolean open, table|nil closedInfo
function M.checkBusinessHours(buildingKey)
    local def = M.buildingInteriors[buildingKey]
    if not def or not def.openHour then return true, nil end
    local hour = M.getGameHour()
    local isOpen
    if def.closeHour > def.openHour then
        -- 正常时段（如 7:00-17:00）
        isOpen = (hour >= def.openHour and hour < def.closeHour)
    else
        -- 跨午夜时段（如 12:00-2:00）
        isOpen = (hour >= def.openHour or hour < def.closeHour)
    end
    if isOpen then
        return true, nil
    end
    return false, {
        shopName  = def.shopName or buildingKey,
        openHour  = def.openHour,
        closeHour = def.closeHour,
    }
end

M.buildingInteriors = {
    blacksmith = {
        imageType = "building", imageId = "blacksmith",
        title = "清水镇 - 铁匠铺",
        shopName = "铁匠铺",
        openHour = 7, closeHour = 17,
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "交易", action = "trade" },
            { label = "委托锻造", action = "forge" },
            { label = "委托加工", action = "craft" },
            { label = "离开", action = "exit" },
        },
    },
    potion_shop = {
        imageType = "building", imageId = "potion_shop",
        title = "清水镇 - 药剂店",
        shopName = "药剂店",
        openHour = 9, closeHour = 21,
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "交易", action = "trade" },
            { label = "委托炼金", action = "alchemy" },
            { label = "深渊兑换", action = "abyss_exchange" },
            { label = "离开", action = "exit" },
        },
    },
    jewelry_shop = {
        imageType = "building", imageId = "jewelry_shop",
        title = "清水镇 - 首饰店",
        shopName = "首饰店",
        openHour = 8, closeHour = 18,
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "交易", action = "trade" },
            { label = "委托镶嵌", action = "socket" },
            { label = "离开", action = "exit" },
        },
    },
    armor_shop = {
        imageType = "building", imageId = "armor_shop",
        title = "清水镇 - 盔甲铺",
        shopName = "盔甲铺",
        openHour = 7, closeHour = 17,
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "交易", action = "trade" },
            { label = "离开", action = "exit" },
        },
    },
    tavern = {
        imageType = "building", imageId = "tavern",
        title = "清水镇 - 酒馆",
        shopName = "酒馆",
        openHour = 10.5, closeHour = 2,
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "交易", action = "trade" },
            { label = "委托烹饪", action = "cooking" },
            { label = "望向舞池", action = "dancefloor" },
            { label = "离开", action = "exit" },
        },
        -- 舞池视角：独立按钮集和标题
        dancefloor = {
            title = "清水镇 - 酒馆·舞池",
            buttons = {
                { label = "交谈", action = "talk" },
                { label = "回到前台", action = "dancefloor" },
                { label = "离开", action = "exit" },
            },
        },
    },
    guild = {
        imageType = "building", imageId = "guild",
        title = "清水镇 - 冒险者公会",
        shopName = "冒险者公会",
        openHour = 7, closeHour = 19,
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "找芙蕾雅", action = "guild_office" },
            { label = "\"广告机\"", action = "ad_machine" },
            { label = "遗失物品", action = "lost_items" },
            { label = "离开", action = "exit" },
        },
    },
    bulletin_board = {
        imageType = "building", imageId = "bulletin_board",
        title = "清水镇 - 布告栏",
        buttons = {
            { label = "离开", action = "exit" },
        },
    },
    guild_master_office = {
        imageType = "building", imageId = "guild_master_office",
        title = "冒险者公会 - 会长办公室",
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "回到前台", action = "back_to_guild" },
            { label = "离开", action = "exit" },
        },
    },
    guild_ad_machine = {
        imageType = "building", imageId = "guild_ad_machine",
        title = "冒险者公会 - \"广告机\"",
        buttons = {
            ---@diagnostic disable-next-line: unicode-name, undefined-global
            { label = "观看\u{201c}广告\u{201d}", action = "watch_ad" },
            { label = "兑奖", action = "exchange" },
            { label = "洗点", action = "respec" },
            { label = "返回前台", action = "return_front" },
        },
    },
    forest_elf = {
        imageType = "building", imageId = "forest_elf",
        title = "森林中的精灵",
        buttons = {
            { label = "交谈", action = "talk" },
            { label = "离开", action = "exit" },
        },
    },
}

-- 建筑按钮 label → 内部定义 key 映射
M.buildingLabelMap = {
    ["铁匠铺"] = "blacksmith",
    ["药剂店"] = "potion_shop",
    ["首饰店"] = "jewelry_shop",
    ["盔甲铺"] = "armor_shop",
    ["酒馆"] = "tavern",
    ["布告栏"] = "bulletin_board",
    ["冒险者公会"] = "guild",
}

--- 会长办公室 idle 视频路径
local GUILD_OFFICE_IDLE_SRC = "video/冒险者公会会长办公室-idle.mp4"

--- 酒馆 idle 视频路径
local TAVERN_IDLE_SRC = "video/酒馆-idle.mp4"

--- 酒馆舞女跳舞视频路径（不循环，停在最后一帧）
local TAVERN_DANCE_SRC = "video/酒馆-舞女跳舞.mp4"
--- 酒馆舞女 idle 视频路径（循环播放，对话背景）
local TAVERN_DANCER_IDLE_SRC = "video/酒馆-舞女Idle.mp4"

--- 铁匠铺打铁视频路径（循环播放，有声）
local BLACKSMITH_FORGE_SRC = "video/铁匠铺-打铁.mp4"

--- 首饰店 idle 视频路径（循环播放，静音）
local JEWELRY_IDLE_SRC = "video/首饰店-idle.mp4"

--- 药剂店 idle 视频路径（循环播放，静音）
local POTION_IDLE_SRC = "video/药剂铺-idle.mp4"
--- 药剂店 idle2 视频路径（睹物思人二完成后使用）
local POTION_IDLE2_SRC = "video/药剂铺-idle2.mp4"

--- 盔甲铺 idle 视频路径（循环播放，静音）
local ARMOR_IDLE_SRC = "video/盔甲铺-idle.mp4"

--- 森林精灵 idle 视频路径（循环播放，静音）
local FOREST_ELF_IDLE_SRC = "video/森林中的精灵-idle.mp4"
local FOREST_ELF_LEAVE_SRC = "video/森林中的精灵-离开.mp4"

--- 进入建筑子场景
---@param buildingKey string  如 "blacksmith"
---@param skipDialogue boolean|nil 跳过入场对话（从子场景返回时使用）
---@return boolean
function M.enterSubScene(buildingKey, skipDialogue)
    local def = M.buildingInteriors[buildingKey]
    if not def then return false end

    -- 检查营业时间（从内部子场景跳转时跳过，如广告机→前台）
    if not skipDialogue then
        local open, closedInfo = M.checkBusinessHours(buildingKey)
        if not open then
            M.closedPopup = closedInfo
            M.closedPopupBtnRect = nil
            return false
        end
    end

    local img = M.registry[def.imageType] and M.registry[def.imageType][def.imageId]
    if not img or img == -1 then return false end

    -- 深拷贝按钮列表，防止事件等逻辑修改原始定义
    local btns = {}
    if def.buttons then
        local QM = require("QuestManager")
        local abyssUnlocked = QM.getQuestStatus("side_lina_manor_6") == "completed"
        for _, b in ipairs(def.buttons) do
            -- 深渊兑换按钮：仅在完成"红龙与魔女"任务后显示
            if b.action == "abyss_exchange" and not abyssUnlocked then
                -- 跳过，不加入按钮列表
            else
                btns[#btns + 1] = { label = b.label, action = b.action }
            end
        end
    end
    M.subScene = {
        id = buildingKey,
        imageHandle = img,
        title = def.title,
        buttons = btns,
    }

    -- 从打烊界面进入广告机：替换"返回前台"为"退出"（回清水镇），隐藏右上角X
    if buildingKey == "guild_ad_machine" and GS.adMachineFromClosed then
        for i, b in ipairs(M.subScene.buttons) do
            if b.action == "return_front" then
                b.label = "退出"
                b.action = "exit_to_town"
                break
            end
        end
        M.subScene.hideExitIcon = true  -- 隐藏右上角X按钮
    end

    -- 睹物思人二完成后：切换药剂店背景图
    if buildingKey == "potion_shop" then
        local QM = require("QuestManager")
        local st = QM.questStates["side_lina_manor_5"]
        if st and st.status == QM.STATUS_COMPLETED then
            local img2 = M.registry["building"] and M.registry["building"]["potion_shop_2"]
            if img2 and img2 > 0 then
                M.subScene.imageHandle = img2
            end
        end
    end

    -- 进入公告栏时默认显示第一个委托
    if buildingKey == "bulletin_board" then
        GS.bulletinQuestIndex = 1
    end

    -- 动画开关判断：事件期间（isEvent）的会长办公室不受开关影响
    local wantVideo = GS.animationEnabled or (GS.isEvent and buildingKey == "guild_master_office")

    -- 冒险者公会：延迟加载视频（避免 Load() 同步阻塞导致画面卡死）
    -- 阶段: "intro" → 播放"进入打招呼"(有声,一次) → "idle" → 无缝循环播放idle视频(静音)
    if wantVideo and buildingKey == "guild" and not M._guildVideoPhase then
        -- 首次进入公会：初始化视频状态机
        M._guildVideoPhase = "intro"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        -- 标记需要加载，实际加载延迟到 updateVideo 中执行（让黑屏先渲染出来）
        M._guildVideoPendingLoad = "video/冒险者公会-进入打招呼.mp4"
        M._guildVideoPendingVol = 1.0
        M._guildVideoLoadDelay = 0.05  -- 等几帧后再加载
    end
    -- 如果 _guildVideoPhase 已存在（从广告机返回），视频状态保持不变

    -- 冒险者公会会长办公室：直接循环播放 idle 视频
    if wantVideo and buildingKey == "guild_master_office" and not M._guildVideoPhase then
        M._guildVideoPhase = "idle"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        M._guildVideoPendingLoad = GUILD_OFFICE_IDLE_SRC
        M._guildVideoPendingVol = 0
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true  -- 标记需要循环
    end

    -- 酒馆：直接循环播放 idle 视频（与会长办公室同样做法）
    if wantVideo and buildingKey == "tavern" and not M._guildVideoPhase then
        M._guildVideoPhase = "idle"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        M._guildVideoPendingLoad = TAVERN_IDLE_SRC
        M._guildVideoPendingVol = 0
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true
    end

    -- 铁匠铺：循环播放打铁视频（有声）
    if wantVideo and buildingKey == "blacksmith" and not M._guildVideoPhase then
        M._guildVideoPhase = "idle"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        M._guildVideoPendingLoad = BLACKSMITH_FORGE_SRC
        M._guildVideoPendingVol = 1.0   -- 播放音频
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true
    end

    -- 首饰店：循环播放 idle 视频（静音）
    if wantVideo and buildingKey == "jewelry_shop" and not M._guildVideoPhase then
        M._guildVideoPhase = "idle"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        M._guildVideoPendingLoad = JEWELRY_IDLE_SRC
        M._guildVideoPendingVol = 0     -- 静音
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true
    end

    -- 药剂店：循环播放 idle 视频（静音）
    -- 睹物思人二完成后播放 idle2 视频
    if wantVideo and buildingKey == "potion_shop" and not M._guildVideoPhase then
        local potionIdleSrc = POTION_IDLE_SRC
        do
            local QM = require("QuestManager")
            local st = QM.questStates["side_lina_manor_5"]
            if st and st.status == QM.STATUS_COMPLETED then
                potionIdleSrc = POTION_IDLE2_SRC
            end
        end
        M._guildVideoPhase = "idle"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        M._guildVideoPendingLoad = potionIdleSrc
        M._guildVideoPendingVol = 0
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true
    end

    -- 盔甲铺：循环播放 idle 视频（静音）
    if wantVideo and buildingKey == "armor_shop" and not M._guildVideoPhase then
        M._guildVideoPhase = "idle"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        M._guildVideoPendingLoad = ARMOR_IDLE_SRC
        M._guildVideoPendingVol = 0
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true
    end

    -- 森林精灵：循环播放 idle 视频（静音）
    if wantVideo and buildingKey == "forest_elf" and not M._guildVideoPhase then
        M._guildVideoPhase = "idle"
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        M._guildVideoPlayer = nil
        M._guildVideoPrevPlayer = nil
        M._guildVideoPrevNvgHandle = nil
        M._guildVideoPendingLoad = FOREST_ELF_IDLE_SRC
        M._guildVideoPendingVol = 0
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true
    end

    if not skipDialogue then
        -- 检查是否有可触发的事件（优先于普通对话）
        local eventTriggered = false
        if buildingKey == "guild" then
            local EventInitialSupply = require("Event.Event_InitialSupply")
            if EventInitialSupply.canTrigger() then
                EventInitialSupply.trigger()
                eventTriggered = true
            end
        end

        -- 检查是否有可触发的对话（事件未触发时才检查）
        if not eventTriggered then
            local DialogueManager = require("DialogueManager")
            local dlgId = DialogueManager.checkBuilding(buildingKey)
            if dlgId then
                DialogueManager.start(dlgId)
            end
        end
    end

    -- 从地图进入森林精灵：标记需要在淡入后自动触发问候对话
    M._forestElfGreetPending = (buildingKey == "forest_elf" and GS._forestElfFromMap) or nil

    -- 进入建筑：先全黑遮罩
    M._fadeAlpha = 255
    M._fadeDoneCallback = nil
    if (buildingKey == "guild" or buildingKey == "tavern" or buildingKey == "blacksmith" or buildingKey == "jewelry_shop" or buildingKey == "potion_shop" or buildingKey == "armor_shop" or buildingKey == "forest_elf") and M._guildVideoPendingLoad then
        -- 视频建筑首次进入：保持全黑，等视频加载完成后再淡入
        M._fadeTarget = 255
    else
        -- 其他建筑 / 从广告机返回公会（视频已在播放）：直接开始淡入
        M._fadeTarget = 0
        -- 动画关闭时视频不加载，问候回调需在此处直接设置
        if M._forestElfGreetPending then
            M._forestElfGreetPending = nil
            M._fadeDoneCallback = function()
                local DM = require("DialogueManager")
                local elfName = GS.resolveNPCSpeaker("艾莉雅")
                local favorTexts = {
                    "{玩家}。",
                    "{玩家}，是你。",
                    "{玩家}，你来了。",
                    "{玩家}，嗯，你的生命进展还顺利吗？",
                    "{玩家}，嗯，你看起来生长的态势很好嘛。",
                    "{玩家},其实我不应该担心，但是在自然面前，你要保护好自己。",
                    "{爱称}，看到你的生命在蓬勃生长，我就放心了，请你再多陪我一会儿。",
                }
                local level = GS.getNPCFavorLevel("forest_elf")
                local text = (level == 0) and "{玩家}。" or favorTexts[level]
                DM.startDynamic({
                    { speaker = elfName, text = text },
                })
            end
        end
    end

    return true
end

--- idle 视频路径
local GUILD_IDLE_SRC = "video/冒险者公会-idle.mp4"

--- 双缓冲切换公会视频：保留旧播放器显示最后一帧，新播放器就绪后再替换
---@param src string 视频路径
---@param vol number 音量
---@param loop boolean|nil 是否循环（idle 用 true）
local function guildSwitchVideo(src, vol, loop)
    -- 旧播放器移至 prev（继续显示最后一帧）
    if M._guildVideoPrevPlayer then
        M._guildVideoPrevPlayer:Stop()
    end
    M._guildVideoPrevPlayer = M._guildVideoPlayer
    M._guildVideoPrevNvgHandle = M._guildVideoNvgHandle

    -- 创建新播放器
    M._guildVideoNvgHandle = nil
    M._guildVideoReady = false
    M._guildVideoPlayer = VideoPlayer:new()
    if M._guildVideoPlayer then
        local ok = M._guildVideoPlayer:Load(src, 1920, 1080)
        if ok then
            M._guildVideoPlayer:SetVolume(vol or 0)
            M._guildVideoPlayer:SetLoop(loop or false)
            M._guildVideoPlayer:Play()
        end
    end
end

--- 切换到舞池视角并播放舞女跳舞视频（渐变黑屏过渡，同建筑进出）
function M.startDancefloorVideo()
    if not GS.animationEnabled then return end  -- 动画关闭时跳过视频
    M._guildVideoPhase = "dancer_performing"  -- 立即设置，防止重复点击
    M._dancerPendingReveal = nil  -- 等全黑后再设，避免旧视频 ready 立刻触发揭示
    M._dancerDialogueDone = false
    M._dancerAfterRevealCb = nil
    -- 渐变到黑屏（与进出建筑一致的速度），完成后切换视频
    M._fadeAlpha = M._fadeAlpha or 0
    M._fadeSpeed = 400
    M._fadeTarget = 255
    M._fadeDoneCallback = function()
        M._dancerPendingReveal = true  -- 全黑后设置，此时旧视频已停止
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        if M._guildVideoPlayer then
            if M._guildVideoPrevPlayer then
                M._guildVideoPrevPlayer:Stop()
            end
            M._guildVideoPrevPlayer = M._guildVideoPlayer
            M._guildVideoPrevNvgHandle = M._guildVideoNvgHandle
            M._guildVideoNvgHandle = nil
        end
        M._guildVideoPlayer = nil
        M._guildVideoPendingLoad = TAVERN_DANCE_SRC
        M._guildVideoPendingVol = 0
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = false
    end
end

--- 旁白对话结束回调：标记对话完成，渐变揭示在 updateVideo 每帧检测中处理
---@param afterRevealCallback function|nil 揭示后执行的回调（如开始舞女正常交谈）
function M.onDancerDialogueDone(afterRevealCallback)
    if not GS.animationEnabled then
        -- 动画关闭时无视频流程，直接执行回调
        if afterRevealCallback then afterRevealCallback() end
        return
    end
    M._dancerDialogueDone = true
    M._dancerAfterRevealCb = afterRevealCallback
    -- 实际揭示在 updateVideo 的每帧条件检测中处理（渐变淡入）
end

--- 直接播放舞女 Idle 视频（今日已观赏过，渐变黑屏过渡）
function M.startDancerIdleVideo()
    if not GS.animationEnabled then return end  -- 动画关闭时跳过视频
    M._guildVideoPhase = "dancer_idle"
    M._dancerPendingReveal = nil  -- 等全黑后再设
    -- 渐变到黑屏（与进出建筑一致的速度），完成后切换视频
    M._fadeAlpha = M._fadeAlpha or 0
    M._fadeSpeed = 400
    M._fadeTarget = 255
    M._fadeDoneCallback = function()
        M._dancerPendingReveal = true  -- 全黑后设置
        M._guildVideoReady = false
        M._guildVideoNvgHandle = nil
        if M._guildVideoPlayer then
            if M._guildVideoPrevPlayer then
                M._guildVideoPrevPlayer:Stop()
            end
            M._guildVideoPrevPlayer = M._guildVideoPlayer
            M._guildVideoPrevNvgHandle = M._guildVideoNvgHandle
            M._guildVideoNvgHandle = nil
        end
        M._guildVideoPlayer = nil
        M._guildVideoPendingLoad = TAVERN_DANCER_IDLE_SRC
        M._guildVideoPendingVol = 0
        M._guildVideoLoadDelay = 0.05
        M._guildVideoPendingLoop = true
    end
end

--- 从舞池视角回到前台：渐变黑屏过渡后恢复酒馆 idle 视频
function M.exitDancefloorVideo()
    if not GS.animationEnabled then return end  -- 动画关闭时跳过视频
    M._dancerPendingReveal = nil   -- 等全黑后再设，避免旧视频 ready 立刻触发揭示
    M._dancerDialogueDone = nil
    M._dancerAfterRevealCb = nil
    -- 渐变到黑屏（与其他舞池转场一致的速度），完成后切换视频
    M._fadeAlpha = M._fadeAlpha or 0
    M._fadeSpeed = 400
    M._fadeTarget = 255
    M._fadeDoneCallback = function()
        M._dancerPendingReveal = true   -- 全黑后设置，此时旧视频已停止
        M._guildVideoPhase = "idle"
        guildSwitchVideo(TAVERN_IDLE_SRC, 0, true)
    end
end

--- 森林精灵场景：从 idle 切换到"离开"视频
--- 视频播完 + 对话结束（两者都满足）后才黑屏并执行回调
---@param onDone function 离开视频播完并黑屏后的回调
function M.startForestElfLeaveVideo(onDone)
    if not GS.animationEnabled or not M._guildVideoPlayer then
        -- 动画关闭或没有视频播放器：标记视频已完成，等对话结束后直接回调
        M._forestElfLeaveCb = onDone
        M._forestElfVideoEnded = true
        M._forestElfDialogueDone = false
        return
    end
    M._forestElfLeaveCb = onDone
    M._forestElfVideoEnded = false
    M._forestElfDialogueDone = false
    M._guildVideoPhase = "forest_elf_leaving"
    guildSwitchVideo(FOREST_ELF_LEAVE_SRC, 0, false)  -- 不循环，播一次
end

--- 标记森林精灵对话已结束（由 Input.lua 在旁白对话完成时调用）
function M.notifyForestElfDialogueDone()
    M._forestElfDialogueDone = true
end

--- 更新视频播放器和过渡动画（每帧调用）
---@param dt number
function M.updateVideo(dt)
    dt = dt or 0.016

    -- ── 淡入淡出过渡 ──
    if M._fadeAlpha and M._fadeTarget ~= nil then
        local fadeDt = math.min(dt, 0.05)  -- 限制单帧步长，防止阻塞后大dt导致跳帧
        local speed = M._fadeSpeed or 800  -- alpha/秒，可由各转场函数覆盖
        if M._fadeAlpha < M._fadeTarget then
            M._fadeAlpha = math.min(M._fadeAlpha + speed * fadeDt, M._fadeTarget)
        elseif M._fadeAlpha > M._fadeTarget then
            M._fadeAlpha = math.max(M._fadeAlpha - speed * fadeDt, M._fadeTarget)
        end
        -- 到达目标后执行回调
        if M._fadeAlpha == M._fadeTarget and M._fadeDoneCallback then
            local cb = M._fadeDoneCallback
            M._fadeDoneCallback = nil
            cb()
        end
    end

    -- ── 公会视频：延迟加载 ──
    if M._guildVideoLoadDelay then
        M._guildVideoLoadDelay = M._guildVideoLoadDelay - dt
        if M._guildVideoLoadDelay <= 0 then
            M._guildVideoLoadDelay = nil
            local src = M._guildVideoPendingLoad
            local vol = M._guildVideoPendingVol or 0
            M._guildVideoPendingLoad = nil
            M._guildVideoPendingVol = nil
            local pendingLoop = M._guildVideoPendingLoop or false
            M._guildVideoPendingLoop = nil
            if src and VideoPlayer then
                M._guildVideoPlayer = VideoPlayer:new()
                if M._guildVideoPlayer then
                    local ok = M._guildVideoPlayer:Load(src, 1920, 1080)
                    if ok then
                        M._guildVideoPlayer:SetVolume(vol)
                        M._guildVideoPlayer:SetLoop(pendingLoop)
                        M._guildVideoPlayer:Play()
                    else
                        log:Write(LOG_WARNING, "[BoardOverlay] Guild video Load failed: " .. src)
                        M._guildVideoPlayer = nil
                    end
                end
            end
            -- 视频加载完成（无论成功失败）
            if M._dancerPendingReveal then
                -- 舞池视频：等 IsReady() 后再渐变揭示（在下方每帧检测中处理）
            elseif M._guildVideoPhase == "dancer_transition" then
                -- dancer_transition：等视频就绪 + 对话完成后再揭示
            else
                -- 公会等：渐变淡入
                M._fadeTarget = 0
                -- 森林精灵从地图进入：淡入完成后自动触发问候对话
                if M._forestElfGreetPending then
                    M._forestElfGreetPending = nil
                    M._fadeDoneCallback = function()
                        local DM = require("DialogueManager")
                        local elfName = GS.resolveNPCSpeaker("艾莉雅")
                        local favorTexts = {
                            "{玩家}。",
                            "{玩家}，是你。",
                            "{玩家}，你来了。",
                            "{玩家}，嗯，你的生命进展还顺利吗？",
                            "{玩家}，嗯，你看起来生长的态势很好嘛。",
                            "{玩家},其实我不应该担心，但是在自然面前，你要保护好自己。",
                            "{爱称}，看到你的生命在蓬勃生长，我就放心了，请你再多陪我一会儿。",
                        }
                        local level = GS.getNPCFavorLevel("forest_elf")
                        local text = (level == 0) and "{玩家}。" or favorTexts[level]
                        DM.startDynamic({
                            { speaker = elfName, text = text },
                        })
                    end
                end
            end
        end
    end

    -- 森林精灵：视频+对话都结束后执行场景切换
    -- 必须在视频播放器检查之前：动画关闭时无播放器，下方会 early return
    if M._forestElfVideoEnded and M._forestElfDialogueDone and M._forestElfLeaveCb then
        if M._fadeAlpha and M._fadeAlpha >= 255 then
            -- 已黑屏 → 直接执行场景切换（保持黑屏状态）
            -- 不调用 hide()，避免黑屏→亮→又黑的闪烁；doSceneSwitch 内部的
            -- startSceneTransition 回调会在全黑阶段调用 BoardOverlay.hide() 完成清理
            local cb = M._forestElfLeaveCb
            M._forestElfLeaveCb = nil
            M._forestElfVideoEnded = nil
            M._forestElfDialogueDone = nil
            if M._guildVideoPlayer then M._guildVideoPlayer:Stop(); M._guildVideoPlayer = nil end
            if M._guildVideoPrevPlayer then M._guildVideoPrevPlayer:Stop(); M._guildVideoPrevPlayer = nil end
            M._guildVideoPhase = nil
            cb()
            return
        else
            -- 动画关闭时无离开视频，对话结束后需手动触发黑屏过渡
            M._fadeTarget = 255
        end
    end

    -- ── 公会视频 ──
    -- dancer_transition：对话完成后才启动 idle 视频（避免原生视频层覆盖 NanoVG 对话框）
    if M._guildVideoPhase == "dancer_transition" and M._dancerTransitionPending and M._dancerDialogueDone then
        M._dancerTransitionPending = nil
        guildSwitchVideo(TAVERN_DANCER_IDLE_SRC, 0, true)
    end
    if not M._guildVideoPlayer then return end
    M._guildVideoPlayer:Update()
    if M._guildVideoPrevPlayer then
        M._guildVideoPrevPlayer:Update()
    end

    -- 新视频就绪 → 销毁 prev
    if not M._guildVideoReady and M._guildVideoPlayer:IsReady() then
        M._guildVideoReady = true
        if M._guildVideoPrevPlayer then
            M._guildVideoPrevPlayer:Stop()
            M._guildVideoPrevPlayer = nil
        end
        M._guildVideoPrevNvgHandle = nil
    end

    -- ── 舞池视频渐变揭示（每帧条件检测） ──
    -- 简单场景：视频就绪 → 渐变淡入
    if M._dancerPendingReveal and M._guildVideoReady then
        M._dancerPendingReveal = nil
        M._fadeTarget = 0
        -- 视频就绪后恢复按钮显示
        if M._guildVideoPhase == "dancer_idle" then
            GS.dancerShowPhase = "done"
            -- 揭示完成后触发回调（如延迟对话）
            if M._dancerAfterRevealCb then
                local cb = M._dancerAfterRevealCb
                M._dancerAfterRevealCb = nil
                M._dancerDialogueDone = nil
                cb()
            end
        elseif M._guildVideoPhase == "idle" and GS.dancerShowPhase == "performing" then
            -- 回到前台：清除舞池状态
            GS.dancerShowPhase = nil
        end
    end
    -- dancer_transition：视频就绪 + 对话结束 → 渐变淡入 + 回调
    if M._guildVideoPhase == "dancer_transition" and M._guildVideoReady and M._dancerDialogueDone then
        M._guildVideoPhase = "dancer_idle"
        M._fadeTarget = 0
        M._dancerDialogueDone = nil
        if M._dancerAfterRevealCb then
            local cb = M._dancerAfterRevealCb
            M._dancerAfterRevealCb = nil
            -- 仅在没有其他对话进行时才执行回调（防止覆盖用户已发起的交谈）
            local DM = require("DialogueManager")
            if not DM.active then
                cb()
            end
        end
    end

    -- 视频播放结束 → 状态切换
    local state = M._guildVideoPlayer:GetState()
    if state == VIDEO_ENDED and M._guildVideoPhase == "intro" then
        -- intro 结束 → 无缝切换到 idle 视频，SetLoop=true 循环播放
        M._guildVideoPhase = "idle"
        guildSwitchVideo(GUILD_IDLE_SRC, 0, true)
    elseif state == VIDEO_ENDED and M._guildVideoPhase == "dancer_performing" then
        -- 舞女跳舞视频播完 → 渐变到黑屏，完成后停止舞蹈视频并等待对话结束
        M._fadeTarget = 255
        M._fadeDoneCallback = function()
            M._guildVideoPhase = "dancer_transition"
            -- 停止舞蹈视频，避免原生视频层持续渲染遮挡 NanoVG 对话框
            if M._guildVideoPlayer then
                M._guildVideoPlayer:Stop()
                M._guildVideoPlayer = nil
            end
            if M._guildVideoPrevPlayer then
                M._guildVideoPrevPlayer:Stop()
                M._guildVideoPrevPlayer = nil
            end
            M._guildVideoReady = false
            M._guildVideoNvgHandle = nil
            M._guildVideoPrevNvgHandle = nil
            -- 标记待加载：等 _dancerDialogueDone 后再启动 idle 视频
            M._dancerTransitionPending = true
        end
    elseif state == VIDEO_ENDED and M._guildVideoPhase == "forest_elf_leaving" then
        -- 森林精灵离开视频播完 → 立即黑屏，不停留在最后一帧
        M._forestElfVideoEnded = true
        M._fadeTarget = 255
    end

end

--- 实际执行退出清理（内部调用）
local function doExitSubScene()
    -- 销毁公会视频播放器，重置状态机（复用统一清理函数）
    M.cleanupVideoState()
    M.subScene = nil
    -- 清除打烊广告机标记
    GS.adMachineFromClosed = false
    -- 清除布告栏残留的点击区域，避免在其他建筑中误触发
    GS.bulletinQuestBtnRect = nil
    GS.bulletinQuestRerollBtnRect = nil
    GS.bulletinArrowLeftRect = nil
    GS.bulletinArrowRightRect = nil
    -- 关闭所有可能打开的界面/面板（防止退出子场景后残留）
    if GS.exchangeMode then GS.exitExchangeMode() end
    if GS.abyssExchangeMode then GS.exitAbyssExchangeMode() end
    if GS.warehouseMode then GS.exitWarehouseMode() end
    if GS.lostItemsMode then GS.exitLostItemsMode() end
    GS.shopMode = false
    GS.enhanceMode = false
    GS.repairMode = false
    GS.forgeMode = false
    GS.homeForgeMode = false
    GS.alchemyMode = false
    GS.homeAlchemyMode = false
    GS.cookingMode = false
    GS.homeCookingMode = false
    GS.homeSmithySelectMode = false
    GS.homeSmithySelectRects = nil
    GS.homeCraftMode = false
    GS.homeEnchantMode = false
    GS.enchantMode = false
    GS.enchantSlotItem = nil
    GS.enchantSlotSource = nil
    GS.enchantSlotSourceId = nil
    GS.enchantResult = nil
    GS.homeSocketMode = false
    GS.refineMode = false
    GS.craftMode = false
    GS.socketMode = false
    GS.cancelGift()
    GS.cancelQuestSubmit()
    -- 关闭对话界面（退出建筑时必须彻底清理，阻止 finish() 内的回调链触发新对话）
    local DM = require("DialogueManager")
    if DM.active then
        DM._dynamicOnComplete = nil  -- 先清除回调，防止 finish() 触发 startQA → startDynamic 链
        DM.finish()
    end

    -- 退出后：从黑屏淡入城镇
    M._fadeAlpha = 255
    M._fadeTarget = 0
    M._fadeDoneCallback = nil
end

--- 退出建筑子场景（带黑屏过渡）
function M.exitSubScene()
    -- 如果正在淡出中则忽略重复调用
    if M._fadeTarget == 255 then return end
    -- 先淡出到黑屏，完成后再执行实际退出
    M._fadeAlpha = M._fadeAlpha or 0
    M._fadeTarget = 255
    M._fadeDoneCallback = doExitSubScene
end

--- 从广告机返回公会前台（保持视频状态不变）
function M.returnToGuildFront()
    local def = M.buildingInteriors["guild"]
    if not def then return end
    local img = M.registry[def.imageType] and M.registry[def.imageType][def.imageId]
    local btns = {}
    if def.buttons then
        for i, b in ipairs(def.buttons) do
            btns[i] = { label = b.label, action = b.action }
        end
    end
    M.subScene = {
        id = "guild",
        imageHandle = img,
        title = def.title,
        buttons = btns,
    }
    -- 视频状态保持不变（_guildVideoPhase, _guildVideoPlayer 等都不动）
    -- 淡入
    M._fadeAlpha = 255
    M._fadeTarget = 0
    M._fadeDoneCallback = nil

    -- 回到公会前台时检查事件触发（与 enterSubScene 中的逻辑一致）
    local EventInitialSupply = require("Event.Event_InitialSupply")
    if EventInitialSupply.canTrigger() then
        EventInitialSupply.trigger()
    end
end

--- 是否在子场景中
---@return boolean
function M.inSubScene()
    return M.subScene ~= nil
end

-- ====================================================================
-- 绘制
-- ====================================================================

--- 绘制覆盖层（在棋盘位置上方）
---@param vg userdata NanoVG 上下文
function M.draw(vg)
    if not M.active or not M.imageHandle then return end

    local boardSize = GS.CELL * GS.BOARD_SIZE
    local bx = GS.BOARD_X
    local by = GS.BOARD_Y
    local border = 4
    local cr = 6

    -- 决定显示的图片：子场景优先，城镇根据时间切换
    local displayImg = M.imageHandle
    -- 城镇背景按时间段切换（仅非子场景时生效）
    if not M.subScene and M.overlayType == "town" and M.overlayId then
        local hour = M.getGameHour()
        local timeKey
        if hour >= 18 or hour < 5 then
            timeKey = M.overlayId .. "_night"   -- 18:00 ~ 5:00
        elseif hour >= 5 and hour < 8 then
            timeKey = M.overlayId .. "_dawn"    -- 5:00 ~ 8:00
        elseif hour >= 16 and hour < 18 then
            timeKey = M.overlayId .. "_dusk"    -- 16:00 ~ 18:00
        end
        if timeKey and M.registry["town"] and M.registry["town"][timeKey] and M.registry["town"][timeKey] ~= -1 then
            displayImg = M.registry["town"][timeKey]
        end
    end
    if M.subScene then
        displayImg = M.subScene.imageHandle
        -- 冒险者公会/会长办公室/酒馆/铁匠铺/首饰店：用视频帧替代静态背景（双缓冲）
        if (M.subScene.id == "guild" or M.subScene.id == "guild_master_office" or M.subScene.id == "tavern" or M.subScene.id == "blacksmith" or M.subScene.id == "jewelry_shop" or M.subScene.id == "potion_shop" or M.subScene.id == "armor_shop" or M.subScene.id == "forest_elf") and (M._guildVideoPlayer or M._guildVideoPrevPlayer) then
            -- 新视频就绪时创建 nvg handle
            if M._guildVideoReady and not M._guildVideoNvgHandle and M._guildVideoPlayer then
                local tex = M._guildVideoPlayer:GetTexture()
                if tex and nvgCreateVideo then
                    M._guildVideoNvgHandle = nvgCreateVideo(vg, tex)
                end
            end
            -- 优先用新 handle，回退用 prev handle（旧视频最后一帧）
            local handle = M._guildVideoNvgHandle or M._guildVideoPrevNvgHandle
            if handle and handle > 0 then
                displayImg = handle
            end
        end
        -- 酒馆舞池视角：根据演出阶段选择背景图
        if M.tavernDanceView and M.subScene.id == "tavern" then
            -- 有舞女视频在播放时，视频帧已被上方视频逻辑设置为 displayImg，无需覆盖
            -- 仅在没有视频播放器时才回退到静态背景图
            if not (M._guildVideoPlayer or M._guildVideoPrevPlayer) then
                local ImageManager = require("ImageManager")
                if GS.dancerShowPhase == "done" then
                    local sittingImg = ImageManager.lazyGet("ui", "image/bg_tavern_dancer_sitting.png")
                    if sittingImg and sittingImg ~= -1 then
                        displayImg = sittingImg
                    end
                else
                    local danceImg = ImageManager.lazyGet("ui", "image/bg_tavern_dancefloor.jpg")
                    if danceImg and danceImg ~= -1 then
                        displayImg = danceImg
                    end
                end
            end
        end
    end

    -- 背景渐变过渡动画（仅昼夜切换时平滑过渡，进入建筑/切换地图直接硬切）
    local BG_FADE_DURATION = 1.5  -- 渐变时长（秒）
    -- 判断是否为"时间导致的背景变化"：同一场景（overlayType+overlayId+subScene不变）下 displayImg 变了
    local sceneKey = tostring(M.overlayType) .. "|" .. tostring(M.overlayId) .. "|" .. tostring(M.subScene and M.subScene.id or "") .. "|" .. tostring(M.tavernDanceView) .. "|" .. tostring(GS.dancerShowPhase or "")
    if not M._bgFadeSceneKey then M._bgFadeSceneKey = sceneKey end
    if not M._bgFadeOldImg then M._bgFadeOldImg = displayImg end
    if not M._bgFadeProgress then M._bgFadeProgress = 1.0 end
    if sceneKey ~= M._bgFadeSceneKey then
        -- 场景切换（进入建筑/换地图）：直接硬切，不渐变
        M._bgFadeSceneKey = sceneKey
        M._bgFadeOldImg = displayImg
        M._bgFadePrevImg = nil
        M._bgFadeProgress = 1.0
    elseif displayImg ~= M._bgFadeOldImg and not (M._guildVideoPlayer or M._guildVideoPrevPlayer) then
        -- 同一场景内图片变了（昼夜切换）：启动渐变（视频播放中跳过，视频帧切换不需要渐变）
        if M._bgFadeProgress >= 1.0 then
            M._bgFadePrevImg = M._bgFadeOldImg
            M._bgFadeProgress = 0.0
        end
        M._bgFadeOldImg = displayImg
    end
    if M._bgFadeProgress < 1.0 then
        local frameDt = time and time.timeStep or (1.0 / 60.0)
        M._bgFadeProgress = math.min(1.0, M._bgFadeProgress + frameDt / BG_FADE_DURATION)
    end

    -- 黑色圆角边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx - border, by - border,
        boardSize + border * 2, boardSize + border * 2, cr)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg)

    -- 图片铺满（圆角裁剪）— 支持渐变过渡
    local innerR = math.max(0, cr - border)
    if M._bgFadePrevImg and M._bgFadeProgress < 1.0 then
        -- 先画旧背景
        local patOld = nvgImagePattern(vg, bx, by, boardSize, boardSize, 0, M._bgFadePrevImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, boardSize, boardSize, innerR)
        nvgFillPaint(vg, patOld)
        nvgFill(vg)
        -- 再叠加新背景（alpha 渐入）
        local patNew = nvgImagePattern(vg, bx, by, boardSize, boardSize, 0, displayImg, M._bgFadeProgress)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, boardSize, boardSize, innerR)
        nvgFillPaint(vg, patNew)
        nvgFill(vg)
    else
        M._bgFadePrevImg = nil
        local pat = nvgImagePattern(vg, bx, by, boardSize, boardSize, 0, displayImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, boardSize, boardSize, innerR)
        nvgFillPaint(vg, pat)
        nvgFill(vg)
    end

    if M.subScene then
        -- ============ 子场景模式 ============
        -- 绘制贴纸/叠加图片
        local def = M.buildingInteriors[M.subScene.id]
        if def and def.notes then
            for _, note in ipairs(def.notes) do
                local noteImg = M.registry[note.imageType] and M.registry[note.imageType][note.imageId]
                if noteImg and noteImg ~= -1 then
                    local ns = boardSize * note.size
                    local nx = bx + boardSize * note.rx - ns / 2
                    local ny = by + boardSize * note.ry - ns / 2
                    local notePat = nvgImagePattern(vg, nx, ny, ns, ns, 0, noteImg, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, nx, ny, ns, ns)
                    nvgFillPaint(vg, notePat)
                    nvgFill(vg)
                end
            end
        end
        -- ============ 冒险者公会：等级徽章 ============
        if M.subScene.id == "guild" and GS.player and not GS.hideRankBadge then
            M.drawAdventurerRankBadge(vg, bx, by, boardSize)
        end

        -- ============ 广告机：描述面板 ============
        if M.subScene.id == "guild_ad_machine" then
            M.drawAdMachineDesc(vg, bx, by, boardSize)
        end

        -- ============ 布告栏：委托卡片直接绘制在背景上 ============
        if M.subScene.id == "bulletin_board" then
            M.drawBulletinQuestOnBoard(vg, bx, by, boardSize)
        end

        -- 绘制子场景按钮
        M.subSceneBtnRects = {}
        M.buildingBtnRects = {}
        -- 根据视角选择按钮集：酒馆舞池有独立按钮（复用上方 def）
        local buttons = M.subScene.buttons
        if M.tavernDanceView and def and def.dancefloor then
            buttons = def.dancefloor.buttons
        end
        -- 演出阶段隐藏所有按钮（交谈、回到前台、退出等）
        local hideBtns = (GS.dancerShowPhase == "performing")
        if buttons and #buttons > 0 and not hideBtns then
            -- 收集所有按钮，exit 按钮放到末尾
            local normalBtns = {}
            local exitBtn = nil
            for _, btn in ipairs(buttons) do
                if btn.action == "exit" then
                    exitBtn = btn
                else
                    normalBtns[#normalBtns + 1] = btn
                end
            end
            -- 将离开按钮追加到末尾
            if exitBtn and not M.subScene.hideExitIcon then
                normalBtns[#normalBtns + 1] = exitBtn
            end

            -- 底部居中排列按钮
            if #normalBtns > 0 then
                local btnH = math.max(24, boardSize * 0.09)
                local btnR = 6
                local fontSize = math.max(14, btnH * 0.5)
                local padX = fontSize * 1.2
                local gap = fontSize * 0.8
                local rowGap = fontSize * 0.5  -- 行间距
                nvgFontSize(vg, fontSize)
                nvgFontFace(vg, "sans")

                -- 计算每个按钮宽度
                local btnWidths = {}
                local totalW = 0
                for i, btn in ipairs(normalBtns) do
                    local tw = nvgTextBounds(vg, 0, 0, btn.label, nil)
                    btnWidths[i] = math.max(60, tw + padX * 2)
                    totalW = totalW + btnWidths[i]
                end
                totalW = totalW + gap * (#normalBtns - 1)

                -- 判断是否需要多行：超过可用宽度的90%就分行
                local availW = boardSize * 0.9
                local rows = {}
                if totalW > availW and #normalBtns > 3 then
                    -- 分两行：前半放第一行，后半放第二行
                    local half = math.ceil(#normalBtns / 2)
                    rows[1] = {}
                    rows[2] = {}
                    for i, btn in ipairs(normalBtns) do
                        if i <= half then
                            rows[1][#rows[1] + 1] = { btn = btn, w = btnWidths[i] }
                        else
                            rows[2][#rows[2] + 1] = { btn = btn, w = btnWidths[i] }
                        end
                    end
                else
                    -- 单行
                    rows[1] = {}
                    for i, btn in ipairs(normalBtns) do
                        rows[1][#rows[1] + 1] = { btn = btn, w = btnWidths[i] }
                    end
                end

                local numRows = #rows
                local totalBtnH = numRows * btnH + (numRows - 1) * rowGap
                local baseY = by + boardSize - totalBtnH - boardSize * 0.06

                for ri, row in ipairs(rows) do
                    local rowTotalW = 0
                    for _, item in ipairs(row) do
                        rowTotalW = rowTotalW + item.w
                    end
                    rowTotalW = rowTotalW + gap * (#row - 1)
                    local startX = bx + (boardSize - rowTotalW) / 2
                    local btnY = baseY + (ri - 1) * (btnH + rowGap)
                    local curX = startX
                    for _, item in ipairs(row) do
                        local bw = item.w
                        local cx = curX + bw / 2
                        local cy = btnY + btnH / 2
                        local isExit = (item.btn.action == "exit")
                        nvgBeginPath(vg)
                        nvgRoundedRect(vg, curX, btnY, bw, btnH, btnR)
                        nvgFillColor(vg, isExit and nvgRGBA(80, 15, 10, 230) or nvgRGBA(30, 20, 10, 220))
                        nvgFill(vg)
                        nvgStrokeColor(vg, isExit and nvgRGBA(200, 60, 50, 240) or nvgRGBA(210, 180, 100, 240))
                        nvgStrokeWidth(vg, 2)
                        nvgStroke(vg)
                        nvgFontSize(vg, fontSize)
                        nvgFontFace(vg, "sans")
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, isExit and nvgRGBA(255, 200, 180, 255) or nvgRGBA(240, 225, 180, 255))
                        nvgText(vg, cx, cy, item.btn.label, nil)
                        M.subSceneBtnRects[#M.subSceneBtnRects + 1] = { x = curX, y = btnY, w = bw, h = btnH, action = item.btn.action, label = item.btn.label }
                        curX = curX + bw + gap
                    end
                end
            end
        end

        -- (对话框移至黑屏遮罩之后绘制，见函数末尾)
    else
        -- ============ 城镇模式：绘制建筑按钮 ============
        M.buildingBtnRects = {}
        M.subSceneBtnRects = {}
        local buildings = M.townBuildings[M.overlayId]
        if buildings then
            local btnH = math.max(18, boardSize * 0.07)
            local btnR = 4
            local fontSize = math.max(11, btnH * 0.6)
            local padX = fontSize * 0.6

            for i, b in ipairs(buildings) do
                nvgFontSize(vg, fontSize)
                nvgFontFace(vg, "sans")
                local tw = nvgTextBounds(vg, 0, 0, b.label, nil)
                local btnW = math.max(36, tw + padX * 2)
                local cx = bx + boardSize * b.rx + (b.ox or 0)
                local cy = by + boardSize * b.ry + (b.oy or 0)
                local x = cx - btnW / 2
                local y = cy - btnH / 2

                -- 按钮背景（半透明深色 + 金边）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, x, y, btnW, btnH, btnR)
                nvgFillColor(vg, nvgRGBA(30, 20, 10, 200))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 220))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 按钮文字
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(240, 225, 180, 255))
                nvgText(vg, cx, cy, b.label, nil)

                -- 存储点击区域
                M.buildingBtnRects[i] = { x = x, y = y, w = btnW, h = btnH, index = i, label = b.label }
            end
        end
    end

    -- ============ 商店商品列表（覆盖在棋盘上方） ============
    if GS.shopMode and GS.shopBuildingKey then
        local shopItems = GS.SHOP_INVENTORY[GS.shopBuildingKey] or {}
        M.drawShopList(vg, bx, by, boardSize, shopItems)
    end

    -- ============ 广告加载面板（覆盖在棋盘上方） ============
    if GS.adLoading then
        M.drawAdLoadingPanel(vg, bx, by, boardSize)
    end

    -- ============ 兑换面板（覆盖在棋盘上方） ============
    if GS.exchangeMode then
        M.drawExchangePanel(vg, bx, by, boardSize)
    end

    -- ============ 深渊兑换面板（覆盖在棋盘上方） ============
    if GS.abyssExchangeMode then
        M.drawAbyssExchangePanel(vg, bx, by, boardSize)
    end

    -- ============ 强化面板（覆盖在棋盘上方） ============
    if GS.enhanceMode then
        M.drawEnhancePanel(vg, bx, by, boardSize)
    end

    -- ============ 精炼面板（覆盖在棋盘上方） ============
    if GS.refineMode then
        M.drawRefinePanel(vg, bx, by, boardSize)
    end

    -- ============ 锻造面板（覆盖在棋盘上方） ============
    if GS.forgeMode then
        M.drawForgePanel(vg, bx, by, boardSize)
    end

    -- ============ 炼金面板（覆盖在棋盘上方） ============
    if GS.alchemyMode then
        M.drawAlchemyPanel(vg, bx, by, boardSize)
    end

    -- ============ 烹饪面板（覆盖在棋盘上方） ============
    if GS.cookingMode then
        M.drawCookingPanel(vg, bx, by, boardSize)
    end

    -- ============ 镶嵌面板（覆盖在棋盘上方） ============
    if GS.socketMode then
        M.drawSocketPanel(vg, bx, by, boardSize)
    end

    -- ============ 修复面板（覆盖在棋盘上方） ============
    if GS.repairMode then
        M.drawRepairPanel(vg, bx, by, boardSize)
    end

    -- ============ 附魔面板（覆盖在棋盘上方） ============
    if GS.enchantMode then
        M.drawEnchantPanel(vg, bx, by, boardSize)
    end

    -- ============ 委托加工面板（覆盖在棋盘上方） ============
    if GS.craftMode then
        M.drawCraftPanel(vg, bx, by, boardSize)
    end

    -- ============ 仓库面板（覆盖在棋盘上方） ============
    if GS.warehouseMode then
        M.drawWarehousePanel(vg, bx, by, boardSize)
    end

    -- ============ 遗失物品面板（覆盖在棋盘上方） ============
    if GS.lostItemsMode then
        M.drawLostItemsPanel(vg, bx, by, boardSize)
    end

    -- ============ 赠送礼物面板（覆盖在棋盘上方） ============
    if GS.giftMode then
        M.drawGiftPanel(vg, bx, by, boardSize)
    end

    -- ============ 任务物品提交面板（覆盖在棋盘上方） ============
    if GS.questSubmitMode then
        M.drawQuestSubmitPanel(vg, bx, by, boardSize)
    end

    -- ============ 打烊弹窗（模态，屏蔽其他操作） ============
    if M.closedPopup then
        local popup = M.closedPopup

        -- 半透明遮罩
        nvgBeginPath(vg)
        nvgRect(vg, bx, by, boardSize, boardSize)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)

        -- 自适应缩放（以 320 为基准）
        local sc = boardSize / 320
        local titleFS   = math.floor(16 * sc)
        local bodyFS    = math.floor(13 * sc)
        local btnFS     = math.floor(13 * sc)
        local lineGap   = math.floor(8 * sc)
        local padX      = math.floor(24 * sc)
        local padTop    = math.floor(18 * sc)
        local padBot    = math.floor(14 * sc)
        local btnW      = math.floor(64 * sc)
        local btnH      = math.floor(26 * sc)
        local btnGap    = math.floor(14 * sc)

        -- 三行文本
        local line1 = popup.shopName
        local function fmtHour(h)
            local hr = math.floor(h)
            local mn = math.floor((h - hr) * 60 + 0.5)
            return string.format("%d:%02d", hr, mn)
        end
        local line2
        if popup.closeHour > popup.openHour then
            line2 = "营业时间：" .. fmtHour(popup.openHour) .. "-" .. fmtHour(popup.closeHour)
        else
            line2 = "营业时间：" .. fmtHour(popup.openHour) .. "-次日" .. fmtHour(popup.closeHour)
        end
        local line3 = "现在门窗紧锁。"

        -- 弹窗宽度：取 boardSize 的 70%，并确保文本不溢出
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, bodyFS)
        local tw2 = nvgTextBounds(vg, 0, 0, line2, nil)
        local boxW = math.max(math.floor(boardSize * 0.70), tw2 + padX * 2)

        -- 弹窗高度：标题 + 2行正文 + 按钮
        local contentH = titleFS + lineGap + bodyFS + lineGap + bodyFS
        local boxH = padTop + contentH + btnGap + btnH + padBot
        local boxX = bx + boardSize / 2 - boxW / 2
        local boxY = by + boardSize / 2 - boxH / 2

        -- 弹窗背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, boxX, boxY, boxW, boxH, math.floor(8 * sc))
        nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        local cx  = boxX + boxW / 2
        local curY = boxY + padTop

        -- 第一行：建筑名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, titleFS)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
        nvgText(vg, cx, curY, line1, nil)
        curY = curY + titleFS + lineGap

        -- 第二行：营业时间
        nvgFontSize(vg, bodyFS)
        nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
        nvgText(vg, cx, curY, line2, nil)
        curY = curY + bodyFS + lineGap

        -- 第三行：打烊提示
        nvgFillColor(vg, nvgRGBA(200, 160, 120, 255))
        nvgText(vg, cx, curY, line3, nil)

        -- 按钮区域
        local isGuild = (popup.shopName == "冒险者公会")
        local btnY2 = boxY + boxH - padBot - btnH
        M.closedPopupAdBtnRect = nil

        if isGuild then
            -- 冒险者公会：左侧"无人广告机" + 右侧"确定"
            local adBtnW = math.floor(80 * sc)
            local totalBtnW = adBtnW + math.floor(8 * sc) + btnW
            local startX = cx - totalBtnW / 2

            -- 左按钮：无人"广告机"
            nvgBeginPath(vg)
            nvgRoundedRect(vg, startX, btnY2, adBtnW, btnH, math.floor(4 * sc))
            nvgFillColor(vg, nvgRGBA(60, 80, 60, 220))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(140, 200, 140, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            nvgFontSize(vg, btnFS)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 240, 200, 255))
            nvgText(vg, startX + adBtnW / 2, btnY2 + btnH / 2, "无人\u{201c}广告机\u{201d}", nil)
            M.closedPopupAdBtnRect = { x = startX, y = btnY2, w = adBtnW, h = btnH }

            -- 右按钮：确定
            local okX = startX + adBtnW + math.floor(8 * sc)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, okX, btnY2, btnW, btnH, math.floor(4 * sc))
            nvgFillColor(vg, nvgRGBA(80, 80, 80, 220))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            nvgFontSize(vg, btnFS)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(240, 225, 180, 255))
            nvgText(vg, okX + btnW / 2, btnY2 + btnH / 2, "确定", nil)
            M.closedPopupBtnRect = { x = okX, y = btnY2, w = btnW, h = btnH }
        else
            -- 其他建筑：居中"确定"按钮
            local btnX = cx - btnW / 2
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY2, btnW, btnH, math.floor(4 * sc))
            nvgFillColor(vg, nvgRGBA(80, 80, 80, 220))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            nvgFontSize(vg, btnFS)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(240, 225, 180, 255))
            nvgText(vg, btnX + btnW / 2, btnY2 + btnH / 2, "确定", nil)
            M.closedPopupBtnRect = { x = btnX, y = btnY2, w = btnW, h = btnH }
        end
    end

    -- ── 淡入淡出黑屏遮罩（覆盖在最上层） ──
    if M._fadeAlpha and M._fadeAlpha > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, bx - border, by - border, boardSize + border * 2, boardSize + border * 2)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(M._fadeAlpha)))
        nvgFill(vg)
    end

    -- ============ Loading 指示器（全黑等待加载时显示）============
    if M._fadeAlpha and M._fadeAlpha >= 250 and (M._guildVideoPendingLoad or M._guildVideoLoadDelay or M._dancerPendingReveal or (M._fadeTarget == 255 and M._fadeDoneCallback)) then
        local t = GetTime():GetElapsedTime()
        local cx = bx + boardSize * 0.5
        local cy = by + boardSize * 0.5

        -- "Loading" 文本
        local fontSize = math.max(14, boardSize * 0.04)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local textW = nvgTextBounds(vg, 0, 0, "Loading", nil)

        -- 四芒星参数
        local starR = math.max(5, fontSize * 0.35)
        local gap = math.max(3, fontSize * 0.25)
        local totalW = textW + gap + starR * 2
        local startX = cx - totalW * 0.5

        -- 绘制文本
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, startX, cy, "Loading", nil)

        -- 绘制旋转四芒星（紧跟文本后方）
        local starCX = startX + textW + gap + starR
        local angle = t * 3.0
        nvgSave(vg)
        nvgTranslate(vg, starCX, cy)
        nvgRotate(vg, angle)
        nvgBeginPath(vg)
        for i = 0, 3 do
            local a = i * math.pi * 0.5
            local px = math.cos(a) * starR
            local py = math.sin(a) * starR
            if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
            local midA = a + math.pi * 0.25
            local midR = starR * 0.35
            local mx = math.cos(midA) * midR
            local my = math.sin(midA) * midR
            nvgLineTo(vg, mx, my)
        end
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- ============ 对话框（黑屏淡出后才显示，加载期间隐藏）============
    -- 每帧重置：只有本帧实际渲染了对话框才设值，避免残留旧值导致点击拦截器误判
    M.dialogueBoxRect = nil
    -- 舞女阶段（跳舞/过渡）/ 森林精灵离开阶段：黑屏时对话仍需显示，让玩家能看完文本
    local isDancerPhase = M._guildVideoPhase == "dancer_performing" or M._guildVideoPhase == "dancer_transition"
    local isForestElfLeaving = M._guildVideoPhase == "forest_elf_leaving" or (M._forestElfVideoEnded and not M._forestElfDialogueDone)
    if M.subScene and (isDancerPhase or isForestElfLeaving or M._kissSceneActive or not M._fadeAlpha or M._fadeAlpha < 10 or M._fadeTarget == 0) then
        local DialogueManager = require("DialogueManager")
        if DialogueManager.active then
            local line = DialogueManager.getCurrentLine()
            if line then
                if not Renderer then Renderer = require "Renderer" end
                local rect = Renderer._drawDialogueBox(vg, line, bx, by, boardSize)
                M.dialogueBoxRect = rect
            end
        end
    end

    -- ============ 告白确认弹窗（最上层，覆盖对话框） ============
    if GS.confessConfirmPopup then
        local popup = GS.confessConfirmPopup
        local npcName = popup.npcName or "她"
        local confirmText = "您是否确认向" .. npcName .. "表达心意？"
        -- 先量文本自适应宽度
        local fontSize = math.max(11, boardSize * 0.034)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        local textW = nvgTextBounds(vg, 0, 0, confirmText, nil)
        local padX = fontSize * 1.4
        local padY = fontSize * 1.0
        local btnH = math.max(20, fontSize * 1.3)
        local btnGap = fontSize * 0.6
        local dw = math.max(textW + padX * 2, boardSize * 0.38)
        local dh = padY + fontSize + btnGap + btnH + padY
        local dx = bx + (boardSize - dw) / 2
        local dy = by + (boardSize - dh) / 2
        -- 半透明遮罩
        nvgBeginPath(vg)
        nvgRect(vg, bx, by, boardSize, boardSize)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)
        -- 对话框背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dx, dy, dw, dh, 7)
        nvgFillColor(vg, nvgRGBA(40, 30, 20, 248))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 170, 100, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        -- 提示文本
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(245, 225, 180, 255))
        nvgText(vg, dx + dw / 2, dy + padY + fontSize / 2, confirmText, nil)
        -- 按钮
        local btnW = (dw - padX * 2 - btnGap) / 2
        local btnY = dy + padY + fontSize + btnGap
        local noX  = dx + padX
        local yesX = dx + padX + btnW + btnGap
        local btnFont = math.max(10, btnH * 0.48)
        nvgFontSize(vg, btnFont)
        -- 取消（红色）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, noX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(180, 50, 40, 220))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(255, 225, 215, 255))
        nvgText(vg, noX + btnW / 2, btnY + btnH / 2, "取消", nil)
        GS.confessConfirmNoRect  = { x = noX,  y = btnY, w = btnW, h = btnH }
        -- 确定（绿色）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, yesX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(50, 150, 60, 220))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(225, 255, 225, 255))
        nvgText(vg, yesX + btnW / 2, btnY + btnH / 2, "确定", nil)
        GS.confessConfirmYesRect = { x = yesX, y = btnY, w = btnW, h = btnH }
    end
end

-- ====================================================================
-- 商店商品列表渲染（羊皮纸底板 + 滚动条）
-- ====================================================================
function M.drawShopList(vg, bx, by, boardSize, shopItems)
    local ImageManager = require("ImageManager")

    -- ============ 羊皮纸底板 ============
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 商品列表 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local titleH = p.titleH
    local innerPad = p.innerPad
    GS.shopCloseRect = p.closeRect

    -- ============ 商品列表区域计算 ============
    local scrollBarW = math.max(8, panelW * 0.03)
    local totalItems = #shopItems
    local needScroll = totalItems > 4

    local listX = panelX + innerPad
    local listY = panelY + titleH + 4
    local listW = panelW - innerPad * 2 - (needScroll and (scrollBarW + 4) or 0)
    local listH = panelH - titleH - 4 - innerPad

    -- 每页4个商品，计算行高
    local maxVisible = 4
    local gap = math.max(4, listH * 0.025)
    local itemH = (listH - gap * (maxVisible - 1)) / maxVisible
    local iconSize = itemH * 0.7
    local fontSize = math.max(10, itemH * 0.30)
    local smallFont = math.max(8, fontSize * 0.8)

    -- 内容总高度 & 滚动范围
    local contentH = totalItems * (itemH + gap) - gap
    local visibleH = listH
    local maxScroll = math.max(0, contentH - visibleH)
    GS.shopScrollY = math.max(0, math.min(maxScroll, GS.shopScrollY))

    -- 存储给 Input 使用
    GS.shopContentH = contentH
    GS.shopVisibleH = visibleH
    GS.shopListClipRect = { x = listX, y = listY, w = listW + (needScroll and (scrollBarW + 4) or 0), h = listH }

    -- ============ 裁剪绘制商品行 ============
    nvgSave(vg)
    nvgScissor(vg, listX, listY, listW, listH)

    GS.shopItemRects = {}
    local shopRectIdx = 0
    for i, shopItem in ipairs(shopItems) do
        local tpl = GS.itemTemplates[shopItem.templateId]
        if tpl then
            local iy = listY + (i - 1) * (itemH + gap) - GS.shopScrollY

            -- 跳过不可见的项
            if iy + itemH >= listY and iy <= listY + listH then
                -- 商品行背景（深棕暖色衬底）
                nvgBeginPath(vg)
                nvgRoundedRect(vg, listX, iy, listW, itemH, 4)
                nvgFillColor(vg, nvgRGBA(45, 36, 28, 160))
                nvgFill(vg)

                -- 行边框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, listX + 0.5, iy + 0.5, listW - 1, itemH - 1, 4)
                nvgStrokeColor(vg, nvgRGBA(90, 70, 45, 180))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)

                -- 物品图标
                local iconX = listX + (itemH - iconSize) / 2
                local iconY = iy + (itemH - iconSize) / 2
                local imgHandle = ImageManager.lazyGet("item", tpl.icon)
                if imgHandle and imgHandle ~= -1 then
                    local iconPat = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, imgHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
                    nvgFillPaint(vg, iconPat)
                    nvgFill(vg)
                end

                -- 稀有度边框
                local rd = GS.RARITY[tpl.rarity or "common"] or GS.RARITY.common
                local rc = rd.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
                nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

                -- 伴侣折扣：莉娜→药剂店对折，朱莉→首饰店对折
                local displayPrice = shopItem.price
                if GS.shopBuildingKey == "potion_shop" then
                    local mul = GS.getPartnerDiscount("potion_buy")
                    if mul < 1.0 then displayPrice = math.max(1, math.ceil(shopItem.price * mul)) end
                elseif GS.shopBuildingKey == "jewelry_shop" then
                    local mul = GS.getPartnerDiscount("jewelry_buy")
                    if mul < 1.0 then displayPrice = math.max(1, math.ceil(shopItem.price * mul)) end
                end

                -- 库存与可购买量
                local stock = shopItem.stock or 0
                local canAfford = GS.gold >= displayPrice and stock > 0
                local maxBuyable = math.min(stock, math.floor(GS.gold / math.max(1, displayPrice)))

                -- 购买按钮（先算按钮宽度，供第二行定位用）
                local buyBtnW = math.max(40, listW * 0.20)
                local buyBtnH = math.max(18, itemH * 0.45)
                local buyBtnX = listX + listW - buyBtnW - 6
                local buyBtnY = iy + (itemH - buyBtnH) / 2

                -- 物品名称（靠上，黑色字体）
                local textX = listX + itemH + 4
                local textRightLimit = buyBtnX - 4  -- 文本区域右边界
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, fontSize)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, textX, iy + itemH * 0.32, tpl.name, nil)

                -- 第二行：库存（白色） + 售价（靠右挨着购买按钮）
                nvgFontSize(vg, smallFont)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
                nvgText(vg, textX, iy + itemH * 0.68, "库存:" .. stock, nil)

                -- 售价靠右（挨着购买按钮左侧）
                local priceStr = tostring(displayPrice) .. "G"
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                if canAfford then
                    nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
                else
                    nvgFillColor(vg, nvgRGBA(160, 80, 60, 200))
                end
                nvgText(vg, buyBtnX - 6, iy + itemH * 0.68, priceStr, nil)

                -- 购买按钮绘制
                nvgBeginPath(vg)
                nvgRoundedRect(vg, buyBtnX, buyBtnY, buyBtnW, buyBtnH, 3)
                if canAfford then
                    nvgFillColor(vg, nvgRGBA(60, 120, 40, 220))
                else
                    nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
                end
                nvgFill(vg)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, buyBtnX + 0.5, buyBtnY + 0.5, buyBtnW - 1, buyBtnH - 1, 3)
                if canAfford then
                    nvgStrokeColor(vg, nvgRGBA(100, 180, 60, 200))
                else
                    nvgStrokeColor(vg, nvgRGBA(160, 160, 160, 120))
                end
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)

                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(9, buyBtnH * 0.5))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if canAfford then
                    nvgFillColor(vg, nvgRGBA(220, 240, 200, 255))
                else
                    nvgFillColor(vg, nvgRGBA(180, 120, 120, 180))
                end
                nvgText(vg, buyBtnX + buyBtnW / 2, buyBtnY + buyBtnH / 2, "购买", nil)

                -- 装备等级（右下角，半透明背景 + 金色文字）
                if tpl.slot and tpl.level then
                    local lvText = "Lv" .. tpl.level
                    local lvFs = math.max(7, math.floor(iconSize * 0.28))
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, lvFs)
                    local tw = nvgTextBounds(vg, 0, 0, lvText, nil, nil)
                    local lvPad = 2
                    local bgW = tw + lvPad * 2
                    local bgH = lvFs + 3
                    local bgX = iconX + iconSize - bgW
                    local bgY = iconY + iconSize - bgH
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 2)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                    nvgFill(vg)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 215, 0, 240))
                    nvgText(vg, bgX + bgW * 0.5, bgY + bgH * 0.5, lvText, nil)
                end

                -- 存储点击区域（顺序索引，避免 ipairs 遇 nil 中断）
                shopRectIdx = shopRectIdx + 1
                GS.shopItemRects[shopRectIdx] = {
                    x = buyBtnX, y = buyBtnY, w = buyBtnW, h = buyBtnH,
                    iconX = iconX, iconY = iconY, iconW = iconSize, iconH = iconSize,
                    templateId = shopItem.templateId, price = displayPrice,
                    stock = stock, name = tpl.name,
                    shopItemRef = shopItem,  -- 引用原数据，方便扣减库存
                }
            end
        end
    end

    -- 空列表提示
    if totalItems == 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(14, listH * 0.06))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
        nvgText(vg, listX + listW / 2, listY + listH / 2, "暂无商品", nil)
    end

    nvgRestore(vg)

    -- ============ 滚动条（仅在内容超出时） ============
    if needScroll and contentH > visibleH then
        local sbTrackX = panelX + panelW - innerPad - scrollBarW
        local sbTrackY = listY
        local sbTrackH = listH

        -- 轨道背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbTrackX, sbTrackY, scrollBarW, sbTrackH, scrollBarW / 2)
        nvgFillColor(vg, nvgRGBA(160, 135, 95, 80))
        nvgFill(vg)

        -- 滑块
        local thumbH = math.max(20, sbTrackH * (visibleH / contentH))
        local thumbRange = sbTrackH - thumbH
        local thumbY = sbTrackY + (maxScroll > 0 and (GS.shopScrollY / maxScroll * thumbRange) or 0)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbTrackX + 1, thumbY, scrollBarW - 2, thumbH, (scrollBarW - 2) / 2)
        if GS.shopScrollBarDragging then
            nvgFillColor(vg, nvgRGBA(120, 90, 40, 230))
        else
            nvgFillColor(vg, nvgRGBA(140, 110, 60, 180))
        end
        nvgFill(vg)

        -- 存储滚动条信息给 Input 使用
        GS.shopScrollBarRect = { x = sbTrackX, y = thumbY, w = scrollBarW, h = thumbH }
        GS.shopScrollBarTrack = { x = sbTrackX, y = sbTrackY, w = scrollBarW, h = sbTrackH }
    else
        GS.shopScrollBarRect = nil
        GS.shopScrollBarTrack = nil
    end
end

-- ====================================================================
-- 仓库面板渲染（羊皮纸底板 + 格子网格 + 滚动条 + 底部按钮）
-- ====================================================================
function M.drawWarehousePanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 羊皮纸底板 ============
    local darkBg = {210, 190, 150, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 仓库 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local titleH = p.titleH
    local innerPad = p.innerPad
    GS.warehouseCloseRect = p.closeRect

    -- ============ 布局计算 ============
    local cols = 6
    local totalSlots = GS.warehouseSlots
    local totalRows = math.ceil(totalSlots / cols)
    local scrollBarW = math.max(8, panelW * 0.03)

    -- 底部容量文字高度
    local capH = math.max(14, panelH * 0.04)

    local gridAreaX = panelX + innerPad
    local gridAreaY = panelY + titleH + 4
    local gridAreaW = panelW - innerPad * 2 - scrollBarW - 4

    -- 格子大小（先算出来，再决定格子区域高度）
    local slotGap = 2
    local slotSize = math.floor((gridAreaW - (cols - 1) * slotGap) / cols)
    slotSize = math.max(14, slotSize)
    local step = slotSize + slotGap

    local gridW = cols * slotSize + (cols - 1) * slotGap
    local gridOffX = gridAreaX + math.floor((gridAreaW - gridW) / 2)

    -- 格子区域只显示4行，第5行位置放按钮
    local visibleRows = 4
    local gridAreaH = visibleRows * step - slotGap
    local btnRowY = gridAreaY + gridAreaH + slotGap

    -- 滚动
    local contentH = totalRows * step - slotGap
    local viewH = gridAreaH
    local maxScroll = math.max(0, contentH - viewH)
    GS.warehouseScrollY = math.max(0, math.min(maxScroll, GS.warehouseScrollY))
    local scrollY = GS.warehouseScrollY

    GS.warehouseContentH = contentH
    GS.warehouseVisibleH = viewH
    GS.warehouseClipRect = { x = gridAreaX, y = gridAreaY, w = gridAreaW + scrollBarW + 4, h = gridAreaH }

    -- ============ 裁剪绘制格子 ============
    nvgSave(vg)
    nvgScissor(vg, gridAreaX, gridAreaY, gridAreaW, gridAreaH)

    GS.warehouseSlotAreas = {}

    for i = 1, totalSlots do
        local row = math.ceil(i / cols)
        local col = ((i - 1) % cols) + 1
        local sx = gridOffX + (col - 1) * step
        local sy = gridAreaY + (row - 1) * step - scrollY

        if sy + slotSize >= gridAreaY and sy <= gridAreaY + viewH then
            GS.warehouseSlotAreas[i] = { x = sx, y = sy, w = slotSize, h = slotSize }

            local item = GS.warehouse[i]
            local isDragSource = GS.itemDragActive and GS.dragWarehouseIdx == i
            local isSelected = GS.warehouseMultiSelect and GS.warehouseSelected[i]

            -- 格子背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
            if isDragSource then
                nvgFillColor(vg, nvgRGBA(60, 45, 20, 180))
            elseif isSelected then
                nvgFillColor(vg, nvgRGBA(40, 80, 40, 255))
            elseif item and item.brittle then
                nvgFillColor(vg, nvgRGBA(220, 40, 40, 255))
            elseif item then
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            else
                nvgFillColor(vg, nvgRGBA(180, 160, 120, 200))
            end
            nvgFill(vg)

            -- 右下高光
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + slotSize, sy)
            nvgLineTo(vg, sx + slotSize, sy + slotSize)
            nvgLineTo(vg, sx, sy + slotSize)
            nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 120))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 左上阴影
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy + slotSize)
            nvgLineTo(vg, sx, sy)
            nvgLineTo(vg, sx + slotSize, sy)
            nvgStrokeColor(vg, nvgRGBA(40, 25, 10, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            if item then
                local itemAlpha = isDragSource and 0.3 or 1.0
                local imgHandle = item.icon and GS.itemImages[item.icon]
                if not imgHandle then
                    imgHandle = ImageManager.lazyGet("item", item.icon)
                end
                if imgHandle and imgHandle ~= -1 then
                    local pad = 2
                    local imgPaint = nvgImagePattern(vg,
                        sx + pad, sy + pad,
                        slotSize - pad * 2, slotSize - pad * 2,
                        0, imgHandle, itemAlpha)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx + pad, sy + pad, slotSize - pad * 2, slotSize - pad * 2, 2)
                    nvgFillPaint(vg, imgPaint)
                    nvgFill(vg)
                else
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, math.max(10, slotSize * 0.4))
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    local firstChar = item.name and string.sub(item.name, 1, 3) or "?"
                    nvgFillColor(vg, nvgRGBA(50, 35, 15, 255))
                    nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, firstChar, nil)
                end

                -- 稀有度边框
                local rarityDef = GS.RARITY and GS.RARITY[item.rarity]
                if rarityDef then
                    local bc = rarityDef.border
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, sx + 0.5, sy + 0.5, slotSize - 1, slotSize - 1, 3)
                    nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 200))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end

                -- 装饰层（精炼/附魔/强化等级/锁定/收藏）
                drawItemDecorations(vg, item, sx, sy, slotSize)

                -- 右下角堆叠数量
                if item.stackable and item.quantity and item.quantity > 1 then
                    local qtyText = tostring(item.quantity)
                    local lvFs = math.max(7, math.floor(slotSize * 0.28))
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, lvFs)
                    local tw = nvgTextBounds(vg, 0, 0, qtyText, nil, nil)
                    local lPad = 3
                    local bgW = tw + lPad * 2
                    local bgH = lvFs + 4
                    local bgX = sx + slotSize - bgW
                    local bgY = sy + slotSize - bgH
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 3)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                    nvgFill(vg)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                    nvgText(vg, bgX + bgW * 0.5, bgY + bgH * 0.5, qtyText, nil)
                end

                -- 多选勾选标记（右上角绿色对勾）
                if isSelected then
                    local ckSz = math.max(8, slotSize * 0.3)
                    local ckX = sx + slotSize - ckSz - 1
                    local ckY = sy + 1
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, ckX, ckY, ckSz, ckSz, 2)
                    nvgFillColor(vg, nvgRGBA(40, 160, 40, 220))
                    nvgFill(vg)
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, ckSz * 0.8)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, ckX + ckSz / 2, ckY + ckSz / 2, "✓", nil)
                end


            end
        end
    end

    nvgRestore(vg)

    -- ============ 滚动条 ============
    local needScroll = contentH > viewH
    if needScroll then
        local sbX = gridAreaX + gridAreaW + 2
        local sbY = gridAreaY
        local sbW = scrollBarW
        local sbH = gridAreaH

        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbX, sbY, sbW, sbH, sbW / 2)
        nvgFillColor(vg, nvgRGBA(120, 120, 120, 80))
        nvgFill(vg)

        local thumbH = math.max(20, sbH * (viewH / contentH))
        local thumbY = sbY + (sbH - thumbH) * (scrollY / maxScroll)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbX + 1, thumbY, sbW - 2, thumbH, (sbW - 2) / 2)
        nvgFillColor(vg, nvgRGBA(180, 140, 80, 200))
        nvgFill(vg)

        GS.warehouseScrollBarRect = { x = sbX + 1, y = thumbY, w = sbW - 2, h = thumbH }
        GS.warehouseScrollBarTrack = { x = sbX, y = sbY, w = sbW, h = sbH }
    else
        GS.warehouseScrollBarRect = nil
        GS.warehouseScrollBarTrack = nil
    end

    -- ============ 第5行按钮区（方形按钮占据格子位置） ============
    -- 悬停检测辅助
    local hoverMx, hoverMy
    do
        local pos = input:GetMousePosition()
        hoverMx = pos.x / GS.dpr / GS.S
        hoverMy = pos.y / GS.dpr / GS.S
    end
    local function btnHovered(bx2, by2, bw2, bh2)
        return hoverMx >= bx2 and hoverMx <= bx2 + bw2 and hoverMy >= by2 and hoverMy <= by2 + bh2
    end

    GS.warehouseBtnRects = {}

    --- 绘制方形渐变按钮（匹配物品栏按钮风格）
    local function drawSquareBtn(col, key, label, gradTop, gradBot, borderColor, textColor)
        local bx2 = gridOffX + (col - 1) * step
        local by2 = btnRowY
        GS.warehouseBtnRects[key] = { x = bx2, y = by2, w = slotSize, h = slotSize }

        local isHover = btnHovered(bx2, by2, slotSize, slotSize)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx2, by2, slotSize, slotSize, 3)
        if isHover then
            -- hover 时稍微提亮
            local hGrad = nvgLinearGradient(vg, bx2, by2, bx2, by2 + slotSize,
                nvgRGBA(math.min(255, gradTop[1] + 30), math.min(255, gradTop[2] + 30), math.min(255, gradTop[3] + 30), 240),
                nvgRGBA(math.min(255, gradBot[1] + 25), math.min(255, gradBot[2] + 25), math.min(255, gradBot[3] + 25), 240))
            nvgFillPaint(vg, hGrad)
        else
            local nGrad = nvgLinearGradient(vg, bx2, by2, bx2, by2 + slotSize,
                nvgRGBA(gradTop[1], gradTop[2], gradTop[3], 220),
                nvgRGBA(gradBot[1], gradBot[2], gradBot[3], 220))
            nvgFillPaint(vg, nGrad)
        end
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx2 + 0.5, by2 + 0.5, slotSize - 1, slotSize - 1, 3)
        nvgStrokeColor(vg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 200))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 文字
        local tc = textColor or {230, 210, 170, 240}
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], tc[4] or 240))
        local cx = bx2 + slotSize / 2
        local cy = by2 + slotSize / 2
        if type(label) == "table" then
            -- 双行文字：label = {"拖入", "取出"}
            local fs = math.max(10, slotSize * 0.35)
            nvgFontSize(vg, fs)
            nvgText(vg, cx, cy - fs * 0.55, label[1], nil)
            nvgText(vg, cx, cy + fs * 0.55, label[2], nil)
        else
            nvgFontSize(vg, math.max(10, slotSize * 0.35))
            nvgText(vg, cx, cy, label, nil)
        end
    end

    -- 取出按钮始终在最右侧(col6)，两种模式下都显示
    local withdrawCol = cols
    local selCount = 0
    if GS.warehouseMultiSelect then
        for _ in pairs(GS.warehouseSelected) do selCount = selCount + 1 end
    end

    if GS.warehouseMultiSelect then
        -- 多选模式：取消(col1)
        drawSquareBtn(1, "cancel", "取消",
            {90, 65, 35}, {65, 45, 22}, {0, 0, 0, 200})
    else
        -- 普通模式：整理(col1) | 多选(col2)
        drawSquareBtn(1, "sort", "整理",
            {90, 65, 35}, {65, 45, 22}, {0, 0, 0, 200})
        drawSquareBtn(2, "multi", "多选",
            {90, 65, 35}, {65, 45, 22}, {0, 0, 0, 200})
    end

    -- 取出按钮（蓝色，最右侧 col6，始终显示）
    local wdLabel = GS.warehouseMultiSelect and "取出" or {"拖入", "取出"}
    drawSquareBtn(withdrawCol, "withdraw", wdLabel,
        {35, 110, 170}, {20, 80, 130}, {60, 150, 200}, {255, 220, 200, 240})

    -- ============ 底部容量文本（在按钮行下方） ============
    local usedCount = 0
    for i = 1, totalSlots do
        if GS.warehouse[i] then usedCount = usedCount + 1 end
    end
    local capText = "容量: " .. usedCount .. " / " .. totalSlots
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(10, capH * 0.8))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(60, 45, 30, 220))
    nvgText(vg, panelX + panelW / 2, btnRowY + slotSize + capH / 2 + 2, capText, nil)
end

-- ====================================================================
-- 共享仓库面板（书桌交互，5格，跨角色共享）
-- ====================================================================
function M.drawSharedStoragePanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 预计算面板高度 ============
    local panelPad = boardSize * 0.04
    local preW = boardSize - panelPad * 2
    local preTitleH = math.max(26, preW * 0.09)
    local preInnerPad = preW * 0.05

    local cols = 5
    local totalSlots = GS.SHARED_STORAGE_SLOTS
    local preGridW = preW - preInnerPad * 2
    local slotGap = 3
    local preSlotSize = math.floor((preGridW - (cols - 1) * slotGap) / cols)
    preSlotSize = math.max(14, preSlotSize)

    local hintH = math.max(14, preSlotSize * 0.45)
    local capH = math.max(14, preSlotSize * 0.45)
    local logBtnH = math.max(14, preSlotSize * 0.7)
    -- 标题 + 提示文字 + 格子 + 取出按钮 + 查看记录按钮 + 容量 + 注意事项 + 边距
    local neededH = preTitleH + 4 + hintH + 6 + preSlotSize + slotGap + 4 + preSlotSize + 4 + logBtnH + capH + 2 + capH + 8 + 8

    -- ============ 羊皮纸底板 ============
    local darkBg = {210, 190, 150, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 共享仓库 -", { height = neededH, bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local titleH = p.titleH
    local innerPad = p.innerPad
    GS.sharedStorageCloseRect = p.closeRect
    GS.sharedStoragePanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

    -- ============ 布局计算 ============
    local gridAreaX = panelX + innerPad
    local gridAreaY = panelY + titleH + 4
    local gridAreaW = panelW - innerPad * 2

    local slotSize = math.floor((gridAreaW - (cols - 1) * slotGap) / cols)
    slotSize = math.max(14, slotSize)
    local step = slotSize + slotGap

    local gridW = cols * slotSize + (cols - 1) * slotGap
    local gridOffX = gridAreaX + math.floor((gridAreaW - gridW) / 2)

    -- ============ 提示文字 ============
    local hintY = gridAreaY
    hintH = math.max(14, slotSize * 0.45)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(10, hintH * 0.85))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(60, 45, 30, 220))
    nvgText(vg, panelX + panelW / 2, hintY + hintH / 2, "所有角色共享的物品存放空间", nil)

    local slotStartY = hintY + hintH + 6

    -- ============ 绘制格子 ============
    GS.sharedStorageSlotAreas = {}

    for i = 1, totalSlots do
        local col = ((i - 1) % cols) + 1
        local sx = gridOffX + (col - 1) * step
        local sy = slotStartY

        GS.sharedStorageSlotAreas[i] = { x = sx, y = sy, w = slotSize, h = slotSize }

        local item = GS.sharedStorage[i]
        local isDragSource = GS.itemDragActive and GS.dragSharedStorageIdx == i

        -- 格子背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
        if isDragSource then
            nvgFillColor(vg, nvgRGBA(60, 45, 20, 180))
        elseif item then
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 160, 120, 200))
        end
        nvgFill(vg)

        -- 右下高光
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + slotSize, sy)
        nvgLineTo(vg, sx + slotSize, sy + slotSize)
        nvgLineTo(vg, sx, sy + slotSize)
        nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 左上阴影
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy + slotSize)
        nvgLineTo(vg, sx, sy)
        nvgLineTo(vg, sx + slotSize, sy)
        nvgStrokeColor(vg, nvgRGBA(40, 25, 10, 100))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        if item then
            local itemAlpha = isDragSource and 0.3 or 1.0
            local imgHandle = item.icon and GS.itemImages[item.icon]
            if not imgHandle then
                imgHandle = ImageManager.lazyGet("item", item.icon)
            end
            if imgHandle and imgHandle ~= -1 then
                local pad = 2
                local imgPaint = nvgImagePattern(vg,
                    sx + pad, sy + pad,
                    slotSize - pad * 2, slotSize - pad * 2,
                    0, imgHandle, itemAlpha)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + pad, sy + pad, slotSize - pad * 2, slotSize - pad * 2, 2)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(10, slotSize * 0.4))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local firstChar = item.name and string.sub(item.name, 1, 3) or "?"
                nvgFillColor(vg, nvgRGBA(50, 35, 15, 255))
                nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, firstChar, nil)
            end

            -- 稀有度边框
            local rarityDef = GS.RARITY and GS.RARITY[item.rarity]
            if rarityDef then
                local bc = rarityDef.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + 0.5, sy + 0.5, slotSize - 1, slotSize - 1, 3)
                nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end

            -- 装饰层
            drawItemDecorations(vg, item, sx, sy, slotSize)

            -- 堆叠数量
            if item.stackable and item.quantity and item.quantity > 1 then
                local qtyText = tostring(item.quantity)
                local lvFs = math.max(7, math.floor(slotSize * 0.28))
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, lvFs)
                local tw = nvgTextBounds(vg, 0, 0, qtyText, nil, nil)
                local lPad = 3
                local bgW = tw + lPad * 2
                local bgH = lvFs + 4
                local bgX = sx + slotSize - bgW
                local bgY = sy + slotSize - bgH
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 3)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                nvgFill(vg)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                nvgText(vg, bgX + bgW * 0.5, bgY + bgH * 0.5, qtyText, nil)
            end
        end
    end

    -- ============ 按钮区 ============
    local hoverMx, hoverMy
    do
        local pos = input:GetMousePosition()
        hoverMx = pos.x / GS.dpr / GS.S
        hoverMy = pos.y / GS.dpr / GS.S
    end

    GS.sharedStorageBtnRects = {}

    local btnRowY = slotStartY + slotSize + slotGap + 4
    local btnH    = slotSize

    -- 取出按钮（蓝色，居中）
    local btnW = slotSize * 2 + slotGap
    local btnX = gridOffX + math.floor((gridW - btnW) / 2)
    GS.sharedStorageBtnRects["withdraw"] = { x = btnX, y = btnRowY, w = btnW, h = btnH }

    local isHoverW = hoverMx >= btnX and hoverMx <= btnX + btnW and hoverMy >= btnRowY and hoverMy <= btnRowY + btnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnRowY, btnW, btnH, 3)
    if isHoverW then
        nvgFillPaint(vg, nvgLinearGradient(vg, btnX, btnRowY, btnX, btnRowY + btnH,
            nvgRGBA(65, 140, 200, 240), nvgRGBA(45, 105, 155, 240)))
    else
        nvgFillPaint(vg, nvgLinearGradient(vg, btnX, btnRowY, btnX, btnRowY + btnH,
            nvgRGBA(35, 110, 170, 220), nvgRGBA(20, 80, 130, 220)))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX + 0.5, btnRowY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(60, 150, 200, 200))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(10, btnH * 0.35))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 200, 240))
    nvgText(vg, btnX + btnW / 2, btnRowY + btnH / 2, "拖入取出", nil)

    -- 查看记录按钮（棕色，居中，在取出按钮下方）
    logBtnH = math.max(14, slotSize * 0.7)
    local logBtnY = btnRowY + btnH + 4
    local logBtnW = btnW
    local logBtnX = btnX
    GS.sharedStorageBtnRects["log"] = { x = logBtnX, y = logBtnY, w = logBtnW, h = logBtnH }

    local isHoverL = hoverMx >= logBtnX and hoverMx <= logBtnX + logBtnW and hoverMy >= logBtnY and hoverMy <= logBtnY + logBtnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, logBtnX, logBtnY, logBtnW, logBtnH, 3)
    if isHoverL then
        nvgFillPaint(vg, nvgLinearGradient(vg, logBtnX, logBtnY, logBtnX, logBtnY + logBtnH,
            nvgRGBA(140, 100, 50, 230), nvgRGBA(100, 70, 30, 230)))
    else
        nvgFillPaint(vg, nvgLinearGradient(vg, logBtnX, logBtnY, logBtnX, logBtnY + logBtnH,
            nvgRGBA(110, 80, 40, 210), nvgRGBA(80, 55, 20, 210)))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, logBtnX + 0.5, logBtnY + 0.5, logBtnW - 1, logBtnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 80, 200))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(9, logBtnH * 0.5))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 235, 180, 240))
    nvgText(vg, logBtnX + logBtnW / 2, logBtnY + logBtnH / 2, "查看记录", nil)

    -- ============ 底部容量文本 ============
    capH = math.max(14, slotSize * 0.45)
    local usedCount = 0
    for i = 1, totalSlots do
        if GS.sharedStorage[i] then usedCount = usedCount + 1 end
    end
    local capText = "容量: " .. usedCount .. " / " .. totalSlots
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(10, capH * 0.8))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(60, 45, 30, 220))
    nvgText(vg, panelX + panelW / 2, logBtnY + logBtnH + capH / 2 + 2, capText, nil)

    -- ============ 禁止提示（任务/特殊物品） ============
    local noteY = logBtnY + logBtnH + capH + 4
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(9, capH * 0.7))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(60, 45, 30, 180))
    nvgText(vg, panelX + panelW / 2, noteY + capH * 0.4, "任务物品和特殊物品不可存入", nil)
end

-- ====================================================================
-- 共享仓库操作记录面板
-- ====================================================================
function M.drawSharedStorageLogPanel(vg, bx, by, boardSize)
    local lines = GS.sharedStorageLogLines or {}

    -- ============ 布局 ============
    local panelPad = boardSize * 0.04
    local panelX = bx + panelPad
    local panelW = boardSize - panelPad * 2
    local innerPad = math.max(6, panelW * 0.025)

    local titleH   = math.max(26, boardSize * 0.07)
    local rowH     = math.max(14, boardSize * 0.038)
    GS.sharedStorageLogRowH = rowH
    local maxRows  = 10
    local listH    = maxRows * rowH
    local closeBtnSz = math.max(18, titleH * 0.7)
    local panelH   = titleH + 8 + listH + 8

    local panelY = by + (boardSize - panelH) / 2

    -- ============ 背景（深棕羊皮纸） ============
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    local bg1 = nvgRGBA(60, 40, 20, 245)
    local bg2 = nvgRGBA(90, 60, 30, 245)
    local bgPaint = nvgLinearGradient(vg, panelX, panelY, panelX, panelY + panelH, bg1, bg2)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 80, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- ============ 标题 ============
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(14, titleH * 0.5))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, panelX + panelW / 2, panelY + titleH / 2, "共享仓库操作记录", nil)

    -- ============ 标题分割线 ============
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + innerPad, panelY + titleH)
    nvgLineTo(vg, panelX + panelW - innerPad, panelY + titleH)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 80, 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- ============ 关闭按钮（右上角 ×） ============
    local closeX = panelX + panelW - innerPad - closeBtnSz
    local closeY = panelY + (titleH - closeBtnSz) / 2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeBtnSz, closeBtnSz, 4)
    nvgFillColor(vg, nvgRGBA(180, 60, 40, 200))
    nvgFill(vg)
    nvgFontSize(vg, math.max(12, closeBtnSz * 0.65))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, closeX + closeBtnSz / 2, closeY + closeBtnSz / 2, "×", nil)
    GS.sharedStorageLogCloseRect = { x = closeX, y = closeY, w = closeBtnSz, h = closeBtnSz }

    -- ============ 日志列表 ============
    local listX = panelX + innerPad
    local listY = panelY + titleH + 8
    local listW = panelW - innerPad * 2

    -- 箭头尺寸提前计算（供内容区垂直避让使用）
    local arrowSz    = math.max(14, rowH * 0.85)
    local arrowX     = panelX + panelW - innerPad - arrowSz
    local arrowUpY   = listY
    local arrowDownY = listY + listH - arrowSz

    -- 当箭头显示时，内容行夹在两箭头之间，避免垂直重叠
    local totalLines = #lines
    local contentStartY, visibleRows
    if totalLines > maxRows then
        contentStartY = arrowUpY + arrowSz + 2
        visibleRows   = math.max(1, math.floor((arrowDownY - contentStartY) / rowH))
    else
        contentStartY = listY
        visibleRows   = maxRows
    end
    GS.sharedStorageLogVisibleRows = visibleRows

    -- 滚动偏移（用 visibleRows 重算 maxScroll）
    local scroll    = GS.sharedStorageLogScroll or 0
    local maxScroll = math.max(0, totalLines - visibleRows)
    scroll = math.max(0, math.min(scroll, maxScroll))
    GS.sharedStorageLogScroll = scroll

    -- 记录面板 rect 用于点击拦截
    GS.sharedStorageLogPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(9, rowH * 0.62))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    for i = 1, visibleRows do
        local lineIdx = i + scroll
        local rowY = contentStartY + (i - 1) * rowH

        -- 交替背景
        if i % 2 == 0 then
            nvgBeginPath(vg)
            nvgRect(vg, listX, rowY, listW, rowH)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 12))
            nvgFill(vg)
        end

        if lines[lineIdx] then
            local txt = lines[lineIdx]
            -- 根据「存入」或「取出」着色
            local color
            if txt:find("存入") then
                color = nvgRGBA(120, 220, 120, 230)
            elseif txt:find("取出") then
                color = nvgRGBA(220, 180, 100, 230)
            else
                color = nvgRGBA(200, 200, 200, 200)
            end
            nvgFillColor(vg, color)
            nvgText(vg, listX + 4, rowY + rowH / 2, txt, nil)
        end
    end

    -- 无记录提示
    if totalLines == 0 then
        nvgFontSize(vg, math.max(11, rowH * 0.7))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 160, 120, 160))
        nvgText(vg, panelX + panelW / 2, listY + listH / 2, "暂无记录", nil)
    end

    -- ============ 滚动按钮 ▲▼（有超过 maxRows 条时显示） ============
    if totalLines > maxRows then
        -- ▲ 上翻
        local upAlpha  = (scroll > 0)          and 220 or 80
        nvgBeginPath(vg)
        nvgRoundedRect(vg, arrowX, arrowUpY, arrowSz, arrowSz, 3)
        nvgFillColor(vg, nvgRGBA(120, 90, 50, upAlpha))
        nvgFill(vg)
        nvgFontSize(vg, math.max(10, arrowSz * 0.7))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 235, 180, upAlpha))
        nvgText(vg, arrowX + arrowSz / 2, arrowUpY + arrowSz / 2, "▲", nil)

        -- ▼ 下翻
        local downAlpha = (scroll < maxScroll)  and 220 or 80
        nvgBeginPath(vg)
        nvgRoundedRect(vg, arrowX, arrowDownY, arrowSz, arrowSz, 3)
        nvgFillColor(vg, nvgRGBA(120, 90, 50, downAlpha))
        nvgFill(vg)
        nvgFontSize(vg, math.max(10, arrowSz * 0.7))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 235, 180, downAlpha))
        nvgText(vg, arrowX + arrowSz / 2, arrowDownY + arrowSz / 2, "▼", nil)

        -- 条数提示（水平居中）
        nvgFontSize(vg, math.max(8, arrowSz * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(180, 160, 100, 140))
        nvgText(vg, panelX + panelW / 2, panelY + panelH - 2,
            string.format("共 %d 条", totalLines), nil)

        -- 保存按钮 rect 供 Input.lua 使用
        GS.sharedStorageLogScrollUpRect   = { x = arrowX, y = arrowUpY,   w = arrowSz, h = arrowSz }
        GS.sharedStorageLogScrollDownRect = { x = arrowX, y = arrowDownY, w = arrowSz, h = arrowSz }
    else
        GS.sharedStorageLogScrollUpRect   = nil
        GS.sharedStorageLogScrollDownRect = nil
    end
end

-- ====================================================================
-- 遗失物品面板（公会界面，简化版仓库面板）
-- ====================================================================
function M.drawLostItemsPanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- ============ 布局预计算（先算内容高度，再画面板） ============
    local cols = 5
    local totalSlots = GS.LOST_ITEMS_MAX  -- 10
    local totalRows = math.ceil(totalSlots / cols)  -- 2

    local panelPad = boardSize * 0.04
    local panelX = bx + panelPad
    local panelW = boardSize - panelPad * 2
    local innerPad = math.max(6, panelW * 0.025)
    local titleH = math.max(26, boardSize * 0.07)

    local gridAreaX = panelX + innerPad
    local gridAreaW = panelW - innerPad * 2

    local slotGap = 2
    local slotSize = math.floor((gridAreaW - (cols - 1) * slotGap) / cols)
    slotSize = math.max(14, slotSize)
    local step = slotSize + slotGap

    local gridW = cols * slotSize + (cols - 1) * slotGap
    local gridOffX = gridAreaX + math.floor((gridAreaW - gridW) / 2)

    -- 底部信息行高度
    local infoFs = math.max(10, slotSize * 0.3)
    local hintFs = math.max(8, infoFs * 0.85)
    local bottomH = 4 + infoFs + 3 + hintFs + 6

    -- 总面板高度 = 标题 + 格子 + 底部信息
    local panelH = titleH + 4 + totalRows * step + bottomH + innerPad
    -- 垂直居中
    local panelY = by + (boardSize - panelH) / 2

    -- ============ 绘制浅灰底板（与仓库配色统一） ============
    local darkBg = {210, 190, 150, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 遗失物品 -", { height = panelH, bgColor = darkBg })
    panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    titleH = p.titleH
    innerPad = p.innerPad
    GS.lostItemsCloseRect = p.closeRect

    -- 用 drawParchmentPanel 返回的实际布局重新计算格子区域
    gridAreaX = panelX + innerPad
    gridAreaW = panelW - innerPad * 2
    slotSize = math.floor((gridAreaW - (cols - 1) * slotGap) / cols)
    slotSize = math.max(14, slotSize)
    step = slotSize + slotGap
    gridW = cols * slotSize + (cols - 1) * slotGap
    gridOffX = gridAreaX + math.floor((gridAreaW - gridW) / 2)
    infoFs = math.max(10, slotSize * 0.3)
    hintFs = math.max(8, infoFs * 0.85)

    local gridAreaY = panelY + titleH + 4

    -- ============ 绘制格子 ============
    GS.lostItemsSlotAreas = {}

    for i = 1, totalSlots do
        local row = math.ceil(i / cols)
        local col = ((i - 1) % cols) + 1
        local sx = gridOffX + (col - 1) * step
        local sy = gridAreaY + (row - 1) * step

        GS.lostItemsSlotAreas[i] = { x = sx, y = sy, w = slotSize, h = slotSize }

        local item = GS.lostItems[i]
        local isDragSource = GS.lostItemDragActive and GS.dragLostItemIdx == i

        -- 正在拖拽的格子半透明
        if isDragSource then
            nvgSave(vg)
            nvgGlobalAlpha(vg, 0.35)
        end

        -- 格子背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotSize, slotSize, 3)
        if item and item.brittle then
            nvgFillColor(vg, nvgRGBA(220, 40, 40, 255))
        elseif item then
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 160, 120, 200))
        end
        nvgFill(vg)

        -- 右下高光
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + slotSize, sy)
        nvgLineTo(vg, sx + slotSize, sy + slotSize)
        nvgLineTo(vg, sx, sy + slotSize)
        nvgStrokeColor(vg, nvgRGBA(50, 45, 40, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 左上阴影
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy + slotSize)
        nvgLineTo(vg, sx, sy)
        nvgLineTo(vg, sx + slotSize, sy)
        nvgStrokeColor(vg, nvgRGBA(40, 25, 10, 100))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        if item then
            -- 物品图标
            local imgHandle = item.icon and GS.itemImages[item.icon]
            if not imgHandle then
                imgHandle = ImageManager.lazyGet("item", item.icon)
            end
            if imgHandle and imgHandle ~= -1 then
                local pad2 = 2
                local imgPaint = nvgImagePattern(vg,
                    sx + pad2, sy + pad2,
                    slotSize - pad2 * 2, slotSize - pad2 * 2,
                    0, imgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + pad2, sy + pad2, slotSize - pad2 * 2, slotSize - pad2 * 2, 2)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(10, slotSize * 0.4))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local firstChar = item.name and string.sub(item.name, 1, 3) or "?"
                nvgFillColor(vg, nvgRGBA(50, 35, 15, 255))
                nvgText(vg, sx + slotSize / 2, sy + slotSize / 2, firstChar, nil)
            end

            -- 稀有度边框
            local rarityDef = GS.RARITY and GS.RARITY[item.rarity]
            if rarityDef then
                local bc = rarityDef.border
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx + 0.5, sy + 0.5, slotSize - 1, slotSize - 1, 3)
                nvgStrokeColor(vg, nvgRGBA(bc[1], bc[2], bc[3], 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end

            -- 装饰层
            drawItemDecorations(vg, item, sx, sy, slotSize)

            -- 堆叠数量
            if item.stackable and item.quantity and item.quantity > 1 then
                local qtyText = tostring(item.quantity)
                local lvFs = math.max(7, math.floor(slotSize * 0.28))
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, lvFs)
                local tw = nvgTextBounds(vg, 0, 0, qtyText, nil, nil)
                local lPad = 3
                local bgW = tw + lPad * 2
                local bgH = lvFs + 4
                local bgX = sx + slotSize - bgW
                local bgY = sy + slotSize - bgH
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 3)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
                nvgFill(vg)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
                nvgText(vg, bgX + bgW * 0.5, bgY + bgH * 0.5, qtyText, nil)
            end
        end

        if isDragSource then
            nvgRestore(vg)
        end
    end

    -- ============ 按钮行 + 信息行 ============
    local btnRowY = gridAreaY + totalRows * step + 4

    local hoverMx, hoverMy
    do
        local pos = input:GetMousePosition()
        hoverMx = pos.x / GS.dpr / GS.S
        hoverMy = pos.y / GS.dpr / GS.S
    end
    local function btnHovered(bx2, by2, bw2, bh2)
        return hoverMx >= bx2 and hoverMx <= bx2 + bw2 and hoverMy >= by2 and hoverMy <= by2 + bh2
    end

    GS.lostItemsBtnRects = {}

    -- 容量文本（左侧）
    local usedCount = 0
    for i = 1, totalSlots do
        if GS.lostItems[i] then usedCount = usedCount + 1 end
    end
    local capText = "容量: " .. usedCount .. " / " .. totalSlots
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, infoFs)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(60, 45, 30, 220))
    nvgText(vg, gridOffX, btnRowY + 2, capText, nil)

    -- 提示文字（容量下方）
    nvgFontSize(vg, hintFs)
    nvgFillColor(vg, nvgRGBA(60, 45, 30, 200))
    nvgText(vg, gridOffX, btnRowY + 2 + infoFs + 3, "拖动物品放回背包即可取回", nil)

    -- "全部取回" 按钮（右侧）
    local btnH = infoFs + 3 + hintFs + 4
    local wdBtnW = slotSize * 2 + slotGap
    local wdBtnX = gridOffX + gridW - wdBtnW
    do
        local bx2, by2, bw2, bh2 = wdBtnX, btnRowY, wdBtnW, btnH
        GS.lostItemsBtnRects["withdraw_all"] = { x = bx2, y = by2, w = bw2, h = bh2 }
        local isHover = btnHovered(bx2, by2, bw2, bh2)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx2, by2, bw2, bh2, 3)
        local gradTop, gradBot = {35, 110, 170}, {20, 80, 130}
        if isHover then
            local hGrad = nvgLinearGradient(vg, bx2, by2, bx2, by2 + bh2,
                nvgRGBA(math.min(255, gradTop[1] + 30), math.min(255, gradTop[2] + 30), math.min(255, gradTop[3] + 30), 240),
                nvgRGBA(math.min(255, gradBot[1] + 25), math.min(255, gradBot[2] + 25), math.min(255, gradBot[3] + 25), 240))
            nvgFillPaint(vg, hGrad)
        else
            local nGrad = nvgLinearGradient(vg, bx2, by2, bx2, by2 + bh2,
                nvgRGBA(gradTop[1], gradTop[2], gradTop[3], 220),
                nvgRGBA(gradBot[1], gradBot[2], gradBot[3], 220))
            nvgFillPaint(vg, nGrad)
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx2 + 0.5, by2 + 0.5, bw2 - 1, bh2 - 1, 3)
        nvgStrokeColor(vg, nvgRGBA(60, 150, 200, 200))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(10, bh2 * 0.4))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 200, 240))
        nvgText(vg, bx2 + bw2 / 2, by2 + bh2 / 2, "全部取回", nil)
    end
end

-- ====================================================================
-- 冒险者等级徽章（公会界面左上角）
-- ====================================================================

-- 等级定义：F → S，每个等级有专属配色
local ADVENTURER_RANKS = {
    { rank = "F", color = {130, 130, 130}, glow = {170, 170, 170}, label = "见习冒险者" },  -- 灰色
    { rank = "E", color = { 60, 140,  60}, glow = { 90, 180,  90}, label = "初级冒险者" },  -- uncommon
    { rank = "D", color = { 60, 100, 180}, glow = { 90, 130, 220}, label = "中级冒险者" },  -- rare
    { rank = "C", color = {140,  60, 180}, glow = {180,  90, 220}, label = "高级冒险者" },  -- fine
    { rank = "B", color = {255, 185,  15}, glow = {255, 215,  50}, label = "精英冒险者" },  -- superior
    { rank = "A", color = {230,  80,  20}, glow = {255, 120,  40}, label = "王牌冒险者" },  -- 橙红
    { rank = "S", color = {230,  20,  40}, glow = {255,  60,  70}, label = "传奇冒险者" },  -- 红
    { rank = "G", color = {220, 100, 220}, glow = {100, 220, 240}, label = "冒险者之神",    -- 蓝粉渐变
      gradient = { {220, 100, 220}, {50, 210, 240} } },
}

-- ====================================================================
-- 广告机描述面板（顶部自适应底板）
-- ====================================================================
function M.drawAdMachineDesc(vg, bx, by, boardSize)
    local titleLine = "神赐的机器"
    ---@diagnostic disable-next-line: unicode-name, undefined-global
    local descLine = "看\u{201c}广告\u{201d}把你的力量传输给异世界的他！帮助在另一个世界拼搏着的穷苦冒险者！"
    local pad = boardSize * 0.04
    local titleFontSize = math.max(14, boardSize * 0.05)
    local descFontSize = math.max(11, boardSize * 0.038)
    local panelX = bx + pad
    local panelY = by + pad
    local panelW = boardSize - pad * 2
    local innerPad = pad * 0.8
    local contentW = panelW - innerPad * 2
    local lineGap = descFontSize * 0.4

    nvgFontFace(vg, "sans")

    -- 计算标题行高度
    local titleLineH = titleFontSize * 1.2

    -- 计算描述行高度（可能自动换行）
    nvgFontSize(vg, descFontSize)
    local bounds = {0, 0, 0, 0}
    nvgTextBoxBounds(vg, panelX + innerPad, 0, contentW, descLine, nil, bounds)
    local descH = (bounds[4] or 0) - (bounds[2] or 0)
    if descH <= 0 then descH = descFontSize * 2.5 end

    local panelH = innerPad + titleLineH + lineGap + descH + innerPad

    -- 底板背景（深色半透明 + 金边）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 6)
    nvgFillColor(vg, nvgRGBA(20, 15, 10, 210))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 6)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 第一行：标题（暖金色，居中，较大字号）
    nvgFontSize(vg, titleFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
    nvgText(vg, panelX + panelW / 2, panelY + innerPad + titleLineH * 0.5, titleLine, nil)

    -- 第二行：描述（浅金色，居中自动换行，较小字号）
    nvgFontSize(vg, descFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(240, 220, 170, 230))
    nvgTextBox(vg, panelX + innerPad, panelY + innerPad + titleLineH + lineGap, contentW, descLine, nil)
end

-- ====================================================================
-- 广告加载面板（居中对话框：加载提示 + 取消按钮）
-- ====================================================================
function M.drawAdLoadingPanel(vg, bx, by, boardSize)
    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, bx, by, boardSize, boardSize)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
    nvgFill(vg)

    -- 面板宽度和内边距
    local panelW = boardSize * 0.75
    local innerPad = panelW * 0.08
    local contentW = panelW - innerPad * 2
    local cornerR = 8

    -- 先测量文字高度，再计算面板总高度
    local msgText = "正在向异世界传送力量，帮助那个世界穷苦的冒险者……"
    local fontSize = math.max(12, boardSize * 0.042)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    local bounds = {0, 0, 0, 0}
    nvgTextBoxBounds(vg, 0, 0, contentW, msgText, nil, bounds)
    local textH = (bounds[4] or (fontSize * 3)) - (bounds[2] or 0)

    local dotFontSize = math.max(14, boardSize * 0.05)
    local dotH = dotFontSize
    local btnH = math.max(24, boardSize * 0.055)
    local gap = math.max(8, boardSize * 0.025)  -- 元素之间的间距

    -- 面板高度 = 上边距 + 文字 + 间距 + 省略号 + 间距 + 按钮 + 下边距
    local panelH = innerPad + textH + gap + dotH + gap + btnH + innerPad
    local panelX = bx + (boardSize - panelW) / 2
    local panelY = by + (boardSize - panelH) / 2

    -- 面板背景（深色羊皮纸风格）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 提示文字
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 230, 160, 255))
    local textX = panelX + panelW / 2
    local textY = panelY + innerPad
    nvgTextBox(vg, panelX + innerPad, textY, contentW, msgText, nil)

    -- 加载动画省略号（根据时间闪烁）
    local dotCount = math.floor((time:GetElapsedTime() * 2) % 4)
    local dots = string.rep(".", dotCount)
    nvgFontSize(vg, dotFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 230, 160, 160))
    nvgText(vg, textX, textY + textH + gap, dots, nil)

    -- "我不想帮助他了"按钮
    local btnW = panelW * 0.50
    local btnX = panelX + (panelW - btnW) / 2
    local btnY = textY + textH + gap + dotH + gap

    -- 按钮底色（暗红色调）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
    nvgFillColor(vg, nvgRGBA(120, 50, 40, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
    nvgStrokeColor(vg, nvgRGBA(180, 100, 70, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 按钮文字
    local btnFontSize = math.max(11, boardSize * 0.035)
    nvgFontSize(vg, btnFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 210, 180, 255))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "我不想帮助他了", nil)

    -- 记录按钮区域供 Input 检测
    GS.adCancelRect = { x = btnX, y = btnY, w = btnW, h = btnH }
end

-- ====================================================================
-- 兑换面板渲染（羊皮纸底板 + 感恩礼券货币）
-- ====================================================================
function M.drawExchangePanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    -- 羊皮纸底板
    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 兑换奖品 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local titleH = p.titleH
    local innerPad = p.innerPad
    GS.exchangeCloseRect = p.closeRect

    -- 持有礼券数量（标题栏下方）
    local ticketCount = GS.countInventoryItem("gratitude_ticket")
    local infoFontSize = math.max(10, titleH * 0.45)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, infoFontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
    local ticketIcon = ImageManager.lazyGet("item", "image/item_gratitude_ticket.png")
    local ticketIconSize = infoFontSize * 1.2
    local ticketText = "感恩礼券 持有：" .. ticketCount .. " 张"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, infoFontSize)
    local textBounds = nvgTextBounds(vg, 0, 0, ticketText, nil)
    local textW = textBounds
    local totalW = ticketIconSize + 4 + textW
    local infoX = panelX + panelW - innerPad - totalW
    local infoY = panelY + titleH + 4 + ticketIconSize / 2
    if ticketIcon and ticketIcon ~= -1 then
        local pat = nvgImagePattern(vg, infoX, infoY - ticketIconSize / 2, ticketIconSize, ticketIconSize, 0, ticketIcon, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, infoX, infoY - ticketIconSize / 2, ticketIconSize, ticketIconSize, 2)
        nvgFillPaint(vg, pat)
        nvgFill(vg)
        -- 黑色边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, infoX, infoY - ticketIconSize / 2, ticketIconSize, ticketIconSize, 2)
        nvgStrokeColor(vg, nvgRGBA(80, 80, 80, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
    nvgText(vg, infoX + ticketIconSize + 4, infoY, ticketText, nil)

    -- 奖品列表
    local listY = infoY + ticketIconSize / 2 + 6
    local listX = panelX + innerPad
    local listW = panelW - innerPad * 2
    local listH = panelY + panelH - innerPad - listY
    local rewards = GS.EXCHANGE_REWARDS
    local maxVisible = 4
    local gap = math.max(4, listH * 0.025)
    local itemH = (listH - gap * (maxVisible - 1)) / maxVisible
    local iconSize = itemH * 0.7
    local fontSize = math.max(10, itemH * 0.30)
    local smallFont = math.max(8, fontSize * 0.8)

    -- 滚动条参数
    local scrollBarW = math.max(6, panelW * 0.02)
    local contentH = #rewards * (itemH + gap) - gap
    local visibleH = listH
    local needScroll = contentH > visibleH
    local maxScroll = math.max(0, contentH - visibleH)
    GS.exchangeScrollY = math.max(0, math.min(GS.exchangeScrollY or 0, maxScroll))
    GS.exchangeContentH = contentH
    GS.exchangeVisibleH = visibleH

    -- 如果需要滚动条，列表宽度缩减给滚动条留空间
    local itemListW = needScroll and (listW - scrollBarW - 4) or listW
    GS.exchangeListClipRect = { x = listX, y = listY, w = listW, h = listH }

    nvgSave(vg)
    nvgScissor(vg, listX, listY, listW, listH)

    GS.exchangeItemRects = {}
    for i, reward in ipairs(rewards) do
        local iy = listY + (i - 1) * (itemH + gap) - (GS.exchangeScrollY or 0)

        if iy + itemH >= listY and iy <= listY + listH then
            -- 行背景（深棕暖色衬底）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, listX, iy, itemListW, itemH, 4)
            nvgFillColor(vg, nvgRGBA(45, 36, 28, 230))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, listX + 0.5, iy + 0.5, itemListW - 1, itemH - 1, 4)
            nvgStrokeColor(vg, nvgRGBA(90, 70, 45, 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 图标
            local iconX = listX + (itemH - iconSize) / 2
            local iconY = iy + (itemH - iconSize) / 2
            local imgHandle = ImageManager.lazyGet("exchange_" .. i, reward.icon)
            if imgHandle and imgHandle ~= -1 then
                local iconPat = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, imgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
                nvgFillPaint(vg, iconPat)
                nvgFill(vg)
            end
            -- 图标边框（根据稀有度着色）
            local br, bg2, bb = 210, 180, 100
            local borderW = 1
            if reward.rewardItemId then
                local tmpl = GS.itemTemplates and GS.itemTemplates[reward.rewardItemId]
                if tmpl and tmpl.rarity and GS.RARITY[tmpl.rarity] then
                    local bc = GS.RARITY[tmpl.rarity].border
                    br, bg2, bb = bc[1], bc[2], bc[3]
                    borderW = 1.5
                end
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
            nvgStrokeColor(vg, nvgRGBA(br, bg2, bb, 220))
            nvgStrokeWidth(vg, borderW)
            nvgStroke(vg)

            -- 名称
            local textX = listX + itemH + 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, textX, iy + itemH * 0.32, reward.name, nil)

            -- 兑换按钮
            local buyBtnW = math.max(40, itemListW * 0.20)
            local buyBtnH = math.max(18, itemH * 0.45)
            local buyBtnX = listX + itemListW - buyBtnW - 6
            local buyBtnY = iy + (itemH - buyBtnH) / 2
            local dailyRemaining = GS.getExchangeDailyRemaining(reward)  -- nil=无限购, -1=不可用
            local canAfford = ticketCount >= reward.ticketCost and (reward.stock or 0) > 0
                and (dailyRemaining == nil or dailyRemaining > 0)

            -- 库存/每日限购信息
            nvgFontSize(vg, smallFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            if dailyRemaining == -1 then
                -- 服务器时间不可用：显示红色提示
                nvgFillColor(vg, nvgRGBA(220, 80, 60, 230))
                nvgText(vg, textX, iy + itemH * 0.68, "连接中...", nil)
            elseif dailyRemaining ~= nil then
                -- 有每日限购：显示今日剩余
                local drColor = dailyRemaining > 0 and nvgRGBA(180, 220, 120, 230) or nvgRGBA(220, 80, 60, 230)
                nvgFillColor(vg, drColor)
                nvgText(vg, textX, iy + itemH * 0.68, "今日:" .. dailyRemaining .. "/" .. reward.dailyLimit, nil)
            else
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
                nvgText(vg, textX, iy + itemH * 0.68, "库存:" .. (reward.stock or 0), nil)
            end

            local priceStr = reward.ticketCost .. "券"
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if canAfford then
                nvgFillColor(vg, nvgRGBA(180, 100, 40, 255))
            else
                nvgFillColor(vg, nvgRGBA(160, 80, 60, 200))
            end
            nvgText(vg, buyBtnX - 6, iy + itemH * 0.68, priceStr, nil)

            -- 兑换按钮绘制
            nvgBeginPath(vg)
            nvgRoundedRect(vg, buyBtnX, buyBtnY, buyBtnW, buyBtnH, 3)
            if canAfford then
                nvgFillColor(vg, nvgRGBA(160, 100, 30, 220))
            else
                nvgFillColor(vg, nvgRGBA(160, 160, 160, 150))
            end
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, buyBtnX + 0.5, buyBtnY + 0.5, buyBtnW - 1, buyBtnH - 1, 3)
            nvgStrokeColor(vg, canAfford and nvgRGBA(220, 170, 60, 200) or nvgRGBA(160, 160, 160, 120))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(9, buyBtnH * 0.5))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, canAfford and nvgRGBA(255, 240, 200, 255) or nvgRGBA(160, 160, 160, 180))
            nvgText(vg, buyBtnX + buyBtnW / 2, buyBtnY + buyBtnH / 2, "兑换", nil)

            -- 存储点击区域（兑换按钮 + 图标区域）
            GS.exchangeItemRects[#GS.exchangeItemRects + 1] = {
                x = buyBtnX, y = buyBtnY, w = buyBtnW, h = buyBtnH,
                rewardIdx = i, name = reward.name,
                ticketCost = reward.ticketCost, stock = reward.stock or 0,
                -- 图标区域（用于点击弹出物品详情）
                iconX = iconX, iconY = iconY, iconW = iconSize, iconH = iconSize,
                -- 整行区域（用于点击弹出物品详情）
                rowX = listX, rowY = iy, rowW = itemListW, rowH = itemH,
                -- 物品模板ID（仅物品类奖品）
                templateId = reward.rewardItemId,
                desc = reward.desc,
            }
        end
    end

    nvgRestore(vg)

    -- 滚动条绘制
    if needScroll and contentH > visibleH then
        local sbTrackX = listX + listW - scrollBarW
        local sbTrackY = listY
        local sbTrackH = listH

        -- 轨道背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbTrackX, sbTrackY, scrollBarW, sbTrackH, scrollBarW / 2)
        nvgFillColor(vg, nvgRGBA(160, 135, 95, 80))
        nvgFill(vg)

        -- 滑块
        local thumbH = math.max(20, sbTrackH * (visibleH / contentH))
        local thumbRange = sbTrackH - thumbH
        local thumbY = sbTrackY + (maxScroll > 0 and (GS.exchangeScrollY / maxScroll * thumbRange) or 0)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, sbTrackX + 1, thumbY, scrollBarW - 2, thumbH, (scrollBarW - 2) / 2)
        if GS.exchangeScrollBarDragging then
            nvgFillColor(vg, nvgRGBA(120, 90, 40, 230))
        else
            nvgFillColor(vg, nvgRGBA(140, 110, 60, 180))
        end
        nvgFill(vg)

        -- 存储滚动条信息给 Input 使用
        GS.exchangeScrollBarRect = { x = sbTrackX, y = thumbY, w = scrollBarW, h = thumbH }
        GS.exchangeScrollBarTrack = { x = sbTrackX, y = sbTrackY, w = scrollBarW, h = sbTrackH }
    else
        GS.exchangeScrollBarRect = nil
        GS.exchangeScrollBarTrack = nil
    end

    -- 兑换确认弹窗
    if GS.exchangeBuyConfirmVisible and GS.exchangeBuyConfirmItem then
        local item = GS.exchangeBuyConfirmItem
        local qty = GS.exchangeBuyQuantity or 1
        local totalCost = item.ticketCost * qty
        -- 先测量文本宽度以自适应弹窗大小
        local confirmText = "确认用 " .. totalCost .. " 张礼券兑换 " .. item.name .. "？"
        local baseFontSize = math.max(12, panelH * 0.045)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, baseFontSize)
        local confirmTW = nvgTextBounds(vg, 0, 0, confirmText, nil)
        local padding = baseFontSize * 3
        local dialogW = math.max(panelW * 0.5, math.min(panelW * 0.9, confirmTW + padding))
        local dialogH = baseFontSize * 5.5
        local dialogX = panelX + (panelW - dialogW) / 2
        local dialogY = panelY + (panelH - dialogH) / 2
        local dialogR = 8

        -- 遮罩
        nvgBeginPath(vg)
        nvgRect(vg, panelX, panelY, panelW, panelH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)

        -- 弹窗背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dialogX, dialogY, dialogW, dialogH, dialogR)
        nvgFillColor(vg, nvgRGBA(235, 215, 170, 250))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dialogX, dialogY, dialogW, dialogH, dialogR)
        nvgStrokeColor(vg, nvgRGBA(100, 70, 30, 200))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 提示文本
        local dfontSize = baseFontSize
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, dfontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(40, 30, 20, 255))
        nvgText(vg, dialogX + dialogW / 2, dialogY + dialogH * 0.35, confirmText, nil)

        -- 取消/确认按钮（取消在左，确认在右）
        local cbtnW = dialogW * 0.28
        local cbtnH = dialogH * 0.25
        local cbtnY = dialogY + dialogH * 0.6
        local noX = dialogX + dialogW / 2 - cbtnW - 10
        local yesX = dialogX + dialogW / 2 + 10

        -- 取消（红色）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, noX, cbtnY, cbtnW, cbtnH, 4)
        nvgFillColor(vg, nvgRGBA(180, 50, 40, 220))
        nvgFill(vg)
        nvgFontSize(vg, math.max(10, cbtnH * 0.55))
        nvgFillColor(vg, nvgRGBA(255, 230, 220, 255))
        nvgText(vg, noX + cbtnW / 2, cbtnY + cbtnH / 2, "取消", nil)
        GS.exchangeBuyNoRect = { x = noX, y = cbtnY, w = cbtnW, h = cbtnH }

        -- 确认（绿色）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, yesX, cbtnY, cbtnW, cbtnH, 4)
        nvgFillColor(vg, nvgRGBA(50, 150, 60, 220))
        nvgFill(vg)
        nvgFontSize(vg, math.max(10, cbtnH * 0.55))
        nvgFillColor(vg, nvgRGBA(230, 255, 230, 255))
        nvgText(vg, yesX + cbtnW / 2, cbtnY + cbtnH / 2, "确认", nil)
        GS.exchangeBuyYesRect = { x = yesX, y = cbtnY, w = cbtnW, h = cbtnH }
    end

    -- 兑换结果提示
    if GS.exchangeBuyMsg then
        local msg = GS.exchangeBuyMsg
        msg.timer = msg.timer - (GS.dt or 0.016)
        if msg.timer <= 0 then
            GS.exchangeBuyMsg = nil
        else
            local alpha = math.min(255, math.floor(msg.timer / 0.3 * 255))
            local mc = msg.color or {200, 200, 200}
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(12, panelH * 0.04))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(mc[1], mc[2], mc[3], alpha))
            nvgText(vg, panelX + panelW / 2, panelY + panelH - innerPad * 2, msg.text, nil)
        end
    end
end

function M.drawAbyssExchangePanel(vg, bx, by, boardSize)
    local ImageManager = require("ImageManager")

    local darkBg = {20, 15, 8, 255}
    local p = drawParchmentPanel(vg, bx, by, boardSize, "- 深渊兑换 -", { bgColor = darkBg })
    local panelX, panelY, panelW, panelH = p.panelX, p.panelY, p.panelW, p.panelH
    local titleH   = p.titleH
    local innerPad = p.innerPad
    GS.abyssExchangeCloseRect = p.closeRect

    -- ---- 右上角：深渊积分显示 ----
    local infoFontSize  = math.max(10, titleH * 0.45)
    local ptIconSize    = infoFontSize * 1.2
    local pointsText    = "深渊积分 持有：" .. (GS.abyssPoints or 0)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, infoFontSize)
    local ptTextW   = nvgTextBounds(vg, 0, 0, pointsText, nil)
    local ptTotalW  = ptIconSize + 4 + ptTextW
    local ptX       = panelX + panelW - innerPad - ptTotalW
    local ptY       = panelY + titleH + 4 + ptIconSize / 2

    local ptIcon = ImageManager.lazyGet("abyss_point_icon", "image/item_abyss_crystal.png")
    if ptIcon and ptIcon ~= -1 then
        local pat = nvgImagePattern(vg, ptX, ptY - ptIconSize / 2, ptIconSize, ptIconSize, 0, ptIcon, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ptX, ptY - ptIconSize / 2, ptIconSize, ptIconSize, 2)
        nvgFillPaint(vg, pat)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ptX, ptY - ptIconSize / 2, ptIconSize, ptIconSize, 2)
        nvgStrokeColor(vg, nvgRGBA(80, 80, 160, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
    nvgText(vg, ptX + ptIconSize + 4, ptY, pointsText, nil)

    -- ---- 物品列表（与 drawExchangePanel 相同布局） ----
    local listY  = ptY + ptIconSize / 2 + 6
    local listX  = panelX + innerPad
    local listW  = panelW - innerPad * 2
    local listH  = panelY + panelH - innerPad - listY
    local items  = GS.ABYSS_EXCHANGE_ITEMS
    local maxVisible = 4
    local gap    = math.max(4, listH * 0.025)
    local itemH  = (listH - gap * (maxVisible - 1)) / maxVisible
    local iconSize  = itemH * 0.7
    local fontSize  = math.max(10, itemH * 0.30)
    local smallFont = math.max(8, fontSize * 0.8)

    local scrollBarW = math.max(6, panelW * 0.02)
    local contentH   = #items * (itemH + gap) - gap
    local visibleH   = listH
    local needScroll = contentH > visibleH
    local maxScroll  = math.max(0, contentH - visibleH)
    GS.abyssExchangeScrollY   = math.max(0, math.min(GS.abyssExchangeScrollY or 0, maxScroll))
    GS.abyssExchangeContentH  = contentH
    GS.abyssExchangeVisibleH  = visibleH

    local itemListW = needScroll and (listW - scrollBarW - 4) or listW
    GS.abyssExchangeListClipRect = { x = listX, y = listY, w = listW, h = listH }

    nvgSave(vg)
    nvgScissor(vg, listX, listY, listW, listH)

    GS.abyssExchangeItemRects = {}
    for i, item in ipairs(items) do
        local iy = listY + (i - 1) * (itemH + gap) - (GS.abyssExchangeScrollY or 0)

        if iy + itemH >= listY and iy <= listY + listH then
            -- 行背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, listX, iy, itemListW, itemH, 4)
            nvgFillColor(vg, nvgRGBA(45, 36, 28, 230))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, listX + 0.5, iy + 0.5, itemListW - 1, itemH - 1, 4)
            nvgStrokeColor(vg, nvgRGBA(90, 70, 45, 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 图标
            local iconX = listX + (itemH - iconSize) / 2
            local iconY = iy + (itemH - iconSize) / 2
            local imgHandle = ImageManager.lazyGet("abyss_ex_" .. i, item.icon)
            if imgHandle and imgHandle ~= -1 then
                local iconPat = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, imgHandle, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
                nvgFillPaint(vg, iconPat)
                nvgFill(vg)
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
            nvgStrokeColor(vg, nvgRGBA(100, 80, 200, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 名称
            local textX = listX + itemH + 4
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, textX, iy + itemH * 0.32, item.name, nil)

            -- 兑换按钮尺寸
            local buyBtnW = math.max(40, itemListW * 0.20)
            local buyBtnH = math.max(18, itemH * 0.45)
            local buyBtnX = listX + itemListW - buyBtnW - 6
            local buyBtnY = iy + (itemH - buyBtnH) / 2

            -- 费用文字 & 持有量
            local costStr, ownedNow, canAfford
            if item.crystalCost and item.crystalCost > 0 then
                ownedNow  = GS.countInventoryItem("abyss_crystal")
                canAfford = ownedNow >= item.crystalCost
                costStr   = item.crystalCost .. "结晶"
            elseif item.pointsCost and item.pointsCost > 0 then
                ownedNow  = GS.abyssPoints or 0
                canAfford = ownedNow >= item.pointsCost
                costStr   = item.pointsCost .. "积分"
            else
                ownedNow  = 0
                canAfford = true
                costStr   = "免费"
            end

            -- 描述/持有量
            nvgFontSize(vg, smallFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(180, 180, 180, 220))
            nvgText(vg, textX, iy + itemH * 0.68, item.desc or "", nil)

            -- 兑换按钮
            nvgBeginPath(vg)
            nvgRoundedRect(vg, buyBtnX, buyBtnY, buyBtnW, buyBtnH, 3)
            nvgFillColor(vg, canAfford and nvgRGBA(160, 100, 30, 220) or nvgRGBA(160, 160, 160, 150))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, buyBtnX + 0.5, buyBtnY + 0.5, buyBtnW - 1, buyBtnH - 1, 3)
            nvgStrokeColor(vg, canAfford and nvgRGBA(220, 170, 60, 200) or nvgRGBA(160, 160, 160, 120))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(9, buyBtnH * 0.5))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, canAfford and nvgRGBA(255, 240, 200, 255) or nvgRGBA(160, 160, 160, 180))
            nvgText(vg, buyBtnX + buyBtnW / 2, buyBtnY + buyBtnH / 2, "兑换", nil)

            GS.abyssExchangeItemRects[#GS.abyssExchangeItemRects + 1] = {
                x = buyBtnX, y = buyBtnY, w = buyBtnW, h = buyBtnH,
                itemIdx = i,
                -- 行整体区域（用于 tap 触发 tooltip）
                rowX = listX, rowY = iy, rowW = itemListW, rowH = itemH,
                -- 图标区域（用于鼠标悬停 tooltip）
                iconX = iconX, iconY = iconY, iconW = iconSize, iconH = iconSize,
                -- 物品模板 ID（如果是物品类奖励）
                templateId = item.templateId or nil,
                -- 用于非物品类奖励的描述文字
                desc = item.desc,
                name = item.name,
            }
        end
    end

    nvgRestore(vg)

    -- ---- 消息提示（淡出） ----
    if GS.abyssExchangeMsg then
        local msg = GS.abyssExchangeMsg
        msg.timer = msg.timer - (GS.dt or 0.016)
        if msg.timer <= 0 then
            GS.abyssExchangeMsg = nil
        else
            local alpha = math.min(255, math.floor(msg.timer / 0.3 * 255))
            local mc    = msg.color or { 200, 200, 200 }
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.max(12, panelH * 0.04))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(mc[1], mc[2], mc[3], alpha))
            nvgText(vg, panelX + panelW / 2, panelY + panelH - innerPad * 2, msg.text, nil)
        end
    end
end

function M.drawAdventurerRankBadge(vg, bx, by, boardSize)
    local rankIdx = math.max(1, math.min(GS.adventurerRank or 1, #ADVENTURER_RANKS))
    local rankInfo = ADVENTURER_RANKS[rankIdx]
    local rc = rankInfo.color
    local rg = rankInfo.glow
    local t = (os.clock or function() return 0 end)()

    -- 徽章尺寸与位置（左上角）
    local badgeSize = math.max(48, boardSize * 0.22)
    local margin = boardSize * 0.04
    local cx = bx + margin + badgeSize / 2
    local cy = by + margin + badgeSize / 2
    local radius = badgeSize / 2

    -- === 1. 外圈光晕（脉冲） ===
    local pulse = math.sin(t * 2.5) * 0.12 + 0.88
    local glowR = radius * 1.45 * pulse
    local glowPaint = nvgRadialGradient(vg, cx, cy, radius * 0.3, glowR,
        nvgRGBA(rg[1], rg[2], rg[3], 70), nvgRGBA(rg[1], rg[2], rg[3], 0))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, glowR)
    nvgFillPaint(vg, glowPaint)
    nvgFill(vg)

    -- === 2. 八角形外框 ===
    local outerR = radius * 1.15
    local numSides = 8
    local angleOff = -math.pi / 2  -- 顶部起始
    -- 外框路径
    nvgBeginPath(vg)
    for i = 0, numSides - 1 do
        local a = angleOff + i * (math.pi * 2 / numSides)
        local px = cx + math.cos(a) * outerR
        local py = cy + math.sin(a) * outerR
        if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgClosePath(vg)
    -- 深色底
    nvgFillColor(vg, nvgRGBA(15, 12, 8, 235))
    nvgFill(vg)
    -- 金色描边
    nvgStrokeColor(vg, nvgRGBA(255, 220, 100, 200))
    nvgStrokeWidth(vg, math.max(2, radius * 0.07))
    nvgStroke(vg)

    -- === 3. 八角形内框（等级色边框） ===
    local innerR = radius * 0.95
    nvgBeginPath(vg)
    for i = 0, numSides - 1 do
        local a = angleOff + i * (math.pi * 2 / numSides)
        local px = cx + math.cos(a) * innerR
        local py = cy + math.sin(a) * innerR
        if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgClosePath(vg)
    nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 180))
    nvgStrokeWidth(vg, math.max(1.5, radius * 0.05))
    nvgStroke(vg)

    -- === 4. 内圆盾牌（主体） ===
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius * 0.8)
    local shieldPaint
    if rankInfo.gradient then
        -- G级特殊：蓝粉线性渐变
        local gc1 = rankInfo.gradient[1]
        local gc2 = rankInfo.gradient[2]
        shieldPaint = nvgLinearGradient(vg, cx, cy - radius * 0.8, cx, cy + radius * 0.8,
            nvgRGBA(gc1[1], gc1[2], gc1[3], 245),
            nvgRGBA(gc2[1], gc2[2], gc2[3], 245))
    else
        shieldPaint = nvgRadialGradient(vg, cx, cy - radius * 0.15, radius * 0.1, radius * 0.82,
            nvgRGBA(math.min(255, rc[1]+60), math.min(255, rc[2]+60), math.min(255, rc[3]+60), 245),
            nvgRGBA(math.max(0, rc[1]-50), math.max(0, rc[2]-50), math.max(0, rc[3]-50), 245))
    end
    nvgFillPaint(vg, shieldPaint)
    nvgFill(vg)
    -- 内圆金色边框
    nvgStrokeColor(vg, nvgRGBA(255, 225, 120, 200))
    nvgStrokeWidth(vg, math.max(1.5, radius * 0.05))
    nvgStroke(vg)

    -- === 5. 等级字母 ===
    local letterSize = radius * 1.4
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, letterSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 发光层
    for _, off in ipairs({{0,-2},{0,2},{-2,0},{2,0}}) do
        nvgFillColor(vg, nvgRGBA(rg[1], rg[2], rg[3], 55))
        nvgText(vg, cx + off[1], cy + off[2], rankInfo.rank, nil)
    end
    -- 阴影
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgText(vg, cx + 1, cy + 2, rankInfo.rank, nil)
    -- 主体
    nvgFillColor(vg, nvgRGBA(255, 255, 248, 255))
    nvgText(vg, cx, cy, rankInfo.rank, nil)

    -- === 6. 称号文字 ===
    local labelSize = math.max(10, radius * 0.36)
    local labelY = cy + radius * 1.3 + labelSize * 0.5
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, labelSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local tw = nvgTextBounds(vg, 0, 0, rankInfo.label, nil)
    local padX = labelSize * 0.6
    local padY = labelSize * 0.3
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - tw / 2 - padX, labelY - labelSize / 2 - padY,
        tw + padX * 2, labelSize + padY * 2, 5)
    nvgFillColor(vg, nvgRGBA(15, 12, 8, 210))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 100, 150))
    nvgStrokeWidth(vg, math.max(1, radius * 0.03))
    nvgStroke(vg)

    nvgFillColor(vg, nvgRGBA(math.min(255, rc[1]+60), math.min(255, rc[2]+60), math.min(255, rc[3]+60), 255))
    nvgText(vg, cx, labelY, rankInfo.label, nil)

    -- === 7. 晋升信息面板（徽章右侧） ===
    M.rankBtnUp = nil
    M.rankBtnDown = nil
    M.rankPromoteBtn = nil

    local panelX = cx + radius * 1.4
    local panelY = cy - radius * 1.0
    local panelFontSize = math.max(11, radius * 0.28)
    local lineH = panelFontSize * 1.5
    local nextRankIdx = rankIdx + 1
    local promo = GS.RANK_PROMOTIONS[nextRankIdx]

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, panelFontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    if GS.hidePromotionPanel then
        -- 事件流程中隐藏晋升面板，不显示任何内容
    elseif rankIdx == 7 then
        -- S级：显示完成面板（不再提示晋升G级）
        local totalBonus = GS.getAdventurerRankBonus()
        local bgPad = lineH * 0.3
        local bgLeft = panelX - bgPad
        local badgeRight = cx + outerR
        local gapLeft = bgLeft - badgeRight
        local sideMargin = boardSize * 0.025
        local bgRight = bx + boardSize - sideMargin - gapLeft
        local bgW = bgRight - bgLeft
        local descLine1 = "这不是旅途终点的开始……"
        local descLine2 = "这只是旅途开始的终点。"
        local maxRows = totalBonus > 0 and 4 or 3
        local bgH = lineH * maxRows + lineH * 0.3

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bgLeft, panelY - bgPad, bgW, bgH + bgPad, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)

        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgText(vg, panelX, panelY, "您已晋升S级冒险者", nil)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
        nvgText(vg, panelX, panelY + lineH, descLine1, nil)
        nvgText(vg, panelX, panelY + lineH * 2, descLine2, nil)
        if totalBonus > 0 then
            nvgFillColor(vg, nvgRGBA(200, 170, 80, 255))
            nvgText(vg, panelX, panelY + lineH * 3, "当前生效: 全属性+" .. totalBonus, nil)
        end
    elseif promo then
        -- 显示晋升条件
        local nextRankInfo = ADVENTURER_RANKS[nextRankIdx]
        local nextRankLetter = nextRankInfo and nextRankInfo.rank or "?"
        local nrc = nextRankInfo and nextRankInfo.color or {255, 255, 255}

        -- 预计算面板尺寸
        local condMet = GS.canPromoteRank()
        local totalBonus = GS.getAdventurerRankBonus()
        local rows = 3  -- 标题、条件、奖励
        if totalBonus > 0 then rows = rows + 1 end  -- 累计加成行
        local btnH2 = math.max(24, lineH * 1.3)
        local btnOffsetY = lineH * (rows - 1) + lineH * 1.8
        local bgPad = lineH * 0.3
        -- 底板高度：条件满足时包含晋升按钮，否则仅显示文字
        local bgH
        if condMet then
            bgH = btnOffsetY + btnH2 + lineH * 0.4
        else
            bgH = lineH * rows + lineH * 0.3
        end
        -- 对称边距：底板左边缘到徽章右边的距离 = 底板右边缘到棋盘右边的距离
        local bgLeft = panelX - bgPad
        local badgeRight = cx + outerR
        local gapLeft = bgLeft - badgeRight
        local sideMargin = boardSize * 0.025
        local bgRight = bx + boardSize - sideMargin - gapLeft
        local bgW = bgRight - bgLeft

        -- 绘制半透明底板
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bgLeft, panelY - bgPad, bgW, bgH + bgPad, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)

        -- 标题行：晋升至 X 级
        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgText(vg, panelX, panelY, "晋升至", nil)
        local titleW = nvgTextBounds(vg, 0, 0, "晋升至", nil)
        nvgFillColor(vg, nvgRGBA(nrc[1], nrc[2], nrc[3], 255))
        nvgText(vg, panelX + titleW + 2, panelY, " " .. nextRankLetter .. " 级", nil)

        -- 条件行
        local condY = panelY + lineH
        local condText = promo.desc
        -- 显示当前进度
        if promo.condType == "kill" then
            local cur = GS.monsterKillCounts[promo.condId] or 0
            local need = promo.condCount
            condText = condText .. " (" .. math.min(cur, need) .. "/" .. need .. ")"
        elseif promo.condType == "dungeon" then
            local done = GS.dungeonsCleared[promo.condId] == true
            condText = condText .. (done and " (已完成)" or " (未完成)")
        end
        if condMet then
            nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        end
        nvgText(vg, panelX, condY, "条件: " .. condText, nil)

        -- 加成行
        local bonusY = condY + lineH
        nvgFillColor(vg, nvgRGBA(120, 220, 255, 255))
        local affinityUnlockNames = { [2]="在意", [3]="重视", [4]="亲密", [5]="爱慕", [6]="挚爱" }
        local unlockName = affinityUnlockNames[nextRankIdx]
        local bonusText = "奖励: 全属性+" .. promo.bonus
        if unlockName then
            bonusText = bonusText .. " 解锁好感度「" .. unlockName .. "」"
        end
        nvgText(vg, panelX, bonusY, bonusText, nil)

        -- 当前累计加成
        if totalBonus > 0 then
            local totalY = bonusY + lineH
            nvgFillColor(vg, nvgRGBA(200, 170, 80, 255))
            nvgText(vg, panelX, totalY, "当前生效: 全属性+" .. totalBonus, nil)
        end

        -- 晋升按钮（仅在条件满足时显示）
        if condMet then
            local btnY = panelY + btnOffsetY
            local btnW = bgW - bgPad * 2
            local btnX2 = panelX
            local btnPulse = math.sin(t * 3) * 0.15 + 0.85

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX2, btnY, btnW, btnH2, 5)
            nvgFillColor(vg, nvgRGBA(math.floor(200 * btnPulse), math.floor(160 * btnPulse), 20, 240))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 240, 100, 230))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
            nvgFontSize(vg, math.max(13, panelFontSize * 1.0))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, btnX2 + btnW / 2, btnY + btnH2 / 2, "晋升", nil)

            M.rankPromoteBtn = { x = btnX2, y = btnY, w = btnW, h = btnH2 }
        end
    else
        -- 已满级（G级）—— 底板尺寸与普通等级一致
        local totalBonus = GS.getAdventurerRankBonus()
        local bgPad = lineH * 0.3
        local bgLeft = panelX - bgPad
        local badgeRight = cx + outerR
        local gapLeft = bgLeft - badgeRight
        local sideMargin = boardSize * 0.025
        local bgRight = bx + boardSize - sideMargin - gapLeft
        local bgW = bgRight - bgLeft
        -- 手动分两行描述文本
        local descLine1 = "历经千辛，您已成为灰界的神明。"
        local descLine2 = "您又能为灰界的人和魔带来什么呢？"
        local maxRows = totalBonus > 0 and 4 or 3  -- 标题 + 描述2行 + 可选加成
        local bgH = lineH * maxRows + lineH * 0.3

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bgLeft, panelY - bgPad, bgW, bgH + bgPad, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)

        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgText(vg, panelX, panelY, "您已晋升灰界神明", nil)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
        nvgText(vg, panelX, panelY + lineH, descLine1, nil)
        nvgText(vg, panelX, panelY + lineH * 2, descLine2, nil)
        if totalBonus > 0 then
            nvgFillColor(vg, nvgRGBA(200, 170, 80, 255))
            nvgText(vg, panelX, panelY + lineH * 3, "当前生效: 全属性+" .. totalBonus, nil)
        end
    end
end

-- ====================================================================
-- 印章动画：触发 / 更新
-- ====================================================================

--- 触发盖章动画（从大缩小 + 音效）
---@param questIdx number 委托索引
function M.triggerStampAnim(questIdx)
    M._stampAnim = {
        questIdx = questIdx,
        progress = 0,
        duration = 0.35,
    }
    -- 播放盖章音效
    if not M._stampSfx then
        M._stampSfx = cache:GetResource("Sound", "audio/sfx/stamp_hit.ogg")
    end
    if M._stampSfx then
        local Combat = require("Combat")
        local sc = Combat.scene_
        if sc then
            local node = sc:CreateChild("StampSfx")
            local src = node:CreateComponent("SoundSource")
            src.gain = 0.8 * GS.masterVolume
            src.autoRemoveMode = REMOVE_COMPONENT
            src:Play(M._stampSfx)
        end
    end
end

--- 每帧更新印章动画进度（由主循环调用）
---@param dt number deltaTime
function M.updateStampAnim(dt)
    local anim = M._stampAnim
    if not anim then return end
    if anim.progress >= 1.0 then return end
    anim.progress = math.min(1.0, anim.progress + dt / anim.duration)
end

return M
