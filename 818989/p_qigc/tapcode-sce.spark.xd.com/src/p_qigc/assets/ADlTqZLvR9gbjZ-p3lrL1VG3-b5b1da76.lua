---------------------------------------------------------------
-- QuestManager.lua  —— 主线 / 支线任务管理器
-- 负责任务定义、进度追踪、完成判定、存档序列化
--
-- v2: 支持通用触发类型、解锁条件、提交方式
---------------------------------------------------------------
local GS -- 延迟引用 GameState，避免循环 require

local M = {}

---------------------------------------------------------------
-- 常量
---------------------------------------------------------------
M.CATEGORY_MAIN  = "main"   -- 主线
M.CATEGORY_SIDE  = "side"   -- 支线

-- 任务状态
M.STATUS_LOCKED     = "locked"      -- 未解锁（前置未满足）
M.STATUS_ACTIVE     = "active"      -- 进行中
M.STATUS_READY      = "ready"       -- 目标已达成，待提交
M.STATUS_COMPLETED  = "completed"   -- 已完成

---------------------------------------------------------------
-- 触发类型常量
---------------------------------------------------------------
M.TRIGGER_EVENT        = "event"         -- 由事件脚本手动调用 activateQuest()
M.TRIGGER_AUTO         = "auto"          -- 解锁条件满足后自动激活
M.TRIGGER_SCENE_ENTER  = "scene_enter"   -- 进入指定场景时自动触发
M.TRIGGER_NPC_DIALOGUE = "npc_dialogue"  -- NPC 对话中选择选项触发

---------------------------------------------------------------
-- 提交方式常量
---------------------------------------------------------------
M.SUBMIT_JOURNAL       = "journal"       -- 日志界面点击提交按钮（默认）
M.SUBMIT_AUTO          = "auto"          -- checkDone 为 true 时自动完成
M.SUBMIT_NPC_DIALOGUE  = "npc_dialogue"  -- 通过 NPC 对话提交
M.SUBMIT_SCENE_TRIGGER = "scene_trigger" -- 进入场景/触发剧情后自动完成

---------------------------------------------------------------
-- 冒险者等级映射
---------------------------------------------------------------
local RANK_LETTERS = { "F", "E", "D", "C", "B", "A", "S", "G" }

local function rankLetter(idx)
    return RANK_LETTERS[idx] or "?"
end

---------------------------------------------------------------
-- 解锁条件检查器（按 type 分派）
---------------------------------------------------------------
local conditionCheckers = {
    --- 前置任务已完成
    quest = function(cond, gs, questStates)
        local preState = questStates[cond.questId]
        return preState and preState.status == M.STATUS_COMPLETED
    end,
    --- 玩家等级要求
    level = function(cond, gs, questStates)
        return (gs.playerLevel or gs.adventurerRank or 1) >= (cond.minLevel or 1)
    end,
    --- 冒险者等级要求
    rank = function(cond, gs, questStates)
        return (gs.adventurerRank or 1) >= (cond.minRank or 1)
    end,
    --- 行为标记（GameState 上的布尔/非nil字段）
    flag = function(cond, gs, questStates)
        if cond.field then
            -- 支持嵌套字段检查，如 field="npcTalkedRecord" subKey="elder"
            local val = gs[cond.field]
            if cond.subKey then
                return type(val) == "table" and val[cond.subKey] == true
            end
            return val ~= nil and val ~= false
        end
        -- 简单标记
        return gs[cond.flag] ~= nil and gs[cond.flag] ~= false
    end,
    --- 事件完成标记
    event_completed = function(cond, gs, questStates)
        return gs.eventCompleted and gs.eventCompleted[cond.eventId] == true
    end,
    --- 自定义函数
    custom = function(cond, gs, questStates)
        return cond.check and cond.check(gs)
    end,
}

--- 检查一组解锁条件是否全部满足
---@param conditions table[]|nil
---@return boolean
local function checkUnlockConditions(conditions, gs, questStates)
    if not conditions or #conditions == 0 then return true end
    for _, cond in ipairs(conditions) do
        local checker = conditionCheckers[cond.type]
        if checker then
            if not checker(cond, gs, questStates) then
                return false
            end
        else
            -- 未知条件类型，视为不满足
            print("[QuestManager] 未知解锁条件类型: " .. tostring(cond.type))
            return false
        end
    end
    return true
end

---------------------------------------------------------------
-- 获取任务的有效解锁条件（兼容旧 prerequisite 字段）
---------------------------------------------------------------
local function getEffectiveUnlockConditions(def)
    if def.unlockConditions then
        return def.unlockConditions
    end
    -- 兼容旧的 prerequisite 字段：转换为 unlockConditions
    if def.prerequisite then
        return { { type = "quest", questId = def.prerequisite } }
    end
    return nil
end

---------------------------------------------------------------
-- 获取任务的有效触发类型
---------------------------------------------------------------
local function getEffectiveTriggerType(def)
    if def.triggerType then return def.triggerType end
    -- 兼容旧逻辑：startLocked=true 的任务需要事件触发
    if def.startLocked then return M.TRIGGER_EVENT end
    -- 有前置任务的，前置完成后自动激活
    if def.prerequisite then return M.TRIGGER_AUTO end
    -- 无前置、无 startLocked → 自动激活
    return M.TRIGGER_AUTO
end

---------------------------------------------------------------
-- 获取任务的有效提交方式
---------------------------------------------------------------
local function getEffectiveSubmitMode(def)
    if def.submitMode then return def.submitMode end
    return M.SUBMIT_JOURNAL  -- 默认：日志按钮提交
end

