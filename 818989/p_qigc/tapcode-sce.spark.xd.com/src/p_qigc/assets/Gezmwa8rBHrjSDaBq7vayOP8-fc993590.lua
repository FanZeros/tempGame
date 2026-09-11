-- ============================================================
-- SignInSystem.lua  —— 5天签到 + 日常签到奖励系统
-- 第1~5天：每天3种奖励（登录/15分钟/1小时），纵向5列布局
-- 第6天起：日常签到模式，横向3个奖励，每日重置
-- ============================================================
local GS = require("GameState")
local ImageManager = require("ImageManager")
local BoardOverlay = require("BoardOverlay")

local M = {}

-- ===== 常量 =====
M.TOTAL_DAYS = 5
M.TIME_REWARD_15 = 15 * 60   -- 15分钟（秒）
M.TIME_REWARD_60 = 60 * 60   -- 1小时（秒）
M.REWARD_ITEM_ID = "gratitude_ticket"  -- 保留兼容

-- ===== 奖励配置表 =====
-- 每天每种奖励 { itemId, count }
-- day 1 time15 = "hero_weapon" 特殊标记，由 getDay1Time15RewardId() 决定
M.REWARD_TABLE = {
    [1] = {
        login  = { "backpack_expand", 5 },
        time15 = { "hero_weapon", 1 },         -- 特殊：按职业发放冒险英雄武器
        time60 = { "warehouse_expand", 5 },
    },
    [2] = {
        login  = { "gratitude_ticket", 3 },
        time15 = { "stat_respec_potion", 1 },
        time60 = { "skill_respec_potion", 1 },
    },
    [3] = {
        login  = { "gratitude_ticket", 3 },
        time15 = { "refine_slot_tool", 3 },
        time60 = { "divine_toughness_agent", 3 },
    },
    [4] = {
        login  = { "gratitude_ticket", 3 },
        time15 = { "divine_repair_agent", 3 },
        time60 = { "divine_catalyst", 3 },
    },
    [5] = {
        login  = { "gratitude_ticket", 3 },
        time15 = { "socket_drill_tool", 1 },
        time60 = { "gratitude_ticket", 10 },
    },
}

-- 日常模式奖励配置
M.DAILY_REWARDS = {
    login  = { "gratitude_ticket", 1 },
    time15 = { "gratitude_ticket", 2 },
    time60 = { "divine_toughness_agent", 1 },
}

-- 9种卓越宝石列表（供选择面板使用）
M.SUPERIOR_GEMS = {
    { id = "gem_hong_shanyao",  name = "赤钢玉",  stat = "力量+5" },
    { id = "gem_huang_shanyao", name = "鹰眼石",  stat = "专注+5" },
    { id = "gem_lan_shanyao",   name = "通识石",  stat = "智慧+5" },
    { id = "gem_lv_shanyao",    name = "猫眼荧",  stat = "敏捷+5" },
    { id = "gem_hei_shanyao",   name = "黑曜石",  stat = "体质+5" },
    { id = "gem_bai_shanyao",   name = "净念石",  stat = "意念+5" },
    { id = "gem_zi_shanyao",    name = "紫观石",  stat = "感知+5" },
    { id = "gem_fen_shanyao",   name = "佳人惑",  stat = "魅力+5" },
    { id = "gem_qing_shanyao",  name = "天选玉",  stat = "幸运+5" },
}

-- 4种冒险英雄副手装备（供副手自选包使用）
M.HERO_OFFHAND_OPTIONS = {
    { id = "hero_shield",  name = "冒险英雄木盾", desc = "盾牌·格挡+10" },
    { id = "hero_quiver",  name = "冒险英雄箭袋", desc = "箭袋·弹射+1" },
    { id = "hero_orb",     name = "冒险英雄晶球", desc = "法器·MP回复+3·技能弹射+1" },
    { id = "hero_dagger",  name = "冒险英雄匕首", desc = "匕首·攻击+21" },
}

-- 第1天15分钟奖励：按职业发放冒险英雄武器
M.CLASS_HERO_WEAPON = {
    warrior  = "hero_sword",
    hunter   = "hero_bow",
    assassin = "hero_dagger",
    mage     = "hero_staff",
    priest   = "hero_mace",
}

--- 获取第1天15分钟奖励的物品ID（按职业）
function M.getDay1Time15RewardId()
    local classId = GS.currentClass or "warrior"
    return M.CLASS_HERO_WEAPON[classId] or "hero_sword"
end

--- 获取某天某种奖励的实际物品ID和数量
---@return string itemId, number count
function M.getRewardInfo(day, rewardType)
    -- 该格子曾被领取过：降级为金币×500（第1天15分钟英雄武器例外）
    if not (day == 1 and rewardType == "time15") and M.isRewardClaimedBefore(day, rewardType) then
        return "gold", 500
    end
    local entry = M.REWARD_TABLE[day] and M.REWARD_TABLE[day][rewardType]
    if not entry then return "gratitude_ticket", 1 end
    local itemId, count = entry[1], entry[2]
    if itemId == "hero_weapon" then
        return M.getDay1Time15RewardId(), count
    end
    return itemId, count
end

--- 获取日常模式某种奖励的实际物品ID和数量
function M.getDailyRewardInfo(rewardType)
    local entry = M.DAILY_REWARDS[rewardType]
    if not entry then return "gratitude_ticket", 1 end
    return entry[1], entry[2]
end

-- ===== 内部状态 =====
M._closeBtnRect = nil
M._rewardBoxes = nil       -- 点击整框领取用
M._iconRects = nil          -- 物品图标区域（用于tooltip点击检测）
M._tooltipPinned = false   -- tooltip 是否被点击固定
M._pinnedTpl = nil          -- 固定的物品模板
M._pinnedAnchor = nil       -- 固定 tooltip 的锚点 {x,y,w,h}
M._hoverTpl = nil           -- 当前帧悬浮检测到的物品模板
M._hoverAnchor = nil        -- 当前帧 hover 的锚点

-- 宝石选择面板状态
M._gemSelectVisible = false
M._gemSelectBoxes = nil     -- 宝石选择按钮区域列表
M._gemSelectedId = nil      -- 当前选中的宝石ID
M._gemHoverTpl = nil        -- 悬浮的物品模板（tooltip用）
M._gemHoverAnchor = nil
M._gemPinnedTpl = nil       -- 点击固定的物品模板
M._gemPinnedAnchor = nil

-- 副手选择面板状态
M._offhandSelectVisible = false
M._offhandSelectBoxes = nil
M._pendingOffhandSlotIdx = nil
M._offhandSelectedId = nil  -- 当前选中的副手ID
M._offhandHoverTpl = nil
M._offhandHoverAnchor = nil
M._offhandPinnedTpl = nil
M._offhandPinnedAnchor = nil

-- 账户级日常签到：云端同步状态
M._dailyCloudLoaded = false   -- 是否已从 clientCloud 加载
M._dailyCloudLoading = false  -- 是否正在加载中
M._dailyCloudLoadFailed = false -- 加载是否失败（失败时禁止写入云端，防止空数据覆盖）
M._dailyCloudRetryTimer = 0   -- 加载失败后的重试冷却计时器
M._dailyCloudSaveTimer = 0    -- 云端保存计时器（周期性保存在线时长）

-- 管理员时间防作弊：GM 定时上传本地时间，玩家用来封顶本地时间
M._adminTime = nil             -- 从云端读取的管理员时间戳（秒），nil=未加载
M._adminTimeLoaded = false     -- 是否已加载管理员时间
M._adminTimeLoading = false    -- 是否正在加载
M._adminTimeLoadFailed = false -- 管理员时间加载是否失败（网络错误等）
M._adminTimeUploadTimer = 0    -- GM 上传时间间隔计时器（秒）
M.ADMIN_TIME_UPLOAD_INTERVAL = 300  -- GM 每5分钟上传一次时间

-- 账户级五日签到领取记录（跨角色共享，扁平结构）
M._signin5SlotsLoaded = false
M._signin5SlotsLoading = false
M._signin5Slots = {}  -- {"1_login"=true, "2_time60"=true, ...} 账户级已领取的具体奖励

-- ===== 工具函数 =====

--- 获取当前真实世界天号（UTC+8 北京时间，以0点为界）
--- 注意：此函数使用本地时间，可被玩家篡改。日常签到应使用 getTrustedDay()
function M.getRealDay()
    return math.floor((os.time() + 8 * 3600) / 86400)
end

-- ===== 管理员时间防作弊 =====

--- 从云端加载管理员时间（所有玩家启动时调用一次）
function M._loadAdminTime()
    if M._adminTimeLoading or M._adminTimeLoaded then return end
    if not clientCloud then
        M._adminTimeLoaded = true
        return
    end
    M._adminTimeLoading = true
    clientCloud:Get("admin_time", {
        ok = function(values, iscores)
            M._adminTimeLoading = false
            M._adminTimeLoaded = true
            M._adminTimeLoadFailed = false
            local t = iscores and iscores.admin_time
            if t and t > 0 then
                M._adminTime = t
                print("[AntiCheat] 管理员时间加载成功:", t)
            else
                print("[AntiCheat] 云端无管理员时间，跳过封顶检查")
            end
        end,
        error = function(code, reason)
            M._adminTimeLoading = false
            M._adminTimeLoaded = true  -- 失败不阻塞流程
            M._adminTimeLoadFailed = true  -- 标记失败，每日限制功能将阻塞
            print("[AntiCheat] 管理员时间加载失败:", code, reason)
        end,
    })
end

