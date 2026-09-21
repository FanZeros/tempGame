local Config = {}

-- Formal-project preview profile. This is intentionally enabled only so the
-- owner can verify today's endgame update before release; disable both max
-- flags before publishing the public build.
Config.TEST_MAX_SKILL_TREE = false
Config.TEST_MAX_WORLD_TREE = false
Config.TEST_WORLD_TREE_RESET_VERSION = 0
Config.TEST_BUILD_LABEL = ""

Config.DESIGN_WIDTH = 480
Config.DESIGN_HEIGHT = 270
Config.TILE_SIZE = 16
Config.SURFACE_Y = 10
-- Center the 10 px wide player inside one 16 px tile column. At x=0 the
-- collision feet straddle columns -1 and 0, so mining only column 0 cannot
-- make the player fall naturally.
Config.PLAYER_SPAWN_X = 8
Config.STAR_BARRIER_Y = 330
Config.FINAL_DENSITY_COMPRESSION = 8
-- Deep Abyss uses the same authored ten layers as the final density, but
-- stretches every layer to three times the final-density travel distance.
Config.ABYSS_LAYER_DEPTH_MULTIPLIER = 3
Config.PRESTIGE_FACTOR = 5
Config.STARDROPS_FOR_FINAL_DENSITY = 10
Config.STARMETAL_STARDROP_CHANCE = 20
Config.GUIDE_PAGE_COUNT = 7
-- The complete authored badge tree costs 2792 after level scaling. Thirty
-- badges across ten layers and ten densities leaves a small safety margin.
-- Saves that already claimed 25-badge layers are backfilled by State.
Config.LEGACY_MISSION_BADGES_PER_LAYER = 25
Config.MISSION_BADGES_PER_LAYER = 30
-- Density 6 is the first major iridium wall. Native veins remain fastest,
-- while this pity counter guarantees steady progress through unlucky routes.
Config.IRIDIUM_PITY_MIN_DENSITY = 6
Config.IRIDIUM_PITY_BLOCKS = 10
-- Combat rewards remain functional beyond these limits; only redundant
-- particles/drop sprites are reduced or merged to protect long endless runs.
Config.MAX_TRANSIENT_EFFECTS = 280
Config.MAX_ORE_DROP_EFFECTS = 120
-- Refinery ticks drain at least one raw gem plus a percentage of large
-- backlogs so late-game production cannot grow without bound.
Config.REFINERY_BACKLOG_PERCENT = 2
-- Guaranteed one-time star-dust rewards break the circular dependency where
-- the player needed StarDebris upgrades before reaching the rare Starmetal
-- layers that used to be its only source.
Config.STAR_DEBRIS_MILESTONES = {
    [3] = 3,
    [5] = 5,
    [7] = 7,
    [10] = 10,
}

Config.Controls = {
    moveX = 48, moveY = 220, moveRadius = 32, moveDeadzone = 8, moveTouchPadding = 6,
    aimX = 405, aimY = 219, aimRadius = 34, aimTouchPadding = 2,
    laserX = 323, laserY = 193, laserW = 40, laserH = 34,
    -- Keep the lock above the drilling pad.  Its old lower-right placement
    -- left only a one-pixel gap from the aim touch zone, so a thumb landing on
    -- the rim could start auto drilling instead of steering the drill.
    autoX = 442, autoY = 148, autoW = 32, autoH = 36,
    jumpX = 389, jumpY = 150, jumpW = 46, jumpH = 30,
    oreHudX = 104, oreHudWidth = 212, oreHudY = 238,
    oreHudMaxPerRow = 7, oreHudRowStep = 21, oreHudItemHeight = 19,
}

