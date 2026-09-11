-- ====================================================================
-- ImageManager.lua - 图片资源统一管理器
-- ====================================================================
-- 集中管理所有 NanoVG 图片资源的加载、获取和分类
-- 分类：ui, skill, rarity, item, monster
-- ====================================================================

local M = {}

-- NanoVG 上下文引用
M.vg = nil

-- 按分类存储图片句柄: { [category] = { [key] = handle } }
M.images = {
    ui       = {},   -- 界面图片（背景、头像、图标等）
    skill    = {},   -- 技能图标
    rarity   = {},   -- 稀有度图片
    item     = {},   -- 物品图片
    monster  = {},   -- 怪物图片
}

-- 统计
M.stats = { total = 0, loaded = 0, failed = 0 }

-- ====================================================================
-- 初始化
-- ====================================================================
---@param vg userdata NanoVG 上下文
function M.init(vg)
    M.vg = vg
    M.stats = { total = 0, loaded = 0, failed = 0 }
end

-- ====================================================================
-- 加载单张图片
-- ====================================================================
---@param category string 分类名 (ui/skill/rarity/item/monster)
---@param key string 资源键名
---@param path string 图片文件路径
---@return integer handle NanoVG 图片句柄（失败返回 -1）
function M.load(category, key, path)
    if not M.vg then
        print("ERROR: ImageManager not initialized (call init first)")
        return -1
    end
    if not M.images[category] then
        print("WARNING: Unknown image category: " .. tostring(category))
        M.images[category] = {}
    end

    M.stats.total = M.stats.total + 1
    local handle = nvgCreateImage(M.vg, path, 0)
    if handle ~= -1 then
        M.images[category][key] = handle
        M.stats.loaded = M.stats.loaded + 1
    else
        print("WARNING: Failed to load image [" .. category .. "/" .. key .. "]: " .. path)
        M.stats.failed = M.stats.failed + 1
    end
    return handle
end

-- ====================================================================
-- 批量加载
-- ====================================================================
---@param category string 分类名
---@param entries table { {key, path}, ... } 或 { key = path, ... }
function M.loadBatch(category, entries)
    if not entries then return end
    -- 支持数组格式 { {key, path}, ... }
    if #entries > 0 then
        for _, entry in ipairs(entries) do
            M.load(category, entry[1], entry[2])
        end
    else
        -- 支持字典格式 { key = path, ... }
        for key, path in pairs(entries) do
            M.load(category, key, path)
        end
    end
end

-- ====================================================================
-- 从数据库加载（适用于 itemTemplates、MONSTER_DB）
-- ====================================================================
---@param category string 分类名
---@param db table 数据表
---@param imageField string 图片路径字段名（如 "icon"、"image"）
function M.loadFromDB(category, db, imageField)
    if not db then return end
    for key, entry in pairs(db) do
        local path = entry[imageField]
        if path then
            M.load(category, path, path)
        end
    end
end

-- ====================================================================
-- 按需加载：查不到就现场加载（适用于怪物等延迟加载场景）
-- ====================================================================
---@param category string 分类名
---@param key string 资源键名（同时也是图片路径）
---@return integer handle NanoVG 图片句柄（失败返回 -1）
function M.lazyGet(category, key)
    if not key then return -1 end
    local cat = M.images[category]
    if not cat then
        M.images[category] = {}
        cat = M.images[category]
    end
    local handle = cat[key]
    if handle then return handle end
    -- 未缓存，现场加载
    local h = M.load(category, key, key)
    if h == -1 then
        -- 缓存失败结果，避免每帧重复加载
        M.images[category][key] = -1
    end
    return h
end

-- ====================================================================
-- 获取图片句柄
-- ====================================================================
---@param category string 分类名
---@param key string 资源键名
---@return integer handle NanoVG 图片句柄（未找到返回 -1）
function M.get(category, key)
    if not key then return -1 end
    local cat = M.images[category]
    if not cat then return -1 end
    return cat[key] or -1
end

-- ====================================================================
-- 获取整个分类的图片表
-- ====================================================================
---@param category string 分类名
---@return table 图片句柄表 { [key] = handle }
function M.getCategory(category)
    return M.images[category] or {}
end

-- ====================================================================
-- 打印统计信息
-- ====================================================================
function M.printStats()
    print(string.format("=== ImageManager Stats: %d loaded, %d failed, %d total ===",
        M.stats.loaded, M.stats.failed, M.stats.total))
    for cat, tbl in pairs(M.images) do
        local count = 0
        for _ in pairs(tbl) do count = count + 1 end
        if count > 0 then
            print(string.format("  [%s]: %d images", cat, count))
        end
    end
end

return M
