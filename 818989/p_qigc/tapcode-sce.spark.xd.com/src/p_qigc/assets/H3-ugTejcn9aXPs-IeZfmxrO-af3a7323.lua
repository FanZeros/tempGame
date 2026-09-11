-- ============================================================
-- Combat_Spawn.lua  —— 怪物生成/采集系统
-- 由 Combat.lua 拆分，通过 init(M) 挂载到主模块
-- ============================================================
local GS = require("GameState")
local BoardOverlay = require("BoardOverlay")

local sub = {}
-- 记录上次刷怪时的关卡，用于换图时重置稀有怪保底计数
local _pityStage = nil

function sub.init(M)

-- ====================================================================
-- 清除死亡怪物
-- ====================================================================
function M.removeDeadMonsters()
    -- 王子/公主死亡联动 buff（移除前检测）
    for _, dead in ipairs(GS.monsters) do
        if dead.hp <= 0 and not dead._deathBuffApplied then
            dead._deathBuffApplied = true
            if dead.image == "image/monster_slime_princess.png" then
                -- 公主死亡：王子获得 +130 攻击力 + 连击
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 and m.image == "image/monster_slime_prince.png" and not m._partnerDeathBuff then
                        m._partnerDeathBuff = true
                        m.atk = m.atk + 130
                        m.extraStrike = (m.extraStrike or 0) + 1
                        M.addDamageText(m.x, m.y - 0.5, "吾之挚爱...", {255, 100, 100})
                        M.addDamageText(m.x, m.y, "攻击力+130", {255, 80, 80})
                    end
                end
            elseif dead.image == "image/monster_slime_prince.png" then
                -- 王子死亡：公主获得 +130 攻击力 + 连击
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 and m.image == "image/monster_slime_princess.png" and not m._partnerDeathBuff then
                        m._partnerDeathBuff = true
                        m.atk = m.atk + 130
                        m.extraStrike = (m.extraStrike or 0) + 1
                        M.addDamageText(m.x, m.y - 0.5, "你会为此付出代价！", {255, 100, 100})
                        M.addDamageText(m.x, m.y, "攻击力+130", {255, 80, 80})
                    end
                end
            end
        end
    end
    -- 火史莱姆精锐死亡：生成尸体（2回合后爆炸）
    for _, dead in ipairs(GS.monsters) do
        if dead.hp <= 0 and dead.eliteType == "fire"
           and not dead._fireCorpseCreated then
            dead._fireCorpseCreated = true
            table.insert(GS.fireCorpses, {
                x = dead.x, y = dead.y,
                turns = 2,  -- 在原地存在2回合，第3回合（turns减到0时）爆炸
                realTimer = 0,  -- 实时计时器（秒），用于自由移动模式下5秒自动爆炸
                image = dead.image,
                color = {220, 80, 40},
                name = dead.name,
                level = dead.level or 45,   -- 保存等级，用于暴怒火史莱姆爆炸伤害缩放
                defId = dead.defId,         -- 保存 defId，区分暴怒/普通精锐
            })
            M.addDamageText(dead.x, dead.y - 0.5, "即将爆炸...", {255, 120, 40})
        end
    end
    -- 史莱姆王死亡：剩余怪物鸟兽散
    for _, dead in ipairs(GS.monsters) do
        if dead.hp <= 0 and dead.bossId == "slime_king" and not dead._fleeTriggered then
            dead._fleeTriggered = true
            for _, m in ipairs(GS.monsters) do
                if m.hp > 0 then
                    m.fleeing = true
                end
            end
            GS.setScreenShake(0.5, 3, 0)
            M.addDamageText(dead.x, dead.y, "史莱姆王倒下了!", {255, 220, 80})
            break
        end
    end

    -- 副本最终BOSS击杀：立即记录通关（不依赖阶段推进，防止竞技场出口逻辑跳过记录）
    if GS.isDungeon and GS.dungeonId then
        local bossToD = {
            slime_king         = "slime_kingdom",
            goblin_boss_dikata = "goblin_arena",
            tidal_boss_unknown = "tidal_sanctuary",
        }
        for _, dead in ipairs(GS.monsters) do
            if dead.hp <= 0 and not dead._dungeonClearTracked then
                local dungeonId = bossToD[dead.defId] or bossToD[dead.bossId]
                if dungeonId and dungeonId == GS.dungeonId then
                    dead._dungeonClearTracked = true
                    GS.trackDungeonClear(dungeonId)
                    print("[副本] BOSS击杀即通关: " .. (dead.name or dead.defId) .. " → " .. dungeonId)
                end
            end
        end
    end

    -- 先知夸迪死亡：清空引雷标记
    for _, dead in ipairs(GS.monsters) do
        if dead.hp <= 0 and dead.defId == "tidal_boss_kuadi" and not dead._lightningCleared then
            dead._lightningCleared = true
            GS.lightningWarnings = {}
            print("[夸迪] 死亡，清空引雷标记")
        end
    end

    -- 记录死亡特效数据（移除前采集位置/图片/尺寸信息）
    for _, dead in ipairs(GS.monsters) do
        if dead.hp <= 0 and not dead.isBrawlThug then
            local s = GS.unitSize(dead)
            -- 为每个死亡怪物生成随机粒子方向
            local particles = {}
            local pCount = math.random(6, 10)
            for pi = 1, pCount do
                local angle = math.random() * math.pi * 2
                local speed = 20 + math.random() * 30
                particles[pi] = {
                    ox = 0, oy = 0,
                    vx = math.cos(angle) * speed,
                    vy = math.sin(angle) * speed - 15,
                    size = 2 + math.random() * 3,
                }
            end
            -- 从伤害文字中获取延迟信息，死亡特效需等伤害数字显示后再播放
            local deathDelay = 0
            local deathPending = false
            local deathProjId = nil
            for _, d in ipairs(GS.damageTexts) do
                if d.x == dead.x and d.y == dead.y then
                    if d.pendingHit then
                        deathPending = true
                        deathProjId = d.projectileId  -- 继承最后一个pending伤害文字的弹道ID
                    end
                    if d.delay and d.delay > deathDelay then
                        deathDelay = d.delay
                    end
                end
            end
            table.insert(GS.deathEffects, {
                x = dead.x, y = dead.y,
                image = dead.image,
                unitScale = s,
                rarity = dead.rarity,
                timer = 0, duration = 0.55,
                particles = particles,
                delay = deathDelay,
                pendingHit = deathPending,
                projectileId = deathProjId,
            })
        end
    end

    -- 酒馆肉搏兜底：任何途径导致 hp<=0 的混混都不死亡，改为击晕
    for _, m in ipairs(GS.monsters) do
        if m.isBrawlThug and m.hp <= 0 then
            m.hp = 1
            if not m.brawlStunned then
                m.brawlStunned = true
                m.stunned = 9999
                M.addDamageText(m.x, m.y, "击晕!", {255, 200, 50})
            end
        end
    end

    for i = #GS.monsters, 1, -1 do
        if GS.monsters[i].hp <= 0 then
            table.remove(GS.monsters, i)
        end
    end

    -- ── 酒馆肉搏：检查混混全部击晕（转场中跳过，避免切换地图时误判胜利） ──
    if GS.tavernBrawlState and not GS.tavernBrawlState.done and not GS.sceneTransition then
        local standing, totalThugs = 0, 0  -- 未被击晕的混混数 / 混混总数
        for _, m in ipairs(GS.monsters) do
            if m.isBrawlThug then
                totalThugs = totalThugs + 1
                if not m.brawlStunned then standing = standing + 1 end
            end
        end
        if totalThugs == 0 then
            -- 混混全被清空（切换关卡/地图），中断肉搏任务
            print("[酒馆肉搏] removeDeadMonsters: 混混不存在，任务中断")
            GS.tavernBrawlState = nil
            GS.brawlCinematic = nil
            return
        end
        GS.tavernBrawlState.killCount = GS.tavernBrawlState.thugCount - standing
        if standing == 0 then
            GS.tavernBrawlState.done = true
            print("[酒馆肉搏] 全部混混击晕！questId: " .. GS.tavernBrawlState.questId)
            -- 立即弹出胜利对话 → 回到酒馆舞池 → 自动提交任务
            local DM_brawl = require("DialogueManager")
            local brawlVictoryDialogue
            if GS.tavernBrawlState.questId == "main_angelica_brawl_2" then
                brawlVictoryDialogue = {
                    { speaker = "安吉莉娅", text = "呀！怎么又打起来了！" },
                    { speaker = "安吉莉娅", text = "他们这几个人就会惹事，你下手还是太轻了。{玩家}，你没事吧？他们有没有伤到你？" },
                    { speaker = "安吉莉娅", text = "对不起，都是我害得你这样……我怎么总是成为麻烦？" },
                    { speaker = "旁白", text = "（安吉莉娅轻轻抚摸着你的伤口，心疼得看着你。你能感觉到那是出于真心的担忧。）" },
                    { speaker = "旁白", text = "（你对安吉莉娅的印象加深了，\"勿忘我\"效果提升！）" },
                }
            else
                brawlVictoryDialogue = {
                    { speaker = "安吉莉娅", text = "{玩家}，谢谢你，男人们一旦喝醉了总是这样。我……我什么都没有，不知道怎么感谢你好了，可以专为你舞一曲作为报答吗？" },
                    { speaker = "旁白", text = "（你对安吉莉娅的印象加深了，\"勿忘我\"效果提升！）" },
                }
            end
            -- ── 黑屏过渡：先淡入黑屏 → 黑屏上播放胜利对话 → 对话结束后淡出到舞池 ──
            GS.brawlCinematic = {
                phase = "fade_in",
                timer = 0,
                alpha = 0,
                FADE_IN  = 0.4,
                FADE_OUT = 0.5,
                onFadeInDone = function()
                    -- 黑屏下播放胜利对话
                    DM_brawl.startDynamic(brawlVictoryDialogue, function()
                        -- 对话结束 → 黑屏下切换场景
                        GS.burningGrounds = {}
                        GS.pendingBurningGrounds = {}
                        GS.fireCorpses = {}
                        GS.monsters = {}
                        GS.flushPendingMpRestores()
                        GS.damageTexts = {}

                        GS.currentBattleBg = "image/bg_grass.png"
                        GS.currentAreaName = "清水镇"
                        GS.currentStageName = "清水镇"
                        -- 回到清水镇酒馆舞池视角
                        BoardOverlay.show("town", "clearwater", "清水镇")
                        BoardOverlay.enterSubScene("tavern", true)  -- skipDialogue
                        BoardOverlay.tavernDanceView = true
                        -- 切换到舞池视频/背景
                        GS.dancerShowPhase = "performing"
                        BoardOverlay.startDancerIdleVideo()
                        if not GS.animationEnabled then
                            GS.dancerShowPhase = "done"
                        end
                        -- 自动提交任务（checkDone 需要 tavernBrawlState.done）
                        local QM_v = require("QuestManager")
                        QM_v.update()
                        print("[酒馆肉搏] 战斗结束，返回酒馆舞池")

                        -- 开始淡出（揭示舞池场景）
                        GS.brawlCinematic.phase = "fade_out"
                        GS.brawlCinematic.timer = 0
                    end)
                end,
            }
        end
    end