Config.Abyss = {
    floorDepthTiles = 12,
    halfWidthTiles = 7,
    exitHealthMultiplier = 3.2,
    difficultyExitInheritance = 0.60,
    exitHalfWidthTiles = 1,
    exitAssistRadius = 34,
    exitAssistAbove = 38,
    exitAssistBelow = 20,
    exitAssistStrength = 7,
    exitAssistHorizontalDamping = 0.42,
    exitAssistVerticalDamping = 0.72,
    coinsPerTile = 1,
    coinTileDropChance = 20,
    floorClearCoins = 2,
    chestCoinMin = 6,
    chestCoinMax = 10,
    enemyCoinDropChance = 25,
    enemyCoinAmount = 1,
    eliteCoinAmount = 2,
    coinPickupSpeed = 155,
    coinMagnetRadius = 72,
    enemyBaseCount = 2,
    enemyCountPerCycle = 1,
    -- Deep floors may schedule hundreds of encounters, but only a bounded
    -- number may remain active at once.  Difficulty continues through enemy
    -- health/speed and replacement spawns without producing O(skills*enemies)
    -- frame spikes on floor 300+.
    maxActiveEnemies = 18,
    maxEnemyProjectiles = 48,
    enemyContactFuelPct = 7,
    enemyFuelDropPct = 8,
    enemySpawnDelay = 1.4,
    -- Every tenth floor from 30 onward becomes a non-blocking beast tide.
    -- The exit can still be opened normally, while players who stay to clear
    -- the marked quota earn a guaranteed equipment drop.
    hordeFirstFloor = 30,
    hordeInterval = 10,
    hordeBaseExtraEnemies = 8,
    hordeExtraEnemiesPerTier = 2,
    hordeMaxExtraEnemies = 24,
    hordeBaseKillGoal = 8,
    hordeKillGoalPerTier = 1,
    hordeMaxKillGoal = 16,
    hordeSpawnDelay = 0.48,
    hordeSpawnDelayPerTier = 0.018,
    hordeSpawnDelayMin = 0.22,
    hordeHealthPerTier = 0.12,
    hordeSpeedPerTier = 0.035,
    hordeDamagePerTier = 0.04,
    hordeBonusCoinsPerKill = 1,
    towerLaserMax = 100,
    towerLaserDrain = 18,
    towerLaserRegen = 9,
    towerLaserCooldown = 6,
    towerLaserCapacityCap = 200,
    towerLaserDamageCap = 2.5,
    towerLaserPierceCap = 3,
    towerLaserRange = 150,
    towerLaserDamageScale = 7.5,
    flashDistance = 48,
    shopBaseCost = 30,
    shopCostPerDifficulty = 8,
    shopCostCap = 110,
    inscriptionShopInterval = 50,
    inscriptionShopChance = 70,
    inscriptionShopPurchaseLimit = 2,
    inscriptionShopRerollCosts = { 30, 60, 100 },
    merchantFloorInterval = 50,
    merchantOfferCount = 4,
    merchantFuelRestorePct = 50,
    equipmentStorageCapacity = 60,
    lootDropChanceMultiplier = 0.32,
    lootPityTiles = 170,
    chestEquipmentChance = 16,
    initialGap = 110,
    catchDistance = 8,
    warningGap = 58,
    catchUpGap = 125,
    catchUpRate = 0.82,
    baseSpeed = 10.5,
    acceleration = 0.09,
    maxSpeed = 60,
    adaptiveSpeedStart = 0.72,
    adaptiveSpeedGrowth = 0.0055,
    adaptiveSpeedMax = 0.9,
    tileHealthMultiplier = 2,
    -- Difficulty advances after 20/40/60/80/100, then every 50 floors.
    -- These replace the old ten-floor quadratic health curve.
    difficultyEarlyInterval = 20,
    difficultyEarlyCap = 5,
    difficultyDeepInterval = 50,
    difficultyTilePerEarlyStage = 0.12,
    difficultyEnemyHealthPerEarlyStage = 0.10,
    difficultyEnemyDamagePerEarlyStage = 0.04,
    difficultyChaserSpeedPerEarlyStage = 0.015,
    difficultyTilePerDeepStage = 1.18,
    difficultyEnemyHealthPerDeepStage = 1.15,
    difficultyEnemyDamagePerDeepStage = 1.06,
    difficultyChaserSpeedPerDeepStage = 1.02,
    difficultyChaserSpeedCap = 1.30,
    difficultyEliteChancePerEarlyStage = 4,
    difficultyEliteChancePerDeepStage = 3,
    difficultyEliteChanceCap = 45,
    difficultyMaxNormalEnemies = 8,
    hardcoreTileHealthMultiplier = 1.45,
    hardcoreChaserSpeedMultiplier = 1.18,
    hardcoreEnemyHealthMultiplier = 1.35,
    hardcoreEnemySpeedMultiplier = 1.12,
    hardcoreEnemyDamageMultiplier = 1.3,
    hardcoreExtraEnemies = 2,
    hardcoreBossDamageMultiplier = 1.35,
    hardcoreBossCooldownMultiplier = 0.78,
    hardcoreScoreMultiplier = 1.5,
    hardcorePointMultiplier = 1.3,
    jumpSpeed = 250,
    jumpCooldown = 0.16,
    jumpCoyoteTime = 0.11,
    dodgeCooldown = 3.2,
    dodgeDuration = 0.22,
    perfectDodgeWindow = 0.3,
    firstBossAttackAt = 5.5,
    bossAttackCooldown = 9,
    bossAttackCooldownMin = 3.2,
    bossAttackCooldownRamp = 0.03,
    bossTelegraph = 1.45,
    bossTelegraphMin = 0.7,
    bossTelegraphRamp = 0.004,
    bossFuelDamagePct = 16,
    -- High-level cooldown multipliers can otherwise create a new long-lived
    -- capstone object every few hundredths of a second.  The renderer uses a
    -- bounded cadence and folds skipped casts back into damage.
    minCapstoneVisualCooldown = 0.18,
    -- All Deep Abyss tool cooldown layers share one final floor.  Individual
    -- passives, equipment, inscriptions and World Tree bonuses still stack,
    -- but can never reduce the original cooldown by more than 70%.
    minToolCooldownMultiplier = 0.30,
    -- Every floor remains in the local crash-safe checkpoint.  Cloud writes
    -- are less frequent because invoking the platform bridge on every very
    -- fast late-game floor caused visible multi-second stalls.
    cloudCheckpointFloorInterval = 15,
    retainedFloorHistory = 2,
    firstMutationAt = 14,
    mutationInterval = 22,
    minimumRewardTime = 8,
    secondsPerPoint = 15,
    depthPerPoint = 45,
    pointFloorExponent = 0.72,
    pointFloorScale = 2.2,
    pointTimeScale = 3,
}

