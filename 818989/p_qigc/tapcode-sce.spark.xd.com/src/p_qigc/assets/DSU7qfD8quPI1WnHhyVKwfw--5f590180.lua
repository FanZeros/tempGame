-- ====================================================================
-- Renderer_Menus.lua — 菜单/弹窗/对话框绘制（从 Renderer.lua 拆分）
-- ====================================================================
-- 包含角色选择/创建/删除、主菜单、游戏结束、物品Tooltip、
-- 确认弹窗、技能装备弹窗、行动菜单、Debuff Tooltip
-- ====================================================================

local GS = require("GameState")
local ImageManager = require("ImageManager")
local Utils = require("Renderer_Utils")
local BanManager = require("BanManager")
local isHovered = Utils.isHovered
local drawHoverHighlight = Utils.drawHoverHighlight

local sub = {}

function sub.init(M)

-- ====================================================================
-- 主菜单背景视频管理
-- ====================================================================
local _menuVideoPlayer = nil   -- VideoPlayer 实例
local _menuVideoNvgHandle = nil -- NanoVG 图片句柄
local _menuVideoReady = false

--- 确保主菜单视频已创建并在播放
local function ensureMenuVideo()
    if _menuVideoPlayer then return end
    if not VideoPlayer then return end
    _menuVideoPlayer = VideoPlayer:new()
    if _menuVideoPlayer then
        local ok = _menuVideoPlayer:Load("video/主菜单.mp4", 1920, 1080)
        if ok then
            _menuVideoPlayer:SetVolume(0)
            _menuVideoPlayer:SetLoop(true)
            _menuVideoPlayer:Play()
        else
            _menuVideoPlayer = nil
        end
    end
end

--- 销毁主菜单视频
local function destroyMenuVideo()
    if _menuVideoPlayer then
        _menuVideoPlayer:Stop()
        _menuVideoPlayer = nil
    end
    _menuVideoNvgHandle = nil
    _menuVideoReady = false
end

--- 更新视频帧并绘制为全屏背景，返回是否成功绘制
local function drawMenuVideoBg(vg, W, H)
    ensureMenuVideo()
    if not _menuVideoPlayer then return false end
    _menuVideoPlayer:Update()
    if not _menuVideoReady and _menuVideoPlayer:IsReady() then
        _menuVideoReady = true
    end
    if _menuVideoReady then
        local tex = _menuVideoPlayer:GetTexture()
        if tex and not _menuVideoNvgHandle and nvgCreateVideo then
            _menuVideoNvgHandle = nvgCreateVideo(vg, tex)
        end
        if _menuVideoNvgHandle and _menuVideoNvgHandle > 0 then
            local videoW = _menuVideoPlayer:GetVideoWidth()
            local videoH = _menuVideoPlayer:GetVideoHeight()
            local scale = math.max(W / videoW, H / videoH)
            local drawW, drawH = videoW * scale, videoH * scale
            local ox, oy = (W - drawW) / 2, (H - drawH) / 2
            local imgPaint = nvgImagePattern(vg, ox, oy, drawW, drawH, 0, _menuVideoNvgHandle, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, W, H)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
            return true
        end
    end
    return false
end

--- 供外部在离开菜单状态时调用销毁视频
function M.destroyMenuVideo()
    destroyMenuVideo()
end

--- Loading + 旋转四芒星指示器（视频未就绪时显示在屏幕下方）
local function drawMenuLoadingIndicator(vg, W, H)
    local t = GetTime():GetElapsedTime()
    local cx = W * 0.5
    local cy = H * 0.85

    local fontSize = math.max(14, math.min(W, H) * 0.04)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textW = nvgTextBounds(vg, 0, 0, "Loading", nil)

    local starR = math.max(5, fontSize * 0.35)
    local gap = math.max(3, fontSize * 0.25)
    local totalW = textW + gap + starR * 2
    local startX = cx - totalW * 0.5

    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgText(vg, startX, cy, "Loading", nil)

    -- 旋转四芒星
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

--- 金色装饰边框（开始菜单 & 角色选择共用）
local function drawGoldBorder(vg, W, H)
    local borderInset = 12
    local borderW = W - borderInset * 2
    local borderH = H - borderInset * 2
    local ga = 180

    -- 外框：粗金线
    nvgBeginPath(vg)
    nvgRoundedRect(vg, borderInset, borderInset, borderW, borderH, 6)
    nvgStrokeWidth(vg, 3)
    nvgStrokeColor(vg, nvgRGBA(220, 180, 60, ga))
    nvgStroke(vg)

    -- 内框：细金线
    local innerInset = borderInset + 6
    nvgBeginPath(vg)
    nvgRoundedRect(vg, innerInset, innerInset, W - innerInset * 2, H - innerInset * 2, 4)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(255, 215, 80, math.floor(ga * 0.6)))
    nvgStroke(vg)

    -- 四角装饰：L 形角标
    local cornerLen = 30
    local cw = 2.5
    local cx, cy = borderInset, borderInset
    local gc = nvgRGBA(255, 200, 50, ga)
    nvgStrokeWidth(vg, cw)
    nvgStrokeColor(vg, gc)
    -- 左上
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy + cornerLen)
    nvgLineTo(vg, cx, cy)
    nvgLineTo(vg, cx + cornerLen, cy)
    nvgStroke(vg)
    -- 右上
    nvgBeginPath(vg)
    nvgMoveTo(vg, W - cx - cornerLen, cy)
    nvgLineTo(vg, W - cx, cy)
    nvgLineTo(vg, W - cx, cy + cornerLen)
    nvgStroke(vg)
    -- 左下
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, H - cy - cornerLen)
    nvgLineTo(vg, cx, H - cy)
    nvgLineTo(vg, cx + cornerLen, H - cy)
    nvgStroke(vg)
    -- 右下
    nvgBeginPath(vg)
    nvgMoveTo(vg, W - cx - cornerLen, H - cy)
    nvgLineTo(vg, W - cx, H - cy)
    nvgLineTo(vg, W - cx, H - cy - cornerLen)
    nvgStroke(vg)

    -- 上下中央装饰短横线
    local decoW = 60
    local decoAlpha = 140
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(255, 215, 80, decoAlpha))
    nvgBeginPath(vg)
    nvgMoveTo(vg, W / 2 - decoW, borderInset)
    nvgLineTo(vg, W / 2 + decoW, borderInset)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, W / 2 - decoW, H - borderInset)
    nvgLineTo(vg, W / 2 + decoW, H - borderInset)
    nvgStroke(vg)
end

-- ====================================================================
-- 绘制：角色选择界面
-- ====================================================================
function M.drawCharSelect()
    local vg = M.vg
    local W, H = GS.SCREEN_W, GS.SCREEN_H
    local time = GetTime():GetElapsedTime()

    -- 初始化选中槽位（默认选中上次活跃的角色）
    if not GS.charSelectSelectedSlot then
        GS.charSelectSelectedSlot = GS.charSlotMeta and GS.charSlotMeta.activeSlot
    end

    -- 背景：优先播放视频，回退到静态图
    local menuVideoOk = drawMenuVideoBg(vg, W, H)
    if not menuVideoOk then
        local startBg = ImageManager.lazyGet("bg_start", "image/title_start_new.png")
        if startBg ~= -1 then
            local imgW, imgH = nvgImageSize(vg, startBg)
            local scale = math.max(W / imgW, H / imgH)
            local drawW, drawH = imgW * scale, imgH * scale
            local imgPaint = nvgImagePattern(vg, (W - drawW) / 2, (H - drawH) / 2, drawW, drawH, 0, startBg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, W, H)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            M.drawBackground()
        end
    end

    -- 暗色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(10, 15, 30, 160))
    nvgFill(vg)

    -- 金色装饰边框
    drawGoldBorder(vg, W, H)

    nvgFontFace(vg, "sans")

    -- 标题
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgText(vg, W / 2 + 2, 42 + 2, "选择角色", nil)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, W / 2, 42, "选择角色", nil)

    -- 卡片布局（3×2 网格）
    local maxSlots = GS.MAX_CHAR_SLOTS
    local COLS, ROWS = 3, 2
    local gap, rowGap = 10, 10
    local cardW = math.min(130, (W - 80 - (COLS - 1) * gap) / COLS)
    local cardH = cardW * 1.35 * 0.8  -- 高度再缩小 1/5
    local totalW = COLS * cardW + (COLS - 1) * gap
    local totalH = ROWS * cardH + (ROWS - 1) * rowGap
    local startX = (W - totalW) / 2
    local startY = math.max(72, (H - totalH) / 2 - 10)

    GS.charSelectCardRects = {}
    GS.charSelectDeleteRects = {}

    for i = 1, maxSlots do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local cx = startX + col * (cardW + gap)
        local cy = startY + row * (cardH + rowGap)
        local slotInfo = GS.getSlotInfo(i)
        GS.charSelectCardRects[i] = { x = cx, y = cy, w = cardW, h = cardH }

        if slotInfo then
            -- 有角色的槽位：显示角色信息卡
            local cc = GS.CLASS_COLORS[slotInfo.class] or {120, 130, 150}

            -- 卡片背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cy, cardW, cardH, 8)
            nvgFillColor(vg, nvgRGBA(25, 30, 50, 220))
            nvgFill(vg)

            -- 职业色彩顶条
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cy, cardW, 6, 8)
            nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 200))
            nvgFill(vg)

            -- 金色选中边框
            if GS.charSelectSelectedSlot == i then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx - 1, cy - 1, cardW + 2, cardH + 2, 9)
                nvgStrokeWidth(vg, 2)
                nvgStrokeColor(vg, nvgRGBA(255, 215, 0, 200))
                nvgStroke(vg)
            else
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx, cy, cardW, cardH, 8)
                nvgStrokeWidth(vg, 1)
                nvgStrokeColor(vg, nvgRGBA(80, 90, 120, 150))
                nvgStroke(vg)
            end

            local imgSize = math.floor(cardW * 0.45)

            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

            -- 职业名（顶部，顶条下方）
            local className = GS.CLASS_NAMES[slotInfo.class] or slotInfo.class
            local classNameY = cy + 16
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 220))
            nvgText(vg, cx + cardW / 2, classNameY, className, nil)

            -- 职业图片（职业名下方）
            local classKey = slotInfo.class or "traveler"
            local avatarImg = M.classAvatars and M.classAvatars[classKey]
            if not avatarImg then
                avatarImg = M.classAvatars and M.classAvatars["traveler"]
            end
            local imgY = classNameY + 10
            if avatarImg then
                local imgX = cx + (cardW - imgSize) / 2
                local paint = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize, 0, avatarImg, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, imgX, imgY, imgSize, imgSize, 6)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
                -- 职业色边框
                nvgBeginPath(vg)
                nvgRoundedRect(vg, imgX, imgY, imgSize, imgSize, 6)
                nvgStrokeWidth(vg, 2)
                nvgStrokeColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 220))
                nvgStroke(vg)
            end

            -- 等级（图片下方）
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(255, 220, 100, 230))
            nvgText(vg, cx + cardW / 2, imgY + imgSize + 8, "Lv." .. (slotInfo.level or 1), nil)

            -- 角色名（卡片底部）
            local displayName = slotInfo.name or "无名"
            if #displayName > 15 then displayName = string.sub(displayName, 1, 15) .. ".." end
            nvgFontSize(vg, 16)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, cx + cardW / 2, cy + cardH - 14, displayName, nil)

            -- 删除按钮（右上角小 x）
            local delSize = 18
            local delX = cx + cardW - delSize - 2
            local delY = cy + 8
            GS.charSelectDeleteRects[i] = { x = delX, y = delY, w = delSize, h = delSize }

            nvgBeginPath(vg)
            nvgRoundedRect(vg, delX, delY, delSize, delSize, 3)
            nvgFillColor(vg, nvgRGBA(180, 40, 40, 120))
            nvgFill(vg)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(255, 200, 200, 200))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, delX + delSize / 2, delY + delSize / 2, "X", nil)
        else
            -- 空槽位：显示 "+" 创建按钮
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cy, cardW, cardH, 8)
            nvgFillColor(vg, nvgRGBA(30, 35, 55, 160))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cy, cardW, cardH, 8)
            nvgStrokeWidth(vg, 1.5)
            local pulse = math.floor(80 + 40 * math.sin(time * 2 + i))
            nvgStrokeColor(vg, nvgRGBA(100, 120, 160, pulse))
            nvgStroke(vg)

            -- 加号
            nvgFontSize(vg, 42)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(100, 120, 160, 180))
            nvgText(vg, cx + cardW / 2, cy + cardH / 2 - 12, "+", nil)

            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(100, 120, 160, 150))
            nvgText(vg, cx + cardW / 2, cy + cardH / 2 + 24, "创建角色", nil)
        end
    end

    -- 底部"进入灰界"按钮
    local selSlot = GS.charSelectSelectedSlot
    local hasSelection = selSlot and GS.getSlotInfo(selSlot) ~= nil
    local btnW, btnH = 140, 40
    local btnX = (W - btnW) / 2
    local btnY = math.min(startY + totalH + 15, H - 50)
    GS.charSelectEnterRect = { x = btnX, y = btnY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
    if hasSelection then
        nvgFillColor(vg, nvgRGBA(50, 80, 60, 230))
    else
        nvgFillColor(vg, nvgRGBA(60, 60, 60, 150))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
    nvgStrokeWidth(vg, 1.5)
    if hasSelection then
        nvgStrokeColor(vg, nvgRGBA(100, 220, 120, 200))
    else
        nvgStrokeColor(vg, nvgRGBA(100, 100, 100, 120))
    end
    nvgStroke(vg)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if GS.versionChecking then
        nvgFillColor(vg, nvgRGBA(255, 200, 100, 255))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "版本检测中……", nil)
    elseif GS.charSwitchSaving then
        -- [修复] 保存未完成时显示提示，防止玩家在数据未同步时切换角色
        nvgFillColor(vg, nvgRGBA(255, 200, 100, 255))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "存档同步中...", nil)
    elseif hasSelection then
        nvgFillColor(vg, nvgRGBA(200, 255, 200, 255))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "进入灰界", nil)
    else
        nvgFillColor(vg, nvgRGBA(140, 140, 140, 150))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "进入灰界", nil)
    end

    -- 版本号（进入灰界按钮下方）
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
    nvgText(vg, btnX + btnW / 2, btnY + btnH + 10, GS.APP_VERSION or "ver0.126", nil)

    -- 视频未就绪时在最上层显示 Loading 动画
    if not menuVideoOk then
        drawMenuLoadingIndicator(vg, W, H)
    end

    -- 封禁提示弹窗
    if GS.charSelectBanMsg then
        local msg = GS.charSelectBanMsg
        -- 半透明遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)
        -- 弹窗背景
        local popW, popH = 260, 80
        local popX, popY = (W - popW) / 2, (H - popH) / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, popX, popY, popW, popH, 10)
        nvgFillColor(vg, nvgRGBA(40, 20, 20, 240))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, popX, popY, popW, popH, 10)
        nvgStrokeWidth(vg, 2)
        nvgStrokeColor(vg, nvgRGBA(200, 60, 60, 220))
        nvgStroke(vg)
        -- 文字
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
        nvgText(vg, W / 2, H / 2, msg.text, nil)
    end

    -- 新角色确认弹窗叠加在最上层
    if GS.charNewConfirmSlot then
        M.drawNewCharConfirm()
    end

    -- 删除确认弹窗叠加在最上层
    if GS.charDeleteStep > 0 then
        M.drawDeleteConfirm()
    end

    -- 版本不一致提示弹窗（优先级最高，遮盖所有其他弹窗）
    if GS.versionMismatch then
        M.drawVersionMismatch()
    end
end

-- ====================================================================
-- 绘制：GM 封禁管理面板
-- ====================================================================
function M.drawGMBanPanel()
    local vg = M.vg
    local W, H = GS.SCREEN_W, GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    -- 面板尺寸
    local panelW = math.min(W * 0.85, 320)
    local panelH = math.min(H * 0.80, 380)
    local panelX = (W - panelW) / 2
    local panelY = (H - panelH) / 2
    local pad = 12

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(20, 15, 30, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgStrokeWidth(vg, 2)
    nvgStrokeColor(vg, nvgRGBA(200, 80, 80, 200))
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    local cx = panelX + panelW / 2
    local curY = panelY + pad

    -- 标题
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
    nvgText(vg, cx, curY + 10, "GM 指令面板", nil)
    curY = curY + 28

    -- ── 标签页 ──
    local activeTab = BanManager.getActiveTab()
    local tabW = (panelW - pad * 2) / 2
    local tabH = 24
    local tabY = curY
    local tabs = { { id = "ban", label = "封禁管理" }, { id = "restore", label = "存档修复" } }
    local tabRects = {}
    for i, tab in ipairs(tabs) do
        local tx = panelX + pad + (i - 1) * tabW
        local isActive = activeTab == tab.id
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW - 2, tabH, 4)
        nvgFillColor(vg, isActive and nvgRGBA(80, 50, 100, 240) or nvgRGBA(35, 28, 50, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW - 2, tabH, 4)
        nvgStrokeWidth(vg, 1)
        nvgStrokeColor(vg, isActive and nvgRGBA(180, 120, 220, 220) or nvgRGBA(100, 80, 130, 120))
        nvgStroke(vg)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, isActive and nvgRGBA(230, 200, 255, 255) or nvgRGBA(150, 130, 170, 200))
        nvgText(vg, tx + (tabW - 2) / 2, tabY + tabH / 2, tab.label, nil)
        tabRects[tab.id] = { x = tx, y = tabY, w = tabW - 2, h = tabH }
    end
    curY = curY + tabH + 6

    if activeTab == "ban" then
    -- ── 封禁管理 Tab ──

    -- 模式切换按钮
    local inputMode = BanManager.getInputMode()
    local modeBtnW = panelW - pad * 2
    local modeBtnH = 22
    local modeBtnX = panelX + pad
    local modeBtnY = curY
    local modeHover = GS.hoverX and GS.hoverY
        and GS.hoverX >= modeBtnX and GS.hoverX <= modeBtnX + modeBtnW
        and GS.hoverY >= modeBtnY and GS.hoverY <= modeBtnY + modeBtnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, modeBtnX, modeBtnY, modeBtnW, modeBtnH, 4)
    nvgFillColor(vg, modeHover and nvgRGBA(60, 50, 80, 240) or nvgRGBA(40, 35, 55, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, modeBtnX, modeBtnY, modeBtnW, modeBtnH, 4)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 180, 160))
    nvgStroke(vg)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local modeLabel = inputMode == "id" and "当前: ID模式 (点击切换昵称模式)" or "当前: 昵称模式 (点击切换ID模式)"
    nvgFillColor(vg, nvgRGBA(180, 170, 220, 255))
    nvgText(vg, modeBtnX + modeBtnW / 2, modeBtnY + modeBtnH / 2, modeLabel, nil)
    curY = curY + modeBtnH + 6

    -- 输入区域：[输入框] [封禁按钮]
    local inputW = panelW * 0.58
    local inputH = 28
    local inputX = panelX + pad
    local inputY = curY
    local banBtnW = panelW * 0.22
    local banBtnH = inputH
    local banBtnX = inputX + inputW + 8
    local banBtnY = curY

    -- 输入框
    local inputActive = BanManager.isInputActive()
    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 5)
    nvgFillColor(vg, inputActive and nvgRGBA(50, 40, 60, 255) or nvgRGBA(35, 30, 45, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 5)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, inputActive and nvgRGBA(200, 140, 140, 220) or nvgRGBA(120, 100, 140, 180))
    nvgStroke(vg)

    -- 输入文字
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local displayText = BanManager.getGMInputText()
    if #displayText == 0 then
        nvgFillColor(vg, nvgRGBA(100, 90, 130, 150))
        local placeholder = inputMode == "id" and "输入TapTap用户ID..." or "输入TapTap昵称..."
        nvgText(vg, inputX + 8, inputY + inputH / 2, placeholder, nil)
    else
        nvgFillColor(vg, nvgRGBA(230, 225, 240, 255))
        nvgText(vg, inputX + 8, inputY + inputH / 2, displayText, nil)
    end

    -- 光标闪烁
    if inputActive and #displayText >= 0 then
        local elapsed = GetTime():GetElapsedTime()
        if math.floor(elapsed * 2) % 2 == 0 then
            local cursorX = inputX + 8
            if #displayText > 0 then
                cursorX = cursorX + nvgTextBounds(vg, 0, 0, displayText, nil) + 2
            end
            nvgBeginPath(vg)
            nvgRect(vg, cursorX, inputY + 5, 2, inputH - 10)
            nvgFillColor(vg, nvgRGBA(200, 150, 150, 200))
            nvgFill(vg)
        end
    end

    -- 封禁按钮
    local isSearching = BanManager.isNicknameSearching()
    local banHover = (not isSearching) and GS.hoverX and GS.hoverY
        and GS.hoverX >= banBtnX and GS.hoverX <= banBtnX + banBtnW
        and GS.hoverY >= banBtnY and GS.hoverY <= banBtnY + banBtnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, banBtnX, banBtnY, banBtnW, banBtnH, 5)
    if isSearching then
        nvgFillColor(vg, nvgRGBA(80, 60, 60, 200))
    else
        nvgFillColor(vg, banHover and nvgRGBA(160, 50, 50, 240) or nvgRGBA(120, 40, 40, 220))
    end
    nvgFill(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, isSearching and 120 or 255))
    local banBtnLabel = isSearching and "搜索中" or (inputMode == "id" and "封禁" or "搜索封禁")
    nvgText(vg, banBtnX + banBtnW / 2, banBtnY + banBtnH / 2, banBtnLabel, nil)

    curY = curY + inputH + 8

    -- 状态消息
    local statusMsg = BanManager.getGMStatusMsg()
    if #statusMsg > 0 then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 100, 220))
        nvgText(vg, panelX + pad, curY + 6, statusMsg, nil)
        curY = curY + 18
    end

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX + pad, curY)
    nvgLineTo(vg, panelX + panelW - pad, curY)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(100, 80, 80, 120))
    nvgStroke(vg)
    curY = curY + 6

    -- 封禁列表标题
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 150, 150, 200))
    local banList = BanManager.getGMBanList()
    nvgText(vg, panelX + pad, curY + 6, "封禁列表 (" .. #banList .. ")", nil)
    curY = curY + 18

    -- 封禁列表内容区域
    local listTop = curY
    local closeBtnH = 28
    local listBottom = panelY + panelH - pad - closeBtnH - 10
    local listH = listBottom - listTop
    local itemH = 30
    local scrollOffset = BanManager.getScrollOffset()

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, panelX + pad, listTop, panelW - pad * 2, listH)

    local unbanBtns = {}
    for i, entry in ipairs(banList) do
        local iy = listTop + (i - 1) * itemH - scrollOffset
        if iy + itemH > listTop and iy < listBottom then
            -- 交替底色
            if i % 2 == 0 then
                nvgBeginPath(vg)
                nvgRect(vg, panelX + pad, iy, panelW - pad * 2, itemH)
                nvgFillColor(vg, nvgRGBA(40, 30, 40, 80))
                nvgFill(vg)
            end
            -- 用户 ID + 昵称
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 210, 230, 255))
            local idDisplay = tostring(entry.userId)
            if entry.nickname and #entry.nickname > 0 then
                idDisplay = idDisplay .. " (" .. entry.nickname .. ")"
            end
            nvgText(vg, panelX + pad + 6, iy + itemH / 2, idDisplay, nil)

            -- 时间
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(150, 140, 160, 180))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, panelX + panelW / 2, iy + itemH / 2, entry.time or "", nil)

            -- 解封按钮
            local ubW, ubH = 40, 20
            local ubX = panelX + panelW - pad - ubW - 4
            local ubY = iy + (itemH - ubH) / 2
            local ubHover = GS.hoverX and GS.hoverY
                and GS.hoverX >= ubX and GS.hoverX <= ubX + ubW
                and GS.hoverY >= ubY and GS.hoverY <= ubY + ubH
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ubX, ubY, ubW, ubH, 4)
            nvgFillColor(vg, ubHover and nvgRGBA(60, 100, 60, 230) or nvgRGBA(40, 70, 40, 200))
            nvgFill(vg)
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(150, 255, 150, 230))
            nvgText(vg, ubX + ubW / 2, ubY + ubH / 2, "解封", nil)

            table.insert(unbanBtns, { x = ubX, y = ubY, w = ubW, h = ubH, userId = entry.userId })
        end
    end

    nvgRestore(vg)

    -- 空列表提示
    if #banList == 0 then
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(120, 110, 130, 150))
        nvgText(vg, cx, listTop + listH / 2, "暂无封禁用户", nil)
    end

    -- 关闭按钮
    local closeBtnW = 80
    local closeBtnX = cx - closeBtnW / 2
    local closeBtnY = panelY + panelH - pad - closeBtnH
    local closeHover = GS.hoverX and GS.hoverY
        and GS.hoverX >= closeBtnX and GS.hoverX <= closeBtnX + closeBtnW
        and GS.hoverY >= closeBtnY and GS.hoverY <= closeBtnY + closeBtnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnW, closeBtnH, 6)
    nvgFillColor(vg, closeHover and nvgRGBA(70, 60, 80, 240) or nvgRGBA(50, 40, 60, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnW, closeBtnH, 6)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 180, 180))
    nvgStroke(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 210, 230, 255))
    nvgText(vg, closeBtnX + closeBtnW / 2, closeBtnY + closeBtnH / 2, "关闭", nil)

    -- 存储点击区域供 Input 使用
    BanManager.panelRects = {
        tabs = tabRects,
        modeBtn = { x = modeBtnX, y = modeBtnY, w = modeBtnW, h = modeBtnH },
        input = { x = inputX, y = inputY, w = inputW, h = inputH },
        banBtn = { x = banBtnX, y = banBtnY, w = banBtnW, h = banBtnH },
        close = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH },
        unbanBtns = unbanBtns,
        panel = { x = panelX, y = panelY, w = panelW, h = panelH },
        listArea = { x = panelX + pad, y = listTop, w = panelW - pad * 2, h = listH },
    }

    elseif activeTab == "restore" then
    -- ── 存档修复 Tab ──
    local closeBtnH = 28
    local ri = BanManager.getRestoreInput()

    -- 说明文字
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 150, 180, 180))
    nvgText(vg, panelX + pad, curY + 7, "指令写入排行榜，玩家上线后自动执行", nil)
    curY = curY + 18

    -- 用户ID输入框
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(180, 170, 200, 200))
    nvgText(vg, panelX + pad, curY + 7, "TapTap 用户 ID", nil)
    curY = curY + 16

    local uidInputW = panelW - pad * 2
    local uidInputH = 28
    local uidInputX = panelX + pad
    local uidInputY = curY
    local uidActive = BanManager.restoreIsUserIdActive()
    nvgBeginPath(vg)
    nvgRoundedRect(vg, uidInputX, uidInputY, uidInputW, uidInputH, 5)
    nvgFillColor(vg, uidActive and nvgRGBA(50, 40, 70, 255) or nvgRGBA(35, 30, 50, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, uidInputX, uidInputY, uidInputW, uidInputH, 5)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, uidActive and nvgRGBA(160, 120, 220, 220) or nvgRGBA(100, 80, 140, 160))
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    if #ri.userId == 0 then
        nvgFillColor(vg, nvgRGBA(100, 90, 130, 140))
        nvgText(vg, uidInputX + 8, uidInputY + uidInputH / 2, "输入数字ID...", nil)
    else
        nvgFillColor(vg, nvgRGBA(230, 220, 250, 255))
        nvgText(vg, uidInputX + 8, uidInputY + uidInputH / 2, ri.userId, nil)
    end
    if uidActive then
        local elapsed = GetTime():GetElapsedTime()
        if math.floor(elapsed * 2) % 2 == 0 then
            local cursorX = uidInputX + 8
            if #ri.userId > 0 then
                cursorX = cursorX + nvgTextBounds(vg, 0, 0, ri.userId, nil) + 2
            end
            nvgBeginPath(vg)
            nvgRect(vg, cursorX, uidInputY + 5, 2, uidInputH - 10)
            nvgFillColor(vg, nvgRGBA(180, 140, 220, 200))
            nvgFill(vg)
        end
    end
    curY = curY + uidInputH + 10

    -- 槽位选择
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 170, 200, 200))
    nvgText(vg, panelX + pad, curY + 7, "角色槽位", nil)
    curY = curY + 16

    local slotBtnW = math.floor((panelW - pad * 2 - 5 * 5) / 6)
    local slotBtnH = 24
    local slotBtns = {}
    for i = 1, 6 do
        local sx = panelX + pad + (i - 1) * (slotBtnW + 5)
        local sy = curY
        local isActive = ri.slotIdx == i
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotBtnW, slotBtnH, 4)
        nvgFillColor(vg, isActive and nvgRGBA(90, 60, 130, 240) or nvgRGBA(40, 32, 55, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotBtnW, slotBtnH, 4)
        nvgStrokeWidth(vg, 1)
        nvgStrokeColor(vg, isActive and nvgRGBA(180, 130, 230, 220) or nvgRGBA(90, 70, 120, 120))
        nvgStroke(vg)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, isActive and nvgRGBA(240, 220, 255, 255) or nvgRGBA(160, 145, 185, 200))
        nvgText(vg, sx + slotBtnW / 2, sy + slotBtnH / 2, tostring(i), nil)
        slotBtns[i] = { x = sx, y = sy, w = slotBtnW, h = slotBtnH, slot = i }
    end
    curY = curY + slotBtnH + 10

    -- 备份序号选择
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 170, 200, 200))
    nvgText(vg, panelX + pad, curY + 7, "备份序号", nil)
    curY = curY + 16

    local bakLabels = { "1 最新", "2 中间", "3 最旧" }
    local bakBtnW = math.floor((panelW - pad * 2 - 2 * 6) / 3)
    local bakBtnH = 24
    local bakBtns = {}
    for i = 1, 3 do
        local bx = panelX + pad + (i - 1) * (bakBtnW + 6)
        local by = curY
        local isActive = ri.backupIndex == i
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bakBtnW, bakBtnH, 4)
        nvgFillColor(vg, isActive and nvgRGBA(60, 90, 130, 240) or nvgRGBA(35, 45, 65, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bakBtnW, bakBtnH, 4)
        nvgStrokeWidth(vg, 1)
        nvgStrokeColor(vg, isActive and nvgRGBA(100, 160, 220, 220) or nvgRGBA(70, 90, 120, 120))
        nvgStroke(vg)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, isActive and nvgRGBA(180, 220, 255, 255) or nvgRGBA(140, 155, 180, 200))
        nvgText(vg, bx + bakBtnW / 2, by + bakBtnH / 2, bakLabels[i], nil)
        bakBtns[i] = { x = bx, y = by, w = bakBtnW, h = bakBtnH, backupIndex = i }
    end
    curY = curY + bakBtnH + 10

    -- 状态消息
    if #ri.statusMsg > 0 then
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 220, 120, 220))
        nvgText(vg, panelX + pad, curY + 6, ri.statusMsg, nil)
        curY = curY + 18
    end

    -- 发送 + 撤销 双按钮（左右排列）
    local dualBtnH = 30
    local dualBtnY = panelY + panelH - pad - closeBtnH - 10 - dualBtnH - 6
    local dualBtnGap = 6
    local dualBtnTotalW = panelW - pad * 2
    local sendBtnW = math.floor(dualBtnTotalW * 0.62)
    local cancelBtnW = dualBtnTotalW - sendBtnW - dualBtnGap
    local sendBtnH = dualBtnH
    local sendBtnX = panelX + pad
    local sendBtnY = dualBtnY
    local cancelBtnX = sendBtnX + sendBtnW + dualBtnGap
    local cancelBtnY = dualBtnY

    local sendHover = GS.hoverX and GS.hoverY
        and GS.hoverX >= sendBtnX and GS.hoverX <= sendBtnX + sendBtnW
        and GS.hoverY >= sendBtnY and GS.hoverY <= sendBtnY + sendBtnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sendBtnX, sendBtnY, sendBtnW, sendBtnH, 6)
    nvgFillColor(vg, sendHover and nvgRGBA(60, 120, 60, 240) or nvgRGBA(40, 85, 40, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sendBtnX, sendBtnY, sendBtnW, sendBtnH, 6)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 160))
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 255, 160, 255))
    nvgText(vg, sendBtnX + sendBtnW / 2, sendBtnY + sendBtnH / 2, "下发存档修复指令", nil)

    -- 撤销按钮
    local cancelHover = GS.hoverX and GS.hoverY
        and GS.hoverX >= cancelBtnX and GS.hoverX <= cancelBtnX + cancelBtnW
        and GS.hoverY >= cancelBtnY and GS.hoverY <= cancelBtnY + dualBtnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, cancelBtnY, cancelBtnW, dualBtnH, 6)
    nvgFillColor(vg, cancelHover and nvgRGBA(120, 60, 40, 240) or nvgRGBA(85, 40, 30, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelBtnX, cancelBtnY, cancelBtnW, dualBtnH, 6)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(200, 120, 100, 160))
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 180, 160, 255))
    nvgText(vg, cancelBtnX + cancelBtnW / 2, cancelBtnY + dualBtnH / 2, "撤销指令", nil)

    -- 关闭按钮（restore tab 共用）
    local closeBtnW2 = 80
    local closeBtnX2 = cx - closeBtnW2 / 2
    local closeBtnY2 = panelY + panelH - pad - closeBtnH
    local closeHover2 = GS.hoverX and GS.hoverY
        and GS.hoverX >= closeBtnX2 and GS.hoverX <= closeBtnX2 + closeBtnW2
        and GS.hoverY >= closeBtnY2 and GS.hoverY <= closeBtnY2 + closeBtnH
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeBtnX2, closeBtnY2, closeBtnW2, closeBtnH, 6)
    nvgFillColor(vg, closeHover2 and nvgRGBA(70, 60, 80, 240) or nvgRGBA(50, 40, 60, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeBtnX2, closeBtnY2, closeBtnW2, closeBtnH, 6)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 180, 180))
    nvgStroke(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 210, 230, 255))
    nvgText(vg, closeBtnX2 + closeBtnW2 / 2, closeBtnY2 + closeBtnH / 2, "关闭", nil)

    BanManager.panelRects = {
        tabs = tabRects,
        close = { x = closeBtnX2, y = closeBtnY2, w = closeBtnW2, h = closeBtnH },
        panel = { x = panelX, y = panelY, w = panelW, h = panelH },
        restoreUidInput = { x = uidInputX, y = uidInputY, w = uidInputW, h = uidInputH },
        restoreSendBtn   = { x = sendBtnX,   y = sendBtnY,   w = sendBtnW,   h = sendBtnH },
        restoreCancelBtn = { x = cancelBtnX, y = cancelBtnY, w = cancelBtnW, h = dualBtnH },
        restoreSlotBtns = slotBtns,
        restoreBakBtns = bakBtns,
    }

    end -- end activeTab
