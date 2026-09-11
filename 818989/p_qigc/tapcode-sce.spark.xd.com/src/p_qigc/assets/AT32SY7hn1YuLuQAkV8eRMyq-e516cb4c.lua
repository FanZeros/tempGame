-- ====================================================================
-- Input.lua - 鼠标/触摸输入、操作指令生成
-- ====================================================================
-- 为联机做准备：输入逻辑独立，可转为指令发送到服务端
-- ====================================================================

---@diagnostic disable-next-line: undefined-global
local sdk = sdk  -- 引擎运行时注入的全局对象

local GS = require("GameState")
local Combat = require("Combat")
local Command = require("Command")
local BoardOverlay = require("BoardOverlay")
local DungeonManager = require("Dungeon.DungeonManager")
local OnlineMonitor = require("OnlineMonitor")
local MonitorPanel = require("MonitorPanel")
local SignInSystem = require("SignInSystem")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local SessionLock = require("SessionLock")
local BanManager = require("BanManager")

local M = {}

--- 检查当前账号是否被封禁（委托 BanManager）
---@return boolean
local function checkBanned()
    return BanManager.checkBanned()
end

-- 长按加点状态
local statHoldKey = nil       -- 当前长按的属性key
local statHoldTimer = 0       -- 已按住时长
local statHoldInterval = 0    -- 距上次加点的累计时间
local STAT_HOLD_DELAY = 0.35  -- 长按触发前的初始延迟（秒）
local STAT_HOLD_RATE  = 0.06  -- 持续加点间隔（秒）

-- 长按制作状态（锻造/炼金/烹饪）
local craftHoldType     = nil   -- "forge" | "alchemy" | "cooking"
local craftHoldIdx      = nil   -- 配方索引
local craftHoldTimer    = 0     -- 已按住时长
local craftHoldInterval = 0     -- 距上次制作的累计时间
local CRAFT_HOLD_DELAY  = 0.35  -- 长按触发前的初始延迟（秒）
local CRAFT_HOLD_RATE   = 0.15  -- 持续制作间隔（秒）

--- 矩形点击检测
---@param mx number 鼠标X
---@param my number 鼠标Y
---@param r table {x, y, w, h}
---@return boolean
local function hitTest(mx, my, r)
    return r and mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

-- ====================================================================
-- 网络检测 + 云存档确认后展示结果 的统一封装（防拔网线作弊）
-- 用于强化、重铸、精炼操作：
--   1. 先用 clientScore:Get 探测网络连通性
--   2. 网络不通 → 弹窗提示，不执行操作
--   3. 网络通 → 快照关键状态 → 执行操作（随机+扣费）→ 不展示结果
--   4. 调用 saveToCloud
--   5. 云存档成功 → 展示结果
--   6. 云存档失败 → 回滚到快照状态，提示存档失败
-- ====================================================================
local _netCheckBusy = false       -- 防止重入
local _netCheckDeadline = 0       -- 应用层超时截止时间（os.clock()）
local _netCheckPhase = ""         -- 当前阶段（"get" / "save"），用于日志
local _netCheckResultSetter = nil -- 当前操作的 resultSetter，超时时用于清除 pending 消息

--- 应用层超时检查（在 handleMouseDown 入口调用）
--- 引擎的 timeout 回调时长未知，这里用 os.clock() 强制 3 秒上限
local function _tryNetTimeout()
    if not _netCheckBusy then return end
    if os.clock() < _netCheckDeadline then return end
    -- 已超时但回调未触发 → 强制解锁并提示
    print("[netCheck] 应用层超时（阶段: " .. _netCheckPhase .. "）")
    if _netCheckResultSetter then
        _netCheckResultSetter({ success = false, msg = "网络响应超时，请重试。", timer = 3.0 })
    end
    _netCheckBusy = false
    _netCheckResultSetter = nil
end

--- 深拷贝物品（包括 refineSlots 等嵌套表）
local function _deepCopyItem(item)
    if not item then return nil end
    local copy = {}
    for k, v in pairs(item) do
        if type(v) == "table" then
            -- refineSlots / gemSlots / effects 等嵌套表需要深拷贝
            copy[k] = {}
            for sk, sv in pairs(v) do
                if type(sv) == "table" then
                    copy[k][sk] = {}
                    for sk2, sv2 in pairs(sv) do
                        copy[k][sk][sk2] = sv2
                    end
                else
                    copy[k][sk] = sv
                end
            end
        else
            copy[k] = v
        end
    end
    return copy
end

--- 从快照恢复物品字段（原地还原，保持引用不变）
local function _restoreItem(target, snapshot)
    -- 清除当前字段
    for k in pairs(target) do
        target[k] = nil
    end
    -- 从快照恢复
    for k, v in pairs(snapshot) do
        if type(v) == "table" then
            target[k] = {}
            for sk, sv in pairs(v) do
                if type(sv) == "table" then
                    target[k][sk] = {}
                    for sk2, sv2 in pairs(sv) do
                        target[k][sk][sk2] = sv2
                    end
                else
                    target[k][sk] = sv
                end
            end
        else
            target[k] = v
        end
    end
end

--- 快照背包（只拷贝被占用的格子）
local function _snapshotInventory()
    local snap = {}
    for i = 1, GS.bagSlots do
        if GS.inventory[i] then
            snap[i] = _deepCopyItem(GS.inventory[i])
        end
    end
    return snap
end

--- 从快照恢复背包
local function _restoreInventory(snap)
    for i = 1, GS.bagSlots do
        if snap[i] then
            if GS.inventory[i] then
                _restoreItem(GS.inventory[i], snap[i])
            else
                GS.inventory[i] = snap[i]
            end
        else
            GS.inventory[i] = nil
        end
    end
end

--- 网络检测后执行操作，云存档成功后展示结果，失败则回滚
---@param operationFn fun(): boolean, string  执行操作并返回 (ok, msg)
---@param resultSetter fun(result: table|nil)  设置结果展示
---@param targetItem table|nil  被操作的物品（强化/精炼/重铸的目标），用于回滚
---@param pendingMsg string|nil  等待期间显示的文案（默认 "处理中……"）
local function netCheckedOperation(operationFn, resultSetter, targetItem, pendingMsg)
    if _netCheckBusy then return end
    _netCheckBusy = true
    _netCheckDeadline = os.clock() + 3.0
    _netCheckPhase = "get"
    _netCheckResultSetter = resultSetter

    -- 立即显示等待提示，让玩家知道操作正在进行
    resultSetter({ pending = true, msg = pendingMsg or "处理中……", timer = 999 })

    local getResolved = false  -- 防止 ok/error/timeout 多次触发

    clientScore:Get("meta", {
        ok = function()
            if getResolved then return end
            getResolved = true

            -- 网络通 → 快照关键状态
            local snapGold = GS.gold
            local snapItem = targetItem and _deepCopyItem(targetItem) or nil
            local snapInv = _snapshotInventory()
            local snapEnhUseCat = GS.enhanceUseCatalyst

            -- 执行操作（随机结果、扣金币、扣材料等）
            local ok, msg = operationFn()

            -- 发起云存档，结果暂不展示
            _netCheckDeadline = os.clock() + 3.0  -- Save 阶段再给 3 秒
            _netCheckPhase = "save"
            local saveResolved = false
            GS.saveToCloud({
                ok = function()
                    if saveResolved then return end
                    saveResolved = true
                    -- 云存档成功 → 更新自动存档快照，避免多余的自动存档
                    GS.updateAutoSaveSnapshot()
                    -- 展示结果
                    resultSetter({ success = ok, msg = msg, timer = 2.0 })
                    _netCheckBusy = false
                    _netCheckResultSetter = nil
                end,
                error = function()
                    if saveResolved then return end
                    saveResolved = true
                    -- 云存档失败 → 回滚到操作前状态（防拔网线作弊）
                    GS.gold = snapGold
                    GS.enhanceUseCatalyst = snapEnhUseCat
                    _restoreInventory(snapInv)
                    if targetItem and snapItem then
                        _restoreItem(targetItem, snapItem)
                    end
                    GS.recalcStats(GS.player)
                    resultSetter({ success = false, msg = "检测不到网络连接，请到信号良好的地方重试。", timer = 3.0 })
                    _netCheckBusy = false
                    _netCheckResultSetter = nil
                end,
                timeout = function()
                    if saveResolved then return end
                    saveResolved = true
                    -- 存档超时 → 回滚（玩家未看到结果，回滚保持本地状态与玩家认知一致）
                    GS.gold = snapGold
                    GS.enhanceUseCatalyst = snapEnhUseCat
                    _restoreInventory(snapInv)
                    if targetItem and snapItem then
                        _restoreItem(targetItem, snapItem)
                    end
                    GS.recalcStats(GS.player)
                    resultSetter({ success = false, msg = "网络不稳定，请重试。", timer = 3.0 })
                    _netCheckBusy = false
                    _netCheckResultSetter = nil
                end,
            })
        end,
        error = function()
            if getResolved then return end
            getResolved = true
            -- 网络不通 → 弹窗提示，不执行操作
            resultSetter({ success = false, msg = "检测不到网络连接，请到信号良好的地方重试。", timer = 3.0 })
            _netCheckBusy = false
            _netCheckResultSetter = nil
        end,
        timeout = function()
            if getResolved then return end
            getResolved = true
            -- 网络探测超时 → 提示（未修改任何数据，安全解锁）
            resultSetter({ success = false, msg = "网络响应超时，请重试。", timer = 3.0 })
            _netCheckBusy = false
            _netCheckResultSetter = nil
        end,
    })
end
-- ====================================================================
-- 兑换码定义与统一验证
-- ====================================================================
local redeemCodeDefs = {
    ["Thanku4play"] = {
        rewards = function()
            GS.addToInventory("hero_offhand_pack", 1)
            GS.addToInventory("backpack_expand", 2)
            GS.addToInventory("potion_hp_s", 10)
            GS.addToInventory("potion_mp_s", 10)
            GS.gold = GS.gold + 500
        end,
        msg = "兑换成功！获得副手自选包、扩充券x2、药水、500G",
    },
    ["zhuangdongxi"] = {
        rewards = function()
            GS.addToInventory("backpack_expand", 5)
            GS.addToInventory("warehouse_expand", 5)
        end,
        msg = "兑换成功！获得背包扩充券x5、仓库扩充券x5",
    },



    ["supergamer"] = {
        accountOnce = true,
        accountKey = "redeem_supergamer",
        rewards = function()
            GS.adFree = true
            GS.triggerAutoSave()
        end,
        msg = "兑换成功！已获得免广告权益（全局生效）",
    },


    ["lajifuwuqi"] = {
        accountOnce = true,
        accountKey  = "redeem_lajifuwuqi",
        rewards = function()
            GS.addToInventory("gratitude_ticket",    5)
            GS.addToInventory("divine_enchant_agent",  1)
            GS.addToInventory("divine_toughness_agent", 1)
        end,
        msg = "兑换成功！获得感恩礼券x5、神炼附魔剂x1、神炼增韧剂x1",
    },

    ["yunlei111"] = {
        globalOnce = true,
        globalKey  = "redeem_yunlei111",
        rewards = function()
            -- 创建蕴雷实例，获取装备引用
            local _, _, item = GS.addToInventory("yun_lei", 1)
            if item then
                -- 设置深渊随机档位：mDef=3档 / elecDmgBonus=5档 / mDefPct=5档 / compChainLightningMax=4档
                item.abyssStatTiers = {
                    mDef                  = 3,
                    elecDmgBonus          = 5,
                    mDefPct               = 5,
                    compChainLightningMax = 4,
                }
                item.hasRandom = true
                GS.rebuildAbyssStats(item)
                -- 设置强化等级 +10
                item.enhanceLevel = 10
                item.name = "\u{201c}蕴雷\u{201d} +10"
            end
        end,
        msg = "兑换成功！获得「蕴雷」+10（魔防3档 / 雷伤5档 / 魔防%5档 / 闪电链4档）",
    },

    ["liquanchuxian"] = {
        globalOnce = true,
        globalKey  = "redeem_liquanchuxian",
        rewards = function()
            GS.addToInventory("gratitude_ticket", 300)
        end,
        msg = "兑换成功！获得感恩礼券x300",
    },

    -- 存档恢复角色槽位兑换码（账户级唯一，从最新每日备份恢复）
    -- cshfjs = 存档恢复角色  y/e/s/si/w/l = 一/二/三/四/五/六
    -- 注意：restoreSlotFromBackup 会用旧备份覆盖 slot，导致 redeemedCodes 记录消失。
    -- 因此 onSuccess 中必须重新触发 triggerAutoSave，确保 redeemedCodes[code]=true 被持久化。
    ["cshfjsy"]  = { accountOnce = true, asyncRewards = true, accountKey = "redeem_cshfjsy",  rewards = function() GS.shopBuyMsg = { text = "正在恢复角色一备份...", timer = 99.0, color = {200, 200, 60} } GS.restoreSlotFromBackup(1, function(tag) GS.redeemedCodes["cshfjsy"] = true GS.triggerAutoSave() GS.shopBuyMsg = { text = "角色一已从备份(" .. tag .. ")恢复，请重新进入角色以生效", timer = 8.0, color = {60, 220, 100} } end, function(r) GS.shopBuyMsg = { text = "恢复失败：" .. r, timer = 5.0, color = {220, 60, 40} } end) end },
    ["cshfjse"]  = { accountOnce = true, asyncRewards = true, accountKey = "redeem_cshfjse",  rewards = function() GS.shopBuyMsg = { text = "正在恢复角色二备份...", timer = 99.0, color = {200, 200, 60} } GS.restoreSlotFromBackup(2, function(tag) GS.redeemedCodes["cshfjse"] = true GS.triggerAutoSave() GS.shopBuyMsg = { text = "角色二已从备份(" .. tag .. ")恢复，请重新进入角色以生效", timer = 8.0, color = {60, 220, 100} } end, function(r) GS.shopBuyMsg = { text = "恢复失败：" .. r, timer = 5.0, color = {220, 60, 40} } end) end },
    ["cshfjss"]  = { accountOnce = true, asyncRewards = true, accountKey = "redeem_cshfjss",  rewards = function() GS.shopBuyMsg = { text = "正在恢复角色三备份...", timer = 99.0, color = {200, 200, 60} } GS.restoreSlotFromBackup(3, function(tag) GS.redeemedCodes["cshfjss"] = true GS.triggerAutoSave() GS.shopBuyMsg = { text = "角色三已从备份(" .. tag .. ")恢复，请重新进入角色以生效", timer = 8.0, color = {60, 220, 100} } end, function(r) GS.shopBuyMsg = { text = "恢复失败：" .. r, timer = 5.0, color = {220, 60, 40} } end) end },
    ["cshfjssi"] = { accountOnce = true, asyncRewards = true, accountKey = "redeem_cshfjssi", rewards = function() GS.shopBuyMsg = { text = "正在恢复角色四备份...", timer = 99.0, color = {200, 200, 60} } GS.restoreSlotFromBackup(4, function(tag) GS.redeemedCodes["cshfjssi"] = true GS.triggerAutoSave() GS.shopBuyMsg = { text = "角色四已从备份(" .. tag .. ")恢复，请重新进入角色以生效", timer = 8.0, color = {60, 220, 100} } end, function(r) GS.shopBuyMsg = { text = "恢复失败：" .. r, timer = 5.0, color = {220, 60, 40} } end) end },
    ["cshfjsw"]  = { accountOnce = true, asyncRewards = true, accountKey = "redeem_cshfjsw",  rewards = function() GS.shopBuyMsg = { text = "正在恢复角色五备份...", timer = 99.0, color = {200, 200, 60} } GS.restoreSlotFromBackup(5, function(tag) GS.redeemedCodes["cshfjsw"] = true GS.triggerAutoSave() GS.shopBuyMsg = { text = "角色五已从备份(" .. tag .. ")恢复，请重新进入角色以生效", timer = 8.0, color = {60, 220, 100} } end, function(r) GS.shopBuyMsg = { text = "恢复失败：" .. r, timer = 5.0, color = {220, 60, 40} } end) end },
    ["cshfjsl"]  = { accountOnce = true, asyncRewards = true, accountKey = "redeem_cshfjsl",  rewards = function() GS.shopBuyMsg = { text = "正在恢复角色六备份...", timer = 99.0, color = {200, 200, 60} } GS.restoreSlotFromBackup(6, function(tag) GS.redeemedCodes["cshfjsl"] = true GS.triggerAutoSave() GS.shopBuyMsg = { text = "角色六已从备份(" .. tag .. ")恢复，请重新进入角色以生效", timer = 8.0, color = {60, 220, 100} } end, function(r) GS.shopBuyMsg = { text = "恢复失败：" .. r, timer = 5.0, color = {220, 60, 40} } end) end },
}

--- 统一兑换码验证与发放（点击确定 & 回车键共用）
---@param code string
local function processRedeemCode(code)
    local codeDef = redeemCodeDefs[code]
    if not codeDef then
        GS.shopBuyMsg = { text = "无效的兑换码", timer = 2.0, color = {220, 60, 40} }
        return
    end
    if codeDef.expireDate then
        local ed = codeDef.expireDate
        local now = os.date("*t")
        if now.year > ed[1] or (now.year == ed[1] and now.month > ed[2])
            or (now.year == ed[1] and now.month == ed[2] and now.day >= ed[3]) then
            GS.shopBuyMsg = { text = "该兑换码已过期", timer = 2.0, color = {220, 160, 40} }
            return
        end
    end
    if GS.redeemedCodes[code] then
        GS.shopBuyMsg = { text = "该兑换码已使用过", timer = 2.0, color = {220, 160, 40} }
        return
    end
    -- 等级限制
    if codeDef.levelMin then
        local lv = GS.player and GS.player.level or 0
        if lv < codeDef.levelMin then
            GS.shopBuyMsg = { text = "需要角色达到 " .. codeDef.levelMin .. " 级才能兑换", timer = 2.5, color = {220, 160, 40} }
            return
        end
    end
    -- 职业限制
    if codeDef.classReq then
        if GS.currentClass ~= codeDef.classReq then
            local className = GS.CLASS_NAMES and GS.CLASS_NAMES[codeDef.classReq] or codeDef.classReq
            GS.shopBuyMsg = { text = "仅限【" .. className .. "】职业角色兑换", timer = 2.5, color = {220, 160, 40} }
            return
        end
    end
    -- 全服唯一兑换码：通过排行榜做全服唯一校验（异步）
    if codeDef.globalOnce and codeDef.globalKey then
        if not clientCloud then
            GS.shopBuyMsg = { text = "网络不可用，请稍后再试", timer = 2.0, color = {220, 160, 40} }
            return
        end
        local gKey = codeDef.globalKey
        -- 防止重复点击
        GS.shopBuyMsg = { text = "正在验证兑换码...", timer = 99.0, color = {200, 200, 60} }
        clientCloud:GetRankList(gKey, 0, 1, {
            ok = function(rankList)
                if rankList and #rankList > 0 then
                    -- 排行榜已有记录，说明已被其他玩家兑换
                    GS.shopBuyMsg = { text = "该兑换码已被其他玩家兑换", timer = 3.0, color = {220, 60, 40} }
                    return
                end
                -- 排行榜为空，提交占位（Add 1 到排行榜），成功后发放奖励
                clientCloud:Add(gKey, 1, {
                    ok = function()
                        codeDef.rewards()
                        GS.redeemedCodes[code] = true
                        GS.triggerAutoSave()
                        GS.shopBuyMsg = { text = codeDef.msg, timer = 4.0, color = {60, 200, 60} }
                    end,
                    error = function(errCode, reason)
                        GS.shopBuyMsg = { text = "兑换失败，请稍后再试", timer = 2.0, color = {220, 60, 40} }
                        print("[Redeem] 全局占位失败:", errCode, reason)
                    end,
                })
            end,
            error = function(errCode, reason)
                GS.shopBuyMsg = { text = "网络错误，请稍后再试", timer = 2.0, color = {220, 60, 40} }
                print("[Redeem] 全局校验失败:", errCode, reason)
            end,
        })
        return
    end
    -- 账户唯一兑换码：通过云变量做账户级唯一校验（异步）
    if codeDef.accountOnce and codeDef.accountKey then
        if not clientCloud then
            GS.shopBuyMsg = { text = "网络不可用，请稍后再试", timer = 2.0, color = {220, 160, 40} }
            return
        end
        local aKey = codeDef.accountKey
        GS.shopBuyMsg = { text = "正在验证兑换码...", timer = 99.0, color = {200, 200, 60} }
        clientCloud:Get(aKey, {
            ok = function(values, iscores)
                local cloudVal = iscores and iscores[aKey]
                if cloudVal and cloudVal > 0 then
                    -- 该账户已在某个角色上兑换过
                    GS.shopBuyMsg = { text = "该兑换码已在其他角色上使用过", timer = 3.0, color = {220, 60, 40} }
                    return
                end
                -- 未兑换，写入云变量占位后发放奖励
                clientCloud:Add(aKey, 1, {
                    ok = function()
                        GS.redeemedCodes[code] = true
                        GS.triggerAutoSave()
                        if codeDef.asyncRewards then
                            -- 异步奖励：自行管理 shopBuyMsg 流程
                            codeDef.rewards()
                        else
                            codeDef.rewards()
                            GS.shopBuyMsg = { text = codeDef.msg, timer = 4.0, color = {60, 200, 60} }
                        end
                    end,
                    error = function(errCode, reason)
                        GS.shopBuyMsg = { text = "兑换失败，请稍后再试", timer = 2.0, color = {220, 60, 40} }
                        print("[Redeem] 账户占位失败:", errCode, reason)
                    end,
                })
            end,
            error = function(errCode, reason)
                GS.shopBuyMsg = { text = "网络错误，请稍后再试", timer = 2.0, color = {220, 60, 40} }
                print("[Redeem] 账户校验失败:", errCode, reason)
            end,
        })
        return
    end
    -- 普通兑换码：同步发放
    codeDef.rewards()
    GS.redeemedCodes[code] = true
    GS.shopBuyMsg = { text = codeDef.msg, timer = 3.0, color = {60, 200, 60} }
end

-- 建筑 key → NPC key 映射（用于 questSubmit 等缺少 npcKey 的上下文）
local BUILDING_TO_NPC = {
    guild           = "guild_receptionist",
    guild_master_office = "guild_master",
    tavern          = "tavern_keeper",
    tavern_dancefloor = "tavern_dancer",
    potion_shop     = "potion_shop_owner",
    jewelry_shop    = "jewelry_shop_owner",
    blacksmith      = "blacksmith_owner",
    armor_shop      = "armor_shop_owner",
    forest_elf      = "forest_elf",
}

--- 通用对话文本占位符替换
--- {玩家}/{爱称} 或 {玩家}\{爱称} → 伴侣用爱称，否则用玩家名
--- {玩家} → 玩家名    {爱称} → NPC对玩家的爱称    {伴侣} → 伴侣名
---@param s string 原始文本
---@param npcKey string|nil NPC 标识（用于判断是否伴侣和获取爱称）
---@return string
local function replaceDialogueTags(s, npcKey)
    if not s then return "" end
    local pName = GS.charName or ""
    -- 如果传入的是建筑 key，转换为 NPC key
    if npcKey and BUILDING_TO_NPC[npcKey] then
        npcKey = BUILDING_TO_NPC[npcKey]
    end
    -- 获取爱称
    local petName = ""
    if npcKey then petName = GS.getNPCPetName(npcKey) end
    -- {玩家}/{爱称} 或 {玩家}\{爱称} → 条件选择：伴侣用爱称，否则用玩家名
    local isPartner = GS.partnerNpcKey and GS.partnerNpcKey == npcKey
    local condName = (isPartner and petName ~= "") and petName or pName
    s = s:gsub("{玩家}/{爱称}", condName)
    s = s:gsub("{玩家}\\{爱称}", condName)
    -- 冒险者/{咳咳} → 伴侣用"咳咳……冒险者"，否则用"冒险者"（芙蕾雅任务接取专用）
    s = s:gsub("冒险者/{咳咳}", isPartner and "咳咳……冒险者" or "冒险者")
    -- 冒险者/{玩家} → 伴侣用爱称，否则用"冒险者"
    s = s:gsub("冒险者/{玩家}", (isPartner and petName ~= "") and petName or "冒险者")
    -- 单独的占位符
    if pName ~= "" then s = s:gsub("{玩家}", pName) end
    if petName ~= "" then s = s:gsub("{爱称}", petName) end
    -- {伴侣} → 当前伴侣名
    if GS.partnerNpcKey then
        local partnerInfo = GS.NPC_REGISTRY[GS.partnerNpcKey]
        if partnerInfo then s = s:gsub("{伴侣}", partnerInfo.name) end
    end
    return s
end

--- 将 submitDialogue/acceptDialogue 统一转换为 dlgLines 数组
--- 支持两种格式:
---   单说话人: { speaker = "X", lines = {"a","b"} }
---   多说话人: { {speaker="X", lines={"a"}}, {speaker="Y", lines={"b"}} }
---@param dlg table submitDialogue 或 acceptDialogue
---@param replFn function|nil 文本替换函数（如 {玩家}/{爱称} 替换）
---@return table dlgLines  {{speaker=, text=}, ...}
local function flattenDialogue(dlg, replFn)
    local out = {}
    if not dlg then return out end
    if dlg.speaker then
        -- 单说话人格式
        for _, lt in ipairs(dlg.lines) do
            local text = replFn and replFn(lt) or lt
            out[#out + 1] = { speaker = dlg.speaker, text = text }
        end
    else
        -- 多说话人格式（数组）
        for _, part in ipairs(dlg) do
            if part.speaker and part.lines then
                for _, lt in ipairs(part.lines) do
                    local text = replFn and replFn(lt) or lt
                    out[#out + 1] = { speaker = part.speaker, text = text }
                end
            end
        end
    end
    return out
end

--- 为 dlgLines 注入延迟奖励发放的 onShow 回调
--- rewardAtLine > 0: 在该行出现时发放奖励
--- rewardAtLine == 0: 在对话结束后发放（返回修改后的 onComplete 回调）
---@param dlgLines table 展平后的对话行数组
---@param questId string 任务 ID
---@param rewardAtLine number 奖励发放行号 (1-based, 0=对话结束)
---@param origOnComplete function|nil 原始的对话完成回调
---@return function onComplete 可能被包装过的完成回调
local function injectRewardCallback(dlgLines, questId, rewardAtLine, origOnComplete)
    local QuestManager = require("QuestManager")
    if rewardAtLine > 0 then
        -- 在指定行的 onShow 中发放奖励
        local targetIdx = math.min(rewardAtLine, #dlgLines)
        if targetIdx >= 1 and dlgLines[targetIdx] then
            dlgLines[targetIdx].onShow = function()
                QuestManager._doGiveRewards(questId)
            end
        end
        return origOnComplete
    else
        -- rewardAtLine == 0: 在对话结束后发放
        return function()
            QuestManager._doGiveRewards(questId)
            if origOnComplete then origOnComplete() end
        end
    end
end

--- UTF-8 字符计数（中文3字节=1字符，ASCII 1字节=1字符）
local function utf8Len(s)
    local len = 0
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        if b < 0x80 then i = i + 1
        elseif b < 0xE0 then i = i + 2
        elseif b < 0xF0 then i = i + 3
        else i = i + 4 end
        len = len + 1
    end
    return len
end

--- 将长文本按中文句末标点拆分为多页对话行（每页≤48字符≈3行）
---@param text string 原始文本
---@param speaker string 说话人
---@return table[] 对话行列表 { {speaker, text}, ... }
local function splitLongText(text, speaker)
    local MAX_CHARS = 48
    if utf8Len(text) <= MAX_CHARS then
        return { { speaker = speaker, text = text } }
    end
    -- 中文句末标点的 UTF-8 字节序列
    local puncts = {
        "\xe3\x80\x82",  -- 。
        "\xef\xbc\x81",  -- ！
        "\xef\xbc\x9f",  -- ？
    }
    -- 按句末标点拆分为句子
    local sentences = {}
    local pos = 1
    while pos <= #text do
        local nearest = nil
        for _, p in ipairs(puncts) do
            local s, e = text:find(p, pos, true)
            if s and (not nearest or s < nearest.s) then
                nearest = { s = s, e = e }
            end
        end
        if nearest then
            local endPos = nearest.e
            -- 句末标点后紧跟闭合引号时，将引号归入当前句子，避免引号被拆到下一句
            -- 对于 ASCII " 需要区分开/闭引号：统计该字符之前出现的次数，奇数=闭合
            local afterByte = text:byte(endPos + 1)
            if afterByte == 0x22 then                        -- ASCII "
                -- 统计从文本开头到 endPos 为止 " 出现的次数
                local qCount = 0
                for qi = 1, endPos do
                    if text:byte(qi) == 0x22 then qCount = qCount + 1 end
                end
                -- 奇数个 " 说明当前处于引号内，下一个 " 是闭合引号，归入当前句子
                if qCount % 2 == 1 then
                    endPos = endPos + 1
                end
            elseif text:sub(endPos + 1, endPos + 3) == "\xe2\x80\x9d" then  -- 中文右双引号 "
                endPos = endPos + 3
            end
            sentences[#sentences + 1] = text:sub(pos, endPos)
            pos = endPos + 1
        else
            sentences[#sentences + 1] = text:sub(pos)
            break
        end
    end
    -- 贪心合并：尽量把多个句子塞进一页
    local pages = {}
    local cur = ""
    for _, sent in ipairs(sentences) do
        if cur == "" then
            cur = sent
        elseif utf8Len(cur) + utf8Len(sent) <= MAX_CHARS then
            cur = cur .. sent
        else
            pages[#pages + 1] = cur
            cur = sent
        end
    end
    if cur ~= "" then
        pages[#pages + 1] = cur
    end
    -- 构建对话行
    local lines = {}
    for _, pg in ipairs(pages) do
        lines[#lines + 1] = { speaker = speaker, text = pg }
    end
    return lines
end

-- 没有告白选项的 NPC
local NO_CONFESS_NPCS = { blacksmith_owner = true, armor_shop_owner = true }

-- 告白文本表：按好感度等级分级
-- 索引 1~6 对应 陌生/友善/在意/亲近(重视)/珍视(亲密)/爱慕
-- 索引 7 = 已有伴侣时告白
-- 每条: { text = "...", delta = 好感度变化 }
-- {玩家} → 玩家名字, {伴侣} → 当前伴侣名字
local CONFESS_TEXTS = {
    guild_master = {  -- 芙蕾雅
        { text = "我不该揣测你，但你现在很奇怪。我劝你最好把心思放在正事上，至少别做坏事。", delta = -2 },
        { text = "我认为你最好把心思放在正事上。", delta = -1 },
        { text = "我认为你最好把心思放在正事上，今天的冒险委托完成了吗？", delta = 0 },
        { text = "{玩家}，现在不是想这些的时候。", delta = 0 },
        { text = "{玩家}……你这样让我的心好乱，你先回去，好吗？", delta = 2 },
        { text = "{玩家}，其实你说的时候，我的心正在怦怦乱跳。我决定正视自己的感情，我也喜欢你。", delta = 5 },
        { text = "你这样做，{伴侣}会怎么想？", delta = -3 },
    },
    guild_receptionist = {  -- 妮可
        { text = "你是不是发烧了？", delta = -2 },
        { text = "啊？冒险者，你是不是发烧了？", delta = -1 },
        { text = "你是不是发烧了？你要好好休息，不要胡思乱想了。", delta = 0 },
        { text = "……谢谢你的心意，但是，我觉得我们现在这样就很好了。", delta = 0 },
        { text = "{玩家}，我……我还没有做好准备。", delta = 2 },
        { text = "{玩家}，谢谢你喜欢这么平凡的我，你可以答应我，要一直、一直喜欢我吗？", delta = 5 },
        { text = "{伴侣}如果知道你这样会伤心的！", delta = -3 },
    },
    jewelry_shop_owner = {  -- 朱莉
        { text = "你睡醒了吗？", delta = -2 },
        { text = "你需要冷静一下。", delta = -1 },
        { text = "你还好吗？是不是睡眠不足？", delta = 0 },
        { text = "你看这颗宝石，虽然是我仿制的，但是很漂亮吧？", delta = 0 },
        { text = "{玩家}，我知道你的心意了，我会考虑的，好吗？", delta = 2 },
        { text = "{玩家}，我喜欢宝石，因为宝石的寿命是永恒的，你的喜欢也是吗？那么，让我试一下吧。", delta = 5 },
        { text = "我会告诉{伴侣}哦……我不会，骗你的，但是下次不要这样了。", delta = -3 },
    },
    potion_shop_owner = {  -- 莉娜
        { text = "……", delta = -2 },
        { text = "……", delta = -1 },
        { text = "我这里有药剂出售，你看起来很需要。", delta = 0 },
        { text = "你是在开玩笑吧？", delta = 0 },
        { text = "{玩家}，这对我来说需要非常大的勇气……我恐怕……", delta = 2 },
        { text = "{玩家}，这需要勇气，但是我不会再退缩了。我喜欢你，我第一次这么喜欢一个男人。", delta = 5 },
        { text = "……", delta = -3 },
    },
    tavern_keeper = {  -- 爱丽丝
        { text = "冒险者，你是姜啤酒喝太多，喝醉了吧？", delta = -2 },
        { text = "冒险者，要来杯果汁醒醒酒吗？", delta = -1 },
        { text = "{玩家}，是不是最近冒险太累了呢？多休息一下会好一些哦。", delta = 0 },
        { text = "{玩家}，谢谢你。我很喜欢你，但现在只是朋友之间的喜欢。", delta = 0 },
        { text = "{玩家}，我……你是认真的吧？不要捉弄我！", delta = 2 },
        { text = "{玩家}，如果你是认真的话——你是吗？是吧？那么，我答应你，因为我也一直偷偷喜欢着你。", delta = 5 },
        { text = "{伴侣}会听到哦。", delta = -3 },
    },
    tavern_dancer = {  -- 安吉莉娅
        { text = "{玩家}，但我可没有你这么随便。", delta = -2 },
        { text = "{玩家}，嘻嘻，我有一点分不清你是喝多了还是喝少了。", delta = -1 },
        { text = "{玩家}，喜欢我的人有很多，迄今为止我还没有心动过。如果你真喜欢我的话，就试试吧。", delta = 0 },
        { text = "{玩家}，我承认我在考虑你，但目前你还需要多努力才行。", delta = 0 },
        { text = "{玩家}，这是我人生中第一次有这种感觉……我还没有准备好，甚至有些害怕。", delta = 2 },
        { text = "{玩家}，其实我很害怕，我不能再失去任何重要的人了。但是，和你在一起的愿望是那么强烈。可以一直看着我吗？", delta = 5 },
        { text = "{伴侣}和你吵架了？你真可怜。", delta = -3 },
    },
    forest_elf = {  -- 艾莉雅
        { text = "……", delta = -2 },
        { text = "……你很奇怪。", delta = -1 },
        { text = "你们人类的情感表达方式，我还在学习理解。", delta = 0 },
        { text = "{玩家}，你们人类的生命太短暂了，不要把时间浪费在这种事上。", delta = 0 },
        { text = "{玩家}……我确实感到对你有\u{201c}需要\u{201d}的情感，但是这是什么呢？我还没有想明白。", delta = 2 },
        { text = "{玩家}，我的寿命远长于你，做出这个决定对我来说并不容易。但是我喜欢你，我已决定陪你走这一程。", delta = 5 },
        { text = "……{伴侣}知道吗？你们人类的感情，比我想象的还要复杂。", delta = -3 },
    },
}

-- 求婚文本（已是伴侣后出现的选项）
-- decline = 挚爱以下的拒绝文本, accept = 挚爱级别的同意文本
local PROPOSAL_TEXTS = {
    guild_master = {  -- 芙蕾雅
        decline = { text = "{玩家}，我很喜欢你，但是这太快了……再给我们一点时间，好吗？", delta = 1 },
        accept  = { text = "我答应你。我一直在等你。为我戴上吧。", delta = 3 },
    },
    guild_receptionist = {  -- 妮可
        decline = { text = "{玩家}，啊，我还没有准备好，我……", delta = 1 },
        accept  = { text = "{玩家}，我真是太幸福了，我早在心里想了无数次，只是今天我才有勇气——我答应你！", delta = 3 },
    },
    jewelry_shop_owner = {  -- 朱莉
        decline = { text = "{玩家}，我们是不是有些太着急了？", delta = 1 },
        accept  = { text = "{玩家}，这枚戒指太漂亮了。但此时此刻，我的眼里只有你……我同意。", delta = 3 },
    },
    potion_shop_owner = {  -- 莉娜
        decline = { text = "{玩家}，我心里已经同意了。但请给我一点时间……", delta = 1 },
        accept  = { text = "{玩家}！那么，说你爱我，我就答应你……好，我答应。", delta = 3 },
    },
    tavern_keeper = {  -- 爱丽丝
        decline = { text = "{玩家}，是不是发展得太快了？我们才刚刚……但我很开心。", delta = 1 },
        accept  = { text = "呀！当然！当然！我太高兴了，{玩家}，我爱你。我答应你。对不起，我语无伦次了。", delta = 3 },
    },
    tavern_dancer = {  -- 安吉莉娅
        decline = { text = "{玩家}，我很想答应你，让我考虑一下，好吗？", delta = 1 },
        accept  = { text = "{玩家}……今后，无论如何都不要离开我？快许诺，哪怕骗我也好……", delta = 3 },
    },
    forest_elf = {  -- 艾莉雅
        decline = { text = "{玩家}，对于精灵来说，誓约是非常严肃的，我还需要考虑，但是你能提议我很开心。", delta = 1 },
        accept  = { text = "{玩家}，订下誓约吧，我已决意这样做。", delta = 3 },
    },
}

-- ====================================================================
-- 亲吻文本（伴侣在建筑场景中的亲吻互动）
-- adore = 爱慕等级（好感度6），devoted = 挚爱等级（好感度7）
-- 每种是对话行列表 { speaker, text }
-- 暂时挚爱使用爱慕文本占位，后续替换
-- ====================================================================
local KISS_TEXTS = {
    guild_master = {  -- 芙蕾雅
        adore = {
            { speaker = "芙蕾雅", text = "（脸红）啊！等一下……这里是办公室。" },
            { speaker = "旁白", text = "（芙蕾雅的脸红成一团，像是下了决心。她站起身，身体前倾探过一整张桌子，在你脸上飞速\xe2\x80\x9c啄\xe2\x80\x9d了一下。）" },
            { speaker = "芙蕾雅", text = "{玩家}，这样可以了吗？剩下的不要在这里。" },
        },
        delta = 3,
    },
    guild_receptionist = {  -- 妮可
        adore = {
            { speaker = "妮可", text = "（脸红）啊呀，这里是前台呀！会有其他人过来的！那……就一下。" },
            { speaker = "旁白", text = "（妮可紧张得四处张望了一下，确认没有人在看向这里，把脑袋凑过来，嘴唇贴上了你的嘴唇……）" },
            { speaker = "妮可", text = "……{玩家}，我喜欢你。" },
        },
        delta = 3,
    },
    jewelry_shop_owner = {  -- 朱莉
        adore = {
            { speaker = "旁白", text = "（朱莉的黑色面纱在风中轻轻摆动，那背后的美丽脸庞只有你能看，想到这，你热血翻涌。）" },
            { speaker = "旁白", text = "（你望向她金黄色的眼眸，那目光像是一双拽住你的手。你亲吻她的额头、她的眼睛……）" },
            { speaker = "旁白", text = "（在你还想做些什么的时候，朱莉发出一阵笑声，轻巧地跳开了。）" },
            { speaker = "朱莉", text = "你好烫，是这里的首饰给了你能量吗？还是……我？" },
        },
        delta = 3,
    },
    potion_shop_owner = {  -- 莉娜
        adore = {
            { speaker = "莉娜", text = "……嗯，过来。" },
            { speaker = "旁白", text = "（你靠近莉娜，那些你爱的火红头发离你越来越近，直到它们轻轻环抱住了你的脑袋。）" },
            { speaker = "旁白", text = "（你知道自己的脸、鼻子和耳朵都在发烫，但都远不如你的另一个五官——嘴唇所感受到的……）" },
            { speaker = "旁白", text = "（……你像是晕过去了，直到莉娜轻轻推开你。她看向你呆滞的样子，\xe2\x80\x9c噗嗤\xe2\x80\x9d地笑了。）" },
        },
        delta = 3,
    },
    tavern_keeper = {  -- 爱丽丝
        adore = {
            { speaker = "爱丽丝", text = "……不要在这么多人的地方！" },
            { speaker = "旁白", text = "（尽管爱丽丝嘴上拒绝了你，但还是在一阵东张西望后，迅猛地在你嘴上亲了一下。）" },
            { speaker = "爱丽丝", text = "{玩家}，你现在喜欢我吗？比昨天是更多还是更少呢？" },
        },
        delta = 3,
    },
    tavern_dancer = {  -- 安吉莉娅
        adore = {
            { speaker = "旁白", text = "（你搂过安吉利娅的肩膀，把她拥入怀中，她很配合，侧过整个身体靠着你的胸膛。）" },
            { speaker = "旁白", text = "（你亲了她，她没有躲闪。你知道周围的人在看着你们，而你亦在宣示这位美丽女子的归属。）" },
            { speaker = "安吉莉娅", text = "……{玩家}，今后，请好好注视着我。" },
        },
        delta = 3,
    },
    forest_elf = {  -- 艾莉雅
        adore = {
            { speaker = "艾莉雅", text = "啊！不要……" },
            { speaker = "旁白", text = "（你抱着艾莉雅，坚定地看着她，她亦感受到了你的愿望。许久，她在你面前慢慢闭上了眼睛。）" },
            { speaker = "旁白", text = "（你知道她同意了，于是你吻了上去。她的嘴唇起初冰凉，但很快烫了起来……）" },
            { speaker = "艾莉雅", text = "{玩家}，我不是真的想拒绝你，我只是还不习惯……我能感受到，我喜欢你。" },
        },
        delta = 3,
    },
}
-- 暂时挚爱使用爱慕文本占位
for _, v in pairs(KISS_TEXTS) do
    if not v.devoted then v.devoted = v.adore end
end

--- 关闭家中伴侣交谈状态
local function closeHomePartnerTalk()
    GS.homePartnerTalkActive = false
    GS.eventInputLocked = false
    -- 如果交谈前伴侣在睡觉，交谈结束后检查是否仍在睡眠时间段
    if GS._partnerWasSleeping and GS.homeNpc then
        GS._partnerWasSleeping = nil
        local hn = GS.homeNpc
        if GS.isPartnerSleeping(hn.npcKey) then
            -- 仍在睡眠时间段 → 恢复睡眠状态
            hn.state = "sleeping"
        else
            -- 已过了睡眠时间段 → 触发唤醒移动到 (3,3)
            local wx, wy = 3, 3
            -- 检查玩家是否占据了目标位置，是则使用备选位置
            if GS.player.x == wx and GS.player.y == wy then
                wx, wy = 4, 3
            end
            local path = GS.homePathFind(hn.x, hn.y, wx, wy)
            if path and #path >= 2 then
                local ox, oy = hn.x, hn.y
                hn.x = wx
                hn.y = wy
                hn.state = "waking_up"
                Combat.startMoveAnim(hn, ox, oy, path)
            else
                hn.x = wx
                hn.y = wy
                hn.state = "idle"
            end
        end
    end
end

--- 加载史莱姆大反击排名数据
---@param tabIdx number 0=总排行, 1~5=各职业排行
function M._loadSlimeRevengeRankData(tabIdx)
    if not clientCloud then
        GS.slimeRevengeRankData = { entries = {}, myRank = nil }
        return
    end
    GS.slimeRevengeRankLoading = true
    GS.slimeRevengeRankData = nil

    local tabDef = GS.SLIME_RANK_TABS[(tabIdx or 0) + 1]
    if not tabDef then
        GS.slimeRevengeRankLoading = false
        GS.slimeRevengeRankData = { entries = {}, myRank = nil }
        return
    end
    local key = tabDef.key

    clientCloud:GetRankList(key, 0, 100, {
        ok = function(rankList)
            local entries = {}
            local userIds = {}
            local myUserId = clientCloud.userId or 0
            ---@type table|nil
            local myRank = nil

            for i, item in ipairs(rankList) do
                local dmg = item.iscore[key] or 0
                local className = (item.score and item.score.slime_rev_class) or nil
                if type(className) == "string" and #className == 0 then className = nil end
                table.insert(entries, {
                    rank = i,
                    userId = item.userId,
                    nickname = "",
                    damage = dmg,
                    className = className,
                })
                table.insert(userIds, item.userId)
                if item.userId == myUserId then
                    myRank = { rank = i, damage = dmg }
                end
            end

            if #userIds == 0 then
                GS.slimeRevengeRankLoading = false
                GS.slimeRevengeRankData = { entries = entries, myRank = myRank }
                return
            end

            -- 查询昵称
            GetUserNickname({
                userIds = userIds,
                onSuccess = function(nicknames)
                    local map = {}
                    for _, info in ipairs(nicknames) do
                        map[info.userId] = info.nickname or ""
                    end
                    for _, entry in ipairs(entries) do
                        entry.nickname = map[entry.userId] or ("ID:" .. tostring(entry.userId))
                    end
                    GS.slimeRevengeRankLoading = false
                    GS.slimeRevengeRankData = { entries = entries, myRank = myRank }
                end,
                onError = function(errorCode)
                    for _, entry in ipairs(entries) do
                        entry.nickname = "ID:" .. tostring(entry.userId)
                    end
                    GS.slimeRevengeRankLoading = false
                    GS.slimeRevengeRankData = { entries = entries, myRank = myRank }
                end
            })
        end,
        error = function(code, reason)
            GS.slimeRevengeRankLoading = false
            GS.slimeRevengeRankData = { entries = {}, myRank = nil }
            print("[大反击排名] 拉取排行榜失败:", code, reason)
        end
    }, "slime_rev_class")
end

--- 加载迪哈塔大反击排名数据
---@param tabIdx number 0=总排行, 1~5=各职业排行
function M._loadDihataRevengeRankData(tabIdx)
    if not clientCloud then
        GS.dihataRevengeRankData = { entries = {}, myRank = nil }
        return
    end
    GS.dihataRevengeRankLoading = true
    GS.dihataRevengeRankData = nil

    local tabDef = GS.DIHATA_RANK_TABS[(tabIdx or 0) + 1]
    if not tabDef then
        GS.dihataRevengeRankLoading = false
        GS.dihataRevengeRankData = { entries = {}, myRank = nil }
        return
    end
    local key = tabDef.key

    clientCloud:GetRankList(key, 0, 100, {
        ok = function(rankList)
            local entries = {}
            local userIds = {}
            local myUserId = clientCloud.userId or 0
            ---@type table|nil
            local myRank = nil

            for i, item in ipairs(rankList) do
                local dmg = item.iscore[key] or 0
                local className = (item.score and item.score.dihata_rev_class) or nil
                if type(className) == "string" and #className == 0 then className = nil end
                table.insert(entries, {
                    rank = i,
                    userId = item.userId,
                    nickname = "",
                    damage = dmg,
                    className = className,
                })
                table.insert(userIds, item.userId)
                if item.userId == myUserId then
                    myRank = { rank = i, damage = dmg }
                end
            end

            if #userIds == 0 then
                GS.dihataRevengeRankLoading = false
                GS.dihataRevengeRankData = { entries = entries, myRank = myRank }
                return
            end

            -- 查询昵称
            GetUserNickname({
                userIds = userIds,
                onSuccess = function(nicknames)
                    local map = {}
                    for _, info in ipairs(nicknames) do
                        map[info.userId] = info.nickname or ""
                    end
                    for _, entry in ipairs(entries) do
                        entry.nickname = map[entry.userId] or ("ID:" .. tostring(entry.userId))
                    end
                    GS.dihataRevengeRankLoading = false
                    GS.dihataRevengeRankData = { entries = entries, myRank = myRank }
                end,
                onError = function(errorCode)
                    for _, entry in ipairs(entries) do
                        entry.nickname = "ID:" .. tostring(entry.userId)
                    end
                    GS.dihataRevengeRankLoading = false
                    GS.dihataRevengeRankData = { entries = entries, myRank = myRank }
                end
            })
        end,
        error = function(code, reason)
            GS.dihataRevengeRankLoading = false
            GS.dihataRevengeRankData = { entries = {}, myRank = nil }
            print("[迪哈塔排名] 拉取排行榜失败:", code, reason)
        end
    }, "dihata_rev_class")
end

--- 家中与伴侣交谈（点击伴侣后触发）
---@param npcKey string NPC标识
function M._startHomePartnerTalk(npcKey)
    local DialogueManager = require("DialogueManager")
    local npcInfo = GS.NPC_REGISTRY[npcKey]
    if not npcInfo then return end

    local speaker = npcInfo.name
    local petName = GS.getNPCPetName(npcKey)
    local greetText = speaker .. "\u{ff1a}" .. petName .. "\u{3002}"

    -- 如果伴侣正在睡觉，暂时切换为 idle（取消睡眠动画），交谈结束后恢复
    if GS.homeNpc and GS.homeNpc.state == "sleeping" then
        GS._partnerWasSleeping = true
        GS.homeNpc.state = "idle"
    else
        GS._partnerWasSleeping = nil
    end

    -- 激活家中伴侣对话状态（让对话框渲染 + 锁定输入）
    GS.homePartnerTalkActive = true
    GS.eventInputLocked = true

    DialogueManager.startDynamic({
        {
            speaker = speaker, text = greetText,
            choices = {
                "我想你这样叫我\u{2026}\u{2026}",
                "\u{ff08}\u{4eb2}\u{543b}\u{5979}\u{ff09}",
                "\u{ff08}\u{62b1}\u{4f4f}\u{5979}\u{ff09}",
                "我想送你\u{2026}\u{2026}",
                "没什么",
            },
            onChoice = function(idx)
                if idx == 1 then
                    -- 弹出爱称输入框（对话保持，输入框覆盖在上层）
                    GS.petNameInput = {
                        active = true,
                        text = "",
                        placeholder = "请输入爱称...",
                        confirmed = false,
                        npcKey = npcKey,
                    }
                    -- 启用文本输入（桌面端激活 IME，移动端弹出软键盘）
                    input:SetScreenKeyboardVisible(true)
                elseif idx == 2 then
                    -- 亲吻她 → 播放两句文本，第二句出现时每日首次+3好感度
                    local kissLines = {
                        {
                            speaker = "旁白",
                            text = "\u{ff08}\u{4f60}\u{4eb2}\u{4e86}" .. speaker .. "\u{ff0c}\u{5979}\u{56de}\u{5e94}\u{7740}\u{4f60}\u{2026}\u{2026}\u{ff09}",
                        },
                        {
                            speaker = speaker,
                            text = "\u{2026}\u{2026}" .. petName .. "\u{ff0c}\u{6211}\u{7231}\u{4f60}\u{3002}",
                            onShow = function()
                                local gameDay = math.floor(((GS.weatherTime or 1) - 1) / 1440)
                                if GS.homeKissDate ~= gameDay then
                                    GS.homeKissDate = gameDay
                                    GS.changeAffinity(npcKey, 3)
                                end
                            end,
                        },
                    }
                    DialogueManager.startDynamic(kissLines, function()
                        closeHomePartnerTalk()
                    end)
                elseif idx == 3 then
                    -- 抱住她 → 黑屏 → 播放5句文本 → 淡出 → 时间推进1小时
                    -- 好感度分两次：第2句+2，第4句+3，各每日限1次
                    local hugLines = {
                        { speaker = "旁白", text = "\u{ff08}\u{4f60}\u{7528}\u{53cc}\u{81c2}\u{73af}\u{62b1}\u{4f4f}\u{4e86}" .. speaker .. "\u{ff0c}\u{5979}\u{8f6c}\u{8eab}\u{4e5f}\u{62b1}\u{4f4f}\u{4e86}\u{4f60}\u{3002}\u{ff09}" },
                        { speaker = speaker, text = "\u{2026}\u{2026}\u{55ef}\u{ff0c}" .. petName .. "\u{ff0c}\u{6765}\u{5427}\u{2026}\u{2026}",
                            onShow = function()
                                local gameDay = math.floor(((GS.weatherTime or 1) - 1) / 1440)
                                if GS.homeHugDate ~= gameDay then
                                    GS.homeHugDate = gameDay
                                    GS.changeAffinity(npcKey, 2)
                                end
                            end,
                        },
                        { speaker = "旁白", text = "\u{ff08}\u{4f60}\u{548c}" .. speaker .. "\u{5ea6}\u{8fc7}\u{4e86}\u{4e00}\u{6bb5}\u{65f6}\u{95f4}\u{2026}\u{2026}\u{ff09}" },
                        { speaker = speaker, text = "\u{2026}\u{2026}" .. petName .. "\u{ff0c}" .. ({
                            guild_master       = "\u{6211}\u{4f1a}\u{4e00}\u{76f4}\u{966a}\u{5728}\u{4f60}\u{8eab}\u{8fb9}\u{7684}\u{3002}",
                            guild_receptionist = "\u{4f60}\u{4f1a}\u{7231}\u{6211}\u{4e00}\u{8f88}\u{5b50}\u{5417}\u{ff1f}\u{4f1a}\u{5417}\u{ff1f}",
                            jewelry_shop_owner = "\u{6211}\u{597d}\u{7231}\u{4f60}\u{ff0c}\u{4f60}\u{5462}\u{ff1f}\u{4f60}\u{7231}\u{6211}\u{5417}\u{ff1f}",
                            potion_shop_owner  = "\u{5373}\u{4f7f}\u{5c06}\u{6765}\u{4f60}\u{8981}\u{79bb}\u{5f00}\u{ff0c}\u{6211}\u{4e5f}\u{4f1a}\u{73cd}\u{89c6}\u{8fd9}\u{6bb5}\u{56de}\u{5fc6}\u{7684}\u{3002}",
                            tavern_keeper      = "\u{8bf4}\u{4f60}\u{7231}\u{6211}\u{3002}\u{4f60}\u{8981}\u{8bf4}\u{2026}\u{2026}\u{7231}\u{6211}\u{3002}",
                            tavern_dancer      = "\u{7b54}\u{5e94}\u{6211}\u{ff0c}\u{6c38}\u{8fdc}\u{4e0d}\u{4f1a}\u{79bb}\u{5f00}\u{6211}\u{ff0c}\u{4e0d}\u{8981}\u{8ba9}\u{6211}\u{518d}\u{53d8}\u{6210}\u{4e00}\u{4e2a}\u{4eba}\u{3002}",
                            forest_elf         = "\u{6211}\u{5bb3}\u{6015}\u{5931}\u{53bb}\u{4f60}\u{ff0c}\u{6240}\u{4ee5}\u{ff0c}\u{6211}\u{4f1a}\u{73cd}\u{60dc}\u{73b0}\u{5728}\u{7684}\u{6bcf}\u{4e00}\u{523b}\u{3002}",
                        })[npcKey] or "\u{8bf4}\u{4f60}\u{7231}\u{6211}\u{3002}\u{4f60}\u{8981}\u{8bf4}\u{2026}\u{2026}\u{7231}\u{6211}\u{3002}",
                            onShow = function()
                                local gameDay = math.floor(((GS.weatherTime or 1) - 1) / 1440)
                                if GS.homeHugDate2 ~= gameDay then
                                    GS.homeHugDate2 = gameDay
                                    GS.changeAffinity(npcKey, 3)
                                end
                            end,
                        },
                        { speaker = "旁白", text = "\u{ff08}" .. speaker .. "\u{7684}\u{8138}\u{988a}\u{7ea2}\u{5f64}\u{5f64}\u{7684}\u{ff0c}\u{800c}\u{4f60}\u{611f}\u{5230}\u{7cbe}\u{795e}\u{6296}\u{64de}\u{3002}\u{ff09}" },
                    }
                    BoardOverlay._fadeAlpha = BoardOverlay._fadeAlpha or 0
                    BoardOverlay._fadeSpeed = 300
                    BoardOverlay._fadeTarget = 255
                    BoardOverlay._kissSceneActive = true
                    BoardOverlay._fadeDoneCallback = function()
                        DialogueManager.startDynamic(hugLines, function()
                            -- 时间推进1小时（60分钟）
                            GS.tickWeatherTime(60)
                            -- 赋予"精神抖擞"BUFF：全属性+1，持续24小时（1440分钟）
                            GS.hugBuff = { active = true, expireTime = GS.weatherTime + 1440 }
                            GS.recalcStats(GS.player)
                            -- 淡出黑屏
                            BoardOverlay._fadeSpeed = 300
                            BoardOverlay._fadeTarget = 0
                            BoardOverlay._fadeDoneCallback = function()
                                BoardOverlay._kissSceneActive = nil
                                closeHomePartnerTalk()
                            end
                        end)
                    end
                elseif idx == 4 then
                    -- 我想送你…… → 进入送礼模式（先解除对话锁定）
                    GS.homePartnerTalkActive = false
                    GS.eventInputLocked = false
                    DialogueManager._dynamicOnComplete = nil
                    DialogueManager.finish()
                    GS.giftMode = true
                    GS.giftNpcKey = npcKey
                    GS.giftNpcName = speaker
                    GS.giftBuildingKey = nil
                    GS.giftFromHome = true
                    GS.giftSlotItem = nil
                    GS.giftSlotSource = nil
                    GS.giftSlotSourceId = nil
                    GS.giftResultText = nil
                    GS.giftResultLiked = nil
                    GS.invOpen = true
                else
                    -- 没什么 → 结束对话
                    closeHomePartnerTalk()
                    DialogueManager.finish()
                end
            end,
        },
    }, function()
        -- onComplete：对话自然结束时也清理状态
        closeHomePartnerTalk()
    end)
end

--- 触发 NPC 交谈问答（可从外部调用，用于赠送完成后回到交谈）
---@param buildingKey string 建筑标识（如 "blacksmith"）
local function triggerNpcTalk(buildingKey)
    local TalkQA = require("data.TalkQA")
    local DialogueManager = require("DialogueManager")
    local qaData = TalkQA[buildingKey]
    if not qaData then return end

    local level = GS.getNPCFavorLevel(qaData.npcKey)
    local respText = (level == 0) and "……" or (qaData.response[level] or qaData.response[1] or "……")
    local pName = GS.charName or ""
    local function replP(s)
        return replaceDialogueTags(s, qaData.npcKey)
    end
    if not GS.talkQAAsked then GS.talkQAAsked = {} end

    local function startQA()
        local questions = {}
        local idxMap = {}
        local lastItem = nil
        local lastOrigIdx = nil
        -- 统计是否还有未问完的普通选项
        local hasNormalOptions = false
        for i, item in ipairs(qaData.qa) do
            if item.a == nil then
                -- 退出选项（如"（离开）"）始终可用，不受 talkQAAsked 过滤
                lastItem = item
                lastOrigIdx = i
            else
                local qaKey = buildingKey .. "_" .. i
                -- 条件选项：condition 返回 false 时不显示
                if item.condition and not item.condition(GS) then
                    -- 条件不满足，跳过
                -- 所有选过的选项都不再出现（除了持久选项由下方单独插入）
                elseif not GS.talkQAAsked[qaKey] then
                    questions[#questions + 1] = replP(item.q)
                    idxMap[#questions] = i
                    hasNormalOptions = true
                end
            end
        end

        -- 当所有普通选项都已问完，插入"（闲聊）"（第一个位置）
        local chatIdx = nil
        local confessIdx = nil
        if not hasNormalOptions then
            -- 在最前面插入"（闲聊）"
            table.insert(questions, 1, "（闲聊）")
            chatIdx = 1
            -- idxMap 索引需要顺移（当前 questions 为空所以不需要）
        end

        -- 当该 NPC 是伴侣时，在闲聊后面插入"（亲吻她）"
        local kissIdx = nil
        if not hasNormalOptions and qaData.npcKey and GS.partnerNpcKey == qaData.npcKey
           and KISS_TEXTS[qaData.npcKey] then
            questions[#questions + 1] = "（亲吻她）"
            kissIdx = #questions
        end

        -- 插入"我想送你……"选项
        local giftIdx = nil
        if qaData.npcKey then
            questions[#questions + 1] = "我想送你……"
            giftIdx = #questions
        end

        -- 当所有普通选项都已问完，插入"（告白）"或"（求婚）"
        -- 迪芬和斯特朗没有告白选项
        if not hasNormalOptions and qaData.npcKey and not NO_CONFESS_NPCS[qaData.npcKey] then
            if GS.partnerNpcKey == qaData.npcKey then
                -- 已是伴侣 → 未求婚时显示"（求婚）"
                if not GS.partnerLivingTogether then
                    questions[#questions + 1] = "（求婚）"
                    confessIdx = #questions
                end
            else
                questions[#questions + 1] = "（告白）"
                confessIdx = #questions
            end
        end

        -- 最后放"没什么了"
        if lastItem then
            questions[#questions + 1] = replP(lastItem.q)
            idxMap[#questions] = lastOrigIdx
        end

        -------------------------------------------------------
        -- NPC 任务选项注入（排在所有选项最前面）
        -------------------------------------------------------
        local QuestManager = require("QuestManager")
        QuestManager.update()  -- 刷新任务状态，确保已达成目标的任务能正确显示提交选项
        local questOpts = {}  -- { text, badge, questId, def }

        -- 可提交的任务（蓝色五角星 badge）优先
        local submitQuests = QuestManager.getNpcSubmitQuests(buildingKey)
        for _, sq in ipairs(submitQuests) do
            questOpts[#questOpts + 1] = {
                text  = sq.def.name or "提交任务",
                badge = "submit",
                questId = sq.questId,
                def   = sq.def,
            }
        end

        -- 可接取的任务（蓝色感叹号 badge）
        local triggerQuests = QuestManager.getNpcTriggerQuests(buildingKey)
        for _, tq in ipairs(triggerQuests) do
            questOpts[#questOpts + 1] = {
                text  = tq.def.name or "接取任务",
                badge = "accept",
                questId = tq.questId,
                def   = tq.def,
            }
        end

        local questCount = #questOpts
        local questChoiceMap = {}  -- idx → questOpt entry

        if questCount > 0 then
            -- 偏移已有的特殊索引
            if chatIdx then chatIdx = chatIdx + questCount end
            if kissIdx then kissIdx = kissIdx + questCount end
            if giftIdx then giftIdx = giftIdx + questCount end
            if confessIdx then confessIdx = confessIdx + questCount end
            -- 偏移 idxMap（原地重建）
            local savedMap = {}
            for k, v in pairs(idxMap) do savedMap[k] = v; idxMap[k] = nil end
            for k, v in pairs(savedMap) do idxMap[k + questCount] = v end
            -- 在 questions 最前面插入任务选项（倒序插入保持顺序）
            for i = questCount, 1, -1 do
                table.insert(questions, 1, questOpts[i].text)
            end
            -- 构建任务选项映射
            for i, qo in ipairs(questOpts) do
                questChoiceMap[i] = qo
            end
            -- 存储 badge 信息供渲染器使用（含任务类型）
            GS._choiceBadges = {}
            for i, qo in ipairs(questOpts) do
                GS._choiceBadges[i] = {
                    type = qo.badge,                         -- "accept" | "submit"
                    category = qo.def and qo.def.category,   -- "main" | "side"
                }
            end
        else
            GS._choiceBadges = nil
        end

        DialogueManager.startDynamic({
            {
                speaker = qaData.speaker, text = respText,
                choices = questions,
                onChoice = function(idx)
                    -- NPC 任务选项
                    if questChoiceMap[idx] then
                        local qo = questChoiceMap[idx]
                        if qo.badge == "accept" then
                            -- 接取任务
                            QuestManager.tryNpcTrigger(buildingKey, qo.questId)
                            -- 接取后检查：如果 checkDone=true 导致任务已变成 READY，
                            -- 则在本次对话中直接完成并发放奖励（避免玩家需要二次交互）
                            local stAfter = QuestManager.questStates[qo.questId]
                            local instantReady = stAfter and stAfter.status == QuestManager.STATUS_READY
                            if instantReady and qo.def.rewardAtLine ~= nil then
                                QuestManager.tryNpcSubmitDeferred(buildingKey, qo.questId)
                            end
                            local dlgLines = flattenDialogue(qo.def.acceptDialogue, replP)
                            local afterDlg = function()
                                GS.saveToCloud()
                                startQA()
                            end
                            if instantReady and qo.def.rewardAtLine ~= nil and #dlgLines > 0 then
                                afterDlg = injectRewardCallback(dlgLines, qo.questId, qo.def.rewardAtLine, afterDlg)
                            end
                            if #dlgLines > 0 then
                                DialogueManager.startDynamic(dlgLines, afterDlg)
                            else
                                if instantReady and qo.def.rewardAtLine ~= nil then
                                    QuestManager._doGiveRewards(qo.questId)
                                end
                                GS.saveToCloud()
                                startQA()
                            end
                        elseif qo.badge == "submit" then
                            local needDragDrop = qo.def.requireItems or qo.def.requireItemFilter
                            if needDragDrop then
                                -- 进入物品提交 UI（拖拽式提交）
                                DialogueManager._dynamicOnComplete = nil
                                DialogueManager.finish()
                                GS.questSubmitMode = true
                                GS.questSubmitQuestId = qo.questId
                                GS.questSubmitDef = qo.def
                                GS.questSubmitNpcName = qaData.speaker
                                GS.questSubmitBuildingKey = buildingKey
                                GS.questSubmitSlotItem = nil
                                GS.questSubmitSlotSource = nil
                                GS.questSubmitSlotSourceId = nil
                                GS.questSubmitRejectMsg = nil
                            else
                                -- 无物品提交：直接对话完成
                                local ral = qo.def.rewardAtLine
                                if ral ~= nil then
                                    -- 延迟发放模式：先完成任务（不发奖励），对话中再发
                                    QuestManager.tryNpcSubmitDeferred(buildingKey, qo.questId)
                                else
                                    -- 原有模式：立即完成并发放奖励
                                    QuestManager.tryNpcSubmit(buildingKey, qo.questId)
                                end
                                local dlgLines = flattenDialogue(qo.def.submitDialogue, function(t)
                                    return replaceDialogueTags(t, qaData.npcKey)
                                end)
                                local afterDlg = function()
                                    GS.saveToCloud()
                                    startQA()
                                end
                                if ral ~= nil and #dlgLines > 0 then
                                    afterDlg = injectRewardCallback(dlgLines, qo.questId, ral, afterDlg)
                                end
                                if #dlgLines > 0 then
                                    DialogueManager.startDynamic(dlgLines, afterDlg)
                                else
                                    if ral ~= nil then
                                        QuestManager._doGiveRewards(qo.questId)
                                    end
                                    GS.saveToCloud()
                                    startQA()
                                end
                            end
                        end
                        return
                    end
                    -- 闲聊
                    if idx == chatIdx then
                        local chatText
                        if level <= 0 then
                            chatText = "（" .. qaData.speaker .. "皱着眉头，似乎无意和你多说什么，只简单说了几句就借机离开了。）"
                        else
                            chatText = "（你和" .. qaData.speaker .. "闲聊了一阵子……交谈万岁。）"
                        end
                        local chatLines = splitLongText(chatText, "旁白")
                        DialogueManager.startDynamic(chatLines, startQA)
                        return
                    end
                    -- 亲吻
                    if idx == kissIdx then
                        local kissData = KISS_TEXTS[qaData.npcKey]
                        local favorLevel = GS.getNPCFavorLevel(qaData.npcKey)
                        -- 选择对应好感度的文本（≥7 挚爱用 devoted，否则用 adore）
                        local lines = (favorLevel >= 7 and kissData.devoted) or kissData.adore
                        -- 替换占位符，并在NPC第一次说话的行上挂好感度回调
                        local kissLines = {}
                        local affinityAttached = false
                        for _, l in ipairs(lines) do
                            local entry = { speaker = replP(l.speaker), text = replP(l.text) }
                            -- 好感度标记挂在第一个非旁白行的 onShow 上
                            if not affinityAttached and l.speaker ~= "旁白" then
                                affinityAttached = true
                                local nk = qaData.npcKey
                                local delta = kissData.delta or 3
                                entry.onShow = function()
                                    local gd = math.floor(((GS.weatherTime or 1) - 1) / 1440)
                                    if GS.npcKissAffinityDate[nk] ~= gd then
                                        GS.npcKissAffinityDate[nk] = gd
                                        GS.changeAffinity(nk, delta)
                                    end
                                end
                            end
                            kissLines[#kissLines + 1] = entry
                        end
                        -- 先淡入黑屏，黑屏后播放对话，对话结束后淡出
                        BoardOverlay._fadeAlpha = BoardOverlay._fadeAlpha or 0
                        BoardOverlay._fadeSpeed = 300
                        BoardOverlay._fadeTarget = 255
                        BoardOverlay._kissSceneActive = true  -- 让对话框在黑屏上方显示
                        BoardOverlay._fadeDoneCallback = function()
                            -- 黑屏完成，播放亲吻对话
                            DialogueManager.startDynamic(kissLines, function()
                                -- 对话结束，淡出黑屏
                                BoardOverlay._fadeSpeed = 300
                                BoardOverlay._fadeTarget = 0
                                BoardOverlay._fadeDoneCallback = function()
                                    -- 淡出完成，清除标记，保存并回到对话选项
                                    BoardOverlay._kissSceneActive = nil
                                    GS.saveToCloud()
                                    startQA()
                                end
                            end)
                        end
                        return
                    end
                    -- 告白 / 求婚
                    if idx == confessIdx then
                        if GS.partnerNpcKey == qaData.npcKey then
                            -- 求婚（判断顺序：家园 → 戒指 → 挚爱）
                            if GS.homeType ~= "large" then
                                -- 没有大型家园
                                local noHomeText = "（话到嘴边，你还是没有开口，只因你想到自己家里连一张双人床都没有。）"
                                local noHomeLines = splitLongText(noHomeText, "旁白")
                                DialogueManager.startDynamic(noHomeLines, startQA)
                            elseif GS.countInventoryItem("oath_ring") <= 0 then
                                -- 没有誓约戒指
                                local noRingText = "（要求婚的话，至少需要准备一枚求婚戒指吧，听说\"广告机\"的奖池里有一枚漂亮的戒指，去看看吧！）"
                                local noRingLines = splitLongText(noRingText, "旁白")
                                DialogueManager.startDynamic(noRingLines, startQA)
                            else
                                -- 有大型家园 + 有戒指 → 发起求婚
                                local proposalData = PROPOSAL_TEXTS[qaData.npcKey]
                                local favorLevel = GS.getNPCFavorLevel(qaData.npcKey)
                                if favorLevel >= 7 and proposalData then
                                    -- 挚爱 → 同意
                                    local entry = proposalData.accept
                                    local propText = replP(entry.text)
                                    local propLines = splitLongText(propText, qaData.speaker)
                                    -- 每日求婚好感度限制（每NPC每天一次）
                                    local gd = math.floor(((GS.weatherTime or 1) - 1) / 1440)
                                    if GS.npcProposalAffinityDate[qaData.npcKey] ~= gd then
                                        GS.npcProposalAffinityDate[qaData.npcKey] = gd
                                        GS.changeAffinity(qaData.npcKey, entry.delta)
                                    end
                                    -- 消耗誓约戒指
                                    GS.removeInventoryItem("oath_ring", 1)
                                    -- 标记求婚成功（同住）
                                    GS.partnerLivingTogether = true
                                    -- 对话结束后弹出"她说她愿意"弹窗
                                    DialogueManager.startDynamic(propLines, function()
                                        GS.proposalSuccessPopup = true
                                        GS.saveToCloud()
                                    end)
                                else
                                    -- 未达挚爱 → 拒绝
                                    local entry = proposalData and proposalData.decline
                                    if entry then
                                        local propText = replP(entry.text)
                                        local propLines = splitLongText(propText, qaData.speaker)
                                        -- 每日求婚好感度限制（每NPC每天一次，与同意共享）
                                        local gd = math.floor(((GS.weatherTime or 1) - 1) / 1440)
                                        if GS.npcProposalAffinityDate[qaData.npcKey] ~= gd then
                                            GS.npcProposalAffinityDate[qaData.npcKey] = gd
                                            GS.changeAffinity(qaData.npcKey, entry.delta)
                                        end
                                        DialogueManager.startDynamic(propLines, startQA)
                                    else
                                        DialogueManager.startDynamic(splitLongText("……", qaData.speaker), startQA)
                                    end
                                end
                            end
                        else
                            -- 告白：先弹出确认框
                            GS.confessConfirmPopup = {
                                npcName = qaData.speaker,
                                action  = function()
                                    local npcTexts = CONFESS_TEXTS[qaData.npcKey]
                                    local favorLevel = math.max(1, GS.getNPCFavorLevel(qaData.npcKey))
                                    local textIdx = favorLevel
                                    if GS.partnerNpcKey and GS.partnerNpcKey ~= qaData.npcKey then
                                        textIdx = 7
                                    end
                                    local entry = npcTexts and npcTexts[textIdx]
                                    if entry then
                                        local confText = replP(entry.text)
                                        local confLines = splitLongText(confText, qaData.speaker)
                                        if entry.delta and entry.delta ~= 0 then
                                            local gd = math.floor(((GS.weatherTime or 1) - 1) / 1440)
                                            if GS.npcConfessAffinityDate[qaData.npcKey] ~= gd then
                                                GS.npcConfessAffinityDate[qaData.npcKey] = gd
                                                GS.changeAffinity(qaData.npcKey, entry.delta)
                                            end
                                        end
                                        if favorLevel >= 6 and not GS.partnerNpcKey then
                                            GS.partnerNpcKey = qaData.npcKey
                                        end
                                        DialogueManager.startDynamic(confLines, startQA)
                                    else
                                        local defaultLines = splitLongText("……", qaData.speaker)
                                        DialogueManager.startDynamic(defaultLines, startQA)
                                    end
                                end
                            }
                            return
                        end
                        return
                    end
                    -- 送礼
                    if idx == giftIdx then
                        DialogueManager._dynamicOnComplete = nil
                        DialogueManager.finish()
                        GS.giftMode = true
                        GS.giftNpcKey = qaData.npcKey
                        GS.giftNpcName = qaData.speaker
                        GS.giftBuildingKey = buildingKey
                        GS.giftSlotItem = nil
                        GS.giftSlotSource = nil
                        GS.giftSlotSourceId = nil
                        GS.giftResultText = nil
                        GS.giftResultLiked = nil
                        GS.invOpen = true
                        return
                    end
                    local origIdx = idxMap[idx]
                    local chosen = qaData.qa[origIdx]
                    if chosen and chosen.a then
                        -- 所有选项选过后都标记为已问（一次性消失）
                        GS.talkQAAsked[buildingKey .. "_" .. origIdx] = true
                        if chosen.onAnswer then
                            chosen.onAnswer(GS)
                        end
                        local ansText = replP(chosen.a)
                        local ansLines = splitLongText(ansText, qaData.speaker)
                        DialogueManager.startDynamic(ansLines, startQA)
                    else
                        DialogueManager._dynamicOnComplete = nil
                        DialogueManager.finish()
                    end
                end,
            },
        })
    end
    startQA()
end

-- ====================================================================
-- 鼠标按下
-- ====================================================================
function M.handleMouseDown(eventType, eventData)
    -- 应用层超时检查：如果网络回调超过 3 秒未返回，强制解锁按钮
    _tryNetTimeout()

    local button = eventData["Button"]:GetInt()

    local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
    local my = eventData["Y"]:GetInt() / GS.dpr / GS.S

    -- 求婚成功弹窗：点击确定按钮关闭
    if GS.proposalSuccessPopup then
        if button == MOUSEB_LEFT then
            local cr = GS.proposalSuccessOkRect
            if cr and hitTest(mx, my, cr) then
                GS.proposalSuccessPopup = false
            end
        end
        return  -- 弹窗显示期间屏蔽所有其他输入
    end

    -- 洗点弹窗点击
    if GS.respecPopupVisible then
        if button == MOUSEB_LEFT then
            -- 选择素质
            if GS.respecStatsRect and hitTest(mx, my, GS.respecStatsRect) then
                GS.respecPopupChoice = "stats"
            -- 选择技能
            elseif GS.respecSkillsRect and hitTest(mx, my, GS.respecSkillsRect) then
                GS.respecPopupChoice = "skills"
            -- 确定按钮
            elseif GS.respecPopupChoice and GS.respecConfirmRect and hitTest(mx, my, GS.respecConfirmRect) then
                local respecType = GS.respecPopupChoice
                GS.respecPopupVisible = false
                GS.respecPopupChoice = nil
                -- 免广告用户：直接洗点
                if GS.adFree then
                    DialogueManager = require("DialogueManager")
                    if respecType == "stats" then
                        local p = GS.player
                        for k, _ in pairs(p.stats) do p.stats[k] = 1 end
                        p.statPoints = p.level * 3
                        GS.recalcStats(p)
                        if p.hp > p.maxHp then p.hp = p.maxHp end
                        if p.mp > p.maxMp then p.mp = p.maxMp end
                        DialogueManager.startDynamic({
                            { speaker = "旁白", text = "（机器闪烁着光芒……你感觉身体中的力量被重新归拢！属性点已全部重置。）" },
                        })
                    elseif respecType == "skills" then
                        GS.skillLevels = {}
                        GS.skillPoints = GS.player.level
                        GS.activeSkills = {}
                        GS.skillCooldowns = {}
                        for i = #GS.companions, 1, -1 do
                            if GS.companions[i].isHound then table.remove(GS.companions, i) end
                        end
                        GS.homeHound = nil
                        DialogueManager.startDynamic({
                            { speaker = "旁白", text = "（机器闪烁着光芒……你感觉脑中的技艺被重新梳理！技能点已全部重置。）" },
                        })
                    end
                    print("[AdFree] 免广告用户，直接洗点完成")
                    return
                end
                -- PC端不支持广告
                if PlatformUtils.IsDesktopPlatform() then
                    local DM = require("DialogueManager")
                    DM.startDynamic({ { speaker = "旁白", text = "（通过这个叫做台式电脑的设备无法传输力量……）" } })
                    return
                end
                -- 播放广告
                GS.adLoading = true
                GS.adSessionId = GS.adSessionId + 1
                local thisSession = GS.adSessionId
                MonitorPanel.reportAdClick()
                sdk:ShowRewardVideoAd(function(result)
                    if result.success then
                        -- 广告确实看完，无论游戏状态如何都发放奖励
                        GS.adLoading = false
                        GS.adCancelRect = nil
                        MonitorPanel.reportAdSuccess()
                        DialogueManager = require("DialogueManager")
                        if respecType == "stats" then
                            -- 重置属性点
                            local p = GS.player
                            for k, _ in pairs(p.stats) do
                                p.stats[k] = 1
                            end
                            p.statPoints = p.level * 3
                            GS.recalcStats(p)
                            if p.hp > p.maxHp then p.hp = p.maxHp end
                            if p.mp > p.maxMp then p.mp = p.maxMp end
                            DialogueManager.startDynamic({
                                { speaker = "旁白", text = "（机器闪烁着光芒……你感觉身体中的力量被重新归拢！属性点已全部重置。）" },
                            })
                        elseif respecType == "skills" then
                            -- 重置技能点
                            GS.skillLevels = {}
                            GS.skillPoints = GS.player.level
                            GS.activeSkills = {}
                            GS.skillCooldowns = {}
                            -- 清除猎犬
                            for i = #GS.companions, 1, -1 do
                                if GS.companions[i].isHound then
                                    table.remove(GS.companions, i)
                                end
                            end
                            GS.homeHound = nil
                            DialogueManager.startDynamic({
                                { speaker = "旁白", text = "（机器闪烁着光芒……你感觉脑中的技艺被重新梳理！技能点已全部重置。）" },
                            })
                        end
                    else
                        -- 广告未完成，检查状态避免过期回调弹出多余提示
                        if thisSession ~= GS.adSessionId then return end
                        if not GS.adLoading then return end
                        GS.adLoading = false
                        GS.adCancelRect = nil
                        MonitorPanel.reportAdFail()
                        DialogueManager = require("DialogueManager")
                        DialogueManager.startDynamic({
                            { speaker = "旁白", text = "（传输中断了……洗点未能完成。）" },
                        })
                    end
                end)
            -- 取消按钮
            elseif GS.respecCancelRect and hitTest(mx, my, GS.respecCancelRect) then
                GS.respecPopupVisible = false
                GS.respecPopupChoice = nil
            end
        end
        return  -- 弹窗显示期间屏蔽所有其他输入
    end

    -- 签到面板点击
    if button == MOUSEB_LEFT then
        if SignInSystem.handleClick(mx, my) then return end
    end

    -- 史莱姆国王大反击：排名面板点击处理
    if GS.slimeRevengeRankPanel and button == MOUSEB_LEFT then
        -- 关闭按钮
        local cbr = GS._slimeRankCloseBtnRect
        if cbr and hitTest(mx, my, cbr) then
            GS.slimeRevengeRankPanel = false
            return
        end
        -- Tab 切换
        if GS._slimeRankTabRects then
            for i, tr in ipairs(GS._slimeRankTabRects) do
                if hitTest(mx, my, tr) then
                    local newTab = i - 1  -- 0-based
                    if newTab ~= GS.slimeRevengeRankTab then
                        GS.slimeRevengeRankTab = newTab
                        GS.slimeRevengeRankScroll = 0
                        M._loadSlimeRevengeRankData(newTab)
                    end
                    return
                end
            end
        end
        -- 列表区域：启动滚动拖拽
        local lr = GS._slimeRankListRect
        if lr and hitTest(mx, my, lr) then
            GS._slimeRankDragging = true
            GS._slimeRankDragStartY = my
            GS._slimeRankDragStartScroll = GS.slimeRevengeRankScroll or 0
            return
        end
        -- 面板内其他区域：拦截
        local pr = GS._slimeRankPanelRect
        if pr and hitTest(mx, my, pr) then
            return
        end
        -- 面板外点击：关闭
        GS.slimeRevengeRankPanel = false
        return
    end

    -- 史莱姆国王大反击：奖励面板点击处理
    if GS.slimeRevengeRewardPanel and button == MOUSEB_LEFT then
        -- 关闭按钮
        local cbr = GS._slimeRewardCloseBtnRect
        if cbr and hitTest(mx, my, cbr) then
            GS.slimeRevengeRewardPanel = false
            if GS.tooltipSource == "reward_preview" then
                GS.tooltipItem = nil
                GS.tooltipPinned = false
                GS.tooltipPinnedPos = nil
            end
            return
        end
        -- 领取按钮
        if GS._slimeRewardClaimRects then
            for idx, rect in pairs(GS._slimeRewardClaimRects) do
                if hitTest(mx, my, rect) then
                    -- 云端已领取数据未加载成功时拒绝领取
                    if not GS._slimeRevengeRewardLoaded then
                        GS.mapTipText = "奖励数据加载中，请稍后再试"
                        GS.mapTipTimer = 2.0
                        return
                    end
                    local entry = GS.SLIME_REVENGE_REWARDS[idx]
                    if entry then
                        -- 发放奖励到背包
                        GS.addToInventory(entry.itemId, entry.qty)
                        -- 标记为已领取
                        GS.slimeRevengeRewardClaimed[idx] = true
                        -- 序列化已领取索引并保存到云端
                        local parts = {}
                        for k, _ in pairs(GS.slimeRevengeRewardClaimed) do
                            parts[#parts + 1] = tostring(k)
                        end
                        local claimedStr = table.concat(parts, ",")
                        if clientCloud then
                            clientCloud:Set("slime_rev_claimed", claimedStr, {
                                ok = function()
                                    print("[大反击奖励] 领取保存成功: " .. claimedStr)
                                end,
                                error = function(code, reason)
                                    print("[大反击奖励] 领取保存失败: " .. tostring(code) .. " " .. tostring(reason))
                                end,
                            })
                        end
                        -- 提示
                        local tpl = GS.itemTemplates and GS.itemTemplates[entry.itemId]
                        local itemName = tpl and tpl.name or entry.itemId
                        GS.mapTipText = "已领取: " .. itemName .. (entry.qty > 1 and ("×" .. entry.qty) or "")
                        GS.mapTipTimer = 2.0
                    end
                    return
                end
            end
        end
        -- 列表区域内：启动滚动拖拽 + 记录待点击图标
        local lr = GS._slimeRewardListRect
        if lr and hitTest(mx, my, lr) then
            -- 先关闭已打开的tooltip
            if GS.tooltipSource == "reward_preview" and GS.tooltipItem then
                GS.tooltipItem = nil
                GS.tooltipPinned = false
                GS.tooltipPinnedPos = nil
            end
            GS._slimeRewardDragging = true
            GS._slimeRewardDragStartY = my
            GS._slimeRewardDragStartScroll = GS.slimeRevengeRewardScroll or 0
            -- 只在点击图标区域时记录（mouseUp时判断是否为点击弹出tooltip）
            GS._slimeRewardPendingRow = nil
            if GS._slimeRewardRowRects then
                for idx, rr in pairs(GS._slimeRewardRowRects) do
                    if hitTest(mx, my, rr) then
                        GS._slimeRewardPendingRow = { idx = idx, itemId = rr.itemId, rect = rr }
                        break
                    end
                end
            end
            return
        end
        -- 面板内其他区域：拦截，不关闭
        local pr = GS._slimeRewardPanelRect
        if pr and hitTest(mx, my, pr) then
            return
        end
        -- 面板外点击：关闭面板
        GS.slimeRevengeRewardPanel = false
        if GS.tooltipSource == "reward_preview" then
            GS.tooltipItem = nil
            GS.tooltipPinned = false
            GS.tooltipPinnedPos = nil
        end
        return
    end

    -- 迪哈塔大反击：排名面板点击处理
    if GS.dihataRevengeRankPanel and button == MOUSEB_LEFT then
        -- 关闭按钮
        local cbr = GS._dihataRankCloseBtnRect
        if cbr and hitTest(mx, my, cbr) then
            GS.dihataRevengeRankPanel = false
            return
        end
        -- Tab 切换
        if GS._dihataRankTabRects then
            for i, tr in ipairs(GS._dihataRankTabRects) do
                if hitTest(mx, my, tr) then
                    local newTab = i - 1  -- 0-based
                    if newTab ~= GS.dihataRevengeRankTab then
                        GS.dihataRevengeRankTab = newTab
                        GS.dihataRevengeRankScroll = 0
                        M._loadDihataRevengeRankData(newTab)
                    end
                    return
                end
            end
        end
        -- 列表区域：启动滚动拖拽
        local lr = GS._dihataRankListRect
        if lr and hitTest(mx, my, lr) then
            GS._dihataRankDragging = true
            GS._dihataRankDragStartY = my
            GS._dihataRankDragStartScroll = GS.dihataRevengeRankScroll or 0
            return
        end
        -- 面板内其他区域：拦截
        local pr = GS._dihataRankPanelRect
        if pr and hitTest(mx, my, pr) then
            return
        end
        -- 面板外点击：关闭
        GS.dihataRevengeRankPanel = false
        return
    end

    -- 迪哈塔大反击：奖励面板点击处理
    if GS.dihataRevengeRewardPanel and button == MOUSEB_LEFT then
        -- 关闭按钮
        local cbr = GS._dihataRewardCloseBtnRect
        if cbr and hitTest(mx, my, cbr) then
            GS.dihataRevengeRewardPanel = false
            if GS.tooltipSource == "reward_preview" then
                GS.tooltipItem = nil
                GS.tooltipPinned = false
                GS.tooltipPinnedPos = nil
            end
            return
        end
        -- 领取按钮
        if GS._dihataRewardClaimRects then
            for idx, rect in pairs(GS._dihataRewardClaimRects) do
                if hitTest(mx, my, rect) then
                    -- 云端已领取数据未加载成功时拒绝领取
                    if not GS._dihataRevengeRewardLoaded then
                        GS.mapTipText = "奖励数据加载中，请稍后再试"
                        GS.mapTipTimer = 2.0
                        return
                    end
                    local entry = GS.DIHATA_REVENGE_REWARDS[idx]
                    if entry then
                        -- 发放奖励到背包
                        GS.addToInventory(entry.itemId, entry.qty)
                        -- 标记为已领取
                        GS.dihataRevengeRewardClaimed[idx] = true
                        -- 序列化已领取索引并保存到云端
                        local parts = {}
                        for k, _ in pairs(GS.dihataRevengeRewardClaimed) do
                            parts[#parts + 1] = tostring(k)
                        end
                        local claimedStr = table.concat(parts, ",")
                        if clientCloud then
                            clientCloud:Set("dihata_rev_claimed", claimedStr, {
                                ok = function()
                                    print("[迪哈塔奖励] 领取保存成功: " .. claimedStr)
                                end,
                                error = function(code, reason)
                                    print("[迪哈塔奖励] 领取保存失败: " .. tostring(code) .. " " .. tostring(reason))
                                end,
                            })
                        end
                        -- 提示
                        local tpl = GS.itemTemplates and GS.itemTemplates[entry.itemId]
                        local itemName = tpl and tpl.name or entry.itemId
                        GS.mapTipText = "已领取: " .. itemName .. (entry.qty > 1 and ("×" .. entry.qty) or "")
                        GS.mapTipTimer = 2.0
                    end
                    return
                end
            end
        end
        -- 列表区域内：启动滚动拖拽 + 记录待点击图标
        local lr = GS._dihataRewardListRect
        if lr and hitTest(mx, my, lr) then
            -- 先关闭已打开的tooltip
            if GS.tooltipSource == "reward_preview" and GS.tooltipItem then
                GS.tooltipItem = nil
                GS.tooltipPinned = false
                GS.tooltipPinnedPos = nil
            end
            GS._dihataRewardDragging = true
            GS._dihataRewardDragStartY = my
            GS._dihataRewardDragStartScroll = GS.dihataRevengeRewardScroll or 0
            -- 只在点击图标区域时记录（mouseUp时判断是否为点击弹出tooltip）
            GS._dihataRewardPendingRow = nil
            if GS._dihataRewardRowRects then
                for idx, rr in pairs(GS._dihataRewardRowRects) do
                    if hitTest(mx, my, rr) then
                        GS._dihataRewardPendingRow = { idx = idx, itemId = rr.itemId, rect = rr }
                        break
                    end
                end
            end
            return
        end
        -- 面板内其他区域：拦截，不关闭
        local pr = GS._dihataRewardPanelRect
        if pr and hitTest(mx, my, pr) then
            return
        end
        -- 面板外点击：关闭面板
        GS.dihataRevengeRewardPanel = false
        if GS.tooltipSource == "reward_preview" then
            GS.tooltipItem = nil
            GS.tooltipPinned = false
            GS.tooltipPinnedPos = nil
        end
        return
    end

    -- 改名输入框
    local ri = GS.renameInput
    if ri and ri.active then
        if button == MOUSEB_LEFT then
            -- 点击确定按钮
            local cr = GS._renameConfirmRect
            if cr and hitTest(mx, my, cr) then
                local txt = ri.text or ""
                if #txt > 0 then
                    GS.charName = txt
                    ri.active = false
                    GS.renameInput = nil
                    input:SetScreenKeyboardVisible(false)
                    GS.triggerAutoSave()
                    GS.shopBuyMsg = { text = "姓名已修改为: " .. txt, timer = 2.5, color = {140, 220, 100} }
                    print("[Input] Rename confirmed: " .. txt)
                end
                return
            end
            -- 点击取消按钮
            local ccr = GS._renameCancelRect
            if ccr and hitTest(mx, my, ccr) then
                ri.active = false
                GS.renameInput = nil
                input:SetScreenKeyboardVisible(false)
                return
            end
            -- 点击输入框区域：重新激活软键盘
            local ir = GS._renameInputRect
            if ir and hitTest(mx, my, ir) then
                input:SetScreenKeyboardVisible(true)
            end
        end
        return  -- 改名输入框显示期间屏蔽所有其他输入
    end

    -- 兑换码输入框
    local rci = GS.redeemCodeInput
    if rci and rci.active then
        if button == MOUSEB_LEFT then
            -- 点击确定按钮
            local cr = GS._redeemCodeConfirmRect
            if cr and hitTest(mx, my, cr) then
                local code = rci.text or ""
                if #code > 0 then
                    rci.active = false
                    input:SetScreenKeyboardVisible(false)
                    processRedeemCode(code)
                end
                return
            end
            -- 点击取消按钮
            local ccr = GS._redeemCodeCancelRect
            if ccr and hitTest(mx, my, ccr) then
                rci.active = false
                input:SetScreenKeyboardVisible(false)
                return
            end
            -- 点击输入框区域
            local ir = GS._redeemCodeInputRect
            if ir and hitTest(mx, my, ir) then
                input:SetScreenKeyboardVisible(true)
            end
        end
        return  -- 兑换码输入框显示期间屏蔽所有其他输入
    end

    -- 脱离卡死确认弹窗
    if GS._unstuckConfirmVisible then
        if button == MOUSEB_LEFT then
            -- 确认按钮
            if GS._unstuckConfirmBtnRect and hitTest(mx, my, GS._unstuckConfirmBtnRect) then
                GS._unstuckConfirmVisible = false
                local DM = require("Dungeon.DungeonManager")
                local ok, msg = DM.unstuck()
                if msg then
                    GS.floatingTexts = GS.floatingTexts or {}
                    table.insert(GS.floatingTexts, {
                        text = msg,
                        x = GS.player.x, y = GS.player.y,
                        color = ok and {255, 220, 100} or {255, 100, 100},
                        timer = 0, duration = 2.5,
                    })
                end
                return
            end
            -- 取消按钮
            if GS._unstuckCancelBtnRect and hitTest(mx, my, GS._unstuckCancelBtnRect) then
                GS._unstuckConfirmVisible = false
                return
            end
        end
        return  -- 确认弹窗显示期间屏蔽其他输入
    end

    -- 爱称修改输入框
    local pni = GS.petNameInput
    if pni and pni.active then
        if button == MOUSEB_LEFT then
            -- 点击确定按钮
            local cr = GS._petNameInputConfirmRect
            if cr and hitTest(mx, my, cr) then
                local txt = pni.text or ""
                if #txt > 0 then
                    pni.confirmed = true
                    print("[Input] Pet name input confirmed: " .. txt)
                end
                return
            end
            -- 点击取消按钮
            local ccr = GS._petNameInputCancelRect
            if ccr and hitTest(mx, my, ccr) then
                pni.cancelled = true
                print("[Input] Pet name input cancelled")
                return
            end
            -- 点击输入框区域（激活 IME / 弹出软键盘）
            local ir = GS._petNameInputRect
            if ir and hitTest(mx, my, ir) then
                input:SetScreenKeyboardVisible(true)
            end
        end
        return  -- 输入框显示期间屏蔽所有其他输入
    end

    -- 事件关卡期间：只允许推进对话 / 选项点击 / 名字输入，屏蔽所有其他输入
    if GS.eventInputLocked then
        if button == MOUSEB_LEFT then
            -- 名字输入面板
            local ni = GS.eventNameInput
            if ni and ni.active then
                -- 点击确定按钮
                local cr = GS._nameInputConfirmRect
                if cr and hitTest(mx, my, cr) then
                    local txt = ni.text or ""
                    if #txt > 0 then
                        ni.confirmed = true
                        input:SetScreenKeyboardVisible(false)
                        print("[Input] Name input confirmed: " .. txt)
                    end
                    return
                end
                -- 点击面板任意区域（非确定按钮）：重新激活软键盘
                -- iOS 上键盘可能因失焦而收起，任意点击都需要重新触发
                input:SetScreenKeyboardVisible(true)
                return
            end
            -- 对话选项按钮
            local DialogueManager = require("DialogueManager")
            if DialogueManager.waitingForChoice and GS._choiceRects then
                for i, rect in ipairs(GS._choiceRects) do
                    if hitTest(mx, my, rect) then
                        DialogueManager.selectChoice(i)
                        return
                    end
                end
                return  -- 等待选择期间点击其他区域不响应
            end
            -- 普通对话推进
            if DialogueManager.active then
                DialogueManager.advance()
            end
        end
        return
    end

    -- 酒馆肉搏黑屏过渡：淡入/淡出阶段屏蔽所有点击，对话阶段推进对话
    if GS.brawlCinematic and button == MOUSEB_LEFT then
        if GS.brawlCinematic.phase == "dialogue" then
            local DialogueManager = require("DialogueManager")
            if DialogueManager.active then
                if DialogueManager.waitingForChoice and GS._choiceRects then
                    for i, rect in ipairs(GS._choiceRects) do
                        if hitTest(mx, my, rect) then
                            DialogueManager.selectChoice(i)
                            return
                        end
                    end
                    return
                end
                DialogueManager.advance()
                return
            end
        end
        return  -- 淡入/淡出阶段屏蔽点击
    end

    -- 酒馆肉搏对话推进（BoardOverlay 已 hide，需在此处理）
    if GS.tavernBrawlState and button == MOUSEB_LEFT then
        local DialogueManager = require("DialogueManager")
        if DialogueManager.active then
            if DialogueManager.waitingForChoice and GS._choiceRects then
                for i, rect in ipairs(GS._choiceRects) do
                    if hitTest(mx, my, rect) then
                        DialogueManager.selectChoice(i)
                        return
                    end
                end
                return
            end
            DialogueManager.advance()
            return
        end
    end

    -- 正在采集中，采集不可中断，但允许 UI 操作（查看背包等）
    -- 地图点击相关逻辑在后续代码中通过 turnPhase 自然屏蔽

    -- 副本死亡：再战按钮
    if GS.isDungeon and GS.gameState == GS.STATE_RESPAWN and button == MOUSEB_LEFT then
        -- 死亡时点击关闭悬停面板
        if GS.tooltipItem then GS.closeTooltip(); return end
        if GS.skillTooltipId then GS.closeSkillTooltip(); return end
        -- 死亡时允许关闭设置面板和自动战斗设置面板
        if GS.showSettings then
            GS.showSettings = false
            GS.showTestStagePanel = false
            return
        end
        if GS.showAutoBattleSettings then
            GS.showAutoBattleSettings = false
            GS.autoConsumablePopupSlot = nil
            GS.autoConsumablePopupItems = {}
            GS.autoFoodBuffPopupSlot = nil
            GS.autoFoodBuffPopupItems = {}
            return
        end
        local r = GS.dungeonRetryBtnRect
        if r and hitTest(mx, my, r) then
            GS.dungeonRetryBtnRect = nil
            -- 复活玩家
            GS.clearAllBuffsDebuffs()
            GS.recalcStats(GS.player)
            GS.player.hp = GS.player.maxHp
            GS.player.acted = false
            GS.respawnTimer = 0
            -- 重置当前阶段
            local DM = require("Dungeon.DungeonManager")
            DM.onPlayerDeath()
            -- 直接将玩家移到复活位置（不播放移动动画）
            local arenaTransCfg = DM.getArenaTransitionConfig()
            if arenaTransCfg and arenaTransCfg.playerReset then
                GS.player.x = arenaTransCfg.playerReset.x
                GS.player.y = arenaTransCfg.playerReset.y
            end
            print("=== 副本再战! 重置到阶段 " .. GS.dungeonPhase .. " ===")
            -- 切换到玩家回合状态（过场动画接管后续流程）
            GS.gameState = GS.STATE_PLAYER
            -- 启动竞技场过场序列（跳过玩家移动，直接BOSS入场 + 对话）
            if not DM.startRetryTransition() then
                -- 无过场配置时直接开始
                Combat.startPlayerTurn()
            end
        end
        return
    end

    -- 街头睡觉中：屏蔽所有操作
    if GS.streetSleepActive then
        return
    end

    -- 息屏挂机中：记录触摸起点，屏蔽其他操作
    if GS.screenOffMode then
        if button == MOUSEB_LEFT then
            GS._screenOffSwipeStartY = my
            GS._screenOffSwipeCurrentY = my
        end
        return
    end

    -- 监测面板（全屏覆盖层，优先拦截）
    if MonitorPanel.showPanel then
        if MonitorPanel.handleClick(mx, my, button) then
            return
        end
        -- 点击面板外关闭
        MonitorPanel.closePanel()
        return
    end

    -- GM 封禁面板（全屏覆盖层，优先拦截）
    if BanManager.isGMPanelOpen() then
        M.handleGMBanPanelClick(mx, my)
        return
    end

    -- 在线监测面板（全屏覆盖层，优先拦截 —— 兼容从GM面板直接打开的情况）
    if OnlineMonitor.showPanel then
        if OnlineMonitor.handleClick(mx, my, button) then
            return
        end
        -- 点击面板外关闭
        return
    end

    -- 房屋购买成功提示弹窗（优先拦截）
    if GS.houseBuySuccessVisible then
        if button == MOUSEB_LEFT then
            local okr = GS.houseBuySuccessOkRect
            if okr and hitTest(mx, my, okr) then
                GS.houseBuySuccessVisible = false
            end
        end
        return
    end

    -- 房屋购买弹窗打开时，拦截所有点击
    if GS.houseBuyDialogVisible then
        if button == MOUSEB_LEFT then
            local yr = GS.houseBuyYesRect
            local nr = GS.houseBuyNoRect
            local sr = GS.streetSleepBtnRect
            if yr and hitTest(mx, my, yr) then
                -- 购买房屋
                GS.gold = GS.gold - 5000
                GS.housePurchased = true
                GS.houseBuyDialogVisible = false
                GS.houseBuySuccessVisible = true
                print("=== 购买房屋成功！ ===")
            elseif sr and hitTest(mx, my, sr) then
                -- 街头睡觉：关闭弹窗，开始时间推进
                GS.houseBuyDialogVisible = false
                GS.streetSleepActive = true
                GS.streetSleepTimer = 0
                print("=== 在街头睡觉，等待清晨... ===")
            elseif nr and hitTest(mx, my, nr) then
                -- 取消/关闭
                GS.houseBuyDialogVisible = false
            end
        end
        return
    end

    -- 家园升级确认弹窗
    if GS.homeUpgradeDialogVisible then
        if button == MOUSEB_LEFT then
            local yr = GS.homeUpgradeYesRect
            local nr = GS.homeUpgradeNoRect
            if yr and hitTest(mx, my, yr) then
                -- 计算费用（差价 = 新房售价 - 旧房回收）
                local cost = GS.homeType == "small" and 52000 or 533000
                if GS.gold >= cost then
                    GS.gold = GS.gold - cost
                    if GS.homeType == "small" then
                        GS.homeType = "medium"
                        print("=== 家园升级为中型家园！ ===")
                    else
                        GS.homeType = "large"
                        print("=== 家园升级为大型家园！ ===")
                    end
                    GS.homeUpgradeDialogVisible = false
                    -- 升级后重置玩家位置到新房间中央
                    local rp = GS.getHomeRoomParams(GS.homeType)
                    local cx = math.floor((rp.fx1 + rp.fx2) / 2)
                    local cy = math.floor((rp.fy1 + rp.fy2) / 2)
                    if GS.player then
                        GS.player.x = cx
                        GS.player.y = cy
                    end
                end
            elseif nr and hitTest(mx, my, nr) then
                GS.homeUpgradeDialogVisible = false
            end
        end
        return
    end

    -- "你没有找到艾莉雅"弹窗打开时，拦截所有点击，只处理确定按钮
    if GS.elfNotFoundPopup then
        if button == MOUSEB_LEFT then
            local br = GS.elfNotFoundConfirmRect
            if br and hitTest(mx, my, br) then
                GS.elfNotFoundPopup = false
            end
        end
        return
    end

    -- 学会精灵语弹窗打开时，拦截所有点击，只处理确定按钮
    if GS.elfvahLearnedPopupVisible then
        if button == MOUSEB_LEFT then
            local br = GS.elfvahLearnedConfirmRect
            if br and hitTest(mx, my, br) then
                GS.elfvahLearnedPopupVisible = false
            end
        end
        return
    end

    -- 阅读弹窗打开时，拦截所有点击，只处理关闭按钮和内容拖动
    if GS.readingPopupVisible then
        if button == MOUSEB_LEFT then
            local cr = GS.readingPopupCloseRect
            if cr and hitTest(mx, my, cr) then
                -- 记录已读书籍
                if GS.readingPopupTemplateId then
                    if not GS.elfvahBooksRead then GS.elfvahBooksRead = {} end
                    GS.elfvahBooksRead[GS.readingPopupTemplateId] = true
                end
                GS.readingPopupVisible = false
                GS.readingPopupScrollY = 0
                GS.readingPopupTouchStartY = nil
                -- 检测是否三本都读过
                if not GS.elfvahLanguageLearned and GS.elfvahBooksRead
                    and GS.elfvahBooksRead["elfvah_language_book_1"]
                    and GS.elfvahBooksRead["elfvah_language_book_2"]
                    and GS.elfvahBooksRead["elfvah_language_book_3"] then
                    GS.elfvahLanguageLearned = true
                    GS.elfvahLearnedPopupVisible = true
                end
            elseif GS.readingPopupTextRect and hitTest(mx, my, GS.readingPopupTextRect) and (GS.readingPopupMaxScroll or 0) > 0 then
                GS.readingPopupTouchStartY = my
                GS.readingPopupTouchStartScroll = GS.readingPopupScrollY or 0
            end
        end
        return
    end

    -- 销毁确认弹窗打开时，拦截所有点击，只处理弹窗按钮
    if GS.destroyConfirmVisible then
        if button == MOUSEB_LEFT then
            local yr = GS.destroyConfirmYesRect
            local nr = GS.destroyConfirmNoRect
            if hitTest(mx, my, yr) then
                -- 确定销毁/出售
                if GS.shopMode then
                    -- 出售模式
                    if GS.destroyConfirmBatch then
                        local count, totalGold = GS.sellSelectedItems()
                        print("=== 批量出售 " .. count .. " 件物品，获得 " .. totalGold .. " 金币 ===")
                    elseif GS.destroyConfirmSlotIdx and GS.inventory[GS.destroyConfirmSlotIdx] then
                        local ok, earned = GS.sellItem(GS.destroyConfirmSlotIdx)
                        print("=== 出售物品，获得 " .. earned .. " 金币 ===")
                    end
                else
                    -- 销毁模式
                    if GS.destroyConfirmBatch then
                        GS.destroySelectedItems()
                        GS.invMultiSelect = false
                        GS.invSelected = {}
                    elseif GS.destroyConfirmSlotIdx and GS.inventory[GS.destroyConfirmSlotIdx] then
                        if not GS.inventory[GS.destroyConfirmSlotIdx].locked then
                            GS.inventory[GS.destroyConfirmSlotIdx] = nil
                        end
                    end
                end
                GS.destroyConfirmVisible = false
                GS.destroyConfirmItem = nil
                GS.destroyConfirmSlotIdx = nil
                GS.destroyConfirmBatch = false
                GS.closeTooltip()
            elseif hitTest(mx, my, nr) then
                -- 取消
                GS.destroyConfirmVisible = false
                GS.destroyConfirmItem = nil
                GS.destroyConfirmSlotIdx = nil
                GS.destroyConfirmBatch = false
            end
            -- 无论点哪里都不传递到下层
        end
        return
    end

    -- 拆分弹窗打开时，拦截所有点击，只处理弹窗内交互
    if GS.splitPopupVisible then
        if button == MOUSEB_LEFT then
            local total = GS.splitPopupTotal or 0
            local maxQty = total - 1
            local qty = GS.splitPopupValue or 1

            -- ±数量按钮
            for _, btn in ipairs(GS.splitPopupQtyBtnRects or {}) do
                if btn.enabled and hitTest(mx, my, btn) then
                    local newQty = qty + btn.delta
                    newQty = math.max(1, math.min(maxQty, newQty))
                    GS.splitPopupValue = newQty
                    return
                end
            end

            -- 滑动条点击/拖拽开始
            local sr = GS.splitPopupSliderRect
            if sr and hitTest(mx, my, sr) then
                GS.splitPopupSliderDragging = true
                -- 立即更新数量
                local ratio = math.max(0, math.min(1, (mx - sr.trackX) / sr.trackW))
                local newQty = math.floor(ratio * (maxQty - 1) + 1.5)
                newQty = math.max(1, math.min(maxQty, newQty))
                GS.splitPopupValue = newQty
                return
            end

            -- 确认按钮：执行拆分
            local cr = GS.splitPopupConfirmRect
            if cr and hitTest(mx, my, cr) then
                local slotIdx = GS.splitPopupSlotIdx
                local splitQty = GS.splitPopupValue or 1
                local item = GS.splitPopupItem
                if slotIdx and item and GS.inventory[slotIdx] then
                    -- 找背包空位放拆分出的物品
                    local emptySlot = nil
                    for si = 1, GS.bagSlots do
                        if not GS.inventory[si] then
                            emptySlot = si
                            break
                        end
                    end
                    if emptySlot then
                        -- 复制物品，设置拆出数量
                        local newItem = {}
                        for k, v in pairs(item) do
                            newItem[k] = v
                        end
                        newItem.quantity = splitQty
                        -- 原物品减少数量
                        GS.inventory[slotIdx].quantity = item.quantity - splitQty
                        -- 放入空位
                        GS.inventory[emptySlot] = newItem
                        GS.autoSave.dirty = true
                        GS.shopBuyMsg = { text = "拆分成功", timer = 1.2, color = {60, 200, 60} }
                    else
                        GS.shopBuyMsg = { text = "背包已满，无法拆分", timer = 2.0, color = {220, 60, 40} }
                    end
                end
                GS.splitPopupVisible = false
                GS.splitPopupItem = nil
                GS.splitPopupSlotIdx = nil
                GS.splitPopupValue = 1
                GS.closeTooltip()
                return
            end

            -- 取消按钮
            local nr = GS.splitPopupCancelRect
            if nr and hitTest(mx, my, nr) then
                GS.splitPopupVisible = false
                GS.splitPopupItem = nil
                GS.splitPopupSlotIdx = nil
                GS.splitPopupValue = 1
                return
            end
            -- 无论点哪里都不传递到下层
        end
        return
    end

    -- 深渊区进入确认弹窗打开时，拦截所有点击，只处理弹窗按钮
    if GS.abyssConfirmVisible then
        if button == MOUSEB_LEFT then
            local yr = GS.abyssConfirmYesRect
            local nr = GS.abyssConfirmNoRect
            if hitTest(mx, my, yr) then
                -- 确定：消耗资源并进入副本
                local ok = false
                if GS.abyssConfirmType == "key" then
                    ok = GS.consumeDivineKey()
                    if ok then
                        GS.mapTipText = "消耗神之匙开启深渊副本"
                        GS.mapTipTimer = 2.0
                    end
                else
                    ok = GS.useAbyssChallenge()
                end
                if ok and GS.abyssConfirmStageData then
                    local doSwitch = GS.abyssConfirmStageData
                    GS.abyssConfirmVisible = false
                    GS.abyssConfirmStageData = nil
                    -- 执行暂存的场景切换闭包
                    doSwitch()
                else
                    -- 资源不足（边界情况：弹窗期间状态变化）
                    GS.mapTipText = "资源不足，无法开启"
                    GS.mapTipTimer = 2.0
                    GS.abyssConfirmVisible = false
                    GS.abyssConfirmStageData = nil
                end
            elseif hitTest(mx, my, nr) then
                -- 取消
                GS.abyssConfirmVisible = false
                GS.abyssConfirmStageData = nil
            end
        end
        return
    end

    -- 虚拟广告倒计时期间屏蔽所有输入
    if GS.abyssFakeAdTimer then return end

    -- 史莱姆国王大反击进入确认弹窗
    if GS.slimeRevengeConfirmVisible then
        if button == MOUSEB_LEFT then
            local yr = GS.slimeRevengeConfirmYesRect
            local nr = GS.slimeRevengeConfirmNoRect
            if yr and hitTest(mx, my, yr) then
                if GS.slimeRevengeConfirmType == "ad" then
                    -- 免广告用户：直接进入
                    if GS.adFree then
                        GS.slimeRevengeConfirmVisible = false
                        local doSwitch = GS.slimeRevengeConfirmCallback
                        GS.slimeRevengeConfirmCallback = nil
                        if doSwitch then doSwitch() end
                        print("[AdFree] 免广告用户，直接进入史莱姆大反击")
                        return
                    end
                    -- PC端不支持广告
                    if PlatformUtils.IsDesktopPlatform() then
                        local DM = require("DialogueManager")
                        DM.startDynamic({ { speaker = "旁白", text = "（通过这个叫做台式电脑的设备无法传输力量……）" } })
                        return
                    end
                    -- 看广告进入
                    GS.adLoading = true
                    GS.adSessionId = GS.adSessionId + 1
                    local thisSession = GS.adSessionId
                    MonitorPanel.reportAdClick()
                    sdk:ShowRewardVideoAd(function(result)
                        if result.success then
                            GS.adLoading = false
                            GS.adCancelRect = nil
                            MonitorPanel.reportAdSuccess()
                            GS.slimeRevengeConfirmVisible = false
                            local doSwitch = GS.slimeRevengeConfirmCallback
                            GS.slimeRevengeConfirmCallback = nil
                            if doSwitch then doSwitch() end
                        else
                            if thisSession ~= GS.adSessionId then return end
                            if not GS.adLoading then return end
                            GS.adLoading = false
                            GS.adCancelRect = nil
                            MonitorPanel.reportAdFail()
                        end
                    end)
                else
                    -- 免费次数模式
                    local ok = GS.useSlimeRevengeChallenge()
                    if ok and GS.slimeRevengeConfirmCallback then
                        local doSwitch = GS.slimeRevengeConfirmCallback
                        GS.slimeRevengeConfirmVisible = false
                        GS.slimeRevengeConfirmCallback = nil
                        doSwitch()
                    else
                        GS.mapTipText = "免费次数不足"
                        GS.mapTipTimer = 2.0
                        GS.slimeRevengeConfirmVisible = false
                        GS.slimeRevengeConfirmCallback = nil
                    end
                end
            elseif nr and hitTest(mx, my, nr) then
                GS.slimeRevengeConfirmVisible = false
                GS.slimeRevengeConfirmCallback = nil
            end
        end
        return
    end

    -- 迪哈塔大反击进入确认弹窗
    if GS.dihataRevengeConfirmVisible then
        if button == MOUSEB_LEFT then
            local yr = GS.dihataRevengeConfirmYesRect
            local nr = GS.dihataRevengeConfirmNoRect
            if yr and hitTest(mx, my, yr) then
                if GS.dihataRevengeConfirmType == "ad" then
                    -- 免广告用户：直接进入
                    if GS.adFree then
                        GS.dihataRevengeConfirmVisible = false
                        local doSwitch = GS.dihataRevengeConfirmCallback
                        GS.dihataRevengeConfirmCallback = nil
                        if doSwitch then doSwitch() end
                        print("[AdFree] 免广告用户，直接进入迪哈塔大反击")
                        return
                    end
                    -- PC端不支持广告
                    if PlatformUtils.IsDesktopPlatform() then
                        local DM = require("DialogueManager")
                        DM.startDynamic({ { speaker = "旁白", text = "（通过这个叫做台式电脑的设备无法传输力量……）" } })
                        return
                    end
                    -- 看广告进入
                    GS.adLoading = true
                    GS.adSessionId = GS.adSessionId + 1
                    local thisSession = GS.adSessionId
                    MonitorPanel.reportAdClick()
                    sdk:ShowRewardVideoAd(function(result)
                        if result.success then
                            GS.adLoading = false
                            GS.adCancelRect = nil
                            MonitorPanel.reportAdSuccess()
                            GS.dihataRevengeConfirmVisible = false
                            local doSwitch = GS.dihataRevengeConfirmCallback
                            GS.dihataRevengeConfirmCallback = nil
                            if doSwitch then doSwitch() end
                        else
                            if thisSession ~= GS.adSessionId then return end
                            if not GS.adLoading then return end
                            GS.adLoading = false
                            GS.adCancelRect = nil
                            MonitorPanel.reportAdFail()
                        end
                    end)
                else
                    -- 免费次数模式
                    local ok = GS.useDihataRevengeChallenge()
                    if ok and GS.dihataRevengeConfirmCallback then
                        local doSwitch = GS.dihataRevengeConfirmCallback
                        GS.dihataRevengeConfirmVisible = false
                        GS.dihataRevengeConfirmCallback = nil
                        doSwitch()
                    else
                        GS.mapTipText = "免费次数不足"
                        GS.mapTipTimer = 2.0
                        GS.dihataRevengeConfirmVisible = false
                        GS.dihataRevengeConfirmCallback = nil
                    end
                end
            elseif nr and hitTest(mx, my, nr) then
                GS.dihataRevengeConfirmVisible = false
                GS.dihataRevengeConfirmCallback = nil
            end
        end
        return
    end

    -- 异世深渊进入确认弹窗
    if GS.abyssWorldConfirmVisible then
        if button == MOUSEB_LEFT then
            local yr = GS.abyssWorldConfirmYesRect
            local nr = GS.abyssWorldConfirmNoRect
            if hitTest(mx, my, yr) then
                if GS.abyssWorldConfirmType == "ad" then
                    -- 免广告用户：直接进入深渊
                    if GS.adFree then
                        GS.abyssWorldConfirmVisible = false
                        local doSwitch = GS.abyssWorldConfirmStageData
                        GS.abyssWorldConfirmStageData = nil
                        if doSwitch then
                            GS.abyssWorldActive = true
                            GS.abyssWorldLives = GS.ABYSS_WORLD_MAX_LIVES
                            GS.isAbyssWorld = true
                            doSwitch()
                        end
                        print("[AdFree] 免广告用户，直接进入异世深渊")
                        return
                    end
                    if GS.abyssFakeAd then
                        -- 假广告用户：播放30秒虚拟广告倒计时
                        GS.abyssWorldConfirmVisible = false
                        local doSwitch = GS.abyssWorldConfirmStageData
                        GS.abyssWorldConfirmStageData = nil
                        GS.abyssFakeAdTimer = 30
                        GS.abyssFakeAdCallback = function()
                            if doSwitch then
                                GS.abyssWorldActive = true
                                GS.abyssWorldLives = GS.ABYSS_WORLD_MAX_LIVES
                                GS.isAbyssWorld = true
                                doSwitch()
                            end
                        end
                        return
                    end
                    -- PC端不支持广告
                    if PlatformUtils.IsDesktopPlatform() then
                        local DM = require("DialogueManager")
                        DM.startDynamic({ { speaker = "旁白", text = "（通过这个叫做台式电脑的设备无法传输力量……）" } })
                        return
                    end
                    -- 看广告开启异世深渊
                    GS.adLoading = true
                    GS.adSessionId = GS.adSessionId + 1
                    local thisSession = GS.adSessionId
                    MonitorPanel.reportAdClick()
                    sdk:ShowRewardVideoAd(function(result)
                        if result.success then
                            -- 广告确实看完，无论游戏状态如何都发放奖励
                            GS.adLoading = false
                            GS.adCancelRect = nil
                            MonitorPanel.reportAdSuccess()
                            GS.abyssWorldConfirmVisible = false
                            local doSwitch = GS.abyssWorldConfirmStageData
                            GS.abyssWorldConfirmStageData = nil
                            if doSwitch then
                                GS.abyssWorldActive = true
                                GS.abyssWorldLives = GS.ABYSS_WORLD_MAX_LIVES
                                GS.isAbyssWorld = true
                                doSwitch()
                            end
                        else
                            -- 广告未完成，检查状态避免过期回调弹出多余提示
                            if thisSession ~= GS.adSessionId then return end
                            if not GS.adLoading then return end
                            GS.adLoading = false
                            GS.adCancelRect = nil
                            MonitorPanel.reportAdFail()
                        end
                    end)
                else
                    -- 免费次数模式
                    local ok = GS.useAbyssWorldChallenge()
                    if ok and GS.abyssWorldConfirmStageData then
                        local doSwitch = GS.abyssWorldConfirmStageData
                        GS.abyssWorldConfirmVisible = false
                        GS.abyssWorldConfirmStageData = nil
                        GS.abyssWorldActive = true
                        GS.abyssWorldLives = GS.ABYSS_WORLD_MAX_LIVES
                        GS.isAbyssWorld = true
                        doSwitch()
                    else
                        GS.mapTipText = "免费次数不足"
                        GS.mapTipTimer = 2.0
                        GS.abyssWorldConfirmVisible = false
                        GS.abyssWorldConfirmStageData = nil
                    end
                end
            elseif hitTest(mx, my, nr) then
                GS.abyssWorldConfirmVisible = false
                GS.abyssWorldConfirmStageData = nil
            end
        end
        return
    end

    -- 异世深渊死亡：返回清水镇按钮
    if GS.isAbyssWorld and GS.gameState == GS.STATE_RESPAWN and button == MOUSEB_LEFT then
        -- 死亡时点击关闭悬停面板
        if GS.tooltipItem then GS.closeTooltip(); return end
        if GS.skillTooltipId then GS.closeSkillTooltip(); return end
        -- 死亡时允许关闭设置面板和自动战斗设置面板
        if GS.showSettings then
            GS.showSettings = false
            GS.showTestStagePanel = false
            return
        end
        if GS.showAutoBattleSettings then
            GS.showAutoBattleSettings = false
            GS.autoConsumablePopupSlot = nil
            GS.autoConsumablePopupItems = {}
            GS.autoFoodBuffPopupSlot = nil
            GS.autoFoodBuffPopupItems = {}
            return
        end
        local r = GS.abyssWorldReturnBtnRect
        if r and hitTest(mx, my, r) then
            GS.abyssWorldReturnBtnRect = nil
            -- 结束异世深渊会话
            GS.abyssWorldActive = false
            GS.isAbyssWorld = false
            -- 复活玩家
            GS.clearAllBuffsDebuffs()
            GS.recalcStats(GS.player)
            GS.player.hp = GS.player.maxHp
            GS.player.mp = GS.player.maxMp
            GS.player.acted = false
            GS.respawnTimer = 0
            -- 清除战斗残留
            GS.monsters = {}
            GS.companions = {}
            GS.damageTexts = {}
            GS.attackEffects = {}
            GS.strikeEffects = {}
            GS.whirlwindEffects = {}
            GS.pendingBounces = {}
            GS.pendingEndPlayerTurn = false
            GS._pendingEndTurnTimer = nil
            -- 黑屏过渡回清水镇
            GS.startSceneTransition(function()
                GS.currentStage = 1
                GS.currentBattleBg = "image/bg_grass.png"
                GS.currentAreaName = "清水镇"
                GS.currentStageName = "清水镇"
                GS.player.x = 6
                GS.player.y = 7
                GS.gameState = GS.STATE_PLAYER
                GS.turnPhase = GS.PHASE_MOVE
                GS.turnNumber = 1
                GS.selectedUnit = nil
                GS.movableCells = {}
                GS.attackableCells = {}
                BoardOverlay.show("town", "clearwater", "清水镇")
                GS.spawnHound()
                Combat.spawnMonsters()
                print("=== 异世深渊死亡，返回清水镇 ===")
            end)
        end
        return
    end

    -- 史莱姆国王大反击死亡：返回清水镇按钮
    if GS.currentStage == GS.STAGE_SLIME_KING_REVENGE and GS.gameState == GS.STATE_RESPAWN and button == MOUSEB_LEFT then
        -- 死亡时允许关闭悬停面板
        if GS.tooltipItem then GS.closeTooltip(); return end
        if GS.skillTooltipId then GS.closeSkillTooltip(); return end
        if GS.showSettings then
            GS.showSettings = false
            GS.showTestStagePanel = false
            return
        end
        if GS.showAutoBattleSettings then
            GS.showAutoBattleSettings = false
            GS.autoConsumablePopupSlot = nil
            GS.autoConsumablePopupItems = {}
            GS.autoFoodBuffPopupSlot = nil
            GS.autoFoodBuffPopupItems = {}
            return
        end
        local r = GS.slimeRevengeReturnBtnRect
        if r and hitTest(mx, my, r) then
            GS.slimeRevengeReturnBtnRect = nil
            -- 复活玩家
            GS.clearAllBuffsDebuffs()
            GS.recalcStats(GS.player)
            GS.player.hp = GS.player.maxHp
            GS.player.mp = GS.player.maxMp
            GS.player.acted = false
            GS.respawnTimer = 0
            -- 清除战斗残留
            GS.monsters = {}
            GS.companions = {}
            GS.damageTexts = {}
            GS.attackEffects = {}
            GS.strikeEffects = {}
            GS.whirlwindEffects = {}
            GS.pendingBounces = {}
            GS.pendingEndPlayerTurn = false
            GS._pendingEndTurnTimer = nil
            -- 黑屏过渡回清水镇
            GS.startSceneTransition(function()
                GS.currentStage = 1
                GS.currentBattleBg = "image/bg_grass.png"
                GS.currentAreaName = "清水镇"
                GS.currentStageName = "清水镇"
                GS.player.x = 6
                GS.player.y = 7
                GS.gameState = GS.STATE_PLAYER
                GS.turnPhase = GS.PHASE_MOVE
                GS.turnNumber = 1
                GS.selectedUnit = nil
                GS.movableCells = {}
                GS.attackableCells = {}
                BoardOverlay.show("town", "clearwater", "清水镇")
                GS.spawnHound()
                Combat.spawnMonsters()
                print("=== 史莱姆大反击死亡，返回清水镇 ===")
            end)
        end
        return
    end

    -- 迪哈塔大反击死亡：返回清水镇按钮
    if GS.currentStage == GS.STAGE_DIHATA_REVENGE and GS.gameState == GS.STATE_RESPAWN and button == MOUSEB_LEFT then
        -- 死亡时允许关闭悬停面板
        if GS.tooltipItem then GS.closeTooltip(); return end
        if GS.skillTooltipId then GS.closeSkillTooltip(); return end
        if GS.showSettings then
            GS.showSettings = false
            GS.showTestStagePanel = false
            return
        end
        if GS.showAutoBattleSettings then
            GS.showAutoBattleSettings = false
            GS.autoConsumablePopupSlot = nil
            GS.autoConsumablePopupItems = {}
            GS.autoFoodBuffPopupSlot = nil
            GS.autoFoodBuffPopupItems = {}
            return
        end
        local r = GS.dihataRevengeReturnBtnRect
        if r and hitTest(mx, my, r) then
            GS.dihataRevengeReturnBtnRect = nil
            -- 复活玩家
            GS.clearAllBuffsDebuffs()
            GS.recalcStats(GS.player)
            GS.player.hp = GS.player.maxHp
            GS.player.mp = GS.player.maxMp
            GS.player.acted = false
            GS.respawnTimer = 0
            -- 清除战斗残留
            GS.monsters = {}
            GS.companions = {}
            GS.damageTexts = {}
            GS.attackEffects = {}
            GS.strikeEffects = {}
            GS.whirlwindEffects = {}
            GS.pendingBounces = {}
            GS.pendingEndPlayerTurn = false
            GS._pendingEndTurnTimer = nil
            -- 黑屏过渡回清水镇
            GS.startSceneTransition(function()
                GS.currentStage = 1
                GS.currentBattleBg = "image/bg_grass.png"
                GS.currentAreaName = "清水镇"
                GS.currentStageName = "清水镇"
                GS.player.x = 6
                GS.player.y = 7
                GS.gameState = GS.STATE_PLAYER
                GS.turnPhase = GS.PHASE_MOVE
                GS.turnNumber = 1
                GS.selectedUnit = nil
                GS.movableCells = {}
                GS.attackableCells = {}
                BoardOverlay.show("town", "clearwater", "清水镇")
                GS.spawnHound()
                Combat.spawnMonsters()
                print("=== 迪哈塔大反击死亡，返回清水镇 ===")
            end)
        end
        return
    end

    -- 技能装备弹窗打开时，拦截所有点击
    if GS.skillEquipPopupVisible then
        if button == MOUSEB_LEFT then
            -- 检查"取消放置"按钮
            local rr = GS.skillEquipPopupRemoveRect
            if hitTest(mx, my, rr) then
                local slot = GS.skillEquipPopupSlot
                if slot and GS.activeSkills[slot] then
                    GS.activeSkills[slot] = nil
                end
                GS.skillEquipPopupVisible = false
                GS.skillEquipPopupSlot = nil
                return
            end

            -- 检查弹窗内技能条目
            for _, entry in ipairs(GS.skillEquipPopupSkillRects) do
                if hitTest(mx, my, entry) then
                    -- 不满足施展条件的技能不可装备
                    if entry.disabled then return end
                    local skillId = entry.skillId
                    if entry.equipped then
                        -- 已装备在其他槽位 → 从旧槽移除，放入新槽
                        for i = 1, GS.ACTIVE_SKILL_SLOTS do
                            if GS.activeSkills[i] == skillId then
                                GS.activeSkills[i] = nil
                                break
                            end
                        end
                    end
                    GS.activeSkills[GS.skillEquipPopupSlot] = skillId
                    -- 冲锋技能：设置冲锋模式
                    if entry.chargeMode then
                        GS.autoChargeMode = entry.chargeMode
                    end
                    GS.skillEquipPopupVisible = false
                    GS.skillEquipPopupSlot = nil
                    return
                end
            end

            -- 点击弹窗外部 → 关闭
            local pr = GS.skillEquipPopupRect
            if pr and not hitTest(mx, my, pr) then
                GS.skillEquipPopupVisible = false
                GS.skillEquipPopupSlot = nil
            end
        end
        return
    end

    -- ====== 行动菜单：技能子菜单拦截 ======
    if GS.actionSkillSubVisible then
        if button == MOUSEB_LEFT then
            for _, entry in ipairs(GS.actionSkillSubRects) do
                if hitTest(mx, my, entry) then
                    if entry.ready then
                        local skillDef = GS.SKILL_DEFS[entry.skillId]
                        local castStages = GS.getSkillCastStages(entry.skillId)
                        if skillDef and skillDef.selfCast and skillDef.needTarget then
                            -- 需要点选目标的自我施放技能（可对友军释放）
                            GS.actionChoice = "selfSkill"
                            GS.actionChosenSkillId = entry.skillId
                            GS.actionSkillSubVisible = false
                            GS.actionSkillSubRects = {}
                            GS.actionSkillSubRect = nil
                            GS.actionMenuVisible = false
                            GS.groundTargetCells = nil  -- 清空，避免与 attackableCells 叠加渲染
                            -- 计算施展范围并高亮显示
                            local pu = GS.selectedUnit
                            local castRange = skillDef.skillRange or (GS.player and GS.player.atkRange) or 3
                            if skillDef.rangeBreaks then
                                local slv = GS.skillLevels[entry.skillId] or 1
                                for _, brk in ipairs(skillDef.rangeBreaks) do
                                    if slv >= brk then castRange = castRange + 1 end
                                end
                            end
                            castRange = castRange + GS.getElementRangeBonus(entry.skillId)
                            if skillDef.useMagic then castRange = math.max(castRange, 3) end
                            GS.attackableCells = {}
                            for dy = -castRange, castRange do
                                for dx = -castRange, castRange do
                                    local tx, ty = pu.x + dx, pu.y + dy
                                    if GS.isInBoard(tx, ty) and (math.abs(dx) + math.abs(dy)) <= castRange then
                                        GS.attackableCells[GS.cellKey(tx, ty)] = true
                                    end
                                end
                            end
                        elseif skillDef and skillDef.selfCast then
                            -- 纯自我施放技能（buff/治疗等），立即释放
                            if castStages > 0 and GS.chantStages < castStages then
                                -- 吟唱段数不足，进入吟唱状态
                                local consume = math.min(castStages, GS.chantStages)
                                GS.chantStages = GS.chantStages - consume
                                GS.useSkill(entry.skillId)  -- 扣蓝+设CD
                                GS.chanting = { skillId = entry.skillId, stagesNeeded = castStages, stagesAccum = consume, castType = "self" }
                                local left = castStages - consume
                                -- Combat.addDamageText(GS.player.x, GS.player.y, "开始吟唱(还需" .. left .. "段)", {180, 160, 220})
                                GS.advanceTurnPhase()
                                GS.selectedUnit.acted = true
                                GS.closeActionMenu()
                                GS.selectedUnit = nil
                                GS.movableCells = {}
                                GS.attackableCells = {}
                                Combat.endPlayerTurn()
                            else
                                -- 段数充足，消耗并直接释放
                                GS.consumeChantForSkill(entry.skillId)
                                Combat.addSkillCastText(GS.selectedUnit.x, GS.selectedUnit.y, entry.skillId)
                                Combat.executePlayerAttack(GS.selectedUnit, GS.selectedUnit, entry.skillId)
                                if not GS.mageCheckContinueTurn() then
                                    GS.advanceTurnPhase()  -- ACTION → END
                                    GS.selectedUnit.acted = true
                                    GS.closeActionMenu()
                                    GS.selectedUnit = nil
                                    GS.movableCells = {}
                                    GS.attackableCells = {}
                                    Combat.endPlayerTurn()
                                end
                            end
                        elseif skillDef and skillDef.aoe then
                            -- AOE技能
                            if castStages > 0 and GS.chantStages < castStages then
                                -- 吟唱段数不足
                                local consume = math.min(castStages, GS.chantStages)
                                GS.chantStages = GS.chantStages - consume
                                GS.useSkill(entry.skillId)
                                GS.chanting = { skillId = entry.skillId, stagesNeeded = castStages, stagesAccum = consume, castType = "aoe" }
                                local left = castStages - consume
                                -- Combat.addDamageText(GS.player.x, GS.player.y, "开始吟唱(还需" .. left .. "段)", {180, 160, 220})
                                GS.advanceTurnPhase()
                                GS.selectedUnit.acted = true
                                Combat.removeDeadMonsters()
                                GS.closeActionMenu()
                                GS.selectedUnit = nil
                                GS.movableCells = {}
                                GS.attackableCells = {}
                                Combat.endPlayerTurn()
                            else
                                GS.consumeChantForSkill(entry.skillId)
                                Combat.performAOE(GS.selectedUnit, entry.skillId)
                                -- 白木胁差：手动施放AOE技能触发额外施展
                                Combat.enqueueExtraDmgSkillCasts(GS.selectedUnit, GS.selectedUnit, entry.skillId)
                                Combat.removeDeadMonsters()
                                if not GS.mageCheckContinueTurn() then
                                    GS.advanceTurnPhase()  -- ACTION → END
                                    GS.selectedUnit.acted = true
                                    GS.closeActionMenu()
                                    if not Combat.startChainIfNeeded(function()
                                        Combat.endPlayerTurn()
                                    end) then
                                        GS.selectedUnit = nil
                                        GS.movableCells = {}
                                        GS.attackableCells = {}
                                        Combat.endPlayerTurn()
                                    end
                                end
                            end
                        elseif skillDef and skillDef.groundTarget then
                            -- 地面目标技能（圣树等）：等待点击空地格子
                            GS.actionChoice = "groundSkill"
                            GS.actionChosenSkillId = entry.skillId
                            GS.actionSkillSubVisible = false
                            GS.actionSkillSubRects = {}
                            GS.actionSkillSubRect = nil
                            GS.actionMenuVisible = false
                            GS.attackableCells = {}  -- 清空，避免与 groundTargetCells 叠加渲染
                            -- 计算可放置范围（用 skillRange + rangeBreaks + 元素熟练加成）
                            if skillDef.skillRange and GS.selectedUnit then
                                local range = skillDef.skillRange
                                if skillDef.rangeBreaks then
                                    local slv = GS.skillLevels[entry.skillId] or 1
                                    for _, brk in ipairs(skillDef.rangeBreaks) do
                                        if slv >= brk then range = range + 1 end
                                    end
                                end
                                range = range + GS.getElementRangeBonus(entry.skillId)
                                local WE_gt = require("WeatherEffects")
                                local isProjGT = WE_gt.isProjectileType(GS.selectedUnit, entry.skillId, GS.selectedUnit.weaponTag)
                                GS.groundTargetCells = GS.getAttackableCells(
                                    GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y,
                                    range, isProjGT)
                            end
                        else
                            -- 单体技能：设置选择，等待点击目标
                            GS.actionChoice = "skill"
                            GS.actionChosenSkillId = entry.skillId
                            GS.actionSkillSubVisible = false
                            GS.actionSkillSubRects = {}
                            GS.actionSkillSubRect = nil
                            GS.actionMenuVisible = false
                            GS.groundTargetCells = nil  -- 清空，避免与 attackableCells 叠加渲染
                            GS.aoeGroundMode = false    -- 清空 AOE 地面施放标记
                            -- 技能有独立攻击距离时，用 skillRange + 元素熟练加成重新计算可攻击格子
                            if skillDef and skillDef.skillRange and GS.selectedUnit then
                                local sRange = skillDef.skillRange
                                if skillDef.rangeBreaks then
                                    local slv = GS.skillLevels[entry.skillId] or 1
                                    for _, brk in ipairs(skillDef.rangeBreaks) do
                                        if slv >= brk then sRange = sRange + 1 end
                                    end
                                end
                                -- 献礼：闪烁突袭施展距离加成
                                if skillDef.flashAssault and GS.player then
                                    sRange = sRange + (GS.player.offeringFlashRangeBonus or 0)
                                end
                                sRange = sRange + GS.getElementRangeBonus(entry.skillId)
                                local WE_sk = require("WeatherEffects")
                                local isProjSK = WE_sk.isProjectileType(GS.selectedUnit, entry.skillId, GS.selectedUnit.weaponTag)
                                GS.attackableCells = GS.getAttackableCells(
                                    GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y,
                                    sRange, isProjSK)
                            end
                            -- 范围化 AOE 技能（银色狮子强击系/哈雷努拉祝福超度）：标记允许点击地面施放
                            if GS.selectedUnit and Combat.isAoeGroundSkill(entry.skillId) then
                                GS.aoeGroundMode = true
                            end
                        end
                    end
                    return
                end
            end
            -- 点击子菜单外部：关闭子菜单，回到主菜单
            local sr = GS.actionSkillSubRect
            if sr and not hitTest(mx, my, sr) then
                GS.actionSkillSubVisible = false
                GS.actionSkillSubRects = {}
                GS.actionSkillSubRect = nil
            end
        end
        return
    end

    -- ====== 行动菜单：主菜单拦截 ======
    if GS.actionMenuVisible then
        if button == MOUSEB_LEFT then
            local rects = GS.actionMenuRects

            -- 普通攻击
            if rects.attack then
                local r = rects.attack
                if hitTest(mx, my, r) then
                    GS.actionChoice = "attack"
                    GS.actionChosenSkillId = nil
                    GS.actionMenuVisible = false
                    -- 留在 STATE_SELECT/PHASE_ACTION，等待点击敌人
                    return
                end
            end

            -- 技能
            if rects.skill then
                local r = rects.skill
                if hitTest(mx, my, r) then
                    local skills = GS.getLearnedActiveSkills()
                    if #skills > 0 then
                        GS.actionSkillSubVisible = true
                    end
                    return
                end
            end

            -- 采集
            if rects.gather then
                local r = rects.gather
                if hitTest(mx, my, r) then
                    GS.actionChoice = "gather"
                    GS.actionChosenSkillId = nil
                    GS.actionMenuVisible = false
                    -- 采集距离固定为1（不受武器攻击距离影响）
                    GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y, 1)
                    -- 留在 PHASE_ACTION，等待点击采集物
                    return
                end
            end

            -- 道具（占位）
            if rects.item then
                local r = rects.item
                if hitTest(mx, my, r) then
                    return
                end
            end

            -- 待机
            if rects.wait then
                local r = rects.wait
                if hitTest(mx, my, r) then
                    GS.advanceTurnPhase()  -- ACTION → END
                    GS.selectedUnit.acted = true
                    GS.closeActionMenu()
                    GS.selectedUnit = nil
                    GS.movableCells = {}
                    GS.attackableCells = {}
                    Combat.endPlayerTurn()
                    return
                end
            end

            -- 撤销移动（行动后禁用）
            if rects.undo then
                local r = rects.undo
                if hitTest(mx, my, r) then
                    if GS.mageActionTaken then
                        -- 已行动，按钮禁用，不响应
                    else
                        -- 撤销移动
                        if GS.selectedUnit and GS.actionPreMoveX then
                            Command.recordUndoMove()
                            GS.selectedUnit.x = GS.actionPreMoveX
                            GS.selectedUnit.y = GS.actionPreMoveY
                            GS.turnPhase = GS.PHASE_MOVE
                            GS.movableCells, GS.movableParents = GS.getMovableCells(GS.selectedUnit)
                            GS.attackableCells = {}
                            -- 地狱踏：撤销移动时清除本次放置的燃烧地面
                            if GS._hellStompPlaced then
                                for _, p in ipairs(GS._hellStompPlaced) do
                                    for j = #GS.burningGrounds, 1, -1 do
                                        local bg = GS.burningGrounds[j]
                                        if bg.x == p.x and bg.y == p.y and bg.hellStomp then
                                            table.remove(GS.burningGrounds, j)
                                            break
                                        end
                                    end
                                end
                                GS._hellStompPlaced = nil
                            end
                        end
                        GS.closeActionMenu()
                    end
                    return
                end
            end

            -- 点击菜单外部：不做任何操作（强制选择）
        end
        return
    end

    -- 右键点击
    if button == MOUSEB_RIGHT then
        -- 自动设置面板：右键卸下自动技能槽
        if GS.showAutoBattleSettings and GS.activeSkillSlotAreas then
            for i, r in pairs(GS.activeSkillSlotAreas) do
                if hitTest(mx, my, r) then
                    if GS.activeSkills[i] then
                        GS.activeSkills[i] = nil
                        GS.closeSkillTooltip()
                    end
                    return
                end
            end
        end
        -- 背包物品直接装备 / 装备槽直接卸下（多选模式下禁用）
        if GS.activeBottomTab == 2 and not GS.invMultiSelect then
            -- 检测装备槽：右键卸下
            if GS.equipSlotAreas then
                for slotId, r in pairs(GS.equipSlotAreas) do
                    if hitTest(mx, my, r) then
                        if GS.equipment[slotId] then
                            GS.unequipItem(slotId)
                            GS.closeTooltip()
                        end
                        return
                    end
                end
            end
            -- 检测背包格子：右键装备 / 使用消耗品
            if GS.inventorySlotAreas then
                for idx, sr in pairs(GS.inventorySlotAreas) do
                    if hitTest(mx, my, sr) then
                        local item = GS.inventory[idx]
                        if item and item.slot then
                            local ok, msg = GS.equipItem(idx)
                            if ok then
                                GS.closeTooltip()
                            elseif msg then
                                GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                            end
                        elseif item then
                            local tpl = GS.itemTemplates[item.templateId]
                            if tpl and tpl.useEffect then
                                local ok, msg = GS.useSpecialItem(idx)
                                if msg and msg ~= "" then
                                    if ok then
                                        GS.shopBuyMsg = { text = msg, timer = 2.0, color = {60, 200, 60} }
                                    else
                                        GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                                    end
                                end
                                GS.closeTooltip()
                            elseif item.consumable and type(item.consumable) == "table" then
                                Command.recordUseItem(idx)
                                local ok, msg = GS.useConsumable(idx)
                                if ok then
                                    GS.shopBuyMsg = { text = msg, timer = 1.5, color = {60, 200, 60} }
                                else
                                    GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                                end
                                GS.closeTooltip()
                            end
                        end
                        return
                    end
                end
            end
        end
        return
    end

    if button ~= MOUSEB_LEFT then return end

    -- "监"按钮点击（管理员监测面板）
    if GS.monitorPanelBtnRect then
        if hitTest(mx, my, GS.monitorPanelBtnRect) then
            if MonitorPanel.showPanel then
                MonitorPanel.closePanel()
            else
                MonitorPanel.openPanel()
            end
            return
        end
    end

    -- GM "管"按钮点击（在设置按钮左侧）
    if GS.gmPanelBtnRect then
        if hitTest(mx, my, GS.gmPanelBtnRect) then
            GS.showGMPanel = not GS.showGMPanel
            if not GS.showGMPanel then
                GS.showTestStagePanel = false
                GS.showTestItemPanel = false
            end
            return
        end
    end

    -- GM "封"按钮点击（封禁管理面板）
    if GS.gmBanBtnRect then
        if hitTest(mx, my, GS.gmBanBtnRect) then
            BanManager.toggleGMPanel()
            return
        end
    end

    -- 设置按钮点击
    if GS.settingsBtnRect then
        local r = GS.settingsBtnRect
        if hitTest(mx, my, r) then
            GS.showSettings = not GS.showSettings
            if not GS.showSettings then
                GS.showTestStagePanel = false
            end
            return
        end
    end

    -- 悬停面板交互（优先级最高，多选模式下禁止装备/卸下操作）
    -- 购买弹窗打开时跳过tooltip交互，交由BoardOverlay分支统一处理
    if GS.tooltipItem and not GS.shopBuyConfirmVisible then
        -- 点击锁定按钮
        if GS.tooltipLockBtnRect then
            local lr = GS.tooltipLockBtnRect
            if hitTest(mx, my, lr) then
                -- 获取当前物品引用并切换锁定状态
                local lockItem = nil
                if GS.tooltipSource == "equipment" and GS.tooltipEquipSlotId then
                    lockItem = GS.equipment[GS.tooltipEquipSlotId]
                elseif GS.tooltipSource == "warehouse" then
                    lockItem = GS.tooltipItem
                elseif GS.tooltipSlotIdx > 0 then
                    lockItem = GS.inventory[GS.tooltipSlotIdx]
                end
                if lockItem then
                    lockItem.locked = not lockItem.locked
                    GS.saveToCloud()
                end
                return
            end
        end
        -- 点击收藏按钮
        if GS.tooltipFavBtnRect then
            local fr = GS.tooltipFavBtnRect
            if hitTest(mx, my, fr) then
                local favItem = nil
                if GS.tooltipSource == "equipment" and GS.tooltipEquipSlotId then
                    favItem = GS.equipment[GS.tooltipEquipSlotId]
                elseif GS.tooltipSource == "warehouse" then
                    favItem = GS.tooltipItem
                elseif GS.tooltipSlotIdx > 0 then
                    favItem = GS.inventory[GS.tooltipSlotIdx]
                end
                if favItem then
                    favItem.starred = not favItem.starred
                    GS.saveToCloud()
                end
                return
            end
        end
        -- 点击装备/卸下按钮
        if GS.tooltipEquipBtnRect and not GS.invMultiSelect then
            local r = GS.tooltipEquipBtnRect
            if hitTest(mx, my, r) then
                if GS.tooltipItem and GS.tooltipItem.templateId
                    and GS.itemTemplates[GS.tooltipItem.templateId]
                    and GS.itemTemplates[GS.tooltipItem.templateId].useEffect then
                    -- 特殊物品使用（背包扩充券、仓库扩充券、自选箱等）优先
                    local idx = GS.tooltipSlotIdx
                    local ok, msg = GS.useSpecialItem(idx)
                    if msg and msg ~= "" then
                        if ok then
                            GS.shopBuyMsg = { text = msg, timer = 2.0, color = {60, 200, 60} }
                        else
                            GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                        end
                    end
                    GS.closeTooltip()
                    return
                elseif GS.tooltipItem and GS.tooltipItem.consumable and type(GS.tooltipItem.consumable) == "table" then
                    local idx = GS.tooltipSlotIdx
                    if GS.gameState == GS.STATE_RESPAWN or GS.gameState == GS.STATE_GAMEOVER then
                        -- 复活倒计时和游戏结束：拦截
                        GS.closeTooltip()
                        return
                    elseif GS.gameState == GS.STATE_ENEMY then
                        -- 敌人回合：排队延迟到玩家回合生效
                        Command.recordUseItem(idx)
                        table.insert(GS.pendingConsumableSlots, idx)
                    else
                        -- 玩家回合：直接使用
                        Command.recordUseItem(idx)
                        local ok, msg = GS.useConsumable(idx)
                        print(msg)
                    end
                elseif GS.tooltipSource == "equipment" then
                    -- 卸下装备
                    local ok, msg = GS.unequipItem(GS.tooltipEquipSlotId)
                    if ok then
                        print("卸下成功: " .. (GS.tooltipItem.name or ""))
                    elseif msg then
                        GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                    end
                else
                    -- 装备物品
                    local idx = GS.tooltipSlotIdx
                    local ok, msg = GS.equipItem(idx)
                    if ok then
                        print("装备成功: " .. (GS.tooltipItem.name or ""))
                    elseif msg then
                        GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                    end
                end
                GS.closeTooltip()
                return
            end
        end
        -- 点击阅读按钮：打开阅读弹窗
        if GS.tooltipReadBtnRect then
            local rb = GS.tooltipReadBtnRect
            if hitTest(mx, my, rb) then
                local item = GS.tooltipItem
                if item then
                    local tpl = item.templateId and GS.itemTemplates[item.templateId]
                    if tpl and tpl.readableText then
                        GS.readingPopupVisible = true
                        GS.readingPopupTitle = item.name or tpl.name or "阅读"
                        GS.readingPopupText = tpl.readableText
                        GS.readingPopupTemplateId = item.templateId
                    end
                end
                return
            end
        end
        -- 点击套装详情按钮：切换二级面板固定
        if GS.setDetailBtnRect then
            local db = GS.setDetailBtnRect
            if hitTest(mx, my, db) then
                GS.setDetailPinned = not GS.setDetailPinned
                return
            end
        end
        -- 点击二级面板内部（不关闭）
        if GS.setDetailPanelRect and GS.setDetailPinned then
            if hitTest(mx, my, GS.setDetailPanelRect) then
                return
            end
        end
        -- 点击面板内部（不关闭；如需滚动则启动拖动）
        -- 主面板
        if GS.tooltipRect and hitTest(mx, my, GS.tooltipRect) then
            if GS.tooltipNeedScroll then
                GS.tooltipTouchStartY = my
                GS.tooltipTouchStartScroll = GS.tooltipScrollY or 0
                GS.tooltipTouchTarget = "main"
            end
            return
        end
        -- 对比面板
        if GS.tooltipCmpRect and hitTest(mx, my, GS.tooltipCmpRect) then
            if GS.tooltipCmpNeedScroll then
                GS.tooltipTouchStartY = my
                GS.tooltipTouchStartScroll = GS.tooltipCmpScrollY or 0
                GS.tooltipTouchTarget = "cmp"
            end
            return
        end
        -- 锁定模式下点击面板外：关闭（同时关闭二级面板）
        if GS.tooltipPinned then
            GS.closeTooltip()
            return
        end
    end

    -- GM 管理面板内：按钮交互
    if GS.showGMPanel then
        -- 测试关卡按钮
        local tbr = GS.testStageBtnRect
        if tbr and tbr.w and tbr.w > 0 then
            if hitTest(mx, my, tbr) then
                GS.showTestStagePanel = not GS.showTestStagePanel
                GS.showTestItemPanel = false
                GS.testStageScrollY = 0
                return
            end
        end

        -- 测试道具按钮
        local tibr = GS.testItemBtnRect
        if tibr and tibr.w and tibr.w > 0 then
            if hitTest(mx, my, tibr) then
                GS.showTestItemPanel = not GS.showTestItemPanel
                GS.showTestStagePanel = false
                GS.testItemScrollY = 0
                return
            end
        end

        -- 测试天气按钮（循环：晴天→雨天→刮风(随机方向)→暴晒→晴天）
        local twbr = GS.testWeatherBtnRect
        if twbr and twbr.w and twbr.w > 0 then
            if hitTest(mx, my, twbr) then
                local RainEffect = require("RainEffect")
                local WindEffect = require("WindEffect")
                local ScorchEffect = require("ScorchEffect")
                if GS.isRaining then
                    RainEffect.setEnabled(false)
                    WindEffect.setEnabled(true, math.random(1, 8))
                    ScorchEffect.setEnabled(false)
                elseif GS.isWindy then
                    WindEffect.setEnabled(false)
                    ScorchEffect.setEnabled(true)
                elseif GS.isScorching then
                    ScorchEffect.setEnabled(false)
                else
                    RainEffect.setEnabled(true)
                end
                return
            end
        end

        -- 职业切换按钮
        local csbr = GS.classSwitchBtnRect
        if csbr and csbr.w and csbr.w > 0 then
            if hitTest(mx, my, csbr) then
                local classList = GS.CLASS_LIST
                local curIdx = 1
                for i, cid in ipairs(classList) do
                    if cid == GS.currentClass then curIdx = i; break end
                end
                local nextIdx = (curIdx % #classList) + 1
                local newClass = classList[nextIdx]
                GS.changeClass(newClass)
                GS.confirmedClass = newClass   -- 管理员切换职业时存入ORIGIN，防止兜底防护还原
                GS.showTestStagePanel = false
                GS.showTestItemPanel = false
                return
            end
        end

        -- 测试家园按钮：循环切换 small→medium→large→small
        local thbr = GS.testHomeBtnRect
        if thbr and thbr.w and thbr.w > 0 then
            if hitTest(mx, my, thbr) then
                local order = { "small", "medium", "large" }
                local curIdx = 1
                for i, v in ipairs(order) do
                    if v == GS.homeType then curIdx = i; break end
                end
                local nextIdx = (curIdx % #order) + 1
                GS.homeType = order[nextIdx]
                if GS.homeMode then
                    local rp = GS.getHomeRoomParams(GS.homeType)
                    local cx = math.floor((rp.fx1 + rp.fx2) / 2)
                    local cy = math.floor((rp.fy1 + rp.fy2) / 2)
                    if GS.player then
                        GS.player.x = cx
                        GS.player.y = cy
                    end
                end
                return
            end
        end

        -- 冒险者等级切换按钮：循环 1→2→...→8→1
        local trbr = GS.testRankBtnRect
        if trbr and trbr.w and trbr.w > 0 then
            if hitTest(mx, my, trbr) then
                local maxRank = 8
                GS.adventurerRank = (GS.adventurerRank or 1) % maxRank + 1
                if GS.player then GS.recalcStats(GS.player) end
                local rankLetters = { "F", "E", "D", "C", "B", "A", "S", "G" }
                print("[测试] 冒险者等级切换为: " .. (rankLetters[GS.adventurerRank] or "?") .. "级")
                return
            end
        end

        -- 清空所有任务记录（管理员）
        local tbbr = GS.testBrawlBtnRect
        if tbbr and tbbr.w and tbbr.w > 0 then
            if hitTest(mx, my, tbbr) then
                local QM_clear = require("QuestManager")
                local keys = {}
                for qid, st in pairs(QM_clear.questStates) do
                    if st.status ~= QM_clear.STATUS_LOCKED then
                        keys[#keys + 1] = qid
                    end
                end
                for _, qid in ipairs(keys) do
                    QM_clear.questStates[qid] = nil
                end
                GS.tavernBrawlState = nil
                GS.angelicaTravelDone = {}
                GS.difenTravelDone = {}
                GS.eliyaTravelDone = {}
                GS.adventurerRank = 1
                GS.monsterKillCounts = {}
                GS.eventCompleted["initial_supply"] = nil
                GS.eventCompleted["initial_supply_weapons"] = nil
                GS.eventCompleted["initial_supply_potions"] = nil
                QM_clear.update()
                QM_clear.activateQuest("main_third_will")
                QM_clear.activateQuest("side_townspeople")
                print("[管理员] 已清空 " .. #keys .. " 个任务记录，已重新激活初始任务，事件2已重置")
                GS.saveToCloud()
                return
            end
        end

        -- 测试伴侣按钮：循环切换 无→芙蕾雅→妮可→…→艾莉雅→无
        local tpbr = GS.testPartnerBtnRect
        if tpbr and tpbr.w and tpbr.w > 0 then
            if hitTest(mx, my, tpbr) then
                local partnerList = {
                    "guild_master", "guild_receptionist", "potion_shop_owner",
                    "jewelry_shop_owner", "tavern_keeper", "tavern_dancer", "forest_elf",
                }
                local curIdx = 0
                for i, k in ipairs(partnerList) do
                    if GS.partnerNpcKey == k then curIdx = i; break end
                end
                local nextIdx = (curIdx % (#partnerList + 1)) + 1
                if nextIdx > #partnerList then
                    GS.partnerNpcKey = nil
                    GS.partnerLivingTogether = false
                    GS.homeNpc = nil
                    print("[测试] 伴侣切换为: 无")
                else
                    GS.partnerNpcKey = partnerList[nextIdx]
                    GS.partnerLivingTogether = true
                    GS.homeNpc = nil
                    GS.homeNpcLastShouldState = nil
                    GS.learnNPCName(partnerList[nextIdx])
                    local pInfo = GS.NPC_REGISTRY[partnerList[nextIdx]]
                    print("[测试] 伴侣切换为: " .. (pInfo and pInfo.name or partnerList[nextIdx]) .. " (同住)")
                end
                return
            end
        end

        -- 测试精灵按钮：切换精灵遭遇每日检定次数
        local tebr = GS.testElfBtnRect
        if tebr and tebr.w and tebr.w > 0 then
            if hitTest(mx, my, tebr) then
                GS.debugElfUnlimitedRolls = not GS.debugElfUnlimitedRolls
                if GS.debugElfUnlimitedRolls then
                    print("[测试] 精灵遭遇: 无限检定（每次进入战斗关卡都可触发）")
                else
                    print("[测试] 精灵遭遇: 每天1次检定（默认）")
                end
                return
            end
        end

        -- 等级-按钮
        local lvDown = GS.testLvDownBtnRect
        if lvDown and lvDown.w and lvDown.w > 0 then
            if hitTest(mx, my, lvDown) then
                if GS.player and GS.player.level > 1 then
                    GS.player.level = GS.player.level - 1
                    GS.player.exp = 0
                    GS.recalcStats(GS.player)
                    GS.player.hp = GS.player.maxHp
                    GS.player.mp = GS.player.maxMp
                    GS.displayExpLevel = GS.player.level
                    GS.updateShopByLevel()
                    print("[测试] 等级降为 Lv." .. GS.player.level)
                end
                return
            end
        end

        -- 等级+按钮
        local lvUp = GS.testLvUpBtnRect
        if lvUp and lvUp.w and lvUp.w > 0 then
            if hitTest(mx, my, lvUp) then
                if GS.player and GS.player.level < 100 then
                    GS.player.level = GS.player.level + 1
                    GS.player.exp = 0
                    GS.player.statPoints = GS.player.statPoints + 3
                    GS.skillPoints = GS.skillPoints + 1
                    GS.recalcStats(GS.player)
                    GS.player.hp = GS.player.maxHp
                    GS.player.mp = GS.player.maxMp
                    GS.displayExpLevel = GS.player.level
                    GS.updateShopByLevel()
                    print("[测试] 等级升为 Lv." .. GS.player.level)
                end
                return
            end
        end

        -- 时间推进+1h按钮
        local ttbr = GS.testTimeBtnRect
        if ttbr and ttbr.w and ttbr.w > 0 then
            if hitTest(mx, my, ttbr) then
                GS.tickWeatherTime(60)
                local newHour = BoardOverlay.getGameHour()
                print(string.format("[测试] 时间推进1小时，当前时间: %02d:%02d", math.floor(newHour), math.floor((newHour % 1) * 60)))
                return
            end
        end

        -- 红龙击杀开关按钮
        local dragonBtn = GS.testDragonBtnRect
        if dragonBtn and dragonBtn.w and dragonBtn.w > 0 then
            if hitTest(mx, my, dragonBtn) then
                if not GS.monsterKillCounts then GS.monsterKillCounts = {} end
                local cur = GS.monsterKillCounts["red_dragon_young"] or 0
                if cur > 0 then
                    GS.monsterKillCounts["red_dragon_young"] = 0
                    print("[测试] 红龙幼龙击杀状态: 未击杀")
                else
                    GS.monsterKillCounts["red_dragon_young"] = 1
                    print("[测试] 红龙幼龙击杀状态: 已击杀")
                end
                return
            end
        end

        -- 手动上传反作弊时间按钮
        local bagExpandBtn = GS.testBagExpandBtnRect
        if bagExpandBtn and bagExpandBtn.w and bagExpandBtn.w > 0 then
            if hitTest(mx, my, bagExpandBtn) then
                GS.bagSlots = GS.bagSlots + 10
                print("[测试] 背包扩容+10，当前上限: " .. GS.bagSlots .. " 格")
                return
            end
        end

        local unlockAbyssBtn = GS.testUnlockAbyssBtnRect
        if unlockAbyssBtn and unlockAbyssBtn.w and unlockAbyssBtn.w > 0 then
            if hitTest(mx, my, unlockAbyssBtn) then
                GS.abyssUnlocked = true
                GS.infiniteTowerUnlocked = true
                -- 填充所有深渊层的前置击杀数，解锁全部层
                for i = 1, 5 do
                    local stIdx = GS["STAGE_ABYSS_" .. i]
                    if stIdx then
                        GS.stageKillCounts[stIdx] = math.max(GS.stageKillCounts[stIdx] or 0, 100)
                    end
                end
                -- 填充无限塔的前置击杀数
                if GS.STAGE_TOWER_1 then
                    GS.stageKillCounts[GS.STAGE_TOWER_1] = math.max(GS.stageKillCounts[GS.STAGE_TOWER_1] or 0, 100)
                end
                print("[管理员] 一键解锁：异世深渊全5层 + 无限塔")
                return
            end
        end

        local uploadTimeBtn = GS.testUploadTimeBtnRect
        if uploadTimeBtn and uploadTimeBtn.w and uploadTimeBtn.w > 0 then
            if hitTest(mx, my, uploadTimeBtn) then
                SignInSystem._uploadAdminTime()
                local now = os.time()
                print("[管理员] 手动上传反作弊时间: " .. now)
                return
            end
        end

        -- 朱莉任务切换按钮
        local julieBtn = GS.testJulieQuestBtnRect
        if julieBtn and julieBtn.w and julieBtn.w > 0 then
            if hitTest(mx, my, julieBtn) then
                local QM = require("QuestManager")
                local JULIE_IDS = {
                    "side_julie_gem_1", "side_julie_gem_2",
                    "side_julie_gem_3", "side_julie_gem_4",
                    "side_julie_gem_5", "side_julie_gem_6",
                }
                local lastSt = QM.questStates["side_julie_gem_6"]
                local allDone = lastSt and lastSt.status == QM.STATUS_COMPLETED
                if allDone then
                    for _, qid in ipairs(JULIE_IDS) do
                        QM.questStates[qid] = nil
                    end
                    print("[管理员] 已清除朱莉全部任务状态")
                else
                    for _, qid in ipairs(JULIE_IDS) do
                        QM.questStates[qid] = QM.questStates[qid] or {}
                        QM.questStates[qid].status = QM.STATUS_COMPLETED
                    end
                    local st5 = QM.questStates["side_julie_gem_5"]
                    st5.completedDate = os.date("%Y-%m-%d", GS._getTrustedTime() - 86400 * 2)
                    st5.submittedGems = { "gem_superior_1", "gem_superior_2", "gem_superior_3" }
                    print("[管理员] 已完成朱莉全部任务(宝石鉴赏1~巧作天工二)")
                end
                GS.saveToCloud()
                return
            end
        end

        -- 生活技能等级切换按钮：0→100→200→300→400→500→0
        local lifeBtn = GS.testLifeSkillBtnRect
        if lifeBtn and lifeBtn.w and lifeBtn.w > 0 then
            if hitTest(mx, my, lifeBtn) then
                local curHLv = GS.getLifeSkillHiddenLevel("gathering")
                local cycle = { 0, 100, 200, 300, 400, 500 }
                local nextHLv = 0
                for i, v in ipairs(cycle) do
                    if curHLv == v and i < #cycle then
                        nextHLv = cycle[i + 1]
                        break
                    end
                end
                -- 将隐藏等级拆分为 tier 和 exp
                local newTier = math.floor(nextHLv / GS.LIFE_SKILL_MAX_LEVEL) + 1
                local newExp  = nextHLv % GS.LIFE_SKILL_MAX_LEVEL
                if newTier > GS.LIFE_SKILL_MAX_TIER then
                    newTier = GS.LIFE_SKILL_MAX_TIER
                    newExp  = nextHLv - (newTier - 1) * GS.LIFE_SKILL_MAX_LEVEL
                end
                for _, def in ipairs(GS.LIFE_SKILL_DEFS) do
                    GS.lifeSkillTiers[def.id] = newTier
                    GS.lifeSkillExp[def.id]   = newExp
                end
                print("[管理员] 所有生活技能隐藏等级设为 " .. nextHLv .. "（等阶" .. newTier .. " 经验" .. newExp .. "）")
                GS.saveToCloud()
                return
            end
        end

        -- 上传版本号到排行榜（管理员专用）
        local uvbr = GS.testUploadVersionBtnRect
        if uvbr and uvbr.w and uvbr.w > 0 then
            if hitTest(mx, my, uvbr) then
                local ver = GS.APP_VERSION or "ver0.126"
                -- 将版本字符串转为整数分数（如 "ver0.126" → 126）以写入 iscores
                local major, minor = ver:match("ver(%d+)%.(%d+)")
                local verInt = (tonumber(major) or 0) * 10000 + (tonumber(minor) or 0)
                GS.gmVersionUploadStatus = "uploading"
                clientCloud:SetInt("game_version_required", verInt, {
                    ok = function()
                        GS.gmVersionUploadStatus = "ok"
                        print("[管理员] 版本号已上传: " .. ver .. " (score=" .. verInt .. ")")
                    end,
                    error = function(code, reason)
                        GS.gmVersionUploadStatus = "fail"
                        print("[管理员] 版本号上传失败:", code, reason)
                    end
                })
                return
            end
        end

        -- 签到模式切换按钮：5天模式 ↔ 日常模式
        local simBr = GS.testSignInModeBtnRect
        if simBr and simBr.w and simBr.w > 0 then
            if hitTest(mx, my, simBr) then
                GS.debugForceDay6 = not GS.debugForceDay6
                if GS.debugForceDay6 then
                    SignInSystem.ensureDailyData()
                end
                print("[管理员] 签到模式切换为: " .. (GS.debugForceDay6 and "日常模式(第6天+)" or "5天模式"))
                return
            end
        end

        -- 测试关卡面板内点击（拖动开始）
        if GS.showTestStagePanel and GS.testStagePanelRect then
            local r = GS.testStagePanelRect
            if hitTest(mx, my, r) then
                GS.testStageDragging = true
                GS.testStageDragStartY = my
                GS.testStageDragStartScroll = GS.testStageScrollY
                GS.testStageDragMoved = false
                return
            end
        end

        -- 测试道具面板：滚动条拖动（优先检测）
        if GS.showTestItemPanel and GS.testItemScrollbar then
            local sb = GS.testItemScrollbar
            local hitPad = 4
            if mx >= sb.x - hitPad and mx <= sb.x + sb.w + hitPad
                and my >= sb.y and my <= sb.y + sb.h then
                GS.testItemScrollbarDragging = true
                GS.testItemScrollbarStartY = my
                GS.testItemScrollbarStartScroll = GS.testItemScrollY or 0
                return
            end
        end
        -- 测试道具面板内点击（内容拖动）
        if GS.showTestItemPanel and GS.testItemPanelRect then
            local r = GS.testItemPanelRect
            if hitTest(mx, my, r) then
                GS.testItemDragging = true
                GS.testItemDragStartY = my
                GS.testItemDragStartScroll = GS.testItemScrollY or 0
                GS.testItemDragMoved = false
                return
            end
        end

        -- 点击GM面板内（不关闭）
        local gpx, gpy, gpw, gph = GS.getGMPanelRect()
        if hitTest(mx, my, { x = gpx, y = gpy, w = gpw, h = gph }) then
            return
        end

        -- 点击GM面板外 → 关闭
        GS.showTestStagePanel = false
        GS.showTestItemPanel = false
        GS.showGMPanel = false
        return
    end

    -- 设置面板内：按钮 & 音量滑块交互
    if GS.showSettings then
        -- 返回角色选择界面按钮（所有玩家可点击）
        local cselbr = GS.charSelectBtnRect
        if cselbr and cselbr.w and cselbr.w > 0 then
            if hitTest(mx, my, cselbr) then
                -- 先保存当前进度，再回到角色选择界面
                -- [修复] 使用回调确保保存完成后再切换，防止网络波动导致共享仓库数据竞态
                GS.charSwitchSaving = true  -- 标记正在进行角色切换保存
                GS.saveToCloud({
                    ok = function()
                        GS.charSwitchSaving = false
                        print("[CharSwitch] 存档保存成功，可安全切换角色")
                    end,
                    error = function(reason)
                        GS.charSwitchSaving = false
                        print("[CharSwitch] 存档保存失败: " .. tostring(reason) .. "，仍允许切换")
                    end,
                    timeout = function()
                        GS.charSwitchSaving = false
                        print("[CharSwitch] 存档保存超时，仍允许切换")
                    end,
                })
                -- [修复] saveToCloud 已同步读取 charSlotIndex 确定目标 key，
                -- 立即清除 charSlotIndex，防止：
                --   1. createNewCharacter 的防御性 saveToCloud 用残留的 slotIndex + 已被 changeClass 修改的 currentClass 覆盖原存档
                --   2. 任何其他意外路径在角色选择界面期间触发保存
                GS.charSlotIndex = nil
                GS.showSettings = false
                GS.showTestStagePanel = false
                GS.showTestItemPanel = false
                if GS.isDungeon then
                    DungeonManager.exit()
                end
                -- 彻底清理场景状态，防止重新进入角色时残留旧场景/UI
                GS.homeMode = false
                GS.warehouseMode = false
                GS.sharedStorageMode = false
                GS.dragSharedStorageIdx = nil
                GS.lostItemsMode = false
                GS.autoSave.enabled = false
                BoardOverlay.hide()

                -- 对话管理器重置（修复：NPC对话在切换角色后残留）
                local DM = require("DialogueManager")
                DM.active = false
                DM.currentId = nil
                DM.currentLines = nil
                DM.lineIndex = 0
                DM.waitingForChoice = false
                DM.choiceResult = nil
                DM._dynamicOnComplete = nil

                -- 兑换商店重置
                GS.exchangeMode = false
                GS.exchangeBuyConfirmVisible = false

                -- 广告加载状态重置
                GS.adLoading = false

                -- 弹窗状态重置
                GS.houseBuyDialogVisible = false
                GS.houseBuySuccessVisible = false
                GS.destroyConfirmVisible = false
                GS.shopBuyConfirmVisible = false
                GS.skillEquipPopupVisible = false

                -- 其他 UI 模式重置
                GS.shopMode = false
                GS.enhanceMode = false
                GS.repairMode = false
                GS.forgeMode = false
                GS.homeForgeMode = false
                GS.alchemyMode = false
                GS.homeAlchemyMode = false
                GS.homeCookingMode = false
                GS.homeSmithySelectMode = false
                GS.homeSmithySelectRects = nil
                GS.homeCraftMode = false
                GS.homeSocketMode = false
                GS.homeEnchantMode = false
                GS.enchantMode = false
                GS.enchantSlotItem = nil
                GS.enchantSlotSource = nil
                GS.enchantSlotSourceId = nil
                GS.enchantResult = nil
                GS.refineMode = false
                GS.craftMode = false
                GS.socketMode = false
                GS.trainingMode = false

                -- 拖拽状态重置
                GS.itemDragActive = false
                GS.dragSlotIdx = nil

                -- 提示框重置
                GS.tooltipItem = nil
                GS.tooltipPinned = false
                GS.skillTooltipId = nil
                GS.skillTooltipPinned = false

                -- [修复] 重置角色选择界面弹窗状态，防止残留 charNewConfirmSlot 拦截后续操作
                GS.charNewConfirmSlot = nil
                GS.charDeleteStep    = 0
                GS.charDeleteSlotIdx = nil
                GS.charDeleteTimer   = 0
                GS.gameState = GS.STATE_CHAR_SELECT
                return
            end
        end

        -- 音量滑块
        local trackX, trackY, trackW, trackH = GS.getSliderTrackRect()
        local hitPad = GS.SLIDER_KNOB_R + 4
        if mx >= trackX - hitPad and mx <= trackX + trackW + hitPad
            and my >= trackY - hitPad and my <= trackY + hitPad then
            GS.masterVolume = math.max(0, math.min(1, (mx - trackX) / trackW))
            GS.volumeSliderDragging = true
            return
        end

        -- 横竖屏开关点击
        if GS.orientToggleRect and hitTest(mx, my, GS.orientToggleRect) then
            GS.forceLandscape = not GS.forceLandscape
            GS.applyScreenOrientation()
            GS.saveOrientationToCloud()
            return
        end

        -- 动画开关点击
        if GS.animToggleRect and hitTest(mx, my, GS.animToggleRect) then
            GS.animationEnabled = not GS.animationEnabled
            GS.saveAnimationToggleToCloud()
            return
        end

        -- 伤害飘字开关点击
        if GS.dmgNumbersToggleRect and hitTest(mx, my, GS.dmgNumbersToggleRect) then
            GS.showDamageNumbers = not GS.showDamageNumbers
            GS.saveDamageNumbersToggleToCloud()
            return
        end

        -- 屏幕震动开关点击
        if GS.shakeToggleRect and hitTest(mx, my, GS.shakeToggleRect) then
            GS.enableScreenShake = not GS.enableScreenShake
            GS.saveScreenShakeToggleToCloud()
            return
        end

        -- 手动保存按钮点击（最少间隔10秒）
        if GS._manualSaveBtnRect and hitTest(mx, my, GS._manualSaveBtnRect) then
            if GS.cloudSaveStatus ~= "saving" then
                local now = GetTime():GetElapsedTime()
                local cd = 3 - (now - (GS._lastManualSaveTime or 0))
                if cd > 0 then
                    GS.shopBuyMsg = { text = "请等待" .. math.ceil(cd) .. "秒后再保存", timer = 1.5, color = {220, 180, 40} }
                else
                    GS._lastManualSaveTime = now
                    GS.saveToCloud({
                        ok = function()
                            GS.shopBuyMsg = { text = "保存成功", timer = 2.0, color = {80, 220, 120} }
                        end,
                        error = function(reason)
                            GS.shopBuyMsg = { text = "保存失败: " .. (reason or "未知错误"), timer = 3.0, color = {220, 60, 40} }
                        end,
                    })
                end
            end
            return
        end

        -- 兑换码按钮点击
        if GS._redeemCodeBtnRect and hitTest(mx, my, GS._redeemCodeBtnRect) then
            GS.redeemCodeInput = { active = true, text = "", imeComposing = false, imeComposition = nil }
            input:SetScreenKeyboardVisible(true)
            return
        end

        -- 修改姓名按钮点击
        if GS._renameBtnRect and hitTest(mx, my, GS._renameBtnRect) then
            GS.renameInput = {
                active = true,
                text = GS.charName or "",
                imeComposing = false,
                imeComposition = nil,
            }
            GS.showSettings = false
            input:SetScreenKeyboardVisible(true)
            return
        end

        -- 息屏挂机按钮点击
        if GS._screenOffBtnRect and hitTest(mx, my, GS._screenOffBtnRect) then
            GS.screenOffMode = true
            GS.showSettings = false
            return
        end

        -- 脱离卡死按钮点击
        if GS._unstuckBtnRect and hitTest(mx, my, GS._unstuckBtnRect) then
            local DM = require("Dungeon.DungeonManager")
            if DM.isActive() then
                GS._unstuckConfirmVisible = true
                GS.showSettings = false
            end
            return
        end

        local px, py, pw, ph = GS.getSettingsPanelRect()
        if hitTest(mx, my, { x = px, y = py, w = pw, h = ph }) then
            return
        end

        -- 点击了设置面板外 → 关闭
        GS.showSettings = false
        return
    end

    if GS.gameState == GS.STATE_MENU then
        -- 预加载还在进行中，忽略点击
        if GS.preloadStatus == "loading" then return end
        -- 存档预加载失败：重新触发加载，不进入角色选择，防止误建角色覆盖云端存档
        if GS.preloadStatus == "error" then
            print("[Menu] 存档加载失败，重新尝试预加载")
            GS.preloadCloudSave()
            return
        end
        -- 检测旧存档需要迁移
        if GS.cachedLegacySaveData then
            GS.migrateLegacySave(function(ok)
                if ok then
                    GS.gameState = GS.STATE_CHAR_SELECT
                end
            end)
            return
        end
        -- 进入角色选择界面
        GS.gameState = GS.STATE_CHAR_SELECT
        return
    end

    if GS.gameState == GS.STATE_CHAR_SELECT then
        M.handleCharSelectClick(mx, my)
        return
    end

    if GS.gameState == GS.STATE_CHAR_CREATE then
        M.handleCharCreateClick(mx, my)
        return
    end

    if GS.gameState == GS.STATE_GAMEOVER then
        -- 死亡时点击关闭悬停面板
        if GS.tooltipItem then GS.closeTooltip(); return end
        if GS.skillTooltipId then GS.closeSkillTooltip(); return end
        -- 死亡时允许关闭设置面板和自动战斗设置面板
        if GS.showSettings then
            GS.showSettings = false
            GS.showTestStagePanel = false
            return
        end
        if GS.showAutoBattleSettings then
            GS.showAutoBattleSettings = false
            GS.autoConsumablePopupSlot = nil
            GS.autoConsumablePopupItems = {}
            GS.autoFoodBuffPopupSlot = nil
            GS.autoFoodBuffPopupItems = {}
            return
        end
        -- [修复] 重置角色选择界面弹窗状态
        GS.charNewConfirmSlot = nil
        GS.charDeleteStep    = 0
        GS.charDeleteSlotIdx = nil
        GS.charDeleteTimer   = 0
        GS.gameState = GS.STATE_CHAR_SELECT
        return
    end

    -- 自动设置按钮点击检测（覆盖层模式下禁用）
    if not BoardOverlay.isActive() and GS.autoBattleSettingsBtnRect then
        local r = GS.autoBattleSettingsBtnRect
        if hitTest(mx, my, r) then
            GS.showAutoBattleSettings = not GS.showAutoBattleSettings
            if not GS.showAutoBattleSettings then
                GS.autoConsumablePopupSlot = nil
                GS.autoConsumablePopupItems = {}
                GS.autoFoodBuffPopupSlot = nil
                GS.autoFoodBuffPopupItems = {}
            end
            return
        end
    end

    -- 自动设置面板打开时的点击处理
    if GS.showAutoBattleSettings then
        -- 1) 消耗品选择弹窗打开时优先处理
        if GS.autoConsumablePopupSlot then
            -- 点击弹窗内的物品
            for _, rect in ipairs(GS.autoConsumablePopupItemRects or {}) do
                if hitTest(mx, my, rect) then
                    if rect.unequip then
                        GS.autoConsumables[GS.autoConsumablePopupSlot] = nil
                    elseif rect.item then
                        GS.autoConsumables[GS.autoConsumablePopupSlot] = rect.item.templateId
                    end
                    GS.autoConsumablePopupSlot = nil
                    GS.autoConsumablePopupItems = {}
                    GS.autoConsumablePopupRect = nil
                    GS.autoConsumablePopupItemRects = {}
                    return
                end
            end
            -- 点击弹窗外部关闭弹窗
            local popR = GS.autoConsumablePopupRect
            if popR and not hitTest(mx, my, popR) then
                GS.autoConsumablePopupSlot = nil
                GS.autoConsumablePopupItems = {}
                GS.autoConsumablePopupRect = nil
                GS.autoConsumablePopupItemRects = {}
                return
            end
            return
        end

        -- 1.5) 食物/增强药剂选择弹窗打开时优先处理
        if GS.autoFoodBuffPopupSlot then
            -- 点击弹窗内的物品
            for _, rect in ipairs(GS.autoFoodBuffPopupItemRects or {}) do
                if hitTest(mx, my, rect) then
                    if rect.unequip then
                        if GS.autoFoodBuffPopupSlot == "food" then
                            GS.autoFood = nil
                        else
                            GS.autoBuffPotion = nil
                        end
                    elseif rect.item then
                        if GS.autoFoodBuffPopupSlot == "food" then
                            GS.autoFood = rect.item.templateId
                        else
                            GS.autoBuffPotion = rect.item.templateId
                        end
                    end
                    GS.autoFoodBuffPopupSlot = nil
                    GS.autoFoodBuffPopupItems = {}
                    GS.autoFoodBuffPopupRect = nil
                    GS.autoFoodBuffPopupItemRects = {}
                    return
                end
            end
            -- 点击弹窗外部关闭弹窗
            local popR = GS.autoFoodBuffPopupRect
            if popR and not hitTest(mx, my, popR) then
                GS.autoFoodBuffPopupSlot = nil
                GS.autoFoodBuffPopupItems = {}
                GS.autoFoodBuffPopupRect = nil
                GS.autoFoodBuffPopupItemRects = {}
                return
            end
            return
        end

        -- 2) 点击消耗品槽位 → 打开选择弹窗
        for i = 1, GS.AUTO_CONSUMABLE_SLOTS do
            local r = GS.autoConsumableSlotAreas[i]
            if hitTest(mx, my, r) then
                local statFilter = GS.AUTO_CONSUMABLE_SLOT_STAT[i]
                local playerLevel = GS.player and GS.player.level or 1
                local candidates = {}
                local seen = {}
                for si = 1, GS.bagSlots do
                    local item = GS.inventory[si]
                    if item and type(item.consumable) == "table" and item.consumable.stat == statFilter
                       and (item.level or 1) <= playerLevel then
                        local tid = item.templateId or item.name
                        if seen[tid] then
                            seen[tid].quantity = (seen[tid].quantity or 1) + (item.quantity or 1)
                        else
                            local entry = {}
                            for k, v in pairs(item) do entry[k] = v end
                            entry.quantity = item.quantity or 1
                            seen[tid] = entry
                            candidates[#candidates + 1] = entry
                        end
                    end
                end
                -- 按等级从高到低排序
                table.sort(candidates, function(a, b)
                    return (a.level or 0) > (b.level or 0)
                end)
                GS.autoConsumablePopupSlot = i
                GS.autoConsumablePopupItems = candidates
                GS.autoConsumablePopupRect = nil
                GS.autoConsumablePopupItemRects = {}
                return
            end
        end

        -- 2.5) 点击阈值按钮 → 循环切换百分比
        for i = 1, GS.AUTO_CONSUMABLE_SLOTS do
            local r = GS.autoConsumableThresholdBtnAreas[i]
            if hitTest(mx, my, r) then
                local cur = GS.autoConsumableThresholds[i] or 50
                -- 循环: 30 → 50 → 70 → 90 → 30
                local steps = { 30, 50, 70, 90 }
                local nextIdx = 1
                for si = 1, #steps do
                    if steps[si] == cur then
                        nextIdx = (si % #steps) + 1
                        break
                    end
                end
                GS.autoConsumableThresholds[i] = steps[nextIdx]
                return
            end
        end

        -- 2.8) 点击食物槽位 → 打开食物选择弹窗
        if GS.autoFoodSlotArea then
            local r = GS.autoFoodSlotArea
            if hitTest(mx, my, r) then
                local candidates = {}
                local seen = {}
                for si = 1, GS.bagSlots do
                    local item = GS.inventory[si]
                    if item then
                        local tpl = GS.itemTemplates[item.templateId]
                        if tpl and tpl.useEffect == "food" then
                            local tid = item.templateId
                            if seen[tid] then
                                seen[tid].quantity = (seen[tid].quantity or 1) + (item.quantity or 1)
                            else
                                local entry = {}
                                for k, v in pairs(item) do entry[k] = v end
                                entry.quantity = item.quantity or 1
                                seen[tid] = entry
                                candidates[#candidates + 1] = entry
                            end
                        end
                    end
                end
                table.sort(candidates, function(a, b)
                    return (a.level or 0) > (b.level or 0)
                end)
                GS.autoFoodBuffPopupSlot = "food"
                GS.autoFoodBuffPopupItems = candidates
                GS.autoFoodBuffPopupRect = nil
                GS.autoFoodBuffPopupItemRects = {}
                return
            end
        end

        -- 2.9) 点击增强药剂槽位 → 打开增强药剂选择弹窗
        if GS.autoBuffPotionSlotArea then
            local r = GS.autoBuffPotionSlotArea
            if hitTest(mx, my, r) then
                local candidates = {}
                local seen = {}
                for si = 1, GS.bagSlots do
                    local item = GS.inventory[si]
                    if item and item.consumable and item.consumable.stat then
                        local stat = item.consumable.stat
                        if stat ~= "hp" and stat ~= "mp" and stat:sub(1, 5) == "buff_" then
                            local tid = item.templateId
                            if seen[tid] then
                                seen[tid].quantity = (seen[tid].quantity or 1) + (item.quantity or 1)
                            else
                                local entry = {}
                                for k, v in pairs(item) do entry[k] = v end
                                entry.quantity = item.quantity or 1
                                seen[tid] = entry
                                candidates[#candidates + 1] = entry
                            end
                        end
                    end
                end
                table.sort(candidates, function(a, b)
                    return (a.level or 0) > (b.level or 0)
                end)
                GS.autoFoodBuffPopupSlot = "buffPotion"
                GS.autoFoodBuffPopupItems = candidates
                GS.autoFoodBuffPopupRect = nil
                GS.autoFoodBuffPopupItemRects = {}
                return
            end
        end

        -- 3) 点击技能槽 → 打开装备弹窗
        if GS.activeSkillSlotAreas then
            for i, r in pairs(GS.activeSkillSlotAreas) do
                if hitTest(mx, my, r) then
                    GS.closeSkillTooltip()
                    GS.skillEquipPopupVisible = true
                    GS.skillEquipPopupSlot = i
                    return
                end
            end
        end

        -- 4) 点击面板外部关闭面板
        local pr = GS.autoBattleSettingsPanelRect
        if pr and not hitTest(mx, my, pr) then
            GS.showAutoBattleSettings = false
            GS.autoConsumablePopupSlot = nil
            GS.autoConsumablePopupItems = {}
            GS.autoFoodBuffPopupSlot = nil
            GS.autoFoodBuffPopupItems = {}
            return
        end
        return
    end

    -- 自动按钮点击检测
    if GS.autoBtnRect then
        local r = GS.autoBtnRect
        if hitTest(mx, my, r) then
            GS.autoMode = not GS.autoMode
            GS.autoTimer = 0
            if GS.autoMode then
                -- 对话/过场期间不触发回合结束（防止竞技场播报中开启自动导致怪物先行动）
                local DialogueManager = require("DialogueManager")
                local skipEndTurn = false
                if DialogueManager.active or GS.arenaTransition then
                    skipEndTurn = true
                end
                -- 采集区无怪物时不触发回合结束（防止连续开关加速时间流逝）
                local curStageAuto = GS.STAGE_DEFS[GS.currentStage]
                if not skipEndTurn and curStageAuto and curStageAuto.noRespawn then
                    local hasEnemyAuto = false
                    for _, m in ipairs(GS.monsters) do
                        if m.hp > 0 then hasEnemyAuto = true; break end
                    end
                    if not hasEnemyAuto then skipEndTurn = true end
                end

                -- 判断玩家本回合是否已移动
                if not skipEndTurn
                    and (GS.gameState == GS.STATE_PLAYER or GS.gameState == GS.STATE_SELECT)
                    and GS.player and GS.player.hp > 0 and not GS.player.acted then

                    local playerHasMoved = (GS.turnPhase ~= GS.PHASE_MOVE)

                    -- 移动动画中（已选择移动位置但未确认行动）视为未移动，返回原位
                    if Combat.pendingManualAction then
                        local pm = Combat.pendingManualAction
                        Combat.pendingManualAction = nil
                        GS.player.x = pm.oldX
                        GS.player.y = pm.oldY
                        GS.player.moveAnim = nil
                        GS.turnPhase = GS.PHASE_MOVE
                        GS.gameState = GS.STATE_PLAYER
                        playerHasMoved = false
                        -- 地狱踏：撤销移动时清除本次放置的燃烧地面
                        if GS._hellStompPlaced then
                            for _, p in ipairs(GS._hellStompPlaced) do
                                for j = #GS.burningGrounds, 1, -1 do
                                    local bg = GS.burningGrounds[j]
                                    if bg.x == p.x and bg.y == p.y and bg.hellStomp then
                                        table.remove(GS.burningGrounds, j)
                                        break
                                    end
                                end
                            end
                            GS._hellStompPlaced = nil
                        end
                    end

                    GS.closeActionMenu()

                    -- 未移动时需要确保 gameState 正确，processAutoCombat 要求 STATE_PLAYER
                    if not playerHasMoved and GS.gameState == GS.STATE_SELECT then
                        GS.gameState = GS.STATE_PLAYER
                    end

                    if playerHasMoved then
                        -- 已移动过：结束当前回合
                        GS.turnPhase = GS.PHASE_END
                        GS.player.acted = true
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        Combat.endPlayerTurn()
                    else
                        -- 未移动：交给 processAutoCombat 正常进行自动回合
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                    end
                else
                    GS.closeActionMenu()
                    GS.selectedUnit = nil
                    GS.movableCells = {}
                    GS.attackableCells = {}
                    -- skipEndTurn 等情况下 gameState 可能仍是 STATE_SELECT，需重置
                    if GS.gameState == GS.STATE_SELECT then
                        GS.gameState = GS.STATE_PLAYER
                    end
                end
            else
                -- 取消自动战斗：法师回合中途恢复手动操作
                if GS.gameState == GS.STATE_PLAYER
                    and GS.player and GS.player.hp > 0 and not GS.player.acted then
                    -- 法师有剩余吟唱段数：打开行动菜单继续手动操作
                    if (GS.currentClass == "mage" or GS.currentClass == "priest") and (GS.chantStages or 0) > 0
                        and not GS.chanting then
                        GS.selectedUnit = GS.player
                        GS.gameState = GS.STATE_SELECT
                        GS.mageCheckContinueTurn()
                    end
                end
            end
            return
        end
    end

    -- 训练场统计面板展开/收起按钮
    if GS.trainingMode and GS.trainingToggleBtnRect then
        if hitTest(mx, my, GS.trainingToggleBtnRect) then
            GS.trainingStatsExpanded = not GS.trainingStatsExpanded
            return
        end
    end

    -- 训练场重置按钮点击检测
    if GS.trainingMode and GS.trainingResetBtnRect then
        if hitTest(mx, my, GS.trainingResetBtnRect) then
            GS.trainingDmgLog = {}
            GS.trainingTurnDmg = 0
            GS.trainingTotalDmg = 0
            GS.trainingTurnCount = 0
            return
        end
    end

    -- 训练假人等级调整按钮
    if GS.trainingMode then
        if GS.trainingLevelDownBtnRect and hitTest(mx, my, GS.trainingLevelDownBtnRect) then
            if GS.trainingDummyTierIdx > 1 then
                GS.trainingDummyTierIdx = GS.trainingDummyTierIdx - 1
                GS.applyDummyTier()
                -- 重置统计
                GS.trainingDmgLog = {}
                GS.trainingTurnDmg = 0
                GS.trainingTotalDmg = 0
                GS.trainingTurnCount = 0
            end
            return
        end
        if GS.trainingLevelUpBtnRect and hitTest(mx, my, GS.trainingLevelUpBtnRect) then
            if GS.trainingDummyTierIdx < #GS.TRAINING_DUMMY_TIERS then
                GS.trainingDummyTierIdx = GS.trainingDummyTierIdx + 1
                GS.applyDummyTier()
                -- 重置统计
                GS.trainingDmgLog = {}
                GS.trainingTurnDmg = 0
                GS.trainingTotalDmg = 0
                GS.trainingTurnCount = 0
            end
            return
        end
    end

    -- 怪物增益&减益按钮点击 & 面板内点击
    if GS.monsterBuffBtnRect and hitTest(mx, my, GS.monsterBuffBtnRect) then
        GS.showMonsterBuffSummary = not GS.showMonsterBuffSummary
        GS.monsterBuffScrollY = 0
        return
    end
    if GS.showMonsterBuffSummary then
        if GS.monsterBuffPanelRect and hitTest(mx, my, GS.monsterBuffPanelRect) then
            -- 面板内点击：启动滚动拖拽
            GS.monsterBuffDragging = true
            GS.monsterBuffDragStartY = my
            GS.monsterBuffDragStartScroll = GS.monsterBuffScrollY or 0
            return
        end
        -- 点击面板外 → 关闭面板
        GS.showMonsterBuffSummary = false
    end

    -- BUFF/DEBUFF总结面板：按钮点击 & 面板内滚动拖拽
    if GS.activeBottomTab == 1 then
        -- 点击"状态"按钮 → 切换面板
        if GS.buffSummaryBtnRect and hitTest(mx, my, GS.buffSummaryBtnRect) then
            GS.showBuffSummary = not GS.showBuffSummary
            GS.buffSummaryScrollY = 0
            return
        end
        -- 面板打开时，面板区域内的点击作为滚动拖拽起始
        if GS.showBuffSummary and GS.buffSummaryClipRect then
            local cr = GS.buffSummaryClipRect
            if hitTest(mx, my, cr) then
                GS.buffSummaryDragging = true
                GS.buffSummaryDragStartY = my
                GS.buffSummaryDragStartScroll = GS.buffSummaryScrollY or 0
                return
            end
            -- 点击面板区域外（但在角色面板内）→ 关闭面板
            -- 不 return，让后续逻辑继续处理
            GS.showBuffSummary = false
        end
    end

    -- 属性感叹号点击（锁定/解锁提示）
    if GS.activeBottomTab == 1 then
        local hitInfo = false
        for statKey, r in pairs(GS.statInfoBtnRects or {}) do
            if hitTest(mx, my, r) then
                if GS.statInfoLocked == statKey then
                    GS.statInfoLocked = nil  -- 再次点击同一个，解锁
                else
                    GS.statInfoLocked = statKey  -- 锁定
                end
                hitInfo = true
                break
            end
        end
        -- 点击其他区域时关闭锁定的提示
        if not hitInfo and GS.statInfoLocked then
            GS.statInfoLocked = nil
            return
        end
        if hitInfo then return end

        -- 右侧属性汇总感叹号点击（锁定/解锁提示）
        local hitCombatInfo = false
        for statName, r in pairs(GS.combatStatInfoBtnRects or {}) do
            if hitTest(mx, my, r) then
                if GS.combatStatInfoLocked == statName then
                    GS.combatStatInfoLocked = nil
                else
                    GS.combatStatInfoLocked = statName
                end
                hitCombatInfo = true
                break
            end
        end
        if not hitCombatInfo and GS.combatStatInfoLocked then
            GS.combatStatInfoLocked = nil
            return
        end
        if hitCombatInfo then return end
    end

    -- 加点按钮点击（仅在角色Tab下，单项上限100）+ 记录长按状态
    if GS.activeBottomTab == 1 and GS.player and GS.player.statPoints and GS.player.statPoints > 0 then
        for statKey, r in pairs(GS.statAddBtnRects) do
            if hitTest(mx, my, r) then
                local curVal = GS.player.stats[statKey] or 0
                if curVal >= 100 then return end  -- 加点上限100
                GS.player.stats[statKey] = curVal + 1
                GS.player.statPoints = GS.player.statPoints - 1
                GS.recalcStats(GS.player)
                -- 开始长按追踪
                statHoldKey = statKey
                statHoldTimer = 0
                statHoldInterval = 0
                return
            end
        end
    end



    -- 背包操作按钮（整理/多选 或 取消/N/UC/R/销毁）
    if GS.activeBottomTab == 2 and GS.invActionBtnRects then
        for key, r in pairs(GS.invActionBtnRects) do
            if hitTest(mx, my, r) then
                if GS.invMultiSelect then
                    if key == "btn1" then
                        -- 取消
                        GS.invMultiSelect = false
                        GS.invSelected = {}
                    elseif key == "btn2" then
                        if GS.warehouseMode then
                            -- 仓库模式：批量存入仓库
                            local selCount = 0
                            for _ in pairs(GS.invSelected) do selCount = selCount + 1 end
                            if selCount > 0 then
                                GS.batchStoreToWarehouse(GS.invSelected)
                                GS.invMultiSelect = false
                                GS.invSelected = {}
                            end
                        elseif GS.sharedStorageMode then
                            -- 共享仓库模式：批量存入共享仓库
                            local selCount = 0
                            for _ in pairs(GS.invSelected) do selCount = selCount + 1 end
                            if selCount > 0 then
                                GS.batchStoreToSharedStorage(GS.invSelected)
                                GS.invMultiSelect = false
                                GS.invSelected = {}
                            end
                        else
                            -- 销毁/出售：弹出确认弹窗
                            local selCount = 0
                            for _ in pairs(GS.invSelected) do selCount = selCount + 1 end
                            if selCount > 0 then
                                if GS.craftMode then
                                    GS.shopBuyMsg = { text = "销毁前请关闭委托加工界面", timer = 2.0, color = {220, 60, 40} }
                                elseif GS.enchantMode then
                                    GS.shopBuyMsg = { text = "销毁前请关闭委托镶嵌界面", timer = 2.0, color = {220, 60, 40} }
                                elseif GS.socketMode then
                                    GS.shopBuyMsg = { text = "销毁前请关闭宝石镶嵌界面", timer = 2.0, color = {220, 60, 40} }
                                else
                                    GS.destroyConfirmVisible = true
                                    GS.destroyConfirmBatch = true
                                    GS.destroyConfirmItem = { name = selCount .. "件物品", rarity = "common" }
                                    GS.destroyConfirmSlotIdx = nil
                                end
                            end
                        end
                    elseif key == "btnN" or key == "btnUC" or key == "btnR" or key == "btnF" then
                        -- 稀有度一键全选（仅选中常规关卡怪物掉落的材料和装备）
                        -- 构建采集/锻造材料排除集合（懒初始化）
                        if not GS._gatherForgeMats then
                            local s = {}
                            -- 采集产出物（矿石、草药、晶矿）
                            for _, def in pairs(GS.GATHER_DEFS) do
                                if def.itemId then s[def.itemId] = true end
                                if def.drops then
                                    for _, d in ipairs(def.drops) do
                                        if d.itemId then s[d.itemId] = true end
                                    end
                                end
                            end
                            -- 锻造产出物（锭）和输入物（矿石/晶矿）
                            for _, recipe in ipairs(GS.FORGE_RECIPES) do
                                if recipe.inputId then s[recipe.inputId] = true end
                                if recipe.outputId then s[recipe.outputId] = true end
                            end
                            -- 生肉、露水精华
                            for _, mid in ipairs({"raw_wolf","raw_pork","raw_chicken","raw_turtle","raw_lion","dew_essence"}) do
                                s[mid] = true
                            end
                            -- 精炼石（2~10阶），不应被稀有度一键选中
                            for tier = 2, 10 do
                                s["refine_stone_" .. tier] = true
                            end
                            -- 酒馆商店中的材料类物品（烹饪原料等）
                            if GS.SHOP_INVENTORY and GS.SHOP_INVENTORY.tavern then
                                for _, entry in ipairs(GS.SHOP_INVENTORY.tavern) do
                                    local tmpl = GS.itemTemplates and GS.itemTemplates[entry.templateId]
                                    if tmpl and tmpl.category == "材料" then
                                        s[entry.templateId] = true
                                    end
                                end
                            end
                            GS._gatherForgeMats = s
                        end
                        local rarityMap = { btnN = "common", btnUC = "uncommon", btnR = "rare", btnF = "fine" }
                        local targetRarity = rarityMap[key]
                        for i = 1, GS.bagSlots do
                            local item = GS.inventory[i]
                            if item and (item.rarity or "common") == targetRarity and not item.locked then
                                local cat = item.category
                                local itemId = item.templateId or item.id
                                if item.slot then
                                    -- 装备：直接选中
                                    GS.invSelected[i] = true
                                elseif cat == "宝石" then
                                    -- 宝石：直接选中
                                    GS.invSelected[i] = true
                                elseif cat == "材料" and not GS._gatherForgeMats[itemId] then
                                    -- 材料：排除采集/锻造产出物，仅选怪物掉落材料
                                    -- 精炼石(category="material" 英文)不在此列，不会被选中
                                    GS.invSelected[i] = true
                                end
                            end
                        end
                    end
                else
                    if key == "btn1" then
                        -- 整理
                        GS.sortInventory()
                        GS.lootFilterVisible = false
                    elseif key == "btn2" then
                        -- 多选（重置排除集合缓存，确保每次进入多选都用最新配置）
                        GS._gatherForgeMats = nil
                        GS.invMultiSelect = true
                        GS.invSelected = {}
                        GS.lootFilterVisible = false
                        GS.closeTooltip()
                    elseif key == "btn3" then
                        -- 拾取过滤：切换面板展开/收起
                        GS.lootFilterVisible = not GS.lootFilterVisible
                        return
                    end
                end
                return
            end
        end
    end

    -- 拾取过滤面板：勾选框点击
    if GS.activeBottomTab == 2 and GS.lootFilterVisible then
        if GS.lootFilterCheckRect and hitTest(mx, my, GS.lootFilterCheckRect) then
            GS.lootFilterNoFine = not GS.lootFilterNoFine
            return
        end
        if GS.lootFilterCheckRectRare and hitTest(mx, my, GS.lootFilterCheckRectRare) then
            GS.lootFilterNoRare = not GS.lootFilterNoRare
            return
        end
        if GS.lootFilterCheckRectFine and hitTest(mx, my, GS.lootFilterCheckRectFine) then
            GS.lootFilterNoFineGrade = not GS.lootFilterNoFineGrade
            return
        end
        -- 点击面板外区域关闭
        if GS.lootFilterPanelRect and not hitTest(mx, my, GS.lootFilterPanelRect) then
            if GS.invActionBtnRects.btn3 and not hitTest(mx, my, GS.invActionBtnRects.btn3) then
                GS.lootFilterVisible = false
            end
        end
    end

    -- 装备槽点击/拖拽起始检测（在背包Tab下，装备栏已移到背包界面左侧）
    -- 购买弹窗打开时屏蔽装备槽交互
    if GS.activeBottomTab == 2 and GS.equipSlotAreas and not GS.shopBuyConfirmVisible then
        for slotId, r in pairs(GS.equipSlotAreas) do
            if hitTest(mx, my, r) then
                local equipped = GS.equipment[slotId]
                if equipped then
                    -- 记录拖拽起始（装备槽）
                    GS.dragEquipSlotId = slotId
                    GS.dragSlotIdx = nil
                    GS.itemDragActive = false
                    GS.itemDragStartX = mx
                    GS.itemDragStartY = my
                    GS.invDragging = true
                    GS.invDragStartY = my
                    GS.invDragStartScroll = GS.invScrollY or 0
                    GS.invDragMoved = false
                else
                    GS.closeTooltip()
                end
                return
            end
        end
    end

    -- 角色面板属性汇总：分页按钮点击（按钮在滚动区域上方，独立检测）
    if GS.activeBottomTab == 1 then
        if GS._statsTabAtkRect and hitTest(mx, my, GS._statsTabAtkRect) then
            GS.statsTabMode = "attack"
            GS.charStatScrollY = 0
            return
        end
        if GS._statsTabDefRect and hitTest(mx, my, GS._statsTabDefRect) then
            GS.statsTabMode = "defense"
            GS.charStatScrollY = 0
            return
        end
    end

    -- 角色面板属性汇总区域：滚动
    if GS.activeBottomTab == 1 and GS.charStatScrollRect then
        local r = GS.charStatScrollRect
        if hitTest(mx, my, r) then
            GS.charStatDragging = true
            GS.charStatDragStartY = my
            GS.charStatDragStartScroll = GS.charStatScrollY or 0
            return
        end
    end

    -- 日志面板：展开/收起按钮
    if GS.activeBottomTab == 4 and GS.journalToggleBtnRects then
        for secIdx, r in ipairs(GS.journalToggleBtnRects) do
            if hitTest(mx, my, r) then
                GS.journalSectionExpanded[secIdx] = not GS.journalSectionExpanded[secIdx]
                return
            end
        end
    end

    -- 日志面板：提交任务按钮
    if GS.activeBottomTab == 4 and GS.journalSubmitBtnRects then
        for _, r in ipairs(GS.journalSubmitBtnRects) do
            if hitTest(mx, my, r) then
                if r.questType == "main" then
                    -- 主线/支线任务提交
                    local QuestManager = require("QuestManager")
                    QuestManager.submitQuest(r.questId)
                elseif r.questType == "bulletin" then
                    -- 委托任务提交
                    local BulletinBoard = require("BulletinBoard")
                    local ok = BulletinBoard.submitComplete(r.questIdx)
                    if ok then
                        BoardOverlay.triggerStampAnim(r.questIdx)
                    end
                end
                return
            end
        end
    end

    -- 日志面板滚动
    if GS.activeBottomTab == 4 and GS.journalScrollRect then
        local r = GS.journalScrollRect
        if hitTest(mx, my, r) then
            GS.journalDragging = true
            GS.journalDragStartY = my
            GS.journalDragStartScroll = GS.journalScrollY or 0
            return
        end
    end

    -- 技能悬停面板锁定态拦截
    if (GS.activeBottomTab == 3 or GS.showAutoBattleSettings) and GS.skillTooltipPinned then
        -- 点击 tooltip 面板内部
        if GS.skillTooltipRect then
            local tr = GS.skillTooltipRect
            if hitTest(mx, my, tr) then
                -- 检测加点按钮点击
                if GS.skillLevelUpBtnRect and hitTest(mx, my, GS.skillLevelUpBtnRect) then
                    local sid = GS.skillTooltipId
                    if sid then
                        local slv = GS.skillLevels[sid] or 0
                        if GS.skillPoints > 0 and slv < GS.SKILL_MAX_LEVEL then
                            GS.skillLevels[sid] = slv + 1
                            GS.skillPoints = GS.skillPoints - 1
                            if GS.player then GS.recalcStats(GS.player) end
                            -- 猎犬相关：首次学习时生成，已有时原地刷新属性
                            if sid == "h_hound" and slv == 0 then
                                GS.spawnHound()
                            elseif (GS.skillLevels["h_hound"] or 0) > 0 then
                                GS.refreshHoundStats()
                            end
                        end
                    end
                end
                return
            end
        end
        -- 点击技能图标 → 切换 tooltip 或穿透到加点逻辑
        local hitSkill = false
        local sameSkilHit = false
        if GS.skillSlotAreas then
            for skillId, r in pairs(GS.skillSlotAreas) do
                if hitTest(mx, my, r) then
                    if skillId == GS.skillTooltipId then
                        -- 点击的是当前 tooltip 对应的同一个技能，穿透到下方加点逻辑
                        sameSkilHit = true
                    else
                        GS.skillTooltipId = skillId
                        GS.skillTooltipSource = "tree"
                        GS.skillTooltipSlotIdx = nil
                    end
                    hitSkill = true
                    break
                end
            end
        end
        if not hitSkill and GS.showAutoBattleSettings and GS.activeSkillSlotAreas then
            for i, r in pairs(GS.activeSkillSlotAreas) do
                if hitTest(mx, my, r) then
                    if GS.activeSkills[i] then
                        GS.skillTooltipId = GS.activeSkills[i]
                        GS.skillTooltipSource = "slot"
                        GS.skillTooltipSlotIdx = i
                        hitSkill = true
                    end
                    break
                end
            end
        end
        if sameSkilHit then
            -- 同一个技能：保持 tooltip 显示即可（加点通过 tooltip 内按钮完成）
            return
        elseif not hitSkill then
            -- 点击面板外部 → 关闭 tooltip
            GS.closeSkillTooltip()
            return
        else
            return
        end
    end

    -- 技能面板点击（锁定悬停提示，加点通过 tooltip 内按钮完成）
    if GS.activeBottomTab == 3 and GS.skillSlotAreas then
        for skillId, r in pairs(GS.skillSlotAreas) do
            if hitTest(mx, my, r) then
                -- 点击图标 → 锁定 tooltip 显示（加点在 tooltip 按钮中完成）
                GS.skillTooltipId = skillId
                GS.skillTooltipSource = "tree"
                GS.skillTooltipPinned = true
                return
            end
        end
    end

    -- 背包滚动条拖动（购买弹窗打开时屏蔽）
    if GS.activeBottomTab == 2 and GS.invScrollBarRect and not GS.shopBuyConfirmVisible then
        local sb = GS.invScrollBarRect
        if hitTest(mx, my, sb) then
            GS.invScrollBarDragging = true
            GS.invScrollBarDragStartY = my
            GS.invScrollBarDragStartScroll = GS.invScrollY
            return
        end
    end

    -- 背包区域交互（购买弹窗打开时屏蔽；共享仓库面板覆盖区域优先交给共享仓库处理）
    if GS.activeBottomTab == 2 and GS.invClipRect and not GS.shopBuyConfirmVisible
        and not (GS.sharedStorageMode and GS.sharedStoragePanelRect and hitTest(mx, my, GS.sharedStoragePanelRect))
    then
        local r = GS.invClipRect
        if hitTest(mx, my, r) then
            -- 记录按下的背包格子（用于拖拽，多选模式下禁用拖拽）
            GS.dragSlotIdx = nil
            GS.itemDragActive = false
            GS.itemDragStartX = mx
            GS.itemDragStartY = my
            if not GS.invMultiSelect and GS.inventorySlotAreas then
                for idx, sr in pairs(GS.inventorySlotAreas) do
                    if hitTest(mx, my, sr) then
                        if GS.inventory[idx] then
                            GS.dragSlotIdx = idx
                        end
                        break
                    end
                end
            end

            if GS.invContentH > GS.invVisibleH then
                GS.invDragging = true
                GS.invDragStartY = my
                GS.invDragStartScroll = GS.invScrollY
                GS.invDragMoved = false
            else
                -- 不需要滚动时也标记按下状态，松手判断点击或拖拽
                GS.invDragging = true
                GS.invDragStartY = my
                GS.invDragStartScroll = GS.invScrollY or 0
                GS.invDragMoved = false
            end
            return
        end
    end

    -- 地图分区标签点击
    if GS.activeBottomTab == 5 and GS.mapZoneTabRects and #GS.mapZoneTabRects > 0 then
        for _, tab in ipairs(GS.mapZoneTabRects) do
            if hitTest(mx, my, tab) then
                if GS.mapStageZone ~= tab.zoneId then
                    GS.mapStageZone = tab.zoneId
                    GS.selectedMapStage = nil
                    GS.mapStageScrollOffset = 0
                end
                return
            end
        end
    end

    -- 地图关卡列表：滚动条拖拽开始
    if GS.activeBottomTab == 5 and GS.mapStageScrollbarRect then
        if hitTest(mx, my, GS.mapStageScrollbarRect) then
            GS.mapStageScrollbarDragging = true
            -- 根据点击位置直接跳转
            local sb = GS.mapStageScrollbarRect
            local relY = (my - sb.y) / sb.h
            local maxScroll = GS.mapStageScrollMaxOffset
            GS.mapStageScrollOffset = math.floor(relY * (maxScroll + 1))
            GS.mapStageScrollOffset = math.max(0, math.min(GS.mapStageScrollOffset, maxScroll))
            return
        end
    end

    -- 地图关卡列表：触摸滑动开始
    if GS.activeBottomTab == 5 and GS.mapStageListClip and GS.mapStageScrollMaxOffset > 0 then
        if hitTest(mx, my, GS.mapStageListClip) then
            GS.mapStageTouchStartY = my
            GS.mapStageTouchStartOffset = GS.mapStageScrollOffset
        end
    end

    -- 史莱姆国王大反击：排名按钮点击
    if GS.activeBottomTab == 5 and GS.mapSlimeRevengeRankBtnRect then
        local r = GS.mapSlimeRevengeRankBtnRect
        if hitTest(mx, my, r) then
            GS.slimeRevengeRankPanel = true
            GS.slimeRevengeRankTab = 0
            GS.slimeRevengeRankScroll = 0
            M._loadSlimeRevengeRankData(0)
            return
        end
    end

    -- 史莱姆国王大反击：奖励按钮点击
    if GS.activeBottomTab == 5 and GS.mapSlimeRevengeRewardBtnRect then
        local r = GS.mapSlimeRevengeRewardBtnRect
        if hitTest(mx, my, r) then
            GS.slimeRevengeRewardPanel = true
            GS.slimeRevengeRewardScroll = 0
            -- 重新加载云端已领取数据
            GS._slimeRevengeRewardLoaded = false
            GS._slimeRevengeRewardLoading = false
            return
        end
    end

    -- 迪哈塔大反击：排名按钮点击
    if GS.activeBottomTab == 5 and GS.mapDihataRevengeRankBtnRect then
        local r = GS.mapDihataRevengeRankBtnRect
        if hitTest(mx, my, r) then
            GS.dihataRevengeRankPanel = true
            GS.dihataRevengeRankTab = 0
            GS.dihataRevengeRankScroll = 0
            M._loadDihataRevengeRankData(0)
            return
        end
    end

    -- 迪哈塔大反击：奖励按钮点击
    if GS.activeBottomTab == 5 and GS.mapDihataRevengeRewardBtnRect then
        local r = GS.mapDihataRevengeRewardBtnRect
        if hitTest(mx, my, r) then
            GS.dihataRevengeRewardPanel = true
            GS.dihataRevengeRewardScroll = 0
            -- 重新加载云端已领取数据
            GS._dihataRevengeRewardLoaded = false
            GS._dihataRevengeRewardLoading = false
            return
        end
    end

    -- 地图"取消"按钮点击（优先于关卡列表，防止被列表条目遮挡）
    if GS.activeBottomTab == 5 and GS.mapCancelButtonRect then
        local r = GS.mapCancelButtonRect
        if hitTest(mx, my, r) then
            GS.selectedMapLocation = nil
            GS.selectedMapStage = nil
            GS.mapQuestStageMode = nil
            return
        end
    end

    -- 地图"前往"按钮点击（优先于关卡列表）
    if GS.activeBottomTab == 5 and GS.mapGoButtonRect then
        local r = GS.mapGoButtonRect
        if hitTest(mx, my, r) then
            -- 过渡中禁止点击
            if GS.sceneTransition then return end
            -- 死亡/复活状态禁止切换
            if GS.gameState == GS.STATE_RESPAWN or GS.gameState == GS.STATE_GAMEOVER then
                GS.mapTipText = "请等待复活后再前往"
                GS.mapTipTimer = 2.0
                return
            end
            local stg = r.stage
            if stg then
                -- 捕获回调所需变量（提前到深渊检查之前，以便闭包可被暂存）
                local locName = r.locName
                local overlayId = stg.overlayId
                local stageIndex = stg.stageIndex
                local stageName = stg.name
                local stageType = stg.type
                local stageBg = r.bg
                local isDungeon = stg.dungeon
                local dungeonId = stg.dungeonId

                -- 构建场景切换执行函数（闭包捕获所有参数）
                local function doSceneSwitch()
                GS.startSceneTransition(function()
                    -- 离开当前场景前关闭所有打开的界面/面板
                    if GS.warehouseMode then GS.exitWarehouseMode() end
                    if GS.lostItemsMode then GS.exitLostItemsMode() end
                    if GS.exchangeMode then GS.exitExchangeMode() end
                    GS.shopMode = false
                    GS.enhanceMode = false
                    GS.repairMode = false
                    GS.forgeMode = false
                    GS.homeForgeMode = false
                    GS.alchemyMode = false
                    GS.homeAlchemyMode = false
                    GS.homeCookingMode = false
                    GS.homeSmithySelectMode = false
                    GS.homeSmithySelectRects = nil
                    GS.homeCraftMode = false
                    GS.homeSocketMode = false
                    GS.homeEnchantMode = false
                    GS.enchantMode = false
                    GS.enchantSlotItem = nil
                    GS.enchantSlotSource = nil
                    GS.enchantSlotSourceId = nil
                    GS.enchantResult = nil
                    GS.refineMode = false
                    GS.craftMode = false
                    GS.socketMode = false
                    -- 关闭对话界面
                    local DM = require("DialogueManager")
                    if DM.active then DM.finish() end
                    if stageType == "town" then
                        -- 城镇场景：显示覆盖层，重置为移动阶段以允许切换装备
                        if GS.isDungeon then DungeonManager.exit() end
                        GS.currentStage = stageIndex
                        GS.isAbyssWorld = false
                        GS.homeMode = false
                        GS.trainingMode = false
                        GS.gameState = GS.STATE_PLAYER
                        GS.turnPhase = GS.PHASE_MOVE
                        GS.currentBattleBg = stageBg or "image/bg_grass.png"
                        GS.currentAreaName = locName
                        GS.currentStageName = stageName
                        BoardOverlay.show("town", overlayId, locName)
                        print("=== 进入场景: " .. locName .. " ===")
                    elseif stageType == "home" then
                        -- 首次点击"家"激活筑巢任务
                        local QM = require("QuestManager")
                        if QM.getQuestStatus("side_nesting") == QM.STATUS_LOCKED then
                            QM.activateQuest("side_nesting")
                        end
                        if not GS.housePurchased then
                            -- 未购买房屋，弹出购买弹窗
                            GS.houseBuyDialogVisible = true
                            return
                        end
                        -- 家：无覆盖层，清空怪物/采集物，自由移动模式
                        if GS.isDungeon then DungeonManager.exit() end
                        BoardOverlay.hide()
                        GS.currentStage = stageIndex
                        GS.isAbyssWorld = false
                        GS.homeMode = true
                        GS.sharedStorageMode = false
                        GS.sharedStorageLogOpen = false
                        GS.trainingMode = false
                        GS.gameState = GS.STATE_PLAYER
                        GS.turnPhase = GS.PHASE_MOVE
                        GS.currentBattleBg = stageBg or "image/bg_home.png"
                        GS.currentAreaName = locName
                        GS.currentStageName = stageName
                        -- 清空场上单位（先保存采集关卡状态）
                        GS.saveGatherStageState()
                        GS.monsters = {}
                        GS.companions = {}
                        GS.gatherables = {}
                        GS.gatheringState = nil
                        GS.gatherResultAnim = nil
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        GS.flushPendingMpRestores()
                        GS.damageTexts = {}
                        GS.holyTrees = {}
                        GS.iceWalls = {}
                        GS.burningGrounds = {}
                        GS.pendingBurningGrounds = {}
                        GS.blizzardZones = {}
                        GS.thunderClouds = {}
                        Combat.clearPendingState()
                        -- 玩家放在门内侧
                        local hp = GS.getHomeRoomParams(GS.homeType)
                        GS.player.x = hp.doorX1
                        GS.player.y = hp.doorY - 1
                        GS.spawnHound()
                        print("=== 进入场景: " .. locName .. " (家) ===")
                    elseif stageType == "training" then
                        -- 训练场：战斗场景但启用训练模式
                        GS.homeMode = false
                        GS.trainingMode = true
                        -- 重置伤害统计
                        GS.trainingDmgLog = {}
                        GS.trainingTurnDmg = 0
                        GS.trainingTotalDmg = 0
                        GS.trainingTurnCount = 0
                        BoardOverlay.hide()

                        GS.currentStage = stageIndex
                        GS.currentBattleBg = stageBg or "image/bg_grass.png"
                        GS.currentAreaName = locName
                        GS.currentStageName = stageName
                        GS.turnNumber = 1

                        Combat.clearPendingState()
                        GS.saveGatherStageState()
                        GS.monsters = {}
                        GS.companions = {}
                        GS.fireCorpses = {}
                        GS.gatherables = {}
                        GS.gatheringState = nil
                        GS.gatherResultAnim = nil
                        GS.playerDebuffs = {}
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        GS.flushPendingMpRestores()
                        GS.damageTexts = {}
                        GS.holyTrees = {}
                        GS.iceWalls = {}
                        GS.burningGrounds = {}
                        GS.pendingBurningGrounds = {}
                        GS.blizzardZones = {}
                        GS.thunderClouds = {}
                        GS.chanting = nil
                        GS.stealthActive = false
                        GS.stealthTurns = 0
                        GS.attackEffects = {}
                        GS.strikeEffects = {}
                        GS.whirlwindEffects = {}
                        GS.stealthSmokeEffect = nil
                        GS.pendingEndPlayerTurn = false
                        GS._pendingEndTurnTimer = nil
                        GS.screenShake = nil
                        GS.tombstoneAnim = nil
                        GS.tombstoneDropAnim = nil
                        GS.closeActionMenu()
                        GS.showAutoBattleSettings = false
                        GS.autoMode = false

                        -- 玩家放在棋盘偏下位置
                        if GS.player then
                            GS.player.acted = false
                            GS.player.x = math.floor(GS.BOARD_SIZE / 2) + 1
                            GS.player.y = math.floor(GS.BOARD_SIZE / 2) + 4  -- 假人下方3格
                            if GS.player.hp <= 0 then
                                GS.player.hp = GS.player.maxHp
                                GS.player.mp = GS.player.maxMp
                            end
                        end

                        GS.gameState = GS.STATE_PLAYER
                        GS.turnPhase = GS.PHASE_MOVE
                        GS.stormBuffTurns = 0

                        -- 根据玩家等级选择默认训练假人档位
                        GS.trainingDummyTierIdx = GS.getDefaultDummyTier(GS.player.level or 1)
                        -- 在棋盘中央刷新训练假人
                        Combat.spawnTrainingDummy()
                        GS.spawnHound()

                        -- 施法职业充能吟唱段数
                        if (GS.currentClass == "mage" or GS.currentClass == "priest") and GS.player and GS.player.hp > 0 then
                            GS.chantStages = 0
                            local gained = GS.rollChantStages()
                            GS.chantStages = gained
                            GS.chantStagesMax = gained
                        end
                        print("=== 进入训练场 ===")
                    elseif stageType == "battle" then
                        -- 战斗关卡：退出覆盖层，完整重置战斗状态，刷怪
                        GS.homeMode = false
                        GS.trainingMode = false
                        BoardOverlay.hide()

                        -- 切换关卡时强制清除酒馆肉搏状态（无论 done 是否为 true）
                        -- 防止 tavernBrawlState.done=true 残留导致所有关卡不刷怪/采集卡死
                        if GS.tavernBrawlState then
                            if GS.tavernBrawlState.done then
                                -- 混混已全部击倒，先触发任务完成（onComplete 内部会清除 tavernBrawlState）
                                local QM_cleanup = require("QuestManager")
                                QM_cleanup.update()
                            end
                            -- 兜底：无论 QM.update() 是否成功完成任务，强制清除残留状态
                            GS.tavernBrawlState = nil
                            GS.brawlCinematic = nil
                        end

                        -- 切换关卡和背景
                        GS.currentStage = stageIndex
                        if stageIndex > (GS.maxStageReached or 1) then GS.maxStageReached = stageIndex end
                        -- 史莱姆国王大反击：重置累计伤害和暴怒层数
                        if stageIndex == GS.STAGE_SLIME_KING_REVENGE then
                            GS.slimeRevengeAccDmg = 0
                            GS.slimeRevengeRageLayer = 0
                        end
                        if stageIndex == GS.STAGE_DIHATA_REVENGE then
                            GS.dihataRevengeAccDmg = 0
                            GS.dihataRevengeRageLayer = 0
                        end
                        GS.currentBattleBg = stageBg or "image/bg_grass.png"
                        GS.currentAreaName = locName
                        GS.currentStageName = stageName
                        GS.turnNumber = 1
                        -- 离开异世深渊进入其他关卡时清除标记（但不结束会话）
                        if not GS.isAbyssWorldStage(stageIndex) then
                            GS.isAbyssWorld = false
                        end

                        -- 清除所有待执行动作和残留目标
                        Combat.clearPendingState()
                        -- 清除所有单位和选择状态（先保存采集关卡状态）
                        GS.saveGatherStageState()
                        GS.monsters = {}
                        GS.companions = {}
                        GS.fireCorpses = {}
                        GS.gatherables = {}
                        GS.gatheringState = nil
                        GS.gatherResultAnim = nil
                        GS.playerDebuffs = {}
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        GS.flushPendingMpRestores()
                        GS.damageTexts = {}

                        -- 清除召唤物和持续效果
                        GS.holyTrees = {}
                        GS.iceWalls = {}
                        GS.burningGrounds = {}
                        GS.pendingBurningGrounds = {}
                        GS.blizzardZones = {}
                        GS.thunderClouds = {}

                        -- 清除吟唱和隐匿状态
                        GS.chanting = nil
                        GS.stealthActive = false
                        GS.stealthTurns = 0

                        -- 清除所有视觉特效
                        GS.attackEffects = {}
                        GS.strikeEffects = {}
                        GS.whirlwindEffects = {}
                        GS.stealthSmokeEffect = nil
                        GS.pendingEndPlayerTurn = false
                        GS._pendingEndTurnTimer = nil
                        GS.screenShake = nil
                        GS.tombstoneAnim = nil
                        GS.tombstoneDropAnim = nil

                        -- 关闭菜单和自动战斗设置面板
                        GS.closeActionMenu()
                        GS.showAutoBattleSettings = false
                        GS.autoMode = false

                        -- 重置玩家状态
                        if GS.player then
                            GS.player.acted = false
                            if isDungeon then
                                -- 副本：玩家出生在底部中央
                                local spawnCells = DungeonManager.getPlayerSpawnCells()
                                local sc = spawnCells[1]
                                GS.player.x = sc[1]
                                GS.player.y = sc[2]
                            else
                                GS.player.x = 6
                                GS.player.y = 7
                            end
                            -- 史莱姆国王大反击：每次进入都从满血满蓝开始
                            if stageIndex == GS.STAGE_SLIME_KING_REVENGE then
                                GS.clearAllBuffsDebuffs()
                                GS.recalcStats(GS.player)
                                GS.player.hp = GS.player.maxHp
                                GS.player.mp = GS.player.maxMp
                            elseif GS.player.hp <= 0 then
                                GS.player.hp = GS.player.maxHp
                                GS.player.mp = GS.player.maxMp
                            end
                        end

                        -- 设置回合状态
                        GS.gameState = GS.STATE_PLAYER
                        GS.turnPhase = GS.PHASE_MOVE
                        GS.stormBuffTurns = 0

                        -- 副本或普通刷怪
                        if isDungeon and dungeonId then
                            -- 重新进入副本时，先清理旧副本状态（防止 arenaWaitForExit 等脏状态残留导致第二关为空）
                            if GS.isDungeon then
                                DungeonManager.exit()
                            end
                            DungeonManager.enter(dungeonId)
                            DungeonManager.spawnForPhase()
                            -- 第一关有旁白对话时，走统一 arenaTransition 对话流程
                            local phase1 = DungeonManager.getPhase()
                            if phase1 and phase1.phaseDialogue and #phase1.phaseDialogue > 0 then
                                GS.arenaTransition = {
                                    step = "dialogue",
                                    timer = 0,
                                    isEntryDialogue = true,
                                }
                            end
                            print("=== 进入副本: " .. stageName .. " ===")
                        else
                            -- 从副本切换到普通关卡时，清理副本状态
                            if GS.isDungeon then
                                DungeonManager.exit()
                            end
                            Combat.spawnGatherables()
                            Combat.spawnMonsters()
                            print("=== 进入战斗: " .. stageName .. " (关卡" .. stageIndex .. ") ===")
                        end
                        GS.spawnHound()

                        -- 施法职业进入战斗/副本时重置并充能吟唱段数
                        if (GS.currentClass == "mage" or GS.currentClass == "priest") and GS.player and GS.player.hp > 0 then
                            GS.chantStages = 0
                            local gained = GS.rollChantStages()
                            GS.chantStages = gained
                            GS.chantStagesMax = gained
                        end
                    elseif stageType == "quest" then
                        -- 任务关卡（艾莉雅旅行）：进入场景播放对话，结束后返回清水镇
                        local questDialogue = stg.dialogue
                        local questQuestId  = stg.questId
                        if GS.isDungeon then DungeonManager.exit() end
                        GS.homeMode = false
                        GS.trainingMode = false
                        BoardOverlay.hide()

                        GS.currentBattleBg = stageBg or "image/bg_grass.png"
                        GS.currentAreaName = locName
                        GS.currentStageName = stageName
                        GS.gameState = GS.STATE_PLAYER
                        GS.turnPhase = GS.PHASE_MOVE

                        -- 如果有战斗事件（如复仇关卡），对话阶段显示森林场景背景，隐藏棋盘
                        local QM_pre = require("QuestManager")
                        local mapInfoPre = QM_pre.DIFEN_TRAVEL_AREA_MAP[stg.questId]
                        if mapInfoPre and mapInfoPre.battleEventId then
                            GS.eventSceneBg = "image/bg_forest.png"
                            GS.currentBattleBg = "image/bg_forest.png"  -- 全屏背景也用森林图
                        end
                        -- 安吉莉娅旅行任务：显示 CG 场景图，隐藏棋盘
                        local mapInfoAngelica = QM_pre.ANGELICA_TRAVEL_AREA_MAP[stg.questId]
                        if mapInfoAngelica and mapInfoAngelica.bg then
                            GS.eventSceneBg = mapInfoAngelica.bg
                            if mapInfoAngelica.battleBg then
                                GS.currentBattleBg = mapInfoAngelica.battleBg
                            end
                        end
                        -- 艾莉雅旅行任务：显示 CG 场景图，隐藏棋盘
                        local mapInfoEliya = QM_pre.ELIYA_TRAVEL_AREA_MAP[stg.questId]
                        if mapInfoEliya and mapInfoEliya.bg then
                            GS.eventSceneBg = mapInfoEliya.bg
                        end

                        -- 清空场上单位
                        GS.saveGatherStageState()
                        GS.monsters = {}
                        GS.companions = {}
                        GS.gatherables = {}
                        GS.gatheringState = nil
                        GS.gatherResultAnim = nil
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        GS.flushPendingMpRestores()
                        GS.damageTexts = {}

                        -- 关闭地图面板，切回默认标签
                        GS.mapQuestStageMode = nil
                        GS.selectedMapLocation = nil
                        GS.selectedMapStage = nil
                        GS.activeBottomTab = 1

                        -- 播放对话
                        if questDialogue and #questDialogue > 0 then
                            local DM2 = require("DialogueManager")
                            GS.isEvent = true           -- 标记事件状态，使对话框渲染到最上层
                            GS.eventInputLocked = true  -- 锁定输入，仅允许对话推进
                            -- 完成旅行并返回镇上的收尾逻辑
                            local function finishTravelQuest(gs)
                                gs.isEvent = false           -- 清除事件状态
                                gs.eventInputLocked = false  -- 恢复输入
                                local QM_t = require("QuestManager")
                                if QM_t.ANGELICA_TRAVEL_AREA_MAP[questQuestId] then
                                    gs.angelicaTravelDone[questQuestId] = true
                                    print("[Quest] 安吉莉娅旅行任务对话完成: " .. questQuestId)
                                elseif QM_t.DIFEN_TRAVEL_AREA_MAP[questQuestId] then
                                    gs.difenTravelDone[questQuestId] = true
                                    print("[Quest] 迪芬旅行任务对话完成: " .. questQuestId)
                                else
                                    gs.eliyaTravelDone[questQuestId] = true
                                    print("[Quest] 艾莉雅旅行任务对话完成: " .. questQuestId)
                                end
                                -- 立即触发一次任务更新（SUBMIT_AUTO 会自动完成）
                                local QM2 = require("QuestManager")
                                QM2.update(gs, 0)
                                -- 回到清水镇
                                gs.startSceneTransition(function()
                                    gs.eventSceneBg = nil  -- 清除CG场景背景，恢复棋盘渲染
                                    gs.currentBattleBg = "image/bg_grass.png"
                                    gs.currentAreaName = "清水镇"
                                    gs.currentStageName = "清水镇"
                                    BoardOverlay.show("town", "clearwater", "清水镇")
                                    print("[Quest] 旅行结束，返回清水镇")
                                end)
                            end

                            DM2.startDynamic(questDialogue, function(gs)
                                -- 检查是否有关卡后附加对话（安吉莉娅/迪芬旅行任务）
                                local QM_pd = require("QuestManager")
                                local mapInfo = QM_pd.ANGELICA_TRAVEL_AREA_MAP[questQuestId]
                                    or QM_pd.DIFEN_TRAVEL_AREA_MAP[questQuestId]

                                -- 检查是否有战斗事件（如迪芬复仇关卡）
                                if mapInfo and mapInfo.battleEventId then
                                    local EvtMgr = require("Event.EventManager")
                                    -- 获取事件定义并设置战斗结束回调
                                    local evtDef = EvtMgr.getEventDef and EvtMgr.getEventDef(mapInfo.battleEventId)
                                    if evtDef then
                                        evtDef._onBattleEnd = function()
                                            -- 战斗结束 → 退出事件
                                            EvtMgr.exit()
                                            if mapInfo.postDialogue then
                                                local postLines2 = {}
                                                for _, block2 in ipairs(mapInfo.postDialogue) do
                                                    for _, line2 in ipairs(block2.lines) do
                                                        postLines2[#postLines2 + 1] = { speaker = block2.speaker, text = line2 }
                                                    end
                                                end
                                                -- 先黑屏过渡切换到清水镇，淡出后再播放 postDialogue
                                                gs.startSceneTransition(function()
                                                    gs.currentBattleBg = "image/bg_grass.png"
                                                    gs.currentAreaName = "清水镇"
                                                    gs.currentStageName = "清水镇"
                                                    BoardOverlay.show("town", "clearwater", "清水镇")
                                                end)
                                                gs.sceneTransition.onComplete = function()
                                                    gs.isEvent = true
                                                    gs.eventInputLocked = true
                                                    local DM4 = require("DialogueManager")
                                                    DM4.startDynamic(postLines2, function(gs3)
                                                        -- 已在清水镇，直接完成任务（不再重复切换场景）
                                                        gs3.isEvent = false
                                                        gs3.eventInputLocked = false
                                                        local QM_t2 = require("QuestManager")
                                                        gs3.difenTravelDone[questQuestId] = true
                                                        print("[Quest] 迪芬旅行任务对话完成: " .. questQuestId)
                                                        QM_t2.update(gs3, 0)
                                                    end)
                                                end
                                            else
                                                finishTravelQuest(gs)
                                            end
                                        end
                                    end
                                    -- 黑屏过渡后进入战斗事件
                                    gs.startSceneTransition(function()
                                        gs.eventSceneBg = nil  -- 清除场景背景，恢复棋盘渲染
                                        EvtMgr.enter(mapInfo.battleEventId)
                                    end)
                                    return
                                end

                                if mapInfo and mapInfo.postDialogue then
                                    -- 将 submitDialogue 格式转换为 startDynamic 格式
                                    local postLines = {}
                                    for _, block in ipairs(mapInfo.postDialogue) do
                                        for _, line in ipairs(block.lines) do
                                            postLines[#postLines + 1] = { speaker = block.speaker, text = line }
                                        end
                                    end
                                    local DM3 = require("DialogueManager")
                                    DM3.startDynamic(postLines, function(gs2)
                                        finishTravelQuest(gs2)
                                    end)
                                else
                                    finishTravelQuest(gs)
                                end
                            end)
                        end
                        print("=== 进入任务关卡: " .. stageName .. " ===")
                    end
                end)
                end -- doSceneSwitch

                -- 等级门槛检查：玩家等级需达到（地图等级 - 5），100级不受此限制
                do
                    local mapLv = 0
                    if stageType == "battle" and stg.zone == "gather" and stg.stageIndex then
                        -- 采集区：取 STAGE_DEFS 中最高怪物等级（与地图显示一致）
                        local stageDef = GS.STAGE_DEFS[stg.stageIndex]
                        if stageDef and stageDef.monsters then
                            for _, m in ipairs(stageDef.monsters) do
                                if m.def and m.def.level and m.def.level > mapLv then
                                    mapLv = m.def.level
                                end
                            end
                        end
                    elseif stageType == "battle" and stg.monsterInfo then
                        -- 常规战斗区：取 monsterInfo 中的等级
                        mapLv = tonumber(string.match(stg.monsterInfo, "Lv(%d+)")) or 0
                    end
                    local playerLv = GS.player and GS.player.level or 1
                    local reqLv = math.min(mapLv - 5, 100)
                    if mapLv > 0 and playerLv < 100 and playerLv < reqLv then
                        GS.mapTipText = "等级不足，需达到 " .. reqLv .. " 级才能进入"
                        GS.mapTipTimer = 2.5
                        return
                    end
                end

                -- 深渊区副本：弹出确认弹窗，不立即消耗资源
                if stg.dungeon and stg.dungeonId then
                    local abyssRemain = GS.getAbyssChallengeRemain()
                    if abyssRemain > 0 then
                        GS.abyssConfirmType = "daily"
                    elseif GS.hasDivineKey() then
                        GS.abyssConfirmType = "key"
                    else
                        GS.mapTipText = "今日深渊挑战次数已用尽"
                        GS.mapTipTimer = 2.0
                        return
                    end
                    -- 暂存闭包，等玩家确认后再执行
                    GS.abyssConfirmVisible = true
                    GS.abyssConfirmStageData = doSceneSwitch
                    return
                end

                -- 异世深渊：每日免费1次，会话内可反复进入，死亡结束会话
                if GS.isAbyssWorldStage(stageIndex) then
                    if GS.abyssWorldActive then
                        -- 会话还在（未死亡），直接进入，不消耗次数
                        GS.isAbyssWorld = true
                        doSceneSwitch()
                    else
                        -- 需要开启新会话
                        local remain = GS.getAbyssWorldRemain()
                        if remain > 0 then
                            GS.abyssWorldConfirmType = "daily"
                        else
                            GS.abyssWorldConfirmType = "ad"
                        end
                        GS.abyssWorldConfirmVisible = true
                        GS.abyssWorldConfirmStageData = doSceneSwitch
                    end
                    return
                end

                -- 史莱姆国王大反击：每日免费1次，用完看广告
                if stageIndex == GS.STAGE_SLIME_KING_REVENGE then
                    local remain = GS.getSlimeRevengeRemain()
                    if remain > 0 then
                        GS.slimeRevengeConfirmType = "daily"
                    else
                        GS.slimeRevengeConfirmType = "ad"
                    end
                    GS.slimeRevengeConfirmVisible = true
                    GS.slimeRevengeConfirmCallback = doSceneSwitch
                    return
                end

                -- 迪哈塔大反击：每日免费1次，用完看广告
                if stageIndex == GS.STAGE_DIHATA_REVENGE then
                    local remain = GS.getDihataRevengeRemain()
                    if remain > 0 then
                        GS.dihataRevengeConfirmType = "daily"
                    else
                        GS.dihataRevengeConfirmType = "ad"
                    end
                    GS.dihataRevengeConfirmVisible = true
                    GS.dihataRevengeConfirmCallback = doSceneSwitch
                    return
                end

                -- ====================================================
                -- 森林精灵随机遭遇：垂雾森林战斗关卡，上午6-11点，5%概率
                -- 限制：非雨天、每个游戏自然日只随机一次
                -- ====================================================
                local locId = r.locId
                local function tryForestElfEncounter()
                    if locId ~= "mist_forest" then return false end
                    if stageType ~= "battle" then return false end
                    -- 已解锁直接拜访按钮后，不再触发随机遭遇
                    if GS.elfvahElfTalked then return false end
                    local hour = BoardOverlay.getGameHour()
                    if hour < 6 or hour >= 12 then return false end
                    -- 雨天不触发
                    if GS.isRaining then return false end
                    -- 每个游戏自然日只随机一次（调试模式可无限）
                    if not GS.debugElfUnlimitedRolls then
                        local today = math.floor((GS.weatherTime - 1) / 1440) + 1
                        if GS._forestElfLastRollDay == today then return false end
                        GS._forestElfLastRollDay = today
                    end
                    if math.random(100) > 5 then return false end
                    -- 触发精灵遭遇！保存原始场景切换闭包
                    GS._forestElfPendingSwitch = doSceneSwitch
                    -- 先显示覆盖层以承载子场景（始终调用以确保 cleanupVideoState）
                    BoardOverlay.show("town", "clearwater", "垂雾森林")
                    BoardOverlay.enterSubScene("forest_elf")
                    -- 弹出初始对话：？？？/艾莉雅："……"
                    local DM = require("DialogueManager")
                    local elfName = GS.resolveNPCSpeaker("艾莉雅")
                    DM.startDynamic({
                        { speaker = elfName, text = "……" },
                    })
                    print("=== 森林精灵随机遭遇触发！===")
                    return true
                end

                -- 自动战斗回合进行中：延迟到回合结束再切换
                if Combat.isTurnBusy() then
                    Combat.pendingStageSwitch = doSceneSwitch
                elseif not tryForestElfEncounter() then
                    doSceneSwitch()
                end
            end
            return
        end
    end

    -- 地图关卡列表点击（在取消/前往按钮之后判断，避免按钮被列表遮挡）
    if GS.activeBottomTab == 5 and #GS.mapStageBtnRects > 0 then
        for _, r in ipairs(GS.mapStageBtnRects) do
            if hitTest(mx, my, r) then
                GS.selectedMapStage = r.stageIdx
                return
            end
        end
    end

    -- 地图面板区域拖拽/点击
    if GS.activeBottomTab == 5 and GS.mapClipRect then
        local r = GS.mapClipRect
        if hitTest(mx, my, r) then
            GS.mapDragging = true
            GS.mapDragStartY = my
            GS.mapDragStartScroll = GS.mapScrollY
            GS.mapDragMoved = false
            return
        end
    end

    -- 底部Tab按钮点击检测
    if GS.bottomTabBtnRects then
        for i, r in ipairs(GS.bottomTabBtnRects) do
            if hitTest(mx, my, r) then
                if i ~= GS.activeBottomTab then
                    GS.tabAnimFrom = GS.activeBottomTab
                    GS.tabAnimDir = (i > GS.activeBottomTab) and 1 or -1
                    GS.tabAnimTimer = GS.tabAnimDuration
                    GS.activeBottomTab = i
                    -- 切换 tab 时退出多选模式
                    if GS.invMultiSelect then
                        GS.invMultiSelect = false
                        GS.invSelected = {}
                    end
                    -- 切换 tab 时关闭技能装备弹窗和tooltip
                    GS.showBuffSummary = false
                    GS.showMonsterBuffSummary = false
                    GS.skillEquipPopupVisible = false
                    GS.skillEquipPopupSlot = nil
                    GS.closeSkillTooltip()
                end
                return
            end
        end
    end

    -- 竞技场过场对话：STATE_ENEMY 时对话无法被常规路径处理，需在此拦截
    if GS.arenaTransition and button == MOUSEB_LEFT then
        local DialogueManager = require("DialogueManager")
        if DialogueManager.active then
            if DialogueManager.waitingForChoice and GS._choiceRects then
                for i, rect in ipairs(GS._choiceRects) do
                    if hitTest(mx, my, rect) then
                        DialogueManager.selectChoice(i)
                        return
                    end
                end
                return
            end
            DialogueManager.advance()
            return
        end
    end

    -- 覆盖层模式：处理按钮点击，阻止棋盘点击（不受 autoMode 限制）
    -- 家模式下仓库也需要处理输入
    if BoardOverlay.isActive() or (GS.homeMode and (GS.warehouseMode or GS.sharedStorageMode or GS.alchemyMode or GS.cookingMode or GS.homeSmithySelectMode or GS.forgeMode or GS.craftMode or GS.enchantMode or GS.socketMode or GS.giftMode)) then
        -- 铁匠台选择弹窗优先处理
        if GS.homeSmithySelectMode and GS.homeSmithySelectRects then
            local sr = GS.homeSmithySelectRects
            if sr.closeBtn and hitTest(mx, my, sr.closeBtn) then
                GS.homeSmithySelectMode = false
                GS.homeSmithySelectRects = nil
                return
            end
            if sr.forgeBtn and hitTest(mx, my, sr.forgeBtn) then
                GS.homeSmithySelectMode = false
                GS.homeSmithySelectRects = nil
                GS.homeForgeMode = true
                GS.forgeMode = true
                GS.forgeResult = nil
                GS.forgeScrollY = 0
                GS.forgeBtnRects = {}
                return
            end
            if sr.craftBtn and hitTest(mx, my, sr.craftBtn) then
                GS.homeSmithySelectMode = false
                GS.homeSmithySelectRects = nil
                GS.homeCraftMode = true
                GS.craftMode = true
                GS.craftTab = "enhance"
                GS.craftSlotItem = nil
                GS.craftSlotSource = nil
                GS.craftSlotSourceId = nil
                GS.craftEnhanceResult = nil
                GS.craftRefineResult = nil
                GS.craftRepairResult = nil
                GS.craftExtractResult = nil
                GS.extractSourceItem = nil
                GS.extractTargetItem = nil
                GS.extractSourceSource = nil
                GS.extractSourceSourceId = nil
                GS.extractTargetSource = nil
                GS.extractTargetSourceId = nil
                -- 会话锁：乐观开启界面，异步检查多端登录
                SessionLock.checkOnCraftOpen()
                return
            end
            if sr.enchantBtn and hitTest(mx, my, sr.enchantBtn) then
                GS.homeSmithySelectMode = false
                GS.homeSmithySelectRects = nil
                GS.homeEnchantMode = true
                GS.enchantMode = true
                GS.enchantSlotItem = nil
                GS.enchantSlotSource = nil
                GS.enchantSlotSourceId = nil
                GS.enchantResult = nil
                return
            end
            return  -- 弹窗打开时拦截其他点击
        end

        -- 告白确认弹窗优先处理
        if GS.confessConfirmPopup then
            local yr = GS.confessConfirmYesRect
            local nr = GS.confessConfirmNoRect
            if hitTest(mx, my, yr) then
                local action = GS.confessConfirmPopup.action
                GS.confessConfirmPopup = nil
                if action then action() end
            elseif hitTest(mx, my, nr) then
                GS.confessConfirmPopup = nil
            end
            return
        end

        -- 兑换确认弹窗优先处理
        if GS.exchangeBuyConfirmVisible then
            local yr = GS.exchangeBuyYesRect
            local nr = GS.exchangeBuyNoRect
            local item = GS.exchangeBuyConfirmItem
            if hitTest(mx, my, yr) then
                if item then
                    local ok, msg = GS.exchangeReward(item.rewardIdx, 1)
                    print("=== 兑换: " .. (item.name or "") .. " => " .. msg .. " ===")
                    if ok then
                        GS.exchangeBuyMsg = { text = msg, timer = 1.5, color = {60, 200, 60} }
                    else
                        GS.exchangeBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                    end
                end
                GS.exchangeBuyConfirmVisible = false
                GS.exchangeBuyConfirmItem = nil
            elseif hitTest(mx, my, nr) then
                GS.exchangeBuyConfirmVisible = false
                GS.exchangeBuyConfirmItem = nil
            end
            return
        end

        -- 购买数量选择弹窗优先处理
        if GS.shopBuyConfirmVisible then
            local yr = GS.shopBuyConfirmYesRect
            local nr = GS.shopBuyConfirmNoRect
            local item = GS.shopBuyConfirmItem
            local unitPrice = item and item.price or 0
            local qty = GS.shopBuyQuantity or 1
            local totalPrice = unitPrice * qty

            -- ±数量按钮
            for _, btn in ipairs(GS.shopBuyQtyBtnRects or {}) do
                if btn.enabled and hitTest(mx, my, btn) then
                    local stock = item and item.stock or 999
                    local affordQty = math.floor(GS.gold / math.max(1, unitPrice))
                    local maxQty = math.min(stock, affordQty)
                    if maxQty < 1 then maxQty = 1 end
                    local newQty = qty + btn.delta
                    newQty = math.max(1, math.min(maxQty, newQty))
                    GS.shopBuyQuantity = newQty
                    return
                end
            end

            -- 滑动条点击/拖拽开始
            local sr = GS.shopBuyQtySliderRect
            if hitTest(mx, my, sr) then
                GS.shopBuyQtySliderDragging = true
                -- 立即更新数量
                local ratio = math.max(0, math.min(1, (mx - sr.trackX) / sr.trackW))
                local maxQty = sr.maxQty or 1
                local newQty = math.floor(ratio * (maxQty - 1) + 1.5)
                newQty = math.max(1, math.min(maxQty, newQty))
                GS.shopBuyQuantity = newQty
                return
            end

            -- 确认按钮
            if hitTest(mx, my, yr) then
                if item and GS.gold >= totalPrice then
                    -- 先检查背包空间
                    local emptyCount = 0
                    for si = 1, GS.bagSlots do
                        if not GS.inventory[si] then emptyCount = emptyCount + 1 end
                    end
                    -- 可堆叠物品检查已有堆叠空间
                    local tpl = GS.itemTemplates[item.templateId]
                    local stackable = tpl and (tpl.consumable ~= nil or tpl.category == "材料" or tpl.stackable) and tpl.slot == nil
                    local stackSpace = 0
                    if stackable then
                        for si = 1, GS.bagSlots do
                            local inv = GS.inventory[si]
                            if inv and inv.templateId == item.templateId and inv.stackable then
                                stackSpace = stackSpace + (GS.STACK_MAX - inv.quantity)
                            end
                        end
                    end
                    local totalSpace = stackSpace + emptyCount * (stackable and GS.STACK_MAX or 1)
                    if totalSpace < qty then
                        -- 背包空间不足
                        GS.shopBuyMsg = { text = "背包空间不足，购买失败", timer = 2.0, color = {220, 60, 40} }
                        GS.shopBuyConfirmVisible = false
                        GS.shopBuyConfirmItem = nil
                        GS.shopBuyQuantity = 1
                        return
                    end
                    local ok, msg = GS.buyItem(item.templateId, item.price, qty)
                    print("=== 购买: " .. (item.name or "") .. " x" .. qty .. " => " .. msg .. " ===")
                    -- 扣减商店库存
                    if ok and item.shopItemRef then
                        item.shopItemRef.stock = math.max(0, (item.shopItemRef.stock or 0) - qty)
                        GS.shopBuyMsg = { text = item.name .. " x" .. qty .. " 购买成功", timer = 1.5, color = {60, 200, 60} }
                    elseif not ok then
                        GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                    end
                end
                GS.shopBuyConfirmVisible = false
                GS.shopBuyConfirmItem = nil
                GS.shopBuyQuantity = 1
            elseif hitTest(mx, my, nr) then
                -- 取消购买
                GS.shopBuyConfirmVisible = false
                GS.shopBuyConfirmItem = nil
                GS.shopBuyQuantity = 1
            end
            return
        end

        -- 打烊弹窗激活时：响应确定按钮和广告机按钮，屏蔽其他交互
        if BoardOverlay.closedPopup then
            local br = BoardOverlay.closedPopupBtnRect
            if br and hitTest(mx, my, br) then
                BoardOverlay.closedPopup = nil
                BoardOverlay.closedPopupBtnRect = nil
                BoardOverlay.closedPopupAdBtnRect = nil
            end
            -- 无人"广告机"按钮（仅冒险者公会打烊时显示）
            local abr = BoardOverlay.closedPopupAdBtnRect
            if abr and hitTest(mx, my, abr) then
                BoardOverlay.closedPopup = nil
                BoardOverlay.closedPopupBtnRect = nil
                BoardOverlay.closedPopupAdBtnRect = nil
                -- 标记从打烊界面进入，用于切换按钮和隐藏X
                GS.adMachineFromClosed = true
                BoardOverlay.enterSubScene("guild_ad_machine", true)
            end
            return
        end

        if BoardOverlay.inSubScene() or (GS.homeMode and (GS.warehouseMode or GS.sharedStorageMode or GS.alchemyMode or GS.cookingMode or GS.homeSmithySelectMode or GS.forgeMode or GS.craftMode or GS.enchantMode or GS.socketMode or GS.giftMode)) then
            -- 镶嵌模式拦截
            if GS.socketMode then
                -- 关闭按钮
                local cr = GS.socketCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.socketMode = false
                    GS.homeSocketMode = false
                    GS.socketResult = nil
                    GS.socketScrollY = 0
                    GS.socketEquipItem = nil
                    GS.socketEquipSource = nil
                    GS.socketEquipSourceId = nil
                    GS.socketSelectedGemSlot = nil
                    GS.socketSelectedGemBag = nil
                    GS.socketGemBtnRects = {}
                    GS.socketTab = "socket"
                    GS.reforgeVeilItem = nil
                    GS.reforgeGemItem = nil
                    GS.reforgeVeilSource = nil
                    GS.reforgeVeilSourceId = nil
                    GS.reforgeGemSource = nil
                    GS.reforgeGemSourceId = nil
                    return
                end
                -- 分页标签点击
                for _, tabBtn in ipairs(GS.socketTabRects or {}) do
                    if hitTest(mx, my, tabBtn) then
                        if GS.socketTab ~= tabBtn.tab then
                            GS.socketTab = tabBtn.tab
                            GS.socketResult = nil
                            -- 切换分页时重置各自状态
                            if tabBtn.tab == "socket" then
                                GS.reforgeVeilItem = nil
                                GS.reforgeGemItem = nil
                                GS.reforgeVeilSource = nil
                                GS.reforgeVeilSourceId = nil
                                GS.reforgeGemSource = nil
                                GS.reforgeGemSourceId = nil
                            else
                                GS.socketEquipItem = nil
                                GS.socketEquipSource = nil
                                GS.socketEquipSourceId = nil
                                GS.socketSelectedGemSlot = nil
                                GS.socketSelectedGemBag = nil
                                GS.socketScrollY = 0
                            end
                        end
                        return
                    end
                end
                -- 重铸分页交互
                if GS.socketTab == "reforge" then
                    if GS.veilReforgeTime then
                        -- 领取按钮
                        local cbr = GS.reforgeCollectBtnRect
                        if cbr and hitTest(mx, my, cbr) then
                            -- 创建新面纱
                            local _, _, addedItem = GS.addToInventory("gem_rainbow_masterwork")
                            if addedItem then
                                local pool = GS.ABYSS_AFFIX_POOL
                                local roll = pool[math.random(#pool)]
                                addedItem.abyssAffix = {
                                    id = roll.id, name = roll.name,
                                    desc = roll.desc, mechanic = roll.mechanic,
                                }
                                local mainStats = {"str","wis","agi","con","foc","per","wil","luk","cha"}
                                local picked = mainStats[math.random(#mainStats)]
                                addedItem.gemEffect = { [picked] = 3 }
                                GS.veilReforgeTime = nil
                                GS.socketResult = { success = true, msg = "获得新的面纱！", timer = 2.0 }
                                GS.saveToCloud()
                            else
                                GS.socketResult = { success = false, msg = "背包已满，无法领取", timer = 2.0 }
                            end
                            return
                        end
                    else
                        -- 重铸按钮
                        local rbr = GS.reforgeBtnRect
                        if rbr and hitTest(mx, my, rbr) then
                            local veil = GS.reforgeVeilItem
                            local gem = GS.reforgeGemItem
                            if veil and gem then
                                -- 消耗面纱：从背包移除
                                if GS.reforgeVeilSource == "bag" and GS.reforgeVeilSourceId then
                                    GS.inventory[GS.reforgeVeilSourceId] = nil
                                end
                                -- 消耗宝石：从背包移除
                                if GS.reforgeGemSource == "bag" and GS.reforgeGemSourceId then
                                    GS.inventory[GS.reforgeGemSourceId] = nil
                                end
                                -- 记录重铸时间
                                GS.veilReforgeTime = GS._getTrustedTime()
                                GS.reforgeVeilItem = nil
                                GS.reforgeGemItem = nil
                                GS.reforgeVeilSource = nil
                                GS.reforgeVeilSourceId = nil
                                GS.reforgeGemSource = nil
                                GS.reforgeGemSourceId = nil
                                GS.socketResult = { success = true, msg = "重铸已开始，24小时后可领取", timer = 2.0 }
                                GS.saveToCloud()
                            end
                            return
                        end
                        -- 点击面纱槽：清空
                        local vdr = GS.reforgeVeilDropRect
                        if vdr and hitTest(mx, my, vdr) then
                            if GS.reforgeVeilItem then
                                GS.reforgeVeilItem = nil
                                GS.reforgeVeilSource = nil
                                GS.reforgeVeilSourceId = nil
                            end
                            return
                        end
                        -- 点击宝石槽：清空
                        local gdr = GS.reforgeGemDropRect
                        if gdr and hitTest(mx, my, gdr) then
                            if GS.reforgeGemItem then
                                GS.reforgeGemItem = nil
                                GS.reforgeGemSource = nil
                                GS.reforgeGemSourceId = nil
                            end
                            return
                        end
                    end
                    return  -- 重铸分页下吞掉其他点击
                end
                -- 点击放置槽：清空已放入的装备（宝石镶嵌分页）
                local dr = GS.socketDropRect
                if dr and hitTest(mx, my, dr) then
                    if GS.socketEquipItem then
                        GS.socketEquipItem = nil
                        GS.socketEquipSource = nil
                        GS.socketEquipSourceId = nil
                        GS.socketSelectedGemSlot = nil
                        GS.socketSelectedGemBag = nil
                        GS.socketResult = nil
                    end
                    return
                end
                -- 开槽按钮点击
                local dbr = GS.socketDrillBtnRect
                if dbr and hitTest(mx, my, dbr) then
                    local ok, msg = GS.drillGemSlot()
                    GS.socketResult = { success = ok, msg = msg, timer = 2.0 }
                    return
                end
                -- 按钮点击：非宝石行按钮立即处理，宝石行延迟到抬起时处理（避免阻断滚动）
                for _, btn in ipairs(GS.socketGemBtnRects or {}) do
                    if hitTest(mx, my, btn) then
                        if btn.type == "gemSlot" then
                            -- 宝石槽：立即处理（不在滚动区域）
                            if GS.socketSelectedGemSlot == btn.idx then
                                GS.socketSelectedGemSlot = nil
                            else
                                GS.socketSelectedGemSlot = btn.idx
                            end
                            return
                        elseif btn.type == "socket" then
                            -- 执行镶嵌：立即处理
                            local ok, msg = GS.doSocket(btn.gemSlotIdx, btn.gemBagSlot)
                            GS.socketResult = { success = ok, msg = msg, timer = 2.0 }
                            return
                        elseif btn.type == "remove" then
                            -- 执行拆卸：立即处理
                            local ok, msg = GS.removeGemFromSocket(btn.idx)
                            GS.socketResult = { success = ok, msg = msg, timer = 2.0 }
                            return
                        elseif btn.type == "gem" then
                            -- 宝石行：记录待处理，先启动滚动追踪
                            GS._socketPendingGemBtn = btn
                            break
                        end
                    end
                end
                -- 面板区域内开始触摸拖动滚动
                local fp = GS.socketPanelRect
                if fp and hitTest(mx, my, fp) then
                    GS.socketTouchStartY = my
                    GS.socketTouchStartScroll = GS.socketScrollY or 0
                end
                return  -- 镶嵌模式下吞掉其他点击
            end

            -- 锻造模式拦截
            if GS.forgeMode then
                -- 关闭按钮
                local cr = GS.forgeCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.forgeMode = false
                    GS.homeForgeMode = false
                    GS.forgeResult = nil
                    GS.forgeScrollY = 0
                    GS.forgeBtnRects = {}
                    return
                end
                -- 配方锻造按钮点击
                for _, btn in ipairs(GS.forgeBtnRects or {}) do
                    if hitTest(mx, my, btn) then
                        local ok, msg = GS.doForge(btn.idx)
                        GS.forgeResult = { success = ok, msg = msg, timer = 2.0 }
                        -- 开始长按追踪
                        craftHoldType = "forge"
                        craftHoldIdx = btn.idx
                        craftHoldTimer = 0
                        craftHoldInterval = 0
                        return
                    end
                end
                -- 产出物品图标点击 → 固定 tooltip
                if GS.forgeIconRects then
                    for _, r in ipairs(GS.forgeIconRects) do
                        if my >= r.listY and my <= r.listY + r.listH
                           and hitTest(mx, my, r) then
                            local tpl = GS.itemTemplates[r.templateId]
                            if tpl then
                                GS.tooltipItem = tpl
                                GS.tooltipSlotIdx = 0
                                GS.tooltipSource = "forge"
                                GS.tooltipEquipSlotId = nil
                                GS.tooltipPinned = true
                                GS.tooltipAnchorRect = r
                            end
                            return
                        end
                    end
                end
                -- 滚动条拖拽检测
                local fsb = GS.forgeScrollBarRect
                if fsb and mx >= fsb.x and mx <= fsb.x + fsb.w and my >= fsb.y and my <= fsb.y + fsb.h then
                    GS.forgeScrollBarDragging = true
                    GS.forgeScrollBarGrabY = my - fsb.y
                    return
                end
                -- 面板区域内开始触摸拖动滚动
                local fp = GS.forgePanelRect
                if fp and hitTest(mx, my, fp) then
                    GS.forgeTouchStartY = my
                    GS.forgeTouchStartScroll = GS.forgeScrollY or 0
                end
                return  -- 锻造模式下吞掉其他点击
            end

            -- 炼金模式拦截
            if GS.alchemyMode then
                -- 关闭按钮
                local cr = GS.alchemyCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.alchemyMode = false
                    GS.homeAlchemyMode = false
                    GS.alchemyResult = nil
                    GS.alchemyScrollY = 0
                    GS.alchemyBtnRects = {}
                    return
                end
                -- 配方炼金按钮点击
                for _, btn in ipairs(GS.alchemyBtnRects or {}) do
                    if hitTest(mx, my, btn) then
                        local ok, msg = GS.doAlchemy(btn.idx)
                        GS.alchemyResult = { success = ok, msg = msg, timer = 2.0 }
                        -- 开始长按追踪
                        craftHoldType = "alchemy"
                        craftHoldIdx = btn.idx
                        craftHoldTimer = 0
                        craftHoldInterval = 0
                        return
                    end
                end
                -- 产出物品图标点击 → 固定 tooltip
                if GS.alchemyIconRects then
                    for _, r in ipairs(GS.alchemyIconRects) do
                        if my >= r.listY and my <= r.listY + r.listH
                           and hitTest(mx, my, r) then
                            local tpl = GS.itemTemplates[r.templateId]
                            if tpl then
                                GS.tooltipItem = tpl
                                GS.tooltipSlotIdx = 0
                                GS.tooltipSource = "alchemy"
                                GS.tooltipEquipSlotId = nil
                                GS.tooltipPinned = true
                                GS.tooltipAnchorRect = r
                            end
                            return
                        end
                    end
                end
                -- 滚动条拖拽检测
                local asb = GS.alchemyScrollBarRect
                if asb and mx >= asb.x and mx <= asb.x + asb.w and my >= asb.y and my <= asb.y + asb.h then
                    GS.alchemyScrollBarDragging = true
                    GS.alchemyScrollBarGrabY = my - asb.y
                    return
                end
                -- 面板区域内开始触摸拖动滚动
                local ap = GS.alchemyPanelRect
                if ap and hitTest(mx, my, ap) then
                    GS.alchemyTouchStartY = my
                    GS.alchemyTouchStartScroll = GS.alchemyScrollY or 0
                end
                return  -- 炼金模式下吞掉其他点击
            end

            -- 烹饪模式拦截
            if GS.cookingMode then
                -- 关闭按钮
                local cr = GS.cookingCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.cookingMode = false
                    GS.homeCookingMode = false
                    GS.cookingResult = nil
                    GS.cookingScrollY = 0
                    GS.cookingBtnRects = {}
                    return
                end
                -- 配方烹饪按钮点击
                for _, btn in ipairs(GS.cookingBtnRects or {}) do
                    if hitTest(mx, my, btn) then
                        local ok, msg = GS.doCooking(btn.idx)
                        GS.cookingResult = { success = ok, msg = msg, timer = 2.0 }
                        -- 开始长按追踪
                        craftHoldType = "cooking"
                        craftHoldIdx = btn.idx
                        craftHoldTimer = 0
                        craftHoldInterval = 0
                        return
                    end
                end
                -- 产出物品图标点击 → 固定 tooltip
                if GS.cookingIconRects then
                    for _, r in ipairs(GS.cookingIconRects) do
                        if my >= r.listY and my <= r.listY + r.listH
                           and hitTest(mx, my, r) then
                            local tpl = GS.itemTemplates[r.templateId]
                            if tpl then
                                GS.tooltipItem = tpl
                                GS.tooltipSlotIdx = 0
                                GS.tooltipSource = "cooking"
                                GS.tooltipEquipSlotId = nil
                                GS.tooltipPinned = true
                                GS.tooltipAnchorRect = r
                            end
                            return
                        end
                    end
                end
                -- 滚动条拖拽检测
                local csb = GS.cookingScrollBarRect
                if csb and mx >= csb.x and mx <= csb.x + csb.w and my >= csb.y and my <= csb.y + csb.h then
                    GS.cookingScrollBarDragging = true
                    GS.cookingScrollBarGrabY = my - csb.y
                    return
                end
                -- 面板区域内开始触摸拖动滚动
                local cp = GS.cookingPanelRect
                if cp and hitTest(mx, my, cp) then
                    GS.cookingTouchStartY = my
                    GS.cookingTouchStartScroll = GS.cookingScrollY or 0
                end
                return  -- 烹饪模式下吞掉其他点击
            end

            -- 委托加工模式拦截
            if GS.craftMode then
                -- 关闭按钮
                local cr = GS.craftCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.craftMode = false
                    GS.homeCraftMode = false
                    GS.craftSlotItem = nil
                    GS.craftSlotSource = nil
                    GS.craftSlotSourceId = nil
                    GS.craftEnhanceResult = nil
                    GS.craftRefineResult = nil
                    GS.craftRepairResult = nil
                    return
                end
                -- 标签页切换
                for _, tr in ipairs(GS.craftTabRects) do
                    if hitTest(mx, my, tr) then
                        if GS.craftTab ~= tr.tab then
                            GS.craftTab = tr.tab
                            -- 切换标签时清除结果提示（保留装备）
                            GS.craftEnhanceResult = nil
                            GS.craftRefineResult = nil
                            GS.craftRepairResult = nil
                            GS.craftExtractResult = nil
                        end
                        return
                    end
                end
                -- 点击放置槽：清空已放入的装备
                local dr = GS.craftDropRect
                if dr and hitTest(mx, my, dr) then
                    if GS.craftSlotItem then
                        GS.craftSlotItem = nil
                        GS.craftSlotSource = nil
                        GS.craftSlotSourceId = nil
                        GS.craftEnhanceResult = nil
                        GS.craftRefineResult = nil
                        GS.craftRepairResult = nil
                    end
                    return
                end
                -- 标签页专属按钮
                if GS.craftTab == "enhance" then
                    -- 催化剂勾选框点击
                    local ccr = GS.enhanceCatalystCheckRect
                    if ccr and hitTest(mx, my, ccr) then
                        GS.enhanceUseCatalyst = not GS.enhanceUseCatalyst
                        return
                    end
                    local ebr = GS.craftEnhanceBtnRect
                    if ebr and hitTest(mx, my, ebr) then
                        if GS.craftSlotItem then
                            -- 临时设置原强化槽变量以复用 GS.enhanceItem()
                            local craftItem = GS.craftSlotItem
                            netCheckedOperation(
                                function()
                                    local origItem = GS.enhanceSlotItem
                                    GS.enhanceSlotItem = craftItem
                                    local ok, msg = GS.enhanceItem()
                                    GS.enhanceSlotItem = origItem
                                    return ok, msg
                                end,
                                function(r) GS.craftEnhanceResult = r end,
                                craftItem,
                                "强化中……"
                            )
                        end
                        return
                    end
                elseif GS.craftTab == "refine" then
                    -- 精炼槽开槽按钮
                    local crdBr = GS.craftRefineDrillBtnRect
                    if crdBr and hitTest(mx, my, crdBr) then
                        local ok, msg = GS.drillRefineSlot(GS.craftSlotItem)
                        GS.craftRefineResult = { success = ok, msg = msg, timer = 2.0 }
                        if ok then GS.saveToCloud() end
                        return
                    end
                    -- 锁定按钮点击
                    if GS.craftRefineLockBtnRects then
                        for i, lockR in ipairs(GS.craftRefineLockBtnRects) do
                            if lockR and hitTest(mx, my, lockR) then
                                local item = GS.craftSlotItem
                                if item and item.refineSlots and item.refineSlots[i] and item.refineSlots[i].attr then
                                    item.refineSlots[i].locked = not item.refineSlots[i].locked
                                end
                                return
                            end
                        end
                    end
                    for i, btnR in pairs(GS.craftRefineSlotBtnRects) do
                        if btnR and hitTest(mx, my, btnR) then
                            local item = GS.craftSlotItem
                            local refineCost = item and GS.getRefineCost(item) or 0
                            local hasGold = item and GS.gold >= refineCost
                            local hasStone = item and GS.countRefineStones(item) > 0
                            if hasGold and hasStone then
                                local slot = item.refineSlots and item.refineSlots[i]
                                if slot and slot.attr then
                                    -- 已有词缀 → 重铸
                                    netCheckedOperation(
                                        function()
                                            local ok = GS.rerollRefineSlot(item, i)
                                            if ok then
                                                GS.gold = GS.gold - refineCost
                                                GS.consumeRefineStone(item)
                                                return true, "重铸成功！"
                                            else
                                                return false, "重铸失败"
                                            end
                                        end,
                                        function(r) GS.craftRefineResult = r end,
                                        item,
                                        "重铸中……"
                                    )
                                else
                                    -- 空槽 → 精炼填充
                                    netCheckedOperation(
                                        function()
                                            local ok = GS.refineItemSlot(item, i)
                                            if ok then
                                                GS.gold = GS.gold - refineCost
                                                GS.consumeRefineStone(item)
                                                return true, "精炼成功！"
                                            else
                                                return false, "精炼失败"
                                            end
                                        end,
                                        function(r) GS.craftRefineResult = r end,
                                        item,
                                        "精炼中……"
                                    )
                                end
                            elseif item and not hasStone then
                                local stoneId = GS.getRequiredStoneId(item)
                                local tpl = GS.itemTemplates[stoneId]
                                GS.craftRefineResult = { success = false, msg = "需要" .. (tpl and tpl.name or "精炼石"), timer = 2.0 }
                            end
                            return
                        end
                    end
                elseif GS.craftTab == "repair" then
                    local rbr = GS.craftRepairBtnRect
                    if rbr and hitTest(mx, my, rbr) then
                        if GS.craftSlotItem then
                            local origItem = GS.repairSlotItem
                            GS.repairSlotItem = GS.craftSlotItem
                            local ok, msg = GS.repairItem()
                            GS.repairSlotItem = origItem
                            GS.craftRepairResult = { success = ok, msg = msg, timer = 2.0 }
                            if ok then GS.saveToCloud() end
                        end
                        return
                    end
                    local tbr = GS.craftToughnessBtnRect
                    if tbr and hitTest(mx, my, tbr) then
                        if GS.craftSlotItem then
                            local origItem = GS.repairSlotItem
                            GS.repairSlotItem = GS.craftSlotItem
                            local ok, msg = GS.repairToughness()
                            GS.repairSlotItem = origItem
                            GS.craftRepairResult = { success = ok, msg = msg, timer = 2.0 }
                            if ok then GS.saveToCloud() end
                        end
                        return
                    end
                elseif GS.craftTab == "extract" then
                    -- 萃取按钮
                    local ebr = GS.craftExtractBtnRect
                    if ebr and hitTest(mx, my, ebr) then
                        if GS.extractSourceItem and GS.extractTargetItem then
                            local ok, msg = GS.extractEnhancement(GS.extractSourceItem, GS.extractTargetItem)
                            GS.craftExtractResult = { success = ok, msg = msg, timer = 2.0 }
                            if ok then
                                GS.saveToCloud()
                                -- 萃取成功后清空槽位
                                GS.extractSourceItem = nil
                                GS.extractTargetItem = nil
                                GS.extractSourceSource = nil
                                GS.extractSourceSourceId = nil
                                GS.extractTargetSource = nil
                                GS.extractTargetSourceId = nil
                            end
                        end
                        return
                    end
                    -- 点击源槽位：归还物品
                    local srcDr = GS.extractSourceDropRect
                    if srcDr and hitTest(mx, my, srcDr) then
                        if GS.extractSourceItem then
                            GS.extractSourceItem = nil
                            GS.extractSourceSource = nil
                            GS.extractSourceSourceId = nil
                        end
                        return
                    end
                    -- 点击目标槽位：归还物品
                    local tgtDr = GS.extractTargetDropRect
                    if tgtDr and hitTest(mx, my, tgtDr) then
                        if GS.extractTargetItem then
                            GS.extractTargetItem = nil
                            GS.extractTargetSource = nil
                            GS.extractTargetSourceId = nil
                        end
                        return
                    end
                end
                return  -- 委托加工模式下吞掉其他点击
            end

            -- 附魔模式拦截
            if GS.enchantMode then
                -- 关闭按钮
                local cr = GS.enchantCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.enchantMode = false
                    GS.homeEnchantMode = false
                    GS.enchantSlotItem = nil
                    GS.enchantSlotSource = nil
                    GS.enchantSlotSourceId = nil
                    GS.enchantResult = nil
                    return
                end
                -- 点击放置槽：清空已放入的装备
                local dr = GS.enchantDropRect
                if dr and hitTest(mx, my, dr) then
                    if GS.enchantSlotItem then
                        GS.enchantSlotItem = nil
                        GS.enchantSlotSource = nil
                        GS.enchantSlotSourceId = nil
                        GS.enchantResult = nil
                    end
                    return
                end
                -- 附魔按钮
                local ebr = GS.enchantBtnRect
                if ebr and hitTest(mx, my, ebr) then
                    local item = GS.enchantSlotItem
                    if item and item.slot then
                        local agentCount = GS.countInventoryItem("divine_enchant_agent")
                        if agentCount >= 1 then
                            netCheckedOperation(
                                function()
                                    -- 消耗1个神炼附魔剂
                                    local removed = GS.removeInventoryItem("divine_enchant_agent", 1)
                                    if not removed then
                                        return false, "附魔剂不足"
                                    end
                                    -- 获取装备T级并附魔
                                    local tier = GS.getItemTier(item)
                                    GS.rollEnchantment(item, tier)
                                    if item.enchantment then
                                        return true, "附魔成功！获得词缀: " .. (item.enchantment.name or "")
                                    else
                                        return false, "附魔失败：无可用词缀"
                                    end
                                end,
                                function(r) GS.enchantResult = r end,
                                item,
                                "附魔中……"
                            )
                        else
                            GS.enchantResult = { success = false, msg = "需要神炼附魔剂", timer = 2.0 }
                        end
                    end
                    return
                end
                return  -- 附魔模式下吞掉其他点击
            end

            -- 赠送模式拦截
            if GS.giftMode then
                -- 关闭按钮
                local clr = GS.giftCloseRect
                if clr and hitTest(mx, my, clr) then
                    local fromHome = GS.giftFromHome
                    local npcKey = GS.giftNpcKey
                    GS.cancelGift()
                    if fromHome and npcKey then
                        M._startHomePartnerTalk(npcKey)
                    end
                    return
                end
                -- 点击放置槽：归还物品到背包并清空槽位
                local dr = GS.giftDropRect
                if dr and hitTest(mx, my, dr) then
                    if GS.giftSlotItem then
                        GS.returnGiftSlotItem()
                    end
                    return
                end
                -- 确认赠送按钮：执行赠送 → 关闭面板 → 对话框显示回应
                local cfr = GS.giftConfirmRect
                if cfr and hitTest(mx, my, cfr) then
                    if GS.giftSlotItem then
                        local bKey = GS.giftBuildingKey
                        local fromHome = GS.giftFromHome
                        local npcName = GS.giftNpcName or "NPC"
                        local npcKey = GS.giftNpcKey
                        GS.executeGift()
                        local resultText = GS.giftResultText or ""
                        local resultLiked = GS.giftResultLiked
                        local gain = GS.giftAffinityGain or 0
                        -- 关闭赠送面板（会清空 giftAffinityGain，所以必须先读取）
                        GS.closeGiftResult()
                        -- 家中送礼：恢复对话锁定，使对话框能渲染和推进
                        if fromHome then
                            GS.homePartnerTalkActive = true
                            GS.eventInputLocked = true
                        end
                        -- 用标准对话框显示NPC回应
                        local DialogueManager = require("DialogueManager")
                        DialogueManager.startDynamic({
                            { speaker = npcName, text = resultText }
                        }, function()
                            if fromHome and npcKey then
                                M._startHomePartnerTalk(npcKey)
                            elseif bKey then
                                triggerNpcTalk(bKey)
                            end
                        end)
                    end
                    return
                end
                -- 取消按钮
                local cnr = GS.giftCancelRect
                if cnr and hitTest(mx, my, cnr) then
                    local fromHome = GS.giftFromHome
                    local npcKey = GS.giftNpcKey
                    GS.cancelGift()
                    if fromHome and npcKey then
                        M._startHomePartnerTalk(npcKey)
                    end
                    return
                end
                return  -- 赠送模式下吞掉其他点击
            end

            -- 任务物品提交模式拦截
            if GS.questSubmitMode then
                -- 关闭按钮
                local clr = GS.questSubmitCloseRect
                if clr and hitTest(mx, my, clr) then
                    local bKey = GS.questSubmitBuildingKey
                    GS.cancelQuestSubmit()
                    if bKey then triggerNpcTalk(bKey) end
                    return
                end
                -- 点击放置槽：归还物品到背包并清空槽位
                local dr = GS.questSubmitDropRect
                if dr and hitTest(mx, my, dr) then
                    if GS.questSubmitSlotItem then
                        GS.returnQuestSubmitItem()
                    end
                    return
                end
                -- 确认提交按钮
                local cfr = GS.questSubmitConfirmRect
                if cfr and hitTest(mx, my, cfr) then
                    if GS.questSubmitSlotItem then
                        local bKey = GS.questSubmitBuildingKey
                        local npcName = GS.questSubmitNpcName or "NPC"
                        local questId = GS.questSubmitQuestId
                        local qDef = GS.questSubmitDef
                        local QuestManager = require("QuestManager")

                        if qDef and qDef.requireItemFilter then
                            -- ── requireItemFilter 模式：槽位物品直接消耗 ──
                            local submittedItem = GS.questSubmitSlotItem
                            GS.questSubmitSlotItem = nil
                            GS.questSubmitSlotSource = nil
                            GS.questSubmitSlotSourceId = nil

                            if qDef.onItemSubmitted then
                                -- 多次提交模式：回调记录已提交物品
                                local st = QuestManager.questStates[questId]
                                local result = qDef.onItemSubmitted(GS, st, submittedItem)
                                -- 兼容：true 表示完成，table.done 表示完成
                                local done = (result == true) or (type(result) == "table" and result.done)
                                if done then
                                    -- 所有物品已提交完毕，完成任务
                                    if st then st.status = QuestManager.STATUS_READY end
                                    local ral = qDef.rewardAtLine
                                    if ral ~= nil then
                                        QuestManager._doCompleteNoReward(questId)
                                    else
                                        QuestManager._doComplete(questId)
                                    end
                                    -- 关闭面板
                                    GS.questSubmitMode = false
                                    GS.questSubmitQuestId = nil
                                    GS.questSubmitDef = nil
                                    GS.questSubmitNpcName = nil
                                    GS.questSubmitBuildingKey = nil
                                    GS.questSubmitRejectMsg = nil
                                    GS.questSubmitDropRect = nil
                                    GS.questSubmitConfirmRect = nil
                                    GS.questSubmitCancelRect = nil
                                    GS.questSubmitCloseRect = nil
                                    -- 显示完成对话
                                    local nk = qDef.npc and qDef.npc.npcKey or bKey
                                    local dlgLines = flattenDialogue(qDef.submitDialogue, function(t)
                                        return replaceDialogueTags(t, nk)
                                    end)
                                    local afterDlg = function()
                                        GS.saveToCloud()
                                        if bKey then triggerNpcTalk(bKey) end
                                    end
                                    if ral ~= nil and #dlgLines > 0 then
                                        afterDlg = injectRewardCallback(dlgLines, questId, ral, afterDlg)
                                    end
                                    if #dlgLines > 0 then
                                        local DialogueManager = require("DialogueManager")
                                        DialogueManager.startDynamic(dlgLines, afterDlg)
                                    else
                                        if ral ~= nil then
                                            QuestManager._doGiveRewards(questId)
                                        end
                                        GS.saveToCloud()
                                        if bKey then triggerNpcTalk(bKey) end
                                    end
                                else
                                    -- 还需要继续提交
                                    local midDialogue = type(result) == "table" and result.dialogue or nil
                                    if midDialogue and #midDialogue > 0 then
                                        -- 有中间提交对话：暂时关闭面板，播放对话，对话结束后重新打开
                                        GS.questSubmitMode = false
                                        -- 构造对话行
                                        local nkMid = qDef.npc and qDef.npc.npcKey or bKey
                                        local dlgLines = {}
                                        for _, dl in ipairs(midDialogue) do
                                            local text = replaceDialogueTags(dl.text, nkMid)
                                            dlgLines[#dlgLines + 1] = { speaker = dl.speaker, text = text }
                                        end
                                        local DialogueManager = require("DialogueManager")
                                        DialogueManager.startDynamic(dlgLines, function()
                                            GS.saveToCloud()
                                            -- 对话结束后重新打开提交面板
                                            GS.questSubmitMode = true
                                            GS.questSubmitQuestId = questId
                                            GS.questSubmitDef = qDef
                                        end)
                                    else
                                        -- 无对话，显示提示信息
                                        local tpl = GS.itemTemplates and GS.itemTemplates[submittedItem.templateId]
                                        local itemName = tpl and tpl.name or submittedItem.templateId
                                        GS.questSubmitRejectMsg = { text = itemName .. " 已收下，请继续提交", timer = 2.0 }
                                        GS.saveToCloud()
                                    end
                                end
                            else
                                -- 单次提交模式（requireItemFilter 无 onItemSubmitted）
                                -- 直接设为 ready 并完成
                                local st = QuestManager.questStates[questId]
                                if st then st.status = QuestManager.STATUS_READY end
                                local useDeferred3 = qDef.rewardAtLine ~= nil
                                if useDeferred3 then
                                    QuestManager._doCompleteNoReward(questId)
                                else
                                    QuestManager._doComplete(questId)
                                end
                                -- 关闭面板
                                GS.questSubmitMode = false
                                GS.questSubmitQuestId = nil
                                GS.questSubmitDef = nil
                                GS.questSubmitNpcName = nil
                                GS.questSubmitBuildingKey = nil
                                GS.questSubmitRejectMsg = nil
                                GS.questSubmitDropRect = nil
                                GS.questSubmitConfirmRect = nil
                                GS.questSubmitCancelRect = nil
                                GS.questSubmitCloseRect = nil
                                -- 显示完成对话
                                local nk2 = qDef.npc and qDef.npc.npcKey or bKey
                                local dlgLines = flattenDialogue(qDef.submitDialogue, function(t)
                                    return replaceDialogueTags(t, nk2)
                                end)
                                local origOnComplete3 = function()
                                    GS.saveToCloud()
                                    if bKey then triggerNpcTalk(bKey) end
                                end
                                if useDeferred3 and #dlgLines > 0 then
                                    origOnComplete3 = injectRewardCallback(dlgLines, questId, qDef.rewardAtLine, origOnComplete3)
                                end
                                if #dlgLines > 0 then
                                    local DialogueManager = require("DialogueManager")
                                    DialogueManager.startDynamic(dlgLines, origOnComplete3)
                                else
                                    if useDeferred3 then
                                        QuestManager._doGiveRewards(questId)
                                    end
                                    origOnComplete3()
                                end
                            end
                        else
                            -- ── 原有 requireItems 模式：归还后由 _doComplete 消耗 ──
                            -- 先验证背包+提交槽中的物品总量是否满足任务要求
                            local canSubmit = true
                            if qDef and qDef.requireItems then
                                for _, reqItem in ipairs(qDef.requireItems) do
                                    local bagCount = GS.countInventoryItem(reqItem.templateId)
                                    local slotCount = 0
                                    local slotItem = GS.questSubmitSlotItem
                                    if slotItem and slotItem.templateId == reqItem.templateId then
                                        slotCount = slotItem.quantity or 1
                                    end
                                    if bagCount + slotCount < (reqItem.count or 1) then
                                        canSubmit = false
                                        local tpl = GS.itemTemplates and GS.itemTemplates[reqItem.templateId]
                                        local itemName = tpl and tpl.name or reqItem.templateId
                                        GS.questSubmitRejectMsg = {
                                            text = itemName .. " 数量不足（需要 " .. (reqItem.count or 1) .. " 个）",
                                            timer = 2.0
                                        }
                                        break
                                    end
                                end
                            end
                            if not canSubmit then
                                return
                            end
                            GS.returnQuestSubmitItem()
                            local useDeferred4 = qDef and qDef.rewardAtLine ~= nil
                            if useDeferred4 then
                                QuestManager.tryNpcSubmitDeferred(bKey, questId)
                            else
                                QuestManager.tryNpcSubmit(bKey, questId)
                            end
                            -- 关闭面板
                            GS.questSubmitMode = false
                            GS.questSubmitQuestId = nil
                            GS.questSubmitDef = nil
                            GS.questSubmitNpcName = nil
                            GS.questSubmitBuildingKey = nil
                            GS.questSubmitRejectMsg = nil
                            GS.questSubmitDropRect = nil
                            GS.questSubmitConfirmRect = nil
                            GS.questSubmitCancelRect = nil
                            GS.questSubmitCloseRect = nil
                            -- 显示完成对话
                            local nk3 = qDef and qDef.npc and qDef.npc.npcKey or bKey
                            local dlgLines = flattenDialogue(qDef and qDef.submitDialogue, function(t)
                                return replaceDialogueTags(t, nk3)
                            end)
                            local origOnComplete4 = function()
                                GS.saveToCloud()
                                if bKey then triggerNpcTalk(bKey) end
                            end
                            if useDeferred4 and #dlgLines > 0 then
                                origOnComplete4 = injectRewardCallback(dlgLines, questId, qDef.rewardAtLine, origOnComplete4)
                            end
                            if #dlgLines > 0 then
                                local DialogueManager = require("DialogueManager")
                                DialogueManager.startDynamic(dlgLines, origOnComplete4)
                            else
                                if useDeferred4 then
                                    QuestManager._doGiveRewards(questId)
                                end
                                origOnComplete4()
                            end
                        end
                    end
                    return
                end
                -- 取消按钮
                local cnr = GS.questSubmitCancelRect
                if cnr and hitTest(mx, my, cnr) then
                    local bKey = GS.questSubmitBuildingKey
                    GS.cancelQuestSubmit()
                    if bKey then triggerNpcTalk(bKey) end
                    return
                end
                return  -- 任务提交模式下吞掉其他点击
            end

            -- 修复模式拦截
            if GS.repairMode then
                -- 关闭按钮
                local cr = GS.repairCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.repairMode = false
                    GS.repairResult = nil
                    GS.repairSlotItem = nil
                    GS.repairSlotSource = nil
                    GS.repairSlotSourceId = nil
                    return
                end
                -- 点击放置槽：清空已放入的装备
                local dr = GS.repairDropRect
                if dr and hitTest(mx, my, dr) then
                    if GS.repairSlotItem then
                        GS.repairSlotItem = nil
                        GS.repairSlotSource = nil
                        GS.repairSlotSourceId = nil
                        GS.repairResult = nil
                    end
                    return
                end
                -- 脆化修复按钮点击
                local rbr = GS.repairBtnRect
                if rbr and hitTest(mx, my, rbr) then
                    if GS.repairSlotItem then
                        local ok, msg = GS.repairItem()
                        GS.repairResult = { success = ok, msg = msg, timer = 2.0 }
                    end
                    return
                end
                -- 韧性修复按钮点击
                local tbr = GS.toughnessBtnRect
                if tbr and hitTest(mx, my, tbr) then
                    if GS.repairSlotItem then
                        local ok, msg = GS.repairToughness()
                        GS.repairResult = { success = ok, msg = msg, timer = 2.0 }
                    end
                    return
                end
                return  -- 修复模式下吞掉其他点击
            end

            -- 精炼模式拦截
            if GS.refineMode then
                -- 关闭按钮
                local cr = GS.refineCloseRect
                if cr and hitTest(mx, my, cr) then
                    GS.refineMode = false
                    GS.refineResult = nil
                    GS.refineSlotItem = nil
                    GS.refineSlotSource = nil
                    GS.refineSlotSourceId = nil
                    return
                end
                -- 点击放置槽：清空已放入的装备
                local dr = GS.refineDropRect
                if dr and hitTest(mx, my, dr) then
                    if GS.refineSlotItem then
                        GS.refineSlotItem = nil
                        GS.refineSlotSource = nil
                        GS.refineSlotSourceId = nil
                        GS.refineResult = nil
                    end
                    return
                end
                -- 精炼开槽按钮点击
                local rdbr = GS.refineDrillBtnRect
                if rdbr and hitTest(mx, my, rdbr) then
                    local ok, msg = GS.drillRefineSlot()
                    GS.refineResult = { success = ok, msg = msg, timer = 2.0 }
                    return
                end
                -- 锁定按钮点击
                if GS.refineLockBtnRects then
                    for i, lockR in ipairs(GS.refineLockBtnRects) do
                        if lockR and hitTest(mx, my, lockR) then
                            local item = GS.refineSlotItem
                            if item and item.refineSlots and item.refineSlots[i] and item.refineSlots[i].attr then
                                item.refineSlots[i].locked = not item.refineSlots[i].locked
                            end
                            return
                        end
                    end
                end
                -- 各精炼槽按钮点击
                for i, btnR in pairs(GS.refineSlotBtnRects) do
                    if btnR and hitTest(mx, my, btnR) then
                        local item = GS.refineSlotItem
                        local refineCost = item and GS.getRefineCost(item) or 0
                        local hasGold = item and GS.gold >= refineCost
                        local hasStone = item and GS.countRefineStones(item) > 0
                        if hasGold and hasStone then
                            local slot = item.refineSlots and item.refineSlots[i]
                            if slot and slot.attr then
                                -- 已有词缀 → 重铸
                                netCheckedOperation(
                                    function()
                                        local ok = GS.rerollRefineSlot(item, i)
                                        if ok then
                                            GS.gold = GS.gold - refineCost
                                            GS.consumeRefineStone(item)
                                            return true, "重铸成功！"
                                        else
                                            return false, "重铸失败"
                                        end
                                    end,
                                    function(r) GS.refineResult = r end,
                                    item,
                                    "重铸中……"
                                )
                            else
                                -- 空槽 → 精炼填充
                                netCheckedOperation(
                                    function()
                                        local ok = GS.refineItemSlot(item, i)
                                        if ok then
                                            GS.gold = GS.gold - refineCost
                                            GS.consumeRefineStone(item)
                                            return true, "精炼成功！"
                                        else
                                            return false, "精炼失败"
                                        end
                                    end,
                                    function(r) GS.refineResult = r end,
                                    item,
                                    "精炼中……"
                                )
                            end
                        elseif item and not hasStone then
                            local stoneId = GS.getRequiredStoneId(item)
                            local tpl = GS.itemTemplates[stoneId]
                            GS.refineResult = { success = false, msg = "需要" .. (tpl and tpl.name or "精炼石"), timer = 2.0 }
                        end
                        return
                    end
                end
                return  -- 精炼模式下吞掉其他点击
            end

            -- 强化模式拦截
            if GS.enhanceMode then
                -- 关闭按钮
                local cr = GS.enhanceCloseRect
                if hitTest(mx, my, cr) then
                    GS.enhanceMode = false
                    GS.enhanceResult = nil
                    GS.enhanceSlotItem = nil
                    GS.enhanceSlotSource = nil
                    GS.enhanceSlotSourceId = nil
                    return
                end
                -- 点击放置槽：清空已放入的装备
                local dr = GS.enhanceDropRect
                if hitTest(mx, my, dr) then
                    if GS.enhanceSlotItem then
                        GS.enhanceSlotItem = nil
                        GS.enhanceSlotSource = nil
                        GS.enhanceSlotSourceId = nil
                        GS.enhanceResult = nil
                    end
                    return
                end
                -- 催化剂勾选框点击
                local ccr2 = GS.enhanceCatalystCheckRect
                if ccr2 and hitTest(mx, my, ccr2) then
                    GS.enhanceUseCatalyst = not GS.enhanceUseCatalyst
                    return
                end
                -- 强化按钮点击
                local ebr = GS.enhanceBtnRect
                if hitTest(mx, my, ebr) then
                    if GS.enhanceSlotItem then
                        netCheckedOperation(
                            function() return GS.enhanceItem() end,
                            function(r) GS.enhanceResult = r end,
                            GS.enhanceSlotItem,
                            "强化中……"
                        )
                    end
                    return
                end
                return  -- 强化模式下吞掉其他点击
            end

            -- 广告加载面板取消按钮
            if GS.adLoading and GS.adCancelRect then
                local cr = GS.adCancelRect
                if hitTest(mx, my, cr) then
                    GS.adLoading = false
                    GS.adCancelRect = nil
                    return
                end
                return  -- 加载中吞掉其他点击
            end

            -- 兑换面板关闭按钮
            if GS.exchangeMode and GS.exchangeCloseRect then
                local cr = GS.exchangeCloseRect
                if hitTest(mx, my, cr) then
                    GS.exitExchangeMode()
                    return
                end
            end

            -- 深渊兑换面板关闭按钮
            if GS.abyssExchangeMode and GS.abyssExchangeCloseRect then
                if hitTest(mx, my, GS.abyssExchangeCloseRect) then
                    GS.exitAbyssExchangeMode()
                    return
                end
            end

            -- 深渊兑换列表区域：启动拖动（mouseUp 时判断是点击还是拖动）
            if GS.abyssExchangeMode and GS.abyssExchangeListClipRect then
                local clip = GS.abyssExchangeListClipRect
                if hitTest(mx, my, clip) then
                    GS.abyssExchangeListDragging = true
                    GS.abyssExchangeListDragStartY = my
                    GS.abyssExchangeListDragStartScroll = GS.abyssExchangeScrollY
                    GS.abyssExchangeListDragMoved = false
                    return
                end
            end

            -- 深渊兑换面板打开时吞掉其他点击
            if GS.abyssExchangeMode then
                return
            end

            -- 兑换滚动条拖拽
            if GS.exchangeMode and GS.exchangeScrollBarTrack then
                local sb = GS.exchangeScrollBarTrack
                if hitTest(mx, my, sb) then
                    GS.exchangeScrollBarDragging = true
                    GS.exchangeScrollBarDragStartY = my
                    GS.exchangeScrollBarDragStartScroll = GS.exchangeScrollY
                    return
                end
            end

            -- 兑换列表区域：启动拖动
            if GS.exchangeMode and GS.exchangeListClipRect then
                local clip = GS.exchangeListClipRect
                if hitTest(mx, my, clip) then
                    GS.exchangeListDragging = true
                    GS.exchangeListDragStartY = my
                    GS.exchangeListDragStartScroll = GS.exchangeScrollY
                    GS.exchangeListDragMoved = false
                    return
                end
            end

            -- 兑换面板打开时吞掉其他点击
            if GS.exchangeMode then
                return
            end

            -- 商店关闭按钮
            if GS.shopMode and GS.shopCloseRect then
                local cr = GS.shopCloseRect
                if hitTest(mx, my, cr) then
                    GS.exitShopMode()
                    return
                end
            end

            -- 商店滚动条拖拽
            if GS.shopMode and GS.shopScrollBarTrack then
                local sb = GS.shopScrollBarTrack
                if hitTest(mx, my, sb) then
                    GS.shopScrollBarDragging = true
                    GS.shopScrollBarDragStartY = my
                    GS.shopScrollBarDragStartScroll = GS.shopScrollY
                    return
                end
            end

            -- 商品列表区域：启动拖动（mouseUp 时判断是点击还是拖动）
            if GS.shopMode and GS.shopListClipRect then
                local clip = GS.shopListClipRect
                if hitTest(mx, my, clip) then
                    GS.shopListDragging = true
                    GS.shopListDragStartY = my
                    GS.shopListDragStartScroll = GS.shopScrollY
                    GS.shopListDragMoved = false
                    return
                end
            end

            -- 仓库关闭按钮
            if GS.warehouseMode and GS.warehouseCloseRect then
                local cr = GS.warehouseCloseRect
                if hitTest(mx, my, cr) then
                    GS.exitWarehouseMode()
                    return
                end
            end

            -- 共享仓库关闭按钮
            if GS.sharedStorageMode and GS.sharedStorageCloseRect then
                local cr = GS.sharedStorageCloseRect
                if hitTest(mx, my, cr) then
                    GS.exitSharedStorageMode()
                    return
                end
            end

            -- 共享仓库日志面板关闭按钮
            if GS.sharedStorageMode and GS.sharedStorageLogOpen and GS.sharedStorageLogCloseRect then
                local cr = GS.sharedStorageLogCloseRect
                if hitTest(mx, my, cr) then
                    GS.sharedStorageLogOpen = false
                    GS.sharedStorageLogLines = nil
                    return
                end
            end

            -- 共享仓库日志面板滚动按钮
            if GS.sharedStorageMode and GS.sharedStorageLogOpen then
                if GS.sharedStorageLogScrollUpRect and hitTest(mx, my, GS.sharedStorageLogScrollUpRect) then
                    GS.sharedStorageLogScroll = math.max(0, (GS.sharedStorageLogScroll or 0) - 1)
                    return
                end
                if GS.sharedStorageLogScrollDownRect and hitTest(mx, my, GS.sharedStorageLogScrollDownRect) then
                    local total = GS.sharedStorageLogLines and #GS.sharedStorageLogLines or 0
                    local visRows = GS.sharedStorageLogVisibleRows or 10
                    local maxScroll = math.max(0, total - visRows)
                    GS.sharedStorageLogScroll = math.min(maxScroll, (GS.sharedStorageLogScroll or 0) + 1)
                    return
                end
            end

            -- 共享仓库日志面板：面板内启动拖拽滚动（防止点击穿透到仓库格子）
            if GS.sharedStorageMode and GS.sharedStorageLogOpen and GS.sharedStorageLogPanelRect then
                if hitTest(mx, my, GS.sharedStorageLogPanelRect) then
                    GS.sharedStorageLogDragging = true
                    GS.sharedStorageLogDragStartY = my
                    GS.sharedStorageLogDragStartScroll = GS.sharedStorageLogScroll or 0
                    return
                end
            end

            -- 共享仓库按钮点击（取出 / 查看记录）
            if GS.sharedStorageMode and GS.sharedStorageBtnRects and not GS.sharedStorageLogOpen then
                local logRect = GS.sharedStorageBtnRects["log"]
                if logRect and hitTest(mx, my, logRect) then
                    local SSLog = require("SharedStorageLog")
                    -- 先显示"加载中"占位，云端回调后刷新列表
                    GS.sharedStorageLogLines = { "正在加载记录..." }
                    GS.sharedStorageLogOpen  = true
                    GS.sharedStorageLogScroll = 0
                    SSLog.getReversed(function(lines)
                        -- 仍在共享仓库且日志面板还开着才更新
                        if GS.sharedStorageMode and GS.sharedStorageLogOpen then
                            GS.sharedStorageLogLines = lines
                            GS.sharedStorageLogScroll = 0
                        end
                    end)
                    return
                end
            end

            -- 遗失物品关闭按钮
            if GS.lostItemsMode and GS.lostItemsCloseRect then
                local cr = GS.lostItemsCloseRect
                if hitTest(mx, my, cr) then
                    GS.exitLostItemsMode()
                    return
                end
            end

            -- 遗失物品按钮点击
            if GS.lostItemsMode and GS.lostItemsBtnRects then
                for key, r in pairs(GS.lostItemsBtnRects) do
                    if hitTest(mx, my, r) then
                        if key == "withdraw_all" then
                            local count, failCount = GS.withdrawAllLostItems()
                            if count > 0 and failCount > 0 then
                                GS.shopBuyMsg = { text = "取回" .. count .. "件，" .. failCount .. "件因背包满无法取回", timer = 2.5, color = {200, 160, 30} }
                            elseif count > 0 then
                                GS.shopBuyMsg = { text = "已全部取回（" .. count .. "件）", timer = 2.0, color = {60, 160, 60} }
                            elseif failCount > 0 then
                                GS.shopBuyMsg = { text = "背包已满，无法取回", timer = 2.0, color = {220, 60, 40} }
                            else
                                GS.shopBuyMsg = { text = "没有可取回的物品", timer = 1.5, color = {140, 100, 50} }
                            end
                        end
                        return
                    end
                end
            end

            -- 遗失物品格子点击（记录拖拽起始 + 显示悬停信息）
            if GS.lostItemsMode and GS.lostItemsSlotAreas then
                for idx, r in pairs(GS.lostItemsSlotAreas) do
                    if hitTest(mx, my, r) then
                        if GS.lostItems[idx] then
                            -- 记录拖拽起始
                            GS.dragLostItemIdx = idx
                            GS.lostItemDragActive = false
                            GS.itemDragStartX = mx
                            GS.itemDragStartY = my
                            -- 显示悬停信息（pin tooltip）
                            GS.tooltipItem = GS.lostItems[idx]
                            GS.tooltipSlotIdx = 0
                            GS.tooltipSource = "lost_items"
                            GS.tooltipEquipSlotId = nil
                            GS.tooltipAnchorRect = r
                            GS.tooltipPinned = true
                            GS.tooltipPinnedPos = nil
                            GS.tooltipScrollY = 0
                        end
                        return
                    end
                end
            end

            -- 布告栏委托：左右箭头切换
            if GS.bulletinArrowLeftRect and hitTest(mx, my, GS.bulletinArrowLeftRect) then
                GS.bulletinQuestIndex = math.max(1, (GS.bulletinQuestIndex or 1) - 1)
                return
            end
            if GS.bulletinArrowRightRect and hitTest(mx, my, GS.bulletinArrowRightRect) then
                local BulletinBoard = require("BulletinBoard")
                local maxIdx = BulletinBoard.quests and #BulletinBoard.quests or 5
                GS.bulletinQuestIndex = math.min(maxIdx, (GS.bulletinQuestIndex or 1) + 1)
                return
            end
            -- 布告栏委托：操作按钮（提交/领取）
            if GS.bulletinQuestBtnRect then
                local r = GS.bulletinQuestBtnRect
                if hitTest(mx, my, r) then
                    local BulletinBoard = require("BulletinBoard")
                    local idx = GS.bulletinQuestIndex or 1
                    if r.action == "accept" then
                        BulletinBoard.acceptQuest(idx)
                    elseif r.action == "submitComplete" then
                        -- 确认提交委托（ready → completed）
                        local ok = BulletinBoard.submitComplete(idx)
                        if ok then
                            BoardOverlay.triggerStampAnim(idx)
                        end
                    elseif r.action == "claim" then
                        local ok = BulletinBoard.claimReward(idx)
                        if ok then
                            -- 领奖时如果还没盖章（从日志提交的情况），补触发
                        end
                    elseif r.action == "submit" then
                        BulletinBoard.trySubmit(idx)
                    end
                    return
                end
            end
            -- 布告栏委托：换一个按钮（看广告重新随机）
            if GS.bulletinQuestRerollBtnRect then
                local rr = GS.bulletinQuestRerollBtnRect
                if hitTest(mx, my, rr) then
                    local BulletinBoard = require("BulletinBoard")
                    local idx = GS.bulletinQuestIndex or 1
                    local q = BulletinBoard.quests and BulletinBoard.quests[idx]
                    if q and not q.rewarded and not q.ready and not q.completed then
                        -- 看广告换委托（未接取 或 已接取进行中 均可）
                        -- 免广告用户：直接换委托
                        if GS.adFree then
                            BulletinBoard.rerollQuest(idx)
                            print("[AdFree] 免广告用户，直接重新随机委托")
                            return
                        end
                        -- PC端不支持广告
                        if PlatformUtils.IsDesktopPlatform() then
                            local DM = require("DialogueManager")
                            DM.startDynamic({ { speaker = "旁白", text = "（通过这个叫做台式电脑的设备无法传输力量……）" } })
                            return
                        end
                        GS.adSessionId = GS.adSessionId + 1
                        local thisSession = GS.adSessionId
                        MonitorPanel.reportAdClick()
                        sdk:ShowRewardVideoAd(function(result)
                            if result and result.success then
                                -- 广告确实看完，无论游戏状态如何都发放奖励
                                MonitorPanel.reportAdSuccess()
                                BulletinBoard.rerollQuest(idx)
                                print("[布告栏] 广告观看成功，已重新随机委托")
                            else
                                -- 广告未完成，检查状态避免过期回调弹出多余提示
                                if thisSession ~= GS.adSessionId then return end
                                MonitorPanel.reportAdFail()
                                print("[布告栏] 广告未完成，取消换一个")
                            end
                        end)
                    end
                    return
                end
            end

            -- 仓库底部按钮点击
            if GS.warehouseMode and GS.warehouseBtnRects then
                for key, r in pairs(GS.warehouseBtnRects) do
                    if hitTest(mx, my, r) then
                        if key == "withdraw" then
                            -- 取出按钮：多选模式下批量取出，非多选模式下无操作
                            if GS.warehouseMultiSelect then
                                local selCount = 0
                                for _ in pairs(GS.warehouseSelected) do selCount = selCount + 1 end
                                if selCount > 0 then
                                    GS.batchWithdrawFromWarehouse(GS.warehouseSelected)
                                    GS.warehouseMultiSelect = false
                                    GS.warehouseSelected = {}
                                end
                            end
                        elseif GS.warehouseMultiSelect then
                            if key == "cancel" then
                                GS.warehouseMultiSelect = false
                                GS.warehouseSelected = {}
                            end
                        else
                            if key == "sort" then
                                GS.sortWarehouse()
                            elseif key == "multi" then
                                GS.warehouseMultiSelect = true
                                GS.warehouseSelected = {}
                                GS.closeTooltip()
                            end
                        end
                        return
                    end
                end
            end

            -- 仓库滚动条拖拽
            if GS.warehouseMode and GS.warehouseScrollBarTrack then
                local sb = GS.warehouseScrollBarTrack
                if hitTest(mx, my, sb) then
                    GS.warehouseScrollBarDragging = true
                    GS.warehouseScrollBarDragStartY = my
                    GS.warehouseScrollBarDragStartScroll = GS.warehouseScrollY
                    return
                end
            end

            -- 仓库格子区域拖动/点击
            if GS.warehouseMode and GS.warehouseClipRect then
                local clip = GS.warehouseClipRect
                if hitTest(mx, my, clip) then
                    GS.warehouseDragging = true
                    GS.warehouseDragStartY = my
                    GS.warehouseDragStartScroll = GS.warehouseScrollY
                    GS.warehouseDragMoved = false
                    -- 检查是否按住了仓库物品格子（用于拖拽）
                    GS.dragWarehouseIdx = nil
                    if GS.warehouseSlotAreas then
                        for idx, sr in pairs(GS.warehouseSlotAreas) do
                            if hitTest(mx, my, sr) then
                                if GS.warehouse[idx] then
                                    GS.dragWarehouseIdx = idx
                                    GS.itemDragStartX = mx
                                    GS.itemDragStartY = my
                                    GS.itemDragActive = false
                                end
                                break
                            end
                        end
                    end
                    return
                end
            end

            -- 共享仓库格子区域点击
            if GS.sharedStorageMode and GS.sharedStorageSlotAreas then
                for idx, sr in pairs(GS.sharedStorageSlotAreas) do
                    if hitTest(mx, my, sr) then
                        if GS.sharedStorage[idx] then
                            GS.dragSharedStorageIdx = idx
                            GS.itemDragStartX = mx
                            GS.itemDragStartY = my
                            GS.itemDragActive = false
                        end
                        return
                    end
                end
            end

            -- 冒险者等级晋升按钮（仅在公会场景有效）
            if BoardOverlay.rankPromoteBtn and BoardOverlay.subScene and BoardOverlay.subScene.id == "guild" and hitTest(mx, my, BoardOverlay.rankPromoteBtn) then
                if GS.canPromoteRank() then
                    local oldRank = GS.adventurerRank
                    if GS.promoteRank() then
                        local promo = GS.RANK_PROMOTIONS[GS.adventurerRank]
                        local rankLetter = promo and promo.rank or "?"
                        print("[晋升] 冒险者等级 " .. oldRank .. " → " .. GS.adventurerRank .. " (" .. rankLetter .. "级)")
                        -- 显示晋升提示
                        if Combat.addDamageText and GS.player then
                            Combat.addDamageText(GS.player.x, GS.player.y - 1.5,
                                "晋升! " .. rankLetter .. "级 全属性+" .. (promo and promo.bonus or 0),
                                {255, 220, 50})
                        end
                    end
                end
                return
            end

            -- 对话激活时：优先处理选项点击，否则推进对话
            local DialogueManager = require("DialogueManager")
            if DialogueManager.active then
                -- 自愈：对话系统认为自己在运行，但对话框实际不可见（渲染门控阻塞）
                -- 此时 waitingForChoice=true 会导致永久卡死（advance被阻塞、选项不可见无法选择）
                -- 检测到这种状态时强制重置，让点击正常传递到下方的按钮处理
                -- 注意：酒馆肉搏/事件/竞技场对话走 Renderer.drawEventDialogue，不设置 dialogueBoxRect，需排除
                local isEventDialogue = GS.tavernBrawlState or GS.brawlCinematic or GS.isEvent or GS.arenaTransition or GS.homePartnerTalkActive
                if not BoardOverlay.dialogueBoxRect and not isEventDialogue then
                    print("[TalkSelfHeal] DM.active but dialogueBox invisible, force resetting. waitChoice=" .. tostring(DialogueManager.waitingForChoice))
                    DialogueManager._dynamicOnComplete = nil
                    DialogueManager.active = false
                    DialogueManager.waitingForChoice = false
                    DialogueManager.choiceResult = nil
                    DialogueManager.currentId = nil
                    DialogueManager.currentLines = nil
                    DialogueManager.lineIndex = 0
                    -- 重置后不 return，让点击继续传递到按钮处理逻辑
                else
                    if DialogueManager.waitingForChoice and GS._choiceRects then
                        for i, rect in ipairs(GS._choiceRects) do
                            if hitTest(mx, my, rect) then
                                DialogueManager.selectChoice(i)
                                return
                            end
                        end
                        return  -- 等待选择期间点击其他区域不响应
                    end
                    DialogueManager.advance()
                    return
                end
            end

            -- 子场景按钮点击（商品列表/仓库/兑换面板打开时屏蔽）
            if GS.shopMode or GS.warehouseMode or GS.exchangeMode or GS.adLoading or GS.lostItemsMode then return end
            for _, r in ipairs(BoardOverlay.subSceneBtnRects) do
                if hitTest(mx, my, r) then
                    if r.action == "exit" then
                        -- 森林精灵场景：离开 → 直接切换到目标关卡
                        local subId = BoardOverlay.subScene and BoardOverlay.subScene.id or ""
                        if subId == "forest_elf" and GS._forestElfPendingSwitch then
                            local pendingSwitch = GS._forestElfPendingSwitch
                            GS._forestElfPendingSwitch = nil
                            local DM = require("DialogueManager")
                            if DM.active then DM.finish() end
                            -- 直接清理覆盖层，由 pendingSwitch 的 startSceneTransition 处理过渡
                            BoardOverlay.hide()
                            pendingSwitch()
                            return
                        end
                        GS.exitShopMode()
                        GS.exitWarehouseMode()
                        GS.exitExchangeMode()
                        GS.adLoading = false
                        GS.adCancelRect = nil
                        BoardOverlay.exitSubScene()
                        GS.triggerAutoSave()
                    elseif r.action == "talk_freya" then
                        DialogueManager = require("DialogueManager")
                        DialogueManager.startDynamic({
                            { speaker = "芙蕾雅", text = "嗯？还有事吗？" },
                        })
                    elseif r.action == "guild_office" then
                        -- 进入会长办公室子场景（清理公会前台视频，让办公室视频正确初始化）
                        BoardOverlay.cleanupVideoState()
                        BoardOverlay.enterSubScene("guild_master_office", true)
                        -- skipDialogue=true 跳过了营业时间检查，但也跳过了自动对话
                        -- 手动触发好感度对话
                        local DM_office = require("DialogueManager")
                        local dlgId = DM_office.checkBuilding("guild_master_office")
                        if dlgId then DM_office.start(dlgId) end
                    elseif r.action == "back_to_guild" then
                        -- 从会长办公室回到公会前台（清理办公室视频，让前台视频正确初始化）
                        BoardOverlay.cleanupVideoState()
                        BoardOverlay.enterSubScene("guild", true)
                    elseif r.action == "ad_machine" then
                        -- 进入广告机子场景（无需营业时间检查）
                        BoardOverlay.enterSubScene("guild_ad_machine", true)
                    elseif r.action == "watch_ad" then
                        -- 每日广告次数检查（自然日重置）
                        local today = os.date("%Y-%m-%d")
                        if GS.adDailyDate ~= today then
                            GS.adDailyDate = today
                            GS.adDailyCount = 0
                        end
                        if GS.adDailyCount >= GS.AD_DAILY_LIMIT then
                            DialogueManager = require("DialogueManager")
                            DialogueManager.startDynamic({
                                { speaker = "旁白", text = "（今天的力量传输次数已达上限，请明天再来吧。）" },
                            })
                        else
                            -- 免广告用户：直接发放感恩礼券
                            if GS.adFree then
                                GS.adDailyCount = GS.adDailyCount + 1
                                local ok, msg = GS.addToInventory("gratitude_ticket", 1)
                                DialogueManager = require("DialogueManager")
                                if ok then
                                    local text = "（那个世界的穷苦冒险者突然感到充满了力量！他感应到了你的帮助，传输了一张\u{201c}感恩礼券\u{201d}给你！）"
                                    if msg and msg:find("遗失物品") then
                                        text = "（那个世界的穷苦冒险者传输了一张\u{201c}感恩礼券\u{201d}给你！但你的背包已满，礼券已放入遗失物品中。）"
                                    end
                                    DialogueManager.startDynamic({
                                        { speaker = "旁白", text = text },
                                    })
                                else
                                    DialogueManager.startDynamic({
                                        { speaker = "旁白", text = "（" .. msg .. "）" },
                                    })
                                end
                                print("[AdFree] 免广告用户，直接发放感恩礼券")
                                return
                            end
                            -- PC端不支持广告
                            if PlatformUtils.IsDesktopPlatform() then
                                local DM = require("DialogueManager")
                                DM.startDynamic({ { speaker = "旁白", text = "（通过这个叫做台式电脑的设备无法传输力量……）" } })
                                return
                            end
                            -- 看广告获得感恩礼券
                            GS.adLoading = true
                            GS.adSessionId = GS.adSessionId + 1
                            local thisSession = GS.adSessionId
                            MonitorPanel.reportAdClick()
                            sdk:ShowRewardVideoAd(function(result)
                                if result.success then
                                    -- 广告确实看完，无论游戏状态如何都发放奖励
                                    GS.adLoading = false
                                    GS.adCancelRect = nil
                                    MonitorPanel.reportAdSuccess()
                                    GS.adDailyCount = GS.adDailyCount + 1
                                    local ok, msg = GS.addToInventory("gratitude_ticket", 1)
                                    if ok then
                                        DialogueManager = require("DialogueManager")
                                        local text = "（那个世界的穷苦冒险者突然感到充满了力量！他感应到了你的帮助，传输了一张\u{201c}感恩礼券\u{201d}给你！）"
                                        if msg and msg:find("遗失物品") then
                                            text = "（那个世界的穷苦冒险者传输了一张\u{201c}感恩礼券\u{201d}给你！但你的背包已满，礼券已放入遗失物品中。）"
                                        end
                                        DialogueManager.startDynamic({
                                            { speaker = "旁白", text = text },
                                        })
                                    else
                                        DialogueManager = require("DialogueManager")
                                        DialogueManager.startDynamic({
                                            { speaker = "旁白", text = "（" .. msg .. "）" },
                                        })
                                    end
                                else
                                    -- 广告未完成，检查状态避免过期回调弹出多余提示
                                    if thisSession ~= GS.adSessionId then return end
                                    if not GS.adLoading then return end
                                    GS.adLoading = false
                                    GS.adCancelRect = nil
                                    MonitorPanel.reportAdFail()
                                    DialogueManager = require("DialogueManager")
                                    DialogueManager.startDynamic({
                                        { speaker = "旁白", text = "（由于你的主动终止，力量传输失败了……你隐约感觉到那个世界的冒险者似乎正在饿着肚子……）" },
                                    })
                                end
                            end)
                        end
                    elseif r.action == "respec" then
                        -- 打开洗点弹窗
                        GS.respecPopupVisible = true
                        GS.respecPopupChoice = nil
                    elseif r.action == "exchange" then
                        -- 打开兑换面板
                        GS.enterExchangeMode()
                    elseif r.action == "abyss_exchange" then
                        -- 打开深渊兑换面板
                        GS.enterAbyssExchangeMode()
                    elseif r.action == "return_front" then
                        -- 返回前台（回到公会，保持视频状态不变）
                        GS.exitExchangeMode()
                        BoardOverlay.returnToGuildFront()
                    elseif r.action == "exit_to_town" then
                        -- 从打烊广告机退出：直接回清水镇
                        GS.exitExchangeMode()
                        GS.adMachineFromClosed = false
                        BoardOverlay.exitSubScene()
                    elseif r.action == "trade" then
                        local buildingKey = BoardOverlay.subScene and BoardOverlay.subScene.id
                        if buildingKey then
                            GS.enterShopMode(buildingKey)
                        end
                    elseif r.action == "repair" then
                        GS.repairMode = true
                        GS.enhanceMode = false  -- 互斥
                        GS.refineMode = false   -- 互斥
                        GS.forgeMode = false    -- 互斥
                        GS.socketMode = false   -- 互斥
                        GS.alchemyMode = false  -- 互斥
                        GS.craftMode = false    -- 互斥
                        GS.cookingMode = false  -- 互斥
                        GS.enchantMode = false  -- 互斥
                        GS.repairResult = nil
                    elseif r.action == "forge" then
                        GS.forgeMode = true
                        GS.enhanceMode = false  -- 互斥
                        GS.refineMode = false   -- 互斥
                        GS.repairMode = false   -- 互斥
                        GS.socketMode = false   -- 互斥
                        GS.alchemyMode = false  -- 互斥
                        GS.craftMode = false    -- 互斥
                        GS.cookingMode = false  -- 互斥
                        GS.enchantMode = false  -- 互斥
                        GS.forgeResult = nil
                        GS.forgeScrollY = 0
                        GS.forgeBtnRects = {}
                    elseif r.action == "alchemy" then
                        GS.alchemyMode = true
                        GS.enhanceMode = false  -- 互斥
                        GS.refineMode = false   -- 互斥
                        GS.repairMode = false   -- 互斥
                        GS.forgeMode = false    -- 互斥
                        GS.socketMode = false   -- 互斥
                        GS.craftMode = false    -- 互斥
                        GS.cookingMode = false  -- 互斥
                        GS.enchantMode = false  -- 互斥
                        GS.alchemyResult = nil
                        GS.alchemyScrollY = 0
                        GS.alchemyBtnRects = {}
                    elseif r.action == "cooking" then
                        GS.cookingMode = true
                        GS.enhanceMode = false  -- 互斥
                        GS.refineMode = false   -- 互斥
                        GS.repairMode = false   -- 互斥
                        GS.forgeMode = false    -- 互斥
                        GS.socketMode = false   -- 互斥
                        GS.alchemyMode = false  -- 互斥
                        GS.craftMode = false    -- 互斥
                        GS.enchantMode = false  -- 互斥
                        GS.cookingResult = nil
                        GS.cookingScrollY = 0
                        GS.cookingBtnRects = {}
                    elseif r.action == "socket" then
                        GS.socketMode = true
                        GS.enhanceMode = false  -- 互斥
                        GS.refineMode = false   -- 互斥
                        GS.repairMode = false   -- 互斥
                        GS.forgeMode = false    -- 互斥
                        GS.alchemyMode = false  -- 互斥
                        GS.craftMode = false    -- 互斥
                        GS.cookingMode = false  -- 互斥
                        GS.enchantMode = false  -- 互斥
                        GS.socketEquipItem = nil
                        GS.socketEquipSource = nil
                        GS.socketEquipSourceId = nil
                        GS.socketSelectedGemSlot = nil
                        GS.socketSelectedGemBag = nil
                        GS.socketResult = nil
                        GS.socketScrollY = 0
                        GS.socketGemBtnRects = {}
                    elseif r.action == "craft" then
                        GS.craftMode = true
                        GS.enhanceMode = false  -- 互斥
                        GS.refineMode = false   -- 互斥
                        GS.repairMode = false   -- 互斥
                        GS.forgeMode = false    -- 互斥
                        GS.socketMode = false   -- 互斥
                        GS.alchemyMode = false  -- 互斥
                        GS.cookingMode = false  -- 互斥
                        GS.enchantMode = false  -- 互斥
                        GS.craftTab = "enhance"
                        GS.craftSlotItem = nil
                        GS.craftSlotSource = nil
                        GS.craftSlotSourceId = nil
                        GS.craftEnhanceResult = nil
                        GS.craftRefineResult = nil
                        GS.craftRepairResult = nil
                        GS.craftExtractResult = nil
                        GS.extractSourceItem = nil
                        GS.extractTargetItem = nil
                        GS.extractSourceSource = nil
                        GS.extractSourceSourceId = nil
                        GS.extractTargetSource = nil
                        GS.extractTargetSourceId = nil
                        GS.craftTabRects = {}
                        GS.craftRefineSlotBtnRects = {}
                        -- 会话锁：乐观开启界面，异步检查多端登录
                        SessionLock.checkOnCraftOpen()
                    elseif r.action == "talk" then
                        -- 对话进行中时忽略交谈按钮（拦截器已处理自愈，此处仅防御性检查）
                        local DM_guard = require("DialogueManager")
                        print("[TalkBtn] pressed. DM.active=" .. tostring(DM_guard.active)
                            .. " waitChoice=" .. tostring(DM_guard.waitingForChoice)
                            .. " boxRect=" .. tostring(BoardOverlay.dialogueBoxRect ~= nil)
                            .. " fadeA=" .. tostring(BoardOverlay._fadeAlpha)
                            .. " fadeT=" .. tostring(BoardOverlay._fadeTarget))
                        if DM_guard.active then break end
                        -- 森林精灵场景：特殊交谈逻辑
                        local buildingKey = BoardOverlay.subScene and BoardOverlay.subScene.id or ""
                        if buildingKey == "forest_elf" then
                            local DM = require("DialogueManager")
                            local elfName = GS.resolveNPCSpeaker("艾莉雅")

                            if GS._forestElfFromMap then
                                -- 从地图直接进入：使用通用交谈问答系统
                                GS.tryDailyTalkAffinity("forest_elf")
                                triggerNpcTalk("forest_elf")
                            else
                                -- 随机遭遇：原有逻辑
                                DM.startDynamic({
                                    {
                                        speaker = elfName, text = "……",
                                        choices = { "你好", "离开" },
                                        onChoice = function(idx)
                                            if idx == 1 then
                                                if GS.elfvahLanguageLearned and not GS.elfvahElfTalked then
                                                    -- 会精灵语且未交谈过：显示特殊对话序列
                                                    DM.startDynamic({
                                                        { speaker = GS.resolveNPCSpeaker("艾莉雅"), text = "你会我们的语言。" },
                                                        { speaker = GS.resolveNPCSpeaker("艾莉雅"), text = "我知道你，你是{玩家}，此世间的变量。" },
                                                        { speaker = GS.resolveNPCSpeaker("艾莉雅"), text = "我之名为艾莉雅，我很好奇，她为什么选中了你，你又能做到什么呢？" },
                                                    }, function()
                                                        -- 第三句话结束后：标记玩家知道艾莉雅的名字
                                                        GS.learnNPCName("forest_elf")
                                                        GS.elfvahElfTalked = true
                                                        -- 显示最后一句（此时名字已解锁，显示"艾莉雅"）
                                                        DM.startDynamic({
                                                            { speaker = GS.resolveNPCSpeaker("艾莉雅"), text = "随时来找我，{玩家}。" },
                                                        }, function()
                                                            -- 对话结束：播放离开视频
                                                            local pendingSwitch = GS._forestElfPendingSwitch
                                                            GS._forestElfPendingSwitch = nil
                                                            BoardOverlay.startForestElfLeaveVideo(function()
                                                                if pendingSwitch then pendingSwitch() end
                                                            end)
                                                            DM.startDynamic({
                                                                { speaker = "旁白", text = "（她对你笑了一下，转过身去，一阵光芒闪过，消失在了雾气中。）" },
                                                            }, function()
                                                                BoardOverlay.notifyForestElfDialogueDone()
                                                            end)
                                                        end)
                                                    end)
                                                else
                                                    -- 不会精灵语 或 已经交谈过：原有逻辑
                                                    local pendingSwitch = GS._forestElfPendingSwitch
                                                    GS._forestElfPendingSwitch = nil
                                                    BoardOverlay.startForestElfLeaveVideo(function()
                                                        if pendingSwitch then pendingSwitch() end
                                                    end)
                                                    DM.startDynamic({
                                                        { speaker = "旁白", text = "（她对你笑了一下，转过身去，一阵光芒闪过，消失在了雾气中。）" },
                                                    }, function()
                                                        BoardOverlay.notifyForestElfDialogueDone()
                                                    end)
                                                end
                                            else
                                                -- "离开"：直接切换到目标关卡
                                                DM.finish()
                                                local pendingSwitch = GS._forestElfPendingSwitch
                                                GS._forestElfPendingSwitch = nil
                                                BoardOverlay.hide()
                                                if pendingSwitch then pendingSwitch() end
                                            end
                                        end,
                                    },
                                })
                            end
                            return
                        end
                        -- 交谈问答系统
                        local TalkQA = require("data.TalkQA")
                        -- 酒馆舞池视角 → 安吉莉娅
                        if buildingKey == "tavern" and BoardOverlay.tavernDanceView then
                            buildingKey = "tavern_dancefloor"
                        end
                        local qaData = TalkQA[buildingKey]
                        if qaData then
                            -- 记录 NPC 交谈（支线任务追踪：按交谈键才算）
                            local buildingToNpc = {
                                blacksmith = "blacksmith",
                                armor_shop = "armor_shop",
                                guild = "guild",
                                jewelry_shop = "jewelry_shop",
                                potion_shop = "potion_shop",
                                tavern = "tavern",
                                tavern_dancefloor = "tavern_dancer",
                            }
                            local npcKey = buildingToNpc[buildingKey]
                            if npcKey and not GS.npcTalkedRecord[npcKey] then
                                GS.npcTalkedRecord[npcKey] = true
                                print("[TalkQA] NPC交谈记录: " .. npcKey)
                            end
                            -- 每日交谈好感度+2
                            GS.tryDailyTalkAffinity(qaData.npcKey)
                            -- 触发交谈问答
                            triggerNpcTalk(buildingKey)
                        end
                    elseif r.action == "dancefloor" then
                        -- 对话进行中时忽略舞池切换（防止覆盖回调链导致卡死）
                        local DM_guard2 = require("DialogueManager")
                        if DM_guard2.active then break end
                        BoardOverlay.tavernDanceView = not BoardOverlay.tavernDanceView
                        -- 切换到舞池视角
                        if BoardOverlay.tavernDanceView then
                            -- ── 酒馆肉搏任务检查（优先于舞蹈观赏） ──
                            local QM_brawl = require("QuestManager")
                            local brawlQuest = QM_brawl.getActiveBrawlQuest()
                            if brawlQuest then
                                -- 有激活的肉搏任务 → 触发肉搏战斗
                                local MonsterDB = require("data.MonsterDB")
                                local thugCount = brawlQuest.thugCount
                                local questId = brawlQuest.questId

                                -- 肉搏一(Lv.10)：3个混混；肉搏二(Lv.25)：4个混混
                                local brawlSpawnList
                                if questId == "main_angelica_brawl_2" then
                                    brawlSpawnList = {
                                        { defId = "tavern_thug_25", pos = {6, 3} },
                                        { defId = "drunk_man_25",   pos = {2, 10} },
                                        { defId = "scarface_25",    pos = {11, 7} },
                                        { defId = "drunk_man_25",   pos = {10, 10} },
                                    }
                                else
                                    brawlSpawnList = {
                                        { defId = "tavern_thug", pos = {6, 3} },
                                        { defId = "drunk_man",   pos = {2, 10} },
                                        { defId = "scarface",    pos = {11, 7} },
                                    }
                                end

                                -- ── 黑屏过渡：先淡入黑屏 → 黑屏上播放对话 → 对话结束后淡出进入战斗 ──
                                DialogueManager = require("DialogueManager")
                                local brawlAcceptDialogue
                                if questId == "main_angelica_brawl_2" then
                                    brawlAcceptDialogue = {
                                        { speaker = "旁白", text = "（你一靠近舞池，几个男人就围了过来。你一眼认出是上次骚扰安吉莉娅的那几位。）" },
                                        { speaker = "喝醉的男人", text = "{玩家}！我反思过了，安吉莉娅小姐一定是因为我太弱了才没有接受我的示爱，只有打败你才能赢得安吉莉娅小姐的芳心！" },
                                        { speaker = "喝醉的男人", text = "我苦练又苦练了这么久，就是为了今天！兄弟们，上！" },
                                        { speaker = "旁白", text = "（你不明白这样群殴，就算赢了你又能证明什么呢？但是麻烦已经降临了。）" },
                                    }
                                else
                                    brawlAcceptDialogue = {
                                        { speaker = "旁白", text = "（你刚转头望向舞池，突然一阵喧闹吵得你耳膜不适。几个喝醉的男人围着美丽的紫发女人大声嚷嚷。）" },
                                        { speaker = "喝醉的男人", text = "安吉莉娅小姐，我喜欢你……求求你了，能不能和我在一起。" },
                                        { speaker = "旁白", text = "（尽管喝醉的男人们都很克制，没有动手动脚，但跳舞的姑娘的窘迫还是显而易见。）" },
                                        { speaker = "旁白", text = "（安吉莉娅四处张望寻找救命稻草，突然看到了你……）" },
                                        { speaker = "安吉莉娅", text = "{玩家}！帮帮我！" },
                                        { speaker = "旁白", text = "（就算你不想惹麻烦，几个喝醉的男人此时此刻也纷纷转过来看着你，把你当成了敌人。酒馆肉搏一触即发。）" },
                                    }
                                end

                                -- 启动黑屏过渡：淡入 → 黑屏上播放对话 → 对话结束后淡出进入战斗
                                GS.brawlCinematic = {
                                    phase = "fade_in",
                                    timer = 0,
                                    alpha = 0,
                                    FADE_IN  = 0.4,
                                    FADE_OUT = 0.5,
                                    -- 淡入完成后的回调：播放对话
                                    onFadeInDone = function()
                                        -- 隐藏 BoardOverlay（在黑屏下进行，玩家看不到）
                                        BoardOverlay.tavernDanceView = false
                                        BoardOverlay.hide()
                                        -- 在黑屏上播放对话
                                        DialogueManager.startDynamic(brawlAcceptDialogue, function()
                                            -- 对话结束 → 准备战斗场景（仍在黑屏下）
                                            GS.tavernBrawlState = { questId = questId, thugCount = thugCount, killCount = 0, done = false }

                                            GS.currentBattleBg = "image/bg_tavern_brawl.jpg"
                                            GS.currentAreaName = "酒馆"
                                            GS.currentStageName = "酒馆肉搏"
                                            GS.gameState = GS.STATE_PLAYER
                                            GS.turnPhase = GS.PHASE_MOVE

                                            -- 清空场上单位
                                            GS.saveGatherStageState()
                                            GS.monsters = {}
                                            GS.companions = {}
                                            GS.gatherables = {}
                                            GS.selectedUnit = nil
                                            GS.movableCells = {}
                                            GS.attackableCells = {}
                                            GS.flushPendingMpRestores()
                                            GS.damageTexts = {}

                                            -- 重置玩家位置到棋盘中央
                                            GS.player.x = math.floor(GS.BOARD_SIZE / 2)
                                            GS.player.y = math.floor(GS.BOARD_SIZE / 2)

                                            -- 生成混混
                                            for ti = 1, thugCount do
                                                local info = brawlSpawnList[ti]
                                                if not info then break end
                                                local tDef = MonsterDB[info.defId] or MonsterDB.tavern_thug
                                                local sp = info.pos
                                                local thug = {
                                                    x = sp[1], y = sp[2],
                                                    defId = info.defId,
                                                    name = tDef.name,
                                                    level = tDef.level or 10,
                                                    hp = tDef.hp, maxHp = tDef.hp,
                                                    atk = tDef.atk, mAtk = tDef.mAtk or tDef.atk,
                                                    def = tDef.def, mdef = tDef.mdef or tDef.def,
                                                    critVal = tDef.critVal or 0,
                                                    critDmg = tDef.critDmg or 50,
                                                    hit = tDef.hit or 0,
                                                    dodge = tDef.dodge or 0,
                                                    atkSpeed = tDef.atkSpeed or 1,
                                                    moveRange = tDef.moveRange, atkRange = tDef.atkRange,
                                                    color = {tDef.color[1], tDef.color[2], tDef.color[3]},
                                                    expReward = 0,
                                                    rarity = tDef.rarity,
                                                    image = tDef.image,
                                                    drops = {},
                                                    noAffix = true,
                                                    isMonster = true, acted = false,
                                                    facing = GS.facingToCenter(sp[1], sp[2]),
                                                    isBrawlThug = true,
                                                }
                                                table.insert(GS.monsters, thug)
                                            end
                                            -- 法师/牧师：初始化吟唱段数
                                            if GS.currentClass == "mage" or GS.currentClass == "priest" then
                                                GS.chantStages = 0
                                                local gained = GS.rollChantStages()
                                                GS.chantStages = gained
                                                GS.chantStagesMax = gained
                                            end
                                            print("[酒馆肉搏] 开始！混混数量: " .. thugCount .. ", questId: " .. questId)

                                            -- 开始淡出（揭示战斗场景）
                                            GS.brawlCinematic.phase = "fade_out"
                                            GS.brawlCinematic.timer = 0
                                        end)
                                    end,
                                }
                                break  -- 处理完毕，退出循环
                            end

                            -- 判断今天是否已观赏过舞蹈（游戏内每天=1440分钟）
                            local currentDay = math.floor((GS.weatherTime - 1) / 1440)
                            if GS.lastDanceDayWatched ~= currentDay then
                                -- 每日首次：黑屏过渡 → 播放舞女跳舞视频 → 旁白对话
                                GS.dancerShowPhase = "performing"
                                BoardOverlay.startDancefloorVideo()
                                DialogueManager = require("DialogueManager")
                                DialogueManager.startDynamic({
                                    { speaker = "旁白", text = "（美丽的紫发女子在舞池中翩翩起舞……白色裙摆旋转如月，紫鸢花香味搅动着空气。）" },
                                    { speaker = "旁白", text = "（她的身姿轻盈，人们望着她，就像是望向一只紫色蝴蝶，轻轻、轻轻地，落在四月初的一片叶尖。）" },
                                    { speaker = "旁白", text = "（你从舞蹈中感到了鼓舞精神的力量，你的能力暂时得到增强。）" },
                                }, function()
                                    -- 旁白对话结束：赋予BUFF、记录今日已观赏
                                    GS.lastDanceDayWatched = currentDay
                                    -- 注意：dancerShowPhase 保持 "performing" 直到 idle 视频就绪揭示后
                                    -- 防止快速点完文本导致交谈按钮提前出现
                                    -- 观看舞蹈：安吉莉娅好感度+3
                                    GS.changeAffinity("tavern_dancer", 3)
                                    print("[好感度] tavern_dancer 观看舞蹈 +3")
                                    -- 赋予"勿忘我"BUFF（持续24小时 = 1440分钟）
                                    local expireTime = GS.weatherTime + 1440
                                    if expireTime > GS.YEAR_MINUTES then
                                        expireTime = expireTime - GS.YEAR_MINUTES
                                    end
                                    GS.forgetMeNotBuff = { active = true, expireTime = expireTime }
                                    GS.recalcStats(GS.player)
                                    print("[酒馆] 获得\"勿忘我\"BUFF，持续24小时")
                                    -- 标记对话结束，等 idle 视频就绪后揭示并开始舞女正常交谈
                                    BoardOverlay.onDancerDialogueDone(function()
                                        -- idle 视频就绪、揭示完成后才标记为 done，此时按钮才显示
                                        GS.dancerShowPhase = "done"
                                        local dlgId = DialogueManager.checkBuilding("tavern_dancefloor")
                                        if dlgId then
                                            DialogueManager.start(dlgId)
                                        end
                                    end)
                                end)
                            else
                                -- 今日已观赏过：黑屏过渡 → 播放舞女 Idle 视频 + 正常对话
                                -- 保持 performing 隐藏按钮，等视频淡入后再切为 done
                                GS.dancerShowPhase = "performing"
                                BoardOverlay.startDancerIdleVideo()
                                -- 动画关闭时视频跳过，直接恢复按钮并立即触发对话
                                if not GS.animationEnabled then
                                    GS.dancerShowPhase = "done"
                                    local dlgId = DialogueManager.checkBuilding("tavern_dancefloor")
                                    if dlgId then
                                        DialogueManager.start(dlgId)
                                    end
                                else
                                    -- 动画开启：等黑屏揭示完成后再触发对话
                                    BoardOverlay.onDancerDialogueDone(function()
                                        local dlgId = DialogueManager.checkBuilding("tavern_dancefloor")
                                        if dlgId then
                                            DialogueManager.start(dlgId)
                                        end
                                    end)
                                end
                            end
                        else
                            -- 回到前台：保持 performing 隐藏按钮，等视频淡入后再清除
                            GS.dancerShowPhase = "performing"
                            BoardOverlay.exitDancefloorVideo()
                            -- 动画关闭时视频跳过，直接恢复按钮
                            if not GS.animationEnabled then
                                GS.dancerShowPhase = "done"
                            end
                        end
                    elseif r.action == "lost_items" then
                        GS.enterLostItemsMode()
                    end
                    break
                end
            end
        else
            -- 城镇建筑按钮点击
            for _, r in ipairs(BoardOverlay.buildingBtnRects) do
                if hitTest(mx, my, r) then
                    if r.label == "家" then
                        -- 首次点击"家"激活筑巢任务
                        local QM = require("QuestManager")
                        if QM.getQuestStatus("side_nesting") == QM.STATUS_LOCKED then
                            QM.activateQuest("side_nesting")
                        end
                        if not GS.housePurchased then
                            -- 未购买房屋，弹出购买弹窗
                            GS.houseBuyDialogVisible = true
                            break
                        end
                        -- 切换到家场景（使用当前拥有的家园类型）
                        GS.startSceneTransition(function()
                            BoardOverlay.hide()
                            GS.currentStage = nil
                            GS.isAbyssWorld = false
                            GS.homeMode = true
                            GS.sharedStorageMode = false
                            GS.sharedStorageLogOpen = false
                            GS.trainingMode = false
                            GS.gameState = GS.STATE_PLAYER
                            GS.turnPhase = GS.PHASE_MOVE
                            GS.currentBattleBg = "image/bg_home.png"
                            GS.currentAreaName = "家"
                            GS.currentStageName = "家"
                            GS.saveGatherStageState()
                            GS.monsters = {}
                            GS.companions = {}
                            GS.gatherables = {}
                            GS.gatheringState = nil
                            GS.gatherResultAnim = nil
                            GS.selectedUnit = nil
                            GS.movableCells = {}
                            GS.attackableCells = {}
                            GS.flushPendingMpRestores()
                            GS.damageTexts = {}
                            GS.holyTrees = {}
                            GS.iceWalls = {}
                            GS.burningGrounds = {}
                            GS.pendingBurningGrounds = {}
                            GS.blizzardZones = {}
                            GS.thunderClouds = {}
                            Combat.clearPendingState()
                            -- 玩家放在门内侧
                            local hp = GS.getHomeRoomParams(GS.homeType)
                            GS.player.x = hp.doorX1
                            GS.player.y = hp.doorY - 1
                            GS.spawnHound()
                            print("=== 从清水镇回家 ===")
                        end)
                    else
                        local key = BoardOverlay.buildingLabelMap[r.label]
                        if key then
                            BoardOverlay.enterSubScene(key)
                        else
                            print("=== 点击建筑: " .. r.label .. "（暂未开放） ===")
                        end
                    end
                    break
                end
            end
        end
        return
    end

    if GS.autoMode then return end

    if GS.gameState ~= GS.STATE_PLAYER and GS.gameState ~= GS.STATE_SELECT then return end

    -- 采集/家具交互进行中，屏蔽棋盘点击（UI 操作已在上方处理）
    if GS.gatheringState then return end
    if GS.furnitureInteract then return end
    -- 充能动画进行中，屏蔽玩家操作
    if GS._chantGainBlocking then return end

    -- 家园升级按钮（像素级检测，在格子转换之前）
    if GS.homeMode and GS.homeUpgradeBtnRect and button == MOUSEB_LEFT then
        if hitTest(mx, my, GS.homeUpgradeBtnRect) then
            GS.homeUpgradeDialogVisible = true
            return
        end
    end

    -- 棋盘点击
    local cx, cy = GS.screenToCell(mx, my)
    if not cx then return end

    -- 点击棋盘上的怪物：锁定为顶栏显示目标（不影响其他操作流程）
    if not GS.homeMode then
        local clickedUnit = GS.getUnitAt(cx, cy)
        if clickedUnit and clickedUnit.isMonster and clickedUnit.hp > 0 then
            GS.topBarLockedTarget = clickedUnit
        end
    end

    if GS.gameState == GS.STATE_PLAYER then
        -- 副本自由移动模式：阶段完成后（arenaWaitForExit），无距离限制
        if GS.isDungeon and GS.arenaWaitForExit and GS.player and GS.player.hp > 0
            and not GS.arenaChestInteract and not GS.arenaTransition then
            -- 点击宝箱：走到宝箱旁边并读条开启
            local clickedChestIdx = nil
            if GS.arenaChests then
                for idx, chest in ipairs(GS.arenaChests) do
                    if not chest.opened and chest.x == cx and chest.y == cy then
                        clickedChestIdx = idx
                        break
                    end
                end
            end

            if clickedChestIdx then
                -- 寻找宝箱旁边离玩家最近的可达格子
                local chest = GS.arenaChests[clickedChestIdx]
                local ox, oy = GS.player.x, GS.player.y
                local dirs = {{0,1},{0,-1},{-1,0},{1,0}}
                local targetX, targetY
                local bestDist = 999
                for _, d in ipairs(dirs) do
                    local nx, ny = chest.x + d[1], chest.y + d[2]
                    if GS.isInBoard(nx, ny) then
                        local dist = math.abs(nx - ox) + math.abs(ny - oy)
                        if dist < bestDist then
                            bestDist = dist
                            targetX, targetY = nx, ny
                        end
                    end
                end
                if targetX then
                    if ox == targetX and oy == targetY then
                        -- 已在宝箱旁，直接开启
                        GS.updateFacing(GS.player, ox, oy, chest.x, chest.y)
                        GS.arenaChestInteract = {
                            chestIdx = clickedChestIdx,
                            progress = 0, duration = 1.5, _displayProgress = 0,
                        }
                        GS.arenaChestPending = nil
                    elseif GS.player.moveAnim then
                        -- 移动中：记录待定目标
                        GS.arenaPendingTarget = {targetX, targetY}
                        GS.arenaChestPending = clickedChestIdx
                        GS.arenaExitPending = false
                    else
                        local path = GS.arenaPathFind(ox, oy, targetX, targetY)
                        if path and #path >= 2 then
                            GS.player.x = targetX
                            GS.player.y = targetY
                            Combat.startMoveAnim(GS.player, ox, oy, path)
                            GS.arenaChestPending = clickedChestIdx
                            GS.arenaExitPending = false
                        end
                    end
                end
                return
            end

            -- 检查目标是否是出口格子的辅助函数
            local function isExitTile(gx, gy)
                if GS.arenaExitTiles then
                    for _, tile in ipairs(GS.arenaExitTiles) do
                        if gx == tile.x and gy == tile.y then return true end
                    end
                end
                return false
            end

            -- 点击空格子：直接移动
            local ox, oy = GS.player.x, GS.player.y
            if cx ~= ox or cy ~= oy then
                local exitPending = isExitTile(cx, cy)
                if GS.player.moveAnim then
                    GS.arenaPendingTarget = {cx, cy}
                    GS.arenaChestPending = nil
                    GS.arenaExitPending = exitPending
                else
                    local path = GS.arenaPathFind(ox, oy, cx, cy)
                    if path and #path >= 2 then
                        GS.player.x = cx
                        GS.player.y = cy
                        Combat.startMoveAnim(GS.player, ox, oy, path)
                        GS.arenaChestPending = nil
                        GS.arenaExitPending = exitPending
                    end
                end
            end
            return
        end

        -- 家模式：点击任意空格子直接移动，无距离限制
        if GS.homeMode and GS.player and GS.player.hp > 0 and not GS.warehouseMode then
            local hp = GS.getHomeRoomParams(GS.homeType)

            -- 点击伴侣NPC：寻路到旁边并发起对话
            if GS.homeNpc then
                print("[HomePartner] click=(" .. cx .. "," .. cy .. ") npc=(" .. GS.homeNpc.x .. "," .. GS.homeNpc.y .. ") state=" .. tostring(GS.homeNpc.state) .. " npcKey=" .. tostring(GS.homeNpc.npcKey) .. " moveAnim=" .. tostring(GS.homeNpc.moveAnim ~= nil))
            else
                print("[HomePartner] homeNpc is nil")
            end
            if GS.homeNpc and GS.homeNpc.npcKey and not GS.homeNpc.moveAnim
               and GS.homeNpc.state ~= "leaving"
               and GS.homeNpc.state ~= "fading_in" and GS.homeNpc.state ~= "fading_out"
               and GS.homeNpc.state ~= "going_to_sleep" and GS.homeNpc.state ~= "going_to_idle"
               and cx == GS.homeNpc.x and cy == GS.homeNpc.y then
                local hn = GS.homeNpc
                local ox, oy = GS.player.x, GS.player.y
                -- 寻找伴侣旁边的可达格子
                local targetX, targetY
                if hn.state == "sleeping" then
                    -- 睡觉时移动到床上另一侧（双人床 x=9..10）
                    local bx = (hn.x == 10) and 9 or 10
                    if GS.isCellEmpty(bx, hn.y) or (bx == ox and hn.y == oy) then
                        targetX, targetY = bx, hn.y
                    end
                end
                if not targetX then
                    local tryDirs = {{0,1},{0,-1},{-1,0},{1,0}}
                    -- 按到玩家的距离排序，优先选最近的格子
                    table.sort(tryDirs, function(a, b)
                        local ax, ay = hn.x + a[1], hn.y + a[2]
                        local bx, by = hn.x + b[1], hn.y + b[2]
                        local da = math.abs(ax - ox) + math.abs(ay - oy)
                        local db = math.abs(bx - ox) + math.abs(by - oy)
                        return da < db
                    end)
                    for _, d in ipairs(tryDirs) do
                        local tx, ty = hn.x + d[1], hn.y + d[2]
                        if (GS.isCellEmpty(tx, ty) or (tx == ox and ty == oy)) then
                            targetX, targetY = tx, ty
                            break
                        end
                    end
                end
                if targetX then
                    if ox == targetX and oy == targetY then
                        -- 已在旁边 → 直接发起对话
                        GS.updateFacing(GS.player, ox, oy, hn.x, hn.y)
                        M._startHomePartnerTalk(hn.npcKey)
                    elseif not GS.player.moveAnim then
                        -- 寻路到伴侣旁边
                        local path = GS.homePathFind(ox, oy, targetX, targetY)
                        if path and #path >= 2 then
                            GS.player.x = targetX
                            GS.player.y = targetY
                            Combat.startMoveAnim(GS.player, ox, oy, path)
                            -- 标记到达后发起伴侣对话
                            GS._homePartnerTalkPending = true
                        end
                    end
                end
                return
            end

            -- 点击家中猎犬：触发"汪汪"浮动文本（每秒限1次）
            if GS.homeHound and cx == GS.homeHound.x and cy == GS.homeHound.y then
                if (GS.homeHound._barkCooldown or 0) <= 0 then
                    GS.homeHound._barkCooldown = 1.0
                    GS.homeHound.floatingText = {
                        text = "汪……汪汪！",
                        duration = 2.0,
                        fadeStart = 1.2,
                        timer = 0,
                    }
                end
                return
            end

            -- 点击可交互家具（储物箱等）
            local clickedFurn = GS.getInteractableFurnitureAt(GS.homeType, cx, cy)
            if clickedFurn then
                -- 寻找家具旁边的可达格子作为目标（优先下方，然后上/左/右）
                local furnCX = clickedFurn.x + (clickedFurn.w - 1) * 0.5  -- 家具中心列
                local furnCY = clickedFurn.y + (clickedFurn.h - 1) * 0.5  -- 家具中心行
                local targetX, targetY
                -- approachDir: "right"=右, "left"=左, "down"=下, "up"=上（可选，覆盖默认优先级）
                local dirMap = {down={0,1}, up={0,-1}, left={-1,0}, right={1,0}}
                local dirs
                if clickedFurn.approachDir and dirMap[clickedFurn.approachDir] then
                    dirs = {dirMap[clickedFurn.approachDir]}
                else
                    dirs = {{0,1},{0,-1},{-1,0},{1,0}}
                end
                -- 优先搜索点击格子(cx,cy)的邻居，再搜索家具其他格子的邻居
                for _, d in ipairs(dirs) do
                    local tx, ty = cx + d[1], cy + d[2]
                    if GS.isCellEmpty(tx, ty) or (GS.player and tx == GS.player.x and ty == GS.player.y) then
                        targetX, targetY = tx, ty
                        break
                    end
                end
                if not targetX then
                    for _, d in ipairs(dirs) do
                        for fy = clickedFurn.y, clickedFurn.y + clickedFurn.h - 1 do
                            for fx = clickedFurn.x, clickedFurn.x + clickedFurn.w - 1 do
                                if fx ~= cx or fy ~= cy then
                                    local tx, ty = fx + d[1], fy + d[2]
                                    if GS.isCellEmpty(tx, ty) or (GS.player and tx == GS.player.x and ty == GS.player.y) then
                                        targetX, targetY = tx, ty
                                        break
                                    end
                                end
                            end
                            if targetX then break end
                        end
                        if targetX then break end
                    end
                end
                if not targetX then return end  -- 无可达位置
                -- 记录待交互家具信息
                -- 共享仓库未解锁时提前拦截，不启动进度条
                if clickedFurn.interact == "shared_storage" and not GS.sharedStorageUnlocked then
                    return
                end
                GS.homePendingFurniture = clickedFurn
                local ox, oy = GS.player.x, GS.player.y
                if ox == targetX and oy == targetY and not GS.player.moveAnim then
                    GS.homePendingFurniture = nil
                    GS.updateFacing(GS.player, ox, oy, furnCX, furnCY)
                    GS.startFurnitureInteract(furnCX, furnCY, clickedFurn.name, function()
                        if clickedFurn.interact == "warehouse" then
                            GS.enterWarehouseMode(clickedFurn.warehouseId)
                        elseif clickedFurn.interact == "alchemy" then
                            GS.homeAlchemyMode = true
                            GS.alchemyMode = true
                            GS.alchemyResult = nil
                            GS.alchemyScrollY = 0
                            GS.alchemyBtnRects = {}
                        elseif clickedFurn.interact == "cooking" then
                            GS.homeCookingMode = true
                            GS.cookingMode = true
                            GS.cookingResult = nil
                            GS.cookingScrollY = 0
                            GS.cookingBtnRects = {}
                        elseif clickedFurn.interact == "smithy" then
                            GS.homeSmithySelectMode = true
                            GS.homeSmithySelectRects = nil
                        elseif clickedFurn.interact == "socket" then
                            GS.homeSocketMode = true
                            GS.socketMode = true
                            GS.socketResult = nil
                            GS.socketScrollY = 0
                        elseif clickedFurn.interact == "shared_storage" then
                            GS.enterSharedStorageMode()
                        end
                    end, nil, clickedFurn.w, clickedFurn.h)
                elseif GS.player.moveAnim then
                    GS.homePendingTarget = {targetX, targetY}
                    GS.homeChestPending = true
                else
                    local path = GS.homePathFind(ox, oy, targetX, targetY)
                    if path and #path >= 2 then
                        GS.player.x = targetX
                        GS.player.y = targetY
                        Combat.startMoveAnim(GS.player, ox, oy, path)
                        GS.homeChestPending = true
                    end
                end
                return
            end
            -- 家场景允许移动区域：房间内部 + 门格子（根据家园类型）
            local inRoom = cx >= hp.fx1 and cx <= hp.fx2 and cy >= hp.fy1 and cy <= hp.fy2
            local isDoor = (cy == hp.doorY and (cx == hp.doorX1 or cx == hp.doorX2))
            if (inRoom or isDoor) and GS.isCellEmpty(cx, cy) then
                if GS.player.moveAnim then
                    -- 移动中：记录最后一次点击，等当前移动结束后再前往
                    GS.homePendingTarget = {cx, cy}
                    GS.homeChestPending = false  -- 取消储物箱待定
                else
                    local oldX, oldY = GS.player.x, GS.player.y
                    if cx ~= oldX or cy ~= oldY then
                        -- 使用BFS寻路（避开障碍物）
                        local path = GS.homePathFind(oldX, oldY, cx, cy)
                        if path and #path >= 2 then
                            GS.player.x = cx
                            GS.player.y = cy
                            Combat.startMoveAnim(GS.player, oldX, oldY, path)
                            -- 目标是门格子：移动完成后切换到清水镇
                            if isDoor then
                                GS.homeDoorPending = true
                            end
                        end
                    end
                end
            end
            return
        end
        -- 竞技场宝箱开启已移至行动菜单中的"开启"按钮
        if GS.player and GS.player.hp > 0 and not GS.player.acted
            and cx == GS.player.x and cy == GS.player.y then
            GS.selectedUnit = GS.player
            GS.movableCells, GS.movableParents = GS.getMovableCells(GS.player)
            GS.attackableCells = GS.getAttackableCells(GS.player, GS.player.x, GS.player.y)
            GS.gameState = GS.STATE_SELECT
        end
    elseif GS.gameState == GS.STATE_SELECT and GS.selectedUnit then
        -- 移动动画播放期间，阻止所有棋盘操作
        if Combat.pendingManualAction or Combat.pendingAutoAction then return end

        local key = GS.cellKey(cx, cy)

        -- 冰墙方向选择（第二阶段）：点击相邻格子确定延伸方向
        if GS.actionChoice == "iceWallDir" then
            local sx, sy = GS.iceWallStartX, GS.iceWallStartY
            local dx, dy = cx - sx, cy - sy
            -- 必须是上下左右四个相邻格子之一
            if (math.abs(dx) + math.abs(dy) == 1) then
                -- 计算最大墙长
                local wallDef = GS.SKILL_DEFS[GS.actionChosenSkillId]
                local lv = GS.skillLevels[GS.actionChosenSkillId] or 1
                local maxLen = wallDef.iceWallBaseLen or 3
                local breaks = wallDef.iceWallLenBreaks or {3, 6, 10}
                for _, brk in ipairs(breaks) do
                    if lv >= brk then maxLen = maxLen + 1 end
                end
                -- 从起点沿方向延伸，遇到障碍/棋盘边界停止
                local wallCells = {}
                for i = 0, maxLen - 1 do
                    local wx, wy = sx + dx * i, sy + dy * i
                    if not GS.isInBoard(wx, wy) then break end
                    if not GS.isCellEmpty(wx, wy) then break end
                    wallCells[#wallCells + 1] = {x = wx, y = wy}
                end
                if #wallCells > 0 then
                    local iwCastStages = GS.getSkillCastStages(GS.actionChosenSkillId)
                    if iwCastStages > 0 and GS.chantStages < iwCastStages then
                        -- 吟唱段数不足，进入吟唱状态（始终结束回合）
                        local consume = math.min(iwCastStages, GS.chantStages)
                        GS.chantStages = GS.chantStages - consume
                        GS.useSkill(GS.actionChosenSkillId)
                        GS.chanting = { skillId = GS.actionChosenSkillId, wallCells = wallCells, stagesNeeded = iwCastStages, stagesAccum = consume, castType = "icewall" }
                        local left = iwCastStages - consume
                        -- Combat.addDamageText(GS.player.x, GS.player.y, "开始吟唱(还需" .. left .. "段)", {180, 160, 220})
                        GS.advanceTurnPhase()
                        GS.selectedUnit.acted = true
                        GS.closeActionMenu()
                        GS.groundTargetCells = nil
                        GS.iceWallStartX = nil
                        GS.iceWallStartY = nil
                        GS.iceWallPreview = nil
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        Combat.endPlayerTurn()
                    else
                        if iwCastStages > 0 then GS.chantStages = GS.chantStages - iwCastStages end
                        Combat.placeIceWalls(GS.selectedUnit, GS.actionChosenSkillId, wallCells)
                        if not GS.mageCheckContinueTurn() then
                            GS.advanceTurnPhase()
                            GS.selectedUnit.acted = true
                            GS.closeActionMenu()
                            GS.groundTargetCells = nil
                            GS.iceWallStartX = nil
                            GS.iceWallStartY = nil
                            GS.iceWallPreview = nil
                            GS.selectedUnit = nil
                            GS.movableCells = {}
                            GS.attackableCells = {}
                            Combat.endPlayerTurn()
                        end
                    end
                end
            else
                -- 点击非相邻格：取消方向选择，回到地面目标选择
                GS.actionChoice = "groundSkill"
                GS.iceWallStartX = nil
                GS.iceWallStartY = nil
                GS.iceWallPreview = nil
            end
            return
        end

        -- 地面目标技能（圣树等）：点击空地格子放置
        if GS.actionChoice == "groundSkill" then
            local groundCells = GS.groundTargetCells or {}
            local chosenDef = GS.SKILL_DEFS[GS.actionChosenSkillId]
            local needEmpty = not (chosenDef and (chosenDef.iceRingAoe or chosenDef.fireballAoe or chosenDef.meteorAoe or chosenDef.blizzardAoe or chosenDef.thunderAoe))
            if groundCells[key] and (not needEmpty or GS.isCellEmpty(cx, cy)) then
                -- 冰墙术：进入方向选择阶段
                if chosenDef and chosenDef.iceWallSkill then
                    GS.actionChoice = "iceWallDir"
                    GS.iceWallStartX = cx
                    GS.iceWallStartY = cy
                    return
                end
                -- 有效位置，执行技能（吟唱检查）
                local gCastStages = GS.getSkillCastStages(GS.actionChosenSkillId)
                if gCastStages > 0 and GS.chantStages < gCastStages then
                    -- 吟唱段数不足，进入吟唱状态
                    local consume = math.min(gCastStages, GS.chantStages)
                    GS.chantStages = GS.chantStages - consume
                    GS.useSkill(GS.actionChosenSkillId)
                    GS.chanting = { skillId = GS.actionChosenSkillId, tx = cx, ty = cy, stagesNeeded = gCastStages, stagesAccum = consume, castType = "ground" }
                    local left = gCastStages - consume
                    -- Combat.addDamageText(GS.player.x, GS.player.y, "开始吟唱(还需" .. left .. "段)", {180, 160, 220})
                    GS.advanceTurnPhase()
                    GS.selectedUnit.acted = true
                    GS.closeActionMenu()
                    GS.groundTargetCells = nil
                    GS.selectedUnit = nil
                    GS.movableCells = {}
                    GS.attackableCells = {}
                    Combat.endPlayerTurn()
                else
                    if gCastStages > 0 then GS.chantStages = GS.chantStages - gCastStages end
                    GS.lastActionTargetX = cx
                    GS.lastActionTargetY = cy
                    -- 记录AOE半径，用于菜单避让整个爆炸区域
                    -- 计算实际 AOE 爆炸半径（注意：skillRange 是施法距离，不是爆炸半径）
                    local aoeR = chosenDef.fireballRadius or chosenDef.meteorRadius or chosenDef.blizzardRadius or 0
                    if aoeR == 0 and (chosenDef.iceRingAoe or chosenDef.holyTree) then aoeR = 1 end  -- 3×3 范围 = 半径1
                    GS.lastActionAoeRadius = aoeR > 0 and aoeR or nil
                    Combat.addSkillCastText(GS.selectedUnit.x, GS.selectedUnit.y, GS.actionChosenSkillId)
                    Combat.executeGroundSkill(GS.selectedUnit, GS.actionChosenSkillId, cx, cy)
                    if chosenDef and chosenDef.freeAction then
                        -- 免费行动技能（闪烁等）：不占用攻击回合，回到行动菜单
                        GS.actionChoice = nil
                        GS.actionChosenSkillId = nil
                        GS.groundTargetCells = nil
                        GS.actionMenuVisible = true
                        GS.movableCells = {}
                        GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y)
                    else
                        Combat.removeDeadMonsters()
                        if not GS.mageCheckContinueTurn() then
                            GS.advanceTurnPhase()  -- ACTION → END
                            GS.selectedUnit.acted = true
                            GS.closeActionMenu()
                            GS.groundTargetCells = nil
                            GS.selectedUnit = nil
                            GS.movableCells = {}
                            GS.attackableCells = {}
                            Combat.endPlayerTurn()
                        else
                            GS.groundTargetCells = nil
                        end
                    end
                end
            else
                -- 点击了无效位置：取消选择，回到行动菜单
                GS.actionMenuVisible = true
                GS.actionChoice = nil
                GS.actionChosenSkillId = nil
                GS.groundTargetCells = nil
                GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y)
            end
            return
        end

        -- 点选目标型自我施放技能：点击自身或友方目标执行
        if GS.actionChoice == "selfSkill" and GS.selectedUnit then
            local pu = GS.selectedUnit
            local skillId = GS.actionChosenSkillId
            local skillDef = skillId and GS.SKILL_DEFS[skillId]
            -- 判断点击位置是否为有效友方目标（自身、猎犬、冰墙、圣树）
            local friendlyTarget = nil
            if cx == pu.x and cy == pu.y then
                friendlyTarget = pu  -- 自身
            else
                -- 检查施展距离
                local dist = math.abs(cx - pu.x) + math.abs(cy - pu.y)
                local castRange = (skillDef and skillDef.skillRange) or (GS.player and GS.player.atkRange) or 3
                if skillDef and skillDef.rangeBreaks then
                    local slv = GS.skillLevels[skillId] or 1
                    for _, brk in ipairs(skillDef.rangeBreaks) do
                        if slv >= brk then castRange = castRange + 1 end
                    end
                end
                if skillId then castRange = castRange + GS.getElementRangeBonus(skillId) end
                if skillDef and skillDef.useMagic then castRange = math.max(castRange, 3) end
                if dist <= castRange then
                    local unit = GS.getUnitAt(cx, cy)
                    if unit and not unit.isMonster then
                        friendlyTarget = unit  -- 友方单位（猎犬、冰墙、圣树等）
                    end
                end
            end
            if friendlyTarget then
                local castStages = GS.getSkillCastStages(skillId)
                if castStages > 0 and GS.chantStages < castStages then
                    -- 吟唱段数不足，进入吟唱状态（始终结束回合）
                    local consume = math.min(castStages, GS.chantStages)
                    GS.chantStages = GS.chantStages - consume
                    GS.useSkill(skillId)
                    GS.chanting = { skillId = skillId, stagesNeeded = castStages, stagesAccum = consume, castType = "selfTarget", target = friendlyTarget }
                    local left = castStages - consume
                    -- Combat.addDamageText(pu.x, pu.y, "开始吟唱(还需" .. left .. "段)", {180, 160, 220})
                    GS.advanceTurnPhase()
                    pu.acted = true
                    GS.closeActionMenu()
                    GS.selectedUnit = nil
                    GS.movableCells = {}
                    GS.attackableCells = {}
                    Combat.endPlayerTurn()
                else
                    -- 段数充足，直接释放
                    GS.consumeChantForSkill(skillId)
                    Combat.addSkillCastText(pu.x, pu.y, skillId)
                    Combat.executePlayerAttack(pu, friendlyTarget, skillId)
                    if not GS.mageCheckContinueTurn() then
                        GS.advanceTurnPhase()
                        pu.acted = true
                        GS.closeActionMenu()
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        Combat.endPlayerTurn()
                    end
                end
                return
            else
                -- 点击其他位置取消，回到行动菜单
                GS.actionChoice = nil
                GS.actionChosenSkillId = nil
                GS.actionMenuVisible = true
                return
            end
        end

        -- 选择了"采集"后点击采集物目标（必须在通用 actionChoice 拦截之前）
        if GS.actionChoice == "gather" then
            if GS.attackableCells[key] then
                local target = GS.getUnitAt(cx, cy)
                if target and target.isGatherable and not target.vanishing and (target.harvestsLeft or 1) > 0 then
                    GS.advanceTurnPhase()  -- ACTION → END
                    GS.movableCells = {}
                    GS.attackableCells = {}
                    GS.closeActionMenu()
                    GS.selectedUnit = nil
                    GS.gameState = GS.STATE_PLAYER  -- 采集开始，退出 SELECT 状态
                    local playerHLv = GS.getLifeSkillHiddenLevel(target.lifeSkill or "gathering")
                    local gatherHLv = target.hiddenLevel or 0
                    local lvDiff = playerHLv - gatherHLv
                    local ppt = lvDiff >= 200 and 1.0 or (lvDiff >= 100 and 0.50 or 0.34)
                    GS.gatheringState = {
                        target      = target,
                        progress    = 0,
                        turnCount   = 0,
                        successRate = GS.calcGatherSuccessRate(playerHLv, gatherHLv),
                        progressPerTurn = ppt,
                    }
                    local turns = ppt >= 1.0 and 1 or (ppt >= 0.50 and 2 or 3)
                    print("[采集] 开始采集 " .. target.name .. "（每回合+" .. math.floor(ppt*100) .. "%，预计" .. turns .. "回合）")
                    return
                end
            end
            -- 点击了非采集物：重新打开行动菜单
            GS.actionMenuVisible = true
            GS.actionChoice = nil
            GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y)
            return
        end

        -- 已选择行动（普通攻击/技能）等待点击目标时，只允许点击敌人
        if GS.actionChoice then
            local target = GS.getUnitAt(cx, cy)
            -- 范围化 AOE 技能允许点击攻击范围内的空地
            local aoeGroundOk = GS.aoeGroundMode and (not target) and GS.attackableCells[key]
            if not aoeGroundOk and not (target and target.isMonster and GS.attackableCells[key]) then
                -- 点击了非敌人目标：重新打开行动菜单
                GS.actionMenuVisible = true
                GS.actionChoice = nil
                GS.actionChosenSkillId = nil
                -- 恢复正常攻击距离（可能被 skillRange 覆盖过）
                GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y)
                return
            end
            -- 是有效目标（敌人或 AOE 空地），继续往下走到攻击逻辑
        end

        -- 点击自己：原地不动，直接进入行动阶段
        if cx == GS.selectedUnit.x and cy == GS.selectedUnit.y then
            -- 法师/牧师攻击后剩余吟唱段数，点击自己重新打开菜单
            if GS.mageWaitingForClick and GS.turnPhase == GS.PHASE_ACTION then
                GS.mageWaitingForClick = nil
                GS.actionMenuVisible = true
                GS.actionChoice = nil
                GS.actionChosenSkillId = nil
                return
            end
            if GS.turnPhase == GS.PHASE_MOVE then
                GS.advanceTurnPhase()  -- MOVE → MID → ACTION
                GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, cx, cy)

                if not GS.autoMode then
                    GS.movableCells = {}
                    GS.actionMenuVisible = true
                    GS.actionChoice = nil
                    GS.actionChosenSkillId = nil
                    GS.actionPreMoveX = cx
                    GS.actionPreMoveY = cy
                else
                    local hasTarget = false
                    for _, m in ipairs(GS.monsters) do
                        if m.hp > 0 and GS.attackableCells[GS.cellKey(m.x, m.y)] then
                            hasTarget = true
                            break
                        end
                    end
                    if not hasTarget then
                        GS.advanceTurnPhase()  -- ACTION → END
                        GS.selectedUnit.acted = true
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        Combat.endPlayerTurn()
                    else
                        GS.movableCells = {}
                    end
                end
            end
            return
        end

        -- 点击可移动格子（移动阶段）
        if GS.movableCells[key] and GS.turnPhase == GS.PHASE_MOVE then
            local oldX, oldY = GS.selectedUnit.x, GS.selectedUnit.y
            Command.recordMove(oldX, oldY, cx, cy)
            local path = GS.reconstructPath(GS.movableParents, oldX, oldY, cx, cy)
            GS.recordPlayerPath(path)
            GS.selectedUnit.x = cx
            GS.selectedUnit.y = cy
            Combat.startMoveAnim(GS.selectedUnit, oldX, oldY, path)

            GS.advanceTurnPhase()  -- MOVE → MID → ACTION

            -- 延迟行动：等移动动画完成后再显示行动菜单/执行攻击
            Combat.pendingManualAction = { oldX = oldX, oldY = oldY, movePath = path }
            return
        end

        -- 点击攻击范围内的怪物
        if GS.attackableCells[key] then
            local target = GS.getUnitAt(cx, cy)
            if target and target.isMonster then
                -- 记录点击的格子坐标（多格单位弹道飞向选中格）
                local ts = GS.unitSize(target)
                if ts > 1 then
                    target._clickedTileX = cx
                    target._clickedTileY = cy
                else
                    target._clickedTileX = nil
                    target._clickedTileY = nil
                end
                if not GS.autoMode and not GS.actionChoice then
                    -- 非自动模式且未选择行动：显示行动菜单
                    if GS.turnPhase == GS.PHASE_MOVE then
                        GS.advanceTurnPhase()  -- MOVE → MID → ACTION
                    end
                    GS.movableCells = {}
                    GS.actionMenuVisible = true
                    GS.actionChoice = nil
                    GS.actionChosenSkillId = nil
                    return
                end

                if GS.turnPhase == GS.PHASE_MOVE then
                    GS.advanceTurnPhase()  -- MOVE → MID → ACTION
                end

                local useSkillId
                if GS.autoMode then
                    useSkillId = GS.pickActiveSkill()
                elseif GS.actionChoice == "skill" then
                    useSkillId = GS.actionChosenSkillId
                else
                    useSkillId = nil  -- 普通攻击
                end

                Command.recordAttack(target.x, target.y, useSkillId)
                -- 吟唱检查（单体技能 + 法杖普攻消耗1段）
                local castStages = useSkillId and GS.getSkillCastStages(useSkillId) or 0
                local wTag = GS.equipment and GS.equipment["weapon_r"] and GS.equipment["weapon_r"].weaponTag
                local isCaster = (GS.currentClass == "mage" or GS.currentClass == "priest")
                local isStaffNormalAtk = (not useSkillId) and isCaster and wTag == "法杖"
                -- 施法职业用非法杖普攻（含无武器）：消耗全部吟唱段数，结束回合
                local isMeleeCasterAtk = (not useSkillId) and isCaster and wTag ~= "法杖"
                if isStaffNormalAtk then castStages = 1 end
                if isStaffNormalAtk and GS.chantStages < 1 then
                    -- 法杖普攻需要1段吟唱但段数不足，无法攻击
                    return
                elseif castStages > 0 and GS.chantStages < castStages then
                    -- 吟唱段数不足，进入吟唱状态
                    local consume = math.min(castStages, GS.chantStages)
                    GS.chantStages = GS.chantStages - consume
                    GS.useSkill(useSkillId)
                    GS.chanting = { skillId = useSkillId, target = target, stagesNeeded = castStages, stagesAccum = consume, castType = "single" }
                    local left = castStages - consume
                    -- Combat.addDamageText(GS.player.x, GS.player.y, "开始吟唱(还需" .. left .. "段)", {180, 160, 220})
                    GS.advanceTurnPhase()
                    GS.selectedUnit.acted = true
                    GS.closeActionMenu()
                    GS.selectedUnit = nil
                    GS.movableCells = {}
                    GS.attackableCells = {}
                    Combat.endPlayerTurn()
                else
                    GS.consumeChantForSkill(useSkillId)
                    -- 法杖普攻：consumeChantForSkill 不处理 nil skillId，手动消耗1段
                    if isStaffNormalAtk then
                        GS.chantStages = math.max(0, (GS.chantStages or 0) - 1)
                    end
                    -- 祝福术/超度：消耗全部剩余吟唱段数（使用1次即结束回合）
                    if useSkillId and (useSkillId == "p_bless" or useSkillId == "p_exorcism") then
                        GS.chantStages = 0
                    end
                    GS.lastActionTargetX = target.x
                    GS.lastActionTargetY = target.y
                    GS.lastActionAoeRadius = nil  -- 单体攻击，无AOE半径
                    Combat.addSkillCastText(GS.selectedUnit.x, GS.selectedUnit.y, useSkillId)
                    Combat.executePlayerAttack(GS.selectedUnit, target, useSkillId)
                    Combat.removeDeadMonsters()
                    -- 施法职业近战武器普攻：消耗全部剩余吟唱段数，直接结束回合
                    if isMeleeCasterAtk then GS.chantStages = 0 end
                    if not GS.mageCheckContinueTurn() then
                        GS.advanceTurnPhase()  -- ACTION → END
                        GS.selectedUnit.acted = true
                        GS.closeActionMenu()
                        -- 连击队列：有额外攻击时延迟结束回合
                        if not Combat.startChainIfNeeded(function()
                            Combat.endPlayerTurn()
                        end) then
                            GS.selectedUnit = nil
                            GS.movableCells = {}
                            GS.attackableCells = {}
                            Combat.endPlayerTurn()
                        end
                    end
                end
            end
            -- 范围化 AOE 技能点击空地施放（银色狮子强击系/哈雷努拉祝福超度）
            if not target and GS.aoeGroundMode and GS.actionChoice == "skill" and GS.actionChosenSkillId then
                local useSkillId = GS.actionChosenSkillId
                if GS.selectedUnit then
                    if GS.turnPhase == GS.PHASE_MOVE then
                        GS.advanceTurnPhase()  -- MOVE → MID → ACTION
                    end
                    -- 构造虚拟目标（只需 x,y 供 AOE 方向计算）
                    local virtualTarget = { x = cx, y = cy }
                    Command.recordAttack(cx, cy, useSkillId)
                    -- 吟唱检查
                    local castStages = GS.getSkillCastStages(useSkillId)
                    if castStages > 0 and GS.chantStages < castStages then
                        local consume = math.min(castStages, GS.chantStages)
                        GS.chantStages = GS.chantStages - consume
                        GS.useSkill(useSkillId)
                        GS.chanting = { skillId = useSkillId, target = virtualTarget, stagesNeeded = castStages, stagesAccum = consume, castType = "single" }
                        GS.advanceTurnPhase()
                        GS.selectedUnit.acted = true
                        GS.closeActionMenu()
                        GS.selectedUnit = nil
                        GS.movableCells = {}
                        GS.attackableCells = {}
                        Combat.endPlayerTurn()
                    else
                        GS.consumeChantForSkill(useSkillId)
                        -- 祝福术/超度：消耗全部剩余吟唱段数
                        if useSkillId == "p_bless" or useSkillId == "p_exorcism" then
                            GS.chantStages = 0
                        end
                        GS.lastActionTargetX = cx
                        GS.lastActionTargetY = cy
                        GS.lastActionAoeRadius = nil
                        Combat.addSkillCastText(GS.selectedUnit.x, GS.selectedUnit.y, useSkillId)
                        Combat.executePlayerAttack(GS.selectedUnit, virtualTarget, useSkillId)
                        Combat.removeDeadMonsters()
                        if not GS.mageCheckContinueTurn() then
                            GS.advanceTurnPhase()  -- ACTION → END
                            GS.selectedUnit.acted = true
                            GS.closeActionMenu()
                            if not Combat.startChainIfNeeded(function()
                                Combat.endPlayerTurn()
                            end) then
                                GS.selectedUnit = nil
                                GS.movableCells = {}
                                GS.attackableCells = {}
                                Combat.endPlayerTurn()
                            end
                        end
                    end
                end
            end
            return
        end

        -- 点击其他位置取消
        GS.closeActionMenu()
        GS.selectedUnit = nil
        GS.movableCells = {}
        GS.attackableCells = {}
        GS.aoeGroundMode = false
        GS.gameState = GS.STATE_PLAYER
    end
end

-- ====================================================================
-- 鼠标释放（滑块拖拽结束）
-- ====================================================================
function M.handleMouseUp(eventType, eventData)
    -- 清除长按加点状态
    statHoldKey = nil
    -- 清除长按制作状态
    craftHoldType = nil

    -- 街头睡觉中：屏蔽所有操作
    if GS.streetSleepActive then return end

    -- 息屏挂机中：检测上滑解锁
    if GS.screenOffMode then
        if GS._screenOffSwipeStartY then
            local my2 = eventData["Y"]:GetInt() / GS.dpr / GS.S
            local dy = GS._screenOffSwipeStartY - my2
            local threshold = GS.SCREEN_H * 0.15
            if dy >= threshold then
                GS.screenOffMode = false
            end
        end
        GS._screenOffSwipeStartY = nil
        GS._screenOffSwipeCurrentY = nil
        return
    end

    -- 监测面板/在线监测面板拖动结束
    MonitorPanel.handleRelease()
    OnlineMonitor.handleRelease()

    -- 阅读弹窗拖动结束
    GS.readingPopupTouchStartY = nil

    -- 弹窗打开时屏蔽所有操作
    if GS.destroyConfirmVisible then return end

    -- 拆分弹窗：滑动条拖动结束
    if GS.splitPopupSliderDragging then
        GS.splitPopupSliderDragging = false
        return
    end
    if GS.splitPopupVisible then return end

    if GS.volumeSliderDragging then
        GS.volumeSliderDragging = false
        GS.saveVolumeToCloud()
    end

    -- 地图关卡列表滚动条/触摸拖动结束
    if GS.mapStageScrollbarDragging then
        GS.mapStageScrollbarDragging = false
    end
    GS.mapStageTouchStartY = nil

    -- 锻造面板触摸/滚动条拖动结束
    GS.forgeTouchStartY = nil
    GS.forgeScrollBarDragging = nil

    -- 炼金面板触摸/滚动条拖动结束
    GS.alchemyTouchStartY = nil
    GS.alchemyScrollBarDragging = nil
    GS.cookingTouchStartY = nil
    GS.cookingScrollBarDragging = nil

    -- 镶嵌面板触摸拖动结束：判断是否为点击（未拖动）
    if GS.socketTouchStartY then
        local dragDist = math.abs((GS.socketScrollY or 0) - (GS.socketTouchStartScroll or 0))
        if dragDist < 3 and GS._socketPendingGemBtn then
            -- 未发生明显拖动，当作点击处理
            local btn = GS._socketPendingGemBtn
            if GS.socketSelectedGemBag == btn.bagSlot then
                GS.socketSelectedGemBag = nil
            else
                GS.socketSelectedGemBag = btn.bagSlot
                -- 如果没有选中宝石槽，自动选中第一个空槽
                if not GS.socketSelectedGemSlot and GS.socketEquipItem and GS.socketEquipItem.gemSlots then
                    for gi, gs in ipairs(GS.socketEquipItem.gemSlots) do
                        if not gs.gemId then
                            GS.socketSelectedGemSlot = gi
                            break
                        end
                    end
                end
            end
        end
        GS.socketTouchStartY = nil
        GS._socketPendingGemBtn = nil
    end

    -- Tooltip 面板触摸拖动结束
    GS.tooltipTouchStartY = nil
    GS.tooltipTouchTarget = nil

    -- 角色属性汇总拖动结束
    if GS.charStatDragging then
        GS.charStatDragging = false
    end

    -- BUFF总结面板拖动结束
    if GS.buffSummaryDragging then
        GS.buffSummaryDragging = false
    end

    -- 怪物BUFF面板拖动结束
    if GS.monsterBuffDragging then
        GS.monsterBuffDragging = false
    end

    -- 共享仓库日志面板拖动结束
    if GS.sharedStorageLogDragging then
        GS.sharedStorageLogDragging = false
    end

    -- 史莱姆排名面板拖动结束
    if GS._slimeRankDragging then
        GS._slimeRankDragging = false
    end

    -- 迪哈塔排名面板拖动结束
    if GS._dihataRankDragging then
        GS._dihataRankDragging = false
    end

    -- 迪哈塔奖励面板拖动结束：判断是否为点击（弹出tooltip）
    if GS._dihataRewardDragging then
        GS._dihataRewardDragging = false
        local dragDist = math.abs((GS.dihataRevengeRewardScroll or 0) - (GS._dihataRewardDragStartScroll or 0))
        if dragDist < 3 and GS._dihataRewardPendingRow then
            -- 未发生明显拖动且点击了图标 → 弹出物品tooltip
            local pending = GS._dihataRewardPendingRow
            local tpl = GS.itemTemplates and GS.itemTemplates[pending.itemId]
            if tpl then
                GS.tooltipItem = tpl
                GS.tooltipSlotIdx = 0
                GS.tooltipSource = "reward_preview"
                GS.tooltipEquipSlotId = nil
                GS.tooltipPinned = true
                GS.tooltipPinnedPos = nil
                GS.tooltipScrollY = 0
                GS.tooltipAnchorRect = pending.rect
            end
        end
        GS._dihataRewardPendingRow = nil
    end

    -- 史莱姆奖励面板拖动结束：判断是否为点击（弹出tooltip）
    if GS._slimeRewardDragging then
        GS._slimeRewardDragging = false
        local dragDist = math.abs((GS.slimeRevengeRewardScroll or 0) - (GS._slimeRewardDragStartScroll or 0))
        if dragDist < 3 and GS._slimeRewardPendingRow then
            -- 未发生明显拖动且点击了图标 → 弹出物品tooltip
            local pending = GS._slimeRewardPendingRow
            local tpl = GS.itemTemplates and GS.itemTemplates[pending.itemId]
            if tpl then
                GS.tooltipItem = tpl
                GS.tooltipSlotIdx = 0
                GS.tooltipSource = "reward_preview"
                GS.tooltipEquipSlotId = nil
                GS.tooltipPinned = true
                GS.tooltipPinnedPos = nil
                GS.tooltipScrollY = 0
                GS.tooltipAnchorRect = pending.rect
            end
        end
        GS._slimeRewardPendingRow = nil
    end

    -- 日志面板拖动结束
    if GS.journalDragging then
        GS.journalDragging = false
    end

    -- 测试关卡面板拖动结束
    if GS.testStageDragging then
        GS.testStageDragging = false

        local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
        local my = eventData["Y"]:GetInt() / GS.dpr / GS.S

        -- 没有拖动过 → 当作点击
        if not GS.testStageDragMoved then
            for _, btn in ipairs(GS.testStageBtnRects) do
                if hitTest(mx, my, btn) then
                    local idx = btn.stageIdx
                    if idx ~= GS.currentStage then
                        local function doTestStageSwitch()
                            -- 酒馆肉搏中切换关卡：取消任务并清空状态
                            if GS.tavernBrawlState and not GS.tavernBrawlState.done then
                                print("[酒馆肉搏] 战斗中切换关卡，任务中断")
                                GS.tavernBrawlState = nil
                                GS.brawlCinematic = nil
                            end
                            GS.saveGatherStageState()
                            GS.currentStage = idx
                            -- 史莱姆国王大反击：重置累计伤害和暴怒层数，满血满蓝
                            if idx == GS.STAGE_SLIME_KING_REVENGE then
                                GS.slimeRevengeAccDmg = 0
                                GS.slimeRevengeRageLayer = 0
                                if GS.player then
                                    GS.clearAllBuffsDebuffs()
                                    GS.recalcStats(GS.player)
                                    GS.player.hp = GS.player.maxHp
                                    GS.player.mp = GS.player.maxMp
                                end
                            end
                            -- 迪哈塔大反击：重置累计伤害和暴怒层数，满血满蓝
                            if idx == GS.STAGE_DIHATA_REVENGE then
                                GS.dihataRevengeAccDmg = 0
                                GS.dihataRevengeRageLayer = 0
                                if GS.player then
                                    GS.clearAllBuffsDebuffs()
                                    GS.recalcStats(GS.player)
                                    GS.player.hp = GS.player.maxHp
                                    GS.player.mp = GS.player.maxMp
                                end
                            end
                            GS.turnNumber = 1
                            Combat.clearPendingState()
                            GS.monsters = {}
                            GS.companions = {}
                            GS.fireCorpses = {}
                            GS.gatherables = {}
                            GS.gatheringState = nil
                            GS.gatherResultAnim = nil
                            GS.playerDebuffs = {}
                            GS.flushPendingMpRestores()
                            GS.damageTexts = {}
                            -- 清除召唤物和持续效果
                            GS.holyTrees = {}
                            GS.iceWalls = {}
                            GS.burningGrounds = {}
                            GS.pendingBurningGrounds = {}
                            GS.blizzardZones = {}
                            GS.thunderClouds = {}
                            -- 清除吟唱和隐匿状态
                            GS.chanting = nil
                            GS.stealthActive = false
                            GS.stealthTurns = 0
                            GS.attackEffects = {}
                            GS.strikeEffects = {}
                            GS.whirlwindEffects = {}
                            GS.stealthSmokeEffect = nil
                            GS.pendingEndPlayerTurn = false
                            GS._pendingEndTurnTimer = nil
                            GS.screenShake = nil
                            GS.selectedUnit = nil
                            GS.movableCells = {}
                            GS.attackableCells = {}
                            GS.closeActionMenu()
                            -- 清除烹饪等家园子面板残留
                            GS.cookingMode = false
                            GS.homeCookingMode = false
                            GS.cookingResult = nil
                            Combat.spawnGatherables()
                            Combat.spawnMonsters()
                            GS.spawnHound()
                            -- 施法职业切换关卡时重置并充能吟唱段数
                            if (GS.currentClass == "mage" or GS.currentClass == "priest") and GS.player and GS.player.hp > 0 then
                                GS.chantStages = 0
                                local gained = GS.rollChantStages()
                                GS.chantStages = gained
                                GS.chantStagesMax = gained
                            end
                            local stageDef = GS.STAGE_DEFS[idx]
                            print("=== 切换到关卡 " .. idx .. ": " .. (stageDef and stageDef.name or "?") .. " ===")
                        end

                        -- 史莱姆国王大反击：需要确认消耗次数
                        if idx == GS.STAGE_SLIME_KING_REVENGE then
                            local remain = GS.getSlimeRevengeRemain()
                            if remain > 0 then
                                GS.slimeRevengeConfirmType = "daily"
                            else
                                GS.slimeRevengeConfirmType = "ad"
                            end
                            GS.slimeRevengeConfirmVisible = true
                            GS.slimeRevengeConfirmCallback = doTestStageSwitch
                            return
                        end

                        -- 迪哈塔大反击：需要确认消耗次数
                        if idx == GS.STAGE_DIHATA_REVENGE then
                            local remain = GS.getDihataRevengeRemain()
                            if remain > 0 then
                                GS.dihataRevengeConfirmType = "daily"
                            else
                                GS.dihataRevengeConfirmType = "ad"
                            end
                            GS.dihataRevengeConfirmVisible = true
                            GS.dihataRevengeConfirmCallback = doTestStageSwitch
                            return
                        end

                        -- 自动战斗回合进行中：延迟到回合结束再切换
                        if Combat.isTurnBusy() then
                            Combat.pendingStageSwitch = doTestStageSwitch
                        else
                            doTestStageSwitch()
                        end
                    end
                    break
                end
            end
        end
        return
    end

    -- 测试道具滚动条拖动结束
    if GS.testItemScrollbarDragging then
        GS.testItemScrollbarDragging = false
    end
    -- 测试道具面板拖动结束
    if GS.testItemDragging then
        GS.testItemDragging = false

        local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
        local my = eventData["Y"]:GetInt() / GS.dpr / GS.S

        -- 没有拖动过 → 当作点击，发放道具
        if not GS.testItemDragMoved then
            local bulkIds = {
                -- 锭
                iron_ingot = true, copper_ingot = true, silver_ingot = true,
                gold_ingot = true, blue_silver_ingot = true,
                radiant_gold_ingot = true, black_steel_ingot = true,
                mithril_ingot = true, true_silver_ingot = true, true_gold_ingot = true,
                -- 精炼石
                refine_stone_2 = true, refine_stone_3 = true, refine_stone_4 = true,
                refine_stone_5 = true, refine_stone_6 = true, refine_stone_7 = true,
                refine_stone_8 = true, refine_stone_9 = true, refine_stone_10 = true,
                -- 金属矿石
                crude_iron_ore = true, tongkuang = true, yinkuang = true,
                jinkuangshi = true, lanyinkuangshi = true, huijinkuangshi = true,
                heigangkuangshi = true, miyinkuangshi = true,
                zhenyinkuangshi = true, zhenjinkuangshi = true,
                -- 碎裂晶矿
                zishuijing_cujing = true, hongshuijing_cujing = true,
                huangshuijing_cujing = true, lanshuijing_cujing = true,
                lvshuijing_cujing = true, heishuijing_cujing = true,
                baishuijing_cujing = true, fenshuijing_cujing = true,
                -- 完整晶矿
                fenshuijing_wanzheng = true, hongshuijing_wanzheng = true,
                huangshuijing_wanzheng = true, lanshuijing_wanzheng = true,
                lvshuijing_wanzheng = true, heishuijing_wanzheng = true,
                baishuijing_wanzheng = true, zishuijing_wanzheng = true,
                -- 纯净晶矿
                zishuijing_chunjing = true, fenshuijing_chunjing = true,
                hongshuijing_chunjing = true, huangshuijing_chunjing = true,
                lanshuijing_chunjing = true, lvshuijing_chunjing = true,
                heishuijing_chunjing = true, baishuijing_chunjing = true,
                -- 闪耀晶矿
                hongshuijing_shanyao = true, huangshuijing_shanyao = true,
                lanshuijing_shanyao = true, lvshuijing_shanyao = true,
                heishuijing_shanyao = true, baishuijing_shanyao = true,
                zishuijing_shanyao = true, fenshuijing_shanyao = true,
                -- 感恩礼券
                gratitude_ticket = true,
                -- 雕刻工具
                refine_slot_tool = true,
                socket_drill_tool = true,
                -- 神炼系列
                divine_enchant_agent = true,
                divine_catalyst = true,
                divine_repair_agent = true,
                divine_toughness_agent = true,
            }
            for _, btn in ipairs(GS.testItemBtnRects or {}) do
                if hitTest(mx, my, btn) then
                    -- 金币特殊处理
                    if btn.special == "gold_100k" then
                        GS.gold = GS.gold + 100000
                        print("[测试] 已获得 100000 金币，当前: " .. GS.gold)
                        break
                    end
                    -- 深渊积分特殊处理
                    if btn.special == "abyss_points_100" then
                        GS.abyssPoints = (GS.abyssPoints or 0) + 100
                        print("[测试] 已获得 100 深渊积分，当前: " .. GS.abyssPoints)
                        break
                    end
                    local giveQty = bulkIds[btn.itemId] and 99 or 1
                    local ok, msg, lastItem = GS.addToInventory(btn.itemId, giveQty)
                    if ok then
                        if lastItem and not btn.special then
                            -- 非特殊装备：附魔/精炼槽判定（与野外掉落一致）
                            local tplCheck = GS.itemTemplates[btn.itemId]
                            if tplCheck and tplCheck.slot then
                                local dropTier = GS.getTierByLevel(tplCheck.level or 1)
                                lastItem.tier = dropTier
                                if math.random() < GS.ENCHANT_CHANCE then
                                    GS.rollEnchantment(lastItem, dropTier)
                                end
                                GS.rollRefineSlots(lastItem, dropTier)
                                GS.rollGemSlots(lastItem)
                                -- 深渊装备100%携带随机词缀
                                if btn.itemId:find("^abyss_") then
                                    local pool = GS.ABYSS_AFFIX_POOL
                                    if pool and #pool > 0 then
                                        local roll = pool[math.random(#pool)]
                                        lastItem.abyssAffix = {
                                            id = roll.id, name = roll.name,
                                            desc = roll.desc, mechanic = roll.mechanic,
                                        }
                                    end
                                end
                                -- 深渊卓越武器随机属性（abyssRandomStats）
                                local abyssRand = tplCheck.abyssRandomStats
                                if abyssRand then
                                    local newEff = {}
                                    for k, v in pairs(lastItem.effects or {}) do newEff[k] = v end
                                    lastItem.effects = newEff
                                    local newExtra = {}
                                    for k, v in pairs(lastItem.extraEffects or {}) do newExtra[k] = v end
                                    lastItem.extraEffects = newExtra
                                    local statTiers = {}
                                    if abyssRand.effects then
                                        for k, rule in pairs(abyssRand.effects) do
                                            if rule.type == "pct_uniform" and newEff[k] and rule.values and #rule.values > 0 then
                                                local base = newEff[k]
                                                local idx = math.random(#rule.values)
                                                local pct = rule.values[idx]
                                                newEff[k] = math.floor(base * (1 + pct / 100) + 0.5)
                                                statTiers[k] = idx
                                            elseif rule.type == "uniform" and rule.values and #rule.values > 0 then
                                                local idx = math.random(#rule.values)
                                                newEff[k] = rule.values[idx]
                                                statTiers[k] = idx
                                            end
                                        end
                                    end
                                    if abyssRand.extraEffects then
                                        for k, rule in pairs(abyssRand.extraEffects) do
                                            if rule.type == "uniform" and rule.values and #rule.values > 0 then
                                                local idx = math.random(#rule.values)
                                                newExtra[k] = rule.values[idx]
                                                statTiers[k] = idx
                                            end
                                        end
                                    end
                                    -- allstat_lines：N条全属性词缀
                                    if abyssRand.allstat_lines then
                                        local asl = abyssRand.allstat_lines
                                        local lineResults = {}
                                        for i = 1, (asl.count or 1) do
                                            local idx = math.random(#asl.values)
                                            local val = asl.values[idx]
                                            lineResults[i] = { value = val, tier = idx }
                                            for _, ak in ipairs(asl.keys) do
                                                newExtra[ak] = (newExtra[ak] or 0) + val
                                            end
                                        end
                                        lastItem.allstatLines = lineResults
                                    end
                                    -- randomResist：随机元素抗性，支持单对象或数组（多段独立随机池）
                                    if abyssRand.randomResist then
                                        local rrList = abyssRand.randomResist
                                        if rrList.pool then rrList = { rrList } end  -- 单对象兼容
                                        local resistResults = {}
                                        for _, rr in ipairs(rrList) do
                                            local pool = {}
                                            for i, v in ipairs(rr.pool) do pool[i] = v end
                                            for i = #pool, 2, -1 do
                                                local j = math.random(i)
                                                pool[i], pool[j] = pool[j], pool[i]
                                            end
                                            for i = 1, math.min(rr.count or 3, #pool) do
                                                local key = pool[i]
                                                local idx = math.random(#rr.values)
                                                local val = rr.values[idx]
                                                newExtra[key] = val
                                                statTiers[key] = idx
                                                resistResults[#resistResults + 1] = { key = key, value = val, tier = idx }
                                            end
                                        end
                                        lastItem.randomResistLines = resistResults
                                    end
                                    -- randomMainBase：从 pool 中随机选 count 种主属性作为基础效果
                                    if abyssRand.randomMainBase then
                                        local rmb = abyssRand.randomMainBase
                                        local pool = {}
                                        for i, v in ipairs(rmb.pool) do pool[i] = v end
                                        for i = #pool, 2, -1 do
                                            local j = math.random(i)
                                            pool[i], pool[j] = pool[j], pool[i]
                                        end
                                        local baseLines = {}
                                        for i = 1, math.min(rmb.count or 1, #pool) do
                                            local key = pool[i]
                                            local val = rmb.value or 1
                                            newEff[key] = (newEff[key] or 0) + val
                                            baseLines[i] = { key = key, value = val }
                                        end
                                        lastItem.randomMainBaseLines = baseLines
                                    end
                                    -- randomMainExtra：从 pool 中随机选 count 条主属性词缀（可重复），值随机
                                    if abyssRand.randomMainExtra then
                                        local rme = abyssRand.randomMainExtra
                                        local extraLines = {}
                                        for i = 1, (rme.count or 1) do
                                            local key = rme.pool[math.random(#rme.pool)]
                                            local idx = math.random(#rme.values)
                                            local val = rme.values[idx]
                                            newExtra[key] = (newExtra[key] or 0) + val
                                            extraLines[i] = { key = key, value = val, tier = idx }
                                        end
                                        lastItem.randomMainExtraLines = extraLines
                                    end
                                    lastItem.abyssStatTiers = statTiers
                                    lastItem.hasRandom = true
                                end
                            end
                            -- forceAbyssAffix：必定携带深渊词缀
                            if tplCheck.forceAbyssAffix then
                                local roll = GS.ABYSS_AFFIX_POOL[math.random(#GS.ABYSS_AFFIX_POOL)]
                                lastItem.abyssAffix = {
                                    id = roll.id, name = roll.name,
                                    desc = roll.desc, mechanic = roll.mechanic,
                                }
                            end
                            -- randomAbyssAffixLimit：随机1种深渊词缀的生效上限（值从模板读取）
                            if tplCheck.randomAbyssAffixLimit then
                                local roll = GS.ABYSS_AFFIX_POOL[math.random(#GS.ABYSS_AFFIX_POOL)]
                                lastItem.abyssAffixLimitTarget = {
                                    id = roll.id, name = roll.name, mechanic = roll.mechanic,
                                }
                            end
                        end
                        -- "朱莉"的面纱：指定深渊词缀 + 随机主属性+3
                        if lastItem and btn.abyssAffixOverride then
                            local af = btn.abyssAffixOverride
                            lastItem.abyssAffix = {
                                id = af.id, name = af.name,
                                desc = af.desc, mechanic = af.mechanic,
                            }
                            local mainStats = {"str","wis","agi","con","foc","per","wil","luk","cha"}
                            local picked = mainStats[math.random(#mainStats)]
                            lastItem.gemEffect = { [picked] = 3 }
                        end
                        local tpl = GS.itemTemplates[btn.itemId]
                        local dropName = tpl and tpl.name or btn.itemId
                        if lastItem and lastItem.enchantment then
                            dropName = dropName .. " [附魔]"
                        end
                        if lastItem and lastItem.refineSlots and #lastItem.refineSlots > 0 then
                            dropName = dropName .. " [精炼]"
                        end
                        if lastItem and lastItem.gemSlots and #lastItem.gemSlots > 0 then
                            dropName = dropName .. " [宝石槽]"
                        end
                        if lastItem and lastItem.abyssAffix then
                            dropName = dropName .. " [词缀:" .. lastItem.abyssAffix.name .. "]"
                        end
                        print("[测试] 已发放: " .. dropName)
                    else
                        print("[测试] 背包已满: " .. (msg or ""))
                    end
                    break
                end
            end
        end
        return
    end

    -- 地图面板拖动结束
    if GS.mapDragging then
        GS.mapDragging = false

        local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
        local my = eventData["Y"]:GetInt() / GS.dpr / GS.S

        -- 没有拖动过 → 当作点击，查找命中的地图地点按钮
        if not GS.mapDragMoved then
            -- 精灵NPC按钮（优先于地点按钮）
            if GS.mapElfBtnRect and hitTest(mx, my, GS.mapElfBtnRect) then
                GS.mapDragging = false
                GS.selectedMapLocation = nil
                -- 条件检查：非下雨 + 上午6-12点
                local hour = BoardOverlay.getGameHour()
                if GS.isRaining or hour < 6 or hour >= 12 then
                    GS.elfNotFoundPopup = true
                    return
                end
                -- 标记是从地图直接进入（非随机遭遇），视频结束后返回地图
                GS._forestElfFromMap = true
                BoardOverlay.show("town", "clearwater", "垂雾森林")
                BoardOverlay.enterSubScene("forest_elf")
                return
            end

            -- 异世深渊按钮
            if GS.mapAbyssBtnRect and hitTest(mx, my, GS.mapAbyssBtnRect) then
                GS.mapDragging = false
                GS.selectedMapLocation = "abyss"
                GS.selectedMapStage = nil
                GS.mapStageScrollOffset = 0
                return
            end

            -- 无限塔按钮
            if GS.mapTowerBtnRect and hitTest(mx, my, GS.mapTowerBtnRect) then
                GS.mapDragging = false
                GS.selectedMapLocation = "tower"
                GS.selectedMapStage = nil
                GS.mapStageScrollOffset = 0
                return
            end

            -- 史莱姆国王大反击按钮
            if GS.mapSlimeRevengeBtnRect and hitTest(mx, my, GS.mapSlimeRevengeBtnRect) then
                GS.mapDragging = false
                GS.selectedMapLocation = "slime_king_revenge"
                GS.selectedMapStage = nil
                GS.mapStageScrollOffset = 0
                return
            end

            -- 迪哈塔大反击按钮
            if GS.mapDihataRevengeBtnRect and hitTest(mx, my, GS.mapDihataRevengeBtnRect) then
                GS.mapDragging = false
                GS.selectedMapLocation = "dihata_revenge"
                GS.selectedMapStage = nil
                GS.mapStageScrollOffset = 0
                return
            end

            -- 艾莉雅旅行任务按钮（优先于地点按钮）
            local hitQuest = false
            if GS.mapQuestBtnRects then
                for _, qBtn in ipairs(GS.mapQuestBtnRects) do
                    if hitTest(mx, my, qBtn) then
                        -- 关卡列表已打开时（含任务模式），屏蔽其他任务按钮
                        if GS.mapQuestStageMode or GS.selectedMapLocation then
                            hitQuest = true
                            break
                        end
                        -- 进入任务关卡选择模式
                        GS.selectedMapLocation = nil
                        GS.selectedMapStage = nil
                        GS.mapStageScrollOffset = 0
                        GS.mapQuestStageMode = {
                            questId   = qBtn.questId,
                            questName = qBtn.questName,
                            areaId    = qBtn.areaId,
                            areaName  = qBtn.areaName,
                            dialogue  = qBtn.dialogue,
                            locId     = qBtn.locId,
                            locName   = qBtn.locName,
                        }
                        hitQuest = true
                        break
                    end
                end
            end

            local hitAny = hitQuest
            if not hitQuest then
            for _, btn in ipairs(GS.mapBtnRects) do
                if hitTest(mx, my, btn) then
                    -- 关卡列表已打开时，屏蔽对其他区域的点击（防止误切换）
                    if GS.selectedMapLocation and GS.selectedMapLocation ~= btn.locId then
                        hitAny = true
                        break
                    end
                    if GS.mapQuestStageMode then
                        hitAny = true
                        break
                    end
                    if GS.selectedMapLocation ~= btn.locId then
                        GS.selectedMapStage = nil  -- 切换地点时重置关卡选择
                        GS.mapStageScrollOffset = 0  -- 重置滚动偏移
                        GS.mapStageScrollbarDragging = false
                        GS.mapStageTouchStartY = nil
                        GS.mapStageZone = "battle"  -- 重置分区
                    
                    end
                    GS.selectedMapLocation = btn.locId
                    hitAny = true
                    break
                end
            end
            end -- if not hitQuest
            if not hitAny and (GS.selectedMapLocation or GS.mapQuestStageMode) then
                GS.selectedMapLocation = nil
                GS.selectedMapStage = nil
                GS.mapStageScrollOffset = 0
                GS.mapStageScrollbarDragging = false
                GS.mapStageTouchStartY = nil
                GS.mapStageZone = "battle"
                GS.mapQuestStageMode = nil
            
            end
        end
        return
    end

    -- 购买数量滑动条拖动结束
    if GS.shopBuyQtySliderDragging then
        GS.shopBuyQtySliderDragging = false
        return
    end

    -- 仓库滚动条拖动结束
    if GS.warehouseScrollBarDragging then
        GS.warehouseScrollBarDragging = false
        return
    end

    -- 仓库区域拖动结束
    if GS.warehouseDragging then
        GS.warehouseDragging = false

        local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
        local my = eventData["Y"]:GetInt() / GS.dpr / GS.S

        -- 仓库物品拖拽放下
        if GS.itemDragActive and GS.dragWarehouseIdx then
            local srcItem = GS.warehouse[GS.dragWarehouseIdx]
            if srcItem then
                -- 检测落点：仓库格子
                local targetWhIdx = nil
                if GS.warehouseSlotAreas then
                    for idx, r in pairs(GS.warehouseSlotAreas) do
                        if hitTest(mx, my, r) then
                            targetWhIdx = idx
                            break
                        end
                    end
                end

                -- 检测落点：背包格子
                local targetBagIdx = nil
                if GS.inventorySlotAreas then
                    for idx, r in pairs(GS.inventorySlotAreas) do
                        if hitTest(mx, my, r) then
                            targetBagIdx = idx
                            break
                        end
                    end
                end

                -- 检测落点：取出按钮
                local hitWithdraw = false
                local wdRect = GS.warehouseBtnRects and GS.warehouseBtnRects["withdraw"]
                if wdRect and hitTest(mx, my, wdRect) then
                    hitWithdraw = true
                end

                if hitWithdraw then
                    -- 仓库 → 取出按钮：取出到背包
                    GS.withdrawFromWarehouse(GS.dragWarehouseIdx)
                elseif targetWhIdx and targetWhIdx ~= GS.dragWarehouseIdx then
                    -- 仓库 → 仓库：交换
                    GS.warehouse[GS.dragWarehouseIdx], GS.warehouse[targetWhIdx] =
                        GS.warehouse[targetWhIdx], GS.warehouse[GS.dragWarehouseIdx]
                elseif targetBagIdx then
                    -- 仓库 → 背包：交换
                    GS.warehouse[GS.dragWarehouseIdx], GS.inventory[targetBagIdx] =
                        GS.inventory[targetBagIdx], GS.warehouse[GS.dragWarehouseIdx]
                end
            end

            GS.itemDragActive = false
            GS.dragWarehouseIdx = nil
            GS.warehouseDragMoved = false
            return
        end

        -- 没有拖拽物品时的点击处理
        if not GS.warehouseDragMoved then
            if GS.warehouseSlotAreas then
                for idx, sr in pairs(GS.warehouseSlotAreas) do
                    if hitTest(mx, my, sr) then
                        local item = GS.warehouse[idx]
                        if GS.warehouseMultiSelect then
                            -- 多选模式：切换选中状态
                            if item then
                                if GS.warehouseSelected[idx] then
                                    GS.warehouseSelected[idx] = nil
                                else
                                    GS.warehouseSelected[idx] = true
                                end
                            end
                        else
                            -- 普通模式：显示tooltip
                            if item then
                                GS.tooltipItem = item
                                GS.tooltipSlotIdx = 0
                                GS.tooltipSource = "warehouse"
                                GS.tooltipEquipSlotId = nil
                                GS.tooltipPinned = true
                                GS.tooltipAnchorRect = sr
                            else
                                GS.closeTooltip()
                            end
                        end
                        break
                    end
                end
            end
        end
        return
    end

    -- 共享仓库物品拖拽释放
    if GS.itemDragActive and GS.dragSharedStorageIdx then
        local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
        local my = eventData["Y"]:GetInt() / GS.dpr / GS.S
        local srcItem = GS.sharedStorage[GS.dragSharedStorageIdx]
        if srcItem then
            -- 检测落点：共享仓库格子
            local targetSSIdx = nil
            if GS.sharedStorageSlotAreas then
                for idx, r in pairs(GS.sharedStorageSlotAreas) do
                    if hitTest(mx, my, r) then
                        targetSSIdx = idx
                        break
                    end
                end
            end

            -- 检测落点：背包格子
            local targetBagIdx = nil
            if GS.inventorySlotAreas then
                for idx, r in pairs(GS.inventorySlotAreas) do
                    if hitTest(mx, my, r) then
                        targetBagIdx = idx
                        break
                    end
                end
            end

            -- 检测落点：取出按钮
            local hitWithdraw = false
            local wdRect = GS.sharedStorageBtnRects and GS.sharedStorageBtnRects["withdraw"]
            if wdRect and hitTest(mx, my, wdRect) then
                hitWithdraw = true
            end

            if hitWithdraw then
                -- 共享仓库 → 取出按钮：取出到背包
                GS.retrieveFromSharedStorage(GS.dragSharedStorageIdx)
            elseif targetSSIdx and targetSSIdx ~= GS.dragSharedStorageIdx then
                -- 共享仓库内交换
                GS.sharedStorage[GS.dragSharedStorageIdx], GS.sharedStorage[targetSSIdx] =
                    GS.sharedStorage[targetSSIdx], GS.sharedStorage[GS.dragSharedStorageIdx]
                GS.autoSave.dirty = true
            elseif targetBagIdx then
                -- 共享仓库 → 背包：取出
                GS.retrieveFromSharedStorage(GS.dragSharedStorageIdx)
            end
        end

        GS.itemDragActive = false
        GS.dragSharedStorageIdx = nil
        return
    end

    -- 共享仓库格子点击（无拖拽时 → tooltip）
    if GS.dragSharedStorageIdx and not GS.itemDragActive then
        local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
        local my = eventData["Y"]:GetInt() / GS.dpr / GS.S
        if GS.sharedStorageSlotAreas then
            for idx, sr in pairs(GS.sharedStorageSlotAreas) do
                if hitTest(mx, my, sr) then
                    local item = GS.sharedStorage[idx]
                    if item then
                        GS.tooltipItem = item
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "shared_storage"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipPinned = true
                        GS.tooltipAnchorRect = sr
                    else
                        GS.closeTooltip()
                    end
                    break
                end
            end
        end
        GS.dragSharedStorageIdx = nil
        return
    end

    -- 兑换滚动条拖动结束
    if GS.exchangeScrollBarDragging then
        GS.exchangeScrollBarDragging = false
        return
    end

    -- 兑换列表拖动结束（未拖动 → 视为点击，处理兑换或显示物品详情）
    if GS.exchangeListDragging then
        GS.exchangeListDragging = false
        if not GS.exchangeListDragMoved then
            local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
            local my = eventData["Y"]:GetInt() / GS.dpr / GS.S
            local clip = GS.exchangeListClipRect
            if clip and hitTest(mx, my, clip) then
                for _, r in ipairs(GS.exchangeItemRects or {}) do
                    -- 兑换按钮点击 → 执行兑换
                    if hitTest(mx, my, r) then
                        local ticketCount = GS.countInventoryItem("gratitude_ticket")
                        -- 每日限购检查
                        local reward = GS.EXCHANGE_REWARDS[r.rewardIdx]
                        local dailyRemaining = reward and GS.getExchangeDailyRemaining(reward)
                        local dailyOk = (dailyRemaining == nil or dailyRemaining > 0)
                        if dailyRemaining == -1 then
                            GS.exchangeBuyMsg = { text = "服务器时间加载中，请稍后再试", timer = 2.0, color = {220, 160, 40} }
                        elseif ticketCount >= r.ticketCost and r.stock > 0 and dailyOk then
                            GS.exchangeBuyConfirmVisible = true
                            GS.exchangeBuyConfirmItem = {
                                rewardIdx = r.rewardIdx, name = r.name,
                                ticketCost = r.ticketCost, stock = r.stock,
                            }
                            GS.exchangeBuyQuantity = 1
                        elseif not dailyOk then
                            GS.exchangeBuyMsg = { text = "今日兑换次数已用完", timer = 1.5, color = {220, 60, 40} }
                        else
                            GS.exchangeBuyMsg = { text = "感恩礼券不足", timer = 1.5, color = {220, 60, 40} }
                        end
                        return
                    end
                    -- 行内其他区域点击 → 显示物品详情 tooltip
                    if r.rowX and hitTest(mx, my, { x = r.rowX, y = r.rowY, w = r.rowW, h = r.rowH }) then
                        if r.templateId then
                            local tpl = GS.itemTemplates[r.templateId]
                            if tpl then
                                GS.tooltipItem = tpl
                                GS.tooltipSlotIdx = 0
                                GS.tooltipSource = "exchange"
                                GS.tooltipEquipSlotId = nil
                                GS.tooltipPinned = true
                                GS.tooltipAnchorRect = { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }
                            end
                        else
                            -- 非物品类奖品（如金币），显示描述提示
                            GS.exchangeBuyMsg = { text = r.desc or r.name, timer = 2.0, color = {200, 180, 100} }
                        end
                        return
                    end
                end
            end
        end
        return
    end

    -- 深渊兑换列表拖动结束（未拖动 → 视为点击，处理兑换或显示物品详情）
    if GS.abyssExchangeListDragging then
        GS.abyssExchangeListDragging = false
        if not GS.abyssExchangeListDragMoved then
            local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
            local my = eventData["Y"]:GetInt() / GS.dpr / GS.S
            local clip = GS.abyssExchangeListClipRect
            if clip and hitTest(mx, my, clip) then
                for _, r in ipairs(GS.abyssExchangeItemRects or {}) do
                    -- 兑换按钮点击 → 执行兑换
                    if hitTest(mx, my, r) then
                        local ok, msg = GS.performAbyssExchange(r.itemIdx)
                        GS.abyssExchangeMsg = {
                            text  = msg,
                            timer = 2.0,
                            color = ok and { 140, 220, 140 } or { 220, 100, 80 },
                        }
                        return
                    end
                    -- 行内其他区域点击（tap）→ 显示详情 tooltip（pinned）
                    if r.rowX and hitTest(mx, my, { x = r.rowX, y = r.rowY, w = r.rowW, h = r.rowH }) then
                        if r.templateId and GS.itemTemplates and GS.itemTemplates[r.templateId] then
                            local tpl = GS.itemTemplates[r.templateId]
                            GS.tooltipItem = tpl
                            GS.tooltipSlotIdx = 0
                            GS.tooltipSource = "abyss_exchange"
                            GS.tooltipEquipSlotId = nil
                            GS.tooltipPinned = true
                            GS.tooltipPinnedPos = nil
                            GS.tooltipAnchorRect = { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }
                        else
                            -- 非物品类（如深渊积分），显示描述提示
                            GS.abyssExchangeMsg = { text = r.desc or r.name or "", timer = 2.0, color = {200, 180, 100} }
                        end
                        return
                    end
                end
            end
        end
        return
    end

    -- 商店滚动条拖动结束
    if GS.shopScrollBarDragging then
        GS.shopScrollBarDragging = false
        return
    end

    -- 商品列表拖动结束（未拖动 → 视为点击，处理购买/详情）
    if GS.shopListDragging then
        GS.shopListDragging = false
        if not GS.shopListDragMoved then
            local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
            local my = eventData["Y"]:GetInt() / GS.dpr / GS.S
            local clip = GS.shopListClipRect
            if hitTest(mx, my, clip) then
                for _, r in ipairs(GS.shopItemRects) do
                    -- 购买按钮
                    if hitTest(mx, my, r) then
                        local stock = r.stock or 0
                        if GS.gold >= r.price and stock > 0 then
                            GS.closeTooltip()
                            GS.shopBuyConfirmVisible = true
                            GS.shopBuyConfirmItem = {
                                templateId = r.templateId, price = r.price,
                                name = r.name, stock = stock,
                                shopItemRef = r.shopItemRef,
                            }
                            GS.shopBuyQuantity = 1
                        end
                        return
                    end
                    -- 图标点击 → 显示物品详情
                    if r.iconX and hitTest(mx, my, { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }) then
                        local tpl = GS.itemTemplates[r.templateId]
                        if tpl then
                            GS.tooltipItem = tpl
                            GS.tooltipSlotIdx = 0
                            GS.tooltipSource = "shop"
                            GS.tooltipEquipSlotId = nil
                            GS.tooltipPinned = true
                            GS.tooltipAnchorRect = { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }
                        end
                        return
                    end
                end
            end
        end
        return
    end

    -- 滚动条拖动结束
    if GS.invScrollBarDragging then
        GS.invScrollBarDragging = false
        return
    end

    -- 遗失物品拖拽结束
    if GS.dragLostItemIdx then
        local idx = GS.dragLostItemIdx
        local wasDragging = GS.lostItemDragActive

        GS.dragLostItemIdx = nil
        GS.lostItemDragActive = false

        if wasDragging and GS.lostItems[idx] then
            local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
            local my = eventData["Y"]:GetInt() / GS.dpr / GS.S

            -- 检测落点：背包格子或背包区域
            local hitBag = false
            if GS.inventorySlotAreas then
                for _, r in pairs(GS.inventorySlotAreas) do
                    if hitTest(mx, my, r) then
                        hitBag = true
                        break
                    end
                end
            end
            if not hitBag and GS.invClipRect then
                hitBag = hitTest(mx, my, GS.invClipRect)
            end

            if hitBag then
                local ok, msg = GS.withdrawFromLostItems(idx)
                if ok then
                    GS.shopBuyMsg = { text = "已取回物品", timer = 1.5, color = {60, 160, 60} }
                else
                    GS.shopBuyMsg = { text = msg, timer = 2.0, color = {220, 60, 40} }
                end
            end
        end
        -- 不 return，让后续逻辑继续处理
    end

    -- 背包拖动结束
    if GS.invDragging then
        GS.invDragging = false

        local mx = eventData["X"]:GetInt() / GS.dpr / GS.S
        local my = eventData["Y"]:GetInt() / GS.dpr / GS.S

        if GS.itemDragActive and (GS.dragSlotIdx or GS.dragEquipSlotId) then
            -- === 物品拖拽结束：判断来源和落点 ===

            -- 查找落点背包格子
            local targetBagIdx = nil
            if GS.inventorySlotAreas then
                for idx, r in pairs(GS.inventorySlotAreas) do
                    if hitTest(mx, my, r) then
                        targetBagIdx = idx
                        break
                    end
                end
            end

            -- 查找落点装备槽
            local targetEquipSlot = nil
            if GS.equipSlotAreas then
                for slotId, r in pairs(GS.equipSlotAreas) do
                    if hitTest(mx, my, r) then
                        targetEquipSlot = slotId
                        break
                    end
                end
            end

            -- 查找落点仓库格子
            local targetWhIdx = nil
            if GS.warehouseMode and GS.warehouseSlotAreas then
                for idx, r in pairs(GS.warehouseSlotAreas) do
                    if hitTest(mx, my, r) then
                        targetWhIdx = idx
                        break
                    end
                end
            end

            -- 背包拖到仓库：空格直接放入，非空格找最前空位
            if GS.warehouseMode and GS.dragSlotIdx then
                -- 判断是否落在仓库格子或仓库区域内
                local hitWarehouse = targetWhIdx ~= nil
                if not hitWarehouse and GS.warehouseClipRect then
                    local clip = GS.warehouseClipRect
                    if clip.w and clip.w > 0 and hitTest(mx, my, clip) then
                        hitWarehouse = true
                    end
                end
                if hitWarehouse then
                    local item = GS.inventory[GS.dragSlotIdx]
                    if item then
                        if targetWhIdx and not GS.warehouse[targetWhIdx] then
                            -- 目标格子为空：直接放入
                            GS.warehouse[targetWhIdx] = item
                            GS.inventory[GS.dragSlotIdx] = nil
                        elseif targetWhIdx and GS.warehouse[targetWhIdx] then
                            local target = GS.warehouse[targetWhIdx]
                            if item.stackable and target.stackable and item.templateId == target.templateId and target.quantity < GS.STACK_MAX then
                                -- 同类可堆叠：合并数量
                                local canAdd = GS.STACK_MAX - target.quantity
                                if canAdd >= item.quantity then
                                    target.quantity = target.quantity + item.quantity
                                    GS.inventory[GS.dragSlotIdx] = nil
                                else
                                    target.quantity = GS.STACK_MAX
                                    item.quantity = item.quantity - canAdd
                                end
                            else
                                -- 不可堆叠或不同物品：走通用存入逻辑
                                GS.storeToWarehouse(GS.dragSlotIdx)
                            end
                        else
                            -- 未命中格子：找最前空位（含堆叠）
                            GS.storeToWarehouse(GS.dragSlotIdx)
                        end
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 背包拖到共享仓库
            if GS.sharedStorageMode and GS.dragSlotIdx then
                -- 检测落点：共享仓库格子
                local targetSSIdx = nil
                if GS.sharedStorageSlotAreas then
                    for idx, r in pairs(GS.sharedStorageSlotAreas) do
                        if hitTest(mx, my, r) then
                            targetSSIdx = idx
                            break
                        end
                    end
                end
                -- 判断是否落在共享仓库任意格子区域内
                local hitSharedStorage = targetSSIdx ~= nil
                if not hitSharedStorage and GS.sharedStorageSlotAreas then
                    -- 检查是否落在面板区域（用第一和最后格子的范围判断）
                    local first = GS.sharedStorageSlotAreas[1]
                    local last = GS.sharedStorageSlotAreas[GS.SHARED_STORAGE_SLOTS]
                    if first and last then
                        local areaRect = { x = first.x, y = first.y, w = last.x + last.w - first.x, h = first.h }
                        if hitTest(mx, my, areaRect) then
                            hitSharedStorage = true
                        end
                    end
                end
                if hitSharedStorage then
                    local item = GS.inventory[GS.dragSlotIdx]
                    if item then
                        local canStore, reason = GS.canStoreInSharedStorage(item)
                        if not canStore then
                            GS.shopBuyMsg = { text = reason or "无法存入", timer = 2.0, color = {220, 60, 40} }
                        elseif targetSSIdx and not GS.sharedStorage[targetSSIdx] then
                            -- 目标格子为空：放入指定格位
                            GS.storeToSharedStorage(GS.dragSlotIdx, targetSSIdx)
                        else
                            -- 找最前空位
                            local stored = false
                            for si = 1, GS.SHARED_STORAGE_SLOTS do
                                if not GS.sharedStorage[si] then
                                    GS.storeToSharedStorage(GS.dragSlotIdx, si)
                                    stored = true
                                    break
                                end
                            end
                            if not stored then
                                GS.shopBuyMsg = { text = "共享仓库已满", timer = 2.0, color = {220, 60, 40} }
                            end
                        end
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在赠送放置槽上
            if GS.giftMode and GS.giftDropRect and not GS.giftResultText then
                local gr = GS.giftDropRect
                if hitTest(mx, my, gr) then
                    local dragItem = nil
                    local srcId = nil
                    -- 赠送只接受背包物品（不接受装备栏）
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcId = GS.dragSlotIdx
                    end
                    if dragItem then
                        -- noGift / 任务物品 / 特殊物品不允许赠送
                        local tpl = GS.itemTemplates[dragItem.templateId]
                        local cat = (tpl and tpl.category) or dragItem.category
                        if (tpl and tpl.noGift) or cat == "任务物品" or cat == "任务" or cat == "特殊" then
                            local rejectText = (cat == "任务物品" or cat == "任务") and "任务物品不可用于赠礼" or "该物品不可用于赠礼"
                            GS.giftRejectMsg = { text = rejectText, timer = 1.5 }
                            GS.itemDragActive = false
                            GS.dragSlotIdx = nil
                            GS.dragEquipSlotId = nil
                            GS.invDragMoved = false
                            GS.invDragging = false
                            return
                        end
                        -- 堆叠物品：拆出1个副本放到赠送槽，背包保留剩余
                        local copy = {}
                        for k, v in pairs(dragItem) do copy[k] = v end
                        copy.quantity = 1
                        if dragItem.quantity and dragItem.quantity > 1 then
                            dragItem.quantity = dragItem.quantity - 1
                        else
                            table.remove(GS.inventory, srcId)
                        end
                        GS.giftSlotItem = copy
                        GS.giftSlotSource = "bag"
                        GS.giftSlotSourceId = srcId
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在任务提交放置槽上
            if GS.questSubmitMode and GS.questSubmitDropRect then
                local qr = GS.questSubmitDropRect
                if hitTest(mx, my, qr) then
                    local dragItem = nil
                    local srcId = nil
                    -- 只接受背包物品
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcId = GS.dragSlotIdx
                    end
                    if dragItem then
                        -- 检查是否为任务所需物品
                        local def = GS.questSubmitDef
                        local accepted = false
                        if def and def.requireItemFilter then
                            -- 自定义过滤器（按品质/类别等动态判断）
                            local tpl = GS.itemTemplates and GS.itemTemplates[dragItem.templateId]
                            accepted = def.requireItemFilter(dragItem, tpl)
                        elseif def and def.requireItems then
                            for _, reqItem in ipairs(def.requireItems) do
                                if dragItem.templateId == reqItem.templateId then
                                    accepted = true
                                    break
                                end
                            end
                        end
                        if not accepted then
                            local rejectText = (def and def.rejectText) or "不是这个物品"
                            GS.questSubmitRejectMsg = { text = rejectText, timer = 1.5 }
                            GS.itemDragActive = false
                            GS.dragSlotIdx = nil
                            GS.dragEquipSlotId = nil
                            GS.invDragMoved = false
                            GS.invDragging = false
                            return
                        end
                        -- 根据任务需求拆出对应数量放到提交槽
                        local needCount = 1
                        if def and def.requireItems then
                            for _, reqItem in ipairs(def.requireItems) do
                                if dragItem.templateId == reqItem.templateId then
                                    needCount = reqItem.count or 1
                                    break
                                end
                            end
                        end
                        -- 先从拖拽的堆叠扣除
                        local dragHas = dragItem.quantity or 1
                        local fromDrag = math.min(needCount, dragHas)
                        if dragHas > fromDrag then
                            dragItem.quantity = dragHas - fromDrag
                        else
                            GS.inventory[srcId] = nil
                        end
                        -- 差额从背包其他同类堆叠中补足
                        local remaining = needCount - fromDrag
                        if remaining > 0 then
                            for si = 1, GS.bagSlots do
                                if remaining <= 0 then break end
                                local inv = GS.inventory[si]
                                if inv and si ~= srcId and inv.templateId == dragItem.templateId then
                                    local has = inv.quantity or 1
                                    if has <= remaining then
                                        remaining = remaining - has
                                        GS.inventory[si] = nil
                                    else
                                        inv.quantity = has - remaining
                                        remaining = 0
                                    end
                                end
                            end
                        end
                        -- 若槽位已有旧物品，先归还背包，防止覆盖导致物品丢失
                        if GS.questSubmitSlotItem then
                            local oldItem = GS.questSubmitSlotItem
                            local returned = false
                            for ri = 1, GS.bagSlots do
                                if not GS.inventory[ri] then
                                    GS.inventory[ri] = oldItem
                                    returned = true
                                    break
                                end
                            end
                            if not returned then
                                print("[QuestSubmit] 警告：背包已满，无法归还旧提交物品: " .. tostring(oldItem.templateId))
                            end
                            GS.questSubmitSlotItem = nil
                        end
                        local copy = {}
                        for k, v in pairs(dragItem) do copy[k] = v end
                        copy.quantity = needCount
                        GS.questSubmitSlotItem = copy
                        GS.questSubmitSlotSource = "bag"
                        GS.questSubmitSlotSourceId = srcId
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在修复放置槽上
            if GS.repairMode and GS.repairDropRect then
                local rr = GS.repairDropRect
                if hitTest(mx, my, rr) then
                    local dragItem = nil
                    local srcType = nil
                    local srcId = nil
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcType = "bag"
                        srcId = GS.dragSlotIdx
                    elseif GS.dragEquipSlotId then
                        dragItem = GS.equipment[GS.dragEquipSlotId]
                        srcType = "equip"
                        srcId = GS.dragEquipSlotId
                    end
                    if dragItem and dragItem.slot then
                        GS.repairSlotItem = dragItem
                        GS.repairSlotSource = srcType
                        GS.repairSlotSourceId = srcId
                        GS.repairResult = nil
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在镶嵌放置槽上（宝石镶嵌分页）
            if GS.socketMode and GS.socketTab == "socket" and GS.socketDropRect then
                local sr = GS.socketDropRect
                if hitTest(mx, my, sr) then
                    local dragItem = nil
                    local srcType = nil
                    local srcId = nil
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcType = "bag"
                        srcId = GS.dragSlotIdx
                    elseif GS.dragEquipSlotId then
                        dragItem = GS.equipment[GS.dragEquipSlotId]
                        srcType = "equip"
                        srcId = GS.dragEquipSlotId
                    end
                    if dragItem and dragItem.slot then
                        GS.socketEquipItem = dragItem
                        GS.socketEquipSource = srcType
                        GS.socketEquipSourceId = srcId
                        GS.socketSelectedGemSlot = nil
                        GS.socketSelectedGemBag = nil
                        GS.socketResult = nil
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在面纱重铸放置槽上
            if GS.socketMode and GS.socketTab == "reforge" and not GS.veilReforgeTime then
                local dragItem = nil
                local srcType = nil
                local srcId = nil
                if GS.dragSlotIdx then
                    dragItem = GS.inventory[GS.dragSlotIdx]
                    srcType = "bag"
                    srcId = GS.dragSlotIdx
                end
                if dragItem then
                    local tpl = GS.itemTemplates and GS.itemTemplates[dragItem.templateId]
                    -- 面纱槽
                    local vdr = GS.reforgeVeilDropRect
                    if vdr and hitTest(mx, my, vdr) then
                        if dragItem.templateId == "gem_rainbow_masterwork" then
                            GS.reforgeVeilItem = dragItem
                            GS.reforgeVeilSource = srcType
                            GS.reforgeVeilSourceId = srcId
                            GS.socketResult = nil
                        else
                            GS.socketResult = { success = false, msg = "只能放入\"朱莉\"的面纱", timer = 2.0 }
                        end
                        GS.itemDragActive = false
                        GS.dragSlotIdx = nil
                        GS.dragEquipSlotId = nil
                        GS.invDragMoved = false
                        GS.invDragging = false
                        return
                    end
                    -- 宝石槽
                    local gdr = GS.reforgeGemDropRect
                    if gdr and hitTest(mx, my, gdr) then
                        if tpl and tpl.gemEffect and tpl.rarity == "superior" then
                            GS.reforgeGemItem = dragItem
                            GS.reforgeGemSource = srcType
                            GS.reforgeGemSourceId = srcId
                            GS.socketResult = nil
                        else
                            GS.socketResult = { success = false, msg = "只能放入卓越品质的宝石", timer = 2.0 }
                        end
                        GS.itemDragActive = false
                        GS.dragSlotIdx = nil
                        GS.dragEquipSlotId = nil
                        GS.invDragMoved = false
                        GS.invDragging = false
                        return
                    end
                end
            end

            -- 检测是否落在附魔放置槽上
            if GS.enchantMode and GS.enchantDropRect then
                local er = GS.enchantDropRect
                if hitTest(mx, my, er) then
                    local dragItem = nil
                    local srcType = nil
                    local srcId = nil
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcType = "bag"
                        srcId = GS.dragSlotIdx
                    elseif GS.dragEquipSlotId then
                        dragItem = GS.equipment[GS.dragEquipSlotId]
                        srcType = "equip"
                        srcId = GS.dragEquipSlotId
                    end
                    if dragItem and dragItem.slot then
                        GS.enchantSlotItem = dragItem
                        GS.enchantSlotSource = srcType
                        GS.enchantSlotSourceId = srcId
                        GS.enchantResult = nil
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在委托加工放置槽上
            if GS.craftMode and GS.craftDropRect then
                local cr = GS.craftDropRect
                if hitTest(mx, my, cr) then
                    local dragItem = nil
                    local srcType = nil
                    local srcId = nil
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcType = "bag"
                        srcId = GS.dragSlotIdx
                    elseif GS.dragEquipSlotId then
                        dragItem = GS.equipment[GS.dragEquipSlotId]
                        srcType = "equip"
                        srcId = GS.dragEquipSlotId
                    end
                    if dragItem and dragItem.slot then
                        GS.craftSlotItem = dragItem
                        GS.craftSlotSource = srcType
                        GS.craftSlotSourceId = srcId
                        GS.craftEnhanceResult = nil
                        GS.craftRefineResult = nil
                        GS.craftRepairResult = nil
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在萃取双槽上
            if GS.craftMode and GS.craftTab == "extract" then
                local function tryExtractDrop(dropRect, setItem, setSource, setSourceId)
                    if dropRect and hitTest(mx, my, dropRect) then
                        local dragItem = nil
                        local srcType = nil
                        local srcId = nil
                        if GS.dragSlotIdx then
                            dragItem = GS.inventory[GS.dragSlotIdx]
                            srcType = "bag"
                            srcId = GS.dragSlotIdx
                        elseif GS.dragEquipSlotId then
                            dragItem = GS.equipment[GS.dragEquipSlotId]
                            srcType = "equip"
                            srcId = GS.dragEquipSlotId
                        end
                        if dragItem and dragItem.slot then
                            setItem(dragItem)
                            setSource(srcType)
                            setSourceId(srcId)
                            GS.craftExtractResult = nil
                        end
                        GS.itemDragActive = false
                        GS.dragSlotIdx = nil
                        GS.dragEquipSlotId = nil
                        GS.invDragMoved = false
                        GS.invDragging = false
                        return true
                    end
                    return false
                end
                if tryExtractDrop(GS.extractSourceDropRect,
                    function(v) GS.extractSourceItem = v end,
                    function(v) GS.extractSourceSource = v end,
                    function(v) GS.extractSourceSourceId = v end) then
                    return
                end
                if tryExtractDrop(GS.extractTargetDropRect,
                    function(v) GS.extractTargetItem = v end,
                    function(v) GS.extractTargetSource = v end,
                    function(v) GS.extractTargetSourceId = v end) then
                    return
                end
            end

            -- 检测是否落在精炼放置槽上
            if GS.refineMode and GS.refineDropRect then
                local rr = GS.refineDropRect
                if hitTest(mx, my, rr) then
                    local dragItem = nil
                    local srcType = nil
                    local srcId = nil
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcType = "bag"
                        srcId = GS.dragSlotIdx
                    elseif GS.dragEquipSlotId then
                        dragItem = GS.equipment[GS.dragEquipSlotId]
                        srcType = "equip"
                        srcId = GS.dragEquipSlotId
                    end
                    if dragItem and dragItem.slot then
                        GS.refineSlotItem = dragItem
                        GS.refineSlotSource = srcType
                        GS.refineSlotSourceId = srcId
                        GS.refineResult = nil
                    end
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在强化放置槽上
            if GS.enhanceMode and GS.enhanceDropRect then
                local er = GS.enhanceDropRect
                if hitTest(mx, my, er) then
                    -- 获取拖拽中的物品
                    local dragItem = nil
                    local srcType = nil   -- "bag" or "equip"
                    local srcId = nil
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        srcType = "bag"
                        srcId = GS.dragSlotIdx
                    elseif GS.dragEquipSlotId then
                        dragItem = GS.equipment[GS.dragEquipSlotId]
                        srcType = "equip"
                        srcId = GS.dragEquipSlotId
                    end
                    if dragItem and dragItem.slot then
                        -- 只有装备类物品才能放入强化槽
                        GS.enhanceSlotItem = dragItem
                        GS.enhanceSlotSource = srcType
                        GS.enhanceSlotSourceId = srcId
                        GS.enhanceResult = nil
                    end
                    -- 清除拖拽状态
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            -- 检测是否落在拆分按钮上
            local spr = GS.splitBtnRect
            if spr and spr.w and spr.w > 0 and hitTest(mx, my, spr) then
                local dragItem = nil
                local slotIdx = nil
                if GS.dragSlotIdx then
                    dragItem = GS.inventory[GS.dragSlotIdx]
                    slotIdx = GS.dragSlotIdx
                end
                if dragItem and slotIdx then
                    -- 检查是否可堆叠且数量 >= 2
                    if dragItem.stackable and (dragItem.quantity or 1) >= 2 then
                        -- 检查背包是否有空位
                        local hasEmpty = false
                        for si = 1, GS.bagSlots do
                            if not GS.inventory[si] then
                                hasEmpty = true
                                break
                            end
                        end
                        if hasEmpty then
                            GS.splitPopupVisible = true
                            GS.splitPopupItem = dragItem
                            GS.splitPopupSlotIdx = slotIdx
                            GS.splitPopupTotal = dragItem.quantity
                            GS.splitPopupValue = 1
                            GS.splitPopupSliderDragging = false
                            GS.closeTooltip()
                        else
                            GS.shopBuyMsg = { text = "背包已满，无法拆分", timer = 2.0, color = {220, 60, 40} }
                        end
                    else
                        GS.shopBuyMsg = { text = "该物品无法拆分", timer = 2.0, color = {220, 60, 40} }
                    end
                end
                -- 清除拖拽状态
                GS.itemDragActive = false
                GS.dragSlotIdx = nil
                GS.dragEquipSlotId = nil
                GS.invDragMoved = false
                GS.invDragging = false
                return
            end

            -- 检测是否落在销毁/存入按钮上
            local dr = GS.destroyBtnRect
            local hitDestroy = dr and dr.w and dr.w > 0 and hitTest(mx, my, dr)

            if hitDestroy then
                if GS.sharedStorageMode then
                    -- 共享仓库模式：拖到存入按钮上 → 直接存入共享仓库
                    if GS.dragSlotIdx then
                        local item = GS.inventory[GS.dragSlotIdx]
                        if item then
                            local canStore, reason = GS.canStoreInSharedStorage(item)
                            if not canStore then
                                GS.shopBuyMsg = { text = reason or "无法存入", timer = 2.0, color = {220, 60, 40} }
                            else
                                -- 找第一个空位
                                local stored = false
                                for si = 1, GS.SHARED_STORAGE_SLOTS do
                                    if not GS.sharedStorage[si] then
                                        GS.storeToSharedStorage(GS.dragSlotIdx, si)
                                        stored = true
                                        break
                                    end
                                end
                                if not stored then
                                    GS.shopBuyMsg = { text = "共享仓库已满", timer = 2.0, color = {220, 60, 40} }
                                end
                            end
                        end
                    end
                elseif GS.warehouseMode then
                    -- 仓库模式：拖到存入按钮上 → 直接存入仓库
                    if GS.dragSlotIdx then
                        GS.storeToWarehouse(GS.dragSlotIdx)
                    end
                else
                    -- 正常模式：拖到销毁/出售按钮上 → 弹出确认弹窗
                    local dragItem = nil
                    local slotIdx = nil
                    if GS.dragSlotIdx then
                        dragItem = GS.inventory[GS.dragSlotIdx]
                        slotIdx = GS.dragSlotIdx
                    end
                    if dragItem and slotIdx then
                        if dragItem.locked then
                            local action = GS.shopMode and "出售" or "销毁"
                            GS.shopBuyMsg = { text = "该物品已锁定，无法" .. action, timer = 2.0, color = {220, 60, 40} }
                        elseif GS.craftMode then
                            GS.shopBuyMsg = { text = "销毁前请关闭委托加工界面", timer = 2.0, color = {220, 60, 40} }
                        elseif GS.enchantMode then
                            GS.shopBuyMsg = { text = "销毁前请关闭委托镶嵌界面", timer = 2.0, color = {220, 60, 40} }
                        elseif GS.socketMode then
                            GS.shopBuyMsg = { text = "销毁前请关闭宝石镶嵌界面", timer = 2.0, color = {220, 60, 40} }
                        else
                            GS.destroyConfirmVisible = true
                            GS.destroyConfirmItem = dragItem
                            GS.destroyConfirmSlotIdx = slotIdx
                            GS.closeTooltip()
                        end
                    end
                end
                -- 清除拖拽状态
                GS.itemDragActive = false
                GS.dragSlotIdx = nil
                GS.dragEquipSlotId = nil
                GS.invDragMoved = false
                GS.invDragging = false
                return
            end

            -- 商店模式：拖到商品列表区域 → 触发出售确认
            if GS.shopMode and GS.dragSlotIdx and GS.shopListClipRect then
                local cr = GS.shopListClipRect
                if cr.w and cr.w > 0 and hitTest(mx, my, cr) then
                    local dragItem = GS.inventory[GS.dragSlotIdx]
                    if dragItem then
                        if dragItem.locked then
                            GS.shopBuyMsg = { text = "该物品已锁定，无法出售", timer = 2.0, color = {220, 60, 40} }
                        else
                            GS.destroyConfirmVisible = true
                            GS.destroyConfirmItem = dragItem
                            GS.destroyConfirmSlotIdx = GS.dragSlotIdx
                            GS.closeTooltip()
                        end
                    end
                    -- 清除拖拽状态
                    GS.itemDragActive = false
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.invDragMoved = false
                    GS.invDragging = false
                    return
                end
            end

            if GS.dragSlotIdx then
                -- 来源：背包格子
                local dragItem = GS.inventory[GS.dragSlotIdx]
                if targetEquipSlot and dragItem and dragItem.slot then
                    -- 非移动阶段禁止变更装备
                    if not GS.canChangeEquip() then
                        GS.shopBuyMsg = { text = "仅移动阶段可切换装备", timer = 2.0, color = {220, 60, 40} }
                        GS.dragSlotIdx = nil
                        GS.dragEquipSlotId = nil
                        GS.itemDragActive = false
                        return
                    end
                    -- 背包 → 装备槽：尝试装备
                    -- 戒指特殊：ring1 类型物品可拖到 ring1 或 ring2
                    local isRingItem = dragItem.slot == "ring1"
                    local isRingSlot = targetEquipSlot == "ring1" or targetEquipSlot == "ring2"
                    -- 等级限制检查
                    local levelOk = true
                    if dragItem.level and GS.player and GS.player.level < dragItem.level then
                        levelOk = false
                        GS.shopBuyMsg = { text = "等级不足（需要Lv." .. dragItem.level .. "）", timer = 2.0, color = {220, 60, 40} }
                    end
                    -- 匕首双持：匕首(slot=weapon_r)可拖到 weapon_l（仅刺客可双持）
                    local isDaggerToLeft = dragItem.weaponTag == "匕首" and dragItem.slot == "weapon_r" and targetEquipSlot == "weapon_l" and GS.currentClass == "assassin"
                    -- 非刺客不能把匕首拖到左手
                    if not levelOk then
                        -- 已提示等级不足
                    elseif dragItem.weaponTag == "匕首" and targetEquipSlot == "weapon_l" and GS.currentClass ~= "assassin" then
                        levelOk = false
                        GS.shopBuyMsg = { text = "仅限刺客可双持匕首", timer = 2.0, color = {220, 60, 40} }
                    end
                    -- 副手职业限制（CLASS_OFFHAND）
                    if levelOk and targetEquipSlot == "weapon_l" and dragItem.offhandTag then
                        if not GS.checkOffhand(dragItem.offhandTag) then
                            levelOk = false
                            GS.shopBuyMsg = { text = "当前职业无法装备" .. dragItem.offhandTag, timer = 2.0, color = {220, 60, 40} }
                        end
                    end
                    -- 右手武器栏职业武器类型限制
                    if levelOk and (targetEquipSlot == "weapon_r" or isDaggerToLeft) and dragItem.weaponTag then
                        local allowed = GS.CLASS_WEAPON_R and GS.CLASS_WEAPON_R[GS.currentClass]
                        if allowed and not allowed[dragItem.weaponTag] then
                            levelOk = false
                            GS.shopBuyMsg = { text = "当前职业无法装备" .. dragItem.weaponTag, timer = 2.0, color = {220, 60, 40} }
                        end
                    end
                    if levelOk and (dragItem.slot == targetEquipSlot or (isRingItem and isRingSlot) or isDaggerToLeft) then
                        -- 卓越装备生效唯一：同 templateId 的卓越装备不能重复装备
                        if dragItem.rarity == "superior" and dragItem.templateId then
                            for _, slotId in ipairs({"weapon_r","weapon_l","hat","shoulder","cloak","chest","gloves","pants","boots","necklace","belt","trinket","ring1","ring2"}) do
                                if slotId ~= targetEquipSlot then
                                    local existing = GS.equipment[slotId]
                                    if existing and existing.templateId == dragItem.templateId then
                                        levelOk = false
                                        GS.shopBuyMsg = { text = "同名卓越装备只能装备一件", timer = 2.0, color = {220, 60, 40} }
                                        break
                                    end
                                end
                            end
                        end
                        if levelOk then
                            -- 物品槽位与目标装备槽匹配，直接装备
                            local oldEquip = GS.equipment[targetEquipSlot]
                            GS.equipment[targetEquipSlot] = dragItem
                            GS.inventory[GS.dragSlotIdx] = oldEquip  -- 旧装备回原格
                            if GS.player then GS.recalcStats(GS.player) end
                            -- 猎犬数量相关装备变更 → 智能更新猎犬
                            local hcb1 = dragItem.extraEffects and dragItem.extraEffects.houndCountBonus
                            local hcb2 = oldEquip and oldEquip.extraEffects and oldEquip.extraEffects.houndCountBonus
                            if hcb1 or hcb2 then GS.updateHounds() end
                        end
                    elseif levelOk then
                        -- 槽位不匹配，使用 equipItem 的智能分配逻辑
                        GS.equipItem(GS.dragSlotIdx)
                    end
                elseif targetBagIdx and targetBagIdx ~= GS.dragSlotIdx then
                    -- 背包 → 背包：同类消耗品合并，否则交换
                    local srcItem = GS.inventory[GS.dragSlotIdx]
                    local dstItem = GS.inventory[targetBagIdx]
                    if srcItem and dstItem
                        and srcItem.stackable and dstItem.stackable
                        and srcItem.templateId == dstItem.templateId
                        and dstItem.quantity < GS.STACK_MAX then
                        -- 合并：将源物品数量填入目标至上限
                        local canAdd = GS.STACK_MAX - dstItem.quantity
                        local add = math.min(srcItem.quantity or 1, canAdd)
                        dstItem.quantity = dstItem.quantity + add
                        srcItem.quantity = (srcItem.quantity or 1) - add
                        if srcItem.quantity <= 0 then
                            GS.inventory[GS.dragSlotIdx] = nil
                        end
                    else
                        -- 普通交换
                        GS.inventory[GS.dragSlotIdx], GS.inventory[targetBagIdx] =
                            GS.inventory[targetBagIdx], GS.inventory[GS.dragSlotIdx]
                    end
                end

            elseif GS.dragEquipSlotId then
                -- 来源：装备槽
                local dragItem = GS.equipment[GS.dragEquipSlotId]
                -- 非移动阶段禁止变更装备（拖到背包=卸下，拖到其他装备槽=交换）
                if (targetBagIdx or targetEquipSlot) and not GS.canChangeEquip() then
                    GS.shopBuyMsg = { text = "仅移动阶段可切换装备", timer = 2.0, color = {220, 60, 40} }
                    GS.dragSlotIdx = nil
                    GS.dragEquipSlotId = nil
                    GS.itemDragActive = false
                    return
                end
                if targetBagIdx then
                    -- 装备槽 → 背包格子
                    local targetItem = GS.inventory[targetBagIdx]
                    if not targetItem then
                        -- 目标为空格，直接放入
                        GS.inventory[targetBagIdx] = dragItem
                        GS.equipment[GS.dragEquipSlotId] = nil
                        if GS.player then GS.recalcStats(GS.player) end
                        if dragItem.extraEffects and dragItem.extraEffects.houndCountBonus then GS.updateHounds() end
                    elseif targetItem.slot == GS.dragEquipSlotId
                        or (targetItem.slot == "ring1" and (GS.dragEquipSlotId == "ring1" or GS.dragEquipSlotId == "ring2")) then
                        -- 目标物品可以替换（槽位匹配，戒指可互换），交换
                        GS.equipment[GS.dragEquipSlotId] = targetItem
                        GS.inventory[targetBagIdx] = dragItem
                        if GS.player then GS.recalcStats(GS.player) end
                        local hcb1 = dragItem.extraEffects and dragItem.extraEffects.houndCountBonus
                        local hcb2 = targetItem.extraEffects and targetItem.extraEffects.houndCountBonus
                        if hcb1 or hcb2 then GS.updateHounds() end
                    else
                        -- 目标物品不能替换，放到第一个空格
                        local placed = false
                        for i = 1, GS.bagSlots do
                            if not GS.inventory[i] then
                                GS.inventory[i] = dragItem
                                GS.equipment[GS.dragEquipSlotId] = nil
                                if GS.player then GS.recalcStats(GS.player) end
                                if dragItem.extraEffects and dragItem.extraEffects.houndCountBonus then GS.updateHounds() end
                                placed = true
                                break
                            end
                        end
                        -- 背包满了则不卸下
                    end
                elseif targetEquipSlot and targetEquipSlot ~= GS.dragEquipSlotId then
                    -- 装备槽 → 装备槽：戒指槽互换 或 武器槽互换
                    local srcIsRing = GS.dragEquipSlotId == "ring1" or GS.dragEquipSlotId == "ring2"
                    local dstIsRing = targetEquipSlot == "ring1" or targetEquipSlot == "ring2"
                    local srcIsWeapon = GS.dragEquipSlotId == "weapon_l" or GS.dragEquipSlotId == "weapon_r"
                    local dstIsWeapon = targetEquipSlot == "weapon_l" or targetEquipSlot == "weapon_r"
                    if srcIsRing and dstIsRing then
                        GS.equipment[GS.dragEquipSlotId], GS.equipment[targetEquipSlot] =
                            GS.equipment[targetEquipSlot], GS.equipment[GS.dragEquipSlotId]
                        if GS.player then GS.recalcStats(GS.player) end
                    elseif srcIsWeapon and dstIsWeapon then
                        -- 武器槽互换：验证装备规则
                        local srcItem = GS.equipment[GS.dragEquipSlotId]
                        local dstItem = GS.equipment[targetEquipSlot]
                        local canSwap = true
                        local swapMsg = nil

                        -- 检查源物品放到目标槽是否合法
                        if srcItem then
                            if targetEquipSlot == "weapon_r" and srcItem.offhandTag then
                                -- 副手专属物品（盾牌/箭袋/法器）不能放到右手
                                canSwap = false
                                swapMsg = srcItem.offhandTag .. "只能装备在左手"
                            elseif targetEquipSlot == "weapon_r" and srcItem.weaponTag then
                                -- 放到右手：检查职业武器类型限制
                                local allowed = GS.CLASS_WEAPON_R and GS.CLASS_WEAPON_R[GS.currentClass]
                                if allowed and not allowed[srcItem.weaponTag] then
                                    canSwap = false
                                    swapMsg = "当前职业无法在右手装备" .. srcItem.weaponTag
                                end
                            elseif targetEquipSlot == "weapon_l" and srcItem.offhandTag then
                                -- 放到左手：检查副手职业限制
                                if not GS.checkOffhand(srcItem.offhandTag) then
                                    canSwap = false
                                    swapMsg = "当前职业无法装备" .. srcItem.offhandTag
                                end
                            elseif targetEquipSlot == "weapon_l" and srcItem.weaponTag == "匕首" then
                                -- 匕首拖到左手：仅刺客可双持
                                if GS.currentClass ~= "assassin" then
                                    canSwap = false
                                    swapMsg = "仅限刺客可双持匕首"
                                end
                            end
                        end

                        -- 检查目标物品放到源槽是否合法
                        if canSwap and dstItem then
                            if GS.dragEquipSlotId == "weapon_r" and dstItem.offhandTag then
                                -- 副手专属物品不能放到右手
                                canSwap = false
                                swapMsg = dstItem.offhandTag .. "只能装备在左手"
                            elseif GS.dragEquipSlotId == "weapon_r" and dstItem.weaponTag then
                                local allowed = GS.CLASS_WEAPON_R and GS.CLASS_WEAPON_R[GS.currentClass]
                                if allowed and not allowed[dstItem.weaponTag] then
                                    canSwap = false
                                    swapMsg = "当前职业无法在右手装备" .. dstItem.weaponTag
                                end
                            elseif GS.dragEquipSlotId == "weapon_l" and dstItem.offhandTag then
                                if not GS.checkOffhand(dstItem.offhandTag) then
                                    canSwap = false
                                    swapMsg = "当前职业无法装备" .. dstItem.offhandTag
                                end
                            elseif GS.dragEquipSlotId == "weapon_l" and dstItem.weaponTag == "匕首" then
                                if GS.currentClass ~= "assassin" then
                                    canSwap = false
                                    swapMsg = "仅限刺客可双持匕首"
                                end
                            end
                        end

                        -- 弓+箭袋互斥检查
                        if canSwap then
                            local newR = (targetEquipSlot == "weapon_r") and srcItem or dstItem
                            local newL = (targetEquipSlot == "weapon_l") and srcItem or dstItem
                            if newR and newR.weaponTag == "弓" and newL and newL.category ~= "箭袋" then
                                canSwap = false
                                swapMsg = "装备弓时左手只能装备箭袋"
                            end
                        end

                        if canSwap then
                            GS.equipment[GS.dragEquipSlotId], GS.equipment[targetEquipSlot] =
                                GS.equipment[targetEquipSlot], GS.equipment[GS.dragEquipSlotId]
                            if GS.player then GS.recalcStats(GS.player) end
                            -- 武器变更时更新猎犬
                            GS.spawnHound()
                        elseif swapMsg then
                            GS.shopBuyMsg = { text = swapMsg, timer = 2.0, color = {220, 60, 40} }
                        end
                    end
                else
                    -- 拖到空白区域（背包区域内但非格子上），卸下到第一个空格
                    if GS.invClipRect then
                        local cr = GS.invClipRect
                        if hitTest(mx, my, cr) then
                            GS.unequipItem(GS.dragEquipSlotId)
                        end
                    end
                end
            end

        elseif not GS.invDragMoved and not GS.shopBuyConfirmVisible then
            -- 没有实质移动，当作点击处理（购买弹窗打开时屏蔽）
            if GS.dragEquipSlotId then
                -- 点击装备槽：显示tooltip
                local equipped = GS.equipment[GS.dragEquipSlotId]
                if equipped then
                    GS.tooltipItem = equipped
                    GS.tooltipSlotIdx = 0
                    GS.tooltipSource = "equipment"
                    GS.tooltipEquipSlotId = GS.dragEquipSlotId
                    GS.tooltipPinned = true
                end
            else
                M.handleInventoryClick(mx, my)
            end
        end

        GS.dragSlotIdx = nil
        GS.dragEquipSlotId = nil
        GS.itemDragActive = false
    end
end

-- ====================================================================
-- 背包格子点击
-- ====================================================================
function M.handleInventoryClick(mx, my)
    if not GS.inventorySlotAreas then return end
    for idx, r in pairs(GS.inventorySlotAreas) do
        if hitTest(mx, my, r) then
            local item = GS.inventory[idx]
            if GS.invMultiSelect then
                -- 多选模式：切换选中状态（锁定物品不可选中）
                if item and not item.locked then
                    if GS.invSelected[idx] then
                        GS.invSelected[idx] = nil
                    else
                        GS.invSelected[idx] = true
                    end
                end
            else
                if item then
                    -- 点击物品：锁定显示悬停面板
                    GS.tooltipItem = item
                    GS.tooltipSlotIdx = idx
                    GS.tooltipPinned = true
                else
                    GS.closeTooltip()
                end
            end
            return
        end
    end
    if not GS.invMultiSelect then
        GS.closeTooltip()
    end
end

-- ====================================================================
-- 键盘事件
-- ====================================================================
function M.handleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- 街头睡觉中：屏蔽所有操作
    if GS.streetSleepActive then return end

    -- 息屏挂机中：屏蔽所有按键
    if GS.screenOffMode then return end

    -- 改名输入模式：处理退格键、回车和取消
    local ri = GS.renameInput
    if ri and ri.active then
        if key == KEY_ESCAPE then
            ri.active = false
            GS.renameInput = nil
            input:SetScreenKeyboardVisible(false)
        elseif key == KEY_BACKSPACE then
            if not ri.imeComposing then
                local text = ri.text or ""
                if #text > 0 then
                    local len = utf8.len(text) or 0
                    if len > 1 then
                        local byteOffset = utf8.offset(text, len)
                        ri.text = text:sub(1, byteOffset - 1)
                    else
                        ri.text = ""
                    end
                end
            end
        elseif key == KEY_RETURN or key == KEY_KP_ENTER then
            if not ri.imeComposing then
                local txt = ri.text or ""
                if #txt > 0 then
                    GS.charName = txt
                    ri.active = false
                    GS.renameInput = nil
                    input:SetScreenKeyboardVisible(false)
                    GS.triggerAutoSave()
                    GS.shopBuyMsg = { text = "姓名已修改为: " .. txt, timer = 2.5, color = {140, 220, 100} }
                    print("[Input] Rename confirmed via Enter: " .. txt)
                end
            end
        end
        return  -- 改名输入模式下屏蔽其他按键
    end

    -- 兑换码输入模式：处理退格键、回车和取消
    local rci = GS.redeemCodeInput
    if rci and rci.active then
        if key == KEY_ESCAPE then
            rci.active = false
            input:SetScreenKeyboardVisible(false)
        elseif key == KEY_BACKSPACE then
            if not rci.imeComposing then
                local text = rci.text or ""
                if #text > 0 then
                    local len = utf8.len(text) or 0
                    if len > 1 then
                        local byteOffset = utf8.offset(text, len)
                        rci.text = text:sub(1, byteOffset - 1)
                    else
                        rci.text = ""
                    end
                end
            end
        elseif key == KEY_RETURN or key == KEY_KP_ENTER then
            if not rci.imeComposing then
                local code = rci.text or ""
                if #code > 0 then
                    rci.active = false
                    input:SetScreenKeyboardVisible(false)
                    processRedeemCode(code)
                end
            end
        end
        return  -- 兑换码输入模式下屏蔽其他按键
    end

    -- 爱称输入模式：处理退格键、回车和取消
    local pni = GS.petNameInput
    if pni and pni.active then
        if key == KEY_ESCAPE then
            pni.cancelled = true
        elseif key == KEY_BACKSPACE then
            if not pni.imeComposing then
                local text = pni.text or ""
                if #text > 0 then
                    local len = utf8.len(text) or 0
                    if len > 1 then
                        local byteOffset = utf8.offset(text, len)
                        pni.text = text:sub(1, byteOffset - 1)
                    else
                        pni.text = ""
                    end
                end
            end
        elseif key == KEY_RETURN or key == KEY_KP_ENTER then
            -- IME 组合期间 Enter 用于确认候选字，不触发输入框确认
            if not pni.imeComposing then
                local txt = pni.text or ""
                if #txt > 0 then
                    pni.confirmed = true
                    print("[Input] Pet name input confirmed via Enter: " .. txt)
                end
            end
        end
        return  -- 爱称输入模式下屏蔽其他按键
    end

    -- 名字输入模式：处理退格键
    local ni = GS.eventNameInput
    if ni and ni.active then
        if key == KEY_BACKSPACE then
            local text = ni.text or ""
            if #text > 0 then
                -- 删除最后一个 UTF-8 字符
                local len = utf8.len(text) or 0
                if len > 1 then
                    local byteOffset = utf8.offset(text, len)
                    ni.text = text:sub(1, byteOffset - 1)
                else
                    ni.text = ""
                end
            end
        elseif key == KEY_RETURN or key == KEY_KP_ENTER then
            local txt = ni.text or ""
            if #txt > 0 then
                ni.confirmed = true
                input:SetScreenKeyboardVisible(false)
                print("[Input] Name input confirmed via Enter: " .. txt)
            end
        end
        return  -- 名字输入模式下屏蔽其他按键
    end

    -- 弹窗打开时，Escape 关闭弹窗，其他按键屏蔽
    if GS.destroyConfirmVisible then
        if key == KEY_ESCAPE then
            GS.destroyConfirmVisible = false
            GS.destroyConfirmItem = nil
            GS.destroyConfirmSlotIdx = nil
            GS.destroyConfirmBatch = false
        end
        return
    end

    if GS.splitPopupVisible then
        if key == KEY_ESCAPE then
            GS.splitPopupVisible = false
            GS.splitPopupItem = nil
            GS.splitPopupSlotIdx = nil
            GS.splitPopupValue = 1
        end
        return
    end

    if GS.abyssConfirmVisible then
        if key == KEY_ESCAPE then
            GS.abyssConfirmVisible = false
            GS.abyssConfirmStageData = nil
        end
        return
    end

    -- 技能装备弹窗：Escape 关闭
    if GS.skillEquipPopupVisible then
        if key == KEY_ESCAPE then
            GS.skillEquipPopupVisible = false
            GS.skillEquipPopupSlot = nil
        end
        return
    end

    -- 行动菜单：技能子菜单 Escape 关闭
    if GS.actionSkillSubVisible then
        if key == KEY_ESCAPE then
            GS.actionSkillSubVisible = false
            GS.actionSkillSubRects = {}
            GS.actionSkillSubRect = nil
        end
        return
    end

    -- 行动菜单：主菜单 Escape → 撤销移动
    if GS.actionMenuVisible then
        if key == KEY_ESCAPE then
            if GS.mageActionTaken then
                -- 已行动，撤销移动禁用，ESC不响应
            else
                if GS.selectedUnit and GS.actionPreMoveX then
                    Command.recordUndoMove()
                    GS.selectedUnit.x = GS.actionPreMoveX
                    GS.selectedUnit.y = GS.actionPreMoveY
                    GS.turnPhase = GS.PHASE_MOVE
                    GS.movableCells, GS.movableParents = GS.getMovableCells(GS.selectedUnit)
                    GS.attackableCells = {}
                    -- 地狱踏：撤销移动时清除本次放置的燃烧地面
                    if GS._hellStompPlaced then
                        for _, p in ipairs(GS._hellStompPlaced) do
                            for j = #GS.burningGrounds, 1, -1 do
                                local bg = GS.burningGrounds[j]
                                if bg.x == p.x and bg.y == p.y and bg.hellStomp then
                                    table.remove(GS.burningGrounds, j)
                                    break
                                end
                            end
                        end
                        GS._hellStompPlaced = nil
                    end
                end
                GS.closeActionMenu()
            end
        end
        return
    end

    if GS.gameState == GS.STATE_PLAYER then
        if key == KEY_E then
            Combat.endPlayerTurn()
        end
    end

    if GS.gameState == GS.STATE_SELECT then
        if key == KEY_ESCAPE then
            if GS.actionChoice then
                -- 正在选择攻击/技能目标，取消选择回到行动菜单
                GS.actionChoice = nil
                GS.actionChosenSkillId = nil
                GS.groundTargetCells = nil
                GS.iceWallStartX = nil
                GS.iceWallStartY = nil
                GS.iceWallPreview = nil
                GS.actionMenuVisible = true
                if GS.selectedUnit then
                    GS.attackableCells = GS.getAttackableCells(GS.selectedUnit, GS.selectedUnit.x, GS.selectedUnit.y)
                end
            else
                GS.closeActionMenu()
                GS.selectedUnit = nil
                GS.movableCells = {}
                GS.attackableCells = {}
                GS.gameState = GS.STATE_PLAYER
            end
        end
        if key == KEY_E then
            GS.closeActionMenu()
            GS.selectedUnit = nil
            GS.movableCells = {}
            GS.attackableCells = {}
            Combat.endPlayerTurn()
        end
    end
end

-- ====================================================================
-- 音量滑块拖拽更新（每帧调用）
-- ====================================================================
function M.updateSliderDrag()
    -- 长按加点：持续加属性点
    if statHoldKey and GS.player and GS.player.statPoints and GS.player.statPoints > 0 then
        local dt = GS.dt or 0
        statHoldTimer = statHoldTimer + dt
        if statHoldTimer >= STAT_HOLD_DELAY then
            statHoldInterval = statHoldInterval + dt
            while statHoldInterval >= STAT_HOLD_RATE do
                statHoldInterval = statHoldInterval - STAT_HOLD_RATE
                local curVal = GS.player.stats[statHoldKey] or 0
                if curVal >= 100 or GS.player.statPoints <= 0 then
                    statHoldKey = nil
                    break
                end
                GS.player.stats[statHoldKey] = curVal + 1
                GS.player.statPoints = GS.player.statPoints - 1
                GS.recalcStats(GS.player)
            end
        end
    else
        statHoldKey = nil
    end

    -- 长按制作：持续锻造/炼金/烹饪
    if craftHoldType and craftHoldIdx then
        local dt = GS.dt or 0
        craftHoldTimer = craftHoldTimer + dt
        if craftHoldTimer >= CRAFT_HOLD_DELAY then
            craftHoldInterval = craftHoldInterval + dt
            while craftHoldInterval >= CRAFT_HOLD_RATE do
                craftHoldInterval = craftHoldInterval - CRAFT_HOLD_RATE
                local ok, msg
                if craftHoldType == "forge" then
                    ok, msg = GS.doForge(craftHoldIdx)
                    GS.forgeResult = { success = ok, msg = msg, timer = 2.0 }
                elseif craftHoldType == "alchemy" then
                    ok, msg = GS.doAlchemy(craftHoldIdx)
                    GS.alchemyResult = { success = ok, msg = msg, timer = 2.0 }
                elseif craftHoldType == "cooking" then
                    ok, msg = GS.doCooking(craftHoldIdx)
                    GS.cookingResult = { success = ok, msg = msg, timer = 2.0 }
                end
                if not ok then
                    craftHoldType = nil
                    break
                end
            end
        end
    else
        craftHoldType = nil
    end

    -- 音量滑块拖动
    if GS.volumeSliderDragging then
        local mx = input:GetMousePosition().x / GS.dpr / GS.S
        local trackX, _, trackW, _ = GS.getSliderTrackRect()
        GS.masterVolume = math.max(0, math.min(1, (mx - trackX) / trackW))
    end

    -- 角色属性汇总滚动
    if GS.charStatDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.charStatDragStartY - my
        local maxScroll = math.max(0, (GS.charStatContentH or 0) - (GS.charStatVisibleH or 1))
        GS.charStatScrollY = math.max(0, math.min(maxScroll, (GS.charStatDragStartScroll or 0) + delta))
    end

    -- BUFF总结面板滚动
    if GS.buffSummaryDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.buffSummaryDragStartY - my
        local maxScroll = GS.buffSummaryMaxScroll or 0
        GS.buffSummaryScrollY = math.max(0, math.min(maxScroll, (GS.buffSummaryDragStartScroll or 0) + delta))
    end

    -- 怪物BUFF面板滚动
    if GS.monsterBuffDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.monsterBuffDragStartY - my
        local maxScroll = GS.monsterBuffMaxScroll or 0
        GS.monsterBuffScrollY = math.max(0, math.min(maxScroll, (GS.monsterBuffDragStartScroll or 0) + delta))
    end

    -- 共享仓库日志面板滚动
    if GS.sharedStorageLogDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local rowH = GS.sharedStorageLogRowH or 20
        local deltaRows = math.floor((GS.sharedStorageLogDragStartY - my) / rowH + 0.5)
        local total = GS.sharedStorageLogLines and #GS.sharedStorageLogLines or 0
        local visRows = GS.sharedStorageLogVisibleRows or 10
        local maxScroll = math.max(0, total - visRows)
        GS.sharedStorageLogScroll = math.max(0, math.min(maxScroll, (GS.sharedStorageLogDragStartScroll or 0) + deltaRows))
    end

    -- 史莱姆奖励面板滚动
    if GS._slimeRewardDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS._slimeRewardDragStartY - my
        local maxScroll = GS._slimeRewardMaxScroll or 0
        GS.slimeRevengeRewardScroll = math.max(0, math.min(maxScroll, (GS._slimeRewardDragStartScroll or 0) + delta))
    end

    -- 史莱姆排名面板滚动
    if GS._slimeRankDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS._slimeRankDragStartY - my
        local maxScroll = GS._slimeRankMaxScroll or 0
        GS.slimeRevengeRankScroll = math.max(0, math.min(maxScroll, (GS._slimeRankDragStartScroll or 0) + delta))
    end

    -- 迪哈塔奖励面板滚动
    if GS._dihataRewardDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS._dihataRewardDragStartY - my
        local maxScroll = GS._dihataRewardMaxScroll or 0
        GS.dihataRevengeRewardScroll = math.max(0, math.min(maxScroll, (GS._dihataRewardDragStartScroll or 0) + delta))
    end

    -- 迪哈塔排名面板滚动
    if GS._dihataRankDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS._dihataRankDragStartY - my
        local maxScroll = GS._dihataRankMaxScroll or 0
        GS.dihataRevengeRankScroll = math.max(0, math.min(maxScroll, (GS._dihataRankDragStartScroll or 0) + delta))
    end

    -- 日志面板滚动
    if GS.journalDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.journalDragStartY - my
        local maxScroll = math.max(0, (GS.journalContentH or 0) - (GS.journalVisibleH or 1))
        GS.journalScrollY = math.max(0, math.min(maxScroll, (GS.journalDragStartScroll or 0) + delta))
    end

    -- 购买数量滑动条拖动
    if GS.shopBuyQtySliderDragging then
        local mx = input:GetMousePosition().x / GS.dpr / GS.S
        local sr = GS.shopBuyQtySliderRect
        if sr then
            local ratio = math.max(0, math.min(1, (mx - sr.trackX) / sr.trackW))
            local maxQty = sr.maxQty or 1
            local newQty = math.floor(ratio * (maxQty - 1) + 1.5)
            newQty = math.max(1, math.min(maxQty, newQty))
            GS.shopBuyQuantity = newQty
        end
    end

    -- 拆分数量滑动条拖动
    if GS.splitPopupSliderDragging then
        local mx = input:GetMousePosition().x / GS.dpr / GS.S
        local sr = GS.splitPopupSliderRect
        if sr then
            local ratio = math.max(0, math.min(1, (mx - sr.trackX) / sr.trackW))
            local maxQty = sr.maxQty or 1
            local newQty = math.floor(ratio * (maxQty - 1) + 1.5)
            newQty = math.max(1, math.min(maxQty, newQty))
            GS.splitPopupValue = newQty
        end
    end

    -- 兑换滚动条拖动
    if GS.exchangeScrollBarDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local track = GS.exchangeScrollBarTrack
        if track then
            local maxScroll = math.max(0, (GS.exchangeContentH or 0) - (GS.exchangeVisibleH or 1))
            local barH = math.max(20, track.h * ((GS.exchangeVisibleH or 1) / math.max(1, GS.exchangeContentH or 1)))
            local trackRange = track.h - barH
            if trackRange > 0 then
                local deltaPixel = my - GS.exchangeScrollBarDragStartY
                local scrollDelta = (deltaPixel / trackRange) * maxScroll
                GS.exchangeScrollY = math.max(0, math.min(maxScroll, GS.exchangeScrollBarDragStartScroll + scrollDelta))
            end
        end
    end

    -- 兑换列表拖动滚动
    if GS.exchangeListDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.exchangeListDragStartY - my
        if math.abs(delta) > 3 then
            GS.exchangeListDragMoved = true
        end
        local maxScroll = math.max(0, (GS.exchangeContentH or 0) - (GS.exchangeVisibleH or 1))
        GS.exchangeScrollY = math.max(0, math.min(maxScroll, GS.exchangeListDragStartScroll + delta))
    end

    -- 深渊兑换列表拖动滚动
    if GS.abyssExchangeListDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.abyssExchangeListDragStartY - my
        if math.abs(delta) > 3 then
            GS.abyssExchangeListDragMoved = true
        end
        local maxScroll = math.max(0, (GS.abyssExchangeContentH or 0) - (GS.abyssExchangeVisibleH or 1))
        GS.abyssExchangeScrollY = math.max(0, math.min(maxScroll, GS.abyssExchangeListDragStartScroll + delta))
    end

    -- 商店滚动条拖动
    if GS.shopScrollBarDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local track = GS.shopScrollBarTrack
        if track then
            local maxScroll = math.max(0, (GS.shopContentH or 0) - (GS.shopVisibleH or 1))
            local barH = math.max(20, track.h * ((GS.shopVisibleH or 1) / math.max(1, GS.shopContentH or 1)))
            local trackRange = track.h - barH
            if trackRange > 0 then
                local deltaPixel = my - GS.shopScrollBarDragStartY
                local scrollDelta = (deltaPixel / trackRange) * maxScroll
                GS.shopScrollY = math.max(0, math.min(maxScroll, GS.shopScrollBarDragStartScroll + scrollDelta))
            end
        end
    end

    -- 商品列表拖动滚动
    if GS.shopListDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.shopListDragStartY - my
        if math.abs(delta) > 3 then
            GS.shopListDragMoved = true
        end
        local maxScroll = math.max(0, (GS.shopContentH or 0) - (GS.shopVisibleH or 1))
        GS.shopScrollY = math.max(0, math.min(maxScroll, GS.shopListDragStartScroll + delta))
    end

    -- 仓库滚动条拖动
    if GS.warehouseScrollBarDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local track = GS.warehouseScrollBarTrack
        if track then
            local maxScroll = math.max(0, (GS.warehouseContentH or 0) - (GS.warehouseVisibleH or 1))
            local barH = math.max(20, track.h * ((GS.warehouseVisibleH or 1) / math.max(1, GS.warehouseContentH or 1)))
            local trackRange = track.h - barH
            if trackRange > 0 then
                local deltaPixel = my - GS.warehouseScrollBarDragStartY
                local scrollDelta = (deltaPixel / trackRange) * maxScroll
                GS.warehouseScrollY = math.max(0, math.min(maxScroll, GS.warehouseScrollBarDragStartScroll + scrollDelta))
            end
        end
    end

    -- 仓库区域拖动滚动 & 物品拖拽
    if GS.warehouseDragging then
        local pos = input:GetMousePosition()
        local mx = pos.x / GS.dpr / GS.S
        local my = pos.y / GS.dpr / GS.S

        -- 判断是滚动还是物品拖拽
        if GS.dragWarehouseIdx and not GS.itemDragActive then
            local dx = mx - (GS.itemDragStartX or mx)
            local dy = my - (GS.itemDragStartY or my)
            if dx * dx + dy * dy > 6 * 6 then
                GS.itemDragActive = true
                GS.closeTooltip()
            end
        end

        if GS.itemDragActive and GS.dragWarehouseIdx then
            -- 物品拖拽模式：更新鼠标坐标
            GS.dragOffsetX = mx
            GS.dragOffsetY = my
        elseif not GS.dragWarehouseIdx then
            -- 纯滚动模式
            local delta = GS.warehouseDragStartY - my
            if math.abs(delta) > 3 then
                GS.warehouseDragMoved = true
            end
            local maxScroll = math.max(0, (GS.warehouseContentH or 0) - (GS.warehouseVisibleH or 1))
            GS.warehouseScrollY = math.max(0, math.min(maxScroll, GS.warehouseDragStartScroll + delta))
        end
    end

    -- 共享仓库物品拖拽移动检测
    if GS.dragSharedStorageIdx and not GS.itemDragActive then
        local pos = input:GetMousePosition()
        local mx = pos.x / GS.dpr / GS.S
        local my = pos.y / GS.dpr / GS.S
        local dx = mx - (GS.itemDragStartX or mx)
        local dy = my - (GS.itemDragStartY or my)
        if dx * dx + dy * dy > 6 * 6 then
            GS.itemDragActive = true
            GS.closeTooltip()
        end
    end
    if GS.itemDragActive and GS.dragSharedStorageIdx then
        local pos = input:GetMousePosition()
        GS.dragOffsetX = pos.x / GS.dpr / GS.S
        GS.dragOffsetY = pos.y / GS.dpr / GS.S
    end

    -- 背包滚动条拖动
    if GS.invScrollBarDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local track = GS.invScrollBarTrack
        if track then
            local maxScroll = math.max(0, GS.invContentH - GS.invVisibleH)
            local barH = math.max(20, track.h * (GS.invVisibleH / GS.invContentH))
            local trackRange = track.h - barH
            if trackRange > 0 then
                local deltaPixel = my - GS.invScrollBarDragStartY
                local scrollDelta = (deltaPixel / trackRange) * maxScroll
                GS.invScrollY = math.max(0, math.min(maxScroll, GS.invScrollBarDragStartScroll + scrollDelta))
            end
        end
    end

    -- 测试关卡面板拖动
    if GS.testStageDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.testStageDragStartY - my
        if math.abs(delta) > 3 then
            GS.testStageDragMoved = true
        end
        local totalStages = #GS.MONSTER_ORDER  -- 只显示怪物测试关卡
        local contentH = totalStages * (26 + 3) + 12
        local r = GS.testStagePanelRect
        local clipH = r and (r.h - 12) or 200
        local maxScroll = math.max(0, contentH - clipH)
        GS.testStageScrollY = math.max(0, math.min(maxScroll, GS.testStageDragStartScroll + delta))
    end

    -- 测试道具滚动条拖动
    if GS.testItemScrollbarDragging and GS.testItemScrollbar then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local sb = GS.testItemScrollbar
        local deltaPixel = my - GS.testItemScrollbarStartY
        local scrollRange = sb.h - sb.thumbH
        if scrollRange > 0 then
            local scrollDelta = deltaPixel / scrollRange * sb.scrollMax
            GS.testItemScrollY = math.max(0, math.min(sb.scrollMax, GS.testItemScrollbarStartScroll + scrollDelta))
        end
    end
    -- 测试道具面板拖动
    if GS.testItemDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.testItemDragStartY - my
        if math.abs(delta) > 3 then
            GS.testItemDragMoved = true
        end
        local totalItems = GS.testItemList and #GS.testItemList or 0
        local contentH = totalItems * (26 + 3) + 12
        local r = GS.testItemPanelRect
        local clipH = r and (r.h - 12) or 200
        local maxScroll = math.max(0, contentH - clipH)
        GS.testItemScrollY = math.max(0, math.min(maxScroll, (GS.testItemDragStartScroll or 0) + delta))
    end

    -- 地图面板拖动
    if GS.mapDragging then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.mapDragStartY - my
        if math.abs(delta) > 3 then
            GS.mapDragMoved = true
        end
        local mapDrawH = GS.mapClipRect and GS.mapClipRect.mapDrawH or 0
        local clipH = GS.mapClipRect and GS.mapClipRect.h or 200
        local maxScroll = math.max(0, mapDrawH - clipH)
        GS.mapScrollY = math.max(0, math.min(maxScroll, GS.mapDragStartScroll + delta))
    end

    -- 背包拖动 & 物品拖拽
    if GS.invDragging then
        local pos = input:GetMousePosition()
        local mx = pos.x / GS.dpr / GS.S
        local my = pos.y / GS.dpr / GS.S

        -- 判断是滚动还是物品拖拽（背包格子或装备槽）
        if (GS.dragSlotIdx or GS.dragEquipSlotId) and not GS.itemDragActive then
            local dx = mx - (GS.itemDragStartX or mx)
            local dy = my - (GS.itemDragStartY or my)
            if dx * dx + dy * dy > 6 * 6 then
                GS.itemDragActive = true
                GS.closeTooltip()
            end
        end

        if GS.itemDragActive then
            -- 物品拖拽模式：更新鼠标坐标
            GS.dragOffsetX = mx
            GS.dragOffsetY = my
        elseif not GS.dragSlotIdx and not GS.dragEquipSlotId then
            -- 纯滚动模式（没有物品/装备拖拽时才滚动背包）
            local delta = GS.invDragStartY - my
            if math.abs(delta) > 3 then
                GS.invDragMoved = true
            end
            local maxScroll = math.max(0, GS.invContentH - GS.invVisibleH)
            GS.invScrollY = math.max(0, math.min(maxScroll, GS.invDragStartScroll + delta))
        end
    end

    -- 遗失物品拖拽检测
    if GS.dragLostItemIdx and not GS.lostItemDragActive then
        local pos = input:GetMousePosition()
        local mx = pos.x / GS.dpr / GS.S
        local my = pos.y / GS.dpr / GS.S
        local dx = mx - (GS.itemDragStartX or mx)
        local dy = my - (GS.itemDragStartY or my)
        if dx * dx + dy * dy > 6 * 6 then
            GS.lostItemDragActive = true
            GS.closeTooltip()
        end
    end
    if GS.lostItemDragActive and GS.dragLostItemIdx then
        local pos = input:GetMousePosition()
        GS.dragOffsetX = pos.x / GS.dpr / GS.S
        GS.dragOffsetY = pos.y / GS.dpr / GS.S
    end

    -- 地图关卡列表：滚动条拖拽
    if GS.mapStageScrollbarDragging and GS.mapStageScrollbarRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local sb = GS.mapStageScrollbarRect
        local relY = math.max(0, math.min(1, (my - sb.y) / sb.h))
        local maxScroll = GS.mapStageScrollMaxOffset
        GS.mapStageScrollOffset = math.floor(relY * maxScroll + 0.5)
        GS.mapStageScrollOffset = math.max(0, math.min(GS.mapStageScrollOffset, maxScroll))
    end

    -- 锻造面板：滚动条拖拽
    if GS.forgeScrollBarDragging and GS.forgePanelRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local fp = GS.forgePanelRect
        local maxSc = fp.maxScroll or 0
        local sbH = GS.forgeScrollBarRect and GS.forgeScrollBarRect.h or 20
        local trackH = fp.h - sbH
        if trackH > 0 and maxSc > 0 then
            local thumbTop = my - (GS.forgeScrollBarGrabY or 0)
            local ratio = math.max(0, math.min(1, (thumbTop - fp.y) / trackH))
            GS.forgeScrollY = ratio * maxSc
        end
    end
    -- 锻造面板：触摸滑动（垂直）
    if GS.forgeTouchStartY and GS.forgePanelRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.forgeTouchStartY - my
        GS.forgeScrollY = math.max(0, GS.forgeTouchStartScroll + delta)
    end

    -- 炼金面板：滚动条拖拽
    if GS.alchemyScrollBarDragging and GS.alchemyPanelRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local ap = GS.alchemyPanelRect
        local maxSc = ap.maxScroll or 0
        local sbH = GS.alchemyScrollBarRect and GS.alchemyScrollBarRect.h or 20
        local trackH = ap.h - sbH
        if trackH > 0 and maxSc > 0 then
            local thumbTop = my - (GS.alchemyScrollBarGrabY or 0)
            local ratio = math.max(0, math.min(1, (thumbTop - ap.y) / trackH))
            GS.alchemyScrollY = ratio * maxSc
        end
    end
    -- 炼金面板：触摸滑动（垂直）
    if GS.alchemyTouchStartY and GS.alchemyPanelRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.alchemyTouchStartY - my
        GS.alchemyScrollY = math.max(0, GS.alchemyTouchStartScroll + delta)
    end
    -- 烹饪面板：滚动条拖拽
    if GS.cookingScrollBarDragging and GS.cookingPanelRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local cp = GS.cookingPanelRect
        local maxSc = cp.maxScroll or 0
        local sbH = GS.cookingScrollBarRect and GS.cookingScrollBarRect.h or 20
        local trackH = cp.h - sbH
        if trackH > 0 and maxSc > 0 then
            local thumbTop = my - (GS.cookingScrollBarGrabY or 0)
            local ratio = math.max(0, math.min(1, (thumbTop - cp.y) / trackH))
            GS.cookingScrollY = ratio * maxSc
        end
    end
    -- 烹饪面板：触摸滑动（垂直）
    if GS.cookingTouchStartY and GS.cookingPanelRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.cookingTouchStartY - my
        GS.cookingScrollY = math.max(0, GS.cookingTouchStartScroll + delta)
    end

    -- 镶嵌面板：触摸滑动（垂直）
    if GS.socketTouchStartY and GS.socketPanelRect then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.socketTouchStartY - my
        local maxScroll = GS.socketMaxScrollY or 0
        GS.socketScrollY = math.max(0, math.min(maxScroll, GS.socketTouchStartScroll + delta))
    end

    -- 阅读弹窗：触摸滑动
    if GS.readingPopupTouchStartY then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.readingPopupTouchStartY - my
        local maxScroll = GS.readingPopupMaxScroll or 0
        GS.readingPopupScrollY = math.max(0, math.min(maxScroll, GS.readingPopupTouchStartScroll + delta))
    end

    -- Tooltip 面板：触摸滑动（垂直滚动，主面板/对比面板独立）
    if GS.tooltipTouchStartY then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local delta = GS.tooltipTouchStartY - my
        if GS.tooltipTouchTarget == "cmp" and GS.tooltipCmpNeedScroll then
            local maxScroll = GS.tooltipCmpMaxScrollY or 0
            GS.tooltipCmpScrollY = math.max(0, math.min(maxScroll, GS.tooltipTouchStartScroll + delta))
        elseif GS.tooltipNeedScroll then
            local maxScroll = GS.tooltipMaxScrollY or 0
            GS.tooltipScrollY = math.max(0, math.min(maxScroll, GS.tooltipTouchStartScroll + delta))
        end
    end

    -- 地图关卡列表：触摸滑动（垂直）
    if GS.mapStageTouchStartY and GS.mapStageListClip then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        local clip = GS.mapStageListClip
        local maxScroll = GS.mapStageScrollMaxOffset
        -- 每移动一个条目高度滚动一格
        local itemStep = clip.h / 7
        local delta = GS.mapStageTouchStartY - my
        local offsetDelta = math.floor(delta / itemStep + 0.5)
        GS.mapStageScrollOffset = math.max(0, math.min(maxScroll, GS.mapStageTouchStartOffset + offsetDelta))
    end

    -- 监测面板拖动滚动
    if MonitorPanel.showPanel and (OnlineMonitor.dragging or MonitorPanel.adDragging or MonitorPanel.lvlDragging) then
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        MonitorPanel.handleDrag(my)
    elseif OnlineMonitor.dragging then
        -- 兼容从GM面板直接打开的在线监测
        local my = input:GetMousePosition().y / GS.dpr / GS.S
        OnlineMonitor.handleDrag(my)
    end


    -- 鼠标悬停检测（仅非锁定状态下；购买弹窗打开时屏蔽）
    if not GS.tooltipPinned and not GS.shopBuyConfirmVisible then
        local pos = input:GetMousePosition()
        local mx = pos.x / GS.dpr / GS.S
        local my = pos.y / GS.dpr / GS.S
        local found = false

        -- 背包物品悬停
        if GS.activeBottomTab == 2 and not GS.invDragging and GS.inventorySlotAreas then
            for idx, r in pairs(GS.inventorySlotAreas) do
                if hitTest(mx, my, r) then
                    local item = GS.inventory[idx]
                    if item then
                        GS.tooltipItem = item
                        GS.tooltipSlotIdx = idx
                        GS.tooltipSource = "inventory"
                        GS.tooltipEquipSlotId = nil
                        found = true
                    end
                    break
                end
            end
        end

        -- 装备槽悬停
        if not found and GS.activeBottomTab == 2 and GS.equipSlotAreas then
            for slotId, r in pairs(GS.equipSlotAreas) do
                if hitTest(mx, my, r) then
                    local equipped = GS.equipment[slotId]
                    if equipped then
                        GS.tooltipItem = equipped
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "equipment"
                        GS.tooltipEquipSlotId = slotId
                        found = true
                    end
                    break
                end
            end
        end

        -- 仓库物品悬停
        if not found and GS.warehouseMode and not GS.warehouseDragging and GS.warehouseSlotAreas then
            for idx, r in pairs(GS.warehouseSlotAreas) do
                if hitTest(mx, my, r) then
                    local item = GS.warehouse[idx]
                    if item then
                        GS.tooltipItem = item
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "warehouse"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = r
                        found = true
                    end
                    break
                end
            end
        end

        -- 共享仓库物品悬停
        if not found and GS.sharedStorageMode and not GS.itemDragActive and GS.sharedStorageSlotAreas then
            for idx, r in pairs(GS.sharedStorageSlotAreas) do
                if hitTest(mx, my, r) then
                    local item = GS.sharedStorage[idx]
                    if item then
                        GS.tooltipItem = item
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "shared_storage"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = r
                        found = true
                    end
                    break
                end
            end
        end

        -- 遗失物品悬停
        if not found and GS.lostItemsMode and GS.lostItemsSlotAreas then
            for idx, r in pairs(GS.lostItemsSlotAreas) do
                if hitTest(mx, my, r) then
                    local item = GS.lostItems[idx]
                    if item then
                        GS.tooltipItem = item
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "lost_items"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = r
                        found = true
                    end
                    break
                end
            end
        end

        -- 炼金面板产出物品图标悬停
        if not found and GS.alchemyMode and GS.alchemyIconRects then
            for _, r in ipairs(GS.alchemyIconRects) do
                -- 只检测在裁剪区域内可见的图标
                if my >= r.listY and my <= r.listY + r.listH
                   and hitTest(mx, my, r) then
                    local tpl = GS.itemTemplates[r.templateId]
                    if tpl then
                        GS.tooltipItem = tpl
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "alchemy"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = r
                        found = true
                    end
                    break
                end
            end
        end

        -- 锻造面板产出物品图标悬停
        if not found and GS.forgeMode and GS.forgeIconRects then
            for _, r in ipairs(GS.forgeIconRects) do
                if my >= r.listY and my <= r.listY + r.listH
                   and hitTest(mx, my, r) then
                    local tpl = GS.itemTemplates[r.templateId]
                    if tpl then
                        GS.tooltipItem = tpl
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "forge"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = r
                        found = true
                    end
                    break
                end
            end
        end

        -- 委托烹饪产出物品图标悬停
        if not found and GS.cookingMode and GS.cookingIconRects then
            for _, r in ipairs(GS.cookingIconRects) do
                if my >= r.listY and my <= r.listY + r.listH
                   and hitTest(mx, my, r) then
                    local tpl = GS.itemTemplates[r.templateId]
                    if tpl then
                        GS.tooltipItem = tpl
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "cooking"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = r
                        found = true
                    end
                    break
                end
            end
        end

        -- 委托加工放置槽物品悬停
        if not found and GS.craftMode and GS.craftDropRect and GS.craftSlotItem then
            local cr = GS.craftDropRect
            if hitTest(mx, my, cr) then
                GS.tooltipItem = GS.craftSlotItem
                GS.tooltipSlotIdx = 0
                GS.tooltipSource = "craft"
                GS.tooltipEquipSlotId = nil
                GS.tooltipAnchorRect = cr
                found = true
            end
        end

        -- 萃取双槽物品悬停
        if not found and GS.craftMode and GS.craftTab == "extract" then
            if GS.extractSourceItem and GS.extractSourceDropRect then
                local sr = GS.extractSourceDropRect
                if hitTest(mx, my, sr) then
                    GS.tooltipItem = GS.extractSourceItem
                    GS.tooltipSlotIdx = 0
                    GS.tooltipSource = "craft"
                    GS.tooltipEquipSlotId = nil
                    GS.tooltipAnchorRect = sr
                    found = true
                end
            end
            if not found and GS.extractTargetItem and GS.extractTargetDropRect then
                local tr = GS.extractTargetDropRect
                if hitTest(mx, my, tr) then
                    GS.tooltipItem = GS.extractTargetItem
                    GS.tooltipSlotIdx = 0
                    GS.tooltipSource = "craft"
                    GS.tooltipEquipSlotId = nil
                    GS.tooltipAnchorRect = tr
                    found = true
                end
            end
        end

        -- 商店物品图标悬停
        if not found and GS.shopMode and GS.shopItemRects then
            for _, r in ipairs(GS.shopItemRects) do
                if r.iconX and hitTest(mx, my, { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }) then
                    local tpl = GS.itemTemplates[r.templateId]
                    if tpl then
                        GS.tooltipItem = tpl
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "shop"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }
                        found = true
                    end
                    break
                end
            end
        end

        -- 兑换物品图标悬停
        if not found and GS.exchangeMode and GS.exchangeItemRects then
            for _, r in ipairs(GS.exchangeItemRects) do
                if r.templateId and r.iconX
                   and hitTest(mx, my, { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }) then
                    local tpl = GS.itemTemplates[r.templateId]
                    if tpl then
                        GS.tooltipItem = tpl
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "exchange"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }
                        found = true
                    end
                    break
                end
            end
        end

        -- 深渊兑换物品图标悬停
        if not found and GS.abyssExchangeMode and GS.abyssExchangeItemRects then
            for _, r in ipairs(GS.abyssExchangeItemRects) do
                if r.iconX and hitTest(mx, my, { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }) then
                    if r.templateId and GS.itemTemplates and GS.itemTemplates[r.templateId] then
                        local tpl = GS.itemTemplates[r.templateId]
                        GS.tooltipItem = tpl
                        GS.tooltipSlotIdx = 0
                        GS.tooltipSource = "abyss_exchange"
                        GS.tooltipEquipSlotId = nil
                        GS.tooltipAnchorRect = { x = r.iconX, y = r.iconY, w = r.iconW, h = r.iconH }
                        found = true
                    end
                    break
                end
            end
        end

        if not found then
            GS.tooltipItem = nil
            GS.tooltipSlotIdx = 0
            GS.tooltipSource = "inventory"
            GS.tooltipEquipSlotId = nil
        end
    end
end

-- ====================================================================
-- 版本检查（异步）：从排行榜读取管理员上传的最低版本号，
-- 与本机版本对比，不一致时设置 GS.versionMismatch = true 并弹窗拦截
-- ====================================================================
local function checkVersionThenEnter(onPass)
    local localVer = GS.APP_VERSION or "ver0.126"
    local major, minor = localVer:match("ver(%d+)%.(%d+)")
    local localInt = (tonumber(major) or 0) * 10000 + (tonumber(minor) or 0)

    GS.versionChecking = true
    clientCloud:Get("game_version_required", {
        ok = function(_values, iscores)
            GS.versionChecking = false
            local requiredInt = iscores and iscores["game_version_required"]
            if requiredInt and type(requiredInt) == "number" and requiredInt > localInt then
                -- 版本落后，弹窗拦截
                GS.versionMismatch = true
            else
                -- 版本一致或云端无记录（首次部署前）：正常进入
                GS.versionMismatch = false
                onPass()
            end
        end,
        error = function(code, reason)
            -- 网络失败时放行（避免因网络问题永久卡住玩家）
            print("[版本检查] 网络错误，跳过检查:", code, reason)
            GS.versionChecking = false
            GS.versionMismatch = false
            onPass()
        end
    })
end

-- ====================================================================
-- 角色选择界面点击处理
-- ====================================================================
function M.handleCharSelectClick(mx, my)
    -- 版本不一致弹窗优先拦截（最高优先级）
    if GS.versionMismatch then
        local dr = GS.versionMismatchDismissRect
        if dr and hitTest(mx, my, dr) then
            GS.versionMismatch = false
        end
        return
    end

    -- 新角色确认弹窗优先拦截
    if GS.charNewConfirmSlot then
        M.handleNewCharConfirmClick(mx, my)
        return
    end

    -- 删除确认弹窗优先拦截
    if GS.charDeleteStep > 0 then
        M.handleDeleteConfirmClick(mx, my)
        return
    end

    -- "进入灰界"按钮
    if GS.charSelectEnterRect and hitTest(mx, my, GS.charSelectEnterRect) then
        -- 封禁账号检查
        if checkBanned() then return end
        -- 版本检测进行中，忽略重复点击
        if GS.versionChecking then return end
        local selSlot = GS.charSelectSelectedSlot
        if selSlot and GS.getSlotInfo(selSlot) and not GS.screenFade then
            -- 版本检查（异步）：通过后再执行黑屏进入流程
            checkVersionThenEnter(function()
            -- 黑屏淡入 → 加载存档 → 进入游戏 → 黑屏淡出
            GS.screenFade = { alpha = 0, target = 255, speed = 300, callback = function()
                GS.loadSlotFromCloud(selSlot, function()
                    if GS.cloudSaveStatus == "loaded" and not SessionLock.isLocked() then
                        -- 存档加载成功且会话有效，正式进入游戏，写入会话锁
                        SessionLock.onEnterGame()
                        if not GS.awakeningCompleted then
                            print("[CharLoad] 苏醒事件未完成，重新进入事件")
                            local EventManager = require("Event.EventManager")
                            EventManager.enter("awakening")
                        else
                            Combat.spawnGatherables()
                            Combat.spawnMonsters()
                            GS.spawnHound()
                            BoardOverlay.show("town", "clearwater", "清水镇")
                            GS.updateAutoSaveSnapshot()
                            GS.autoSave.enabled = true
                        end
                    else
                        -- 加载失败或被多端踢出：回退到角色选择界面
                        print("[CharLoad] 进入游戏失败，回退角色选择 status=" .. tostring(GS.cloudSaveStatus))
                        GS.charSlotIndex = nil
                        GS.autoSave.enabled = false
                        -- [修复] 重置弹窗状态，防止残留 charNewConfirmSlot 干扰后续操作
                        GS.charNewConfirmSlot = nil
                        GS.charDeleteStep    = 0
                        GS.charDeleteSlotIdx = nil
                        GS.charDeleteTimer   = 0
                        GS.gameState = GS.STATE_CHAR_SELECT
                    end
                    -- 淡出黑屏
                    GS.screenFade = { alpha = 255, target = 0, speed = 300 }
                end)
            end }
            end)  -- checkVersionThenEnter
        end
        return
    end

    -- 检查每个槽位的删除按钮和卡片点击
    for i = 1, GS.MAX_CHAR_SLOTS do
        -- 删除按钮（仅有角色的槽位）
        local delRect = GS.charSelectDeleteRects[i]
        if delRect and hitTest(mx, my, delRect) then
            local slotInfo = GS.getSlotInfo(i)
            if slotInfo then
                GS.charDeleteSlotIdx = i
                GS.charDeleteStep = 1
                GS.charDeleteTimer = 0
                return
            end
        end

        -- 卡片点击
        local cardRect = GS.charSelectCardRects[i]
        if cardRect and hitTest(mx, my, cardRect) then
            local slotInfo = GS.getSlotInfo(i)
            if slotInfo then
                -- 有角色 → 选中该槽位
                GS.charSelectSelectedSlot = i
            else
                -- 空槽位 → 若所有槽都为空（首次游玩）直接创建；否则弹窗确认
                if checkBanned() then return end
                local usedCount = GS.getUsedSlotCount()
                if usedCount == 0 then
                    -- 安全守卫：charSlotMeta 为 nil 说明预加载失败，禁止新建角色，防止空 meta 覆盖云端真实存档
                    if not GS.charSlotMeta then
                        print("[CharCreate] charSlotMeta 为 nil（预加载失败），阻止新建角色，请重试或重新加载")
                        return
                    end
                    -- 全空槽：首次游玩，直接进入（先做版本检查）
                    checkVersionThenEnter(function()
                        print("[CharCreate] 首次游玩，直接创建角色: slot=" .. tostring(i))
                        GS.createNewCharacter(i, "……", "traveler", function(ok)
                            if not ok then print("[CharCreate] 云端保存失败，但事件已进入") end
                        end)
                        local EventManager = require("Event.EventManager")
                        EventManager.enter("awakening")
                    end)
                else
                    -- 已有角色：弹窗询问是否创建新角色
                    GS.charNewConfirmSlot = i
                    print("[CharCreate] 弹出新角色确认弹窗: slot=" .. tostring(i))
                end
            end
            return
        end
    end
end

-- ====================================================================
-- 角色创建界面点击处理
-- ====================================================================
function M.handleCharCreateClick(mx, my)
    -- 换名按钮
    if GS.charCreateRerollRect and hitTest(mx, my, GS.charCreateRerollRect) then
        GS.charCreateName = "无名"
        return
    end

    -- 职业卡片
    for _, rect in ipairs(GS.charCreateClassRects) do
        if hitTest(mx, my, rect) then
            GS.charCreateClass = rect.classId
            return
        end
    end

    -- 取消按钮
    if GS.charCreateBackRect and hitTest(mx, my, GS.charCreateBackRect) then
        GS.gameState = GS.STATE_CHAR_SELECT
        return
    end

    -- 确认创建按钮
    if GS.charCreateConfirmRect and hitTest(mx, my, GS.charCreateConfirmRect) then
        -- 安全守卫：charSlotMeta 为 nil 说明预加载失败，禁止新建角色，防止空 meta 覆盖云端真实存档
        if not GS.charSlotMeta then
            print("[CharCreate] charSlotMeta 为 nil（预加载失败），阻止确认创建角色")
            return
        end
        if GS.charCreateClass then
            local name = GS.charCreateName
            if name == "" then name = "无名" end
            print("[CharCreate] 开始创建角色: class=" .. tostring(GS.charCreateClass) .. " slot=" .. tostring(GS.charCreateSlotIdx))
            local createOk, createErr = pcall(function()
                GS.createNewCharacter(GS.charCreateSlotIdx, name, GS.charCreateClass, function(ok)
                    if not ok then
                        print("[CharCreate] 云端保存失败，但事件已进入")
                    end
                end)
            end)
            if not createOk then
                print("[CharCreate] 创建角色时发生错误: " .. tostring(createErr))
                -- 即使创建失败，确保 initGame 已运行则仍尝试进入事件
            end
            -- 同步进入苏醒事件（不等异步保存回调，避免竞态条件）
            local EventManager = require("Event.EventManager")
            print("[CharCreate] 准备进入苏醒事件, isEvent=" .. tostring(GS.isEvent) .. " gameState=" .. tostring(GS.gameState))
            EventManager.enter("awakening")
            print("[CharCreate] 苏醒事件已进入, isEvent=" .. tostring(GS.isEvent))
        end
        return
    end
end

-- ====================================================================
-- 删除确认弹窗点击处理
-- ====================================================================
function M.handleDeleteConfirmClick(mx, my)
    -- 取消按钮
    if GS.charDeleteCancelRect and hitTest(mx, my, GS.charDeleteCancelRect) then
        GS.charDeleteStep = 0
        GS.charDeleteSlotIdx = nil
        GS.charDeleteTimer = 0
        return
    end

    -- 确认按钮
    if GS.charDeleteConfirmRect and hitTest(mx, my, GS.charDeleteConfirmRect) then
        if GS.charDeleteStep == 1 then
            -- 第一次确认 → 进入第二次确认（3秒冷却）
            GS.charDeleteStep = 2
            GS.charDeleteTimer = 3.0
            return
        elseif GS.charDeleteStep == 2 and GS.charDeleteTimer <= 0 then
            -- 冷却结束，真正删除
            local slotIdx = GS.charDeleteSlotIdx
            GS.deleteCharacterSlot(slotIdx, function(ok)
                if ok then
                    -- 如果删除的是当前活跃角色，清空槽位索引
                    if GS.charSlotIndex == slotIdx then
                        GS.charSlotIndex = nil
                    end
                end
            end)
            -- 如果删除的是选中的槽位，清除选中状态
            if GS.charSelectSelectedSlot == slotIdx then
                GS.charSelectSelectedSlot = nil
            end
            GS.charDeleteStep = 0
            GS.charDeleteSlotIdx = nil
            GS.charDeleteTimer = 0
            return
        end
    end
end

-- ====================================================================
-- 新角色确认弹窗点击处理
-- ====================================================================
function M.handleNewCharConfirmClick(mx, my)
    -- 取消
    if GS.charNewCancelRect and hitTest(mx, my, GS.charNewCancelRect) then
        GS.charNewConfirmSlot = nil
        return
    end
    -- 确认创建
    if GS.charNewConfirmRect and hitTest(mx, my, GS.charNewConfirmRect) then
        local slotIdx = GS.charNewConfirmSlot
        GS.charNewConfirmSlot = nil
        -- [安全校验] 再次确认目标槽位确实为空，防止状态残留时误操作已有角色的槽位
        if GS.getSlotInfo(slotIdx) then
            print("[CharCreate] 安全拦截：槽位" .. tostring(slotIdx) .. "已有角色，取消创建")
            return
        end
        -- [安全守卫] charSlotMeta 为 nil 说明预加载失败，禁止新建角色防止覆盖云端存档
        if not GS.charSlotMeta then
            print("[CharCreate] charSlotMeta 为 nil（预加载失败），阻止新建角色（弹窗确认路径）")
            return
        end
        -- 先做版本检查，通过后再进入
        checkVersionThenEnter(function()
            print("[CharCreate] 确认创建新角色: slot=" .. tostring(slotIdx))
            GS.createNewCharacter(slotIdx, "……", "traveler", function(ok)
                if not ok then print("[CharCreate] 云端保存失败，但事件已进入") end
            end)
            local EventManager = require("Event.EventManager")
            EventManager.enter("awakening")
        end)
        return
    end
    -- [修复] 点击弹窗外部区域（未命中任何按钮）也关闭弹窗
    -- 防止 charNewConfirmSlot 残留并在后续拦截"进入灰界"等正常操作
    GS.charNewConfirmSlot = nil
end

-- ====================================================================
-- GM 封禁面板点击处理
-- ====================================================================
function M.handleGMBanPanelClick(mx, my)
    local rects = BanManager.panelRects
    if not rects or not rects.panel then return end

    -- 点击面板外部 → 关闭面板
    if not hitTest(mx, my, rects.panel) then
        BanManager.closeGMPanel()
        return
    end

    -- 关闭按钮
    if rects.close and hitTest(mx, my, rects.close) then
        BanManager.closeGMPanel()
        return
    end

    -- 标签页切换
    if rects.tabs then
        for tabId, rect in pairs(rects.tabs) do
            if hitTest(mx, my, rect) then
                BanManager.setActiveTab(tabId)
                return
            end
        end
    end

    local activeTab = BanManager.getActiveTab()

    if activeTab == "ban" then
        -- 输入框点击 → 激活输入
        if rects.input and hitTest(mx, my, rects.input) then
            BanManager.activateInput()
            return
        end

        -- 模式切换按钮
        if rects.modeBtn and hitTest(mx, my, rects.modeBtn) then
            BanManager.toggleInputMode()
            return
        end

        -- 封禁按钮
        if rects.banBtn and hitTest(mx, my, rects.banBtn) then
            local text = BanManager.getGMInputText()
            if #text > 0 then
                BanManager.gmBanUserByInput(text)
            end
            return
        end

        -- 解封按钮列表
        if rects.unbanBtns then
            for _, btn in ipairs(rects.unbanBtns) do
                if hitTest(mx, my, btn) then
                    BanManager.gmUnbanUser(btn.userId)
                    return
                end
            end
        end

        -- 点击面板内其他区域 → 取消输入焦点
        BanManager.deactivateInput()

    elseif activeTab == "restore" then
        -- 用户ID输入框
        if rects.restoreUidInput and hitTest(mx, my, rects.restoreUidInput) then
            BanManager.restoreActivateUserId()
            return
        end

        -- 槽位按钮
        if rects.restoreSlotBtns then
            for _, btn in ipairs(rects.restoreSlotBtns) do
                if hitTest(mx, my, btn) then
                    BanManager.restoreSetSlot(btn.slot)
                    return
                end
            end
        end

        -- 备份序号按钮
        if rects.restoreBakBtns then
            for _, btn in ipairs(rects.restoreBakBtns) do
                if hitTest(mx, my, btn) then
                    BanManager.restoreSetBackupIndex(btn.backupIndex)
                    return
                end
            end
        end

        -- 发送指令按钮
        if rects.restoreSendBtn and hitTest(mx, my, rects.restoreSendBtn) then
            BanManager.sendRestoreCmd()
            return
        end
        -- 撤销指令按钮
        if rects.restoreCancelBtn and hitTest(mx, my, rects.restoreCancelBtn) then
            BanManager.cancelRestoreCmd()
            return
        end

        -- 点击其他区域 → 取消输入焦点
        BanManager.restoreDeactivate()
    end
end

return M