Config.CapstoneDamageMultipliers = {
    FallingPickaxe = 12,
    TermiteDrones = 8,
    Molenir = 20,
    TheWorm = 4,
}

Config.Paths = {
    imageRoot = "image/diggin/original/",
    generatedRoot = "image/diggin/generated/",
    audioRoot = "audio/diggin/original/",
    fontLatin = "Fonts/diggin/bitcell_memesbruh03.ttf",
    fontChinese = "Fonts/diggin/fusion-pixel-12px-proportional-zh_hans.ttf",
    logo = "image/diggin/generated/ui/title_cn.png",
    surface = "image/diggin/original/Tilesets/Main/bgTest.png",
    parallax1 = "image/diggin/original/Tilesets/Main/parallax_1.png",
    parallax2 = "image/diggin/original/Tilesets/Main/parallax_2.png",
    player = "image/diggin/original/Player Assets/animacija_16px-Sheet.png",
    playerHit = "image/diggin/original/Player Assets/hit_sprite.png",
    playerHit2 = "image/diggin/original/Player Assets/hit_sprite_2.png",
    playerLaser = "image/diggin/original/Player Assets/dougLasering.png",
    drill = "image/diggin/original/Player Assets/animacija_busilica_16px-Sheet.png",
    skillAtlas = "image/diggin/original/UI/skilltreeNew.png",
    skillBackground = "image/diggin/original/UI/skillTreeBackgroundSheet.png",
    chestOpen = "image/diggin/original/Tilesets/Main/chest_22x22open.png",
    goldenDrill = "image/diggin/generated/rewards/golden_drill.png",
    stardrop = "image/diggin/original/UI/star1.png",
    abyssChaser = "image/diggin/generated/abyss/abyss_chaser-v1.png",
    abyssGate = "image/diggin/generated/abyss/abyss_gate-v1.png",
    abyssEventGolden = "image/diggin/generated/abyss/event_golden_layer-v1.png",
    abyssEventExplosive = "image/diggin/generated/abyss/event_explosive_vein-v1.png",
    abyssEventChest = "image/diggin/generated/abyss/event_chest_cluster-v1.png",
    abyssEventRisk = "image/diggin/generated/abyss/event_high_risk-v1.png",
    abyssLootAtlas = "image/diggin/generated/abyss/abyss_loot_rarity_atlas-v1.png",
    abyssEquipmentAtlas = "image/diggin/generated/abyss/abyss_equipment_atlas-v2.png",
    abyssWorldItemAtlas = "image/diggin/generated/world_tree/abyss_world_items_atlas-v2.png",
    abyssTowerCoin = "image/diggin/generated/abyss_tower/pickup_coin-v1.png",
    abyssTowerFuel = "image/diggin/generated/abyss_tower/pickup_fuel-sheet-v1.png",
    abyssTowerBlink = "image/diggin/generated/abyss_tower/fx_blink_dash-sheet-v1.png",
    abyssTowerExit = "image/diggin/generated/abyss_tower/floor_exit_portal-sheet-v1.png",
    abyssTowerCore = "image/diggin/generated/abyss_tower/rift_core_break-sheet-v1.png",
    abyssTowerProjectile = "image/diggin/generated/abyss_tower/enemy_wisp_projectile-sheet-v1.png",
    abyssTowerShop = "image/diggin/generated/abyss_tower/shop_terminal-sheet-v1.png",
    abyssMerchantShopkeeper = "image/diggin/generated/abyss_shop/merchant_counter-v1.png",
    abyssTowerChestItems = "image/diggin/generated/abyss_tower/chest_items-atlas-v1.png",
    abyssTowerRouteIcons = "image/diggin/generated/abyss_tower/route_icons-atlas-v1.png",
    abyssTowerEnemyRat = "image/diggin/generated/abyss_tower/enemy_rat-v1.png",
    abyssTowerEnemySpider = "image/diggin/generated/abyss_tower/enemy_ash_spider-v1.png",
    abyssTowerEnemyWisp = "image/diggin/generated/abyss_tower/enemy_glowing_wisp-v1.png",
    abyssTowerEnemyCentipede = "image/diggin/generated/abyss_tower/enemy_fire_centipede-v1.png",
    abyssTowerEnemyMimic = "image/diggin/generated/abyss_tower/enemy_hungry_mimic-v1.png",
    abyssTowerEnemySkull = "image/diggin/generated/abyss_tower/enemy_unholy_skull-v1.png",
    abyssTowerEnemyBurst = "image/diggin/generated/abyss_tower/fx_enemy_burst-sheet-v1.png",
    abyssInscriptionAtlas = "image/diggin/generated/abyss_inscriptions/inscription_atlas-25-v1.png",
    worldTree = "image/diggin/generated/world_tree/world_tree-v1.png",
    worldTreePoint = "image/diggin/generated/world_tree/world_tree_point-v2.png",
}