--- GM 上传本地时间到云端（SetInt 覆盖写入）
function M._uploadAdminTime()
    if not clientCloud then return end
    local now = os.time()
    clientCloud:SetInt("admin_time", now, {
        ok = function()
            M._adminTime = now  -- 同步本地缓存
            print("[AntiCheat] 管理员时间已上传:", now)
        end,
        error = function(code, reason)
            print("[AntiCheat] 管理员时间上传失败:", code, reason)
        end,
    })
end

--- GM 定时上传（在 update 中调用）
---@param dt number
function M.updateAdminTime(dt)
    if not GS.isGM() then return end
    M._adminTimeUploadTimer = M._adminTimeUploadTimer - dt
    if M._adminTimeUploadTimer <= 0 then
        M._adminTimeUploadTimer = M.ADMIN_TIME_UPLOAD_INTERVAL
        M._uploadAdminTime()
    end
end

--- 管理员时间是否可靠（已加载成功且未失败）
--- 用于每日限制功能（签到、限购）在 admin_time 不可用时阻塞操作
---@return boolean reliable
---@return string|nil reason 不可靠时的原因描述
function M.isAdminTimeReliable()
    if not M._adminTimeLoaded then
        return false, "服务器时间加载中"
    end
    if M._adminTimeLoadFailed then
        return false, "服务器时间加载失败"
    end
    return true, nil
end

--- 获取可信天号（防作弊版本）
--- 1. 本地时间被 admin_time 封顶（防往前调）
--- 2. 调用方配合 dayKey 单调递增（防往回调）
function M.getTrustedDay()
    local localTime = os.time()
    -- 如果有管理员时间且本地时间超前，用管理员时间封顶
    if M._adminTime and localTime > M._adminTime then
        localTime = M._adminTime
    end
    return math.floor((localTime + 8 * 3600) / 86400)
end

--- 获取当前是签到第几天（1~5，超过5则返回6+）
function M.getCurrentSignDay()
    if GS.signInStartDay <= 0 then return 0 end
    return M.getTrustedDay() - GS.signInStartDay + 1
end

--- 判断是否处于日常签到模式（第6天起）
function M.isDailyMode()
    if GS.debugForceDay6 then return true end
    return M.getCurrentSignDay() > M.TOTAL_DAYS
end

--- 判断签到系统是否应该显示（完成事件2 + 5天内 或 日常模式）
function M.isActive()
    if not GS.eventCompleted or not GS.eventCompleted["initial_supply"] then
        return false
    end
    if GS.signInStartDay <= 0 then return false end
    -- 5天内 或 日常模式（第6天起永久激活）
    return M.getCurrentSignDay() <= M.TOTAL_DAYS or M.isDailyMode()
end

--- 激活签到系统（完成事件2时调用）
function M.activate()
    if GS.signInStartDay > 0 then return end -- 已激活
    GS.signInStartDay = M.getTrustedDay()
    GS.signInRewards = {}
    GS.signInDayPlayTime = {}
    for i = 1, M.TOTAL_DAYS do
        GS.signInRewards[i] = { login = false, time15 = false, time60 = false }
        GS.signInDayPlayTime[i] = 0
    end
    print("=== 签到系统激活，起始天号：" .. GS.signInStartDay .. " ===")
end

--- 确保签到数据完整（防御性）
function M.ensureData()
    -- 懒加载账户级槽位领取记录（仅请求一次）
    M._loadSignin5Slots()
    if not GS.signInRewards then GS.signInRewards = {} end
    if not GS.signInDayPlayTime then GS.signInDayPlayTime = {} end
    for i = 1, M.TOTAL_DAYS do
        if not GS.signInRewards[i] then
            GS.signInRewards[i] = { login = false, time15 = false, time60 = false }
        end
        if not GS.signInDayPlayTime[i] then
            GS.signInDayPlayTime[i] = 0
        end
    end
end

-- ===== 五日签到：槽位领取记录（账户级） =====

--- 从 clientCloud 懒加载槽位领取记录
function M._loadSignin5Slots()
    if M._signin5SlotsLoading or M._signin5SlotsLoaded then return end
    if not clientCloud then
        M._signin5SlotsLoaded = true
        return
    end
    M._signin5SlotsLoading = true
    clientCloud:Get("signin5_slots", {
        ok = function(values, iscores)
            M._signin5SlotsLoading = false
            M._signin5SlotsLoaded = true
            local data = values and values.signin5_slots
            if data and type(data) == "table" then
                -- 检测旧格式（按槽位分组）并迁移为新格式（扁平账户级）
                local needsMigration = false
                for k, v in pairs(data) do
                    if type(v) == "table" then
                        needsMigration = true
                        break
                    end
                end
                if needsMigration then
                    local flat = {}
                    for _, slotData in pairs(data) do
                        if type(slotData) == "table" then
                            for rk, rv in pairs(slotData) do
                                if rv == true then flat[rk] = true end
                            end
                        end
                    end
                    M._signin5Slots = flat
                    M._saveSignin5Slots()  -- 回写新格式
                    print("[SignIn5] 旧格式已迁移为账户级扁平格式")
                else
                    M._signin5Slots = data
                end
            end
            print("[SignIn5] 领取记录加载完成:", M._signin5Slots)
        end,
        error = function(code, reason)
            M._signin5SlotsLoading = false
            M._signin5SlotsLoaded = true  -- 失败时使用空默认值（不阻塞领取）
            print("[SignIn5] 槽位领取记录加载失败:", code, reason)
        end,
    })
end

--- 保存槽位领取记录到 clientCloud
function M._saveSignin5Slots()
    if not clientCloud then return end
    clientCloud:Set("signin5_slots", M._signin5Slots, {
        ok = function() print("[SignIn5] 槽位领取记录已保存") end,
        error = function(code, reason) print("[SignIn5] 槽位领取记录保存失败:", code, reason) end,
    })
end

--- 该账户是否已领取过某个具体奖励（账户级，跨角色共享）
---@param day number
---@param rewardType string "login"|"time15"|"time60"
---@return boolean
function M.isRewardClaimedBefore(day, rewardType)
    if not M._signin5SlotsLoaded then return false end
    return M._signin5Slots[day .. "_" .. rewardType] == true
end

-- ===== 日常签到：账户级云端数据管理 =====

--- 从 clientCloud 加载日常签到数据（账户级）
function M.loadDailyFromCloud()
    if M._dailyCloudLoading then return end
    if not clientCloud then
        -- 无网络，使用本地默认值
        M._dailyCloudLoaded = true
        return
    end
    M._dailyCloudLoading = true
    clientCloud:Get("daily_signin", {
        ok = function(values, iscores)
            M._dailyCloudLoading = false
            M._dailyCloudLoaded = true
            M._dailyCloudLoadFailed = false  -- 加载成功，允许写入云端
            local data = values and values.daily_signin
            if data then
                local today = M.getTrustedDay()
                if data.dayKey == today then
                    -- 同一天，恢复云端状态
                    GS.dailySignInDayKey = data.dayKey
                    GS.dailySignInRewards = data.rewards or { login = false, time15 = false, time60 = false }
                    GS.dailySignInPlayTime = data.playTime or 0
                elseif today > data.dayKey then
                    -- 新的一天（往后），重置并保存
                    GS.dailySignInDayKey = today
                    GS.dailySignInRewards = { login = false, time15 = false, time60 = false }
                    GS.dailySignInPlayTime = 0
                    M.saveDailyToCloud()
                else
                    -- today < data.dayKey：玩家时间回退了，沿用云端dayKey（防回退作弊）
                    GS.dailySignInDayKey = data.dayKey
                    GS.dailySignInRewards = data.rewards or { login = false, time15 = false, time60 = false }
                    GS.dailySignInPlayTime = data.playTime or 0
                    print("[AntiCheat] 检测到时间回退，沿用云端dayKey:", data.dayKey, "本地today:", today)
                end
            else
                -- 云端无数据（首次进入日常模式），初始化
                GS.dailySignInDayKey = M.getTrustedDay()
                GS.dailySignInRewards = { login = false, time15 = false, time60 = false }
                GS.dailySignInPlayTime = 0
                M.saveDailyToCloud()
            end
            print("=== 日常签到：云端数据加载完成 ===")
        end,
        error = function(code, reason)
            M._dailyCloudLoading = false
            M._dailyCloudLoaded = true  -- 加载失败也标记完成，使用本地默认值
            M._dailyCloudLoadFailed = true  -- 标记加载失败，禁止写入云端防止空数据覆盖
            print("[DailySignIn] 云端加载失败:", code, reason)
        end,
    })
end

--- 将日常签到数据保存到 clientCloud（账户级）
function M.saveDailyToCloud()
    if not clientCloud then return end
    if not M._dailyCloudLoaded then return end
    if M._dailyCloudLoadFailed then return end  -- 加载失败时禁止写入，防止空数据覆盖云端
    clientCloud:Set("daily_signin", {
        dayKey = GS.dailySignInDayKey,
        rewards = GS.dailySignInRewards,
        playTime = GS.dailySignInPlayTime,
    }, {
        ok = function() end,
        error = function(code, reason)
            print("[DailySignIn] 云端保存失败:", code, reason)
        end,
    })
end

