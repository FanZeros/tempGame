local Common = require "urhox-libs/Plugin/_Common"
local Environment = require "urhox-libs/Plugin/Environment"

local Files = {}

Files.REMOTE = "REMOTE"
Files.LOCAL = "LOCAL"
local syncMode = Files.REMOTE

local nativeFileOperation = rawget(_G, "__urhox_plugin_files_native_op")
if rawget(_G, "__urhox_plugin_files_backend") == nil and type(nativeFileOperation) == "function" then
    local function submit(operation, payload, done, transform)
        local json = rawget(_G, "cjson")
        if type(json) ~= "table" or type(json.encode) ~= "function" or type(json.decode) ~= "function" then
            Common.Defer(function()
                done(nil, { code = "BACKEND_UNAVAILABLE", message = "cjson is unavailable", retryable = false })
            end)
            return { Cancel = function() end }
        end
        local ok, encoded = pcall(json.encode, payload or {})
        if not ok then
            Common.Defer(function()
                done(nil, { code = "INVALID_REQUEST", message = tostring(encoded), retryable = false })
            end)
            return { Cancel = function() end }
        end
        nativeFileOperation(operation, encoded, function(responseJson, nativeError)
            if nativeError then done(nil, nativeError); return end
            local decodeOk, response = pcall(json.decode, responseJson)
            if not decodeOk or type(response) ~= "table" then
                done(nil, { code = "BACKEND_UNAVAILABLE", message = "invalid file backend response", retryable = false })
            elseif response.error then
                done(nil, response.error)
            elseif transform then
                local transformOk, value = pcall(transform, response.result)
                if transformOk then done(value, nil)
                else done(nil, { code = "BACKEND_UNAVAILABLE", message = tostring(value), retryable = false }) end
            else
                done(response.result, nil)
            end
        end)
        return { Cancel = function() end }
    end

    local backend = {}
    function backend:GetCapabilities(done) return submit("capabilities", {}, done) end
    function backend:List(path, done) return submit("list", { path = path }, done, function(v) return v.entries end) end
    function backend:Exists(path, done) return submit("exists", { path = path }, done, function(v) return v.exists end) end
    function backend:ReadText(path, done) return submit("readText", { path = path }, done, function(v) return v.text end) end
    function backend:ReadBinary(path, done) return submit("readBinary", { path = path }, done, function(v)
        assert(type(v) == "table" and type(v.bytesBase64) == "string", "binary response is invalid")
        local bytes = Common.Base64Decode(v.bytesBase64)
        assert(bytes ~= nil, "binary response is not valid base64")
        return bytes
    end) end
    function backend:WriteText(path, content, done) return submit("writeText", { path = path, content = content }, done) end
    function backend:WriteBinary(path, bytes, mime, done)
        if type(bytes) ~= "string" then
            done(nil, Common.Error("INVALID_REQUEST", "native binary backend requires a string", false))
            return { Cancel = function() end }
        end
        return submit("writeBinary", { path = path, bytesBase64 = Common.Base64Encode(bytes), mime = mime }, done)
    end
    function backend:Mkdir(path, done) return submit("mkdir", { path = path }, done) end
    function backend:Remove(path, done) return submit("remove", { path = path }, done) end
    function backend:Rename(fromPath, toPath, done)
        return submit("rename", { path = fromPath, toPath = toPath }, done)
    end
    rawset(_G, "__urhox_plugin_files_backend", backend)
end

local function validPath(path, allowRoot)
    if type(path) ~= "string" or path == "" then
        return false
    end
    if path:sub(1, 1) == "/" or path:sub(1, 1) == "~" or path:find("\\", 1, true)
        or path:find(":", 1, true) or path:find("//", 1, true) or path:find("%z") then
        return false
    end
    if path:sub(-1) == "/" and not allowRoot then
        return false
    end
    if path == "." or path == ".." then
        return false
    end
    for part in path:gmatch("[^/]+") do
        if part == "." or part == ".." then
            return false
        end
    end
    return true
end

local function writablePath(path, allowRoot)
    if not validPath(path, allowRoot) then
        return false, "INVALID_PATH"
    end
    local namespace = path:match("^(assets)/") or path:match("^(docs)/")
    if not namespace then
        return false, "PERMISSION_DENIED"
    end
    if not allowRoot and path == namespace .. "/" then
        return false, "PERMISSION_DENIED"
    end
    return true
end

local function check(callback)
    local ok, err = Environment.RequirePlugin()
    if not ok then
        return Common.Reject(callback, err.code, err.message, err.retryable)
    end
end

local function reject(callback, message)
    return Common.Reject(callback, "INVALID_PATH", message, false)
end

local function complete(callback, result, err)
    local cancelled = false
    Common.Defer(function()
        if not cancelled and callback then
            callback(result, err)
        end
    end)
    return {
        Cancel = function()
            cancelled = true
        end,
    }
end

local function parseSyncArguments(path, callback)
    if type(path) == "function" and callback == nil then
        callback = path
        path = nil
    end
    if path ~= nil and type(path) ~= "string" then
        return nil, callback, Common.Error("INVALID_REQUEST", "path must be a string", false)
    end
    if path ~= nil then
        local allowed, code = writablePath(path, false)
        if not allowed then
            return nil, callback, Common.Error(code or "INVALID_PATH", "sync path is not allowed", false)
        end
    end
    return path, callback, nil
