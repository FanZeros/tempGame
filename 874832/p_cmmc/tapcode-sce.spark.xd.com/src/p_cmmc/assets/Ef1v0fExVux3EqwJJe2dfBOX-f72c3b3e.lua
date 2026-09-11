-- ============================================================
-- 纵跃魔塔 (Vertical Leap Tower) - 卡牌 + 魔塔 + 跳跃 RPG
-- UrhoX NanoVG 实现
-- ============================================================
---@class SDKGlobal
---@field ShowRewardVideoAd fun(self: SDKGlobal, callback: fun(result: {success: boolean, msg: string}))
---@field GetNativeExitMenuRect fun(self: SDKGlobal): table|nil
---@type SDKGlobal
sdk = sdk

require "LuaScripts/Utilities/Sample"

-- ============================================================
-- 游戏配置
-- ============================================================
require "data_defs"

-- 开发/测试工具环境检测：优先读取宿主运行环境，识别不到时保守关闭。
ENABLE_DEV_TOOLS = false
SHOW_EDITOR_BUTTON = false
local devToolsEnvSource = "unknown"

local function containsAnyWord(value, words)
    if value == nil then return nil end
    local s = string.lower(tostring(value))
    if s == "" then return nil end
    for _, word in ipairs(words) do
        if s == word or string.find(s, word, 1, true) then return true end
    end
    return nil
end

local function classifyEnvText(value)
    local prodWords = {"production", "prod", "release", "online", "official", "formal"}
    if containsAnyWord(value, prodWords) then return false end

    local testWords = {"test", "testing", "staging", "debug", "dev", "development", "preview", "sandbox", "trial", "maker", "editor", "devtools", "qa"}
    if containsAnyWord(value, testWords) then return true end

    return nil
end

local function classifyPreviewText(value)
    local previewWords = {"preview", "maker", "editor", "devtools", "debug", "test", "sandbox", "trial", "simulator"}
    if containsAnyWord(value, previewWords) then return true end
    return nil
end

local function classifyEnvInfo(info)
    if type(info) == "string" or type(info) == "number" then
        return classifyEnvText(info)
    end
    if type(info) ~= "table" then return nil end

    local textKeys = {"environment", "env", "channel", "mode", "stage", "runtimeEnv", "buildType", "versionType", "releaseType", "host", "container", "platform", "scene"}
    for _, key in ipairs(textKeys) do
        local result = classifyEnvText(info[key])
        if result ~= nil then return result end
    end

    local prodBoolKeys = {"isProduction", "production", "isProd", "prod", "isRelease", "release", "isFormal", "formal"}
    for _, key in ipairs(prodBoolKeys) do
        if info[key] == true then return false end
    end

    local testBoolKeys = {"debug", "isDebug", "test", "isTest", "isPreview", "preview", "sandbox", "isSandbox", "isEditor", "editor", "isMaker", "maker", "isDevTools", "devtools"}
    for _, key in ipairs(testBoolKeys) do
        if info[key] == true then return true end
    end

    return nil
end

local function safeField(obj, key)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj[key] end)
    if ok then return value end
    return nil
end

local function safeMethodResult(obj, methodName)
    local method = safeField(obj, methodName)
    if type(method) ~= "function" then return nil end
    local ok, result = pcall(method, obj)
    if ok then return result end
    ok, result = pcall(method)
    if ok then return result end
    return nil
end

local function safeGlobalFunctionResult(functionName)
    local fn = rawget(_G, functionName)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function classifyArguments(args)
    if type(args) == "string" or type(args) == "number" then
        return classifyPreviewText(args)
    end
    if type(args) ~= "table" then return nil end

    for _, arg in ipairs(args) do
        local result = classifyPreviewText(arg)
        if result ~= nil then return result end
    end
    return nil
end

local function detectPreviewEnvironment()
    if rawget(_G, "__tool_mode__") then
        return true, "global:__tool_mode__"
    end

    local previewGlobals = {"TAPTAP_PREVIEW", "SCE_PREVIEW", "MAKER_PREVIEW", "IS_PREVIEW", "PREVIEW_MODE", "EDITOR_MODE", "DEVTOOLS_MODE"}
    for _, key in ipairs(previewGlobals) do
        local value = rawget(_G, key)
        if value == true then return true, "global:" .. key end
        local result = classifyPreviewText(value)
        if result ~= nil then return result, "global:" .. key end
    end

    local argsResult = classifyArguments(safeGlobalFunctionResult("GetArguments"))
    if argsResult ~= nil then return argsResult, "GetArguments" end

    local platformResult = classifyPreviewText(safeGlobalFunctionResult("GetPlatform"))
    if platformResult ~= nil then return platformResult, "GetPlatform" end

    platformResult = classifyPreviewText(safeGlobalFunctionResult("GetNativePlatform"))
    if platformResult ~= nil then return platformResult, "GetNativePlatform" end

    return nil, "preview:unknown"
end

local function detectHostEnvironment()
    local tapObj = rawget(_G, "tap")
    local tapGetInfo = safeField(tapObj, "getSystemInfoSync")
    if type(tapGetInfo) == "function" then
        local ok, info = pcall(tapGetInfo)
        if ok then
            local result = classifyEnvInfo(info)
            if result ~= nil then return result, "tap.getSystemInfoSync" end
        end
    end

    local sdkObj = rawget(_G, "sdk")
    local sdkMethods = {"GetSystemInfoSync", "GetSystemInfo", "GetRuntimeEnv", "GetEnvironment", "GetEnv", "GetChannel", "GetReleaseType"}
    for _, methodName in ipairs(sdkMethods) do
        local info = safeMethodResult(sdkObj, methodName)
        local result = classifyEnvInfo(info)
        if result ~= nil then return result, "sdk:" .. methodName end
    end

    local sdkTestMethods = {"IsTestEnvironment", "IsDebug", "IsPreview", "IsSandbox"}
    local sdkTestFalseSource = nil
    for _, methodName in ipairs(sdkTestMethods) do
        local result = safeMethodResult(sdkObj, methodName)
        if result == true then return true, "sdk:" .. methodName end
        if result == false then sdkTestFalseSource = "sdk:" .. methodName end
    end

    local sdkProdMethods = {"IsProduction", "IsRelease", "IsFormal"}
    for _, methodName in ipairs(sdkProdMethods) do
        local result = safeMethodResult(sdkObj, methodName)
        if result == true then return false, "sdk:" .. methodName end
    end

    if sdkTestFalseSource then return false, sdkTestFalseSource end

    local globals = {"TAPTAP_ENV", "SCE_ENV", "RUNTIME_ENV", "APP_ENV", "BUILD_ENV"}
    for _, key in ipairs(globals) do
        local result = classifyEnvInfo(rawget(_G, key))
        if result ~= nil then return result, "global:" .. key end
    end

    return nil, "host:unknown"
end

local function DetectDevToolsEnabled()
    local result, source = detectPreviewEnvironment()
    if result ~= nil then
        devToolsEnvSource = source
        return result
    end

    result, source = detectHostEnvironment()
    if result ~= nil then
        devToolsEnvSource = source
        return result
    end

    devToolsEnvSource = source or "default"
    return true
end

local function ConfigureDevTools()
    ENABLE_DEV_TOOLS = DetectDevToolsEnabled()
    SHOW_EDITOR_BUTTON = ENABLE_DEV_TOOLS
    log:Write(LOG_INFO, "[Env] devTools=" .. tostring(ENABLE_DEV_TOOLS) .. " source=" .. tostring(devToolsEnvSource))
end


-- 地图数据 (每层11x11) - 由 MapGenerator 随机生成或使用手工地图
local MapGenerator = require("MapGenerator")
---@type table|nil
MAP_DATA = nil

-- ============================================================
-- 游戏状态
-- ============================================================
player = {
    row = 2, col = 2,
    floor = 1,
    hp = 100, atk = 10, def = 5,
    gold = 0,
    yellowKeys = 0,
    blueKeys = 0,
    redKeys = 0,
    facing = "down",  -- 当前朝向: down/up/left/right
    skills = {},      -- 已激活的被动技能 id 集合, e.g. {shield=true, vampire=true}
    relics = {},      -- 已获得的遗物 id 集合, e.g. {gemCraft=true}
    gems = {},        -- 宝石背包 {flame=2, frost=1, ...}
    cards = {         -- 卡牌库存(对象数组)
        {id = "strike", usesLeft = -1},
        {id = "strike", usesLeft = -1},
        {id = "strike", usesLeft = -1},
        {id = "strike", usesLeft = -1},
    },
    mp = 5,           -- 当前MP
    maxMp = 10,       -- MP上限
    mpRegen = 5,      -- 每回合MP恢复量
    drawCount = 3,    -- 每回合抽牌数
    shopUpgradeBuys = {}, -- 商店升级区各商品已购买次数（用于独立涨价）
    shopSoldCards = {}, -- 商店已售出的卡牌记录，按楼层保存
    level = 1,        -- 当前等级
    exp = 0,          -- 当前经验值
}

local function getDifficultyIndex()
    local idx = tonumber(charSelect.selectedDifficulty) or 1
    if not DIFFICULTY_DEF[idx] then idx = 1 end
    return idx
end

local function getDifficultyDef()
    return DIFFICULTY_DEF[getDifficultyIndex()]
end

local function scaleDifficultyEnemyStat(value, minValue)
    local diff = getDifficultyDef()
    local mul = diff.enemyMul or 1.0
    return math.max(minValue or 1, math.floor(value * mul + 0.5))
end

local function getMonsterScaledHP(m)
    return scaleDifficultyEnemyStat(m.hp or 1, 1)
end

local function getMonsterScaledATK(m)
    return scaleDifficultyEnemyStat(m.atk or 0, 0)
end

---@type table<integer, table<integer, table<integer, string>>>
maps = {}
gameState = "title"  -- "title", "mode_select", "char_select", "playing", "win", "gameover", "editor"

-- ============================================================
require "editor"

-- ============================================================
-- 跳跃上楼系统
-- 和传统魔塔不同，此魔塔被增加了封印，上楼之后无法下楼。
-- 玩家可选择: 普通上楼(+1层) 或 跳跃上楼(+2层, 删除1张牌)
-- ============================================================
local stairUI = {
    active = false,         -- 是否显示上楼选择弹窗
    phase = "choose",       -- "choose"=选择模式, "delete"=选牌删除, "animating"=跳跃动画
    canJump = true,         -- 是否可以跳跃(牌组>5且有下一层可跳)
    cardScroll = 0,         -- 删牌列表滚动
    cardRects = {},         -- 卡牌点击区域
    selectedCard = nil,     -- 选中要删除的卡牌索引
    confirmRect = nil,      -- 确认按钮区域
    cancelRect = nil,       -- 取消按钮区域
    normalRect = nil,       -- 普通上楼按钮区域
    jumpRect = nil,         -- 跳跃上楼按钮区域
    jumpAnim = {
        active = false,
        phase = "fade_in",      -- "fade_in" → "card_burn" → "floor_jump" → "fade_out" → done
        timer = 0,
        fadeInDur = 0.5,        -- 前置淡入重叠
        cardBurnDur = 0.7,      -- 卡牌消散时长
        floorJumpDur = 0.9,     -- 楼层跳跃时长
        fadeOutDur = 0.5,       -- 后置淡出重叠
        fromFloor = 0,
        toFloor = 0,
        cardName = "",          -- 被燃烧的卡牌名
        cardColor = {255,255,255}, -- 卡牌颜色
        screenShake = 0,        -- 屏幕震动量
    },
    firstShow = true,       -- 是否第一次显示(显示封印提示)
}

-- 消息系统
local msg = {text = "", timer = 0, color = {255, 255, 255}}

-- 移动冷却
local moveCooldown = 0
local MOVE_CD = 0.15

-- ============================================================
-- 屏幕与布局
-- ============================================================
physW, physH, dpr, logicalW, logicalH = 0, 0, 1, 0, 0
cellSize, gridX, gridY = 0, 0, 0
local statsH = 55
local dpadCenterX, dpadCenterY, dpadBtnSize

-- NanoVG
nvgCtx = nil
fontNormal = nil

-- 精灵图
spriteImages = {}   -- {path = {handle, imgW, imgH}}
spr = {
    player = nil, playerW = 0, playerH = 0,
    wall = nil, wallW = 0, wallH = 0,
    item = nil, itemW = 0, itemH = 0,
    key = nil, keyW = 0, keyH = 0,
    door = nil, doorW = 0, doorH = 0,
    stair = nil, stairW = 0, stairH = 0,
    titleLogo = nil, titleLogoW = 0, titleLogoH = 0,
    bgTitle = nil, bgTitleW = 0, bgTitleH = 0,
    bgGame = nil, bgGameW = 0, bgGameH = 0,
    bgMode = nil, bgModeW = 0, bgModeH = 0,
}

-- 标题背景视频
titleVideo = nil      -- VideoPlayer 实例
titleVideoImg = nil   -- NanoVG 图片句柄
local titleVideoUnsupported = false

local function releaseTitleVideo()
    if titleVideoImg and titleVideoImg > 0 then
        if nvgDeleteVideo then
            nvgDeleteVideo(nvgCtx, titleVideoImg)
        else
            nvgDeleteImage(nvgCtx, titleVideoImg)
        end
        titleVideoImg = nil
    end
    if titleVideo then
        titleVideo:Stop()
        titleVideo:Dispose()
        titleVideo = nil
    end
end

local function ensureTitleVideo()
    if titleVideo or titleVideoUnsupported or not nvgCtx then return end
    local player = VideoPlayer:new()
    if not player then
        titleVideoUnsupported = true
        return
    end
    local ok = player:Load("video/start_bg.mp4", 1280, 720)
    if ok then
        titleVideo = player
        titleVideo:SetVolume(0)
        titleVideo:SetLoop(true)
        titleVideo:Play()
        log:Write(LOG_INFO, "Title video loaded")
    else
        log:Write(LOG_WARNING, "Title video load failed (expected on non-WASM)")
        player:Stop()
        player:Dispose()
        titleVideoUnsupported = true
    end
end

-- RPG Maker 单角色精灵图: 144x192, 3列x4行, 每帧48x48
-- 动画: 循环3列 (左脚/站立/右脚), 面朝下(第1行)
SPRITE_FRAME_W = 48
SPRITE_FRAME_H = 48
local SPRITE_SY = 0   -- 怪物默认面朝下(第1行)

-- 四方向朝向映射 (RPG Maker 行顺序: 下/左/右/上)
local FACING_SY = {down = 0, left = 48, right = 96, up = 144}
-- 玩家精灵帧配置（支持瑞比等特殊尺寸角色）
-- frow: 四方向行号映射
plSpr = {fw = 48, fh = 48, ox = 0, oy = 0, frow = {down = 0, left = 1, right = 2, up = 3}}

-- 动画系统
local ANIM_INTERVAL = 0.35  -- 每帧间隔(秒)
ANIM_FRAMES = {0, 1, 2, 1}  -- 列索引序列: 左脚→站立→右脚→站立
animTimer = 0
animFrameIndex = 1  -- 当前动画序列索引(1-4)

-- 平滑移动动画
local MOVE_ANIM_DURATION = 0.1  -- 移动动画时长(秒)
local moveAnim = {
    active = false,
    fromRow = 0, fromCol = 0,
    t = 0,
}

-- 自动寻路系统
local autoPath = {}       -- 寻路路径队列 {{row, col}, ...}，从下一步开始
local autoPathTimer = 0   -- 自动行走计时器
local AUTO_STEP_INTERVAL = 0  -- 每步间隔(秒)
local autoPathDest = nil  -- 寻路目的地 {row, col}，用于瞬移判定

-- 开门动画
local doorAnims = {}      -- {{row, col, tile, timer, duration}, ...}
local DOOR_ANIM_DURATION = 0.35

-- 战斗动画系统
local showBattleAnim = true  -- 是否播放战斗动画（固定开启）
local handbookOpen = false   -- 怪物手册是否打开
-- UI面板状态（合并减少顶层局部变量数量，避免Lua 200 local限制）
local cardBook = {
    open = false, scroll = 0,
    drag = { active = false, startY = 0, startScroll = 0, startX = 0 },
    cardRects = {},
    selectedIdx = nil,  -- 选中卡牌索引（用于放大预览+关键词）
}
local gemPanel = {
    open = false, cardIdx = nil, rects = {}, removeRect = nil,
}
local gemEquip = {
    open = false, gemId = nil, cardRects = {}, closeRect = nil, scroll = 0,
    confirmCardIdx = nil, confirmRect = nil, cancelRect = nil,  -- 确认步骤
    backpackRect = nil,  -- "放入背包"按钮
    fromMap = false, mapRow = nil, mapCol = nil, mapFloor = nil,  -- 地图拾取来源
    drag = { active = false, startY = 0, startX = 0, startScroll = 0 },  -- 拖拽滚动
    panelRect = nil,  -- 面板区域（用于判断点击是否在面板内）
}
-- 标题页统一图鉴
codex = {
    open = false, tab = 1, -- 1=卡牌 2=怪物 3=宝石 4=遗物
    scroll = 0,
    drag = { active = false, startY = 0, startScroll = 0 },
    closeRect = nil, tabRects = {},
    selectedCard = nil,  -- 选中卡牌id（用于放大预览+关键词）
    cardFilter = 0,      -- 0=全部 1=角色专属 2=通用
    filterRects = {},
    cardRects = {},      -- Tab1 卡牌点击区域 {{id, x, y, w, h}, ...}
}
local pileView = {
    open = false,
    pileType = nil,   -- "deck" or "discard"
    scroll = 0,
    drag = { active = false, startY = 0, startScroll = 0 },
}
local levelUp = {
    open = false, candidates = {}, pendingCount = 0, selectedIndex = nil,
    cardRects = {}, confirmRect = nil, refreshRect = nil,
    adRefreshUsed = 0,  -- 本次升级已看广告刷新次数
}
local dev = {
    mode = false, tapCount = 0, tapTimer = 0, scroll = 0,
    drag = { active = false, startY = 0, startScroll = 0 },
    contentH = 0, -- 内容总高度（用于限制滚动）
}
-- 卡牌开发者工具：可视化调整卡牌各区域位置和大小
cardDev = {
    active = false,
    previewId = "strike",    -- 预览用的卡牌ID
    -- 可编辑参数（比例值，相对于卡牌宽高）
    p = {
        nameTop    = 0.135,  nameBot    = 0.250,  nameOffX = 0.066,
        imgTop     = 0.245,  imgBot     = 0.559,
        imgMarginX = 0.156,  imgOffX  = 0.013,
        descTop    = 0.599,  descBot    = 0.850,
        descPadX   = 0.204,  descOffX = 0.015,
        manaX      = 0.096,  manaY      = 0.089, manaSize = 0.166,
        framePadX  = 0.0,    framePadY  = 0.0,   -- 卡框内边距（比例值）
        cardScale  = 1.625,  -- 卡牌整体缩放 (1.0=默认, 卡框图片有透明边距需放大补偿)
    },
    -- 选中区域: 1=name, 2=image, 3=desc, 4=mana, nil=无
    selected = nil,
    -- 拖拽状态: mode="move"|"resize"
    drag = { active = false, mode = nil, region = 0, startX = 0, startY = 0, origP = nil },
    -- 导出文本
    exportText = nil,
}
gameMenu = {open = false, btnRects = {}, confirm = nil}  -- 游戏内菜单（存档/读档/返回标题），confirm="title"时显示确认
gameAutoSave = true  -- 自动存档开关（默认开启）

-- 多存档槽位系统
MAX_SAVE_SLOTS = 3
lastUsedSlot = 1  -- 上次手动保存/读取的槽位，自动存档跟随
saveSlotPanel = {
    open = false,
    mode = nil,       -- "save" | "load"
    slotRects = {},   -- 点击区域
    closeRect = nil,
    confirmSlot = nil, -- 覆盖确认的槽位号
    confirmRects = {}, -- 确认/取消按钮区域
    thumbs = {},       -- {[slot] = nvgImageHandle}  截图缩略图句柄
}
local relicDetail = {open = false, id = nil}  -- 遗物详情弹窗
local relicHudRects = {}  -- HUD上遗物图标的点击区域
relicDetail.skillOpen = false  -- 技能详情弹窗
relicDetail.skillKey = nil
relicDetail.skillRects = {}  -- HUD上技能图标的点击区域
BATTLE_ROUND_DURATION = 0.4   -- 每回合时长(秒)
local BATTLE_RESULT_DURATION = 0.4  -- 结果展示时长(秒)
battle = {
    active = false,
    monsters = {},          -- 多怪物数组 [{ch,name,maxHP,hp,displayHP,atk,def,dmg,baseDmg,playerDmg,sprite,spriteRow,skill,regen,preemptive,gold,shakeOffset,alive,effects}]
    playerHP = 0,           -- 战斗中玩家当前HP
    playerStartHP = 0,      -- 战斗开始时玩家HP
    round = 0,              -- 当前回合
    timer = 0,              -- 当前阶段计时
    phase = "",             -- "waiting_for_card","card_effect","end_turn","monster_atk","result"
    targetRow = 0,          -- 目标怪物所在行（移动目的地）
    targetCol = 0,          -- 目标怪物所在列
    shakeOffset = 0,        -- 玩家受击抖动偏移
    hasShield = false,      -- 圣盾被动
    -- 卡牌战斗字段
    deck = {},              -- 牌库（抽牌堆）
    hand = {},              -- 手牌 [{id, playerCardIdx, cardType}]
    discard = {},           -- 弃牌堆
    selectedCard = nil,     -- 选中的手牌索引
    cardEffects = {},       -- 全局持续效果（兼容旧代码）
    powerNext = false,      -- 蓄力：下次攻击2倍
    reflectActive = false,  -- 反射：下次受击反弹
    guardActive = false,    -- 格挡：本回合伤害变为1
    shieldHP = 0,           -- 护盾值（吸收伤害）
    hoveredCard = 0,        -- 鼠标悬浮的卡牌索引
    effectText = "",        -- 当前效果文字
    effectTimer = 0,        -- 效果文字计时
    -- 血条拖尾（显示用）
    displayPlayerHP = 0,    -- 玩家HP拖尾值（平滑追赶playerHP）
    -- MP系统
    mp = 0,                 -- 战斗中当前MP
    maxMp = 0,              -- 战斗中MP上限
    mpRegen = 0,            -- 每回合MP恢复量
    consumedCardIndices = {},  -- 战后需要从player.cards删除的索引列表
    -- 多敌人信息
    allEnemyPositions = {},     -- 所有参战敌人的位置 [{row, col, ch}]（用于战后清除地图）
    totalGold = 0,              -- 累计金币
    totalMonsterNames = {},     -- 所有参战怪物名称（用于结算消息）
    -- consumeOne 卡牌选择状态
    consumeSelect = nil,  -- nil=非选择模式, {cardIndex=打出的卡牌索引, cardId=卡牌id, card=卡牌数据}
    -- 倍速
    speed = 1,  -- 战斗倍速: 1=正常, 2=二倍速, 3=三倍速
}

-- 卡牌拖拽/选择状态
cardDrag = {
    active = false,
    cardIndex = 0,
    startX = 0, startY = 0,
    curX = 0, curY = 0,
    offsetX = 0, offsetY = 0,  -- 拖拽起始点相对卡牌左上角的偏移
}
-- battle.hoveredCard: 鼠标悬浮卡牌索引，存在 battle 表中以避免 upvalue 上限
-- 卡牌扇形动画状态（参考RM CardSystem）
cardAnims = {}  -- {[i] = {x, y, rot, scale}}
-- 发牌/弃牌动画状态
cardDealAnim = {
    active = false,
    timer = 0,
    count = 0,           -- 本次发牌数
    startIdx = 1,        -- 从手牌的哪个索引开始是新牌
    delayPerCard = 0.08, -- 每张牌的延迟间隔
}
cardDiscardAnim = {
    active = false,
    timer = 0,
    cards = {},  -- 弃牌动画中的卡牌 {x, y, rot, scale, targetX, targetY}
    duration = 0.45,
}
-- 诅咒卡植入动画（敌人塞卡时播放）
curseInsertAnim = {
    active = false,
    timer = 0,
    flyDuration = 0.6,   -- 飞行动画时长
    holdDuration = 0.8,  -- 到达后停留展示时长
    cards = {},  -- {cardId, monsterIdx}
}
-- 出牌队列：允许在 card_effect 期间继续拖拽出牌，顺序执行
local cardPlayQueue = {}  -- { card1_ref, card2_ref, ... }

-- 浮动伤害/治疗文字列表
-- {text, targetIdx(怪物索引,nil=玩家), timer, duration, r, g, b}
floatTexts = {}

-- 怪物信息浮窗（点击地图怪物时显示）
local monsterInfoPopup = {
    active = false,
    timer = 0,
    duration = 3.0,
    name = "",
    hp = 0, atk = 0, def = 0,
    exp = 0, gold = 0,
    row = 0, col = 0,  -- 格子位置（用于定位浮窗）
    hpLoss = 0, canWin = false,  -- 战斗预判
}

--- 添加浮动伤害/治疗文字
---@param text string 显示文本（如 "-9" 或 "+5"）
---@param targetIdx number|nil 怪物索引，nil表示玩家
---@param r number 红
---@param g number 绿
---@param b number 蓝
local function addFloatText(text, targetIdx, r, g, b)
    table.insert(floatTexts, {
        text = text,
        targetIdx = targetIdx,
        timer = 0,
        duration = 0.8,
        r = r or 255, g = g or 255, b = b or 100,
    })
end

-- 多次攻击分步动画系统
-- hits: { {fn = function() ... end}, ... } 每个 fn 执行一次攻击（含伤害计算、浮动文字、音效）
-- delay: 每次攻击间隔秒数
-- onComplete: 全部完成后回调（可选）
local multiHitState = nil  -- { hits={}, current=0, delay=0.25, timer=0, onComplete=nil }
local function startMultiHit(hits, delay, onComplete)
    multiHitState = {
        hits = hits,
        current = 0,
        delay = delay or 0.25,
        timer = 0,
        onComplete = onComplete,
    }
end

-- ============================================================
-- 辅助函数
-- ============================================================

--- Fisher-Yates洗牌
local function shuffleArray(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

--- 从player.cards构建战斗牌库（limited卡每场战斗重置可用次数）
local function buildBattleDeck()
    battle.deck = {}
    battle.discard = {}
    battle.consumedCardIndices = {}

    for idx, card in ipairs(player.cards) do
        local def = CARD_DEF[card.id]
        if def then
            local usesLeft = nil
            if def.cardType == "limited" then
                usesLeft = (def.maxUses or 1) + ((card.gem == "frost") and 1 or 0)
            end
            table.insert(battle.deck, {
                id = card.id,
                playerCardIdx = idx,
                cardType = def.cardType,
                gem = card.gem,
                usesLeft = usesLeft,
            })
        end
    end

    shuffleArray(battle.deck)
end

--- 从牌库抽牌到手牌（牌库空则洗入弃牌堆）
local function drawCards(count)
    local startIdx = #battle.hand + 1
    local drawn = 0
    for i = 1, count do
        if #battle.deck == 0 then
            if #battle.discard == 0 then
                break  -- 没有可抽的牌了
            end
            -- 弃牌堆洗回牌库
            for _, c in ipairs(battle.discard) do
                table.insert(battle.deck, c)
            end
            battle.discard = {}
            shuffleArray(battle.deck)
        end
        local card = table.remove(battle.deck)
        table.insert(battle.hand, card)
        drawn = drawn + 1
    end
    -- 启动发牌动画
    if drawn > 0 then
        cardDealAnim.active = true
        cardDealAnim.timer = 0
        cardDealAnim.count = drawn
        cardDealAnim.startIdx = startIdx
    end
    -- 保底：手牌中必须有至少一张攻击牌
    local hasStrike = false
    for _, c in ipairs(battle.hand) do
        if c.id == "strike" then hasStrike = true; break end
    end
    if not hasStrike and #battle.hand > 0 then
        -- 从牌库中找一张攻击牌换入
        for di = 1, #battle.deck do
            if battle.deck[di].id == "strike" then
                -- 将牌库中的攻击牌与手牌最后一张交换
                local strikeCard = table.remove(battle.deck, di)
                local replaced = battle.hand[#battle.hand]
                battle.hand[#battle.hand] = strikeCard
                table.insert(battle.deck, replaced)
                hasStrike = true
                break
            end
        end
        -- 牌库也没有攻击牌，从弃牌堆找
        if not hasStrike then
            for di = 1, #battle.discard do
                if battle.discard[di].id == "strike" then
                    local strikeCard = table.remove(battle.discard, di)
                    local replaced = battle.hand[#battle.hand]
                    battle.hand[#battle.hand] = strikeCard
                    table.insert(battle.discard, replaced)
                    break
                end
            end
        end
    end
end

--- 弃掉所有手牌到弃牌堆（带动画）
local function discardHand()
    -- 保存当前位置用于弃牌飞出动画
    cardDiscardAnim.cards = {}
    for i, card in ipairs(battle.hand) do
        local a = cardAnims[i]
        if a then
            table.insert(cardDiscardAnim.cards, {
                cardInfo = card,
                x = a.x, y = a.y, rot = a.rot, scale = a.scale,
                startX = a.x, startY = a.y, startRot = a.rot, startScale = a.scale,
            })
        end
        card.costReduction = nil  -- 清除节流减费（仅当回合有效）
        table.insert(battle.discard, card)
    end
    if #cardDiscardAnim.cards > 0 then
        cardDiscardAnim.active = true
        cardDiscardAnim.timer = 0
    end
    battle.hand = {}
    battle.selectedCard = nil
    cardAnims = {}
    battle.hoveredCard = 0
end

--- 获取当前动画帧的 SX (精灵图X偏移)
function getAnimSX()
    return plSpr.ox + ANIM_FRAMES[animFrameIndex] * plSpr.fw
end

--- 判断字符是否为怪物
function isMonster(ch)
    return MONSTER_DEF[ch] ~= nil
end

--- 判断字符是否为物品
function isItem(ch)
    return ITEM_DEF[ch] ~= nil
end

--- 判断字符是否为钥匙
function isKey(ch)
    return KEY_DEF[ch] ~= nil
end

--- 判断字符是否为门
function isDoor(ch)
    return DOOR_DEF[ch] ~= nil
end

--- 判断字符是否可通行
local function isPassable(ch)
    return ch ~= 'W'
end

--- 显示消息
local function showMessage(text, duration, r, g, b)
    msg.text = text
    msg.timer = duration or 2.0
    msg.color = {r or 255, g or 220, b or 100}
end

--- 初始化地图（深拷贝）
local function initMaps()
    maps = {}
    for f = 1, TOTAL_FLOORS do
        maps[f] = {}
        for r = 1, GRID do
            maps[f][r] = {}
            local rowStr = MAP_DATA[f][r]
            for c = 1, GRID do
                maps[f][r][c] = rowStr:sub(c, c)
            end
        end
    end
end

--- 查找指定字符在地图上的位置
local function findTile(floor, ch)
    for r = 1, GRID do
        for c = 1, GRID do
            if maps[floor][r][c] == ch then
                return r, c
            end
        end
    end
    return nil, nil
end

--- 计算战斗结果, 返回 {canWin, hpLoss, rounds}
function calcCombat(monsterCh)
    local m = MONSTER_DEF[monsterCh]
    if not m then return {canWin = false, hpLoss = 99999, rounds = 0} end

    local playerDmg = player.atk - m.def

    -- 怪物技能：魔攻 - 无视玩家防御
    local monsterAtk = getMonsterScaledATK(m)
    -- 怪物技能：狂暴 - HP低于50%时攻击翻倍（预估按1.5倍计算）
    if m.skill and m.skill.id == "berserk" then
        monsterAtk = math.floor(monsterAtk * 1.5)
    end
    local monsterDmg
    if m.skill and m.skill.id == "magicAtk" then
        monsterDmg = monsterAtk
    else
        monsterDmg = math.max(0, monsterAtk - player.def)
    end

    -- 怪物技能：反击 - 每回合额外固定伤害
    local counterDmg = 0
    if m.skill and m.skill.id == "counter" then
        counterDmg = m.skill.value or 0
    end
    monsterDmg = monsterDmg + counterDmg

    -- 坚韧被动：受到伤害降低25%（在怪物技能加成之后）
    if player.skills.tough then
        monsterDmg = math.floor(monsterDmg * 0.75)
    end

    -- 怪物技能：再生 - 每回合恢复HP，等效降低玩家伤害
    ---@type number
    local effectivePlayerDmg = playerDmg
    if m.skill and m.skill.id == "regen" then
        effectivePlayerDmg = playerDmg - (m.skill.value or 0)
    end

    if effectivePlayerDmg <= 0 then
        return {canWin = false, hpLoss = 99999, rounds = 0}
    end

    -- 暴击被动：首击1.5倍伤害
    local monsterHP = getMonsterScaledHP(m)
    if player.skills.crit then
        local firstHit = math.floor(playerDmg * 1.5)  -- 暴击用原始伤害
        monsterHP = monsterHP - firstHit
        if monsterHP <= 0 then
            -- 一击秒杀
            local hpLoss = 0
            -- 先攻：怪物先手打一回合
            if m.skill and m.skill.id == "preemptive" then
                hpLoss = hpLoss + monsterDmg
            end
            if player.skills.shield then hpLoss = 0 end  -- 圣盾免第一回合
            return {canWin = (player.hp > hpLoss), hpLoss = hpLoss, rounds = 1}
        end
        -- 剩余HP用有效伤害计算（考虑再生）
        local remainRounds = math.ceil(monsterHP / effectivePlayerDmg)
        local totalRounds = 1 + remainRounds
        local hpLoss = totalRounds * monsterDmg
        -- 先攻：额外一回合怪物攻击
        if m.skill and m.skill.id == "preemptive" then
            hpLoss = hpLoss + monsterDmg
        end
        -- 圣盾被动：首回合免伤
        if player.skills.shield then
            hpLoss = hpLoss - monsterDmg
        end
        return {canWin = (player.hp > hpLoss), hpLoss = hpLoss, rounds = totalRounds}
    end

    -- 无暴击的普通计算
    local rounds = math.ceil(monsterHP / effectivePlayerDmg)
    local hpLoss = rounds * monsterDmg

    -- 先攻：怪物先手，额外一回合伤害
    if m.skill and m.skill.id == "preemptive" then
        hpLoss = hpLoss + monsterDmg
    end

    -- 圣盾被动：首回合免伤
    if player.skills.shield then
        hpLoss = hpLoss - monsterDmg
    end
    hpLoss = math.max(0, hpLoss)

    return {canWin = (player.hp > hpLoss), hpLoss = hpLoss, rounds = rounds}
end

--- 计算临界值：攻击力再增加多少可以减少一回合击杀
--- 返回 {critAtk = 需增加的攻击, hpSave = 可节省的HP}
function calcCritical(monsterCh)
    local m = MONSTER_DEF[monsterCh]
    if not m then return nil end

    local playerDmg = player.atk - m.def
    local monsterAtk = getMonsterScaledATK(m)
    local monsterHP = getMonsterScaledHP(m)
    local monsterDmg = math.max(0, monsterAtk - player.def)

    -- 无法造成伤害：显示需要多少攻击才能破防
    if playerDmg <= 0 then
        return {critAtk = m.def - player.atk + 1, hpSave = monsterDmg}
    end

    local rounds = math.ceil(monsterHP / playerDmg)

    -- 已经1回合秒杀，无需更多攻击
    if rounds <= 1 then
        return {critAtk = 0, hpSave = 0}
    end

    -- 减少到 rounds-1 回合所需的新每回合伤害
    local newRounds = rounds - 1
    local newDmg = math.ceil(monsterHP / newRounds)
    local critAtk = newDmg - playerDmg
    local hpSave = monsterDmg  -- 少一回合节省一回合的伤害

    return {critAtk = critAtk, hpSave = hpSave}
end

--- 计算布局
local function calcLayout()
    statsH = math.max(90, logicalH * 0.15)
    local dpadH = math.max(90, logicalH * 0.18)
    local pad = 8
    local availW = logicalW - pad * 2
    local availH = logicalH - statsH - dpadH - pad * 2

    cellSize = math.floor(math.min(availW / GRID, availH / GRID))
    local gridW = cellSize * GRID
    local gridH = cellSize * GRID
    gridX = math.floor((logicalW - gridW) / 2)
    gridY = math.floor(statsH + pad + (availH - gridH) / 2)

    -- D-pad 位置
    dpadBtnSize = math.floor(math.min(dpadH * 0.35, logicalW * 0.12))
    dpadCenterX = logicalW / 2
    dpadCenterY = gridY + gridH + pad + dpadH / 2
end

-- ============================================================
-- 游戏逻辑
-- ============================================================

--- 启动移动动画
local function startMoveAnim(oldRow, oldCol)
    moveAnim.active = true
    moveAnim.fromRow = oldRow
    moveAnim.fromCol = oldCol
    moveAnim.t = 0
end

--- BFS 寻路: 返回从 (sr,sc) 到 (tr,tc) 的路径（不含起点，含终点）
--- 只经过空地/物品/楼梯/可击败怪物，遇到第一个非空地(怪物/物品/楼梯)就停
--- avoidDoors: true 时不经过门
local function findPath(sr, sc, tr, tc, avoidDoors)
    if sr == tr and sc == tc then return {} end

    local floor = player.floor
    local visited = {}
    local parent = {}
    local queue = {}
    local head = 1

    local function key(r, c) return r * 100 + c end

    visited[key(sr, sc)] = true
    queue[#queue + 1] = {sr, sc}

    local dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}

    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        local cr, cc = cur[1], cur[2]

        for _, d in ipairs(dirs) do
            local nr, nc = cr + d[1], cc + d[2]
            if nr >= 1 and nr <= GRID and nc >= 1 and nc <= GRID then
                local k = key(nr, nc)
                if not visited[k] then
                    local tile = maps[floor][nr][nc]
                    -- 可通行: 空地、玩家起始位、物品、钥匙、楼梯、可击败怪物、门
                    local passable = false
                    local canExpand = false  -- 是否可以继续扩展搜索
                    if tile == 'W' then
                        -- 墙壁：不可通行（前置判断，防止与 SKILL_DEF 等字符冲突）
                    elseif tile == '.' or tile == 'P' then
                        passable = true
                        canExpand = true
                    elseif isItem(tile) or isKey(tile) or isSkill(tile) or isGem(tile) or isRelic(tile) then
                        passable = true
                        canExpand = true
                    elseif tile == 'U' or tile == 'D' then
                        passable = true
                        canExpand = true  -- 楼梯可穿越（自动寻路时不触发换层）
                    elseif isDoor(tile) then
                        if avoidDoors then
                            -- 避门模式：门仅作为终点可达，不可穿越
                            if nr == tr and nc == tc then
                                passable = true
                                canExpand = false
                            end
                        else
                            passable = true
                            canExpand = true  -- 门可穿越（自动寻路时逐步开门）
                        end
                    elseif tile == SHOP_NPC_CHAR then
                        passable = true
                        canExpand = false  -- 商人仅作终点
                    elseif isMonster(tile) then
                        passable = true
                        canExpand = false  -- 怪物仅作终点，不可穿越
                    end

                    if passable then
                        visited[k] = true
                        parent[k] = {cr, cc}
                        if nr == tr and nc == tc then
                            -- 回溯路径
                            local path = {}
                            local pr, pc = tr, tc
                            while pr ~= sr or pc ~= sc do
                                table.insert(path, 1, {pr, pc})
                                local pk = parent[key(pr, pc)]
                                pr, pc = pk[1], pk[2]
                            end
                            return path
                        end
                        if canExpand then
                            queue[#queue + 1] = {nr, nc}
                        end
                    end
                end
            end
        end
    end

    return nil  -- 不可达
end

--- 检查胜利条件（当前开放内容终点 Boss 被击败）
function checkWin()
    local winFloor = math.min(CONTENT_MAX_FLOOR or TOTAL_FLOORS, TOTAL_FLOORS)
    local bossChar = BOSS_FLOORS[winFloor]
    if not bossChar or not maps[winFloor] then return false end
    for r = 1, GRID do
        for c = 1, GRID do
            if maps[winFloor][r][c] == bossChar then
                return false
            end
        end
    end
    return true
end

-- ============================================================
-- 音频系统
-- ============================================================

--- 初始化音频系统
local function initAudio()
    audioScene = Scene()
    audioScene:CreateComponent("Octree")

    -- BGM 节点和声源
    bgmNode = audioScene:CreateChild("BGM")
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource:SetSoundType("Music")
    bgmSource:SetGain(0.4)

    -- 预加载所有音效
    for name, path in pairs(SFX_PATHS) do
        local sound = cache:GetResource("Sound", path)
        if sound then
            sound:SetLooped(false)
            sfxSounds[name] = sound
        else
            log:Write(LOG_WARNING, "Failed to load SFX: " .. path)
        end
    end

    -- 设置主音量
    audio:SetMasterGain("Music", 0.35)
    audio:SetMasterGain("Effect", 0.8)

    log:Write(LOG_INFO, "音频系统初始化完成")
end

--- 根据楼层播放对应BGM
local function playBgmForFloor(floor)
    local trackKey = "explore"
    for _, range in ipairs(FLOOR_BGM) do
        if floor >= range.from and floor <= range.to then
            trackKey = range.track
            break
        end
    end
    -- 如果BGM没变就不切换
    if trackKey == currentBgmTrack then return end
    currentBgmTrack = trackKey

    local path = BGM_TRACKS[trackKey]
    if not path then return end

    local sound = cache:GetResource("Sound", path)
    if sound then
        sound:SetLooped(true)
        bgmSource:Play(sound)
        log:Write(LOG_INFO, "BGM切换: " .. trackKey .. " (" .. path .. ")")
    end
end

--- 播放音效
function playSfx(name, gain)
    local sound = sfxSounds[name]
    if not sound then return end
    if not audioScene then return end

    local sfxNode = audioScene:CreateChild("SFX")
    local source = sfxNode:CreateComponent("SoundSource")
    source:SetSoundType("Effect")
    source:SetGain(gain or 1.0)
    source.autoRemoveMode = REMOVE_NODE
    source:Play(sound)
end

-- ============================================================
-- 存档系统
-- ============================================================

--- 序列化地图为紧凑字符串表
local function serializeMaps()
    local data = {}
    for f = 1, TOTAL_FLOORS do
        data[f] = {}
        for r = 1, GRID do
            local row = ""
            for c = 1, GRID do
                row = row .. maps[f][r][c]
            end
            data[f][r] = row
        end
    end
    return data
end

--- 从字符串表恢复地图
local function deserializeMaps(data)
    maps = {}
    for f = 1, TOTAL_FLOORS do
        maps[f] = {}
        for r = 1, GRID do
            maps[f][r] = {}
            local rowStr = data[f][r]
            for c = 1, GRID do
                maps[f][r][c] = rowStr:sub(c, c)
            end
        end
    end
end

_cjson = _G["cjson"]

-- 从 JSON 加载卡牌定义
do
    local file = cache:GetFile("data/card.json")
    if file then
        local str = file:ReadString()
        file:Close()
        local ok, data = pcall(_cjson.decode, str)
        if ok and type(data) == "table" then
            CARD_DEF = data
            local count = 0
            for _ in pairs(CARD_DEF) do count = count + 1 end
            log:Write(LOG_INFO, "[CardDef] 已从 card.json 加载 " .. count .. " 张卡牌")
        else
            log:Write(LOG_ERROR, "[CardDef] card.json 解析失败!")
        end
    else
        log:Write(LOG_ERROR, "[CardDef] 未找到 data/card.json!")
    end
end

--- 获取槽位文件路径
function slotPath(slot)
    return "saves/slot_" .. slot .. ".json"
end
local function slotScreenshotPath(slot)
    return "saves/slot_" .. slot .. ".png"
end

--- 迁移旧存档（save.json → slot 1）
local function migrateOldSave()
    if fileSystem:FileExists("save.json") and not fileSystem:FileExists(slotPath(1)) then
        fileSystem:CreateDir("saves")
        local src = File("save.json", FILE_READ)
        if src:IsOpen() then
            local content = src:ReadString()
            src:Close()
            local dst = File(slotPath(1), FILE_WRITE)
            if dst:IsOpen() then
                dst:WriteString(content)
                dst:Close()
                log:Write(LOG_INFO, "[Save] 旧存档已迁移到 slot 1")
            end
        end
    end
end

--- 保存游戏存档到指定槽位
local function saveGame(slot)
    slot = slot or lastUsedSlot or 1
    fileSystem:CreateDir("saves")
    local saveData = {
        version = 1,
        timestamp = os.time(),
        player = {
            row = player.row, col = player.col, floor = player.floor,
            hp = player.hp, atk = player.atk, def = player.def,
            gold = player.gold,
            yellowKeys = player.yellowKeys, blueKeys = player.blueKeys, redKeys = player.redKeys,
            facing = player.facing,
            skills = player.skills,
            relics = player.relics,
            gems = player.gems,
            cards = player.cards,
            cardCostMods = player.cardCostMods or {},
            mp = player.mp, maxMp = player.maxMp, mpRegen = player.mpRegen,
            drawCount = player.drawCount,
            shopUpgradeBuys = player.shopUpgradeBuys or {},
            shopSoldCards = player.shopSoldCards or {},
            level = player.level, exp = player.exp,
            charIdx = player.charIdx or 1,
        },
        maps = serializeMaps(),
        selectedMode = charSelect.selectedMode,
        selectedDifficulty = getDifficultyIndex(),
    }
    local ok, jsonStr = pcall(_cjson.encode, saveData)
    if not ok then
        log:Write(LOG_ERROR, "Save failed: encode error")
        return false
    end
    local file = File(slotPath(slot), FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
    else
        log:Write(LOG_ERROR, "Save failed: cannot open file")
    end
    -- 云存档（WASM 平台本地文件刷新即丢，云端持久化）
    if clientCloud then
        clientCloud:Set("save_slot_" .. slot, jsonStr, {
            ok = function() log:Write(LOG_INFO, "[Save] 云存档 slot " .. slot .. " 成功") end,
            error = function(code, reason) log:Write(LOG_WARNING, "[Save] 云存档失败: " .. tostring(reason)) end
        })
    end
    lastUsedSlot = slot
    return true
end

--- 检查是否存在存档（无参数检查任意槽位，有参数检查指定槽位）
function hasSaveFile(slot)
    if slot then
        return fileSystem:FileExists(slotPath(slot))
    end
    -- 先检查旧存档
    if fileSystem:FileExists("save.json") then return true end
    for i = 1, MAX_SAVE_SLOTS do
        if fileSystem:FileExists(slotPath(i)) then return true end
    end
    return false
end

--- 获取存档槽位摘要信息
local function getSaveSlotInfo(slot)
    local path = slotPath(slot)
    if not fileSystem:FileExists(path) then return nil end
    local file = File(path, FILE_READ)
    if not file:IsOpen() then return nil end
    local jsonStr = file:ReadString()
    file:Close()
    local ok, data = pcall(_cjson.decode, jsonStr)
    if not ok or not data or not data.player then return nil end
    local p = data.player
    local info = {
        floor = p.floor or 1,
        hp = p.hp or 0,
        atk = p.atk or 0,
        def = p.def or 0,
        gold = p.gold or 0,
        level = p.level or 1,
        cards = p.cards and #p.cards or 0,
        timestamp = data.timestamp,
        hasScreenshot = fileSystem:FileExists(slotScreenshotPath(slot)),
    }
    return info
end

--- 读取游戏存档，成功返回 true
local function loadGame(slot)
    slot = slot or lastUsedSlot or 1
    -- 向下兼容：如果指定槽位不存在但旧存档存在，先迁移
    if not hasSaveFile(slot) and fileSystem:FileExists("save.json") then
        migrateOldSave()
    end
    -- 优先本地文件（同一会话内有效）
    local jsonStr = nil
    if hasSaveFile(slot) then
        local file = File(slotPath(slot), FILE_READ)
        if file:IsOpen() then
            jsonStr = file:ReadString()
            file:Close()
        end
    end
    if not jsonStr or jsonStr == "" then return false end
    local ok, saveData = pcall(_cjson.decode, jsonStr)
    if not ok or not saveData or not saveData.player then
        log:Write(LOG_ERROR, "Load failed: decode error")
        return false
    end

    -- 恢复角色数据
    local p = saveData.player
    player.row = p.row; player.col = p.col; player.floor = p.floor
    player.hp = p.hp; player.atk = p.atk; player.def = p.def
    player.gold = p.gold
    player.yellowKeys = p.yellowKeys; player.blueKeys = p.blueKeys; player.redKeys = p.redKeys
    player.facing = p.facing or "down"
    player.skills = p.skills or {}
    player.relics = p.relics or {}
    player.gems = p.gems or {}
    player.cardCostMods = p.cardCostMods or {}
    player.cards = p.cards or {}
    player.mp = p.mp or 5; player.maxMp = p.maxMp or 10; player.mpRegen = p.mpRegen or 5
    player.drawCount = p.drawCount or 3
    player.shopUpgradeBuys = type(p.shopUpgradeBuys) == "table" and p.shopUpgradeBuys or {}
    player.shopSoldCards = p.shopSoldCards or {}
    player.level = p.level or 1; player.exp = p.exp or 0
    player.charIdx = p.charIdx or 1

    -- 恢复角色精灵
    local char = CHARACTER_LIST[player.charIdx] or CHARACTER_LIST[1]
    PLAYER_SPRITE_PATH = char.sprite
    if spr.player and spr.player ~= 0 then
        nvgDeleteImage(nvgCtx, spr.player)
        spr.player = nil
    end
    local ph = nvgCreateImage(nvgCtx, PLAYER_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if ph ~= -1 and ph ~= 0 then
        spr.playerW, spr.playerH = nvgImageSize(nvgCtx, ph)
        spr.player = ph
    end
    if char.spriteConfig and spr.player then
        local sc = char.spriteConfig
        local blockW = spr.playerW / sc.cols
        local blockH = spr.playerH / sc.rows
        plSpr.fw = blockW / 3
        plSpr.fh = blockH / 4
        plSpr.ox = (sc.charIndex % sc.cols) * blockW
        plSpr.oy = math.floor(sc.charIndex / sc.cols) * blockH
    else
        plSpr.fw = (spr.playerW or 144) / 3
        plSpr.fh = (spr.playerH or 192) / 4
        plSpr.ox = 0
        plSpr.oy = 0
    end

    -- 恢复地图
    charSelect.selectedMode = saveData.selectedMode or 2
    if charSelect.selectedMode == 1 then charSelect.selectedMode = 2 end  -- 随机地图暂不可用
    charSelect.selectedDifficulty = tonumber(saveData.selectedDifficulty) or 1
    if not DIFFICULTY_DEF[charSelect.selectedDifficulty] then charSelect.selectedDifficulty = 1 end
    if charSelect.selectedMode == 2 then
        local mapData, totalFloors = loadMapJsonFromCache()
        if mapData and next(mapData) then
            TOTAL_FLOORS = totalFloors
            BOSS_FLOORS = {[10]="J",[18]="X",[20]="X",[30]="L",[40]="N",[50]="7"}
        else
            local fm = require("FixedMaps")
            TOTAL_FLOORS = fm.TOTAL_FLOORS
            BOSS_FLOORS = fm.BOSS_FLOORS
        end
    else
        TOTAL_FLOORS = 50
        BOSS_FLOORS = {[10]="J",[18]="X",[20]="X",[30]="L",[40]="N",[50]="7"}
    end
    deserializeMaps(saveData.maps)

    -- 重置战斗/UI状态
    gameState = "playing"
    msg.text = ""; msg.timer = 0
    moveAnim.active = false
    autoPath = {}
    battle.active = false
    levelUp.open = false; levelUp.pendingCount = 0
    shopOpen = false

    playBgmForFloor(player.floor)
    lastUsedSlot = slot
    showMessage("存档已加载 - 第 " .. player.floor .. " 层 (槽位" .. slot .. ")", 2.0, 100, 255, 100)
    return true
end

--- 检查游戏结束
function checkGameOver()
    if player.hp <= 0 then
        gameState = "gameover"
        if bgmSource then bgmSource:Stop() end
        playSfx("gameover", 1.0)
        return true
    end
    if checkWin() then
        gameState = "win"
        if bgmSource then bgmSource:Stop() end
        playSfx("victory", 1.0)
        return true
    end
    return false
end

--- 获取第一个存活怪物的索引
function getFirstAliveMonster()
    for i, mo in ipairs(battle.monsters) do
        if mo.alive then return i end
    end
    return nil
end

--- 检查是否所有怪物都死亡
local function allMonstersDead()
    for _, mo in ipairs(battle.monsters) do
        if mo.alive then return false end
    end
    return true
end

--- 计算所有存活怪物的总伤害
local function getTotalMonsterDmg()
    local total = 0
    for _, mo in ipairs(battle.monsters) do
        if mo.alive then total = total + mo.dmg end
    end
    return total
end

-- ============================================================
-- 经验 / 升级 系统
-- ============================================================

--- 升级所需经验
local function expToNextLevel(level)
    return 5 + level * 5
end

--- 根据怪物地图字符获取经验值
local function getMonsterExp(ch)
    local m = MONSTER_DEF[ch]
    if not m then return 0 end
    return m.exp or 0
end

--- 升级选卡池（按稀有度和等级分层）
-- 精良卡池（低等级即可获得）
local UNCOMMON_CARD_POOL = {"heal","guard","power","heavyStrike","shield","thrifty","alchemy"}
-- 稀有卡池（等级5+）
local RARE_CARD_POOL = {"drain","weaken","reflect","execute","pierce","thunder","haste","sacrifice","empower","gambit"}
-- 史诗卡池（等级10+）
local EPIC_CARD_POOL = {"cleave","ironWall","thorns","fusion"}
-- 传说卡池（等级15+）
local LEGENDARY_CARD_POOL = {"deathDance","oblivion","immortal","warCry"}

--- 随机选 3 张候选卡牌（按等级概率加权）
local function generateLevelUpCandidates(guaranteeTop)
    -- 构建可用卡池
    local pool = {}
    for _, id in ipairs(UNCOMMON_CARD_POOL) do table.insert(pool, id) end
    if player.level >= 5 then
        for _, id in ipairs(RARE_CARD_POOL) do table.insert(pool, id) end
    end
    if player.level >= 10 then
        for _, id in ipairs(EPIC_CARD_POOL) do table.insert(pool, id) end
    end
    if player.level >= 15 then
        for _, id in ipairs(LEGENDARY_CARD_POOL) do table.insert(pool, id) end
    end
    -- 角色专属卡
    if player.charIdx then
        local char = CHARACTER_LIST[player.charIdx]
        if char and char.exclusive then
            for _, id in ipairs(char.exclusive) do table.insert(pool, id) end
        end
    end

    -- 确定当前最高可用稀有度
    local topRarity = "uncommon"
    if player.level >= 15 then topRarity = "legendary"
    elseif player.level >= 10 then topRarity = "epic"
    elseif player.level >= 5 then topRarity = "rare"
    end

    -- 稀有度权重（根据等级动态调整）
    local lv = player.level or 1
    local rarityWeights = {
        common    = math.max(5,  40 - lv * 3),
        uncommon  = math.max(15, 50 - lv * 2),
        rare      = math.min(40, 15 + lv * 2),
        epic      = math.min(30, math.max(0, (lv - 8) * 3)),
        legendary = math.min(20, math.max(0, (lv - 13) * 2.5)),
    }

    -- 加权随机抽取
    local candidates = {}
    local used = {}
    for _ = 1, 3 do
        -- 为池中每张卡计算权重
        local weighted = {}
        local totalWeight = 0
        for _, id in ipairs(pool) do
            if not used[id] then
                local def = CARD_DEF[id]
                local w = rarityWeights[def and def.rarity or "uncommon"] or 10
                totalWeight = totalWeight + w
                table.insert(weighted, {id = id, weight = w, cumulative = totalWeight})
            end
        end
        if #weighted == 0 then break end
        -- 轮盘选择
        local roll = math.random() * totalWeight
        for _, entry in ipairs(weighted) do
            if roll <= entry.cumulative then
                table.insert(candidates, entry.id)
                used[entry.id] = true
                break
            end
        end
    end

    -- 广告刷新保底：确保至少一张最高稀有度卡牌
    if guaranteeTop and #candidates > 0 then
        local hasTop = false
        for _, id in ipairs(candidates) do
            local def = CARD_DEF[id]
            if def and def.rarity == topRarity then hasTop = true; break end
        end
        if not hasTop then
            -- 从池中筛选最高稀有度卡牌，随机替换最后一张
            local topPool = {}
            for _, id in ipairs(pool) do
                if not used[id] then
                    local def = CARD_DEF[id]
                    if def and def.rarity == topRarity then
                        table.insert(topPool, id)
                    end
                end
            end
            if #topPool > 0 then
                candidates[#candidates] = topPool[math.random(#topPool)]
            end
        end
    end

    return candidates
end

--- 打开升级选卡弹窗
local function openLevelUpPopup()
    if levelUp.pendingCount <= 0 then
        levelUp.open = false
        return
    end
    levelUp.candidates = generateLevelUpCandidates()
    levelUp.selectedIndex = nil
    levelUp.adRefreshUsed = 0
    levelUp.open = true
end

--- 选择升级卡牌
local function selectLevelUpCard(index)
    local cardId = levelUp.candidates[index]
    if not cardId then return end
    local def = CARD_DEF[cardId]
    if not def then return end

    local uses = def.maxUses
    table.insert(player.cards, {id = cardId, usesLeft = uses})

    showMessage("升级！获得卡牌: " .. def.name, 2.0, 100, 255, 100)
    playSfx("victory", 0.5)

    levelUp.pendingCount = levelUp.pendingCount - 1
    if levelUp.pendingCount > 0 then
        openLevelUpPopup()
    else
        levelUp.open = false
    end
end

--- 发放经验并处理升级
local function awardExp(amount)
    if amount <= 0 then return end
    player.exp = player.exp + amount
    local leveledUp = false
    while player.exp >= expToNextLevel(player.level) do
        player.exp = player.exp - expToNextLevel(player.level)
        player.level = player.level + 1
        levelUp.pendingCount = levelUp.pendingCount + 1
        leveledUp = true
    end
    if leveledUp then
        openLevelUpPopup()
    end
end

--- 战斗结算：战斗动画结束后调用
local function finishBattle()
    battle.active = false
    cardDrag.active = false
    cardAnims = {}
    battle.hoveredCard = 0
    pileView.open = false
    pileView.scroll = 0

    -- 同步MP回玩家
    player.mp = battle.mp

    -- 删除已消耗的一次性卡牌（按降序删除避免索引偏移）
    if #battle.consumedCardIndices > 0 then
        table.sort(battle.consumedCardIndices, function(a, b) return a > b end)
        for _, idx in ipairs(battle.consumedCardIndices) do
            if idx >= 1 and idx <= #player.cards then
                table.remove(player.cards, idx)
            end
        end
    end

    -- 扣血
    player.hp = battle.playerHP
    local hpLoss = battle.playerStartHP - battle.playerHP

    -- 偷窃技能：怪物每回合偷取金币
    local stolenGold = 0
    for _, mo in ipairs(battle.monsters) do
        if mo.skill and mo.skill.id == "steal" then
            stolenGold = stolenGold + (mo.skill.value or 0) * battle.round
        end
    end
    if stolenGold > 0 then
        player.gold = math.max(0, player.gold - stolenGold)
        addFloatText("-" .. stolenGold .. "G(偷窃)", nil, 255, 180, 50)
    end

    -- 贪婪被动：双倍金币（用总金币）
    local goldGain = battle.totalGold
    if player.skills.greed then
        goldGain = goldGain * 2
    end
    player.gold = player.gold + goldGain

    -- 吸血被动：回复所有被击杀怪物总HP的10%
    local vampHeal = 0
    if player.skills.vampire then
        local totalMHP = 0
        for _, pos in ipairs(battle.allEnemyPositions) do
            local mdef = MONSTER_DEF[pos.ch]
            if mdef then totalMHP = totalMHP + getMonsterScaledHP(mdef) end
        end
        vampHeal = math.floor(totalMHP * 0.10)
        if vampHeal > 0 then
            player.hp = player.hp + vampHeal
        end
    end

    -- 清除所有参战敌人的地图位置（开发者战斗不修改地图）
    if not battle.devBattle then
        for _, pos in ipairs(battle.allEnemyPositions) do
            maps[player.floor][pos.row][pos.col] = '.'
        end
        -- 移动到目标怪物位置
        local oldRow, oldCol = player.row, player.col
        player.row = battle.targetRow
        player.col = battle.targetCol
        startMoveAnim(oldRow, oldCol)
    end
    -- 玩家存活才播放胜利音效
    if player.hp > 0 then
        playSfx("victory", 0.7)
    end

    -- 计算经验
    local totalExp = 0
    for _, pos in ipairs(battle.allEnemyPositions) do
        totalExp = totalExp + getMonsterExp(pos.ch)
    end

    -- 构建消息
    local nameStr = table.concat(battle.totalMonsterNames, "+")
    local resultMsg = "击败 " .. nameStr .. "！ HP-" .. hpLoss .. " 金币+" .. goldGain
    if vampHeal > 0 then
        resultMsg = resultMsg .. " 吸血+" .. vampHeal
    end
    if totalExp > 0 then
        resultMsg = resultMsg .. " EXP+" .. totalExp
    end
    -- 诅咒技能已改为攻击时临时植入（仅本场战斗内有效）

    -- Boss 掉落卡牌
    local bossDropMsg = ""
    for _, pos in ipairs(battle.allEnemyPositions) do
        local drop = BOSS_DROP[pos.ch]
        if drop and drop.pool and #drop.pool > 0 then
            -- 从掉落池中随机选一张玩家没有的卡，如果都有则随机选
            local candidates = {}
            for _, cardId in ipairs(drop.pool) do
                local alreadyHas = false
                for _, pc in ipairs(player.cards) do
                    if pc.id == cardId then alreadyHas = true; break end
                end
                if not alreadyHas then candidates[#candidates + 1] = cardId end
            end
            if #candidates == 0 then candidates = drop.pool end
            local dropCardId = candidates[math.random(#candidates)]
            local cdef = CARD_DEF[dropCardId]
            if cdef then
                local usesLeft = -1
                if cdef.cardType == "limited" then usesLeft = cdef.maxUses or 1 end
                table.insert(player.cards, {id = dropCardId, usesLeft = usesLeft})
                local rDef = RARITY_DEF[drop.rarity or cdef.rarity or "rare"]
                bossDropMsg = bossDropMsg .. " Boss掉落[" .. (rDef and rDef.name or "") .. "]" .. cdef.name .. "！"
            end
        end
    end
    if bossDropMsg ~= "" then
        resultMsg = resultMsg .. bossDropMsg
    end

    showMessage(resultMsg, 3.0, 255, 200, 50)
    checkGameOver()

    -- 发放经验（通关/死亡时跳过，避免升级弹窗和结束画面重叠）
    if totalExp > 0 and gameState == "playing" then
        awardExp(totalExp)
    end

    -- 恢复战斗前的自动寻路路径（如果有）
    if battle.savedAutoPath and #battle.savedAutoPath > 0 and gameState == "playing" then
        autoPath = battle.savedAutoPath
        autoPathDest = battle.savedAutoPathDest
        autoPathTimer = 0
    end
    battle.savedAutoPath = nil
    battle.savedAutoPathDest = nil
end

--- 逃跑：退出战斗，敌人不变不会死
local function fleeBattle()
    battle.active = false
    cardDrag.active = false
    cardAnims = {}
    battle.hoveredCard = 0
    pileView.open = false
    pileView.scroll = 0

    -- 同步HP和MP回玩家
    player.hp = battle.playerHP
    player.mp = battle.mp

    -- 逃跑后检查死亡
    if checkGameOver() then return end

    -- 不清除地图敌人，不给金币/经验/奖励，不移动玩家位置
    showMessage("逃跑成功！", 1.5, 255, 200, 100)

    -- 恢复自动寻路
    if battle.savedAutoPath and #battle.savedAutoPath > 0 and gameState == "playing" then
        autoPath = battle.savedAutoPath
        autoPathDest = battle.savedAutoPathDest
        autoPathTimer = 0
    end
    battle.savedAutoPath = nil
    battle.savedAutoPathDest = nil
end

--- 打出卡牌: 处理效果并转入下一阶段
--- 获取卡牌实际费用（考虑减费效果）
function getCardCost(cardInfo)
    local def = CARD_DEF[cardInfo.id]
    if not def then return 0 end
    local gemReduce = 0
    if cardInfo.gem == "thrift" then gemReduce = 1 end
    local permReduce = (player.cardCostMods and player.cardCostMods[cardInfo.id]) or 0
    return math.max(0, (def.mpCost or 0) - (cardInfo.costReduction or 0) - gemReduce - permReduce)
end

--- 被消耗卡牌的宝石触发（视为打出）
local playCard  -- 前向声明（echo宝石需要在triggerEatenGem中调用）

--- @param eaten table 被消耗的卡牌信息
--- @param dmgDealt number 本次造成的伤害总量
--- @param healDone number 本次治愈的HP总量
--- @param shieldDone number 本次获得的护盾总量
--- @param targetIdx number|nil 单体目标索引（nil=AoE/无目标）
function triggerEatenGem(eaten, dmgDealt, healDone, shieldDone, targetIdx)
    if not eaten or not eaten.gem then return end
    local eGem = eaten.gem
    local gd = GEM_DEF[eGem]
    if not gd then return end
    addFloatText(gd.name, nil, gd.r, gd.g, gd.b)

    if eGem == "flame" and dmgDealt > 0 then
        local bonus = math.max(1, math.floor(dmgDealt * 0.3))
        if targetIdx then
            local mo = battle.monsters[targetIdx]
            if mo and mo.alive then
                mo.hp = mo.hp - bonus
                addFloatText("-" .. bonus, targetIdx, 255, 100, 30)
            end
        else
            for mi, mo in ipairs(battle.monsters) do
                if mo.alive then
                    mo.hp = mo.hp - bonus
                    addFloatText("-" .. bonus, mi, 255, 100, 30)
                end
            end
        end
    elseif eGem == "holy" then
        if healDone > 0 then
            local bonus = math.max(1, math.floor(healDone * 0.5))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bonus)
            addFloatText("+" .. bonus, nil, 255, 230, 80)
        end
        if shieldDone > 0 then
            local bonus = math.max(1, math.floor(shieldDone * 0.5))
            battle.shieldHP = battle.shieldHP + bonus
            addFloatText("盾+" .. bonus, nil, 255, 230, 80)
        end
    elseif eGem == "blood" and dmgDealt > 0 then
        local bonus = math.max(1, math.floor(dmgDealt * 0.1))
        battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bonus)
        addFloatText("+" .. bonus, nil, 200, 40, 60)
    elseif eGem == "thunder" and dmgDealt > 0 then
        -- 溅射20%伤害给其他存活怪物
        local splash = math.max(1, math.floor(dmgDealt * 0.2))
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive and mi ~= targetIdx then
                mo.hp = mo.hp - splash
                addFloatText("⚡" .. splash, mi, 180, 100, 255)
            end
        end
    elseif eGem == "thrift" then
        battle.mp = math.min(battle.maxMp, battle.mp + 1)
        addFloatText("MP+1", nil, 80, 220, 180)
    elseif eGem == "frost" then
        -- 寒冰石被动效果：卡片消耗次数+1（无主动消耗触发效果）
    elseif eGem == "echo" then
        -- 余韵石：被卡牌效果弃掉时视为免费打出一次
        local ecDef = CARD_DEF[eaten.id]
        if ecDef and ecDef.type ~= "curse"
           and not ecDef.consumeOne and not ecDef.consumeHand
           and not eaten._echoFiring then
            -- 标记防递归
            eaten._echoFiring = true
            -- 临时插回手牌末尾并免费打出
            eaten.costReduction = (eaten.costReduction or 0) + 99
            table.insert(battle.hand, eaten)
            addFloatText("🔁" .. ecDef.name, nil, 160, 120, 255)
            playCard(#battle.hand)
            eaten._echoFiring = nil
        end
    end
end

--- 通过卡牌引用在手牌中找到索引并打出
local function playCardByRef(cardRef)
    for i, c in ipairs(battle.hand) do
        if c == cardRef then
            playCard(i)
            return true
        end
    end
    return false
end

playCard = function(cardIndex)
    local card = battle.hand[cardIndex]
    if not card then return end
    local def = CARD_DEF[card.id]
    if not def then return end

    -- consumeOne 回调执行（MP 已在第一次调用时扣除）
    local isConsumeCallback = battle.consumeSelect and battle.consumeSelect.eatIdx

    if not isConsumeCallback then
        -- 检查是否无法打出
        if def.unplayable then
            battle.effectText = def.name .. " 无法打出"
            battle.effectTimer = 0.5
            battle.timer = 0
            return
        end
        -- 巨力挥砍：本回合无法攻击
        if battle.titanSkipActive and def.type == "attack" then
            battle.effectText = "本回合无法攻击!"
            battle.effectTimer = 0.8
            battle.timer = 0
            return
        end
        -- 检查MP
        local actualCost = getCardCost(card)
        if actualCost > battle.mp then
            battle.effectText = def.name .. " MP不足(" .. actualCost .. ")"
            battle.effectTimer = 0.5
            battle.timer = 0  -- 重置timer防止队列连锁调用时卡住
            return
        end

        -- consumeOne 卡牌：进入手牌选择模式（而非随机消耗）
        if def.consumeOne then
            -- 检查是否有其他手牌可消耗
            local hasCandidates = false
            for i = 1, #battle.hand do
                if i ~= cardIndex then hasCandidates = true; break end
            end
            if hasCandidates then
                -- 先扣 MP
                if actualCost > 0 then
                    battle.mp = battle.mp - actualCost
                end
                battle.consumeSelect = {
                    cardIndex = cardIndex,
                    cardId = card.id,
                    card = card,
                    mpCost = actualCost,
                }
                battle.selectedCard = nil
                battle.effectText = "选择要消耗的手牌"
                battle.effectTimer = 99  -- 持续显示直到选择
                return
            end
            -- 无其他手牌可消耗 → 直接失败
            battle.effectText = def.name .. " 无牌可消耗！"
            battle.effectTimer = 0.5
            return
        end

        -- 扣除MP
        if actualCost > 0 then
            battle.mp = battle.mp - actualCost
        end
    end

    battle.selectedCard = nil

    -- 获取当前目标怪物，仅攻击/debuff类需要
    local ti = battle.targetIdx or getFirstAliveMonster()
    local target = ti and battle.monsters[ti] or nil
    -- 破甲之力：无视目标DEF，直接用ATK计算
    local pDmg
    local armorStanceActive = battle.armorStanceNext and target ~= nil
    if armorStanceActive then
        local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
        pDmg = math.max(0, effAtk)
    else
        pDmg = target and math.max(0, target.playerDmg) or 0
    end
    local dmg = 0
    local gem = card.gem  -- 附魔宝石ID（可能为nil）
    local thunderSplashDmg = 0   -- 雷霆石溅射：记录本次攻击总伤害
    local thunderSplashTarget = ti  -- 雷霆石溅射：排除的主目标

    -- 暴击被动：首击1.5倍伤害
    local isCrit = false
    if player.skills.crit and not battle.critUsed and pDmg > 0 then
        pDmg = math.floor(pDmg * 1.5)
        isCrit = true
    end

    -- 易伤倍率：目标有易伤层数时伤害x1.5
    local isVulnerable = false
    if target and target.effects and target.effects.vulnerable and target.effects.vulnerable > 0 then
        pDmg = math.floor(pDmg * 1.5)
        isVulnerable = true
    end

    -- 怒火倍率：每层+10%伤害
    local furyStacks = battle.fury or 0
    local furyMult = 1 + furyStacks * 0.1
    if furyStacks > 0 then
        pDmg = math.floor(pDmg * furyMult)
    end

    if card.id == "strike" then
        if not target then goto card_done end
        dmg = pDmg
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.effectText = ""
        addFloatText("-" .. dmg, ti, 255, 50, 50)
        target.shakeOffset = 4
        playSfx("attack", 0.6)

    elseif card.id == "heal" then
        local healAmt = math.floor(player.def * 0.5)
        if gem == "holy" then healAmt = math.floor(healAmt * 1.5) end
        local oldHP = battle.playerHP
        battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + healAmt)
        healAmt = math.floor(battle.playerHP - oldHP)
        battle.effectText = ""
        addFloatText("+" .. healAmt, nil, 100, 255, 100)
        playSfx("pickup", 0.5)

    elseif card.id == "guard" then
        battle.guardActive = true
        if gem == "holy" then
            battle.guardGemHoly = true  -- 圣光格挡：反弹25%
        end
        battle.effectText = "格挡！本回合伤害变为1"
        playSfx("pickup", 0.5)

    elseif card.id == "poison" then
        local poisonStacks = 5
        for _, mo in ipairs(battle.monsters) do
            if mo.alive then
                mo.effects.poison = (mo.effects.poison or 0) + poisonStacks
            end
        end
        battle.effectText = "淬毒！全体毒+" .. poisonStacks
        playSfx("attack", 0.4)

    elseif card.id == "venomBlade" then
        if not target then goto card_done end
        dmg = pDmg
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        if target.hp <= 0 then target.hp = 0; target.alive = false end
        local poisonAdd = 3
        target.effects.poison = (target.effects.poison or 0) + poisonAdd
        battle.effectText = "毒刃！" .. dmg .. "伤害 毒+" .. poisonAdd
        playSfx("attack", 0.5)

    elseif card.id == "shieldSlam" then
        if not target then goto card_done end
        dmg = battle.shieldHP or 0
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        if target.hp <= 0 then target.hp = 0; target.alive = false end
        battle.effectText = "护盾猛击！" .. dmg .. "伤害"
        playSfx("attack", 0.5)

    elseif card.id == "bloodRite" then
        local hpCost = math.floor(player.atk * 0.3)
        battle.hp = math.max(1, battle.hp - hpCost)
        battle.playerHP = battle.hp
        battle.mp = math.min(battle.maxMp, battle.mp + 2)
        battle.effectText = "血祭！-" .. hpCost .. "HP +2MP"
        playSfx("hurt", 0.3)

    elseif card.id == "power" then
        battle.powerNext = true
        battle.effectText = "蓄力！下次攻击x2"
        playSfx("pickup", 0.5)

    elseif card.id == "drain" then
        if not target then goto card_done end
        dmg = pDmg
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        local healDrain = dmg
        if gem == "blood" then healDrain = math.floor(healDrain * 1.1) end
        battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + healDrain)
        battle.effectText = ""
        addFloatText("-" .. dmg, ti, 255, 50, 50)
        addFloatText("+" .. healDrain, nil, 100, 255, 100)
        target.shakeOffset = 4
        playSfx("attack", 0.6)

    elseif card.id == "weaken" then
        local weakenTurns = 2
        for _, mo in ipairs(battle.monsters) do
            if mo.alive then
                mo.effects.weaken = {turns = weakenTurns}
                mo.dmg = math.floor(mo.baseDmg / 2)
                if player.skills.tough then
                    mo.dmg = math.floor(mo.dmg * 0.75)
                end
            end
        end
        battle.effectText = "削弱！全体ATK减半" .. weakenTurns .. "回合"
        playSfx("pickup", 0.5)

    elseif card.id == "reflect" then
        battle.reflectActive = true
        if gem == "holy" then
            battle.reflectGemHoly = true  -- 圣光反射：反弹75%
        end
        battle.effectText = "反射！反弹" .. (gem == "holy" and "75" or "50") .. "%伤害"
        playSfx("pickup", 0.5)

    elseif card.id == "execute" then
        if not target then goto card_done end
        local execThresh = gem == "flame" and 0.3 or 0.2  -- 烈焰石：阈值提升到30%
        if target.hp <= target.maxHP * execThresh then
            target.hp = 0
            thunderSplashDmg = target.maxHP  -- 处决视为满血伤害用于溅射
            battle.effectText = ""
            addFloatText("处决!", ti, 255, 220, 50)
            target.shakeOffset = 6
            playSfx("attack", 0.8)
        else
            dmg = pDmg
            if gem == "flame" then dmg = math.floor(dmg * 1.3) end
            target.hp = target.hp - dmg
            thunderSplashDmg = dmg
            if gem == "blood" and dmg > 0 then
                local bloodHeal = math.max(1, math.floor(dmg * 0.1))
                battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            end
            battle.effectText = ""
            addFloatText("-" .. dmg, ti, 255, 50, 50)
            target.shakeOffset = 4
            playSfx("attack", 0.6)
        end

    elseif card.id == "haste" then
        -- 疾速：连击2次（分步动画）
        if not target then goto card_done end
        dmg = pDmg
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        local hasteDmg = dmg
        local hasteTotalDmg = {0}
        local hasteHits = {}
        for hit = 1, 2 do
            table.insert(hasteHits, { fn = function()
                if not target.alive then return end
                target.hp = target.hp - hasteDmg
                hasteTotalDmg[1] = hasteTotalDmg[1] + hasteDmg
                target.shakeOffset = 5
                addFloatText("-" .. hasteDmg, ti, 255, 50, 50)
                playSfx("attack", 0.6)
                if target.hp <= 0 then target.alive = false end
            end })
        end
        startMultiHit(hasteHits, 0.25, function()
            thunderSplashDmg = hasteTotalDmg[1]
            if gem == "blood" and hasteTotalDmg[1] > 0 then
                local bloodHeal = math.max(1, math.floor(hasteTotalDmg[1] * 0.1))
                battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
                addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
            end
        end)
        battle.effectText = ""

    elseif card.id == "thunder" then
        local thunderDmg = player.level * 3
        local hitCount = 0
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive then
                local actualDmg = thunderDmg
                if mo.effects.vulnerable and mo.effects.vulnerable > 0 then actualDmg = math.floor(actualDmg * 1.5) end
                mo.hp = mo.hp - actualDmg
                mo.shakeOffset = 5
                hitCount = hitCount + 1
                addFloatText("-" .. actualDmg, mi, 180, 130, 255)
            end
        end
        battle.effectText = ""
        playSfx("attack", 0.7)

    elseif card.id == "firestorm" then
        local totalDmg = 0
        local hitCount = 0
        local mult = card.mult or 1.0
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive then
                local moDmg = math.max(0, math.floor(mo.playerDmg * mult))
                if mo.effects.vulnerable and mo.effects.vulnerable > 0 then moDmg = math.floor(moDmg * 1.5) end
                if furyStacks > 0 then moDmg = math.floor(moDmg * furyMult) end
                if battle.powerNext then moDmg = moDmg * 2 end
                mo.hp = mo.hp - moDmg
                mo.shakeOffset = 6
                totalDmg = totalDmg + moDmg
                hitCount = hitCount + 1
                addFloatText("-" .. moDmg, mi, 255, 120, 30)
            end
        end
        if battle.powerNext then battle.powerNext = false end
        battle.effectText = ""
        playSfx("attack", 0.8)

    elseif card.id == "thrifty" then
        -- 所有手牌费用-1（不含自身，因为自身即将被移除）
        local reduced = 0
        for i, c in ipairs(battle.hand) do
            if i ~= cardIndex then
                c.costReduction = (c.costReduction or 0) + 1
                reduced = reduced + 1
            end
        end
        battle.effectText = "节流！" .. reduced .. "张牌费用-1"
        playSfx("pickup", 0.5)

    elseif card.id == "meditate" then
        local oldMp = battle.mp
        battle.mp = math.min(battle.maxMp, battle.mp + 1)
        local gained = battle.mp - oldMp
        battle.effectText = "冥想！MP+" .. gained
        playSfx("pickup", 0.5)

    elseif card.id == "pierce" then
        -- 破除目标怪物的防御（单体）
        if not target then goto card_done end
        if target.alive and target.def > 0 then
            target.def = 0
            local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
            target.playerDmg = math.max(0, effAtk)
            battle.effectText = "破防！" .. target.name .. " DEF归零"
        else
            battle.effectText = "破防！目标无防御"
        end
        playSfx("attack", 0.5)

    elseif card.id == "armorBreak" then
        -- 破甲打击：造成ATK点伤害（无视DEF）
        if not target then goto card_done end
        local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
        dmg = math.max(0, effAtk)
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        -- 易伤倍率
        if target.effects.vulnerable and target.effects.vulnerable > 0 then
            dmg = math.floor(dmg * 1.5)
        end
        -- 怒火倍率
        if furyStacks > 0 then dmg = math.floor(dmg * furyMult) end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.effectText = ""
        addFloatText("-" .. dmg, ti, 255, 130, 30)
        target.shakeOffset = 5
        playSfx("attack", 0.7)

    elseif card.id == "savageBash" then
        -- 野蛮冲撞：造成60%基础伤害并获得1层怒火
        if not target then goto card_done end
        dmg = math.max(0, math.floor(pDmg * 0.6))
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.fury = (battle.fury or 0) + 1
        battle.effectText = ""
        addFloatText("-" .. dmg, ti, 210, 90, 40)
        addFloatText("怒火+1", nil, 200, 50, 30)
        target.shakeOffset = 4
        playSfx("attack", 0.5)

    elseif card.id == "roar" then
        -- 怒嚎：获得2层怒火并抽1张牌
        battle.fury = (battle.fury or 0) + 2
        drawCards(1)
        battle.effectText = ""
        addFloatText("怒火+2", nil, 200, 50, 30)
        playSfx("pickup", 0.6)

    elseif card.id == "armorStance" then
        -- 破甲之力：下一次基础攻击(strike)转化为破甲伤害
        battle.armorStanceNext = true
        battle.effectText = ""
        addFloatText("破甲之力!", nil, 220, 100, 30)
        playSfx("pickup", 0.5)

    elseif card.id == "rend" then
        -- 撕裂：造成50%基础伤害 + 施加2层易伤
        if not target then goto card_done end
        dmg = math.max(0, math.floor(pDmg * 0.5))
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        -- 施加2层易伤
        local vulnStacks = 2
        target.effects.vulnerable = (target.effects.vulnerable or 0) + vulnStacks
        battle.effectText = ""
        addFloatText("-" .. dmg, ti, 200, 60, 40)
        addFloatText("易伤+" .. vulnStacks, ti, 255, 180, 60)
        target.shakeOffset = 4
        playSfx("attack", 0.5)

    elseif card.id == "bloodFrenzy" then
        -- 嗜血狂暴：消耗25%当前HP，本场ATK+3，本回合攻击吸血20%，怒火+2
        local hpCost = math.max(1, math.floor(battle.playerHP * 0.25))
        battle.playerHP = math.max(1, battle.playerHP - hpCost) -- 至少保留1HP
        battle.frenzyAtk = (battle.frenzyAtk or 0) + 3
        battle.fury = (battle.fury or 0) + 2
        battle.bloodFrenzyHeal = true
        -- 重算所有怪物受到的玩家伤害
        for _, mo in ipairs(battle.monsters) do
            if mo.alive then
                local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                mo.playerDmg = math.max(0, effAtk - mo.def)
            end
        end
        battle.effectText = ""
        addFloatText("-" .. hpCost .. "HP", nil, 200, 50, 50)
        addFloatText("ATK+3 怒火+2 吸血!", nil, 180, 20, 30)
        playSfx("pickup", 0.6)

    elseif card.id == "rampage" then
        -- 暴走：对目标连续攻击3次，每次50%伤害，击杀转移目标（分步动画）
        if not target then goto card_done end
        local rampageTotalDmg = {0}  -- 用表包装以便闭包共享
        local rampageCur = {target = target, ti = ti}
        local rampageHits = {}
        for hit = 1, 3 do
            table.insert(rampageHits, { fn = function()
                -- 寻找存活目标
                if not rampageCur.target or not rampageCur.target.alive then
                    rampageCur.ti = nil
                    for mi, mo in ipairs(battle.monsters) do
                        if mo.alive then rampageCur.ti = mi; rampageCur.target = mo; break end
                    end
                end
                if not rampageCur.target or not rampageCur.target.alive then return end
                local ct = rampageCur.target
                local hitDmg = math.max(0, math.floor(ct.playerDmg * 0.5))
                if ct.effects.vulnerable and ct.effects.vulnerable > 0 then hitDmg = math.floor(hitDmg * 1.5) end
                if furyStacks > 0 then hitDmg = math.floor(hitDmg * furyMult) end
                if gem == "flame" then hitDmg = math.floor(hitDmg * 1.3) end
                if hit == 1 and battle.powerNext then hitDmg = hitDmg * 2; battle.powerNext = false end
                if hit == 1 and player.skills.crit and not battle.critUsed and hitDmg > 0 then
                    hitDmg = math.floor(hitDmg * 1.5)
                    battle.critUsed = true
                    addFloatText("暴击!", rampageCur.ti, 255, 160, 30)
                end
                ct.hp = ct.hp - hitDmg
                rampageTotalDmg[1] = rampageTotalDmg[1] + hitDmg
                ct.shakeOffset = 5
                addFloatText("-" .. hitDmg, rampageCur.ti, 200, 40, 50)
                playSfx("attack", 0.6)
                if ct.hp <= 0 then ct.alive = false; rampageCur.target = nil; rampageCur.ti = nil end
            end })
        end
        startMultiHit(rampageHits, 0.3, function()
            thunderSplashDmg = rampageTotalDmg[1]
            if gem == "blood" and rampageTotalDmg[1] > 0 then
                local bloodHeal = math.max(1, math.floor(rampageTotalDmg[1] * 0.1))
                battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
                addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
            end
        end)
        battle.effectText = ""

    elseif card.id == "furyCleave" then
        -- 怒劈：80%伤害，怒火≥3时120%
        if not target then goto card_done end
        local mult = (furyStacks >= 3) and 1.2 or 0.8
        dmg = math.max(0, math.floor(pDmg * mult))
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.effectText = ""
        if furyStacks >= 3 then
            addFloatText("怒劈!-" .. dmg, ti, 255, 120, 30)
        else
            addFloatText("-" .. dmg, ti, 200, 80, 30)
        end
        target.shakeOffset = 5
        playSfx("attack", 0.7)

    elseif card.id == "battleCry" then
        -- 威吓：怒火+1，全体敌人易伤1回合
        battle.fury = (battle.fury or 0) + 1
        for _, mo in ipairs(battle.monsters) do
            if mo.alive then
                mo.effects.vulnerable = (mo.effects.vulnerable or 0) + 1
            end
        end
        battle.effectText = ""
        addFloatText("怒火+1", nil, 200, 50, 30)
        addFloatText("全体易伤+1!", nil, 255, 180, 60)
        playSfx("attack", 0.6)

    elseif card.id == "toughHide" then
        -- 厚皮：ATK50%护盾，怒火+1
        local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
        local shieldAmt = math.max(1, math.floor(effAtk * 0.5))
        if gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.fury = (battle.fury or 0) + 1
        battle.effectText = ""
        addFloatText("盾+" .. shieldAmt, nil, 160, 110, 50)
        addFloatText("怒火+1", nil, 200, 50, 30)
        playSfx("pickup", 0.5)

    elseif card.id == "berserkerRage" then
        -- 狂暴姿态：获得易伤（受伤+30%），怒火+3
        battle.berserkerRageActive = true
        battle.fury = (battle.fury or 0) + 3
        battle.effectText = ""
        addFloatText("怒火+3!", nil, 220, 40, 20)
        addFloatText("易伤! 受伤+30%", nil, 255, 180, 60)
        playSfx("attack", 0.6)

    elseif card.id == "groundSlam" then
        -- 震地猛击：全体80%伤害，各+1易伤
        local totalDmg = 0
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive then
                local moDmg = math.max(0, math.floor(mo.playerDmg * 0.8))
                if mo.effects.vulnerable and mo.effects.vulnerable > 0 then
                    moDmg = math.floor(moDmg * 1.5)
                end
                if furyStacks > 0 then moDmg = math.floor(moDmg * furyMult) end
                if gem == "flame" then moDmg = math.floor(moDmg * 1.3) end
                if battle.powerNext then moDmg = moDmg * 2 end
                mo.hp = mo.hp - moDmg
                totalDmg = totalDmg + moDmg
                mo.shakeOffset = 4
                mo.effects.vulnerable = (mo.effects.vulnerable or 0) + 1
                addFloatText("-" .. moDmg, mi, 180, 100, 40)
            end
        end
        if battle.powerNext then battle.powerNext = false end
        thunderSplashDmg = totalDmg
        if gem == "blood" and totalDmg > 0 then
            local bloodHeal = math.max(1, math.floor(totalDmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.effectText = ""
        addFloatText("全体易伤+1!", nil, 255, 180, 60)
        playSfx("attack", 0.8)

    elseif card.id == "furyBurst" then
        -- 怒火爆发：消耗所有怒火，每层40%基础伤害
        if not target then goto card_done end
        local stacks = battle.fury or 0
        if stacks <= 0 then
            addFloatText("无怒火!", nil, 180, 180, 180)
            battle.effectText = ""
            playSfx("btn", 0.3)
        else
            dmg = math.max(0, math.floor(pDmg * stacks * 0.4 / furyMult)) -- pDmg已含fury，先除掉再按层数算
            if gem == "flame" then dmg = math.floor(dmg * 1.3) end
            if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
            target.hp = target.hp - dmg
            thunderSplashDmg = dmg
            if gem == "blood" and dmg > 0 then
                local bloodHeal = math.max(1, math.floor(dmg * 0.1))
                battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
                addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
            end
            battle.fury = 0
            battle.effectText = ""
            addFloatText("🔥x" .. stacks .. " -" .. dmg, ti, 240, 60, 20)
            target.shakeOffset = 6
            playSfx("attack", 0.9)
        end

    elseif card.id == "undying" then
        -- 不屈：本回合HP不会低于1，怒火+2
        battle.undyingActive = true
        battle.fury = (battle.fury or 0) + 2
        battle.effectText = ""
        addFloatText("不屈!", nil, 180, 50, 30)
        addFloatText("怒火+2", nil, 200, 50, 30)
        playSfx("pickup", 0.6)

    elseif card.id == "bloodScent" then
        -- 嗜血本能：击杀敌人时怒火+3并回复10HP，持续3回合
        battle.bloodScentTurns = (battle.bloodScentTurns or 0) + 3
        battle.effectText = ""
        addFloatText("嗜血本能!", nil, 190, 30, 40)
        playSfx("pickup", 0.6)

    elseif card.id == "titanGrip" then
        -- 巨力挥砍：造成200%伤害，下回合无法攻击
        if not target then goto card_done end
        dmg = math.max(0, math.floor(pDmg * 2.0))
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.titanSkipNext = true
        battle.effectText = ""
        addFloatText("-" .. dmg .. "!", ti, 220, 50, 40)
        target.shakeOffset = 8
        playSfx("attack", 1.0)

    elseif card.id == "warpath" then
        -- 战争之路：怒火+5，ATK+2，抽2张牌
        battle.fury = (battle.fury or 0) + 5
        battle.frenzyAtk = (battle.frenzyAtk or 0) + 2
        -- 重算怪物受到的玩家伤害
        for _, mo in ipairs(battle.monsters) do
            if mo.alive then
                local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                mo.playerDmg = math.max(0, effAtk - mo.def)
            end
        end
        drawCards(2)
        battle.effectText = ""
        addFloatText("怒火+5!", nil, 200, 30, 20)
        addFloatText("ATK+2 +2抽", nil, 255, 140, 30)
        playSfx("pickup", 0.8)

    elseif card.id == "defend" then
        local shieldAmt = math.floor(player.def * 0.7)
        if gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.effectText = ""
        addFloatText("盾+" .. shieldAmt, nil, 100, 180, 255)
        playSfx("pickup", 0.5)

    elseif card.id == "shield" then
        local shieldAmt = math.floor(player.def * 1.4)
        if gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.effectText = ""
        addFloatText("盾+" .. shieldAmt, nil, 100, 180, 255)
        playSfx("pickup", 0.5)

    elseif card.id == "atkShield" then
        local shieldAmt = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
        if gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.effectText = ""
        addFloatText("盾+" .. shieldAmt, nil, 100, 180, 255)
        playSfx("pickup", 0.5)

    elseif card.id == "cardDraw" then
        drawCards(2)
        battle.effectText = "战术！抽2张牌"
        playSfx("pickup", 0.5)

    elseif card.id == "heavyStrike" then
        if not target then goto card_done end
        dmg = math.floor(pDmg * 1.5)
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.effectText = ""
        addFloatText("-" .. dmg, ti, 255, 50, 50)
        target.shakeOffset = 6
        playSfx("attack", 0.8)

    elseif card.id == "bladestorm" then
        local totalDmg = 0
        local hitCount = 0
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive then
                local moDmg = math.max(0, mo.playerDmg)
                if mo.effects.vulnerable and mo.effects.vulnerable > 0 then moDmg = math.floor(moDmg * 1.5) end
                if furyStacks > 0 then moDmg = math.floor(moDmg * furyMult) end
                if gem == "flame" then moDmg = math.floor(moDmg * 1.3) end
                if battle.powerNext then moDmg = moDmg * 2 end
                mo.hp = mo.hp - moDmg
                mo.shakeOffset = 6
                totalDmg = totalDmg + moDmg
                hitCount = hitCount + 1
                addFloatText("-" .. moDmg, mi, 255, 50, 50)
            end
        end
        if battle.powerNext then battle.powerNext = false end
        battle.effectText = ""
        playSfx("attack", 0.8)

    elseif card.id == "soulBurn" then
        -- 弃掉所有其他手牌，每张对全体造成25伤害
        local consumed = 0
        local eatenCards = {}
        for i = #battle.hand, 1, -1 do
            if i ~= cardIndex then
                local c = battle.hand[i]
                table.insert(eatenCards, c)
                table.insert(battle.discard, c)
                table.remove(battle.hand, i)
                consumed = consumed + 1
                if i < cardIndex then cardIndex = cardIndex - 1 end
            end
        end
        local dmgPer = 25
        local totalDmg = consumed * dmgPer
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive then
                local actualDmg = totalDmg
                if mo.effects.vulnerable and mo.effects.vulnerable > 0 then actualDmg = math.floor(actualDmg * 1.5) end
                mo.hp = mo.hp - actualDmg
                mo.shakeOffset = 6
                addFloatText("-" .. actualDmg, mi, 255, 80, 30)
            end
        end
        for _, ec in ipairs(eatenCards) do
            triggerEatenGem(ec, totalDmg, 0, 0, nil)
        end
        battle.effectText = ""
        playSfx("attack", 0.8)

    elseif card.id == "handBlast" then
        -- 乱击：弃掉所有其他手牌，每张对目标造成50%基础伤害（分步动画）
        if not target then goto card_done end
        local consumed = 0
        local eatenCards = {}
        for i = #battle.hand, 1, -1 do
            if i ~= cardIndex then
                local c = battle.hand[i]
                table.insert(eatenCards, c)
                table.insert(battle.discard, c)
                table.remove(battle.hand, i)
                consumed = consumed + 1
                if i < cardIndex then cardIndex = cardIndex - 1 end
            end
        end
        if consumed > 0 then
            local hbTotalDmg = {0}
            local hbHits = {}
            for hit = 1, consumed do
                table.insert(hbHits, { fn = function()
                    if not target.alive then return end
                    local hitDmg = math.max(0, math.floor(target.playerDmg * 0.5))
                    if target.effects.vulnerable and target.effects.vulnerable > 0 then hitDmg = math.floor(hitDmg * 1.5) end
                    if furyStacks > 0 then hitDmg = math.floor(hitDmg * furyMult) end
                    if gem == "flame" then hitDmg = math.floor(hitDmg * 1.3) end
                    if hit == 1 and battle.powerNext then hitDmg = hitDmg * 2; battle.powerNext = false end
                    if hit == 1 and player.skills.crit and not battle.critUsed and hitDmg > 0 then
                        hitDmg = math.floor(hitDmg * 1.5)
                        battle.critUsed = true
                        addFloatText("暴击!", ti, 255, 160, 30)
                    end
                    target.hp = target.hp - hitDmg
                    hbTotalDmg[1] = hbTotalDmg[1] + hitDmg
                    target.shakeOffset = 5
                    addFloatText("-" .. hitDmg, ti, 230, 120, 40)
                    playSfx("attack", 0.5)
                    if target.hp <= 0 then target.alive = false end
                end })
            end
            local hbEatenCards = eatenCards
            startMultiHit(hbHits, 0.2, function()
                thunderSplashDmg = hbTotalDmg[1]
                for _, ec in ipairs(hbEatenCards) do
                    triggerEatenGem(ec, hbTotalDmg[1], 0, 0, nil)
                end
                if gem == "blood" and hbTotalDmg[1] > 0 then
                    local bloodHeal = math.max(1, math.floor(hbTotalDmg[1] * 0.1))
                    battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
                    addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
                end
            end)
        end
        battle.effectText = ""

    elseif card.id == "devour" then
        -- 消耗1张手牌，造成其费用x12伤害并回复等量HP
        if not target then goto card_done end
        local eatIdx = battle.consumeSelect and battle.consumeSelect.eatIdx or nil
        if eatIdx then
            local eaten = battle.hand[eatIdx]
            local eatenDef = CARD_DEF[eaten.id]
            local eatCost = eatenDef and eatenDef.mpCost or 0
            dmg = eatCost * 12
            if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
            target.hp = target.hp - dmg
            target.shakeOffset = 5
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + dmg)
            -- 移除被吞噬的卡牌（放入弃牌堆）
            table.insert(battle.discard, eaten)
            table.remove(battle.hand, eatIdx)
            if eatIdx < cardIndex then cardIndex = cardIndex - 1 end
            battle.effectText = ""
            addFloatText("-" .. dmg, ti, 255, 50, 50)
            addFloatText("+" .. dmg, nil, 100, 255, 100)
            triggerEatenGem(eaten, dmg, dmg, 0, ti)
        else
            battle.effectText = "吞噬失败！无牌可吃"
        end
        playSfx("attack", 0.7)

    elseif card.id == "convert" then
        -- 消耗1张手牌，获得其费用x8护盾并恢复2MP
        local eatIdx = battle.consumeSelect and battle.consumeSelect.eatIdx or nil
        if eatIdx then
            local eaten = battle.hand[eatIdx]
            local eatenDef = CARD_DEF[eaten.id]
            local eatCost = eatenDef and eatenDef.mpCost or 0
            local shieldAmt = eatCost * 8
            battle.shieldHP = battle.shieldHP + shieldAmt
            battle.mp = math.min(battle.maxMp, battle.mp + 2)
            table.insert(battle.discard, eaten)
            table.remove(battle.hand, eatIdx)
            if eatIdx < cardIndex then cardIndex = cardIndex - 1 end
            battle.effectText = ""
            addFloatText("盾+" .. shieldAmt, nil, 100, 180, 255)
            triggerEatenGem(eaten, 0, 0, shieldAmt, nil)
        else
            battle.effectText = "转化失败！无牌可用"
        end
        playSfx("pickup", 0.5)

    elseif card.id == "wound" or card.id == "curse" or card.id == "frail"
        or card.id == "erode" or card.id == "fog" or card.id == "nightmare" then
        -- 诅咒卡：打出时无效果（花费费用将其从手牌移除），效果仅在回合结束时仍在手牌中才触发

    -- === 新增史诗卡牌效果 ===
    elseif card.id == "cleave" then
        if not target then goto card_done end
        dmg = math.floor(pDmg * 1.5)
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        target.shakeOffset = 6
        addFloatText("-" .. dmg, ti, 255, 50, 50)
        -- 溅射其余敌人50%
        local splashDmg = math.floor(dmg * 0.5)
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive and mi ~= ti then
                local actualSplash = splashDmg
                if mo.effects.vulnerable and mo.effects.vulnerable > 0 then actualSplash = math.floor(actualSplash * 1.5) end
                mo.hp = mo.hp - actualSplash
                mo.shakeOffset = 3
                addFloatText("-" .. actualSplash, mi, 255, 120, 80)
            end
        end
        if gem == "blood" and dmg > 0 then
            local bloodHeal = math.max(1, math.floor(dmg * 0.1))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
            addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
        end
        battle.effectText = ""
        playSfx("attack", 0.8)

    elseif card.id == "ironWall" then
        local shieldAmt = math.floor(player.def * 2.1)
        if gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.effectText = ""
        addFloatText("盾+" .. shieldAmt, nil, 100, 180, 255)
        playSfx("pickup", 0.6)

    elseif card.id == "thorns" then
        local shieldAmt = math.floor(player.def * 0.7)
        if gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.thornsActive = 2  -- 持续2回合
        battle.thornsRate = 0.4
        battle.effectText = ""
        addFloatText("盾+" .. shieldAmt, nil, 100, 180, 255)
        playSfx("pickup", 0.6)

    -- === 新增传说卡牌效果 ===
    elseif card.id == "deathDance" then
        -- 死亡之舞：随机攻击3次（分步动画）
        local aliveList = {}
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive then table.insert(aliveList, mi) end
        end
        if #aliveList > 0 then
            local ddTotalDmg = {0}
            local ddHits = {}
            -- 预先随机选择目标（避免闭包中随机数问题）
            local ddTargets = {}
            for _ = 1, 3 do
                table.insert(ddTargets, aliveList[math.random(1, #aliveList)])
            end
            for hitIdx = 1, 3 do
                table.insert(ddHits, { fn = function()
                    -- 重新检查存活列表
                    local curAlive = {}
                    for mi, mo in ipairs(battle.monsters) do
                        if mo.alive then table.insert(curAlive, mi) end
                    end
                    if #curAlive == 0 then return end
                    local ri = ddTargets[hitIdx]
                    -- 如果预选目标已死，随机选一个存活的
                    if not battle.monsters[ri].alive then
                        ri = curAlive[math.random(1, #curAlive)]
                    end
                    local mo = battle.monsters[ri]
                    local hitDmg = math.floor(mo.playerDmg * 0.6)
                    if mo.effects.vulnerable and mo.effects.vulnerable > 0 then hitDmg = math.floor(hitDmg * 1.5) end
                    if furyStacks > 0 then hitDmg = math.floor(hitDmg * furyMult) end
                    if gem == "flame" then hitDmg = math.floor(hitDmg * 1.3) end
                    if hitIdx == 1 and battle.powerNext then hitDmg = hitDmg * 2; battle.powerNext = false end
                    if hitIdx == 1 and player.skills.crit and not battle.critUsed and hitDmg > 0 then
                        hitDmg = math.floor(hitDmg * 1.5)
                        battle.critUsed = true
                        addFloatText("暴击!", ri, 255, 160, 30)
                    end
                    mo.hp = mo.hp - hitDmg
                    mo.shakeOffset = 6
                    ddTotalDmg[1] = ddTotalDmg[1] + hitDmg
                    addFloatText("-" .. hitDmg, ri, 200, 80, 255)
                    playSfx("attack", 0.6)
                    if mo.hp <= 0 then mo.alive = false end
                end })
            end
            startMultiHit(ddHits, 0.35, function()
                thunderSplashDmg = ddTotalDmg[1]
                if gem == "blood" and ddTotalDmg[1] > 0 then
                    local bloodHeal = math.max(1, math.floor(ddTotalDmg[1] * 0.1))
                    battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + bloodHeal)
                    addFloatText("+" .. bloodHeal, nil, 100, 255, 100)
                end
            end)
        end
        if battle.powerNext then battle.powerNext = false end
        battle.effectText = ""

    elseif card.id == "oblivion" then
        if not target then goto card_done end
        dmg = math.floor(target.hp * 0.5)
        if dmg < 1 then dmg = 1 end
        if gem == "flame" then dmg = math.floor(dmg * 1.3) end
        if battle.powerNext then dmg = dmg * 2; battle.powerNext = false end
        target.hp = target.hp - dmg
        thunderSplashDmg = dmg
        target.shakeOffset = 6
        battle.effectText = ""
        addFloatText("-" .. dmg, ti, 200, 80, 255)
        playSfx("attack", 0.8)

    elseif card.id == "immortal" then
        battle.guardActive = true
        battle.immortalActive = true  -- 完全免疫伤害
        local healAmt = math.floor(battle.playerStartHP * 0.1)
        battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + healAmt)
        battle.effectText = "不灭！本回合无敌"
        addFloatText("+" .. healAmt, nil, 100, 255, 100)
        playSfx("pickup", 0.7)

    elseif card.id == "warCry" then
        battle.warCryAtk = (battle.warCryAtk or 0) + 5
        -- 重算所有怪物受到的玩家伤害
        for _, mo in ipairs(battle.monsters) do
            if mo.alive then
                local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                mo.playerDmg = math.max(0, effAtk - mo.def)
            end
        end
        local shieldAmt = player.def * 2
        if gem == "holy" then shieldAmt = math.floor(shieldAmt * 1.5) end
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.effectText = "战吼！ATK+5"
        addFloatText("盾+" .. shieldAmt, nil, 100, 180, 255)
        playSfx("attack", 0.7)

    -- === 组合卡牌效果 ===
    elseif card.id == "alchemy" then
        -- 消耗1张手牌，恢复其费用x2 MP
        local eatIdx = battle.consumeSelect and battle.consumeSelect.eatIdx or nil
        if eatIdx then
            local eaten = battle.hand[eatIdx]
            local eatenDef = CARD_DEF[eaten.id]
            local eatCost = eatenDef and eatenDef.mpCost or 0
            local mpGain = eatCost * 2
            battle.mp = math.min(battle.maxMp, battle.mp + mpGain)
            table.insert(battle.discard, eaten)
            table.remove(battle.hand, eatIdx)
            if eatIdx < cardIndex then cardIndex = cardIndex - 1 end
            battle.effectText = ""
            addFloatText("MP+" .. mpGain, nil, 180, 200, 60)
            triggerEatenGem(eaten, 0, 0, 0, nil)
        else
            battle.effectText = "炼金失败！无牌可用"
        end
        playSfx("pickup", 0.5)

    elseif card.id == "sacrifice" then
        -- 消耗1张手牌，对全体敌人造成其费用x8伤害
        local eatIdx = battle.consumeSelect and battle.consumeSelect.eatIdx or nil
        if eatIdx then
            local eaten = battle.hand[eatIdx]
            local eatenDef = CARD_DEF[eaten.id]
            local eatCost = eatenDef and eatenDef.mpCost or 0
            local aoeDmg = eatCost * 8
            if battle.powerNext then aoeDmg = aoeDmg * 2; battle.powerNext = false end
            for mi, mo in ipairs(battle.monsters) do
                if mo.alive then
                    local actualDmg = aoeDmg
                    if mo.effects.vulnerable and mo.effects.vulnerable > 0 then actualDmg = math.floor(actualDmg * 1.5) end
                    mo.hp = mo.hp - actualDmg
                    mo.shakeOffset = 5
                    addFloatText("-" .. actualDmg, mi, 200, 50, 100)
                end
            end
            table.insert(battle.discard, eaten)
            table.remove(battle.hand, eatIdx)
            if eatIdx < cardIndex then cardIndex = cardIndex - 1 end
            battle.effectText = ""
            triggerEatenGem(eaten, aoeDmg, 0, 0, nil)
        else
            battle.effectText = "献祭失败！无牌可用"
        end
        playSfx("attack", 0.7)

    elseif card.id == "empower" then
        -- 消耗1张手牌，本场战斗ATK+费用x2
        local eatIdx = battle.consumeSelect and battle.consumeSelect.eatIdx or nil
        if eatIdx then
            local eaten = battle.hand[eatIdx]
            local eatenDef = CARD_DEF[eaten.id]
            local eatCost = eatenDef and eatenDef.mpCost or 0
            local atkBoost = eatCost * 2
            battle.warCryAtk = (battle.warCryAtk or 0) + atkBoost
            for _, mo in ipairs(battle.monsters) do
                if mo.alive then
                    local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
                    mo.playerDmg = math.max(0, effAtk - mo.def)
                end
            end
            table.insert(battle.discard, eaten)
            table.remove(battle.hand, eatIdx)
            if eatIdx < cardIndex then cardIndex = cardIndex - 1 end
            battle.effectText = ""
            addFloatText("ATK+" .. atkBoost, nil, 255, 140, 30)
            triggerEatenGem(eaten, 0, 0, 0, nil)
        else
            battle.effectText = "强化失败！无牌可用"
        end
        playSfx("pickup", 0.6)

    elseif card.id == "gambit" then
        -- 消耗1张手牌，抽取等同其费用张牌(1-4)
        local eatIdx = battle.consumeSelect and battle.consumeSelect.eatIdx or nil
        if eatIdx then
            local eaten = battle.hand[eatIdx]
            local eatenDef = CARD_DEF[eaten.id]
            local eatCost = eatenDef and eatenDef.mpCost or 0
            local drawNum = math.max(1, math.min(4, eatCost))
            table.insert(battle.discard, eaten)
            table.remove(battle.hand, eatIdx)
            if eatIdx < cardIndex then cardIndex = cardIndex - 1 end
            drawCards(drawNum)
            battle.effectText = ""
            addFloatText("抽" .. drawNum .. "张", nil, 220, 180, 255)
            triggerEatenGem(eaten, 0, 0, 0, nil)
        else
            battle.effectText = "赌运失败！无牌可用"
        end
        playSfx("pickup", 0.5)

    elseif card.id == "fusion" then
        -- 弃掉所有其他手牌，获得总费用x5护盾 + 回复总费用x3 HP
        local totalCost = 0
        local consumed = 0
        local eatenCards = {}
        for i = #battle.hand, 1, -1 do
            if i ~= cardIndex then
                local c = battle.hand[i]
                local cDef = CARD_DEF[c.id]
                totalCost = totalCost + (cDef and cDef.mpCost or 0)
                table.insert(eatenCards, c)
                table.insert(battle.discard, c)
                table.remove(battle.hand, i)
                consumed = consumed + 1
                if i < cardIndex then cardIndex = cardIndex - 1 end
            end
        end
        local shieldAmt = totalCost * 5
        local healAmt = totalCost * 3
        battle.shieldHP = battle.shieldHP + shieldAmt
        battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + healAmt)
        battle.effectText = ""
        if shieldAmt > 0 then addFloatText("盾+" .. shieldAmt, nil, 60, 200, 200) end
        if healAmt > 0 then addFloatText("+" .. healAmt, nil, 100, 255, 100) end
        for _, ec in ipairs(eatenCards) do
            triggerEatenGem(ec, 0, healAmt, shieldAmt, nil)
        end
        playSfx("pickup", 0.6)

    elseif def.type == "item" and def.itemEffect then
        local eff = def.itemEffect
        if eff.type == "hp" then
            player.hp = player.hp + eff.amount
            battle.playerHP = battle.playerHP + eff.amount
            battle.playerStartHP = battle.playerStartHP + eff.amount
            battle.effectText = ""
            addFloatText("HP+" .. eff.amount, nil, 100, 255, 100)
        elseif eff.type == "atk" then
            player.atk = player.atk + eff.amount
            for _, mo in ipairs(battle.monsters) do
                if mo.alive then mo.playerDmg = math.max(0, player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0) - mo.def) end
            end
            battle.effectText = ""
            addFloatText("ATK+" .. eff.amount, nil, 255, 200, 50)
        elseif eff.type == "def" then
            player.def = player.def + eff.amount
            -- 重算所有怪物对玩家的伤害
            for _, mo in ipairs(battle.monsters) do
                if mo.alive then
                    local mAtk = mo.atk
                    if mo.skill and mo.skill.id == "berserk" and mo.hp < mo.maxHP * 0.5 then
                        mAtk = mo.atk * 2
                    end
                    local newDmg
                    if mo.skill and mo.skill.id == "magicAtk" then
                        newDmg = mAtk
                    else
                        newDmg = math.max(0, mAtk - player.def)
                    end
                    if mo.skill and mo.skill.id == "counter" then
                        newDmg = newDmg + (mo.skill.value or 0)
                    end
                    if player.skills.tough then
                        newDmg = math.floor(newDmg * 0.75)
                    end
                    mo.dmg = newDmg
                    mo.baseDmg = newDmg
                end
            end
            battle.effectText = ""
            addFloatText("DEF+" .. eff.amount, nil, 100, 180, 255)
        end
        playSfx("pickup", 0.5)
    end

    ::card_done::

    -- 破甲之力：攻击类卡牌打出后消耗buff（破甲打击本身无视DEF，不消耗）
    if armorStanceActive and def and def.type == "attack" and card.id ~= "armorBreak" then
        battle.armorStanceNext = false
    end

    -- 暴击被动：首击成功，标记已使用并显示特效
    if isCrit and dmg > 0 then
        battle.critUsed = true
        addFloatText("暴击!", ti, 255, 160, 30)
    end

    -- 清除 consumeOne 选择状态
    battle.consumeSelect = nil

    -- 雷霆石：攻击造成20%范围伤害（溅射其他存活怪物）
    if gem == "thunder" and thunderSplashDmg > 0 then
        local splash = math.max(1, math.floor(thunderSplashDmg * 0.2))
        for mi, mo in ipairs(battle.monsters) do
            if mo.alive and mi ~= thunderSplashTarget then
                mo.hp = mo.hp - splash
                mo.shakeOffset = 3
                addFloatText("⚡" .. splash, mi, 180, 100, 255)
            end
        end
    end

    -- 嗜血狂暴吸血：本回合所有攻击伤害的20%回血
    if battle.bloodFrenzyHeal then
        local frenzyDmg = math.max(dmg, thunderSplashDmg)
        if frenzyDmg > 0 then
            local frenzyHeal = math.max(1, math.floor(frenzyDmg * 0.2))
            battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + frenzyHeal)
            addFloatText("吸血+" .. frenzyHeal, nil, 255, 100, 100)
        end
    end

    -- 标记死亡怪物
    for _, mo in ipairs(battle.monsters) do
        if mo.alive and mo.hp <= 0 then
            mo.hp = 0
            mo.alive = false
            -- 嗜血本能：击杀时怒火+3并回复10HP
            if (battle.bloodScentTurns or 0) > 0 then
                battle.fury = (battle.fury or 0) + 3
                local scentHeal = 10
                battle.playerHP = math.min(battle.playerStartHP, battle.playerHP + scentHeal)
                addFloatText("嗜血!怒火+3 +10HP", nil, 190, 30, 40)
            end
        end
    end

    -- 汲取石：打出后抽1张牌
    if gem == "draw" then
        drawCards(1)
        addFloatText("+1抽", nil, 60, 180, 220)
    end

    -- 从手牌移除已打出的卡牌，并按类型路由
    table.remove(battle.hand, cardIndex)
    cardAnims = {}
    battle.hoveredCard = 0
    card.costReduction = nil  -- 清除节流减费

    if card.cardType == "consumable" then
        table.insert(battle.consumedCardIndices, card.playerCardIdx)
    elseif card.cardType == "limited" then
        card.usesLeft = math.max(0, (card.usesLeft or 1) - 1)
        if card.usesLeft > 0 then
            table.insert(battle.discard, card)
        end
    else
        table.insert(battle.discard, card)
    end

    -- 检查所有怪物死亡
    if allMonstersDead() then
        cardPlayQueue = {}
        battle.phase = "result"
        battle.timer = 0
        return
    end

    -- 进入卡牌效果展示阶段（出牌后不结束回合，可继续出牌）
    battle.autoEndTimer = nil  -- 出牌成功，清除自动结束倒计时
    battle.phase = "card_effect"
    battle.timer = 0
end

--- 收集目标位置上下左右的相邻敌人（不含目标自身）
--- @return table[] 相邻敌人列表 [{ch, row, col}]
local function collectAdjacentEnemies(row, col)
    local dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
    local result = {}
    local map = maps[player.floor]
    for _, d in ipairs(dirs) do
        local ar, ac = row + d[1], col + d[2]
        if ar >= 1 and ar <= GRID and ac >= 1 and ac <= GRID then
            local ch = map[ar][ac]
            if isMonster(ch) then
                -- 避免重复（玩家自身位置不会是怪物）
                table.insert(result, {ch = ch, row = ar, col = ac})
            end
        end
    end
    return result
end

--- 构建单个怪物的战斗数据条目
local function buildMonsterEntry(monsterCh)
    local m = MONSTER_DEF[monsterCh]
    local monsterHP = getMonsterScaledHP(m)
    local monsterAtk = getMonsterScaledATK(m)
    local playerDmg = player.atk - m.def

    local monsterDmg
    if m.skill and m.skill.id == "magicAtk" then
        monsterDmg = monsterAtk
    else
        monsterDmg = math.max(0, monsterAtk - player.def)
    end
    if m.skill and m.skill.id == "counter" then
        monsterDmg = monsterDmg + (m.skill.value or 0)
    end
    if player.skills.tough then
        monsterDmg = math.floor(monsterDmg * 0.75)
    end

    local regenVal = 0
    if m.skill and m.skill.id == "regen" then
        regenVal = m.skill.value or 0
    end

    return {
        ch = monsterCh,
        name = m.name,
        maxHP = monsterHP,
        hp = monsterHP,
        displayHP = monsterHP,
        atk = monsterAtk,
        def = m.def,
        dmg = monsterDmg,
        baseDmg = monsterDmg,
        playerDmg = playerDmg,
        sprite = m.sprite,
        spriteRow = m.spriteRow or 0,
        skill = m.skill,
        regen = regenVal,
        preemptive = (m.skill and m.skill.id == "preemptive") == true,
        gold = m.gold,
        boss = m.boss or false,
        shakeOffset = 0,
        alive = true,
        -- 每个怪物独立的持续效果
        effects = {}, -- {poison={turns,dmg}, weaken={turns}}
    }
end

--- 攻击开始时立即触发诅咒技能（植入负面卡牌）
local function applyCurseOnHit(mo, monsterIdx)
    if not mo or not mo.skill or mo.skill.id ~= "curse" then return end
    local cardId = mo.skill.cardId
    local count = mo.skill.count or 1
    local cdef = CARD_DEF[cardId]
    for _ = 1, count do
        table.insert(battle.discard, {
            id = cardId,
            playerCardIdx = -1,
            cardType = cdef and cdef.cardType or "normal",
        })
    end
    if cdef then
        battle.effectText = mo.name .. "植入" .. count .. "张" .. cdef.name .. "！"
        battle.effectTimer = 0.8
    end
    curseInsertAnim.active = true
    curseInsertAnim.timer = 0
    curseInsertAnim.cards = {}
    for ci = 1, count do
        table.insert(curseInsertAnim.cards, {
            cardId = cardId,
            monsterIdx = monsterIdx,
            delay = (ci - 1) * 0.12,
        })
    end
end

--- 启动战斗动画（或直接结算）
local function startBattle(monsterCh, nr, nc)
    local m = MONSTER_DEF[monsterCh]
    local result = calcCombat(monsterCh)

    -- 收集相邻敌人
    local adjacent = collectAdjacentEnemies(nr, nc)
    -- 所有参战敌人位置列表（含目标自身，带怪物字符ch）
    local allPositions = {{row = nr, col = nc, ch = monsterCh}}
    local allNames = {m.name}
    ---@type number
    local totalGoldSum = m.gold
    for _, adj in ipairs(adjacent) do
        table.insert(allPositions, {row = adj.row, col = adj.col, ch = adj.ch})
        local am = MONSTER_DEF[adj.ch]
        if am then
            table.insert(allNames, am.name)
            totalGoldSum = totalGoldSum + am.gold
        end
    end

    -- 预估伤害为0：敌人打不动玩家，直接碾压
    local allZeroDmg = (result.hpLoss == 0)
    if allZeroDmg then
        for _, adj in ipairs(adjacent) do
            local adjResult = calcCombat(adj.ch)
            if adjResult.hpLoss > 0 then allZeroDmg = false; break end
        end
    end

    if not showBattleAnim or allZeroDmg then
        -- 跳过动画，直接结算所有敌人
        local totalHpLoss = result.hpLoss
        for _, adj in ipairs(adjacent) do
            local adjResult = calcCombat(adj.ch)
            totalHpLoss = totalHpLoss + adjResult.hpLoss
        end
        player.hp = player.hp - totalHpLoss

        -- 偷窃技能：地精偷金币
        local stealRounds = result.rounds
        if m.skill and m.skill.id == "steal" then
            local stolen = (m.skill.value or 0) * stealRounds
            if stolen > 0 then
                player.gold = math.max(0, player.gold - stolen)
                addFloatText("-" .. stolen .. "G(偷窃)", nil, 255, 180, 50)
            end
        end

        local goldGain = totalGoldSum
        if player.skills.greed then goldGain = goldGain * 2 end
        player.gold = player.gold + goldGain

        local vampHeal = 0
        if player.skills.vampire then
            ---@type number
            local totalMHP = getMonsterScaledHP(m)
            for _, adj in ipairs(adjacent) do
                local am = MONSTER_DEF[adj.ch]
                if am then totalMHP = totalMHP + getMonsterScaledHP(am) end
            end
            vampHeal = math.floor(totalMHP * 0.10)
            player.hp = player.hp + vampHeal
        end

        -- 清除所有参战敌人
        for _, pos in ipairs(allPositions) do
            maps[player.floor][pos.row][pos.col] = '.'
        end
        -- 计算经验
        local totalExp = 0
        for _, pos in ipairs(allPositions) do
            totalExp = totalExp + getMonsterExp(pos.ch)
        end

        local nameStr = table.concat(allNames, "+")
        local resultMsg = "击败 " .. nameStr .. "！ HP-" .. totalHpLoss .. " 金币+" .. goldGain
        if vampHeal > 0 then resultMsg = resultMsg .. " 吸血+" .. vampHeal end
        if totalExp > 0 then resultMsg = resultMsg .. " EXP+" .. totalExp end
        -- 诅咒技能已改为攻击时临时植入（碾压模式不触发）
        -- 碾压路径：Boss 掉落卡牌
        for _, pos in ipairs(allPositions) do
            local drop = BOSS_DROP[pos.ch]
            if drop and drop.pool and #drop.pool > 0 then
                local candidates = {}
                for _, cardId in ipairs(drop.pool) do
                    local alreadyHas = false
                    for _, pc in ipairs(player.cards) do
                        if pc.id == cardId then alreadyHas = true; break end
                    end
                    if not alreadyHas then candidates[#candidates + 1] = cardId end
                end
                if #candidates == 0 then candidates = drop.pool end
                local dropCardId = candidates[math.random(#candidates)]
                local cdef = CARD_DEF[dropCardId]
                if cdef then
                    local usesLeft = -1
                    if cdef.cardType == "limited" then usesLeft = cdef.maxUses or 1 end
                    table.insert(player.cards, {id = dropCardId, usesLeft = usesLeft})
                    local rDef = RARITY_DEF[drop.rarity or cdef.rarity or "rare"]
                    resultMsg = resultMsg .. " Boss掉落[" .. (rDef and rDef.name or "") .. "]" .. cdef.name .. "！"
                end
            end
        end

        showMessage(resultMsg, 3.0, 255, 200, 50)
        local oldRow, oldCol = player.row, player.col
        player.row = nr
        player.col = nc
        startMoveAnim(oldRow, oldCol)

        -- 发放经验
        if totalExp > 0 then
            awardExp(totalExp)
        end
        return
    end

    -- 构建怪物数组（统一战斗）
    local monsters = { buildMonsterEntry(monsterCh) }
    for _, adj in ipairs(adjacent) do
        table.insert(monsters, buildMonsterEntry(adj.ch))
    end

    -- 检查是否有先攻怪物
    local hasPreemptive = false
    for _, mo in ipairs(monsters) do
        if mo.preemptive then hasPreemptive = true; break end
    end

    -- 启动战斗动画
    battle.active = true
    battle.monsters = monsters
    battle.playerHP = player.hp
    battle.playerStartHP = player.hp
    battle.displayPlayerHP = player.hp
    battle.hasShield = player.skills.shield == true
    battle.round = 0
    battle.timer = 0
    battle.targetRow = nr
    battle.targetCol = nc
    battle.shakeOffset = 0
    battle.allEnemyPositions = allPositions
    battle.totalGold = totalGoldSum
    battle.totalMonsterNames = allNames
    battle.consumedCardIndices = {}

    -- 卡牌战斗状态初始化
    battle.hand = {}
    battle.selectedCard = nil
    battle.cardEffects = {}
    battle.powerNext = false
    battle.critUsed = false  -- 暴击被动：首击标记
    battle.reflectActive = false
    battle.guardActive = false
    battle.immortalActive = false
    battle.shieldHP = 0
    battle.curseAtkLoss = 0
    battle.curseDefLoss = 0
    battle.fogDrawLoss = 0
    battle.warCryAtk = 0
    battle.frenzyAtk = 0
    battle.fury = 0
    battle.bloodFrenzyHeal = false
    battle.thornsActive = 0
    battle.thornsRate = 0
    battle.berserkerRageActive = false
    battle.undyingActive = false
    battle.bloodScentTurns = 0
    battle.titanSkipNext = false
    battle.titanSkipActive = false
    multiHitState = nil
    battle.effectText = ""
    battle.effectTimer = 0
    floatTexts = {}            -- 清空浮动伤害文字
    battle.atkIndex = 0        -- 当前攻击的怪物索引（逐个攻击用）
    battle.atkMonsterDmg = 0   -- 当前攻击怪物的单次伤害
    battle.atkMonsterName = "" -- 当前攻击怪物名
    battle.atkShielded = false -- 圣盾免伤状态
    battle.atkActualDmg = 0    -- 实际扣血量
    battle.targetIdx = getFirstAliveMonster() or 1  -- 玩家选中的攻击目标
    battle._monsterRects = {}  -- 怪物点击区域（渲染时填充）
    battle._moEffectRects = {} -- 怪物debuff图标点击区域（渲染时填充）
    battle._statusRects = {}   -- 状态图标点击区域（渲染时填充）
    battle._statusPopup = nil  -- 状态详情弹窗 {st = ...}
    battle._endTurnDiscarded = nil
    battle._endTurnCurseProcessed = nil
    battle.autoEndTimer = nil
    cardDrag.active = false
    cardDiscardAnim.active = false
    cardDiscardAnim.cards = {}
    cardDiscardAnim.timer = 0
    curseInsertAnim.active = false
    curseInsertAnim.cards = {}
    curseInsertAnim.timer = 0

    -- MP初始化
    battle.mp = player.maxMp
    battle.maxMp = player.maxMp
    battle.mpRegen = player.mpRegen
    battle.devBattle = false  -- 正常战斗，胜利后清除地图格子

    -- 构建牌库并抽初始手牌
    buildBattleDeck()
    drawCards(player.drawCount)

    -- 先攻：怪物先手，从monster_atk开始；否则等待选卡
    if hasPreemptive then
        battle.phase = "monster_atk"
        -- 先攻：初始化逐个攻击（预扣伤害，和后续攻击逻辑一致）
        for i, mo in ipairs(battle.monsters) do
            if mo.alive then
                battle.atkIndex = i
                battle.atkMonsterDmg = mo.dmg
                battle.atkMonsterName = mo.name
                battle.atkShieldAbsorb = 0
                -- 圣盾：先攻回合 round==0 免伤
                local shielded = battle.hasShield and battle.round == 0
                battle.atkShielded = shielded
                local preDmg = mo.dmg
                if shielded then preDmg = 0 end
                if battle.immortalActive then preDmg = 0 end
                -- 护盾吸收（无视护盾的怪物跳过）
                if preDmg > 0 and battle.shieldHP > 0 and not (mo.skill and mo.skill.id == "pierceShield") then
                    battle.atkShieldAbsorb = math.min(battle.shieldHP, mo.dmg)
                    if battle.shieldHP >= preDmg then preDmg = 0
                    else preDmg = preDmg - battle.shieldHP end
                end
                battle.atkActualDmg = preDmg
                battle.playerHP = battle.playerHP - preDmg
                if battle.undyingActive and battle.playerHP < 1 then battle.playerHP = 1 end
                playSfx("monster_attack", 0.3)
                if shielded then
                    playSfx("block", 0.5)
                elseif battle.atkShieldAbsorb > 0 then
                    playSfx("block", 0.4)
                    battle.shakeOffset = -3
                elseif preDmg > 0 then
                    playSfx("hurt", 0.5)
                    battle.shakeOffset = -8
                else
                    battle.shakeOffset = -8
                end
                applyCurseOnHit(mo, i)
                break
            end
        end
    else
        battle.phase = "waiting_for_card"
    end
    cardAnims = {}
    battle.hoveredCard = 0
    autoPath = {}
end

--- 开发者测试战斗：直接指定多个怪物字符，不依赖地图位置
local function startDevBattle(monsterChars)
    local monsters = {}
    local allNames = {}
    local totalGoldSum = 0
    local allPositions = {}
    for _, mch in ipairs(monsterChars) do
        local m = MONSTER_DEF[mch]
        if m then
            table.insert(monsters, buildMonsterEntry(mch))
            table.insert(allNames, m.name)
            totalGoldSum = totalGoldSum + m.gold
            table.insert(allPositions, {row = player.row, col = player.col, ch = mch})
        end
    end
    if #monsters == 0 then return end

    local hasPreemptive = false
    for _, mo in ipairs(monsters) do
        if mo.preemptive then hasPreemptive = true; break end
    end

    battle.active = true
    battle.monsters = monsters
    battle.playerHP = player.hp
    battle.playerStartHP = player.hp
    battle.displayPlayerHP = player.hp
    battle.hasShield = player.skills.shield == true
    battle.round = 0
    battle.timer = 0
    battle.targetRow = player.row
    battle.targetCol = player.col
    battle.shakeOffset = 0
    battle.allEnemyPositions = allPositions
    battle.totalGold = totalGoldSum
    battle.totalMonsterNames = allNames
    battle.consumedCardIndices = {}
    battle.hand = {}
    battle.selectedCard = nil
    battle.cardEffects = {}
    battle.powerNext = false
    battle.critUsed = false  -- 暴击被动：首击标记
    battle.reflectActive = false
    battle.guardActive = false
    battle.immortalActive = false
    battle.shieldHP = 0
    battle.warCryAtk = 0
    battle.frenzyAtk = 0
    battle.fury = 0
    battle.bloodFrenzyHeal = false
    battle.thornsActive = 0
    battle.thornsRate = 0
    battle.berserkerRageActive = false
    battle.undyingActive = false
    battle.bloodScentTurns = 0
    battle.titanSkipNext = false
    battle.titanSkipActive = false
    multiHitState = nil
    battle.effectText = ""
    battle.effectTimer = 0
    floatTexts = {}
    battle.atkIndex = 0
    battle.atkMonsterDmg = 0
    battle.atkMonsterName = ""
    battle.atkShielded = false
    battle.atkActualDmg = 0
    battle.targetIdx = getFirstAliveMonster() or 1
    battle._monsterRects = {}
    battle._moEffectRects = {}
    battle._statusRects = {}
    battle._endTurnDiscarded = nil
    battle._endTurnCurseProcessed = nil
    battle.autoEndTimer = nil
    cardDrag.active = false
    cardDiscardAnim.active = false
    cardDiscardAnim.cards = {}
    cardDiscardAnim.timer = 0
    curseInsertAnim.active = false
    curseInsertAnim.cards = {}
    curseInsertAnim.timer = 0
    battle.mp = player.maxMp
    battle.maxMp = player.maxMp
    battle.mpRegen = player.mpRegen
    battle.devBattle = true  -- 标记为开发者战斗，胜利后不清除地图格子

    buildBattleDeck()
    drawCards(player.drawCount)

    if hasPreemptive then
        battle.phase = "monster_atk"
        for i, mo in ipairs(battle.monsters) do
            if mo.alive then
                battle.atkIndex = i
                battle.atkMonsterDmg = mo.dmg
                battle.atkMonsterName = mo.name
                if mo.dmg > 0 then playSfx("hurt", 0.5) end
                battle.shakeOffset = -8
                break
            end
        end
    else
        battle.phase = "waiting_for_card"
    end
    cardAnims = {}
    battle.hoveredCard = 0
    autoPath = {}
end

--- 更新玩家朝向
local function updateFacing(dr, dc)
    if dr == -1 then player.facing = "up"
    elseif dr == 1 then player.facing = "down"
    elseif dc == -1 then player.facing = "left"
    elseif dc == 1 then player.facing = "right"
    end
end

--- 尝试移动玩家
local function tryMove(dr, dc)
    if gameState ~= "playing" then return end
    if moveAnim.active then return end  -- 移动动画中禁止输入
    if battle.active then return end    -- 战斗动画中禁止输入
    if stairUI.active then return end   -- 上楼选择中禁止输入
    if stairUI.jumpAnim.active then return end  -- 跳跃动画中禁止输入

    -- 无论能否移动，先更新朝向
    updateFacing(dr, dc)

    local nr = player.row + dr
    local nc = player.col + dc

    -- 边界检查
    if nr < 1 or nr > GRID or nc < 1 or nc > GRID then return end

    local tile = maps[player.floor][nr][nc]

    -- 墙壁
    if tile == 'W' then return end

    -- 怪物（卡牌战斗系统：始终允许进入战斗，不做数值预估阻挡）
    if isMonster(tile) then
        startBattle(tile, nr, nc)
        return
    end

    -- 钥匙
    if isKey(tile) then
        local key = KEY_DEF[tile]
        player[key.field] = player[key.field] + 1
        maps[player.floor][nr][nc] = '.'
        playSfx("pickup", 0.8)
        showMessage(key.name .. "！", 1.5, key.r, key.g, key.b)
        local oldRow, oldCol = player.row, player.col
        player.row = nr
        player.col = nc
        startMoveAnim(oldRow, oldCol)
        return
    end

    -- 门
    if isDoor(tile) then
        local door = DOOR_DEF[tile]
        if player[door.keyField] > 0 then
            player[door.keyField] = player[door.keyField] - 1
            -- 记录开门动画
            table.insert(doorAnims, {row = nr, col = nc, tile = tile, timer = 0, duration = DOOR_ANIM_DURATION})
            maps[player.floor][nr][nc] = '.'
            playSfx("door", 0.8)
            showMessage("打开了" .. door.name .. "！", 1.5, door.r, door.g, door.b)
            local oldRow, oldCol = player.row, player.col
            player.row = nr
            player.col = nc
            startMoveAnim(oldRow, oldCol)
        else
            local keyName = door.keyField == "yellowKeys" and "黄钥匙" or
                            door.keyField == "blueKeys" and "蓝钥匙" or "红钥匙"
            showMessage("需要" .. keyName .. "！", 1.5, 255, 80, 80)
            autoPath = {}
        end
        return
    end

    -- 物品 → 作为卡牌加入牌组（按楼层决定物品等级）
    if isItem(tile) then
        local cardId
        -- 血瓶
        if tile == "h" then cardId = "hp50"
        elseif tile == "H" then cardId = "hp100"
        elseif tile == "z" then cardId = "hp300"
        -- 攻击宝石
        elseif tile == "a" then cardId = "atk1"
        elseif tile == "j" then cardId = "atk2"
        elseif tile == "m" then cardId = "atk4"
        elseif tile == "s" then cardId = "atk8"
        elseif tile == "v" then cardId = "atk15"
        -- 防御宝石
        elseif tile == "d" then cardId = "def1"
        elseif tile == "c" then cardId = "def2"
        elseif tile == "g" then cardId = "def4"
        elseif tile == "q" then cardId = "def8"
        elseif tile == "x" then cardId = "def15"
        end
        if cardId then
            local cdef = CARD_DEF[cardId]
            table.insert(player.cards, {id = cardId, usesLeft = cdef.maxUses})
            playSfx("pickup", 0.8)
            showMessage("获得卡牌【" .. cdef.name .. "】" .. cdef.desc, 1.5, cdef.r, cdef.g, cdef.b)
        end
        maps[player.floor][nr][nc] = '.'
        local oldRow, oldCol = player.row, player.col
        player.row = nr
        player.col = nc
        startMoveAnim(oldRow, oldCol)
        return
    end

    -- 被动技能
    if isSkill(tile) then
        local sk = SKILL_DEF[tile]
        if not player.skills[sk.id] then
            player.skills[sk.id] = true
            playSfx("pickup", 0.8)
            showMessage("获得被动技能【" .. sk.name .. "】" .. sk.desc, 3.0, sk.r, sk.g, sk.b)
        else
            showMessage("已拥有【" .. sk.name .. "】", 1.5, sk.r, sk.g, sk.b)
        end
        maps[player.floor][nr][nc] = '.'
        local oldRow, oldCol = player.row, player.col
        player.row = nr
        player.col = nc
        startMoveAnim(oldRow, oldCol)
        return
    end

    -- 遗物拾取
    if isRelic(tile) then
        local rl = RELIC_DEF[tile]
        if not player.relics[rl.id] then
            player.relics[rl.id] = true
            playSfx("pickup", 0.8)
            showMessage(rl.icon .. " 获得遗物【" .. rl.name .. "】", 2.0, rl.r, rl.g, rl.b)
        else
            showMessage("已拥有【" .. rl.name .. "】", 1.5, rl.r, rl.g, rl.b)
        end
        maps[player.floor][nr][nc] = '.'
        local oldRow, oldCol = player.row, player.col
        player.row = nr
        player.col = nc
        startMoveAnim(oldRow, oldCol)
        return
    end

    -- 宝石拾取 → 弹出选择面板（镶嵌/放入背包），取消则留在地图
    if isGem(tile) then
        local gemId = GEM_MAP_CHAR[tile]
        local gd = GEM_DEF[gemId]
        playSfx("pickup", 0.8)
        local oldRow, oldCol = player.row, player.col
        player.row = nr
        player.col = nc
        startMoveAnim(oldRow, oldCol)
        -- 打开装备选择面板（不移除地图、不加背包）
        gemEquip.open = true
        gemEquip.gemId = gemId
        gemEquip.scroll = 0
        gemEquip.fromMap = true
        gemEquip.mapRow = nr
        gemEquip.mapCol = nc
        gemEquip.mapFloor = player.floor
        autoPath = {}
        return
    end

    -- 商店NPC（不消失，可反复访问）
    if tile == SHOP_NPC_CHAR then
        local ok, items = pcall(getShopItems, player.floor)
        shopItems = ok and items or {}
        shopOpen = true
        shopScroll = 0
        autoPath = {}
        if not ok then
            log:Write(LOG_ERROR, "[Shop] 商品生成失败: " .. tostring(items))
            showMessage("商店暂时无法打开", 1.5, 255, 100, 100)
        end
        playSfx("pickup", 0.8)
        return
    end

    -- 楼梯上
    if tile == 'U' then
        if #autoPath > 0 then
            -- 自动寻路：略过楼梯，当作空地走过
            local oldRow, oldCol = player.row, player.col
            player.row = nr
            player.col = nc
            startMoveAnim(oldRow, oldCol)
            return
        end
        if player.floor < TOTAL_FLOORS then
            if player.floor + 1 > math.min(CONTENT_MAX_FLOOR or TOTAL_FLOORS, TOTAL_FLOORS) then
                showMessage("后续内容正在完善中，敬请期待", 2.5, 255, 220, 100)
                playSfx("block", 0.6)
                return
            end
            -- 弹出跳跃上楼选择界面
            stairUI.active = true
            stairUI.phase = "choose"
            stairUI.selectedCard = nil
            stairUI.cardScroll = 0
            stairUI.cardRects = {}
            -- 判断是否可以跳跃: 牌组>5张 且 目标层不超过总层数/已开放内容
            local contentMaxFloor = math.min(CONTENT_MAX_FLOOR or TOTAL_FLOORS, TOTAL_FLOORS)
            stairUI.canJump = (#player.cards > 5) and (player.floor + 2 <= contentMaxFloor)
            -- 首次显示封印提示
            if stairUI.firstShow then
                showMessage("⚠ 魔塔封印: 上楼后无法下楼，请谨慎决定!", 3.5, 255, 200, 80)
                stairUI.firstShow = false
            end
        end
        return
    end

    -- 楼梯下（封印：禁止下楼）
    if tile == 'D' then
        if #autoPath > 0 then
            local oldRow, oldCol = player.row, player.col
            player.row = nr
            player.col = nc
            startMoveAnim(oldRow, oldCol)
            return
        end
        showMessage("封印之力阻止了你…上楼之后无法下楼", 2.0, 255, 100, 100)
        playSfx("block", 0.6)
        return
    end

    -- 空地
    local oldRow, oldCol = player.row, player.col
    player.row = nr
    player.col = nc
    startMoveAnim(oldRow, oldCol)
end

-- ============================================================
-- 渲染
-- ============================================================

--- 绘制精灵图子区域
--- @param imageHandle number NanoVG 图片句柄
--- @param imgW number 整张图片宽度
--- @param imgH number 整张图片高度
--- @param sx number 源区域X (像素)
--- @param sy number 源区域Y (像素)
--- @param sw number 源区域宽 (像素)
--- @param sh number 源区域高 (像素)
--- @param dx number 目标X
--- @param dy number 目标Y
--- @param dw number 目标宽
--- @param dh number 目标高
function drawSpriteRegion(imageHandle, imgW, imgH, sx, sy, sw, sh, dx, dy, dw, dh)
    if imgW <= 0 or imgH <= 0 or sw <= 0 or sh <= 0 then return end
    local scaleX = dw / sw
    local scaleY = dh / sh
    nvgSave(nvgCtx)
    nvgIntersectScissor(nvgCtx, dx, dy, dw, dh)
    local imgX = dx - sx * scaleX
    local imgY = dy - sy * scaleY
    local imgDrawW = imgW * scaleX
    local imgDrawH = imgH * scaleY
    local imgPaint = nvgImagePattern(nvgCtx, imgX, imgY, imgDrawW, imgDrawH, 0, imageHandle, 1.0)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, dx, dy, dw, dh)
    nvgFillPaint(nvgCtx, imgPaint)
    nvgFill(nvgCtx)
    nvgRestore(nvgCtx)
end

-- 卡牌图片路径映射（统一命名: image/card_{id}.png）
local CARD_IMG_PATH = {
    strike      = "image/card_strike.png",
    defend      = "image/card_defend.png",
    heal        = "image/card_heal.png",
    guard       = "image/card_guard.png",
    shield      = "image/card_shield.png",
    poison      = "image/card_poison.png",
    power       = "image/card_power.png",
    drain       = "image/card_drain.png",
    weaken      = "image/card_weaken.png",
    reflect     = "image/card_reflect.png",
    execute     = "image/card_execute.png",
    haste       = "image/card_haste.png",
    thunder     = "image/card_thunder.png",
    firestorm   = "image/card_firestorm.png",
    thrifty     = "image/card_thrifty.png",
    meditate    = "image/card_meditate.png",
    pierce      = "image/card_pierce.png",
    heavyStrike = "image/card_heavyStrike.png",
    bladestorm  = "image/card_bladestorm.png",
    soulBurn    = "image/card_soulBurn.png",
    handBlast   = "image/card_handBlast.png",
    devour      = "image/card_devour.png",
    convert     = "image/card_convert.png",
    wound       = "image/card_wound.png",
    curse       = "image/card_curse.png",
    cleave      = "image/card_cleave.png",
    ironWall    = "image/card_ironWall.png",
    thorns      = "image/card_thorns.png",
    deathDance  = "image/card_deathDance.png",
    oblivion    = "image/card_oblivion.png",
    immortal    = "image/card_immortal.png",
    warCry      = "image/card_warCry.png",
    atkShield   = "image/card_atkShield.png",
    cardDraw    = "image/card_cardDraw.png",
    alchemy     = "image/card_alchemy.png",
    sacrifice   = "image/card_sacrifice.png",
    empower     = "image/card_empower.png",
    gambit      = "image/card_gambit.png",
    fusion      = "image/card_fusion.png",
    frail       = "image/card_frail.png",
    erode       = "image/card_erode.png",
    fog         = "image/card_fog.png",
    nightmare   = "image/card_nightmare.png",
    venomBlade  = "image/card_venomBlade.png",
    shieldSlam  = "image/card_shieldSlam.png",
    bloodRite   = "image/card_bloodRite.png",
    armorBreak  = "image/card_armorBreak.png",
    armorStance = "image/card_armorStance.png",
    rend        = "image/card_rend.png",
    bloodFrenzy = "image/card_bloodFrenzy.png",
    rampage     = "image/card_rampage.png",
    savageBash  = "image/card_savageBash.png",
    roar        = "image/card_roar.png",
    furyCleave  = "image/card_furyCleave.png",
    battleCry   = "image/card_battleCry.png",
    toughHide   = "image/card_toughHide.png",
    berserkerRage = "image/card_berserkerRage.png",
    groundSlam  = "image/card_groundSlam.png",
    furyBurst   = "image/card_furyBurst.png",
    undying     = "image/card_undying.png",
    bloodScent  = "image/card_bloodScent.png",
    titanGrip   = "image/card_titanGrip.png",
    warpath     = "image/card_warpath.png",
}

-- 卡牌图片句柄缓存 {id = {handle, w, h}}
local cardImages = {}

-- 图标图片路径映射（挂在 spr 表上，避免 local 变量数超限）
spr.ICON_IMG_PATH = {}  -- 所有图标由 IconSet.png 统一提供，无需单独文件
-- 图标图片句柄缓存 {id = {handle, w, h}}
spr.iconImages = {}

--- 加载所有精灵图
local function loadSpriteImages()
    -- 加载怪物精灵图
    for id, m in pairs(MONSTER_DEF) do
        if m.sprite and not spriteImages[m.sprite] then
            local handle = nvgCreateImage(nvgCtx, m.sprite, NVG_IMAGE_NEAREST)
            if handle ~= -1 and handle ~= 0 then
                local w, h = nvgImageSize(nvgCtx, handle)
                spriteImages[m.sprite] = {handle = handle, w = w, h = h}
                log:Write(LOG_INFO, "Loaded sprite: " .. m.sprite .. " (" .. w .. "x" .. h .. ")")
            else
                log:Write(LOG_WARNING, "Failed to load sprite: " .. m.sprite)
            end
        end
    end

    -- 加载玩家精灵图
    local ph = nvgCreateImage(nvgCtx, PLAYER_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if ph ~= -1 and ph ~= 0 then
        spr.playerW, spr.playerH = nvgImageSize(nvgCtx, ph)
        spr.player = ph
        log:Write(LOG_INFO, "Loaded player sprite: " .. PLAYER_SPRITE_PATH .. " (" .. spr.playerW .. "x" .. spr.playerH .. ")")
    else
        log:Write(LOG_WARNING, "Failed to load player sprite: " .. PLAYER_SPRITE_PATH)
    end

    -- 加载墙壁精灵图（最近邻采样，避免 atlas 纹理泄漏）
    local wh = nvgCreateImage(nvgCtx, WALL_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if wh ~= -1 and wh ~= 0 then
        spr.wallW, spr.wallH = nvgImageSize(nvgCtx, wh)
        spr.wall = wh
        log:Write(LOG_INFO, "Loaded wall sprite: " .. WALL_SPRITE_PATH .. " (" .. spr.wallW .. "x" .. spr.wallH .. ")")
    else
        log:Write(LOG_WARNING, "Failed to load wall sprite: " .. WALL_SPRITE_PATH)
    end

    -- 加载物品精灵图（宝石+血瓶，最近邻采样）
    local ih = nvgCreateImage(nvgCtx, ITEM_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if ih ~= -1 and ih ~= 0 then
        spr.itemW, spr.itemH = nvgImageSize(nvgCtx, ih)
        spr.item = ih
        log:Write(LOG_INFO, "Loaded item sprite: " .. ITEM_SPRITE_PATH .. " (" .. spr.itemW .. "x" .. spr.itemH .. ")")
    else
        log:Write(LOG_WARNING, "Failed to load item sprite: " .. ITEM_SPRITE_PATH)
    end

    -- 加载宝石精灵图（$2 (4).png，4行3列，最近邻采样）
    local gemH = nvgCreateImage(nvgCtx, "image/$2 (4).png", NVG_IMAGE_NEAREST)
    if gemH ~= -1 and gemH ~= 0 then
        spr.gemStonesW, spr.gemStonesH = nvgImageSize(nvgCtx, gemH)
        spr.gemStones = gemH
        log:Write(LOG_INFO, "Loaded gem stones sprite: " .. spr.gemStonesW .. "x" .. spr.gemStonesH)
    else
        log:Write(LOG_WARNING, "Failed to load gem stones sprite")
    end

    -- 加载钥匙精灵图（最近邻采样）
    local kh = nvgCreateImage(nvgCtx, KEY_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if kh ~= -1 and kh ~= 0 then
        spr.keyW, spr.keyH = nvgImageSize(nvgCtx, kh)
        spr.key = kh
        log:Write(LOG_INFO, "Loaded key sprite: " .. KEY_SPRITE_PATH .. " (" .. spr.keyW .. "x" .. spr.keyH .. ")")
    else
        log:Write(LOG_WARNING, "Failed to load key sprite: " .. KEY_SPRITE_PATH)
    end

    -- 加载门精灵图（最近邻采样）
    local dh2 = nvgCreateImage(nvgCtx, DOOR_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if dh2 ~= -1 and dh2 ~= 0 then
        spr.doorW, spr.doorH = nvgImageSize(nvgCtx, dh2)
        spr.door = dh2
        log:Write(LOG_INFO, "Loaded door sprite: " .. DOOR_SPRITE_PATH .. " (" .. spr.doorW .. "x" .. spr.doorH .. ")")
    else
        log:Write(LOG_WARNING, "Failed to load door sprite: " .. DOOR_SPRITE_PATH)
    end

    -- 加载楼梯精灵图（最近邻采样）
    local sh2 = nvgCreateImage(nvgCtx, STAIR_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if sh2 ~= -1 and sh2 ~= 0 then
        spr.stairW, spr.stairH = nvgImageSize(nvgCtx, sh2)
        spr.stair = sh2
        log:Write(LOG_INFO, "Loaded stair sprite: " .. STAIR_SPRITE_PATH .. " (" .. spr.stairW .. "x" .. spr.stairH .. ")")
    else
        log:Write(LOG_WARNING, "Failed to load stair sprite: " .. STAIR_SPRITE_PATH)
    end

    -- 启动时预加载所有实际卡牌插画；资源配置只打包脚本可达的图片，未引用的历史素材不会进入默认组
    for id, path in pairs(CARD_IMG_PATH) do
        local ch = nvgCreateImage(nvgCtx, path, 0)
        if ch ~= -1 and ch ~= 0 then
            local cw, chh = nvgImageSize(nvgCtx, ch)
            cardImages[id] = {handle = ch, w = cw, h = chh}
            log:Write(LOG_INFO, "Loaded card image: " .. id .. " (" .. cw .. "x" .. chh .. ")")
        else
            log:Write(LOG_WARNING, "Failed to load card image: " .. path)
        end
    end

    -- 加载卡牌框图片
    local cfh = nvgCreateImage(nvgCtx, "image/card/card_frame_clean.png", 0)
    if cfh ~= -1 and cfh ~= 0 then
        spr.cardFrameW, spr.cardFrameH = nvgImageSize(nvgCtx, cfh)
        spr.cardFrame = cfh
        log:Write(LOG_INFO, "Loaded card frame: " .. spr.cardFrameW .. "x" .. spr.cardFrameH)
    else
        log:Write(LOG_WARNING, "Failed to load card frame")
    end

    -- 加载物品卡背景图
    local itemBgH = nvgCreateImage(nvgCtx, "image/card_item_bg.png", 0)
    if itemBgH ~= -1 and itemBgH ~= 0 then
        spr.itemBgW, spr.itemBgH = nvgImageSize(nvgCtx, itemBgH)
        spr.itemBg = itemBgH
        log:Write(LOG_INFO, "Loaded item card bg: " .. spr.itemBgW .. "x" .. spr.itemBgH)
    else
        log:Write(LOG_WARNING, "Failed to load item card bg")
    end

    -- 加载费用宝石图片 (mana_0 ~ mana_5)
    spr.manaGems = {}
    for i = 0, 5 do
        local mh = nvgCreateImage(nvgCtx, "image/card/mana_" .. i .. ".png", 0)
        if mh ~= -1 and mh ~= 0 then
            local mw, mhh = nvgImageSize(nvgCtx, mh)
            spr.manaGems[i] = {handle = mh, w = mw, h = mhh}
            log:Write(LOG_INFO, "Loaded mana gem " .. i .. ": " .. mw .. "x" .. mhh)
        else
            log:Write(LOG_WARNING, "Failed to load mana gem: " .. i)
        end
    end

    -- 加载标题背景图
    local bgh = nvgCreateImage(nvgCtx, "image/bg_title.png", 0)
    if bgh ~= -1 and bgh ~= 0 then
        spr.bgTitleW, spr.bgTitleH = nvgImageSize(nvgCtx, bgh)
        spr.bgTitle = bgh
        log:Write(LOG_INFO, "Loaded title bg: " .. spr.bgTitleW .. "x" .. spr.bgTitleH)
    else
        log:Write(LOG_WARNING, "Failed to load title bg")
    end

    -- 加载模式选择背景图
    local mbg = nvgCreateImage(nvgCtx, "image/bg_mode.png", 0)
    if mbg ~= -1 and mbg ~= 0 then
        spr.bgModeW, spr.bgModeH = nvgImageSize(nvgCtx, mbg)
        spr.bgMode = mbg
        log:Write(LOG_INFO, "Loaded mode bg: " .. spr.bgModeW .. "x" .. spr.bgModeH)
    end

    -- 加载 IconSet.png（统一精灵图，包含全部图标）
    -- 加载 IconSet.png（尝试多个路径）
    spr.iconSetHandle = nil
    local iconSetPaths = {"image/IconSet.png", "IconSet.png", "icons/IconSet.png"}
    for _, iconSetPath in ipairs(iconSetPaths) do
        local isH = nvgCreateImage(nvgCtx, iconSetPath, NVG_IMAGE_NEAREST)
        if isH and isH ~= 0 and isH ~= -1 then
            local isW, isHH = nvgImageSize(nvgCtx, isH)
            if isW > 0 and isHH > 0 then
                spr.iconSetHandle = isH
                spr.iconSetW = isW
                spr.iconSetH = isHH
                log:Write(LOG_INFO, "Loaded IconSet: " .. iconSetPath .. " (" .. isW .. "x" .. isHH .. ")")
                break
            end
        end
    end
    if not spr.iconSetHandle then
        log:Write(LOG_WARNING, "IconSet load FAILED (tried all paths)")
    end

    -- 兼容: 仍尝试加载单独icon文件作为fallback
    local iconOk, iconFail = 0, 0
    for id, path in pairs(spr.ICON_IMG_PATH) do
        local ih = nvgCreateImage(nvgCtx, path, NVG_IMAGE_NEAREST)
        if ih ~= nil and ih ~= 0 and ih ~= -1 then
            local iw, ihh = nvgImageSize(nvgCtx, ih)
            spr.iconImages[id] = {handle = ih, w = iw, h = ihh}
            iconOk = iconOk + 1
        else
            iconFail = iconFail + 1
        end
    end
    log:Write(LOG_INFO, "Loaded icon images: " .. iconOk .. " ok, " .. iconFail .. " failed (IconSet as primary)")
end

--- 绘制图标图片（居中绘制在指定区域）
-- IconSet 图标行列映射 (iconId → {row, col})
spr.ICON_SET_MAP = {
    -- Row 0: 宝石(8) + 属性(5) + UI(3)
    gem_flame = {0,0}, gem_frost = {0,1}, gem_holy = {0,2}, gem_thunder = {0,3},
    gem_thrift = {0,4}, gem_blood = {0,5}, gem_echo = {0,6}, gem_draw = {0,7},
    icon_hp = {0,8}, icon_atk = {0,9}, icon_def = {0,10}, icon_mp = {0,11},
    icon_gold = {0,12}, icon_scroll_tactics = {0,13}, icon_scroll_wisdom = {0,14}, icon_card = {0,15},
    -- Row 1: 状态(16)
    status_shield = {1,0}, status_power = {1,1}, status_reflect = {1,2}, status_thorns = {1,3},
    status_poison = {1,4}, status_weaken = {1,5}, status_burn = {1,6}, status_curse = {1,7},
    status_berserk = {1,8}, status_frail = {1,9}, status_fog = {1,10}, status_vulnerable = {1,11},
    status_undying = {1,12}, status_blood_scent = {1,13}, status_exhausted = {1,14}, status_immortal = {1,15},
    -- Row 2: 技能(7) + 物品(5)
    skill_frost_armor = {2,0}, skill_vampire = {2,1}, skill_greatsword = {2,2}, skill_thorn_armor = {2,3},
    skill_bag = {2,4}, skill_execute = {2,5}, skill_meditate = {2,6},
    item_potion_hp = {2,7}, item_hammer = {2,8}, item_key = {2,9}, mode_random = {2,10}, mode_fixed = {2,11},
}

function spr.drawIcon(iconId, cx, cy, size, alpha, noBorder)
    local halfS = size / 2
    local x, y = cx - halfS, cy - halfS
    local a = alpha or 1.0

    -- 优先: 从 IconSet.png 裁切绘制
    -- noBorder=true: 跳过4px边框只取内部24x24(用于地图格子等已有底色的场景)
    -- noBorder=false/nil(默认): 显示完整32x32含边框图标
    if spr.iconSetHandle and spr.ICON_SET_MAP[iconId] then
        local mapping = spr.ICON_SET_MAP[iconId]
        local row, col = mapping[1], mapping[2]
        local BORDER = noBorder and 4 or 0
        local INNER = 32 - BORDER * 2
        local sx = col * 32 + BORDER
        local sy = row * 32 + BORDER
        local scaleX = size / INNER
        local scaleY = size / INNER
        local imgX = x - sx * scaleX
        local imgY = y - sy * scaleY

        nvgSave(nvgCtx)
        nvgGlobalAlpha(nvgCtx, a)
        nvgIntersectScissor(nvgCtx, x, y, size, size)
        local imgPaint = nvgImagePattern(nvgCtx, imgX, imgY,
            spr.iconSetW * scaleX, spr.iconSetH * scaleY, 0, spr.iconSetHandle, 1.0)
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, x, y, size, size)
        nvgFillPaint(nvgCtx, imgPaint)
        nvgFill(nvgCtx)
        nvgRestore(nvgCtx)
        return true
    end

    -- Fallback: 单独icon文件
    local img = spr.iconImages[iconId]
    if img and img.handle then
        local scaleX = size / img.w
        local scaleY = size / img.h
        local imgX = x
        local imgY = y

        nvgSave(nvgCtx)
        nvgGlobalAlpha(nvgCtx, a)
        local imgPaint = nvgImagePattern(nvgCtx, imgX, imgY, size, size, 0, img.handle, 1.0)
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, imgX, imgY, size, size)
        nvgFillPaint(nvgCtx, imgPaint)
        nvgFill(nvgCtx)
        nvgRestore(nvgCtx)
        return true
    end

    return false
end

--- 绘制圆角矩形
function drawRoundRect(x, y, w, h, radius, r, g, b, a)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, x, y, w, h, radius or 4)
    nvgFillColor(nvgCtx, nvgRGBA(r, g, b, a or 255))
    nvgFill(nvgCtx)
end

--- 绘制渐变条（带高光玻璃效果）
--- r,g,b: 主色调  a: 透明度  darkRatio: 底部暗化比例(0~1, 默认0.45)
function drawGradientBar(x, y, w, h, radius, r, g, b, a, darkRatio)
    if w < 1 then return end
    a = a or 255
    darkRatio = darkRatio or 0.45
    local rad = math.min(radius or 4, h / 2, w / 2)
    local dr = math.floor(r * darkRatio)
    local dg = math.floor(g * darkRatio)
    local db = math.floor(b * darkRatio)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, x, y, w, h, rad)
    local grad = nvgLinearGradient(nvgCtx, x, y, x, y + h,
        nvgRGBA(r, g, b, a), nvgRGBA(dr, dg, db, a))
    nvgFillPaint(nvgCtx, grad)
    nvgFill(nvgCtx)
end

--- 绘制条背景（凹陷质感）
function drawBarBg(x, y, w, h, radius, a)
    a = a or 255
    -- 底色
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, x, y, w, h, radius or 4)
    local bgGrad = nvgLinearGradient(nvgCtx, x, y, x, y + h,
        nvgRGBA(15, 15, 25, a), nvgRGBA(35, 35, 50, a))
    nvgFillPaint(nvgCtx, bgGrad)
    nvgFill(nvgCtx)
    -- 内阴影（顶部暗线）
    if h >= 6 then
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, x, y, w, math.max(2, h * 0.3), radius or 4)
        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, math.floor(a * 0.3)))
        nvgFill(nvgCtx)
    end
end

--- 绘制文字（居中）
function drawTextCenter(text, x, y, size, r, g, b, a)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, size)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(r or 255, g or 255, b or 255, a or 255))
    nvgText(nvgCtx, x, y, text)
end

--- 绘制文字（左对齐）
function drawTextLeft(text, x, y, size, r, g, b, a)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, size)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(r or 255, g or 255, b or 255, a or 255))
    nvgText(nvgCtx, x, y, text)
end

--- 绘制文字（右对齐）
local function drawTextRight(text, x, y, size, r, g, b, a)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, size)
    nvgTextAlign(nvgCtx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(r or 255, g or 255, b or 255, a or 255))
    nvgText(nvgCtx, x, y, text)
end

--- 绘制像素风描边文字（右下角对齐）
local function drawPixelText(text, x, y, size, r, g, b, a)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, size)
    nvgFontBlur(nvgCtx, 0)
    nvgTextAlign(nvgCtx, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    -- 粗描边（模拟像素轮廓）
    local outW = math.max(1.5, size * 0.12)
    nvgStrokeWidth(nvgCtx, outW)
    nvgStrokeColor(nvgCtx, nvgRGBA(0, 0, 0, a or 255))
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, a or 255))
    -- 四方向偏移绘制黑底
    for _, off in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
        nvgText(nvgCtx, x + off[1] * outW * 0.6, y + off[2] * outW * 0.6, text)
    end
    -- 前景色
    nvgFillColor(nvgCtx, nvgRGBA(r or 255, g or 255, b or 255, a or 255))
    nvgText(nvgCtx, x, y, text)
end

--- 绘制单个格子
function drawTile(row, col)
    local x = gridX + (col - 1) * cellSize
    local y = gridY + (row - 1) * cellSize
    local s = cellSize
    local pad = 0
    local tile = maps[player.floor][row][col]

    -- 背景（地板）
    if spr.stair then
        -- Inside_B.png 第2行第4列 (0-indexed: row=1, col=3)
        drawSpriteRegion(spr.stair, spr.stairW, spr.stairH,
            3 * SPRITE_FRAME_W, 1 * SPRITE_FRAME_H, SPRITE_FRAME_W, SPRITE_FRAME_H,
            x, y, s, s)
    else
        drawRoundRect(x, y, s, s, 0, 45, 42, 60)
    end

    -- 开门动画（门已变为地板，叠加渐隐的门精灵）
    for _, da in ipairs(doorAnims) do
        if da.row == row and da.col == col then
            local p = da.timer / da.duration  -- 0→1
            local alpha = math.floor(255 * (1 - p))
            local scale = 1 - p * 0.3  -- 缩小到0.7
            local ds = s * scale
            local dx = x + (s - ds) / 2
            local dy = y + (s - ds) / 2
            if spr.door then
                local doorColMap = { Y = 0, B = 1, R = 2 }
                local dc = doorColMap[da.tile] or 0
                nvgGlobalAlpha(nvgCtx, alpha / 255)
                drawSpriteRegion(spr.door, spr.doorW, spr.doorH,
                    dc * SPRITE_FRAME_W, 0, SPRITE_FRAME_W, SPRITE_FRAME_H,
                    dx, dy, ds, ds)
                nvgGlobalAlpha(nvgCtx, 1.0)
            else
                local d = DOOR_DEF[da.tile]
                if d then
                    drawRoundRect(dx, dy, ds, ds, 3, d.r, d.g, d.b, alpha)
                end
            end
            break
        end
    end

    -- 墙壁（使用精灵图左上角48x48静态帧）
    if tile == 'W' then
        if spr.wall then
            local wx = x + pad
            local wy = y + pad
            local ws = s - pad * 2
            drawSpriteRegion(spr.wall, spr.wallW, spr.wallH,
                0, 0, SPRITE_FRAME_W, SPRITE_FRAME_H,
                wx, wy, ws, ws)
        else
            -- 回退：精灵未加载时用纯色块
            drawRoundRect(x + pad, y + pad, s - pad * 2, s - pad * 2, 1, 85, 75, 105)
        end
        return
    end

    -- 楼梯上 (Inside_B.png 第7排第8列, 1-indexed)
    if tile == 'U' then
        if spr.stair then
            local margin = s * 0.05
            local dw = s - margin * 2
            local dh = s - margin * 2
            drawSpriteRegion(spr.stair, spr.stairW, spr.stairH,
                336, 288, SPRITE_FRAME_W, SPRITE_FRAME_H,
                x + margin, y + margin, dw, dh)
        else
            drawRoundRect(x + pad + 2, y + pad + 2, s - pad * 2 - 4, s - pad * 2 - 4, 3, 80, 180, 80)
            local fs = math.max(10, s * 0.45)
            drawTextCenter("\u{2B06}", x + s / 2, y + s / 2, fs, 255, 255, 255)
        end
        return
    end

    -- 楼梯下 (Inside_B.png 第7排第7列, 1-indexed)
    if tile == 'D' then
        if spr.stair then
            local margin = s * 0.05
            local dw = s - margin * 2
            local dh = s - margin * 2
            drawSpriteRegion(spr.stair, spr.stairW, spr.stairH,
                288, 288, SPRITE_FRAME_W, SPRITE_FRAME_H,
                x + margin, y + margin, dw, dh)
        else
            drawRoundRect(x + pad + 2, y + pad + 2, s - pad * 2 - 4, s - pad * 2 - 4, 3, 180, 140, 80)
            local fs = math.max(10, s * 0.45)
            drawTextCenter("\u{2B07}", x + s / 2, y + s / 2, fs, 255, 255, 255)
        end
        return
    end

    -- 钥匙
    if isKey(tile) then
        if spr.key then
            -- 钥匙精灵帧映射: tile → 列号（第1行）
            local keyColMap = { ["y"] = 0, ["b"] = 1, ["r"] = 2 }
            local kc = keyColMap[tile]
            if kc then
                local margin = s * 0.05
                local dw = s - margin * 2
                local dh = s - margin * 2
                drawSpriteRegion(spr.key, spr.keyW, spr.keyH,
                    kc * SPRITE_FRAME_W, 0, SPRITE_FRAME_W, SPRITE_FRAME_H,
                    x + margin, y + margin, dw, dh)
            end
        else
            -- 回退：精灵未加载时用色块
            local k = KEY_DEF[tile]
            drawRoundRect(x + pad + 2, y + pad + 2, s - pad * 2 - 4, s - pad * 2 - 4, 3, k.r, k.g, k.b)
            drawTextCenter("K", x + s / 2, y + s / 2, math.max(8, s * 0.3), 255, 255, 255)
        end
        return
    end

    -- 门
    if isDoor(tile) then
        local d = DOOR_DEF[tile]
        if spr.door then
            -- 门精灵：$1 (2).png 三列分别对应黄/蓝/红门
            local doorColMap = { Y = 0, B = 1, R = 2 }
            local dc = doorColMap[tile] or 0
            local fw = SPRITE_FRAME_W  -- 48
            local fh = SPRITE_FRAME_H  -- 48
            drawSpriteRegion(spr.door, spr.doorW, spr.doorH,
                dc * fw, 0, fw, fh,
                x, y, s, s)
        else
            -- 回退：简单色块
            drawRoundRect(x, y, s, s, 3, d.r, d.g, d.b, 240)
        end
        return
    end

    -- 怪物
    if isMonster(tile) then
        local m = MONSTER_DEF[tile]

        -- Boss 脉冲光环（移至所有格子绘制后单独叠加，避免被相邻格子背景遮挡）

        local spriteData = m.sprite and spriteImages[m.sprite]
        if spriteData then
            -- 使用精灵图渲染（带动画）
            local margin = s * 0.05
            local dw = s - margin * 2
            local dh = s - margin * 2
            local sy = (m.spriteRow or 0) * SPRITE_FRAME_H
            drawSpriteRegion(spriteData.handle, spriteData.w, spriteData.h,
                getAnimSX(), sy, SPRITE_FRAME_W, SPRITE_FRAME_H,
                x + margin, y + margin, dw, dh)
        else
            -- 精灵图未加载，回退到原始绘制
            local inner = s * 0.35
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, x + s / 2, y + s / 2, inner)
            nvgFillColor(nvgCtx, nvgRGBA(m.r, m.g, m.b, 255))
            nvgFill(nvgCtx)
            local fs = math.max(8, s * 0.35)
            local label = m.name:sub(1, 3)
            drawTextCenter(label, x + s / 2, y + s / 2, fs, 255, 255, 255)
        end
        -- 怪物技能名、预估伤害、临界值已隐藏（不在地图格子上显示）

        return
    end

    -- 被动技能道具
    if isSkill(tile) then
        local sk = SKILL_DEF[tile]
        local cx = x + s / 2
        local cy = y + s / 2

        -- 呼吸脉冲光晕（保留，增加存在感）
        local pulse = 0.6 + 0.4 * math.sin(animTimer * 4)
        local glowR = s * 0.4 + s * 0.06 * pulse
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, cx, cy, glowR)
        nvgFillColor(nvgCtx, nvgRGBA(sk.r, sk.g, sk.b, math.floor(30 * pulse)))
        nvgFill(nvgCtx)

        -- 直接显示完整图标（带边框）
        if not (sk.iconId and spr.drawIcon(sk.iconId, cx, cy, s * 0.75)) then
            drawTextCenter(sk.icon, cx, cy, math.max(10, s * 0.45), sk.r, sk.g, sk.b)
        end
        return
    end

    -- 宝石道具
    if isGem(tile) then
        local gemId = GEM_MAP_CHAR[tile]
        local gd = GEM_DEF[gemId]
        local cx = x + s / 2
        local cy = y + s / 2

        -- 呼吸光晕
        local pulse = 0.5 + 0.5 * math.sin(animTimer * 5)
        local glowR = s * 0.4 + s * 0.06 * pulse
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, cx, cy, glowR)
        nvgFillColor(nvgCtx, nvgRGBA(gd.r, gd.g, gd.b, math.floor(35 * pulse)))
        nvgFill(nvgCtx)

        -- 直接显示完整图标（带边框）
        if not (gd.iconId and spr.drawIcon(gd.iconId, cx, cy, s * 0.75)) then
            drawTextCenter(gd.icon, cx, cy, math.max(9, s * 0.4), 255, 255, 255)
        end
        return
    end

    -- 遗物道具
    if isRelic(tile) then
        local rl = RELIC_DEF[tile]
        local cx = x + s / 2
        local cy = y + s / 2
        local r2 = s * 0.38
        -- 旋转光晕
        local pulse = 0.5 + 0.5 * math.sin(animTimer * 3)
        local glowR = r2 + s * 0.1 * pulse
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, cx, cy, glowR)
        nvgFillColor(nvgCtx, nvgRGBA(rl.r, rl.g, rl.b, math.floor(50 * pulse)))
        nvgFill(nvgCtx)
        -- 遗物图标（完整边框）
        if not (rl.iconId and spr.drawIcon(rl.iconId, cx, cy, s * 0.75)) then
            drawTextCenter(rl.icon, cx, cy, math.max(10, s * 0.45), 255, 255, 255)
        end
        return
    end

    -- 物品（使用精灵图：第1行=红蓝绿宝石, 第2行=血瓶）
    if isItem(tile) then
        local itemDef = ITEM_DEF[tile]
        if itemDef and itemDef.sprite and spr.gemStones then
            -- 新宝石系列：使用 $2 (4).png 精灵图（4行3列）
            local margin = s * 0.05
            local dw = s - margin * 2
            local dh = s - margin * 2
            local gemCols = 3
            local gemFrameW = spr.gemStonesW / gemCols
            local gemFrameH = spr.gemStonesH / 4
            drawSpriteRegion(spr.gemStones, spr.gemStonesW, spr.gemStonesH,
                (itemDef.spriteCol or 0) * gemFrameW, (itemDef.spriteRow or 0) * gemFrameH,
                gemFrameW, gemFrameH,
                x + margin, y + margin, dw, dh)
        elseif spr.item then
            -- 血瓶/基础宝石：使用旧精灵图
            local itemFrameMap = {
                ["a"] = {col = 0, row = 0},  -- 攻击宝石 → 红宝石
                ["d"] = {col = 1, row = 0},  -- 防御宝石 → 蓝宝石
                ["h"] = {col = 0, row = 1},  -- 小血瓶
                ["H"] = {col = 1, row = 1},  -- 中血瓶
                ["z"] = {col = 2, row = 1},  -- 大血瓶
            }
            local frame = itemFrameMap[tile]
            if frame then
                local margin = s * 0.05
                local dw = s - margin * 2
                local dh = s - margin * 2
                drawSpriteRegion(spr.item, spr.itemW, spr.itemH,
                    frame.col * SPRITE_FRAME_W, frame.row * SPRITE_FRAME_H,
                    SPRITE_FRAME_W, SPRITE_FRAME_H,
                    x + margin, y + margin, dw, dh)
            end
        else
            -- 回退：精灵未加载时用简单色块+文字
            local item = ITEM_DEF[tile]
            local cx = x + s / 2
            local cy = y + s / 2
            if item.type == "hp" then
                drawRoundRect(x + pad + 2, y + pad + 2, s - pad * 2 - 4, s - pad * 2 - 4, 3, 220, 40, 50)
                drawTextCenter("HP", cx, cy, math.max(8, s * 0.3), 255, 255, 255)
            elseif item.type == "atk" then
                drawRoundRect(x + pad + 2, y + pad + 2, s - pad * 2 - 4, s - pad * 2 - 4, 3, 255, 140, 20)
                drawTextCenter("ATK", cx, cy, math.max(8, s * 0.25), 255, 255, 255)
            elseif item.type == "def" then
                drawRoundRect(x + pad + 2, y + pad + 2, s - pad * 2 - 4, s - pad * 2 - 4, 3, 50, 110, 255)
                drawTextCenter("DEF", cx, cy, math.max(8, s * 0.25), 255, 255, 255)
            end
        end
        return
    end

    -- 商人NPC
    if tile == SHOP_NPC_CHAR then
        local cx = x + s / 2
        local cy = y + s / 2
        local r2 = s * 0.40
        -- 呼吸光晕（金色）
        local pulse = 0.6 + 0.4 * math.sin(animTimer * 3)
        local glowR = r2 + s * 0.1 * pulse
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, cx, cy, glowR)
        nvgFillColor(nvgCtx, nvgRGBA(255, 200, 50, math.floor(35 * pulse)))
        nvgFill(nvgCtx)
        -- 底圆（深棕色）
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, cx, cy, r2)
        nvgFillColor(nvgCtx, nvgRGBA(60, 40, 20, 220))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 80, 200))
        nvgStrokeWidth(nvgCtx, math.max(1, s * 0.04))
        nvgStroke(nvgCtx)
        -- 金币图标
        drawTextCenter("\u{1FA99}", cx, cy - s * 0.05, math.max(12, s * 0.45), 255, 220, 80)
        -- 底部小标签
        local tagFs = math.max(7, s * 0.20)
        nvgFontSize(nvgCtx, tagFs)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvgCtx, nvgRGBA(255, 240, 180, 255))
        nvgText(nvgCtx, cx, y + s - 1, "\u{5546}\u{5E97}")
        return
    end

    -- 空地: 寻路路径高亮
    if #autoPath > 0 then
        for _, step in ipairs(autoPath) do
            if step[1] == row and step[2] == col then
                -- 半透明菱形标记
                local cx2 = x + s / 2
                local cy2 = y + s / 2
                local d = s * 0.15
                nvgBeginPath(nvgCtx)
                nvgMoveTo(nvgCtx, cx2, cy2 - d)
                nvgLineTo(nvgCtx, cx2 + d, cy2)
                nvgLineTo(nvgCtx, cx2, cy2 + d)
                nvgLineTo(nvgCtx, cx2 - d, cy2)
                nvgClosePath(nvgCtx)
                nvgFillColor(nvgCtx, nvgRGBA(100, 200, 255, 100))
                nvgFill(nvgCtx)
                break
            end
        end
    end
end

--- 绘制玩家
function drawPlayer()
    local s = cellSize

    -- 平滑移动: lerp 计算视觉位置
    local visualCol, visualRow
    if moveAnim.active then
        local p = math.min(moveAnim.t / MOVE_ANIM_DURATION, 1.0)
        -- ease-out: 开始快，结束慢
        local ep = 1 - (1 - p) * (1 - p)
        visualCol = moveAnim.fromCol + (player.col - moveAnim.fromCol) * ep
        visualRow = moveAnim.fromRow + (player.row - moveAnim.fromRow) * ep
    else
        visualCol = player.col
        visualRow = player.row
    end

    local x = gridX + (visualCol - 1) * cellSize
    local y = gridY + (visualRow - 1) * cellSize

    -- 四方向朝向: 根据 facing 选择精灵图行
    local facingSY = plSpr.oy + (plSpr.frow[player.facing] or 0) * plSpr.fh

    -- 移动中播放行走动画，静止时固定站立帧(列1)
    local sx
    if moveAnim.active then
        sx = getAnimSX()
    else
        sx = plSpr.ox + 1 * plSpr.fw  -- 站立帧(中间列)
    end

    if spr.player then
        local margin = s * 0.05
        local dw = s - margin * 2
        local dh = s - margin * 2
        drawSpriteRegion(spr.player, spr.playerW, spr.playerH,
            sx, facingSY, plSpr.fw, plSpr.fh,
            x + margin, y + margin, dw, dh)
    else
        -- 精灵图未加载，回退到原始绘制
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, x + s / 2, y + s / 2, s * 0.4)
        nvgFillColor(nvgCtx, nvgRGBA(70, 140, 255, 60))
        nvgFill(nvgCtx)
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, x + s / 2, y + s / 2, s * 0.3)
        nvgFillColor(nvgCtx, nvgRGBA(70, 140, 255, 255))
        nvgFill(nvgCtx)
        local fs = math.max(8, s * 0.35)
        drawTextCenter("勇", x + s / 2, y + s / 2, fs, 255, 255, 255)
    end
end

--- 绘制状态栏（三行布局）
function drawStats()
    -- 背景
    drawRoundRect(0, 0, logicalW, statsH, 0, 25, 22, 40, 240)

    local topPad = statsH * 0.08  -- 顶部留白，避免被刘海/状态栏遮挡
    local contentH = statsH - topPad
    local rowH = contentH / 3
    local fs = math.max(10, rowH * 0.52)
    local y1 = topPad + rowH / 2             -- 第一行垂直中心
    local y2 = topPad + rowH + rowH / 2      -- 第二行垂直中心
    local y3 = topPad + rowH * 2 + rowH / 2  -- 第三行垂直中心
    local pad = 8

    -- === 第一行: F楼层 + 功能按钮（菜单、牌组、怪物） ===
    drawTextLeft("F" .. player.floor, pad, y1, fs + 2, 200, 200, 255)

    -- 功能按钮（第一行右侧）
    local btnH1 = rowH * 0.7
    local btnY1 = y1 - btnH1 / 2
    local hbBtnW1 = fs * 2.5
    local hbBtnX1 = logicalW - hbBtnW1 - 6
    drawRoundRect(hbBtnX1, btnY1, hbBtnW1, btnH1, 4, 60, 60, 120, 200)
    drawTextCenter("怪物", hbBtnX1 + hbBtnW1 / 2, y1, fs * 0.8, 180, 200, 255)

    local cbBtnW1 = fs * 2.5
    local cbBtnX1 = hbBtnX1 - cbBtnW1 - 4
    drawRoundRect(cbBtnX1, btnY1, cbBtnW1, btnH1, 4, 100, 80, 40, 200)
    drawTextCenter("牌组", cbBtnX1 + cbBtnW1 / 2, y1, fs * 0.8, 255, 220, 120)

    local menuBtnW1 = fs * 2.5
    local menuBtnX1 = cbBtnX1 - menuBtnW1 - 4
    drawRoundRect(menuBtnX1, btnY1, menuBtnW1, btnH1, 4, 80, 70, 90, 200)
    drawTextCenter("菜单", menuBtnX1 + menuBtnW1 / 2, y1, fs * 0.8, 200, 200, 220)

    -- === 第二行: Lv HP ATK DEF EXP ===
    local lvX = pad
    drawTextLeft("Lv." .. player.level, lvX, y2, fs, 255, 220, 80)

    local hpX = lvX + fs * 2.8
    drawTextLeft("HP:" .. player.hp, hpX, y2, fs, 255, 100, 100)

    local atkX = hpX + fs * 5
    drawTextLeft("ATK:" .. player.atk, atkX, y2, fs, 255, 180, 50)

    local defX = atkX + fs * 4.2
    drawTextLeft("DEF:" .. player.def, defX, y2, fs, 100, 150, 255)

    -- 中毒层数显示
    if battle and (battle.playerPoison or 0) > 0 then
        local poisonX = defX + fs * 4.2
        drawTextLeft("毒:" .. battle.playerPoison, poisonX, y2, fs, 120, 200, 60)
    end

    -- 经验进度条（第二行末尾）
    local expNeeded = expToNextLevel(player.level)
    local expRatio = math.min(1, player.exp / math.max(1, expNeeded))
    local expStartX = defX + fs * 4.2
    local expFs = math.max(7, fs * 0.7)
    drawTextLeft("EXP:" .. player.exp .. "/" .. expNeeded, expStartX, y2 - fs * 0.15, expFs, 255, 220, 80)
    local expBarW = fs * 3.5
    local expBarH = math.max(3, rowH * 0.16)
    local expBarY = y2 + fs * 0.35
    drawRoundRect(expStartX, expBarY, expBarW, expBarH, 2, 40, 35, 60)
    drawRoundRect(expStartX, expBarY, expBarW * expRatio, expBarH, 2, 255, 220, 80)

    -- === 第三行: MP 抽牌 金币 钥匙(右对齐) ===
    local mpStartX = pad
    drawTextLeft("MP:" .. player.maxMp, mpStartX, y3, fs, 160, 120, 255)

    local drawX = mpStartX + fs * 3.5
    drawTextLeft("抽牌:" .. player.drawCount, drawX, y3, fs, 180, 220, 140)

    local goldX = drawX + fs * 4
    drawTextLeft("G:" .. player.gold, goldX, y3, fs, 255, 220, 50)

    -- 钥匙（右对齐，从右边缘往左排列）
    local keyIconSize = fs * 1.1
    local keyKeys = {
        { count = player.redKeys,    col = 2, r = 255, g = 60,  b = 60 },
        { count = player.blueKeys,   col = 1, r = 80,  g = 160, b = 255 },
        { count = player.yellowKeys, col = 0, r = 255, g = 220, b = 50 },
    }
    local kxRight = logicalW - pad
    for _, kk in ipairs(keyKeys) do
        local countStr = tostring(kk.count)
        nvgFontFace(nvgCtx, "sans")
        nvgFontSize(nvgCtx, fs * 0.85)
        local tw = nvgTextBounds(nvgCtx, 0, 0, countStr)
        kxRight = kxRight - tw
        drawTextLeft(countStr, kxRight, y3, fs * 0.85, kk.r, kk.g, kk.b)
        kxRight = kxRight - keyIconSize - 1
        if spr.key then
            drawSpriteRegion(spr.key, spr.keyW, spr.keyH,
                kk.col * SPRITE_FRAME_W, 0, SPRITE_FRAME_W, SPRITE_FRAME_H,
                kxRight, y3 - keyIconSize / 2, keyIconSize, keyIconSize)
        else
            drawRoundRect(kxRight, y3 - keyIconSize / 2, keyIconSize, keyIconSize, 2, kk.r, kk.g, kk.b, 180)
        end
        kxRight = kxRight - fs * 0.4
    end

    -- === 第四行: 被动技能 + 遗物（statsH下方） ===
    local y4 = statsH + rowH * 0.4
    local skIconSize = math.max(8, rowH * 0.55)
    local skillOrder = {"S", "V", "K", "T", "E", "Q"}
    local skStartX = pad
    local skIdx = 0
    relicDetail.skillRects = {}
    for _, ch in ipairs(skillOrder) do
        local sk = SKILL_DEF[ch]
        if sk and player.skills[sk.id] then
            local sx = skStartX + skIdx * (skIconSize + 3)
            if not (sk.iconId and spr.drawIcon(sk.iconId, sx + skIconSize / 2, y4, skIconSize)) then
                drawTextCenter(sk.icon, sx + skIconSize / 2, y4, skIconSize * 0.7, sk.r, sk.g, sk.b)
            end
            table.insert(relicDetail.skillRects, {x = sx, y = y4 - skIconSize * 0.5, w = skIconSize, h = skIconSize, key = ch})
            skIdx = skIdx + 1
        end
    end

    -- 遗物图标
    relicHudRects = {}
    local relicOrder = {"G"}
    local rlStartX = skStartX + skIdx * (skIconSize + 3)
    if skIdx > 0 then rlStartX = rlStartX + 4 end  -- 技能和遗物间加点间距
    for _, ch in ipairs(relicOrder) do
        local rl = RELIC_DEF[ch]
        if player.relics[rl.id] then
            local rx = rlStartX
            if not (rl.iconId and spr.drawIcon(rl.iconId, rx + skIconSize / 2, y4, skIconSize)) then
                drawTextCenter(rl.icon, rx + skIconSize / 2, y4, skIconSize * 0.7, rl.r, rl.g, rl.b)
            end
            table.insert(relicHudRects, {x = rx, y = y4 - skIconSize * 0.5, w = skIconSize, h = skIconSize, relicId = rl.id})
            rlStartX = rlStartX + skIconSize + 3
        end
    end

    -- （功能按钮已移到第一行绘制）
end

--- 绘制方向按钮
function drawDpad()
    local bs = dpadBtnSize
    local cx = dpadCenterX
    local cy = dpadCenterY
    local gap = bs * 0.1

    local ar = bs * 0.22  -- 箭头三角形半径

    -- 上
    local ux, uy = cx, cy - bs - gap
    drawRoundRect(ux - bs / 2, uy - bs / 2, bs, bs, 6, 80, 75, 110, 180)
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, ux, uy - ar)
    nvgLineTo(nvgCtx, ux - ar, uy + ar)
    nvgLineTo(nvgCtx, ux + ar, uy + ar)
    nvgClosePath(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 230, 255))
    nvgFill(nvgCtx)

    -- 下
    local dx, dy = cx, cy + gap + bs
    drawRoundRect(dx - bs / 2, dy - bs / 2, bs, bs, 6, 80, 75, 110, 180)
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, dx, dy + ar)
    nvgLineTo(nvgCtx, dx - ar, dy - ar)
    nvgLineTo(nvgCtx, dx + ar, dy - ar)
    nvgClosePath(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 230, 255))
    nvgFill(nvgCtx)

    -- 左
    local lx, ly = cx - bs - gap, cy
    drawRoundRect(lx - bs / 2, ly - bs / 2, bs, bs, 6, 80, 75, 110, 180)
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, lx - ar, ly)
    nvgLineTo(nvgCtx, lx + ar, ly - ar)
    nvgLineTo(nvgCtx, lx + ar, ly + ar)
    nvgClosePath(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 230, 255))
    nvgFill(nvgCtx)

    -- 右
    local rx, ry = cx + gap + bs, cy
    drawRoundRect(rx - bs / 2, ry - bs / 2, bs, bs, 6, 80, 75, 110, 180)
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, rx + ar, ry)
    nvgLineTo(nvgCtx, rx - ar, ry - ar)
    nvgLineTo(nvgCtx, rx - ar, ry + ar)
    nvgClosePath(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 230, 255))
    nvgFill(nvgCtx)
end

--- 绘制游戏界面底部 Game Jam 说明
function drawGameJamNote()
    local noteFs = math.max(8, math.min(12, logicalH * 0.018))
    local lineGap = noteFs * 1.15
    local noteY = logicalH - noteFs * 2.2
    local centerX = logicalW / 2

    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvgCtx, noteFs)
    nvgFillColor(nvgCtx, nvgRGBA(220, 190, 120, 155))
    nvgText(nvgCtx, centerX, noteY, "21天制造新星 GameJam 作品")
    nvgFontSize(nvgCtx, noteFs * 0.9)
    nvgFillColor(nvgCtx, nvgRGBA(160, 150, 130, 130))
    nvgText(nvgCtx, centerX, noteY + lineGap, "更多内容正在开发中，敬请期待")
end

--- 绘制消息
function drawMessage()
    if msg.timer <= 0 or msg.text == "" then return end

    local fs = math.max(12, cellSize * 0.45)
    local msgW = #msg.text * fs * 0.6 + 30
    local msgH = fs + 16
    local mx = (logicalW - msgW) / 2
    local my = gridY - msgH - 4

    -- 如果 my 太小，放在网格下方
    if my < statsH then
        my = gridY + cellSize * GRID + 4
    end

    -- 背景
    local alpha = math.min(220, math.floor(msg.timer * 200))
    drawRoundRect(mx, my, msgW, msgH, 6, 30, 28, 45, alpha)

    -- 文字
    drawTextCenter(msg.text, logicalW / 2, my + msgH / 2, fs,
        msg.color[1], msg.color[2], msg.color[3], math.min(255, math.floor(msg.timer * 250)))
end

--- 绘制怪物手册
function drawHandbook()
    if not handbookOpen then return end

    -- 收集当前楼层所有怪物类型（去重）
    local monsterSet = {}
    local monsterList = {}
    for r = 1, GRID do
        for c = 1, GRID do
            local tile = maps[player.floor][r][c]
            if isMonster(tile) and not monsterSet[tile] then
                monsterSet[tile] = true
                local m = MONSTER_DEF[tile]
                local result = calcCombat(tile)
                table.insert(monsterList, {
                    ch = tile,
                    name = m.name,
                    hp = getMonsterScaledHP(m), atk = getMonsterScaledATK(m), def = m.def, gold = m.gold,
                    sprite = m.sprite, spriteRow = m.spriteRow or 0,
                    skill = m.skill, boss = m.boss,
                    canWin = result.canWin,
                    hpLoss = result.hpLoss,
                    rounds = result.rounds,
                })
            end
        end
    end

    -- 按HP损失从低到高排序，不可战胜的排最后
    table.sort(monsterList, function(a, b)
        if a.canWin and not b.canWin then return true end
        if not a.canWin and b.canWin then return false end
        if a.canWin and b.canWin then return a.hpLoss < b.hpLoss end
        return a.hpLoss < b.hpLoss
    end)

    -- 面板尺寸
    local rowH = math.max(28, logicalH * 0.055)
    local titleH = rowH * 1.3
    local footerH = rowH * 0.8
    local itemH = rowH * 1.6  -- 每个怪物含技能描述
    local contentH = #monsterList * itemH
    local panelH = math.min(logicalH * 0.88, titleH + contentH + footerH + 16)
    local panelW = math.min(logicalW * 0.92, 380)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 全屏遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 150)

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 8, 30, 28, 50, 240)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 8)
    nvgStrokeColor(nvgCtx, nvgRGBA(120, 160, 240, 180))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 标题
    local titleFs = math.max(13, rowH * 0.55)
    drawTextCenter("怪物图鉴 - F" .. player.floor, px + panelW / 2, py + titleH / 2, titleFs, 220, 220, 255)

    -- 左上角MP显示（与战斗一致）
    local mpFs = math.max(9, titleFs * 0.65)
    local mpBarW = panelW * 0.2
    local mpBarH = math.max(4, titleH * 0.12)
    local mpBarX = px + 8
    local mpBarY = py + titleH - mpBarH - 4
    drawRoundRect(mpBarX, mpBarY, mpBarW, mpBarH, 2, 30, 30, 50)
    local mpFill = player.maxMp > 0 and math.max(0, player.mp / player.maxMp) or 0
    drawRoundRect(mpBarX, mpBarY, mpBarW * mpFill, mpBarH, 2, 80, 80, 220)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, mpFs)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(130, 130, 255, 255))
    nvgText(nvgCtx, mpBarX, mpBarY - mpFs * 0.6, "MP:" .. player.maxMp)

    -- 分隔线
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, px + 8, py + titleH)
    nvgLineTo(nvgCtx, px + panelW - 8, py + titleH)
    nvgStrokeColor(nvgCtx, nvgRGBA(100, 120, 180, 120))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 怪物列表（每个怪物两行：属性行 + 技能描述行）
    local fs = math.max(9, rowH * 0.38)
    local spriteSize = rowH * 0.8
    local startY = py + titleH + 4

    if #monsterList == 0 then
        drawTextCenter("当前楼层没有怪物", px + panelW / 2, startY + rowH / 2, fs, 150, 150, 150)
    else
        for i, info in ipairs(monsterList) do
            local ry = startY + (i - 1) * itemH
            if ry + itemH > py + panelH - footerH then break end  -- 超出面板

            -- 交替行背景
            if i % 2 == 0 then
                drawRoundRect(px + 4, ry, panelW - 8, itemH - 2, 3, 255, 255, 255, 10)
            end

            local cy = ry + rowH / 2

            -- 怪物精灵小图
            local spriteData = info.sprite and spriteImages[info.sprite]
            if spriteData then
                local sx = 0  -- 第一帧
                local sy = info.spriteRow * SPRITE_FRAME_H
                drawSpriteRegion(spriteData.handle, spriteData.w, spriteData.h,
                    sx, sy, SPRITE_FRAME_W, SPRITE_FRAME_H,
                    px + 8, ry + (rowH - spriteSize) / 2, spriteSize, spriteSize)
            end

            -- 名称 + 技能
            local nameX = px + 12 + spriteSize
            local nameStr = info.name
            if info.skill then
                nameStr = nameStr .. "[" .. info.skill.name .. "]"
            end
            nvgFontFace(nvgCtx, "sans")
            nvgFontSize(nvgCtx, fs)
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            if info.boss then
                nvgFillColor(nvgCtx, nvgRGBA(255, 80, 60, 255))
            else
                nvgFillColor(nvgCtx, nvgRGBA(230, 230, 240, 255))
            end
            nvgText(nvgCtx, nameX, cy, nameStr)

            -- 属性：HP/ATK/DEF
            local statX = px + panelW * 0.48
            local statFs = math.max(8, fs * 0.85)
            nvgFontSize(nvgCtx, statFs)

            nvgFillColor(nvgCtx, nvgRGBA(255, 120, 120, 255))
            nvgText(nvgCtx, statX, cy - statFs * 0.55, "HP:" .. info.hp)
            nvgFillColor(nvgCtx, nvgRGBA(255, 200, 80, 255))
            nvgText(nvgCtx, statX, cy + statFs * 0.55, "A:" .. info.atk .. " D:" .. info.def)

            -- 金币 + 预估HP损失
            local resultX = px + panelW * 0.78
            nvgFontSize(nvgCtx, statFs)
            nvgFillColor(nvgCtx, nvgRGBA(255, 220, 50, 255))
            nvgTextAlign(nvgCtx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgText(nvgCtx, resultX, cy - statFs * 0.55, "G:" .. info.gold)

            if info.canWin then
                if info.hpLoss == 0 then
                    nvgFillColor(nvgCtx, nvgRGBA(100, 255, 100, 255))
                    nvgText(nvgCtx, px + panelW - 10, cy + statFs * 0.55, "无伤")
                else
                    nvgFillColor(nvgCtx, nvgRGBA(255, 180, 80, 255))
                    nvgText(nvgCtx, px + panelW - 10, cy + statFs * 0.55, "-" .. info.hpLoss)
                end
            else
                nvgFillColor(nvgCtx, nvgRGBA(255, 60, 60, 255))
                nvgText(nvgCtx, px + panelW - 10, cy + statFs * 0.55, "无法战胜")
            end

            -- 技能描述行（第二行）
            local descY = ry + rowH + 2
            local descFs = math.max(8, fs * 0.8)
            nvgFontSize(nvgCtx, descFs)
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            if info.skill and info.skill.desc then
                nvgFillColor(nvgCtx, nvgRGBA(255, 180, 100, 180))
                nvgText(nvgCtx, px + 12 + spriteSize, descY, "技能: " .. info.skill.desc)
            else
                nvgFillColor(nvgCtx, nvgRGBA(120, 120, 140, 120))
                nvgText(nvgCtx, px + 12 + spriteSize, descY, "无特殊技能")
            end
        end
    end

    -- 底部提示
    local footFs = math.max(9, fs * 0.85)
    drawTextCenter("点击任意位置关闭", px + panelW / 2, py + panelH - footerH / 2, footFs, 150, 150, 180)
end

-- ============================================================
-- 卡牌图鉴
-- ============================================================

--- 获取战斗中卡牌的实际数值描述
--- 计算宝石修正后的伤害值（供描述/预览/HP条统一使用）
function applyGemDmg(baseDmg, gem)
    if gem == "flame" then return math.floor(baseDmg * 1.3) end
    return baseDmg
end

local function getCardBattleDesc(cardId, gem)
    if not battle.active then return nil end
    local ti = battle.targetIdx or getFirstAliveMonster()
    local pDmg, mHP, mMaxHP, baseMoDmg = 0, 0, 1, 0
    if ti then
        local mo = battle.monsters[ti]
        -- 破甲之力：预览也显示无视DEF的伤害
        if battle.armorStanceNext and CARD_DEF[cardId] and CARD_DEF[cardId].type == "attack" and cardId ~= "armorBreak" then
            local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
            pDmg = math.max(0, effAtk)
        else
            pDmg = math.max(0, mo.playerDmg)
        end
        mHP = mo.hp
        mMaxHP = mo.maxHP
        baseMoDmg = mo.baseDmg
    end
    -- 宝石修正攻击伤害
    local gDmg = applyGemDmg(pDmg, gem)
    local gDmg2 = battle.powerNext and (gDmg * 2) or gDmg
    local strikeDesc = "造成" .. gDmg2 .. "伤害"
    local cardDef = CARD_DEF[cardId]
    if battle.armorStanceNext and cardDef and cardDef.type == "attack" then
        local target = ti and battle.monsters[ti] or nil
        local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
        local armorDmg = math.max(0, effAtk)
        if target and target.effects and target.effects.vulnerable and target.effects.vulnerable > 0 then
            armorDmg = math.floor(armorDmg * 1.5)
        end
        local furyStacks = battle.fury or 0
        if furyStacks > 0 then armorDmg = math.floor(armorDmg * (1 + furyStacks * 0.1)) end
        armorDmg = applyGemDmg(armorDmg, gem)
        if battle.powerNext then armorDmg = armorDmg * 2 end
        strikeDesc = "造成" .. armorDmg .. "破甲伤害\n(破甲之力·无视DEF)"
    end
    local healAmt = math.floor(player.def * 0.5)
    if gem == "holy" then healAmt = math.floor(healAmt * 1.5) end
    local poisonTurns = 3
    local weakenTurns = 2
    local thunderDmg = player.level * 3
    local reflectPct = gem == "holy" and 75 or 50
    local descs = {
        strike  = strikeDesc,
        heal    = "回复" .. healAmt .. "点HP",
        guard   = "本回合伤害变为1" .. (gem == "holy" and "(反弹25%)" or ""),
        poison  = "全体敌人毒+5",
        venomBlade = gDmg2 .. "伤害 毒+3",
        shieldSlam = "造成" .. (battle.shieldHP or 0) .. "伤害(=当前护盾)",
        bloodRite = "-" .. math.floor(player.atk * 0.3) .. "HP +2MP",
        power   = "下次攻击x2(" .. (gDmg * 2) .. ")",
        drain   = "造成" .. gDmg2 .. "伤害并回复",
        weaken  = "全体ATK减半" .. weakenTurns .. "回合(→" .. math.floor(baseMoDmg / 2) .. ")",
        reflect = "受击反弹" .. reflectPct .. "%伤害",
        execute = (mHP <= mMaxHP * 0.2) and "可处决！一击必杀" or "HP>" .. math.floor(mMaxHP * 0.2) .. "时普攻" .. gDmg2,
        haste   = "连击2次共" .. (gDmg2 * 2) .. "伤害",
        thunder = "全体敌人受" .. thunderDmg .. "伤害",
        defend  = "护盾+" .. math.floor(player.def * 0.7) .. (gem == "holy" and "(圣光x1.5)" or ""),
        shield  = "护盾+" .. math.floor(player.def * 1.4) .. (gem == "holy" and "(圣光x1.5)" or ""),
        pierce  = "目标DEF归零(当前DEF:" .. (battle.monsters[battle.targetIdx] and battle.monsters[battle.targetIdx].def or 0) .. ")",
        firestorm = "全体敌人受70%基础伤害(共" .. (function()
            local total = 0
            for _, mo in ipairs(battle.monsters) do
                if mo.alive then total = total + math.max(0, math.floor(mo.playerDmg * 0.7)) end
            end
            if battle.powerNext then total = total * 2 end
            return total
        end)() .. ")",
        heavyStrike = "造成" .. math.floor(gDmg2 * 1.5) .. "伤害",
        cleave  = "造成" .. math.floor(gDmg2 * 1.5) .. "伤害 溅射" .. math.floor(gDmg2 * 1.5 * 0.5),
        ironWall = "护盾+" .. math.floor(player.def * 2.1) .. (gem == "holy" and "(圣光x1.5)" or ""),
        thorns  = "护盾+" .. math.floor(player.def * 0.7) .. " 反弹40%伤害2回合",
        deathDance = "全体随机3次 每次" .. math.floor(gDmg * 0.6) .. "伤害",
        oblivion = "造成目标" .. math.floor(mHP * 0.5) .. "伤害(50%当前HP)",
        immortal = "本回合无敌 回复" .. math.floor(battle.playerStartHP * 0.1) .. "HP",
        warCry  = "ATK+5 护盾+" .. (player.def * 2),
        atkShield = "护盾+" .. (player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)) .. (gem == "holy" and "(圣光x1.5)" or ""),
        cardDraw = "立即抽2张牌",
        armorBreak = "造成" .. (function()
            local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
            local d = math.max(0, effAtk)
            if gem == "flame" then d = math.floor(d * 1.3) end
            if battle.powerNext then d = d * 2 end
            return d
        end)() .. "破甲伤害",
        armorStance = "下次攻击转为破甲伤害(" .. (function()
            local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
            return math.max(0, effAtk)
        end)() .. "基础 无视DEF)",
        rend = "造成" .. math.floor(gDmg2 * 0.5) .. "伤害 易伤+2",
        bloodFrenzy = "-" .. math.max(1, math.floor((battle and battle.playerHP or 0) * 0.25)) .. "HP ATK+3 怒火+2 吸血20%",
        rampage = "连击3次 每次" .. math.floor(gDmg2 * 0.5) .. "伤害 击杀转移",
        savageBash = "造成" .. math.floor(gDmg2 * 0.6) .. "伤害 怒火+1",
        roar = "怒火+2 抽1张牌",
        furyCleave = "造成" .. (((battle.fury or 0) >= 3) and math.floor(gDmg2 * 1.2) or math.floor(gDmg2 * 0.8)) .. "伤害" .. (((battle.fury or 0) >= 3) and "(怒火≥3!)" or "(怒火<3)"),
        battleCry = "怒火+1 全体易伤+1回合",
        toughHide = "护盾+" .. math.max(1, math.floor((player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)) * 0.5)) .. (gem == "holy" and "(圣光x1.5)" or "") .. " 怒火+1",
        berserkerRage = "易伤(受伤+30%) 怒火+3",
        groundSlam = "全体80%伤害 各+1易伤",
        furyBurst = "消耗" .. (battle.fury or 0) .. "层怒火 造成" .. ((battle.fury or 0) > 0 and math.floor(gDmg2 * (battle.fury or 0) * 0.4 / (1 + (battle.fury or 0) * 0.1)) or 0) .. "伤害",
        undying = "本回合HP不低于1 怒火+2",
        bloodScent = "击杀时怒火+3并回复10HP，持续3回合",
        titanGrip = "造成" .. math.floor(gDmg2 * 2.0) .. "伤害 下回合无法攻击",
        warpath = "怒火+5 ATK+2 抽2张牌",
        handBlast = "弃" .. (#(battle and battle.hand or {}) - 1) .. "张牌 每张" .. math.floor(gDmg2 * 0.5) .. "伤害(共" .. math.floor(gDmg2 * 0.5) * math.max(0, #(battle and battle.hand or {}) - 1) .. ")",
    }
    local result = descs[cardId]
    -- 雷霆石：单体攻击卡追加溅射描述
    local singleAtkCards = {strike=true, drain=true, execute=true, haste=true, heavyStrike=true, cleave=true, oblivion=true, armorBreak=true, rend=true, savageBash=true, furyCleave=true, furyBurst=true, titanGrip=true}
    if gem == "thunder" and result and singleAtkCards[cardId] then
        local splashBase = gDmg2
        if cardId == "haste" then splashBase = gDmg2 * 2
        elseif cardId == "heavyStrike" or cardId == "cleave" then splashBase = math.floor(gDmg2 * 1.5)
        elseif cardId == "oblivion" then splashBase = math.floor(mHP * 0.5)
        elseif cardId == "armorBreak" then
            local effAtk = player.atk + (battle.warCryAtk or 0) + (battle.frenzyAtk or 0) - (battle.curseAtkLoss or 0)
            splashBase = math.max(0, effAtk)
            if gem == "flame" then splashBase = math.floor(splashBase * 1.3) end
            if battle.powerNext then splashBase = splashBase * 2 end
        elseif cardId == "rend" then splashBase = math.floor(gDmg2 * 0.5)
        end
        result = result .. " ⚡溅射" .. math.max(1, math.floor(splashBase * 0.2))
    end
    -- 汲取石通用后缀
    if gem == "draw" and result then
        result = result .. " +抽1张"
    end
    return result
end

--- 卡牌符号图标
local CARD_ICON = {
    strike = "⚔", heal = "✚", guard = "🛡", defend = "🛡", shield = "🛡", poison = "☠",
    power = "⚡", drain = "💜", weaken = "▼", reflect = "◇",
    execute = "☠", haste = "»", thunder = "⚡", firestorm = "🔥",
    thrifty = "💰", meditate = "🧘", pierce = "🔓",
    heavyStrike = "⚔", bladestorm = "🌀",
    soulBurn = "🔥", handBlast = "👊", devour = "👁", convert = "♻",
    cleave = "⚔", ironWall = "🛡", thorns = "🌿",
    atkShield = "🛡", cardDraw = "📋",
    deathDance = "💀", oblivion = "🌀", immortal = "✦", warCry = "📯",
    venomBlade = "🗡", shieldSlam = "🛡", bloodRite = "🩸",
    armorBreak = "⚔", armorStance = "🔓", rend = "💢",
    bloodFrenzy = "🩸", rampage = "💥",
    savageBash = "💥", roar = "🔥",
    furyCleave = "⚔", battleCry = "📢", toughHide = "🛡", berserkerRage = "😤",
    groundSlam = "💥", furyBurst = "💢", undying = "💪", bloodScent = "👃",
    titanGrip = "🪓", warpath = "🔥",
    wound = "💀", curse = "☠",
    hp50 = "❤", hp100 = "❤", hp300 = "❤",
    atk1 = "💎", atk2 = "💎", atk3 = "💎", atk4 = "💎", atk5 = "💎", atk8 = "💎", atk15 = "💎",
    def1 = "💎", def2 = "💎", def3 = "💎", def4 = "💎", def5 = "💎", def8 = "💎", def15 = "💎",
}

-- 卡牌图标 → IconSet映射 (cardId → iconSetId)
-- 没有专属卡面图的卡牌用 IconSet 替代 emoji
local CARD_ICONSET_MAP = {
    strike = "icon_atk", heal = "icon_hp", guard = "status_shield", defend = "status_shield",
    shield = "status_shield", poison = "status_poison", power = "status_power",
    drain = "skill_vampire", weaken = "status_weaken", reflect = "status_reflect",
    execute = "skill_execute", haste = "status_power", thunder = "gem_thunder",
    firestorm = "status_burn", thrifty = "icon_gold", meditate = "skill_meditate",
    pierce = "status_vulnerable", heavyStrike = "icon_atk", bladestorm = "status_berserk",
    soulBurn = "status_burn", handBlast = "status_berserk", devour = "status_curse",
    convert = "gem_echo", cleave = "icon_atk", ironWall = "skill_thorn_armor",
    thorns = "status_thorns", atkShield = "status_shield", cardDraw = "icon_card",
    deathDance = "status_curse", oblivion = "status_curse", immortal = "status_immortal",
    warCry = "status_berserk", venomBlade = "status_poison", shieldSlam = "status_shield",
    bloodRite = "gem_blood", armorBreak = "icon_atk", armorStance = "status_vulnerable",
    rend = "status_vulnerable", bloodFrenzy = "gem_blood", rampage = "status_berserk",
    savageBash = "status_berserk", roar = "status_burn", furyCleave = "icon_atk",
    battleCry = "status_berserk", toughHide = "skill_thorn_armor", berserkerRage = "status_berserk",
    groundSlam = "status_berserk", furyBurst = "status_berserk", undying = "status_undying",
    bloodScent = "status_blood_scent", titanGrip = "skill_execute", warpath = "status_burn",
    wound = "status_curse", curse = "status_curse",
    hp50 = "icon_hp", hp100 = "icon_hp", hp300 = "icon_hp",
    atk1 = "icon_atk", atk2 = "icon_atk", atk3 = "icon_atk", atk4 = "icon_atk", atk5 = "icon_atk", atk8 = "icon_atk", atk15 = "icon_atk",
    def1 = "icon_def", def2 = "icon_def", def3 = "icon_def", def4 = "icon_def", def5 = "icon_def", def8 = "icon_def", def15 = "icon_def",
}

--- 关键词解释表（从 assets/data/glossary.json 加载，方便修改）
KEYWORD_GLOSSARY = {}
do
    local file = cache:GetFile("data/glossary.json")
    if file then
        local str = file:ReadString()
        file:Close()
        local ok, data = pcall(_cjson.decode, str)
        if ok and type(data) == "table" then
            KEYWORD_GLOSSARY = data
            log:Write(LOG_INFO, "[Glossary] 已从 glossary.json 加载 " .. #data .. " 条关键词")
        else
            log:Write(LOG_WARNING, "[Glossary] glossary.json 解析失败，使用空表")
        end
    else
        log:Write(LOG_WARNING, "[Glossary] 未找到 data/glossary.json")
    end
end

--- 收集卡牌的关键词提示
function collectKeywordTips(cdef)
    local tips = {}
    local seen = {}
    for _, entry in ipairs(KEYWORD_GLOSSARY) do
        if not seen[entry.kw] and string.find(cdef.desc, entry.kw, 1, true) then
            table.insert(tips, entry.tip)
            seen[entry.kw] = true
        end
    end
    if cdef.cardType == "limited" and not seen["消耗"] then
        table.insert(tips, "消耗：本场战斗限用" .. (cdef.maxUses or 1) .. "次")
    end
    if cdef.cardType == "consumable" and not seen["销毁"] then
        table.insert(tips, "销毁：使用后永久从牌组中移除")
    end
    return tips
end

-- 属性宝石卡牌使用与地图物品一致的素材：+1 用旧物品图，+2/+4/+8/+15 用新版宝石图
local CARD_ITEM_SPRITE_MAP = {
    atk2 = {sheet = "gemStones", col = 0, row = 0},
    atk3 = {sheet = "gemStones", col = 0, row = 2},
    atk4 = {sheet = "gemStones", col = 0, row = 2},
    atk5 = {sheet = "gemStones", col = 0, row = 3},
    atk8 = {sheet = "gemStones", col = 0, row = 3},
    atk15 = {sheet = "gemStones", col = 0, row = 1},
    def2 = {sheet = "gemStones", col = 1, row = 0},
    def3 = {sheet = "gemStones", col = 1, row = 2},
    def4 = {sheet = "gemStones", col = 1, row = 2},
    def5 = {sheet = "gemStones", col = 1, row = 3},
    def8 = {sheet = "gemStones", col = 1, row = 3},
    def15 = {sheet = "gemStones", col = 1, row = 1},
}

local function drawCardItemSprite(cardId, def, dx, dy, dw, dh)
    local override = CARD_ITEM_SPRITE_MAP[cardId]
    if override and override.sheet == "gemStones" and spr.gemStones then
        local gemFrameW = spr.gemStonesW / 3
        local gemFrameH = spr.gemStonesH / 4
        drawSpriteRegion(spr.gemStones, spr.gemStonesW, spr.gemStonesH,
            override.col * gemFrameW, override.row * gemFrameH,
            gemFrameW, gemFrameH,
            dx, dy, dw, dh)
        return true
    end
    if def.spriteFrame and spr.item then
        local frame = def.spriteFrame
        drawSpriteRegion(spr.item, spr.itemW, spr.itemH,
            frame.col * SPRITE_FRAME_W, frame.row * SPRITE_FRAME_H,
            SPRITE_FRAME_W, SPRITE_FRAME_H,
            dx, dy, dw, dh)
        return true
    end
    return false
end

--- 绘制关键词解释框（卡牌右侧）
--- @param tips string[] 关键词提示列表
--- @param boxX number 框左上角X，anchorRight=true 时为右边界
--- @param boxY number 框顶部Y，anchorBottom=true 时为底边界
--- @param maxW number 最大宽度
--- @param fontSize number 字体大小
function drawKeywordGlossary(tips, boxX, boxY, maxW, fontSize, anchorBottom, anchorRight)
    if #tips == 0 then return end
    local padX, padY = 8, 6
    local textW = maxW - padX * 2
    if textW < 20 then return end
    -- 先设置字体参数用于测量
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, fontSize)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    -- 计算每条 tip 的换行高度
    local totalH = 0
    local tipHeights = {}
    for i, tip in ipairs(tips) do
        local bounds = nvgTextBoxBounds(nvgCtx, 0, 0, textW, tip)
        local h = bounds[4] - bounds[2]
        tipHeights[i] = h
        totalH = totalH + h
    end
    local gapH = fontSize * 0.4  -- 条目间距
    local boxH = padY * 2 + totalH + gapH * (#tips - 1)
    local boxW = maxW
    if anchorRight then
        boxX = boxX - boxW
    end
    -- anchorBottom模式：boxY为底边，向上绘制
    if anchorBottom then
        boxY = math.max(4, boxY - boxH)
    end
    -- 背景
    drawRoundRect(boxX, boxY, boxW, boxH, 6, 20, 22, 45, 220)
    -- 边框
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, boxX, boxY, boxW, boxH, 6)
    nvgStrokeColor(nvgCtx, nvgRGBA(120, 140, 200, 160))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)
    -- 文本（使用 nvgTextBox 自动换行）
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, fontSize)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(200, 215, 240, 230))
    local curY = boxY + padY
    for i, tip in ipairs(tips) do
        nvgTextBox(nvgCtx, boxX + padX, curY, textW, tip)
        curY = curY + tipHeights[i] + gapH
    end
end

--- 查找描述文本中所有glossary关键词的字符索引集合
function findKeywordCharIndices(descText)
    local kwSet = {}
    for _, entry in ipairs(KEYWORD_GLOSSARY) do
        local kw = entry.kw
        local searchStart = 1
        while true do
            local bytePos = string.find(descText, kw, searchStart, true)
            if not bytePos then break end
            -- 用utf8.len计算bytePos前有多少个字符
            local charsBefore = 0
            if bytePos > 1 then
                charsBefore = utf8.len(descText, 1, bytePos - 1) or 0
            end
            local kwCharLen = utf8.len(kw) or 0
            for ci = charsBefore + 1, charsBefore + kwCharLen do
                kwSet[ci] = true
            end
            searchStart = bytePos + #kw
        end
    end
    return kwSet
end

--- 统一绘制单张卡牌
function drawCard(x, y, w, h, cardInfo, isSelected, isDragging)
    local def = CARD_DEF[cardInfo.id]
    if not def then return end

    -- 卡框PNG有透明边距，布局传入的是"可见区域"尺寸
    -- 渲染时扩展回PNG完整尺寸，让透明边距溢出到布局边界外
    local frameOverX = 0.14  -- 横向每侧溢出比例
    local frameOverY = 0.11  -- 纵向每侧溢出比例
    local overX = w * frameOverX
    local overY = h * frameOverY
    x = x - overX
    y = y - overY
    w = w + overX * 2
    h = h + overY * 2

    local cardCost = getCardCost(cardInfo)
    local isUsable = (not battle.active) or (battle.mp >= cardCost and not def.unplayable)
    local alpha = 255
    local pad = math.max(1, w * 0.03)

    -- 稀有度颜色
    local rarityDef = RARITY_DEF[def.rarity or (def.type == "curse" and "curse") or "common"]
    local rr, rg, rb = rarityDef and rarityDef.r or 180, rarityDef and rarityDef.g or 180, rarityDef and rarityDef.b or 180

    -- 卡牌框图片布局比例（始终使用 cardDev.p 中的值）
    local cdp = cardDev.p
    local nameRatioTop = cdp.nameTop
    local nameRatioBot = cdp.nameBot
    local imgRatioTop  = cdp.imgTop
    local imgRatioBot  = cdp.imgBot
    local descRatioTop = cdp.descTop
    local descRatioBot = cdp.descBot

    local hasFrame = spr.cardFrame ~= nil

    -- 保存状态（不再裁剪，依赖外层容器的 scissor 处理溢出）
    nvgSave(nvgCtx)

    if hasFrame then
        -- ========== 层1：卡牌插画（底层，在图片窗口区域内） ==========
        local imgMarginX = cdp.imgMarginX
        local imgOffX = w * cdp.imgOffX
        local imgWinY = y + h * imgRatioTop
        local imgWinH = h * (imgRatioBot - imgRatioTop)
        local imgWinX = x + w * imgMarginX + imgOffX
        local imgWinW = w * (1 - imgMarginX * 2)

        local cimg = cardImages[cardInfo.id]
        if cimg then
            local scaleX = imgWinW / cimg.w
            local scaleY = imgWinH / cimg.h
            local sc = math.max(scaleX, scaleY)
            local drawW = cimg.w * sc
            local drawH = cimg.h * sc
            local ox = imgWinX - (drawW - imgWinW) / 2
            local oy = imgWinY - (drawH - imgWinH) / 2
            local imgPaint = nvgImagePattern(nvgCtx, ox, oy, drawW, drawH, 0, cimg.handle, 1.0)
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, imgWinX, imgWinY, imgWinW, imgWinH)
            nvgFillPaint(nvgCtx, imgPaint)
            nvgFill(nvgCtx)
        elseif def.spriteFrame and (spr.item or spr.gemStones) then
            -- 物品卡背景图（先画底图再画精灵，裁剪在imgWin内）
            nvgSave(nvgCtx)
            nvgIntersectScissor(nvgCtx, imgWinX, imgWinY, imgWinW, imgWinH)
            if spr.itemBg then
                local bgScX = imgWinW / spr.itemBgW
                local bgScY = imgWinH / spr.itemBgH
                local bgSc = math.max(bgScX, bgScY)
                local bgDW = spr.itemBgW * bgSc
                local bgDH = spr.itemBgH * bgSc
                local bgOX = imgWinX - (bgDW - imgWinW) / 2
                local bgOY = imgWinY - (bgDH - imgWinH) / 2
                local bgPaint = nvgImagePattern(nvgCtx, bgOX, bgOY, bgDW, bgDH, 0, spr.itemBg, 1.0)
                nvgBeginPath(nvgCtx)
                nvgRect(nvgCtx, imgWinX, imgWinY, imgWinW, imgWinH)
                nvgFillPaint(nvgCtx, bgPaint)
                nvgFill(nvgCtx)
            end
            local spriteSize = imgWinH - pad * 2
            local spriteX = imgWinX + (imgWinW - spriteSize) / 2
            drawCardItemSprite(cardInfo.id, def, spriteX, imgWinY + pad, spriteSize, spriteSize)
            nvgRestore(nvgCtx)
        else
            -- 优先用 IconSet 图标替代 emoji（裁剪在imgWin内）
            nvgSave(nvgCtx)
            nvgIntersectScissor(nvgCtx, imgWinX, imgWinY, imgWinW, imgWinH)
            local iconFs = math.max(12, imgWinH * 0.55)
            local iconSetId = CARD_ICONSET_MAP[cardInfo.id]
            if not (iconSetId and spr.drawIcon(iconSetId, x + w / 2, imgWinY + imgWinH / 2, iconFs)) then
                local icon = CARD_ICON[cardInfo.id] or "?"
                drawTextCenter(icon, x + w / 2, imgWinY + imgWinH / 2, iconFs, def.r, def.g, def.b, 200)
            end
            nvgRestore(nvgCtx)
        end

        -- ========== 层2：卡牌框图片（覆盖在插画上方） ==========
        local framePaint = nvgImagePattern(nvgCtx, x, y, w, h, 0, spr.cardFrame, 1.0)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, x, y, w, h, 4)
        nvgFillPaint(nvgCtx, framePaint)
        nvgFill(nvgCtx)

        -- ========== 层3：名称文字（在名称横幅区域，始终居中） ==========
        local nameBarCenterY = y + h * (nameRatioTop + nameRatioBot) / 2
        local nameBarH = h * (nameRatioBot - nameRatioTop)
        local nameOffX = w * cdp.nameOffX
        local nameCenterX = x + w / 2 + nameOffX
        local nameAvailW = w * (1 - imgMarginX * 2)
        local nameFs = math.max(8, nameBarH * 0.7)
        -- 名字超过4个字符时缩小字号
        local nameCharCount = utf8.len(def.name) or #def.name
        if nameCharCount > 4 then
            nameFs = math.max(6, nameFs * 4 / nameCharCount)
        end
        nvgFontFace(nvgCtx, "sans")
        nvgFontSize(nvgCtx, nameFs)
        local nameTextW = nvgTextBounds(nvgCtx, 0, 0, def.name)
        if nameTextW > nameAvailW * 0.9 and nameAvailW > 0 then
            nameFs = math.max(6, nameFs * (nameAvailW * 0.9) / nameTextW)
        end
        local nameR, nameG, nameB
        if (def.rarity or "common") == "common" then
            nameR, nameG, nameB = 255, 255, 255  -- 普通卡：白色
        else
            -- 其他稀有度：更亮的颜色（原色混合白色）
            nameR = math.min(255, math.floor(rr * 0.6 + 255 * 0.4))
            nameG = math.min(255, math.floor(rg * 0.6 + 255 * 0.4))
            nameB = math.min(255, math.floor(rb * 0.6 + 255 * 0.4))
        end
        -- 灰色描边
        local strokeOff = math.max(1, nameFs * 0.06)
        nvgFontFace(nvgCtx, "sans")
        nvgFontSize(nvgCtx, nameFs)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(80, 80, 80, alpha))
        for _, off in ipairs({{-strokeOff,0},{strokeOff,0},{0,-strokeOff},{0,strokeOff}}) do
            nvgText(nvgCtx, nameCenterX + off[1], nameBarCenterY + off[2], def.name)
        end
        -- 主文字
        drawTextCenter(def.name, nameCenterX, nameBarCenterY, nameFs, nameR, nameG, nameB, alpha)

        -- ========== 层4：描述区文字 ==========
        local descTop = y + h * descRatioTop
        local descBot = y + h * descRatioBot
        local descH = descBot - descTop
        local descText = getCardBattleDesc(cardInfo.id, cardInfo.gem) or def.desc
        if cardInfo.gem and GEM_DEF[cardInfo.gem] then
            local gd = GEM_DEF[cardInfo.gem]
            descText = descText .. "\n" .. gd.icon .. gd.desc
        end
        -- 卡牌类型标签追加到描述末尾
        local destroyStart = -1  -- "销毁"/"不可打出"起始字符索引（用于红色渲染）
        if def.unplayable then
            local charCount = 0
            for _ in utf8.codes(descText) do charCount = charCount + 1 end
            destroyStart = charCount + 2
            descText = descText .. "\n不可打出"
        elseif def.cardType == "consumable" then
            -- 计算"销毁"在descText中的字符位置（换行符+销毁 = 倒数第3个字符起）
            local charCount = 0
            for _ in utf8.codes(descText) do charCount = charCount + 1 end
            destroyStart = charCount + 2  -- +1换行符, +2起"销"
            descText = descText .. "\n销毁"
        elseif def.cardType == "limited" then
            local remaining = def.maxUses
            if cardInfo.usesLeft ~= nil then
                remaining = math.max(0, cardInfo.usesLeft)
            end
            descText = descText .. "\n消耗" .. remaining
        end
        local descPadX = cdp.descPadX
        local descOffX = w * cdp.descOffX
        local descPad = w * descPadX
        local descMaxFs = math.max(5, h * 0.075)
        local descMinFs = math.max(4, h * 0.04)
        local descAvailH = descH - pad * 2
        local descBoxW = w - descPad * 2
        local descFs = descMaxFs
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        while descFs > descMinFs do
            nvgFontSize(nvgCtx, descFs)
            local bounds = nvgTextBoxBounds(nvgCtx, 0, 0, descBoxW, descText)
            local textH = bounds[4] - bounds[2]
            if textH <= descAvailH then break end
            descFs = descFs - 0.5
        end
        nvgFontSize(nvgCtx, descFs)
        local normalClr = nvgRGBA(50, 40, 30, alpha)
        local numClr = nvgRGBA(180, 50, 30, alpha)
        local destroyClr = nvgRGBA(200, 40, 40, alpha)
        local kwIndices = findKeywordCharIndices(descText)
        local descDrawX = x + descPad + descOffX
        local descDrawY = descTop + pad
        local lineH = descFs * 1.2
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFontSize(nvgCtx, descFs)
        local curX = descDrawX
        local curY = descDrawY
        local charIdx = 0
        for _, cp in utf8.codes(descText) do
            charIdx = charIdx + 1
            local ch = utf8.char(cp)
            if ch == "\n" then
                curX = descDrawX
                curY = curY + lineH
            else
                local chW = nvgTextBounds(nvgCtx, 0, 0, ch)
                if curX + chW > descDrawX + descBoxW and curX > descDrawX then
                    curX = descDrawX
                    curY = curY + lineH
                end
                local isNum = (cp >= 0x30 and cp <= 0x39) or cp == 0x25 or cp == 0x2E or cp == 0xD7
                local clr = normalClr
                if destroyStart > 0 and charIdx >= destroyStart then
                    clr = destroyClr
                elseif isNum then
                    clr = numClr
                end
                nvgFillColor(nvgCtx, clr)
                nvgText(nvgCtx, curX, curY, ch)
                curX = curX + chW
            end
        end
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)



        -- ========== 层5：费用宝石图片（左上角） ==========
        local manaGemSize = h * cdp.manaSize
        local manaOffX = cdp.manaX
        local manaOffY = cdp.manaY
        if cardCost >= 0 and cardCost <= 5 and spr.manaGems[cardCost] then
            local gem = spr.manaGems[cardCost]
            local gemDrawSize = manaGemSize
            local gemX = x + w * manaOffX
            local gemY = y + h * manaOffY
            local gemPaint = nvgImagePattern(nvgCtx, gemX, gemY, gemDrawSize, gemDrawSize, 0, gem.handle, 1.0)
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, gemX, gemY, gemDrawSize, gemDrawSize)
            nvgFillPaint(nvgCtx, gemPaint)
            nvgFill(nvgCtx)
        elseif cardCost > 5 then
            -- 费用超过5，退回NanoVG绘制
            local mpFs = math.max(7, h * 0.13)
            local mpR = mpFs * 0.55
            local mpX2 = x + pad + mpR + w * 0.01
            local mpY2 = y + pad + mpR + h * 0.015
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, mpX2, mpY2, mpR)
            nvgFillColor(nvgCtx, nvgRGBA(30, 50, 160, 230))
            nvgFill(nvgCtx)
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, mpX2, mpY2, mpR)
            nvgStrokeColor(nvgCtx, nvgRGBA(100, 140, 255, 180))
            nvgStrokeWidth(nvgCtx, 1)
            nvgStroke(nvgCtx)
            drawTextCenter(tostring(cardCost), mpX2, mpY2, mpFs * 0.7, 200, 220, 255, alpha)
        end

        -- ========== 层6：宝石图标（右上角，避开左上费用宝石） ==========
        if cardInfo.gem and GEM_DEF[cardInfo.gem] then
            local gd = GEM_DEF[cardInfo.gem]
            local gemFs = math.max(8, h * 0.13)
            local gemIconX = x + w - pad - gemFs * 0.15
            local gemIconY = y + pad + gemFs * 0.15
            if not (gd.iconId and spr.drawIcon(gd.iconId, gemIconX, gemIconY, gemFs * 0.85)) then
                drawTextCenter(gd.icon, gemIconX, gemIconY, gemFs * 0.8, gd.r, gd.g, gd.b, alpha)
            end
        end

    else
        -- ========== 无卡牌框时退回旧绘制逻辑 ==========
        local bgR, bgG, bgB = 40, 38, 60
        if isSelected then bgR, bgG, bgB = 55, 50, 80 end
        if isDragging then bgR, bgG, bgB = 65, 60, 90 end
        drawRoundRect(x, y, w, h, 5, bgR, bgG, bgB, alpha)

        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, x, y, w, h, 5)
        if isSelected then
            nvgStrokeColor(nvgCtx, nvgRGBA(rr, rg, rb, 255))
            nvgStrokeWidth(nvgCtx, 2.5)
        else
            nvgStrokeColor(nvgCtx, nvgRGBA(rr, rg, rb, 180))
            nvgStrokeWidth(nvgCtx, 1.5)
        end
        nvgStroke(nvgCtx)

        local nameBarH = h * 0.18
        local mpBadgeW = 0
        if cardCost > 0 then
            local mpFs2 = math.max(7, h * 0.13)
            mpBadgeW = mpFs2 * 1.1
        end
        local nameAvailW = w - pad * 2 - mpBadgeW
        local nameCenterX = x + pad + mpBadgeW + nameAvailW / 2
        local nameFs = math.max(8, nameBarH * 0.75)
        -- 名字超过4个字符时缩小字号
        local nameCharCount2 = utf8.len(def.name) or #def.name
        if nameCharCount2 > 4 then
            nameFs = math.max(6, nameFs * 4 / nameCharCount2)
        end
        nvgFontFace(nvgCtx, "sans")
        nvgFontSize(nvgCtx, nameFs)
        local nameTextW = nvgTextBounds(nvgCtx, 0, 0, def.name)
        if nameTextW > nameAvailW * 0.9 and nameAvailW > 0 then
            nameFs = math.max(6, nameFs * (nameAvailW * 0.9) / nameTextW)
        end
        drawTextCenter(def.name, nameCenterX, y + pad + nameBarH / 2, nameFs, rr, rg, rb, alpha)

        local iconTop = y + pad + nameBarH + pad * 0.5
        local iconH = h * 0.38
        drawRoundRect(x + pad, iconTop, w - pad * 2, iconH, 3, rr, rg, rb, 35)
        local cimg = cardImages[cardInfo.id]
        if cimg then
            local iconAreaW = w - pad * 2
            local scaleX = iconAreaW / cimg.w
            local scaleY = iconH / cimg.h
            local sc = math.max(scaleX, scaleY)
            local drawW = cimg.w * sc
            local drawH = cimg.h * sc
            local ox = x + pad - (drawW - iconAreaW) / 2
            local oy = iconTop - (drawH - iconH) / 2
            local imgPaint = nvgImagePattern(nvgCtx, ox, oy, drawW, drawH, 0, cimg.handle, 1.0)
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, x + pad, iconTop, iconAreaW, iconH, 3)
            nvgFillPaint(nvgCtx, imgPaint)
            nvgFill(nvgCtx)
        elseif def.spriteFrame and (spr.item or spr.gemStones) then
            -- 物品卡背景图
            if spr.itemBg then
                local iconAreaW2 = w - pad * 2
                local bgScX2 = iconAreaW2 / spr.itemBgW
                local bgScY2 = iconH / spr.itemBgH
                local bgSc2 = math.max(bgScX2, bgScY2)
                local bgDW2 = spr.itemBgW * bgSc2
                local bgDH2 = spr.itemBgH * bgSc2
                local bgOX2 = x + pad - (bgDW2 - iconAreaW2) / 2
                local bgOY2 = iconTop - (bgDH2 - iconH) / 2
                local bgPaint2 = nvgImagePattern(nvgCtx, bgOX2, bgOY2, bgDW2, bgDH2, 0, spr.itemBg, 1.0)
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, x + pad, iconTop, iconAreaW2, iconH, 3)
                nvgFillPaint(nvgCtx, bgPaint2)
                nvgFill(nvgCtx)
            end
            local iconAreaW = w - pad * 2
            local spriteSize = iconH - pad * 2
            local spriteX = x + pad + (iconAreaW - spriteSize) / 2
            drawCardItemSprite(cardInfo.id, def, spriteX, iconTop + pad, spriteSize, spriteSize)
        else
            local iconFs = math.max(12, iconH * 0.55)
            local iconSetId = CARD_ICONSET_MAP[cardInfo.id]
            if not (iconSetId and spr.drawIcon(iconSetId, x + w / 2, iconTop + iconH / 2, iconFs)) then
                local icon = CARD_ICON[cardInfo.id] or "?"
                drawTextCenter(icon, x + w / 2, iconTop + iconH / 2, iconFs, def.r, def.g, def.b, 200)
            end
        end

        local descTop = iconTop + iconH + pad * 0.5
        local descH = y + h - descTop - pad
        drawRoundRect(x + pad, descTop, w - pad * 2, descH, 3, 50, 48, 70, 200)
        local descText = getCardBattleDesc(cardInfo.id, cardInfo.gem) or def.desc
        if cardInfo.gem and GEM_DEF[cardInfo.gem] then
            local gd = GEM_DEF[cardInfo.gem]
            descText = descText .. "\n" .. gd.icon .. gd.desc
        end
        -- 卡牌类型标签追加到描述末尾
        local destroyStart2 = -1
        if def.unplayable then
            local charCount = 0
            for _ in utf8.codes(descText) do charCount = charCount + 1 end
            destroyStart2 = charCount + 2
            descText = descText .. "\n不可打出"
        elseif def.cardType == "consumable" then
            local charCount = 0
            for _ in utf8.codes(descText) do charCount = charCount + 1 end
            destroyStart2 = charCount + 2
            descText = descText .. "\n销毁"
        elseif def.cardType == "limited" then
            local remaining = def.maxUses
            if cardInfo.usesLeft ~= nil then
                remaining = math.max(0, cardInfo.usesLeft)
            end
            descText = descText .. "\n消耗" .. remaining
        end
        local descPad = w * 0.06
        local descMaxFs = math.max(5, h * 0.08)
        local descMinFs = math.max(4, h * 0.045)
        local descAvailH = descH - pad
        local descBoxW = w - descPad * 2
        local descFs = descMaxFs
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        while descFs > descMinFs do
            nvgFontSize(nvgCtx, descFs)
            local bounds = nvgTextBoxBounds(nvgCtx, 0, 0, descBoxW, descText)
            local textH = bounds[4] - bounds[2]
            if textH <= descAvailH then break end
            descFs = descFs - 0.5
        end
        nvgFontSize(nvgCtx, descFs)
        local normalClr = nvgRGBA(200, 200, 220, alpha)
        local numClr = nvgRGBA(255, 230, 100, alpha)
        local destroyClr2 = nvgRGBA(255, 80, 80, alpha)
        local kwIndices2 = findKeywordCharIndices(descText)
        local descDrawX = x + descPad
        local descDrawY = descTop + pad * 0.5
        local lineH = descFs * 1.2
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFontSize(nvgCtx, descFs)
        local curX = descDrawX
        local curY = descDrawY
        local charIdx2 = 0
        for _, cp in utf8.codes(descText) do
            charIdx2 = charIdx2 + 1
            local ch = utf8.char(cp)
            if ch == "\n" then
                curX = descDrawX
                curY = curY + lineH
            else
                local chW = nvgTextBounds(nvgCtx, 0, 0, ch)
                if curX + chW > descDrawX + descBoxW and curX > descDrawX then
                    curX = descDrawX
                    curY = curY + lineH
                end
                local isNum = (cp >= 0x30 and cp <= 0x39) or cp == 0x25 or cp == 0x2E or cp == 0xD7
                local clr = normalClr
                if destroyStart2 > 0 and charIdx2 >= destroyStart2 then
                    clr = destroyClr2
                elseif isNum then
                    clr = numClr
                end
                nvgFillColor(nvgCtx, clr)
                nvgText(nvgCtx, curX, curY, ch)
                curX = curX + chW
            end
        end
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)



        if cardCost > 0 then
            local mpFs = math.max(7, h * 0.13)
            local mpR = mpFs * 0.55
            local mpX2 = x + pad + mpR
            local mpY2 = y + pad + mpR + h * 0.015
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, mpX2, mpY2, mpR)
            nvgFillColor(nvgCtx, nvgRGBA(30, 50, 160, 230))
            nvgFill(nvgCtx)
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, mpX2, mpY2, mpR)
            nvgStrokeColor(nvgCtx, nvgRGBA(100, 140, 255, 180))
            nvgStrokeWidth(nvgCtx, 1)
            nvgStroke(nvgCtx)
            drawTextCenter(tostring(cardCost), mpX2, mpY2, mpFs * 0.7, 200, 220, 255, alpha)
        end

        if cardInfo.gem and GEM_DEF[cardInfo.gem] then
            local gd = GEM_DEF[cardInfo.gem]
            local gemFs = math.max(7, h * 0.13)
            local gemR = gemFs * 0.55
            local gemX = x + w - pad - gemR
            local gemY = y + pad + gemR + h * 0.015
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, gemX, gemY, gemR)
            nvgFillColor(nvgCtx, nvgRGBA(gd.r, gd.g, gd.b, 200))
            nvgFill(nvgCtx)
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, gemX, gemY, gemR)
            nvgStrokeColor(nvgCtx, nvgRGBA(255, 255, 255, 160))
            nvgStrokeWidth(nvgCtx, 1)
            nvgStroke(nvgCtx)
            if not (gd.iconId and spr.drawIcon(gd.iconId, gemX, gemY, gemFs * 0.8)) then
                drawTextCenter(gd.icon, gemX, gemY, gemFs * 0.7, 255, 255, 255, alpha)
            end
        end
    end

    -- 不可用时不再叠加暗淡遮罩（保持卡牌原始外观）

    -- 恢复裁切区域
    nvgRestore(nvgCtx)
end

-- ============================================================
-- 卡牌图鉴
-- ============================================================

local CARD_ORDER = {"strike", "defend", "heal", "guard", "shield", "meditate", "thrifty", "poison", "venomBlade", "shieldSlam", "bloodRite", "power", "heavyStrike", "savageBash", "roar", "furyCleave", "battleCry", "toughHide", "berserkerRage", "groundSlam", "furyBurst", "undying", "bloodScent", "titanGrip", "warpath", "drain", "weaken", "reflect", "pierce", "execute", "haste", "thunder", "firestorm", "bladestorm", "soulBurn", "handBlast", "devour", "convert", "hp50", "hp100", "hp300", "atk1", "atk2", "atk4", "atk8", "atk15", "def1", "def2", "def4", "def8", "def15"}

-- ============================================================
-- 宝石装备选择面板（拾取宝石后弹出）
-- ============================================================
-- ============================================================
-- 遗物详情弹窗
-- ============================================================
function drawRelicDetail()
    if not relicDetail.open or not relicDetail.id then return end
    -- 查找遗物定义
    local rl
    for _, rd in pairs(RELIC_DEF) do
        if rd.id == relicDetail.id then rl = rd; break end
    end
    if not rl then relicDetail.open = false; return end

    local panelW = math.min(logicalW * 0.7, 260)
    local panelH = math.min(logicalH * 0.3, 160)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 120)
    -- 面板
    drawRoundRect(px, py, panelW, panelH, 10, 25, 22, 50, 245)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(rl.r, rl.g, rl.b, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 图标（优先图片）
    local iconFs = math.max(20, panelH * 0.2)
    if not (rl.iconId and spr.drawIcon(rl.iconId, px + panelW / 2, py + panelH * 0.22, iconFs * 1.2)) then
        drawTextCenter(rl.icon, px + panelW / 2, py + panelH * 0.22, iconFs, rl.r, rl.g, rl.b)
    end

    -- 名称
    local nameFs = math.max(12, panelH * 0.12)
    drawTextCenter(rl.name, px + panelW / 2, py + panelH * 0.42, nameFs, rl.r, rl.g, rl.b)

    -- 描述
    local descFs = math.max(9, panelH * 0.09)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, descFs)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 255))
    nvgTextBox(nvgCtx, px + 20, py + panelH * 0.55, panelW - 40, rl.desc)

    -- 底部提示
    local tipFs = math.max(8, descFs * 0.85)
    drawTextCenter("点击任意处关闭", px + panelW / 2, py + panelH - tipFs * 1.5, tipFs, 120, 120, 150)
end

function drawSkillDetail()
    if not relicDetail.skillOpen or not relicDetail.skillKey then return end
    local sk = SKILL_DEF[relicDetail.skillKey]
    if not sk then relicDetail.skillOpen = false; return end

    local panelW = math.min(logicalW * 0.7, 260)
    local panelH = math.min(logicalH * 0.3, 160)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 120)
    drawRoundRect(px, py, panelW, panelH, 10, 25, 22, 50, 245)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(sk.r, sk.g, sk.b, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    local iconFs = math.max(20, panelH * 0.2)
    if not (sk.iconId and spr.drawIcon(sk.iconId, px + panelW / 2, py + panelH * 0.22, iconFs * 1.2)) then
        drawTextCenter(sk.icon, px + panelW / 2, py + panelH * 0.22, iconFs, sk.r, sk.g, sk.b)
    end
    local nameFs = math.max(12, panelH * 0.12)
    drawTextCenter(sk.name, px + panelW / 2, py + panelH * 0.42, nameFs, sk.r, sk.g, sk.b)
    local descFs = math.max(9, panelH * 0.09)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, descFs)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 255))
    nvgTextBox(nvgCtx, px + 20, py + panelH * 0.55, panelW - 40, sk.desc)
    local tipFs = math.max(8, descFs * 0.85)
    drawTextCenter("点击任意处关闭", px + panelW / 2, py + panelH - tipFs * 1.5, tipFs, 120, 120, 150)
end

--- 战斗状态详情弹窗
function drawStatusPopup()
    if not battle._statusPopup then return end
    local st = battle._statusPopup.st
    if not st then battle._statusPopup = nil; return end

    local panelW = math.min(logicalW * 0.6, 220)
    local panelH = math.min(logicalH * 0.22, 120)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 100)
    -- 面板
    drawRoundRect(px, py, panelW, panelH, 10, 25, 22, 50, 240)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(st.r, st.g, st.b, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 图标
    local iconFs = math.max(18, panelH * 0.25)
    if not (st.iconId and spr.drawIcon(st.iconId, px + panelW / 2, py + panelH * 0.25, iconFs * 1.1)) then
        drawTextCenter(st.icon, px + panelW / 2, py + panelH * 0.25, iconFs, st.r, st.g, st.b)
    end

    -- 名称
    local nameFs = math.max(11, panelH * 0.13)
    drawTextCenter(st.name, px + panelW / 2, py + panelH * 0.48, nameFs, st.r, st.g, st.b)

    -- 描述
    local descFs = math.max(9, panelH * 0.1)
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, descFs)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 255))
    nvgTextBox(nvgCtx, px + 16, py + panelH * 0.6, panelW - 32, st.desc)

    -- 底部提示
    local tipFs = math.max(7, descFs * 0.8)
    drawTextCenter("点击任意处关闭", px + panelW / 2, py + panelH - tipFs * 1.5, tipFs, 120, 120, 150)
end

function drawGemEquipPanel()
    if not gemEquip.open or not gemEquip.gemId then return end
    local gd = GEM_DEF[gemEquip.gemId]
    if not gd then gemEquip.open = false; return end

    gemEquip.cardRects = {}
    gemEquip.closeRect = nil
    gemEquip.confirmRect = nil
    gemEquip.cancelRect = nil

    -- ========== 确认页面：显示镶嵌前/后对比 ==========
    if gemEquip.confirmCardIdx then
        local card = player.cards[gemEquip.confirmCardIdx]
        if not card then gemEquip.confirmCardIdx = nil; return end
        local cdef = CARD_DEF[card.id]
        if not cdef then gemEquip.confirmCardIdx = nil; return end

        local panelW = math.min(logicalW * 0.92, 380)
        local panelH = math.min(logicalH * 0.72, 420)
        local px = (logicalW - panelW) / 2
        local py = (logicalH - panelH) / 2

        -- 全屏遮罩
        drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 180)
        -- 面板背景
        drawRoundRect(px, py, panelW, panelH, 10, 25, 22, 50, 245)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
        nvgStrokeColor(nvgCtx, nvgRGBA(gd.r, gd.g, gd.b, 200))
        nvgStrokeWidth(nvgCtx, 2)
        nvgStroke(nvgCtx)

        -- 标题
        local tFs = math.max(11, panelH * 0.045)
        local titleTxt = "镶嵌 " .. gd.name .. " 到 " .. cdef.name
        local titleCX = px + panelW / 2
        local titleCY = py + tFs * 1.2
        spr.drawIcon(gd.iconId, titleCX - nvgTextBounds(nvgCtx, 0, 0, titleTxt) / 2 - tFs * 0.6, titleCY, tFs * 0.9)
        drawTextCenter(titleTxt, titleCX, titleCY, tFs, gd.r, gd.g, gd.b)

        -- 两张卡牌对比
        local cardW = math.floor(math.min((panelW - 40) / 2.3, 130) * 1.25)
        local cardH = cardW * 1.5
        local gap = panelW * 0.06
        local totalW = cardW * 2 + gap
        local startX = px + (panelW - totalW) / 2
        local cardY = py + tFs * 3.6

        -- 左：镶嵌前
        local labelFs = math.max(9, tFs * 0.8)
        drawTextCenter("镶嵌前", startX + cardW / 2, cardY - labelFs * 0.8, labelFs, 180, 180, 200)
        drawCard(startX, cardY, cardW, cardH, {id = card.id, gem = card.gem}, false, false)

        -- 箭头
        local arrowX = startX + cardW + gap / 2
        local arrowY = cardY + cardH * 0.45
        local arrowFs = math.max(14, gap * 0.8)
        drawTextCenter("→", arrowX, arrowY, arrowFs, gd.r, gd.g, gd.b)

        -- 右：镶嵌后
        local rightX = startX + cardW + gap
        drawTextCenter("镶嵌后", rightX + cardW / 2, cardY - labelFs * 0.8, labelFs, gd.r, gd.g, gd.b)
        drawCard(rightX, cardY, cardW, cardH, {id = card.id, gem = gemEquip.gemId}, false, false)

        -- 替换提示
        if card.gem and GEM_DEF[card.gem] then
            local oldGd = GEM_DEF[card.gem]
            local warnFs = math.max(8, labelFs * 0.85)
            drawTextCenter(oldGd.icon .. oldGd.name .. " 将被替换并返还", px + panelW / 2, cardY + cardH + warnFs * 1.2, warnFs, 255, 200, 100)
        end

        -- 按钮区域
        local btnW = math.min(panelW * 0.35, 120)
        local btnH = math.max(28, panelH * 0.07)
        local btnY = py + panelH - btnH - panelH * 0.05
        local btnGap = panelW * 0.06

        -- 确认按钮
        local confirmX = px + panelW / 2 - btnW - btnGap / 2
        drawRoundRect(confirmX, btnY, btnW, btnH, 6, gd.r * 0.3, gd.g * 0.3, gd.b * 0.3, 230)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, confirmX, btnY, btnW, btnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(gd.r, gd.g, gd.b, 200))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
        local btnFs = math.max(10, btnH * 0.5)
        drawTextCenter("确认镶嵌", confirmX + btnW / 2, btnY + btnH / 2, btnFs, gd.r, gd.g, gd.b)
        gemEquip.confirmRect = {x = confirmX, y = btnY, w = btnW, h = btnH}

        -- 取消按钮
        local cancelX = px + panelW / 2 + btnGap / 2
        drawRoundRect(cancelX, btnY, btnW, btnH, 6, 80, 70, 100, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cancelX, btnY, btnW, btnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(180, 180, 200, 120))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
        drawTextCenter("返回", cancelX + btnW / 2, btnY + btnH / 2, btnFs, 200, 200, 220)
        gemEquip.cancelRect = {x = cancelX, y = btnY, w = btnW, h = btnH}
        return
    end

    -- ========== 选卡列表页面（卡牌网格） ==========
    -- 筛选可镶嵌的卡牌：空槽卡不需要锤子；已有宝石的卡需要宝石工匠锤才能替换
    local eligibleCards = {}
    for ci, c in ipairs(player.cards) do
        local cdef = CARD_DEF[c.id]
        if cdef and cdef.cardType ~= "consumable" and (not c.gem or player.relics.gemCraft) then
            table.insert(eligibleCards, {idx = ci, card = c, def = cdef})
        end
    end

    -- 卡牌网格布局
    local cardPad = 8
    local panelW = math.min(logicalW * 0.92, 400)
    local innerW = panelW - 24
    local baseCardW = (innerW - cardPad * 2) / 3  -- 原3列尺寸
    local cardW = math.floor(baseCardW * 1.0)  -- 0.8倍 (1.25*0.8=1.0)
    local cols = math.max(2, math.floor((innerW + cardPad) / (cardW + cardPad)))
    local cardH = cardW * 1.5
    local rows = math.ceil(#eligibleCards / cols)
    local titleH = math.max(38, logicalH * 0.06)
    local subtitleH = math.max(24, logicalH * 0.035)
    local hintH = math.max(20, logicalH * 0.03)
    local footerH = math.max(36, logicalH * 0.05)
    local gridH = rows * (cardH + cardPad) + cardPad
    local maxGridH = logicalH * 0.55
    local visibleGridH = math.min(gridH, maxGridH)
    local panelH = titleH + subtitleH + hintH + visibleGridH + footerH + 12
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 全屏遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 180)

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 10, 25, 22, 50, 245)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(gd.r, gd.g, gd.b, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)
    -- 保存面板区域用于点击判断
    gemEquip.panelRect = {x = px, y = py, w = panelW, h = panelH}

    -- 标题：宝石图标 + 名称
    local tFs = math.max(12, titleH * 0.48)
    local gemTitleCX = px + panelW / 2
    local gemTitleCY = py + titleH * 0.4
    spr.drawIcon(gd.iconId, gemTitleCX - nvgTextBounds(nvgCtx, 0, 0, gd.name) / 2 - tFs * 0.6, gemTitleCY, tFs * 0.9)
    drawTextCenter(gd.name, gemTitleCX, gemTitleCY, tFs, gd.r, gd.g, gd.b)
    -- 副标题：效果描述
    local sFs = math.max(8, subtitleH * 0.45)
    drawTextCenter(gd.desc, px + panelW / 2, py + titleH + subtitleH * 0.4, sFs, 200, 200, 220)

    -- 分隔线
    local sepY = py + titleH + subtitleH
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, px + 12, sepY)
    nvgLineTo(nvgCtx, px + panelW - 12, sepY)
    nvgStrokeColor(nvgCtx, nvgRGBA(gd.r, gd.g, gd.b, 80))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 提示文字
    local hintFs = math.max(8, sFs * 0.9)
    drawTextCenter("选择一张卡牌镶嵌宝石", px + panelW / 2, sepY + hintH * 0.5, hintFs, 160, 160, 180)

    -- 卡牌网格（裁剪区域内滚动）
    local gridTop = sepY + hintH
    local maxScroll = math.max(0, gridH - visibleGridH)
    gemEquip.scroll = math.max(0, math.min(gemEquip.scroll, maxScroll))

    nvgSave(nvgCtx)
    nvgScissor(nvgCtx, px, gridTop, panelW, visibleGridH)

    for ei, ec in ipairs(eligibleCards) do
        local col = (ei - 1) % cols
        local row = math.floor((ei - 1) / cols)
        local cx = px + 12 + col * (cardW + cardPad)
        local cy = gridTop + cardPad + row * (cardH + cardPad) - gemEquip.scroll
        if cy + cardH > gridTop - cardH and cy < gridTop + visibleGridH + cardH then
            drawCard(cx, cy, cardW, cardH, {id = ec.card.id, gem = ec.card.gem}, false, false)
            table.insert(gemEquip.cardRects, {x = cx, y = cy, w = cardW, h = cardH, cardIdx = ec.idx})
        end
    end

    nvgRestore(nvgCtx)

    -- 底部按钮区域
    local closeH = footerH - 8
    local closeY = py + panelH - footerH + 2
    local cFs = math.max(9, closeH * 0.55)

    if gemEquip.fromMap then
        -- 地图拾取：两个按钮（放入背包 + 暂不镶嵌）
        local gap = 8
        local btnW = (panelW - 24 - gap) / 2
        local bpX = px + 12
        local clX = bpX + btnW + gap

        -- "放入背包"按钮（绿色调）
        drawRoundRect(bpX, closeY, btnW, closeH, 5, 40, 90, 60, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, bpX, closeY, btnW, closeH, 5)
        nvgStrokeColor(nvgCtx, nvgRGBA(100, 200, 130, 150))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)
        drawTextCenter("放入背包", bpX + btnW / 2, closeY + closeH / 2, cFs, 130, 230, 150)
        gemEquip.backpackRect = {x = bpX, y = closeY, w = btnW, h = closeH}

        -- "暂不镶嵌"按钮
        drawRoundRect(clX, closeY, btnW, closeH, 5, 80, 70, 100, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, clX, closeY, btnW, closeH, 5)
        nvgStrokeColor(nvgCtx, nvgRGBA(180, 180, 200, 120))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)
        drawTextCenter("暂不镶嵌", clX + btnW / 2, closeY + closeH / 2, cFs, 200, 200, 220)
        gemEquip.closeRect = {x = clX, y = closeY, w = btnW, h = closeH}
    else
        -- 背包来源：单个关闭按钮
        local closeW = panelW * 0.5
        local closeX = px + (panelW - closeW) / 2
        drawRoundRect(closeX, closeY, closeW, closeH, 5, 80, 70, 100, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, closeX, closeY, closeW, closeH, 5)
        nvgStrokeColor(nvgCtx, nvgRGBA(180, 180, 200, 120))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)
        drawTextCenter("暂不镶嵌", closeX + closeW / 2, closeY + closeH / 2, cFs, 200, 200, 220)
        gemEquip.closeRect = {x = closeX, y = closeY, w = closeW, h = closeH}
        gemEquip.backpackRect = nil
    end
end

-- ============================================================
-- 跳跃上楼系统 - 逻辑 & UI
-- ============================================================

local function getContentMaxFloor()
    return math.min(CONTENT_MAX_FLOOR or TOTAL_FLOORS, TOTAL_FLOORS)
end

local function showContentLockedMessage()
    showMessage("后续内容正在完善中，敬请期待", 2.5, 255, 220, 100)
    playSfx("block", 0.6)
end

local function canAccessFloor(targetFloor)
    return targetFloor <= getContentMaxFloor()
end

--- 执行普通上楼 (+1层)
local function doNormalClimb()
    local targetFloor = player.floor + 1
    if not canAccessFloor(targetFloor) then
        stairUI.active = false
        showContentLockedMessage()
        return
    end

    stairUI.active = false
    player.floor = targetFloor
    local dr2, dc2 = findTile(player.floor, 'D')
    if dr2 then
        player.row = dr2
        player.col = dc2
    end
    moveAnim.active = false
    autoPath = {}
    playSfx("stairs", 0.8)
    playBgmForFloor(player.floor)
    if BOSS_FLOORS[player.floor] then
        local bossM = MONSTER_DEF[BOSS_FLOORS[player.floor]]
        showMessage("到达第 " .. player.floor .. " 层 - " .. (bossM and bossM.name or "???") .. "在等你", 2.5, 255, 80, 60)
    else
        showMessage("到达第 " .. player.floor .. " 层", 1.5, 200, 200, 255)
    end
    if gameAutoSave then saveGame() end
end

--- 执行跳跃上楼 (+2层, 删除指定卡牌)
local function doJumpClimb(cardIndex)
    local targetFloor = math.min(TOTAL_FLOORS, player.floor + 2)
    if not canAccessFloor(targetFloor) then
        stairUI.active = false
        stairUI.phase = "choose"
        showContentLockedMessage()
        return
    end

    -- 删除选中的卡牌
    local removedCard = table.remove(player.cards, cardIndex)
    local cardDef = CARD_DEF[removedCard.id]
    local cardName = cardDef and cardDef.name or removedCard.id
    local isCurse = cardDef and cardDef.type == "curse"

    -- 启动跳跃动画（延迟实际楼层切换）
    local anim = stairUI.jumpAnim
    anim.active = true
    anim.phase = "fade_in"
    anim.timer = 0
    anim.fromFloor = player.floor
    anim.toFloor = targetFloor
    anim.cardName = cardName
    anim.cardId = removedCard.id
    anim.cardColor = {cardDef and cardDef.r or 200, cardDef and cardDef.g or 200, cardDef and cardDef.b or 200}
    anim.isCurse = isCurse
    anim.screenShake = 0

    stairUI.active = false
    stairUI.phase = "choose"
    playSfx("attack", 0.6)  -- 卡牌燃烧音效
end

--- 跳跃动画完成时执行实际楼层切换（动画由 fade_out 结束时关闭）
local function finishJumpClimb()
    local anim = stairUI.jumpAnim

    player.floor = anim.toFloor
    local dr2, dc2 = findTile(player.floor, 'D')
    if dr2 then
        player.row = dr2
        player.col = dc2
    end
    moveAnim.active = false
    autoPath = {}
    playSfx("stairs", 0.8)
    playBgmForFloor(player.floor)

    -- 删诅咒卡奖励
    if anim.isCurse then
        player.gold = player.gold + 5
        showMessage("跳跃! 燃烧【" .. anim.cardName .. "】跃至第 " .. player.floor .. " 层 (+5金币)", 2.5, 255, 220, 80)
    else
        showMessage("跳跃! 燃烧【" .. anim.cardName .. "】跃至第 " .. player.floor .. " 层", 2.0, 120, 220, 255)
    end

    if BOSS_FLOORS[player.floor] then
        local bossM = MONSTER_DEF[BOSS_FLOORS[player.floor]]
        showMessage("到达第 " .. player.floor .. " 层 - " .. (bossM and bossM.name or "???") .. "在等你", 2.5, 255, 80, 60)
    end
    if gameAutoSave then saveGame() end
end

--- 绘制跳跃上楼动画 (卡牌消散 + 楼层跳跃)
function drawJumpAnim()
    local anim = stairUI.jumpAnim
    if not anim.active then return end

    local w = logicalW
    local h = logicalH
    local cx = w / 2
    local cy = h / 2

    -- 屏幕震动偏移
    if anim.screenShake > 0 then
        local sx = (math.random() - 0.5) * anim.screenShake * 2
        local sy = (math.random() - 0.5) * anim.screenShake * 2
        nvgTranslate(nvgCtx, sx, sy)
    end

    if anim.phase == "fade_in" then
        -- === 前置淡入阶段（0.5s 遮罩渐显） ===
        local t = anim.timer / anim.fadeInDur  -- 0→1
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, 0, 0, w, h)
        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, math.floor(140 * t)))
        nvgFill(nvgCtx)

        -- 提示文字淡入
        if t > 0.3 then
            local textAlpha = math.floor(255 * ((t - 0.3) / 0.7))
            nvgFontSize(nvgCtx, 16)
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, nvgRGBA(255, 200, 100, textAlpha))
            nvgText(nvgCtx, cx, cy, "燃烧卡牌...")
        end

    elseif anim.phase == "card_burn" then
        -- === 卡牌消散阶段 ===
        local t = anim.timer / anim.cardBurnDur  -- 0→1
        local easeT = t * t  -- 加速

        -- 全屏暗色遮罩（从fade_in的140继续）
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, 0, 0, w, h)
        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 140 + math.floor(60 * t)))
        nvgFill(nvgCtx)

        -- 卡牌尺寸（基于屏幕比例）
        local baseCardW = math.min(w * 0.35, 130)
        local baseCardH = baseCardW * 1.45
        local cardW = baseCardW * (1 - easeT * 0.4)
        local cardH = baseCardH * (1 - easeT * 0.4)
        local cardX = cx - cardW / 2
        local cardY = cy - cardH / 2 - easeT * 40  -- 向上飘
        local alpha = math.floor(255 * (1 - easeT))

        -- 卡牌发光外框（越来越亮）
        local glowAlpha = math.floor(150 * easeT)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cardX - 5, cardY - 5, cardW + 10, cardH + 10, 10)
        nvgFillColor(nvgCtx, nvgRGBA(255, 180, 50, glowAlpha))
        nvgFill(nvgCtx)

        -- 使用统一 drawCard 渲染（保持和游戏中一致的卡牌外观）
        nvgSave(nvgCtx)
        nvgGlobalAlpha(nvgCtx, alpha / 255)
        drawCard(cardX, cardY, cardW, cardH, {id = anim.cardId}, false, false)
        nvgRestore(nvgCtx)

        -- 卡牌名字（底部）
        if alpha > 80 then
            nvgFontSize(nvgCtx, 13 * (1 - easeT * 0.3))
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, alpha))
            nvgText(nvgCtx, cx, cardY + cardH + 14, anim.cardName)
        end

        -- 粒子（向上飘散的火星）
        for i = 1, 8 do
            local px = cx + math.sin(i * 1.0 + t * 8) * (15 + t * 35)
            local py = (cardY + cardH/2) - t * 60 - i * 7
            local pAlpha = math.floor(220 * (1 - t) * (1 - i/9))
            if pAlpha > 0 then
                nvgBeginPath(nvgCtx)
                nvgCircle(nvgCtx, px, py, 1.5 + t * 2.5)
                nvgFillColor(nvgCtx, nvgRGBA(255, 200, 60, pAlpha))
                nvgFill(nvgCtx)
            end
        end

    elseif anim.phase == "floor_jump" then
        -- === 楼层跳跃阶段 ===
        local t = anim.timer / anim.floorJumpDur  -- 0→1
        local easeT = 1 - (1 - t) * (1 - t)  -- 减速

        -- 白色闪光（快速淡出）
        local flashAlpha = math.floor(180 * math.max(0, 1 - t * 3))
        if flashAlpha > 0 then
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, 0, 0, w, h)
            nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, flashAlpha))
            nvgFill(nvgCtx)
        end

        -- 楼层数字跳动 (从 fromFloor → toFloor)
        local displayFloor = anim.fromFloor
        if t > 0.2 then displayFloor = anim.fromFloor + 1 end
        if t > 0.5 then displayFloor = anim.toFloor end

        -- 数字弹跳缩放
        local numScale = 1.0
        if t < 0.3 then
            numScale = 1.0 + 0.5 * math.sin(t / 0.3 * math.pi)
        elseif t > 0.5 and t < 0.7 then
            numScale = 1.0 + 0.3 * math.sin((t - 0.5) / 0.2 * math.pi)
        end

        local numFs = 36 * numScale
        local numAlpha = math.floor(255 * math.min(1, t * 4))
        nvgFontSize(nvgCtx, numFs)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(120, 220, 255, numAlpha))
        nvgText(nvgCtx, cx, cy - 10, "F" .. displayFloor)

        -- 向上箭头动画
        local arrowY = cy + 30 - easeT * 20
        local arrowAlpha = math.floor(200 * (1 - t))
        nvgFontSize(nvgCtx, 20)
        nvgFillColor(nvgCtx, nvgRGBA(180, 130, 255, arrowAlpha))
        nvgText(nvgCtx, cx, arrowY, "^")

        -- "跳跃" 文字
        if t > 0.3 then
            local txtAlpha = math.floor(200 * math.min(1, (t - 0.3) * 3))
            nvgFontSize(nvgCtx, 14)
            nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, txtAlpha))
            nvgText(nvgCtx, cx, cy + 25, "跳跃!")
        end

    elseif anim.phase == "fade_out" then
        -- === 后置淡出阶段（0.5s 遮罩渐隐，新楼层已加载） ===
        local t = anim.timer / anim.fadeOutDur  -- 0→1
        local alpha = math.floor(140 * (1 - t))
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, 0, 0, w, h)
        nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, alpha))
        nvgFill(nvgCtx)

        -- 新楼层提示淡出
        if t < 0.6 then
            local textAlpha = math.floor(255 * (1 - t / 0.6))
            nvgFontSize(nvgCtx, 18)
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, nvgRGBA(120, 220, 255, textAlpha))
            nvgText(nvgCtx, cx, cy, "第 " .. anim.toFloor .. " 层")
        end
    end

    -- 重置震动
    if anim.screenShake > 0 then
        nvgResetTransform(nvgCtx)
    end
end

--- 绘制跳跃上楼弹窗
function drawStairUI()
    if not stairUI.active then return end

    local w = logicalW
    local h = logicalH

    -- 半透明遮罩
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, w, h)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 180))
    nvgFill(nvgCtx)

    if stairUI.phase == "choose" then
        -- ========== 选择阶段: 显示下一层完整地图预览 ==========

        local nextFloor = player.floor + 1
        local contentMaxFloor = getContentMaxFloor()
        local jumpFloor = math.min(contentMaxFloor, player.floor + 2)

        -- 面板布局（自适应屏幕宽度）
        local titleH = 46
        local btnH = 40
        local btnPad = 10
        local panelPad = 10
        local maxPanelW = w * 0.92  -- 面板最大不超过屏幕92%宽度
        -- 地图格子大小：取高度和宽度限制中较小的
        local mapAreaH = h * 0.55
        local mapCellByH = math.floor(mapAreaH / GRID)
        local mapCellByW = math.floor((maxPanelW - panelPad * 2) / GRID)
        local mapCellSize = math.min(mapCellByH, mapCellByW)
        local mapSize = mapCellSize * GRID
        local panelW = math.min(math.max(mapSize + panelPad * 2, w * 0.7), maxPanelW)
        local panelH = titleH + mapSize + btnH + btnPad * 3
        local px = (w - panelW) / 2
        local py = (h - panelH) / 2

        -- 面板背景
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 12)
        nvgFillColor(nvgCtx, nvgRGBA(30, 25, 45, 240))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(100, 180, 255, 200))
        nvgStrokeWidth(nvgCtx, 2)
        nvgStroke(nvgCtx)

        -- 封印提示（面板上方）
        nvgFontSize(nvgCtx, 11)
        nvgFillColor(nvgCtx, nvgRGBA(255, 150, 80, 220))
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvgCtx, w / 2, py - 12, "⚠ 封印: 上楼后无法下楼")

        -- 标题
        nvgFontSize(nvgCtx, 17)
        nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 255))
        nvgText(nvgCtx, w / 2, py + 22, "第 " .. nextFloor .. " 层预览")

        -- 渲染下一层地图（临时替换全局变量）
        local savedFloor = player.floor
        local savedGridX = gridX
        local savedGridY = gridY
        local savedCellSize = cellSize

        local mapX = px + (panelW - mapSize) / 2
        local mapY = py + titleH
        gridX = mapX
        gridY = mapY
        cellSize = mapCellSize
        player.floor = nextFloor

        nvgSave(nvgCtx)
        nvgScissor(nvgCtx, mapX, mapY, mapSize, mapSize)
        for r = 1, GRID do
            for c = 1, GRID do
                drawTile(r, c)
            end
        end
        nvgRestore(nvgCtx)

        -- 恢复全局变量
        player.floor = savedFloor
        gridX = savedGridX
        gridY = savedGridY
        cellSize = savedCellSize

        -- 底部按钮区域
        local btnAreaY = mapY + mapSize + btnPad
        local bw = panelW * 0.40
        local btn1X = px + panelW * 0.06
        local btn2X = px + panelW * 0.54

        -- 普通上楼按钮
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btn1X, btnAreaY, bw, btnH, 8)
        nvgFillColor(nvgCtx, nvgRGBA(40, 80, 50, 230))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(80, 200, 100, 200))
        nvgStrokeWidth(nvgCtx, 2)
        nvgStroke(nvgCtx)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(nvgCtx, 14)
        nvgFillColor(nvgCtx, nvgRGBA(200, 255, 200, 255))
        nvgText(nvgCtx, btn1X + bw/2, btnAreaY + btnH/2, "上楼 → F" .. nextFloor)
        stairUI.normalRect = {x = btn1X, y = btnAreaY, w = bw, h = btnH}

        -- 跳跃上楼按钮
        local jumpAlpha = stairUI.canJump and 230 or 120
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, btn2X, btnAreaY, bw, btnH, 8)
        nvgFillColor(nvgCtx, nvgRGBA(60, 40, 90, jumpAlpha))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, stairUI.canJump and nvgRGBA(150, 100, 255, 200) or nvgRGBA(80, 60, 100, 100))
        nvgStrokeWidth(nvgCtx, 2)
        nvgStroke(nvgCtx)
        nvgFontSize(nvgCtx, 13)
        if stairUI.canJump then
            nvgFillColor(nvgCtx, nvgRGBA(200, 180, 255, 255))
            nvgText(nvgCtx, btn2X + bw/2, btnAreaY + btnH * 0.35, "跳过 → F" .. jumpFloor)
            nvgFontSize(nvgCtx, 10)
            nvgFillColor(nvgCtx, nvgRGBA(255, 130, 100, 200))
            nvgText(nvgCtx, btn2X + bw/2, btnAreaY + btnH * 0.72, "删除1张卡牌")
        else
            nvgFillColor(nvgCtx, nvgRGBA(120, 100, 140, 150))
            nvgText(nvgCtx, btn2X + bw/2, btnAreaY + btnH * 0.35, "跳过(不可用)")
            nvgFontSize(nvgCtx, 10)
            nvgFillColor(nvgCtx, nvgRGBA(150, 100, 100, 150))
            local reason = #player.cards <= 5 and "牌组≤5张" or "内容开发中"
            nvgText(nvgCtx, btn2X + bw/2, btnAreaY + btnH * 0.72, reason)
        end
        stairUI.jumpRect = {x = btn2X, y = btnAreaY, w = bw, h = btnH}

        -- 取消（底部小字）
        local cancelW = panelW * 0.3
        local cancelH = 22
        local cancelX = (w - cancelW) / 2
        local cancelY = btnAreaY + btnH + 2
        nvgFontSize(nvgCtx, 10)
        nvgFillColor(nvgCtx, nvgRGBA(140, 130, 130, 180))
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvgCtx, cancelX + cancelW/2, cancelY + cancelH/2, "暂不上楼")
        stairUI.cancelRect = {x = cancelX, y = cancelY, w = cancelW, h = cancelH}

    elseif stairUI.phase == "delete" then
        -- ========== 删牌阶段: 网格选卡（复用 drawCard） ==========
        local cardCount = #player.cards
        local cardH = math.min(h * 0.28, 140)
        local cardW = math.floor(cardH * 0.68)
        local gap = 8
        local cols = math.max(2, math.min(5, math.floor((w * 0.88) / (cardW + gap))))
        local rows = math.max(1, math.ceil(cardCount / cols))
        local gridW = cols * cardW + (cols - 1) * gap
        local gridH = rows * (cardH + gap)

        local titleH = math.max(38, h * 0.07)
        local footerH = math.max(50, h * 0.08)
        local panelW = gridW + 28
        local panelH = math.min(h * 0.9, titleH + gridH + footerH + 20)
        local px = (w - panelW) / 2
        local py = (h - panelH) / 2

        local contentTop = py + titleH
        local contentH = panelH - titleH - footerH
        local scrollMax = math.max(0, gridH + 10 - contentH)
        stairUI.cardScroll = math.max(0, math.min(stairUI.cardScroll, scrollMax))

        -- 面板背景
        drawRoundRect(px, py, panelW, panelH, 12, 25, 20, 40, 245)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 12)
        nvgStrokeColor(nvgCtx, nvgRGBA(255, 120, 60, 200))
        nvgStrokeWidth(nvgCtx, 2)
        nvgStroke(nvgCtx)

        -- 标题
        local titleFs = math.max(14, titleH * 0.45)
        drawTextCenter("选择要燃烧的卡牌 (跳跃至第 " .. math.min(getContentMaxFloor(), player.floor + 2) .. " 层)",
            px + panelW / 2, py + titleH * 0.4, titleFs, 255, 180, 100)
        local subFs = math.max(10, titleFs * 0.7)
        drawTextCenter("该卡牌将被永久删除，化为跳跃之力",
            px + panelW / 2, py + titleH * 0.75, subFs, 200, 160, 100)

        -- 裁剪内容区域
        nvgSave(nvgCtx)
        nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)

        -- 卡牌网格（复用 drawCard）
        local startX = px + (panelW - gridW) / 2
        local startY = contentTop + 6 - stairUI.cardScroll
        stairUI.cardRects = {}

        for i, card in ipairs(player.cards) do
            local def = CARD_DEF[card.id]
            if not def then goto continueStairCard end

            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local cx = startX + col * (cardW + gap)
            local cy = startY + row * (cardH + gap)

            -- 跳过不可见卡牌
            if cy + cardH >= contentTop and cy <= contentTop + contentH then
                local isSelected = (stairUI.selectedCard == i)
                local drawY = cy
                if isSelected then drawY = cy - 4 end

                drawCard(cx, drawY, cardW, cardH, {id = card.id, gem = card.gem}, isSelected, false)

                -- 选中时红色"删除"标记
                if isSelected then
                    local markFs = math.max(9, cardW * 0.14)
                    nvgFontSize(nvgCtx, markFs)
                    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                    nvgFillColor(nvgCtx, nvgRGBA(255, 80, 50, 255))
                    nvgText(nvgCtx, cx + cardW / 2, drawY + cardH + 2, "✦删除")
                end

                stairUI.cardRects[i] = {x = cx, y = drawY, w = cardW, h = cardH}
            end

            ::continueStairCard::
        end

        nvgRestore(nvgCtx)

        -- 滚动条
        if scrollMax > 0 then
            local barH = math.max(20, contentH * (contentH / (gridH + 10)))
            local barY = contentTop + (contentH - barH) * (stairUI.cardScroll / scrollMax)
            local barX = px + panelW - 6
            drawRoundRect(barX, barY, 3, barH, 2, 255, 120, 60, 120)
        end

        -- 底部按钮
        local btnAreaY = py + panelH - footerH + 6
        local confirmW = panelW * 0.4
        local confirmH = 34
        local confirmX = px + panelW * 0.08
        local backX = px + panelW * 0.52
        local backW = panelW * 0.4

        -- 确认删除按钮
        local canConfirm = stairUI.selectedCard ~= nil
        drawRoundRect(confirmX, btnAreaY, confirmW, confirmH, 8,
            canConfirm and 120 or 50, canConfirm and 40 or 40, canConfirm and 30 or 40, canConfirm and 230 or 150)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, confirmX, btnAreaY, confirmW, confirmH, 8)
        nvgStrokeColor(nvgCtx, canConfirm and nvgRGBA(255, 100, 60, 200) or nvgRGBA(80, 60, 60, 100))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
        local confirmFs = math.max(12, confirmH * 0.42)
        nvgFontSize(nvgCtx, confirmFs)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, canConfirm and nvgRGBA(255, 200, 150, 255) or nvgRGBA(120, 100, 100, 150))
        nvgText(nvgCtx, confirmX + confirmW / 2, btnAreaY + confirmH / 2, "确认燃烧跳跃")
        stairUI.confirmRect = {x = confirmX, y = btnAreaY, w = confirmW, h = confirmH}

        -- 返回按钮
        drawRoundRect(backX, btnAreaY, backW, confirmH, 8, 40, 40, 60, 200)
        nvgFontSize(nvgCtx, confirmFs)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 255))
        nvgText(nvgCtx, backX + backW / 2, btnAreaY + confirmH / 2, "返回")
        stairUI.cancelRect = {x = backX, y = btnAreaY, w = backW, h = confirmH}
    end
end

--- 处理跳跃上楼弹窗的点击事件
function handleStairUIClick(x, y)
    if not stairUI.active then return false end

    local function hitRect(rect)
        if not rect then return false end
        return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
    end

    if stairUI.phase == "choose" then
        -- 普通上楼
        if hitRect(stairUI.normalRect) then
            playSfx("btn", 0.7)
            doNormalClimb()
            return true
        end
        -- 跳跃上楼
        if stairUI.canJump and hitRect(stairUI.jumpRect) then
            playSfx("btn", 0.7)
            stairUI.phase = "delete"
            stairUI.selectedCard = nil
            stairUI.cardScroll = 0
            return true
        end
        -- 取消
        if hitRect(stairUI.cancelRect) then
            playSfx("btn", 0.5)
            stairUI.active = false
            return true
        end

    elseif stairUI.phase == "delete" then
        -- 选择卡牌
        for i, rect in pairs(stairUI.cardRects) do
            if hitRect(rect) then
                playSfx("btn", 0.5)
                stairUI.selectedCard = i
                return true
            end
        end
        -- 确认删除
        if stairUI.selectedCard and hitRect(stairUI.confirmRect) then
            playSfx("attack", 0.6)
            doJumpClimb(stairUI.selectedCard)
            return true
        end
        -- 返回
        if hitRect(stairUI.cancelRect) then
            playSfx("btn", 0.5)
            stairUI.phase = "choose"
            return true
        end
    end

    return true  -- 消费事件，不穿透
end

-- ============================================================
-- 商店UI弹窗
-- ============================================================
function drawShop()
    if not shopOpen then return end
    if type(shopItems) ~= "table" then shopItems = {} end
    shopItemRects = {}
    shopCloseRect = nil

    -- 分离卡牌和非卡牌商品
    local cardItems = {}
    local otherItems = {}
    for i, item in ipairs(shopItems) do
        item._origIdx = i
        if item.isCard and item.cardId then
            table.insert(cardItems, item)
        else
            table.insert(otherItems, item)
        end
    end

    -- 面板尺寸
    local panelW = math.min(logicalW * 0.92, 400)
    local titleH = math.max(30, logicalH * 0.042)
    local goldBarH = math.max(22, logicalH * 0.03)
    local footerH = math.max(34, logicalH * 0.042)
    local pad = 6
    local innerW = panelW - pad * 2

    -- 卡牌网格
    local cardGap = 4
    local baseCardCellW = math.floor((innerW - cardGap * 2) / 3)
    local cardW2 = math.floor((baseCardCellW - 6) * 0.95)
    local cardH2 = math.floor(cardW2 * 1.48)
    local cardCellW = cardW2 + 6
    local cardCols = math.max(2, math.floor((innerW + cardGap) / (cardCellW + cardGap)))
    local cardBtnH = math.max(22, cardH2 * 0.17)
    local cardCellH = cardH2 + cardBtnH + 8
    local cardRows = math.ceil(#cardItems / cardCols)
    local cardSectionH = cardRows > 0 and (cardRows * cardCellH + (cardRows - 1) * cardGap) or 0
    local cardLblH = #cardItems > 0 and 18 or 0

    -- 非卡牌网格：2列
    local otherCols = 2
    local otherGap = 5
    local otherCellW = math.floor((innerW - otherGap * (otherCols - 1)) / otherCols)
    local otherCellH = math.max(50, logicalH * 0.072)
    local otherRows = math.ceil(#otherItems / otherCols)
    local otherSectionH = otherRows > 0 and (otherRows * otherCellH + (otherRows - 1) * otherGap) or 0
    local otherLblH = #otherItems > 0 and 18 or 0

    -- 总内容高度
    local totalContentH = cardLblH + cardSectionH + 8 + otherLblH + otherSectionH + 8
    local panelH = math.min(logicalH * 0.92, titleH + goldBarH + totalContentH + footerH + 16)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 全屏遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 160)

    -- 面板背景（深色渐变感）
    drawRoundRect(px, py, panelW, panelH, 10, 22, 18, 40, 248)
    -- 顶部高光
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px + 1, py + 1, panelW - 2, titleH, 10)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 15))
    nvgFill(nvgCtx)
    -- 边框
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 80, 160))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    -- 标题
    local titleFs = math.max(15, titleH * 0.58)
    drawTextCenter("\u{1FA99} \u{5546}\u{5E97}", px + panelW / 2, py + titleH / 2, titleFs, 255, 220, 100)

    -- 分隔线
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, px + 10, py + titleH)
    nvgLineTo(nvgCtx, px + panelW - 10, py + titleH)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 80, 60))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 金币显示
    local goldY = py + titleH + 2
    local goldFs = math.max(11, goldBarH * 0.55)
    nvgFontSize(nvgCtx, goldFs)
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 80, 255))
    nvgText(nvgCtx, px + panelW - 12, goldY + goldBarH / 2, "\u{1FA99} " .. player.gold)

    -- 内容区域（可滚动）
    local listY = goldY + goldBarH + 4
    local listH = panelH - titleH - goldBarH - footerH - 12
    nvgSave(nvgCtx)
    nvgIntersectScissor(nvgCtx, px, listY, panelW, listH)

    local curY = listY - shopScroll

    -- === 卡牌区域标题 ===
    if #cardItems > 0 then
        local lblFs = math.max(10, 12)
        nvgFontSize(nvgCtx, lblFs)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(255, 210, 80, 180))
        nvgText(nvgCtx, px + pad + 2, curY + cardLblH / 2, "\u{25C6} \u{5361}\u{724C}")
        curY = curY + cardLblH

        -- 卡牌网格
        for ci = 1, #cardItems do
            local item = cardItems[ci]
            local col = (ci - 1) % cardCols
            local row = math.floor((ci - 1) / cardCols)
            local cx = px + pad + col * (cardCellW + cardGap)
            local cy = curY + row * (cardCellH + cardGap)
            local canBuy = player.gold >= item.cost

            -- 可见性判断
            if cy + cardCellH >= listY and cy <= listY + listH then
                -- 格子背景
                local bgA = canBuy and 130 or 60
                drawRoundRect(cx, cy, cardCellW, cardCellH, 5, 32, 28, 52, bgA)
                -- 买得起时微弱金边
                if canBuy then
                    nvgBeginPath(nvgCtx)
                    nvgRoundedRect(nvgCtx, cx, cy, cardCellW, cardCellH, 5)
                    nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 80, 50))
                    nvgStrokeWidth(nvgCtx, 1)
                    nvgStroke(nvgCtx)
                end

                -- 绘制卡牌
                local cardInfo = {id = item.cardId}
                drawCard(cx + 3, cy + 3, cardW2, cardH2, cardInfo, false, false)

                -- 价格按钮
                local btnW = cardCellW - 6
                local btnH3 = cardBtnH
                local btnX = cx + 3
                local btnY = cy + cardH2 + 5
                if canBuy then
                    drawRoundRect(btnX, btnY, btnW, btnH3, 4, 45, 125, 40, 230)
                else
                    drawRoundRect(btnX, btnY, btnW, btnH3, 4, 65, 50, 50, 140)
                end
                local pFs = math.max(9, btnH3 * 0.52)
                if canBuy then
                    drawTextCenter(tostring(item.cost) .. "G", btnX + btnW / 2, btnY + btnH3 / 2, pFs, 255, 225, 80)
                else
                    drawTextCenter(tostring(item.cost) .. "G", btnX + btnW / 2, btnY + btnH3 / 2, pFs, 120, 100, 80)
                end

                -- 整个格子可点击
                table.insert(shopItemRects, {x = cx, y = cy, w = cardCellW, h = cardCellH, index = item._origIdx})
            end
        end
        curY = curY + cardSectionH + 8
    end

    -- === 道具区域标题 ===
    if #otherItems > 0 then
        local lblFs = math.max(10, 12)
        nvgFontSize(nvgCtx, lblFs)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(140, 200, 255, 180))
        nvgText(nvgCtx, px + pad + 2, curY + otherLblH / 2, "\u{25C6} 升级")
        curY = curY + otherLblH

        -- 道具网格
        for oi = 1, #otherItems do
            local item = otherItems[oi]
            local col = (oi - 1) % otherCols
            local row = math.floor((oi - 1) / otherCols)
            local ox = px + pad + col * (otherCellW + otherGap)
            local oy = curY + row * (otherCellH + otherGap)
            local canBuy = player.gold >= item.cost

            if oy + otherCellH >= listY and oy <= listY + listH then
                -- 格子背景
                local bgA = canBuy and 150 or 70
                drawRoundRect(ox, oy, otherCellW, otherCellH, 5, 32, 28, 52, bgA)

                -- 图标（左侧，优先图片）
                local iconFs = math.max(14, otherCellH * 0.32)
                local iconX = ox + otherCellH * 0.3
                local iconY = oy + otherCellH * 0.45
                if not (item.iconId and spr.drawIcon(item.iconId, iconX, iconY, iconFs)) then
                    drawTextCenter(item.icon, iconX, iconY, iconFs, item.r, item.g, item.b)
                end

                -- 名称（图标右侧）
                local nameFs = math.max(9, otherCellH * 0.22)
                local descFs = math.max(7, otherCellH * 0.17)
                local textX = ox + otherCellH * 0.56
                nvgFontSize(nvgCtx, nameFs)
                nvgFontFace(nvgCtx, "sans")
                nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvgCtx, nvgRGBA(canBuy and 255 or 140, canBuy and 255 or 140, canBuy and 255 or 140, canBuy and 250 or 160))
                nvgText(nvgCtx, textX, oy + otherCellH * 0.28, item.name)

                -- 描述
                nvgFontSize(nvgCtx, descFs)
                nvgFillColor(nvgCtx, nvgRGBA(170, 170, 195, canBuy and 200 or 110))
                nvgText(nvgCtx, textX, oy + otherCellH * 0.52, item.desc)

                -- 价格（底部右侧）
                local priceW = math.max(36, otherCellW * 0.33)
                local priceH = math.max(18, otherCellH * 0.28)
                local priceX = ox + otherCellW - priceW - 4
                local priceY = oy + otherCellH - priceH - 4
                if canBuy then
                    drawRoundRect(priceX, priceY, priceW, priceH, 3, 45, 125, 40, 220)
                else
                    drawRoundRect(priceX, priceY, priceW, priceH, 3, 65, 50, 50, 130)
                end
                local pFs = math.max(8, priceH * 0.55)
                if canBuy then
                    drawTextCenter(tostring(item.cost) .. "G", priceX + priceW / 2, priceY + priceH / 2, pFs, 255, 225, 80)
                else
                    drawTextCenter(tostring(item.cost) .. "G", priceX + priceW / 2, priceY + priceH / 2, pFs, 120, 100, 80)
                end

                -- 整个格子可点击
                table.insert(shopItemRects, {x = ox, y = oy, w = otherCellW, h = otherCellH, index = item._origIdx})
            end
        end
    end

    nvgRestore(nvgCtx)

    -- 底部关闭按钮
    local closeBtnW = math.max(90, panelW * 0.38)
    local closeBtnH = math.max(28, footerH * 0.72)
    local closeBtnX = px + (panelW - closeBtnW) / 2
    local closeBtnY = py + panelH - footerH + (footerH - closeBtnH) / 2 - 2
    drawRoundRect(closeBtnX, closeBtnY, closeBtnW, closeBtnH, 6, 110, 50, 50, 220)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, closeBtnX, closeBtnY, closeBtnW, closeBtnH, 6)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 120, 120, 80))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    local closeFs = math.max(10, closeBtnH * 0.5)
    drawTextCenter("\u{5173}\u{95ED}\u{5546}\u{5E97}", closeBtnX + closeBtnW / 2, closeBtnY + closeBtnH / 2, closeFs, 255, 210, 210)
    shopCloseRect = {x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH}
end

function drawCardBook()
    if not cardBook.open then return end
    cardBook.cardRects = {}

    local totalOwned = #player.cards
    local cardH = math.floor(math.max(110, math.min(logicalH * 0.22, 160)) * 1.25)
    local cardW = math.floor(cardH * 0.68)
    local gap = 8
    local cols = math.max(2, math.min(5, math.floor((logicalW * 0.88) / (cardW + gap))))
    local rows = math.ceil(totalOwned / cols)
    local gridW = cols * cardW + (cols - 1) * gap
    local gridH = rows * (cardH + gap)

    local titleH = math.max(28, logicalH * 0.05)
    local footerH = math.max(22, logicalH * 0.035)
    local panelW = gridW + 24
    local panelH = math.min(logicalH * 0.9, titleH + gridH + footerH + 20)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 内容区域（标题和底部之间）
    local contentTop = py + titleH
    local contentH = panelH - titleH - footerH
    local scrollMax = math.max(0, gridH + 10 - contentH)
    cardBook.scroll = math.max(0, math.min(cardBook.scroll, scrollMax))

    -- 全屏遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 150)

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 8, 30, 28, 50, 240)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 8)
    nvgStrokeColor(nvgCtx, nvgRGBA(180, 140, 60, 180))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 统计宝石数量
    local gemCount = 0
    for _, v in pairs(player.gems) do gemCount = gemCount + (v or 0) end

    local titleFs = math.max(13, titleH * 0.55)
    local titleStr = "我的牌组 (" .. totalOwned .. "张)"
    if gemCount > 0 then
        titleStr = titleStr .. " 宝石:" .. gemCount
    end
    drawTextCenter(titleStr, px + panelW / 2, py + titleH / 2, titleFs, 255, 220, 120)

    -- 分隔线
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, px + 8, py + titleH)
    nvgLineTo(nvgCtx, px + panelW - 8, py + titleH)
    nvgStrokeColor(nvgCtx, nvgRGBA(180, 140, 60, 100))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 裁剪内容区域（scissor）
    nvgSave(nvgCtx)
    nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)

    -- 卡牌网格（每张卡独立显示）
    local startX = px + (panelW - gridW) / 2
    local startY = contentTop + 6 - cardBook.scroll

    for idx, c in ipairs(player.cards) do
        local def = CARD_DEF[c.id]
        if not def then goto continue end

        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        local cx = startX + col * (cardW + gap)
        local cy = startY + row * (cardH + gap)

        -- 跳过完全不可见的卡牌
        if cy + cardH < contentTop or cy > contentTop + contentH then
            goto continue
        end

        -- 构造卡牌信息（带宝石）
        local cardInfo = {id = c.id, gem = c.gem}

        -- 使用统一 drawCard 渲染
        drawCard(cx, cy, cardW, cardH, cardInfo, false, false)

        -- 记录点击区域（cardIdx 直接对应 player.cards 索引）
        table.insert(cardBook.cardRects, {x = cx, y = cy, w = cardW, h = cardH, cardIdx = idx})

        ::continue::
    end

    nvgRestore(nvgCtx)

    -- 滚动条指示器（仅可滚动时显示）
    if scrollMax > 0 then
        local barH = math.max(20, contentH * (contentH / (gridH + 10)))
        local barY = contentTop + (contentH - barH) * (cardBook.scroll / scrollMax)
        local barX = px + panelW - 6
        drawRoundRect(barX, barY, 3, barH, 2, 180, 140, 60, 120)
    end

    -- 底部提示
    local footFs = math.max(9, titleFs * 0.75)
    local hintText = "点击卡牌查看详情 · 滑动浏览"
    if not scrollMax or scrollMax <= 0 then hintText = "点击卡牌查看详情 · 点击空白关闭" end
    drawTextCenter(hintText, px + panelW / 2, py + panelH - footerH / 2, footFs, 150, 150, 180)

    -- === 选中卡牌放大预览 + 关键词解释 ===
    cardBook._gemBtnRect = nil
    cardBook._closeRect = nil
    if cardBook.selectedIdx and player.cards[cardBook.selectedIdx] then
        local selCard = player.cards[cardBook.selectedIdx]
        local selDef = CARD_DEF[selCard.id]
        if selDef then
            -- 半透明遮罩
            drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 120)

            -- 放大卡牌
            local prevH = math.min(logicalH * 0.4, 220)
            local prevW = math.floor(prevH * 0.68)
            local prevX = logicalW * 0.5 - prevW - 10  -- 居中偏左
            local prevY = (logicalH - prevH) / 2
            local cardInfo = {id = selCard.id, gem = selCard.gem}
            drawCard(prevX, prevY, prevW, prevH, cardInfo, true, false)

            -- 卡牌右上角关键词解释框：右下角对齐卡牌右上角，并略微左下移避免压住关闭按钮
            local tips = collectKeywordTips(selDef)
            local glossMaxW = math.min(math.max(prevW * 1.2, 180), logicalW - 20, 260)
            local glossFs = math.max(9, prevH * 0.045)
            if glossMaxW > 60 and #tips > 0 then
                local cardTopRightX = prevX + prevW
                local glossRightX = math.max(glossMaxW + 5, math.min(cardTopRightX - 14, logicalW - 5))
                local glossBottomY = math.max(18, prevY + 16)
                drawKeywordGlossary(tips, glossRightX, glossBottomY, glossMaxW, glossFs, true, true)
            end

            -- 宝石镶嵌按钮（卡牌下方）：空槽可直接镶嵌；更换已有宝石需要宝石工匠锤
            local hasGemToSocket = gemCount > 0
            local canManageGem = hasGemToSocket or selCard.gem
            if canManageGem then
                local btnW = math.min(prevW, 120)
                local btnH = math.max(24, prevH * 0.1)
                local btnX = prevX + (prevW - btnW) / 2
                local btnY = prevY + prevH + 8
                local lockedReplace = selCard.gem and not player.relics.gemCraft
                if lockedReplace then
                    drawRoundRect(btnX, btnY, btnW, btnH, 4, 70, 60, 60, 210)
                else
                    drawRoundRect(btnX, btnY, btnW, btnH, 4, 60, 50, 100, 220)
                end
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, btnX, btnY, btnW, btnH, 4)
                nvgStrokeColor(nvgCtx, lockedReplace and nvgRGBA(180, 120, 100, 180) or nvgRGBA(140, 130, 220, 200))
                nvgStrokeWidth(nvgCtx, 1.5)
                nvgStroke(nvgCtx)
                local gemBtnFs = math.max(9, btnH * 0.5)
                local gemLabel
                if lockedReplace then
                    gemLabel = "需工匠锤"
                elseif selCard.gem then
                    gemLabel = "更换宝石"
                else
                    gemLabel = "镶嵌宝石"
                end
                drawTextCenter(gemLabel, btnX + btnW / 2, btnY + btnH / 2, gemBtnFs,
                    lockedReplace and 230 or 200, lockedReplace and 170 or 190, lockedReplace and 140 or 255)
                cardBook._gemBtnRect = {x = btnX, y = btnY, w = btnW, h = btnH, locked = lockedReplace}
            end

            -- 关闭按钮（卡牌右上角内侧）
            local closeR = math.max(12, prevH * 0.07)
            local closeX = prevX + prevW - closeR * 0.15
            local closeY = prevY + closeR * 0.15
            nvgBeginPath(nvgCtx)
            nvgCircle(nvgCtx, closeX, closeY, closeR)
            nvgFillColor(nvgCtx, nvgRGBA(80, 60, 60, 220))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(200, 150, 150, 200))
            nvgStrokeWidth(nvgCtx, 1.5)
            nvgStroke(nvgCtx)
            local xFs = math.max(10, closeR * 1.0)
            drawTextCenter("X", closeX, closeY, xFs, 220, 180, 180)
            cardBook._closeRect = {x = closeX - closeR, y = closeY - closeR, w = closeR * 2, h = closeR * 2}
        end
    end

    -- === 宝石选择面板（覆盖在图鉴上方） ===
    if gemPanel.open and gemPanel.cardIdx then
        gemPanel.rects = {}
        gemPanel.removeRect = nil
        local card = player.cards[gemPanel.cardIdx]
        if not card then
            gemPanel.open = false
        else
            local cdef = CARD_DEF[card.id]
            local gpW = math.min(logicalW * 0.82, 320)
            -- 计算有多少种宝石可用
            local gemList = {}
            for gid, _ in pairs(GEM_DEF) do
                if (player.gems[gid] or 0) > 0 then
                    table.insert(gemList, gid)
                end
            end
            table.sort(gemList)
            local gemRows = math.ceil(#gemList / 3)
            local rowH2 = math.max(36, logicalH * 0.055)
            local headerH = math.max(36, logicalH * 0.06)
            local removeH = card.gem and rowH2 or 0
            local emptyH = #gemList == 0 and rowH2 or 0
            local gpH = headerH + gemRows * rowH2 + removeH + emptyH + 16
            local gpX = (logicalW - gpW) / 2
            local gpY = (logicalH - gpH) / 2

            -- 面板背景
            drawRoundRect(gpX, gpY, gpW, gpH, 10, 20, 18, 40, 245)
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, gpX, gpY, gpW, gpH, 10)
            nvgStrokeColor(nvgCtx, nvgRGBA(140, 200, 255, 180))
            nvgStrokeWidth(nvgCtx, 2)
            nvgStroke(nvgCtx)

            -- 标题
            local gpFs = math.max(11, headerH * 0.45)
            local cardName = cdef and cdef.name or card.id
            local gemSlotStr = cardName
            if card.gem and GEM_DEF[card.gem] then
                gemSlotStr = gemSlotStr .. " [" .. GEM_DEF[card.gem].name .. "]"
            else
                gemSlotStr = gemSlotStr .. " [空槽◇]"
            end
            drawTextCenter(gemSlotStr, gpX + gpW / 2, gpY + headerH / 2, gpFs, 200, 220, 255)

            -- 分隔线
            nvgBeginPath(nvgCtx)
            nvgMoveTo(nvgCtx, gpX + 10, gpY + headerH)
            nvgLineTo(nvgCtx, gpX + gpW - 10, gpY + headerH)
            nvgStrokeColor(nvgCtx, nvgRGBA(140, 200, 255, 80))
            nvgStrokeWidth(nvgCtx, 1)
            nvgStroke(nvgCtx)

            -- 宝石列表（3列）
            local gemItemW = (gpW - 20) / 3
            local curY2 = gpY + headerH + 4
            local itemFs = math.max(9, rowH2 * 0.38)

            if #gemList == 0 then
                if card.gem and GEM_DEF[card.gem] then
                    -- 已装备宝石：显示当前宝石详情
                    local gd = GEM_DEF[card.gem]
                    local curGemTxt = "当前: " .. gd.name
                    local curGemCX = gpX + gpW / 2
                    local curGemCY = curY2 + rowH2 * 0.35
                    spr.drawIcon(gd.iconId, curGemCX - nvgTextBounds(nvgCtx, 0, 0, curGemTxt) / 2 - itemFs * 0.55, curGemCY, itemFs * 0.85)
                    drawTextCenter(curGemTxt, curGemCX, curGemCY, itemFs, gd.r, gd.g, gd.b)
                    local descFs2 = math.max(6, itemFs * 0.6)
                    drawTextCenter(gd.desc, gpX + gpW / 2, curY2 + rowH2 * 0.72, descFs2, 180, 180, 200)
                else
                    drawTextCenter("暂无宝石", gpX + gpW / 2, curY2 + rowH2 / 2, itemFs, 150, 150, 180)
                end
                curY2 = curY2 + rowH2
            else
                for gi, gid in ipairs(gemList) do
                    local gd = GEM_DEF[gid]
                    local gcol = (gi - 1) % 3
                    local grow = math.floor((gi - 1) / 3)
                    local gx = gpX + 10 + gcol * gemItemW
                    local gy = curY2 + grow * rowH2
                    local gw = gemItemW - 4
                    local gh = rowH2 - 4

                    -- 背景
                    local isCurrentGem = (card.gem == gid)
                    if isCurrentGem then
                        drawRoundRect(gx, gy, gw, gh, 5, gd.r, gd.g, gd.b, 60)
                    else
                        drawRoundRect(gx, gy, gw, gh, 5, 40, 38, 60, 200)
                    end
                    nvgBeginPath(nvgCtx)
                    nvgRoundedRect(nvgCtx, gx, gy, gw, gh, 5)
                    nvgStrokeColor(nvgCtx, nvgRGBA(gd.r, gd.g, gd.b, 160))
                    nvgStrokeWidth(nvgCtx, 1)
                    nvgStroke(nvgCtx)

                    -- 图标+名称+数量
                    local cnt2 = player.gems[gid] or 0
                    local gemLabel = gd.name .. " x" .. cnt2
                    local gemLabelW = nvgTextBounds(nvgCtx, 0, 0, gemLabel)
                    local gemCX = gx + gw / 2
                    local gemCY = gy + gh * 0.35
                    spr.drawIcon(gd.iconId, gemCX - gemLabelW / 2 - itemFs * 0.55, gemCY, itemFs * 0.9)
                    drawTextCenter(gemLabel, gemCX + itemFs * 0.3, gemCY, itemFs, 255, 255, 255)
                    -- 效果描述
                    local descFs = math.max(6, itemFs * 0.6)
                    drawTextCenter(gd.desc, gx + gw / 2, gy + gh * 0.7, descFs, 180, 180, 200)

                    table.insert(gemPanel.rects, {x = gx, y = gy, w = gw, h = gh, gemId = gid})
                end
                curY2 = curY2 + gemRows * rowH2
            end

            -- 拆卸按钮（仅已镶嵌时显示）
            if card.gem then
                local rmX = gpX + gpW * 0.2
                local rmW = gpW * 0.6
                local rmY = curY2 + 2
                local rmH = rowH2 - 6
                drawRoundRect(rmX, rmY, rmW, rmH, 5, 120, 40, 40, 200)
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, rmX, rmY, rmW, rmH, 5)
                nvgStrokeColor(nvgCtx, nvgRGBA(255, 100, 100, 160))
                nvgStrokeWidth(nvgCtx, 1)
                nvgStroke(nvgCtx)
                drawTextCenter("拆卸宝石", rmX + rmW / 2, rmY + rmH / 2, itemFs, 255, 200, 200)
                gemPanel.removeRect = {x = rmX, y = rmY, w = rmW, h = rmH}
            end
        end
    end
end

-- ============================================================
-- 牌库/弃牌堆查看弹窗
-- ============================================================
function drawPileView()
    if not pileView.open or not battle.active then return end

    local pile = pileView.pileType == "deck" and battle.deck or battle.discard
    local titleText = pileView.pileType == "deck"
        and ("牌库 (" .. #pile .. "张)")
        or  ("弃牌堆 (" .. #pile .. "张)")
    local titleR = pileView.pileType == "deck" and 150 or 180
    local titleG = pileView.pileType == "deck" and 180 or 150
    local titleB = 220

    local cardH = math.floor(math.max(110, math.min(logicalH * 0.22, 160)) * 1.25)
    local cardW = math.floor(cardH * 0.68)
    local gap = 8
    local cols = math.max(2, math.min(5, math.floor((logicalW * 0.88) / (cardW + gap))))
    local rows = math.max(1, math.ceil(#pile / cols))
    local gridW = cols * cardW + (cols - 1) * gap
    local gridH = rows * (cardH + gap)

    local titleH = math.max(28, logicalH * 0.05)
    local footerH = math.max(22, logicalH * 0.035)
    local panelW = gridW + 24
    local panelH = math.min(logicalH * 0.9, titleH + gridH + footerH + 20)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    local contentTop = py + titleH
    local contentH = panelH - titleH - footerH
    local scrollMax = math.max(0, gridH + 10 - contentH)
    pileView.scroll = math.max(0, math.min(pileView.scroll, scrollMax))

    -- 全屏遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 150)

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 8, 30, 28, 50, 240)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 8)
    nvgStrokeColor(nvgCtx, nvgRGBA(titleR, titleG, titleB, 180))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 标题
    local titleFs = math.max(13, titleH * 0.55)
    drawTextCenter(titleText, px + panelW / 2, py + titleH / 2, titleFs, titleR, titleG, titleB)

    -- 分隔线
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, px + 8, py + titleH)
    nvgLineTo(nvgCtx, px + panelW - 8, py + titleH)
    nvgStrokeColor(nvgCtx, nvgRGBA(titleR, titleG, titleB, 100))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)

    -- 裁剪内容区域
    nvgSave(nvgCtx)
    nvgIntersectScissor(nvgCtx, px, contentTop, panelW, contentH)

    if #pile == 0 then
        -- 空牌堆提示
        local emptyFs = math.max(11, titleFs * 0.85)
        drawTextCenter("（空）", px + panelW / 2, contentTop + contentH / 2, emptyFs, 120, 120, 150)
    else
        -- 卡牌网格
        local startX = px + (panelW - gridW) / 2
        local startY = contentTop + 6 - pileView.scroll

        for idx, c in ipairs(pile) do
            local def = CARD_DEF[c.id]
            if not def then goto continuePile end

            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local cx = startX + col * (cardW + gap)
            local cy = startY + row * (cardH + gap)

            -- 跳过不可见卡牌
            if cy + cardH < contentTop or cy > contentTop + contentH then
                goto continuePile
            end

            drawCard(cx, cy, cardW, cardH, {id = c.id, gem = c.gem}, false, false)

            ::continuePile::
        end
    end

    nvgRestore(nvgCtx)

    -- 滚动条
    if scrollMax > 0 then
        local barH = math.max(20, contentH * (contentH / (gridH + 10)))
        local barY = contentTop + (contentH - barH) * (pileView.scroll / scrollMax)
        local barX = px + panelW - 6
        drawRoundRect(barX, barY, 3, barH, 2, titleR, titleG, titleB, 120)
    end

    -- 底部提示
    local footFs = math.max(9, titleFs * 0.75)
    local hintText = "点击空白关闭"
    drawTextCenter(hintText, px + panelW / 2, py + panelH - footerH / 2, footFs, 150, 150, 180)
end

-- ============================================================
-- 升级选卡弹窗
-- ============================================================
-- levelUp.cardRects / levelUp.confirmRect 在表中声明

function drawLevelUpPopup()
    if not levelUp.open or #levelUp.candidates == 0 then return end

    levelUp.cardRects = {}

    -- 半透明遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 160)

    -- 面板尺寸
    local panelW = math.min(logicalW * 0.92, 500)
    local panelH = math.min(logicalH * 0.65, 420)
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 12, 25, 20, 50, 240)
    -- 边框
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 12)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 220, 80, 200))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 标题
    local titleFs = math.max(14, panelH * 0.08)
    drawTextCenter("升级！Lv." .. player.level, px + panelW / 2, py + panelH * 0.08, titleFs, 255, 220, 80)

    -- 副标题
    local subFs = math.max(10, titleFs * 0.7)
    local pendingText = ""
    if levelUp.pendingCount > 1 then
        pendingText = "  (还有" .. (levelUp.pendingCount - 1) .. "次)"
    end
    drawTextCenter("选择一张卡牌加入牌组" .. pendingText, px + panelW / 2, py + panelH * 0.16, subFs, 200, 200, 220)

    -- 三张卡牌横排
    local cardCount = #levelUp.candidates
    local cardW = math.floor(math.min(panelW * 0.28, 120) * 1.25)
    local cardH = cardW * 1.5
    local gap = (panelW - cardW * cardCount) / (cardCount + 1)
    local cardY = py + panelH * 0.22

    for i, cardId in ipairs(levelUp.candidates) do
        local def = CARD_DEF[cardId]
        if not def then goto continue end

        local cx = px + gap * i + cardW * (i - 1)
        local isSelected = (levelUp.selectedIndex == i)

        -- 选中时上浮
        local drawY = cardY
        if isSelected then drawY = cardY - cardH * 0.06 end

        -- 存储点击区域
        table.insert(levelUp.cardRects, {x = cx, y = drawY, w = cardW, h = cardH, index = i})

        -- 使用统一 drawCard 渲染
        drawCard(cx, drawY, cardW, cardH, {id = cardId}, isSelected, false)

        -- 选中卡牌时显示关键字解释框（卡牌上方）
        if isSelected and def then
            local tips = collectKeywordTips(def)
            if #tips > 0 then
                local glossMaxW = math.min(math.max(cardW * 1.3, 160), panelW * 0.6, 240)
                local glossX = cx + (cardW - glossMaxW) / 2
                glossX = math.max(px + 4, math.min(glossX, px + panelW - glossMaxW - 4))
                local glossFs = math.max(8, cardH * 0.045)
                local glossBottomY = drawY - 4
                drawKeywordGlossary(tips, glossX, glossBottomY, glossMaxW, glossFs, true)
            end
        end

        ::continue::
    end

    -- 确认按钮（选中卡牌后显示）
    -- 底部按钮区域（刷新 + 确认选择 并排）
    local btnH = math.max(28, panelH * 0.1)
    local btnY = py + panelH - btnH - panelH * 0.06
    local btnGap = 10
    local showRefresh = levelUp.adRefreshUsed < 1
    local hasSelection = levelUp.selectedIndex and levelUp.selectedIndex >= 1 and levelUp.selectedIndex <= cardCount

    if showRefresh and hasSelection then
        -- 两个按钮并排
        local totalW = panelW * 0.8
        local eachW = (totalW - btnGap) / 2
        local startX = px + (panelW - totalW) / 2

        -- 看广告刷新（左）
        local rfX, rfW = startX, eachW
        drawRoundRect(rfX, btnY, rfW, btnH, 6, 80, 60, 140, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, rfX, btnY, rfW, btnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(180, 160, 255, 200))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
        local rfFs = math.max(11, btnH * 0.45)
        drawTextCenter("看广告刷新", rfX + rfW / 2, btnY + btnH / 2, rfFs, 220, 210, 255)
        levelUp.refreshRect = {x = rfX, y = btnY, w = rfW, h = btnH}

        -- 确认选择（右）
        local cfX, cfW = startX + eachW + btnGap, eachW
        drawRoundRect(cfX, btnY, cfW, btnH, 6, 60, 180, 80, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cfX, btnY, cfW, btnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(120, 255, 140, 200))
        nvgStrokeWidth(nvgCtx, 2)
        nvgStroke(nvgCtx)
        local cfFs = math.max(12, btnH * 0.5)
        drawTextCenter("确认选择", cfX + cfW / 2, btnY + btnH / 2, cfFs, 255, 255, 255)
        levelUp.confirmRect = {x = cfX, y = btnY, w = cfW, h = btnH}

    elseif showRefresh then
        -- 只有刷新按钮（未选卡）
        local rfW = math.min(panelW * 0.5, 160)
        local rfX = px + (panelW - rfW) / 2
        drawRoundRect(rfX, btnY, rfW, btnH, 6, 80, 60, 140, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, rfX, btnY, rfW, btnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(180, 160, 255, 200))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)
        local rfFs = math.max(11, btnH * 0.45)
        drawTextCenter("看广告刷新", rfX + rfW / 2, btnY + btnH / 2, rfFs, 220, 210, 255)
        levelUp.refreshRect = {x = rfX, y = btnY, w = rfW, h = btnH}
        levelUp.confirmRect = nil

    elseif hasSelection then
        -- 只有确认按钮（刷新已用完）
        local cfW = math.min(panelW * 0.5, 160)
        local cfX = px + (panelW - cfW) / 2
        drawRoundRect(cfX, btnY, cfW, btnH, 6, 60, 180, 80, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cfX, btnY, cfW, btnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(120, 255, 140, 200))
        nvgStrokeWidth(nvgCtx, 2)
        nvgStroke(nvgCtx)
        local cfFs = math.max(12, btnH * 0.5)
        drawTextCenter("确认选择", cfX + cfW / 2, btnY + btnH / 2, cfFs, 255, 255, 255)
        levelUp.confirmRect = {x = cfX, y = btnY, w = cfW, h = btnH}
        levelUp.refreshRect = nil
    else
        levelUp.confirmRect = nil
        levelUp.refreshRect = nil
    end
end

-- ============================================================
-- 开发者面板
-- ============================================================
-- 面板按钮定义（用于渲染和点击检测共享）
local DEV_BUTTONS = {}  -- 每帧重建

function buildDevButtons()
    DEV_BUTTONS = {}
    local pw = math.min(logicalW * 0.96, 440)
    local ph = math.min(logicalH * 0.95, 780)
    local px = (logicalW - pw) / 2
    local py = (logicalH - ph) / 2
    local fs = math.max(11, ph * 0.028)
    local btnH = math.max(22, fs * 2.0)
    local btnPad = 3
    local contentX = px + 10
    local contentW = pw - 20
    local curY = py + fs * 2.2 + dev.scroll

    -- 辅助函数：添加一行按钮
    local function addRow(label, buttons)
        -- label
        local row = {y = curY, h = btnH, label = label, items = {}}
        local btnAreaX = contentX + contentW * 0.28
        local btnAreaW = contentW * 0.72
        local btnW = math.floor((btnAreaW - (# buttons - 1) * btnPad) / #buttons)
        for idx, btn in ipairs(buttons) do
            local bx = btnAreaX + (idx - 1) * (btnW + btnPad)
            table.insert(row.items, {
                x = bx, y = curY, w = btnW, h = btnH,
                text = btn.text, action = btn.action,
                r = btn.r or 60, g = btn.g or 100, b = btn.b or 160,
            })
        end
        table.insert(DEV_BUTTONS, row)
        curY = curY + btnH + btnPad + 1
    end

    -- === 工具按钮（置顶） ===
    addRow("工具", {
        {text = "地图编辑", action = function() dev.mode = false; gameState = "editor" end, r=50,g=100,b=140},
        {text = "卡牌调试", action = function() dev.mode = false; cardDev.active = true; cardDev.exportText = nil end, r=80,g=60,b=140},
        {text = "关闭面板", action = function() dev.mode = false end, r=100,g=50,b=50},
    })
    curY = curY + 4

    -- === 属性调整 ===
    addRow("HP", {
        {text = "-100", action = function() player.hp = math.max(1, player.hp - 100) end, r=160,g=60,b=60},
        {text = "+100", action = function() player.hp = player.hp + 100 end, r=60,g=140,b=60},
        {text = "+1000", action = function() player.hp = player.hp + 1000 end, r=60,g=180,b=60},
    })
    addRow("ATK", {
        {text = "-5", action = function() player.atk = math.max(1, player.atk - 5) end, r=160,g=60,b=60},
        {text = "+5", action = function() player.atk = player.atk + 5 end, r=60,g=140,b=60},
        {text = "+50", action = function() player.atk = player.atk + 50 end, r=60,g=180,b=60},
    })
    addRow("DEF", {
        {text = "-5", action = function() player.def = math.max(0, player.def - 5) end, r=160,g=60,b=60},
        {text = "+5", action = function() player.def = player.def + 5 end, r=60,g=140,b=60},
        {text = "+50", action = function() player.def = player.def + 50 end, r=60,g=180,b=60},
    })
    addRow("金币", {
        {text = "+50", action = function() player.gold = player.gold + 50 end, r=180,g=160,b=40},
        {text = "+500", action = function() player.gold = player.gold + 500 end, r=200,g=180,b=40},
    })
    addRow("钥匙", {
        {text = "+黄", action = function() player.yellowKeys = player.yellowKeys + 1 end, r=180,g=160,b=40},
        {text = "+蓝", action = function() player.blueKeys = player.blueKeys + 1 end, r=60,g=120,b=200},
        {text = "+红", action = function() player.redKeys = player.redKeys + 1 end, r=180,g=50,b=50},
    })

    -- 分隔
    curY = curY + 4

    -- === 楼层跳转 ===
    addRow("楼层", {
        {text = "-5", action = function()
            player.floor = math.max(1, player.floor - 5)
            playBgmForFloor(player.floor)
            local sr, sc = findTile(player.floor, 'D')
            if sr then player.row = sr; player.col = sc end
        end, r=160,g=100,b=60},
        {text = "-1", action = function()
            player.floor = math.max(1, player.floor - 1)
            playBgmForFloor(player.floor)
            local sr, sc = findTile(player.floor, 'D')
            if sr then player.row = sr; player.col = sc end
        end, r=140,g=80,b=60},
        {text = "+1", action = function()
            player.floor = math.min(getContentMaxFloor(), player.floor + 1)
            playBgmForFloor(player.floor)
            local sr, sc = findTile(player.floor, 'U')
            if not sr then sr, sc = findTile(player.floor, 'D') end
            if sr then player.row = sr; player.col = sc end
        end, r=60,g=120,b=60},
        {text = "+5", action = function()
            player.floor = math.min(getContentMaxFloor(), player.floor + 5)
            playBgmForFloor(player.floor)
            local sr, sc = findTile(player.floor, 'U')
            if not sr then sr, sc = findTile(player.floor, 'D') end
            if sr then player.row = sr; player.col = sc end
        end, r=60,g=160,b=60},
    })

    curY = curY + 4

    -- === 添加卡牌（自动收集所有非物品、非诅咒卡牌） ===
    local cardIds = {}
    for cid, cd in pairs(CARD_DEF) do
        if cd.type ~= "item" and cd.type ~= "curse" then
            table.insert(cardIds, cid)
        end
    end
    table.sort(cardIds, function(a, b)
        local ra = ({common=1,uncommon=2,rare=3,epic=4,legendary=5})[CARD_DEF[a].rarity or "common"] or 1
        local rb = ({common=1,uncommon=2,rare=3,epic=4,legendary=5})[CARD_DEF[b].rarity or "common"] or 1
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    -- 每行4张卡牌
    for ci = 1, #cardIds, 4 do
        local rowBtns = {}
        for j = 0, 3 do
            local cid = cardIds[ci + j]
            if cid then
                local cd = CARD_DEF[cid]
                table.insert(rowBtns, {
                    text = "+" .. cd.name,
                    action = function() table.insert(player.cards, {id = cid, usesLeft = cd.maxUses}); showMessage("获得卡牌【"..cd.name.."】", 1.5, cd.r, cd.g, cd.b) end,
                    r = math.floor(cd.r * 0.5), g = math.floor(cd.g * 0.5), b = math.floor(cd.b * 0.5),
                })
            end
        end
        local label = ci == 1 and "卡牌" or ""
        addRow(label, rowBtns)
    end

    curY = curY + 4

    -- === 测试战斗（单怪） ===
    local monsterChars = {"1","2","3","4","5","6","8","9","A","C","7"}
    for mi = 1, #monsterChars, 3 do
        local rowBtns = {}
        for j = 0, 2 do
            local mch = monsterChars[mi + j]
            if mch then
                local md = MONSTER_DEF[mch]
                table.insert(rowBtns, {
                    text = md.name:sub(1,6),
                    action = function() dev.mode = false; startDevBattle({mch}) end,
                    r = math.floor(md.r * 0.4), g = math.floor(md.g * 0.4), b = math.floor(md.b * 0.4),
                })
            end
        end
        local label = mi == 1 and "战斗" or ""
        addRow(label, rowBtns)
    end

    curY = curY + 4

    -- === 测试战斗（多怪编队） ===
    local multiFormations = {
        {text = "2x绿史", chars = {"1","1"}, r=40,g=120,b=40},
        {text = "2x红史", chars = {"2","2"}, r=160,g=40,b=40},
        {text = "绿+红", chars = {"1","2"}, r=100,g=80,b=40},
        {text = "3x绿史", chars = {"1","1","1"}, r=40,g=140,b=40},
        {text = "3x混合", chars = {"1","2","3"}, r=100,g=80,b=60},
        {text = "4x绿史", chars = {"1","1","1","1"}, r=40,g=160,b=40},
        {text = "4x混合", chars = {"2","3","4","5"}, r=120,g=60,b=80},
        {text = "2x骷髅", chars = {"4","4"}, r=100,g=100,b=100},
        {text = "2xBoss", chars = {"7","7"}, r=120,g=40,b=120},
    }
    for fi = 1, #multiFormations, 3 do
        local rowBtns = {}
        for j = 0, 2 do
            local f = multiFormations[fi + j]
            if f then
                table.insert(rowBtns, {
                    text = f.text,
                    action = function() dev.mode = false; startDevBattle(f.chars) end,
                    r = f.r, g = f.g, b = f.b,
                })
            end
        end
        local label = fi == 1 and "编队" or ""
        addRow(label, rowBtns)
    end

    -- 记录内容总高度并限制滚动范围
    local contentTop = py + fs * 2.2
    local visibleH = ph - fs * 2.2 - fs * 1.5  -- 减去标题和底部提示
    dev.contentH = curY - dev.scroll - contentTop  -- 实际内容高度（去掉scroll偏移）
    local scrollMax = math.max(0, dev.contentH - visibleH)
    dev.scroll = math.max(-0, math.min(dev.scroll, scrollMax))

    return px, py, pw, ph, fs
end

-- ============================================================
-- 卡牌开发者工具
-- ============================================================
cardDev.regions = {"name", "image", "desc", "mana", "frame", "card"}
cardDev.regionLabels = {name="名称栏", image="插画区", desc="描述区", mana="费用宝石", frame="边框", card="卡牌大小"}
cardDev.colors = {
    name  = {80, 200, 255},
    image = {100, 255, 100},
    desc  = {255, 200, 80},
    mana  = {255, 100, 200},
    frame = {255, 160, 80},
    card  = {255, 255, 255},
}

--- 获取区域在卡牌预览坐标中的矩形 {x,y,w,h}
function cardDev.regionRect(region, cx, cy, cw, ch)
    local p = cardDev.p
    if region == "name" then
        local ox = cw * (p.nameOffX or 0)
        return {x = cx + ox, y = cy + ch * p.nameTop, w = cw, h = ch * (p.nameBot - p.nameTop)}
    elseif region == "image" then
        local mx = cw * p.imgMarginX
        local ox = cw * (p.imgOffX or 0)
        return {x = cx + mx + ox, y = cy + ch * p.imgTop, w = cw - mx * 2, h = ch * (p.imgBot - p.imgTop)}
    elseif region == "desc" then
        local dx = cw * p.descPadX
        local ox = cw * (p.descOffX or 0)
        return {x = cx + dx + ox, y = cy + ch * p.descTop, w = cw - dx * 2, h = ch * (p.descBot - p.descTop)}
    elseif region == "mana" then
        local sz = ch * p.manaSize
        return {x = cx + cw * p.manaX, y = cy + ch * p.manaY, w = sz, h = sz}
    elseif region == "frame" then
        local fpx = cw * p.framePadX
        local fpy = ch * p.framePadY
        return {x = cx + fpx, y = cy + fpy, w = cw - fpx * 2, h = ch - fpy * 2}
    elseif region == "card" then
        return {x = cx, y = cy, w = cw, h = ch}
    end
end

function cardDev.draw()
    if not cardDev.active then return end

    -- 全屏遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 15, 13, 25, 240)

    local fs = math.max(10, logicalH * 0.022)
    local isPortrait = logicalH > logicalW

    -- 卡牌预览区（左侧/上侧）
    local cardH, cardW
    if isPortrait then
        cardH = logicalH * 0.50
        cardW = cardH * 0.746
    else
        cardH = logicalH * 0.78
        cardW = cardH * 0.746
    end
    local cx = isPortrait and ((logicalW - cardW) / 2) or (logicalW * 0.05)
    local cy = isPortrait and (fs * 3) or ((logicalH - cardH) / 2)

    -- 绘制预览卡牌（使用drawCard）
    local previewInfo = {id = cardDev.previewId, gem = nil, costReduction = 0}
    drawCard(cx, cy, cardW, cardH, previewInfo, false, false)

    -- 叠加区域指示框（跳过 card，因为它就是整张卡牌）
    for i, region in ipairs(cardDev.regions) do
        if region == "card" or region == "frame" then goto continue_region end
        local rc = cardDev.regionRect(region, cx, cy, cardW, cardH)
        local clr = cardDev.colors[region]
        local sel = (cardDev.selected == i)
        nvgBeginPath(nvgCtx)
        nvgRect(nvgCtx, rc.x, rc.y, rc.w, rc.h)
        nvgStrokeColor(nvgCtx, nvgRGBA(clr[1], clr[2], clr[3], sel and 255 or 120))
        nvgStrokeWidth(nvgCtx, sel and 2.5 or 1.2)
        nvgStroke(nvgCtx)
        -- 区域标签
        nvgFontFace(nvgCtx, "sans")
        nvgFontSize(nvgCtx, fs * 0.7)
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(nvgCtx, nvgRGBA(clr[1], clr[2], clr[3], sel and 255 or 160))
        nvgText(nvgCtx, rc.x + 2, rc.y + 1, cardDev.regionLabels[region])
        -- 选中区域加四角拖拽手柄
        if sel then
            local hs = math.max(4, cardW * 0.04)
            local corners = {
                {rc.x, rc.y}, {rc.x + rc.w - hs, rc.y},
                {rc.x, rc.y + rc.h - hs}, {rc.x + rc.w - hs, rc.y + rc.h - hs},
            }
            for _, cn in ipairs(corners) do
                nvgBeginPath(nvgCtx)
                nvgRect(nvgCtx, cn[1], cn[2], hs, hs)
                nvgFillColor(nvgCtx, nvgRGBA(clr[1], clr[2], clr[3], 200))
                nvgFill(nvgCtx)
            end
        end
        ::continue_region::
    end

    -- frame / card 选中时单独绘制指示框
    for _, spRegion in ipairs({"frame", "card"}) do
        local spIdx = (spRegion == "frame") and 5 or 6
        if cardDev.selected == spIdx then
            local rc = cardDev.regionRect(spRegion, cx, cy, cardW, cardH)
            local clr = cardDev.colors[spRegion]
            nvgBeginPath(nvgCtx)
            nvgRect(nvgCtx, rc.x, rc.y, rc.w, rc.h)
            nvgStrokeColor(nvgCtx, nvgRGBA(clr[1], clr[2], clr[3], 255))
            nvgStrokeWidth(nvgCtx, 2.5)
            nvgStroke(nvgCtx)
            -- 标签
            nvgFontFace(nvgCtx, "sans")
            nvgFontSize(nvgCtx, fs * 0.7)
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(nvgCtx, nvgRGBA(clr[1], clr[2], clr[3], 255))
            nvgText(nvgCtx, rc.x + 2, rc.y + 1, cardDev.regionLabels[spRegion])
            -- 四角手柄
            local hs = math.max(4, cardW * 0.04)
            local corners = {
                {rc.x, rc.y}, {rc.x + rc.w - hs, rc.y},
                {rc.x, rc.y + rc.h - hs}, {rc.x + rc.w - hs, rc.y + rc.h - hs},
            }
            for _, cn in ipairs(corners) do
                nvgBeginPath(nvgCtx)
                nvgRect(nvgCtx, cn[1], cn[2], hs, hs)
                nvgFillColor(nvgCtx, nvgRGBA(clr[1], clr[2], clr[3], 200))
                nvgFill(nvgCtx)
            end
        end
    end

    -- 右侧/下侧参数面板
    local panelX, panelY, panelW, panelH
    if isPortrait then
        panelX = 8
        panelY = cy + cardH + fs
        panelW = logicalW - 16
        panelH = logicalH - panelY - fs
    else
        panelX = cx + cardW + logicalW * 0.03
        panelY = cy
        panelW = logicalW - panelX - 8
        panelH = cardH
    end

    -- 面板背景
    drawRoundRect(panelX, panelY, panelW, panelH, 6, 25, 22, 40, 220)

    -- 标题
    local titleFs = fs * 1.1
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, titleFs)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(255, 200, 50, 255))
    nvgText(nvgCtx, panelX + panelW / 2, panelY + 4, "Card Dev Tool")

    -- 参数列表
    local lineH = fs * 1.5
    local startY = panelY + titleFs + 10
    local paramFs = fs * 0.85
    nvgFontSize(nvgCtx, paramFs)
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    local paramLines = {
        {label = "名称栏", items = {
            {"nameTop",  cardDev.p.nameTop},  {"nameBot",  cardDev.p.nameBot},
            {"nameOffX", cardDev.p.nameOffX},
        }},
        {label = "插画区", items = {
            {"imgTop",   cardDev.p.imgTop},   {"imgBot",   cardDev.p.imgBot},
            {"imgMarginX", cardDev.p.imgMarginX}, {"imgOffX", cardDev.p.imgOffX},
        }},
        {label = "描述区", items = {
            {"descTop",  cardDev.p.descTop},  {"descBot",  cardDev.p.descBot},
            {"descPadX", cardDev.p.descPadX}, {"descOffX", cardDev.p.descOffX},
        }},
        {label = "费用宝石", items = {
            {"manaX",    cardDev.p.manaX},    {"manaY",    cardDev.p.manaY},
            {"manaSize", cardDev.p.manaSize},
        }},
    }

    -- 计算战斗中实际卡牌像素尺寸
    local isPortraitCard = logicalH > logicalW
    local baseCardH = isPortraitCard
        and math.max(120, math.min(logicalW * 0.38, 165))
        or  math.max(130, math.min(logicalH * 0.27, 180))
    local baseCardW = math.floor(baseCardH * 0.68)
    baseCardH = math.floor(baseCardH)
    local actualCardH = math.floor(baseCardH * (cardDev.p.cardScale or 1.0))
    local actualCardW = math.floor(actualCardH * 0.68)

    cardDev._labelRects = {}
    local py2 = startY
    for gi, group in ipairs(paramLines) do
        local clr = cardDev.colors[cardDev.regions[gi]]
        local isSel = (cardDev.selected == gi)
        nvgFillColor(nvgCtx, nvgRGBA(clr[1], clr[2], clr[3], isSel and 255 or 160))
        nvgFontSize(nvgCtx, paramFs)
        cardDev._labelRects[gi] = {x = panelX + 8, y = py2, w = panelW * 0.6, h = lineH * 0.7}
        nvgText(nvgCtx, panelX + 8, py2, (isSel and "> " or "  ") .. group.label)
        py2 = py2 + lineH * 0.7
        for _, item in ipairs(group.items) do
            nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 220))
            nvgFontSize(nvgCtx, paramFs * 0.9)
            nvgText(nvgCtx, panelX + 20, py2, string.format("%-12s %.3f", item[1], item[2]))
            py2 = py2 + lineH * 0.65
        end
        py2 = py2 + lineH * 0.2
    end
    -- 边框
    local frameClr = cardDev.colors.frame
    local isFrameSel = (cardDev.selected == 5)
    nvgFillColor(nvgCtx, nvgRGBA(frameClr[1], frameClr[2], frameClr[3], isFrameSel and 255 or 160))
    nvgFontSize(nvgCtx, paramFs)
    cardDev._labelRects[5] = {x = panelX + 8, y = py2, w = panelW * 0.6, h = lineH * 0.7}
    nvgText(nvgCtx, panelX + 8, py2, (isFrameSel and "> " or "  ") .. "边框")
    py2 = py2 + lineH * 0.7
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 220))
    nvgFontSize(nvgCtx, paramFs * 0.9)
    nvgText(nvgCtx, panelX + 20, py2, string.format("framePadX    %.3f", cardDev.p.framePadX))
    py2 = py2 + lineH * 0.65
    nvgText(nvgCtx, panelX + 20, py2, string.format("framePadY    %.3f", cardDev.p.framePadY))
    py2 = py2 + lineH * 0.65 + lineH * 0.2

    -- 卡牌大小
    local cardClr = cardDev.colors.card
    local isCardSel = (cardDev.selected == 6)
    nvgFillColor(nvgCtx, nvgRGBA(cardClr[1], cardClr[2], cardClr[3], isCardSel and 255 or 160))
    nvgFontSize(nvgCtx, paramFs)
    cardDev._labelRects[6] = {x = panelX + 8, y = py2, w = panelW * 0.6, h = lineH * 0.7}
    nvgText(nvgCtx, panelX + 8, py2, (isCardSel and "> " or "  ") .. "卡牌大小")
    py2 = py2 + lineH * 0.7
    nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 220))
    nvgFontSize(nvgCtx, paramFs * 0.9)
    nvgText(nvgCtx, panelX + 20, py2, string.format("cardScale    %.2f", cardDev.p.cardScale))
    py2 = py2 + lineH * 0.65
    nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 180))
    nvgText(nvgCtx, panelX + 20, py2, string.format("基础尺寸     %dx%d px", baseCardW, baseCardH))
    py2 = py2 + lineH * 0.65
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 220))
    nvgText(nvgCtx, panelX + 20, py2, string.format("实际尺寸     %dx%d px", actualCardW, actualCardH))
    py2 = py2 + lineH * 0.65
    -- 绘制 1:1 实际尺寸预览框
    local sizeBoxX = panelX + 20
    local sizeBoxY = py2 + 2
    local sizeBoxMaxW = panelW - 40
    local sizeBoxMaxH = math.max(20, (panelY + panelH) - sizeBoxY - lineH * 3.5)
    -- 等比缩放使预览框适配面板空间
    local sizeScale = math.min(1.0, sizeBoxMaxW / actualCardW, sizeBoxMaxH / actualCardH)
    local drawSzW = math.floor(actualCardW * sizeScale)
    local drawSzH = math.floor(actualCardH * sizeScale)
    -- 虚线边框
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, sizeBoxX, sizeBoxY, drawSzW, drawSzH, 3)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 220, 100, 180))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)
    -- 半透明填充
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, sizeBoxX, sizeBoxY, drawSzW, drawSzH, 3)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 20))
    nvgFill(nvgCtx)
    -- 缩放比例标注（如果不是1:1）
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, paramFs * 0.75)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 200))
    if sizeScale < 1.0 then
        nvgText(nvgCtx, sizeBoxX + drawSzW / 2, sizeBoxY + drawSzH / 2,
            string.format("%.0f%%", sizeScale * 100))
    else
        nvgText(nvgCtx, sizeBoxX + drawSzW / 2, sizeBoxY + drawSzH / 2, "1:1")
    end
    py2 = sizeBoxY + drawSzH + 4

    -- 按钮区域
    local btnH = math.max(24, fs * 1.8)
    local btnW2 = (panelW - 24) / 3
    local btnY = math.min(py2 + lineH * 0.3, panelY + panelH - btnH - 6)

    -- 按钮: 切换卡牌
    cardDev._btnSwitch = {x = panelX + 6, y = btnY, w = btnW2, h = btnH}
    drawRoundRect(panelX + 6, btnY, btnW2, btnH, 4, 50, 80, 150, 220)
    drawTextCenter("换卡", panelX + 6 + btnW2 / 2, btnY + btnH / 2, paramFs, 200, 220, 255)

    -- 按钮: 导出参数
    cardDev._btnExport = {x = panelX + 10 + btnW2, y = btnY, w = btnW2, h = btnH}
    local exportLabel = cardDev.exportText and "已复制" or "导出"
    local ebr, ebg = cardDev.exportText and 80 or 50, cardDev.exportText and 180 or 140
    drawRoundRect(panelX + 10 + btnW2, btnY, btnW2, btnH, 4, ebr, ebg, 80, 220)
    drawTextCenter(exportLabel, panelX + 10 + btnW2 + btnW2 / 2, btnY + btnH / 2, paramFs, 200, 255, 200)

    -- 按钮: 关闭
    cardDev._btnClose = {x = panelX + 14 + btnW2 * 2, y = btnY, w = btnW2, h = btnH}
    drawRoundRect(panelX + 14 + btnW2 * 2, btnY, btnW2, btnH, 4, 140, 50, 50, 220)
    drawTextCenter("关闭", panelX + 14 + btnW2 * 2 + btnW2 / 2, btnY + btnH / 2, paramFs, 255, 200, 200)

    -- 操作提示
    nvgFontFace(nvgCtx, "sans")
    nvgFontSize(nvgCtx, paramFs * 0.8)
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 180))
    local tipY = math.min(py2 + 2, panelY + panelH - btnH - fs * 1.5)
    nvgText(nvgCtx, panelX + panelW / 2, tipY, "点选区域 → 拖拽移动 / 右下角缩放")

    -- 导出文本显示
    if cardDev.exportText then
        local etFs = paramFs * 0.75
        nvgFontFace(nvgCtx, "sans")
        nvgFontSize(nvgCtx, etFs)
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(nvgCtx, nvgRGBA(100, 255, 100, 255))
        local ety = panelY + panelH - fs * 0.5
        -- 向上显示导出文本
        for line in cardDev.exportText:gmatch("[^\n]+") do
            ety = ety - etFs * 1.2
        end
        for line in cardDev.exportText:gmatch("[^\n]+") do
            nvgText(nvgCtx, panelX + 8, ety, line)
            ety = ety + etFs * 1.2
        end
    end

    -- 战斗中手牌实际触摸范围可视化（叠加在预览卡牌上，居中对齐）
    do
        local isPC = logicalH > logicalW
        local bCardH = isPC
            and math.max(120, math.min(logicalW * 0.38, 165))
            or  math.max(130, math.min(logicalH * 0.27, 180))
        bCardH = math.floor(bCardH * (cardDev.p.cardScale or 1.0))
        local bCardW = math.floor(bCardH * 0.68)
        -- 居中叠加在预览卡牌上
        local bx = cx + (cardW - bCardW) / 2
        local by = cy + (cardH - bCardH) / 2
        -- 绘制触摸范围框
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, bx, by, bCardW, bCardH, 4)
        nvgStrokeColor(nvgCtx, nvgRGBA(100, 255, 100, 200))
        nvgStrokeWidth(nvgCtx, 2.0)
        nvgStroke(nvgCtx)
        -- 半透明填充
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, bx, by, bCardW, bCardH, 4)
        nvgFillColor(nvgCtx, nvgRGBA(100, 255, 100, 25))
        nvgFill(nvgCtx)
        -- 标签
        nvgFontFace(nvgCtx, "sans")
        nvgFontSize(nvgCtx, fs * 0.7)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvgCtx, nvgRGBA(100, 255, 100, 220))
        nvgText(nvgCtx, bx + bCardW / 2, by - 2, string.format("触摸区 %dx%d", bCardW, bCardH))
    end

    -- 记录卡牌预览区用于点击检测
    cardDev._cardRect = {x = cx, y = cy, w = cardW, h = cardH}
end

--- 导出参数为 Lua 代码
function cardDev.export()
    local p = cardDev.p
    local lines = {
        "-- Card Dev Export --",
        string.format("nameRatioTop = %.3f, nameRatioBot = %.3f, nameOffX = %.3f,", p.nameTop, p.nameBot, p.nameOffX),
        string.format("imgRatioTop  = %.3f, imgRatioBot  = %.3f, imgMarginX = %.3f, imgOffX = %.3f,", p.imgTop, p.imgBot, p.imgMarginX, p.imgOffX),
        string.format("descRatioTop = %.3f, descRatioBot = %.3f, descPadX   = %.3f, descOffX = %.3f,", p.descTop, p.descBot, p.descPadX, p.descOffX),
        string.format("manaX = %.3f, manaY = %.3f, manaSize = %.3f,", p.manaX, p.manaY, p.manaSize),
        string.format("framePadX = %.3f, framePadY = %.3f,", p.framePadX, p.framePadY),
        string.format("cardScale = %.2f,", p.cardScale),
    }
    cardDev.exportText = table.concat(lines, "\n")
    -- 注：WASM 环境不支持系统剪贴板，导出内容输出到日志
    log:Write(LOG_INFO, "=== CARD DEV EXPORT (已复制到剪贴板) ===")
    for _, line in ipairs(lines) do
        log:Write(LOG_INFO, line)
    end
    log:Write(LOG_INFO, "=== END EXPORT ===")
end

--- 处理卡牌开发者工具的点击（按下）
function cardDev.handleClick(lx, ly)
    if not cardDev.active then return false end
    local function hitRect(r)
        return r and lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h
    end

    -- 功能按钮
    if hitRect(cardDev._btnClose) then
        cardDev.active = false
        return true
    end
    if hitRect(cardDev._btnExport) then
        cardDev.export()
        return true
    end
    if hitRect(cardDev._btnSwitch) then
        local idx = 1
        for i, id in ipairs(CARD_ORDER) do
            if id == cardDev.previewId then idx = i; break end
        end
        idx = idx % #CARD_ORDER + 1
        cardDev.previewId = CARD_ORDER[idx]
        cardDev.exportText = nil
        return true
    end

    -- 参数面板标签点击 → 选中区域
    if cardDev._labelRects then
        for li, lr in pairs(cardDev._labelRects) do
            if hitRect(lr) then
                cardDev.selected = li
                return true
            end
        end
    end

    -- 卡牌区域：检测点击 → 选中 + 启动拖拽
    local cr = cardDev._cardRect
    if cr and hitRect(cr) then
        -- 检测哪个区域被点中（mana 优先，然后内部区域，frame/card 最后兜底）
        local hitOrder = {4, 1, 2, 3, 5, 6}
        local hitIdx = nil
        for _, ri in ipairs(hitOrder) do
            local region = cardDev.regions[ri]
            local rc = cardDev.regionRect(region, cr.x, cr.y, cr.w, cr.h)
            if lx >= rc.x and lx <= rc.x + rc.w and ly >= rc.y and ly <= rc.y + rc.h then
                hitIdx = ri
                break
            end
        end
        if hitIdx then
            cardDev.selected = hitIdx
            -- 判断是右下角缩放还是整体移动
            local region = cardDev.regions[hitIdx]
            local rc = cardDev.regionRect(region, cr.x, cr.y, cr.w, cr.h)
            local handleSize = math.max(12, cr.w * 0.08)
            local inResize = (lx >= rc.x + rc.w - handleSize and ly >= rc.y + rc.h - handleSize)
            -- card / frame 区域始终用 resize 模式（拖拽改大小）
            if region == "card" or region == "frame" then inResize = true end
            -- 快照当前参数
            local snap = {}
            for k, v in pairs(cardDev.p) do snap[k] = v end
            cardDev.drag = {
                active = true,
                mode = inResize and "resize" or "move",
                region = hitIdx,
                startX = lx, startY = ly,
                origP = snap,
                cardW = cr.w, cardH = cr.h,
            }
        else
            cardDev.selected = nil
        end
        return true
    end

    return true  -- 消费所有点击，防止穿透
end

--- 释放存档截图缩略图句柄
local function releaseSaveSlotThumbs()
    for slot, handle in pairs(saveSlotPanel.thumbs) do
        if handle and handle ~= 0 then
            nvgDeleteImage(nvgCtx, handle)
        end
    end
    saveSlotPanel.thumbs = {}
end

--- 加载存档截图缩略图
local function loadSaveSlotThumbs()
    releaseSaveSlotThumbs()
    for i = 1, MAX_SAVE_SLOTS do
        local ssPath = slotScreenshotPath(i)
        if fileSystem:FileExists(ssPath) then
            local h = nvgCreateImage(nvgCtx, ssPath, 0)
            if h and h ~= 0 then
                saveSlotPanel.thumbs[i] = h
            end
        end
    end
end

--- 打开存档槽位面板
local function openSaveSlotPanel(mode)
    saveSlotPanel.open = true
    saveSlotPanel.mode = mode
    saveSlotPanel.confirmSlot = nil
    saveSlotPanel.confirmRects = {}
    -- 迁移旧存档
    migrateOldSave()
    -- 加载缩略图
    loadSaveSlotThumbs()
end

--- 关闭存档槽位面板
local function closeSaveSlotPanel()
    saveSlotPanel.open = false
    saveSlotPanel.mode = nil
    saveSlotPanel.confirmSlot = nil
    saveSlotPanel.confirmRects = {}
    releaseSaveSlotThumbs()
end

--- 格式化时间戳
local function formatTimestamp(ts)
    if not ts then return "未知时间" end
    return os.date("%m/%d %H:%M", ts)
end

--- 绘制存档槽位选择面板
function drawSaveSlotPanel()
    if not saveSlotPanel.open then return end
    saveSlotPanel.slotRects = {}
    saveSlotPanel.closeRect = nil

    -- 半透明遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 170)

    -- 面板尺寸
    local panelW = math.min(340, logicalW * 0.85)
    local slotH = math.max(72, logicalH * 0.12)
    local gap = 8
    local padY = 14
    local titleH = 36
    local panelH = titleH + padY * 2 + MAX_SAVE_SLOTS * (slotH + gap) - gap + 12
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 10, 25, 22, 45, 245)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(140, 160, 220, 120))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    -- 标题
    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local titleText = saveSlotPanel.mode == "save" and "保存游戏" or "读取存档"
    nvgFontSize(nvgCtx, math.max(14, titleH * 0.5))
    nvgFillColor(nvgCtx, nvgRGBA(230, 220, 255, 255))
    nvgText(nvgCtx, px + panelW / 2, py + titleH / 2, titleText)

    -- 关闭按钮（右上角 X）
    local closeSize = 24
    local closeX = px + panelW - closeSize - 6
    local closeY = py + 6
    nvgFontSize(nvgCtx, 18)
    nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 200))
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvgCtx, closeX + closeSize / 2, closeY + closeSize / 2, "X")
    saveSlotPanel.closeRect = {x = closeX, y = closeY, w = closeSize, h = closeSize}

    -- 绘制槽位
    local sx = px + 12
    local slotW = panelW - 24
    local sy = py + titleH + padY
    local thumbW = math.max(60, slotH * 1.35)
    local thumbH = slotH - 8
    local infoFs = math.max(11, slotH * 0.16)

    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    for i = 1, MAX_SAVE_SLOTS do
        local info = getSaveSlotInfo(i)
        local isConfirming = (saveSlotPanel.confirmSlot == i)

        -- 槽位背景
        local bgR, bgG, bgB, bgA = 40, 38, 60, 220
        if isConfirming then
            bgR, bgG, bgB, bgA = 80, 40, 40, 240
        elseif info then
            bgR, bgG, bgB, bgA = 45, 50, 70, 230
        end
        drawRoundRect(sx, sy, slotW, slotH, 8, bgR, bgG, bgB, bgA)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, sx, sy, slotW, slotH, 8)
        nvgStrokeColor(nvgCtx, nvgRGBA(120, 140, 180, 80))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)

        if isConfirming then
            -- 覆盖确认模式
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(nvgCtx, infoFs + 1)
            nvgFillColor(nvgCtx, nvgRGBA(255, 200, 180, 255))
            nvgText(nvgCtx, sx + slotW / 2, sy + slotH * 0.3, "覆盖此存档？")

            local cBtnW = math.min(70, slotW * 0.3)
            local cBtnH = math.max(24, slotH * 0.35)
            local cBtnY = sy + slotH * 0.55
            local cGap = 12
            local cBtnX1 = sx + slotW / 2 - cBtnW - cGap / 2
            local cBtnX2 = sx + slotW / 2 + cGap / 2

            -- 确认按钮
            drawRoundRect(cBtnX1, cBtnY, cBtnW, cBtnH, 5, 160, 60, 50, 230)
            nvgFontSize(nvgCtx, infoFs)
            nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 240))
            nvgText(nvgCtx, cBtnX1 + cBtnW / 2, cBtnY + cBtnH / 2, "确认")
            -- 取消按钮
            drawRoundRect(cBtnX2, cBtnY, cBtnW, cBtnH, 5, 70, 70, 90, 230)
            nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 240))
            nvgText(nvgCtx, cBtnX2 + cBtnW / 2, cBtnY + cBtnH / 2, "取消")

            saveSlotPanel.confirmRects = {
                confirm = {x = cBtnX1, y = cBtnY, w = cBtnW, h = cBtnH},
                cancel = {x = cBtnX2, y = cBtnY, w = cBtnW, h = cBtnH},
            }
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        elseif info then
            -- 有存档：截图 + 信息
            local tx = sx + 6
            local ty = sy + 4
            local thumb = saveSlotPanel.thumbs[i]
            if thumb then
                -- 绘制截图缩略图
                local imgPaint = nvgImagePattern(nvgCtx, tx, ty, thumbW, thumbH, 0, thumb, 1.0)
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, tx, ty, thumbW, thumbH, 4)
                nvgFillPaint(nvgCtx, imgPaint)
                nvgFill(nvgCtx)
                -- 截图边框
                nvgBeginPath(nvgCtx)
                nvgRoundedRect(nvgCtx, tx, ty, thumbW, thumbH, 4)
                nvgStrokeColor(nvgCtx, nvgRGBA(100, 120, 160, 100))
                nvgStrokeWidth(nvgCtx, 1)
                nvgStroke(nvgCtx)
            else
                -- 无截图占位
                drawRoundRect(tx, ty, thumbW, thumbH, 4, 30, 30, 40, 200)
                nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFontSize(nvgCtx, infoFs)
                nvgFillColor(nvgCtx, nvgRGBA(120, 120, 140, 150))
                nvgText(nvgCtx, tx + thumbW / 2, ty + thumbH / 2, "无截图")
                nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            end

            -- 右侧信息
            local infoX = tx + thumbW + 8
            local lineH = slotH / 5
            nvgFontFace(nvgCtx, "sans")
            nvgFontSize(nvgCtx, infoFs + 1)
            nvgFillColor(nvgCtx, nvgRGBA(220, 200, 140, 255))
            nvgText(nvgCtx, infoX, sy + lineH * 1, "槽位 " .. i .. "  F" .. info.floor)

            nvgFontSize(nvgCtx, infoFs)
            nvgFillColor(nvgCtx, nvgRGBA(200, 210, 230, 220))
            nvgText(nvgCtx, infoX, sy + lineH * 2, "HP:" .. info.hp .. " ATK:" .. info.atk .. " DEF:" .. info.def)
            nvgText(nvgCtx, infoX, sy + lineH * 3, "Lv." .. info.level .. " G:" .. info.gold .. " C:" .. info.cards)
            nvgFillColor(nvgCtx, nvgRGBA(150, 160, 180, 180))
            nvgText(nvgCtx, infoX, sy + lineH * 4, formatTimestamp(info.timestamp))
        else
            -- 空槽位
            nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(nvgCtx, infoFs + 2)
            nvgFillColor(nvgCtx, nvgRGBA(120, 120, 150, 160))
            nvgText(nvgCtx, sx + slotW / 2, sy + slotH / 2, "槽位 " .. i .. " - 空存档")
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        end

        table.insert(saveSlotPanel.slotRects, {slot = i, x = sx, y = sy, w = slotW, h = slotH})
        sy = sy + slotH + gap
    end

    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
end

--- 绘制游戏内菜单面板（存档/读档/返回标题）
function drawGameMenu()
    if not gameMenu.open then return end
    gameMenu.btnRects = {}

    -- 半透明遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 150)

    -- 面板
    local panelW = math.min(280, logicalW * 0.65)
    local btnH = math.max(40, logicalH * 0.065)
    local gap = 10

    nvgFontFace(nvgCtx, "sans")
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- === 确认对话框模式 ===
    if gameMenu.confirm == "title" then
        local cPanelW = math.min(260, logicalW * 0.6)
        local cBtnH = btnH
        local cGap = 10
        local cPadY = 16
        local cTitleH = 36
        local cMsgH = 36
        local cPanelH = cTitleH + cMsgH + cPadY * 2 + 2 * (cBtnH + cGap) - cGap
        local cpx = (logicalW - cPanelW) / 2
        local cpy = (logicalH - cPanelH) / 2

        drawRoundRect(cpx, cpy, cPanelW, cPanelH, 10, 40, 30, 30, 245)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, cpx, cpy, cPanelW, cPanelH, 10)
        nvgStrokeColor(nvgCtx, nvgRGBA(200, 100, 100, 150))
        nvgStrokeWidth(nvgCtx, 1.5)
        nvgStroke(nvgCtx)

        nvgFontSize(nvgCtx, math.max(14, cTitleH * 0.55))
        nvgFillColor(nvgCtx, nvgRGBA(255, 180, 180, 255))
        nvgText(nvgCtx, cpx + cPanelW / 2, cpy + cTitleH / 2, "确认返回标题？")

        nvgFontSize(nvgCtx, math.max(11, cMsgH * 0.4))
        nvgFillColor(nvgCtx, nvgRGBA(200, 200, 210, 200))
        nvgText(nvgCtx, cpx + cPanelW / 2, cpy + cTitleH + cMsgH / 2, "未保存的进度将会丢失")

        local cBtnW = cPanelW - 32
        local cbx = cpx + 16
        local cby = cpy + cTitleH + cMsgH + cPadY

        -- 确认按钮
        drawRoundRect(cbx, cby, cBtnW, cBtnH, 6, 160, 60, 50, 220)
        nvgFontSize(nvgCtx, math.max(12, cBtnH * 0.42))
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 240))
        nvgText(nvgCtx, cbx + cBtnW / 2, cby + cBtnH / 2, "确认返回")
        table.insert(gameMenu.btnRects, {key = "confirm_title", x = cbx, y = cby, w = cBtnW, h = cBtnH})
        cby = cby + cBtnH + cGap

        -- 取消按钮
        drawRoundRect(cbx, cby, cBtnW, cBtnH, 6, 70, 70, 90, 220)
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 240))
        nvgText(nvgCtx, cbx + cBtnW / 2, cby + cBtnH / 2, "取消")
        table.insert(gameMenu.btnRects, {key = "cancel_confirm", x = cbx, y = cby, w = cBtnW, h = cBtnH})
        return
    end

    -- === 正常菜单 ===
    local items = {
        {key = "save",   text = "保存游戏",   r = 60,  g = 140, b = 80},
        {key = "load",   text = "读取存档",   r = 60,  g = 100, b = 160},
        {key = "title",  text = "返回标题",   r = 140, g = 80,  b = 60},
        {key = "close",  text = "继续游戏",   r = 80,  g = 80,  b = 100},
    }
    local padY = 16
    local titleH = 36
    local toggleH = math.max(32, btnH * 0.8)
    local panelH = titleH + padY * 2 + #items * (btnH + gap) - gap + gap + toggleH
    local px = (logicalW - panelW) / 2
    local py = (logicalH - panelH) / 2

    -- 面板背景
    drawRoundRect(px, py, panelW, panelH, 10, 30, 28, 50, 240)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, panelW, panelH, 10)
    nvgStrokeColor(nvgCtx, nvgRGBA(120, 140, 200, 120))
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStroke(nvgCtx)

    -- 标题
    nvgFontSize(nvgCtx, math.max(14, titleH * 0.55))
    nvgFillColor(nvgCtx, nvgRGBA(220, 220, 240, 255))
    nvgText(nvgCtx, px + panelW / 2, py + titleH / 2, "游戏菜单")

    -- 按钮
    local btnW = panelW - 32
    local bx = px + 16
    local by = py + titleH + padY
    local btnFs = math.max(12, btnH * 0.42)
    for _, item in ipairs(items) do
        drawRoundRect(bx, by, btnW, btnH, 6, item.r, item.g, item.b, 220)
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, bx, by, btnW, btnH, 6)
        nvgStrokeColor(nvgCtx, nvgRGBA(255, 255, 255, 40))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)
        nvgFontSize(nvgCtx, btnFs)
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 240))
        nvgText(nvgCtx, bx + btnW / 2, by + btnH / 2, item.text)
        table.insert(gameMenu.btnRects, {key = item.key, x = bx, y = by, w = btnW, h = btnH})
        by = by + btnH + gap
    end

    -- === 自动存档开关 ===
    by = by + gap * 0.5
    local toggleFs = math.max(11, toggleH * 0.42)
    local labelText = "自动存档"
    local switchW = math.max(40, toggleH * 1.2)
    local switchH = math.max(20, toggleH * 0.55)
    -- 分隔线
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, bx, by - gap * 0.3)
    nvgLineTo(nvgCtx, bx + btnW, by - gap * 0.3)
    nvgStrokeColor(nvgCtx, nvgRGBA(120, 120, 160, 60))
    nvgStrokeWidth(nvgCtx, 1)
    nvgStroke(nvgCtx)
    -- 标签
    nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvgCtx, toggleFs)
    nvgFillColor(nvgCtx, nvgRGBA(180, 180, 200, 220))
    nvgText(nvgCtx, bx + 4, by + toggleH / 2, labelText)
    -- 开关滑块
    local swX = bx + btnW - switchW - 4
    local swY = by + (toggleH - switchH) / 2
    local swR = switchH / 2
    if gameAutoSave then
        -- 开启状态：绿色
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, swX, swY, switchW, switchH, swR)
        nvgFillColor(nvgCtx, nvgRGBA(60, 160, 80, 230))
        nvgFill(nvgCtx)
        -- 圆形滑块（右侧）
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, swX + switchW - swR - 2, swY + swR, swR - 3)
        nvgFillColor(nvgCtx, nvgRGBA(255, 255, 255, 240))
        nvgFill(nvgCtx)
    else
        -- 关闭状态：灰色
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, swX, swY, switchW, switchH, swR)
        nvgFillColor(nvgCtx, nvgRGBA(80, 80, 100, 200))
        nvgFill(nvgCtx)
        -- 圆形滑块（左侧）
        nvgBeginPath(nvgCtx)
        nvgCircle(nvgCtx, swX + swR + 2, swY + swR, swR - 3)
        nvgFillColor(nvgCtx, nvgRGBA(160, 160, 170, 240))
        nvgFill(nvgCtx)
    end
    nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    table.insert(gameMenu.btnRects, {key = "toggle_autosave", x = swX, y = swY, w = switchW, h = switchH})
end

function drawDevPanel()
    if not dev.mode then return end

    local px, py, pw, ph, fs = buildDevButtons()

    -- 半透明遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 180)

    -- 面板背景
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, px, py, pw, ph, 8)
    nvgFillColor(nvgCtx, nvgRGBA(30, 28, 45, 245))
    nvgFill(nvgCtx)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 200, 50, 180))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    -- 标题
    drawTextCenter("DEV MODE", px + pw / 2, py + fs * 1.1, fs * 1.3, 255, 200, 50)

    -- 当前状态摘要
    local infoY = py + fs * 2.0
    local infoFs = fs * 0.85
    local info = string.format("HP:%d ATK:%d DEF:%d G:%d F%d 卡:%d MP:%d/%d",
        player.hp, player.atk, player.def, player.gold, player.floor, #player.cards, player.mp, player.maxMp)
    drawTextCenter(info, px + pw / 2, infoY, infoFs, 180, 180, 200)

    -- 裁剪区域（防溢出）
    nvgSave(nvgCtx)
    nvgScissor(nvgCtx, px, py + fs * 2.2, pw, ph - fs * 2.2)

    -- 渲染所有按钮行
    local contentX = px + 10
    for _, row in ipairs(DEV_BUTTONS) do
        -- 行标签
        if row.label and row.label ~= "" then
            nvgFontFace(nvgCtx, "sans")
            nvgFontSize(nvgCtx, fs)
            nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvgCtx, nvgRGBA(200, 200, 220, 255))
            nvgText(nvgCtx, contentX, row.y + row.h / 2, row.label)
        end
        -- 按钮
        for _, btn in ipairs(row.items) do
            nvgBeginPath(nvgCtx)
            nvgRoundedRect(nvgCtx, btn.x, btn.y, btn.w, btn.h, 4)
            nvgFillColor(nvgCtx, nvgRGBA(btn.r, btn.g, btn.b, 220))
            nvgFill(nvgCtx)
            nvgStrokeColor(nvgCtx, nvgRGBA(btn.r + 60, btn.g + 60, btn.b + 60, 150))
            nvgStrokeWidth(nvgCtx, 1)
            nvgStroke(nvgCtx)
            drawTextCenter(btn.text, btn.x + btn.w / 2, btn.y + btn.h / 2, fs * 0.85,
                math.min(255, btn.r + 140), math.min(255, btn.g + 140), math.min(255, btn.b + 140))
        end
    end

    nvgRestore(nvgCtx)

    -- 滚动条指示器
    local contentTop = py + fs * 2.2
    local visibleH = ph - fs * 2.2 - fs * 1.5
    local scrollMax = math.max(0, dev.contentH - visibleH)
    if scrollMax > 0 then
        local barH = math.max(20, visibleH * (visibleH / dev.contentH))
        local barY = contentTop + (visibleH - barH) * (dev.scroll / scrollMax)
        drawRoundRect(px + pw - 6, barY, 3, barH, 2, 255, 200, 50, 120)
    end

    -- 底部提示
    local hint = scrollMax > 0 and "上下滑动浏览 · 连击楼层5次打开/关闭" or "连击楼层5次打开/关闭"
    drawTextCenter(hint, px + pw / 2, py + ph - fs * 0.7, fs * 0.7, 120, 120, 140)
end

--- 处理开发者面板点击（TouchBegin），启动拖拽
function handleDevClick(lx, ly)
    if not dev.mode then return false end
    -- 点击面板外：关闭
    local pw = math.min(logicalW * 0.96, 440)
    local ph = math.min(logicalH * 0.95, 780)
    local ppx = (logicalW - pw) / 2
    local ppy = (logicalH - ph) / 2
    if lx < ppx or lx > ppx + pw or ly < ppy or ly > ppy + ph then
        dev.mode = false
        return true
    end
    -- 面板内：启动拖拽（TouchEnd 中判断点击还是滚动）
    dev.drag.active = true
    dev.drag.startY = ly
    dev.drag.startScroll = dev.scroll
    dev.drag.startX = lx
    return true
end

--- 处理开发者面板拖拽结束（TouchEnd），判断点击还是滚动
function handleDevTouchEnd(lx, ly)
    if not dev.drag.active then return false end
    dev.drag.active = false
    local dragDist = math.abs(ly - dev.drag.startY)
    if dragDist < 10 then
        -- 拖拽距离很小，视为点击 → 检查按钮命中
        for _, row in ipairs(DEV_BUTTONS) do
            for _, btn in ipairs(row.items) do
                if lx >= btn.x and lx <= btn.x + btn.w and ly >= btn.y and ly <= btn.y + btn.h then
                    playSfx("btn", 0.5)
                    btn.action()
                    return true
                end
            end
        end
    end
    return true
end

--- 绘制游戏结束/胜利画面
endScreenRects = { loadBtn = nil, restartBtn = nil }

function drawEndScreen()
    -- 半透明遮罩
    drawRoundRect(0, 0, logicalW, logicalH, 0, 0, 0, 0, 180)

    local panelW = math.min(logicalW * 0.9, 420)
    local panelH = math.min(logicalH * 0.62, 360)
    local panelX = (logicalW - panelW) / 2
    local panelY = (logicalH - panelH) / 2
    local safeW = panelW - 28
    local fs = math.max(16, math.min(28, panelH * 0.09))

    drawRoundRect(panelX, panelY, panelW, panelH, 12, 24, 22, 45, 242)
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, panelX, panelY, panelW, panelH, 12)
    nvgStrokeColor(nvgCtx, nvgRGBA(110, 140, 230, 210))
    nvgStrokeWidth(nvgCtx, 2)
    nvgStroke(nvgCtx)

    local function fittedFontSize(text, desiredSize, maxW, minSize)
        local size = desiredSize
        minSize = minSize or 10
        nvgFontFace(nvgCtx, "sans")
        while size > minSize do
            nvgFontSize(nvgCtx, size)
            if nvgTextBounds(nvgCtx, 0, 0, text) <= maxW then return size end
            size = size - 1
        end
        return minSize
    end

    local function drawFitCenter(text, y, desiredSize, r, g, b, a)
        local size = fittedFontSize(text, desiredSize, safeW, math.max(9, desiredSize * 0.55))
        drawTextCenter(text, logicalW / 2, y, size, r, g, b, a)
    end

    local function drawFitButton(text, x, y, w, h, radius, br, bg, bb, tr, tg, tb)
        drawRoundRect(x, y, w, h, radius, br, bg, bb, 220)
        local textSize = fittedFontSize(text, math.min(fs * 0.82, h * 0.46), w - 16, 10)
        drawTextCenter(text, x + w / 2, y + h / 2, textSize, tr, tg, tb)
    end

    if gameState == "win" then
        drawFitCenter("恭喜通关（暂时）！", panelY + panelH * 0.18, fs * 1.15, 255, 220, 50)
        drawFitCenter("本游戏是21天GameJam开发", panelY + panelH * 0.34, fs * 0.82, 200, 255, 200)
        drawFitCenter("剩余楼层仍在制作中", panelY + panelH * 0.46, fs * 0.82, 200, 220, 255)
        drawFitCenter("敬请期待！", panelY + panelH * 0.58, fs, 255, 220, 120)
        drawFitCenter("最终状态: HP " .. player.hp .. "  ATK " .. player.atk .. "  DEF " .. player.def,
            panelY + panelH * 0.72, fs * 0.65, 180, 180, 220)
        drawFitCenter("点击任意位置重新开始", panelY + panelH * 0.88, fs * 0.65, 180, 180, 200)
        endScreenRects.loadBtn = nil
        endScreenRects.restartBtn = nil
    else
        drawFitCenter("勇者倒下了...", panelY + panelH * 0.22, fs * 1.12, 255, 80, 80)
        drawFitCenter("在第 " .. player.floor .. " 层被击败",
            panelY + panelH * 0.40, fs * 0.9, 200, 180, 180)

        -- 按钮区域
        local btnW = math.min(panelW * 0.36, 150)
        local btnH = math.max(34, math.min(48, fs * 1.7))
        local btnY = panelY + panelH * 0.68
        local gap = math.min(fs * 0.6, panelW * 0.05)
        local hasSave = hasSaveFile()

        if hasSave then
            -- 两个按钮：读档 + 重新开始，保证总宽度不超过面板
            local totalW = btnW * 2 + gap
            if totalW > safeW then
                btnW = (safeW - gap) / 2
                totalW = btnW * 2 + gap
            end
            local startX = panelX + (panelW - totalW) / 2

            local lbX = startX
            drawFitButton("读档", lbX, btnY, btnW, btnH, 6, 60, 120, 180, 220, 240, 255)
            endScreenRects.loadBtn = { x = lbX, y = btnY, w = btnW, h = btnH }

            local rbX = startX + btnW + gap
            drawFitButton("重新开始", rbX, btnY, btnW, btnH, 6, 100, 60, 60, 255, 200, 200)
            endScreenRects.restartBtn = { x = rbX, y = btnY, w = btnW, h = btnH }
        else
            local rbX = panelX + (panelW - btnW) / 2
            drawFitButton("重新开始", rbX, btnY, btnW, btnH, 6, 100, 60, 60, 255, 200, 200)
            endScreenRects.restartBtn = { x = rbX, y = btnY, w = btnW, h = btnH }
            endScreenRects.loadBtn = nil
        end
    end
end

--- 界面点击区域（每帧重建）
menuRects = {
    title = { startBtn = nil, continueBtn = nil, galleryBtn = nil, editorBtn = nil },
    mode = { modes = {}, difficulties = {}, nextBtn = nil, backBtn = nil },
}
charSelectRects = {
    chars = {},     -- {x,y,w,h, idx}
    startBtn = nil, -- {x,y,w,h}
    backBtn = nil,  -- {x,y,w,h}
}

--- 获取角色的精灵帧参数（用于角色选择界面动画）
function getCharSpriteFrame(charIdx)
    local char = CHARACTER_LIST[charIdx]
    local preview = charSelect.charPreviews[charIdx]
    if not preview then return nil end
    local imgW, imgH = nvgImageSize(nvgCtx, preview)
    local cfg = char.spriteConfig
    if cfg then
        -- 特殊精灵图（如瑞比4x2大图）：先按cols×rows切块，再按标准3x4拆帧
        local blockW = imgW / cfg.cols
        local blockH = imgH / cfg.rows
        local bx = (cfg.charIndex % cfg.cols) * blockW
        local by = math.floor(cfg.charIndex / cfg.cols) * blockH
        local frameW = blockW / 3
        local frameH = blockH / 4
        return {handle = preview, imgW = imgW, imgH = imgH,
                frameW = frameW, frameH = frameH,
                offsetX = bx, offsetY = by}
    else
        -- 标准 RPG Maker 3x4 精灵图
        local frameW = imgW / 3
        local frameH = imgH / 4
        return {handle = preview, imgW = imgW, imgH = imgH,
                frameW = frameW, frameH = frameH,
                offsetX = 0, offsetY = 0}
    end
end

-- ============================================================
-- 输入处理
-- ============================================================

--- 处理D-pad点击
function handleDpadClick(lx, ly)
    local bs = dpadBtnSize
    local cx = dpadCenterX
    local cy = dpadCenterY
    local gap = bs * 0.1

    -- 上
    if lx >= cx - bs / 2 and lx <= cx + bs / 2 and
       ly >= cy - bs - gap - bs / 2 and ly <= cy - gap - bs / 2 then
        autoPath = {}
        tryMove(-1, 0)
        return true
    end
    -- 下
    if lx >= cx - bs / 2 and lx <= cx + bs / 2 and
       ly >= cy + gap + bs / 2 and ly <= cy + gap + bs * 1.5 then
        autoPath = {}
        tryMove(1, 0)
        return true
    end
    -- 左
    if lx >= cx - bs - gap - bs / 2 and lx <= cx - gap - bs / 2 and
       ly >= cy - bs / 2 and ly <= cy + bs / 2 then
        autoPath = {}
        tryMove(0, -1)
        return true
    end
    -- 右
    if lx >= cx + gap + bs / 2 and lx <= cx + gap + bs * 1.5 and
       ly >= cy - bs / 2 and ly <= cy + bs / 2 then
        autoPath = {}
        tryMove(0, 1)
        return true
    end

    return false
end

--- 处理网格点击（寻路到目标格）
function handleGridClick(lx, ly)
    local gc = math.floor((lx - gridX) / cellSize) + 1
    local gr = math.floor((ly - gridY) / cellSize) + 1

    if gc < 1 or gc > GRID or gr < 1 or gr > GRID then return false end
    if gr == player.row and gc == player.col then return false end

    -- 点击怪物格：显示属性浮窗（不阻止寻路）
    local clickedTile = maps[player.floor][gr][gc]
    if isMonster(clickedTile) then
        local mdef = MONSTER_DEF[clickedTile]
        if mdef then
            monsterInfoPopup.active = true
            monsterInfoPopup.timer = 0
            monsterInfoPopup.name = mdef.name
            monsterInfoPopup.hp = getMonsterScaledHP(mdef)
            monsterInfoPopup.atk = getMonsterScaledATK(mdef)
            monsterInfoPopup.def = mdef.def
            monsterInfoPopup.row = gr
            monsterInfoPopup.col = gc
        end
    end

    -- 寻路中再次点击目的地：瞬移（依次执行剩余步骤，跳过动画）
    if #autoPath > 0 and autoPathDest and autoPathDest[1] == gr and autoPathDest[2] == gc then
        moveAnim.active = false
        while #autoPath > 0 do
            local step = autoPath[1]
            table.remove(autoPath, 1)
            local sr = step[1] - player.row
            local sc = step[2] - player.col
            -- 安全检查：每步只能移动一格，偏移异常说明前一步未能移动，立即中断
            if math.abs(sr) + math.abs(sc) ~= 1 then break end
            local prevRow, prevCol = player.row, player.col
            tryMove(sr, sc)
            moveAnim.active = false  -- 跳过移动动画
            -- 移动失败（位置未变）或战斗/游戏状态变化时中断
            if player.row == prevRow and player.col == prevCol then break end
            if gameState ~= "playing" or battle.active then break end
        end
        autoPath = {}
        autoPathDest = nil
        checkGameOver()
        return true
    end

    -- 相邻格: 直接移动（保持原有逻辑）
    local dr = gr - player.row
    local dc = gc - player.col
    if (math.abs(dr) == 1 and dc == 0) or (dr == 0 and math.abs(dc) == 1) then
        autoPath = {}  -- 清除寻路
        autoPathDest = nil
        tryMove(dr, dc)
        return true
    end

    -- 远距离: BFS 寻路（优先不经过门，找不到再允许走门）
    local path = findPath(player.row, player.col, gr, gc, true)
    if not path or #path == 0 then
        path = findPath(player.row, player.col, gr, gc, false)
    end
    if path and #path > 0 then
        autoPath = path
        autoPathDest = {gr, gc}  -- 记录目的地
        autoPathTimer = 0  -- 立即开始第一步
        return true
    else
        showMessage("无法到达该位置", 1.0, 200, 150, 150)
        return false
    end
end

--- 从选择界面进入游戏
function startGame()
    -- 设置角色精灵
    local char = CHARACTER_LIST[charSelect.selectedChar]
    PLAYER_SPRITE_PATH = char.sprite

    -- 重新加载玩家精灵图
    if spr.player and spr.player ~= 0 then
        nvgDeleteImage(nvgCtx, spr.player)
        spr.player = nil
    end
    local ph = nvgCreateImage(nvgCtx, PLAYER_SPRITE_PATH, NVG_IMAGE_NEAREST)
    if ph ~= -1 and ph ~= 0 then
        spr.playerW, spr.playerH = nvgImageSize(nvgCtx, ph)
        spr.player = ph
    end

    -- 设置角色精灵帧配置（需要先加载图片获取实际尺寸）
    if char.spriteConfig and spr.player then
        local sc = char.spriteConfig
        local blockW = spr.playerW / sc.cols
        local blockH = spr.playerH / sc.rows
        plSpr.fw = blockW / 3
        plSpr.fh = blockH / 4
        plSpr.ox = (sc.charIndex % sc.cols) * blockW
        plSpr.oy = math.floor(sc.charIndex / sc.cols) * blockH
    else
        -- 标准 RPG Maker 3x4 格式
        plSpr.fw = (spr.playerW or 144) / 3
        plSpr.fh = (spr.playerH or 192) / 4
        plSpr.ox = 0
        plSpr.oy = 0
    end

    -- 根据模式生成地图
    if charSelect.selectedMode == 2 then
        -- 固定模式：优先从 data/map.json 加载，回退到 FixedMaps.lua
        local mapData, totalFloors = loadMapJsonFromCache()
        if mapData and next(mapData) then
            TOTAL_FLOORS = totalFloors
            MAP_DATA = mapData
            BOSS_FLOORS = {[10]="J",[18]="X",[20]="X",[30]="L",[40]="N",[50]="7"}
        else
            local fm = require("FixedMaps")
            TOTAL_FLOORS = fm.TOTAL_FLOORS
            BOSS_FLOORS = fm.BOSS_FLOORS
            MAP_DATA = fm.data
        end
        -- 开发模式下可加载用户编辑的地图覆盖；发布包只使用正式地图数据。
        if ENABLE_DEV_TOOLS and fileSystem:FileExists("edited_maps.json") then
            local ef = File("edited_maps.json", FILE_READ)
            if ef:IsOpen() then
                local estr = ef:ReadString()
                ef:Close()
                if estr and estr ~= "" then
                    local eok, edata = pcall(_cjson.decode, estr)
                    if eok and edata then
                        local editData, editTotal = parseMapJson(edata)
                        if editData and next(editData) then
                            if editTotal > 0 then TOTAL_FLOORS = editTotal end
                            for f, lines in pairs(editData) do
                                MAP_DATA[f] = lines
                            end
                            log:Write(LOG_INFO, "[MapData] 已覆盖沙箱编辑地图")
                        end
                    end
                end
            end
        end
    else
        -- 随机模式：使用随机生成器
        TOTAL_FLOORS = 50
        BOSS_FLOORS = {[10]="J",[18]="X",[20]="X",[30]="L",[40]="N",[50]="7"}
        local mapSeed = os.time()
        math.randomseed(mapSeed)
        MAP_DATA = MapGenerator.generateAllFloors(mapSeed)
    end

    -- 重置玩家属性
    player.row = 2
    player.col = 2
    player.floor = 1
    local diff = getDifficultyDef()
    player.hp = 100 + (diff.hpBonus or 0)
    player.atk = 10
    player.def = 8
    player.gold = 0
    player.yellowKeys = 0
    player.blueKeys = 0
    player.redKeys = 0
    player.facing = "down"
    player.skills = {}
    player.relics = {}
    player.gems = {}
    player.cardCostMods = {}
    player.shopUpgradeBuys = {}
    player.shopSoldCards = {}
    player.level = 1
    player.exp = 0
    player.charIdx = charSelect.selectedChar  -- 记录当前角色索引

    -- 使用角色专属初始卡组
    player.cards = {}
    for _, cardId in ipairs(char.startCards) do
        table.insert(player.cards, {id = cardId, usesLeft = -1})
    end

    player.mp = 5
    player.maxMp = 10
    player.mpRegen = 5
    player.drawCount = 3

    -- 应用角色被动技能
    local passiveKey = char.passive
    if passiveKey then
        local skill = SKILL_DEF[passiveKey]
        if skill then
            player.skills[skill.id] = true
            -- 被动效果: 灵能(M)=每回合额外+1MP恢复, 多抽(D)=每回合多抽1张
            if passiveKey == "M" then
                player.mpRegen = player.mpRegen + 1
            elseif passiveKey == "Q" then
                player.drawCount = player.drawCount + 1
            end
        end
    end

    gameState = "playing"
    msg.text = ""
    msg.timer = 0
    moveAnim.active = false
    autoPath = {}
    battle.active = false
    initMaps()
    -- 找到玩家起始位置
    for r = 1, GRID do
        for c = 1, GRID do
            if maps[1][r][c] == 'P' then
                player.row = r
                player.col = c
                maps[1][r][c] = '.'
                break
            end
        end
    end
    playBgmForFloor(1)
    showMessage("欢迎来到魔塔！当前版本开放至第18层", 2.5, 200, 220, 255)
end

--- 切换到标题BGM
function playTitleBgm()
    if currentBgmTrack == "title" then return end
    local s = cache:GetResource("Sound", BGM_TRACKS.title)
    if s then
        s:SetLooped(true)
        bgmSource:Play(s)
        currentBgmTrack = "title"
    end
end

--- 重新开始游戏（回到标题画面）
function restartGame()
    gameState = "title"
    if saveSlotPanel.open then closeSaveSlotPanel() end
    playTitleBgm()
end

--- 处理点击/触摸坐标
function handleClick(inputX, inputY)
    local lx = inputX / dpr
    local ly = inputY / dpr

    -- 标题画面
    if gameState == "title" then
        -- 存档槽位面板打开时优先处理
        if saveSlotPanel.open then
            -- 确认覆盖模式
            if saveSlotPanel.confirmSlot then
                local cr = saveSlotPanel.confirmRects
                if cr.confirm and lx >= cr.confirm.x and lx <= cr.confirm.x + cr.confirm.w
                   and ly >= cr.confirm.y and ly <= cr.confirm.y + cr.confirm.h then
                    playSfx("btn", 0.5)
                    saveSlotPanel.confirmSlot = nil
                    return
                end
                if cr.cancel and lx >= cr.cancel.x and lx <= cr.cancel.x + cr.cancel.w
                   and ly >= cr.cancel.y and ly <= cr.cancel.y + cr.cancel.h then
                    playSfx("btn", 0.5)
                    saveSlotPanel.confirmSlot = nil
                    saveSlotPanel.confirmRects = {}
                    return
                end
                saveSlotPanel.confirmSlot = nil
                saveSlotPanel.confirmRects = {}
                return
            end
            -- 关闭按钮
            local cr = saveSlotPanel.closeRect
            if cr and lx >= cr.x and lx <= cr.x + cr.w and ly >= cr.y and ly <= cr.y + cr.h then
                playSfx("btn", 0.5)
                closeSaveSlotPanel()
                return
            end
            -- 槽位点击（标题屏只支持 load 模式）
            for _, sr in ipairs(saveSlotPanel.slotRects) do
                if lx >= sr.x and lx <= sr.x + sr.w and ly >= sr.y and ly <= sr.y + sr.h then
                    playSfx("btn", 0.5)
                    if hasSaveFile(sr.slot) then
                        closeSaveSlotPanel()
                        if not loadGame(sr.slot) then
                            showMessage("读档失败", 1.5, 255, 80, 80)
                        end
                    else
                        showMessage("该槽位没有存档", 1.0, 255, 200, 80)
                    end
                    return
                end
            end
            -- 点击面板外部关闭
            closeSaveSlotPanel()
            return
        end
        -- 图鉴打开时优先处理
        if codex.open then
            -- 已选中卡牌时，点击任意处关闭预览
            if codex.selectedCard then
                codex.selectedCard = nil
                return
            end
            -- Tab 点击检测
            for ti, tr in ipairs(codex.tabRects) do
                if lx >= tr.x and lx <= tr.x + tr.w and ly >= tr.y and ly <= tr.y + tr.h then
                    if codex.tab ~= ti then
                        playSfx("btn", 0.5)
                        codex.tab = ti
                        codex.scroll = 0
                        codex.selectedCard = nil
                    end
                    return
                end
            end
            -- 卡牌筛选按钮点击检测
            for _, fr in ipairs(codex.filterRects) do
                if lx >= fr.x and lx <= fr.x + fr.w and ly >= fr.y and ly <= fr.y + fr.h then
                    if codex.cardFilter ~= fr.filter then
                        playSfx("btn", 0.5)
                        codex.cardFilter = fr.filter
                        codex.scroll = 0
                        codex.selectedCard = nil
                    end
                    return
                end
            end
            -- 点击面板外部关闭
            local pr = codex.panelRect
            if pr and (lx < pr.x or lx > pr.x + pr.w or ly < pr.y or ly > pr.y + pr.h) then
                codex.open = false
                codex.scroll = 0
                return
            end
            -- 开始拖拽滚动（卡牌选中在 MouseUp 时判断，避免拖拽误触）
            codex.drag.active = true
            codex.drag.startY = ly
            codex.drag.startScroll = codex.scroll
            codex.drag.startX = lx
            return
        end
        local sb = menuRects.title.startBtn
        if sb and lx >= sb.x and lx <= sb.x + sb.w and ly >= sb.y and ly <= sb.y + sb.h then
            playSfx("btn", 0.5)
            gameState = "mode_select"
            return
        end
        local cb = menuRects.title.continueBtn
        if cb and lx >= cb.x and lx <= cb.x + cb.w and ly >= cb.y and ly <= cb.y + cb.h then
            playSfx("btn", 0.5)
            openSaveSlotPanel("load")
            return
        end
        local gb = menuRects.title.galleryBtn
        if gb and lx >= gb.x and lx <= gb.x + gb.w and ly >= gb.y and ly <= gb.y + gb.h then
            playSfx("btn", 0.5)
            codex.open = true
            codex.scroll = 0
            codex.tab = 1
            return
        end
        local chb = menuRects.title.charBtn
        if chb and lx >= chb.x and lx <= chb.x + chb.w and ly >= chb.y and ly <= chb.y + chb.h then
            playSfx("btn", 0.5)
            charSelect.fromTitle = true
            gameState = "char_select"
            charSelectRects.startBtn = nil
            return
        end
        local eb = menuRects.title.editorBtn
        if ENABLE_DEV_TOOLS and eb and lx >= eb.x and lx <= eb.x + eb.w and ly >= eb.y and ly <= eb.y + eb.h then
            playSfx("btn", 0.5)
            gameState = "editor"
            return
        end
        return
    end

    -- 编辑器界面
    if ENABLE_DEV_TOOLS and gameState == "editor" then
        handleEditorClick(lx, ly)
        return
    elseif gameState == "editor" then
        gameState = "title"
        return
    end

    -- 模式选择界面
    if gameState == "mode_select" then
        -- 模式点击
        for _, rect in ipairs(menuRects.mode.modes) do
            if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
                if rect.mode == 1 then return end  -- 随机地图敬请期待，不可选
                playSfx("btn", 0.5)
                charSelect.selectedMode = rect.mode
                return
            end
        end
        -- 难度点击
        for _, rect in ipairs(menuRects.mode.difficulties or {}) do
            if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
                playSfx("btn", 0.5)
                charSelect.selectedDifficulty = rect.difficulty
                return
            end
        end
        -- 下一步按钮
        local nb = menuRects.mode.nextBtn
        if nb and lx >= nb.x and lx <= nb.x + nb.w and ly >= nb.y and ly <= nb.y + nb.h then
            playSfx("btn", 0.5)
            charSelect.fromTitle = false
            gameState = "char_select"
            charSelectRects.startBtn = nil
            return
        end
        -- 返回按钮
        local bb = menuRects.mode.backBtn
        if bb and lx >= bb.x and lx <= bb.x + bb.w and ly >= bb.y and ly <= bb.y + bb.h then
            playSfx("btn", 0.5)
            gameState = "title"
            playTitleBgm()
            return
        end
        return
    end

    -- 角色选择界面
    if gameState == "char_select" then
        -- 左箭头点击
        local al = charSelectRects.arrowLeft
        if al and lx >= al.x and lx <= al.x + al.w and ly >= al.y and ly <= al.y + al.h then
            playSfx("btn", 0.5)
            charSelect.selectedChar = math.max(1, charSelect.selectedChar - 1)
            return
        end
        -- 右箭头点击
        local ar = charSelectRects.arrowRight
        if ar and lx >= ar.x and lx <= ar.x + ar.w and ly >= ar.y and ly <= ar.y + ar.h then
            playSfx("btn", 0.5)
            charSelect.selectedChar = math.min(#CHARACTER_LIST, charSelect.selectedChar + 1)
            return
        end
        -- 开始按钮
        local sb = charSelectRects.startBtn
        if sb and lx >= sb.x and lx <= sb.x + sb.w and ly >= sb.y and ly <= sb.y + sb.h then
            playSfx("btn", 0.5)
            startGame()
            return
        end
        -- 返回按钮
        local bb = charSelectRects.backBtn
        if bb and lx >= bb.x and lx <= bb.x + bb.w and ly >= bb.y and ly <= bb.y + bb.h then
            playSfx("btn", 0.5)
            if charSelect.fromTitle then
                charSelect.fromTitle = false
                gameState = "title"
                playTitleBgm()
            else
                gameState = "mode_select"
            end
            return
        end
        return
    end

    -- 卡牌开发者工具打开时：优先处理
    if ENABLE_DEV_TOOLS and cardDev.active then
        cardDev.handleClick(lx, ly)
        return
    elseif cardDev.active then
        cardDev.active = false
    end

    -- 开发者面板打开时：优先处理
    if ENABLE_DEV_TOOLS and dev.mode then
        handleDevClick(lx, ly)
        return
    elseif dev.mode then
        dev.mode = false
    end

    -- 遗物详情弹窗打开时：点击任意处关闭
    if relicDetail.open then
        relicDetail.open = false
        relicDetail.id = nil
        return
    end

    -- 技能详情弹窗打开时：点击任意处关闭
    if relicDetail.skillOpen then
        relicDetail.skillOpen = false
        relicDetail.skillKey = nil
        return
    end

    -- 状态详情弹窗打开时：点击任意处关闭
    if battle._statusPopup then
        battle._statusPopup = nil
        return
    end

    -- 宝石装备面板打开时：处理面板内点击
    if gemEquip.open then
        -- 确认页面
        if gemEquip.confirmCardIdx then
            gemEquip.drag.active = false  -- 清除残留拖拽状态
            -- 确认镶嵌按钮
            if gemEquip.confirmRect then
                local r = gemEquip.confirmRect
                if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                    playSfx("btn", 0.5)
                    local card = player.cards[gemEquip.confirmCardIdx]
                    if card then
                        if card.gem and not player.relics.gemCraft then
                            showMessage("更换宝石需要宝石工匠锤", 1.5, 255, 170, 100)
                            return
                        end
                        -- 返还已镶嵌的旧宝石到背包
                        if card.gem then
                            player.gems[card.gem] = (player.gems[card.gem] or 0) + 1
                        end
                        if gemEquip.fromMap then
                            -- 来自地图拾取：清除地图格子，直接镶嵌（不经过背包）
                            if gemEquip.mapFloor and gemEquip.mapRow and gemEquip.mapCol then
                                maps[gemEquip.mapFloor][gemEquip.mapRow][gemEquip.mapCol] = '.'
                            end
                        else
                            -- 来自背包：扣除背包中的宝石
                            player.gems[gemEquip.gemId] = (player.gems[gemEquip.gemId] or 0) - 1
                            if player.gems[gemEquip.gemId] <= 0 then player.gems[gemEquip.gemId] = nil end
                        end
                        card.gem = gemEquip.gemId
                        local gemDef = GEM_DEF[gemEquip.gemId]
                        local cdef = CARD_DEF[card.id]
                        local cname = cdef and cdef.name or card.id
                        showMessage(gemDef.name .. " 已镶嵌到 " .. cname .. "！", 1.5, gemDef.r, gemDef.g, gemDef.b)
                    end
                    gemEquip.open = false
                    gemEquip.gemId = nil
                    gemEquip.confirmCardIdx = nil
                    gemEquip.fromMap = false
                    return
                end
            end
            -- 取消/返回按钮
            if gemEquip.cancelRect then
                local r = gemEquip.cancelRect
                if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                    playSfx("btn", 0.5)
                    gemEquip.confirmCardIdx = nil  -- 返回选卡列表
                    return
                end
            end
            -- 点击面板外部 → 返回选卡列表
            gemEquip.confirmCardIdx = nil
            return
        end
        -- 选卡列表页面：开始拖拽跟踪（松手时判断是滚动还是点击）
        gemEquip.drag.active = true
        gemEquip.drag.startY = ly
        gemEquip.drag.startX = lx
        gemEquip.drag.startScroll = gemEquip.scroll
        return
    end

    -- 牌库/弃牌堆查看弹窗：点击关闭
    if pileView.open then
        pileView.drag.active = true
        pileView.drag.startY = ly
        pileView.drag.startScroll = pileView.scroll
        return
    end

    -- 手册/图鉴打开时：点击关闭
    if handbookOpen then
        handbookOpen = false
        return
    end
    if cardBook.open then
        if gemPanel.open then
            -- 宝石面板打开时，处理面板内点击
            -- 拆卸按钮
            if gemPanel.removeRect then
                local r = gemPanel.removeRect
                if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                    playSfx("btn", 0.5)
                    local card = player.cards[gemPanel.cardIdx]
                    if card and card.gem then
                        if not player.relics.gemCraft then
                            showMessage("拆卸宝石需要宝石工匠锤", 1.5, 255, 170, 100)
                            return
                        end
                        player.gems[card.gem] = (player.gems[card.gem] or 0) + 1
                        showMessage(GEM_DEF[card.gem].name .. " 已拆卸", 1.0, 255, 200, 100)
                        card.gem = nil
                    end
                    gemPanel.open = false
                    return
                end
            end
            -- 宝石选项
            for _, r in ipairs(gemPanel.rects) do
                if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                    playSfx("btn", 0.5)
                    local card = player.cards[gemPanel.cardIdx]
                    if card then
                        -- 如果已有宝石，必须有工匠锤才能更换
                        if card.gem and not player.relics.gemCraft then
                            showMessage("更换宝石需要宝石工匠锤", 1.5, 255, 170, 100)
                            return
                        end
                        if card.gem then
                            player.gems[card.gem] = (player.gems[card.gem] or 0) + 1
                        end
                        -- 消耗并镶嵌新宝石
                        player.gems[r.gemId] = (player.gems[r.gemId] or 0) - 1
                        if player.gems[r.gemId] <= 0 then player.gems[r.gemId] = nil end
                        card.gem = r.gemId
                        local gd = GEM_DEF[r.gemId]
                        showMessage(gd.name .. " 已镶嵌！" .. gd.desc, 1.5, gd.r, gd.g, gd.b)
                    end
                    gemPanel.open = false
                    return
                end
            end
            -- 点击面板外部 → 关闭宝石面板
            gemPanel.open = false
            return
        end
        -- 开始拖拽滚动（松手时判断是关闭还是滚动/点击卡牌）
        cardBook.drag.active = true
        cardBook.drag.startY = ly
        cardBook.drag.startScroll = cardBook.scroll
        cardBook.drag.startX = lx  -- 记录起始X用于卡牌点击检测
        return
    end

    -- 跳跃上楼弹窗
    if stairUI.active then
        if handleStairUIClick(lx, ly) then return end
    end

    -- 商店弹窗：点击购买/关闭
    if shopOpen then
        -- 关闭按钮
        if shopCloseRect then
            local r = shopCloseRect
            if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                playSfx("btn", 0.5)
                shopOpen = false
                return
            end
        end
        -- 商品购买按钮
        if type(shopItemRects) ~= "table" then shopItemRects = {} end
        if type(shopItems) ~= "table" then shopItems = {} end
        for _, rect in ipairs(shopItemRects) do
            if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
                playSfx("btn", 0.5)
                local item = shopItems[rect.index]
                if item and player.gold >= item.cost then
                    player.gold = player.gold - item.cost
                    item.action()
                    local shouldRefreshShop = false
                    if item.isCard and item.cardId then
                        player.shopSoldCards = player.shopSoldCards or {}
                        local floorKey = tostring(player.floor)
                        player.shopSoldCards[floorKey] = player.shopSoldCards[floorKey] or {}
                        player.shopSoldCards[floorKey][item.cardId] = true
                        shouldRefreshShop = true
                    end
                    if item.isUpgrade then
                        player.shopUpgradeBuys = type(player.shopUpgradeBuys) == "table" and player.shopUpgradeBuys or {}
                        player.shopUpgradeBuys[item.id] = (player.shopUpgradeBuys[item.id] or 0) + 1
                        shouldRefreshShop = true
                    end
                    if shouldRefreshShop then
                        local ok, items = pcall(getShopItems, player.floor)
                        shopItems = ok and items or shopItems
                    end
                    playSfx("pickup", 1.0)
                    showMessage(item.name .. " 购买成功！", 1.5, 100, 255, 100)
                else
                    showMessage("金币不足！", 1.5, 255, 100, 100)
                end
                return
            end
        end
        -- 弹窗内阻止其他交互
        return
    end

    -- 升级选卡弹窗：点击选中 + 确认
    if levelUp.open then
        -- 检测看广告刷新按钮
        if levelUp.refreshRect then
            local r = levelUp.refreshRect
            if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                playSfx("btn", 0.5)
                sdk:ShowRewardVideoAd(function(result)
                    if result.success then
                        levelUp.candidates = generateLevelUpCandidates(true)
                        levelUp.selectedIndex = nil
                        levelUp.adRefreshUsed = levelUp.adRefreshUsed + 1
                        showMessage("卡牌已刷新！", 1.0, 180, 160, 255)
                    else
                        showMessage("广告播放失败", 1.0, 255, 100, 100)
                    end
                end)
                return
            end
        end
        -- 先检测确认按钮
        if levelUp.confirmRect and levelUp.selectedIndex then
            local r = levelUp.confirmRect
            if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                playSfx("btn", 0.5)
                selectLevelUpCard(levelUp.selectedIndex)
                return
            end
        end
        -- 再检测卡牌点击（选中/取消选中）
        for _, rect in ipairs(levelUp.cardRects) do
            if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
                playSfx("btn", 0.5)
                if levelUp.selectedIndex == rect.index then
                    levelUp.selectedIndex = nil  -- 取消选中
                else
                    levelUp.selectedIndex = rect.index  -- 选中
                end
                return
            end
        end
        -- 弹窗打开时，阻止其他交互
        return
    end

    if gameState == "gameover" then
        -- 失败界面：存档槽位面板打开时优先处理
        if saveSlotPanel.open then
            -- 确认覆盖模式（读档不需要确认覆盖，但保险处理）
            if saveSlotPanel.confirmSlot then
                saveSlotPanel.confirmSlot = nil
                saveSlotPanel.confirmRects = {}
                return
            end
            -- 关闭按钮
            local cr = saveSlotPanel.closeRect
            if cr and lx >= cr.x and lx <= cr.x + cr.w and ly >= cr.y and ly <= cr.y + cr.h then
                playSfx("btn", 0.5)
                closeSaveSlotPanel()
                return
            end
            -- 槽位点击（只支持读档）
            for _, sr in ipairs(saveSlotPanel.slotRects) do
                if lx >= sr.x and lx <= sr.x + sr.w and ly >= sr.y and ly <= sr.y + sr.h then
                    playSfx("btn", 0.5)
                    if hasSaveFile(sr.slot) then
                        closeSaveSlotPanel()
                        if loadGame(sr.slot) then
                            -- loadGame 内部已设置 gameState="playing" 并播放 BGM
                        else
                            showMessage("读档失败", 1.5, 255, 80, 80)
                        end
                    else
                        showMessage("该槽位没有存档", 1.0, 255, 200, 80)
                    end
                    return
                end
            end
            -- 点击面板外部关闭
            closeSaveSlotPanel()
            return
        end
        -- 读档按钮
        local lr = endScreenRects.loadBtn
        if lr and lx >= lr.x and lx <= lr.x + lr.w and ly >= lr.y and ly <= lr.y + lr.h then
            playSfx("btn", 0.5)
            openSaveSlotPanel("load")
            return
        end
        -- 重新开始按钮
        local rr = endScreenRects.restartBtn
        if rr and lx >= rr.x and lx <= rr.x + rr.w and ly >= rr.y and ly <= rr.y + rr.h then
            playSfx("btn", 0.5)
            restartGame()
            return
        end
        return
    end

    if gameState ~= "playing" then
        restartGame()
        return
    end

    -- 存档槽位面板打开时优先处理
    if saveSlotPanel.open then
        -- 确认覆盖模式
        if saveSlotPanel.confirmSlot then
            local cr = saveSlotPanel.confirmRects
            if cr.confirm and lx >= cr.confirm.x and lx <= cr.confirm.x + cr.confirm.w
               and ly >= cr.confirm.y and ly <= cr.confirm.y + cr.confirm.h then
                playSfx("btn", 0.5)
                local s = saveSlotPanel.confirmSlot
                if saveGame(s) then
                    showMessage("已保存到槽位 " .. s, 1.5, 100, 255, 100)
                else
                    showMessage("保存失败", 1.5, 255, 80, 80)
                end
                closeSaveSlotPanel()
                gameMenu.open = false
                gameMenu.confirm = nil
                return
            end
            if cr.cancel and lx >= cr.cancel.x and lx <= cr.cancel.x + cr.cancel.w
               and ly >= cr.cancel.y and ly <= cr.cancel.y + cr.cancel.h then
                playSfx("btn", 0.5)
                saveSlotPanel.confirmSlot = nil
                saveSlotPanel.confirmRects = {}
                return
            end
            -- 点击其他区域取消确认
            saveSlotPanel.confirmSlot = nil
            saveSlotPanel.confirmRects = {}
            return
        end
        -- 关闭按钮
        local cr = saveSlotPanel.closeRect
        if cr and lx >= cr.x and lx <= cr.x + cr.w and ly >= cr.y and ly <= cr.y + cr.h then
            playSfx("btn", 0.5)
            closeSaveSlotPanel()
            return
        end
        -- 槽位点击
        for _, sr in ipairs(saveSlotPanel.slotRects) do
            if lx >= sr.x and lx <= sr.x + sr.w and ly >= sr.y and ly <= sr.y + sr.h then
                playSfx("btn", 0.5)
                if saveSlotPanel.mode == "save" then
                    if hasSaveFile(sr.slot) then
                        -- 已有存档，弹确认
                        saveSlotPanel.confirmSlot = sr.slot
                    else
                        -- 空槽位，直接保存
                        if saveGame(sr.slot) then
                            showMessage("已保存到槽位 " .. sr.slot, 1.5, 100, 255, 100)
                        else
                            showMessage("保存失败", 1.5, 255, 80, 80)
                        end
                        closeSaveSlotPanel()
                        gameMenu.open = false
                        gameMenu.confirm = nil
                    end
                elseif saveSlotPanel.mode == "load" then
                    if hasSaveFile(sr.slot) then
                        closeSaveSlotPanel()
                        gameMenu.open = false
                        gameMenu.confirm = nil
                        if loadGame(sr.slot) then
                            -- loadGame 内部已有 showMessage
                        else
                            showMessage("读档失败", 1.5, 255, 80, 80)
                        end
                    else
                        showMessage("该槽位没有存档", 1.0, 255, 200, 80)
                    end
                end
                return
            end
        end
        -- 点击面板外部关闭
        closeSaveSlotPanel()
        return
    end

    -- 游戏菜单打开时优先处理
    if gameMenu.open then
        for _, br in ipairs(gameMenu.btnRects) do
            if lx >= br.x and lx <= br.x + br.w and ly >= br.y and ly <= br.y + br.h then
                playSfx("btn", 0.5)
                if br.key == "save" then
                    openSaveSlotPanel("save")
                elseif br.key == "load" then
                    openSaveSlotPanel("load")
                elseif br.key == "title" then
                    -- 进入确认模式
                    gameMenu.confirm = "title"
                elseif br.key == "confirm_title" then
                    -- 确认返回标题
                    gameMenu.open = false
                    gameMenu.confirm = nil
                    restartGame()
                elseif br.key == "cancel_confirm" then
                    -- 取消确认，回到主菜单
                    gameMenu.confirm = nil
                elseif br.key == "toggle_autosave" then
                    gameAutoSave = not gameAutoSave
                    showMessage(gameAutoSave and "自动存档：开" or "自动存档：关", 1.0, 180, 200, 255)
                elseif br.key == "close" then
                    gameMenu.open = false
                    gameMenu.confirm = nil
                end
                return
            end
        end
        -- 点击面板外部：确认模式下回到主菜单，否则关闭
        if gameMenu.confirm then
            gameMenu.confirm = nil
        else
            gameMenu.open = false
        end
        return
    end

    -- 楼层区域连击检测（隐藏触发开发者面板）
    local rowH = statsH / 3
    local btnFs = math.max(10, rowH * 0.52)
    local floorW = btnFs * 2.5
    if ENABLE_DEV_TOOLS and lx <= floorW + 10 and ly <= rowH then
        dev.tapCount = dev.tapCount + 1
        dev.tapTimer = 1.5  -- 1.5秒内连击有效
        if dev.tapCount >= 5 then
            dev.mode = true
            dev.tapCount = 0
            dev.scroll = 0
            showMessage("DEV MODE", 1.0, 255, 200, 50)
            return
        end
    end

    -- 功能按钮检测（第一行右侧）
    local btnH = rowH * 0.7
    local y1 = rowH / 2
    local btnY = y1 - btnH / 2

    -- 怪物图鉴按钮检测（第一行）
    local hbBtnW = btnFs * 2.5
    local hbBtnX = logicalW - hbBtnW - 6
    if not battle.active and lx >= hbBtnX and lx <= hbBtnX + hbBtnW and ly >= btnY and ly <= btnY + btnH then
        playSfx("btn", 0.5)
        handbookOpen = true
        return
    end

    -- 卡牌图鉴按钮检测（第一行）
    local cbBtnW = btnFs * 2.5
    local cbBtnX = hbBtnX - cbBtnW - 4
    if not battle.active and lx >= cbBtnX and lx <= cbBtnX + cbBtnW and ly >= btnY and ly <= btnY + btnH then
        playSfx("btn", 0.5)
        cardBook.open = true
        cardBook.scroll = 0
        gemPanel.open = false
        gemPanel.cardIdx = nil
        return
    end

    -- 菜单按钮检测（第一行）
    local menuBtnW = btnFs * 2.5
    local menuBtnX = cbBtnX - menuBtnW - 4
    if not battle.active and lx >= menuBtnX and lx <= menuBtnX + menuBtnW and ly >= btnY and ly <= btnY + btnH then
        playSfx("btn", 0.5)
        gameMenu.open = true
        gameMenu.confirm = nil
        return
    end

    -- 技能HUD图标点击 → 打开详情弹窗
    for _, rect in ipairs(relicDetail.skillRects) do
        if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
            playSfx("btn", 0.5)
            relicDetail.skillOpen = true
            relicDetail.skillKey = rect.key
            return
        end
    end

    -- 遗物HUD图标点击 → 打开详情弹窗
    for _, rect in ipairs(relicHudRects) do
        if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
            playSfx("btn", 0.5)
            relicDetail.open = true
            relicDetail.id = rect.relicId
            return
        end
    end

    -- 战斗状态图标点击 → 打开详情弹窗
    if battle.active and battle._statusRects then
        for _, rect in ipairs(battle._statusRects) do
            if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
                playSfx("btn", 0.5)
                battle._statusPopup = {st = rect.st}
                return
            end
        end
    end

    -- 怪物debuff图标点击 → 打开详情弹窗
    if battle.active and battle._moEffectRects then
        for _, rect in ipairs(battle._moEffectRects) do
            if lx >= rect.x and lx <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
                playSfx("btn", 0.5)
                battle._statusPopup = {st = rect.st}
                return
            end
        end
    end

    -- 战斗中的交互
    if battle.active then
        -- 倍速按钮检测（任何阶段都可切换）
        local sb = battle._speedBtn
        if sb and lx >= sb.x and lx <= sb.x + sb.w and ly >= sb.y and ly <= sb.y + sb.h then
            playSfx("btn", 0.5)
            local spd = battle.speed or 1
            if spd >= 3 then battle.speed = 1
            else battle.speed = spd + 1 end
            return
        end

        -- 等待选卡或效果展示阶段：检查卡牌点击/拖拽
        if battle.phase == "waiting_for_card" or battle.phase == "card_effect" then
            -- 结束回合按钮检测（仅 waiting 阶段，consumeSelect 模式下禁用）
            if battle.phase == "waiting_for_card" and not battle.consumeSelect then
                -- 检测是否点击了逃跑按钮区域，不是则取消逃跑确认
                local fb0 = battle._fleeBtn
                local hitFlee = fb0 and lx >= fb0.x and lx <= fb0.x + fb0.w and ly >= fb0.y and ly <= fb0.y + fb0.h
                if not hitFlee and battle.fleeConfirm then
                    battle.fleeConfirm = false
                end

                local eb = battle._endTurnBtn
                if eb and lx >= eb.x and lx <= eb.x + eb.w and ly >= eb.y and ly <= eb.y + eb.h then
                    playSfx("btn", 0.5)
                    cardPlayQueue = {}
                    battle.autoEndTimer = nil
                    battle.fleeConfirm = false
                    battle.phase = "end_turn"
                    battle.timer = 0
                    return
                end

                -- 逃跑按钮检测
                local fb = battle._fleeBtn
                if fb and lx >= fb.x and lx <= fb.x + fb.w and ly >= fb.y and ly <= fb.y + fb.h then
                    playSfx("btn", 0.5)
                    if battle.fleeConfirm then
                        -- 二次确认：进入逃跑攻击阶段
                        battle.fleeConfirm = false
                        battle.fleeing = true
                        battle.phase = "monster_atk"
                        battle.timer = 0
                        battle.atkIndex = 0
                        for i, mo in ipairs(battle.monsters) do
                            if mo.alive then battle.atkIndex = i; break end
                        end
                        if battle.atkIndex > 0 then
                            local mo = battle.monsters[battle.atkIndex]
                            battle.atkMonsterDmg = mo.dmg
                            battle.atkMonsterName = mo.name
                            battle.atkShieldAbsorb = 0
                            -- 预计算圣盾状态
                            local hasPreemptive = false
                            for _, m in ipairs(battle.monsters) do
                                if m.alive and m.preemptive then hasPreemptive = true; break end
                            end
                            local shieldRound = hasPreemptive and 0 or 1
                            battle.atkShielded = battle.hasShield and battle.round == shieldRound
                            -- 预计算实际伤害并立即扣血
                            local preDmg = mo.dmg
                            if battle.guardActive then preDmg = math.min(preDmg, 1)
                            elseif battle.atkShielded then preDmg = 0 end
                            if battle.immortalActive then preDmg = 0 end
                            if preDmg > 0 and not battle.guardActive and not battle.atkShielded and battle.shieldHP > 0 and not (mo.skill and mo.skill.id == "pierceShield") then
                                battle.atkShieldAbsorb = math.min(battle.shieldHP, mo.dmg)
                                if battle.shieldHP >= preDmg then preDmg = 0
                                else preDmg = preDmg - battle.shieldHP end
                            end
                            if battle.berserkerRageActive and preDmg > 0 then preDmg = math.floor(preDmg * 1.3) end
                            battle.atkActualDmg = preDmg
                            battle.playerHP = battle.playerHP - preDmg
                            if battle.undyingActive and battle.playerHP < 1 then battle.playerHP = 1 end
                            playSfx("monster_attack", 0.3)
                            if battle.guardActive then
                                playSfx("block", 0.5)
                            elseif battle.atkShielded then
                                playSfx("block", 0.5)
                            elseif battle.atkShieldAbsorb > 0 then
                                playSfx("block", 0.4)
                                battle.shakeOffset = -3
                            elseif preDmg > 0 then
                                playSfx("hurt", 0.5)
                                battle.shakeOffset = -8
                            else
                                battle.shakeOffset = -8
                            end
                            applyCurseOnHit(mo, battle.atkIndex)
                        else
                            fleeBattle()
                        end
                    else
                        battle.fleeConfirm = true
                    end
                    return
                end

                -- 牌库按钮点击
                local dr = battle._deckRect
                if dr and lx >= dr.x and lx <= dr.x + dr.w and ly >= dr.y and ly <= dr.y + dr.h then
                    playSfx("btn", 0.5)
                    pileView.open = true
                    pileView.pileType = "deck"
                    pileView.scroll = 0
                    return
                end

                -- 弃牌堆按钮点击
                local dcr = battle._discardRect
                if dcr and lx >= dcr.x and lx <= dcr.x + dcr.w and ly >= dcr.y and ly <= dcr.y + dcr.h then
                    playSfx("btn", 0.5)
                    pileView.open = true
                    pileView.pileType = "discard"
                    pileView.scroll = 0
                    return
                end
            end
            -- 扇形卡牌点击检测（与 drawBattleAnim 一致，使用 cardAnims）
            local numCards = #battle.hand
            if numCards > 0 and #cardAnims >= numCards then
                local isPortraitHit = logicalH > logicalW
                local cardH = isPortraitHit
                    and math.max(120, math.min(logicalW * 0.38, 165))
                    or  math.max(130, math.min(logicalH * 0.27, 180))
                cardH = math.floor(cardH * 0.9 * (cardDev.p.cardScale or 1.0))
                local cardW = math.floor(cardH * 0.68)

                -- 检测顺序：选中的卡牌优先（它在最上层），然后从右到左
                local selIdx = battle.selectedCard
                local checkOrder = {}
                if selIdx and selIdx >= 1 and selIdx <= numCards then
                    table.insert(checkOrder, selIdx)
                end
                for i = numCards, 1, -1 do
                    if i ~= selIdx then
                        table.insert(checkOrder, i)
                    end
                end

                for _, i in ipairs(checkOrder) do
                    local a = cardAnims[i]
                    if a then
                        local s = a.scale
                        local sw = cardW * s
                        local sh = cardH * s
                        -- 将点击坐标转到卡牌局部空间（锚点：底部中心）
                        local dx = lx - a.x
                        local dy = ly - a.y
                        local cosR = math.cos(-a.rot)
                        local sinR = math.sin(-a.rot)
                        local localX = dx * cosR - dy * sinR
                        local localY = dx * sinR + dy * cosR

                        if localX >= -sw / 2 and localX <= sw / 2 and localY >= -sh and localY <= 0 then
                            -- consumeOne 选择模式：点击卡牌作为消耗目标
                            if battle.consumeSelect then
                                local cs = battle.consumeSelect
                                if i ~= cs.cardIndex then
                                    -- 选中目标卡牌，执行效果
                                    cs.eatIdx = i
                                    battle.effectText = ""
                                    battle.effectTimer = 0
                                    -- 重新调用 playCard，此时 consumeSelect 已带 eatIdx
                                    playCard(cs.cardIndex)
                                end
                                -- 点击自身卡牌则忽略
                                return
                            end
                            -- 正常模式：选中并启动拖拽
                            battle.selectedCard = i
                            cardDrag.active = true
                            cardDrag.cardIndex = i
                            cardDrag.startX = lx
                            cardDrag.startY = ly
                            cardDrag.curX = lx
                            cardDrag.curY = ly
                            -- 记录点击点在卡牌内的比例偏移（0~1）
                            cardDrag.offsetX = (localX + sw / 2) / sw
                            cardDrag.offsetY = (localY + sh) / sh
                            return
                        end
                    end
                end
            end
            -- 点击怪物区域：切换攻击目标
            if battle.phase == "waiting_for_card" and battle._monsterRects then
                for _, mr in ipairs(battle._monsterRects) do
                    if lx >= mr.x and lx <= mr.x + mr.w and ly >= mr.y and ly <= mr.y + mr.h then
                        local mo = battle.monsters[mr.idx]
                        if mo and mo.alive and mr.idx ~= battle.targetIdx then
                            battle.targetIdx = mr.idx
                            playSfx("click", 0.3)
                        end
                        return
                    end
                end
            end
            -- 点击非卡牌区域
            if battle.consumeSelect then
                -- 取消 consumeOne 选择，退还 MP
                local cs = battle.consumeSelect
                battle.mp = math.min(battle.maxMp, battle.mp + cs.mpCost)
                battle.consumeSelect = nil
                battle.effectText = "已取消"
                battle.effectTimer = 0.5
                return
            end
            battle.selectedCard = nil
            return
        end
        -- 其他战斗阶段：点击跳过
        if battle.phase == "result" then
            finishBattle()
        end
        return
    end

    -- 先检查D-pad
    if handleDpadClick(lx, ly) then return end

    -- 再检查网格点击
    handleGridClick(lx, ly)
end

-- ============================================================
-- 事件处理
-- ============================================================

function Start()
    -- 创建 NanoVG 上下文
    nvgCtx = nvgCreate(1)  -- 1 = NVG_ANTIALIAS
    if nvgCtx == nil then
        log:Write(LOG_ERROR, "Failed to create NanoVG context")
        return
    end

    -- 初始化字体
    fontNormal = nvgCreateFont(nvgCtx, "sans", "font.ttf")
    if fontNormal == -1 then
        log:Write(LOG_ERROR, "Failed to load font")
    end

    -- 加载精灵图
    loadSpriteImages()

    -- 根据宿主/项目环境自动启用或关闭测试工具。
    ConfigureDevTools()

    -- 屏幕参数
    physW = graphics:GetWidth()
    physH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    logicalW = physW / dpr
    logicalH = physH / dpr
    -- 小屏适配：宽度不足500时全局缩放
    local MIN_LAYOUT_W = 500
    if logicalW < MIN_LAYOUT_W then
        dpr = physW / MIN_LAYOUT_W
        logicalW = MIN_LAYOUT_W
        logicalH = physH / dpr
    end

    -- 计算布局（地图和玩家位置在角色选择后由 startGame() 初始化）
    calcLayout()

    -- 订阅事件（NanoVGRender 需要传入 nvgCtx）
    SubscribeToEvent(nvgCtx, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")


    -- 从云端恢复存档到本地（WASM 平台刷新后本地文件丢失）
    if clientCloud then
        fileSystem:CreateDir("saves")
        pcall(function()
            clientCloud:BatchGet()
                :Get("save_slot_1")
                :Get("save_slot_2")
                :Get("save_slot_3")
                :Load({
                    ok = function(values)
                        for i = 1, MAX_SAVE_SLOTS do
                            local key = "save_slot_" .. i
                            if values[key] and values[key] ~= "" then
                                local file = File(slotPath(i), FILE_WRITE)
                                if file:IsOpen() then
                                    file:WriteString(values[key])
                                    file:Close()
                                    log:Write(LOG_INFO, "[Cloud] 恢复存档 slot " .. i .. " (" .. #values[key] .. " bytes)")
                                end
                            end
                        end
                    end,
                    error = function(code, reason)
                        log:Write(LOG_WARNING, "[Cloud] 云存档恢复失败: " .. tostring(reason))
                    end
                })
        end)
    end

    -- 标题背景视频按需加载，离开标题页后释放
    ensureTitleVideo()

    -- 初始化音频系统
    initAudio()

    -- 播放标题BGM
    local titleBgm = cache:GetResource("Sound", BGM_TRACKS.title)
    if titleBgm then
        titleBgm:SetLooped(true)
        bgmSource:Play(titleBgm)
        currentBgmTrack = "title"
    end

    log:Write(LOG_INFO, "魔塔游戏启动完成")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 标题背景视频只在标题页加载和更新，避免进游戏后继续占用解码/纹理内存
    if gameState == "title" then
        ensureTitleVideo()
        if titleVideo then
            titleVideo:Update()
        end
    elseif titleVideo or titleVideoImg then
        releaseTitleVideo()
    end

    -- 编辑器 Ctrl+Z 撤销
    if ENABLE_DEV_TOOLS and gameState == "editor" then
        if input:GetKeyPress(KEY_Z) and input:GetQualifierDown(QUAL_CTRL) then
            editorUndo()
        end
    elseif gameState == "editor" then
        gameState = "title"
    end

    -- 开发者面板滚轮滚动
    if ENABLE_DEV_TOOLS and dev.mode then
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            dev.scroll = dev.scroll - wheel * 40
            if dev.scroll < 0 then dev.scroll = 0 end
        end
    end

    -- 图鉴滚轮滚动
    if gameState == "title" and codex.open then
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            codex.scroll = codex.scroll - wheel * 40
            if codex.scroll < 0 then codex.scroll = 0 end
        end
    end

    -- 动画计时
    animTimer = animTimer + dt
    if animTimer >= ANIM_INTERVAL then
        animTimer = animTimer - ANIM_INTERVAL
        animFrameIndex = animFrameIndex % #ANIM_FRAMES + 1
    end

    -- 怪物信息浮窗计时
    if monsterInfoPopup.active then
        monsterInfoPopup.timer = monsterInfoPopup.timer + dt
        if monsterInfoPopup.timer >= monsterInfoPopup.duration then
            monsterInfoPopup.active = false
        end
    end

    -- 跳跃上楼动画更新
    if stairUI.jumpAnim.active then
        local anim = stairUI.jumpAnim
        anim.timer = anim.timer + dt
        if anim.phase == "fade_in" and anim.timer >= anim.fadeInDur then
            anim.phase = "card_burn"
            anim.timer = 0
        elseif anim.phase == "card_burn" and anim.timer >= anim.cardBurnDur then
            anim.phase = "floor_jump"
            anim.timer = 0
            anim.screenShake = 4
            playSfx("stairs", 0.8)
        elseif anim.phase == "floor_jump" then
            anim.screenShake = math.max(0, anim.screenShake - dt * 15)
            if anim.timer >= anim.floorJumpDur then
                anim.phase = "fade_out"
                anim.timer = 0
                -- 在fade_out开始时执行实际楼层切换，这样淡出时已经是新楼层
                finishJumpClimb()
            end
        elseif anim.phase == "fade_out" and anim.timer >= anim.fadeOutDur then
            anim.active = false
        end
    end

    -- 角色选择界面动画计时
    if gameState == "char_select" or gameState == "title" then
        charSelect.animTimer = charSelect.animTimer + dt
        if charSelect.animTimer >= ANIM_INTERVAL then
            charSelect.animTimer = charSelect.animTimer - ANIM_INTERVAL
            charSelect.animFrameIdx = charSelect.animFrameIdx % #ANIM_FRAMES + 1
        end
    end

    -- 开门动画推进
    for i = #doorAnims, 1, -1 do
        doorAnims[i].timer = doorAnims[i].timer + dt
        if doorAnims[i].timer >= doorAnims[i].duration then
            table.remove(doorAnims, i)
        end
    end

    -- 移动动画推进
    if moveAnim.active then
        moveAnim.t = moveAnim.t + dt
        if moveAnim.t >= MOVE_ANIM_DURATION then
            moveAnim.active = false
        end
    end

    -- 消息计时
    if msg.timer > 0 then
        msg.timer = msg.timer - dt
    end

    -- 编辑器消息计时
    if mapEditor.msgTimer > 0 then
        mapEditor.msgTimer = mapEditor.msgTimer - dt
    end

    -- 移动冷却
    if moveCooldown > 0 then
        moveCooldown = moveCooldown - dt
    end

    -- 开发者模式连击超时
    if dev.tapTimer > 0 then
        dev.tapTimer = dev.tapTimer - dt
        if dev.tapTimer <= 0 then
            dev.tapCount = 0
        end
    end

    -- 战斗动画推进
    if battle.active then
        local bdt = dt * (battle.speed or 1)  -- 倍速
        battle.timer = battle.timer + bdt
        -- 玩家抖动衰减（帧率相关，用倍速加速衰减）
        if battle.shakeOffset ~= 0 then
            local shakeFactor = 0.85 ^ (battle.speed or 1)
            battle.shakeOffset = battle.shakeOffset * shakeFactor
            if math.abs(battle.shakeOffset) < 0.5 then
                battle.shakeOffset = 0
            end
        end
        -- 每个怪物的抖动衰减
        for _, mo in ipairs(battle.monsters) do
            if mo.shakeOffset ~= 0 then
                local shakeFactor = 0.85 ^ (battle.speed or 1)
                mo.shakeOffset = mo.shakeOffset * shakeFactor
                if math.abs(mo.shakeOffset) < 0.5 then
                    mo.shakeOffset = 0
                end
            end
        end

        -- 效果文字计时
        if battle.effectTimer > 0 then
            battle.effectTimer = battle.effectTimer - bdt
        end

        -- 浮动伤害文字计时
        for i = #floatTexts, 1, -1 do
            floatTexts[i].timer = floatTexts[i].timer + bdt
            if floatTexts[i].timer >= floatTexts[i].duration then
                table.remove(floatTexts, i)
            end
        end

        if battle.phase == "waiting_for_card" then
            -- 等待玩家选择卡牌
            -- 输入在 handleClick/handleCardInput 中处理
            -- 自动结束回合倒计时（无牌可打时启动，consumeSelect 模式下暂停）
            if battle.autoEndTimer and battle.autoEndTimer > 0 and not battle.consumeSelect then
                battle.autoEndTimer = battle.autoEndTimer - bdt
                if battle.autoEndTimer <= 0 then
                    battle.autoEndTimer = nil
                    battle.phase = "end_turn"
                    battle.timer = 0
                end
            end

        elseif battle.phase == "card_effect" then
            -- 多次攻击分步动画处理
            if multiHitState then
                multiHitState.timer = multiHitState.timer + bdt
                if multiHitState.current == 0 or multiHitState.timer >= multiHitState.delay then
                    multiHitState.current = multiHitState.current + 1
                    multiHitState.timer = 0
                    if multiHitState.current <= #multiHitState.hits then
                        -- 执行当前一击
                        multiHitState.hits[multiHitState.current].fn()
                        battle.timer = 0  -- 重置 phase timer，保持在 card_effect
                    else
                        -- 全部攻击完成
                        if multiHitState.onComplete then multiHitState.onComplete() end
                        multiHitState = nil
                        battle.timer = 0
                        -- 检查是否所有怪物已死亡（暴走等多段攻击可能在过程中击杀全部）
                        if allMonstersDead() then
                            cardPlayQueue = {}
                            battle.phase = "result"
                        end
                    end
                end
                -- multiHit 期间不走下面的正常流程
            else
            -- 卡牌效果展示阶段（队列中有牌时缩短等待）
            local effectWait = #cardPlayQueue > 0 and 0.2 or 0.4
            if battle.timer >= effectWait then
                -- 队列中有待打出的牌，立即执行下一张
                if #cardPlayQueue > 0 then
                    local nextCard = table.remove(cardPlayQueue, 1)
                    local ok = playCardByRef(nextCard)
                    if not ok then
                        -- 引用失效（卡牌已不在手牌中），重置timer继续处理队列
                        battle.timer = 0
                    end
                    -- playCardByRef 内部会重新设 phase = "card_effect"
                else
                    -- 队列为空，回到选卡阶段
                    battle.phase = "waiting_for_card"
                    battle.timer = 0
                    -- 检查是否还能出牌
                    local canPlayAny = false
                    if #battle.hand > 0 then
                        for _, c in ipairs(battle.hand) do
                            local cdef = CARD_DEF[c.id]
                            if battle.mp >= getCardCost(c) and not (cdef and cdef.unplayable) then
                                canPlayAny = true
                                break
                            end
                        end
                    end
                    if not canPlayAny then
                        -- 无牌可打：设延迟自动结束回合（给玩家时间看效果）
                        battle.autoEndTimer = 0.4
                    end
                end
            end
            end -- multiHitState else end

        elseif battle.phase == "end_turn" then
            -- 结束回合：先处理手牌诅咒被动，再弃牌（带动画），等动画结束后再敌人攻击
            if not battle._endTurnCurseProcessed then
                -- 处理手牌中诅咒卡的回合结束被动效果
                local curseTexts = {}
                for _, c in ipairs(battle.hand) do
                    local cdef = CARD_DEF[c.id]
                    if cdef and cdef.endOfTurnEffect then
                        local eff = cdef.endOfTurnEffect
                        if eff.type == "damage" then
                            battle.hp = math.max(0, battle.hp - eff.amount)
                            table.insert(curseTexts, cdef.name .. " -" .. eff.amount .. "HP")
                        elseif eff.type == "def_loss" then
                            battle.curseDefLoss = (battle.curseDefLoss or 0) + eff.amount
                            for _, mo in ipairs(battle.monsters) do
                                if mo.alive and not (mo.skill and mo.skill.id == "magicAtk") then
                                    mo.baseDmg = mo.baseDmg + eff.amount
                                    mo.dmg = mo.dmg + eff.amount
                                    if mo.effects and mo.effects.weaken then
                                        mo.dmg = math.floor(mo.baseDmg / 2)
                                    end
                                end
                            end
                            table.insert(curseTexts, cdef.name .. " DEF-" .. eff.amount)
                        elseif eff.type == "shield_half" then
                            local oldShield = battle.shieldHP or 0
                            battle.shieldHP = math.floor(oldShield / 2)
                            table.insert(curseTexts, cdef.name .. " 盾减半")
                        elseif eff.type == "draw_loss" then
                            battle.fogDrawLoss = (battle.fogDrawLoss or 0) + eff.amount
                            table.insert(curseTexts, cdef.name .. " 少抽" .. eff.amount .. "张")
                        elseif eff.type == "player_poison" then
                            battle.playerPoison = (battle.playerPoison or 0) + eff.amount
                            table.insert(curseTexts, cdef.name .. " 毒+" .. eff.amount)
                        elseif eff.type == "replicate" then
                            -- 噩梦：复制1张噩梦洗入牌库（越来越多）
                            local copy = { id = c.id, playerCardIdx = -1, cardType = "normal" }
                            -- 随机插入牌库
                            local insertPos = #battle.deck > 0 and math.random(1, #battle.deck + 1) or 1
                            table.insert(battle.deck, insertPos, copy)
                            table.insert(curseTexts, cdef.name .. " 蔓延+1")
                        end
                    end
                end
                if #curseTexts > 0 then
                    battle.effectText = table.concat(curseTexts, " | ")
                    battle.effectTimer = 1.0
                    playSfx("hurt", 0.4)
                    if battle.hp <= 0 then
                        battle.phase = "result"
                        battle.win = false
                        battle.timer = 0
                        battle._endTurnCurseProcessed = nil
                    end
                end
                battle._endTurnCurseProcessed = true
                battle.timer = 0
            end
            if battle.phase ~= "end_turn" then
                -- 诅咒致死，已切换到 result 阶段
            elseif not battle._endTurnDiscarded then
                -- 第一帧：触发弃牌
                discardHand()
                battle._endTurnDiscarded = true
                battle.timer = 0
            else
            -- 等弃牌动画结束（或至少0.3秒）
            local discardDone = not cardDiscardAnim.active
            if discardDone and battle.timer >= 0.3 then
                battle._endTurnDiscarded = nil
                battle.round = battle.round + 1
                battle.phase = "monster_atk"
                battle.timer = 0
                -- 找第一个存活怪物开始攻击
                battle.atkIndex = 0
                for i, mo in ipairs(battle.monsters) do
                    if mo.alive then battle.atkIndex = i; break end
                end
                if battle.atkIndex > 0 then
                    local mo = battle.monsters[battle.atkIndex]
                    -- 狂暴：HP低于50%时攻击翻倍
                    if mo.skill and mo.skill.id == "berserk" and mo.hp < mo.maxHP * 0.5 then
                        local bAtk = mo.atk * 2
                        local newDmg = math.max(0, bAtk - player.def)
                        if player.skills.tough then newDmg = math.floor(newDmg * 0.75) end
                        mo.dmg = newDmg
                    end
                    battle.atkMonsterDmg = mo.dmg
                    battle.atkMonsterName = mo.name
                    battle.atkShieldAbsorb = 0
                    -- 预计算圣盾状态
                    local hasPreemptive = false
                    for _, m in ipairs(battle.monsters) do
                        if m.alive and m.preemptive then hasPreemptive = true; break end
                    end
                    local shieldRound = hasPreemptive and 0 or 1
                    battle.atkShielded = battle.hasShield and battle.round == shieldRound
                    -- 预计算实际伤害并立即扣血（让HP条同步刷新）
                    local preDmg = mo.dmg
                    if battle.guardActive then preDmg = math.min(preDmg, 1)
                    elseif battle.atkShielded then preDmg = 0 end
                    if battle.immortalActive then preDmg = 0 end
                    -- 护盾吸收（无视护盾的怪物跳过）
                    if preDmg > 0 and not battle.guardActive and not battle.atkShielded and battle.shieldHP > 0 and not (mo.skill and mo.skill.id == "pierceShield") then
                        battle.atkShieldAbsorb = math.min(battle.shieldHP, mo.dmg)
                        if battle.shieldHP >= preDmg then preDmg = 0
                        else preDmg = preDmg - battle.shieldHP end
                    end
                    if battle.berserkerRageActive and preDmg > 0 then preDmg = math.floor(preDmg * 1.3) end
                    battle.atkActualDmg = preDmg
                    battle.playerHP = battle.playerHP - preDmg
                    if battle.undyingActive and battle.playerHP < 1 then battle.playerHP = 1 end
                    playSfx("monster_attack", 0.3)
                    if battle.guardActive then
                        playSfx("block", 0.5)
                    elseif battle.atkShielded then
                        playSfx("block", 0.5)
                    elseif battle.atkShieldAbsorb > 0 then
                        playSfx("block", 0.4)
                        battle.shakeOffset = -3
                    elseif preDmg > 0 then
                        playSfx("hurt", 0.5)
                        battle.shakeOffset = -8
                    else
                        battle.shakeOffset = -8
                    end
                    applyCurseOnHit(mo, battle.atkIndex)
                end
            end
            end -- if battle.phase ~= "end_turn" / elseif / else

        elseif battle.phase == "monster_atk" then
            -- 逐个怪物攻击，每个怪物持续 MONSTER_ATK_INTERVAL 秒
            local MONSTER_ATK_INTERVAL = 1.0
            if battle.atkIndex <= 0 then
                -- 无存活怪物，直接进入回合结束处理
                battle.timer = MONSTER_ATK_INTERVAL
                battle.atkIndex = #battle.monsters + 1
            end

            if battle.timer >= MONSTER_ATK_INTERVAL then
                -- 当前怪物的攻击结算
                local curIdx = battle.atkIndex
                if curIdx >= 1 and curIdx <= #battle.monsters then
                    local mo = battle.monsters[curIdx]
                    if mo.alive then
                        local actualDmg = mo.dmg
                        -- 判断是否有先攻怪物
                        local hasPreemptive = false
                        for _, m in ipairs(battle.monsters) do
                            if m.alive and m.preemptive then hasPreemptive = true; break end
                        end
                        -- 圣盾免伤（先攻round==0 或 普通round==1，整轮免伤）
                        local shieldRound = hasPreemptive and 0 or 1
                        local shielded = battle.hasShield and battle.round == shieldRound

                        -- 格挡减伤（对所有怪物生效，只消耗一次）
                        if battle.guardActive then
                            -- 圣光格挡：减伤+反弹25%
                            if battle.guardGemHoly and mo.dmg > 0 then
                                local guardReflect = math.floor(mo.dmg * 0.25)
                                mo.hp = mo.hp - guardReflect
                                if mo.hp <= 0 then mo.hp = 0; mo.alive = false end
                            end
                            actualDmg = math.min(actualDmg, 1)
                        elseif shielded then
                            actualDmg = 0
                        end

                        -- 不灭：完全免疫伤害
                        if battle.immortalActive then
                            actualDmg = 0
                        end

                        -- 反射: 反弹伤害（圣光75%，普通50%）
                        if battle.reflectActive and mo.dmg > 0 then
                            local reflectRate = battle.reflectGemHoly and 0.75 or 0.5
                            local reflected = math.floor(mo.dmg * reflectRate)
                            mo.hp = mo.hp - reflected
                            mo.shakeOffset = 4
                            addFloatText("-" .. reflected, curIdx, 200, 150, 255)
                            battle.effectTimer = 0.8
                            if mo.hp <= 0 then
                                mo.hp = 0
                                mo.alive = false
                            end
                        end

                        -- 荆棘甲：反弹40%伤害
                        if (battle.thornsActive or 0) > 0 and mo.dmg > 0 then
                            local thornsDmg = math.floor(mo.dmg * (battle.thornsRate or 0.4))
                            mo.hp = mo.hp - thornsDmg
                            mo.shakeOffset = 3
                            if mo.hp <= 0 then mo.hp = 0; mo.alive = false end
                        end

                        -- 护盾吸收伤害（已在攻击开始时预扣，此处仅更新shieldHP）
                        if actualDmg > 0 and battle.shieldHP > 0 then
                            if battle.shieldHP >= actualDmg then
                                battle.shieldHP = battle.shieldHP - actualDmg
                                actualDmg = 0
                            else
                                actualDmg = actualDmg - battle.shieldHP
                                battle.shieldHP = 0
                            end
                        end
                        -- HP已在攻击开始时预扣，此处不再重复扣除
                        -- 诅咒技能已在攻击开始时立即触发（applyCurseOnHit）
                    end
                end

                -- 找下一个存活怪物
                local nextIdx = 0
                for i = curIdx + 1, #battle.monsters do
                    if battle.monsters[i].alive then nextIdx = i; break end
                end

                if nextIdx > 0 then
                    -- 还有下一个怪物，继续攻击
                    battle.atkIndex = nextIdx
                    battle.timer = 0
                    local nmo = battle.monsters[nextIdx]
                    -- 狂暴：HP低于50%时攻击翻倍
                    if nmo.skill and nmo.skill.id == "berserk" and nmo.hp < nmo.maxHP * 0.5 then
                        local bAtk = nmo.atk * 2
                        local newDmg = math.max(0, bAtk - player.def)
                        if player.skills.tough then newDmg = math.floor(newDmg * 0.75) end
                        nmo.dmg = newDmg
                    end
                    battle.atkMonsterDmg = nmo.dmg
                    battle.atkMonsterName = nmo.name
                    battle.atkShieldAbsorb = 0
                    -- 预计算实际伤害并立即扣血（圣盾状态沿用同一回合）
                    local preDmg2 = nmo.dmg
                    if battle.guardActive then preDmg2 = math.min(preDmg2, 1)
                    elseif battle.atkShielded then preDmg2 = 0 end
                    if battle.immortalActive then preDmg2 = 0 end
                    if preDmg2 > 0 and not battle.guardActive and not battle.atkShielded and battle.shieldHP > 0 then
                        battle.atkShieldAbsorb = math.min(battle.shieldHP, nmo.dmg)
                        if battle.shieldHP >= preDmg2 then preDmg2 = 0
                        else preDmg2 = preDmg2 - battle.shieldHP end
                    end
                    if battle.berserkerRageActive and preDmg2 > 0 then preDmg2 = math.floor(preDmg2 * 1.3) end
                    battle.atkActualDmg = preDmg2
                    battle.playerHP = battle.playerHP - preDmg2
                    if battle.undyingActive and battle.playerHP < 1 then battle.playerHP = 1 end
                    playSfx("monster_attack", 0.3)
                    if battle.guardActive then
                        playSfx("block", 0.5)
                    elseif battle.atkShielded then
                        playSfx("block", 0.5)
                    elseif battle.atkShieldAbsorb > 0 then
                        playSfx("block", 0.4)
                        battle.shakeOffset = -3
                    elseif preDmg2 > 0 then
                        playSfx("hurt", 0.5)
                        battle.shakeOffset = -8
                    else
                        battle.shakeOffset = -8
                    end
                    applyCurseOnHit(nmo, nextIdx)
                else
                    -- 所有怪物都攻击完毕
                    battle.atkIndex = 0
                    battle.atkMonsterDmg = 0
                    battle.atkShielded = false
                    battle.atkActualDmg = 0

                    -- 清除格挡、反射和护盾（护盾只持续一回合）
                    if battle.guardActive then
                        battle.guardActive = false
                        battle.guardGemHoly = nil
                    end
                    if battle.reflectActive then
                        battle.reflectActive = false
                        battle.reflectGemHoly = nil
                    end
                    battle.immortalActive = false
                    battle.bloodFrenzyHeal = false  -- 嗜血狂暴吸血仅持续1回合
                    battle.berserkerRageActive = false
                    battle.undyingActive = false
                    -- 嗜血本能回合递减
                    if (battle.bloodScentTurns or 0) > 0 then
                        battle.bloodScentTurns = battle.bloodScentTurns - 1
                    end
                    -- 巨力挥砍：下回合跳过攻击
                    if battle.titanSkipNext then
                        battle.titanSkipActive = true
                        battle.titanSkipNext = false
                    else
                        battle.titanSkipActive = false
                    end
                    -- 怒火层数减半
                    if (battle.fury or 0) > 0 then
                        battle.fury = math.floor(battle.fury / 2)
                    end
                    if (battle.thornsActive or 0) > 0 then
                        battle.thornsActive = battle.thornsActive - 1
                    end
                    battle.shieldHP = 0

                    -- 玩家死亡检查（HP在预扣阶段已扣减）
                    if battle.playerHP <= 0 then
                        battle.playerHP = 0
                        player.hp = 0
                        battle.phase = "result"
                        battle.timer = 0
                        checkGameOver()
                        return
                    end

                    -- 逃跑：被攻击一次后退出战斗
                    if battle.fleeing then
                        battle.fleeing = false
                        fleeBattle()
                        return
                    end

                    -- 检查怪物全灭（反射致死）
                    if allMonstersDead() then
                        battle.phase = "result"
                        battle.timer = 0
                        return
                    end

                    -- 每个存活怪物：处理独立效果倒计时
                    for _, mo in ipairs(battle.monsters) do
                        if mo.alive then
                            if mo.effects.weaken then
                                mo.effects.weaken.turns = mo.effects.weaken.turns - 1
                                if mo.effects.weaken.turns <= 0 then
                                    mo.effects.weaken = nil
                                    mo.dmg = mo.baseDmg
                                end
                            end
                            if mo.effects.poison and mo.effects.poison > 0 then
                                -- 毒素伤害：每回合造成层数点伤害，自动扣减1层
                                local poisonDmg = mo.effects.poison
                                mo.hp = mo.hp - poisonDmg
                                if mo.hp <= 0 then mo.hp = 0; mo.alive = false end
                                mo.effects.poison = mo.effects.poison - 1
                                if mo.effects.poison <= 0 then
                                    mo.effects.poison = nil
                                end
                            end
                            -- 易伤倒计时：每回合减少1层
                            if mo.effects.vulnerable and mo.effects.vulnerable > 0 then
                                mo.effects.vulnerable = mo.effects.vulnerable - 1
                                if mo.effects.vulnerable <= 0 then
                                    mo.effects.vulnerable = nil
                                end
                            end
                            if mo.regen > 0 then
                                mo.hp = math.min(mo.maxHP, mo.hp + mo.regen)
                            end
                        end
                    end

                    -- 毒素致死后检查全灭
                    if allMonstersDead() then
                        battle.phase = "result"
                        battle.timer = 0
                        return
                    end

                    -- 判断先攻
                    local hasPreemptive = false
                    for _, mo in ipairs(battle.monsters) do
                        if mo.alive and mo.preemptive then hasPreemptive = true; break end
                    end

                    -- 先攻模式首回合怪物先攻后转入等待选卡（不弃牌/抽牌）
                    if hasPreemptive and battle.round == 0 then
                        battle.round = 1
                        battle.phase = "waiting_for_card"
                        battle.timer = 0
                    else
                        -- 正常回合结束：玩家中毒结算 → MP恢复 → 抽新手牌
                        if (battle.playerPoison or 0) > 0 then
                            local pDmg = battle.playerPoison
                            battle.hp = math.max(0, battle.hp - pDmg)
                            battle.playerHP = battle.hp
                            addFloatText("毒-" .. pDmg .. "HP", nil, 120, 200, 60)
                            battle.playerPoison = battle.playerPoison - 1
                            playSfx("hurt", 0.3)
                            if battle.hp <= 0 then
                                battle.phase = "result"
                                battle.win = false
                                battle.timer = 0
                            end
                        end
                        if battle.phase == "result" then
                            -- 中毒致死，跳过后续
                        else
                        battle.mp = math.min(battle.maxMp, battle.mp + battle.mpRegen)
                        -- 迷雾效果：减少抽牌数（最少抽1张）
                        local actualDraw = player.drawCount
                        if (battle.fogDrawLoss or 0) > 0 then
                            actualDraw = math.max(1, actualDraw - battle.fogDrawLoss)
                            addFloatText("迷雾-" .. battle.fogDrawLoss .. "抽", nil, 100, 100, 120)
                            battle.fogDrawLoss = 0  -- 消耗后重置
                        end
                        drawCards(actualDraw)
                        if #battle.hand == 0 then
                            table.insert(battle.hand, {
                                id = "strike",
                                playerCardIdx = -1,
                                cardType = "normal",
                            })
                        end
                        battle.phase = "waiting_for_card"
                        battle.timer = 0
                        end -- if battle.phase == "result" else
                    end
                end
            end

        elseif battle.phase == "result" then
            if battle.timer >= BATTLE_RESULT_DURATION then
                finishBattle()
            end
        end
        return  -- 战斗中不处理其他输入
    end

    -- H键切换怪物手册
    if input:GetKeyPress(KEY_H) then
        if not battle.active and gameState == "playing" then
            handbookOpen = not handbookOpen
        end
    end

    -- 卡牌图鉴快捷键
    if input:GetKeyPress(KEY_C) then
        if not battle.active and gameState == "playing" then
            cardBook.open = not cardBook.open
        end
    end

    -- 手册/图鉴打开时不处理其他输入
    if handbookOpen or cardBook.open then return end

    if gameState ~= "playing" then return end

    -- 自动寻路行走
    if #autoPath > 0 and not moveAnim.active and not battle.active then
        autoPathTimer = autoPathTimer + dt
        if autoPathTimer >= AUTO_STEP_INTERVAL then
            autoPathTimer = 0
            local step = autoPath[1]
            table.remove(autoPath, 1)
            local prevRow, prevCol = player.row, player.col
            local dr = step[1] - player.row
            local dc = step[2] - player.col
            -- 安全检查：每步只能移动一格
            if math.abs(dr) + math.abs(dc) ~= 1 then
                autoPath = {}
                autoPathDest = nil
            else
                -- 保存剩余路径（tryMove 中 startBattle 会清空 autoPath）
                local savedPath = {}
                for i, v in ipairs(autoPath) do savedPath[i] = v end
                local savedDest = autoPathDest

                tryMove(dr, dc)
                checkGameOver()

                if gameState ~= "playing" then
                    autoPath = {}
                    autoPathDest = nil
                elseif battle.active then
                    -- 动画战斗开始，保存剩余路径待战斗结束后恢复
                    battle.savedAutoPath = savedPath
                    battle.savedAutoPathDest = savedDest
                else
                    -- 检测移动是否成功
                    local moved = (player.row ~= prevRow or player.col ~= prevCol)
                    if not moved then
                        autoPath = {}
                        autoPathDest = nil
                    end
                end
            end
        end
    end

    -- 键盘输入（中断自动寻路）
    if moveCooldown <= 0 and not moveAnim.active then
        local moved = false
        if input:GetKeyDown(KEY_UP) or input:GetKeyDown(KEY_W) then
            autoPath = {}; autoPathDest = nil
            tryMove(-1, 0)
            moved = true
        elseif input:GetKeyDown(KEY_DOWN) or input:GetKeyDown(KEY_S) then
            autoPath = {}; autoPathDest = nil
            tryMove(1, 0)
            moved = true
        elseif input:GetKeyDown(KEY_LEFT) or input:GetKeyDown(KEY_A) then
            autoPath = {}; autoPathDest = nil
            tryMove(0, -1)
            moved = true
        elseif input:GetKeyDown(KEY_RIGHT) or input:GetKeyDown(KEY_D) then
            autoPath = {}; autoPathDest = nil
            tryMove(0, 1)
            moved = true
        end
        if moved then
            moveCooldown = MOVE_CD
            checkGameOver()
        end
    end
end

function HandleNanoVGRender()
    nvgBeginFrame(nvgCtx, logicalW, logicalH, dpr)

    -- 标题画面
    if gameState == "title" then
        drawTitleScreen()
        drawCodex()
        drawSaveSlotPanel()
        nvgEndFrame(nvgCtx)
        return
    end

    -- 编辑器界面
    if ENABLE_DEV_TOOLS and gameState == "editor" then
        drawEditorScreen()
        nvgEndFrame(nvgCtx)
        return
    elseif gameState == "editor" then
        gameState = "title"
    end

    -- 模式选择界面
    if gameState == "mode_select" then
        drawModeSelect()
        nvgEndFrame(nvgCtx)
        return
    end

    -- 角色选择界面
    if gameState == "char_select" then
        drawCharSelect()
        nvgEndFrame(nvgCtx)
        return
    end

    -- 背景
    drawRoundRect(0, 0, logicalW, logicalH, 0, 22, 20, 35)

    -- 网格
    for r = 1, GRID do
        for c = 1, GRID do
            drawTile(r, c)
        end
    end

    -- Boss 脉冲红圈光环（在所有格子绘制完后叠加，避免被相邻格子背景遮挡）
    for r = 1, GRID do
        for c = 1, GRID do
            local tile = maps[player.floor][r][c]
            if isMonster(tile) then
                local m = MONSTER_DEF[tile]
                if m and m.boss then
                    local x = gridX + (c - 1) * cellSize
                    local y = gridY + (r - 1) * cellSize
                    local s = cellSize
                    local pulse = 0.5 + 0.5 * math.sin(animTimer * 3)
                    local glowR = s * 0.55 + s * 0.08 * pulse
                    nvgBeginPath(nvgCtx)
                    nvgCircle(nvgCtx, x + s / 2, y + s / 2, glowR)
                    nvgFillColor(nvgCtx, nvgRGBA(255, 40, 40, math.floor(50 * pulse)))
                    nvgFill(nvgCtx)
                    nvgBeginPath(nvgCtx)
                    nvgCircle(nvgCtx, x + s / 2, y + s / 2, glowR)
                    nvgStrokeColor(nvgCtx, nvgRGBA(255, 80, 40, math.floor(120 * pulse)))
                    nvgStrokeWidth(nvgCtx, 1.5)
                    nvgStroke(nvgCtx)
                end
            end
        end
    end

    -- 玩家
    drawPlayer()

    -- 怪物信息浮窗
    if monsterInfoPopup.active and not battle.active then
        local mi = monsterInfoPopup
        local t = mi.timer / mi.duration
        local fadeAlpha = t < 0.8 and 255 or math.floor(255 * (1 - (t - 0.8) / 0.2))

        -- 浮窗位置：在怪物格子上方
        local tileX = gridX + (mi.col - 1) * cellSize + cellSize / 2
        local tileY = gridY + (mi.row - 1) * cellSize

        local popW = math.max(cellSize * 2.5, 110)
        local popH = 38
        local popX = tileX - popW / 2
        local popY = tileY - popH - 4

        -- 边界修正
        if popX < 2 then popX = 2 end
        if popX + popW > logicalW - 2 then popX = logicalW - popW - 2 end
        if popY < 2 then popY = tileY + cellSize + 4 end  -- 格子下方

        nvgSave(nvgCtx)
        nvgGlobalAlpha(nvgCtx, fadeAlpha / 255)

        -- 背景
        nvgBeginPath(nvgCtx)
        nvgRoundedRect(nvgCtx, popX, popY, popW, popH, 5)
        nvgFillColor(nvgCtx, nvgRGBA(20, 15, 35, 220))
        nvgFill(nvgCtx)
        nvgStrokeColor(nvgCtx, nvgRGBA(150, 130, 80, 160))
        nvgStrokeWidth(nvgCtx, 1)
        nvgStroke(nvgCtx)

        -- 名字
        local fs = math.max(10, popH * 0.28)
        nvgFontSize(nvgCtx, fs)
        nvgFontFace(nvgCtx, "sans")
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(nvgCtx, nvgRGBA(255, 220, 100, 255))
        nvgText(nvgCtx, popX + 6, popY + 4, mi.name)

        -- HP ATK DEF
        nvgFontSize(nvgCtx, fs * 0.85)
        nvgFillColor(nvgCtx, nvgRGBA(255, 100, 100, 230))
        nvgText(nvgCtx, popX + 6, popY + 4 + fs + 2, "HP:" .. mi.hp)
        nvgFillColor(nvgCtx, nvgRGBA(255, 180, 80, 230))
        nvgText(nvgCtx, popX + 6 + popW * 0.35, popY + 4 + fs + 2, "ATK:" .. mi.atk)
        nvgFillColor(nvgCtx, nvgRGBA(100, 180, 255, 230))
        nvgText(nvgCtx, popX + 6 + popW * 0.68, popY + 4 + fs + 2, "DEF:" .. mi.def)

        nvgRestore(nvgCtx)
    end

    -- 状态栏
    drawStats()

    -- 方向按钮
    drawDpad()

    -- 底部开发说明
    drawGameJamNote()

    -- 战斗预估
    -- drawCombatPreview()  -- 已禁用战斗预估面板

    -- 战斗动画
    drawBattleAnim()

    -- 牌库/弃牌堆查看
    drawPileView()

    -- 怪物手册
    drawHandbook()
    drawCardBook()
    drawShop()
    drawStairUI()
    drawJumpAnim()
    drawGemEquipPanel()
    drawRelicDetail()
    drawSkillDetail()
    drawStatusPopup()

    -- 升级选卡弹窗
    drawLevelUpPopup()

    -- 游戏菜单
    drawGameMenu()

    -- 存档槽位面板（在菜单之上）
    drawSaveSlotPanel()

    -- 开发者面板
    if ENABLE_DEV_TOOLS then
        drawDevPanel()
    end

    -- 卡牌开发者工具
    if ENABLE_DEV_TOOLS then
        cardDev.draw()
    end

    -- 消息
    drawMessage()

    -- 结束画面
    if gameState == "win" or gameState == "gameover" then
        drawEndScreen()
    end

    nvgEndFrame(nvgCtx)
end

function HandleScreenMode()
    physW = graphics:GetWidth()
    physH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    logicalW = physW / dpr
    logicalH = physH / dpr
    -- 小屏适配：宽度不足500时全局缩放
    local MIN_LAYOUT_W = 500
    if logicalW < MIN_LAYOUT_W then
        dpr = physW / MIN_LAYOUT_W
        logicalW = MIN_LAYOUT_W
        logicalH = physH / dpr
    end
    calcLayout()
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    -- 跳过触摸模拟的鼠标事件，避免双重触发
    if input:GetNumTouches() > 0 then return end

    local mousePos = input:GetMousePosition()
    handleClick(mousePos.x, mousePos.y)
    if gameState == "playing" then
        checkGameOver()
    end
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    handleClick(tx, ty)
    if gameState == "playing" then
        checkGameOver()
    end
end

-- ============================================================
-- 卡牌拖拽处理
-- ============================================================
function handleDragMove(px, py)
    local lx = px / dpr
    local ly = py / dpr
    -- 编辑器拖拽绘制
    if ENABLE_DEV_TOOLS and gameState == "editor" and mapEditor.isDragging then
        handleEditorMove(lx, ly)
        return
    end
    -- 卡牌开发者工具拖拽
    if ENABLE_DEV_TOOLS and cardDev.active and cardDev.drag.active then
        local d = cardDev.drag
        local dx = lx - d.startX
        local dy = ly - d.startY
        local cw = d.cardW
        local ch = d.cardH
        local region = cardDev.regions[d.region]
        local p = cardDev.p
        local o = d.origP
        if d.mode == "move" then
            -- 整体移动区域
            if region == "name" then
                p.nameTop = o.nameTop + dy / ch
                p.nameBot = o.nameBot + dy / ch
                p.nameOffX = (o.nameOffX or 0) + dx / cw
            elseif region == "image" then
                p.imgTop = o.imgTop + dy / ch
                p.imgBot = o.imgBot + dy / ch
                p.imgOffX = (o.imgOffX or 0) + dx / cw
            elseif region == "desc" then
                p.descTop = o.descTop + dy / ch
                p.descBot = o.descBot + dy / ch
                p.descOffX = (o.descOffX or 0) + dx / cw
            elseif region == "mana" then
                p.manaX = math.max(0, o.manaX + dx / cw)
                p.manaY = math.max(0, o.manaY + dy / ch)
            elseif region == "frame" then
                -- 边框移动：同时调整 X/Y 内边距
                p.framePadX = math.max(0, math.min(0.3, o.framePadX + dx / cw))
                p.framePadY = math.max(0, math.min(0.3, o.framePadY + dy / ch))
            elseif region == "card" then
                -- card 区域移动无意义，忽略
            end
        elseif d.mode == "resize" then
            -- 右下角缩放：改变底边/右边
            if region == "name" then
                p.nameBot = o.nameBot + dy / ch
            elseif region == "image" then
                p.imgBot = o.imgBot + dy / ch
                p.imgMarginX = math.max(0, o.imgMarginX - dx / cw)
            elseif region == "desc" then
                p.descBot = o.descBot + dy / ch
                p.descPadX = math.max(0, o.descPadX - dx / cw)
            elseif region == "mana" then
                local delta = math.max(dx / cw, dy / ch)
                p.manaSize = math.max(0.03, o.manaSize + delta)
            elseif region == "frame" then
                -- 边框缩放：拖拽右下角调整内边距
                p.framePadX = math.max(0, math.min(0.3, o.framePadX - dx / cw))
                p.framePadY = math.max(0, math.min(0.3, o.framePadY - dy / ch))
            elseif region == "card" then
                -- 整张卡牌缩放
                local scaleDelta = dy / ch
                p.cardScale = math.max(0.5, math.min(3.0, (o.cardScale or 1.0) + scaleDelta))
            end
        end
        return
    end
    -- 开发者面板拖拽滚动
    if dev.drag.active then
        local dy = dev.drag.startY - ly
        dev.scroll = dev.drag.startScroll + dy
        return
    end
    -- 镶嵌面板拖拽滚动
    if gemEquip.drag.active then
        local dy = gemEquip.drag.startY - ly
        gemEquip.scroll = gemEquip.drag.startScroll + dy
        return
    end
    -- 牌堆查看拖拽滚动
    if pileView.drag.active then
        local dy = pileView.drag.startY - ly
        pileView.scroll = pileView.drag.startScroll + dy
        return
    end
    -- 图鉴拖拽滚动
    if cardBook.drag.active then
        local dy = cardBook.drag.startY - ly  -- 向上拖为正（滚动增加）
        cardBook.scroll = cardBook.drag.startScroll + dy
        return
    end
    -- 图鉴（标题页）拖拽滚动
    if codex.drag.active then
        local dy = codex.drag.startY - ly
        codex.scroll = codex.drag.startScroll + dy
        return
    end
    if not cardDrag.active then return end
    cardDrag.curX = lx
    cardDrag.curY = ly
end

function handleDragEnd(px, py)
    local lx = px / dpr
    local ly = py / dpr
    -- 编辑器拖拽结束
    if ENABLE_DEV_TOOLS and gameState == "editor" then
        handleEditorRelease()
        return
    end
    -- 卡牌开发者工具拖拽结束
    if ENABLE_DEV_TOOLS and cardDev.active and cardDev.drag.active then
        cardDev.drag.active = false
        return
    end
    -- 开发者面板拖拽结束
    if ENABLE_DEV_TOOLS and dev.drag.active then
        handleDevTouchEnd(lx, ly)
        return
    end
    -- 镶嵌面板拖拽结束
    if gemEquip.drag.active then
        gemEquip.drag.active = false
        local dragDist = math.abs(ly - gemEquip.drag.startY)
        if dragDist < 8 then
            -- 拖拽距离很小，视为点击
            local clickX = gemEquip.drag.startX or lx
            -- "放入背包"按钮（仅地图拾取时有）
            if gemEquip.backpackRect and gemEquip.fromMap then
                local r = gemEquip.backpackRect
                if clickX >= r.x and clickX <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                    playSfx("btn", 0.5)
                    player.gems[gemEquip.gemId] = (player.gems[gemEquip.gemId] or 0) + 1
                    if gemEquip.mapFloor and gemEquip.mapRow and gemEquip.mapCol then
                        maps[gemEquip.mapFloor][gemEquip.mapRow][gemEquip.mapCol] = '.'
                    end
                    local gemDef = GEM_DEF[gemEquip.gemId]
                    showMessage(gemDef.name .. " 已放入背包", 1.0, gemDef.r, gemDef.g, gemDef.b)
                    gemEquip.open = false
                    gemEquip.gemId = nil
                    gemEquip.fromMap = false
                    return
                end
            end
            -- 关闭按钮（暂不镶嵌）
            if gemEquip.closeRect then
                local r = gemEquip.closeRect
                if clickX >= r.x and clickX <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                    playSfx("btn", 0.5)
                    gemEquip.open = false
                    gemEquip.gemId = nil
                    gemEquip.fromMap = false
                    return
                end
            end
            -- 卡牌选项 → 进入确认步骤
            for _, r in ipairs(gemEquip.cardRects) do
                if clickX >= r.x and clickX <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
                    playSfx("btn", 0.5)
                    gemEquip.confirmCardIdx = r.cardIdx
                    return
                end
            end
            -- 点击面板内空白 → 不做任何事（不关闭）
            -- 点击面板外部 → 关闭
            if gemEquip.panelRect then
                local p = gemEquip.panelRect
                if clickX >= p.x and clickX <= p.x + p.w and ly >= p.y and ly <= p.y + p.h then
                    -- 面板内空白，不关闭
                    return
                end
            end
            -- 面板外部 → 关闭
            gemEquip.open = false
            gemEquip.gemId = nil
            gemEquip.fromMap = false
        end
        return
    end
    -- 牌堆查看拖拽结束
    if pileView.drag.active then
        pileView.drag.active = false
        local dragDist = math.abs(ly - pileView.drag.startY)
        if dragDist < 8 then
            -- 拖拽距离很小，视为点击 → 关闭
            pileView.open = false
            pileView.scroll = 0
        end
        return
    end
    -- 图鉴（标题页）拖拽结束
    if codex.drag.active then
        codex.drag.active = false
        local dragDist = math.abs(ly - codex.drag.startY)
        if dragDist < 10 and codex.tab == 1 then
            -- 拖拽距离很小，视为点击 → 检测卡牌选中
            for _, cr in ipairs(codex.cardRects) do
                if lx >= cr.x and lx <= cr.x + cr.w and ly >= cr.y and ly <= cr.y + cr.h then
                    playSfx("btn", 0.5)
                    codex.selectedCard = cr.id
                    break
                end
            end
        end
        return
    end
    -- 图鉴拖拽结束
    if cardBook.drag.active then
        cardBook.drag.active = false
        local dragDist = math.abs(ly - cardBook.drag.startY)
        if dragDist < 8 then
            -- 拖拽距离很小，视为点击
            -- 如果有卡牌预览打开，先处理预览层的点击
            if cardBook.selectedIdx then
                -- 点击预览中的宝石按钮区域在 drawCardBook 中记录
                if cardBook._gemBtnRect then
                    local gb = cardBook._gemBtnRect
                    local clickX = cardBook.drag.startX or lx
                    if clickX >= gb.x and clickX <= gb.x + gb.w and ly >= gb.y and ly <= gb.y + gb.h then
                        local card = player.cards[cardBook.selectedIdx]
                        if card then
                            local cardDef = CARD_DEF[card.id]
                            if cardDef and cardDef.cardType == "consumable" then
                                showMessage("销毁型卡牌无法镶嵌宝石", 1.5, 255, 100, 80)
                            elseif gb.locked or (card.gem and not player.relics.gemCraft) then
                                showMessage("更换宝石需要宝石工匠锤", 1.5, 255, 170, 100)
                            else
                                gemPanel.cardIdx = cardBook.selectedIdx
                                gemPanel.open = true
                                cardBook.selectedIdx = nil
                            end
                        end
                        return
                    end
                end
                -- 关闭按钮
                if cardBook._closeRect then
                    local cr = cardBook._closeRect
                    local clickX = cardBook.drag.startX or lx
                    if clickX >= cr.x and clickX <= cr.x + cr.w and ly >= cr.y and ly <= cr.y + cr.h then
                        cardBook.selectedIdx = nil
                        return
                    end
                end
                -- 点击其他位置：关闭卡牌预览
                cardBook.selectedIdx = nil
                return
            end
            local clickedCard = false
            local clickX = cardBook.drag.startX or lx
            for _, rect in ipairs(cardBook.cardRects) do
                if clickX >= rect.x and clickX <= rect.x + rect.w and ly >= rect.y and ly <= rect.y + rect.h then
                    -- 点击卡牌 → 打开放大预览
                    cardBook.selectedIdx = rect.cardIdx
                    clickedCard = true
                    break
                end
            end
            if not clickedCard then
                -- 点击空白区域 → 关闭牌组
                cardBook.open = false
                cardBook.scroll = 0
                gemPanel.open = false
                cardBook.selectedIdx = nil
            end
        end
        return
    end
    if not cardDrag.active then return end
    local dragDist = cardDrag.startY - ly  -- 向上拖拽为正
    cardDrag.active = false

    -- 向上拖拽超过30像素：打出卡牌（consumeSelect 模式下禁止拖拽出牌）
    if dragDist > 30 and battle.active and not battle.consumeSelect then
        if battle.phase == "waiting_for_card" then
            playCard(cardDrag.cardIndex)
        elseif battle.phase == "card_effect" then
            -- 效果播放中，入队等待顺序执行
            local cardRef = battle.hand[cardDrag.cardIndex]
            if cardRef then
                table.insert(cardPlayQueue, cardRef)
            end
        end
    end
    -- 否则取消拖拽（卡牌回到原位，保持选中状态）
    cardDrag.cardIndex = 0
end

function HandleMouseMove(eventType, eventData)
    if input:GetNumTouches() > 0 then return end
    local mousePos = input:GetMousePosition()
    handleDragMove(mousePos.x, mousePos.y)

    -- 卡牌悬浮检测（仅在战斗中、未拖拽时）
    if not battle.active or cardDrag.active then battle.hoveredCard = 0; return end
    local lx, ly = mousePos.x / dpr, mousePos.y / dpr
    local numCards = #battle.hand
    if numCards == 0 or #cardAnims < numCards then battle.hoveredCard = 0; return end
    local isPortrait = logicalH > logicalW
    local hcH = isPortrait and math.max(120, math.min(logicalW * 0.38, 165))
                            or math.max(130, math.min(logicalH * 0.27, 180))
    hcH = math.floor(hcH * (cardDev.p.cardScale or 1.0))
    local hcW = math.floor(hcH * 0.68)
    -- 从上层到下层检测（选中卡优先，然后从右到左）
    local selIdx = battle.selectedCard
    local checkOrder = {}
    if selIdx and selIdx >= 1 and selIdx <= numCards then checkOrder[1] = selIdx end
    for i = numCards, 1, -1 do
        if i ~= selIdx then checkOrder[#checkOrder + 1] = i end
    end
    for _, i in ipairs(checkOrder) do
        local a = cardAnims[i]
        if a then
            local sw, sh = hcW * a.scale, hcH * a.scale
            local dx, dy = lx - a.x, ly - a.y
            local cosR, sinR = math.cos(-a.rot), math.sin(-a.rot)
            local localX = dx * cosR - dy * sinR
            local localY = dx * sinR + dy * cosR
            if localX >= -sw / 2 and localX <= sw / 2 and localY >= -sh and localY <= 0 then
                battle.hoveredCard = i
                return
            end
        end
    end
    battle.hoveredCard = 0
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    if input:GetNumTouches() > 0 then return end
    local mousePos = input:GetMousePosition()
    handleDragEnd(mousePos.x, mousePos.y)
    if gameState == "playing" then
        checkGameOver()
    end
end

function HandleTouchMove(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    handleDragMove(tx, ty)
end

function HandleTouchEnd(eventType, eventData)
    local tx = eventData["X"]:GetInt()
    local ty = eventData["Y"]:GetInt()
    handleDragEnd(tx, ty)
    if gameState == "playing" then
        checkGameOver()
    end
end

