local AbyssLeaderboard = require("diggin.AbyssLeaderboard")
local WorldTree = require("diggin.WorldTree")

local Controller = {}
Controller.__index = Controller

function Controller.New()
    return setmetatable({ status = "idle", rows = {}, rank = nil, score = nil, error = nil,
        returnMode = "world_tree", boardMode = AbyssLeaderboard.MODE_ENDLESS,
        hardcoreUnlocked = false, requestId = 0, retryCount = 0,
        season = 2, viewKind = "neighbors",
        retryDelay = 0, localBestFloor = 0, dataRevision = 0, _state = nil }, Controller)
end

function Controller:GetLocalBestFloor()
    local state = self._state
    if not state then return 0 end
    if state.GetBestAbyssFloor then return state:GetBestAbyssFloor(self.boardMode, self.season) end
    local value
    if self.season == 1 then
        value = self.boardMode == "hardcore" and state.bestAbyssHardcoreFloor or state.bestAbyssFloor
    else
        value = self.boardMode == "hardcore" and state.bestAbyssS2HardcoreFloor or state.bestAbyssS2Floor
    end
    return math.max(0, math.floor(tonumber(value) or 0))
end

function Controller:Refresh(isAutomaticRetry)
    if not isAutomaticRetry then self.retryCount = 0 end
    self.requestId = self.requestId + 1
    local requestId = self.requestId
    self.localBestFloor = self:GetLocalBestFloor()
    self.status, self.rows, self.rank, self.score, self.error = "loading", {}, nil, nil, nil
    local function finishFetch(result, err)
        if requestId ~= self.requestId then return end
        if not result then
            local reason = tostring(err or "unknown_error")
            if (reason == "not_logged_in" or reason == "timeout") and self.retryCount < 2 then
                self.status, self.error = "waiting_login", reason
                self.retryDelay = 0.8 + self.retryCount * 1.2
            else
                self.status, self.error = "error", reason
            end
            return
        end
        self.status = result.status or "ready"
        self.rows, self.rank, self.score = result.rows or {}, result.rank, result.score
        self.dataRevision = self.dataRevision + 1
    end
    local function fetch()
        if requestId ~= self.requestId then return end
        if self.viewKind == "honor" then
            local honors = require("diggin.SeasonHonors")
            if self.season == 1 and honors.sealed then
                local rows = {}
                for rank, winner in ipairs(honors.winners[self.boardMode] or {}) do
                    rows[rank] = { rank = rank, userId = winner.userId, nickname = winner.nickname, floor = winner.floor }
                end
                finishFetch({ status = "ready", rows = rows }, nil)
                return
            end
            AbyssLeaderboard.FetchTop(self.boardMode, 3, function(items, err)
                if err then finishFetch(nil, err); return end
                local floorKey = AbyssLeaderboard.GetKeys(self.boardMode, self.season)
                local _, coinKey = AbyssLeaderboard.GetKeys(self.boardMode, self.season)
                local rows = AbyssLeaderboard.NormalizeRankList(items, floorKey, coinKey, 0, nil)
                local ids = {}
                for _, row in ipairs(rows) do
                    ids[#ids + 1] = row.userId
                end
                finishFetch({ status = "ready", rows = rows }, nil)
                if #ids > 0 and type(GetUserNickname) == "function" then
                    GetUserNickname({ userIds = ids, onSuccess = function(names)
                        for _, name in ipairs(names or {}) do
                            local nameUserId = name.userId or name.user_id or name.uid
                            local nickname = tostring(name.nickname or name.name or "")
                            for _, row in ipairs(rows) do
                                if tostring(row.userId) == tostring(nameUserId)
                                    and nickname ~= "" and utf8.len(nickname) then row.nickname = nickname end
                            end
                        end
                        if requestId == self.requestId then self.dataRevision = self.dataRevision + 1 end
                    end, onError = function() end })
                end
            end, self.season)
        else
            AbyssLeaderboard.FetchNeighbors(self.boardMode, finishFetch, self.season, function(rows)
                if requestId ~= self.requestId then return end
                self.rows = rows or self.rows
                self.dataRevision = self.dataRevision + 1
            end)
        end
    end
    -- A run completed while account/cloud services were unavailable still
    -- has a durable local record.  As soon as login becomes ready, opening or
    -- refreshing this page backfills that depth before loading neighbours.
    if self.season == 2 and self.localBestFloor > 0 then
        local callbackRan = false
        local started = AbyssLeaderboard.Submit(self.boardMode, self.localBestFloor, 0, function()
            callbackRan = true
            fetch()
        end)
        if not started and not callbackRan then fetch() end
    else
        fetch()
    end
end

function Controller:Update(dt)
    if self.status ~= "waiting_login" then return end
    self.retryDelay = math.max(0, (self.retryDelay or 0) - math.max(0, tonumber(dt) or 0))
    if self.retryDelay <= 0 then
        self.retryCount = self.retryCount + 1
        self:Refresh(true)
    end
end

function Controller:Open(app, returnMode, boardMode)
    self._state = app.state
    self.returnMode = returnMode == "ended" and "ended" or "world_tree"
    self.hardcoreUnlocked = WorldTree.IsFullyMaxed(app.state)
    local requested = boardMode
    if not requested and self.returnMode == "ended" then requested = app.lastAbyssMode end
    if requested == AbyssLeaderboard.MODE_HARDCORE and self.hardcoreUnlocked then
        self.boardMode = AbyssLeaderboard.MODE_HARDCORE
    elseif self.boardMode == AbyssLeaderboard.MODE_HARDCORE and not self.hardcoreUnlocked then
        self.boardMode = AbyssLeaderboard.MODE_ENDLESS
    elseif requested == AbyssLeaderboard.MODE_ENDLESS then
        self.boardMode = AbyssLeaderboard.MODE_ENDLESS
    end
    app.mode = "abyss_leaderboard"
    self:Refresh()
end

function Controller:Close(app)
    self.requestId = self.requestId + 1
    self.status = "idle"
    if self.returnMode == "ended" then app.mode = "ended" else app:OpenWorldTree() end
end

function Controller:HandleAction(app, id)
    if id == "leaderboard_season" then
        self.season = self.season == 2 and 1 or 2
        self:Refresh(); return true
    end
    if id == "leaderboard_honor" then
        self.viewKind = self.viewKind == "honor" and "neighbors" or "honor"
        self:Refresh(); return true
    end
    if id == "leaderboard_back" then self:Close(app); return true end
    if id == "leaderboard_refresh" then self:Refresh(); return true end
    if id == "leaderboard_endless" then
        self.boardMode = AbyssLeaderboard.MODE_ENDLESS
        self:Refresh()
        return true
    end
    if id == "leaderboard_hardcore" and self.hardcoreUnlocked then
        self.boardMode = AbyssLeaderboard.MODE_HARDCORE
        self:Refresh()
        return true
    end
    return false
end

return Controller
