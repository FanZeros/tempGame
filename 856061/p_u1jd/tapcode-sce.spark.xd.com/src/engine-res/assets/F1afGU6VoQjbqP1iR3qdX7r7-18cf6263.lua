-- LuaScripts/Utilities/Previews/Isolation_Server.lua
-- Server-mode file isolation: completely blocks ALL file system access.
-- On the server, game scripts have zero reason to touch the filesystem.

local iso = require('LuaScripts/Utilities/Previews/Isolation_Common')
local Warn = iso.Warn
local BlockMethod = iso.BlockMethod
local BlockProperty = iso.BlockProperty
local urlWhitelist = require('LuaScripts/Utilities/Previews/UrlWhitelist')

-- Capture function references into locals BEFORE user scripts can tamper with the module.
-- package.loaded caches the module table; without this defense, user scripts could do:
--   package.loaded['LuaScripts/Utilities/Previews/UrlWhitelist'].InstallHttpHooks = function() end
-- and bypass all whitelist checks.
local _installHttpHooks = urlWhitelist.InstallHttpHooks
local _loadPolicyFromResource = urlWhitelist.LoadPolicyFromResource
local _DEFAULT_RESOURCE = urlWhitelist.DEFAULT_RESOURCE

-- Scrub isolation modules from package.loaded so user scripts cannot require() and modify them.
-- The local variables above already hold direct function references, so the module tables
-- are no longer needed. This also prevents user scripts from discovering isolation internals.
if package and package.loaded then
    package.loaded['LuaScripts/Utilities/Previews/UrlWhitelist'] = nil
    package.loaded['LuaScripts/Utilities/Previews/Isolation_Common'] = nil
    package.loaded['LuaScripts/Utilities/Previews/Isolation_Server'] = nil
end
urlWhitelist = nil
iso = nil

-- ============================================================================
-- HTTP isolation: server preview uses URL whitelist
-- ============================================================================

-- Server preview keeps GetHttp/http/HttpManager/HttpClient available because
-- Network:MakeHttpRequest (old Civetweb API) does NOT support SSL — only HttpClient
-- (libhv) can make HTTPS requests. InstallHttpHooks enforces the whitelist at
-- HttpClient:Send() and Network:MakeHttpRequest before sending.
--
-- __SERVICE_URL_WHITELIST_RESOURCE__ is expected to be injected by the trusted host
-- environment before this isolation script loads. User Lua should not get a chance to
-- override it, but we still validate the type here and fall back to the built-in default
-- if the value is missing or malformed.
local injectedWhitelistResource = rawget(_G, "__SERVICE_URL_WHITELIST_RESOURCE__")
local WHITELIST_RESOURCE = _DEFAULT_RESOURCE
if injectedWhitelistResource ~= nil then
    if type(injectedWhitelistResource) == "string" and injectedWhitelistResource ~= "" then
        WHITELIST_RESOURCE = injectedWhitelistResource
    else
        Warn("[Preview/Isolation_Server] Ignoring invalid __SERVICE_URL_WHITELIST_RESOURCE__; expected non-empty string")
    end
end
local serviceUrlPolicy = _loadPolicyFromResource(WHITELIST_RESOURCE)

if log then
    log:Write(LOG_INFO, string.format(
        "[Preview/Isolation_Server] Loaded service URL whitelist from %s (%d urls, %d domains)",
        WHITELIST_RESOURCE,
        serviceUrlPolicy.urlCount or 0,
        serviceUrlPolicy.domainCount or 0
    ))
end

-- Enforce the whitelist on Network:MakeHttpRequest and HttpClient:Send. Server
-- preview keeps HttpManager/GetHttp/http fully available (no per-method blocks).
_installHttpHooks(serviceUrlPolicy)

-- ============================================================================
-- File: block all access
-- ============================================================================

BlockMethod(File, "Open",      false)
BlockMethod(File, "new",       nil)
BlockMethod(File, "new_local", nil)

-- File() call syntax — __call is a metamethod, BlockMethod can't handle it
local File_mt = getmetatable(File)
if File_mt and File_mt.__call then
    File_mt.__call = function()
        if log then log:Write(LOG_ERROR, "File() is not allowed") end
        return nil
    end
end

-- ============================================================================
-- FileSystem: block all access
-- ============================================================================

BlockMethod(FileSystem, "CreateDir",           false)
BlockMethod(FileSystem, "Delete",              false)
BlockMethod(FileSystem, "Copy",                false)
BlockMethod(FileSystem, "Rename",              false)
BlockMethod(FileSystem, "FileExists",          false)
BlockMethod(FileSystem, "DirExists",           false)
BlockMethod(FileSystem, "ScanDir",             {})
BlockMethod(FileSystem, "SetCurrentDir",       false)
BlockMethod(FileSystem, "SetLastModifiedTime", false)
BlockMethod(FileSystem, "GetLastModifiedTime", false)

-- Block path getters that leak server directory structure
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
-- Image: block all save
-- ============================================================================

BlockMethod(Image, "SaveBMP",  false)
BlockMethod(Image, "SavePNG",  false)
BlockMethod(Image, "SaveTGA",  false)
BlockMethod(Image, "SaveJPG",  false)
BlockMethod(Image, "SaveDDS",  false)
BlockMethod(Image, "SaveWEBP", false)

-- ============================================================================
-- C++ direct file write API: block all
-- These C++ methods create File objects internally, bypassing the Lua File wrapper.
-- ============================================================================

BlockMethod(Scene,     "Save",             false)
BlockMethod(Scene,     "SaveXML",          false)
BlockMethod(Scene,     "SaveJSON",         false)
BlockMethod(JSONFile,  "Save",             false)
BlockMethod(XMLFile,   "Save",             false)
BlockMethod(Resource,  "Save",             false)
BlockMethod(UIElement, "SaveXML",          false)
BlockMethod(Input,     "SaveGestures",     false)
BlockMethod(Input,     "SaveGesture",      false)
BlockMethod(Graphics,  "BeginDumpShaders", false)

-- ============================================================================
-- ResourceCache / DownloadManager — block interfaces that leak filesystem paths
-- ============================================================================

BlockMethod(ResourceCache,   "GetResourceDirs",     {})
BlockMethod(ResourceCache,   "GetResourceFileName",  "")
BlockMethod(DownloadManager, "GetDefaultDirectory",  "")

BlockProperty(ResourceCache,   "resourceDirs")
BlockProperty(DownloadManager, "defaultDirectory")
