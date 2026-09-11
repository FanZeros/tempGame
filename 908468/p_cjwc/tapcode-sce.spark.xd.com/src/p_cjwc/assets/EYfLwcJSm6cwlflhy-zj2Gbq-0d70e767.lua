-- Values in this file are transcribed from the shipped Nightgate Defense demo
-- battle tables. Keep this module data-only so battle rules stay auditable.

local OriginalData = require("nightgate.OriginalData")
local HeroSkillData = require("nightgate.HeroSkillData")

local Config = {}

Config.TITLE = "Nightgate Defense"
Config.MAX_ENEMIES = 240
Config.MAX_PROJECTILES = 260
Config.MAX_PARTICLES = 260
Config.MAX_FLOATING_TEXT = 70

-- The desktop demo's tables are authored around a slower presentation than the
-- mobile runtime produced at 1.0. Apply one shared simulation scale so movement,
-- spawning, attacks, projectiles, pickups and battle VFX stay in sync.
Config.GAME_TIME_SCALE = 0.58

Config.COLORS = {
    ink = { 13, 12, 18, 255 },
    panel = { 35, 32, 39, 248 },
    panelLight = { 58, 54, 62, 255 },
    border = { 119, 111, 125, 255 },
    grass = { 47, 102, 46, 255 },
    wall = { 24, 23, 32, 255 },
    wallEdge = { 56, 52, 67, 255 },
    text = { 239, 235, 224, 255 },
    muted = { 176, 169, 178, 255 },
    gold = { 255, 174, 40, 255 },
    crystal = { 207, 132, 255, 255 },
    danger = { 210, 48, 45, 255 },
    hp = { 154, 38, 29, 255 },
    unlocked = { 58, 196, 82, 255 },
    locked = { 194, 58, 54, 255 },
    cursor = { 215, 79, 30, 255 },
}

Config.SIDES = {
    { id = "top", name = "上方城墙", dx = 0, dy = -1 },
    { id = "right", name = "右方城墙", dx = 1, dy = 0 },
    { id = "bottom", name = "下方城墙", dx = 0, dy = 1 },
    { id = "left", name = "左方城墙", dx = -1, dy = 0 },
}

Config.ARCHER = {
    id = 20001,
    name = "弓箭手-艾琳",
    icon = "image/nightgate/heroes/asset_1b61c80a.png",
    sprite = "image/nightgate/heroes/elfsharpshooter_6bad7f61.png",
    damage = 1,
    interval = 1.0,
    projectileSpeed = 410,
}

-- Original archer leaders and traits from battle_tbhero.json/battle_tbtrait.json.
Config.ARCHERS = {
    {
        id = 20001, name = "弓箭手-艾琳", unlockAttribute = 0,
        icon = "image/nightgate/heroes/asset_1b61c80a.png", sprite = Config.ARCHER.sprite,
        passiveId = 80000, passiveUnlockAttribute = 69, passiveAttribute = 68, passiveValue = 2,
    },
    {
        id = 20002, name = "弓箭手-米娅", unlockAttribute = 70,
        icon = "image/nightgate/items/-_c1eef605.png", sprite = Config.ARCHER.sprite,
        passiveId = 80001, passiveUnlockAttribute = 0, passiveAttribute = 67, passiveValue = 1.5,
    },
}
Config.ARCHER_BY_ID = {}
for index = 1, #Config.ARCHERS do
    Config.ARCHER_BY_ID[Config.ARCHERS[index].id] = Config.ARCHERS[index]
end

Config.HERO = {
    name = "奥术师",
    sprite = "image/nightgate/heroes/beginnerenchanter_ed5cc520.png",
    damage = 4,
    interval = 1.0,
    specialEvery = 8,
}

Config.HEROES = OriginalData.HeroDefinitions
Config.HERO_BY_ID = {}
Config.HERO_BY_UNLOCK_ATTRIBUTE = {}
for index = 1, #Config.HEROES do
    local hero = Config.HEROES[index]
    HeroSkillData.Attach(hero)
    Config.HERO_BY_ID[hero.id] = hero
    Config.HERO_BY_UNLOCK_ATTRIBUTE[hero.unlockAttribute] = hero
end

