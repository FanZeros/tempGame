-- LuaScripts/Utilities/Previews/Isolation_Client.lua
-- Project file isolation for game Lua VM (client mode).
-- Scopes all file write/read operations to the project's own savedata directory,
-- preventing one project from accessing another project's files.
--
-- Two-level savedata directory:
--   SAVEDATA_ROOT      = project-level: <project_download_root>/savedata/
--   SAVEUSERDATA_ROOT  = user-level:    SAVEDATA_ROOT .. "<UserId>/"
-- Scripts are isolated to SAVEUSERDATA_ROOT by default.
--
-- SAVEDATA_ROOT resolution priority:
--   1. __SAVEDATA_ROOT__ (C++ injection)
--   2. Derive from settings.json filesystem path (strip /assets/...)
--   3. Derive from main.lua filesystem path (entry script, always exists)
--   4. Fallback: GetRootDir()/savedata/<ProjectId>/

local iso = require('LuaScripts/Utilities/Previews/Isolation_Common')
local Warn = iso.Warn
local ClassName = iso.ClassName
local BlockMethod = iso.BlockMethod
local BlockProperty = iso.BlockProperty
local urlWhitelist = require('LuaScripts/Utilities/Previews/UrlWhitelist')

-- Capture whitelist functions before user scripts can tamper with package.loaded.
local _installHttpHooks = urlWhitelist.InstallHttpHooks
local _loadPolicyFromResource = urlWhitelist.LoadPolicyFromResource
local CLIENT_URL_WHITELIST_RESOURCE =
    "LuaScripts/Utilities/Previews/ClientUrlWhitelist.json"

-- Scrub isolation modules from package.loaded so user scripts cannot require()
-- them later and tamper with whitelist checks.
if package and package.loaded then
    package.loaded['LuaScripts/Utilities/Previews/UrlWhitelist'] = nil
    package.loaded['LuaScripts/Utilities/Previews/Isolation_Common'] = nil
    package.loaded['LuaScripts/Utilities/Previews/Isolation_Client'] = nil
end
urlWhitelist = nil
iso = nil

-- ============================================================================
-- HTTP isolation: client preview allows only client URL whitelist targets
-- ============================================================================

local clientUrlPolicy = _loadPolicyFromResource(CLIENT_URL_WHITELIST_RESOURCE)

if log then
    log:Write(LOG_INFO, string.format(
        "[Preview/Isolation_Client] Loaded client URL whitelist from %s (%d urls, %d domains)",
        CLIENT_URL_WHITELIST_RESOURCE,
        clientUrlPolicy.urlCount or 0,
        clientUrlPolicy.domainCount or 0
    ))
end

-- Enforce the whitelist on Network:MakeHttpRequest and HttpClient:Send.
_installHttpHooks(clientUrlPolicy, "client")

-- Keep HttpClient creation (http:Create()) available, but neuter manager-wide
-- operations on the shared HttpManager: CancelAllRequests would reach requests
-- that do not belong to this game, and the active-count getters leak unrelated
-- request state. Per-request control stays on HttpClient (Cancel / callbacks).
BlockMethod(HttpManager, "CancelAllRequests", nil)
BlockMethod(HttpManager, "GetActiveRequestCount", 0)
BlockProperty(HttpManager, "activeRequestCount")

-- ============================================================================
-- Savedata root (project-level)
-- Must be resolved BEFORE we block FileSystem getters and File:GetName below.
-- ============================================================================

--- Derive project download root from a known resource's filesystem path.
--- cache:GetFile routes through manifest, file:GetName returns absolute path:
---   .../update/tapcode-sce.spark.xd.com/src/p_ssla/assets/<hash>.json
--- Strip /assets/... to get the project root.
local function GetProjectRoot(resourceName)
    if not cache:Exists(resourceName) then return nil end
    local file = cache:GetFile(resourceName)
    if not file then return nil end
    local relativePath = file:GetName()
    file:Close()
    if not relativePath or relativePath == "" then return nil end
    -- GetName returns relative path; resolve to absolute via GetResourceFileName
    local fullPath = cache:GetResourceFileName(relativePath)
    if not fullPath or fullPath == "" then return nil end
    local root = fullPath:match("^(.+)/assets/")
    if root then return root .. "/" end
    return nil