---------------------------------------------------------------
-- 主线任务定义
-- 新增字段说明：
--   triggerType      : "event"/"auto"/"scene_enter"/"npc_dialogue"
--   triggerData      : 触发参数（scene_enter → {sceneId=...}, npc_dialogue → {npcId=..., optionKey=...}）
--   unlockConditions : 解锁条件数组 [{type="quest",questId=...}, {type="level",minLevel=...}, ...]
--   submitMode       : "journal"/"auto"/"npc_dialogue"/"scene_trigger"
--   submitData       : 提交参数（npc_dialogue → {npcId=...}, scene_trigger → {sceneId=...}）
---------------------------------------------------------------
M.QUEST_DEFS = {
    -- ====== 1. 第三意志 ======
    {
        id   = "main_third_will",
        name = "第三意志",
        desc = "你来到了这个世界，有什么在呼唤着你。",
        category = M.CATEGORY_MAIN,
        prerequisite = nil,
        startLocked = true,  -- 事件1完成时激活
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_JOURNAL,
        rewardLabel = "奖励：未知",
        checkDone = function(gs)
            return gs.thirdWillCompleted == true
        end,
        progress = function(gs)
            local done = gs.thirdWillCompleted == true
            return done and 1 or 0, 1, "找到意义"
        end,
    },

    -- ====== 2~7. 提高冒险者等级系列（F→E→D→C→B→A→S） ======
    {
        id   = "main_rank_e",
        name = "提高冒险者等级·E",
        desc = "完成清水镇冒险者公会的晋升考核，证明你的实力。",
        category = M.CATEGORY_MAIN,
        prerequisite = nil,
        startLocked = true,  -- 事件2晋升条件出现时激活
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_AUTO,
        rewardItems = { { templateId = "backpack_expand", count = 1 } },
        checkDone = function(gs) return (gs.adventurerRank or 1) >= 2 end,
        progress = function(gs)
            local promo = gs.RANK_PROMOTIONS and gs.RANK_PROMOTIONS[2]
            local desc = promo and promo.desc or "完成晋升条件"
            if promo then
                if promo.condType == "kill" then
                    local cur = math.min(gs.monsterKillCounts[promo.condId] or 0, promo.condCount)
                    return cur, promo.condCount, desc
                elseif promo.condType == "dungeon" then
                    return gs.dungeonsCleared[promo.condId] and 1 or 0, 1, desc
                elseif promo.condType == "stage_reach" then
                    return (gs.maxStageReached or 1) >= (promo.condStage or 999) and 1 or 0, 1, desc
                end
            end
            return (gs.adventurerRank or 1) >= 2 and 1 or 0, 1, desc
        end,
    },
    {
        id   = "main_rank_d",
        name = "提高冒险者等级·D",
        desc = "完成清水镇冒险者公会的晋升考核，证明你的实力。",
        category = M.CATEGORY_MAIN,
        prerequisite = "main_rank_e",
        triggerType = M.TRIGGER_AUTO,
        submitMode  = M.SUBMIT_AUTO,
        rewardItems = { { templateId = "backpack_expand", count = 2 } },
        checkDone = function(gs) return (gs.adventurerRank or 1) >= 3 end,
        progress = function(gs)
            local promo = gs.RANK_PROMOTIONS and gs.RANK_PROMOTIONS[3]
            local desc = promo and promo.desc or "完成晋升条件"
            if promo then
                if promo.condType == "kill" then
                    local cur = math.min(gs.monsterKillCounts[promo.condId] or 0, promo.condCount)
                    return cur, promo.condCount, desc
                elseif promo.condType == "dungeon" then
                    return gs.dungeonsCleared[promo.condId] and 1 or 0, 1, desc
                elseif promo.condType == "stage_reach" then
                    return (gs.maxStageReached or 1) >= (promo.condStage or 999) and 1 or 0, 1, desc
                end
            end
            return (gs.adventurerRank or 1) >= 3 and 1 or 0, 1, desc
        end,
    },
    {
        id   = "main_rank_c",
        name = "提高冒险者等级·C",
        desc = "完成清水镇冒险者公会的晋升考核，证明你的实力。",
        category = M.CATEGORY_MAIN,
        prerequisite = "main_rank_d",
        triggerType = M.TRIGGER_AUTO,
        submitMode  = M.SUBMIT_AUTO,
        rewardItems = { { templateId = "backpack_expand", count = 3 } },
        checkDone = function(gs) return (gs.adventurerRank or 1) >= 4 end,
        progress = function(gs)
            local promo = gs.RANK_PROMOTIONS and gs.RANK_PROMOTIONS[4]
            local desc = promo and promo.desc or "完成晋升条件"
            if promo then
                if promo.condType == "kill" then
                    local cur = math.min(gs.monsterKillCounts[promo.condId] or 0, promo.condCount)
                    return cur, promo.condCount, desc
                elseif promo.condType == "dungeon" then
                    return gs.dungeonsCleared[promo.condId] and 1 or 0, 1, desc
                elseif promo.condType == "stage_reach" then
                    return (gs.maxStageReached or 1) >= (promo.condStage or 999) and 1 or 0, 1, desc
                end
            end
            return (gs.adventurerRank or 1) >= 4 and 1 or 0, 1, desc
        end,
    },
    {
        id   = "main_rank_b",
        name = "提高冒险者等级·B",
        desc = "完成清水镇冒险者公会的晋升考核，证明你的实力。",
        category = M.CATEGORY_MAIN,
        prerequisite = "main_rank_c",
        triggerType = M.TRIGGER_AUTO,
        submitMode  = M.SUBMIT_AUTO,
        rewardItems = { { templateId = "backpack_expand", count = 4 } },
        checkDone = function(gs) return (gs.adventurerRank or 1) >= 5 end,
        progress = function(gs)
            local promo = gs.RANK_PROMOTIONS and gs.RANK_PROMOTIONS[5]
            local desc = promo and promo.desc or "完成晋升条件"
            if promo then
                if promo.condType == "kill" then
                    local cur = math.min(gs.monsterKillCounts[promo.condId] or 0, promo.condCount)
                    return cur, promo.condCount, desc
                elseif promo.condType == "dungeon" then
                    return gs.dungeonsCleared[promo.condId] and 1 or 0, 1, desc
                elseif promo.condType == "stage_reach" then
                    return (gs.maxStageReached or 1) >= (promo.condStage or 999) and 1 or 0, 1, desc
                end
            end
            return (gs.adventurerRank or 1) >= 5 and 1 or 0, 1, desc
        end,
    },
    {
        id   = "main_rank_a",
        name = "提高冒险者等级·A",
        desc = "完成清水镇冒险者公会的晋升考核，证明你的实力。",
        category = M.CATEGORY_MAIN,
        prerequisite = "main_rank_b",
        triggerType = M.TRIGGER_AUTO,
        submitMode  = M.SUBMIT_AUTO,
        rewardItems = { { templateId = "backpack_expand", count = 5 } },
        checkDone = function(gs) return (gs.adventurerRank or 1) >= 6 end,
        progress = function(gs)
            local promo = gs.RANK_PROMOTIONS and gs.RANK_PROMOTIONS[6]
            local desc = promo and promo.desc or "完成晋升条件"
            if promo then
                if promo.condType == "kill" then
                    local cur = math.min(gs.monsterKillCounts[promo.condId] or 0, promo.condCount)
                    return cur, promo.condCount, desc
                elseif promo.condType == "dungeon" then
                    return gs.dungeonsCleared[promo.condId] and 1 or 0, 1, desc
                elseif promo.condType == "stage_reach" then
                    return (gs.maxStageReached or 1) >= (promo.condStage or 999) and 1 or 0, 1, desc
                end
            end
            return (gs.adventurerRank or 1) >= 6 and 1 or 0, 1, desc
        end,
    },
    {
        id   = "main_rank_s",
        name = "提高冒险者等级·S",
        desc = "完成清水镇冒险者公会的晋升考核，证明你的实力。",
        category = M.CATEGORY_MAIN,
        prerequisite = "main_rank_a",
        triggerType = M.TRIGGER_AUTO,
        submitMode  = M.SUBMIT_AUTO,
        rewardItems = { { templateId = "backpack_expand", count = 6 } },
        checkDone = function(gs) return (gs.adventurerRank or 1) >= 7 end,
        progress = function(gs)
            local promo = gs.RANK_PROMOTIONS and gs.RANK_PROMOTIONS[7]
            local desc = promo and promo.desc or "完成晋升条件"
            if promo then
                if promo.condType == "kill" then
                    local cur = math.min(gs.monsterKillCounts[promo.condId] or 0, promo.condCount)
                    return cur, promo.condCount, desc
                elseif promo.condType == "dungeon" then
                    return gs.dungeonsCleared[promo.condId] and 1 or 0, 1, desc
                elseif promo.condType == "stage_reach" then
                    return (gs.maxStageReached or 1) >= (promo.condStage or 999) and 1 or 0, 1, desc
                end
            end
            local done = (gs.adventurerRank or 1) >= 7
            return done and 1 or 0, 1, desc
        end,
    },

    -- ====== 支线：筑巢 ======
    {
        id   = "side_nesting",
        name = "筑巢",
        desc = "你来到了陌生的世界，需要一个栖身之所。",
        category = M.CATEGORY_SIDE,
        prerequisite = nil,
        startLocked = true,  -- 首次点击清水镇"家"按钮时激活
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_JOURNAL,
        rewardItems = { { templateId = "warehouse_expand", count = 5 } },
        checkDone = function(gs)
            return gs.housePurchased == true
        end,
        progress = function(gs)
            local done = gs.housePurchased == true
            return done and 1 or 0, 1, "拥有\"家\""
        end,
    },

    -- ====== 支线：清水镇的人们 ======
    {
        id   = "side_townspeople",
        name = "清水镇的人们",
        desc = "与清水镇的居民们交谈，了解这里的人们。",
        category = M.CATEGORY_SIDE,
        prerequisite = nil,
        startLocked = true,  -- 事件1完成时激活
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_JOURNAL,
        rewardItems = { { templateId = "backpack_expand", count = 5 } },
        checkDone = function(gs)
            local talked = gs.npcTalkedRecord or {}
            local targets = {
                "blacksmith", "armor_shop", "guild",
                "jewelry_shop", "potion_shop",
                "tavern_dancer", "tavern",
            }
            for _, npcKey in ipairs(targets) do
                if not talked[npcKey] then return false end
            end
            return true
        end,
        progress = function(gs)
            local talked = gs.npcTalkedRecord or {}
            local targets = {
                "blacksmith", "armor_shop", "guild",
                "jewelry_shop", "potion_shop",
                "tavern_dancer", "tavern",
            }
            local count = 0
            for _, npcKey in ipairs(targets) do
                if talked[npcKey] then count = count + 1 end
            end
            return count, #targets, "与清水镇的居民交谈"
        end,
    },

    -- ====== 支线：化身蝙蝠 ======
    {
        id   = "side_bat_fang",
        name = "化身蝙蝠",
        desc = "到垂雾森林的森林入口击杀随机出现的吸血蝙蝠，获取它掉落的蝙蝠牙挂饰装备。",
        category = M.CATEGORY_SIDE,
        prerequisite = nil,
        startLocked = true,
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_JOURNAL,
        reward = 500,
        checkDone = function(gs)
            if gs.countInventoryItem("bat_fang_trinket") >= 1 then return true end
            local eq = gs.equipment
            return eq and eq["trinket"] and eq["trinket"].templateId == "bat_fang_trinket"
        end,
        progress = function(gs)
            local has = gs.countInventoryItem("bat_fang_trinket") >= 1
                or (gs.equipment and gs.equipment["trinket"] and gs.equipment["trinket"].templateId == "bat_fang_trinket")
            return has and 1 or 0, 1, "获取蝙蝠牙挂饰"
        end,
    },

    -- ====== 支线（每日）：为了大家！ ======
    {
        id   = "side_daily_bulletin",
        name = "为了大家！",
        desc = "看一下公告板上都有什么事项吧——为了大家！",
        category = M.CATEGORY_SIDE,
        prerequisite = nil,
        startLocked = true,  -- 由公告板刷新时激活
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_JOURNAL,
        daily = true,        -- 标记为每日任务
        -- 动态奖励：前2次完成给3000G，第3次起给感恩礼券×3
        getRewardItems = function(gs)
            if (gs.bulletinQuestTotalDone or 0) < 2 then
                return nil, 3000  -- 无物品奖励，金币3000
            end
            return { { templateId = "gratitude_ticket", count = 3 } }, nil
        end,
        checkDone = function(gs)
            return (gs.dailyBulletinDoneCount or 0) >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.dailyBulletinDoneCount or 0, 5)
            return count, 5, "完成公告板委托"
        end,
    },

    -- ====== 迪芬任务序列：物资订单一 ======
    {
        id   = "side_difen_order1",
        name = "物资订单一",
        desc = "迪芬的库存快用完了，她需要一些铜矿石。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "armor_shop" },
        unlockConditions = {
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 15 end },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "armor_shop" },
        npcQuestLine = "difen",  -- 任务序列标识，用于 UI 排序
        npcQuestOrder = 1,       -- 序列内排序
        acceptDialogue = {
            speaker = "迪芬",
            lines = {
                "嘿，{玩家}，最近盔甲铺生意不错，我想补一点库存的矿石。",
                "这里有一个物资订单。反正你也要出去冒险，顺便就带一点回来吧，收购价格绝对好。",
            },
        },
        submitDialogue = {
            speaker = "迪芬",
            lines = {
                "嗯，我看看……不错，这是你的报酬。下次还能请你帮忙吗？",
            },
        },
        rewardAtLine = 1, -- "报酬"
        acceptOptionText = "有什么我能做的吗？",
        submitOptionText = "对了，你要的物资……",
        requireItems = { { templateId = "tongkuang", count = 5 } },
        reward = 450,
        onComplete = function(gs)
            gs.changeAffinity("armor_shop", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("tongkuang") >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("tongkuang"), 5)
            return count, 5, "提交铜矿石"
        end,
    },

    -- ====== 迪芬任务序列：物资订单二 ======
    {
        id   = "side_difen_order2",
        name = "物资订单二",
        desc = "迪芬给你提供了一份银矿石订单。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "armor_shop" },
        unlockConditions = {
            { type = "quest", questId = "side_difen_order1" },
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 25 end },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "armor_shop" },
        npcQuestLine = "difen",
        npcQuestOrder = 2,
        acceptDialogue = {
            speaker = "迪芬",
            lines = {
                "{玩家}，我这有个有挑战的活。对之前的冒险者我没有信心，但是你目前的表现超出了我的预期。",
                "于是昨天我突然想，为什么不想办法整一些银矿石呢？这是稀罕物，但价格不会亏待你的，这是物资订单。",
            },
        },
        submitDialogue = {
            speaker = "迪芬",
            lines = {
                "快拿过来，这些矿石太美了……谢谢你，{玩家}。",
            },
        },
        rewardAtLine = 0, -- 无报酬提及，对话结束后发放
        acceptOptionText = "有什么我能做的吗？",
        submitOptionText = "对了，你要的物资……",
        requireItems = { { templateId = "yinkuang", count = 5 } },
        reward = 1000,
        onComplete = function(gs)
            gs.changeAffinity("armor_shop", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("yinkuang") >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("yinkuang"), 5)
            return count, 5, "提交银矿石"
        end,
    },

    -- ====== 迪芬任务序列：物资订单三 ======
    {
        id   = "side_difen_order3",
        name = "物资订单三",
        desc = "迪芬给你提供了一份银矿石订单。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "armor_shop" },
        unlockConditions = {
            { type = "quest", questId = "side_difen_order2" },
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 35 end },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "armor_shop" },
        npcQuestLine = "difen",
        npcQuestOrder = 3,
        acceptDialogue = {
            speaker = "迪芬",
            lines = {
                "{玩家}，上次的银矿石很好，就是有点不太够用。所以又有新的物资订单了，来试试吧。",
            },
        },
        submitDialogue = {
            speaker = "迪芬",
            lines = {
                "这下应该够用了。{玩家}……我不知道说什么好，你帮了我太多。",
            },
        },
        rewardAtLine = 0, -- 无报酬提及，对话结束后发放
        acceptOptionText = "有什么我能做的吗？",
        submitOptionText = "对了，你要的物资……",
        requireItems = { { templateId = "yinkuang", count = 10 } },
        reward = 2000,
        onComplete = function(gs)
            gs.changeAffinity("armor_shop", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("yinkuang") >= 10
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("yinkuang"), 10)
            return count, 10, "提交银矿石"
        end,
    },

    -- ====== 迪芬任务序列：复仇 ======
    {
        id   = "side_difen_revenge",
        name = "复仇",
        desc = "迪芬请你陪同他前往垂雾森林，他有必须要做的事情。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "armor_shop" },
        unlockConditions = {
            { type = "quest", questId = "side_difen_order3" },
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 45 end },
        },
        submitMode  = M.SUBMIT_AUTO,
        npcQuestLine = "difen",
        npcQuestOrder = 4,
        onActivate = function(gs)
            -- 接取时清除旅行完成标记，防止存档残留导致立即自动完成
            if gs.difenTravelDone then
                gs.difenTravelDone["side_difen_revenge"] = nil
            end
        end,
        acceptDialogue = {
            speaker = "迪芬",
            lines = {
                "{玩家}，能陪我去一趟垂雾森林吗？那里有个矿洞我必须得自己去，我知道这很麻烦，但我会给报酬的。",
            },
        },
        acceptOptionText = "你今天看起来不太一样？",
        reward = 0,
        rewardLabel = "奖励：制甲匠的遗物项链",
        rewardItems = { { templateId = "difen_legacy_necklace", count = 1 } },
        checkDone = function(gs)
            return gs.difenTravelDone and gs.difenTravelDone["side_difen_revenge"]
        end,
        progress = function(gs)
            local done = gs.difenTravelDone and gs.difenTravelDone["side_difen_revenge"]
            return done and 1 or 0, 1, "陪迪芬前往垂雾森林矿洞"
        end,
        onComplete = function(gs)
            gs.changeAffinity("armor_shop", 20)
            print("[Quest] 迪芬任务4（复仇）完成：好感+20, 获得制甲匠的遗物项链")
        end,
    },

    -- ==========================================================
    -- 斯特朗任务序列
    -- ==========================================================

    -- ====== 斯特朗 1：补货 ======
    {
        id   = "side_strong_restock",
        name = "补货",
        desc = "斯特朗需要一批铁矿石粗矿补充库存。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "blacksmith" },
        unlockConditions = {},  -- 无解锁条件
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "blacksmith" },
        npcQuestLine = "strong",
        npcQuestOrder = 1,
        acceptDialogue = {
            speaker = "斯特朗",
            lines = {
                "哥们儿，你出去的时候帮我整点铁矿石回来，帮我个忙，怎样？钱不会少你的。",
            },
        },
        submitDialogue = {
            speaker = "斯特朗",
            lines = {
                "哥们儿，靠谱。拿着，这是钱。",
            },
        },
        rewardAtLine = 1, -- "这是钱"
        acceptOptionText = "有什么我能帮忙的吗？",
        submitOptionText = "你要的铁矿石，我带来了。",
        requireItems = { { templateId = "crude_iron_ore", count = 5 } },
        reward = 300,
        onComplete = function(gs)
            gs.changeAffinity("blacksmith_owner", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("crude_iron_ore") >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("crude_iron_ore"), 5)
            return count, 5, "提交铁矿石粗矿"
        end,
    },

    -- ====== 斯特朗 2：学徒一 ======
    {
        id   = "side_strong_apprentice1",
        name = "学徒一",
        desc = "斯特朗想让约瑟夫实践锻造金矿石，需要你帮忙收集材料。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "blacksmith" },
        unlockConditions = {
            { type = "quest", questId = "side_difen_revenge" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "blacksmith" },
        npcQuestLine = "strong",
        npcQuestOrder = 2,
        acceptDialogue = {
            speaker = "斯特朗",
            lines = {
                "约瑟夫现在在我这当学徒，你知道吧？我看出来他完完全全是这块料，所以我准备好好教他，就像我师父带我一样。",
                "但是呢，锻造这门手艺得靠实践出真知，如果你有好的材料就拿过来吧，约瑟夫会免费帮你加工成金属锭。",
                "先来一点金矿石粗矿怎么样？相信我，他是个天才，活儿干得肯定比你好。",
            },
        },
        submitDialogue = {
            { speaker = "斯特朗", lines = { "交给约瑟夫吧。" } },
            { speaker = "旁白", lines = { "（叮叮当当——）" } },
            { speaker = "斯特朗", lines = { "成了，这金属锭打造得太漂亮了，拿去吧。" } },
        },
        rewardAtLine = 3, -- "拿去吧"
        acceptOptionText = "有什么我能帮忙的吗？",
        submitOptionText = "金矿石粗矿带来了。",
        requireItems = { { templateId = "jinkuangshi", count = 5 } },
        rewardItems = { { templateId = "gold_ingot", count = 15 } },
        onComplete = function(gs)
            gs.changeAffinity("blacksmith_owner", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("jinkuangshi") >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("jinkuangshi"), 5)
            return count, 5, "提交金矿石粗矿"
        end,
    },

    -- ====== 斯特朗 3：学徒二 ======
    {
        id   = "side_strong_apprentice2",
        name = "学徒二",
        desc = "斯特朗需要蓝银矿石来教约瑟夫更高级的锻造技艺。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "blacksmith" },
        unlockConditions = {
            { type = "quest", questId = "side_strong_apprentice1" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "blacksmith" },
        npcQuestLine = "strong",
        npcQuestOrder = 3,
        acceptDialogue = {
            speaker = "斯特朗",
            lines = {
                "接下来我的教学计划是教约瑟夫怎么对付蓝银矿石，你有了就拿过来吧，规矩还是老规矩。",
            },
        },
        submitDialogue = {
            {
                speaker = "斯特朗",
                lines = {
                    "这个不错，交给约瑟夫吧。",
                },
            },
            {
                speaker = "旁白",
                lines = {
                    "（叮叮当当……）",
                },
            },
            {
                speaker = "斯特朗",
                lines = {
                    "成了，这金属锭打造得太漂亮了，拿去吧。",
                },
            },
        },
        rewardAtLine = 3, -- "拿去吧"
        acceptOptionText = "有什么我能帮忙的吗？",
        submitOptionText = "蓝银矿石在这里。",
        requireItems = { { templateId = "lanyinkuangshi", count = 5 } },
        rewardItems = { { templateId = "blue_silver_ingot", count = 15 } },
        onComplete = function(gs)
            gs.changeAffinity("blacksmith_owner", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("lanyinkuangshi") >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("lanyinkuangshi"), 5)
            return count, 5, "提交蓝银矿石粗矿"
        end,
    },

    -- ====== 斯特朗 4：学徒三 ======
    {
        id   = "side_strong_apprentice3",
        name = "学徒三",
        desc = "约瑟夫的成长需要辉金矿石，斯特朗请你帮忙搜集。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "blacksmith" },
        unlockConditions = {
            { type = "quest", questId = "side_strong_apprentice2" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "blacksmith" },
        npcQuestLine = "strong",
        npcQuestOrder = 4,
        acceptDialogue = {
            speaker = "斯特朗",
            lines = {
                "辉金矿石，能想办法整5个吗？我一生也只见过几次，但是约瑟夫的成长需要这玩意儿，拜托你了，哥们儿。",
            },
        },
        submitDialogue = {
            {
                speaker = "斯特朗",
                lines = {
                    "我真没奢望你能真搞来，这太漂亮了，你等着。",
                },
            },
            {
                speaker = "旁白",
                lines = {
                    "（叮叮当当……）",
                },
            },
            {
                speaker = "斯特朗",
                lines = {
                    "成了，这金属锭打造得太漂亮了，拿去吧。",
                },
            },
        },
        rewardAtLine = 3, -- "拿去吧"
        acceptOptionText = "有什么我能帮忙的吗？",
        submitOptionText = "辉金矿石，请过目。",
        requireItems = { { templateId = "huijinkuangshi", count = 5 } },
        rewardItems = { { templateId = "radiant_gold_ingot", count = 15 } },
        onComplete = function(gs)
            gs.changeAffinity("blacksmith_owner", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("huijinkuangshi") >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("huijinkuangshi"), 5)
            return count, 5, "提交辉金矿石粗矿"
        end,
    },

    -- ====== 斯特朗 5：学徒四 ======
    {
        id   = "side_strong_apprentice4",
        name = "学徒四",
        desc = "约瑟夫的最终考验——帮斯特朗找到传说中的黑钢矿石。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "blacksmith" },
        unlockConditions = {
            { type = "quest", questId = "side_strong_apprentice3" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "blacksmith" },
        npcQuestLine = "strong",
        npcQuestOrder = 5,
        acceptDialogue = {
            speaker = "斯特朗",
            lines = {
                "约瑟夫的技艺已经不低于我，现在是时候让他青出于蓝而胜于蓝了。",
                "听说这个世界上有一种纯黑的坚硬矿石，比钢铁还要坚硬数十倍。我也没见过，你要是能搞来，我们保准帮你打造得漂漂亮亮的。",
            },
        },
        submitDialogue = {
            {
                speaker = "斯特朗",
                lines = {
                    "……",
                },
            },
            {
                speaker = "旁白",
                lines = {
                    "（斯特朗看到黑钢矿石，激动地说不出话……叮叮当当……）",
                },
            },
            {
                speaker = "斯特朗",
                lines = {
                    "成了，拿去吧。",
                },
            },
        },
        rewardAtLine = 3, -- "拿去吧"
        acceptOptionText = "有什么我能帮忙的吗？",
        submitOptionText = "黑钢矿石，我带回来了。",
        requireItems = { { templateId = "heigangkuangshi", count = 5 } },
        rewardItems = { { templateId = "black_steel_ingot", count = 15 } },
        onComplete = function(gs)
            gs.changeAffinity("blacksmith_owner", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("heigangkuangshi") >= 5
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("heigangkuangshi"), 5)
            return count, 5, "提交黑钢矿石粗矿"
        end,
    },

    -- ====== 斯特朗 6：作品 ======
    {
        id   = "side_strong_masterwork",
        name = "作品",
        desc = "约瑟夫已经出师了，斯特朗说他打造了一件作品要送给你。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "blacksmith" },
        unlockConditions = {
            { type = "quest", questId = "side_strong_apprentice4" },
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 90 end },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "blacksmith" },
        npcQuestLine = "strong",
        npcQuestOrder = 6,
        acceptDialogue = {
            speaker = "斯特朗",
            lines = {
                "嘿，哥们儿，听着，约瑟夫的成长你帮了很大的忙。庆幸的是，我们没有看走眼，他确实是个不折不扣的天才。",
                "好材料太稀缺了，只够打造一个腰带扣。我帮他做成腰带了，你试试合不合体。",
            },
        },
        submitDialogue = {
            speaker = "斯特朗",
            lines = { "怎么样，合适吧？" },
        },
        acceptOptionText = "有什么我能帮忙的吗？",
        submitOptionText = "我来看看约瑟夫的作品。",
        -- requireItems: 无需提交物品，纯对话任务
        rewardItems = { { templateId = "blacksmith_belt", count = 1 } },
        onComplete = function(gs)
            gs.changeAffinity("blacksmith_owner", 20)
        end,
        checkDone = function(gs)
            -- 接取即完成（对话任务）
            return true
        end,
        progress = function(gs)
            return 1, 1, "与斯特朗交谈"
        end,
    },

    -- ==========================================================
    -- 爱丽丝任务序列：听说很好吃
    -- ==========================================================

    -- ====== 爱丽丝 1：听说很好吃一 ======
    {
        id   = "side_alice_food1",
        name = "听说很好吃一",
        desc = "爱丽丝假借红杯酒馆名义举办的美食交换大赛。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "tavern" },
        unlockConditions = {},
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "tavern" },
        npcQuestLine = "alice_food",
        npcQuestOrder = 1,
        acceptDialogue = {
            speaker = "爱丽丝",
            lines = {
                "{玩家}/{爱称}，红杯酒馆近期在举办美食交换活动……哈哈，好吧，其实是我自己想吃。",
                "我一直都想吃盐烤肉，你可以带一份给我吗？作为交换，我也会给你一份我喜爱的食物。",
            },
        },
        submitDialogue = {
            {
                speaker = "爱丽丝",
                lines = {
                    "哇！你真的带来了！太谢谢你了！啊，好好吃……",
                },
            },
            {
                speaker = "爱丽丝",
                lines = {
                    "这份圣百合炒肉送给你！",
                },
            },
        },
        rewardAtLine = 2, -- "送给你"
        acceptOptionText = "你最近在忙什么？",
        submitOptionText = "给你带了好吃的。",
        requireItems = { { templateId = "cook_salt_meat", count = 1 } },
        rewardItems  = { { templateId = "cook_lily_stir_fry", count = 1 } },
        rewardLabel = "奖励：圣百合炒肉×1",
        onComplete = function(gs)
            gs.changeAffinity("tavern_keeper", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("cook_salt_meat") >= 1
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("cook_salt_meat"), 1)
            return count, 1, "提交盐烤肉"
        end,
    },

    -- ====== 爱丽丝 2：听说很好吃二 ======
    {
        id   = "side_alice_food2",
        name = "听说很好吃二",
        desc = "爱丽丝假借红杯酒馆名义举办的美食交换大赛。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "tavern" },
        unlockConditions = {
            { type = "quest", questId = "side_alice_food1" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "tavern" },
        npcQuestLine = "alice_food",
        npcQuestOrder = 2,
        acceptDialogue = {
            speaker = "爱丽丝",
            lines = {
                "{玩家}/{爱称}，美食交换活动还在举办中哦！嘻嘻，不要揭穿我！",
                "最近我特别想吃炒什锦蔬菜，作为交换，我也会给你一份美食的！",
            },
        },
        submitDialogue = {
            speaker = "爱丽丝",
            lines = {
                "好好吃，味道很清爽。这份蒸熊掌给你，你试试看？",
            },
        },
        rewardAtLine = 1, -- "给你"
        acceptOptionText = "你最近在忙什么？",
        submitOptionText = "给你带了好吃的。",
        requireItems = { { templateId = "cook_veggie_mix", count = 1 } },
        rewardItems  = { { templateId = "cook_steamed_paw", count = 1 } },
        rewardLabel = "奖励：蒸熊掌×1",
        onComplete = function(gs)
            gs.changeAffinity("tavern_keeper", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("cook_veggie_mix") >= 1
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("cook_veggie_mix"), 1)
            return count, 1, "提交炒什锦蔬菜"
        end,
    },

    -- ====== 爱丽丝 3：听说很好吃三 ======
    {
        id   = "side_alice_food3",
        name = "听说很好吃三",
        desc = "爱丽丝假借红杯酒馆名义举办的美食交换大赛。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "tavern" },
        unlockConditions = {
            { type = "quest", questId = "side_alice_food2" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "tavern" },
        npcQuestLine = "alice_food",
        npcQuestOrder = 3,
        acceptDialogue = {
            speaker = "爱丽丝",
            lines = {
                "{玩家}/{爱称}，又来进行美食交换了吗？",
                "嗯……我想试试岩龟肉汤，用灰海岸边的岩龟肉熬制而成的美味肉汤……嘿嘿，流口水了，拜托你了。",
            },
        },
        submitDialogue = {
            speaker = "爱丽丝",
            lines = {
                "好美味。作为礼物，这个送给你！",
            },
        },
        rewardAtLine = 1, -- "送给你"
        acceptOptionText = "你最近在忙什么？",
        submitOptionText = "给你带了好吃的。",
        requireItems = { { templateId = "cook_turtle_soup", count = 1 } },
        rewardItems  = { { templateId = "cook_starry_sky", count = 1 } },
        rewardLabel = "奖励：\"星空\"×1",
        onComplete = function(gs)
            gs.changeAffinity("tavern_keeper", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("cook_turtle_soup") >= 1
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("cook_turtle_soup"), 1)
            return count, 1, "提交岩龟肉汤"
        end,
    },

    -- ====== 爱丽丝 4：听说很好吃四 ======
    {
        id   = "side_alice_food4",
        name = "听说很好吃四",
        desc = "爱丽丝假借红杯酒馆名义举办的美食交换大赛。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "tavern" },
        unlockConditions = {
            { type = "quest", questId = "side_alice_food3" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "tavern" },
        npcQuestLine = "alice_food",
        npcQuestOrder = 4,
        acceptDialogue = {
            speaker = "爱丽丝",
            lines = {
                "{玩家}/{爱称}，当当当当！美食交换活动绝赞举办中！",
                "我听说世界上存在一种果冻，不仅有长得像星云般漂亮的花纹，而且口味也特别好。好像叫做星云果冻？能带来给我吗？拜托拜托！",
            },
        },
        submitDialogue = {
            speaker = "爱丽丝",
            lines = {
                "居然真的带来了……那我也不会小气的，品尝一下这份海陆空盛宴吧！",
            },
        },
        rewardAtLine = 0, -- 无报酬提及，对话结束后发放
        acceptOptionText = "你最近在忙什么？",
        submitOptionText = "给你带了好吃的。",
        requireItems = { { templateId = "cook_nebula_jelly", count = 1 } },
        rewardItems  = { { templateId = "cook_land_sea_feast", count = 1 } },
        rewardLabel = "奖励：海陆空盛宴×1",
        onComplete = function(gs)
            gs.changeAffinity("tavern_keeper", 20)
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("cook_nebula_jelly") >= 1
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("cook_nebula_jelly"), 1)
            return count, 1, "提交星云果冻"
        end,
    },

    -- ====== 爱丽丝 5：听说很好吃五 ======
    {
        id   = "side_alice_food5",
        name = "听说很好吃五",
        desc = "爱丽丝假借红杯酒馆名义举办的美食交换大赛。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "tavern" },
        unlockConditions = {
            { type = "quest", questId = "side_alice_food4" },
        },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "tavern" },
        npcQuestLine = "alice_food",
        npcQuestOrder = 5,
        acceptDialogue = {
            speaker = "爱丽丝",
            lines = {
                "{玩家}/{爱称}，听说世界上存在着一种最最顶级的果冻，叫做宇宙果冻，我特别特别想吃。",
                "但是我已经没有更好的食物可以和你交换了……什么？不交换也可以？太谢谢了！",
            },
        },
        submitDialogue = {
            {
                speaker = "爱丽丝",
                lines = {
                    "这个口味真是无法形容……我不知道怎么谢你了。",
                    "对了，其实我最近在红杯酒馆的酒窖里发现了这个盒子。",
                    "里面是空的，但是打开时好像有人在里面说话……送给你吧！万一对你有用呢？",
                },
            },
            {
                speaker = "爱丽丝",
                lines = {
                    "偶尔也放松下来享受美食吧，总是紧张地参与冒险，会累垮的。",
                },
            },
            {
                speaker = "旁白",
                lines = {
                    "（这个盒子是一个链接异世界的共享仓库，你把它放在了家里的书桌上。）",
                    "（现在你可以在不同角色间转移一些异世界规则允许的物品了，注意，不是全部哦。）",
                },
            },
        },
        rewardAtLine = 3, -- "送给你吧"
        acceptOptionText = "你最近在忙什么？",
        submitOptionText = "给你带了好吃的。",
        requireItems = { { templateId = "cook_cosmos_jelly", count = 1 } },
        -- rewardItems: 共享仓库解锁（不是物品奖励）
        rewardLabel = "奖励：开启共享仓库",
        onComplete = function(gs)
            gs.changeAffinity("tavern_keeper", 20)
            gs.sharedStorageUnlocked = true
            print("[Quest] 爱丽丝任务5完成：共享仓库已解锁")
        end,
        checkDone = function(gs)
            return gs.countInventoryItem("cook_cosmos_jelly") >= 1
        end,
        progress = function(gs)
            local count = math.min(gs.countInventoryItem("cook_cosmos_jelly"), 1)
            return count, 1, "提交宇宙果冻"
        end,
    },
}

-- ==========================================================
-- 芙蕾雅任务序列（程序化生成）
-- ==========================================================

-- 斩首系列：按等级排序的稀有怪物赏金任务
local RARE_MONSTERS_ORDERED = {
    { defId = "item_slime",           name = "吞下物品的史莱姆", level = 3,   area = "慈爱平原", stage = "平原入口" },
    { defId = "rare_bat",             name = "吸血蝙蝠",         level = 7,   area = "垂雾森林", stage = "森林入口" },
    { defId = "wolf_king",            name = "白狼王",           level = 10,  area = "垂雾森林", stage = "森林外围一" },
    { defId = "boar_king",            name = "野猪王",           level = 15,  area = "垂雾森林", stage = "森林外围二" },
    { defId = "chest_goblin",         name = "宝箱哥布林",       level = 19,  area = "慈爱平原", stage = "平原中心" },
    { defId = "young_werewolf",       name = "幼年狼人",         level = 24,  area = "垂雾森林", stage = "森林中心一" },
    { defId = "vampire_girl",         name = "吸血少女",         level = 30,  area = "巴洛庄园", stage = "庄园入口" },
    { defId = "golden_tree_root",     name = "小黄金树根精",     level = 34,  area = "垂雾森林", stage = "森林中心二" },
    { defId = "strange_demon_slime",  name = "奇怪的恶魔史莱姆", level = 38,  area = "慈爱平原", stage = "平原深处" },
    { defId = "skeleton_king",        name = "骷髅王",           level = 42,  area = "慈爱平原", stage = "平原深处的墓地" },
    { defId = "grey_ghost",           name = "\"阿灰\"",         level = 46,  area = "巴洛庄园", stage = "庄园一楼" },
    { defId = "black_bear_king",      name = "黑熊王",           level = 47,  area = "垂雾森林", stage = "森林中心三" },
    { defId = "piano_monster",        name = "钢琴妖怪",         level = 55,  area = "巴洛庄园", stage = "庄园二楼" },
    { defId = "copper_turtle",        name = "铜壳龟",           level = 59,  area = "灰海",     stage = "灰海海岸" },
    { defId = "knight_doll",          name = "骑士人偶",         level = 63,  area = "巴洛庄园", stage = "庄园三楼" },
    { defId = "mummy_pharaoh",        name = "木乃伊法老",       level = 68,  area = "慈爱平原", stage = "墓穴入口" },
    { defId = "golden_giant_tree",    name = "大黄金树根精",     level = 71,  area = "垂雾森林", stage = "森林深处一" },
    { defId = "fishman_warrior",      name = "鱼人战士",         level = 75,  area = "灰海",     stage = "灰海浅滩" },
    { defId = "centaur_priest",       name = "半人马祭司",       level = 80,  area = "灰山",     stage = "灰山脚下森林" },
    { defId = "star_demon_elite",     name = "圆滚滚上等星恶魔", level = 80,  area = "升月堡",   stage = "城下森林入口" },
    { defId = "star_demon_fat_elite", name = "胖乎乎上等星恶魔", level = 84,  area = "升月堡",   stage = "城下森林外围" },
    { defId = "nameless_horror",      name = "形似章鱼的生物",   level = 88,  area = "灰海",     stage = "灰海海边洞窟" },
    { defId = "flower_fairy",         name = "花仙妖精",         level = 92,  area = "垂雾森林", stage = "森林深处二" },
    { defId = "baron_baro",           name = "\"巴洛\"伯爵",     level = 100, area = "巴洛庄园", stage = "庄园四楼" },
    { defId = "cosmos_demon_elite",   name = "上等宇宙恶魔",     level = 100, area = "升月堡",   stage = "城下森林中心" },
    { defId = "fake_chimera",         name = "伪奇美拉",         level = 100, area = "升月堡",   stage = "城下森林深处" },
}

for i, monster in ipairs(RARE_MONSTERS_ORDERED) do
    local mDefId = monster.defId
    local mName  = monster.name
    local mLevel = monster.level
    local questId = "main_freya_bounty_" .. mDefId
    local prevQuestId = i > 1 and ("main_freya_bounty_" .. RARE_MONSTERS_ORDERED[i - 1].defId) or nil

    local def = {
        id   = questId,
        name = "斩首·" .. mName,
        desc = "到" .. monster.area .. "的" .. monster.stage .. "击杀" .. mName .. "（随机出现）。",
        category = M.CATEGORY_MAIN,
        -- 所有斩首任务均为自动接取（第一个在苏醒事件结束时激活）
        triggerType = M.TRIGGER_AUTO,
        submitMode  = M.SUBMIT_JOURNAL,
        npcQuestLine = "freya_bounty",
        npcQuestOrder = i,
        reward = mLevel * 200,
        rewardLabel = "奖励：" .. (mLevel * 200) .. "金",
        onActivate = function(gs, state)
            state.snapshot = { killCount = gs.monsterKillCounts[mDefId] or 0 }
        end,
        onComplete = function(gs)
            gs.changeAffinity("guild_master", 1)
        end,
        checkDone = function(gs, st)
            local base = st and st.snapshot and st.snapshot.killCount or 0
            return (gs.monsterKillCounts[mDefId] or 0) > base
        end,
        progress = function(gs, st)
            local base = st and st.snapshot and st.snapshot.killCount or 0
            local killed = (gs.monsterKillCounts[mDefId] or 0) - base
            local done = killed >= 1 and 1 or 0
            return done, 1, "击杀" .. mName
        end,
    }

    -- 解锁条件：第一个只需要冒险者等级 F 以上，后续需要前置任务完成
    if prevQuestId then
        def.unlockConditions = {
            { type = "quest", questId = prevQuestId },
        }
    else
        def.unlockConditions = {}  -- 第一个斩首任务无前置
    end

    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = def
end

-- 最后一个斩首任务的 ID（用于后续任务前置条件）
local LAST_BOUNTY_ID = "main_freya_bounty_" .. RARE_MONSTERS_ORDERED[#RARE_MONSTERS_ORDERED].defId

-- ====== 灰界大扫除一：通关史莱姆王国 ======
M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
    id   = "main_freya_dungeon1",
    name = "灰界大扫除一",
    desc = "芙蕾雅希望你去清剿史莱姆王国，清除那里的威胁。",
    category = M.CATEGORY_MAIN,
    triggerType = M.TRIGGER_NPC_DIALOGUE,
    triggerData = { npcId = "guild_master_office" },
    unlockConditions = {
        { type = "rank", minRank = 3 },  -- D级以上
    },
    submitMode  = M.SUBMIT_NPC_DIALOGUE,
    submitData  = { npcId = "guild_master_office" },
    npcQuestLine = "freya_dungeon",
    npcQuestOrder = 1,
    acceptDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{咳咳}，公会现在有一个紧急任务。",
            "在慈爱平原发现了魔物的异常活动，一些史莱姆似乎通过某种方式成为了更高级的存在。",
            "这是之前没有观察到过的现象，阿妮塔传来指示，要彻底解决这个事态。",
            '请你到慈爱平原调查一下吧，这片区域的代号是"史莱姆王国"。',
        },
    },
    submitDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{玩家}，史莱姆的麻烦已经解决了，你提交的工作报告我们会仔细研究的。",
            "这是任务奖励，请收下吧。",
        },
    },
    rewardAtLine = 2, -- "请收下吧"
    acceptOptionText = "有什么大型委托吗？",
    submitOptionText = "史莱姆王国已经清剿完毕。",
    reward = 12000,
    rewardLabel = "奖励：12000金",
    onActivate = function(gs, state)
        state.snapshot = { clearCount = gs.dungeonClearCounts["slime_kingdom"] or 0 }
    end,
    onComplete = function(gs)
        gs.changeAffinity("guild_master", 20)
    end,
    checkDone = function(gs, st)
        local base = st and st.snapshot and st.snapshot.clearCount or 0
        return (gs.dungeonClearCounts["slime_kingdom"] or 0) > base
    end,
    progress = function(gs, st)
        local base = st and st.snapshot and st.snapshot.clearCount or 0
        local cleared = (gs.dungeonClearCounts["slime_kingdom"] or 0) - base
        local done = cleared >= 1 and 1 or 0
        return done, 1, "通关史莱姆王国"
    end,
}

