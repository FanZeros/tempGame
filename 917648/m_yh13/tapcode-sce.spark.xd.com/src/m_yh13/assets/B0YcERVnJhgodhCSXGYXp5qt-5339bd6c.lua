local Config = require("diggin.Config")
local WorldTree = require("diggin.WorldTree")
local AbyssRunTools = require("diggin.AbyssRunTools")

local AbyssDraft = {}

AbyssDraft.ROUTES = {
    {
        id = "safe", name = "脆岩捷径", color = Config.Palette.green, iconIndex = 1,
        description = "矿层生命 -45% · 怪物/Boss较弱 · 苔根系专属装备",
        healthMultiplier = 0.55, chaseMultiplier = 0.92, lootMultiplier = 0.8, pointMultiplier = 0.9,
        enemyHealthMultiplier = 0.88, enemySpeedMultiplier = 0.94, enemyDamageMultiplier = 0.86,
        bossDamageMultiplier = 0.88, bossCooldownMultiplier = 1.12, enemyCountBonus = 0,
    },
    {
        id = "treasure", name = "丰矿支脉", color = Config.Palette.gold, iconIndex = 2,
        description = "宝箱与装备更丰厚 · 敌人标准强度 · 聚宝系专属装备",
        healthMultiplier = 0.9, chaseMultiplier = 1, lootMultiplier = 1.35, pointMultiplier = 1.08,
        enemyHealthMultiplier = 1, enemySpeedMultiplier = 1, enemyDamageMultiplier = 1,
        bossDamageMultiplier = 1, bossCooldownMultiplier = 1, enemyCountBonus = 1,
    },
    {
        id = "risk", name = "灾变裂谷", color = Config.Palette.red, iconIndex = 3,
        description = "矿层、怪物与Boss强化 · 高掉落 · 灾变系专属装备",
        healthMultiplier = 1.18, chaseMultiplier = 1.12, lootMultiplier = 1.8, pointMultiplier = 1.28,
        enemyHealthMultiplier = 1.3, enemySpeedMultiplier = 1.14, enemyDamageMultiplier = 1.28,
        bossDamageMultiplier = 1.34, bossCooldownMultiplier = 0.82, enemyCountBonus = 2,
    },
}

local ROUTE_BY_ID = {}
for _, route in ipairs(AbyssDraft.ROUTES) do ROUTE_BY_ID[route.id] = route end

