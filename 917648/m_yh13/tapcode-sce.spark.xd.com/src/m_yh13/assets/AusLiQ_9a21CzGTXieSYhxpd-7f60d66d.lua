local Config = require("diggin.Config")
local AbyssContent = require("diggin.AbyssContent")

local WorldTree = {}

WorldTree.CAPSTONES = {
    "FallingPickaxe",
    "TermiteDrones",
    "Molenir",
    "TheWorm",
}

local TIER_COUNTS = { 1, 3, 5, 7, 9 }

local function pct(label)
    return function(value) return string.format("%s +%s%%", label, tostring(value)) end
end

local function flat(label)
    return function(value) return string.format("%s +%s", label, tostring(value)) end
end

local BRANCH_DEFINITIONS = {
    {
        id = "giant",
        name = "巨镐之冠",
        capstone = "FallingPickaxe",
        rootId = "root_damage",
        direction = { 0, -1 },
        color = Config.Palette.red,
        rootStat = "global_damage_pct",
        rootValue = 6,
        rootEffect = "钻头与四大技能伤害 +6%/级",
        itemId = "starcore_bomb",
        itemName = "星核爆钻",
        names = {
            "巨镐根脉", "铁脊齿", "裂岩锋", "震层柄", "陨星握",
            "红晶刃", "星核爆钻", "穿层尖", "崩山势", "暴击刻痕",
            "磁轨镐", "地震回响", "碎甲棱", "过载钻尖", "岩浆锤",
            "天穹落镐", "双重陨击", "星火刃阵", "深核穿透", "极限转速",
            "王冠镐卫", "破界齿轮", "陨铁共振", "巨镐奔袭", "世界裂口",
        },
        icons = {
            "FallingPickaxe", "MiningDamage1", "MiningDamage2", "MiningDamage3", "MiningDamage4",
            "CritDamage1", "DynamiteActive", "MiningRate1", "ShockwaveActive", "CritChance1",
            "DrillMissiles", "Aftershocks", "DrillMissileDamage", "OverdriveStrength", "BoomstoneDamage",
            "FallingPickaxe", "AftershockAmount", "Shrapnel", "DrillMissileAoE", "MiningSpeed",
            "SpinningPickaxeDamage", "ShockwaveDamage", "DynamiteDamage2", "FallingPickaxe", "CritArtefact",
        },
        effects = {
            { stat = "abyss_drill_damage_pct", base = 4, growth = 2, text = pct("深渊钻头伤害") },
            { stat = "capstone_damage_pct", base = 5, growth = 2, text = pct("四大技能伤害") },
            { stat = "capstone_cooldown_pct", base = 2, growth = 1, text = pct("四大技能冷却缩减") },
            { stat = "world_item_power_pct", base = 6, growth = 3, text = pct("世界树道具威力") },
            { stat = "abyss_critical_chance_flat", base = 1, growth = 0.5, text = pct("深渊暴击率") },
            { stat = "abyss_critical_damage_pct", base = 8, growth = 4, text = pct("深渊暴击伤害") },
        },
    },
    {
        id = "drone",
        name = "无人机蜂巢",
        capstone = "TermiteDrones",
        rootId = "root_fuel",
        direction = { 1, 0 },
        color = Config.Palette.cyan,
        rootStat = "fuel_capacity_pct",
        rootValue = 8,
        rootEffect = "深渊最大燃料 +8%/级",
        itemId = "amber_swarm",
        itemName = "琥珀蜂群",
        names = {
            "无人机蜂巢", "燃芯薄膜", "回收翼", "蜂巢储槽", "冷凝管",
            "琥珀电池", "琥珀蜂群", "节流阀", "伴飞翼", "深层雷达",
            "修复蜂", "脉冲桨", "燃料镜面", "蜂群协议", "自律采掘",
            "增压囊", "零损耗管", "光翼矩阵", "深渊续航", "反冲推进",
            "群体回充", "永动节拍", "蜂后指令", "无人机军团", "天穹蜂巢",
        },
        icons = {
            "TermiteDrones", "FuelEfficiency1", "DrillDrones", "FuelTank1", "FuelEfficiency2",
            "Fuelstone", "TermiteDrones", "FuelEfficiency3", "DrillDroneSpeed", "FieldOfView1",
            "DrillDroneArtefact", "MovementSpeed1", "FuelTank2", "DrillDroneCount", "Collector",
            "FuelTank3", "FuelEfficiency4", "TermiteDrones", "FuelTank4", "OverdriveActive",
            "FuelstoneFrequency", "FuelTank5", "DrillDroneDamage", "TermiteDrones", "LaserCapacity",
        },
        effects = {
            { stat = "fuel_capacity_pct", base = 2, growth = 1, text = pct("深渊最大燃料") },
            { stat = "fuel_efficiency_pct", base = 3, growth = 1, text = pct("深渊燃料效率") },
            { stat = "abyss_move_speed_pct", base = 2, growth = 1, text = pct("深渊移动速度") },
            { stat = "world_item_cooldown_pct", base = 3, growth = 1, text = pct("世界树道具冷却缩减") },
            { stat = "capstone_cooldown_pct", base = 2, growth = 1, text = pct("四大技能冷却缩减") },
            { stat = "abyss_fuel_regen", base = 0.08, growth = 0.04, text = flat("深渊每秒燃料恢复") },
        },
    },
    {
        id = "mole",
        name = "鼹神圣域",
        capstone = "Molenir",
        rootId = "root_headstart",
        direction = { 0, 1 },
        color = Config.Palette.gold,
        rootStat = "headstart",
        rootValue = 10,
        rootEffect = "巨物初始距离 +10/级",
        itemId = "root_aegis",
        itemName = "生命根盾",
        names = {
            "鼹神庇护", "岩甲祷文", "预警须", "缓冲爪", "退潮印",
            "护根结界", "生命根盾", "厚土壳", "吞噬延迟", "守望眼",
            "根墙", "安全绳", "震退爪", "石肤层", "不屈穴",
            "再生甲", "警戒环", "缓时土", "反扑根", "深穴壁垒",
            "守门图腾", "大地脉搏", "终末护盾", "鼹神之锤", "永恒地窟",
        },
        icons = {
            "Molenir", "LastDitchEffort", "FieldOfView2", "Boomstone", "ShockwaveRadius",
            "LastDitchArtefact", "Molenir", "FuelTank2", "AftershockSpread", "FieldOfView4",
            "BoomstoneRange", "MovementSpeed1", "ShockwaveActive", "FuelTank3", "LastDitchEffort",
            "FuelEfficiency4", "FieldOfView4", "Aftershocks", "Molenir", "WorldSize2",
            "BoomstoneDamage2", "ShockwaveDamage", "LastDitchArtefact", "Molenir", "WorldSize4",
        },
        effects = {
            { stat = "headstart", base = 4, growth = 2, text = flat("巨物初始距离") },
            { stat = "monster_slow_pct", base = 1.5, growth = 0.5, text = pct("巨物移动减速") },
            { stat = "warning_gap", base = 2, growth = 1, text = flat("危险预警距离") },
            { stat = "aegis_push", base = 6, growth = 3, text = flat("生命根盾击退距离") },
            { stat = "aegis_recharge_pct", base = 4, growth = 2, text = pct("生命根盾充能加速") },
            { stat = "aegis_charge_bonus", base = 1, growth = 0, text = flat("生命根盾最大层数") },
        },
    },
    {
        id = "worm",
        name = "地龙年轮",
        capstone = "TheWorm",
        rootId = "root_yield",
        direction = { -1, 0 },
        color = Config.Palette.purple,
        rootStat = "point_yield_pct",
        rootValue = 8,
        rootEffect = "世界树点数 +8%/级",
        itemId = "chronobloom",
        itemName = "时光花",
        names = {
            "地龙年轮", "星尘芽", "丰收须", "异变刻度", "深度印",
            "时间花苞", "时光花", "宝箱嗅觉", "黄金年轮", "矿脉记忆",
            "星辰枝", "丰产环", "险区账簿", "深层红利", "年轮加速",
            "宝藏脉冲", "点数孢子", "异变共鸣", "时间延展", "终局丰收",
            "星河根系", "永生刻痕", "深渊账册", "地龙王", "世界果实",
        },
        icons = {
            "TheWorm", "Feverstone", "Collector", "ResourceTripler", "WorldSize1",
            "FeverstoneDuration", "TheWorm", "GoldBonanza", "AugmentGold", "CollectorSpeed",
            "FeverstoneSpawnRate", "CollectorMult", "BoomstoneSpawnRate", "PlatinumBonanza", "MiningRate3",
            "DiamondRefinery", "ResourceTripler", "IridiumBonanza", "FeverstoneDuration", "AugmentPlatinum",
            "Feverstone", "CollectorSpeed", "CollectorMult", "TheWorm", "ResourceTripler",
        },
        effects = {
            { stat = "point_yield_pct", base = 2, growth = 1, text = pct("世界树点数收益") },
            { stat = "score_mult_pct", base = 3, growth = 1, text = pct("深渊生存计分") },
            { stat = "depth_point_pct", base = 3, growth = 1, text = pct("深度点数收益") },
            { stat = "mutation_reward_pct", base = 4, growth = 2, text = pct("异变区域计分") },
            { stat = "chronobloom_duration", base = 0.3, growth = 0.15, text = flat("时光花减速持续秒数") },
            { stat = "world_item_cooldown_pct", base = 3, growth = 1, text = pct("世界树道具冷却缩减") },
        },
    },
}