Config.Audio = {
    menu = "audio/diggin/original/Music/Main Menu/Diggin Main Menu.ogg",
    skill = "audio/diggin/original/Music/Skill Tree/Skill TreeOST.ogg",
    gameplay = {
        "audio/diggin/original/Music/Gameplay/DENS1.ogg",
        "audio/diggin/original/Music/Gameplay/DENS2.ogg",
        "audio/diggin/original/Music/Gameplay/DENS3.ogg",
        "audio/diggin/original/Music/Gameplay/DENS4.ogg",
        "audio/diggin/original/Music/Gameplay/DENS5.ogg",
        "audio/diggin/original/Music/Gameplay/DENS6.ogg",
        "audio/diggin/original/Music/Gameplay/DENS7.ogg",
        "audio/diggin/original/Music/Gameplay/DENS8.ogg",
        "audio/diggin/original/Music/Gameplay/DENS9-1.ogg",
        "audio/diggin/original/Music/Gameplay/DENS9-2.ogg",
        "audio/diggin/original/Music/Gameplay/DENS10.ogg",
    },
    drill = "audio/diggin/original/Sfx/drillLoop.mp3",
    hit = "audio/diggin/original/Sfx/hitStoneSfx.ogg",
    breakTile = "audio/diggin/original/Sfx/StoneBroken.ogg",
    pickup = "audio/diggin/original/Sfx/pickUpSfx.ogg",
    click = "audio/diggin/original/Sfx/MouseUp.ogg",
    deny = "audio/diggin/original/Sfx/denySFX.ogg",
    explosion = "audio/diggin/original/Sfx/explosionSfx.ogg",
    overdrive = "audio/diggin/original/Sfx/Overdrive.ogg",
    overheat = "audio/diggin/original/Sfx/Overheat.ogg",
    starmetal = "audio/diggin/original/Sfx/hitStarmetal.mp3",
    stardrop = "audio/diggin/original/Sfx/starstone.mp3",
    mission = "audio/diggin/original/Sfx/missionClaim.ogg",
}

