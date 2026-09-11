local Prestige = {}

Prestige.Definitions = {
    {
        id = "p_root", name = "黄金火种", description = "点燃转生技能树。怪物掉落金币永久提高，金币飞入左侧计数后按加成入账。",
        icon = "image/nightgate/achievements/prestiged_8b334685.png", parents = {}, x = 430, y = 310,
        costs = { 1 }, values = { 20 }, effect = "goldGainBonus", effectText = "金币获取", suffix = "%",
    },
    {
        id = "p_power", name = "不灭锋芒", description = "所有指针、弓箭手与英雄造成的伤害永久提高。",
        icon = "image/nightgate/achievements/totaldamage_e4ab383a.png", parents = { "p_root" }, x = 220, y = 160,
        costs = { 1, 2, 3, 4, 5 }, values = { 8, 8, 8, 8, 8 }, effect = "allDamageBonus", effectText = "所有伤害", suffix = "%",
    },
    {
        id = "p_cursor", name = "灵魂指针", description = "提高指针每次扩张攻击的基础伤害。",
        icon = "image/nightgate/achievements/enemieskilled_281a9c96.png", parents = { "p_power" }, x = 40, y = 50,
        costs = { 2, 3, 4 }, values = { 1, 1, 1 }, effect = "cursorBase", effectText = "指针基础伤害", suffix = "",
    },
    {
        id = "p_archer", name = "永恒箭阵", description = "弓箭手解锁后，每支箭都获得额外基础伤害。",
        icon = "image/nightgate/achievements/skilltreecount_e7f1479b.png", parents = { "p_power" }, x = 40, y = 270,
        costs = { 2, 3, 4 }, values = { 1, 1, 1 }, effect = "archerDamage", effectText = "弓箭伤害", suffix = "",
    },
    {
        id = "p_wall", name = "古老城垒", description = "四面城墙获得永久额外生命值。",
        icon = "image/nightgate/achievements/survivalday_a86b9cd8.png", parents = { "p_root" }, x = 640, y = 160,
        costs = { 1, 2, 3, 4, 5 }, values = { 20, 20, 20, 20, 20 }, effect = "wallFlat", effectText = "城墙生命", suffix = "",
    },
    {
        id = "p_armor", name = "石肤祝福", description = "降低每次怪物攻击对城墙造成的伤害。",
        icon = "image/nightgate/achievements/bossdefeated_4a433817.png", parents = { "p_wall" }, x = 820, y = 50,
        costs = { 2, 3, 4 }, values = { 1, 1, 1 }, effect = "wallDefense", effectText = "城墙防御", suffix = "",
    },
    {
        id = "p_dodge", name = "迷雾屏障", description = "城墙有概率完全避开一次怪物攻击。",
        icon = "image/nightgate/achievements/survivorinfinal_5772b72d.png", parents = { "p_wall" }, x = 820, y = 270,
        costs = { 2, 3, 4 }, values = { 2, 2, 2 }, effect = "wallDodge", effectText = "城墙闪避", suffix = "%",
    },
    {
        id = "p_supply", name = "开拓储备", description = "提高怪物掉落金币的获取量，每级永久增加30%。",
        icon = "image/nightgate/achievements/totalgold_76e38729.png", parents = { "p_root" }, x = 220, y = 500,
        costs = { 1, 2, 3, 4 }, values = { 30, 30, 30, 30 }, effect = "goldGainBonus", effectText = "金币获取", suffix = "%",
    },
    {
        id = "p_gold", name = "丰收契约", description = "每晚胜利结算时获得更多金币。",
        icon = "image/nightgate/currency/asset_632cd9da.png", parents = { "p_supply" }, x = 40, y = 620,
        costs = { 2, 3, 4, 5 }, values = { 10, 10, 10, 10 }, effect = "goldSettlementBonus", effectText = "结算金币", suffix = "%",
    },
    {
        id = "p_crystal", name = "晶石共鸣", description = "每晚胜利结算时获得更多晶石。",
        icon = "image/nightgate/achievements/crystalkilled_6b90ffbe.png", parents = { "p_supply" }, x = 400, y = 620,
        costs = { 2, 3, 4, 5 }, values = { 10, 10, 10, 10 }, effect = "crystalSettlementBonus", effectText = "结算晶石", suffix = "%",
    },
    {
        id = "p_fate", name = "命运涟漪", description = "扩大指针攻击圆环，更容易覆盖成群怪物。",
        icon = "image/nightgate/achievements/boxkilled_c837b95f.png", parents = { "p_root" }, x = 640, y = 500,
        costs = { 1, 2, 3, 4, 5 }, values = { 5, 5, 5, 5, 5 }, effect = "cursorRadiusBonus", effectText = "指针范围", suffix = "%",
    },
    {
        id = "p_hunt", name = "晶兽追猎", description = "每晚额外出现晶石怪，让重生后的资源恢复更快。",
        icon = "image/nightgate/achievements/equipcollected_bd3a6ed7.png", parents = { "p_fate" }, x = 600, y = 620,
        costs = { 2, 3, 4 }, values = { 1, 1, 1 }, effect = "extraCrystalMonsters", effectText = "额外晶石怪", suffix = "",
    },
    {
        id = "p_dragon", name = "古龙盟约", description = "每晚获得一次古龙助战机会，清理危急方向的怪群。",
        icon = "image/nightgate/achievements/gameplayed_6c82dbdc.png", parents = { "p_fate" }, x = 820, y = 620,
        costs = { 6 }, values = { 1 }, effect = "dragonAssist", effectText = "古龙助战", suffix = "",
    },
    {
        id = "p_afterglow", name = "轮回余火", description = "转生后的前3夜获得50%全伤害和150城墙耐久，快速越过重复开局。",
        icon = "image/nightgate/skill_tree/generated/prestige_afterglow.png", parents = { "p_root" }, x = 430, y = 100,
        costs = { 1 }, values = { 1 }, effect = "earlyAfterglow", effectText = "前3夜余火", suffix = "",
        levelTexts = { "前3夜：全伤害+50%，城墙+150" },
    },
    {
        id = "p_spirit_archers", name = "灵魂箭阵", description = "即使尚未重建弓箭分支，也会由四面墙周期发射灵魂箭。",
        icon = "image/nightgate/skill_tree/generated/expansion_archer_barrage.png", parents = { "p_afterglow" }, x = 330, y = 0,
        costs = { 2 }, values = { 1 }, effect = "spiritVolleyEnabled", effectText = "自动灵魂箭", suffix = "",
        levelTexts = { "永久启用四墙灵魂箭阵" },
    },
    {
        id = "p_auto_hunt", name = "自主狩猎", description = "每次重生直接启用自动指针，未点普通自动指针节点也可生效。",
        icon = "image/nightgate/skill_tree/generated/expansion_cursor_echo.png", parents = { "p_afterglow" }, x = 530, y = 0,
        costs = { 2 }, values = { 1 }, effect = "autoHuntEnabled", effectText = "自动指针", suffix = "",
        levelTexts = { "永久启用自动指针攻击" },
    },
}