WorldTree.BRANCHES = BRANCH_DEFINITIONS
WorldTree.NODES = {}
WorldTree.NODE_BY_ID = {}
WorldTree.ITEMS = {}
WorldTree.ITEM_ORDER = {}
WorldTree.LEGACY_ITEM_NODE_MIGRATIONS = {
    wt_giant_07 = "wt_giant_16",
    wt_drone_07 = "wt_drone_16",
    wt_mole_07 = "wt_mole_16",
    wt_worm_07 = "wt_worm_16",
}

WorldTree.MUTATIONS = {
    {
        id = "golden_layer",
        name = "黄金层",
        description = "点数计时 ×1.25",
        icon = Config.Paths.abyssEventGolden,
        speedMultiplier = 1.0,
        scoreMultiplier = 1.25,
        color = Config.Palette.gold,
    },
    {
        id = "explosive_vein",
        name = "爆炸矿脉",
        description = "巨物加速 15% · 点数 ×1.35",
        icon = Config.Paths.abyssEventExplosive,
        speedMultiplier = 1.15,
        scoreMultiplier = 1.35,
        color = Config.Palette.orange,
    },
    {
        id = "chest_cluster",
        name = "宝箱群",
        description = "点数计时 ×1.20",
        icon = Config.Paths.abyssEventChest,
        speedMultiplier = 1.0,
        scoreMultiplier = 1.2,
        color = Config.Palette.gold,
    },
    {
        id = "high_risk",
        name = "高危区域",
        description = "巨物加速 30% · 点数 ×1.60",
        icon = Config.Paths.abyssEventRisk,
        speedMultiplier = 1.3,
        scoreMultiplier = 1.6,
        color = Config.Palette.red,
    },
}

