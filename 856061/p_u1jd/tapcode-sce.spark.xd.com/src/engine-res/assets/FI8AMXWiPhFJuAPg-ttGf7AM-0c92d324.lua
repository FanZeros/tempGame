-- Shared scenery for the voxel destruction samples: the ground and the house.
--
-- Extracted so VoxelDrivingDemo and VoxelDemolitionDemo build the same building. Two copies of a
-- sixty-line grid-carving routine drift apart within a couple of edits, and the demos are most useful
-- when "what happens when you hit this wall" means the same thing in both.
--
-- Returns a table of functions; nothing here touches globals other than the engine's own.

local M = {}

-- Voxel size of the HOUSE — the destruction granularity of the samples. 0.1 m breaks into fist-sized
-- pieces rather than half-metre blocks.
--
-- The house is authored in METRES below and converted, so this number can be changed alone and the
-- building keeps its size, wall thickness and openings. At 0.1 the same 8 x 6 x 8 m house holds about
-- 114k solid voxels against 6.7k at 0.25; storage is a bitset so that is kilobytes, and the greedy
-- surface mesher merges flat walls into the same large quads regardless of resolution, so neither is
-- the render cost. What does scale is per-damage work (labeling, spall grouping) — fine per event,
-- one more reason impacts are cooldown-limited rather than per-frame.
M.VOXEL = 0.1

-- The ground stays at a coarser voxel than the house, for two reasons that do not apply to anything
-- destructible. First, VoxelGrid caps a volume at 256 voxels per axis, and this 60 m field would need
-- 600 at 0.1 — it simply does not fit in one volume. Second, the ground is indestructible scenery:
-- granularity only shows where material is removed or curved, and this is neither.
M.GROUND_VOXEL = 0.25
M.GROUND_VOXELS = 240
M.GROUND_THICK = 4
M.GROUND_HALF = M.GROUND_VOXELS * M.GROUND_VOXEL * 0.5

-- House: 8 x 8 m footprint, 6 m tall, walls and roof 0.5 m thick. Front door faces -X, so a vehicle
-- approaching along +X drives straight at it.
M.HOUSE_SIZE = Vector3(8.0, 6.0, 8.0)

-- Palette indices used by the scenery, defined once by M.DefinePalette. Hardness is what a damage
-- call's power is measured against: fists dent plaster, only heavy blows crack the concrete roof.
M.MAT_BRICK = 1
M.MAT_ROOF = 2
M.MAT_TRIM = 3
M.MAT_GROUND = 4
M.MAT_GLASS = 5

function M.DefinePalette(world)
    world:SetPaletteEntry(M.MAT_BRICK, Color(0.72, 0.45, 0.35), 1.0)   -- warm brick
    world:SetPaletteEntry(M.MAT_ROOF, Color(0.35, 0.37, 0.42), 2.5)    -- concrete slab
    world:SetPaletteEntry(M.MAT_TRIM, Color(0.55, 0.42, 0.28), 0.5)    -- wooden trim
    world:SetPaletteEntry(M.MAT_GROUND, Color(0.42, 0.44, 0.40), 100.0)
    -- Style 1 = shatters to dust: a punched window leaves a hole and nothing else.
    world:SetPaletteEntry(M.MAT_GLASS, Color(0.62, 0.78, 0.88), 0.3, 1)
end
M.HOUSE_ORIGIN = Vector3(8.0, 0.0, -4.0)
M.WALL_THICKNESS = 0.5

-- Creates the ground plane. Marked indestructible: damage applied by world position cannot tell
-- scenery from a target, so without this anything carrying an impact probe near itself digs a trench
-- along its own route. Four voxels thick, not one — a thin static floor can be punched through by a
-- heavy body moving fast, and the extra layers merge into the same single collision box anyway.
function M.CreateGround(world)
    local ground = world:CreateVolume(M.GROUND_VOXELS, M.GROUND_THICK, M.GROUND_VOXELS,
        M.GROUND_VOXEL, Vector3(-M.GROUND_HALF, -M.GROUND_THICK * M.GROUND_VOXEL, -M.GROUND_HALF),
        Quaternion())
    ground:GetGrid():FillBox(0, 0, 0, M.GROUND_VOXELS - 1, M.GROUND_THICK - 1,
        M.GROUND_VOXELS - 1, true)
    ground:GetGrid():PaintBox(0, 0, 0, 100000, 100000, 100000, M.MAT_GROUND)
    ground.material = world:GetPaletteMaterial()
    ground.destructible = false
    world:FinalizeVolume(ground)
    ground:RebuildGeometry()
    return ground
end

-- Metres-to-voxel-index conversion for one axis. lo is inclusive, hi exclusive, both in metres from
-- the house origin; returns an inclusive index pair. Rounding to nearest keeps 0.25-multiple inputs
-- honest at any voxel size that roughly divides them.
local function Span(lo, hi)
    return math.floor(lo / M.VOXEL + 0.5), math.floor(hi / M.VOXEL + 0.5) - 1
end

