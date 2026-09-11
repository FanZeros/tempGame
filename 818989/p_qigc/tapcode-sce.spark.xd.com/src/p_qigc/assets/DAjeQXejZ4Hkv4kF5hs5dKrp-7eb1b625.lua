-- ====================================================================
-- SessionLock.lua - 多端会话锁（v2）
-- 防止玩家同时在多台设备上运行游戏（规避强化/精炼失败结果）
--
-- 工作原理：
--   1. app 启动时仅在本地生成 sessionId，不写云端
--   2. 玩家选择槽位并成功加载存档后，才写入云端（onEnterGame）
--      → 云端始终保存「最后进入游戏」的那台设备的 ID
--   3. 心跳（15s）读取云端 ID，若不符 → 强制返回角色选择界面
--      → charSlotIndex 被清空 → saveToCloud 自动变成空操作
--      → 旧内存存档无法写入云端
--   4. 打开委托加工界面时触发即时检查（加快发现速度）
-- ====================================================================

local M = {}

-- ────────────────────────────────────────────────────────────────────
-- 配置
-- ────────────────────────────────────────────────────────────────────
local SESSION_KEY              = "__dev_session__"
local HEARTBEAT_INTERVAL_NORMAL = 5    -- 秒：普通游玩时的心跳间隔
local HEARTBEAT_INTERVAL_CRAFT  = 3    -- 秒：委托加工界面内的高频心跳

-- ────────────────────────────────────────────────────────────────────
-- 内部状态
-- ────────────────────────────────────────────────────────────────────
local sessionId_      = 0      -- 本设备会话 ID（随机整数，本地生成）
local inGame_         = false  -- 是否已进入游戏（loadSlot 成功后为 true）
local heartbeatTimer_ = 0      -- 心跳计时器（秒）
local locked_         = false  -- 是否已检测到多端登录

-- ────────────────────────────────────────────────────────────────────
-- 私有工具
-- ────────────────────────────────────────────────────────────────────

local function generateSessionId()
    local t = os.time()
    math.randomseed(t)
    local a = math.random(1, 999999)
    math.randomseed(t + a)
    local b = math.random(1, 999999)
    local id = (a * 1000 + b) % 2000000000
    return (id == 0) and 1 or id
end

-- 强制返回角色选择界面，清空活跃槽位
-- charSlotIndex = nil 后，saveToCloud 的首行检查会自动拦截所有存档
local function forceReturnToCharSelect()
    local ok, GS = pcall(require, "GameState")
    if not ok or not GS then return end

    if GS.gameState == GS.STATE_MENU then return end  -- 已在开始游戏界面，无需重复

    print("[SessionLock] 强制返回开始游戏界面")

    -- 先关掉所有存档相关状态，防止黑屏期间意外触发存档
    GS.charSlotIndex    = nil       -- 清空活跃槽位 → saveToCloud 自动拦截
    GS.autoSave.enabled = false     -- 关闭自动存档
    GS.craftMode        = false
    GS.homeCraftMode    = false
    GS.enchantMode      = false
    GS.homeEnchantMode  = false
    inGame_             = false

    -- 黑屏淡入后切换界面，避免画面硬跳
    GS.screenFade = {
        alpha    = 0,
        target   = 255,
        speed    = 400,
        callback = function()
            GS.gameState  = GS.STATE_MENU
            -- 重新拉取最新 meta，确保下次进入选角界面时显示的是最新云端数据
            -- （Device B 长期在后台，charSlotMeta 已过期）
            local okSave, GSSave = pcall(require, "GameState_Save")
            if okSave and GSSave and GSSave.preloadCloudSave then
                print("[SessionLock] 重新加载云端存档 meta")
                GSSave.preloadCloudSave()
            end
            -- 淡出黑屏
            GS.screenFade = { alpha = 255, target = 0, speed = 300 }
        end
    }
end

local function showLockedWarning()
    local ok, DM = pcall(require, "DialogueManager")
    if ok and DM and DM.startDynamic then
        DM.startDynamic({
            { speaker = "系统", text = "检测到您的账号已在另一台设备上登录，已返回角色选择界面。如需继续游戏，请重新进入。" }
        })
    else
        print("[SessionLock] 警告：账号在另一台设备登录")
    end
end

