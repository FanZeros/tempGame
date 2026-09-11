-- ============================================================
-- Event_InitialSupply.lua  —— 事件#2：领取初始物资
-- 触发条件：1号事件(awakening)完成 且 本事件未完成时，进入冒险者公会
-- ============================================================

local GS = require("GameState")
local DialogueManager = require("DialogueManager")
local SignInSystem = require("SignInSystem")

local M = {}
M.id = "initial_supply"

-- 根据职业决定发放的武器装备
local CLASS_WEAPONS = {
    warrior  = { { id = "iron_sword",  name = "铁剑" },   { id = "wood_shield", name = "木盾" } },
    hunter   = { { id = "wood_bow",    name = "木弓" },   { id = "quiver",      name = "箭袋" } },
    mage     = { { id = "wood_staff",  name = "木法杖" }, { id = "wood_shield", name = "木盾" } },
    assassin = { { id = "iron_dagger", name = "铁匕首" }, { id = "wood_shield", name = "木盾" } },
    priest   = { { id = "iron_mace",   name = "铁钉锤" }, { id = "wood_shield", name = "木盾" } },
}

--- 检查是否满足触发条件
---@return boolean
function M.canTrigger()
    -- 1号事件必须已完成
    if not GS.awakeningCompleted then return false end
    -- 本事件不能重复触发
    if GS.eventCompleted["initial_supply"] then return false end
    return true
end

--- 发放武器（带防重复领取保护）
local function grantWeapons()
    if GS.eventCompleted["initial_supply_weapons"] then
        print("[Event_InitialSupply] Weapons already granted, skipping")
        return
    end
    local classId = GS.currentClass or "warrior"
    local weapons = CLASS_WEAPONS[classId] or CLASS_WEAPONS.warrior
    for _, w in ipairs(weapons) do
        local ok, msg = GS.addToInventory(w.id, 1)
        print("[Event_InitialSupply] Grant weapon: " .. w.name .. " -> " .. tostring(ok) .. " " .. tostring(msg))
    end
    GS.eventCompleted["initial_supply_weapons"] = true
    GS.updateAutoSaveSnapshot()
end

--- 发放药水和金币（带防重复领取保护）
local function grantPotionsAndGold()
    if GS.eventCompleted["initial_supply_potions"] then
        print("[Event_InitialSupply] Potions & gold already granted, skipping")
        return
    end
    GS.addToInventory("potion_hp_s", 10)
    GS.addToInventory("potion_mp_s", 10)
    GS.gold = GS.gold + 500
    GS.eventCompleted["initial_supply_potions"] = true
    GS.updateAutoSaveSnapshot()
    print("[Event_InitialSupply] Granted 10x HP potion, 10x MP potion, 500 gold")
end

--- 触发事件（在 enterSubScene("guild") 时调用）
function M.trigger()
    if not M.canTrigger() then return false end

    print("[Event_InitialSupply] Event triggered!")

    -- 进入事件时隐藏冒险者等级徽章和晋升条件面板
    GS.hideRankBadge = true
    GS.hidePromotionPanel = true

    -- 获取武器名称用于对话
    local classId = GS.currentClass or "warrior"
    local weapons = CLASS_WEAPONS[classId] or CLASS_WEAPONS.warrior
    local weaponNames = {}
    for _, w in ipairs(weapons) do
        weaponNames[#weaponNames + 1] = w.name
    end
    local weaponStr = table.concat(weaponNames, "和")

    -- 第1段对话：介绍 + 提到武器
    GS.learnNPCName("guild_receptionist")
    local lines1 = {
        { speaker = "？？？", text = "欢迎来到冒险者公会！我是妮可！" },
        { speaker = "妮可", text = "你就是{玩家}吧。让我登记一下……好了。" },
        { speaker = "妮可", text = "会长已经通知我为你准备了新人物资，首先是武器。" },
    }

    DialogueManager.startDynamic(lines1, function()
        -- 第1段结束 → 发放武器 → 开始第2段
        grantWeapons()
        print("[Event_InitialSupply] Weapons granted, starting part 2")

        local lines2 = {
            { speaker = "妮可", text = "（你获得了" .. weaponStr .. "）" },
            { speaker = "妮可", text = "试试看，哇，很适合你！嗯……还有一些金币和药剂！" },
        }

        DialogueManager.startDynamic(lines2, function()
            -- 第2段结束 → 发放药水+金币 → 开始第3段
            grantPotionsAndGold()
            print("[Event_InitialSupply] Potions & gold granted, starting part 3")

            local lines3a = {
                { speaker = "妮可", text = "（你获得了10个小型生命药水、10个小型魔法药水和500金币）" },
                { speaker = "妮可", text = "差不多就是这些了，最近外面魔物越来越多，人们离开清水镇越来越困难了，希望你施以援手。这是请求，拜托你了！" },
            }

            DialogueManager.startDynamic(lines3a, function()
                -- 显示冒险者等级徽章
                GS.hideRankBadge = false
                print("[Event_InitialSupply] Showing rank badge")

                local lines3b = {
                    { speaker = "妮可", text = "冒险者公会也将为你在这个世界的冒险提供帮助，你现在登记的冒险者等级是F级。" },
                }

                DialogueManager.startDynamic(lines3b, function()
                    -- 显示晋升条件面板
                    GS.hidePromotionPanel = false
                    print("[Event_InitialSupply] Showing promotion panel")

                    -- 激活主线「提高冒险者等级·E」
                    local QuestManager = require("QuestManager")
                    QuestManager.activateQuest("main_rank_e")

                    -- 第5段：公会委托（委托说明，结束后接取任务）
                    local lines3c_commission = {
                        { speaker = "妮可", text = "公会有一个委托，也是对你的初步考验。请到垂雾森林的森林入口寻找吸血蝙蝠，获取它身上携带的蝙蝠牙挂饰。" },
                    }

                    DialogueManager.startDynamic(lines3c_commission, function()
                        -- 委托说明结束 → 自动接取支线「化身蝙蝠」
                        QuestManager.activateQuest("side_bat_fang")

                        -- 第6段：鼓励语 + 结束
                        local lines3c = {
                            { speaker = "妮可", text = "请努力讨伐魔物并提高冒险者等级，升级后我们将提供更优质的服务。" },
                            { speaker = "妮可", text = "那么，请努力吧，{玩家}！" },
                        }

                        DialogueManager.startDynamic(lines3c, function()
                            -- 全部对话结束，标记事件完成并云存档
                            GS.eventCompleted["initial_supply"] = true
                            -- 激活5天签到奖励系统
                            SignInSystem.activate()
                            -- 与妮可的对话自动计入支线「清水镇的人们」
                            if not GS.npcTalkedRecord["guild"] then
                                GS.npcTalkedRecord["guild"] = true
                            end
                            GS.updateAutoSaveSnapshot()
                            GS.saveToCloud()
                            print("[Event_InitialSupply] Event completed, cloud saved")
                        end)
                    end)
                end)
            end)
        end)
    end)

    return true
end

return M
