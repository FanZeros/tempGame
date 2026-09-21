local Config = require("diggin.Config")
local Util = require("diggin.Util")
local State = require("diggin.State")
local World = require("diggin.World")
local Renderer = require("diggin.Renderer")
local AudioManager = require("diggin.Audio")
local Controls = require("diggin.Controls")
local Ads = require("diggin.Ads")
local ProgressionController = require("diggin.ProgressionController")
local ActiveEffects = require("diggin.ActiveEffects")
local Laser = require("diggin.Laser")
local WorldTree = require("diggin.WorldTree")
local AbyssMode = require("diggin.AbyssMode")
local AbyssLoot = require("diggin.AbyssLoot")
local DropController = require("diggin.DropController")
local AbyssLeaderboardController = require("diggin.AbyssLeaderboardController")

local App = {}
App.__index = App
App.UpdateAimFromPad = Controls.UpdateAimFromPad
App.ToggleAutoDig = Controls.ToggleAutoDig
App.CancelAutoDigForMovement = Controls.CancelAutoDigForMovement
App.RefreshHeldInputs = Controls.RefreshHeldInputs
App.GetTouchAction = Controls.GetTouchAction
App.UpdateTouchLaserAim = Controls.UpdateTouchLaserAim
App.WatchAdForGoldenDrill = Ads.WatchAdForGoldenDrill
App.WatchAdForSettlementDouble = Ads.WatchAdForSettlementDouble
App.WatchAdForFuelRescue = Ads.WatchAdForFuelRescue
App.WatchAdForAbyssReroll = Ads.WatchAdForAbyssReroll
App.WatchAdForSupportStarStone = Ads.WatchAdForSupportStarStone
App.QueueOreDrop = DropController.QueueOreDrop
App.QueueArtefactDrop = DropController.QueueArtefactDrop
App.QueueRelicDrop = DropController.QueueRelicDrop
App.QueueAbyssLootDrop = DropController.QueueAbyssLootDrop
App.FinishOreDrop = DropController.FinishOreDrop
App.FinishArtefactDrop = DropController.FinishArtefactDrop
App.FinishRelicDrop = DropController.FinishRelicDrop
App.FinishAbyssLootDrop = DropController.FinishAbyssLootDrop
App.CollectAllOreDrops = DropController.CollectAllOreDrops
App.TriggerDynamiteVolley = ActiveEffects.TriggerDynamiteVolley

local function hitId(rects, x, y)
    -- World-space interactables can overlap the large mobile movement pads.
    -- Check the two merchant entry targets first so an unordered pairs()
    -- traversal can never turn a merchant tap into movement or drilling.
    for _, priorityId in ipairs({ "abyss_merchant", "abyss_merchant_world" }) do
        local rect = rects and rects[priorityId]
        if rect and rect.enabled then
            local inside = rect.circle
                and Util.Length(x - rect.cx, y - rect.cy) <= rect.radius
                or (not rect.circle and Util.PointInRect(x, y, rect))
            if inside then return priorityId end
        end
    end
    for id, rect in pairs(rects or {}) do
        local inside
        if rect.circle then
            inside = Util.Length(x - rect.cx, y - rect.cy) <= rect.radius
        else
            inside = Util.PointInRect(x, y, rect)
        end
        if id ~= "abyss_merchant" and id ~= "abyss_merchant_world"
            and rect.enabled and inside then return id end
    end
    return nil
end

local function hitAbyssChoiceId(rects, x, y)
    for id, rect in pairs(rects or {}) do
        local choiceAction = id == "abyss_choice_recover" or id == "abyss_reroll"
            or id == "abyss_reroll_ad" or id == "abyss_merchant_close"
            or id == "abyss_merchant_reroll" or id == "abyss_merchant_fuel"
            or id:sub(1, 13) == "abyss_choice:"
        if choiceAction and rect.enabled then
            local inside = rect.circle
                and Util.Length(x - rect.cx, y - rect.cy) <= rect.radius
                or (not rect.circle and Util.PointInRect(x, y, rect))
            if inside then return id end
        end
    end
    return nil
end

local function cubicOut(t)
    local inverse = 1 - t
    return 1 - inverse * inverse * inverse
end

local function cubicIn(t)
    return t * t * t
end

function App.New(vg, scene)
    local self = setmetatable({}, App)
    self.state = State.New()
    self.world = World.New(self.state)
    self.renderer = Renderer.New(vg, self.state)
    self.audio = AudioManager.New(scene, self.state)
    self.mode = "menu"; self.previousMode = "menu"
    self.showCredits = false; self.showNewGameConfirm = false; self.showEndRunConfirm = false
    self.showFuelRescue = false
    self.guidePage = 1
    self.guideReturnMode = "menu"
    self.hudCollapsed = false
    self.abyssItemsCollapsed = false
    self.pointerX = 240
    self.pointerY = 135
    self.leftHeld = false; self.rightHeld = false
    self.mouseLeftHeld = false; self.mouseRightHeld = false
    self.mouseAimPad = false; self.mouseLaserHeld = false
    self.touchHeld = false
    self.touches = {}
    self.mobileMove = 0
    self.mobileAimX, self.mobileAimY = 0, 1
    self.autoDigLocked = false
    self.draggingSkillTree = false; self.draggingWorldTree = false
    self.controlLayoutDrag = nil
    self.controlLayoutReturnMode = "menu"
    self.dragLastX = 0
    self.dragLastY = 0
    self.skillView = { x = 240, y = 135, zoom = 0.72 }
    self.worldTreeView = { x = 240, y = 135, zoom = 0.58 }
    self.selectedSkill = nil
    self.selectedWorldTreeNode = "root_damage"
    self.selectedRelic = "rusted_gear"
    self.selectedArtefact = "DynamiteAmount"
    self.selectedAbyssLootSlot = nil
    self.selectedAbyssStorageUid = nil
    self.blacksmithPage = 1
    self.weaponCodexPage = 1
    self.showBlacksmith = false
    self.showWeaponCodex = false
    self.relicTab = "standard"
    self.relicPage = 1
    self.worldTreeHover = nil
    self.effects = {}
    self.pendingOre = {}
    self.pendingArtefacts = {}
    self.pendingRelics = {}
    self.pendingAbyssLoot = 0
    self.oreDropEffectCount = 0
    self.runDensityStarsEarned = 0
    self.runFinalDensityUnlockedNow = false
    self.runRelicCoreBonus = 0
    self.lastSettlement = nil
    self.endReason = nil
    self.settlementAdPending = false
    self.settlementAdClaimed = false
    self.fuelRescueAdPending = false
    self.abyssRerollAdPending = false
    self.supportAdPending = false
    self.fuelRescueUsed = false
    self.fuelRescueReason = nil
    self.relicProcTimers = {}
    self.aftershockProcCounter = 0
    self.droneLastDitchTriggered = false
    self.activeTimers = {}
    self.economyTimers = {}
    self.factoryProduced = 0
    self.iridiumPityHintShown = false
    self.cameraKick = 0
    self.cameraKickTime = 0
    self.player = { x = Config.PLAYER_SPAWN_X, y = Config.SURFACE_Y * 16 - 7, vx = 0, vy = 0, onGround = false }
    self.aimAngle = math.pi * 0.5
    self.drillingActive = false
    self.drillTimer = 0
    self.fuel = 10
    self.maxFuel = 10
    self.fuelLossPassive = 0
    self.overdriveEnergy = 0
    self.overdriveMax = 10
    self.overdriveActive = false
    self.laserEnergy = 0
    self.laserMax = 10
    self.laserCooldownRemaining = 0
    self.laserActive = false
    self.laserHitTimer = 0
    self.laserEndX = self.player.x
    self.laserEndY = self.player.y
    self.laserBeams = {}
    self.frenzyTime = 0
    self.frenzyMultiplier = 1
    self.runDepth = 0
    self.currentLayerIndex = 1
    self.endedCommitted = false
    self.abyss = AbyssMode.New(); self.abyssLeaderboard = AbyssLeaderboardController.New()
    self.isAbyssRun = false
    self.lastRunWasAbyss = false
    self.lastAbyssMode = "endless"
    self.lastAbyssSettlement = nil
    self.densityUnlockTimer = 0
    self.newDensityUnlocked = nil
    self.toastText = nil
    self.toastTimer = 0
    self.toastColor = Config.Palette.cream
    self.adPending = false
    self.audio:PlayMusic(Config.Audio.menu)
    self:ShowProgressionRecovery()
    self.state:LoadCloud(function()
        self.audio:ApplyMute()
        self:ShowProgressionRecovery()
    end)
    return self
end

