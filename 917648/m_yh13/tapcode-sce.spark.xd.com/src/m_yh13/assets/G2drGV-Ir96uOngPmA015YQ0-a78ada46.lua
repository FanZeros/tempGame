local Config = require("diggin.Config")
local Util = require("diggin.Util")
local AbyssLoot = require("diggin.AbyssLoot")
local AbyssDifficulty = require("diggin.AbyssDifficulty")
local AbyssPortalSchedule = require("diggin.AbyssPortalSchedule")

local AbyssTower = {}
AbyssTower.__index = AbyssTower

AbyssTower.ENEMY_TYPES = {
    { id = "rat", name = "裂岩鼠", path = Config.Paths.abyssTowerEnemyRat, hp = 1.0, speed = 24, size = 15 },
    { id = "spider", name = "灰烬蛛", path = Config.Paths.abyssTowerEnemySpider, hp = 1.3, speed = 20, size = 16 },
    { id = "wisp", name = "辉光灵", path = Config.Paths.abyssTowerEnemyWisp, hp = 0.9, speed = 15, size = 17, ranged = true },
    { id = "centipede", name = "熔火蜈蚣", path = Config.Paths.abyssTowerEnemyCentipede, hp = 1.7, speed = 18, size = 19 },
    { id = "mimic", name = "饥饿拟态", path = Config.Paths.abyssTowerEnemyMimic, hp = 2.2, speed = 13, size = 20 },
    { id = "skull", name = "不净颅骨", path = Config.Paths.abyssTowerEnemySkull, hp = 1.5, speed = 17, size = 18, ranged = true },
}

AbyssTower.CHEST_ITEMS = {
    { id = "laser_battery", name = "辉光电池", description = "容量+25并充满，上限200；满级重复恢复20%燃料", iconIndex = 1 },
    { id = "piercing_lens", name = "贯穿透镜", description = "额外贯穿+1，上限3；满级重复恢复20%燃料", iconIndex = 2 },
    { id = "prism_laser", name = "折射棱镜", description = "伤害倍率+0.3，上限2.5；满级重复恢复20%燃料", iconIndex = 3 },
    { id = "frost_bomb", name = "冰冻炸弹", description = "冻结并清除本层现存怪物", iconIndex = 4 },
    { id = "decoy_drill", name = "诱饵钻机", description = "抵挡接下来2次怪物伤害", iconIndex = 5 },
    { id = "coin_magnet", name = "引力钱袋", description = "金币吸附范围 +36", iconIndex = 6 },
    { id = "fuel_cell", name = "燃料胶囊", description = "恢复35%燃料", iconIndex = 7 },
    { id = "phase_core", name = "闪现稳定器", description = "闪现距离 +18", iconIndex = 8 },
    { id = "exit_scanner", name = "出口扫描罗盘", description = "标记本层三格传送门横坐标", iconIndex = 9 },
}

local ITEM_BY_ID = {}
for _, item in ipairs(AbyssTower.CHEST_ITEMS) do ITEM_BY_ID[item.id] = item end