end

-- ====================================================================
-- 绘制：角色创建界面
-- ====================================================================
function M.drawCharCreate()
    local vg = M.vg
    local W, H = GS.SCREEN_W, GS.SCREEN_H
    local time = GetTime():GetElapsedTime()

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(15, 18, 35, 255))
    nvgFill(vg)

    nvgFontFace(vg, "sans")

    -- 标题
    nvgFontSize(vg, 32)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, W / 2, 36, "创建新角色", nil)

    -- 角色名区域
    local nameBoxW = math.min(280, W * 0.7)
    local nameBoxH = 36
    local nameBoxX = (W - nameBoxW) / 2
    local nameBoxY = 65

    nvgBeginPath(vg)
    nvgRoundedRect(vg, nameBoxX, nameBoxY, nameBoxW, nameBoxH, 6)
    nvgFillColor(vg, nvgRGBA(30, 35, 55, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nameBoxX, nameBoxY, nameBoxW, nameBoxH, 6)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(100, 110, 140, 150))
    nvgStroke(vg)

    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local displayName = GS.charCreateName
    if displayName == "" then displayName = "随机名称" end
    nvgFillColor(vg, nvgRGBA(255, 255, 255, displayName == "随机名称" and 120 or 240))
    nvgText(vg, W / 2, nameBoxY + nameBoxH / 2, displayName, nil)

    -- 换名按钮（骰子图标）
    local rerollSize = nameBoxH - 4
    local rerollX = nameBoxX + nameBoxW + 6
    local rerollY = nameBoxY + 2
    GS.charCreateRerollRect = { x = rerollX, y = rerollY, w = rerollSize, h = rerollSize }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, rerollX, rerollY, rerollSize, rerollSize, 4)
    nvgFillColor(vg, nvgRGBA(60, 70, 100, 200))
    nvgFill(vg)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 220, 240, 220))
    nvgText(vg, rerollX + rerollSize / 2, rerollY + rerollSize / 2, "换", nil)

    -- 职业选择区域
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 190, 220, 200))
    nvgText(vg, W / 2, nameBoxY + nameBoxH + 20, "选择职业", nil)

    local classList = GS.CLASS_LIST
    local classCount = #classList
    local classCardW = math.min(100, (W - 30) / classCount - 6)
    local classCardH = classCardW * 1.3
    local classTotalW = classCount * classCardW + (classCount - 1) * 6
    local classStartX = (W - classTotalW) / 2
    local classStartY = nameBoxY + nameBoxH + 38

    GS.charCreateClassRects = {}

    for idx, classId in ipairs(classList) do
        local cx = classStartX + (idx - 1) * (classCardW + 6)
        local cc = GS.CLASS_COLORS[classId] or {120, 130, 150}
        local selected = (GS.charCreateClass == classId)

        GS.charCreateClassRects[idx] = { x = cx, y = classStartY, w = classCardW, h = classCardH, classId = classId }

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, classStartY, classCardW, classCardH, 8)
        if selected then
            nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 60))
        else
            nvgFillColor(vg, nvgRGBA(25, 30, 50, 200))
        end
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, classStartY, classCardW, classCardH, 8)
        nvgStrokeWidth(vg, selected and 2 or 1)
        if selected then
            nvgStrokeColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 240))
        else
            nvgStrokeColor(vg, nvgRGBA(80, 90, 120, 120))
        end
        nvgStroke(vg)

        -- 职业色顶条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, classStartY, classCardW, 5, 8)
        nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], selected and 240 or 120))
        nvgFill(vg)

        -- 职业名
        local className = GS.CLASS_NAMES[classId] or classId
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, selected and 255 or 180))
        nvgText(vg, cx + classCardW / 2, classStartY + classCardH / 2, className, nil)
    end

    -- 底部按钮区域
    local btnW = 100
    local btnH = 34
    local btnY = classStartY + classCardH + 24
    local gap = 20
    local totalBtnW = btnW * 2 + gap
    local btnStartX = (W - totalBtnW) / 2

    -- 取消按钮
    local cancelX = btnStartX
    GS.charCreateBackRect = { x = cancelX, y = btnY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnY, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBA(60, 50, 70, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnY, btnW, btnH, 6)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBA(150, 140, 160, 150))
    nvgStroke(vg)
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 240))
    nvgText(vg, cancelX + btnW / 2, btnY + btnH / 2, "取消", nil)

    -- 确认按钮
    local confirmX = btnStartX + btnW + gap
    GS.charCreateConfirmRect = { x = confirmX, y = btnY, w = btnW, h = btnH }
    local canConfirm = GS.charCreateClass ~= nil

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnY, btnW, btnH, 6)
    if canConfirm then
        nvgFillColor(vg, nvgRGBA(40, 100, 60, 220))
    else
        nvgFillColor(vg, nvgRGBA(50, 50, 60, 180))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnY, btnW, btnH, 6)
    nvgStrokeWidth(vg, 1)
    if canConfirm then
        nvgStrokeColor(vg, nvgRGBA(100, 220, 120, 180))
    else
        nvgStrokeColor(vg, nvgRGBA(80, 80, 100, 120))
    end
    nvgStroke(vg)
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, canConfirm and 240 or 100))
    nvgText(vg, confirmX + btnW / 2, btnY + btnH / 2, "创建", nil)
end

-- ====================================================================
-- 绘制：新建角色确认弹窗
-- ====================================================================
function M.drawNewCharConfirm()
    local vg = M.vg
    local W, H = GS.SCREEN_W, GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗面板
    local panelW = 300
    local panelH = 130
    local panelX = (W - panelW) / 2
    local panelY = (H - panelH) / 2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(30, 30, 45, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(120, 120, 160, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFontSize(vg, 17)
    nvgFillColor(vg, nvgRGBA(220, 220, 240, 255))
    nvgText(vg, W / 2, panelY + 32, "确认创建新角色？", nil)

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 200))
    nvgText(vg, W / 2, panelY + 56, "将在此槽位开启一段新的旅程", nil)

    -- 按钮
    local btnW = 90
    local btnH = 32
    local btnY = panelY + panelH - btnH - 16
    local gap = 20
    local totalBtnW = btnW * 2 + gap
    local btnStartX = (W - totalBtnW) / 2

    -- 取消按钮
    local cancelX = btnStartX
    GS.charNewCancelRect = { x = cancelX, y = btnY, w = btnW, h = btnH }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnY, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBA(60, 60, 80, 220))
    nvgFill(vg)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 240))
    nvgText(vg, cancelX + btnW / 2, btnY + btnH / 2, "取消", nil)

    -- 确认按钮
    local confirmX = btnStartX + btnW + gap
    GS.charNewConfirmRect = { x = confirmX, y = btnY, w = btnW, h = btnH }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnY, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBA(50, 100, 160, 230))
    nvgFill(vg)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 230, 255, 255))
    nvgText(vg, confirmX + btnW / 2, btnY + btnH / 2, "确认", nil)
end

-- ====================================================================
-- 绘制：角色删除确认弹窗
-- ====================================================================
function M.drawDeleteConfirm()
    local vg = M.vg
    local W, H = GS.SCREEN_W, GS.SCREEN_H

    -- 全屏半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗面板
    local panelW = math.min(260, W * 0.7)
    local panelH = 160
    local panelX = (W - panelW) / 2
    local panelY = (H - panelH) / 2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(30, 25, 45, 240))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(200, 60, 60, 180))
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 获取要删除的角色信息
    local slotInfo = GS.getSlotInfo(GS.charDeleteSlotIdx or 0)
    local charDesc = ""
    if slotInfo then
        local className = GS.CLASS_NAMES[slotInfo.class] or slotInfo.class
        charDesc = (slotInfo.name or "无名") .. " (" .. className .. " Lv." .. (slotInfo.level or 1) .. ")"
    end

    if GS.charDeleteStep == 1 then
        -- 第一次确认
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 100, 80, 255))
        nvgText(vg, W / 2, panelY + 30, "确认删除角色？", nil)

        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(220, 220, 230, 220))
        nvgText(vg, W / 2, panelY + 55, charDesc, nil)

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(255, 180, 150, 180))
        nvgText(vg, W / 2, panelY + 75, "该操作不可撤销！", nil)
    elseif GS.charDeleteStep == 2 then
        -- 第二次确认（3秒冷却）
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 60, 40, 255))
        nvgText(vg, W / 2, panelY + 30, "再次确认删除！", nil)

        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(220, 220, 230, 220))
        nvgText(vg, W / 2, panelY + 55, charDesc, nil)

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(255, 150, 120, 200))
        nvgText(vg, W / 2, panelY + 75, "角色数据将永久删除！", nil)
    end

    -- 按钮区域
    local btnW = 90
    local btnH = 32
    local btnY = panelY + panelH - btnH - 18
    local gap = 20
    local totalBtnW = btnW * 2 + gap
    local btnStartX = (W - totalBtnW) / 2

    -- 取消按钮
    local cancelX = btnStartX
    GS.charDeleteCancelRect = { x = cancelX, y = btnY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnY, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBA(60, 60, 80, 220))
    nvgFill(vg)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 240))
    nvgText(vg, cancelX + btnW / 2, btnY + btnH / 2, "取消", nil)

    -- 确认删除按钮
    local confirmX = btnStartX + btnW + gap
    GS.charDeleteConfirmRect = { x = confirmX, y = btnY, w = btnW, h = btnH }

    local cooldownActive = GS.charDeleteStep == 2 and GS.charDeleteTimer > 0
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnY, btnW, btnH, 6)
    if cooldownActive then
        nvgFillColor(vg, nvgRGBA(80, 40, 40, 150))
    else
        nvgFillColor(vg, nvgRGBA(160, 40, 30, 220))
    end
    nvgFill(vg)

    nvgFontSize(vg, 15)
    if cooldownActive then
        nvgFillColor(vg, nvgRGBA(200, 150, 150, 180))
        local sec = math.ceil(GS.charDeleteTimer)
        nvgText(vg, confirmX + btnW / 2, btnY + btnH / 2, "等待(" .. sec .. "s)", nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 220, 200, 255))
        if GS.charDeleteStep == 1 then
            nvgText(vg, confirmX + btnW / 2, btnY + btnH / 2, "确认", nil)
        else
            nvgText(vg, confirmX + btnW / 2, btnY + btnH / 2, "永久删除", nil)
        end
    end
end

-- ====================================================================
-- 绘制：版本不一致提示弹窗
-- ====================================================================
function M.drawVersionMismatch()
    local vg = M.vg
    local W, H = GS.SCREEN_W, GS.SCREEN_H

    -- 全屏半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    -- 弹窗尺寸（宽不超过 85% 屏宽，高不超过 55% 屏高）
    local panelW  = math.min(320, W * 0.85)
    local panelH  = math.min(190, H * 0.55)
    local panelX  = (W - panelW) / 2
    local panelY  = (H - panelH) / 2
    local padX    = 16                   -- 左右内边距
    local innerW  = panelW - padX * 2    -- 文本可用宽度

    -- 背景面板
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(35, 20, 10, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgStrokeWidth(vg, 2)
    nvgStrokeColor(vg, nvgRGBA(220, 120, 30, 200))
    nvgStroke(vg)

    nvgFontFace(vg, "sans")

    -- 标题（单行居中，顶部 14px 内边距）
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg, 17)
    nvgFillColor(vg, nvgRGBA(255, 160, 50, 255))
    nvgText(vg, panelX + panelW / 2, panelY + 14, "检测到新版本，需要更新", nil)

    -- 正文：nvgTextBox 自动换行，左对齐，行高 1.5
    -- nvgTextBox(vg, x, y, breakRowWidth, str, nil)
    -- x 为文本区左边，breakRowWidth 为可用宽度
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 13)
    nvgTextLineHeight(vg, 1.5)
    nvgFillColor(vg, nvgRGBA(220, 200, 170, 230))
    nvgTextBox(vg, panelX + padX, panelY + 46, innerW,
        "请重新启动游戏更新至最新版本，以免存档数据丢失。" ..
        "可能需要多次尝试，感谢您的理解。", nil)

    -- 「我知道了」按钮（居中，锚定面板底部）
    local btnW = 120
    local btnH = 34
    local btnX = (W - btnW) / 2
    local btnY = panelY + panelH - btnH - 14

    GS.versionMismatchDismissRect = { x = btnX, y = btnY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
    nvgFillColor(vg, nvgRGBA(160, 80, 20, 220))
    nvgFill(vg)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(255, 230, 180, 255))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "我知道了", nil)
end

-- ====================================================================
-- 绘制：脱离卡死确认弹窗
-- ====================================================================
function M.drawUnstuckConfirm()
    local vg = M.vg
    local W, H = GS.SCREEN_W, GS.SCREEN_H

    -- 全屏半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗面板
    local panelW = math.min(260, W * 0.7)
    local panelH = 140
    local panelX = (W - panelW) / 2
    local panelY = (H - panelH) / 2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(30, 25, 45, 240))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 180))
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, W / 2, panelY + 28, "脱离卡死", nil)

    -- 说明文字
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(220, 220, 230, 220))
    nvgText(vg, W / 2, panelY + 52, "将重置当前小关状态", nil)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(200, 180, 140, 180))
    nvgText(vg, W / 2, panelY + 68, "已领取宝箱的小关会跳到出口阶段", nil)

    -- 按钮区域
    local btnW = 90
    local btnH = 32
    local btnY = panelY + panelH - btnH - 16
    local gap = 20
    local totalBtnW = btnW * 2 + gap
    local btnStartX = (W - totalBtnW) / 2

    -- 取消按钮
    local cancelX = btnStartX
    GS._unstuckCancelBtnRect = { x = cancelX, y = btnY, w = btnW, h = btnH }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnY, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBA(60, 60, 80, 220))
    nvgFill(vg)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 240))
    nvgText(vg, cancelX + btnW / 2, btnY + btnH / 2, "取消", nil)

    -- 确认按钮
    local confirmX = btnStartX + btnW + gap
    GS._unstuckConfirmBtnRect = { x = confirmX, y = btnY, w = btnW, h = btnH }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnY, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBA(180, 140, 40, 220))
    nvgFill(vg)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
    nvgText(vg, confirmX + btnW / 2, btnY + btnH / 2, "确认", nil)
end

-- ====================================================================
-- 绘制：菜单
-- ====================================================================
function M.drawMenu()
    local vg = M.vg

    -- 开始界面背景：优先播放视频，回退到静态图
    local menuVideoOk = drawMenuVideoBg(vg, GS.SCREEN_W, GS.SCREEN_H)
    if not menuVideoOk then
        local startBg = ImageManager.lazyGet("bg_start", "image/title_start_new.png")
        if startBg ~= -1 then
            local imgW, imgH = nvgImageSize(vg, startBg)
            local scale = math.max(GS.SCREEN_W / imgW, GS.SCREEN_H / imgH)
            local drawW, drawH = imgW * scale, imgH * scale
            local ox, oy = (GS.SCREEN_W - drawW) / 2, (GS.SCREEN_H - drawH) / 2
            local imgPaint = nvgImagePattern(vg, ox, oy, drawW, drawH, 0, startBg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            M.drawBackground()
        end
    end

    -- 半透明暗色遮罩，让文字更清晰
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
    nvgFillColor(vg, nvgRGBA(10, 15, 30, 120))
    nvgFill(vg)

    -- 金色装饰边框
    local W, H = GS.SCREEN_W, GS.SCREEN_H
    local time = GetTime():GetElapsedTime()
    drawGoldBorder(vg, W, H)

    nvgFontFace(vg, "sans")

    local titleSize = GS.isLandscape and 52 or 38
    nvgFontSize(vg, titleSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgText(vg, GS.SCREEN_W / 2 + 3, GS.SCREEN_H / 2 - 50 + 3, "灰界：我重生异世", nil)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2 - 50, "灰界：我重生异世", nil)

    local blink = math.floor(180 + 75 * math.sin(time * 3))
    nvgFontSize(vg, 24)
    if GS.preloadStatus == "loading" then
        nvgFillColor(vg, nvgRGBA(180, 190, 220, 180))
        nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2 + 20, "正在加载存档...", nil)
    elseif GS.preloadStatus == "error" then
        nvgFillColor(vg, nvgRGBA(255, 100, 80, 255))
        nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2 + 20, "存档加载失败，点击重试", nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, blink))
        nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2 + 20, "点击开始游戏", nil)
    end

    -- 视频未就绪时在最上层显示 Loading 动画
    if not menuVideoOk then
        drawMenuLoadingIndicator(vg, GS.SCREEN_W, GS.SCREEN_H)
    end
end

-- ====================================================================
-- 绘制：游戏结束
-- ====================================================================
function M.drawGameOver()
    local vg = M.vg
    M.drawBackground()

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
    nvgFillColor(vg, nvgRGBA(10, 12, 25, 160))
    nvgFill(vg)

    nvgFontFace(vg, "sans")

    nvgFontSize(vg, 50)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
    nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2 - 60, "游戏结束", nil)

    nvgFontSize(vg, 30)
    nvgFillColor(vg, nvgRGBA(255, 215, 0, 255))
    nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2, "得分: " .. GS.score, nil)

    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(180, 190, 220, 255))
    local endStageName = GS.STAGE_DEFS[GS.currentStage] and GS.STAGE_DEFS[GS.currentStage].name or ("关卡" .. GS.currentStage)
    nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2 + 40, endStageName .. " · 坚持了 " .. GS.turnNumber .. " 回合", nil)

    local time = GetTime():GetElapsedTime()
    local blink = math.floor(180 + 75 * math.sin(time * 3))
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, blink))
    nvgText(vg, GS.SCREEN_W / 2, GS.SCREEN_H / 2 + 100, "点击返回菜单", nil)
end

