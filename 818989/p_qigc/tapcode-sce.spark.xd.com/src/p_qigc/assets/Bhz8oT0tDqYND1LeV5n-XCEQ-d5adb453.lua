--- 哥布林竞技场副本定义
local GS = require("GameState")

local M = {}

M.name = "哥布林竞技场"

-- 竞技场过场配置：阶段结束后玩家回到 playerReset，敌人从 enemySpawn 走到 enemyTarget
M.arenaTransition = {
    playerReset = { x = 7, y = 10 },
    enemySpawn  = { x = 6, y = 1 },
    enemyTarget = { x = 6, y = 3 },
}

M.phases = {
    -- Phase 1: 3个哥布林勇士
    {
        name = "哥布林勇士",
        spawnMode = "top",
        bosses = {
            GS.MONSTER_DB.goblin_warrior_arena,
            GS.MONSTER_DB.goblin_warrior_arena,
            GS.MONSTER_DB.goblin_warrior_arena,
        },
        -- 第一关结束后弹出下一关预告
        arenaAnnounce = "阴险\"迪呜\"",
    },
    -- Phase 2: BOSS 迪呜
    {
        name = "BOSS：阴险\"迪呜\"",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.goblin_boss_diwu },
        arenaAnnounce = "聪明\"迪拉\"",
    },
    -- Phase 3: BOSS 迪拉
    {
        name = "BOSS：聪明\"迪拉\"",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.goblin_boss_dila },
        arenaAnnounce = "英雄\"迪卡塔\"",
    },
    -- Phase 4: BOSS 迪卡塔（最终BOSS）
    {
        name = "BOSS：英雄\"迪卡塔\"",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.goblin_boss_dikata },
        -- 最终阶段无 arenaAnnounce
    },
}

return M
