-- ====================================================================
-- Event/EventManager.lua - 事件关卡管理器
-- ====================================================================
-- 管理脚本化事件关卡的生命周期（进入/退出/更新）
-- 平行于 DungeonManager，独立于 STAGE_DEFS
-- ====================================================================

local GS = require("GameState")

local M = {}

-- 事件注册表
local eventDefs = {}
-- 当前活跃事件实例
local currentEvent = nil
-- 保存的游戏状态（事件结束后恢复）
local savedState = nil

--- 注册一个事件定义
---@param eventId string 事件 ID
---@param eventDef table 事件定义（需实现 onEnter/onExit/update）
function M.register(eventId, eventDef)
    eventDefs[eventId] = eventDef
    print("[EventManager] Registered event: " .. eventId)
end

--- 进入事件关卡
---@param eventId string 事件 ID
---@return boolean 是否成功进入
function M.enter(eventId)
    local def = eventDefs[eventId]
    if not def then
        print("[EventManager] Unknown event: " .. tostring(eventId))
        return false
    end

    -- 保存当前战斗状态
    savedState = {
        currentStage = GS.currentStage,
        currentBattleBg = GS.currentBattleBg,
        monsters = GS.monsters,
        companions = GS.companions,
        turnNumber = GS.turnNumber,
        stealthActive = GS.stealthActive,
        stealthTurns = GS.stealthTurns,
        gameState = GS.gameState,
        turnPhase = GS.turnPhase,
        holyTrees = GS.holyTrees,
        iceWalls = GS.iceWalls,
        burningGrounds = GS.burningGrounds,
        blizzardZones = GS.blizzardZones,
        thunderClouds = GS.thunderClouds,
        fireCorpses = GS.fireCorpses,
        playerDebuffs = GS.playerDebuffs,
    }

    -- 关闭可能残留的 BoardOverlay（如上次事件结束后留下的城镇覆盖层）
    local BoardOverlay = require("BoardOverlay")
    if BoardOverlay.isActive() then
        BoardOverlay.hide()
    end

    -- 设置事件模式
    GS.isEvent = true
    GS.eventId = eventId
    GS.eventInputLocked = true
    GS.monsters = {}
    GS.companions = {}
    GS.holyTrees = {}
    GS.iceWalls = {}
    GS.burningGrounds = {}
    GS.pendingBurningGrounds = {}
    GS.blizzardZones = {}
    GS.thunderClouds = {}
    GS.fireCorpses = {}
    GS.playerDebuffs = {}
    GS.turnNumber = 0
    GS.gameState = GS.STATE_PLAYER
    GS.turnPhase = GS.PHASE_MOVE

    -- 初始化事件
    currentEvent = def
    currentEvent:onEnter()

    print("=== 进入事件: " .. tostring(eventId) .. " ===")
    return true
end

--- 退出事件关卡
---@param skipRestore boolean|nil 是否跳过状态恢复（角色创建后首次进入不需恢复）
function M.exit(skipRestore)
    if not GS.isEvent then return end

    local eventId = GS.eventId

    if currentEvent and currentEvent.onExit then
        currentEvent:onExit()
    end

    -- 清除事件状态
    GS.isEvent = false
    GS.eventId = nil
    GS.eventInputLocked = false
    GS.eventAllowNormalTurns = false
    GS.monsters = {}
    GS.companions = {}

    -- 恢复保存的状态
    if not skipRestore and savedState then
        GS.currentStage = savedState.currentStage
        GS.currentBattleBg = savedState.currentBattleBg
        GS.monsters = savedState.monsters or {}
        GS.companions = savedState.companions or {}
        GS.turnNumber = savedState.turnNumber
        GS.stealthActive = savedState.stealthActive
        GS.stealthTurns = savedState.stealthTurns
        GS.gameState = savedState.gameState
        GS.turnPhase = savedState.turnPhase
        GS.holyTrees = savedState.holyTrees or {}
        GS.iceWalls = savedState.iceWalls or {}
        GS.burningGrounds = savedState.burningGrounds or {}
        GS.blizzardZones = savedState.blizzardZones or {}
        GS.thunderClouds = savedState.thunderClouds or {}
        GS.fireCorpses = savedState.fireCorpses or {}
        GS.playerDebuffs = savedState.playerDebuffs or {}
    end

    savedState = nil
    currentEvent = nil
    print("=== 退出事件: " .. tostring(eventId) .. " ===")
end

--- 获取事件定义（用于外部设置回调等）
---@param eventId string
---@return table|nil
function M.getEventDef(eventId)
    return eventDefs[eventId]
end

--- 是否正在事件中
---@return boolean
function M.isActive()
    return GS.isEvent and currentEvent ~= nil
end

--- 每帧更新（由 main.lua 调用）
---@param dt number
function M.update(dt)
    if not M.isActive() then return end
    currentEvent:update(dt)
end

--- 获取当前事件
---@return table|nil
function M.getCurrentEvent()
    return currentEvent
end

return M