-- ====================================================================
-- 物品悬停信息面板（内部绘制函数）
-- headerText: 可选顶部标题（如"当前装备"），headerColor: 标题颜色
-- showBtn: 是否显示装备/卸下按钮
-- 返回 { x, y, w, h } 面板矩形
-- ====================================================================
local function drawTooltipPanel(vg, item, px, py, pw, showBtn, isEquipSource, headerText, headerColor)
    local lineH = 22
    local padX = 12
    local padY = 10
    local btnH = 28
    local descFontSize = 13
    local maxTextW = pw - padX * 2

    -- 计算内容行数
    local lines = {}
    -- 深渊兑换预览模式：tooltipSource 为 abyss_exchange 且模板有 exchangePreview 时使用占位文本
    local exchangePreview = nil
    if GS.tooltipSource == "abyss_exchange" then
        local ep = item.exchangePreview
        if not ep and item.id then
            local t = GS.itemTemplates and GS.itemTemplates[item.id]
            ep = t and t.exchangePreview
        end
        exchangePreview = ep
    end
    if headerText then
        lines[#lines + 1] = { type = "header", text = headerText, color = headerColor or {255, 215, 0} }
        lines[#lines + 1] = { type = "sep" }
    end
    local displayName = item.name or "未知"
    lines[#lines + 1] = { type = "name", text = displayName }
    -- 精炼韧性 & 脆化状态
    if item.refineSlots then
        GS.ensureRefineToughness(item)
        local maxT = GS.getMaxRefineToughness(item)
        local curT = item.refineToughness or maxT
        local tText = "精炼韧性: " .. curT .. "/" .. maxT
        lines[#lines + 1] = { type = "toughness", text = tText, curT = curT, maxT = maxT, brittle = item.brittle }
    elseif item.brittle then
        lines[#lines + 1] = { type = "toughness", brittle = true }
    end
    local catLabel = item.weaponTag or item.category or ""
    local catLevel = catLabel .. "  Lv." .. (item.level or 1)
    local playerLv = GS.player and GS.player.level or 1
    local lvTooLow = (item.consumable or item.slot) and item.level and playerLv < item.level
    local classMismatch = false
    if item.slot == "weapon_r" and item.weaponTag then
        local a = GS.CLASS_WEAPON_R and GS.CLASS_WEAPON_R[GS.currentClass]
        classMismatch = a and not a[item.weaponTag]
    elseif item.slot == "weapon_l" and item.offhandTag then
        classMismatch = not GS.checkOffhand(item.offhandTag)
    end
    local subRed = (lvTooLow or classMismatch) and {255, 80, 80} or nil
    lines[#lines + 1] = { type = "sub", text = catLevel, color = subRed }
    -- 生效唯一标记（朱莉的面纱 + 卓越装备，不含材料/消耗品等非装备物品）
    if item.templateId == "gem_rainbow_masterwork" or (item.category == "宝石" and item.id == "gem_rainbow_masterwork")
       or (item.rarity == "superior" and item.slot) then
        lines[#lines + 1] = { type = "unique_active", text = "（生效唯一）" }
    end
    local rarityDef = GS.RARITY[item.rarity]
    if rarityDef then
        lines[#lines + 1] = { type = "rarity", text = rarityDef.name, color = rarityDef.color }
    end
    local hasStats = item.effects or item.special or (item.consumable and type(item.consumable) == "table")
    if hasStats and not exchangePreview then
        lines[#lines + 1] = { type = "sep" }
    end
    -- 隐藏的内部属性（不显示在面板上）
    local hiddenAttrs = { batFangCount = true, potionHealBonusMaxLv = true, randomSub = true,
                          meteorStunChance = true, blizzardFreezeDuration = true }
    if item.effects and not exchangePreview then
        local effectNames = { atk = "物理攻击力", def = "物理防御力", hp = "生命值", mp = "魔法值",
                              spd = "速度", crit = "暴击率",
                              str = "力量", wis = "智慧", agi = "敏捷", con = "体质",
                              foc = "专注", per = "感知", wil = "意念", luk = "幸运", cha = "魅力",
                              hpRegen = "HP自然回复", mpRegen = "MP自然回复",
                              hpDrain = "HP流失", critVal = "物理暴击值", dodge = "闪避值",
                              hit = "命中值", maxMonsters = "怪物出现上限", spawnCount = "怪物出现数量",
                              critDmg = "物理暴击伤害", lifesteal = "吸血",
                              batFangLifesteal = "吸血",
                              physLifesteal = "物理吸血", magLifesteal = "法术吸血",
                              manaLeech = "魔力回收",
                              moveRange = "移动距离", atkSpeed = "攻击速度",
                              castSpeed = "吟唱速度",
                              mAtk = "魔法攻击力", mDef = "魔法防御力", mdef = "魔法防御力", avoidCrit = "避开要害",
                              mCritVal = "魔法暴击值", mCritDmg = "魔法暴击伤害",
                              atkRange = "攻击距离",
                              magDmgBonus = "魔法伤害加成",
                              fireDmgBonus = "火焰伤害", iceDmgBonus = "冰冻伤害",
                              elecDmgBonus = "雷电伤害", lightDmgBonus = "神圣伤害",
                              ragingFireBonus = "燃火",
                              radianceNearDmgBonus = "辉光近处增伤",
                              swordDmgBonus = "剑类伤害", daggerDmgBonus = "匕首伤害",
                              maceDmgBonus = "钉锤伤害", bowDmgBonus = "弓类伤害",
                              staffDmgBonus = "法杖伤害", physDmgBonus = "物理伤害",
                              arsenalScatter = "散射",
                              healStoreRate = "治疗存储", healReleaseRate = "存储释放",
                              furyStackPerCrit = "狂怒叠加", furyMaxStacks = "狂怒上限", furyDecayOnNonCrit = "狂怒衰减",
                              pDmgReduce = "物理伤害减免",
                              mDmgReduce = "魔法伤害减免",
                              blockHeal = "格挡回血", onHitHeal = "命中回血",
                              castHeal = "施法回血", onMagDmgHeal = "魔伤回血",
                              castMpRegen = "施法回魔", onHitDefReduce = "命中减防",
                              resFire = "火焰抗性", resIce = "寒冰抗性", resElec = "雷电抗性",
                              resLight = "神圣抗性", resDark = "暗影抗性", resNature = "自然抗性",
                              holySpringBlessing = "圣泉祝福", shelterBlessing = "庇护祝福",
                              onKillHealHp = "击杀回血", onDamageTakenHeal = "受伤回血",
                              potionHealBonus = "药水额外治疗",
                              healEffectPct = "治疗效果加成",
                              bounceDmgInc = "弹射伤害递增",
                              agiToAtkSpeedEff = "每5点敏捷，攻速额外",
                              perToHealEffPct = "每5点感知，治疗效果",
                              nearDmgBonus = "近处敌人伤害",
                              counterComboMax = "反击连击上限",
                              counterComboConRate = "体质连击概率",
                              dodgeCounterChanceBonus = "闪避反击概率",
                              dodgeCounterDmgBonus = "闪避反击伤害",
                              defPct = "物理防御加成",
                              mDefPct = "魔法防御加成",
                              deferDmgPct = "受伤缓冲",
                              allEleRes = "所有元素抗性",
                              hitVal = "命中值",
                              illusionDmgPct = "幻影伤害提高",
                              illusionSearchRange = "幻影检索范围",
                              illusionSingleExtra = "幻影集中攻击",
                              scatterAtkPer = "每1点散射提高物理攻击力",
                              atkRangeHitPer = "每1格最大攻击距离提高命中值",
                              derivStormDmgBonus = "护甲清空时触发衍生飓风，衍生飓风伤害倍率提高",
                              illusionSingleDmgPct = "幻影集中伤害",
                              distDmgPctPerGrid = "距离伤害加成",
                              radianceDmgBonus = "辉光伤害",
                              radianceStunChance = "辉光晕眩",
                              rangedDefRate = "远程减伤",
                              rangedDefCap = "远程减伤上限",
                              cstarAgiL = "伴随星敏捷", cstarAtkSpdL = "伴随星攻速",
                              cstarStrR = "伴随星力量", cstarWisR = "伴随星智慧",
                              cstarCritDmgR = "伴随星物暴伤", cstarMCritDmgR = "伴随星法暴伤",
                              dodgeRateBonus1 = "闪避率额外提高", dodgeRateBonus2 = "闪避率额外提高",
                              phantomDodge = "每层幻影闪避值",
                              houndSplashPct = "猎犬溅射", houndCountBonus = "猎犬数量", houndRespawnTurns = "猎犬复活",
                              windDmgPct = "起风伤害", windCallLevel = "唤风",
                              rangeBounceCount = "远程弹射", rangeBounceDmgMul = "远程弹射伤害",
                              rangedExplosionPct = "远程爆炸伤害",
                              explosionAoeMax = "爆炸扩展上限",
                              holyAoePct = "祝福超度范围化",
                              strikeAoePct = "强击系范围化",
                              killExpBonus = "击杀怪物经验值获取" }
        -- 属性显示顺序（保证物理攻击力在魔法攻击力前面等）
        local effectOrder = { "atk", "mAtk", "def", "mDef", "mdef", "hp", "mp", "str", "agi", "con", "wis", "foc", "per", "wil", "luk", "cha",
                              "critVal", "critDmg", "mCritVal", "mCritDmg", "avoidCrit", "hit", "dodge",
                              "atkSpeed", "castSpeed", "moveRange", "atkRange",
                              "hpRegen", "mpRegen", "hpDrain", "lifesteal", "batFangLifesteal", "physLifesteal", "magLifesteal",
                              "blockHeal", "onHitHeal", "castHeal", "onMagDmgHeal",
                              "castMpRegen", "onHitDefReduce",
                              "magDmgBonus", "pDmgReduce", "mDmgReduce",
                              "resFire", "resIce", "resElec", "resLight", "resDark", "resNature",
                              "holySpringBlessing", "shelterBlessing",
                              "maxMonsters", "spd", "crit" }
        -- 合并基础属性 + 强化加成为一个数值
        local enhLv = item.enhanceLevel or 0
        local enhGain = enhLv > 0 and GS.getEnhanceGain(item, enhLv) or {}
        -- 格挡属性单独合并显示
        local hasBlock = item.effects.block_chance ~= nil
        -- 随机词条档位（仅卓越装备）
        local baseAbyssTiers = ((item.rarity or "") == "superior") and item.abyssStatTiers or nil
        -- 按固定顺序输出
        for _, k in ipairs(effectOrder) do
            local v = item.effects[k]
            if v and k ~= "block_chance" and k ~= "block_amount" then
                local label = effectNames[k] or k
                local total = v + (enhGain[k] or 0)
                local sign = total >= 0 and "+" or ""
                lines[#lines + 1] = { type = "base_effect", text = label .. " " .. sign .. total,
                                      rarityTier = baseAbyssTiers and baseAbyssTiers[k] or nil }
            end
        end
        -- 未在 effectOrder 中的属性兜底
        for k, v in pairs(item.effects) do
            if k ~= "block_chance" and k ~= "block_amount" then
                local found = false
                for _, ek in ipairs(effectOrder) do if ek == k then found = true; break end end
                if not found then
                    local label = effectNames[k] or k
                    local total = v + (enhGain[k] or 0)
                    local sign = total >= 0 and "+" or ""
                    lines[#lines + 1] = { type = "base_effect", text = label .. " " .. sign .. total,
                                          rarityTier = baseAbyssTiers and baseAbyssTiers[k] or nil }
                end
            end
        end
        if hasBlock then
            local pct = math.floor(item.effects.block_chance * 100)  -- 几率固定不变
            local ba = (item.effects.block_amount or 1) + (enhGain.block_amount or 0)
            local blockTier = baseAbyssTiers and baseAbyssTiers["block_amount"] or nil
            lines[#lines + 1] = { type = "base_effect", text = pct .. "%概率格挡" .. ba .. "点物理伤害", rarityTier = blockTier }
        end
    end
    -- 深渊词缀（紫色六芒星，显示在附魔上方）
    if item.abyssAffix and not exchangePreview then
        lines[#lines + 1] = { type = "sep" }
        local affixDesc = item.abyssAffix.desc
        for _, pool in ipairs(GS.ABYSS_AFFIX_POOL or {}) do
            if pool.id == item.abyssAffix.id then affixDesc = pool.desc; break end
        end
        -- 统计已装备的同类词缀数量，显示 X/N（N=3+装备加成）
        local mechanic = item.abyssAffix.mechanic
        local equippedCount = 0
        local maxCount = 3
        if mechanic and GS.equipment then
            local superiorSeen = {}
            for _, slotId in ipairs({"weapon_r","weapon_l","hat","shoulder","cloak","chest","gloves","pants","boots","necklace","belt","trinket","ring1","ring2"}) do
                local slot = GS.equipment[slotId]
                if slot then
                    -- 统计同类词缀装备数
                    if slot.abyssAffix and slot.abyssAffix.mechanic == mechanic then
                        equippedCount = equippedCount + 1
                    end
                    if slot.gemSlots then
                        for _, gs in ipairs(slot.gemSlots) do
                            if gs.abyssAffix and gs.abyssAffix.mechanic == mechanic then
                                equippedCount = equippedCount + 1
                            end
                        end
                    end
                    -- 计算 abyssAffixLimitTarget 加成（卓越生效唯一）
                    if slot.abyssAffixLimitTarget and slot.abyssAffixLimitTarget.mechanic == mechanic then
                        local skipBonus = false
                        if slot.rarity == "superior" and slot.templateId then
                            if superiorSeen[slot.templateId] then
                                skipBonus = true
                            end
                            superiorSeen[slot.templateId] = true
                        end
                        if not skipBonus then
                            local tpl = slot.templateId and GS.itemTemplates[slot.templateId]
                            maxCount = maxCount + (tpl and tpl.randomAbyssAffixLimit or 1)
                        end
                    end
                end
            end
        end
        local stackLabel = mechanic and (" " .. math.min(equippedCount, maxCount) .. "/" .. maxCount) or ""
        lines[#lines + 1] = { type = "abyss_affix", text = item.abyssAffix.name .. stackLabel, desc = affixDesc }
    end
    -- 附魔属性（稀有度颜色显示）
    if item.enchantment then
        lines[#lines + 1] = { type = "sep" }
        local ench = item.enchantment
        local sign = ench.value >= 0 and "+" or ""
        local valStr = sign .. ench.value .. ench.suffix
        lines[#lines + 1] = { type = "enchant", text = ench.name .. " " .. valStr, rolledTier = GS.getItemTier(item) }
    end
    -- 精炼槽位（在附魔和附加属性之间）
    if item.refineSlots and #item.refineSlots > 0 then
        lines[#lines + 1] = { type = "sep" }
        for _, slot in ipairs(item.refineSlots) do
            if slot.attr then
                local sign = slot.value >= 0 and "+" or ""
                local valStr = sign .. slot.value .. (slot.suffix or "")
                lines[#lines + 1] = { type = "refine_filled", text = slot.name .. " " .. valStr, rolledTier = slot.rolledTier }
            else
                lines[#lines + 1] = { type = "refine_empty", text = "空精炼槽" }
            end
        end
    end
    -- 宝石槽位（在精炼槽之后、附加属性之前）
    if item.gemSlots and #item.gemSlots > 0 then
        lines[#lines + 1] = { type = "sep" }
        for _, gs in ipairs(item.gemSlots) do
            if gs.gemId then
                local gemTpl = GS.itemTemplates[gs.gemId]
                local gemName = gemTpl and gemTpl.name or gs.gemId
                local gemRarity = gemTpl and gemTpl.rarity or "common"
                -- 汇总宝石属性文本
                local effectStr = ""
                if gs.gemEffect then
                    for k, v in pairs(gs.gemEffect) do
                        local kName = k
                        for _, sd in ipairs(GS.STAT_DEFS) do
                            if sd.key == k then kName = sd.name; break end
                        end
                        if effectStr ~= "" then effectStr = effectStr .. " " end
                        effectStr = effectStr .. kName .. "+" .. v
                    end
                end
                -- 宝石携带深渊词缀时显示词缀名（如"朱莉"的面纱）
                local gemAbyssLabel = ""
                if gs.abyssAffix then
                    gemAbyssLabel = gs.abyssAffix.name
                end
                -- 属性和词缀较长时拆成两行
                local subLine = ""
                if gemAbyssLabel ~= "" then subLine = gemAbyssLabel end
                if effectStr ~= "" then
                    subLine = subLine ~= "" and (subLine .. " " .. effectStr) or effectStr
                end
                lines[#lines + 1] = { type = "gem_filled", text = gemName, gemRarity = gemRarity }
                if subLine ~= "" then
                    lines[#lines + 1] = { type = "gem_filled_sub", text = subLine, gemRarity = gemRarity }
                end
            else
                lines[#lines + 1] = { type = "gem_empty", text = "空宝石槽" }
            end
        end
    end
    -- 附加属性（绿色显示，不受强化影响；兼容旧实例从模板回填）
    local extraEff = item.extraEffects
    if not extraEff and item.templateId then
        local tpl = GS.itemTemplates[item.templateId]
        if tpl then extraEff = tpl.extraEffects end
    end
    if extraEff and not exchangePreview then
        lines[#lines + 1] = { type = "sep" }
        local effectNames = { atk = "物理攻击力", def = "物理防御力", hp = "生命值", mp = "魔法值",
                              str = "力量", wis = "智慧", agi = "敏捷", con = "体质",
                              foc = "专注", per = "感知", wil = "意念", luk = "幸运", cha = "魅力",
                              hpRegen = "HP自然回复", mpRegen = "MP自然回复",
                              hpDrain = "HP流失", critVal = "物理暴击值", dodge = "闪避值",
                              hit = "命中值", maxMonsters = "怪物出现上限", spawnCount = "怪物出现数量",
                              critDmg = "物理暴击伤害", lifesteal = "吸血",
                              batFangLifesteal = "吸血",
                              physLifesteal = "物理吸血", magLifesteal = "法术吸血",
                              manaLeech = "魔力回收",
                              moveRange = "移动距离", atkSpeed = "攻击速度",
                              castSpeed = "吟唱速度",
                              mAtk = "魔法攻击力", mDef = "魔法防御力", mdef = "魔法防御力", avoidCrit = "避开要害",
                              mCritVal = "魔法暴击值", mCritDmg = "魔法暴击伤害",
                              atkRange = "攻击距离",
                              magDmgBonus = "魔法伤害加成",
                              fireDmgBonus = "火焰伤害", iceDmgBonus = "冰冻伤害",
                              elecDmgBonus = "雷电伤害", lightDmgBonus = "神圣伤害",
                              ragingFireBonus = "燃火",
                              radianceNearDmgBonus = "辉光近处增伤",
                              swordDmgBonus = "剑类伤害", daggerDmgBonus = "匕首伤害",
                              maceDmgBonus = "钉锤伤害", bowDmgBonus = "弓类伤害",
                              staffDmgBonus = "法杖伤害", physDmgBonus = "物理伤害",
                              arsenalScatter = "散射",
                              healStoreRate = "治疗存储", healReleaseRate = "存储释放",
                              furyStackPerCrit = "狂怒叠加", furyMaxStacks = "狂怒上限", furyDecayOnNonCrit = "狂怒衰减",
                              pDmgReduce = "物理伤害减免",
                              mDmgReduce = "魔法伤害减免",
                              blockHeal = "格挡回血", onHitHeal = "命中回血",
                              castHeal = "施法回血", onMagDmgHeal = "魔伤回血",
                              castMpRegen = "施法回魔", onHitDefReduce = "命中减防",
                              resFire = "火焰抗性", resIce = "寒冰抗性", resElec = "雷电抗性",
                              resLight = "神圣抗性", resDark = "暗影抗性", resNature = "自然抗性",
                              holySpringBlessing = "圣泉祝福", shelterBlessing = "庇护祝福",
                              onKillHealHp = "击杀回血", onDamageTakenHeal = "受伤回血",
                              potionHealBonus = "药水额外治疗",
                              healEffectPct = "治疗效果加成",
                              bounceDmgInc = "弹射伤害递增",
                              agiToAtkSpeedEff = "每5点敏捷，攻速额外",
                              perToHealEffPct = "每5点感知，治疗效果",
                              nearDmgBonus = "近处敌人伤害",
                              counterComboMax = "反击连击上限",
                              counterComboConRate = "体质连击概率",
                              dodgeCounterChanceBonus = "闪避反击概率",
                              dodgeCounterDmgBonus = "闪避反击伤害",
                              defPct = "物理防御加成",
                              mDefPct = "魔法防御加成",
                              deferDmgPct = "受伤缓冲",
                              allEleRes = "所有元素抗性",
                              hitVal = "命中值",
                              illusionDmgPct = "幻影伤害提高",
                              illusionSearchRange = "幻影检索范围",
                              illusionSingleExtra = "幻影集中攻击",
                              scatterAtkPer = "每1点散射提高物理攻击力",
                              atkRangeHitPer = "每1格最大攻击距离提高命中值",
                              derivStormDmgBonus = "护甲清空时触发衍生飓风，衍生飓风伤害倍率提高",
                              illusionSingleDmgPct = "幻影集中伤害",
                              distDmgPctPerGrid = "距离伤害加成",
                              radianceDmgBonus = "辉光伤害",
                              radianceStunChance = "辉光晕眩",
                              rangedDefRate = "远程减伤",
                              rangedDefCap = "远程减伤上限",
                              cstarAgiL = "伴随星敏捷", cstarAtkSpdL = "伴随星攻速",
                              cstarStrR = "伴随星力量", cstarWisR = "伴随星智慧",
                              cstarCritDmgR = "伴随星物暴伤", cstarMCritDmgR = "伴随星法暴伤",
                              dodgeRateBonus1 = "闪避率额外提高", dodgeRateBonus2 = "闪避率额外提高",
                              phantomDodge = "每层幻影闪避值",
                              houndSplashPct = "猎犬溅射", houndCountBonus = "猎犬数量", houndRespawnTurns = "猎犬复活",
                              windDmgPct = "起风伤害", windCallLevel = "唤风",
                              rangeBounceCount = "远程弹射", rangeBounceDmgMul = "远程弹射伤害",
                              rangedExplosionPct = "远程爆炸伤害",
                              explosionAoeMax = "爆炸扩展上限",
                              holyAoePct = "祝福超度范围化",
                              strikeAoePct = "强击系范围化",
                              killExpBonus = "击杀怪物经验值获取" }
        -- 百分比属性集合
        local pctAttrs = { lifesteal = true, batFangLifesteal = true, critDmg = true, mCritDmg = true,
                           physLifesteal = true, magLifesteal = true,
                           magDmgBonus = true, pDmgReduce = true, mDmgReduce = true,
                           resFire = true, resIce = true, resElec = true,
                           resLight = true, resDark = true, resNature = true,
                           holySpringBlessing = true, shelterBlessing = true,
                           fireDmgBonus = true, iceDmgBonus = true,
                           ragingFireBonus = true,
                           radianceNearDmgBonus = true,
                           elecDmgBonus = true, lightDmgBonus = true,
                           swordDmgBonus = true, daggerDmgBonus = true,
                           maceDmgBonus = true, bowDmgBonus = true,
                           staffDmgBonus = true, physDmgBonus = true,
                           healEffectPct = true,
                           bounceDmgInc = true,
                           nearDmgBonus = true,
                           defPct = true,
                           mDefPct = true,
                           deferDmgPct = true,
                           allEleRes = true,
                           illusionDmgPct = true,
                           illusionSingleDmgPct = true,
                           derivStormDmgBonus = true,
                           radianceDmgBonus = true,
                           radianceStunChance = true,
                           cstarCritDmgR = true, cstarMCritDmgR = true,
                           dodgeRateBonus1 = true, dodgeRateBonus2 = true,
                           houndSplashPct = true,
                           windDmgPct = true,
                           rangeBounceDmgMul = true,
                           rangedExplosionPct = true,
                           holyAoePct = true,
                           strikeAoePct = true,
                           killExpBonus = true }
        -- 描述性属性（不显示数值，直接显示文本；排在数值属性之后）
        local descAttrs = { noBoss = "区域首领不会出现", rebirth = "【重生】每三天抵挡一次致死伤害",
                           heroHeavyStrike = "重击：50%概率重击，额外造成33点伤害",
                           -- heroPhantom: 改为档位显示"幻影+N"，不再作为描述性属性
                           heroMaceHeal = "回合结束时治疗自身12点HP",
                           heroScatter = "散射：普通攻击额外攻击1个目标",
                           heroLightningCast = "电击：普通攻击对目标施放1级电击术",
                           heroBounce = "弹射：普通攻击向3格范围内敌人弹射1次",
                           heroNormalAtkMpRegen = "普通攻击时，MP回复3点",
                           heroSkillBounce = "弹射：远程单体技能向3格范围内敌人弹射1次",
                           gemBoxSelect = "开启后从9种卓越稀有度宝石中任选一颗获取",
                           heroOffhandSelect = "开启后从冒险英雄系列副手装备中任选一件",
                           heresyFearAtk = "攻击有3%概率令目标陷入恐惧1回合",
                           heresyFearDef = "受到攻击有5%概率令攻击者陷入恐惧1回合",
                           fearDmgBonus = "对恐惧状态目标造成伤害+10%" }
        -- 第一轮：普通数值属性（按优先级排序显示）
        local abyssTiers = ((item.rarity or "") == "superior") and item.abyssStatTiers or nil
        local extraEffPriority = { agi = 1, foc = 2,
                                   atk = 4, def = 5, critDmg = 6, bounceDmgInc = 7,
                                   iceDmgBonus = 8, blizzardFreezeChance = 9,
                                   str = 10, hp = 11, con = 12, per = 13,
                                   defPct = 14, mDefPct = 14, deferDmgPct = 15,
                                   hit = 12.5,
                                   allEleRes = 16,
                                   wis = 17, fireDmgBonus = 17.2, resFire = 17.4, ragingFireBonus = 17.6,
                                   critVal = 17.5, wil = 18, mCritVal = 19, mCritDmg = 20,
                                   magDmgBonus = 21, physDmgBonus = 21,
                                   allStatDmgPer10 = 22, allStatReducePer10 = 23,
                                   hitVal = 24, illusionDmgPct = 25, heroPhantom = 26, illusionSingleExtra = 26.5, illusionSingleDmgPct = 26.6, phantomDodge = 27,
                                   mpCostDmgCoeff = 27,
                                   dodgeRateBonus1 = 28, dodgeRateBonus2 = 29,
                                   arsenalScatter = 30,
                                   healStoreRate = 31, healReleaseRate = 32,
                                   distDmgPctPerGrid = 33,
                                   furyStackPerCrit = 34, furyMaxStacks = 35, furyDecayOnNonCrit = 36,
                                   houndSplashPct = 37,
                                   windDmgPct = 38, windCallLevel = 39,
                                   rangeBounceCount = 40, rangeBounceDmgMul = 41,
                                   rangedExplosionPct = 42,
                                   explosionAoeMax = 43,
                                   holyAoePct = 44, radianceDmgBonus = 44.5, radianceNearDmgBonus = 44.6,
                                   strikeAoePct = 45,
                                   atkPerUnusedSP = 46, mAtkPerUnusedSP = 47,
                                   dmgToMpPct = 48, mpToMagDmgPct = 49,
                                   whirlPhantomCount = 50, whirlPhantomMul = 51,
                                   nonCritPhysPenalty = 52,
                                   focuserDmgPer = 53, focuserMaxStacks = 54,
                                   thunderJarBounce = 55, thunderJarRange = 56, compChainLightningMax = 56.5, houndCountBonus = 56.6, houndRespawnTurns = 56.7,
                                   deepThinkDmgPer = 57, castRange = 58, atkRangeBonus = 59,
                                   mpToHpPct = 60,
                                   skillAoeBonusIfNoOffhand = 61,
                                   skillDmgReduction = 62, normalAtkMatkCoeff = 63, normalAtkMatkRange = 64, dualDaggerDmgPct = 65,
                                   counterComboConRate = 65.5,
                                   dodgeCounterChanceBonus = 65.6, dodgeCounterDmgBonus = 65.7,
                                   noCombo = 1000, aspdSkillDmgPct = 1000,
                                   killExpBonus = 9999 }
        local extraEffKeys = {}
        for k in pairs(extraEff) do extraEffKeys[#extraEffKeys + 1] = k end
        -- 如果物品模板指定了 extraEffOrder，按该顺序排列
        local itemOrder = item.extraEffOrder
        if not itemOrder and item.templateId then
            local tplOrd = GS.itemTemplates[item.templateId]
            if tplOrd then itemOrder = tplOrd.extraEffOrder end
        end
        table.sort(extraEffKeys, function(a, b)
            if itemOrder then
                local oa, ob = itemOrder[a], itemOrder[b]
                if oa or ob then
                    return (oa or 999) < (ob or 999)
                end
            end
            local pa = extraEffPriority[a] or 999
            local pb = extraEffPriority[b] or 999
            if pa ~= pb then return pa < pb end
            return a < b
        end)
        -- 全属性合并：9项基础属性值相同时显示为一行"全属性 +N"
        -- 或：allstatLines 模式（千面骰等）每条词缀独立显示
        local allStatKeys = { "str", "wis", "agi", "con", "foc", "per", "wil", "luk", "cha" }
        local allStatMerged = {}  -- 被合并的属性key集合
        do
            if item.allstatLines and #item.allstatLines > 0 then
                -- 多条全属性词缀，每条独立显示
                for i, lineInfo in ipairs(item.allstatLines) do
                    local val = lineInfo.value
                    local sign = val >= 0 and "+" or ""
                    lines[#lines+1] = { type = "extra_effect", text = "全属性 " .. sign .. val, rarityTier = lineInfo.tier }
                end
                for _, sk in ipairs(allStatKeys) do allStatMerged[sk] = true end
            elseif item.randomMainExtraLines and #item.randomMainExtraLines > 0 then
                -- randomMainExtraLines：每条独立显示（带档位颜色）
                local attrNames = { str = "力量", wis = "智慧", agi = "敏捷", con = "体质",
                                    foc = "专注", per = "感知", wil = "意念", luk = "幸运", cha = "魅力" }
                for _, lineInfo in ipairs(item.randomMainExtraLines) do
                    local aName = attrNames[lineInfo.key] or lineInfo.key
                    local val = lineInfo.value
                    local sign = val >= 0 and "+" or ""
                    lines[#lines+1] = { type = "extra_effect", text = aName .. " " .. sign .. val, rarityTier = lineInfo.tier }
                end
                -- 标记这些属性已显示，不在通用循环中重复
                for _, lineInfo in ipairs(item.randomMainExtraLines) do
                    allStatMerged[lineInfo.key] = true
                end
            else
                local allSame = true
                local baseVal = extraEff[allStatKeys[1]]
                if type(baseVal) == "number" then
                    for i = 2, #allStatKeys do
                        if extraEff[allStatKeys[i]] ~= baseVal then allSame = false break end
                    end
                    if allSame then
                        local sign = baseVal >= 0 and "+" or ""
                        lines[#lines+1] = { type = "extra_effect", text = "全属性 " .. sign .. baseVal }
                        for _, sk in ipairs(allStatKeys) do allStatMerged[sk] = true end
                    end
                end
            end
        end
        for _, k in ipairs(extraEffKeys) do
            local v = extraEff[k]
            if type(v) ~= "number" then goto continue_extra1 end
            if hiddenAttrs[k] then goto continue_extra1 end
            if allStatMerged[k] then goto continue_extra1 end
            if descAttrs[k] then goto continue_extra1 end
            -- 特殊属性：eleFlowBonus（元素流转增伤）
            if k == "eleFlowBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "回合内最后使用的元素法术，使下回合其他元素魔法伤害提高" .. string.format("%g%%", v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：allStatDmgPer10（每10点属性提供伤害加成）
            if k == "allStatDmgPer10" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每10点属性提供" .. string.format("%g%%", v) .. "伤害加成", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：allStatReducePer10（每10点属性提供伤害减免）
            if k == "allStatReducePer10" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每10点属性提供" .. string.format("%g%%", v) .. "伤害减免", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：agiToAtkSpeedEff（自定义格式，不用通用"label +v"）
            if k == "agiToAtkSpeedEff" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每有5点敏捷，攻击速度提高" .. string.format("%g", v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：perToHealEffPct（每5点感知提高治疗效果）
            if k == "perToHealEffPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每5点感知提高治疗效果" .. string.format("%g%%", v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：nearDmgBonus（对近处敌人造成伤害加成）
            if k == "nearDmgBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "对近处敌人造成伤害+" .. string.format("%g%%", v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：ragingFireBonus（燃火，完整描述句式）
            if k == "ragingFireBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "燃火：若回合开始时处于灼烧地面，火焰伤害额外提高" .. string.format("%g%%", v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：radianceNearDmgBonus（辉光对近处敌人额外伤害）
            if k == "radianceNearDmgBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "辉光对近处敌人造成的伤害提高" .. string.format("%g%%", v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：atkPerUnusedSP / mAtkPerUnusedSP（未使用技能点加成）
            if k == "atkPerUnusedSP" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每1点未使用的技能点使物理攻击力提高" .. math.floor(v) .. "点", rarityTier = tier }
                goto continue_extra1
            end
            if k == "mAtkPerUnusedSP" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每1点未使用的技能点使魔法攻击力提高" .. math.floor(v) .. "点", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：dmgToMpPct（伤害回魔比例）
            if k == "dmgToMpPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "根据造成伤害的" .. string.format("%g%%", v) .. "回复魔法值", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：mpToMagDmgPct（每100最大魔法值提高法术伤害%）
            if k == "mpToMagDmgPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每100点最大魔法值提高" .. string.format("%g%%", v) .. "法术伤害", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：whirlPhantomCount（旋风斩触发幻影数量）
            if k == "whirlPhantomCount" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "旋风斩可以触发幻影，至多" .. math.floor(v) .. "个。", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：whirlPhantomMul（幻影旋风斩倍率）
            if k == "whirlPhantomMul" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "幻影使用" .. math.floor(v) .. "%倍率的旋风斩", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：nonCritPhysPenalty（未暴击物理伤害惩罚）
            if k == "nonCritPhysPenalty" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local pct = math.abs(math.floor(v))
                lines[#lines+1] = { type = "extra_effect", text = "未暴击的物理伤害-" .. pct .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：focuserDmgPer（聚焦器：封印词缀增伤）
            if k == "focuserDmgPer" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local pct = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "所有深渊词缀不再生效，每一条被封印的词缀提高伤害" .. pct .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：focuserMaxStacks（聚焦器：增伤上限条数）
            if k == "focuserMaxStacks" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "至多" .. n .. "条词缀提供增伤。", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：thunderJarBounce（养雷壶：闪电链弹射次数）
            if k == "thunderJarBounce" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "闪电链弹射次数+" .. n, rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：thunderJarRange（养雷壶：闪电链弹射范围）
            if k == "thunderJarRange" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "闪电链的弹射范围+" .. n, rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：littleZeusRange（小宙斯：普攻变为远程雷击，攻击距离）
            if k == "littleZeusRange" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "普通攻击变为雷电属性远程攻击，攻击距离为" .. n, rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：littleZeusPhysPct（小宙斯：物理攻击力缩放%）
            if k == "littleZeusPhysPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "根据物理攻击力的" .. math.floor(v) .. "%造成伤害", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：littleZeusMagPct（小宙斯：魔法攻击力缩放%）
            if k == "littleZeusMagPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "根据魔法攻击力的" .. math.floor(v) .. "%造成伤害", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：littleZeusChainProb（小宙斯：闪电链触发概率%）
            if k == "littleZeusChainProb" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "闪电链的触发概率提高到" .. math.floor(v) .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：houndCountBonus（狼群银哨：额外猎犬数量，需要猎犬技能）
            if k == "houndCountBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "猎犬技能数量+" .. n, rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：houndRespawnTurns（狼群银哨：猎犬复活时间）
            if k == "houndRespawnTurns" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "猎犬复活时间变为" .. n .. "回合", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：compChainLightningMax（蕴雷：同伴/幻影闪电链每回合触发次数）
            if k == "compChainLightningMax" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "每回合同伴和幻影可触发闪电链至多" .. n .. "次", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：deepThinkDmgPer（深度思维：每额外吟唱段数增伤%）
            if k == "deepThinkDmgPer" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "施法时清空吟唱，每额外消耗1段+" .. string.format("%g%%", v) .. "伤害/治疗", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：castRange（虚空握：远程技能施展距离）
            if k == "castRange" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                if n > 0 then
                    lines[#lines+1] = { type = "extra_effect", text = "远程技能施展距离+" .. n, rarityTier = tier }
                else
                    lines[#lines+1] = { type = "extra_effect", text = "远程技能施展距离+0", rarityTier = tier }
                end
                goto continue_extra1
            end
            -- 特殊属性：atkRangeBonus（虚空握：攻击距离加成）
            if k == "atkRangeBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                if n > 0 then
                    lines[#lines+1] = { type = "extra_effect", text = "攻击距离+" .. n, rarityTier = tier }
                else
                    lines[#lines+1] = { type = "extra_effect", text = "攻击距离+0", rarityTier = tier }
                end
                goto continue_extra1
            end
            -- abyssAffixLimitBonus 已移除，改用 abyssAffixLimitTarget（在下方独立显示）
            if k == "abyssAffixLimitBonus" then
                goto continue_extra1
            end
            -- 特殊属性：noCombo（与aspdSkillDmgPct合并显示，此处跳过）
            if k == "noCombo" then
                goto continue_extra1
            end
            -- 特殊属性：aspdSkillDmgPct（攻速转技能伤害，合并noCombo显示）
            if k == "aspdSkillDmgPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "不能触发连击，每1点攻速提高技能伤害" .. string.format("%g%%", v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：counterComboMax（反击连击次数）
            if k == "counterComboMax" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "反击时根据体质触发连击，至多" .. math.floor(v) .. "次", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：counterComboConRate（每1点体质提供的连击概率）
            if k == "counterComboConRate" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每1点体质提供" .. string.format("%g%%", v) .. "连击概率", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：dodgeCounterChanceBonus（水中蛇：左手空时反击概率加成）
            if k == "dodgeCounterChanceBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "左手武器栏为空时，反击概率提高" .. math.floor(v) .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：dodgeCounterDmgBonus（水中蛇：闪避触发反击+伤害加成）
            if k == "dodgeCounterDmgBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "闪避可以触发反击，反击伤害提高" .. math.floor(v) .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：meteorStunDuration（与 meteorStunChance 合并显示）
            if k == "meteorStunDuration" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local chance = extraEff.meteorStunChance or 25
                local dur = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "「陨石术」" .. chance .. "%概率施加" .. dur .. "回合晕眩", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：blizzardFreezeChance（与 blizzardFreezeDuration 合并显示）
            if k == "blizzardFreezeChance" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local dur = math.floor(extraEff.blizzardFreezeDuration or 1)
                lines[#lines+1] = { type = "extra_effect", text = "「暴风雪」" .. v .. "%概率对冻僵目标施加" .. dur .. "回合冰冻", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：counterRangedPct（反击倍率，显示为百分比）
            if k == "counterRangedPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local pct = math.floor(v * 100)
                lines[#lines+1] = { type = "extra_effect", text = "反击类技能以" .. pct .. "%倍率作用于远程攻击", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：thunderCloudChainLightChance（雷电书闪电链触发概率）
            if k == "thunderCloudChainLightChance" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "「雷云术」" .. v .. "%概率额外施放闪电链", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：holySpringBlessing / shelterBlessing（显示等级和实际效果）
            if k == "holySpringBlessing" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local realPct = math.floor(v * 5)
                lines[#lines+1] = { type = "extra_effect", text = "圣泉祝福 Lv." .. v .. "（HP/MP回复+" .. realPct .. "%）", rarityTier = tier }
                goto continue_extra1
            end
            if k == "shelterBlessing" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local realPct = math.floor(v * 1)
                lines[#lines+1] = { type = "extra_effect", text = "庇护祝福 Lv." .. v .. "（物防/魔防+" .. realPct .. "%）", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：heroPhantom（幻影词条，按实际值显示）
            if k == "heroPhantom" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "幻影+" .. math.floor(v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：phantomDodge（聚影众：每层幻影提高闪避值）
            if k == "phantomDodge" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每层幻影提高" .. math.floor(v) .. "点闪避值", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：illusionSingleExtra（极影之形：幻影集中攻击，合并 illusionSingleDmgPct 显示）
            if k == "illusionSingleExtra" then
                local tier = abyssTiers and (abyssTiers["illusionSingleDmgPct"] or abyssTiers[k]) or nil
                local parts = { "对同一目标可以作用的幻影+" .. math.floor(v) }
                local dmgPct = extraEff.illusionSingleDmgPct
                if dmgPct and dmgPct > 0 then
                    parts[#parts+1] = "幻影伤害增加" .. dmgPct .. "%"
                end
                lines[#lines+1] = { type = "extra_effect", text = table.concat(parts, "，"), rarityTier = tier }
                goto continue_extra1
            end
            -- illusionSingleDmgPct 与 illusionSingleExtra 同时存在时，已在集中攻击行合并显示
            if k == "illusionSingleDmgPct" and extraEff.illusionSingleExtra then
                goto continue_extra1
            end
            -- 特殊属性：arsenalScatter（军火库：散射词条，按实际值显示）
            if k == "arsenalScatter" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "散射+" .. math.floor(v), rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：healStoreRate（圣光结晶：治疗存储）
            if k == "healStoreRate" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "治疗的" .. v .. "%存储", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：healReleaseRate（圣光结晶：存储释放）
            if k == "healReleaseRate" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每3回合释放存储量的" .. v .. "%治疗自身", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：distDmgPctPerGrid（神射手：每格距离伤害加成）
            if k == "distDmgPctPerGrid" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "每格距离伤害+" .. v .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：furyStackPerCrit（血屠：每次暴击叠加狂怒）
            if k == "furyStackPerCrit" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "每次暴击叠加" .. v .. "层\xe2\x80\x9c狂怒\xe2\x80\x9d（攻击力+3，暴击伤害+1%）",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：furyMaxStacks（血屠：狂怒上限）
            if k == "furyMaxStacks" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "\xe2\x80\x9c狂怒\xe2\x80\x9d上限" .. v .. "层",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：furyDecayOnNonCrit（血屠：未暴击衰减）
            if k == "furyDecayOnNonCrit" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "每次未暴击的攻击降低" .. v .. "层\xe2\x80\x9c狂怒\xe2\x80\x9d",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：mpCostDmgCoeff（魔贯：施法消耗MP增伤）
            if k == "mpCostDmgCoeff" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "施法消耗30%魔法值增伤（系数" .. v .. "%）", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：radianceDmgBonus（至高天：同时装备天使时辉光伤害加成）
            if k == "radianceDmgBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "同时装备「天使」时，辉光伤害+" .. v .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：radianceStunChance（天使：同时装备至高天时辉光晕眩）
            if k == "radianceStunChance" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "同时装备「至高天」时，辉光" .. v .. "%概率晕眩敌人", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：rangedDefRate（山脉：物防超700每10点远程减伤率）
            -- rangedDefRate 显示后紧跟 rangedDefCap，保证顺序（pairs遍历无序）
            if k == "rangedDefRate" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "物防超700部分每10点降低远程伤害" .. v .. "%", rarityTier = tier }
                if extraEff.rangedDefCap then
                    local tierCap = abyssTiers and abyssTiers["rangedDefCap"] or nil
                    lines[#lines+1] = { type = "extra_effect", text = "降低比例至多" .. extraEff.rangedDefCap .. "%", rarityTier = tierCap }
                end
                goto continue_extra1
            end
            -- rangedDefCap 已在 rangedDefRate 中追加，跳过
            if k == "rangedDefCap" then
                goto continue_extra1
            end
            -- 特殊属性：伴随星（槽位条件，6行固定顺序，由 cstarAgiL 统一发射）
            if k == "cstarAgiL" then
                local ee = extraEff
                local at = abyssTiers
                local entries = {
                    { key = "cstarAgiL",      prefix = "装备在左手时，敏捷+",         pct = false },
                    { key = "cstarAtkSpdL",   prefix = "装备在左手时，攻击速度+",     pct = false },
                    { key = "cstarStrR",      prefix = "装备在右手时，力量+",         pct = false },
                    { key = "cstarWisR",      prefix = "装备在右手时，智慧+",         pct = false },
                    { key = "cstarCritDmgR",  prefix = "装备在右手时，物理暴击伤害+", pct = true },
                    { key = "cstarMCritDmgR", prefix = "装备在右手时，魔法暴击伤害+", pct = true },
                }
                for _, e in ipairs(entries) do
                    if ee[e.key] then
                        local tier = at and at[e.key] or nil
                        local suffix = e.pct and "%" or ""
                        lines[#lines+1] = { type = "extra_effect", text = e.prefix .. ee[e.key] .. suffix, rarityTier = tier }
                    end
                end
                goto continue_extra1
            end
            if k == "cstarAtkSpdL" or k == "cstarStrR" or k == "cstarWisR" or k == "cstarCritDmgR" or k == "cstarMCritDmgR" then
                goto continue_extra1  -- 已在 cstarAgiL 中统一发射
            end
            -- 特殊属性：houndSplashPct（驯兽圈：猎犬溅射）
            if k == "houndSplashPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "溅射类词条作用于猎犬，猎犬攻击具有" .. v .. "%的基础溅射效果", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：houndCountBonus（狼群银哨：额外猎犬数量）
            if k == "houndCountBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "猎犬技能数量+" .. n, rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：houndRespawnTurns（狼群银哨：猎犬复活时间）
            if k == "houndRespawnTurns" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local n = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "猎犬复活时间变为" .. n .. "回合", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：windDmgPct（集风袋：起风时伤害提高）
            if k == "windDmgPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect", text = "起风时伤害提高" .. v .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：windCallLevel（集风袋：唤风词条，按值显示等风/祈风/唤风）
            if k == "windCallLevel" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local text
                if v >= 999 then
                    text = "唤风：随机天气时必定刮风"
                elseif v > 66 then
                    text = "祈风：起风概率大幅提高"
                elseif v > 33 then
                    text = "祈风：起风概率中幅提高"
                elseif v > 0 then
                    text = "祈风：起风概率小幅提高"
                else
                    text = "等风：无事发生"
                end
                lines[#lines+1] = { type = "extra_effect", text = text, rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：rangeBounceCount（银鹿：使弹射词缀对远程单体技能生效）
            if k == "rangeBounceCount" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local mulVal = extraEff.rangeBounceDmgMul or 100
                lines[#lines+1] = { type = "extra_effect",
                    text = "弹射词缀对远程单体技能生效（至多" .. v .. "次，" .. mulVal .. "%伤害），不传递控制效果",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：rangeBounceDmgMul 已合并到 rangeBounceCount 中显示，跳过
            if k == "rangeBounceDmgMul" then
                goto continue_extra1
            end
            -- 特殊属性：rangedExplosionPct（爆炸信：远程单体技能爆炸）
            if k == "rangedExplosionPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "远程单体技能命中后周围1格爆炸（" .. v .. "%伤害）",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：explosionAoeMax（爆炸信：技能扩展可作用上限）
            if k == "explosionAoeMax" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "技能扩展可作用于爆炸范围（至多" .. v .. "条）",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：holyAoePct（哈雷努拉：祝福术/超度变为范围技能）
            if k == "holyAoePct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "\"祝福术\"和\"超度\"变为范围技能（" .. v .. "%伤害）",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：strikeAoePct（银色狮子：强击系技能变为范围技能）
            if k == "strikeAoePct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "\"强击\"系技能变为范围技能（" .. v .. "%伤害）",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：deferDmgPct（解放日：受伤缓冲）
            if k == "deferDmgPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "受到伤害的" .. v .. "%延迟到下回合结束阶段结算",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：mpToHpPct（幻纱：回合结束MP转化生命）
            if k == "mpToHpPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "回合结束时将" .. v .. "%魔法值转化为生命值",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：hellStompBurnPct（地狱踏：移动留下燃烧地面）
            if k == "hellStompBurnPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "移动留下持续2回合的燃烧地面，伤害为魔攻的" .. v .. "%",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：hellStompHealPct（地狱踏：免疫灼烧地面+治疗）
            if k == "hellStompHealPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "免疫燃烧地面，燃烧伤害以" .. v .. "%治疗自身",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：offeringAutoFlashMax（献礼：连击中断自动闪烁突袭）
            if k == "offeringAutoFlashMax" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "连击中断时自动使用闪烁突袭，至多" .. v .. "次",
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：offeringFlashRangeBonus（献礼：闪烁突袭施展距离加成）
            if k == "offeringFlashRangeBonus" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "闪烁突袭施展距离+" .. v,
                    rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：extraDmgSkillCast（白木胁差：盾牌失效 + 额外施展，合并为一行）
            if k == "extraDmgSkillCast" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local hasNoPassive = item and item.noShieldPassive
                local txt
                if hasNoPassive and v > 0 then
                    txt = "\u{201c}盾牌熟练\u{201d}和\u{201c}盾牌专精\u{201d}不再生效，伤害类技能额外施展" .. v .. "次"
                elseif hasNoPassive then
                    txt = "\u{201c}盾牌熟练\u{201d}和\u{201c}盾牌专精\u{201d}不再生效"
                elseif v > 0 then
                    txt = "伤害类技能额外施展" .. v .. "次"
                end
                if txt then
                    lines[#lines+1] = { type = "extra_effect", text = txt, rarityTier = tier }
                end
                goto continue_extra1
            end
            if k == "skillAoeBonusIfNoOffhand" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local txt = "左手武器栏为空时，技能作用范围+" .. v
                lines[#lines+1] = { type = "extra_effect",
                    text = txt, rarityTier = tier }
                goto continue_extra1
            end
            if k == "skillDmgReduction" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local txt = "技能伤害降低" .. v .. "%"
                lines[#lines+1] = { type = "extra_effect",
                    text = txt, rarityTier = tier }
                goto continue_extra1
            end
            if k == "normalAtkMatkCoeff" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local rng = extraEff.normalAtkMatkRange or 0
                local rngTier = abyssTiers and abyssTiers["normalAtkMatkRange"] or nil
                local txt = "普通攻击时根据魔攻" .. v .. "%造成魔法伤害"
                lines[#lines+1] = { type = "extra_effect",
                    text = txt, rarityTier = tier }
                -- 范围作为子行紧跟其后
                local rngTxt = "上述伤害范围：自身" .. rng .. "格内"
                lines[#lines+1] = { type = "extra_effect",
                    text = rngTxt, rarityTier = rngTier }
                goto continue_extra1
            end
            if k == "normalAtkMatkRange" then
                -- 已由 normalAtkMatkCoeff 合并输出，跳过
                goto continue_extra1
            end
            if k == "dualDaggerDmgPct" then
                local tier = abyssTiers and abyssTiers[k] or nil
                local pct = math.floor(v)
                lines[#lines+1] = { type = "extra_effect", text = "双持匕首时伤害降低为" .. pct .. "%", rarityTier = tier }
                goto continue_extra1
            end
            -- 特殊属性：equipThorns（国王冠冕：受击反伤）
            if k == "equipThorns" then
                local tier = abyssTiers and abyssTiers[k] or nil
                lines[#lines+1] = { type = "extra_effect",
                    text = "受到攻击时对攻击者造成" .. v .. "点物理伤害",
                    rarityTier = tier }
                goto continue_extra1
            end
            local label
            if k == "potionHealBonus" and (extraEff.potionHealBonusMaxLv or 0) > 0 then
                label = "Lv" .. extraEff.potionHealBonusMaxLv .. "以下药水额外治疗"
            else
                label = effectNames[k] or k
            end
            local sign = v >= 0 and "+" or ""
            local tier = abyssTiers and abyssTiers[k] or nil
            if pctAttrs[k] then
                local suffix = k == "batFangLifesteal" and "（上限10点）"
                            or k == "derivStormDmgBonus" and "，每回合最多触发一次。"
                            or ""
                local displaySign = k == "derivStormDmgBonus" and "" or sign
                lines[#lines + 1] = { type = "extra_effect", text = label .. " " .. displaySign .. v .. "%" .. suffix, rarityTier = tier }
            else
                lines[#lines + 1] = { type = "extra_effect", text = label .. " " .. sign .. v, rarityTier = tier }
            end
            ::continue_extra1::
        end
        -- 第二轮：描述性属性（重生等）放最后
        for k, v in pairs(extraEff) do
            if type(v) ~= "number" then goto continue_extra2 end
            if descAttrs[k] then
                lines[#lines + 1] = { type = "extra_effect", text = descAttrs[k] }
            end
            ::continue_extra2::
        end
    end
    -- 模板级特殊属性：normalAtkProc（普攻触发技能）
    do
        local tplProc = item.templateId and GS.itemTemplates[item.templateId]
        local proc = tplProc and tplProc.normalAtkProc
        if proc then
            -- 如果没有 extraEffects 节（即上方没有生成 sep），需要补一条分割线
            if not extraEff then
                lines[#lines+1] = { type = "sep" }
            end
            local skillName = "技能"
            local sDef = GS.SKILL_DEFS and GS.SKILL_DEFS[proc.skillId]
            if sDef and sDef.name then skillName = sDef.name end
            local chance = proc.chance or 0
            local lv = proc.level or 1
            local capText = ""
            if proc.dmgCap then capText = "（伤害上限" .. proc.dmgCap .. "）" end
            lines[#lines+1] = { type = "extra_effect",
                text = "普通攻击有" .. chance .. "%概率触发" .. lv .. "级" .. skillName .. capText }
        end
    end
    -- 模板级特殊属性：skillUseProc（技能使用触发技能）
    do
        local tplProc = item.templateId and GS.itemTemplates[item.templateId]
        local proc = tplProc and tplProc.skillUseProc
        if proc then
            if not extraEff and not (tplProc and tplProc.normalAtkProc) then
                lines[#lines+1] = { type = "sep" }
            end
            local skillName = "技能"
            local sDef = GS.SKILL_DEFS and GS.SKILL_DEFS[proc.skillId]
            if sDef and sDef.name then skillName = sDef.name end
            local chance = proc.chance or 0
            local lv = proc.level or 1
            local targetText = proc.targetNearest and "对最近的敌人" or ""
            local capText = ""
            if proc.dmgCap then capText = "（伤害上限" .. proc.dmgCap .. "）" end
            lines[#lines+1] = { type = "extra_effect",
                text = "使用技能时有" .. chance .. "%概率" .. targetText .. "使用" .. lv .. "级" .. skillName .. capText }
        end
    end
    -- abyssAffixLimitTarget：紫色六芒星显示随机深渊词缀生效上限（值从模板读取）
    if item.abyssAffixLimitTarget then
        local alt = item.abyssAffixLimitTarget
        local tplAlt = item.templateId and GS.itemTemplates[item.templateId]
        local bonus = tplAlt and tplAlt.randomAbyssAffixLimit or 1
        local sign = bonus >= 0 and "+" or ""
        lines[#lines+1] = { type = "abyss_affix", text = alt.name .. " 生效上限" .. sign .. bonus }
    end
    -- 宝石镶嵌属性加成（绿色显示）
    local gemEff = item.gemEffect
    if not gemEff and item.templateId then
        local tplGem = GS.itemTemplates[item.templateId]
        if tplGem then gemEff = tplGem.gemEffect end
    end
    if not gemEff and item.id and GS.itemTemplates[item.id] then
        gemEff = GS.itemTemplates[item.id].gemEffect
    end
    if gemEff then
        lines[#lines + 1] = { type = "sep" }
        local gemStatNames = {}
        for _, sd in ipairs(GS.STAT_DEFS) do
            gemStatNames[sd.key] = sd.name
        end
        for k, v in pairs(gemEff) do
            if type(v) == "number" then
                local label = gemStatNames[k] or k
                local sign = v >= 0 and "+" or ""
                lines[#lines + 1] = { type = "extra_effect", text = label .. " " .. sign .. v }
            end
        end
    end
    -- 套装信息（在附加属性之后显示）
    local setId = item.setId
    if not setId and item.templateId then
        local tpl2 = GS.itemTemplates[item.templateId]
        if tpl2 then setId = tpl2.setId end
    end
    if setId and GS.SET_DEFS[setId] then
        local setDef = GS.SET_DEFS[setId]
        -- 统计当前已装备的套装件数
        local equippedCount = 0
        local equippedIds = {}
        for _, eqItem in pairs(GS.equipment) do
            if eqItem then
                local eSid = eqItem.setId
                if not eSid and eqItem.templateId then
                    local eTpl = GS.itemTemplates[eqItem.templateId]
                    if eTpl then eSid = eTpl.setId end
                end
                if eSid == setId then
                    equippedCount = equippedCount + 1
                    equippedIds[eqItem.templateId or eqItem.id] = true
                end
            end
        end
        lines[#lines + 1] = { type = "sep" }
        -- 套装标题 + 详情按钮（组件和效果移到二级面板）
        local setPieces = {}
        for _, pieceId in ipairs(setDef.pieces) do
            local pTpl = GS.itemTemplates[pieceId]
            if pTpl then
                setPieces[#setPieces + 1] = { text = pTpl.name, active = equippedIds[pieceId] and true or false }
            end
        end
        local setBonuses = {}
        for _, b in ipairs(setDef.bonuses) do
            setBonuses[#setBonuses + 1] = { text = "(" .. b.count .. "件) " .. b.desc, active = (equippedCount >= b.count) }
        end
        lines[#lines + 1] = {
            type = "set_title", text = setDef.name .. " (" .. equippedCount .. "/" .. #setDef.pieces .. ")",
            pieces = setPieces, bonuses = setBonuses,
        }
    end
    if item.consumable and type(item.consumable) == "table" then
        local c = item.consumable
        if c.stat == "hp" or c.stat == "mp" then
            local statNames = { hp = "生命值", mp = "魔法值" }
            lines[#lines + 1] = { type = "effect", text = "恢复 " .. c.amount .. " 点" .. statNames[c.stat] }
        elseif c.stat and c.stat:sub(1, 5) == "buff_" then
            local buffNames = {
                buff_str = "力量", buff_agi = "敏捷", buff_con = "体质",
                buff_wis = "智慧", buff_foc = "专注", buff_per = "感知",
                buff_wil = "意念", buff_luk = "幸运", buff_cha = "魅力",
                buff_hit = "命中", buff_atk = "物攻", buff_matk = "魔攻",
                buff_def = "物防", buff_dodge = "闪避", buff_mdef = "魔防",
                buff_fire_res = "火焰抗性", buff_ice_res = "寒冰抗性",
                buff_thunder_res = "雷电抗性", buff_nature_res = "自然抗性",
                buff_dark_res = "暗黑抗性", buff_holy_res = "神圣抗性",
                buff_fire_dmg = "火焰伤害", buff_ice_dmg = "寒冰伤害",
                buff_thunder_dmg = "雷电伤害", buff_holy_dmg = "神圣伤害",
            }
            local label = buffNames[c.stat] or c.stat
            local suffix = c.isPercent and "%" or ""
            lines[#lines + 1] = { type = "extra_effect", text = label .. " +" .. c.amount .. suffix .. "（" .. (c.duration or 6) .. "小时）" }
        end
    end

    -- 食物 foodEffect 绿色文本渲染
    local tplFood = GS.itemTemplates[item.templateId or item.id]
    if tplFood and tplFood.foodEffect then
        local fe = tplFood.foodEffect
        local foodStatNames = {
            hpRegen = "HP回复", mpRegen = "MP回复",
            str = "力量", agi = "敏捷", con = "体质",
            wis = "智慧", foc = "专注", per = "感知",
            wil = "意念", luk = "幸运", cha = "魅力",
            physCrit = "物理暴击", magicCrit = "魔法暴击", spellCrit = "法术暴击",
            fireDmgBonus = "火焰伤害", fireDmgPct = "火焰伤害",
            iceDmgPct = "寒冰伤害", thunderDmgPct = "雷电伤害", holyDmgPct = "神圣伤害",
        }
        local order = { "hpRegen", "mpRegen", "str", "agi", "con", "wis", "foc", "per", "wil", "luk", "cha", "physCrit", "magicCrit", "spellCrit", "fireDmgBonus", "fireDmgPct", "iceDmgPct", "thunderDmgPct", "holyDmgPct" }
        for _, key in ipairs(order) do
            if fe[key] and fe[key] ~= 0 then
                local label = foodStatNames[key] or key
                local suffix = (key:find("Pct") or key:find("Bonus")) and "%" or ""
                lines[#lines + 1] = { type = "extra_effect", text = label .. " +" .. fe[key] .. suffix .. "（持续8小时）" }
            end
        end
    end

    -- 深渊兑换预览（替代正常属性块，仅在 abyss_exchange 来源且有 exchangePreview 时显示）
    if exchangePreview then
        if exchangePreview.effects and #exchangePreview.effects > 0 then
            lines[#lines + 1] = { type = "sep" }
            for _, e in ipairs(exchangePreview.effects) do
                lines[#lines + 1] = { type = "effect", text = e.text, white = e.white }
            end
        end
        if exchangePreview.abyssAffix then
            lines[#lines + 1] = { type = "sep" }
            lines[#lines + 1] = { type = "abyss_affix", text = exchangePreview.abyssAffix, desc = "兑换后随机抽取" }
        end
        if exchangePreview.extraEffects and #exchangePreview.extraEffects > 0 then
            lines[#lines + 1] = { type = "sep" }
            for _, e in ipairs(exchangePreview.extraEffects) do
                lines[#lines + 1] = { type = "extra_effect", text = e.text, white = e.white }
            end
        end
    end

    if item.desc and item.desc ~= "" then
        lines[#lines + 1] = { type = "sep" }
        lines[#lines + 1] = { type = "desc", text = item.desc }
    end
    -- 出售价格 & 锁定/收藏按钮行（即使不可出售也显示按钮）
    local sp = GS.getItemSellPrice(item)
    lines[#lines + 1] = { type = "sep" }
    if sp > 0 then
        lines[#lines + 1] = { type = "sellprice", text = "单价: " .. sp .. " G" }
    else
        lines[#lines + 1] = { type = "sellprice", text = nil }
    end

    -- 文本换行预处理（desc 和 effect 类型）
    local wrappedMap = {}
    for i, l in ipairs(lines) do
        if l.type == "desc" or l.type == "effect" or l.type == "enhance" or l.type == "base_effect" or l.type == "special" or l.type == "enchant" or l.type == "extra_effect" then
            local fs = l.type == "desc" and descFontSize or 14
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, fs)
            local tw = nvgTextBounds(vg, 0, 0, l.text or "", nil)
            if tw > maxTextW then
                local wrapped = {}
                local cur = ""
                for _, code in utf8.codes(l.text) do
                    local ch = utf8.char(code)
                    local test = cur .. ch
                    local tw2 = nvgTextBounds(vg, 0, 0, test, nil)
                    if tw2 > maxTextW and cur ~= "" then
                        wrapped[#wrapped + 1] = cur
                        cur = ch
                    else
                        cur = test
                    end
                end
                if cur ~= "" then wrapped[#wrapped + 1] = cur end
                wrappedMap[i] = wrapped
            end
        end
    end

    -- 计算面板高度
    local contentH = padY
    for i, l in ipairs(lines) do
        if l.type == "sep" then
            contentH = contentH + 8
        elseif l.type == "desc" then
            local wl = wrappedMap[i] or { l.text }
            contentH = contentH + #wl * (lineH - 2) + 4
        elseif l.type == "set_title" then
            contentH = contentH + lineH
        elseif l.type == "abyss_affix" then
            contentH = contentH + lineH  -- 标题行
            if l.desc then
                nvgFontSize(vg, 11)
                local descMaxW = maxTextW - 14
                -- 使用 utf8 感知的换行计算
                local descWrapped = {}
                local cur = ""
                for _, code in utf8.codes(l.desc) do
                    local ch = utf8.char(code)
                    local test = cur .. ch
                    local tw2 = nvgTextBounds(vg, 0, 0, test, nil)
                    if tw2 > descMaxW and cur ~= "" then
                        descWrapped[#descWrapped + 1] = cur
                        cur = ch
                    else
                        cur = test
                    end
                end
                if cur ~= "" then descWrapped[#descWrapped + 1] = cur end
                wrappedMap[i] = { _abyssDesc = descWrapped }
                local descLineH = 15  -- 11px字号用更紧凑的行高
                contentH = contentH + #descWrapped * descLineH
            end
        elseif (l.type == "effect" or l.type == "enhance" or l.type == "base_effect" or l.type == "special" or l.type == "enchant" or l.type == "extra_effect") and wrappedMap[i] then
            contentH = contentH + #wrappedMap[i] * lineH
        else
            contentH = contentH + lineH
        end
    end
    local itemTpl = item.templateId and GS.itemTemplates[item.templateId]
    local hasUseEffect = itemTpl and itemTpl.useEffect
    local isReadable = itemTpl and itemTpl.readableText
    if showBtn and (item.slot or item.consumable or hasUseEffect) then
        contentH = contentH + 6 + btnH
    end
    if showBtn and isReadable then
        contentH = contentH + 6 + btnH
    end
    contentH = contentH + padY

    -- 绘制面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, contentH, 6)
    nvgFillColor(vg, nvgRGBA(15, 12, 8, 240))
    nvgFill(vg)

    -- 稀有度渐变装饰（顶部）
    local gc = rarityDef and rarityDef.color or {100, 85, 60}
    local gradH = 28
    nvgSave(vg)
    nvgIntersectScissor(vg, px, py, pw, gradH)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, gradH, 6)
    local grad = nvgLinearGradient(vg, px, py, px, py + gradH,
        nvgRGBA(gc[1], gc[2], gc[3], 70), nvgRGBA(gc[1], gc[2], gc[3], 0))
    nvgFillPaint(vg, grad)
    nvgFill(vg)
    nvgRestore(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, contentH, 6)
    local borderColor = rarityDef and rarityDef.border or {100, 85, 60}
    nvgStrokeColor(vg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 绘制内容
    nvgFontFace(vg, "sans")
    local curY = py + padY

    for li, l in ipairs(lines) do
        if l.type == "header" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local hc = l.color
            nvgFillColor(vg, nvgRGBA(hc[1], hc[2], hc[3], 255))
            nvgText(vg, px + pw / 2, curY, l.text, nil)
            curY = curY + lineH
        elseif l.type == "name" then
            -- 自适应字号：名称过长时缩小字体
            local nameFontSize = 18
            nvgFontSize(vg, nameFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local nameW = nvgTextBounds(vg, 0, 0, l.text, nil, nil)
            while nameW > maxTextW and nameFontSize > 11 do
                nameFontSize = nameFontSize - 1
                nvgFontSize(vg, nameFontSize)
                nameW = nvgTextBounds(vg, 0, 0, l.text, nil, nil)
            end
            local nc = rarityDef and rarityDef.color or {255, 255, 255}
            -- 拆分名字和强化等级后缀，分别着色
            local baseName, enhSuffix = string.match(l.text, "^(.-)( %+%d+)$")
            if baseName and enhSuffix and item.enhanceLevel and item.enhanceLevel > 0 then
                -- 先量两段宽度，居中绘制
                local bw = nvgTextBounds(vg, 0, 0, baseName, nil, nil)
                local ew = nvgTextBounds(vg, 0, 0, enhSuffix, nil, nil)
                local totalW = bw + ew
                local startX = px + (pw - totalW) / 2
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(nc[1], nc[2], nc[3], 255))
                nvgText(vg, startX, curY, baseName, nil)
                local _, enhC = GS.getEnhanceRarity(item.enhanceLevel)
                nvgFillColor(vg, nvgRGBA(enhC[1], enhC[2], enhC[3], 255))
                nvgText(vg, startX + bw, curY, enhSuffix, nil)
            else
                nvgFillColor(vg, nvgRGBA(nc[1], nc[2], nc[3], 255))
                nvgText(vg, px + pw / 2, curY, l.text, nil)
            end
            curY = curY + lineH
        elseif l.type == "toughness" then
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            if l.brittle and not l.text then
                -- 仅脆化标记（无精炼韧性）
                nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
                nvgText(vg, px + pw / 2, curY, "已脆化", nil)
            elseif l.brittle then
                -- 脆化标记（红色）+ 韧性信息，同一行居中
                local brittleStr = "已脆化  "
                local tStr = l.text
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                local bw = nvgTextBounds(vg, 0, 0, brittleStr, nil, nil)
                local tw = nvgTextBounds(vg, 0, 0, tStr, nil, nil)
                local totalW = bw + tw
                local startX = px + (pw - totalW) / 2
                nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
                nvgText(vg, startX, curY, brittleStr, nil)
                -- 韧性颜色
                local tColor
                if l.curT <= 0 then tColor = {255, 80, 80}
                elseif l.curT < l.maxT then tColor = {255, 200, 80}
                else tColor = {120, 220, 120} end
                nvgFillColor(vg, nvgRGBA(tColor[1], tColor[2], tColor[3], 220))
                nvgText(vg, startX + bw, curY, tStr, nil)
            else
                -- 仅韧性信息，居中
                local tColor
                if l.curT <= 0 then tColor = {255, 80, 80}
                elseif l.curT < l.maxT then tColor = {255, 200, 80}
                else tColor = {120, 220, 120} end
                nvgFillColor(vg, nvgRGBA(tColor[1], tColor[2], tColor[3], 220))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgText(vg, px + pw / 2, curY, l.text, nil)
            end
            curY = curY + lineH
        elseif l.type == "sub" then
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local sc = l.color
            nvgFillColor(vg, sc and nvgRGBA(sc[1], sc[2], sc[3], 240) or nvgRGBA(255, 200, 60, 230))
            nvgText(vg, px + pw / 2, curY, l.text, nil)
            curY = curY + lineH
        elseif l.type == "unique_active" then
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 170, 50, 220))
            nvgText(vg, px + pw / 2, curY, l.text, nil)
            curY = curY + lineH
        elseif l.type == "rarity" then
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            local rc = l.color
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 220))
            nvgText(vg, px + pw / 2, curY, l.text, nil)
            curY = curY + lineH
        elseif l.type == "sep" then
            curY = curY + 3
            nvgBeginPath(vg)
            nvgMoveTo(vg, px + padX, curY)
            nvgLineTo(vg, px + pw - padX, curY)
            nvgStrokeColor(vg, nvgRGBA(120, 100, 70, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            curY = curY + 5
        elseif l.type == "base_effect" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local textX = px + padX
            if l.rarityTier then
                -- 上指三角形档位标记（阴影+主体+高光+描边）
                local tierRarityMap = { "common", "uncommon", "rare", "fine", "superior" }
                local rarityKey = tierRarityMap[l.rarityTier] or "common"
                local rc = GS.RARITY[rarityKey] and GS.RARITY[rarityKey].color or {200, 200, 200}
                local tcx = px + padX + 3
                local tcy = curY + 7
                local tr = 2.5
                -- 阴影
                nvgBeginPath(vg)
                nvgMoveTo(vg, tcx + 1,      tcy - tr + 1)
                nvgLineTo(vg, tcx + tr + 1, tcy + tr + 1)
                nvgLineTo(vg, tcx - tr + 1, tcy + tr + 1)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
                nvgFill(vg)
                -- 主体
                nvgBeginPath(vg)
                nvgMoveTo(vg, tcx,      tcy - tr)
                nvgLineTo(vg, tcx + tr, tcy + tr)
                nvgLineTo(vg, tcx - tr, tcy + tr)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
                nvgFill(vg)
                -- 高光（上半三角）
                nvgBeginPath(vg)
                nvgMoveTo(vg, tcx,      tcy - tr)
                nvgLineTo(vg, tcx + tr, tcy + tr)
                nvgLineTo(vg, tcx - tr, tcy + tr)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 50))
                nvgFill(vg)
                -- 描边
                nvgBeginPath(vg)
                nvgMoveTo(vg, tcx,      tcy - tr)
                nvgLineTo(vg, tcx + tr, tcy + tr)
                nvgLineTo(vg, tcx - tr, tcy + tr)
                nvgClosePath(vg)
                nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1] + 50), math.min(255, rc[2] + 50), math.min(255, rc[3] + 50), 255))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
                textX = px + padX + 10
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            else
                nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
            end
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, textX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "special" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(100, 220, 100, 255))
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, px + padX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "abyss_affix" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            -- 紫色六芒星图标
            local abyssColor = {180, 80, 220}
            local starCX = px + padX + 5
            local starCY = curY + 8
            local outerR = 5
            local innerR = 2.5
            nvgBeginPath(vg)
            for i = 0, 5 do
                local angle = math.rad(-90 + i * 60)
                local ox = starCX + outerR * math.cos(angle)
                local oy = starCY + outerR * math.sin(angle)
                if i == 0 then nvgMoveTo(vg, ox, oy) else nvgLineTo(vg, ox, oy) end
                local iAngle = math.rad(-90 + i * 60 + 30)
                local ix = starCX + innerR * math.cos(iAngle)
                local iy = starCY + innerR * math.sin(iAngle)
                nvgLineTo(vg, ix, iy)
            end
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(abyssColor[1], abyssColor[2], abyssColor[3], 240))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(220, 140, 255, 255))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            -- 词缀名称（紫色）
            local abyssTextX = px + padX + 14
            nvgFillColor(vg, nvgRGBA(abyssColor[1], abyssColor[2], abyssColor[3], 255))
            nvgText(vg, abyssTextX, curY, l.text, nil)
            curY = curY + lineH
            -- 词缀描述（浅紫色，较小字号）
            if l.desc then
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(200, 160, 240, 220))
                -- 使用预计算的 utf8 换行结果
                local descLines = (wrappedMap[li] and wrappedMap[li]._abyssDesc) or { l.desc }
                local descLineH = 15  -- 11px字号用更紧凑的行高
                for _, dline in ipairs(descLines) do
                    nvgText(vg, abyssTextX, curY, dline, nil)
                    curY = curY + descLineH
                end
            end
        elseif l.type == "enchant" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            -- 根据 T 级确定稀有度颜色
            local et = l.rolledTier or 0
            local enchRarity
            if et <= 1 then     enchRarity = "common"
            elseif et <= 3 then enchRarity = "uncommon"
            elseif et <= 5 then enchRarity = "rare"
            elseif et <= 7 then enchRarity = "fine"
            else                enchRarity = "superior"
            end
            local ec = GS.RARITY[enchRarity] and GS.RARITY[enchRarity].color or {80,160,255}
            -- 稀有度颜色四芒星图标（与装备栏右上角同款）
            local starX = px + padX + 3
            local starY2 = curY + 7
            local sr = 2.5
            nvgBeginPath(vg)
            nvgMoveTo(vg, starX, starY2 - sr)
            nvgLineTo(vg, starX + sr * 0.3, starY2 - sr * 0.3)
            nvgLineTo(vg, starX + sr, starY2)
            nvgLineTo(vg, starX + sr * 0.3, starY2 + sr * 0.3)
            nvgLineTo(vg, starX, starY2 + sr)
            nvgLineTo(vg, starX - sr * 0.3, starY2 + sr * 0.3)
            nvgLineTo(vg, starX - sr, starY2)
            nvgLineTo(vg, starX - sr * 0.3, starY2 - sr * 0.3)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(ec[1], ec[2], ec[3], 240))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(math.min(255, ec[1] + 50), math.min(255, ec[2] + 50), math.min(255, ec[3] + 50), 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 文字偏移到星星右侧
            local textOffX = px + padX + 10
            nvgFillColor(vg, nvgRGBA(ec[1], ec[2], ec[3], 255))
            local wl = wrappedMap[li] or { l.text }
            for wi, wline in ipairs(wl) do
                nvgText(vg, textOffX, curY, wline, nil)
                -- 第一行右侧显示 T 级标签（同稀有度颜色）
                if wi == 1 and l.rolledTier then
                    nvgFontSize(vg, 11)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(ec[1], ec[2], ec[3], 200))
                    nvgText(vg, px + pw - padX, curY + 1, "T" .. l.rolledTier, nil)
                    -- 恢复
                    nvgFontSize(vg, 14)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(ec[1], ec[2], ec[3], 255))
                end
                curY = curY + lineH
            end
        elseif l.type == "refine_filled" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            -- 根据 T 级确定稀有度颜色
            local rt = l.rolledTier or 0
            local refRarity
            if rt <= 1 then     refRarity = "common"
            elseif rt <= 3 then refRarity = "uncommon"
            elseif rt <= 5 then refRarity = "rare"
            elseif rt <= 7 then refRarity = "fine"
            else                refRarity = "superior"
            end
            local rc = GS.RARITY[refRarity] and GS.RARITY[refRarity].color or {200,200,200}
            -- 稀有度颜色菱形（带阴影和高光）
            local diamCx = px + padX + 3
            local diamCy = curY + 7
            local diamR = 3.0
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
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
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
            local textOffX = px + padX + 10
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            local wl = wrappedMap[li] or { l.text }
            for wi, wline in ipairs(wl) do
                nvgText(vg, textOffX, curY, wline, nil)
                -- 第一行右侧显示 T 级标签（同稀有度颜色）
                if wi == 1 and l.rolledTier then
                    nvgFontSize(vg, 11)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 200))
                    nvgText(vg, px + pw - padX, curY + 1, "T" .. l.rolledTier, nil)
                    -- 恢复
                    nvgFontSize(vg, 14)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
                end
                curY = curY + lineH
            end
        elseif l.type == "refine_empty" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            -- 灰色空心菱形
            local diamCx = px + padX + 3
            local diamCy = curY + 7
            local diamR = 3.0
            nvgBeginPath(vg)
            nvgMoveTo(vg, diamCx, diamCy - diamR)
            nvgLineTo(vg, diamCx + diamR, diamCy)
            nvgLineTo(vg, diamCx, diamCy + diamR)
            nvgLineTo(vg, diamCx - diamR, diamCy)
            nvgClosePath(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            local textOffX = px + padX + 10
            nvgFillColor(vg, nvgRGBA(120, 120, 120, 200))
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, textOffX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "gem_filled" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local rc = GS.RARITY[l.gemRarity] and GS.RARITY[l.gemRarity].color or {200,200,200}
            -- 宝石圆形图标（实心 + 高光 + 描边）
            local gemCx = px + padX + 3
            local gemCy = curY + 7
            local gemR = 3.2
            nvgBeginPath(vg)
            nvgCircle(vg, gemCx + 0.5, gemCy + 0.5, gemR)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 70))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, gemCx, gemCy, gemR)
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, gemCx - 0.5, gemCy - 0.8, gemR * 0.55)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, gemCx, gemCy, gemR)
            nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1] + 50), math.min(255, rc[2] + 50), math.min(255, rc[3] + 50), 255))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            local textOffX = px + padX + 10
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, textOffX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "gem_filled_sub" then
            -- 宝石第二行：属性+词缀，左对齐宝石名（无圆形图标）
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local rc = GS.RARITY[l.gemRarity] and GS.RARITY[l.gemRarity].color or {200,200,200}
            local textOffX = px + padX + 10
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            nvgText(vg, textOffX, curY, l.text, nil)
            curY = curY + lineH
        elseif l.type == "gem_empty" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            -- 灰色空心圆形
            local gemCx = px + padX + 3
            local gemCy = curY + 7
            local gemR = 3.2
            nvgBeginPath(vg)
            nvgCircle(vg, gemCx, gemCy, gemR)
            nvgStrokeColor(vg, nvgRGBA(120, 120, 120, 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            local textOffX = px + padX + 10
            nvgFillColor(vg, nvgRGBA(120, 120, 120, 200))
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, textOffX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "extra_effect" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local textX = px + padX
            if l.rarityTier then
                -- 词条档位方形标记（样式同精炼菱形：阴影+主体+高光+描边）
                local tierRarityMap = { "common", "uncommon", "rare", "fine", "superior" }
                local rarityKey = tierRarityMap[l.rarityTier] or "common"
                local rc = GS.RARITY[rarityKey] and GS.RARITY[rarityKey].color or {200, 200, 200}
                local sqCx = px + padX + 3
                local sqCy = curY + 7
                local sqR = 3.0
                -- 阴影
                nvgBeginPath(vg)
                nvgRect(vg, sqCx - sqR + 1, sqCy - sqR + 1, sqR * 2, sqR * 2)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
                nvgFill(vg)
                -- 主体
                nvgBeginPath(vg)
                nvgRect(vg, sqCx - sqR, sqCy - sqR, sqR * 2, sqR * 2)
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 240))
                nvgFill(vg)
                -- 高光（上半）
                nvgBeginPath(vg)
                nvgRect(vg, sqCx - sqR, sqCy - sqR, sqR * 2, sqR)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
                nvgFill(vg)
                -- 描边
                nvgBeginPath(vg)
                nvgRect(vg, sqCx - sqR, sqCy - sqR, sqR * 2, sqR * 2)
                nvgStrokeColor(vg, nvgRGBA(math.min(255, rc[1] + 50), math.min(255, rc[2] + 50), math.min(255, rc[3] + 50), 255))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
                textX = px + padX + 10
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            else
                if l.white then
                    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
                else
                    nvgFillColor(vg, nvgRGBA(100, 220, 100, 255))
                end
            end
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, textX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "set_title" then
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
            nvgText(vg, px + padX, curY, l.text, nil)
            -- 对比面板不显示[详情]按钮，避免覆盖主面板的 setDetailBtnRect
            if not headerText then
                -- "[详情]" 按钮
                local titleTW = nvgTextBounds(vg, 0, 0, l.text, nil)
                local detailBtnX = px + padX + titleTW + 6
                local detailBtnY = curY
                local detailBtnText = "[详情]"
                nvgFontSize(vg, 11)
                local detailBtnTW = nvgTextBounds(vg, 0, 0, detailBtnText, nil)
                -- 检测鼠标悬停
                local mx = input:GetMousePosition().x / (GS.dpr or 1) / (GS.S or 1)
                local my = input:GetMousePosition().y / (GS.dpr or 1) / (GS.S or 1)
                local hoverDetail = mx >= detailBtnX and mx <= detailBtnX + detailBtnTW
                    and my >= detailBtnY and my <= detailBtnY + lineH
                if hoverDetail then
                    nvgFillColor(vg, nvgRGBA(255, 255, 150, 255))
                else
                    nvgFillColor(vg, nvgRGBA(180, 170, 140, 200))
                end
                nvgText(vg, detailBtnX, curY, detailBtnText, nil)
                -- 存储按钮rect和套装数据供二级面板使用
                GS.setDetailBtnRect = { x = detailBtnX, y = detailBtnY, w = detailBtnTW, h = lineH }
                GS.setDetailData = { pieces = l.pieces, bonuses = l.bonuses }
                GS.setDetailHover = hoverDetail
            end
            curY = curY + lineH
        elseif l.type == "effect" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if l.white then
                nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
            else
                nvgFillColor(vg, nvgRGBA(100, 220, 100, 255))
            end
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, px + padX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "enhance" then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local enhLvForColor = item.enhanceLevel or 0
            local _, enhLineC = GS.getEnhanceRarity(enhLvForColor)
            nvgFillColor(vg, nvgRGBA(enhLineC[1], enhLineC[2], enhLineC[3], 255))
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, px + padX, curY, wline, nil)
                curY = curY + lineH
            end
        elseif l.type == "desc" then
            nvgFontSize(vg, descFontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(180, 170, 150, 180))
            local wl = wrappedMap[li] or { l.text }
            for _, wline in ipairs(wl) do
                nvgText(vg, px + padX, curY, wline, nil)
                curY = curY + lineH - 2
            end
            curY = curY + 4
        elseif l.type == "classreq" then
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if l.match then
                nvgFillColor(vg, nvgRGBA(100, 200, 100, 220))
            else
                nvgFillColor(vg, nvgRGBA(220, 80, 60, 230))
            end
            nvgText(vg, px + padX, curY, l.text, nil)
            curY = curY + lineH
        elseif l.type == "sellprice" and showBtn then
            -- 锁定按钮（售价行左侧）——仅背包/装备/仓库来源显示
            local isLocked = item.locked == true
            local lockBtnSz = lineH - 2
            local lockBtnX = px + padX
            local lockBtnY = curY + 1
            -- 底板背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, lockBtnX, lockBtnY, lockBtnSz, lockBtnSz, 3)
            if isLocked then
                nvgFillColor(vg, nvgRGBA(180, 60, 60, 80))
            else
                nvgFillColor(vg, nvgRGBA(120, 120, 120, 60))
            end
            nvgFill(vg)
            nvgStrokeColor(vg, isLocked and nvgRGBA(220, 80, 80, 120) or nvgRGBA(150, 150, 150, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 锁定图标（图片）
            local lockImg = isLocked and M.lockClosedImg or M.lockOpenImg
            if lockImg and lockImg > 0 then
                local iconSz = lockBtnSz - 4
                local iconOff = 2
                local paint = nvgImagePattern(vg, lockBtnX + iconOff, lockBtnY + iconOff, iconSz, iconSz, 0, lockImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, lockBtnX + iconOff, lockBtnY + iconOff, iconSz, iconSz)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
            if not headerText then
                GS.tooltipLockBtnRect = { x = lockBtnX, y = lockBtnY, w = lockBtnSz, h = lockBtnSz }
            end
            -- 收藏按钮（锁定按钮右侧）
            local isFav = item.starred == true
            local favBtnX = lockBtnX + lockBtnSz + 3
            local favBtnY = lockBtnY
            nvgBeginPath(vg)
            nvgRoundedRect(vg, favBtnX, favBtnY, lockBtnSz, lockBtnSz, 3)
            if isFav then
                nvgFillColor(vg, nvgRGBA(180, 160, 40, 80))
            else
                nvgFillColor(vg, nvgRGBA(120, 120, 120, 60))
            end
            nvgFill(vg)
            nvgStrokeColor(vg, isFav and nvgRGBA(220, 200, 60, 120) or nvgRGBA(150, 150, 150, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 星星图标（路径绘制）
            local starBtnR = (lockBtnSz - 4) * 0.5
            M.drawStarPath(vg, favBtnX + lockBtnSz / 2, favBtnY + lockBtnSz / 2, starBtnR, "btn", isFav)
            if not headerText then
                GS.tooltipFavBtnRect = { x = favBtnX, y = favBtnY, w = lockBtnSz, h = lockBtnSz }
            end
            -- 售价文本（右对齐，垂直居中）——仅有价格时显示
            if l.text then
                local lockY = curY + lineH / 2
                nvgFontSize(vg, 13)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(220, 190, 100, 230))
                nvgText(vg, px + pw - padX, lockY, l.text, nil)
            end
            curY = curY + lineH
        end
    end

    -- 操作按钮（装备/卸下/使用）
    local btnRect = nil
    local hasBtn = showBtn and (item.slot or item.consumable or hasUseEffect)
    if hasBtn then
        local btnW = pw - padX * 2
        local btnX = px + padX
        local btnY = curY + 4
        btnRect = { x = btnX, y = btnY, w = btnW, h = btnH }

        local btnBg, btnBord, btnTxt, btnTxtC
        if item.consumable or hasUseEffect then
            local pLv = GS.player and GS.player.level or 1
            local canUse = not item.level or pLv >= item.level
            if canUse then
                btnBg   = {50, 80, 120}
                btnBord = {80, 130, 180}
                btnTxt  = "使用"
                btnTxtC = {210, 230, 255}
            else
                btnBg   = {70, 70, 70}
                btnBord = {100, 100, 100}
                btnTxt  = "等级不足"
                btnTxtC = {150, 150, 150}
            end
        elseif isEquipSource then
            btnBg   = {100, 55, 45}
            btnBord = {160, 90, 70}
            btnTxt  = "卸下"
            btnTxtC = {240, 215, 210}
        else
            local pLv = GS.player and GS.player.level or 1
            local canEquip = not item.level or pLv >= item.level
            local classOk = true
            local classMsg = ""
            if item.slot == "weapon_r" and item.weaponTag then
                local a = GS.CLASS_WEAPON_R and GS.CLASS_WEAPON_R[GS.currentClass]
                if a and not a[item.weaponTag] then classOk = false; classMsg = item.weaponTag end
            elseif item.slot == "weapon_l" and item.offhandTag then
                if not GS.checkOffhand(item.offhandTag) then classOk = false; classMsg = item.offhandTag end
            end
            if canEquip and classOk then
                btnBg   = {60, 100, 50}
                btnBord = {100, 160, 80}
                btnTxt  = "装备"
                btnTxtC = {220, 240, 210}
            elseif not classOk then
                btnBg   = {70, 70, 70}
                btnBord = {100, 100, 100}
                btnTxt  = "无法装备" .. classMsg
                btnTxtC = {150, 150, 150}
            else
                btnBg   = {70, 70, 70}
                btnBord = {100, 100, 100}
                btnTxt  = "等级不足"
                btnTxtC = {150, 150, 150}
            end
        end

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(btnBg[1], btnBg[2], btnBg[3], 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgStrokeColor(vg, nvgRGBA(btnBord[1], btnBord[2], btnBord[3], 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(btnTxtC[1], btnTxtC[2], btnTxtC[3], 255))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, btnTxt, nil)
        curY = curY + 4 + btnH
    end

    -- 阅读按钮（阅读物专用）
    if showBtn and isReadable then
        local rBtnW = pw - padX * 2
        local rBtnX = px + padX
        local rBtnY = curY + 4
        GS.tooltipReadBtnRect = { x = rBtnX, y = rBtnY, w = rBtnW, h = btnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rBtnX, rBtnY, rBtnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(80, 60, 40, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rBtnX, rBtnY, rBtnW, btnH, 4)
        nvgStrokeColor(vg, nvgRGBA(160, 130, 80, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 220, 180, 255))
        nvgText(vg, rBtnX + rBtnW / 2, rBtnY + btnH / 2, "阅读", nil)
    end

    return { x = px, y = py, w = pw, h = contentH }, btnRect
end

-- 物品悬停信息面板
-- ====================================================================
function M.drawItemTooltip()
    local item = GS.tooltipItem
    if not item then
        GS.tooltipRect = nil
        GS.tooltipEquipBtnRect = nil
        GS.tooltipLockBtnRect = nil
        GS.tooltipFavBtnRect = nil
        GS.tooltipReadBtnRect = nil
        GS.setDetailBtnRect = nil
        GS.setDetailData = nil
        GS.setDetailHover = false
        GS.tooltipScrollY = 0
        GS.tooltipNeedScroll = false
        GS.tooltipMaxScrollY = 0
        GS.tooltipCmpScrollY = 0
        GS.tooltipCmpNeedScroll = false
        GS.tooltipCmpMaxScrollY = 0
        GS.tooltipCmpRect = nil
        return
    end

    local vg = M.vg
    local slotArea
    local isEquipSource = (GS.tooltipSource == "equipment")
    if GS.tooltipSource == "shop" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "warehouse" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "exchange" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "lost_items" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "alchemy" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "craft" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "forge" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "cooking" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "shared_storage" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "signin" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "reward_preview" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif GS.tooltipSource == "abyss_exchange" and GS.tooltipAnchorRect then
        slotArea = GS.tooltipAnchorRect
    elseif isEquipSource and GS.tooltipEquipSlotId then
        slotArea = GS.equipSlotAreas and GS.equipSlotAreas[GS.tooltipEquipSlotId]
    else
        slotArea = GS.inventorySlotAreas and GS.inventorySlotAreas[GS.tooltipSlotIdx]
    end
    if not slotArea then
        GS.tooltipRect = nil
        GS.tooltipEquipBtnRect = nil
        return
    end

    local pw = 180
    local gap = 4

    -- 判断是否需要显示对比面板（背包物品 + 对应槽位已有装备）
    local compareItem = nil
    if not isEquipSource and item.slot
        and GS.tooltipSource ~= "reward_preview" then
        compareItem = GS.equipment[item.slot]
    end

    -- 计算主面板位置（先用临时 y 计算高度；商店/兑换来源不显示按钮）
    local isReadOnlySource = (GS.tooltipSource == "shop" or GS.tooltipSource == "exchange"
        or GS.tooltipSource == "lost_items" or GS.tooltipSource == "alchemy"
        or GS.tooltipSource == "craft" or GS.tooltipSource == "forge"
        or GS.tooltipSource == "cooking" or GS.tooltipSource == "shared_storage"
        or GS.tooltipSource == "signin" or GS.tooltipSource == "reward_preview"
        or GS.tooltipSource == "abyss_exchange")
    local isShopSource = isReadOnlySource
    local mainRect = drawTooltipPanel(vg, item, 0, -9999, pw, not isReadOnlySource, isEquipSource)
    local mainH = mainRect.h

    -- 如果有对比面板，先计算对比高度以确定最终 y 位置
    local cmpH = 0
    if compareItem then
        local cmpRect = drawTooltipPanel(vg, compareItem, 0, -9999, pw, false, false, "当前装备", {255, 215, 0})
        cmpH = cmpRect.h
    end
    local maxH = math.max(mainH, cmpH)

    -- 面板位置（pinned 时复用已保存的位置，避免随鼠标移动）
    local totalW = compareItem and (pw + gap + pw) or pw
    local px, py
    if GS.tooltipPinned and GS.tooltipPinnedPos then
        px = GS.tooltipPinnedPos.px
        py = GS.tooltipPinnedPos.py
    else
        px = slotArea.x + slotArea.w / 2 - totalW / 2
        py = slotArea.y - maxH - 4
        -- 三层边界防护：翻转 → 再翻转 → 强制 clamp
        if py < GS.TOP_BAR_H then
            py = slotArea.y + slotArea.h + 4
        end
        if py + maxH > GS.SCREEN_H - 4 then py = GS.TOP_BAR_H + 2 end
        if px < 4 then px = slotArea.x + slotArea.w + 4 end
        if px + totalW > GS.SCREEN_W - 4 then px = slotArea.x - totalW - 4 end
        if px < 4 then px = 4 end
        if px + totalW > GS.SCREEN_W - 4 then px = GS.SCREEN_W - 4 - totalW end

        -- 防止 tooltip 遮挡源格子（确保不重叠）
        local tooltipRight = px + totalW
        local tooltipBottom = py + maxH
        local slotRight = slotArea.x + slotArea.w
        local slotBottom = slotArea.y + slotArea.h
        local overlapsX = px < slotRight and tooltipRight > slotArea.x
        local overlapsY = py < slotBottom and tooltipBottom > slotArea.y
        if overlapsX and overlapsY then
            -- 尝试放到格子右侧
            local tryPx = slotRight + 4
            if tryPx + totalW <= GS.SCREEN_W - 4 then
                px = tryPx
            else
                -- 放到格子左侧
                px = slotArea.x - totalW - 4
                if px < 4 then px = 4 end
            end
        end
        -- pinned 时保存位置
        if GS.tooltipPinned then
            GS.tooltipPinnedPos = { px = px, py = py }
        end
    end

    -- ============ 滚动支持：主面板和对比面板独立滚动 ============
    local availH = GS.SCREEN_H - py - 4
    local origPy = py

    -- 主面板滚动
    local mainNeedScroll = mainH > availH and availH > 80
    GS.tooltipNeedScroll = mainNeedScroll
    if mainNeedScroll then
        if not GS.tooltipScrollY then GS.tooltipScrollY = 0 end
        local maxScrollAmt = mainH - availH
        GS.tooltipScrollY = math.max(0, math.min(GS.tooltipScrollY, maxScrollAmt))
        GS.tooltipMaxScrollY = maxScrollAmt
    else
        GS.tooltipScrollY = 0
        GS.tooltipMaxScrollY = 0
    end

    -- 对比面板滚动
    local cmpNeedScroll = compareItem and cmpH > availH and availH > 80
    GS.tooltipCmpNeedScroll = cmpNeedScroll or false
    if cmpNeedScroll then
        if not GS.tooltipCmpScrollY then GS.tooltipCmpScrollY = 0 end
        local cmpMaxScroll = cmpH - availH
        GS.tooltipCmpScrollY = math.max(0, math.min(GS.tooltipCmpScrollY, cmpMaxScroll))
        GS.tooltipCmpMaxScrollY = cmpMaxScroll
    else
        GS.tooltipCmpScrollY = 0
        GS.tooltipCmpMaxScrollY = 0
    end

    -- 绘制面板：有对比时，指向装备靠近鼠标，当前装备放远端
    local mainPanelRect
    if compareItem then
        -- 判断鼠标在 tooltip 区域的左侧还是右侧，决定近远端
        local mainOnLeft
        if GS.tooltipPinned and GS.tooltipPinnedPos and GS.tooltipPinnedPos.mainOnLeft ~= nil then
            mainOnLeft = GS.tooltipPinnedPos.mainOnLeft
        else
            local mousePos = input:GetMousePosition()
            local mouseSX = mousePos.x / GS.dpr / GS.S
            local tooltipCenterX = px + totalW / 2
            mainOnLeft = (mouseSX < tooltipCenterX)
            if GS.tooltipPinned and GS.tooltipPinnedPos then
                GS.tooltipPinnedPos.mainOnLeft = mainOnLeft
            end
        end

        local showBtn = not isReadOnlySource
        local mainX = mainOnLeft and px or (px + pw + gap)
        local cmpX = mainOnLeft and (px + pw + gap) or px

        -- 绘制主面板（独立 scissor + scroll）
        local mainPy = origPy
        if mainNeedScroll then
            nvgSave(vg)
            nvgScissor(vg, mainX - 2, origPy - 2, pw + 4, availH + 6)
            mainPy = origPy - GS.tooltipScrollY
        end
        local rect, btnRect = drawTooltipPanel(vg, item, mainX, mainPy, pw, showBtn, isEquipSource)
        GS.tooltipRect = rect
        GS.tooltipEquipBtnRect = btnRect
        mainPanelRect = rect
        if mainNeedScroll then nvgRestore(vg) end

        -- 绘制对比面板（独立 scissor + scroll）
        local cmpPy = origPy
        if cmpNeedScroll then
            nvgSave(vg)
            nvgScissor(vg, cmpX - 2, origPy - 2, pw + 4, availH + 6)
            cmpPy = origPy - GS.tooltipCmpScrollY
        end
        local cmpRect = drawTooltipPanel(vg, compareItem, cmpX, cmpPy, pw, false, false, "当前装备", {255, 215, 0})
        GS.tooltipCmpRect = cmpRect
        if cmpNeedScroll then nvgRestore(vg) end
    else
        -- 无对比，直接绘制主面板
        GS.tooltipCmpRect = nil
        local showBtn = not isReadOnlySource
        local mainPy = origPy
        if mainNeedScroll then
            nvgSave(vg)
            nvgScissor(vg, px - 2, origPy - 2, pw + 4, availH + 6)
            mainPy = origPy - GS.tooltipScrollY
        end
        local rect, btnRect = drawTooltipPanel(vg, item, px, mainPy, pw, showBtn, isEquipSource)
        GS.tooltipRect = rect
        GS.tooltipEquipBtnRect = btnRect
        mainPanelRect = rect
        if mainNeedScroll then nvgRestore(vg) end
    end

    -- ============ 滚动条指示器 ============
    local function drawScrollBar(scrollY, maxScrollY, needScroll, barPx, panelH)
        if not needScroll then return end
        local barW = 3
        local barX = barPx
        local barY = origPy + 4
        local barH = availH - 8
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 1.5)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
        nvgFill(vg)
        local thumbRatio = availH / panelH
        local thumbH = math.max(16, barH * thumbRatio)
        local scrollRatio = maxScrollY > 0 and (scrollY / maxScrollY) or 0
        local thumbY = barY + scrollRatio * (barH - thumbH)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, barW, thumbH, 1.5)
        nvgFillColor(vg, nvgRGBA(200, 180, 140, 150))
        nvgFill(vg)
    end
    if mainNeedScroll then
        local mainBarX = (GS.tooltipRect and (GS.tooltipRect.x + pw - 4)) or (px + pw - 4)
        drawScrollBar(GS.tooltipScrollY, GS.tooltipMaxScrollY, true, mainBarX, mainH)
    end
    if cmpNeedScroll then
        local cmpBarX = (GS.tooltipCmpRect and (GS.tooltipCmpRect.x + pw - 4)) or (px + pw + gap + pw - 4)
        drawScrollBar(GS.tooltipCmpScrollY, GS.tooltipCmpMaxScrollY, true, cmpBarX, cmpH)
    end
    -- 修正 rect 为可见区域
    if mainNeedScroll or cmpNeedScroll then
        if mainPanelRect then
            mainPanelRect = {
                x = mainPanelRect.x, y = origPy,
                w = mainPanelRect.w, h = math.min(mainPanelRect.h, availH),
            }
        end
        if GS.tooltipRect then
            GS.tooltipRect = {
                x = GS.tooltipRect.x, y = origPy,
                w = GS.tooltipRect.w, h = math.min(GS.tooltipRect.h, availH),
            }
        end
        if GS.tooltipCmpRect then
            GS.tooltipCmpRect = {
                x = GS.tooltipCmpRect.x, y = origPy,
                w = GS.tooltipCmpRect.w, h = math.min(GS.tooltipCmpRect.h, availH),
            }
        end
    end

    -- 套装详情二级悬停面板（悬停或点击固定时显示）
    if (GS.setDetailHover or GS.setDetailPinned) and GS.setDetailData and mainPanelRect then
        local sd = GS.setDetailData
        local padX2 = 8
        local padY2 = 6
        local lineH2 = 16
        local spw = 160  -- 二级面板宽度

        -- 计算二级面板高度
        local spH = padY2
        -- 套装组件标题
        spH = spH + lineH2
        -- 组件列表
        if sd.pieces then spH = spH + #sd.pieces * lineH2 end
        -- 间隔
        spH = spH + 6
        -- 套装效果标题
        spH = spH + lineH2
        -- 效果列表（需要换行计算）
        if sd.bonuses then
            for _, b in ipairs(sd.bonuses) do
                nvgFontSize(vg, 12)
                nvgFontFace(vg, "sans")
                local btw = nvgTextBounds(vg, 0, 0, b.text, nil)
                local wrapLines = math.max(1, math.ceil(btw / (spw - padX2 * 2)))
                spH = spH + wrapLines * lineH2
            end
        end
        spH = spH + padY2

        -- 定位：紧贴主面板右侧
        local spx = mainPanelRect.x + mainPanelRect.w + 4
        local spy = mainPanelRect.y
        -- 如果右侧放不下，放到左侧
        if spx + spw > GS.SCREEN_W - 4 then
            spx = mainPanelRect.x - spw - 4
        end
        if spx < 4 then spx = 4 end
        -- 垂直边界
        if spy + spH > GS.SCREEN_H - 4 then
            spy = GS.SCREEN_H - 4 - spH
        end
        if spy < GS.TOP_BAR_H then spy = GS.TOP_BAR_H + 2 end

        -- 存储二级面板rect供点击检测
        GS.setDetailPanelRect = { x = spx, y = spy, w = spw, h = spH }

        -- 绘制二级面板背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, spx, spy, spw, spH, 6)
        nvgFillColor(vg, nvgRGBA(20, 18, 25, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 60, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        local cy = spy + padY2

        -- 套装组件标题
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
        nvgText(vg, spx + padX2, cy, "套装组件", nil)
        cy = cy + lineH2

        -- 组件列表
        if sd.pieces then
            nvgFontSize(vg, 12)
            for _, p in ipairs(sd.pieces) do
                if p.active then
                    nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
                else
                    nvgFillColor(vg, nvgRGBA(100, 100, 100, 160))
                end
                nvgText(vg, spx + padX2 + 6, cy, p.text, nil)
                cy = cy + lineH2
            end
        end

        -- 间隔线
        cy = cy + 3
        nvgBeginPath(vg)
        nvgMoveTo(vg, spx + padX2, cy)
        nvgLineTo(vg, spx + spw - padX2, cy)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        cy = cy + 3

        -- 套装效果标题
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
        nvgText(vg, spx + padX2, cy, "套装效果", nil)
        cy = cy + lineH2

        -- 效果列表（支持换行）
        if sd.bonuses then
            nvgFontSize(vg, 12)
            local maxBonusTW = spw - padX2 * 2
            for _, b in ipairs(sd.bonuses) do
                if b.active then
                    nvgFillColor(vg, nvgRGBA(100, 220, 100, 255))
                else
                    nvgFillColor(vg, nvgRGBA(100, 100, 100, 160))
                end
                -- 简易换行
                local btw = nvgTextBounds(vg, 0, 0, b.text, nil)
                if btw <= maxBonusTW then
                    nvgText(vg, spx + padX2, cy, b.text, nil)
                    cy = cy + lineH2
                else
                    -- 逐字换行
                    local cur = ""
                    for _, code in utf8.codes(b.text) do
                        local ch = utf8.char(code)
                        local test = cur .. ch
                        local tw2 = nvgTextBounds(vg, 0, 0, test, nil)
                        if tw2 > maxBonusTW and cur ~= "" then
                            nvgText(vg, spx + padX2, cy, cur, nil)
                            cy = cy + lineH2
                            cur = ch
                        else
                            cur = test
                        end
                    end
                    if cur ~= "" then
                        nvgText(vg, spx + padX2, cy, cur, nil)
                        cy = cy + lineH2
                    end
                end
            end
        end
    else
        GS.setDetailPanelRect = nil
    end
end

--- 阅读弹窗（全屏遮罩 + 居中弹窗 + 右上角X关闭）
function M.drawReadingPopup()
    if not GS.readingPopupVisible then return end
    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    local dlgW = math.min(W * 0.8, 340)
    local dlgH = math.min(H * 0.7, 300)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14
    local titleH = 30

    -- 弹窗背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(180, 150, 90, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    local title = GS.readingPopupTitle or "阅读"
    nvgText(vg, dlgX + dlgW / 2, dlgY + titleH / 2, title, nil)

    -- 标题分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, dlgX + pad, dlgY + titleH)
    nvgLineTo(vg, dlgX + dlgW - pad, dlgY + titleH)
    nvgStrokeColor(vg, nvgRGBA(150, 120, 70, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 左上角 X 按钮
    local closeSz = 20
    local closeX = dlgX + 6
    local closeY = dlgY + (titleH - closeSz) / 2
    GS.readingPopupCloseRect = { x = closeX, y = closeY, w = closeSz, h = closeSz }
    -- X 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeSz, closeSz, 3)
    nvgFillColor(vg, nvgRGBA(120, 40, 40, 160))
    nvgFill(vg)
    -- X 图标
    local cx, cy = closeX + closeSz / 2, closeY + closeSz / 2
    local cr = closeSz * 0.3
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - cr, cy - cr)
    nvgLineTo(vg, cx + cr, cy + cr)
    nvgMoveTo(vg, cx + cr, cy - cr)
    nvgLineTo(vg, cx - cr, cy + cr)
    nvgStrokeColor(vg, nvgRGBA(240, 220, 200, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 正文内容（支持滚动）
    local textX = dlgX + pad
    local textAreaY = dlgY + titleH + pad
    local textW = dlgW - pad * 2
    local textAreaH = dlgH - titleH - pad * 2
    local scrollBarW = 4

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 计算文本总高度
    local bodyText = GS.readingPopupText or ""
    local drawTextW = textW - scrollBarW - 4
    local bounds = nvgTextBoxBounds(vg, textX, 0, drawTextW, bodyText)
    local contentH = 14
    if bounds and #bounds >= 4 then
        contentH = bounds[4] - bounds[2]
    end
    if contentH <= 14 then
        -- fallback：用行高估算
        local _, _, lineH = nvgTextMetrics(vg)
        if lineH and lineH > 0 then
            -- 粗略估算行数
            local lineCount = 1
            for _ in bodyText:gmatch("\n") do lineCount = lineCount + 1 end
            -- 每行字符数
            local charsPerLine = math.max(1, math.floor(drawTextW / 8))
            for line in bodyText:gmatch("[^\n]+") do
                local lineLen = #line
                lineCount = lineCount + math.max(0, math.ceil(lineLen / charsPerLine) - 1)
            end
            contentH = lineCount * lineH
        end
    end

    -- 滚动状态
    local maxScroll = math.max(0, contentH - textAreaH)
    if not GS.readingPopupScrollY then GS.readingPopupScrollY = 0 end
    GS.readingPopupScrollY = math.max(0, math.min(GS.readingPopupScrollY, maxScroll))
    local scrollY = GS.readingPopupScrollY

    -- 存储文本区域用于拖动检测
    GS.readingPopupTextRect = { x = dlgX, y = textAreaY, w = dlgW, h = textAreaH }
    GS.readingPopupMaxScroll = maxScroll

    -- 裁剪文本区域
    nvgSave(vg)
    nvgScissor(vg, dlgX + pad, textAreaY, dlgW - pad * 2, textAreaH)
    nvgFillColor(vg, nvgRGBA(220, 210, 190, 240))
    nvgTextBox(vg, textX, textAreaY - scrollY, drawTextW, bodyText, nil)
    nvgRestore(vg)

    -- 滚动条（仅在需要滚动时显示）
    if maxScroll > 0 then
        local barX = dlgX + dlgW - pad - scrollBarW
        local barTrackH = textAreaH
        local barH = math.max(20, barTrackH * (textAreaH / contentH))
        local barY = textAreaY + (barTrackH - barH) * (scrollY / maxScroll)
        -- 轨道
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, textAreaY, scrollBarW, barTrackH, 2)
        nvgFillColor(vg, nvgRGBA(100, 80, 50, 60))
        nvgFill(vg)
        -- 滑块
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, scrollBarW, barH, 2)
        nvgFillColor(vg, nvgRGBA(180, 150, 90, 180))
        nvgFill(vg)
    end
end

--- 学会精灵语能力弹窗
function M.drawElfvahLearnedPopup()
    if not GS.elfvahLearnedPopupVisible then return end
    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local pad = 14
    local cornerR = 8
    local dlgW = math.min(W * 0.8, 300)
    local dlgH = math.min(H * 0.45, 150)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2

    -- 背景（深色）
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
    nvgFontSize(vg, 17)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "精灵语言学习者", nil)

    -- 正文
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local textW = dlgW - pad * 2
    local textY = dlgY + pad + 26
    nvgTextBox(vg, dlgX + pad, textY, textW, "经过研习《伊芙瓦精灵语基础》，你学会了使用伊芙瓦精灵语进行基础交谈的能力。", nil)

    -- 确定按钮（绿色渐变，居中）
    local btnW = 60
    local btnH = 24
    local btnBaseY = dlgY + dlgH - pad - btnH
    local btnX = dlgX + (dlgW - btnW) / 2
    GS.elfvahLearnedConfirmRect = { x = btnX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnBaseY, btnW, btnH, 3)
    local gGrad = nvgLinearGradient(vg, btnX, btnBaseY, btnX, btnBaseY + btnH,
        nvgRGBA(40, 140, 45, 230), nvgRGBA(25, 100, 30, 230))
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 255, 220, 250))
    nvgText(vg, btnX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)

    if isHovered(btnX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, btnX, btnBaseY, btnW, btnH, 3)
    end
end

--- "你没有找到艾莉雅"提示弹窗
function M.drawElfNotFoundPopup()
    if not GS.elfNotFoundPopup then return end
    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local pad = 14
    local cornerR = 8
    local dlgW = math.min(W * 0.7, 240)
    local dlgH = math.min(H * 0.35, 110)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2

    -- 背景
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

    -- 正文
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + dlgH * 0.38, "你没有找到艾莉雅\u{3002}", nil)

    -- 确定按钮
    local btnW = 60
    local btnH = 24
    local btnBaseY = dlgY + dlgH - pad - btnH
    local btnX = dlgX + (dlgW - btnW) / 2
    GS.elfNotFoundConfirmRect = { x = btnX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnBaseY, btnW, btnH, 3)
    local gGrad = nvgLinearGradient(vg, btnX, btnBaseY, btnX, btnBaseY + btnH,
        nvgRGBA(40, 140, 45, 230), nvgRGBA(25, 100, 30, 230))
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 255, 220, 250))
    nvgText(vg, btnX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)

    if isHovered(btnX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, btnX, btnBaseY, btnW, btnH, 3)
    end
end

--- 销毁确认弹窗（全屏遮罩 + 居中弹窗）
function M.drawDestroyConfirmDialog()
    if not GS.destroyConfirmVisible then return end
    if not GS.destroyConfirmBatch and not GS.destroyConfirmItem then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩覆盖全屏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸（设计坐标，nvgScale 已处理缩放）
    local dlgW = math.min(W * 0.7, 260)
    local dlgH = math.min(H * 0.35, 130)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 弹窗边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 提示文字
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    if GS.destroyConfirmBatch then
        -- 批量销毁/出售模式
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
        nvgText(vg, dlgX + dlgW / 2, dlgY + pad, GS.shopMode and "是否确认出售" or "是否确认销毁", nil)

        nvgFontSize(vg, 16)
        nvgFillColor(vg, GS.shopMode and nvgRGBA(40, 130, 40, 255) or nvgRGBA(180, 50, 35, 255))
        local batchCount = 0
        for _ in pairs(GS.invSelected or {}) do batchCount = batchCount + 1 end
        nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 22, "选中的 " .. batchCount .. " 件物品？", nil)

        -- 批量出售时显示预计金币
        if GS.shopMode then
            local totalGold = 0
            for idx in pairs(GS.invSelected) do
                if GS.inventory[idx] then
                    local price = GS.getItemSellPrice(GS.inventory[idx])
                    local qty = GS.inventory[idx].quantity or 1
                    totalGold = totalGold + price * qty
                end
            end
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(180, 140, 30, 255))
            nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 44, "预计获得: " .. totalGold .. " G", nil)
        end
    else
        -- 单个物品销毁/出售模式
        local itemName = GS.destroyConfirmItem.name or "物品"
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
        nvgText(vg, dlgX + dlgW / 2, dlgY + pad, GS.shopMode and "确定出售" or "确定销毁", nil)

        local rd = GS.RARITY[GS.destroyConfirmItem.rarity or "common"] or GS.RARITY.common
        local rc = rd.color
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 20, itemName, nil)

        -- 单个出售时显示预计金币
        if GS.shopMode and GS.destroyConfirmSlotIdx and GS.inventory[GS.destroyConfirmSlotIdx] then
            local item = GS.inventory[GS.destroyConfirmSlotIdx]
            local price = GS.getItemSellPrice(item)
            local qty = item.quantity or 1
            local total = price * qty
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(180, 140, 30, 255))
            nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 42, "预计获得: " .. total .. " G", nil)
        else
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(200, 160, 120, 255))
            nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 42, "？", nil)
        end
    end

    -- 按钮区域
    local btnW = 60
    local btnH = 24
    local btnGap = 16
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮
    local cancelX = btnStartX
    GS.destroyConfirmNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 3)
    local cGrad = nvgLinearGradient(vg, cancelX, btnBaseY, cancelX, btnBaseY + btnH,
        nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
    nvgFillPaint(vg, cGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 150))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)

    -- 取消按钮 hover 高亮
    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 3)
    end

    -- 确定按钮（红色）
    local confirmX = btnStartX + btnW + btnGap
    GS.destroyConfirmYesRect = { x = confirmX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnBaseY, btnW, btnH, 3)
    local rGrad = nvgLinearGradient(vg, confirmX, btnBaseY, confirmX, btnBaseY + btnH,
        nvgRGBA(180, 50, 35, 230), nvgRGBA(140, 30, 15, 230))
    nvgFillPaint(vg, rGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(220, 120, 80, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFillColor(vg, nvgRGBA(255, 220, 200, 250))
    nvgText(vg, confirmX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)

    -- 确定按钮 hover 高亮
    if isHovered(confirmX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, confirmX, btnBaseY, btnW, btnH, 3)
    end
end

-- ====================================================================
-- 洗点弹窗（素质/技能选择 + 确定/取消）
-- ====================================================================
function M.drawRespecPopupDialog()
    if not GS.respecPopupVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
    nvgFill(vg)

    -- 弹窗尺寸
    local dlgW = math.min(W * 0.75, 280)
    local dlgH = math.min(H * 0.5, 200)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 弹窗背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 245))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "洗点", nil)

    -- 副标题说明
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(200, 180, 140, 200))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 24, "观看广告后重置已分配的点数", nil)

    -- 选项区域
    local optY = dlgY + pad + 54
    local optW = dlgW * 0.38
    local optH = 50
    local gap = dlgW * 0.06
    local optX1 = dlgX + (dlgW - optW * 2 - gap) / 2
    local optX2 = optX1 + optW + gap

    local choice = GS.respecPopupChoice

    -- 素质选项
    local sel1 = (choice == "stats")
    nvgBeginPath(vg)
    nvgRoundedRect(vg, optX1, optY, optW, optH, 6)
    if sel1 then
        nvgFillColor(vg, nvgRGBA(80, 60, 20, 255))
    else
        nvgFillColor(vg, nvgRGBA(50, 40, 20, 200))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, optX1 + 0.5, optY + 0.5, optW - 1, optH - 1, 6)
    nvgStrokeColor(vg, sel1 and nvgRGBA(255, 210, 80, 255) or nvgRGBA(150, 130, 80, 180))
    nvgStrokeWidth(vg, sel1 and 2 or 1)
    nvgStroke(vg)

    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, sel1 and nvgRGBA(255, 230, 140, 255) or nvgRGBA(200, 180, 140, 220))
    nvgText(vg, optX1 + optW / 2, optY + optH / 2 - 8, "素质", nil)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(180, 160, 120, 180))
    nvgText(vg, optX1 + optW / 2, optY + optH / 2 + 10, "重置属性加点", nil)

    GS.respecStatsRect = { x = optX1, y = optY, w = optW, h = optH }

    -- 技能选项
    local sel2 = (choice == "skills")
    nvgBeginPath(vg)
    nvgRoundedRect(vg, optX2, optY, optW, optH, 6)
    if sel2 then
        nvgFillColor(vg, nvgRGBA(80, 60, 20, 255))
    else
        nvgFillColor(vg, nvgRGBA(50, 40, 20, 200))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, optX2 + 0.5, optY + 0.5, optW - 1, optH - 1, 6)
    nvgStrokeColor(vg, sel2 and nvgRGBA(255, 210, 80, 255) or nvgRGBA(150, 130, 80, 180))
    nvgStrokeWidth(vg, sel2 and 2 or 1)
    nvgStroke(vg)

    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, sel2 and nvgRGBA(255, 230, 140, 255) or nvgRGBA(200, 180, 140, 220))
    nvgText(vg, optX2 + optW / 2, optY + optH / 2 - 8, "技能", nil)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(180, 160, 120, 180))
    nvgText(vg, optX2 + optW / 2, optY + optH / 2 + 10, "重置技能加点", nil)

    GS.respecSkillsRect = { x = optX2, y = optY, w = optW, h = optH }

    -- 底部按钮
    local btnW = dlgW * 0.35
    local btnH = 32
    local btnY = dlgY + dlgH - pad - btnH
    local btnGap = 20
    local btnX1 = dlgX + (dlgW - btnW * 2 - btnGap) / 2
    local btnX2 = btnX1 + btnW + btnGap

    -- 取消按钮
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX1, btnY, btnW, btnH, 5)
    nvgFillColor(vg, nvgRGBA(60, 50, 35, 240))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX1 + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 5)
    nvgStrokeColor(vg, nvgRGBA(150, 130, 80, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 140, 240))
    nvgText(vg, btnX1 + btnW / 2, btnY + btnH / 2, "取消", nil)
    GS.respecCancelRect = { x = btnX1, y = btnY, w = btnW, h = btnH }

    -- 确定按钮（未选择时灰色）
    local canConfirm = (choice ~= nil)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX2, btnY, btnW, btnH, 5)
    if canConfirm then
        nvgFillColor(vg, nvgRGBA(120, 90, 20, 240))
    else
        nvgFillColor(vg, nvgRGBA(50, 45, 35, 240))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX2 + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 5)
    nvgStrokeColor(vg, canConfirm and nvgRGBA(210, 180, 100, 240) or nvgRGBA(100, 90, 60, 150))
    nvgStrokeWidth(vg, canConfirm and 2 or 1)
    nvgStroke(vg)
    nvgFontSize(vg, 15)
    nvgFillColor(vg, canConfirm and nvgRGBA(255, 230, 140, 255) or nvgRGBA(120, 110, 80, 180))
    nvgText(vg, btnX2 + btnW / 2, btnY + btnH / 2, "确定", nil)
    GS.respecConfirmRect = { x = btnX2, y = btnY, w = btnW, h = btnH }
end

-- ====================================================================
-- 堆叠物品拆分弹窗（滑动条选择拆分数量）
-- ====================================================================
function M.drawSplitPopupDialog()
    if not GS.splitPopupVisible then return end
    local item = GS.splitPopupItem
    local total = GS.splitPopupTotal
    if not item or total < 2 then
        GS.splitPopupVisible = false
        return
    end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H
    local qty = GS.splitPopupValue or 1

    -- 限制范围
    if qty < 1 then qty = 1; GS.splitPopupValue = 1 end
    if qty >= total then qty = total - 1; GS.splitPopupValue = qty end

    local maxQty = total - 1  -- 最多拆出 total-1 个（至少留1个）

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    local dlgW = math.min(W * 0.85, 300)
    local dlgH = math.min(H * 0.55, 240)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 12

    -- 背景
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
    local cy = dlgY + pad
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, cy, "拆分物品", nil)
    cy = cy + 20

    -- 物品名（带稀有度颜色）
    local tpl = GS.itemTemplates and GS.itemTemplates[item.templateId]
    local itemName = tpl and tpl.name or (item.name or "物品")
    local rd = GS.RARITY[(tpl and tpl.rarity) or (item.rarity or "common")] or GS.RARITY.common
    local rc = rd.color
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
    nvgText(vg, dlgX + dlgW / 2, cy, itemName .. " x" .. total, nil)
    cy = cy + 24

    -- 拆分数量显示：拆出 qty | 剩余 total-qty
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, cy + 4,
        "拆出 " .. qty .. "  |  剩余 " .. (total - qty), nil)
    cy = cy + 22

    -- ±按钮行
    local sliderPadX = pad + 10
    local sliderX = dlgX + sliderPadX
    local sliderW = dlgW - sliderPadX * 2

    local qBtnH = 30
    local qBtnY = cy + 2
    local qBtnCount = 4
    local qBtnGap2 = 8
    local qBtnW = (sliderW - qBtnGap2 * (qBtnCount - 1)) / qBtnCount

    GS.splitPopupQtyBtnRects = {}
    local qLabels = { "-10", "-1", "+1", "+10" }
    local qDeltas = { -10, -1, 1, 10 }
    for bi = 1, qBtnCount do
        local bx = sliderX + (bi - 1) * (qBtnW + qBtnGap2)
        local isPlus = qDeltas[bi] > 0
        local newQty = qty + qDeltas[bi]
        local enabled = newQty >= 1 and newQty <= maxQty

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, qBtnY, qBtnW, qBtnH, 4)
        if enabled then
            if isPlus then
                nvgFillColor(vg, nvgRGBA(50, 120, 50, 220))
            else
                nvgFillColor(vg, nvgRGBA(120, 60, 40, 220))
            end
        else
            nvgFillColor(vg, nvgRGBA(100, 90, 70, 120))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + 0.5, qBtnY + 0.5, qBtnW - 1, qBtnH - 1, 4)
        nvgStrokeColor(vg, enabled and nvgRGBA(180, 160, 100, 180) or nvgRGBA(120, 110, 90, 100))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, enabled and nvgRGBA(230, 220, 190, 255) or nvgRGBA(140, 130, 110, 150))
        nvgText(vg, bx + qBtnW / 2, qBtnY + qBtnH / 2, qLabels[bi], nil)
        GS.splitPopupQtyBtnRects[bi] = { x = bx, y = qBtnY, w = qBtnW, h = qBtnH, delta = qDeltas[bi], enabled = enabled }
        if enabled and isHovered(bx, qBtnY, qBtnW, qBtnH) then
            drawHoverHighlight(vg, bx, qBtnY, qBtnW, qBtnH, 4)
        end
    end
    cy = qBtnY + qBtnH + 10

    -- 滑动条
    local sliderH = 6
    local sliderY = cy + 4

    -- 轨道
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderX, sliderY, sliderW, sliderH, sliderH / 2)
    nvgFillColor(vg, nvgRGBA(140, 115, 75, 120))
    nvgFill(vg)

    -- 已填充部分
    local sliderRatio = maxQty > 1 and ((qty - 1) / (maxQty - 1)) or 0
    local fillW = sliderW * sliderRatio
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderX, sliderY, fillW, sliderH, sliderH / 2)
        nvgFillColor(vg, nvgRGBA(180, 130, 40, 200))
        nvgFill(vg)
    end

    -- 滑块圆点
    local knobR = 8
    local knobX = sliderX + fillW
    local knobY2 = sliderY + sliderH / 2
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, knobY2, knobR)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, knobY2, knobR)
    nvgStrokeColor(vg, nvgRGBA(100, 80, 40, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 存储滑动条区域（扩大点击区域）
    GS.splitPopupSliderRect = { x = sliderX - knobR, y = sliderY - knobR,
        w = sliderW + knobR * 2, h = sliderH + knobR * 2,
        trackX = sliderX, trackW = sliderW, maxQty = maxQty }

    -- 底部按钮
    local btnW = 100
    local btnH = 36
    local btnGap3 = 20
    local totalBtnW = btnW * 2 + btnGap3
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮
    local cancelX = btnStartX
    GS.splitPopupCancelRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 5)
    local cGrad = nvgLinearGradient(vg, cancelX, btnBaseY, cancelX, btnBaseY + btnH,
        nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
    nvgFillPaint(vg, cGrad)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 5)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 150))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)
    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 5)
    end

    -- 确定按钮（橙色）
    local confirmX = btnStartX + btnW + btnGap3
    GS.splitPopupConfirmRect = { x = confirmX, y = btnBaseY, w = btnW, h = btnH }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnBaseY, btnW, btnH, 5)
    local rGrad = nvgLinearGradient(vg, confirmX, btnBaseY, confirmX, btnBaseY + btnH,
        nvgRGBA(180, 120, 30, 230), nvgRGBA(140, 90, 15, 230))
    nvgFillPaint(vg, rGrad)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 5)
    nvgStrokeColor(vg, nvgRGBA(220, 180, 80, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 240, 200, 250))
    nvgText(vg, confirmX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)
    if isHovered(confirmX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, confirmX, btnBaseY, btnW, btnH, 5)
    end
end

-- ====================================================================
-- 购买确认弹窗
-- ====================================================================
function M.drawBuyConfirmDialog()
    if not GS.shopBuyConfirmVisible then return end
    if not GS.shopBuyConfirmItem then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H
    local item = GS.shopBuyConfirmItem
    local unitPrice = item.price or 0
    local stock = item.stock or 999
    local qty = GS.shopBuyQuantity or 1
    local affordQty = math.floor(GS.gold / math.max(1, unitPrice))
    local maxQty = math.min(stock, affordQty)
    if maxQty < 1 then maxQty = 1 end
    -- 确保数量在范围内
    if qty > maxQty then
        qty = maxQty
        GS.shopBuyQuantity = qty
    end
    local totalPrice = unitPrice * qty

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    local dlgW = math.min(W * 0.85, 300)
    local dlgH = math.min(H * 0.65, 300)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 12

    -- 背景（深色）
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

    -- ===== 标题：购买 + 物品名 =====
    local cy = dlgY + pad
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, cy, "购买数量", nil)
    cy = cy + 20

    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(40, 100, 40, 255))
    nvgText(vg, dlgX + dlgW / 2, cy, item.name or "物品", nil)
    cy = cy + 24

    -- ===== 数量显示 =====
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgText(vg, dlgX + dlgW / 2, cy + 6, tostring(qty), nil)
    cy = cy + 22

    -- ===== ±按钮行（与滑动条等宽，均匀分布） =====
    local sliderPadX = pad + 10
    local sliderX = dlgX + sliderPadX
    local sliderW = dlgW - sliderPadX * 2

    local qBtnH = 32
    local qBtnY = cy + 2
    -- 4个按钮均匀分布在 sliderX ~ sliderX+sliderW 范围内
    local qBtnCount = 4
    local qBtnGap = 8
    local qBtnW = (sliderW - qBtnGap * (qBtnCount - 1)) / qBtnCount

    GS.shopBuyQtyBtnRects = {}
    local qLabels = { "-10", "-1", "+1", "+10" }
    local qDeltas = { -10, -1, 1, 10 }
    for bi = 1, qBtnCount do
        local bx = sliderX + (bi - 1) * (qBtnW + qBtnGap)
        local isPlus = qDeltas[bi] > 0
        local newQty = qty + qDeltas[bi]
        local enabled = newQty >= 1 and newQty <= maxQty

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, qBtnY, qBtnW, qBtnH, 4)
        if enabled then
            if isPlus then
                nvgFillColor(vg, nvgRGBA(50, 120, 50, 220))
            else
                nvgFillColor(vg, nvgRGBA(120, 60, 40, 220))
            end
        else
            nvgFillColor(vg, nvgRGBA(100, 90, 70, 120))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + 0.5, qBtnY + 0.5, qBtnW - 1, qBtnH - 1, 4)
        nvgStrokeColor(vg, enabled and nvgRGBA(180, 160, 100, 180) or nvgRGBA(120, 110, 90, 100))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, enabled and nvgRGBA(230, 220, 190, 255) or nvgRGBA(140, 130, 110, 150))
        nvgText(vg, bx + qBtnW / 2, qBtnY + qBtnH / 2, qLabels[bi], nil)
        GS.shopBuyQtyBtnRects[bi] = { x = bx, y = qBtnY, w = qBtnW, h = qBtnH, delta = qDeltas[bi], enabled = enabled }
        if enabled and isHovered(bx, qBtnY, qBtnW, qBtnH) then
            drawHoverHighlight(vg, bx, qBtnY, qBtnW, qBtnH, 4)
        end
    end
    cy = qBtnY + qBtnH + 10

    -- ===== 滑动条（与按钮等宽） =====
    local sliderH = 6
    local sliderY = cy + 4

    -- 轨道
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sliderX, sliderY, sliderW, sliderH, sliderH / 2)
    nvgFillColor(vg, nvgRGBA(140, 115, 75, 120))
    nvgFill(vg)

    -- 已填充部分
    local sliderRatio = maxQty > 1 and ((qty - 1) / (maxQty - 1)) or 0
    local fillW = sliderW * sliderRatio
    if fillW > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sliderX, sliderY, fillW, sliderH, sliderH / 2)
        nvgFillColor(vg, nvgRGBA(60, 130, 60, 200))
        nvgFill(vg)
    end

    -- 滑块圆点
    local knobR = 8
    local knobX = sliderX + fillW
    local knobY = sliderY + sliderH / 2
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, knobY, knobR)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, knobY, knobR)
    nvgStrokeColor(vg, nvgRGBA(100, 80, 40, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 存储滑动条区域（扩大点击区域）
    GS.shopBuyQtySliderRect = { x = sliderX - knobR, y = sliderY - knobR, w = sliderW + knobR * 2, h = sliderH + knobR * 2,
                                 trackX = sliderX, trackW = sliderW, maxQty = maxQty }

    cy = sliderY + sliderH + 14

    -- ===== 总价 =====
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local canAffordTotal = GS.gold >= totalPrice
    if canAffordTotal then
        nvgFillColor(vg, nvgRGBA(180, 140, 40, 255))
    else
        nvgFillColor(vg, nvgRGBA(200, 60, 40, 255))
    end
    nvgText(vg, dlgX + dlgW / 2, cy, "总价: " .. totalPrice .. " 金币", nil)
    cy = cy + 8

    -- ===== 底部按钮 =====
    local btnW = 100
    local btnH = 38
    local btnGap = 20
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮
    local cancelX = btnStartX
    GS.shopBuyConfirmNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 5)
    local cGrad = nvgLinearGradient(vg, cancelX, btnBaseY, cancelX, btnBaseY + btnH,
        nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
    nvgFillPaint(vg, cGrad)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 5)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 150))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)
    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 5)
    end

    -- 确定按钮（绿色）
    local confirmX = btnStartX + btnW + btnGap
    GS.shopBuyConfirmYesRect = { x = confirmX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnBaseY, btnW, btnH, 5)
    if canAffordTotal then
        local rGrad = nvgLinearGradient(vg, confirmX, btnBaseY, confirmX, btnBaseY + btnH,
            nvgRGBA(40, 130, 40, 230), nvgRGBA(25, 95, 25, 230))
        nvgFillPaint(vg, rGrad)
    else
        nvgFillColor(vg, nvgRGBA(100, 90, 70, 150))
    end
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 5)
    if canAffordTotal then
        nvgStrokeColor(vg, nvgRGBA(120, 200, 80, 180))
    else
        nvgStrokeColor(vg, nvgRGBA(100, 90, 70, 100))
    end
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if canAffordTotal then
        nvgFillColor(vg, nvgRGBA(220, 255, 200, 250))
    else
        nvgFillColor(vg, nvgRGBA(140, 130, 110, 150))
    end
    nvgText(vg, confirmX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)
    if canAffordTotal and isHovered(confirmX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, confirmX, btnBaseY, btnW, btnH, 5)
    end
