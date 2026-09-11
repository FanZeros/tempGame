-- ============================================================
-- GameState_Shop.lua  —— 商店系统（库存/分级装备/补货/买卖）
-- 由 GameState.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================

local sub = {}

function sub.init(M)

-- ===== 装备价值表（稀有度 × T级） =====
-- N=common, UC=uncommon, R=rare, SR=fine, UR=superior
-- 头部/肩部/手部/脚部 使用表值的 70%（向下取整），其余部位使用 100%
local EQUIP_VALUE_TABLE = {
    --       T0   T1   T2   T3   T4   T5   T6   T7   T8   T9
    common   = { 41,  50,  60,  71,  85, 102, 122, 146, 175, 210 },
    uncommon = { 50,  60,  72,  86, 103, 123, 147, 176, 211, 253 },
    rare     = { 60,  72,  86, 103, 123, 147, 176, 211, 253, 303 },
    fine     = { 72,  86, 103, 123, 147, 176, 211, 253, 303, 363 },
    superior = { 258, 309, 369, 441, 528, 633, 759, 909, 1089, 1305 },
}

-- 70% 价值部位
local REDUCED_VALUE_SLOTS = { hat = true, shoulder = true, gloves = true, boots = true }

--- 根据稀有度、T级（0-9）、部位获取装备价值
---@param rarity string
---@param tier number 0-9
---@param slot string|nil
---@return number
local function getEquipValue(rarity, tier, slot)
    local tbl = EQUIP_VALUE_TABLE[rarity]
    if not tbl then return 1 end
    local idx = math.max(1, math.min(tier + 1, 10))  -- tier 0 → index 1
    local val = tbl[idx]
    if slot and REDUCED_VALUE_SLOTS[slot] then
        val = math.floor(val * 0.7)
    end
    return val
end

--- 根据等级推算 T 级（0-9）
---@param level number
---@return number
local function levelToTier(level)
    return math.max(0, math.min(9, math.floor((level - 1) / 10)))
end

M.SHOP_INVENTORY = {
    potion_shop = {
        { templateId = "potion_hp_s", price = 5, stock = 99 },
        { templateId = "potion_mp_s", price = 5, stock = 99 },
    },
    blacksmith = {
        { templateId = "iron_sword",   price = 41, stock = 1 },
        { templateId = "wood_bow",     price = 41, stock = 1 },
        { templateId = "iron_dagger",  price = 41, stock = 1 },
        { templateId = "iron_mace",    price = 41, stock = 1 },
        { templateId = "wood_staff",   price = 41, stock = 1 },
        { templateId = "wood_shield",  price = 41, stock = 1 },
        { templateId = "quiver",       price = 41, stock = 1 },
    },
    jewelry_shop = {
        { templateId = "fake_ruby_ring",     price = 20, stock = 1 },
        { templateId = "fake_sapphire_ring", price = 20, stock = 1 },
        { templateId = "fake_emerald_ring",  price = 20, stock = 1 },
        { templateId = "fake_obsidian_ring", price = 20, stock = 1 },
        { templateId = "fake_opal_ring",     price = 20, stock = 1 },
        { templateId = "fake_topaz_ring",    price = 20, stock = 1 },
        { templateId = "fake_amethyst_ring", price = 20, stock = 1 },
        { templateId = "fake_rose_ring",     price = 20, stock = 1 },
        { templateId = "fake_cyan_ring",     price = 20, stock = 1 },
        { templateId = "silver_moon_necklace", price = 41, stock = 1 },
        { templateId = "crystal_ball",       price = 41, stock = 1 },
    },
    tavern = {
        { templateId = "food_apple",         price = 7,  stock = 99 },
        { templateId = "food_milk",          price = 7,  stock = 99 },
        { templateId = "food_apple_juice",   price = 15, stock = 99 },
        { templateId = "food_ginger_beer",   price = 15, stock = 99 },
        { templateId = "food_honey_ribs",    price = 50, stock = 99 },
        { templateId = "food_roast_chicken", price = 50, stock = 99 },
        { templateId = "food_apple_pie",     price = 50, stock = 99 },
        { templateId = "honey",              price = 10, stock = 99 },
        { templateId = "sugar",              price = 10, stock = 99 },
        { templateId = "salt",               price = 10, stock = 99 },
        { templateId = "raw_chicken",        price = 10, stock = 99 },
        { templateId = "wheat_flour",        price = 10, stock = 99 },
        { templateId = "potato",             price = 10, stock = 99 },
    },
    armor_shop = {
        { templateId = "leather_armor",  price = 41, stock = 1 },
        { templateId = "leather_pants",  price = 41, stock = 1 },
        { templateId = "leather_boots",  price = 28, stock = 1 },
        { templateId = "iron_helmet",    price = 28, stock = 1 },
        { templateId = "iron_shoulder",  price = 28, stock = 1 },
        { templateId = "travel_cloak",   price = 41, stock = 1 },
        { templateId = "leather_belt",   price = 41, stock = 1 },
        { templateId = "leather_gloves", price = 28, stock = 1 },
    },
}

