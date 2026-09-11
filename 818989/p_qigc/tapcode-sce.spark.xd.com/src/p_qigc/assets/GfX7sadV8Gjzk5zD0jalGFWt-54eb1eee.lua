-- ====================================================================
-- MonitorPanel.lua — 监测面板模块
-- 功能：管理员专用监测面板，包含在线监测和广告监测两个标签页
-- 数据通过排行榜（iscores）传递，支持按玩家分类查看
-- ====================================================================
local GS = require("GameState")
local OnlineMonitor = require("OnlineMonitor")
local M = {}

-- ── 常量 ──
local RANK_PAGE_SIZE = 1000
local NICKNAME_BATCH_SIZE = 200  -- GetUserNickname 每批最多查询数量

-- ── 分批查询昵称（绕过单次请求数量上限）──
local function batchGetNicknames(userIds, onDone)
    local map = {}
    local total = #userIds
    if total == 0 then onDone(map); return end
    local totalBatches = math.ceil(total / NICKNAME_BATCH_SIZE)
    local doneBatches = 0
    for i = 1, total, NICKNAME_BATCH_SIZE do
        local batch = {}
        for j = i, math.min(i + NICKNAME_BATCH_SIZE - 1, total) do
            batch[#batch + 1] = userIds[j]
        end
        GetUserNickname({
            userIds = batch,
            onSuccess = function(nicknames)
                for _, info in ipairs(nicknames) do
                    if info.nickname and info.nickname ~= "" then
                        local key = tostring(math.floor(tonumber(info.userId) or 0))
                        map[key] = info.nickname
                    end
                end
                doneBatches = doneBatches + 1
                if doneBatches >= totalBatches then onDone(map) end
            end,
            onError = function()
                doneBatches = doneBatches + 1
                if doneBatches >= totalBatches then onDone(map) end
            end
        })
    end
end
local AD_REPORT_KEY_PREFIX = "ad_click_"     -- 广告点击次数 key 前缀 + YYYYMMDD
local AD_SUCCESS_KEY_PREFIX = "ad_succ_"     -- 广告成功次数 key 前缀 + YYYYMMDD
local AD_FAIL_KEY_PREFIX = "ad_fail_"        -- 广告失败次数 key 前缀 + YYYYMMDD
local CHART_DAYS = 15                        -- 折线图显示天数

-- ── 面板状态 ──
M.showPanel = false
M.activeTab = "online"       -- "online" | "ad"

-- ── 广告监测状态 ──
M.adPanelDate = ""           -- 当前查看日期 YYYYMMDD
M.adPanelDateDisplay = ""    -- 显示用 "2026-03-30"
M.adRankData = {}            -- { {userId, nickname, clicks, successes, failures}, ... }
M.adRankLoading = false
M.adRankLoaded = false
M.adScrollY = 0
M.adDragging = false
M.adDragStartY = 0
M.adDragStartScroll = 0
M.adDragMoved = false
M.adListH = 0           -- 广告列表实际可见高度（用于滚动计算）

-- ── 折线图数据 ──
M.chartData = {}             -- { {date="03-28", count=5}, ... } 最近15天成功领奖
M.chartLoading = false
M.chartLoaded = false
M.chartPendingCount = 0      -- 还有多少天的数据待返回

-- ── 等级监测状态 ──
M.lvlRankData = {}           -- { {userId, nickname, classId, level}, ... }
M.lvlRankLoading = false
M.lvlRankLoaded = false
M.lvlScrollY = 0
M.lvlDragging = false
M.lvlDragStartY = 0
M.lvlDragStartScroll = 0
M.lvlDragMoved = false
M.lvlListH = 0               -- 可见列表高度（用于滚动计算）
M.lvlPanelDate = ""          -- 当前查看日期 YYYYMMDD
M.lvlPanelDateDisplay = ""   -- 显示用 "2026-03-30"

-- 职业中文名和颜色映射
local CLASS_NAMES = {
    warrior  = "战士",
    hunter   = "猎人",
    assassin = "刺客",
    mage     = "法师",
    priest   = "牧师",
    traveler = "旅人",
}
local CLASS_COLORS = {
    warrior  = {220, 100,  70},
    hunter   = { 80, 200,  80},
    assassin = {190,  80, 210},
    mage     = { 80, 140, 240},
    priest   = {240, 220,  80},
    traveler = {160, 160, 160},
}

-- ── 按钮 Rect ──
M.panelRect = nil
M.closeBtnRect = nil
M.tabOnlineRect = nil
M.tabAdRect = nil
M.tabLvlRect = nil
M.adPrevDateBtnRect = nil
M.adNextDateBtnRect = nil
M.lvlPrevDateBtnRect = nil
M.lvlNextDateBtnRect = nil

-- ══════════════════════════════════════════════
-- 广告数据上报（在广告调用处调用）
-- ══════════════════════════════════════════════

--- 上报广告点击
function M.reportAdClick()
    if not clientCloud then return end
    local today = os.date("%Y%m%d")
    clientCloud:Add(AD_REPORT_KEY_PREFIX .. today, 1, {
        error = function(code, reason)
            print("[MonitorPanel] 广告点击上报失败:", code, reason)
        end
    })
end

--- 上报广告成功
function M.reportAdSuccess()
    if not clientCloud then return end
    local today = os.date("%Y%m%d")
    clientCloud:Add(AD_SUCCESS_KEY_PREFIX .. today, 1, {
        error = function(code, reason)
            print("[MonitorPanel] 广告成功上报失败:", code, reason)
        end
    })
end

--- 上报广告失败
function M.reportAdFail()
    if not clientCloud then return end
    local today = os.date("%Y%m%d")
    clientCloud:Add(AD_FAIL_KEY_PREFIX .. today, 1, {
        error = function(code, reason)
            print("[MonitorPanel] 广告失败上报失败:", code, reason)
        end
    })
end

-- ══════════════════════════════════════════════
-- 面板控制
-- ══════════════════════════════════════════════

function M.openPanel()
    M.showPanel = true
    M.activeTab = "online"
    OnlineMonitor.openPanel()
    -- 初始化广告标签日期
    M.adPanelDate = os.date("%Y%m%d")
    M.adPanelDateDisplay = os.date("%Y-%m-%d")
    M.adScrollY = 0
    M.adRankData = {}
    M.adRankLoaded = false
    M.chartData = {}
    M.chartLoaded = false
    -- 初始化等级标签日期
    M.lvlPanelDate = os.date("%Y%m%d")
    M.lvlPanelDateDisplay = os.date("%Y-%m-%d")
    M.lvlScrollY = 0
    M.lvlRankData = {}
    M.lvlRankLoaded = false
end

function M.closePanel()
    M.showPanel = false
    OnlineMonitor.closePanel()
    M.adRankData = {}
    M.adRankLoaded = false
    M.adRankLoading = false
    M.chartData = {}
    M.chartLoaded = false
    M.chartLoading = false
    M.lvlRankData = {}
    M.lvlRankLoaded = false
    M.lvlRankLoading = false
end

function M.switchTab(tab)
    if M.activeTab == tab then return end
    M.activeTab = tab
    if tab == "online" then
        OnlineMonitor.openPanel()
    elseif tab == "ad" then
        OnlineMonitor.closePanel()
        M.adScrollY = 0
        M.adRankData = {}
        M.adRankLoaded = false
        M._fetchAdRankData()
        -- 拉取折线图数据
        if not M.chartLoaded and not M.chartLoading then
            M._fetchChartData()
        end
    else -- "level"
        OnlineMonitor.closePanel()
        M.lvlScrollY = 0
        M.lvlRankData = {}
        M.lvlRankLoaded = false
        M._fetchLevelRankData()
    end
end

-- ── 广告日期切换 ──
function M.switchAdDate(delta)
    local y = tonumber(M.adPanelDate:sub(1, 4))
    local mo = tonumber(M.adPanelDate:sub(5, 6))
    local d = tonumber(M.adPanelDate:sub(7, 8))
    local t = os.time({ year = y, month = mo, day = d, hour = 12 })
    t = t + delta * 86400
    local nd = os.date("*t", t)
    M.adPanelDate = string.format("%04d%02d%02d", nd.year, nd.month, nd.day)
    M.adPanelDateDisplay = string.format("%04d-%02d-%02d", nd.year, nd.month, nd.day)

    local today = os.date("%Y%m%d")
    if M.adPanelDate > today then
        M.adPanelDate = today
        M.adPanelDateDisplay = os.date("%Y-%m-%d")
        return
    end

    M.adScrollY = 0
    M.adRankData = {}
    M.adRankLoaded = false
    M._fetchAdRankData()
end

-- ── 拉取广告排行榜数据 ──
function M._fetchAdRankData()
    if M.adRankLoading then return end
    M.adRankLoading = true
    M.adRankLoaded = false

    local clickKey = AD_REPORT_KEY_PREFIX .. M.adPanelDate
    local succKey = AD_SUCCESS_KEY_PREFIX .. M.adPanelDate
    local failKey = AD_FAIL_KEY_PREFIX .. M.adPanelDate

    clientCloud:GetRankList(succKey, 0, RANK_PAGE_SIZE, {
        ok = function(rankList)
            M.adRankLoading = false
            M.adRankLoaded = true

            local entries = {}
            local userIds = {}
            for i, item in ipairs(rankList) do
                local clicks = item.iscore[clickKey] or 0
                local successes = item.iscore[succKey] or 0
                local failures = item.iscore[failKey] or 0
                if type(clicks) == "string" then clicks = tonumber(clicks) or 0 end
                if type(successes) == "string" then successes = tonumber(successes) or 0 end
                if type(failures) == "string" then failures = tonumber(failures) or 0 end
                table.insert(entries, {
                    rank = i,
                    userId = item.userId,
                    nickname = "",
                    clicks = clicks,
                    successes = successes,
                    failures = failures,
                })
                table.insert(userIds, item.userId)
            end

            if #userIds == 0 then
                M.adRankData = entries
                return
            end

            batchGetNicknames(userIds, function(map)
                for _, entry in ipairs(entries) do
                    entry.nickname = map[tostring(entry.userId)] or ("ID:" .. tostring(entry.userId))
                end
                M.adRankData = entries
            end)
        end,
        error = function(code, reason)
            M.adRankLoading = false
            M.adRankLoaded = true
            M.adRankData = {}
            print("[MonitorPanel] 拉取广告排行榜失败:", code, reason)
        end
    }, clickKey, failKey)
end

-- ── 拉取15天折线图数据 ──
function M._fetchChartData()
    if not clientCloud then return end
    M.chartLoading = true
    M.chartLoaded = false
    M.chartData = {}

    local now = os.time()
    local days = {}
    for i = CHART_DAYS - 1, 0, -1 do
        local t = now - i * 86400
        local dt = os.date("*t", t)
        local dateKey = string.format("%04d%02d%02d", dt.year, dt.month, dt.day)
        local dateLabel = string.format("%02d-%02d", dt.month, dt.day)
        table.insert(days, { key = dateKey, label = dateLabel, count = 0 })
    end

    M.chartPendingCount = #days

    for idx, day in ipairs(days) do
        local succKey = AD_SUCCESS_KEY_PREFIX .. day.key
        clientCloud:GetRankList(succKey, 0, RANK_PAGE_SIZE, {
            ok = function(rankList)
                local total = 0
                for _, item in ipairs(rankList) do
                    local v = item.iscore[succKey] or 0
                    total = total + v
                end
                days[idx].count = total
                M.chartPendingCount = M.chartPendingCount - 1
                if M.chartPendingCount <= 0 then
                    M.chartData = days
                    M.chartLoading = false
                    M.chartLoaded = true
                end
            end,
            error = function(code, reason)
                days[idx].count = 0
                M.chartPendingCount = M.chartPendingCount - 1
                if M.chartPendingCount <= 0 then
                    M.chartData = days
                    M.chartLoading = false
                    M.chartLoaded = true
                end
            end
        })
    end
end

-- ── 等级日期切换 ──
function M.switchLvlDate(delta)
    local y = tonumber(M.lvlPanelDate:sub(1, 4))
    local mo = tonumber(M.lvlPanelDate:sub(5, 6))
    local d = tonumber(M.lvlPanelDate:sub(7, 8))
    local t = os.time({ year = y, month = mo, day = d, hour = 12 })
    t = t + delta * 86400
    local nd = os.date("*t", t)
    M.lvlPanelDate = string.format("%04d%02d%02d", nd.year, nd.month, nd.day)
    M.lvlPanelDateDisplay = string.format("%04d-%02d-%02d", nd.year, nd.month, nd.day)

    local today = os.date("%Y%m%d")
    if M.lvlPanelDate > today then
        M.lvlPanelDate = today
        M.lvlPanelDateDisplay = os.date("%Y-%m-%d")
        return
    end

    M.lvlScrollY = 0
    M.lvlRankData = {}
    M.lvlRankLoaded = false
    M._fetchLevelRankData()
end

-- ── 拉取等级排行榜数据 ──
function M._fetchLevelRankData()
    if M.lvlRankLoading then return end
    if not clientCloud then return end
    M.lvlRankLoading = true
    M.lvlRankLoaded = false

    -- 以当天在线时长为主键，附带 player_level 和 player_class
    local onlineKey = "online_" .. M.lvlPanelDate

    clientCloud:GetRankList(onlineKey, 0, RANK_PAGE_SIZE, {
        ok = function(rankList)
            M.lvlRankLoading = false
            M.lvlRankLoaded = true

            local entries = {}
            local userIds = {}
            for _, item in ipairs(rankList) do
                local level = 0
                local classId = "warrior"
                if item.score then
                    local lv = item.score.player_level
                    if lv then
                        if type(lv) == "string" then lv = tonumber(lv) or 0 end
                        level = lv
                    end
                    local cl = item.score.player_class
                    if cl and type(cl) == "string" and cl ~= "" then
                        classId = cl
                    end
                end
                local loginTs = 0
                if item.score then
                    local lt = item.score.login_ts
                    if lt then
                        if type(lt) == "string" then lt = tonumber(lt) or 0 end
                        loginTs = lt
                    end
                end
                table.insert(entries, {
                    userId  = item.userId,
                    nickname = "",
                    classId = classId,
                    level   = level,
                    loginTs = loginTs,
                    isOnline = false,
                })
                table.insert(userIds, item.userId)
            end

            -- 判断在线状态（心跳120秒内视为在线）
            local nowTs = os.time()
            for _, e in ipairs(entries) do
                if e.loginTs > 0 and (nowTs - e.loginTs) < 120 then
                    e.isOnline = true
                end
            end
            -- 在线优先，同组按等级降序
            table.sort(entries, function(a, b)
                if a.isOnline ~= b.isOnline then
                    return a.isOnline
                end
                return a.level > b.level
            end)
            -- 赋排名
            for i, e in ipairs(entries) do e.rank = i end

            if #userIds == 0 then
                M.lvlRankData = entries
                return
            end

            batchGetNicknames(userIds, function(map)
                for _, entry in ipairs(entries) do
                    entry.nickname = map[tostring(entry.userId)] or ("ID:" .. tostring(entry.userId))
                end
                M.lvlRankData = entries
            end)
        end,
        error = function(code, reason)
            M.lvlRankLoading = false
            M.lvlRankLoaded = true
            M.lvlRankData = {}
            print("[MonitorPanel] 拉取等级排行榜失败:", code, reason)
        end
    }, "player_level", "player_class", "login_ts")
end

-- ══════════════════════════════════════════════
-- 绘制面板
-- ══════════════════════════════════════════════

function M.drawPanel(vg)
    if not M.showPanel then return end

    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    local pw = math.min(360, sw - 16)
    local ph = math.min(520, sh - 24)
    local px = math.floor((sw - pw) / 2)
    local py = math.floor((sh - ph) / 2)
    M.panelRect = { x = px, y = py, w = pw, h = ph }

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, sw, sh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, pw, ph, 8)
    nvgFillColor(vg, nvgRGBA(25, 15, 15, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 80, 80, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")

    -- ── 标题栏 ──
    local titleH = 28
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, px + pw / 2, py + titleH / 2, "数据监测", nil)

    -- 关闭按钮
    local closeBtnSize = 20
    local closeBtnX = px + pw - closeBtnSize - 6
    local closeBtnY = py + 4
    M.closeBtnRect = { x = closeBtnX, y = closeBtnY, w = closeBtnSize, h = closeBtnSize }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnSize, closeBtnSize, 3)
    nvgFillColor(vg, nvgRGBA(150, 50, 50, 200))
    nvgFill(vg)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, closeBtnX + closeBtnSize / 2, closeBtnY + closeBtnSize / 2, "X", nil)

    -- ── 标签栏 ──
    local tabY = py + titleH
    local tabH = 26
    local tabGap = 4
    local tabW = math.floor((pw - 20 - tabGap * 2) / 3)
    local tabStartX = px + 10

    local tabs = {
        { id = "online", label = "在线监测", activeColor = {60, 100, 160}, textColor = {200, 220, 255} },
        { id = "ad",     label = "广告监测", activeColor = {160, 80,  60}, textColor = {255, 210, 200} },
        { id = "level",  label = "等级监测", activeColor = {60, 130,  80}, textColor = {200, 255, 210} },
    }

    for i, tab in ipairs(tabs) do
        local tx = tabStartX + (i - 1) * (tabW + tabGap)
        local isActive = M.activeTab == tab.id
        local rect = { x = tx, y = tabY, w = tabW, h = tabH }
        if i == 1 then M.tabOnlineRect = rect
        elseif i == 2 then M.tabAdRect = rect
        else M.tabLvlRect = rect end

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW, tabH, 4)
        local ac = tab.activeColor
        nvgFillColor(vg, isActive and nvgRGBA(ac[1], ac[2], ac[3], 230) or nvgRGBA(40, 40, 50, 200))
        nvgFill(vg)
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tc = tab.textColor
        nvgFillColor(vg, isActive and nvgRGBA(tc[1], tc[2], tc[3], 255) or nvgRGBA(140, 150, 170, 200))
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, tab.label, nil)
    end

    -- ── 内容区域 ──
    local contentY = tabY + tabH + 4
    local contentH = ph - (contentY - py) - 4

    if M.activeTab == "online" then
        M._drawOnlineContent(vg, px, contentY, pw, contentH)
    elseif M.activeTab == "ad" then
        M._drawAdContent(vg, px, contentY, pw, contentH)
    else
        M._drawLevelContent(vg, px, contentY, pw, contentH)
    end
