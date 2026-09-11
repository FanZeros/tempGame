-- Voxel physics benchmark: a deterministic five-phase workload over the district scene.
--
-- Every phase is frame-scheduled and every blast lands at fixed coordinates, and the engine's
-- damage noise is a coordinate hash, so two runs of this script produce the same destruction —
-- which is what makes numbers comparable across engine versions.
--
-- Phases
--   1 idle       static world, orbiting camera: render + broad-phase baseline
--   2 spikes     five isolated blasts, seconds apart: the cost of ONE damage event
--   3 sustained  a blast every half second walking across a building: steady-state demolition
--   4 saturation heavy blasting until the frozen-debris cap is the limiting factor
--   5 settle     hands off until everything freezes: how long the world takes to go quiet
--
-- Output: one BENCH CSV line per frame in the game log, plus BENCHMARK-DONE at the end. Parse with
-- tools or a grep; the fields are named in the BENCH-HEADER line.

local scenery = require "VoxelBenchScene"

local world
local buildings
local cameraNode
local frame = 0
local phase = 0
local statusText

-- os.clock() is the finest timer script can reach and resolves to about a millisecond on
-- Windows, which is enough for per-frame world:Update cost on a scene this size.
local function Now()
    return os.clock()
end

function Start()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    scenery.CreateEnvironment(scene_)

    world = scene_:CreateComponent("VoxelPhysicsWorld")
    -- The benchmark times Update() itself, so the automatic scene-update step must not run.
    world.updateEnabled = false
    world:SetMinFragmentVoxels(12)
    world:SetMaxFrozenFragments(300)
    world:SetSpallChunkVoxels(4)
    world:SetMaxSpallChunks(24)
    world:SetSpallSpeed(3.0)
    world:SetDamageNoise(0.35)

    buildings = scenery.CreateDistrict(world)

    cameraNode = scene_:CreateChild("Camera")
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 500.0
    renderer:SetViewport(0, Viewport:new(scene_, camera))

    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    statusText = ui.root:CreateChild("Text")
    statusText:SetFont(font, 14)
    statusText:SetPosition(12, 12)
    statusText.color = Color(1, 1, 1)

    local total = 0
    for i = 0, world.volumeCount - 1 do
        local v = world:GetVolume(i)
        if v ~= nil then total = total + v:GetGrid().solidCount end
    end
    print(string.format("BENCH-SCENE volumes=%d solidVoxels=%d", world.volumeCount, total))
    print("BENCH-HEADER frame,phase,dt_ms,update_ms,damage_ms,volumes,frozen,moving")

    SubscribeToEvent("Update", "HandleUpdate")
end

-- Blast helper: timed, so phase totals separate "the engine stepping" from "the damage call".
local damageMsThisFrame = 0.0
local function Blast(x, y, z, r)
    local t0 = Now()
    world:ApplyDamageAtWorldPoint(Vector3(x, y, z), r)
    damageMsThisFrame = damageMsThisFrame + (Now() - t0) * 1000.0
end

-- The workload schedule. All frame numbers assume roughly 60 fps but nothing breaks if the frame
-- rate differs — the schedule is by frame index, so the WORK is identical run to run.
local function RunWorkload()
    -- Phase 2: five isolated spikes on building 1, one every 180 frames.
    if frame == 700 or frame == 880 or frame == 1060 or frame == 1240 or frame == 1420 then
        local n = (frame - 700) / 180
        Blast(-20.0 + 1.0 + n * 1.5, 1.5, -18.0 + 0.25, 2.5)
    end

    -- Phase 3: sustained demolition of building 4 (the big block), a blast every 30 frames
    -- sweeping along its front wall and up.
    if frame >= 1600 and frame < 3400 and frame % 30 == 0 then
        local n = (frame - 1600) / 30
        local x = -18.0 + 0.5 + (n % 10) * 1.0
        local y = 1.0 + math.floor(n / 10) * 1.3
        Blast(x, y, 6.0 + 0.25, 2.2)
    end

    -- Phase 4: saturation — heavy blasts alternating across two more buildings plus the tower
    -- legs, driving debris to the cap.
    if frame >= 3400 and frame < 5200 and frame % 45 == 0 then
        local n = (frame - 3400) / 45
        if n % 3 == 0 then
            Blast(0.0 + 0.5 + (n / 3 % 8) * 1.4, 1.2 + (n % 2) * 2.0, 8.0 + 0.25, 2.4)
        elseif n % 3 == 1 then
            Blast(8.0 + 0.5 + (n % 6) * 1.3, 1.5, -18.0 + 0.25, 2.2)
        else
            Blast(24.0 + 0.4, 2.0 + (n % 4) * 0.8, -14.0 + 0.4, 1.2)
        end
    end
    -- Phase 5 (>= 5200): nothing — measure the road to silence.
end

local function PhaseOf(f)
    if f < 700 then return 1 end
    if f < 1600 then return 2 end
    if f < 3400 then return 3 end
    if f < 5200 then return 4 end
    return 5
end

function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()
    frame = frame + 1
    phase = PhaseOf(frame)
    damageMsThisFrame = 0.0

    RunWorkload()

    local t0 = Now()
    world:Update(timeStep, 1)
    local updateMs = (Now() - t0) * 1000.0

    local moving = 0
    for i = 0, world.volumeCount - 1 do
        local v = world:GetVolume(i)
        if v ~= nil and v:GetNode() ~= nil and not v:IsStatic() then moving = moving + 1 end
    end

    print(string.format("BENCH %d,%d,%.2f,%.2f,%.2f,%d,%d,%d",
        frame, phase, timeStep * 1000.0, updateMs, damageMsThisFrame,
        world.volumeCount, world:GetFrozenFragmentCount(), moving))

    -- Orbit slowly around the district so render load is realistic and stable.
    local angle = frame * 0.15
    cameraNode.position = Vector3(55.0 * math.cos(math.rad(angle)), 22.0,
        55.0 * math.sin(math.rad(angle)))
    cameraNode:LookAt(Vector3(0.0, 2.0, -5.0))

    statusText.text = string.format("bench phase %d  frame %d  vols %d  frozen %d  moving %d",
        phase, frame, world.volumeCount, world:GetFrozenFragmentCount(), moving)

    if frame >= 6400 or (phase == 5 and moving == 0 and frame > 5300) then
        print(string.format("BENCHMARK-DONE frame=%d", frame))
        engine:Exit()
    end
end
