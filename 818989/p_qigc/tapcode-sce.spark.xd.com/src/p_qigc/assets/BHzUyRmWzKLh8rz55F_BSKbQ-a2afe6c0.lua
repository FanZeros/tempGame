-- ====================================================================
-- OnlineMonitor.lua — 在线监测模块
-- 功能：追踪玩家每日在线时长，上报云排行榜，管理员可查看排行和在线状态
-- ====================================================================
local GS = require("GameState")
local M = {}

-- ── 常量 ──
local REPORT_INTERVAL = 60       -- 每60秒上报一次在线时长
local HEARTBEAT_INTERVAL = 30    -- 每30秒更新一次心跳时间戳
local ONLINE_THRESHOLD = 120     -- 心跳超过120秒视为离线
local RANK_PAGE_SIZE = 1000      -- 排行榜单次请求条数（拉取全部玩家）
local NICKNAME_BATCH_SIZE = 200  -- GetUserNickname 每批最多查询数量

-- ── 分批查询昵称（绕过单次请求数量上限）──
-- onDone(map)：map[userId] = nickname 字符串
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
                        -- userId 可能是浮点数（如 1576069892.0），统一转为整数字符串再存 map
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

-- ── 内部状态 ──
M.lastReportTime = 0             -- 上次上报时的 os.time()
M.reportTimer = 0                -- 上报计时器
M.heartbeatTimer = 0             -- 心跳计时器
M.todayKey = ""                  -- 当前日期 key: "online_20260330"
M.todayDate = ""                 -- 当前日期 "YYYYMMDD"
M.initialized = false

-- ── 面板状态 ──
M.showPanel = false
M.panelDate = ""                 -- 当前查看的日期 "YYYYMMDD"
M.panelDateDisplay = ""          -- 显示用 "2026-03-30"
M.rankData = {}                  -- 排行榜数据 { {userId, nickname, seconds, loginTs, isOnline}, ... }
M.rankLoading = false
M.rankLoaded = false
M.scrollY = 0
M.dragging = false
M.dragStartY = 0
M.dragStartScroll = 0
M.dragMoved = false
M.panelRect = nil
M.closeBtnRect = nil
M.prevDateBtnRect = nil
M.nextDateBtnRect = nil
M.adminNowTs = 0                 -- 管理员当前 os.time()（用于比对在线状态）

-- ── 初始化（游戏启动时调用一次） ──
function M.init()
    if M.initialized then return end
    if not clientCloud then return end

    M.lastReportTime = os.time()
    M.todayDate = os.date("%Y%m%d")
    M.todayKey = "online_" .. M.todayDate
    M.panelDate = M.todayDate
    M.panelDateDisplay = os.date("%Y-%m-%d")
    M.initialized = true

    -- 立刻上报一次心跳
    M._sendHeartbeat()
    -- 初次上报：增加0秒，建立排行榜记录
    clientCloud:Add(M.todayKey, 0)
end

-- ── 每帧更新（在 HandleUpdate 中调用） ──
function M.update(dt)
    if not M.initialized then
        M.init()
        if not M.initialized then return end
    end

    -- 检查跨天
    local newDate = os.date("%Y%m%d")
    if newDate ~= M.todayDate then
        -- 先把昨天剩余时间上报
        M._reportOnlineTime()
        M.todayDate = newDate
        M.todayKey = "online_" .. newDate
        M.lastReportTime = os.time()
        clientCloud:Add(M.todayKey, 0)  -- 建立新一天的记录
    end

    -- 定时上报在线时长（增量）
    M.reportTimer = M.reportTimer + dt
    if M.reportTimer >= REPORT_INTERVAL then
        M.reportTimer = 0
        M._reportOnlineTime()
    end

    -- 定时心跳
    M.heartbeatTimer = M.heartbeatTimer + dt
    if M.heartbeatTimer >= HEARTBEAT_INTERVAL then
        M.heartbeatTimer = 0
        M._sendHeartbeat()
    end
end

-- ── 上报在线时长增量到 iscores（使用 Add 累加） ──
function M._reportOnlineTime()
    local now = os.time()
    local delta = now - M.lastReportTime
    if delta <= 0 then return end
    M.lastReportTime = now

    clientCloud:Add(M.todayKey, delta, {
        error = function(code, reason)
            print("[OnlineMonitor] 上报在线时长失败:", code, reason)
        end
    })
