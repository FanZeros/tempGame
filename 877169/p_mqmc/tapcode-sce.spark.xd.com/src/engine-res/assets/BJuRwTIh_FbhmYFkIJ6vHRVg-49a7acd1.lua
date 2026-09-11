-- LuaScripts/Utilities/Previews/Isolation_Common.lua
-- Shared isolation rules for both client and server modes.
-- Loaded by Isolation_Client.lua and Isolation_Server.lua via require.
--
-- On load, this module:
--   1. Removes dangerous globals (io, loadfile, dofile, PackageFile, NamedPipe)
--   1b. Sanitizes debug (only traceback/getinfo, removes getupvalue/getregistry etc.)
--   2. Sanitizes os (only clock/time/date/difftime)
--   3. Removes dangerous FileSystem methods (SystemCommand etc.)
--   4. Blocks Log:Open (prevents log redirection to arbitrary files)
--   5. Blocks non-HTTP network access (Connect/Server/etc.)
--   6. Returns helper functions for Client/Server specific isolation

local M = {}

-- ============================================================================
-- Helper functions (exported for Client/Server use)
-- ============================================================================

local function Warn(msg)
    if log then
        log:Write(LOG_WARNING, msg)
    end
end
M.Warn = Warn

--- Get the tolua++ class name from a class table.
--- tolua_newmetatable stores registry[metatable] = type_name (reverse mapping).
--- tolua.type() returns "class <name>" for class tables, we strip the "class " prefix.
local function ClassName(class)
    local tname = tolua.type(class)       -- "class File", "class FileSystem", etc.
    return tname:match("^class (.+)") or tname
end
M.ClassName = ClassName

--- Block a method: replace with a warning stub that returns blockReturn.
--- @param class table       tolua++ type table (e.g. File, FileSystem); nil is silently ignored
--- @param methodName string
--- @param blockReturn any   value the blocked method returns
local function BlockMethod(class, methodName, blockReturn)
    if not class then return end
    if not class[methodName] then return end
    local msg = ClassName(class) .. ":" .. methodName .. " is not allowed"
    rawset(class, methodName, function()
        if log then log:Write(LOG_ERROR, msg) end
        return blockReturn
    end)
end
M.BlockMethod = BlockMethod

--- Block a global function with a warning stub.
--- @param name string
--- @param blockReturn any
local function BlockGlobalFunction(name, blockReturn)
    if rawget(_G, name) == nil then return end
    local msg = name .. " is not allowed"
    rawset(_G, name, function()
        if log then log:Write(LOG_ERROR, msg) end
        return blockReturn
    end)
end
M.BlockGlobalFunction = BlockGlobalFunction

--- Nil a tolua++ .get property so property-style access returns nil.
--- tolua++ class_index_event only calls C functions from .get (lua_iscfunction check),
--- so Lua replacements silently fail. We nil the entry instead.
--- @param class table       tolua++ type table
--- @param propName string   property name in the .get table
local function BlockProperty(class, propName)
    if not class then return end
    local gt = rawget(class, ".get")
    if gt and gt[propName] then
        gt[propName] = nil
    end
end
M.BlockProperty = BlockProperty

--- Block an entire tolua++ class: remove all methods and properties, keep __gc for C++ destructor.
local function BlockClass(class)
    if not class then return end
    for k in pairs(class) do
        if k ~= "__gc" then rawset(class, k, nil) end
    end
end
M.BlockClass = BlockClass

--- Remove methods entirely (set to nil). For dangerous operations like SystemCommand.
local function RemoveMethods(class, methods)
    if not class then return end
    for _, name in ipairs(methods) do
        rawset(class, name, nil)
    end
end
M.RemoveMethods = RemoveMethods

-- ============================================================================
-- Shared isolation rules (executed on load)
-- ============================================================================

-- Block dangerous globals
PackageFile = nil
NamedPipe = nil
io = nil
loadfile = nil
dofile = nil

-- Block :delete() on ALL tolua++ class tables (must run BEFORE debug sanitization).
-- tolua++ registers a separate `delete` on each class table, so blocking RefCounted:delete
-- alone does NOT propagate to subclasses or unrelated types like VectorBuffer.
-- We iterate the Lua registry where tolua++ stores class tables (string key → table value with .collector).
if debug and debug.getregistry then
    local reg = debug.getregistry()
    for k, v in pairs(reg) do
        if type(k) == "string" and type(v) == "table" and rawget(v, "delete") then
            if k == "File" then
                -- File:delete → Close + warning
                local origClose = rawget(v, "Close") or v.Close
                if origClose then
                    rawset(v, "delete", function(self)
                        Warn("File:delete is not allowed, calling Close instead")
                        return origClose(self)
                    end)
                end
            else
                local msg = k .. ":delete is not allowed"
                rawset(v, "delete", function()
                    if log then log:Write(LOG_ERROR, msg) end
                end)
            end
        end
    end
end

-- Sanitize debug: only keep traceback and getinfo, remove sandbox-escape functions
-- (getregistry, getupvalue/setupvalue, getmetatable/setmetatable, sethook, getlocal/setlocal, upvaluejoin)
if debug then
    local safeDebug = {
        traceback = debug.traceback,
        getinfo = debug.getinfo,
    }
    debug = safeDebug
    if package and package.loaded then
        package.loaded.debug = safeDebug
    end
end

-- Sanitize package: block C module loading and prevent require() from restoring removed modules
if package then
    package.loadlib = nil
    package.cpath = ""
    -- Remove C module searchers (loaders[3]/[4] in Lua 5.1/LuaJIT, searchers[3]/[4] in Lua 5.4)
    local searchers = package.searchers or package.loaders
    if searchers then
        searchers[3] = nil
        searchers[4] = nil
    end
    if package.loaded then
        package.loaded.io = nil
        -- Note: package.loaded.debug is already set to safeDebug above (not nil)
    end
end

-- Sanitize os: only keep safe functions
if os then
    local safe = {
        clock = os.clock,
        time = os.time,
        date = os.date,
        difftime = os.difftime,
    }
    os = safe
    -- Prevent require("os") from restoring the original unsanitized table
    if package and package.loaded then
        package.loaded.os = safe
    end
end

-- Remove dangerous FileSystem methods
RemoveMethods(FileSystem, {
    "SystemCommand", "SystemRun", "SystemCommandAsync", "SystemRunAsync", "SystemOpen"
})

-- Block Log:Open to prevent redirecting log output to arbitrary files
BlockMethod(Log, "Open", false)

-- Block non-HTTP Network access
BlockMethod(Network, "Connect",                  false)
BlockMethod(Network, "ConnectWithTransport",     false)
BlockMethod(Network, "Disconnect",               nil)
BlockMethod(Network, "StartServer",              false)
BlockMethod(Network, "StartServerWithTransport", false)
BlockMethod(Network, "StopServer",               nil)
BlockMethod(Network, "AddServerTransport",       nil)
BlockMethod(Network, "StopServerTransport",      nil)
BlockMethod(Network, "SetPreferredTransport",    nil)
BlockMethod(Network, "StartNATClient",           nil)

return M