-- The run always begins without signature weapons. Ordinary choices build
-- forge progress; every forge milestone offers three final weapons/masteries.
AbyssDraft.BOONS = {
    { id = "star_fuel", branch = "star", name = "星核燃芯", description = "世界树道具伤害 +14%", color = Config.Palette.red,
        maxLevel = 2, stats = { item_power_pct = 14 } },
    { id = "star_focus", branch = "star", name = "爆钻聚焦", description = "世界树道具冷却 -8%", color = Config.Palette.red,
        maxLevel = 2, requires = "star_fuel", stats = { item_cooldown_pct = 8 } },
    { id = "starcore_bomb", branch = "star", itemId = "starcore_bomb", name = "星核爆钻", description = "获得星核爆钻；周期性大范围爆破", color = Config.Palette.red,
        maxLevel = 1, requires = "star_focus" },

    { id = "amber_signal", branch = "amber", name = "蜂群信标", description = "世界树道具冷却 -7%", color = Config.Palette.cyan,
        maxLevel = 2, stats = { item_cooldown_pct = 7 } },
    { id = "amber_protocol", branch = "amber", name = "琥珀协议", description = "世界树道具伤害 +12%", color = Config.Palette.cyan,
        maxLevel = 2, requires = "amber_signal", stats = { item_power_pct = 12 } },
    { id = "amber_swarm", branch = "amber", itemId = "amber_swarm", name = "琥珀蜂群", description = "获得琥珀蜂群；连续清理附近矿层", color = Config.Palette.cyan,
        maxLevel = 1, requires = "amber_protocol" },

    { id = "root_seed", branch = "root", name = "根盾胚芽", description = "深渊轰击伤害减免 +8%", color = Config.Palette.green,
        maxLevel = 2, stats = { boss_reduction_pct = 8 } },
    { id = "root_charge", branch = "root", name = "岩脉充能", description = "完美闪避窗口 +0.04秒", color = Config.Palette.green,
        maxLevel = 2, requires = "root_seed", stats = { perfect_window = 0.04 } },
    { id = "root_aegis", branch = "root", itemId = "root_aegis", name = "生命根盾", description = "获得生命根盾；格挡吞噬并击退巨物", color = Config.Palette.green,
        maxLevel = 1, requires = "root_charge" },

    { id = "chrono_spore", branch = "chrono", name = "时光孢子", description = "闪避冷却 -8%", color = Config.Palette.purple,
        maxLevel = 2, stats = { dodge_cooldown_pct = 8 } },
    { id = "chrono_calyx", branch = "chrono", name = "迟滞花萼", description = "追击速度 -5%", color = Config.Palette.purple,
        maxLevel = 2, requires = "chrono_spore", stats = { chaser_slow_pct = 5 } },
    { id = "chronobloom", branch = "chrono", itemId = "chronobloom", name = "时光花", description = "获得时光花；周期性减速上方巨物", color = Config.Palette.purple,
        maxLevel = 1, requires = "chrono_calyx" },

    { id = "forge_falling_pickaxe", branch = "forge", capstoneId = "FallingPickaxe", name = "巨镐奔袭", description = "回旋镐 Lv.5 进化；不额外占道具槽", color = Config.Palette.red, maxLevel = 1 },
    { id = "forge_termite_drones", branch = "forge", capstoneId = "TermiteDrones", name = "无人机军团", description = "钻地无人机 Lv.5 进化；不额外占道具槽", color = Config.Palette.cyan, maxLevel = 1 },
    { id = "forge_molenir", branch = "forge", capstoneId = "Molenir", name = "鼹神之锤", description = "震荡波 Lv.5 进化；不额外占道具槽", color = Config.Palette.gold, maxLevel = 1 },
    { id = "forge_the_worm", branch = "forge", capstoneId = "TheWorm", name = "地龙王", description = "子弹蠕虫 Lv.5 进化；不额外占道具槽", color = Config.Palette.purple, maxLevel = 1 },
    { id = "forge_abyss_bombardment", branch = "forge", capstoneId = "AbyssBombardment", name = "裂界轰天雷", description = "爆破炸弹 Lv.5 进化；双轮重型轰炸", color = Config.Palette.orange, maxLevel = 1 },
    { id = "forge_shard_typhoon", branch = "forge", capstoneId = "ShardTyphoon", name = "万刃矿暴", description = "爆裂弹片 Lv.5 进化；释放高密度穿矿弹幕", color = Config.Palette.orange, maxLevel = 1 },
    { id = "forge_meteor_drill_array", branch = "forge", capstoneId = "MeteorDrillArray", name = "天穹钻阵", description = "钻头导弹 Lv.5 进化；召唤密集钻头陨雨", color = Config.Palette.red, maxLevel = 1 },
    { id = "forge_singularity_drill", branch = "forge", capstoneId = "SingularityDrill", name = "奇点钻球", description = "弹跳钻球 Lv.5 进化；多重钻球封锁矿层", color = Config.Palette.purple, maxLevel = 1 },

    { id = "deep_drill", branch = "common", name = "深层钻压", description = "钻头伤害 +18%", color = Config.Palette.gold,
        maxLevel = 6, stats = { drill_damage_pct = 18 } },
    { id = "fuel_loop", branch = "common", name = "燃料循环", description = "立即恢复20%燃料，容量 +6%", color = Config.Palette.green,
        maxLevel = 4, stats = { fuel_capacity_pct = 6 }, instantFuelPct = 20 },
    { id = "phase_boots", branch = "common", name = "相位履带", description = "移动速度 +7% · 闪避距离 +8%", color = Config.Palette.cyan,
        maxLevel = 4, stats = { move_speed_pct = 7, dodge_distance_pct = 8 } },
    { id = "abyss_luck", branch = "common", name = "轮回寻宝", description = "本局装备品级幸运 +1", color = Config.Palette.purple,
        maxLevel = 3, stats = { loot_grade_bonus = 1 } },
    { id = "weapon_overclock", branch = "forge", forgeOption = true, name = "专武超频", description = "已解锁终极专武伤害 +25%", color = Config.Palette.gold,
        maxLevel = 99, stats = { capstone_power_pct = 25 } },
    { id = "weapon_cooling", branch = "forge", forgeOption = true, name = "永冻机匣", description = "已解锁终极专武冷却 -15%", color = Config.Palette.cyan,
        maxLevel = 99, stats = { capstone_cooldown_pct = 15 } },
    { id = "weapon_resonance", branch = "forge", forgeOption = true, name = "四相共鸣", description = "终极专武伤害 +12% · 冷却 -8%", color = Config.Palette.purple,
        maxLevel = 99, stats = { capstone_power_pct = 12, capstone_cooldown_pct = 8 } },
}