function App:StartRun(resetProgress, isAbyss, abyssMode)
    isAbyss = isAbyss == true
    abyssMode = abyssMode == "hardcore" and "hardcore" or "endless"
    if isAbyss and not self.state:CanEnterAbyss() then
        self:ShowToast(WorldTree.GetUnlockReason(self.state), Config.Palette.red, 3)
        self.audio:PlaySfx(Config.Audio.deny, 0.7)
        return false
    end
    if isAbyss and abyssMode == "hardcore" and not WorldTree.IsFullyMaxed(self.state) then
        self:ShowToast("世界树全部节点满级后才会出现硬核模式", Config.Palette.red, 3)
        self.audio:PlaySfx(Config.Audio.deny, 0.7)
        return false
    end
    if resetProgress then self.state:ResetProgress() end
    self.state.abyssRulesActive = isAbyss
    self.state.abyssHardcoreActive = isAbyss and abyssMode == "hardcore"
    if isAbyss then self.state:SetDensity(11) end
    self.showNewGameConfirm = false
    self.showEndRunConfirm = false
    self.showFuelRescue = false
    self.world:Reset()
    self.combatStats = require("diggin.RunCombatStats").New()
    self.world.combatStats = self.combatStats
    self.drillGameplay = nil
    self.showCombatReport, self.combatReportPage = false, 1
    self.state:ResetRunInventory()
    self.player = { x = Config.PLAYER_SPAWN_X, y = Config.SURFACE_Y * 16 - 7, vx = 0, vy = 0, onGround = false }
    self.maxFuel = math.max(1, self.state:GetGeneralStat("fuel_amount")
        * (isAbyss and WorldTree.GetAbyssFuelMultiplier(self.state) or 1))
    self.fuel = self.maxFuel
    self.fuelLossPassive = 0
    self.overdriveMax = math.max(1, self.state:GetActiveStat("overdrive", "overdrive_amount"))
    self.overdriveEnergy = 0
    self.overdriveActive = false
    self.laserMax = math.max(1, self.state:GetActiveStat("overheat", "laser_amount"))
    self.laserEnergy = 0
    self.laserActive = false
    self.drillingActive = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.touches = {}
    self.mobileMove = 0
    self.mobileAimX, self.mobileAimY = 0, 1
    self.autoDigLocked = false
    self.drillTimer = 0
    self.laserHitTimer = 0
    self.laserBeams = {}
    self.frenzyTime = 0
    self.frenzyMultiplier = 1
    self.effects = {}
    self.pendingOre = {}
    self.pendingArtefacts = {}
    self.pendingRelics = {}
    self.pendingAbyssLoot = 0
    self.oreDropEffectCount = 0
    self.runDensityStarsEarned = 0
    self.runFinalDensityUnlockedNow = false
    self.runRelicCoreBonus = 0
    self.lastSettlement = nil
    self.endReason = nil
    self.settlementAdPending = false
    self.settlementAdClaimed = false
    self.fuelRescueAdPending = false
    self.abyssRerollAdPending = false
    self.fuelRescueUsed = false
    self.fuelRescueReason = nil
    self.relicProcTimers = {}
    self.aftershockProcCounter = 0
    self.droneLastDitchTriggered = false
    self.activeTimers = {}
    self.economyTimers = {}
    self.factoryProduced = 0
    self.iridiumPityHintShown = false
    self.cameraKick = 0
    self.runDepth = 0
    self.currentLayerIndex = 1
    self.endedCommitted = false
    self.isAbyssRun = isAbyss
    self.abyssRunMode = isAbyss and abyssMode or nil
    self.abyssItemsCollapsed = false
    self.lastRunWasAbyss = isAbyss
    if isAbyss then self.lastAbyssMode = abyssMode end
    self.lastAbyssSettlement = nil
    if isAbyss then self.abyss:Start(self, abyssMode) else self.abyss:Reset() end
    self.densityUnlockTimer = 0
    self.newDensityUnlocked = nil
    self.mode = "playing"
    self.audio:SetDrilling(false)
    self.audio:PlayGameplayMusic(math.min(10, self.state.prestige))
    local equipped = #self.state.equippedRelics
    local activeArtefacts = self.state:GetArtefactActiveCount()
    if isAbyss then
        local name = abyssMode == "hardcore" and "硬核模式" or "无尽模式"
        self:ShowToast(name .. "开始 · 本局看得分与层数，深度榜只记录最深层",
            abyssMode == "hardcore" and Config.Palette.red or Config.Palette.cyan, 4)
    elseif equipped > 0 or activeArtefacts > 0 then
        self:ShowToast(string.format("普通遗物 %d/4 · 天赋遗物 %d 项生效", equipped, activeArtefacts), Config.Palette.gold, 3.2)
    end
    return true
end

function App:StartAbyssRun(abyssMode)
    if not self.state:CanEnterAbyss() then return self:StartRun(false, true, abyssMode) end
    require("diggin.AbyssIdentity").Open(self, abyssMode)
    return true
end

function App:OpenSkills()
    self.mode = "skills"
    self.leftHeld = false
    self.rightHeld = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.autoDigLocked = false
    self.touches = {}
    self.mobileMove = 0
    self.drillingActive = false
    self.overdriveActive = false
    self.laserActive = false
    self.audio:SetDrilling(false)
    self.audio:PlayMusic(Config.Audio.skill)
end

function App:OpenArtefact(artefactId)
    local node = self.state.nodeById[artefactId]
    if not node or not node.is_artefact then return end
    self.selectedSkill = artefactId
    local zoom = self.skillView.zoom
    self.skillView.x = Config.DESIGN_WIDTH * 0.5 - node.position[1] * zoom
    self.skillView.y = Config.DESIGN_HEIGHT * 0.5 - node.position[2] * zoom
    self:OpenSkills()
end

function App:OpenRelics(relicId)
    if relicId and self.state:GetRelic(relicId) then
        self.relicTab = "standard"
        self.selectedRelic = relicId
        local relic = self.state:GetRelic(relicId)
        self.relicPage = math.floor((relic.map - 1) / 2) + 1
    end
    self.mode = "relics"
    self.leftHeld = false
    self.rightHeld = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.autoDigLocked = false
    self.touches = {}
    self.mobileMove = 0
    self.drillingActive = false
    self.overdriveActive = false
    self.laserActive = false
    self.audio:SetDrilling(false)
    self.audio:PlayMusic(Config.Audio.skill)
end

function App:OpenMaterials()
    self.mode = "materials"
    self.leftHeld = false
    self.rightHeld = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.autoDigLocked = false
    self.touches = {}
    self.mobileMove = 0
    self.drillingActive = false
    self.overdriveActive = false
    self.laserActive = false
    self.audio:SetDrilling(false)
    self.audio:PlayMusic(Config.Audio.skill)
end

function App:OpenWorldTree()
    self.state:RefreshWorldTreeAwakening()
    self.mode = "world_tree"
    self.showBlacksmith = false
    self.showWeaponCodex = false
    self.leftHeld = false
    self.rightHeld = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.autoDigLocked = false
    self.touches = {}
    self.mobileMove = 0
    self.drillingActive = false
    self.overdriveActive = false
    self.laserActive = false
    self.audio:SetDrilling(false)
    self.audio:PlayMusic(Config.Audio.skill)
end

function App:OpenGuide(returnMode)
    if self.mode == "playing" then
        self:Pause()
        self.guideReturnMode = "paused"
    else
        self.guideReturnMode = returnMode or self.mode or "menu"
    end
    self.guidePage = Util.Clamp(math.floor(self.guidePage or 1), 1, Config.GUIDE_PAGE_COUNT)
    self.mode = "guide"
end

function App:CloseGuide()
    if self.guideReturnMode == "paused" then
        self.mode = "paused"
    else
        self.mode = "menu"
        self.audio:PlayMusic(Config.Audio.menu)
    end
end

function App:OpenMenu()
    self.mode = "menu"
    self.showCredits = false
    self.showNewGameConfirm = false
    self.showEndRunConfirm = false
    self.autoDigLocked = false
    self.leftHeld = false
    self.rightHeld = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.touches = {}
    self.mobileMove = 0
    self.audio:SetDrilling(false)
    self.audio:PlayMusic(Config.Audio.menu)
    self.state:Save()
end

function App:Shutdown()
    self.audio:SetDrilling(false)
    if self.mode == "playing" or self.mode == "paused" then
        self:EndRun("closed")
    end
    self.state:Save()
end

function App:ShowToast(text, color, duration)
    if self.state and self.state.toastEnabled == false then return false end
    self.toastText = tostring(text or "")
    self.toastColor = color or Config.Palette.cream
    self.toastTimer = duration or 2.4
    return true
end

function App:SetToastEnabled(enabled)
    self.state.toastEnabled = enabled ~= false
    self.toastText = nil
    self.toastTimer = 0
    self.state:Save()
    if self.state.toastEnabled then
        self:ShowToast("战斗提示已开启", Config.Palette.cyan, 2.2)
    end
    self.audio:PlaySfx(Config.Audio.click, 0.65)
end

function App:Pause()
    if self.mode ~= "playing" then return end
    self.previousMode = self.mode
    self.mode = "paused"
    self.showEndRunConfirm = false
    self.leftHeld = false
    self.rightHeld = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.autoDigLocked = false
    self.touches = {}
    self.mobileMove = 0
    self.drillingActive = false
    self.overdriveActive = false
    self.laserActive = false
    self.audio:SetDrilling(false)
end

function App:Resume()
    if self.mode ~= "paused" then return end
    if self.showFuelRescue then return end
    self.mode = "playing"
    self.audio:SetDrilling(self.drillingActive)
end

function App:HandleFuelExhausted(reason)
    if self.mode ~= "playing" then return false end
    local hardcore = self.isAbyssRun and self.abyss and self.abyss.IsHardcore
        and self.abyss:IsHardcore()
    if self.fuelRescueUsed or hardcore then
        self:EndRun(reason or "fuel")
        return false
    end
    self.fuel = 0
    self.fuelRescueReason = reason or "fuel"
    self:Pause()
    self.showFuelRescue = true
    self:ShowToast("燃料耗尽 · 可看广告呼叫一次救援", Config.Palette.gold, 3.2)
    return true
end

function App:ResumeFromFuelRescue()
    if self.mode ~= "paused" or self.showFuelRescue ~= true or self.fuelRescueUsed then return 0 end
    self.fuelRescueUsed = true
    self.showFuelRescue = false
    self.fuelRescueReason = nil
    self.fuel = math.max(1, self.maxFuel * 0.3)
    self.mode = "playing"
    self.previousMode = "playing"
    self:AddBurst(self.player.x, self.player.y - 8, Config.Palette.green, 16)
    self:AddRing(self.player.x, self.player.y - 8, 28, Config.Palette.green, 0.65)
    return self.fuel
end

function App:DeclineFuelRescue()
    if self.showFuelRescue ~= true then return false end
    local reason = self.fuelRescueReason or "fuel"
    self.showFuelRescue = false
    self.fuelRescueReason = nil
    self:EndRun(reason)
    return true
end

function App:EndRun(reason)
    if self.mode ~= "playing" and self.mode ~= "paused" then return end
    self.runDepth = math.max(self.runDepth, math.floor(self.player.y / 16) - Config.SURFACE_Y)
    self.mode = "ended"
    if self.combatStats then self.combatStats.frozen = true end
    self.showEndRunConfirm = false
    self.showFuelRescue = false
    self.fuelRescueReason = nil
    self.endReason = reason or (self.fuel <= 0 and "fuel" or "manual")
    self.overdriveActive = false
    self.laserActive = false
    self.leftHeld = false
    self.rightHeld = false
    self.mouseLeftHeld = false
    self.mouseRightHeld = false
    self.mouseAimPad = false
    self.mouseLaserHeld = false
    self.autoDigLocked = false
    self.touches = {}
    self.mobileMove = 0
    self.audio:SetDrilling(false)
    self:CollectAllOreDrops()
    if self.isAbyssRun then self.lastAbyssSettlement = self.abyss:Finalize(self.state) end
    if not self.endedCommitted then
        self.endedCommitted = true
        if self.isAbyssRun and self.lastAbyssSettlement then
            require("diggin.Cosmetics").GrantRunDrop(self.state, self.lastAbyssSettlement)
        end
        self.lastSettlement = self.state:CommitRunInventory({
            depth = self.runDepth,
            layer = self.currentLayerIndex,
            chestCores = self.runRelicCoreBonus,
            newDensityStars = self.runDensityStarsEarned,
            finalDensityUnlockedNow = self.runFinalDensityUnlockedNow,
        })
        if self.lastAbyssSettlement then
            self.lastSettlement.abyss = self.lastAbyssSettlement
            self.lastSettlement.worldTreePoints = self.lastAbyssSettlement.points or 0
        end
    end
    self.state.abyssRulesActive = false
