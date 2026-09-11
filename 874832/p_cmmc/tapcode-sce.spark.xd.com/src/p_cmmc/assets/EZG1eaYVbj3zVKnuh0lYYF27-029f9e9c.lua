-- ============================================================
-- 纵跃魔塔 - 数据定义模块
-- 游戏配置、角色、怪物、卡牌、技能、宝石等静态数据
-- ============================================================

GRID = 11
TOTAL_FLOORS = 50
CONTENT_MAX_FLOOR = 18  -- 当前已开放内容最高层，后续楼层暂不可访问

-- 怪物数据: {名称, HP, ATK, DEF, 金币, 颜色RGB, 精灵图路径}
-- 按难度分层: 1,2(Tier1) → 3,4(Tier2) → 5,6(Tier3) → 8,9(Tier4) → A,C(Tier5) → 7(Boss)
MONSTER_DEF = {
    -- Tier 1: 第1-10层
    ["1"] = {name = "绿色史莱姆", hp = 35,  atk = 18, def = 1,  gold = 1,  exp = 1,  r = 60,  g = 200, b = 60,  sprite = "image/$2 (2).png"},
    ["2"] = {name = "红色史莱姆", hp = 45,  atk = 20, def = 2,  gold = 2,  exp = 2,  r = 220, g = 60,  b = 60,  sprite = "image/$2 (2).png", spriteRow = 1,
             skill = {id = "curse", name = "侵蚀", cardId = "erode", count = 1, desc = "攻击后植入1张侵蚀卡"}},
    ["4"] = {name = "蝙蝠",       hp = 35,  atk = 22, def = 4,  gold = 3,  exp = 3,  r = 160, g = 60,  b = 200, sprite = "image/$2 (1).png", spriteRow = 0,
             skill = {id = "preemptive", name = "先攻", desc = "先于玩家攻击"}},
    -- Tier 2: 第6-18层
    ["3"] = {name = "骷髅士兵",   hp = 50,  atk = 25, def = 5,  gold = 4,  exp = 3,  r = 200, g = 200, b = 200, sprite = "image/$1 (16).png", spriteRow = 0,
             skill = {id = "curse", name = "迷雾", cardId = "fog", count = 1, desc = "攻击后植入1张迷雾卡"}},
    ["p"] = {name = "黑史莱姆",   hp = 60,  atk = 28, def = 3,  gold = 3,  exp = 3,  r = 120, g = 100, b = 140, sprite = "image/$2 (2).png", spriteRow = 2},
    ["F"] = {name = "地精",       hp = 40,  atk = 32, def = 2,  gold = 8,  exp = 4,  r = 160, g = 120, b = 80,  sprite = "image/$1 (19).png", spriteRow = 3,
             skill = {id = "steal", name = "偷窃", value = 5, desc = "每次攻击偷取5金币"}},
    ["I"] = {name = "幽灵",       hp = 55,  atk = 30, def = 0,  gold = 5,  exp = 5,  r = 220, g = 220, b = 240, sprite = "image/$1 (21).png", spriteRow = 3,
             skill = {id = "pierceShield", name = "虚无", desc = "无视玩家护盾"}},
    -- Tier 3: 第14-26层
    ["5"] = {name = "初级法师",   hp = 70,  atk = 38, def = 6,  gold = 6,  exp = 5,  r = 180, g = 80,  b = 220, sprite = "image/$1 (18).png",
             skill = {id = "magicAtk", name = "魔攻", desc = "无视玩家防御"}},
    ["6"] = {name = "骷髅战士",   hp = 90,  atk = 45, def = 10, gold = 8,  exp = 6,  r = 220, g = 210, b = 180, sprite = "image/$1 (16).png", spriteRow = 1,
             skill = {id = "curse", name = "诅咒", cardId = "wound", count = 1, desc = "攻击后植入1张创伤卡"}},
    ["O"] = {name = "石像守卫",   hp = 100, atk = 38, def = 18, gold = 7,  exp = 6,  r = 180, g = 180, b = 200, sprite = "image/$1 (20).png", spriteRow = 0},
    ["k"] = {name = "狂战士",     hp = 80,  atk = 58, def = 5,  gold = 10, exp = 7,  r = 220, g = 80,  b = 60,  sprite = "image/$1 (19).png", spriteRow = 0,
             skill = {id = "berserk", name = "狂暴", desc = "HP低于50%时攻击翻倍"}},
    -- Tier 4: 第22-36层
    ["8"] = {name = "兽面人",     hp = 130, atk = 58, def = 12, gold = 12, exp = 8,  r = 180, g = 120, b = 60,  sprite = "image/$1 (17).png",
             skill = {id = "counter", name = "反击", value = 5, desc = "每回合额外造成5点伤害"}},
    ["9"] = {name = "石头人",     hp = 60,  atk = 68, def = 20, gold = 15, exp = 10, r = 160, g = 160, b = 140, sprite = "image/$1 (17).png", spriteRow = 1,
             skill = {id = "curse", name = "虚弱", cardId = "frail", count = 1, desc = "攻击后植入1张虚弱卡"}},
    ["Z"] = {name = "恶魔骑士",   hp = 160, atk = 70, def = 18, gold = 18, exp = 12, r = 200, g = 50,  b = 50,  sprite = "image/$1 (20).png", spriteRow = 2,
             skill = {id = "curse", name = "血咒", cardId = "wound", count = 2, desc = "攻击后植入2张创伤卡"}},
    -- Tier 5: 第32-48层
    ["A"] = {name = "暗黑骑士",   hp = 180, atk = 78, def = 22, gold = 20, exp = 14, r = 60,  g = 40,  b = 80,  sprite = "image/$1 (16).png", spriteRow = 2,
             skill = {id = "curse", name = "噩梦", cardId = "nightmare", count = 1, desc = "攻击后植入1张噩梦卡"}},
    ["C"] = {name = "魔王守卫",   hp = 250, atk = 95, def = 30, gold = 30, exp = 20, r = 180, g = 40,  b = 40,  sprite = "image/$1 (21).png", spriteRow = 2,
             skill = {id = "counter", name = "反击", value = 10, desc = "每回合额外造成10点伤害"}},
    -- Boss: 第10层
    ["J"] = {name = "史莱姆王",   hp = 200, atk = 35, def = 5,  gold = 50, exp = 25, r = 60,  g = 255, b = 80,  sprite = "image/$2 (2).png", spriteRow = 3,
             boss = true, skill = {id = "regen", name = "再生", value = 5, desc = "每回合恢复5点HP"}},
    -- Boss: 第20层
    ["L"] = {name = "巨龙",       hp = 700, atk = 115,def = 35, gold = 220,exp = 80, r = 220, g = 200, b = 160, sprite = "image/$1 (22).png",
             boss = true, skill = {id = "counter", name = "反击", value = 15, desc = "每回合额外造成15点伤害"}},
    -- Boss: 第30层
    ["N"] = {name = "吸血鬼",     hp = 550, atk = 85, def = 25, gold = 160,exp = 60, r = 140, g = 40,  b = 200, sprite = "image/$2 (1).png", spriteRow = 2,
             boss = true, skill = {id = "magicAtk", name = "魔攻", desc = "无视玩家防御"}},
    -- Boss: 第40层
    ["X"] = {name = "大章鱼",     hp = 400, atk = 65, def = 15, gold = 100,exp = 40, r = 255, g = 80,  b = 20,  sprite = "image/$1 (22).png", spriteRow = 1,
             boss = true, skill = {id = "counter", name = "反击", value = 8, desc = "每回合额外造成8点伤害"}},
    -- Boss: 第50层（最终Boss）
    ["7"] = {name = "魔王",       hp = 800, atk = 140,def = 40, gold = 300,exp = 100,r = 255, g = 20,  b = 20,  sprite = "image/Package2.png", spriteRow = 4,
             boss = true, skill = {id = "regen", name = "再生", value = 20, desc = "每回合恢复20点HP"}},
}