end

-- ====================================================================
-- 购买结果提示飘字
-- ====================================================================
function M.drawShopBuyMsg(dt)
    local msg = GS.shopBuyMsg
    if not msg then return end
    msg.timer = msg.timer - dt
    if msg.timer <= 0 then
        GS.shopBuyMsg = nil
        return
    end
    local vg = M.vg
    local W = GS.SCREEN_W
    local alpha = math.min(1, msg.timer / 0.3) -- 最后 0.3 秒淡出
    local c = msg.color or {255, 255, 255}

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 背景条
    local tw = nvgTextBounds(vg, 0, 0, msg.text, nil)
    local bgW = tw + 24
    local bgH = 28
    local bgX = (W - bgW) / 2
    local bgY = GS.SCREEN_H * 0.35
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
    nvgFill(vg)

    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(255 * alpha)))
    nvgText(vg, W / 2, bgY + bgH / 2, msg.text, nil)
end

-- ====================================================================
-- 技能装备弹窗
-- ====================================================================
function M.drawSkillEquipPopup()
    if not GS.skillEquipPopupVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H
    local slotIdx = GS.skillEquipPopupSlot or 1

    local skills = GS.getEquippableSkills(slotIdx)
    local hasEquipped = GS.activeSkills[slotIdx] ~= nil

    -- 手机竖屏模式放大 1.8 倍
    local pScale = (H > W) and 1.8 or 1.0

    -- 布局参数
    local gridCols = 4
    local iconSize = math.floor(28 * pScale)
    local iconGap = math.floor(6 * pScale)
    local labelH = math.floor(12 * pScale)
    local cellH = iconSize + labelH + 2
    local cellGap = math.floor(4 * pScale)
    local pad = math.floor(12 * pScale)
    local titleH = math.floor(22 * pScale)
    local removeBtnH = math.floor(22 * pScale)

    local gridRows = math.max(1, math.ceil(#skills / gridCols))
    local gridW = gridCols * iconSize + (gridCols - 1) * iconGap
    local gridH = gridRows * cellH + (gridRows - 1) * cellGap

    local dlgW = math.max(gridW + pad * 2, 170)
    local dlgH = titleH + pad + gridH + pad
        + (hasEquipped and (removeBtnH + 8) or 0)
        + (#skills == 0 and 30 or 0)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 6

    GS.skillEquipPopupRect = { x = dlgX, y = dlgY, w = dlgW, h = dlgH }

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

    -- 弹窗边框
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
    local titleText = "选择技能 — 槽位 " .. slotIdx
    nvgText(vg, dlgX + dlgW / 2, dlgY + math.floor(6 * pScale), titleText, nil)

    -- 技能网格
    GS.skillEquipPopupSkillRects = {}
    local startX = dlgX + (dlgW - gridW) / 2
    local startY = dlgY + titleH + pad

    if #skills == 0 then
        -- 无可用技能提示
        nvgFontSize(vg, 11 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 160, 120, 255))
        nvgText(vg, dlgX + dlgW / 2, startY + math.floor(15 * pScale), "暂无已学习的技能", nil)
    else
        for idx, skill in ipairs(skills) do
            local col = ((idx - 1) % gridCols)
            local row = math.floor((idx - 1) / gridCols)
            local sx = startX + col * (iconSize + iconGap)
            local sy = startY + row * (cellH + cellGap)

            -- 存储点击区域
            GS.skillEquipPopupSkillRects[idx] = {
                x = sx, y = sy, w = iconSize, h = cellH,
                skillId = skill.skillId,
                equipped = skill.equipped,
                disabled = skill.disabled,
                chargeMode = skill.chargeMode,
            }

            local dimmed = skill.equipped or skill.disabled
            local alpha = dimmed and 0.4 or 1.0

            -- 图标背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx, sy, iconSize, iconSize, 3)
            local sImg = M.skillImages and M.skillImages[skill.skillId]
            if sImg and sImg ~= -1 then
                local imgPat = nvgImagePattern(vg, sx, sy, iconSize, iconSize, 0, sImg, alpha)
                nvgFillPaint(vg, imgPat)
            else
                local c = skill.col
                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(160 * alpha)))
            end
            nvgFill(vg)

            -- 图标边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sx + 0.5, sy + 0.5, iconSize - 1, iconSize - 1, 3)
            nvgStrokeColor(vg, nvgRGBA(80, 60, 30, dimmed and 80 or 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 技能名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 7 * pScale)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 200, 160, dimmed and 100 or 220))
            nvgText(vg, sx + iconSize / 2, sy + iconSize + 1, skill.name, nil)

            -- 已装备 / 不满足条件 标记
            if skill.disabled then
                -- 半透明黑色遮罩
                nvgBeginPath(vg)
                nvgRoundedRect(vg, sx, sy, iconSize, iconSize, 3)
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
                nvgFill(vg)
                -- 禁用文字
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 5.5 * pScale)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 100, 80, 240))
                local reason = skill.disabledReason or "不可用"
                nvgText(vg, sx + iconSize / 2, sy + iconSize / 2 - 3 * pScale, "不满足", nil)
                nvgText(vg, sx + iconSize / 2, sy + iconSize / 2 + 3 * pScale, "施展条件", nil)
            elseif skill.equipped then
                nvgFontSize(vg, 6 * pScale)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(180, 50, 30, 220))
                nvgText(vg, sx + iconSize / 2, sy + iconSize / 2, "已装备", nil)
            end

            -- Hover 高亮
            if not dimmed and isHovered(sx, sy, iconSize, cellH) then
                drawHoverHighlight(vg, sx, sy, iconSize, iconSize, 3)
            end
        end
    end

    -- "取消放置"按钮（仅当槽位已有技能时显示）
    if hasEquipped then
        local btnW = math.floor(70 * pScale)
        local btnH = removeBtnH
        local btnX = dlgX + (dlgW - btnW) / 2
        local btnY = dlgY + dlgH - pad - btnH

        GS.skillEquipPopupRemoveRect = { x = btnX, y = btnY, w = btnW, h = btnH }

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 3)
        local rGrad = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
            nvgRGBA(160, 50, 35, 220), nvgRGBA(120, 30, 15, 220))
        nvgFillPaint(vg, rGrad)
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, 3)
        nvgStrokeColor(vg, nvgRGBA(200, 100, 70, 180))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 200, 250))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "卸下", nil)

        if isHovered(btnX, btnY, btnW, btnH) then
            drawHoverHighlight(vg, btnX, btnY, btnW, btnH, 3)
        end
    else
        GS.skillEquipPopupRemoveRect = nil
    end
