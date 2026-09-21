-- LuaScripts/Utilities/Previews/UserInfo.lua
-- Unified nickname query API for both server and client
-- This is the single source of truth for nickname queries.
-- LobbyManager:GetUserNickname also delegates to this global function.

local TAG = "[UserInfo]"
local pendingRequests = {}

-- Client-side: subscribe to UserNicknameResponse for async callback dispatch
if SubscribeToEvent and not (_G.IsServerMode and _G.IsServerMode()) then
    SubscribeToEvent("UserNicknameResponse", function(eventType, eventData)
        local requestId = eventData["RequestId"]:GetInt()
        local callbacks = pendingRequests[requestId]
        if not callbacks then return end
        pendingRequests[requestId] = nil

        if eventData["Success"]:GetBool() then
            local nicknames = {}
            local json = eventData["Nicknames"]:GetString()
            if json and json ~= "" then
                local ok, parsed = pcall(cjson.decode, json)
                if ok and parsed and parsed.nicknames then
                    nicknames = parsed.nicknames
                end
            end
            if callbacks.onSuccess then callbacks.onSuccess(nicknames) end
        else
            if callbacks.onError then callbacks.onError(eventData["ErrorCode"]:GetInt()) end
        end
    end)
end

-- Cleanup stale pending requests (timeout = 30s), called lazily before each new request
local TIMEOUT_SECONDS = 30
local function cleanupStalePendingRequests()
    local now = os.time()
    for id, req in pairs(pendingRequests) do
        if now - req.timestamp > TIMEOUT_SECONDS then
            print(TAG .. " WARN: request " .. tostring(id) .. " timed out, cleaning up")
            pendingRequests[id] = nil
            if req.onError then
                pcall(req.onError, -2) -- -2 = timeout
            end
        end
    end
end

--- Batch query user nicknames (unified API for server and client)
--- Server: reads nick_name from connection identity (synchronous)
--- Client: queries via lobby C++ object (asynchronous)
--- @param options table
---   - userIds: table user ID list (required), e.g. {12345, 67890}
---   - onSuccess: function(nicknames) nicknames = { {userId=N, nickname="..."}, ... }
---   - onError: function(errorCode)
_G.GetUserNickname = function(options)
    local rawIds = options.userIds
    if not rawIds or #rawIds == 0 then
        print(TAG .. " ERROR: userIds is required")
        return
    end

    -- Normalize userIds: accept both number and string, convert to number
    local userIds = {}
    for i, id in ipairs(rawIds) do
        userIds[i] = tonumber(id) or 0
    end

    -- Server mode: resolve from SERVER_PLAYER_AUTH_INFOS (set by UrhoXServer C++)
    if _G.IsServerMode and _G.IsServerMode() then
        local authInfos = _G.SERVER_PLAYER_AUTH_INFOS or {}
        local nicknames = {}
        for _, uid in ipairs(userIds) do
            local info = authInfos[uid]
            nicknames[#nicknames + 1] = { userId = uid, nickname = (info and info.nickName) or "" }
        end
        if options.onSuccess then options.onSuccess(nicknames) end
        return
    end

    -- Client mode: query via lobby C++ object
    cleanupStalePendingRequests()

    if not lobby or not lobby.GetUserNickname then
        print(TAG .. " ERROR: lobby object or GetUserNickname not available")
        if options.onError then options.onError(-1) end
        return
    end

    local requestId = lobby:GetUserNickname(userIds)
    if not requestId or requestId < 0 then
        print(TAG .. " ERROR: lobby:GetUserNickname returned invalid requestId: " .. tostring(requestId))
        if options.onError then options.onError(-1) end
        return
    end

    pendingRequests[requestId] = {
        onSuccess = options.onSuccess,
        onError = options.onError,
        timestamp = os.time(),
    }
end
