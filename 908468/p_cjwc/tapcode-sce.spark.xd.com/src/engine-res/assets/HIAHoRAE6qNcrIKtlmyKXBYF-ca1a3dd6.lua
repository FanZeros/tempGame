-- Teardown official-level vehicle assembly.
--
-- Converter writes a LuaScriptInstance of this type on the chassis VoxelVolume node,
-- plus a child marker tagged td_vehicle_spec whose Name holds:
--   td_vehicle|force|maxSpeed|steerDeg|grip|stiff|damp|skid| x,y,z,r,rest,steer,drive;...
--
-- VoxelVehicle MUST live on the same node as the chassis VoxelVolume (GetChassis()).
-- Wheels are visual VoxelVolumes (State=0, Collidable=false). We parent their hub
-- nodes under the chassis and pose them like VoxelTown:
--   * hub local XZ stays at the spec attach (no world-space snap)
--   * hub local Y = attachY - (rest - compression)
--   * spin a child at the visual AABB centre around chassis Z (the axle)
--   * steer yaws the hub around chassis Y
--
-- Do NOT set hub.worldPosition = contact - down * radius. Script Update runs
-- before the solver, so that contact is one frame stale: at speed the wheels
-- trail the body and clip into the shell (cullington cars, ~v*dt). Trucks hide
-- the same lag because their wells are bigger. See vehicle-system.md.

TdVoxelVehicle = ScriptObject()

local function ParseNumber(s, default)
    local n = tonumber(s)
    if n == nil then
        return default
    end
    return n
end

local function FindSpecNode(node)
    if node == nil then
        return nil
    end
    -- New format: marker tagged td_vehicle_spec, spec string in Name.
    -- GetChildrenWithTag returns a plain 1-based Lua table here, NOT a
    -- StringVector-style userdata: `#t` is the count and `t[1]` is the first hit.
    -- Calling t:Size() throws "attempt to call a nil value (method 'Size')",
    -- which aborted DelayedStart and left the vehicle unassembled (verified).
    local tagged = node:GetChildrenWithTag("td_vehicle_spec", true)
    if tagged ~= nil and #tagged > 0 then
        return tagged[1]
    end
    -- Legacy: child named TdVehicleSpec (spec was wrongly stuffed into Tags).
    local marker = node:GetChild("TdVehicleSpec", true)
    if marker ~= nil then
        return marker
    end
    for i = 0, node:GetNumChildren() - 1 do
        local ch = node:GetChild(i)
        if ch ~= nil then
            local name = ch.name or ""
            if name == "TdVehicleSpec" or string.sub(name, 1, 11) == "td_vehicle|" then
                return ch
            end
        end
    end
    return nil
end