end

local SAVEDATA_ROOT = __SAVEDATA_ROOT__
if not SAVEDATA_ROOT then
    local projectRoot = GetProjectRoot("settings.json")
                     or GetProjectRoot("main.lua")
    if projectRoot then
        SAVEDATA_ROOT = projectRoot .. "savedata/"
    else
        -- Last resort: UserDocumentsDir/temp/savedata/<ProjectId>/
        Warn("GetProjectRoot failed, falling back to UserDocumentsDir")
        local docDir = fileSystem:GetUserDocumentsDir()
        local projectId = GetProjectId and GetProjectId() or "unknown"
        SAVEDATA_ROOT = docDir .. "temp/savedata/" .. projectId .. "/"
    end
end

-- Ensure trailing slash
if SAVEDATA_ROOT:sub(-1) ~= "/" then
    SAVEDATA_ROOT = SAVEDATA_ROOT .. "/"
end

-- ============================================================================
-- Saveuserdata root (per-user, assembled in Lua for hot-update flexibility)
-- ============================================================================

-- New binaries: CEGlobal::SetUserId called in login pipeline before Lua VM starts.
-- Old binaries: GetUserId() returns 0 (CEGlobal::SetUserId not yet backported).
local userId = GetUserId and GetUserId() or 0
if userId == 0 then
    Warn("userId is 0, savedata will not be per-user isolated")
end
local SAVEUSERDATA_ROOT = SAVEDATA_ROOT .. tostring(userId) .. "/"

-- Create directories (must be before FileSystem wrapping below)
fileSystem:CreateDir(SAVEDATA_ROOT)

-- Migrate legacy savedata: old binaries stored under userId=0.
-- When upgrading to new binary with real userId, rename 0/ to <userId>/
-- so existing save data is preserved.
if userId ~= 0 then
    local legacyDir = SAVEDATA_ROOT .. "0/"
    if fileSystem:DirExists(legacyDir) and not fileSystem:DirExists(SAVEUSERDATA_ROOT) then
        local ok = fileSystem:Rename(legacyDir, SAVEUSERDATA_ROOT)
        if ok then
            print("[Isolation] Migrated savedata from 0/ to " .. tostring(userId) .. "/")
        else
            Warn("Failed to migrate savedata from 0/ to " .. tostring(userId) .. "/")
        end
    end
end

fileSystem:CreateDir(SAVEUSERDATA_ROOT)

-- ============================================================================
-- Path resolution
-- ============================================================================

local function ContainsTraversal(path)
    local p = path:gsub("\\", "/")
    return p == ".."
        or p:find("^%.%./") ~= nil     -- starts with ../
        or p:find("/%.%./") ~= nil     -- contains /../
        or p:find("/%.%.$") ~= nil     -- ends with /..
end

local function ResolvePath(path, operation)
    if not path then
        return nil, "empty path"
    end
    if path:find("\0") then
        return nil, "path contains null byte"
    end
    path = path:gsub("\\", "/")
    if ContainsTraversal(path) then
        return nil, "path contains '..': " .. path
    end
    if IsAbsolutePath(path) then
        return nil, operation .. " blocked: absolute path not allowed"
    end
    return SAVEUSERDATA_ROOT .. path
end

-- ============================================================================
-- tolua++ override helpers (path-dependent, client-specific)
--
-- NOTE on tolua++ .get tables:
--   tolua++ class_index_event only calls C functions from .get (lua_iscfunction check).
--   Lua function replacements silently fail. So we nil .get entries instead of replacing.
--   For properties that need a Lua getter, wrap __index on the type table (see File section).
-- ============================================================================

