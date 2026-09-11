local Common = require "urhox-libs/Plugin/_Common"
local Environment = require "urhox-libs/Plugin/Environment"
local Files = require "urhox-libs/Plugin/Files"

local Agent = {}
local completedExports = {}
local completedExportOrder = {}
local pendingExports = {}
local maxCompletedExports = 256

local function rememberCompletedExport(operationKey, result, err)
    if not completedExports[operationKey] then
        completedExportOrder[#completedExportOrder + 1] = operationKey
    end
    completedExports[operationKey] = { result = result, err = err }
    while #completedExportOrder > maxCompletedExports do
        local oldest = table.remove(completedExportOrder, 1)
        completedExports[oldest] = nil
    end
end

local function cancelExportSubscriber(operationKey, pending, subscriber)
    subscriber.callback = nil
    local hasSubscriber = false
    for _, current in ipairs(pending.subscribers) do
        if current.callback then hasSubscriber = true; break end
    end
    if not hasSubscriber and not pending.finished then
        pending.cancelled = true
        if pending.active and type(pending.active.Cancel) == "function" then pending.active:Cancel() end
        pendingExports[operationKey] = nil
    end
end

local nativeSubmit = rawget(_G, "__urhox_plugin_agent_native_submit")
local nativeCancel = rawget(_G, "__urhox_plugin_agent_native_cancel")
if rawget(_G, "__urhox_plugin_agent_backend") == nil and type(nativeSubmit) == "function" then
    local eventSubscribers = {}
    local nextEventSubscriber = 1
    local function submit(method, payload, done, requestId, transform)
        local json = rawget(_G, "cjson")
        if type(json) ~= "table" or type(json.encode) ~= "function" or type(json.decode) ~= "function" then
            Common.Defer(function()
                done(nil, { code = "AGENT_SDK_UNAVAILABLE", message = "cjson is unavailable", retryable = false })
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
        local nativeRequestId = nativeSubmit(method, encoded, function(responseJson, nativeError)
            if nativeError then
                done(nil, nativeError)
                return
            end
            local decodeOk, response = pcall(json.decode, responseJson)
            if not decodeOk or type(response) ~= "table" then
                done(nil, { code = "AGENT_SDK_UNAVAILABLE", message = "invalid Agent SDK response", retryable = false })
            elseif response.error then
                done(nil, response.error)
            else
                local transformOk, value = true, response.result
                if transform then
                    transformOk, value = pcall(transform, response.result)
                end
                if not transformOk then
                    done(nil, { code = "AGENT_SDK_UNAVAILABLE", message = tostring(value), retryable = false })
                else
                    done(value, nil)
                end
            end
        end, requestId)
        return {
            Cancel = function()
                if type(nativeCancel) == "function" then nativeCancel(nativeRequestId) end
            end,
        }
    end

    local backend = {}
    function backend:GetCapabilities(done) return submit("capabilities.get", {}, done) end
    function backend:CreateSession(input, done)
        local payload = {}
        for key, value in pairs(input) do payload[key] = value end
        if type(input.references) == "table" then
            payload.references = {}
            for index, reference in ipairs(input.references) do
                local copy = {}
                for key, value in pairs(reference) do copy[key] = value end
                if type(copy.data) == "string" then
                    copy.dataBase64 = Common.Base64Encode(copy.data)
                    copy.data = nil
                    copy.encoding = "base64"
                end
                payload.references[index] = copy
            end
        end
        return submit("session.create", payload, done, input.requestId)
    end
    function backend:SendPrompt(sessionId, input, done)
        return submit("turn.prompt", { sessionId = sessionId, input = input }, done, input.requestId)
    end
    function backend:Cancel(sessionId, turnId, done)
        return submit("turn.cancel", { sessionId = sessionId, turnId = turnId }, done)
    end
    function backend:Resume(sessionId, afterSequence, done)
        return submit("session.resume", { sessionId = sessionId, afterSequence = afterSequence }, done)
    end
    function backend:GetSession(sessionId, done) return submit("session.get", { sessionId = sessionId }, done) end
    function backend:ListArtifacts(sessionId, done)
        return submit("artifact.list", { sessionId = sessionId }, done, nil, function(value)
            assert(type(value) == "table" and type(value.artifacts) == "table", "artifact list response is invalid")
            return value.artifacts
        end)
    end
    function backend:ReadArtifact(sessionId, path, done)
        return submit("artifact.read", { sessionId = sessionId, path = path }, done, nil, function(value)
            assert(type(value) == "table" and type(value.bytesBase64) == "string", "artifact read response is invalid")
            local bytes = Common.Base64Decode(value.bytesBase64)
            assert(bytes ~= nil, "artifact read response is not valid base64")
            return bytes
        end)
    end
    function backend:DiscardSession(sessionId, done)
        return submit("session.discard", { sessionId = sessionId }, done)
    end
    function backend:OnEvent(done)
        local id = nextEventSubscriber
        nextEventSubscriber = nextEventSubscriber + 1
        eventSubscribers[id] = done
        return { Cancel = function() eventSubscribers[id] = nil end }
    end
    rawset(_G, "__urhox_plugin_agent_dispatch_event", function(eventJson)
        local json = rawget(_G, "cjson")
        if type(json) ~= "table" or type(json.decode) ~= "function" then return end
        local ok, event = pcall(json.decode, eventJson)
        if not ok or type(event) ~= "table" then return end
        for _, subscriber in pairs(eventSubscribers) do
            subscriber(event)
        end
    end)
    rawset(_G, "__urhox_plugin_agent_backend", backend)
end

local function check(callback)
    local ok, err = Environment.RequirePlugin()
    if not ok then
        return Common.Reject(callback, err.code, err.message, err.retryable)
    end
end

local function call(method, args, callback)
    local rejected = check(callback)
    if rejected then
        return rejected
    end
    if args.n == nil then args.n = #args end
    return Common.Call("agent", method, args, callback)
end

function Agent.Initialize(options)
    options = options or {}
    if options.backend ~= nil and type(options.backend) == "table" then
        Common.SetBackend("agent", options.backend)
    end
    return true
end

function Agent.SetBackendForTesting(backend)
    Common.SetBackend("agent", backend)
end

function Agent.GetCapabilities(callback)
    return call("GetCapabilities", {}, callback)
end

function Agent.CreateSession(input, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(input) ~= "table" or type(input.requestId) ~= "string" or input.requestId == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "CreateSession requires input.requestId", false)
    end
    return call("CreateSession", { input }, callback)
end

function Agent.SendPrompt(sessionId, input, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" or type(input) ~= "table"
        or type(input.requestId) ~= "string" or input.requestId == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "SendPrompt arguments are invalid", false)
    end
    local hasText = type(input.prompt) == "string" and input.prompt ~= ""
    if type(input.messages) == "table" then
        for _, message in ipairs(input.messages) do
            if type(message) == "table" and message.type == "text" and type(message.text) == "string"
                and message.text ~= "" then
                hasText = true
                break
            end
        end
    end
    if not hasText then
        return Common.Reject(callback, "INVALID_REQUEST", "SendPrompt requires prompt or text messages", false)
    end
    return call("SendPrompt", { sessionId, input }, callback)
end

function Agent.Cancel(sessionId, turnId, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" or type(turnId) ~= "string" or turnId == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "Cancel arguments are invalid", false)
    end
    return call("Cancel", { sessionId, turnId }, callback)
end

function Agent.Resume(sessionId, afterSequence, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" or (afterSequence ~= nil and type(afterSequence) ~= "number") then
        return Common.Reject(callback, "INVALID_REQUEST", "Resume arguments are invalid", false)
    end
    return call("Resume", { sessionId, afterSequence or 0 }, callback)
end

function Agent.GetSession(sessionId, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "sessionId is required", false)
    end
    return call("GetSession", { sessionId }, callback)
end

function Agent.ListArtifacts(sessionId, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "sessionId is required", false)
    end
    return call("ListArtifacts", { sessionId }, callback)
end

function Agent.ReadArtifact(sessionId, path, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" or type(path) ~= "string" or path == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "ReadArtifact arguments are invalid", false)
    end
    return call("ReadArtifact", { sessionId, path }, callback)
end

function Agent.ExportArtifacts(sessionId, mappings, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" or type(mappings) ~= "table"
        or type(mappings.requestId) ~= "string" or mappings.requestId == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "ExportArtifacts arguments are invalid", false)
    end
    local items = mappings.items or mappings
    if type(items) ~= "table" then
        return Common.Reject(callback, "INVALID_REQUEST", "ExportArtifacts items are invalid", false)
    end

    local requestId = mappings.requestId
    local operationKey = sessionId .. "\0" .. requestId
    if completedExports[operationKey] then
        local completed = completedExports[operationKey]
        local active = true
        Common.Defer(function()
            if active and callback then callback(completed.result, completed.err) end
        end)
        return { Cancel = function() active = false end }
    end

    local pending = pendingExports[operationKey]
    if pending then
        local subscriber = { callback = callback }
        pending.subscribers[#pending.subscribers + 1] = subscriber
        return { Cancel = function() cancelExportSubscriber(operationKey, pending, subscriber) end }
    end

    local firstSubscriber = { callback = callback }
    pending = { subscribers = { firstSubscriber }, active = nil, cancelled = false, finished = false }
    pendingExports[operationKey] = pending
    local exported = {}

    local function finish(result, err)
        if pending.finished or pending.cancelled then return end
        pending.finished = true
        pendingExports[operationKey] = nil
        rememberCompletedExport(operationKey, result, err)
        for _, subscriber in ipairs(pending.subscribers) do
            local currentSubscriber = subscriber
            Common.Defer(function()
                local target = currentSubscriber.callback
                currentSubscriber.callback = nil
                if target then target(result, err) end
            end)
        end
    end

    local function exportAt(index)
        if pending.cancelled then return end
        local mapping = items[index]
        if mapping == nil then
            finish({ requestId = requestId, exported = exported }, nil)
            return
        end
        if type(mapping) ~= "table" or type(mapping.source) ~= "string" or mapping.source == ""
            or type(mapping.target) ~= "string" or mapping.target == "" then
            finish(nil, Common.Error("INVALID_REQUEST", "artifact mapping requires source and target", false))
            return
        end
        if mapping.mode ~= nil and mapping.mode ~= "binary" and mapping.mode ~= "text" then
            finish(nil, Common.Error("INVALID_REQUEST", "artifact mapping mode is invalid", false))
            return
        end
        if mapping.source:sub(1, 1) == "/" or mapping.source:sub(1, 1) == "~"
            or mapping.source:find("\\", 1, true) or mapping.source:find(":", 1, true)
            or mapping.source:find("//", 1, true) or mapping.source:find("%z")
            or (not mapping.source:match("^result/") and not mapping.source:match("^generated/")
                and not mapping.source:match("^screenshots/")) then
            finish(nil, Common.Error("INVALID_PATH", "artifact source path is invalid", false))
            return
        end
        for part in mapping.source:gmatch("[^/]+") do
            if part == "." or part == ".." then
                finish(nil, Common.Error("INVALID_PATH", "artifact source path is invalid", false))
                return
            end
        end
        pending.active = Agent.ReadArtifact(sessionId, mapping.source, function(data, readErr)
            if readErr then finish(nil, readErr); return end
            local writer = mapping.mode == "text" and Files.WriteText or Files.WriteBinary
            local function onWritten(result, writeErr)
                if writeErr then finish(nil, writeErr); return end
                exported[#exported + 1] = { source = mapping.source, target = mapping.target, result = result }
                exportAt(index + 1)
            end
            if mapping.mode == "text" then
                pending.active = writer(mapping.target, data, onWritten)
            else
                pending.active = writer(mapping.target, data, mapping.mime, onWritten)
            end
        end)
    end

    Common.Defer(function() exportAt(1) end)
    return {
        Cancel = function()
            cancelExportSubscriber(operationKey, pending, firstSubscriber)
        end,
    }
end

function Agent.DiscardSession(sessionId, callback)
    local rejected = check(callback)
    if rejected then return rejected end
    if type(sessionId) ~= "string" or sessionId == "" then
        return Common.Reject(callback, "INVALID_REQUEST", "sessionId is required", false)
    end
    return call("DiscardSession", { sessionId }, callback)
end

function Agent.OnEvent(callback)
    if type(callback) ~= "function" then
        return function() end
    end
    local okEnvironment = Environment.RequirePlugin()
    if not okEnvironment then
        return function() end
    end
    local backend = Common.GetBackend("agent")
    if type(backend) ~= "table" and type(backend) ~= "userdata" then
        return function() end
    end
    if type(backend.OnEvent) ~= "function" then
        return function() end
    end
    local active = true
    local ok, handle = pcall(function()
        return backend:OnEvent(function(event)
            Common.Defer(function()
                if active then callback(event) end
            end)
        end)
    end)
    if not ok then
        return function() active = false end
    end
    return function()
        if not active then return end
        active = false
        if type(handle) == "function" then
            pcall(handle)
        elseif handle and type(handle.Cancel) == "function" then
            pcall(function() handle:Cancel() end)
        end
    end
end

return Agent