local function ParseSpec(tags)
    if tags == nil or tags == "" then
        return nil
    end
    local parts = {}
    for token in string.gmatch(tags, "[^|]+") do
        parts[#parts + 1] = token
    end
    if #parts < 8 or parts[1] ~= "td_vehicle" then
        return nil
    end
    local spec = {
        force = ParseNumber(parts[2], 8000),
        maxSpeed = ParseNumber(parts[3], 0),
        steerDeg = ParseNumber(parts[4], 35),
        grip = ParseNumber(parts[5], 0.9),
        stiff = ParseNumber(parts[6], 30000),
        damp = ParseNumber(parts[7], 3500),
        skid = ParseNumber(parts[8], 0) > 0.5,
        wheels = {},
    }
    local wheelBlob = parts[9] or ""
    if wheelBlob ~= "" then
        for wtok in string.gmatch(wheelBlob, "[^;]+") do
            local f = {}
            for num in string.gmatch(wtok, "[^,]+") do
                f[#f + 1] = ParseNumber(num, 0)
            end
            if #f >= 7 then
                spec.wheels[#spec.wheels + 1] = {
                    attach = Vector3(f[1], f[2], f[3]),
                    radius = math.max(f[4], 0.08),
                    rest = math.max(f[5], 0.05),
                    steer = f[6],
                    drive = f[7] > 0.5,
                }
            end
        end
    end
    return spec
end

local function CollectWheelHubs(root, out)
    if root == nil then
        return
    end
    -- Converter stamps td_wheel_hub even when <wheel name="fl"> renamed the node.
    -- Name=="wheel" is the fallback for scenes converted before that tag existed.
    if root:HasTag("td_wheel_hub") or root.name == "wheel" then
        out[#out + 1] = root
    end
    for i = 0, root:GetNumChildren() - 1 do
        CollectWheelHubs(root:GetChild(i), out)
    end
end

local function ReparentKeepWorld(child, parent)
    if child == nil or parent == nil then
        return
    end
    local worldPos = child.worldPosition
    local worldRot = child.worldRotation
    child.parent = parent
    child.worldPosition = worldPos
    child.worldRotation = worldRot
end

-- Hub 对齐到底盘局部系(X 车头 / Y 上 / Z 轴),子节点保持世界位姿。
-- 这样后面转轮只要绕 hub 局部 Z,转向绕局部 Y,和 VoxelTown 同一套公式。
local function AlignHubToChassis(hub)
    if hub == nil then
        return
    end
    local saved = {}
    for i = 0, hub:GetNumChildren() - 1 do
        local ch = hub:GetChild(i)
        saved[#saved + 1] = { n = ch, p = ch.worldPosition, r = ch.worldRotation }
    end
    hub.rotation = Quaternion()
    for _, s in ipairs(saved) do
        s.n.worldPosition = s.p
        s.n.worldRotation = s.r
    end
end

local function CollectWheelVisuals(root, out)
    if root == nil then
        return
    end
    local tagged = root:GetChildrenWithTag("td_wheel_visual", true)
    if tagged ~= nil and #tagged > 0 then
        for i = 1, #tagged do
            out[#out + 1] = tagged[i]
        end
        return
    end
    if root:GetComponent("VoxelVolume") ~= nil then
        out[#out + 1] = root
        return
    end
    for i = 0, root:GetNumChildren() - 1 do
        CollectWheelVisuals(root:GetChild(i), out)
    end
end

-- 体素网格原点是 AABB 最小角,不是轮心。转轮必须绕视觉并集中心,否则
-- 轮子会绕最小角公转,看起来就是往后甩进车壳。
local function VisualsCenterWorld(visuals)
    local minx, miny, minz = 1e9, 1e9, 1e9
    local maxx, maxy, maxz = -1e9, -1e9, -1e9
    local any = false
    for _, vis in ipairs(visuals) do
        local vol = vis:GetComponent("VoxelVolume")
        local grid = vol and vol:GetGrid() or nil
        local vs = vol and vol.voxelSize or 0
        if grid ~= nil and vs ~= nil and vs > 0 then
            local dims = grid:GetDimensions()
            local sx, sy, sz = dims.x * vs, dims.y * vs, dims.z * vs
            for ix = 0, 1 do
                for iy = 0, 1 do
                    for iz = 0, 1 do
                        local w = vis.worldTransform * Vector3(ix * sx, iy * sy, iz * sz)
                        if w.x < minx then minx = w.x end
                        if w.y < miny then miny = w.y end
                        if w.z < minz then minz = w.z end
                        if w.x > maxx then maxx = w.x end
                        if w.y > maxy then maxy = w.y end
                        if w.z > maxz then maxz = w.z end
                        any = true
                    end
                end
            end
        else
            local p = vis.worldPosition
            if p.x < minx then minx = p.x end
            if p.y < miny then miny = p.y end
            if p.z < minz then minz = p.z end
            if p.x > maxx then maxx = p.x end
            if p.y > maxy then maxy = p.y end
            if p.z > maxz then maxz = p.z end
            any = true
        end
    end
    if not any then
        return nil
    end
    return Vector3((minx + maxx) * 0.5, (miny + maxy) * 0.5, (minz + maxz) * 0.5)
end

local function AttachSpinNode(hub)
    local visuals = {}
    CollectWheelVisuals(hub, visuals)
    local spin = hub:CreateChild("WheelSpin")
    spin.temporary = true
    spin.rotation = Quaternion()
    local movable = {}
    for _, vis in ipairs(visuals) do
        if vis ~= hub then
            movable[#movable + 1] = vis
        end
    end
    if #movable == 0 then
        spin.position = Vector3.ZERO
        return spin
    end
    local center = VisualsCenterWorld(movable)
    if center ~= nil then
        spin.worldPosition = center
    else
        spin.position = Vector3.ZERO
    end
    for _, vis in ipairs(movable) do
        ReparentKeepWorld(vis, spin)
    end
    return spin
end

function TdVoxelVehicle:Start()
    -- Scene load is still applying sibling VoxelVolume / physics adopt here.
    -- Do not CreateComponent or reparent until DelayedStart (first SceneUpdate).
    self.vehicle = nil
    self.hubs = {}
    self.ready = false
    self.steerInput = 0
end

function TdVoxelVehicle:DelayedStart()
    if self.ready then
        return
    end

    local node = self.node
    if node == nil then
        return
    end

    local specNode = FindSpecNode(node)
    local specRaw = nil
    if specNode ~= nil then
        specRaw = specNode.name
        if specRaw == nil or specRaw == "" or specRaw == "TdVehicleSpec" then
            specRaw = specNode.tags
        end
    end
    local spec = specRaw and ParseSpec(specRaw) or nil
    if spec == nil or #spec.wheels == 0 then
        -- Boat / nodrive prop: keep geometry, no suspension.
        return
    end

    -- Chassis VoxelVolume + world adopt must already have run (post ApplyAttributes).
    if node:GetComponent("VoxelVolume") == nil then
        return
    end

    -- Frame contract (converter guarantees since the canonical-chassis bake):
    --   * The chassis node's LOCAL frame is X = nose, Y = up, Z = side — exactly
    --     what VoxelVehicle::ApplyWheelForces derives its ray/drive/grip axes
    --     from. The converter re-bakes the voxel data (models/*__vf*.vox) so the
    --     node no longer carries the old Z-up axis-swap rotation.
    --   * Spec wheel anchors are authored in that same chassis-local frame,
    --     origin at the grid min corner (the node origin). Feed them to AddWheel
    --     verbatim — no swizzle, no re-basing.
    -- History: scenes converted BEFORE the bake had chassis local Y along the car
    -- length and Z up, and anchors in the vehicle-GROUP frame; suspension rays
    -- then shot horizontally and cars never moved (cullington, 2/4 grounded at
    -- zero ray distance). Re-convert such scenes instead of patching here.

    local vehicle = node:GetComponent("VoxelVehicle")
    if vehicle == nil then
        vehicle = node:CreateComponent("VoxelVehicle")
    end
    if vehicle == nil then
        return
    end
    vehicle:ClearWheels()
    vehicle.maxDriveForce = spec.force
    vehicle.maxSpeed = spec.maxSpeed
    vehicle.maxSteerAngle = spec.steerDeg
    vehicle.grip = spec.grip
    vehicle.skidSteer = spec.skid
    -- Runtime-created component skips scene-load ApplyAttributes; register with the world.
    vehicle:ApplyAttributes()

    -- 载具组在转换成功路径上打了 td_vehicle。从底盘往上走到该 tag,
    -- 不要靠 parent.name=="body"：<body name="chassis"> 转出来不叫 body,
    -- 会停在 body 节点上,而轮 hub 是它的兄弟,CollectWheelHubs 一个也收不到。
    local searchRoot = node
    local walk = node
    while walk ~= nil do
        if walk:HasTag("td_vehicle") then
            searchRoot = walk
            break
        end
        walk = walk.parent
    end
    if searchRoot == node then
        -- 旧转换产物可能没有组 tag:回退 vehicle/body/vox 启发式。
        local parent = node.parent
        if parent ~= nil and parent.name == "body" and parent.parent ~= nil then
            searchRoot = parent.parent
        elseif parent ~= nil then
            searchRoot = parent
        end
    end

    local hubs = {}
    CollectWheelHubs(searchRoot, hubs)
    if #hubs ~= #spec.wheels then
        print(string.format(
            "[TdVoxelVehicle] %s: found %d wheel hubs, spec has %d",
            node.name or "chassis", #hubs, #spec.wheels))
    end

    for i, w in ipairs(spec.wheels) do
        vehicle:AddWheel(w.attach, w.radius, w.rest, spec.stiff, spec.damp, false, w.drive)
        vehicle:SetWheelSteerFactor(i - 1, w.steer)
        local hub = hubs[i]
        if hub ~= nil then
            ReparentKeepWorld(hub, node)
            AlignHubToChassis(hub)
            local spin = AttachSpinNode(hub)
            self.hubs[#self.hubs + 1] = {
                node = hub,
                spinNode = spin,
                attachX = w.attach.x,
                attachY = w.attach.y,
                attachZ = w.attach.z,
                radius = w.radius,
                rest = w.rest,
                steer = w.steer,
                spin = 0.0,
            }
        end
    end

    self.vehicle = vehicle
    self.ready = true
end

function TdVoxelVehicle:Update(timeStep)
    if not self.ready or self.vehicle == nil then
        return
    end

    -- Optional: if this node (or an ancestor) has tag td_player_drive, read WASD.
    -- Official converted scenes stay parked unless a game script calls SetInput.
    local node = self.node
    local drive = false
    if node ~= nil then
        drive = node:HasTag("td_player_drive")
        if not drive and node.parent ~= nil then
            drive = node.parent:HasTag("td_player_drive")
        end
    end
    self.steerInput = 0
    if drive and input ~= nil then
        local throttle = 0
        local steer = 0
        local brake = 0
        if input:GetKeyDown(KEY_W) then
            throttle = throttle + 1
        end
        if input:GetKeyDown(KEY_S) then
            throttle = throttle - 1
        end
        if input:GetKeyDown(KEY_A) then
            steer = steer - 1
        end
        if input:GetKeyDown(KEY_D) then
            steer = steer + 1
        end
        if input:GetKeyDown(KEY_SPACE) then
            brake = 1
        end
        self.steerInput = steer
        self.vehicle:SetInput(throttle, steer, brake)
    end
end

-- Scene::Update 顺序: SceneUpdate → SceneSubsystemUpdate(VoxelPhysics
-- ApplyWheelForces + Jolt) → ScenePostUpdate。
-- Update 里只送 SetInput,必须赶在本帧求解之前;轮视觉放 PostUpdate,读的才是
-- 本帧 compression / steerAngle / forwardSpeed。不要用 FixedUpdate —— 那条
-- 挂的是 Bullet PhysicsWorld,体素载具不走它。
function TdVoxelVehicle:PostUpdate(timeStep)
    if not self.ready or self.vehicle == nil or self.node == nil then
        return
    end
    local speed = self.vehicle.forwardSpeed
    local spinWheels = not self.vehicle.skidSteer
    for i, hub in ipairs(self.hubs) do
        local hn = hub.node
        if hn ~= nil then
            local compression = self.vehicle:GetWheelCompression(i - 1)
            hn.position = Vector3(
                hub.attachX,
                hub.attachY - (hub.rest - compression),
                hub.attachZ)
            hn.rotation = Quaternion(
                self.vehicle:GetWheelSteerAngle(i - 1), Vector3(0.0, 1.0, 0.0))
            if spinWheels and hub.spinNode ~= nil and hub.radius > 1e-4 then
                hub.spin = (hub.spin + speed / hub.radius * timeStep * 57.2958) % 360.0
                hub.spinNode.rotation = Quaternion(0.0, 0.0, -hub.spin)
            end
        end
    end
end