end

-- ══════════════════════════════════════════════
-- 在线监测内容
-- ══════════════════════════════════════════════

function M._drawOnlineContent(vg, px, contentY, pw, contentH)
    local OM = OnlineMonitor

    -- 日期切换栏
    local dateBarY = contentY
    local dateBarH = 26
    local arrowW = 30

    local prevX = px + 8
    OM.prevDateBtnRect = { x = prevX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, prevX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, nvgRGBA(60, 70, 100, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 200, 255, 255))
    nvgText(vg, prevX + arrowW / 2, dateBarY + dateBarH / 2, "<", nil)

    local nextX = px + pw - arrowW - 8
    OM.nextDateBtnRect = { x = nextX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    local isToday = (OM.panelDate == os.date("%Y%m%d"))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nextX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, isToday and nvgRGBA(40, 40, 50, 150) or nvgRGBA(60, 70, 100, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isToday and nvgRGBA(100, 100, 120, 150) or nvgRGBA(180, 200, 255, 255))
    nvgText(vg, nextX + arrowW / 2, dateBarY + dateBarH / 2, ">", nil)

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
    local dateLabel = OM.panelDateDisplay
    if isToday then dateLabel = dateLabel .. " (今天)" end
    nvgText(vg, px + pw / 2, dateBarY + dateBarH / 2, dateLabel, nil)

    -- 列表区域
    local listY = dateBarY + dateBarH + 4
    local bottomStatH = 30  -- 底部统计区域高度
    local listH = contentH - dateBarH - 8 - bottomStatH
    local pad = 6
    local itemH = 28
    local gap = 2

    local clipX = px + pad
    local clipY = listY
    local clipW = pw - pad * 2
    local clipH = listH

    if OM.rankLoading then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 170, 220, 200))
        nvgText(vg, px + pw / 2, listY + listH / 2, "加载中...", nil)
        M._drawOnlineBottom(vg, px, listY + listH + 2, pw, bottomStatH, OM)
        return
    end

    if OM.rankLoaded and #OM.rankData == 0 then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 150, 170, 180))
        nvgText(vg, px + pw / 2, listY + listH / 2, "暂无数据", nil)
        M._drawOnlineBottom(vg, px, listY + listH + 2, pw, bottomStatH, OM)
        return
    end

    local totalItems = #OM.rankData
    local contentTotalH = totalItems * (itemH + gap)
    local scrollMax = math.max(0, contentTotalH - clipH)
    OM.scrollY = math.max(0, math.min(OM.scrollY, scrollMax))

    nvgSave(vg)
    nvgScissor(vg, clipX, clipY, clipW, clipH)

    local startY = clipY - OM.scrollY
    local myUserId = clientCloud and clientCloud.userId or 0

    for i, entry in ipairs(OM.rankData) do
        local iy = startY + (i - 1) * (itemH + gap)
        if iy + itemH >= clipY and iy <= clipY + clipH then
            local isMe = (entry.userId == myUserId)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, clipX, iy, clipW, itemH, 4)
            if isMe then
                nvgFillColor(vg, nvgRGBA(50, 70, 100, 180))
            elseif i % 2 == 0 then
                nvgFillColor(vg, nvgRGBA(30, 35, 55, 150))
            else
                nvgFillColor(vg, nvgRGBA(35, 40, 60, 150))
            end
            nvgFill(vg)

            if isMe then
                nvgStrokeColor(vg, nvgRGBA(80, 140, 220, 150))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            end

            local midY = iy + itemH / 2

            -- 排名
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if i <= 3 then
                local rankColors = {
                    {255, 215, 0},
                    {192, 192, 192},
                    {205, 127, 50},
                }
                local rc = rankColors[i]
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            else
                nvgFillColor(vg, nvgRGBA(140, 150, 180, 200))
            end
            nvgText(vg, clipX + 14, midY, "#" .. i, nil)

            -- 在线状态圆点
            local dotX = clipX + 28
            if entry.isOnline then
                nvgBeginPath(vg)
                nvgCircle(vg, dotX, midY, 3.5)
                nvgFillColor(vg, nvgRGBA(50, 220, 80, 255))
                nvgFill(vg)
            else
                nvgBeginPath(vg)
                nvgCircle(vg, dotX, midY, 3)
                nvgFillColor(vg, nvgRGBA(100, 100, 110, 150))
                nvgFill(vg)
            end

            -- 昵称
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local nameColor = isMe and nvgRGBA(120, 180, 255, 255) or nvgRGBA(200, 210, 230, 230)
            nvgFillColor(vg, nameColor)
            local displayName = entry.nickname
            if isMe then displayName = displayName .. " (我)" end
            nvgText(vg, clipX + 36, midY, displayName, nil)

            -- 在线时长
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 200, 160, 220))
            nvgText(vg, clipX + clipW - 4, midY, OnlineMonitor.formatTime(entry.seconds), nil)
        end
    end

    -- 滚动条
    if scrollMax > 0 then
        local barW = 3
        local barX = clipX + clipW - barW - 1
        local barAreaH = clipH - 4
        local thumbH = math.max(12, barAreaH * clipH / contentTotalH)
        local thumbY = clipY + 2 + (barAreaH - thumbH) * (OM.scrollY / scrollMax)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, clipY + 2, barW, barAreaH, 1.5)
        nvgFillColor(vg, nvgRGBA(40, 50, 70, 80))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, barW, thumbH, 1.5)
        nvgFillColor(vg, nvgRGBA(80, 140, 220, 180))
        nvgFill(vg)
    end

    nvgRestore(vg)

    -- 底部统计
    M._drawOnlineBottom(vg, px, listY + listH + 2, pw, bottomStatH, OM)
