local RelicData = {}

-- Two relics belong to each density/map. Icons are recovered original-game
-- skill sprites that already ship with the project, so the library stays in
-- the same pixel-art language and never depends on missing generated files.
RelicData.list = {
    { id = "rusted_gear", map = 1, name = "锈蚀齿轮", icon = "MovementSpeed1", color = "cyan", cost = 12,
      description = "移动速度 +12%", bonuses = { movement_speed_pct = 12 } },
    { id = "tempered_bit", map = 1, name = "淬火钻头", icon = "MiningDamage1", color = "red", cost = 16,
      description = "钻探伤害 +15%", bonuses = { drill_damage_pct = 15 } },

    { id = "fuel_filter", map = 2, name = "净化滤芯", icon = "FuelEfficiency1", color = "green", cost = 24,
      description = "燃料效率 +15%", bonuses = { fuel_efficiency_pct = 15 } },
    { id = "cargo_magnet", map = 2, name = "回收磁芯", icon = "CollectorSpeed", color = "cyan", cost = 30,
      description = "掉落物飞行速度 +60%", bonuses = { pickup_speed_pct = 60 } },

    { id = "lucky_nugget", map = 3, name = "幸运金粒", icon = "GoldBonanza", color = "gold", cost = 40,
      description = "挖矿有 8% 概率双倍掉落", bonuses = { double_drop_chance = 8 } },
    { id = "crit_lens", map = 3, name = "裂隙透镜", icon = "CritChance1", color = "red", cost = 48,
      description = "钻击暴击率 +8%", bonuses = { critical_chance_flat = 8 } },

    { id = "blast_fuse", map = 4, name = "短燃引信", icon = "DynamiteCooldown", color = "orange", cost = 60,
      description = "所有自动技能冷却 -18%", bonuses = { active_cooldown_pct = 18 } },
    { id = "shaped_charge", map = 4, name = "定向药包", icon = "DynamiteRadius", color = "orange", cost = 72,
      description = "爆炸与范围技能半径 +25%", bonuses = { explosion_radius_pct = 25 } },

    { id = "platinum_seal", map = 5, name = "铂金印章", icon = "AugmentPlatinum", color = "gold", cost = 88,
      description = "局外资源结算量 +15%", bonuses = { settlement_yield_pct = 15 } },
    { id = "deep_compass", map = 5, name = "深层罗盘", icon = "FieldOfView2", color = "cyan", cost = 102,
      description = "黄金及稀有矿权重 +25%", bonuses = { rare_ore_weight_pct = 25 } },

    { id = "emerald_loop", map = 6, name = "翡翠回路", icon = "FeverstoneDuration", color = "green", cost = 120,
      description = "狂热持续时间 +35%", bonuses = { frenzy_duration_pct = 35 } },
    { id = "repair_nanites", map = 6, name = "修复纳米群", icon = "Fuelstone", color = "green", cost = 138,
      description = "每挖碎矿块恢复 0.18 燃料", bonuses = { fuel_recovery_flat = 0.18 } },

    { id = "ruby_core", map = 7, name = "红玉核心", icon = "CritDamage1", color = "red", cost = 160,
      description = "暴击伤害 +40%", bonuses = { critical_damage_pct = 40 } },
    { id = "chain_spark", map = 7, name = "连锁火花", icon = "CritChain", color = "purple", cost = 182,
      description = "暴击有 35% 概率击打相邻矿块", bonuses = { crit_splash_chance = 35 } },

    { id = "diamond_shell", map = 8, name = "钻石外壳", icon = "FuelTank4", color = "cyan", cost = 208,
      description = "燃料上限 +25%", bonuses = { fuel_capacity_pct = 25 } },
    { id = "overdrive_coil", map = 8, name = "超频线圈", icon = "OverdriveStrength", color = "gold", cost = 236,
      description = "超频钻探强度 +30%", bonuses = { overdrive_strength_pct = 30 } },

    { id = "star_metal_shard", map = 9, name = "星金属残片", icon = "ResourceTripler", color = "purple", cost = 270,
      description = "挖矿有 5% 概率三倍掉落", bonuses = { triple_drop_chance = 5 } },
    { id = "relic_beacon", map = 9, name = "遗物信标", icon = "FieldOfView4", color = "cyan", cost = 306,
      description = "宝箱生成率额外 +0.18%", bonuses = { chest_chance_flat = 0.18 } },

    { id = "void_drill", map = 10, name = "虚空钻芯", icon = "MiningDamage4", color = "purple", cost = 346,
      description = "直接钻击有 4% 概率瞬间破坏", bonuses = { instant_break_chance = 4 } },
    { id = "depth_crown", map = 10, name = "地心王冠", icon = "UpgradeStart", color = "gold", cost = 390,
      description = "所有矿物掉落量 +12%", bonuses = { all_yield_pct = 12 } },
}

RelicData.byId = {}
RelicData.byMap = {}
for _, relic in ipairs(RelicData.list) do
    RelicData.byId[relic.id] = relic
    RelicData.byMap[relic.map] = RelicData.byMap[relic.map] or {}
    RelicData.byMap[relic.map][#RelicData.byMap[relic.map] + 1] = relic
end

return RelicData
