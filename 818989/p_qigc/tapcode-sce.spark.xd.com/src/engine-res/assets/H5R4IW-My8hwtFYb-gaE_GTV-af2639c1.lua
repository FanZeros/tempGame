-- Procedural demolition district for the voxel physics benchmark.
--
-- A Teardown-scale small lot: several buildings of a few archetypes, a water tower, boundary
-- walls and crate stacks, all destructible at 0.1 m granularity — one to two million solid voxels.
-- Everything is authored in METRES and generated deterministically, so a benchmark run is
-- comparable across engine versions, and the same module doubles as a showcase scene.

local M = {}

M.VOXEL = 0.1                   -- destruction granularity of every building
M.GROUND_VOXEL = 0.25           -- scenery only; indestructible

-- Metres-to-index span for a volume with the given voxel size. lo inclusive, hi exclusive.
local function Span(v, lo, hi)
    return math.floor(lo / v + 0.5), math.floor(hi / v + 0.5) - 1
end

-- Flat palette colours, one per archetype. Every volume is painted uniformly — one material per
-- volume means the mesher never splits quads at paint borders, so quad counts (and therefore the
-- remesh numbers this scene exists to measure) stay comparable with pre-palette baselines.
-- Hardness stays 0: the workload's damage calls use the default infinite power either way.
M.MAT_WALL = 1
M.MAT_STEEL = 2
M.MAT_CRATE = 3
M.MAT_GROUND = 4

function M.DefinePalette(world)
    world:SetPaletteEntry(M.MAT_WALL, Color(0.62, 0.58, 0.52), 0.0)
    world:SetPaletteEntry(M.MAT_STEEL, Color(0.46, 0.51, 0.58), 0.0)
    world:SetPaletteEntry(M.MAT_CRATE, Color(0.58, 0.44, 0.28), 0.0)
    world:SetPaletteEntry(M.MAT_GROUND, Color(0.42, 0.44, 0.40), 0.0)
end

local function PaintAll(volume, material)
    volume:GetGrid():PaintBox(0, 0, 0, 100000, 100000, 100000, material)
end

-- 100 x 100 m ground, tiled because one volume caps at 256 voxels per axis.
function M.CreateGround(world)
    local tile = 200            -- 50 m per tile at 0.25
    for tx = 0, 1 do
        for tz = 0, 1 do
            local origin = Vector3(-50.0 + tx * 50.0, -4 * M.GROUND_VOXEL, -50.0 + tz * 50.0)
            local ground = world:CreateVolume(tile, 4, tile, M.GROUND_VOXEL, origin, Quaternion())
            ground:GetGrid():FillBox(0, 0, 0, tile - 1, 3, tile - 1, true)
            PaintAll(ground, M.MAT_GROUND)
            ground.material = world:GetPaletteMaterial()
            ground.destructible = false
            world:FinalizeVolume(ground)
            ground:RebuildGeometry()
        end
    end
end

-- One-storey house: the demo archetype, parameterised. sx/sy/sz metres, walls/roof `t` thick.
local function House(world, origin, sx, sy, sz, t)
    local v = M.VOXEL
    local wx0, wx1 = Span(v, 0, sx)
    local wy0, wy1 = Span(v, 0, sy)
    local wz0, wz1 = Span(v, 0, sz)
    local house = world:CreateVolume(wx1 + 1, wy1 + 1, wz1 + 1, v, origin, Quaternion())
    local g = house:GetGrid()

    local function Carve(x0, y0, z0, x1, y1, z1)
        local ax0, ax1 = Span(v, x0, x1)
        local ay0, ay1 = Span(v, y0, y1)
        local az0, az1 = Span(v, z0, z1)
        g:FillBox(ax0, ay0, az0, ax1, ay1, az1, false)
    end

    g:FillBox(wx0, wy0, wz0, wx1, wy1, wz1, true)
    Carve(t, 0.0, t, sx - t, sy - t, sz - t)
    Carve(0.0, 0.0, sz * 0.4, t, 2.4, sz * 0.4 + 1.2)          -- door on -X
    -- One window per wall at eye height; small houses get proportionally small ones.
    local wlo, whi = 1.4, 2.4
    Carve(0.0, wlo, sz * 0.7, t, whi, sz * 0.7 + 1.0)
    Carve(sx - t, wlo, sz * 0.25, sx, whi, sz * 0.25 + 1.0)
    Carve(sx * 0.3, wlo, 0.0, sx * 0.3 + 1.0, whi, t)
    Carve(sx * 0.6, wlo, sz - t, sx * 0.6 + 1.0, whi, sz)

    PaintAll(house, M.MAT_WALL)
    house.material = world:GetPaletteMaterial()
    world:FinalizeVolume(house)
    house:RebuildGeometry()
    return house
end

