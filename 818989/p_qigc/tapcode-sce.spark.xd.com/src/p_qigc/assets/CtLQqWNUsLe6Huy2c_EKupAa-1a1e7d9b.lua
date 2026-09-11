--- 潮汐祭祀圣所副本定义（竞技场模式，参照哥布林竞技场）
local GS = require("GameState")

local M = {}

M.name = "潮汐祭祀圣所"

-- 玩家复活重生点（固定位置）
M.playerSpawn = { x = 7, y = 12 }

-- 竞技场过场配置（scrollMode：使用棋盘滚动代替走位过场）
M.arenaTransition = {
    playerReset = { x = 7, y = 10 },
    enemySpawn  = { x = 6, y = 1 },
    enemyTarget = { x = 6, y = 3 },
    scrollMode  = true,
}

M.phases = {
    -- Phase 1: 3个鱼人精锐战士
    {
        name = "鱼人精锐战士",
        spawnMode = "top",
        bosses = {
            GS.MONSTER_DB.fishman_elite_tidal,
            GS.MONSTER_DB.fishman_elite_tidal,
            GS.MONSTER_DB.fishman_elite_tidal,
        },
        arenaAnnounce = "怕疼的\"杰尼\"",
        phaseDialogue = {
            { speaker = "旁白", text = "（当你站在洞窟外时，你感觉到洞窟里有视线正在看你。）" },
            { speaker = "旁白", text = "（进来以后这种感觉更加明显了，它没有威胁，它对你充满好奇。）" },
        },
        -- 第一关死亡复活后不显示任何文本
        deathRetryDialogue = {},
    },
    -- Phase 2: BOSS 怕疼的"杰尼"
    {
        name = "BOSS：怕疼的\"杰尼\"",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.tidal_boss_jeni },
        bossSpawnPositions = { { x = 6, y = 1 } },
        chestRule = "boss_drop",
        arenaAnnounce = "先知\"夸迪\"",
        -- 自定义过场对话（替代竞技场播报）
        phaseDialogue = {
            { speaker = "旁白", text = "（一个奇特的鱼人全副武装，背上背着巨大的龟壳，样子滑稽。它看上去累坏了，小声念叨着什么。）" },
        },
        -- BOSS入场后头顶浮动文本
        bossFloatingText = "不……不要打我，疼很难受。",
    },
    -- Phase 3: BOSS 先知"夸迪"
    {
        name = "BOSS：先知\"夸迪\"",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.tidal_boss_kuadi },
        bossSpawnPositions = { { x = 6, y = 1 } },
        chestRule = "boss_drop",
        arenaAnnounce = "不可知物",
        phaseDialogue = {
            { speaker = "旁白", text = "（继续往洞窟里面走，你见到了一个手持法杖的鱼人……它凸起的眼窝里是紫的，像是被感染了。）" },
        },
        bossFloatingText = "主……主在吩咐……我遵命。",
    },
    -- Phase 4: BOSS 不可知物（4格单位，最终BOSS）
    {
        name = "BOSS：不可知物",
        spawnMode = "top",
        bosses = { GS.MONSTER_DB.tidal_boss_unknown },
        -- 固定刷新位置：左上角(6,1)，占据(6,1)(7,1)(6,2)(7,2)
        bossSpawnPositions = { { x = 6, y = 1 } },
        -- 宝箱生成在4格BOSS身体的左下角
        chestRule = "boss_bottom_left",
        phaseDialogue = {
            { speaker = "旁白", text = "（洞窟的最末段出现了一个巨大的紫色球体，看上去像是一个大脑。）" },
            { speaker = "旁白", text = "（你的耳朵里传来神秘的低语，但你完全搞不清楚它们在说什么，那是一种你没有听过的语言。）" },
            { speaker = "旁白", text = "（渐渐地，你感觉周围的一切都睁开了眼睛，这个世界正在凝视你。）" },
        },
    },
}

return M
