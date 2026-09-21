local Config = require("diggin.Config")
local Util = require("diggin.Util")
local AbyssLoot = require("diggin.AbyssLoot")

local DropController = {}

function DropController.QueueOreDrop(app, ore, amount, x, y)
    if not ore or not amount or amount <= 0 then return false, false, 0 end
    if not Config.Ores[ore] then
        app.state:AddRunOre(ore, amount)
        return true, false, amount
    end
    local banked = ore == "Stardrop"
    local finalUnlockedNow = false
    if banked then
        local added
        added, finalUnlockedNow = app.state:AddRunOre(ore, amount)
        if not added or added <= 0 then return false, false, 0 end
        amount = added
    end
    app.oreDropEffectCount = math.max(0, math.floor(tonumber(app.oreDropEffectCount) or 0))
    if app.oreDropEffectCount >= Config.MAX_ORE_DROP_EFFECTS then
        for index = #app.effects, 1, -1 do
            local effect = app.effects[index]
            if effect.kind == "ore_drop" and effect.ore == ore and effect.banked == banked then
                effect.units = effect.units + amount
                app.pendingOre[ore] = (app.pendingOre[ore] or 0) + amount
                return true, finalUnlockedNow, amount
            end
        end
        if not banked then app.state:AddRunOre(ore, amount) end
        return true, finalUnlockedNow, amount
    end
    local awayX, awayY = Util.Normalize(x - app.player.x, y - app.player.y)
    local angle = math.atan(awayY, awayX) + (math.random() - 0.5) * math.pi * 0.5
    local distance = 20 + math.random() * 20
    app.pendingOre[ore] = (app.pendingOre[ore] or 0) + amount
    app.oreDropEffectCount = app.oreDropEffectCount + 1
    app.effects[#app.effects + 1] = {
        kind = "ore_drop", ore = ore, units = amount, banked = banked, phase = "pop",
        x = x, y = y, startX = x, startY = y,
        popX = x + math.cos(angle) * distance,
        popY = y + math.sin(angle) * distance,
        elapsed = 0, duration = 0.2 + math.random() * 0.4,
    }
    return true, finalUnlockedNow, amount
end

function DropController.QueueArtefactDrop(app, artefactId, x, y)
    if not artefactId or app.pendingArtefacts[artefactId] then return end
    app.pendingArtefacts[artefactId] = true
    local angle = -math.pi * 0.5 + (math.random() - 0.5) * math.pi * 0.8
    local distance = 30 + math.random() * 20
    app.effects[#app.effects + 1] = {
        kind = "artefact_drop", artefactId = artefactId, phase = "pop",
        x = x, y = y, startX = x, startY = y,
        popX = x + math.cos(angle) * distance,
        popY = y + math.sin(angle) * distance,
        elapsed = 0, duration = 0.45,
    }
end

function DropController.QueueRelicDrop(app, relicId, x, y)
    local relic = app.state:GetRelic(relicId)
    if not relic or app.pendingRelics[relicId] then return end
    app.pendingRelics[relicId] = true
    local angle = -math.pi * 0.5 + (math.random() - 0.5) * math.pi * 0.7
    local distance = 34 + math.random() * 18
    app.effects[#app.effects + 1] = {
        kind = "relic_drop", relicId = relicId, phase = "pop",
        x = x, y = y, startX = x, startY = y,
        popX = x + math.cos(angle) * distance,
        popY = y + math.sin(angle) * distance,
        elapsed = 0, duration = 0.48,
    }
end

function DropController.QueueAbyssLootDrop(app, item, x, y)
    if type(item) ~= "table" then return false end
    app.pendingAbyssLoot = math.max(0, math.floor(tonumber(app.pendingAbyssLoot) or 0)) + 1
    local angle = -math.pi * 0.5 + (math.random() - 0.5) * math.pi * 0.65
    local distance = 38 + math.random() * 20
    app.effects[#app.effects + 1] = {
        kind = "abyss_loot_drop", item = item, phase = "pop",
        x = x, y = y, startX = x, startY = y,
        popX = x + math.cos(angle) * distance,
        popY = y + math.sin(angle) * distance,
        elapsed = 0, duration = 0.52,
    }
    return true
end