-- Boss 掉落卡牌表：击败 Boss 后必定掉落一张稀有卡牌
BOSS_DROP = {
    ["J"] = {pool = {"drain","weaken","reflect","execute","pierce","thunder","haste"}, rarity = "rare"},       -- 10F
    ["L"] = {pool = {"cleave","ironWall","thorns"},                                   rarity = "epic"},       -- 20F
    ["N"] = {pool = {"cleave","ironWall","thorns","firestorm","bladestorm","soulBurn","handBlast"},rarity = "epic"},       -- 30F
    ["X"] = {pool = {"deathDance","oblivion","immortal","warCry"},                     rarity = "legendary"},  -- 40F
    -- 50F 魔王不掉卡牌（打完即通关）
}

-- Boss 楼层配置：哪些楼层是 Boss 层，以及对应的 Boss 字符
BOSS_FLOORS = {
    [10] = "J",  -- 史莱姆王
    [18] = "X",  -- 当前版本终点 Boss（临时通关）
    [20] = "X",  -- 大章鱼
    [30] = "L",  -- 巨龙
    [40] = "N",  -- 吸血鬼
    [50] = "7",  -- 魔王
}

PLAYER_SPRITE_PATH = "image/$axe-warrior.png"

-- ============================================================
-- 角色列表
-- ============================================================
CHARACTER_LIST = {
    {id = "axe-warrior", name = "狂战士", sprite = "image/$axe-warrior.png",
     passive = "K", startCards = {"strike","strike","defend","defend","savageBash","furyCleave"},
     exclusive = {"savageBash","roar","bladestorm","execute","armorStance","rend","bloodFrenzy","rampage","furyCleave","battleCry","toughHide","berserkerRage","groundSlam","furyBurst","undying","bloodScent","titanGrip","warpath"}},
    {id = "ruibi",       name = "瑞比",   sprite = "image/ruibi2.png",
     passive = "M", startCards = {"strike","strike","strike","heal","defend","defend"},
     spriteConfig = {cols = 4, rows = 2, charIndex = 0},
     exclusive = {"meditate","convert"}},
    {id = "snake",       name = "蛇人",   sprite = "image/$z-snake.png",
     passive = "V", startCards = {"strike","strike","strike","poison","defend","defend"},
     exclusive = {"poison","devour"}},
    {id = "lion",        name = "狮人",   sprite = "image/$z-lion.png",
     passive = "T", startCards = {"strike","strike","strike","guard","defend","defend"},
     exclusive = {"shield","reflect"}},
    {id = "golt",        name = "高特",   sprite = "image/$z-golt.png",
     passive = "Q", startCards = {"strike","strike","strike","power","defend","defend"},
     exclusive = {"firestorm","soulBurn"}},
    {id = "knight",      name = "追光剑士", sprite = "image/$Lady-knight.png",
     passive = "S", startCards = {"strike","strike","strike","heal","defend","defend"},
     exclusive = {"pierce","thunder"}},
    {id = "lezi",        name = "乐子仙人",   sprite = "image/$lezi.png",
     passive = "E", startCards = {"strike","strike","strike","thrifty","defend","defend"},
     exclusive = {"haste","weaken"}},
    {id = "robot",       name = "测试机器人", sprite = "image/$cha39.png",
     passive = "T", startCards = {"strike","strike","strike","guard","defend","defend"},
     exclusive = {"shield","ironWall"}},
}