-- Creates the house and returns its volume. Caller owns it; pass it to world:RemoveVolume to rebuild.
--
-- Authored in metres so the voxel size is a free choice. The carve list is the same building the
-- samples have always had: door on -X, two windows per wall at eye height — the piers between the
-- windows are the structural weak points.
function M.CreateHouse(world)
    local sx, sy, sz = M.HOUSE_SIZE.x, M.HOUSE_SIZE.y, M.HOUSE_SIZE.z
    local t = M.WALL_THICKNESS

    local wx0, wx1 = Span(0.0, sx)
    local wy0, wy1 = Span(0.0, sy)
    local wz0, wz1 = Span(0.0, sz)

    local house = world:CreateVolume(wx1 + 1, wy1 + 1, wz1 + 1, M.VOXEL, M.HOUSE_ORIGIN,
        Quaternion())
    local g = house:GetGrid()

    local function Carve(x0, y0, z0, x1, y1, z1)
        local ax0, ax1 = Span(x0, x1)
        local ay0, ay1 = Span(y0, y1)
        local az0, az1 = Span(z0, z1)
        g:FillBox(ax0, ay0, az0, ax1, ay1, az1, false)
    end

    -- Solid block, then hollowed out. Walls on every side and the roof are one thickness; note there
    -- is no floor slab — the hollow starts at y = 0.
    g:FillBox(wx0, wy0, wz0, wx1, wy1, wz1, true)
    Carve(t, 0.0, t, sx - t, sy - t, sz - t)

    -- Door in the -X wall, 1.5 m wide and 3 m tall.
    Carve(0.0, 0.0, 3.25, t, 3.0, 4.75)

    -- Windows, 1.25 m square at eye height (2.25 to 3.5 m), two per wall.
    local wlo, whi = 2.25, 3.5
    Carve(0.0, wlo, 1.25, t, whi, 2.5)              -- -X wall
    Carve(0.0, wlo, 5.5, t, whi, 6.75)
    Carve(sx - t, wlo, 1.25, sx, whi, 2.5)          -- +X wall
    Carve(sx - t, wlo, 5.5, sx, whi, 6.75)
    Carve(1.5, wlo, 0.0, 2.75, whi, t)              -- -Z wall
    Carve(5.25, wlo, 0.0, 6.5, whi, t)
    Carve(1.5, wlo, sz - t, 2.75, whi, sz)          -- +Z wall
    Carve(5.25, wlo, sz - t, 6.5, whi, sz)

    -- Paint: brick walls, a concrete roof, wooden trim around the door. PaintBox is authoring
    -- order-sensitive — later coats overwrite earlier ones, like real painting.
    g:PaintBox(0, 0, 0, 10000, 10000, 10000, M.MAT_BRICK)
    local ry0 = select(1, Span(sy - t, sy))
    g:PaintBox(0, ry0, 0, 10000, 10000, 10000, M.MAT_ROOF)
    local dz0 = select(1, Span(2.95, 3.25))
    local dz1 = select(2, Span(4.75, 5.05))
    local dy1 = select(2, Span(2.9, 3.2))
    g:PaintBox(0, 0, dz0, select(2, Span(0, t)), dy1, dz1, M.MAT_TRIM)

    -- Glass panes: one voxel thick, centred in each window opening, painted after the wall
    -- coats so the paint passes cannot overwrite them.
    local function Pane(x0, y0, z0, x1, y1, z1)
        local ax0, ax1 = Span(x0, x1)
        local ay0, ay1 = Span(y0, y1)
        local az0, az1 = Span(z0, z1)
        g:FillBox(ax0, ay0, az0, ax1, ay1, az1, true)
        g:PaintBox(ax0, ay0, az0, ax1, ay1, az1, M.MAT_GLASS)
    end
    Pane(0.2, wlo, 1.25, 0.3, whi, 2.5)
    Pane(0.2, wlo, 5.5, 0.3, whi, 6.75)
    Pane(sx - 0.3, wlo, 1.25, sx - 0.2, whi, 2.5)
    Pane(sx - 0.3, wlo, 5.5, sx - 0.2, whi, 6.75)
    Pane(1.5, wlo, 0.2, 2.75, whi, 0.3)
    Pane(5.25, wlo, 0.2, 6.5, whi, 0.3)
    Pane(1.5, wlo, sz - 0.3, 2.75, whi, sz - 0.2)
    Pane(5.25, wlo, sz - 0.3, 6.5, whi, sz - 0.2)

    house.material = world:GetPaletteMaterial()
    world:FinalizeVolume(house)
    house:RebuildGeometry()
    return house
end

-- Zone and sun shared by both samples. The light is deliberately off-axis: with it square-on, two of
-- the three voxel face directions get identical lighting and the blocky geometry becomes hard to read.
function M.CreateEnvironment(scene)
    local zoneNode = scene:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(-2000.0, 2000.0)
    zone.ambientColor = Color(0.28, 0.30, 0.34)
    zone.fogColor = Color(0.52, 0.60, 0.70)
    zone.fogStart = 60.0
    zone.fogEnd = 180.0

    local lightNode = scene:CreateChild("Sun")
    lightNode.direction = Vector3(0.6, -1.0, 0.45)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.castShadows = true
    light.brightness = 1.1
end

return M