end

-- ── 发送心跳时间戳（用 Set 存储，供管理员判断在线状态） ──
function M._sendHeartbeat()
    clientCloud:Set("login_ts", os.time(), {
        error = function(code, reason)
            print("[OnlineMonitor] 心跳上报失败:", code, reason)
        end
    })
    -- 同步上报玩家等级和职业（供等级排行榜监测使用）
    local level = (GS.player and GS.player.level) or 1
    clientCloud:Set("player_level", level, {
        error = function(code, reason)
            print("[OnlineMonitor] 等级上报失败:", code, reason)
        end
    })
    local classId = GS.currentClass or "warrior"
    clientCloud:Set("player_class", classId, {
        error = function(code, reason)
            print("[OnlineMonitor] 职业上报失败:", code, reason)
        end
    })
end

-- ── 打开面板 ──
function M.openPanel()
    M.showPanel = true
    M.panelDate = os.date("%Y%m%d")
    M.panelDateDisplay = os.date("%Y-%m-%d")
    M.scrollY = 0
    M.rankData = {}
    M.rankLoaded = false
    M.adminNowTs = os.time()
    M._fetchRankData()
end

-- ── 关闭面板 ──
function M.closePanel()
    M.showPanel = false
    M.rankData = {}
    M.rankLoaded = false
    M.rankLoading = false
end

-- ── 切换日期（delta: -1 前一天, +1 后一天） ──
function M.switchDate(delta)
    -- 解析当前 panelDate
    local y = tonumber(M.panelDate:sub(1, 4))
    local m = tonumber(M.panelDate:sub(5, 6))
    local d = tonumber(M.panelDate:sub(7, 8))
    local t = os.time({ year = y, month = m, day = d, hour = 12 })
    t = t + delta * 86400
    local nd = os.date("*t", t)
    M.panelDate = string.format("%04d%02d%02d", nd.year, nd.month, nd.day)
    M.panelDateDisplay = string.format("%04d-%02d-%02d", nd.year, nd.month, nd.day)

    -- 不允许查看未来日期
    local today = os.date("%Y%m%d")
    if M.panelDate > today then
        M.panelDate = today
        M.panelDateDisplay = os.date("%Y-%m-%d")
        return
    end

    M.scrollY = 0
    M.rankData = {}
    M.rankLoaded = false
    M.adminNowTs = os.time()
    M._fetchRankData()
end

-- ── 拉取排行榜数据 ──
function M._fetchRankData()
    if M.rankLoading then return end
    M.rankLoading = true
    M.rankLoaded = false

    local key = "online_" .. M.panelDate

    clientCloud:GetRankList(key, 0, RANK_PAGE_SIZE, {
        ok = function(rankList)
            M.rankLoading = false
            M.rankLoaded = true
            M.adminNowTs = os.time()

            -- 收集 userId 列表
            local entries = {}
            local userIds = {}
            for i, item in ipairs(rankList) do
                local seconds = item.iscore[key] or 0
                local loginTs = (item.score and item.score.login_ts) or 0
                if type(loginTs) == "string" then loginTs = tonumber(loginTs) or 0 end
                table.insert(entries, {
                    rank = i,
                    userId = item.userId,
                    nickname = "",
                    seconds = seconds,
                    loginTs = loginTs,
                    isOnline = false,
                })
                table.insert(userIds, item.userId)
            end

            if #userIds == 0 then
                M.rankData = entries
                return
            end

            -- 分批查询昵称（每批200，防止单次超限导致部分显示ID:数字）
            batchGetNicknames(userIds, function(map)
                for _, entry in ipairs(entries) do
                    entry.nickname = map[tostring(entry.userId)] or ("ID:" .. tostring(entry.userId))
                    -- 判断在线状态：心跳时间戳在阈值内
                    if entry.loginTs > 0 and (M.adminNowTs - entry.loginTs) < ONLINE_THRESHOLD then
                        entry.isOnline = true
                    end
                end
                M._sortEntries(entries)
                M.rankData = entries
            end)
        end,
        error = function(code, reason)
            M.rankLoading = false
            M.rankLoaded = true
            M.rankData = {}
            print("[OnlineMonitor] 拉取排行榜失败:", code, reason)
        end
    }, "login_ts")