-- Two-storey block: like the house plus an interior floor slab with a stair hole.
local function Block(world, origin, sx, sy, sz, t)
    local v = M.VOXEL
    local wx0, wx1 = Span(v, 0, sx)
    local wy0, wy1 = Span(v, 0, sy)
    local wz0, wz1 = Span(v, 0, sz)
    local block = world:CreateVolume(wx1 + 1, wy1 + 1, wz1 + 1, v, origin, Quaternion())
    local g = block:GetGrid()

    local function Fill(x0, y0, z0, x1, y1, z1, solid)
        local ax0, ax1 = Span(v, x0, x1)
        local ay0, ay1 = Span(v, y0, y1)
        local az0, az1 = Span(v, z0, z1)
        g:FillBox(ax0, ay0, az0, ax1, ay1, az1, solid)
    end

    Fill(0, 0, 0, sx, sy, sz, true)
    Fill(t, 0, t, sx - t, sy - t, sz - t, false)
    local mid = sy * 0.5
    Fill(t, mid, t, sx - t, mid + t, sz - t, true)              -- storey slab
    Fill(sx * 0.6, mid, sz * 0.6, sx * 0.6 + 2.0, mid + t, sz * 0.6 + 2.0, false)  -- stair hole
    Fill(0.0, 0.0, sz * 0.4, t, 2.4, sz * 0.4 + 1.2, false)     -- door
    for _, wy in ipairs({ 1.4, mid + 1.4 }) do                  -- window rows, both storeys
        Fill(0.0, wy, sz * 0.7, t, wy + 1.0, sz * 0.7 + 1.0, false)
        Fill(sx - t, wy, sz * 0.25, sx, wy + 1.0, sz * 0.25 + 1.0, false)
        Fill(sx * 0.3, wy, 0.0, sx * 0.3 + 1.0, wy + 1.0, t, false)
        Fill(sx * 0.6, wy, sz - t, sx * 0.6 + 1.0, wy + 1.0, sz, false)
    end

    PaintAll(block, M.MAT_WALL)
    block.material = world:GetPaletteMaterial()
    world:FinalizeVolume(block)
    block:RebuildGeometry()
    return block
end

-- Water tower: a tank on four slim legs — the collapse-prone structure that exercises severing,
-- the support-aware keeper and big-piece freezing.
local function WaterTower(world, origin)
    local v = M.VOXEL
    local sx, sy, sz = 4.0, 8.0, 4.0
    local wx0, wx1 = Span(v, 0, sx)
    local wy0, wy1 = Span(v, 0, sy)
    local wz0, wz1 = Span(v, 0, sz)
    local tower = world:CreateVolume(wx1 + 1, wy1 + 1, wz1 + 1, v, origin, Quaternion())
    local g = tower:GetGrid()

    local function Fill(x0, y0, z0, x1, y1, z1)
        local ax0, ax1 = Span(v, x0, x1)
        local ay0, ay1 = Span(v, y0, y1)
        local az0, az1 = Span(v, z0, z1)
        g:FillBox(ax0, ay0, az0, ax1, ay1, az1, true)
    end

    for _, lx in ipairs({ 0.2, sx - 0.6 }) do
        for _, lz in ipairs({ 0.2, sz - 0.6 }) do
            Fill(lx, 0.0, lz, lx + 0.4, 5.0, lz + 0.4)          -- legs
        end
    end
    Fill(0.0, 5.0, 0.0, sx, 7.5, sz)                            -- tank

    PaintAll(tower, M.MAT_STEEL)
    tower.material = world:GetPaletteMaterial()
    world:FinalizeVolume(tower)
    tower:RebuildGeometry()
    return tower
end

-- A stack of loose crates: light dynamic bodies for heavy-on-light contact load.
local function CrateStack(world, origin, count)
    local v = M.VOXEL
    for i = 0, count - 1 do
        local side = 6          -- 0.6 m crates
        local crate = world:CreateVolume(side, side, side, v,
            origin + Vector3((i % 2) * 0.65, math.floor(i / 2) * 0.62, (i % 3) * 0.2), Quaternion())
        crate:GetGrid():FillBox(0, 0, 0, side - 1, side - 1, side - 1, true)
        PaintAll(crate, M.MAT_CRATE)
        crate.material = world:GetPaletteMaterial()
        crate.density = 200.0
        world:FinalizeVolumeAsDynamic(crate)
        crate:RebuildGeometry()
    end
end

-- Builds the whole district. Returns the list of buildings so the workload can aim at them.
function M.CreateDistrict(world)
    M.DefinePalette(world)
    M.CreateGround(world)

    local buildings = {}
    -- Main street: three houses and two blocks, 14 m pitch.
    table.insert(buildings, House(world, Vector3(-20.0, 0.0, -18.0), 8.0, 5.0, 7.0, 0.5))
    table.insert(buildings, House(world, Vector3(-6.0, 0.0, -19.0), 7.0, 4.5, 8.0, 0.5))
    table.insert(buildings, House(world, Vector3(8.0, 0.0, -18.0), 9.0, 5.5, 7.5, 0.5))
    table.insert(buildings, Block(world, Vector3(-18.0, 0.0, 6.0), 10.0, 7.0, 9.0, 0.5))
    table.insert(buildings, Block(world, Vector3(0.0, 0.0, 8.0), 12.0, 7.5, 10.0, 0.5))
    table.insert(buildings, House(world, Vector3(18.0, 0.0, 8.0), 8.0, 5.0, 8.0, 0.5))
    table.insert(buildings, WaterTower(world, Vector3(24.0, 0.0, -14.0)))

    CrateStack(world, Vector3(-10.0, 0.0, -5.0), 8)
    CrateStack(world, Vector3(14.0, 0.0, 0.0), 6)

    world:OptimizeBroadPhase()
    return buildings
end

function M.CreateEnvironment(scene)
    local zoneNode = scene:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(-2000.0, 2000.0)
    zone.ambientColor = Color(0.28, 0.30, 0.34)
    zone.fogColor = Color(0.52, 0.60, 0.70)
    zone.fogStart = 80.0
    zone.fogEnd = 300.0

    local lightNode = scene:CreateChild("Sun")
    lightNode.direction = Vector3(0.6, -1.0, 0.45)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.castShadows = true
    light.brightness = 1.1
end

return M