local byId = {}
for index = 1, #Prestige.Definitions do
    byId[Prestige.Definitions[index].id] = Prestige.Definitions[index]
end

function Prestige.GetDefinition(id)
    return byId[id]
end

function Prestige.GetLevel(levels, id)
    return math.max(0, math.floor(tonumber(levels and levels[id]) or 0))
end

function Prestige.CalculateReward(bestNight)
    bestNight = math.max(0, math.floor(tonumber(bestNight) or 0))
    if bestNight < 10 then return 0 end
    -- 10/20/30 nights now grant 6/12/18 points. A full ~140-point tree
    -- takes about eight long clears instead of fourteen, while short runs
    -- still reward substantially less than deep runs.
    return 1 + math.floor(bestNight / 2) + math.floor(bestNight / 15)
end

function Prestige.GetMilestone(night)
    night = math.max(0, math.floor(tonumber(night) or 0))
    if night >= 30 then return 30 end
    if night >= 20 then return 20 end
    if night >= 10 then return 10 end
    return 0
end

function Prestige.GetUnlockReason(levels, definition)
    if not definition then return "未知转生节点" end
    for index = 1, #definition.parents do
        if Prestige.GetLevel(levels, definition.parents[index]) <= 0 then
            local parent = byId[definition.parents[index]]
            return "需先点亮「" .. tostring(parent and parent.name or definition.parents[index]) .. "」"
        end
    end
    return nil
end

function Prestige.IsRevealed(levels, definition)
    if not definition then return false end
    if #definition.parents == 0 or Prestige.GetLevel(levels, definition.id) > 0 then return true end
    for index = 1, #definition.parents do
        if Prestige.GetLevel(levels, definition.parents[index]) > 0 then return true end
    end
    return false
