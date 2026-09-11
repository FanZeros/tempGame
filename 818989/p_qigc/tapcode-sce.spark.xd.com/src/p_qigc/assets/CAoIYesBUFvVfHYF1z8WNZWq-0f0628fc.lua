-- ====================================================================
-- data/MonsterDB.lua - 怪物数据库（从 GameState.lua 提取）
-- ====================================================================
-- 纯数据模块，不依赖任何运行时状态
-- 用法: local MONSTER_DB = require("data.MonsterDB")
-- ====================================================================

local db = {
    -- Lv1
    slime             = { name = "史莱姆",       level = 1,  rarity = "common", hp = 25,   atk = 15,  mAtk = 15, def = 3, mdef = 3, atkSpeed = 1, critVal = 0.20,   critDmg = 50, hit = 3,     dodge = 3.75,   moveRange = 2, atkRange = 1, color = {100, 220, 120}, expReward = 1, image = "image/monster_slime.png", drops = { { id = "slime_crystal", chance = 0.50 } } },
    -- 酒馆肉搏一（Lv.10）
    tavern_thug       = { name = "混混",         level = 10, rarity = "common", hp = 250,  atk = 32,  mAtk = 32,  def = 40,  mdef = 40,  atkSpeed = 1,  critVal = 5,  critDmg = 50, hit = 7,  dodge = 13, moveRange = 2, atkRange = 1, color = {180, 160, 100}, expReward = 10, image = "image/monster_thug.png",      atkAttr = "physical", noAffix = true },
    drunk_man         = { name = "喝醉的男人",   level = 10, rarity = "common", hp = 250,  atk = 32,  mAtk = 32,  def = 40,  mdef = 40,  atkSpeed = 1,  critVal = 10, critDmg = 50, hit = 7,  dodge = 13, moveRange = 2, atkRange = 1, color = {160, 140, 110}, expReward = 10, image = "image/monster_drunk_man.png",  atkAttr = "physical", noAffix = true },
    scarface          = { name = "刀疤脸",       level = 10, rarity = "common", hp = 250,  atk = 20,  mAtk = 20,  def = 40,  mdef = 40,  atkSpeed = 50, critVal = 5,  critDmg = 50, hit = 7,  dodge = 13, moveRange = 3, atkRange = 1, color = {140, 120, 100}, expReward = 10, image = "image/monster_scarface.png",  atkAttr = "physical", noAffix = true },
    -- 酒馆肉搏二（Lv.25）
    tavern_thug_25    = { name = "混混",         level = 25, rarity = "common", hp = 1100, atk = 88,  mAtk = 88,  def = 120, mdef = 120, atkSpeed = 1,  critVal = 30, critDmg = 50, hit = 10, dodge = 30, moveRange = 2, atkRange = 1, color = {180, 160, 100}, expReward = 30, image = "image/monster_thug.png",      atkAttr = "physical", noAffix = true },
    drunk_man_25      = { name = "喝醉的男人",   level = 25, rarity = "common", hp = 1100, atk = 88,  mAtk = 88,  def = 120, mdef = 120, atkSpeed = 1,  critVal = 30, critDmg = 50, hit = 10, dodge = 30, moveRange = 2, atkRange = 1, color = {160, 140, 110}, expReward = 30, image = "image/monster_drunk_man.png",  atkAttr = "physical", noAffix = true },
    scarface_25       = { name = "刀疤脸",       level = 25, rarity = "common", hp = 1100, atk = 50,  mAtk = 20,  def = 120, mdef = 120, atkSpeed = 50, critVal = 30, critDmg = 50, hit = 10, dodge = 30, moveRange = 3, atkRange = 1, color = {140, 120, 100}, expReward = 30, image = "image/monster_scarface.png",  atkAttr = "physical", noAffix = true },
    item_slime        = { name = "吞下物品的史莱姆", level = 3, rarity = "rare", hp = 100, atk = 15, def = 3, critVal = 1, critDmg = 50, hit = 4, dodge = 4, moveRange = 2, atkRange = 1, color = {180, 210, 240}, expReward = 5, image = "image/monster_item_slime.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_ITEM_SLIME" },
    -- Lv3
    fire_slime        = { name = "火史莱姆",     level = 3,  rarity = "common", hp = 120,  atk = 33,  mAtk = 33, def = 9, mdef = 9, atkSpeed = 1, critVal = 10, critDmg = 50, hit = 4, dodge = 7, moveRange = 2, atkRange = 2, color = {220, 80, 40},   expReward = 2, image = "image/monster_fire_slime.png", atkAttr = "magic", element = "fire" },
    ice_slime         = { name = "冰史莱姆",     level = 3,  rarity = "common", hp = 120,  atk = 33,  mAtk = 33, def = 9, mdef = 9, atkSpeed = 1, critVal = 10, critDmg = 50, hit = 4, dodge = 7, moveRange = 2, atkRange = 2, color = {100, 180, 240}, expReward = 2, image = "image/monster_ice_slime.png", atkAttr = "magic", element = "ice" },
    elec_slime        = { name = "电史莱姆",     level = 3,  rarity = "common", hp = 120,  atk = 20,  mAtk = 20, def = 9, mdef = 9, atkSpeed = 50, critVal = 10, critDmg = 50, hit = 4, dodge = 7, moveRange = 2, atkRange = 2, color = {240, 220, 60},  expReward = 2, image = "image/monster_elec_slime.png", atkAttr = "magic", element = "thunder" },
    bat               = { name = "蝙蝠",         level = 3,  rarity = "common", hp = 45,  atk = 24,  mAtk = 24,  def = 8,  mdef = 8,  atkSpeed = 1,  critVal = 0.60,   critDmg = 50, hit = 4,     dodge = 8,      moveRange = 3, atkRange = 1, color = {160, 120, 80},  expReward = 2, image = "image/monster_bat.png",  atkAttr = "physical", drops = { { id = "bat_wing", chance = 0.50 } } },
    -- Lv7-8
    rare_bat          = { name = "吸血蝙蝠",     level = 7,  rarity = "rare",   hp = 150,  atk = 28,  mAtk = 28,  def = 10,  mdef = 10,  atkSpeed = 1,  critVal = 2,      critDmg = 50, hit = 10,    dodge = 12,     moveRange = 3, atkRange = 1, color = {60, 20, 30},    expReward = 10, image = "image/monster_rare_bat.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_RARE_BAT" },
    wolf              = { name = "野狼",         level = 7,  rarity = "common", hp = 200,  atk = 26,  mAtk = 26, def = 24, mdef = 24, atkSpeed = 1, critVal = 1.40,   critDmg = 50, hit = 5,     dodge = 11.25,  moveRange = 3, atkRange = 1, color = {140, 140, 140}, expReward = 4, image = "image/monster_wolf.png", drops = { { id = "wolf_skin", chance = 0.50 }, { id = "raw_wolf", chance = 0.10 } } },
    wolf_king         = { name = "白狼王",       level = 10, rarity = "rare", hp = 480,  atk = 56,  def = 24,     critVal = 15,     critDmg = 75, hit = 15,    dodge = 20,     moveRange = 4, atkRange = 1, color = {220, 220, 230}, expReward = 20, image = "image/monster_wolf_king.png", noAffix = true, dropGroup = "DROP_GROUP_WOLF_KING", drops = { { id = "raw_wolf", chance = 0.10 } } },
    -- Lv11-12
    boar              = { name = "野猪",         level = 11, rarity = "common", hp = 400,  atk = 32,  mAtk = 32, def = 56, mdef = 56, atkSpeed = 1, critVal = 2.20,   critDmg = 50, hit = 5,     dodge = 16.25,  moveRange = 3, atkRange = 1, color = {120, 80, 160},  expReward = 5, image = "image/monster_boar.png", drops = { { id = "boar_tusk", chance = 0.50 }, { id = "raw_pork", chance = 0.10 } } },
    boar_king         = { name = "野猪王",       level = 15, rarity = "rare",   hp = 800, atk = 72,  def = 80,    critVal = 5,      critDmg = 50, hit = 10,    dodge = 16.25,  moveRange = 4, atkRange = 1, color = {100, 60, 40},   expReward = 25, image = "image/monster_boar_king.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_BOAR_KING", drops = { { id = "raw_pork", chance = 0.10 } } },
    bear              = { name = "野熊",         level = 43, rarity = "common", hp = 2500, atk = 104, mAtk = 104, def = 281, mdef = 281, atkSpeed = 1, critVal = 17.20,  critDmg = 50, hit = 12,    dodge = 62.50,  moveRange = 3, atkRange = 1, color = {160, 100, 60},  expReward = 34, image = "image/monster_bear.png", drops = { { id = "bear_skin", chance = 0.50 }, { id = "bear_paw", chance = 0.10 } } },
    black_bear_king   = { name = "黑熊王",       level = 47, rarity = "rare",   hp = 6800, atk = 176, def = 300,    critVal = 47,     critDmg = 50, hit = 35,    dodge = 62.50,  moveRange = 4, atkRange = 1, color = {40, 30, 30},    expReward = 130, image = "image/monster_black_bear_king.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_BLACK_BEAR", drops = { { id = "bear_paw", chance = 0.10 } } },
    grey_bear         = { name = "灰熊",         level = 46, rarity = "common", hp = 2840, atk = 115, mAtk = 115, def = 299, mdef = 299, atkSpeed = 1, critVal = 18.40,  critDmg = 50, hit = 13.60, dodge = 66.67,  moveRange = 2, atkRange = 1, color = {130, 120, 115}, expReward = 78, image = "image/monster_grey_bear.png", atkAttr = "physical", drops = { { id = "bear_skin", chance = 0.50 }, { id = "bear_paw", chance = 0.10 } } },
    -- Lv15-16 哥布林系列
    goblin            = { name = "哥布林",       level = 15, rarity = "common", hp = 600, atk = 44,  mAtk = 44, def = 63, mdef = 63, atkSpeed = 1, critVal = 6,      critDmg = 50, hit = 5,     dodge = 22.67,  moveRange = 3, atkRange = 1, color = {120, 180, 80},  expReward = 6, image = "image/monster_goblin.png", drops = { { id = "@gold", amount = 6, chance = 1.0 } } },
    goblin_club       = { name = "木棍哥布林",   level = 16, rarity = "common", hp = 600, atk = 48,  mAtk = 48, def = 77, mdef = 77, atkSpeed = 1, critVal = 6.40,   critDmg = 50, hit = 5,     dodge = 24,     moveRange = 3, atkRange = 1, color = {130, 170, 70},  expReward = 6, image = "image/monster_goblin_club.png", drops = { { id = "@gold", amount = 7, chance = 1.0 } } },
    goblin_shield     = { name = "盾牌哥布林",   level = 16, rarity = "common", hp = 700, atk = 44,  mAtk = 44, def = 88, mdef = 88, atkSpeed = 1, critVal = 6.40,   critDmg = 50, hit = 5,     dodge = 24,     moveRange = 2, atkRange = 1, color = {110, 170, 90},  expReward = 6, image = "image/monster_goblin_shield.png", drops = { { id = "@gold", amount = 7, chance = 1.0 } } },
    goblin_archer     = { name = "弓箭哥布林",   level = 16, rarity = "common", hp = 600, atk = 48,  mAtk = 48, def = 77, mdef = 77, atkSpeed = 1, critVal = 6.40,   critDmg = 50, hit = 5,     dodge = 24,     moveRange = 2, atkRange = 3, color = {140, 180, 60},  expReward = 6, image = "image/monster_goblin_archer.png", drops = { { id = "@gold", amount = 7, chance = 1.0 } } },
    chest_goblin      = { name = "宝箱哥布林",   level = 19, rarity = "rare", hp = 2400, atk = 0,   def = 77,     critVal = 6.40,   critDmg = 50, hit = 5,     dodge = 24,     moveRange = 1, atkRange = 1, color = {200, 160, 60},  expReward = 30, image = "image/monster_chest_goblin.png", atkAttr = "physical", ai = "flee", noAffix = true, dropGroup = "DROP_GROUP_CHEST_GOBLIN" },
    -- Lv20-25
    fierce_wolf       = { name = "凶狼",         level = 20, rarity = "common", hp = 900, atk = 60, mAtk = 60, def = 104, mdef = 104, atkSpeed = 1, critVal = 8,      critDmg = 50, hit = 5,     dodge = 29.33,  moveRange = 3, atkRange = 1, color = {100, 100, 110}, expReward = 8, image = "image/monster_fierce_wolf.png", drops = { { id = "fierce_wolf_fang", chance = 0.50 }, { id = "raw_wolf", chance = 0.10 } } },
    young_werewolf    = { name = "幼年狼人",     level = 24, rarity = "rare",   hp = 2000, atk = 102, def = 104,    critVal = 30,     critDmg = 50, hit = 20,    dodge = 40,     moveRange = 3, atkRange = 1, color = {140, 130, 100}, expReward = 40, image = "image/monster_young_werewolf.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_WEREWOLF_PUP" },
    vampire_youth     = { name = "吸血魔蝠",     level = 25, rarity = "common", hp = 1000, atk = 68, mAtk = 68, def = 111, mdef = 111, atkSpeed = 1, critVal = 10,     critDmg = 50, hit = 6,     dodge = 36,     moveRange = 3, atkRange = 1, color = {180, 50, 60},   expReward = 10, image = "image/monster_vampire_bat.png", drops = { { id = "vampire_fang", chance = 0.50 } } },
    vampire_boy       = { name = "吸血少年",     level = 30, rarity = "rare",   hp = 2800, atk = 116, def = 144,    critVal = 30,     critDmg = 50, hit = 24,    dodge = 40,     moveRange = 3, atkRange = 1, color = {40, 20, 60},    expReward = 50, image = "image/monster_vampire_boy.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_VAMPIRE_GIRL" },
    vampire_girl      = { name = "吸血少女",     level = 30, rarity = "rare",   hp = 2400, atk = 116, def = 111, critVal = 30,     critDmg = 50, hit = 24,    dodge = 40,     moveRange = 3, atkRange = 3, color = {80, 20, 40},    expReward = 50, image = "image/monster_vampire_girl.png", atkAttr = "magic", element = "shadow", noAffix = true, dropGroup = "DROP_GROUP_VAMPIRE_GIRL" },
    -- Lv29-33
    tree_root         = { name = "树根精",       level = 29, rarity = "common", hp = 1500, atk = 80, mAtk = 80, def = 149, mdef = 149, atkSpeed = 1, critVal = 11.60,  critDmg = 50, hit = 7.50,  dodge = 41.33,  moveRange = 2, atkRange = 1, color = {100, 140, 60},  expReward = 12, image = "image/monster_tree_root.png", drops = { { id = "tree_root_wood", chance = 0.50 }, { id = "dew_essence", chance = 0.10 } } },
    golden_tree_root  = { name = "小黄金树根精", level = 34, rarity = "rare",   hp = 3440, atk = 128, def = 200,    critVal = 30,     critDmg = 50, hit = 25,    dodge = 42,     moveRange = 2, atkRange = 1, color = {200, 180, 60},  expReward = 60, image = "image/monster_golden_tree_root.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_GOLDEN_TREE", drops = { { id = "dew_essence", chance = 0.10 } } },
    demon_slime       = { name = "恶魔史莱姆",   level = 33, rarity = "common", hp = 1800, atk = 77, mAtk = 77, def = 209, mdef = 209, atkSpeed = 1, critVal = 13.20,  critDmg = 50, hit = 8.70,  dodge = 46.67,  moveRange = 2, atkRange = 1, color = {160, 80, 200},  expReward = 18, image = "image/monster_demon_slime.png", drops = { { id = "dark_slime_crystal", chance = 0.50 } } },
    strange_demon_slime = { name = "奇怪的恶魔史莱姆", level = 38, rarity = "rare", hp = 3200, atk = 142, def = 232, critVal = 40, critDmg = 50, hit = 30, dodge = 47, moveRange = 2, atkRange = 1, color = {200, 210, 240}, expReward = 70, image = "image/monster_strange_demon_slime.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_STRANGE_DEMON" },
    -- Lv37-38 骷髅系列
    skeleton_sword    = { name = "持剑骷髅兵",   level = 37, rarity = "common", hp = 2300, atk = 88, mAtk = 88, def = 232, mdef = 232, atkSpeed = 1, critVal = 14.80,  critDmg = 50, hit = 9.90,  dodge = 52,     moveRange = 2, atkRange = 1, color = {200, 200, 190}, expReward = 21, image = "image/monster_skeleton_sword.png", drops = { { id = "skeleton_bone", chance = 0.50 } } },
    skeleton_archer   = { name = "弓箭骷髅兵",   level = 38, rarity = "common", hp = 2200, atk = 88, mAtk = 88, def = 208, mdef = 208, atkSpeed = 1, critVal = 15.20,  critDmg = 50, hit = 11.10, dodge = 53.33,  moveRange = 2, atkRange = 3, color = {190, 190, 180}, expReward = 21, image = "image/monster_skeleton_archer.png", drops = { { id = "skeleton_bone", chance = 0.50 } } },
    skeleton_king     = { name = "骷髅王",       level = 42, rarity = "rare",   hp = 6400, atk = 160, def = 262,    critVal = 42,     critDmg = 50, hit = 11.10, dodge = 25,     moveRange = 2, atkRange = 1, color = {220, 190, 80},  expReward = 80, image = "image/monster_skeleton_king.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_SKELETON_KING" },
    -- Lv42-46
    ghost             = { name = "幽灵",         level = 42, rarity = "common", hp = 1800, atk = 105, mAtk = 105, def = 262, mdef = 262, atkSpeed = 1, critVal = 16.80,  critDmg = 50, hit = 11.40, dodge = 146.67, moveRange = 4, atkRange = 1, color = {160, 200, 240}, expReward = 32, image = "image/monster_ghost.png", drops = { { id = "ghost_cloth", chance = 0.50 } } },
    grey_ghost        = { name = "\"阿灰\"",     level = 46, rarity = "rare",   hp = 1600, atk = 200, def = 262, critVal = 16.80,  critDmg = 50, hit = 33,    dodge = 230,    moveRange = 4, atkRange = 1, color = {160, 160, 160}, expReward = 125, image = "image/monster_grey_ghost.png", atkAttr = "magic", element = "shadow", noAffix = true, dropGroup = "DROP_GROUP_GREY_GHOST" },
    slime_elite       = { name = "史莱姆精锐",   level = 45, rarity = "uncommon", hp = 5000,  atk = 170, mAtk = 170, def = 340, mdef = 340, atkSpeed = 1, critVal = 20,  critDmg = 50, hit = 40,    dodge = 63,     moveRange = 2, atkRange = 1, color = {100, 220, 120}, expReward = 28,  image = "image/monster_slime.png", atkAttr = "physical" },
    -- Lv45 史莱姆王国副本
    fire_slime_elite  = { name = "火史莱姆精锐", level = 45, rarity = "rare",    hp = 5000,  atk = 187, mAtk = 187, def = 340, mdef = 340, atkSpeed = 1, critVal = 20,  critDmg = 50, hit = 40,    dodge = 63,     moveRange = 2, atkRange = 1, color = {220, 80, 40},   expReward = 30,  image = "image/monster_fire_slime.png", atkAttr = "magic", element = "fire", eliteType = "fire" },
    ice_slime_elite   = { name = "冰史莱姆精锐", level = 45, rarity = "rare",    hp = 5000,  atk = 153, mAtk = 153, def = 340, mdef = 340, atkSpeed = 1, critVal = 20,  critDmg = 50, hit = 40,    dodge = 63,     moveRange = 2, atkRange = 1, color = {100, 180, 240}, expReward = 30,  image = "image/monster_ice_slime.png", atkAttr = "magic", element = "ice", eliteType = "ice" },
    elec_slime_elite  = { name = "电史莱姆精锐", level = 45, rarity = "rare",    hp = 5000,  atk = 170, mAtk = 170, def = 340, mdef = 340, atkSpeed = 1, critVal = 30,  critDmg = 50, hit = 40,    dodge = 63,     moveRange = 4, atkRange = 1, color = {240, 220, 60},  expReward = 30,  image = "image/monster_elec_slime.png", atkAttr = "magic", element = "thunder", eliteType = "elec" },
    slime_princess    = { name = "史莱姆公主",   level = 45, rarity = "fine",    hp = 30000, atk = 179, mAtk = 179, def = 450, mdef = 350, atkSpeed = 1, critVal = 30,  critDmg = 50, hit = 50,    dodge = 70,     moveRange = 5, atkRange = 1, color = {240, 160, 180}, expReward = 250, image = "image/monster_slime_princess.png", atkAttr = "physical" },
    slime_prince      = { name = "史莱姆王子",   level = 45, rarity = "fine",    hp = 30000, atk = 145, mAtk = 145, def = 350, mdef = 450, atkSpeed = 1, critVal = 30,  critDmg = 50, hit = 50,    dodge = 70,     moveRange = 3, atkRange = 1, color = {160, 200, 240}, expReward = 250, image = "image/monster_slime_prince.png", atkAttr = "magic", element = "holy" },
    slime_king        = { name = "史莱姆王",     level = 45, rarity = "superior", hp = 50000, atk = 196, mAtk = 196, def = 450, mdef = 450, atkSpeed = 1, critVal = 30,  critDmg = 50, hit = 60,    dodge = 60,     moveRange = 2, atkRange = 1, color = {220, 180, 60},  expReward = 500, image = "image/monster_slime_king.png", atkAttr = "physical", size = 2, knockbackDist = 2, knockbackWallDmg = 300, summonEliteInterval = 4, bossId = "slime_king" },
    -- Lv100 史莱姆国王大反击
    slime_king_enraged = { name = "暴怒史莱姆王", level = 45, rarity = "superior", hp = 999999999, atk = 280, mAtk = 280, def = 450, mdef = 450, atkSpeed = 1, critVal = 30, critDmg = 50, hit = 60, dodge = 60, moveRange = 2, atkRange = 1, color = {255, 140, 30}, expReward = 0, image = "image/monster_slime_king.png", atkAttr = "physical", size = 2, knockbackDist = 2, knockbackWallDmg = 800, summonEliteInterval = 3, bossId = "slime_king", immortal = true },
    fire_slime_enraged = { name = "暴怒火史莱姆", level = 45, rarity = "rare", hp = 5000, atk = 220, mAtk = 220, def = 340, mdef = 340, atkSpeed = 1,  critVal = 20, critDmg = 50, hit = 40, dodge = 63, moveRange = 2, atkRange = 1, color = {220, 80, 40},  expReward = 0, image = "image/monster_fire_slime.png", atkAttr = "magic", element = "fire",    eliteType = "fire" },
    ice_slime_enraged  = { name = "暴怒冰史莱姆", level = 45, rarity = "rare", hp = 5000, atk = 180, mAtk = 180, def = 340, mdef = 340, atkSpeed = 1,  critVal = 20, critDmg = 50, hit = 40, dodge = 63, moveRange = 2, atkRange = 1, color = {100, 180, 240}, expReward = 0, image = "image/monster_ice_slime.png",  atkAttr = "magic", element = "ice",     eliteType = "ice" },
    elec_slime_enraged = { name = "暴怒雷史莱姆", level = 45, rarity = "rare", hp = 5000, atk = 120, mAtk = 120, def = 340, mdef = 340, atkSpeed = 50, critVal = 30, critDmg = 50, hit = 40, dodge = 63, moveRange = 4, atkRange = 3, color = {240, 220, 60},  expReward = 0, image = "image/monster_elec_slime.png", atkAttr = "magic", element = "thunder", eliteType = "elec" },
    -- 迪卡塔的弟弟迪哈塔大反击
    goblin_hero_dihata = { name = "哥布林英雄迪哈塔", level = 65, rarity = "superior", hp = 999999999, atk = 360, mAtk = 360, def = 900, mdef = 900, atkSpeed = 1, critVal = 50, critDmg = 50, hit = 100, dodge = 120, moveRange = 3, atkRange = 99, color = {140, 180, 60}, expReward = 0, image = "image/goblin_hero_dihata.png", atkAttr = "physical", size = 1, bossId = "goblin_dihata", immortal = true },
    star_demon_round  = { name = "圆滚滚星恶魔", level = 75, rarity = "common", hp = 7500, atk = 238, mAtk = 238, def = 1100, mdef = 1100, atkSpeed = 1, critVal = 59.00,  critDmg = 50, hit = 27.00, dodge = 117.00, moveRange = 2, atkRange = 1, color = {140, 60, 180},  expReward = 3315, image = "image/monster_star_demon_round.png", drops = { { id = "dark_star_crystal", chance = 0.50 } } },
    star_demon_elite  = { name = "圆滚滚上等星恶魔", level = 80, rarity = "rare", hp = 13000, atk = 385, mAtk = 385, def = 1125, mdef = 1125, atkSpeed = 1, critVal = 80.00, critDmg = 50, hit = 70.00, dodge = 130.00, moveRange = 2, atkRange = 1, color = {60, 20, 80}, expReward = 13000, image = "image/monster_star_demon_elite.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_STAR_DEMON" },
    -- Lv50-52 妖怪系列
    candle_monster    = { name = "烛台妖怪",     level = 50, rarity = "common", hp = 3300, atk = 128, mAtk = 128, def = 320, mdef = 320, atkSpeed = 1, critVal = 40,     critDmg = 50, hit = 13.80, dodge = 74.29,  moveRange = 3, atkRange = 3, color = {220, 160, 40},  expReward = 143, image = "image/monster_candle_monster.png", atkAttr = "magic", element = "fire", drops = { { id = "magic_candlestick", chance = 0.50 } } },
    sofa_monster      = { name = "沙发妖怪",     level = 51, rarity = "common", hp = 3450, atk = 122, mAtk = 122, def = 352, mdef = 352, atkSpeed = 1, critVal = 40.80,  critDmg = 50, hit = 15,    dodge = 75.71,  moveRange = 3, atkRange = 1, color = {160, 120, 80},  expReward = 150, image = "image/monster_sofa_monster.png", drops = { { id = "magic_cloth", chance = 0.50 } } },
    book_monster      = { name = "书本妖怪",     level = 52, rarity = "common", hp = 3420, atk = 128, mAtk = 128, def = 341, mdef = 341, atkSpeed = 1, critVal = 41.60,  critDmg = 50, hit = 15.30, dodge = 77.14,  moveRange = 3, atkRange = 1, color = {140, 100, 80},  expReward = 156, image = "image/monster_book_monster.png", drops = { { id = "magic_page", chance = 0.50 }, { pool = {"elfvah_language_book_1", "elfvah_language_book_2", "elfvah_language_book_3"}, chance = 0.005 } } },
    piano_monster     = { name = "钢琴妖怪",     level = 55, rarity = "rare",   hp = 8000, atk = 200, def = 360,   critVal = 55,     critDmg = 50, hit = 47,    dodge = 77.47,  moveRange = 3, atkRange = 1, color = {140, 100, 70},  expReward = 600, image = "image/monster_piano.png", atkAttr = "magic", noAffix = true, dropGroup = "DROP_GROUP_PIANO" },
    -- Lv54
    rock_turtle        = { name = "岩壳龟",       level = 54, rarity = "common", hp = 4500, atk = 119, mAtk = 119, def = 400, mdef = 400, atkSpeed = 1, critVal = 43.20,  critDmg = 50, hit = 15.60, dodge = 1,      moveRange = 1, atkRange = 1, color = {210, 130, 60},  expReward = 195, image = "image/monster_rock_turtle.png", atkAttr = "physical", drops = { { id = "organ_fragment", chance = 0.50 }, { id = "raw_turtle", chance = 0.10 } } },
    -- Lv57-58 人偶系列
    butler_doll       = { name = "管家人偶",     level = 57, rarity = "common", hp = 4100, atk = 133, mAtk = 133, def = 365, mdef = 365, atkSpeed = 1, critVal = 45.60,  critDmg = 50, hit = 16.20, dodge = 84.29,  moveRange = 3, atkRange = 1, color = {60, 60, 80},    expReward = 312, image = "image/monster_butler_puppet.png", drops = { { id = "magic_puppeteer", chance = 0.50 } } },
    maid_doll         = { name = "女仆人偶",     level = 58, rarity = "common", hp = 3900, atk = 140, mAtk = 140, def = 352, mdef = 352, atkSpeed = 1, critVal = 46.40,  critDmg = 50, hit = 17.10, dodge = 85.71,  moveRange = 3, atkRange = 3, color = {200, 120, 140}, expReward = 312, image = "image/monster_maid_doll.png", atkAttr = "magic", drops = { { id = "magic_puppeteer", chance = 0.50 } } },
    knight_doll       = { name = "骑士人偶",     level = 63, rarity = "rare",   hp = 8800, atk = 232, def = 528,    critVal = 70,     critDmg = 50, hit = 55,    dodge = 97,     moveRange = 3, atkRange = 1, color = {180, 180, 190}, expReward = 1200, image = "image/monster_knight_doll.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_KNIGHT_DOLL" },
    -- Lv63
    mummy             = { name = "木乃伊",       level = 63, rarity = "common", hp = 6300, atk = 168, mAtk = 168, def = 662, mdef = 662, atkSpeed = 1, critVal = 50.40,  critDmg = 50, hit = 17.40, dodge = 97.01,  moveRange = 2, atkRange = 1, color = {180, 160, 100}, expReward = 650, image = "image/monster_mummy.png", drops = { { id = "mummy_wrap", chance = 0.50 } } },
    mummy_pharaoh     = { name = "木乃伊法老",   level = 68, rarity = "rare",   hp = 12000, atk = 300, def = 750,    critVal = 50.40,  critDmg = 50, hit = 60,    dodge = 97.01,  moveRange = 2, atkRange = 1, color = {200, 180, 80},  expReward = 2500, image = "image/monster_mummy_pharaoh.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_PHARAOH" },
    -- Lv63-65 哥布林竞技场副本
    goblin_warrior_arena = { name = "哥布林勇士", level = 65, rarity = "rare",   hp = 10000,  atk = 300, mAtk = 300, def = 660, mdef = 660, critVal = 60,  critDmg = 50, hit = 60,  dodge = 100, moveRange = 3, atkRange = 1, color = {120, 160, 60},  expReward = 550,   image = "image/monster_goblin_warrior.png", atkAttr = "physical" },
    goblin_boss_diwu     = { name = "阴险\"迪呜\"", level = 65, rarity = "fine",   hp = 65000,  atk = 245, mAtk = 245, def = 500, mdef = 500, atkSpeed = 60, critVal = 80,  critDmg = 50, hit = 80,  dodge = 120, moveRange = 5, atkRange = 1, color = {100, 80, 60},  expReward = 9000,  image = "image/monster_goblin_diwu.png", atkAttr = "physical", ai = "flank" },
    goblin_boss_dila     = { name = "聪明\"迪拉\"", level = 65, rarity = "fine",   hp = 70000,  atk = 306, mAtk = 306, def = 700, mdef = 700, critVal = 70,  critDmg = 50, hit = 80,  dodge = 110, moveRange = 2, atkRange = 4, color = {80, 140, 200},  expReward = 9000,  image = "image/monster_goblin_dila.png", atkAttr = "magic", element = "ice", ai = "ice_mage" },
    goblin_boss_dikata   = { name = "英雄\"迪卡塔\"", level = 65, rarity = "superior",   hp = 100000, atk = 345, mAtk = 345, def = 850, mdef = 850, critVal = 70,  critDmg = 50, hit = 100, dodge = 120, moveRange = 3, atkRange = 1, color = {180, 140, 40},  expReward = 10000, image = "image/monster_goblin_dikata.png", atkAttr = "physical" },
    -- Lv66
    giant_tree_root   = { name = "大型树根精",   level = 66, rarity = "common", hp = 6500, atk = 189, mAtk = 189, def = 734, mdef = 734, atkSpeed = 1, critVal = 52.80,  critDmg = 50, hit = 18.90, dodge = 101.49, moveRange = 2, atkRange = 1, color = {120, 100, 60},   expReward = 988,  image = "image/monster_giant_tree_root.png", atkAttr = "physical", drops = { { id = "giant_tree_root_wood", chance = 0.50 }, { id = "dew_essence", chance = 0.10 } } },
    golden_giant_tree = { name = "大黄金树根精", level = 71, rarity = "rare",   hp = 16000, atk = 320, def = 800,    critVal = 71,     critDmg = 50, hit = 65,    dodge = 101.49, moveRange = 2, atkRange = 1, color = {210, 190, 70},   expReward = 3800, image = "image/monster_golden_giant_tree_root.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_GOLDEN_GIANT_TREE", drops = { { id = "dew_essence", chance = 0.10 } } },
    -- Lv69-70
    fishman           = { name = "鱼人",         level = 69, rarity = "common", hp = 7000, atk = 219, mAtk = 219, def = 991, mdef = 991, atkSpeed = 1, critVal = 55.20,  critDmg = 50, hit = 19.80, dodge = 105.97, moveRange = 3, atkRange = 1, color = {60, 140, 80},    expReward = 1560, image = "image/monster_fishman.png", drops = { { id = "fishman_scale", chance = 0.50 } } },
    fishman_warrior   = { name = "鱼人战士",     level = 75, rarity = "rare",   hp = 14000, atk = 350, def = 1000,   critVal = 75,     critDmg = 50, hit = 70,    dodge = 105.97, moveRange = 4, atkRange = 1, color = {80, 160, 140},   expReward = 6000, image = "image/monster_fishman_warrior.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_FISHMAN" },
    copper_turtle     = { name = "铜壳龟",       level = 59, rarity = "rare",   hp = 20000, atk = 176, def = 560,   critVal = 43.20,  critDmg = 50, hit = 15.60, dodge = 1,      moveRange = 1, atkRange = 1, color = {180, 130, 60},   expReward = 750, image = "image/monster_copper_turtle.png", atkAttr = "physical", mAtk = 240, noAffix = true, dropGroup = "DROP_GROUP_COPPER_TURTLE", drops = { { id = "raw_turtle", chance = 0.10 } } },
    -- Lv74-75 半人马系列
    centaur_hunter    = { name = "半人马猎手",   level = 74, rarity = "common", hp = 7000, atk = 238, mAtk = 238, def = 1050, mdef = 1050, atkSpeed = 1, critVal = 59.20,  critDmg = 50, hit = 20.70, dodge = 116.92, moveRange = 5, atkRange = 3, color = {160, 130, 80},   expReward = 3250, image = "image/monster_centaur_hunter.png", drops = { { id = "centaur_token", chance = 0.50 } } },
    centaur_warrior   = { name = "半人马战士",   level = 75, rarity = "common", hp = 7500, atk = 237, mAtk = 237, def = 1125, mdef = 1125, atkSpeed = 1, critVal = 60,     critDmg = 50, hit = 27.75, dodge = 118.46, moveRange = 5, atkRange = 1, color = {150, 120, 70},   expReward = 3380, image = "image/monster_centaur_warrior.png", drops = { { id = "centaur_token", chance = 0.50 } } },
    centaur_priest    = { name = "半人马祭司",   level = 80, rarity = "rare",   hp = 12000, atk = 380, def = 1125,   critVal = 120,    critDmg = 50, hit = 80,    dodge = 130,    moveRange = 5, atkRange = 5, color = {40, 30, 50},     expReward = 13000, image = "image/monster_centaur_priest.png", atkAttr = "magic", element = "shadow", noAffix = true, dropGroup = "DROP_GROUP_CENTAUR_PRIEST" },
    -- Lv79
    star_demon_fat    = { name = "胖乎乎星恶魔", level = 79, rarity = "common", hp = 7900, atk = 248, mAtk = 248, def = 1185, mdef = 1185, atkSpeed = 1, critVal = 63.20,  critDmg = 50, hit = 28.13, dodge = 124.62, moveRange = 3, atkRange = 1, color = {160, 80, 180},   expReward = 7800, image = "image/monster_star_demon_fat.png", drops = { { id = "dark_nebula_crystal", chance = 0.50 } } },
    star_demon_fat_elite = { name = "胖乎乎上等星恶魔", level = 84, rarity = "rare", hp = 14000, atk = 390, def = 1185, critVal = 84, critDmg = 50, hit = 75, dodge = 124.62, moveRange = 3, atkRange = 1, color = {40, 10, 60}, expReward = 30000, image = "image/monster_star_demon_fat_elite.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_STAR_FAT" },
    -- Lv83-88 海洋/森林系列
    five_eye_starfish = { name = "五眼海星",     level = 83, rarity = "common", hp = 8400, atk = 209, mAtk = 209, def = 1201, mdef = 1201, atkSpeed = 1, critVal = 66.40, critDmg = 50, hit = 29.63, dodge = 130.77, moveRange = 3, atkRange = 3, color = {80, 140, 200},  expReward = 18200, image = "image/monster_five_eye_starfish.png", atkAttr = "magic", element = "ice", drops = { { id = "starfish_eye", chance = 0.50 } } },
    octopus_demon     = { name = "章鱼魔",       level = 84, rarity = "common", hp = 8500, atk = 262, mAtk = 262, def = 1216, mdef = 1216, atkSpeed = 1, critVal = 67.20, critDmg = 50, hit = 37.35, dodge = 132.31, moveRange = 3, atkRange = 1, color = {100, 60, 160},  expReward = 19500, image = "image/monster_octopus_demon.png", drops = { { id = "octopus_tentacle", chance = 0.50 } } },
    nameless_horror   = { name = "形似章鱼的生物",     level = 88, rarity = "rare",   hp = 10000, atk = 390, def = 1250,   critVal = 88,     critDmg = 50, hit = 82,    dodge = 300,    moveRange = 5, atkRange = 4, color = {30, 10, 40},    expReward = 75000, image = "image/monster_nameless_horror.png", atkAttr = "magic", element = "shadow", noAffix = true, dropGroup = "DROP_GROUP_NAMELESS" },
    tree_fairy        = { name = "树精女妖",     level = 88, rarity = "common", hp = 9000, atk = 218, mAtk = 218, def = 1232, mdef = 1232, atkSpeed = 1, critVal = 70.40,  critDmg = 50, hit = 37.80, dodge = 142.86, moveRange = 3, atkRange = 3, color = {80, 180, 100},  expReward = 26000, image = "image/monster_tree_fairy.png", atkAttr = "magic", element = "nature", drops = { { id = "magic_leaf", chance = 0.50 }, { id = "dew_essence", chance = 0.10 } } },
    flower_fairy      = { name = "花仙妖精",     level = 92, rarity = "rare",   hp = 18000, atk = 450, def = 1300,   critVal = 92,     critDmg = 50, hit = 85,    dodge = 142.86, moveRange = 4, atkRange = 4, color = {255, 150, 200}, expReward = 100000, image = "image/monster_flower_fairy.png", atkAttr = "magic", element = "nature", noAffix = true, dropGroup = "DROP_GROUP_FLOWER_FAIRY", drops = { { id = "dew_essence", chance = 0.10 } } },
    -- Lv91-92 吸血鬼（两种变体）
    vampire_female    = { name = "女性吸血鬼",   level = 92, rarity = "common", hp = 10000, atk = 344, mAtk = 344, def = 1300, mdef = 1300, atkSpeed = 1, critVal = 121.44, critDmg = 50, hit = 46.41, dodge = 156.67, moveRange = 4, atkRange = 3, color = {160, 30, 60},   expReward = 32500, image = "image/monster_vampire_female.png", atkAttr = "magic", element = "shadow", drops = { { id = "cursed_cloak", chance = 0.50 } } },
    vampire_male      = { name = "男性吸血鬼",   level = 91, rarity = "common", hp = 11000, atk = 410, mAtk = 410, def = 1430, mdef = 1430, atkSpeed = 1, critVal = 120.12, critDmg = 50, hit = 39.60, dodge = 155,    moveRange = 4, atkRange = 1, color = {120, 20, 40},   expReward = 31200, image = "image/monster_vampire_male.png", drops = { { id = "cursed_cloak", chance = 0.50 } } },
    baron_baro        = { name = "\"巴洛\"伯爵", level = 100, rarity = "rare",  hp = 100000, atk = 700, def = 1800,  critVal = 133,    critDmg = 50, hit = 100,   dodge = 170,    moveRange = 3, atkRange = 1, color = {180, 160, 200}, expReward = 200000, image = "image/monster_baron_baro.png", atkAttr = "physical", noAffix = true, dropGroup = "DROP_GROUP_BARON" },
    -- Lv94 宇宙恶魔（两种变体）
    cosmos_demon_a    = { name = "宇宙恶魔",     level = 94, rarity = "common", hp = 11500, atk = 360, mAtk = 360, def = 1329, mdef = 1329, atkSpeed = 1, critVal = 124.08, critDmg = 50, hit = 46.92, dodge = 160,   moveRange = 4, atkRange = 3, color = {80, 40, 140},   expReward = 39000, image = "image/monster_cosmic_demon.png", atkAttr = "magic", element = "shadow", drops = { { id = "dark_cosmos_crystal", chance = 0.50 } } },
    cosmos_demon_elite = { name = "上等宇宙恶魔", level = 100, rarity = "rare", hp = 88000, atk = 680, def = 1650,   critVal = 133,    critDmg = 50, hit = 100,   dodge = 170,    moveRange = 5, atkRange = 5, color = {60, 20, 120},   expReward = 200000, image = "image/monster_cosmos_demon_elite.png", atkAttr = "magic", element = "shadow", noAffix = true, dropGroup = "DROP_GROUP_COSMOS_ELITE" },
    -- Lv97
    chimera           = { name = "蛇尾狮",       level = 97, rarity = "common", hp = 15000, atk = 500, mAtk = 500, def = 1650, mdef = 1650, atkSpeed = 1, critVal = 128.04, critDmg = 50, hit = 47.94, dodge = 165,   moveRange = 4, atkRange = 1, color = {200, 60, 40},   expReward = 52000, image = "image/monster_snake_tail_lion.png", drops = { { id = "chimera_mane", chance = 0.50 }, { id = "raw_lion", chance = 0.10 } } },
    fake_chimera      = { name = "伪奇美拉",     level = 100, rarity = "rare",  hp = 95000, atk = 720, def = 1700,   critVal = 133,    critDmg = 50, hit = 100,   dodge = 170,    moveRange = 4, atkRange = 1, color = {40, 40, 40},    expReward = 200000, image = "image/monster_fake_chimera.png", element = "ice", noAffix = true, dropGroup = "DROP_GROUP_FAKE_CHIMERA", drops = { { id = "raw_lion", chance = 0.10 } } },
    -- ============ 龙族 ============
    red_dragon_young  = { name = "红龙幼龙",     level = 110, rarity = "fine", hp = 500000, atk = 1200, mAtk = 1200, def = 3000, mdef = 3000, critVal = 150, critDmg = 50, hit = 150, dodge = 200, moveRange = 5, atkRange = 3, color = {220, 50, 30}, expReward = 1000000, image = "image/monster_red_dragon_young.png", atkAttr = "magic", element = "fire", size = 2, noAffix = true, drops = { { id = "red_dragon_ring", chance = 1.0, enchantTier = 9, forceEnchant = true, noRefineSlots = true, noGemSlots = true } } },

    -- ============ 城堡史莱姆 ============
    castle_slime      = { name = "城堡史莱姆",   level = 115, rarity = "common", hp = 22000, atk = 620, mAtk = 620, def = 2100, mdef = 2100, atkSpeed = 1, critVal = 140, critDmg = 50, hit = 50, dodge = 175, moveRange = 2, atkRange = 1, color = {160, 160, 180}, expReward = 50000, image = "image/monster_slime.png", atkAttr = "physical", drops = { { id = "slime_crystal", chance = 0.50 } } },

    -- ============ 石像鬼 ============
    gargoyle          = { name = "石像鬼",       level = 110, rarity = "epic", hp = 300000, atk = 5000, mAtk = 5000, def = 5000, mdef = 5000, atkSpeed = 1, critVal = 300, critDmg = 50, hit = 180, dodge = 200, moveRange = 4, atkRange = 1, color = {140, 140, 150}, expReward = 1000000, image = "image/monster_gargoyle.png", atkAttr = "physical", size = 2, noAffix = true },

    -- 训练假人（不移动、不攻击、无奖励）
    training_dummy    = { name = "训练假人",     level = 97, rarity = "common", hp = 99999999, atk = 0, def = 520.05, critVal = 0, critDmg = 0, hit = 0, dodge = 147.01, moveRange = 0, atkRange = 0, color = {180, 140, 80}, expReward = 0, image = "image/monster_training_dummy.png", noAffix = true, isTrainingDummy = true },

    -- ============ Lv85 潮汐祭祀圣所副本 ============
    fishman_elite_tidal    = { name = "鱼人精锐战士",     level = 85, rarity = "rare",     hp = 12500,  atk = 380, mAtk = 380, def = 1200, mdef = 1200, atkSpeed = 1, critVal = 70,  critDmg = 50, hit = 75,  dodge = 130, moveRange = 3, atkRange = 1, color = {60, 140, 180},  expReward = 16000,  image = "image/fishman_elite.png", atkAttr = "physical" },
    tidal_boss_jeni        = { name = "怕疼的\"杰尼\"",   level = 85, rarity = "fine",     hp = 100000, atk = 357, mAtk = 357, def = 1500, mdef = 1500, atkSpeed = 1, critVal = 80,  critDmg = 50, hit = 80,  dodge = 0,   moveRange = 2, atkRange = 1, color = {80, 180, 120},  expReward = 60000,  image = "image/boss_jenny.png", atkAttr = "physical" },
    tidal_boss_kuadi       = { name = "先知\"夸迪\"",     level = 85, rarity = "fine",     hp = 90000,  atk = 391, mAtk = 391, def = 1300, mdef = 1300, atkSpeed = 1, critVal = 90,  critDmg = 50, hit = 100, dodge = 140, moveRange = 3, atkRange = 4, color = {180, 160, 60},  expReward = 60000,  image = "image/boss_quadi.png", atkAttr = "magic", element = "thunder" },
    tidal_boss_unknown     = { name = "不可知物",         level = 85, rarity = "fine",     hp = 100000, atk = 255, mAtk = 255, def = 1000, mdef = 1000, atkSpeed = 1, critVal = 90,  critDmg = 50, hit = 120, dodge = 300, moveRange = 0, atkRange = 12, color = {60, 40, 80},   expReward = 80000,  image = "image/boss_unknown.png", atkAttr = "magic", element = "shadow", size = 2 },

    -- ============ 事件关卡友军 ============
    freya             = { name = "芙蕾雅",       level = 100, rarity = "superior",   hp = 9999,  atk = 1500, mAtk = 1500, def = 1500, mdef = 1500, critVal = 300, critDmg = 100, hit = 200, dodge = 230, moveRange = 4, atkRange = 1, atkSpeed = 50, color = {255, 215, 0}, image = "image/freya_icon.png", atkAttr = "physical", isEventAlly = true, noAffix = true },
    difen             = { name = "迪芬",         level = 45,  rarity = "superior",   hp = 500,   atk = 450,  mAtk = 450,  def = 1000, mdef = 1000, critVal = 50,  critDmg = 50,  hit = 300, dodge = 30,  moveRange = 2, atkRange = 1, color = {180, 160, 100}, expReward = 126, image = "image/difen_icon.png", atkAttr = "physical", isEventAlly = true, noAffix = true },

    -- ============ 无限塔特殊怪物 ============
    -- 守门人（无限塔第一层 BOSS）：双持匕首 + 闪烁突袭
    gatekeeper        = { name = "守门人",       level = 110, rarity = "superior",   hp = 1000000, atk = 2000, mAtk = 2000, def = 5000, mdef = 50000, atkSpeed = 200, critVal = 300, critDmg = 50, hit = 500, dodge = 350, moveRange = 5, atkRange = 1, color = {80, 40, 120}, expReward = 100000, image = "image/monster_gatekeeper.png", atkAttr = "physical", noAffix = true, weaponTag = "双匕首", extraStrike = 1, ai = "gatekeeper", gatekeeperFlashCD = 2, gatekeeperFlashRange = 3, gatekeeperFlashAtkSpd = 50 },
}