end

-- ── 在线监测底部统计 ──
function M._drawOnlineBottom(vg, px, bottomY, pw, bottomH, OM)
    local onlineCount = 0
    local totalSeconds = 0
    local totalPlayers = #OM.rankData
    local over60Count = 0

    for _, entry in ipairs(OM.rankData) do
        if entry.isOnline then onlineCount = onlineCount + 1 end
        local sec = entry.seconds or 0
        totalSeconds = totalSeconds + sec
        if sec >= 3600 then over60Count = over60Count + 1 end  -- >= 60分钟 = 3600秒
    end

    local avgStr = "0分"
    if totalPlayers > 0 then
        local avgSec = math.floor(totalSeconds / totalPlayers)
        if avgSec >= 3600 then
            avgStr = string.format("%d时%02d分", math.floor(avgSec / 3600), math.floor(avgSec % 3600 / 60))
        else
            avgStr = string.format("%d分", math.floor(avgSec / 60))
        end
    end

    -- 第一行：在线人数 | 平均在线时长
    local row1Y = bottomY + 4
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 200, 130, 220))
    nvgText(vg, px + 10, row1Y + 4, "在线:" .. onlineCount .. "人", nil)

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 200, 255, 200))
    nvgText(vg, px + pw / 2, row1Y + 4, "均:" .. avgStr, nil)

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 180, 100, 200))
    nvgText(vg, px + pw - 10, row1Y + 4, ">60分:" .. over60Count .. "人", nil)

    -- 第二行：总人数
    local row2Y = row1Y + 13
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 150, 180, 160))
    nvgText(vg, px + 10, row2Y + 4, "共 " .. totalPlayers .. " 人有数据", nil)