end

function App:KickCamera(amount, duration)
    if self.state.screenShakeEnabled == false then return end
    self.cameraKick = math.max(self.cameraKick, amount)
    self.cameraKickTime = math.max(self.cameraKickTime, duration)
end

function App:GetCameraShake()
    if self.state.screenShakeEnabled == false then return 0, 0 end
    if self.cameraKickTime <= 0 then return 0, 0 end
    local amplitude = self.cameraKick * Util.Clamp(self.cameraKickTime / 0.35, 0, 1)
    return math.sin(self.renderer.time * 83) * amplitude, math.cos(self.renderer.time * 71) * amplitude
end

function App:AddParticle(x, y, color, speed)
    if #self.effects >= Config.MAX_TRANSIENT_EFFECTS then return end
    local angle = math.random() * math.pi * 2
    local velocity = speed or math.random(25, 75)
    self.effects[#self.effects + 1] = {
        kind = "particle", x = x, y = y,
        vx = math.cos(angle) * velocity, vy = math.sin(angle) * velocity,
        life = 0.35 + math.random() * 0.35, maxLife = 0.7,
        size = math.random(1, 3), r = color[1], g = color[2], b = color[3],
    }
end

function App:AddBurst(x, y, color, count)
    for _ = 1, count or 10 do self:AddParticle(x, y, color, 30 + math.random() * 65) end
end

function App:AddMaterialBurst(tile, count, critical)
    if not tile then return end
    local x = tile.x * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    local y = tile.y * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    local color = Config.LayerParticleColors[tile.tilemap] or Config.Palette.inkSoft
    self:AddBurst(x, y, color, count or 6)
    if critical then self:AddBurst(x, y, Config.Palette.gold, 3) end
end

function App:IsLastDitchActive()
    return self.state:IsNodeBought("LastDitchEffort") and self.maxFuel > 0 and self.fuel / self.maxFuel <= 0.05
end

function App:AddHitFlash(tile, critical)
    if not tile or tile.maxHealth == math.huge or tile.health >= tile.maxHealth then return end
    if #self.effects >= Config.MAX_TRANSIENT_EFFECTS then return end
    local remaining = Util.Clamp(tile.health / tile.maxHealth, 0, 1)
    local level = remaining >= 0.66 and 0 or (remaining >= 0.33 and 1 or 2)
    self.effects[#self.effects + 1] = {
        kind = "hit_flash",
        x = tile.x * Config.TILE_SIZE,
        y = tile.y * Config.TILE_SIZE,
        level = level,
        critical = critical,
        life = 0.1,
        maxLife = 0.1,
    }
end

function App:AwardDensityStardrop(density)
    density = math.floor(tonumber(density) or 0)
    if density < 1 or density > 10 then return false end
    local queued, finalUnlockedNow, added = self:QueueOreDrop("Stardrop", 1, self.player.x, self.player.y - 12)
    if not queued then return false end
    self.runDensityStarsEarned = self.runDensityStarsEarned + added
    self.runFinalDensityUnlockedNow = self.runFinalDensityUnlockedNow or finalUnlockedNow
    self:AddBurst(self.player.x, self.player.y - 12, Config.Palette.cyan, 18)
    self:AddBurst(self.player.x, self.player.y - 12, Config.Palette.cream, 8)
    self:KickCamera(1.25, 0.3)
    self.audio:PlaySfx(Config.Audio.stardrop, 0.9, 1.0)
    local projected = self.state:GetDensityStarCount()
    if finalUnlockedNow then
        self:ShowToast("10颗星辰齐聚 · 终极密度开启", Config.Palette.gold, 4)
    else
        self:ShowToast(string.format("首次贯穿密度 %d · 获得星辰 %d/%d", density, projected, Config.STARDROPS_FOR_FINAL_DENSITY), Config.Palette.cyan, 4)
    end
    return true
end

function App:AddRing(x, y, radius, color, duration)
    self.effects[#self.effects + 1] = {
        kind = "ring", x = x, y = y, radius = radius,
        life = duration or 0.45, maxLife = duration or 0.45,
        r = color[1], g = color[2], b = color[3],
    }
end

function App:ShowGoldenDrillProc(tier, multiplier, x, y)
    local text = tier == "jackpot" and "终极大奖 ×" .. tostring(multiplier) or "黄金钻头 ×" .. tostring(multiplier)
    self.effects[#self.effects + 1] = {
        kind = "loot_multiplier",
        x = x,
        y = y - 8,
        text = text,
        life = tier == "jackpot" and 1.8 or 0.9,
        maxLife = tier == "jackpot" and 1.8 or 0.9,
        jackpot = tier == "jackpot",
    }
    self:AddRing(x, y, tier == "jackpot" and 58 or 28, Config.Palette.gold, tier == "jackpot" and 1.1 or 0.5)
    self:AddBurst(x, y, Config.Palette.gold, tier == "jackpot" and 32 or 12)
    if tier == "jackpot" then
        self:AddBurst(x, y, Config.Palette.cyan, 18)
        self:KickCamera(2.4, 0.8)
        self:ShowToast("终极大奖！本次矿物 ×" .. tostring(multiplier), Config.Palette.gold, 4)
    end
end

function App:ShowRelicProc(relicId, text, x, y, throttle)
    if not self.state:IsRelicEquipped(relicId) then return end
    if (self.relicProcTimers[relicId] or 0) > 0 then return end
    self.relicProcTimers[relicId] = throttle or 0.65
    self.effects[#self.effects + 1] = {
        kind = "relic_proc",
        relicId = relicId,
        x = x or self.player.x,
        y = y or (self.player.y - 18),
        text = text or "遗物生效",
        life = 0.8,
        maxLife = 0.8,
    }
end

function App:CollectAugments(tile, centerX, centerY)
    local mappings = {
        { "AugmentStone", "augment_stone", "Stone" },
        { "AugmentSilver", "augment_iron", "Silver" },
        { "AugmentGold", "augment_gold", "Gold" },
        { "AugmentPlatinum", "augment_platinum", "Platinum" },
        { "AugmentIridium", "augment_iridium", "Iridium" },
    }
    for _, mapping in ipairs(mappings) do
        if self.state:IsNodeBought(mapping[1]) then
            self:QueueOreDrop(
                mapping[3],
                self.state:GetActiveStat(mapping[2], "additional_amount"),
                centerX + math.random(-3, 3),
                centerY + math.random(-3, 3)
            )
        end
    end
end