--- Wrap a method whose first arg is a file path: resolve to savedata before calling original.
--- @param class table     tolua++ type table (e.g. FileSystem, Image)
--- @param methodName string
--- @param op string       "read" or "write" (for error messages)
--- @param blockReturn any  value to return when path is rejected
local function WrapPathMethod(class, methodName, op, blockReturn)
    local orig = class[methodName]
    if not orig then return end
    local tag = ClassName(class)
    rawset(class, methodName, function(self, path, ...)
        if type(path) ~= "string" then
            return orig(self, path, ...)
        end
        local resolved, err = ResolvePath(path, op)
        if not resolved then
            Warn(tag .. ":" .. methodName .. " blocked: " .. err)
            return blockReturn
        end
        return orig(self, resolved, ...)
    end)
end

--- Wrap a method whose first TWO args are file paths (e.g. Copy, Rename).
local function WrapDualPathMethod(class, methodName, op, blockReturn)
    local orig = class[methodName]
    if not orig then return end
    local tag = ClassName(class)
    rawset(class, methodName, function(self, src, dest, ...)
        local rSrc, e1 = ResolvePath(src, op)
        if not rSrc then
            Warn(tag .. ":" .. methodName .. " blocked (src): " .. e1)
            return blockReturn
        end
        local rDest, e2 = ResolvePath(dest, op)
        if not rDest then
            Warn(tag .. ":" .. methodName .. " blocked (dest): " .. e2)
            return blockReturn
        end
        return orig(self, rSrc, rDest, ...)
    end)
end

-- ============================================================================
-- File isolation (special: mode-aware path wrapping + name stripping)
-- ============================================================================

-- File:Open / File:new / File:new_local / File() need mode-aware wrapping
-- because the second arg is a file mode, not part of the path.
local function WrapFilePathFunc(origFunc, apiName, blockReturn)
    return function(self, fileName, mode, ...)
        if fileName == nil then
            return origFunc(self)
        end
        if type(fileName) ~= "string" then
            Warn(apiName .. " blocked: non-string path")
            return blockReturn
        end
        local op = (mode == FILE_WRITE or mode == FILE_READWRITE) and "write" or "read"
        local resolved, err = ResolvePath(fileName, op)
        if not resolved then
            Warn(apiName .. " blocked: " .. err)
            return blockReturn
        end
        return origFunc(self, resolved, mode, ...)
    end
end

-- File:Open
local Original_File_Open = File.Open
rawset(File, 'Open', WrapFilePathFunc(Original_File_Open, "File:Open", false))

-- File:new
local Original_File_new = File.new
if Original_File_new then
    rawset(File, 'new', WrapFilePathFunc(Original_File_new, "File:new", nil))
end

-- File:new_local
local Original_File_new_local = File.new_local
if Original_File_new_local then
    rawset(File, 'new_local', WrapFilePathFunc(Original_File_new_local, "File:new_local", nil))
end

-- File() call syntax (__call metamethod)
local File_mt = getmetatable(File)
if File_mt and File_mt.__call then
    local orig_call = File_mt.__call
    File_mt.__call = WrapFilePathFunc(orig_call, "File()", nil)
end