end

-- ====================================================================
-- 行动菜单（移动后弹出：普通攻击/技能/道具/待机）
-- ====================================================================
function M.drawActionMenu()
    if not GS.actionMenuVisible and not GS.actionSkillSubVisible then return end
    if not GS.selectedUnit then return end
    -- 副本过场对话激活时隐藏行动菜单，避免遮挡对话框
    if GS.arenaTransition then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 玩家屏幕坐标
    local pu = GS.selectedUnit
    local playerSX = GS.BOARD_X + (pu.x - 1) * GS.CELL + GS.CELL / 2
    local playerSY = GS.BOARD_Y + (pu.y - 1) * GS.CELL + GS.CELL / 2

    -- 手机竖屏放大
    local pScale = (H > W) and 1.6 or 1.0

    -- 菜单尺寸
    local menuW = math.floor(90 * pScale)
    local btnH = math.floor(26 * pScale)
    local btnGap = math.floor(3 * pScale)
    local pad = math.floor(6 * pScale)

    -- 判断攻击范围内是否有采集物（用于决定是否显示采集按钮）
    local hasGatherNearby = false
    for _, g in ipairs(GS.gatherables) do
        if GS.attackableCells[GS.cellKey(g.x, g.y)] then
            hasGatherNearby = true
            break
        end
    end

    local numBtns = 5
    if hasGatherNearby then numBtns = numBtns + 1 end
    local menuH = pad * 2 + numBtns * btnH + (numBtns - 1) * btnGap

    -- 定位：根据最近攻击目标/AOE目标区域与玩家的相对位置决定菜单方向
    -- 目标在玩家右侧 → 菜单放左侧，避免遮挡攻击结果/AOE爆炸区域；反之亦然
    local placeRight = true  -- 默认放右侧
    local tx = GS.lastActionTargetX
    local ty = GS.lastActionTargetY
    local aoeR = GS.lastActionAoeRadius or 0
    if tx then
        -- 计算目标区域（含AOE半径）的屏幕范围
        local targetSX = GS.BOARD_X + (tx - 1) * GS.CELL + GS.CELL / 2
        local aoePixelR = aoeR * GS.CELL
        local aoeLeft = targetSX - aoePixelR
        local aoeRight = targetSX + aoePixelR

        if aoeR > 0 then
            -- AOE技能：菜单放在AOE区域不覆盖的一侧
            local spaceLeft = aoeLeft - (playerSX - GS.CELL * 0.7 - menuW)
            local spaceRight = (playerSX + GS.CELL * 0.7 + menuW) - aoeRight
            -- 菜单放在与AOE区域重叠更少的一侧
            if playerSX <= targetSX then
                -- 玩家在目标左侧或同列，菜单放左侧
                placeRight = false
            else
                -- 玩家在目标右侧，菜单放右侧
                placeRight = true
            end
        else
            -- 单体攻击：保持原有逻辑
            if tx > pu.x then
                placeRight = false
            elseif tx == pu.x then
                placeRight = playerSX >= W / 2
            end
        end
    end

    local menuX
    if placeRight then
        menuX = playerSX + GS.CELL * 0.7
        if menuX + menuW > W - 4 then
            if aoeR > 0 then
                menuX = W - 4 - menuW  -- AOE模式：贴右边缘，不翻转到左边挡住AOE
            else
                menuX = playerSX - GS.CELL * 0.7 - menuW
            end
        end
    else
        menuX = playerSX - GS.CELL * 0.7 - menuW
        if menuX < 4 then
            if aoeR > 0 then
                menuX = 4  -- AOE模式：贴左边缘，不翻转到右边挡住AOE
            else
                menuX = playerSX + GS.CELL * 0.7
            end
        end
    end
    local menuY = playerSY - menuH / 2
    if menuY < GS.TOP_BAR_H + 4 then menuY = GS.TOP_BAR_H + 4 end
    if menuY + menuH > H - 4 then menuY = H - 4 - menuH end

    GS.actionMenuRect = { x = menuX, y = menuY, w = menuW, h = menuH }

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)

    -- 面板阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, menuX + 2, menuY + 2, menuW, menuH, 5)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, menuX, menuY, menuW, menuH, 5)
    local bgGrad = nvgLinearGradient(vg, menuX, menuY, menuX, menuY + menuH,
        nvgRGBA(50, 42, 30, 240), nvgRGBA(35, 28, 18, 240))
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 面板边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, menuX + 0.5, menuY + 0.5, menuW - 1, menuH - 1, 5)
    nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 判断技能/道具是否可用
    local hasSkills = #GS.getLearnedActiveSkills() > 0
    local hasItems = false  -- 道具系统暂未实装

    -- 按钮定义
    local buttons = {
        { key = "attack", label = "攻击", color = {160, 55, 40} },
        { key = "skill",  label = "技能",     color = {45, 100, 170}, disabled = not hasSkills },
        { key = "gather", label = "采集",     color = {60, 130, 50},  hidden = not hasGatherNearby },
        { key = "item",   label = "道具",     color = {80, 80, 80},   disabled = not hasItems },
        { key = "wait",   label = "结束回合",  color = {130, 60, 40} },
        { key = "undo",   label = "撤销移动", color = {60, 90, 60}, disabled = GS.mageActionTaken },
    }

    GS.actionMenuRects = {}
    local curY = menuY + pad
    local mx, my = GS.hoverX or 0, GS.hoverY or 0

    for _, btn in ipairs(buttons) do
        if btn.hidden then goto continueBtn end
        local btnX = menuX + pad
        local btnW = menuW - pad * 2
        local r = { x = btnX, y = curY, w = btnW, h = btnH }
        GS.actionMenuRects[btn.key] = r

        local c = btn.color
        local locked = btn.disabled
        local hovered = (not locked) and (mx >= btnX and mx <= btnX + btnW and my >= curY and my <= curY + btnH)
        local brightAdd = hovered and 30 or 0
        local alpha = locked and 100 or 220

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, curY, btnW, btnH, 3)
        local bGrad = nvgLinearGradient(vg, btnX, curY, btnX, curY + btnH,
            nvgRGBA(c[1]+brightAdd, c[2]+brightAdd, c[3]+brightAdd, alpha),
            nvgRGBA(math.max(0,c[1]-15+brightAdd), math.max(0,c[2]-15+brightAdd), math.max(0,c[3]-15+brightAdd), alpha))
        nvgFillPaint(vg, bGrad)
        nvgFill(vg)

        -- 按钮边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + 0.5, curY + 0.5, btnW - 1, btnH - 1, 3)
        nvgStrokeColor(vg, nvgRGBA(math.min(255,c[1]+50), math.min(255,c[2]+50), math.min(255,c[3]+50), locked and 50 or 120))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local textAlpha = locked and 80 or 250
        nvgFillColor(vg, nvgRGBA(255, 240, 220, textAlpha))
        nvgText(vg, btnX + btnW / 2, curY + btnH / 2, btn.label, nil)

        curY = curY + btnH + btnGap
        ::continueBtn::
    end

    -- 技能子菜单
    if GS.actionSkillSubVisible then
        M.drawActionSkillSub(menuX, menuY, menuW, pScale)
    end