end

-- ══════════════════════════════════════════════
-- 广告监测内容
-- ══════════════════════════════════════════════

function M._drawAdContent(vg, px, contentY, pw, contentH)
    -- 日期切换栏
    local dateBarY = contentY
    local dateBarH = 26
    local arrowW = 30

    local prevX = px + 8
    M.adPrevDateBtnRect = { x = prevX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, prevX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, nvgRGBA(100, 60, 60, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, prevX + arrowW / 2, dateBarY + dateBarH / 2, "<", nil)

    local nextX = px + pw - arrowW - 8
    M.adNextDateBtnRect = { x = nextX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    local isToday = (M.adPanelDate == os.date("%Y%m%d"))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nextX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, isToday and nvgRGBA(40, 40, 50, 150) or nvgRGBA(100, 60, 60, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isToday and nvgRGBA(100, 100, 120, 150) or nvgRGBA(255, 200, 200, 255))
    nvgText(vg, nextX + arrowW / 2, dateBarY + dateBarH / 2, ">", nil)

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 230, 220, 255))
    local dlabel = M.adPanelDateDisplay
    if isToday then dlabel = dlabel .. " (今天)" end
    nvgText(vg, px + pw / 2, dateBarY + dateBarH / 2, dlabel, nil)

    -- 列表表头
    local headerY = dateBarY + dateBarH + 2
    local headerH = 20
    local pad = 6
    local clipX = px + pad
    local clipW = pw - pad * 2

    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 150, 140, 200))
    nvgText(vg, clipX + 4, headerY + headerH / 2, "#", nil)
    nvgText(vg, clipX + 24, headerY + headerH / 2, "玩家", nil)

    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local dataAreaX = clipX + clipW * 0.5
    local colW = clipW * 0.5 / 3
    nvgFillColor(vg, nvgRGBA(200, 180, 100, 200))
    nvgText(vg, dataAreaX + colW * 0.5, headerY + headerH / 2, "点击", nil)
    nvgFillColor(vg, nvgRGBA(100, 200, 120, 200))
    nvgText(vg, dataAreaX + colW * 1.5, headerY + headerH / 2, "成功", nil)
    nvgFillColor(vg, nvgRGBA(200, 100, 100, 200))
    nvgText(vg, dataAreaX + colW * 2.5, headerY + headerH / 2, "失败", nil)

    -- 表头分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, clipX, headerY + headerH)
    nvgLineTo(vg, clipX + clipW, headerY + headerH)
    nvgStrokeColor(vg, nvgRGBA(120, 80, 80, 100))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 底部区域划分：统计行 + 折线图
    local chartH = 110       -- 折线图高度
    local statRowH = 16      -- 统计行高度
    local bottomH = statRowH + chartH + 4

    -- 列表内容
    local listY = headerY + headerH + 2
    local listH = contentH - (listY - contentY) - bottomH - 4
    M.adListH = listH   -- 缓存供滚动计算使用
    local itemH = 28
    local itemGap = 2
    local clipY = listY

    if M.adRankLoading then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 150, 150, 200))
        nvgText(vg, px + pw / 2, listY + listH / 2, "加载中...", nil)
        M._drawAdBottom(vg, px, listY + listH + 2, pw, bottomH, dataAreaX, colW, 0, 0, 0)
        return
    end

    if M.adRankLoaded and #M.adRankData == 0 then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 150, 170, 180))
        nvgText(vg, px + pw / 2, listY + listH / 2, "暂无数据", nil)
        M._drawAdBottom(vg, px, listY + listH + 2, pw, bottomH, dataAreaX, colW, 0, 0, 0)
        return
    end

    local totalItems = #M.adRankData
    local adContentH = totalItems * (itemH + itemGap)
    local scrollMax = math.max(0, adContentH - listH)
    M.adScrollY = math.max(0, math.min(M.adScrollY, scrollMax))

    -- 统计汇总
    local totalClicks = 0
    local totalSuccesses = 0
    local totalFailures = 0
    for _, entry in ipairs(M.adRankData) do
        totalClicks = totalClicks + entry.clicks
        totalSuccesses = totalSuccesses + entry.successes
        totalFailures = totalFailures + entry.failures
    end

    nvgSave(vg)
    nvgScissor(vg, clipX, clipY, clipW, listH)

    local startY = clipY - M.adScrollY
    local myUserId = clientCloud and clientCloud.userId or 0

    for i, entry in ipairs(M.adRankData) do
        local iy = startY + (i - 1) * (itemH + itemGap)
        if iy + itemH >= clipY and iy <= clipY + listH then
            local isMe = (entry.userId == myUserId)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, clipX, iy, clipW, itemH, 4)
            if isMe then
                nvgFillColor(vg, nvgRGBA(70, 50, 50, 180))
            elseif i % 2 == 0 then
                nvgFillColor(vg, nvgRGBA(35, 25, 25, 150))
            else
                nvgFillColor(vg, nvgRGBA(40, 30, 30, 150))
            end
            nvgFill(vg)

            if isMe then
                nvgStrokeColor(vg, nvgRGBA(200, 100, 80, 150))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            end

            local midY = iy + itemH / 2

            -- 排名
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if i <= 3 then
                local rankColors = {
                    {255, 215, 0},
                    {192, 192, 192},
                    {205, 127, 50},
                }
                local rc = rankColors[i]
                nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
            else
                nvgFillColor(vg, nvgRGBA(140, 150, 180, 200))
            end
            nvgText(vg, clipX + 14, midY, "#" .. i, nil)

            -- 昵称
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local nameColor = isMe and nvgRGBA(255, 160, 140, 255) or nvgRGBA(220, 200, 190, 230)
            nvgFillColor(vg, nameColor)
            local displayName = entry.nickname
            if isMe then displayName = displayName .. " (我)" end
            nvgText(vg, clipX + 28, midY, displayName, nil)

            -- 数据列
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 200, 120, 230))
            nvgText(vg, dataAreaX + colW * 0.5, midY, tostring(entry.clicks), nil)
            nvgFillColor(vg, nvgRGBA(120, 220, 140, 230))
            nvgText(vg, dataAreaX + colW * 1.5, midY, tostring(entry.successes), nil)
            nvgFillColor(vg, nvgRGBA(220, 120, 120, 230))
            nvgText(vg, dataAreaX + colW * 2.5, midY, tostring(entry.failures), nil)
        end
    end

    -- 滚动条
    if scrollMax > 0 then
        local barW = 3
        local barX = clipX + clipW - barW - 1
        local barAreaH = listH - 4
        local thumbH = math.max(12, barAreaH * listH / adContentH)
        local thumbY = clipY + 2 + (barAreaH - thumbH) * (M.adScrollY / scrollMax)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, clipY + 2, barW, barAreaH, 1.5)
        nvgFillColor(vg, nvgRGBA(50, 40, 40, 80))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, barW, thumbH, 1.5)
        nvgFillColor(vg, nvgRGBA(200, 100, 80, 180))
        nvgFill(vg)
    end

    nvgRestore(vg)

    -- 底部区域
    M._drawAdBottom(vg, px, listY + listH + 2, pw, bottomH, dataAreaX, colW, totalClicks, totalSuccesses, totalFailures)
