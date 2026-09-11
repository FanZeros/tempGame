--- 副本管理器
local GS = require("GameState")
local Combat -- 延迟加载，避免循环引用

local M = {}

-- 副本注册表
local dungeonDefs = {
    slime_kingdom    = require("Dungeon.SlimeKingdom"),
    goblin_arena     = require("Dungeon.GoblinArena"),
    tidal_sanctuary  = require("Dungeon.TidalSanctuary"),
}

-- 当前副本引用
local currentDungeon = nil

-- 底部居中4格（副本出生/复活位置）
-- 注意：棋盘坐标 y=1 是屏幕顶部，y=BOARD_SIZE 是屏幕底部
local BS = GS.BOARD_SIZE
local BOTTOM_SPAWN_CELLS = {
    { 6, BS }, { 7, BS },
    { 6, BS - 1 }, { 7, BS - 1 },
}

---------------------------------------------------------------------------
-- 内部：从怪物定义创建怪物实例
---------------------------------------------------------------------------
local function createMonster(def, x, y)
    return {
        x = x, y = y,
        defId = def.id,
        name = def.name .. " Lv." .. def.level,
        level = def.level or 1,
        hp = def.hp, maxHp = def.hp,
        atk = def.atk, mAtk = def.mAtk, def = def.def, mdef = def.mdef or def.def,
        atkSpeed = def.atkSpeed or 0,
        critVal = def.critVal or 0,
        critDmg = def.critDmg or 50,
        hit = def.hit or 0,
        dodge = def.dodge or 0,
        moveRange = def.moveRange, atkRange = def.atkRange,
        color = { def.color[1], def.color[2], def.color[3] },
        expReward = def.expReward or 0,
        rarity = def.rarity,
        image = def.image,
        drops = def.drops,
        ai = def.ai,
        size = def.size,
        eliteType = def.eliteType,
        knockbackDist = def.knockbackDist,
        knockbackWallDmg = def.knockbackWallDmg,
        summonEliteInterval = def.summonEliteInterval,
        bossId = def.bossId,
        isMonster = true, acted = false,
        facing = GS.facingToCenter(x, y),
    }
end