-- 难度配置：选择模式界面使用，战斗计算读取同一份数据
DIFFICULTY_DEF = {
    {name = "简单", enemyMul = 1.0, hpBonus = 0,   desc = "当前体验"},
    {name = "中等", enemyMul = 1.2, hpBonus = 100, desc = "敌人HP/ATK×1.2\n初始HP+100"},
    {name = "困难", enemyMul = 1.5, hpBonus = 300, desc = "敌人HP/ATK×1.5\n初始HP+300"},
}

-- 角色选择 & 模式选择状态
charSelect = {
    selectedChar = 1,       -- 当前选中角色索引
    selectedMode = 2,       -- 1=随机地图(敬请期待), 2=固定地图
    selectedDifficulty = 1, -- 1=简单, 2=中等, 3=困难
    charPreviews = {},      -- NanoVG image handles
    loaded = false,         -- 是否已加载预览图
}

WALL_SPRITE_PATH = "image/$!1 (3).png"  -- 墙壁贴图（取左上角48x48静态帧）
ITEM_SPRITE_PATH = "image/$1 (43).png"  -- 物品贴图（第1行:红蓝绿宝石, 第2行:三种血瓶）
KEY_SPRITE_PATH = "image/$1 (39).png"   -- 钥匙贴图（第1行:黄蓝红钥匙）
DOOR_SPRITE_PATH = "image/$1 (2).png"   -- 门贴图（列0黄门, 列1蓝门, 列2红门）
STAIR_SPRITE_PATH = "image/Inside_B.png" -- 楼梯贴图（第7排: 列7下楼, 列8上楼）