-- ====== 灰界大扫除二：通关哥布林竞技场 ======
M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
    id   = "main_freya_dungeon2",
    name = "灰界大扫除二",
    desc = "芙蕾雅委托你清剿哥布林竞技场。",
    category = M.CATEGORY_MAIN,
    triggerType = M.TRIGGER_NPC_DIALOGUE,
    triggerData = { npcId = "guild_master_office" },
    unlockConditions = {
        { type = "quest", questId = "main_freya_dungeon1" },
        { type = "rank", minRank = 4 },  -- C级以上
    },
    submitMode  = M.SUBMIT_NPC_DIALOGUE,
    submitData  = { npcId = "guild_master_office" },
    npcQuestLine = "freya_dungeon",
    npcQuestOrder = 2,
    acceptDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{咳咳}，阿妮塔的指示来了。在慈爱平原深处再次发现了魔物的异常活动。",
            "一些哥布林在它们荒蛮的竞技场中组织决斗，在不断对抗中，族群中似乎诞生了强大的存在。",
            "这对人类很可能是个危险，请你去调查一下哥布林竞技场中的情况，如果有威胁的话就立刻铲除掉。",
        },
    },
    submitDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{玩家}，你的工作成果我们确认了，你真是可靠的冒险者，这是报酬。",
        },
    },
    rewardAtLine = 1, -- "报酬"
    acceptOptionText = "有什么大型委托吗？",
    submitOptionText = "哥布林竞技场已经清剿完毕。",
    reward = 18000,
    rewardLabel = "奖励：18000金",
    onActivate = function(gs, state)
        state.snapshot = { clearCount = gs.dungeonClearCounts["goblin_arena"] or 0 }
    end,
    onComplete = function(gs)
        gs.changeAffinity("guild_master", 20)
    end,
    checkDone = function(gs, st)
        local base = st and st.snapshot and st.snapshot.clearCount or 0
        return (gs.dungeonClearCounts["goblin_arena"] or 0) > base
    end,
    progress = function(gs, st)
        local base = st and st.snapshot and st.snapshot.clearCount or 0
        local cleared = (gs.dungeonClearCounts["goblin_arena"] or 0) - base
        local done = cleared >= 1 and 1 or 0
        return done, 1, "通关哥布林竞技场"
    end,
}

-- ====== 灰界大扫除三：通关潮汐祭祀圣所 ======
M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
    id   = "main_freya_dungeon3",
    name = "灰界大扫除三",
    desc = "芙蕾雅委托你清剿最危险的副本——潮汐祭祀圣所。",
    category = M.CATEGORY_MAIN,
    triggerType = M.TRIGGER_NPC_DIALOGUE,
    triggerData = { npcId = "guild_master_office" },
    unlockConditions = {
        { type = "quest", questId = "main_freya_dungeon2" },
        { type = "rank", minRank = 5 },  -- B级以上
    },
    submitMode  = M.SUBMIT_NPC_DIALOGUE,
    submitData  = { npcId = "guild_master_office" },
    npcQuestLine = "freya_dungeon",
    npcQuestOrder = 3,
    acceptDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{咳咳}，接阿妮塔神谕，在灰海发现了魔物异常活动的迹象。",
            "一些鱼人在海边洞穴里举行祭祀活动，似乎是一种异神崇拜……目前不太清楚里面的具体情况。",
            "请你去调查一下，但是要小心，这个工作很危险，答应我，做好准备再去，好吗？",
        },
    },
    submitDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{玩家}，你能安全回来太好了，这是工作的酬劳。你先好好休息一阵子吧，不要累坏了。",
        },
    },
    rewardAtLine = 1, -- "酬劳"
    acceptOptionText = "有什么大型委托吗？",
    submitOptionText = "潮汐祭祀圣所已经清剿完毕。",
    reward = 24000,
    rewardLabel = "奖励：24000金",
    onActivate = function(gs, state)
        state.snapshot = { clearCount = gs.dungeonClearCounts["tidal_sanctuary"] or 0 }
    end,
    onComplete = function(gs)
        gs.changeAffinity("guild_master", 20)
    end,
    checkDone = function(gs, st)
        local base = st and st.snapshot and st.snapshot.clearCount or 0
        return (gs.dungeonClearCounts["tidal_sanctuary"] or 0) > base
    end,
    progress = function(gs, st)
        local base = st and st.snapshot and st.snapshot.clearCount or 0
        local cleared = (gs.dungeonClearCounts["tidal_sanctuary"] or 0) - base
        local done = cleared >= 1 and 1 or 0
        return done, 1, "通关潮汐祭祀圣所"
    end,
}

