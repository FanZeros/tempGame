-- ResourceCacheExtensions.lua
-- Extends ResourceCache with download and async loading methods.
--
-- Proxied download methods (delegate to DownloadManager):
--   cache:DownloadResource(uri [, onComplete])
--   cache:DownloadResources(uris [, onComplete [, onProgress]])
--   cache:CancelDownload(uri)
--   cache:GetDownloadState(uri)
--
-- Download observer (global progress monitoring):
--   cache:ObserveDownloads(onProgress [, onComplete])  → observerId
--   cache:StopObservingDownloads(observerId)
--
-- Async loading for non-DWP resource types:
--   cache:GetResourceAsync(typeName, uri [, callback])
--
-- DWP-supported types (Texture2D, Model, Animation, Sound, etc.) already have
-- placeholder + hot-reload built into GetResource(). GetResourceAsync handles
-- types that DON'T have placeholders: when the file isn't local yet,
-- GetResource() returns nil and poisons the null-resource cache.
--
-- Loaded automatically by urhox-libs/Engine/init.lua.
--
-- Usage:
--   -- Download
--   cache:DownloadResource("uuid://hero-tex", function(success, errorMessage)
--       if success then print("done") end
--   end)
--
--   local refs = cache:GetResRefs({"uuid://scene", "uuid://hero"}, true)
--   cache:DownloadResources(refs, function(success, failedCount)
--       print("batch done:", success)
--   end)
--
--   -- Async loading (callback style)
--   cache:GetResourceAsync("JSONFile", "uuid://config", function(resource)
--       if resource then print("loaded:", resource.name) end
--   end)
--
--   -- Async loading (coroutine style)
--   coroutine.start(function()
--       local json = cache:GetResourceAsync("JSONFile", "uuid://config")
--       if json then print("loaded:", json.name) end
--   end)

--------------------------------------------------------------------------------
-- Subsystem references
--------------------------------------------------------------------------------

local cache_ = GetCache and GetCache()
if not cache_ then
    log:Write(LOG_ERROR, "GetResourceAsync:GetCache() unavailable, cache:GetResourceAsync will not be installed")
    return
end

local ResourceCache_meta = getmetatable(cache_)
if not ResourceCache_meta then
    log:Write(LOG_ERROR, "ResourceCacheExtensions: ResourceCache metatable unavailable, extensions will not be installed")
    return
end

local dm_ = GetDownloadManager and GetDownloadManager()

-- Pre-check required C++ APIs
local invalid_ = false
if not dm_ then
    log:Write(LOG_WARNING, "ResourceCacheExtensions: GetDownloadManager() unavailable")
    invalid_ = true
elseif not dm_.DownloadResource then
    log:Write(LOG_WARNING, "ResourceCacheExtensions: dm:DownloadResource unavailable")
    invalid_ = true
end
local hasReleaseResource_ = cache_.ReleaseResource ~= nil

--------------------------------------------------------------------------------
-- cache:DownloadResource(uri [, onComplete])
-- Proxy to DownloadManager:DownloadResource
-- Wraps task callback to (success, errorMessage) for simplicity
--------------------------------------------------------------------------------

ResourceCache_meta.DownloadResource = function(self, uri, onComplete)
    if invalid_ then
        log:Write(LOG_ERROR, "DownloadResource: unavailable for '" .. uri .. "'")
        return
    end
    if onComplete then
        dm_:DownloadResource(uri, function(task)
            if task then
                onComplete(task:IsSuccess(), task.errorMessage)
            else
                onComplete(false, "download task is nil")
            end
        end)
    else
        dm_:DownloadResource(uri)
    end
end

--------------------------------------------------------------------------------
-- cache:DownloadResources(uris [, onComplete [, onProgress]])
-- Proxy to DownloadManager:DownloadResources
-- Returns groupId
--------------------------------------------------------------------------------

ResourceCache_meta.DownloadResources = function(self, uris, onComplete, onProgress)
    if invalid_ then
        log:Write(LOG_ERROR, "DownloadResources: unavailable")
        return 0
    end
    return dm_:DownloadResources(uris, onComplete, onProgress)
end

--------------------------------------------------------------------------------
-- cache:CancelDownload(uri)
-- Proxy to DownloadManager:CancelResourceTask
--------------------------------------------------------------------------------

ResourceCache_meta.CancelDownload = function(self, uri)
    if invalid_ then return false end
    return dm_:CancelResourceTask(uri)
end

--------------------------------------------------------------------------------
-- cache:CancelDownloadGroup(groupId)
-- Proxy to DownloadManager:CancelGroup
--------------------------------------------------------------------------------

ResourceCache_meta.CancelDownloadGroup = function(self, groupId)
    if invalid_ then return end
    dm_:CancelGroup(groupId)
end

--------------------------------------------------------------------------------
-- cache:GetDownloadState(uri)
-- Proxy to DownloadManager:GetResourceTaskState
--------------------------------------------------------------------------------

ResourceCache_meta.GetDownloadState = function(self, uri)
    if invalid_ then return DOWNLOAD_FAILED end
    return dm_:GetResourceTaskState(uri)
end

--------------------------------------------------------------------------------
-- cache:GetResourceAsync(typeName, uri [, callback])
--
-- With callback:    callback(resource) is called with the loaded resource or nil.
-- Without callback: must be inside coroutine.start(); yields until resource is ready.
--------------------------------------------------------------------------------