end

-- ── 排序：在线优先，各组内按时长降序 ──
function M._sortEntries(entries)
    table.sort(entries, function(a, b)
        if a.isOnline ~= b.isOnline then
            return a.isOnline  -- true 排前面
        end
        return a.seconds > b.seconds  -- 同组按时长降序
    end)
    -- 重新编号
    for i, entry in ipairs(entries) do
        entry.rank = i
    end
end

-- ── 格式化秒数为可读时间 ──
function M.formatTime(seconds)
    if seconds < 60 then
        return seconds .. "秒"
    elseif seconds < 3600 then
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return string.format("%d分%02d秒", m, s)
    else
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        return string.format("%d时%02d分", h, m)
    end
end

-- ── 绘制面板（在 NanoVGRender 中调用） ──
function M.drawPanel(vg)
    if not M.showPanel then return end

    local sw, sh = GS.SCREEN_W, GS.SCREEN_H
    local pw = math.min(280, sw - 20)
    local ph = math.min(360, sh - 40)
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
    nvgFillColor(vg, nvgRGBA(20, 25, 45, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 140, 220, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")

    -- ── 标题栏 ──
    local titleH = 30
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, 255))
    nvgText(vg, px + pw / 2, py + titleH / 2, "在线监测", nil)

    -- 关闭按钮
    local closeBtnSize = 20
    local closeBtnX = px + pw - closeBtnSize - 6
    local closeBtnY = py + 5
    M.closeBtnRect = { x = closeBtnX, y = closeBtnY, w = closeBtnSize, h = closeBtnSize }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnSize, closeBtnSize, 3)
    nvgFillColor(vg, nvgRGBA(150, 50, 50, 200))
    nvgFill(vg)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, closeBtnX + closeBtnSize / 2, closeBtnY + closeBtnSize / 2, "X", nil)

    -- ── 日期切换栏 ──
    local dateBarY = py + titleH
    local dateBarH = 26
    local arrowW = 30

    -- 左箭头
    local prevX = px + 8
    M.prevDateBtnRect = { x = prevX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    nvgBeginPath(vg)
    nvgRoundedRect(vg, prevX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, nvgRGBA(60, 70, 100, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 200, 255, 255))
    nvgText(vg, prevX + arrowW / 2, dateBarY + dateBarH / 2, "<", nil)

    -- 右箭头
    local nextX = px + pw - arrowW - 8
    M.nextDateBtnRect = { x = nextX, y = dateBarY + 2, w = arrowW, h = dateBarH - 4 }
    -- 如果是今天，右箭头变灰
    local isToday = (M.panelDate == os.date("%Y%m%d"))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, nextX, dateBarY + 2, arrowW, dateBarH - 4, 3)
    nvgFillColor(vg, isToday and nvgRGBA(40, 40, 50, 150) or nvgRGBA(60, 70, 100, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isToday and nvgRGBA(100, 100, 120, 150) or nvgRGBA(180, 200, 255, 255))
    nvgText(vg, nextX + arrowW / 2, dateBarY + dateBarH / 2, ">", nil)

    -- 日期文字
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
    local dateLabel = M.panelDateDisplay
    if isToday then dateLabel = dateLabel .. " (今天)" end
    nvgText(vg, px + pw / 2, dateBarY + dateBarH / 2, dateLabel, nil)

    -- ── 列表区域 ──
    local listY = dateBarY + dateBarH + 4
    local listH = ph - (listY - py) - 6
    local pad = 6
    local itemH = 28
    local gap = 2

    local clipX = px + pad
    local clipY = listY
    local clipW = pw - pad * 2
    local clipH = listH

    -- 加载中提示
    if M.rankLoading then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 170, 220, 200))
        nvgText(vg, px + pw / 2, listY + listH / 2, "加载中...", nil)
        return
    end

    if M.rankLoaded and #M.rankData == 0 then
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 150, 170, 180))
        nvgText(vg, px + pw / 2, listY + listH / 2, "暂无数据", nil)
        return
    end

    -- 计算内容高度和滚动
    local totalItems = #M.rankData
    local contentH = totalItems * (itemH + gap)
    local scrollMax = math.max(0, contentH - clipH)
    M.scrollY = math.max(0, math.min(M.scrollY, scrollMax))

    nvgSave(vg)
    nvgScissor(vg, clipX, clipY, clipW, clipH)

    local startY = clipY - M.scrollY
    local myUserId = clientCloud and clientCloud.userId or 0

    for i, entry in ipairs(M.rankData) do
        local iy = startY + (i - 1) * (itemH + gap)

        if iy + itemH >= clipY and iy <= clipY + clipH then
            local isMe = (entry.userId == myUserId)

            -- 行背景
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
                    {255, 215, 0},   -- 金
                    {192, 192, 192}, -- 银
                    {205, 127, 50},  -- 铜
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
            nvgText(vg, clipX + clipW - 4, midY, M.formatTime(entry.seconds), nil)
        end
    end

    -- ── 滚动条 ──
    if scrollMax > 0 then
        local barW = 3
        local barX = clipX + clipW - barW - 1
        local barAreaH = clipH - 4
        local thumbH = math.max(12, barAreaH * clipH / contentH)
        local thumbY = clipY + 2 + (barAreaH - thumbH) * (M.scrollY / scrollMax)
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

    -- ── 底部统计 ──
    local onlineCount = 0
    for _, entry in ipairs(M.rankData) do
        if entry.isOnline then onlineCount = onlineCount + 1 end
    end
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(100, 180, 120, 200))
    nvgText(vg, px + 10, py + ph - 10, "当前在线: " .. onlineCount .. " 人", nil)

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 150, 180, 180))
    nvgText(vg, px + pw - 10, py + ph - 10, "共 " .. #M.rankData .. " 人", nil)
end

-- ── 处理点击（返回 true 表示事件已消费） ──
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

    -- 左箭头（前一天）
    if M.prevDateBtnRect then
        local r = M.prevDateBtnRect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            M.switchDate(-1)
            return true
        end
    end

    -- 右箭头（后一天）
    if M.nextDateBtnRect then
        local r = M.nextDateBtnRect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            local isToday = (M.panelDate == os.date("%Y%m%d"))
            if not isToday then
                M.switchDate(1)
            end
            return true
        end
    end

    -- 面板内开始拖动
    if M.panelRect then
        local r = M.panelRect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            M.dragging = true
            M.dragStartY = my
            M.dragStartScroll = M.scrollY
            M.dragMoved = false
            return true
        end
    end

    return false
end

-- ── 处理拖动（鼠标移动时调用） ──
function M.handleDrag(my)
    if not M.dragging then return end
    local delta = M.dragStartY - my
    if math.abs(delta) > 2 then
        M.dragMoved = true
    end

    local totalItems = #M.rankData
    local itemH = 28
    local gap = 2
    local contentH = totalItems * (itemH + gap)
    local clipH = M.panelRect and (M.panelRect.h - 66) or 200
    local scrollMax = math.max(0, contentH - clipH)
    M.scrollY = math.max(0, math.min(scrollMax, M.dragStartScroll + delta))
end

-- ── 处理释放（鼠标松开时调用） ──
function M.handleRelease()
    if not M.dragging then return false end
    M.dragging = false
    return true
end

-- ── 滚轮滚动 ──
function M.handleWheel(wheelDelta)
    if not M.showPanel then return false end
    if not M.panelRect then return false end

    -- 检查鼠标是否在面板内
    local mx = GS.hoverX
    local my = GS.hoverY
    local r = M.panelRect
    if mx < r.x or mx > r.x + r.w or my < r.y or my > r.y + r.h then
        return false
    end

    local totalItems = #M.rankData
    local itemH = 28
    local gap = 2
    local contentH = totalItems * (itemH + gap)
    local clipH = (r.h - 66)
    local scrollMax = math.max(0, contentH - clipH)
    M.scrollY = math.max(0, math.min(scrollMax, M.scrollY - wheelDelta * 30))
    return true
end

return M
