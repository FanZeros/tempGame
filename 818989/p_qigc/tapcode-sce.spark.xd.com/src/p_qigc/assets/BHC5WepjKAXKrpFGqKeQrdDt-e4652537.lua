-- ============================================================
-- GameState_Save.lua  —— 存档/云存储/角色槽位管理
-- 由 GameState.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================

local sub = {}
local SSLog = require("SharedStorageLog")

function sub.init(M)

--- 生成 key-only 指纹：将表的所有 key 排序后拼接为字符串
function M._buildKeyFingerprint(tbl)
    if not tbl then return "" end
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return table.concat(keys, ",")
end

--- 生成 key=value 指纹：将表的 key 排序后拼接 key=value 字符串
function M._buildKVFingerprint(tbl)
    if not tbl then return "" end
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(tbl[k]) end
    return table.concat(parts, ",")
end

function M.collectSaveData()
    -- 序列化物品栏（支持堆叠数量、附魔、锁定）
    local invData = {}
    for i = 1, M.bagSlots do
        local inv = M.inventory[i]
        if inv then
            if inv.stackable and inv.quantity then
                local d = { id = inv.templateId, qty = inv.quantity }
                if inv.locked then d.locked = true end
                if inv.starred then d.starred = true end
                invData[tostring(i)] = d
            elseif inv.enchantment or (inv.enhanceLevel and inv.enhanceLevel > 0) or inv.locked or inv.starred or inv.refineSlots or inv.gemSlots or inv.tier or inv.brittle or inv.refineToughness or inv.hasRandom or inv.abyssAffix or inv.gemEffect then
                local d = { id = inv.templateId }
                if inv.enhanceLevel and inv.enhanceLevel > 0 then d.enhLv = inv.enhanceLevel end
                if inv.enchantment then d.ench = inv.enchantment end
                if inv.locked then d.locked = true end
                if inv.starred then d.starred = true end
                if inv.refineSlots then d.refineSlots = inv.refineSlots end
                if inv.gemSlots then d.gemSlots = inv.gemSlots end
                if inv.tier then d.tier = inv.tier end
                if inv.brittle then d.brittle = true end
                if inv.refineToughness then d.refineToughness = inv.refineToughness end
                if inv.hasRandom then
                    local tpl = M.itemTemplates[inv.templateId]
                    if tpl and tpl.abyssRandomStats then
                        -- 深渊装备：只存档位索引，加载时从模板重建数值
                        d.abyssStatTiers = inv.abyssStatTiers
                        d.allstatLines = inv.allstatLines
                        d.randomResistLines = inv.randomResistLines
                        d.randomMainBaseLines = inv.randomMainBaseLines
                        d.randomMainExtraLines = inv.randomMainExtraLines
                        d.abyssAffixLimitTarget = inv.abyssAffixLimitTarget
                        d.templateVersion       = inv.templateVersion
                    else
                        -- 旧式随机装备（如法老之环）：存完整值
                        d.effects = inv.effects
                        d.extraEffects = inv.extraEffects
                        d.desc = inv.desc
                    end
                end
                if inv.abyssAffix then d.abyssAffix = inv.abyssAffix end
                if inv.gemEffect then d.gemEffect = inv.gemEffect end
                invData[tostring(i)] = d
            else
                invData[tostring(i)] = inv.templateId
            end
        end
    end
    -- 序列化装备（保存强化等级、附魔、锁定）
    local equipData = {}
    for slotId, item in pairs(M.equipment) do
        if item.enchantment or (item.enhanceLevel and item.enhanceLevel > 0) or item.locked or item.starred or item.refineSlots or item.gemSlots or item.tier or item.brittle or item.refineToughness or item.hasRandom or item.abyssAffix then
            local d = { id = item.templateId }
            if item.enhanceLevel and item.enhanceLevel > 0 then d.enhLv = item.enhanceLevel end
            if item.enchantment then d.ench = item.enchantment end
            if item.locked then d.locked = true end
            if item.starred then d.starred = true end
            if item.refineSlots then d.refineSlots = item.refineSlots end
            if item.gemSlots then d.gemSlots = item.gemSlots end
            if item.tier then d.tier = item.tier end
            if item.brittle then d.brittle = true end
            if item.refineToughness then d.refineToughness = item.refineToughness end
            if item.hasRandom then
                local tpl = M.itemTemplates[item.templateId]
                if tpl and tpl.abyssRandomStats then
                    -- 深渊装备：只存档位索引，加载时从模板重建数值
                    d.abyssStatTiers = item.abyssStatTiers
                    d.allstatLines = item.allstatLines
                    d.randomResistLines = item.randomResistLines
                    d.randomMainBaseLines = item.randomMainBaseLines
                    d.randomMainExtraLines = item.randomMainExtraLines
                    d.abyssAffixLimitTarget = item.abyssAffixLimitTarget
                    d.templateVersion       = item.templateVersion
                else
                    -- 旧式随机装备（如法老之环）：存完整值
                    d.effects = item.effects
                    d.extraEffects = item.extraEffects
                    d.desc = item.desc
                end
            end
            if item.abyssAffix then d.abyssAffix = item.abyssAffix end
            equipData[slotId] = d
        else
            equipData[slotId] = item.templateId
        end
    end
    local p = M.player
    -- 序列化商店库存（只保存每个商品的当前 stock）
    local shopStockData = {}
    for shopKey, items in pairs(M.SHOP_INVENTORY) do
        shopStockData[shopKey] = {}
        for i, entry in ipairs(items) do
            shopStockData[shopKey][tostring(i)] = {
                templateId = entry.templateId,
                stock = entry.stock,
            }
        end
    end
    return {
        version = 1,
        name = M.charName or "",
        currentClass = M.currentClass,
        confirmedClass = M.confirmedClass,
        currentStage = M.currentStage,
        turnNumber = M.turnNumber,
        gold = M.gold,
        score = M.score,
        player = {
            x = p.x, y = p.y,
            facing = p.facing or "down",
            level = p.level, exp = p.exp,
            stats = p.stats,
            statPoints = p.statPoints,
            hp = p.hp, mp = p.mp,
        },
        inventory = invData,
        equipment = equipData,
        skillPoints = M.skillPoints,
        skillLevels = M.skillLevels,
        activeSkills = M.activeSkills,
        autoConsumables = M.autoConsumables,
        autoConsumableThresholds = M.autoConsumableThresholds,
        autoFood = M.autoFood,
        autoBuffPotion = M.autoBuffPotion,
        autoChargeMode = M.autoChargeMode,
        adventurerRank = M.adventurerRank,
        monsterKillCounts = M.monsterKillCounts,
        stageKillCounts = M.stageKillCounts,
        maxStageReached = M.maxStageReached,
        stageClearedOnce = M.stageClearedOnce,
        knownNPCs = M.knownNPCs,
        talkQAAsked = M.talkQAAsked,
        npcTalkedRecord = M.npcTalkedRecord,
        dungeonsCleared = M.dungeonsCleared,
        dungeonClearCounts = M.dungeonClearCounts,
        areaKillCounts = M.areaKillCounts,
        eliyaTravelDone = M.eliyaTravelDone,
        angelicaTravelDone = M.angelicaTravelDone,
        difenTravelDone = M.difenTravelDone,
        forgetMeNotLevel = M.forgetMeNotLevel,
        forgetMeNotPermanent = M.forgetMeNotPermanent or false,
        _angelicaSeaKillSnapshot = M._angelicaSeaKillSnapshot,
        infiniteTowerUnlocked = M.infiniteTowerUnlocked,
        sharedStorageUnlocked = M.sharedStorageUnlocked,
        abyssUnlocked = M.abyssUnlocked,
        abyssPoints = M.abyssPoints or 0,
        lifeSkillExp = M.lifeSkillExp,
        lifeSkillTiers = M.lifeSkillTiers,
        shopStock = shopStockData,
        warehouses = (function()
            local allWh = {}
            for wid = 1, M.WAREHOUSE_COUNT do
                local whData = {}
                local wh = M.warehouses[wid] or {}
                for i = 1, M.warehouseSlots do
                    local inv = wh[i]
                    if inv then
                        if inv.stackable and inv.quantity then
                            local d = { id = inv.templateId, qty = inv.quantity }
                            if inv.locked then d.locked = true end
                            if inv.starred then d.starred = true end
                            whData[tostring(i)] = d
                        elseif inv.enchantment or (inv.enhanceLevel and inv.enhanceLevel > 0) or inv.locked or inv.starred or inv.refineSlots or inv.gemSlots or inv.tier or inv.brittle or inv.refineToughness or inv.hasRandom or inv.abyssAffix or inv.gemEffect then
                            local d = { id = inv.templateId }
                            if inv.enhanceLevel and inv.enhanceLevel > 0 then d.enhLv = inv.enhanceLevel end
                            if inv.enchantment then d.ench = inv.enchantment end
                            if inv.locked then d.locked = true end
                            if inv.starred then d.starred = true end
                            if inv.refineSlots then d.refineSlots = inv.refineSlots end
                            if inv.gemSlots then d.gemSlots = inv.gemSlots end
                            if inv.tier then d.tier = inv.tier end
                            if inv.brittle then d.brittle = true end
                            if inv.refineToughness then d.refineToughness = inv.refineToughness end
                            if inv.hasRandom then
                                local tpl = M.itemTemplates[inv.templateId]
                                if tpl and tpl.abyssRandomStats then
                                    d.abyssStatTiers = inv.abyssStatTiers
                                    d.allstatLines = inv.allstatLines
                                    d.randomResistLines = inv.randomResistLines
                                    d.randomMainBaseLines = inv.randomMainBaseLines
                                    d.randomMainExtraLines = inv.randomMainExtraLines
                                    d.abyssAffixLimitTarget = inv.abyssAffixLimitTarget
                                    d.templateVersion       = inv.templateVersion
                                else
                                    d.effects = inv.effects
                                    d.extraEffects = inv.extraEffects
                                    d.desc = inv.desc
                                end
                            end
                            if inv.abyssAffix then d.abyssAffix = inv.abyssAffix end
                            if inv.gemEffect then d.gemEffect = inv.gemEffect end
                            whData[tostring(i)] = d
                        else
                            whData[tostring(i)] = inv.templateId
                        end
                    end
                end
                allWh[tostring(wid)] = whData
            end
            return allWh
        end)(),
        dialogueFlags = M.dialogueFlags,
        redeemedCodes = M.redeemedCodes,
        npcAffinity = M.npcAffinity,
        npcTalkAffinityDate = M.npcTalkAffinityDate,
        npcKissAffinityDate = M.npcKissAffinityDate,
        npcConfessAffinityDate = M.npcConfessAffinityDate,
        npcProposalAffinityDate = M.npcProposalAffinityDate,
        homeKissDate = M.homeKissDate,
        homeHugDate = M.homeHugDate,
        homeHugDate2 = M.homeHugDate2,
        awakeningCompleted = M.awakeningCompleted,
        eventCompleted = M.eventCompleted,
        signInStartDay = M.signInStartDay,
        signInRewards = M.signInRewards,
        signInDayPlayTime = M.signInDayPlayTime,
        -- 日常签到数据已迁移至账户级云端（clientCloud），不再存角色存档
        isRaining = M.isRaining,
        isWindy = M.isWindy,
        windDirection = M.windDirection,
        isScorching = M.isScorching,
        weatherTime = M.weatherTime,
        weatherChangeTimer = M.weatherChangeTimer,
        weatherCheckCount = M.weatherCheckCount,
        gatherStageStates = M.gatherStageStates,
        gatherResetCounter = M.gatherResetCounter,
        lastRestockDay = M.lastRestockDay,
        rebirthCooldownDay = M.rebirthCooldownDay,
        veilReforgeTime = M.veilReforgeTime,
        abyssChallengeDay = M.abyssChallengeDay,
        abyssChallengeUsed = M.abyssChallengeUsed,
        abyssWorldDay = M.abyssWorldDay,
        abyssWorldUsed = M.abyssWorldUsed,
        abyssWorldActive = M.abyssWorldActive,
        abyssWorldLives = M.abyssWorldLives,
        slimeRevengeDay = M.slimeRevengeDay,
        slimeRevengeUsed = M.slimeRevengeUsed,
        dihataRevengeDay = M.dihataRevengeDay,
        dihataRevengeUsed = M.dihataRevengeUsed,
        abyssFakeAd = M.abyssFakeAd or nil,
        adFree = M.adFree or nil,
        dailyBulletinDoneCount = M.dailyBulletinDoneCount,
        bulletinQuestTotalDone = M.bulletinQuestTotalDone > 0 and M.bulletinQuestTotalDone or nil,
        housePurchased = M.housePurchased,
        homeType = M.homeType,
        partnerNpcKey = M.partnerNpcKey,
        partnerLivingTogether = M.partnerLivingTogether or nil,
        customPetNames = (M.customPetNames and next(M.customPetNames)) and M.customPetNames or nil,
        elfvahBooksRead = M.elfvahBooksRead,
        elfvahLanguageLearned = M.elfvahLanguageLearned or nil,
        elfvahElfTalked = M.elfvahElfTalked or nil,
        adDailyCount = M.adDailyCount,
        adDailyDate = M.adDailyDate,
        bagSlots = M.bagSlots,
        warehouseSlots = M.warehouseSlots,
        lostItems = (function()
            local liData = {}
            for i = 1, M.LOST_ITEMS_MAX do
                local inv = M.lostItems[i]
                if inv then
                    if inv.stackable and inv.quantity then
                        local d = { id = inv.templateId, qty = inv.quantity }
                        if inv.locked then d.locked = true end
                        if inv.starred then d.starred = true end
                        liData[tostring(i)] = d
                    elseif inv.enchantment or (inv.enhanceLevel and inv.enhanceLevel > 0) or inv.locked or inv.starred or inv.refineSlots or inv.gemSlots or inv.tier or inv.brittle or inv.refineToughness or inv.hasRandom or inv.abyssAffix or inv.gemEffect then
                        local d = { id = inv.templateId }
                        if inv.enhanceLevel and inv.enhanceLevel > 0 then d.enhLv = inv.enhanceLevel end
                        if inv.enchantment then d.ench = inv.enchantment end
                        if inv.locked then d.locked = true end
                        if inv.starred then d.starred = true end
                        if inv.refineSlots then d.refineSlots = inv.refineSlots end
                        if inv.gemSlots then d.gemSlots = inv.gemSlots end
                        if inv.tier then d.tier = inv.tier end
                        if inv.brittle then d.brittle = true end
                        if inv.refineToughness then d.refineToughness = inv.refineToughness end
                        if inv.hasRandom then
                            local tpl = M.itemTemplates[inv.templateId]
                            if tpl and tpl.abyssRandomStats then
                                d.abyssStatTiers = inv.abyssStatTiers
                                d.allstatLines = inv.allstatLines
                                d.randomResistLines = inv.randomResistLines
                                d.randomMainBaseLines = inv.randomMainBaseLines
                                d.randomMainExtraLines = inv.randomMainExtraLines
                                d.abyssAffixLimitTarget = inv.abyssAffixLimitTarget
                                d.templateVersion       = inv.templateVersion
                            else
                                d.effects = inv.effects
                                d.extraEffects = inv.extraEffects
                                d.desc = inv.desc
                            end
                        end
                        if inv.abyssAffix then d.abyssAffix = inv.abyssAffix end
                        if inv.gemEffect then d.gemEffect = inv.gemEffect end
                        liData[tostring(i)] = d
                    else
                        liData[tostring(i)] = inv.templateId
                    end
                end
            end
            return liData
        end)(),
        forgetMeNotBuff = M.forgetMeNotBuff,
        hugBuff = M.hugBuff,
        foodBuff = M.foodBuff,
        potionBuffs = M.potionBuffs,
        lastDanceDayWatched = M.lastDanceDayWatched,
        bulletinBoard = (function()
            local BulletinBoard = require("BulletinBoard")
            return BulletinBoard.collectSaveData()
        end)(),
        questManager = (function()
            local QuestManager = require("QuestManager")
            return QuestManager.collectSaveData()
        end)(),
    }
