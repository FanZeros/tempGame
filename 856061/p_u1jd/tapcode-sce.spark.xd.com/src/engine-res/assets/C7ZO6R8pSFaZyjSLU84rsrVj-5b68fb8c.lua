local M = {}

M.RUNTIME = "runtime"
M.PLUGIN = "plugin"

function M.Get()
    local getter = rawget(_G, "GetApplicationEnvironment")
    if type(getter) == "function" then
        local ok, value = pcall(getter)
        if ok and (value == M.RUNTIME or value == M.PLUGIN) then
            return value
        end
    end
    return M.RUNTIME
end

function M.IsPlugin()
    return M.Get() == M.PLUGIN
end

function M.IsRuntime()
    return M.Get() == M.RUNTIME
end

function M.RequirePlugin()
    if M.IsPlugin() then
        return true
    end
    return false, {
        code = "PLUGIN_ENVIRONMENT_REQUIRED",
        message = "Plugin API is only available in plugin environment",
        retryable = false,
    }
end

return M