---------------------------------------------------------------------------
-- 内部：收集可用生成位置
---------------------------------------------------------------------------
local function collectSpawnCells(mode)
    local cells = {}
    if mode == "top" then
        -- 仅屏幕顶边 (y = 1)
        for i = 1, GS.BOARD_SIZE do
            if GS.isCellEmpty(i, 1) then
                cells[#cells + 1] = { i, 1 }
            end
        end
    else
        -- 四条边
        for i = 1, GS.BOARD_SIZE do
            if GS.isCellEmpty(i, 1) then cells[#cells + 1] = { i, 1 } end
            if GS.isCellEmpty(i, GS.BOARD_SIZE) then cells[#cells + 1] = { i, GS.BOARD_SIZE } end
            if GS.isCellEmpty(1, i) then cells[#cells + 1] = { 1, i } end
            if GS.isCellEmpty(GS.BOARD_SIZE, i) then cells[#cells + 1] = { GS.BOARD_SIZE, i } end
        end
    end
    -- 随机打乱
    for i = #cells, 2, -1 do
        local j = math.random(1, i)
        cells[i], cells[j] = cells[j], cells[i]
    end
    return cells
end

---------------------------------------------------------------------------
-- 内部：在边缘找一对水平相邻的空格（用于并排刷新 Boss）
---------------------------------------------------------------------------
local function findAdjacentPair(mode)
    local cells = collectSpawnCells(mode)
    -- 对每个候选格，检查右侧是否也空
    for _, c in ipairs(cells) do
        local nx = c[1] + 1
        if nx <= GS.BOARD_SIZE and GS.isCellEmpty(nx, c[2]) then
            return { c, { nx, c[2] } }
        end
    end
    -- 退化：随机取两个格
    if #cells >= 2 then
        return { cells[1], cells[2] }
    end
    return nil
end

---------------------------------------------------------------------------
-- 内部：统计场上存活怪物数
---------------------------------------------------------------------------
local function countAlive()
    local n = 0
    for _, m in ipairs(GS.monsters) do
        if m.hp > 0 then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- 公共接口
---------------------------------------------------------------------------

--- 进入副本
function M.enter(dungeonId)
    currentDungeon = dungeonDefs[dungeonId]
    if not currentDungeon then
        print("[DungeonManager] Unknown dungeon: " .. tostring(dungeonId))
        return
    end
    GS.isDungeon = true
    GS.dungeonId = dungeonId
    GS.dungeonPhase = 1
    GS.dungeonCheckpoint = 0
    GS.dungeonSpawnCount = 0
    GS.dungeonWaveIndex = 0
    GS.dungeonPhaseComplete = false
    GS.dungeonPhaseTurn = 0
    -- 确保竞技场过渡状态完全清空（防止上次副本残留状态导致第二关为空）
    GS.arenaTransition = nil
    GS.dungeonScrollAnim = nil
    GS.arenaWaitForExit = false
    GS.arenaDungeonCleared = false
    GS.arenaExitTiles = nil
    GS.arenaExitPending = false
    GS.arenaPendingTarget = nil
    print("=== 进入副本: " .. currentDungeon.name .. " ===")
    print("=== 阶段 1: " .. currentDungeon.phases[1].name .. " ===")
end

--- 是否正在副本中
function M.isActive()
    return GS.isDungeon and currentDungeon ~= nil
end

--- 获取当前阶段定义
function M.getPhase()
    if not currentDungeon then return nil end
    return currentDungeon.phases[GS.dungeonPhase]
end

--- 获取玩家出生/复活位置
function M.getPlayerSpawnCells()
    -- 副本自定义重生点优先
    if currentDungeon and currentDungeon.playerSpawn then
        local sp = currentDungeon.playerSpawn
        return { { sp.x, sp.y } }
    end
    return BOTTOM_SPAWN_CELLS
end

--- 检查当前阶段是否完成，若完成则推进到下一阶段
--- @return boolean 是否发生了阶段切换
function M.checkPhaseComplete()
    if not M.isActive() then return false end
    local phase = M.getPhase()
    if not phase then return false end

    -- 条件：所有怪物已生成完毕 且 场上无存活怪物
    if not GS.dungeonPhaseComplete then return false end
    if countAlive() > 0 then return false end

    -- 竞技场：等待玩家踩绿色出口格子后才推进（已在等待中则跳过）
    if GS.arenaWaitForExit then return false end
    if currentDungeon and currentDungeon.arenaTransition then
        -- 进入等待出口状态，不立即推进
        GS.arenaWaitForExit = true
        GS.arenaExitTiles = { {x = 6, y = 1}, {x = 7, y = 1} }
        GS.topBarLockedTarget = nil
        -- 检测是否为最终阶段（下一阶段不存在）：标记通关
        local nextIdx = GS.dungeonPhase + 1
        if not currentDungeon.phases[nextIdx] then
            GS.arenaDungeonCleared = true
            print("=== 竞技场最终阶段完成，副本通关！等待玩家踩出口 ===")
        else
            print("=== 竞技场阶段完成，等待玩家踩出口 ===")
        end
        return false
    end

    -- === 非竞技场：直接阶段通关 ===
    return M.advancePhase(phase)
end

--- 实际推进阶段（从绿色出口触发或非竞技场自动触发）
function M.advancePhase(phase)
    phase = phase or M.getPhase()

    -- 存检查点
    if phase and phase.checkpoint then
        GS.dungeonCheckpoint = GS.dungeonPhase
        print("=== 检查点已保存: 阶段 " .. GS.dungeonPhase .. " ===")
    end

    -- 推进
    GS.dungeonPhase = GS.dungeonPhase + 1
    GS.dungeonSpawnCount = 0
    GS.dungeonWaveIndex = 0
    GS.dungeonPhaseComplete = false
    GS.dungeonPhaseTurn = 0
    GS.lastPlayerTarget = nil
    GS.topBarLockedTarget = nil
    GS.monsters = {}
    GS.companions = {}
    GS.fireCorpses = {}

    local nextPhase = M.getPhase()
    if not nextPhase then
        -- 副本通关：保持 isDungeon=true，不再刷怪
        print("=== 副本通关: " .. currentDungeon.name .. " ===")
        -- 记录副本通关（用于冒险者等级晋升条件）
        if GS.dungeonId then
            GS.trackDungeonClear(GS.dungeonId)
        end
        return true
    end

    -- 施法职业副本阶段推进时重置吟唱段数（充能交由 startPlayerTurn 统一处理，避免叠加）
    if (GS.currentClass == "mage" or GS.currentClass == "priest") and GS.player and GS.player.hp > 0 then
        GS.chantStages = 0
        GS.chantStagesMax = 0
        GS._chantPendingReset = true  -- 标记覆盖（而非叠加），由 startPlayerTurn 充能
    end

    -- 竞技场过场：上一阶段有 arenaAnnounce 时启动过场序列
    if phase and phase.arenaAnnounce and currentDungeon.arenaTransition then
        local trans = currentDungeon.arenaTransition
        if trans.scrollMode then
            -- 滚动模式过场：棋盘整体向下滚动，而非走位过场
            -- 先清除猎犬（滚动结束后重新生成）
            for i = #GS.companions, 1, -1 do
                if GS.companions[i].isHound then
                    table.remove(GS.companions, i)
                end
            end
            -- 启动棋盘滚动动画
            if GS.player and GS.player.hp > 0 then
                local targetY = GS.BOARD_SIZE
                local deltaY = targetY - GS.player.y
                if deltaY > 0 then
                    GS.dungeonScrollAnim = {
                        targetX = GS.player.x,
                        targetY = targetY,
                        totalOffset = deltaY * GS.CELL,
                        timer = 0,
                        duration = 0.6,
                        scrollModeTransition = true,  -- 标记：滚动结束后需刷怪+开始玩家回合
                        announce = phase.arenaAnnounce,
                    }
                else
                    -- 玩家已在底部，无需滚动，走统一的 arenaTransition 对话流程
                    GS.spawnHound()
                    M.spawnForPhase()
                    local newPhase = M.getPhase()
                    GS.arenaTransition = {
                        step = "dialogue",
                        timer = 0,
                        isScrollTransition = true,
                        announce = phase.arenaAnnounce,
                    }
                    -- 如果新阶段没有对话也没有默认播报，直接进入 done
                    if not (newPhase and newPhase.phaseDialogue and #newPhase.phaseDialogue > 0)
                       and not phase.arenaAnnounce then
                        GS.arenaTransition.step = "done"
                    end
                end
            end
            print("=== 棋盘滚动过场开始: 下一阶段 " .. phase.arenaAnnounce .. " ===")
        else
            -- 标准竞技场过场：走位 + 对话
            GS.arenaTransition = {
                step = "player_move",     -- 当前步骤
                timer = 0,
                playerTarget = trans.playerReset,
                enemySpawn   = trans.enemySpawn,
                enemyTarget  = trans.enemyTarget,
                announce     = phase.arenaAnnounce,
                enemy = nil,              -- 过场中刷出的预览敌人
            }
            print("=== 竞技场过场开始: 下一对手 " .. phase.arenaAnnounce .. " ===")
        end
    end

    -- 非竞技场/非滚动过场：立即重新生成猎犬（竞技场过场在 done 步骤中生成，滚动过场在滚动结束后生成）
    if not GS.arenaTransition and not GS.dungeonScrollAnim then
        GS.spawnHound()
    end

    print("=== 阶段 " .. GS.dungeonPhase .. ": " .. nextPhase.name .. " ===")
    return true
end

--- 竞技场：玩家踩到绿色出口时调用
function M.triggerArenaExit()
    if not GS.arenaWaitForExit then return false end
    local phase = M.getPhase()
    -- 清除等待状态
    GS.arenaWaitForExit = false
    GS.arenaExitTiles = nil
    -- 清除残留宝箱
    GS.arenaChests = {}
    GS.arenaChestInteract = nil
    GS.arenaChestPending = nil
    GS.arenaExitPending = false
    -- 清除燃烧地面，不保留到下一关
    GS.burningGrounds = {}
    -- 执行阶段推进
    return M.advancePhase(phase)
end

--- 按当前阶段规则刷怪
function M.spawnForPhase()
    if not M.isActive() then return end
    if GS.dungeonPhaseComplete then return end

    local phase = M.getPhase()
    if not phase then return end

    GS.dungeonPhaseTurn = GS.dungeonPhaseTurn + 1

    -- ====== Boss 阶段：立即生成所有 Boss ======
    if phase.bosses then
        if phase.bossSpawnPositions then
            -- 固定位置刷新：按 bosses 数组顺序对应 bossSpawnPositions
            for i, def in ipairs(phase.bosses) do
                local pos = phase.bossSpawnPositions[i]
                if pos then
                    local monster = createMonster(def, pos.x, pos.y)
                    table.insert(GS.monsters, monster)
                    print("  BOSS[" .. i .. "] " .. (def.name or "?") .. " 固定刷新于 (" .. pos.x .. "," .. pos.y .. ")")
                end
            end
        elseif phase.adjacentBosses and #phase.bosses == 2 then
            -- 并排刷新：找一对相邻空格
            local pair = findAdjacentPair(phase.spawnMode or "edge")
            if pair then
                local m1 = createMonster(phase.bosses[1], pair[1][1], pair[1][2])
                local m2 = createMonster(phase.bosses[2], pair[2][1], pair[2][2])
                table.insert(GS.monsters, m1)
                table.insert(GS.monsters, m2)
            end
        else
            local cells = collectSpawnCells(phase.spawnMode or "edge")
            local idx = 1
            for _, def in ipairs(phase.bosses) do
                local bossSize = def.size or 1
                if bossSize > 1 then
                    -- 大型 Boss：找一个 sxs 空区域
                    local placed = false
                    for _, c in ipairs(cells) do
                        if GS.isAreaEmpty(c[1], c[2], bossSize) then
                            local monster = createMonster(def, c[1], c[2])
                            table.insert(GS.monsters, monster)
                            placed = true
                            break
                        end
                    end
                    if not placed then
                        -- 退化：强制放置在第一个空格（可能溢出但不至于不刷）
                        if idx <= #cells then
                            local monster = createMonster(def, cells[idx][1], cells[idx][2])
                            table.insert(GS.monsters, monster)
                            idx = idx + 1
                        end
                    end
                else
                    if idx <= #cells then
                        local monster = createMonster(def, cells[idx][1], cells[idx][2])
                        table.insert(GS.monsters, monster)
                        idx = idx + 1
                    end
                end
            end
        end
        GS.dungeonPhaseComplete = true
        print("  BOSS 出现!")
        return
    end

    -- ====== 波次阶段：每 N 回合生成一波 ======
    if phase.waves then
        local interval = phase.waveInterval or 2
        local shouldSpawn = (GS.dungeonPhaseTurn == 1)
            or ((GS.dungeonPhaseTurn - 1) % interval == 0)

        if shouldSpawn and GS.dungeonWaveIndex < #phase.waves then
            GS.dungeonWaveIndex = GS.dungeonWaveIndex + 1
            local wave = phase.waves[GS.dungeonWaveIndex]
            local cells = collectSpawnCells(phase.spawnMode or "edge")
            local idx = 1
            for _, def in ipairs(wave) do
                if idx <= #cells then
                    local monster = createMonster(def, cells[idx][1], cells[idx][2])
                    table.insert(GS.monsters, monster)
                    idx = idx + 1
                end
            end
            print("  波次 " .. GS.dungeonWaveIndex .. "/" .. #phase.waves)

            if GS.dungeonWaveIndex >= #phase.waves then
                GS.dungeonPhaseComplete = true
            end
        end
        return
    end

    -- ====== 常规阶段：按间隔持续刷怪 ======
    if phase.monsters then
        local interval = phase.spawnInterval or 1
        if GS.dungeonPhaseTurn > 1 and (GS.dungeonPhaseTurn - 1) % interval ~= 0 then
            return
        end

        local alive = countAlive()
        local perTurn = phase.spawnPerTurn or 1
        local remaining = phase.totalCount - GS.dungeonSpawnCount
        local canSpawn = math.min(perTurn, remaining)
        -- 有上限时才限制场上数量
        if phase.maxOnBoard then
            canSpawn = math.min(canSpawn, phase.maxOnBoard - alive)
        end

        if canSpawn > 0 then
            local cells = collectSpawnCells(phase.spawnMode or "edge")
            local spawned = 0
            for _, pos in ipairs(cells) do
                if spawned >= canSpawn then break end
                local def = phase.monsters[math.random(#phase.monsters)]
                local monster = createMonster(def, pos[1], pos[2])
                table.insert(GS.monsters, monster)
                spawned = spawned + 1
            end
            GS.dungeonSpawnCount = GS.dungeonSpawnCount + spawned
        end

        if GS.dungeonSpawnCount >= phase.totalCount then
            GS.dungeonPhaseComplete = true
        end
    end
end

--- 玩家死亡时处理检查点回退
---------------------------------------------------------------------------
-- 竞技场过场动画状态机（每帧调用）
-- 步骤: player_move → player_wait → enemy_spawn → enemy_wait → dialogue → wait_dialogue → done
---------------------------------------------------------------------------
function M.updateArenaTransition(dt)
    local at = GS.arenaTransition
    if not at then return false end
    if not Combat then Combat = require("Combat") end
    local DialogueManager = require("DialogueManager")

    at.timer = at.timer + dt

    -- Step 1: 玩家移动到指定位置
    if at.step == "player_move" then
        if GS.player then
            local oldX, oldY = GS.player.x, GS.player.y
            local tx, ty = at.playerTarget.x, at.playerTarget.y
            GS.player.x = tx
            GS.player.y = ty
            -- 完整路径：起点 → (拐点) → 终点，先水平再垂直
            local path = { { oldX, oldY } }  -- 起点
            if oldX ~= tx then
                path[#path + 1] = { tx, oldY }  -- 水平移动到目标列
            end
            if oldY ~= ty then
                path[#path + 1] = { tx, ty }    -- 垂直移动到目标行
            end
            if #path >= 2 then
                Combat.startMoveAnim(GS.player, oldX, oldY, path)
            end
        end
        at.step = "player_wait"
        at.timer = 0
        return true
    end

    -- Step 2: 等待玩家移动动画完成
    if at.step == "player_wait" then
        if GS.player and GS.player.moveAnim then
            return true  -- 还在移动
        end
        -- 非 BOSS 关再战：跳过 enemy_spawn/enemy_wait，直接刷怪 + 简单对话
        if at.isNonBossRetry then
            M.spawnForPhase()
            at.step = "dialogue"
            at.timer = 0
            return true
        end
        at.step = "enemy_spawn"
        at.timer = 0
        return true
    end

    -- Step 3: 在入口刷出下一阶段的敌人并开始走位动画
    if at.step == "enemy_spawn" then
        -- 短暂延迟 0.3 秒
        if at.timer < 0.3 then return true end

        local phase = M.getPhase()
        if phase and phase.bosses then
            for _, def in ipairs(phase.bosses) do
                local sx, sy = at.enemySpawn.x, at.enemySpawn.y
                local tx, ty = at.enemyTarget.x, at.enemyTarget.y
                local monster = createMonster(def, tx, ty)
                table.insert(GS.monsters, monster)
                -- 走位动画：从 spawn 走到 target
                local path = {}
                for step_y = sy + 1, ty do
                    path[#path + 1] = { sx, step_y }
                end
                if #path > 0 then
                    Combat.startMoveAnim(monster, sx, sy, path)
                end
                at.enemy = monster
            end
        end
        GS.dungeonPhaseComplete = true  -- 标记已生成，阻止 spawnForPhase 重复刷
        at.step = "enemy_wait"
        at.timer = 0
        return true
    end

    -- Step 4: 等待敌人走位动画完成
    if at.step == "enemy_wait" then
        local anyMoving = false
        for _, m in ipairs(GS.monsters) do
            if m.moveAnim then anyMoving = true; break end
        end
        if anyMoving then return true end
        at.step = "dialogue"
        at.timer = 0
        return true
    end

    -- Step 5: 弹出对话框
    if at.step == "dialogue" then
        -- 短暂延迟 0.2 秒让画面稳定
        if at.timer < 0.2 then return true end

        local phase = M.getPhase()
        local dialogueLines

        if at.isNonBossRetry then
            -- 死亡复活后再战：优先使用 phase.deathRetryDialogue
            if phase and phase.deathRetryDialogue then
                if #phase.deathRetryDialogue == 0 then
                    -- 空数组 = 跳过对话，直接进入战斗
                    at.step = "done"
                    return true
                end
                dialogueLines = phase.deathRetryDialogue
            else
                -- 默认竞技场播报
                dialogueLines = {
                    { speaker = "竞技场播报", text = "哦哦哦哦哦！挑战者又站起来了！" },
                }
            end
        elseif phase and phase.phaseDialogue then
            -- 自定义过场对话（如旁白叙述）
            dialogueLines = phase.phaseDialogue
        else
            -- 默认竞技场播报
            local playerName = GS.charName or "冒险者"
            dialogueLines = {
                { speaker = "竞技场播报", text = "下一场对战的双方是，" .. playerName .. "，对阵，" .. at.announce .. "！" },
            }
        end
        DialogueManager.startDynamic(dialogueLines, function()
            -- 对话结束回调：设置 BOSS 浮动文本（如果有）
            if phase and phase.bossFloatingText and not at.isNonBossRetry then
                local found = false
                for _, m in ipairs(GS.monsters) do
                    if m.hp > 0 then
                        m.floatingText = {
                            text = phase.bossFloatingText,
                            timer = 0,
                            duration = 5.0,
                            fadeStart = 3.5,
                        }
                        found = true
                        print("=== BOSS浮动文本已设置: " .. phase.bossFloatingText .. " (怪物: " .. (m.name or "unknown") .. ") ===")
                        break  -- 只给第一个存活的BOSS设置
                    end
                end
                if not found then
                    print("=== 警告：未找到存活的BOSS来设置浮动文本！monsters数量: " .. #GS.monsters .. " ===")
                end
            end
            at.step = "done"
        end)
        at.step = "wait_dialogue"
        at.timer = 0
        return true
    end

    -- Step 6: 等待对话结束
    if at.step == "wait_dialogue" then
        if DialogueManager.active then
            return true  -- 对话还在显示
        end
        at.step = "done"
    end

    -- Step 7: 过场结束，恢复正常游戏流
    if at.step == "done" then
        local isScroll = at.isScrollTransition
        local isEntry  = at.isEntryDialogue
        print("=== 竞技场过场结束 (scroll=" .. tostring(isScroll) .. " entry=" .. tostring(isEntry) .. ") ===")
        GS.arenaTransition = nil

        if isEntry then
            -- Phase 1 入口对话：怪物+猎犬已刷好，玩家回合已开始，无需额外操作
            return false
        end

        if isScroll then
            -- 滚动过场：怪物+猎犬在滚动完成时已刷好，只需开始玩家回合
            if not Combat then Combat = require("Combat") end
            GS.gameState = GS.STATE_PLAYER
            Combat.startPlayerTurn()
            return false
        end

        -- 标准走位过场：重新生成猎犬 + 开始玩家回合
        GS.spawnHound()
        if not Combat then Combat = require("Combat") end
        GS.gameState = GS.STATE_PLAYER
        Combat.startPlayerTurn()
        return false
    end

    return true
end

--- 获取竞技场过场配置（供外部读取 playerReset 等）
function M.getArenaTransitionConfig()
    if currentDungeon and currentDungeon.arenaTransition then
        return currentDungeon.arenaTransition
    end
    return nil
end

function M.onPlayerDeath()
    if not M.isActive() then return end

    -- 重置当前关卡状态，重新挑战当前阶段
    GS.dungeonSpawnCount = 0
    GS.dungeonWaveIndex = 0
    GS.dungeonPhaseComplete = false
    GS.dungeonPhaseTurn = 0
    GS.lastPlayerTarget = nil
    GS.topBarLockedTarget = nil
    GS.monsters = {}
    GS.companions = {}
    GS.fireCorpses = {}
    GS.arenaTransition = nil
    GS.arenaWaitForExit = false
    GS.arenaExitTiles = nil
    GS.arenaChests = {}
    GS.arenaChestInteract = nil
    GS.arenaChestPending = nil
    GS.arenaExitPending = false
    GS.lightningWarnings = {}

    -- 再战时关闭自动战斗
    if GS.autoMode then
        GS.autoMode = false
        GS.autoTimer = 0
        print("[副本] 再战：已关闭自动战斗")
    end

    local phase = M.getPhase()
    if phase then
        print("=== 死亡重置: 重新挑战阶段 " .. GS.dungeonPhase .. ": " .. phase.name .. " ===")
    end
end

--- 再战时启动竞技场过场序列（玩家移到 playerReset，BOSS 从 enemySpawn 走到 enemyTarget + 对话）
function M.startRetryTransition()
    if not currentDungeon or not currentDungeon.arenaTransition then
        -- 无过场配置，直接刷怪开战
        M.spawnForPhase()
        GS.spawnHound()
        return false
    end
    local trans = currentDungeon.arenaTransition

    -- 滚动模式：不使用走位过场，直接刷怪开战
    if trans.scrollMode then
        M.spawnForPhase()
        GS.spawnHound()
        return false
    end

    local phase = M.getPhase()

    -- 判断当前阶段是否是 BOSS 关（name 以 "BOSS：" 开头）
    local isBossPhase = phase and phase.name and phase.name:find("^BOSS") ~= nil

    if isBossPhase then
        -- BOSS 关：玩家已在位置，直接从 enemy_spawn 开始（BOSS 入场 → 对话）
        local rawName = phase.arenaAnnounce or phase.name or "???"
        local announce = rawName:gsub("^BOSS：", "")
        GS.arenaTransition = {
            step = "enemy_spawn",
            timer = 0,
            playerTarget = trans.playerReset,
            enemySpawn   = trans.enemySpawn,
            enemyTarget  = trans.enemyTarget,
            announce     = announce,
            enemy = nil,
        }
        print("=== 再战过场开始: " .. announce .. " ===")
    else
        -- 非 BOSS 关（如第一关哥布林勇士）：玩家已在位置，直接刷怪 + 简单对话
        M.spawnForPhase()
        GS.arenaTransition = {
            step = "dialogue",
            timer = 0,
            playerTarget = trans.playerReset,
            enemySpawn   = trans.enemySpawn,
            enemyTarget  = trans.enemyTarget,
            announce     = nil,
            enemy = nil,
            isNonBossRetry = true,  -- 标记：非 BOSS 关再战
        }
        print("=== 再战过场开始（非BOSS关） ===")
    end
    return true
end

--- 退出副本
function M.exit()
    GS.isDungeon = false
    GS.dungeonId = nil
    GS.dungeonPhase = 0
    GS.dungeonCheckpoint = 0
    GS.dungeonSpawnCount = 0
    GS.dungeonWaveIndex = 0
    GS.dungeonPhaseComplete = false
    GS.dungeonPhaseTurn = 0
    GS.arenaWaitForExit = false
    GS.arenaExitTiles = nil
    GS.arenaChests = {}
    GS.arenaChestInteract = nil
    GS.arenaChestPending = nil
    GS.arenaExitPending = false
    GS.arenaPendingTarget = nil
    GS.arenaDungeonCleared = false
    -- 清理过渡动画状态，防止中途退出时残留
    GS.arenaTransition = nil
    GS.dungeonScrollAnim = nil
    currentDungeon = nil
    -- 清除不可知物凝视 buff（防止带出副本）
    if GS.player then
        GS.player._unknownGaze = 0
        GS.player._gazePer = 0
        GS.player._gazeFoc = 0
    end
    print("=== 离开副本 ===")
end

--- 脱离卡死：重置当前小关状态
--- 如果本小关宝箱已领取，则跳到等待踩出口状态（防止刷BOSS）
--- 否则重置到小关开始
--- @return boolean success 是否执行成功
--- @return string message 提示信息
function M.unstuck()
    if not M.isActive() then
        return false, "当前不在副本中，无法使用"
    end

    local phase = M.getPhase()
    if not phase then
        return false, "副本阶段异常，请退出副本"
    end

    -- 检查本小关是否已完成（BOSS已击败 / 宝箱已领取）
    local hasOpenedChest = false
    for _, chest in ipairs(GS.arenaChests) do
        if chest.opened then
            hasOpenedChest = true
            break
        end
    end
    -- arenaWaitForExit = 怪物全灭后进入等待踩出口状态（真正的阶段通关）
    -- 注意：dungeonPhaseComplete 仅表示"怪物已全部生成"，BOSS 还活着时就已为 true，不能用于判断通关
    local phaseAlreadyDone = GS.arenaWaitForExit

    -- 清除战斗/过场相关状态
    GS.monsters = {}
    GS.companions = {}
    GS.fireCorpses = {}
    GS.lightningWarnings = {}
    GS.arenaTransition = nil
    GS.arenaChestInteract = nil
    GS.arenaChestPending = nil
    GS.arenaExitPending = false
    GS.arenaPendingTarget = nil
    GS.lastPlayerTarget = nil
    GS.topBarLockedTarget = nil
    GS.burningGrounds = {}

    -- 关闭自动战斗
    if GS.autoMode then
        GS.autoMode = false
        GS.autoTimer = 0
    end

    -- 恢复玩家状态
    GS.clearAllBuffsDebuffs()
    GS.recalcStats(GS.player)
    GS.player.hp = GS.player.maxHp
    GS.player.acted = false
    GS.respawnTimer = 0

    -- 施法职业：重置吟唱段数（充能交由 startPlayerTurn 统一处理，避免叠加）
    if (GS.currentClass == "mage" or GS.currentClass == "priest") and GS.player and GS.player.hp > 0 then
        GS.chantStages = 0
        GS.chantStagesMax = 0
        GS._chantPendingReset = true  -- 标记覆盖（而非叠加），由 startPlayerTurn 充能
    end

    -- 将玩家移到复活位置
    local arenaTransCfg = M.getArenaTransitionConfig()
    if arenaTransCfg and arenaTransCfg.playerReset then
        GS.player.x = arenaTransCfg.playerReset.x
        GS.player.y = arenaTransCfg.playerReset.y
    end

    if hasOpenedChest or phaseAlreadyDone then
        -- 宝箱已领取/阶段已完成：跳到等待踩出口状态（防止刷BOSS）
        GS.dungeonPhaseComplete = true
        GS.arenaWaitForExit = true
        GS.arenaExitTiles = { {x = 6, y = 1}, {x = 7, y = 1} }
        -- 只清除已领取的宝箱，保留未领取的（防止玩家丢失未开启的掉落）
        local keptChests = {}
        for _, chest in ipairs(GS.arenaChests) do
            if not chest.opened then
                keptChests[#keptChests + 1] = chest
            end
        end
        GS.arenaChests = keptChests
        GS.gameState = GS.STATE_PLAYER

        -- 检测是否最终阶段
        local nextIdx = GS.dungeonPhase + 1
        if currentDungeon and not currentDungeon.phases[nextIdx] then
            GS.arenaDungeonCleared = true
        end

        -- 生成猎犬
        GS.spawnHound()

        local reason = hasOpenedChest and "宝箱已领取" or "阶段已完成"
        local hint = #keptChests > 0 and "请先领取宝箱，再踩绿色出口前往下一关"
                                      or "请踩绿色出口前往下一关"
        print("=== 脱离卡死: " .. reason .. "，跳到等待出口状态 (阶段 " .. GS.dungeonPhase .. "), 剩余宝箱: " .. #keptChests .. " ===")
        return true, "已脱离卡死！" .. hint
    else
        -- 宝箱未领取：完全重置当前小关
        GS.dungeonSpawnCount = 0
        GS.dungeonWaveIndex = 0
        GS.dungeonPhaseComplete = false
        GS.dungeonPhaseTurn = 0
        GS.arenaWaitForExit = false
        GS.arenaExitTiles = nil
        GS.arenaChests = {}
        GS.gameState = GS.STATE_PLAYER

        print("=== 脱离卡死: 重置阶段 " .. GS.dungeonPhase .. ": " .. (phase.name or "?") .. " ===")

        -- 启动过场/刷怪
        if not M.startRetryTransition() then
            if not Combat then Combat = require("Combat") end
            Combat.startPlayerTurn()
        end

        return true, "已脱离卡死！重新开始当前小关"
    end
end

return M
