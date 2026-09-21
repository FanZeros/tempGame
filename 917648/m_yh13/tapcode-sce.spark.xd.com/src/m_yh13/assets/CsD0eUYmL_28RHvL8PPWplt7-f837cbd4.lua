local Early = {}

function Early.Add(tree, config)
    -- New stable IDs preserve every existing branch and legacy save mapping.
    local entries = {
        { "钻齿萌芽", "abyss_drill_damage_pct", 5, "深渊钻头伤害 +5%/级", 1 },
        { "备用燃芯", "fuel_capacity_pct", 5, "深渊最大燃料 +5%/级", 2 },
        { "节流嫩叶", "fuel_efficiency_pct", 3, "深渊燃料效率 +3%/级", 2 },
        { "修复新芽", "abyss_fuel_regen", 0.04, "深渊每秒恢复燃料 +0.04/级", 2 },
        { "安全绳结", "headstart", 8, "巨物初始距离 +8/级", 3 },
        { "迟滞花苞", "monster_slow_pct", 1, "巨物移动减速 +1%/级", 3 },
        { "轻履根须", "abyss_move_speed_pct", 2, "深渊移动速度 +2%/级", 3 },
        { "冷凝幼枝", "world_item_cooldown_pct", 2, "世界树道具冷却缩减 +2%/级", 4 },
        { "星露新生", "point_yield_pct", 3, "世界树点数收益 +3%/级", 4 },
    }
    local positions = { {-64,-64}, {64,-64}, {96,-96}, {128,-128},
        {64,64}, {96,96}, {128,128}, {-64,64}, {-96,96} }
    for index, entry in ipairs(entries) do
        local branch = tree.BRANCHES[entry[5]]
        local node = { id = "wt_early_" .. index, name = entry[1], stat = entry[2],
            value = entry[3], effect = entry[4], branch = branch.id, branchName = "起步新枝",
            rootId = branch.rootId, capstone = branch.capstone, color = branch.color,
            tier = 1, slot = index, maxLevel = 3, cost = 1, costGrowth = 1,
            parents = { branch.rootId }, unlocks = {}, position = positions[index],
            early = true, earlyIconIndex = index,
            icon = config.Paths.generatedRoot .. "world_tree_early_atlas.png" }
        tree.NODES[#tree.NODES + 1], tree.NODE_BY_ID[node.id] = node, node
    end
end

return Early