-- ====== 进入升月堡 ======
M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
    id   = "main_freya_moonrise",
    name = "进入升月堡",
    desc = "完成所有赏金委托和灰界清剿后，芙蕾雅告诉你升月堡的入口已经开启。",
    category = M.CATEGORY_MAIN,
    triggerType = M.TRIGGER_NPC_DIALOGUE,
    triggerData = { npcId = "guild_master_office" },
    unlockConditions = {
        { type = "quest", questId = LAST_BOUNTY_ID },
        { type = "quest", questId = "main_freya_dungeon3" },
    },
    submitMode  = M.SUBMIT_NPC_DIALOGUE,
    submitData  = { npcId = "guild_master_office" },
    npcQuestLine = "freya_final",
    npcQuestOrder = 1,
    acceptDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{咳咳}，灰界的魔物已经清扫的差不多了。",
            "除了少数难以抵达的区域可能还有威胁，大部分区域相比以前已经清净了。",
            "现在是时候向升月堡的魔王发起总攻了。",
            "魔王是一个非常邪恶的存在，而且善于蛊惑人心，你要坚定。",
            "冒险者/{咳咳}……这是你的使命，阿妮塔、我和镇子都不能接受失去你。",
            "但是，使命就是不惜一切代价都要去做的事情。我……我们等着你凯旋归来！",
        },
    },
    submitDialogue = {
        speaker = "芙蕾雅",
        lines = {
            "冒险者/{玩家}，听说你已经顺利通过升月堡正门桥梁抵达内部了。",
            "你要万分小心，不要受到魔王的蛊惑。",
            "另外，做好准备再继续深入吧，一定要安全回来。我等着看你建立丰功伟业。",
        },
    },
    rewardAtLine = 0, -- 无报酬提及，对话结束后发放
    acceptOptionText = "一切都准备好了吗？",
    submitOptionText = "我已经进入升月堡了。",
    reward = 30000,
    rewardLabel = "奖励：30000金",
    onActivate = function(gs, state)
        state.snapshot = { entered = gs.moonriseFortressEntered or false }
    end,
    onComplete = function(gs)
        gs.changeAffinity("guild_master", 20)
    end,
    checkDone = function(gs, st)
        local wasEntered = st and st.snapshot and st.snapshot.entered or false
        if wasEntered then return false end  -- 接取前就已进入的不算
        return gs.moonriseFortressEntered == true
    end,
    progress = function(gs, st)
        local wasEntered = st and st.snapshot and st.snapshot.entered or false
        local done = (not wasEntered and gs.moonriseFortressEntered == true) and 1 or 0
        return done, 1, "进入升月堡"
    end,
}

-- ====== 杀死魔王 ======
M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
    id   = "main_freya_demon_king",
    name = "杀死魔王",
    desc = "升月堡深处，魔王正等待着最终的挑战者。",
    category = M.CATEGORY_MAIN,
    triggerType = M.TRIGGER_AUTO,
    unlockConditions = {
        { type = "quest", questId = "main_freya_moonrise" },
    },
    submitMode  = M.SUBMIT_JOURNAL,
    npcQuestLine = "freya_final",
    npcQuestOrder = 2,
    reward = 50000,
    rewardLabel = "奖励：50000金",
    onActivate = function(gs, state)
        state.snapshot = { killed = gs.demonKingDefeated or false }
    end,
    onComplete = function(gs)
        gs.changeAffinity("guild_master", 20)
    end,
    checkDone = function(gs, st)
        local wasKilled = st and st.snapshot and st.snapshot.killed or false
        if wasKilled then return false end
        return gs.demonKingDefeated == true
    end,
    progress = function(gs, st)
        local wasKilled = st and st.snapshot and st.snapshot.killed or false
        local done = (not wasKilled and gs.demonKingDefeated == true) and 1 or 0
        return done, 1, "击败魔王"
    end,
}

-- ==========================================================
-- 妮可任务序列（魔物清剿 ×6）
-- ==========================================================

local NICOLE_EXTERMINATE_AREAS = {
    { areaName = "慈爱平原", reward = 2000,
      acceptLines = {
          "冒险者，最近公会发布的魔物清剿任务清单在这里，请你查看。",
          "完成任务可以获得金币奖励哦，对公会帮助大的话，公会还会提高你将来日常委托的奖励。",
          "这次需要进行的是慈爱平原的魔物清剿，请努力吧！",
      },
      submitLines = {
          "公会已经确认了，那么请收下委托酬金。",
          "（因为你的贡献，今后日常委托任务奖励提高了！）",
      },
    },
    { areaName = "垂雾森林", reward = 4000,
      acceptLines = {
          "冒险者，请查看公会最新发布的魔物清剿任务。",
          "这次需要进行的是垂雾森林的魔物清剿，请努力吧！",
      },
      submitLines = {
          "公会已经确认了，那么请收下委托酬金。",
          "冒险者，最近在你的努力下，清水镇周围太平多了，还请多多努力。",
          "（因为你的贡献，今后日常委托任务奖励提高了！）",
      },
    },
    { areaName = "巴洛庄园", reward = 8000,
      acceptLines = {
          "冒险者，请查看公会最新发布的魔物清剿任务。",
          "这次需要进行的是巴洛庄园的魔物清剿，请努力吧！",
      },
      submitLines = {
          "公会已经确认了，公会和居民对你表示由衷的感谢！那么请收下委托酬金。",
          "（因为你的贡献，今后日常委托任务奖励提高了！）",
      },
    },
    { areaName = "灰海",     reward = 16000,
      acceptLines = {
          "冒险者，请查看公会最新发布的魔物清剿任务。",
          "这次需要进行灰海区域的魔物清剿，请努力吧。",
      },
      submitLines = {
          "您的工作结果公会已经确认了，对公会和居民的帮助我们没齿难忘。",
          "那么请收下委托酬金。",
          "（因为你的贡献，今后日常委托任务奖励提高了！）",
      },
    },
    { areaName = "灰山",     reward = 32000,
      acceptLines = {
          "冒险者，请您查看公会最新发布的魔物清剿任务。",
          "这次是灰山区域的魔物清剿。",
      },
      submitLines = {
          "您的努力公会已经确认了，公会不会辜负的，今后也将全力支持您的冒险。",
          "那么请收下委托酬金。",
          "（因为你的贡献，今后日常委托任务奖励提高了！）",
      },
    },
    { areaName = "升月堡",   reward = 50000,
      acceptLines = {
          "冒险者，请查看公会最新发布的魔物清剿任务。",
          "这次是升月堡区域的魔物清剿工作，还请您协助。",
      },
      submitLines = {
          "您辛苦了，真希望有一天灰界能够清净一点，大家都能过上平静的生活。",
          "您的工作结果公会已经确认了，那么请收下委托酬金。",
          "（因为你的贡献，今后日常委托任务奖励提高了！）",
      },
    },
}

local NICOLE_KILL_TARGET = 300  -- 每个区域需要击杀的怪物数

for i, entry in ipairs(NICOLE_EXTERMINATE_AREAS) do
    local areaName = entry.areaName
    local goldReward = entry.reward
    local numLabel = ({ "一", "二", "三", "四", "五", "六" })[i]
    local questId = "side_nicole_exterminate_" .. i
    local prevQuestId = i > 1 and ("side_nicole_exterminate_" .. (i - 1)) or nil

    local def = {
        id   = questId,
        name = "魔物清剿" .. numLabel,
        desc = "妮可发布的委托：在" .. areaName .. "击杀" .. NICOLE_KILL_TARGET .. "只怪物。",
        category = M.CATEGORY_SIDE,
        npc = {
            buildingKey = "guild",
            npcKey      = "guild_receptionist",
            speaker     = "妮可",
        },
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "guild" },
        npcQuestLine = "nicole_exterminate",
        npcQuestOrder = i,
        startLocked = true,
        unlockConditions = prevQuestId
            and { { type = "quest", questId = prevQuestId } }
            or  {},
        acceptDialogue = {
            speaker = "妮可",
            lines = entry.acceptLines,
        },
        submitDialogue = (function()
            local parts = {}
            -- 除最后一行外的都是妮可的台词
            local nicoleLines = {}
            for j = 1, #entry.submitLines - 1 do
                nicoleLines[#nicoleLines + 1] = entry.submitLines[j]
            end
            parts[#parts + 1] = { speaker = "妮可", lines = nicoleLines }
            -- 最后一行是旁白
            parts[#parts + 1] = { speaker = "旁白", lines = { entry.submitLines[#entry.submitLines] } }
            return parts
        end)(),
        rewardAtLine = i <= 3 and 1 or 2, -- "酬金"
        acceptOptionText = i == 1 and "有没有清剿魔物的委托？" or "下一个清剿区域是？",
        reward = goldReward,
        rewardLabel = "奖励：" .. goldReward .. "G",
        onActivate = function(gs, state)
            state.snapshot = { areaKills = gs.areaKillCounts[areaName] or 0 }
        end,
        onComplete = function(gs)
            gs.changeAffinity("guild_receptionist", 20)
        end,
        checkDone = function(gs, st)
            local base = st and st.snapshot and st.snapshot.areaKills or 0
            return (gs.areaKillCounts[areaName] or 0) - base >= NICOLE_KILL_TARGET
        end,
        progress = function(gs, st)
            local base = st and st.snapshot and st.snapshot.areaKills or 0
            local killed = math.max(0, (gs.areaKillCounts[areaName] or 0) - base)
            local done = math.min(killed, NICOLE_KILL_TARGET)
            return done, NICOLE_KILL_TARGET, "在" .. areaName .. "击杀怪物"
        end,
    }

    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = def
end

--- 获取妮可"魔物清剿"任务完成数量（用于委托奖励加成计算）
---@return number completedCount 已完成的清剿任务数量 (0-6)
function M.getNicoleExterminateCompleted()
    local count = 0
    for i = 1, #NICOLE_EXTERMINATE_AREAS do
        local st = M.questStates["side_nicole_exterminate_" .. i]
        if st and st.status == M.STATUS_COMPLETED then
            count = count + 1
        end
    end
    return count
end

---------------------------------------------------------------
-- 朱莉支线：宝石鉴赏 (6 个链式任务)
---------------------------------------------------------------
-- 品质映射: 优秀=uncommon, 稀有=rare, 精良=fine, 卓越=superior
local JULIE_GEM_QUESTS = {
    { rarity = "uncommon", rarityLabel = "优秀", reward = 400,
      acceptLines = {
          "冒险者大人，我有一个工作，不知道你是不是感兴趣呢？",
          "宝石具有一种神奇力量，它们通过影响人类的精神世界，进而提高人类影响现实世界的能力。",
          "人们的勇气、自信和求知等精神力量，正在真切地使他们变强大。",
          "人类需要宝石的力量对抗魔物，但是宝石太稀少了，这种力量不应该被自然所垄断。",
          "因此，我致力于成为一个仿制人造宝石的大师。如果有一天人们能够大量生产增强能力的宝石，那么也许我们可以战胜魔王也说不定？",
          "无论如何，我想试一下。在那之前我要把天然宝石研究透彻。",
          "所以，能请你带一颗优秀品质的宝石给我吗？我会付钱的。",
      },
      submitLines = { "谢谢你，冒险者大人，这是报酬，还请你收下。" },
    },
    { rarity = "rare", rarityLabel = "稀有", reward = 2000,
      acceptLines = {
          "冒险者大人，上次的宝石很有用，但还不够。",
          "能请你带一颗稀有品质的宝石给我吗？报酬不会省略的。",
      },
      submitLines = { "冒险者大人，请收下报酬，谢谢你为我做这件事。" },
    },
    { rarity = "fine", rarityLabel = "精良", reward = 10000,
      acceptLines = { "冒险者大人，嗯……我需要一颗精良品质的宝石以进一步精进研究，麻烦你了。" },
      submitLines = { "它太美丽了……谢谢你，冒险者大人，这是酬劳。" },
    },
    { rarity = "superior", rarityLabel = "卓越", reward = 50000,
      acceptLines = {
          "冒险者大人，研究到了最后一步了，请你带一颗卓越品质的宝石给我。",
          "我知道这是非常稀有的东西，所以我们都得碰运气。如果你有幸得到的话……请你务必要考虑拿来给我，谢谢你！",
      },
      submitLines = { "这是……天呐！冒险者大人，谢谢你，这是报酬，你帮了我太多了……" },
    },
}

-- 宝石品质过滤器工厂
local function makeGemRarityFilter(requiredRarity)
    return function(item, tpl)
        if not tpl then return false end
        return tpl.category == "宝石" and tpl.rarity == requiredRarity
    end
end

-- 任务 1~4: 提交指定品质宝石各 1 颗
for i, entry in ipairs(JULIE_GEM_QUESTS) do
    local questId = "side_julie_gem_" .. i
    local prevQuestId = i > 1 and ("side_julie_gem_" .. (i - 1)) or nil

    local def = {
        id   = questId,
        name = "宝石鉴赏" .. ({ "一", "二", "三", "四" })[i],
        desc = "朱莉想鉴赏一颗" .. entry.rarityLabel .. "品质的宝石。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "jewelry_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "jewelry_shop" },
        npcQuestLine = "julie_gem",
        npcQuestOrder = i,
        acceptDialogue = {
            speaker = "朱莉",
            lines = entry.acceptLines,
        },
        submitDialogue = {
            speaker = "朱莉",
            lines = entry.submitLines,
        },
        rewardAtLine = 1, -- "报酬"/"酬劳"
        acceptOptionText = i == 1 and "你最近在忙什么？" or "还需要宝石吗？",
        submitOptionText = "我带了一颗宝石来给你。",
        submitPrompt = "请提交: " .. entry.rarityLabel .. "品质宝石 x1",
        rejectText = "这不是" .. entry.rarityLabel .. "品质的宝石",
        requireItemFilter = makeGemRarityFilter(entry.rarity),
        reward = entry.reward,
        checkDone = function() return false end,  -- 由 requireItemFilter 提交流程完成
        progress = function(gs)
            return 0, 1, "提交" .. entry.rarityLabel .. "品质宝石"
        end,
        onComplete = function(gs)
            gs.changeAffinity("jewelry_shop_owner", 20)
        end,
    }

    -- 解锁条件
    if prevQuestId then
        def.unlockConditions = { { type = "quest", questId = prevQuestId } }
    else
        def.unlockConditions = {
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 20 end },
        }
    end

    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = def
end

-- 任务 5: 提交 3 颗不同的卓越品质宝石
do
    local questId = "side_julie_gem_5"

    -- 过滤器：卓越品质宝石，且尚未提交过同模板
    local function gemFilter5(item, tpl)
        if not tpl then return false end
        if tpl.category ~= "宝石" or tpl.rarity ~= "superior" then return false end
        -- 检查是否已经提交过这个模板
        local st = M.questStates[questId]
        if st and st.submittedGems then
            for _, gid in ipairs(st.submittedGems) do
                if gid == item.templateId then return false end
            end
        end
        return true
    end

    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = questId,
        name = "巧作天工",
        desc = "朱莉想收集 3 颗不同的卓越品质宝石进行对比鉴赏。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "jewelry_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "jewelry_shop" },
        npcQuestLine = "julie_gem",
        npcQuestOrder = 5,
        unlockConditions = {
            { type = "quest", questId = "side_julie_gem_4" },
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 80 end },
        },
        acceptDialogue = {
            speaker = "朱莉",
            lines = {
                "冒险者大人，我的研究已经有了成果，你给了我很大的帮助，我也想为你做一些事。",
                "如果你能得到三颗卓越品质的宝石的话，拿来给我吧，我会帮你加工成世界上最为强大的宝石。",
            },
        },
        submitDialogue = {
            speaker = "朱莉",
            lines = {
                "没想到你真的能得到三颗这样的宝物，冒险者大人，交给我吧，请你过一阵子再来找我，我需要一些时间加工。",
            },
        },
        rewardAtLine = 0, -- 无报酬提及
        acceptOptionText = "鉴赏进展如何？",
        submitOptionText = "我带了卓越宝石来。",
        submitPrompt = "请提交: 不同的卓越品质宝石（还需 %d 颗）",
        rejectText = "需要卓越品质的宝石，且不能与已提交的重复",
        requireItemFilter = gemFilter5,
        reward = 0,
        checkDone = function() return false end,  -- 由 onItemSubmitted 控制
        progress = function(gs)
            local st = M.questStates[questId]
            local submitted = (st and st.submittedGems) and #st.submittedGems or 0
            return submitted, 3, "提交不同的卓越宝石"
        end,
        --- 每次提交一颗宝石时调用，返回 true 表示全部完成
        onItemSubmitted = function(gs, st, item)
            if not st.submittedGems then st.submittedGems = {} end
            st.submittedGems[#st.submittedGems + 1] = item.templateId
            local tpl = gs.itemTemplates and gs.itemTemplates[item.templateId]
            local itemName = tpl and tpl.name or item.templateId
            print("[QuestManager] 朱莉宝石鉴赏五: 收下 " .. itemName .. " (" .. #st.submittedGems .. "/3)")
            return #st.submittedGems >= 3
        end,
        onComplete = function(gs)
            gs.changeAffinity("jewelry_shop_owner", 20)
        end,
    }
end

-- 任务 6: 巧作天工（第二个自然日后解锁，对话完成，奖励特殊宝石）
do
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "side_julie_gem_6",
        name = "巧作天工二",
        desc = "朱莉说她在准备一件特别的东西，过几天再来找她。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "jewelry_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "jewelry_shop" },
        npcQuestLine = "julie_gem",
        npcQuestOrder = 6,
        unlockConditions = {
            { type = "quest", questId = "side_julie_gem_5" },
            { type = "custom", check = function(gs)
                -- 需要在任务5完成后的第2个自然日才能解锁（使用可信时间防作弊）
                local st5 = M.questStates["side_julie_gem_5"]
                if not st5 or not st5.completedDate then return false end
                GS = GS or require("GameState")
                local trustedTime = GS._getTrustedTime()
                local today = os.date("%Y-%m-%d", trustedTime)
                -- 计算日期差（简化：比较字符串，至少过2天）
                if today <= st5.completedDate then return false end
                -- 计算天数差
                local y1, m1, d1 = st5.completedDate:match("(%d+)-(%d+)-(%d+)")
                local y2, m2, d2 = today:match("(%d+)-(%d+)-(%d+)")
                if not y1 or not y2 then return false end
                local t1 = os.time({ year = tonumber(y1), month = tonumber(m1), day = tonumber(d1) })
                local t2 = os.time({ year = tonumber(y2), month = tonumber(m2), day = tonumber(d2) })
                local daysDiff = math.floor((t2 - t1) / 86400)
                return daysDiff >= 1
            end },
        },
        acceptDialogue = {
            speaker = "朱莉",
            lines = {
                "冒险者大人，请收下吧，这是我今生研究工作的顶峰，希望在您未来的冒险中能对你有所帮助。",
            },
        },
        submitDialogue = {
            speaker = "朱莉",
            lines = {
                "冒险者大人，请收下吧，这是我今生研究工作的顶峰，希望在您未来的冒险中能对你有所帮助。",
            },
        },
        rewardAtLine = 1, -- "收下吧"
        acceptOptionText = "朱莉，你之前说的东西准备好了吗？",
        submitOptionText = "我来拿那颗特别的宝石。",
        reward = 0,
        rewardItems = { { templateId = "gem_rainbow_masterwork", count = 1 } },
        checkDone = function() return true end,  -- 接取即完成（对话完成任务）
        progress = function()
            return 1, 1, "与朱莉交谈"
        end,
        onComplete = function(gs)
            gs.changeAffinity("jewelry_shop_owner", 20)
        end,
    }
end