--- 确保日常签到数据完整（云端加载 + 新一天重置）
function M.ensureDailyData()
    -- 懒加载管理员时间（首次调用时触发）
    M._loadAdminTime()
    -- 首次进入日常模式 或 上次加载失败（带 10 秒冷却），触发（重）加载
    if (not M._dailyCloudLoaded or M._dailyCloudLoadFailed) and not M._dailyCloudLoading then
        if not M._dailyCloudLoadFailed or M._dailyCloudRetryTimer <= 0 then
            M._dailyCloudRetryTimer = 10  -- 失败后 10 秒再重试
            M.loadDailyFromCloud()
        end
    end
    -- 防御性默认值（加载期间使用）
    if not GS.dailySignInRewards or type(GS.dailySignInRewards) ~= "table" then
        GS.dailySignInRewards = { login = false, time15 = false, time60 = false }
    end
    if not GS.dailySignInPlayTime then
        GS.dailySignInPlayTime = 0
    end
    -- 云端加载成功后才做日期检查（加载失败时跳过，防止空数据写入云端）
    if M._dailyCloudLoaded and not M._dailyCloudLoadFailed then
        local today = M.getTrustedDay()
        -- 只有 today 严格大于当前 dayKey 才重置（防止回退作弊）
        if today > (GS.dailySignInDayKey or 0) then
            GS.dailySignInDayKey = today
            GS.dailySignInRewards = { login = false, time15 = false, time60 = false }
            GS.dailySignInPlayTime = 0
            M.saveDailyToCloud()
            print("=== 日常签到：新的一天，重置奖励 ===")
        end
    end
end

--- 获取日常签到某奖励的状态
---@param rewardType string "login"|"time15"|"time60"
---@return string "claimable"|"claimed"|"locked"
function M.getDailyRewardStatus(rewardType)
    M.ensureDailyData()
    -- 云端数据加载中或加载失败，全部显示为锁定（防止误领/无法保存）
    if not M._dailyCloudLoaded then return "locked" end
    if M._dailyCloudLoadFailed then return "locked" end
    -- 管理员时间加载失败时锁定（防止调时间作弊）
    if M._adminTimeLoadFailed then return "locked" end
    local r = GS.dailySignInRewards
    if r[rewardType] then return "claimed" end

    if rewardType == "login" then
        return "claimable"
    end

    local needed = rewardType == "time15" and M.TIME_REWARD_15 or M.TIME_REWARD_60
    local played = GS.dailySignInPlayTime or 0
    if played >= needed then return "claimable" end
    return "locked"
end

--- 领取日常签到奖励
---@param rewardType string "login"|"time15"|"time60"
---@return boolean success
function M.claimDailyReward(rewardType)
    if not M._dailyCloudLoaded then return false end  -- 云端数据未加载，禁止领取
    if M._dailyCloudLoadFailed then return false end   -- 云端加载失败，禁止领取（无法保存）
    if M._adminTimeLoadFailed then return false end    -- 管理员时间加载失败，禁止领取（防调时间作弊）
    M.ensureDailyData()
    local r = GS.dailySignInRewards
    if r[rewardType] then return false end -- 已领取

    local status = M.getDailyRewardStatus(rewardType)
    if status ~= "claimable" then return false end

    r[rewardType] = true
    local itemId, count = M.getDailyRewardInfo(rewardType)
    GS.addToInventory(itemId, count)
    print("=== 日常签到奖励领取: " .. rewardType .. " → " .. itemId .. "×" .. count .. " ===")
    M.saveDailyToCloud()  -- 立即保存到云端（账户级）
    GS.saveToCloud()      -- 同时保存角色存档（背包变了）
    return true
end

--- 日常签到是否有可领取的奖励
function M.hasDailyClaimable()
    for _, rt in ipairs({"login", "time15", "time60"}) do
        if M.getDailyRewardStatus(rt) == "claimable" then
            return true
        end
    end
    return false
end

-- ===== 每帧更新 =====

--- 每帧更新（累计在线时间）
function M.update(dt)
    -- 懒激活：老存档已完成事件2但未激活签到
    if GS.signInStartDay <= 0 and GS.eventCompleted and GS.eventCompleted["initial_supply"] then
        M.activate()
    end
    if not M.isActive() then return end

    -- 只在游戏状态中累计时间
    local inGame = GS.gameState ~= GS.STATE_MENU and GS.gameState ~= GS.STATE_CHAR_SELECT
       and GS.gameState ~= GS.STATE_CHAR_CREATE and GS.gameState ~= GS.STATE_GAMEOVER

    if M.isDailyMode() then
        -- 日常签到模式：累计当天时间（账户级云端存储）
        if M._dailyCloudRetryTimer > 0 then
            M._dailyCloudRetryTimer = M._dailyCloudRetryTimer - dt
        end
        M.ensureDailyData()
        if inGame and M._dailyCloudLoaded then
            local prev = GS.dailySignInPlayTime or 0
            local cur = prev + dt
            GS.dailySignInPlayTime = cur
            -- 每30秒将在线时长同步到云端
            M._dailyCloudSaveTimer = M._dailyCloudSaveTimer + dt
            if M._dailyCloudSaveTimer >= 30 then
                M._dailyCloudSaveTimer = 0
                M.saveDailyToCloud()
            end
        end
    else
        -- 5天签到模式
        M.ensureData()
        local day = M.getCurrentSignDay()
        if day < 1 or day > M.TOTAL_DAYS then return end
        if inGame then
            local prev = GS.signInDayPlayTime[day] or 0
            local cur = prev + dt
            GS.signInDayPlayTime[day] = cur
            if math.floor(cur / 30) > math.floor(prev / 30) and GS.autoSave then
                GS.autoSave.dirty = true
            end
        end
    end
end

-- ===== 5天签到：领取与状态 =====

--- 领取奖励（5天模式）
---@param day number 第几天
---@param rewardType string "login"|"time15"|"time60"
---@return boolean success
function M.claimReward(day, rewardType)
    if day < 1 or day > M.TOTAL_DAYS then return false end
    -- 管理员时间加载失败时禁止领取（防调时间作弊）
    if M._adminTimeLoadFailed then
        print("[SignIn5] 管理员时间加载失败，暂时无法领取")
        return false
    end
    -- 云端槽位数据未加载完时禁止领取（防止绕过降级检查拿到原始奖励）
    -- 第1天15分钟英雄武器不受降级影响，可豁免
    if not M._signin5SlotsLoaded and not (day == 1 and rewardType == "time15") then
        print("[SignIn5] 云端槽位数据尚未加载，暂时无法领取")
        return false
    end
    M.ensureData()
    local r = GS.signInRewards[day]
    if not r then return false end
    if r[rewardType] then return false end -- 已领取

    local curDay = M.getCurrentSignDay()

    -- 登录奖励：只能在当天或之前的天（当天可领）
    if rewardType == "login" then
        if day > curDay then return false end
    end

    -- 时间奖励：必须累计够
    if rewardType == "time15" then
        if (GS.signInDayPlayTime[day] or 0) < M.TIME_REWARD_15 then return false end
    elseif rewardType == "time60" then
        if (GS.signInDayPlayTime[day] or 0) < M.TIME_REWARD_60 then return false end
    end

    -- 发放奖励
    r[rewardType] = true
    local itemId, count = M.getRewardInfo(day, rewardType)

    if day == 1 and rewardType == "time15" then
        -- 第1天15分钟：发放职业对应的冒险英雄武器（带附魔+精炼槽）
        local _, _, addedItem = GS.addToInventory(itemId, 1)
        if addedItem then
            local tier = 1
            addedItem.tier = tier
            GS.rollEnchantment(addedItem, tier)
            local maxSlots = GS.getMaxRefineSlots(tier)
            if maxSlots > 0 then
                addedItem.refineSlots = {}
                for i = 1, maxSlots do
                    addedItem.refineSlots[i] = {}
                end
            end
        end
        print("=== 签到奖励领取: 第1天 time15 → 冒险英雄武器 " .. itemId .. " ===")
    elseif itemId == "gold" then
        -- 金币直接加到 GS.gold（不是背包物品）
        GS.gold = (GS.gold or 0) + count
        print("=== 签到奖励领取: 第" .. day .. "天 " .. rewardType .. " → 金币×" .. count .. " ===")
    else
        GS.addToInventory(itemId, count)
        print("=== 签到奖励领取: 第" .. day .. "天 " .. rewardType .. " → " .. itemId .. "×" .. count .. " ===")
    end
    -- 记录该格子已被领取（账户级，跨角色共享）
    local rewardKey = day .. "_" .. rewardType
    if not M._signin5Slots[rewardKey] then
        M._signin5Slots[rewardKey] = true
        M._saveSignin5Slots()
    end
    GS.saveToCloud()
    return true
end

--- 确认选择宝石（宝石选择面板回调）
--- 支持两种来源：签到系统直接发放 / 背包使用自选箱
function M.confirmGemSelection(gemId)
    if M._pendingGemSlotIdx then
        -- 来源：背包使用自选箱 → 消耗物品，发放宝石
        local slotIdx = M._pendingGemSlotIdx
        local item = GS.inventory[slotIdx]
        if item then
            if item.stackable and item.quantity and item.quantity > 1 then
                item.quantity = item.quantity - 1
            else
                GS.inventory[slotIdx] = nil
            end
        end
        GS.addToInventory(gemId, 1)
        print("=== 自选箱使用: 背包格" .. slotIdx .. " → 卓越宝石 " .. gemId .. " ===")
        GS.saveToCloud()
    elseif M._pendingGemDay and M._pendingGemRewardType then
        -- 来源：签到系统直接发放（兼容旧路径）
        local day = M._pendingGemDay
        local rewardType = M._pendingGemRewardType
        M.ensureData()
        local r = GS.signInRewards[day]
        if r then
            r[rewardType] = true
            GS.addToInventory(gemId, 1)
            print("=== 签到奖励领取: 第" .. day .. "天 " .. rewardType .. " → 卓越宝石 " .. gemId .. " ===")
            GS.saveToCloud()
        end
    else
        return
    end

    M._gemSelectVisible = false
    M._gemSelectBoxes = nil
    M._pendingGemDay = nil
    M._pendingGemRewardType = nil
    M._pendingGemSlotIdx = nil