-- ============================================================
-- 音频配置
-- ============================================================
BGM_TRACKS = {
    title   = "audio/bgm_title.ogg",
    explore = "audio/bgm_explore.ogg",
    castle  = "audio/bgm_castle.ogg",
    ice     = "audio/bgm_ice.ogg",
    calm    = "audio/bgm_calm.ogg",
    passage = "audio/bgm_passage.ogg",
    boss    = "audio/bgm_boss.ogg",
}
-- 按楼层范围选BGM
FLOOR_BGM = {
    {from = 1,  to = 10, track = "explore"},
    {from = 11, to = 20, track = "castle"},
    {from = 21, to = 30, track = "ice"},
    {from = 31, to = 40, track = "passage"},
    {from = 41, to = 49, track = "calm"},
    {from = 50, to = 50, track = "boss"},
}
SFX_PATHS = {
    attack  = "audio/sfx_attack.ogg",
    hurt    = "audio/sfx_hurt.ogg",
    pickup  = "audio/sfx_pickup.ogg",
    door    = "audio/sfx_door.ogg",
    stairs  = "audio/sfx_stairs.ogg",
    victory = "audio/sfx_victory.ogg",
    gameover= "audio/sfx_gameover.ogg",
    monster_attack = "audio/sfx_monster_attack.ogg",
    block   = "audio/sfx_block.ogg",
    btn     = "audio/sfx_btn_click.ogg",
}

---@type Scene
local audioScene = nil
---@type Node
local bgmNode = nil
---@type SoundSource
local bgmSource = nil
sfxSounds = {}      -- 预加载的音效 Sound 对象
local currentBgmTrack = "" -- 当前播放的BGM track key

-- 前置声明（getShopItems 需要引用后面定义的 CARD_DEF）
-- CARD_DEF 是全局变量，在 main.lua 中从 card.json 加载

-- 物品效果
ITEM_DEF = {
    ["h"] = {type = "hp",  amount = 50,  name = "小血瓶"},
    ["H"] = {type = "hp",  amount = 100, name = "中血瓶"},
    ["z"] = {type = "hp",  amount = 300, name = "大血瓶"},
    -- 攻击宝石系列（红色，sprite col=0）
    ["a"] = {type = "atk", amount = 1,   name = "攻击宝石"},
    ["j"] = {type = "atk", amount = 2,   name = "攻击宝石+2", sprite = "image/$2 (4).png", spriteRow = 0, spriteCol = 0},
    ["m"] = {type = "atk", amount = 4,   name = "攻击宝石+4", sprite = "image/$2 (4).png", spriteRow = 2, spriteCol = 0},
    ["s"] = {type = "atk", amount = 8,   name = "攻击宝石+8", sprite = "image/$2 (4).png", spriteRow = 3, spriteCol = 0},
    ["v"] = {type = "atk", amount = 15,  name = "攻击宝石+15",sprite = "image/$2 (4).png", spriteRow = 1, spriteCol = 0},
    -- 防御宝石系列（蓝色，sprite col=1）
    ["d"] = {type = "def", amount = 1,   name = "防御宝石"},
    ["c"] = {type = "def", amount = 2,   name = "防御宝石+2", sprite = "image/$2 (4).png", spriteRow = 0, spriteCol = 1},
    ["g"] = {type = "def", amount = 4,   name = "防御宝石+4", sprite = "image/$2 (4).png", spriteRow = 2, spriteCol = 1},
    ["q"] = {type = "def", amount = 8,   name = "防御宝石+8", sprite = "image/$2 (4).png", spriteRow = 3, spriteCol = 1},
    ["x"] = {type = "def", amount = 15,  name = "防御宝石+15",sprite = "image/$2 (4).png", spriteRow = 1, spriteCol = 1},
}

