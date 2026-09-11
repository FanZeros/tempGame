-- ====================================================================
-- DialogueManager.lua - 对话管理器
-- ====================================================================
-- 负责：条件判断、对话启动/推进/结束、flags 标记
-- 用法: local DialogueManager = require("DialogueManager")
-- ====================================================================

local M = {}
local GS = require("GameState")
local DialogueData = require("data.Dialogues")

-- ===== 对话 UI 状态 =====
M.active = false           -- 是否正在显示对话
M.currentId = nil           -- 当前对话 ID
M.currentLines = nil        -- 当前对话行列表
M.lineIndex = 0             -- 当前行索引（1-based）
M.waitingForChoice = false  -- 是否正在等待选项
M.choiceResult = nil        -- 选项结果索引（1-based）

--- 检查某建筑是否有可触发的对话
---@param buildingKey string 建筑 key（如 "blacksmith"）
---@return string|nil 对话 ID，无则 nil
function M.checkBuilding(buildingKey)
    local candidates = {}
    for id, dlg in pairs(DialogueData) do
        if dlg.building == buildingKey then
            -- once 类型：已触发过则跳过
            if dlg.once and GS.dialogueFlags[id] then
                -- skip
            else
                -- condition 检查
                if not dlg.condition or dlg.condition(GS) then
                    candidates[#candidates + 1] = { id = id, priority = dlg.priority or 0 }
                end
            end
        end
    end
    if #candidates == 0 then return nil end
    -- 按 priority 降序排序，取最高优先级
    table.sort(candidates, function(a, b) return a.priority > b.priority end)
    return candidates[1].id
end

--- 启动对话
---@param dialogueId string 对话 ID
---@return boolean 是否成功启动
function M.start(dialogueId)
    local dlg = DialogueData[dialogueId]
    if not dlg then return false end
    local lines = type(dlg.lines) == "function" and dlg.lines() or dlg.lines
    if not lines or #lines == 0 then return false end
    M.active = true
    M.currentId = dialogueId
    M.currentLines = lines
    M.lineIndex = 1
    M.waitingForChoice = false   -- 重置：防止前一次 startDynamic 的残留状态阻塞推进
    M.choiceResult = nil
    M._dynamicOnComplete = nil   -- 重置：防止 finish() 时误触发已失效的回调链
    -- 第一行的 onShow 回调
    if lines[1].onShow then
        lines[1].onShow()
    end
    print("[DialogueManager] start: " .. dialogueId .. " (" .. #lines .. " lines)")
    return true
end

--- 推进到下一行（玩家点击触发）
function M.advance()
    if not M.active then return end
    -- 如果当前行有 choices 且尚未选择，不允许推进
    if M.waitingForChoice then return end
    M.lineIndex = M.lineIndex + 1
    if M.lineIndex > #M.currentLines then
        M.finish()
        return
    end
    -- 检查新行是否有选项
    local line = M.currentLines[M.lineIndex]
    if line and line.choices then
        M.waitingForChoice = true
        M.choiceResult = nil
    end
    -- onShow 回调（行首次显示时触发）
    if line and line.onShow then
        line.onShow()
    end
end

--- 选择选项（玩家点击选项按钮触发）
---@param index number 选项索引（1-based）
function M.selectChoice(index)
    if not M.waitingForChoice then return end
    local line = M.currentLines[M.lineIndex]
    if not line or not line.choices then return end
    if index < 1 or index > #line.choices then return end
    M.choiceResult = index
    M.waitingForChoice = false
    -- 如果有 onChoice 回调，执行它
    if line.onChoice then
        line.onChoice(index, line.choices[index])
    end
end

--- 结束对话
function M.finish()
    if not M.active then return end
    local dlg = DialogueData[M.currentId]
    -- 标记 once 类型
    if dlg and dlg.once then
        GS.dialogueFlags[M.currentId] = true
        print("[DialogueManager] flagged: " .. M.currentId)
    end
    -- NPC 交谈记录已移至 TalkQA（按交谈键时记录，而非进入建筑）
    -- onComplete 回调（静态对话数据）
    if dlg and dlg.onComplete then
        dlg.onComplete(GS)
    end
    -- 动态对话的 onComplete 回调
    local prevLines = M.currentLines
    if M._dynamicOnComplete then
        local cb = M._dynamicOnComplete
        M._dynamicOnComplete = nil
        cb(GS)
    end
    -- 如果回调中启动了新对话（currentLines 已变），不要覆盖新对话状态
    if M.currentLines ~= prevLines then
        print("[DialogueManager] finish: chained to new dialogue")
        return
    end
    local id = M.currentId
    M.active = false
    M.currentId = nil
    M.currentLines = nil
    M.lineIndex = 0
    M.waitingForChoice = false
    M.choiceResult = nil
    print("[DialogueManager] finish: " .. tostring(id))
end

--- 启动动态对话（直接传入 lines 表，无需在 Dialogues.lua 中注册）
---@param lines table[] 对话行列表
---@param onComplete function|nil 完成回调
---@return boolean
function M.startDynamic(lines, onComplete)
    if not lines or #lines == 0 then return false end
    M.active = true
    M.currentId = "_dynamic_"
    M.currentLines = lines
    M.lineIndex = 1
    M.waitingForChoice = false
    M.choiceResult = nil
    M._dynamicOnComplete = onComplete
    -- 检查第一行是否有选项
    if lines[1].choices then
        M.waitingForChoice = true
    end
    -- 第一行的 onShow 回调
    if lines[1].onShow then
        lines[1].onShow()
    end
    print("[DialogueManager] startDynamic (" .. #lines .. " lines)")
    return true
end

--- 替换对话文本中的占位符
---@param text string
---@return string
local function replacePlaceholders(text, speakerNpcId)
    if not text then return "" end
    local pName = GS.charName or ""
    -- 获取爱称和伴侣判断
    local petName = ""
    if speakerNpcId then petName = GS.getNPCPetName(speakerNpcId) end
    -- {玩家}/{爱称} 或 {玩家}\{爱称} → 条件选择：伴侣用爱称，否则用玩家名
    local isPartner = GS.partnerNpcKey and GS.partnerNpcKey == speakerNpcId
    local condName = (isPartner and petName ~= "") and petName or pName
    text = text:gsub("{玩家}/{爱称}", condName)
    text = text:gsub("{玩家}\\{爱称}", condName)
    -- 冒险者/{玩家} → 伴侣用爱称，否则用"冒险者"
    text = text:gsub("冒险者/{玩家}", (isPartner and petName ~= "") and petName or "冒险者")
    -- 单独的占位符
    if pName ~= "" then text = text:gsub("{玩家}", pName) end
    if petName ~= "" then text = text:gsub("{爱称}", petName) end
    return text
end

--- 获取当前对话行（自动替换占位符）
---@return table|nil { speaker = string, text = string, choices = table|nil }
function M.getCurrentLine()
    if not M.active or not M.currentLines then return nil end
    local line = M.currentLines[M.lineIndex]
    if not line then return nil end
    -- 通过 speaker 名字反查 npcId，用于解析 {爱称}
    local npcId = line.speaker and GS._speakerToNPC[line.speaker] or nil
    return {
        speaker = GS.resolveNPCSpeaker(replacePlaceholders(line.speaker, npcId)),
        text = replacePlaceholders(line.text, npcId),
        choices = line.choices,
        onChoice = line.onChoice,
    }
end

--- 是否为最后一行
---@return boolean
function M.isLastLine()
    if not M.active or not M.currentLines then return false end
    return M.lineIndex >= #M.currentLines
end

return M