end

--- 获取某天某奖励的状态（5天模式）
---@return string "claimable"|"claimed"|"missed"|"locked"
function M.getRewardStatus(day, rewardType)
    M.ensureData()
    -- 管理员时间加载失败时全部锁定（防调时间作弊）
    if M._adminTimeLoadFailed then return "locked" end
    local r = GS.signInRewards[day]
    if not r then return "locked" end
    if r[rewardType] then return "claimed" end

    local curDay = M.getCurrentSignDay()

    if rewardType == "login" then
        if day < curDay then return "missed" end
        if day == curDay then return "claimable" end
        return "locked"
    end

    -- 时间奖励
    local needed = rewardType == "time15" and M.TIME_REWARD_15 or M.TIME_REWARD_60
    local played = GS.signInDayPlayTime[day] or 0

    if day < curDay then
        return "missed"
    elseif day == curDay then
        if played >= needed then return "claimable" end
        return "locked"
    else
        return "locked"
    end
end

--- 获取锁定图标句柄
function M.getLockImg()
    local Renderer = require("Renderer")
    if Renderer.lockClosedImg and Renderer.lockClosedImg > 0 then
        return Renderer.lockClosedImg
    end
    return nil
end

--- 获取物品图标句柄（通用，根据 itemId）
function M.getItemIconById(itemId)
    if itemId == "gold" then
        return ImageManager.lazyGet("signIn_gold", "image/money_bag.png")
    end
    local tpl = GS.itemTemplates and GS.itemTemplates[itemId]
    if tpl and tpl.icon then
        return ImageManager.lazyGet("signIn_" .. itemId, tpl.icon)
    end
    return nil
end

--- 预加载所有宝石图标（打开面板时调用，避免首帧黑块）
function M.preloadGemIcons()
    for _, gem in ipairs(M.SUPERIOR_GEMS) do
        M.getItemIconById(gem.id)
    end
end

--- 预加载所有副手装备图标（打开面板时调用）
function M.preloadOffhandIcons()
    for _, opt in ipairs(M.HERO_OFFHAND_OPTIONS) do
        M.getItemIconById(opt.id)
    end
end

--- 确认选择副手装备（副手选择面板回调）
function M.confirmOffhandSelection(itemId)
    if not M._pendingOffhandSlotIdx then return end

    local slotIdx = M._pendingOffhandSlotIdx
    local item = GS.inventory[slotIdx]
    if item then
        -- 消耗自选包
        if item.stackable and item.quantity and item.quantity > 1 then
            item.quantity = item.quantity - 1
        else
            GS.inventory[slotIdx] = nil
        end
    end

    -- 发放选中的副手装备（带附魔+精炼槽，与冒险英雄武器一致）
    local _, _, addedItem = GS.addToInventory(itemId, 1)
    if addedItem then
        local tier = 1
        addedItem.tier = tier
        GS.rollEnchantment(addedItem, tier)
        local maxSlots = GS.getMaxRefineSlots(tier)
        if maxSlots > 0 then
            addedItem.refineSlots = {}
            for i = 1, maxSlots do
                addedItem.refineSlots[i] = {}
            end
        end
    end

    print("=== 副手自选包使用: 背包格" .. slotIdx .. " → " .. itemId .. " ===")
    GS.saveToCloud()

    M._offhandSelectVisible = false
    M._offhandSelectBoxes = nil
    M._pendingOffhandSlotIdx = nil
end

--- 获取物品图标句柄（感恩礼券，兼容旧接口）
function M.getItemIcon()
    return ImageManager.lazyGet("item", "image/item_gratitude_ticket.png")
end

-- ===== 渲染 =====

--- 绘制左上角签到按钮（在topBar下方）
function M.drawButton(vg)
    -- 仅清水镇室外显示（排除建筑内部、家、训练场）
    local isTownOutdoor = M.isActive()
        and GS.currentAreaName == "清水镇"
        and not GS.homeMode
        and not GS.trainingMode
        and not BoardOverlay.subScene
    if not isTownOutdoor then
        GS.signInBtnRect = nil
        return
    end

    -- 场景转场时跟随淡入淡出：in=渐隐, hold=全隐, out=渐现
    local btnAlpha = 1.0
    local tr = GS.sceneTransition
    if tr then
        if tr.phase == "in" then
            btnAlpha = 1.0 - math.min(1, tr.timer / tr.FADE_IN)
        elseif tr.phase == "hold" then
            btnAlpha = 0
        elseif tr.phase == "out" then
            btnAlpha = math.min(1, tr.timer / tr.FADE_OUT)
        end
        if btnAlpha <= 0 then
            GS.signInBtnRect = nil
            return
        end
        nvgGlobalAlpha(vg, btnAlpha)
    end

    -- 按钮位置：相对于棋盘黑框，上边距 = 左边距
    local frameX = GS.BOARD_X - 4
    local frameY = GS.BOARD_Y - 4
    local btnSize = 36
    local btnPad = 6
    local btnX = frameX + btnPad
    local btnY = frameY + btnPad

    GS.signInBtnRect = { x = btnX, y = btnY, w = btnSize, h = btnSize }

    -- 按钮底框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnSize, btnSize, 6)
    nvgFillColor(vg, nvgRGBA(40, 35, 25, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 礼物图标
    local imgHandle = ImageManager.lazyGet("signInGift", "image/gift_box.png")
    if imgHandle and imgHandle ~= -1 then
        local pad = 3
        local imgPaint = nvgImagePattern(vg, btnX + pad, btnY + pad,
            btnSize - pad * 2, btnSize - pad * 2, 0, imgHandle, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX + pad, btnY + pad, btnSize - pad * 2, btnSize - pad * 2, 4)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- 有可领取奖励时显示红点
    if M.hasClaimable() then
        local dotR = 5
        local dotX = btnX + btnSize - 3
        local dotY = btnY + 3
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotY, dotR)
        nvgFillColor(vg, nvgRGBA(220, 50, 40, 255))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    -- 恢复全局透明度
    if btnAlpha < 1.0 then
        nvgGlobalAlpha(vg, 1.0)
    end
end

--- 是否有可领取的奖励（统一：5天模式 或 日常模式）
function M.hasClaimable()
    if M.isDailyMode() then
        return M.hasDailyClaimable()
    end
    local curDay = M.getCurrentSignDay()
    if curDay < 1 then return false end
    for day = 1, math.min(curDay, M.TOTAL_DAYS) do
        for _, rt in ipairs({"login", "time15", "time60"}) do
            if M.getRewardStatus(day, rt) == "claimable" then
                return true
            end
        end
    end
    return false
end

--- 获取鼠标在设计坐标系下的位置
function M.getMouseDesignPos()
    local dpr = GS.dpr or 1
    local s = GS.S or 1
    local mx = input.mousePosition.x / dpr / s
    local my = input.mousePosition.y / dpr / s
    return mx, my
end

--- 绘制签到面板（自动分派到5天面板或日常面板）
function M.drawPanel(vg)
    if GS.signInPanelVisible then
        if M.isDailyMode() then
            M.drawDailyPanel(vg)
        else
            M.drawFiveDayPanel(vg)
        end
    end

    -- 宝石选择面板独立渲染（可从签到或背包使用自选箱触发）
    if M._gemSelectVisible then
        M.drawGemSelectPanel(vg)
    end

    -- 副手选择面板独立渲染（从背包使用自选包触发）
    if M._offhandSelectVisible then
        M.drawOffhandSelectPanel(vg)
    end
end

--- 获取某个奖励的显示文本（物品名×数量）
function M.getRewardDisplayText(itemId, count)
    if itemId == "gold" then
        return "金币×" .. (count or 0)
    end
    local tpl = GS.itemTemplates and GS.itemTemplates[itemId]
    local name = tpl and tpl.name or itemId
    -- 截断过长的名字（15字节 = 5个中文字符）
    if #name > 15 then
        name = string.sub(name, 1, 15)
    end
    if count > 1 then
        return name .. "×" .. count
    end
    return name
end

--- 绘制日常签到面板（横向3个奖励）
function M.drawDailyPanel(vg)
    M.ensureDailyData()

    -- 面板尺寸（比5天面板更紧凑）
    local panelW = math.min(280, GS.SCREEN_W - 20)
    local panelH = 206
    local panelX = (GS.SCREEN_W - panelW) / 2
    local panelY = (GS.SCREEN_H - panelH) / 2

    -- 不透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(35, 30, 20, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, panelX + panelW / 2, panelY + 22, "日常签到", nil)

    -- 关闭按钮
    local closeSize = 24
    local closeX = panelX + panelW - closeSize - 6
    local closeY = panelY + 6
    M._closeBtnRect = { x = closeX, y = closeY, w = closeSize, h = closeSize }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeSize, closeSize, 4)
    nvgFillColor(vg, nvgRGBA(120, 40, 40, 200))
    nvgFill(vg)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, closeX + closeSize / 2, closeY + closeSize / 2, "×", nil)

    -- 图标句柄
    local lockImg = M.getLockImg()

    -- 鼠标位置
    local mx, my = M.getMouseDesignPos()

    -- 三种奖励横向排列
    local rewards = {
        { key = "login",  label = "登录" },
        { key = "time15", label = "15分钟" },
        { key = "time60", label = "1小时" },
    }

    local colCount = 3
    local marginX = 16
    local colW = (panelW - marginX * 2) / colCount
    local startX = panelX + marginX
    local startY = panelY + 46

    M._rewardBoxes = {}
    M._iconRects = {}
    M._hoverTpl = nil
    M._hoverAnchor = nil

    for ri, rw in ipairs(rewards) do
        local cx = startX + (ri - 1) * colW + colW / 2
        local boxW = colW - 8
        local boxH = 100
        local boxX = cx - boxW / 2
        local boxY = startY

        local status = M.getDailyRewardStatus(rw.key)
        local itemId, count = M.getDailyRewardInfo(rw.key)

        -- 奖励格背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, boxX, boxY, boxW, boxH, 6)
        if status == "claimed" then
            nvgFillColor(vg, nvgRGBA(30, 28, 22, 255))
        elseif status == "claimable" then
            nvgFillColor(vg, nvgRGBA(60, 50, 25, 255))
        else
            nvgFillColor(vg, nvgRGBA(40, 35, 28, 255))
        end
        nvgFill(vg)

        -- 边框
        if status == "claimable" then
            nvgStrokeColor(vg, nvgRGBA(80, 220, 80, 255))
            nvgStrokeWidth(vg, 2)
        else
            nvgStrokeColor(vg, nvgRGBA(100, 90, 60, 120))
            nvgStrokeWidth(vg, 1)
        end
        nvgStroke(vg)

        -- 奖励类型标签
        nvgFontSize(vg, 12)
        if status == "claimed" then
            nvgFillColor(vg, nvgRGBA(120, 120, 120, 180))
        else
            nvgFillColor(vg, nvgRGBA(200, 190, 160, 220))
        end
        nvgText(vg, cx, boxY + 16, rw.label, nil)

        -- 物品图标（居中）
        local iconSize = 24
        local iconX = cx - iconSize / 2
        local iconY = boxY + 28
        local displayIcon = M.getItemIconById(itemId)

        if displayIcon and displayIcon > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX - 1, iconY - 1, iconSize + 2, iconSize + 2, 3)
            nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 220))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            local alpha = (status == "claimed") and 0.4 or 1.0
            local imgPaint = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, displayIcon, alpha)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 3)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(220, 180, 80, 220))
            nvgText(vg, cx, iconY + iconSize / 2, M.getRewardDisplayText(itemId, count), nil)
        end

        -- 物品名称
        nvgFontSize(vg, 9)
        if status == "claimed" then
            nvgFillColor(vg, nvgRGBA(120, 120, 120, 160))
        else
            nvgFillColor(vg, nvgRGBA(220, 180, 80, 220))
        end
        nvgText(vg, cx, iconY + iconSize + 10, M.getRewardDisplayText(itemId, count), nil)

        -- 存储图标区域（tooltip 用）
        local rewardTpl = GS.itemTemplates and GS.itemTemplates[itemId]
        M._iconRects[#M._iconRects + 1] = {
            x = iconX, y = iconY, w = iconSize, h = iconSize,
            itemTpl = rewardTpl,
        }

        -- 状态标记
        if status == "claimed" then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, boxX, boxY, boxW, boxH, 6)
            nvgFillColor(vg, nvgRGBA(10, 10, 5, 120))
            nvgFill(vg)
            nvgFontSize(vg, boxH * 0.5)
            nvgFillColor(vg, nvgRGBA(60, 200, 60, 200))
            nvgText(vg, cx, boxY + boxH / 2, "✓", nil)
        elseif status == "claimable" then
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(80, 230, 80, 255))
            nvgText(vg, cx, boxY + boxH - 10, "点击领取", nil)
            M._rewardBoxes[#M._rewardBoxes + 1] = {
                x = boxX, y = boxY, w = boxW, h = boxH,
                daily = true, rewardType = rw.key,
            }
        else
            if rw.key == "time15" or rw.key == "time60" then
                local needed = rw.key == "time15" and M.TIME_REWARD_15 or M.TIME_REWARD_60
                local played = GS.dailySignInPlayTime or 0
                local mins = math.floor(played / 60)
                local totalMins = math.floor(needed / 60)
                nvgFontSize(vg, 10)
                nvgFillColor(vg, nvgRGBA(150, 150, 120, 180))
                nvgText(vg, cx, boxY + boxH - 10, mins .. "/" .. totalMins .. "分钟", nil)
            else
                M.drawLockIcon(vg, cx, boxY + boxH - 10, lockImg)
            end
        end

        -- 悬停检测
        if rewardTpl and mx >= iconX and mx <= iconX + iconSize and my >= iconY and my <= iconY + iconSize then
            if not M._tooltipPinned then
                M._hoverTpl = rewardTpl
                M._hoverAnchor = { x = iconX, y = iconY, w = iconSize, h = iconSize }
            end
        end
    end

    -- 累计在线时间
    local totalSec = math.floor(GS.dailySignInPlayTime or 0)
    local h = math.floor(totalSec / 3600)
    local m = math.floor((totalSec % 3600) / 60)
    local s = totalSec % 60
    local timeStr
    if h > 0 then
        timeStr = string.format("累计在线: %d时%02d分%02d秒", h, m, s)
    else
        timeStr = string.format("累计在线: %d分%02d秒", m, s)
    end
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
    nvgText(vg, panelX + panelW / 2, panelY + panelH - 28, timeStr, nil)

    -- 底部提示
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(160, 150, 120, 180))
    nvgText(vg, panelX + panelW / 2, panelY + panelH - 14, "每日重置，登录及持续游玩即可领取", nil)

    -- tooltip 渲染
    M.drawTooltipOverlay(vg)
