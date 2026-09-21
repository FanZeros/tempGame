local Config = require("diggin.Config")
local Util = require("diggin.Util")
local WorldTree = require("diggin.WorldTree")
local AbyssItems = require("diggin.AbyssItems")
local AbyssRunTools = require("diggin.AbyssRunTools")
local AbyssLoot = require("diggin.AbyssLoot")
local AbyssDraft = require("diggin.AbyssDraft")
local AbyssTower = require("diggin.AbyssTower")
local AbyssLeaderboard = require("diggin.AbyssLeaderboard")
local AbyssPassives = require("diggin.AbyssPassives")
local AbyssInscriptions = require("diggin.AbyssInscriptions")
local AbyssDifficulty = require("diggin.AbyssDifficulty")

local AbyssMode = {}
AbyssMode.__index = AbyssMode

local function swallowBackgroundInput(app)
    if not app then return end
    app.touches = {}
    app.mouseLeftHeld, app.mouseRightHeld = false, false
    app.mouseAimPad, app.mouseLaserHeld = false, false
    app.mobileMove = 0
    -- Preserve the lock itself; the choice only pauses it. After the modal
    -- closes, an enabled lock resumes automatically and only the lock button
    -- can turn it off.
    app.leftHeld = app.autoDigLocked == true
    app.rightHeld, app.touchHeld = false, false
    app.drillingActive, app.overdriveActive, app.laserActive = false, false, false
    if app.audio and app.audio.SetDrilling then app.audio:SetDrilling(false) end
end

function AbyssMode.New()
    local self = setmetatable({}, AbyssMode)
    self:Reset()
    return self
end

function AbyssMode:Reset()
    self.active = false
    self.runMode = "endless"
    self.time = 0
    self.scoreSeconds = 0
    self.maxDepth = 0
    self.monsterY = 0
    self.currentMutation = nil
    self.mutationIndex = 0
    self.nextMutationAt = Config.Abyss.firstMutationAt
    self.projectedPoints = 0
    self.lastAwardedPoints = 0
    self.bankedPoints = 0
    self.lastCheckpointFloor = 0
    self.itemTimers = {}
    self.chronobloomTime = 0
    self.aegisCharges = 0
    self.aegisMaxCharges = 0
    self.aegisRecharge = 0
    self.previousPlayerY = nil
    self.playerDescentSpeed = 0
    self.currentSpeed = 0
    self.nextBossAttackAt = Config.Abyss.firstBossAttackAt
    self.bossAttack = nil
    self.bossAttackIndex = 0
    self.bossHits = 0
    self.lootLayers = {}
    self.tilesSinceLoot = 0
    self.lootSlotCursor = 1
    self.lootDrops = 0
    self.bestLootGrade = nil
    self.floor = 1
    self.maxFloor = 1
    self.cycle = 1
    self.route = nil
    self.choice = nil
    self.choiceSerial = 1
    self.pendingNextFloor = nil
    self.boons = {}
    self.runItems = {}
    self.runTools = {}
    self.runCapstones = {}
    self.runToolEvolutions = {}
    self.passives = {}
    self.inscriptions = {}
    self.inscriptionShopHandled = {}
    self.inscriptionShopPity = false
    self.inscriptionShopSerial = 1
    self.inscriptionShopPurchases = 0
    self.inscriptionShopRerolls = 0
    self.merchantChoice = nil
    self.merchantChoiceFloor = nil
    self.inscriptionRuntime = { fuelAt = {} }
    self.forgeProgress = 0
    self.nextForgeFloor = 4
    self.weaponChoiceSerial = 1
    self.toolChoiceSerial = 1
    self.passiveChoiceSerial = 1
    self.rerolls = AbyssPassives.START_REROLLS
    self.adRerollUsed = false
    self.lootGradeBonus = 0
    self.extractionStreak = 0
    self.boss = nil
    self.bossesDefeated = 0
    self.dodgeCooldown = 0
    self.dodgeTime = 0
    self.perfectDodges = 0
    self.jumpCooldown = 0
    self.jumpCoyoteTime = 0
    self.jumps = 0
    self.bossEvolutionTier = 0
    self.lastBossEvolutionTier = 0
    self.rootPauseTime = 0
    self.tower = self.tower or AbyssTower.New()
    self.tower:Reset()
end

function AbyssMode:Start(app, runMode)
    self:Reset()
    self.active = true
    self.runMode = runMode == "hardcore" and "hardcore" or "endless"
    app.state.abyssHardcoreActive = self:IsHardcore()
    if self:IsHardcore() then self.nextBossAttackAt = self.nextBossAttackAt * 0.72 end
    local startGap = Config.Abyss.initialGap + WorldTree.GetHeadStartDistance(app.state)
    self.monsterY = app.player.y - startGap
    self.previousPlayerY = app.player.y
    self._choiceState = app.state
    self._app = app
    self.inscriptionShopSeed = math.random(1, 2147483000)
    app.state.abyssRunBonuses = {}
    app.state.abyssCurrentFloor = 1
    AbyssItems.Start(app, self)
    self.tower:Start(app, self)
    self.choice = AbyssDraft.MakeRouteChoice(1)
    swallowBackgroundInput(app)
    app.state.abyssRouteHealthMultiplier = 1
    app.state.abyssRouteId = nil
end

function AbyssMode:GetGap(playerY)
    return (tonumber(playerY) or 0) - self.monsterY
end

function AbyssMode:GetMutation()
    return self.currentMutation
end

function AbyssMode:GetBossAttack()
    return self.bossAttack
end

function AbyssMode:GetCurrentSpeed()
    return self.currentSpeed or 0
end

function AbyssMode:GetFloor() return self.floor or 1 end
function AbyssMode:GetCycle() return math.floor((self:GetFloor() - 1) / 10) + 1 end
function AbyssMode:GetDifficultyStage() return AbyssDifficulty.GetStage(self:GetFloor()) end
function AbyssMode:GetRoute() return self.route end
function AbyssMode:AssistExitEntry(app, dt)
    return self.active and self.tower and self.tower:AssistExitEntry(app, dt) or false