Config.Palette = {
    ink = { 48, 44, 46, 255 },
    inkSoft = { 57, 49, 75, 255 },
    cream = { 235, 248, 215, 255 },
    creamDim = { 185, 204, 171, 255 },
    cyan = { 40, 204, 219, 255 },
    orange = { 244, 148, 30, 255 },
    red = { 225, 59, 62, 255 },
    green = { 96, 184, 82, 255 },
    purple = { 143, 71, 141, 255 },
    gold = { 244, 187, 43, 255 },
    shadow = { 18, 14, 18, 230 },
}

Config.BranchColors = {
    core = { 238, 214, 121, 255 },
    damage = { 231, 70, 69, 255 },
    fuel = { 79, 206, 113, 255 },
    quake = { 244, 156, 39, 255 },
    world = { 48, 190, 219, 255 },
}

-- Dominant colours sampled from the opaque material cell (1, 6) of each
-- recovered Godot terrain atlas. Dirt/rock hit particles use their own source
-- material instead of the previous generic orange placeholder.
Config.LayerParticleColors = {
    [0] = { 94, 54, 67, 255 },
    [1] = { 124, 96, 99, 255 },
    [2] = { 90, 83, 83, 255 },
    [3] = { 57, 49, 75, 255 },
    [4] = { 60, 89, 86, 255 },
    [5] = { 57, 49, 75, 255 },
    [6] = { 57, 49, 75, 255 },
    [7] = { 94, 54, 67, 255 },
    [9] = { 79, 84, 107, 255 },
    [10] = { 57, 123, 68, 255 },
    [11] = { 57, 49, 75, 255 },
    [12] = { 49, 38, 42, 255 },
}

Config.BaseStats = {
    drill_damage = 3,
    drill_speed = 1,
    critical_chance = 0,
    critical_damage_multiplier = 1.5,
    movement_speed = 20,
    fuel_amount = 10,
    fuel_efficiency = 1,
    fuel_regeneration = 0,
    fov_radius = 32,
    world_width = 5,
    resource_gain = 0,
}

Config.ActiveBaseStats = {
    dynamite = { damage = 250, cooldown = 5, radius = 16, amount = 1 },
    shockwave = { damage = 150, cooldown = 5, radius = 32 },
    aftershocks = { damage = 100, cooldown = 5, tiles = 5, amount = 1, crit_proc = 0 },
    shrapnel_debris = { damage = 100, cooldown = 5, amount = 5 },
    pickarang = { damage = 250, cooldown = 5, amount = 1 },
    drill_drones = { damage = 100, cooldown = 5, amount = 1, attack_speed = 1, last_ditch = 0 },
    drill_missile = { damage = 400, cooldown = 5, amount = 1, explosion_radius = 32 },
    pickaxe_orbit = { damage = 120, cooldown = 5, amount = 1 },
    bouncing_ball = { damage = 200, cooldown = 5, amount = 1, lifetime = 3 },
    bullet_worms = { damage = 80, cooldown = 10, amount = 2 },
    boomstone = { chance = 1, damage = 60, radius = 32 },
    feverstone = { chance = 0.2, duration = 3, multiplier = 2 },
    fuelstone = { chance = 1, fuel_increase = 4 },
    overdrive = {
        overdrive_efficiency = 1,
        overdrive_regeneration = 1,
        overdrive_amount = 10,
        overdrive_strength = 4,
        overdrive_drill_scaling = 25,
    },
    overheat = {
        laser_efficiency = 1,
        laser_regeneration = 1,
        laser_amount = 10,
        laser_strength = 100,
        energy_per_drill_hit = 0,
        laser_drill_scaling = 150,
    },
    augment_stone = { additional_amount = 1 },
    augment_iron = { additional_amount = 1 },
    augment_gold = { additional_amount = 1 },
    augment_platinum = { additional_amount = 1 },
    augment_iridium = { additional_amount = 1 },
    refine_ruby = {
        ruby_enabled = 1,
        emerald_enabled = 0,
        diamond_enabled = 0,
        ruby_smelting_rate = 4,
        emerald_smelting_rate = 8,
        diamond_smelting_rate = 15,
        ruby_mult = 1,
        emerald_mult = 1,
        diamond_mult = 1,
    },
    the_collector = { production_rate = 8, production_amount = 1, production_limit = 100 },
    triple_trouble = { chance = 5 },
}