Config.CURSOR = {
    sprite = "image/nightgate/input/cursor_d7219acf.png",
    baseDamage = 3,
    -- Slower opening cadence requested for the mobile port. Skill-tree
    -- cooldown reductions still apply to this original base interval.
    interval = 0.95,
    radius = 42,
}

-- Keep the recovered level budgets intact while giving the first three nights
-- more breathing room on a touch screen. Later nights use the original pace.
Config.EARLY_SPAWN_MULTIPLIER = { [1] = 1.25, [2] = 1.16, [3] = 1.08 }

-- Recovered verbatim from battle_tbprestige.json. The nine original permanent
-- blessings are awarded in three tiers according to the night reached when
-- performing a prestige. The repeatable prestige tree remains additional growth.
Config.PRESTIGE_UNLOCK_NIGHT = 10
Config.PRESTIGE_BLESSINGS = {
    { night = 10, attribute = 64, value = 50, name = "结算金币额外获得", suffix = "%" },
    { night = 10, attribute = 65, value = 50, name = "结算晶石额外获得", suffix = "%" },
    { night = 10, attribute = 59, value = 2, name = "每晚额外召唤晶石怪", suffix = "" },
    { night = 20, attribute = 7, value = 10, name = "城墙闪避", suffix = "%" },
    { night = 20, attribute = 30, value = 10, name = "指针造成两次伤害概率", suffix = "%" },
    { night = 20, attribute = 28, value = 15, name = "指针作用范围加成", suffix = "%" },
    { night = 30, attribute = 34, value = 5, name = "弓箭手进入狂暴状态概率", suffix = "%" },
    { night = 30, attribute = 35, value = 50, name = "箭矢对 Boss 增伤", suffix = "%" },
    { night = 30, attribute = 66, value = 1, name = "随机召龙助战", suffix = "" },
}

-- Original demo monster values (battle_tbmonster.json).
Config.MONSTERS = {
    ghost = { name = "幽灵", sprite = "image/nightgate/monsters/graverevenant_84d26f6a.png", hp = 8, speed = 0.8, wallDamage = 2, attackInterval = 1.5, reward = 1, difficulty = 1, size = 29 },
    minotaur = { name = "牛头人", sprite = "image/nightgate/monsters/powerfulyak_acd1d5c0.png", hp = 16, speed = 0.6, wallDamage = 4, attackInterval = 2.0, reward = 2, difficulty = 2, size = 38 },
    golem = { name = "石头人", sprite = "image/nightgate/monsters/adamantium_golem_2d61cd08.png", hp = 25, speed = 0.5, wallDamage = 2, attackInterval = 2.0, reward = 3, difficulty = 3, size = 42 },
    skeleton = { name = "小骷髅", sprite = "image/nightgate/monsters/decrepitbones_fa91e8da.png", hp = 6, speed = 1.2, wallDamage = 2, attackInterval = 1.0, reward = 1, difficulty = 1, size = 25 },
    twinSkeleton = { name = "双头骷髅", sprite = "image/nightgate/monsters/ossifiedslayer_620dfc56.png", hp = 15, speed = 0.7, wallDamage = 3, attackInterval = 1.0, reward = 4, difficulty = 2, size = 38 },
    bull = { name = "冲锋大牛", sprite = "image/nightgate/monsters/armoredgoliath_9a3ad4e6.png", hp = 35, speed = 0.6, wallDamage = 5, attackInterval = 2.0, reward = 1, difficulty = 4, size = 45 },
    wolf = { name = "骑狼哥布林", sprite = "image/nightgate/monsters/goblinwolfrider_45885915.png", hp = 15, speed = 0.8, wallDamage = 2, attackInterval = 1.5, reward = 1, difficulty = 1, size = 34 },
    axeGoblin = { name = "巨斧哥布林", sprite = "image/nightgate/monsters/orcreaver_a68233c0.png", hp = 19, speed = 0.7, wallDamage = 10, attackInterval = 4.0, reward = 2, difficulty = 2, size = 38 },
    bomber = { name = "炸弹人", sprite = "image/nightgate/monsters/bazzle_a5028421.png", hp = 25, speed = 0.6, wallDamage = 15, attackInterval = 1.0, reward = 3, difficulty = 2, size = 34 },
    crystal = { name = "低品质晶石怪", sprite = "image/nightgate/monsters/rind_eb07489a.png", hp = 6, speed = 0.8, wallDamage = 2, attackInterval = 1.5, reward = 0, crystal = 1, difficulty = 1, size = 28 },
    stoneBoss = { name = "石头人首领", sprite = "image/nightgate/monsters/bonegolem_62642797.png", hp = 180, speed = 0.5, wallDamage = 50, attackInterval = 3.0, reward = 30, difficulty = 50, size = 74, boss = true },
    goblinBoss = { name = "哥布林王", sprite = "image/nightgate/monsters/orccaptain_7fb78bc0.png", hp = 300, speed = 0.5, wallDamage = 80, attackInterval = 3.0, reward = 40, difficulty = 50, size = 78, boss = true },
}