end

-- ── 广告监测底部：统计 + 折线图 ──
function M._drawAdBottom(vg, px, bottomY, pw, bottomH, dataAreaX, colW, totalClicks, totalSuccesses, totalFailures)
    -- 统计行
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 180, 100, 200))
    nvgText(vg, px + 10, bottomY + 6, "点击:" .. totalClicks, nil)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 200, 120, 200))
    nvgText(vg, px + pw / 2, bottomY + 6, "成功:" .. totalSuccesses, nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 100, 100, 200))
    nvgText(vg, px + pw - 10, bottomY + 6, "失败:" .. totalFailures, nil)

    -- 分隔线
    local chartTopY = bottomY + 18
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 8, chartTopY)
    nvgLineTo(vg, px + pw - 8, chartTopY)
    nvgStrokeColor(vg, nvgRGBA(120, 80, 80, 80))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 折线图标题
    local chartTitleY = chartTopY + 2
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 160, 140, 180))
    nvgText(vg, px + 10, chartTitleY + 6, "近15天成功领奖趋势", nil)

    if M.chartLoading then
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 130, 120, 180))
        nvgText(vg, px + pw / 2, chartTopY + 50, "加载中...", nil)
        return
    end

    if not M.chartLoaded or #M.chartData == 0 then
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 130, 120, 150))
        nvgText(vg, px + pw / 2, chartTopY + 50, "暂无趋势数据", nil)
        return
    end

    -- 折线图绘制区域
    local chartPad = 10
    local chartLabelW = 26    -- 左侧Y轴标签宽度
    local chartBottomH = 16   -- 底部X轴标签高度
    local chartX = px + chartPad + chartLabelW
    local chartY = chartTitleY + 14
    local chartW = pw - chartPad * 2 - chartLabelW
    local chartH = 110 - 14 - chartBottomH - 6

    -- 找最大值
    local maxVal = 1
    for _, d in ipairs(M.chartData) do
        if d.count > maxVal then maxVal = d.count end
    end
    -- 向上取整到美观刻度
    local niceMax = maxVal
    if maxVal <= 5 then niceMax = 5
    elseif maxVal <= 10 then niceMax = 10
    elseif maxVal <= 20 then niceMax = 20
    elseif maxVal <= 50 then niceMax = 50
    elseif maxVal <= 100 then niceMax = 100
    else niceMax = math.ceil(maxVal / 50) * 50
    end

    -- Y轴网格线 (0, 中间, 最大)
    local yTicks = {0, math.floor(niceMax / 2), niceMax}
    nvgFontSize(vg, 8)
    for _, tick in ipairs(yTicks) do
        local yy = chartY + chartH - (tick / niceMax) * chartH
        -- 网格线
        nvgBeginPath(vg)
        nvgMoveTo(vg, chartX, yy)
        nvgLineTo(vg, chartX + chartW, yy)
        nvgStrokeColor(vg, nvgRGBA(80, 60, 60, 60))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)
        -- 标签
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 120, 110, 160))
        nvgText(vg, chartX - 3, yy, tostring(tick), nil)
    end

    -- 数据点和折线
    local n = #M.chartData
    if n < 2 then return end
    local stepX = chartW / (n - 1)

    -- 绘制填充区域（半透明）
    nvgBeginPath(vg)
    for i, d in ipairs(M.chartData) do
        local dx = chartX + (i - 1) * stepX
        local dy = chartY + chartH - (d.count / niceMax) * chartH
        if i == 1 then
            nvgMoveTo(vg, dx, dy)
        else
            nvgLineTo(vg, dx, dy)
        end
    end
    nvgLineTo(vg, chartX + (n - 1) * stepX, chartY + chartH)
    nvgLineTo(vg, chartX, chartY + chartH)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(100, 200, 120, 30))
    nvgFill(vg)

    -- 绘制折线
    nvgBeginPath(vg)
    for i, d in ipairs(M.chartData) do
        local dx = chartX + (i - 1) * stepX
        local dy = chartY + chartH - (d.count / niceMax) * chartH
        if i == 1 then
            nvgMoveTo(vg, dx, dy)
        else
            nvgLineTo(vg, dx, dy)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(100, 220, 140, 230))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 绘制数据点 + X轴标签
    for i, d in ipairs(M.chartData) do
        local dx = chartX + (i - 1) * stepX
        local dy = chartY + chartH - (d.count / niceMax) * chartH

        -- 数据点
        nvgBeginPath(vg)
        nvgCircle(vg, dx, dy, 2.5)
        nvgFillColor(vg, nvgRGBA(100, 230, 140, 255))
        nvgFill(vg)

        -- 数据值（非零时显示）
        if d.count > 0 then
            nvgFontSize(vg, 7)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(150, 240, 170, 220))
            nvgText(vg, dx, dy - 4, tostring(d.count), nil)
        end

        -- X轴标签（间隔显示避免重叠）
        if i == 1 or i == n or (i - 1) % 3 == 0 then
            nvgFontSize(vg, 7)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(140, 120, 110, 160))
            nvgText(vg, dx, chartY + chartH + 3, d.label, nil)
        end
    end
