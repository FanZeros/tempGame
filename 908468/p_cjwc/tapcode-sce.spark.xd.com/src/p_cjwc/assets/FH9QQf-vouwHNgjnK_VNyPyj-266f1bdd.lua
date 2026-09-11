local ExpansionSkills = {}

local ICON_ROOT = "image/nightgate/skill_tree/generated/"

-- These nodes extend the original 78-node tree without changing any source-derived
-- IDs, costs, levels or positions. Parents only need to be lit once, matching the
-- release tree's unlock rule.
ExpansionSkills.Definitions = {
    {
        id = "x_cursor_echo", branch = 1, name = "回响指针",
        description = "指针攻击有概率在原位置追加一次65%伤害的回响。",
        icon = ICON_ROOT .. "expansion_cursor_echo.png", parents = { "1_3_2" },
        survivorNight = 8, attribute = 0, effectTarget = 0, percent = true,
        costs = { 450, 1200 }, values = { 15, 15 }, effect = "cursorEchoChance",
        levelTexts = { "回响概率 +15%", "回响概率再 +15%" }, position = { -160, 640 },
    },
    {
        id = "x_cursor_storm", branch = 1, name = "四壁雷鸣",
        description = "每8次指针攻击，对四个方向最危险的怪物各追加一次雷击。",
        icon = ICON_ROOT .. "expansion_cursor_echo.png", parents = { "x_cursor_echo" },
        survivorNight = 15, attribute = 0, effectTarget = 0, percent = false,
        costs = { 4500 }, values = { 8 }, effect = "cursorStormEvery",
        levelTexts = { "每8次攻击触发四壁雷鸣" }, position = { -160, 800 },
    },
    {
        id = "x_wall_thorns", branch = 2, name = "荆棘城垒",
        description = "怪物成功攻击城墙时，会受到随全局伤害成长的反击。",
        icon = ICON_ROOT .. "expansion_wall_laststand.png", parents = { "2_4_3" },
        survivorNight = 8, attribute = 0, effectTarget = 0, percent = false,
        costs = { 600, 1800 }, values = { 4, 4 }, effect = "wallThornsDamage",
        levelTexts = { "城墙反击伤害 +4", "城墙反击伤害再 +4" }, position = { 800, -160 },
    },
    {
        id = "x_wall_laststand", branch = 2, name = "不屈防线",
        description = "每夜首次受到致命伤害时，城墙保留25%耐久并震退怪群。",
        icon = ICON_ROOT .. "expansion_wall_laststand.png", parents = { "x_wall_thorns" },
        survivorNight = 15, attribute = 0, effectTarget = 0, percent = false,
        costs = { 5000 }, values = { 1 }, effect = "wallLastStandEnabled",
        levelTexts = { "每夜获得1次不屈防线" }, position = { 960, -160 },
    },
    {
        id = "x_hero_resonance", branch = 3, name = "元素共鸣",
        description = "所有英雄更快积蓄第二技能，每级少需1次普通攻击。",
        icon = ICON_ROOT .. "expansion_hero_resonance.png", parents = { "3_4_2" },
        survivorNight = 8, attribute = 0, effectTarget = 2, percent = false,
        costs = { 600, 1800 }, values = { 1, 1 }, effect = "heroSpecialAcceleration",
        levelTexts = { "第二技能蓄力 -1次", "第二技能蓄力再 -1次" }, position = { -320, -800 },
    },
    {
        id = "x_hero_unity", branch = 3, name = "四方合击",
        description = "英雄累计释放4次第二技能后，在战场中央引爆联合奥术。",
        icon = ICON_ROOT .. "expansion_hero_resonance.png", parents = { "x_hero_resonance" },
        survivorNight = 15, attribute = 0, effectTarget = 2, percent = false,
        costs = { 6000 }, values = { 4 }, effect = "heroUnityEvery",
        levelTexts = { "每4次英雄技能触发联合奥术" }, position = { -320, -960 },
    },
    {
        id = "x_archer_ricochet", branch = 4, name = "折射箭",
        description = "箭矢命中后有概率自动转向同一侧的另一名有效目标。",
        icon = ICON_ROOT .. "expansion_archer_barrage.png", parents = { "4_4_4" },
        survivorNight = 8, attribute = 0, effectTarget = 1, percent = true,
        costs = { 500, 1500 }, values = { 15, 15 }, effect = "archerRicochetChance",
        levelTexts = { "折射概率 +15%", "折射概率再 +15%" }, position = { -800, -320 },
    },
    {
        id = "x_archer_barrage", branch = 4, name = "齐射号令",
        description = "累计12轮弓箭攻击后，四面墙同时向各自目标发射强化箭。",
        icon = ICON_ROOT .. "expansion_archer_barrage.png", parents = { "x_archer_ricochet" },
        survivorNight = 15, attribute = 0, effectTarget = 1, percent = false,
        costs = { 5500 }, values = { 12 }, effect = "archerBarrageEvery",
        levelTexts = { "每12轮攻击触发四墙齐射" }, position = { -960, -320 },
    },
}

local function getEffectTotal(levels, effect)
    local total = 0
    for index = 1, #ExpansionSkills.Definitions do
        local definition = ExpansionSkills.Definitions[index]
        if definition.effect == effect then
            local level = math.min(math.max(0, math.floor(tonumber(levels and levels[definition.id]) or 0)), #definition.values)
            for valueIndex = 1, level do
                total = total + (tonumber(definition.values[valueIndex]) or 0)
            end
        end
    end
    return total
end

function ExpansionSkills.ApplyStats(stats, levels)
    stats.cursorEchoChance = getEffectTotal(levels, "cursorEchoChance") / 100
    stats.cursorStormEvery = math.max(0, math.floor(getEffectTotal(levels, "cursorStormEvery") + 0.5))
    stats.wallThornsDamage = getEffectTotal(levels, "wallThornsDamage")
    stats.wallLastStandEnabled = getEffectTotal(levels, "wallLastStandEnabled") > 0
    stats.heroSpecialAcceleration = math.max(0, math.floor(getEffectTotal(levels, "heroSpecialAcceleration") + 0.5))
    stats.heroUnityEvery = math.max(0, math.floor(getEffectTotal(levels, "heroUnityEvery") + 0.5))
    stats.archerRicochetChance = getEffectTotal(levels, "archerRicochetChance") / 100
    stats.archerBarrageEvery = math.max(0, math.floor(getEffectTotal(levels, "archerBarrageEvery") + 0.5))
end

return ExpansionSkills