end

-- ====================================================================
-- 行动菜单 - 技能子菜单
-- ====================================================================
function M.drawActionSkillSub(parentX, parentY, parentW, pScale)
    local vg = M.vg
    local skills = GS.getLearnedActiveSkills()

    if #skills == 0 then
        GS.actionSkillSubVisible = false
        return
    end

    local entryH = math.floor(28 * pScale)
    local entryGap = math.floor(2 * pScale)
    local pad = math.floor(8 * pScale)
    local subW = math.floor(((GS.currentClass == "mage" or GS.currentClass == "priest") and 150 or 130) * pScale)
    local subH = pad * 2 + #skills * entryH + (#skills - 1) * entryGap

    -- 定位：根据主菜单相对于玩家的位置决定子菜单展开方向
    local pu = GS.selectedUnit
    local playerSX = pu and (GS.BOARD_X + (pu.x - 1) * GS.CELL + GS.CELL / 2) or (GS.SCREEN_W / 2)
    local menuOnLeft = (parentX + parentW / 2) < playerSX
    local subX
    if menuOnLeft then
        -- 主菜单在玩家左侧，子菜单向左展开
        subX = parentX - subW - 4
        if subX < 4 then subX = parentX + parentW + 4 end
    else
        -- 主菜单在玩家右侧，子菜单向右展开
        subX = parentX + parentW + 4
        if subX + subW > GS.SCREEN_W - 4 then subX = parentX - subW - 4 end
    end
    if subX < 4 then subX = 4 end
    if subX + subW > GS.SCREEN_W - 4 then subX = GS.SCREEN_W - 4 - subW end
    local subY = parentY
    if subY + subH > GS.SCREEN_H - 4 then
        subY = GS.SCREEN_H - 4 - subH
    end
    if subY < 4 then
        subY = 4
    end

    GS.actionSkillSubRect = { x = subX, y = subY, w = subW, h = subH }

    -- 面板阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subX + 2, subY + 2, subW, subH, 5)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subX, subY, subW, subH, 5)
    local bgGrad = nvgLinearGradient(vg, subX, subY, subX, subY + subH,
        nvgRGBA(45, 38, 28, 245), nvgRGBA(32, 26, 16, 245))
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 面板边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subX + 0.5, subY + 0.5, subW - 1, subH - 1, 5)
    nvgStrokeColor(vg, nvgRGBA(140, 110, 60, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 技能条目
    GS.actionSkillSubRects = {}
    local curY = subY + pad
    local mx, my = GS.hoverX or 0, GS.hoverY or 0

    for i, skill in ipairs(skills) do
        local eX = subX + pad
        local eW = subW - pad * 2
        local r = { x = eX, y = curY, w = eW, h = entryH, skillId = skill.skillId, ready = skill.ready }
        GS.actionSkillSubRects[i] = r

        local alpha = skill.ready and 255 or 80
        local hovered = skill.ready and (mx >= eX and mx <= eX + eW and my >= curY and my <= curY + entryH)

        -- 条目背景（悬停时）
        if hovered then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, eX, curY, eW, entryH, 3)
            nvgFillColor(vg, nvgRGBA(255, 220, 140, 40))
            nvgFill(vg)
        end

        -- 技能名色块
        local sc = skill.col
        nvgBeginPath(vg)
        nvgRoundedRect(vg, eX + 2, curY + entryH / 2 - 5, 10, 10, 2)
        nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], alpha))
        nvgFill(vg)

        -- 技能名
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 230, 210, alpha))
        local nameStr = skill.name
        if skill.isAoe then nameStr = nameStr .. "(AOE)" end
        nvgText(vg, eX + 16, curY + entryH / 2, nameStr, nil)

        -- 吟唱段数标记（法师技能）
        if (skill.castStages or 0) > 0 then
            local csText = skill.castStages .. "段"
            local nameW = nvgTextBounds(vg, 0, 0, nameStr, nil)
            local tagX = eX + 16 + nameW + 4
            nvgFontSize(vg, 9 * pScale)
            if skill.chantReady then
                nvgFillColor(vg, nvgRGBA(160, 140, 220, alpha))
            else
                nvgFillColor(vg, nvgRGBA(220, 100, 60, alpha))
            end
            nvgText(vg, tagX, curY + entryH / 2, csText, nil)
        end

        -- MP/CD 信息
        nvgFontSize(vg, 10 * pScale)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if skill.cdLeft > 0 then
            nvgFillColor(vg, nvgRGBA(200, 60, 40, 200))
            nvgText(vg, eX + eW - 2, curY + entryH / 2, "CD:" .. skill.cdLeft, nil)
        else
            nvgFillColor(vg, nvgRGBA(80, 140, 220, alpha))
            nvgText(vg, eX + eW - 2, curY + entryH / 2, "MP:" .. skill.mpCost, nil)
        end

        curY = curY + entryH + entryGap
    end
