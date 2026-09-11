-- Recovered directly from battle_tbhero.json, battle_tbskill.json and
-- language_tblang.json. Keep this separate from the generated OriginalData
-- table so the runtime behaviour and the character detail UI share one source.
local HeroSkillData = {}

HeroSkillData.ProfessionNames = {
    [1] = "神圣",
    [2] = "魔法",
    [3] = "自然",
    [4] = "元素",
}

HeroSkillData.NormalSkills = {
    [1001] = { id = 1001, damage = 4, interval = 0.5, penetration = 2, size = 0.8, range = 7, speed = 10 },
    [1002] = { id = 1002, damage = 3, interval = 0.4, penetration = 2, size = 0.8, range = 7, speed = 12 },
    [1003] = { id = 1003, damage = 3, interval = 0.3, penetration = 2, size = 0.7, range = 8, speed = 10 },
    [1004] = { id = 1004, damage = 3, interval = 0.3, penetration = 2, size = 0.7, range = 8, speed = 10 },
    [1005] = { id = 1005, damage = 6, interval = 0.5, penetration = 2, size = 0.8, range = 8, speed = 8 },
    [1006] = { id = 1006, damage = 4, interval = 0.3, penetration = 2, size = 0.7, range = 8, speed = 10 },
    [1007] = { id = 1007, damage = 2, interval = 0.35, penetration = 2, size = 0.8, range = 10, speed = 7 },
    [1008] = { id = 1008, damage = 3, interval = 0.3, penetration = 2, size = 0.7, range = 8, speed = 10 },
    [1009] = { id = 1009, damage = 3, interval = 0.3, penetration = 2, size = 0.7, range = 8, speed = 10 },
}

HeroSkillData.SpecialSkills = {
    [2001] = {
        id = 2001, name = "奥数飞弹", description = "发射奥术飞弹，对敌人造成伤害",
        icon = "image/nightgate/skill_tree/asset_6e170bf2.png", skillType = 8,
        damage = 12, count = 2, penetration = 4, size = 1.8, range = 10, speed = 12,
    },
    [2002] = {
        id = 2002, name = "秘法斩击", description = "在敌人处连续斩击三次，造成多段伤害",
        icon = "image/nightgate/skill_tree/asset_176cfafc.png", skillType = 6,
        damage = 8, count = 2, hitCount = 3, penetration = -1, size = 2.2, range = 10, speed = 12,
    },
    [2003] = {
        id = 2003, name = "元素法球", description = "凝聚元素法球，延迟爆发后造成范围伤害",
        icon = "image/nightgate/skill_tree/asset_cca5afb4.png", skillType = 7,
        damage = 12, count = 2, penetration = 1, size = 2, range = 10, speed = 12,
    },
    [2004] = {
        id = 2004, name = "圣域", description = "在敌人脚下展开圣域，造成范围伤害",
        icon = "image/nightgate/skill_tree/asset_fc73a32b.png", skillType = 5,
        damage = 12, count = 2, penetration = 1, size = 2, range = 10, speed = 12,
    },
    [2005] = {
        id = 2005, name = "天罚大剑", description = "敌人上方召唤大剑从天而降，造成范围伤害",
        icon = "image/nightgate/skill_tree/asset_c314f20d.png", skillType = 3,
        damage = 16, count = 2, penetration = -1, size = 2.6, range = 10, speed = 12,
    },
    [2006] = {
        id = 2006, name = "光辉之矛", description = "投掷光辉之矛，对敌人造成伤害",
        icon = "image/nightgate/skill_tree/asset_1931f7f6.png", skillType = 4,
        damage = 12, count = 2, penetration = 1, size = 2, range = 10, speed = 12,
    },
    [2007] = {
        id = 2007, name = "古树突刺", description = "从地面召唤古树尖刺，造成范围伤害",
        icon = "image/nightgate/skill_tree/asset_09197b8c.png", skillType = 10,
        damage = 18, count = 2, penetration = -1, size = 2.4, range = 10, speed = 12,
    },
    [2008] = {
        id = 2008, name = "火爪", description = "烈焰爪击敌人，并施加燃烧效果",
        icon = "image/nightgate/skill_tree/asset_df330e97.png", skillType = 9,
        damage = 12, count = 2, penetration = 1, size = 2, range = 10, speed = 12,
        statusDamageCoefficient = 0.2,
    },
    [2009] = {
        id = 2009, name = "寄生花种", description = "花种附着于敌人，敌人死亡时爆发范围伤害",
        icon = "image/nightgate/skill_tree/asset_47711094.png", skillType = 11,
        damage = 12, count = 2, penetration = 1, size = 2, range = 10, speed = 12,
    },
}

-- These bindings intentionally follow battle_tbhero.json exactly, including
-- Elementalist -> Fire Claw and Oracle -> Heavenly Sword in the shipped demo.
HeroSkillData.HeroBindings = {
    [10001] = { normal = 1001, special = 2001, triggerCount = 8 },
    [10002] = { normal = 1002, special = 2002, triggerCount = 10 },
    [10003] = { normal = 1003, special = 2008, triggerCount = 14 },
    [10004] = { normal = 1004, special = 2005, triggerCount = 12 },
    [10005] = { normal = 1005, special = 2005, triggerCount = 12 },
    [10006] = { normal = 1006, special = 2006, triggerCount = 12 },
    [10007] = { normal = 1007, special = 2007, triggerCount = 18 },
    [10008] = { normal = 1008, special = 2008, triggerCount = 12 },
    [10009] = { normal = 1009, special = 2009, triggerCount = 12 },
}

function HeroSkillData.Attach(hero)
    local binding = HeroSkillData.HeroBindings[hero.id]
    if not binding then return hero end
    local normal = HeroSkillData.NormalSkills[binding.normal]
    local special = HeroSkillData.SpecialSkills[binding.special]
    hero.normalSkillId = binding.normal
    hero.specialSkillId = binding.special
    hero.normalSkill = normal
    hero.specialSkill = special
    hero.specialEvery = binding.triggerCount
    if normal then
        hero.damage = normal.damage
        hero.projectileSpeed = normal.speed * 42
    end
    if special then
        hero.specialName = special.name
        hero.specialDescription = special.description
        hero.specialIcon = special.icon
        hero.specialDamage = special.damage
        hero.specialCount = special.count
        hero.specialPenetration = special.penetration
    end
    return hero
end

return HeroSkillData