end

--- 绘制5天签到面板（原有逻辑）
function M.drawFiveDayPanel(vg)
    local curDay = M.getCurrentSignDay()
    M.ensureData()

    -- 面板尺寸（自适应底部文本宽度）
    local qqTipText = "加入QQ群1060256060即可领取冒险者启程礼包CDKEY（包含冒险英雄副手任选包）"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    local qqTextW = nvgTextBounds(vg, 0, 0, qqTipText, nil)
    local minW = math.max(340, qqTextW + 24)
    local panelW = math.min(minW, GS.SCREEN_W - 20)
    local panelH = 290
    local panelX = (GS.SCREEN_W - panelW) / 2
    local panelY = (GS.SCREEN_H - panelH) / 2

    -- 缓存面板尺寸供点击处理使用
    M._fiveDayPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

    -- 不透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    -- 面板背景（完全不透明）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(35, 30, 20, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, panelX + panelW / 2, panelY + 22, "签到奖励", nil)

    -- 关闭按钮
    local closeSize = 24
    local closeX = panelX + panelW - closeSize - 6
    local closeY = panelY + 6
    M._closeBtnRect = { x = closeX, y = closeY, w = closeSize, h = closeSize }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeSize, closeSize, 4)
    nvgFillColor(vg, nvgRGBA(120, 40, 40, 200))
    nvgFill(vg)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, closeX + closeSize / 2, closeY + closeSize / 2, "×", nil)

    -- 获取图标句柄
    local lockImg = M.getLockImg()

    -- 鼠标位置（设计坐标系）
    local mx, my = M.getMouseDesignPos()

    -- 每天一列
    local colW = (panelW - 20) / M.TOTAL_DAYS
    local startX = panelX + 10
    local startY = panelY + 46

    M._rewardBoxes = {}
    M._iconRects = {}
    M._hoverTpl = nil
    M._hoverAnchor = nil

    for day = 1, M.TOTAL_DAYS do
        local cx = startX + (day - 1) * colW + colW / 2

        -- 天数标题
        local dayLabel = "第" .. day .. "天"
        local isToday = (day == curDay)
        nvgFontSize(vg, 12)
        if isToday then
            nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
            dayLabel = dayLabel .. "(今日)"
            nvgFontSize(vg, 11)
        elseif day < curDay then
            nvgFillColor(vg, nvgRGBA(160, 160, 160, 200))
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        end
        nvgText(vg, cx, startY, dayLabel, nil)

        -- 三种奖励
        local rewardKeys = {
            { key = "login",  label = "登录" },
            { key = "time15", label = "15分钟" },
            { key = "time60", label = "1小时" },
        }

        for ri, rw in ipairs(rewardKeys) do
            local ry = startY + 18 + (ri - 1) * 62
            local boxW = colW - 6
            local boxH = 56
            local boxX = cx - boxW / 2
            local boxY = ry

            local status = M.getRewardStatus(day, rw.key)
            local itemId, count = M.getRewardInfo(day, rw.key)

            -- 奖励格背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, boxX, boxY, boxW, boxH, 5)
            if status == "claimed" or status == "missed" then
                nvgFillColor(vg, nvgRGBA(30, 28, 22, 255))
            elseif status == "claimable" then
                nvgFillColor(vg, nvgRGBA(60, 50, 25, 255))
            else
                nvgFillColor(vg, nvgRGBA(40, 35, 28, 255))
            end
            nvgFill(vg)

            -- 边框
            if status == "claimable" then
                nvgStrokeColor(vg, nvgRGBA(80, 220, 80, 255))
                nvgStrokeWidth(vg, 2)
            else
                nvgStrokeColor(vg, nvgRGBA(100, 90, 60, 120))
                nvgStrokeWidth(vg, 1)
            end
            nvgStroke(vg)

            -- 奖励类型标签
            nvgFontSize(vg, 10)
            if status == "claimed" or status == "missed" then
                nvgFillColor(vg, nvgRGBA(120, 120, 120, 180))
            else
                nvgFillColor(vg, nvgRGBA(200, 190, 160, 220))
            end
            nvgText(vg, cx, boxY + 11, rw.label, nil)

            -- 物品图标区域（居中，带黑色边框）
            local iconSize = 18
            local iconX = cx - iconSize / 2
            local iconY = boxY + 18

            -- 已领取状态：不显示图标和数量，直接显示"已领取"和✓
            if status == "claimed" then
                nvgFontSize(vg, 16)
                nvgFillColor(vg, nvgRGBA(60, 200, 60, 200))
                nvgText(vg, cx, boxY + 26, "✓", nil)
                nvgFontSize(vg, 9)
                nvgFillColor(vg, nvgRGBA(60, 200, 60, 180))
                nvgText(vg, cx, boxY + 42, "已领取", nil)
                -- 不存储 tooltip 区域（已领取无需 tooltip）
            else
                local displayIcon = M.getItemIconById(itemId)

                if displayIcon and displayIcon > 0 then
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, iconX - 1, iconY - 1, iconSize + 2, iconSize + 2, 2)
                    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 220))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)

                    local alpha = (status == "missed") and 0.4 or 1.0
                    local imgPaint = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, displayIcon, alpha)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 2)
                    nvgFillPaint(vg, imgPaint)
                    nvgFill(vg)
                else
                    -- fallback 文字
                    nvgFontSize(vg, 9)
                    if status == "missed" then
                        nvgFillColor(vg, nvgRGBA(100, 100, 100, 160))
                    else
                        nvgFillColor(vg, nvgRGBA(220, 180, 80, 220))
                    end
                    nvgText(vg, cx, iconY + iconSize / 2, M.getRewardDisplayText(itemId, count), nil)
                end

                -- 数量标签（图标右下角，count > 1 时显示）
                if count and count > 1 then
                    local qtyText = "×" .. count
                    nvgFontSize(vg, 9)
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    -- 描边增强可读性
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
                    local qx, qy = iconX + iconSize + 1, iconY + iconSize + 1
                    for ox = -1, 1 do
                        for oy = -1, 1 do
                            if ox ~= 0 or oy ~= 0 then
                                nvgText(vg, qx + ox, qy + oy, qtyText, nil)
                            end
                        end
                    end
                    nvgFillColor(vg, nvgRGBA(220, 200, 140, 255))
                    nvgText(vg, qx, qy, qtyText, nil)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                end

            end

            -- 状态标记
            if status == "claimed" then
                -- 已在上方统一处理，无需额外覆盖层
            elseif status == "missed" then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, boxX, boxY, boxW, boxH, 5)
                nvgFillColor(vg, nvgRGBA(10, 10, 5, 120))
                nvgFill(vg)
                -- 用画线绘制叉号（避免字体缺字显示方块）
                local crossSize = boxH * 0.22
                local ccx, ccy = cx, boxY + boxH / 2
                nvgBeginPath(vg)
                nvgMoveTo(vg, ccx - crossSize, ccy - crossSize)
                nvgLineTo(vg, ccx + crossSize, ccy + crossSize)
                nvgMoveTo(vg, ccx + crossSize, ccy - crossSize)
                nvgLineTo(vg, ccx - crossSize, ccy + crossSize)
                nvgStrokeColor(vg, nvgRGBA(220, 60, 50, 200))
                nvgStrokeWidth(vg, 3)
                nvgLineCap(vg, NVG_ROUND)
                nvgStroke(vg)
            elseif status == "claimable" then
                -- 云端槽位数据未加载完时，显示加载提示（防止领取绕过降级检查）
                -- 第1天15分钟英雄武器不受降级影响，可直接领取
                local cloudReady = M._signin5SlotsLoaded or (day == 1 and rw.key == "time15")
                nvgFontSize(vg, 9)
                if cloudReady then
                    nvgFillColor(vg, nvgRGBA(80, 230, 80, 255))
                    nvgText(vg, cx, boxY + 46, "点击领取", nil)
                    M._rewardBoxes[#M._rewardBoxes + 1] = {
                        x = boxX, y = boxY, w = boxW, h = boxH,
                        day = day, rewardType = rw.key,
                    }
                else
                    nvgFillColor(vg, nvgRGBA(200, 200, 100, 180))
                    nvgText(vg, cx, boxY + 46, "加载中...", nil)
                end
            else
                if rw.key == "time15" or rw.key == "time60" then
                    if day == curDay then
                        local needed = rw.key == "time15" and M.TIME_REWARD_15 or M.TIME_REWARD_60
                        local played = GS.signInDayPlayTime[day] or 0
                        local mins = math.floor(played / 60)
                        local totalMins = math.floor(needed / 60)
                        nvgFontSize(vg, 9)
                        nvgFillColor(vg, nvgRGBA(150, 150, 120, 180))
                        nvgText(vg, cx, boxY + 46, mins .. "/" .. totalMins .. "分钟", nil)
                    else
                        M.drawLockIcon(vg, cx, boxY + 46, lockImg)
                    end
                else
                    M.drawLockIcon(vg, cx, boxY + 46, lockImg)
                end
            end

            -- 检测鼠标悬停图标区域（用于完整 tooltip，已领取状态无需 tooltip）
            if status ~= "claimed" then
                local rewardTpl = GS.itemTemplates and GS.itemTemplates[itemId]
                if rewardTpl and mx >= iconX and mx <= iconX + iconSize and my >= iconY and my <= iconY + iconSize then
                    if not M._tooltipPinned then
                        M._hoverTpl = rewardTpl
                        M._hoverAnchor = { x = iconX, y = iconY, w = iconSize, h = iconSize }
                    end
                end
            end
        end
    end

    -- QQ群提示（绿色）
    nvgFontSize(vg, 9)
    nvgFillColor(vg, nvgRGBA(100, 220, 100, 220))
    local qqTipY = panelY + panelH - 26
    nvgText(vg, panelX + panelW / 2, qqTipY, qqTipText, nil)

    -- 底部提示
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(160, 150, 120, 180))
    local tipY = panelY + panelH - 14
    nvgText(vg, panelX + panelW / 2, tipY, "每天登录即可领取，累计游玩时间可领额外奖励", nil)

    -- tooltip 渲染
    M.drawTooltipOverlay(vg)
