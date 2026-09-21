local Config = require("diggin.Config")

local LeaderboardRenderer = {}

local function clippedName(value, limit)
    value = tostring(value or "未知玩家")
    if not utf8.len(value) then return "未知玩家" end
    local finish = utf8.offset(value, (limit or 10) + 1)
    return finish and value:sub(1, finish - 1) .. "…" or value
end

local function rowByDelta(view, delta)
    for _, row in ipairs(view.rows or {}) do
        if row.rank - view.rank == delta then return row end
    end
    return nil
end

local function drawRow(renderer, view, delta, label, y)
    local row = rowByDelta(view, delta)
    local isMe = delta == 0
    local border = isMe and Config.Palette.cyan or { 94, 83, 109, 255 }
    renderer:FillRect(62, y, 356, 30, isMe and { 31, 62, 72, 245 } or { 36, 30, 44, 238 })
    renderer:StrokeRect(62, y, 356, 30, border, isMe and 2 or 1)
    renderer:Text(label, 72, y + 15, 8, isMe and Config.Palette.cyan or Config.Palette.creamDim,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    if not row then
        local emptyText = delta < 0 and "已经是榜首" or (delta > 0 and "暂时没有下一名" or "本人的榜单数据正在同步")
        renderer:Text(emptyText, 156, y + 15, 8, Config.Palette.creamDim,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        return
    end
    renderer:Text("#" .. tostring(row.rank), 126, y + 15, 10,
        isMe and Config.Palette.gold or Config.Palette.cream, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    renderer:Text(clippedName(row.nickname, 12), 166, y + 15, 8, Config.Palette.cream,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    renderer:Text("最深第 " .. tostring(row.floor or 0) .. " 层", 400, y + 15, 9,
        isMe and Config.Palette.cyan or Config.Palette.green, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
end

local function errorText(errorCode)
    if errorCode == "not_logged_in" then return "尚未取得 TapTap 登录状态" end
    if errorCode == "timeout" then return "云端连接超时，本机纪录不会丢失" end
    if errorCode == "cloud_unavailable" then return "当前环境不支持云端排行榜" end
    if errorCode == "empty_rank_list" then return "排行榜已连接，但暂未返回名次数据" end
    return "排行榜读取失败：" .. tostring(errorCode or "未知错误")
end

function LeaderboardRenderer.Draw(renderer, app)
    local view = app.abyssLeaderboard
    renderer.leaderboardButtons = {}
    renderer:DrawStarfield()
    renderer:FillRect(0, 0, Config.DESIGN_WIDTH, 28, { 26, 21, 35, 248 })
    renderer:DrawButton("leaderboard_back", "返回", 7, 4, 56, 20, true,
        app.leaderboardHover == "leaderboard_back", renderer.leaderboardButtons)
    renderer:Text("S" .. tostring(view.season or 2) .. " 深渊深度榜", 76, 7, 12, Config.Palette.cream)
    renderer:Text("单局最深层 · 分赛季", 214, 14, 7, Config.Palette.cyan,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    renderer:DrawButton("leaderboard_refresh", view.status == "loading" and "连接中" or "刷新",
        410, 4, 62, 20, view.status ~= "loading",
        app.leaderboardHover == "leaderboard_refresh", renderer.leaderboardButtons)

    renderer:DrawPanel(46, 43, 388, 184, view.viewKind == "honor" and "荣耀榜" or "我的上下各五名")
    renderer:DrawButton("leaderboard_season", view.season == 1 and "进入S2" or "查看S1", 62, 69, 70, 20, true,
        false, renderer.leaderboardButtons)
    renderer:DrawButton("leaderboard_honor", view.viewKind == "honor" and "附近名次" or "金银铜榜", 140, 69, 70, 20, true,
        false, renderer.leaderboardButtons)
    renderer:DrawButton("leaderboard_endless", "无尽深度", 260, 48, 72, 18, true,
        view.boardMode == "endless", renderer.leaderboardButtons)
    if view.hardcoreUnlocked then
        renderer:DrawButton("leaderboard_hardcore", "硬核深度", 338, 48, 72, 18, true,
            view.boardMode == "hardcore", renderer.leaderboardButtons)
    end
    if view.status == "loading" or view.status == "idle" then
        renderer:Text("正在连接全服排行榜…", 240, 139, 12, Config.Palette.cyan,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    elseif view.status == "waiting_login" then
        renderer:Text("正在等待 TapTap 账号与云服务…", 240, 130, 11, Config.Palette.cyan,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        renderer:Text("会自动重试；也可以返回后重新进入", 240, 151, 8, Config.Palette.creamDim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    elseif view.status == "error" then
        renderer:Text(errorText(view.error), 240, 132, 10, Config.Palette.red,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local localText = (view.localBestFloor or 0) > 0
            and ("本机最佳：第 " .. tostring(view.localBestFloor) .. " 层 · 登录后会自动补交")
            or "登录 TapTap 后点击右上角“刷新”重试"
        renderer:Text(localText, 240, 153, 8, Config.Palette.creamDim,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    elseif view.status == "unranked" then
        renderer:Text("你还没有深渊闯塔纪录", 240, 127, 12, Config.Palette.gold,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local unrankedText = (view.localBestFloor or 0) > 0
            and ("本机最佳第 " .. tostring(view.localBestFloor) .. " 层正在补交，请稍后刷新")
            or "完成或安全撤离一局后，最高层会自动提交"
        renderer:Text(unrankedText, 240, 150, 8,
            Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    else
        if view.viewKind == "honor" then
            local medals = { "金 · 冠军", "银 · 亚军", "铜 · 季军" }
            local colors = { Config.Palette.gold, Config.Palette.cream, Config.Palette.orange }
            for index = 1, 3 do
                local row = view.rows[index]
                local y = 105 + (index - 1) * 34
                renderer:Text(medals[index], 66, y, 10, colors[index])
                renderer:Text(row and row.nickname or "虚位以待", 146, y, 8, Config.Palette.cream)
                renderer:Text(row and (tostring(row.floor) .. "层") or "—", 400, y, 10, colors[index], NVG_ALIGN_RIGHT)
            end
            local honors = require("diggin.SeasonHonors")
            for rank = 1, 3 do
                if renderer.DrawSheetCell then
                    renderer:DrawSheetCell(honors.skinAtlas, 3, 2, rank, 360, 91 + (rank - 1) * 34, 22, 29, 1)
                end
            end
            renderer:Text(view.season == 1 and (honors.sealed and "S1已核定 · 获奖账号进入深渊自动穿戴"
                or "S1历史榜仍可能变化 · 待核定名单发奖") or "S2进行中 · 当前名次不是最终获奖名单",
                240, 211, 7, Config.Palette.creamDim, NVG_ALIGN_CENTER)
        else
            local mine = rowByDelta(view, 0)
            local mineText = mine and ("我：第" .. mine.rank .. "名 · 最深" .. mine.floor .. "层")
                or (view.rank and ("我：第" .. view.rank .. "名 · 最深" .. tostring(view.score or 0) .. "层"))
                or "本人名次同步中"
            renderer:Text(mineText,
                313, 80, 9, Config.Palette.cyan, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            for side = 1, 2 do
                local x = side == 1 and 60 or 245
                renderer:Text(side == 1 and "上方五名" or "下方五名", x, 98, 8, Config.Palette.creamDim)
                for index = 1, 5 do
                    local delta = side == 1 and index - 6 or index
                    local row = rowByDelta(view, delta)
                    local y = 116 + (index - 1) * 21
                    renderer:FillRect(x, y, 173, 19, { 36, 30, 44, 238 })
                    local name = row and ("#" .. row.rank .. " " .. clippedName(row.nickname or "矿工", 8)) or "暂无名次"
                    -- Clip long account names before the independent depth column.
                    name = clippedName(name, 10)
                    renderer:Text(name, x + 3, y + 5, 7, Config.Palette.cream)
                    renderer:Text(row and (row.floor .. "层") or "—", x + 169, y + 5, 8,
                        Config.Palette.green, NVG_ALIGN_RIGHT)
                end
            end
        end
    end
    local modeText = view.boardMode == "hardcore" and "硬核深度榜" or "无尽深度榜"
    renderer:Text(modeText .. "只记录最深层；不累计局数、金币或本局得分", 240, 246, 8,
        Config.Palette.creamDim, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
end

return LeaderboardRenderer