function App:OnTileDestroyed(tile, source)
    if not tile then return end
    local centerX = tile.x * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    local centerY = tile.y * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    if self.isAbyssRun and self.abyss and self.abyss.active then
        self.abyss:OnTileDestroyed(self, tile, centerX, centerY)
        self:AddMaterialBurst(tile, 13, tile.abyssExit == true)
        self:KickCamera(tile.abyssExit and 2.4 or 0.75, tile.abyssExit and 0.45 or 0.2)
        self.audio:PlaySfx(tile.abyssExit and Config.Audio.explosion or Config.Audio.breakTile,
            tile.abyssExit and 0.85 or 0.58, tile.abyssExit and 0.86 or 1.04)
        return
    end
    local multiplier = 1.0
    if tile.modifier == "bonanza" then multiplier = 5 end
    multiplier = multiplier * self.frenzyMultiplier
    if self:IsLastDitchActive() and self.state:IsNodeBought("LastDitchArtefact") then multiplier = multiplier * 2 end
    local tripleChance = self.state:GetRelicBonus("triple_drop_chance")
    local doubleChance = self.state:GetRelicBonus("double_drop_chance")
    local dropRoll = math.random() * 100
    if tripleChance > 0 and dropRoll < tripleChance then
        multiplier = multiplier * 3
        self:ShowRelicProc("star_metal_shard", "三倍掉落 ×3", centerX, centerY)
    elseif doubleChance > 0 and dropRoll < tripleChance + doubleChance then
        multiplier = multiplier * 2
        self:ShowRelicProc("lucky_nugget", "双倍掉落 ×2", centerX, centerY)
    end
    local allYield = self.state:GetRelicBonus("all_yield_pct")
    if allYield > 0 and math.random() * 100 < allYield then
        multiplier = multiplier + 1
        self:ShowRelicProc("depth_crown", "地心馈赠 +1份", centerX, centerY, 0.9)
    end
    if source == "drill" and not self.isAbyssRun then
        local goldenMultiplier, tier = self.state:RollGoldenDrillReward()
        multiplier = multiplier * (goldenMultiplier * 1.0)
        if tier then self:ShowGoldenDrillProc(tier, goldenMultiplier, centerX, centerY) end
    end
    if tile.ore ~= "Bedrock" and tile.ore ~= "StarBarrier" then
        local minedOre = ({ Ruby = "RubyUnsmelted", Emerald = "EmeraldUnsmelted", Diamond = "DiamondUnsmelted" })[tile.ore] or tile.ore
        self:QueueOreDrop(minedOre, multiplier, centerX, centerY)
        if tile.ore == "Starmetal" then
            self:QueueOreDrop(math.random() < 0.7 and "StarDebris" or "StarStone", 1, centerX + 4, centerY - 3)
            if math.random() * 100 < Config.STARMETAL_STARDROP_CHANCE then
                local queued, finalUnlockedNow, added = self:QueueOreDrop("Stardrop", 1, centerX - 4, centerY - 6)
                if queued then
                    self.runDensityStarsEarned = self.runDensityStarsEarned + added
                    self.runFinalDensityUnlockedNow = self.runFinalDensityUnlockedNow or finalUnlockedNow
                    self:AddBurst(centerX, centerY, Config.Palette.cyan, 14)
                    self.audio:PlaySfx(Config.Audio.stardrop, 0.8, 1.08)
                    self:ShowToast(finalUnlockedNow and "10颗星辰齐聚 · 终极密度开启" or "星金属共鸣 · 额外获得星辰", finalUnlockedNow and Config.Palette.gold or Config.Palette.cyan, 3)
                end
            end
        end
    end
    self:CollectAugments(tile, centerX, centerY)
    local pityIridium = self.state:RegisterIridiumPity(tile.layerIndex, tile.ore)
    if pityIridium > 0 then
        self:QueueOreDrop("Iridium", pityIridium, centerX + 3, centerY - 3)
        if not self.iridiumPityHintShown then
            self.iridiumPityHintShown = true
            self:ShowToast("伴生铱保底触发 · 密度6起每10块稳定产出", Config.Palette.cyan, 3.2)
        end
    end
    self:AddMaterialBurst(tile, 13, tile.ore == "Starmetal")
    self:KickCamera(0.75, 0.2)
    self.audio:PlaySfx(tile.ore == "Starmetal" and Config.Audio.starmetal or Config.Audio.breakTile, 0.65, 0.92 + math.random() * 0.16)

    local fuelRecovery = self.state:GetRelicBonus("fuel_recovery_flat")
    if fuelRecovery > 0 and self.fuel < self.maxFuel then
        self.fuel = math.min(self.maxFuel, self.fuel + fuelRecovery)
        self:ShowRelicProc("repair_nanites", string.format("燃料 +%.2f", fuelRecovery), centerX, centerY, 1.1)
    end

    if tile.modifier == "fuelstone" then
        self.fuel = math.min(self.maxFuel, self.fuel + self.state:GetActiveStat("fuelstone", "fuel_increase"))
    elseif tile.modifier == "feverstone" then
        self.frenzyTime = self.state:GetActiveStat("feverstone", "duration")
            * (1 + self.state:GetRelicBonus("frenzy_duration_pct") / 100)
        self.frenzyMultiplier = Config.ActiveBaseStats.feverstone.multiplier
        if self.state:GetRelicBonus("frenzy_duration_pct") > 0 then
            self:ShowRelicProc("emerald_loop", "狂热延长", centerX, centerY)
        end
    elseif tile.modifier == "chest" then
        self.effects[#self.effects + 1] = {
            kind = "chest_open", x = centerX, y = centerY,
            life = 0.75, maxLife = 0.75,
        }
        local relicId = self.state:RollMapRelic(math.min(10, self.state.prestige), self.pendingRelics)
        if relicId then
            self:QueueRelicDrop(relicId, centerX, centerY - 4)
        else
            local cores = 2 + math.floor(math.min(10, self.state.prestige) / 2)
            self.runRelicCoreBonus = self.runRelicCoreBonus + cores
            self:QueueOreDrop("Gold", 25, centerX, centerY - 4)
            self:ShowToast("本密度遗物线索已集齐 · 黄金 ×25 · 结算核心 +" .. tostring(cores), Config.Palette.gold, 3.6)
        end
        local artefactId = self.state:RollRandomArtefact(self.pendingArtefacts)
        if artefactId then self:QueueArtefactDrop(artefactId, centerX + 5, centerY - 8) end
    elseif tile.modifier == "boomstone" and source ~= "boomstone" then
        local radius = self.state:GetActiveStat("boomstone", "radius")
        local damage = self.state:GetGeneralStat("drill_damage") * self.state:GetActiveStat("boomstone", "damage") / 100
        self:AddRing(centerX, centerY, radius, Config.Palette.orange, 0.4)
        self.audio:PlaySfx(Config.Audio.explosion, 0.85)
        self.world:DamageArea(centerX, centerY, radius, damage, function(other)
            self:OnTileDestroyed(other, "boomstone")
        end)
    end

    if source == "drill" and self.state:IsNodeBought("Aftershocks") then
        local tiles = math.max(1, math.floor(self.state:GetActiveStat("aftershocks", "tiles")))
        if self.state:IsNodeBought("AftershockArtefact") then
            local every = math.max(1, math.floor(self.state:GetActiveStat("aftershocks", "crit_proc")))
            self.aftershockProcCounter = self.aftershockProcCounter + 1
            if self.aftershockProcCounter >= every then
                self.aftershockProcCounter = 0
                tiles = tiles * 3
                self.effects[#self.effects + 1] = {
                    kind = "skill_proc", node = "AftershockArtefact",
                    x = centerX, y = centerY, life = 0.65, maxLife = 0.65,
                }
                self:ShowToast("护身符生效 · 本次余震范围 ×3", Config.Palette.purple, 2.4)
            end
        end
        local damage = self.state:GetGeneralStat("drill_damage") * self.state:GetActiveStat("aftershocks", "damage") / 100
        for i = 1, tiles do
            local angle = math.random() * math.pi * 2
            local tx = tile.x + math.floor(math.cos(angle) * i)
            local ty = tile.y + math.floor(math.sin(angle) * i)
            local destroyed, other = self.world:DamageTile(self.world:GetTile(tx, ty), damage, false)
            if destroyed then self:OnTileDestroyed(other, "aftershock") end
        end
    end
end

function App:ShowProgressionRecovery()
    local grant = self.state.progressionRecoveryGrant
    if self.progressionRecoveryShown or type(grant) ~= "table" then return end
    local badges = math.floor(tonumber(grant.badges) or 0)
    local starDebris = math.floor(tonumber(grant.starDebris) or 0)
    if badges <= 0 and starDebris <= 0 then return end
    self.progressionRecoveryShown = true
    self:ShowToast(string.format("旧存档资源已接续 · 徽章 +%d · 星尘 +%d", badges, starDebris), Config.Palette.gold, 4.5)
end

function App:TriggerDrillDroneLastDitch()
    if self.droneLastDitchTriggered or not self.state:IsNodeBought("DrillDrones")
        or self.state:GetActiveStat("drill_drones", "last_ditch") <= 0 then return end
    self.droneLastDitchTriggered = true
    local count = math.max(1, math.floor(self.state:GetActiveStat("drill_drones", "amount")))
    local damage = self.state:GetGeneralStat("drill_damage")
        * self.state:GetActiveStat("drill_drones", "damage") / 100
    local radius = 28 * (1 + self.state:GetRelicBonus("explosion_radius_pct") / 100)
    for index = 1, count do
        local angle = math.pi * 2 * (index - 1) / count
        local x = self.player.x + math.cos(angle) * 24
        local y = self.player.y + math.sin(angle) * 18
        self:AddRing(x, y, radius, Config.Palette.cyan, 0.55)
        self:AddBurst(x, y, Config.Palette.cyan, 10)
        self.world:DamageArea(x, y, radius, damage, function(tile)
            self:OnTileDestroyed(tile, "drill_drone_last_ditch")
        end)
    end
    self.effects[#self.effects + 1] = {
        kind = "skill_proc", node = "DrillDroneArtefact",
        x = self.player.x, y = self.player.y - 18, life = 0.8, maxLife = 0.8,
    }
    self:KickCamera(4.5, 0.45)
    self.audio:PlaySfx(Config.Audio.explosion, 0.95, 0.9)
    self:ShowToast("帐篷地钉生效 · 无人机终焉爆炸", Config.Palette.cyan, 3)
end

function App:ConsumeFuel(amount)
    local efficiency = math.max(0.001, self.state:GetGeneralStat("fuel_efficiency"))
    self.fuel = math.max(0, self.fuel - amount / efficiency)
    if self.fuel <= 0 then
        self:TriggerDrillDroneLastDitch()
        self:HandleFuelExhausted("fuel")
    end
end

function App:StartDrilling()
    if self.drillingActive then return end
    self.drillingActive = true
    self.drillTimer = 0
    self.audio:SetDrilling(true)
end

function App:TryActivateOverdrive()
    if self.isAbyssRun then self.overdriveActive = false; return end
    if not self.state:IsNodeBought("OverdriveActive") then return end
    if self.overdriveActive or self.overdriveEnergy < self.overdriveMax * 0.1 then return end
    self.overdriveActive = true
    local layer = self.world:GetLayerNumber(math.floor(self.player.y / 16))
    self:ConsumeFuel(math.max(1, layer + layer) * 1.5)
    self.audio:PlaySfx(Config.Audio.overdrive, 0.55)
end

function App:UpdateDrill(dt)
    if not self.drillingActive then return end
    self.drillTimer = self.drillTimer - dt
    local rate = math.max(0.05, self.state:GetGeneralStat("drill_speed"))
    if self:IsLastDitchActive() then rate = rate * 2 end
    local interval = self.overdriveActive and 0.05 or (1 / rate)
    if self.drillTimer > 0 then return end
    local aimWorldX = self.pointerX - 240
    local aimWorldY = self.player.y + self.pointerY - 135
    local tile, dx, dy = self.world:GetDrillTarget(self.player, aimWorldX, aimWorldY)
    if not tile then return end
    self.drillTimer = interval
    local critical = math.random() * 100 <= self.state:GetGeneralStat("critical_chance")
    local damage = self.state:GetGeneralStat("drill_damage")
    if self.overdriveActive then
        damage = self.state:GetActiveStat("overdrive", "overdrive_strength")
            + damage * self.state:GetActiveStat("overdrive", "overdrive_drill_scaling") / 100
    else
        self:ConsumeFuel(self.world:GetFuelCost(tile, self.maxFuel))
    end
    if self.mode ~= "playing" then return end
    local instantBreak = self.state:GetRelicBonus("instant_break_chance")
    if instantBreak > 0 and math.random() * 100 < instantBreak then
        damage = math.max(damage, tile.health + 1)
        self:ShowRelicProc("void_drill", "虚空贯穿！", tile.x * 16 + 8, tile.y * 16 + 8, 0.8)
    end
    local healthBeforeDrill = tile.health
    local destroyed, hitTile = self.world:DamageTile(tile, damage, critical, "drill")
    if tile.health < healthBeforeDrill then
        require("diggin.DrillGameplay").OnHit(self, tile, dx, dy, damage, destroyed)
    end
    self:AddMaterialBurst(tile, critical and 8 or 4, critical)
    self:KickCamera(critical and 0.6 or 0.3, 0.3)
    self.audio:PlayDrillSfx(Config.Audio.hit, 0.45, 0.9 + math.random() * 0.2)
    local recoil = self.overdriveActive and 0 or 100
    self.player.vx = self.player.vx - dx * recoil
    if dy < 0.55 then self.player.vy = self.player.vy - dy * recoil end
    if self.state:IsNodeBought("Laser") then
        self.laserEnergy = math.min(self.laserMax, self.laserEnergy + self.state:GetActiveStat("overheat", "energy_per_drill_hit"))
    end
    if destroyed then
        self:OnTileDestroyed(hitTile, "drill")
    else
        self:AddHitFlash(tile, critical)
    end
    local oldCritChain = self.state:IsNodeBought("CritArtefact") and math.random() < 0.33
    local relicChain = self.state:GetRelicBonus("crit_splash_chance") > 0
        and math.random() * 100 < self.state:GetRelicBonus("crit_splash_chance")
    if critical and (oldCritChain or relicChain) then
        if relicChain then
            self:ShowRelicProc("chain_spark", "暴击连锁！", tile.x * 16 + 8, tile.y * 16 + 8)
        end
        for _, offset in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
            local adjacent = self.world:GetTile(tile.x + offset[1], tile.y + offset[2])
            local adjacentDestroyed, adjacentTile = self.world:DamageTile(adjacent, damage, false)
            if adjacentDestroyed then self:OnTileDestroyed(adjacentTile, "critical_chain") end
        end
    end