end

--- 绘制自选面板的tooltip（宝石/副手共用）
function M.drawSelectTooltip(vg, pinnedTpl, pinnedAnchor, hoverTpl, hoverAnchor, panelRect)
    local tipItem = pinnedTpl or hoverTpl
    local tipAnchor = pinnedAnchor or hoverAnchor
    if tipItem and tipAnchor then
        local Renderer = require("Renderer")
        local pw = 180
        local testRect = Renderer.drawTooltipPanel(vg, tipItem, 0, -9999, pw, false, false)
        local tipH = testRect.h
        local tipX, tipY
        local gap = 6
        local margin = 4

        if panelRect then
            -- 优先放在面板侧边，避免遮挡选中物品
            local spaceRight = GS.SCREEN_W - margin - (panelRect.x + panelRect.w)
            local spaceLeft  = panelRect.x - margin
            if spaceRight >= pw + gap then
                -- 放面板右侧
                tipX = panelRect.x + panelRect.w + gap
                tipY = tipAnchor.y
            elseif spaceLeft >= pw + gap then
                -- 放面板左侧
                tipX = panelRect.x - pw - gap
                tipY = tipAnchor.y
            else
                -- 两侧放不下，放物品上方
                tipX = tipAnchor.x + tipAnchor.w / 2 - pw / 2
                tipY = tipAnchor.y - tipH - gap
            end
        else
            tipX = tipAnchor.x + tipAnchor.w / 2 - pw / 2
            tipY = tipAnchor.y - tipH - gap
        end

        -- 边界修正
        if tipX < margin then tipX = margin end
        if tipX + pw > GS.SCREEN_W - margin then tipX = GS.SCREEN_W - margin - pw end
        if tipY < margin then tipY = margin end
        if tipY + tipH > GS.SCREEN_H - margin then tipY = GS.SCREEN_H - margin - tipH end

        Renderer.drawTooltipPanel(vg, tipItem, tipX, tipY, pw, false, false)
    end
end