--- @param self ResourceCache
--- @param typeName string   Resource type name (e.g. "JSONFile", "XMLFile", "BinaryFile")
--- @param uri string        Resource URI (uuid://, alias://, fs_path)
--- @param callback? fun(resource: Resource|nil)
--- @return Resource|nil     Only in coroutine mode (no callback)
ResourceCache_meta.GetResourceAsync = function(self, typeName, uri, callback)
    if invalid_ then
        log:Write(LOG_ERROR, "GetResourceAsync: unavailable for '" .. uri .. "'")
        if callback then
            callback(nil)
            return
        end
        return nil
    end

    -- Fast path: file already exists locally
    if self:Exists(uri) then
        local resource = self:GetResource(typeName, uri)
        if not resource and hasReleaseResource_ then
            -- null-cache hit, release and reload
            self:ReleaseResource(typeName, uri, true)
            resource = self:GetResource(typeName, uri)
        end
        if callback then
            callback(resource)
        end
        return resource
    end

    -- Download then load (DownloadManager clears negative cache before download)
    local function onDownloaded(task)
        if task:IsSuccess() then
            return self:GetResource(typeName, uri)
        end
        log:Write(LOG_ERROR, "GetResourceAsync:download failed for '" .. uri
            .. "': " .. (task.errorMessage or "unknown error"))
        return nil
    end

    -- Callback mode
    if callback then
        dm_:DownloadResource(uri, function(task)
            callback(onDownloaded(task))
        end)
        return
    end

    -- Coroutine mode
    local co = coroutine.running()
    if not co then
        log:Write(LOG_ERROR, "GetResourceAsync: requires callback or coroutine for '" .. uri .. "'")
        return nil
    end

    dm_:DownloadResource(uri, function(task)
        local ok, err = coroutine.resume(co, onDownloaded(task))
        if not ok then
            log:Write(LOG_ERROR, "GetResourceAsync: coroutine resume failed for '" .. uri .. "': " .. tostring(err))
        end
    end)

    return coroutine.yield()
end

--------------------------------------------------------------------------------
-- Download Observer
--
-- cache:ObserveDownloads(onProgress [, onComplete])  → observerId
-- cache:StopObservingDownloads(observerId)
--
-- Monitors background download activity without knowing specific resources.
-- Each observer session tracks its own totalCount / completedBytes.
-- Auto-ends when all active downloads complete (activeCount reaches 0).
--
-- onProgress(completedCount, totalCount, completedBytes)
-- onComplete(completedBytes)  -- optional, called when activeCount == 0
--
-- Multiple observers can coexist; a single C++ observer is lazily registered
-- and broadcasts to all active Lua observer sessions.
--------------------------------------------------------------------------------

local observers_ = {}
local nextObserverId_ = 1
local globalObserverInstalled_ = false

--- Install or remove the single C++ observer based on active Lua observers
local function syncGlobalObserver()
    local hasObservers = next(observers_) ~= nil
    if hasObservers and not globalObserverInstalled_ then
        dm_:SetDownloadObserver(function(activeCount, completedTaskBytes)
            -- Broadcast to all active observers; collect finished ids
            local finished = nil
            for id, obs in pairs(observers_) do
                -- Track totalCount changes
                if activeCount > obs.prevActive then
                    -- New downloads started during observation
                    obs.totalCount = obs.totalCount + (activeCount - obs.prevActive)
                end
                obs.completedBytes = obs.completedBytes + completedTaskBytes
                obs.prevActive = activeCount

                local completedCount = obs.totalCount - activeCount
                if obs.onProgress then
                    obs.onProgress(completedCount, obs.totalCount, obs.completedBytes)
                end

                if activeCount == 0 and obs.onComplete then
                    if not finished then finished = {} end
                    finished[#finished + 1] = id
                end
            end

            -- Auto-end finished observers (safe: iterates separate `finished` list,
            -- so onComplete calling ObserveDownloads won't break iteration)
            if finished then
                for _, id in ipairs(finished) do
                    local obs = observers_[id]
                    if obs and obs.onComplete then
                        obs.onComplete(obs.completedBytes)
                    end
                    observers_[id] = nil
                end
                syncGlobalObserver()
            end
        end)
        globalObserverInstalled_ = true
    elseif not hasObservers and globalObserverInstalled_ then
        dm_:ClearDownloadObserver()
        globalObserverInstalled_ = false
    end
end

--- Start observing background downloads.
--- With onComplete: auto-ends when activeCount reaches 0.
--- Without onComplete: persists until StopObservingDownloads is called.
--- @param onProgress fun(completedCount: integer, totalCount: integer, completedBytes: number)
--- @param onComplete? fun(completedBytes: number) Called when activeCount reaches 0 (enables auto-end)
--- @return integer observerId Use with StopObservingDownloads to cancel
ResourceCache_meta.ObserveDownloads = function(self, onProgress, onComplete)
    if invalid_ then
        log:Write(LOG_ERROR, "ObserveDownloads: unavailable")
        return 0
    end

    local id = nextObserverId_
    nextObserverId_ = nextObserverId_ + 1

    local activeCount = dm_.activeCount
    observers_[id] = {
        prevActive = activeCount,
        totalCount = activeCount,
        completedBytes = 0,
        onProgress = onProgress,
        onComplete = onComplete,
    }

    -- If already idle and has onComplete, fire immediately
    if activeCount == 0 and onComplete then
        if onProgress then onProgress(0, 0, 0) end
        onComplete(0)
        observers_[id] = nil
        return id
    end

    syncGlobalObserver()
    return id
end

--- Stop observing downloads early (before activeCount reaches 0).
--- @param observerId integer ID returned by ObserveDownloads
ResourceCache_meta.StopObservingDownloads = function(self, observerId)
    if observers_[observerId] then
        observers_[observerId] = nil
        syncGlobalObserver()
    end
end
