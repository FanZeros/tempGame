--- 史莱姆王国副本定义（竞技场模式 + 棋盘滚动过场）
local GS = require("GameState")

local M = {}

M.name = "史莱姆王国"

-- 玩家复活重生点（固定位置）
M.playerSpawn = { x = 7, y = 12 }

-- 竞技场过场配置（scrollMode：使用棋盘滚动代替走位过场）
M.arenaTransition = {
    playerReset = { x = 7, y = 10 },
    enemySpawn  = { x = 6, y = 1 },
    enemyTarget = { x = 6, y = 3 },
    scrollMode  = true,  -- 使用棋盘滚动过场而非竞技场走位过场
}

M.phases = {
    -- Phase 1: 从顶部刷新30个Lv1史莱姆（不限场上数量）
    {
        name = "史莱姆大军",
        spawnMode = "top",
        monsters = { GS.MONSTER_DB.slime },
        totalCount = 30,
        spawnPerTurn = 3,
        spawnInterval = 1,
        arenaAnnounce = "精锐史莱姆",
        phaseDialogue = {
            { speaker = "旁白", text = "（你进入了这个属于史莱姆的国度，一大群史莱姆朝你冲了过来，蹦蹦跳跳。）" },
        },
    },
    -- Phase 2: 每回合1个精锐，共10个（不限场上数量）
    {
        name = "精锐史莱姆",
        spawnMode = "top",
        monsters = { GS.MONSTER_DB.slime_elite },
        totalCount = 10,
        spawnPerTurn = 1,
        spawnInterval = 1,
        arenaAnnounce = "BOSS：王子与公主",
        phaseDialogue = {
            { speaker = "旁白", text = "（又一大群史莱姆蹦蹦蹦跳跳地冲了过来，但是气势远超你之前碰到的其他史莱姆。）" },
        },
    },
    -- Phase 3: BOSS - 王子与公主（固定位置刷新，通关存检查点）
    {
        name = "BOSS：王子与公主",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.slime_prince, GS.MONSTER_DB.slime_princess },
        -- 固定刷新位置：王子(7,1)，公主(6,1)，按 bosses 数组顺序对应
        bossSpawnPositions = { { x = 7, y = 1 }, { x = 6, y = 1 } },
        checkpoint = true,
        arenaAnnounce = "元素精锐",
        -- 宝箱特殊规则：只生成1个，出现在后死亡的那个BOSS位置
        chestRule = "last_killed_boss",
        phaseDialogue = {
            { speaker = "旁白", text = "（好吧，又是两个蹦蹦跳跳的家伙。公主似乎要保护身后加油的王子。）" },
        },
    },
    -- Phase 4: 火冰电精锐各1，每2回合一波，共3波
    {
        name = "元素精锐",
        spawnMode = "top",
        waves = {
            { GS.MONSTER_DB.fire_slime_elite, GS.MONSTER_DB.ice_slime_elite, GS.MONSTER_DB.elec_slime_elite },
            { GS.MONSTER_DB.fire_slime_elite, GS.MONSTER_DB.ice_slime_elite, GS.MONSTER_DB.elec_slime_elite },
            { GS.MONSTER_DB.fire_slime_elite, GS.MONSTER_DB.ice_slime_elite, GS.MONSTER_DB.elec_slime_elite },
        },
        waveInterval = 2,
        arenaAnnounce = "BOSS：史莱姆王",
        phaseDialogue = {
            { speaker = "旁白", text = "（蹦蹦跳跳，蹦蹦跳跳，旁白想不出其他词汇，而且你也感到受够了。）" },
        },
    },
    -- Phase 5: BOSS - 史莱姆王（固定位置刷新，左上角(6,1)的2x2区域）
    {
        name = "BOSS：史莱姆王",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.slime_king },
        -- 固定刷新位置：国王左上角(6,1)，占据(6,1)(7,1)(6,2)(7,2)
        bossSpawnPositions = { { x = 6, y = 1 } },
        -- 宝箱特殊规则：生成在4格BOSS身体的左下角
        chestRule = "boss_bottom_left",
        phaseDialogue = {
            { speaker = "旁白", text = "（这可真是个大家伙，你的潜意识告诉你，应该离他远点，但你的使命没有同意。）" },
        },
    },
}

return M