end

function App:UpdateLaser(dt)
    if self.isAbyssRun then self.abyss:UpdateTowerLaser(self, dt); return end
    Laser.Update(self, dt)
end

function App:DetonateDynamite(effect)
    self.effects[#self.effects + 1] = {
        kind = "explosion",
        x = effect.x,
        y = effect.y,
        radius = effect.radius,
        visualScale = effect.visualScale or 1,
        life = 0.42,
        maxLife = 0.42,
    }
    self:AddRing(effect.x, effect.y, effect.radius, Config.Palette.orange, 0.48)
    self:AddBurst(effect.x, effect.y, Config.Palette.orange, 14)
    self:AddBurst(effect.x, effect.y, Config.Palette.gold, 8)
    if effect.legendary then
        self:AddBurst(effect.x, effect.y, Config.Palette.purple, 16)
        self:ShowToast("传奇一击 ×4", Config.Palette.gold, 1.2)
    end
    self:KickCamera(math.min(5, 2.5 + effect.radius * 0.04), 0.35)
    self.world:DamageArea(effect.x, effect.y, effect.radius, effect.damage, function(tile)
        self:OnTileDestroyed(tile, "dynamite")
    end, "DynamiteActive")
    ActiveEffects.DamageAbyssEnemies(self, effect.x, effect.y, effect.radius, effect.damage, "DynamiteActive")
    self.audio:PlaySfx(Config.Audio.explosion, 0.85, 0.95 + math.random() * 0.1)
end

function App:UpdateEconomy(dt)
    if self.state:IsNodeBought("Collector") and self.drillingActive then
        local rate = math.max(0.25, self.state:GetActiveStat("the_collector", "production_rate"))
        self.economyTimers.collector = (self.economyTimers.collector or rate) - dt
        if self.economyTimers.collector <= 0 then
            self.economyTimers.collector = self.economyTimers.collector + rate
            local limit = math.max(1, self.state:GetActiveStat("the_collector", "production_limit"))
            local amount = math.max(1, math.floor(self.state:GetActiveStat("the_collector", "production_amount")))
            amount = math.min(amount, math.max(0, limit - self.factoryProduced))
            if amount > 0 then
                self.factoryProduced = self.factoryProduced + amount
                self.state.runInventory.FactoryOre = (self.state.runInventory.FactoryOre or 0) + amount
            end
        end
    end

    if not self.state:IsNodeBought("RubyRefinery") then return end
    local refinery = {
        { raw = "RubyUnsmelted", refined = "Ruby", enabled = true, rate = "ruby_smelting_rate", mult = "ruby_mult" },
        { raw = "EmeraldUnsmelted", refined = "Emerald", enabled = self.state:GetActiveStat("refine_ruby", "emerald_enabled") > 0, rate = "emerald_smelting_rate", mult = "emerald_mult" },
        { raw = "DiamondUnsmelted", refined = "Diamond", enabled = self.state:GetActiveStat("refine_ruby", "diamond_enabled") > 0, rate = "diamond_smelting_rate", mult = "diamond_mult" },
    }
    for _, definition in ipairs(refinery) do
        if definition.enabled then
            local rate = math.max(0.25, self.state:GetActiveStat("refine_ruby", definition.rate))
            self.economyTimers[definition.raw] = (self.economyTimers[definition.raw] or rate) - dt
            if self.economyTimers[definition.raw] <= 0 then
                self.economyTimers[definition.raw] = self.economyTimers[definition.raw] + rate
                if (self.state.runInventory[definition.raw] or 0) > 0
                    or (self.state.inventory[definition.raw] or 0) > 0 then
                    local amount = math.max(1, math.floor(self.state:GetActiveStat("refine_ruby", definition.mult)))
                    self.state:RefineBacklog(definition.raw, definition.refined, amount)
                end
            end
        end
    end
end

function App:UpdateActiveUpgrades(dt)
    ActiveEffects.UpdateActiveUpgrades(self, dt)
end

function App:UpdateEffects(dt)
    for index = #self.effects, 1, -1 do
        local effect = self.effects[index]
        local finished = false
        local collectible = effect.kind == "ore_drop" or effect.kind == "artefact_drop"
            or effect.kind == "relic_drop" or effect.kind == "abyss_loot_drop"
        if collectible then
            effect.elapsed = effect.elapsed + dt
            local t = Util.Clamp(effect.elapsed / effect.duration, 0, 1)
            if effect.phase == "pop" then
                local eased = cubicOut(t)
                effect.x = Util.Lerp(effect.startX, effect.popX, eased)
                effect.y = Util.Lerp(effect.startY, effect.popY, eased)
                if t >= 1 then
                    local screenX, screenY = self.renderer:WorldToScreen(self.player, effect.x, effect.y)
                    effect.phase = "collect"
                    effect.startScreenX = screenX
                    effect.startScreenY = screenY
                    effect.screenX = screenX
                    effect.screenY = screenY
                    effect.elapsed = 0
                    local pickupSpeed = 1 + self.state:GetRelicBonus("pickup_speed_pct") / 100
                    effect.duration = (0.2 + math.random() * 0.4) / pickupSpeed
                end
            else
                local targetX, targetY
                if effect.kind == "ore_drop" then
                    targetX, targetY = self.renderer:GetOreHudTarget(self, effect.ore)
                elseif effect.kind == "artefact_drop" then
                    targetX, targetY = self.renderer:GetArtefactHudTarget(self, effect.artefactId)
                elseif effect.kind == "abyss_loot_drop" then
                    targetX, targetY = self.renderer:GetAbyssLootHudTarget(effect.item.slot)
                else
                    targetX, targetY = self.renderer:GetRelicHudTarget(self, effect.relicId)
                end
                local eased = cubicIn(t)
                effect.screenX = Util.Lerp(effect.startScreenX, targetX, eased)
                effect.screenY = Util.Lerp(effect.startScreenY, targetY, eased)
                if t >= 1 or Util.Length(effect.screenX - targetX, effect.screenY - targetY) < 3 then
                    if effect.kind == "ore_drop" then
                        self:FinishOreDrop(effect, true)
                    elseif effect.kind == "artefact_drop" then
                        self:FinishArtefactDrop(effect, true)
                    elseif effect.kind == "abyss_loot_drop" then
                        self:FinishAbyssLootDrop(effect, true)
                    else
                        self:FinishRelicDrop(effect, true)
                    end
                    finished = true
                end
            end
        else
            effect.life = effect.life - dt
        end
        if effect.kind == "particle" then
            effect.x = effect.x + effect.vx * dt
            effect.y = effect.y + effect.vy * dt
            effect.vy = effect.vy + 120 * dt
            effect.vx = effect.vx * math.exp(-5 * dt)
        elseif effect.kind == "active_effect" then
            finished = ActiveEffects.UpdateEffect(self, effect, dt) or finished
        elseif effect.kind == "dynamite" then
            effect.x = effect.x + effect.vx * dt
            effect.y = effect.y + effect.vy * dt
            effect.vy = effect.vy + effect.gravity * dt
            effect.rotation = effect.rotation + effect.rotationSpeed * dt
            effect.sparkTimer = effect.sparkTimer - dt
            if effect.sparkTimer <= 0 then
                effect.sparkTimer = effect.sparkTimer + 0.06
                self:AddParticle(effect.x + 4, effect.y - 5, Config.Palette.gold, 16)
            end
            if effect.life <= 0 then
                self:DetonateDynamite(effect)
                finished = true
            end
        elseif effect.kind == "skill_proc" then
            effect.x = self.player.x
            effect.y = self.player.y - 18
        end
        if finished or (not collectible and effect.life <= 0) then
            table.remove(self.effects, index)
        end
    end
end