--- 绘制宝石选择面板（第5天1小时奖励专用）
function M.drawGemSelectPanel(vg)
    local gems = M.SUPERIOR_GEMS
    local cols = 3

    local panelW = 260
    local panelH = 290
    local panelX = (GS.SCREEN_W - panelW) / 2
    local panelY = (GS.SCREEN_H - panelH) / 2

    -- 半透明遮罩（叠加在签到面板上）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(30, 25, 15, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 40, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, panelX + panelW / 2, panelY + 22, "选择一颗卓越宝石", nil)

    -- 关闭按钮（取消选择）
    local closeSize = 22
    local closeX = panelX + panelW - closeSize - 6
    local closeY = panelY + 6
    M._gemCloseBtnRect = { x = closeX, y = closeY, w = closeSize, h = closeSize }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeSize, closeSize, 4)
    nvgFillColor(vg, nvgRGBA(120, 40, 40, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, closeX + closeSize / 2, closeY + closeSize / 2, "×", nil)

    -- 宝石网格（3×3）
    local gridStartX = panelX + 16
    local gridStartY = panelY + 44
    local cellW = (panelW - 32) / cols
    local cellH = 58

    M._gemSelectBoxes = {}
    M._gemIconRects = {}

    local mx, my = M.getMouseDesignPos()
    if not M._gemPinnedTpl then
        M._gemHoverTpl = nil
        M._gemHoverAnchor = nil
    end

    for gi, gem in ipairs(gems) do
        local col = ((gi - 1) % cols)
        local row = math.floor((gi - 1) / cols)
        local cx = gridStartX + col * cellW + cellW / 2
        local cy = gridStartY + row * cellH

        local boxW = cellW - 6
        local boxH = cellH - 6
        local boxX = cx - boxW / 2
        local boxY = cy

        -- 悬停检测
        local hovered = mx >= boxX and mx <= boxX + boxW and my >= boxY and my <= boxY + boxH
        local selected = M._gemSelectedId == gem.id

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, boxX, boxY, boxW, boxH, 5)
        if selected then
            nvgFillColor(vg, nvgRGBA(60, 80, 40, 255))
        elseif hovered then
            nvgFillColor(vg, nvgRGBA(70, 60, 30, 255))
        else
            nvgFillColor(vg, nvgRGBA(45, 40, 28, 255))
        end
        nvgFill(vg)

        -- 边框
        if selected then
            nvgStrokeColor(vg, nvgRGBA(80, 220, 80, 255))
            nvgStrokeWidth(vg, 2)
        elseif hovered then
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 255))
            nvgStrokeWidth(vg, 2)
        else
            nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 150))
            nvgStrokeWidth(vg, 1)
        end
        nvgStroke(vg)

        -- 宝石图标（垂直居中）
        local iconSize = 24
        local iconX = cx - iconSize / 2
        local iconY = boxY + (boxH - iconSize - 12) / 2
        local gemIcon = M.getItemIconById(gem.id)
        if gemIcon and gemIcon > 0 then
            local iw, ih = nvgImageSize(vg, gemIcon)
            if iw > 0 and ih > 0 then
                local imgPaint = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, gemIcon, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 3)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end
        end

        -- 宝石名称
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 240))
        nvgText(vg, cx, iconY + iconSize + 10, gem.name, nil)

        -- 存储点击区域
        M._gemSelectBoxes[#M._gemSelectBoxes + 1] = {
            x = boxX, y = boxY, w = boxW, h = boxH,
            gemId = gem.id,
        }

        -- tooltip 悬浮检测
        local gemTpl = GS.itemTemplates and GS.itemTemplates[gem.id]
        if gemTpl then
            M._gemIconRects[#M._gemIconRects + 1] = {
                x = boxX, y = boxY, w = boxW, h = boxH, itemTpl = gemTpl,
            }
            if hovered and not M._gemPinnedTpl then
                M._gemHoverTpl = gemTpl
                M._gemHoverAnchor = { x = boxX, y = boxY, w = boxW, h = boxH }
            end
        end
    end

    -- 确定按钮
    local btnW = 80
    local btnH = 26
    local btnX = panelX + panelW / 2 - btnW / 2
    local btnY = panelY + panelH - 44
    M._gemConfirmBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }

    local btnEnabled = M._gemSelectedId ~= nil
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
    if btnEnabled then
        nvgFillColor(vg, nvgRGBA(50, 120, 50, 255))
    else
        nvgFillColor(vg, nvgRGBA(60, 55, 45, 255))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, btnEnabled and nvgRGBA(80, 200, 80, 200) or nvgRGBA(100, 90, 60, 120))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgFillColor(vg, btnEnabled and nvgRGBA(255, 255, 255, 255) or nvgRGBA(120, 110, 90, 180))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "确定", nil)

    -- 底部提示
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(160, 150, 120, 160))
    nvgText(vg, panelX + panelW / 2, panelY + panelH - 10, "选择后点击确定领取", nil)

    -- tooltip 渲染
    M.drawSelectTooltip(vg, M._gemPinnedTpl, M._gemPinnedAnchor, M._gemHoverTpl, M._gemHoverAnchor,
        { x = panelX, y = panelY, w = panelW, h = panelH })
end

--- 绘制副手选择面板（2×2 网格）
function M.drawOffhandSelectPanel(vg)
    local options = M.HERO_OFFHAND_OPTIONS
    local cols = 2

    local panelW = 230
    local panelH = 210
    local panelX = (GS.SCREEN_W - panelW) / 2
    local panelY = (GS.SCREEN_H - panelH) / 2

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GS.SCREEN_W, GS.SCREEN_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(30, 25, 15, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 40, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, panelX + panelW / 2, panelY + 22, "选择一件副手装备", nil)

    -- 关闭按钮
    local closeSize = 22
    local closeX = panelX + panelW - closeSize - 6
    local closeY = panelY + 6
    M._offhandCloseBtnRect = { x = closeX, y = closeY, w = closeSize, h = closeSize }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeX, closeY, closeSize, closeSize, 4)
    nvgFillColor(vg, nvgRGBA(120, 40, 40, 200))
    nvgFill(vg)
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, closeX + closeSize / 2, closeY + closeSize / 2, "×", nil)

    -- 2×2 网格
    local gridStartX = panelX + 16
    local gridStartY = panelY + 44
    local cellW = (panelW - 32) / cols
    local cellH = 58

    M._offhandSelectBoxes = {}
    M._offhandIconRects = {}

    local mx, my = M.getMouseDesignPos()
    if not M._offhandPinnedTpl then
        M._offhandHoverTpl = nil
        M._offhandHoverAnchor = nil
    end

    for gi, opt in ipairs(options) do
        local col = ((gi - 1) % cols)
        local row = math.floor((gi - 1) / cols)
        local cx = gridStartX + col * cellW + cellW / 2
        local cy = gridStartY + row * cellH

        local boxW = cellW - 6
        local boxH = cellH - 6
        local boxX = cx - boxW / 2
        local boxY = cy

        -- 悬停检测
        local hovered = mx >= boxX and mx <= boxX + boxW and my >= boxY and my <= boxY + boxH
        local selected = M._offhandSelectedId == opt.id

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, boxX, boxY, boxW, boxH, 5)
        if selected then
            nvgFillColor(vg, nvgRGBA(60, 80, 40, 255))
        elseif hovered then
            nvgFillColor(vg, nvgRGBA(70, 60, 30, 255))
        else
            nvgFillColor(vg, nvgRGBA(45, 40, 28, 255))
        end
        nvgFill(vg)

        -- 边框
        if selected then
            nvgStrokeColor(vg, nvgRGBA(80, 220, 80, 255))
            nvgStrokeWidth(vg, 2)
        elseif hovered then
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 255))
            nvgStrokeWidth(vg, 2)
        else
            nvgStrokeColor(vg, nvgRGBA(120, 100, 60, 150))
            nvgStrokeWidth(vg, 1)
        end
        nvgStroke(vg)

        -- 装备图标（垂直居中）
        local iconSize = 26
        local iconX = cx - iconSize / 2
        local iconY = boxY + (boxH - iconSize - 12) / 2
        local optIcon = M.getItemIconById(opt.id)
        if optIcon and optIcon > 0 then
            local iw, ih = nvgImageSize(vg, optIcon)
            if iw > 0 and ih > 0 then
                local imgPaint = nvgImagePattern(vg, iconX, iconY, iconSize, iconSize, 0, optIcon, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 3)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 180))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end
        end

        -- 装备名称
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 240))
        nvgText(vg, cx, iconY + iconSize + 10, opt.name, nil)

        -- 存储点击区域
        M._offhandSelectBoxes[#M._offhandSelectBoxes + 1] = {
            x = boxX, y = boxY, w = boxW, h = boxH,
            itemId = opt.id,
        }

        -- tooltip 悬浮检测
        local optTpl = GS.itemTemplates and GS.itemTemplates[opt.id]
        if optTpl then
            M._offhandIconRects[#M._offhandIconRects + 1] = {
                x = boxX, y = boxY, w = boxW, h = boxH, itemTpl = optTpl,
            }
            if hovered and not M._offhandPinnedTpl then
                M._offhandHoverTpl = optTpl
                M._offhandHoverAnchor = { x = boxX, y = boxY, w = boxW, h = boxH }
            end
        end
    end

    -- 确定按钮
    local btnW = 80
    local btnH = 26
    local btnX = panelX + panelW / 2 - btnW / 2
    local btnY = panelY + panelH - 44
    M._offhandConfirmBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }

    local btnEnabled = M._offhandSelectedId ~= nil
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
    if btnEnabled then
        nvgFillColor(vg, nvgRGBA(50, 120, 50, 255))
    else
        nvgFillColor(vg, nvgRGBA(60, 55, 45, 255))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, btnEnabled and nvgRGBA(80, 200, 80, 200) or nvgRGBA(100, 90, 60, 120))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontSize(vg, 13)
    nvgFillColor(vg, btnEnabled and nvgRGBA(255, 255, 255, 255) or nvgRGBA(120, 110, 90, 180))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "确定", nil)

    -- 底部提示
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(160, 150, 120, 160))
    nvgText(vg, panelX + panelW / 2, panelY + panelH - 10, "选择后点击确定领取", nil)

    -- tooltip 渲染
    M.drawSelectTooltip(vg, M._offhandPinnedTpl, M._offhandPinnedAnchor, M._offhandHoverTpl, M._offhandHoverAnchor,
        { x = panelX, y = panelY, w = panelW, h = panelH })
end

