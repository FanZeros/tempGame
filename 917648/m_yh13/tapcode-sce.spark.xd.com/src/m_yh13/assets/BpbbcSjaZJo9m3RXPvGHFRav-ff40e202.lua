local Config = require("diggin.Config")

local Ads = {}
local previewAdUIPrepared = false

-- Maker's desktop FakeAd overlay imports UI/Core/UI directly.  That bypasses
-- urhox-libs/UI/init.lua, where UI.Inspector is normally registered, while
-- preview mode still asks UI.Init() to start the inspector.  Register it before
-- the SDK can open FakeAd so the overlay does not emit
-- "UI Inspector requested but failed to load".
local function preparePreviewAdUI()
    if previewAdUIPrepared then return end
    previewAdUIPrepared = true
    local getEnv = rawget(_G, "GetTapMakerEnvString")
    if type(getEnv) ~= "function" or getEnv() ~= "preview" then return end

    local uiOK, previewUI = pcall(require, "urhox-libs/UI/Core/UI")
    if not uiOK or type(previewUI) ~= "table" or previewUI.Inspector then return end

    local inspectorOK, inspector = pcall(require, "urhox-libs/UI/Core/UIInspector")
    if inspectorOK and type(inspector) == "table" then
        previewUI.Inspector = inspector
    else
        -- Some release runtimes strip the preview-only inspector module.  The
        -- no-op lifecycle keeps FakeAd usable without changing the game UI.
        previewUI.Inspector = {
            Init = function() end,
            Shutdown = function() end,
        }
    end
end

local function failureText(result, rewardName)
    local message = result and tostring(result.msg or "") or ""
    if message == "embed manual close" then
        return "需完整观看广告才能获得" .. tostring(rewardName or "奖励")
    elseif message == "unsupported platform" then
        return "浏览器预览不支持广告，请用 TapTap 真机扫码测试"
    elseif message ~= "" then
        return "广告暂不可用：" .. message
    end
    return "广告暂不可用，请稍后重试"
end

function Ads.WatchAdForGoldenDrill(app)
    if app.adPending then return end
    ---@diagnostic disable-next-line: undefined-global
    if not sdk or not sdk.ShowRewardVideoAd then
        app:ShowToast("当前环境不支持激励广告，请用 TapTap 真机测试", Config.Palette.red, 3)
        return
    end

    app.adPending = true
    app.mouseLeftHeld, app.mouseRightHeld = false, false
    app.mouseAimPad, app.mouseLaserHeld = false, false
    app.autoDigLocked = false
    app.touches = {}
    app:RefreshHeldInputs()
    app.drillingActive, app.overdriveActive, app.laserActive = false, false, false
    app.audio:SetDrilling(false)
    app:ShowToast("正在加载激励广告…", Config.Palette.creamDim, 4)

    preparePreviewAdUI()

    local completed, callbackFired = false, false
    local function finish(result)
        if completed then return end
        completed = true
        app.adPending = false
        if result and result.success == true then
            local added = app.state:AddGoldenDrillCharges(Config.GoldenDrill.chargesPerAd)
            app:ShowToast("获得黄金钻头 · 可挖 " .. tostring(added) .. " 次", Config.Palette.gold, 3.2)
            app:AddBurst(app.player.x, app.player.y, Config.Palette.gold, 18)
            app:AddRing(app.player.x, app.player.y, 34, Config.Palette.gold, 0.75)
            app.audio:PlaySfx(Config.Audio.pickup, 0.8, 1.08)
        else
            app:ShowToast(failureText(result, "黄金钻头"), Config.Palette.red, 3.5)
        end
    end

    local accepted = false
    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        accepted = sdk:ShowRewardVideoAd(function(result)
            callbackFired = true
            finish(result)
        end)
    end)
    if not ok then
        finish({ success = false, msg = tostring(err) })
    elseif accepted == false and not callbackFired then
        finish({ success = false, msg = "请求未受理，请稍后重试" })
    end
end


function Ads.WatchAdForSettlementDouble(app)
    if app.adPending or app.settlementAdPending or app.settlementAdClaimed then return end
    local settlement = app.lastSettlement
    local eligibleTotal = settlement and math.max(0, math.floor(tonumber(settlement.adBonusEligibleTotal) or 0)) or 0
    if eligibleTotal <= 0 then
        app:ShowToast("本局没有可翻倍的矿石", Config.Palette.creamDim, 2.5)
        return
    end
    ---@diagnostic disable-next-line: undefined-global
    if not sdk or not sdk.ShowRewardVideoAd then
        app:ShowToast("当前环境不支持激励广告，请用 TapTap 真机测试", Config.Palette.red, 3)
        return
    end

    app.adPending = true
    app.settlementAdPending = true
    app:ShowToast("正在加载激励广告…", Config.Palette.creamDim, 4)
    preparePreviewAdUI()

    local completed, callbackFired = false, false
    local function finish(result)
        if completed then return end
        completed = true
        app.adPending = false
        app.settlementAdPending = false
        if result and result.success == true then
            local added = app.state:GrantSettlementAdBonus(settlement.settledResources)
            if added > 0 then
                app.settlementAdClaimed = true
                settlement.adBonus = added
                app:ShowToast("广告完成 · 本局矿石额外 +" .. tostring(added), Config.Palette.gold, 3.5)
                app.audio:PlaySfx(Config.Audio.pickup, 0.85, 1.1)
            else
                app:ShowToast("本局没有可翻倍的矿石", Config.Palette.creamDim, 2.5)
            end
        else
            app:ShowToast(failureText(result, "双倍矿石"), Config.Palette.red, 3.5)
        end
    end

    local accepted = false
    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        accepted = sdk:ShowRewardVideoAd(function(result)
            callbackFired = true
            finish(result)
        end)
    end)
    if not ok then
        finish({ success = false, msg = tostring(err) })
    elseif accepted == false and not callbackFired then
        finish({ success = false, msg = "请求未受理，请稍后重试" })
    end
