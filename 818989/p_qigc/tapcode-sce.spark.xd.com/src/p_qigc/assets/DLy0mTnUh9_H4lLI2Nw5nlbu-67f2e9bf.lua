-- ====================================================================
-- GameState.lua - 游戏状态、常量、工具函数、属性计算
-- ====================================================================
-- 为联机做准备：所有游戏状态集中管理，便于服务端同步
-- ====================================================================

local M = {}

-- ====================================================================
-- GM 管理员系统
-- ====================================================================
M.GM_IDS = {
    ["1576069892"] = true,
    ["74809094"] = true,
}

--- 判断当前用户是否为 GM（需要 clientCloud 已初始化）
function M.isGM()
    if clientCloud and clientCloud.userId then
        return M.GM_IDS[tostring(clientCloud.userId)] == true
    end
    return false
end

-- ====================================================================
-- 游戏状态常量
-- ====================================================================
M.STATE_MENU      = 0
M.STATE_PLAYER    = 1   -- 玩家回合（等待点击角色）
M.STATE_SELECT    = 2   -- 已选中角色，显示移动/攻击范围
M.STATE_ENEMY     = 3   -- 敌人回合
M.STATE_RESPAWN   = 4   -- 复活倒计时中
M.STATE_GAMEOVER  = 5
M.STATE_COMPANION = 6   -- 友军回合（猎犬等）
M.STATE_CHAR_SELECT = 7 -- 角色选择界面
M.STATE_CHAR_CREATE = 8 -- 创建新角色界面

-- 回合阶段定义
M.PHASE_PRE    = "pre"       -- 回合前阶段（预留）
M.PHASE_MOVE   = "move"      -- 移动阶段
M.PHASE_MID    = "mid"       -- 中间阶段（预留）
M.PHASE_ACTION = "action"    -- 行动阶段
M.PHASE_END    = "end_turn"  -- 回合结束阶段（预留）

-- ====================================================================
-- ====================================================================
-- 游戏版本号（与选择角色界面底部显示保持同步）
-- ====================================================================
M.APP_VERSION = "ver0.127"

-- ====================================================================
-- 布局常量
-- ====================================================================
M.BOARD_SIZE = 12
M.INV_COLS = 5        -- 布局计算基准列数（决定格子大小）
M.INV_ROWS = 7        -- 布局计算基准行数（一页最多显示行数）
M.INV_SHOW_COLS = 5   -- 实际显示列数
M.INV_SHOW_ROWS = 7   -- 一页最多显示行数
M.INVENTORY_SLOTS = M.INV_SHOW_COLS * 8  -- 40 格（超出7行滚动）
M.TOP_BAR_H = 44
M.safeTop = 0               -- 顶部安全区域（灵动岛/刘海屏）
M.TOP_BAR_CONTENT_MID_Y = 22  -- 顶栏内容垂直中心
M.EXP_BAR_H = 5   -- 经验条高度
M.EXP_GAP = 3     -- 经验条与状态栏间距
M.DESIGN_W = 450   -- 设计分辨率宽度（竖版基准）
M.RESPAWN_TIME = 5.0  -- 复活等待秒数
M.MAX_MONSTERS = 3  -- 同时存在的最大怪物数量
M.AUTO_DELAY = 0.15   -- 自动行动间隔（秒）

-- 设置面板几何常量
M.SETTINGS_PANEL_W = 180
M.SETTINGS_PANEL_H = 274
M.SLIDER_TRACK_MARGIN_X = 16
M.SLIDER_TRACK_H = 6
M.SLIDER_KNOB_R = 8

-- ====================================================================
-- 技能树定义（多职业）
-- ====================================================================
M.SKILL_MAX_LEVEL = 10

--- 当前职业
M.currentClass = "warrior"

--- 职业列表
M.CLASS_LIST = { "warrior", "hunter", "assassin", "mage", "priest" }
M.CLASS_NAMES = {
    warrior  = "战士",
    hunter   = "猎人",
    assassin = "刺客",
    mage     = "法师",
    priest   = "牧师",
    traveler = "旅人",
}
M.CLASS_COLORS = {
    warrior  = {200, 80, 80},
    hunter   = {80, 180, 60},
    assassin = {180, 60, 180},
    mage     = {60, 120, 220},
    priest   = {220, 200, 60},
    traveler = {160, 160, 160},
}


-- ====================================================================
-- 角色/怪物定义
-- ====================================================================
M.PLAYER_DEFS = {
    warrior = {
        name = "战士",
        stats = { str = 1, agi = 1, con = 1, wis = 1, foc = 1, per = 1, wil = 1, luk = 1, cha = 1 },
        color = {60, 120, 220},
        level = 1, exp = 0, statPoints = 3,
    },
    hunter = {
        name = "猎人",
        stats = { str = 1, agi = 1, con = 1, wis = 1, foc = 1, per = 1, wil = 1, luk = 1, cha = 1 },
        color = {80, 180, 60},
        level = 1, exp = 0, statPoints = 3,
    },
    assassin = {
        name = "刺客",
        stats = { str = 1, agi = 1, con = 1, wis = 1, foc = 1, per = 1, wil = 1, luk = 1, cha = 1 },
        color = {180, 60, 180},
        level = 1, exp = 0, statPoints = 3,
    },
    mage = {
        name = "法师",
        stats = { str = 1, agi = 1, con = 1, wis = 1, foc = 1, per = 1, wil = 1, luk = 1, cha = 1 },
        color = {200, 80, 80},
        level = 1, exp = 0, statPoints = 3,
    },
    priest = {
        name = "牧师",
        stats = { str = 1, agi = 1, con = 1, wis = 1, foc = 1, per = 1, wil = 1, luk = 1, cha = 1 },
        color = {220, 200, 60},
        level = 1, exp = 0, statPoints = 3,
    },
    traveler = {
        name = "旅人",
        stats = { str = 1, agi = 1, con = 1, wis = 1, foc = 1, per = 1, wil = 1, luk = 1, cha = 1 },
        color = {160, 160, 160},
        level = 1, exp = 0, statPoints = 3,
    },
}
--- 兼容：PLAYER_DEF 指向当前职业
M.PLAYER_DEF = M.PLAYER_DEFS.warrior

--- 怪物数据库（数据已提取到 data/MonsterDB.lua）
M.MONSTER_DB = require("data.MonsterDB")
-- 自动为每个怪物定义注入 id 字段
for k, v in pairs(M.MONSTER_DB) do v.id = k end

-- ====================================================================
-- 关卡定义（按关卡分类管理怪物生成）
-- ====================================================================
-- 按等级排序的怪物key列表（用于生成关卡）
M.MONSTER_ORDER = {
    "slime", "item_slime", "fire_slime", "ice_slime", "elec_slime", "bat", "rare_bat",
    "wolf", "wolf_king",
    "boar", "boar_king", "bear", "black_bear_king",
    "goblin", "goblin_club", "goblin_shield", "goblin_archer", "chest_goblin",
    "fierce_wolf", "young_werewolf", "vampire_youth", "vampire_girl",
    "tree_root", "golden_tree_root", "demon_slime", "strange_demon_slime",
    "skeleton_sword", "skeleton_archer", "skeleton_king",
    "ghost", "grey_ghost", "slime_elite", "fire_slime_elite", "ice_slime_elite", "elec_slime_elite", "slime_princess", "slime_prince", "slime_king", "star_demon_round", "star_demon_elite",
    "candle_monster", "sofa_monster", "book_monster", "piano_monster",
    "rock_turtle", "copper_turtle",
    "butler_doll", "maid_doll", "knight_doll",
    "mummy", "mummy_pharaoh",
    "giant_tree_root", "golden_giant_tree",
    "fishman", "fishman_warrior",
    "centaur_hunter", "centaur_warrior", "centaur_priest",
    "star_demon_fat", "star_demon_fat_elite",
    "five_eye_starfish", "octopus_demon", "nameless_horror", "tree_fairy", "flower_fairy",
    "vampire_female", "vampire_male", "baron_baro",
    "cosmos_demon_a", "cosmos_demon_elite",
    "chimera", "fake_chimera",
}

-- 关卡默认参数
local STAGE_DEFAULTS = {
    maxMonsters     = 3,
    spawnInterval   = 2,
    spawnThresholds = {3},
    spawnCounts     = {1, 2},
    advanceTurn     = 999,
}

-- 自动为每种怪物生成测试关卡（用于设置菜单的关卡测试功能，一关一种怪物，无混合）
M.STAGE_DEFS = {}
for i, key in ipairs(M.MONSTER_ORDER) do
    local mdef = M.MONSTER_DB[key]
    M.STAGE_DEFS[i] = {
        name            = mdef.name,
        maxMonsters     = STAGE_DEFAULTS.maxMonsters,
        spawnInterval   = STAGE_DEFAULTS.spawnInterval,
        spawnThresholds = STAGE_DEFAULTS.spawnThresholds,
        spawnCounts     = STAGE_DEFAULTS.spawnCounts,
        advanceTurn     = STAGE_DEFAULTS.advanceTurn,
        monsters        = { { weight = 1, def = mdef } },
    }
end

-- 怪物key → 测试关卡索引的反查表（设置菜单关卡测试用）
M.STAGE_INDEX = {}
for i, key in ipairs(M.MONSTER_ORDER) do
    M.STAGE_INDEX[key] = i
end

-- ====================================================================
-- 地图关卡定义（手动配置，用于实际地图入口）
-- ====================================================================

-- 平原入口：史莱姆
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "平原入口",
    maxMonsters = 3,
    maxMonstersByLevel = {1, 3},
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.slime },
        { weight = 1,  def = M.MONSTER_DB.item_slime },
    },
}
M.STAGE_SLIME = #M.STAGE_DEFS

-- 森林入口：野猪
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林入口",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 8},
    spawnCounts = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.bat },
        { weight = 1,  def = M.MONSTER_DB.rare_bat },
    },
}
M.STAGE_BAT = #M.STAGE_DEFS

-- 森林外围一：野狼
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林外围一",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.wolf },
        { weight = 1,  def = M.MONSTER_DB.wolf_king },
    },
}
M.STAGE_WOLF = #M.STAGE_DEFS

-- 森林外围二：蝙蝠
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林外围二",
    maxMonsters = 2,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.boar },
        { weight = 1,  def = M.MONSTER_DB.boar_king },
    },
}
M.STAGE_BOAR = #M.STAGE_DEFS

-- 森林中心一：幼狼人
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林中心一",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.fierce_wolf },
        { weight = 1,  def = M.MONSTER_DB.young_werewolf },
    },
}
M.STAGE_FIERCE_WOLF = #M.STAGE_DEFS

-- 森林中心二：树根精
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林中心二",
    maxMonsters = 2,
    spawnInterval = 1,
    spawnThresholds = {},
    spawnCounts = {1},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.tree_root },
        { weight = 1,  def = M.MONSTER_DB.golden_tree_root },
    },
}
M.STAGE_TREE_ROOT = #M.STAGE_DEFS

-- 森林中心三：野熊
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林中心三",
    maxMonsters = 2,
    spawnInterval = 1,
    spawnThresholds = {},
    spawnCounts = {1},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.bear },
        { weight = 1,  def = M.MONSTER_DB.black_bear_king },
    },
}
M.STAGE_BEAR = #M.STAGE_DEFS

-- 平原外围：哥布林
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "平原外围",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 8},
    spawnCounts = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.goblin },
    },
}
M.STAGE_GOBLIN = #M.STAGE_DEFS

-- 庄园入口：吸血魔蝠
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园入口",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 8},
    spawnCounts = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.vampire_youth },
        -- { weight = 0.5, def = M.MONSTER_DB.vampire_boy },  -- 暂时移除，避免与斩首·吸血少女任务混淆
        { weight = 0.5, def = M.MONSTER_DB.vampire_girl },
    },
}
M.STAGE_VAMPIRE_YOUTH = #M.STAGE_DEFS

-- 平原深处：恶魔史莱姆
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "平原深处",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.demon_slime },
        { weight = 1,  def = M.MONSTER_DB.strange_demon_slime },
    },
}
M.STAGE_DEMON_SLIME = #M.STAGE_DEFS

-- 平原深处的墓地：骷髅兵
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "平原深处的墓地",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 49, def = M.MONSTER_DB.skeleton_sword },
        { weight = 49, def = M.MONSTER_DB.skeleton_archer },
        { weight = 1,  def = M.MONSTER_DB.skeleton_king },
    },
}
M.STAGE_SKELETON = #M.STAGE_DEFS

-- 庄园一楼：幽灵
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园一楼",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.ghost },
        { weight = 1,  def = M.MONSTER_DB.grey_ghost },
    },
}
M.STAGE_GHOST = #M.STAGE_DEFS

-- 城下森林入口：圆滚滚星恶魔
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下森林入口",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 8},
    spawnCounts = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.star_demon_round },
        { weight = 1,  def = M.MONSTER_DB.star_demon_elite },
    },
}
M.STAGE_STAR_DEMON_ROUND = #M.STAGE_DEFS

-- 灰山脚下森林入口：灰熊
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰山脚下森林入口",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.grey_bear },
        { weight = 1,  def = M.MONSTER_DB.black_bear_king },
    },
}
M.STAGE_GREY_BEAR = #M.STAGE_DEFS

-- 灰海海岸：岩壳龟
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰海海岸",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.rock_turtle },
        { weight = 1,  def = M.MONSTER_DB.copper_turtle },
    },
}
M.STAGE_ROCK_TURTLE = #M.STAGE_DEFS

-- 墓穴：木乃伊
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "墓穴入口",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.mummy },
        { weight = 1,  def = M.MONSTER_DB.mummy_pharaoh },
    },
}
M.STAGE_MUMMY = #M.STAGE_DEFS

-- 森林深处一：大型树根精
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林深处一",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.giant_tree_root },
        { weight = 1,  def = M.MONSTER_DB.golden_giant_tree },
    },
}
M.STAGE_GIANT_TREE_ROOT = #M.STAGE_DEFS

-- 城下森林外围：胖乎乎星恶魔
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下森林外围",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 8},
    spawnCounts = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.star_demon_fat },
        { weight = 1,  def = M.MONSTER_DB.star_demon_fat_elite },
    },
}
M.STAGE_STAR_DEMON_FAT = #M.STAGE_DEFS

-- 森林深处二：树精女妖
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林深处二",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.tree_fairy },
        { weight = 1,  def = M.MONSTER_DB.flower_fairy },
    },
}
M.STAGE_TREE_FAIRY = #M.STAGE_DEFS

-- 城下森林深处：蛇尾狮
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下森林深处",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {},
    spawnCounts = {1},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.chimera },
        { weight = 1,  def = M.MONSTER_DB.fake_chimera },
    },
}
M.STAGE_CHIMERA = #M.STAGE_DEFS

-- ====================================================================
-- 自定义混合关卡（多种怪物混合出现）
-- ====================================================================

-- 大群哥布林（多种哥布林混合出现，数量更多）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "平原中心",
    maxMonsters = 5,
    spawnInterval = 2,
    spawnThresholds = {2, 5},
    spawnCounts     = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 33, def = M.MONSTER_DB.goblin_club },
        { weight = 33, def = M.MONSTER_DB.goblin_shield },
        { weight = 33, def = M.MONSTER_DB.goblin_archer },
        { weight = 1,  def = M.MONSTER_DB.chest_goblin },
    },
}
M.STAGE_GOBLIN_SWARM = #M.STAGE_DEFS  -- 记录索引供地图引用

-- 自定义混合关卡：家具妖怪（烛台、沙发、书本妖怪混合）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园二楼",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 8},
    spawnCounts     = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 33, def = M.MONSTER_DB.candle_monster },
        { weight = 33, def = M.MONSTER_DB.sofa_monster },
        { weight = 33, def = M.MONSTER_DB.book_monster },
        { weight = 1,  def = M.MONSTER_DB.piano_monster },
    },
}
M.STAGE_FURNITURE = #M.STAGE_DEFS

-- 自定义混合关卡：人偶（管家人偶、女仆人偶混合）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园三楼",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts     = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 49, def = M.MONSTER_DB.butler_doll },
        { weight = 49, def = M.MONSTER_DB.maid_doll },
        { weight = 1,  def = M.MONSTER_DB.knight_doll },
    },
}
M.STAGE_DOLLS = #M.STAGE_DEFS

-- 自定义混合关卡：鱼人（鱼人、鱼人战士混合）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰海浅滩",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts     = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 98, def = M.MONSTER_DB.fishman },
        { weight = 1,  def = M.MONSTER_DB.fishman_warrior },
    },
}
M.STAGE_TURTLE_SHARK = #M.STAGE_DEFS

-- 自定义混合关卡：双魔（章鱼魔、五眼海星混合）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰海海边洞窟",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts     = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 49, def = M.MONSTER_DB.octopus_demon },
        { weight = 49, def = M.MONSTER_DB.five_eye_starfish },
        { weight = 1,  def = M.MONSTER_DB.nameless_horror },
    },
}
M.STAGE_SEA_DEMONS = #M.STAGE_DEFS

-- 自定义混合关卡：半人马（半人马猎手、半人马战士混合）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰山脚下森林",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts     = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 49, def = M.MONSTER_DB.centaur_hunter },
        { weight = 49, def = M.MONSTER_DB.centaur_warrior },
        { weight = 1,  def = M.MONSTER_DB.centaur_priest },
    },
}
M.STAGE_CENTAURS = #M.STAGE_DEFS

-- 自定义关卡：宇宙恶魔
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下森林中心",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts     = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 99, def = M.MONSTER_DB.cosmos_demon_a },
        { weight = 1, def = M.MONSTER_DB.cosmos_demon_elite },
    },
}
M.STAGE_COSMOS_DEMONS = #M.STAGE_DEFS

-- 自定义混合关卡：吸血鬼（女吸血鬼、男吸血鬼混合）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园四楼",
    maxMonsters = 3,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    monsters = {
        { weight = 49, def = M.MONSTER_DB.vampire_female },
        { weight = 49, def = M.MONSTER_DB.vampire_male },
        { weight = 1, def = M.MONSTER_DB.baron_baro },
    },
}
M.STAGE_VAMPIRES = #M.STAGE_DEFS

-- 自定义混合关卡：史莱姆王国副本（公主、王子、国王混合）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "史莱姆王国",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 7},
    spawnCounts     = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 3, def = M.MONSTER_DB.slime_elite },
        { weight = 2, def = M.MONSTER_DB.fire_slime_elite },
        { weight = 2, def = M.MONSTER_DB.ice_slime_elite },
        { weight = 2, def = M.MONSTER_DB.elec_slime_elite },
        { weight = 1, def = M.MONSTER_DB.slime_princess },
        { weight = 1, def = M.MONSTER_DB.slime_prince },
        { weight = 1, def = M.MONSTER_DB.slime_king },
    },
}
M.STAGE_SLIME_KINGDOM = #M.STAGE_DEFS

-- 哥布林竞技场（副本）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "哥布林竞技场",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 7},
    spawnCounts     = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 1, def = M.MONSTER_DB.goblin_warrior_arena },
        { weight = 1, def = M.MONSTER_DB.goblin_boss_diwu },
        { weight = 1, def = M.MONSTER_DB.goblin_boss_dila },
        { weight = 1, def = M.MONSTER_DB.goblin_boss_dikata },
    },
}
M.STAGE_GOBLIN_ARENA = #M.STAGE_DEFS

-- 潮汐祭祀圣所（副本）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "潮汐祭祀圣所",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3, 7},
    spawnCounts     = {1, 2, 3},
    advanceTurn = 999,
    monsters = {
        { weight = 8, def = M.MONSTER_DB.fishman },
        { weight = 2, def = M.MONSTER_DB.fishman_warrior },
    },
}
M.STAGE_TIDAL_SANCTUARY = #M.STAGE_DEFS

-- 采集关卡：植物茂盛区入口
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "植物茂盛区入口",
    maxMonsters = 5,
    spawnInterval = 99999,        -- 不再后续刷新
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,           -- 标记：初始刷新后不再刷新新怪物和采集物
    spawnAnywhere = true,       -- 全图随机刷怪（非边缘）
    monsters = {
        { weight = 100, def = M.MONSTER_DB.slime },
    },
    initialMonsterCount = 5,    -- 1级史莱姆×5
}
M.STAGE_GATHER_PLAIN_LV1 = #M.STAGE_DEFS

-- 采集关卡：植物茂盛区中心（Lv30）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "植物茂盛区中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 34, def = M.MONSTER_DB.fire_slime },
        { weight = 33, def = M.MONSTER_DB.ice_slime },
        { weight = 33, def = M.MONSTER_DB.elec_slime },
    },
    initialMonsterCount = 5,    -- 火/冰/电史莱姆随机×5
}
M.STAGE_GATHER_PLAIN_LV2 = #M.STAGE_DEFS

-- 采集关卡：植物茂盛区深处（Lv60）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "植物茂盛区深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 25, def = M.MONSTER_DB.goblin },
        { weight = 25, def = M.MONSTER_DB.goblin_club },
        { weight = 25, def = M.MONSTER_DB.goblin_shield },
        { weight = 25, def = M.MONSTER_DB.goblin_archer },
    },
    initialMonsterCount = 5,    -- 4种哥布林随机×5
}
M.STAGE_GATHER_PLAIN_LV3 = #M.STAGE_DEFS

-- 采集关卡：平原矿洞入口（Lv1）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "平原矿洞入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 34, def = M.MONSTER_DB.fire_slime },
        { weight = 33, def = M.MONSTER_DB.ice_slime },
        { weight = 33, def = M.MONSTER_DB.elec_slime },
    },
    initialMonsterCount = 5,    -- 火/冰/电史莱姆随机×5
}
M.STAGE_GATHER_PLAIN_MINE_LV1 = #M.STAGE_DEFS

-- 采集关卡：平原矿洞开发区（Lv30）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "平原矿洞开发区",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 25, def = M.MONSTER_DB.goblin },
        { weight = 25, def = M.MONSTER_DB.goblin_club },
        { weight = 25, def = M.MONSTER_DB.goblin_shield },
        { weight = 25, def = M.MONSTER_DB.goblin_archer },
    },
    initialMonsterCount = 5,    -- 4种哥布林随机×5
}
M.STAGE_GATHER_PLAIN_MINE_LV2 = #M.STAGE_DEFS

-- 采集关卡：森林矿洞入口（蝙蝠 Lv3）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林矿洞入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.bat },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FOREST_LV1 = #M.STAGE_DEFS

-- 采集关卡：森林矿洞开发区（野狼 Lv7）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林矿洞开发区",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.wolf },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FOREST_LV2 = #M.STAGE_DEFS

-- 采集关卡：森林矿洞中心（凶狼 Lv20）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林矿洞中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.fierce_wolf },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FOREST_LV3 = #M.STAGE_DEFS

-- 采集关卡：森林矿洞深处（野熊 Lv43）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "森林矿洞深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.bear },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FOREST_LV4 = #M.STAGE_DEFS

-- 采集关卡：海边矿洞入口（Lv150）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "海边矿洞入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.goblin },
        { weight = 30, def = M.MONSTER_DB.goblin_club },
        { weight = 20, def = M.MONSTER_DB.goblin_shield },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_SEA_LV1 = #M.STAGE_DEFS

-- 采集关卡：海边矿洞前段（Lv150）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "海边矿洞前段",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.rock_turtle },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_SEA_LV2 = #M.STAGE_DEFS

-- 采集关卡：海边矿洞中心（Lv150）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "海边矿洞中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.fishman },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_SEA_LV3 = #M.STAGE_DEFS

-- 采集关卡：海边矿洞深处（Lv150）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "海边矿洞深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.five_eye_starfish },
        { weight = 50, def = M.MONSTER_DB.octopus_demon },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_SEA_LV4 = #M.STAGE_DEFS

-- 采集关卡：灰海-海边植物区入口（Lv54）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "海边植物区入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.goblin },
        { weight = 30, def = M.MONSTER_DB.goblin_club },
        { weight = 20, def = M.MONSTER_DB.goblin_shield },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_GREY_SEA_LV1 = #M.STAGE_DEFS

-- 采集关卡：灰海-海边植物区中心（Lv69）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "海边植物区中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.rock_turtle },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_GREY_SEA_LV2 = #M.STAGE_DEFS

-- 采集关卡：灰海-海边植物区深处（Lv85）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "海边植物区深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.fishman },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_GREY_SEA_LV3 = #M.STAGE_DEFS

-- 采集关卡：山崖矿洞入口（Lv46）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "山崖矿洞入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.grey_bear },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MOUNT_LV1 = #M.STAGE_DEFS

-- 采集关卡：山崖矿洞前段（Lv46）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "山崖矿洞前段",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.grey_bear },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MOUNT_LV2 = #M.STAGE_DEFS

-- 采集关卡：山崖矿洞中心（Lv120）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "山崖矿洞中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.centaur_warrior },
        { weight = 50, def = M.MONSTER_DB.centaur_hunter },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MOUNT_LV3 = #M.STAGE_DEFS

-- 采集关卡：山崖矿洞深处（Lv120）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "山崖矿洞深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.centaur_warrior },
        { weight = 50, def = M.MONSTER_DB.centaur_hunter },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MOUNT_LV4 = #M.STAGE_DEFS

-- 采集关卡：垂雾森林-植物繁茂区入口（蝙蝠 Lv3）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "植物繁茂区入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.bat },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MIST_FOREST_LV1 = #M.STAGE_DEFS

-- 采集关卡：垂雾森林-植物繁茂区中心（野猪 Lv11）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "植物繁茂区中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.boar },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MIST_FOREST_LV2 = #M.STAGE_DEFS

-- 采集关卡：垂雾森林-植物繁茂区深处（树根精 Lv29）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "植物繁茂区深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.tree_root },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MIST_FOREST_LV3 = #M.STAGE_DEFS

-- 采集关卡：巴洛庄园-庄园种植区入口（Lv24）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园种植区入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.vampire_youth },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MANOR_LV1 = #M.STAGE_DEFS

-- 采集关卡：巴洛庄园-庄园种植区中心（Lv42）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园种植区中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.ghost },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MANOR_LV2 = #M.STAGE_DEFS

-- 采集关卡：巴洛庄园-庄园种植区深处（Lv57）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园种植区深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.candle_monster },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MANOR_LV3 = #M.STAGE_DEFS

-- 采集关卡：巴洛庄园-庄园隐秘花房（Lv91）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "庄园隐秘花房",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.maid_doll },
        { weight = 50, def = M.MONSTER_DB.butler_doll },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_MANOR_LV4 = #M.STAGE_DEFS

-- 采集关卡：灰山-植物繁茂区入口（Lv46）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰山植物繁茂区入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.grey_bear },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_GREY_MT_LV1 = #M.STAGE_DEFS

-- 采集关卡：灰山-植物繁茂区中心（Lv90）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰山植物繁茂区中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.centaur_warrior },
        { weight = 50, def = M.MONSTER_DB.centaur_hunter },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_GREY_MT_LV2 = #M.STAGE_DEFS

-- 采集关卡：灰山-植物繁茂区深处（Lv120）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "灰山植物繁茂区深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 50, def = M.MONSTER_DB.centaur_warrior },
        { weight = 50, def = M.MONSTER_DB.centaur_hunter },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_GREY_MT_LV3 = #M.STAGE_DEFS

-- 采集关卡：升月堡-城下花园入口（Lv46）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下花园入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.star_demon_round },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FORT_LV1 = #M.STAGE_DEFS

-- 采集关卡：升月堡-城下花园中心（Lv79）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下花园中心",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.star_demon_fat },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FORT_LV2 = #M.STAGE_DEFS

-- 采集关卡：升月堡-城下花园深处（Lv97）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下花园深处",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.cosmos_demon_a },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FORT_LV3 = #M.STAGE_DEFS

-- 采集关卡：升月堡-城下深窟入口（Lv79）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下深窟入口",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.star_demon_fat },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FORT_MINE_LV1 = #M.STAGE_DEFS

-- 采集关卡：升月堡-城下深窟通道（Lv94）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下深窟通道",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.cosmos_demon_a },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FORT_MINE_LV2 = #M.STAGE_DEFS

-- 采集关卡：升月堡-城下深窟通道后段（Lv97）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下深窟通道后段",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.chimera },
    },
    initialMonsterCount = 5,
}
M.STAGE_GATHER_FORT_MINE_LV2B = #M.STAGE_DEFS

-- 采集关卡：升月堡-城下深窟开阔区
-- 默认：5只蛇尾狮(Lv97)
-- 接了"红龙与魔女"任务时：动态切换为1只红龙幼龙(Lv110)
-- 击杀红龙幼龙后：恢复为5只蛇尾狮
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城下深窟开阔区",
    maxMonsters = 5,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {0},
    advanceTurn = 999,
    noRespawn = true,
    spawnAnywhere = true,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.chimera },
    },
    initialMonsterCount = 5,
    -- 动态怪物覆盖：由 Combat_Spawn 在刷新时检查任务状态
    dynamicMonsterOverride = "red_dragon_quest",
}
M.STAGE_GATHER_FORT_MINE_LV3 = #M.STAGE_DEFS

-- 训练场关卡：只刷1个训练假人在中央，不再刷新
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "训练场",
    maxMonsters = 1,
    spawnInterval = 99999,
    spawnThresholds = {999},
    spawnCounts     = {1},
    advanceTurn = 999,
    initialMonsterCount = 1,
    monsters = {
        { weight = 1, def = M.MONSTER_DB.training_dummy },
    },
    isTrainingStage = true,
}
M.STAGE_TRAINING = #M.STAGE_DEFS

-- 升月堡正门桥梁：石像鬼
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "升月堡正门桥梁",
    maxMonsters = 3,
    spawnInterval = 3,
    spawnThresholds = {},
    spawnCounts = {1},
    advanceTurn = 999,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.gargoyle },
    },
}
M.STAGE_FORT_BRIDGE = #M.STAGE_DEFS

-- 升月堡城堡前厅：城堡史莱姆（占位关卡）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "城堡前厅",
    maxMonsters = 4,
    spawnInterval = 2,
    spawnThresholds = {3},
    spawnCounts = {1, 2},
    advanceTurn = 999,
    monsters = {
        { weight = 100, def = M.MONSTER_DB.castle_slime },
    },
}
M.STAGE_CASTLE_HALL = #M.STAGE_DEFS

-- ========== 异世深渊（5层） ==========
-- 蛇尾狮基础属性作为缩放基准
local CHIMERA_BASE = M.MONSTER_DB.chimera
local ABYSS_FLOORS = {
    { name = "深渊一层", maxLv =  20, level = 105, mult =  1.2, hpMult =  1.2, hitMult = 1.2, dodgeMult = 1.2, critMult = 1.2, spawnCount = 3, maxMonsters = 15 },
    { name = "深渊二层", maxLv =  40, level = 110, mult =  1.8, hpMult =  2.0, hitMult = 1.4, dodgeMult = 1.5, critMult = 1.7, spawnCount = 4, maxMonsters = 18 },
    { name = "深渊三层", maxLv =  60, level = 120, mult =  3.0, hpMult =  3.5, hitMult = 1.7, dodgeMult = 1.8, critMult = 2.2, spawnCount = 5, maxMonsters = 21 },
    { name = "深渊四层", maxLv =  80, level = 130, mult =  5.0, hpMult =  6.0, hitMult = 2.0, dodgeMult = 2.1, critMult = 2.7, spawnCount = 7, maxMonsters = 24 },
    { name = "深渊五层", maxLv = 100, level = 140, mult = 10.0, hpMult = 10.0, hitMult = 3.0, dodgeMult = 2.4, critMult = 3.2, spawnCount = 9, maxMonsters = 27 },
}

-- 常规区怪物key列表（排除酒馆、副本、boss、事件等特殊怪物）
local ABYSS_EXCLUDE = {
    tavern_thug = true, drunk_man = true, scarface = true,
    tavern_thug_25 = true, drunk_man_25 = true, scarface_25 = true,
    item_slime = true, chest_goblin = true, training_dummy = true, freya = true,
    -- 副本怪
    slime_elite = true, fire_slime_elite = true, ice_slime_elite = true, elec_slime_elite = true,
    slime_princess = true, slime_prince = true, slime_king = true,
    goblin_warrior_arena = true, goblin_boss_diwu = true, goblin_boss_dila = true, goblin_boss_dikata = true,
    fishman_elite_tidal = true, tidal_boss_jeni = true, tidal_boss_kuadi = true, tidal_boss_unknown = true,
    -- 龙族/城堡/石像鬼
    red_dragon_young = true, castle_slime = true, gargoyle = true,
    -- 大反击专属（不死Boss / 0经验小怪）
    slime_king_enraged = true, fire_slime_enraged = true, ice_slime_enraged = true, elec_slime_enraged = true,
    goblin_hero_dihata = true,
}

-- 按等级范围收集常规区怪物
local function collectAbyssMonsters(maxLv)
    local list = {}
    for key, mdef in pairs(M.MONSTER_DB) do
        if not ABYSS_EXCLUDE[key] and not mdef.isEventAlly and mdef.level <= maxLv then
            list[#list + 1] = key
        end
    end
    return list
end

-- 深渊基础掉落组
M.ABYSS_BASIC_DROP_POOL = {
    "abyss_soldier_sword",    "abyss_soldier_dagger",  "abyss_soldier_mace",
    "abyss_soldier_bow",      "abyss_soldier_staff",
    "abyss_soldier_quiver",   "abyss_soldier_orb",     "abyss_soldier_shield",
    "abyss_soldier_chest",    "abyss_soldier_pants",   "abyss_soldier_hat",
    "abyss_soldier_shoulder", "abyss_soldier_cloak",   "abyss_soldier_gloves",
    "abyss_soldier_belt",     "abyss_soldier_boots",
}

-- 生成缩放后的怪物变体定义
local function makeAbyssVariant(srcKey, floorLevel, mult, floorIndex, hpMult, hitMult, dodgeMult, critMult)
    local src = M.MONSTER_DB[srcKey]
    -- 深渊攻击范围加成：仅对远程怪物（atkRange>1）生效，一层+1，二层+2...五层+5
    local baseRange = src.atkRange or 1
    local rangeBonus = (baseRange > 1) and floorIndex or 0
    -- 深渊移动距离加成：一层+0，二层+1，三层+2，四层+3，五层+4
    local moveBonus = floorIndex - 1
    local variant = {
        id       = src.id,
        name     = src.name,
        level    = floorLevel,
        rarity   = src.rarity,
        hp       = math.floor(CHIMERA_BASE.hp   * hpMult),
        atk      = math.floor(CHIMERA_BASE.atk  * mult),
        mAtk     = math.floor(CHIMERA_BASE.mAtk * mult),
        def      = math.floor(CHIMERA_BASE.def  * mult),
        mdef     = math.floor(CHIMERA_BASE.mdef * mult),
        critVal  = math.floor(CHIMERA_BASE.critVal * (critMult or mult) * 100 + 0.5) / 100,
        critDmg  = src.critDmg or 50,
        hit      = math.floor(CHIMERA_BASE.hit   * hitMult * 100 + 0.5) / 100,
        dodge    = math.floor(CHIMERA_BASE.dodge * dodgeMult * 100 + 0.5) / 100,
        atkSpeed = src.atkSpeed or 1,
        moveRange = (src.moveRange or 1) + moveBonus,
        atkRange  = baseRange + rangeBonus,
        color    = {src.color[1], src.color[2], src.color[3]},
        expReward = src.expReward,
        image    = src.image,
        atkAttr  = src.atkAttr,
        element  = src.element,
        ai       = src.ai,
        size     = src.size,
        rarity   = "fine",
        isAbyss  = true,
        dropGroup = "ABYSS_BASIC_DROP_POOL",
        dropGroupChance = 0.01,
        -- 深渊怪物只掉落深渊结晶（50%概率），不掉落原怪物的掉落物（不复制src.drops）
        drops = { { id = "abyss_crystal", chance = 0.15 } },
        maxHp    = math.floor(CHIMERA_BASE.hp * hpMult),
    }
    -- 电史莱姆在深渊中攻击力减半（因为攻速50，连击极快）
    if srcKey == "elec_slime" then
        variant.atk  = math.floor(variant.atk  / 2)
        variant.mAtk = math.floor(variant.mAtk / 2)
    end
    return variant
end

for i, floor in ipairs(ABYSS_FLOORS) do
    local keys = collectAbyssMonsters(floor.maxLv)
    local monsterEntries = {}
    for _, key in ipairs(keys) do
        monsterEntries[#monsterEntries + 1] = {
            weight = 1,
            def = makeAbyssVariant(key, floor.level, floor.mult, i, floor.hpMult, floor.hitMult, floor.dodgeMult, floor.critMult),
        }
    end
    M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
        name = floor.name,
        maxMonsters = floor.maxMonsters or 20,
        spawnInterval = 1,
        spawnThresholds = {1},
        spawnCounts = {floor.spawnCount},
        advanceTurn = 999,
        monsters = monsterEntries,
        statVariance = 0.2,  -- 每只怪刷新时属性 ±20% 随机浮动
    }
    M["STAGE_ABYSS_" .. i] = #M.STAGE_DEFS
end

-- 异世深渊卓越武器池（每层独立，第二层额外继承第一层）
M.ABYSS_WEAPON_POOLS = {
    [1] = { "waltz_bow", "grand_theater", "piano_gloves", "holy_touch", "scorpio_shield", "dice_of_faces", "liberation_day", "elemental_resist", "the_omnipotent", "mirror_armor", "eternal_night", "polar_day", "emperor_new_pants", "immeasurable_armor", "mountain_guard", "fortress_helm", "black_mist_hood", "dream_dagger", "iron_ship", "companion_star", "gale_stride", "prophecy_orb", "elemental_flow", "elemental_barrier", "rock_cloth", "sinking_cloak", "holy_crystal", "blood_slaughter", "shadow_gather_shoulder", "golden_island_shoulder", "beast_taming_ring", "wind_gathering_quiver", "silver_deer", "explosive_letter", "harenura", "silver_lion", "mountain_shield", "grey_shadow", "paper_umbrella", "hell_stomp" },  -- 深渊一层专属装备（40个）
    [2] = { "chuxin_belt", "phantom_silk", "magic_stone_necklace", "deep_thought", "void_grip", "abyss_visitor", "kuangxue", "thomas_sword", "apocalypse_dagger", "offering_blade", "thunder_fang", "storm_eye", "magic_pierce", "blazing_tome", "frost_tome", "thunder_tome", "angel_shield", "heavens_zenith", "shadow_dagger", "arsenal_quiver", "yun_lei" },  -- 深渊二层专属装备（21个，同时继承一层，见 ABYSS_POOL_INHERIT）
    [3] = { "focuser", "thunder_jar", "extreme_moon", "qianjunling", "sharpshooter_hat", "wolf_whistle", "shadow_form_legs", "water_snake", "shiraki_wakizashi", "little_zeus" },  -- 深渊三层专属装备（10个）
    [4] = {},               -- 深渊四层专属武器
    [5] = {},               -- 深渊五层专属武器
}
-- 层间继承规则：每层可掉落本层及所有低层的武器池
M.ABYSS_POOL_INHERIT = {
    [2] = {1},
    [3] = {1, 2},
    [4] = {1, 2, 3},
    [5] = {1, 2, 3, 4},
}

-- 史莱姆国王大反击：迎战！（固定出生点，不刷新）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "迎战！",
    maxMonsters = 1,
    spawnInterval = 999,
    spawnThresholds = {},
    spawnCounts = {1},
    advanceTurn = 999,
    noRespawn = true,
    initialMonsterCount = 1,
    fixedSpawnPos = {{6, 3}},
    monsters = {
        { weight = 100, def = M.MONSTER_DB.slime_king_enraged },
    },
}
M.STAGE_SLIME_KING_REVENGE = #M.STAGE_DEFS

-- 史莱姆国王大反击：累计伤害奖励档位（账号共享，只能领取一次）
M.SLIME_REVENGE_REWARDS = {
    { dmg = 5000,         itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 15000,        itemId = "divine_toughness_agent",  qty = 1 },
    { dmg = 30000,        itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 60000,        itemId = "divine_catalyst",         qty = 1 },
    { dmg = 120000,       itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 240000,       itemId = "divine_repair_agent",     qty = 1 },
    { dmg = 500000,       itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 1000000,      itemId = "divine_toughness_agent",  qty = 1 },
    { dmg = 2000000,      itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 3000000,      itemId = "jelly_ring_young",        qty = 1 },
    { dmg = 5000000,      itemId = "divine_catalyst",         qty = 1 },
    { dmg = 8000000,      itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 10000000,     itemId = "divine_repair_agent",     qty = 1 },
    { dmg = 15000000,     itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 20000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 25000000,     itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 30000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 35000000,     itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 40000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 45000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 50000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 60000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 70000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 80000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 90000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 100000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 120000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 140000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 160000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 180000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 200000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 250000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 300000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 350000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 400000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 450000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 500000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 550000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 600000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 650000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 700000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 750000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 800000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 850000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 900000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 950000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 1000000000,   itemId = "divine_enchant_agent",    qty = 1 },
}
-- 奖励面板状态
M.slimeRevengeRewardPanel = false     -- 面板是否打开
M.slimeRevengeRewardClaimed = {}      -- 已领取的档位索引集合 { [1]=true, [2]=true, ... }
M._slimeRevengeRewardLoaded = false   -- 云端已领取数据是否已加载
M._slimeRevengeRewardLoading = false  -- 是否正在加载
M.slimeRevengeRewardScroll = 0        -- 奖励列表滚动偏移

-- 排名面板状态
M.slimeRevengeRankPanel = false       -- 排名面板是否打开
M.slimeRevengeRankTab = 0             -- 0=总排行, 1~5=各职业排行
M.slimeRevengeRankData = nil          -- 排行榜数据 { entries={}, myRank=nil, total=0 }
M.slimeRevengeRankLoading = false     -- 是否正在加载
M.slimeRevengeRankScroll = 0          -- 排行列表滚动偏移

-- 排名 tab 定义：{ key, label }
M.SLIME_RANK_TABS = {
    { key = "slime_revenge_best", label = "总排行" },
    { key = "slime_rev_warrior",  label = "战士" },
    { key = "slime_rev_hunter",   label = "猎人" },
    { key = "slime_rev_assassin", label = "刺客" },
    { key = "slime_rev_mage",     label = "法师" },
    { key = "slime_rev_priest",   label = "牧师" },
}

-- 史莱姆大反击每日挑战
M.slimeRevengeDay = -1              -- 上次消耗挑战次数的可信天数
M.slimeRevengeUsed = 0              -- 当天已使用的挑战次数
M.SLIME_REVENGE_DAILY_LIMIT = 1     -- 每日免费挑战上限
M.slimeRevengeConfirmVisible = false -- 进入确认弹窗是否可见
M.slimeRevengeConfirmType = "daily"  -- "daily"=消耗免费次数, "ad"=看广告
M.slimeRevengeConfirmCallback = nil  -- 确认后执行的回调

--- 获取史莱姆大反击剩余免费次数
function M.getSlimeRevengeRemain()
    local realDay = math.floor(M._getTrustedTime() / 86400)
    if realDay > M.slimeRevengeDay then
        return M.SLIME_REVENGE_DAILY_LIMIT
    end
    return math.max(0, M.SLIME_REVENGE_DAILY_LIMIT - M.slimeRevengeUsed)
end

--- 消耗一次史莱姆大反击免费次数
function M.useSlimeRevengeChallenge()
    local realDay = math.floor(M._getTrustedTime() / 86400)
    if realDay > M.slimeRevengeDay then
        M.slimeRevengeDay = realDay
        M.slimeRevengeUsed = 0
    end
    if M.slimeRevengeUsed >= M.SLIME_REVENGE_DAILY_LIMIT then return false end
    M.slimeRevengeUsed = M.slimeRevengeUsed + 1
    return true
end

-- ====================================================================
-- 迪卡塔的弟弟迪哈塔大反击：迎战！（固定出生点，不刷新）
-- ====================================================================
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "迎战！",
    maxMonsters = 1,
    spawnInterval = 999,
    spawnThresholds = {},
    spawnCounts = {1},
    advanceTurn = 999,
    noRespawn = true,
    initialMonsterCount = 1,
    fixedSpawnPos = {{6, 3}},
    monsters = {
        { weight = 100, def = M.MONSTER_DB.goblin_hero_dihata },
    },
}
M.STAGE_DIHATA_REVENGE = #M.STAGE_DEFS

-- 迪哈塔大反击：累计伤害奖励档位（账号共享，只能领取一次）
M.DIHATA_REVENGE_REWARDS = {
    { dmg = 5000,         itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 15000,        itemId = "divine_toughness_agent",  qty = 1 },
    { dmg = 30000,        itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 60000,        itemId = "divine_catalyst",         qty = 1 },
    { dmg = 120000,       itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 240000,       itemId = "divine_repair_agent",     qty = 1 },
    { dmg = 500000,       itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 1000000,      itemId = "divine_toughness_agent",  qty = 1 },
    { dmg = 2000000,      itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 3000000,      itemId = "divine_catalyst",         qty = 1 },
    { dmg = 5000000,      itemId = "divine_catalyst",         qty = 1 },
    { dmg = 8000000,      itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 10000000,     itemId = "divine_repair_agent",     qty = 1 },
    { dmg = 15000000,     itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 20000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 25000000,     itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 30000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 35000000,     itemId = "gratitude_ticket",        qty = 1 },
    { dmg = 40000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 45000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 50000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 60000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 70000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 80000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 90000000,     itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 100000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 120000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 140000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 160000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 180000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 200000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 250000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 300000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 350000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 400000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 450000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 500000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 550000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 600000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 650000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 700000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 750000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 800000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 850000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 900000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 950000000,    itemId = "divine_enchant_agent",    qty = 1 },
    { dmg = 1000000000,   itemId = "divine_enchant_agent",    qty = 1 },
}

-- 迪哈塔奖励面板状态
M.dihataRevengeRewardPanel = false
M.dihataRevengeRewardClaimed = {}
M._dihataRevengeRewardLoaded = false
M._dihataRevengeRewardLoading = false
M.dihataRevengeRewardScroll = 0

-- 迪哈塔排名面板状态
M.dihataRevengeRankPanel = false
M.dihataRevengeRankTab = 0
M.dihataRevengeRankData = nil
M.dihataRevengeRankLoading = false
M.dihataRevengeRankScroll = 0

-- 迪哈塔排名 tab 定义
M.DIHATA_RANK_TABS = {
    { key = "dihata_revenge_best", label = "总排行" },
    { key = "dihata_rev_warrior",  label = "战士" },
    { key = "dihata_rev_hunter",   label = "猎人" },
    { key = "dihata_rev_assassin", label = "刺客" },
    { key = "dihata_rev_mage",     label = "法师" },
    { key = "dihata_rev_priest",   label = "牧师" },
}

-- 迪哈塔大反击每日挑战
M.dihataRevengeDay = -1
M.dihataRevengeUsed = 0
M.DIHATA_REVENGE_DAILY_LIMIT = 1
M.dihataRevengeConfirmVisible = false
M.dihataRevengeConfirmType = "daily"
M.dihataRevengeConfirmCallback = nil

--- 获取迪哈塔大反击剩余免费次数
function M.getDihataRevengeRemain()
    local realDay = math.floor(M._getTrustedTime() / 86400)
    if realDay > M.dihataRevengeDay then
        return M.DIHATA_REVENGE_DAILY_LIMIT
    end
    return math.max(0, M.DIHATA_REVENGE_DAILY_LIMIT - M.dihataRevengeUsed)
end

--- 消耗一次迪哈塔大反击免费次数
function M.useDihataRevengeChallenge()
    local realDay = math.floor(M._getTrustedTime() / 86400)
    if realDay > M.dihataRevengeDay then
        M.dihataRevengeDay = realDay
        M.dihataRevengeUsed = 0
    end
    if M.dihataRevengeUsed >= M.DIHATA_REVENGE_DAILY_LIMIT then return false end
    M.dihataRevengeUsed = M.dihataRevengeUsed + 1
    return true
end

-- 无限塔第一层：守门人（固定出生点，不刷新）
M.STAGE_DEFS[#M.STAGE_DEFS + 1] = {
    name = "第一层",
    maxMonsters = 1,
    spawnInterval = 999,
    spawnThresholds = {},
    spawnCounts = {1},
    advanceTurn = 999,
    noRespawn = true,
    initialMonsterCount = 1,
    fixedSpawnPos = {{6, 3}},  -- 守门人固定出生在 (6,3)
    monsters = {
        { weight = 100, def = M.MONSTER_DB.gatekeeper },
    },
}
M.STAGE_TOWER_1 = #M.STAGE_DEFS

-- ========== 室内关卡标记 ==========
-- 矿洞/洞窟类采集关卡 + 庄园楼层 + 灰海海边洞窟 均为室内
M.INDOOR_STAGES = {
    -- 平原矿洞
    [M.STAGE_GATHER_PLAIN_MINE_LV1] = true,
    [M.STAGE_GATHER_PLAIN_MINE_LV2] = true,
    -- 森林矿洞
    [M.STAGE_GATHER_FOREST_LV1] = true,
    [M.STAGE_GATHER_FOREST_LV2] = true,
    [M.STAGE_GATHER_FOREST_LV3] = true,
    [M.STAGE_GATHER_FOREST_LV4] = true,
    -- 海边矿洞
    [M.STAGE_GATHER_SEA_LV1] = true,
    [M.STAGE_GATHER_SEA_LV2] = true,
    [M.STAGE_GATHER_SEA_LV3] = true,
    [M.STAGE_GATHER_SEA_LV4] = true,
    -- 山崖矿洞
    [M.STAGE_GATHER_MOUNT_LV1] = true,
    [M.STAGE_GATHER_MOUNT_LV2] = true,
    [M.STAGE_GATHER_MOUNT_LV3] = true,
    [M.STAGE_GATHER_MOUNT_LV4] = true,
    -- 升月堡城下深窟
    [M.STAGE_GATHER_FORT_MINE_LV1] = true,
    [M.STAGE_GATHER_FORT_MINE_LV2] = true,
    [M.STAGE_GATHER_FORT_MINE_LV2B] = true,
    [M.STAGE_GATHER_FORT_MINE_LV3] = true,
    -- 巴洛庄园楼层（一楼~四楼）
    [M.STAGE_GHOST]     = true,   -- 庄园一楼
    [M.STAGE_FURNITURE] = true,   -- 庄园二楼
    [M.STAGE_DOLLS]     = true,   -- 庄园三楼
    [M.STAGE_VAMPIRES]  = true,   -- 庄园四楼
    -- 灰海海边洞窟
    [M.STAGE_SEA_DEMONS] = true,
    -- 潮汐祭祀圣所（洞窟）
    [M.STAGE_TIDAL_SANCTUARY] = true,
    -- 无限塔
    [M.STAGE_TOWER_1] = true,
}

--- 判断当前是否处于室内（不含清风镇建筑物，那个由 BoardOverlay.inSubScene 判断）
---@return boolean
function M.isIndoorStage()
    if M.homeMode then return true end
    if M.tavernBrawlState then return true end  -- 酒馆肉搏是室内场景
    if M.eventId == "difen_revenge" then return true end  -- 迪芬复仇：矿洞内
    return M.INDOOR_STAGES[M.currentStage] == true
end

-- ========== 采集物定义 ==========
M.GATHER_DEFS = {
    qingcicao = {
        id = "qingcicao", name = "青慈草",
        image = "image/gather_qingcicao.png", itemId = "qingcicao",
        gatherTime = 3.0, color = {80, 180, 80}, rarity = "common",
        lifeSkill = "gathering", hiddenLevel = 1,
        -- 采集固定产出基础品质

    },
    ziyan = {
        id = "ziyan", name = "紫鸢",
        image = "image/gather_purple_iris.png", itemId = "ziyan",
        gatherTime = 3.0, color = {120, 80, 180}, rarity = "common",
        lifeSkill = "gathering", hiddenLevel = 25,

    },
    shuweicao = {
        id = "shuweicao", name = "鼠尾草",
        image = "image/gather_sage.png", itemId = "shuweicao",
        gatherTime = 3.0, color = {140, 80, 200}, rarity = "common",
        lifeSkill = "gathering", hiddenLevel = 50,

    },
    -- 龙舌兰（基础稀有度：优秀）
    wei_li_cao = {
        id = "wei_li_cao", name = "龙舌兰",
        image = "image/gather_qingcicao.png", itemId = "wei_li_cao",
        gatherTime = 3.5, color = {200, 100, 80}, rarity = "uncommon",
        lifeSkill = "gathering", hiddenLevel = 75,

    },
    -- 魔绣球（基础稀有度：优秀）
    mo_li_cao = {
        id = "mo_li_cao", name = "魔绣球",
        image = "image/gather_qingcicao.png", itemId = "mo_li_cao",
        gatherTime = 3.5, color = {100, 120, 200}, rarity = "uncommon",
        lifeSkill = "gathering", hiddenLevel = 100,

    },
    -- 圣百合（基础稀有度：优秀）
    jian_gu_cao = {
        id = "jian_gu_cao", name = "圣百合",
        image = "image/gather_qingcicao.png", itemId = "jian_gu_cao",
        gatherTime = 3.5, color = {160, 140, 100}, rarity = "uncommon",
        lifeSkill = "gathering", hiddenLevel = 125,

    },
    -- 眩目雏菊（基础稀有度：优秀）
    shan_bi_cao = {
        id = "shan_bi_cao", name = "眩目雏菊",
        image = "image/gather_qingcicao.png", itemId = "shan_bi_cao",
        gatherTime = 3.5, color = {140, 180, 100}, rarity = "uncommon",
        lifeSkill = "gathering", hiddenLevel = 150,

    },
    -- 蓝星（基础稀有度：稀有）
    mo_kang_cao = {
        id = "mo_kang_cao", name = "蓝星",
        image = "image/gather_qingcicao.png", itemId = "mo_kang_cao",
        gatherTime = 4.0, color = {80, 200, 180}, rarity = "rare",
        lifeSkill = "gathering", hiddenLevel = 175,

    },
    -- 夜幽兰（基础稀有度：稀有）
    zhi_hui_cao = {
        id = "zhi_hui_cao", name = "夜幽兰",
        image = "image/gather_qingcicao.png", itemId = "zhi_hui_cao",
        gatherTime = 4.0, color = {180, 160, 220}, rarity = "rare",
        lifeSkill = "gathering", hiddenLevel = 200,

    },
    -- 紫色猫（基础稀有度：稀有）
    gan_zhi_cao = {
        id = "gan_zhi_cao", name = "紫色猫",
        image = "image/gather_qingcicao.png", itemId = "gan_zhi_cao",
        gatherTime = 4.0, color = {100, 180, 200}, rarity = "rare",
        lifeSkill = "gathering", hiddenLevel = 225,

    },
    -- 一串黄（基础稀有度：稀有）
    zhuan_zhu_cao = {
        id = "zhuan_zhu_cao", name = "一串黄",
        image = "image/gather_qingcicao.png", itemId = "zhuan_zhu_cao",
        gatherTime = 4.0, color = {100, 100, 200}, rarity = "rare",
        lifeSkill = "gathering", hiddenLevel = 250,

    },
    -- 绿葵（基础稀有度：稀有）
    min_jie_cao = {
        id = "min_jie_cao", name = "绿葵",
        image = "image/gather_qingcicao.png", itemId = "min_jie_cao",
        gatherTime = 4.0, color = {80, 200, 120}, rarity = "rare",
        lifeSkill = "gathering", hiddenLevel = 275,

    },
    -- 赤冠花（基础稀有度：精良）
    li_liang_cao = {
        id = "li_liang_cao", name = "赤冠花",
        image = "image/gather_qingcicao.png", itemId = "li_liang_cao",
        gatherTime = 4.5, color = {200, 80, 80}, rarity = "fine",
        lifeSkill = "gathering", hiddenLevel = 325,

    },
    -- 黑号（基础稀有度：精良）
    ti_zhi_cao = {
        id = "ti_zhi_cao", name = "黑号",
        image = "image/gather_qingcicao.png", itemId = "ti_zhi_cao",
        gatherTime = 4.5, color = {200, 160, 80}, rarity = "fine",
        lifeSkill = "gathering", hiddenLevel = 300,

    },
    -- 银月花（基础稀有度：精良）
    yi_nian_cao = {
        id = "yi_nian_cao", name = "银月花",
        image = "image/gather_qingcicao.png", itemId = "yi_nian_cao",
        gatherTime = 4.5, color = {160, 100, 200}, rarity = "fine",
        lifeSkill = "gathering", hiddenLevel = 350,

    },
    -- 粉色铃兰（基础稀有度：精良）
    xing_yun_cao = {
        id = "xing_yun_cao", name = "粉色铃兰",
        image = "image/gather_qingcicao.png", itemId = "xing_yun_cao",
        gatherTime = 4.5, color = {80, 200, 80}, rarity = "fine",
        lifeSkill = "gathering", hiddenLevel = 375,

    },
    si_ye_cao = {
        id = "si_ye_cao", name = "四叶草",
        image = "image/gather_clover.png", itemId = "si_ye_cao",
        gatherTime = 4.5, color = {60, 200, 100}, rarity = "fine",
        lifeSkill = "gathering", hiddenLevel = 375,
    },
    -- 以下草药仅有卓越品质，无稀有度变种
    huo_kang_cao = {
        id = "huo_kang_cao", name = "火焰魔力菇",
        image = "image/gather_qingcicao.png", itemId = "huo_kang_cao",
        gatherTime = 5.0, color = {220, 80, 40}, rarity = "superior",
        lifeSkill = "gathering", hiddenLevel = 400,
    },
    bing_kang_cao = {
        id = "bing_kang_cao", name = "寒冰魔力菇",
        image = "image/gather_qingcicao.png", itemId = "bing_kang_cao",
        gatherTime = 5.0, color = {80, 180, 220}, rarity = "superior",
        lifeSkill = "gathering", hiddenLevel = 425,
    },
    lei_kang_cao = {
        id = "lei_kang_cao", name = "雷电魔力菇",
        image = "image/gather_qingcicao.png", itemId = "lei_kang_cao",
        gatherTime = 5.0, color = {220, 220, 80}, rarity = "superior",
        lifeSkill = "gathering", hiddenLevel = 450,
    },
    zi_ran_kang_cao = {
        id = "zi_ran_kang_cao", name = "自然魔力菇",
        image = "image/gather_qingcicao.png", itemId = "zi_ran_kang_cao",
        gatherTime = 5.0, color = {60, 180, 60}, rarity = "superior",
        lifeSkill = "gathering", hiddenLevel = 475,
    },
    sheng_kang_cao = {
        id = "sheng_kang_cao", name = "神圣魔力菇",
        image = "image/gather_qingcicao.png", itemId = "sheng_kang_cao",
        gatherTime = 5.0, color = {240, 220, 160}, rarity = "superior",
        lifeSkill = "gathering", hiddenLevel = 500,
    },
    an_kang_cao = {
        id = "an_kang_cao", name = "暗黑魔力菇",
        image = "image/gather_qingcicao.png", itemId = "an_kang_cao",
        gatherTime = 5.0, color = {120, 60, 160}, rarity = "superior",
        lifeSkill = "gathering", hiddenLevel = 500,
    },
    iron_ore = {
        id          = "iron_ore",
        name        = "铁矿",
        image       = "image/gather_iron_ore.png",
        itemId      = "crude_iron_ore",
        gatherTime  = 3.0,
        color       = {160, 140, 120},
        rarity      = "common",
        lifeSkill   = "mining",
        hiddenLevel = 0,
    },
    hantong_iron = {
        id          = "hantong_iron",
        name        = "含铜铁矿",
        image       = "image/gather_hantong_iron.png",
        drops       = {
            { itemId = "tongkuang",      weight = 30 },  -- 30% 铜矿石
            { itemId = "crude_iron_ore", weight = 70 },  -- 70% 铁矿石
        },
        gatherTime  = 3.0,
        color       = {180, 120, 80},
        rarity      = "common",
        lifeSkill   = "mining",
        hiddenLevel = 30,
    },
    xiutong = {
        id          = "xiutong",
        name        = "锈铜矿",
        image       = "image/gather_xiutong.png",
        drops       = {
            { itemId = "tongkuang",      weight = 70 },  -- 70% 铜矿石
            { itemId = "crude_iron_ore", weight = 30 },  -- 30% 铁矿石
        },
        gatherTime  = 3.0,
        color       = {140, 160, 120},
        rarity      = "common",
        lifeSkill   = "mining",
        hiddenLevel = 60,
    },
    tongkuang = {
        id          = "tongkuang",
        name        = "铜矿",
        image       = "image/gather_tongkuang.png",
        itemId      = "tongkuang",
        gatherTime  = 3.0,
        color       = {190, 140, 100},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 100,
    },
    zishuijing = {
        id          = "zishuijing",
        name        = "紫晶矿",
        image       = "image/gather_zijing.png",
        drops       = {
            { itemId = "zishuijing_cujing",    weight = 90 },  -- 90% 碎裂紫晶矿
            { itemId = "zishuijing_wanzheng",  weight = 7 },   -- 7%  完整紫晶矿
            { itemId = "zishuijing_chunjing",  weight = 2 },   -- 2%  纯净紫晶矿
            { itemId = "zishuijing_shanyao",   weight = 1 },   -- 1%  闪耀紫晶矿
        },
        gatherTime  = 3.0,
        color       = {160, 100, 200},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    qingshuijing = {
        id          = "qingshuijing",
        name        = "青晶矿",
        image       = "image/gather_cyan_crystal.png",
        drops       = {
            { itemId = "qingshuijing_cujing",    weight = 90 },
            { itemId = "qingshuijing_wanzheng",  weight = 7 },
            { itemId = "qingshuijing_chunjing",   weight = 2 },
            { itemId = "qingshuijing_shanyao",    weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {80, 200, 200},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    yinkuang = {
        id          = "yinkuang",
        name        = "银矿",
        image       = "image/gather_yinkuang.png",
        itemId      = "yinkuang",
        gatherTime  = 3.0,
        color       = {200, 200, 210},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 150,
    },
    -- ===== 高级矿物采集物 =====
    hanjin_iron = {
        id          = "hanjin_iron",
        name        = "含金铁矿",
        image       = "image/gather_hanjin_iron.png",
        drops       = {
            { itemId = "jinkuangshi",   weight = 30 },  -- 30% 金矿石
            { itemId = "crude_iron_ore", weight = 70 },  -- 70% 铁矿石
        },
        gatherTime  = 3.0,
        color       = {210, 190, 100},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 180,
    },
    jinkuang = {
        id          = "jinkuang",
        name        = "金矿",
        image       = "image/gather_jinkuang.png",
        itemId      = "jinkuangshi",
        gatherTime  = 3.0,
        color       = {230, 200, 50},
        rarity      = "rare",
        lifeSkill   = "mining",
        hiddenLevel = 230,
    },
    lanyinkuang = {
        id          = "lanyinkuang",
        name        = "蓝银矿",
        image       = "image/gather_lanyinkuang.png",
        itemId      = "lanyinkuangshi",
        gatherTime  = 3.0,
        color       = {100, 140, 220},
        rarity      = "rare",
        lifeSkill   = "mining",
        hiddenLevel = 280,
    },
    huijinkuang = {
        id          = "huijinkuang",
        name        = "辉金矿",
        image       = "image/gather_huijinkuang.png",
        itemId      = "huijinkuangshi",
        gatherTime  = 3.0,
        color       = {240, 220, 100},
        rarity      = "fine",
        lifeSkill   = "mining",
        hiddenLevel = 330,
    },
    heigangkuang = {
        id          = "heigangkuang",
        name        = "黑钢矿",
        image       = "image/gather_heigangkuang.png",
        itemId      = "heigangkuangshi",
        gatherTime  = 3.0,
        color       = {60, 60, 80},
        rarity      = "fine",
        lifeSkill   = "mining",
        hiddenLevel = 380,
    },
    miyinkuang = {
        id          = "miyinkuang",
        name        = "秘银矿",
        image       = "image/gather_miyinkuang.png",
        itemId      = "miyinkuangshi",
        gatherTime  = 3.0,
        color       = {180, 200, 240},
        rarity      = "superior",
        lifeSkill   = "mining",
        hiddenLevel = 430,
    },
    zhenyinkuang = {
        id          = "zhenyinkuang",
        name        = "真银矿",
        image       = "image/gather_zhenyinkuang.png",
        itemId      = "zhenyinkuangshi",
        gatherTime  = 3.0,
        color       = {220, 230, 250},
        rarity      = "superior",
        lifeSkill   = "mining",
        hiddenLevel = 480,
    },
    zhenjinkuang = {
        id          = "zhenjinkuang",
        name        = "真金矿",
        image       = "image/gather_zhenjinkuang.png",
        itemId      = "zhenjinkuangshi",
        gatherTime  = 3.0,
        color       = {255, 215, 0},
        rarity      = "superior",
        lifeSkill   = "mining",
        hiddenLevel = 520,
    },
    -- ===== 水晶矿采集物 =====
    hongshuijing = {
        id          = "hongshuijing",
        name        = "红晶矿",
        image       = "image/gather_hongshuijing.png",
        drops       = {
            { itemId = "hongshuijing_cujing",    weight = 90 },
            { itemId = "hongshuijing_wanzheng",  weight = 7 },
            { itemId = "hongshuijing_chunjing",  weight = 2 },
            { itemId = "hongshuijing_shanyao",   weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {220, 60, 60},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    huangshuijing = {
        id          = "huangshuijing",
        name        = "黄晶矿",
        image       = "image/gather_huangshuijing.png",
        drops       = {
            { itemId = "huangshuijing_cujing",    weight = 90 },
            { itemId = "huangshuijing_wanzheng",  weight = 7 },
            { itemId = "huangshuijing_chunjing",  weight = 2 },
            { itemId = "huangshuijing_shanyao",   weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {230, 200, 50},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    lanshuijing = {
        id          = "lanshuijing",
        name        = "蓝晶矿",
        image       = "image/gather_lanshuijing.png",
        drops       = {
            { itemId = "lanshuijing_cujing",    weight = 90 },
            { itemId = "lanshuijing_wanzheng",  weight = 7 },
            { itemId = "lanshuijing_chunjing",  weight = 2 },
            { itemId = "lanshuijing_shanyao",   weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {60, 120, 230},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    lvshuijing = {
        id          = "lvshuijing",
        name        = "绿晶矿",
        image       = "image/gather_lvshuijing.png",
        drops       = {
            { itemId = "lvshuijing_cujing",    weight = 90 },
            { itemId = "lvshuijing_wanzheng",  weight = 7 },
            { itemId = "lvshuijing_chunjing",  weight = 2 },
            { itemId = "lvshuijing_shanyao",   weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {60, 200, 80},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    heishuijing = {
        id          = "heishuijing",
        name        = "黑晶矿",
        image       = "image/gather_heishuijing.png",
        drops       = {
            { itemId = "heishuijing_cujing",    weight = 90 },
            { itemId = "heishuijing_wanzheng",  weight = 7 },
            { itemId = "heishuijing_chunjing",  weight = 2 },
            { itemId = "heishuijing_shanyao",   weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {40, 40, 50},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    baishuijing = {
        id          = "baishuijing",
        name        = "白晶矿",
        image       = "image/gather_baishuijing.png",
        drops       = {
            { itemId = "baishuijing_cujing",    weight = 90 },
            { itemId = "baishuijing_wanzheng",  weight = 7 },
            { itemId = "baishuijing_chunjing",  weight = 2 },
            { itemId = "baishuijing_shanyao",   weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {240, 240, 250},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
    fenshuijing = {
        id          = "fenshuijing",
        name        = "粉晶矿",
        image       = "image/gather_fenshuijing.png",
        drops       = {
            { itemId = "fenshuijing_cujing",    weight = 90 },
            { itemId = "fenshuijing_wanzheng",  weight = 7 },
            { itemId = "fenshuijing_chunjing",  weight = 2 },
            { itemId = "fenshuijing_shanyao",   weight = 1 },
        },
        gatherTime  = 3.0,
        color       = {240, 170, 190},
        rarity      = "uncommon",
        lifeSkill   = "mining",
        hiddenLevel = 120,
    },
}
-- 关卡采集物配置：哪些关卡会刷新哪些采集物
-- 格式：count = 总生成数量，数组部分为权重池 { defId, weight }
-- 每个采集点独立按 weight 概率随机选择品种；单品种时 weight=100 即 100%
M.STAGE_GATHER_SPAWNS = {
    [M.STAGE_GATHER_PLAIN_LV1]  = { count = 5, { defId = "qingcicao",    weight = 100 } },
    [M.STAGE_GATHER_PLAIN_LV2]  = { count = 5,
        { defId = "qingcicao", weight = 50 }, { defId = "ziyan", weight = 50 },
    },
    [M.STAGE_GATHER_PLAIN_LV3]  = { count = 5,
        { defId = "qingcicao", weight = 34 }, { defId = "ziyan", weight = 33 }, { defId = "shuweicao", weight = 33 },
    },
    -- 平原矿洞
    [M.STAGE_GATHER_PLAIN_MINE_LV1] = { count = 5,
        { defId = "iron_ore", weight = 95 }, { defId = "fenshuijing", weight = 5 },
    },
    [M.STAGE_GATHER_PLAIN_MINE_LV2] = { count = 5,
        { defId = "iron_ore", weight = 60 }, { defId = "hantong_iron", weight = 30 },
        { defId = "fenshuijing", weight = 10 },
    },
    -- 森林矿洞
    [M.STAGE_GATHER_FOREST_LV1] = { count = 5,
        { defId = "hantong_iron", weight = 50 }, { defId = "iron_ore", weight = 40 },
        { defId = "lvshuijing", weight = 5 }, { defId = "huangshuijing", weight = 5 },
    },
    [M.STAGE_GATHER_FOREST_LV2] = { count = 5,
        { defId = "xiutong", weight = 50 }, { defId = "hantong_iron", weight = 40 },
        { defId = "lvshuijing", weight = 5 }, { defId = "huangshuijing", weight = 5 },
    },
    [M.STAGE_GATHER_FOREST_LV3] = { count = 5,
        { defId = "tongkuang", weight = 20 }, { defId = "xiutong", weight = 70 },
        { defId = "lvshuijing", weight = 5 }, { defId = "huangshuijing", weight = 5 },
    },
    [M.STAGE_GATHER_FOREST_LV4] = { count = 5,
        { defId = "tongkuang", weight = 70 }, { defId = "xiutong", weight = 10 }, { defId = "yinkuang", weight = 10 },
        { defId = "lvshuijing", weight = 5 }, { defId = "huangshuijing", weight = 5 },
    },
    -- 海边矿洞
    [M.STAGE_GATHER_SEA_LV1] = { count = 5,
        { defId = "yinkuang", weight = 20 }, { defId = "tongkuang", weight = 65 },
        { defId = "lanshuijing", weight = 5 }, { defId = "zishuijing", weight = 5 }, { defId = "qingshuijing", weight = 5 },
    },
    [M.STAGE_GATHER_SEA_LV2] = { count = 5,
        { defId = "yinkuang", weight = 45 }, { defId = "tongkuang", weight = 40 },
        { defId = "lanshuijing", weight = 5 }, { defId = "zishuijing", weight = 5 }, { defId = "qingshuijing", weight = 5 },
    },
    [M.STAGE_GATHER_SEA_LV3] = { count = 5,
        { defId = "yinkuang", weight = 65 }, { defId = "tongkuang", weight = 17 }, { defId = "lanyinkuang", weight = 3 },
        { defId = "lanshuijing", weight = 5 }, { defId = "zishuijing", weight = 5 }, { defId = "qingshuijing", weight = 5 },
    },
    [M.STAGE_GATHER_SEA_LV4] = { count = 5,
        { defId = "yinkuang", weight = 79 }, { defId = "lanyinkuang", weight = 5 }, { defId = "zhenyinkuang", weight = 1 },
        { defId = "lanshuijing", weight = 5 }, { defId = "zishuijing", weight = 5 }, { defId = "qingshuijing", weight = 5 },
    },
    -- 山崖矿洞
    [M.STAGE_GATHER_MOUNT_LV1] = { count = 5,
        { defId = "hanjin_iron", weight = 15 }, { defId = "tongkuang", weight = 70 },
        { defId = "heishuijing", weight = 5 }, { defId = "hongshuijing", weight = 5 }, { defId = "baishuijing", weight = 5 },
    },
    [M.STAGE_GATHER_MOUNT_LV2] = { count = 5,
        { defId = "jinkuang", weight = 15 }, { defId = "hanjin_iron", weight = 70 },
        { defId = "heishuijing", weight = 5 }, { defId = "hongshuijing", weight = 5 }, { defId = "baishuijing", weight = 5 },
    },
    [M.STAGE_GATHER_MOUNT_LV3] = { count = 5,
        { defId = "jinkuang", weight = 70 }, { defId = "hanjin_iron", weight = 10 }, { defId = "huijinkuang", weight = 3 },
        { defId = "heishuijing", weight = 5 }, { defId = "hongshuijing", weight = 5 }, { defId = "baishuijing", weight = 5 },
    },
    [M.STAGE_GATHER_MOUNT_LV4] = { count = 5,
        { defId = "jinkuang", weight = 59 }, { defId = "heigangkuang", weight = 20 }, { defId = "huijinkuang", weight = 5 }, { defId = "zhenjinkuang", weight = 1 },
        { defId = "heishuijing", weight = 5 }, { defId = "hongshuijing", weight = 5 }, { defId = "baishuijing", weight = 5 },
    },
    -- 垂雾森林采集
    [M.STAGE_GATHER_MIST_FOREST_LV1] = { count = 5,
        { defId = "qingcicao", weight = 50 }, { defId = "wei_li_cao", weight = 25 }, { defId = "shuweicao", weight = 25 },
    },
    [M.STAGE_GATHER_MIST_FOREST_LV2] = { count = 5,
        { defId = "qingcicao", weight = 30 }, { defId = "wei_li_cao", weight = 30 }, { defId = "mo_li_cao", weight = 30 },
        { defId = "zi_ran_kang_cao", weight = 10 },
    },
    [M.STAGE_GATHER_MIST_FOREST_LV3] = { count = 5,
        { defId = "mo_li_cao", weight = 25 }, { defId = "jian_gu_cao", weight = 25 },
        { defId = "shan_bi_cao", weight = 25 }, { defId = "zi_ran_kang_cao", weight = 25 },
    },
    -- 巴洛庄园采集
    [M.STAGE_GATHER_MANOR_LV1] = { count = 5,
        { defId = "qingcicao", weight = 34 }, { defId = "ziyan", weight = 33 }, { defId = "mo_kang_cao", weight = 33 },
    },
    [M.STAGE_GATHER_MANOR_LV2] = { count = 5,
        { defId = "qingcicao", weight = 25 }, { defId = "mo_kang_cao", weight = 25 },
        { defId = "zhi_hui_cao", weight = 25 }, { defId = "gan_zhi_cao", weight = 25 },
    },
    [M.STAGE_GATHER_MANOR_LV3] = { count = 5,
        { defId = "qingcicao", weight = 15 }, { defId = "ziyan", weight = 15 },
        { defId = "zhi_hui_cao", weight = 30 }, { defId = "gan_zhi_cao", weight = 30 }, { defId = "huo_kang_cao", weight = 10 },
    },
    [M.STAGE_GATHER_MANOR_LV4] = { count = 5,
        { defId = "zhi_hui_cao", weight = 34 }, { defId = "gan_zhi_cao", weight = 33 }, { defId = "huo_kang_cao", weight = 33 },
    },
    -- 灰海采集
    [M.STAGE_GATHER_GREY_SEA_LV1] = { count = 5,
        { defId = "ziyan", weight = 49 }, { defId = "zhuan_zhu_cao", weight = 17 }, { defId = "min_jie_cao", weight = 17 }, { defId = "si_ye_cao", weight = 17 },
    },
    [M.STAGE_GATHER_GREY_SEA_LV2] = { count = 5,
        { defId = "si_ye_cao", weight = 34 }, { defId = "zhuan_zhu_cao", weight = 33 }, { defId = "min_jie_cao", weight = 33 },
        { defId = "bing_kang_cao", weight = 10 },
    },
    [M.STAGE_GATHER_GREY_SEA_LV3] = { count = 5,
        { defId = "zhuan_zhu_cao", weight = 22 }, { defId = "min_jie_cao", weight = 22 }, { defId = "si_ye_cao", weight = 22 }, { defId = "bing_kang_cao", weight = 33 },
    },
    -- 灰山采集
    [M.STAGE_GATHER_GREY_MT_LV1] = { count = 5,
        { defId = "qingcicao", weight = 45 }, { defId = "ti_zhi_cao", weight = 45 },
        { defId = "lei_kang_cao", weight = 5 }, { defId = "sheng_kang_cao", weight = 5 },
    },
    [M.STAGE_GATHER_GREY_MT_LV2] = { count = 5,
        { defId = "qingcicao", weight = 30 }, { defId = "ti_zhi_cao", weight = 30 }, { defId = "li_liang_cao", weight = 30 },
        { defId = "lei_kang_cao", weight = 5 }, { defId = "sheng_kang_cao", weight = 5 },
    },
    [M.STAGE_GATHER_GREY_MT_LV3] = { count = 5,
        { defId = "qingcicao", weight = 20 }, { defId = "ti_zhi_cao", weight = 20 }, { defId = "li_liang_cao", weight = 20 },
        { defId = "lei_kang_cao", weight = 20 }, { defId = "sheng_kang_cao", weight = 20 },
    },
    -- 升月堡城下花园采集
    [M.STAGE_GATHER_FORT_LV1] = { count = 5,
        { defId = "qingcicao", weight = 30 }, { defId = "ziyan", weight = 30 },
        { defId = "xing_yun_cao", weight = 30 }, { defId = "an_kang_cao", weight = 10 },
    },
    [M.STAGE_GATHER_FORT_LV2] = { count = 5,
        { defId = "qingcicao", weight = 20 }, { defId = "ziyan", weight = 20 },
        { defId = "yi_nian_cao", weight = 20 }, { defId = "xing_yun_cao", weight = 20 }, { defId = "an_kang_cao", weight = 20 },
    },
    [M.STAGE_GATHER_FORT_LV3] = { count = 5,
        { defId = "yi_nian_cao", weight = 34 }, { defId = "xing_yun_cao", weight = 33 }, { defId = "an_kang_cao", weight = 33 },
    },
    -- 升月堡矿洞（总权重900，晶石9选一各等权）
    [M.STAGE_GATHER_FORT_MINE_LV1] = { count = 5,
        -- 矿石 40%/12%/8%，晶石9选一共40%（各≈4.44%），总权重900
        { defId = "lanyinkuang", weight = 360 }, { defId = "huijinkuang", weight = 108 }, { defId = "heigangkuang", weight = 72 },
        { defId = "hongshuijing", weight = 40 }, { defId = "lanshuijing", weight = 40 }, { defId = "huangshuijing", weight = 40 },
        { defId = "lvshuijing", weight = 40 }, { defId = "heishuijing", weight = 40 }, { defId = "baishuijing", weight = 40 },
        { defId = "zishuijing", weight = 40 }, { defId = "fenshuijing", weight = 40 }, { defId = "qingshuijing", weight = 40 },
    },
    [M.STAGE_GATHER_FORT_MINE_LV2] = { count = 5,
        -- 矿石 30%/18%/12%，晶石9选一共40%（各≈4.44%），总权重900
        { defId = "lanyinkuang", weight = 270 }, { defId = "huijinkuang", weight = 162 }, { defId = "heigangkuang", weight = 108 },
        { defId = "hongshuijing", weight = 40 }, { defId = "lanshuijing", weight = 40 }, { defId = "huangshuijing", weight = 40 },
        { defId = "lvshuijing", weight = 40 }, { defId = "heishuijing", weight = 40 }, { defId = "baishuijing", weight = 40 },
        { defId = "zishuijing", weight = 40 }, { defId = "fenshuijing", weight = 40 }, { defId = "qingshuijing", weight = 40 },
    },
    [M.STAGE_GATHER_FORT_MINE_LV2B] = { count = 5,
        -- 矿石 12%/12%/6%，晶石9选一共70%（各≈7.78%），总权重900（同开阔区）
        { defId = "miyinkuang", weight = 108 }, { defId = "zhenyinkuang", weight = 108 }, { defId = "zhenjinkuang", weight = 54 },
        { defId = "hongshuijing", weight = 70 }, { defId = "lanshuijing", weight = 70 }, { defId = "huangshuijing", weight = 70 },
        { defId = "lvshuijing", weight = 70 }, { defId = "heishuijing", weight = 70 }, { defId = "baishuijing", weight = 70 },
        { defId = "zishuijing", weight = 70 }, { defId = "fenshuijing", weight = 70 }, { defId = "qingshuijing", weight = 70 },
    },
    [M.STAGE_GATHER_FORT_MINE_LV3] = { count = 5,
        -- 矿石 30%/18%/7%，晶石9选一共45%（各5%），总权重1000
        { defId = "miyinkuang", weight = 300 }, { defId = "zhenyinkuang", weight = 180 }, { defId = "zhenjinkuang", weight = 70 },
        { defId = "hongshuijing", weight = 50 }, { defId = "lanshuijing", weight = 50 }, { defId = "huangshuijing", weight = 50 },
        { defId = "lvshuijing", weight = 50 }, { defId = "heishuijing", weight = 50 }, { defId = "baishuijing", weight = 50 },
        { defId = "zishuijing", weight = 50 }, { defId = "fenshuijing", weight = 50 }, { defId = "qingshuijing", weight = 50 },
    },
}

-- ====================================================================
-- 区域图片系统：同一采集物在不同区域显示不同图片
-- ====================================================================

-- 关卡索引 → 区域标签映射
M.STAGE_GATHER_AREA = {
    -- 慈爱平原 → "plain"
    [M.STAGE_GATHER_PLAIN_LV1]       = "plain",
    [M.STAGE_GATHER_PLAIN_LV2]       = "plain",
    [M.STAGE_GATHER_PLAIN_LV3]       = "plain",
    -- 垂雾森林 → "forest"
    [M.STAGE_GATHER_MIST_FOREST_LV1] = "forest",
    [M.STAGE_GATHER_MIST_FOREST_LV2] = "forest",
    [M.STAGE_GATHER_MIST_FOREST_LV3] = "forest",
    -- 灰山 → "forest"
    [M.STAGE_GATHER_GREY_MT_LV1]     = "forest",
    [M.STAGE_GATHER_GREY_MT_LV2]     = "forest",
    [M.STAGE_GATHER_GREY_MT_LV3]     = "forest",
    -- 巴洛庄园 → "garden"
    [M.STAGE_GATHER_MANOR_LV1]       = "garden",
    [M.STAGE_GATHER_MANOR_LV2]       = "garden",
    [M.STAGE_GATHER_MANOR_LV3]       = "garden",
    [M.STAGE_GATHER_MANOR_LV4]       = "garden",
    -- 升月堡 → "garden"
    [M.STAGE_GATHER_FORT_LV1]        = "garden",
    [M.STAGE_GATHER_FORT_LV2]        = "garden",
    [M.STAGE_GATHER_FORT_LV3]        = "garden",
    -- 灰海 → "sea"（暂用默认图片，后续可扩展）
    [M.STAGE_GATHER_GREY_SEA_LV1]    = "sea",
    [M.STAGE_GATHER_GREY_SEA_LV2]    = "sea",
    [M.STAGE_GATHER_GREY_SEA_LV3]    = "sea",
    -- 矿洞区域（采矿关卡也标记，方便未来扩展矿石图片）
    [M.STAGE_GATHER_FOREST_LV1]      = "forest",
    [M.STAGE_GATHER_FOREST_LV2]      = "forest",
    [M.STAGE_GATHER_FOREST_LV3]      = "forest",
    [M.STAGE_GATHER_FOREST_LV4]      = "forest",
    [M.STAGE_GATHER_SEA_LV1]         = "sea",
    [M.STAGE_GATHER_SEA_LV2]         = "sea",
    [M.STAGE_GATHER_SEA_LV3]         = "sea",
    [M.STAGE_GATHER_SEA_LV4]         = "sea",
    [M.STAGE_GATHER_FORT_MINE_LV1]   = "garden",
    [M.STAGE_GATHER_FORT_MINE_LV2]   = "garden",
    [M.STAGE_GATHER_FORT_MINE_LV2B]  = "garden",
    [M.STAGE_GATHER_FORT_MINE_LV3]   = "garden",
}

--- 区域专属图片覆盖表
--- 格式: GATHER_AREA_IMAGES[defId][area] = "image/xxx.png"
--- 未配置的 defId 或 area 将使用 GATHER_DEFS 中的默认图片
M.GATHER_AREA_IMAGES = {
    qingcicao = {
        plain  = "image/gather_qingcicao_plain.png",
        forest = "image/gather_qingcicao_forest.png",
        garden = "image/gather_qingcicao_garden.png",
        -- sea: 未配置，使用默认图片
    },
    ziyan = {
        plain  = "image/gather_ziyan_plain.png",
        forest = "image/gather_ziyan_forest.png",
        garden = "image/gather_ziyan_garden.png",
        sea    = "image/gather_ziyan_sea.png",
    },
    shuweicao = {
        forest = "image/gather_shuweicao_forest.png",
    },
    wei_li_cao = {
        forest = "image/gather_wei_li_cao_forest.png",
    },
    mo_li_cao = {
        forest = "image/gather_mo_li_cao_forest.png",
    },
    jian_gu_cao = {
        forest = "image/gather_jian_gu_cao_forest.png",
    },
    shan_bi_cao = {
        forest = "image/gather_shan_bi_cao_forest.png",
    },
    zi_ran_kang_cao = {
        forest = "image/gather_zi_ran_kang_cao_forest.png",
    },
    mo_kang_cao = {
        garden = "image/gather_mo_kang_cao_garden.png",
    },
    zhi_hui_cao = {
        garden = "image/gather_zhi_hui_cao_garden.png",
    },
    gan_zhi_cao = {
        garden = "image/gather_gan_zhi_cao_garden.png",
    },
    huo_kang_cao = {
        garden = "image/gather_huo_kang_cao_garden.png",
    },
    zhuan_zhu_cao = {
        sea = "image/gather_zhuan_zhu_cao_sea.png",
    },
    min_jie_cao = {
        sea = "image/gather_min_jie_cao_sea.png",
    },
    bing_kang_cao = {
        sea = "image/gather_bing_kang_cao_sea.png",
    },
    ti_zhi_cao = { forest = "image/gather_ti_zhi_cao_forest.png" },
    li_liang_cao = { forest = "image/gather_li_liang_cao_forest.png" },
    lei_kang_cao = { forest = "image/gather_lei_kang_cao_forest.png" },
    sheng_kang_cao = { forest = "image/gather_sheng_kang_cao_forest.png" },
    yi_nian_cao = { garden = "image/gather_yi_nian_cao_garden.png" },
    xing_yun_cao = { garden = "image/gather_xing_yun_cao_garden.png" },
    an_kang_cao = { garden = "image/gather_an_kang_cao_garden.png" },
    -- 后续在此处为更多植物添加区域图片
}

--- 获取采集物在指定关卡的区域图片
---@param defId string 采集物定义ID
---@param stageIndex number 当前关卡索引
---@return string|nil image 区域图片路径，nil 则使用默认
---@return string|nil area 区域标签
function M.getGatherImage(defId, stageIndex)
    local area = M.STAGE_GATHER_AREA[stageIndex]
    if not area then return nil, nil end
    local areaImages = M.GATHER_AREA_IMAGES[defId]
    if not areaImages then return nil, area end
    return areaImages[area], area
end

-- ====================================================================
-- 运行时状态（集中管理，便于联机同步）
-- ====================================================================
M.gameState = M.STATE_MENU
-- ===== 多角色槽位系统 =====
M.charSlotMeta = nil              -- 云端 meta 数据 { version=2, activeSlot, slots={} }
M.charSlotIndex = nil             -- 当前活跃槽位 (1-6)
M.resumeCheckPending = false      -- 从后台恢复时的会话检查进行中，阻断 saveToCloud
M.charSelectCardRects = {}        -- 6张角色卡的点击区域
M.charSelectDeleteRects = {}      -- 删除图标点击区域
M.charSelectBackRect = nil        -- 返回标题按钮
M.charCreateSlotIdx = nil         -- 正在创建的槽位索引
M.charCreateName = ""             -- 创建角色的名字
M.charCreateClass = nil           -- 选择的职业
M.charCreateClassRects = {}       -- 职业卡片点击区域
M.charCreateConfirmRect = nil     -- 确认按钮
M.charCreateBackRect = nil        -- 取消按钮
M.charCreateRerollRect = nil      -- 换名按钮
M.charDeleteSlotIdx = nil         -- 正在删除的槽位
M.charDeleteStep = 0              -- 0=无, 1=第一次确认, 2=第二次确认(3秒冷却)
M.charDeleteTimer = 0             -- 第二次确认冷却倒计时
M.charDeleteConfirmRect = nil
M.charDeleteCancelRect = nil
M.charNewConfirmSlot = nil        -- 待创建的槽位（新角色确认弹窗）
M.charNewConfirmRect = nil
M.charNewCancelRect = nil
M.cachedLegacySaveData = nil      -- 旧存档迁移暂存
M.MAX_CHAR_SLOTS = 6
M.charName = ""                   -- 当前角色名
M.awakeningCompleted = false      -- 苏醒事件（事件#1）是否已完整完成
M.eventCompleted = {}             -- 所有事件完成标记 { ["awakening"]=true, ["initial_supply"]=true, ... }
M.currentStage = 1
M.currentBattleBg = "image/bg_grass.png"   -- 当前战斗背景路径（按关卡/区域切换）
M.turnNumber = 0

-- 副本状态
M.isEvent = false
M.eventId = nil
M.eventInputLocked = false

M.isDungeon = false
M.dungeonId = nil
M.dungeonPhase = 0
M.dungeonCheckpoint = 0
M.dungeonSpawnCount = 0
M.dungeonWaveIndex = 0
M.dungeonPhaseComplete = false
M.dungeonPhaseTurn = 0
M.dungeonScrollAnim = nil   -- { offsetY, timer, duration } 棋盘整体滚动动画

-- 深渊区每日挑战次数
M.abyssChallengeDay = -1    -- 上次消耗挑战次数的游戏天数
M.abyssChallengeUsed = 0    -- 当天已使用的挑战次数
M.ABYSS_DAILY_LIMIT = 1    -- 每日挑战上限

-- 深渊区进入确认弹窗
M.abyssConfirmVisible = false    -- 弹窗是否可见
M.abyssConfirmType = "daily"     -- "daily"=消耗免费次数, "key"=消耗神之匙
M.abyssConfirmYesRect = {}       -- 确定按钮区域
M.abyssConfirmNoRect = {}        -- 取消按钮区域
M.abyssConfirmStageData = nil    -- 暂存的场景切换数据（闭包）

-- 异世深渊每日挑战（区别于深渊区副本的 abyssChallenge 系统）
M.abyssWorldDay = -1             -- 上次消耗异世深渊挑战次数的游戏天数
M.abyssWorldUsed = 0             -- 当天已使用的挑战次数
M.ABYSS_WORLD_DAILY_LIMIT = 1   -- 每日免费挑战上限
M.abyssWorldActive = false       -- 当前是否有一次有效的异世深渊会话（进入后到死亡前）
M.abyssWorldLives = 0            -- 异世深渊剩余生命次数（初始3，死亡扣1，归0时通道关闭）
M.ABYSS_WORLD_MAX_LIVES = 3     -- 异世深渊初始生命数
M.isAbyssWorld = false           -- 当前关卡是否属于异世深渊

-- 异世深渊进入确认弹窗
M.abyssWorldConfirmVisible = false   -- 弹窗是否可见
M.abyssWorldConfirmType = "daily"    -- "daily"=消耗免费次数, "ad"=看广告
M.abyssWorldConfirmYesRect = {}      -- 确定按钮区域
M.abyssWorldConfirmNoRect = {}       -- 取消按钮区域
M.abyssWorldConfirmStageData = nil   -- 暂存的场景切换数据（闭包）
M.abyssFakeAd = false                -- 兑换码 vipisvip：深渊用虚拟广告代替真实广告
M.adFree = false                     -- 兑换码 supergamer：全局免广告权益（所有广告直接跳过）
M.abyssFakeAdTimer = nil             -- 虚拟广告倒计时（30秒），nil=未激活
M.abyssFakeAdCallback = nil          -- 虚拟广告完成后的回调
M.abyssWorldReturnBtnRect = nil      -- 死亡界面"返回清水镇"按钮区域

-- ===== 5天签到奖励系统 =====
M.signInStartDay = 0                  -- 系统激活时的真实天号 (os.time()/86400)
M.signInRewards = {}                  -- {[1]={login=bool,time15=bool,time60=bool}, ...}
M.signInDayPlayTime = {}              -- {[1]=秒数, [2]=秒数, ...} 每天累计游玩时间
M.signInPanelVisible = false          -- 面板是否打开
M.signInBtnRect = nil                 -- 按钮区域
-- ===== 第6天+ 日常签到系统 =====
M.dailySignInDayKey = 0               -- 当前日常签到的真实天号（每日重置判断）
M.dailySignInRewards = {}             -- { login=bool, time15=bool, time60=bool } 当天奖励
M.dailySignInPlayTime = 0             -- 当天累计游玩秒数
M.debugForceDay6 = false              -- 管理员：强制进入第6天模式

-- 求婚成功弹窗
M.proposalSuccessPopup = false        -- 弹窗是否可见
M.proposalSuccessOkRect = {}          -- 确定按钮区域

-- 爱称修改输入框
M.petNameInput = nil                  -- { active, text, placeholder, confirmed, npcKey }
M._petNameInputConfirmRect = nil      -- 确定按钮区域
M._petNameInputCancelRect = nil       -- 取消按钮区域
M._petNameInputRect = nil             -- 输入框区域
-- 自定义爱称存储（npcKey → 自定义称呼）
M.customPetNames = {}

-- 兑换码系统
M.redeemedCodes = {}                  -- 已兑换的码集合 { ["Thanku4play"] = true }
M.redeemCodeInput = nil               -- { active, text, imeComposing, imeComposition }
M._redeemCodeConfirmRect = nil        -- 确定按钮区域
M._redeemCodeCancelRect = nil         -- 取消按钮区域
M._redeemCodeInputRect = nil          -- 输入框区域
M._redeemCodeBtnRect = nil            -- 设置面板中兑换码按钮区域

--- 计算爱称加权长度：CJK字符占2，其余占1
---@param s string
---@return integer
function M._petNameWeightedLen(s)
    local w = 0
    for _, code in utf8.codes(s) do
        if code >= 0x2E80 then  -- CJK及以上区段（中日韩、全角符号等）
            w = w + 2
        else
            w = w + 1
        end
    end
    return w
end

-- 家中伴侣交谈
M.homePartnerTalkActive = false       -- 是否正在与伴侣交谈

-- 竞技场：阶段间等待玩家踩绿色出口
M.arenaWaitForExit = false        -- 是否正在等待玩家踩出口格子
M.arenaExitTiles = nil            -- { {x=6,y=1}, {x=7,y=1} } 绿色出口格子
M.arenaChests = {}                -- { {x, y, gold, opened} ... } 竞技场BOSS掉落宝箱
M.arenaChestInteract = nil        -- { chestIdx, progress, duration, _displayProgress } 宝箱交互状态
M.arenaChestPending = nil         -- 移动完成后待开启的宝箱索引（chest table ref）
M.arenaExitPending = false        -- 移动完成后待触发的出口
M.arenaPendingTarget = nil        -- 自由移动中待前往的目标 {x, y}
M.arenaDungeonCleared = false     -- 副本通关标志（最终BOSS击败后显示通关文本）
M.gold = 0
M.score = 0
M.animTimer = 0

M.turnPhase = ""
M.enemyAttackFired = false

---@type table|nil
M.player = nil
M.monsters = {}
M.companions = {}       -- 友军伙伴列表（猎犬等）
M._playerPosTrail = {}  -- 玩家位置轨迹（猎犬跟随用），最多保留最近5个位置
M.holyTrees = {}        -- 圣树召唤物列表 {x, y, turnsLeft, hitsLeft, healRange, healPct, casterMAtk, isHolyTree=true, hp, maxHp}
M.iceWalls = {}         -- 冰墙列表 {x, y, turnsLeft, hitsLeft, hp, maxHp, isIceWall=true}
M.burningGrounds = {}   -- 燃烧地面列表 {x, y, turnsLeft, burnPct, casterMAtk}
M.pendingBurningGrounds = {} -- 延迟出现的燃烧地面 {delay, items={{x,y,turnsLeft,burnPct,casterMAtk},...}}
M.blizzardZones = {}    -- 暴风雪区域列表 {cx, cy, radius, turnsLeft, mul, casterMAtk, skillId, slowDur, slowVal}
M.thunderClouds = {}    -- 雷云列表 {target, turnsLeft, mul, casterMAtk, aoeRadius, skillName}
M.lightningWarnings = {} -- 夸迪引雷标记格子列表 {x, y}
M.fireCorpses = {}      -- 火史莱姆精锐尸体 {x, y, turns, image, color}
M.gatherables = {}      -- 采集物列表 {x, y, defId, name, image, itemId, gatherTime, lifeSkill, hiddenLevel, isGatherable=true}
M.gatherStageStates = {}     -- 各采集关卡保存的采集物状态 { [stageIndex] = { alive={...}, depleted=bool, resetCounter=N } }
M.gatherResetCounter = 0     -- [废弃] 旧全局计数器，仅存档兼容用；实际刷新由各关卡 resetCounter 独立控制
M.lastRestockDay = 0             -- 上次商店补货的游戏天数（每天凌晨4点补货一次）
M.rebirthCooldownDay = nil       -- 铸甲匠项链【重生】被动CD：上次触发的游戏天数（nil=从未触发）
M.playerDebuffs = {}    -- 玩家 debuff 列表 {type="dodge"/"move", val=N, turns=N, source="..."}

--- 复活时需要清除的玩家字段（新增 buff/debuff 只需在此追加）
--- playerFields: 设为 nil 的 player 属性
--- gsFields:     设为指定值的 GS 属性 { field, resetValue }
--- special:      需要特殊处理的回调函数列表
M.RESPAWN_CLEAR = {
    playerFields = {
        -- debuff
        "sandBlinded", "sandBlindedTurns",
        "taunted", "tauntAtkPct", "tauntDefPct",
        "stunned", "poisoned", "armorBroken", "feared",
        -- 不可知物凝视
        "_unknownGaze", "_gazePer", "_gazeFoc",
        -- 祝福 buff
        "conquerTurns", "conquerAtkPct",
        "shelterTurns", "shelterDefPct",
        "miracleTurns", "miracleVal",
        -- 冲锋怒吼 buff
        "chargeRoarTurns", "chargeRoarDmgPct", "chargeRoarReducePct",
    },
    gsFields = {
        { field = "focusBuffTurns",  resetValue = 0 },
        { field = "stormBuffTurns",  resetValue = 0 },
        { field = "stormStartCount", resetValue = nil },
        { field = "stormEndCount",   resetValue = nil },
        { field = "_eleFlowElem",     resetValue = nil },
        { field = "_eleFlowLastElem", resetValue = nil },
        { field = "_eleFlowTurns",    resetValue = nil },
        { field = "bloodShield",      resetValue = 0 },
    },
    special = {
        -- 备用武器：清除待执行的免费投掷和暴击BUFF
        function(player, gs)
            player._spareWeaponTarget = nil
            player._spareWeaponThrows = nil
            player._spareWeaponPending = nil
            player._spareWeaponCritDmg = nil
            player._spareWeaponCritTurns = nil
        end,
        -- 清除怪物身上的标记
        function(player, gs)
            for _, m in ipairs(gs.monsters) do
                if m.marked then m.marked = nil end
            end
        end,
    },
}

--- 获取可信时间戳（admin_time 封顶，防前调作弊）
--- 懒加载 SignInSystem 避免循环依赖
function M._getTrustedTime()
    local SignInSystem = require("SignInSystem")
    SignInSystem._loadAdminTime()
    local localTime = os.time()
    if SignInSystem._adminTime and localTime > SignInSystem._adminTime then
        localTime = SignInSystem._adminTime
    end
    return localTime
end

--- 获取深渊区当日剩余挑战次数
function M.getAbyssChallengeRemain()
    local realDay = math.floor(M._getTrustedTime() / 86400)  -- 可信天数（UTC）
    if realDay > M.abyssChallengeDay then
        return M.ABYSS_DAILY_LIMIT  -- 新的一天（往后），未使用
    end
    return math.max(0, M.ABYSS_DAILY_LIMIT - M.abyssChallengeUsed)
end

--- 消耗一次深渊区每日挑战次数，成功返回 true
function M.useAbyssChallenge()
    local realDay = math.floor(M._getTrustedTime() / 86400)  -- 可信天数（UTC）
    if realDay > M.abyssChallengeDay then
        M.abyssChallengeDay = realDay
        M.abyssChallengeUsed = 0
    end
    if M.abyssChallengeUsed >= M.ABYSS_DAILY_LIMIT then
        return false
    end
    M.abyssChallengeUsed = M.abyssChallengeUsed + 1
    return true
end

--- 返回当前深渊层数（1~5），非深渊返回 nil
function M.getAbyssFloorIndex(stageIndex)
    stageIndex = stageIndex or M.currentStage
    for i = 1, 5 do
        if M["STAGE_ABYSS_" .. i] and stageIndex == M["STAGE_ABYSS_" .. i] then
            return i
        end
    end
    return nil
end

--- 判断某个 stageIndex 是否属于异世深渊（STAGE_ABYSS_1 ~ STAGE_ABYSS_5）
function M.isAbyssWorldStage(stageIndex)
    if not stageIndex then return false end
    for i = 1, 5 do
        if M["STAGE_ABYSS_" .. i] and stageIndex == M["STAGE_ABYSS_" .. i] then
            return true
        end
    end
    return false
end

--- 判断指定格子是否处于深渊毒雾区域
--- @param x number 格子X坐标
--- @param y number 格子Y坐标
--- @return boolean 是否在毒雾中
function M.isPoisonFogTile(x, y)
    local floor = M.getAbyssFloorIndex()
    if not floor then return false end
    local bs = M.BOARD_SIZE
    if floor == 2 then
        -- 二层：四角曼哈顿距离≤2
        local corners = {{1,1},{bs,1},{1,bs},{bs,bs}}
        for _, c in ipairs(corners) do
            if math.abs(x - c[1]) + math.abs(y - c[2]) <= 2 then
                return true
            end
        end
    elseif floor == 3 then
        -- 三层：外两圈（edgeDist < 2，即 edgeDist 为 0 或 1）
        local edgeDist = math.min(x - 1, bs - x, y - 1, bs - y)
        if edgeDist < 2 then
            return true
        end
    end
    return false
end

--- 获取异世深渊当日剩余免费次数
function M.getAbyssWorldRemain()
    local realDay = math.floor(M._getTrustedTime() / 86400)  -- 可信天数（UTC）
    if realDay > M.abyssWorldDay then
        return M.ABYSS_WORLD_DAILY_LIMIT  -- 新的一天（往后），未使用
    end
    return math.max(0, M.ABYSS_WORLD_DAILY_LIMIT - M.abyssWorldUsed)
end

--- 消耗一次异世深渊每日免费次数，成功返回 true
function M.useAbyssWorldChallenge()
    local realDay = math.floor(M._getTrustedTime() / 86400)  -- 可信天数（UTC）
    if realDay > M.abyssWorldDay then
        M.abyssWorldDay = realDay
        M.abyssWorldUsed = 0
    end
    if M.abyssWorldUsed >= M.ABYSS_WORLD_DAILY_LIMIT then
        return false
    end
    M.abyssWorldUsed = M.abyssWorldUsed + 1
    return true
end

--- 检测背包中是否有神之匙并消耗一个，成功返回 true
function M.consumeDivineKey()
    for i = 1, M.bagSlots do
        local item = M.inventory[i]
        if item and item.templateId == "divine_key" then
            if item.stackable and item.quantity and item.quantity > 1 then
                item.quantity = item.quantity - 1
            else
                M.inventory[i] = nil
            end
            return true
        end
    end
    return false
end

--- 检测背包中是否持有神之匙
function M.hasDivineKey()
    for i = 1, M.bagSlots do
        local item = M.inventory[i]
        if item and item.templateId == "divine_key" then
            return true
        end
    end
    return false
end

--- 复活时清除所有 BUFF 和 DEBUFF（调用此函数即可）
function M.clearAllBuffsDebuffs()
    local cfg = M.RESPAWN_CLEAR
    local player = M.player
    -- 清除 playerDebuffs 列表
    M.playerDebuffs = {}
    -- 清除 player 字段
    for _, f in ipairs(cfg.playerFields) do
        player[f] = nil
    end
    -- 重置 GS 字段
    for _, entry in ipairs(cfg.gsFields) do
        M[entry.field] = entry.resetValue
    end
    -- 执行特殊处理
    for _, fn in ipairs(cfg.special) do
        fn(player, M)
    end
end

--- 获取玩家 debuff 总减值（返回负数）。type: "dodge" 或 "move"
function M.getPlayerDebuffTotal(dtype)
    local total = 0
    for _, db in ipairs(M.playerDebuffs) do
        if db.type == dtype then total = total - db.val end
    end
    return total
end

M.selectedUnit = nil
M.movableCells = {}
M.movableParents = {}   -- BFS parent map，用于路径重建
M.attackableCells = {}
M.damageTexts = {}
M.pendingMpRestores = {} -- 延迟回蓝队列（与伤害数字同步）

--- 立即结算所有待回蓝条目，然后清空队列
function M.flushPendingMpRestores()
    for _, mr in ipairs(M.pendingMpRestores) do
        local t = mr.target
        if t and t.mp and t.maxMp then
            t.mp = math.min(t.mp + mr.amount, t.maxMp)
        end
    end
    M.pendingMpRestores = {}
end
M.attackEffects = {}
M.pendingBounces = {}   -- 深渊弹射延迟队列（分帧执行）
M.strikeEffects = {}    -- 强击技能专属特效
M.powerShotEffects = {} -- 劲射技能专属特效
M.stunShotEffects = {}  -- 晕眩射击专属特效
M.snipeEffects = {}     -- 狙击技能专属特效
M.whirlwindEffects = {} -- 旋风斩AOE特效
M.iceRingEffects = {}   -- 冰环术AOE特效
M.fireballEffects = {}  -- 火球术AOE特效
M.meteorEffects = {}    -- 陨石术AOE特效
M.lightningChainEffects = {} -- 闪电链特效
M.thunderStrikeEffects = {}  -- 落雷术特效
M.blizzardIceEffects = {}    -- 暴风雪冰锥坠落特效
M.burnEffects = {}           -- 火焰护盾烧伤特效
M.thunderCloudStrikeEffects = {} -- 雷云攻击闪电特效
M.healEffects = {}      -- 治疗特效（羁绊链接等）
M.divineGraceEffects = {} -- 神佑特效（神圣粒子升腾）
M.holyTreeWaveEffects = {} -- 圣树冲击波特效（扩散圆环）
M.blessEffects = {}       -- 祝福术特效（神圣锤击）
M.sandBlindEffects = {} -- 泼沙致盲特效
M.tauntEffects = {}     -- 嘲讽技能特效
M.cleaveEffects = {}    -- 顺劈溅射特效
M.meleeSplashEffects = {} -- 深渊溅射特效
M.rangedExplosionEffects = {} -- 爆炸信爆炸特效
M.holyAoeEffects = {} -- 哈雷努拉祝福/超度AOE区域特效
M.strikeAoeEffects = {} -- 银色狮子强击系AOE冲击波特效
M.magicShieldEffects = {} -- 魔法盾激活/关闭特效
M.iceWallCreateEffects = {} -- 冰墙术创建特效
M.blinkEffects = {} -- 闪烁传送特效
M.deathEffects = {} -- 怪物死亡特效（缩小+淡出+粒子）
M.phantomDissolveEffects = {} -- 幻影消散特效
M.phantomAttackEffects = {}  -- 幻影攻击特效（深渊词缀）
M.radianceWaveEffects = {}   -- 辉光扩散特效（深渊词缀：治疗伤害周围范围）
M.apocalypseAoeEffects = {}  -- 默示录紫色爆炸光环特效
M.swordQiEffects = {}        -- 远程反击剑气飞行特效
M.pendingEndPlayerTurn = false  -- 延迟结束玩家回合标记
M._pendingEndTurnTimer = nil    -- 延迟计时器（超时保护）
M.screenShake = nil     -- 屏幕震动 {timer, duration, intensity, delay}
M.superiorDropFlash = nil -- 卓越装备掉落橙光闪烁 {timer, duration, phase}

--- 触发卓越装备掉落橙光闪烁
function M.triggerSuperiorDropFlash()
    M.superiorDropFlash = { timer = 0, duration = 1.2 }
end

--- 设置屏幕震动（弱震动不会覆盖尚未播完的强震动）
function M.setScreenShake(duration, intensity, delay)
    if not M.enableScreenShake then return end
    delay = delay or 0
    if M.screenShake then
        local s = M.screenShake
        local elapsed = s.timer - (s.delay or 0)
        -- 当前震动尚未播完且强度 >= 新震动 → 跳过
        if elapsed < s.duration and s.intensity >= intensity then
            return
        end
    end
    M.screenShake = { timer = 0, duration = duration, intensity = intensity, delay = delay }
end

M.stormBuffTurns = 0    -- 风暴状态剩余回合数

-- 勿忘我 BUFF（酒馆舞池每日观赏获得）
-- { active = true, expireTime = weatherTime值 }
-- 效果：HP回复+1, MP回复+1, 力量+1, 专注+1, 智慧+1
M.forgetMeNotBuff = nil
M.forgetMeNotLevel = 0  -- 勿忘我BUFF等级（安吉莉娅任务奖励，0~4），增强勿忘我效果
M.forgetMeNotPermanent = false  -- 勿忘我永久效果（安吉莉娅最终任务奖励）
M.hugBuff = nil  -- 精神抖擞BUFF（家中拥抱伴侣获得）{ active = true, expireTime = weatherTime值 }，全属性+1，持续24小时
M.foodBuff = nil  -- 食物BUFF { foodId, name, expireTime, hpRegen, mpRegen, str, foc, wis, con, agi, per, wil, luk, physCrit, magicCrit, fireDmgPct, iceDmgPct, thunderDmgPct, holyDmgPct }
M.potionBuffs = {} -- 药水BUFF { [stat] = { amount, expireTime, isPercent } }，同类型覆盖
M.lastDanceDayWatched = -1  -- 上次观赏舞蹈的游戏天数（weatherTime / 1440 取整）
M.dancerShowPhase = nil     -- 舞池演出阶段: nil=无, "performing"=演出中, "done"=演出完毕(显示坐姿)

M.stealthActive = false -- 隐匿状态
M.stealthTurns = 0       -- 隐匿剩余回合数
M.stealthSmokeEffect = nil -- 隐匿烟雾弹特效 { x, y, timer, duration }
M.focusBuffTurns = 0    -- 静神状态剩余回合数
M._playerMovedThisTurn = false  -- 本回合玩家是否发生了移动（静神被动判定用）
M.fireShieldTurns = 0   -- 火焰护盾剩余回合数
M.fireShieldReducePct = 0  -- 火焰护盾伤害减免百分比
-- 吟唱系统（法师专用）
M.chantStages = 0       -- 当前持有的吟唱段数
M.chantStagesMax = 0    -- 本回合获得的总段数（用于UI方块显示）
M.chanting = nil        -- 吟唱状态 { skillId, target (敌人引用或nil), tx, ty (地面坐标或nil), stagesNeeded, stagesAccum, castType ("single"/"aoe"/"ground"/"self") }
M.mageActionTaken = false  -- 法师本回合是否已执行过行动（用于禁止撤销移动）
M.fireShieldReflectPct = 0 -- 火焰护盾反伤百分比（基于 matk）
M.magicShieldActive = false -- 魔法盾开关状态
M.bloodShield = 0           -- 饮血护甲值（过量吸血存储）
M.markedTarget = nil    -- 标记目标（猎人标记的敌人）
M.inventory = {}
M.itemImages = {}           -- 物品图片句柄缓存 { [imageKey] = nvgImageHandle }
M.mapScrollY = 0            -- 地图面板滚动偏移
M.mapDragging = false       -- 地图面板拖拽中
M.mapDragLastY = 0          -- 拖拽上一次Y坐标
M.mapBtnRects = {}              -- 地图地点按钮区域 { {x,y,w,h,locId,locName,locIndex}, ... }
M.selectedMapLocation = nil     -- 当前选中的地图地点 id
M.selectedMapStage = nil        -- 当前选中的关卡索引（在地点 stages 数组中的下标）
M.mapStageScrollOffset = 0      -- 关卡列表滚动偏移（条目数）
M.mapStageListClip = nil        -- 关卡列表裁剪区域 {x,y,w,h}
M.mapStageScrollbarRect = nil   -- 滚动条轨道区域 {x,y,w,h}
M.mapStageScrollbarDragging = false  -- 是否正在拖拽滚动条
M.mapStageScrollMaxOffset = 0   -- 最大滚动偏移
M.mapStageTouchStartY = nil     -- 触摸滑动起始Y
M.mapStageTouchStartOffset = 0  -- 触摸滑动起始偏移
M.mapStageBtnRects = {}         -- 关卡按钮区域 { {x,y,w,h,stageIdx}, ... }
M.mapGoButtonRect = nil         -- 地图"前往"按钮区域
M.mapCancelButtonRect = nil     -- 地图"取消"按钮区域
M.mapTipText = nil              -- 地图临时提示文本
M.mapTipTimer = 0               -- 提示剩余时间

-- 地图分区系统（采集区/常规区/深渊区）
M.MAP_ZONE_DEFS = {
    { id = "gather",  name = "采集区", color = {80, 180, 80}  },
    { id = "battle",  name = "常规区", color = {200, 160, 80} },
    { id = "dungeon", name = "深渊区", color = {200, 60, 60}  },
}
M.MAP_ZONE_ORDER = { "gather", "battle", "dungeon" }
M.mapStageZone = "battle"          -- 当前活跃分区
M.mapZoneTabRects = {}             -- 分区标签点击区域
M.mapZoneTouchStartX = nil         -- 水平滑动起始 X

-- ====================================================================
-- 稀有度定义
-- ====================================================================
M.RARITY = {
    common    = { name = "普通", color = {200, 200, 200}, border = {140, 140, 140} },
    uncommon  = { name = "优秀", color = {90, 220, 90},   border = {60, 180, 60} },
    rare      = { name = "稀有", color = {80, 160, 255},  border = {50, 120, 220} },
    fine      = { name = "精良", color = {180, 80, 255},  border = {140, 50, 220} },
    superior  = { name = "卓越", color = {255, 185, 15},  border = {220, 155, 10} },
    epic      = { name = "史诗", color = {230, 80, 20},   border = {190, 60, 15} },
    legendary = { name = "传说", color = {230, 20, 40},   border = {190, 15, 30} },
    divine    = { name = "神明", color = {220, 100, 220}, border = {50, 210, 240}, gradient = { {220, 100, 220}, {50, 210, 240} } },
}

-- 稀有度升级映射
M.RARITY_UP = {
    common    = "uncommon",
    uncommon  = "rare",
    rare      = "fine",
    fine      = "superior",
    superior  = "epic",
    epic      = "legendary",
    legendary = "divine",
    divine    = "divine",
}

-- ====================================================================
-- 怪物词缀系统
-- ====================================================================
M.MONSTER_AFFIXES = {
    -- 1. 强壮的：生命+20%
    { name = "强壮的", apply = function(m)
        m.hp    = math.floor(m.hp * 1.2)
        m.maxHp = math.floor(m.maxHp * 1.2)
    end },
    -- 2. 锐利的：暴击值+20%
    { name = "锐利的", apply = function(m)
        m.critVal = math.floor((m.critVal or 0) * 1.2)
    end },
    -- 3. 坚硬的：防御+20%
    { name = "坚硬的", apply = function(m)
        m.def = math.floor(m.def * 1.2)
    end },
    -- 4. 迅捷的：移动范围+2
    { name = "迅捷的", apply = function(m)
        m.moveRange = (m.moveRange or 1) + 2
    end },
    -- 5. 凶残的：暴击伤害+40%
    { name = "凶残的", apply = function(m)
        m.critDmg = (m.critDmg or 50) + 40
    end },
    -- 6. 灵巧的：闪避+20%
    { name = "灵巧的", apply = function(m)
        m.dodge = math.floor((m.dodge or 0) * 1.2)
    end },
    -- 7. 精准的：命中+20%
    { name = "精准的", apply = function(m)
        m.hit = math.floor((m.hit or 0) * 1.2)
    end },
    -- 8. 急速的：攻击速度+50
    { name = "急速的", apply = function(m)
        m.atkSpeed = (m.atkSpeed or 0) + 50
    end },
    -- 9. 残暴的：攻击+20%
    { name = "残暴的", apply = function(m)
        m.atk = math.floor(m.atk * 1.2)
    end },
    -- 10. 富有的：攻击+10%，防御+10%，必掉UC装备
    { name = "富有的", apply = function(m)
        m.atk = math.floor(m.atk * 1.1)
        m.def = math.floor(m.def * 1.1)
        m.guaranteeDrop = true
    end },
    -- 11. 自愈的：每回合恢复5%最大生命
    { name = "自愈的", apply = function(m)
        m.selfHeal = true
    end },
    -- 12. 火焰的：攻击变为火元素魔法攻击，火焰抗性+50%，攻击范围3
    { name = "火焰的", apply = function(m)
        m.element = "fire"
        m.affixRangedStyle = "fire"
        m.mAtk = m.mAtk or m.atk
        m.resFire = (m.resFire or 0) + 50
        m.atkRange = 3
    end },
    -- 13. 寒冰的：攻击变为冰元素魔法攻击，冰冻抗性+50%，攻击范围3
    { name = "寒冰的", apply = function(m)
        m.element = "ice"
        m.affixRangedStyle = "ice"
        m.mAtk = m.mAtk or m.atk
        m.resIce = (m.resIce or 0) + 50
        m.atkRange = 3
    end },
    -- 14. 雷电的：攻击变为雷元素魔法攻击，雷电抗性+50%，攻击范围3
    { name = "雷电的", apply = function(m)
        m.element = "thunder"
        m.affixRangedStyle = "thunder"
        m.mAtk = m.mAtk or m.atk
        m.resElec = (m.resElec or 0) + 50
        m.atkRange = 3
    end },
    -- 15. 神圣的：攻击变为光元素魔法攻击，神圣抗性+50%，攻击范围3
    { name = "神圣的", apply = function(m)
        m.element = "light"
        m.affixRangedStyle = "light"
        m.mAtk = m.mAtk or m.atk
        m.resLight = (m.resLight or 0) + 50
        m.atkRange = 3
    end },
}



-- 销毁确认弹窗
M.destroyConfirmVisible = false   -- 弹窗是否可见
M.destroyConfirmItem = nil        -- 待销毁物品引用
M.destroyConfirmSlotIdx = nil     -- 待销毁物品的背包索引
M.destroyConfirmBatch = false     -- 批量销毁模式
M.destroyBtnRect = {}             -- 销毁按钮屏幕区域 {x,y,w,h}
M.destroyConfirmYesRect = {}      -- 弹窗确定按钮区域
M.destroyConfirmNoRect = {}       -- 弹窗取消按钮区域

-- ====================================================================
-- 对话系统
-- ====================================================================
M.dialogueFlags = {}            -- { [dialogueId] = true } 已触发的一次性对话

-- ====================================================================
-- 好感度系统
-- ====================================================================
M.npcAffinity = {}              -- { [npcKey] = number } NPC好感度值

--- speaker 显示名 → npcKey 反向映射（Renderer 用 speaker 名字查询，存储统一用 npcKey）
local SPEAKER_TO_NPCKEY = {
    ["芙蕾雅"]   = "guild_master",
    ["妮可"]     = "guild_receptionist",
    ["朱莉"]     = "jewelry_shop_owner",
    ["莉娜"]     = "potion_shop_owner",
    ["爱丽丝"]   = "tavern_keeper",
    ["安吉莉娅"] = "tavern_dancer",
    ["斯特朗"]   = "blacksmith_owner",
    ["迪芬"]     = "armor_shop_owner",
    ["艾莉雅"]   = "forest_elf",
}

--- 将 speaker 名字或 npcKey 统一转换为 npcKey
---@param key string speaker 名字或 npcKey
---@return string npcKey
local function resolveNpcKey(key)
    return SPEAKER_TO_NPCKEY[key] or key
end

--- 获取NPC好感度值（默认10）
---@param speaker string speaker 名字或 npcKey 均可
---@return number
function M.getAffinity(speaker)
    if not speaker then return 10 end
    local npcKey = resolveNpcKey(speaker)
    if M.npcAffinity[npcKey] == nil then
        M.npcAffinity[npcKey] = 10
    end
    return M.npcAffinity[npcKey]
end

--- 好感度提升动画状态
M.affinityAnim = nil  -- { startTime = number } 触发时记录时间，Renderer 读取并播放动画
--- 好感度下降动画状态
M.affinityDownAnim = nil  -- { startTime = number }

--- 冒险者等级对好感度的上限约束
--- 未达到对应冒险者等级时，好感度值不能超过此上限
--- key = 所需冒险者等级（2=E, 3=D, 4=C, 5=B, 6=A），value = 好感度值上限
M.AFFINITY_RANK_CAPS = {
    [2] = 99,   -- 未达E级：好感度上限99（无法进入"在意"）
    [3] = 199,  -- 未达D级：好感度上限199（无法进入"重视"）
    [4] = 299,  -- 未达C级：好感度上限299（无法进入"亲密"）
    [5] = 399,  -- 未达B级：好感度上限399（无法进入"爱慕"）
    [6] = 499,  -- 未达A级：好感度上限499（无法进入"挚爱"）
}

--- 根据当前冒险者等级计算好感度上限
---@return number 好感度值上限
function M.getAffinityCapByRank()
    local rank = M.adventurerRank or 1
    -- 从高到低找到第一个未满足的等级要求，其上限即为当前上限
    -- 如果所有等级都满足（rank >= 6），返回 500（正常最大值）
    local cap = 500
    for reqRank = 2, 6 do
        if rank < reqRank then
            cap = M.AFFINITY_RANK_CAPS[reqRank]
            break
        end
    end
    return cap
end

--- 修改NPC好感度
---@param speaker string speaker 名字或 npcKey 均可
---@param delta number
function M.changeAffinity(speaker, delta)
    if not speaker then return end
    local npcKey = resolveNpcKey(speaker)
    local cur = M.getAffinity(npcKey)
    -- 冒险者等级限制好感度上限
    local rankCap = M.getAffinityCapByRank()
    local newVal = math.max(-30, math.min(rankCap, cur + delta))
    M.npcAffinity[npcKey] = newVal
    -- 好感度变化时触发动画（伴侣使用粉色爱心风格）
    local isPartner = (M.partnerNpcKey and npcKey == M.partnerNpcKey)
    if delta > 0 then
        M.affinityAnim = { startTime = time.elapsedTime, isPartner = isPartner }
    elseif delta < 0 then
        M.affinityDownAnim = { startTime = time.elapsedTime }
    end
end

--- 根据好感度值获取评价标签
---@param speaker string
---@return string label, number r, number g, number b
function M.getAffinityLabel(speaker)
    local val = M.getAffinity(speaker)
    if val <= -1 then
        return "反感", 230, 90, 90
    elseif val <= 30 then
        return "陌生", 160, 160, 160
    elseif val <= 100 then
        return "友善", 90, 220, 90
    elseif val <= 200 then
        return "在意", 80, 160, 255
    elseif val <= 300 then
        return "重视", 180, 80, 255
    elseif val <= 400 then
        return "亲密", 230, 80, 20
    elseif val <= 499 then
        return "爱慕", 255, 100, 150
    else
        return "挚爱", 180, 20, 40
    end
end

-- 每日交谈好感度记录 { [npcKey] = gameDay } 记录上次交谈加好感的游戏天数
M.npcTalkAffinityDate = {}

-- 每日亲吻好感度记录 { [npcKey] = gameDay } 记录上次亲吻加好感的游戏天数
M.npcKissAffinityDate = {}
-- 每日告白好感度记录 { [npcKey] = gameDay }
M.npcConfessAffinityDate = {}
-- 每日求婚好感度记录 { [npcKey] = gameDay }
M.npcProposalAffinityDate = {}
M.homeKissDate = -1          -- 家中亲吻好感度上次生效的游戏日
M.homeHugDate = -1           -- 家中拥抱好感度(+2)上次生效的游戏日
M.homeHugDate2 = -1          -- 家中拥抱好感度(+3)上次生效的游戏日

--- 每日交谈好感度+2（每个NPC每游戏日仅一次）
---@param npcKey string TalkQA 中的 npcKey
function M.tryDailyTalkAffinity(npcKey)
    if not npcKey then return end
    -- 反感状态下交谈不加好感度，必须通过赠送礼物回升
    if M.getAffinity(npcKey) < 0 then return end
    local gameDay = math.floor(((M.weatherTime or 1) - 1) / 1440)
    if M.npcTalkAffinityDate[npcKey] == gameDay then return end
    M.npcTalkAffinityDate[npcKey] = gameDay
    M.changeAffinity(npcKey, 2)
    print("[好感度] " .. npcKey .. " 每日交谈 +2（游戏第" .. gameDay .. "天）")
end

-- ====================================================================
-- 赠送礼物系统
-- ====================================================================
M.giftMode = false              -- 是否处于赠送模式
M.giftNpcKey = nil              -- 当前赠送对象的 npcKey
M.giftNpcName = nil             -- 当前赠送对象显示名称
M.giftSlotItem = nil            -- 赠送槽中放入的物品引用
M.giftSlotSource = nil          -- 来源标识: "bag"
M.giftSlotSourceId = nil        -- 背包索引(number)
M.giftDropRect = nil            -- 拖入放置区域
M.giftConfirmRect = nil         -- 确认按钮区域
M.giftCancelRect = nil          -- 取消按钮区域
M.giftCloseRect = nil           -- 关闭按钮区域
M.giftRejectMsg = nil           -- 赠送拒绝提示（如不可赠送物品）
M.giftResultText = nil          -- 赠送结果文本
M.giftResultLiked = nil         -- 是否喜欢（用于文本颜色）
M.giftBuildingKey = nil         -- 当前交谈的建筑key（赠送完回到交谈）

--- NPC 礼物偏好表：爱丽丝去掉"黑号"
--- 花类植物的 ID 列表（16种，不含黑号）
local HERB_FLOWER_IDS = {
    ziyan = true, shuweicao = true,
    wei_li_cao = true, mo_li_cao = true, jian_gu_cao = true,
    shan_bi_cao = true, mo_kang_cao = true, zhi_hui_cao = true,
    gan_zhi_cao = true, zhuan_zhu_cao = true, min_jie_cao = true,
    -- ti_zhi_cao (黑号) 已排除
    li_liang_cao = true, yi_nian_cao = true,
    xing_yun_cao = true, si_ye_cao = true,
}

--- 金属矿石 ID 列表
local METAL_ORE_IDS = {
    tongkuang = true, crude_iron_ore = true,
    yinkuang = true, jinkuangshi = true,
    lanyinkuangshi = true, huijinkuangshi = true,
    heigangkuangshi = true, miyinkuangshi = true,
    zhenyinkuangshi = true, zhenjinkuangshi = true,
}

--- 金属锭 ID 列表
local METAL_INGOT_IDS = {
    copper_ingot = true, iron_ingot = true,
    silver_ingot = true, gold_ingot = true,
    blue_silver_ingot = true, radiant_gold_ingot = true,
    black_steel_ingot = true, mithril_ingot = true,
    true_silver_ingot = true, true_gold_ingot = true,
}

--- 晶矿 ID 判定（名称含"晶矿"的材料）
local function isCrystalOre(tpl)
    if tpl.category ~= "材料" then return false end
    return tpl.name and tpl.name:find("晶矿") ~= nil
end

--- 判断物品是否为指定 NPC 喜欢的礼物
---@param npcKey string NPC 标识
---@param item table 背包中的物品实例
---@return boolean
function M.isGiftLiked(npcKey, item)
    if not item then return false end
    local tpl = M.itemTemplates[item.templateId]
    if not tpl then return false end

    if npcKey == "guild_master" then
        -- 芙蕾雅：独特装备
        return tpl.isUnique == true

    elseif npcKey == "guild_receptionist" then
        -- 妮可：花类植物（16种，不含黑号）
        return HERB_FLOWER_IDS[tpl.id] == true

    elseif npcKey == "jewelry_shop_owner" then
        -- 朱莉：晶矿、宝石、项链、戒指
        if tpl.category == "宝石" then return true end
        if tpl.category == "项链" then return true end
        if tpl.category == "戒指" then return true end
        if isCrystalOre(tpl) then return true end
        return false

    elseif npcKey == "potion_shop_owner" then
        -- 莉娜：法杖、法器、生命和魔法药水以外的药剂
        if tpl.category == "法杖" then return true end
        if tpl.category == "副手" and tpl.offhandTag == "法器" then return true end
        if tpl.category == "消耗品" then
            -- 排除 HP 和 MP 药水
            local id = tpl.id or ""
            if id:find("^potion_hp_") or id:find("^potion_mp_") then
                return false
            end
            return true
        end
        return false

    elseif npcKey == "tavern_keeper" then
        -- 爱丽丝：食物
        return tpl.category == "食物"

    elseif npcKey == "blacksmith_owner" then
        -- 斯特朗：剑、匕首、钉锤、弓、金属矿、金属锭
        if tpl.weaponTag == "单手剑" then return true end
        if tpl.weaponTag == "匕首" then return true end
        if tpl.weaponTag == "锤" then return true end
        if tpl.category == "弓" then return true end
        if METAL_ORE_IDS[tpl.id] then return true end
        if METAL_INGOT_IDS[tpl.id] then return true end
        return false

    elseif npcKey == "armor_shop_owner" then
        -- 迪芬：防具、盾牌、金属矿、金属锭
        local armorCats = {
            ["头部"] = true, ["肩部"] = true, ["胸部"] = true,
            ["手部"] = true, ["腰部"] = true, ["腰带"] = true,
            ["腿部"] = true, ["脚部"] = true, ["背部"] = true,
        }
        if armorCats[tpl.category] then return true end
        if tpl.category == "盾牌" then return true end
        if METAL_ORE_IDS[tpl.id] then return true end
        if METAL_INGOT_IDS[tpl.id] then return true end
        return false

    elseif npcKey == "forest_elf" then
        -- 艾莉雅：阅读物
        return tpl.category == "阅读物"
    end

    return false
end

--- 赠送好感度增益表：GIFT_AFFINITY_TABLE[好感等级][稀有度] = 好感度增量
--- 好感等级 1~7 对应：陌生、友善、在意、重视、亲密、爱慕、挚爱
--- 稀有度列：common(普通)、uncommon(优秀)、rare(稀有)、fine(精良)、superior(卓越)
local GIFT_AFFINITY_TABLE = {
    [1] = { common = 2, uncommon = 3, rare = 4, fine = 4, superior = 4 }, -- 陌生
    [2] = { common = 2, uncommon = 3, rare = 4, fine = 4, superior = 4 }, -- 友善
    [3] = { common = 1, uncommon = 2, rare = 3, fine = 4, superior = 4 }, -- 在意
    [4] = { common = 0, uncommon = 1, rare = 2, fine = 3, superior = 4 }, -- 重视
    [5] = { common = 0, uncommon = 0, rare = 1, fine = 2, superior = 3 }, -- 亲密
    [6] = { common = 0, uncommon = 0, rare = 0, fine = 1, superior = 2 }, -- 爱慕
    [7] = { common = 0, uncommon = 0, rare = 0, fine = 0, superior = 1 }, -- 挚爱
}

--- 根据NPC好感等级和物品稀有度，获取赠送好感度增量
---@param npcKey string
---@param rarity string|nil
---@return number 好感度增量
function M.getGiftAffinityGain(npcKey, rarity)
    local level = M.getNPCFavorLevel(npcKey)
    if level < 1 then level = 1 end
    if level > 7 then level = 7 end
    local row = GIFT_AFFINITY_TABLE[level]
    if not row then return 0 end
    -- epic/legendary/divine 等更高稀有度按 superior 列计算
    local r = rarity or "common"
    if r == "epic" or r == "legendary" or r == "divine" then
        r = "superior"
    end
    return row[r] or 0
end

--- 执行赠送：扣除物品、判定喜好、加好感度
function M.executeGift()
    local item = M.giftSlotItem
    if not item then return end

    -- 安吉莉娅特殊处理：不接受任何礼物，物品退回背包
    if M.giftNpcKey == "tavern_dancer" then
        M.giftResultText = "谢谢你，但是我不能要。想要我开心的话，只要你能多来看我的舞蹈就好。"
        M.giftResultLiked = false
        M.returnGiftSlotItem()
        print("[赠送] tavern_dancer 拒绝礼物，物品已退回")
        return
    end

    local liked = M.isGiftLiked(M.giftNpcKey, item)

    -- 物品已在拖入赠送槽时从背包扣除，此处无需再扣

    -- 个性化送礼回应文本（按 npcKey 区分）
    -- {玩家}/{爱称}：未结婚用玩家名，已结婚用爱称
    local npcKey = M.giftNpcKey
    local nameTag
    if M.partnerNpcKey and M.partnerNpcKey == npcKey then
        nameTag = M.getNPCPetName(npcKey)
    else
        nameTag = M.charName or ""
    end
    local giftTexts = {
        guild_master       = { dislike = "哦，谢谢你。",
                               like    = "这个好特别，我很喜欢。谢谢你，" .. nameTag .. "。" },
        guild_receptionist = { dislike = "谢谢你，" .. nameTag .. "。",
                               like    = "哇！好漂亮的花！心情变好了！谢谢你！" .. nameTag .. "！" },
        jewelry_shop_owner = { dislike = "嗯？谢谢。",
                               like    = "哇……好漂亮。谢谢你，" .. nameTag .. "，我很喜欢。" },
        potion_shop_owner  = { dislike = "……",
                               like    = "这个是我喜欢的，" .. nameTag .. "，谢谢你。" },
        tavern_keeper      = { dislike = nameTag .. "，这个东西很奇怪。不能送我一些好吃的吗？",
                               like    = "哇，看起来好美味！谢谢" .. nameTag .. "！" },
        forest_elf         = { dislike = nameTag .. "，谢谢你，但下次不用给我这个。",
                               like    = "啊！我喜欢故事，谢谢你，" .. nameTag .. "。" },
        blacksmith_owner   = { dislike = "这是啥？",
                               like    = "真正的尖货，谢了，哥们儿。" },
        armor_shop_owner   = { dislike = "嗯，还行。谢谢。",
                               like    = "真是好玩意儿，谢谢你。" },
    }
    local texts = giftTexts[npcKey]

    if liked then
        local tpl = M.itemTemplates[item.templateId]
        local rarity = tpl and tpl.rarity or "common"
        local gain = M.getGiftAffinityGain(M.giftNpcKey, rarity)
        M.giftResultText = (texts and texts.like) or "哇，这是我喜欢的，谢谢你！"
        M.giftResultLiked = true
        M.giftAffinityGain = gain
        if gain > 0 then
            M.changeAffinity(M.giftNpcKey, gain)
            print("[赠送] " .. M.giftNpcKey .. " 喜欢礼物，好感度+" .. gain .. "（稀有度:" .. rarity .. "）")
        else
            print("[赠送] " .. M.giftNpcKey .. " 喜欢礼物，但稀有度不足（" .. rarity .. "），好感度不变")
        end
    else
        M.giftResultText = (texts and texts.dislike) or "哦，谢谢你给我这个。"
        M.giftResultLiked = false
        M.giftAffinityGain = 0
        print("[赠送] " .. M.giftNpcKey .. " 不太喜欢礼物")
    end

    -- 清空赠送槽
    M.giftSlotItem = nil
    M.giftSlotSource = nil
    M.giftSlotSourceId = nil
end

--- 归还赠送槽物品到背包（拆出的1个还回去）
function M.returnGiftSlotItem()
    if not M.giftSlotItem then return end
    local srcIdx = M.giftSlotSourceId
    local returned = false
    -- 优先合并回原位置
    if srcIdx and M.inventory[srcIdx] then
        local bagItem = M.inventory[srcIdx]
        if bagItem.templateId == M.giftSlotItem.templateId then
            bagItem.quantity = (bagItem.quantity or 1) + 1
            returned = true
        end
    end
    -- 原位置不匹配，遍历背包找同类合并
    if not returned then
        for _, bagItem in ipairs(M.inventory) do
            if bagItem.templateId == M.giftSlotItem.templateId then
                bagItem.quantity = (bagItem.quantity or 1) + 1
                returned = true
                break
            end
        end
    end
    -- 背包无同类，作为新条目插入
    if not returned then
        M.inventory[#M.inventory + 1] = M.giftSlotItem
    end
    M.giftSlotItem = nil
    M.giftSlotSource = nil
    M.giftSlotSourceId = nil
end

--- 取消赠送（归还物品到背包）
function M.cancelGift()
    M.returnGiftSlotItem()
    M.giftResultText = nil
    M.giftResultLiked = nil
    M.giftMode = false
    M.giftFromHome = nil
end

--- 关闭赠送结果，回到交谈
function M.closeGiftResult()
    M.giftResultText = nil
    M.giftResultLiked = nil
    M.giftAffinityGain = nil
    M.giftMode = false
    M.giftFromHome = nil
end

-- ====================================================================
-- 任务物品提交系统
-- ====================================================================
M.questSubmitMode = false           -- 是否处于任务提交模式
M.questSubmitQuestId = nil          -- 当前提交的任务 ID
M.questSubmitDef = nil              -- 当前任务定义（含 requireItems）
M.questSubmitNpcName = nil          -- NPC 显示名称
M.questSubmitBuildingKey = nil      -- 当前建筑 key（完成后回到交谈）
M.questSubmitSlotItem = nil         -- 提交槽中放入的物品引用
M.questSubmitSlotSource = nil       -- 来源标识: "bag"
M.questSubmitSlotSourceId = nil     -- 背包索引(number)
M.questSubmitDropRect = nil         -- 拖入放置区域
M.questSubmitConfirmRect = nil      -- 确认按钮区域
M.questSubmitCancelRect = nil       -- 取消按钮区域
M.questSubmitCloseRect = nil        -- 关闭按钮区域
M.questSubmitRejectMsg = nil        -- 拒绝提示（如"不是这个物品"）

--- 归还任务提交槽中的物品到背包
function M.returnQuestSubmitItem()
    if not M.questSubmitSlotItem then return end
    local srcIdx = M.questSubmitSlotSourceId
    local returnQty = M.questSubmitSlotItem.quantity or 1
    local remaining = returnQty
    -- 优先合并回原位置（受堆叠上限限制）
    if srcIdx and M.inventory[srcIdx] then
        local bagItem = M.inventory[srcIdx]
        if bagItem.templateId == M.questSubmitSlotItem.templateId then
            local canAdd = M.STACK_MAX - (bagItem.quantity or 1)
            if canAdd > 0 then
                local add = math.min(remaining, canAdd)
                bagItem.quantity = (bagItem.quantity or 1) + add
                remaining = remaining - add
            end
        end
    end
    -- 还有剩余，走正常添加流程（自动处理堆叠上限和新格子）
    if remaining > 0 then
        M.addToInventory(M.questSubmitSlotItem.templateId, remaining)
    end
    M.questSubmitSlotItem = nil
    M.questSubmitSlotSource = nil
    M.questSubmitSlotSourceId = nil
end

--- 取消任务提交（归还物品 + 重置状态）
function M.cancelQuestSubmit()
    M.returnQuestSubmitItem()
    M.questSubmitRejectMsg = nil
    M.questSubmitMode = false
    M.questSubmitQuestId = nil
    M.questSubmitDef = nil
    M.questSubmitNpcName = nil
    M.questSubmitBuildingKey = nil
    M.questSubmitDropRect = nil
    M.questSubmitConfirmRect = nil
    M.questSubmitCancelRect = nil
    M.questSubmitCloseRect = nil
end

-- ====================================================================
-- 交易系统
-- ====================================================================
M.shopMode = false              -- 是否处于交易模式
M.shopBuildingKey = nil         -- 当前交易的建筑key

-- 自动战斗
M.autoMode = false
M.autoTimer = 0
M.homeMode = false
M.homeType = "small"            -- 当前进入的家类型: "small"/"medium"/"large"
M.housePurchased = false        -- 是否已购买小型家园
M.houseBuyDialogVisible = false -- 购买房屋弹窗
M.houseBuyYesRect = nil
M.houseBuyNoRect = nil
M.houseBuySuccessVisible = false -- 购买成功提示弹窗
M.houseBuySuccessOkRect = nil
M.homeUpgradeDialogVisible = false -- 家园升级确认弹窗
M.homeUpgradeYesRect = nil
M.homeUpgradeNoRect = nil
M.homeUpgradeBtnRect = nil         -- 升级按钮区域（棋盘左上角）
M.streetSleepActive = false      -- 街头睡觉中（时间推进到早7点）
M.streetSleepTimer = 0           -- 街头睡觉实时计时器
M.streetSleepBtnRect = nil       -- "确定"按钮区域
M.isRaining = true          -- 世界天气状态（true=雨天, false=晴天）
M.isWindy = false           -- 刮风天气
M.windDirection = 1         -- 风向 1~8（1=北, 顺时针）
M.isScorching = false       -- 暴晒天气
-- 天气变更计时系统
M.YEAR_MINUTES = 518400     -- 一年总分钟数 (360天×24时×60分，每月30天×12个月)
M.weatherTime = 1            -- 全局分钟计时器（1~518400，每+1代表过了1分钟，满后回到1）
M.weatherChangeTimer = 0    -- 自上次天气变更以来的时间累计（天气变更后重置为0）
M.weatherCheckCount = 0     -- 自上次天气变更以来的鉴定次数
M.weatherRealTimer = 0      -- 非战斗实时计时器（秒）
M.trainingMode = false
-- 训练场伤害统计
M.trainingDmgLog = {}       -- 每回合伤害记录 { turn1_dmg, turn2_dmg, ... }
M.trainingTurnDmg = 0       -- 当前回合累计伤害
M.trainingTotalDmg = 0      -- 总伤害
M.trainingTurnCount = 0     -- 已完成的回合数
M.trainingResetBtnRect = nil -- 重置按钮点击区域 {x,y,w,h}

-- 训练假人等级档位表
M.TRAINING_DUMMY_TIERS = {
    { level = 10,  def = 53,   mdef = 53,   dodge = 16   },
    { level = 20,  def = 104,  mdef = 104,  dodge = 29   },
    { level = 30,  def = 153,  mdef = 153,  dodge = 42   },
    { level = 40,  def = 228,  mdef = 228,  dodge = 56   },
    { level = 50,  def = 320,  mdef = 320,  dodge = 74   },
    { level = 60,  def = 370,  mdef = 370,  dodge = 89   },
    { level = 70,  def = 1000, mdef = 1000, dodge = 110  },
    { level = 80,  def = 1200, mdef = 1200, dodge = 127  },
    { level = 90,  def = 1400, mdef = 1400, dodge = 150  },
    { level = 100, def = 1700, mdef = 1700, dodge = 170  },
    { level = 110, def = 2200, mdef = 2200, dodge = 200  },
}
M.trainingDummyTierIdx = 1    -- 当前选中的档位索引 (1-based)
M.trainingLevelUpBtnRect = nil
M.trainingLevelDownBtnRect = nil
M.trainingStatsExpanded = true   -- 统计面板展开/收起状态
M.trainingToggleBtnRect = nil    -- 展开/收起按钮点击区域

--- 根据玩家等级选择默认训练假人档位（<= 玩家等级的最高档）
---@param playerLevel number
---@return number tierIdx
function M.getDefaultDummyTier(playerLevel)
    local tiers = M.TRAINING_DUMMY_TIERS
    local best = 1
    for i, t in ipairs(tiers) do
        if t.level <= playerLevel then
            best = i
        end
    end
    return best
end

--- 应用当前档位属性到所有训练假人
function M.applyDummyTier()
    local tier = M.TRAINING_DUMMY_TIERS[M.trainingDummyTierIdx]
    if not tier then return end
    for _, m in ipairs(M.monsters) do
        if m.isTrainingDummy then
            m.level = tier.level
            m.def = tier.def
            m.mdef = tier.mdef
            m.dodge = tier.dodge
        end
    end
end

-- 鼠标悬停位置（设计坐标）
M.hoverX = 0
M.hoverY = 0

-- debuff tooltip 锁定（点击/触摸后保持显示）
M.lockedDebuffTooltip = nil  -- 锁定的 tooltip 数据

-- 复活
M.respawnTimer = 0
M.respawnMoveCD = 0            -- 复活期间怪物移动冷却
M.deathX = 0
M.deathY = 0
M.tombstoneAnim = nil
M.tombstoneDropAnim = nil
M.reviveEffect = nil  -- 复活光芒特效 { x, y, timer, duration }

-- 采集状态
M.gatheringState = nil  -- { target, progress, turnCount, successRate } 正在采集时非 nil（回合制）
M.gatherResultAnim = nil  -- { x, y, success, timer, duration, itemName } 采集结果动画

-- 家具交互状态（实时进度条，无失败）
M.furnitureInteract = nil  -- { targetX, targetY, progress, duration, action, name }

-- 条形动画（缓冲填充）
M.displayExp = 0
M.displayExpLevel = 1
M.displayHp = 0
M.displayMp = 0

-- 设置面板
M.showSettings = false
M.showGMPanel = false        -- GM 管理面板（独立于设置面板）
M.masterVolume = 0.5
M.volumeSliderDragging = false
M.animationEnabled = false   -- 建筑动画开关（true=播放视频，false=仅用静态背景图）
M.forceLandscape = false     -- 横屏开关（true=强制横屏，false=竖屏）
M.showDamageNumbers = true   -- 伤害数字显示开关（true=显示飘字，false=隐藏）
M.enableScreenShake = true   -- 屏幕震动开关（true=启用震动，false=禁用）
M.showTestStagePanel = false
M.testStageBtnRect = nil
M.testStageScrollY = 0
M.testStagePanelRect = nil
M.testStageBtnRects = {}
M.testStageDragging = false
M.testStageDragStartY = 0
M.testStageDragStartScroll = 0
M.testStageDragMoved = false

M.showTestItemPanel = false
M.testItemBtnRect = nil
M.testItemScrollY = 0
M.testItemPanelRect = nil
M.testItemBtnRects = {}
M.testItemDragging = false
M.testItemDragStartY = 0
M.testItemDragStartScroll = 0
M.testItemDragMoved = false
M.testItemList = nil

-- 布局变量（每帧由渲染更新）
M.SCREEN_W = 0
M.SCREEN_H = 0
M.S = 1
M.dpr = 1
M.isLandscape = false
M.startupElapsed = 0          -- 启动计时器，用于跳过前几帧的物理尺寸检测
M.CELL = 0
M.BOARD_X = 0
M.BOARD_Y = 0
M.BOTTOM_H = 0
M.INFO_H = 0
M.RIGHT_PANEL_X = 0
M.RIGHT_PANEL_W = 0

-- UI 交互区域（每帧由渲染更新）
M.autoBtnRect = nil
M.settingsBtnRect = nil
M.inventorySlotAreas = {}
M.bottomTabBtnRects = {}    -- 底部5个标签按钮区域
M.activeBottomTab = 5       -- 当前激活的标签（默认地图=5）
M.tabAnimTimer = 0          -- Tab 切换动画计时器
M.tabAnimDuration = 0.22    -- 动画时长
M.tabAnimFrom = 0           -- 切换前的 Tab 索引（0=无动画）
M.tabAnimDir = 0            -- 滑动方向（1=向左滑出，-1=向右滑出）
M.showStatsSummary = false  -- 是否显示属性汇总子面板
M.statsSummaryBtnRect = nil -- 属性汇总按钮区域
M.statsTabMode = "attack"   -- 属性汇总分页："attack" 进攻 / "defense" 防守
M.showBuffSummary = false   -- 是否显示BUFF/DEBUFF总结面板
M.buffSummaryBtnRect = nil  -- BUFF总结按钮区域
M.buffSummaryScrollY = 0    -- BUFF总结面板滚动偏移

M.showMonsterBuffSummary = false  -- 是否显示怪物BUFF/DEBUFF总结面板
M.monsterBuffBtnRect = nil       -- 怪物BUFF按钮区域
M.monsterBuffScrollY = 0         -- 怪物BUFF面板滚动偏移
M.topBarLockedTarget = nil       -- 顶栏点击锁定的目标怪物

-- 每日公告板委托完成计数（用于"为了大家！"支线任务）
M.dailyBulletinDoneCount = 0
M.bulletinQuestTotalDone = 0  -- 布告栏任务累计完成次数（前2次给3000G，之后给感恩礼券）

-- 物品拖拽
M.dragSlotIdx = nil         -- 正在拖拽的背包格子索引
M.itemDragActive = false    -- 是否激活物品拖拽（超过阈值后）
M.itemDragStartX = 0        -- 按下时的鼠标坐标
M.itemDragStartY = 0
M.dragOffsetX = 0           -- 拖拽中的鼠标坐标
M.dragOffsetY = 0

-- 物品悬停信息面板
M.tooltipItem = nil         -- 当前悬停的物品数据
M.tooltipSlotIdx = 0        -- 当前悬停的背包格子索引
M.tooltipSource = "inventory" -- 来源: "inventory" 或 "equipment"
M.tooltipEquipSlotId = nil  -- 装备栏来源时的槽位 id
M.tooltipPinned = false     -- 是否锁定显示（点击/触摸触发）
M.tooltipRect = nil         -- 悬停面板区域 {x,y,w,h}
M.tooltipEquipBtnRect = nil -- 装备/卸下按钮区域 {x,y,w,h}
M.tooltipLockBtnRect = nil  -- 锁定按钮区域 {x,y,w,h}
M.tooltipFavBtnRect = nil   -- 收藏按钮区域 {x,y,w,h}
M.tooltipPinnedPos = nil    -- 锁定时保存的面板位置 {px,py}
M.equipSlotAreas = {}       -- 装备槽屏幕区域 { [slotId] = {x,y,w,h} }

-- 自动战斗设置面板
M.showAutoBattleSettings = false
M.AUTO_CONSUMABLE_SLOTS = 2    -- 挂机自动消耗品槽数量
M.autoConsumables = {}         -- { [1..2] = templateId or nil }
M.autoConsumableSlotAreas = {} -- { [1..2] = {x,y,w,h} }  面板内消耗品槽区域
M.autoConsumableThresholds = { 50, 50 }  -- { [1..2] = 百分比 } 低于此比例时自动使用
M.autoConsumableThresholdBtnAreas = {} -- { [1..2] = {x,y,w,h} }
M.autoBattleSettingsPanelRect = nil  -- 面板整体区域
M.autoConsumablePopupSlot = nil      -- 当前打开的消耗品选择弹窗槽位 (1 or 2)
M.autoConsumablePopupItems = {}      -- 弹窗中的候选消耗品列表
M.autoConsumablePopupRect = nil      -- 弹窗整体区域
M.autoConsumablePopupItemRects = {}  -- 弹窗中每个物品的点击区域
M.AUTO_CONSUMABLE_SLOT_STAT = { "hp", "mp" } -- 槽位1=生命药水, 槽位2=魔法药水
M.pendingConsumableSlots = {}  -- 敌人回合中排队等待使用的消耗品背包槽位
M.consumableCooldown = 0       -- 消耗品公共CD（剩余回合数，0=可用）
M.CONSUMABLE_CD_TURNS = 3      -- 使用后进入3回合CD（每4回合可用1次）

-- 自动食物和增强药剂
M.autoFood = nil               -- 自动食物 templateId（效果消失后自动补充）
M.autoBuffPotion = nil          -- 自动增强药剂 templateId（效果消失后自动补充）
M.autoChargeMode = "flank"      -- 冲锋模式: "flank"=侧翼冲锋(远程优先), "front"=正面冲锋(最近优先)
M.autoFoodSlotArea = nil        -- 食物槽位点击区域 {x,y,w,h}
M.autoBuffPotionSlotArea = nil  -- 增强药剂槽位点击区域 {x,y,w,h}
M.autoFoodBuffPopupSlot = nil   -- 弹窗类型: "food" or "buffPotion"
M.autoFoodBuffPopupItems = {}   -- 弹窗候选物品列表
M.autoFoodBuffPopupRect = nil   -- 弹窗整体区域
M.autoFoodBuffPopupItemRects = {} -- 弹窗中每个物品的点击区域

-- 技能悬停信息面板
M.skillTooltipId = nil       -- 当前悬停的技能 ID (string)
M.skillTooltipPinned = false -- 是否锁定显示（点击/触摸触发）
M.skillTooltipRect = nil     -- 悬停面板区域 {x,y,w,h}
M.skillTooltipSource = nil   -- 来源: "tree" 或 "slot"
M.skillTooltipSlotIdx = nil  -- 装备槽来源时的槽位索引

--- 关闭技能悬停面板
function M.closeSkillTooltip()
    M.skillTooltipId = nil
    M.skillTooltipPinned = false
    M.skillTooltipRect = nil
    M.skillTooltipSource = nil
    M.skillTooltipSlotIdx = nil
end

-- 加点系统
M.statAddBtnRects = {}      -- { [statKey] = {x,y,w,h} }
M.statInfoBtnRects = {}     -- { [statKey] = {x,y,w,h} } 感叹号按钮区域
M.statInfoHover = nil       -- 当前悬停的属性key
M.statInfoLocked = nil      -- 点击锁定的属性key
M.combatStatInfoBtnRects = {}  -- 右侧属性汇总感叹号按钮区域
M.combatStatInfoHover = nil
M.combatStatInfoLocked = nil
-- 右侧属性汇总需要感叹号提示的属性
-- 值为函数时返回 { {text, color?}, ... } 的 segments 数组（color 为 {r,g,b,a}，nil 为默认色）
-- 值为字符串时按纯文本显示
M.COMBAT_STAT_TIPS = {
    ["物理暴击值"] = function()
        local p = M.player
        if not p then return nil end
        local lv = math.max(1, p.level or 1)
        local critVal = p.critVal or 0
        local rate = math.min(critVal / (lv * 4), lv / 100) * 100
        local rateStr = string.format("%.1f%%", rate)
        return {
            { text = "你目前攻击" },
            { text = "相同等级", color = {20, 160, 20, 255} },
            { text = "敌人的暴击率是" },
            { text = rateStr, color = {20, 160, 20, 255} },
            { text = "。" },
        }
    end,
    ["攻击速度"] = function()
        local p = M.player
        if not p then return nil end
        local aspd = p.atkSpeed or 0
        local pct = string.format("%.0f%%", aspd * 2)
        return {
            { text = "你目前的物理普通攻击连击概率为" },
            { text = pct, color = {20, 160, 20, 255} },
            { text = "，每1点攻击速度提高2%概率。" },
        }
    end,
    ["魔法暴击值"] = function()
        local p = M.player
        if not p then return nil end
        local lv = math.max(1, p.level or 1)
        local mCritVal = p.mCritRate or 0
        local rate = math.min(mCritVal / (lv * 4), lv / 100) * 100
        local rateStr = string.format("%.1f%%", rate)
        return {
            { text = "你目前攻击" },
            { text = "相同等级", color = {20, 160, 20, 255} },
            { text = "敌人的暴击率是" },
            { text = rateStr, color = {20, 160, 20, 255} },
            { text = "。" },
        }
    end,
    ["吟唱速度"] = function()
        local p = M.player
        if not p then return nil end
        local cspd = p.castSpeed or 0
        local pct = string.format("%.0f%%", cspd * 2)
        return {
            { text = "你目前回合开始获取额外吟唱段数的概率为" },
            { text = pct, color = {20, 160, 20, 255} },
            { text = "，每一点吟唱速度提高2%概率。" },
        }
    end,
}
M.STAT_DEFS = {
    { key = "str", name = "力量", desc = "+3 物理攻击力, +1.5 物理暴击值", descHunter = "+1.5 物理攻击力, +1.5 物理暴击值" },
    { key = "agi", name = "敏捷", desc = "+0.5 攻击速度, +1 闪避值, 每50点+1移动距离" },
    { key = "con", name = "体质", desc = "+9 HP, +4 物理防御力, +0.5 HP自然回复" },
    { key = "wis", name = "智慧", desc = "+3.5 魔法攻击力, +5 MP" },
    { key = "foc", name = "专注", desc = "+1 物理攻击力, +1 命中值", descHunter = "+2.5 物理攻击力, +1 命中值" },
    { key = "per", name = "感知", desc = "+1.5 魔法暴击值, +4 魔法防御力, +0.5 MP自然回复" },
    { key = "wil", name = "意念", desc = "+1 命中值, +0.5 吟唱速度" },
    { key = "luk", name = "幸运", desc = "+1.25% 暴击伤害, +1.25% 魔法暴击伤害, +1 避开要害" },
    { key = "cha", name = "魅力", desc = "同伴 +10 HP, 同伴造成伤害 +1%, 同伴受到伤害 -0.1%" },
}

-- 装备槽定义（左7 + 右7 = 14）
M.equipSlotDefs = {
    -- 左列
    { id = "hat",       name = "头部",     emoji = "🎩", col = "L" },
    { id = "shoulder",  name = "肩部",     emoji = "🛡️", col = "L" },
    { id = "cloak",     name = "背部",     emoji = "🧣", col = "L" },
    { id = "chest",     name = "胸部",     emoji = "👕", col = "L" },
    { id = "gloves",    name = "手部",     emoji = "🧤", col = "L" },
    { id = "pants",     name = "腿部",     emoji = "👖", col = "L" },
    { id = "boots",     name = "脚部",     emoji = "👢", col = "L" },
    -- 右列
    { id = "necklace",  name = "项链",     emoji = "📿", col = "R" },
    { id = "belt",      name = "腰部",     emoji = "🪢", col = "R" },
    { id = "trinket",   name = "挂饰",     emoji = "🔮", col = "R" },
    { id = "ring1",     name = "戒指",     emoji = "💍", col = "R" },
    { id = "ring2",     name = "戒指",     emoji = "💍", col = "R" },
    { id = "weapon_l",  name = "左手武器", emoji = "🗡️", col = "R" },
    { id = "weapon_r",  name = "右手武器", emoji = "⚔️", col = "R" },
}
M.equipment = {} -- 已装备物品，key = slot id

-- ====================================================================
-- 工具函数
-- ====================================================================
function M.cellKey(x, y)
    return y * 100 + x
end

function M.isInBoard(x, y)
    return x >= 1 and x <= M.BOARD_SIZE and y >= 1 and y <= M.BOARD_SIZE
end

-- 大型单位辅助函数
function M.unitSize(unit) return unit.size or 1 end

function M.forEachOccupiedCell(unit, fn)
    local s = M.unitSize(unit)
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            fn(unit.x + dx, unit.y + dy)
        end
    end
end

function M.isAreaInBoard(x, y, s)
    return x >= 1 and y >= 1 and x + s - 1 <= M.BOARD_SIZE and y + s - 1 <= M.BOARD_SIZE
end

function M.isAreaEmpty(x, y, s, excludeUnit)
    if not M.isAreaInBoard(x, y, s) then return false end
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            if not M.isCellEmpty(x + dx, y + dy) then
                -- isCellEmpty 返回 false 可能因为有单位或其他阻挡
                -- 如果是 excludeUnit 自身占据的格子则放行
                local u = M.getUnitAt(x + dx, y + dy)
                if u == excludeUnit then
                    -- 是自身占据的格子，检查除单位外的其他阻挡（宝箱等）
                    -- isCellEmpty 最后调用 getUnitAt，所以如果只是因为自身单位才返回 false，放行
                    -- 重新检查除 getUnitAt 以外的阻挡条件
                    local cx, cy = x + dx, y + dy
                    -- 竞技场宝箱阻挡
                    if M.arenaWaitForExit then
                        for _, chest in ipairs(M.arenaChests) do
                            if not chest.opened and chest.x == cx and chest.y == cy then
                                return false
                            end
                        end
                    end
                    -- 家场景阻挡（大型单位通常不在家场景，但保险起见）
                    if M.homeMode then
                        -- 家场景墙壁/家具已在 isCellEmpty 中检查，这里直接返回 false
                        return false
                    end
                else
                    return false
                end
            end
        end
    end
    return true
end

function M.unitCenterPos(unit)
    local s = M.unitSize(unit)
    return unit.x + (s - 1) / 2, unit.y + (s - 1) / 2
end

function M.manhattanToUnit(px, py, unit)
    local s = M.unitSize(unit)
    local cx = math.max(unit.x, math.min(px, unit.x + s - 1))
    local cy = math.max(unit.y, math.min(py, unit.y + s - 1))
    return math.abs(px - cx) + math.abs(py - cy)
end

function M.getUnitAt(x, y)
    if M.player and M.player.x == x and M.player.y == y and M.player.hp > 0 then
        return M.player
    end
    -- 墓碑碰撞体积：复活倒计时期间死亡位置不可通行
    if M.gameState == M.STATE_RESPAWN and M.deathX == x and M.deathY == y then
        return { isTombstone = true, x = x, y = y }
    end
    -- 暴怒史莱姆王移动计算时：无碰撞体积，仅友军（分身/猎犬）阻挡
    if M._enragedKingMoving then
        for _, c in ipairs(M.companions) do
            if c.hp > 0 and c.x == x and c.y == y then return c end
        end
        return nil
    end
    for _, m in ipairs(M.monsters) do
        if m.hp > 0 then
            local s = m.size or 1
            if x >= m.x and x < m.x + s and y >= m.y and y < m.y + s then
                return m
            end
        end
    end
    for _, c in ipairs(M.companions) do
        if c.hp > 0 and c.x == x and c.y == y then
            return c
        end
    end
    for _, t in ipairs(M.holyTrees) do
        if t.x == x and t.y == y then
            return t
        end
    end
    for _, w in ipairs(M.iceWalls) do
        if w.x == x and w.y == y then
            return w
        end
    end
    for _, g in ipairs(M.gatherables) do
        if g.x == x and g.y == y and not g.vanishing and (g.harvestsLeft or 1) > 0 then
            return g
        end
    end
    return nil
end

--- 根据移动方向更新单位朝向
--- @param unit table 单位对象（player/monster/companion）
--- @param fromX number 起始格X
--- @param fromY number 起始格Y
--- @param toX number 目标格X
--- @param toY number 目标格Y
function M.updateFacing(unit, fromX, fromY, toX, toY)
    local dx = toX - fromX
    local dy = toY - fromY
    if dx == 0 and dy == 0 then return end
    -- 优先取绝对值较大的分量方向
    if math.abs(dx) >= math.abs(dy) then
        unit.facing = dx > 0 and "right" or "left"
    else
        unit.facing = dy > 0 and "down" or "up"
    end
end

--- 让单位面向目标单位
function M.faceTarget(unit, target)
    if not unit or not target then return end
    M.updateFacing(unit, unit.x, unit.y, target.x, target.y)
end

--- 根据位置计算朝向棋盘中心的方向（用于怪物刷新时赋初始朝向）
function M.facingToCenter(x, y)
    local cx, cy = M.BOARD_SIZE / 2 + 0.5, M.BOARD_SIZE / 2 + 0.5
    local dx = cx - x
    local dy = cy - y
    if dx == 0 and dy == 0 then return "down" end
    if math.abs(dx) > math.abs(dy) then
        return dx > 0 and "right" or "left"
    elseif math.abs(dy) > math.abs(dx) then
        return dy > 0 and "down" or "up"
    else
        -- 四角对角线：优先纵向（左上/右上朝下，左下/右下朝上）
        return dy > 0 and "down" or "up"
    end
end

--- 获取家园房间参数（墙壁范围、地板范围、门位置）
---@param hType string "small"|"medium"|"large"
---@return table {wx1,wy1,wx2,wy2, fx1,fy1,fx2,fy2, doorX1,doorX2,doorY}
function M.getHomeRoomParams(hType)
    if hType == "medium" then
        -- 中型：墙体8x8, 地板6x6
        return { wx1=3, wy1=3, wx2=10, wy2=10, fx1=4, fy1=4, fx2=9, fy2=9, doorX1=6, doorX2=7, doorY=10 }
    elseif hType == "large" then
        -- 大型：墙体12x12, 地板10x10
        return { wx1=1, wy1=1, wx2=12, wy2=12, fx1=2, fy1=2, fx2=11, fy2=11, doorX1=6, doorX2=7, doorY=12 }
    else
        -- 小型：墙体6x6, 地板4x4
        return { wx1=4, wy1=4, wx2=9, wy2=9, fx1=5, fy1=5, fx2=8, fy2=8, doorX1=6, doorX2=7, doorY=9 }
    end
end

--- 家具定义表（数据驱动）
--- imgKey/imgFile: 有图片资源的家具；无图片的用灰色占位
--- interact: 可交互类型 ("warehouse"=仓库)
--- warehouseId: 储物箱编号（1=床旁, 2=灶台旁, 3/4=工坊），升级时同编号数据继承
M.HOME_FURNITURE = {
    small = {
        { name="床",    x=8, y=5, w=1, h=2, imgKey="home_bed",       imgFile="image/home_bed.png", walkable=true },
        { name="储物箱", x=7, y=5, w=1, h=1, imgKey="home_chest",     imgFile="image/home_chest.png", interact="warehouse", warehouseId=1 },
        { name="书柜",  x=5, y=5, w=2, h=1, imgKey="home_bookshelf", imgFile="image/home_bookshelf.png" },
        { name="书桌",  x=5, y=7, w=1, h=2, imgKey="home_desk",      imgFile="image/home_desk.png", rotate=-90, interact="shared_storage" },
    },
    medium = {
        { name="书柜",  x=4, y=4, w=2, h=1, imgKey="home_bookshelf", imgFile="image/home_bookshelf.png" },
        { name="书桌",  x=6, y=4, w=2, h=1, imgKey="home_desk", imgFile="image/home_desk.png", interact="shared_storage" },
        { name="储物箱", x=8, y=4, w=1, h=1, imgKey="home_chest",     imgFile="image/home_chest.png", interact="warehouse", warehouseId=1, approachDir="down" },
        { name="床",    x=9, y=4, w=1, h=2, imgKey="home_bed",       imgFile="image/home_bed.png", walkable=true },
        { name="盆栽",  x=4, y=6, w=1, h=1, imgKey="home_plant", imgFile="image/home_plant.png" },
        { name="储物箱", x=4, y=7, w=1, h=1, imgKey="home_chest",     imgFile="image/home_chest.png", interact="warehouse", warehouseId=2, approachDir="right" },
        { name="灶台",  x=4, y=8, w=1, h=2, imgKey="home_stove", imgFile="image/home_stove.png", interact="cooking" },
        { name="炼金台", x=9, y=8, w=1, h=2, imgKey="home_alchemy_table", imgFile="image/home_alchemy_table.png", interact="alchemy" },
    },
    large = {
        -- 上左房间（厨房/餐厅）
        { name="盆栽",  x=2,  y=2,  w=1, h=1, imgKey="home_plant", imgFile="image/home_plant.png" },
        { name="灶台",  x=3,  y=2,  w=2, h=1, imgKey="home_stove_h", imgFile="image/home_stove_h.png", interact="cooking" },
        { name="储物箱", x=6,  y=2,  w=1, h=1, imgKey="home_chest", imgFile="image/home_chest.png", interact="warehouse", warehouseId=2, approachDir="down" },
        { name="盆栽",  x=2,  y=6,  w=1, h=1, imgKey="home_plant", imgFile="image/home_plant.png" },
        { name="书柜",  x=3,  y=6,  w=2, h=1, imgKey="home_bookshelf", imgFile="image/home_bookshelf.png" },
        { name="餐桌",  x=3,  y=4,  w=2, h=1, imgKey="home_dining_table", imgFile="image/home_dining_table.png" },
        -- 上右房间（卧室）
        { name="盆栽",  x=8,  y=2,  w=1, h=1, imgKey="home_plant", imgFile="image/home_plant.png" },
        { name="盆栽",  x=11, y=2,  w=1, h=1, imgKey="home_plant", imgFile="image/home_plant.png" },
        { name="双人床", x=9, y=2,  w=2, h=2, imgKey="home_double_bed", imgFile="image/home_double_bed.png", walkable=true },
        { name="书桌",  x=9,  y=6,  w=2, h=1, imgKey="home_desk", imgFile="image/home_desk.png", interact="shared_storage" },
        { name="储物箱", x=11, y=6,  w=1, h=1, imgKey="home_chest", imgFile="image/home_chest.png", interact="warehouse", warehouseId=1, approachDir="up" },
        -- 下区域（工坊）
        { name="储物箱", x=4,  y=8,  w=1, h=1, imgKey="home_chest", imgFile="image/home_chest.png", interact="warehouse", warehouseId=3, approachDir="down" },
        { name="铁匠台", x=2,  y=8,  w=2, h=2, imgKey="home_smithy", imgFile="image/home_smithy.png", interact="smithy" },
        { name="储物箱", x=11, y=8,  w=1, h=1, imgKey="home_chest", imgFile="image/home_chest.png", interact="warehouse", warehouseId=4, approachDir="left" },
        { name="炼金台", x=11, y=9,  w=1, h=2, imgKey="home_alchemy_table", imgFile="image/home_alchemy_table.png", interact="alchemy" },
        { name="手工桌", x=2,  y=11, w=2, h=1, imgKey="home_crafting_table", imgFile="image/home_crafting_table.png", interact="socket" },
        { name="盆栽",  x=4,  y=11, w=1, h=1, imgKey="home_plant", imgFile="image/home_plant.png" },
        { name="盆栽",  x=11, y=11, w=1, h=1, imgKey="home_plant", imgFile="image/home_plant.png" },
    },
}

--- 内墙定义表（不可通行的内部墙格子）
M.HOME_INNER_WALLS = {
    small = {},
    medium = {
        -- 横向隔墙 y=7, x=7..9
        {x=7, y=7, d="h"}, {x=8, y=7, d="h"}, {x=9, y=7, d="h"},
    },
    large = {
        -- 纵向隔墙上段（分隔上左房和上右房, x=7, y=2..4）
        {x=7, y=2, d="v"}, {x=7, y=3, d="v"}, {x=7, y=4, d="v"},
        -- 横向隔墙（分隔上下区域, y=7，x=6,7留通道）
        {x=2, y=7, d="h"}, {x=3, y=7, d="h"}, {x=4, y=7, d="h"}, {x=5, y=7, d="hv"},
        {x=8, y=7, d="hv"}, {x=9, y=7, d="h"}, {x=10, y=7, d="h"}, {x=11, y=7, d="h"},
        -- 纵向下延（从交叉点往下各一格）
        {x=5, y=8, d="v"}, {x=8, y=8, d="v"},
        -- 底行墙柱
        {x=5, y=11, d="v"}, {x=8, y=11, d="v"},
    },
}

--- 查询指定坐标是否是内墙
function M.isHomeInnerWall(hType, x, y)
    local walls = M.HOME_INNER_WALLS[hType]
    if not walls then return false end
    for _, w in ipairs(walls) do
        if w.x == x and w.y == y then return true end
    end
    return false
end

--- 查询指定坐标是否被家具占据（walkable=true 的家具不阻挡通行）
function M.isHomeFurnitureAt(hType, x, y)
    local furns = M.HOME_FURNITURE[hType]
    if not furns then return false end
    for _, f in ipairs(furns) do
        if not f.walkable and x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h then
            return true
        end
    end
    return false
end

--- 判断玩家是否站在床上（支持所有家园类型的床和双人床）
function M.isPlayerOnBed()
    if not M.homeMode or not M.player or M.player.moveAnim then return false end
    local furns = M.HOME_FURNITURE[M.homeType]
    if not furns then return false end
    local px, py = M.player.x, M.player.y
    for _, f in ipairs(furns) do
        if (f.name == "床" or f.name == "双人床") and f.walkable then
            if px >= f.x and px < f.x + f.w and py >= f.y and py < f.y + f.h then
                return true
            end
        end
    end
    return false
end

--- 查找指定坐标上的可交互家具（返回家具定义或nil）
function M.getInteractableFurnitureAt(hType, cx, cy)
    local furns = M.HOME_FURNITURE[hType]
    if not furns then return nil end
    for _, f in ipairs(furns) do
        if f.interact and cx >= f.x and cx < f.x + f.w and cy >= f.y and cy < f.y + f.h then
            return f
        end
    end
    return nil
end

function M.isCellEmpty(x, y)
    if not M.isInBoard(x, y) then return false end
    -- 家场景墙壁阻挡
    if M.homeMode then
        local p = M.getHomeRoomParams(M.homeType)
        if (x >= p.wx1 and x <= p.wx2 and y >= p.wy1 and y <= p.wy2)
           and (x == p.wx1 or x == p.wx2 or y == p.wy1 or y == p.wy2) then
            -- 门的位置可以通行
            if y == p.doorY and (x == p.doorX1 or x == p.doorX2) then
                -- 门，不阻挡
            else
                return false
            end
        end
        -- 内墙碰撞
        if M.isHomeInnerWall(M.homeType, x, y) then return false end
        -- 家具碰撞
        if M.isHomeFurnitureAt(M.homeType, x, y) then return false end
        -- 墙壁外区域不可通行（大型家园无墙外空间，但中型有）
        if x < p.fx1 or x > p.fx2 or y < p.fy1 or y > p.fy2 then
            -- 门通道特殊处理：门所在行可通行
            if not (y == p.doorY and x >= p.doorX1 and x <= p.doorX2) then
                return false
            end
        end
    end
    -- 家中伴侣NPC阻挡（非移动状态时占位）
    if M.homeMode and M.homeNpc and not M.homeNpc.moveAnim
       and M.homeNpc.x == x and M.homeNpc.y == y then
        return false
    end
    -- 家中猎犬阻挡
    if M.homeMode and M.homeHound
       and M.homeHound.x == x and M.homeHound.y == y then
        return false
    end
    -- 竞技场宝箱阻挡
    if M.arenaWaitForExit then
        for _, chest in ipairs(M.arenaChests) do
            if not chest.opened and chest.x == x and chest.y == y then
                return false
            end
        end
    end
    return M.getUnitAt(x, y) == nil
end

--- 家场景 BFS 寻路：返回从 (fx,fy) 到 (tx,ty) 的最短路径，绕过障碍物
--- @return table|nil 路径 {{x1,y1},{x2,y2},...} 或 nil（无路径）
function M.homePathFind(fx, fy, tx, ty)
    if fx == tx and fy == ty then return {{fx, fy}} end
    local p = M.getHomeRoomParams(M.homeType)
    local queue = {{fx, fy}}
    local visited = {}
    local parent = {}
    visited[fy * 100 + fx] = true
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        local cx, cy = cur[1], cur[2]
        if cx == tx and cy == ty then
            -- 回溯路径
            local path = {}
            local px, py = tx, ty
            while px ~= fx or py ~= fy do
                table.insert(path, 1, {px, py})
                local pp = parent[py * 100 + px]
                px, py = pp[1], pp[2]
            end
            table.insert(path, 1, {fx, fy})
            return path
        end
        for _, d in ipairs(dirs) do
            local nx, ny = cx + d[1], cy + d[2]
            local nk = ny * 100 + nx
            if not visited[nk] then
                local inRoom = nx >= p.fx1 and nx <= p.fx2 and ny >= p.fy1 and ny <= p.fy2
                local isDoor = (ny == p.doorY and (nx == p.doorX1 or nx == p.doorX2))
                local isTarget = (nx == tx and ny == ty)
                -- 目标格子只检查家具碰撞，不检查玩家自身
                local passable = false
                if (inRoom or isDoor) then
                    if isTarget then
                        -- 目标格子：只检查墙壁和家具，不检查 getUnitAt
                        if M.homeType == "small" then
                            local isFurniture = (nx == 7 and ny == 5)           -- 储物箱
                                or ((nx == 5 or nx == 6) and ny == 5)           -- 书柜
                                or (nx == 5 and (ny == 7 or ny == 8))           -- 书桌
                            passable = not isFurniture
                        else
                            passable = true
                        end
                    else
                        passable = M.isCellEmpty(nx, ny)
                    end
                end
                if passable then
                    visited[nk] = true
                    parent[nk] = {cx, cy}
                    queue[#queue + 1] = {nx, ny}
                end
            end
        end
    end
    return nil
end

--- 竞技场/副本自由移动寻路（BFS，无怪物时全棋盘可通行）
function M.arenaPathFind(fx, fy, tx, ty)
    if fx == tx and fy == ty then return {{fx, fy}} end
    if not M.isInBoard(tx, ty) then return nil end
    -- 构建宝箱占据格子集合（不可通行）
    local blocked = {}
    if M.arenaChests then
        for _, chest in ipairs(M.arenaChests) do
            if not chest.opened then
                blocked[chest.y * 100 + chest.x] = true
            end
        end
    end
    -- 目标格子本身不视为阻挡（允许走到出口等位置）
    blocked[ty * 100 + tx] = nil
    local queue = {{fx, fy}}
    local visited = {}
    local parent = {}
    visited[fy * 100 + fx] = true
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        local cx, cy = cur[1], cur[2]
        if cx == tx and cy == ty then
            local path = {}
            local px, py = tx, ty
            while px ~= fx or py ~= fy do
                table.insert(path, 1, {px, py})
                local pp = parent[py * 100 + px]
                px, py = pp[1], pp[2]
            end
            table.insert(path, 1, {fx, fy})
            return path
        end
        for _, d in ipairs(dirs) do
            local nx, ny = cx + d[1], cy + d[2]
            local nk = ny * 100 + nx
            if not visited[nk] and M.isInBoard(nx, ny) and not blocked[nk] then
                visited[nk] = true
                parent[nk] = {cx, cy}
                queue[#queue + 1] = {nx, ny}
            end
        end
    end
    return nil
end

--- 将占据指定格子的单位推到最近的空格子
--- 用于友方单位（圣树/冰墙）创建时，目标格子已被怪物占据的情况
---@param x number 目标格子X
---@param y number 目标格子Y
---@return boolean 是否成功（格子为空或已成功推开）
function M.displaceUnitAt(x, y)
    local occupant = M.getUnitAt(x, y)
    if not occupant then return true end  -- 格子已空
    if occupant == M.player then return false end  -- 不推开玩家

    -- BFS查找最近的空格子
    local visited = {}
    local queue = {}
    local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
    visited[M.cellKey(x, y)] = true
    for _, d in ipairs(dirs) do
        local nx, ny = x + d[1], y + d[2]
        local k = M.cellKey(nx, ny)
        if M.isInBoard(nx, ny) and not visited[k] then
            visited[k] = true
            queue[#queue + 1] = {nx, ny}
        end
    end

    local idx = 1
    while idx <= #queue do
        local cx, cy = queue[idx][1], queue[idx][2]
        idx = idx + 1
        if M.isCellEmpty(cx, cy) then
            -- 找到空格子，移动占据者
            occupant.x = cx
            occupant.y = cy
            return true
        end
        for _, d in ipairs(dirs) do
            local nx, ny = cx + d[1], cy + d[2]
            local k = M.cellKey(nx, ny)
            if M.isInBoard(nx, ny) and not visited[k] then
                visited[k] = true
                queue[#queue + 1] = {nx, ny}
            end
        end
    end
    return false  -- 没有空格子（极端情况）
end

function M.manhattan(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

M.EXP_TABLE = {
    5, 10, 15, 20, 25, 35, 40, 45, 50, 55,                    -- 1-10
    61, 67, 73, 81, 89, 97, 107, 118, 130, 143,                -- 11-20
    157, 173, 190, 209, 230, 253, 278, 306, 336, 404,          -- 21-30
    484, 581, 698, 837, 1004, 1205, 1446, 1736, 2083, 2499,    -- 31-40
    2999, 3599, 4319, 5183, 6219, 7463, 8955, 10747, 12896, 15475,  -- 41-50
    18570, 22284, 26741, 32089, 38507, 46208, 55450, 66540, 79847, 95817,  -- 51-60
    114980, 137976, 165572, 198686, 238423, 286108, 343329, 411995, 494394, 593273,  -- 61-70
    711928, 854314, 1025176, 1230211, 1476254, 1771505, 2125805, 2550967, 3061160, 3673392,  -- 71-80
    4408070, 5289684, 6347621, 7617145, 9140574, 10968689, 13162427, 15794912, 18953895, 22744674,  -- 81-90
    27293609, 32752331, 39302797, 47163356, 56596027, 67915233, 81498279, 97797935, 99999999,  -- 91-99
}

function M.expToNextLevel(level)
    if level >= 1 and level <= #M.EXP_TABLE then
        return M.EXP_TABLE[level]
    end
    return 99999999
end

-- ====================================================================
-- 强化系统
-- ====================================================================
M.enhanceMode = false         -- 是否处于强化模式
M.enhanceResult = nil         -- 最近一次强化结果 { success, msg, timer }
M.enhanceSlotItem = nil       -- 强化槽中放入的物品引用
M.enhanceSlotSource = nil     -- 来源标识: "equip" 或 "bag"
M.enhanceSlotSourceId = nil   -- 来源装备槽id(string) 或 背包索引(number)
M.enhanceDropRect = nil       -- 强化放置槽的屏幕区域 {x,y,w,h}
M.enhanceBtnRect = nil        -- 强化按钮区域

-- 修复模式（独立面板）
M.repairMode = false          -- 是否处于修复模式
M.repairResult = nil          -- 最近一次修复结果 { success, msg, timer }
M.repairSlotItem = nil        -- 修复槽中放入的物品引用
M.repairSlotSource = nil      -- 来源标识: "equip" 或 "bag"
M.repairSlotSourceId = nil    -- 来源装备槽id(string) 或 背包索引(number)
M.repairDropRect = nil        -- 修复放置槽的屏幕区域 {x,y,w,h}
M.repairBtnRect = nil         -- 修复按钮区域
M.repairCloseRect = nil       -- 修复面板关闭按钮区域
M.toughnessBtnRect = nil      -- 韧性修复按钮区域
M.REPAIR_COST = 1             -- 修复脆化费用（金币）

-- 锻造模式（独立面板）
M.forgeMode = false           -- 是否处于锻造模式
M.forgeResult = nil           -- 最近一次锻造结果 { success, msg, timer }
M.forgeCloseRect = nil        -- 锻造面板关闭按钮区域
M.forgeScrollY = 0            -- 配方列表滚动偏移
M.forgeBtnRects = {}          -- 每个配方的锻造按钮区域 [{x,y,w,h,idx}, ...]
M.FORGE_FUEL_RATE = 0.30      -- 燃料费 = 原材料value × 30%
M.FORGE_COMMISSION_RATE = 0.50 -- 委托加工费 = 原材料value × 50%

-- 炼金模式（独立面板）
M.alchemyMode = false           -- 是否处于炼金模式
M.homeAlchemyMode = false       -- 是否从家用炼金台打开（委托费为0）
M.homeCookingMode = false       -- 是否从家用灶台打开（委托费为0）
M.homeSmithySelectMode = false  -- 铁匠台选择弹窗（锻造/加工/附魔）
M.homeSmithySelectRects = nil   -- 弹窗按钮区域 { forgeBtn, craftBtn, enchantBtn, closeBtn }
M.homeForgeMode = false         -- 是否从家用铁匠台打开锻造（委托费为0）
M.homeCraftMode = false         -- 是否从家用铁匠台打开加工（委托费为0）
M.homeEnchantMode = false       -- 是否从家用铁匠台打开附魔
M.enchantMode = false           -- 附魔面板是否打开
M.enchantSlotItem = nil         -- 附魔面板中放置的装备引用
M.enchantSlotSource = nil       -- 装备来源（"equip" / "bag"）
M.enchantSlotSourceId = nil     -- 装备来源索引
M.enchantResult = nil           -- 附魔结果 { success, msg, timer }
M.enchantCloseRect = nil        -- 附魔面板关闭按钮区域
M.enchantDropRect = nil         -- 附魔面板装备放置区域
M.enchantBtnRect = nil          -- 附魔按钮区域
M.homeSocketMode = false        -- 是否从家用手工桌打开镶嵌（费用打3折）
M.alchemyResult = nil           -- 最近一次炼金结果 { success, msg, timer }
M.alchemyCloseRect = nil        -- 炼金面板关闭按钮区域
M.alchemyScrollY = 0            -- 配方列表滚动偏移
M.alchemyPanelRect = nil        -- 炼金面板区域（用于滚动事件）

-- 委托加工模式（统一面板：强化/精炼/修复）
M.craftMode = false              -- 是否处于委托加工模式
M.craftTab = "enhance"           -- 当前子标签: "enhance" | "refine" | "repair"
M.craftSlotItem = nil            -- 共享放置槽中的物品引用
M.craftSlotSource = nil          -- 来源标识: "equip" 或 "bag"
M.craftSlotSourceId = nil        -- 来源装备槽id(string) 或 背包索引(number)
M.craftDropRect = nil            -- 共享放置槽的屏幕区域 {x,y,w,h}
M.craftCloseRect = nil           -- 面板关闭按钮区域
M.craftTabRects = {}             -- 三个标签页的点击区域
M.craftEnhanceResult = nil       -- 强化结果 { success, msg, timer }
M.craftEnhanceBtnRect = nil      -- 强化按钮区域
M.craftRefineResult = nil        -- 精炼结果
M.craftRefineSlotBtnRects = {}   -- 精炼槽按钮
M.craftRepairResult = nil        -- 修复结果
M.craftRepairBtnRect = nil       -- 修复按钮区域
M.craftToughnessBtnRect = nil    -- 韧性修复按钮区域
M.craftExtractResult = nil       -- 萃取结果 { success, msg, timer }
M.craftExtractBtnRect = nil      -- 萃取按钮区域
M.extractSourceItem = nil        -- 萃取源装备（低等级，有强化）
M.extractTargetItem = nil        -- 萃取目标装备（高等级，+0）
M.extractSourceSource = nil      -- 源来源标识: "equip" 或 "bag"
M.extractSourceSourceId = nil    -- 源来源装备槽id 或 背包索引
M.extractTargetSource = nil      -- 目标来源标识
M.extractTargetSourceId = nil    -- 目标来源装备槽id 或 背包索引
M.extractSourceDropRect = nil    -- 源装备放置槽区域
M.extractTargetDropRect = nil    -- 目标装备放置槽区域

-- 布告栏委托（直接渲染在建筑背景上）
M.bulletinQuestIndex = 1        -- 当前查看的委托索引 (1-5)
M.bulletinQuestBtnRect = nil         -- 当前委托的操作按钮区域（提交/领取/接取）
M.bulletinQuestRerollBtnRect = nil   -- 换一个按钮区域（看广告重新随机委托）
M.bulletinArrowLeftRect = nil        -- 左箭头区域
M.bulletinArrowRightRect = nil       -- 右箭头区域

-- 日志面板（Tab 4）滚动状态
M.journalScrollY = 0            -- 滚动偏移
M.journalScrollRect = nil       -- 可滚动区域（由 Renderer_Panels 设置）
M.journalContentH = 0           -- 内容总高度
M.journalVisibleH = 0           -- 可见高度
M.journalDragging = false       -- 是否正在拖拽滚动
M.journalDragStartY = 0
M.journalDragStartScroll = 0
M.journalSectionExpanded = { true, true, true }  -- 三大任务分类展开状态
M.journalToggleBtnRects = {}   -- 展开/收起按钮点击区域
M.journalSubmitBtnRects = {}   -- 提交任务按钮点击区域

-- 镶嵌模式（独立面板）
M.socketMode = false            -- 是否处于镶嵌模式
M.socketResult = nil            -- 最近一次镶嵌结果 { success, msg, timer }
M.socketCloseRect = nil         -- 镶嵌面板关闭按钮区域
M.socketScrollY = 0             -- 面板滚动偏移
M.socketEquipItem = nil         -- 当前放入的装备引用
M.socketEquipSource = nil       -- 装备来源 "bag"/"equip"
M.socketEquipSourceId = nil     -- 装备来源索引/id
M.socketSelectedGemSlot = nil   -- 选中的宝石槽索引 (1-based)
M.socketSelectedGemBag = nil    -- 选中的背包宝石槽索引 (1-based in bag)
M.socketGemBtnRects = {}        -- 宝石镶嵌按钮区域
M.socketDropRect = nil          -- 装备放置槽区域
M.socketPanelRect = nil         -- 面板整体区域（用于滚动拖拽）
M.socketTab = "socket"          -- 镶嵌面板当前分页 "socket" / "reforge"
M.socketTabRects = {}           -- 分页标签点击区域

-- 面纱重铸（在镶嵌面板的"面纱重铸"分页中）
M.veilReforgeTime = nil         -- 重铸开始时间戳（nil=未在重铸）
M.reforgeVeilItem = nil         -- 放入的面纱引用
M.reforgeGemItem = nil          -- 放入的卓越宝石引用
M.reforgeVeilSource = nil       -- 面纱来源 "bag"/"equip"
M.reforgeVeilSourceId = nil     -- 面纱来源索引
M.reforgeGemSource = nil        -- 宝石来源 "bag"
M.reforgeGemSourceId = nil      -- 宝石来源索引
M.reforgeVeilDropRect = nil     -- 面纱放置槽区域
M.reforgeGemDropRect = nil      -- 宝石放置槽区域
M.reforgeBtnRect = nil          -- 重铸按钮区域
M.reforgeCollectBtnRect = nil   -- 领取按钮区域

-- 锻造配方表：inputId=消耗矿石, outputId=产出锭, forgingLevel=锻造等级需求
M.FORGE_RECIPES = {
    { inputId = "crude_iron_ore",  outputId = "iron_ingot",         forgingLevel = 0 },
    { inputId = "tongkuang",       outputId = "copper_ingot",       forgingLevel = 50 },
    { inputId = "yinkuang",        outputId = "silver_ingot",       forgingLevel = 100 },
    { inputId = "jinkuangshi",     outputId = "gold_ingot",         forgingLevel = 150 },
    { inputId = "lanyinkuangshi",  outputId = "blue_silver_ingot",  forgingLevel = 200 },
    { inputId = "huijinkuangshi",  outputId = "radiant_gold_ingot", forgingLevel = 250 },
    { inputId = "heigangkuangshi", outputId = "black_steel_ingot",  forgingLevel = 300 },
    { inputId = "miyinkuangshi",   outputId = "mithril_ingot",      forgingLevel = 350 },
    { inputId = "zhenyinkuangshi", outputId = "true_silver_ingot",  forgingLevel = 400 },
    { inputId = "zhenjinkuangshi", outputId = "true_gold_ingot",    forgingLevel = 450 },
    -- 晶矿切选：type="crystal_cut", 同色概率产出不同品质
    { inputId = "hongshuijing_cujing",    outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "hong" },
    { inputId = "huangshuijing_cujing",   outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "huang" },
    { inputId = "lanshuijing_cujing",     outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "lan" },
    { inputId = "lvshuijing_cujing",      outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "lv" },
    { inputId = "heishuijing_cujing",     outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "hei" },
    { inputId = "baishuijing_cujing",     outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "bai" },
    { inputId = "zishuijing_cujing",      outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "zi" },
    { inputId = "fenshuijing_cujing",     outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "fen" },
    { inputId = "qingshuijing_cujing",    outputId = nil, forgingLevel = 100, type = "crystal_cut", color = "qing" },
    { inputId = "hongshuijing_wanzheng",  outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "hong" },
    { inputId = "huangshuijing_wanzheng", outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "huang" },
    { inputId = "lanshuijing_wanzheng",   outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "lan" },
    { inputId = "lvshuijing_wanzheng",    outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "lv" },
    { inputId = "heishuijing_wanzheng",   outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "hei" },
    { inputId = "baishuijing_wanzheng",   outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "bai" },
    { inputId = "zishuijing_wanzheng",    outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "zi" },
    { inputId = "fenshuijing_wanzheng",   outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "fen" },
    { inputId = "qingshuijing_wanzheng",  outputId = nil, forgingLevel = 200, type = "crystal_cut", color = "qing" },
    { inputId = "hongshuijing_chunjing",  outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "hong" },
    { inputId = "huangshuijing_chunjing", outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "huang" },
    { inputId = "lanshuijing_chunjing",   outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "lan" },
    { inputId = "lvshuijing_chunjing",    outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "lv" },
    { inputId = "heishuijing_chunjing",   outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "hei" },
    { inputId = "baishuijing_chunjing",   outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "bai" },
    { inputId = "zishuijing_chunjing",    outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "zi" },
    { inputId = "fenshuijing_chunjing",   outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "fen" },
    { inputId = "qingshuijing_chunjing",  outputId = nil, forgingLevel = 300, type = "crystal_cut", color = "qing" },
    { inputId = "hongshuijing_shanyao",   outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "hong" },
    { inputId = "huangshuijing_shanyao",  outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "huang" },
    { inputId = "lanshuijing_shanyao",    outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "lan" },
    { inputId = "lvshuijing_shanyao",     outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "lv" },
    { inputId = "heishuijing_shanyao",    outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "hei" },
    { inputId = "baishuijing_shanyao",    outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "bai" },
    { inputId = "zishuijing_shanyao",     outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "zi" },
    { inputId = "fenshuijing_shanyao",    outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "fen" },
    { inputId = "qingshuijing_shanyao",   outputId = nil, forgingLevel = 400, type = "crystal_cut", color = "qing" },
}

-- 晶矿切选概率表：输入晶矿品质 → 产出同色宝石(gem_{color}_{tier})的概率
-- 碎裂晶矿: 10%完整宝石, 90%碎裂宝石
-- 完整晶矿: 10%纯净宝石, 30%完整宝石, 60%碎裂宝石
-- 纯净晶矿: 10%闪耀宝石, 30%纯净宝石, 60%完整宝石
-- 闪耀晶矿: 30%闪耀宝石, 70%纯净宝石
M.CRYSTAL_CUT_TIER_NAMES = { cujing = "碎裂", wanzheng = "完整", chunjing = "纯净", shanyao = "闪耀" }
M.CRYSTAL_CUT_ODDS = {
    cujing   = { { tier = "wanzheng", chance = 0.10 }, { tier = "cujing", chance = 0.90 } },
    wanzheng = { { tier = "chunjing", chance = 0.10 }, { tier = "wanzheng", chance = 0.30 }, { tier = "cujing", chance = 0.60 } },
    chunjing = { { tier = "shanyao",  chance = 0.10 }, { tier = "chunjing", chance = 0.30 }, { tier = "wanzheng", chance = 0.60 } },
    shanyao  = { { tier = "shanyao",  chance = 0.30 }, { tier = "chunjing", chance = 0.70 } },
}

--- 根据输入晶矿 ID 提取品质后缀
function M.getCrystalTierFromId(inputId)
    for _, t in ipairs({"shanyao", "chunjing", "wanzheng", "cujing"}) do
        if inputId:sub(-#t) == t then return t end
    end
    return nil
end

--- 根据概率表随机选择产出宝石品质
function M.rollCrystalCutResult(inputTier)
    local odds = M.CRYSTAL_CUT_ODDS[inputTier]
    if not odds then return inputTier end
    local roll = math.random()
    local cumul = 0
    for _, entry in ipairs(odds) do
        cumul = cumul + entry.chance
        if roll <= cumul then return entry.tier end
    end
    return odds[#odds].tier  -- fallback
end

--- 执行锻造：消耗1个矿石 + 金币（燃料费+委托加工费），产出1个锭，获得锻造经验
---@param recipeIdx number 配方索引（1-based）
---@return boolean success, string msg
function M.doForge(recipeIdx)
    local recipe = M.FORGE_RECIPES[recipeIdx]
    if not recipe then return false, "无效配方" end

    local inputTpl = M.itemTemplates[recipe.inputId]
    if not inputTpl then return false, "物品数据异常" end

    -- 晶矿切选：产出由概率决定，不使用固定 outputId
    local isCrystalCut = recipe.type == "crystal_cut"
    if not isCrystalCut then
        if not recipe.outputId then return false, "该配方尚未开放" end
        local outputTpl = M.itemTemplates[recipe.outputId]
        if not outputTpl then return false, "物品数据异常" end
    end

    -- 计算锻造等级差与失败率
    local playerHLv = M.getLifeSkillHiddenLevel("forging")
    local levelDeficit = math.max(0, recipe.forgingLevel - playerHLv)  -- 缺少的经验点数
    local failRate = math.min(levelDeficit * 0.04, 1.0)  -- 每缺1点+4%失败率，上限100%
    local successRate = 1.0 - failRate

    -- 检查背包是否有矿石
    local inputSlot = nil
    for i = 1, M.bagSlots do
        local item = M.inventory[i]
        if item and item.templateId == recipe.inputId then
            inputSlot = i
            break
        end
    end
    if not inputSlot then return false, "缺少 " .. inputTpl.name end

    -- 计算费用
    local matValue = inputTpl.value or 0
    local fuelCost = math.ceil(matValue * M.FORGE_FUEL_RATE)
    local commCost = M.homeForgeMode and 0 or math.ceil(matValue * M.FORGE_COMMISSION_RATE)
    local totalCost = fuelCost + commCost
    if M.gold < totalCost then
        return false, "金币不足（需 " .. totalCost .. " G）"
    end

    -- 确定产出物 ID
    local actualOutputId
    if isCrystalCut then
        local inputTier = M.getCrystalTierFromId(recipe.inputId)
        if not inputTier then return false, "无法识别晶矿品质" end
        local resultTier = M.rollCrystalCutResult(inputTier)
        actualOutputId = "gem_" .. recipe.color .. "_" .. resultTier
    else
        actualOutputId = recipe.outputId
    end
    local outputTpl = M.itemTemplates[actualOutputId]
    if not outputTpl then return false, "产出物数据异常: " .. actualOutputId end

    -- 检查产出物能否放入背包（堆叠或空位）
    local canStack = false
    local hasEmpty = false
    local outputStackable = (outputTpl.consumable ~= nil or outputTpl.category == "材料") and outputTpl.slot == nil
    for i = 1, M.bagSlots do
        local inv = M.inventory[i]
        if not inv then
            hasEmpty = true; break
        elseif outputStackable and inv.templateId == actualOutputId and inv.stackable and inv.quantity < (M.STACK_MAX or 99) then
            canStack = true; break
        end
    end
    -- 扣矿后会腾出空位的情况
    local inputItem = M.inventory[inputSlot]
    local willFreeSlot = not inputItem.quantity or inputItem.quantity <= 1
    if not canStack and not hasEmpty and not willFreeSlot then
        return false, "背包已满"
    end

    -- 执行：扣矿石、扣金币
    if inputItem.quantity and inputItem.quantity > 1 then
        inputItem.quantity = inputItem.quantity - 1
    else
        M.inventory[inputSlot] = nil
    end
    M.gold = M.gold - totalCost

    local actionName = isCrystalCut and "切选" or "锻造"
    local lifeSkillId = "forging"

    -- 锻造成功/失败判定
    local roll = math.random()
    if roll >= successRate then
        -- 锻造失败：材料和金币已扣除，不产出
        local pct = math.floor(successRate * 100 + 0.5)
        return false, actionName .. "失败！(成功率" .. pct .. "%) 损失了 " .. inputTpl.name .. " 和 " .. totalCost .. " G"
    end

    -- 大成功/特大成功判定
    local critMul, critType = M.rollLifeSkillCrit(lifeSkillId)
    local finalOutCount = 1 * critMul

    -- 产出物放入背包
    local added = M.addToInventory(actualOutputId, finalOutCount)
    if not added then return false, "背包已满" end

    -- 锻造经验
    local diff = playerHLv - recipe.forgingLevel
    local expGain = 0
    if successRate < 0.50 then
        -- 低于50%成功率时成功，获得2点经验
        expGain = 2
    elseif diff < 0 then
        expGain = 1
    elseif diff <= 25 then
        expGain = 1
    elseif diff <= 40 then
        if math.random() <= 0.5 then expGain = 1 end
    elseif diff <= 50 then
        if math.random() <= 0.2 then expGain = 1 end
    end

    local tierUpMsg = nil
    if expGain > 0 then
        local curExp = (M.lifeSkillExp[lifeSkillId] or 0) + expGain
        local curTier = M.lifeSkillTiers[lifeSkillId] or 1
        if curExp >= M.LIFE_SKILL_MAX_LEVEL and curTier < M.LIFE_SKILL_MAX_TIER then
            curExp = curExp - M.LIFE_SKILL_MAX_LEVEL
            curTier = curTier + 1
            M.lifeSkillTiers[lifeSkillId] = curTier
            local tierDef = M.LIFE_SKILL_TIERS[curTier]
            tierUpMsg = "锻造升阶: " .. tierDef.name
        elseif curTier >= M.LIFE_SKILL_MAX_TIER then
            curExp = math.min(curExp, M.LIFE_SKILL_MAX_LEVEL)
        end
        M.lifeSkillExp[lifeSkillId] = curExp
    end
    local critLabel = critType == "super" and "★特大成功★ " or (critType == "great" and "★大成功★ " or "")
    local countStr = finalOutCount > 1 and (" ×" .. finalOutCount) or ""
    local msg = critLabel .. actionName .. "成功: " .. outputTpl.name .. countStr
    if expGain > 0 then msg = msg .. "  锻造经验+" .. expGain end
    if tierUpMsg then msg = msg .. "  " .. tierUpMsg end
    return true, msg
end

-- ====================================================================
-- 炼金配方表：inputId=消耗草药, outputId=产出药剂, alchemyLevel=炼金等级需求
-- alchemyLevel 对应生活技能隐藏等级 = (tier-1)*100 + exp
-- ====================================================================
M.alchemyBtnRects = {}           -- 每个配方的炼金按钮区域

M.ALCHEMY_RECIPES = {
    -- ── 生命药剂（青慈草系列）──
    { inputId = "qingcicao", inputCount = 1,  outputId = "potion_hp_s",   alchemyLevel = 1,   fuelCost = 3,    commissionCost = 5, outputCount = 5 },
    { inputId = "qingcicao", inputCount = 1,  outputId = "potion_hp_m",   alchemyLevel = 75,  fuelCost = 3,    commissionCost = 5, outputCount = 3 },
    { inputId = "qingcicao", inputCount = 3,  outputId = "potion_hp_l",   alchemyLevel = 110, fuelCost = 9,    commissionCost = 15, outputCount = 3 },
    { inputId = "qingcicao", inputCount = 7,  outputId = "potion_hp_xl",  alchemyLevel = 150, fuelCost = 21,   commissionCost = 35, outputCount = 3 },
    { inputId = "qingcicao", inputCount = 15, outputId = "potion_hp_xxl", alchemyLevel = 200, fuelCost = 45,   commissionCost = 75, outputCount = 3 },

    -- ── 魔法药剂（紫鸢系列）──
    { inputId = "ziyan", inputCount = 1,  outputId = "potion_mp_s",   alchemyLevel = 25,  fuelCost = 3,    commissionCost = 6, outputCount = 5 },
    { inputId = "ziyan", inputCount = 1,  outputId = "potion_mp_m",   alchemyLevel = 100, fuelCost = 3,    commissionCost = 6, outputCount = 3 },
    { inputId = "ziyan", inputCount = 3,  outputId = "potion_mp_l",   alchemyLevel = 125, fuelCost = 10,   commissionCost = 18, outputCount = 3 },
    { inputId = "ziyan", inputCount = 7,  outputId = "potion_mp_xl",  alchemyLevel = 175, fuelCost = 25,   commissionCost = 42, outputCount = 3 },
    { inputId = "ziyan", inputCount = 15, outputId = "potion_mp_xxl", alchemyLevel = 225, fuelCost = 54,   commissionCost = 90, outputCount = 3 },

    -- ── 精准药剂（鼠尾草系列）──
    { inputId = "shuweicao", inputCount = 1,  outputId = "potion_acc_s",   alchemyLevel = 50,  fuelCost = 4,    commissionCost = 7 },
    { inputId = "shuweicao", inputCount = 3,  outputId = "potion_acc_m",   alchemyLevel = 130, fuelCost = 13,   commissionCost = 22 },
    { inputId = "shuweicao", inputCount = 6,  outputId = "potion_acc_l",   alchemyLevel = 150, fuelCost = 27,   commissionCost = 45 },
    { inputId = "shuweicao", inputCount = 10, outputId = "potion_acc_xl",  alchemyLevel = 200, fuelCost = 45,   commissionCost = 75 },
    { inputId = "shuweicao", inputCount = 15, outputId = "potion_acc_xxl", alchemyLevel = 250, fuelCost = 67,   commissionCost = 112 },

    -- ── 威力药剂（龙舌兰系列）──
    { inputId = "wei_li_cao", inputCount = 3,  outputId = "potion_atk_m",   alchemyLevel = 160, fuelCost = 27,   commissionCost = 45 },
    { inputId = "wei_li_cao", inputCount = 6,  outputId = "potion_atk_l",   alchemyLevel = 175, fuelCost = 54,   commissionCost = 90 },
    { inputId = "wei_li_cao", inputCount = 10, outputId = "potion_atk_xl",  alchemyLevel = 225, fuelCost = 90,   commissionCost = 150 },
    { inputId = "wei_li_cao", inputCount = 15, outputId = "potion_atk_xxl", alchemyLevel = 275, fuelCost = 135,  commissionCost = 225 },

    -- ── 魔力药剂（魔绣球系列）──
    { inputId = "mo_li_cao", inputCount = 3,  outputId = "potion_matk_m",   alchemyLevel = 190, fuelCost = 40,   commissionCost = 67 },
    { inputId = "mo_li_cao", inputCount = 6,  outputId = "potion_matk_l",   alchemyLevel = 200, fuelCost = 81,   commissionCost = 135 },
    { inputId = "mo_li_cao", inputCount = 10, outputId = "potion_matk_xl",  alchemyLevel = 250, fuelCost = 135,  commissionCost = 225 },
    { inputId = "mo_li_cao", inputCount = 15, outputId = "potion_matk_xxl", alchemyLevel = 300, fuelCost = 202,  commissionCost = 337 },

    -- ── 坚固药剂（圣百合系列）──
    { inputId = "jian_gu_cao", inputCount = 3,  outputId = "potion_def_m",   alchemyLevel = 200, fuelCost = 54,   commissionCost = 90 },
    { inputId = "jian_gu_cao", inputCount = 6,  outputId = "potion_def_l",   alchemyLevel = 225, fuelCost = 108,  commissionCost = 180 },
    { inputId = "jian_gu_cao", inputCount = 10, outputId = "potion_def_xl",  alchemyLevel = 275, fuelCost = 180,  commissionCost = 300 },
    { inputId = "jian_gu_cao", inputCount = 15, outputId = "potion_def_xxl", alchemyLevel = 325, fuelCost = 270,  commissionCost = 450 },

    -- ── 闪避药剂（眩目雏菊系列）──
    { inputId = "shan_bi_cao", inputCount = 3,  outputId = "potion_dodge_m",   alchemyLevel = 200, fuelCost = 67,   commissionCost = 112 },
    { inputId = "shan_bi_cao", inputCount = 6,  outputId = "potion_dodge_l",   alchemyLevel = 250, fuelCost = 135,  commissionCost = 225 },
    { inputId = "shan_bi_cao", inputCount = 10, outputId = "potion_dodge_xl",  alchemyLevel = 300, fuelCost = 225,  commissionCost = 375 },
    { inputId = "shan_bi_cao", inputCount = 15, outputId = "potion_dodge_xxl", alchemyLevel = 350, fuelCost = 337,  commissionCost = 562 },

    -- ── 魔防药剂（蓝星系列）──
    { inputId = "mo_kang_cao", inputCount = 6,  outputId = "potion_mdef_l",   alchemyLevel = 275, fuelCost = 252,  commissionCost = 420 },
    { inputId = "mo_kang_cao", inputCount = 10, outputId = "potion_mdef_xl",  alchemyLevel = 325, fuelCost = 420,  commissionCost = 700 },
    { inputId = "mo_kang_cao", inputCount = 15, outputId = "potion_mdef_xxl", alchemyLevel = 375, fuelCost = 630,  commissionCost = 1050 },

    -- ── 智慧药剂（夜幽兰系列）──
    { inputId = "zhi_hui_cao", inputCount = 6,  outputId = "potion_wis_l",   alchemyLevel = 300, fuelCost = 270,  commissionCost = 450 },
    { inputId = "zhi_hui_cao", inputCount = 10, outputId = "potion_wis_xl",  alchemyLevel = 350, fuelCost = 450,  commissionCost = 750 },
    { inputId = "zhi_hui_cao", inputCount = 15, outputId = "potion_wis_xxl", alchemyLevel = 400, fuelCost = 675,  commissionCost = 1125 },

    -- ── 感知药剂（紫色猫系列）──
    { inputId = "gan_zhi_cao", inputCount = 6,  outputId = "potion_per_l",   alchemyLevel = 300, fuelCost = 288,  commissionCost = 480 },
    { inputId = "gan_zhi_cao", inputCount = 10, outputId = "potion_per_xl",  alchemyLevel = 375, fuelCost = 480,  commissionCost = 800 },
    { inputId = "gan_zhi_cao", inputCount = 15, outputId = "potion_per_xxl", alchemyLevel = 425, fuelCost = 720,  commissionCost = 1200 },

    -- ── 专注药剂（一串黄系列）──
    { inputId = "zhuan_zhu_cao", inputCount = 6,  outputId = "potion_foc_l",   alchemyLevel = 300, fuelCost = 306,  commissionCost = 510 },
    { inputId = "zhuan_zhu_cao", inputCount = 10, outputId = "potion_foc_xl",  alchemyLevel = 400, fuelCost = 510,  commissionCost = 850 },
    { inputId = "zhuan_zhu_cao", inputCount = 15, outputId = "potion_foc_xxl", alchemyLevel = 450, fuelCost = 765,  commissionCost = 1275 },

    -- ── 敏捷药剂（绿葵系列）──
    { inputId = "min_jie_cao", inputCount = 6,  outputId = "potion_agi_l",   alchemyLevel = 300, fuelCost = 324,  commissionCost = 540 },
    { inputId = "min_jie_cao", inputCount = 10, outputId = "potion_agi_xl",  alchemyLevel = 400, fuelCost = 540,  commissionCost = 900 },
    { inputId = "min_jie_cao", inputCount = 15, outputId = "potion_agi_xxl", alchemyLevel = 475, fuelCost = 810,  commissionCost = 1350 },

    -- ── 体质药剂（黑号系列）──
    { inputId = "ti_zhi_cao", inputCount = 10, outputId = "potion_con_xl",  alchemyLevel = 400, fuelCost = 570,  commissionCost = 950 },
    { inputId = "ti_zhi_cao", inputCount = 15, outputId = "potion_con_xxl", alchemyLevel = 475, fuelCost = 855,  commissionCost = 1425 },

    -- ── 力量药剂（赤冠花系列）──
    { inputId = "li_liang_cao", inputCount = 10, outputId = "potion_str_xl",  alchemyLevel = 400, fuelCost = 1500, commissionCost = 2500 },
    { inputId = "li_liang_cao", inputCount = 15, outputId = "potion_str_xxl", alchemyLevel = 475, fuelCost = 2250, commissionCost = 3750 },

    -- ── 意念药剂（银月花系列）──
    { inputId = "yi_nian_cao", inputCount = 10, outputId = "potion_wil_xl",  alchemyLevel = 400, fuelCost = 1800, commissionCost = 3000 },
    { inputId = "yi_nian_cao", inputCount = 15, outputId = "potion_wil_xxl", alchemyLevel = 475, fuelCost = 2700, commissionCost = 4500 },

    -- ── 幸运药剂（四叶草系列）──
    { inputId = "si_ye_cao", inputCount = 10, outputId = "potion_luk_xl",  alchemyLevel = 400, fuelCost = 2100, commissionCost = 3500 },
    { inputId = "si_ye_cao", inputCount = 15, outputId = "potion_luk_xxl", alchemyLevel = 475, fuelCost = 3150, commissionCost = 5250 },
    -- ── 魅力药剂（粉色铃兰系列）──
    { inputId = "xing_yun_cao", inputCount = 10, outputId = "potion_cha_xl",  alchemyLevel = 400, fuelCost = 2100, commissionCost = 3500 },
    { inputId = "xing_yun_cao", inputCount = 15, outputId = "potion_cha_xxl", alchemyLevel = 475, fuelCost = 3150, commissionCost = 5250 },

    -- ── 抗性药剂（魔力菇系列）──
    { inputId = "huo_kang_cao",    inputCount = 3, outputId = "potion_fire_res",    alchemyLevel = 475, fuelCost = 4500,  commissionCost = 7500 },
    { inputId = "bing_kang_cao",   inputCount = 3, outputId = "potion_ice_res",     alchemyLevel = 475, fuelCost = 4950,  commissionCost = 8250 },
    { inputId = "lei_kang_cao",    inputCount = 3, outputId = "potion_thunder_res", alchemyLevel = 475, fuelCost = 5400,  commissionCost = 9000 },
    { inputId = "zi_ran_kang_cao", inputCount = 3, outputId = "potion_nature_res",  alchemyLevel = 475, fuelCost = 5850,  commissionCost = 9750 },
    { inputId = "an_kang_cao",     inputCount = 3, outputId = "potion_dark_res",    alchemyLevel = 475, fuelCost = 6300,  commissionCost = 10500 },
    { inputId = "sheng_kang_cao",  inputCount = 3, outputId = "potion_holy_res",    alchemyLevel = 475, fuelCost = 6300,  commissionCost = 10500 },

    -- ── 增幅药剂（魔力菇系列）──
    { inputId = "huo_kang_cao",    inputCount = 5, outputId = "potion_fire_amp",    alchemyLevel = 500, fuelCost = 7500,  commissionCost = 12500 },
    { inputId = "bing_kang_cao",   inputCount = 5, outputId = "potion_ice_amp",     alchemyLevel = 500, fuelCost = 8250,  commissionCost = 13750 },
    { inputId = "lei_kang_cao",    inputCount = 5, outputId = "potion_thunder_amp", alchemyLevel = 500, fuelCost = 9000,  commissionCost = 15000 },
    { inputId = "sheng_kang_cao",  inputCount = 5, outputId = "potion_holy_amp",    alchemyLevel = 500, fuelCost = 10500, commissionCost = 17500 },
}

--- 执行炼金：消耗N个草药(由recipe.inputCount决定) + 金币（燃料费+委托加工费），产出1个药剂，获得炼金经验
---@param recipeIdx number 配方索引（1-based）
---@return boolean success, string msg
function M.doAlchemy(recipeIdx)
    local recipe = M.ALCHEMY_RECIPES[recipeIdx]
    if not recipe then return false, "无效配方" end

    local inputTpl = M.itemTemplates[recipe.inputId]
    if not inputTpl then return false, "物品数据异常" end

    local outputTpl = M.itemTemplates[recipe.outputId]
    if not outputTpl then return false, "产出物数据异常" end

    -- 计算炼金等级差与失败率
    local playerHLv = M.getLifeSkillHiddenLevel("alchemy")
    local levelDeficit = math.max(0, recipe.alchemyLevel - playerHLv)
    local failRate = math.min(levelDeficit * 0.04, 1.0)
    local successRate = 1.0 - failRate

    -- 检查背包是否有足够草药
    local needCount = recipe.inputCount or 1
    local haveCount = M.countInventoryItem(recipe.inputId)
    if haveCount < needCount then return false, "缺少 " .. inputTpl.name .. "（需要" .. needCount .. "个，当前" .. haveCount .. "个）" end

    -- 使用配方中的固定费用（家用炼金台免委托费；莉娜伴侣免委托费）
    local fuelCost = recipe.fuelCost or 0
    local partnerAlchMul = M.getPartnerDiscount("alchemy_commission")
    local commCost = M.homeAlchemyMode and 0 or math.ceil((recipe.commissionCost or 0) * partnerAlchMul)
    local totalCost = fuelCost + commCost
    if M.gold < totalCost then
        return false, "金币不足（需 " .. totalCost .. " G）"
    end

    -- 检查产出物能否放入背包（堆叠或空位）
    local canStack = false
    local hasEmpty = false
    local outputStackable = (outputTpl.consumable ~= nil or outputTpl.category == "材料") and outputTpl.slot == nil
    for i = 1, M.bagSlots do
        local inv = M.inventory[i]
        if not inv then
            hasEmpty = true; break
        elseif outputStackable and inv.templateId == recipe.outputId and inv.stackable and inv.quantity < (M.STACK_MAX or 99) then
            canStack = true; break
        end
    end
    -- 扣除草药后是否会空出格子
    local willFreeSlot = (haveCount <= needCount)
    if not canStack and not hasEmpty and not willFreeSlot then
        return false, "背包已满"
    end

    -- 执行：扣草药、扣金币
    M.removeInventoryItem(recipe.inputId, needCount)
    M.gold = M.gold - totalCost

    local lifeSkillId = "alchemy"

    -- 炼金成功/失败判定
    local roll = math.random()
    if roll >= successRate then
        local pct = math.floor(successRate * 100 + 0.5)
        return false, "炼金失败！(成功率" .. pct .. "%) 损失了 " .. needCount .. "个" .. inputTpl.name .. " 和 " .. totalCost .. " G"
    end

    -- 大成功/特大成功判定
    local critMul, critType = M.rollLifeSkillCrit(lifeSkillId)

    -- 产出物放入背包
    local outCount = (recipe.outputCount or 1) * critMul
    local added = M.addToInventory(recipe.outputId, outCount)
    if not added then return false, "背包已满" end

    -- 炼金经验
    local diff = playerHLv - recipe.alchemyLevel
    local expGain = 0
    if successRate < 0.50 then
        expGain = 2
    elseif diff < 0 then
        expGain = 1
    elseif diff <= 25 then
        expGain = 1
    elseif diff <= 40 then
        if math.random() <= 0.5 then expGain = 1 end
    elseif diff <= 50 then
        if math.random() <= 0.2 then expGain = 1 end
    end

    local tierUpMsg = nil
    if expGain > 0 then
        local curExp = (M.lifeSkillExp[lifeSkillId] or 0) + expGain
        local curTier = M.lifeSkillTiers[lifeSkillId] or 1
        if curExp >= M.LIFE_SKILL_MAX_LEVEL and curTier < M.LIFE_SKILL_MAX_TIER then
            curExp = curExp - M.LIFE_SKILL_MAX_LEVEL
            curTier = curTier + 1
            M.lifeSkillTiers[lifeSkillId] = curTier
            local tierDef = M.LIFE_SKILL_TIERS[curTier]
            tierUpMsg = "炼金升阶: " .. tierDef.name
        elseif curTier >= M.LIFE_SKILL_MAX_TIER then
            curExp = math.min(curExp, M.LIFE_SKILL_MAX_LEVEL)
        end
        M.lifeSkillExp[lifeSkillId] = curExp
    end
    local critLabel = critType == "super" and "★特大成功★ " or (critType == "great" and "★大成功★ " or "")
    local countStr = outCount > 1 and (" ×" .. outCount) or ""
    local msg = critLabel .. "炼金成功: " .. outputTpl.name .. countStr
    if expGain > 0 then msg = msg .. "  炼金经验+" .. expGain end
    if tierUpMsg then msg = msg .. "  " .. tierUpMsg end
    return true, msg
end

-- ====================================================================
-- 烹饪配方表：多种材料组合产出食物
-- cookingLevel 对应生活技能隐藏等级 = (tier-1)*100 + exp
-- ====================================================================
M.cookingBtnRects = {}
M.cookingIconRects = {}

M.ANY_RAW_MEAT_IDS = { "raw_chicken", "raw_wolf", "raw_pork", "raw_turtle", "raw_lion" }

M.COOKING_RECIPES = {
    -- 1. 苹果汁（=酒馆同款 food_apple_juice）
    { inputs = { {"food_apple", 1} }, outputId = "food_apple_juice", cookingLevel = 1, fuelCost = 5, commissionCost = 10 },
    -- 2. 史莱姆果冻
    { inputs = { {"slime_crystal", 1}, {"sugar", 1} }, outputId = "cook_slime_jelly", cookingLevel = 25, fuelCost = 5, commissionCost = 10 },
    -- 3. 苹果派（=酒馆同款 food_apple_pie）
    { inputs = { {"food_apple", 1}, {"wheat_flour", 1} }, outputId = "food_apple_pie", cookingLevel = 50, fuelCost = 5, commissionCost = 10 },
    -- 4. 土豆配青慈烤鸡（=酒馆同款 food_roast_chicken）
    { inputs = { {"potato", 1}, {"raw_chicken", 1}, {"qingcicao", 1} }, outputId = "food_roast_chicken", cookingLevel = 75, fuelCost = 5, commissionCost = 10 },
    -- 5. 蝙蝠翅炸串
    { inputs = { {"bat_wing", 1}, {"salt", 1} }, outputId = "cook_bat_skewer", cookingLevel = 100, fuelCost = 5, commissionCost = 10 },
    -- 6. 蜂蜜烤狼肋排（=酒馆同款 food_honey_ribs）
    { inputs = { {"honey", 1}, {"raw_wolf", 1} }, outputId = "food_honey_ribs", cookingLevel = 125, fuelCost = 5, commissionCost = 10 },
    -- 7. 盐烤肉（任意生肉）
    { inputs = { {"any_raw_meat", 1}, {"salt", 1} }, outputId = "cook_salt_meat", cookingLevel = 150, fuelCost = 5, commissionCost = 10, anyRawMeat = true },
    -- 8. 圣百合炒肉
    { inputs = { {"raw_pork", 1}, {"jian_gu_cao", 1}, {"salt", 1} }, outputId = "cook_lily_stir_fry", cookingLevel = 175, fuelCost = 5, commissionCost = 10 },
    -- 9. 紫鸢露
    { inputs = { {"dew_essence", 1}, {"ziyan", 1}, {"sugar", 1} }, outputId = "cook_violet_dew", cookingLevel = 200, fuelCost = 5, commissionCost = 10 },
    -- 10. 史莱姆黑果冻
    { inputs = { {"dark_slime_crystal", 1}, {"sugar", 1} }, outputId = "cook_dark_slime_jelly", cookingLevel = 225, fuelCost = 5, commissionCost = 10 },
    -- 11. 炒什锦蔬菜
    { inputs = { {"min_jie_cao", 1}, {"jian_gu_cao", 1}, {"salt", 1} }, outputId = "cook_veggie_mix", cookingLevel = 250, fuelCost = 5, commissionCost = 10 },
    -- 12. 蒸熊掌
    { inputs = { {"bear_paw", 1}, {"salt", 1}, {"honey", 1} }, outputId = "cook_steamed_paw", cookingLevel = 275, fuelCost = 5, commissionCost = 10 },
    -- 13. 星辰果冻
    { inputs = { {"dark_star_crystal", 1}, {"sugar", 1} }, outputId = "cook_star_jelly", cookingLevel = 300, fuelCost = 5, commissionCost = 10 },
    -- 14. 岩龟肉汤
    { inputs = { {"raw_turtle", 1}, {"salt", 1} }, outputId = "cook_turtle_soup", cookingLevel = 325, fuelCost = 5, commissionCost = 10 },
    -- 15. "星空"
    { inputs = { {"yi_nian_cao", 1}, {"mo_kang_cao", 1}, {"zhi_hui_cao", 1}, {"salt", 1} }, outputId = "cook_starry_sky", cookingLevel = 350, fuelCost = 5, commissionCost = 10 },
    -- 16. 幸运猪肉串
    { inputs = { {"raw_pork", 1}, {"xing_yun_cao", 1}, {"salt", 1} }, outputId = "cook_lucky_skewer", cookingLevel = 375, fuelCost = 5, commissionCost = 10 },
    -- 17. 星云果冻
    { inputs = { {"dark_nebula_crystal", 1}, {"sugar", 1} }, outputId = "cook_nebula_jelly", cookingLevel = 400, fuelCost = 5, commissionCost = 10 },
    -- 18. 章鱼汤
    { inputs = { {"octopus_tentacle", 1}, {"salt", 1}, {"ti_zhi_cao", 1} }, outputId = "cook_octopus_soup", cookingLevel = 425, fuelCost = 5, commissionCost = 10 },
    -- 19. 海陆空盛宴
    { inputs = { {"raw_chicken", 1}, {"raw_pork", 1}, {"raw_wolf", 1}, {"octopus_tentacle", 1}, {"salt", 1} }, outputId = "cook_land_sea_feast", cookingLevel = 450, fuelCost = 5, commissionCost = 10 },
    -- 20. 宇宙果冻
    { inputs = { {"dark_cosmos_crystal", 1}, {"sugar", 1}, {"an_kang_cao", 1} }, outputId = "cook_cosmos_jelly", cookingLevel = 475, fuelCost = 5, commissionCost = 10 },
    -- 21. 炙烤狮肉
    { inputs = { {"raw_lion", 1}, {"salt", 1}, {"li_liang_cao", 1} }, outputId = "cook_roast_lion", cookingLevel = 475, fuelCost = 5, commissionCost = 10 },
    -- 22. 火焰圣菇汤
    { inputs = { {"huo_kang_cao", 1}, {"salt", 1}, {"yi_nian_cao", 1} }, outputId = "cook_fire_mushroom_soup", cookingLevel = 475, fuelCost = 5, commissionCost = 10 },
    -- 23. 寒冰圣菇汤
    { inputs = { {"bing_kang_cao", 1}, {"salt", 1}, {"yi_nian_cao", 1} }, outputId = "cook_ice_mushroom_soup", cookingLevel = 475, fuelCost = 5, commissionCost = 10 },
    -- 24. 雷电圣菇汤
    { inputs = { {"lei_kang_cao", 1}, {"salt", 1}, {"yi_nian_cao", 1} }, outputId = "cook_thunder_mushroom_soup", cookingLevel = 475, fuelCost = 5, commissionCost = 10 },
    -- 25. 神圣菇汤
    { inputs = { {"sheng_kang_cao", 1}, {"salt", 1}, {"yi_nian_cao", 1} }, outputId = "cook_holy_mushroom_soup", cookingLevel = 475, fuelCost = 5, commissionCost = 10 },
}

--- 执行烹饪：消耗多种材料 + 金币（燃料费+委托加工费），产出食物，获得烹饪经验
---@param recipeIdx number 配方索引（1-based）
---@return boolean success, string msg
function M.doCooking(recipeIdx)
    local recipe = M.COOKING_RECIPES[recipeIdx]
    if not recipe then return false, "无效配方" end

    local outputTpl = M.itemTemplates[recipe.outputId]
    if not outputTpl then return false, "产出物数据异常" end

    -- 计算烹饪等级差与失败率
    local playerHLv = M.getLifeSkillHiddenLevel("cooking")
    local levelDeficit = math.max(0, recipe.cookingLevel - playerHLv)
    local failRate = math.min(levelDeficit * 0.04, 1.0)
    local successRate = 1.0 - failRate

    -- 解析材料需求（处理 any_raw_meat 特殊情况）
    local resolvedInputs = {}
    for _, inp in ipairs(recipe.inputs) do
        local matId = inp[1]
        local matCount = inp[2]
        if matId == "any_raw_meat" then
            -- 自动选择持有数量最多的生肉
            local bestId, bestCount = nil, 0
            for _, mid in ipairs(M.ANY_RAW_MEAT_IDS) do
                local c = M.countInventoryItem(mid)
                if c > bestCount then bestId, bestCount = mid, c end
            end
            if not bestId then return false, "没有任何生肉" end
            resolvedInputs[#resolvedInputs + 1] = { id = bestId, count = matCount }
        else
            resolvedInputs[#resolvedInputs + 1] = { id = matId, count = matCount }
        end
    end

    -- 检查所有材料是否足够
    for _, ri in ipairs(resolvedInputs) do
        local tpl = M.itemTemplates[ri.id]
        if not tpl then return false, "物品数据异常" end
        local have = M.countInventoryItem(ri.id)
        if have < ri.count then
            return false, "缺少 " .. tpl.name .. "（需要" .. ri.count .. "个，当前" .. have .. "个）"
        end
    end

    -- 检查金币
    -- 家用灶台免委托费
    local fuelCost = recipe.fuelCost or 0
    local commCost = M.homeCookingMode and 0 or (recipe.commissionCost or 0)
    local totalCost = fuelCost + commCost
    if M.gold < totalCost then
        return false, "金币不足（需 " .. totalCost .. " G）"
    end

    -- 检查背包空间
    local canStack = false
    local hasEmpty = false
    local outputStackable = (outputTpl.consumable ~= nil or outputTpl.category == "材料") and outputTpl.slot == nil
    for i = 1, M.bagSlots do
        local inv = M.inventory[i]
        if not inv then
            hasEmpty = true; break
        elseif outputStackable and inv.templateId == recipe.outputId and inv.stackable and inv.quantity < (M.STACK_MAX or 99) then
            canStack = true; break
        end
    end
    -- 扣除材料后是否会空出格子
    local willFreeSlot = false
    for _, ri in ipairs(resolvedInputs) do
        local have = M.countInventoryItem(ri.id)
        if have <= ri.count then willFreeSlot = true; break end
    end
    if not canStack and not hasEmpty and not willFreeSlot then
        return false, "背包已满"
    end

    -- 执行：扣材料、扣金币
    for _, ri in ipairs(resolvedInputs) do
        M.removeInventoryItem(ri.id, ri.count)
    end
    M.gold = M.gold - totalCost

    local lifeSkillId = "cooking"

    -- 烹饪成功/失败判定
    local roll = math.random()
    if roll >= successRate then
        local pct = math.floor(successRate * 100 + 0.5)
        local lostStr = ""
        for idx, ri in ipairs(resolvedInputs) do
            local tpl = M.itemTemplates[ri.id]
            if idx > 1 then lostStr = lostStr .. "、" end
            lostStr = lostStr .. ri.count .. "个" .. (tpl and tpl.name or ri.id)
        end
        -- 烹饪失败产出"奇怪焦物"
        M.addToInventory("cook_burnt", 1)
        return false, "烹饪失败！(成功率" .. pct .. "%) 损失了 " .. lostStr .. " 和 " .. totalCost .. " G，获得了奇怪焦物"
    end

    -- 大成功/特大成功判定
    local critMul, critType = M.rollLifeSkillCrit(lifeSkillId)

    -- 产出放入背包
    local outCount = (recipe.outputCount or 1) * critMul
    local added = M.addToInventory(recipe.outputId, outCount)
    if not added then return false, "背包已满" end

    -- 烹饪经验（与炼金相同逻辑）
    local diff = playerHLv - recipe.cookingLevel
    local expGain = 0
    if successRate < 0.50 then
        expGain = 2
    elseif diff < 0 then
        expGain = 1
    elseif diff <= 25 then
        expGain = 1
    elseif diff <= 40 then
        if math.random() <= 0.5 then expGain = 1 end
    elseif diff <= 50 then
        if math.random() <= 0.2 then expGain = 1 end
    end

    local tierUpMsg = nil
    if expGain > 0 then
        local curExp = (M.lifeSkillExp[lifeSkillId] or 0) + expGain
        local curTier = M.lifeSkillTiers[lifeSkillId] or 1
        if curExp >= M.LIFE_SKILL_MAX_LEVEL and curTier < M.LIFE_SKILL_MAX_TIER then
            curExp = curExp - M.LIFE_SKILL_MAX_LEVEL
            curTier = curTier + 1
            M.lifeSkillTiers[lifeSkillId] = curTier
            local tierDef = M.LIFE_SKILL_TIERS[curTier]
            tierUpMsg = "烹饪升阶: " .. tierDef.name
        elseif curTier >= M.LIFE_SKILL_MAX_TIER then
            curExp = math.min(curExp, M.LIFE_SKILL_MAX_LEVEL)
        end
        M.lifeSkillExp[lifeSkillId] = curExp
    end
    local critLabel = critType == "super" and "★特大成功★ " or (critType == "great" and "★大成功★ " or "")
    local countStr = outCount > 1 and (" ×" .. outCount) or ""
    local msg = critLabel .. "烹饪成功: " .. outputTpl.name .. countStr
    if expGain > 0 then msg = msg .. "  烹饪经验+" .. expGain end
    if tierUpMsg then msg = msg .. "  " .. tierUpMsg end
    return true, msg
end

--- 执行宝石镶嵌：将背包中的宝石镶入装备的宝石槽
---@param gemSlotIdx number 装备宝石槽索引（1-based）
---@param gemBagSlot number 背包中宝石物品的槽位索引
---@return boolean success, string msg
function M.doSocket(gemSlotIdx, gemBagSlot)
    local equip = M.socketEquipItem
    if not equip then return false, "请先放入装备" end
    if not equip.gemSlots or #equip.gemSlots == 0 then return false, "该装备没有宝石槽" end
    if not gemSlotIdx or gemSlotIdx < 1 or gemSlotIdx > #equip.gemSlots then return false, "无效的宝石槽" end

    local slot = equip.gemSlots[gemSlotIdx]
    if slot.gemId then return false, "该宝石槽已被占用" end

    -- 检查背包宝石
    if not gemBagSlot then return false, "请选择一颗宝石" end
    local gemItem = M.inventory[gemBagSlot]
    if not gemItem then return false, "宝石不存在" end
    local gemTpl = M.itemTemplates[gemItem.templateId]
    if not gemTpl or not gemTpl.gemEffect then return false, "所选物品不是宝石" end

    -- 镶嵌费用：宝石价值 × 50%（家用手工桌打3折；朱莉伴侣折扣）
    local gemValue = gemTpl.value or 0
    local baseCost = math.ceil(gemValue * 0.50)
    local partnerMul = M.getPartnerDiscount("socket")
    local cost = M.homeSocketMode and math.ceil(baseCost * 0.3) or math.ceil(baseCost * partnerMul)
    if M.gold < cost then return false, "金币不足（需 " .. cost .. " G）" end

    -- 执行镶嵌：从背包扣除宝石，写入宝石槽
    if gemItem.quantity and gemItem.quantity > 1 then
        gemItem.quantity = gemItem.quantity - 1
    else
        M.inventory[gemBagSlot] = nil
    end
    M.gold = M.gold - cost

    slot.gemId = gemItem.templateId
    -- 优先使用实例级 gemEffect（如朱莉面纱的随机主属性），否则用模板
    local sourceGemEffect = gemItem.gemEffect or gemTpl.gemEffect
    slot.gemEffect = {}
    for k, v in pairs(sourceGemEffect) do
        slot.gemEffect[k] = v
    end
    -- 宝石携带深渊词缀时，一并写入宝石槽（如"朱莉"的面纱）
    if gemItem.abyssAffix then
        slot.abyssAffix = {
            id = gemItem.abyssAffix.id,
            name = gemItem.abyssAffix.name,
            desc = gemItem.abyssAffix.desc,
            mechanic = gemItem.abyssAffix.mechanic,
        }
    end

    -- 清除选中状态
    M.socketSelectedGemSlot = nil
    M.socketSelectedGemBag = nil

    return true, "镶嵌成功: " .. gemTpl.name
end

--- 拆卸宝石：从装备宝石槽中移除宝石，归还到背包
---@param gemSlotIdx number 装备宝石槽索引（1-based）
---@return boolean success, string msg
function M.removeGemFromSocket(gemSlotIdx)
    local equip = M.socketEquipItem
    if not equip then return false, "请先放入装备" end
    if not equip.gemSlots or #equip.gemSlots == 0 then return false, "该装备没有宝石槽" end
    if not gemSlotIdx or gemSlotIdx < 1 or gemSlotIdx > #equip.gemSlots then return false, "无效的宝石槽" end

    local slot = equip.gemSlots[gemSlotIdx]
    if not slot.gemId then return false, "该宝石槽是空的" end

    -- 拆卸费用：宝石价值 × 100%（家用手工桌打3折）
    local gemTpl = M.itemTemplates[slot.gemId]
    local gemValue = gemTpl and gemTpl.value or 0
    local partnerMul = M.getPartnerDiscount("socket")
    local cost = M.homeSocketMode and math.ceil(gemValue * 0.3) or math.ceil(gemValue * partnerMul)
    if M.gold < cost then return false, "金币不足（需 " .. cost .. " G）" end

    -- 尝试归还宝石到背包（直接拿返回的 addedItem 引用，避免用索引查找时误找到包里的同名旧宝石）
    local added, _, addedItem = M.addToInventory(slot.gemId, 1)
    if not added then return false, "背包已满，无法归还宝石" end

    M.gold = M.gold - cost

    -- 宝石槽携带深渊词缀或实例属性时，写回到刚归还的宝石实例上（如"朱莉"的面纱）
    if addedItem and (slot.abyssAffix or (slot.gemEffect and next(slot.gemEffect))) then
        if slot.abyssAffix then
            addedItem.abyssAffix = {
                id = slot.abyssAffix.id,
                name = slot.abyssAffix.name,
                desc = slot.abyssAffix.desc,
                mechanic = slot.abyssAffix.mechanic,
            }
        end
        -- 恢复实例级 gemEffect（如朱莉面纱的随机主属性）
        if slot.gemEffect and next(slot.gemEffect) then
            addedItem.gemEffect = {}
            for k, v in pairs(slot.gemEffect) do
                addedItem.gemEffect[k] = v
            end
        end
    end

    -- 清空宝石槽
    local gemName = gemTpl and gemTpl.name or slot.gemId
    slot.gemId = nil
    slot.gemEffect = nil
    slot.abyssAffix = nil

    M.socketSelectedGemSlot = nil
    M.socketSelectedGemBag = nil

    return true, "拆卸成功: " .. gemName
end

--- 为无宝石槽的装备开凿一个宝石槽，消耗1个开孔工具
---@return boolean success
---@return string msg
function M.drillGemSlot()
    local equip = M.socketEquipItem
    if not equip then return false, "请先放入装备" end
    if equip.gemSlots and #equip.gemSlots > 0 then return false, "该装备已有宝石槽" end

    local toolCount = M.countInventoryItem("socket_drill_tool")
    if toolCount < 1 then return false, "没有开孔工具" end

    M.removeInventoryItem("socket_drill_tool", 1)
    equip.gemSlots = { {} }  -- 添加1个空宝石槽

    return true, "开槽成功！装备获得了一个宝石槽"
end

--- 获取指定T级装备的精炼槽上限
function M.getMaxRefineSlots(tier)
    local chances = M.REFINE_SLOT_CHANCES[tier]
    if not chances then return 0 end
    local maxSlots = 0
    for i = 1, #chances do
        if chances[i] > 0 then maxSlots = i - 1 end
    end
    return maxSlots
end

--- 使用精炼槽雕刻工具为装备开凿一个精炼槽
function M.drillRefineSlot(equipOverride)
    local equip = equipOverride or M.refineSlotItem
    if not equip then return false, "请先放入装备" end

    local tier = M.getItemTier(equip)
    local maxSlots = M.getMaxRefineSlots(tier)
    if maxSlots <= 0 then return false, "该装备T级过低，无法拥有精炼槽" end

    local curSlots = equip.refineSlots and #equip.refineSlots or 0
    if curSlots >= maxSlots then return false, "精炼槽已达T" .. tier .. "上限(" .. maxSlots .. "槽)" end

    local toolCount = M.countInventoryItem("refine_slot_tool")
    if toolCount < 1 then return false, "没有精炼槽雕刻工具" end

    M.removeInventoryItem("refine_slot_tool", 1)
    if not equip.refineSlots then equip.refineSlots = {} end
    table.insert(equip.refineSlots, {})  -- 添加1个空精炼槽

    return true, "开槽成功！装备获得了一个精炼槽 (" .. (#equip.refineSlots) .. "/" .. maxSlots .. ")"
end

-- 精炼模式（独立面板）
M.refineMode = false          -- 是否处于精炼模式
M.refineResult = nil          -- 最近一次精炼/重铸结果 { success, msg, timer }
M.refineSlotItem = nil        -- 精炼槽中放入的物品引用
M.refineSlotSource = nil      -- 来源标识: "equip" 或 "bag"
M.refineSlotSourceId = nil    -- 来源装备槽id(string) 或 背包索引(number)
M.refineDropRect = nil        -- 精炼放置槽的屏幕区域 {x,y,w,h}
M.refineCloseRect = nil       -- 精炼面板关闭按钮区域
M.refineDrillBtnRect = nil    -- 精炼开槽按钮区域
M.refineSlotBtnRects = {}     -- 每个精炼槽位的按钮区域 [{x,y,w,h}, ...]

--- 切换职业（测试用）
---@param classId string 职业ID（warrior/hunter/assassin/mage/priest）
function M.changeClass(classId)
    local classDef = M.PLAYER_DEFS[classId]
    if not classDef then return end
    local p = M.player
    if not p then return end

    -- 更新当前职业
    M.currentClass = classId
    M.PLAYER_DEF = classDef
    M.SKILL_TREE_LAYOUT = M.CLASS_SKILL_TREE_LAYOUTS[classId]

    -- 更新玩家名称和颜色
    p.name = classDef.name
    p.color = classDef.color

    -- 重置技能（不同职业技能树不同，必须清空）
    M.skillLevels = {}
    M.skillPoints = p.level  -- 1级起就有1点，每级+1，100级=100点
    M.activeSkills = {}
    M.skillCooldowns = {}
    M.chantStages = 0
    M.chantStagesMax = 0
    M.chanting = nil

    -- 重算属性
    M.recalcStats(p)
    if p.hp > p.maxHp then p.hp = p.maxHp end
    if p.mp > p.maxMp then p.mp = p.maxMp end
end

-- ============================================================
-- recalcStats 辅助函数
-- ============================================================

--- 汇总技能被动加成（仅对玩家生效）
---@return table sb 固定值加成
---@return table sbPct 百分比加成
local function collectSkillPassives()
    local sb = {}
    local sbPct = {}
    local weaponR_for_tag = M.equipment and M.equipment["weapon_r"]
    local weaponL_for_tag = M.equipment and M.equipment["weapon_l"]
    local curWeaponTagForSkill = weaponR_for_tag and weaponR_for_tag.weaponTag
    -- 右手无有效武器标签时，检查左手（如单持匕首）
    if not curWeaponTagForSkill and weaponL_for_tag and weaponL_for_tag.weaponTag then
        curWeaponTagForSkill = weaponL_for_tag.weaponTag
    end

    for skillId, def in pairs(M.SKILL_DEFS) do
        if def.type == "passive" and def.bonus and (M.skillLevels[skillId] or 0) > 0
           and (not def.reqWeaponTag or curWeaponTagForSkill == def.reqWeaponTag) then
            local key = def.bonus
            local slv = M.skillLevels[skillId]
            if def.bonusPct then
                local pct = def.bonusPerLv * slv
                if slv >= M.SKILL_MAX_LEVEL and def.bonusMaxLvExtra then
                    pct = pct + def.bonusMaxLvExtra
                end
                sbPct[key] = (sbPct[key] or 0) + pct
            else
                sb[key] = (sb[key] or 0) + def.bonusPerLv * slv
            end
        end
    end
    return sb, sbPct
end

--- 计算基础值面板（仅含点数+等级成长，不含装备/套装/技能被动）
local function calculateBaseStats(unit, s, isHunter, lvAtk, lvMAtk, lvCrit, lvMCrit, lvHit, lvHp, lvMp, lvDef, lvMDef)
    local bStr, bAgi, bCon, bWis, bFoc = s.str, s.agi, s.con, s.wis, s.foc
    local bPer, bWil = (s.per or 0), (s.wil or 0)
    local bLuk = (s.luk or 0)
    unit.baseStats = {
        atk = isHunter
            and (10 + math.floor(bStr * 1.5) + math.floor(bFoc * 2.5) + math.floor(lvAtk))
            or  (10 + bStr * 3 + bFoc + math.floor(lvAtk)),
        critVal = math.floor(bStr * 1.5) + lvCrit,
        critDmg = 25 + bLuk * 1.25,
        avoidCrit = 0 + bLuk,
        hit = 1 + bFoc + bWil + lvHit,
        atkSpeed = math.floor(bAgi * 0.5),
        mAtk = 10 + math.floor(bWis * 3.5) + math.floor(lvMAtk),
        maxHp = 30 + bCon * 9 + lvHp,
        maxMp = 20 + bWis * 5 + lvMp,
        def = 10 + bCon * 4 + lvDef,
        mDef = 10 + bPer * 4 + lvMDef,
        dodge = 0 + bAgi,
        hpRegen = 0 + bCon * 0.5,
        mpRegen = 0 + bPer * 0.5,
        moveRange = 2 + math.floor(bAgi / 50),
        rAtk = 5 + bFoc,
        mCritRate = math.floor(bPer * 1.5) + lvMCrit,
        mCritDmg = 25 + bLuk * 1.25,
        castSpeed = math.floor(bWil * 0.5),
        resFire = 0, resIce = 0, resElec = 0, resLight = 0, resDark = 0, resNature = 0,
    }
end

--- 条件被动加成（武器专精、野性、双持、满弓、静神、祝福buff等）
local function applyConditionalPassives(unit)
    unit.dmgPctBonus = 0
    unit.hitPctBonus = 0
    unit.atkSpdPctBonus = 0
    unit.defPctBonus = 0

    local condWeaponR = M.equipment and M.equipment["weapon_r"]
    local curWeaponTag = condWeaponR and condWeaponR.weaponTag
    local condWeaponL = M.equipment and M.equipment["weapon_l"]
    -- 右手无有效武器标签时，检查左手（如单持匕首）
    if not curWeaponTag and condWeaponL and condWeaponL.weaponTag then
        curWeaponTag = condWeaponL.weaponTag
    end
    -- 弓必须同时装备箭袋才视为装备弓，否则视为赤手空拳
    if curWeaponTag == "弓" and (not condWeaponL or condWeaponL.category ~= "箭袋") then
        curWeaponTag = nil
    end
    local hasShield = condWeaponL and condWeaponL.category == "盾牌"

    -- 武器/装备标签匹配的条件被动
    for skillId, def in pairs(M.SKILL_DEFS) do
        if def.type == "passive" and def.condTag and def.condBonus
           and (M.skillLevels[skillId] or 0) > 0 then
            local matched = (curWeaponTag == def.condTag)
                or (def.condTag == "盾" and hasShield)
            if matched then
                local slv = M.skillLevels[skillId]
                local cb = def.condBonus
                unit.dmgPctBonus = unit.dmgPctBonus + (cb.dmgPct or 0) * slv
                unit.hitPctBonus = unit.hitPctBonus + (cb.hitPct or 0) * slv
                unit.atkSpdPctBonus = (unit.atkSpdPctBonus or 0) + (cb.atkSpdPct or 0) * slv
                unit.defPctBonus = (unit.defPctBonus or 0) + (cb.defPct or 0) * slv
                if cb.hitFlat then
                    unit.hit = unit.hit + cb.hitFlat * slv
                end
                if cb.atkSpdFlat then
                    unit.atkSpeed = unit.atkSpeed + cb.atkSpdFlat * slv
                end
                if cb.critFlat then
                    unit.critVal = unit.critVal + cb.critFlat * slv
                end
                if cb.pCritDmgPct then
                    unit.critDmg = (unit.critDmg or 50) + cb.pCritDmgPct * slv
                end
            end
        end
    end

    -- 野性：猎人攻速+2/级（固定值）
    local wildLv = M.skillLevels["h_wild"] or 0
    if wildLv > 0 then
        local wDef = M.SKILL_DEFS["h_wild"]
        unit.atkSpeed = unit.atkSpeed + (wDef.wildAtkSpdFlatPerLv or 2) * wildLv
    end

    -- 双手持剑：仅装备一把单手剑时，攻速-10
    local dwLv = M.skillLevels["dual_wield"] or 0
    if dwLv > 0 and curWeaponTag == "单手剑" then
        local offhand = M.equipment and M.equipment["weapon_l"]
        if not offhand then
            local dwDef = M.SKILL_DEFS["dual_wield"]
            unit.atkSpeed = unit.atkSpeed - (dwDef.dualWieldAtkSpdPenalty or 10)
        end
    end

    -- 双持熟练/双持专精：攻速加成（仅双持匕首时生效）
    if M.isDualDagger() then
        for _, sid in ipairs({"a_dual_prof", "a_dual_master"}) do
            local slv = M.skillLevels[sid] or 0
            if slv > 0 then
                local sd = M.SKILL_DEFS[sid]
                if sd and sd.dualAtkSpdPerLv then
                    unit.atkSpeed = unit.atkSpeed + sd.dualAtkSpdPerLv * slv
                end
            end
        end
    end

    -- 满弓：攻速-20，伤害+2%/级（需要装备弓）
    local fdLv = M.skillLevels["h_full_draw"] or 0
    if fdLv > 0 and curWeaponTag == "弓" then
        local fdDef = M.SKILL_DEFS["h_full_draw"]
        unit.atkSpeed = unit.atkSpeed - (fdDef.fullDrawAtkSpdPenalty or 20)
        unit.dmgPctBonus = unit.dmgPctBonus + (fdDef.fullDrawDmgPctPerLv or 2) * fdLv
    end

    -- 静神buff：伤害+X%
    if M.focusBuffTurns > 0 then
        local fDef = M.SKILL_DEFS["h_shuttle"]
        local fLv = M.skillLevels["h_shuttle"] or 0
        if fDef and fLv > 0 then
            local pct = (fDef.focusDmgPctBase or 12) + (fDef.focusDmgPctPerLv or 2) * (fLv - 1)
            unit.dmgPctBonus = unit.dmgPctBonus + pct
            unit.atkSpeed = unit.atkSpeed + (fDef.focusAtkSpdPerLv or 2) * fLv
        end
    end

    -- 百分比乘算应用
    if unit.hitPctBonus > 0 then
        unit.hit = math.floor(unit.hit * (1 + unit.hitPctBonus / 100))
    end
    if (unit.atkSpdPctBonus or 0) > 0 then
        unit.atkSpeed = math.floor(unit.atkSpeed * (1 + unit.atkSpdPctBonus / 100))
    end
    unit.atkSpeed = math.max(0, math.floor(unit.atkSpeed))
    -- defPctBonus 延后到 unit.def 计算之后应用（见体质区域）

    -- 祝福buff加成
    if unit.conquerAtkPct and unit.conquerAtkPct > 0 and unit.conquerTurns and unit.conquerTurns > 0 then
        unit.atk  = math.floor(unit.atk  * (1 + unit.conquerAtkPct / 100))
    end
    -- 庇护祝福：技能版与装备版互斥，取等级高的生效（每级1%物防/魔防）
    do
        local skillPct = 0
        if unit.shelterDefPct and unit.shelterDefPct > 0 and unit.shelterTurns and unit.shelterTurns > 0 then
            skillPct = unit.shelterDefPct  -- 技能版：每级1%
        end
        local equipPct = (unit.shelterBlessing or 0) * 1  -- 装备版：每级1%
        local finalPct = math.max(skillPct, equipPct)
        if finalPct > 0 then
            unit.def = math.floor(unit.def * (1 + finalPct / 100))
            unit.mDef = math.floor(unit.mDef * (1 + finalPct / 100))
            unit.mdef = unit.mDef  -- 同步小写别名
        end
    end
    -- 圣泉祝福：技能版与装备版互斥，取等级高的生效（每级5%回复加成）—— 面板数值
    do
        local skillPct = 0
        if unit.holySpringRegenPct and unit.holySpringRegenPct > 0 and unit.holySpringTurns and unit.holySpringTurns > 0 then
            skillPct = unit.holySpringRegenPct
        end
        local equipPct = (unit.holySpringBlessing or 0) * 5
        local finalPct = math.max(skillPct, equipPct)
        if finalPct > 0 then
            unit.hpRegen = math.floor(unit.hpRegen * (1 + finalPct / 100))
            unit.mpRegen = math.floor(unit.mpRegen * (1 + finalPct / 100))
        end
    end
    if unit.miracleVal and unit.miracleVal > 0 and unit.miracleTurns and unit.miracleTurns > 0 then
        -- 暴击值、闪避值、命中值：百分比加成，至少每1%对应1点
        local critBase = unit.critVal or 0
        local critPctBonus = math.floor(critBase * unit.miracleVal / 100)
        unit.critVal = critBase + math.max(critPctBonus, unit.miracleVal)

        local dodgeBase = unit.dodge or 0
        local dodgePctBonus = math.floor(dodgeBase * unit.miracleVal / 100)
        unit.dodge = dodgeBase + math.max(dodgePctBonus, unit.miracleVal)

        local hitBase = unit.hit or 0
        local hitPctBonus = math.floor(hitBase * unit.miracleVal / 100)
        unit.hit = hitBase + math.max(hitPctBonus, unit.miracleVal)

        -- 魔法暴击值：同样的百分比加成逻辑
        local mCritBase = unit.mCritRate or 0
        local mCritPctBonus = math.floor(mCritBase * unit.miracleVal / 100)
        unit.mCritRate = mCritBase + math.max(mCritPctBonus, unit.miracleVal)

        -- 暴击伤害：物理和魔法都加成（2%/等级）
        local miracleCritDmg = unit.miracleVal * 2
        unit.critDmg = (unit.critDmg or 50) + miracleCritDmg
        unit.mCritDmg = (unit.mCritDmg or 25) + miracleCritDmg
    end
end

--- HP/MP 变化时按比例调整当前值
local function adjustCurrentHpMp(unit, oldMaxHp, oldMaxMp)
    if oldMaxHp > 0 and unit.hp then
        if unit.hp > 0 then
            local ratio = unit.hp / oldMaxHp
            unit.hp = math.max(1, math.floor(unit.maxHp * ratio))
        end
        -- hp <= 0: 保持死亡状态
    else
        unit.hp = unit.maxHp
    end

    if oldMaxMp > 0 and unit.mp then
        local ratio = unit.mp / oldMaxMp
        unit.mp = math.max(0, math.floor(unit.maxMp * ratio))
    else
        unit.mp = unit.maxMp
    end
end

function M.recalcStats(unit)
    local s = unit.stats
    local oldMaxHp = unit.maxHp or 0

    -- 汇总装备加成（仅对玩家生效）
    local eb = (unit == M.player) and M.getEquipBonus() or {}

    -- 汇总套装加成（仅对玩家生效）
    local setB = (unit == M.player) and M.getSetBonus() or {}

    -- 汇总技能被动加成（仅对玩家生效）
    local sb, sbPct = {}, {}
    if unit == M.player then
        sb, sbPct = collectSkillPassives()
    end

    -- 冒险者等级全属性加成（仅对玩家生效）
    local rankBonus = (unit == M.player) and M.getAdventurerRankBonus() or 0

    -- 勿忘我 BUFF 检查（永久效果或临时buff）
    local fmnBuff = 0
    local fmnHpRegen, fmnMpRegen = 0, 0
    if unit == M.player then
        local fmnActive = false
        if M.forgetMeNotPermanent then
            -- 永久效果：安吉莉娅最终任务完成后，效果永远存在
            fmnActive = true
        elseif M.forgetMeNotBuff then
            if M.forgetMeNotBuff.expireTime and M.weatherTime > M.forgetMeNotBuff.expireTime
               and M.forgetMeNotBuff.expireTime > 0 then
                M.forgetMeNotBuff = nil  -- 过期清除
            else
                fmnActive = true
            end
        end
        if fmnActive then
            local fmnLv = M.forgetMeNotLevel or 0
            fmnBuff = 1 + fmnLv       -- 力量+(1+lv), 专注+(1+lv), 智慧+(1+lv)
            fmnHpRegen = 1 + fmnLv    -- HP回复+(1+lv)
            fmnMpRegen = 1 + fmnLv    -- MP回复+(1+lv)
        end
    end

    -- 食物 BUFF 检查（过期则清除，单食物覆盖机制）
    local foodStr, foodFoc, foodWis = 0, 0, 0
    local foodCon, foodAgi, foodPer, foodWil, foodLuk = 0, 0, 0, 0, 0
    local foodHpRegen, foodMpRegen = 0, 0
    local foodPhysCrit, foodMagicCrit = 0, 0
    local foodFireDmgPct, foodIceDmgPct, foodThunderDmgPct, foodHolyDmgPct = 0, 0, 0, 0
    if unit == M.player and M.foodBuff then
        if M.foodBuff.expireTime and M.weatherTime > M.foodBuff.expireTime
           and M.foodBuff.expireTime > 0 then
            M.foodBuff = nil  -- 过期清除
        else
            local fb = M.foodBuff
            foodStr  = fb.str  or 0
            foodFoc  = fb.foc  or 0
            foodWis  = fb.wis  or 0
            foodCon  = fb.con  or 0
            foodAgi  = fb.agi  or 0
            foodPer  = fb.per  or 0
            foodWil  = fb.wil  or 0
            foodLuk  = fb.luk  or 0
            foodHpRegen   = fb.hpRegen   or 0
            foodMpRegen   = fb.mpRegen   or 0
            foodPhysCrit  = fb.physCrit  or 0
            foodMagicCrit = fb.magicCrit or 0
            foodFireDmgPct    = fb.fireDmgPct    or 0
            foodIceDmgPct     = fb.iceDmgPct     or 0
            foodThunderDmgPct = fb.thunderDmgPct or 0
            foodHolyDmgPct    = fb.holyDmgPct    or 0
        end
    end

    -- 药水 BUFF 检查（过期则清除，同类型覆盖机制）
    local pb = {}  -- 收集生效的药水 buff 值
    if unit == M.player and M.potionBuffs then
        for stat, buff in pairs(M.potionBuffs) do
            if buff.expireTime and M.weatherTime > buff.expireTime and buff.expireTime > 0 then
                M.potionBuffs[stat] = nil  -- 过期清除
            else
                pb[stat] = buff.amount or 0
            end
        end
    end

    -- 精神抖擞 BUFF 检查（过期则清除）
    local hugBuff = 0
    if unit == M.player and M.hugBuff then
        if M.hugBuff.expireTime and M.weatherTime > M.hugBuff.expireTime
           and M.hugBuff.expireTime > 0 then
            M.hugBuff = nil  -- 过期清除
        else
            hugBuff = 1  -- 全属性+1
        end
    end

    -- 有效属性 = 基础属性 + 装备 + 冒险者等级 + 勿忘我BUFF + 精神抖擞BUFF + 食物BUFF + 药水BUFF
    local str = math.max(1, s.str + (eb.str or 0) + (setB.str or 0) + rankBonus + fmnBuff + hugBuff + foodStr + (pb.buff_str or 0))
    local agi = math.max(1, s.agi + (eb.agi or 0) + rankBonus + hugBuff + foodAgi + (pb.buff_agi or 0))
    local con = math.max(1, s.con + (eb.con or 0) + rankBonus + hugBuff + foodCon + (pb.buff_con or 0))
    local wis = math.max(1, s.wis + (eb.wis or 0) + rankBonus + fmnBuff + hugBuff + foodWis + (pb.buff_wis or 0))
    local foc = math.max(1, s.foc + (eb.foc or 0) + rankBonus + fmnBuff + hugBuff + foodFoc + (pb.buff_foc or 0) + (unit._gazeFoc or 0))
    local per = math.max(1, (s.per or 0) + (eb.per or 0) + rankBonus + hugBuff + foodPer + (pb.buff_per or 0) + (unit._gazePer or 0))
    local wil = math.max(1, (s.wil or 0) + (eb.wil or 0) + rankBonus + hugBuff + foodWil + (pb.buff_wil or 0))
    local luk = math.max(1, (s.luk or 0) + (eb.luk or 0) + rankBonus + hugBuff + foodLuk + (pb.buff_luk or 0))
    local cha = math.max(0, (s.cha or 0) + (eb.cha or 0) + rankBonus + hugBuff + (pb.buff_cha or 0))

    -- 等级自然成长（level 1 无加成，每升1级按职业成长）
    local lv = math.max(0, (unit.level or 1) - 1)
    local isPhysClass = (unit.name == "战士" or unit.name == "猎人" or unit.name == "刺客")
    local isPriest = (unit.name == "牧师")  -- 牧师：物魔双修，物攻魔攻均+2/级
    local lvAtk   = (isPhysClass or isPriest) and (lv * 2) or (lv * 0.5)  -- 物攻: 物理系/牧师+2/级, 其他+0.5/级
    local lvMAtk  = (not isPhysClass or isPriest) and (lv * 2) or (lv * 0.5)  -- 魔攻: 魔法系/牧师+2/级, 物理系+0.5/级
    local lvCrit  = lv * 1   -- 物暴值 +1/级
    local lvHit   = lv * 1   -- 命中 +1/级
    local lvMCrit = lv * 1   -- 法暴值 +1/级
    local lvHp    = lv * 5   -- HP +5/级
    local lvMp    = lv * 2   -- MP +2/级
    local lvDef   = lv * 2   -- 物防 +2/级
    local lvMDef  = lv * 2   -- 魔防 +2/级

    -- 力量: +3物攻, +1.5物暴值（猎人: 专注+2物攻, 力量+1.5物攻）
    local isHunter = (unit.name == "猎人")
    local baseAtk = isHunter
        and (10 + math.floor(str * 1.5) + math.floor(foc * 2.5))
        or  (10 + str * 3 + foc)
    unit.atk        = baseAtk + math.floor(lvAtk) + (eb.atk or 0) + (sb.atk or 0) + (setB.atk or 0) + (pb.buff_atk or 0)
    if (sbPct.atk or 0) > 0 then
        local pctBonus = math.floor(unit.atk * sbPct.atk / 100)
        local minBonus = sbPct.atk  -- 至少每1%对应1点
        unit.atk = unit.atk + math.max(pctBonus, minBonus)
    end

    -- 双手持握：右手武器攻击力加成提高
    if unit == M.player then
        local dwLv2 = M.skillLevels["dual_wield"] or 0
        if dwLv2 > 0 then
            local wr2 = M.equipment and M.equipment["weapon_r"]
            local wl2 = M.equipment and M.equipment["weapon_l"]
            if wr2 and wr2.weaponTag == "单手剑" and not wl2 then
                -- 计算右手武器提供的攻击力（仅基础+强化）
                local weaponAtk = 0
                if wr2.effects and wr2.effects.atk then weaponAtk = weaponAtk + wr2.effects.atk end
                local enhLv2 = wr2.enhanceLevel or 0
                if enhLv2 > 0 then
                    local gain = M.getEnhanceGain(wr2, enhLv2)
                    if gain.atk then weaponAtk = weaponAtk + gain.atk end
                end
                local dwDef2 = M.SKILL_DEFS["dual_wield"]
                local bonusPct = (dwDef2.dualWieldWeaponAtkBonusBase or 75) + (dwLv2 - 1) * (dwDef2.dualWieldWeaponAtkBonusPerLv or 5)
                unit.atk = unit.atk + math.floor(weaponAtk * bonusPct / 100)
            end
        end
    end

    unit.critVal   = math.floor(str * 1.5) + lvCrit + (eb.critVal or 0) + (sb.critVal or 0) + (setB.critVal or 0) + foodPhysCrit
    if (sbPct.critVal or 0) > 0 then
        local pctBonus = math.floor(unit.critVal * sbPct.critVal / 100)
        local minBonus = sbPct.critVal  -- 至少每1%对应1点
        unit.critVal = unit.critVal + math.max(pctBonus, minBonus)
    end
    unit.critDmg    = 25             + luk * 1.25 + (eb.critDmg or 0) + (sb.critDmg or 0) + (setB.critDmg or 0)
    unit.avoidCrit  = 0 + luk        + (eb.avoidCrit or 0)

    -- 敏捷: +1攻速, +1闪避
    unit.atkSpeed   = math.floor(agi * 0.5) + (eb.atkSpeed or 0) + (sb.atkSpeed or 0) + (setB.atkSpeed or 0)
    -- agiToAtkSpeedEff: 每5点敏捷，攻击速度额外+N（N为装备档位系数，0.6~1.0）
    if (eb.agiToAtkSpeedEff or 0) > 0 then
        unit.atkSpeed = unit.atkSpeed + math.floor(agi / 5 * eb.agiToAtkSpeedEff)
    end
    -- 闪烁突袭临时攻速加成：recalcStats 被中途调用时保留加成，endPlayerTurn 清除时再 recalcStats
    if (unit._flashAtkSpdBonus or 0) > 0 then
        unit.atkSpeed = unit.atkSpeed + unit._flashAtkSpdBonus
    end
    unit.dodge      = 0 + agi      + (eb.dodge or 0)    + (sb.dodge or 0) + (setB.dodge or 0) + (pb.buff_dodge or 0)
    if (sbPct.dodge or 0) > 0 then
        local pctBonus = math.floor(unit.dodge * sbPct.dodge / 100)
        local minBonus = sbPct.dodge  -- 至少每1%对应1点
        unit.dodge = unit.dodge + math.max(pctBonus, minBonus)
    end
    -- phantomDodge: 每层幻影提高闪避值（聚影众等装备）
    if (eb.phantomDodge or 0) > 0 then
        -- 统计总幻影数：深渊词缀 melee_phantom（上限3）+ 装备 heroPhantom
        local phantomFromAffix = 0
        if M.equipment then
            for _, slotId in ipairs({"weapon_r", "weapon_l", "hat", "body", "shoulder", "belt", "pants", "boots", "gloves", "quiver", "offhand", "necklace", "ring1", "ring2"}) do
                local slot = M.equipment[slotId]
                if slot then
                    if slot.abyssAffix and slot.abyssAffix.mechanic == "melee_phantom" then
                        phantomFromAffix = phantomFromAffix + 1
                    end
                    if slot.heroAffix and slot.heroAffix.mechanic == "melee_phantom" then
                        phantomFromAffix = phantomFromAffix + 1
                    end
                end
            end
        end
        if phantomFromAffix > 3 then phantomFromAffix = 3 end
        local totalPhantom = phantomFromAffix + (eb.heroPhantom or 0)
        if totalPhantom > 0 then
            unit.dodge = unit.dodge + totalPhantom * eb.phantomDodge
        end
    end
    -- dodgeRateBonus: 闪避率额外提高（两条词缀独立叠加，最终合并）
    unit.dodgeRateBonus = (eb.dodgeRateBonus1 or 0) + (eb.dodgeRateBonus2 or 0)
    -- arsenalScatter: 军火库箭袋提供的散射次数
    unit.arsenalScatter = (eb.arsenalScatter or 0)
    -- healStoreRate/healReleaseRate: 圣光结晶治疗存储与释放
    unit.healStoreRate   = 0 + (eb.healStoreRate or 0)
    unit.healReleaseRate = 0 + (eb.healReleaseRate or 0)
    -- distDmgPctPerGrid: 神射手远程普通攻击距离伤害加成（每格%）
    unit.distDmgPctPerGrid = 0 + (eb.distDmgPctPerGrid or 0)
    -- 血屠：狂怒叠层（暴击叠加，未暴击衰减）
    unit.furyStackPerCrit   = 0 + (eb.furyStackPerCrit or 0)
    unit.furyMaxStacks      = 0 + (eb.furyMaxStacks or 0)
    unit.furyDecayOnNonCrit = 0 + (eb.furyDecayOnNonCrit or 0)
    unit.moveRange  = 2 + math.floor(agi / 50) + (eb.moveRange or 0)

    -- 体质: +9HP, +4物防, +0.5HP恢复（先应用体质百分比加成）
    if (sbPct.con or 0) > 0 then con = math.floor(con * (1 + sbPct.con / 100)) end
    unit.maxHp      = 30 + con * 9 + lvHp + (eb.hp or 0) + (sb.maxHp or 0) + (setB.hp or 0)
    if (sbPct.maxHp or 0) > 0 then unit.maxHp = math.floor(unit.maxHp * (1 + sbPct.maxHp / 100)) end
    unit.maxHp      = math.max(1, unit.maxHp)
    unit.def        = 10 + con * 4 + lvDef + (eb.def or 0) + (sb.def or 0) + (pb.buff_def or 0)
    if (sbPct.def or 0) > 0 then
        local pctBonus = math.floor(unit.def * sbPct.def / 100)
        local minBonus = sbPct.def  -- 至少每1%对应1点
        unit.def = unit.def + math.max(pctBonus, minBonus)
    end
    -- defPctBonus（武器被动 + 装备 defPct）在最终 def 基础上乘算
    local totalDefPct = (unit.defPctBonus or 0) + (eb.defPct or 0)
    if totalDefPct > 0 then
        unit.def = math.floor(unit.def * (1 + totalDefPct / 100))
    end
    -- 延迟伤害百分比（解放日胸甲）
    unit.deferDmgPct = (eb.deferDmgPct or 0)
    -- MP转化生命百分比（幻纱）
    unit.mpToHpPct = (eb.mpToHpPct or 0)
    -- 地狱踏：移动留下燃烧地面（burnPct=魔攻伤害%），免疫燃烧地面+治疗%
    unit.hellStompBurnPct = (eb.hellStompBurnPct or 0)
    unit.hellStompHealPct = (eb.hellStompHealPct or 0)
    -- 献礼：连击中断自动闪烁突袭次数上限 / 闪烁突袭施展距离加成
    unit.offeringAutoFlashMax    = (eb.offeringAutoFlashMax or 0)
    unit.offeringFlashRangeBonus = (eb.offeringFlashRangeBonus or 0)
    -- 白木胁差：伤害类技能额外施展次数
    unit.extraDmgSkillCast = (eb.extraDmgSkillCast or 0)
    unit.hpRegen    = 0 + con * 0.5 + (eb.hpRegen or 0) + (sb.hpRegen or 0) + fmnHpRegen + foodHpRegen
    if (sbPct.hpRegen or 0) > 0 then
        local pctBonus = math.floor(unit.hpRegen * sbPct.hpRegen / 100)
        local minBonus = sbPct.hpRegen  -- 至少每1%对应1点
        unit.hpRegen = unit.hpRegen + math.max(pctBonus, minBonus)
    end

    -- 智慧: +3.5魔攻, +5MP
    unit.mAtk       = 10 + math.floor(wis * 3.5) + math.floor(lvMAtk) + (eb.mAtk or 0) + (setB.mAtk or 0) + (pb.buff_matk or 0)
    if (sbPct.mAtk or 0) > 0 then
        local pctBonus = math.floor(unit.mAtk * sbPct.mAtk / 100)
        local minBonus = sbPct.mAtk  -- 至少每1%对应1点
        unit.mAtk = unit.mAtk + math.max(pctBonus, minBonus)
    end
    -- 征服祝福：魔攻加成（物攻加成在上方atk区域）
    if unit.conquerAtkPct and unit.conquerAtkPct > 0 and unit.conquerTurns and unit.conquerTurns > 0 then
        unit.mAtk = math.floor(unit.mAtk * (1 + unit.conquerAtkPct / 100))
    end
    local oldMaxMp  = unit.maxMp or 0
    unit.maxMp      = 20 + wis * 5 + lvMp + (eb.mp or 0) + (sb.maxMp or 0) + (setB.mp or 0)
    if (sbPct.maxMp or 0) > 0 then unit.maxMp = math.floor(unit.maxMp * (1 + sbPct.maxMp / 100)) end
    unit.maxMp      = math.max(1, unit.maxMp)

    -- 专注: +0.5物攻(已合并到atk), +1命中
    unit.rAtk       = 5 + foc      + (eb.rAtk or 0)
    unit.hit        = 1 + foc + wil + lvHit + (eb.hit or 0) + (eb.hitVal or 0) + (pb.buff_hit or 0)
    if (sbPct.hit or 0) > 0 then
        local pctBonus = math.floor(unit.hit * sbPct.hit / 100)
        local minBonus = sbPct.hit  -- 至少每1%对应1点
        unit.hit = unit.hit + math.max(pctBonus, minBonus)
    end
    -- 攻击距离基于武器类型：弓/法杖=远程(3)，其他/空手=近战(1)
    -- 弓必须同时装备箭袋才算远程，否则视为赤手空拳(近战)
    local weaponR = M.equipment["weapon_r"]
    local weaponL_range = M.equipment["weapon_l"]
    local wTag = weaponR and weaponR.weaponTag or nil
    -- 右手无有效武器标签时，检查左手（如单持匕首）
    if not wTag and weaponL_range and weaponL_range.weaponTag then
        wTag = weaponL_range.weaponTag
    end
    if wTag == "弓" then
        if not weaponL_range or weaponL_range.category ~= "箭袋" then
            wTag = nil  -- 无箭袋，视为赤手空拳
        end
    end
    local isLittleZeus = (eb.littleZeusRange or 0) > 0 and wTag == "锤"
    local isRangedWeapon = (wTag == "弓" or wTag == "法杖") or isLittleZeus
    if isLittleZeus then
        unit.atkRange = eb.littleZeusRange
    else
        unit.atkRange = isRangedWeapon and 3 or 1
    end
    -- 仅远程武器受攻击距离加成影响
    if isRangedWeapon then
        unit.atkRange = unit.atkRange + (eb.atkRange or 0) + (eb.atkRangeBonus or 0)
        -- 瞄准：Lv.3/6/10时攻击距离各+1
        local aimLv = M.skillLevels["h_aim"] or 0
        if aimLv > 0 then
            local aimDef = M.SKILL_DEFS["h_aim"]
            if aimDef and aimDef.aimRangeLvs then
                for _, reqLv in ipairs(aimDef.aimRangeLvs) do
                    if aimLv >= reqLv then
                        unit.atkRange = unit.atkRange + 1
                    end
                end
            end
        end
    end

    -- 守林人：每1格最大攻击距离提高命中值（atkRange确定后补加）
    if (eb.atkRangeHitPer or 0) > 0 then
        unit.hit = unit.hit + (unit.atkRange or 1) * eb.atkRangeHitPer
    end

    -- 盾牌特殊：反击类技能作用于远程攻击的倍率（0=不生效，0.6~1.0=生效倍率）
    unit.counterRangedPct = eb.counterRangedPct or 0

    -- 感知: +1.5法暴值, +4魔防, +0.5MP恢复
    unit.mCritRate  = math.floor(per * 1.5) + lvMCrit + (eb.mCritVal or 0) + (eb.mCritRate or 0) + foodMagicCrit
    unit.mDef       = 10 + per * 4   + lvMDef + (eb.mDef or 0) + (pb.buff_mdef or 0)
    -- mDefPct（装备 mDefPct 百分比加成）在最终 mDef 基础上乘算
    local totalMDefPct = (eb.mDefPct or 0)
    if totalMDefPct > 0 then
        unit.mDef = math.floor(unit.mDef * (1 + totalMDefPct / 100))
    end
    unit.mdef       = unit.mDef  -- 小写别名，供 Combat 伤害计算使用
    unit.mCritDmg   = 25             + luk * 1.25 + (eb.mCritDmg or 0)

    -- 血屠：狂怒层数加成（攻击力+3/层，暴击伤害+1%/层，物理+魔法）
    if (unit.furyMaxStacks or 0) > 0 and (unit._furyStacks or 0) > 0 then
        local stk = unit._furyStacks
        unit.atk     = unit.atk     + stk * 3
        unit.critDmg = unit.critDmg + stk
        unit.mCritDmg = unit.mCritDmg + stk
    end

    unit.mpRegen    = 0 + per * 0.5  + (eb.mpRegen or 0) + (sb.mpRegen or 0) + fmnMpRegen + foodMpRegen
    if (sbPct.mpRegen or 0) > 0 then
        local pctBonus = math.floor(unit.mpRegen * sbPct.mpRegen / 100)
        local minBonus = sbPct.mpRegen  -- 至少每1%对应1点
        unit.mpRegen = unit.mpRegen + math.max(pctBonus, minBonus)
    end

    -- 意念: +0.5吟唱, +1命中(已合并到hit)
    unit.castSpeed  = math.floor(wil * 0.5) + (eb.castSpeed or 0)
    -- 吟唱速度UP被动技能加成
    if unit == M.player then
        local cstLv = M.skillLevels["m_cast_spd"] or 0
        if cstLv > 0 then
            local cstDef = M.SKILL_DEFS["m_cast_spd"]
            if cstDef then
                unit.castSpeed = unit.castSpeed + (cstDef.castSpdPerLv or 5) * cstLv
            end
        end
    end

    -- 感知/专注/体质有效值（含凝视加成），供凝视额外伤害、大剧院连击等公式使用
    unit.per = per
    unit.foc = foc
    unit.con = con

    -- 魅力: 召唤物/同伴 HP+10/点, 伤害+1%/点, 受伤-0.1%/点
    unit.cha = cha

    -- 元素抗性（百分比，可由装备、被动技能、药水提供）
    local allEleRes = (eb.allEleRes or 0)  -- 镜铠：所有元素抗性(%)
    unit.resFire    = 0 + (eb.resFire or 0) + (sb.resFire or 0) + (pb.buff_fire_res or 0) + allEleRes
    unit.resIce     = 0 + (eb.resIce or 0) + (sb.resIce or 0) + (pb.buff_ice_res or 0) + allEleRes
    unit.resElec    = 0 + (eb.resElec or 0) + (sb.resElec or 0) + (pb.buff_thunder_res or 0) + allEleRes
    unit.resLight   = 0 + (eb.resLight or 0) + (sb.resLight or 0) + (pb.buff_holy_res or 0) + allEleRes
    unit.resDark    = 0 + (eb.resDark or 0) + (sb.resDark or 0) + (pb.buff_dark_res or 0) + allEleRes
    unit.resNature  = 0 + (eb.resNature or 0) + (sb.resNature or 0) + (pb.buff_nature_res or 0) + allEleRes

    -- 基础值面板（仅含点数+等级成长，用于属性汇总面板分离显示）
    if unit == M.player then
        calculateBaseStats(unit, s, isHunter, lvAtk, lvMAtk, lvCrit, lvMCrit, lvHit, lvHp, lvMp, lvDef, lvMDef)
    end

    -- 装备特殊效果：怪物数量加成
    unit.maxMonstersBonus = (eb.maxMonsters or 0)
    -- 装备特殊效果：每次刷怪数量加成
    unit.spawnCountBonus = (eb.spawnCount or 0)
    -- 装备特殊效果：区域首领不出现
    unit.noBoss = (eb.noBoss or 0) > 0

    -- 吸血：回复造成伤害的百分比（如 10 表示 10%）
    unit.lifesteal = 0 + (eb.lifesteal or 0)              -- 通用吸血(%)，无上限
    unit.physLifesteal = 0 + (eb.physLifesteal or 0)       -- 物理吸血(%)，无上限
    unit.magLifesteal  = 0 + (eb.magLifesteal or 0)        -- 法术吸血(%)，无上限
    unit.batFangLifesteal = 0 + (eb.batFangLifesteal or 0) -- 蝙蝠牙吸血(%)，上限10点/件
    unit.batFangLifestealCap = (eb.batFangCount or 0) * 10 -- 每件蝙蝠牙装备独立10点上限
    unit.manaLeech = 0 + (eb.manaLeech or 0)               -- 魔力回收(%)：魔法伤害的百分比回复MP

    -- 托马斯：左手武器栏为空时，技能作用范围加成
    local noOffhand = not (M.equipment and M.equipment["weapon_l"])
    unit.equipAoeBonus = noOffhand and (eb.skillAoeBonusIfNoOffhand or 0) or 0

    -- 默示录：技能伤害减免(%) / 普攻AOE魔法伤害
    unit.skillDmgReduction  = 0 + (eb.skillDmgReduction or 0)   -- 技能伤害降低(%)
    unit.normalAtkMatkCoeff = 0 + (eb.normalAtkMatkCoeff or 0)   -- 普攻魔法系数(%)
    unit.normalAtkMatkRange = 0 + (eb.normalAtkMatkRange or 0)   -- 普攻魔法范围(格)
    unit.dualDaggerDmgPct   = 0 + (eb.dualDaggerDmgPct or 0)    -- 双持匕首伤害比例(%)

    -- 魔法石项链：根据造成伤害的百分比回复魔法值
    unit.dmgToMpPct = (eb.dmgToMpPct or 0)  -- 伤害转魔法比例(%)
    -- 魔法石项链：每100点最大魔法值提高法术伤害(%)
    unit.mpToMagDmgPct = (eb.mpToMagDmgPct or 0)

    -- 千军令：旋风斩触发幻影
    unit.whirlPhantomCount = (eb.whirlPhantomCount or 0)  -- 幻影数量
    unit.whirlPhantomMul   = (eb.whirlPhantomMul or 0)    -- 幻影倍率(%)

    -- 狂血：未暴击物理伤害惩罚(%)
    unit.nonCritPhysPenalty = (eb.nonCritPhysPenalty or 0)

    -- 聚焦器：禁用散射/弹射/幻影/溅射，每条生效词缀增伤
    unit.focuserDmgPer    = (eb.focuserDmgPer or 0)      -- 每条词缀增伤(%)
    unit.focuserMaxStacks = (eb.focuserMaxStacks or 0)    -- 至多计算几条

    -- 极重月：禁连击 + 攻速转技能伤害
    unit.noCombo         = (eb.noCombo or 0) > 0           -- 禁止触发连击
    unit.aspdSkillDmgPct = (eb.aspdSkillDmgPct or 0)       -- 每点攻速提高技能伤害%

    -- HP流失：每回合损失的HP（如 10 表示每回合掉10HP）
    unit.hpDrain = 0 + (eb.hpDrain or 0)

    -- 装备特殊效果：伤害减免/回血/施法效果/祝福等
    unit.pDmgReduce       = 0 + (eb.pDmgReduce or 0)       -- 物理伤害减免(%)
    unit.mDmgReduce       = 0 + (eb.mDmgReduce or 0)       -- 魔法伤害减免(%)
    -- 全能者腰带：每10点属性提供伤害加成/减免
    local allStatDmgPer10    = (eb.allStatDmgPer10 or 0)
    local allStatReducePer10 = (eb.allStatReducePer10 or 0)
    if allStatDmgPer10 > 0 or allStatReducePer10 > 0 then
        local totalStats = str + wis + agi + con + foc + per + wil + luk + cha
        if allStatDmgPer10 > 0 then
            unit.allStatDmgBonus = totalStats / 10 * allStatDmgPer10
        end
        if allStatReducePer10 > 0 then
            local reduce = totalStats / 10 * allStatReducePer10
            unit.pDmgReduce = unit.pDmgReduce + reduce
            unit.mDmgReduce = unit.mDmgReduce + reduce
        end
    end
    -- 受伤降低被动技能：物理+魔法伤害减免各+1%/等级
    if unit == M.player then
        local dmgReduceLv = M.skillLevels and M.skillLevels["p_dmg_reduce"] or 0
        if dmgReduceLv > 0 then
            local reducePct = dmgReduceLv * 1
            unit.pDmgReduce = unit.pDmgReduce + reducePct
            unit.mDmgReduce = unit.mDmgReduce + reducePct
        end
    end
    -- 初心腰带：每1点未使用的技能点提高攻击力/魔攻
    local atkPerUnusedSP  = (eb.atkPerUnusedSP or 0)
    local mAtkPerUnusedSP = (eb.mAtkPerUnusedSP or 0)
    if unit == M.player and (atkPerUnusedSP > 0 or mAtkPerUnusedSP > 0) then
        local unusedSP = M.skillPoints or 0
        if unusedSP > 0 then
            if atkPerUnusedSP > 0 then
                unit.atk  = unit.atk  + math.floor(unusedSP * atkPerUnusedSP)
            end
            if mAtkPerUnusedSP > 0 then
                unit.mAtk = unit.mAtk + math.floor(unusedSP * mAtkPerUnusedSP)
            end
        end
    end
    -- 守林人：每1点散射提高物理攻击力（与 performScatter 保持一致的散射数计算）
    if unit == M.player and (eb.scatterAtkPer or 0) > 0 then
        local sc = 0
        -- 深渊词缀 ranged_scatter（聚焦器屏蔽深渊词缀散射，与 Combat 保持一致）
        if (unit.focuserDmgPer or 0) <= 0 and M.equipment then
            local superiorSeen = {}
            for _, slotId in ipairs({"weapon_r","weapon_l","hat","shoulder","cloak",
                                     "chest","gloves","pants","boots","necklace",
                                     "belt","trinket","ring1","ring2"}) do
                local item = M.equipment[slotId]
                if item then
                    if item.rarity == "superior" and item.templateId then
                        if superiorSeen[item.templateId] then goto scatterContinue end
                        superiorSeen[item.templateId] = true
                    end
                    if item.abyssAffix and item.abyssAffix.mechanic == "ranged_scatter" then
                        sc = sc + 1
                    end
                    if item.heroAffix and item.heroAffix.mechanic == "ranged_scatter" then
                        sc = sc + 1
                    end
                    ::scatterContinue::
                end
            end
        end
        -- 英雄长弓（不受聚焦器影响）
        local wr_sc = M.equipment and M.equipment["weapon_r"]
        if wr_sc and wr_sc.templateId == "hero_bow" then sc = sc + 1 end
        -- 军火库箭袋（不受聚焦器影响）
        sc = sc + (unit.arsenalScatter or 0)
        -- 分心满级：散射+1
        if (M.skillLevels["h_distraction"] or 0) >= (M.SKILL_MAX_LEVEL or 10) then
            sc = sc + 1
        end
        if sc > 0 then
            unit.atk = unit.atk + sc * eb.scatterAtkPer
        end
    end

    unit.blockHeal        = 0 + (eb.blockHeal or 0)         -- 格挡时回血(固定值)
    unit.onHitHeal        = 0 + (eb.onHitHeal or 0)         -- 命中时回血(固定值)
    unit.onHitDefReduce   = 0 + (eb.onHitDefReduce or 0)    -- 命中时减防(固定值)
    unit.castHeal         = 0 + (eb.castHeal or 0)          -- 施法时回血(固定值)
    unit.castMpRegen      = 0 + (eb.castMpRegen or 0)       -- 施法时回魔(固定值)
    unit.onKillHealHp     = 0 + (eb.onKillHealHp or 0)     -- 击杀时回血(固定值)
    unit.healEffectPct    = 0 + (eb.healEffectPct or 0)     -- 施加的治疗效果加成(%)
    -- perToHealEffPct: 每5点感知，治疗效果额外+N%（N为装备档位系数，0.15~0.35）
    if (eb.perToHealEffPct or 0) > 0 then
        unit.healEffectPct = unit.healEffectPct + math.floor(per / 5) * eb.perToHealEffPct
    end
    -- 圣洁：治疗效果+2%/等级
    local holyPurityLv = M.skillLevels["p_holy_purity"] or 0
    if holyPurityLv > 0 then
        local purityDef = M.SKILL_DEFS["p_holy_purity"]
        unit.healEffectPct = unit.healEffectPct + (purityDef and purityDef.healEffectPerLv or 2) * holyPurityLv
    end
    unit.onMagDmgHeal     = 0 + (eb.onMagDmgHeal or 0)     -- 造成魔法伤害时回血(%)
    unit.onDamageTakenHeal = 0 + (eb.onDamageTakenHeal or 0) -- 受伤时回血(固定值)
    unit.potionHealBonus  = 0 + (eb.potionHealBonus or 0)  -- 药水额外治疗量(固定值)
    unit.potionHealBonusMaxLv = 0 + (eb.potionHealBonusMaxLv or 0) -- 药水加成生效的最大等级
    unit.holySpringBlessing = 0 + (eb.holySpringBlessing or 0)  -- 圣泉祝福：回合开始回血(%)
    unit.shelterBlessing  = 0 + (eb.shelterBlessing or 0)   -- 庇护祝福：受击减伤(%)
    unit.equipThorns      = 0 + (eb.equipThorns or 0)        -- 受击反伤(固定物理伤害)
    unit.rebirth          = 0 + (eb.rebirth or 0)            -- 重生：抵挡致死伤害（铸甲匠项链）

    -- 伤害加成（精炼词缀提供，百分比值）
    unit.weaponTag      = wTag  -- 当前武器标签，供战斗伤害管线使用
    unit.swordDmgBonus  = (eb.swordDmgBonus or 0)
    unit.daggerDmgBonus = (eb.daggerDmgBonus or 0)
    unit.maceDmgBonus   = (eb.maceDmgBonus or 0)
    unit.bowDmgBonus    = (eb.bowDmgBonus or 0)
    unit.staffDmgBonus  = (eb.staffDmgBonus or 0)
    unit.physDmgBonus   = (eb.physDmgBonus or 0)
    unit.bounceDmgInc   = (eb.bounceDmgInc or 0)  -- 弹射伤害每跳递增(%)
    unit.rangeBounceCount  = (eb.rangeBounceCount or 0)   -- 远程技能弹射次数（银鹿）
    unit.rangeBounceDmgMul = (eb.rangeBounceDmgMul or 100) -- 远程技能弹射伤害倍率%(银鹿)
    unit.rangedExplosionPct = (eb.rangedExplosionPct or 0)  -- 远程技能爆炸伤害%(爆炸信)
    unit.explosionAoeMax   = (eb.explosionAoeMax or 0)    -- 爆炸信可受技能扩展影响的上限
    unit.holyAoePct        = (eb.holyAoePct or 0)           -- 祝福术/超度范围化伤害%(哈雷努拉)
    unit.strikeAoePct      = (eb.strikeAoePct or 0)          -- 强击系范围化伤害%(银色狮子)
    unit.nearDmgBonus   = (eb.nearDmgBonus or 0)  -- 近处敌人伤害加成(%，切比雪夫距离<=1)
    unit.counterComboMax = (eb.counterComboMax or 0) -- 反击连击上限（根据体质触发额外反击次数）
    unit.counterComboConRate = (eb.counterComboConRate or 0) -- 每1点体质提供的连击概率(%)
    unit.dodgeCounterChanceBonus = (eb.dodgeCounterChanceBonus or 0) -- 水中蛇：反击概率加成(%)
    unit.dodgeCounterDmgBonus   = (eb.dodgeCounterDmgBonus or 0)   -- 水中蛇：反击伤害加成(%)
    unit.illusionDmgPct = (eb.illusionDmgPct or 0)  -- 幻影伤害提高(%)
    unit.illusionSearchRange  = (eb.illusionSearchRange or 0)   -- 幻影检索范围扩展（格数）
    unit.illusionSingleExtra  = (eb.illusionSingleExtra or 0)   -- 幻影对单一目标额外作用数量
    unit.illusionSingleDmgPct = (eb.illusionSingleDmgPct or 0)  -- 幻影单一目标额外伤害(%)
    unit.derivStormDmgBonus = (eb.derivStormDmgBonus or 0)  -- 衍生飓风技能伤害倍率提高(%)；>0时护甲清零触发飓风
    unit.magDmgBonus    = (eb.magDmgBonus or 0)
    -- 魔法石：每100点最大魔法值提高法术伤害(%)
    if (unit.mpToMagDmgPct or 0) > 0 and (unit.maxMp or 0) > 0 then
        unit.magDmgBonus = unit.magDmgBonus + unit.maxMp / 100 * unit.mpToMagDmgPct
    end
    unit.fireDmgBonus      = (eb.fireDmgBonus or 0) + (pb.buff_fire_dmg or 0) + foodFireDmgPct
    unit.ragingFireBonus   = (eb.ragingFireBonus or 0)   -- 燃火：站在灼烧地面时火焰伤害额外乘算加成(%)
    unit.meteorStunChance  = (eb.meteorStunChance or 0)   -- 烈焰书：陨石术晕眩概率(%)
    unit.meteorStunDuration = (eb.meteorStunDuration or 0) -- 烈焰书：陨石术晕眩回合数
    unit.iceDmgBonus    = (eb.iceDmgBonus or 0) + (pb.buff_ice_dmg or 0) + foodIceDmgPct
    unit.blizzardFreezeChance  = (eb.blizzardFreezeChance or 0)   -- 寒冰书：暴风雪冰冻概率(%)
    unit.blizzardFreezeDuration = (eb.blizzardFreezeDuration or 0) -- 寒冰书：暴风雪冰冻回合数
    unit.elecDmgBonus   = (eb.elecDmgBonus or 0) + (pb.buff_thunder_dmg or 0) + foodThunderDmgPct
    unit.thunderCloudChainLightChance = (eb.thunderCloudChainLightChance or 0)  -- 雷电书：雷云术触发闪电链概率(%)
    unit.thunderJarBounce = (eb.thunderJarBounce or 0)  -- 养雷壶：闪电链额外弹射次数
    unit.thunderJarRange  = (eb.thunderJarRange or 0)   -- 养雷壶：闪电链额外弹射范围
    unit.deepThinkDmgPer  = (eb.deepThinkDmgPer or 0)   -- 深度思维：每额外吟唱段数增伤%
    unit.castRange        = (eb.castRange or 0)          -- 虚空握：远程技能施展距离加成
    unit.atkRangeBonus    = (eb.atkRangeBonus or 0)      -- 虚空握：攻击距离加成
    unit.lightDmgBonus  = (eb.lightDmgBonus or 0) + (pb.buff_holy_dmg or 0) + foodHolyDmgPct
    unit.mpCostDmgCoeff = (eb.mpCostDmgCoeff or 0)  -- 魔贯：施法消耗MP增伤系数(%)
    unit.eleFlowBonus   = (eb.eleFlowBonus or 0)     -- 元素流转：造成元素伤害后其他元素下回合增伤(%)
    unit.radianceDmgBonus     = (eb.radianceDmgBonus or 0)      -- 辉光伤害加成(%)
    unit.radianceNearDmgBonus = (eb.radianceNearDmgBonus or 0)  -- 辉光对近处敌人额外伤害加成(%)
    unit.radianceStunChance = (eb.radianceStunChance or 0) -- 辉光晕眩概率(%)
    unit.rangedDefRate = (eb.rangedDefRate or 0)  -- 山脉盾：每10点超700物防的远程减伤率(%)
    unit.rangedDefCap  = (eb.rangedDefCap or 0)   -- 山脉盾：远程减伤上限(%)

    -- 至高天+天使联动条件：各自的词条仅在同时装备对方时生效
    if unit == M.player and M.equipment then
        local wr = M.equipment["weapon_r"]
        local wl = M.equipment["weapon_l"]
        local hasHeavensZenith = (wr and wr.templateId == "heavens_zenith") or (wl and wl.templateId == "heavens_zenith")
        local hasAngelShield   = (wr and wr.templateId == "angel_shield")   or (wl and wl.templateId == "angel_shield")
        -- 至高天的辉光伤害加成：需要同时装备天使
        if not hasAngelShield then
            unit.radianceDmgBonus = 0
        end
        -- 天使的辉光晕眩概率：需要同时装备至高天
        if not hasHeavensZenith then
            unit.radianceStunChance = 0
        end
    end

    -- 伴随星：存储 cstar* 值（供 tooltip 显示），实际加成已在 getEquipBonus 中转换
    unit.cstarAgiL     = (eb.cstarAgiL or 0)
    unit.cstarAtkSpdL  = (eb.cstarAtkSpdL or 0)
    unit.cstarStrR     = (eb.cstarStrR or 0)
    unit.cstarWisR     = (eb.cstarWisR or 0)
    unit.cstarCritDmgR = (eb.cstarCritDmgR or 0)
    unit.cstarMCritDmgR = (eb.cstarMCritDmgR or 0)
    if unit == M.player and M.equipment then
        local wr = M.equipment["weapon_r"]
        local wl = M.equipment["weapon_l"]
        local inLeft  = (wl and wl.templateId == "companion_star")
        local inRight = (wr and wr.templateId == "companion_star")
        if inLeft then
            -- 左手生效：清零右手属性（tooltip 不显示不生效的）
            unit.cstarStrR = 0; unit.cstarWisR = 0; unit.cstarCritDmgR = 0; unit.cstarMCritDmgR = 0
        elseif inRight then
            -- 右手生效：清零左手属性
            unit.cstarAgiL = 0; unit.cstarAtkSpdL = 0
        else
            unit.cstarAgiL = 0; unit.cstarAtkSpdL = 0
            unit.cstarStrR = 0; unit.cstarWisR = 0; unit.cstarCritDmgR = 0; unit.cstarMCritDmgR = 0
        end
    end

    -- 条件被动加成（武器专精、buff等）
    if unit == M.player then
        applyConditionalPassives(unit)
    end

    -- HP/MP 按比例调整
    adjustCurrentHpMp(unit, oldMaxHp, oldMaxMp)

    -- 饮血护甲值上限钳制
    if unit == M.player then
        local bloodDrinkLv = M.skillLevels and M.skillLevels["w_blood_drink"] or 0
        if bloodDrinkLv > 0 then
            local cap = math.floor(unit.maxHp * 0.02 * bloodDrinkLv)
            M.bloodShield = math.min(M.bloodShield or 0, cap)
        else
            M.bloodShield = 0
        end
    end
end

-- ====================================================================
-- 回合阶段推进
-- ====================================================================
function M.advanceTurnPhase()
    -- 酒馆肉搏胜利已触发，冻结回合推进
    if M.tavernBrawlState and M.tavernBrawlState.done then return true end
    local NEXT = {
        [M.PHASE_PRE]    = M.PHASE_MOVE,
        [M.PHASE_MOVE]   = M.PHASE_MID,
        [M.PHASE_MID]    = M.PHASE_ACTION,
        [M.PHASE_ACTION] = M.PHASE_END,
    }
    local nextPhase = NEXT[M.turnPhase]
    if not nextPhase then return true end
    M.turnPhase = nextPhase
    if nextPhase == M.PHASE_PRE or nextPhase == M.PHASE_MID then
        return M.advanceTurnPhase()
    end
    if nextPhase == M.PHASE_END then return true end
    return false
end

-- ====================================================================
-- BFS 可移动格子
-- ====================================================================
--- BFS 可移动格计算（玩家/怪物通用，支持大型单位）
---@param unit table 单位
---@param allowPassFriendly boolean|nil 是否允许穿过友方（怪物穿友方，玩家不能）
function M.getMovableCells(unit, allowPassFriendly)
    local result = {}
    local visited = {}   -- stateKey (cellKey.."_"..flags) -> min cost
    local parents = {}   -- cellKey -> {parentX, parentY}
    local bestCost = {}  -- cellKey -> min cost（用于选最短路径的 parent）
    local s = M.unitSize(unit)
    local startKey = M.cellKey(unit.x, unit.y)

    -- 风向设置
    local WE = require("WeatherEffects")
    local wdx, wdy = WE.getWindDirComponents()
    local windActive = (wdx ~= 0 or wdy ~= 0)

    -- 队列: {x, y, cost, windFlags}
    local queue = {{unit.x, unit.y, 0, 0}}
    visited[startKey .. "_0"] = 0

    while #queue > 0 do
        local cur = table.remove(queue, 1)
        local cx, cy, cost, wflags = cur[1], cur[2], cur[3], cur[4]

        -- 跳过过期条目
        local ck = M.cellKey(cx, cy)
        local stateKey = ck .. "_" .. wflags
        if visited[stateKey] and visited[stateKey] < cost then
            goto continue_bfs
        end

        if cost > 0 then
            -- 大型单位：检查整个 sxs 区域是否可停留
            if s > 1 then
                if M.isAreaEmpty(cx, cy, s, unit) then
                    result[ck] = true
                end
            else
                if M.isCellEmpty(cx, cy) then
                    result[ck] = true
                end
            end
        end
        -- 玩家移速 debuff 减免
        local effMoveRange = unit.moveRange
        -- 隐匿状态：移动距离覆盖为固定值
        if unit == M.player and M.stealthActive then
            local sLv = M.skillLevels["a_stealth"] or 0
            local sDef = M.SKILL_DEFS["a_stealth"]
            if sDef then
                effMoveRange = sDef.stealthMoveBase or 1
                if sDef.stealthMoveLvs then
                    for _, reqLv in ipairs(sDef.stealthMoveLvs) do
                        if sLv >= reqLv then effMoveRange = effMoveRange + 1 end
                    end
                end
            end
        end
        -- 玩家 debuff 减速（在禁移判定之前处理，保证 debuff 不会把移动减到 0 以下）
        if unit == M.player and M.playerDebuffs then
            for _, db in ipairs(M.playerDebuffs) do
                if db.type == "move" then effMoveRange = effMoveRange - db.val end
            end
            effMoveRange = math.max(1, effMoveRange)
        end
        -- 玩家冻僵 debuff：迪拉冰锥术命中后移动距离-1
        if unit == M.player and unit.chilled and unit.chilledTurns and unit.chilledTurns > 0 then
            effMoveRange = effMoveRange - unit.chilled
            effMoveRange = math.max(1, effMoveRange)
        end
        -- 静神已改为被动，不再限制移动（玩家主动选择不移动才触发 buff）
        -- 吟唱状态：无法移动
        if unit == M.player and M.chanting then
            effMoveRange = 0
        end
        -- 冰墙减速已改为冻僵debuff（在 Combat.applyIceWallChill 中施加）
        -- 暴风雪减速 debuff：moveSlow 字段
        if unit ~= M.player and unit.moveSlow and unit.moveSlow > 0 then
            effMoveRange = effMoveRange - unit.moveSlow
        end
        -- 冻僵 debuff：冰锥术命中后移动距离减少
        if unit ~= M.player and unit.chilled and unit.chilledTurns and unit.chilledTurns > 0 then
            effMoveRange = effMoveRange - unit.chilled
        end
        -- 天气移动修正：雨天潮湿(-1)
        local rainMod = WE.getRainMoveMod()
        if rainMod ~= 0 then
            effMoveRange = effMoveRange + rainMod
        end
        -- 总兜底：怪物/友军无论叠加多少减速debuff，最少移动1格
        -- （眩晕/冰冻等控制效果在 planAllEnemyMoves 中跳过行动，不经过此处）
        if unit ~= M.player and effMoveRange < 1 then
            effMoveRange = 1
        end
        -- 狂风移动修正：根据路径标记计算风向加成
        local windBonus = windActive and WE.calcWindMoveBonus(wflags, wdx, wdy) or 0
        local effRangeWithWind = math.max(effMoveRange, effMoveRange + windBonus)
        if cost < effRangeWithWind then
            local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
            for _, d in ipairs(dirs) do
                local nx, ny = cx + d[1], cy + d[2]
                local nk = M.cellKey(nx, ny)
                    local canPass = false
                    if s > 1 then
                        -- 大型单位：检查整个 sxs 区域
                        if M.isAreaInBoard(nx, ny, s) then
                            if allowPassFriendly then
                                canPass = true
                                for dy2 = 0, s - 1 do
                                    for dx2 = 0, s - 1 do
                                        local checkX, checkY = nx + dx2, ny + dy2
                                        local u = M.getUnitAt(checkX, checkY)
                                        if u and u ~= unit then
                                            canPass = false
                                            break
                                        end
                                        -- 额外阻挡检查（竞技场宝箱等）
                                        if M.arenaWaitForExit then
                                            for _, chest in ipairs(M.arenaChests) do
                                                if not chest.opened and chest.x == checkX and chest.y == checkY then
                                                    canPass = false
                                                    break
                                                end
                                            end
                                            if not canPass then break end
                                        end
                                    end
                                    if not canPass then break end
                                end
                            else
                                canPass = M.isAreaEmpty(nx, ny, s, unit)
                            end
                        end
                    else
                        if M.isInBoard(nx, ny) then
                            if allowPassFriendly then
                                local occupant = M.getUnitAt(nx, ny)
                                if occupant == nil or occupant == unit then
                                    canPass = true
                                elseif unit.isCompanion and occupant.isCompanion then
                                    -- 同伴之间可以互相穿越
                                    canPass = true
                                elseif unit.isMonster and occupant.isMonster then
                                    -- 怪物之间可以互相穿越
                                    canPass = true
                                else
                                    canPass = false
                                end
                            else
                                canPass = M.isCellEmpty(nx, ny) or (nx == unit.x and ny == unit.y)
                            end
                        end
                    end
                    if canPass then
                        -- 更新风向路径标记
                        local newFlags = windActive
                            and WE.updateWindFlags(wflags, d[1], d[2], wdx, wdy)
                            or 0
                        local newCost = cost + 1
                        -- 计算新路径的风向加成，检查是否在有效范围内
                        local newWindBonus = windActive
                            and WE.calcWindMoveBonus(newFlags, wdx, wdy) or 0
                        local newEffRange = math.max(effMoveRange, effMoveRange + newWindBonus)
                        if newCost <= newEffRange then
                            local nStateKey = nk .. "_" .. newFlags
                            if not visited[nStateKey] or visited[nStateKey] > newCost then
                                visited[nStateKey] = newCost
                                -- 更新 parent（优先最短路径）
                                if not bestCost[nk] or newCost < bestCost[nk] then
                                    parents[nk] = {cx, cy}
                                    bestCost[nk] = newCost
                                end
                                table.insert(queue, {nx, ny, newCost, newFlags})
                            end
                        end
                    end
            end
        end
        ::continue_bfs::
    end
    return result, parents
end

--- 从 BFS parent map 重建路径（返回从起点到终点的 waypoints 数组）
function M.reconstructPath(parents, fromX, fromY, toX, toY)
    if fromX == toX and fromY == toY then return nil end
    local path = {}
    local cx, cy = toX, toY
    local startKey = M.cellKey(fromX, fromY)
    while true do
        table.insert(path, 1, {cx, cy})
        local k = M.cellKey(cx, cy)
        if k == startKey then break end
        local p = parents[k]
        if not p then break end  -- 安全兜底
        cx, cy = p[1], p[2]
    end
    -- 确保起点在路径头部
    if #path == 0 or path[1][1] ~= fromX or path[1][2] ~= fromY then
        table.insert(path, 1, {fromX, fromY})
    end
    return path
end

--- 怪物专用：允许穿过友方怪物（兼容旧调用）
function M.getMovableCellsForMonster(unit)
    return M.getMovableCells(unit, true)
end

-- ====================================================================
-- 攻击范围
-- ====================================================================
function M.getAttackableCells(unit, fromX, fromY, rangeOverride, isProjectile)
    local result = {}
    local s = M.unitSize(unit)
    local range = rangeOverride or unit.atkRange
    -- 普通攻击时自动从武器类型推断弹道类型
    if isProjectile == nil and not rangeOverride then
        local wTag = unit.weaponTag
        isProjectile = (wTag == "弓" or wTag == "法杖")
    end
    -- 弹道类攻击在刮风时有方向性射程调整（顺风+1, 逆风-1）
    local useWindRange = isProjectile and M.isWindy
    local WE_range = nil
    if useWindRange then
        WE_range = require("WeatherEffects")
        useWindRange = WE_range.isActive()
    end
    local scanRange = useWindRange and (range + 1) or range
    -- 从所有占据的格子向外辐射攻击范围
    for oy = 0, s - 1 do
        for ox = 0, s - 1 do
            local cx, cy = fromX + ox, fromY + oy
            for dy = -scanRange, scanRange do
                for dx = -scanRange, scanRange do
                    local dist = math.abs(dx) + math.abs(dy)
                    if dist <= scanRange and dist > 0 then
                        local tx, ty = cx + dx, cy + dy
                        -- 排除自身占据的格子
                        if M.isInBoard(tx, ty) and not (tx >= fromX and tx < fromX + s and ty >= fromY and ty < fromY + s) then
                            local effectiveRange = range
                            if useWindRange then
                                effectiveRange = range + WE_range.getWindRangeMod(cx, cy, tx, ty)
                            end
                            if dist <= effectiveRange then
                                result[M.cellKey(tx, ty)] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

-- ====================================================================
-- 设置面板几何
-- ====================================================================
function M.getSettingsPanelRect()
    local edgeInset = M.isLandscape and 40 or 0
    local px = 8 + edgeInset
    local py = M.TOP_BAR_H + 4
    -- GM 按钮已移至独立面板，设置面板高度：音量+横屏+动画+伤害飘字+震动+手动保存+兑换码+修改姓名+(脱离卡死)+息屏挂机+返回按钮
    local ph = M.isDungeon and 410 or 374
    return px, py, M.SETTINGS_PANEL_W, ph
end

function M.getGMPanelRect()
    local edgeInset = M.isLandscape and 40 or 0
    local px = 8 + edgeInset
    local py = M.TOP_BAR_H + 4
    -- 标题28 + 11行×(24+4) + 底部4 = 340
    local ph = 340
    return px, py, M.SETTINGS_PANEL_W, ph
end

function M.getSliderTrackRect()
    local px, py = M.getSettingsPanelRect()
    local trackX = px + M.SLIDER_TRACK_MARGIN_X
    local trackW = M.SETTINGS_PANEL_W - M.SLIDER_TRACK_MARGIN_X * 2
    local trackY = py + 42
    return trackX, trackY, trackW, M.SLIDER_TRACK_H
end

-- ====================================================================
-- 坐标转换
-- ====================================================================
function M.screenToCell(sx, sy)
    local cx = math.floor((sx - M.BOARD_X) / M.CELL) + 1
    local cy = math.floor((sy - M.BOARD_Y) / M.CELL) + 1
    if cx >= 1 and cx <= M.BOARD_SIZE and cy >= 1 and cy <= M.BOARD_SIZE then
        return cx, cy
    end
    return nil, nil
end

-- ====================================================================
-- 云存档
-- ====================================================================
M.cloudSaveStatus = ""  -- "", "saving", "saved", "error", "loading", "loaded"
M.cloudSaveTimer = 0    -- 状态提示显示倒计时

-- ====================================================================
-- 天气变更鉴定系统
-- ====================================================================
-- 时间累计：战斗中每回合+1，非战斗每5秒+1
-- 每累计120进行一次鉴定，初始成功率5%，失败后+5%
-- 成功率 = 5% × 鉴定次数，与累计时间存在勾稽关系：
--   鉴定次数 = floor(累计时间 / 120)，故成功率 = 累计时间 / 24 (%)
-- 成功后天气变更、时间和鉴定次数重置
-- ====================================================================

local WEATHER_NAMES = {
    clear = "晴天", rain = "下雨", wind = "刮风", scorching = "暴晒",
}

--- 获取当前天气类型标识
---@return string "clear"|"rain"|"wind"|"scorching"
function M.getCurrentWeather()
    if M.isScorching then return "scorching" end
    if M.isWindy then return "wind" end
    if M.isRaining then return "rain" end
    return "clear"
end

--- 设置天气类型（互斥，同时只有一种天气）
---@param weatherType string "clear"|"rain"|"wind"|"scorching"
function M.setWeather(weatherType)
    M.isRaining = false
    M.isWindy = false
    M.isScorching = false
    if weatherType == "rain" then
        M.isRaining = true
    elseif weatherType == "wind" then
        M.isWindy = true
        M.windDirection = math.random(1, 8)
    elseif weatherType == "scorching" then
        M.isScorching = true
    end
    -- "clear" = 三个标志全 false
end

--- 加权随机选择新天气（排除当前天气，夜间排除暴晒）
---@param currentWeather string 当前天气类型
---@return string 新天气类型
function M._rollNewWeather(currentWeather)
    -- 集风袋：唤风装备效果
    local eb = M.getEquipBonus and M.getEquipBonus() or {}
    local windCall = eb.windCallLevel or 0

    -- 唤风（999）：随机天气时必定刮风
    if windCall >= 999 then
        return "wind"
    end

    -- 祈风（33/66/100）：按百分比提高风权重；基础权重放大100倍以支持整数随机
    local WEATHER_WEIGHTS = { clear = 300, rain = 100, wind = 100, scorching = 100 }
    if windCall > 0 then
        WEATHER_WEIGHTS.wind = WEATHER_WEIGHTS.wind + windCall  -- 100+33=133, 100+66=166, 100+100=200
    end

    local hourNow = math.floor(((M.weatherTime - 1) % 1440) / 60)
    local isNight = (hourNow >= 18 or hourNow < 5)
    local pool = {}
    local totalWeight = 0
    for _, w in ipairs({"clear", "rain", "wind", "scorching"}) do
        -- 排除当前天气；夜间排除暴晒
        if w ~= currentWeather and not (isNight and w == "scorching") then
            local wt = WEATHER_WEIGHTS[w]
            totalWeight = totalWeight + wt
            pool[#pool + 1] = { type = w, weight = wt }
        end
    end
    local roll2 = math.random(1, totalWeight)
    local cumul = 0
    local newWeather = pool[1].type
    for _, entry in ipairs(pool) do
        cumul = cumul + entry.weight
        if roll2 <= cumul then
            newWeather = entry.type
            break
        end
    end
    return newWeather
end

--- 天气时间推进（核心鉴定逻辑）
--- weatherTime 为全局分钟计时器（1~518400），只增不重置（满一年回到1）
--- weatherChangeTimer 用于天气鉴定（天气变更后重置为0）
---@param amount number 推进的时间单位（默认1），每+1代表1分钟
function M.tickWeatherTime(amount)
    local inc = amount or 1
    -- 推进全局分钟计时器（1~YEAR_MINUTES，满后回到1）
    M.weatherTime = M.weatherTime + inc
    if M.weatherTime > M.YEAR_MINUTES then
        M.weatherTime = M.weatherTime - M.YEAR_MINUTES
        -- 确保不会因为大步进跳过多轮
        if M.weatherTime < 1 then M.weatherTime = 1 end
        -- 年末回绕：同步修正所有 buff 的绝对过期时间点，防止剩余时间显示异常
        local yr = M.YEAR_MINUTES
        if M.foodBuff and M.foodBuff.expireTime then
            M.foodBuff.expireTime = M.foodBuff.expireTime - yr
        end
        if M.forgetMeNotBuff and M.forgetMeNotBuff.expireTime then
            M.forgetMeNotBuff.expireTime = M.forgetMeNotBuff.expireTime - yr
        end
        if M.hugBuff and M.hugBuff.expireTime then
            M.hugBuff.expireTime = M.hugBuff.expireTime - yr
        end
        if M.potionBuffs then
            for _, buff in pairs(M.potionBuffs) do
                if buff.expireTime then
                    buff.expireTime = buff.expireTime - yr
                end
            end
        end
    end
    -- 推进天气鉴定计时器
    M.weatherChangeTimer = M.weatherChangeTimer + inc
    -- 检查是否到达下一个120阈值
    local nextThreshold = (M.weatherCheckCount + 1) * 120
    if M.weatherChangeTimer >= nextThreshold then
        M.weatherCheckCount = M.weatherCheckCount + 1
        local rate = 5 * M.weatherCheckCount  -- 5%, 10%, 15%, ... 最高100%
        local roll = math.random(1, 100)
        if roll <= rate then
            -- 鉴定成功：加权随机选择天气
            local current = M.getCurrentWeather()
            local newWeather = M._rollNewWeather(current)
            local oldName = WEATHER_NAMES[current] or current
            local newName = WEATHER_NAMES[newWeather] or newWeather
            M.setWeather(newWeather)
            -- 只重置鉴定计时器和鉴定次数，全局分钟计时器不重置
            M.weatherChangeTimer = 0
            M.weatherCheckCount = 0
            print("[Weather] 天气变更: " .. oldName .. " → " .. newName
                .. (newWeather == "wind" and ("（风向=" .. M.windDirection .. "）") or "")
                .. " (全局时间=" .. M.weatherTime .. "分钟)")
        else
            print("[Weather] 鉴定失败 (成功率=" .. rate .. "%, 掷骰=" .. roll .. ")")
        end
    end

    -- 晚上(18:00~5:00)不允许暴晒：如果时间推进后进入夜晚且当前是暴晒，强制重随机
    if M.isScorching then
        local hourNow = math.floor(((M.weatherTime - 1) % 1440) / 60)
        if hourNow >= 18 or hourNow < 5 then
            local oldName = WEATHER_NAMES[M.getCurrentWeather()]
            local newWeather = M._rollNewWeather("scorching")
            M.setWeather(newWeather)
            local newName = WEATHER_NAMES[newWeather] or newWeather
            M.weatherChangeTimer = 0
            M.weatherCheckCount = 0
            print("[Weather] 夜间不允许暴晒，自动切换: " .. oldName .. " → " .. newName)
        end
    end

    -- 商店补货：跨天且过了凌晨4点时补货（睡觉推进时间也能触发）
    local currentDay = math.floor((M.weatherTime - 1) / 1440) + 1
    local currentHour = math.floor(((M.weatherTime - 1) % 1440) / 60)
    -- 年度回绕修正：weatherTime 满一年回到1时 currentDay 变小，需重置 lastRestockDay
    if currentDay < M.lastRestockDay then
        M.lastRestockDay = 0
    end
    if currentDay > M.lastRestockDay and currentHour >= 4 then
        M.lastRestockDay = currentDay
        M.restockShops()
        print("[商店] ===== 凌晨4点补货！商店库存已刷新（第" .. currentDay .. "天）=====")
    end
end


-- ====================================================================
-- 采集关卡状态持久化（720点周期重置）
-- ====================================================================

--- 保存当前采集关卡的采集物状态（离开关卡时调用）
--- 根据采集关卡的怪物等级返回该关卡的采集物刷新间隔（回合数）
--- @param stageIdx number 关卡索引
--- @return number 刷新间隔回合数
function M.getGatherResetInterval(stageIdx)
    local stageDef = M.STAGE_DEFS[stageIdx]
    if not stageDef or not stageDef.monsters then return 300 end  -- 默认300
    -- 取该关卡怪物池中最高等级
    local maxLevel = 0
    for _, entry in ipairs(stageDef.monsters) do
        local def = entry.def
        if def and def.level and def.level > maxLevel then
            maxLevel = def.level
        end
    end
    -- 按等级分档
    if maxLevel <= 20 then return 10
    elseif maxLevel <= 40 then return 30
    elseif maxLevel <= 60 then return 60
    elseif maxLevel <= 80 then return 100
    else return 300
    end
end

--- 注意：切换关卡时 currentStage 可能已更新为新关卡，
--- 因此使用 _currentGatherStage 记录采集物实际所属关卡
function M.saveGatherStageState()
    local stageIdx = M._currentGatherStage
    if not stageIdx then return end  -- 当前不在采集关卡
    local spawns = M.STAGE_GATHER_SPAWNS[stageIdx]
    if not spawns then return end

    -- 收集仍存活的采集物
    local alive = {}
    for _, g in ipairs(M.gatherables) do
        if not g.vanishing and (g.harvestsLeft or 0) > 0 then
            alive[#alive + 1] = {
                x = g.x, y = g.y,
                defId = g.defId,
                harvestsLeft = g.harvestsLeft,
            }
        end
    end
    -- 即使 alive 为空也保存标记，区分"全部采完"和"从未进入"
    -- 保留已有的 resetCounter（每回合递增的独立刷新计数器）
    local prevCounter = 0
    local prev = M.gatherStageStates[stageIdx]
    if prev and prev.resetCounter then
        prevCounter = prev.resetCounter
    end
    M.gatherStageStates[stageIdx] = { alive = alive, depleted = (#alive == 0), resetCounter = prevCounter }
    M._currentGatherStage = nil
    print("[采集] 保存关卡 " .. stageIdx .. " 状态：剩余 " .. #alive .. " 个采集物")
end

--- 恢复采集关卡的采集物状态（进入关卡时调用）
--- @return boolean 是否有保存的状态可恢复
function M.restoreGatherStageState()
    local saved = M.gatherStageStates[M.currentStage]
    if not saved then return false end
    -- 兼容新格式 { alive = {...}, depleted = bool } 和旧格式（纯数组）
    local aliveList = saved.alive or saved
    -- 全部采完：返回 true 表示"有记录"，但不生成任何采集物
    if saved.depleted or #aliveList == 0 then
        M.gatherables = {}
        M._currentGatherStage = M.currentStage
        print("[采集] 关卡 " .. M.currentStage .. " 已采完，等待重置")
        return true
    end

    M.gatherables = {}
    for _, s in ipairs(aliveList) do
        local def = M.GATHER_DEFS[s.defId]
        if def then
            local gatherable = {
                x           = s.x,
                y           = s.y,
                defId       = def.id,
                name        = def.name,
                image       = M.getGatherImage(def.id, M.currentStage) or def.image,
                areaTag     = M.STAGE_GATHER_AREA[M.currentStage],
                itemId          = def.itemId,
                drops           = def.drops,
                rarityVariants  = def.rarityVariants,
                gatherTime  = def.gatherTime,
                color       = {def.color[1], def.color[2], def.color[3]},
                rarity      = def.rarity,
                lifeSkill   = def.lifeSkill,
                hiddenLevel = def.hiddenLevel or 0,
                isGatherable = true,
                harvestsLeft = s.harvestsLeft,
            }
            table.insert(M.gatherables, gatherable)
        end
    end
    M._currentGatherStage = M.currentStage
    print("[采集] 恢复关卡 " .. M.currentStage .. " 状态：" .. #M.gatherables .. " 个采集物")
    return true
end

--- 采集重置计时推进（每回合调用一次）
--- 按关卡独立计时，不同等级的采集区有不同刷新间隔
function M.tickGatherReset()
    -- 第一趟：递增各关卡计数器，收集到期的关卡
    local expired = {}
    for stageIdx, state in pairs(M.gatherStageStates) do
        if type(state) == "table" then
            state.resetCounter = (state.resetCounter or 0) + 1
            local interval = M.getGatherResetInterval(stageIdx)
            if state.resetCounter >= interval then
                expired[#expired + 1] = stageIdx
            end
        end
    end
    -- 第二趟：统一清除到期关卡（避免遍历中删 key 的潜在跳过问题）
    for _, stageIdx in ipairs(expired) do
        M.gatherStageStates[stageIdx] = nil
        local interval = M.getGatherResetInterval(stageIdx)
        print("[采集] 关卡 " .. stageIdx .. " 达到 " .. interval .. " 回合，已刷新")
        -- 如果玩家当前就在这个采集关卡：清除标记，离开后回来会重新随机
        if M.currentStage == stageIdx and M.STAGE_GATHER_SPAWNS[stageIdx] then
            M._currentGatherStage = nil
            print("[采集] 玩家在该采集区内，离开后回来将刷新")
        end
    end
    -- 兼容：全局计数器仍递增（旧存档迁移后可在几个周期内自然过渡）
    M.gatherResetCounter = (M.gatherResetCounter or 0) + 1

    -- 商店补货：每天凌晨4点补货一次
    local currentDay = math.floor((M.weatherTime - 1) / 1440) + 1
    local currentHour = math.floor(((M.weatherTime - 1) % 1440) / 60)
    -- 年度回绕修正
    if currentDay < M.lastRestockDay then
        M.lastRestockDay = 0
    end
    if currentDay > M.lastRestockDay and currentHour >= 4 then
        M.lastRestockDay = currentDay
        M.restockShops()
        print("[商店] ===== 凌晨4点补货！商店库存已刷新（第" .. currentDay .. "天）=====")
    end
end

-- ====================================================================
-- 猎犬伙伴系统
-- ====================================================================

--- 猎犬在家中的固定位置（按家园类型）
M.HOME_HOUND_POS = {
    small  = { x = 8, y = 8 },
    medium = { x = 9, y = 6 },
    large  = { x = 5, y = 6 },
}

--- 家中猎犬数据（非nil时在家场景渲染）
M.homeHound = nil  -- { x, y }

--- 猎犬属性继承比例表（Lv1 → MaxLv 线性插值）
M.HOUND_INHERIT = {
    hp       = { 1.00, 2.80 },
    mp       = { 0.55, 1.00 },
    atk      = { 0.35, 0.80 },
    critVal  = { 0.55, 1.00 },
    critDmg  = { 0.55, 1.00 },  -- 仅继承超过125%的部分
    hit      = { 0.55, 1.00 },
    atkSpeed = { 0.24, 0.60 },
    def      = { 0.55, 1.00 },
    mdef     = { 0.55, 1.00 },
    dodge    = { 0.55, 1.00 },
    hpRegen  = { 0.55, 1.00 },
    mpRegen  = { 0.55, 1.00 },
}

--- 创建猎犬伙伴，属性继承自玩家
function M.createHound()
    local p = M.player
    if not p then return nil end
    local slv = M.skillLevels["h_hound"] or 0
    if slv <= 0 then return nil end

    local maxLv = M.SKILL_MAX_LEVEL  -- 10
    local t = math.min((slv - 1) / math.max(maxLv - 1, 1), 1.0) -- 0~1 插值因子

    local function inherit(stat)
        local range = M.HOUND_INHERIT[stat]
        if not range then return 0 end
        local ratio = range[1] + (range[2] - range[1]) * t
        local val = (p[stat] or 0) * ratio
        return math.floor(val + 0.5)
    end

    local hound = {
        x = p.x, y = p.y, -- 临时位置，spawnHound 会调整
        facing = p.facing or "down",  -- 继承主人朝向
        name = "猎犬",
        hp = inherit("hp"),
        maxHp = inherit("hp"),
        mp = inherit("mp"),
        maxMp = inherit("mp"),
        atk = inherit("atk"),
        def = inherit("def"),
        mdef = inherit("mdef"),
        critVal = inherit("critVal"),
        critDmg = (function()
            -- 基础25% + 继承玩家超过25%的部分
            local extra = math.max(0, (p.critDmg or 50) - 25)
            local cdRange = M.HOUND_INHERIT.critDmg
            local ratio = cdRange[1] + (cdRange[2] - cdRange[1]) * t
            return 25 + math.floor(extra * ratio + 0.5)
        end)(),
        hit = inherit("hit"),
        dodge = inherit("dodge"),
        atkSpeed = inherit("atkSpeed"),
        hpRegen = inherit("hpRegen"),
        mpRegen = inherit("mpRegen"),
        moveRange = 4
            + ((M.skillLevels["h_beast_prof"]   or 0) >= maxLv and 1 or 0)
            + ((M.skillLevels["h_beast_master"] or 0) >= maxLv and 1 or 0)
            + ((M.skillLevels["h_wild"]         or 0) >= maxLv and 1 or 0),
        atkRange = 1,       -- 固定1
        color = { 80, 180, 80 },  -- 绿色
        image = "image/hound.png",
        isMonster = false,
        isCompanion = true,
        acted = false,
        level = p.level or slv,
    }

    -- 魅力加成：每点魅力 +10 HP
    local chaBonus = (p.cha or 0) * 10
    hound.hp = hound.hp + chaBonus
    hound.maxHp = hound.maxHp + chaBonus

    -- 驯兽专精：猎犬属性百分比加成
    local bmLv = M.skillLevels["h_beast_master"] or 0
    if bmLv > 0 then
        local bmDef = M.SKILL_DEFS["h_beast_master"]
        local function pctUp(val, pctPerLv)
            return math.floor(val * (1 + (pctPerLv or 0) * bmLv / 100))
        end
        hound.atk      = pctUp(hound.atk,      bmDef.houndAtkPctPerLv)
        hound.critVal  = pctUp(hound.critVal,   bmDef.houndCritPctPerLv)
        hound.hit      = pctUp(hound.hit,       bmDef.houndHitPctPerLv)
        hound.atkSpeed = pctUp(hound.atkSpeed,  bmDef.houndAtkSpdPctPerLv)
        hound.dodge    = pctUp(hound.dodge,     bmDef.houndDodgePctPerLv)
    end

    -- 野性：猎犬攻速+5/级（固定值）
    local wildLv = M.skillLevels["h_wild"] or 0
    if wildLv > 0 then
        local wDef = M.SKILL_DEFS["h_wild"]
        hound.atkSpeed = hound.atkSpeed + (wDef.wildHoundAtkSpdFlatPerLv or 5) * wildLv
    end

    return hound
end

--- 在玩家身旁寻找空位并生成猎犬
--- 在指定位置附近寻找空位放置一只猎犬，返回是否成功
---@param hound table
---@param px number 搜索中心 x
---@param py number 搜索中心 y
---@param occupied table<string,boolean> 已被占用的格子集合（cellKey → true）
---@return boolean
local function placeHoundNear(hound, px, py, occupied)
    local offsets = {
        {1,0}, {-1,0}, {0,1}, {0,-1},
        {1,1}, {1,-1}, {-1,1}, {-1,-1},
    }
    for _, off in ipairs(offsets) do
        local nx, ny = px + off[1], py + off[2]
        local key = M.cellKey(nx, ny)
        if M.isCellEmpty(nx, ny) and not occupied[key] then
            hound.x = nx
            hound.y = ny
            occupied[key] = true
            return true
        end
    end
    -- 扩大搜索范围（2格距离）
    for dy = -2, 2 do
        for dx = -2, 2 do
            if math.abs(dx) + math.abs(dy) <= 2 then
                local nx, ny = px + dx, py + dy
                local key = M.cellKey(nx, ny)
                if M.isCellEmpty(nx, ny) and not occupied[key] then
                    hound.x = nx
                    hound.y = ny
                    occupied[key] = true
                    return true
                end
            end
        end
    end
    return false
end

--- 原地刷新已有猎犬的属性（不重置血量和位置）
--- 用于技能加点等场景，避免猎犬满血瞬移回玩家身边
function M.refreshHoundStats()
    if M.homeMode then return end
    local slv = M.skillLevels["h_hound"] or 0
    if slv <= 0 then return end

    local existingHounds = {}
    for _, c in ipairs(M.companions) do
        if c.isHound then
            existingHounds[#existingHounds + 1] = c
        end
    end
    if #existingHounds == 0 then return end

    -- 用模板获取最新属性
    local tpl = M.createHound()
    if not tpl then return end

    for _, h in ipairs(existingHounds) do
        local hpRatio = h.hp / math.max(h.maxHp, 1)
        local mpRatio = h.mp / math.max(h.maxMp, 1)
        h.maxHp    = tpl.maxHp
        h.hp       = math.max(1, math.floor(tpl.maxHp * hpRatio))
        h.maxMp    = tpl.maxMp
        h.mp       = math.floor(tpl.maxMp * mpRatio)
        h.atk      = tpl.atk
        h.def      = tpl.def
        h.mdef     = tpl.mdef
        h.critVal  = tpl.critVal
        h.critDmg  = tpl.critDmg
        h.hit      = tpl.hit
        h.dodge    = tpl.dodge
        h.atkSpeed = tpl.atkSpeed
        h.hpRegen  = tpl.hpRegen
        h.mpRegen  = tpl.mpRegen
        h.moveRange = tpl.moveRange
        h.level    = tpl.level
    end
end

--- 装备变更时智能更新猎犬：脱下时立即减少多余猎犬，穿上时不立即增加
--- 新猎犬只在切换地图或死亡复活时通过 spawnHound() 补齐
function M.updateHounds()
    if M.homeMode then return end
    local slv = M.skillLevels["h_hound"] or 0

    -- 计算期望猎犬数量
    local desiredCount = 0
    if slv > 0 then
        desiredCount = 1
        local eb = M.getEquipBonus and M.getEquipBonus() or {}
        local bonus = eb.houndCountBonus or 0
        if bonus > 0 then
            desiredCount = 1 + math.floor(bonus)
        end
    end

    -- 收集现有猎犬（含已死亡但仍在列表中的）
    local existingHounds = {}
    for _, c in ipairs(M.companions) do
        if c.isHound then
            existingHounds[#existingHounds + 1] = c
        end
    end

    if #existingHounds == 0 then return end

    -- 如果期望数量为 0（不再有猎犬技能），移除所有
    if desiredCount == 0 then
        for i = #M.companions, 1, -1 do
            if M.companions[i].isHound then
                table.remove(M.companions, i)
            end
        end
        return
    end

    -- 脱装备导致数量超额：立即移除多余猎犬（从后往前）
    if #existingHounds > desiredCount then
        local toRemove = #existingHounds - desiredCount
        local removed = 0
        for i = #M.companions, 1, -1 do
            if removed >= toRemove then break end
            if M.companions[i].isHound then
                table.remove(M.companions, i)
                removed = removed + 1
            end
        end
        -- 重新收集剩余猎犬
        existingHounds = {}
        for _, c in ipairs(M.companions) do
            if c.isHound then
                existingHounds[#existingHounds + 1] = c
            end
        end
    end

    -- 刷新剩余猎犬属性（保留血量比例和位置）
    local tpl = M.createHound()
    if not tpl then return end
    for _, h in ipairs(existingHounds) do
        local hpRatio = h.hp / math.max(h.maxHp, 1)
        local mpRatio = h.mp / math.max(h.maxMp, 1)
        h.maxHp    = tpl.maxHp
        h.hp       = math.max(1, math.floor(tpl.maxHp * hpRatio))
        h.maxMp    = tpl.maxMp
        h.mp       = math.floor(tpl.maxMp * mpRatio)
        h.atk      = tpl.atk
        h.def      = tpl.def
        h.mdef     = tpl.mdef
        h.critVal  = tpl.critVal
        h.critDmg  = tpl.critDmg
        h.hit      = tpl.hit
        h.dodge    = tpl.dodge
        h.atkSpeed = tpl.atkSpeed
        h.hpRegen  = tpl.hpRegen
        h.mpRegen  = tpl.mpRegen
        h.moveRange = tpl.moveRange
        h.level    = tpl.level
    end
    -- 注意：穿上装备导致数量不足时，不在此处补充
    -- 新猎犬会在切换地图 / 死亡复活时由 spawnHound() 自动补齐
end

function M.spawnHound()
    -- 家园模式下不生成战斗猎犬（使用装饰性 homeHound 代替）
    if M.homeMode then return end

    -- 移除旧猎犬
    for i = #M.companions, 1, -1 do
        if M.companions[i].isHound then
            table.remove(M.companions, i)
        end
    end

    local hound = M.createHound()
    if not hound then return end
    hound.isHound = true

    -- 计算猎犬总数（基础 1 只 + 装备 houndCountBonus，需要猎犬技能）
    local houndCount = 1
    local slv = M.skillLevels["h_hound"] or 0
    if slv > 0 then
        local eb = M.getEquipBonus and M.getEquipBonus() or {}
        local bonus = eb.houndCountBonus or 0
        if bonus > 0 then
            houndCount = 1 + math.floor(bonus)
        end
    end

    -- 放置猎犬：记录已占用的格子避免重叠
    local px, py = M.player.x, M.player.y
    local occupied = {}
    -- 标记玩家位置
    occupied[M.cellKey(px, py)] = true

    -- 放置第一只猎犬
    if not placeHoundNear(hound, px, py, occupied) then return end
    table.insert(M.companions, hound)


    -- 放置额外猎犬
    for i = 2, houndCount do
        local extra = M.createHound()
        if not extra then break end
        extra.isHound = true
        extra.houndIndex = i  -- 标记序号（用于区分）
        extra.name = "猎犬" .. i
        extra.color = { 60 + i * 20, 180, 60 + i * 10 }  -- 略微不同的颜色
        if not placeHoundNear(extra, px, py, occupied) then break end
        table.insert(M.companions, extra)
        print("[猎犬" .. i .. "] 生成在 (" .. extra.x .. "," .. extra.y .. ") HP=" .. extra.hp .. " ATK=" .. extra.atk)
    end
end

-- ====================================================================
-- 初始化游戏
-- ====================================================================
--- 记录玩家移动路径的每一格到轨迹（猎犬跟随用）
--- @param path table|nil  reconstructPath 返回的路径 {{x1,y1},{x2,y2},...}
function M.recordPlayerPath(path)
    if not path or #path < 2 then return end
    local trail = M._playerPosTrail
    -- 从路径第1格开始逐格追加（跳过与末尾重复的起点）
    for i = 1, #path do
        local px, py = path[i][1], path[i][2]
        local last = trail[#trail]
        if not last or last.x ~= px or last.y ~= py then
            trail[#trail + 1] = { x = px, y = py }
        end
    end
    -- 保留最近10格轨迹
    while #trail > 10 do
        table.remove(trail, 1)
    end
end

function M.initGame()
    M.monsters = {}
    M.companions = {}
    M._playerPosTrail = {}
    M.holyTrees = {}
    M.iceWalls = {}
    M.burningGrounds = {}
    M.pendingBurningGrounds = {}
    M.blizzardZones = {}
    M.thunderClouds = {}
    M.lightningWarnings = {}
    M.fireCorpses = {}
    M.gatherables = {}
    M.gatherStageStates = {}
    M.gatherResetCounter = 0
    M.lastRestockDay = 0
    M.rebirthCooldownDay = nil
    M.gatheringState = nil
    M.gatherResultAnim = nil
    M.furnitureInteract = nil
    M.playerDebuffs = {}
    M.damageTexts = {}
    M.pendingMpRestores = {}
    M.selectedUnit = nil

    -- 副本状态重置
    M.isDungeon = false
    M.dungeonId = nil
    M.dungeonPhase = 0
    M.dungeonCheckpoint = 0
    M.dungeonSpawnCount = 0
    M.dungeonWaveIndex = 0
    M.dungeonPhaseComplete = false
    M.dungeonPhaseTurn = 0
    M.dungeonScrollAnim = nil
    M.arenaWaitForExit = false
    M.arenaExitTiles = nil
    M.arenaChests = {}
    M.arenaChestInteract = nil
    M.arenaChestPending = nil
    M.arenaExitPending = false
    M.arenaPendingTarget = nil
    M.arenaDungeonCleared = false

    -- 模式/UI 状态重置
    M.autoMode = false
    M.autoTimer = 0
    M.homeMode = false
    M.homeType = "small"
    M.trainingMode = false
    M.trainingDmgLog = {}
    M.trainingTurnDmg = 0
    M.trainingTotalDmg = 0
    M.trainingTurnCount = 0
    M.shopMode = false
    M.shopBuildingKey = nil
    M.warehouseMode = false
    M.enhanceMode = false
    M.enhanceResult = nil
    M.enhanceSlotItem = nil
    M.enhanceSlotSource = nil
    M.enhanceSlotSourceId = nil
    M.repairMode = false
    M.repairResult = nil
    M.repairSlotItem = nil
    M.repairSlotSource = nil
    M.repairSlotSourceId = nil
    M.forgeMode = false
    M.forgeResult = nil
    M.forgeScrollY = 0
    M.forgeBtnRects = {}
    M.alchemyMode = false
    M.homeAlchemyMode = false
    M.alchemyResult = nil
    M.homeCookingMode = false
    M.homeSmithySelectMode = false
    M.homeSmithySelectRects = nil
    M.homeForgeMode = false
    M.homeCraftMode = false
    M.homeEnchantMode = false
    M.enchantMode = false
    M.enchantSlotItem = nil
    M.enchantSlotSource = nil
    M.enchantSlotSourceId = nil
    M.enchantResult = nil
    M.enchantCloseRect = nil
    M.enchantDropRect = nil
    M.enchantBtnRect = nil
    M.homeSocketMode = false
    M.alchemyScrollY = 0
    M.alchemyBtnRects = {}
    M.refineMode = false
    M.refineResult = nil
    M.refineSlotItem = nil
    M.refineSlotSource = nil
    M.refineSlotSourceId = nil
    M.craftMode = false
    M.craftTab = "enhance"
    M.craftSlotItem = nil
    M.craftSlotSource = nil
    M.craftSlotSourceId = nil
    M.craftEnhanceResult = nil
    M.craftRefineResult = nil
    M.craftRepairResult = nil
    M.craftExtractResult = nil
    M.craftExtractBtnRect = nil
    M.extractSourceItem = nil
    M.extractTargetItem = nil
    M.extractSourceSource = nil
    M.extractSourceSourceId = nil
    M.extractTargetSource = nil
    M.extractTargetSourceId = nil
    M.extractSourceDropRect = nil
    M.extractTargetDropRect = nil
    M.craftTabRects = {}
    M.craftRefineSlotBtnRects = {}
    M.socketMode = false
    M.socketResult = nil
    M.socketScrollY = 0
    M.socketEquipItem = nil
    M.socketEquipSource = nil
    M.socketEquipSourceId = nil
    M.socketSelectedGemSlot = nil
    M.socketSelectedGemBag = nil
    M.socketGemBtnRects = {}
    M.socketTab = "socket"
    M.socketTabRects = {}
    M.reforgeVeilItem = nil
    M.reforgeGemItem = nil
    M.reforgeVeilSource = nil
    M.reforgeVeilSourceId = nil
    M.reforgeGemSource = nil
    M.reforgeGemSourceId = nil
    M.reforgeVeilDropRect = nil
    M.reforgeGemDropRect = nil
    M.reforgeBtnRect = nil
    M.reforgeCollectBtnRect = nil

    -- 背包/仓库 UI 交互状态重置
    M.invMultiSelect = false
    M.invSelected = {}
    M.warehouseMultiSelect = false
    M.warehouseSelected = {}
    M.warehouseScrollY = 0
    M.warehouseDragging = false
    M.warehouseScrollBarDragging = false
    M.dragWarehouseIdx = nil

    -- 物品提示框重置
    M.tooltipItem = nil
    M.tooltipPinned = false
    M.tooltipPinnedPos = nil
    M.skillTooltipId = nil
    M.skillTooltipPinned = false

    -- 弹窗状态重置
    M.skillEquipPopupVisible = false
    M.skillEquipPopupSlot = nil
    M.destroyConfirmVisible = false
    M.destroyConfirmItem = nil
    M.destroyConfirmSlotIdx = nil
    M.destroyConfirmBatch = false
    M.abyssConfirmVisible = false
    M.abyssConfirmStageData = nil

    -- 商店 UI 重置
    M.shopScrollY = 0
    M.shopScrollBarDragging = false
    M.shopListDragging = false
    M.shopBuyConfirmVisible = false
    M.shopBuyConfirmItem = nil
    M.shopBuyQuantity = 1
    M.shopBuyMsg = nil
    M.shopBuyQtySliderDragging = false

    -- 兑换商店重置
    M.exchangeMode = false
    M.exchangeItemRects = {}
    M.exchangeScrollY = 0
    M.exchangeBuyConfirmVisible = false
    M.exchangeBuyConfirmItem = nil
    M.exchangeBuyQuantity = 1
    M.exchangeBuyMsg = nil
    M.exchangeCloseRect = nil
    M.exchangeBuyYesRect = nil
    M.exchangeBuyNoRect = nil
    M.exchangeScrollBarDragging = false
    M.exchangeScrollBarTrack = nil
    M.exchangeScrollBarRect = nil
    M.exchangeListDragging = false
    M.exchangeListClipRect = nil
    M.exchangeContentH = 0
    M.exchangeVisibleH = 0

    -- 广告加载状态重置
    M.adLoading = false
    M.adCancelRect = nil

    -- 遗失物品系统重置
    M.lostItemsMode = false
    M.lostItemsScrollBarDragging = false
    M.lostItemsDragging = false

    -- 房屋相关重置
    M.housePurchased = false
    M.homeMode = false
    M.homeType = "small"
    M.houseBuyDialogVisible = false
    M.houseBuyYesRect = nil
    M.houseBuyNoRect = nil
    M.houseBuySuccessVisible = false
    M.houseBuySuccessOkRect = nil
    M.homeUpgradeDialogVisible = false
    M.homeUpgradeYesRect = nil
    M.homeUpgradeNoRect = nil
    M.homeUpgradeBtnRect = nil
    M.streetSleepActive = false
    M.streetSleepTimer = 0
    M.streetSleepBtnRect = nil

    -- 对话管理器重置
    local DialogueManager = require("DialogueManager")
    DialogueManager.active = false
    DialogueManager.currentId = nil
    DialogueManager.currentLines = nil
    DialogueManager.lineIndex = 0
    DialogueManager.waitingForChoice = false
    DialogueManager.choiceResult = nil
    DialogueManager._dynamicOnComplete = nil

    -- 底部面板/标签重置
    M.activeBottomTab = 5
    M.showStatsSummary = false
    M.statsTabMode = "attack"
    M.showBuffSummary = false
    M.buffSummaryScrollY = 0
    M.showMonsterBuffSummary = false
    M.monsterBuffBtnRect = nil
    M.monsterBuffScrollY = 0
    M.topBarLockedTarget = nil
    M.dailyBulletinDoneCount = 0
    M.bulletinQuestTotalDone = 0
    M.showSettings = false
    M.showTestStagePanel = false
    M.showTestItemPanel = false

    -- 拖拽状态重置
    M.dragSlotIdx = nil
    M.itemDragActive = false
    M.lockedDebuffTooltip = nil
    M.statInfoHover = nil
    M.statInfoLocked = nil
    M.combatStatInfoHover = nil
    M.combatStatInfoLocked = nil

    -- 地图面板重置
    M.mapScrollY = 0
    M.mapDragging = false
    M.selectedMapLocation = nil
    M.selectedMapStage = nil
    M.mapStageScrollOffset = 0
    M.mapStageScrollbarDragging = false
    M.mapStageTouchStartY = nil
    M.mapTipText = nil
    M.mapTipTimer = 0
    M.mapStageZone = "battle"

    -- 法师专用状态重置
    M.mageActionTaken = false
    M.mageWaitingForClick = nil
    M.mageChantTarget = nil
    M.mageChantSkill = nil
    M.mageTargetCell = nil

    -- 额外特效重置
    M.deathEffects = {}
    M.phantomDissolveEffects = {}

    -- 自动存档状态重置（防止旧角色的脏标记导致无意义保存）
    M.autoSave.dirty = false
    M.autoSave.cooldown = 0
    M.autoSave.enabled = false  -- 由调用方在进入游戏时重新启用

    -- 复活状态重置
    M.respawnTimer = 0
    M.respawnMoveCD = 0
    M.deathX = 0
    M.deathY = 0
    M.tombstoneAnim = nil
    M.tombstoneDropAnim = nil
    M.reviveEffect = nil

    -- 消耗品冷却/队列重置
    M.consumableCooldown = 0
    M.pendingConsumableSlots = {}

    -- 场景过渡重置
    M.sceneTransition = nil
    M.brawlCinematic = nil
    M.eventSceneBg = nil
    M.currentBattleBg = "image/bg_grass.png"
    M.currentAreaName = "清水镇"
    M.currentStageName = "清水镇"
    M.movableCells = {}
    M.movableParents = {}
    M.attackableCells = {}
    M.currentStage = 1
    M.turnNumber = 1
    M.gold = 0
    M.score = 0
    M.awakeningCompleted = false
    M.bgmMuted = false
    M.eventCompleted = {}
    M.signInStartDay = 0
    M.signInRewards = {}
    M.signInDayPlayTime = {}
    M.signInPanelVisible = false
    -- 日常签到是账户级云端数据，切角色时保留内存状态，不清零不重新加载
    -- 修复：之前切角色会先异步 save 再清零再异步 load，存在竞态条件
    --       导致 load 拿到旧数据（奖励未标记已领取），可重复领取
    local SignInSystem = package.loaded["SignInSystem"]
    if SignInSystem then
        -- 仅保存当前在线时长到云端，不重置任何标志
        if SignInSystem._dailyCloudLoaded and not SignInSystem._dailyCloudLoadFailed then
            SignInSystem.saveDailyToCloud()
        end
        -- _dailyCloudLoaded / GS.dailySignIn* 保持不变，跨角色共享
    end
    -- M.dailySignInDayKey / dailySignInRewards / dailySignInPlayTime 不再重置
    M.debugForceDay6 = false
    M.attackEffects = {}
    M.pendingBounces = {}
    M.strikeEffects = {}
    M.powerShotEffects = {}
    M.stunShotEffects = {}
    M.snipeEffects = {}
    M.whirlwindEffects = {}
    M.iceRingEffects = {}
    M.fireballEffects = {}
    M.meteorEffects = {}
    M.lightningChainEffects = {}
    M.thunderStrikeEffects = {}
    M.blizzardIceEffects = {}
    M.burnEffects = {}
    M.thunderCloudStrikeEffects = {}
    M.healEffects = {}
    M.divineGraceEffects = {}
    M.holyTreeWaveEffects = {}
    M.blessEffects = {}
    M.sandBlindEffects = {}
    M.tauntEffects = {}
    M.cleaveEffects = {}
    M.meleeSplashEffects = {}
    M.rangedExplosionEffects = {}
    M.holyAoeEffects = {}
    M.strikeAoeEffects = {}
    M.magicShieldEffects = {}
    M.iceWallCreateEffects = {}
    M.blinkEffects = {}
    M.phantomAttackEffects = {}
    M.radianceWaveEffects = {}
    M.apocalypseAoeEffects = {}
    M.swordQiEffects = {}
    M.pendingEndPlayerTurn = false
    M._pendingEndTurnTimer = nil
    M.screenShake = nil
    M.superiorDropFlash = nil
    M.stormBuffTurns = 0
    M.forgetMeNotBuff = nil
    M.forgetMeNotLevel = 0
    M.forgetMeNotPermanent = false
    M.hugBuff = nil
    M.foodBuff = nil
    M.potionBuffs = {}
    M.lastDanceDayWatched = -1
    M.stealthActive = false
    M.stealthTurns = 0
    M.stealthSmokeEffect = nil
    M.focusBuffTurns = 0
    M.fireShieldTurns = 0
    M.fireShieldReducePct = 0
    M.fireShieldReflectPct = 0
    M.magicShieldActive = false
    M.chantStages = 0
    M.chantStagesMax = 0
    M.chanting = nil
    M.markedTarget = nil
    M.tombstoneAnim = nil
    M.tombstoneDropAnim = nil
    M.closeActionMenu()

    -- 创建玩家角色
    M.player = {
        x = 6, y = 7,
        facing = "down",  -- 朝向：up/down/left/right
        name = M.PLAYER_DEF.name,
        stats = {},
        color = M.PLAYER_DEF.color,
        isMonster = false, acted = false,
        level = M.PLAYER_DEF.level,
        exp = M.PLAYER_DEF.exp,
        statPoints = M.PLAYER_DEF.statPoints,
    }
    for k, v in pairs(M.PLAYER_DEF.stats) do
        M.player.stats[k] = v
    end
    M.recalcStats(M.player)
    M.displayExp = M.player.exp
    M.displayExpLevel = M.player.level
    M.displayHp = M.player.hp
    M.displayMp = M.player.mp
    M.currentShopTier = 0
    M.updateShopByLevel()

    -- 初始化装备（空）
    M.equipment = {}

    -- 初始化技能等级和装备槽（1级起就有1点技能点）
    M.skillPoints = 1
    M.skillLevels = {}
    M.skillCooldowns = {}
    M.activeSkills = {}

    -- 重置背包/仓库容量为初始值
    M.bagSlots = 15
    M.warehouseSlots = 12

    -- 初始化物品栏（空）
    M.inventory = {}
    for i = 1, M.bagSlots do
        M.inventory[i] = nil
    end
    -- 初始化仓库（多储物箱）
    M.warehouses = { {}, {}, {}, {} }
    M.activeWarehouseId = 1
    M.warehouse = M.warehouses[1]

    -- 初始化冒险者等级
    M.adventurerRank = 1
    M.monsterKillCounts = {}
    M.rareKillPitySince = 0
    M.stageKillCounts = {}
    M.maxStageReached = 1
    M.stageClearedOnce = {}  -- 采集区是否清空过一次（用于采集区解锁下一关）
    M.dungeonsCleared = {}
    M.dungeonClearCounts = {}
    M.areaKillCounts = {}

    -- 已知 NPC 名字（玩家通过剧情/对话得知真名后记录）
    M.knownNPCs = {}

    -- TalkQA 已问过的一次性问题（key = "buildingKey_qaIndex"）
    M.talkQAAsked = {}

    -- NPC 好感度重置（已废弃的 npcFavorability 已合并到 npcAffinity）
    M.npcAffinity = {}
    M.customPetNames = {}

    -- 解锁标志重置（定义在 GameState_Shop.lua，但需在此处重置）
    M.infiniteTowerUnlocked = false
    M.sharedStorageUnlocked = false
    M.sharedStorage = {}
    M.sharedStorageMode = false
    M.dragSharedStorageIdx = nil
    M.abyssUnlocked = false
    M.abyssPoints = 0            -- 深渊积分（通过深渊兑换获得，用于兑换深渊装备）

    -- 旅行任务完成标记重置
    M.eliyaTravelDone = {}
    M.angelicaTravelDone = {}
    M.difenTravelDone = {}

    -- 广告每日计数重置
    M.adDailyCount = 0
    M.adDailyDate = ""

    -- currentClass 不在此重置：它是角色身份属性，仅由 createNewCharacter / applySaveData 写入

    -- 兑换码记录重置
    M.redeemedCodes = {}

    -- 任务快照重置
    M._angelicaSeaKillSnapshot = nil

    -- 天气系统重置
    M.isRaining = true
    M.isWindy = false
    M.windDirection = 1
    M.isScorching = false
    M.weatherTime = 1
    M.weatherChangeTimer = 0
    M.weatherCheckCount = 0

    -- 深渊系统每日次数重置
    M.abyssChallengeDay = -1
    M.abyssChallengeUsed = 0
    M.abyssWorldDay = -1
    M.abyssWorldUsed = 0
    M.abyssWorldActive = false
    M.abyssWorldLives = 0

    -- Elfvah 语言学习系统重置
    M.elfvahBooksRead = nil
    M.elfvahLanguageLearned = false
    M.elfvahElfTalked = false

    -- NPC 交谈记录（支线任务追踪用）
    M.npcTalkedRecord = {}

    -- 每日交谈好感度记录
    M.npcTalkAffinityDate = {}
    M.npcKissAffinityDate = {}
    M.npcConfessAffinityDate = {}
    M.npcProposalAffinityDate = {}
    M.homeKissDate = -1
    M.homeHugDate = -1
    M.homeHugDate2 = -1

    -- 伴侣系统
    M.partnerNpcKey = nil            -- 伴侣 npcKey（如 "tavern_keeper"）
    M.partnerLivingTogether = false  -- 是否同住
    M.homeNpc = nil                  -- 运行时家中NPC实体（不持久化）
    M.homeNpcLastShouldState = nil   -- 用于检测时间变化触发出现/离开动画

    -- 赠送系统重置
    M.giftMode = false
    M.giftNpcKey = nil
    M.giftNpcName = nil
    M.giftSlotItem = nil
    M.giftSlotSource = nil
    M.giftSlotSourceId = nil
    M.giftResultText = nil
    M.giftResultLiked = nil
    M.giftBuildingKey = nil

    -- 任务提交系统重置
    M.questSubmitMode = false
    M.questSubmitQuestId = nil
    M.questSubmitDef = nil
    M.questSubmitNpcName = nil
    M.questSubmitBuildingKey = nil
    M.questSubmitSlotItem = nil
    M.questSubmitSlotSource = nil
    M.questSubmitSlotSourceId = nil
    M.questSubmitRejectMsg = nil

    -- 初始化生活技能
    M.lifeSkillExp = {}
    M.lifeSkillTiers = {}

    -- 初始化对话标记
    M.dialogueFlags = {}

    -- 初始化自动战斗设置
    M.showAutoBattleSettings = false
    M.autoConsumables = {}
    M.autoConsumableThresholds = { 50, 50 }
    M.autoConsumablePopupSlot = nil
    M.autoConsumablePopupItems = {}
    M.autoConsumablePopupRect = nil
    M.autoConsumablePopupItemRects = {}
    M.autoFood = nil
    M.autoBuffPotion = nil
    M.autoFoodSlotArea = nil
    M.autoBuffPotionSlotArea = nil
    M.autoFoodBuffPopupSlot = nil
    M.autoFoodBuffPopupItems = {}
    M.autoFoodBuffPopupRect = nil
    M.autoFoodBuffPopupItemRects = {}
    M.invScrollY = 0
    M.invDragging = false

    -- 猎犬伙伴：游戏开始时自动生成
    M.spawnHound()

    -- 重置任务系统（新角色/新游戏时清除旧状态）
    require("QuestManager").init()

    M.gameState = M.STATE_PLAYER
    M.turnPhase = M.PHASE_MOVE

    print("=== 游戏开始! 回合 " .. M.turnNumber .. " ===")
end

-- ============================================================
-- 子模块挂载
-- ============================================================
require("GameState_Skills").init(M)
require("GameState_Items").init(M)
require("GameState_Shop").init(M)
require("GameState_Save").init(M)
require("BulletinBoard").init(M)
require("QuestManager").init()

-- ====================================================================
-- NPC 名字系统：未知时显示"？？？"，剧情揭示后显示真名
-- ====================================================================
M.NPC_REGISTRY = {
    guild_master       = { name = "芙蕾雅" },
    guild_receptionist = { name = "妮可" },
    blacksmith_owner   = { name = "斯特朗" },
    potion_shop_owner  = { name = "莉娜" },
    jewelry_shop_owner = { name = "朱莉" },
    armor_shop_owner   = { name = "迪芬" },
    tavern_keeper      = { name = "爱丽丝" },
    tavern_dancer      = { name = "安吉莉娅" },
    forest_elf         = { name = "艾莉雅" },
}

-- NPC 所属建筑映射（用于查询营业时间）
M.NPC_BUILDING_MAP = {
    guild_master       = "guild",
    guild_receptionist = "guild",
    tavern_keeper      = "tavern",
    tavern_dancer      = "tavern",
    potion_shop_owner  = "potion_shop",
    jewelry_shop_owner = "jewelry_shop",
    blacksmith_owner   = "blacksmith",
    armor_shop_owner   = "armor_shop",
}

-- 没有建筑的NPC自定义在家时间段
M.NPC_HOME_SCHEDULE = {
    forest_elf = { homeStart = 15, homeEnd = 4 },  -- 下午3点到次日凌晨4点
}

-- 伴侣睡觉时间表
M.NPC_SLEEP_SCHEDULE = {
    guild_master       = { sleepStart = 23, sleepEnd = 6 },
    guild_receptionist = { sleepStart = 23, sleepEnd = 6 },
    potion_shop_owner  = { sleepStart = 1,  sleepEnd = 8 },
    jewelry_shop_owner = { sleepStart = 0,  sleepEnd = 7 },
    tavern_keeper      = { sleepStart = 3,  sleepEnd = 10 },
    tavern_dancer      = { sleepStart = 3,  sleepEnd = 10 },
    forest_elf         = { sleepStart = 0,  sleepEnd = 3 },
}

-- NPC 默认爱称（挚爱等级使用）
-- "名字" 表示使用玩家名字，其他为固定文本
M.NPC_PET_NAMES = {
    guild_master       = "名字",     -- 芙蕾雅 → 用玩家名字
    guild_receptionist = "亲爱的",   -- 妮可
    jewelry_shop_owner = "亲爱的",   -- 朱莉
    potion_shop_owner  = "名字",     -- 莉娜 → 用玩家名字
    tavern_keeper      = "老公",     -- 爱丽丝
    tavern_dancer      = "老公",     -- 安吉莉娅
    forest_elf         = "夫君",     -- 艾莉雅
}

--- 获取 NPC 对玩家的爱称（解析后的实际文本）
--- 优先使用玩家自定义爱称，否则使用默认值
---@param npcId string
---@return string
function M.getNPCPetName(npcId)
    -- 优先使用玩家自定义爱称
    local custom = M.customPetNames and M.customPetNames[npcId]
    if custom and custom ~= "" then
        return custom
    end
    -- 默认爱称
    local pet = M.NPC_PET_NAMES[npcId]
    if pet == "名字" then
        return M.charName or ""
    end
    return pet or ""
end

-- 反向映射：speaker 名字 → npcId
M._speakerToNPC = {}
for id, info in pairs(M.NPC_REGISTRY) do
    M._speakerToNPC[info.name] = id
end

--- 标记玩家已得知某 NPC 的真名
---@param npcId string NPC_REGISTRY 中的 key
function M.learnNPCName(npcId)
    M.knownNPCs[npcId] = true
end

--- 将对话 speaker 名字解析为真名或"？？？"
---@param speaker string 原始 speaker 字符串（如"斯特朗"、"莉娜"）
---@return string 解析后的显示名
function M.resolveNPCSpeaker(speaker)
    local npcId = M._speakerToNPC[speaker]
    if not npcId then return speaker end -- 非 NPC 名字（旁白、玩家名等），原样返回
    if M.knownNPCs[npcId] then
        return speaker -- 已知，显示真名
    else
        return "？？？"
    end
end

-- ====================================================================
-- NPC 好感度系统（统一使用 npcAffinity，旧 npcFavorability 已废弃）
-- ====================================================================
-- 好感度等级阈值（基于 npcAffinity 值，范围 -30~600+）
-- level 0: 低于陌生（好感值 < 0，即反感）→ 对话显示"……"
-- level 1~7: 正常好感等级
M.FAVOR_LEVELS = {
    { name = "陌生", threshold = 0 },    -- 1: 0~30
    { name = "友善", threshold = 31 },   -- 2: 31~100
    { name = "在意", threshold = 101 },  -- 3: 101~200
    { name = "重视", threshold = 201 },  -- 4: 201~300
    { name = "亲密", threshold = 301 },  -- 5: 301~400
    { name = "爱慕", threshold = 401 },  -- 6: 401~499
    { name = "挚爱", threshold = 500 },  -- 7: 500+
}

--- 好感度等级上限（同性别NPC无法达到爱慕）
M.NPC_FAVOR_CAP = {
    blacksmith_owner = 5,  -- 斯特朗：上限亲密
    armor_shop_owner = 5,  -- 迪芬：上限亲密
}

--- 获取 NPC 好感度等级索引（0-7）
--- 返回 0 表示低于陌生（好感值 < 0），调用方应显示"……"
---@param npcId string
---@return number 等级索引（0=低于陌生, 1=陌生, 2=友善, 3=在意, 4=重视, 5=亲密, 6=爱慕, 7=挚爱）
function M.getNPCFavorLevel(npcId)
    local value = M.getAffinity(npcId)
    if value < 0 then return 0 end
    local level = 1
    for i = #M.FAVOR_LEVELS, 1, -1 do
        if value >= M.FAVOR_LEVELS[i].threshold then
            level = i
            break
        end
    end
    local cap = M.NPC_FAVOR_CAP[npcId]
    if cap and level > cap then level = cap end
    -- 挚爱（7）需要已成为伴侣，否则停留在爱慕（6）
    if level >= 7 and M.partnerNpcKey ~= npcId then
        level = 6
    end
    return level
end

-- ====================================================================
-- 伴侣系统：伴侣折扣
-- ====================================================================
--- 获取伴侣带来的费用折扣倍率
--- 朱莉(jewelry_shop_owner)：交往→镶嵌/拆除七折，结婚→三折
--- 莉娜(potion_shop_owner)：交往→炼金免委托费，结婚→药剂店购买对折
---@param discountType string "socket"|"alchemy_commission"|"potion_buy"
---@return number multiplier 费用乘数（1.0=无折扣）
function M.getPartnerDiscount(discountType)
    if discountType == "socket" then
        -- 朱莉伴侣：镶嵌/拆除费用折扣
        if M.partnerNpcKey == "jewelry_shop_owner" then
            if M.partnerLivingTogether then return 0.1 end  -- 结婚→一折
            return 0.3  -- 交往→三折
        end
    elseif discountType == "jewelry_buy" then
        -- 朱莉伴侣且已结婚：首饰店购买价对折
        if M.partnerNpcKey == "jewelry_shop_owner" and M.partnerLivingTogether then
            return 0.5
        end
    elseif discountType == "alchemy_commission" then
        -- 莉娜伴侣：炼金委托费免除
        if M.partnerNpcKey == "potion_shop_owner" then
            return 0  -- 交往即免委托费（交往/结婚都免）
        end
    elseif discountType == "potion_buy" then
        -- 莉娜伴侣且已结婚：药剂店购买价对折
        if M.partnerNpcKey == "potion_shop_owner" and M.partnerLivingTogether then
            return 0.5
        end
    end
    return 1.0
end

-- ====================================================================
-- 伴侣系统：判断伴侣NPC是否应该在家中
-- ====================================================================
--- 判断指定NPC当前是否应在家中（建筑打烊+5分钟 ~ 开门-5分钟）
---@param npcKey string
---@return boolean
function M.shouldPartnerBeHome(npcKey)
    if not M.partnerLivingTogether or M.partnerNpcKey ~= npcKey then return false end
    if M.homeType ~= "large" then return false end
    local buildingKey = M.NPC_BUILDING_MAP[npcKey]
    if not buildingKey then
        -- 没有建筑的NPC使用自定义在家时间
        local custom = M.NPC_HOME_SCHEDULE and M.NPC_HOME_SCHEDULE[npcKey]
        if not custom then return false end
        local BoardOverlay = require("BoardOverlay")
        local hour = BoardOverlay.getGameHour()
        if custom.homeEnd < custom.homeStart then
            -- 跨午夜（如15:00-4:00）
            return hour >= custom.homeStart or hour < custom.homeEnd
        else
            return hour >= custom.homeStart and hour < custom.homeEnd
        end
    end
    local BoardOverlay = require("BoardOverlay")
    local def = BoardOverlay.buildingInteriors[buildingKey]
    if not def or not def.openHour then return false end
    local hour = BoardOverlay.getGameHour()
    local closeH = def.closeHour + 5 / 60   -- 打烊+5分钟
    local openH  = def.openHour  - 5 / 60   -- 开门-5分钟
    if def.closeHour < def.openHour then
        -- 跨午夜（如酒馆 10:30-2:00）：休息段 = [closeH, openH)
        return hour >= closeH and hour < openH
    else
        -- 正常（如公会 7-19）：休息段 = [closeH, 24) ∪ [0, openH)
        return hour >= closeH or hour < openH
    end
end

--- 判断伴侣当前是否在睡觉
---@param npcKey string
---@return boolean
function M.isPartnerSleeping(npcKey)
    local sched = M.NPC_SLEEP_SCHEDULE[npcKey]
    if not sched then return false end
    local BoardOverlay = require("BoardOverlay")
    local hour = BoardOverlay.getGameHour()
    if sched.sleepEnd < sched.sleepStart then
        -- 跨午夜（如23:00-6:00）
        return hour >= sched.sleepStart or hour < sched.sleepEnd
    else
        return hour >= sched.sleepStart and hour < sched.sleepEnd
    end
end

--- 获取伴侣在家阶段："sleeping" / "awake_morning" / "awake_evening"
--- awake_morning = 睡醒后到出门上班前（位于 3,3）
--- awake_evening = 回家后到入睡前（位于 10,4）
---@param npcKey string
---@return string phase
function M.getPartnerHomePhase(npcKey)
    if M.isPartnerSleeping(npcKey) then return "sleeping" end
    local sched = M.NPC_SLEEP_SCHEDULE[npcKey]
    if not sched then return "awake_evening" end
    local BoardOverlay = require("BoardOverlay")
    local hour = BoardOverlay.getGameHour()
    local sleepEnd = sched.sleepEnd
    -- 计算出门上班时间（morning 的结束点）
    local leaveTime
    local buildingKey = M.NPC_BUILDING_MAP[npcKey]
    if buildingKey then
        local def = BoardOverlay.buildingInteriors[buildingKey]
        if def and def.openHour then
            leaveTime = def.openHour - 5 / 60
        end
    end
    if not leaveTime then
        local custom = M.NPC_HOME_SCHEDULE[npcKey]
        if custom then leaveTime = custom.homeEnd end
    end
    if not leaveTime then return "awake_evening" end
    -- morning = [sleepEnd, leaveTime) 这段很短的时间
    if sleepEnd <= leaveTime then
        if hour >= sleepEnd and hour < leaveTime then
            return "awake_morning"
        end
    else
        if hour >= sleepEnd or hour < leaveTime then
            return "awake_morning"
        end
    end
    return "awake_evening"
end

return M