function DropController.FinishOreDrop(app, effect, animate)
    if not effect.banked then app.state:AddRunOre(effect.ore, effect.units) end
    app.pendingOre[effect.ore] = math.max(0, (app.pendingOre[effect.ore] or 0) - effect.units)
    app.oreDropEffectCount = math.max(0, math.floor(tonumber(app.oreDropEffectCount) or 0) - 1)
    if animate then
        local targetX, targetY = app.renderer:GetOreHudTarget(app, effect.ore)
        app.effects[#app.effects + 1] = {
            kind = "hud_pop", x = targetX, y = targetY,
            life = 0.22, maxLife = 0.22, ore = effect.ore,
        }
        app.audio:PlaySfx(Config.Audio.pickup, 0.35, 0.95 + math.random() * 0.1)
    end
end

function DropController.FinishArtefactDrop(app, effect, animate)
    app.pendingArtefacts[effect.artefactId] = nil
    local unlocked = app.state:UnlockArtefact(effect.artefactId)
    if not unlocked then return end
    local node = app.state.nodeById[effect.artefactId]
    if animate then
        local targetX, targetY = app.renderer:GetArtefactHudTarget(app, effect.artefactId)
        app.effects[#app.effects + 1] = {
            kind = "hud_pop", x = targetX, y = targetY,
            life = 0.42, maxLife = 0.42, artefactId = effect.artefactId,
        }
        app.audio:PlaySfx(Config.Audio.pickup, 0.8, 1.12)
    end
    app:ShowToast("获得天赋遗物：" .. (node and node.name or effect.artefactId) .. " · 已收入图鉴",
        Config.Palette.gold, 3.4)
end

function DropController.FinishRelicDrop(app, effect, animate)
    app.pendingRelics[effect.relicId] = nil
    local relic = app.state:GetRelic(effect.relicId)
    if not relic then return end
    local newlySeen = app.state:MarkRelicSeen(effect.relicId)
    if not newlySeen then return end
    local cores = 2 + math.floor(relic.map / 2)
    app.runRelicCoreBonus = app.runRelicCoreBonus + cores
    if animate then
        local targetX, targetY = app.renderer:GetRelicHudTarget(app, effect.relicId)
        app.effects[#app.effects + 1] = {
            kind = "hud_pop", x = targetX, y = targetY,
            life = 0.5, maxLife = 0.5, relicId = effect.relicId,
        }
        app.audio:PlaySfx(Config.Audio.pickup, 0.9, 1.14)
    end
    app:ShowToast("发现新遗物：" .. relic.name .. " · 回遗物库研究 · 核心 +" .. tostring(cores),
        Config.Palette.gold, 4)
end

function DropController.FinishAbyssLootDrop(app, effect, animate)
    local item = effect and effect.item
    if not item then return end
    app.pendingAbyssLoot = math.max(0, (app.pendingAbyssLoot or 0) - 1)
    local equipped, dust, stored = app.state:AddAbyssLoot(item)
    if app.abyss then
        app.abyss.lootDrops = (app.abyss.lootDrops or 0) + 1
        local currentBest = AbyssLoot.GetGradeIndex(app.abyss.bestLootGrade)
        if (item.gradeIndex or 0) > currentBest then app.abyss.bestLootGrade = item.grade end
    end
    if animate then
        local targetX, targetY = app.renderer:GetAbyssLootHudTarget(item.slot)
        app.effects[#app.effects + 1] = {
            kind = "hud_pop", x = targetX, y = targetY,
            life = 0.55, maxLife = 0.55, abyssGrade = item.grade,
        }
        app.audio:PlaySfx(Config.Audio.pickup, 0.95, 0.86 + (item.gradeIndex or 1) * 0.045)
    end
    local suffix = equipped and " · 空槽已自动装备"
        or (stored and (dust > 0 and (" · 已存仓库 · 淘汰装备分解 +" .. tostring(dust)) or " · 已存入装备仓库")
        or (" · 仓库已满 · 自动分解晶尘 +" .. tostring(dust)))
    app:ShowToast("获得 " .. item.name .. suffix,
        AbyssLoot.GetGradeColor(item.grade, app.renderer.time), 3.2)
end

function DropController.CollectAllOreDrops(app)
    for index = #app.effects, 1, -1 do
        local effect = app.effects[index]
        if effect.kind == "ore_drop" then
            DropController.FinishOreDrop(app, effect, false)
            table.remove(app.effects, index)
        elseif effect.kind == "artefact_drop" then
            DropController.FinishArtefactDrop(app, effect, false)
            table.remove(app.effects, index)
        elseif effect.kind == "relic_drop" then
            DropController.FinishRelicDrop(app, effect, false)
            table.remove(app.effects, index)
        elseif effect.kind == "abyss_loot_drop" then
            DropController.FinishAbyssLootDrop(app, effect, false)
            table.remove(app.effects, index)
        end
    end
end

return DropController