-- 检测到多端登录的统一处理
local function onMultiDeviceDetected()
    if locked_ then return end
    locked_ = true
    forceReturnToCharSelect()
    showLockedWarning()
end

-- ────────────────────────────────────────────────────────────────────
-- 公开 API
-- ────────────────────────────────────────────────────────────────────

--- 在 Start() 中调用：仅在本地生成 sessionId，不写云端。
--- 云端写入推迟到 onEnterGame()，避免「打开 app 但未进入游戏」就占用会话。
function M.init()
    sessionId_ = generateSessionId()
    print("[SessionLock] 初始化，本机 sessionId=" .. sessionId_)
end

--- 在 loadSlotFromCloud 成功回调中调用：正式进入游戏，写入云端。
--- 从这一刻起本设备持有会话锁，其他设备的心跳将检测到不一致。
function M.onEnterGame()
    inGame_ = true
    locked_ = false   -- 重新进入游戏时重置，确保心跳检查恢复正常
    heartbeatTimer_ = 0
    print("[SessionLock] 进入游戏，写入云端 sessionId=" .. sessionId_)

    clientCloud:SetInt(SESSION_KEY, sessionId_, {
        ok = function(values, iscores)
            print("[SessionLock] 会话 ID 已写入云端")
        end,
        err = function(code, msg)
            print("[SessionLock] 写入失败: " .. tostring(code) .. " " .. tostring(msg))
        end
    })
end

--- 异步检查当前会话是否有效。
--- onValid / onInvalid 均可为 nil。
function M.check(onValid, onInvalid)
    if locked_ then
        if onInvalid then onInvalid() end
        return
    end

    clientCloud:Get(SESSION_KEY, {
        ok = function(values, iscores)
            local cloudId = iscores and iscores[SESSION_KEY]
            if cloudId and cloudId ~= 0 and cloudId ~= sessionId_ then
                print("[SessionLock] 多端登录! 云端=" .. tostring(cloudId)
                      .. " 本机=" .. tostring(sessionId_))
                onMultiDeviceDetected()
                if onInvalid then onInvalid() end
            else
                if onValid then onValid() end
            end
        end,
        err = function(code, msg)
            -- 网络错误保守处理：不踢出（避免误伤）
            print("[SessionLock] 检查失败(网络): " .. tostring(msg))
            if onValid then onValid() end
        end
    })
end

--- 打开委托加工界面时调用：触发即时检查，加快发现速度。
--- 若检测到多端登录，直接返回角色选择界面。
function M.checkOnCraftOpen()
    if not inGame_ then return end
    M.check(nil, nil)  -- onMultiDeviceDetected 已在 check 内部统一处理
end

--- 从后台恢复焦点时调用：同步设置阻断标志后立刻检查会话。
--- 阻断标志（GS.resumeCheckPending）让 saveToCloud 在检查完成前直接 return，
--- 消除"检查回调返回前 autoSave 已发出写入"的竞态窗口。
function M.checkOnResume()
    if not inGame_ then return end

    local ok, GS = pcall(require, "GameState")
    if ok and GS then
        GS.resumeCheckPending = true   -- 同步阻断，先于任何 Update tick
    end
    heartbeatTimer_ = 0

    print("[SessionLock] 从后台恢复，立刻检查会话（存档已阻断）")

    local function release()
        if ok and GS then GS.resumeCheckPending = false end
    end

    M.check(
        release,   -- 会话有效：释放阻断，正常恢复存档
        release    -- 会话无效：已被踢回选角（charSlotIndex=nil），释放标志无害
    )
end

--- 每帧更新（心跳）。进入游戏后才启动。
--- 委托加工界面内使用高频心跳（3s），其余状态使用普通频率（15s）。
function M.update(dt)
    if locked_ or not inGame_ then return end

    local ok, GS = pcall(require, "GameState")
    local inCraft = ok and GS and GS.craftMode == true
    local interval = inCraft and HEARTBEAT_INTERVAL_CRAFT or HEARTBEAT_INTERVAL_NORMAL

    heartbeatTimer_ = heartbeatTimer_ + dt
    if heartbeatTimer_ >= interval then
        heartbeatTimer_ = 0
        M.check(nil, nil)
    end
end

--- 返回当前是否已检测到多端登录。
function M.isLocked()
    return locked_
end

return M