-- 附魔宝石定义
GEM_DEF = {
    flame   = {name = "烈焰石", icon = "🔥", iconId = "gem_flame",   desc = "攻击伤害+30%",        r = 255, g = 100, b = 30},
    frost   = {name = "寒冰石", icon = "🧊", iconId = "gem_frost",   desc = "卡片消耗次数+1",      r = 100, g = 200, b = 255},
    holy    = {name = "圣光石", icon = "✨", iconId = "gem_holy",    desc = "治愈/防御效果+50%",    r = 255, g = 230, b = 80},
    thunder = {name = "雷霆石", icon = "⚡", iconId = "gem_thunder", desc = "攻击造成20%范围伤害",  r = 180, g = 100, b = 255},
    thrift  = {name = "节能石", icon = "💎", iconId = "gem_thrift",  desc = "卡片花费MP-1",        r = 80,  g = 220, b = 180},
    blood   = {name = "嗜血石", icon = "🩸", iconId = "gem_blood",   desc = "攻击回复10%伤害HP",   r = 200, g = 40,  b = 60},
    echo    = {name = "余韵石", icon = "🔁", iconId = "gem_echo",   desc = "被卡牌效果弃掉时视为打出", r = 160, g = 120, b = 255},
    draw    = {name = "汲取石", icon = "📥", iconId = "gem_draw",   desc = "打出后抽1张牌",        r = 60,  g = 180, b = 220},
}
-- 地图字符 → 宝石ID
GEM_MAP_CHAR = {
    ["f"] = "flame",
    ["i"] = "frost",
    ["l"] = "holy",
    ["t"] = "thunder",
    ["n"] = "thrift",
    ["o"] = "blood",
    ["e"] = "echo",
    ["w"] = "draw",
}

-- 钥匙定义: 地图字符 → {颜色名, RGB}
KEY_DEF = {
    ["y"] = {name = "黄钥匙", field = "yellowKeys", r = 255, g = 220, b = 50},
    ["b"] = {name = "蓝钥匙", field = "blueKeys",   r = 80,  g = 160, b = 255},
    ["r"] = {name = "红钥匙", field = "redKeys",     r = 255, g = 60,  b = 60},
}

-- 门定义: 地图字符 → {对应钥匙field, 颜色}
DOOR_DEF = {
    ["Y"] = {name = "黄门", keyField = "yellowKeys", r = 200, g = 180, b = 40},
    ["B"] = {name = "蓝门", keyField = "blueKeys",   r = 60,  g = 120, b = 220},
    ["R"] = {name = "红门", keyField = "redKeys",     r = 200, g = 40,  b = 40},
}

-- 被动技能定义: 地图字符 → {名称, 描述, 图标颜色, 图标符号}
SKILL_DEF = {
    ["S"] = {id = "shield",   name = "圣盾",   desc = "每场战斗首回合免伤",       icon = "S", iconId = "skill_frost_armor", r = 100, g = 200, b = 255},
    ["V"] = {id = "vampire",  name = "吸血",   desc = "击败怪物回复10%已造成伤害", icon = "V", iconId = "skill_vampire",     r = 220, g = 50,  b = 80},
    ["K"] = {id = "crit",     name = "暴击",   desc = "每场战斗首击1.5倍伤害",     icon = "K", iconId = "skill_greatsword",  r = 255, g = 160, b = 30},
    ["T"] = {id = "tough",    name = "坚韧",   desc = "受到伤害降低25%",           icon = "T", iconId = "skill_thorn_armor", r = 80,  g = 180, b = 80},
    ["E"] = {id = "greed",    name = "贪婪",   desc = "击败怪物获得双倍金币",      icon = "E", iconId = "icon_gold",         r = 255, g = 220, b = 50},
    ["M"] = {id = "mpBoost",  name = "灵能",   desc = "每回合额外恢复1MP",         icon = "M", iconId = "icon_mp",           r = 120, g = 160, b = 255},
    ["Q"] = {id = "extraDraw",name = "多抽",   desc = "每回合多抽1张牌",           icon = "Q", iconId = "skill_bag",         r = 180, g = 220, b = 100},
}