end

-- ══════════════════════════════════════════════
-- 等级监测内容
-- ══════════════════════════════════════════════

function M._drawLevelContent(vg, px, contentY, pw, contentH)
    local dateBarY = contentY
    local dateBarH = 26
    local arrowW = 30
    local pad = 6
    local clipX = px + pad
    local clipW = pw - pad * 2

    -- 左箭头
    local prevX = px + 8
    M.lvlPrevDateBtnRect = { x = prevX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, prevX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, nvgRGBA(40, 100, 60, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 255, 200, 255))
    nvgText(vg, prevX + arrowW / 2, dateBarY + dateBarH / 2, "<", nil)

    -- 右箭头
    local nextX = px + pw - arrowW - 8
    M.lvlNextDateBtnRect = { x = nextX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    local isToday = (M.lvlPanelDate == os.date("%Y%m%d"))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nextX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, isToday and nvgRGBA(30, 40, 35, 150) or nvgRGBA(40, 100, 60, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isToday and nvgRGBA(80, 100, 85, 150) or nvgRGBA(180, 255, 200, 255))
    nvgText(vg, nextX + arrowW / 2, dateBarY + dateBarH / 2, ">", nil)

    -- 日期文字
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(210, 255, 225, 255))
    local dlabel = M.lvlPanelDateDisplay
    if isToday then dlabel = dlabel .. " (今天)" end
    nvgText(vg, px + pw / 2, dateBarY + dateBarH / 2, dlabel, nil)

    -- 表头
    local headerY = dateBarY + dateBarH + 2
    local headerH = 20
    -- 列宽：# | ● | 玩家昵称 | 职业 | 等级
    local rankColW  = 26
    local dotColW   = 10
    local classColW = 36
    local lvlColW   = 34
    local nameColX  = clipX + rankColW + dotColW + 2
    local classColX = clipX + clipW - classColW - lvlColW - 2
    local lvlColX   = clipX + clipW - lvlColW

    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(160, 200, 170, 200))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, clipX + rankColW / 2, headerY + headerH / 2, "#", nil)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, nameColX, headerY + headerH / 2, "玩家昵称", nil)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 200, 160, 200))
    nvgText(vg, classColX + classColW / 2, headerY + headerH / 2, "职业", nil)
    nvgFillColor(vg, nvgRGBA(200, 240, 180, 200))
    nvgText(vg, lvlColX + lvlColW / 2, headerY + headerH / 2, "等级", nil)

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, clipX, headerY + headerH)
    nvgLineTo(vg, clipX + clipW, headerY + headerH)
    nvgStrokeColor(vg, nvgRGBA(80, 140, 100, 100))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 底部统计栏高度
    local statH = 20
    local listY  = headerY + headerH + 2
    local listH  = contentH - (listY - contentY) - statH - 4
    M.lvlListH = listH

    local itemH  = 28
    local itemGap = 2
    local clipY  = listY

    -- 加载中 / 暂无数据
    if M.lvlRankLoading then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 200, 170, 200))
        nvgText(vg, px + pw / 2, listY + listH / 2, "加载中...", nil)
        M._drawLevelStats(vg, px, listY + listH + 2, pw, statH, 0, 0, 0)
        return
    end

    if M.lvlRankLoaded and #M.lvlRankData == 0 then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 170, 155, 180))
        nvgText(vg, px + pw / 2, listY + listH / 2, "暂无数据", nil)
        M._drawLevelStats(vg, px, listY + listH + 2, pw, statH, 0, 0, 0)
        return
    end

    local totalItems = #M.lvlRankData
    local contentTotalH = totalItems * (itemH + itemGap)
    local scrollMax = math.max(0, contentTotalH - listH)
    M.lvlScrollY = math.max(0, math.min(M.lvlScrollY, scrollMax))

    -- 统计数据
    local totalLevel = 0
    local maxLevel   = 0
    for _, e in ipairs(M.lvlRankData) do
        totalLevel = totalLevel + e.level
        if e.level > maxLevel then maxLevel = e.level end
    end
    local avgLevel = totalItems > 0 and math.floor(totalLevel / totalItems) or 0

    nvgSave(vg)
    nvgScissor(vg, clipX, clipY, clipW, listH)

    local startY = clipY - M.lvlScrollY
    local myUserId = clientCloud and clientCloud.userId or 0

    for i, entry in ipairs(M.lvlRankData) do
        local iy = startY + (i - 1) * (itemH + itemGap)
        if iy + itemH >= clipY and iy <= clipY + listH then
            local isMe = (entry.userId == myUserId)

            -- 行背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, clipX, iy, clipW, itemH, 4)
            if isMe then
                nvgFillColor(vg, nvgRGBA(40, 80, 55, 200))
            elseif i % 2 == 0 then
                nvgFillColor(vg, nvgRGBA(25, 38, 30, 150))
            else
                nvgFillColor(vg, nvgRGBA(30, 45, 35, 150))
            end
            nvgFill(vg)
            if isMe then
                nvgStrokeColor(vg, nvgRGBA(80, 200, 120, 150))
                nvgStrokeWidth(vg, 0.8)
                nvgStroke(vg)
            end

            local midY = iy + itemH / 2

            -- 排名
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if i == 1 then
                nvgFillColor(vg, nvgRGBA(255, 215, 0, 255))
            elseif i == 2 then
                nvgFillColor(vg, nvgRGBA(192, 192, 192, 255))
            elseif i == 3 then
                nvgFillColor(vg, nvgRGBA(205, 127, 50, 255))
            else
                nvgFillColor(vg, nvgRGBA(130, 160, 140, 200))
            end
            nvgText(vg, clipX + rankColW / 2, midY, "#" .. i, nil)

            -- 在线状态圆点
            local dotX = clipX + rankColW + dotColW / 2
            if entry.isOnline then
                nvgBeginPath(vg)
                nvgCircle(vg, dotX, midY, 3.5)
                nvgFillColor(vg, nvgRGBA(50, 220, 80, 255))
                nvgFill(vg)
            else
                nvgBeginPath(vg)
                nvgCircle(vg, dotX, midY, 3)
                nvgFillColor(vg, nvgRGBA(100, 100, 110, 150))
                nvgFill(vg)
            end

            -- 昵称
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local nameColor = isMe and nvgRGBA(140, 255, 170, 255) or nvgRGBA(210, 235, 215, 230)
            nvgFillColor(vg, nameColor)
            local displayName = entry.nickname
            if isMe then displayName = displayName .. " (我)" end
            nvgText(vg, nameColX, midY, displayName, nil)

            -- 职业标签
            local cc = CLASS_COLORS[entry.classId] or {160, 160, 160}
            local cn = CLASS_NAMES[entry.classId] or entry.classId
            nvgBeginPath(vg)
            nvgRoundedRect(vg, classColX, iy + 6, classColW, itemH - 12, 3)
            nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 60))
            nvgFill(vg)
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(cc[1], cc[2], cc[3], 240))
            nvgText(vg, classColX + classColW / 2, midY, cn, nil)

            -- 等级
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(160, 240, 180, 255))
            nvgText(vg, lvlColX + lvlColW / 2, midY, "Lv." .. entry.level, nil)
        end
    end

    -- 滚动条
    if scrollMax > 0 then
        local barW   = 3
        local barX   = clipX + clipW - barW - 1
        local barAreaH = listH - 4
        local thumbH = math.max(12, barAreaH * listH / contentTotalH)
        local thumbY = clipY + 2 + (barAreaH - thumbH) * (M.lvlScrollY / scrollMax)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, clipY + 2, barW, barAreaH, 1.5)
        nvgFillColor(vg, nvgRGBA(40, 60, 45, 80))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, thumbY, barW, thumbH, 1.5)
        nvgFillColor(vg, nvgRGBA(80, 200, 120, 180))
        nvgFill(vg)
    end

    nvgRestore(vg)

    M._drawLevelStats(vg, px, listY + listH + 2, pw, statH, totalItems, avgLevel, maxLevel)