end

-- ====================================================================
-- 怪物生成
-- ====================================================================
--- 从当前关卡怪物列表中按权重随机选取一个怪物模板
---@param monsterList table
---@return table
local function pickMonsterEntry(monsterList)
    if #monsterList == 1 then return monsterList[1] end
    -- noBoss：过滤稀有品质（rare）区域首领
    local list = monsterList
    if GS.player and GS.player.noBoss and #monsterList > 1 then
        local filtered = {}
        for _, e in ipairs(monsterList) do
            if e.def.rarity ~= "rare" then
                filtered[#filtered + 1] = e
            end
        end
        if #filtered > 0 then list = filtered end
    end
    if #list == 1 then return list[1] end
    -- 场上已有稀有怪时，不再刷出新的稀有怪
    local hasRareOnBoard = false
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 and m.rarity == "rare" then
            hasRareOnBoard = true
            break
        end
    end
    if hasRareOnBoard and #list > 1 then
        local filtered = {}
        for _, e in ipairs(list) do
            if e.def.rarity ~= "rare" then
                filtered[#filtered + 1] = e
            end
        end
        if #filtered > 0 then list = filtered end
    end
    if #list == 1 then return list[1] end
    -- 稀有怪保底：连续击杀150只非稀有怪后，强制刷稀有怪
    if (GS.rareKillPitySince or 0) >= 150 then
        local rareEntries = {}
        for _, e in ipairs(list) do
            if e.def.rarity == "rare" then
                rareEntries[#rareEntries + 1] = e
            end
        end
        if #rareEntries > 0 then
            GS.rareKillPitySince = 0
            return rareEntries[math.random(#rareEntries)]
        end
    end
    local totalW = 0
    for _, e in ipairs(list) do totalW = totalW + (e.weight or 1) end
    local roll = math.random() * totalW
    for _, e in ipairs(list) do
        roll = roll - (e.weight or 1)
        if roll <= 0 then return e end
    end
    return list[#list]
end

--- 训练场：在棋盘中央刷新一个训练假人
function M.spawnTrainingDummy()
    local def = GS.MONSTER_DB.training_dummy
    if not def then return end
    local cx = math.floor(GS.BOARD_SIZE / 2) + 1
    local cy = math.floor(GS.BOARD_SIZE / 2) + 1  -- 中央偏下
    local monster = {
        x = cx, y = cy,
        defId = "training_dummy",
        name = def.name,
        level = def.level or 97,
        hp = def.hp, maxHp = def.maxHp,
        atk = def.atk, mAtk = def.mAtk, def = def.def, mdef = def.mdef or def.def,
        critVal = def.critVal or 0,
        critDmg = def.critDmg or 0,
        hit = def.hit or 0,
        dodge = def.dodge or 0,
        moveRange = 0, atkRange = 0,
        color = {def.color[1], def.color[2], def.color[3]},
        expReward = 0,
        rarity = def.rarity,
        image = def.image,
        isMonster = true, acted = true,  -- acted=true 让假人跳过行动
        noAffix = true,
        isTrainingDummy = true,
        facing = "down",
    }
    GS.monsters[#GS.monsters + 1] = monster
    -- 应用当前等级档位属性
    GS.applyDummyTier()
    print("=== 训练假人已刷新在 (" .. cx .. "," .. cy .. "), 等级档位: " .. GS.trainingDummyTierIdx .. " ===")
end

function M.spawnMonsters()
    -- 换图时重置稀有怪保底计数
    if _pityStage ~= GS.currentStage then
        _pityStage = GS.currentStage
        GS.rareKillPitySince = 0
    end
    -- 非战斗场景不刷怪（训练场、家、城镇等）
    if GS.trainingMode then return end
    if GS.homeMode then return end
    if BoardOverlay.isActive() then return end
    -- 酒馆肉搏模式下不刷新普通怪物
    if GS.tavernBrawlState then return end
    -- 读取当前关卡配置
    local stage = GS.STAGE_DEFS[GS.currentStage]
    if not stage then return end

    -- 动态怪物覆盖：红龙与魔女任务
    -- 接了任务且尚未完成时，城下深窟开阔区刷1只红龙幼龙；否则刷5只蛇尾狮
    local activeMonsters = stage.monsters
    local activeMaxMonsters = stage.maxMonsters
    local activeInitialCount = stage.initialMonsterCount
    if stage.dynamicMonsterOverride == "red_dragon_quest" then
        local QM = require("QuestManager")
        local st = QM.questStates["side_lina_manor_6"]
        if st and st.status == QM.STATUS_ACTIVE then
            -- 检查是否已击杀红龙幼龙（用 snapshot + monsterKillCounts 判断）
            local base = st.snapshot and st.snapshot.killCount or 0
            local killed = (GS.monsterKillCounts["red_dragon_young"] or 0) - base
            if killed < 1 then
                -- 尚未击杀：刷1只红龙幼龙
                activeMonsters = { { weight = 100, def = GS.MONSTER_DB.red_dragon_young } }
                activeMaxMonsters = 1
                activeInitialCount = 1
            end
            -- 已击杀过：使用默认的蛇尾狮配置
        end
        -- 任务未接或已完成：使用默认的蛇尾狮配置
    end

    -- 根据关卡配置计算刷怪数
    local thresholds = stage.spawnThresholds or {3, 8}
    local counts     = stage.spawnCounts or {1, 2, 3}
    local count = counts[1] or 1
    for i, th in ipairs(thresholds) do
        if GS.turnNumber > th then
            count = counts[i + 1] or count
        end
    end

    -- 装备加成：每次刷怪数量（可正可负，至少为1）
    if GS.player and (GS.player.spawnCountBonus or 0) ~= 0 then
        count = math.max(1, count + GS.player.spawnCountBonus)
    end

    -- 支持 initialMonsterCount：首次刷新时使用指定数量
    if activeInitialCount then
        local alive = 0
        for _, m in ipairs(GS.monsters) do
            if m.hp > 0 then alive = alive + 1 end
        end
        if alive == 0 and #GS.monsters == 0 then
            count = activeInitialCount
        end
    end

    local maxMon
    if stage.maxMonstersByLevel and #stage.maxMonstersByLevel > 0 and GS.player then
        local lvl = math.min(GS.player.level, #stage.maxMonstersByLevel)
        lvl = math.max(1, lvl)
        maxMon = stage.maxMonstersByLevel[lvl] or activeMaxMonsters or GS.MAX_MONSTERS
    else
        maxMon = activeMaxMonsters or GS.MAX_MONSTERS
    end
    -- 装备加成：怪物数量上限（可正可负，至少为1）
    if GS.player and (GS.player.maxMonstersBonus or 0) ~= 0 then
        maxMon = math.max(1, maxMon + GS.player.maxMonstersBonus)
    end
    local alive = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then alive = alive + 1 end
    end
    count = math.min(count, maxMon - alive)
    if count <= 0 then return end

    -- 固定出生点：优先使用关卡配置的固定位置
    local spawnEdge = {}
    if stage.fixedSpawnPos and #GS.monsters == 0 then
        for _, fp in ipairs(stage.fixedSpawnPos) do
            table.insert(spawnEdge, {fp[1], fp[2]})
        end
        -- 固定出生点不做随机打乱
        local spawned = 0
        for _, pos in ipairs(spawnEdge) do
            if spawned >= count then break end
            local entry = pickMonsterEntry(activeMonsters)
            local def = entry.def
            local monSize = def.size or 1
            if GS.isAreaEmpty(pos[1], pos[2], monSize) then
                local monster = {
                    x = pos[1], y = pos[2],
                    defId = def.id,
                    name = def.name .. " Lv." .. def.level,
                    level = def.level or 1,
                    hp = def.hp, maxHp = def.maxHp,
                    atk = def.atk, mAtk = def.mAtk, def = def.def, mdef = def.mdef or def.def,
                    critVal = def.critVal or 0,
                    critDmg = def.critDmg or 50,
                    hit = def.hit or 0,
                    dodge = def.dodge or 0,
                    atkSpeed = def.atkSpeed or 1,
                    moveRange = def.moveRange, atkRange = def.atkRange,
                    color = {def.color[1], def.color[2], def.color[3]},
                    expReward = def.expReward or 0,
                    rarity = def.rarity,
                    image = def.image,
                    drops = entry.drops or def.drops,
                    ai = def.ai,
                    size = def.size,
                    eliteType = def.eliteType,
                    knockbackDist = def.knockbackDist,
                    knockbackWallDmg = def.knockbackWallDmg,
                    summonEliteInterval = def.summonEliteInterval,
                    bossId = def.bossId,
                    weaponTag = def.weaponTag,
                    extraStrike = def.extraStrike,
                    gatekeeperFlashCD = def.gatekeeperFlashCD,
                    gatekeeperFlashRange = def.gatekeeperFlashRange,
                    gatekeeperFlashAtkSpd = def.gatekeeperFlashAtkSpd,
                    atkAttr = def.atkAttr,
                    noAffix = def.noAffix,
                    resistance = def.resistance,
                    weakness = def.weakness,
                    immortal = def.immortal,
                    isAbyss = def.isAbyss,
                    isMonster = true, acted = false,
                    justSpawned = true,
                    facing = GS.facingToCenter(pos[1], pos[2]),
                }
                table.insert(GS.monsters, monster)
                spawned = spawned + 1
            end
        end
        return  -- 固定出生点处理完毕，直接返回
    end

    -- 收集刷怪空位
    if stage.spawnAnywhere then
        -- 采集区关卡：全图随机位置
        for gx = 1, GS.BOARD_SIZE do
            for gy = 1, GS.BOARD_SIZE do
                table.insert(spawnEdge, {gx, gy})
            end
        end
    else
        -- 常规关卡：边缘位置
        for i = 1, GS.BOARD_SIZE do
            table.insert(spawnEdge, {i, 1})
            table.insert(spawnEdge, {i, GS.BOARD_SIZE})
            table.insert(spawnEdge, {1, i})
            table.insert(spawnEdge, {GS.BOARD_SIZE, i})
        end
    end
    for i = #spawnEdge, 2, -1 do
        local j = math.random(1, i)
        spawnEdge[i], spawnEdge[j] = spawnEdge[j], spawnEdge[i]
    end

    local spawned = 0
    for _, pos in ipairs(spawnEdge) do
        if spawned >= count then break end
        local entry = pickMonsterEntry(activeMonsters)
        local def = entry.def
        local monSize = def.size or 1
        if GS.isAreaEmpty(pos[1], pos[2], monSize) then
            local monster = {
                x = pos[1], y = pos[2],
                defId = def.id,
                name = def.name .. " Lv." .. def.level,
                level = def.level or 1,
                hp = def.hp, maxHp = def.maxHp,
                atk = def.atk, mAtk = def.mAtk, def = def.def, mdef = def.mdef or def.def,
                critVal = def.critVal or 0,
                critDmg = def.critDmg or 50,
                hit = def.hit or 0,
                dodge = def.dodge or 0,
                atkSpeed = def.atkSpeed or 1,
                moveRange = def.moveRange, atkRange = def.atkRange,
                color = {def.color[1], def.color[2], def.color[3]},
                expReward = def.expReward or 0,
                rarity = def.rarity,
                image = def.image,
                drops = entry.drops or def.drops,
                ai = def.ai,
                size = def.size,
                eliteType = def.eliteType,
                knockbackDist = def.knockbackDist,
                knockbackWallDmg = def.knockbackWallDmg,
                summonEliteInterval = def.summonEliteInterval,
                bossId = def.bossId,
                weaponTag = def.weaponTag,
                extraStrike = def.extraStrike,
                gatekeeperFlashCD = def.gatekeeperFlashCD,
                gatekeeperFlashRange = def.gatekeeperFlashRange,
                gatekeeperFlashAtkSpd = def.gatekeeperFlashAtkSpd,
                atkAttr = def.atkAttr,
                noAffix = def.noAffix,
                resistance = def.resistance,
                weakness = def.weakness,
                immortal = def.immortal,
                isAbyss = def.isAbyss,
                isMonster = true, acted = false,
                justSpawned = true,
                facing = GS.facingToCenter(pos[1], pos[2]),
            }
            -- 掉落组：从掉落组中等概率随机选一个，按 dropGroupChance 概率掉落
            if def.dropGroup and GS[def.dropGroup] then
                local pool = GS[def.dropGroup]
                local dropId = pool[math.random(#pool)]
                -- 根据装备自身等级计算 tier，使掉落装备有概率附带附魔和精炼槽
                local tpl = GS.itemTemplates[dropId]
                local dropTier = GS.getTierByLevel(tpl and tpl.level or 1)
                local dropChance = def.dropGroupChance or 1.0
                monster.drops = { { id = dropId, chance = dropChance, enchantTier = dropTier, isAbyssDrop = def.isAbyss or false, isRareDrop = (not def.isAbyss) or nil, isChestGoblinDrop = (def.dropGroup == "DROP_GROUP_CHEST_GOBLIN") or nil } }
                -- dropGroup 怪物也保留 def.drops 中的额外掉落（如生肉）
                if def.drops then
                    for _, d in ipairs(def.drops) do
                        monster.drops[#monster.drops + 1] = d
                    end
                end
            end
            -- 属性随机浮动（深渊等关卡配置 statVariance 时生效）
            if stage.statVariance and stage.statVariance > 0 then
                local sv = stage.statVariance
                local function vary(v)
                    return math.floor(v * (1 - sv + math.random() * sv * 2) + 0.5)
                end
                monster.hp     = vary(monster.hp)
                monster.maxHp  = monster.hp
                monster.atk    = vary(monster.atk)
                monster.mAtk   = vary(monster.mAtk)
                monster.def    = vary(monster.def)
                monster.mdef   = vary(monster.mdef)
                monster.critVal = math.floor(monster.critVal * (1 - sv + math.random() * sv * 2) * 100 + 0.5) / 100
                monster.hit     = math.floor(monster.hit    * (1 - sv + math.random() * sv * 2) * 100 + 0.5) / 100
                monster.dodge   = math.floor(monster.dodge  * (1 - sv + math.random() * sv * 2) * 100 + 0.5) / 100
            end
            -- 5% 概率附加随机词缀（noAffix 怪物跳过；采集区不出词缀怪）
            if not def.noAffix and not stage.noRespawn and math.random() < 0.05 and #GS.MONSTER_AFFIXES > 0 then
                local affix = GS.MONSTER_AFFIXES[math.random(#GS.MONSTER_AFFIXES)]
                affix.apply(monster)
                monster.name = affix.name .. " " .. monster.name
                if not def.isAbyss then
                    monster.rarity = GS.RARITY_UP[monster.rarity] or monster.rarity
                end
                monster.expReward = math.floor(monster.expReward * 1.5)
                monster.affix = affix.name
                -- 词缀怪额外掉落：浅拷贝 drops 后追加
                local newDrops = {}
                for _, d in ipairs(monster.drops or {}) do
                    newDrops[#newDrops + 1] = d
                end
                local mLv = monster.level or 1
                -- 根据怪物等级分档：<30 级 100% / <50 级 66% / >=50 级 30%
                local baseChance = mLv < 30 and 1.0 or (mLv < 50 and 0.66 or 0.30)
                -- 富有的词缀掉落件数：<30 级 3件 / <50 级 2件 / >=50 级 1件
                local dropCount = monster.guaranteeDrop and (mLv < 30 and 3 or (mLv < 50 and 2 or 1)) or 1
                local dropChance = monster.guaranteeDrop and 1.0 or baseChance
                if def.isAbyss then
                    -- 深渊词缀怪：额外掉落深渊装备（从 ABYSS_BASIC_DROP_POOL 随机）
                    local pool = GS.ABYSS_BASIC_DROP_POOL
                    for _ = 1, dropCount do
                        local dropId = pool[math.random(#pool)]
                        local tpl = GS.itemTemplates[dropId]
                        local dropTier = GS.getTierByLevel(tpl and tpl.level or 1)
                        newDrops[#newDrops + 1] = { id = dropId, chance = dropChance, enchantTier = dropTier, isAbyssDrop = true }
                    end
                else
                    for _ = 1, dropCount do
                        local dropId, dropTier = GS.rollFieldBasicDrop(mLv)
                        newDrops[#newDrops + 1] = { id = dropId, chance = dropChance, enchantTier = dropTier }
                    end
                end
                monster.drops = newDrops
            end
            table.insert(GS.monsters, monster)
            spawned = spawned + 1
        end
    end
end

-- ====================================================================
-- 采集物刷新
-- ====================================================================
function M.spawnGatherables()
    local spawns = GS.STAGE_GATHER_SPAWNS[GS.currentStage]
    if not spawns then return end

    -- 优先恢复已保存的采集物状态（玩家之前离开过该关卡）
    -- 注意：直接内联检查，避免跨模块函数调用可能的加载顺序问题
    local saved = type(GS.gatherStageStates) == "table" and GS.gatherStageStates[GS.currentStage] or nil
    if saved then
        -- 兼容新格式 { alive = {...}, depleted = bool } 和旧格式（纯数组）
        local aliveList = saved.alive or saved
        -- 全部采完：不生成任何采集物，直接返回
        if saved.depleted or #aliveList == 0 then
            GS.gatherables = {}
            GS._currentGatherStage = GS.currentStage
            print("[采集] 关卡 " .. GS.currentStage .. " 已采完，等待重置")
            return
        end
        -- 恢复保存的采集物（只在确实有剩余采集物时才恢复）
        GS.gatherables = {}
        for _, s in ipairs(aliveList) do
            local def = GS.GATHER_DEFS[s.defId]
            if def then
                local gatherable = {
                    x           = s.x,
                    y           = s.y,
                    defId       = def.id,
                    name        = def.name,
                    image       = GS.getGatherImage(def.id, GS.currentStage) or def.image,
                    areaTag     = GS.STAGE_GATHER_AREA[GS.currentStage],
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
                table.insert(GS.gatherables, gatherable)
            end
        end
        GS._currentGatherStage = GS.currentStage
        print("[采集] 恢复关卡 " .. GS.currentStage .. " 状态：" .. #GS.gatherables .. " 个采集物")
        return
    end

    -- 构建权重池
    local pool = {}
    local totalWeight = 0
    for _, entry in ipairs(spawns) do
        local w = entry.weight or 100
        pool[#pool + 1] = { defId = entry.defId, weight = w }
        totalWeight = totalWeight + w
    end
    if #pool == 0 or totalWeight <= 0 then return end

    local totalCount = spawns.count or 5

    for _ = 1, totalCount do
        -- 按权重随机选择品种
        local roll = math.random() * totalWeight
        local acc = 0
        local selectedDefId = pool[1].defId
        for _, p in ipairs(pool) do
            acc = acc + p.weight
            if roll <= acc then
                selectedDefId = p.defId
                break
            end
        end

        local def = GS.GATHER_DEFS[selectedDefId]
        if not def then goto continue end

        -- 随机选择空位（避开边缘2格，让采集物分布在内部区域）
        local candidates = {}
        for gx = 2, GS.BOARD_SIZE - 1 do
            for gy = 2, GS.BOARD_SIZE - 1 do
                if GS.isCellEmpty(gx, gy) then
                    candidates[#candidates + 1] = {gx, gy}
                end
            end
        end
        if #candidates == 0 then break end

        local pos = candidates[math.random(#candidates)]
        local gatherable = {
            x           = pos[1],
            y           = pos[2],
            defId       = def.id,
            name        = def.name,
            image       = GS.getGatherImage(def.id, GS.currentStage) or def.image,
            areaTag     = GS.STAGE_GATHER_AREA[GS.currentStage],
            itemId          = def.itemId,
            drops           = def.drops,
            rarityVariants  = def.rarityVariants,
            gatherTime  = def.gatherTime,
            color       = {def.color[1], def.color[2], def.color[3]},
            rarity      = def.rarity,
            lifeSkill   = def.lifeSkill,
            hiddenLevel = def.hiddenLevel or 0,
            isGatherable = true,
            harvestsLeft = 3,
        }
        table.insert(GS.gatherables, gatherable)

        ::continue::
    end
    if #GS.gatherables > 0 then
        GS._currentGatherStage = GS.currentStage
        print("[采集] 刷新了 " .. #GS.gatherables .. " 个采集物")
    end
end

--- 采集完成处理（由 main.lua 计时器到时后调用）
function M.finishGathering()
    local gs = GS.gatheringState
    if not gs then return end

    local target = gs.target
    -- 使用闪烁阶段预判的结果（如果有），否则现场随机
    local success = gs._result
    if success == nil then
        success = math.random() <= gs.successRate
    end

    if success then
        -- 采集成功：消耗采集次数，次数耗尽播放消失动画
        target.harvestsLeft = (target.harvestsLeft or 1) - 1
        if target.harvestsLeft <= 0 then
            target.vanishing = true
            target.vanishTimer = 0
            target.vanishDuration = 0.6
            -- 生成扩散粒子
            target.vanishParticles = {}
            local rarityDef = GS.RARITY[target.rarity or "common"]
            local gc = rarityDef and rarityDef.color or {200, 200, 200}
            for pi = 1, 10 do
                local angle = (pi - 1) / 10 * math.pi * 2 + math.random() * 0.3
                table.insert(target.vanishParticles, {
                    angle = angle,
                    speed = 40 + math.random() * 30,
                    size  = 2 + math.random() * 2,
                    r = math.min(255, gc[1] + math.random(-20, 40)),
                    g = math.min(255, gc[2] + math.random(-20, 40)),
                    b = math.min(255, gc[3] + math.random(-20, 40)),
                })
            end
        end
        -- 概率掉落：drops（矿物多品种）> rarityVariants（植物稀有度变种）> 固定 itemId
        local dropItemId = target.itemId
        if target.drops and #target.drops > 0 then
            local totalWeight = 0
            for _, d in ipairs(target.drops) do
                totalWeight = totalWeight + (d.weight or 1)
            end
            local roll = math.random() * totalWeight
            local acc = 0
            for _, d in ipairs(target.drops) do
                acc = acc + (d.weight or 1)
                if roll <= acc then
                    dropItemId = d.itemId
                    break
                end
            end
        elseif target.rarityVariants and #target.rarityVariants > 0 then
            -- 植物稀有度变种：按权重随机选择不同稀有度的产出物
            local totalWeight = 0
            for _, v in ipairs(target.rarityVariants) do
                totalWeight = totalWeight + (v.weight or 1)
            end
            local roll = math.random() * totalWeight
            local acc = 0
            for _, v in ipairs(target.rarityVariants) do
                acc = acc + (v.weight or 1)
                if roll <= acc then
                    dropItemId = v.itemId
                    break
                end
            end
        end
        local ok, msg = GS.addToInventory(dropItemId, 1)
        -- 显示实际掉落物名称
        local dropItemName = target.name
        local dropTpl = GS.itemTemplates and GS.itemTemplates[dropItemId]
        if dropTpl then dropItemName = dropTpl.name end
        M.addDamageText(target.x, target.y, "成功！", {80, 220, 80})
        GS.gatherResultAnim = {
            x = target.x, y = target.y,
            success = true, timer = 0, duration = 1.0,
            itemName = dropItemName, itemId = dropItemId,
        }
        if not ok then
            M.addDamageText(target.x, target.y, msg or "背包已满", {255, 100, 80})
        end
        print("[采集] 成功采集 " .. dropItemName)

        -- 采集经验获取（仅成功时）
        local lifeSkillId = target.lifeSkill
        if lifeSkillId then
            local playerHLv = GS.getLifeSkillHiddenLevel(lifeSkillId)
            local gatherHLv = target.hiddenLevel or 0
            local diff = playerHLv - gatherHLv
            local expGain = 0
            -- 低成功率（<50%）采集成功时，获得2点经验
            if (gs.successRate or 1) < 0.50 then
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
            if expGain > 0 then
                local curExp = (GS.lifeSkillExp[lifeSkillId] or 0) + expGain
                local curTier = GS.lifeSkillTiers[lifeSkillId] or 1
                if curExp >= GS.LIFE_SKILL_MAX_LEVEL and curTier < GS.LIFE_SKILL_MAX_TIER then
                    curExp = curExp - GS.LIFE_SKILL_MAX_LEVEL
                    curTier = curTier + 1
                    GS.lifeSkillTiers[lifeSkillId] = curTier
                    local tierDef = GS.LIFE_SKILL_TIERS[curTier]
                    local skillName = lifeSkillId
                    for _, def in ipairs(GS.LIFE_SKILL_DEFS) do
                        if def.id == lifeSkillId then skillName = def.name; break end
                    end
                    M.addDamageText(target.x, target.y, skillName .. " 升阶: " .. tierDef.name, tierDef.col)
                    print("[生活技能] " .. skillName .. " 升阶至 " .. tierDef.name)
                elseif curTier >= GS.LIFE_SKILL_MAX_TIER then
                    curExp = math.min(curExp, GS.LIFE_SKILL_MAX_LEVEL)
                end
                GS.lifeSkillExp[lifeSkillId] = curExp
                local skillName2 = lifeSkillId
                for _, def in ipairs(GS.LIFE_SKILL_DEFS) do
                    if def.id == lifeSkillId then skillName2 = def.name; break end
                end
                M._damageTextDelay = 0.5
                M.addDamageText(target.x, target.y, skillName2 .. " 经验+" .. expGain, {180, 140, 30})
                M._damageTextDelay = 0
                print("[生活技能] " .. lifeSkillId .. " 经验 +" .. expGain .. " → " .. curExp .. "/" .. GS.LIFE_SKILL_MAX_LEVEL)
            end
        end
    else
        if gs._zeroRate then
            -- 等级不足：采集物不消失，显示红色提示
            M.addDamageText(target.x, target.y, "你的经验对这个采集物感到束手无策", {220, 50, 50})
            GS.gatherResultAnim = {
                x = target.x, y = target.y,
                success = false, timer = 0, duration = 1.0,
                itemName = target.name,
            }
            print("[采集] 等级不足，无法采集 " .. target.name)
        else
            -- 正常采集失败：消耗采集次数，次数耗尽播放消失动画
            target.harvestsLeft = (target.harvestsLeft or 1) - 1
            if target.harvestsLeft <= 0 then
                target.vanishing = true
                target.vanishTimer = 0
                target.vanishDuration = 0.6
                target.vanishParticles = {}
                local rarityDef = GS.RARITY[target.rarity or "common"]
                local gc = rarityDef and rarityDef.color or {200, 200, 200}
                for pi = 1, 10 do
                    local angle = (pi - 1) / 10 * math.pi * 2 + math.random() * 0.3
                    table.insert(target.vanishParticles, {
                        angle = angle,
                        speed = 40 + math.random() * 30,
                        size  = 2 + math.random() * 2,
                        r = math.min(255, gc[1] + math.random(-20, 40)),
                        g = math.min(255, gc[2] + math.random(-20, 40)),
                        b = math.min(255, gc[3] + math.random(-20, 40)),
                    })
                end
            end
            M.addDamageText(target.x, target.y, "失败！", {220, 50, 50})
            GS.gatherResultAnim = {
                x = target.x, y = target.y,
                success = false, timer = 0, duration = 0.8,
                itemName = target.name,
            }
            -- 采集失败时：根据成功率概率获得1点经验（上限50%）
            local lifeSkillId2 = target.lifeSkill
            if lifeSkillId2 then
                local failExpChance = math.min(0.50, gs.successRate or 0)
                if failExpChance > 0 and math.random() <= failExpChance then
                    local curExp = (GS.lifeSkillExp[lifeSkillId2] or 0) + 1
                    local curTier = GS.lifeSkillTiers[lifeSkillId2] or 1
                    if curExp >= GS.LIFE_SKILL_MAX_LEVEL and curTier < GS.LIFE_SKILL_MAX_TIER then
                        curExp = curExp - GS.LIFE_SKILL_MAX_LEVEL
                        curTier = curTier + 1
                        GS.lifeSkillTiers[lifeSkillId2] = curTier
                        local tierDef = GS.LIFE_SKILL_TIERS[curTier]
                        local skillName = lifeSkillId2
                        for _, def in ipairs(GS.LIFE_SKILL_DEFS) do
                            if def.id == lifeSkillId2 then skillName = def.name; break end
                        end
                        M.addDamageText(target.x, target.y, skillName .. " 升阶: " .. tierDef.name, tierDef.col)
                    elseif curTier >= GS.LIFE_SKILL_MAX_TIER then
                        curExp = math.min(curExp, GS.LIFE_SKILL_MAX_LEVEL)
                    end
                    GS.lifeSkillExp[lifeSkillId2] = curExp
                    local skillName2 = lifeSkillId2
                    for _, def in ipairs(GS.LIFE_SKILL_DEFS) do
                        if def.id == lifeSkillId2 then skillName2 = def.name; break end
                    end
                    M._damageTextDelay = 0.5
                    M.addDamageText(target.x, target.y, skillName2 .. " 经验+1", {180, 140, 30})
                    M._damageTextDelay = 0
                    print("[生活技能] 采集失败但获得经验: " .. lifeSkillId2 .. " +1")
                end
            end
            print("[采集] 采集失败")
        end
    end

    GS.gatheringState = nil

    -- 结束玩家回合
    if GS.selectedUnit then
        GS.selectedUnit.acted = true
    end
    GS.selectedUnit = nil
    GS.movableCells = {}
    GS.attackableCells = {}
    GS.closeActionMenu()
    M.endPlayerTurn()
end

end -- sub.init

return sub