function App:UpdatePlaying(dt)
    if self.adPending then return end
    if self.isAbyssRun and self.abyss:IsChoicePending() then self.abyss:Update(self, dt); return end
    local keyboardMovement = 0
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then keyboardMovement = keyboardMovement - 1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then keyboardMovement = keyboardMovement + 1 end
    if self.autoDigLocked then self.pointerX, self.pointerY = 240 + self.player.x, 235 end
    self:UpdateTouchLaserAim()
    local aimWorldX = self.pointerX - 240
    local aimWorldY = self.player.y + self.pointerY - 135
    self.aimAngle = math.atan(aimWorldY - self.player.y, aimWorldX - self.player.x)

    local shopSafe = self.isAbyssRun and self.abyss.tower and self.abyss.tower:IsShopFloor()
    if self.leftHeld and not shopSafe and not (self.isAbyssRun and self.abyss:IsBossActive()) then
        self:StartDrilling()
        self:TryActivateOverdrive()
    else
        if self.drillingActive then
            self.drillingActive = false
            self.audio:SetDrilling(false)
        end
        self.overdriveActive = false
    end
    if not self.isAbyssRun then
        local canLaser = self.state:IsNodeBought("Laser")
        if self.rightHeld and canLaser and self.laserEnergy >= self.laserMax * 0.05 then
            self.laserActive = true
        elseif not self.rightHeld then
            self.laserActive = false
        end
    end

    if self.state:IsNodeBought("OverdriveActive") then
        self.overdriveMax = math.max(1, self.state:GetActiveStat("overdrive", "overdrive_amount"))
        if self.overdriveActive then
            local efficiency = math.max(0.001, self.state:GetActiveStat("overdrive", "overdrive_efficiency"))
            self.overdriveEnergy = math.max(0, self.overdriveEnergy - dt * 7.5 / efficiency)
            if self.overdriveEnergy <= 0 then self.overdriveActive = false end
        else
            self.overdriveEnergy = math.min(self.overdriveMax, self.overdriveEnergy + dt * self.state:GetActiveStat("overdrive", "overdrive_regeneration") / 2)
        end
    end

    local movement = Util.Clamp(keyboardMovement + self.mobileMove, -1, 1)
    if self.overdriveActive then
        local dx, dy = Util.Normalize(aimWorldX - self.player.x, aimWorldY - self.player.y)
        self.player.vx = self.player.vx + dx * 500 * dt
        self.player.vy = self.player.vy + dy * 500 * dt
        local speed = Util.Length(self.player.vx, self.player.vy)
        if speed > 100 then self.player.vx = self.player.vx / speed * 100; self.player.vy = self.player.vy / speed * 100 end
    else
        self.player.vx = movement * self.state:GetGeneralStat("movement_speed")
        if not self.player.onGround then self.player.vy = self.player.vy + 1500 * dt end
    end
    if self.isAbyssRun and self.abyss then self.abyss:AssistExitEntry(self, dt) end
    if self.isAbyssRun and self.abyss:IsBossActive() then self.player.vy = math.min(0, self.player.vy) end
    self.world:MovePlayer(self.player, dt)

    if self.drillingActive then
        self.fuelLossPassive = self.fuelLossPassive + dt / 60
        self:ConsumeFuel(dt * self.fuelLossPassive)
        if self.mode ~= "playing" then return end
        self.fuel = math.min(self.maxFuel, self.fuel + dt * self.state:GetGeneralStat("fuel_regeneration"))
    end
    self:UpdateDrill(dt)
    if self.mode ~= "playing" then return end
    self:UpdateLaser(dt)
    if not shopSafe then
        self:UpdateActiveUpgrades(dt)
        self:UpdateEconomy(dt)
    end

    if self.frenzyTime > 0 then
        self.frenzyTime = math.max(0, self.frenzyTime - dt)
        if self.frenzyTime <= 0 then self.frenzyMultiplier = 1 end
    end
    local tileY = math.floor(self.player.y / 16)
    local layerIndex = self.world:GetLayerIndex(tileY)
    self.runDepth = math.max(self.runDepth, tileY - Config.SURFACE_Y)
    local unlockedDensity, missionReward, firstLayerClaim, starDebrisReward, starStoneReward =
        self.state:RegisterLayer(layerIndex)
    if missionReward and missionReward > 0 then
        local rewardText = string.format("密度 %d · 第 %d 层任务完成 · 徽章 +%d", self.state.prestige, layerIndex, missionReward)
        if starDebrisReward and starDebrisReward > 0 then
            rewardText = rewardText .. string.format(" · 星尘 +%d", starDebrisReward)
        end
        self:ShowToast(rewardText, Config.Palette.gold, 3.2)
        self.audio:PlaySfx(Config.Audio.mission, 0.75, 1.0)
    end
    if unlockedDensity then
        self.newDensityUnlocked = unlockedDensity
        self.densityUnlockTimer = 3
    end
    if starStoneReward and starStoneReward > 0 then
        self:AddBurst(self.player.x, self.player.y - 10, Config.Palette.gold, 16)
        self.audio:PlaySfx(Config.Audio.starmetal, 0.85, 1.08)
        self:ShowToast("终极密度 · 本局首次抵达第10层 · 星石 +1", Config.Palette.gold, 4)
    end
    if layerIndex >= 10 and firstLayerClaim then self:AwardDensityStardrop(self.state.prestige) end
    if layerIndex ~= self.currentLayerIndex then
        self.currentLayerIndex = layerIndex
    end
    if self.isAbyssRun and self.abyss.active then
        self.abyss:Update(self, dt)
    end
end

function App:Update(dt)
    dt = math.min(dt, 0.05)
    self.renderer:Update(dt)
    if self.toastTimer > 0 then
        self.toastTimer = math.max(0, self.toastTimer - dt)
        if self.toastTimer <= 0 then self.toastText = nil end
    end
    if self.densityUnlockTimer > 0 then self.densityUnlockTimer = math.max(0, self.densityUnlockTimer - dt) end
    for relicId, remaining in pairs(self.relicProcTimers) do
        remaining = remaining - dt
        if remaining <= 0 then self.relicProcTimers[relicId] = nil else self.relicProcTimers[relicId] = remaining end
    end
    if self.cameraKickTime > 0 then
        self.cameraKickTime = math.max(0, self.cameraKickTime - dt)
        if self.cameraKickTime == 0 then self.cameraKick = 0 end
    end
    if self.mode == "playing" then self:UpdatePlaying(dt) end
    if self.mode == "abyss_leaderboard" and self.abyssLeaderboard.Update then
        self.abyssLeaderboard:Update(dt)
    end
    -- A Deep Abyss draft is a real pause. Long-lived capstones previously kept
    -- drilling behind the modal, pre-broke later exits on the low-health route,
    -- and made one selection cascade through many floors.
    local abyssDraftPaused = self.mode == "playing" and self.isAbyssRun
        and self.abyss and self.abyss:IsChoicePending()
    if not abyssDraftPaused then self:UpdateEffects(dt) end
    if input:GetKeyPress(KEY_ESCAPE) then
        if self.mode == "ended" and self.showCombatReport then self.showCombatReport = false
        elseif self.mode == "playing" then self:Pause()
        elseif self.mode == "paused" then
            if self.showEndRunConfirm then self.showEndRunConfirm = false else self:Resume() end
        elseif self.mode == "guide" then self:CloseGuide()
        elseif self.mode == "control_layout" then self:CloseControlLayout()
        elseif self.mode == "abyss_leaderboard" then self.abyssLeaderboard:Close(self)
        elseif self.mode == "world_tree" and self.showBlacksmith then
            self.showBlacksmith = false
        elseif self.mode == "world_tree" and self.showWeaponCodex then
            self.showWeaponCodex = false
        elseif self.mode == "skills" or self.mode == "relics" or self.mode == "materials"
            or self.mode == "world_tree" or self.mode == "season_hub" then self:OpenMenu()
        end
    end
end

function App:HandleRelicAction(id)
    return ProgressionController.HandleRelicAction(self, id)
end

function App:BuySelectedSkill()
    return ProgressionController.BuySelectedSkill(self)
end

function App:HandleWorldTreeAction(id)
    if not id then return end
    if id == "blacksmith" then
        self.showBlacksmith, self.showWeaponCodex = true, false
        self.selectedAbyssLootSlot = self.selectedAbyssLootSlot or "drill_core"
        self.selectedAbyssStorageUid = nil
        self.blacksmithPage = 1
        self.audio:PlaySfx(Config.Audio.click, 0.55)
        return
    end
    if id == "blacksmith_close" then self.showBlacksmith = false; return end
    if id:sub(1, 16) == "blacksmith_slot:" then
        self.selectedAbyssLootSlot = id:sub(17)
        self.selectedAbyssStorageUid = nil
        self.audio:PlaySfx(Config.Audio.click, 0.48)
        return
    end
    if id:sub(1, 19) == "blacksmith_storage:" then
        self.selectedAbyssStorageUid = tonumber(id:sub(20))
        local item = self.state:GetAbyssStoredItem(self.selectedAbyssStorageUid)
        if item then self.selectedAbyssLootSlot = item.slot end
        self.audio:PlaySfx(Config.Audio.click, 0.48)
        return
    end
    if id == "blacksmith_prev" then self.blacksmithPage = math.max(1, (self.blacksmithPage or 1) - 1); return end
    if id == "blacksmith_next" then self.blacksmithPage = (self.blacksmithPage or 1) + 1; return end
    if id == "blacksmith_equip" and self.selectedAbyssStorageUid then
        local ok, value = self.state:EquipAbyssStoredItem(self.selectedAbyssStorageUid)
        self.selectedAbyssStorageUid = nil
        self:ShowToast(ok and "装备已交换" or value, ok and Config.Palette.cyan or Config.Palette.red, 2)
        return
    end
    if id == "blacksmith_salvage" and self.selectedAbyssStorageUid then
        local ok, value = self.state:SalvageAbyssStoredItem(self.selectedAbyssStorageUid)
        self.selectedAbyssStorageUid = nil
        self:ShowToast(ok and ("分解完成 · 晶尘 +" .. tostring(value)) or value,
            ok and Config.Palette.gold or Config.Palette.red, 2)
        return
    end
    if id == "blacksmith_salvage_all" then
        local ok, value, count = self.state:SalvageAbyssStoredJunk("B")
        self.selectedAbyssStorageUid = nil
        self:ShowToast(ok and string.format("一键分解 %d件 · 晶尘 +%d", count, value) or value,
            ok and Config.Palette.gold or Config.Palette.red, 2.6)
        return
    end
    if id == "blacksmith_forge" and self.selectedAbyssLootSlot then
        local ok, value, level = AbyssLoot.Forge(self.state, self.selectedAbyssLootSlot)
        self:ShowToast(ok and ("锻造强化至 +" .. tostring(level) .. " · 消耗 " .. tostring(value) .. " 晶尘") or value,
            ok and Config.Palette.gold or Config.Palette.red, 2.6)
        return
    end
    if id == "blacksmith_promote" and self.selectedAbyssLootSlot then
        local ok, value, grade = AbyssLoot.Promote(self.state, self.selectedAbyssLootSlot)
        self:ShowToast(ok and ("装备升阶至 " .. tostring(grade) .. " · 消耗 " .. tostring(value) .. " 晶尘") or value,
            ok and Config.Palette.cyan or Config.Palette.red, 2.6)
        return
    end
    if id == "weapon_codex" then self.showWeaponCodex, self.showBlacksmith = true, false; self.weaponCodexPage = 1; return end
    if id == "weapon_codex_close" then self.showWeaponCodex = false; return end
    if id == "weapon_codex_prev" then self.weaponCodexPage = math.max(1, (self.weaponCodexPage or 1) - 1); return end
    if id == "weapon_codex_next" then self.weaponCodexPage = (self.weaponCodexPage or 1) + 1; return end
    if id == "world_tree_loot_reforge" and self.selectedAbyssLootSlot then
        local ok, value = AbyssLoot.Reforge(self.state, self.selectedAbyssLootSlot); self:ShowToast(ok and ("重铸完成 · 消耗 " .. value .. " 晶尘") or value, ok and Config.Palette.cyan or Config.Palette.red, 2.5); return
    end
    if id == "world_tree_loot_close" then self.selectedAbyssLootSlot = nil; return end
    if id:sub(1, 16) == "world_tree_loot:" then
        self.selectedAbyssLootSlot = id:sub(17)
        self.audio:PlaySfx(Config.Audio.click, 0.55)
        return
    end
    if id == "world_tree_back" then
        self:OpenMenu()
        return
    end
    if id == "world_tree_leaderboard" then self.abyssLeaderboard:Open(self, "world_tree"); return end
    if id == "world_tree_enter_abyss" then
        self:StartAbyssRun("endless")
        return
    end
    if id == "world_tree_enter_hardcore" then
        self:StartAbyssRun("hardcore")
        return
    end
    local nodeId
    if id == "world_tree_buy_selected" then
        nodeId = self.selectedWorldTreeNode
    elseif id:sub(1, 15) == "world_tree_buy:" then
        nodeId = id:sub(16)
    else
        return
    end
    local node = WorldTree.NODE_BY_ID[nodeId]
    local bought, cost, level = self.state:BuyWorldTreeNode(nodeId)
    if bought then
        self:ShowToast(string.format("%s提升至 Lv.%d · 消耗 %d 点", node.name, level, cost),
            Config.Palette.cyan, 3)
        self.audio:PlaySfx(Config.Audio.click, 0.75, 1.05)
    else
        self:ShowToast(self.state.worldTreeAwakened and "世界树点数不足或已满级" or "四个终极技能齐聚后世界树才会苏醒",
            Config.Palette.red, 3)
        self.audio:PlaySfx(Config.Audio.deny, 0.7)
    end