end

local function backendSupports(method)
    local backend = Common.GetBackend("files")
    return (type(backend) == "table" or type(backend) == "userdata") and type(backend[method]) == "function"
end

local function call(method, args, callback)
    local rejected = check(callback)
    if rejected then
        return rejected
    end
    if args.n == nil then args.n = #args end
    return Common.Call("files", method, args, callback)
end

function Files.SetBackendForTesting(backend)
    Common.SetBackend("files", backend)
end

function Files.GetMode(callback)
    local rejected = check(callback)
    if rejected then
        return rejected
    end
    if backendSupports("GetMode") then
        return Common.Call("files", "GetMode", {}, callback)
    end
    return complete(callback, { mode = syncMode, supported = false }, nil)
end

function Files.SetMode(mode, callback)
    local rejected = check(callback)
    if rejected then
        return rejected
    end
    if type(mode) ~= "string" then
        return Common.Reject(callback, "INVALID_REQUEST", "mode must be a string", false)
    end
    mode = mode:upper()
    if mode ~= Files.REMOTE and mode ~= Files.LOCAL then
        return Common.Reject(callback, "INVALID_REQUEST", "mode must be REMOTE or LOCAL", false)
    end
    if backendSupports("SetMode") then
        return Common.Call("files", "SetMode", { mode }, function(result, err)
            if not err then
                syncMode = mode
            end
            if callback then
                callback(result, err)
            end
        end)
    end
    syncMode = mode
    return complete(callback, { mode = syncMode, supported = false }, nil)
end

function Files.SyncToRemote(path, callback)
    local normalizedPath, syncCallback, argumentError = parseSyncArguments(path, callback)
    local rejected = check(syncCallback)
    if rejected then
        return rejected
    end
    if argumentError then
        return Common.Reject(syncCallback, argumentError.code, argumentError.message, argumentError.retryable)
    end
    if backendSupports("SyncToRemote") then
        return Common.Call("files", "SyncToRemote", table.pack(normalizedPath), syncCallback)
    end
    return complete(syncCallback, { path = normalizedPath, synced = false, supported = false }, nil)
end

function Files.SyncToLocal(path, callback)
    local normalizedPath, syncCallback, argumentError = parseSyncArguments(path, callback)
    local rejected = check(syncCallback)
    if rejected then
        return rejected
    end
    if argumentError then
        return Common.Reject(syncCallback, argumentError.code, argumentError.message, argumentError.retryable)
    end
    if backendSupports("SyncToLocal") then
        return Common.Call("files", "SyncToLocal", table.pack(normalizedPath), syncCallback)
    end
    return complete(syncCallback, { path = normalizedPath, synced = false, supported = false }, nil)
end

function Files.GetCapabilities(callback)
    return call("GetCapabilities", {}, callback)
end

function Files.List(path, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if path == nil then path = "" end
    if path ~= "" and not validPath(path, false) then return reject(callback, "virtual path is invalid") end
    return call("List", { path }, callback)
end

function Files.Exists(path, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if not validPath(path, false) then return reject(callback, "virtual path is invalid") end
    return call("Exists", { path }, callback)
end

function Files.ReadText(path, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if not validPath(path, false) then return reject(callback, "virtual path is invalid") end
    return call("ReadText", { path }, callback)
end

function Files.ReadBinary(path, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if not validPath(path, false) then return reject(callback, "virtual path is invalid") end
    return call("ReadBinary", { path }, callback)
end

function Files.WriteText(path, content, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(content) ~= "string" then return Common.Reject(callback, "INVALID_REQUEST", "content must be a string", false) end
    local allowed, code = writablePath(path, false)
    if not allowed then return Common.Reject(callback, code or "INVALID_PATH", "write path is not allowed", false) end
    return call("WriteText", { path, content }, callback)
end

function Files.WriteBinary(path, bytes, mime, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(bytes) ~= "string" then
        return Common.Reject(callback, "INVALID_REQUEST", "bytes must be a string buffer", false)
    end
    if mime ~= nil and type(mime) ~= "string" then return Common.Reject(callback, "INVALID_REQUEST", "mime must be a string", false) end
    local allowed, code = writablePath(path, false)
    if not allowed then return Common.Reject(callback, code or "INVALID_PATH", "write path is not allowed", false) end
    return call("WriteBinary", table.pack(path, bytes, mime), callback)
end

function Files.Mkdir(path, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    local allowed, code = writablePath(path, false)
    if not allowed then return Common.Reject(callback, code or "INVALID_PATH", "mkdir path is not allowed", false) end
    return call("Mkdir", { path }, callback)
end

function Files.Remove(path, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    local allowed, code = writablePath(path, false)
    if not allowed then return Common.Reject(callback, code or "INVALID_PATH", "remove path is not allowed", false) end
    return call("Remove", { path }, callback)
end

function Files.Rename(fromPath, toPath, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    local fromAllowed, fromCode = writablePath(fromPath, false)
    local toAllowed, toCode = writablePath(toPath, false)
    if not fromAllowed or not toAllowed then
        return Common.Reject(callback, fromCode or toCode or "INVALID_PATH", "rename path is not allowed", false)
    end
    return call("Rename", { fromPath, toPath }, callback)
end

return Files