function isSkill(ch)
    return SKILL_DEF[ch] ~= nil
end

-- 遗物定义: 地图字符 → {id, name, desc, icon, r, g, b}
RELIC_DEF = {
    ["G"] = {id = "gemCraft",  name = "宝石工匠锤", desc = "可以卸下宝石重新安装", icon = "", iconId = "item_hammer", r = 255, g = 180, b = 60},
}

function isRelic(ch)
    return RELIC_DEF[ch] ~= nil
end

function isGem(ch)
    return GEM_MAP_CHAR[ch] ~= nil
end

-- 商店NPC: 地图字符 '$'
SHOP_NPC_CHAR = '$'

-- 商店商品列表（按层级动态生成，价格随楼层提升）
function getShopItems(floor)
    if not player then return {} end
    player.cards = player.cards or {}
    player.gems = player.gems or {}
    player.relics = player.relics or {}
    floor = floor or player.floor or 1
    local tier = math.ceil(floor / 10)  -- 1~5
    local items = {}
    local floorKey = tostring(floor)
    local soldCards = player.shopSoldCards and player.shopSoldCards[floorKey] or {}
    local function isShopCardSold(cardId)
        return soldCards[cardId] == true
    end
    local function addShopCardItem(item)
        if item.cardId and not isShopCardSold(item.cardId) then
            table.insert(items, item)
        end
    end
    local upgradeBuys = type(player.shopUpgradeBuys) == "table" and player.shopUpgradeBuys or {}
    local function getUpgradePrice(itemId)
        return 20 + (upgradeBuys[itemId] or 0) * 10
    end
    -- 血瓶（按商店层级给不同等级）
    local hpSmallId = tier <= 3 and "hp50" or "hp100"
    local hpLargeId = tier <= 3 and "hp100" or "hp300"
    local hpSD, hpLD = CARD_DEF[hpSmallId], CARD_DEF[hpLargeId]
    addShopCardItem({id = "shop_hp1", name = hpSD.name, desc = hpSD.desc, cost = 5 + tier * 3,  icon = "❤", iconId = "icon_hp", r = hpSD.r, g = hpSD.g, b = hpSD.b, isCard = true, cardId = hpSmallId,
        action = function() table.insert(player.cards, {id = hpSmallId, usesLeft = 1}) end})
    addShopCardItem({id = "shop_hp2", name = hpLD.name, desc = hpLD.desc, cost = 10 + tier * 5, icon = "❤", iconId = "icon_hp", r = hpLD.r, g = hpLD.g, b = hpLD.b, isCard = true, cardId = hpLargeId,
        action = function() table.insert(player.cards, {id = hpLargeId, usesLeft = 1}) end})
    -- 攻防属性卡（按当前楼层段位给不同等级）
    local atkId, defId
    if floor >= 41 then
        atkId, defId = "atk15", "def15"
    elseif floor >= 31 then
        atkId, defId = "atk8", "def8"
    elseif floor >= 21 then
        atkId, defId = "atk4", "def4"
    elseif floor >= 11 then
        atkId, defId = "atk2", "def2"
    else
        atkId, defId = "atk1", "def1"
    end
    local atkD, defD = CARD_DEF[atkId], CARD_DEF[defId]
    addShopCardItem({id = "shop_atk", name = atkD.name, desc = atkD.desc, cost = 8 + tier * 5, icon = "⚔", iconId = "icon_atk", r = atkD.r, g = atkD.g, b = atkD.b, isCard = true, cardId = atkId,
        action = function() table.insert(player.cards, {id = atkId, usesLeft = 1}) end})
    addShopCardItem({id = "shop_def", name = defD.name, desc = defD.desc, cost = 8 + tier * 5, icon = "🛡", iconId = "icon_def", r = defD.r, g = defD.g, b = defD.b, isCard = true, cardId = defId,
        action = function() table.insert(player.cards, {id = defId, usesLeft = 1}) end})
    -- 升级区：每个升级商品独立计价，购买该商品后仅该商品涨价
    table.insert(items, {id = "maxmp2", name = "魔力结晶", desc = "MP上限+2", cost = getUpgradePrice("maxmp2"), icon = "✦", iconId = "icon_mp", r = 160, g = 120, b = 255, isUpgrade = true,
        action = function() player.maxMp = player.maxMp + 2; player.mp = math.min(player.mp + 2, player.maxMp) end})
    table.insert(items, {id = "mpreg1", name = "魔力泉水", desc = "MP回复+1", cost = getUpgradePrice("mpreg1"), icon = "✧", iconId = "icon_mp", r = 120, g = 180, b = 255, isUpgrade = true,
        action = function() player.mpRegen = player.mpRegen + 1 end})
    -- 战术精通：战术卡费用-1（需要已拥有战术卡且尚未购买过）
    local hasCardDraw = false
    for _, c in ipairs(player.cards) do
        if c.id == "cardDraw" then hasCardDraw = true; break end
    end
    if hasCardDraw and (not player.cardCostMods or (player.cardCostMods.cardDraw or 0) < 1) then
        table.insert(items, {id = "cardDraw_cheap", name = "战术精通", desc = "战术卡费用永久-1(→0费)", cost = getUpgradePrice("cardDraw_cheap"), icon = "📋", iconId = "icon_scroll_tactics", r = 80, g = 200, b = 200, isUpgrade = true,
            action = function()
                if not player.cardCostMods then player.cardCostMods = {} end
                player.cardCostMods.cardDraw = (player.cardCostMods.cardDraw or 0) + 1
            end})
    end
    -- 抽牌数提升（最多+2，即5张）
    if player.drawCount < 5 then
        table.insert(items, {id = "draw1", name = "智慧卷轴", desc = "每回合抽牌+1(当前" .. player.drawCount .. ")", cost = getUpgradePrice("draw1"), icon = "📜", iconId = "icon_scroll_wisdom", r = 180, g = 220, b = 140, isUpgrade = true,
            action = function() player.drawCount = player.drawCount + 1 end})
    end
    -- 卡牌（通用池 + 角色专属卡，按层级筛选）
    local CARD_TIER = {guard=1, poison=1, meditate=1, heal=1, shield=1, atkShield=1, venomBlade=1, shieldSlam=1, bloodRite=1,
        power=2, weaken=2, thrifty=2, heavyStrike=2,
        drain=3, reflect=3, thunder=3, pierce=3, devour=3, convert=3, cardDraw=3,
        cleave=3, ironWall=3, thorns=3,
        haste=4, execute=4, firestorm=4, bladestorm=4, soulBurn=4, handBlast=4,
        deathDance=4, oblivion=4, immortal=5, warCry=5,
        armorBreak=3, armorStance=2, rend=3, bloodFrenzy=4, rampage=4,
        savageBash=1, roar=1,
        furyCleave=1, battleCry=1, toughHide=2, berserkerRage=2, bloodScent=2,
        groundSlam=3, furyBurst=3, undying=3, titanGrip=4, warpath=5}
    -- 通用池：所有角色都能获得的卡牌（含新卡）
    local COMMON_POOL = {"heal","guard","power","heavyStrike","drain","thrifty","atkShield","cardDraw",
        "cleave","ironWall","thorns","deathDance","oblivion","immortal","warCry","venomBlade","shieldSlam","bloodRite"}
    local charExclusive = nil
    if player.charIdx then
        local ch = CHARACTER_LIST[player.charIdx]
        if ch and ch.exclusive then charExclusive = ch.exclusive end
    end
    local cardPool = {}
    -- 先加入通用池
    for _, cid in ipairs(COMMON_POOL) do
        if tier >= (CARD_TIER[cid] or 1) then
            table.insert(cardPool, cid)
        end
    end
    -- 再加入角色专属卡
    if charExclusive then
        for _, cid in ipairs(charExclusive) do
            if tier >= (CARD_TIER[cid] or 1) then
                table.insert(cardPool, cid)
            end
        end
    end
    -- 从卡池中选2张可购买卡牌
    local shuffled = {}
    for _, v in ipairs(cardPool) do table.insert(shuffled, v) end
    -- 简单洗牌（基于楼层号确定）
    for i = #shuffled, 2, -1 do
        local j = ((floor * 7 + i * 13) % i) + 1
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    for ci = 1, math.min(2, #shuffled) do
        local cid = shuffled[ci]
        local cd = CARD_DEF[cid]
        if cd then
            -- 根据稀有度调整价格
            local rarityPriceMult = ({common=0.5, uncommon=0.8, rare=1.0, epic=1.5, legendary=2.2})
            local priceMult = rarityPriceMult[cd.rarity or "uncommon"] or 1.0
            local cardPrice = math.floor((10 + tier * 8) * priceMult)
            addShopCardItem({
                id = "card_" .. cid, name = "卡牌:" .. cd.name, desc = cd.desc,
                cost = cardPrice, icon = "🃏", iconId = "icon_card",
                r = cd.r, g = cd.g, b = cd.b, isCard = true, cardId = cid,
                action = function()
                    table.insert(player.cards, {id = cid, usesLeft = cd.maxUses})
                end
            })
        end
    end
    -- 宝石：技能宝石池整体前移一档，tier1 即开始提供
    do
        local gemPool = {}
        table.insert(gemPool, "flame")
        table.insert(gemPool, "frost")
        table.insert(gemPool, "draw")
        if tier >= 2 then
            table.insert(gemPool, "holy")
            table.insert(gemPool, "thunder")
            table.insert(gemPool, "echo")
        end
        if tier >= 3 then
            table.insert(gemPool, "thrift")
            table.insert(gemPool, "blood")
        end
        -- 基于楼层洗牌选1颗
        for gi = #gemPool, 2, -1 do
            local gj = ((floor * 11 + gi * 17) % gi) + 1
            gemPool[gi], gemPool[gj] = gemPool[gj], gemPool[gi]
        end
        local gid = gemPool[1]
        local gd = GEM_DEF[gid]
        table.insert(items, {
            id = "gem_" .. gid, name = gd.icon .. gd.name, desc = gd.desc,
            cost = 25 + tier * 15, icon = gd.icon, iconId = gd.iconId,
            r = gd.r, g = gd.g, b = gd.b,
            action = function()
                player.gems[gid] = (player.gems[gid] or 0) + 1
            end
        })
    end

    -- 遗物（未拥有时出现在商店）
    for ch, rl in pairs(RELIC_DEF) do
        if not player.relics[rl.id] then
            table.insert(items, {
                id = "relic_" .. rl.id, name = rl.icon .. rl.name, desc = rl.desc,
                cost = 30 + tier * 20, icon = rl.icon, iconId = rl.iconId,
                r = rl.r, g = rl.g, b = rl.b,
                action = function()
                    player.relics[rl.id] = true
                end
            })
        end
    end

    return items
end
---@diagnostic enable: undefined-global

-- ============================================================
-- 卡牌系统定义
-- ============================================================
-- 稀有度定义
RARITY_DEF = {
    common    = {name = "普通", order = 1, r = 180, g = 180, b = 180},
    uncommon  = {name = "精良", order = 2, r = 80,  g = 200, b = 80},
    rare      = {name = "稀有", order = 3, r = 60,  g = 140, b = 255},
    epic      = {name = "史诗", order = 4, r = 180, g = 80,  b = 255},
    legendary = {name = "传说", order = 5, r = 255, g = 180, b = 40},
    curse     = {name = "诅咒", order = 6, r = 140, g = 40,  b = 100},
}
-- 卡牌定义: 从 assets/data/card.json 加载（延迟到 cjson 初始化后）
CARD_DEF = {}