end

function App:OpenControlLayout(returnMode)
    self.controlLayoutReturnMode = returnMode == "paused" and "paused" or "menu"
    self.controlLayoutDrag = nil
    self.mode = "control_layout"
end

function App:CloseControlLayout()
    self.controlLayoutDrag = nil
    self.state:Save()
    self.mode = self.controlLayoutReturnMode == "paused" and "paused" or "menu"
end

function App:HandleMenuAction(id)
    if self.adPending then return end
    if self.showNewGameConfirm then
        if id == "new_confirm" then self:StartRun(true)
        elseif id == "new_cancel" then self.showNewGameConfirm = false end
        return
    end
    if id == "continue" then self:StartRun(false)
    elseif id == "new" then
        if self.state:HasProgress() then self.showNewGameConfirm = true else self:StartRun(true) end
    elseif id == "skills" then self:OpenSkills()
    elseif id == "relics" then self:OpenRelics()
    elseif id == "materials" then self:OpenMaterials()
    elseif id == "world_tree" then self:OpenWorldTree()
    elseif id == "season_notice" then require("diggin.SeasonHub").Open(self, "notice")
    elseif id == "wardrobe" then require("diggin.SeasonHub").Open(self, "character")
    elseif id == "guide" then self:OpenGuide("menu")
    elseif id == "controls" then self:OpenControlLayout("menu")
    elseif id == "support_author" then self:WatchAdForSupportStarStone()
    elseif id == "settings" then self.audio:ToggleMute()
    elseif id == "drill_sound" then self.audio:ToggleDrillSound()
    elseif id == "credits" then self.showCredits = true
    elseif id == "density_prev" then self.state:SetDensity(self.state.prestige - 1)
    elseif id == "density_next" then self.state:SetDensity(self.state.prestige + 1)
    end
end

function App:HandleKeyDown(key)
    if self.mode == "playing" and self.isAbyssRun then
        if key == KEY_W or key == KEY_UP then self.abyss:TryJump(self); return end
        if key == KEY_SPACE then self.abyss:TryDodge(self); return end
    end
    if key ~= KEY_RETURN and key ~= KEY_SPACE then return end
    if self.mode == "menu" then
        if self.showNewGameConfirm then
            self:HandleMenuAction("new_cancel")
        elseif self.showCredits then
            self.showCredits = false
        else
            self:HandleMenuAction(self.menuHover or "continue")
        end
    elseif self.mode == "ended" then
        if self.showCombatReport then self.showCombatReport = false; return end
        if not self.adPending then self:StartRun(false, self.lastRunWasAbyss, self.lastAbyssMode) end
    elseif self.mode == "paused" then
        if self.showFuelRescue and not self.adPending then self:DeclineFuelRescue()
        elseif self.showEndRunConfirm then self.showEndRunConfirm = false else self:Resume() end
    elseif self.mode == "guide" then
        if self.guidePage < Config.GUIDE_PAGE_COUNT then self.guidePage = self.guidePage + 1 else self:CloseGuide() end
    elseif self.mode == "skills" and self.selectedSkill then
        self:BuySelectedSkill()
    elseif self.mode == "relics" then
        self:HandleRelicAction(self.relicTab == "talent" and "talent_action" or "relic_action")
    elseif self.mode == "world_tree" and self.state:CanEnterAbyss() then
        self:StartAbyssRun()
    elseif self.mode == "control_layout" then
        self:CloseControlLayout()
    end
end

