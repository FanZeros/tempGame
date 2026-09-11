local RewardAds = {}
RewardAds.__index = RewardAds

local DEFAULT_TIMEOUT = 120

local function notify(callback, event)
    if callback then callback(event) end
end

function RewardAds.New(battle, sdkApi, timeout)
    return setmetatable({
        battle = battle,
        sdk = sdkApi,
        timeout = math.max(1, tonumber(timeout) or DEFAULT_TIMEOUT),
        pending = false,
        pendingPlacement = nil,
        elapsed = 0,
        finish = nil,
    }, RewardAds)
end

function RewardAds:IsPending(placement)
    if placement ~= nil then
        return self.pending == true and self.pendingPlacement == placement
    end
    return self.pending == true
end

function RewardAds:GetPendingPlacement()
    return self.pendingPlacement
end

function RewardAds:_Request(options, callback)
    if self.pending then
        notify(callback, { phase = "failure", placement = options.placement, message = "广告正在播放，请稍候" })
        return false
    end

    local value, reason, requestId = options.getOffer(self.battle)
    if value == nil then
        notify(callback, {
            phase = "failure",
            placement = options.placement,
            message = reason or "当前奖励不可领取",
        })
        return false
    end
    if not self.sdk or type(self.sdk.ShowRewardVideoAd) ~= "function" then
        notify(callback, {
            phase = "failure",
            placement = options.placement,
            message = "当前环境暂不支持广告",
        })
        return false
    end

    self.pending = true
    self.pendingPlacement = options.placement
    self.elapsed = 0
    notify(callback, {
        phase = "loading",
        placement = options.placement,
        amount = value,
        requestId = requestId,
        message = options.loadingMessage(value),
    })
    print("RewardAd " .. options.placement .. " request started; request=" .. tostring(requestId))

    local completed = false
    local callbackFired = false
    local function finish(result)
        if completed then
            print("RewardAd duplicate or late result ignored")
            return
        end
        completed = true
        self.pending = false
        self.pendingPlacement = nil
        self.elapsed = 0
        self.finish = nil

        if result and result.success == true then
            local ok, reward, message = options.claim(self.battle, requestId)
            notify(callback, {
                phase = ok and "success" or "failure",
                placement = options.placement,
                amount = reward or 0,
                requestId = requestId,
                message = message or (ok and "奖励已领取" or "奖励领取失败"),
            })
            print("RewardAd " .. options.placement .. " " .. (ok and "granted" or "denied")
                .. "; request=" .. tostring(requestId))
            return
        end

        local rawMessage = result and result.msg or "广告暂不可用"
        local userMessage = rawMessage == "embed manual close"
            and "需完整观看广告才能获得奖励"
            or "广告暂不可用，请稍后重试"
        notify(callback, {
            phase = "failure",
            placement = options.placement,
            amount = 0,
            requestId = requestId,
            message = userMessage,
            rawMessage = rawMessage,
        })
        print("RewardAd " .. options.placement .. " failed: " .. tostring(rawMessage))
    end
    self.finish = finish

    local accepted = self.sdk:ShowRewardVideoAd(function(result)
        callbackFired = true
        finish(result)
    end)
    if accepted == false and not callbackFired then
        finish({ success = false, msg = "request not accepted" })
    end
    return accepted ~= false
end

function RewardAds:RequestNightGold(callback)
    return self:_Request({
        placement = "night_gold",
        getOffer = function(battle) return battle:GetNightGoldAdOffer() end,
        claim = function(battle, requestId) return battle:ClaimNightGoldFromRewardAd(requestId) end,
        loadingMessage = function(amount)
            return "请完整观看广告，成功后额外获得 +" .. tostring(amount) .. " 金币"
        end,
    }, callback)
end

function RewardAds:RequestDefeatRevive(callback)
    return self:_Request({
        placement = "defeat_revive",
        getOffer = function(battle) return battle:GetDefeatReviveAdOffer() end,
        claim = function(battle, requestId) return battle:ClaimDefeatReviveFromRewardAd(requestId) end,
        loadingMessage = function(amount)
            return "完整观看后城墙恢复 " .. tostring(amount) .. "% 并继续本夜"
        end,
    }, callback)
end

function RewardAds:RequestNightSupply(callback)
    return self:_Request({
        placement = "night_supply",
        getOffer = function(battle) return battle:GetNightSupplyAdOffer() end,
        claim = function(battle, requestId) return battle:ClaimNightSupplyFromRewardAd(requestId) end,
        loadingMessage = function(amount)
            return "完整观看后下一夜城墙上限 +" .. tostring(amount) .. "%"
        end,
    }, callback)
end

function RewardAds:Update(dt)
    if not self.pending then return end
    self.elapsed = self.elapsed + math.max(0, tonumber(dt) or 0)
    if self.elapsed < self.timeout then return end
    local finish = self.finish
    if finish then
        print("RewardAd " .. tostring(self.pendingPlacement) .. " timed out")
        finish({ success = false, msg = "callback timeout" })
    end
end

return RewardAds