-- ==========================================================
-- 朱莉面纱重铸（已迁移到委托镶嵌面板的"面纱重铸"分页）
-- ==========================================================

-- 任务5完成时记录日期（用于巧作天工二解锁检查，使用可信时间防作弊）
local orig_doComplete = M._doComplete
M._doComplete = function(questId)
    local result = orig_doComplete(questId)
    if result and questId == "side_julie_gem_5" then
        local st = M.questStates[questId]
        if st then
            st.completedDate = os.date("%Y-%m-%d", GS._getTrustedTime())
        end
    end
    return result
end

-- ==========================================================
-- 莉娜任务序列（巴洛庄园 ×6）
-- 结构：旧家园(1) → 睹物思人一(2) → 睹物思人二(3,lv45) → 睹物思人三(4,lv55) → 睹物思人四(5,lv80) → 红龙与魔女(6,lv90)
-- ==========================================================

-- 巴洛庄园各楼层对应的关卡索引（在 GameState.lua 中定义）
-- STAGE_VAMPIRE_YOUTH = 庄园入口, STAGE_GHOST = 一楼, STAGE_FURNITURE = 二楼
-- STAGE_DOLLS = 三楼, STAGE_VAMPIRES = 四楼

-- 任务 1: 旧家园 — 进入巴洛庄园任意关卡
do
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "side_lina_manor_1",
        name = "旧家园",
        desc = "莉娜希望你替她去一趟巴洛庄园看看，回来向她描述一下巴洛庄园现在的样子。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "potion_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "potion_shop" },
        npc = {
            buildingKey = "potion_shop",
            npcKey      = "potion_shop_owner",
            speaker     = "莉娜",
        },
        startLocked = true,
        unlockConditions = {
            { type = "custom", check = function(gs)
                return (gs.player and gs.player.level or 1) >= 30
            end },
        },
        acceptDialogue = {
            speaker = "莉娜",
            lines = {
                "{玩家}，在清水镇东南方向有一个庄园，名字叫巴洛庄园。",
                "如果你将来到那里的话，能否给我描述一下它现在的样子？",
            },
        },
        submitDialogue = {
            { speaker = "旁白", lines = { "（你向莉娜描述了一下巴洛庄园现在破败的样子……）" } },
            { speaker = "莉娜", lines = { "嗯，我知道了，谢谢你专程跑这么一趟，这是辛苦费，收下吧。" } },
        },
        rewardAtLine = 2, -- "辛苦费，收下吧"
        acceptOptionText = "你好像有心事？",
        submitOptionText = "我去过巴洛庄园了。",
        reward = 1000,
        rewardLabel = "奖励：1000G",
        checkDone = function(gs)
            local s = gs.currentStage
            return s == gs.STAGE_VAMPIRE_YOUTH or s == gs.STAGE_GHOST
                or s == gs.STAGE_FURNITURE or s == gs.STAGE_DOLLS
                or s == gs.STAGE_VAMPIRES
        end,
        progress = function(gs)
            local s = gs.currentStage
            local entered = (s == gs.STAGE_VAMPIRE_YOUTH or s == gs.STAGE_GHOST
                or s == gs.STAGE_FURNITURE or s == gs.STAGE_DOLLS
                or s == gs.STAGE_VAMPIRES)
            return entered and 1 or 0, 1, "进入巴洛庄园"
        end,
        onComplete = function(gs)
            gs.changeAffinity("potion_shop_owner", 20)
        end,
    }
end

-- 任务 2: 睹物思人一 — 提交老旧手帕（巴洛庄园1楼怪物掉落）
-- 解锁条件：完成"旧家园"
do
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "side_lina_manor_2",
        name = "睹物思人一",
        desc = "莉娜拜托你在巴洛庄园一楼寻找旧物。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "potion_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "potion_shop" },
        npc = {
            buildingKey = "potion_shop",
            npcKey      = "potion_shop_owner",
            speaker     = "莉娜",
        },
        startLocked = true,
        unlockConditions = {
            { type = "quest", questId = "side_lina_manor_1" },
        },
        npcQuestLine = "lina_manor",
        npcQuestOrder = 2,
        acceptDialogue = {
            speaker = "莉娜",
            lines = {
                "{玩家}/{爱称}，下次去巴洛庄园时，顺便帮我找一些老物件吧。",
                "在一楼的怪物身上找一找。",
                "我喜欢收集旧的东西，如果找到你觉得我有可能感兴趣的东西就带回来，我会给你报酬的。",
            },
        },
        submitDialogue = {
            speaker = "莉娜",
            lines = {
                "嗯，这个双头鸟家徽和蓝色细线缝边——这张手帕是典型的巴洛庄园风格。",
                "巴洛庄园的每一位管家和女佣都使用这样的手帕。",
                "巴洛……巴洛是一位温柔的家主，至少7年前是如此。",
                "他和清水镇很有渊源，一度为了镇子，从平原到海边，从森林到山脚，到处讨伐魔物。",
                "但是，后来一切都变了。这是报酬，收下吧。",
            },
        },
        rewardAtLine = 5, -- "报酬，收下吧"
        acceptOptionText = "庄园里还有什么让你在意的吗？",
        submitOptionText = "我找到了一些旧物。",
        submitPrompt = "请提交: 老旧手帕",
        rejectText = "这不是我要找的东西",
        requireItemFilter = function(item, tpl)
            return item.templateId == "old_handkerchief"
        end,
        reward = 3000,
        rewardLabel = "奖励：3000G",
        checkDone = function(gs) return false end,
        progress = function(gs)
            local st = M.questStates["side_lina_manor_2"]
            local hasItem = gs.countInventoryItem("old_handkerchief") > 0
            local submitted = st and st.submittedItems and st.submittedItems["old_handkerchief"]
            if submitted then hasItem = true end
            local done = submitted and 1 or 0
            return done, 1, "提交老旧手帕", {
                { hasItem and 1 or 0, 1, "获取老旧手帕" },
                { done, 1, "提交老旧手帕" },
            }
        end,
        onItemSubmitted = function(gs, st, item)
            if not st.submittedItems then st.submittedItems = {} end
            st.submittedItems[item.templateId] = true
            return true
        end,
        onComplete = function(gs)
            gs.changeAffinity("potion_shop_owner", 20)
        end,
    }
end

-- 任务 3: 睹物思人二 — 提交老旧胸针（巴洛庄园2楼怪物掉落）
-- 解锁条件：完成"睹物思人一"(side_lina_manor_2) + 等级45
do
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "side_lina_manor_3",
        name = "睹物思人二",
        desc = "莉娜拜托你在巴洛庄园二楼寻找旧物。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "potion_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "potion_shop" },
        npc = {
            buildingKey = "potion_shop",
            npcKey      = "potion_shop_owner",
            speaker     = "莉娜",
        },
        startLocked = true,
        unlockConditions = {
            { type = "quest", questId = "side_lina_manor_2" },
            { type = "custom", check = function(gs)
                return (gs.player and gs.player.level or 1) >= 45
            end },
        },
        npcQuestLine = "lina_manor",
        npcQuestOrder = 3,
        acceptDialogue = {
            speaker = "莉娜",
            lines = {
                "{玩家}/{爱称}，上次的物品我很满意，接下来去巴洛庄园二楼试试吧。",
                "在怪物身上获得有价值的老旧物品就带回来给我，我会付费。",
            },
        },
        submitDialogue = {
            speaker = "莉娜",
            lines = {
                "这是巴洛庄园的女主人薇拉最喜欢用的胸针！你是在哪找到的？",
                "薇拉是一位美人，出生于清水镇。相夫教子，她很称职，在巴洛年少时就和他结婚了。",
                "我记得薇拉结婚时请画师给她画了一张笑容灿烂的画，她本来邀请巴洛一起，但巴洛拒绝了，他说那太累了。",
                "薇拉的温柔光辉就在此处闪烁，她一贯乐于接纳别人所做的选择，而且自得其乐。",
                "即使是在结婚时，丈夫不愿和自己共同步入一副画框也是如此。",
                "嗯……我想想，画上的薇拉一袭黑色礼服，金褐色的长发在阳光下闪闪发光，戴着誓约戒指，笑容灿烂……",
                "那时的幸福一去不返了。这是报酬，收下吧。",
            },
        },
        rewardAtLine = 7, -- "报酬，收下吧"
        acceptOptionText = "庄园里还有什么让你在意的吗？",
        submitOptionText = "我找到了一些旧物。",
        submitPrompt = "请提交: 老旧胸针",
        rejectText = "这不是我要找的东西",
        requireItemFilter = function(item, tpl)
            return item.templateId == "old_brooch"
        end,
        reward = 5000,
        rewardLabel = "奖励：5000G",
        checkDone = function(gs) return false end,
        progress = function(gs)
            local st = M.questStates["side_lina_manor_3"]
            local hasItem = gs.countInventoryItem("old_brooch") > 0
            local submitted = st and st.submittedItems and st.submittedItems["old_brooch"]
            if submitted then hasItem = true end
            local done = submitted and 1 or 0
            return done, 1, "提交老旧胸针", {
                { hasItem and 1 or 0, 1, "获取老旧胸针" },
                { done, 1, "提交老旧胸针" },
            }
        end,
        onItemSubmitted = function(gs, st, item)
            if not st.submittedItems then st.submittedItems = {} end
            st.submittedItems[item.templateId] = true
            return true
        end,
        onComplete = function(gs)
            gs.changeAffinity("potion_shop_owner", 20)
        end,
    }
end

-- 任务 4: 睹物思人三 — 提交老旧怀表（巴洛庄园3楼怪物掉落）
-- 解锁条件：完成"睹物思人二"(side_lina_manor_3) + 等级55
do
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "side_lina_manor_4",
        name = "睹物思人三",
        desc = "莉娜拜托你在巴洛庄园三楼寻找旧物。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "potion_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "potion_shop" },
        npc = {
            buildingKey = "potion_shop",
            npcKey      = "potion_shop_owner",
            speaker     = "莉娜",
        },
        startLocked = true,
        unlockConditions = {
            { type = "quest", questId = "side_lina_manor_3" },
            { type = "custom", check = function(gs)
                return (gs.player and gs.player.level or 1) >= 55
            end },
        },
        npcQuestLine = "lina_manor",
        npcQuestOrder = 4,
        acceptDialogue = {
            speaker = "莉娜",
            lines = {
                "{玩家}/{爱称}，这次要不去巴洛庄园三楼试试？",
                "在三楼的怪物身上看看有什么有价值的老旧物品。",
            },
        },
        submitDialogue = {
            speaker = "莉娜",
            lines = {
                "巴洛的怀表！这你都能拿到！",
                "巴洛是一个非常重视时间观念的人，似乎是和他年少时的经历有关。",
                "他有时候看着怀表读出时间的读数，7点、8点、9点、10点半……他经常念叨。",
                "生命是很残酷的，巴洛在灰界已经是非常强大的存在，但是也抵抗不了时间之神的腐蚀。",
                "他想反抗，犯下了致命的错误。这是报酬，收下吧。",
            },
        },
        rewardAtLine = 5, -- "报酬，收下吧"
        acceptOptionText = "庄园里还有什么让你在意的吗？",
        submitOptionText = "我找到了一些旧物。",
        submitPrompt = "请提交: 老旧怀表",
        rejectText = "这不是我要找的东西",
        requireItemFilter = function(item, tpl)
            return item.templateId == "old_pocket_watch"
        end,
        reward = 7000,
        rewardLabel = "奖励：7000G",
        checkDone = function(gs) return false end,
        progress = function(gs)
            local st = M.questStates["side_lina_manor_4"]
            local hasItem = gs.countInventoryItem("old_pocket_watch") > 0
            local submitted = st and st.submittedItems and st.submittedItems["old_pocket_watch"]
            if submitted then hasItem = true end
            local done = submitted and 1 or 0
            return done, 1, "提交老旧怀表", {
                { hasItem and 1 or 0, 1, "获取老旧怀表" },
                { done, 1, "提交老旧怀表" },
            }
        end,
        onItemSubmitted = function(gs, st, item)
            if not st.submittedItems then st.submittedItems = {} end
            st.submittedItems[item.templateId] = true
            return true
        end,
        onComplete = function(gs)
            gs.changeAffinity("potion_shop_owner", 20)
        end,
    }
end

-- 任务 5: 睹物思人四 — 提交老旧狮子玩偶（巴洛庄园4楼怪物掉落）
-- 解锁条件：完成"睹物思人三"(side_lina_manor_4) + 等级80
do
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "side_lina_manor_5",
        name = "睹物思人四",
        desc = "莉娜拜托你到巴洛庄园四楼寻找旧物。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "potion_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "potion_shop" },
        npc = {
            buildingKey = "potion_shop",
            npcKey      = "potion_shop_owner",
            speaker     = "莉娜",
        },
        startLocked = true,
        unlockConditions = {
            { type = "quest", questId = "side_lina_manor_4" },
            { type = "custom", check = function(gs)
                return (gs.player and gs.player.level or 1) >= 80
            end },
        },
        npcQuestLine = "lina_manor",
        npcQuestOrder = 5,
        acceptDialogue = {
            speaker = "莉娜",
            lines = {
                "{玩家}/{爱称}，你拿回来的东西很有帮助。",
                "你成长了，我对你的能力有信心，我有个不情之请，能不能到巴洛庄园四楼找一下有没有什么老旧的东西？",
                "拿回来给我吧。",
            },
        },
        submitDialogue = {
            { speaker = "莉娜", lines = {
                "这是……这个玩偶是我的童年伙伴。",
                "{玩家}/{爱称}，我……我是巴洛的女儿，而巴洛曾经是清水镇的冒险者。",
                "他非常强大，为清水镇付出了自己的全部；他坚信自己的使命就是要杀死魔王……",
                "直到他站到升月堡前，他连门都进不去，那桥上的石像鬼几乎坚不可摧。",
                "我了解巴洛，他不怕死，他怕使命未竞，但岁月追杀，人终究会老。",
                "为了……延长自己的寿命，他走上了错误的道路——他想成神。",
            }},
            { speaker = "莉娜", lines = {
                "不好意思，我说得太多烦到你了吧。",
                "不知道为什么，我现在有勇气面对这个世界了。这是报酬，收下吧。",
            }},
        },
        rewardAtLine = 8, -- "报酬，收下吧"
        acceptOptionText = "庄园里还有什么让你在意的吗？",
        submitOptionText = "我找到了一些旧物。",
        submitPrompt = "请提交: 老旧狮子玩偶",
        rejectText = "这不是我要找的东西",
        requireItemFilter = function(item, tpl)
            return item.templateId == "old_lion_doll"
        end,
        reward = 10000,
        rewardLabel = "奖励：10000G",
        checkDone = function(gs) return false end,
        progress = function(gs)
            local st = M.questStates["side_lina_manor_5"]
            local hasItem = gs.countInventoryItem("old_lion_doll") > 0
            local submitted = st and st.submittedItems and st.submittedItems["old_lion_doll"]
            if submitted then hasItem = true end
            local done = submitted and 1 or 0
            return done, 1, "提交老旧狮子玩偶", {
                { hasItem and 1 or 0, 1, "获取老旧狮子玩偶" },
                { done, 1, "提交老旧狮子玩偶" },
            }
        end,
        onItemSubmitted = function(gs, st, item)
            if not st.submittedItems then st.submittedItems = {} end
            st.submittedItems[item.templateId] = true
            return true
        end,
        onComplete = function(gs)
            gs.changeAffinity("potion_shop_owner", 20)
        end,
    }
end

-- 任务 6: 红龙与魔女 — 击杀红龙幼龙 x1，解锁异世深渊
-- 解锁条件：完成"睹物思人四"(side_lina_manor_5) + 等级90
do
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "side_lina_manor_6",
        name = "红龙与魔女",
        desc = "莉娜告诉你，城下深窟开阔区有一只红龙幼龙镇守，它的龙血结界阻止了她用符文开启深渊通道。击杀红龙后，莉娜便可以远程开启异世深渊。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "potion_shop" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "potion_shop" },
        npc = {
            buildingKey = "potion_shop",
            npcKey      = "potion_shop_owner",
            speaker     = "莉娜",
        },
        startLocked = true,
        unlockConditions = {
            { type = "quest", questId = "side_lina_manor_5" },
            { type = "custom", check = function(gs)
                return (gs.player and gs.player.level or 1) >= 90
            end },
        },
        npcQuestLine = "lina_manor",
        npcQuestOrder = 6,
        acceptDialogue = {
            speaker = "莉娜",
            lines = {
                "{玩家}/{爱称}，其实，在巴洛死后，我也一直在寻找进入升月堡，击败魔王的方法。",
                "我试过寻找捷径和密径，但是没有找到，所以唯有变得更强这一种方法。",
                "这些年我不是毫无收获，在升月堡城下有一个深窟，穿过狭窄通道可以达到一个开阔区，",
                "古书记载深窟底部有一个通往异世界的深渊，那里的魔物比这个世界更为强大，但是那里有极为强大的武装。",
                "我钻研此事好几年了，已经熟练掌握了开启深渊通道的符文，",
                "但是现在那里有一只……红龙幼龙镇守，红龙是一种神奇的生物，它的龙血能够张开结界，屏蔽远古的魔法。",
                "杀死红龙后回来找我，只要没了红龙的魔力庇佑，我可以远程用符文开启深渊的通道。",
            },
        },
        submitDialogue = {
            { speaker = "莉娜", lines = {
                "你杀死红龙幼龙了，我能感知到，我的魔力现在可以穿梭到深窟底部了。",
            }},
            { speaker = "旁白", lines = {
                "（莉娜闭上眼睛，磅礴的魔力从她的体内奔涌而出，直冲向窗框、门框、烟囱……",
                "冲向整个房间每一处通往外界的缝隙。有什么东西变化了，你的直觉告诉你。）",
            }},
            { speaker = "莉娜", lines = {
                "呼……深渊的通道已经打开了。",
                "去吧，{玩家}/{爱称}，完成巴洛……不，完成你自己的使命！",
                "灰界只有你能拯救了！我……我相信你。",
            }},
        },
        rewardAtLine = 0, -- 无报酬提及，对话结束后发放
        acceptOptionText = "莉娜，你还有什么想拜托我的吗？",
        submitOptionText = "红龙幼龙已经被我击败了。",
        reward = 30000,
        rewardLabel = "奖励：30000G",
        onActivate = function(gs, state)
            state.snapshot = { killCount = gs.monsterKillCounts["red_dragon_young"] or 0 }
        end,
        checkDone = function(gs, st)
            local base = st and st.snapshot and st.snapshot.killCount or 0
            return (gs.monsterKillCounts["red_dragon_young"] or 0) - base >= 1
        end,
        progress = function(gs, st)
            local base = st and st.snapshot and st.snapshot.killCount or 0
            local killed = math.max(0, (gs.monsterKillCounts["red_dragon_young"] or 0) - base)
            return math.min(killed, 1), 1, "击杀红龙幼龙"
        end,
        onComplete = function(gs)
            gs.changeAffinity("potion_shop_owner", 20)
            gs.abyssUnlocked = true
            print("[Quest] 莉娜任务6（红龙与魔女）完成：解锁异世深渊")
        end,
    }
