local S = {}
S.RECIPES = {
    { tool = "magma_lance", passive = "rift_compass", name = "熔脉延展", stat = "range", value = 0.15, text = "熔脉长枪+裂隙罗盘Lv.2：范围额外+15%" },
    { tool = "crystal_saw", passive = "giant_core", name = "重型锯轮", stat = "damage", value = 0.15, text = "晶轮锯阵+巨化核心Lv.2：伤害额外+15%" },
    { tool = "prism_borer", passive = "echo_chamber", name = "分光棱镜", stat = "amount", value = 1, text = "棱镜钻束+增殖腔室Lv.2：额外1束" },
    { tool = "chain_drill", passive = "swift_bearing", name = "雷链加速", stat = "speed", value = 0.15, text = "链雷钻机+迅捷轴承Lv.2：触发速度额外+15%" },
    { tool = "frost_capsule", passive = "coolant_loop", name = "寒潮循环", stat = "cooldown", value = 0.1, text = "霜封胶囊+永冻回路Lv.2：冷却额外-10%" },
    { tool = "phoenix_fuel", passive = "power_prism", name = "余烬再生", stat = "support", value = 0.15, text = "涅槃燃芯+增幅棱镜Lv.2：恢复额外+15%" },
    { tool = "echo_charge", passive = "rift_compass", name = "深层回声", stat = "range", value = 0.15, text = "回声爆种+裂隙罗盘Lv.2：爆破范围额外+15%" },
    { tool = "magnetic_harpoon", passive = "giant_core", name = "强磁聚拢", stat = "range", value = 0.15, text = "磁轨钩钻+巨化核心Lv.2：牵引范围额外+15%" },
}
function S.Get(abyss, key, stat)
    if not abyss then return 0 end
    for _, recipe in ipairs(S.RECIPES) do
        if recipe.tool == key and recipe.stat == stat
            and (tonumber((abyss.runItems or {})[key]) or 0) > 0
            and (tonumber((abyss.passives or {})[recipe.passive]) or 0) >= 2 then return recipe.value end
    end
    return 0
end
function S.Active(abyss)
    local result = {}
    for _, recipe in ipairs(S.RECIPES) do
        if S.Get(abyss, recipe.tool, recipe.stat) > 0 then result[#result + 1] = recipe.name end
    end
    return result
end
return S
