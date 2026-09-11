-- ====================================================================
-- SharedStorageLog.lua - 共享仓库操作日志（本地文件 + 云端双存）
--
-- 一致性策略（合并优先）：
--   写入 → 追加本地 → 合并本地+云端 → 写回双端
--   读取 → 拉取本地+云端 → 合并 → 写回双端 → 返回结果
--
--   合并算法：取两端并集 → 按行字符串去重 → 按行首时间戳升序排列 → 裁剪到上限
--
-- 数据格式："2026-05-19 14:32:01 | 战士小明 | 存入 | 精制生命药水 x3"
-- 云 key  ："shared_storage_log"（clientCloud values，存 table）
-- 本地文件："shared_storage_log.txt"
-- 上限    ：500 条；超出时删最旧 100 条
-- ====================================================================

local M = {}

local LOG_FILE    = "shared_storage_log.txt"
local CLOUD_KEY   = "shared_storage_log"
local MAX_ENTRIES = 500
local TRIM_BATCH  = 100

-- ====================================================================
-- 本地文件读写
-- ====================================================================

---@return string[]
local function loadLocal()
    if not fileSystem:FileExists(LOG_FILE) then return {} end
    local file = File(LOG_FILE, FILE_READ)
    if not file:IsOpen() then return {} end
    local content = file:ReadString()
    file:Close()
    if not content or content == "" then return {} end
    local lines = {}
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

---@param lines string[]
local function writeLocal(lines)
    local file = File(LOG_FILE, FILE_WRITE)
    if not file:IsOpen() then
        print("[SSLog] 无法写入本地日志文件")
        return
    end
    file:WriteString(table.concat(lines, "\n") .. "\n")
    file:Close()
end

-- ====================================================================
-- 云端读写
-- ====================================================================

---@param lines string[]
local function uploadCloud(lines)
    if not clientCloud then return end
    clientCloud:Set(CLOUD_KEY, lines, {
        error = function(code, reason)
            print("[SSLog] 云端上传失败:", code, reason)
        end
    })
end

-- ====================================================================
-- 合并算法
-- 取两端并集 → 按行字符串去重 → 按行首19字符时间戳升序排列 → 裁剪上限
-- ====================================================================

---@param a string[]
---@param b string[]
---@return string[]
local function mergeLines(a, b)
    -- 并集去重（用 set 快速判断）
    local seen  = {}
    local merged = {}
    for _, line in ipairs(a) do
        if not seen[line] then
            seen[line] = true
            merged[#merged + 1] = line
        end
    end
    for _, line in ipairs(b) do
        if not seen[line] then
            seen[line] = true
            merged[#merged + 1] = line
        end
    end

    -- 按时间戳（行首 19 字符）升序排列
    table.sort(merged, function(x, y)
        return x:sub(1, 19) < y:sub(1, 19)
    end)

    -- 超出上限则删最旧的 TRIM_BATCH 条
    if #merged > MAX_ENTRIES then
        local trimmed = {}
        for i = TRIM_BATCH + 1, #merged do trimmed[#trimmed + 1] = merged[i] end
        return trimmed
    end
    return merged
end

---@param lines string[]
---@return string[]
local function reverseLines(lines)
    local rev = {}
    for i = #lines, 1, -1 do rev[#rev + 1] = lines[i] end
    return rev
end

-- ====================================================================
-- 公开接口
-- ====================================================================

--- 追加一条操作记录，并将合并结果写回本地+云端
---@param action   string  "存入" 或 "取出"
---@param itemName string
---@param qty      number
---@param charName string
function M.append(action, itemName, qty, charName)
    local qtyStr = (qty and qty > 1) and (" x" .. tostring(qty)) or ""
    local ts     = os.date("%Y-%m-%d %H:%M:%S")
    local entry  = string.format("%s | %s | %s | %s%s",
        ts, charName or "未知", action, itemName or "?", qtyStr)

    local local_ = loadLocal()
    local_[#local_ + 1] = entry

    -- 若云端可用，先拉一次云端做合并再写回（保证新条目不覆盖其他设备的记录）
    if clientCloud then
        clientCloud:Get(CLOUD_KEY, {
            ok = function(values, _)
                local cloud = (values and type(values[CLOUD_KEY]) == "table")
                              and values[CLOUD_KEY] or {}
                local merged = mergeLines(local_, cloud)
                writeLocal(merged)
                uploadCloud(merged)
            end,
            error = function(code, reason)
                -- 云端不可用，至少保住本地
                print("[SSLog] append 云端读取失败，仅写本地:", code, reason)
                local trimmed = mergeLines(local_, {})
                writeLocal(trimmed)
            end
        })
    else
        -- 无云端（单机调试），只写本地
        local trimmed = mergeLines(local_, {})
        writeLocal(trimmed)
    end
end

--- 读取日志（最新在前），自动合并本地+云端后写回双端，使用回调返回结果
---@param onResult fun(lines: string[])
function M.getReversed(onResult)
    local local_ = loadLocal()

    if clientCloud then
        clientCloud:Get(CLOUD_KEY, {
            ok = function(values, _)
                local cloud = (values and type(values[CLOUD_KEY]) == "table")
                              and values[CLOUD_KEY] or {}
                local merged = mergeLines(local_, cloud)

                -- 若合并后数据与本地/云端任一端不同则写回（静默修复不一致）
                local localChanged = (#merged ~= #local_)
                if not localChanged then
                    for i, v in ipairs(merged) do
                        if v ~= local_[i] then localChanged = true; break end
                    end
                end
                if localChanged then
                    writeLocal(merged)
                    uploadCloud(merged)
                end

                onResult(reverseLines(merged))
            end,
            error = function(code, reason)
                print("[SSLog] 读取云端失败，使用本地数据:", code, reason)
                onResult(reverseLines(local_))
            end
        })
    else
        onResult(reverseLines(local_))
    end
end

return M
