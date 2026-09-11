-- Intl rewarded-ad failure notice.

local TAG = "[RewardVideoAd]"
local COMING_SOON_MESSAGE = "This feature is coming soon."
local LUA_ENV_RUNTIME = 0

if type(GetLuaEnvironment) ~= "function" then
    return true
end

local environmentResult, luaEnvironment = pcall(GetLuaEnvironment)
if not environmentResult or luaEnvironment ~= LUA_ENV_RUNTIME then
    return true
end

if IsServerMode and IsServerMode() then
    return true
end

if type(HasAppArg) ~= "function" then
    return true
end

local ok, isIntl = pcall(HasAppArg, "intl")
if not ok or not isIntl then
    return true
end

if type(sdk) ~= "table" or type(sdk.ShowRewardVideoAd) ~= "function" then
    return true
end

local showRewardVideoAd = sdk.ShowRewardVideoAd

local function showComingSoonToast()
    local ok, err = pcall(function()
        local UI = require("urhox-libs/UI")
        if not UI.Toast or type(UI.Toast.Show) ~= "function" then
            return
        end
        if not UI.GetNVGContext() or not UI.GetRoot() or not UI.IsEnabled() then
            return
        end

        UI.Toast.Show({
            message = COMING_SOON_MESSAGE,
            variant = "info",
            duration = 3,
        })
    end)

    if not ok then
        print(TAG .. " failed to show toast: " .. tostring(err))
    end
end

sdk.ShowRewardVideoAd = function(self, callback, ...)
    local failureNotified = false

    local function notifyFailure()
        if failureNotified then
            return
        end
        failureNotified = true
        showComingSoonToast()
    end

    local callbackToPass = callback
    if callback == nil or type(callback) == "function" then
        callbackToPass = function(result, ...)
            if type(result) == "table" and result.success == false then
                notifyFailure()
            end

            if callback then
                return callback(result, ...)
            end
        end
    end

    return showRewardVideoAd(self, callbackToPass, ...)
end

return true