-- Finite branch nodes eventually run out during long Abyss loops. These three
-- repeatable choices keep the per-floor draft and its progression valid forever.
AbyssDraft.ENDLESS_BOONS = {
    { id = "endless_drill", branch = "endless", endless = true, name = "轮回钻压",
        description = "钻头伤害 +15% · 可无限叠加", color = Config.Palette.gold,
        stats = { drill_damage_pct = 15 } },
    { id = "endless_fuel", branch = "endless", endless = true, name = "轮回燃芯",
        description = "立即恢复25%燃料，容量 +5% · 可无限叠加", color = Config.Palette.green,
        stats = { fuel_capacity_pct = 5 }, instantFuelPct = 25 },
    { id = "endless_motion", branch = "endless", endless = true, name = "轮回动能",
        description = "移动速度 +5% · 闪现距离 +8% · 可无限叠加", color = Config.Palette.cyan,
        stats = { move_speed_pct = 5, dodge_distance_pct = 8 } },
}

local BOON_BY_ID = {}
for _, boon in ipairs(AbyssDraft.BOONS) do BOON_BY_ID[boon.id] = boon end
for _, boon in ipairs(AbyssDraft.ENDLESS_BOONS) do BOON_BY_ID[boon.id] = boon end

function AbyssDraft.GetRoute(id) return ROUTE_BY_ID[id] end
function AbyssDraft.GetBoon(id) return BOON_BY_ID[id] end

local function boonLevel(abyss, id)
    return math.max(0, math.floor(tonumber(abyss and abyss.boons and abyss.boons[id]) or 0))
end

local function eligible(state, abyss, boon)
    if not boon.endless and boonLevel(abyss, boon.id) >= boon.maxLevel then return false end
    if boon.capstoneId or boon.forgeOption then return false end
    if boon.requires and boonLevel(abyss, boon.requires) <= 0 then return false end
    if boon.itemId and not WorldTree.IsItemUnlocked(state, boon.itemId) then return false end
    return true
end

function AbyssDraft.MakeRouteChoice(floor)
    return { kind = "route", floor = floor, title = "选择本局唯一矿路 · 选后锁定", options = AbyssDraft.ROUTES }
end