end

function Prestige.GetNodeState(levels, definition)
    local level = Prestige.GetLevel(levels, definition.id)
    if Prestige.GetUnlockReason(levels, definition) then return "locked" end
    if level >= #definition.costs then return "maxed" end
    if level > 0 then return "owned" end
    return "available"
end

function Prestige.GetCost(levels, id)
    local definition = byId[id]
    return definition and definition.costs[Prestige.GetLevel(levels, id) + 1] or nil
end

function Prestige.GetEffectText(definition, levelIndex)
    levelIndex = math.max(1, math.floor(tonumber(levelIndex) or 1))
    if definition.levelTexts then
        return definition.levelTexts[levelIndex] or definition.levelTexts[#definition.levelTexts]
    end
    local value = definition.values[levelIndex] or definition.values[#definition.values] or 0
    return definition.effectText .. " +" .. tostring(value) .. (definition.suffix or "")
end

local function getEffectTotal(levels, effect)
    local total = 0
    for index = 1, #Prestige.Definitions do
        local definition = Prestige.Definitions[index]
        if definition.effect == effect then
            local level = math.min(Prestige.GetLevel(levels, definition.id), #definition.values)
            for valueIndex = 1, level do total = total + (tonumber(definition.values[valueIndex]) or 0) end
        end
    end
    return total
end

function Prestige.GetStartingGold(levels)
    return math.max(0, math.floor(getEffectTotal(levels, "startingGold") + 0.5))
end

function Prestige.ApplyStats(stats, levels, battle)
    stats.allDamageBonus = stats.allDamageBonus + getEffectTotal(levels, "allDamageBonus") / 100
    stats.cursorBase = stats.cursorBase + getEffectTotal(levels, "cursorBase")
    stats.archerDamage = stats.archerDamage + getEffectTotal(levels, "archerDamage")
    stats.wallFlat = stats.wallFlat + getEffectTotal(levels, "wallFlat")
    stats.wallDefense = stats.wallDefense + getEffectTotal(levels, "wallDefense")
    stats.wallDodge = stats.wallDodge + getEffectTotal(levels, "wallDodge") / 100
    stats.goldGainBonus = stats.goldGainBonus + getEffectTotal(levels, "goldGainBonus") / 100
    stats.goldSettlementBonus = stats.goldSettlementBonus + getEffectTotal(levels, "goldSettlementBonus")
    stats.crystalSettlementBonus = stats.crystalSettlementBonus + getEffectTotal(levels, "crystalSettlementBonus")
    stats.cursorRadiusBonus = stats.cursorRadiusBonus + getEffectTotal(levels, "cursorRadiusBonus") / 100
    stats.extraCrystalMonsters = stats.extraCrystalMonsters + getEffectTotal(levels, "extraCrystalMonsters")
    stats.dragonAssist = stats.dragonAssist + getEffectTotal(levels, "dragonAssist")
    stats.spiritVolleyEnabled = getEffectTotal(levels, "spiritVolleyEnabled")
    if getEffectTotal(levels, "autoHuntEnabled") > 0 then
        stats.randomCursorEnabled = stats.randomCursorEnabled + 1
    end
    local activeNight = math.max(1, math.floor(tonumber(battle and (battle.night or battle.nextNight)) or 1))
    if activeNight <= 3 and getEffectTotal(levels, "earlyAfterglow") > 0 then
        stats.allDamageBonus = stats.allDamageBonus + 0.50
        stats.wallFlat = stats.wallFlat + 150
        stats.earlyAfterglowActive = true
    end
end

function Prestige.TryUpgrade(battle, id)
    local definition = byId[id]
    if not definition then return false, "未知转生节点" end
    local reason = Prestige.GetUnlockReason(battle.prestigeLevels, definition)
    if reason then return false, reason end
    local level = Prestige.GetLevel(battle.prestigeLevels, id)
    local cost = definition.costs[level + 1]
    if not cost then return false, "已满级" end
    if battle.prestigePoints < cost then return false, "转生点不足" end
    battle.prestigePoints = battle.prestigePoints - cost
    battle.prestigeLevels[id] = level + 1
    if definition.effect == "startingGold" then
        battle.gold = battle.gold + (tonumber(definition.values[level + 1]) or 0)
    end
    battle.dirtySave = true
    return true, "已点亮「" .. definition.name .. "」"
end

return Prestige