end

-- ====================================================================
-- Debuff Tooltip（最顶层绘制，在 nvgEndFrame 之前调用）
-- ====================================================================
function M.drawDebuffTooltip()
    if not GS.debuffTooltip then return end
    local vg = M.vg
    local tt = GS.debuffTooltip
    local tipFontSize = 11
    local padTX, padTY = 8, 5
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, tipFontSize)
    local tipLines = {}
    tipLines[#tipLines + 1] = tt.name
    for line in tt.desc:gmatch("[^\n]+") do
        tipLines[#tipLines + 1] = line
    end
    local maxTW = 0
    for _, ln in ipairs(tipLines) do
        local tw = nvgTextBounds(vg, 0, 0, ln, nil, nil)
        if tw > maxTW then maxTW = tw end
    end
    local tipLineH = tipFontSize + 3
    local tipW = maxTW + padTX * 2
    local tipH = #tipLines * tipLineH + padTY * 2
    local tipX = tt.x - tipW / 2
    local tipY = tt.y - tipH - 4
    -- 屏幕边界修正
    if tipX < 2 then tipX = 2 end
    if tipX + tipW > GS.SCREEN_W - 2 then tipX = GS.SCREEN_W - 2 - tipW end
    if tipY < 2 then tipY = tt.y + 18 end -- 上方放不下则显示在下方
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tipX, tipY, tipW, tipH, 4)
    nvgFillColor(vg, nvgRGBA(20, 20, 30, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(tt.r, tt.g, tt.b, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    for li, ln in ipairs(tipLines) do
        if li == 1 then
            nvgFillColor(vg, nvgRGBA(tt.r, tt.g, tt.b, 255))
            nvgFontSize(vg, tipFontSize + 1)
        else
            nvgFillColor(vg, nvgRGBA(220, 220, 220, 220))
            nvgFontSize(vg, tipFontSize)
        end
        nvgText(vg, tipX + padTX, tipY + padTY + (li - 1) * tipLineH, ln, nil)
    end
end


-- ====================================================================
-- 房屋购买弹窗
-- ====================================================================
function M.drawHouseBuyDialog()
    if not GS.houseBuyDialogVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩覆盖全屏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local canAfford = GS.gold >= 5000
    local hourNow = math.floor(((GS.weatherTime - 1) % 1440) / 60)
    local isNightNow = (hourNow >= 18 or hourNow < 7)
    local showSleepOption = (not canAfford) and isNightNow
    local dlgW = math.min(W * 0.75, 280)
    local dlgH = canAfford and math.min(H * 0.38, 140)
        or (showSleepOption and math.min(H * 0.52, 200) or math.min(H * 0.42, 155))
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 弹窗边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 提示文字
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    -- 第一行
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "清水镇有一间狭小房间正在出售……", nil)

    -- 第二行
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(180, 140, 30, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 22, "售价5000 G。", nil)

    if canAfford then
        -- 金币足够：显示取消和购买两个按钮
        local btnW = 60
        local btnH = 24
        local btnGap = 16
        local totalBtnW = btnW * 2 + btnGap
        local btnStartX = dlgX + (dlgW - totalBtnW) / 2
        local btnBaseY = dlgY + dlgH - pad - btnH

        -- 取消按钮（红色）
        local cancelX = btnStartX
        GS.houseBuyNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 3)
        local cGrad = nvgLinearGradient(vg, cancelX, btnBaseY, cancelX, btnBaseY + btnH,
            nvgRGBA(180, 50, 35, 230), nvgRGBA(140, 30, 15, 230))
        nvgFillPaint(vg, cGrad)
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
        nvgStrokeColor(vg, nvgRGBA(220, 120, 80, 180))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 200, 250))
        nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)

        if isHovered(cancelX, btnBaseY, btnW, btnH) then
            drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 3)
        end

        -- 购买按钮（绿色）
        local buyX = btnStartX + btnW + btnGap
        GS.houseBuyYesRect = { x = buyX, y = btnBaseY, w = btnW, h = btnH }

        nvgBeginPath(vg)
        nvgRoundedRect(vg, buyX, btnBaseY, btnW, btnH, 3)
        local gGrad = nvgLinearGradient(vg, buyX, btnBaseY, buyX, btnBaseY + btnH,
            nvgRGBA(40, 140, 45, 230), nvgRGBA(25, 100, 30, 230))
        nvgFillPaint(vg, gGrad)
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, buyX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 180))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        nvgFillColor(vg, nvgRGBA(220, 255, 220, 250))
        nvgText(vg, buyX + btnW / 2, btnBaseY + btnH / 2, "购买", nil)

        if isHovered(buyX, btnBaseY, btnW, btnH) then
            drawHoverHighlight(vg, buyX, btnBaseY, btnW, btnH, 3)
        end
    else
        -- 金币不足：显示提示文字
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 50, 35, 240))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 46, "你持有的金币不足，继续努力吧！", nil)

        if showSleepOption then
            -- 夜晚：显示街头睡觉选项
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(160, 150, 220, 240))
            nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 68, "要在街头睡到清晨吗？", nil)

            -- 两个按钮：关闭（左） + 确定（右）
            local btnW = 60
            local btnH = 24
            local btnGap = 16
            local totalBtnW = btnW * 2 + btnGap
            local btnStartX = dlgX + (dlgW - totalBtnW) / 2
            local btnBaseY = dlgY + dlgH - pad - btnH

            -- 关闭按钮（左，暗色）
            local closeX = btnStartX
            GS.houseBuyNoRect = { x = closeX, y = btnBaseY, w = btnW, h = btnH }

            nvgBeginPath(vg)
            nvgRoundedRect(vg, closeX, btnBaseY, btnW, btnH, 3)
            local cGrad = nvgLinearGradient(vg, closeX, btnBaseY, closeX, btnBaseY + btnH,
                nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
            nvgFillPaint(vg, cGrad)
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, closeX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
            nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 150))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))
            nvgText(vg, closeX + btnW / 2, btnBaseY + btnH / 2, "关闭", nil)
            if isHovered(closeX, btnBaseY, btnW, btnH) then
                drawHoverHighlight(vg, closeX, btnBaseY, btnW, btnH, 3)
            end

            -- 确定按钮（右，蓝紫色 - 睡觉）
            local sleepX = btnStartX + btnW + btnGap
            GS.streetSleepBtnRect = { x = sleepX, y = btnBaseY, w = btnW, h = btnH }

            nvgBeginPath(vg)
            nvgRoundedRect(vg, sleepX, btnBaseY, btnW, btnH, 3)
            local sGrad = nvgLinearGradient(vg, sleepX, btnBaseY, sleepX, btnBaseY + btnH,
                nvgRGBA(50, 50, 130, 230), nvgRGBA(30, 30, 90, 230))
            nvgFillPaint(vg, sGrad)
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sleepX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
            nvgStrokeColor(vg, nvgRGBA(120, 120, 200, 180))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            nvgFillColor(vg, nvgRGBA(210, 210, 255, 250))
            nvgText(vg, sleepX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)
            if isHovered(sleepX, btnBaseY, btnW, btnH) then
                drawHoverHighlight(vg, sleepX, btnBaseY, btnW, btnH, 3)
            end
        else
            -- 非夜晚或已购买：只显示关闭按钮
            local btnW = 60
            local btnH = 24
            local btnBaseY = dlgY + dlgH - pad - btnH
            local btnX = dlgX + (dlgW - btnW) / 2
            GS.houseBuyNoRect = { x = btnX, y = btnBaseY, w = btnW, h = btnH }
            GS.streetSleepBtnRect = nil

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnBaseY, btnW, btnH, 3)
            local cGrad = nvgLinearGradient(vg, btnX, btnBaseY, btnX, btnBaseY + btnH,
                nvgRGBA(90, 65, 35, 220), nvgRGBA(65, 45, 22, 220))
            nvgFillPaint(vg, cGrad)
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
            nvgStrokeColor(vg, nvgRGBA(160, 130, 70, 150))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(230, 210, 170, 240))
            nvgText(vg, btnX + btnW / 2, btnBaseY + btnH / 2, "关闭", nil)
            if isHovered(btnX, btnBaseY, btnW, btnH) then
                drawHoverHighlight(vg, btnX, btnBaseY, btnW, btnH, 3)
            end
        end
        GS.houseBuyYesRect = nil
    end
