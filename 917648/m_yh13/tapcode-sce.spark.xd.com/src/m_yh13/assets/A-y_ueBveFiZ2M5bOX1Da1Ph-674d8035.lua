local Config = require("diggin.Config")

local AbyssContent = {}

-- Four original tree tools plus ten new late-tree tools. Unlock/mastery
-- nodes are deliberately placed in tiers four and five so a new save must
-- grow a real branch before adding the tool to its run draft pool.
AbyssContent.WORLD_ITEMS = {
    { id = "starcore_bomb", name = "星核爆钻", branch = "giant", unlockIndex = 16, upgradeIndex = 17,
        color = Config.Palette.red, icon = Config.Paths.generatedRoot .. "skill_icons/DynamiteActive.png",
        description = "向钻探方向投射多枚星核爆钻。", mastery = "爆破伤害 +30% · 冷却 -8%",
        masteryStats = { starcore_bomb_power_pct = 30, starcore_bomb_cooldown_pct = 8 } },
    { id = "magma_lance", name = "熔脉长枪", branch = "giant", unlockIndex = 20, upgradeIndex = 21,
        color = Config.Palette.orange, atlasIndex = 1, description = "沿钻探方向贯穿连续矿层与怪物。",
        mastery = "贯穿伤害 +35% · 冷却 -8%",
        masteryStats = { magma_lance_power_pct = 35, magma_lance_cooldown_pct = 8 } },
    { id = "crystal_saw", name = "晶轮锯阵", branch = "giant", unlockIndex = 24, upgradeIndex = 25,
        color = Config.Palette.cyan, atlasIndex = 2, description = "旋转晶锯环绕矿工切割四周。",
        mastery = "锯阵伤害 +30% · 作用范围 +12%",
        masteryStats = { crystal_saw_power_pct = 30, crystal_saw_range_pct = 12 } },

    { id = "amber_swarm", name = "琥珀蜂群", branch = "drone", unlockIndex = 16, upgradeIndex = 17,
        color = Config.Palette.cyan, icon = Config.Paths.generatedRoot .. "skill_icons/TermiteDrones.png",
        description = "蜂群连续寻找附近矿层并爆破。", mastery = "蜂群伤害 +28% · 冷却 -10%",
        masteryStats = { amber_swarm_power_pct = 28, amber_swarm_cooldown_pct = 10 } },
    { id = "prism_borer", name = "棱镜钻束", branch = "drone", unlockIndex = 20, upgradeIndex = 21,
        color = Config.Palette.cyan, atlasIndex = 3, description = "发射分叉的三束棱镜钻光。",
        mastery = "钻束伤害 +30% · 射程 +15%",
        masteryStats = { prism_borer_power_pct = 30, prism_borer_range_pct = 15 } },
    { id = "chain_drill", name = "链雷钻机", branch = "drone", unlockIndex = 24, upgradeIndex = 25,
        color = Config.Palette.purple, atlasIndex = 4, description = "电弧在怪物与矿脉间连续跳跃。",
        mastery = "链雷伤害 +32% · 冷却 -8%",
        masteryStats = { chain_drill_power_pct = 32, chain_drill_cooldown_pct = 8 } },

    { id = "root_aegis", name = "生命根盾", branch = "mole", unlockIndex = 16, upgradeIndex = 17,
        color = Config.Palette.green, icon = Config.Paths.generatedRoot .. "skill_icons/Molenir.png",
        description = "储存护盾，阻止巨物吞噬并击退它。", mastery = "根盾充能 +1 · 充能加速 10%",
        masteryStats = { root_aegis_power_pct = 30, root_aegis_cooldown_pct = 10 } },
    { id = "void_mine", name = "虚空地雷", branch = "mole", unlockIndex = 19, upgradeIndex = 20,
        color = Config.Palette.purple, atlasIndex = 5, description = "下方爆破并牵引范围内怪物。",
        mastery = "地雷伤害 +35% · 爆炸范围 +12%",
        masteryStats = { void_mine_power_pct = 35, void_mine_range_pct = 12 } },
    { id = "frost_capsule", name = "霜封胶囊", branch = "mole", unlockIndex = 22, upgradeIndex = 23,
        color = Config.Palette.cyan, atlasIndex = 6, description = "减速怪物和巨物；不造成伤害。",
        mastery = "冻结持续 +25% · 冷却 -10%",
        masteryStats = { frost_capsule_power_pct = 25, frost_capsule_cooldown_pct = 10 } },
    { id = "phoenix_fuel", name = "涅槃燃芯", branch = "mole", unlockIndex = 24, upgradeIndex = 25,
        color = Config.Palette.gold, atlasIndex = 7, description = "周期恢复燃料；不造成伤害。",
        mastery = "恢复量 +35% · 冷却 -10%",
        masteryStats = { phoenix_fuel_power_pct = 35, phoenix_fuel_cooldown_pct = 10 } },

    { id = "chronobloom", name = "时光花", branch = "worm", unlockIndex = 16, upgradeIndex = 17,
        color = Config.Palette.purple, icon = Config.Paths.generatedRoot .. "skill_icons/TheWorm.png",
        description = "周期绽放，使上方巨物大幅减速。", mastery = "持续时间 +25% · 冷却 -8%",
        masteryStats = { chronobloom_power_pct = 25, chronobloom_cooldown_pct = 8 } },
    { id = "echo_charge", name = "回声爆种", branch = "worm", unlockIndex = 19, upgradeIndex = 20,
        color = Config.Palette.orange, atlasIndex = 8, description = "复制一次爆破，在更深处再次引爆。",
        mastery = "回声伤害 +30% · 冷却 -8%",
        masteryStats = { echo_charge_power_pct = 30, echo_charge_cooldown_pct = 8 } },
    { id = "magnetic_harpoon", name = "磁轨钩钻", branch = "worm", unlockIndex = 22, upgradeIndex = 23,
        color = Config.Palette.gold, atlasIndex = 9, description = "牵引金币与怪物后集中钻爆。",
        mastery = "牵引范围 +18% · 伤害 +25%",
        masteryStats = { magnetic_harpoon_power_pct = 25, magnetic_harpoon_range_pct = 18 } },
    { id = "rift_beacon", name = "裂隙信标", branch = "worm", unlockIndex = 24, upgradeIndex = 25,
        color = Config.Palette.cyan, atlasIndex = 10, description = "在传送门层定位并轰击三格裂隙核心。",
        mastery = "核心伤害 +40% · 冷却 -10%",
        masteryStats = { rift_beacon_power_pct = 40, rift_beacon_cooldown_pct = 10 } },
}