Config.OreNames = {
    [0] = "Stone", [1] = "Silver", [2] = "Gold", [3] = "Starmetal",
    [4] = "Bedrock", [5] = "Platinum", [6] = "Iridium", [7] = "Ruby",
    [8] = "Emerald", [9] = "Diamond", [10] = "StarDebris", [11] = "StarStone",
    [12] = "FactoryOre", [13] = "RubyUnsmelted", [14] = "EmeraldUnsmelted",
    [15] = "DiamondUnsmelted", [16] = "MissionRewardOre", [17] = "StarBarrier",
    [18] = "Stardrop",
}

Config.Ores = {
    -- Stone is the ordinary material of the current geological layer. It has
    -- no separate ore-vein overlay in the original game. The recovered
    -- newOres sprites are pickup/inventory art; drawing them on every Stone
    -- tile made most of the dirt field look like orange/white ore fragments.
    Stone = { id = 0, zh = "石头", health = 10 },
    Silver = { id = 1, zh = "白银", health = 15, path = "image/diggin/original/Tilesets/ironOre.png", frames = 4 },
    Gold = { id = 2, zh = "黄金", health = 30, path = "image/diggin/original/Tilesets/Main/goldore.png", frames = 3 },
    Starmetal = { id = 3, zh = "星金属", health = 10, frames = 1 },
    Bedrock = { id = 4, zh = "基岩", health = 9, indestructible = true },
    Platinum = { id = 5, zh = "铂金", health = 50, path = "image/diggin/original/Ores/platinum.png", frames = 4 },
    Iridium = { id = 6, zh = "铱", health = 60, path = "image/diggin/original/Tilesets/specialOresTile.png", frames = 3, row = 1 },
    Ruby = { id = 7, zh = "红宝石", health = 20, path = "image/diggin/original/Tilesets/specialOresTile.png", frames = 3, row = 2 },
    Emerald = { id = 8, zh = "绿宝石", health = 30, path = "image/diggin/original/Tilesets/specialOresTile.png", frames = 3, row = 3 },
    Diamond = { id = 9, zh = "钻石", health = 40, path = "image/diggin/original/Tilesets/specialOresTile.png", frames = 3, row = 4 },
    RubyUnsmelted = { id = 13, zh = "红宝石原矿", health = 10, path = "image/diggin/original/Tilesets/specialOresTile.png", frames = 3, row = 2 },
    EmeraldUnsmelted = { id = 14, zh = "绿宝石原矿", health = 15, path = "image/diggin/original/Tilesets/specialOresTile.png", frames = 3, row = 3 },
    DiamondUnsmelted = { id = 15, zh = "钻石原矿", health = 30, path = "image/diggin/original/Tilesets/specialOresTile.png", frames = 3, row = 4 },
    StarDebris = { id = 10, zh = "星尘", health = 1 },
    StarStone = { id = 11, zh = "星石", health = 1 },
    FactoryOre = { id = 12, zh = "铝", health = 1 },
    MissionRewardOre = { id = 16, zh = "任务徽章", health = 1 },
    StarBarrier = { id = 17, zh = "星界屏障", health = 1, indestructible = true },
    Stardrop = { id = 18, zh = "星辰", health = 1 },
}

-- Always-visible material atlas. Keep source labels compact enough for the
-- fixed 480x270 three-column screen while still naming the actual system that
-- produces each resource.
Config.MaterialCatalog = {
    { ore = "Stone", source = "各层普通地块" },
    { ore = "Silver", source = "第1-8层白银矿" },
    { ore = "Gold", source = "各层金矿／宝箱补偿" },
    { ore = "Platinum", source = "第2-10层铂金矿" },
    { ore = "Iridium", source = "密度6起伴生保底／第3-10层矿脉" },
    { ore = "Starmetal", source = "第6、8-10层／终极密度" },
    { ore = "RubyUnsmelted", source = "挖掘红宝石矿" },
    { ore = "EmeraldUnsmelted", source = "挖掘绿宝石矿" },
    { ore = "DiamondUnsmelted", source = "第5层后钻石矿" },
    { ore = "Ruby", source = "宝石精炼厂" },
    { ore = "Emerald", source = "精炼厂＋绿宝石科技" },
    { ore = "Diamond", source = "精炼厂＋钻石科技" },
    { ore = "StarDebris", source = "星金属／第3、5、7、10层" },
    { ore = "StarStone", source = "星金属／终极10层每局＋1" },
    { ore = "FactoryOre", source = "收藏家自动生产" },
    { ore = "MissionRewardOre", source = "各密度每层首达＋30" },
    { ore = "Stardrop", source = "第10层首通／星金属" },
}