end

-- ── 等级监测底部统计 ──
function M._drawLevelStats(vg, px, bottomY, pw, bottomH, total, avgLv, maxLv)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 200, 170, 200))
    nvgText(vg, px + 10, bottomY + bottomH / 2, "共" .. total .. "人", nil)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 240, 180, 200))
    nvgText(vg, px + pw / 2, bottomY + bottomH / 2, "均 Lv." .. avgLv, nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 255, 200, 200))
    nvgText(vg, px + pw - 10, bottomY + bottomH / 2, "最高 Lv." .. maxLv, nil)
end

-- ══════════════════════════════════════════════
-- 输入处理
-- ══════════════════════════════════════════════

function M.handleClick(mx, my, button)
    if not M.showPanel then return false end
    if button ~= MOUSEB_LEFT then return false end

    -- 关闭按钮
    if M.closeBtnRect then
        local r = M.closeBtnRect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            M.closePanel()
            return true
        end
    end

    -- 标签切换
    if M.tabOnlineRect then
        local r = M.tabOnlineRect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            M.switchTab("online")
            return true
        end
    end
    if M.tabAdRect then
        local r = M.tabAdRect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            M.switchTab("ad")
            return true
        end
    end
    if M.tabLvlRect then
        local r = M.tabLvlRect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            M.switchTab("level")
            return true
        end
    end

    -- 在线标签的交互
    if M.activeTab == "online" then
        local OM = OnlineMonitor
        if OM.prevDateBtnRect then
            local r = OM.prevDateBtnRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                OM.switchDate(-1)
                return true
            end
        end
        if OM.nextDateBtnRect then
            local r = OM.nextDateBtnRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                local isToday = (OM.panelDate == os.date("%Y%m%d"))
                if not isToday then
                    OM.switchDate(1)
                end
                return true
            end
        end
        -- 面板内拖动
        if M.panelRect then
            local r = M.panelRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                OM.dragging = true
                OM.dragStartY = my
                OM.dragStartScroll = OM.scrollY
                OM.dragMoved = false
                return true
            end
        end
    end

    -- 广告标签的交互
    if M.activeTab == "ad" then
        if M.adPrevDateBtnRect then
            local r = M.adPrevDateBtnRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                M.switchAdDate(-1)
                return true
            end
        end
        if M.adNextDateBtnRect then
            local r = M.adNextDateBtnRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                local isToday = (M.adPanelDate == os.date("%Y%m%d"))
                if not isToday then
                    M.switchAdDate(1)
                end
                return true
            end
        end
        -- 面板内拖动
        if M.panelRect then
            local r = M.panelRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                M.adDragging = true
                M.adDragStartY = my
                M.adDragStartScroll = M.adScrollY
                M.adDragMoved = false
                return true
            end
        end
    end

    -- 等级标签的交互
    if M.activeTab == "level" then
        if M.lvlPrevDateBtnRect then
            local r = M.lvlPrevDateBtnRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                M.switchLvlDate(-1)
                return true
            end
        end
        if M.lvlNextDateBtnRect then
            local r = M.lvlNextDateBtnRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                local isToday = (M.lvlPanelDate == os.date("%Y%m%d"))
                if not isToday then
                    M.switchLvlDate(1)
                end
                return true
            end
        end
        -- 面板内拖动
        if M.panelRect then
            local r = M.panelRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                M.lvlDragging = true
                M.lvlDragStartY = my
                M.lvlDragStartScroll = M.lvlScrollY
                M.lvlDragMoved = false
                return true
            end
        end
    end

    return false