function App:HandlePointerDown(button, x, y, isTouch, touchId)
    if self.mode == "season_hub" then
        if button == MOUSEB_LEFT or isTouch then require("diggin.SeasonHub").Pointer(self, x, y) end
        return
    end
    local previousPointerX, previousPointerY = self.pointerX, self.pointerY
    self.pointerX, self.pointerY = x, y
    if self.mode == "control_layout" then
        if button ~= MOUSEB_LEFT and not isTouch then return end
        local id = hitId(self.renderer.controlLayoutButtons, x, y)
        if id == "controls_back" then
            self:CloseControlLayout()
        elseif id == "controls_reset" then
            self.state:ResetMobileControls()
            self:ShowToast("手机键位已恢复默认", Config.Palette.cyan, 2)
        elseif id and id:sub(1, 8) == "control_" then
            self.controlLayoutDrag = id:sub(9)
        end
        return
    elseif self.mode == "menu" then
        if self.showCredits then self.showCredits = false; return end
        if button == MOUSEB_LEFT or isTouch then self:HandleMenuAction(hitId(self.renderer.menuButtons, x, y)) end
    elseif self.mode == "playing" then
        if self.isAbyssRun and self.abyss:IsChoicePending() then
            -- Choice cards are a separate input layer.  The HUD is still
            -- rendered underneath, but its joystick/lock hitboxes must never
            -- win the unordered table lookup while the modal is visible.
            local choiceAction = hitAbyssChoiceId(self.renderer.hudButtons, x, y)
            if choiceAction then self.abyss:HandleHudAction(self, choiceAction) end
            return
        end
        local hudAction = hitId(self.renderer.hudButtons, x, y)
        if self.isAbyssRun and self.abyss:HandleHudAction(self, hudAction) then return
        elseif self.isAbyssRun and self.abyss:IsChoicePending() then
            -- A draft is a true modal: every pointer that was not consumed by
            -- one of its own buttons stops here instead of drilling/moving in
            -- the obscured playfield.
            return
        elseif hudAction == "toast_disable" then self:SetToastEnabled(false); return
        elseif hudAction == "abyss_items_toggle" then self.abyssItemsCollapsed = not self.abyssItemsCollapsed; return
        elseif hudAction == "pause" then self:Pause(); return
        elseif hudAction == "hud_toggle" then self.hudCollapsed = not self.hudCollapsed; return
        elseif hudAction == "help" then self:OpenGuide("paused"); return
        elseif hudAction == "reward_ad" then self:WatchAdForGoldenDrill(); return
        elseif hudAction == "auto_dig" then self:ToggleAutoDig(); return
        elseif hudAction and hudAction:sub(1, 16) == "abyss_loot_info:" then
            local slotId = hudAction:sub(17)
            local slot = AbyssLoot.GetSlot(slotId)
            local grade = AbyssLoot.GetEquippedGrade(self.state, slotId)
            local title = grade and (grade.name .. "·" .. slot.name) or (slot and slot.name or "深渊装备")
            self:ShowToast(title .. "：" .. AbyssLoot.GetSlotBonusText(self.state, slotId),
                grade and AbyssLoot.GetGradeColor(grade.id, self.renderer.time) or Config.Palette.creamDim, 4)
            return
        elseif hudAction == "aim_pad" then
            self:UpdateAimFromPad(x, y)
            if isTouch then
                self.touches[touchId or -1] = { action = "aim", x = x, y = y }
            else
                self.mouseAimPad, self.mouseLeftHeld = true, true
            end
            self:RefreshHeldInputs()
            return
        elseif hudAction == "laser" and not self.isAbyssRun and self.state:IsNodeBought("Laser") then
            self.pointerX, self.pointerY = previousPointerX, previousPointerY
            if isTouch then self.touches[touchId or -1] = { action = "laser", x = x, y = y }
            else self.mouseLaserHeld = true end
            self:RefreshHeldInputs()
            return
        elseif hudAction and hudAction:sub(1, 11) == "relic_info:" then
            local relic = self.state:GetRelic(hudAction:sub(12))
            if relic then self:ShowToast(relic.name .. "：" .. relic.description, Config.Palette.gold, 3.4) end
            return
        elseif hudAction and hudAction:sub(1, 10) == "artefact:" then
            self:OpenArtefact(hudAction:sub(11))
            return
        end
        if isTouch then
            local action = self:GetTouchAction(x, y)
            if action == "move" or action == "laser" then
                self.pointerX, self.pointerY = previousPointerX, previousPointerY
            end
            self.touches[touchId or -1] = { action = action, x = x, y = y }
            if action == "aim" then self:UpdateAimFromPad(x, y) end
            self:RefreshHeldInputs()
        elseif button == MOUSEB_RIGHT then
            self.mouseRightHeld = true
            self:RefreshHeldInputs()
        elseif button == MOUSEB_LEFT then
            self.mouseLeftHeld = true
            self:RefreshHeldInputs()
        end
    elseif self.mode == "ended" then
        local id = hitId(self.renderer.endButtons, x, y)
        if self.showCombatReport then
            if id == "report_close" then self.showCombatReport = false
            elseif id == "report_next" then self.combatReportPage = (self.combatReportPage or 1) + 1
            elseif id == "report_prev" then self.combatReportPage = math.max(1, (self.combatReportPage or 1) - 1) end
            return
        end
        if id == "combat_report" then self.showCombatReport = true
        elseif id == "settlement_double" then self:WatchAdForSettlementDouble()
        elseif id == "leaderboard" then self.abyssLeaderboard:Open(self, "ended")
        elseif id == "skills" then self:OpenSkills()
        elseif id == "relics" then self:OpenRelics()
        elseif id == "world_tree" then self:OpenWorldTree()
        elseif id == "again" then self:StartRun(false, self.lastRunWasAbyss, self.lastAbyssMode) end
    elseif self.mode == "paused" then
        local id = hitId(self.renderer.hudButtons, x, y)
        if self.showFuelRescue then
            if id == "fuel_rescue_ad" then self:WatchAdForFuelRescue()
            elseif id == "fuel_rescue_settle" then self:DeclineFuelRescue() end
        elseif self.showEndRunConfirm then
            if id == "end_cancel" then self.showEndRunConfirm = false
            elseif id == "end_confirm" then self:EndRun("manual") end
        elseif id == "resume" then self:Resume()
        elseif id == "mute" then self.audio:ToggleMute()
        elseif id == "drill_sound" then self.audio:ToggleDrillSound()
        elseif id == "toast_toggle" then self:SetToastEnabled(self.state.toastEnabled == false)
        elseif id == "shake_toggle" then
            self.state.screenShakeEnabled = self.state.screenShakeEnabled == false
            self.cameraKick, self.cameraKickTime = 0, 0
            self.state:Save()
        elseif id == "guide" then self:OpenGuide("paused")
        elseif id == "controls" then self:OpenControlLayout("paused")
        elseif id == "end_run" then self.showEndRunConfirm = true end
    elseif self.mode == "skills" then
        local id = hitId(self.renderer.hudButtons, x, y)
        if id == "play" then self:StartRun(false); return
        elseif id == "back" then self:OpenMenu(); return
        elseif id == "density_prev" then self.state:SetDensity(self.state.prestige - 1); return
        elseif id == "density_next" then self.state:SetDensity(self.state.prestige + 1); return
        elseif id == "materials" then self:OpenMaterials(); return
        elseif id == "buy_skill" and self.selectedSkill then
            self:BuySelectedSkill()
            return
        end
        local nodeId = hitId(self.renderer.skillNodeRects, x, y)
        if nodeId then
            self.selectedSkill = nodeId
            self.audio:PlaySfx(Config.Audio.click, 0.55)
        else
            self.draggingSkillTree = true
            self.dragLastX, self.dragLastY = x, y
        end
    elseif self.mode == "relics" then
        self:HandleRelicAction(hitId(self.renderer.relicButtons, x, y))
    elseif self.mode == "materials" then
        local id = hitId(self.renderer.materialButtons, x, y)
        if id == "back" then self:OpenMenu()
        elseif id == "play" then self:StartRun(false) end
    elseif self.mode == "world_tree" then
        local actionId = hitId(self.renderer.worldTreeButtons, x, y)
        if actionId then
            self:HandleWorldTreeAction(actionId)
            return
        end
        -- Blacksmith/codex are modal: blank areas must not select or drag the
        -- world tree underneath them.
        if self.showBlacksmith or self.showWeaponCodex then return end
        local nodeId = hitId(self.renderer.worldTreeNodeRects, x, y)
        if nodeId then
            self.selectedWorldTreeNode = nodeId
            self.selectedAbyssLootSlot = nil
            self.audio:PlaySfx(Config.Audio.click, 0.55)
        else
            self.draggingWorldTree = true
            self.dragLastX, self.dragLastY = x, y
        end
    elseif self.mode == "abyss_leaderboard" then
        self.abyssLeaderboard:HandleAction(self, hitId(self.renderer.leaderboardButtons, x, y))
    elseif self.mode == "guide" then
        local id = hitId(self.renderer.guideButtons, x, y)
        if id == "guide_prev" then
            self.guidePage = math.max(1, self.guidePage - 1)
        elseif id == "guide_next" then
            if self.guidePage < Config.GUIDE_PAGE_COUNT then self.guidePage = self.guidePage + 1 else self:CloseGuide() end
        end
    end
end

function App:HandlePointerUp(button, x, y, isTouch, touchId)
    if self.mode == "control_layout" then
        if self.controlLayoutDrag then self.state:Save() end
        self.controlLayoutDrag = nil
        return
    end
    if isTouch then
        local id = touchId or -1
        local touch = self.touches[id]
        if touch and touch.action == "aim" then self:UpdateAimFromPad(x, y)
        elseif touch and touch.action == "dig" then self.pointerX, self.pointerY = x, y end
        self.touches[id] = nil
    elseif button == MOUSEB_RIGHT then
        self.pointerX, self.pointerY = x, y
        self.mouseRightHeld = false
    elseif button == MOUSEB_LEFT then
        if self.mouseAimPad then self:UpdateAimFromPad(x, y)
        elseif not self.mouseLaserHeld then self.pointerX, self.pointerY = x, y end
        self.mouseLeftHeld = false
        self.mouseAimPad = false
        self.mouseLaserHeld = false
    end
    self:RefreshHeldInputs()
    if not self.isAbyssRun and not self.rightHeld then self.laserActive = false end
    if not self.leftHeld then self.overdriveActive = false end
    self.draggingSkillTree = false
    self.draggingWorldTree = false
end

function App:HandlePointerMove(x, y, touchId)
    if self.mode == "control_layout" then
        self.pointerX, self.pointerY = x, y
        if self.controlLayoutDrag then
            local changed = self.state:SetMobileControlPosition(self.controlLayoutDrag, x, y)
            if not changed and self.toastTimer <= 0 then
                self:ShowToast("键位不能互相重叠", Config.Palette.red, 1)
            end
        end
        self.controlLayoutHover = hitId(self.renderer.controlLayoutButtons, x, y)
        return
    end
    if touchId ~= nil and self.mode == "playing" then
        local touch = self.touches[touchId]
        if touch then
            touch.x, touch.y = x, y
            if touch.action == "move" then self:RefreshHeldInputs(); return end
            if touch.action == "aim" then self:UpdateAimFromPad(x, y); return end
            if touch.action == "laser" then self:UpdateTouchLaserAim(); return end
        end
    end
    if touchId == nil and self.mouseAimPad then self:UpdateAimFromPad(x, y); return end
    self.pointerX, self.pointerY = x, y
    if self.mode == "skills" and self.draggingSkillTree then
        self.skillView.x = self.skillView.x + x - self.dragLastX
        self.skillView.y = self.skillView.y + y - self.dragLastY
        self.skillView.x = Util.Clamp(self.skillView.x, -220, 700)
        self.skillView.y = Util.Clamp(self.skillView.y, -300, 570)
        self.dragLastX, self.dragLastY = x, y
    elseif self.mode == "world_tree" and self.draggingWorldTree then
        self.worldTreeView.x = self.worldTreeView.x + x - self.dragLastX
        self.worldTreeView.y = self.worldTreeView.y + y - self.dragLastY
        self.worldTreeView.x = Util.Clamp(self.worldTreeView.x, -520, 1000)
        self.worldTreeView.y = Util.Clamp(self.worldTreeView.y, -520, 800)
        self.dragLastX, self.dragLastY = x, y
    end
    self.menuHover = self.mode == "menu" and hitId(self.renderer.menuButtons, x, y) or nil
    self.endHover = self.mode == "ended" and hitId(self.renderer.endButtons, x, y) or nil
    self.skillHover = self.mode == "skills" and hitId(self.renderer.hudButtons, x, y) or nil
    self.relicHover = self.mode == "relics" and hitId(self.renderer.relicButtons, x, y) or nil
    self.materialHover = self.mode == "materials" and hitId(self.renderer.materialButtons, x, y) or nil
    self.worldTreeHover = self.mode == "world_tree" and hitId(self.renderer.worldTreeButtons, x, y) or nil
    self.leaderboardHover = self.mode == "abyss_leaderboard" and hitId(self.renderer.leaderboardButtons, x, y) or nil
    self.pauseHover = self.mode == "paused" and hitId(self.renderer.hudButtons, x, y) or nil
end

function App:HandleWheel(delta, x, y)
    if (self.mode ~= "skills" and self.mode ~= "world_tree") or delta == 0 then return end
    local view = self.mode == "skills" and self.skillView or self.worldTreeView
    local oldZoom = view.zoom
    local newZoom = Util.Clamp(oldZoom * (delta > 0 and 1.12 or 0.89), 0.42, 1.35)
    local worldX = (x - view.x) / oldZoom
    local worldY = (y - view.y) / oldZoom
    view.zoom = newZoom
    view.x = x - worldX * newZoom
    view.y = y - worldY * newZoom
end

function App:Render()
    self.renderer:Draw(self)
    if self.mode == "playing" and self.laserActive then
        local sx1, sy1 = self.renderer:WorldToScreen(self.player, self.player.x, self.player.y)
        local sx2, sy2 = self.renderer:WorldToScreen(self.player, self.laserEndX, self.laserEndY)
        nvgBeginPath(self.renderer.vg)
        nvgMoveTo(self.renderer.vg, sx1, sy1)
        nvgLineTo(self.renderer.vg, sx2, sy2)
        nvgStrokeColor(self.renderer.vg, Util.Color(self.overdriveActive and Config.Palette.cream or Config.Palette.cyan))
        nvgStrokeWidth(self.renderer.vg, self.overdriveActive and 5 or 2)
        nvgStroke(self.renderer.vg)
    end
end

return App
