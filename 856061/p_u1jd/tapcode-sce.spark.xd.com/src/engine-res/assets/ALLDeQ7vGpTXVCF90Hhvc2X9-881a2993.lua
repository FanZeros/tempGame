-- ============================================================================
-- Image Cache
-- UrhoX UI Library - Yoga + NanoVG
-- Manages image loading and caching for UI backgrounds
-- ============================================================================

local ImageCache = {}

-- Cache structure: { path = { handle, width, height } }
local cache_ = {}

-- NanoVG context reference (set during render)
local nvgContext_ = nil

-- ============================================================================
-- Context Management
-- ============================================================================

--- Set NanoVG context (call at start of each frame)
---@param nvg NVGContextWrapper|nil NanoVG context
function ImageCache.SetContext(nvg)
    nvgContext_ = nvg
end

--- Get current NanoVG context
---@return NVGContextWrapper|nil
function ImageCache.GetContext()
    return nvgContext_
end

-- ============================================================================
-- Image Loading
-- ============================================================================

--- Get image handle (auto-cached)
---@param path string Image file path
---@return number Image handle (0 if failed)
function ImageCache.Get(path)
    if not path or path == "" then
        return 0
    end

    if not nvgContext_ then
        return 0
    end

    -- Return cached image
    if cache_[path] then
        return cache_[path].handle
    end

    -- Load new image
    local handle = nvgCreateImage(nvgContext_, path, 0)
    if handle and handle > 0 then
        local w, h = nvgImageSize(nvgContext_, handle)
        cache_[path] = {
            handle = handle,
            width = w or 0,
            height = h or 0,
        }
        return handle
    end

    -- Cache failed load to avoid repeated attempts
    cache_[path] = { handle = 0, width = 0, height = 0 }
    return 0
end

--- Get image size (queries real texture size to handle DWP hot-reload)
---@param path string Image file path
---@return number # width
---@return number # height
function ImageCache.GetSize(path)
    local entry = cache_[path]
    if entry and entry.handle > 0 and nvgContext_ then
        -- Query real texture size from NanoVG (handles DWP hot-reload size changes)
        local w, h = nvgImageSize(nvgContext_, entry.handle)
        if w and w > 0 and h and h > 0 then
            entry.width = w
            entry.height = h
        end
        return entry.width, entry.height
    end
    if entry then
        return entry.width, entry.height
    end
    return 0, 0
end

--- Check if image is loaded
---@param path string Image file path
---@return boolean
function ImageCache.IsLoaded(path)
    local entry = cache_[path]
    return entry and entry.handle > 0
end

-- ============================================================================
-- Cache Management
-- ============================================================================

--- Release a specific image
---@param path string Image file path
function ImageCache.Release(path)
    local entry = cache_[path]
    if entry and entry.handle > 0 and nvgContext_ then
        nvgDeleteImage(nvgContext_, entry.handle)
    end
    cache_[path] = nil
end

--- Clear all cached images (call on scene exit)
function ImageCache.Clear()
    if nvgContext_ then
        for path, entry in pairs(cache_) do
            if entry.handle > 0 then
                nvgDeleteImage(nvgContext_, entry.handle)
            end
        end
    end
    cache_ = {}
end

--- Get cache statistics
---@return table { count, loaded }
function ImageCache.GetStats()
    local count = 0
    local loaded = 0
    for _, entry in pairs(cache_) do
        count = count + 1
        if entry.handle > 0 then
            loaded = loaded + 1
        end
    end
    return { count = count, loaded = loaded }
end

--- Get all cached paths (for debugging)
---@return string[]
function ImageCache.GetCachedPaths()
    local paths = {}
    for path, _ in pairs(cache_) do
        table.insert(paths, path)
    end
    return paths
end

return ImageCache