local function numberText(value)
    if math.abs(value - math.floor(value)) < 0.001 then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end

local ITEM_NODE_BY_BRANCH_INDEX = {}
for _, item in ipairs(AbyssContent.WORLD_ITEMS) do
    WorldTree.ITEM_ORDER[#WorldTree.ITEM_ORDER + 1] = item.id
    ITEM_NODE_BY_BRANCH_INDEX[item.branch] = ITEM_NODE_BY_BRANCH_INDEX[item.branch] or {}
    ITEM_NODE_BY_BRANCH_INDEX[item.branch][item.unlockIndex] = { kind = "item", item = item }
    ITEM_NODE_BY_BRANCH_INDEX[item.branch][item.upgradeIndex] = { kind = "item_upgrade", item = item }
end

local function buildBranch(branch)
    local tierStart = {}
    local running = 1
    for tier, count in ipairs(TIER_COUNTS) do
        tierStart[tier] = running
        running = running + count
    end

    local index = 0
    for tier, count in ipairs(TIER_COUNTS) do
        for slot = 1, count do
            index = index + 1
            local id = index == 1 and branch.rootId or string.format("wt_%s_%02d", branch.id, index)
            local radial = 58 + (tier - 1) * 76
            local lateral = (slot - (count + 1) * 0.5) * 34
            local dx, dy = branch.direction[1], branch.direction[2]
            local px, py = -dy, dx
            local node = {
                id = id,
                name = branch.names[index],
                branch = branch.id,
                branchName = branch.name,
                color = branch.color,
                capstone = branch.capstone,
                rootId = branch.rootId,
                icon = branch.icons[index],
                tier = tier,
                slot = slot,
                maxLevel = index == 1 and 8 or 1,
                position = { dx * radial + px * lateral, dy * radial + py * lateral },
                parents = {},
                unlocks = {},
            }

            if tier > 1 then
                local previousCount = TIER_COUNTS[tier - 1]
                local normalized = count == 1 and 0 or (slot - 1) / (count - 1)
                local parentSlot = math.floor(normalized * math.max(0, previousCount - 1) + 0.5) + 1
                local parentIndex = tierStart[tier - 1] + parentSlot - 1
                node.parents[1] = parentIndex == 1 and branch.rootId
                    or string.format("wt_%s_%02d", branch.id, parentIndex)
            end

            local authoredItemNode = ITEM_NODE_BY_BRANCH_INDEX[branch.id]
                and ITEM_NODE_BY_BRANCH_INDEX[branch.id][index]
            if index == 1 then
                node.stat = branch.rootStat
                node.value = branch.rootValue
                node.effect = branch.rootEffect
            elseif authoredItemNode and authoredItemNode.kind == "item" then
                local item = authoredItemNode.item
                node.kind = "item"
                node.itemId = item.id
                node.name = item.name
                node.icon = item.icon
                node.iconAtlasIndex = item.atlasIndex
                node.effect = "解锁深渊专属道具：" .. item.name .. "。" .. item.description
                WorldTree.ITEMS[item.id] = {
                    id = item.id,
                    nodeId = id,
                    masteryNodeId = string.format("wt_%s_%02d", branch.id, item.upgradeIndex),
                    name = item.name,
                    branch = branch.id,
                    icon = item.icon,
                    iconIndex = item.atlasIndex,
                    color = item.color,
                    description = item.description,
                }
            elseif authoredItemNode and authoredItemNode.kind == "item_upgrade" then
                local item = authoredItemNode.item
                node.kind = "item_upgrade"
                node.itemId = item.id
                node.name = item.name .. "精通"
                node.icon = item.icon
                node.iconAtlasIndex = item.atlasIndex
                node.stats = item.masteryStats or {
                    [item.id .. "_power_pct"] = 30,
                    [item.id .. "_cooldown_pct"] = 8,
                }
                node.effect = item.mastery
            else
                local effect = branch.effects[((index - 2) % #branch.effects) + 1]
                local value = effect.base + (tier - 1) * effect.growth
                value = tonumber(numberText(value)) or value
                node.stat = effect.stat
                node.value = value
                node.effect = effect.text(numberText(value))
            end

            WorldTree.NODES[#WorldTree.NODES + 1] = node
            WorldTree.NODE_BY_ID[id] = node
        end
    end
end

for _, branch in ipairs(BRANCH_DEFINITIONS) do buildBranch(branch) end
require("diggin.WorldTreeEarly").Add(WorldTree, Config)
require("diggin.DrillMechanicsCatalog").ReplaceNodes(WorldTree)
for _, node in ipairs(WorldTree.NODES) do
    for _, parentId in ipairs(node.parents) do
        local parent = WorldTree.NODE_BY_ID[parentId]
        if parent then parent.unlocks[#parent.unlocks + 1] = node.id end
    end
end

function WorldTree.GetCapstoneCount(state)
    local count = 0
    for _, nodeId in ipairs(WorldTree.CAPSTONES) do
        if state:IsNodeBought(nodeId) then count = count + 1 end
    end
    return count
end

function WorldTree.GetMissingCapstoneNames(state)
    local missing = {}
    for _, nodeId in ipairs(WorldTree.CAPSTONES) do
        if not state:IsNodeBought(nodeId) then
            local node = state.nodeById and state.nodeById[nodeId]
            missing[#missing + 1] = node and node.name or nodeId
        end
    end
    return missing
end

function WorldTree.HasAllCapstones(state)
    return WorldTree.GetCapstoneCount(state) == #WorldTree.CAPSTONES
end

function WorldTree.GetFullyMaxedNodeCount(state)
    local count = 0
    for _, node in ipairs(WorldTree.NODES) do
        if WorldTree.GetLevel(state, node.id) >= node.maxLevel then count = count + 1 end
    end
    return count
end

function WorldTree.IsFullyMaxed(state)
    return state ~= nil and WorldTree.GetFullyMaxedNodeCount(state) == #WorldTree.NODES
end

function WorldTree.GetLevel(state, nodeId)
    return math.max(0, math.floor(tonumber(state.worldTreeLevels and state.worldTreeLevels[nodeId]) or 0))
end

function WorldTree.IsAvailable(state, node)
    if not node or state.worldTreeAwakened ~= true then return false end
    if #node.parents == 0 then return true end
    local rootRequirement = ({ 0, 2, 4, 6, 8 })[node.tier] or 8
    if WorldTree.GetLevel(state, node.rootId) < rootRequirement then return false end
    for _, parentId in ipairs(node.parents) do
        if WorldTree.GetLevel(state, parentId) > 0 then return true end
    end
    return false
end

function WorldTree.IsVisible(state, node)
    return node ~= nil and (WorldTree.GetLevel(state, node.id) > 0
        or #node.parents == 0 or WorldTree.IsAvailable(state, node))
end

function WorldTree.GetCost(state, nodeId)
    local node = WorldTree.NODE_BY_ID[nodeId]
    if not node then return 0 end
    local level = WorldTree.GetLevel(state, nodeId)
    if node.cost then return node.cost + level * (node.costGrowth or 0) end
    if node.maxLevel > 1 then return 2 + level * 2 end
    local tierCost = ({ 2, 4, 8, 14, 22 })[node.tier] or 22
    if node.kind == "item" then tierCost = tierCost + 8
    elseif node.kind == "item_upgrade" then tierCost = tierCost + 4 end
    return tierCost
end

function WorldTree.CanBuy(state, nodeId)
    local node = WorldTree.NODE_BY_ID[nodeId]
    if not node or not WorldTree.IsAvailable(state, node) then return false end
    if WorldTree.GetLevel(state, nodeId) >= node.maxLevel then return false end
    return math.floor(tonumber(state.worldTreePoints) or 0) >= WorldTree.GetCost(state, nodeId)
end

function WorldTree.GetStat(state, statId)
    local total = 0
    for _, node in ipairs(WorldTree.NODES) do
        if node.stat == statId then
            total = total + WorldTree.GetLevel(state, node.id) * (tonumber(node.value) or 0)
        end
        if node.stats and node.stats[statId] then
            total = total + WorldTree.GetLevel(state, node.id) * (tonumber(node.stats[statId]) or 0)
        end
    end
    return total
end

function WorldTree.IsItemUnlocked(state, itemId)
    local item = WorldTree.ITEMS[itemId]
    return item ~= nil and WorldTree.GetLevel(state, item.nodeId) > 0
end

function WorldTree.CanEnterAbyss(state)
    return state.worldTreeAwakened == true and state:IsFinalDensityUnlocked()
end

function WorldTree.GetUnlockReason(state)
    local capstones = WorldTree.GetCapstoneCount(state)
    if capstones < #WorldTree.CAPSTONES then
        local missing = WorldTree.GetMissingCapstoneNames(state)
        return string.format("需解锁四个终极技能（%d/4）· 缺少：%s",
            capstones, table.concat(missing, "、"))
    end
    if not state:IsFinalDensityUnlocked() then
        return string.format("需集齐 10 颗星辰（%d/10）", state:GetDensityStarCount())
    end
    return "深渊矿脉已开启"
end

function WorldTree.GetDamageMultiplier(state)
    return 1 + WorldTree.GetStat(state, "global_damage_pct") / 100
end

function WorldTree.GetAbyssFuelMultiplier(state)
    return 1 + WorldTree.GetStat(state, "fuel_capacity_pct") / 100
end

function WorldTree.GetHeadStartDistance(state)
    return WorldTree.GetStat(state, "headstart")
end

function WorldTree.GetPointMultiplier(state)
    return 1 + WorldTree.GetStat(state, "point_yield_pct") / 100
end

function WorldTree.GetCapstoneDamageMultiplier(state)
    return 1 + WorldTree.GetStat(state, "capstone_damage_pct") / 100
end

function WorldTree.GetCapstoneCooldownMultiplier(state)
    return math.max(0.35, 1 - WorldTree.GetStat(state, "capstone_cooldown_pct") / 100)
end

function WorldTree.GetWorldItemPowerMultiplier(state)
    return 1 + WorldTree.GetStat(state, "world_item_power_pct") / 100
end

function WorldTree.GetWorldItemCooldownMultiplier(state)
    return math.max(0.35, 1 - WorldTree.GetStat(state, "world_item_cooldown_pct") / 100)
end

function WorldTree.GetMonsterSpeedMultiplier(state)
    return math.max(0.55, 1 - WorldTree.GetStat(state, "monster_slow_pct") / 100)
end

function WorldTree.GetScoreMultiplier(state)
    return 1 + WorldTree.GetStat(state, "score_mult_pct") / 100
end

function WorldTree.GetDepthPointMultiplier(state)
    return 1 + WorldTree.GetStat(state, "depth_point_pct") / 100
end

function WorldTree.GetMutationRewardMultiplier(state)
    return 1 + WorldTree.GetStat(state, "mutation_reward_pct") / 100
end

return WorldTree
