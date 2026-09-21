local Config = require("diggin.Config")
local Cosmetics = require("diggin.Cosmetics")
local Hub = { title = "S2·裂界新生" }

function Hub.Open(app, tab)
    app:OpenMenu()
    app.mode = "season_hub"
    app.seasonTab = tab or "notice"
    app.seasonSelected = nil
    app.renderer.seasonButtons = {}
end

function Hub.Pointer(app, x, y)
    if app.adPending then return end
    for id, box in pairs(app.renderer.seasonButtons or {}) do
        if box.enabled and x >= box.x and x <= box.x + box.w
            and y >= box.y and y <= box.y + box.h then
            if id == "back" then app:OpenMenu()
            elseif id == "notice" or id == "character" or id == "drill" then
                app.seasonTab, app.seasonSelected = id, nil
            elseif id == "default" then Cosmetics.Equip(app.state, app.seasonTab, nil)
            elseif id == "equip" then Cosmetics.Equip(app.state, app.seasonTab, app.seasonSelected)
            elseif Cosmetics.byId[id] then app.seasonSelected = id end
            -- Invalidate old hitboxes immediately when the view changes.
            app.renderer.seasonButtons = {}
            return
        end
    end
end

function Hub.Draw(r, app)
    r:DrawStarfield()
    r.seasonButtons = {}
    local buttons = r.seasonButtons
    r:Text(Hub.title, 14, 10, 14, Config.Palette.cyan)
    for index, tab in ipairs({ { "notice", "赛季公告" }, { "character", "人物时装" }, { "drill", "钻头外观" } }) do
        r:DrawButton(tab[1], tab[2], 12 + (index - 1) * 113, 33, 106, 24,
            true, app.seasonTab == tab[1], buttons)
    end
    r:DrawButton("back", "返回", 388, 33, 80, 24, true, false, buttons)
    if app.seasonTab == "notice" then
        r:DrawPanel(12, 65, 456, 194, "深渊第二赛季 · 单机更新")
        local lines = {
            "S2·裂界新生：无尽与硬核开启新榜，S1历史记录保留。",
            "新增20件外观：10套人物、10款钻头，两个部位独立搭配。",
            "四档稀有度：稀有 / 史诗 / 传说 / 神话，外观不附带属性。",
            "深渊抵达10层且挑战满3分钟，结算有0.5%概率得新时装。",
            "商店停留不计挑战时间；每局仅抽一次，不重复获得旧款。",
            "弹片伤害降低25%，限制重复命中；商店暂停计时收益。",
            "第一赛季两榜前三奖励独立核验，不加入随机时装池。",
            "点击主菜单“S2更新公告”可再次查看；人物/钻头页可预览。",
        }
        for i, line in ipairs(lines) do r:Text(line, 22, 91 + (i - 1) * 20, 8, Config.Palette.cream) end
        return
    end
    local profile = Cosmetics.Normalize(app.state.cosmetics)
    local offset = app.seasonTab == "character" and 0 or 10
    for index = 1, 10 do
        local item = Cosmetics.items[offset + index]
        local x, y = 12 + ((index - 1) % 5) * 92, 65 + math.floor((index - 1) / 5) * 68
        local selected = app.seasonSelected == item.id
        local rarity = Cosmetics.rarity[item.rarity]
        r:FillRect(x, y, 88, 64, Config.Palette.inkSoft)
        r:StrokeRect(x, y, 88, 64, selected and Config.Palette.cream or rarity.color, selected and 2 or 1)
        Cosmetics.Draw(r, item, x + 25, y + 2, 38, 38, 1)
        r:Text(item.name, x + 44, y + 42, 7, rarity.color, NVG_ALIGN_CENTER)
        local status = profile.equipped[item.slot] == item.id and "已装备"
            or (profile.owned[item.id] and "已拥有" or "未拥有·可预览")
        r:Text(status, x + 44, y + 53, 6, Config.Palette.creamDim, NVG_ALIGN_CENTER)
        buttons[item.id] = { x = x, y = y, w = 88, h = 64, enabled = true }
    end
    local item = Cosmetics.byId[app.seasonSelected]
    r:Text(item and (item.name .. " · " .. Cosmetics.rarity[item.rarity].name .. " · "
        .. Cosmetics.rarity[item.rarity].motion .. " · 无属性")
        or "选择外观查看稀有度；人物与钻头独立装备", 14, 210, 8, Config.Palette.cream)
    r:DrawButton("default", "恢复默认", 12, 229, 106, 27, true, false, buttons)
    r:DrawButton("equip", "装备选中外观", 126, 229, 132, 27,
        item ~= nil and profile.owned[item.id] == true, false, buttons)
    local odds = "深渊10层+3分钟 · 结算掉率0.5%"
    if item and not profile.owned[item.id] then
        local pool, total = Cosmetics.GetDropPool(app.state)
        for _, row in ipairs(pool) do
            if row.item.id == item.id then
                odds = string.format("此款当前每次合格结算概率 %.5f%%", 100 * Cosmetics.dropChance * row.weight / total)
            end
        end
    end
    r:Text(odds, 272, 239, 6, Config.Palette.creamDim)
end

return Hub
