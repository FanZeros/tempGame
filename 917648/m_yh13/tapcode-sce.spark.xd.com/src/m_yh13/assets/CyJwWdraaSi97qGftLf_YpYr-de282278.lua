local Config = require("diggin.Config")
local Util = require("diggin.Util")
local AbyssDifficulty = require("diggin.AbyssDifficulty")
local AbyssPortalSchedule = require("diggin.AbyssPortalSchedule")

local World = {}
World.__index = World

local function keyFor(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

function World.New(state)
    local self = setmetatable({}, World)
    self.state = state
    self.seed = math.random(1, 999999)
    self.tiles = {}
    self.starmetalPositions = {}
    self.layersWithStarmetal = {}
    return self
end

function World:Reset()
    self.seed = math.random(1, 999999)
    self.tiles = {}
    self.starmetalPositions = {}
    self.layersWithStarmetal = {}
end

function World:EffectiveDepth(authoredDepth)
    if self.state.prestige == 11 then
        local finalDensityDepth = math.floor(authoredDepth / Config.FINAL_DENSITY_COMPRESSION)
        if self.state.abyssRulesActive then
            return finalDensityDepth * Config.ABYSS_LAYER_DEPTH_MULTIPLIER
        end
        return finalDensityDepth
    end
    return authoredDepth
end

function World:GetLayerIndex(tileY)
    local depth = tileY - Config.SURFACE_Y
    if self.state.abyssRulesActive then
        local floor = math.max(1, math.floor(math.max(0, depth) / Config.Abyss.floorDepthTiles) + 1)
        return ((floor - 1) % #Config.Layers) + 1
    end
    local index = 1
    for i, layer in ipairs(Config.Layers) do
        if depth >= self:EffectiveDepth(layer.fromY) then index = i end
    end
    return index
end

function World:GetAbyssFloor(tileY)
    local depth = math.max(0, (tonumber(tileY) or Config.SURFACE_Y) - Config.SURFACE_Y)
    return math.floor(depth / Config.Abyss.floorDepthTiles) + 1
end

function World:GetAbyssHealthMultiplier(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    local hardcoreMultiplier = self.state.abyssHardcoreActive
        and Config.Abyss.hardcoreTileHealthMultiplier or 1
    return Config.Abyss.tileHealthMultiplier
        * AbyssDifficulty.GetTileHealthMultiplier(floor) * hardcoreMultiplier
end

function World:GetAbyssExitHealthMultiplier(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    local hardcoreMultiplier = self.state.abyssHardcoreActive
        and Config.Abyss.hardcoreTileHealthMultiplier or 1
    return Config.Abyss.tileHealthMultiplier
        * AbyssDifficulty.GetExitHealthMultiplier(floor) * hardcoreMultiplier
end

-- Portal floors use a deterministic three-cell gate. Other floors keep normal
-- mineable seams, allowing continuous descent until the next portal milestone.
function World:GetAbyssExitX(floor)
    local halfWidth = self:GetWorldHalfWidth()
    if self:IsAbyssShopFloor(floor) then return math.max(0, halfWidth - 1) end
    local margin = halfWidth >= 3 and 1 or 0
    return Util.HashInt(math.max(1, math.floor(tonumber(floor) or 1)), self.seed, 9421,
        -halfWidth + margin, halfWidth - margin)
end

function World:IsAbyssShopFloor(floor)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    local interval = math.max(1, math.floor(tonumber(Config.Abyss.merchantFloorInterval) or 50))
    return floor > 1 and floor % interval == 0
end

function World:IsAbyssPortalFloor(floor)
    return AbyssPortalSchedule.IsPortalFloor(floor)
end

-- The portal spans three tile columns. Clear both its gate row and the first
-- row of the next floor, otherwise an apparently open portal immediately hits
-- a cached/generated ore tile (most visible on the floor-50 merchant room).
function World:OpenAbyssExitArea(floor, centerX, halfWidth)
    floor = math.max(1, math.floor(tonumber(floor) or 1))
    centerX = math.floor(tonumber(centerX) or self:GetAbyssExitX(floor))
    halfWidth = math.max(1, math.floor(tonumber(halfWidth) or 1))
    local gateY = Config.SURFACE_Y + floor * Config.Abyss.floorDepthTiles - 1
    local opened = 0
    for y = gateY, gateY + 1 do
        for x = centerX - halfWidth, centerX + halfWidth do
            local key = keyFor(x, y)
            if self.tiles[key] ~= false then opened = opened + 1 end
            self.tiles[key] = false
        end
    end
    return opened
end

-- Abyss floors are one-way chambers. Keeping every generated tile and mined
-- tombstone from hundreds of completed floors makes Lua's garbage collector
-- periodically scan an ever-growing table. Retain a small safety history for
-- camera/jump overlap and release everything older at floor transitions.
function World:PruneAbyssFloorsBefore(minFloor)
    if not self.state.abyssRulesActive then return 0 end
    minFloor = math.max(1, math.floor(tonumber(minFloor) or 1))
    if minFloor <= 1 then return 0 end
    local cutoffY = Config.SURFACE_Y + (minFloor - 1) * Config.Abyss.floorDepthTiles
    local removed = 0
    for key, tile in pairs(self.tiles) do
        local tileY
        if type(tile) == "table" then
            tileY = tonumber(tile.y)
        else
            tileY = tonumber(tostring(key):match(":(-?%d+)$"))
        end
        if tileY and tileY < cutoffY then
            self.tiles[key] = nil
            removed = removed + 1
        end
    end
    return removed
end

function World:GetLayer(tileY)
    return Config.Layers[self:GetLayerIndex(tileY)]
end

function World:GetLayerNumber(tileY)
    return self:GetLayerIndex(tileY) - 1
end

function World:GetWorldHalfWidth()
    if self.state.abyssRulesActive then return Config.Abyss.halfWidthTiles end
    return math.max(2, math.floor(self.state:GetGeneralStat("world_width") * 0.5))
end

function World:CanPlaceStarmetal(x, y, layerIndex)
    if layerIndex < 5 or self.state.prestige < 4 then return false end
    if #self.starmetalPositions >= 3 or self.layersWithStarmetal[layerIndex] then return false end
    for _, position in ipairs(self.starmetalPositions) do
        local dx = position.x - x
        local dy = position.y - y
        if dx * dx + dy * dy < 25 then return false end
    end
    return true
end

function World:SelectOre(x, y, layer, layerIndex)
    local roll = Util.Hash01(x * 1.2345, y * 0.9876, self.seed + 17)
    local total = 0
    local candidates = {}
    local platinumBonus = not self.state.abyssRulesActive
        and math.min((layer.weights.Platinum or 0) * 0.20, layer.weights.Stone or 0) or 0
    for oreName, weight in pairs(layer.weights) do
        local effective = math.max(0, weight)
        if oreName == "Platinum" then effective = effective + platinumBonus end
        if oreName == "Stone" then effective = effective - platinumBonus end
        if oreName ~= "Stone" and oreName ~= "Silver" then
            effective = effective * (1 + self.state:GetRelicBonus("rare_ore_weight_pct") / 100)
        end
        if oreName == "Starmetal" then
            effective = effective * self.state.prestige / 8
        end
        total = total + effective
        candidates[#candidates + 1] = { name = oreName, weight = effective }
    end
    table.sort(candidates, function(a, b)
        return (Config.Ores[a.name] and Config.Ores[a.name].id or 0) < (Config.Ores[b.name] and Config.Ores[b.name].id or 0)
    end)
    local cursor = roll * total
    local selected = "Stone"
    for _, candidate in ipairs(candidates) do
        cursor = cursor - candidate.weight
        if cursor <= 0 then selected = candidate.name; break end
    end
    if selected == "Starmetal" then
        if not self:CanPlaceStarmetal(x, y, layerIndex) then return "Stone" end
        self.starmetalPositions[#self.starmetalPositions + 1] = { x = x, y = y }
        self.layersWithStarmetal[layerIndex] = true
    end
    return selected
end

function World:SelectModifier(x, y, oreName)
    local roll = Util.Hash01(x, y, self.seed + 301) * 100
    if self.state.abyssRulesActive and self.state.abyssRouteId == "risk" and roll < 4 then return "boomstone" end
    if self.state:IsNodeBought("Boomstone") and roll < self.state:GetActiveStat("boomstone", "chance") then
        return "boomstone"
    end
    roll = Util.Hash01(x, y, self.seed + 302) * 100
    if self.state:IsNodeBought("Fuelstone") and roll < self.state:GetActiveStat("fuelstone", "chance") then
        return "fuelstone"
    end
    roll = Util.Hash01(x, y, self.seed + 303) * 100
    if self.state:IsNodeBought("Feverstone") and roll < self.state:GetActiveStat("feverstone", "chance") then
        return "feverstone"
    end
    local routeChestBonus = self.state.abyssRulesActive and self.state.abyssRouteId == "treasure" and 0.018 or 0
    local chestThreshold = 0.997 - routeChestBonus - self.state:GetRelicBonus("chest_chance_flat") / 100
    if y > Config.SURFACE_Y + 12 and Util.Hash01(x, y, self.seed + 401) > chestThreshold then
        return "chest"
    end
    if oreName == "Silver" and self.state:IsNodeBought("SilverBonanza") and Util.Hash01(x, y, self.seed + 501) * 100 < 5 then
        return "bonanza"
    end
    if oreName == "Gold" and self.state:IsNodeBought("GoldBonanza") and Util.Hash01(x, y, self.seed + 502) * 100 < 3 then
        return "bonanza"
    end
    if oreName == "Platinum" and self.state:IsNodeBought("PlatinumBonanza") and Util.Hash01(x, y, self.seed + 503) * 100 < 2 then
        return "bonanza"
    end
    if oreName == "Iridium" and self.state:IsNodeBought("IridiumBonanza") and Util.Hash01(x, y, self.seed + 504) * 100 < 1 then
        return "bonanza"
    end
    return nil
end

function World:CreateTile(x, y)
    if y < Config.SURFACE_Y then return nil end
    local halfWidth = self:GetWorldHalfWidth()
    if x < -halfWidth or x > halfWidth then
        return {
            x = x, y = y, ore = "Bedrock", health = math.huge, maxHealth = math.huge,
            layerIndex = self:GetLayerIndex(y), tilemap = 12, variant = Util.HashInt(x, y, self.seed, 0, 2),
            indestructible = true,
        }
    end
    if not self.state.abyssRulesActive and y - Config.SURFACE_Y >= self:EffectiveDepth(320) then
        return {
            x = x, y = y, ore = "StarBarrier", health = 1, maxHealth = 1,
            layerIndex = #Config.Layers, tilemap = 11, variant = Util.HashInt(x, y, self.seed, 0, 2),
            indestructible = self.state.prestige ~= 11,
        }
    end
    local layerIndex = self:GetLayerIndex(y)
    local layer = Config.Layers[layerIndex]
    local abyssFloor = self.state.abyssRulesActive and self:GetAbyssFloor(y) or nil
    local abyssDepth = y - Config.SURFACE_Y
    if abyssFloor and self:IsAbyssShopFloor(abyssFloor) then
        local floorTop = Config.SURFACE_Y + (abyssFloor - 1) * Config.Abyss.floorDepthTiles
        local platformY = floorTop + Config.Abyss.floorDepthTiles - 4
        local exitX = self:GetAbyssExitX(abyssFloor)
        -- Safe merchant rooms are open chambers resting on a wide, unbreakable
        -- floor.  The three-column shaft at the far right is already open so
        -- visiting the merchant never blocks the endless run.
        if y < platformY or math.abs(x - exitX) <= Config.Abyss.exitHalfWidthTiles then
            return nil
        end
        return {
            x = x, y = y, ore = "Bedrock", health = math.huge, maxHealth = math.huge,
            layerIndex = layerIndex, abyssFloor = abyssFloor, abyssShopFloor = true,
            tilemap = layer.tilemap, variant = Util.HashInt(x, y, self.seed + 1281, 0, 2),
            indestructible = true,
        }
    end
    local isPortalFloor = abyssFloor and self:IsAbyssPortalFloor(abyssFloor)
    local isAbyssGateRow = isPortalFloor and abyssDepth >= 0
        and abyssDepth % Config.Abyss.floorDepthTiles == Config.Abyss.floorDepthTiles - 1
    local isAbyssExit = isAbyssGateRow
        and math.abs(x - self:GetAbyssExitX(abyssFloor)) <= Config.Abyss.exitHalfWidthTiles
    if isAbyssGateRow and not isAbyssExit then
        return {
            x = x, y = y, ore = "Bedrock", health = math.huge, maxHealth = math.huge,
            layerIndex = layerIndex, abyssFloor = abyssFloor, abyssGate = true,
            tilemap = layer.tilemap, variant = Util.HashInt(x, y, self.seed + 81, 0, 2),
            indestructible = true,
        }
    end
    local oreName = self:SelectOre(x, y, layer, layerIndex)
    local ore = Config.Ores[oreName] or Config.Ores.Stone
    local prestigeMultiplier = Config.PRESTIGE_FACTOR ^ (self.state.prestige - 1)
    local health = ore.health * layer.health * prestigeMultiplier
    if self.state.abyssRulesActive then
        local routeMultiplier = math.max(0.35, tonumber(self.state.abyssRouteHealthMultiplier) or 1)
        local abyssHealthMultiplier = isAbyssExit
            and self:GetAbyssExitHealthMultiplier(abyssFloor)
            or self:GetAbyssHealthMultiplier(abyssFloor)
        health = health * abyssHealthMultiplier * routeMultiplier
        if isAbyssExit then health = health * Config.Abyss.exitHealthMultiplier end
    end
    return {
        x = x,
        y = y,
        ore = oreName,
        health = health,
        maxHealth = health,
        layerIndex = layerIndex,
        abyssFloor = abyssFloor,
        abyssExit = isAbyssExit == true,
        tilemap = layer.tilemap,
        variant = Util.HashInt(x, y, self.seed + 81, 0, 2),
        modifier = isAbyssExit and nil or self:SelectModifier(x, y, oreName),
        indestructible = ore.indestructible == true,
    }
end

function World:GetTile(x, y)
    x = math.floor(x)
    y = math.floor(y)
    local key = keyFor(x, y)
    if self.tiles[key] == false then return nil end
    if self.tiles[key] == nil then self.tiles[key] = self:CreateTile(x, y) or false end
    if self.tiles[key] == false then return nil end
    return self.tiles[key]
end

function World:IsSolidTile(x, y)
    return self:GetTile(x, y) ~= nil
end

function World:IsSolidAtPixel(worldX, worldY)
    return self:IsSolidTile(math.floor(worldX / Config.TILE_SIZE), math.floor(worldY / Config.TILE_SIZE))
end

function World:MovePlayer(player, dt)
    local radius = 5
    local nextX = player.x + player.vx * dt
    local topY = player.y - radius
    local bottomY = player.y + radius
    if player.vx > 0 and (self:IsSolidAtPixel(nextX + radius, topY) or self:IsSolidAtPixel(nextX + radius, bottomY)) then
        local tileX = math.floor((nextX + radius) / Config.TILE_SIZE)
        nextX = tileX * Config.TILE_SIZE - radius - 0.01
        player.vx = 0
    elseif player.vx < 0 and (self:IsSolidAtPixel(nextX - radius, topY) or self:IsSolidAtPixel(nextX - radius, bottomY)) then
        local tileX = math.floor((nextX - radius) / Config.TILE_SIZE)
        nextX = (tileX + 1) * Config.TILE_SIZE + radius + 0.01
        player.vx = 0
    end
    player.x = nextX

    local nextY = player.y + player.vy * dt
    if player.vy > 0 and (self:IsSolidAtPixel(player.x - radius, nextY + radius) or self:IsSolidAtPixel(player.x + radius, nextY + radius)) then
        local tileY = math.floor((nextY + radius) / Config.TILE_SIZE)
        nextY = tileY * Config.TILE_SIZE - radius - 0.01
        player.vy = 0
        player.onGround = true
    elseif player.vy < 0 and (self:IsSolidAtPixel(player.x - radius, nextY - radius) or self:IsSolidAtPixel(player.x + radius, nextY - radius)) then
        local tileY = math.floor((nextY - radius) / Config.TILE_SIZE)
        nextY = (tileY + 1) * Config.TILE_SIZE + radius + 0.01
        player.vy = 0
    else
        player.onGround = false
    end
    player.y = nextY
end

function World:GetDrillTarget(player, aimX, aimY)
    local dx, dy = Util.Normalize(aimX - player.x, aimY - player.y)
    local probeX = player.x + dx * 18
    local probeY = player.y + dy * 18
    local tileX = math.floor(probeX / Config.TILE_SIZE)
    local tileY = math.floor(probeY / Config.TILE_SIZE)
    return self:GetTile(tileX, tileY), dx, dy
end

function World:DamageTile(tile, damage, critical, source)
    if not tile then return false, nil end
    if tile.indestructible then return false, tile end
    if self.state.abyssRulesActive and tile.abyssFloor then
        local currentFloor = math.max(1,
            math.floor(tonumber(self.state.abyssCurrentFloor) or tile.abyssFloor))
        -- The player rests immediately above the first row of the next floor.
        -- That seam must be breakable before their centre can cross the floor
        -- boundary and let AbyssMode advance. Keep every deeper future tile
        -- protected so wide effects still cannot pre-clear later chambers.
        local nextFloorEntryRow = Config.SURFACE_Y
            + currentFloor * Config.Abyss.floorDepthTiles
        local isNextFloorEntry = tile.abyssFloor == currentFloor + 1
            and tile.y == nextFloorEntryRow
        if tile.abyssFloor > currentFloor and not isNextFloorEntry then return false, tile end
    end
    local finalDamage = damage
    if critical then finalDamage = finalDamage * self.state:GetGeneralStat("critical_damage_multiplier") end
    require("diggin.RunCombatStats").Record(self.combatStats, source, "ore", finalDamage, tile.health)
    tile.health = tile.health - finalDamage
    if tile.health > 0 then return false, tile end
    self.tiles[keyFor(tile.x, tile.y)] = false
    return true, tile
end

function World:DamageArea(worldX, worldY, radius, damage, onDestroyed, source)
    local minX = math.floor((worldX - radius) / Config.TILE_SIZE)
    local maxX = math.floor((worldX + radius) / Config.TILE_SIZE)
    local minY = math.floor((worldY - radius) / Config.TILE_SIZE)
    local maxY = math.floor((worldY + radius) / Config.TILE_SIZE)
    local count = 0
    for y = minY, maxY do
        for x = minX, maxX do
            local cx = x * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
            local cy = y * Config.TILE_SIZE + Config.TILE_SIZE * 0.5
            if Util.Length(cx - worldX, cy - worldY) <= radius then
                local destroyed, tile = self:DamageTile(self:GetTile(x, y), damage, false, source)
                if destroyed then
                    count = count + 1
                    if onDestroyed then onDestroyed(tile) end
                end
            end
        end
    end
    return count
end

function World:GetFuelCost(tile, maxFuel)
    if not tile then return 0 end
    if tile.ore == "StarBarrier" then return maxFuel / 3 end
    local layer = tile.layerIndex - 1
    local baseCost = math.max(1, (layer + 1) ^ 3) / 3
    if self.state.abyssRulesActive then
        local floor = tile.abyssFloor or self:GetAbyssFloor(tile.y)
        return baseCost * (1 + math.max(0, floor - 1) * 0.08)
    end
    return baseCost * Config.PRESTIGE_FACTOR ^ (self.state.prestige - 1)
end

return World