end

--- 补救白板朱莉面纱：若宝石缺失深渊词缀或主属性加成，随机赋予一次
--- 只修补确实空白的字段，不覆盖已有词缀
--- 兼容两种对象：背包/仓库物品（templateId）和装备宝石槽（gemId）
---@param item table 任意物品对象或装备宝石槽（非面纱则跳过）
---@return boolean repaired 是否发生了实际修补
function M._repairBlankVeil(item)
    -- 兼容背包/仓库物品（.templateId）和装备宝石槽（.gemId）
    local id = item and (item.templateId or item.gemId)
    if id ~= "gem_rainbow_masterwork" then return false end
    local pool = M.ABYSS_AFFIX_POOL
    if not pool or #pool == 0 then return false end

    local repaired = false

    -- 补深渊词缀
    if not item.abyssAffix then
        local roll = pool[math.random(#pool)]
        item.abyssAffix = {
            id       = roll.id,
            name     = roll.name,
            desc     = roll.desc,
            mechanic = roll.mechanic,
        }
        print("[存档修复] 面纱补救深渊词缀: " .. roll.name)
        repaired = true
    end

    -- 补主属性加成
    if not item.gemEffect or not next(item.gemEffect) then
        local mainStats = { "str", "wis", "agi", "con", "foc", "per", "wil", "luk", "cha" }
        local picked = mainStats[math.random(#mainStats)]
        item.gemEffect = { [picked] = 3 }
        print("[存档修复] 面纱补救主属性: " .. picked .. "+3")
        repaired = true
    end

    return repaired
end

--- 从存档数据恢复游戏状态
function M.applySaveData(data)
    if not data or not data.player then return false end
    -- 先做一次普通初始化获取干净的状态
    M.initGame()
    -- 恢复职业（必须在 initGame 之后，否则会被 initGame 重置为 warrior）
    local savedClass = data.currentClass or "warrior"
    if M.PLAYER_DEFS[savedClass] then
        M.currentClass = savedClass
        M.PLAYER_DEF = M.PLAYER_DEFS[savedClass]
        M.SKILL_TREE_LAYOUT = M.CLASS_SKILL_TREE_LAYOUTS[savedClass]
        -- 同步更新 initGame 创建的 player 的名称和颜色
        if M.player then
            M.player.name = M.PLAYER_DEF.name
            M.player.color = M.PLAYER_DEF.color
        end
    end
    -- 恢复 confirmedClass（独立于 changeClass，仅在加载和觉醒确认时写入）
    M.confirmedClass = data.confirmedClass or M.currentClass
    -- 恢复角色名
    M.charName = data.name or ""
    -- 恢复关卡/回合
    M.currentStage = data.currentStage or 1
    M.turnNumber = data.turnNumber or 1
    M.gold = data.gold or 0
    M.score = data.score or 0
    -- 恢复世界天气状态（默认雨天）
    if data.isRaining ~= nil then
        M.isRaining = data.isRaining
    else
        M.isRaining = true
    end
    M.isWindy = data.isWindy or false
    M.windDirection = data.windDirection or 1
    M.isScorching = data.isScorching or false
    -- 恢复天气变更计时
    M.weatherTime = data.weatherTime or 1
    if M.weatherTime < 1 then M.weatherTime = 1 end  -- 兼容旧存档（旧值为0）
    M.weatherChangeTimer = data.weatherChangeTimer or 0
    M.weatherCheckCount = data.weatherCheckCount or 0
    M.weatherRealTimer = 0
    -- 恢复采集关卡状态（JSON序列化后key变为字符串，需转回数字）
    -- 兼容旧格式（纯数组）和新格式（{ alive = {...}, depleted = bool, resetCounter = N }）
    local oldGlobalCounter = data.gatherResetCounter or 0
    M.gatherStageStates = {}
    if data.gatherStageStates then
        for k, v in pairs(data.gatherStageStates) do
            if type(v) == "table" then
                local numKey = tonumber(k) or k
                if v.alive ~= nil then
                    -- 新格式：{ alive = {...}, depleted = bool, resetCounter = N }
                    -- 若缺少 resetCounter，用旧全局计数器作为初始值（平滑迁移）
                    if not v.resetCounter then
                        v.resetCounter = oldGlobalCounter
                    end
                    M.gatherStageStates[numKey] = v
                elseif #v > 0 then
                    -- 旧格式：纯数组，转为新格式，继承全局计数器
                    M.gatherStageStates[numKey] = { alive = v, depleted = false, resetCounter = oldGlobalCounter }
                end
                -- 旧格式空数组：跳过（等同"从未进入"）
            end
        end
    end
    M.gatherResetCounter = oldGlobalCounter  -- 兼容保留
    M.lastRestockDay = data.lastRestockDay or 0
    M.rebirthCooldownDay = data.rebirthCooldownDay  -- 重生被动CD（nil表示从未触发）
    M.veilReforgeTime = data.veilReforgeTime  -- nil表示未在重铸
    M.abyssChallengeDay = data.abyssChallengeDay or -1
    M.abyssChallengeUsed = data.abyssChallengeUsed or 0
    M.abyssWorldDay = data.abyssWorldDay or -1
    M.abyssWorldUsed = data.abyssWorldUsed or 0
    M.abyssWorldActive = data.abyssWorldActive or false
    M.abyssWorldLives = data.abyssWorldLives or 0
    M.slimeRevengeDay = data.slimeRevengeDay or -1
    M.slimeRevengeUsed = data.slimeRevengeUsed or 0
    M.dihataRevengeDay = data.dihataRevengeDay or -1
    M.dihataRevengeUsed = data.dihataRevengeUsed or 0
    M.abyssFakeAd = data.abyssFakeAd or M.abyssFakeAd or false
    M.adFree = data.adFree or M.adFree or false
    M.dailyBulletinDoneCount = data.dailyBulletinDoneCount or 0
    M.bulletinQuestTotalDone = data.bulletinQuestTotalDone or 0
    M.housePurchased = data.housePurchased or false
    M.homeType = data.homeType or "small"
    M.partnerNpcKey = data.partnerNpcKey
    M.partnerLivingTogether = data.partnerLivingTogether or false
    M.customPetNames = data.customPetNames or {}
    M.elfvahBooksRead = data.elfvahBooksRead or nil
    M.elfvahLanguageLearned = data.elfvahLanguageLearned or false
    M.elfvahElfTalked = data.elfvahElfTalked or false
    M.homeNpc = nil  -- 运行时状态不持久化
    M.adDailyCount = data.adDailyCount or 0
    M.adDailyDate = data.adDailyDate or ""
    -- 恢复勿忘我BUFF和舞池观赏记录
    M.forgetMeNotBuff = data.forgetMeNotBuff  -- nil 或 { active, expireTime }
    M.hugBuff = data.hugBuff  -- nil 或 { active, expireTime }，精神抖擞BUFF
    M.foodBuff = data.foodBuff  -- nil 或 { foodId, name, expireTime, hpRegen, mpRegen, str, foc, wis }
    M.potionBuffs = data.potionBuffs or {}  -- { [stat] = { amount, expireTime, isPercent } }
    -- 修复旧存档中因 weatherTime 回绕导致 expireTime 远大于当前时间的异常值
    -- 正常 buff 最长 8 小时 = 480 分钟，若剩余时间超过 1440 分钟（24 小时）则视为异常并清除
    local MAX_VALID_REMAIN = 1440
    local wt = M.weatherTime or 1
    if M.foodBuff and M.foodBuff.expireTime and (M.foodBuff.expireTime - wt) > MAX_VALID_REMAIN then
        M.foodBuff = nil
        print("[存档修复] foodBuff.expireTime 异常，已清除")
    end
    if M.forgetMeNotBuff and M.forgetMeNotBuff.expireTime
       and (M.forgetMeNotBuff.expireTime - wt) > MAX_VALID_REMAIN then
        M.forgetMeNotBuff = nil
        print("[存档修复] forgetMeNotBuff.expireTime 异常，已清除")
    end
    if M.hugBuff and M.hugBuff.expireTime and (M.hugBuff.expireTime - wt) > MAX_VALID_REMAIN then
        M.hugBuff = nil
        print("[存档修复] hugBuff.expireTime 异常，已清除")
    end
    for stat, buff in pairs(M.potionBuffs) do
        if buff.expireTime and (buff.expireTime - wt) > MAX_VALID_REMAIN then
            M.potionBuffs[stat] = nil
            print("[存档修复] potionBuff[" .. stat .. "].expireTime 异常，已清除")
        end
    end
    M.lastDanceDayWatched = data.lastDanceDayWatched or -1
    M.dancerShowPhase = nil  -- 演出状态不持久化
    -- 恢复布告栏委托数据（始终调用，无数据时清除旧状态防止跨角色泄漏）
    local BulletinBoard = require("BulletinBoard")
    BulletinBoard.applySaveData(data.bulletinBoard)
    -- 恢复玩家
    local pd = data.player
    M.player.x = pd.x or 6
    M.player.y = pd.y or 7
    M.player.facing = pd.facing or "down"
    M.player.level = pd.level or 1
    M.player.exp = pd.exp or 0
    M.player.statPoints = pd.statPoints or 0
    if pd.stats then
        for k, v in pairs(pd.stats) do
            M.player.stats[k] = v
        end
    end
    -- 先用临时stats计算一次，最终 recalcStats 在装备恢复后执行
    M.player.hp = pd.hp or 1  -- 暂存，装备恢复后再 clamp
    M.player.mp = pd.mp or 0
    M.bloodShield = 0  -- 饮血护甲值：重新登录时清零
    M.displayExp = M.player.exp
    M.displayExpLevel = M.player.level
    -- 恢复背包/仓库扩充容量（在恢复物品栏之前）
    if data.bagSlots and data.bagSlots > M.bagSlots then
        M.bagSlots = data.bagSlots
    end
    if data.warehouseSlots and data.warehouseSlots > M.warehouseSlots then
        M.warehouseSlots = data.warehouseSlots
    end
    -- 恢复物品栏（兼容新旧存档格式）
    M.inventory = {}
    for i = 1, M.bagSlots do M.inventory[i] = nil end
    if data.inventory then
        for k, v in pairs(data.inventory) do
            local idx = tonumber(k)
            if idx then
                if type(v) == "table" then
                    local item = M.createItem(v.id, v.qty)
                    if item then
                        if v.enhLv and v.enhLv > 0 then
                            item.enhanceLevel = v.enhLv
                            local tpl = M.itemTemplates[v.id]
                            if tpl then item.name = tpl.name .. " +" .. v.enhLv end
                        end
                        if v.tier then item.tier = v.tier end
                        if v.ench then item.enchantment = v.ench end
                        if v.locked then item.locked = true end
                        if v.starred then item.starred = true end
                        if v.refineSlots then item.refineSlots = v.refineSlots end
                        if v.gemSlots then item.gemSlots = v.gemSlots end
                        if v.brittle then item.brittle = true end
                        if v.refineToughness then item.refineToughness = v.refineToughness end
                        if v.enhLv and v.enhLv > 0 then
                            local base = (M.itemTemplates[v.id] or {}).value or 0
                            item.value = base + M.calcEnhanceTotalInvestment(item)
                        end
                        if v.abyssStatTiers then
                            -- 有档位索引：统一从模板重建（兼容新旧存档格式，保证模板更新后数值同步）
                            item.abyssStatTiers = v.abyssStatTiers
                            item.allstatLines = v.allstatLines
                            item.randomResistLines = v.randomResistLines
                            item.randomMainBaseLines = v.randomMainBaseLines
                            item.randomMainExtraLines = v.randomMainExtraLines
                            item.abyssAffixLimitTarget = v.abyssAffixLimitTarget
                            item.templateVersion       = v.templateVersion
                            item.hasRandom = true
                            M.rebuildAbyssStats(item)
                        else
                            -- 无档位索引：无深渊随机属性，直接用存档值
                            if v.effects then item.effects = v.effects; item.hasRandom = true end
                            if v.extraEffects then item.extraEffects = v.extraEffects end
                            if v.desc then item.desc = v.desc end
                        end
                        if v.abyssAffix then item.abyssAffix = v.abyssAffix end
                        if v.gemEffect then item.gemEffect = v.gemEffect end
                    end
                    M.inventory[idx] = item
                else
                    -- 旧格式：直接是 templateId 字符串
                    M.inventory[idx] = M.createItem(v)
                end
            end
        end
    end
    -- 恢复装备（兼容新旧存档格式）
    M.equipment = {}
    if data.equipment then
        for slotId, v in pairs(data.equipment) do
            if type(v) == "table" then
                -- 新格式：{ id = templateId, enhLv = N, ench = {...}, locked = bool }
                local item = M.createItem(v.id)
                if item then
                    if v.enhLv and v.enhLv > 0 then
                        item.enhanceLevel = v.enhLv
                        local tpl = M.itemTemplates[v.id]
                        if tpl then item.name = tpl.name .. " +" .. v.enhLv end
                    end
                    if v.tier then item.tier = v.tier end
                    if v.ench then item.enchantment = v.ench end
                    if v.locked then item.locked = true end
                    if v.starred then item.starred = true end
                    if v.refineSlots then item.refineSlots = v.refineSlots end
                    if v.gemSlots then item.gemSlots = v.gemSlots end
                    if v.brittle then item.brittle = true end
                    if v.refineToughness then item.refineToughness = v.refineToughness end
                    if v.enhLv and v.enhLv > 0 then
                        local base = (M.itemTemplates[v.id] or {}).value or 0
                        item.value = base + M.calcEnhanceTotalInvestment(item)
                    end
                    if v.abyssStatTiers then
                        -- 有档位索引：统一从模板重建（兼容新旧存档格式，保证模板更新后数值同步）
                        item.abyssStatTiers = v.abyssStatTiers
                        item.allstatLines = v.allstatLines
                        item.randomResistLines = v.randomResistLines
                        item.randomMainBaseLines = v.randomMainBaseLines
                        item.randomMainExtraLines = v.randomMainExtraLines
                        item.abyssAffixLimitTarget = v.abyssAffixLimitTarget
                        item.templateVersion       = v.templateVersion
                        item.hasRandom = true
                        M.rebuildAbyssStats(item)
                    else
                        -- 无档位索引：无深渊随机属性，直接用存档值
                        if v.effects then item.effects = v.effects; item.hasRandom = true end
                        if v.extraEffects then item.extraEffects = v.extraEffects end
                        if v.desc then item.desc = v.desc end
                    end
                    if v.abyssAffix then item.abyssAffix = v.abyssAffix end
                    if v.gemEffect then item.gemEffect = v.gemEffect end
                end
                M.equipment[slotId] = item
            else
                -- 旧格式：直接是 templateId 字符串
                M.equipment[slotId] = M.createItem(v)
            end
        end
    end
    -- 迁移：修正无效槽位 "legs" → 退回背包
    if M.equipment["legs"] then
        local item = M.equipment["legs"]
        M.equipment["legs"] = nil
        if item then
            table.insert(M.inventory, item)
            print("[Save迁移] 将无效槽位 legs 的装备 " .. (item.name or item.templateId or "?") .. " 退回背包")
        end
    end
    -- 迁移：修正无效槽位 "hand" → 退回背包（虚空握曾错误使用 hand 而非 gloves）
    if M.equipment["hand"] then
        local item = M.equipment["hand"]
        M.equipment["hand"] = nil
        if item then
            table.insert(M.inventory, item)
            print("[Save迁移] 将无效槽位 hand 的装备 " .. (item.name or item.templateId or "?") .. " 退回背包")
        end
    end
    -- 迁移：修正无效槽位 "head" → 退回背包（深度思维曾错误使用 head 而非 hat）
    if M.equipment["head"] then
        local item = M.equipment["head"]
        M.equipment["head"] = nil
        if item then
            table.insert(M.inventory, item)
            print("[Save迁移] 将无效槽位 head 的装备 " .. (item.name or item.templateId or "?") .. " 退回背包")
        end
    end
    -- 迁移：hero_mace extraEffects 从 heroRadiance → heroMaceHeal（辉光改为被动技能）
    for _, slot in pairs(M.equipment) do
        if type(slot) == "table" and slot.templateId == "hero_mace"
           and slot.extraEffects and slot.extraEffects.heroRadiance then
            slot.extraEffects.heroRadiance = nil
            slot.extraEffects.heroMaceHeal = 12
            print("[Save迁移] hero_mace: heroRadiance → heroMaceHeal")
        end
    end
    -- 背包中的 hero_mace 也需要迁移
    for _, item in ipairs(M.inventory) do
        if type(item) == "table" and item.templateId == "hero_mace"
           and item.extraEffects and item.extraEffects.heroRadiance then
            item.extraEffects.heroRadiance = nil
            item.extraEffects.heroMaceHeal = 12
        end
    end

    -- 恢复技能
    M.skillPoints = data.skillPoints or 0
    M.skillLevels = {}
    if data.skillLevels then
        for k, v in pairs(data.skillLevels) do
            M.skillLevels[k] = v
        end
        -- 存档兼容：p_pdef_up → p_dmg_reduce（物理防御力UP 替换为 受伤降低）
        if M.skillLevels["p_pdef_up"] then
            if not M.skillLevels["p_dmg_reduce"] or M.skillLevels["p_dmg_reduce"] == 0 then
                M.skillLevels["p_dmg_reduce"] = M.skillLevels["p_pdef_up"]
            end
            M.skillLevels["p_pdef_up"] = nil
        end
        -- 存档兼容：p_mp_up → p_radiance（魔法值UP 替换为 辉光）
        if M.skillLevels["p_mp_up"] then
            if not M.skillLevels["p_radiance"] or M.skillLevels["p_radiance"] == 0 then
                M.skillLevels["p_radiance"] = M.skillLevels["p_mp_up"]
            end
            M.skillLevels["p_mp_up"] = nil
        end
        -- 存档兼容：quick_adj → w_blood_drink（生命回复UP 替换为 饮血）
        if M.skillLevels["quick_adj"] then
            if not M.skillLevels["w_blood_drink"] or M.skillLevels["w_blood_drink"] == 0 then
                M.skillLevels["w_blood_drink"] = M.skillLevels["quick_adj"]
            end
            M.skillLevels["quick_adj"] = nil
        end
    end
    M.activeSkills = {}
    if data.activeSkills then
        for k, v in pairs(data.activeSkills) do
            M.activeSkills[tonumber(k) or k] = v
        end
    end
    -- 恢复生活技能经验和等阶
    M.lifeSkillExp = {}
    M.lifeSkillTiers = {}
    if data.lifeSkillExp then
        for k, v in pairs(data.lifeSkillExp) do
            M.lifeSkillExp[k] = v
        end
    end
    if data.lifeSkillTiers then
        for k, v in pairs(data.lifeSkillTiers) do
            M.lifeSkillTiers[k] = v
        end
    end
    -- 恢复自动战斗设置
    if data.autoConsumables then
        M.autoConsumables = {}
        for k, v in pairs(data.autoConsumables) do
            M.autoConsumables[tonumber(k) or k] = v
        end
    end
    if data.autoConsumableThresholds then
        M.autoConsumableThresholds = {}
        for k, v in pairs(data.autoConsumableThresholds) do
            M.autoConsumableThresholds[tonumber(k) or k] = v
        end
    end
    -- 恢复自动食物和增强药剂设置
    M.autoFood = data.autoFood
    M.autoBuffPotion = data.autoBuffPotion
    M.autoChargeMode = data.autoChargeMode or "flank"
    -- 恢复冒险者等级（必须在 recalcStats 之前，否则等级加成无法传导到二级属性）
    M.adventurerRank = data.adventurerRank or 1
    -- 恢复击杀追踪与副本通关记录
    M.monsterKillCounts = data.monsterKillCounts or {}
    -- stageKillCounts / stageClearedOnce 的 key 是数字(stageIndex)，
    -- JSON 序列化后变为字符串，需转回数字才能与 GS.currentStage 匹配
    M.stageKillCounts = {}
    if data.stageKillCounts then
        for k, v in pairs(data.stageKillCounts) do
            M.stageKillCounts[tonumber(k) or k] = v
        end
    end
    M.maxStageReached = data.maxStageReached or data.currentStage or 1
    M.stageClearedOnce = {}
    if data.stageClearedOnce then
        for k, v in pairs(data.stageClearedOnce) do
            M.stageClearedOnce[tonumber(k) or k] = v
        end
    end
    M.knownNPCs = data.knownNPCs or {}
    M.talkQAAsked = data.talkQAAsked or {}
    M.npcTalkedRecord = data.npcTalkedRecord or {}
    -- 旧存档兼容：从 dialogueFlags 的首访对话迁移交谈记录
    if not data.npcTalkedRecord and M.dialogueFlags then
        local flagToNpc = {
            blacksmith_first_visit = "blacksmith",
            armor_shop_first_visit = "armor_shop",
            jewelry_shop_first_visit = "jewelry_shop",
            potion_shop_first_visit = "potion_shop",
            tavern_first_visit = "tavern",
            dancer_first_visit = "tavern_dancer",
        }
        for flag, npcKey in pairs(flagToNpc) do
            if M.dialogueFlags[flag] then
                M.npcTalkedRecord[npcKey] = true
            end
        end
        -- 舞女旧存档兼容：通过好感度判断
        if (M.npcAffinity["tavern_dancer"] or 0) > 10 then
            M.npcTalkedRecord["tavern_dancer"] = true
        end
    end
    M.dungeonsCleared = data.dungeonsCleared or {}
    M.dungeonClearCounts = data.dungeonClearCounts or {}
    M.areaKillCounts = data.areaKillCounts or {}
    M.eliyaTravelDone = data.eliyaTravelDone or {}
    M.angelicaTravelDone = data.angelicaTravelDone or {}
    M.difenTravelDone = data.difenTravelDone or {}
    M.forgetMeNotLevel = math.min(data.forgetMeNotLevel or 0, 4)
    M.forgetMeNotPermanent = data.forgetMeNotPermanent or false
    M._angelicaSeaKillSnapshot = data._angelicaSeaKillSnapshot
    M.infiniteTowerUnlocked = data.infiniteTowerUnlocked or false
    M.sharedStorageUnlocked = data.sharedStorageUnlocked or false
    M.abyssUnlocked = data.abyssUnlocked or false
    M.abyssPoints = data.abyssPoints or 0
    -- 恢复主线/支线任务（必须在 adventurerRank / dungeonsCleared 之后）
    do
        local QuestManager = require("QuestManager")
        QuestManager.applySaveData(data.questManager)
    end
    M.recalcStats(M.player)
    M.player.hp = math.min(pd.hp or M.player.maxHp, M.player.maxHp)
    M.player.mp = math.min(pd.mp or M.player.maxMp, M.player.maxMp)
    -- 死亡状态重进：以1HP复活
    if M.player.hp <= 0 then
        M.player.hp = 1
        print("[Save] 检测到死亡状态存档，以1HP复活")
    end
    M.displayHp = M.player.hp
    M.displayMp = M.player.mp
    M.currentShopTier = 0  -- 重置以强制刷新
    M.updateShopByLevel()
    -- 恢复商店库存（用存档的 stock 覆盖 updateShopByLevel 生成的默认值）
    if data.shopStock then
        for shopKey, savedItems in pairs(data.shopStock) do
            local shopItems = M.SHOP_INVENTORY[shopKey]
            if shopItems then
                for idx, savedEntry in pairs(savedItems) do
                    local i = tonumber(idx)
                    if i and shopItems[i] and shopItems[i].templateId == savedEntry.templateId then
                        shopItems[i].stock = savedEntry.stock
                    end
                end
            end
        end
    end
    -- 恢复仓库（多储物箱）
    M.warehouses = { {}, {}, {}, {} }
    local function loadWarehouseData(whData, targetTable)
        if not whData then return end
        for k, v in pairs(whData) do
            local idx = tonumber(k)
            if idx then
                if type(v) == "table" then
                    local item = M.createItem(v.id, v.qty)
                    if item then
                        if v.enhLv and v.enhLv > 0 then
                            item.enhanceLevel = v.enhLv
                            local tpl = M.itemTemplates[v.id]
                            if tpl then item.name = tpl.name .. " +" .. v.enhLv end
                        end
                        if v.tier then item.tier = v.tier end
                        if v.ench then item.enchantment = v.ench end
                        if v.locked then item.locked = true end
                        if v.starred then item.starred = true end
                        if v.refineSlots then item.refineSlots = v.refineSlots end
                        if v.gemSlots then item.gemSlots = v.gemSlots end
                        if v.brittle then item.brittle = true end
                        if v.refineToughness then item.refineToughness = v.refineToughness end
                        if v.enhLv and v.enhLv > 0 then
                            local base = (M.itemTemplates[v.id] or {}).value or 0
                            item.value = base + M.calcEnhanceTotalInvestment(item)
                        end
                        if v.abyssStatTiers and not v.effects then
                            item.abyssStatTiers = v.abyssStatTiers
                            item.allstatLines = v.allstatLines
                            item.randomResistLines = v.randomResistLines
                            item.randomMainBaseLines = v.randomMainBaseLines
                            item.randomMainExtraLines = v.randomMainExtraLines
                            item.abyssAffixLimitTarget = v.abyssAffixLimitTarget
                            item.templateVersion       = v.templateVersion
                            item.hasRandom = true
                            M.rebuildAbyssStats(item)
                        else
                            if v.effects then item.effects = v.effects; item.hasRandom = true end
                            if v.extraEffects then item.extraEffects = v.extraEffects end
                            if v.desc then item.desc = v.desc end
                            if v.abyssStatTiers then item.abyssStatTiers = v.abyssStatTiers end
                            if v.allstatLines then item.allstatLines = v.allstatLines end
                        end
                        if v.abyssAffix then item.abyssAffix = v.abyssAffix end
                        if v.gemEffect then item.gemEffect = v.gemEffect end
                    end
                    targetTable[idx] = item
                else
                    targetTable[idx] = M.createItem(v)
                end
            end
        end
    end
    if data.warehouses then
        -- 新格式：多仓库
        for wid = 1, M.WAREHOUSE_COUNT do
            loadWarehouseData(data.warehouses[tostring(wid)], M.warehouses[wid])
        end
    elseif data.warehouse then
        -- 旧格式兼容：单仓库 → 仓库1
        loadWarehouseData(data.warehouse, M.warehouses[1])
    end
    M.activeWarehouseId = 1
    M.warehouse = M.warehouses[1]
    -- 恢复遗失物品
    M.lostItems = {}
    if data.lostItems then
        for k, v in pairs(data.lostItems) do
            local idx = tonumber(k)
            if idx then
                if type(v) == "table" then
                    local item = M.createItem(v.id, v.qty)
                    if item then
                        if v.enhLv and v.enhLv > 0 then
                            item.enhanceLevel = v.enhLv
                            local tpl = M.itemTemplates[v.id]
                            if tpl then item.name = tpl.name .. " +" .. v.enhLv end
                        end
                        if v.tier then item.tier = v.tier end
                        if v.ench then item.enchantment = v.ench end
                        if v.locked then item.locked = true end
                        if v.starred then item.starred = true end
                        if v.refineSlots then item.refineSlots = v.refineSlots end
                        if v.gemSlots then item.gemSlots = v.gemSlots end
                        if v.brittle then item.brittle = true end
                        if v.refineToughness then item.refineToughness = v.refineToughness end
                        if v.enhLv and v.enhLv > 0 then
                            local base = (M.itemTemplates[v.id] or {}).value or 0
                            item.value = base + M.calcEnhanceTotalInvestment(item)
                        end
                        if v.abyssStatTiers and not v.effects then
                            item.abyssStatTiers = v.abyssStatTiers
                            item.allstatLines = v.allstatLines
                            item.randomResistLines = v.randomResistLines
                            item.randomMainBaseLines = v.randomMainBaseLines
                            item.randomMainExtraLines = v.randomMainExtraLines
                            item.abyssAffixLimitTarget = v.abyssAffixLimitTarget
                            item.templateVersion       = v.templateVersion
                            item.hasRandom = true
                            M.rebuildAbyssStats(item)
                        else
                            if v.effects then item.effects = v.effects; item.hasRandom = true end
                            if v.extraEffects then item.extraEffects = v.extraEffects end
                            if v.desc then item.desc = v.desc end
                            if v.abyssStatTiers then item.abyssStatTiers = v.abyssStatTiers end
                            if v.allstatLines then item.allstatLines = v.allstatLines end
                        end
                        if v.abyssAffix then item.abyssAffix = v.abyssAffix end
                        if v.gemEffect then item.gemEffect = v.gemEffect end
                    end
                    M.lostItems[idx] = item
                else
                    M.lostItems[idx] = M.createItem(v)
                end
            end
        end
    end
    -- 恢复对话标记
    M.dialogueFlags = data.dialogueFlags or {}
    -- 恢复兑换码记录
    M.redeemedCodes = data.redeemedCodes or {}
    -- 恢复好感度
    M.npcAffinity = data.npcAffinity or {}
    M.npcTalkAffinityDate = data.npcTalkAffinityDate or {}
    M.npcKissAffinityDate = data.npcKissAffinityDate or {}
    M.npcConfessAffinityDate = data.npcConfessAffinityDate or {}
    M.npcProposalAffinityDate = data.npcProposalAffinityDate or {}
    M.homeKissDate = data.homeKissDate or -1
    M.homeHugDate = data.homeHugDate or -1
    M.homeHugDate2 = data.homeHugDate2 or -1
    -- 恢复苏醒事件完成标志
    -- [兜底逻辑] 等级 > 1 是曾正常游玩的铁证（苏醒事件期间没有战斗经验，无法升级）。
    -- 因此无论存档中 awakeningCompleted 是 nil（旧存档）还是显式 false（异常存档），
    -- 只要等级 > 1，一律视为苏醒事件已完成，防止 changeClass 二次抹除技能。
    local levelNow = M.player and (M.player.level or 1) or 1
    if data.awakeningCompleted then
        M.awakeningCompleted = true
    elseif levelNow > 1 then
        -- 等级 > 1 但标志为 false/nil：存档不一致，自动修正
        M.awakeningCompleted = true
        print("[Migration] awakeningCompleted 不一致：level=" .. levelNow .. " 但标志为 false/nil，已自动修正")
    else
        M.awakeningCompleted = false
    end
    -- 恢复事件完成状态表
    M.eventCompleted = data.eventCompleted or {}
    M.signInStartDay = data.signInStartDay or 0
    M.signInRewards = data.signInRewards or {}
    M.signInDayPlayTime = data.signInDayPlayTime or {}
    -- 日常签到数据已迁移至账户级云端（clientCloud），不再从角色存档加载

    -- [兜底防护] 通过已学技能反推真实职业，修复任何职业被错误覆盖的情况
    -- 场景：不同角色槽位之间切换时，initGame 可能把 currentClass 重置为错误值
    if M.skillLevels then
        -- 构建技能→职业映射表
        local skillToClass = {}
        for classId, layout in pairs(M.CLASS_SKILL_TREE_LAYOUTS) do
            for _, row in ipairs(layout) do
                for _, skillId in ipairs(row) do
                    if skillId then
                        skillToClass[skillId] = classId
                    end
                end
            end
        end
        -- 从已学技能中推断真实职业
        local detectedClass = nil
        local conflict = false
        for skillId, lv in pairs(M.skillLevels) do
            if lv and lv > 0 then
                local cls = skillToClass[skillId]
                if cls then
                    if detectedClass == nil then
                        detectedClass = cls
                    elseif detectedClass ~= cls then
                        conflict = true
                        break
                    end
                end
            end
        end
        -- 检测到职业不一致且无冲突时修复
        if detectedClass and not conflict and M.PLAYER_DEFS[detectedClass]
           and detectedClass ~= M.currentClass then
            print("[存档修复] 检测到职业不一致：存档=" .. tostring(M.currentClass)
                .. " 技能推断=" .. detectedClass .. "，已修正")
            M.currentClass = detectedClass
            M.confirmedClass = detectedClass
            M.PLAYER_DEF = M.PLAYER_DEFS[detectedClass]
            M.SKILL_TREE_LAYOUT = M.CLASS_SKILL_TREE_LAYOUTS[detectedClass]
            if M.player then
                M.player.name = M.PLAYER_DEF.name
                M.player.color = M.PLAYER_DEF.color
            end
        end
        -- [兜底防护 Layer2] 技能为空时，用 confirmedClass 回退
        -- 场景：changeClass 清空了 skillLevels 后的错误存档覆盖
        if not detectedClass and M.confirmedClass
           and M.PLAYER_DEFS[M.confirmedClass]
           and M.confirmedClass ~= M.currentClass then
            print("[存档修复] 技能为空，通过 confirmedClass 回退：存档="
                .. tostring(M.currentClass) .. " confirmedClass=" .. M.confirmedClass .. "，已修正")
            M.currentClass = M.confirmedClass
            M.PLAYER_DEF = M.PLAYER_DEFS[M.confirmedClass]
            M.SKILL_TREE_LAYOUT = M.CLASS_SKILL_TREE_LAYOUTS[M.confirmedClass]
            if M.player then
                M.player.name = M.PLAYER_DEF.name
                M.player.color = M.PLAYER_DEF.color
            end
        end
    end

    -- 同步所有装备的附魔/精炼词缀数值（确保与最新池子定义一致）
    M.syncAllAffixValues()

    -- [存档修复] 白板朱莉面纱补救：扫描背包、仓库、装备宝石槽
    -- 如面纱缺失深渊词缀或主属性加成，随机赋予一次（不覆盖已有词缀）
    local veilRepaired = false
    for _, item in pairs(M.inventory or {}) do
        if M._repairBlankVeil(item) then veilRepaired = true end
    end
    for wid = 1, M.WAREHOUSE_COUNT do
        for _, item in pairs(M.warehouses and M.warehouses[wid] or {}) do
            if M._repairBlankVeil(item) then veilRepaired = true end
        end
    end
    local equipSlotRepaired = false
    for _, equip in pairs(M.equipment or {}) do
        if equip and equip.gemSlots then
            for _, slot in pairs(equip.gemSlots) do
                if slot and slot.gemId == "gem_rainbow_masterwork" then
                    if M._repairBlankVeil(slot) then
                        veilRepaired = true
                        equipSlotRepaired = true
                    end
                end
            end
        end
    end
    -- 装备槽内词缀修复后需重算属性，确保当局生效
    if equipSlotRepaired then
        M.recalcStats(M.player)
    end
    -- 有任何修复发生时标记存档脏位，确保修复结果被持久化
    -- （指纹函数仅追踪 templateId+quantity，不追踪 abyssAffix/gemEffect 深字段）
    if veilRepaired and M.autoSave then
        M.autoSave.dirty = true
    end

    return true
end

--- 从存档数据中提取 meta 概要信息（用于角色选择界面显示）
function M.buildMetaSlotInfo(saveData)
    if not saveData then return nil end
    local p = saveData.player or {}
    return {
        name    = saveData.name or "",
        class   = saveData.currentClass or "warrior",
        level   = p.level or 1,
        stage   = saveData.currentStage or 1,
        gold    = saveData.gold or 0,
        rank    = saveData.adventurerRank or 1,
    }
end

-- ===== 每日云存档备份系统 =====
-- 每个自然日自动备份一次，滚动保留最近 3 天
local BACKUP_KEEP_DAYS = 3
M._backupDoneToday = {}  -- { [slotIdx] = "MMDD" } 记录今天是否已备份（内存缓存，避免重复）

--- 获取备份用的日期标签（MMDD格式，紧凑）
local function getBackupDateTag()
    return os.date("%m%d")
end

--- 执行每日备份（在正常存档成功后异步调用）
---@param slotIdx number 槽位索引
---@param saveData table 当前存档数据
function M._tryDailyBackup(slotIdx, saveData)
    local today = getBackupDateTag()
    -- 今天已经备份过该槽位，跳过
    if M._backupDoneToday[slotIdx] == today then return end

    local bakMetaKey = "bak_meta"
    -- 读取备份 meta，判断今天是否已备份
    clientScore:Get(bakMetaKey, {
        ok = function(values)
            local bakMeta = (values and values[bakMetaKey]) or {}
            local slotKey = tostring(slotIdx)
            local history = bakMeta[slotKey] or {}  -- 日期标签数组，如 {"0326","0327","0328"}

            -- 检查是否已有今天的备份
            for _, tag in ipairs(history) do
                if tag == today then
                    M._backupDoneToday[slotIdx] = today
                    print("[备份] 槽位" .. slotIdx .. " 今日(" .. today .. ")已有备份，跳过")
                    return
                end
            end

            -- 构建新的历史列表（加入今天）
            history[#history + 1] = today

            -- 找出需要删除的过期备份
            local expiredTags = {}
            while #history > BACKUP_KEEP_DAYS do
                local old = table.remove(history, 1)
                expiredTags[#expiredTags + 1] = old
            end

            -- 更新 meta
            bakMeta[slotKey] = history

            -- 构建 BatchSet：写入今天的备份 + 更新 meta + 删除过期备份
            local batch = clientScore:BatchSet()
            local bakKey = "slot_" .. slotIdx .. "_bak_" .. today
            batch:Set(bakKey, saveData)
            batch:Set(bakMetaKey, bakMeta)
            for _, oldTag in ipairs(expiredTags) do
                local oldKey = "slot_" .. slotIdx .. "_bak_" .. oldTag
                batch:Delete(oldKey)
            end

            batch:Save("每日备份槽位" .. slotIdx, {
                ok = function()
                    M._backupDoneToday[slotIdx] = today
                    print("[备份] 槽位" .. slotIdx .. " 每日备份成功 (" .. today .. "), 保留: " .. table.concat(history, ","))
                    if #expiredTags > 0 then
                        print("[备份] 已清理过期备份: " .. table.concat(expiredTags, ","))
                    end
                end,
                error = function(code, reason)
                    print("[备份] 槽位" .. slotIdx .. " 每日备份失败: " .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            print("[备份] 读取备份 meta 失败: " .. tostring(reason))
        end,
    })
end

--- 从最新备份恢复指定槽位数据到云端存档（兑换码触发）
---@param slotIdx number 槽位索引 (1-6)
---@param onSuccess fun(tag: string) 成功回调，参数为备份日期标签 MMDD
---@param onError fun(reason: string) 失败回调
function M.restoreSlotFromBackup(slotIdx, onSuccess, onError)
    local bakMetaKey = "bak_meta"
    clientScore:Get(bakMetaKey, {
        ok = function(values)
            local bakMeta = (values and values[bakMetaKey]) or {}
            local history = bakMeta[tostring(slotIdx)] or {}
            if #history == 0 then
                if onError then onError("该槽位没有找到任何备份记录") end
                return
            end
            -- 取上一个自然日的备份（即 history 中日期标签 < 今天的最新一条）
            local today = getBackupDateTag()
            local targetTag = nil
            for i = #history, 1, -1 do
                if history[i] ~= today then
                    targetTag = history[i]
                    break
                end
            end
            if not targetTag then
                if onError then onError("没有找到今天之前的备份记录（当前仅有今日备份）") end
                return
            end
            local bakKey = "slot_" .. slotIdx .. "_bak_" .. targetTag
            clientScore:Get(bakKey, {
                ok = function(vals)
                    local bakData = vals and vals[bakKey]
                    if not bakData then
                        if onError then onError("备份数据为空（" .. targetTag .. "）") end
                        return
                    end
                    -- 将备份写回正式槽位，同步更新 meta 摘要
                    local slotKey = "slot_" .. slotIdx
                    local batch = clientScore:BatchSet()
                        :Set(slotKey, bakData)
                    if M.charSlotMeta and M.charSlotMeta.slots then
                        M.charSlotMeta.slots[tostring(slotIdx)] = M.buildMetaSlotInfo(bakData)
                        batch:Set("meta", M.charSlotMeta)
                    end
                    batch:Save("备份恢复槽位" .. slotIdx, {
                        ok = function()
                            print("[备份恢复] 槽位" .. slotIdx .. " 已从备份 " .. targetTag .. " 恢复")
                            if onSuccess then onSuccess(targetTag) end
                        end,
                        error = function(code, reason)
                            print("[备份恢复] 写入失败:", code, reason)
                            if onError then onError("写入失败: " .. tostring(reason)) end
                        end,
                    })
                end,
                error = function(code, reason)
                    if onError then onError("备份读取失败: " .. tostring(reason)) end
                end,
            })
        end,
        error = function(code, reason)
            if onError then onError("备份元数据读取失败: " .. tostring(reason)) end
        end,
    })
end

-- ── GM 指令执行（目标玩家客户端侧）──
-- 记录本次会话已处理的指令 ts，防止重复执行
local _gmRestoreProcessedTs = {}
local _GM_RESTORE_DONE_FILE = "gm_restore_done.txt"
local _gmRestoreDoneLoaded = false  -- 文件只需加载一次

--- 从本地文件加载已处理的 ts 集合（防重启后重复执行，只执行一次）
local function _loadGMRestoreDone()
    if _gmRestoreDoneLoaded then return end
    _gmRestoreDoneLoaded = true
    if not fileSystem:FileExists(_GM_RESTORE_DONE_FILE) then return end
    local f = File(_GM_RESTORE_DONE_FILE, FILE_READ)
    if not f:IsOpen() then return end
    local content = f:ReadString()
    f:Close()
    if not content or content == "" then return end
    for ts in content:gmatch("(%d+)") do
        _gmRestoreProcessedTs[tonumber(ts)] = true
    end
end

--- 将一个 ts 追加写入本地已处理文件
local function _saveGMRestoreDone(ts)
    -- 最多保留 200 条，超出时清空重写（实际不会有那么多GM指令）
    local existing = {}
    if fileSystem:FileExists(_GM_RESTORE_DONE_FILE) then
        local f = File(_GM_RESTORE_DONE_FILE, FILE_READ)
        if f:IsOpen() then
            local c = f:ReadString()
            f:Close()
            if c then
                for v in c:gmatch("(%d+)") do existing[#existing + 1] = v end
            end
        end
    end
    existing[#existing + 1] = tostring(ts)
    if #existing > 200 then
        -- 裁剪：只保留最新 100 条
        local trimmed = {}
        for i = #existing - 99, #existing do trimmed[#trimmed + 1] = existing[i] end
        existing = trimmed
    end
    local f = File(_GM_RESTORE_DONE_FILE, FILE_WRITE)
    if f:IsOpen() then
        f:WriteString(table.concat(existing, "\n") .. "\n")
        f:Close()
    end
end

--- 检查并执行 GM 下发的存档修复指令（在进入角色选择时调用）
function M.checkAndExecuteGMRestoreCmd()
    if not clientCloud then return end
    if not clientCloud.GetUserID then return end
    local myId = clientCloud:GetUserID()
    if not myId or myId <= 0 then return end
    -- 首次调用时从本地文件加载已处理记录
    _loadGMRestoreDone()

    -- 正确读取：
    --   entry.iscore.gm_restore  → GM 写入的目标 userId（SetInt）
    --   entry.score.gm_restore_cmd → GM 写入的指令参数（Set），通过附加字段获取
    clientCloud:GetRankList("gm_restore", 0, 100, {
        ok = function(list)
            if not list or #list == 0 then return end
            for _, entry in ipairs(list) do
                local iscore = entry.iscore or {}
                local score  = entry.score  or {}
                -- 安全校验：指令必须来自已知 GM 账号，防止普通玩家伪造指令
                local writerId = tostring(entry.userId or "")
                if M.GM_IDS[writerId] and tonumber(iscore.gm_restore) == tonumber(myId) then
                    local data = score.gm_restore_cmd
                    if not data then goto continue end
                    local ts = data.ts or 0
                    -- 已处理过则跳过（内存或文件均已记录）
                    if _gmRestoreProcessedTs[ts] then goto continue end
                    -- 先做内存标记，防止本次会话内重入；
                    -- 文件持久化延迟到写云端成功后执行，失败时撤销内存标记允许下次重试
                    _gmRestoreProcessedTs[ts] = true

                    local slotIdx     = tonumber(data.slot) or 1
                    local backupIndex = tonumber(data.backupIndex) or 1
                    -- 槽位范围校验（1-6）
                    if slotIdx < 1 or slotIdx > 6 then
                        print("[GMRestore] slot 超出范围: " .. slotIdx .. "，跳过")
                        _gmRestoreProcessedTs[ts] = nil  -- 撤销内存标记
                        goto continue
                    end

                    print("[GMRestore] 收到存档修复指令: slot=" .. slotIdx .. " backupIndex=" .. backupIndex .. " ts=" .. ts)

                    -- 根据 backupIndex 找到对应备份 tag
                    local bakMetaKey = "bak_meta"
                    clientScore:Get(bakMetaKey, {
                        ok = function(values)
                            local bakMeta = (values and values[bakMetaKey]) or {}
                            local history = bakMeta[tostring(slotIdx)] or {}
                            if #history == 0 then
                                print("[GMRestore] 槽位" .. slotIdx .. " 无备份记录，跳过")
                                _gmRestoreProcessedTs[ts] = nil  -- 撤销：无备份可用，允许下次重试
                                return
                            end
                            -- backupIndex: 1=最新(末尾), 2=中间, 3=最旧(头部)
                            local tagIdx = #history - (backupIndex - 1)
                            if tagIdx < 1 then tagIdx = 1 end
                            local targetTag = history[tagIdx]
                            if not targetTag then
                                print("[GMRestore] 备份序号" .. backupIndex .. " 超出范围，实际备份数=" .. #history)
                                _gmRestoreProcessedTs[ts] = nil  -- 撤销：数据问题，允许重试
                                return
                            end
                            -- 执行恢复
                            local bakKey = "slot_" .. slotIdx .. "_bak_" .. targetTag
                            clientScore:Get(bakKey, {
                                ok = function(vals)
                                    local bakData = vals and vals[bakKey]
                                    if not bakData then
                                        print("[GMRestore] 备份数据为空 tag=" .. targetTag)
                                        _gmRestoreProcessedTs[ts] = nil  -- 撤销：数据问题，允许重试
                                        return
                                    end
                                    local slotKey = "slot_" .. slotIdx
                                    local batch = clientScore:BatchSet()
                                        :Set(slotKey, bakData)
                                    if M.charSlotMeta and M.charSlotMeta.slots then
                                        -- 同步更新内存中的 meta slot 信息
                                        M.charSlotMeta.slots[tostring(slotIdx)] = M.buildMetaSlotInfo(bakData)
                                        -- 仅当 meta 有效时才写入云端，避免旧格式用户（charSlotMeta=nil）把 meta 覆盖为 nil
                                        batch:Set("meta", M.charSlotMeta)
                                    end
                                    batch:Save("GM存档修复槽位" .. slotIdx, {
                                        ok = function()
                                            -- ✅ 写入成功后才持久化 ts，防止重启后重复执行
                                            _saveGMRestoreDone(ts)
                                            print("[GMRestore] 槽位" .. slotIdx .. " 已从备份 " .. targetTag .. " 恢复（GM指令）")
                                            M.charSelectBanMsg = { text = "您的角色" .. slotIdx .. "存档已由GM修复，请重新进入角色", timer = 8.0 }
                                        end,
                                        error = function(code, reason)
                                            -- ❌ 写入失败：撤销内存标记，下次登录重试
                                            _gmRestoreProcessedTs[ts] = nil
                                            print("[GMRestore] 写入失败（下次登录将重试）:", code, reason)
                                        end,
                                    })
                                end,
                                error = function(code, reason)
                                    _gmRestoreProcessedTs[ts] = nil  -- 撤销：网络失败，允许重试
                                    print("[GMRestore] 读取备份失败:", code, reason)
                                end,
                            })
                        end,
                        error = function(code, reason)
                            _gmRestoreProcessedTs[ts] = nil  -- 撤销：网络失败，允许重试
                            print("[GMRestore] 读取 bak_meta 失败:", code, reason)
                        end,
                    })
                    ::continue::
                end
            end
        end,
        error = function(code, reason)
            print("[GMRestore] 拉取指令队列失败:", code, reason)
        end,
    }, "gm_restore_cmd")  -- 附加字段：同时拉取指令参数
end

--- 保存到云端（多角色版：写入当前槽位 + 更新 meta）
-- ===== 共享仓库序列化/反序列化 =====

--- 序列化共享仓库物品为存档格式
---@return table|nil 共享仓库数据（nil 表示为空且未解锁无需保存）
function M.collectSharedStorageData()
    local items = {}
    local hasAny = false
    for i = 1, M.SHARED_STORAGE_SLOTS do
        local item = M.sharedStorage[i]
        if item then
            hasAny = true

            if item.stackable and item.quantity then
                local d = { id = item.templateId, qty = item.quantity }
                if item.locked then d.locked = true end
                items[tostring(i)] = d
            elseif item.enchantment or (item.enhanceLevel and item.enhanceLevel > 0) or item.locked or item.refineSlots or item.gemSlots or item.tier or item.brittle or item.refineToughness or item.hasRandom or item.abyssAffix or item.gemEffect then
                local d = { id = item.templateId }
                if item.enhanceLevel and item.enhanceLevel > 0 then d.enhLv = item.enhanceLevel end
                if item.enchantment then d.ench = item.enchantment end
                if item.locked then d.locked = true end
                if item.refineSlots then d.refineSlots = item.refineSlots end
                if item.gemSlots then d.gemSlots = item.gemSlots end
                if item.tier then d.tier = item.tier end
                if item.brittle then d.brittle = true end
                if item.refineToughness then d.refineToughness = item.refineToughness end
                if item.hasRandom then
                    local tpl = M.itemTemplates[item.templateId]
                    if tpl and tpl.abyssRandomStats then
                        -- 深渊装备：只存档位索引
                        d.abyssStatTiers = item.abyssStatTiers
                        d.allstatLines = item.allstatLines
                        d.randomResistLines = item.randomResistLines
                        d.randomMainBaseLines = item.randomMainBaseLines
                        d.randomMainExtraLines = item.randomMainExtraLines
                        d.abyssAffixLimitTarget = item.abyssAffixLimitTarget
                        d.templateVersion       = item.templateVersion
                    else
                        -- 旧式随机装备：存完整值
                        d.effects = item.effects
                        d.extraEffects = item.extraEffects
                        d.desc = item.desc
                    end
                end
                if item.abyssAffix then d.abyssAffix = item.abyssAffix end
                if item.gemEffect then d.gemEffect = item.gemEffect end
                items[tostring(i)] = d
            else
                items[tostring(i)] = item.templateId
            end
        end
    end
    -- 如果已解锁（不管有没有物品），都要保存解锁状态到账号级 key，让其他角色也能读到
    if not hasAny and not M.sharedStorageUnlocked then return nil end
    local result = { version = 1, items = items }
    if M.sharedStorageUnlocked then result.unlocked = true end
    return result
end

--- 反序列化共享仓库数据
---@param data table|nil 云端读取的共享仓库数据
function M.applySharedStorageData(data)
    M.sharedStorage = {}
    if not data then return end
    -- 账号中任意角色解锁过共享仓库，则当前角色也视为已解锁
    if data.unlocked then
        M.sharedStorageUnlocked = true
    end
    if not data.items then return end
    local ItemTemplates = require("data.ItemTemplates")
    for k, v in pairs(data.items) do
        local idx = tonumber(k)
        if idx and idx >= 1 and idx <= M.SHARED_STORAGE_SLOTS then
            if type(v) == "string" then
                -- 简单格式：只有 templateId
                local tmpl = ItemTemplates[v]
                if tmpl then

                    M.sharedStorage[idx] = M.createItem(v)
                end
            elseif type(v) == "table" and v.id then
                local tmpl = ItemTemplates[v.id]
                if tmpl then
                    local item = M.createItem(v.id)
                    if v.qty then item.quantity = v.qty end
                    if v.enhLv then item.enhanceLevel = v.enhLv end
                    if v.ench then item.enchantment = v.ench end
                    if v.locked then item.locked = true end
                    if v.refineSlots then item.refineSlots = v.refineSlots end
                    if v.gemSlots then item.gemSlots = v.gemSlots end
                    if v.tier then item.tier = v.tier end
                    if v.brittle then item.brittle = true end
                    if v.refineToughness then item.refineToughness = v.refineToughness end
                    if v.abyssStatTiers and not v.effects then
                        -- 新格式：只有档位索引，从模板重建
                        item.abyssStatTiers = v.abyssStatTiers
                        item.allstatLines = v.allstatLines
                        item.randomResistLines = v.randomResistLines
                        item.randomMainBaseLines = v.randomMainBaseLines
                        item.randomMainExtraLines = v.randomMainExtraLines
                        item.abyssAffixLimitTarget = v.abyssAffixLimitTarget
                        item.templateVersion       = v.templateVersion
                        item.hasRandom = true
                        M.rebuildAbyssStats(item)
                    elseif v.hasRandom or v.effects then
                        -- 旧格式/非深渊随机：完整值覆盖
                        if v.effects then item.effects = v.effects; item.hasRandom = true end
                        if v.extraEffects then item.extraEffects = v.extraEffects end
                        if v.desc then item.desc = v.desc end
                        if v.abyssStatTiers then item.abyssStatTiers = v.abyssStatTiers end
                        if v.allstatLines then item.allstatLines = v.allstatLines end
                    end
                    if v.abyssAffix then item.abyssAffix = v.abyssAffix end
                    if v.gemEffect then item.gemEffect = v.gemEffect end
                    M.sharedStorage[idx] = item
                end
            end
        end
    end
    -- [存档修复] 白板朱莉面纱补救：扫描共享仓库
    local sharedVeilRepaired = false
    for _, item in pairs(M.sharedStorage) do
        if M._repairBlankVeil(item) then sharedVeilRepaired = true end
    end
    if sharedVeilRepaired and M.autoSave then
        M.autoSave.dirty = true
    end
    print("[SharedStorage] 加载完成，共 " .. M.countSharedStorageItems() .. " 个物品")
end

--- 统计共享仓库物品数量
function M.countSharedStorageItems()
    local count = 0
    for i = 1, M.SHARED_STORAGE_SLOTS do
        if M.sharedStorage[i] then count = count + 1 end
    end
    return count
end

--- 检查物品是否可放入共享仓库
---@param item table 物品对象
---@return boolean canStore, string|nil reason
function M.canStoreInSharedStorage(item)
    if not item then return false, "无效物品" end
    if item.category == "任务" then return false, "任务物品不能放入共享仓库" end
    if item.category == "任务物品" then return false, "任务物品不能放入共享仓库" end
    if item.category == "特殊" then return false, "特殊物品不能放入共享仓库" end
    return true, nil
end

--- 构建装备档位后缀字符串，用于共享仓库日志
--- 格式示例：" [3+2134]"、" [3+2134 溅射]"、" [2+113 弹射]"
--- 仅对有 abyssStatTiers 的深渊装备生效；普通装备返回 nil
---@param item table
---@return string|nil
local function buildEquipTierStr(item)
    if not item or not item.slot then return nil end
    -- 只有深渊装备有 abyssStatTiers（1-5档系统）
    if not item.abyssStatTiers then return nil end
    local tpl = item.templateId and M.itemTemplates and M.itemTemplates[item.templateId]
    local abyssRand = tpl and tpl.abyssRandomStats

    -- 第一部分：基础属性档位（1~5）
    -- 来源：abyssRandomStats.effects 的键（掉落武器），或 randomMainBaseLines（兑换装备）
    local baseTier = nil
    -- randomMainBaseLines：兑换装备（火魔女腰带等），values 数组才有档位
    if item.randomMainBaseLines and #item.randomMainBaseLines > 0 then
        baseTier = item.randomMainBaseLines[1].tier  -- 可能为 nil（固定值 randomMainBase）
    end
    -- abyssRandomStats.effects：掉落深渊武器的 atk/mAtk/def 档位
    if not baseTier and abyssRand and abyssRand.effects then
        for k in pairs(abyssRand.effects) do
            local t = item.abyssStatTiers[k]
            if t then baseTier = t; break end
        end
    end

    -- 第二部分：附加属性档位（1~5），按来源顺序收集
    -- 来源1：abyssRandomStats.extraEffects 的键（按模板 key 顺序）
    local extraTiers = {}
    if abyssRand and abyssRand.extraEffects then
        -- 借助 extraEffOrder 排序（若存在），否则按 pairs 顺序
        local order = tpl.extraEffOrder
        local orderedKeys = {}
        for k in pairs(abyssRand.extraEffects) do
            orderedKeys[#orderedKeys + 1] = k
        end
        if order then
            table.sort(orderedKeys, function(a, b)
                return (order[a] or 999) < (order[b] or 999)
            end)
        end
        for _, k in ipairs(orderedKeys) do
            local t = item.abyssStatTiers[k]
            if t then extraTiers[#extraTiers + 1] = t end
        end
    end
    -- 来源2：randomResistLines（多段随机抗性/属性，如火魔女腰带、巴洛英雄戒指）
    if item.randomResistLines then
        for _, line in ipairs(item.randomResistLines) do
            if line.tier then extraTiers[#extraTiers + 1] = line.tier end
        end
    end
    -- 来源3：allstatLines（全属性词缀行）
    if item.allstatLines then
        for _, line in ipairs(item.allstatLines) do
            if line.tier then extraTiers[#extraTiers + 1] = line.tier end
        end
    end
    -- 来源4：randomMainExtraLines（随机主属性词缀）
    if item.randomMainExtraLines then
        for _, line in ipairs(item.randomMainExtraLines) do
            if line.tier then extraTiers[#extraTiers + 1] = line.tier end
        end
    end

    -- 无任何档位信息则跳过（如固定值 randomMainBase 且无额外词缀）
    if not baseTier and #extraTiers == 0 then return nil end

    -- 拼接档位字符串
    local extraStr = ""
    for _, t in ipairs(extraTiers) do extraStr = extraStr .. tostring(t) end
    local tierStr
    if baseTier and extraStr ~= "" then
        tierStr = tostring(baseTier) .. "+" .. extraStr
    elseif baseTier then
        tierStr = tostring(baseTier)
    else
        tierStr = extraStr
    end

    -- 第三部分：深渊词缀名称
    local affixName = item.abyssAffix and item.abyssAffix.name
    -- 第四部分：深渊词缀上限词条（深渊来客戒指等特殊装备）
    local limitName = item.abyssAffixLimitTarget and item.abyssAffixLimitTarget.name

    local extras = {}
    if affixName then extras[#extras + 1] = affixName end
    if limitName then extras[#extras + 1] = limitName end

    if #extras > 0 then
        return " [" .. tierStr .. " " .. table.concat(extras, " ") .. "]"
    else
        return " [" .. tierStr .. "]"
    end
end

--- 从背包放入共享仓库
---@param bagIndex number 背包格位索引
---@param storageIndex number 共享仓库格位索引
---@return boolean success
function M.storeToSharedStorage(bagIndex, storageIndex)
    if not M.sharedStorageUnlocked then
        print("[SharedStorage] 共享仓库未解锁")
        return false
    end
    if storageIndex < 1 or storageIndex > M.SHARED_STORAGE_SLOTS then return false end
    local item = M.inventory[bagIndex]
    if not item then return false end
    local canStore, reason = M.canStoreInSharedStorage(item)
    if not canStore then
        print("[SharedStorage] 无法存入: " .. (reason or ""))
        return false
    end
    -- 目标格位必须为空
    if M.sharedStorage[storageIndex] then
        print("[SharedStorage] 目标格位已被占用")
        return false
    end
    -- 从背包移除，放入共享仓库
    M.inventory[bagIndex] = nil
    M.sharedStorage[storageIndex] = item
    M.autoSave.dirty = true

    print("[SharedStorage] 存入成功: " .. item.name .. " -> 格位" .. storageIndex)
    local logName = item.name .. (buildEquipTierStr(item) or "")
    SSLog.append("存入", logName, item.quantity or 1, M.charName)
    return true
end

--- 批量从背包存入共享仓库（多选模式，自动找空位）
---@param selectedMap table { [bagIdx]=true }
---@return number 成功存入数量
function M.batchStoreToSharedStorage(selectedMap)
    local count = 0
    local indices = {}
    for idx in pairs(selectedMap) do indices[#indices + 1] = idx end
    table.sort(indices)
    for _, bagIdx in ipairs(indices) do
        local item = M.inventory[bagIdx]
        if item then
            local canStore = M.canStoreInSharedStorage(item)
            if canStore then
                -- 找第一个空位
                for si = 1, M.SHARED_STORAGE_SLOTS do
                    if not M.sharedStorage[si] then
                        M.storeToSharedStorage(bagIdx, si)
                        count = count + 1
                        break
                    end
                end
            end
        end
    end
    return count
end

--- 从共享仓库取出到背包
---@param storageIndex number 共享仓库格位索引
---@return boolean success
function M.retrieveFromSharedStorage(storageIndex)
    if storageIndex < 1 or storageIndex > M.SHARED_STORAGE_SLOTS then return false end
    local item = M.sharedStorage[storageIndex]
    if not item then return false end
    -- 找到背包空位
    local emptySlot = nil
    for i = 1, M.bagSlots do
        if not M.inventory[i] then
            emptySlot = i
            break
        end
    end
    if not emptySlot then
        print("[SharedStorage] 背包已满")
        return false
    end
    -- 从共享仓库移除，放入背包
    M.sharedStorage[storageIndex] = nil
    M.inventory[emptySlot] = item
    M.autoSave.dirty = true
    print("[SharedStorage] 取出成功: " .. item.name .. " -> 背包格位" .. emptySlot)
    local logName = item.name .. (buildEquipTierStr(item) or "")
    SSLog.append("取出", logName, item.quantity or 1, M.charName)
    return true
end

--- ⚠️ 调用前提：charSlotIndex 必须有效，且内存中的游戏数据是完整的。
--- 禁止在以下时机调用：
---   - loadSlotFromCloud 的异步等待期间（数据已归零，charSlotIndex 为 nil）
---   - initGame() 刚执行完、applySaveData 尚未恢复数据时
---   - gameState 为 STATE_CHAR_SELECT / STATE_MENU 时
---@param callbacks? { ok?: function, error?: fun(reason: string) } 可选回调
function M.saveToCloud(callbacks)
    if not M.charSlotIndex then
        print("=== 无活跃槽位，跳过保存 ===")
        if callbacks and callbacks.error then callbacks.error("无活跃槽位") end
        return
    end
    -- 从后台恢复后会话检查尚未完成，阻断本次保存，避免用过期数据覆盖云端
    if M.resumeCheckPending then
        print("=== resumeCheckPending 期间跳过存档（等待会话校验） ===")
        return
    end

    -- 并发保护：若当前已有 HTTP 请求在途，将本次请求缓存为"最新待保存"，当前请求完成后自动触发
    -- 用"覆盖"而非"排队"：只保留最新一次，避免因多次覆盖堆积过多请求
    -- 同时捕获当前 charSlotIndex：角色切换时 charSlotIndex 会在 saveToCloud 返回后被同步清空，
    -- 但 initGame() 尚未调用，内存数据仍属于该槽位，flush 时需临时恢复才能正确写入
    if M.cloudSaveStatus == "saving" then
        print("=== saveToCloud 并发保护：当前保存进行中，缓存最新请求 ===")
        M._pendingSaveCallbacks = { cb = callbacks, slotIdx = M.charSlotIndex }
        return
    end

    M.cloudSaveStatus = "saving"
    M.cloudSaveTimer = 3
    local saveData = M.collectSaveData()
    local slotKey = "slot_" .. M.charSlotIndex

    -- 更新 meta 中该槽位的概要
    if M.charSlotMeta and M.charSlotMeta.slots then
        M.charSlotMeta.slots[tostring(M.charSlotIndex)] = M.buildMetaSlotInfo(saveData)
        M.charSlotMeta.activeSlot = M.charSlotIndex
    end

    -- 缓存 slotIdx 和 saveData 供回调使用
    local curSlotIdx = M.charSlotIndex

    -- 序列化共享仓库数据
    local sharedStorageData = M.collectSharedStorageData()

    local batch = clientScore:BatchSet()
        :Set(slotKey, saveData)
    -- 仅当 meta 有效时才写入，避免旧格式用户（charSlotMeta=nil）把云端 meta 覆盖为 nil
    if M.charSlotMeta then
        batch:Set("meta", M.charSlotMeta)
    end
    if sharedStorageData then
        batch:Set("shared_storage", sharedStorageData)
    end

    -- 内部：当前 HTTP 完成后，若有待保存请求则触发之
    local function _flushPendingSave()
        local pending = M._pendingSaveCallbacks
        if pending ~= nil then
            M._pendingSaveCallbacks = nil
            -- 角色切换场景：charSlotIndex 已被清空，但 initGame() 尚未调用，
            -- 内存数据仍属于排队时捕获的槽位，临时恢复以确保保存到正确 key
            local needRestore = (M.charSlotIndex == nil and pending.slotIdx ~= nil)
            if needRestore then
                M.charSlotIndex = pending.slotIdx
            end
            print("=== saveToCloud 触发缓存的待保存请求 (槽位" .. tostring(pending.slotIdx) .. ") ===")
            M.saveToCloud(pending.cb)
            -- saveToCloud 已同步捕获 charSlotIndex（local curSlotIdx），立即还原 nil 维持安全保障
            if needRestore then
                M.charSlotIndex = nil
            end
        end
    end

    local saveEvents = {
        ok = function()
            M.cloudSaveStatus = "saved"
            M.cloudSaveTimer = 3
            -- 同步更新共享仓库缓存，防止 createNewCharacter 使用过时数据
            if sharedStorageData then
                M.cachedSharedStorageData = sharedStorageData
            end
            print("=== 云存档保存成功 (槽位" .. curSlotIdx .. ") ===")
            -- 正常存档成功后，尝试每日备份
            M._tryDailyBackup(curSlotIdx, saveData)
            if callbacks and callbacks.ok then callbacks.ok() end
            _flushPendingSave()
        end,
        error = function(code, reason)
            M.cloudSaveStatus = "error"
            M.cloudSaveTimer = 3
            print("=== 云存档保存失败: " .. tostring(reason) .. " ===")
            if callbacks and callbacks.error then callbacks.error(tostring(reason)) end
            _flushPendingSave()
        end,
    }
    -- 透传 timeout 回调（调用方可选提供）
    if callbacks and callbacks.timeout then
        saveEvents.timeout = function()
            M.cloudSaveStatus = "error"
            M.cloudSaveTimer = 3
            print("=== 云存档保存超时 (槽位" .. curSlotIdx .. ") ===")
            callbacks.timeout()
            _flushPendingSave()
        end
    else
        -- 即使调用方未提供 timeout 回调，也需确保 pending 被 flush
        saveEvents.timeout = function()
            M.cloudSaveStatus = "error"
            M.cloudSaveTimer = 3
            print("=== 云存档保存超时 (槽位" .. curSlotIdx .. ") ===")
            _flushPendingSave()
        end
    end
    batch:Save("存档槽位" .. M.charSlotIndex, saveEvents)
end

-- ===== 自动存档系统 =====
M.autoSave = {
    enabled = false,         -- 进入游戏后才启用
    dirty = false,           -- 是否有未保存的变化
    cooldown = 0,            -- 发现变化后的等待倒计时（秒）
    minInterval = 5,         -- 两次存档最小间隔（秒）
    delaySec = 3,            -- 发现变化后延迟几秒再存（合并短时间内多次变化）
    lastSaveTime = 0,        -- 上次存档时间戳
    -- 快照：上次存档时的值
    snapshot = {
        gold = 0,
        exp = 0,
        hp = 0,
        mp = 0,
        statPoints = 0,
        skillPoints = 0,
        invFingerprint = "",
    },
}

--- 生成背包指纹字符串
function M.getInventoryFingerprint()
    local parts = {}
    for i = 1, M.bagSlots do
        local item = M.inventory[i]
        if item then
            parts[#parts + 1] = i .. ":" .. (item.templateId or "?") .. ":" .. (item.quantity or 1)
        end
    end
    return table.concat(parts, ",")
end

--- 生成仓库指纹字符串（覆盖所有储物箱）
function M.getWarehouseFingerprint()
    local parts = {}
    for wid = 1, M.WAREHOUSE_COUNT do
        local wh = M.warehouses[wid] or {}
        for i = 1, M.warehouseSlots do
            local item = wh[i]
            if item then
                parts[#parts + 1] = wid .. "_" .. i .. ":" .. item.templateId .. ":" .. (item.quantity or 1)
            end
        end
    end
    return table.concat(parts, ",")
end

--- 生成共享仓库指纹字符串
function M.getSharedStorageFingerprint()
    local parts = {}
    for i = 1, M.SHARED_STORAGE_SLOTS do
        local item = M.sharedStorage and M.sharedStorage[i]
        if item then
            local seg = i .. ":" .. item.templateId .. ":" .. (item.quantity or 1)
            -- 纳入深渊词缀变化（如朱莉面纱重铸后词缀改变）
            if item.abyssAffix then
                seg = seg .. ":ax=" .. (item.abyssAffix.id or "")
            end
            -- 纳入实例级 gemEffect 变化（如朱莉面纱随机主属性）
            if item.gemEffect then
                local gkeys = {}
                for k, v in pairs(item.gemEffect) do
                    gkeys[#gkeys + 1] = k .. "=" .. tostring(v)
                end
                table.sort(gkeys)
                seg = seg .. ":ge=" .. table.concat(gkeys, ";")
            end
            -- 纳入已镶嵌宝石槽的词缀变化（装备内含面纱时）
            if item.gemSlots then
                for si, slot in ipairs(item.gemSlots) do
                    if slot.gemId then
                        local sseg = "gs" .. si .. "=" .. slot.gemId
                        if slot.abyssAffix then sseg = sseg .. ":ax=" .. (slot.abyssAffix.id or "") end
                        seg = seg .. ":" .. sseg
                    end
                end
            end
            parts[#parts + 1] = seg
        end
    end
    return table.concat(parts, ",")
end

--- 生成失物招领指纹字符串
function M.getLostItemsFingerprint()
    local parts = {}
    for i = 1, M.LOST_ITEMS_MAX do
        local item = M.lostItems and M.lostItems[i]
        if item then
            parts[#parts + 1] = i .. ":" .. item.templateId .. ":" .. (item.quantity or 1)
        end
    end
    return table.concat(parts, ",")
end

--- 用当前值更新快照
function M.updateAutoSaveSnapshot()
    local s = M.autoSave.snapshot
    local p = M.player
    if not p then return end
    s.gold = M.gold or 0
    s.exp = p.exp or 0
    s.hp = p.hp or 0
    s.mp = p.mp or 0
    s.statPoints = p.statPoints or 0
    s.skillPoints = M.skillPoints or 0
    s.invFingerprint = M.getInventoryFingerprint()
    s.whFingerprint = M.getWarehouseFingerprint()
    s.sharedStorageFP = M.getSharedStorageFingerprint()
    s.lostItemsFP = M.getLostItemsFingerprint()
    -- stageKillCounts 指纹：所有击杀数之和
    local skTotal = 0
    for _, v in pairs(M.stageKillCounts or {}) do skTotal = skTotal + v end
    s.stageKillTotal = skTotal
    -- stageClearedOnce 指纹：已清空的关卡数
    local scCount = 0
    for _ in pairs(M.stageClearedOnce or {}) do scCount = scCount + 1 end
    s.stageClearedCount = scCount
    -- knownNPCs 指纹：拼接所有已知 NPC ID（排序保证稳定）
    s.knownNPCFP = M._buildKeyFingerprint(M.knownNPCs)
    -- talkQAAsked 指纹
    s.talkQAAskedFP = M._buildKeyFingerprint(M.talkQAAsked)
    -- dialogueFlags 指纹：拼接所有已触发标记
    s.dialogueFlagFP = M._buildKeyFingerprint(M.dialogueFlags)
    -- dungeonsCleared 指纹：拼接所有已通关副本 ID
    s.dungeonsClearedFP = M._buildKeyFingerprint(M.dungeonsCleared)
    -- eventCompleted 指纹：拼接所有已完成事件 ID
    s.eventCompletedFP = M._buildKeyFingerprint(M.eventCompleted)
    -- npcTalkedRecord 指纹
    s.npcTalkedFP = M._buildKeyFingerprint(M.npcTalkedRecord)
    -- npcAffinity 指纹（key=value，检测好感度数值变化）
    s.npcAffinityFP = M._buildKVFingerprint(M.npcAffinity)
    -- 深渊积分
    s.abyssPoints = M.abyssPoints or 0
end

--- 检测当前值是否与快照不同
function M.checkAutoSaveDirty()
    local s = M.autoSave.snapshot
    local p = M.player
    if not p then return false end
    if (M.gold or 0) ~= s.gold then return true end
    if (p.exp or 0) ~= s.exp then return true end
    if (p.hp or 0) ~= s.hp then return true end
    if (p.mp or 0) ~= s.mp then return true end
    if (p.statPoints or 0) ~= s.statPoints then return true end
    if (M.skillPoints or 0) ~= s.skillPoints then return true end
    if M.getInventoryFingerprint() ~= s.invFingerprint then return true end
    if M.getWarehouseFingerprint() ~= (s.whFingerprint or "") then return true end
    if M.getSharedStorageFingerprint() ~= (s.sharedStorageFP or "") then return true end
    if M.getLostItemsFingerprint() ~= (s.lostItemsFP or "") then return true end
    -- stageKillCounts 变化检测
    local skTotal = 0
    for _, v in pairs(M.stageKillCounts or {}) do skTotal = skTotal + v end
    if skTotal ~= (s.stageKillTotal or 0) then return true end
    -- stageClearedOnce 变化检测
    local scCount = 0
    for _ in pairs(M.stageClearedOnce or {}) do scCount = scCount + 1 end
    if scCount ~= (s.stageClearedCount or 0) then return true end
    -- knownNPCs 变化检测
    if M._buildKeyFingerprint(M.knownNPCs) ~= (s.knownNPCFP or "") then return true end
    -- talkQAAsked 变化检测
    if M._buildKeyFingerprint(M.talkQAAsked) ~= (s.talkQAAskedFP or "") then return true end
    -- dialogueFlags 变化检测
    if M._buildKeyFingerprint(M.dialogueFlags) ~= (s.dialogueFlagFP or "") then return true end
    -- dungeonsCleared 变化检测
    if M._buildKeyFingerprint(M.dungeonsCleared) ~= (s.dungeonsClearedFP or "") then return true end
    -- eventCompleted 变化检测
    if M._buildKeyFingerprint(M.eventCompleted) ~= (s.eventCompletedFP or "") then return true end
    -- npcTalkedRecord 变化检测
    if M._buildKeyFingerprint(M.npcTalkedRecord) ~= (s.npcTalkedFP or "") then return true end
    -- npcAffinity 变化检测（好感度数值变化）
    if M._buildKVFingerprint(M.npcAffinity) ~= (s.npcAffinityFP or "") then return true end
    -- 深渊积分变化检测
    if (M.abyssPoints or 0) ~= (s.abyssPoints or 0) then return true end
    return false
end

-- (天气系统函数保留在 GameState.lua 主文件中)

--- [修复] 处理因角色切换保存未完成而延迟的槽位加载
--- 在主循环中每帧调用，检查保存是否完成、是否超时
function M.tickPendingLoadSlot(dt)
    local pending = M._pendingLoadSlot
    if not pending then return end

    pending.waitTimer = pending.waitTimer + dt

    -- 保存完成或超时：执行加载
    if not M.charSwitchSaving or pending.waitTimer >= pending.maxWait then
        if pending.waitTimer >= pending.maxWait then
            print("[LoadSlot] 等待保存超时(" .. pending.maxWait .. "s)，强制加载")
            M.charSwitchSaving = false
        else
            print("[LoadSlot] 保存已完成，继续加载槽位 " .. pending.slotIdx)
        end
        local slotIdx = pending.slotIdx
        local callback = pending.callback
        M._pendingLoadSlot = nil
        M.loadSlotFromCloud(slotIdx, callback)
    end
end

function M.tickAutoSave(dt)
    local as = M.autoSave
    if not as.enabled then return end
    if M.gameState == M.STATE_MENU or M.gameState == M.STATE_GAMEOVER
       or M.gameState == M.STATE_CHAR_SELECT or M.gameState == M.STATE_CHAR_CREATE then return end
    if M.cloudSaveStatus == "saving" then return end

    -- 检测变化
    if not as.dirty then
        if M.checkAutoSaveDirty() then
            as.dirty = true
            as.cooldown = as.delaySec
        end
    else
        -- 已经脏了，倒计时
        as.cooldown = as.cooldown - dt
        -- 如果在倒计时期间又有新变化，重置倒计时（合并连续变化）
        if M.checkAutoSaveDirty() then
            -- 值仍在变化中（比如连续战斗），保持等待
        end
        if as.cooldown <= 0 then
            local now = GetTime():GetElapsedTime()
            if now - as.lastSaveTime >= as.minInterval then
                as.lastSaveTime = now
                M.saveToCloud({
                    ok = function()
                        M.updateAutoSaveSnapshot()
                        as.dirty = false
                    end,
                    error = function()
                        -- HTTP 失败：保持 dirty=true，下次 tick 自动重试
                        print("[AutoSave] 存档失败，下次 tick 重试")
                    end,
                    timeout = function()
                        print("[AutoSave] 存档超时，下次 tick 重试")
                    end,
                })
            else
                -- 距上次存档太近，再等一下
                as.cooldown = as.minInterval - (now - as.lastSaveTime)
            end
        end
    end
end

--- 立即触发一次存档（离开建筑等关键节点调用）
--- 不依赖脏检测，无条件保存（关键节点的数据完整性优先）
function M.triggerAutoSave()
    local as = M.autoSave
    if not as.enabled then return end
    if M.cloudSaveStatus == "saving" then return end
    if M.gameState == M.STATE_MENU or M.gameState == M.STATE_GAMEOVER
       or M.gameState == M.STATE_CHAR_SELECT or M.gameState == M.STATE_CHAR_CREATE then return end
    local now = GetTime():GetElapsedTime()
    if now - as.lastSaveTime < as.minInterval then return end
    as.lastSaveTime = now
    M.saveToCloud({
        ok = function()
            M.updateAutoSaveSnapshot()
            as.dirty = false
        end,
        error = function()
            print("[TriggerAutoSave] 存档失败，下次 tick 重试")
        end,
        timeout = function()
            print("[TriggerAutoSave] 存档超时，下次 tick 重试")
        end,
    })
end

--- 预加载云存档（多角色版：读取 meta + 旧 save_data 用于迁移判断）
M.cachedSaveData = nil       -- 缓存的存档数据（兼容旧流程）
M.preloadStatus = ""         -- "", "loading", "ready", "none", "error"

function M.preloadCloudSave()
    M.preloadStatus = "loading"
    clientScore:BatchGet()
        :Key("meta")
        :Key("save_data")
        :Key("shared_storage")
        :Fetch({
            ok = function(values, iscores)
                -- 缓存共享仓库数据（供 loadSlotFromCloud 使用时已有）
                if values and values["shared_storage"] then
                    M.cachedSharedStorageData = values["shared_storage"]
                end
                if values and values.meta and values.meta.version then
                    -- 新格式：已有 meta
                    M.charSlotMeta = values.meta
                    M.cachedLegacySaveData = nil
                    M.preloadStatus = "ready"
                    print("=== 云存档预加载成功 (多角色 v" .. tostring(values.meta.version) .. ") ===")
                elseif values and values.save_data then
                    -- 旧格式：有 save_data 但无 meta，需要迁移
                    M.charSlotMeta = nil
                    M.cachedLegacySaveData = values.save_data
                    M.preloadStatus = "ready"
                    print("=== 检测到旧存档，等待迁移 ===")
                else
                    -- 全新用户：无任何存档
                    M.charSlotMeta = {
                        version = 2,
                        activeSlot = nil,
                        slots = {},
                    }
                    M.cachedLegacySaveData = nil
                    M.preloadStatus = "none"
                    print("=== 无云存档（新用户） ===")
                end
                -- 检查是否有 GM 下发的存档修复指令
                M.checkAndExecuteGMRestoreCmd()
            end,
            error = function(code, reason)
                M.cachedSaveData = nil
                M.charSlotMeta = nil
                M.preloadStatus = "error"
                print("=== 云存档预加载失败: " .. tostring(reason) .. " ===")
            end,
        })
end

--- 迁移旧存档到多角色格式（旧 save_data → slot_1 + meta）
function M.migrateLegacySave(callback)
    local legacyData = M.cachedLegacySaveData
    if not legacyData then
        if callback then callback(false, "无旧存档数据") end
        return
    end
    print("=== 开始迁移旧存档到槽位1 ===")
    -- 构建 meta
    local meta = {
        version = 2,
        activeSlot = 1,
        slots = {
            ["1"] = M.buildMetaSlotInfo(legacyData),
        },
    }
    -- 如果旧存档没有 name，赋予默认名
    if not legacyData.name or legacyData.name == "" then
        legacyData.name = "无名"
    end
    meta.slots["1"].name = legacyData.name

    -- 原子操作：写入 meta + slot_1 + 删除旧 save_data
    clientScore:BatchSet()
        :Set("meta", meta)
        :Set("slot_1", legacyData)
        :Delete("save_data")
        :Save("迁移旧存档", {
            ok = function()
                M.charSlotMeta = meta
                M.charSlotIndex = 1
                M.cachedLegacySaveData = nil
                print("=== 旧存档迁移成功 ===")
                if callback then callback(true) end
            end,
            error = function(code, reason)
                print("=== 旧存档迁移失败: " .. tostring(reason) .. " ===")
                if callback then callback(false, reason) end
            end,
        })
end

--- 从云端读取指定槽位
function M.loadSlotFromCloud(slotIdx, callback)
    -- [修复] 如果角色切换保存尚未完成（网络波动），延迟到保存完成再加载，
    -- 防止 BatchGet 读到旧的 shared_storage 数据导致共享仓库物品词缀/属性丢失
    if M.charSwitchSaving then
        print("[LoadSlot] 角色切换保存尚未完成，等待保存结束后再加载...")
        M._pendingLoadSlot = { slotIdx = slotIdx, callback = callback, waitTimer = 0, maxWait = 10 }
        return
    end

    -- 先清空旧角色的内存状态，防止加载失败时残留上一个角色的数据
    M.initGame()
    -- ⚠️ 危险区间开始：从这里到异步回调 applySaveData 之前，内存中所有持久化数据都是归零状态。
    -- 此期间绝对不能调用 saveToCloud()，否则会把空数据写入云端导致清档。
    -- 当前的安全保障：
    --   1. initGame() 已将 autoSave.enabled 设为 false
    --   2. gameState 仍为 STATE_CHAR_SELECT，tickAutoSave/triggerAutoSave 会直接返回
    --   3. charSlotIndex 在下方被置 nil，saveToCloud 第一行会拦截
    M.charSlotIndex = nil
    M.cloudSaveStatus = "loading"
    M.cloudSaveTimer = 3
    local slotKey = "slot_" .. slotIdx
    clientScore:BatchGet()
        :Key(slotKey)
        :Key("shared_storage")
        :Fetch({
        ok = function(values, iscores)
            if values and values[slotKey] then
                local ok = M.applySaveData(values[slotKey])
                if ok then
                    M.charSlotIndex = slotIdx
                    -- 加载共享仓库数据并同步缓存
                    M.cachedSharedStorageData = values["shared_storage"]
                    M.applySharedStorageData(values["shared_storage"])
                    -- 槽位已确定，刷新每日委托（确保每个角色独立）
                    local BulletinBoard = require("BulletinBoard")
                    BulletinBoard.ensureReady()
                    M.cloudSaveStatus = "loaded"
                    M.cloudSaveTimer = 3
                    print("=== 槽位" .. slotIdx .. "读取成功 ===")
                else
                    M.cloudSaveStatus = "error"
                    M.cloudSaveTimer = 3
                end
            else
                M.cloudSaveStatus = "error"
                M.cloudSaveTimer = 3
                print("=== 槽位" .. slotIdx .. "无数据 ===")
            end
            if callback then callback() end
        end,
        error = function(code, reason)
            M.cloudSaveStatus = "error"
            M.cloudSaveTimer = 3
            print("=== 槽位" .. slotIdx .. "读取失败: " .. tostring(reason) .. " ===")
            if callback then callback() end
        end,
    })
end

--- 从云端读取（兼容旧接口，现在加载当前活跃槽位）
function M.loadFromCloud(callback)
    local slotIdx = M.charSlotIndex or (M.charSlotMeta and M.charSlotMeta.activeSlot) or 1
    M.loadSlotFromCloud(slotIdx, callback)
end

--- 创建新角色并保存到云端
function M.createNewCharacter(slotIdx, charName, classId, callback)
    -- 初始化游戏状态为该职业的初始状态
    local classDef = M.PLAYER_DEFS[classId]
    if not classDef then
        if callback then callback(false, "无效职业") end
        return
    end

    -- 防御性保存：如果当前有已加载的不同槽位，先保存其内存数据防止丢失
    -- （返回角色选择时的 saveToCloud 可能因网络等原因未完成）
    if M.charSlotIndex and M.charSlotIndex ~= slotIdx then
        M.saveToCloud()
    end

    M.charName = charName or ""
    M.charSlotIndex = slotIdx
    -- 在 initGame 清空前，先从当前内存捕获最新共享仓库状态
    -- （cachedSharedStorageData 仅在登录时预加载，玩家游戏期间的修改不会更新它，直接用会导致数据回滚）
    local preservedSharedData = M.collectSharedStorageData() or M.cachedSharedStorageData
    M.initGame()
    -- 恢复共享仓库数据（防止后续自动存档把空数据覆盖到云端）
    if preservedSharedData then
        M.applySharedStorageData(preservedSharedData)
    end
    -- 设置新角色的职业
    M.currentClass = classId
    M.confirmedClass = classId  -- 与 currentClass 同步，changeClass 不会修改此字段
    M.PLAYER_DEF = M.PLAYER_DEFS[classId]
    M.SKILL_TREE_LAYOUT = M.CLASS_SKILL_TREE_LAYOUTS[classId]
    if M.player then
        M.player.name = M.PLAYER_DEF.name
        M.player.color = M.PLAYER_DEF.color
    end
    -- 新角色：重置委托状态后生成新委托
    local BulletinBoard = require("BulletinBoard")
    BulletinBoard.reset()
    BulletinBoard.ensureReady()

    -- 收集初始存档
    local saveData = M.collectSaveData()
    local slotKey = "slot_" .. slotIdx

    -- 更新 meta
    if not M.charSlotMeta then
        M.charSlotMeta = { version = 2, activeSlot = slotIdx, slots = {} }
    end
    M.charSlotMeta.slots[tostring(slotIdx)] = M.buildMetaSlotInfo(saveData)
    M.charSlotMeta.activeSlot = slotIdx

    clientScore:BatchSet()
        :Set(slotKey, saveData)
        :Set("meta", M.charSlotMeta)
        :Save("创建角色槽位" .. slotIdx, {
            ok = function()
                print("=== 角色创建成功 (槽位" .. slotIdx .. ": " .. charName .. ") ===")
                if callback then callback(true) end
            end,
            error = function(code, reason)
                print("=== 角色创建失败: " .. tostring(reason) .. " ===")
                if callback then callback(false, reason) end
            end,
        })
end

--- 删除角色槽位
function M.deleteCharacterSlot(slotIdx, callback)
    local slotKey = "slot_" .. slotIdx
    if not M.charSlotMeta or not M.charSlotMeta.slots then
        if callback then callback(false, "无 meta 数据") end
        return
    end

    -- 先保存旧值，失败时可回滚（防止内存-云端不一致导致玩家误认为槽位已空后新建角色覆盖旧存档）
    local oldSlotInfo   = M.charSlotMeta.slots[tostring(slotIdx)]
    local oldActiveSlot = M.charSlotMeta.activeSlot

    -- 从 meta 中移除该槽位
    M.charSlotMeta.slots[tostring(slotIdx)] = nil

    -- 如果删除的是当前活跃槽位，清除 activeSlot
    if M.charSlotMeta.activeSlot == slotIdx then
        M.charSlotMeta.activeSlot = nil
    end

    clientScore:BatchSet()
        :Delete(slotKey)
        :Set("meta", M.charSlotMeta)
        :Save("删除角色槽位" .. slotIdx, {
            ok = function()
                print("=== 角色槽位" .. slotIdx .. "删除成功 ===")
                if callback then callback(true) end
            end,
            error = function(code, reason)
                -- 写入失败：回滚内存 meta，保持内存与云端一致
                M.charSlotMeta.slots[tostring(slotIdx)] = oldSlotInfo
                M.charSlotMeta.activeSlot = oldActiveSlot
                print("=== 角色槽位" .. slotIdx .. "删除失败，已回滚内存: " .. tostring(reason) .. " ===")
                if callback then callback(false, reason) end
            end,
        })
end

--- 生成随机角色名
function M.generateCharName()
    local prefixes = {
        "银月", "星辰", "暗影", "赤焰", "苍穹",
        "碧落", "玄冰", "紫电", "金风", "翠云",
        "烈焰", "霜华", "雷鸣", "清风", "铁血",
        "孤峰", "幽兰", "天罡", "地煞", "龙吟",
    }
    local suffixes = {
        "剑客", "行者", "游侠", "猎手", "术士",
        "守卫", "斗士", "隐者", "先知", "勇者",
        "旅人", "浪客", "骑士", "猛将", "智者",
        "刺客", "弓手", "战神", "贤者", "修罗",
    }
    return prefixes[math.random(#prefixes)] .. suffixes[math.random(#suffixes)]
end

--- 获取某个槽位的概要信息（从 meta 中读取）
function M.getSlotInfo(slotIdx)
    if not M.charSlotMeta or not M.charSlotMeta.slots then return nil end
    return M.charSlotMeta.slots[tostring(slotIdx)]
end

--- 获取已占用的槽位数量
function M.getUsedSlotCount()
    if not M.charSlotMeta or not M.charSlotMeta.slots then return 0 end
    local count = 0
    for _ in pairs(M.charSlotMeta.slots) do
        count = count + 1
    end
    return count
end

--- 保存音量到云端
function M.saveVolumeToCloud()
    clientScore:Set("master_volume", M.masterVolume, {
        ok = function()
            print("=== 音量保存成功: " .. M.masterVolume .. " ===")
        end,
        error = function(code, reason)
            print("=== 音量保存失败: " .. tostring(reason) .. " ===")
        end,
    })
end

--- 从云端读取音量（游戏启动时调用）
function M.loadVolumeFromCloud()
    clientScore:Get("master_volume", {
        ok = function(values)
            if values and values.master_volume then
                M.masterVolume = tonumber(values.master_volume) or 0.5
                print("=== 音量读取成功: " .. M.masterVolume .. " ===")
            end
        end,
        error = function(code, reason)
            print("=== 音量读取失败，使用默认值: " .. tostring(reason) .. " ===")
        end,
    })
end

--- 保存动画开关到云端
function M.saveAnimationToggleToCloud()
    local val = M.animationEnabled and 1 or 0
    clientScore:Set("animation_enabled", val, {
        ok = function()
            print("=== 动画开关保存成功: " .. val .. " ===")
        end,
        error = function(code, reason)
            print("=== 动画开关保存失败: " .. tostring(reason) .. " ===")
        end,
    })
end

--- 从云端读取动画开关（游戏启动时调用）
function M.loadAnimationToggleFromCloud()
    clientScore:Get("animation_enabled", {
        ok = function(values)
            if values and values.animation_enabled ~= nil then
                M.animationEnabled = (tonumber(values.animation_enabled) or 1) == 1
                print("=== 动画开关读取成功: " .. tostring(M.animationEnabled) .. " ===")
            end
        end,
        error = function(code, reason)
            print("=== 动画开关读取失败，使用默认值: " .. tostring(reason) .. " ===")
        end,
    })
end

-- ====================================================================
-- 伤害飘字 & 屏幕震动开关
-- ====================================================================

function M.saveDamageNumbersToggleToCloud()
    local val = M.showDamageNumbers and 1 or 0
    clientScore:Set("show_damage_numbers", val, {
        ok = function()
            print("=== 伤害飘字开关保存成功: " .. val .. " ===")
        end,
        error = function(code, reason)
            print("=== 伤害飘字开关保存失败: " .. tostring(reason) .. " ===")
        end,
    })
end

function M.saveScreenShakeToggleToCloud()
    local val = M.enableScreenShake and 1 or 0
    clientScore:Set("enable_screen_shake", val, {
        ok = function()
            print("=== 屏幕震动开关保存成功: " .. val .. " ===")
        end,
        error = function(code, reason)
            print("=== 屏幕震动开关保存失败: " .. tostring(reason) .. " ===")
        end,
    })
end

function M.loadDisplayTogglesFromCloud()
    clientScore:Get("show_damage_numbers", {
        ok = function(values)
            if values and values.show_damage_numbers ~= nil then
                M.showDamageNumbers = (tonumber(values.show_damage_numbers) or 1) == 1
                print("=== 伤害飘字开关读取成功: " .. tostring(M.showDamageNumbers) .. " ===")
            end
        end,
        error = function(code, reason)
            print("=== 伤害飘字开关读取失败，使用默认值: " .. tostring(reason) .. " ===")
        end,
    })
    clientScore:Get("enable_screen_shake", {
        ok = function(values)
            if values and values.enable_screen_shake ~= nil then
                M.enableScreenShake = (tonumber(values.enable_screen_shake) or 1) == 1
                print("=== 屏幕震动开关读取成功: " .. tostring(M.enableScreenShake) .. " ===")
            end
        end,
        error = function(code, reason)
            print("=== 屏幕震动开关读取失败，使用默认值: " .. tostring(reason) .. " ===")
        end,
    })
end

-- ====================================================================
-- 横竖屏方向控制
-- ====================================================================

--- 应用屏幕方向设置
function M.applyScreenOrientation()
    local g = GetGraphics()
    if g and g.SetOrientations then
        if M.forceLandscape then
            g:SetOrientations("LandscapeLeft LandscapeRight")
        else
            g:SetOrientations("Portrait PortraitUpsideDown")
        end
    end
end

--- 解锁屏幕方向（允许所有方向，启动时调用以覆盖平台锁定）
function M.unlockScreenOrientation()
    local g = GetGraphics()
    if g and g.SetOrientations then
        g:SetOrientations("LandscapeLeft LandscapeRight Portrait PortraitUpsideDown")
    end
end

--- 保存横竖屏偏好到云端
function M.saveOrientationToCloud()
    local val = M.forceLandscape and 1 or 0
    clientScore:Set("force_landscape", val, {
        ok = function()
            print("=== 横竖屏偏好保存成功: " .. val .. " ===")
        end,
        error = function(code, reason)
            print("=== 横竖屏偏好保存失败: " .. tostring(reason) .. " ===")
        end,
    })
end

--- 从云端读取横竖屏偏好（游戏启动时调用）
function M.loadOrientationFromCloud()
    -- 先检查是否需要一次性强制竖屏重置
    clientScore:Get("orient_reset_v2", {
        ok = function(rstValues)
            local alreadyReset = rstValues and (tonumber(rstValues.orient_reset_v2) or 0) == 1
            if not alreadyReset then
                -- ── 首次重置：强制竖屏，保存偏好 + 写入重置标记 ──
                M.forceLandscape = false
                M.applyScreenOrientation()
                M.saveOrientationToCloud()                 -- 保存 force_landscape=0
                clientScore:Set("orient_reset_v2", 1, {
                    ok    = function() print("=== 一次性竖屏重置标记已保存 ===") end,
                    error = function(c, r) print("=== 重置标记保存失败: " .. tostring(r) .. " ===") end,
                })
                print("=== 一次性强制竖屏重置已执行 ===")
            else
                -- ── 已重置过：正常读取用户偏好 ──
                clientScore:Get("force_landscape", {
                    ok = function(values)
                        if values and values.force_landscape ~= nil then
                            M.forceLandscape = (tonumber(values.force_landscape) or 0) == 1
                            M.applyScreenOrientation()
                            print("=== 横竖屏偏好读取成功: " .. tostring(M.forceLandscape) .. " ===")
                        end
                    end,
                    error = function(code, reason)
                        print("=== 横竖屏偏好读取失败，使用默认值: " .. tostring(reason) .. " ===")
                    end,
                })
            end
        end,
        error = function(code, reason)
            -- 读取重置标记失败，降级为正常加载偏好
            print("=== 重置标记读取失败，正常加载偏好: " .. tostring(reason) .. " ===")
            clientScore:Get("force_landscape", {
                ok = function(values)
                    if values and values.force_landscape ~= nil then
                        M.forceLandscape = (tonumber(values.force_landscape) or 0) == 1
                        M.applyScreenOrientation()
                    end
                end,
                error = function(c, r)
                    print("=== 横竖屏偏好也读取失败: " .. tostring(r) .. " ===")
                end,
            })
        end,
    })
end

--- 从云端读取免广告权益（游戏启动时调用）
--- 兑换码 vipisvip 通过 clientCloud 写入 redeem_vipisvip=1
--- 这里异步检查，如果该账号已兑换则设置 abyssFakeAd=true
function M.loadAdFreeFromCloud()
    if not clientCloud then return end
    -- 读取深渊假广告权益（vipisvip）
    clientCloud:Get("redeem_vipisvip", {
        ok = function(values, iscores)
            local cloudVal = iscores and iscores["redeem_vipisvip"]
            if cloudVal and cloudVal > 0 then
                M.abyssFakeAd = true
                print("[AdFree] 云端深渊假广告权益已生效")
            end
        end,
        error = function(code, reason)
            print("[AdFree] 云端 vipisvip 读取失败: " .. tostring(reason))
        end,
    })
    -- 读取全局免广告权益（supergamer）
    clientCloud:Get("redeem_supergamer", {
        ok = function(values, iscores)
            local cloudVal = iscores and iscores["redeem_supergamer"]
            if cloudVal and cloudVal > 0 then
                M.adFree = true
                print("[AdFree] 云端全局免广告权益已生效")
            end
        end,
        error = function(code, reason)
            print("[AdFree] 云端 supergamer 读取失败: " .. tostring(reason))
        end,
    })
end

-- ====================================================================
-- 场景切换过渡效果
-- ====================================================================
M.sceneTransition = nil  -- nil=无过渡, { timer, phase, callback }

--- 启动场景切换过渡
---@param callback function 在全黑时执行的实际切换逻辑
function M.startSceneTransition(callback)
    M.sceneTransition = {
        timer = 0,
        phase = "in",       -- "in"=淡入黑屏, "hold"=保持全黑, "out"=淡出
        callback = callback,
        FADE_IN  = 0.15,    -- 淡入时长
        HOLD     = 0.10,    -- 全黑保持时长
        FADE_OUT = 0.25,    -- 淡出时长
    }
end

end  -- sub.init

return sub