end

-- ==========================================================
-- 艾莉雅任务序列（灰界旅行 ×7 主线）
-- ==========================================================
do
    local NUM_LABELS = { "一", "二", "三", "四", "五", "六", "七" }

    local ELIYA_TRAVEL_QUESTS = {
        {
            areaId = "clearwater", areaName = "清水镇",
            bg = "image/cg_grey_travel.png",
            level = 0,
            acceptLines = {
                "{玩家}/{爱称}，我近期想在灰界到处看看，你有空的话就一起吧？反正闲着也是闲着，不是吗？",
            },
            dialogue = {
                { speaker = "艾莉雅", text = "清水镇，灰界人类最后的庇护之所。这个镇子的祥和并非全无代价。" },
                { speaker = "艾莉雅", text = "阿瑞忒——也就是你们通常所称之阿妮塔——在清水镇布下结界，让魔物无法靠近，但是与此同时也把灰界其他地界的统治权让渡给了卡吉雅。" },
                { speaker = "艾莉雅", text = "这是一场战争，而这样的战争已经进行了无数次，不止这个世界在战争，还有无数个世界在战争。" },
            },
        },
        {
            areaId = "mercy_plain", areaName = "慈爱平原",
            bg = "image/cg_grey_travel_2.png",
            level = 20,
            acceptLines = {
                "{玩家}/{爱称}，我近期想在灰界到处看看，你有空的话就一起吧？下一站是慈爱平原。",
            },
            dialogue = {
                { speaker = "艾莉雅", text = "慈爱平原，多好的风光啊，如果没有人类和魔物的斗争，魔物在这里也可以安静地生活吧？" },
                { speaker = "艾莉雅", text = "你想过为什么人类和魔物要这样千百年的斗争吗？因为阿妮塔和卡吉雅都不会允许，这是灰界的游戏规则。" },
                { speaker = "艾莉雅", text = "神明，到底是什么样的存在呢？又如何才能成为神明呢？" },
                { speaker = "艾莉雅", text = "每一个物种都在倾尽全力地存活下去，每一个物种中都不乏有强烈成神愿望的个体。只是像史莱姆和哥布林这样的智力，很难真正理解成神这件事情罢了。" },
            },
        },
        {
            areaId = "mist_forest", areaName = "垂雾森林",
            bg = "image/cg_grey_travel_3.png",
            level = 30,
            acceptLines = {
                "{玩家}/{爱称}，我近期想在灰界到处看看，你有空的话就一起吧？下一站是垂雾森林。",
            },
            dialogue = {
                { speaker = "艾莉雅", text = "垂雾森林，这里的雾气沉降是最近百年的现象。上个世纪我经过时，这里还是阳光明媚、生机勃勃。" },
                { speaker = "艾莉雅", text = "我猜想是森林中的树精和花仙正在觉醒，他们长出双脚和羽翼，渴望着成为更高阶的存在。" },
                { speaker = "艾莉雅", text = "与自然沟通是他们的本能，然而，驱动自然的魔法力量污染了介质，魔法粒子混杂在空气中形成了魔雾，这就是雾气沉降的本质了。" },
                { speaker = "艾莉雅", text = "你不好奇吗？我对这些都很好奇。" },
            },
        },
        {
            areaId = "barlow_manor", areaName = "巴洛庄园",
            bg = "image/cg_grey_travel_4.png",
            level = 40,
            acceptLines = {
                "{玩家}/{爱称}，我近期想在灰界到处看看，你有空的话就一起吧？下一站是巴洛庄园。",
            },
            dialogue = {
                { speaker = "艾莉雅", text = "巴洛，伟大的冒险者，上一任第三意志。他确实足够努力，但是这个世界中的游戏规则不是由他制定的。" },
                { speaker = "艾莉雅", text = "一颗棋子要怎么在棋盘中战胜棋手呢？答案只有一个——先成为棋手。巴洛想通了这个道理，但是他在道路上一错再错。" },
                { speaker = "艾莉雅", text = "时间不等人，寿命无几的巴洛必须先解决寿命问题。他想借吸血鬼的长生之力，为自己主动引来诅咒，可凡人身躯怎么承受神降的诅咒呢？" },
                { speaker = "艾莉雅", text = "他疯了，这是他自找的。" },
            },
        },
        {
            areaId = "grey_sea", areaName = "灰海",
            bg = "image/cg_grey_travel_5.png",
            level = 50,
            acceptLines = {
                "{玩家}/{爱称}，我近期想在灰界到处看看，你有空的话就一起吧？下一站是灰海。",
            },
            dialogue = {
                { speaker = "艾莉雅", text = "灰海，一望无际。是为屏障，即众神为棋盘所划之界，人类和魔物均无法穿越。" },
                { speaker = "艾莉雅", text = "有无数人问过这个问题，海的对面是什么？我也不知道，但是我猜那里什么都没有，灰界为灰神所创，无法观测之处自然无需浪费神力。" },
                { speaker = "艾莉雅", text = "灰海亦是远古异神的居所，鱼人群落在漫长的岁月中诞生了来自神秘低语的异神崇拜。鱼人意识到自己无法成神，就召唤外神以谋求庇护。" },
                { speaker = "艾莉雅", text = "阿妮塔为了抵挡神秘低语的入侵，降下神力，让灰海陷入永恒静寂。" },
            },
        },
        {
            areaId = "grey_mountain", areaName = "灰山",
            bg = "image/cg_grey_travel_6.png",
            level = 70,
            acceptLines = {
                "{玩家}/{爱称}，我近期想在灰界到处看看，你有空的话就一起吧？下一站是灰山。",
            },
            dialogue = {
                { speaker = "艾莉雅", text = "灰山，高耸入云，大刀阔斧。是为屏障之二，灰山和灰海联合为一体，拦住了想要离开棋盘的一切生物。" },
                { speaker = "艾莉雅", text = "灰山之巅筑有一座高塔，名为无限塔。古书记载，传为神明所建，无限塔其高为无穷尽之数，但也有人说，此乃成神之路。" },
                { speaker = "艾莉雅", text = "我指引你一条登山之路吧，你可以自己去看。" },
            },
        },
        {
            areaId = "moonrise_fort", areaName = "升月堡",
            bg = "image/cg_grey_travel_7.png",
            level = 90,
            acceptLines = {
                "{玩家}/{爱称}，我近期想在灰界到处看看，你有空的话就一起吧？下一站是升月堡。",
            },
            dialogue = {
                { speaker = "艾莉雅", text = "升月堡，卡吉雅之居所，就如清水镇乃阿妮塔之居所一般。到了此处，灰界旅行宣告结束了。" },
                { speaker = "艾莉雅", text = "我已来过无数遍，真正旅行之人是你。{玩家}/{爱称}，我还是不懂，人类和魔物为何要争斗不休呢？" },
                { speaker = "艾莉雅", text = "同样是寻求成神，同样是互相杀戮，又为什么吾等即为正义，魔物即为邪恶呢？" },
                { speaker = "艾莉雅", text = "你是谁？为什么要来到这里？谁又在牵着你走？你的内心深处，由你自己之意志所诉说的那一句话，此时此刻是什么呢？" },
            },
        },
    }

    -- 区域映射表（供 Renderer_Panels / Input 查询）
    M.ELIYA_TRAVEL_AREA_MAP = {}

    for i, entry in ipairs(ELIYA_TRAVEL_QUESTS) do
        local questId = "main_eliya_travel_" .. i
        local prevQuestId = i > 1 and ("main_eliya_travel_" .. (i - 1)) or nil

        -- 构建解锁条件
        local unlock = {}
        if prevQuestId then
            unlock[#unlock + 1] = { type = "quest", questId = prevQuestId }
        end
        if entry.level > 0 then
            unlock[#unlock + 1] = { type = "custom", check = function(gs)
                return (gs.player and gs.player.level or 1) >= entry.level
            end }
        end

        local def = {
            id   = questId,
            name = "灰界旅行" .. NUM_LABELS[i],
            desc = "与艾莉雅一起前往" .. entry.areaName .. "，感受灰界的风景与故事。",
            category = M.CATEGORY_MAIN,
            triggerType = M.TRIGGER_NPC_DIALOGUE,
            triggerData = { npcId = "forest_elf" },
            submitMode  = M.SUBMIT_AUTO,
            npc = {
                buildingKey = "forest_elf",
                npcKey      = "forest_elf",
                speaker     = "艾莉雅",
            },
            startLocked = true,
            unlockConditions = #unlock > 0 and unlock or nil,
            acceptDialogue = {
                speaker = "艾莉雅",
                lines = entry.acceptLines,
            },
            acceptOptionText = i == 1 and "你想出去走走吗？" or "还想去别的地方看看吗？",
            reward = 0,
            rewardLabel = "奖励：好感度+20",
            checkDone = function(gs)
                return gs.eliyaTravelDone and gs.eliyaTravelDone[questId]
            end,
            progress = function(gs)
                local done = gs.eliyaTravelDone and gs.eliyaTravelDone[questId]
                return done and 1 or 0, 1, "前往" .. entry.areaName .. "旅行"
            end,
            onComplete = function(gs)
                gs.changeAffinity("forest_elf", 20)
                if i == 6 then
                    -- 解锁无限塔
                    gs.infiniteTowerUnlocked = true
                    print("[Quest] 艾莉雅旅行任务6完成：解锁无限塔")
                end
            end,
        }

        M.QUEST_DEFS[#M.QUEST_DEFS + 1] = def

        -- 填充区域映射
        M.ELIYA_TRAVEL_AREA_MAP[questId] = {
            areaId   = entry.areaId,
            areaName = entry.areaName,
            dialogue = entry.dialogue,
            bg       = entry.bg,
        }
    end
end

-- ====== 安吉莉娅任务序列（5个） ======
-- 任务1-2：酒馆肉搏（望向舞池自动触发）
-- 任务3-5：灰海旅行（地图关卡触发）
do
    -- ── 任务1：酒馆肉搏 ──
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "main_angelica_brawl_1",
        name = "酒馆肉搏",
        desc = "酒馆舞池突然冲出几个喝醉的男人骚扰安吉莉娅，替她教训他们。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_AUTO,
        startLocked = true,
        unlockConditions = {
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 10 end },
        },
        npcQuestLine = "angelica",
        npcQuestOrder = 1,
        rewardLabel = "奖励：勿忘我效果提升",
        checkDone = function(gs)
            return gs.tavernBrawlState and gs.tavernBrawlState.questId == "main_angelica_brawl_1"
                   and gs.tavernBrawlState.done
        end,
        progress = function(gs)
            if gs.tavernBrawlState and gs.tavernBrawlState.questId == "main_angelica_brawl_1" then
                return gs.tavernBrawlState.killCount or 0, 3, "击败混混"
            end
            return 0, 3, "击败混混"
        end,
        onComplete = function(gs)
            gs.changeAffinity("tavern_dancer", 20)
            gs.forgetMeNotLevel = math.max(gs.forgetMeNotLevel or 0, 1)
            gs.recalcStats(gs.player)
            gs.tavernBrawlState = nil
            print("[Quest] 安吉莉娅任务1完成：好感+20, 勿忘我Lv." .. gs.forgetMeNotLevel)
        end,
        _brawlThugCount = 3,
    }

    -- ── 任务2：酒馆肉搏二 ──
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "main_angelica_brawl_2",
        name = "酒馆肉搏二",
        desc = "上次的混混又来找你的麻烦了，解决他们。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_EVENT,
        submitMode  = M.SUBMIT_AUTO,
        startLocked = true,
        unlockConditions = {
            { type = "quest", questId = "main_angelica_brawl_1" },
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 25 end },
        },
        npcQuestLine = "angelica",
        npcQuestOrder = 2,
        rewardLabel = "奖励：勿忘我效果提升",
        checkDone = function(gs)
            return gs.tavernBrawlState and gs.tavernBrawlState.questId == "main_angelica_brawl_2"
                   and gs.tavernBrawlState.done
        end,
        progress = function(gs)
            if gs.tavernBrawlState and gs.tavernBrawlState.questId == "main_angelica_brawl_2" then
                return gs.tavernBrawlState.killCount or 0, 4, "击败混混"
            end
            return 0, 4, "击败混混"
        end,
        onComplete = function(gs)
            gs.changeAffinity("tavern_dancer", 20)
            gs.forgetMeNotLevel = math.max(gs.forgetMeNotLevel or 0, 2)
            gs.recalcStats(gs.player)
            gs.tavernBrawlState = nil
            print("[Quest] 安吉莉娅任务2完成：好感+20, 勿忘我Lv." .. gs.forgetMeNotLevel)
        end,
        _brawlThugCount = 4,
    }

    -- ── 任务3：看海的准备（NPC对话触发，击杀灰海100怪物） ──
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = {
        id   = "main_angelica_travel_1",
        name = "看海的准备",
        desc = "安吉莉娅请你确认灰海的安全，去扫荡灰海的魔物吧。",
        category = M.CATEGORY_SIDE,
        triggerType = M.TRIGGER_NPC_DIALOGUE,
        triggerData = { npcId = "tavern_dancefloor" },
        submitMode  = M.SUBMIT_NPC_DIALOGUE,
        submitData  = { npcId = "tavern_dancefloor" },
        npc = {
            buildingKey = "tavern_dancefloor",
            npcKey      = "tavern_dancer",
            speaker     = "安吉莉娅",
        },
        startLocked = true,
        unlockConditions = {
            { type = "quest", questId = "main_angelica_brawl_2" },
            { type = "custom", check = function(gs) return (gs.player and gs.player.level or 1) >= 55 end },
        },
        npcQuestLine = "angelica",
        npcQuestOrder = 3,
        acceptDialogue = {
            speaker = "安吉莉娅",
            lines = {
                "{玩家}/{爱称}，我有一个不情之请，我……我想去灰海边看看。",
                "但是我不了解清水镇外面魔物的情况，可以请你帮我看一下灰海那里是否安全吗？",
                "我没有什么可以给你的，我知道这很过分，但我只能拜托你了……",
            },
        },
        acceptOptionText = "你想出去走走吗？",
        submitDialogue = {
            { speaker = "安吉莉娅", lines = {
                "{玩家}/{爱称}，你说你帮我清理了那里的魔物？太感谢了！",
                "这样的话，我就可以完成她的心愿了……等我准备好了，再拜托你可以吗？",
            }},
            { speaker = "旁白", lines = {
                "（你在安吉莉娅的脸上同时看到了期待、快乐、紧张、如释重负等等情绪叠加的色彩。最主要的是……她好漂亮。）",
            }},
            { speaker = "旁白", lines = {
                "（你对安吉莉娅的印象加深了，\"勿忘我\"效果提升！）",
            }},
        },
        rewardAtLine = 0, -- 无报酬提及
        reward = 0,
        rewardLabel = "奖励：勿忘我效果提升",
        -- 击杀计数：接取时记录快照，之后累计差值
        onActivate = function(gs)
            -- 记录接取时各灰海关卡的击杀快照
            local snapshot = 0
            if gs.areaKillCounts then
                for areaName, count in pairs(gs.areaKillCounts) do
                    if areaName:find("^灰海") then
                        snapshot = snapshot + count
                    end
                end
            end
            gs._angelicaSeaKillSnapshot = snapshot
            print("[Quest] 看海的准备：记录灰海击杀快照=" .. snapshot)
        end,
        checkDone = function(gs)
            local total = 0
            if gs.areaKillCounts then
                for areaName, count in pairs(gs.areaKillCounts) do
                    if areaName:find("^灰海") then
                        total = total + count
                    end
                end
            end
            local snapshot = gs._angelicaSeaKillSnapshot or 0
            return (total - snapshot) >= 100
        end,
        progress = function(gs)
            local total = 0
            if gs.areaKillCounts then
                for areaName, count in pairs(gs.areaKillCounts) do
                    if areaName:find("^灰海") then
                        total = total + count
                    end
                end
            end
            local snapshot = gs._angelicaSeaKillSnapshot or 0
            local killed = math.min(total - snapshot, 100)
            if killed < 0 then killed = 0 end
            return killed, 100, "在灰海击杀怪物"
        end,
        onComplete = function(gs)
            gs.changeAffinity("tavern_dancer", 20)
            gs.forgetMeNotLevel = math.max(gs.forgetMeNotLevel or 0, 3)
            gs.recalcStats(gs.player)
            gs._angelicaSeaKillSnapshot = nil
            print("[Quest] 安吉莉娅任务3完成：好感+20, 勿忘我Lv." .. gs.forgetMeNotLevel)
        end,
    }

    -- ── 任务4：她要去的地方（灰海旅行关卡，地图按钮触发） ──
    local ANGELICA_TRAVEL_QUESTS = {
        {
            id = "main_angelica_travel_2",
            name = "她要去的地方",
            desc = "安吉莉娅终于可以去看海了，带她前往灰海边。",
            areaId = "grey_sea",
            areaName = "灰海浅滩",
            bg = "image/cg_angelica_sea.png",
            battleBg = "image/bg_grey_sea.jpg",
            level = 65,
            prevQuest = "main_angelica_travel_1",
            order = 4,
            dialogue = {
                { speaker = "旁白", text = "（灰海，挂在岸边。是一整片悬浮的死寂。）" },
                { speaker = "旁白", text = "（浪前仆后继，但却没有一丝生机。你寻找着这种违和感的来源，恍然发现，面前的这一片空间里竟然没有一点声响。）" },
                { speaker = "旁白", text = "（本该存在的水与水碰撞和挤压的声音，在这里并不存在；本该存在的浪涌上沙滩、拍打岩石的声音，在这里并不存在。）" },
                { speaker = "旁白", text = "（安吉莉娅朝着灰海海边走去，她脱下鞋子，雪白的双脚踩在沙滩上的\"啪啪\"声是这片空间存在着声音传播介质的唯一证明。）" },
                { speaker = "安吉莉娅", text = "妈妈……" },
                { speaker = "旁白", text = "（你远远看到安吉莉娅拿出一个瓶子，将瓶中的粉末慢慢洒向了大海。海水在浮动，安吉莉娅洁白的脚踝时隐时现。）" },
                { speaker = "旁白", text = "（她开始旋转……你知道，那是为了她生命中最重要的观众而起舞。）" },
            },
            submitDialogue = {
                { speaker = "安吉莉娅", lines = {
                    "{玩家}/{爱称}，我妈妈病死前说她想在死后葬在大海里，我承诺她一定。",
                    "过去，我常常害怕自己无法兑现，但是，幸好有你。",
                }},
                { speaker = "安吉莉娅", lines = {
                    "{玩家}/{爱称}，我们走吧，谢谢你。",
                }},
                { speaker = "旁白", lines = {
                    "（安吉莉娅转身向返回清水镇的方向离开，你跟了上去。）",
                }},
                { speaker = "安吉莉娅", lines = {
                    "{玩家}/{爱称}，你和其他男人不一样，感觉很可靠，能遇到你真是太好了……",
                }},
                { speaker = "旁白", lines = {
                    "（你对安吉莉娅的印象加深了，\"勿忘我\"的精神力量你已铭记在心，永远不会忘记。）",
                }},
            },
        },
    }

    M.ANGELICA_TRAVEL_AREA_MAP = {}

    for _, entry in ipairs(ANGELICA_TRAVEL_QUESTS) do
        local questId = entry.id
        local unlock = {}
        if entry.prevQuest then
            unlock[#unlock + 1] = { type = "quest", questId = entry.prevQuest }
        end
        if entry.level > 0 then
            local lvReq = entry.level
            unlock[#unlock + 1] = { type = "custom", check = function(gs)
                return (gs.player and gs.player.level or 1) >= lvReq
            end }
        end

        local submitDlg = entry.submitDialogue
        local def = {
            id   = questId,
            name = entry.name,
            desc = entry.desc,
            category = M.CATEGORY_SIDE,
            triggerType = M.TRIGGER_NPC_DIALOGUE,
            triggerData = { npcId = "tavern_dancefloor" },
            submitMode  = M.SUBMIT_AUTO,
            npc = {
                buildingKey = "tavern_dancefloor",
                npcKey      = "tavern_dancer",
                speaker     = "安吉莉娅",
            },
            startLocked = true,
            unlockConditions = #unlock > 0 and unlock or nil,
            npcQuestLine = "angelica",
            npcQuestOrder = entry.order,
            acceptDialogue = {
                speaker = "安吉莉娅",
                lines = {
                    "{玩家}/{爱称}，去海边的事情，我已经准备好了，能否请你陪我去呢？",
                    "我……我很害怕，如果遇到魔物的话……",
                    "真的可以吗？太好了！那我们随时出发！",
                },
            },
            acceptOptionText = "她准备好了吗？",
            reward = 0,
            rewardLabel = "奖励：勿忘我变为永久效果",
            checkDone = function(gs)
                return gs.angelicaTravelDone and gs.angelicaTravelDone[questId]
            end,
            progress = function(gs)
                local done = gs.angelicaTravelDone and gs.angelicaTravelDone[questId]
                return done and 1 or 0, 1, "与安吉莉娅一起前往灰海边"
            end,
            submitDialogue = submitDlg,
            rewardAtLine = 0, -- 无报酬提及
            onComplete = function(gs)
                gs.changeAffinity("tavern_dancer", 20)
                gs.forgetMeNotLevel = math.max(gs.forgetMeNotLevel or 0, 4)
                gs.forgetMeNotPermanent = true
                gs.recalcStats(gs.player)
                print("[Quest] 安吉莉娅任务4完成：好感+20, 勿忘我变为永久效果")
            end,
        }

        M.QUEST_DEFS[#M.QUEST_DEFS + 1] = def

        M.ANGELICA_TRAVEL_AREA_MAP[questId] = {
            areaId   = entry.areaId,
            areaName = entry.areaName,
            dialogue = entry.dialogue,
            postDialogue = entry.submitDialogue,  -- 关卡对话后的附加对话
            bg       = entry.bg or nil,
            battleBg = entry.battleBg or nil,
        }
    end
end

--- 获取当前激活的安吉莉娅旅行任务列表
---@return table[] { questId, areaId, dialogue }
function M.getActiveAngelicaTravelQuests()
    local result = {}
    for questId, info in pairs(M.ANGELICA_TRAVEL_AREA_MAP) do
        local st = M.questStates[questId]
        if st and st.status == M.STATUS_ACTIVE then
            local def = nil
            for _, d in ipairs(M.QUEST_DEFS) do
                if d.id == questId then def = d break end
            end
            result[#result + 1] = {
                questId   = questId,
                questName = def and def.name or info.areaName,
                areaId    = info.areaId,
                areaName  = info.areaName,
                dialogue  = info.dialogue,
            }
        end
    end
    return result
end

-- ==========================================================
-- 迪芬旅行任务（复仇）地图注册
-- ==========================================================
M.DIFEN_TRAVEL_AREA_MAP = {
    ["side_difen_revenge"] = {
        areaId   = "mist_forest",
        areaName = "垂雾森林",
        -- 战斗事件配置：对话播完后进入 EventManager 事件关卡
        battleEventId = "difen_revenge",
        dialogue = {
            -- 前往任务关卡（战前对话）
            { speaker = "旁白", text = "（出发前你看到迪芬的时候，他全副武装，穿着一套银制的盔甲。行为举止显然由于不适应这种重量而略显笨拙。）" },
            { speaker = "迪芬", text = "别笑我，我怕死。" },
            { speaker = "旁白", text = "（你们来到垂雾森林，迪芬领着你在林间娴熟地穿梭，就像一条鱼滑翔在自己的池塘里一样。）" },
            { speaker = "旁白", text = "（你问他，是不是经常来森林。他边走边说，只来过一次，但是这条路我在脑海里已经走了成千上万次了。）" },
            { speaker = "旁白", text = "（最终，你们来到一处矿洞，看起来很普通，里面隐约有风吹出。）" },
            { speaker = "迪芬", text = "不知道它在不在里面。" },
            { speaker = "旁白", text = "（迪芬在洞口呆站了一会儿，你看到他双肩耸动，似乎做了几次深呼吸。随后，他给了你一个眼神，让你跟上。）" },
            { speaker = "旁白", text = "（你们在洞里穿行，一些野兽的唾液和粪便的气息混杂在空气流动中。突然，矿洞中传出一声熊的咆哮。）" },
            { speaker = "迪芬", text = "终于到了这一天，{玩家}，谢谢你陪我到这里。" },
            { speaker = "迪芬", text = "就是这畜生杀了我的父亲，一会儿你不要插手，我要亲手为他报仇。" },
            { speaker = "迪芬", text = "除非……除非我没能做到，到时候请你帮我最后一个忙——杀了它。" },
            -- ↑ 对话结束后自动进入 battleEventId 指定的战斗事件
            -- 战后对话和 postDialogue 由事件关卡内部处理
        },
        postDialogue = {
            -- [5] 回到清水镇
            { speaker = "迪芬", lines = {
                "人类真是很奇怪，我现在反而感觉心里很空……我会帮约瑟夫找个地方呆着，你不用担心。",
                "无论如何，感谢你，{玩家}，你帮我完成了我一生的愿望。",
                "这个项链是我父亲留给我的，现在给你吧——作为谢礼。",
            }},
        },
        bg = nil,
    },
}

--- 获取当前激活的迪芬旅行任务列表
---@return table[] { questId, areaId, dialogue }
function M.getActiveDifenTravelQuests()
    local result = {}
    for questId, info in pairs(M.DIFEN_TRAVEL_AREA_MAP) do
        local st = M.questStates[questId]
        if st and st.status == M.STATUS_ACTIVE then
            local def = nil
            for _, d in ipairs(M.QUEST_DEFS) do
                if d.id == questId then def = d break end
            end
            result[#result + 1] = {
                questId   = questId,
                questName = def and def.name or info.areaName,
                areaId    = info.areaId,
                areaName  = info.areaName,
                dialogue  = info.dialogue,
            }
        end
    end
    return result
end

--- 获取当前激活的酒馆肉搏任务（若有）
---@return table|nil { questId, thugCount }
function M.getActiveBrawlQuest()
    -- 1. 先查找已激活的肉搏任务
    for _, def in ipairs(M.QUEST_DEFS) do
        if def._brawlThugCount then
            local st = M.questStates[def.id]
            if st and st.status == M.STATUS_ACTIVE then
                return { questId = def.id, thugCount = def._brawlThugCount }
            end
        end
    end
    -- 2. 没有已激活的 → 尝试激活满足解锁条件的 TRIGGER_EVENT 肉搏任务
    GS = GS or require("GameState")
    for _, def in ipairs(M.QUEST_DEFS) do
        if def._brawlThugCount then
            local st = M.questStates[def.id]
            if st and st.status == M.STATUS_LOCKED then
                local conditions = getEffectiveUnlockConditions(def)
                if checkUnlockConditions(conditions, GS, M.questStates) then
                    M.activateQuest(def.id)
                    print("[QuestManager] 肉搏任务自动激活: " .. def.name)
                    return { questId = def.id, thugCount = def._brawlThugCount }
                end
            end
        end
    end
    return nil
end

--- 获取当前激活的艾莉雅旅行任务列表
---@return table[] { questId, areaId, dialogue }
function M.getActiveEliyaTravelQuests()
    local result = {}
    for questId, info in pairs(M.ELIYA_TRAVEL_AREA_MAP) do
        local st = M.questStates[questId]
        if st and st.status == M.STATUS_ACTIVE then
            local def = nil
            for _, d in ipairs(M.QUEST_DEFS) do
                if d.id == questId then def = d break end
            end
            result[#result + 1] = {
                questId   = questId,
                questName = def and def.name or info.areaName,
                areaId    = info.areaId,
                areaName  = info.areaName,
                dialogue  = info.dialogue,
            }
        end
    end
    return result
end

-- 快速查找表  id → def
local defById = {}
for _, def in ipairs(M.QUEST_DEFS) do
    defById[def.id] = def
end

--- 注册新任务定义（供外部模块动态追加任务）
---@param def table 任务定义
function M.registerQuest(def)
    M.QUEST_DEFS[#M.QUEST_DEFS + 1] = def
    defById[def.id] = def
    -- 初始化状态
    if not M.questStates[def.id] then
        if def.startLocked or getEffectiveTriggerType(def) == M.TRIGGER_EVENT then
            M.questStates[def.id] = { status = M.STATUS_LOCKED }
        else
            local conditions = getEffectiveUnlockConditions(def)
            if conditions and #conditions > 0 then
                M.questStates[def.id] = { status = M.STATUS_LOCKED }
            else
                M.questStates[def.id] = { status = M.STATUS_ACTIVE }
            end
        end
    end
end

--- 批量注册任务定义
---@param defs table[] 任务定义列表
function M.registerQuests(defs)
    for _, def in ipairs(defs) do
        M.registerQuest(def)
    end
end

--- 按 id 获取任务定义
---@param questId string
---@return table|nil
function M.getQuestDef(questId)
    return defById[questId]
end

---------------------------------------------------------------
-- 运行时状态（由 init / applySaveData 填充）
-- questStates[id] = { status = "locked"/"active"/"ready"/"completed" }
---------------------------------------------------------------
M.questStates = {}

---------------------------------------------------------------
-- 初始化 / 重置
---------------------------------------------------------------
function M.init()
    M.questStates = {}
    for _, def in ipairs(M.QUEST_DEFS) do
        local trigger = getEffectiveTriggerType(def)
        if trigger == M.TRIGGER_EVENT or trigger == M.TRIGGER_SCENE_ENTER or trigger == M.TRIGGER_NPC_DIALOGUE then
            -- 需要外部触发才激活
            M.questStates[def.id] = { status = M.STATUS_LOCKED }
        else
            -- TRIGGER_AUTO: 检查解锁条件
            local conditions = getEffectiveUnlockConditions(def)
            if conditions and #conditions > 0 then
                M.questStates[def.id] = { status = M.STATUS_LOCKED }
            else
                M.questStates[def.id] = { status = M.STATUS_ACTIVE }
            end
        end
    end
end

---------------------------------------------------------------
-- 手动激活任务（由事件脚本调用，兼容所有触发类型）
---------------------------------------------------------------
function M.activateQuest(questId)
    local st = M.questStates[questId]
    if st and st.status == M.STATUS_LOCKED then
        st.status = M.STATUS_ACTIVE
        local def = defById[questId]
        -- 调用 onActivate 保存快照数据（用于"接取后才计数"机制）
        if def and def.onActivate then
            GS = GS or require("GameState")
            def.onActivate(GS, st)
        end
        local name = def and def.name or questId
        print("[QuestManager] 任务激活: " .. name)
        -- 立即刷新：检查新激活的任务是否已满足完成条件
        M.update()
        return true
    end
    return false
end

---------------------------------------------------------------
-- 场景进入触发（由场景切换逻辑调用）
-- 检查所有 triggerType="scene_enter" 且解锁条件满足的任务
---@param sceneId string 当前进入的场景 ID
---@return string[] 被激活的任务 ID 列表
---------------------------------------------------------------
function M.onSceneEnter(sceneId)
    GS = GS or require("GameState")
    local activated = {}
    for _, def in ipairs(M.QUEST_DEFS) do
        local st = M.questStates[def.id]
        if st and st.status == M.STATUS_LOCKED then
            local trigger = getEffectiveTriggerType(def)
            if trigger == M.TRIGGER_SCENE_ENTER then
                local td = def.triggerData
                if td and td.sceneId == sceneId then
                    -- 检查解锁条件
                    local conditions = getEffectiveUnlockConditions(def)
                    if checkUnlockConditions(conditions, GS, M.questStates) then
                        M.activateQuest(def.id)
                        activated[#activated + 1] = def.id
                        print("[QuestManager] 场景触发任务激活: " .. def.name .. " (场景: " .. sceneId .. ")")
                    end
                end
            end
        end
        -- 同时检查 submitMode="scene_trigger" 的已激活任务是否需要自动完成
        if st and st.status == M.STATUS_READY then
            local submit = getEffectiveSubmitMode(def)
            if submit == M.SUBMIT_SCENE_TRIGGER then
                local sd = def.submitData
                if sd and sd.sceneId == sceneId then
                    M._doComplete(def.id)
                    print("[QuestManager] 场景触发任务自动完成: " .. def.name)
                end
            end
        end
    end
    return activated
end

---------------------------------------------------------------
-- NPC 对话触发（由对话系统调用）
-- 检查某 NPC 是否有可触发的任务，返回可接取的任务列表
---@param npcId string NPC ID
---@return table[] 可接取的任务列表 { {def=..., questId=...}, ... }
---------------------------------------------------------------
function M.getNpcTriggerQuests(npcId)
    GS = GS or require("GameState")
    local result = {}
    for _, def in ipairs(M.QUEST_DEFS) do
        local st = M.questStates[def.id]
        if st and st.status == M.STATUS_LOCKED then
            local trigger = getEffectiveTriggerType(def)
            if trigger == M.TRIGGER_NPC_DIALOGUE then
                local td = def.triggerData
                local matchNpc = (td and td.npcId == npcId)
                    or (not td and def.npc and def.npc.buildingKey == npcId)
                if matchNpc then
                    local conditions = getEffectiveUnlockConditions(def)
                    if checkUnlockConditions(conditions, GS, M.questStates) then
                        result[#result + 1] = { def = def, questId = def.id }
                    end
                end
            end
        end
    end
    return result
end

--- 通过 NPC 对话接取任务
---@param npcId string NPC ID
---@param questId string 任务 ID
---@return boolean 是否成功
function M.tryNpcTrigger(npcId, questId)
    local def = defById[questId]
    if not def then return false end
    local trigger = getEffectiveTriggerType(def)
    if trigger ~= M.TRIGGER_NPC_DIALOGUE then return false end
    local td = def.triggerData
    local matchNpc = (td and td.npcId == npcId)
        or (not td and def.npc and def.npc.buildingKey == npcId)
    if not matchNpc then return false end
    return M.activateQuest(questId)
end

---------------------------------------------------------------
-- NPC 对话提交（由对话系统调用）
-- 检查某 NPC 处是否有可提交的任务
---@param npcId string NPC ID
---@return table[] 可提交的任务列表 { {def=..., questId=...}, ... }
---------------------------------------------------------------
function M.getNpcSubmitQuests(npcId)
    local result = {}
    for _, def in ipairs(M.QUEST_DEFS) do
        local st = M.questStates[def.id]
        if st then
            local submit = getEffectiveSubmitMode(def)
            if submit == M.SUBMIT_NPC_DIALOGUE then
                local sd = def.submitData
                if sd and sd.npcId == npcId then
                    -- requireItemFilter 任务在 ACTIVE 状态即可提交（提交即完成）
                    if st.status == M.STATUS_READY then
                        result[#result + 1] = { def = def, questId = def.id }
                    elseif st.status == M.STATUS_ACTIVE and def.requireItemFilter then
                        result[#result + 1] = { def = def, questId = def.id }
                    end
                end
            end
        end
    end
    return result
end

--- 通过 NPC 对话提交任务
---@param npcId string NPC ID
---@param questId string 任务 ID
---@return boolean 是否成功
function M.tryNpcSubmit(npcId, questId)
    local def = defById[questId]
    if not def then return false end
    local submit = getEffectiveSubmitMode(def)
    if submit ~= M.SUBMIT_NPC_DIALOGUE then return false end
    local sd = def.submitData
    if not sd or sd.npcId ~= npcId then return false end
    local st = M.questStates[questId]
    if not st or st.status ~= M.STATUS_READY then return false end
    return M._doComplete(questId)
end

---------------------------------------------------------------
-- 每日任务重置（由公告板刷新时调用）
---------------------------------------------------------------
function M.resetDailyQuests()
    GS = GS or require("GameState")
    for _, def in ipairs(M.QUEST_DEFS) do
        if def.daily then
            M.questStates[def.id] = { status = M.STATUS_ACTIVE }
            print("[QuestManager] 每日任务重置: " .. def.name)
        end
    end
    GS.dailyBulletinDoneCount = 0
end

---------------------------------------------------------------
-- 辅助：解析任务的物品奖励和金币奖励（支持动态 getRewardItems）
-- 返回 rewardItems, reward（金币）
---------------------------------------------------------------
function M.resolveRewards(def)
    GS = GS or require("GameState")
    if def.getRewardItems then
        local items, gold = def.getRewardItems(GS)
        return items, gold or def.reward
    end
    return def.rewardItems, def.reward
end

---------------------------------------------------------------
-- 内部：完成任务并发放奖励
---@param questId string
---@return boolean
---------------------------------------------------------------
function M._doComplete(questId)
    GS = GS or require("GameState")
    local st = M.questStates[questId]
    if not st or (st.status ~= M.STATUS_READY) then
        return false
    end
    st.status = M.STATUS_COMPLETED
    local def = defById[questId]
    if def then
        -- 消耗所需物品（NPC 提交类任务）
        if def.requireItems then
            for _, ri in ipairs(def.requireItems) do
                GS.removeInventoryItem(ri.templateId, ri.count or 1)
                local tpl = GS.itemTemplates and GS.itemTemplates[ri.templateId]
                local itemName = tpl and tpl.name or ri.templateId
                print("[QuestManager] 消耗物品: " .. itemName .. " x" .. (ri.count or 1))
            end
        end
        -- 解析奖励（支持动态 getRewardItems）
        local resolvedItems, resolvedGold = M.resolveRewards(def)
        -- 金币奖励
        local goldAmt = resolvedGold or 0
        if goldAmt > 0 then
            GS.gold = (GS.gold or 0) + goldAmt
            print("[QuestManager] 任务奖励: +" .. goldAmt .. " 金币")
        end
        -- 物品奖励
        if resolvedItems then
            for _, ri in ipairs(resolvedItems) do
                for _ = 1, (ri.count or 1) do
                    local _, _, addedItem = GS.addToInventory(ri.templateId)
                    -- 卓越任务装备：必定随机附魔 + 随机精炼槽/宝石槽
                    if addedItem and (ri.templateId == "difen_legacy_necklace" or ri.templateId == "blacksmith_belt") then
                        local tier = GS.getTierByLevel(addedItem.level or 1)
                        addedItem.tier = tier
                        GS.rollEnchantment(addedItem, tier)
                        GS.rollRefineSlots(addedItem, tier)
                        GS.rollGemSlots(addedItem)
                        print("[QuestManager] 卓越装备自动附魔: " .. ri.templateId .. " tier=" .. tier)
                    end
                    -- "朱莉"的面纱：随机赋予一条深渊词缀作为镶嵌效果
                    if addedItem and ri.templateId == "gem_rainbow_masterwork" then
                        local pool = GS.ABYSS_AFFIX_POOL
                        local roll = pool[math.random(#pool)]
                        addedItem.abyssAffix = {
                            id = roll.id,
                            name = roll.name,
                            desc = roll.desc,
                            mechanic = roll.mechanic,
                        }
                        print("[QuestManager] 朱莉面纱随机深渊词缀: " .. roll.name)
                        -- 随机赋予一条主属性+3
                        local mainStats = {"str","wis","agi","con","foc","per","wil","luk","cha"}
                        local picked = mainStats[math.random(#mainStats)]
                        addedItem.gemEffect = { [picked] = 3 }
                        print("[QuestManager] 朱莉面纱随机主属性: " .. picked .. "+3")
                    end
                end
                local tpl = GS.itemTemplates[ri.templateId]
                local itemName = tpl and tpl.name or ri.templateId
                print("[QuestManager] 任务奖励: +" .. (ri.count or 1) .. " " .. itemName)
            end
        end
        -- 布告栏任务累计完成计数（前2次给3000G，第3次起给感恩礼券）
        if questId == "side_daily_bulletin" then
            GS.bulletinQuestTotalDone = (GS.bulletinQuestTotalDone or 0) + 1
            print("[QuestManager] 布告栏任务累计完成: " .. GS.bulletinQuestTotalDone .. " 次")
        end
        -- 完成回调
        if def.onComplete then
            def.onComplete(GS)
        end
        print("[QuestManager] 任务提交完成: " .. def.name)
    end
    -- 立即刷新（可能触发链式解锁）
    M.update()
    return true
end

---------------------------------------------------------------
-- 内部：完成任务但不发放奖励（用于延迟发放模式）
-- 仅标记状态为已完成、消耗所需物品、刷新链式解锁
---@param questId string
---@return boolean
---------------------------------------------------------------
function M._doCompleteNoReward(questId)
    GS = GS or require("GameState")
    local st = M.questStates[questId]
    if not st or (st.status ~= M.STATUS_READY) then
        return false
    end
    st.status = M.STATUS_COMPLETED
    local def = defById[questId]
    if def then
        -- 消耗所需物品（NPC 提交类任务）
        if def.requireItems then
            for _, ri in ipairs(def.requireItems) do
                GS.removeInventoryItem(ri.templateId, ri.count or 1)
                local tpl = GS.itemTemplates and GS.itemTemplates[ri.templateId]
                local itemName = tpl and tpl.name or ri.templateId
                print("[QuestManager] 消耗物品: " .. itemName .. " x" .. (ri.count or 1))
            end
        end
        -- 记录完成日期（用于后续任务解锁的日期检查，使用可信时间防作弊）
        if questId == "side_julie_gem_5" then
            if st then st.completedDate = os.date("%Y-%m-%d", GS._getTrustedTime()) end
        end
        print("[QuestManager] 任务标记完成(延迟发放奖励): " .. (def.name or questId))
    end
    -- 立即刷新（可能触发链式解锁）
    M.update()
    return true
end

---------------------------------------------------------------
-- 内部：发放指定任务的奖励（金币、物品、回调）
-- 与 _doCompleteNoReward 配合使用，在对话指定行触发
---@param questId string
---------------------------------------------------------------
function M._doGiveRewards(questId)
    GS = GS or require("GameState")
    local def = defById[questId]
    if not def then return end
    -- 防重复发放
    local st = M.questStates[questId]
    if st and st._rewardsGiven then return end
    if st then st._rewardsGiven = true end
    -- 解析奖励（支持动态 getRewardItems）
    local resolvedItems, resolvedGold = M.resolveRewards(def)
    -- 金币奖励
    local goldAmt = resolvedGold or 0
    if goldAmt > 0 then
        GS.gold = (GS.gold or 0) + goldAmt
        print("[QuestManager] 延迟奖励发放: +" .. goldAmt .. " 金币")
    end
    -- 物品奖励
    if resolvedItems then
        for _, ri in ipairs(resolvedItems) do
            for _ = 1, (ri.count or 1) do
                local _, _, addedItem = GS.addToInventory(ri.templateId)
                -- 卓越任务装备：必定随机附魔 + 随机精炼槽/宝石槽
                if addedItem and (ri.templateId == "difen_legacy_necklace" or ri.templateId == "blacksmith_belt") then
                    local tier = GS.getTierByLevel(addedItem.level or 1)
                    addedItem.tier = tier
                    GS.rollEnchantment(addedItem, tier)
                    GS.rollRefineSlots(addedItem, tier)
                    GS.rollGemSlots(addedItem)
                    print("[QuestManager] 卓越装备自动附魔: " .. ri.templateId .. " tier=" .. tier)
                end
                -- "朱莉"的面纱：随机赋予一条深渊词缀作为镶嵌效果
                if addedItem and ri.templateId == "gem_rainbow_masterwork" then
                    local pool = GS.ABYSS_AFFIX_POOL
                    local roll = pool[math.random(#pool)]
                    addedItem.abyssAffix = {
                        id = roll.id,
                        name = roll.name,
                        desc = roll.desc,
                        mechanic = roll.mechanic,
                    }
                    print("[QuestManager] 朱莉面纱随机深渊词缀: " .. roll.name)
                    -- 随机赋予一条主属性+3
                    local mainStats = {"str","wis","agi","con","foc","per","wil","luk","cha"}
                    local picked = mainStats[math.random(#mainStats)]
                    addedItem.gemEffect = { [picked] = 3 }
                    print("[QuestManager] 朱莉面纱随机主属性: " .. picked .. "+3")
                end
            end
            local tpl = GS.itemTemplates[ri.templateId]
            local itemName = tpl and tpl.name or ri.templateId
            print("[QuestManager] 延迟奖励发放: +" .. (ri.count or 1) .. " " .. itemName)
        end
    end
    -- 完成回调（好感度变化等）
    if def.onComplete then
        def.onComplete(GS)
    end
    print("[QuestManager] 任务奖励已发放: " .. (def.name or questId))
end

---------------------------------------------------------------
-- 通过 NPC 对话提交任务（延迟发放奖励版）
---@param npcId string NPC ID
---@param questId string 任务 ID
---@return boolean 是否成功
---------------------------------------------------------------
function M.tryNpcSubmitDeferred(npcId, questId)
    local def = defById[questId]
    if not def then return false end
    local submit = getEffectiveSubmitMode(def)
    if submit ~= M.SUBMIT_NPC_DIALOGUE then return false end
    local sd = def.submitData
    if not sd or sd.npcId ~= npcId then return false end
    local st = M.questStates[questId]
    if not st or st.status ~= M.STATUS_READY then return false end
    return M._doCompleteNoReward(questId)
end

---------------------------------------------------------------
-- 每帧/定期调用：刷新所有任务状态
-- 1. active → ready（checkDone 达成）
-- 2. ready → completed（submitMode="auto" 时自动完成）
-- 3. locked → active（解锁条件满足 + triggerType="auto"）
---------------------------------------------------------------
function M.update()
    GS = GS or require("GameState")
    local changed = true
    while changed do
        changed = false
        for _, def in ipairs(M.QUEST_DEFS) do
            local st = M.questStates[def.id]
            if not st then
                st = { status = M.STATUS_LOCKED }
                M.questStates[def.id] = st
            end

            -- active → locked（肉搏任务运行时状态丢失后恢复）
            -- tavernBrawlState 不会被保存，重启后为 nil，导致任务永远完不了
            if st.status == M.STATUS_ACTIVE and def._brawlThugCount and not GS.tavernBrawlState then
                st.status = M.STATUS_LOCKED
                changed = true
                print("[QuestManager] 肉搏任务运行时状态丢失，重置为 LOCKED: " .. def.name)
            end

            -- active → ready（目标达成）
            if st.status == M.STATUS_ACTIVE then
                if def.checkDone(GS, st) then
                    local submit = getEffectiveSubmitMode(def)
                    if submit == M.SUBMIT_AUTO then
                        -- 自动提交：直接完成
                        st.status = M.STATUS_READY
                        M._doComplete(def.id)
                        changed = true
                        print("[QuestManager] 任务自动完成: " .. def.name)
                    else
                        st.status = M.STATUS_READY
                        changed = true
                        print("[QuestManager] 任务目标达成，待提交: " .. def.name)
                    end
                end
            end

            -- ready → active（物品不足时回退，仅限 requireItems 类任务）
            if st.status == M.STATUS_READY and def.requireItems then
                if not def.checkDone(GS, st) then
                    st.status = M.STATUS_ACTIVE
                    changed = true
                    print("[QuestManager] 任务条件不再满足，回退: " .. def.name)
                end
            end

            -- locked → active（解锁条件满足 + 触发类型为 auto）
            if st.status == M.STATUS_LOCKED then
                local trigger = getEffectiveTriggerType(def)
                if trigger == M.TRIGGER_AUTO then
                    local conditions = getEffectiveUnlockConditions(def)
                    if checkUnlockConditions(conditions, GS, M.questStates) then
                        M.activateQuest(def.id)
                        changed = true
                        print("[QuestManager] 任务自动解锁: " .. def.name)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------
-- 查询接口
---------------------------------------------------------------

--- 获取所有激活中（含待提交）的主线任务列表
---@return table[]
function M.getActiveMainQuests()
    local result = {}
    for _, def in ipairs(M.QUEST_DEFS) do
        if def.category == M.CATEGORY_MAIN then
            local st = M.questStates[def.id]
            if st and (st.status == M.STATUS_ACTIVE or st.status == M.STATUS_READY) then
                result[#result + 1] = { def = def, state = st }
            end
        end
    end
    return result
end

--- 获取所有激活中（含待提交）的支线任务列表
function M.getActiveSideQuests()
    local result = {}
    for _, def in ipairs(M.QUEST_DEFS) do
        if def.category == M.CATEGORY_SIDE then
            local st = M.questStates[def.id]
            if st and (st.status == M.STATUS_ACTIVE or st.status == M.STATUS_READY) then
                result[#result + 1] = { def = def, state = st }
            end
        end
    end
    return result
end

--- 手动提交任务（日志按钮调用，兼容旧逻辑）
---@param questId string
---@return boolean success
function M.submitQuest(questId)
    local def = defById[questId]
    if def then
        local submit = getEffectiveSubmitMode(def)
        -- 只有 journal 提交方式才允许从日志按钮提交
        if submit ~= M.SUBMIT_JOURNAL then
            print("[QuestManager] 任务 " .. def.name .. " 不支持日志提交 (submitMode=" .. submit .. ")")
            return false
        end
    end
    return M._doComplete(questId)
end

--- 按 id 获取任务状态
function M.getQuestStatus(questId)
    local st = M.questStates[questId]
    return st and st.status or M.STATUS_LOCKED
end

--- 判断任务是否可以在日志界面显示提交按钮
---@param questId string
---@return boolean
function M.canJournalSubmit(questId)
    local def = defById[questId]
    if not def then return false end
    local st = M.questStates[questId]
    if not st or st.status ~= M.STATUS_READY then return false end
    local submit = getEffectiveSubmitMode(def)
    return submit == M.SUBMIT_JOURNAL
end

---------------------------------------------------------------
-- 存档 / 读档
---------------------------------------------------------------

--- 收集存档数据
function M.collectSaveData()
    local data = {}
    for id, st in pairs(M.questStates) do
        local hasExtra = st.snapshot or st.submittedGems or st.completedDate or st.submittedItems
        if hasExtra then
            local entry = { status = st.status }
            if st.snapshot then entry.snapshot = st.snapshot end
            if st.submittedGems then entry.submittedGems = st.submittedGems end
            if st.completedDate then entry.completedDate = st.completedDate end
            if st.submittedItems then entry.submittedItems = st.submittedItems end
            data[id] = entry
        else
            data[id] = st.status
        end
    end
    return data
end

--- 应用存档数据
function M.applySaveData(data)
    GS = GS or require("GameState")
    if not data then
        -- 旧存档：根据当前游戏状态智能初始化，不做链式自动完成
        M.questStates = {}
        for _, def in ipairs(M.QUEST_DEFS) do
            -- "第三意志"/"清水镇的人们"：苏醒事件完成后激活
            if def.id == "main_third_will" or def.id == "side_townspeople" then
                if GS.awakeningCompleted then
                    M.questStates[def.id] = { status = M.STATUS_ACTIVE }
                else
                    M.questStates[def.id] = { status = M.STATUS_LOCKED }
                end
            -- 等级提升系列：只激活当前目标等级的任务
            elseif def.id:find("^main_rank_") then
                if def.checkDone(GS, M.questStates[def.id]) then
                    M.questStates[def.id] = { status = M.STATUS_COMPLETED }
                elseif def.prerequisite then
                    local preState = M.questStates[def.prerequisite]
                    if preState and preState.status == M.STATUS_COMPLETED then
                        M.questStates[def.id] = { status = M.STATUS_ACTIVE }
                    else
                        M.questStates[def.id] = { status = M.STATUS_LOCKED }
                    end
                else
                    if GS.eventCompleted and GS.eventCompleted["initial_supply"] then
                        M.questStates[def.id] = { status = M.STATUS_ACTIVE }
                    else
                        M.questStates[def.id] = { status = M.STATUS_LOCKED }
                    end
                end
            else
                -- 其他任务走默认逻辑
                local conditions = getEffectiveUnlockConditions(def)
                if not conditions or #conditions == 0 then
                    M.questStates[def.id] = { status = M.STATUS_ACTIVE }
                else
                    M.questStates[def.id] = { status = M.STATUS_LOCKED }
                end
            end
        end
        return
    end
    M.questStates = {}
    -- 迁移旧存档：side_freya_* → main_freya_*
    for id, val in pairs(data) do
        if type(id) == "string" and id:find("^side_freya_") then
            local newId = id:gsub("^side_freya_", "main_freya_")
            if not data[newId] then
                data[newId] = val
            end
            data[id] = nil
        end
    end
    -- 先恢复存档中的状态（兼容旧格式 string 和新格式 table）
    for id, val in pairs(data) do
        if type(val) == "table" then
            local st = { status = val.status }
            if val.snapshot then st.snapshot = val.snapshot end
            if val.submittedGems then st.submittedGems = val.submittedGems end
            if val.completedDate then st.completedDate = val.completedDate end
            if val.submittedItems then st.submittedItems = val.submittedItems end
            M.questStates[id] = st
        else
            M.questStates[id] = { status = val }
        end
    end
    -- 对存档中未记录的新任务初始化
    for _, def in ipairs(M.QUEST_DEFS) do
        if not M.questStates[def.id] then
            local trigger = getEffectiveTriggerType(def)
            if trigger == M.TRIGGER_EVENT or trigger == M.TRIGGER_SCENE_ENTER or trigger == M.TRIGGER_NPC_DIALOGUE then
                M.questStates[def.id] = { status = M.STATUS_LOCKED }
            else
                local conditions = getEffectiveUnlockConditions(def)
                if conditions and #conditions > 0 then
                    M.questStates[def.id] = { status = M.STATUS_LOCKED }
                else
                    M.questStates[def.id] = { status = M.STATUS_ACTIVE }
                end
            end
        end
    end
    -- 迁移：面纱重铸任务已删除，清理旧存档中残留的任务状态
    do
        if M.questStates["side_julie_veil_reforge"] then
            M.questStates["side_julie_veil_reforge"] = nil
        end
        if M.questStates["side_julie_veil_pickup"] then
            M.questStates["side_julie_veil_pickup"] = nil
        end
    end

    -- 迁移：圆滚滚上等星恶魔从Lv51调整为Lv80，斩首任务顺序已变更
    -- 旧存档中若该任务为ACTIVE，重置为LOCKED，等新前置(半人马祭司)完成后自然解锁
    -- 同时后续任务(钢琴妖怪)的新前置为黑熊王(必然已完成)，会在M.update()中自动激活
    do
        local st = M.questStates["main_freya_bounty_star_demon_elite"]
        if st and st.status == M.STATUS_ACTIVE then
            st.status = M.STATUS_LOCKED
            st.snapshot = nil
            print("[QuestManager] 迁移：斩首·圆滚滚上等星恶魔已重置，等待新前置任务解锁")
        end
    end

    -- 立即刷新一次
    M.update()
end

return M
