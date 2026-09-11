-- ============================================================
-- BulletinBoard.lua  —— 布告栏每日委托系统
-- 每个现实自然日刷新 5 个委托，基于玩家等级/采集等级
-- ============================================================
local GS   -- 延迟绑定 GameState
local MonsterDB = require("data.MonsterDB")

local M = {}

-- ======================== 常量 ========================

--- 委托类型
M.QUEST_TYPES = {
    RARE_KILL   = 1,   -- 击杀稀有怪物 x1
    NORMAL_KILL = 2,   -- 击杀普通怪物 x30
    DROP_SUBMIT = 3,   -- 提交怪物掉落物 x15
    PLANT_GATHER = 4,  -- 提交植物采集物 x3
    MINE_GATHER  = 5,  -- 提交矿石采集物 x3
}

M.QUEST_COUNT = 5

--- 每种委托的目标数量
local QUEST_AMOUNTS = {
    [1] = 1,   -- 稀有怪物击杀
    [2] = 30,  -- 普通怪物击杀
    [3] = 15,  -- 怪物掉落物提交
    [4] = 3,   -- 植物采集物提交
    [5] = 3,   -- 矿石采集物提交
}

--- 基于玩家刷新时等级的委托奖励表 { [level] = { exp, gold } }
--- 实际发放时上下随机浮动 10% 取整
local QUEST_REWARD_TABLE = {
    [1]={10,300},[2]={19,315},[3]={27,330},[4]={34,347},[5]={40,364},
    [6]={49,382},[7]={50,402},[8]={50,422},[9]={53,443},[10]={55,465},
    [11]={58,488},[12]={60,513},[13]={63,538},[14]={65,565},[15]={67,593},
    [16]={69,623},[17]={70,654},[18]={71,687},[19]={72,721},[20]={73,758},
    [21]={74,795},[22]={75,835},[23]={75,877},[24]={76,921},[25]={76,967},
    [26]={76,1015},[27]={81,1066},[28]={86,1120},[29]={91,1176},[30]={105,1234},
    [31]={122,1296},[32]={140,1361},[33]={161,1429},[34]={185,1500},[35]={211,1576},
    [36]={242,1654},[37]={275,1737},[38]={313,1824},[39]={355,1915},[40]={400,2011},
    [41]={450,2111},[42]={504,2217},[43]={562,2328},[44]={622,2444},[45]={685,2567},
    [46]={747,2695},[47]={869,2830},[48]={1011,2971},[49]={1174,3120},[50]={1362,3276},
    [51]={1579,3440},[52]={1828,3612},[53]={2113,3792},[54]={2439,3982},[55]={2811,4181},
    [56]={3235,4390},[57]={3771,4610},[58]={4392,4840},[59]={5111,5082},[60]={5941,5336},
    [61]={6899,5603},[62]={8003,5883},[63]={9273,6178},[64]={10730,6487},[65]={12399,6811},
    [66]={14306,7151},[67]={16480,7509},[68]={18952,7885},[69]={21754,8279},[70]={24918,8693},
    [71]={28478,9127},[72]={32464,9584},[73]={36907,10063},[74]={41828,10566},[75]={47241,11095},
    [76]={53146,11649},[77]={59523,12232},[78]={66326,12843},[79]={76529,13486},[80]={88162,14160},
    [81]={101386,14868},[82]={116374,15611},[83]={133301,16392},[84]={152343,17212},[85]={173671,18072},
    [86]={197437,18976},[87]={223762,19925},[88]={252719,20921},[89]={284309,21967},[90]={318426,23065},
    [91]={354817,24219},[92]={393028,25430},[93]={432331,26701},[94]={471634,28036},[95]={509365,29438},
    [96]={543322,30910},[97]={570488,32455},[98]={586788,34078},[99]={593394,35782},[100]={600000,37571},
}

-- ======================== 工具函数 ========================

--- DJB2 哈希（确定性随机种子）
local function djb2(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) & 0x7FFFFFFF
    end
    return hash
end

--- 基于种子的确定性伪随机数生成器（LCG）
---@param seed number
---@return number newSeed, number value01
local function lcgNext(seed)
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed, (seed % 10000) / 10000
end

--- 获取指定等级的委托奖励（含 ±10% 随机浮动）
---@param playerLevel number
---@param seed number LCG种子
---@return number expReward, number goldReward, number newSeed
local function getQuestReward(playerLevel, seed)
    local lv = math.max(1, math.min(100, playerLevel))
    local entry = QUEST_REWARD_TABLE[lv]
    if not entry then entry = QUEST_REWARD_TABLE[100] end
    local baseExp, baseGold = entry[1], entry[2]
    -- ±10% 浮动
    local s1, r1 = lcgNext(seed)
    local s2, r2 = lcgNext(s1)
    local expMul = 0.9 + r1 * 0.2   -- 0.9 ~ 1.1
    local goldMul = 0.9 + r2 * 0.2  -- 0.9 ~ 1.1
    return math.floor(baseExp * expMul + 0.5), math.floor(baseGold * goldMul + 0.5), s2
end