end

-- ====================================================================
-- 房屋购买成功提示弹窗
-- ====================================================================
function M.drawHouseBuySuccessDialog()
    if not GS.houseBuySuccessVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local dlgW = math.min(W * 0.8, 300)
    local dlgH = math.min(H * 0.45, 170)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 背景（深色）
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

    -- 文字
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    -- 第一行：恭喜你！
    nvgFontSize(vg, 17)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "恭喜你！", nil)

    -- 第二行
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 24, "在一个陌生的世界拥有了", nil)

    -- 第三行
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 42, "自己的一席之地！", nil)

    -- 第四行
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 64, "现在你可以从地图上的清水镇", nil)

    -- 第五行
    ---@diagnostic disable-next-line: unicode-name, undefined-global
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad + 82, "直接返回\u{201c}家\u{201d}中了。", nil)

    -- 确定按钮（居中）
    local btnW = 60
    local btnH = 24
    local btnBaseY = dlgY + dlgH - pad - btnH
    local btnX = dlgX + (dlgW - btnW) / 2
    GS.houseBuySuccessOkRect = { x = btnX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnBaseY, btnW, btnH, 3)
    local gGrad = nvgLinearGradient(vg, btnX, btnBaseY, btnX, btnBaseY + btnH,
        nvgRGBA(40, 140, 45, 230), nvgRGBA(25, 100, 30, 230))
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 255, 220, 250))
    nvgText(vg, btnX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)

    if isHovered(btnX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, btnX, btnBaseY, btnW, btnH, 3)
    end
end

-- ====================================================================
-- 家园升级确认弹窗
-- ====================================================================
function M.drawHomeUpgradeDialog()
    if not GS.homeUpgradeDialogVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 计算升级信息
    local nextType, cost, nextName, sellBack, fullPrice, title, body
    if GS.homeType == "small" then
        nextType = "medium"
        fullPrice = 57000
        sellBack = 5000
        cost = fullPrice - sellBack  -- 52000
        nextName = "独立小型房屋"
        title = "购买并搬迁至独立小型房屋"
        body = "在狭小房间待久了，还是让人颇感压抑。目前在清水镇有面积稍大的独立小型房屋出售，售价"
            .. fullPrice .. "G。而出售你现在的住处可以获得" .. sellBack
            .. "G。是否支付差价" .. cost .. "G购买并搬迁至独立小屋？"
    else
        nextType = "large"
        fullPrice = 590000
        sellBack = 57000
        cost = fullPrice - sellBack  -- 533000
        nextName = "大型房屋"
        title = "购买并搬迁至大型房屋"
        body = "其实住在这里已经很好了，但是人总有追求。目前清水镇还有更大面积的大型房屋出售，售价为"
            .. fullPrice .. "G。而出售你现在的住所可以获得" .. sellBack
            .. "G。是否支付差价" .. cost .. "G购买并搬迁至大型房屋？"
    end
    local canAfford = GS.gold >= cost

    -- 布局参数
    local pad = 14
    local cornerR = 8
    local titleFs = 15
    local bodyFs = 13
    local btnW = 60
    local btnH = 24
    local btnGap = 16
    local dlgW = math.min(W * 0.85, 320)
    local textW = dlgW - pad * 2

    -- 估算正文行数（中文≈fontSize宽，数字≈fontSize*0.55宽）
    local byteLen = #body
    local approxChars = byteLen / 2.5  -- 中英混合粗略估计
    local charsPerLine = math.floor(textW / (bodyFs * 0.85))
    if charsPerLine < 1 then charsPerLine = 1 end
    local lines = math.ceil(approxChars / charsPerLine)
    local lineH = bodyFs * 1.4
    local bodyH = lines * lineH

    -- 计算弹窗高度（自适应内容）
    local titleH = titleFs + 10
    local notAffordH = canAfford and 0 or (bodyFs + 8)
    local dlgH = pad + titleH + bodyH + 22 + notAffordH + btnH + pad
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 背景（深色）
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
    local cy = dlgY + pad
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, titleFs)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, cy, title, nil)
    cy = cy + titleH

    -- 正文（单段文本，nvgTextBox 自动换行）
    nvgFontSize(vg, bodyFs)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    nvgTextBox(vg, dlgX + pad, cy, textW, body, nil)
    cy = cy + bodyH + 4

    -- 金币不足提示
    if not canAfford then
        cy = cy + 4
        nvgFontSize(vg, bodyFs)
        nvgFillColor(vg, nvgRGBA(200, 60, 40, 220))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(vg, dlgX + dlgW / 2, cy, "（金币不足）", nil)
    end

    -- 按钮
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮（红色）
    local cancelX = btnStartX
    GS.homeUpgradeNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 3)
    local cGrad = nvgLinearGradient(vg, cancelX, btnBaseY, cancelX, btnBaseY + btnH,
        nvgRGBA(180, 50, 35, 230), nvgRGBA(140, 30, 15, 230))
    nvgFillPaint(vg, cGrad)
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 200, 250))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)

    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 3)
    end

    -- 升级按钮（绿色，金币不足时灰色）
    local buyX = btnStartX + btnW + btnGap
    GS.homeUpgradeYesRect = { x = buyX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, buyX, btnBaseY, btnW, btnH, 3)
    local gGrad
    if canAfford then
        gGrad = nvgLinearGradient(vg, buyX, btnBaseY, buyX, btnBaseY + btnH,
            nvgRGBA(40, 140, 45, 230), nvgRGBA(25, 100, 30, 230))
    else
        gGrad = nvgLinearGradient(vg, buyX, btnBaseY, buyX, btnBaseY + btnH,
            nvgRGBA(100, 100, 100, 230), nvgRGBA(70, 70, 70, 230))
    end
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)

    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, canAfford and nvgRGBA(220, 255, 220, 250) or nvgRGBA(180, 180, 180, 200))
    nvgText(vg, buyX + btnW / 2, btnBaseY + btnH / 2, "升级", nil)

    if canAfford and isHovered(buyX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, buyX, btnBaseY, btnW, btnH, 3)
    end
end

-- ====================================================================
-- 求婚成功弹窗（"她说她愿意"）
-- ====================================================================
function M.drawProposalSuccessPopup()
    if not GS.proposalSuccessPopup then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩覆盖全屏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    -- 弹窗文本
    local title = "她说她愿意"
    local bodyText = "冷冰冰的房子即使再大，作为一个\u{201c}家\u{201d}而言，还是有所缺失。你的爱人鼓足勇气，答应了你的求婚，今后将住进你的家中，与你共度余生。而你呢？是否做好准备呢？"

    -- 计算文本自适应高度
    local dlgW = math.min(W * 0.78, 380)
    local pad = 16
    local textAreaW = dlgW - pad * 2
    local titleSize = 17
    local bodySize = 13

    -- 预计算正文高度（使用 nvgTextBoxBounds 正确处理 UTF-8 自动换行）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, bodySize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local bounds = nvgTextBoxBounds(vg, 0, 0, textAreaW, bodyText)
    local bodyH = 14
    if bounds and #bounds >= 4 then
        bodyH = bounds[4] - bounds[2]
    end

    -- 弹窗总高度 = 标题区 + 正文区 + 按钮区 + 间距
    local titleAreaH = titleSize + pad
    local btnH = 26
    local dlgH = pad + titleAreaH + bodyH + pad * 0.8 + btnH + pad
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 245))
    nvgFill(vg)

    -- 弹窗边框（金色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(210, 180, 100, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题（金色居中）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, titleSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 140, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, title, nil)

    -- 正文（nvgTextBox 自动换行，浅金色）
    nvgFontSize(vg, bodySize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 200, 160, 255))
    local textY = dlgY + pad + titleAreaH
    nvgTextBox(vg, dlgX + pad, textY, textAreaW, bodyText, nil)

    -- 确定按钮（绿色，居中）
    local btnW = 80
    local btnX = dlgX + (dlgW - btnW) / 2
    local btnY = dlgY + dlgH - pad - btnH
    local btnR = 4

    GS.proposalSuccessOkRect = { x = btnX, y = btnY, w = btnW, h = btnH }

    local gGrad = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
        nvgRGBA(50, 140, 50, 230), nvgRGBA(35, 100, 35, 230))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, btnR)
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX + 0.5, btnY + 0.5, btnW - 1, btnH - 1, btnR)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 255, 220, 255))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "确定", nil)

    -- hover 高亮
    if isHovered(btnX, btnY, btnW, btnH) then
        drawHoverHighlight(vg, btnX, btnY, btnW, btnH, btnR)
    end
end

-- ====================================================================
-- 深渊区进入确认弹窗
-- ====================================================================
function M.drawAbyssConfirmDialog()
    if not GS.abyssConfirmVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩覆盖全屏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local dlgW = math.min(W * 0.75, 280)
    local dlgH = math.min(H * 0.38, 145)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 弹窗边框（红色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(200, 60, 50, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题（红色）
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(220, 60, 50, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "是否确认开启深渊副本", nil)

    -- 消耗说明（金色，根据 type 区分文本）
    nvgFontSize(vg, 14)
    local line2Y = dlgY + pad + 22
    nvgFillColor(vg, nvgRGBA(240, 200, 100, 255))
    if GS.abyssConfirmType == "key" then
        nvgText(vg, dlgX + dlgW / 2, line2Y, "将消耗 1 把「神之匙」开启", nil)
    else
        nvgText(vg, dlgX + dlgW / 2, line2Y, "将消耗今日免费挑战次数开启", nil)
    end

    -- 警告文本（红色）
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(220, 60, 50, 220))
    nvgText(vg, dlgX + dlgW / 2, line2Y + 20, "开启后中途退出无法再次进入", nil)

    -- 按钮区域
    local btnW = 60
    local btnH = 24
    local btnGap = 16
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮（左，灰色，与地图取消按钮一致）
    local cancelX = btnStartX
    GS.abyssConfirmNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 3)
    nvgFillColor(vg, nvgRGBA(60, 55, 50, 200))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(150, 140, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 170, 255))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)

    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 3)
    end

    -- 确定按钮（右，绿色）
    local confirmX = btnStartX + btnW + btnGap
    GS.abyssConfirmYesRect = { x = confirmX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnBaseY, btnW, btnH, 3)
    local gGrad = nvgLinearGradient(vg, confirmX, btnBaseY, confirmX, btnBaseY + btnH,
        nvgRGBA(50, 140, 50, 230), nvgRGBA(35, 100, 35, 230))
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFillColor(vg, nvgRGBA(220, 255, 220, 255))
    nvgText(vg, confirmX + btnW / 2, btnBaseY + btnH / 2, "确定", nil)

    if isHovered(confirmX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, confirmX, btnBaseY, btnW, btnH, 3)
    end
end

-- ====================================================================
-- 异世深渊进入确认弹窗（区别于深渊区副本的 drawAbyssConfirmDialog）
-- ====================================================================
function M.drawAbyssWorldConfirmDialog()
    if not GS.abyssWorldConfirmVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local dlgW = math.min(W * 0.75, 280)
    local dlgH = math.min(H * 0.38, 145)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 弹窗边框（红色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(200, 60, 50, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题（红色）
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(220, 60, 50, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "是否进入异世深渊", nil)

    -- 消耗说明（金色，根据 type 区分文本）
    nvgFontSize(vg, 14)
    local line2Y = dlgY + pad + 22
    nvgFillColor(vg, nvgRGBA(240, 200, 100, 255))
    if GS.abyssWorldConfirmType == "ad" then
        nvgText(vg, dlgX + dlgW / 2, line2Y, "今日免费次数已用完", nil)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(220, 180, 80, 220))
        nvgText(vg, dlgX + dlgW / 2, line2Y + 18, "看广告吸收异世界能量强行开启通道！", nil)
    else
        nvgText(vg, dlgX + dlgW / 2, line2Y, "将消耗今日免费挑战次数开启", nil)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(220, 60, 50, 220))
        nvgText(vg, dlgX + dlgW / 2, line2Y + 18, "深渊中死亡3次后通道将关闭", nil)
    end

    -- 按钮区域
    local btnW = 60
    local btnH = 24
    local btnGap = 16
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮（左，灰色）
    local cancelX = btnStartX
    GS.abyssWorldConfirmNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 3)
    nvgFillColor(vg, nvgRGBA(60, 55, 50, 200))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(150, 140, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 170, 255))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)

    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 3)
    end

    -- 确定按钮（右，绿色）
    local confirmX = btnStartX + btnW + btnGap
    GS.abyssWorldConfirmYesRect = { x = confirmX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnBaseY, btnW, btnH, 3)
    local gGrad = nvgLinearGradient(vg, confirmX, btnBaseY, confirmX, btnBaseY + btnH,
        nvgRGBA(50, 140, 50, 230), nvgRGBA(35, 100, 35, 230))
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 100, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local btnLabel = GS.abyssWorldConfirmType == "ad" and "看广告" or "确定"
    nvgFillColor(vg, nvgRGBA(220, 255, 220, 255))
    nvgText(vg, confirmX + btnW / 2, btnBaseY + btnH / 2, btnLabel, nil)

    if isHovered(confirmX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, confirmX, btnBaseY, btnW, btnH, 3)
    end
end

-- ====================================================================
-- 史莱姆国王大反击进入确认弹窗
-- ====================================================================
function M.drawSlimeRevengeConfirmDialog()
    if not GS.slimeRevengeConfirmVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local dlgW = math.min(W * 0.75, 280)
    local dlgH = math.min(H * 0.38, 145)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 弹窗边框（绿色，区别于异世深渊的红色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(80, 180, 60, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题（绿色）
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(80, 200, 60, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "是否进入史莱姆国王大反击", nil)

    -- 消耗说明
    nvgFontSize(vg, 14)
    local line2Y = dlgY + pad + 22
    nvgFillColor(vg, nvgRGBA(240, 200, 100, 255))
    if GS.slimeRevengeConfirmType == "ad" then
        nvgText(vg, dlgX + dlgW / 2, line2Y, "今日免费次数已用完", nil)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(220, 180, 80, 220))
        nvgText(vg, dlgX + dlgW / 2, line2Y + 18, "看广告获取额外挑战机会！", nil)
    else
        local remain = GS.getSlimeRevengeRemain()
        nvgText(vg, dlgX + dlgW / 2, line2Y, "将消耗今日免费挑战次数（剩余" .. remain .. "次）", nil)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(220, 60, 50, 220))
        nvgText(vg, dlgX + dlgW / 2, line2Y + 18, "死亡后无法复活，只能返回清水镇", nil)
    end

    -- 按钮区域
    local btnW = 60
    local btnH = 24
    local btnGap = 16
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮（左，灰色）
    local cancelX = btnStartX
    GS.slimeRevengeConfirmNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 3)
    nvgFillColor(vg, nvgRGBA(60, 55, 50, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(150, 140, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 170, 255))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)

    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 3)
    end

    -- 确定按钮（右，绿色）
    local confirmX = btnStartX + btnW + btnGap
    GS.slimeRevengeConfirmYesRect = { x = confirmX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnBaseY, btnW, btnH, 3)
    local gGrad = nvgLinearGradient(vg, confirmX, btnBaseY, confirmX, btnBaseY + btnH,
        nvgRGBA(50, 160, 50, 230), nvgRGBA(35, 110, 35, 230))
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(100, 220, 100, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local btnLabel = GS.slimeRevengeConfirmType == "ad" and "看广告" or "确定"
    nvgFillColor(vg, nvgRGBA(220, 255, 220, 255))
    nvgText(vg, confirmX + btnW / 2, btnBaseY + btnH / 2, btnLabel, nil)

    if isHovered(confirmX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, confirmX, btnBaseY, btnW, btnH, 3)
    end
end

-- ====================================================================
-- 迪哈塔大反击进入确认弹窗
-- ====================================================================
function M.drawDihataRevengeConfirmDialog()
    if not GS.dihataRevengeConfirmVisible then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 弹窗尺寸
    local dlgW = math.min(W * 0.75, 280)
    local dlgH = math.min(H * 0.38, 145)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local cornerR = 8
    local pad = 14

    -- 弹窗背景（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, cornerR)
    nvgFillColor(vg, nvgRGBA(35, 25, 15, 240))
    nvgFill(vg)

    -- 弹窗边框（橙色，区别于史莱姆的绿色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX + 0.5, dlgY + 0.5, dlgW - 1, dlgH - 1, cornerR)
    nvgStrokeColor(vg, nvgRGBA(200, 140, 40, 240))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题（橙色）
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(220, 160, 40, 255))
    nvgText(vg, dlgX + dlgW / 2, dlgY + pad, "是否进入迪哈塔大反击", nil)

    -- 消耗说明
    nvgFontSize(vg, 14)
    local line2Y = dlgY + pad + 22
    nvgFillColor(vg, nvgRGBA(240, 200, 100, 255))
    if GS.dihataRevengeConfirmType == "ad" then
        nvgText(vg, dlgX + dlgW / 2, line2Y, "今日免费次数已用完", nil)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(220, 180, 80, 220))
        nvgText(vg, dlgX + dlgW / 2, line2Y + 18, "看广告获取额外挑战机会！", nil)
    else
        local remain = GS.getDihataRevengeRemain()
        nvgText(vg, dlgX + dlgW / 2, line2Y, "将消耗今日免费挑战次数（剩余" .. remain .. "次）", nil)
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(220, 60, 50, 220))
        nvgText(vg, dlgX + dlgW / 2, line2Y + 18, "死亡后无法复活，只能返回清水镇", nil)
    end

    -- 按钮区域
    local btnW = 60
    local btnH = 24
    local btnGap = 16
    local totalBtnW = btnW * 2 + btnGap
    local btnStartX = dlgX + (dlgW - totalBtnW) / 2
    local btnBaseY = dlgY + dlgH - pad - btnH

    -- 取消按钮（左，灰色）
    local cancelX = btnStartX
    GS.dihataRevengeConfirmNoRect = { x = cancelX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnBaseY, btnW, btnH, 3)
    nvgFillColor(vg, nvgRGBA(60, 55, 50, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(150, 140, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 170, 255))
    nvgText(vg, cancelX + btnW / 2, btnBaseY + btnH / 2, "取消", nil)

    if isHovered(cancelX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, cancelX, btnBaseY, btnW, btnH, 3)
    end

    -- 确定按钮（右，橙色）
    local confirmX = btnStartX + btnW + btnGap
    GS.dihataRevengeConfirmYesRect = { x = confirmX, y = btnBaseY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnBaseY, btnW, btnH, 3)
    local gGrad = nvgLinearGradient(vg, confirmX, btnBaseY, confirmX, btnBaseY + btnH,
        nvgRGBA(200, 140, 40, 230), nvgRGBA(150, 100, 20, 230))
    nvgFillPaint(vg, gGrad)
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX + 0.5, btnBaseY + 0.5, btnW - 1, btnH - 1, 3)
    nvgStrokeColor(vg, nvgRGBA(240, 180, 80, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local btnLabel = GS.dihataRevengeConfirmType == "ad" and "看广告" or "确定"
    nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
    nvgText(vg, confirmX + btnW / 2, btnBaseY + btnH / 2, btnLabel, nil)

    if isHovered(confirmX, btnBaseY, btnW, btnH) then
        drawHoverHighlight(vg, confirmX, btnBaseY, btnW, btnH, 3)
    end
end

-- ====================================================================
-- 虚拟广告倒计时全屏遮罩（兑换码 shenyuanjiaguang）
-- ====================================================================
function M.drawAbyssFakeAdOverlay()
    if not GS.abyssFakeAdTimer then return end

    local vg = M.vg
    local W = GS.SCREEN_W
    local H = GS.SCREEN_H

    -- 全屏半透明黑色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    -- 倒计时数字
    local secs = math.ceil(GS.abyssFakeAdTimer)
    if secs < 0 then secs = 0 end

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 大号倒计时
    nvgFontSize(vg, 48)
    nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
    nvgText(vg, W / 2, H / 2 - 20, tostring(secs), nil)

    -- 提示文字
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(220, 200, 170, 200))
    nvgText(vg, W / 2, H / 2 + 25, "正在吸收异世界能量...", nil)

    -- 底部进度条
    local barW = math.min(W * 0.6, 240)
    local barH = 6
    local barX = (W - barW) / 2
    local barY = H / 2 + 50
    local progress = 1.0 - (GS.abyssFakeAdTimer / 30.0)
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(60, 50, 40, 180))
    nvgFill(vg)

    -- 进度
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3)
    nvgFillColor(vg, nvgRGBA(255, 180, 40, 230))
    nvgFill(vg)
end

-- 导出 drawTooltipPanel 供外部模块（如签到面板）直接调用
M.drawTooltipPanel = drawTooltipPanel

end -- sub.init

return sub
