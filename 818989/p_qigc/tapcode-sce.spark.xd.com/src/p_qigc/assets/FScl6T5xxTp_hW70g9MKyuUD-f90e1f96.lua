-- ====================================================================
-- BanManager.lua - 实时封禁系统（基于 clientCloud iscore）
-- ====================================================================
-- 原理：
--   GM 封禁玩家时，在自己的 iscore 写入 ban_<userId> = 1
--   所有客户端每分钟通过 GetUserRank 查询 GM 的 ban_<myId> 值
--   如果值 >= 1，则判定为被封禁，踢回角色选择界面
-- ====================================================================

local GS = require("GameState")

local M = {}

-- ── 配置 ──
local POLL_INTERVAL = 60         -- 轮询间隔（秒）
local NICKNAME_BATCH_SIZE = 200  -- GetUserNickname 每批最多查询数量

-- ── 分批查询昵称（绕过单次请求数量上限）──
local function batchGetNicknames(userIds, onDone)
    local map = {}
    local total = #userIds
    if total == 0 then onDone(map); return end
    local totalBatches = math.ceil(total / NICKNAME_BATCH_SIZE)
    local doneBatches = 0
    for i = 1, total, NICKNAME_BATCH_SIZE do
        local batch = {}
        for j = i, math.min(i + NICKNAME_BATCH_SIZE - 1, total) do
            batch[#batch + 1] = userIds[j]
        end
        GetUserNickname({
            userIds = batch,
            onSuccess = function(nicknames)
                for _, info in ipairs(nicknames) do
                    if info.nickname and info.nickname ~= "" then
                        map[tostring(info.userId)] = info.nickname
                    end
                end
                doneBatches = doneBatches + 1
                if doneBatches >= totalBatches then onDone(map) end
            end,
            onError = function()
                doneBatches = doneBatches + 1
                if doneBatches >= totalBatches then onDone(map) end
            end
        })
    end
end

local GM_PRIMARY_ID = 1576069892 -- 主 GM 的 userId（用于存储封禁数据）
local MAX_BAN_DISPLAY = 50       -- 面板最大显示数量

-- ── 状态 ──
local pollTimer = 0              -- 轮询计时器
local isBannedFlag = false       -- 当前用户是否被封禁
local initialized = false        -- 是否已初始化
local firstCheckDone = false     -- 首次检查是否完成

-- ── GM 面板状态 ──
local gmBanList = {}             -- GM 本地维护的封禁列表 { {userId=number, time=string}, ... }
local gmBanListLoaded = false    -- 是否已从云端加载
local gmInputText = ""           -- GM 输入框文本
local gmStatusMsg = ""           -- 操作状态消息
local gmStatusTimer = 0          -- 状态消息倒计时
local gmPanelOpen = false        -- 面板是否打开
local gmScrollOffset = 0         -- 列表滚动偏移
local gmInputActive = false      -- 输入框是否激活
local gmInputMode = "id"         -- 输入模式: "id" = TapTap用户ID, "nickname" = TapTap昵称
local gmNicknameSearching = false -- 昵称搜索中（异步）

-- ── GM 面板标签页 ──
local gmActiveTab = "ban"        -- 当前标签页: "ban" = 封禁管理, "restore" = 存档修复

-- ── 存档修复 Tab 状态 ──
local restoreInput = {
    userId      = "",            -- 目标玩家 TapTap ID（字符串，输入中）
    slotIdx     = 1,             -- 目标槽位 1-6
    backupIndex = 1,             -- 备份序号 1=最新 2=中间 3=最旧
    activeField = nil,           -- 当前激活的输入框: "userId" 或 nil
    statusMsg   = "",            -- 操作反馈
    statusTimer = 0,
}

-- 面板点击区域（渲染时写入，Input 读取）
M.panelRects = {}                -- { close, input, banBtn, unbanBtns = {} }

-- ====================================================================
-- 公共 API
-- ====================================================================

--- 初始化封禁管理器（在 clientCloud 就绪后调用）
function M.init()
    if initialized then return end
    if not clientCloud then return end
    initialized = true
    pollTimer = 0  -- 立即执行首次检查
    -- GM 加载封禁列表
    if GS.isGM() then
        M._loadGMBanList()
    end
end

--- 每帧更新（在 HandleUpdate 中调用）
---@param dt number
function M.update(dt)
    if not initialized or not clientCloud then return end

    -- 状态消息倒计时
    if gmStatusTimer > 0 then
        gmStatusTimer = gmStatusTimer - dt
        if gmStatusTimer <= 0 then
            gmStatusMsg = ""
        end
    end
    M.restoreUpdateTimer(dt)

    -- 轮询封禁状态
    pollTimer = pollTimer - dt
    if pollTimer <= 0 then
        pollTimer = POLL_INTERVAL
        M._checkBanStatus()
    end
end

--- 检查当前用户是否被封禁
---@return boolean
function M.isBanned()
    return isBannedFlag
end

--- 首次检查是否已完成
---@return boolean
function M.isFirstCheckDone()
    return firstCheckDone
end

--- 执行封禁（踢回角色选择界面 + 显示提示）
function M.enforce()
    if not isBannedFlag then return end
    -- 如果不在角色选择界面，踢回去
    if GS.gameState ~= GS.STATE_CHAR_SELECT and GS.gameState ~= GS.STATE_CHAR_CREATE then
        GS.gameState = GS.STATE_CHAR_SELECT
        GS.charSlotIndex = nil
        GS.autoSave.enabled = false
    end
    GS.charSelectBanMsg = { text = "您的账号已被封禁", timer = 5.0 }
end

--- 替代旧的 checkBanned()，供 Input.lua 调用
---@return boolean
function M.checkBanned()
    if isBannedFlag then
        GS.charSelectBanMsg = { text = "您的账号已被封禁", timer = 3.0 }
        return true
    end
    return false
end

-- ── GM 面板控制 ──

function M.isGMPanelOpen()
    return gmPanelOpen
end

function M.toggleGMPanel()
    gmPanelOpen = not gmPanelOpen
    if gmPanelOpen and not gmBanListLoaded then
        M._loadGMBanList()
    end
end

function M.closeGMPanel()
    gmPanelOpen = false
    gmInputActive = false
    input:SetScreenKeyboardVisible(false)
end

function M.getGMInputText()
    return gmInputText
end

function M.setGMInputText(text)
    gmInputText = text
end

function M.getGMBanList()
    return gmBanList
end

function M.getGMStatusMsg()
    return gmStatusMsg
end

function M.isInputActive()
    return gmInputActive
end

function M.activateInput()
    gmInputActive = true
    input:SetScreenKeyboardVisible(true)
end

function M.deactivateInput()
    gmInputActive = false
    input:SetScreenKeyboardVisible(false)
end

function M.getInputMode()
    return gmInputMode
end

function M.toggleInputMode()
    if gmInputMode == "id" then
        gmInputMode = "nickname"
    else
        gmInputMode = "id"
    end
    gmInputText = ""  -- 切换模式时清空输入
end

function M.isNicknameSearching()
    return gmNicknameSearching
end

function M.appendInputChar(ch)
    if not gmInputActive then return end
    if gmInputMode == "id" then
        -- ID 模式：只接受数字
        if ch:match("^%d+$") then
            if #gmInputText < 20 then
                gmInputText = gmInputText .. ch
            end
        end
    else
        -- 昵称模式：接受任意字符（中文、字母、数字等）
        local currentLen = utf8.len(gmInputText) or 0
        local chLen = utf8.len(ch) or 0
        if currentLen + chLen <= 30 then
            gmInputText = gmInputText .. ch
        end
    end
end

function M.backspaceInput()
    if not gmInputActive then return end
    if #gmInputText > 0 then
        if gmInputMode == "id" then
            -- 纯 ASCII 数字，直接截断最后一个字符
            gmInputText = gmInputText:sub(1, -2)
        else
            -- 昵称模式：UTF-8 安全截断
            local chars = {}
            for _, c in utf8.codes(gmInputText) do
                table.insert(chars, utf8.char(c))
            end
            table.remove(chars)
            gmInputText = table.concat(chars)
        end
    end
end

function M.getScrollOffset()
    return gmScrollOffset
end

function M.setScrollOffset(offset)
    gmScrollOffset = math.max(0, offset)
end

-- ── 标签页 API ──
function M.getActiveTab() return gmActiveTab end
function M.setActiveTab(tab)
    gmActiveTab = tab
    -- 切换 Tab 时关闭所有输入框激活状态
    gmInputActive = false
    restoreInput.activeField = nil
    input:SetScreenKeyboardVisible(false)
end

-- ── 存档修复 Tab API ──
function M.getRestoreInput() return restoreInput end

function M.restoreActivateUserId()
    restoreInput.activeField = "userId"
    input:SetScreenKeyboardVisible(true)
end

function M.restoreDeactivate()
    restoreInput.activeField = nil
    input:SetScreenKeyboardVisible(false)
end

function M.restoreIsUserIdActive()
    return restoreInput.activeField == "userId"
end

function M.restoreAppendChar(ch)
    if restoreInput.activeField == "userId" then
        if ch:match("^%d+$") and #restoreInput.userId < 20 then
            restoreInput.userId = restoreInput.userId .. ch
        end
    end
end

function M.restoreBackspace()
    if restoreInput.activeField == "userId" and #restoreInput.userId > 0 then
        restoreInput.userId = restoreInput.userId:sub(1, -2)
    end
end

function M.restoreSetSlot(idx)
    restoreInput.slotIdx = math.max(1, math.min(6, idx))
end

function M.restoreSetBackupIndex(idx)
    restoreInput.backupIndex = math.max(1, math.min(3, idx))
end

function M.restoreSetStatus(msg, duration)
    restoreInput.statusMsg = msg
    restoreInput.statusTimer = duration or 4.0
end

function M.restoreUpdateTimer(dt)
    if restoreInput.statusTimer > 0 then
        restoreInput.statusTimer = restoreInput.statusTimer - dt
        if restoreInput.statusTimer <= 0 then
            restoreInput.statusMsg = ""
        end
    end
end

--- GM 下发存档修复指令
function M.sendRestoreCmd()
    local userId = tonumber(restoreInput.userId)
    if not userId or userId <= 0 then
        M.restoreSetStatus("请输入有效的 TapTap 用户ID", 3.0)
        return
    end
    local slot = restoreInput.slotIdx
    local backupIndex = restoreInput.backupIndex
    -- 正确写法：
    --   SetInt("gm_restore", targetUserId)     → iscore，用于排行榜匹配目标玩家
    --   Set("gm_restore_cmd", cmdData)         → score，存储指令参数
    local cmdData = { slot = slot, backupIndex = backupIndex, ts = os.time() }
    clientCloud:BatchSet()
        :SetInt("gm_restore", userId)
        :Set("gm_restore_cmd", cmdData)
        :Save("GM存档修复指令", {
            ok = function()
                M.restoreSetStatus("指令已发送 → 玩家上线后自动执行（槽位" .. slot .. " 备份" .. backupIndex .. "）", 6.0)
                print("[GMRestore] 指令已写入 userId=" .. userId .. " slot=" .. slot .. " backupIndex=" .. backupIndex)
            end,
            error = function(code, reason)
                M.restoreSetStatus("发送失败: " .. tostring(reason), 4.0)
                print("[GMRestore] 写入失败:", code, reason)
            end,
        })
end

function M.cancelRestoreCmd()
    clientCloud:BatchSet()
        :Delete("gm_restore")
        :Delete("gm_restore_cmd")
        :Save("撤销GM存档修复指令", {
            ok = function()
                M.restoreSetStatus("指令已撤销", 3.0)
                print("[GMRestore] 指令已撤销")
            end,
            error = function(code, reason)
                M.restoreSetStatus("撤销失败: " .. tostring(reason), 3.0)
            end,
        })
end

--- GM 封禁入口（根据当前输入模式自动选择）
---@param inputText string
function M.gmBanUserByInput(inputText)
    if gmInputMode == "id" then
        M.gmBanUser(inputText)
    else
        M.gmBanByNickname(inputText)
    end
end

--- GM 封禁一个用户（按 ID）
---@param userIdStr string
function M.gmBanUser(userIdStr)
    if not GS.isGM() then return end
    if not clientCloud then return end

    local targetId = tonumber(userIdStr)
    if not targetId or targetId <= 0 then
        gmStatusMsg = "无效的用户ID"
        gmStatusTimer = 3.0
        return
    end

    M._executeBan(targetId)
end

--- GM 封禁一个用户（按昵称，异步匹配）
---@param nickname string
function M.gmBanByNickname(nickname)
    if not GS.isGM() then return end
    if not clientCloud then return end

    if not nickname or #nickname == 0 then
        gmStatusMsg = "请输入昵称"
        gmStatusTimer = 3.0
        return
    end

    if gmNicknameSearching then
        gmStatusMsg = "正在搜索中，请稍候..."
        gmStatusTimer = 2.0
        return
    end

    gmNicknameSearching = true
    gmStatusMsg = "正在搜索昵称: " .. nickname .. " ..."
    gmStatusTimer = 15.0

    -- 只查当天在线排行榜前1000名
    local onlineKey = "online_" .. os.date("%Y%m%d")
    local searchNickname = nickname

    clientCloud:GetRankList(onlineKey, 0, 1000, {
        ok = function(rankList)
            local allUserIds = {}
            for _, item in ipairs(rankList) do
                table.insert(allUserIds, item.userId)
            end
            M._matchNicknameAndBan(allUserIds, searchNickname)
        end,
        error = function(code, reason)
            gmNicknameSearching = false
            gmStatusMsg = "获取在线列表失败: " .. tostring(code)
            gmStatusTimer = 4.0
        end
    })
end

--- 内部：从收集到的 userIds 中匹配昵称并执行封禁
---@param userIds number[]
---@param targetNickname string
function M._matchNicknameAndBan(userIds, targetNickname)
    if #userIds == 0 then
        gmNicknameSearching = false
        gmStatusMsg = "排行榜中无用户数据，无法匹配"
        gmStatusTimer = 4.0
        return
    end

    -- 分批查询（每批200，防止单次超限丢失用户）
    batchGetNicknames(userIds, function(map)
        gmNicknameSearching = false
        local matched = {}
        for uid, nick in pairs(map) do
            if nick == targetNickname then
                table.insert(matched, { userId = tonumber(uid) or uid, nickname = nick })
            end
        end

        if #matched == 0 then
            gmStatusMsg = "未找到昵称为 \"" .. targetNickname .. "\" 的用户"
            gmStatusTimer = 4.0
        elseif #matched == 1 then
            local uid = matched[1].userId
            gmStatusMsg = "匹配到用户: " .. tostring(uid) .. " (" .. matched[1].nickname .. ")"
            gmStatusTimer = 3.0
            M._executeBan(uid, matched[1].nickname)
        else
            -- 多个同名用户，全部封禁
            local idList = {}
            for _, info in ipairs(matched) do
                table.insert(idList, tostring(info.userId))
            end
            gmStatusMsg = "找到" .. #matched .. "个同名用户: " .. table.concat(idList, ", ") .. "，全部封禁"
            gmStatusTimer = 5.0
            for _, info in ipairs(matched) do
                M._executeBan(info.userId, info.nickname)
            end
        end
    end)
end

--- 内部：执行封禁操作（共用逻辑）
---@param targetId number
---@param nickname string|nil
function M._executeBan(targetId, nickname)
    if not GS.isGM() then return end
    if not clientCloud then return end

    if not targetId or targetId <= 0 then
        gmStatusMsg = "无效的用户ID"
        gmStatusTimer = 3.0
        return
    end

    -- 不能封禁 GM 自己
    if GS.GM_IDS[tostring(targetId)] then
        gmStatusMsg = "不能封禁管理员"
        gmStatusTimer = 3.0
        return
    end

    -- 检查是否已在列表中
    for _, entry in ipairs(gmBanList) do
        if entry.userId == targetId then
            gmStatusMsg = "用户 " .. tostring(targetId) .. " 已在封禁列表中"
            gmStatusTimer = 3.0
            return
        end
    end

    -- 写入 iscore: ban_<userId> = 1
    local banKey = "ban_" .. tostring(targetId)
    clientCloud:SetInt(banKey, 1, {
        ok = function()
            -- 更新本地列表
            table.insert(gmBanList, {
                userId = targetId,
                time = os.date("%Y-%m-%d %H:%M"),
                nickname = nickname,
            })
            -- 保存列表到云端 values
            M._saveGMBanList()
            local displayName = nickname and (nickname .. " (" .. tostring(targetId) .. ")") or tostring(targetId)
            gmStatusMsg = "已封禁: " .. displayName
            gmStatusTimer = 3.0
            gmInputText = ""
            print("[BanManager] Banned user: " .. tostring(targetId) .. (nickname and (" nickname=" .. nickname) or ""))
        end,
        error = function(code, reason)
            gmStatusMsg = "封禁失败: " .. tostring(reason)
            gmStatusTimer = 3.0
            print("[BanManager] Ban failed: " .. tostring(reason))
        end
    })
end

--- GM 解封一个用户
---@param targetId number
function M.gmUnbanUser(targetId)
    if not GS.isGM() then return end
    if not clientCloud then return end

    -- 写入 iscore: ban_<userId> = 0
    local banKey = "ban_" .. tostring(targetId)
    clientCloud:SetInt(banKey, 0, {
        ok = function()
            -- 从本地列表移除
            for i = #gmBanList, 1, -1 do
                if gmBanList[i].userId == targetId then
                    table.remove(gmBanList, i)
                    break
                end
            end
            M._saveGMBanList()
            gmStatusMsg = "已解封: " .. tostring(targetId)
            gmStatusTimer = 3.0
            print("[BanManager] Unbanned user: " .. tostring(targetId))
        end,
        error = function(code, reason)
            gmStatusMsg = "解封失败: " .. tostring(reason)
            gmStatusTimer = 3.0
            print("[BanManager] Unban failed: " .. tostring(reason))
        end
    })
end

-- ====================================================================
-- 内部实现
-- ====================================================================

--- 检查当前用户是否被封禁（通过读取 GM 的 iscore）
function M._checkBanStatus()
    local myId = clientCloud.userId
    if not myId then return end

    -- GM 不检查自己
    if GS.isGM() then
        firstCheckDone = true
        return
    end

    local banKey = "ban_" .. tostring(myId)

    clientCloud:GetUserRank(GM_PRIMARY_ID, banKey, {
        ok = function(rank, scoreValue)
            firstCheckDone = true
            local wasBanned = isBannedFlag
            -- scoreValue >= 1 表示被封禁
            isBannedFlag = (scoreValue ~= nil and scoreValue >= 1)

            if isBannedFlag and not wasBanned then
                -- 新检测到封禁，立即执行
                print("[BanManager] Ban detected for userId: " .. tostring(myId))
                M.enforce()
            elseif not isBannedFlag and wasBanned then
                -- 被解封
                print("[BanManager] User unbanned: " .. tostring(myId))
            end
        end,
        error = function(code, reason)
            firstCheckDone = true
            -- 查询失败不改变状态
            print("[BanManager] Check failed: " .. tostring(reason))
        end
    })
end

--- GM: 从云端加载封禁列表（存在 values.ban_list 中）
function M._loadGMBanList()
    if not clientCloud then return end
    clientCloud:Get("ban_list", {
        ok = function(values, iscores)
            local list = values and values.ban_list
            if type(list) == "table" then
                gmBanList = list
            else
                gmBanList = {}
            end
            gmBanListLoaded = true
            print("[BanManager] GM ban list loaded, count=" .. #gmBanList)
        end,
        error = function(code, reason)
            gmBanListLoaded = true
            print("[BanManager] Failed to load ban list: " .. tostring(reason))
        end
    })
end

--- GM: 保存封禁列表到云端
function M._saveGMBanList()
    if not clientCloud then return end
    clientCloud:Set("ban_list", gmBanList, {
        ok = function()
            print("[BanManager] Ban list saved, count=" .. #gmBanList)
        end,
        error = function(code, reason)
            print("[BanManager] Failed to save ban list: " .. tostring(reason))
        end
    })
end

return M