-- One completed rewarded video grants a run-spanning golden drill charge pack.
-- Rolls are mutually exclusive and checked from rarest to most common so the
-- displayed percentages remain exact rather than stacking with one another.
Config.GoldenDrill = {
    chargesPerAd = 120,
    doubleChance = 20,
    tripleChance = 5,
    jackpotChance = 0.1,
    jackpotMultiplier = 100,
}

Config.LayerSheets = {
    [0] = "image/diggin/original/Tilesets/layer/layer1.png",
    [1] = "image/diggin/original/Tilesets/layer/layer1.5.png",
    [2] = "image/diggin/original/Tilesets/layer/layer2.png",
    [3] = "image/diggin/original/Tilesets/layer/layer3.png",
    [4] = "image/diggin/original/Tilesets/layer/layer4.png",
    [5] = "image/diggin/original/Tilesets/layer/layer5.png",
    [6] = "image/diggin/original/Tilesets/layer/layer6.png",
    [7] = "image/diggin/original/Tilesets/layer/layer10.png",
    [9] = "image/diggin/original/Tilesets/layer/zuti layer.png",
    [10] = "image/diggin/original/Tilesets/layer/zeleni layer.png",
    [11] = "image/diggin/original/Tilesets/layer/starlayer.png",
    [12] = "image/diggin/original/Tilesets/Main/bedrockLayer.png",
}

Config.Layers = {
    { key = "LAYER_DIRT", zh = "泥土层", tilemap = 0, fromY = 0, health = 1, weights = { Stone = 82, Silver = 17, Gold = 1 } },
    { key = "LAYER_GRAVEL", zh = "砾石层", tilemap = 1, fromY = 20, health = 2.5, weights = { Stone = 73, Silver = 18, Gold = 7, Platinum = 0.5, Ruby = 1, Emerald = 0.5 } },
    { key = "LAYER_STONE", zh = "岩石层", tilemap = 2, fromY = 50, health = 10, weights = { Stone = 66, Silver = 13, Gold = 16, Platinum = 3, Iridium = 0.5, Ruby = 1, Emerald = 0.5 } },
    { key = "LAYER_SLATE", zh = "板岩层", tilemap = 3, fromY = 80, health = 10, weights = { Stone = 55, Silver = 6, Gold = 14, Platinum = 18, Iridium = 3, Ruby = 2.5, Emerald = 1.5 } },
    { key = "LAYER_MOSSROCK", zh = "苔岩层", tilemap = 4, fromY = 110, health = 20, weights = { Stone = 52, Silver = 3, Gold = 9, Platinum = 18, Iridium = 11, Ruby = 3.5, Emerald = 2.5, Diamond = 1 } },
    { key = "LAYER_FROST", zh = "冻土层", tilemap = 5, fromY = 140, health = 40, weights = { Stone = 54, Silver = 2, Gold = 3, Starmetal = 0.006, Platinum = 14, Iridium = 17, Ruby = 5, Emerald = 4, Diamond = 1 } },
    { key = "LAYER_GEODE", zh = "晶洞层", tilemap = 6, fromY = 170, health = 50, weights = { Stone = 51, Silver = 1, Gold = 3, Platinum = 10, Iridium = 17, Ruby = 8, Emerald = 6, Diamond = 4 } },
    { key = "LAYER_MANTLE", zh = "地幔层", tilemap = 7, fromY = 200, health = 70, weights = { Stone = 53, Silver = 1, Gold = 3, Starmetal = 0.016, Platinum = 8, Iridium = 13, Ruby = 6, Emerald = 8, Diamond = 8 } },
    { key = "LAYER_ACIDROCK", zh = "酸岩层", tilemap = 9, fromY = 260, health = 80, weights = { Stone = 54, Gold = 1, Starmetal = 0.1, Platinum = 6, Iridium = 11, Ruby = 4, Emerald = 8, Diamond = 16 } },
    { key = "LAYER_OUTER_CORE", zh = "外核层", tilemap = 10, fromY = 290, health = 80, weights = { Stone = 52, Gold = 1, Starmetal = 0.1, Platinum = 5, Iridium = 11, Ruby = 4, Emerald = 7, Diamond = 20 } },
}

return Config
