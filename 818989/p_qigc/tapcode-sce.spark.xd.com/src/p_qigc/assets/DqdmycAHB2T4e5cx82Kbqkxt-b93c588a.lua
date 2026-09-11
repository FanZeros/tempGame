-- ============================================================
-- Command.lua — 命令模式（联机预备架构）
-- ============================================================
-- 将玩家操作记录为可序列化的命令对象。
-- 当前单机模式下，原有执行逻辑不变，仅增加命令记录。
-- 联机模式下，命令可通过网络发送到服务端验证后再执行。
-- ============================================================

local GS = require("GameState")

local M = {}

-- ============================================================
-- 命令历史（可用于回放/调试/联机同步）
-- ============================================================
M.history = {}
M.historyMaxSize = 200

--- 记录命令到历史
---@param cmdType string 命令类型
---@param data table? 命令数据
function M.record(cmdType, data)
    local entry = {
        turn  = GS.turnCount or 0,
        phase = GS.turnPhase or 0,
        time  = os.clock(),
        type  = cmdType,
    }
    if data then
        for k, v in pairs(data) do
            entry[k] = v
        end
    end
    table.insert(M.history, entry)
    if #M.history > M.historyMaxSize then
        table.remove(M.history, 1)
    end
end

-- ============================================================
-- 快捷记录函数（语义化包装）
-- ============================================================

--- 记录移动命令
---@param fromX number
---@param fromY number
---@param toX number
---@param toY number
function M.recordMove(fromX, fromY, toX, toY)
    M.record("move", { fromX = fromX, fromY = fromY, toX = toX, toY = toY })
end

--- 记录攻击命令
---@param targetX number
---@param targetY number
---@param skillId string?
function M.recordAttack(targetX, targetY, skillId)
    M.record("attack", { targetX = targetX, targetY = targetY, skillId = skillId })
end

--- 记录使用物品命令
---@param slotIdx number
function M.recordUseItem(slotIdx)
    M.record("useItem", { slotIdx = slotIdx })
end

--- 记录结束回合命令
function M.recordEndTurn()
    M.record("endTurn")
end

--- 记录撤销移动命令
function M.recordUndoMove()
    M.record("undoMove")
end

-- ============================================================
-- 查询 API
-- ============================================================

--- 清空命令历史
function M.clearHistory()
    M.history = {}
end

--- 获取最近 N 条命令
---@param n number?
---@return table[]
function M.getRecentCommands(n)
    n = n or 10
    local result = {}
    local start = math.max(1, #M.history - n + 1)
    for i = start, #M.history do
        result[#result + 1] = M.history[i]
    end
    return result
end

--- 获取当前回合的所有命令
---@return table[]
function M.getCurrentTurnCommands()
    local turn = GS.turnCount or 0
    local result = {}
    for i = #M.history, 1, -1 do
        if M.history[i].turn == turn then
            table.insert(result, 1, M.history[i])
        elseif M.history[i].turn < turn then
            break
        end
    end
    return result
end

return M
