local Config = require("diggin.Config")
local Util = require("diggin.Util")
local SkillText = require("diggin.SkillText")

local ProgressionController = {}

function ProgressionController.BuySelectedSkill(app)
    local node = app.selectedSkill and app.state.nodeById[app.selectedSkill]
    local previousLevel = node and app.state:GetLevel(node.id) or 0
    if not node then
        app.audio:PlaySfx(Config.Audio.deny, 0.7)
        return false
    end
    local bought, worldTreeAwakenedNow = app.state:Buy(node)
    if not bought then
        app.audio:PlaySfx(Config.Audio.deny, 0.7)
        return false
    end
    app.audio:PlaySfx(Config.Audio.click, 0.7)
    if worldTreeAwakenedNow then
        app:ShowToast("四个终极技能齐聚 · 世界树已苏醒", Config.Palette.gold, 4)
    elseif node.is_artefact then
        local message = previousLevel == 0
            and ("天赋遗物已镶入：" .. SkillText.GetName(node) .. " · 效果已生效")
            or ("天赋遗物已升级：" .. SkillText.GetName(node) .. " Lv." .. tostring(app.state:GetLevel(node.id)))
        app:ShowToast(message, Config.Palette.green, 3)
    end
    return true
end

function ProgressionController.HandleRelicAction(app, id)
    if not id then return end
    if id == "back" then app:OpenMenu(); return end
    if id == "play" then app:StartRun(false); return end
    if id == "relic_tab_standard" then
        app.relicTab = "standard"
        return
    end
    if id == "relic_tab_talent" then
        app.relicTab = "talent"
        return
    end
    if id:sub(1, 14) == "talent_select:" then
        app.selectedArtefact = id:sub(15)
        app.audio:PlaySfx(Config.Audio.click, 0.55)
        return
    end
    if id == "talent_action" then
        local node = app.state.nodeById[app.selectedArtefact]
        if node and node.is_artefact and app.state:IsArtefactDiscovered(node.id) then
            app:OpenArtefact(node.id)
        else
            app:ShowToast("该天赋遗物尚未从宝箱发现", Config.Palette.red, 2.5)
            app.audio:PlaySfx(Config.Audio.deny, 0.7)
        end
        return
    end
    if id == "relic_prev" or id == "relic_next" then
        app.relicPage = Util.Clamp(app.relicPage + (id == "relic_prev" and -1 or 1), 1, 5)
        local firstMap = (app.relicPage - 1) * 2 + 1
        local relics = app.state.relicData.byMap[firstMap] or {}
        if relics[1] then app.selectedRelic = relics[1].id end
        return
    end
    if id:sub(1, 13) == "relic_select:" then
        app.selectedRelic = id:sub(14)
        app.audio:PlaySfx(Config.Audio.click, 0.55)
        return
    end
    if id:sub(1, 11) == "relic_slot:" then
        local slot = tonumber(id:sub(12))
        local relicId = slot and app.state.equippedRelics[slot]
        if relicId then
            local relic = app.state:GetRelic(relicId)
            app.state:ToggleRelicEquipped(relicId)
            app:ShowToast("已卸下：" .. (relic and relic.name or relicId), Config.Palette.creamDim)
        end
        return
    end
    if id ~= "relic_action" then return end
    local relic = app.state:GetRelic(app.selectedRelic)
    if not relic then return end
    if not app.state:IsRelicUnlocked(relic.id) then
        if not app.state:IsRelicMapAvailable(relic) then
            app:ShowToast("到达密度 " .. tostring(relic.map) .. " 后才能研究", Config.Palette.red)
        elseif app.state.seenRelics[relic.id] ~= true then
            app:ShowToast("先在密度 " .. tostring(relic.map) .. " 打开宝箱发现该遗物", Config.Palette.red, 3)
        elseif app.state:UnlockRelic(relic.id) then
            app:ShowToast("遗物解锁并装备：" .. relic.name, Config.Palette.gold, 3)
            app.audio:PlaySfx(Config.Audio.pickup, 0.8, 1.1)
        else
            app:ShowToast("遗物核心不足：需要 " .. tostring(relic.cost), Config.Palette.red)
            app.audio:PlaySfx(Config.Audio.deny, 0.7)
        end
        return
    end
    local changed, status = app.state:ToggleRelicEquipped(relic.id)
    if changed then
        app:ShowToast((status == "equipped" and "已装备：" or "已卸下：") .. relic.name,
            status == "equipped" and Config.Palette.gold or Config.Palette.creamDim)
        app.audio:PlaySfx(Config.Audio.click, 0.7)
    elseif status == "full" then
        app:ShowToast("4 个装备栏已满，请先卸下一件", Config.Palette.red)
        app.audio:PlaySfx(Config.Audio.deny, 0.7)
    end
end

return ProgressionController