-- ===== 分级装备：数据驱动模板 + 货架管理 =====
-- 设计：每档属性显式列出，便于查看和微调，不依赖公式自动计算
do
    local TIER_NAMES = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

    -- ── 分级装备数据表 ──
    -- 每个条目：baseId, tiers[1..10] = { effects, [special], price, stock }
    -- tiers[1] = 基础档（Lv1-10），tiers[2] = 第二档（Lv11-20），以此类推
    local TIERED_ITEMS = {
        -- ─── 盔甲铺 ───
        { baseId = "iron_helmet", tiers = {  -- hat → 70%
            { effects = { def = 1  }, price = 28,  stock = 1 },
            { effects = { def = 3  }, price = 35,  stock = 1 },
            { effects = { def = 6  }, price = 42,  stock = 1 },
            { effects = { def = 8  }, price = 49,  stock = 1 },
            { effects = { def = 10 }, price = 59,  stock = 1 },
            { effects = { def = 12 }, price = 71,  stock = 1 },
            { effects = { def = 15 }, price = 85,  stock = 1 },
            { effects = { def = 17 }, price = 102, stock = 1 },
            { effects = { def = 19 }, price = 122, stock = 1 },
            { effects = { def = 21 }, price = 147, stock = 1 },
        }},
        { baseId = "iron_shoulder", tiers = {  -- shoulder → 70%
            { effects = { def = 1  }, price = 28,  stock = 1 },
            { effects = { def = 3  }, price = 35,  stock = 1 },
            { effects = { def = 6  }, price = 42,  stock = 1 },
            { effects = { def = 8  }, price = 49,  stock = 1 },
            { effects = { def = 10 }, price = 59,  stock = 1 },
            { effects = { def = 12 }, price = 71,  stock = 1 },
            { effects = { def = 15 }, price = 85,  stock = 1 },
            { effects = { def = 17 }, price = 102, stock = 1 },
            { effects = { def = 19 }, price = 122, stock = 1 },
            { effects = { def = 21 }, price = 147, stock = 1 },
        }},
        { baseId = "travel_cloak", tiers = {  -- cloak → 100%
            { effects = { mDef = 2  }, price = 41,  stock = 1 },
            { effects = { mDef = 6  }, price = 50,  stock = 1 },
            { effects = { mDef = 11 }, price = 60,  stock = 1 },
            { effects = { mDef = 15 }, price = 71,  stock = 1 },
            { effects = { mDef = 20 }, price = 85,  stock = 1 },
            { effects = { mDef = 24 }, price = 102, stock = 1 },
            { effects = { mDef = 29 }, price = 122, stock = 1 },
            { effects = { mDef = 33 }, price = 146, stock = 1 },
            { effects = { mDef = 38 }, price = 175, stock = 1 },
            { effects = { mDef = 42 }, price = 210, stock = 1 },
        }},
        { baseId = "leather_armor", tiers = {  -- chest → 100%
            { effects = { def = 2  }, price = 41,  stock = 1 },
            { effects = { def = 6  }, price = 50,  stock = 1 },
            { effects = { def = 11 }, price = 60,  stock = 1 },
            { effects = { def = 15 }, price = 71,  stock = 1 },
            { effects = { def = 20 }, price = 85,  stock = 1 },
            { effects = { def = 24 }, price = 102, stock = 1 },
            { effects = { def = 29 }, price = 122, stock = 1 },
            { effects = { def = 33 }, price = 146, stock = 1 },
            { effects = { def = 38 }, price = 175, stock = 1 },
            { effects = { def = 42 }, price = 210, stock = 1 },
        }},
        { baseId = "leather_gloves", tiers = {  -- gloves → 70%
            { effects = { def = 1  }, price = 28,  stock = 1 },
            { effects = { def = 3  }, price = 35,  stock = 1 },
            { effects = { def = 6  }, price = 42,  stock = 1 },
            { effects = { def = 8  }, price = 49,  stock = 1 },
            { effects = { def = 10 }, price = 59,  stock = 1 },
            { effects = { def = 12 }, price = 71,  stock = 1 },
            { effects = { def = 15 }, price = 85,  stock = 1 },
            { effects = { def = 17 }, price = 102, stock = 1 },
            { effects = { def = 19 }, price = 122, stock = 1 },
            { effects = { def = 21 }, price = 147, stock = 1 },
        }},
        { baseId = "leather_pants", tiers = {  -- pants → 100%
            { effects = { def = 2  }, price = 41,  stock = 1 },
            { effects = { def = 6  }, price = 50,  stock = 1 },
            { effects = { def = 11 }, price = 60,  stock = 1 },
            { effects = { def = 15 }, price = 71,  stock = 1 },
            { effects = { def = 20 }, price = 85,  stock = 1 },
            { effects = { def = 24 }, price = 102, stock = 1 },
            { effects = { def = 29 }, price = 122, stock = 1 },
            { effects = { def = 33 }, price = 146, stock = 1 },
            { effects = { def = 38 }, price = 175, stock = 1 },
            { effects = { def = 42 }, price = 210, stock = 1 },
        }},
        { baseId = "leather_boots", tiers = {  -- boots → 70%
            { effects = { def = 1  }, price = 28,  stock = 1 },
            { effects = { def = 3  }, price = 35,  stock = 1 },
            { effects = { def = 6  }, price = 42,  stock = 1 },
            { effects = { def = 8  }, price = 49,  stock = 1 },
            { effects = { def = 10 }, price = 59,  stock = 1 },
            { effects = { def = 12 }, price = 71,  stock = 1 },
            { effects = { def = 15 }, price = 85,  stock = 1 },
            { effects = { def = 17 }, price = 102, stock = 1 },
            { effects = { def = 19 }, price = 122, stock = 1 },
            { effects = { def = 21 }, price = 147, stock = 1 },
        }},
        { baseId = "leather_belt", tiers = {  -- belt → 100%
            { effects = { mDef = 2  }, price = 41,  stock = 1 },
            { effects = { mDef = 6  }, price = 50,  stock = 1 },
            { effects = { mDef = 11 }, price = 60,  stock = 1 },
            { effects = { mDef = 15 }, price = 71,  stock = 1 },
            { effects = { mDef = 20 }, price = 85,  stock = 1 },
            { effects = { mDef = 24 }, price = 102, stock = 1 },
            { effects = { mDef = 29 }, price = 122, stock = 1 },
            { effects = { mDef = 33 }, price = 146, stock = 1 },
            { effects = { mDef = 38 }, price = 175, stock = 1 },
            { effects = { mDef = 42 }, price = 210, stock = 1 },
        }},
        -- ─── 首饰铺 ───
        { baseId = "silver_moon_necklace", tiers = {  -- necklace → 100%
            { effects = { hp = 4  }, price = 41,  stock = 1 },
            { effects = { hp = 10 }, price = 50,  stock = 1 },
            { effects = { hp = 13 }, price = 60,  stock = 1 },
            { effects = { hp = 17 }, price = 71,  stock = 1 },
            { effects = { hp = 22 }, price = 85,  stock = 1 },
            { effects = { hp = 29 }, price = 102, stock = 1 },
            { effects = { hp = 38 }, price = 122, stock = 1 },
            { effects = { hp = 49 }, price = 146, stock = 1 },
            { effects = { hp = 64 }, price = 175, stock = 1 },
            { effects = { hp = 83 }, price = 210, stock = 1 },
        }},
        -- ─── 铁匠铺 ─── (全部 weapon_r/weapon_l → 100%)
        { baseId = "iron_sword", tiers = {
            { effects = { atk = 3  }, price = 41,  stock = 1 },
            { effects = { atk = 10 }, price = 50,  stock = 1 },
            { effects = { atk = 20 }, price = 60,  stock = 1 },
            { effects = { atk = 30 }, price = 71,  stock = 1 },
            { effects = { atk = 40 }, price = 85,  stock = 1 },
            { effects = { atk = 50 }, price = 102, stock = 1 },
            { effects = { atk = 60 }, price = 122, stock = 1 },
            { effects = { atk = 70 }, price = 146, stock = 1 },
            { effects = { atk = 80 }, price = 175, stock = 1 },
            { effects = { atk = 90 }, price = 210, stock = 1 },
        }},
        { baseId = "wood_bow", tiers = {
            { effects = { atk = 3  }, price = 41,  stock = 1 },
            { effects = { atk = 10 }, price = 50,  stock = 1 },
            { effects = { atk = 20 }, price = 60,  stock = 1 },
            { effects = { atk = 30 }, price = 71,  stock = 1 },
            { effects = { atk = 40 }, price = 85,  stock = 1 },
            { effects = { atk = 50 }, price = 102, stock = 1 },
            { effects = { atk = 60 }, price = 122, stock = 1 },
            { effects = { atk = 70 }, price = 146, stock = 1 },
            { effects = { atk = 80 }, price = 175, stock = 1 },
            { effects = { atk = 90 }, price = 210, stock = 1 },
        }},
        { baseId = "iron_dagger", tiers = {
            { effects = { atk = 3  }, price = 41,  stock = 1 },
            { effects = { atk = 10 }, price = 50,  stock = 1 },
            { effects = { atk = 20 }, price = 60,  stock = 1 },
            { effects = { atk = 30 }, price = 71,  stock = 1 },
            { effects = { atk = 40 }, price = 85,  stock = 1 },
            { effects = { atk = 50 }, price = 102, stock = 1 },
            { effects = { atk = 60 }, price = 122, stock = 1 },
            { effects = { atk = 70 }, price = 146, stock = 1 },
            { effects = { atk = 80 }, price = 175, stock = 1 },
            { effects = { atk = 90 }, price = 210, stock = 1 },
        }},
        { baseId = "iron_mace", tiers = {  -- 物魔双修：atk+mAtk 同值（T1+×0.9四舍五入）
            { effects = { atk = 3,  mAtk = 3  }, price = 41,  stock = 1 },
            { effects = { atk = 9,  mAtk = 9  }, price = 50,  stock = 1 },
            { effects = { atk = 18, mAtk = 18 }, price = 60,  stock = 1 },
            { effects = { atk = 27, mAtk = 27 }, price = 71,  stock = 1 },
            { effects = { atk = 36, mAtk = 36 }, price = 85,  stock = 1 },
            { effects = { atk = 45, mAtk = 45 }, price = 102, stock = 1 },
            { effects = { atk = 54, mAtk = 54 }, price = 122, stock = 1 },
            { effects = { atk = 63, mAtk = 63 }, price = 146, stock = 1 },
            { effects = { atk = 72, mAtk = 72 }, price = 175, stock = 1 },
            { effects = { atk = 81, mAtk = 81 }, price = 210, stock = 1 },
        }},
        { baseId = "wood_staff", tiers = {
            { effects = { mAtk = 3  }, price = 41,  stock = 1 },
            { effects = { mAtk = 10 }, price = 50,  stock = 1 },
            { effects = { mAtk = 20 }, price = 60,  stock = 1 },
            { effects = { mAtk = 30 }, price = 71,  stock = 1 },
            { effects = { mAtk = 40 }, price = 85,  stock = 1 },
            { effects = { mAtk = 50 }, price = 102, stock = 1 },
            { effects = { mAtk = 60 }, price = 122, stock = 1 },
            { effects = { mAtk = 70 }, price = 146, stock = 1 },
            { effects = { mAtk = 80 }, price = 175, stock = 1 },
            { effects = { mAtk = 90 }, price = 210, stock = 1 },
        }},
        { baseId = "wood_shield", tiers = {
            { effects = { def = 2,  block_chance = 0.4, block_amount = 4  }, price = 41,  stock = 1 },
            { effects = { def = 6,  block_chance = 0.4, block_amount = 8  }, price = 50,  stock = 1 },
            { effects = { def = 11, block_chance = 0.4, block_amount = 12 }, price = 60,  stock = 1 },
            { effects = { def = 15, block_chance = 0.4, block_amount = 16 }, price = 71,  stock = 1 },
            { effects = { def = 20, block_chance = 0.4, block_amount = 20 }, price = 85,  stock = 1 },
            { effects = { def = 24, block_chance = 0.4, block_amount = 24 }, price = 102, stock = 1 },
            { effects = { def = 29, block_chance = 0.4, block_amount = 28 }, price = 122, stock = 1 },
            { effects = { def = 33, block_chance = 0.4, block_amount = 32 }, price = 146, stock = 1 },
            { effects = { def = 38, block_chance = 0.4, block_amount = 36 }, price = 175, stock = 1 },
            { effects = { def = 42, block_chance = 0.4, block_amount = 40 }, price = 210, stock = 1 },
        }},
        { baseId = "quiver", tiers = {
            { effects = { atk = 3  }, price = 41,  stock = 1 },
            { effects = { atk = 10 }, price = 50,  stock = 1 },
            { effects = { atk = 20 }, price = 60,  stock = 1 },
            { effects = { atk = 30 }, price = 71,  stock = 1 },
            { effects = { atk = 40 }, price = 85,  stock = 1 },
            { effects = { atk = 50 }, price = 102, stock = 1 },
            { effects = { atk = 60 }, price = 122, stock = 1 },
            { effects = { atk = 70 }, price = 146, stock = 1 },
            { effects = { atk = 80 }, price = 175, stock = 1 },
            { effects = { atk = 90 }, price = 210, stock = 1 },
        }},
        -- ─── 首饰铺 ───
        { baseId = "crystal_ball", tiers = {
            { effects = { mAtk = 3  }, price = 41,  stock = 1 },
            { effects = { mAtk = 10 }, price = 50,  stock = 1 },
            { effects = { mAtk = 20 }, price = 60,  stock = 1 },
            { effects = { mAtk = 30 }, price = 71,  stock = 1 },
            { effects = { mAtk = 40 }, price = 85,  stock = 1 },
            { effects = { mAtk = 50 }, price = 102, stock = 1 },
            { effects = { mAtk = 60 }, price = 122, stock = 1 },
            { effects = { mAtk = 70 }, price = 146, stock = 1 },
            { effects = { mAtk = 80 }, price = 175, stock = 1 },
            { effects = { mAtk = 90 }, price = 210, stock = 1 },
        }},
    }

    -- ── 从数据表注册 itemTemplate ──
    M.TIERED_SHOP_DATA = {}  -- { [baseId] = { [tier] = { id, price, stock } } }

    for _, entry in ipairs(TIERED_ITEMS) do
        local baseId = entry.baseId
        local base = M.itemTemplates[baseId]
        M.TIERED_SHOP_DATA[baseId] = {}

        for tier, data in ipairs(entry.tiers) do
            -- tier 1 = 基础档，直接使用原模板ID；tier 2+ 创建新模板
            if tier == 1 then
                M.TIERED_SHOP_DATA[baseId][tier] = {
                    id    = baseId,
                    price = data.price,
                    stock = data.stock,
                }
            else
                local newId = baseId .. "_t" .. tier
                M.itemTemplates[newId] = {
                    id       = newId,
                    name     = base.name,
                    category = base.category,
                    rarity   = base.rarity,
                    level    = (tier - 1) * 10 + 1,
                    slot     = base.slot,
                    icon     = base.icon,
                    effects  = data.effects,
                    special  = data.special,
                    weaponTag  = base.weaponTag,
                    offhandTag = base.offhandTag,
                    desc     = base.desc,
                }
                M.TIERED_SHOP_DATA[baseId][tier] = {
                    id    = newId,
                    price = data.price,
                    stock = data.stock,
                }
            end
        end
    end

    -- ── 货架定义：每个商店在各档位的商品列表 ──
    -- 格式：shopId → { baseId1, baseId2, ... }
    -- updateShopByLevel 根据 tier 查 TIERED_SHOP_DATA[baseId][tier] 组装货架
    M.SHOP_SHELVES = {
        armor_shop = {
            "leather_armor", "leather_pants", "leather_boots",
            "iron_helmet", "iron_shoulder", "travel_cloak",
            "leather_belt", "leather_gloves",
        },
        blacksmith = { "iron_sword", "wood_bow", "iron_dagger", "iron_mace", "wood_staff", "wood_shield", "quiver" },
        -- 首饰铺升级项链和水晶球，其余戒指不分级
        jewelry_necklace = { "silver_moon_necklace" },
        jewelry_offhand = { "crystal_ball" },
    }

    -- ── 野外基础掉落组分级注册（uncommon T0-T9） ──
    -- T0=Lv6(已存在), T1=Lv16, T2=Lv26 ... T9=Lv96
    -- ucTiers: 显式分级数值(T1-T9)，优先于从 common 推导
    -- ucEffectKey: 指定仅缩放哪个 effect key，其余保留基础模板值（用于盾牌等多属性装备）
    local UC_WEAPON_VALS      = { 12, 24, 36, 48, 60, 72, 84, 96, 108 }  -- T1-T9
    local UC_MACE_VALS        = { 11, 22, 32, 43, 54, 65, 76, 86, 97 }  -- T1-T9 钉锤（×0.9四舍五入）
    local UC_HEAVY_ARMOR_VALS = { 8, 13, 19, 24, 30, 36, 41, 47, 52 }    -- T1-T9 胸甲/腿甲/盾牌def + 披风/腰带mDef
    local UC_SHIELD_BLOCK_VALS = { 9, 14, 19, 24, 28, 33, 38, 43, 48 } -- T1-T9 盾牌block_amount
    local UC_LIGHT_ARMOR_VALS = { 4, 7, 10, 12, 15, 18, 21, 24, 26 }     -- T1-T9 头盔/护肩/手套/鞋子def
    local UNCOMMON_TO_COMMON = {
        { uncommonId = "copper_helmet",       commonBase = "iron_helmet",        ucTiers = UC_LIGHT_ARMOR_VALS },
        { uncommonId = "copper_shoulder",      commonBase = "iron_shoulder",      ucTiers = UC_LIGHT_ARMOR_VALS },
        { uncommonId = "copper_cloak",         commonBase = "travel_cloak",       ucTiers = UC_HEAVY_ARMOR_VALS },
        { uncommonId = "copper_chest_armor",   commonBase = "leather_armor",      ucTiers = UC_HEAVY_ARMOR_VALS },
        { uncommonId = "copper_gloves",        commonBase = "leather_gloves",     ucTiers = UC_LIGHT_ARMOR_VALS },
        { uncommonId = "copper_leg_armor",     commonBase = "leather_pants",      ucTiers = UC_HEAVY_ARMOR_VALS },
        { uncommonId = "copper_boots",         commonBase = "leather_boots",      ucTiers = UC_LIGHT_ARMOR_VALS },
        { uncommonId = "copper_belt",          commonBase = "leather_belt",       ucTiers = UC_HEAVY_ARMOR_VALS },
        { uncommonId = "copper_iron_sword",    commonBase = "iron_sword",         ucTiers = UC_WEAPON_VALS },
        { uncommonId = "inlaid_copper_bow",    commonBase = "wood_bow",           ucTiers = UC_WEAPON_VALS },
        { uncommonId = "copper_handle_dagger", commonBase = "iron_dagger",        ucTiers = UC_WEAPON_VALS },
        { uncommonId = "copper_handle_mace",   commonBase = "iron_mace",          ucTiers = UC_MACE_VALS },
        { uncommonId = "inlaid_copper_staff",  commonBase = "wood_staff",         ucTiers = UC_WEAPON_VALS },
        { uncommonId = "copper_wood_shield",   commonBase = "wood_shield",        ucTiers = UC_HEAVY_ARMOR_VALS, ucEffectKey = "def", ucBlockTiers = UC_SHIELD_BLOCK_VALS },
        { uncommonId = "copper_quiver",        commonBase = "quiver",             ucTiers = UC_WEAPON_VALS },
        { uncommonId = "copper_crystal_ball",  commonBase = "crystal_ball",       ucTiers = UC_WEAPON_VALS },
    }

    --- 从 TIERED_ITEMS 提取指定 baseId 的 tiers 数组
    local commonTiersMap = {}
    for _, entry in ipairs(TIERED_ITEMS) do
        commonTiersMap[entry.baseId] = entry.tiers
    end

    --- 线性外推：根据最后两档的差值推算下一档
    local function extrapolateEffects(tiers)
        local last = tiers[#tiers]
        local prev = tiers[#tiers - 1]
        local ext = {}
        for k, v in pairs(last.effects) do
            local diff = v - (prev.effects[k] or 0)
            ext[k] = v + diff
        end
        local result = { effects = ext }
        -- 外推 price
        result.price = (last.price or 0) + ((last.price or 0) - (prev.price or 0))
        return result
    end

    -- 为每件 uncommon 装备注册 T1-T9 模板
    -- T0 已在 itemTemplates 中手工定义，对应 common tier 2
    -- T_n (n>=1) 对应 common tier (n+2)
    M.UNCOMMON_TIERED_IDS = {}  -- { [uncommonBaseId] = { [0]=id_t0, [1]=id_t1, ... } }

    for _, mapping in ipairs(UNCOMMON_TO_COMMON) do
        local uid   = mapping.uncommonId
        local cBase = mapping.commonBase
        local base  = M.itemTemplates[uid]
        local cTiers = commonTiersMap[cBase]
        if base and cTiers then
            M.UNCOMMON_TIERED_IDS[uid] = { [0] = uid }

            for t = 1, 9 do
                local newEffects, newSpecial, newPrice

                if mapping.ucTiers then
                    -- 显式分级：用 ucTiers[t] 填充 effect keys
                    local val = mapping.ucTiers[t]
                    newEffects = {}
                    if mapping.ucEffectKey then
                        -- 仅缩放指定 key，其余保留基础模板值（如盾牌）
                        for k, v in pairs(base.effects) do
                            newEffects[k] = v
                        end
                        newEffects[mapping.ucEffectKey] = val
                        -- 盾牌格挡伤害独立分级
                        if mapping.ucBlockTiers and mapping.ucBlockTiers[t] then
                            newEffects.block_amount = mapping.ucBlockTiers[t]
                        end
                    else
                        -- 所有 keys 赋同值（武器/单属性防具）
                        for k, _ in pairs(base.effects) do
                            newEffects[k] = val
                        end
                    end
                    newSpecial = nil
                    newPrice   = getEquipValue("uncommon", t, base.slot)
                else
                    -- 从 common tiers 推导
                    local cTierIdx = t + 2  -- uncommon T_n = common tier (n+2)
                    local cData
                    if cTierIdx <= #cTiers then
                        cData = cTiers[cTierIdx]
                    else
                        cData = extrapolateEffects(cTiers)
                    end
                    newEffects = cData.effects
                    newSpecial = cData.special
                    newPrice   = cData.price
                end

                local newId = uid .. "_t" .. t
                local newLevel = t * 10 + 6  -- T1=16, T2=26, ... T9=96
                M.itemTemplates[newId] = {
                    id        = newId,
                    name      = base.name,
                    category  = base.category,
                    rarity    = "uncommon",
                    level     = newLevel,
                    slot      = base.slot,
                    icon      = base.icon,
                    effects   = newEffects,
                    special   = newSpecial,
                    weaponTag  = base.weaponTag,
                    offhandTag = base.offhandTag,
                    desc      = base.desc,
                    value     = newPrice,
                }
                M.UNCOMMON_TIERED_IDS[uid][t] = newId
            end
        end
    end
end

M.currentShopTier = 0

--- 根据玩家等级更新商店货架（盔甲铺、铁匠铺、首饰铺项链）
function M.updateShopByLevel()
    local playerLv = M.player and M.player.level or 1
    local tier = M.getTierByLevel(playerLv) + 1  -- 1-based: 1=T0, 2=T1, ..., 10=T9
    tier = math.min(math.max(tier, 1), 10)

    if tier == M.currentShopTier then return end
    M.currentShopTier = tier

    -- 更新盔甲铺
    M.SHOP_INVENTORY.armor_shop = {}
    for _, baseId in ipairs(M.SHOP_SHELVES.armor_shop) do
        local data = M.TIERED_SHOP_DATA[baseId][tier]
        table.insert(M.SHOP_INVENTORY.armor_shop, {
            templateId = data.id,
            price      = data.price,
            stock      = data.stock,
        })
    end

    -- 更新铁匠铺
    M.SHOP_INVENTORY.blacksmith = {}
    for _, baseId in ipairs(M.SHOP_SHELVES.blacksmith) do
        local data = M.TIERED_SHOP_DATA[baseId][tier]
        table.insert(M.SHOP_INVENTORY.blacksmith, {
            templateId = data.id,
            price      = data.price,
            stock      = data.stock,
        })
    end

    -- 更新首饰铺中的项链和水晶球
    local jewelryShelves = { "jewelry_necklace", "jewelry_offhand" }
    for _, shelfKey in ipairs(jewelryShelves) do
        for _, baseId in ipairs(M.SHOP_SHELVES[shelfKey] or {}) do
            local data = M.TIERED_SHOP_DATA[baseId][tier]
            if data then
                for i, entry in ipairs(M.SHOP_INVENTORY.jewelry_shop) do
                    if entry.templateId:find(baseId) then
                        M.SHOP_INVENTORY.jewelry_shop[i] = {
                            templateId = data.id,
                            price      = data.price,
                            stock      = data.stock,
                        }
                        break
                    end
                end
            end
        end
    end

    -- 更新药水铺（累加上架：达到等级后追加更高级药水，低级保留）
    M.SHOP_INVENTORY.potion_shop = {
        { templateId = "potion_hp_s", price = 5,   stock = 99 },
        { templateId = "potion_mp_s", price = 5,   stock = 99 },
    }
    if playerLv >= 20 then
        table.insert(M.SHOP_INVENTORY.potion_shop, { templateId = "potion_hp_m", price = 25,  stock = 99 })
        table.insert(M.SHOP_INVENTORY.potion_shop, { templateId = "potion_mp_m", price = 25,  stock = 99 })
    end
    if playerLv >= 40 then
        table.insert(M.SHOP_INVENTORY.potion_shop, { templateId = "potion_hp_l", price = 100, stock = 99 })
        table.insert(M.SHOP_INVENTORY.potion_shop, { templateId = "potion_mp_l", price = 100, stock = 99 })
    end
    if playerLv >= 60 then
        table.insert(M.SHOP_INVENTORY.potion_shop, { templateId = "potion_hp_xl", price = 300, stock = 99 })
        table.insert(M.SHOP_INVENTORY.potion_shop, { templateId = "potion_mp_xl", price = 300, stock = 99 })
    end

    -- 所有商店按物品等级排序
    local function sortByLevel(list)
        table.sort(list, function(a, b)
            local ta = M.itemTemplates[a.templateId]
            local tb = M.itemTemplates[b.templateId]
            local la = ta and ta.level or 0
            local lb = tb and tb.level or 0
            return la > lb
        end)
    end
    sortByLevel(M.SHOP_INVENTORY.armor_shop)
    sortByLevel(M.SHOP_INVENTORY.blacksmith)
    sortByLevel(M.SHOP_INVENTORY.jewelry_shop)
    sortByLevel(M.SHOP_INVENTORY.potion_shop)
end

-- ===== 冒险者等级（1=F, 2=E, 3=D, 4=C, 5=B, 6=A, 7=S, 8=G） =====
M.adventurerRank = 1  -- 初始 F 级

-- 击杀追踪（特定怪物的击杀计数，用于冒险者等级晋升条件）
M.monsterKillCounts = {}
-- 稀有怪保底计数：连续击杀非稀有怪的数量，达到150时下次强制刷稀有怪
M.rareKillPitySince = 0

-- 区域击杀计数（按区域名累计击杀数，用于妮可"魔物清剿"任务）
M.areaKillCounts = {}

-- 艾莉雅灰界旅行任务完成标记（questId → true）
M.eliyaTravelDone = {}
-- 安吉莉娅旅行任务完成标记（questId → true）
M.angelicaTravelDone = {}
-- 迪芬旅行任务完成标记（questId → true）
M.difenTravelDone = {}
-- 酒馆肉搏任务状态
M.tavernBrawlState = nil  -- nil=无, { questId, thugCount, killCount }
-- 无限塔解锁（艾莉雅任务6奖励）
M.infiniteTowerUnlocked = false
-- 共享仓库解锁（爱丽丝任务5奖励，每角色独立）
M.sharedStorageUnlocked = false
-- 共享仓库数据（跨角色共享，5格，独立保存在 shared_storage 云键中）
M.SHARED_STORAGE_SLOTS = 5
M.sharedStorage = {}  -- { [1]={templateId, quantity, ...}, [2]=nil, ... }
-- [修复] 角色切换保存状态标记，防止网络波动导致共享仓库竞态
M.charSwitchSaving = false
M._pendingLoadSlot = nil

-- 副本通关追踪（记录已通关的副本 ID）
M.dungeonsCleared = {}
-- 副本通关计数（用于任务"接取后才计数"机制）
M.dungeonClearCounts = {}

-- 冒险者等级晋升定义：index 对应目标等级（2=E, 3=D, ... 7=S）
-- condType: "kill" = 击杀指定怪物, "dungeon" = 通关指定副本, "stage_reach" = 到达指定关卡
-- condId: 怪物 defId 或 副本 dungeonId; condStage: stageIndex（stage_reach 用）
-- condCount: 需要的击杀数量（dungeon 默认 1 次）
-- bonus: 本次晋升获得的全属性加成
M.RANK_PROMOTIONS = {
    [2] = { rank = "E", condType = "kill",    condId = "young_werewolf",  condCount = 1, bonus = 1, desc = "击杀幼年狼人" },
    [3] = { rank = "D", condType = "kill",    condId = "black_bear_king", condCount = 1, bonus = 1, desc = "击杀黑熊王" },
    [4] = { rank = "C", condType = "dungeon", condId = "slime_kingdom",   condCount = 1, bonus = 1, desc = "通关\"史莱姆王国\"" },
    [5] = { rank = "B", condType = "dungeon", condId = "goblin_arena",    condCount = 1, bonus = 2, desc = "通关\"哥布林竞技场\"" },
    [6] = { rank = "A", condType = "dungeon", condId = "tidal_sanctuary", condCount = 1, bonus = 2, desc = "通关\"潮汐祭祀圣所\"" },
    [7] = { rank = "S", condType = "stage_reach", condStage = M.STAGE_FORT_BRIDGE, bonus = 3, desc = "抵达升月堡正门桥梁" },
    [8] = { rank = "G", condType = "none",                               condCount = 0, bonus = 0, desc = "冒险者，您的冒险仍未完待续……" },
}

--- 获取冒险者等级带来的全属性加成总值
function M.getAdventurerRankBonus()
    local total = 0
    for rankIdx = 2, (M.adventurerRank or 1) do
        local promo = M.RANK_PROMOTIONS[rankIdx]
        if promo then
            total = total + promo.bonus
        end
    end
    return total
end

--- 检查是否满足下一等级的晋升条件
function M.canPromoteRank()
    local nextRank = (M.adventurerRank or 1) + 1
    local promo = M.RANK_PROMOTIONS[nextRank]
    if not promo then return false end  -- 已满级或无晋升数据（G级无条件晋升）

    if promo.condType == "kill" then
        local count = M.monsterKillCounts[promo.condId] or 0
        return count >= promo.condCount
    elseif promo.condType == "dungeon" then
        return M.dungeonsCleared[promo.condId] == true
    elseif promo.condType == "stage_reach" then
        return (M.maxStageReached or 1) >= (promo.condStage or 999)
    end
    return false
end

--- 执行晋升（调用前需先检查 canPromoteRank）
function M.promoteRank()
    if not M.canPromoteRank() then return false end
    local newRank = M.adventurerRank + 1
    M.adventurerRank = newRank
    -- 晋升后重新计算属性
    if M.player then
        M.recalcStats(M.player)
    end
    -- 自动完成对应的晋升任务（E=2→main_rank_e, D=3→main_rank_d, ...）
    local RANK_QUEST_MAP = {
        [2] = "main_rank_e", [3] = "main_rank_d", [4] = "main_rank_c",
        [5] = "main_rank_b", [6] = "main_rank_a", [7] = "main_rank_s",
    }
    local questId = RANK_QUEST_MAP[newRank]
    if questId then
        local QM = require("QuestManager")
        local st = QM.questStates[questId]
        if st and (st.status == QM.STATUS_ACTIVE or st.status == QM.STATUS_READY) then
            st.status = QM.STATUS_READY
            QM._doComplete(questId)
            print("[promoteRank] 自动完成晋升任务: " .. questId)
        end
    end
    return true
end

--- 记录特定怪物的击杀
function M.trackMonsterKill(defId)
    if not defId then return end
    M.monsterKillCounts[defId] = (M.monsterKillCounts[defId] or 0) + 1
    -- 稀有怪保底：击杀稀有怪重置计数，否则累加
    local mdef = M.MONSTER_DB[defId]
    if mdef and mdef.rarity == "rare" then
        M.rareKillPitySince = 0
    else
        -- 场上还有存活的稀有怪时，保底计数器暂停
        local hasRare = false
        for _, m in ipairs(M.monsters) do
            if m.hp > 0 and m.rarity == "rare" then
                hasRare = true
                break
            end
        end
        if not hasRare then
            M.rareKillPitySince = (M.rareKillPitySince or 0) + 1
        end
    end
end

--- 记录副本通关
function M.trackDungeonClear(dungeonId)
    if not dungeonId then return end
    M.dungeonsCleared[dungeonId] = true
    M.dungeonClearCounts[dungeonId] = (M.dungeonClearCounts[dungeonId] or 0) + 1
end

--- 库存上限定义
local STOCK_MAX_POTION    = 99
local STOCK_MAX_EQUIPMENT = 1

--- 补满所有商店库存（由采集区720回合重置时统一触发）
function M.restockShops()
    for shopKey, items in pairs(M.SHOP_INVENTORY) do
        for _, entry in ipairs(items) do
            local tpl = M.itemTemplates[entry.templateId]
            if tpl and (tpl.category == "消耗品" or tpl.category == "食物" or tpl.category == "材料") then
                entry.stock = STOCK_MAX_POTION
            else
                entry.stock = STOCK_MAX_EQUIPMENT
            end
        end
    end
end

--- 记录一次击杀，转发给布告栏委托系统
---@param defId string|nil 怪物定义ID
function M.onMonsterKill(defId)
    if defId then
        local BulletinBoard = require("BulletinBoard")
        BulletinBoard.onMonsterKill(defId)
    end
    -- 区域击杀计数（用于妮可"魔物清剿"任务）
    local area = M.currentAreaName
    if area and area ~= "" then
        M.areaKillCounts[area] = (M.areaKillCounts[area] or 0) + 1
    end
end

-- ===== 统一价格后处理：为所有物品设置 value（价值） =====
-- 规则：sellPrice 由 getItemSellPrice() 动态计算 = floor(value / 2)
-- 优先级：商店售价 > 模板 value > 稀有度默认
do
    -- 1. 收集所有商店售价 → templateId → shopPrice
    local shopPriceMap = {}
    for _, shopItems in pairs(M.SHOP_INVENTORY) do
        for _, entry in ipairs(shopItems) do
            shopPriceMap[entry.templateId] = entry.price
        end
    end
    -- 收集分级装备的商店售价
    for _, tiers in pairs(M.TIERED_SHOP_DATA) do
        for _, data in pairs(tiers) do
            shopPriceMap[data.id] = data.price
        end
    end

    -- 2. 稀有度默认价值（仅用于既不在商店也无 value 的物品）
    local rarityPrices = { common = 2, uncommon = 5, rare = 15, fine = 50, superior = 200, epic = 500, legendary = 1000, divine = 2000 }

    -- 3. 遍历所有物品模板，统一设置 value
    for id, tpl in pairs(M.itemTemplates) do
        local shopPrice = shopPriceMap[id]
        if shopPrice then
            -- 商店出售的物品：value = 商店售价
            tpl.value = shopPrice
        elseif tpl.slot and EQUIP_VALUE_TABLE[tpl.rarity] then
            -- 有部位且在价值表中的装备：按 稀有度×T级×部位 自动计算
            local tier = levelToTier(tpl.level or 1)
            tpl.value = getEquipValue(tpl.rarity, tier, tpl.slot)
        elseif tpl.value then
            -- 已手动设置 value（非装备类物品保留原值）
        else
            -- 既不在商店也无价格信息 → 按稀有度默认
            local fallback = rarityPrices[tpl.rarity or "common"] or 1
            tpl.value = fallback * 2
        end
    end
end

-- 商品列表 UI 状态
M.shopItemRects = {}            -- 商品点击区域 { [i] = {x,y,w,h, templateId, price} }
M.shopScrollY = 0               -- 商品列表滚动偏移
M.shopScrollBarDragging = false -- 商店滚动条拖拽中
M.shopScrollBarDragStartY = 0
M.shopScrollBarDragStartScroll = 0
M.shopScrollBarRect = nil       -- 滚动条滑块区域（渲染端设置）
M.shopScrollBarTrack = nil      -- 滚动条轨道区域（渲染端设置）
M.shopContentH = 0              -- 商品列表内容总高度
M.shopVisibleH = 0              -- 商品列表可见高度
M.shopListClipRect = nil        -- 商品列表裁剪区域
M.shopListDragging = false      -- 商品列表拖动滚动中
M.shopListDragStartY = 0
M.shopListDragStartScroll = 0
M.shopListDragMoved = false     -- 是否已发生拖动（区分点击和拖动）
M.shopCloseRect = nil           -- 商店关闭按钮区域
M.shopBuyConfirmVisible = false -- 购买确认弹窗
M.shopBuyConfirmItem = nil      -- 待购买商品 {templateId, price, name}
M.shopBuyConfirmYesRect = {}
M.shopBuyConfirmNoRect = {}
M.shopBuyQuantity = 1           -- 购买数量
M.shopBuyQtySliderRect = nil    -- 数量滑动条轨道区域
M.shopBuyQtySliderDragging = false -- 数量滑动条拖拽中
M.shopBuyQtyBtnRects = {}       -- +1, +10, -1, -10 按钮区域
M.shopBuyMsg = nil              -- 购买结果提示 {text, timer, color}

--- 进入交易模式
function M.enterShopMode(buildingKey)
    M.shopMode = true
    M.shopBuildingKey = buildingKey
    M.shopItemRects = {}
    M.shopScrollY = 0
    M.shopScrollBarDragging = false
    M.shopScrollBarRect = nil
    M.shopScrollBarTrack = nil
    M.shopListDragging = false
    M.shopListDragMoved = false
    M.shopBuyConfirmVisible = false
    M.shopBuyQuantity = 1
    M.shopBuyQtySliderDragging = false
    M.activeBottomTab = 2  -- 切换到背包标签
end

--- 退出交易模式
function M.exitShopMode()
    M.shopMode = false
    M.shopBuildingKey = nil
    M.shopItemRects = {}
    M.shopScrollY = 0
    M.shopScrollBarDragging = false
    M.shopScrollBarRect = nil
    M.shopScrollBarTrack = nil
    M.shopListDragging = false
    M.shopListDragMoved = false
    M.shopBuyConfirmVisible = false
    M.shopBuyConfirmItem = nil
    M.shopBuyQuantity = 1
    M.shopBuyQtySliderDragging = false
end

--- 购买物品
---@param templateId string
---@param price number
---@return boolean success
---@return string message
function M.buyItem(templateId, price, quantity)
    quantity = quantity or 1
    local totalCost = price * quantity
    if M.gold < totalCost then
        return false, "金币不足"
    end
    -- 逐个添加到背包
    local added = 0
    for i = 1, quantity do
        local ok, msg = M.addToInventory(templateId, 1)
        if ok then
            added = added + 1
        else
            if added > 0 then
                M.gold = M.gold - price * added
                return false, "购买了" .. added .. "个，背包已满"
            end
            return false, msg
        end
    end
    M.gold = M.gold - totalCost
    return true, "购买成功 x" .. quantity
end

--- 计算物品出售价格（基于物品当前价值 + 宝石价值，半价出售）
---@param item table
---@return number
function M.getItemSellPrice(item)
    -- 物品当前价值（已包含强化投资）
    local itemValue = item.value
    if not itemValue then
        if item.templateId then
            local tpl = M.itemTemplates[item.templateId]
            if tpl then itemValue = tpl.value end
        end
    end
    if not itemValue then
        -- 无价格信息 → 按稀有度默认
        local rarityPrices = { common = 2, uncommon = 5, rare = 15, fine = 50, superior = 200, epic = 500, legendary = 1000, divine = 2000 }
        itemValue = (rarityPrices[item.rarity or "common"] or 1) * 2
    end
    -- 加入镶嵌宝石的价值
    local gemValue = 0
    if item.gemSlots then
        for _, slot in ipairs(item.gemSlots) do
            if slot.gemId then
                local gemTpl = M.itemTemplates[slot.gemId]
                gemValue = gemValue + (gemTpl and gemTpl.value or 0)
            end
        end
    end
    return math.floor((itemValue + gemValue) / 2)
end

--- 出售物品（从背包移除并获得金币）
---@param slotIdx number 背包格子索引
---@return boolean success
---@return number goldEarned
function M.sellItem(slotIdx)
    local item = M.inventory[slotIdx]
    if not item then return false, 0 end
    if item.locked then return false, 0 end
    local price = M.getItemSellPrice(item)
    local qty = item.quantity or 1
    local total = price * qty
    M.gold = M.gold + total
    M.inventory[slotIdx] = nil
    return true, total
end

--- 批量出售选中物品
---@return number count
---@return number totalGold
function M.sellSelectedItems()
    local count = 0
    local totalGold = 0
    for idx in pairs(M.invSelected) do
        if M.inventory[idx] and not M.inventory[idx].locked then
            local price = M.getItemSellPrice(M.inventory[idx])
            local qty = M.inventory[idx].quantity or 1
            totalGold = totalGold + price * qty
            M.inventory[idx] = nil
            count = count + 1
        end
    end
    M.gold = M.gold + totalGold
    M.invSelected = {}
    M.invMultiSelect = false
    if count > 0 then M.sortInventory() end
    return count, totalGold
end

-- ===== 兑换系统（感恩礼券兑换奖品） =====

M.EXCHANGE_REWARDS = {
    { id = "divine_toughness_agent", name = "神炼增韧剂", desc = "可补充10点武器装备的精炼韧性", ticketCost = 5,
      rewardType = "item", rewardItemId = "divine_toughness_agent", stock = 99, icon = "image/item_divine_toughness.png",
      dailyLimit = 2 },
    { id = "divine_key", name = "神之匙", desc = "进入深渊区副本时自动消耗，额外开启一次挑战", ticketCost = 1,
      rewardType = "item", rewardItemId = "divine_key", stock = 99, icon = "image/item_divine_key.png" },
    { id = "oath_ring", name = "誓约戒指", desc = "向心爱之人求婚时使用的誓约戒指", ticketCost = 30,
      rewardType = "item", rewardItemId = "oath_ring", stock = 1, icon = "image/item_oath_ring.png" },
    { id = "backpack_expand", name = "背包扩充券", desc = "背包物品栏上限+1格", ticketCost = 2,
      rewardType = "item", rewardItemId = "backpack_expand", stock = 99, icon = "image/item_backpack_expand.png" },
    { id = "warehouse_expand", name = "私人仓库扩充券", desc = "仓库容量上限+1格", ticketCost = 2,
      rewardType = "item", rewardItemId = "warehouse_expand", stock = 99, icon = "image/item_warehouse_expand.png" },
    { id = "stat_respec_potion", name = "素质洗点药水", desc = "重置所有属性加点", ticketCost = 3,
      rewardType = "item", rewardItemId = "stat_respec_potion", stock = 99, icon = "image/item_stat_respec.png" },
    { id = "skill_respec_potion", name = "技能洗点药水", desc = "重置所有技能加点", ticketCost = 3,
      rewardType = "item", rewardItemId = "skill_respec_potion", stock = 99, icon = "image/item_skill_respec.png" },
    { id = "divine_extract_agent", name = "神炼萃取剂", desc = "将低等级装备的强化等级转移到高等级装备", ticketCost = 1,
      rewardType = "item", rewardItemId = "divine_extract_agent", stock = 99, icon = "image/item_divine_extract.png" },
    { id = "divine_repair_agent", name = "神炼修复剂", desc = "修复脆化装备的必需材料", ticketCost = 3,
      rewardType = "item", rewardItemId = "divine_repair_agent", stock = 99, icon = "image/item_divine_repair.png" },
    { id = "divine_catalyst", name = "神炼催化剂", desc = "强化时使用，成功率+5%", ticketCost = 3,
      rewardType = "item", rewardItemId = "divine_catalyst", stock = 99, icon = "image/item_divine_catalyst.png" },
    { id = "refine_slot_tool", name = "精炼槽雕刻工具", desc = "为精炼槽未满的装备开凿一个精炼槽", ticketCost = 10,
      rewardType = "item", rewardItemId = "refine_slot_tool", stock = 99, icon = "image/item_refine_slot_tool.png" },
    { id = "socket_drill_tool", name = "宝石嵌槽开孔工具", desc = "为无宝石槽的装备开凿一个槽位", ticketCost = 10,
      rewardType = "item", rewardItemId = "socket_drill_tool", stock = 99, icon = "image/item_socket_drill_tool.png" },
}

M.adLoading = false       -- 广告加载中状态
M.adCancelRect = nil      -- "我不想帮助他了"按钮区域
M.adSessionId = 0         -- 广告请求会话ID（防止旧回调误触发）
M.adDailyCount = 0        -- 今日已观看广告次数
M.adDailyDate = ""        -- 上次观看广告的日期字符串（用于重置每日计数）
M.AD_DAILY_LIMIT = 20     -- 每日广告观看上限

-- 洗点弹窗状态
M.respecPopupVisible = false    -- 洗点弹窗是否显示
M.respecPopupChoice = nil       -- "stats" 或 "skills"
M.respecConfirmRect = nil       -- 确定按钮区域
M.respecCancelRect = nil        -- 取消按钮区域
M.respecStatsRect = nil         -- 素质选项区域
M.respecSkillsRect = nil        -- 技能选项区域

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
M.exchangeDailyBought = {}    -- { [itemId] = count } 今日已购数量
M.exchangeDailyDayKey = 0     -- 上次购买的可信天号（单调递增，防回调时间）
M._exchangeDailyCloudLoaded = false   -- 云端限购数据是否已加载
M._exchangeDailyCloudLoading = false  -- 是否正在加载
M._exchangeDailyCloudFailed = false   -- 加载是否失败

--- 从云端加载兑奖机每日限购数据（启动时调用一次）
function M.loadExchangeDailyFromCloud()
    if M._exchangeDailyCloudLoading or M._exchangeDailyCloudLoaded then return end
    if not clientCloud then
        M._exchangeDailyCloudLoaded = true
        return
    end
    M._exchangeDailyCloudLoading = true
    clientCloud:Get("exchange_daily", {
        ok = function(values)
            M._exchangeDailyCloudLoading = false
            M._exchangeDailyCloudLoaded = true
            M._exchangeDailyCloudFailed = false
            local data = values and values.exchange_daily
            if data then
                local SignIn = require("SignInSystem")
                local reliable = SignIn.isAdminTimeReliable()
                local today = reliable and SignIn.getTrustedDay() or 0
                if data.dayKey and today > data.dayKey then
                    -- 新的一天，重置
                    M.exchangeDailyBought = {}
                    M.exchangeDailyDayKey = today
                elseif data.dayKey and today < data.dayKey then
                    -- 时间回退，沿用云端dayKey（防回调作弊）
                    M.exchangeDailyDayKey = data.dayKey
                    M.exchangeDailyBought = data.bought or {}
                    print("[AntiCheat] 兑换限购：检测到时间回退，沿用云端dayKey:", data.dayKey)
                else
                    -- 同一天，恢复云端数据
                    M.exchangeDailyDayKey = data.dayKey or 0
                    M.exchangeDailyBought = data.bought or {}
                end
            end
            print("=== 兑换限购：云端数据加载完成 ===")
        end,
        error = function(code, reason)
            M._exchangeDailyCloudLoading = false
            M._exchangeDailyCloudLoaded = true
            M._exchangeDailyCloudFailed = true
            print("[ExchangeDaily] 云端加载失败:", code, reason)
        end,
    })
end

--- 保存兑奖机每日限购数据到云端
function M.saveExchangeDailyToCloud()
    if not clientCloud then return end
    if not M._exchangeDailyCloudLoaded then return end
    if M._exchangeDailyCloudFailed then return end  -- 加载失败时禁止写入，防空数据覆盖
    clientCloud:Set("exchange_daily", {
        dayKey = M.exchangeDailyDayKey,
        bought = M.exchangeDailyBought,
    }, {
        ok = function() end,
        error = function(code, reason)
            print("[ExchangeDaily] 云端保存失败:", code, reason)
        end,
    })
end

--- 获取兑奖机物品的每日限购剩余次数（反作弊：使用可信天号+单调递增dayKey）
---@param reward table EXCHANGE_REWARDS 条目
---@return number|nil remaining 剩余次数，nil 表示无限购，-1 表示服务器时间不可用
---@return string|nil reason 不可用时的原因
function M.getExchangeDailyRemaining(reward)
    if not reward.dailyLimit then return nil end
    -- 懒加载：首次访问时触发云端加载
    M.loadExchangeDailyFromCloud()
    -- 云端限购数据未加载完成时阻塞
    if not M._exchangeDailyCloudLoaded then
        return -1, "限购数据加载中"
    end
    if M._exchangeDailyCloudFailed then
        return -1, "限购数据加载失败"
    end
    local SignIn = require("SignInSystem")
    -- 服务器时间不可用时阻塞限购物品兑换
    local reliable, reason = SignIn.isAdminTimeReliable()
    if not reliable then
        return -1, reason
    end
    local today = SignIn.getTrustedDay()
    -- 新的一天：重置计数（dayKey 单调递增，防止回调时间刷购买次数）
    if today > M.exchangeDailyDayKey then
        M.exchangeDailyBought = {}
        M.exchangeDailyDayKey = today
        M.saveExchangeDailyToCloud()
    end
    -- today <= exchangeDailyDayKey 时不重置（防回调）
    local bought = M.exchangeDailyBought[reward.id] or 0
    return math.max(0, reward.dailyLimit - bought)
end

--- 进入兑换模式
function M.enterExchangeMode()
    -- 懒加载：打开兑换界面时触发云端限购数据加载
    M.loadExchangeDailyFromCloud()
    M.exchangeMode = true
    M.exchangeItemRects = {}
    M.exchangeScrollY = 0
    M.exchangeBuyConfirmVisible = false
    M.exchangeBuyConfirmItem = nil
    M.exchangeBuyQuantity = 1
    M.exchangeBuyMsg = nil
    M.exchangeScrollBarDragging = false
    M.exchangeScrollBarTrack = nil
    M.exchangeScrollBarRect = nil
    M.exchangeListDragging = false
    M.exchangeListClipRect = nil
    M.exchangeContentH = 0
    M.exchangeVisibleH = 0
    M.activeBottomTab = 2  -- 切换到背包标签
end

--- 退出兑换模式
function M.exitExchangeMode()
    M.exchangeMode = false
    M.exchangeItemRects = {}
    M.exchangeScrollY = 0
    M.exchangeBuyConfirmVisible = false
    M.exchangeBuyConfirmItem = nil
    M.exchangeBuyQuantity = 1
    M.exchangeBuyMsg = nil
    M.exchangeScrollBarDragging = false
    M.exchangeScrollBarTrack = nil
    M.exchangeScrollBarRect = nil
    M.exchangeListDragging = false
    M.exchangeListClipRect = nil
    M.exchangeContentH = 0
    M.exchangeVisibleH = 0
end

--- 兑换奖品（扣除感恩礼券，发放奖励）
---@param rewardIdx number 奖品索引
---@param quantity number 数量
---@return boolean success
---@return string message
function M.exchangeReward(rewardIdx, quantity)
    quantity = quantity or 1
    local reward = M.EXCHANGE_REWARDS[rewardIdx]
    if not reward then return false, "未知奖品" end

    -- 每日限购检查（反作弊：使用可信天号）
    if reward.dailyLimit then
        local remaining, reason = M.getExchangeDailyRemaining(reward)
        if remaining == -1 then
            return false, reason or "服务器时间不可用，暂时无法兑换限购物品"
        end
        if remaining <= 0 then
            return false, "今日兑换次数已用完"
        end
        if quantity > remaining then
            return false, "今日剩余兑换次数不足（剩余" .. remaining .. "次）"
        end
    end

    local totalCost = reward.ticketCost * quantity
    local owned = M.countInventoryItem("gratitude_ticket")
    if owned < totalCost then
        return false, "感恩礼券不足"
    end

    -- 扣除礼券
    M.removeInventoryItem("gratitude_ticket", totalCost)

    -- 发放奖励
    if reward.rewardType == "gold" then
        M.gold = M.gold + reward.rewardAmount * quantity
    elseif reward.rewardType == "item" then
        for _ = 1, quantity do
            local ok, msg = M.addToInventory(reward.rewardItemId, 1)
            if not ok then
                return true, reward.name .. " 兑换成功，但" .. msg
            end
        end
    end

    -- 扣减库存
    reward.stock = math.max(0, (reward.stock or 0) - quantity)

    -- 记录每日限购购买次数并保存到云端
    if reward.dailyLimit then
        M.exchangeDailyBought[reward.id] = (M.exchangeDailyBought[reward.id] or 0) + quantity
        M.saveExchangeDailyToCloud()
    end

    return true, reward.name .. " x" .. quantity .. " 兑换成功"
end

-- ===== 深渊兑换物品表 =====
-- crystalCost: 消耗深渊结晶数量；pointsCost: 消耗深渊积分数量（二选一）
-- 目前第一项用结晶换积分，后续装备用积分兑换
M.ABYSS_EXCHANGE_ITEMS = {
    { id = "abyss_point_1", name = "深渊积分", desc = "99*深渊结晶兑换1深渊积分",
      crystalCost = 99, rewardType = "abyssPoints", rewardAmount = 1,
      icon = "image/item_abyss_crystal.png", stock = 9999,
      templateId = "abyss_crystal" },
    { id = "abyss_balo_ring", name = "\"巴洛骑士戒指\"",
      desc = "100深渊积分兑换",
      pointsCost = 100, rewardType = "abyssItem", rewardItemId = "balo_hero_ring",
      icon = "image/item_balo_hero_ring.png", stock = 9999,
      templateId = "balo_hero_ring" },
    { id = "abyss_fire_witch_belt", name = "\"火魔女\"",
      desc = "100深渊积分兑换",
      pointsCost = 100, rewardType = "abyssItem", rewardItemId = "fire_witch_belt",
      icon = "image/item_fire_witch_belt.png", stock = 9999,
      templateId = "fire_witch_belt" },
    { id = "abyss_prayer_day_shoulder", name = "\"祷告日\"",
      desc = "100深渊积分兑换",
      pointsCost = 100, rewardType = "abyssItem", rewardItemId = "prayer_day_shoulder",
      icon = "image/item_prayer_day_shoulder.png", stock = 9999,
      templateId = "prayer_day_shoulder" },
    { id = "abyss_shadow_association", name = "\"影子协会\"",
      desc = "100深渊积分兑换",
      pointsCost = 100, rewardType = "abyssItem", rewardItemId = "shadow_association",
      icon = "image/item_shadow_association.png", stock = 9999,
      templateId = "shadow_association" },
    { id = "abyss_forest_guardian", name = "\"守林人\"",
      desc = "100深渊积分兑换",
      pointsCost = 100, rewardType = "abyssItem", rewardItemId = "forest_guardian",
      icon = "image/item_forest_guardian.png", stock = 9999,
      templateId = "forest_guardian" },
    { id = "abyss_balo_manor_hurricane", name = "\"巴洛庄园飓风\"",
      desc = "100深渊积分兑换",
      pointsCost = 100, rewardType = "abyssItem", rewardItemId = "balo_manor_hurricane",
      icon = "image/item_balo_manor_hurricane.png", stock = 9999,
      templateId = "balo_manor_hurricane" },
}

-- ===== 深渊兑换模式 =====
M.abyssExchangeMode = false
M.abyssExchangeCloseRect = nil
M.abyssExchangeItemRects = {}   -- 每行兑换按钮区域（含 rowX/Y/W/H, iconX/Y/W/H）
M.abyssExchangeScrollY = 0
M.abyssExchangeListClipRect = nil
M.abyssExchangeContentH = 0
M.abyssExchangeVisibleH = 0
M.abyssExchangeMsg = nil
M.abyssExchangeListDragging = false
M.abyssExchangeListDragMoved = false
M.abyssExchangeListDragStartY = 0
M.abyssExchangeListDragStartScroll = 0

--- 进入深渊兑换模式
function M.enterAbyssExchangeMode()
    M.abyssExchangeMode = true
    M.abyssExchangeCloseRect = nil
    M.abyssExchangeItemRects = {}
    M.abyssExchangeScrollY = 0
    M.abyssExchangeListClipRect = nil
    M.abyssExchangeContentH = 0
    M.abyssExchangeVisibleH = 0
    M.abyssExchangeMsg = nil
    M.abyssExchangeListDragging = false
    M.abyssExchangeListDragMoved = false
    M.abyssExchangeListDragStartY = 0
    M.abyssExchangeListDragStartScroll = 0
    M.activeBottomTab = 2  -- 切换到背包标签
end

--- 退出深渊兑换模式
function M.exitAbyssExchangeMode()
    M.abyssExchangeMode = false
    M.abyssExchangeCloseRect = nil
    M.abyssExchangeItemRects = {}
    M.abyssExchangeScrollY = 0
    M.abyssExchangeListClipRect = nil
    M.abyssExchangeContentH = 0
    M.abyssExchangeVisibleH = 0
    M.abyssExchangeMsg = nil
    M.abyssExchangeListDragging = false
    M.abyssExchangeListDragMoved = false
    -- 清除本面板产生的 tooltip
    if M.tooltipSource == "abyss_exchange" then
        M.tooltipItem = nil
        M.tooltipPinned = false
        M.tooltipPinnedPos = nil
        M.tooltipSource = "inventory"
    end
end

--- 执行深渊兑换
---@param itemIdx number ABYSS_EXCHANGE_ITEMS 索引
---@return boolean success
---@return string message
function M.performAbyssExchange(itemIdx)
    itemIdx = itemIdx or 1
    local item = M.ABYSS_EXCHANGE_ITEMS[itemIdx]
    if not item then return false, "未知兑换项目" end

    -- 消耗深渊结晶
    if item.crystalCost and item.crystalCost > 0 then
        local owned = M.countInventoryItem("abyss_crystal")
        if owned < item.crystalCost then
            return false, "深渊结晶不足（需要" .. item.crystalCost .. "个，拥有" .. owned .. "个）"
        end
        local ok, msg = M.removeInventoryItem("abyss_crystal", item.crystalCost)
        if not ok then
            return false, "兑换失败：" .. (msg or "未知错误")
        end
    end

    -- 消耗深渊积分
    if item.pointsCost and item.pointsCost > 0 then
        if (M.abyssPoints or 0) < item.pointsCost then
            return false, "深渊积分不足（需要" .. item.pointsCost .. "个）"
        end
        M.abyssPoints = M.abyssPoints - item.pointsCost
    end

    -- 发放奖励
    local rewardAmount = item.rewardAmount or 1
    if item.rewardType == "abyssPoints" then
        M.abyssPoints = (M.abyssPoints or 0) + rewardAmount
    elseif item.rewardType == "item" and item.rewardItemId then
        for _ = 1, rewardAmount do
            local ok, msg = M.addToInventory(item.rewardItemId, 1)
            if not ok then
                M.saveToCloud()
                return true, item.name .. " 兑换成功，但" .. msg
            end
        end
    elseif item.rewardType == "abyssItem" and item.rewardItemId then
        -- 生成带深渊随机属性 + 1条深渊词缀的装备，无附魔/精炼/宝石槽
        local ok, msg, addedItem = M.addToInventory(item.rewardItemId, 1)
        if not ok then
            M.saveToCloud()
            return true, item.name .. " 兑换成功，但" .. msg
        end
        if addedItem then
            local tpl = M.itemTemplates[item.rewardItemId]
            -- 设置等级对应 tier
            local itemLevel = (tpl and tpl.level) or 1
            addedItem.tier = M.getTierByLevel(itemLevel)
            -- 处理 abyssRandomStats（完整随机化，与卓越掉落逻辑一致）
            local abyssRand = tpl and tpl.abyssRandomStats
            if abyssRand then
                local newEff = {}
                for k, v in pairs(addedItem.effects or {}) do newEff[k] = v end
                addedItem.effects = newEff
                local newExtra = {}
                for k, v in pairs(addedItem.extraEffects or {}) do newExtra[k] = v end
                addedItem.extraEffects = newExtra
                local statTiers = {}
                -- effects 随机化
                if abyssRand.effects then
                    for k, rule in pairs(abyssRand.effects) do
                        if rule.type == "pct_uniform" and newEff[k] and rule.values and #rule.values > 0 then
                            local idx = math.random(#rule.values)
                            newEff[k] = math.floor(newEff[k] * (1 + rule.values[idx] / 100) + 0.5)
                            statTiers[k] = idx
                        elseif rule.type == "uniform" and rule.values and #rule.values > 0 then
                            local idx = math.random(#rule.values)
                            newEff[k] = rule.values[idx]
                            statTiers[k] = idx
                        end
                    end
                end
                -- extraEffects 随机化
                if abyssRand.extraEffects then
                    for k, rule in pairs(abyssRand.extraEffects) do
                        if rule.type == "uniform" and rule.values and #rule.values > 0 then
                            local idx = math.random(#rule.values)
                            newExtra[k] = rule.values[idx]
                            statTiers[k] = idx
                        end
                    end
                end
                -- allstat_lines
                if abyssRand.allstat_lines then
                    local asl = abyssRand.allstat_lines
                    local lineResults = {}
                    for i = 1, (asl.count or 1) do
                        local idx = math.random(#asl.values)
                        local val = asl.values[idx]
                        lineResults[i] = { value = val, tier = idx }
                        for _, k in ipairs(asl.keys) do
                            newExtra[k] = (newExtra[k] or 0) + val
                        end
                    end
                    addedItem.allstatLines = lineResults
                end
                -- randomResist（支持单对象或数组）
                if abyssRand.randomResist then
                    local rrList = abyssRand.randomResist
                    if rrList.pool then rrList = { rrList } end
                    local resistResults = {}
                    for _, rr in ipairs(rrList) do
                        local pool = {}
                        for i, v in ipairs(rr.pool) do pool[i] = v end
                        for i = #pool, 2, -1 do
                            local j = math.random(i)
                            pool[i], pool[j] = pool[j], pool[i]
                        end
                        for i = 1, math.min(rr.count or 3, #pool) do
                            local key = pool[i]
                            local idx = math.random(#rr.values)
                            local val = rr.values[idx]
                            newExtra[key] = val
                            statTiers[key] = idx
                            resistResults[#resistResults + 1] = { key = key, value = val, tier = idx }
                        end
                    end
                    addedItem.randomResistLines = resistResults
                end
                -- randomMainBase
                if abyssRand.randomMainBase then
                    local rmb = abyssRand.randomMainBase
                    local pool = {}
                    for i, v in ipairs(rmb.pool) do pool[i] = v end
                    for i = #pool, 2, -1 do
                        local j = math.random(i)
                        pool[i], pool[j] = pool[j], pool[i]
                    end
                    local baseLines = {}
                    for i = 1, math.min(rmb.count or 1, #pool) do
                        local key = pool[i]
                        local val, tier
                        if rmb.values and #rmb.values > 0 then
                            tier = math.random(#rmb.values)
                            val  = rmb.values[tier]
                        else
                            val  = rmb.value or 1
                        end
                        newEff[key] = (newEff[key] or 0) + val
                        statTiers[key] = tier  -- 记录档位，用于 tooltip 档位颜色/三角指示
                        baseLines[i] = { key = key, value = val, tier = tier }
                    end
                    addedItem.randomMainBaseLines = baseLines
                end
                -- randomMainExtra
                if abyssRand.randomMainExtra then
                    local rme = abyssRand.randomMainExtra
                    local extraLines = {}
                    for i = 1, (rme.count or 1) do
                        local key = rme.pool[math.random(#rme.pool)]
                        local idx = math.random(#rme.values)
                        local val = rme.values[idx]
                        newExtra[key] = (newExtra[key] or 0) + val
                        extraLines[i] = { key = key, value = val, tier = idx }
                    end
                    addedItem.randomMainExtraLines = extraLines
                end
                addedItem.abyssStatTiers = statTiers
                addedItem.hasRandom = true
                -- 记录模板版本，防止将来版本升级时重新触发 reroll
                addedItem.templateVersion = tpl.templateVersion or 1
            end
            -- 随机深渊词缀（模板标记 noAbyssAffix 时跳过）
            if not tpl.noAbyssAffix then
                local roll = M.ABYSS_AFFIX_POOL[math.random(#M.ABYSS_AFFIX_POOL)]
                addedItem.abyssAffix = {
                    id       = roll.id,
                    name     = roll.name,
                    desc     = roll.desc,
                    mechanic = roll.mechanic,
                }
            end
        end
    end

    M.saveToCloud()
    return true, item.name .. " 兑换成功！"
end

end  -- sub.init

return sub
