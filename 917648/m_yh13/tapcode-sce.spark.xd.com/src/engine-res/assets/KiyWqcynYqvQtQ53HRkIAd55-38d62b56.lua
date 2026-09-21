-- LegacyGate.lua — 旧版大厅开关的统一读取（Host 与 Runtime 共用，单一真源）。
--
-- 开关文件 GameLobby/LegacySwitch.lua 是纯 Lua 热更文件，返回布尔：
--   return true  -> 旧版固定大厅
--   return false / 其它 -> 新版自定义大厅（默认）
--
-- 为什么不经 require 读开关：require 对「没有返回值」的模块会把结果塌缩成 true，无法与显式
-- return true 区分。若开关文件被误改成无返回值，Host 与 Runtime 若各用各的读法就会分裂
-- （一侧判旧版、一侧判新版）。故两侧统一走本模块裸读文件 + load + pcall，只认显式布尔 true；
-- 缺文件 / 加载失败 / 执行出错 / 无返回值一律按 false（安全默认：新版）。

local SWITCH_FILE = "urhox-libs/GameLobby/LegacySwitch.lua"

local function logError(msg)
    msg = "[LegacyGate] " .. tostring(msg)
    if log and LOG_ERROR then log:Write(LOG_ERROR, msg) else print(msg) end
end

local M = {}

--- 旧版大厅是否启用（只认开关文件显式 return true）。
--- @return boolean
function M.IsLegacyEnabled()
    if not (cache and cache.GetFile and cache.Exists) then return false end
    if not cache:Exists(SWITCH_FILE) then return false end
    local file = cache:GetFile(SWITCH_FILE)
    if not file then return false end
    local lines = {}
    while not file:IsEof() do lines[#lines + 1] = file:ReadLine() end
    file:Close()
    local chunk, err = load(table.concat(lines, "\n"), "@" .. SWITCH_FILE, "t")
    if not chunk then
        logError(_tr("t_1BzIP4N7b1C6aoy4ej", tostring(err)))
        return false
    end
    local ok, enabled = pcall(chunk)
    if not ok then
        logError(_tr("t_14klqS9Hr14K7GCPM1", tostring(enabled)))
        return false
    end
    return enabled == true
end

return M