-- File:GetName() / file.name — strip SAVEDATA_ROOT prefix so scripts only see relative paths
local Original_File_GetName = File.GetName
local function StrippedGetName(self)
    local name = Original_File_GetName(self)
    if name and name:sub(1, #SAVEUSERDATA_ROOT) == SAVEUSERDATA_ROOT then
        return name:sub(#SAVEUSERDATA_ROOT + 1)
    end
    return name
end
rawset(File, 'GetName', StrippedGetName)

-- Wrap File's __index to intercept "name" property access.
-- tolua++ .get only calls C functions, so we intercept at the __index level instead.
-- No recursion: class_index_event uses rawget internally.
do
    local orig_file_index = rawget(File, '__index')
    if orig_file_index then
        rawset(File, '__index', function(self, key)
            if key == "name" then
                return StrippedGetName(self)
            end
            return orig_file_index(self, key)
        end)
    end
end

-- ============================================================================
-- FileSystem isolation
-- ============================================================================

-- Savedata-scoped write operations
WrapPathMethod(FileSystem, "CreateDir",           "write", false)
WrapPathMethod(FileSystem, "Delete",              "write", false)
WrapPathMethod(FileSystem, "SetLastModifiedTime", "write", false)

-- Savedata-scoped read operations
WrapPathMethod(FileSystem, "FileExists",          "read", false)
WrapPathMethod(FileSystem, "DirExists",           "read", false)
WrapPathMethod(FileSystem, "GetLastModifiedTime", "read", false)
WrapPathMethod(FileSystem, "ScanDir",             "read", {})

-- Dual-path operations
WrapDualPathMethod(FileSystem, "Copy",   "write", false)
WrapDualPathMethod(FileSystem, "Rename", "write", false)

-- Block dangerous operations
BlockMethod(FileSystem, "SetCurrentDir", false)

-- Block path getters that leak system directory structure
BlockMethod(FileSystem, "GetCurrentDir",        "")
BlockMethod(FileSystem, "GetProgramDir",        "")
BlockMethod(FileSystem, "GetUserDocumentsDir",  "")
BlockMethod(FileSystem, "GetAppPreferencesDir", "")
BlockMethod(FileSystem, "GetTemporaryDir",      "")

BlockProperty(FileSystem, "currentDir")
BlockProperty(FileSystem, "programDir")
BlockProperty(FileSystem, "userDocumentsDir")
BlockProperty(FileSystem, "temporaryDir")

-- ============================================================================
-- Image isolation
-- ============================================================================

WrapPathMethod(Image, "SaveBMP",  "write", false)
WrapPathMethod(Image, "SavePNG",  "write", false)
WrapPathMethod(Image, "SaveTGA",  "write", false)
WrapPathMethod(Image, "SaveJPG",  "write", false)
WrapPathMethod(Image, "SaveDDS",  "write", false)
WrapPathMethod(Image, "SaveWEBP", "write", false)

-- ============================================================================
-- C++ direct file write API isolation
-- These C++ methods create File objects internally, bypassing the Lua File wrapper.
-- Redirect writes to savedata directory.
-- ============================================================================

WrapPathMethod(Scene,     "Save",             "write", false)
WrapPathMethod(Scene,     "SaveXML",          "write", false)
WrapPathMethod(Scene,     "SaveJSON",         "write", false)
WrapPathMethod(JSONFile,  "Save",             "write", false)
WrapPathMethod(XMLFile,   "Save",             "write", false)
WrapPathMethod(Resource,  "Save",             "write", false)
WrapPathMethod(UIElement, "SaveXML",          "write", false)
WrapPathMethod(Input,     "SaveGestures",     "write", false)
WrapPathMethod(Input,     "SaveGesture",      "write", false)
WrapPathMethod(Graphics,  "BeginDumpShaders", "write", false)

-- ============================================================================
-- ResourceCache / DownloadManager — block interfaces that leak filesystem paths
-- ============================================================================

BlockMethod(ResourceCache,   "GetResourceDirs",    {})
BlockMethod(ResourceCache,   "GetResourceFileName", "")
BlockMethod(DownloadManager, "GetDefaultDirectory", "")

BlockProperty(ResourceCache,   "resourceDirs")
BlockProperty(DownloadManager, "defaultDirectory")

-- ============================================================================
-- Public API
-- ============================================================================

--- Returns the project-level savedata root path.
function GetSavedataRoot()
    return SAVEDATA_ROOT
end

--- Returns the per-user savedata root path (default isolation scope for scripts).
function GetSaveUserdataRoot()
    return SAVEUSERDATA_ROOT
end
