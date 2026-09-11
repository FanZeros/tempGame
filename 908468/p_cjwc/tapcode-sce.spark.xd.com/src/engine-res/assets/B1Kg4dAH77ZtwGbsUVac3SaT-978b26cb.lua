local Common = {}

local backends = {}
local pending = {}
local eventHookInstalled = false

local function defer(fn)
    local timer = rawget(_G, "Timer")
    -- UrhoX exposes Timer as a constructor function in some runtime builds;
    -- only index it when the value is an object/table carrying the async API.
    if (type(timer) == "table" or type(timer) == "userdata") and type(timer.after) == "function" then
        local ok = pcall(timer.after, 0, fn)
        if ok then
            return
        end
    end

    pending[#pending + 1] = fn
    if not eventHookInstalled and type(rawget(_G, "SubscribeToEvent")) == "function" then
        eventHookInstalled = true
        SubscribeToEvent("BeginFrame", function()
            Common.Flush()
        end)
    end
end

function Common.Flush()
    if #pending == 0 then
        return
    end
    local current = pending
    pending = {}
    for _, fn in ipairs(current) do
        pcall(fn)
    end
end

function Common.Defer(fn)
    assert(type(fn) == "function", "Plugin callback must be a function")
    defer(fn)
end

function Common.SetBackend(kind, backend)
    backends[kind] = backend
end

function Common.GetBackend(kind)
    if backends[kind] ~= nil then
        return backends[kind]
    end
    local globalName = kind == "agent" and "__urhox_plugin_agent_backend" or "__urhox_plugin_files_backend"
    return rawget(_G, globalName)
end

local function errorObject(code, message, retryable)
    return { code = code, message = message, retryable = retryable == true }
end

function Common.Reject(callback, code, message, retryable)
    local cancelled = false
    Common.Defer(function()
        if not cancelled and callback then
            callback(nil, errorObject(code, message, retryable))
        end
    end)
    return {
        Cancel = function()
            cancelled = true
        end,
    }
end

local function invoke(backend, method, args, callback)
    local called = false
    local cancelled = false
    local delivered = false
    local function finish(result, err)
        if called then
            return
        end
        called = true
        Common.Defer(function()
            delivered = true
            if not cancelled and callback then
                callback(result, err)
            end
        end)
    end

    if args.n == nil then
        args.n = #args
    end
    local packed = table.pack(table.unpack(args, 1, args.n))
    packed.n = args.n + 1
    packed[packed.n] = finish
    local ok, handle = pcall(function()
        return backend[method](backend, table.unpack(packed, 1, packed.n))
    end)
    if not ok then
        finish(nil, errorObject("BACKEND_UNAVAILABLE", tostring(handle), false))
        handle = nil
    end
    return {
        Cancel = function()
            if cancelled or delivered then
                return
            end
            cancelled = true
            if not called and handle and type(handle.Cancel) == "function" then
                pcall(function() handle:Cancel() end)
            end
        end,
    }
end

function Common.Call(kind, method, args, callback)
    local backend = Common.GetBackend(kind)
    if type(backend) ~= "table" and type(backend) ~= "userdata" then
        return Common.Reject(callback, "BACKEND_UNAVAILABLE", "Plugin backend is not installed", false)
    end
    if type(backend[method]) ~= "function" then
        return Common.Reject(callback, "BACKEND_UNAVAILABLE", "Plugin backend method is unavailable: " .. method, false)
    end
    return invoke(backend, method, args, callback)
end

function Common.Error(code, message, retryable)
    return errorObject(code, message, retryable)
end

local base64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function Common.Base64Encode(value)
    assert(type(value) == "string", "Base64Encode requires a string")
    local result = {}
    for index = 1, #value, 3 do
        local a = value:byte(index) or 0
        local b = value:byte(index + 1)
        local c = value:byte(index + 2)
        local triple = a * 65536 + (b or 0) * 256 + (c or 0)
        result[#result + 1] = base64Alphabet:sub(math.floor(triple / 262144) % 64 + 1, math.floor(triple / 262144) % 64 + 1)
        result[#result + 1] = base64Alphabet:sub(math.floor(triple / 4096) % 64 + 1, math.floor(triple / 4096) % 64 + 1)
        result[#result + 1] = b and base64Alphabet:sub(math.floor(triple / 64) % 64 + 1, math.floor(triple / 64) % 64 + 1) or "="
        result[#result + 1] = c and base64Alphabet:sub(triple % 64 + 1, triple % 64 + 1) or "="
    end
    return table.concat(result)
end

function Common.Base64Decode(value)
    if type(value) ~= "string" or #value % 4 ~= 0 then
        return nil
    end
    local result = {}
    local function digit(character)
        if character == "=" then
            return nil
        end
        local position = base64Alphabet:find(character, 1, true)
        return position and position - 1
    end
    for index = 1, #value, 4 do
        local third, fourth = value:sub(index + 2, index + 2), value:sub(index + 3, index + 3)
        local a, b = digit(value:sub(index, index)), digit(value:sub(index + 1, index + 1))
        local c, d = digit(third), digit(fourth)
        if a == nil or b == nil or (c == nil and value:sub(index + 2, index + 2) ~= "=")
            or (d == nil and fourth ~= "=") or (third == "=" and fourth ~= "=")
            or ((third == "=" or fourth == "=") and index + 3 < #value) then
            return nil
        end
        local triple = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
        result[#result + 1] = string.char(math.floor(triple / 65536) % 256)
        if c ~= nil then
            result[#result + 1] = string.char(math.floor(triple / 256) % 256)
        end
        if d ~= nil then
            result[#result + 1] = string.char(triple % 256)
        end
    end
    return table.concat(result)
end

return Common
