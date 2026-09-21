local AbyssLeaderboard = {}

AbyssLeaderboard.MODE_ENDLESS = "endless"
AbyssLeaderboard.MODE_HARDCORE = "hardcore"

-- Current builds submit only S2. The original S1 keys remain read-only here;
-- shutting off old-client writes requires a platform cutoff/snapshot.
AbyssLeaderboard.SEASON = 2
AbyssLeaderboard.FLOOR_KEY = "diggin_abyss_s2_tower_floor"
AbyssLeaderboard.COIN_KEY = "diggin_abyss_s2_tower_coins"
AbyssLeaderboard.HARDCORE_FLOOR_KEY = "diggin_abyss_s2_hardcore_floor"
AbyssLeaderboard.HARDCORE_COIN_KEY = "diggin_abyss_s2_hardcore_coins"

local function normalizeMode(mode)
    return mode == AbyssLeaderboard.MODE_HARDCORE
        and AbyssLeaderboard.MODE_HARDCORE or AbyssLeaderboard.MODE_ENDLESS
end

local function validUserId(userId)
    if userId == nil then return false end
    local value = tostring(userId)
    return value ~= "" and value ~= "0"
end

local function currentUserId()
    local userId = clientCloud and clientCloud.userId or nil
    if validUserId(userId) then return userId end
    -- On some mobile runtimes lobby is ready one frame before clientCloud's
    -- convenience property.  Both values identify the same signed-in player.
    if lobby and lobby.GetMyUserId then
        local ok, lobbyUserId = pcall(function() return lobby:GetMyUserId() end)
        if ok and validUserId(lobbyUserId) then return lobbyUserId end
    end
    return nil
end

local function finishOnce(callback)
    local finished = false
    return function(...)
        if finished then return end
        finished = true
        if callback then callback(...) end
    end
end

local function errorReason(code, reason, fallback)
    if tonumber(code) == -2 then return "timeout" end
    local value = tostring(reason or code or fallback or "cloud_failed")
    if value:lower():find("timeout", 1, true) or value:find("超时", 1, true) then return "timeout" end
    return value
end

function AbyssLeaderboard.GetKeys(mode, season)
    if season == 1 then
        if normalizeMode(mode) == AbyssLeaderboard.MODE_HARDCORE then
            return "diggin_abyss_hardcore_floor", "diggin_abyss_hardcore_coins"
        end
        return "diggin_abyss_tower_floor", "diggin_abyss_tower_coins"
    end
    if normalizeMode(mode) == AbyssLeaderboard.MODE_HARDCORE then
        return AbyssLeaderboard.HARDCORE_FLOOR_KEY, AbyssLeaderboard.HARDCORE_COIN_KEY
    end
    return AbyssLeaderboard.FLOOR_KEY, AbyssLeaderboard.COIN_KEY
end

function AbyssLeaderboard.GetAvailability(operation)
    if not clientCloud then return false, "cloud_unavailable", nil end
    if operation == "submit" then
        if not clientCloud.Get or not clientCloud.SetInt then return false, "cloud_unavailable", nil end
    elseif not clientCloud.GetRankList or not clientCloud.GetUserRank then
        return false, "cloud_unavailable", nil
    end
    local userId = currentUserId()
    if not userId then return false, "not_logged_in", nil end
    return true, nil, userId
end