end

function M.handleDrag(my)
    if M.activeTab == "online" then
        OnlineMonitor.handleDrag(my)
        return
    end
    if M.activeTab == "ad" then
        if not M.adDragging then return end
        local delta = M.adDragStartY - my
        if math.abs(delta) > 2 then M.adDragMoved = true end
        local adContentH = #M.adRankData * 30
        local clipH = M.adListH > 0 and M.adListH or 200
        local scrollMax = math.max(0, adContentH - clipH)
        M.adScrollY = math.max(0, math.min(scrollMax, M.adDragStartScroll + delta))
        return
    end
    if M.activeTab == "level" then
        if not M.lvlDragging then return end
        local delta = M.lvlDragStartY - my
        if math.abs(delta) > 2 then M.lvlDragMoved = true end
        local lvlContentH = #M.lvlRankData * 30
        local clipH = M.lvlListH > 0 and M.lvlListH or 200
        local scrollMax = math.max(0, lvlContentH - clipH)
        M.lvlScrollY = math.max(0, math.min(scrollMax, M.lvlDragStartScroll + delta))
    end
end

function M.handleRelease()
    if M.activeTab == "online" then
        OnlineMonitor.handleRelease()
    end
    if M.adDragging then M.adDragging = false end
    if M.lvlDragging then M.lvlDragging = false end
end

function M.handleWheel(wheelDelta)
    if not M.showPanel then return false end
    if not M.panelRect then return false end

    local mx = GS.hoverX
    local my = GS.hoverY
    local r = M.panelRect
    if mx < r.x or mx > r.x + r.w or my < r.y or my > r.y + r.h then
        return false
    end

    local itemH = 28
    local gp = 2
    if M.activeTab == "online" then
        local OM = OnlineMonitor
        local contentTotalH = #OM.rankData * (itemH + gp)
        local clipH = r.h - 100
        local scrollMax = math.max(0, contentTotalH - clipH)
        OM.scrollY = math.max(0, math.min(scrollMax, OM.scrollY - wheelDelta * 30))
    elseif M.activeTab == "ad" then
        local adContentH = #M.adRankData * (itemH + gp)
        local clipH = M.adListH > 0 and M.adListH or 200
        local scrollMax = math.max(0, adContentH - clipH)
        M.adScrollY = math.max(0, math.min(scrollMax, M.adScrollY - wheelDelta * 30))
    else  -- "level"
        local lvlContentH = #M.lvlRankData * (itemH + gp)
        local clipH = M.lvlListH > 0 and M.lvlListH or 200
        local scrollMax = math.max(0, lvlContentH - clipH)
        M.lvlScrollY = math.max(0, math.min(scrollMax, M.lvlScrollY - wheelDelta * 30))
    end
    return true
end

return M