end
function AbyssMode:IsChoicePending() return self.choice ~= nil end
function AbyssMode:IsBossActive() return false end
function AbyssMode:IsHardcore() return self.runMode == "hardcore" end

local BOSS_EVOLUTION_NAMES = {
    "噬岩幼体", "裂光巨口", "震地暴君", "交叉猎杀者", "双星吞噬者", "轮回深渊王",
}

function AbyssMode:GetBossEvolutionTier()
    return math.max(0, math.floor(self:GetFloor() / 10))
end

function AbyssMode:GetBossEvolutionName()
    local tier = self:GetBossEvolutionTier()
    return BOSS_EVOLUTION_NAMES[math.min(#BOSS_EVOLUTION_NAMES, tier + 1)]
end

function AbyssMode:GetRunScore()
    local tower = self.tower or {}
    local score = math.floor(math.max(0, self.scoreSeconds or 0) * 10)
        + math.max(0, math.floor(self.maxDepth or 0)) * 4
        + math.max(0, math.floor(tower.coinsEarned or 0)) * 6
        + math.max(0, math.floor(tower.kills or 0)) * 120
        + math.max(0, self:GetFloor() - 1) * 250
    if self:IsHardcore() then score = score * Config.Abyss.hardcoreScoreMultiplier end
    return math.max(0, math.floor(score))
end

local function setRouteTileHealth(app, floor, oldMultiplier, newMultiplier)
    if not app.world or not app.world.tiles then return end
    local ratio = newMultiplier / math.max(0.01, oldMultiplier)
    for _, tile in pairs(app.world.tiles) do
        if type(tile) == "table" and tile.abyssFloor == floor and not tile.indestructible then
            local healthRatio = tile.maxHealth > 0 and tile.health / tile.maxHealth or 1
            tile.maxHealth = tile.maxHealth * ratio
            tile.health = tile.maxHealth * healthRatio
        end
    end
end

function AbyssMode:BeginRouteChoice(floor)
    if self.route then
        self:AdvanceToFloor(floor)
        return false
    end
    self.pendingNextFloor = floor
    self.choice = AbyssDraft.MakeRouteChoice(floor)
    self.currentSpeed = 0
    swallowBackgroundInput(self._app)
    return true
end

function AbyssMode:AdvanceToFloor(floor)
    local oldEvolution = self:GetBossEvolutionTier()
    local oldDifficulty = AbyssDifficulty.GetStage(self:GetFloor())
    self.floor = math.max(1, math.floor(tonumber(floor) or 1))
    self.maxFloor = math.max(self.maxFloor or 1, self.floor)
    self.cycle = self:GetCycle()
    self.choice = nil
    self.pendingNextFloor = nil
    self.bossEvolutionTier = self:GetBossEvolutionTier()
    if self.bossEvolutionTier > oldEvolution and self._app and self._app.ShowToast then
        self._app:ShowToast(string.format("深渊Boss进化 · 形态%d %s · 新攻击已解锁",
            self.bossEvolutionTier + 1, self:GetBossEvolutionName()), Config.Palette.red, 3.5)
        self.nextBossAttackAt = math.min(self.nextBossAttackAt or self.time, self.time + 1.8)
    end
    self.lastBossEvolutionTier = math.max(self.lastBossEvolutionTier or 0, self.bossEvolutionTier)
    local newDifficulty = AbyssDifficulty.GetStage(self.floor)
    if newDifficulty > oldDifficulty and self._app and self._app.ShowToast then
        self._app:ShowToast(string.format("深渊难度提升 · 第%d阶 · 矿脉与怪物强化",
            newDifficulty), Config.Palette.orange, 3.2)
    end
    if self._choiceState then self._choiceState.abyssCurrentFloor = self.floor end
    if self._app and self.tower then
        self.tower:PrepareFloor(self._app, self, self.floor)
        if self.tower:IsShopFloor() then
            self.bossAttack = nil
            self.currentSpeed = 0
            self.monsterY = math.min(self.monsterY,
                (self._app.player and self._app.player.y or self.monsterY)
                    - Config.Abyss.warningGap - 32)
            self.merchantChoice, self.merchantChoiceFloor = nil, nil
        end
    end
end

function AbyssMode:BeginBoonChoice(completedFloor)
    -- Reaching the gate means the next floor has already been earned. Bank the
    -- irreversible depth/World Tree progress before opening the modal so a
    -- browser reload or client termination cannot roll a deep run back to its
    -- previous settlement.
    local reachedFloor = math.max(1, math.floor(tonumber(completedFloor) or 1) + 1)
    self.maxFloor = math.max(self.maxFloor or 1, reachedFloor)
    if self._choiceState then self:CheckpointProgress(self._choiceState, reachedFloor) end
    local build = require("diggin.AbyssBuildChoice")
    self.choice = nil
    if build.IsMilestone(completedFloor) then
        if #AbyssRunTools.GetEvolutionCandidates(self) > 0 then
            self.choice = AbyssDraft.MakeWeaponChoice(self, completedFloor)
        end
        self.choice = self.choice or build.Make(self._choiceState, self, completedFloor)
    end
    if not self.choice then
        self:AdvanceToFloor(reachedFloor)
        return
    end
    self.currentSpeed = 0
    swallowBackgroundInput(self._app)
end

function AbyssMode:RerollChoice(app, fromAd)
    if not self.choice then return false end
    if fromAd then
        if self.adRerollUsed or self:IsHardcore() then return false end
    elseif (self.rerolls or 0) <= 0 then
        return false
    end
    local kind, floor = self.choice.kind, self.choice.floor
    local replacement
    if kind == "build" then
        replacement = require("diggin.AbyssBuildChoice").Make(self._choiceState, self, floor)
    elseif kind == "tool" then
        replacement = AbyssRunTools.MakeChoice(self._choiceState, self, floor)
    elseif kind == "passive" then
        replacement = AbyssPassives.MakeChoice(self, floor)
    elseif kind == "weapon" then
        replacement = AbyssDraft.MakeWeaponChoice(self, floor)
    elseif kind == "reward" then
        replacement = AbyssPassives.MakeRewardChoice(floor)
    elseif kind == "boon" then
        replacement = AbyssDraft.MakeBoonChoice(self._choiceState, self, floor)
    else
        return false
    end
    if replacement then
        self.choice = replacement
    elseif not self:RepairChoice(app, "刷新池为空") then
        return false
    end
    if fromAd then
        self.adRerollUsed = true
    else
        self.rerolls = self.rerolls - 1
    end
    if app.ShowToast then
        local text = fromAd and "广告刷新完成 · 本局额外刷新已使用"
            or ("已刷新本次三选一 · 剩余 " .. tostring(self.rerolls) .. " 次")
        app:ShowToast(text, Config.Palette.cyan, 1.8)
    end
    return true
end

-- Live saves can keep a draft on screen while the underlying loadout changes
-- (for example after a delayed effect callback).  Never leave an option that
-- can no longer be applied on screen: replace it with three unconditional
-- supplies so the run remains recoverable.
function AbyssMode:RepairChoice(app, reason)
    local choice = self.choice
    if not choice then return false end
    local floor = math.max(1, math.floor(tonumber(choice.floor) or self:GetFloor()))
    if choice.kind == "route" then
        self.choice = AbyssDraft.MakeRouteChoice(floor)
    elseif choice.kind == "merchant_shop" then
        self.choice = AbyssInscriptions.MakeShopChoice(self, floor, AbyssRunTools.DEFINITIONS,
            Config.Abyss.merchantOfferCount, "merchant_shop")
            or { kind = "merchant_shop", floor = floor, title = "商人铭刻货架", options = {} }
        self.merchantChoice = self.choice
    elseif choice.hardcoreStarter then
        self.choice = AbyssRunTools.MakeHardcoreStarterChoice(self._choiceState, self)
            or AbyssPassives.MakeRewardChoice(floor)
    elseif choice.kind == "build" then
        self.choice = require("diggin.AbyssBuildChoice").Make(self._choiceState, self, floor)
        if not self.choice then self:AdvanceToFloor(floor + 1) end
    else
        self.choice = AbyssPassives.MakeRewardChoice(floor)
    end
    print(string.format("[AbyssChoiceRecovery] kind=%s floor=%d reason=%s",
        tostring(choice.kind), floor, tostring(reason or "unknown")))
    if app and app.ShowToast then
        app:ShowToast("选项状态已刷新 · 若仍无响应请点“保底继续”", Config.Palette.cyan, 2.8)
    end
    return true
end

-- A separate rescue action is intentionally always available on choice
-- screens.  It grants only a small fuel supply and advances normally, so a
-- bad/stale option or third-party touch issue can never end an otherwise valid
-- endless run.
function AbyssMode:ForceContinueChoice(app)
    local choice = self.choice
    if not choice then return false end
    local floor = math.max(1, math.floor(tonumber(choice.floor) or self:GetFloor()))
    if choice.kind == "route" then
        return self:HandleHudAction(app, "abyss_choice:safe")
    end
    if choice.kind == "merchant_shop" then
        self.merchantChoice = choice
        self.choice = nil
        return true
    end
    if choice.hardcoreStarter then
        for _, option in ipairs(choice.options or {}) do
            if self:HandleHudAction(app, "abyss_choice:" .. tostring(option.id)) then return true end
        end
        return self:RepairChoice(app, "starter_force_continue_failed")
    end
    -- reward_fuel has no slot, prerequisite or maximum-level gate.
    pcall(AbyssPassives.ApplyReward, app, self, "reward_fuel", floor)
    self.choice = nil
    self:AdvanceToFloor(floor + 1)
    print(string.format("[AbyssChoiceRecovery] forced_continue kind=%s floor=%d",
        tostring(choice.kind), floor))
    if app and app.ShowToast then
        app:ShowToast("已使用保底继续 · 燃料补给已发放", Config.Palette.gold, 2.2)
    end
    return true
end

function AbyssMode:OpenMerchant(app)
    if not self.tower or not self.tower:IsShopFloor() or self.choice then return false end
    -- The player already has to tap the merchant terminal itself. Requiring a
    -- second world-distance check made the visible button appear broken on
    -- wide mobile screens and after camera easing, so a valid shop-floor tap
    -- now opens the page directly.
    if self.merchantChoiceFloor ~= self.floor then
        self.inscriptionShopPurchases, self.inscriptionShopRerolls = 0, 0
        self.merchantChoice = AbyssInscriptions.MakeShopChoice(self, self.floor,
            AbyssRunTools.DEFINITIONS, Config.Abyss.merchantOfferCount, "merchant_shop")
            or { kind = "merchant_shop", floor = self.floor, title = "商人铭刻货架", options = {} }
        self.merchantChoiceFloor = self.floor
    end
    self.choice = self.merchantChoice
    self.currentSpeed = 0
    swallowBackgroundInput(app)
    return true
end

function AbyssMode:HandleHudAction(app, id)
    if id == "abyss_merchant" or id == "abyss_merchant_world" then
        return self:OpenMerchant(app)
    end
    if id == "abyss_dodge" then self:TryDodge(app); return true end
    if id == "abyss_jump" then self:TryJump(app); return true end
    if id == "abyss_reroll" then return self:RerollChoice(app) end
    if id == "abyss_reroll_ad" then app:WatchAdForAbyssReroll(); return true end
    if id == "abyss_choice_recover" then return self:ForceContinueChoice(app) end
    if id == "abyss_merchant_close" and self.choice and self.choice.kind == "merchant_shop" then
        self.merchantChoice = self.choice
        self.choice = nil
        return true
    end
    if id == "abyss_merchant_fuel" and self.choice and self.choice.kind == "merchant_shop" then
        local bought, cost, reason = self.tower:BuyMerchantFuel(app, self.floor)
        local message = bought and ("燃料补充完成 · 消耗 " .. tostring(cost) .. " 金币")
            or (reason == "full" and "燃料已满"
            or (reason == "used" and "本层已经补充过燃料"
            or ("补充燃料需要 " .. tostring(cost) .. " 金币")))
        if app.ShowToast then app:ShowToast(message, bought and Config.Palette.green or Config.Palette.red, 2) end
        return true
    end
    if id == "abyss_merchant_reroll" and self.choice and self.choice.kind == "merchant_shop" then
        local replacement, cost = AbyssInscriptions.Reroll(self, self.tower,
            self.choice.floor, AbyssRunTools.DEFINITIONS)
        if replacement then
            replacement.kind = "merchant_shop"
            self.choice = replacement
            self.merchantChoice = replacement
            if app.ShowToast then app:ShowToast("铭刻货架已刷新 · 消耗 " .. tostring(cost) .. " 金币",
                Config.Palette.cyan, 2) end
        elseif app.ShowToast then
            app:ShowToast("刷新铭刻需要 " .. tostring(cost) .. " 金币", Config.Palette.red, 2)
        end
        return true
    end
    if not id or id:sub(1, 13) ~= "abyss_choice:" or not self.choice then return false end
    local optionId = id:sub(14)
    local choice = self.choice
    if choice.kind == "merchant_shop" then
        local selectedOption
        for _, option in ipairs(choice.options or {}) do
            if option.id == optionId then selectedOption = option; break end
        end
        if not selectedOption then return self:RepairChoice(app, "missing_inscription:" .. tostring(optionId)) end
        local bought, result = AbyssInscriptions.Buy(self, self.tower, selectedOption)
        if not bought then
            local message = result == "limit" and "本层商人最多出售2枚铭刻"
                or (result == "sold" and "这件商品已经售出"
                or (type(result) == "number" and ("购买需要 " .. tostring(result) .. " 金币")
                or "该铭刻已经无法装备"))
            if app.ShowToast then app:ShowToast(message, Config.Palette.red, 2) end
            return true
        end
        if app.ShowToast then
            app:ShowToast(selectedOption.toolName .. "已刻入「" .. selectedOption.name .. "」· -"
                .. tostring(result) .. "金币", selectedOption.color, 2.6)
        end
        self.merchantChoice = self.choice
        return true
    elseif choice.kind == "route" then
        if self.route then
            self:AdvanceToFloor(choice.floor)
            return true
        end
        local route = AbyssDraft.GetRoute(optionId)
        if not route then return self:RepairChoice(app, "invalid_route:" .. tostring(optionId)) end
        local old = tonumber(app.state.abyssRouteHealthMultiplier) or 1
        self.route = route
        self.floor = choice.floor
        self.maxFloor = math.max(self.maxFloor, self.floor)
        self.cycle = self:GetCycle()
        app.state.abyssRouteHealthMultiplier = route.healthMultiplier
        app.state.abyssRouteId = route.id
        app.state.abyssCurrentFloor = self.floor
        setRouteTileHealth(app, self.floor, old, route.healthMultiplier)
        self.choice, self.pendingNextFloor = nil, nil
        if self:IsHardcore() and AbyssRunTools.GetSlotCount(self) == 0 then
            self.choice = AbyssRunTools.MakeHardcoreStarterChoice(app.state, self)
            self.currentSpeed = 0
        end
        if app.ShowToast then app:ShowToast(route.name .. " · " .. route.description, route.color, 2.4) end
        return true
    elseif choice.kind == "boon" or choice.kind == "weapon" or choice.kind == "tool"
        or choice.kind == "passive" or choice.kind == "reward" or choice.kind == "build" then
        local applied, boon
        local selectedOption
        for _, option in ipairs(choice.options or {}) do
            if option.id == optionId then selectedOption = option; break end
        end
        if not selectedOption then return self:RepairChoice(app, "missing_option:" .. tostring(optionId)) end
        local callOk
        callOk, applied, boon = pcall(function()
            if selectedOption.reward then
                return AbyssPassives.ApplyReward(app, self, optionId, choice.floor)
            elseif selectedOption.runTool then return AbyssRunTools.Apply(app, self, optionId)
            elseif selectedOption.passive then return AbyssPassives.Apply(app, self, optionId)
            elseif choice.kind == "tool" then return AbyssRunTools.Apply(app, self, optionId)
            elseif choice.kind == "weapon" then return AbyssDraft.ForgeWeapon(app, self, optionId, choice.floor)
            elseif choice.kind == "passive" then return AbyssPassives.Apply(app, self, optionId)
            elseif choice.kind == "reward" then return AbyssPassives.ApplyReward(app, self, optionId, choice.floor)
            end
            return AbyssDraft.ApplyBoon(app, self, optionId)
        end)
        if not callOk or not applied or type(boon) ~= "table" then
            return self:RepairChoice(app, not callOk and applied or ("apply_rejected:" .. tostring(optionId)))
        end
        if boon.itemId then AbyssItems.Activate(app, self, boon.itemId) end
        if choice.kind == "weapon" and boon.capstoneId then
            local evolvedNode = AbyssRunTools.GetToolForEvolution(boon.capstoneId)
            local effectByNode = {
                Boomerang = "pickarang", DrillDrones = "drill_drones",
                ShockwaveActive = "shockwave", BulletWorms = "bullet_worms",
            }
            for index = #(app.effects or {}), 1, -1 do
                if app.effects[index].effectId == effectByNode[evolvedNode] then table.remove(app.effects, index) end
            end
        end
        self.choice = nil
        local prefix = selectedOption and selectedOption.reward and "补给 · "
            or (choice.kind == "weapon" and "专武锻成 · "
            or (choice.kind == "tool" and "道具 · "
            or (choice.kind == "passive" and "被动 · "
            or (choice.kind == "reward" and "补给 · " or "深渊强化 · "))))
        if app.ShowToast then app:ShowToast(prefix .. boon.name .. " · " .. boon.description, boon.color, 2.4) end
        if choice.hardcoreStarter then return true end
        self:AdvanceToFloor(choice.floor + 1)
        return true
    end
    return false
end

function AbyssMode:TryJump(app)
    if not self.active or self.choice or (self.jumpCooldown or 0) > 0 then return false end
    if not app or not app.player
        or (app.player.onGround ~= true and (self.jumpCoyoteTime or 0) <= 0) then return false end
    app.player.vy = -Config.Abyss.jumpSpeed
    app.player.onGround = false
    self.jumpCooldown = Config.Abyss.jumpCooldown
    self.jumpCoyoteTime = 0
    self.jumps = (self.jumps or 0) + 1
    if app.AddBurst then app:AddBurst(app.player.x, app.player.y + 5, Config.Palette.cyan, 5) end
    return true
end

function AbyssMode:TryDodge(app)
    if not self.active or self.choice or self.dodgeCooldown > 0 then return false end
    local cooldownReduction = AbyssDraft.GetStat(self, "dodge_cooldown_pct")
    self.dodgeCooldown = Config.Abyss.dodgeCooldown * math.max(0.35, 1 - cooldownReduction / 100)
    self.dodgeTime = Config.Abyss.dodgeDuration
    local distance = Config.Abyss.flashDistance * (1 + AbyssDraft.GetStat(self, "dodge_distance_pct") / 100)
    local moved = self.tower:TryFlash(app, self, distance)
    local attack = self.bossAttack
    local window = Config.Abyss.perfectDodgeWindow + AbyssDraft.GetStat(self, "perfect_window")
        + AbyssLoot.GetBonus(app.state, "perfect_window")
    if attack and attack.timer <= window then
        attack.perfectDodged = true
        self.perfectDodges = self.perfectDodges + 1
        self.monsterY = self.monsterY - 24
        self.rootPauseTime = math.max(self.rootPauseTime or 0, 2.8)
        if app.AddBurst then app:AddBurst(app.player.x, app.player.y, Config.Palette.cyan, 22) end
        if app.KickCamera then app:KickCamera(3.5, 0.25) end
        if app.ShowToast then app:ShowToast("完美闪现 · 击退巨物", Config.Palette.cyan, 1.5) end
    elseif app.ShowToast then
        app:ShowToast(string.format("相位闪现 · %.0f", moved or 0), Config.Palette.cyan, 0.8)
    end
    return true
end

function AbyssMode:OnWorldItemTriggered(app, itemId, powerMultiplier)
    return false
end

function AbyssMode:OnTileDestroyed(app, tile, worldX, worldY)
    if not self.active or not self.tower then return false end
    return self.tower:OnTileDestroyed(app, self, tile, worldX, worldY)
end

function AbyssMode:CanUseTowerLaser()
    return self.active and self.tower and self.tower.laserEnergy > 0
        and (self.tower.laserCooldownRemaining or 0) <= 0
end

function AbyssMode:UpdateTowerLaser(app, dt)
    if not self.active or not self.tower then return false end
    self.tower:UpdateLaser(app, self, dt)
    return true
end

function AbyssMode:CalculateBasePoints(state)
    if self.time < Config.Abyss.minimumRewardTime then return 0 end
    -- Floor 700 used to convert its full pixel depth directly into thousands
    -- of points, enough to finish the whole tree in a single run. Both time
    -- and floor now keep growing, but with diminishing returns.
    local rawTimePoints = math.max(0, self.scoreSeconds / Config.Abyss.secondsPerPoint)
    local timePoints = math.floor(math.sqrt(rawTimePoints) * Config.Abyss.pointTimeScale)
    local depthMultiplier = state and WorldTree.GetDepthPointMultiplier(state) or 1
    local reachedFloor = math.max(1, math.floor(tonumber(self.maxFloor or self.floor) or 1))
    local floorPoints = math.floor((reachedFloor ^ Config.Abyss.pointFloorExponent)
        * Config.Abyss.pointFloorScale * depthMultiplier)
    return math.max(1, timePoints + floorPoints)
end

function AbyssMode:CalculateAward(state)
    local base = self:CalculateBasePoints(state)
    if base <= 0 then return 0 end
    local equipmentMultiplier = 1 + AbyssLoot.GetBonus(state, "point_gain_pct") / 100
    local modeMultiplier = self:IsHardcore() and Config.Abyss.hardcorePointMultiplier or 1
    return math.max(1, math.floor(base * WorldTree.GetPointMultiplier(state)
        * equipmentMultiplier * modeMultiplier + 0.0001))
end

function AbyssMode:CheckpointProgress(state, reachedFloor)
    if not self.active or not state then return false, 0 end
    reachedFloor = math.max(1, math.floor(tonumber(reachedFloor) or self.maxFloor or self.floor or 1))
    self.maxFloor = math.max(self.maxFloor or 1, reachedFloor)
    local depthChanged = state.RegisterAbyssDepth
        and state:RegisterAbyssDepth(self.runMode, self.maxFloor) or false

    local targetAward = self:CalculateAward(state)
    local alreadyBanked = math.max(0, math.floor(tonumber(self.bankedPoints) or 0))
    local delta = math.max(0, targetAward - alreadyBanked)
    self.bankedPoints = math.max(alreadyBanked, targetAward)
    self.lastCheckpointFloor = math.max(self.lastCheckpointFloor or 0, self.maxFloor)

    local granted = 0
    local cloudInterval = math.max(1, math.floor(tonumber(Config.Abyss.cloudCheckpointFloorInterval) or 15))
    local saveMode = (reachedFloor <= 2 or reachedFloor % cloudInterval == 0) and "cloud" or "local"
    if delta > 0 and state.GrantWorldTreePoints then
        granted = state:GrantWorldTreePoints(delta, saveMode)
        self.lastAwardedPoints = math.max(0, math.floor(tonumber(self.lastAwardedPoints) or 0)) + granted
    elseif depthChanged then
        if saveMode == "local" and state.SaveLocalCheckpoint then state:SaveLocalCheckpoint()
        elseif state.Save then state:Save() end
    end
    return depthChanged or granted > 0, granted
end

function AbyssMode:GetSecondsToNextPoint()
    local interval = Config.Abyss.secondsPerPoint
    local progress = self.scoreSeconds % interval
    return math.max(0, interval - progress)
end

function AbyssMode:SelectMutation(app)
    self.mutationIndex = self.mutationIndex + 1
    local offset = math.max(0, math.floor(tonumber(app.state.abyssRuns) or 0))
    local index = ((self.mutationIndex + offset - 1) % #WorldTree.MUTATIONS) + 1
    self.currentMutation = WorldTree.MUTATIONS[index]
    self.nextMutationAt = self.nextMutationAt + Config.Abyss.mutationInterval
    app:ShowToast("深渊异变 · " .. self.currentMutation.name .. " · " .. self.currentMutation.description,
        self.currentMutation.color, 3.4)
end

local function zoneContainsPlayer(zone, player)
    local playerX = tonumber(player.x) or 0
    local playerY = tonumber(player.y) or 0
    if zone.shape == "column" then
        return math.abs(playerX - zone.x) <= zone.halfWidth
    elseif zone.shape == "band" then
        return math.abs(playerY - zone.y) <= zone.halfHeight
    end
    return Util.Length(playerX - zone.x, playerY - zone.y) <= zone.radius
end

local function attackZones(attack)
    return attack.zones or { attack }
end

local function attackContainsPlayer(attack, player)
    for _, zone in ipairs(attackZones(attack)) do
        if zoneContainsPlayer(zone, player) then return true end
    end
    return false
end

function AbyssMode:StartBossAttack(app)
    self.bossAttackIndex = self.bossAttackIndex + 1
    local evolution = self:GetBossEvolutionTier()
    local patternCount = math.min(6, 1 + evolution + (self:IsHardcore() and 1 or 0))
    local pattern = ((self.bossAttackIndex + math.max(0, self.mutationIndex) - 1) % patternCount) + 1
    local telegraph = math.max(Config.Abyss.bossTelegraphMin,
        Config.Abyss.bossTelegraph - self.time * Config.Abyss.bossTelegraphRamp)
    telegraph = telegraph * math.max(0.58, 1 - evolution * 0.035)
    if self:IsHardcore() then telegraph = telegraph * 0.82 end
    local sizeScale = 1 + math.min(10, evolution) * 0.035
    local attack = {
        timer = telegraph,
        duration = telegraph,
        color = Config.Palette.red,
        evolution = evolution,
        zones = {},
    }
    local playerX = tonumber(app.player.x) or 0
    local playerY = tonumber(app.player.y) or 0
    if pattern == 1 then
        attack.id = "meteor"
        attack.name = "深渊陨击"
        attack.zones[1] = { shape = "circle",
            x = playerX + Util.Clamp((app.player.vx or 0) * 0.35, -28, 28),
            y = playerY + Util.Clamp((app.player.vy or 0) * 0.12, -8, 26),
            radius = 25 * sizeScale }
        attack.damageMultiplier = 1
    elseif pattern == 2 then
        attack.id = "column"
        attack.name = "裂隙光柱"
        attack.zones[1] = { shape = "column",
            x = playerX + ((self.bossAttackIndex % 2 == 0) and 18 or -18),
            y = playerY, halfWidth = 17 * sizeScale, radius = 31 * sizeScale }
        attack.damageMultiplier = 0.86
    elseif pattern == 3 then
        attack.id = "quake"
        attack.name = "吞地震荡"
        attack.zones[1] = { shape = "band", x = playerX, y = playerY + 24,
            halfHeight = 15 * sizeScale, radius = 34 * sizeScale }
        attack.damageMultiplier = 0.92
    elseif pattern == 4 then
        attack.id = "cross"
        attack.name = "十字猎杀"
        attack.zones = {
            { shape = "column", x = playerX, y = playerY, halfWidth = 12 * sizeScale, radius = 28 * sizeScale },
            { shape = "band", x = playerX, y = playerY, halfHeight = 11 * sizeScale, radius = 28 * sizeScale },
        }
        attack.damageMultiplier = 1.02
    elseif pattern == 5 then
        attack.id = "twins"
        attack.name = "双星夹击"
        local offset = 17 * sizeScale
        attack.zones = {
            { shape = "circle", x = playerX - offset, y = playerY, radius = 21 * sizeScale },
            { shape = "circle", x = playerX + offset, y = playerY, radius = 21 * sizeScale },
        }
        attack.damageMultiplier = 1.08
    else
        attack.id = "eclipse"
        attack.name = "轮回蚀界"
        attack.zones = {
            { shape = "column", x = playerX, y = playerY, halfWidth = 10 * sizeScale, radius = 26 * sizeScale },
            { shape = "circle", x = playerX - 28, y = playerY + 14, radius = 18 * sizeScale },
            { shape = "circle", x = playerX + 28, y = playerY - 14, radius = 18 * sizeScale },
        }
        attack.damageMultiplier = 1.16
    end
    attack.damageMultiplier = attack.damageMultiplier * (1 + evolution * 0.08)
        * (self:IsHardcore() and Config.Abyss.hardcoreBossDamageMultiplier or 1)
        * (self.route and self.route.bossDamageMultiplier or 1)
    local primary = attack.zones[1]
    attack.shape, attack.x, attack.y = primary.shape, primary.x, primary.y
    attack.radius, attack.halfWidth, attack.halfHeight = primary.radius, primary.halfWidth, primary.halfHeight
    self.bossAttack = attack
end

function AbyssMode:ResolveBossAttack(app)
    local attack = self.bossAttack
    if not attack then return false end
    local hit = not attack.perfectDodged and (self.dodgeTime or 0) <= 0 and attackContainsPlayer(attack, app.player)
    for _, zone in ipairs(attackZones(attack)) do
        local blastX = zone.shape == "column" and zone.x or (tonumber(app.player.x) or 0)
        local blastY = zone.shape == "band" and zone.y or zone.y
        if zone.shape == "circle" then blastX, blastY = zone.x, zone.y end
        if app.AddRing then app:AddRing(blastX, blastY, zone.radius or 28, Config.Palette.red, 0.65) end
        if app.AddBurst then
            app:AddBurst(blastX, blastY, Config.Palette.red, 16)
            app:AddBurst(blastX, blastY, Config.Palette.purple, 8)
        end
        if app.world and app.world.DamageArea then
            local damage = app.state:GetGeneralStat("drill_damage") * 7
            app.world:DamageArea(blastX, blastY, zone.radius or 28, damage, function(tile)
                if app.OnTileDestroyed then app:OnTileDestroyed(tile, "abyss_boss") end
            end)
        end
    end
    if app.KickCamera then app:KickCamera(hit and 6.5 or 3.2, 0.48) end
    if app.audio and app.audio.PlaySfx then
        app.audio:PlaySfx(Config.Audio.explosion, hit and 0.96 or 0.68, 0.78)
    end
    if hit then
        self.bossHits = self.bossHits + 1
        local reduction = Util.Clamp(AbyssLoot.GetBonus(app.state, "boss_damage_reduction_pct"), 0, 70)
        local maxFuel = math.max(1, tonumber(app.maxFuel) or tonumber(app.fuel) or 100)
        app.fuel = tonumber(app.fuel) or maxFuel
        local damage = maxFuel * Config.Abyss.bossFuelDamagePct / 100
            * (attack.damageMultiplier or 1) * (1 - reduction / 100)
        app.fuel = math.max(0, app.fuel - damage)
        local playerX = tonumber(app.player.x) or 0
        app.player.vx = (tonumber(app.player.vx) or 0) + ((playerX < attack.x) and -42 or 42)
        app.player.vy = math.min(tonumber(app.player.vy) or 0, -48)
        if app.ShowToast then
            app:ShowToast(string.format("%s命中 · 燃料 -%.1f", attack.name, damage), Config.Palette.red, 2.2)
        end
        if app.fuel <= 0 then
            if app.HandleFuelExhausted then app:HandleFuelExhausted("abyss_bombardment")
            else app:EndRun("abyss_bombardment") end
        end
    end
    self.bossAttack = nil
    local cooldown = math.max(Config.Abyss.bossAttackCooldownMin,
        Config.Abyss.bossAttackCooldown - self.time * Config.Abyss.bossAttackCooldownRamp)
    cooldown = cooldown * math.max(0.58, 1 - self:GetBossEvolutionTier() * 0.045)
    if self:IsHardcore() then cooldown = cooldown * Config.Abyss.hardcoreBossCooldownMultiplier end
    cooldown = cooldown * (self.route and self.route.bossCooldownMultiplier or 1)
    self.nextBossAttackAt = self.time + cooldown
    return hit
end

function AbyssMode:UpdateBossAttack(app, dt)
    if self.bossAttack then
        self.bossAttack.timer = math.max(0, self.bossAttack.timer - dt)
        if self.bossAttack.timer <= 0 then self:ResolveBossAttack(app) end
    elseif self.time >= self.nextBossAttackAt then
        self:StartBossAttack(app)
    end
end

function AbyssMode:Update(app, dt)
    if not self.active then return false end
    self.dodgeCooldown = math.max(0, (self.dodgeCooldown or 0) - dt)
    self.dodgeTime = math.max(0, (self.dodgeTime or 0) - dt)
    self.jumpCooldown = math.max(0, (self.jumpCooldown or 0) - dt)
    if app.player and app.player.onGround then
        self.jumpCoyoteTime = Config.Abyss.jumpCoyoteTime
    else
        self.jumpCoyoteTime = math.max(0, (self.jumpCoyoteTime or 0) - dt)
    end
    self.rootPauseTime = math.max(0, (self.rootPauseTime or 0) - dt)
    if self.choice then return false end
    local shopSafe = self.tower and self.tower:IsShopFloor()
    if not shopSafe then self.time = self.time + dt end
    self.maxDepth = math.max(self.maxDepth, math.max(0, math.floor(app.runDepth or 0)))
    local observedFloor = math.floor(math.max(0, app.runDepth or 0) / Config.Abyss.floorDepthTiles) + 1
    if observedFloor > self.floor then
        local completedFloor = self.floor
        local gateY = (Config.SURFACE_Y + completedFloor * Config.Abyss.floorDepthTiles) * Config.TILE_SIZE - 7
        app.player.y = math.min(app.player.y, gateY)
        app.player.vy = math.min(0, app.player.vy or 0)
        self:BeginBoonChoice(completedFloor)
        return false
    end
    if not shopSafe and self.time >= self.nextMutationAt then self:SelectMutation(app) end

    local mutation = self.currentMutation
    local route = self.route
    local scoreMultiplier = WorldTree.GetScoreMultiplier(app.state) * (route and route.pointMultiplier or 1)
    if mutation then
        scoreMultiplier = scoreMultiplier * mutation.scoreMultiplier
            * WorldTree.GetMutationRewardMultiplier(app.state)
    end
    if not shopSafe then self.scoreSeconds = self.scoreSeconds + dt * scoreMultiplier end
    self.projectedPoints = self:CalculateAward(app.state)

    if self.tower and self.tower:IsShopFloor() then
        self.currentSpeed = 0
        self.bossAttack = nil
        self.previousPlayerY = app.player.y
        self.playerDescentSpeed = 0
        self.tower:Update(app, self, dt)
        return false
    end

    local currentPlayerY = tonumber(app.player.y) or 0
    local previousPlayerY = self.previousPlayerY or currentPlayerY
    local descentSpeed = math.max(0, (currentPlayerY - previousPlayerY) / math.max(0.001, dt))
    self.previousPlayerY = currentPlayerY
    local smoothing = 1 - math.exp(-dt * 3)
    self.playerDescentSpeed = Util.Lerp(self.playerDescentSpeed or 0, descentSpeed, smoothing)

    local authoredSpeed = Config.Abyss.baseSpeed + self.time * Config.Abyss.acceleration
    local adaptiveMultiplier = math.min(Config.Abyss.adaptiveSpeedMax,
        Config.Abyss.adaptiveSpeedStart + self.time * Config.Abyss.adaptiveSpeedGrowth)
    local treeSpeedMultiplier = WorldTree.GetMonsterSpeedMultiplier(app.state)
    -- Tree slow remains useful against the authored chase curve, but cannot
    -- permanently make the chaser slower than a fully upgraded falling player.
    local runSlow = math.max(0.35, 1 - AbyssDraft.GetStat(self, "chaser_slow_pct") / 100)
    local hardcoreSpeed = self:IsHardcore() and Config.Abyss.hardcoreChaserSpeedMultiplier or 1
    local adaptiveSpeed = self.playerDescentSpeed * adaptiveMultiplier * treeSpeedMultiplier * runSlow * hardcoreSpeed
    local difficultySpeed = AbyssDifficulty.GetChaserSpeedMultiplier(self.floor)
    adaptiveSpeed = adaptiveSpeed * difficultySpeed
    local speed = authoredSpeed * (mutation and mutation.speedMultiplier or 1)
        * treeSpeedMultiplier * runSlow * difficultySpeed
        * (route and route.chaseMultiplier or 1) * hardcoreSpeed
    speed = math.min(Config.Abyss.maxSpeed, math.max(speed, adaptiveSpeed))
    if self.chronobloomTime > 0 then speed = speed * 0.55 end
    local gap = self:GetGap(app.player.y)
    if gap > Config.Abyss.catchUpGap then
        speed = speed + (gap - Config.Abyss.catchUpGap) * Config.Abyss.catchUpRate
    end
    speed = math.min(Config.Abyss.maxSpeed, speed)
    if self.rootPauseTime > 0 then speed = 0 end
    self.currentSpeed = speed
    self.monsterY = self.monsterY + speed * dt
    self.tower:Update(app, self, dt)
    if app.mode and app.mode ~= "playing" then return true end
    AbyssItems.Update(app, self, dt)
    self:UpdateBossAttack(app, dt)
    if app.mode and app.mode ~= "playing" then return true end

    if self:GetGap(app.player.y) <= Config.Abyss.catchDistance then
        if AbyssItems.TryPreventCatch(app, self) then return false end
        app:EndRun("abyss_caught")
        return true
    end
    return false
end

function AbyssMode:Finalize(state)
    if not self.active then return nil end
    self:CheckpointProgress(state, self.maxFloor or self.floor or 1)
    self.active = false
    state.abyssRuns = math.max(0, math.floor(tonumber(state.abyssRuns) or 0)) + 1
    state.bestAbyssTime = math.max(tonumber(state.bestAbyssTime) or 0, self.time)
    if state.RegisterAbyssDepth then
        state:RegisterAbyssDepth(self.runMode, self.maxFloor or self.floor or 1)
    end
    state.abyssRouteHealthMultiplier = nil
    state.abyssRouteId = nil
    state.abyssRunBonuses = nil
    state.abyssCurrentFloor = nil
    state.abyssHardcoreActive = false
    state:Save()
    local towerCoins = self.tower and self.tower.coins or 0
    local towerCoinsEarned = self.tower and self.tower.coinsEarned or towerCoins
    local towerKills = self.tower and self.tower.kills or 0
    local towerChests = self.tower and self.tower.chests or 0
    local settlement = {
        time = self.time,
        depth = self.maxDepth,
        points = self.lastAwardedPoints,
        bestTime = state.bestAbyssTime,
        mutation = self.currentMutation and self.currentMutation.id or nil,
        lootDrops = self.lootDrops or 0,
        bestLootGrade = self.bestLootGrade,
        bossHits = self.bossHits or 0,
        floor = self.maxFloor or self.floor or 1,
        mode = self.runMode,
        score = self:GetRunScore(),
        bossEvolution = self.lastBossEvolutionTier or self:GetBossEvolutionTier(),
        bossEvolutionName = self:GetBossEvolutionName(),
        bossesDefeated = self.bossesDefeated or 0,
        perfectDodges = self.perfectDodges or 0,
        jumps = self.jumps or 0,
        coins = towerCoins,
        coinsEarned = towerCoinsEarned,
        kills = towerKills,
        chests = towerChests,
        leaderboardSubmitted = false,
        leaderboardPending = false,
    }
    local leaderboardCompleted = false
    local leaderboardStarted = AbyssLeaderboard.Submit(self.runMode, settlement.floor, towerCoinsEarned,
        function(ok)
            leaderboardCompleted = true
            settlement.leaderboardPending = false
            settlement.leaderboardSubmitted = ok == true
            if ok then
                AbyssLeaderboard.FetchUserRank(self.runMode, function(rank, score)
                    settlement.leaderboardRank = rank
                    settlement.leaderboardFloor = score
                end)
            end
        end) == true
    settlement.leaderboardPending = leaderboardStarted and not leaderboardCompleted
    return settlement
end

return AbyssMode