AbyssContent.WORLD_ITEM_BY_ID = {}
for _, item in ipairs(AbyssContent.WORLD_ITEMS) do
    if item.atlasIndex then item.icon = Config.Paths.abyssWorldItemAtlas end
    AbyssContent.WORLD_ITEM_BY_ID[item.id] = item
end

-- Five visual identities per slot: two universal pieces plus one exclusive
-- item for each route. Across all three routes this produces 20 collectible
-- equipment entries while preserving the existing four-slot loadout.
AbyssContent.EQUIPMENT = {
    { id = "fracture_core", slot = "drill_core", name = "裂纹钻心", route = "universal", intrinsicStat = "drill_damage_pct", intrinsicScale = 0.55 },
    { id = "starbronze_turbine", slot = "drill_core", name = "星铜涡轮", route = "universal", intrinsicStat = "item_cooldown_pct", intrinsicScale = 0.18 },
    { id = "moss_core", slot = "drill_core", name = "苔根钻核", route = "safe", intrinsicStat = "boss_damage_reduction_pct", intrinsicScale = 0.22 },
    { id = "gilded_diviner", slot = "drill_core", name = "镀金寻脉仪", route = "treasure", intrinsicStat = "loot_luck", intrinsicScale = 0.35 },
    { id = "calamity_auger", slot = "drill_core", name = "灾变熔钻", route = "risk", intrinsicStat = "item_power_pct", intrinsicScale = 0.42 },

    { id = "stone_treads", slot = "greaves", name = "岩行履带", route = "universal", intrinsicStat = "move_speed_pct", intrinsicScale = 0.18 },
    { id = "phase_boots", slot = "greaves", name = "相位长靴", route = "universal", intrinsicStat = "perfect_window", intrinsicScale = 0.004 },
    { id = "moss_step", slot = "greaves", name = "软苔踏靴", route = "safe", intrinsicStat = "fuel_efficiency_pct", intrinsicScale = 0.28 },
    { id = "gold_magnet_boots", slot = "greaves", name = "拾金磁履", route = "treasure", intrinsicStat = "loot_luck", intrinsicScale = 0.3 },
    { id = "magma_stride", slot = "greaves", name = "熔脉疾足", route = "risk", intrinsicStat = "move_speed_pct", intrinsicScale = 0.28 },

    { id = "forged_shell", slot = "shell", name = "锻铁护壳", route = "universal", intrinsicStat = "boss_damage_reduction_pct", intrinsicScale = 0.28 },
    { id = "prism_carapace", slot = "shell", name = "棱晶反应甲", route = "universal", intrinsicStat = "item_power_pct", intrinsicScale = 0.32 },
    { id = "rooted_bulwark", slot = "shell", name = "生根壁甲", route = "safe", intrinsicStat = "boss_damage_reduction_pct", intrinsicScale = 0.42 },
    { id = "vault_scale", slot = "shell", name = "宝库鳞甲", route = "treasure", intrinsicStat = "point_gain_pct", intrinsicScale = 0.32 },
    { id = "calamity_thorn", slot = "shell", name = "灾厄荆甲", route = "risk", intrinsicStat = "drill_damage_pct", intrinsicScale = 0.4 },

    { id = "prospector_compass", slot = "sigil", name = "勘探者罗盘", route = "universal", intrinsicStat = "loot_luck", intrinsicScale = 0.36 },
    { id = "cycle_hourglass", slot = "sigil", name = "轮回沙漏", route = "universal", intrinsicStat = "item_cooldown_pct", intrinsicScale = 0.2 },
    { id = "rest_charm", slot = "sigil", name = "安息护符", route = "safe", intrinsicStat = "fuel_capacity_pct", intrinsicScale = 0.5 },
    { id = "treasure_seal", slot = "sigil", name = "聚宝王印", route = "treasure", intrinsicStat = "point_gain_pct", intrinsicScale = 0.58 },
    { id = "bloodmoon_contract", slot = "sigil", name = "血月契印", route = "risk", intrinsicStat = "item_power_pct", intrinsicScale = 0.48 },
}

AbyssContent.EQUIPMENT_BY_ID = {}
for index, item in ipairs(AbyssContent.EQUIPMENT) do
    item.iconIndex = index
    AbyssContent.EQUIPMENT_BY_ID[item.id] = item
end

return AbyssContent
