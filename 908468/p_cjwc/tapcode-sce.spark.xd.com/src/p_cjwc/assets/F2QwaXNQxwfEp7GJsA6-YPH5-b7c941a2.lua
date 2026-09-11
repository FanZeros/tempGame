local Battle = require("nightgate.Battle")
local Config = require("nightgate.Config")
local Equipment = require("nightgate.Equipment")
local Skills = require("nightgate.Skills")
local Prestige = require("nightgate.Prestige")
local UIData = require("nightgate.OriginalUIData")
local MapData = require("nightgate.OriginalMapData")
local WallData = require("nightgate.OriginalWallData")
local Tutorial = require("nightgate.Tutorial")
local SkillPage = require("nightgate.SkillPage")
local SkillCanvas = require("nightgate.SkillCanvas")
local RewardAds = require("nightgate.RewardAds")
local EconomySkills = require("nightgate.EconomySkills")
local LootSystem = require("nightgate.LootSystem")
local MonsterAffixes = require("nightgate.MonsterAffixes")
local SettingsPage = require("nightgate.SettingsPage")

local SelfTest = {}

local function expect(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function closeTo(actual, expected)
    return math.abs(actual - expected) < 0.0001
end

function SelfTest.Run()
    local passed = 0
    local function check(condition, message)
        expect(condition, message)
        passed = passed + 1
    end

    check(#Skills.Definitions == 86, "技能树必须保留原版78节点并追加8个玩法节点")
    check(#EconomySkills.Definitions == 12, "财富技能树必须包含12个可用节点")
    check(#Config.LEVELS == 30, "原作普通战役必须为30夜")
    check(Config.FINAL_NIGHT_LEVEL.id == 10999, "最终之夜必须使用原表10999关卡")
    check(Config.TEST_LEVEL.id == 99999, "内部测试关必须与正式进度隔离")
    check(#Config.HEROES == 9, "英雄表必须包含原作9名英雄")
    local finalDifficultyCount = 0
    for difficulty = 0, Config.MAX_FINAL_DIFFICULTY do
        if Config.FINAL_NIGHT_DIFFICULTIES[difficulty] then finalDifficultyCount = finalDifficultyCount + 1 end
    end
    check(finalDifficultyCount == 6, "最终之夜必须包含0到5共6档难度")
    check(#Config.EQUIPMENT_ORDER == 60, "装备配置记录必须为60")
    check(UIData.designWidth == 1920 and UIData.designHeight == 1080, "原版UI设计分辨率必须为1920x1080")
    check(UIData.arena.x == 462 and UIData.arena.y == 31 and UIData.arena.size == 996, "战场必须使用原版固定矩形")
    check(#UIData.characterRows == 8, "装备页必须显示四墙队长与英雄共8行")
    check(#MapData.decorations == 81, "战场必须装载原版地图prefab中的81个装饰实例")
    local wallPositionsComplete = true
    for side = 1, 4 do
        wallPositionsComplete = wallPositionsComplete and #WallData.positions[side] == 52
    end
    check(wallPositionsComplete, "四面墙必须各使用原版prefab的52个守军站位")
    check(closeTo(WallData.heroes[1][2], 11.65) and closeTo(WallData.heroes[4][1], -10.956), "英雄必须使用原版四面墙HeroPos坐标")
    local originalPositionedSkills = 0
    local expansionPositionedSkills = 0
    local allSkillsPositioned = true
    for index = 1, #Skills.Definitions do
        if UIData.skillPositions[Skills.Definitions[index].id] then
            originalPositionedSkills = originalPositionedSkills + 1
        elseif Skills.Definitions[index].position then
            expansionPositionedSkills = expansionPositionedSkills + 1
        else
            allSkillsPositioned = false
        end
    end
    check(originalPositionedSkills == 78 and expansionPositionedSkills == 8 and allSkillsPositioned,
        "原版78节点必须保持prefab坐标，8个扩展节点必须提供独立坐标")
    local generatedExpansionIcons = true
    for index = 1, #Skills.Definitions do
        local definition = Skills.Definitions[index]
        if string.sub(definition.id, 1, 2) == "x_"
            and not string.find(definition.icon or "", "skill_tree/generated/", 1, true) then
            generatedExpansionIcons = false
        end
    end
    for _, id in ipairs({ "p_afterglow", "p_spirit_archers", "p_auto_hunt" }) do
        local definition = Prestige.GetDefinition(id)
        if not definition or not string.find(definition.icon or "", "skill_tree/generated/", 1, true) then
            generatedExpansionIcons = false
        end
    end
    check(generatedExpansionIcons, "本次新增技能与转生节点必须全部使用image生成的像素图标")

    local allNightsSpawnFromCenter = true
    for night = 1, #Config.LEVELS do
        local nightBattle = Battle.New({ nextNight = night, bestNight = 32 })
        nightBattle:SetArena(100, 50, 400)
        nightBattle:StartNight()
        if not nightBattle:SpawnEnemy() or #nightBattle.enemies ~= 1 then
            allNightsSpawnFromCenter = false
            break
        end
        local enemy = nightBattle.enemies[1]
        local centerX, centerY = 300, 250
        local startsAtCenter = math.abs(enemy.x - centerX) <= 9.01 and math.abs(enemy.y - centerY) <= 9.01
        local targetsWall = enemy.tx == 182 or enemy.tx == 418 or enemy.ty == 132 or enemy.ty == 368
        if not startsAtCenter or not targetsWall or enemy.side < 1 or enemy.side > 4 then
            allNightsSpawnFromCenter = false
            break
        end
    end
    check(allNightsSpawnFromCenter, "全部30个普通夜都必须从中心出怪并向四面墙之一移动")

    local lateContentValid = true
    for night = 11, Config.CAMPAIGN_NIGHT_COUNT do
        local level = Config.LEVELS[night]
        if not level or #level.waves == 0 or not Config.LEVEL_DROPS[level.dropDay] then
            lateContentValid = false
            break
        end
        for waveIndex = 1, #level.waves do
            local wave = Config.MONSTER_WAVES[level.waves[waveIndex]]
            if not wave or #wave.monsterIds == 0 then
                lateContentValid = false
                break
            end
            for monsterIndex = 1, #wave.monsterIds do
                if not Config.MONSTERS[wave.monsterIds[monsterIndex]] then lateContentValid = false end
            end
        end
    end
    check(lateContentValid, "第11到30夜必须具有完整波次、怪物与掉落引用")

    local levels = {}
    local root = Skills.GetDefinition("0_0_0")
    local firstChild = Skills.GetDefinition("1_1_1")
    local function revealedCount(currentLevels)
        local count = 0
        for index = 1, #Skills.Definitions do
            if Skills.IsRevealed(currentLevels, Skills.Definitions[index]) then count = count + 1 end
        end
        return count
    end
    check(revealedCount(levels) == 1, "技能树开局只能看见中央根节点，不能提前显示其他节点")
    check(Skills.IsRevealed(levels, root), "技能树初始必须只显露中央根节点")
    check(not Skills.IsRevealed(levels, firstChild), "中央根节点未点亮前第一圈分支必须完全隐藏")
    check(Skills.GetNodeState(levels, root, 1) == "available", "根节点初始应可点亮")
    check(Skills.GetNodeState(levels, firstChild, 1) == "locked", "未满足前置时子节点应锁定")
    levels["0_0_0"] = 1
    check(revealedCount(levels) == 5, "点亮中央根节点后只能显露与其直连的四个第一圈节点")
    check(Skills.IsRevealed(levels, firstChild), "中央根节点点亮后必须显露直接相连的第一圈分支")
    check(not Skills.IsRevealed(levels, Skills.GetDefinition("1_2_1")), "未点亮第一圈分支时更深节点必须保持隐藏")
    check(Skills.GetNodeState(levels, firstChild, 1) == "available", "前置达到1级后子节点应点亮为可用")
    levels["1_1_1"] = 1
    check(revealedCount(levels) == 8, "点亮单条第一圈分支后只能新增该分支的三个直接子节点")
    check(Skills.IsRevealed(levels, Skills.GetDefinition("1_2_1")), "点亮一条分支后只能继续显露它的直接子节点")
    check(not Skills.IsRevealed(levels, Skills.GetDefinition("1_3_1")), "分支不得越级显示隔代节点")
    check(Skills.GetNodeState(levels, firstChild, 1) == "owned", "购买后节点应保持点亮")
    levels["1_1_1"] = #firstChild.costs
    check(Skills.GetNodeState(levels, firstChild, 1) == "maxed", "满级节点应显示满级点亮")

    local gated = Skills.GetDefinition("3_1_1")
    check(Skills.GetNodeState(levels, gated, 2) == "locked", "通关夜数不足时英雄节点应锁定")
    check(Skills.GetNodeState(levels, gated, 3) == "available", "守过第3晚后英雄节点应可用")
    local multiParent = Skills.GetDefinition("3_3_1")
    levels["3_2_1"] = 1
    levels["3_2_2"] = 0
    check(Skills.GetNodeState(levels, multiParent, 11) == "locked", "多前置缺一时节点应锁定")
    levels["3_2_2"] = 1
    check(Skills.GetNodeState(levels, multiParent, 11) == "available", "多前置全部满足后节点应可用")
    check(Skills.GetNodeState({ ["4_1_1"] = 1 }, Skills.GetDefinition("4_2_1"), 1) == "available",
        "所有分支前置点亮1级后必须可继续加点，不能再要求3级或满级")
    local onePointLevels = {}
    for index = 1, #Skills.Definitions do
        onePointLevels[Skills.Definitions[index].id] = 1
    end
    local onePointTreeReachable = true
    for index = 1, #Skills.Definitions do
        if not Skills.IsUnlocked(onePointLevels, Skills.Definitions[index], 32) then
            onePointTreeReachable = false
            break
        end
    end
    check(onePointTreeReachable, "技能树全部父节点只点亮1级时，所有后续节点都必须满足前置条件")
    local maxedLevels = {}
    for index = 1, #Skills.Definitions do
        maxedLevels[Skills.Definitions[index].id] = #Skills.Definitions[index].costs
    end
    check(revealedCount(maxedLevels) == 86, "完全点亮技能树后必须显露全部86个节点")
    local allReachable = true
    for index = 1, #Skills.Definitions do
        if not Skills.IsUnlocked(maxedLevels, Skills.Definitions[index], 32) then
            allReachable = false
            break
        end
    end
    check(allReachable, "全部86个节点在满足前置和夜数后必须可达")
    local expansionStats = Battle.New({ bestNight = 30, skillLevels = {
        x_cursor_echo = 2, x_cursor_storm = 1,
        x_wall_thorns = 2, x_wall_laststand = 1,
        x_hero_resonance = 2, x_hero_unity = 1,
        x_archer_ricochet = 2, x_archer_barrage = 1,
    } }):GetStats()
    check(closeTo(expansionStats.cursorEchoChance, 0.30) and expansionStats.cursorStormEvery == 8
        and expansionStats.wallThornsDamage == 8 and expansionStats.wallLastStandEnabled
        and expansionStats.heroSpecialAcceleration == 2 and expansionStats.heroUnityEvery == 4
        and closeTo(expansionStats.archerRicochetChance, 0.30) and expansionStats.archerBarrageEvery == 12,
        "8个扩展技能节点必须全部写入战斗属性，不能只显示图标与文本")
    check(Skills.IsUnlocked({ ["1_2_1"] = 1 }, Skills.GetDefinition("1_3_1"), 32), "原表高等级前置在正式版中必须降为点亮1级")
    local releaseNodesFunctional = true
    for index = 1, #Skills.Definitions do
        local definition = Skills.Definitions[index]
        local position = UIData.skillPositions[definition.id]
        if position and position[3] == true and (tonumber(definition.values[1]) or 0) <= 0 then
            releaseNodesFunctional = false
            break
        end
    end
    check(releaseNodesFunctional, "原Demo限制节点在正式版中必须有名称、价格与非零技能效果")

    local economyParentsValid = true
    for index = 1, #EconomySkills.Definitions do
        local definition = EconomySkills.Definitions[index]
        if #definition.costs ~= #definition.values or #definition.costs <= 0 then economyParentsValid = false end
        for parentIndex = 1, #definition.parents do
            if not EconomySkills.GetDefinition(definition.parents[parentIndex]) then economyParentsValid = false end
        end
    end
    check(economyParentsValid, "财富技能节点必须具有有效前置、价格与效果")
    local economyBattle = Battle.New({ gold = 100, economyLevels = {} })
    local economyUpgradeOk = EconomySkills.TryUpgrade(economyBattle, "e_root")
    check(economyUpgradeOk and economyBattle.gold == 80 and EconomySkills.GetLevel(economyBattle.economyLevels, "e_root") == 1,
        "财富技能必须能通过详情按钮消耗金币并持久记录等级")
    local economyStats = economyBattle:GetStats()
    check(closeTo(economyStats.goldGainBonus, 0.10) and closeTo(economyStats.rewardDoubleChance, 0.06)
        and closeTo(economyStats.rewardTripleChance, 0.02) and closeTo(economyStats.rewardQuadChance, 0.006)
        and closeTo(economyStats.jackpotChance, 0.001) and economyStats.jackpotMultiplier == 20,
        "财富树基础倍率概率与0.1%超级大奖必须正确进入战斗属性")
    local jackpotReward, jackpotMultiplier, jackpotTier = LootSystem.RollGoldReward(2, economyStats, {}, function() return 0 end)
    local quadReward, _, quadTier = LootSystem.RollGoldReward(2, economyStats, {}, function() return 0.001 end)
    local normalReward, normalMultiplier, normalTier = LootSystem.RollGoldReward(2, economyStats, {}, function() return 0.99 end)
    check(jackpotReward == 40 and jackpotMultiplier == 20 and jackpotTier == "jackpot"
        and quadReward == 8 and quadTier == "quad"
        and normalReward == 2 and normalMultiplier == 1 and normalTier == "normal",
        "2倍/3倍/4倍/超级大奖必须使用互斥概率并正确放大本次怪物金币")
    local earlyEnemy = { name = "幽灵", hp = 10, maxHP = 10, speed = 1, wallDamage = 1, attackInterval = 1, reward = 1, size = 24 }
    check(MonsterAffixes.Apply(earlyEnemy, 3, {}, function() return 0 end) == nil, "第4夜前不得生成词缀精英怪")
    local randomValues = { 0, 0 }
    local randomIndex = 0
    local eliteEnemy = { name = "幽灵", hp = 10, maxHP = 10, speed = 1, wallDamage = 1, attackInterval = 1, reward = 2, size = 24 }
    local affix = MonsterAffixes.Apply(eliteEnemy, 4, {}, function()
        randomIndex = randomIndex + 1
        return randomValues[randomIndex] or 0
    end)
    check(affix and affix.id == "swift" and eliteEnemy.elite and eliteEnemy.reward == 3 and eliteEnemy.speed > 1,
        "第4夜起必须能生成有强度差异、视觉标签和额外奖励的精英怪")
    local releaseStats = Battle.New({ skillLevels = {
        ["3_5_2"] = 1, ["4_4_2"] = 1, ["4_4_4"] = 1, ["4_5_2"] = 1, ["4_5_3"] = 1,
    } }):GetStats()
    check(closeTo(releaseStats.heroSkillDamageByAttribute[48], 2)
        and closeTo(releaseStats.archerCooldownReduction, 0.10)
        and closeTo(releaseStats.archerProjectilePenetration, 0.05)
        and releaseStats.archerMiaUnlocked and releaseStats.archerDamage >= Config.ARCHER.damage + 2,
        "正式版技能节点必须实际进入英雄与弓箭手战斗属性计算")

    local lateHeroNodes = { "3_2_12", "3_2_13", "3_2_21", "3_2_22", "3_2_23" }
    local lateHeroGateValid = true
    for index = 1, #lateHeroNodes do
        local testLevels = {}
        for definitionIndex = 1, #Skills.Definitions do
            local definition = Skills.Definitions[definitionIndex]
            testLevels[definition.id] = definition.id == lateHeroNodes[index] and 0 or #definition.costs
        end
        local definition = Skills.GetDefinition(lateHeroNodes[index])
        if Skills.GetNodeState(testLevels, definition, 10) ~= "locked" or Skills.GetNodeState(testLevels, definition, 11) ~= "available" then
            lateHeroGateValid = false
            break
        end
    end
    check(lateHeroGateValid, "五个后期英雄节点必须在第11夜按原表开放")

    local heroLevels = { ["3_1_1"] = 1, ["3_2_1"] = 1, ["3_2_11"] = 1, ["3_2_12"] = 1 }
    local unlockedHeroes = Skills.GetUnlockedHeroes(heroLevels)
    check(#unlockedHeroes == 4, "已购买的四个英雄解锁节点必须生成四名可用英雄")
    local heroBattle = Battle.New({ skillLevels = heroLevels, bestNight = 11 })
    check(heroBattle:GetHeroForSide(4) and heroBattle:GetHeroForSide(4).name == "野性祭司", "后期英雄必须能实际分配到四墙战斗")

    local lockedRosterBattle = Battle.New({ inventory = { { id = 2000 } } })
    check(lockedRosterBattle:GetStats().archerCount == 0 and not lockedRosterBattle:IsArcherUnlocked(), "新存档不得默认赠送弓箭手")
    local allArcherSidesLocked = true
    for side = 1, 4 do
        allArcherSidesLocked = allArcherSidesLocked and lockedRosterBattle:GetArcherCountForSide(side) == 0
    end
    check(allArcherSidesLocked, "未点亮弓箭节点时四面墙都不得出现弓箭手")
    lockedRosterBattle.enemies = { { dead = false, side = 1, x = 300, y = 200, tx = 300, ty = 100, boss = false } }
    lockedRosterBattle:ShootSide(1)
    check(#lockedRosterBattle.projectiles == 0, "未点亮弓箭节点时战斗后台不得发射箭矢")
    check(lockedRosterBattle:EquipInventoryItem(1, 1) == false and #lockedRosterBattle.inventory == 1, "弓箭手未解锁时队长装备槽必须保持锁定")
    check(not lockedRosterBattle:IsRoleUnlocked(1, "hero"), "未购买英雄节点时英雄装备槽必须保持锁定")

    local archerBattle = Battle.New({ skillLevels = { ["4_1_1"] = 1 } })
    check(archerBattle:GetStats().archerCount == 8 and archerBattle:IsArcherUnlocked(), "弓箭节点4_1_1一级必须按原表解锁总计8名弓箭手")
    check(#archerBattle:GetUnlockedArchers() == 1 and archerBattle:GetArcherForSide(1).id == 20001, "首批弓箭手只能使用原表默认队长艾琳")
    local firstArcherDistributionValid = true
    for side = 1, 4 do
        firstArcherDistributionValid = firstArcherDistributionValid and archerBattle:GetArcherCountForSide(side) == 2
    end
    check(firstArcherDistributionValid, "首级8名弓箭手必须均分到四面墙各2名")
    archerBattle.enemies = { { dead = false, side = 1, x = 300, y = 200, tx = 300, ty = 100, boss = false } }
    archerBattle:ShootSide(1)
    check(#archerBattle.projectiles == 2, "解锁首级弓箭手后单面必须按2名守军发射箭矢")
    local archerRosterBattle = Battle.New({
        skillLevels = { ["4_1_1"] = 1, ["4_4_3"] = 1, ["4_4_31"] = 1, ["4_5_2"] = 1 },
        selectedArchers = { [3] = 20002 },
    })
    local archerRosterStats = archerRosterBattle:GetStats()
    check(#archerRosterBattle:GetUnlockedArchers() == 2 and archerRosterBattle:GetArcherForSide(3).id == 20002, "米娅必须由属性70节点独立解锁并可按城墙选择")
    check(archerRosterStats.archerEileenPassiveUnlocked and archerRosterStats.archerMiaUnlocked and archerRosterStats.explosiveArrowUnlocked, "艾琳被动、米娅和爆炸箭必须保持三个独立解锁状态")
    check(archerRosterBattle:CycleArcher(1) and archerRosterBattle:GetArcherForSide(1).id == 20002, "队长头像必须能在已解锁的艾琳与米娅之间切换")
    local unevenArcherBattle = Battle.New({ skillLevels = { ["4_1_1"] = 3, ["4_2_1"] = 3, ["4_3_1"] = 1 } })
    local distributedTotal, minSide, maxSide = 0, math.huge, 0
    for side = 1, 4 do
        local count = unevenArcherBattle:GetArcherCountForSide(side)
        distributedTotal = distributedTotal + count
        minSide = math.min(minSide, count)
        maxSide = math.max(maxSide, count)
    end
    check(distributedTotal == 75 and maxSide - minSide <= 1, "非4倍数弓箭手总数必须无重复地均匀分配到四墙")

    local postTen = Battle.New({ nextNight = 10, bestNight = 9 })
    postTen.night = 10
    postTen.activeMode = "campaign"
    postTen:FinishVictory()
    check(postTen.nextNight == 11 and postTen.bestNight == 10, "通关第10夜必须连续推进到第11夜")
    check(postTen.state == "victory" and postTen:DismissResult() and postTen.state == "home", "胜利结算窗必须可返回升级页")

    local campaignEnd = Battle.New({ nextNight = 30, bestNight = 29 })
    campaignEnd.night = 30
    campaignEnd.activeMode = "campaign"
    campaignEnd:FinishVictory()
    check(not campaignEnd:IsFinalNightUnlocked() and campaignEnd.nextNight == 30, "最终之夜必须由原作转生仪式解锁，而非直接通关第30夜")

    local prestigeBattle = Battle.New({
        bestNight = 10, nextNight = 11, gold = 123, crystals = 17, equipmentShards = 9,
        quickDamageLevel = 3, quickWallLevel = 2, skillLevels = { ["1_1_1"] = 1 },
        inventory = { { id = 1000 } },
    })
    check(Prestige.CalculateReward(10) == 6 and Prestige.CalculateReward(20) == 12
        and Prestige.CalculateReward(30) == 18, "转生点必须按10/20/30夜结算为6/12/18")
    check(prestigeBattle:CanPrestige(), "完成第10夜后必须满足转生条件")
    check(prestigeBattle:PerformPrestige(), "满足条件时必须可以执行转生")
    check(prestigeBattle.prestigeCount == 1 and prestigeBattle.prestigeMilestone == 10
        and prestigeBattle:IsFinalNightUnlocked(), "转生后必须永久记录第10夜祝福并解锁最终之夜")
    check(prestigeBattle.prestigePoints == 6 and prestigeBattle.prestigePointsTotal == 6,
        "完成第10夜转生必须获得6点可消费转生点")
    check(prestigeBattle.gold == 6 and prestigeBattle.crystals == 0 and prestigeBattle.equipmentShards == 0
        and #prestigeBattle.inventory == 0 and next(prestigeBattle.skillLevels) == nil
        and prestigeBattle.quickDamageLevel == 0 and prestigeBattle.quickWallLevel == 0 and prestigeBattle.nextNight == 1,
        "转生必须重置普通成长并携带6枚基础金币，避免第一夜卡死")
    check(prestigeBattle:TryUpgrade("0_0_0"), "转生后基础金币必须足够重新点亮普通技能树根节点")

    local resetRegression = Battle.New({ bestNight = 30, nextNight = 30, gold = 500 })
    local firstWave = Config.MONSTER_WAVES[Config.LEVELS[1].waves[1]]
    local resetArchetype = Config.MONSTERS[firstWave.monsterIds[1]]
    local nightThirtyCombat = resetRegression:GetEnemyCombatStats(resetArchetype, Config.LEVELS[30])
    resetRegression.night = 30
    resetRegression.levelConfig = Config.LEVELS[30]
    resetRegression.enemies = { { dead = false } }
    resetRegression.projectiles = { { life = 1 } }
    resetRegression.spawnBudget = 999
    check(resetRegression:PerformPrestige(), "第30夜转生必须可以执行")
    check(resetRegression.night == nil and resetRegression.levelConfig == nil and resetRegression.spawnBudget == 0
        and #resetRegression.enemies == 0 and #resetRegression.projectiles == 0,
        "转生必须清除第30夜关卡引用、刷怪预算、敌人与投射物")
    resetRegression:StartNight()
    local resetCombat = resetRegression:GetEnemyCombatStats(resetArchetype)
    local freshCombat = Battle.New({ nextNight = 1 }):GetEnemyCombatStats(resetArchetype, Config.LEVELS[1])
    check(nightThirtyCombat.hp > freshCombat.hp and resetCombat.hp == freshCombat.hp
        and resetCombat.wallDamage == freshCombat.wallDamage and closeTo(resetCombat.speed, freshCombat.speed)
        and resetRegression.activeMode == "campaign" and resetRegression.night == 1,
        "转生后普通战役主入口必须进入第1夜并恢复第一夜属性，不能误入最终之夜或沿用第30夜倍率")

    local function prestigeRevealedCount(levels)
        local count = 0
        for index = 1, #Prestige.Definitions do
            if Prestige.IsRevealed(levels, Prestige.Definitions[index]) then count = count + 1 end
        end
        return count
    end
    check(prestigeRevealedCount(prestigeBattle.prestigeLevels) == 1,
        "转生技能树初始只能显示中央黄金火种")
    check(prestigeBattle:TryPrestigeUpgrade("p_root") and prestigeBattle.prestigePoints == 5 and prestigeBattle.gold == 3,
        "点亮黄金火种必须消耗1转生点，且不能伪装成即时补发金币")
    check(prestigeRevealedCount(prestigeBattle.prestigeLevels) == 6,
        "点亮转生树中央节点后必须显示四条原分支与轮回余火")
    check(prestigeBattle:TryPrestigeUpgrade("p_power") and prestigeBattle:TryPrestigeUpgrade("p_wall"),
        "转生点必须可以点亮伤害与城墙两条永久分支")
    local prestigeStats = prestigeBattle:GetStats()
    check(closeTo(prestigeStats.damageMultiplier, 1.08) and prestigeStats.wallMax == 130
        and closeTo(prestigeStats.goldGainBonus, 0.20), "已点亮的转生伤害、城墙与金币获取节点必须进入战斗属性")
    check(prestigeStats.goldSettlementBonus == 50 and prestigeStats.crystalSettlementBonus == 50
        and prestigeStats.extraCrystalMonsters == 2 and closeTo(prestigeStats.wallDodge, 0),
        "第10夜转生必须结算原作前三项永久祝福，但不能提前获得第20夜属性")
    local supplyStats = Battle.New({ prestigeCount = 1, prestigeMilestone = 10,
        prestigeLevels = { p_root = 1, p_supply = 1 } }):GetStats()
    check(closeTo(supplyStats.goldGainBonus, 0.50) and Prestige.GetStartingGold({ p_supply = 4 }) == 0,
        "开拓储备每级必须增加30%金币获取，不得继续增加或补发开局金币")
    prestigeBattle.bestNight = 20
    check(prestigeBattle:CanPrestige() and prestigeBattle:PerformPrestige(), "达到条件后必须允许重复转生")
    check(prestigeBattle.prestigeCount == 2 and prestigeBattle.prestigePoints == 15
        and prestigeBattle.prestigePointsTotal == 18 and prestigeBattle.prestigeMilestone == 20 and prestigeBattle.gold == 6,
        "第二次转生必须累加夜数奖励、基础金币并将永久祝福提升到第20夜")
    check(Prestige.GetLevel(prestigeBattle.prestigeLevels, "p_power") == 1
        and closeTo(prestigeBattle:GetStats().damageMultiplier, 1.08), "重复转生不得清除已点亮的转生技能")
    local tierTwentyStats = prestigeBattle:GetStats()
    check(closeTo(tierTwentyStats.wallDodge, 0.10) and closeTo(tierTwentyStats.cursorDoubleChance, 0.10)
        and closeTo(tierTwentyStats.cursorRadiusBonus, 0.15) and closeTo(tierTwentyStats.archerBerserkChance, 0),
        "第20夜转生必须追加闪避、双击和指针范围，但不能提前获得第30夜属性")

    local tierThirtyStats = Battle.New({ prestigeCount = 1, prestigeMilestone = 30 }):GetStats()
    check(closeTo(tierThirtyStats.archerBerserkChance, 0.05) and closeTo(tierThirtyStats.archerBossBonus, 0.50)
        and tierThirtyStats.dragonAssist == 1, "第30夜转生必须结算狂暴、Boss增伤与古龙助战")

    local prestigeTreeCost = 0
    for index = 1, #Prestige.Definitions do
        for costIndex = 1, #Prestige.Definitions[index].costs do
            prestigeTreeCost = prestigeTreeCost + Prestige.Definitions[index].costs[costIndex]
        end
    end
    check(prestigeTreeCost == 140 and math.ceil(prestigeTreeCost / Prestige.CalculateReward(30)) == 8,
        "转生树总成本应为140点，第30夜完整轮回约8次点满")
    local earlyKit = Battle.New({ nextNight = 1, prestigeLevels = {
        p_root = 1, p_afterglow = 1, p_spirit_archers = 1, p_auto_hunt = 1,
    } })
    local earlyKitStats = earlyKit:GetStats()
    check(closeTo(earlyKitStats.damageMultiplier, 1.5) and earlyKitStats.wallMax == 260
        and earlyKitStats.spiritVolleyEnabled == 1 and earlyKitStats.randomCursorEnabled > 0,
        "第10夜6点必须能组成余火、灵魂箭阵与自动狩猎的完整启动质变")
    earlyKit.nextNight = 4
    local expiredAfterglow = earlyKit:GetStats()
    check(closeTo(expiredAfterglow.damageMultiplier, 1) and expiredAfterglow.wallMax == 110
        and expiredAfterglow.spiritVolleyEnabled == 1 and expiredAfterglow.randomCursorEnabled > 0,
        "轮回余火只持续前3夜，自动狩猎与灵魂箭阵必须永久生效")

    local legacyPrestige = Battle.New({ prestigeCount = 1, gold = 0 })
    check(legacyPrestige.prestigePoints == 5 and Prestige.GetLevel(legacyPrestige.prestigeLevels, "p_root") == 1
        and legacyPrestige.prestigeMilestone == 10 and legacyPrestige.gold == 6,
        "旧版已转生存档必须迁移补偿点数、中央节点、第10夜祝福与开局金币")

    local freshSaveBattle = Battle.New({
        prestigeCount = 2, prestigePoints = 9, prestigePointsTotal = 15, prestigeLevels = { p_root = 1, p_power = 2 },
        gold = 99, crystals = 8, equipmentShards = 4, bestNight = 20, skillLevels = { ["1_1_1"] = 2 },
        musicVolume = 0.35, sfxVolume = 0.8,
    })
    freshSaveBattle:StartNewSave()
    check(freshSaveBattle.prestigeCount == 0 and freshSaveBattle.prestigeMilestone == 0
        and freshSaveBattle.gold == 3 and freshSaveBattle.crystals == 0
        and freshSaveBattle.equipmentShards == 0 and freshSaveBattle.bestNight == 1 and freshSaveBattle.nextNight == 1
        and freshSaveBattle.prestigePoints == 0 and freshSaveBattle.prestigePointsTotal == 0
        and next(freshSaveBattle.prestigeLevels) == nil and next(freshSaveBattle.skillLevels) == nil,
        "新游戏必须建立完全独立的新存档并清除全部转生状态")
    check(closeTo(freshSaveBattle:GetMusicVolume(), 0.35) and closeTo(freshSaveBattle:GetSfxVolume(), 0.8),
        "新游戏只能重置游戏进度，不能覆盖玩家的声音偏好")

    local finalBattle = Battle.New({ prestigeCount = 1, finalDifficultyUnlocked = 1, finalDifficultySelected = 1 })
    check(finalBattle:StartFinalNight(1), "已解锁的最终之夜难度必须可进入")
    check(finalBattle.levelConfig.difficulty == 1300 and finalBattle.levelConfig.hp == 5100 and finalBattle.levelConfig.atk == 400, "最终难度1必须应用原表难度、血量与攻击加成")
    check(finalBattle.levelConfig.moveSpeed == 10 and finalBattle.levelConfig.crystal == 10 and finalBattle.levelConfig.dropRateBonus == 20, "最终难度1必须应用移速、晶石与装备掉率加成")

    local bossBattle = Battle.New({ nextNight = 26, bestNight = 30 })
    bossBattle:StartNight()
    local bossSpawned = false
    local spawnGuard = 0
    while bossBattle.spawnBudget > 0 and spawnGuard < 2500 do
        spawnGuard = spawnGuard + 1
        local before = #bossBattle.enemies
        bossBattle:SpawnEnemy()
        if #bossBattle.enemies > before and bossBattle.enemies[#bossBattle.enemies].boss then bossSpawned = true end
        bossBattle.enemies = {}
    end
    check(bossSpawned, "第26夜原表哥布林王波次必须保证生成")

    local finalBossBattle = Battle.New({ prestigeCount = 1, finalDifficultyUnlocked = 0 })
    finalBossBattle:StartFinalNight(0)
    local finalBossIds = {}
    spawnGuard = 0
    while finalBossBattle.spawnBudget > 0 and spawnGuard < 2500 do
        spawnGuard = spawnGuard + 1
        local before = #finalBossBattle.enemies
        finalBossBattle:SpawnEnemy()
        if #finalBossBattle.enemies > before then
            local enemy = finalBossBattle.enemies[#finalBossBattle.enemies]
            if enemy.boss then finalBossIds[enemy.id] = true end
        end
        finalBossBattle.enemies = {}
    end
    check(finalBossIds["boss死灵"] and finalBossIds["boss哥布林王"], "最终之夜必须各生成一次死灵与哥布林王")

    local cappedWaveBattle = Battle.New({ nextNight = 2, bestNight = 30 })
    cappedWaveBattle:StartNight()
    spawnGuard = 0
    while cappedWaveBattle.spawnBudget > 0 and spawnGuard < 300 do
        spawnGuard = spawnGuard + 1
        cappedWaveBattle:SpawnEnemy()
        cappedWaveBattle.enemies = {}
    end
    check((cappedWaveBattle.waveSpawnCounts["普通-牛头人10"] or 0) <= 10, "带数量上限的原表波次不得超额生成")

    local upgradeBattle = Battle.New({ gold = 3, bestNight = 1 })
    check(upgradeBattle:TryUpgrade("0_0_0") == true, "有足够金币应能点亮根节点")
    check(upgradeBattle.gold == 0 and upgradeBattle.skillLevels["0_0_0"] == 1, "点亮应扣除原表金币并写入等级")

    local onboardingBattle = Battle.New({ gold = 9, bestNight = 1 })
    check(onboardingBattle:TryUpgrade("0_0_0") and onboardingBattle:TryUpgrade("4_1_1"),
        "新存档累积9金币后必须能按中央节点到弓箭节点的路径开启自动攻击")
    check(onboardingBattle.gold == 0 and onboardingBattle:IsArcherUnlocked()
        and onboardingBattle:GetStats().archerCount == 8,
        "首条引导路径应消耗3+6金币并解锁总计8名弓箭手")
    local onboardingDistributionValid = true
    for side = 1, 4 do
        onboardingDistributionValid = onboardingDistributionValid
            and onboardingBattle:GetArcherCountForSide(side) == 2
    end
    check(onboardingDistributionValid, "通过引导解锁的8名弓箭手必须四墙各分2名")

    local tutorialBattle = Battle.New({ gold = 3, tutorialCompleted = false })
    local tutorialApp = { battle = tutorialBattle, screen = "game", selectedTab = "skills" }
    check(Tutorial.ResolveStep(tutorialApp) == "root", "新存档引导必须先指向中央根节点")
    tutorialApp.selectedTab = "equipment"
    check(Tutorial.ResolveStep(tutorialApp) == "skills_tab", "离开技能页时引导必须指向技能树页签")
    tutorialApp.selectedTab = "skills"
    tutorialBattle.skillLevels["0_0_0"] = 1
    tutorialBattle.gold = 0
    check(Tutorial.ResolveStep(tutorialApp) == "start", "点亮核心但金币不足时引导必须指向新轮次")
    tutorialBattle.state = "running"
    check(Tutorial.ResolveStep(tutorialApp) == "battle", "首夜进行中必须显示指针守城引导")
    tutorialBattle.state = "victory"
    check(Tutorial.ResolveStep(tutorialApp) == "result", "首夜结算时必须指向返回升级")
    tutorialBattle.state = "home"
    tutorialBattle.gold = 6
    check(Tutorial.ResolveStep(tutorialApp) == "archer", "拥有6金币后必须指向弓箭手自动攻击节点")
    tutorialBattle.skillLevels["4_1_1"] = 1
    check(Tutorial.ResolveStep(tutorialApp) == "complete", "弓箭手解锁后必须进入引导完成步骤")
    check(tutorialBattle:CompleteTutorial() and Tutorial.ResolveStep(tutorialApp) == nil,
        "完成或跳过引导后不得再覆盖正常界面")
    tutorialBattle:StartNewSave()
    check(not tutorialBattle.tutorialCompleted and Tutorial.ResolveStep(tutorialApp) == "root",
        "明确建立新存档后必须重新开启新手引导")

    local mobileUpgradeBattle = Battle.New({ gold = 200, bestNight = 1 })
    check(mobileUpgradeBattle:TryUpgrade("0_0_0") and mobileUpgradeBattle:TryUpgrade("0_0_0")
        and mobileUpgradeBattle:TryUpgrade("0_0_0"), "手机端持有200金币时必须能连续点满第一个技能")
    check(mobileUpgradeBattle.gold == 29 and mobileUpgradeBattle.skillLevels["0_0_0"] == 3,
        "第一个技能三级总价必须为171金币，200金币点满后应剩29金币")
    check(not mobileUpgradeBattle:TryUpgrade("0_0_0") and mobileUpgradeBattle.message == "已满级",
        "已满级后必须返回明确失败原因，不能表现为点击无响应")

    local buttonUpgradeBattle = Battle.New({ gold = 3, bestNight = 1 })
    local buttonFeedback = nil
    local buttonFlash = nil
    local buttonUpgradeHarness = {
        battle = buttonUpgradeBattle,
        selectedSkill = nil,
        pinnedSkill = nil,
        skillDetail = { SetVisible = function() end },
        skillCanvas = { FlashNode = function(_, id, ok) buttonFlash = { id = id, ok = ok } end },
        GetSkillNode = function(_, id) return { id = id, revealed = id == "0_0_0" } end,
        ShowSkillFeedback = function(_, message, ok) buttonFeedback = { message = message, ok = ok } end,
        Refresh = function() end,
    }
    check(SkillPage.TryUpgrade(buttonUpgradeHarness, "0_0_0", "self_test_button"),
        "手机端详情升级按钮必须能独立完成加点，不依赖双击手势")
    check(buttonUpgradeBattle.gold == 0 and buttonUpgradeBattle.skillLevels["0_0_0"] == 1
        and buttonFeedback and buttonFeedback.ok and buttonFlash and buttonFlash.id == "0_0_0" and buttonFlash.ok,
        "详情升级按钮成功后必须扣金币、写等级并显示成功反馈")

    local skillHitNode = { id = "hit_test_root", x = 672, y = 412, size = 64, revealed = true }
    local skillHitCanvas = SkillCanvas {
        width = 1520, height = 970, nodes = { skillHitNode }, hitPadding = 34,
        minPanX = -500, maxPanX = 500, minPanY = -500, maxPanY = 500,
    }
    skillHitCanvas.absoluteLayout = { x = 200, y = 110, w = 1520, h = 970 }
    local hitAtVisualCenter = skillHitCanvas:FindNode(200 + 672 + 32, 110 + 412 + 32)
    check(hitAtVisualCenter and hitAtVisualCenter.id == "hit_test_root",
        "技能节点命中必须扣除画布绝对偏移，电脑和手机点击位置应与节点图像一致")
    skillHitCanvas:SetView(90, -60, 1.5)
    local hitAfterPanZoom = skillHitCanvas:FindNode(
        200 + 90 + (672 + 32) * 1.5,
        110 - 60 + (412 + 32) * 1.5
    )
    check(hitAfterPanZoom and hitAfterPanZoom.id == "hit_test_root",
        "技能树拖动和缩放后节点命中仍须与视觉位置一致")

    local rewardAdBattle = Battle.New({ gold = 50 })
    rewardAdBattle.state = "victory"
    rewardAdBattle.runStartGold = 50
    rewardAdBattle.gold = 67
    rewardAdBattle.nightGoldEarned = 17
    rewardAdBattle.nightResultId = 8
    local successSdk = { ShowRewardVideoAd = function(_, callback)
        callback({ success = true, msg = "embed success" })
        return true
    end }
    local successEvent = nil
    local rewardAds = RewardAds.New(rewardAdBattle, successSdk)
    check(rewardAds:RequestNightGold(function(event) successEvent = event end),
        "结算页激励广告请求成功时必须进入本夜金币领取流程")
    check(rewardAdBattle.gold == 84 and rewardAdBattle.nightGoldAdClaimed and rewardAdBattle.dirtySave
        and successEvent and successEvent.phase == "success" and successEvent.amount == 17,
        "广告只能补发本夜17金币，不能把开局已有50金币一起翻倍")
    check(not rewardAds:RequestNightGold(function() end) and rewardAdBattle.gold == 84,
        "同一夜激励金币只能领取一次")

    local closedAdBattle = Battle.New({ gold = 40 })
    closedAdBattle.state = "defeat"
    closedAdBattle.runStartGold = 40
    closedAdBattle.gold = 49
    closedAdBattle.nightGoldEarned = 9
    closedAdBattle.nightResultId = 9
    local closedSdk = { ShowRewardVideoAd = function(_, callback)
        callback({ success = false, msg = "embed manual close" })
        return true
    end }
    local closedEvent = nil
    check(RewardAds.New(closedAdBattle, closedSdk):RequestNightGold(function(event) closedEvent = event end)
        and closedAdBattle.gold == 49 and not closedAdBattle.nightGoldAdClaimed
        and closedEvent and closedEvent.phase == "failure",
        "广告提前关闭时不得发放金币或占用本夜领取次数")

    local rejectedAdBattle = Battle.New({ gold = 30 })
    rejectedAdBattle.state = "victory"
    rejectedAdBattle.runStartGold = 30
    rejectedAdBattle.gold = 36
    rejectedAdBattle.nightGoldEarned = 6
    rejectedAdBattle.nightResultId = 10
    local rejectedSdk = { ShowRewardVideoAd = function() return false end }
    local rejectedEvent = nil
    check(not RewardAds.New(rejectedAdBattle, rejectedSdk):RequestNightGold(function(event) rejectedEvent = event end)
        and rejectedAdBattle.gold == 36 and not rejectedAdBattle.nightGoldAdClaimed
        and rejectedEvent and rejectedEvent.phase == "failure",
        "广告加载失败或请求未受理时不得发放金币")

    local supplyBattle = Battle.New({ nextNight = 5, prestigeCount = 2 })
    local baseSupplyWall = supplyBattle:GetStats().wallMax
    local supplyEvent = nil
    local supplyAds = RewardAds.New(supplyBattle, successSdk)
    check(supplyAds:RequestNightSupply(function(event) supplyEvent = event end)
        and supplyEvent and supplyEvent.phase == "success" and supplyBattle:IsNightSupplyReady()
        and supplyBattle.adSupplyClaimKey == "2:5" and supplyBattle.dirtySave,
        "第5夜战前激励必须写入当前转生轮次，并在完整观看后标记战备就绪")
    supplyBattle:StartNight()
    check(supplyBattle.nightSupplyActive and supplyBattle.adSupplyReadyKey == nil
        and supplyBattle.wallMax == math.floor(baseSupplyWall * 1.3 + 0.5),
        "战前激励只能在下一次开战时消耗，并把本夜城墙上限提高30%")
    supplyBattle:ReturnHome()
    check(not supplyAds:RequestNightSupply(function() end),
        "同一转生轮次的同一里程碑夜不能重复领取战前激励")

    local nonMilestoneSupply = Battle.New({ nextNight = 6 })
    check(not RewardAds.New(nonMilestoneSupply, successSdk):RequestNightSupply(function() end),
        "战前激励只应在第5、10、15、20、25、30夜出现")

    local reviveBattle = Battle.New({ nextNight = 3 })
    reviveBattle:StartNight()
    local reviveWallMax = reviveBattle.wallMax
    reviveBattle.enemies = { { wait = 0, attackTimer = 0 } }
    reviveBattle:FinishDefeat()
    local reviveEvent = nil
    local reviveAds = RewardAds.New(reviveBattle, successSdk)
    check(reviveAds:RequestDefeatRevive(function(event) reviveEvent = event end)
        and reviveEvent and reviveEvent.phase == "success" and reviveBattle.state == "running"
        and reviveBattle.nightReviveAdUsed and reviveBattle.wallHP == math.floor(reviveWallMax * 0.35 + 0.5)
        and reviveBattle.enemies[1].wait >= 2,
        "败北激励完整观看后必须恢复35%城墙、暂停敌人并继续当前战斗")
    reviveBattle:FinishDefeat()
    check(not reviveAds:RequestDefeatRevive(function() end),
        "同一次挑战最多只能使用一次广告续战")

    local defeatSettlement = Battle.New({ gold = 20 })
    defeatSettlement.state = "running"
    defeatSettlement.night = 2
    defeatSettlement.runStartGold = 20
    defeatSettlement.gold = 23
    defeatSettlement.nightResultId = 11
    defeatSettlement.coinPickups = { { value = 2 }, { value = 5 } }
    defeatSettlement:FinishDefeat()
    check(defeatSettlement.gold == 30 and defeatSettlement.nightGoldEarned == 10
        and #defeatSettlement.coinPickups == 0,
        "失败结算前必须将已经掉落的金币入账并计入本夜可翻倍金额")

    local equipBattle = Battle.New({
        skillLevels = { ["4_1_1"] = 1 },
        inventory = { { id = 1000, level = 0, new = true }, { id = 1000, level = 0 }, { id = 2000, level = 0, new = true } },
        equipmentShards = 10,
    })
    check(equipBattle:EquipInventoryItem(3, 1) == true, "箭矢应能自动装配")
    check(Equipment.GetEquipped(equipBattle, 1, "captain", 2).id == 2000, "箭矢必须进入队长第2槽")
    check(Equipment.GetEquipped(equipBattle, 1, "captain", 2).new == true, "装备new标记必须随装配与存档保留")
    check(equipBattle:QuickMergeEquipment() == true, "两件相同种类品质装备应可一键合成")
    check(#equipBattle.inventory == 1 and equipBattle.inventory[1].id == 1001, "黑木弓应合成为下一品质1001")
    check(equipBattle.inventory[1].new == true, "合成装备必须显示原版new标记")
    check(equipBattle:EquipInventoryItem(1, 1) == true, "弓应能自动装配")
    check(Equipment.GetEquipped(equipBattle, 1, "captain", 1).id == 1001, "弓必须进入队长第1槽")
    check(equipBattle:StrengthenEquipment(1, "captain", 1) == true, "有碎片时装备应可强化")
    check(Equipment.GetEquipped(equipBattle, 1, "captain", 1).level == 1 and equipBattle.equipmentShards == 9, "0到1级应消耗原表1碎片")
    check(Equipment.DescribeEffects(Equipment.GetEquipped(equipBattle, 1, "captain", 1)):find("所有伤害加成", 1, true) ~= nil, "装备详情窗必须显示原表属性名称")

    local dropBattle = Battle.New()
    check(dropBattle:AddEquipmentDrop({ commonWeights = { { 0, 1 } }, weaponWeights = { { 1, 1 } }, maxQuality = 0 }, { materialDoubleChance = 0 }) == true
        and #dropBattle.runDrops == 1 and #dropBattle.inventory == 1, "战斗结算窗必须记录本轮真实装备掉落")

    local recycleBattle = Battle.New({ inventory = { { id = 1000 }, { id = 1001 } } })
    check(recycleBattle:RecycleInventory() == true, "背包装备应可批量分解")
    check(recycleBattle.equipmentShards == 9 and #recycleBattle.inventory == 0, "普通与精良分解应按原表获得3+6碎片")

    local lockedStatsBattle = Battle.New({ equipment = { [1] = { captain = { [1] = { id = 1000 } } } } })
    check(closeTo(lockedStatsBattle:GetStats().damageMultiplier, 1), "未解锁角色身上的旧存档装备不得后台生效")
    local statsBattle = Battle.New({ skillLevels = { ["4_1_1"] = 1 }, equipment = { [1] = { captain = { [1] = { id = 1000 } } } } })
    local stats = statsBattle:GetStats()
    check(closeTo(stats.damageMultiplier, 1) and closeTo(stats.archerDamageMultiplier, 1.2),
        "黑木弓所有伤害+20%只能进入弓箭手实际伤害，不能错误增益指针与英雄")
    check(closeTo(stats.archerCrit, 0.02) and closeTo(stats.cursorCrit, 0),
        "黑木弓暴击率+2%只能进入弓箭手暴击，不能错误写入指针暴击")
    local scopedTalentStats = Battle.New({ skillLevels = {
        ["4_1_1"] = 1, ["4_2_2"] = 1, ["4_3_3"] = 1, ["4_4_4"] = 1,
        ["3_4_1"] = 1, ["3_4_4"] = 1, ["3_4_5"] = 1, ["3_5_5"] = 1,
    } }):GetStats()
    check(closeTo(scopedTalentStats.archerCrit, 0.05) and closeTo(scopedTalentStats.cursorCrit, 0)
        and closeTo(scopedTalentStats.archerProjectilePenetration, 0.05)
        and closeTo(scopedTalentStats.archerProjectileRadiusBonus, 0.15),
        "弓箭暴击、穿透与范围节点必须进入弓箭战斗路径且不污染指针")
    check(scopedTalentStats.heroProjectileExtraChance > 0 and scopedTalentStats.heroProjectilePenetration > 0
        and scopedTalentStats.heroProjectileRadiusBonus > 0 and scopedTalentStats.heroProjectileSizeMultiplier > 1,
        "英雄投射物个数、穿透、范围与大小节点必须全部产生可观测属性变化")

    check(Config.CURSOR.interval >= 0.9, "手机端指针基础攻击间隔必须放慢到可辨识扩张圆环的节奏")
    check(Config.GAME_TIME_SCALE <= 0.6 and closeTo(Battle.New({}).speed, Config.GAME_TIME_SCALE), "战斗必须使用统一慢速时间倍率，避免局部系统呈现二倍速")
    local speedBattle = Battle.New({ speedMultiplier = 3 })
    check(speedBattle:GetSpeedMultiplier() == 3 and closeTo(speedBattle.speed, Config.GAME_TIME_SCALE * 3),
        "存档中的3倍速必须恢复并统一作用于战斗时间")
    check(speedBattle:SetSpeedMultiplier(2) and speedBattle:GetSpeedMultiplier() == 2
        and closeTo(speedBattle.speed, Config.GAME_TIME_SCALE * 2) and speedBattle.dirtySave,
        "1/2/3倍速切换必须立即生效并标记保存")
    local volumeBattle = Battle.New({ musicVolume = 0.45, sfxVolume = 0.7 })
    check(closeTo(volumeBattle:GetMusicVolume(), 0.45) and closeTo(volumeBattle:GetSfxVolume(), 0.7),
        "存档中的音乐与音效音量必须正确恢复")
    check(volumeBattle:SetMusicVolume(-1) and volumeBattle:SetSfxVolume(2)
        and closeTo(volumeBattle:GetMusicVolume(), 0) and closeTo(volumeBattle:GetSfxVolume(), 1)
        and volumeBattle.dirtySave,
        "声音设置必须限制在0%到100%，修改后必须标记保存")
    local appliedMusic, appliedSfx = nil, nil
    local settingsHarness = {
        battle = Battle.New({}),
        audioManager = {
            SetMusicVolume = function(_, value) appliedMusic = value end,
            SetSfxVolume = function(_, value) appliedSfx = value end,
        },
        settingsMusicValue = { SetText = function() end },
        settingsSfxValue = { SetText = function() end },
    }
    SettingsPage.SetVolume(settingsHarness, "music", 42)
    SettingsPage.SetVolume(settingsHarness, "sfx", 73)
    check(closeTo(settingsHarness.battle:GetMusicVolume(), 0.42) and closeTo(appliedMusic, 0.42)
        and closeTo(settingsHarness.battle:GetSfxVolume(), 0.73) and closeTo(appliedSfx, 0.73),
        "设置页滑块必须同时更新存档状态与正在播放的音乐/音效")
    local pacingBattle = Battle.New({ nextNight = 1 })
    pacingBattle:StartNight()
    check(pacingBattle.spawnInterval > Config.LEVELS[1].duration / Config.LEVELS[1].difficulty, "第一夜刷怪间隔必须比原始预算换算值更舒缓")
    check(Config.HERO_BY_ID[10002].specialSkill.name == "秘法斩击" and Config.HERO_BY_ID[10002].specialEvery == 10,
        "秘法师必须按原表每10次普通攻击触发秘法斩击")
    check(Config.HERO_BY_ID[10007].specialSkill.name == "古树突刺" and Config.HERO_BY_ID[10007].specialSkill.damage == 18,
        "德鲁伊必须按原表使用18点基础伤害的古树突刺")
    check(Config.HERO_BY_ID[10009].specialSkill.description:find("死亡时爆发", 1, true) ~= nil,
        "花灵寄生花种必须保留死亡爆炸说明")

    local heroVfxBattle = Battle.New({ skillLevels = { ["3_1_1"] = 1 } })
    heroVfxBattle.enemies = {
        { id = "test", name = "测试怪", side = 1, x = 420, y = 280, tx = 420, ty = 100, hp = 999, maxHP = 999,
            speed = 0, wallDamage = 1, attackInterval = 1, attackTimer = 1, wait = 0, reward = 0, crystal = 0,
            difficulty = 1, size = 30, boss = false, flash = 0, bob = 0, atWall = false, dead = false },
    }
    local arcaneHero = Config.HERO_BY_ID[10001]
    check(heroVfxBattle:ActivateHeroSpecial(1, arcaneHero, heroVfxBattle.enemies[1], 420, 120, heroVfxBattle:GetStats())
        and #heroVfxBattle.skillEffects == 1 and heroVfxBattle.skillEffects[1].skillId == 2001,
        "英雄技能触发时必须创建与原作技能编号绑定的独立美术特效")
    heroVfxBattle:DamageEnemy(heroVfxBattle.enemies[1], 12, Config.COLORS.cursor, false, "cursor")
    local cursorText = heroVfxBattle.floatingText[#heroVfxBattle.floatingText]
    check(cursorText.style == "cursor" and cursorText.size >= 23 and cursorText.color[1] >= 250 and cursorText.color[2] >= 240,
        "指针伤害数字必须比普通伤害更大、更亮并启用粗描边样式")

    local splitTargetBattle = Battle.New({ skillLevels = { ["4_1_1"] = 1 } })
    splitTargetBattle.enemies = {
        { id = "a", dead = false, side = 1, x = 300, y = 200, tx = 300, ty = 100, hp = 1, maxHP = 1, boss = false, incomingDamage = 0 },
        { id = "b", dead = false, side = 1, x = 320, y = 210, tx = 320, ty = 100, hp = 1, maxHP = 1, boss = false, incomingDamage = 0 },
        { id = "c", dead = false, side = 1, x = 340, y = 220, tx = 340, ty = 100, hp = 1, maxHP = 1, boss = false, incomingDamage = 0 },
    }
    splitTargetBattle:ShootSide(1)
    check(#splitTargetBattle.projectiles == 2
        and splitTargetBattle.projectiles[1].target ~= splitTargetBattle.projectiles[2].target,
        "同墙多名弓箭手必须依据飞行中预留伤害分摊目标，避免全体射向同一只残血怪")
    local abandonedTarget = splitTargetBattle.projectiles[1].target
    abandonedTarget.dead = true
    splitTargetBattle:UpdateProjectiles(0.001)
    check(splitTargetBattle.projectiles[1].target ~= abandonedTarget
        and (abandonedTarget.incomingDamage or 0) == 0,
        "目标提前死亡时在途箭矢必须释放预留伤害并自动改射其他怪物")

    local chestBattle = Battle.New({ nextNight = 1 })
    local chestSource = { x = 300, y = 240, side = 1, size = 30, noChestSpawn = false }
    check(chestBattle:TrySpawnCursorChest(chestSource, { cursorChestChance = 1 })
        and #chestBattle.enemies == 1 and chestBattle.enemies[1].id == "宝箱怪"
        and chestBattle.enemies[1].noChestSpawn,
        "指针击杀生成宝箱怪天赋必须真实生成奖励怪，并阻止宝箱怪连锁生成")

    local coinBattle = Battle.New({ gold = 10, nextNight = 1 })
    coinBattle:StartNight()
    coinBattle.enemies = {
        { id = "test", name = "测试怪", side = 1, x = 420, y = 280, tx = 420, ty = 100, hp = 1, maxHP = 1,
            speed = 0, wallDamage = 1, attackInterval = 1, attackTimer = 1, wait = 0, reward = 3, crystal = 0,
            difficulty = 1, size = 30, boss = false, flash = 0, bob = 0, atWall = false, dead = false },
    }
    coinBattle:DamageEnemy(coinBattle.enemies[1], 2, Config.COLORS.cursor, false)
    check(coinBattle.gold == 10 and #coinBattle.coinPickups > 0, "怪物死亡时金币不得立即入账，必须先生成飞行动画")
    coinBattle:UpdateVFX(2)
    check(coinBattle.gold == 13 and #coinBattle.coinPickups == 0, "金币飞到左侧HUD后才可完成入账")

    local boostedCoinBattle = Battle.New({ gold = 10, nextNight = 1, prestigeCount = 1,
        prestigeMilestone = 10, prestigeLevels = { p_root = 1 } })
    boostedCoinBattle:StartNight()
    boostedCoinBattle:AddGoldPickups(420, 280, 5)
    boostedCoinBattle:UpdateVFX(2)
    check(boostedCoinBattle.gold == 16 and closeTo(boostedCoinBattle:GetStats().goldGainBonus, 0.20),
        "黄金火种必须把怪物掉落的5金币提高到6，并在飞行动画结束后入账")

    local migrated = Battle.New({ inventory = { 1, 2 } })
    check(migrated.inventory[1].id == 1000 and migrated.inventory[2].id == 2000, "旧版存档装备编号应自动迁移")

    return "PASS " .. tostring(passed) .. " checks"
end

return SelfTest