function AbyssTower.GetHordeTier(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    local first = math.max(1, math.floor(tonumber(Config.Abyss.hordeFirstFloor) or 30))
    local interval = math.max(1, math.floor(tonumber(Config.Abyss.hordeInterval) or 10))
    if floor < first or (floor - first) % interval ~= 0 then return 0 end
    return 1 + math.floor(AbyssDifficulty.GetStage(floor) / 2)
end

local function distanceToSegment(px, py, ax, ay, bx, by)
    local abx, aby = bx - ax, by - ay
    local length2 = abx * abx + aby * aby
    if length2 <= 0.0001 then return Util.Length(px - ax, py - ay), 0 end
    local t = Util.Clamp(((px - ax) * abx + (py - ay) * aby) / length2, 0, 1)
    local qx, qy = ax + abx * t, ay + aby * t
    return Util.Length(px - qx, py - qy), t
end

local function canOccupy(world, x, y)
    if not world or not world.IsSolidAtPixel then return true end
    local radius = 5
    return not world:IsSolidAtPixel(x - radius, y - radius)
        and not world:IsSolidAtPixel(x + radius, y - radius)
        and not world:IsSolidAtPixel(x - radius, y + radius)
        and not world:IsSolidAtPixel(x + radius, y + radius)
end

local function recoverSafeHorizontalPosition(world, x, y, centerX)
    if canOccupy(world, x, y) then return x end
    local awayFromExit = x <= centerX and -1 or 1
    local maxDistance = Config.TILE_SIZE * 2
    for distance = 1, maxDistance do
        local first = x + awayFromExit * distance
        if canOccupy(world, first, y) then return first end
        local second = x - awayFromExit * distance
        if canOccupy(world, second, y) then return second end
    end
    return nil
end

local function moveHorizontalSafely(world, startX, targetX, y)
    if not world or not world.IsSolidAtPixel then return targetX end
    local distance = targetX - startX
    local steps = math.max(1, math.ceil(math.abs(distance)))
    local lastSafeX = startX
    for step = 1, steps do
        local candidateX = startX + distance * step / steps
        if not canOccupy(world, candidateX, y) then break end
        lastSafeX = candidateX
    end
    return lastSafeX
end

function AbyssTower.New()
    local self = setmetatable({}, AbyssTower)
    self:Reset()
    return self
end

function AbyssTower:Reset()
    self.coins = 0
    self.coinsEarned = 0
    self.floorCoins = 0
    self.floor = 1
    self.exitX = 0
    self.exitY = Config.SURFACE_Y + Config.Abyss.floorDepthTiles - 1
    self.exitOpen = false
    self.exitRevealed = false
    self.exitPulse = 0
    self.portalFloor = false
    self.enemies = {}
    self.projectiles = {}
    self.pickups = {}
    self.bursts = {}
    self.enemySerial = 0
    self.spawnTimer = 0
    self.spawnedThisFloor = 0
    self.targetEnemyCount = 0
    self.laserMax = Config.Abyss.towerLaserMax
    self.laserEnergy = self.laserMax
    self.laserCooldownRemaining = 0
    self.laserDamageMultiplier = 1
    self.laserPierce = 0
    self.magnetRadius = Config.Abyss.coinMagnetRadius
    self.flashBonus = 0
    self.shieldCharges = 0
    self.flashFx = nil
    self.lastChestItem = nil
    self.kills = 0
    self.chests = 0
    self.deepestFloor = 1
    self.hordeActive = false
    self.hordeTier = 0
    self.hordeKills = 0
    self.hordeKillGoal = 0
    self.hordeRewardGranted = false
    self.shopFloor = false
    self.merchantX = 0
    self.merchantY = 0
    self.merchantFuelPurchased = false
end

function AbyssTower:IsShopFloorNumber(floor)
    floor = math.max(1, math.floor(tonumber(floor) or self.floor or 1))
    local interval = math.max(1, math.floor(tonumber(Config.Abyss.merchantFloorInterval) or 50))
    return floor > 1 and floor % interval == 0
end

function AbyssTower:IsShopFloor()
    return self.shopFloor == true
end

function AbyssTower:Start(app, abyss)
    self:Reset()
    app.laserMax = self.laserMax
    app.laserEnergy = self.laserEnergy
    app.laserCooldownRemaining = self.laserCooldownRemaining
    self:PrepareFloor(app, abyss, 1)
end

function AbyssTower:PrepareFloor(app, abyss, floor)
    local nextFloor = math.max(1, math.floor(tonumber(floor) or 1))
    if self.floor and nextFloor ~= self.floor then
        for _, pickup in ipairs(self.pickups or {}) do
            if pickup.kind == "coin" then
                self.coins = self.coins + pickup.amount
                self.coinsEarned = self.coinsEarned + pickup.amount
            end
        end
        self.enemies, self.projectiles, self.pickups = {}, {}, {}
    end
    if app.world and app.world.PruneAbyssFloorsBefore then
        local retained = math.max(1, math.floor(tonumber(Config.Abyss.retainedFloorHistory) or 2))
        app.world:PruneAbyssFloorsBefore(nextFloor - retained)
    end
    self.floor = nextFloor
    self.deepestFloor = math.max(self.deepestFloor or 1, self.floor)
    self.floorCoins = 0
    self.exitOpen = false
    self.exitRevealed = false
    self.exitPulse = 0
    self.portalFloor = AbyssPortalSchedule.IsPortalFloor(self.floor)
    self.simulationOnly = not (app.world and app.world.GetAbyssExitX)
    self.exitX = self.simulationOnly and 0 or app.world:GetAbyssExitX(self.floor)
    self.exitY = Config.SURFACE_Y + self.floor * Config.Abyss.floorDepthTiles - 1
    self.spawnedThisFloor = 0
    self.spawnTimer = 0.25
    self.shopFloor = self:IsShopFloorNumber(self.floor)
    self.merchantFuelPurchased = false
    local floorTopY = Config.SURFACE_Y + (self.floor - 1) * Config.Abyss.floorDepthTiles
    self.merchantX = 0
    self.merchantY = (floorTopY + Config.Abyss.floorDepthTiles - 4) * Config.TILE_SIZE - 8
    if self.shopFloor then
        self.hordeTier, self.hordeActive = 0, false
        self.hordeKills, self.hordeKillGoal, self.hordeRewardGranted = 0, 0, true
        self.targetEnemyCount = 0
        self.exitOpen, self.exitRevealed = true, true
        if app.world and app.world.OpenAbyssExitArea then
            app.world:OpenAbyssExitArea(self.floor, self.exitX, Config.Abyss.exitHalfWidthTiles)
        end
        if app.ShowToast then
            app:ShowToast("安全商店层 · 点商人或中央【打开商店】", Config.Palette.cyan, 3)
        end
        return
    end
    self.hordeTier = AbyssTower.GetHordeTier(self.floor)
    self.hordeActive = self.hordeTier > 0
    self.hordeKills = 0
    self.hordeRewardGranted = false
    self.hordeKillGoal = self.hordeActive and math.min(
        Config.Abyss.hordeMaxKillGoal,
        Config.Abyss.hordeBaseKillGoal + (self.hordeTier - 1) * Config.Abyss.hordeKillGoalPerTier) or 0
    local hordeExtra = self.hordeActive and math.min(
        Config.Abyss.hordeMaxExtraEnemies,
        Config.Abyss.hordeBaseExtraEnemies + (self.hordeTier - 1) * Config.Abyss.hordeExtraEnemiesPerTier) or 0
    self.targetEnemyCount = AbyssDifficulty.GetNormalEnemyTarget(self.floor)
        + ((abyss and abyss.IsHardcore and abyss:IsHardcore()) and Config.Abyss.hardcoreExtraEnemies or 0)
        + (abyss and abyss.route and abyss.route.enemyCountBonus or 0)
        + hordeExtra
    self.targetEnemyCount = math.min(Config.Abyss.maxActiveEnemies or 18, self.targetEnemyCount)
    if self.hordeActive and app.ShowToast then
        app:ShowToast(string.format("兽潮来袭 · 第%d阶 · 击退%d只保底装备",
            self.hordeTier, self.hordeKillGoal), Config.Palette.red, 3)
    end
end

function AbyssTower:SpawnEnemy(app, forcedType, abyss)
    local definition = forcedType
    if type(definition) ~= "table" then
        local maxIndex = math.min(#AbyssTower.ENEMY_TYPES, 2 + math.floor((self.floor - 1) / 2))
        definition = AbyssTower.ENEMY_TYPES[((self.enemySerial + self.floor * 3) % maxIndex) + 1]
    end
    self.enemySerial = self.enemySerial + 1
    local halfWidth = app.world and app.world.GetWorldHalfWidth and app.world:GetWorldHalfWidth()
        or Config.Abyss.halfWidthTiles
    local xColumn = -halfWidth + ((self.enemySerial * 3 + self.floor * 2) % (halfWidth * 2 + 1))
    local floorTopY = (Config.SURFACE_Y + (self.floor - 1) * Config.Abyss.floorDepthTiles) * Config.TILE_SIZE
    local yOffset = 28 + ((self.enemySerial * 31) % math.max(32, (Config.Abyss.floorDepthTiles - 3) * Config.TILE_SIZE))
    local baseHp = math.max(8, app.state:GetGeneralStat("drill_damage") * 5)
    local hardcore = app.state and app.state.abyssHardcoreActive == true
    local route = abyss and abyss.route or nil
    local hordeHealthMultiplier = self.hordeActive
        and (1 + self.hordeTier * Config.Abyss.hordeHealthPerTier) or 1
    local hordeSpeedMultiplier = self.hordeActive
        and (1 + self.hordeTier * Config.Abyss.hordeSpeedPerTier) or 1
    local elite = math.random() * 100 < AbyssDifficulty.GetEliteChance(self.floor)
    local eliteHealthMultiplier = elite and 1.6 or 1
    local hp = baseHp * definition.hp * AbyssDifficulty.GetEnemyHealthMultiplier(self.floor)
        * (hardcore and Config.Abyss.hardcoreEnemyHealthMultiplier or 1)
        * hordeHealthMultiplier * eliteHealthMultiplier
        * (route and route.enemyHealthMultiplier or 1)
    local enemy = {
        id = self.enemySerial, type = definition.id, name = definition.name, path = definition.path,
        x = xColumn * Config.TILE_SIZE + Config.TILE_SIZE * 0.5, y = floorTopY + yOffset,
        hp = hp, maxHp = hp, speed = definition.speed
            * AbyssDifficulty.GetChaserSpeedMultiplier(self.floor)
            * (hardcore and Config.Abyss.hardcoreEnemySpeedMultiplier or 1) * hordeSpeedMultiplier
            * (elite and 1.1 or 1)
            * (route and route.enemySpeedMultiplier or 1),
        size = definition.size, ranged = definition.ranged == true, contactCooldown = 0,
        shootTimer = definition.ranged and (1.3 + (self.enemySerial % 3) * 0.45) or 99,
        horde = self.hordeActive, elite = elite,
    }
    self.enemies[#self.enemies + 1] = enemy
    return enemy
end

function AbyssTower:QueuePickup(kind, x, y, amount)
    self.pickups[#self.pickups + 1] = {
        kind = kind, x = x, y = y, amount = amount or 1,
        vx = (math.random() - 0.5) * 35, vy = -28 - math.random() * 20, life = 12,
    }
end

function AbyssTower:AddBurst(x, y, color)
    self.bursts[#self.bursts + 1] = { x = x, y = y, color = color or Config.Palette.cyan, life = 0.48, maxLife = 0.48 }
end

function AbyssTower:ApplyChestItem(app, abyss, itemId)
    local item = ITEM_BY_ID[itemId]
    if not item then return false end
    self.lastChestItem = item
    local capped = (item.id == "laser_battery" and self.laserMax >= Config.Abyss.towerLaserCapacityCap)
        or (item.id == "prism_laser" and self.laserDamageMultiplier >= Config.Abyss.towerLaserDamageCap)
        or (item.id == "piercing_lens" and self.laserPierce >= Config.Abyss.towerLaserPierceCap)
    if capped then
        app.fuel = math.min(app.maxFuel, app.fuel + app.maxFuel * 0.20)
        if app.ShowToast then app:ShowToast(item.name .. "已满级 · 恢复20%燃料", Config.Palette.gold, 3) end
        return true
    end
    if item.id == "fuel_cell" then
        app.fuel = math.min(app.maxFuel, app.fuel + app.maxFuel * 0.35)
    elseif item.id == "prism_laser" then
        self.laserDamageMultiplier = math.min(Config.Abyss.towerLaserDamageCap, self.laserDamageMultiplier + 0.3)
    elseif item.id == "laser_battery" then
        self.laserMax = math.min(Config.Abyss.towerLaserCapacityCap, self.laserMax + 25)
        self.laserEnergy = self.laserMax
        self.laserCooldownRemaining = 0
        app.laserCooldownRemaining = 0
    elseif item.id == "piercing_lens" then
        self.laserPierce = math.min(Config.Abyss.towerLaserPierceCap, self.laserPierce + 1)
    elseif item.id == "coin_magnet" then
        self.magnetRadius = self.magnetRadius + 36
    elseif item.id == "phase_core" then
        self.flashBonus = self.flashBonus + 18
    elseif item.id == "decoy_drill" then
        self.shieldCharges = self.shieldCharges + 2
    elseif item.id == "frost_bomb" then
        for index = #self.enemies, 1, -1 do self:KillEnemy(app, abyss, index, true) end
    elseif item.id == "exit_scanner" then
        self.exitRevealed = true
    end
    if app.ShowToast then app:ShowToast("宝箱道具 · " .. item.name .. " · " .. item.description, Config.Palette.gold, 3) end
    return true
end

function AbyssTower:OpenChest(app, abyss, worldX, worldY)
    self.chests = self.chests + 1
    local index = ((self.chests * 5 + self.floor * 3 - 1) % #AbyssTower.CHEST_ITEMS) + 1
    local item = AbyssTower.CHEST_ITEMS[index]
    self:ApplyChestItem(app, abyss, item.id)
    self:QueuePickup("coin", worldX, worldY,
        math.random(Config.Abyss.chestCoinMin, Config.Abyss.chestCoinMax))
    self:AddBurst(worldX, worldY, Config.Palette.gold)
end

function AbyssTower:OpenExit(app, tile)
    if self.exitOpen then return false end
    if not tile or tile.abyssExit ~= true then return false end
    -- A delayed projectile from a retained floor must never open the current
    -- floor's gate.  Strong builds can keep several long-lived effects alive
    -- around a transition, so bind the callback to the prepared floor.
    if tile.abyssFloor and tile.abyssFloor ~= self.floor then return false end
    self.exitOpen = true
    self.exitRevealed = true
    self.exitPulse = 1.2
    -- All three portal cells are valid cores. Keep the deterministic centre
    -- instead of shifting the opening when a side cell is destroyed.
    self.exitY = Config.SURFACE_Y + self.floor * Config.Abyss.floorDepthTiles - 1
    self:QueuePickup("coin", tile.x * Config.TILE_SIZE + 8,
        tile.y * Config.TILE_SIZE + 8, Config.Abyss.floorClearCoins)
    if app.world and app.world.OpenAbyssExitArea then
        app.world:OpenAbyssExitArea(self.floor, self.exitX, Config.Abyss.exitHalfWidthTiles)
    end
    self:AddBurst(tile.x * Config.TILE_SIZE + 8, tile.y * Config.TILE_SIZE + 8, Config.Palette.cyan)
    if app.ShowToast then
        app:ShowToast("裂隙核心已破 · 通往第 " .. tostring(self.floor + 1) .. " 层的道路开启", Config.Palette.cyan, 2.4)
    end
    return true
end

-- Tile destruction and tower progression are deliberately separate systems.
-- A high-level blast can remove an exit cell before its Lua callback reaches
-- the tower (or while a floor transition is settling).  Without reconciliation
-- the physical gate is open but exitOpen remains false, which leaves the
-- player apparently stuck at the portal.  Treat the world tiles as the source
-- of truth and repair that one-way desync; OpenExit stays idempotent so rewards
-- cannot be granted twice.
function AbyssTower:ReconcileExitState(app)
    if self.exitOpen or not self.portalFloor or self.shopFloor
        or not app.world or not app.world.GetTile then return false end
    local halfWidth = math.max(1, math.floor(tonumber(Config.Abyss.exitHalfWidthTiles) or 1))
    local canonicalY = Config.SURFACE_Y + self.floor * Config.Abyss.floorDepthTiles - 1
    for x = self.exitX - halfWidth, self.exitX + halfWidth do
        if app.world:GetTile(x, canonicalY) == nil then
            return self:OpenExit(app, {
                x = self.exitX,
                y = canonicalY,
                abyssFloor = self.floor,
                abyssExit = true,
            })
        end
    end
    return false
end

function AbyssTower:AssistExitEntry(app, dt)
    if not self.exitOpen or not app.player then return false end
    local centerX = self.exitX * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    local centerY = self.exitY * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
    local laneOffset = Util.Clamp(math.floor((app.player.x - centerX) / Config.TILE_SIZE + 0.5),
        -Config.Abyss.exitHalfWidthTiles, Config.Abyss.exitHalfWidthTiles)
    local targetLaneX = centerX + laneOffset * Config.TILE_SIZE
    local dx = targetLaneX - app.player.x
    local dy = centerY - app.player.y
    if math.abs(dx) > Config.Abyss.exitAssistRadius
        or dy < -Config.Abyss.exitAssistBelow
        or dy > Config.Abyss.exitAssistAbove then return false end
    local safeX = recoverSafeHorizontalPosition(app.world, app.player.x, app.player.y, targetLaneX)
    if safeX == nil then return false end
    app.player.x = safeX
    local strength = Util.Clamp((tonumber(dt) or 0) * Config.Abyss.exitAssistStrength, 0, 0.45)
    local targetX = Util.Lerp(app.player.x, targetLaneX, strength)
    app.player.x = moveHorizontalSafely(app.world, app.player.x, targetX, app.player.y)
    app.player.vx = (app.player.vx or 0) * Config.Abyss.exitAssistHorizontalDamping
    if (app.player.vy or 0) > 0 then
        app.player.vy = app.player.vy * Config.Abyss.exitAssistVerticalDamping
    end
    return true
end

function AbyssTower:OnTileDestroyed(app, abyss, tile, worldX, worldY)
    if tile.abyssExit then
        self:OpenExit(app, tile)
    else
        local amount = tile.modifier == "bonanza" and math.random(2, 3) or Config.Abyss.coinsPerTile
        if tile.modifier == "bonanza" or math.random() * 100 < Config.Abyss.coinTileDropChance then
            self:QueuePickup("coin", worldX, worldY, amount)
        end
        if tile.modifier == "chest" then
            self:OpenChest(app, abyss, worldX, worldY)
            if math.random() * 100 < Config.Abyss.chestEquipmentChance then
                AbyssLoot.TryDrop(app, abyss, tile, worldX, worldY - 6, true)
            end
        else
            AbyssLoot.TryDrop(app, abyss, tile, worldX, worldY - 6, false)
        end
    end
    return true
end

function AbyssTower:DamageEnemy(app, abyss, index, damage, source)
    local enemy = self.enemies[index]
    if not enemy then return false end
    require("diggin.RunCombatStats").Record(app.combatStats, source, "enemy", damage, enemy.hp)
    enemy.hp = enemy.hp - math.max(0, damage or 0)
    if enemy.hp <= 0 then self:KillEnemy(app, abyss, index, false); return true end
    return false
end

function AbyssTower:KillEnemy(app, abyss, index, silent)
    local enemy = self.enemies[index]
    if not enemy then return end
    table.remove(self.enemies, index)
    self.kills = self.kills + 1
    self:QueuePickup("fuel", enemy.x, enemy.y, app.maxFuel * Config.Abyss.enemyFuelDropPct / 100)
    if enemy.elite then
        self:QueuePickup("coin", enemy.x, enemy.y, Config.Abyss.eliteCoinAmount)
    elseif not enemy.horde and math.random() * 100 < Config.Abyss.enemyCoinDropChance then
        self:QueuePickup("coin", enemy.x, enemy.y, Config.Abyss.enemyCoinAmount)
    end
    if self.hordeActive and enemy.horde then
        self.hordeKills = math.min(self.hordeKillGoal, self.hordeKills + 1)
        self:QueuePickup("coin", enemy.x, enemy.y,
            Config.Abyss.hordeBonusCoinsPerKill + math.floor((self.hordeTier - 1) / 2))
        if self.hordeKills >= self.hordeKillGoal and not self.hordeRewardGranted then
            self.hordeRewardGranted = true
            AbyssLoot.TryDrop(app, abyss, {
                abyssFloor = self.floor,
                modifier = "horde",
            }, enemy.x, enemy.y - 7, true)
            if app.ShowToast then
                app:ShowToast("兽潮击退 · 深渊装备已掉落 · 出口仍可正常下潜", Config.Palette.gold, 3)
            end
        end
    end
    self:AddBurst(enemy.x, enemy.y, Config.Palette.cyan)
    if not silent and app.audio and app.audio.PlaySfx then app.audio:PlaySfx(Config.Audio.breakTile, 0.45, 1.18) end
end

function AbyssTower:FireProjectile(enemy, player)
    if #self.projectiles >= (Config.Abyss.maxEnemyProjectiles or 48) then return false end
    local dx, dy = Util.Normalize(player.x - enemy.x, player.y - enemy.y)
    self.projectiles[#self.projectiles + 1] = {
        x = enemy.x, y = enemy.y, vx = dx * 62, vy = dy * 62,
        life = 4.5, radius = 5, frame = 0, damageMultiplier = enemy.elite and 1.25 or 1,
    }
    return true
end

function AbyssTower:DamagePlayer(app, abyss, amount, sourceName, sourceMultiplier)
    if (self.shieldCharges or 0) > 0 then
        self.shieldCharges = self.shieldCharges - 1
        if app.ShowToast then app:ShowToast("根盾抵挡 · " .. sourceName, Config.Palette.green, 1.5) end
        return false
    end
    amount = math.max(0, amount) * AbyssDifficulty.GetEnemyDamageMultiplier(self.floor)
        * ((abyss and abyss.IsHardcore and abyss:IsHardcore())
            and Config.Abyss.hardcoreEnemyDamageMultiplier or 1)
        * (self.hordeActive and (1 + self.hordeTier * Config.Abyss.hordeDamagePerTier) or 1)
        * math.max(0, tonumber(sourceMultiplier) or 1)
        * (abyss and abyss.route and abyss.route.enemyDamageMultiplier or 1)
    app.fuel = math.max(0, app.fuel - amount)
    if app.AddBurst then app:AddBurst(app.player.x, app.player.y, Config.Palette.red, 10) end
    if app.ShowToast then app:ShowToast(sourceName .. " · 燃料 -" .. string.format("%.1f", amount), Config.Palette.red, 1.4) end
    if app.fuel <= 0 then
        if app.HandleFuelExhausted then app:HandleFuelExhausted("abyss_enemy")
        else app:EndRun("abyss_enemy") end
    end
    return true
end

function AbyssTower:UpdateEnemies(app, abyss, dt)
    self.spawnTimer = self.spawnTimer - dt
    if self.spawnedThisFloor < self.targetEnemyCount and self.spawnTimer <= 0
        and #self.enemies < (Config.Abyss.maxActiveEnemies or 18) then
        self:SpawnEnemy(app, nil, abyss)
        self.spawnedThisFloor = self.spawnedThisFloor + 1
        self.spawnTimer = self.hordeActive and math.max(Config.Abyss.hordeSpawnDelayMin,
            Config.Abyss.hordeSpawnDelay - (self.hordeTier - 1) * Config.Abyss.hordeSpawnDelayPerTier)
            or Config.Abyss.enemySpawnDelay
    end
    for index = #self.enemies, 1, -1 do
        local enemy = self.enemies[index]
        enemy.contactCooldown = math.max(0, enemy.contactCooldown - dt)
        enemy.slowTime = math.max(0, (enemy.slowTime or 0) - dt)
        enemy.shootTimer = enemy.shootTimer - dt
        local dx, dy = Util.Normalize(app.player.x - enemy.x, app.player.y - enemy.y)
        local slow = enemy.slowTime > 0 and 0.35 or 1
        enemy.x = enemy.x + dx * enemy.speed * slow * dt
        enemy.y = enemy.y + dy * enemy.speed * slow * dt
        if enemy.ranged and enemy.shootTimer <= 0 and Util.Length(app.player.x - enemy.x, app.player.y - enemy.y) < 135 then
            self:FireProjectile(enemy, app.player)
            enemy.shootTimer = math.max(1.1, 2.8 - self.floor * 0.04)
        end
        if enemy.contactCooldown <= 0 and Util.Length(app.player.x - enemy.x, app.player.y - enemy.y) <= 9 + enemy.size * 0.25 then
            enemy.contactCooldown = 1.1
            self:DamagePlayer(app, abyss, app.maxFuel * Config.Abyss.enemyContactFuelPct / 100,
                (enemy.elite and "精英·" or "") .. enemy.name .. "撞击", enemy.elite and 1.25 or 1)
            if app.mode ~= "playing" then return end
        end
    end
end

function AbyssTower:UpdateProjectiles(app, abyss, dt)
    for index = #self.projectiles, 1, -1 do
        local shot = self.projectiles[index]
        shot.life = shot.life - dt
        shot.x, shot.y = shot.x + shot.vx * dt, shot.y + shot.vy * dt
        shot.frame = (shot.frame or 0) + dt * 10
        if Util.Length(app.player.x - shot.x, app.player.y - shot.y) <= 9 then
            self:DamagePlayer(app, abyss, app.maxFuel * 0.05, "裂隙弹", shot.damageMultiplier)
            table.remove(self.projectiles, index)
        elseif shot.life <= 0 then
            table.remove(self.projectiles, index)
        end
    end
end

function AbyssTower:UpdatePickups(app, dt)
    for index = #self.pickups, 1, -1 do
        local pickup = self.pickups[index]
        pickup.life = pickup.life - dt
        local dx, dy = app.player.x - pickup.x, app.player.y - pickup.y
        local distance = Util.Length(dx, dy)
        local radius = pickup.kind == "coin" and self.magnetRadius or 84
        if distance < radius then
            local nx, ny = Util.Normalize(dx, dy)
            pickup.vx, pickup.vy = nx * Config.Abyss.coinPickupSpeed, ny * Config.Abyss.coinPickupSpeed
        else
            pickup.vy = pickup.vy + 90 * dt
            pickup.vx = pickup.vx * math.max(0, 1 - dt * 2)
        end
        pickup.x, pickup.y = pickup.x + pickup.vx * dt, pickup.y + pickup.vy * dt
        if distance <= 11 then
            if pickup.kind == "coin" then
                self.coins = self.coins + pickup.amount
                self.coinsEarned = self.coinsEarned + pickup.amount
                self.floorCoins = self.floorCoins + pickup.amount
            else
                app.fuel = math.min(app.maxFuel, app.fuel + pickup.amount)
            end
            if app.audio and app.audio.PlaySfx then app.audio:PlaySfx(Config.Audio.pickup, 0.35, pickup.kind == "coin" and 1.15 or 0.92) end
            table.remove(self.pickups, index)
        elseif pickup.life <= 0 then
            if pickup.kind == "coin" then
                self.coins = self.coins + pickup.amount
                self.coinsEarned = self.coinsEarned + pickup.amount
                self.floorCoins = self.floorCoins + pickup.amount
            end
            table.remove(self.pickups, index)
        end
    end
end

function AbyssTower:Update(app, abyss, dt)
    self.exitPulse = math.max(0, (self.exitPulse or 0) - dt)
    if self.flashFx then
        self.flashFx.life = self.flashFx.life - dt
        if self.flashFx.life <= 0 then self.flashFx = nil end
    end
    for index = #self.bursts, 1, -1 do
        self.bursts[index].life = self.bursts[index].life - dt
        if self.bursts[index].life <= 0 then table.remove(self.bursts, index) end
    end
    if self.simulationOnly then return end
    self:ReconcileExitState(app)
    if not self.shopFloor then self:UpdateEnemies(app, abyss, dt) end
    if app.mode ~= "playing" then return end
    self:UpdateProjectiles(app, abyss, dt)
    if app.mode ~= "playing" then return end
    self:UpdatePickups(app, dt)
end

function AbyssTower:UpdateLaser(app, abyss, dt)
    app.laserMax = self.laserMax
    app.laserEnergy = self.laserEnergy
    app.laserCooldownRemaining = self.laserCooldownRemaining or 0
    if self.laserCooldownRemaining > 0 then
        self.laserCooldownRemaining = math.max(0, self.laserCooldownRemaining - dt)
        app.laserCooldownRemaining = self.laserCooldownRemaining
        app.laserActive = false
        if self.laserCooldownRemaining <= 0 then
            self.laserEnergy = self.laserMax
            app.laserEnergy = self.laserEnergy
        end
        return
    end

    local range = Config.Abyss.towerLaserRange
    local target, targetDistance = nil, nil
    for _, enemy in ipairs(self.enemies) do
        if (enemy.hp or 0) > 0 then
            local distance = Util.Length(enemy.x - app.player.x, enemy.y - app.player.y)
            if distance <= range and (not targetDistance or distance < targetDistance) then
                target, targetDistance = enemy, distance
            end
        end
    end
    if not target then
        app.laserActive = false
        app.laserEndX, app.laserEndY = app.player.x, app.player.y
        return
    end

    app.laserActive = true
    self.laserEnergy = math.max(0, self.laserEnergy - Config.Abyss.towerLaserDrain * dt)
    app.laserEnergy = self.laserEnergy
    if self.laserEnergy <= 0 then
        self.laserCooldownRemaining = Config.Abyss.towerLaserCooldown
        app.laserCooldownRemaining = self.laserCooldownRemaining
        app.laserActive = false
        return
    end
    local safeDistance = math.max(0.001, targetDistance)
    local dx = (target.x - app.player.x) / safeDistance
    local dy = (target.y - app.player.y) / safeDistance
    local endX, endY = app.player.x + dx * range, app.player.y + dy * range
    local hits = {}
    for index, enemy in ipairs(self.enemies) do
        local distance, t = distanceToSegment(enemy.x, enemy.y, app.player.x, app.player.y, endX, endY)
        if distance <= math.max(7, enemy.size * 0.45) then hits[#hits + 1] = { index = index, t = t, enemy = enemy } end
    end
    table.sort(hits, function(a, b) return a.t < b.t end)
    local allowed = math.min(#hits, 1 + self.laserPierce)
    if allowed > 0 then endX, endY = hits[allowed].enemy.x, hits[allowed].enemy.y end
    app.laserEndX, app.laserEndY = endX, endY
    app.laserHitTimer = (app.laserHitTimer or 0) - dt
    if app.laserHitTimer <= 0 and allowed > 0 then
        app.laserHitTimer = 0.12
        local damage = app.state:GetGeneralStat("drill_damage") * Config.Abyss.towerLaserDamageScale * self.laserDamageMultiplier
        -- Descending array indices stay valid as killed enemies are removed.
        local indices = {}
        for hitIndex = 1, allowed do indices[#indices + 1] = hits[hitIndex].index end
        table.sort(indices, function(a, b) return a > b end)
        for _, index in ipairs(indices) do self:DamageEnemy(app, abyss, index, damage, "laser") end
        if app.AddBurst then app:AddBurst(endX, endY, Config.Palette.cyan, 3) end
    end
end

function AbyssTower:TryFlash(app, abyss, distance)
    local dx, dy = math.cos(app.aimAngle or 0), math.sin(app.aimAngle or 0)
    if math.abs(dx) + math.abs(dy) < 0.1 then dx, dy = 1, 0 end
    local requested = math.max(12, (distance or Config.Abyss.flashDistance) + self.flashBonus)
    local startX, startY = app.player.x, app.player.y
    if not app.world or not app.world.IsSolidAtPixel then
        app.player.x, app.player.y = startX + dx * requested, startY + dy * requested
        self.flashFx = { x = startX, y = startY, toX = app.player.x, toY = app.player.y, life = 0.34, maxLife = 0.34 }
        return requested
    end
    local bestX, bestY = startX, startY
    for step = 4, requested, 4 do
        local nx, ny = startX + dx * step, startY + dy * step
        if not canOccupy(app.world, nx, ny) then break end
        bestX, bestY = nx, ny
    end
    app.player.x, app.player.y = bestX, bestY
    app.player.vx, app.player.vy = dx * 18, dy * 18
    self.flashFx = { x = startX, y = startY, toX = bestX, toY = bestY, life = 0.34, maxLife = 0.34 }
    self:AddBurst(bestX, bestY, Config.Palette.cyan)
    return Util.Length(bestX - startX, bestY - startY)
end

function AbyssTower:GetShopCost(floor)
    return AbyssDifficulty.GetSupplyCost(floor or self.floor)
end

function AbyssTower:BuyMerchantFuel(app, floor)
    if not self:IsShopFloorNumber(floor) or self.merchantFuelPurchased then
        return false, self:GetShopCost(floor), "used"
    end
    local cost = self:GetShopCost(floor)
    if self.coins < cost then return false, cost, "coins" end
    if app.fuel >= app.maxFuel then return false, cost, "full" end
    self.coins = self.coins - cost
    app.fuel = math.min(app.maxFuel, app.fuel
        + app.maxFuel * (Config.Abyss.merchantFuelRestorePct or 50) / 100)
    self.merchantFuelPurchased = true
    return true, cost, "ok"
end

return AbyssTower