function AbyssDraft.MakeEndlessChoice(abyss, completedFloor)
    local options = {}
    for _, boon in ipairs(AbyssDraft.ENDLESS_BOONS) do options[#options + 1] = boon end
    abyss.choiceSerial = math.max(1, math.floor(tonumber(abyss.choiceSerial) or 1)) + 1
    return {
        kind = "boon",
        floor = completedFloor,
        title = "贯穿第 " .. completedFloor .. " 层 · 轮回强化三选一",
        options = options,
    }
end

function AbyssDraft.MakeWeaponChoice(abyss, completedFloor)
    if completedFloor < (abyss.nextForgeFloor or 4) or (abyss.forgeProgress or 0) < 3 then return nil end
    local eligible = {}
    for _, capstoneId in ipairs(AbyssRunTools.GetEvolutionCandidates(abyss)) do eligible[capstoneId] = true end
    local options = {}
    local finals = {
        "forge_abyss_bombardment", "forge_molenir", "forge_shard_typhoon", "forge_falling_pickaxe",
        "forge_meteor_drill_array", "forge_singularity_drill", "forge_the_worm", "forge_termite_drones",
    }
    local start = ((abyss.weaponChoiceSerial or 1) - 1) % #finals + 1
    for offset = 0, #finals - 1 do
        local boon = BOON_BY_ID[finals[((start + offset - 1) % #finals) + 1]]
        if boon and eligible[boon.capstoneId] then options[#options + 1] = boon end
        if #options >= 3 then break end
    end
    local offeredEvolution = #options > 0
    -- A run owns at most five tools, while the global recipe book now holds
    -- eight evolutions.  Mastery must depend on the current loadout, not on
    -- collecting mutually exclusive recipes in the same run.
    if not offeredEvolution and AbyssRunTools.GetEvolutionCount(abyss) <= 0 then return nil end
    for _, id in ipairs({ "weapon_overclock", "weapon_cooling", "weapon_resonance" }) do
        local mastery = BOON_BY_ID[id]
        if #options < 3 and boonLevel(abyss, id) < mastery.maxLevel then options[#options + 1] = mastery end
    end
    if #options == 0 then return nil end
    abyss.weaponChoiceSerial = (abyss.weaponChoiceSerial or 1) + 1
    return { kind = "weapon", floor = completedFloor,
        title = offeredEvolution and "满级道具进化 · 三选一" or "专武精通 · 三选一", options = options }
end

function AbyssDraft.MakeBoonChoice(state, abyss, completedFloor)
    local weaponChoice = AbyssDraft.MakeWeaponChoice(abyss, completedFloor)
    if weaponChoice then return weaponChoice end
    local candidates = {}
    for _, boon in ipairs(AbyssDraft.BOONS) do
        if eligible(state, abyss, boon) then candidates[#candidates + 1] = boon end
    end
    local isEndless = #candidates == 0
    local options = {}
    local serial = math.max(1, math.floor(tonumber(abyss.choiceSerial) or 1))
    if isEndless then
        return AbyssDraft.MakeEndlessChoice(abyss, completedFloor)
    else
        local start = ((serial * 5 + completedFloor * 3 - 1) % #candidates) + 1
        for offset = 0, math.min(2, #candidates - 1) do
            options[#options + 1] = candidates[((start + offset - 1) % #candidates) + 1]
        end
        -- Keep the promise made by the modal title even while the last one or
        -- two finite nodes are being consumed.
        for _, boon in ipairs(AbyssDraft.ENDLESS_BOONS) do
            if #options >= 3 then break end
            options[#options + 1] = boon
        end
    end
    abyss.choiceSerial = serial + 1
    return { kind = "boon", floor = completedFloor,
        title = "贯穿第 " .. completedFloor .. " 层 · 三选一", options = options }
end

local function applyStats(app, abyss, boon)
    app.state.abyssRunBonuses = app.state.abyssRunBonuses or {}
    for statId in pairs(boon.stats or {}) do
        app.state.abyssRunBonuses[statId] = AbyssDraft.GetStat(abyss, statId)
    end
end

function AbyssDraft.ApplyBoon(app, abyss, id)
    local boon = BOON_BY_ID[id]
    if not boon or not eligible(app.state, abyss, boon) then return false end
    abyss.boons[id] = boonLevel(abyss, id) + 1
    abyss.forgeProgress = math.min(3, (abyss.forgeProgress or 0) + 1)
    applyStats(app, abyss, boon)
    if boon.instantFuelPct then
        app.fuel = math.min(app.maxFuel, app.fuel + app.maxFuel * boon.instantFuelPct / 100)
    end
    if boon.stats and boon.stats.fuel_capacity_pct then
        local gained = app.maxFuel * boon.stats.fuel_capacity_pct / 100
        app.maxFuel, app.fuel = app.maxFuel + gained, math.min(app.maxFuel + gained, app.fuel + gained)
    end
    return true, boon
end

function AbyssDraft.ForgeWeapon(app, abyss, id, completedFloor)
    local boon = BOON_BY_ID[id]
    if not boon or (not boon.capstoneId and not boon.forgeOption) or (abyss.forgeProgress or 0) < 3 then return false end
    if boonLevel(abyss, id) >= boon.maxLevel then return false end
    if boon.capstoneId and abyss.runCapstones[boon.capstoneId] then return false end
    local baseTool = boon.capstoneId and AbyssRunTools.GetToolForEvolution(boon.capstoneId) or nil
    if boon.capstoneId and (not baseTool or AbyssRunTools.GetLevel(abyss, baseTool) < AbyssRunTools.MAX_LEVEL) then
        return false
    end
    abyss.boons[id] = boonLevel(abyss, id) + 1
    if boon.capstoneId then
        abyss.runCapstones[boon.capstoneId] = true
        AbyssRunTools.MarkEvolved(abyss, baseTool, boon.capstoneId)
    end
    applyStats(app, abyss, boon)
    abyss.forgeProgress = 0
    abyss.nextForgeFloor = math.max(completedFloor + 4, (abyss.nextForgeFloor or 4) + 5)
    return true, boon
end

function AbyssDraft.GetStat(abyss, statId)
    local total = 0
    for id, level in pairs(abyss and abyss.boons or {}) do
        local boon = BOON_BY_ID[id]
        if boon and boon.stats and boon.stats[statId] then total = total + boon.stats[statId] * level end
    end
    local caps = {
        move_speed_pct = 120, dodge_distance_pct = 160,
        item_cooldown_pct = 70, capstone_cooldown_pct = 75,
    }
    return caps[statId] and math.min(caps[statId], total) or total
end

return AbyssDraft