--- 从列表中确定性地选一个
---@param list table
---@param seed number
---@return any item, number newSeed
local function pickFromList(list, seed)
    if #list == 0 then return nil, seed end
    local newSeed, val = lcgNext(seed)
    local idx = math.floor(val * #list) + 1
    if idx > #list then idx = #list end
    return list[idx], newSeed
end

-- ======================== 候选池构建 ========================

--- 不应出现在委托中的怪物（副本怪、仅在采集区出现的怪、特殊怪）
local QUEST_BLACKLIST = {
    -- 副本：史莱姆王国
    slime_elite = true, fire_slime_elite = true, ice_slime_elite = true, elec_slime_elite = true,
    slime_princess = true, slime_prince = true, slime_king = true,
    -- 副本：哥布林竞技场
    goblin_warrior_arena = true,
    goblin_boss_diwu = true,
    goblin_boss_dila = true,
    goblin_boss_dikata = true,
    -- 仅在采集区出现
    fire_slime = true, ice_slime = true, elec_slime = true,
    -- 特殊怪物
    red_dragon_young = true, freya = true, training_dummy = true,
    -- 大反击专属
    goblin_hero_dihata = true,
    -- 酒馆NPC（不应成为委托目标）
    tavern_thug = true, drunk_man = true, scarface = true,
    tavern_thug_25 = true, drunk_man_25 = true, scarface_25 = true,
    -- 超出玩家等级上限的怪物（保险黑名单）
    gargoyle = true, castle_slime = true,
}

--- 获取稀有怪物候选列表（有 dropGroup 的才算）
---@param minLv number
---@param maxLv number
---@return table[] list  { defId, name, level }
local function getRareMonsters(minLv, maxLv)
    local list = {}
    for defId, mdef in pairs(MonsterDB) do
        if mdef.rarity == "rare" and mdef.dropGroup
           and mdef.level >= minLv and mdef.level <= maxLv
           and not mdef.isTrainingDummy
           and not QUEST_BLACKLIST[defId] then
            list[#list + 1] = { defId = defId, name = mdef.name, level = mdef.level }
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

--- 获取普通怪物候选列表（击杀类）
---@param minLv number
---@param maxLv number
---@return table[] list  { defId, name, level }
local function getNormalMonsters(minLv, maxLv)
    local list = {}
    for defId, mdef in pairs(MonsterDB) do
        if mdef.rarity ~= "rare" and mdef.rarity ~= "fine" and mdef.rarity ~= "superior"
           and mdef.level >= minLv and mdef.level <= maxLv
           and not mdef.isTrainingDummy
           and not QUEST_BLACKLIST[defId] then
            list[#list + 1] = { defId = defId, name = mdef.name, level = mdef.level }
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

--- 获取有掉落物的普通怪物候选列表
---@param minLv number
---@param maxLv number
---@return table[] list  { defId, name, level, dropItemId, dropItemName }
local function getMonstersWithDrops(minLv, maxLv)
    local list = {}
    for defId, mdef in pairs(MonsterDB) do
        if mdef.rarity ~= "rare" and mdef.rarity ~= "fine" and mdef.rarity ~= "superior"
           and mdef.level >= minLv and mdef.level <= maxLv
           and not mdef.isTrainingDummy
           and not QUEST_BLACKLIST[defId]
           and mdef.drops then
            for _, drop in ipairs(mdef.drops) do
                if drop.id and drop.id ~= "@gold" then
                    local tpl = GS.itemTemplates and GS.itemTemplates[drop.id]
                    local dropName = tpl and tpl.name or drop.id
                    list[#list + 1] = {
                        defId = defId,
                        name = mdef.name,
                        level = mdef.level,
                        dropItemId = drop.id,
                        dropItemName = dropName,
                    }
                    break  -- 一个怪物只取第一个非金币掉落
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

--- 获取采集物候选列表
---@param skill string "gathering" | "mining"
---@param minHLv number
---@param maxHLv number
---@return table[] list  { id, name, itemId, hiddenLevel }
local function getGatherCandidates(skill, minHLv, maxHLv)
    local list = {}
    for _, gdef in pairs(GS.GATHER_DEFS) do
        if gdef.lifeSkill == skill
           and gdef.hiddenLevel >= minHLv
           and gdef.hiddenLevel <= maxHLv then
            local useItemId = gdef.itemId
            local useName   = gdef.name
            -- 没有 itemId 但有 drops 的采集物（晶矿类），取权重最高的掉落物
            if not useItemId and gdef.drops and #gdef.drops > 0 then
                local bestDrop = gdef.drops[1]
                for i = 2, #gdef.drops do
                    if gdef.drops[i].weight > bestDrop.weight then
                        bestDrop = gdef.drops[i]
                    end
                end
                useItemId = bestDrop.itemId
                -- 用掉落物的名称作为任务显示名
                local tpl = GS.itemTemplates and GS.itemTemplates[useItemId]
                if tpl and tpl.name then
                    useName = tpl.name
                end
            end
            if useItemId then
                list[#list + 1] = {
                    id = gdef.id,
                    name = useName,
                    itemId = useItemId,
                    image = gdef.image,
                    hiddenLevel = gdef.hiddenLevel,
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.hiddenLevel < b.hiddenLevel end)
    return list
end

-- ======================== 委托生成 ========================

--- 获取当前日期字符串（可信版本，admin_time 封顶防作弊）
---@return string 格式 "YYYY-MM-DD"
function M.getTodayStr()
    local SignInSystem = require("SignInSystem")
    SignInSystem._loadAdminTime()  -- 懒加载，确保管理员时间可用
    local localTime = os.time()
    if SignInSystem._adminTime and localTime > SignInSystem._adminTime then
        localTime = SignInSystem._adminTime
    end
    return os.date("%Y-%m-%d", localTime)
end

--- 生成 5 个每日委托
---@param playerLevel number 玩家等级
---@param gatheringHLv number 采集隐藏等级
---@param miningHLv number 采矿隐藏等级
---@param dateStr string 日期字符串
---@return table[] quests
function M.generateQuests(playerLevel, gatheringHLv, miningHLv, dateStr)
    local quests = {}

    -- 稀有怪物等级范围：玩家等级 -12 ~ +3
    local rareMinLv = math.max(1, playerLevel - 12)
    local rareMaxLv = math.min(playerLevel + 3, 110)
    -- 普通怪物/掉落物等级范围：玩家等级 -15 ~ +0
    local monMinLv = math.max(1, playerLevel - 15)
    local monMaxLv = playerLevel

    -- 采集隐藏等级范围：0 ~ 当前技能隐藏等级（全部已解锁采集物）
    local gatherMinHLv = 0
    local gatherMaxHLv = gatheringHLv
    local mineMinHLv   = 0
    local mineMaxHLv   = miningHLv

    -- 构建候选池
    local rarePool   = getRareMonsters(rareMinLv, rareMaxLv)
    local normalPool = getNormalMonsters(monMinLv, monMaxLv)
    local dropPool   = getMonstersWithDrops(monMinLv, monMaxLv)
    local plantPool  = getGatherCandidates("gathering", gatherMinHLv, gatherMaxHLv)
    local minePool   = getGatherCandidates("mining", mineMinHLv, mineMaxHLv)

    -- 若某个池为空，逐步放宽范围（不超过玩家等级+15，避免低级玩家刷出高级怪物）
    local fallbackMaxLv = math.min(playerLevel + 15, 110)
    if #rarePool == 0 then rarePool = getRareMonsters(1, fallbackMaxLv) end
    if #normalPool == 0 then normalPool = getNormalMonsters(1, fallbackMaxLv) end
    if #dropPool == 0 then dropPool = getMonstersWithDrops(1, fallbackMaxLv) end
    if #plantPool == 0 then plantPool = getGatherCandidates("gathering", 0, 999) end
    if #minePool == 0 then minePool = getGatherCandidates("mining", 0, 999) end

    -- 种子基于日期 + 角色槽位 + 玩家等级（每个角色独立委托）
    local charSlot = GS.charSlotIndex or 1
    local baseSeed = djb2(dateStr .. "|slot" .. tostring(charSlot)
                          .. "|" .. tostring(playerLevel)
                          .. "|g" .. tostring(gatheringHLv)
                          .. "|m" .. tostring(miningHLv))

    -- 1. 稀有怪物击杀 x1
    local seed = baseSeed
    local rareTarget, s1 = pickFromList(rarePool, seed)
    seed = s1
    if rareTarget then
        local expR, goldR, s1r = getQuestReward(playerLevel, seed)
        seed = s1r
        quests[1] = {
            type = M.QUEST_TYPES.RARE_KILL,
            targetId = rareTarget.defId,
            targetName = rareTarget.name,
            targetLevel = rareTarget.level,
            required = QUEST_AMOUNTS[1],
            progress = 0,
            completed = false,
            accepted = false,
            rewarded = false,
            reward = goldR,
            expReward = expR,
        }
    end

    -- 2. 普通怪物击杀 x30
    local normalTarget, s2 = pickFromList(normalPool, seed)
    seed = s2
    if normalTarget then
        local expR, goldR, s2r = getQuestReward(playerLevel, seed)
        seed = s2r
        quests[2] = {
            type = M.QUEST_TYPES.NORMAL_KILL,
            targetId = normalTarget.defId,
            targetName = normalTarget.name,
            targetLevel = normalTarget.level,
            required = QUEST_AMOUNTS[2],
            progress = 0,
            completed = false,
            accepted = false,
            rewarded = false,
            reward = goldR,
            expReward = expR,
        }
    end

    -- 3. 怪物掉落物提交 x15
    local dropTarget, s3 = pickFromList(dropPool, seed)
    seed = s3
    if dropTarget then
        local expR, goldR, s3r = getQuestReward(playerLevel, seed)
        seed = s3r
        quests[3] = {
            type = M.QUEST_TYPES.DROP_SUBMIT,
            targetId = dropTarget.dropItemId,
            targetName = dropTarget.dropItemName,
            monsterName = dropTarget.name,
            monsterDefId = dropTarget.defId,
            targetLevel = dropTarget.level,
            required = QUEST_AMOUNTS[3],
            progress = 0,
            completed = false,
            accepted = false,
            rewarded = false,
            reward = goldR,
            expReward = expR,
        }
    end

    -- 4. 植物采集物提交 x3
    local plantTarget, s4 = pickFromList(plantPool, seed)
    seed = s4
    if plantTarget then
        local expR, goldR, s4r = getQuestReward(playerLevel, seed)
        seed = s4r
        quests[4] = {
            type = M.QUEST_TYPES.PLANT_GATHER,
            targetId = plantTarget.itemId,
            targetName = plantTarget.name,
            targetLevel = plantTarget.hiddenLevel,
            gatherImage = plantTarget.image,
            required = QUEST_AMOUNTS[4],
            progress = 0,
            completed = false,
            accepted = false,
            rewarded = false,
            reward = goldR,
            expReward = expR,
        }
    end

    -- 5. 矿石采集物提交 x3
    local mineTarget, s5 = pickFromList(minePool, seed)
    seed = s5
    if mineTarget then
        local expR, goldR, s5r = getQuestReward(playerLevel, seed)
        seed = s5r
        quests[5] = {
            type = M.QUEST_TYPES.MINE_GATHER,
            targetId = mineTarget.itemId,
            targetName = mineTarget.name,
            targetLevel = mineTarget.hiddenLevel,
            gatherImage = mineTarget.image,
            required = QUEST_AMOUNTS[5],
            progress = 0,
            completed = false,
            accepted = false,
            rewarded = false,
            reward = goldR,
            expReward = expR,
        }
    end

    return quests
end

-- ======================== 重新随机委托（看广告后） ========================

--- 根据委托类型获取对应候选池
---@param questType number
---@return table pool
local function getPoolForType(questType)
    if not GS then GS = require("GameState") end
    local playerLevel = GS.player and GS.player.level or 1
    local gatheringHLv = GS.getLifeSkillHiddenLevel("gathering")
    local miningHLv    = GS.getLifeSkillHiddenLevel("mining")

    local rareMinLv = math.max(1, playerLevel - 12)
    local rareMaxLv = math.min(playerLevel + 3, 110)
    local monMinLv = math.max(1, playerLevel - 15)
    local monMaxLv = playerLevel
    local gatherMinHLv = 0
    local gatherMaxHLv = gatheringHLv
    local mineMinHLv   = 0
    local mineMaxHLv   = miningHLv
    local fallbackMaxLv = math.min(playerLevel + 15, 110)

    if questType == M.QUEST_TYPES.RARE_KILL then
        local pool = getRareMonsters(rareMinLv, rareMaxLv)
        if #pool == 0 then pool = getRareMonsters(1, fallbackMaxLv) end
        return pool
    elseif questType == M.QUEST_TYPES.NORMAL_KILL then
        local pool = getNormalMonsters(monMinLv, monMaxLv)
        if #pool == 0 then pool = getNormalMonsters(1, fallbackMaxLv) end
        return pool
    elseif questType == M.QUEST_TYPES.DROP_SUBMIT then
        local pool = getMonstersWithDrops(monMinLv, monMaxLv)
        if #pool == 0 then pool = getMonstersWithDrops(1, fallbackMaxLv) end
        return pool
    elseif questType == M.QUEST_TYPES.PLANT_GATHER then
        local pool = getGatherCandidates("gathering", gatherMinHLv, gatherMaxHLv)
        if #pool == 0 then pool = getGatherCandidates("gathering", 0, 999) end
        return pool
    elseif questType == M.QUEST_TYPES.MINE_GATHER then
        local pool = getGatherCandidates("mining", mineMinHLv, mineMaxHLv)
        if #pool == 0 then pool = getGatherCandidates("mining", 0, 999) end
        return pool
    end
    return {}
end

--- 重新随机指定索引的委托（在同类别候选池中重新选取）
---@param questIdx number 1-5
---@return boolean success
function M.rerollQuest(questIdx)
    local q = M.quests and M.quests[questIdx]
    if not q then return false end
    -- 已领奖、目标已达成（待提交）、已提交待领奖 均不允许换
    if q.rewarded or q.ready or q.completed then return false end

    if not GS then GS = require("GameState") end
    local playerLevel = GS.player and GS.player.level or 1

    local pool = getPoolForType(q.type)
    if #pool == 0 then
        print("[布告栏] 换一个失败：候选池为空")
        return false
    end

    -- 排除当前正在显示的目标，确保换出不同的
    local currentId = q.targetId
    local filtered = {}
    for _, item in ipairs(pool) do
        -- 击杀类用 defId，采集/掉落类用 itemId/dropItemId
        local itemId = item.defId or item.dropItemId or item.itemId
        if itemId ~= currentId then
            filtered[#filtered + 1] = item
        end
    end
    -- 如果排除后为空（池里只有1个），保底不排除
    if #filtered > 0 then pool = filtered end

    -- 使用时间戳 + 随机数生成新种子
    local newSeed = djb2(tostring(os.time()) .. "|reroll|" .. tostring(questIdx) .. "|" .. tostring(math.random(1, 99999)))
    local picked, s1 = pickFromList(pool, newSeed)
    if not picked then return false end

    local expR, goldR, _ = getQuestReward(playerLevel, s1)

    -- 根据类别构建新任务数据（保留 type 和结构，替换目标与奖励）
    if q.type == M.QUEST_TYPES.RARE_KILL then
        q.targetId = picked.defId
        q.targetName = picked.name
        q.targetLevel = picked.level
    elseif q.type == M.QUEST_TYPES.NORMAL_KILL then
        q.targetId = picked.defId
        q.targetName = picked.name
        q.targetLevel = picked.level
    elseif q.type == M.QUEST_TYPES.DROP_SUBMIT then
        q.targetId = picked.dropItemId
        q.targetName = picked.dropItemName
        q.monsterName = picked.name
        q.monsterDefId = picked.defId
        q.targetLevel = picked.level
    elseif q.type == M.QUEST_TYPES.PLANT_GATHER then
        q.targetId = picked.itemId
        q.targetName = picked.name
        q.targetLevel = picked.hiddenLevel
        q.gatherImage = picked.image
    elseif q.type == M.QUEST_TYPES.MINE_GATHER then
        q.targetId = picked.itemId
        q.targetName = picked.name
        q.targetLevel = picked.hiddenLevel
        q.gatherImage = picked.image
    end

    q.reward = goldR
    q.expReward = expR
    q.progress = 0
    q.completed = false

    print("[布告栏] 换一个成功: " .. M.getQuestDesc(q))
    return true
end

-- ======================== 接取委托 ========================

--- 接取委托（玩家点击"接取委托"按钮后调用）
---@param questIdx number 1-5
---@return boolean success
---@return string message
function M.acceptQuest(questIdx)
    local q = M.quests and M.quests[questIdx]
    if not q then return false, "委托不存在" end
    if q.accepted then return false, "已接取该委托" end
    q.accepted = true
    print("[布告栏] 接取委托: " .. M.getQuestDesc(q))
    return true, "接取成功: " .. M.getQuestTypeLabel(q)
end

--- 获取已接取的委托列表（用于日志面板显示）
---@return table[] acceptedQuests  { idx, quest }
function M.getAcceptedQuests()
    local result = {}
    if not M.quests then return result end
    for i = 1, M.QUEST_COUNT do
        local q = M.quests[i]
        if q and q.accepted and not q.rewarded then
            result[#result + 1] = { idx = i, quest = q }
        end
    end
    return result
end

-- ======================== 进度跟踪 ========================

--- 怪物被击杀时调用（由 GameState_Shop.onMonsterKill 转发）
---@param defId string
function M.onMonsterKill(defId)
    if not M.quests or not defId then return end

    -- 稀有怪物击杀任务（只有已接取的才计进度）
    local q1 = M.quests[1]
    if q1 and q1.accepted and not q1.completed and not q1.ready and q1.type == M.QUEST_TYPES.RARE_KILL
       and q1.targetId == defId then
        q1.progress = q1.progress + 1
        if q1.progress >= q1.required then
            q1.ready = true
            print("[布告栏] 委托目标达成，待提交: 击杀 " .. q1.targetName)
        end
    end

    -- 普通怪物击杀任务（只有已接取的才计进度）
    local q2 = M.quests[2]
    if q2 and q2.accepted and not q2.completed and not q2.ready and q2.type == M.QUEST_TYPES.NORMAL_KILL
       and q2.targetId == defId then
        q2.progress = q2.progress + 1
        if q2.progress >= q2.required then
            q2.ready = true
            print("[布告栏] 委托目标达成，待提交: 击杀 " .. q2.targetName .. " x" .. q2.required)
        end
    end
end

--- 检查提交类委托的当前持有数量（用于 UI 显示）
---@param quest table
---@return number held
function M.getHeldCount(quest)
    if not quest or not quest.targetId then return 0 end
    if quest.type == M.QUEST_TYPES.DROP_SUBMIT
       or quest.type == M.QUEST_TYPES.PLANT_GATHER
       or quest.type == M.QUEST_TYPES.MINE_GATHER then
        return GS.countInventoryItem(quest.targetId)
    end
    return 0
end

--- 尝试提交物品（扣除背包物品，增加 progress）
---@param questIdx number 1-5
---@return boolean success
---@return string message
function M.trySubmit(questIdx)
    local q = M.quests and M.quests[questIdx]
    if not q then return false, "委托不存在" end
    if not q.accepted then return false, "尚未接取该委托" end
    if q.completed then return false, "委托已完成" end
    if q.rewarded then return false, "已领取奖励" end

    -- 仅提交类委托支持提交物品
    if q.type ~= M.QUEST_TYPES.DROP_SUBMIT
       and q.type ~= M.QUEST_TYPES.PLANT_GATHER
       and q.type ~= M.QUEST_TYPES.MINE_GATHER then
        return false, "该委托无需提交物品"
    end

    local still = q.required - q.progress
    if still <= 0 then
        q.ready = true
        return false, "物品已提交完毕，待确认提交"
    end

    local held = GS.countInventoryItem(q.targetId)
    if held <= 0 then return false, "背包中没有 " .. q.targetName end

    local submitCount = math.min(held, still)
    local ok = GS.removeInventoryItem(q.targetId, submitCount)
    if not ok then return false, "扣除物品失败" end

    q.progress = q.progress + submitCount
    if q.progress >= q.required then
        q.ready = true
        print("[布告栏] 委托物品已提交完毕，待确认: " .. q.targetName .. " x" .. q.required)
    end

    return true, "提交了 " .. q.targetName .. " x" .. submitCount
end

--- 确认提交委托（ready → completed）
---@param questIdx number 1-5
---@return boolean success
---@return string message
function M.submitComplete(questIdx)
    local q = M.quests and M.quests[questIdx]
    if not q then return false, "委托不存在" end
    if not q.accepted then return false, "尚未接取该委托" end
    if q.completed then return false, "委托已完成" end
    if not q.ready then return false, "委托目标尚未达成" end

    q.completed = true
    -- 每日公告板委托完成计数+1
    GS.dailyBulletinDoneCount = (GS.dailyBulletinDoneCount or 0) + 1
    print("[布告栏] 委托已提交完成: " .. M.getQuestTypeLabel(q) .. " (今日完成: " .. GS.dailyBulletinDoneCount .. "/5)")

    -- 提交后自动领取奖励（合并为一步操作）
    local claimOk, claimMsg = M.claimReward(questIdx)
    if claimOk then
        return true, claimMsg
    end
    return true, "委托提交成功"
end

--- 领取奖励
---@param questIdx number 1-5
---@return boolean success
---@return string message
function M.claimReward(questIdx)
    local q = M.quests and M.quests[questIdx]
    if not q then return false, "委托不存在" end
    if not q.accepted then return false, "尚未接取该委托" end
    if not q.completed then return false, "委托尚未完成" end
    if q.rewarded then return false, "奖励已领取" end

    q.rewarded = true

    -- 委托奖励加成（妮可"魔物清剿"任务，每完成一个 +7%）
    local QuestManager = require("QuestManager")
    local bonusCount = QuestManager.getNicoleExterminateCompleted()
    local bonusPct = bonusCount * 7  -- 0% ~ 42%
    local baseGold = q.reward
    local bonusGold = math.floor(baseGold * bonusPct / 100 + 0.5)
    local totalGold = baseGold + bonusGold
    GS.gold = GS.gold + totalGold

    -- 经验奖励
    local expReward = q.expReward or 0
    if expReward > 0 and GS.player and GS.player.exp then
        GS.player.exp = GS.player.exp + expReward
        if GS.player.level >= 100 then
            GS.player.exp = math.min(GS.player.exp, 99999999)
        end
    end

    if bonusGold > 0 then
        print("[布告栏] 领取奖励: " .. baseGold .. "+" .. bonusGold .. "(加成" .. bonusPct .. "%)=" .. totalGold .. "G + " .. expReward .. "EXP")
        return true, "获得 " .. totalGold .. " 金币(含" .. bonusPct .. "%加成) 和 " .. expReward .. " 经验"
    else
        print("[布告栏] 领取奖励: " .. totalGold .. "G + " .. expReward .. "EXP")
        return true, "获得 " .. totalGold .. " 金币 和 " .. expReward .. " 经验"
    end
end

-- ======================== 日期检查与刷新 ========================

--- 检查是否需要刷新（新的一天 或 角色切换）
--- 防回退：只有日期往后推进才触发刷新（玩家回调时间不会重刷委托）
---@return boolean
function M.needsRefresh()
    local today = M.getTodayStr()
    -- 首次（无记录）或日期往后推进时刷新
    if not M.lastRefreshDate or today > M.lastRefreshDate then return true end
    -- 角色槽位变化时也需要刷新（_lastCharSlot 为 nil 时也视为需要刷新）
    local curSlot = GS and GS.charSlotIndex or 1
    if M._lastCharSlot ~= curSlot then return true end
    return false
end

--- 执行刷新
function M.refresh()
    if not GS or not GS.player then return end

    local today = M.getTodayStr()
    local playerLevel = GS.player.level or 1
    local gatheringHLv = GS.getLifeSkillHiddenLevel("gathering")
    local miningHLv    = GS.getLifeSkillHiddenLevel("mining")

    M.quests = M.generateQuests(playerLevel, gatheringHLv, miningHLv, today)
    M.lastRefreshDate = today
    M._lastCharSlot = GS.charSlotIndex or 1

    -- 每日任务重置（"为了大家！"等）
    local QuestManager = require("QuestManager")
    QuestManager.resetDailyQuests()

    print("[布告栏] 委托已刷新 (日期: " .. today .. ", 槽位: " .. M._lastCharSlot .. ", 玩家Lv: " .. playerLevel .. ")")
end

--- 确保委托数据已初始化（进入游戏时调用）
function M.ensureReady()
    local curSlot = GS and GS.charSlotIndex or 1
    if M.needsRefresh() then
        -- 如果只是 _lastCharSlot 未设置（刚从存档恢复），且同一天且已有委托数据，
        -- 则只更新槽位追踪，不重新生成（保留存档中的进度）
        local today = M.getTodayStr()
        if M.lastRefreshDate == today and M.quests and M._lastCharSlot == nil then
            M._lastCharSlot = curSlot
        else
            M.refresh()
        end
    end
end

-- ======================== 序列化 ========================

--- 收集存档数据
---@return table
function M.collectSaveData()
    local data = {
        lastRefreshDate = M.lastRefreshDate,
    }
    if M.quests then
        data.quests = {}
        for i = 1, M.QUEST_COUNT do
            local q = M.quests[i]
            if q then
                data.quests[i] = {
                    type = q.type,
                    targetId = q.targetId,
                    targetName = q.targetName,
                    monsterName = q.monsterName,
                    targetLevel = q.targetLevel,
                    required = q.required,
                    progress = q.progress,
                    completed = q.completed,
                    accepted = q.accepted,
                    rewarded = q.rewarded,
                    ready = q.ready,
                    reward = q.reward,
                    expReward = q.expReward,
                }
            end
        end
    end
    return data
end

--- 重置所有运行时状态（切换角色/新角色时防止数据泄漏）
function M.reset()
    M.quests = nil
    M.lastRefreshDate = nil
    M._lastCharSlot = nil
end

--- 应用存档数据
---@param data table|nil
function M.applySaveData(data)
    -- 先重置全部状态，防止跨角色数据泄漏
    M.reset()
    if not data then return end
    M.lastRefreshDate = data.lastRefreshDate
    if data.quests then
        M.quests = {}
        for i = 1, M.QUEST_COUNT do
            local qd = data.quests[i]
            if qd then
                local prog = qd.progress or 0
                local req = qd.required or 1
                -- 兼容旧存档：ready 未持久化时，根据 progress >= required 重算
                -- 所有类型的委托都适用（击杀类/提交类），因为提交类的物品已从背包扣除
                local isReady = qd.ready
                if isReady == nil and prog >= req and qd.accepted and not qd.completed and not qd.rewarded then
                    isReady = true
                end
                M.quests[i] = {
                    type = qd.type,
                    targetId = qd.targetId,
                    targetName = qd.targetName,
                    monsterName = qd.monsterName,
                    targetLevel = qd.targetLevel,
                    required = req,
                    progress = prog,
                    completed = qd.completed or false,
                    accepted = qd.accepted or false,
                    rewarded = qd.rewarded or false,
                    ready = isReady or false,
                    reward = qd.reward or 0,
                    expReward = qd.expReward or 0,
                }
            end
        end
    end
end

-- ======================== 初始化 ========================

function M.init(gameState)
    GS = gameState
    M.quests = nil
    M.lastRefreshDate = nil
end

-- ======================== UI 辅助 ========================

--- 获取委托类型文字描述（带具体目标名）
---@param questOrType table|number  quest对象或questType数字
---@return string
function M.getQuestTypeLabel(questOrType)
    -- 兼容旧调用：传数字时返回前缀
    if type(questOrType) == "number" then
        local prefixes = { [1] = "讨伐", [2] = "讨伐", [3] = "收集", [4] = "采集", [5] = "采集" }
        return prefixes[questOrType] or "未知"
    end
    local q = questOrType
    local name = q.targetName or "未知"
    if q.type == M.QUEST_TYPES.RARE_KILL then
        return "讨伐·" .. name
    elseif q.type == M.QUEST_TYPES.NORMAL_KILL then
        return "讨伐·" .. name
    elseif q.type == M.QUEST_TYPES.DROP_SUBMIT then
        return "收集·" .. name
    elseif q.type == M.QUEST_TYPES.PLANT_GATHER then
        return "采集·" .. name
    elseif q.type == M.QUEST_TYPES.MINE_GATHER then
        return "采集·" .. name
    end
    return "未知"
end

--- 获取委托描述文字
---@param quest table
---@return string
function M.getQuestDesc(quest)
    if not quest then return "" end
    if quest.type == M.QUEST_TYPES.RARE_KILL then
        return "击杀 " .. quest.targetName .. " (Lv." .. quest.targetLevel .. ")"
    elseif quest.type == M.QUEST_TYPES.NORMAL_KILL then
        return "击杀 " .. quest.targetName .. " (Lv." .. quest.targetLevel .. ") x" .. quest.required
    elseif quest.type == M.QUEST_TYPES.DROP_SUBMIT then
        return "提交 " .. quest.targetName .. " x" .. quest.required
               .. " (" .. (quest.monsterName or "怪物") .. "掉落)"
    elseif quest.type == M.QUEST_TYPES.PLANT_GATHER then
        return "提交 " .. quest.targetName .. " x" .. quest.required
    elseif quest.type == M.QUEST_TYPES.MINE_GATHER then
        return "提交 " .. quest.targetName .. " x" .. quest.required
    end
    return "未知委托"
end

--- 获取进度文字
---@param quest table
---@return string
function M.getProgressText(quest)
    if not quest then return "" end
    if quest.rewarded then return "已完成" end
    if quest.completed then return "待领取" end
    return quest.progress .. "/" .. quest.required
end

--- 获取状态颜色 RGBA
---@param quest table
---@return number, number, number, number
function M.getStatusColor(quest)
    if not quest then return 128, 128, 128, 255 end
    if quest.rewarded then return 100, 100, 100, 180 end  -- 灰色
    if quest.completed then return 50, 180, 50, 255 end   -- 绿色
    return 220, 180, 80, 255                               -- 金色（进行中）
end

-- ======================== 区域提示映射 ========================

--- 怪物 defId → 所在区域名称
local MONSTER_AREA_MAP = {
    -- 慈爱平原
    slime = "慈爱平原", item_slime = "慈爱平原",
    -- fire_slime/ice_slime/elec_slime 已排除（仅采集区出现，在 QUEST_BLACKLIST 中）
    goblin = "慈爱平原", goblin_club = "慈爱平原",
    goblin_shield = "慈爱平原", goblin_archer = "慈爱平原",
    chest_goblin = "慈爱平原",
    demon_slime = "慈爱平原", strange_demon_slime = "慈爱平原",
    skeleton = "慈爱平原", skeleton_sword = "慈爱平原", skeleton_archer = "慈爱平原",
    skeleton_king = "慈爱平原",
    mummy = "慈爱平原", mummy_pharaoh = "慈爱平原",
    -- 垂雾森林
    bat = "垂雾森林", rare_bat = "垂雾森林",
    wolf = "垂雾森林", wolf_king = "垂雾森林",
    boar = "垂雾森林", boar_king = "垂雾森林",
    fierce_wolf = "垂雾森林", young_werewolf = "垂雾森林",
    tree_root = "垂雾森林", giant_tree_root = "垂雾森林",
    golden_tree_root = "垂雾森林", golden_giant_tree = "垂雾森林",
    bear = "垂雾森林", black_bear_king = "垂雾森林",
    tree_fairy = "垂雾森林", flower_fairy = "垂雾森林",
    -- 巴洛庄园
    vampire_youth = "巴洛庄园",
    vampire_boy = "巴洛庄园", vampire_girl = "巴洛庄园",
    vampire_male = "巴洛庄园", vampire_female = "巴洛庄园",
    ghost = "巴洛庄园", grey_ghost = "巴洛庄园",
    furniture_big = "巴洛庄园", furniture_small = "巴洛庄园",
    candle_monster = "巴洛庄园", sofa_monster = "巴洛庄园", book_monster = "巴洛庄园",
    piano_monster = "巴洛庄园",
    doll_melee = "巴洛庄园", doll_range = "巴洛庄园",
    butler_doll = "巴洛庄园", maid_doll = "巴洛庄园",
    knight_doll = "巴洛庄园",
    baron_baro = "巴洛庄园",
    -- 升月堡
    star_demon_round = "升月堡", star_demon_fat = "升月堡",
    star_demon_elite = "升月堡", star_demon_fat_elite = "升月堡",
    cosmos_demon_melee = "升月堡", cosmos_demon_range = "升月堡",
    cosmos_demon_a = "升月堡", cosmos_demon_elite = "升月堡",
    chimera = "升月堡", fake_chimera = "升月堡",
    -- 灰海
    rock_turtle = "灰海", turtle_shark = "灰海", copper_turtle = "灰海",
    sea_demon_a = "灰海", sea_demon_b = "灰海",
    fishman = "灰海", fishman_warrior = "灰海",
    five_eye_starfish = "灰海", octopus_demon = "灰海",
    nameless_horror = "灰海",
    -- 灰山
    centaur_hunter = "灰山", centaur_warrior = "灰山", centaur_priest = "灰山",
    -- 副本怪物已排除（在 QUEST_BLACKLIST 中，不会出现在委托里）
}

--- 获取委托的区域提示文本
---@param quest table
---@return string
function M.getLocationHint(quest)
    if not quest then return "" end
    local qtype = quest.type
    if qtype == M.QUEST_TYPES.RARE_KILL or qtype == M.QUEST_TYPES.NORMAL_KILL then
        local area = MONSTER_AREA_MAP[quest.targetId]
        if area then
            return "据说出没在" .. area
        end
        return "据说出没在未知区域"
    elseif qtype == M.QUEST_TYPES.DROP_SUBMIT then
        -- 掉落物委托：显示掉落来源怪物
        return "据说" .. (quest.monsterName or "怪物") .. "会掉落"
    elseif qtype == M.QUEST_TYPES.PLANT_GATHER then
        return "可在各区域植物繁茂区采集"
    elseif qtype == M.QUEST_TYPES.MINE_GATHER then
        return "可在各区域矿洞采集"
    end
    return ""
end

--- 获取委托图标信息（用于卡片渲染）
---@param quest table
---@return string|nil iconCategory  "monster" 或 "item"
---@return string|nil iconPath      图像路径
function M.getQuestIconInfo(quest)
    if not quest then return nil, nil end
    local qtype = quest.type
    if qtype == M.QUEST_TYPES.RARE_KILL or qtype == M.QUEST_TYPES.NORMAL_KILL then
        -- 击杀类：显示怪物图标
        local mdef = MonsterDB[quest.targetId]
        if mdef and mdef.image then
            return "monster", mdef.image
        end
    elseif qtype == M.QUEST_TYPES.DROP_SUBMIT then
        -- 掉落物提交类：显示物品图标
        if not GS then GS = require("GameState") end
        local tpl = GS.itemTemplates and GS.itemTemplates[quest.targetId]
        if tpl and tpl.icon then
            return "item", tpl.icon
        end
    elseif qtype == M.QUEST_TYPES.PLANT_GATHER or qtype == M.QUEST_TYPES.MINE_GATHER then
        -- 采集类：显示物品图标
        if not GS then GS = require("GameState") end
        local tpl = GS.itemTemplates and GS.itemTemplates[quest.targetId]
        if tpl and tpl.icon then
            return "item", tpl.icon
        end
    end
    return nil, nil
end

return M