-- 怪物抗性/弱点设定
-- resistance: 抗该元素，受到该元素伤害减少 30%
-- weakness:   弱该元素，受到该元素伤害增加 30%
local MONSTER_ELEMENTS = {
    -- 元素史莱姆系
    fire_slime        = { resistance = {"fire"}, weakness = {"thunder"} },
    ice_slime         = { resistance = {"ice"}, weakness = {"fire"} },
    elec_slime        = { resistance = {"thunder"}, weakness = {"ice"} },
    fire_slime_elite  = { resistance = {"fire"}, weakness = {"thunder"} },
    ice_slime_elite   = { resistance = {"ice"}, weakness = {"fire"} },
    elec_slime_elite  = { resistance = {"thunder"}, weakness = {"ice"} },
    fire_slime_enraged = { resistance = {"fire"}, weakness = {"thunder"} },
    ice_slime_enraged  = { resistance = {"ice"}, weakness = {"fire"} },
    elec_slime_enraged = { resistance = {"thunder"}, weakness = {"ice"} },
    -- 蝙蝠系
    bat               = { weakness = {"thunder"} },
    rare_bat          = { weakness = {"thunder"} },
    vampire_youth     = { weakness = {"thunder"} },
    -- 狼系
    wolf              = { resistance = {"ice"}, weakness = {"fire"} },
    wolf_king         = { resistance = {"ice"}, weakness = {"fire"} },
    young_werewolf    = { resistance = {"ice"}, weakness = {"fire"} },
    -- 野猪系
    boar              = { resistance = {"ice"}, weakness = {"fire"} },
    boar_king         = { resistance = {"ice"}, weakness = {"fire"} },
    -- 熊系
    bear              = { resistance = {"ice"}, weakness = {"fire"} },
    black_bear_king   = { resistance = {"ice"}, weakness = {"fire"} },
    grey_bear         = { resistance = {"ice"}, weakness = {"fire"} },
    -- 哥布林系
    goblin            = { weakness = {"thunder"} },
    goblin_club       = { weakness = {"thunder"} },
    goblin_shield     = { weakness = {"thunder"} },
    goblin_archer     = { weakness = {"thunder"} },
    chest_goblin      = { weakness = {"thunder"} },
    -- 吸血系
    vampire_boy       = { weakness = {"holy"} },
    vampire_girl      = { weakness = {"holy"} },
    vampire_male      = { resistance = {"fire"}, weakness = {"holy"} },
    vampire_female    = { resistance = {"fire"}, weakness = {"holy"} },
    -- 树根精系
    tree_root         = { resistance = {"ice"}, weakness = {"fire"} },
    golden_tree_root  = { resistance = {"holy"}, weakness = {"fire"} },
    giant_tree_root   = { resistance = {"ice"}, weakness = {"fire"} },
    golden_giant_tree = { resistance = {"holy"}, weakness = {"fire"} },
    -- 恶魔史莱姆系
    demon_slime       = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    strange_demon_slime = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    -- 骷髅/亡灵系
    skeleton_sword    = { weakness = {"holy"} },
    skeleton_archer   = { weakness = {"holy"} },
    skeleton_king     = { weakness = {"holy"} },
    ghost             = { weakness = {"holy"} },
    grey_ghost        = { weakness = {"holy"} },
    mummy             = { weakness = {"holy"} },
    mummy_pharaoh     = { weakness = {"holy"} },
    -- 星恶魔系
    star_demon_round  = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    star_demon_elite  = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    star_demon_fat    = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    star_demon_fat_elite = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    -- 宇宙恶魔系
    cosmos_demon_a    = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    cosmos_demon_elite = { resistance = {"fire"}, weakness = {"holy", "ice"} },
    -- 妖怪系
    candle_monster    = { resistance = {"fire"}, weakness = {"ice"} },
    sofa_monster      = { resistance = {"ice"}, weakness = {"fire"} },
    book_monster      = { weakness = {"fire"} },
    piano_monster     = { weakness = {"fire"} },
    -- 岩壳龟系
    rock_turtle       = { resistance = {"fire"}, weakness = {"thunder"} },
    copper_turtle     = { resistance = {"ice"}, weakness = {"thunder"} },
    -- 人偶系
    butler_doll       = { resistance = {"thunder"}, weakness = {"ice"} },
    maid_doll         = { resistance = {"thunder"}, weakness = {"ice"} },
    knight_doll       = { resistance = {"thunder"}, weakness = {"ice"} },
    -- 鱼人系
    fishman           = { resistance = {"fire"}, weakness = {"thunder"} },
    fishman_warrior   = { resistance = {"fire"}, weakness = {"thunder"} },
    -- 海洋系
    five_eye_starfish = { resistance = {"fire"}, weakness = {"thunder"} },
    octopus_demon     = { resistance = {"holy"}, weakness = {"thunder"} },
    nameless_horror   = { resistance = {"holy"}, weakness = {"thunder"} },
    -- 森林系
    tree_fairy        = { resistance = {"holy"}, weakness = {"fire"} },
    flower_fairy      = { resistance = {"holy"}, weakness = {"fire"} },
    -- 龙族
    red_dragon_young  = { resistance = {"fire"} },
    gargoyle          = { resistance = {"ice"}, weakness = {"holy"} },
    -- 潮汐祭祀圣所
    fishman_elite_tidal = { resistance = {"fire"}, weakness = {"thunder"} },
    tidal_boss_jeni     = { resistance = {"fire"}, weakness = {"thunder"} },
    tidal_boss_kuadi    = { resistance = {"fire"}, weakness = {"thunder"} },
    tidal_boss_unknown  = { resistance = {"ice"}, weakness = {"holy"} },
}
for key, elem in pairs(MONSTER_ELEMENTS) do
    if db[key] then
        db[key].resistance = elem.resistance
        db[key].weakness   = elem.weakness
    end
end

-- 为所有怪物补充默认字段
for _, mdef in pairs(db) do
    mdef.maxHp     = mdef.maxHp     or mdef.hp
    mdef.mdef      = mdef.mdef      or mdef.def        -- 魔法防御力，默认等于物理防御力
    mdef.mAtk      = mdef.mAtk      or mdef.atk        -- 魔法攻击力，默认等于物理攻击力
    mdef.atkAttr   = mdef.atkAttr   or "physical"      -- 攻击类型：physical / magic
    mdef.mCritRate = mdef.mCritRate or mdef.critVal     -- 魔法暴击值，默认等于物理暴击值
    mdef.mCritDmg  = mdef.mCritDmg  or mdef.critDmg    -- 魔法暴击伤害，默认等于物理暴击伤害
    -- element 不设默认值，nil 表示无元素属性
end

return db