local function fallbackNickname(userId, isMe)
    if isMe then return "我" end
    local value = tostring(userId or "")
    return value ~= "" and ("玩家" .. value:sub(math.max(1, #value - 3))) or "未知玩家"
end

local function cleanNickname(value, fallback)
    value = tostring(value or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" or not utf8.len(value) then return fallback end
    local ending = utf8.offset(value, 13)
    return ending and value:sub(1, ending - 1) or value
end

-- Cloud runtimes have shipped both camelCase and underscored rank row fields.
-- Normalize at the boundary so the renderer never receives a blank name,
-- missing depth, or an invented sequential rank when an explicit rank exists.
function AbyssLeaderboard.NormalizeRankList(rankList, floorKey, coinKey, start, myUserId)
    local rows = {}
    start = math.max(0, math.floor(tonumber(start) or 0))
    for index, item in ipairs(rankList or {}) do
        local scores = type(item.iscore) == "table" and item.iscore
            or (type(item.scores) == "table" and item.scores)
            or (type(item.scoreMap) == "table" and item.scoreMap) or {}
        local userId = item.userId or item.user_id or item.uid
        local isMe = myUserId ~= nil and tostring(userId) == tostring(myUserId)
        local floor = scores[floorKey]
        if floor == nil and type(item.score) ~= "table" then floor = item.score end
        floor = floor == nil and item.floor or floor
        local coins = scores[coinKey]
        if coins == nil then coins = item.coins end
        rows[#rows + 1] = {
            rank = math.max(1, math.floor(tonumber(item.rank or item.position) or (start + index))),
            userId = userId,
            floor = math.max(0, math.floor(tonumber(floor) or 0)),
            coins = math.max(0, math.floor(tonumber(coins) or 0)),
            isMe = isMe,
            nickname = cleanNickname(item.nickname, fallbackNickname(userId, isMe)),
        }
    end
    return rows
end

local function writeRecord(mode, floor, coins, callback)
    local floorKey, coinKey = AbyssLeaderboard.GetKeys(mode)
    -- Auxiliary data is written first. The ranked floor is written last so a
    -- partial upload can never publish a rank with stale supporting data.
    clientCloud:SetInt(coinKey, coins, {
        ok = function()
            clientCloud:SetInt(floorKey, floor, {
                ok = function()
                    if callback then callback(true, "updated", floor) end
                end,
                error = function(code, reason)
                    if callback then callback(false, errorReason(code, reason, "floor_write_failed")) end
                end,
                timeout = function() if callback then callback(false, "timeout") end end,
            })
        end,
        error = function(code, reason)
            if callback then callback(false, errorReason(code, reason, "coin_write_failed")) end
        end,
        timeout = function() if callback then callback(false, "timeout") end end,
    })
end

-- Both boards are pure depth boards. Only a strictly deeper single run can
-- replace the stored result; run count, coins and local run score never break
-- ties or accumulate into rank.
function AbyssLeaderboard.Submit(mode, floor, coins, callback)
    if mode ~= AbyssLeaderboard.MODE_ENDLESS and mode ~= AbyssLeaderboard.MODE_HARDCORE then
        callback, coins, floor, mode = coins, floor, mode, AbyssLeaderboard.MODE_ENDLESS
    end
    mode = normalizeMode(mode)
    local finish = finishOnce(callback)
    local available, unavailableReason = AbyssLeaderboard.GetAvailability("submit")
    if not available then
        finish(false, unavailableReason)
        return false
    end
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    coins = math.max(0, math.floor(tonumber(coins) or 0))
    local floorKey = AbyssLeaderboard.GetKeys(mode)
    clientCloud:Get(floorKey, {
        ok = function(_, iscores)
            local previous = math.max(0, math.floor(tonumber(iscores and iscores[floorKey]) or 0))
            if floor <= previous then
                finish(true, "kept", previous)
            else
                writeRecord(mode, floor, coins, finish)
            end
        end,
        error = function(code, reason)
            finish(false, errorReason(code, reason, "record_read_failed"))
        end,
        timeout = function() finish(false, "timeout") end,
    })
    return true
end

function AbyssLeaderboard.FetchTop(mode, count, callback, season)
    mode = normalizeMode(mode)
    local finish = finishOnce(callback)
    local available, unavailableReason = AbyssLeaderboard.GetAvailability("fetch")
    if not available then
        finish({}, unavailableReason)
        return false
    end
    local floorKey, coinKey = AbyssLeaderboard.GetKeys(mode, season)
    clientCloud:GetRankList(floorKey, 0, math.max(1, math.floor(count or 10)), {
        ok = function(rankList) finish(rankList or {}, nil) end,
        error = function(code, reason) finish({}, errorReason(code, reason, "rank_list_failed")) end,
        timeout = function() finish({}, "timeout") end,
    }, coinKey)
    return true
end

function AbyssLeaderboard.FetchUserRank(mode, callback)
    mode = normalizeMode(mode)
    local finish = finishOnce(callback)
    local available, unavailableReason, userId = AbyssLeaderboard.GetAvailability("fetch")
    if not available then
        finish(nil, nil, unavailableReason)
        return false
    end
    local floorKey = AbyssLeaderboard.GetKeys(mode)
    clientCloud:GetUserRank(userId, floorKey, {
        ok = function(rank, floor)
            finish(rank, math.max(0, math.floor(tonumber(floor) or 0)), nil)
        end,
        error = function(code, reason) finish(nil, nil, errorReason(code, reason, "user_rank_failed")) end,
        timeout = function() finish(nil, nil, "timeout") end,
    })
    return true
end

-- GetUserRank is 1-based while GetRankList's start offset is 0-based, hence
-- rank - 6 for up to five players above and five below (plus self).
function AbyssLeaderboard.FetchNeighbors(mode, callback, season, onUpdated)
    mode = normalizeMode(mode)
    local finish = finishOnce(callback)
    local available, unavailableReason, currentUserId = AbyssLeaderboard.GetAvailability("fetch")
    if not available then
        finish(nil, unavailableReason)
        return false
    end
    local floorKey, coinKey = AbyssLeaderboard.GetKeys(mode, season)
    clientCloud:GetUserRank(currentUserId, floorKey, {
        ok = function(rank, score)
            rank = math.floor(tonumber(rank) or 0)
            if rank < 1 then
                finish({ status = "unranked", mode = mode, rank = nil, rows = {} }, nil)
                return
            end
            local start = math.max(0, rank - 6)
            local count = rank - start + 5
            clientCloud:GetRankList(floorKey, start, count, {
                ok = function(rankList)
                    local rows = AbyssLeaderboard.NormalizeRankList(rankList,
                        floorKey, coinKey, start, currentUserId)
                    local userIds = {}
                    for _, row in ipairs(rows) do
                        if row.userId ~= nil then userIds[#userIds + 1] = row.userId end
                    end
                    if #rows == 0 then
                        finish(nil, "empty_rank_list")
                        return
                    end
                    local result = {
                        status = "ready", mode = mode, rank = rank,
                        score = math.max(0, math.floor(tonumber(score) or 0)), rows = rows,
                    }
                    -- Ranking data is usable without nicknames.  Return it
                    -- immediately and let the asynchronous name lookup enrich
                    -- the same row objects later instead of keeping the page
                    -- stuck on “connecting”.
                    finish(result, nil)
                    if #userIds == 0 or type(GetUserNickname) ~= "function" then return end
                    GetUserNickname({
                        userIds = userIds,
                        onSuccess = function(nicknames)
                            local names = {}
                            for _, info in ipairs(nicknames or {}) do
                                local userId = info.userId or info.user_id or info.uid
                                names[tostring(userId)] = cleanNickname(info.nickname or info.name, "")
                            end
                            for _, row in ipairs(rows) do
                                local nickname = names[tostring(row.userId)]
                                if nickname and nickname ~= "" then row.nickname = nickname end
                            end
                            if onUpdated then onUpdated(rows) end
                        end,
                        onError = function() end,
                    })
                end,
                error = function(code, reason)
                    finish(nil, errorReason(code, reason, "rank_list_failed"))
                end,
                timeout = function() finish(nil, "timeout") end,
            }, coinKey)
        end,
        error = function(code, reason)
            finish(nil, errorReason(code, reason, "user_rank_failed"))
        end,
        timeout = function() finish(nil, "timeout") end,
    })
    return true
end

return AbyssLeaderboard
