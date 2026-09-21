local Config = require("diggin.Config")
local Util = require("diggin.Util")
local Stats = require("diggin.RunCombatStats")
local Tools = require("diggin.AbyssRunTools")
local Passives = require("diggin.AbyssPassives")
local Synergies = require("diggin.AbyssSynergies")
local Report = {}
function Report.Draw(r, app)
    r:FillRect(0, 0, 480, 270, { 13, 9, 23, 250 })
    r:DrawPanel(16, 12, 448, 246, "本局战报 · 实际输出与搭配")
    local ledger = app.combatStats or Stats.New()
    r:Text("破矿 " .. Util.FormatNumber(ledger.ore) .. "  对怪 " .. Util.FormatNumber(ledger.enemy)
        .. "  回油 " .. Util.FormatNumber(ledger.fuel), 30, 42, 8, Config.Palette.gold)
    local rows = Stats.Rows(ledger)
    local pages = math.max(1, math.ceil(#rows / 5))
    app.combatReportPage = math.min(pages + 1, math.max(1, app.combatReportPage or 1))
    local page = app.combatReportPage
    if page <= pages then
        r:Text("来源                         矿石伤害       怪物伤害       回油", 30, 65, 7, Config.Palette.cyan)
        for i = 1, 5 do
            local row = rows[(page - 1) * 5 + i]
            if row then
                local definition = Tools.GetDefinition(row.source)
                local names = { drill = "钻头", tree_drill = "世界树钻技", laser = "激光", other = "环境/其他", inscription_blast = "铭刻次级爆破" }
                local y = 86 + (i - 1) * 22
                r:Text(definition and definition.name or names[row.source] or "其他技能", 30, y, 8, Config.Palette.cream)
                r:Text(Util.FormatNumber(row.ore), 230, y, 8, Config.Palette.creamDim)
                r:Text(Util.FormatNumber(row.enemy), 305, y, 8, Config.Palette.creamDim)
                r:Text(Util.FormatNumber(row.fuel), 392, y, 8, Config.Palette.green)
            end
        end
        r:Text("只计实际损失，不含溢出伤害；下一页可查看本局搭配。", 30, 202, 7, Config.Palette.creamDim)
    else
        local abyss = app.abyss or {}
        local active, passive = {}, {}
        for _, d in ipairs(Tools.DEFINITIONS) do
            local level = Tools.GetLevel(abyss, d.key)
            if level > 0 then active[#active + 1] = d.name .. " Lv." .. level end
        end
        for _, recipe in ipairs(Tools.EVOLUTION_RECIPES) do
            if (abyss.runCapstones or {})[recipe.capstone] then active[#active + 1] = "专武：" .. recipe.name end
        end
        for _, d in ipairs(Passives.DEFINITIONS) do
            local level = Passives.GetLevel(abyss, d.id)
            if level > 0 then passive[#passive + 1] = d.name .. " Lv." .. level end
        end
        r:Text("主动道具与专武", 30, 64, 8, Config.Palette.cyan)
        r:TextBox(#active > 0 and table.concat(active, " / ") or "本局未选择深渊道具", 30, 78, 410, 7, Config.Palette.cream)
        r:Text("被动", 30, 124, 8, Config.Palette.cyan)
        r:TextBox(#passive > 0 and table.concat(passive, " / ") or "无", 30, 138, 410, 7, Config.Palette.cream)
        local links = Synergies.Active(abyss)
        r:Text("已激活联动", 30, 173, 8, Config.Palette.gold)
        r:TextBox(#links > 0 and table.concat(links, " / ") or "无（对应被动需达到Lv.2）", 30, 187, 410, 7, Config.Palette.cream)
    end
    r:DrawButton("report_prev", "上一页", 30, 227, 100, 20, page > 1, false, r.endButtons)
    r:Text(page .. "/" .. (pages + 1), 164, 233, 8, Config.Palette.creamDim)
    r:DrawButton("report_next", "下一页", 210, 227, 100, 20, page < pages + 1, false, r.endButtons)
    r:DrawButton("report_close", "返回结算", 340, 227, 100, 20, true, false, r.endButtons)
end
return Report