--- 绘制 tooltip 浮层（共用）
function M.drawTooltipOverlay(vg)
    local tipItem = (M._tooltipPinned and M._pinnedTpl) or M._hoverTpl
    local tipAnchor = (M._tooltipPinned and M._pinnedAnchor) or M._hoverAnchor
    if tipItem and tipAnchor then
        local Renderer = require("Renderer")
        local pw = 180
        local testRect = Renderer.drawTooltipPanel(vg, tipItem, 0, -9999, pw, false, false)
        local tipH = testRect.h
        local tipX = tipAnchor.x + tipAnchor.w / 2 - pw / 2
        local tipY = tipAnchor.y - tipH - 4
        if tipX < 4 then tipX = 4 end
        if tipX + pw > GS.SCREEN_W - 4 then tipX = GS.SCREEN_W - 4 - pw end
        if tipY < 4 then
            tipY = tipAnchor.y + tipAnchor.h + 4
        end
        if tipY + tipH > GS.SCREEN_H - 4 then
            tipY = GS.SCREEN_H - 4 - tipH
        end
        if tipY < 4 then tipY = 4 end
        Renderer.drawTooltipPanel(vg, tipItem, tipX, tipY, pw, false, false)
    end
end

--- 绘制锁定图标（使用物品栏风格的锁定图片，与进度文字同行）
function M.drawLockIcon(vg, cx, cy, lockImg)
    local lockSz = 14
    if lockImg and lockImg > 0 then
        local lx = cx - lockSz / 2
        local ly = cy - lockSz / 2
        local paint = nvgImagePattern(vg, lx, ly, lockSz, lockSz, 0, lockImg, 0.7)
        nvgBeginPath(vg)
        nvgRect(vg, lx, ly, lockSz, lockSz)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(100, 100, 80, 150))
        nvgText(vg, cx, cy, "🔒", nil)
    end
end

-- ===== 输入处理 =====

--- 清除所有签到相关 tooltip
local function clearSigninTooltips()
    M._tooltipPinned = false
    M._pinnedTpl = nil
    M._pinnedAnchor = nil
    M._hoverTpl = nil
    M._hoverAnchor = nil
end

--- 处理点击事件，返回 true 表示已消费
function M.handleClick(x, y)
    -- 宝石选择面板优先处理（最上层，不受地点限制，可从背包使用自选箱触发）
    if M._gemSelectVisible then
        -- 关闭按钮
        if M._gemCloseBtnRect then
            local r = M._gemCloseBtnRect
            if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
                M._gemSelectVisible = false
                M._gemSelectBoxes = nil
                M._gemSelectedId = nil
                M._gemPinnedTpl = nil
                M._gemPinnedAnchor = nil
                M._pendingGemDay = nil
                M._pendingGemRewardType = nil
                M._pendingGemSlotIdx = nil
                return true
            end
        end

        -- 确定按钮
        if M._gemConfirmBtnRect and M._gemSelectedId then
            local r = M._gemConfirmBtnRect
            if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
                M.confirmGemSelection(M._gemSelectedId)
                M._gemSelectedId = nil
                M._gemPinnedTpl = nil
                M._gemPinnedAnchor = nil
                return true
            end
        end

        -- 点击宝石格子 → 选中 + 固定tooltip
        if M._gemSelectBoxes then
            for i, box in ipairs(M._gemSelectBoxes) do
                if x >= box.x and x <= box.x + box.w and y >= box.y and y <= box.y + box.h then
                    M._gemSelectedId = box.gemId
                    -- 固定tooltip
                    local tpl = M._gemIconRects and M._gemIconRects[i] and M._gemIconRects[i].itemTpl
                    if tpl then
                        if M._gemPinnedTpl == tpl then
                            M._gemPinnedTpl = nil
                            M._gemPinnedAnchor = nil
                        else
                            M._gemPinnedTpl = tpl
                            M._gemPinnedAnchor = { x = box.x, y = box.y, w = box.w, h = box.h }
                        end
                    end
                    return true
                end
            end
        end

        -- 点击面板内其他区域：取消固定tooltip
        local panelW = 260
        local panelH = 290
        local panelX = (GS.SCREEN_W - panelW) / 2
        local panelY = (GS.SCREEN_H - panelH) / 2
        if x >= panelX and x <= panelX + panelW and y >= panelY and y <= panelY + panelH then
            M._gemPinnedTpl = nil
            M._gemPinnedAnchor = nil
            return true
        end

        -- 点击面板外关闭
        M._gemSelectVisible = false
        M._gemSelectBoxes = nil
        M._gemSelectedId = nil
        M._gemPinnedTpl = nil
        M._gemPinnedAnchor = nil
        M._pendingGemDay = nil
        M._pendingGemRewardType = nil
        M._pendingGemSlotIdx = nil
        return true
    end

    -- 副手选择面板处理（最上层，不受地点限制）
    if M._offhandSelectVisible then
        -- 关闭按钮
        if M._offhandCloseBtnRect then
            local r = M._offhandCloseBtnRect
            if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
                M._offhandSelectVisible = false
                M._offhandSelectBoxes = nil
                M._offhandSelectedId = nil
                M._offhandPinnedTpl = nil
                M._offhandPinnedAnchor = nil
                M._pendingOffhandSlotIdx = nil
                return true
            end
        end

        -- 确定按钮
        if M._offhandConfirmBtnRect and M._offhandSelectedId then
            local r = M._offhandConfirmBtnRect
            if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
                M.confirmOffhandSelection(M._offhandSelectedId)
                M._offhandSelectedId = nil
                M._offhandPinnedTpl = nil
                M._offhandPinnedAnchor = nil
                return true
            end
        end

        -- 点击副手格子 → 选中 + 固定tooltip
        if M._offhandSelectBoxes then
            for i, box in ipairs(M._offhandSelectBoxes) do
                if x >= box.x and x <= box.x + box.w and y >= box.y and y <= box.y + box.h then
                    M._offhandSelectedId = box.itemId
                    -- 固定tooltip
                    local tpl = M._offhandIconRects and M._offhandIconRects[i] and M._offhandIconRects[i].itemTpl
                    if tpl then
                        if M._offhandPinnedTpl == tpl then
                            M._offhandPinnedTpl = nil
                            M._offhandPinnedAnchor = nil
                        else
                            M._offhandPinnedTpl = tpl
                            M._offhandPinnedAnchor = { x = box.x, y = box.y, w = box.w, h = box.h }
                        end
                    end
                    return true
                end
            end
        end

        -- 点击面板内其他区域：取消固定tooltip
        local panelW = 230
        local panelH = 210
        local panelX = (GS.SCREEN_W - panelW) / 2
        local panelY = (GS.SCREEN_H - panelH) / 2
        if x >= panelX and x <= panelX + panelW and y >= panelY and y <= panelY + panelH then
            M._offhandPinnedTpl = nil
            M._offhandPinnedAnchor = nil
            return true
        end

        -- 点击面板外关闭
        M._offhandSelectVisible = false
        M._offhandSelectBoxes = nil
        M._offhandSelectedId = nil
        M._offhandPinnedTpl = nil
        M._offhandPinnedAnchor = nil
        M._pendingOffhandSlotIdx = nil
        return true
    end

    -- 以下仅清水镇室外响应点击
    if GS.currentAreaName ~= "清水镇" or GS.homeMode or GS.trainingMode or BoardOverlay.subScene then
        return false
    end

    -- 签到按钮点击
    if GS.signInBtnRect and not GS.signInPanelVisible then
        local r = GS.signInBtnRect
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            GS.signInPanelVisible = true
            clearSigninTooltips()
            return true
        end
    end

    -- 面板打开时
    if GS.signInPanelVisible then
        -- 关闭按钮
        if M._closeBtnRect then
            local r = M._closeBtnRect
            if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
                GS.signInPanelVisible = false
                clearSigninTooltips()
                return true
            end
        end

        -- 点击物品图标 → 固定/取消完整 tooltip
        if M._iconRects then
            for _, ir in ipairs(M._iconRects) do
                if ir.itemTpl and x >= ir.x and x <= ir.x + ir.w and y >= ir.y and y <= ir.y + ir.h then
                    if M._tooltipPinned and M._pinnedTpl == ir.itemTpl then
                        M._tooltipPinned = false
                        M._pinnedTpl = nil
                        M._pinnedAnchor = nil
                    else
                        M._tooltipPinned = true
                        M._pinnedTpl = ir.itemTpl
                        M._pinnedAnchor = { x = ir.x, y = ir.y, w = ir.w, h = ir.h }
                    end
                    return true
                end
            end
        end

        -- 点击整框领取
        if M._rewardBoxes then
            for _, box in ipairs(M._rewardBoxes) do
                if x >= box.x and x <= box.x + box.w and y >= box.y and y <= box.y + box.h then
                    if box.daily then
                        M.claimDailyReward(box.rewardType)
                    else
                        M.claimReward(box.day, box.rewardType)
                    end
                    return true
                end
            end
        end

        -- 点击面板内其他区域：取消固定的 tooltip
        local panelW, panelH, panelX, panelY
        if M.isDailyMode() then
            panelW = math.min(280, GS.SCREEN_W - 20)
            panelH = 190
            panelX = (GS.SCREEN_W - panelW) / 2
            panelY = (GS.SCREEN_H - panelH) / 2
        elseif M._fiveDayPanelRect then
            -- 使用渲染时缓存的自适应面板尺寸
            panelX = M._fiveDayPanelRect.x
            panelY = M._fiveDayPanelRect.y
            panelW = M._fiveDayPanelRect.w
            panelH = M._fiveDayPanelRect.h
        else
            panelW = math.min(340, GS.SCREEN_W - 20)
            panelH = 290
            panelX = (GS.SCREEN_W - panelW) / 2
            panelY = (GS.SCREEN_H - panelH) / 2
        end

        if x >= panelX and x <= panelX + panelW and y >= panelY and y <= panelY + panelH then
            clearSigninTooltips()
            return true
        end

        -- 点击面板外关闭
        GS.signInPanelVisible = false
        clearSigninTooltips()
        return true
    end

    return false
end

return M