-- Nights 1-10 from battle_tblevel.json. hp/atk are percentage additions.
Config.LEVELS = {
    { duration = 12, difficulty = 18, hp = 0, atk = 0, crystal = 0, waves = { "ghost" } },
    { duration = 8, difficulty = 54, hp = 30, atk = 0, crystal = 1, waves = { "ghost", "minotaur" } },
    { duration = 7, difficulty = 90, hp = 100, atk = 2, crystal = 1, waves = { "ghost", "minotaur" } },
    { duration = 7, difficulty = 158, hp = 210, atk = 3, crystal = 1, waves = { "ghost", "minotaur", "golem", "bomber" } },
    { duration = 10, difficulty = 271, hp = 430, atk = 14, crystal = 2, boss = "stoneBoss", waves = { "ghost", "minotaur", "stoneBoss" } },
    { duration = 6.4, difficulty = 294, hp = 710, atk = 30, crystal = 2, waves = { "minotaur", "skeleton" } },
    { duration = 15, difficulty = 362, hp = 975, atk = 48, crystal = 2, waves = { "skeleton", "wolf" } },
    { duration = 6.8, difficulty = 430, hp = 1980, atk = 68, crystal = 3, waves = { "golem", "twinSkeleton", "bull" } },
    { duration = 7, difficulty = 498, hp = 3025, atk = 90, crystal = 3, waves = { "golem", "axeGoblin", "bomber" } },
    { duration = 15, difficulty = 720, hp = 3810, atk = 114, crystal = 3, boss = "goblinBoss", waves = { "ghost", "axeGoblin", "goblinBoss", "wolf", "twinSkeleton" } },
}

-- Replace the early vertical-slice subset with the shipped 30-night campaign.
-- The two remaining level rows are the final-night encounter and an internal test map.
Config.MONSTERS = OriginalData.MonsterDefinitions
Config.MONSTER_WAVES = OriginalData.MonsterWaves
Config.LEVELS = {}
for index = 1, OriginalData.CampaignLevelCount do
    Config.LEVELS[index] = OriginalData.Levels[index]
end
Config.CAMPAIGN_NIGHT_COUNT = #Config.LEVELS
Config.FINAL_NIGHT_LEVEL = OriginalData.Levels[OriginalData.FinalNightLevelIndex]
Config.TEST_LEVEL = OriginalData.Levels[OriginalData.TestLevelIndex]
Config.FINAL_NIGHT_DIFFICULTIES = OriginalData.FinalNightDifficulties
Config.MAX_FINAL_DIFFICULTY = 5

Config.EQUIPMENT_BY_ID = OriginalData.EquipmentById
Config.EQUIPMENT_ORDER = OriginalData.EquipmentOrder
Config.EQUIPMENT_RECYCLE = OriginalData.RecycleByQuality
Config.EQUIPMENT_STRENGTHEN = OriginalData.Strengthen
Config.EQUIPMENT_QUALITY_NAMES = OriginalData.QualityNames
Config.EQUIPMENT_CAPACITY = OriginalData.InventoryCapacity
Config.LEVEL_DROPS = OriginalData.LevelDrops

-- Save migration for the six placeholder entries used by the first mobile build.
Config.LEGACY_EQUIPMENT_MAP = { 1000, 2000, 3000, 4000, 1001, 2002 }

return Config