end

function Ads.WatchAdForFuelRescue(app)
    if app.adPending or app.showFuelRescue ~= true or app.fuelRescueUsed == true then return end
    if app.isAbyssRun and app.abyss and app.abyss.IsHardcore and app.abyss:IsHardcore() then
        app:ShowToast("硬核模式不提供广告救援", Config.Palette.red, 2.8)
        return
    end
    ---@diagnostic disable-next-line: undefined-global
    if not sdk or not sdk.ShowRewardVideoAd then
        app:ShowToast("当前环境不支持激励广告，请用 TapTap 真机测试", Config.Palette.red, 3)
        return
    end

    app.adPending = true
    app.fuelRescueAdPending = true
    app:ShowToast("正在呼叫广告救援…", Config.Palette.creamDim, 4)
    preparePreviewAdUI()

    local completed, callbackFired = false, false
    local function finish(result)
        if completed then return end
        completed = true
        app.adPending = false
        app.fuelRescueAdPending = false
        if result and result.success == true then
            local restored = app:ResumeFromFuelRescue()
            if restored and restored > 0 then
                app:ShowToast(string.format("救援成功 · 燃料恢复 %.1f", restored), Config.Palette.green, 3.2)
                app.audio:PlaySfx(Config.Audio.pickup, 0.85, 1.05)
            else
                app:ShowToast("本局救援资格已使用", Config.Palette.creamDim, 2.5)
            end
        else
            app:ShowToast(failureText(result, "燃料救援"), Config.Palette.red, 3.5)
        end
    end

    local accepted = false
    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        accepted = sdk:ShowRewardVideoAd(function(result)
            callbackFired = true
            finish(result)
        end)
    end)
    if not ok then
        finish({ success = false, msg = tostring(err) })
    elseif accepted == false and not callbackFired then
        finish({ success = false, msg = "请求未受理，请稍后重试" })
    end
end

function Ads.WatchAdForAbyssReroll(app)
    local abyss = app.abyss
    if app.adPending or not app.isAbyssRun or not abyss or not abyss.choice
        or (abyss.rerolls or 0) > 0 or abyss.adRerollUsed == true then return end
    if abyss.IsHardcore and abyss:IsHardcore() then
        app:ShowToast("硬核模式不提供广告刷新", Config.Palette.red, 2.8)
        return
    end
    ---@diagnostic disable-next-line: undefined-global
    if not sdk or not sdk.ShowRewardVideoAd then
        app:ShowToast("当前环境不支持激励广告，请用 TapTap 真机测试", Config.Palette.red, 3)
        return
    end

    app.adPending = true
    app.abyssRerollAdPending = true
    app:ShowToast("正在加载额外刷新…", Config.Palette.creamDim, 4)
    preparePreviewAdUI()

    local completed, callbackFired = false, false
    local function finish(result)
        if completed then return end
        completed = true
        app.adPending = false
        app.abyssRerollAdPending = false
        if result and result.success == true then
            if abyss:RerollChoice(app, true) then
                app.audio:PlaySfx(Config.Audio.click, 0.75, 1.05)
            else
                app:ShowToast("当前选项无法刷新", Config.Palette.red, 2.5)
            end
        else
            app:ShowToast(failureText(result, "额外刷新"), Config.Palette.red, 3.5)
        end
    end

    local accepted = false
    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        accepted = sdk:ShowRewardVideoAd(function(result)
            callbackFired = true
            finish(result)
        end)
    end)
    if not ok then
        finish({ success = false, msg = tostring(err) })
    elseif accepted == false and not callbackFired then
        finish({ success = false, msg = "请求未受理，请稍后重试" })
    end
end

function Ads.WatchAdForSupportStarStone(app)
    if app.adPending or app.supportAdPending then return end
    if not app.state:CanClaimSupportStarStone() then
        app:ShowToast("本账号已经领取过支持奖励", Config.Palette.creamDim, 2.5)
        return
    end
    ---@diagnostic disable-next-line: undefined-global
    if not sdk or not sdk.ShowRewardVideoAd then
        app:ShowToast("当前环境不支持激励广告，请用 TapTap 真机测试", Config.Palette.red, 3)
        return
    end

    app.adPending = true
    app.supportAdPending = true
    app:ShowToast("正在加载支持广告…", Config.Palette.creamDim, 4)
    preparePreviewAdUI()

    local completed, callbackFired = false, false
    local function finish(result)
        if completed then return end
        completed = true
        app.adPending = false
        app.supportAdPending = false
        if result and result.success == true then
            local granted = app.state:GrantSupportStarStone()
            if granted then
                app:ShowToast("感谢支持！星石 +1 · 每个账号仅限一次", Config.Palette.gold, 4)
                app.audio:PlaySfx(Config.Audio.pickup, 0.9, 1.08)
            else
                app:ShowToast("本账号已经领取过支持奖励", Config.Palette.creamDim, 2.5)
            end
        else
            app:ShowToast(failureText(result, "星石"), Config.Palette.red, 3.5)
        end
    end

    local accepted = false
    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        accepted = sdk:ShowRewardVideoAd(function(result)
            callbackFired = true
            finish(result)
        end)
    end)
    if not ok then
        finish({ success = false, msg = tostring(err) })
    elseif accepted == false and not callbackFired then
        finish({ success = false, msg = "请求未受理，请稍后重试" })
    end
end

return Ads
