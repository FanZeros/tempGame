--[[
================================================================================
  ThirdPersonCamera.lua - Third Person Camera Library
================================================================================

A flexible third-person camera system with:
- Multiple camera modes (normal, armed, aiming, or custom)
- Smooth transitions (distance, offset, FOV)
- Wall collision detection (prevents camera clipping)
- Yaw/pitch based camera orientation

Usage:
    require "urhox-libs.Camera.ThirdPersonCamera"

    -- Create camera
    local tpCamera = ThirdPersonCamera.Create(scene, {
        modes = {
            normal = { distance = 5.0, offset = Vector3(0, 1.7, 0), fov = 45.0 },
            armed = { distance = 4.0, offset = Vector3(0.6, 1.6, 0), fov = 45.0 },
            aiming = { distance = 2.0, offset = Vector3(0.4, 1.5, 0), fov = 32.0 },
        },
        transitionSpeed = 8.0,
    })

    -- Set viewport
    renderer:SetViewport(0, Viewport:new(scene, tpCamera:GetCamera()))

    -- Switch modes
    tpCamera:SetMode("armed")

    -- Update each frame (in PostUpdate)
    tpCamera:Update(timeStep, targetNode, yaw, pitch)

完整文档与脚手架（路径相对 ai-dev-kit 根）：
    engine-docs/recipes/camera.md          -- 模式设计、碰撞检测、与角色控制的接线
    templates/scaffold-3d-character.lua    -- 第三人称角色游戏完整示例

================================================================================
--]]

--------------------------------------------------------------------------------
-- Module Definition
--------------------------------------------------------------------------------

---@class ThirdPersonCamera
ThirdPersonCamera = {}

-- Default configuration
local DEFAULT_CONFIG = {
    modes = {
        normal = { distance = 5.0, offset = Vector3(0, 1.7, 0), fov = 45.0 },
    },
    transitionSpeed = 8.0,
    collisionMask = nil,  -- Will use global CollisionMaskCamera
    minDistance = 0.5,
    farClip = 300.0,
    nearClip = 0.1,
    -- Collision settings
    collisionPadding = 0.2,         -- Extra padding from collision point
    collisionRecoverySpeed = 4.0,   -- Speed for recovering from collision (slower than approach)
    collisionApproachSpeed = 100.0, -- Speed for approaching collision (faster to avoid clipping)
}

--------------------------------------------------------------------------------
-- ThirdPersonCameraInstance Class
--------------------------------------------------------------------------------

---@class ThirdPersonCameraInstance
---@field _scene Scene
---@field _node Node
---@field _camera Camera
---@field _modes table
---@field _currentMode string
---@field _transitionSpeed number
---@field _collisionMask number
---@field _minDistance number
---@field _currentDistance number        -- Target distance (from mode config)
---@field _currentOffset Vector3
---@field _currentFOV number
---@field _actualDistance number         -- Actual distance after collision (smoothed)
---@field _collisionPadding number
---@field _collisionRecoverySpeed number
---@field _collisionApproachSpeed number
local ThirdPersonCameraInstance = {}
ThirdPersonCameraInstance.__index = ThirdPersonCameraInstance

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Create a third-person camera
---@param scene Scene Scene object (used for raycast collision detection)
---@param config table|nil Configuration table
---@return ThirdPersonCameraInstance
function ThirdPersonCamera.Create(scene, config)
    local self = setmetatable({}, ThirdPersonCameraInstance)

    -- Merge configuration
    config = config or {}
    self._scene = scene
    self._modes = config.modes or DEFAULT_CONFIG.modes
    self._transitionSpeed = config.transitionSpeed or DEFAULT_CONFIG.transitionSpeed
    self._collisionMask = config.collisionMask  -- Can be nil, will check global
    self._minDistance = config.minDistance or DEFAULT_CONFIG.minDistance

    -- Current mode
    self._currentMode = config.initialMode or "normal"

    -- Collision settings
    self._collisionPadding = config.collisionPadding or DEFAULT_CONFIG.collisionPadding
    self._collisionRecoverySpeed = config.collisionRecoverySpeed or DEFAULT_CONFIG.collisionRecoverySpeed
    self._collisionApproachSpeed = config.collisionApproachSpeed or DEFAULT_CONFIG.collisionApproachSpeed

    -- Initialize interpolation state from initial mode
    local initialMode = self._modes[self._currentMode] or self._modes.normal or next(self._modes)
    if initialMode then
        self._currentDistance = initialMode.distance
        self._currentOffset = Vector3(initialMode.offset.x, initialMode.offset.y, initialMode.offset.z)
        self._currentFOV = initialMode.fov
    else
        self._currentDistance = 5.0
        self._currentOffset = Vector3(0, 1.7, 0)
        self._currentFOV = 45.0
    end

    -- Initialize actual distance (will be smoothed separately for collision)
    self._actualDistance = self._currentDistance

    -- Mode transition state (only interpolate during transitions, not every frame)
    self._isTransitioning = false

    -- Create camera node (detached from scene, like the original implementation)
    self._node = Node()
    self._camera = self._node:CreateComponent("Camera")
    self._camera.fov = self._currentFOV
    self._camera.farClip = config.farClip or DEFAULT_CONFIG.farClip
    self._camera.nearClip = config.nearClip or DEFAULT_CONFIG.nearClip

    print("[ThirdPersonCamera] Created with " .. self:_countModes() .. " modes, initial mode: " .. self._currentMode)

    return self
end

--- Set camera mode
---@param modeName string Mode name (e.g., "normal", "armed", "aiming")
function ThirdPersonCameraInstance:SetMode(modeName)
    if self._modes[modeName] then
        if self._currentMode ~= modeName then
            self._currentMode = modeName
            self._isTransitioning = true
        end
    else
        print("[ThirdPersonCamera] Warning: Mode '" .. tostring(modeName) .. "' not found")
    end
end

--- Get current mode name
---@return string
function ThirdPersonCameraInstance:GetMode()
    return self._currentMode
end

--- Update camera each frame
---@param timeStep number Time step (delta time)
---@param targetNode Node Target node to follow
---@param yaw number Horizontal rotation angle (degrees)
---@param pitch number Vertical rotation angle (degrees)
function ThirdPersonCameraInstance:Update(timeStep, targetNode, yaw, pitch)
    local targetConfig = self._modes[self._currentMode]
    if not targetConfig then return end

    -- Exponential decay smoothing for mode transitions
    local lerpFactor = 1.0 - math.exp(-self._transitionSpeed * timeStep)

    -- Interpolate camera parameters only during mode transitions
    if self._isTransitioning then
        self._currentDistance = Lerp(self._currentDistance, targetConfig.distance, lerpFactor)
        self._currentOffset = self._currentOffset:Lerp(targetConfig.offset, lerpFactor)
        self._currentFOV = Lerp(self._currentFOV, targetConfig.fov, lerpFactor)

        -- Snap to exact values when close enough to avoid floating point drift
        local SNAP_THRESHOLD = 0.001
        local distDiff = math.abs(self._currentDistance - targetConfig.distance)
        local offsetDiff = (self._currentOffset - targetConfig.offset):Length()
        local fovDiff = math.abs(self._currentFOV - targetConfig.fov)

        if distDiff < SNAP_THRESHOLD and offsetDiff < SNAP_THRESHOLD and fovDiff < SNAP_THRESHOLD then
            self._currentDistance = targetConfig.distance
            self._currentOffset = Vector3(targetConfig.offset.x, targetConfig.offset.y, targetConfig.offset.z)
            self._currentFOV = targetConfig.fov
            self._isTransitioning = false
        end
    end

    -- Apply FOV
    self._camera.fov = self._currentFOV

    -- Calculate camera orientation
    local rot = Quaternion(yaw, Vector3(0, 1, 0))
    local dir = rot * Quaternion(pitch, Vector3.RIGHT)

    -- Calculate aim point (target position + rotated offset)
    local aimPoint = targetNode.position + rot * self._currentOffset

    -- Ray direction (camera looks forward, so ray goes backward)
    local rayDir = dir * Vector3(0, 0, -1)

    -- Wall collision detection
    local targetDistance = self._currentDistance
    local physicsWorld = self._scene:GetComponent("PhysicsWorld")
    if physicsWorld then
        local collisionMask = self._collisionMask or CollisionMaskCamera
        local result = physicsWorld:RaycastSingle(Ray(aimPoint, rayDir), targetDistance, collisionMask)
        if result.body then
            targetDistance = Max(self._minDistance, result.distance - self._collisionPadding)
        end
    end

    -- Clamp target distance
    targetDistance = Clamp(targetDistance, self._minDistance, self._currentDistance)

    -- Asymmetric smoothing for collision distance:
    -- - Fast approach when getting closer (avoid clipping through walls)
    -- - Slow recovery when moving away (avoid jitter at collision boundaries)
    local distanceSpeed
    if targetDistance < self._actualDistance then
        -- Approaching obstacle: use fast speed
        distanceSpeed = self._collisionApproachSpeed
    else
        -- Recovering from obstacle: use slow speed
        distanceSpeed = self._collisionRecoverySpeed
    end
    local distanceLerpFactor = 1.0 - math.exp(-distanceSpeed * timeStep)
    self._actualDistance = Lerp(self._actualDistance, targetDistance, distanceLerpFactor)

    -- Apply position and rotation
    self._node.position = aimPoint + rayDir * self._actualDistance
    self._node.rotation = dir
end

--- Get camera node
---@return Node
function ThirdPersonCameraInstance:GetNode()
    return self._node
end

--- Get Camera component
---@return Camera
function ThirdPersonCameraInstance:GetCamera()
    return self._camera
end

--- Get current camera distance (actual, after collision)
---@return number
function ThirdPersonCameraInstance:GetCurrentDistance()
    return self._currentDistance
end

--- Get current FOV
---@return number
function ThirdPersonCameraInstance:GetCurrentFOV()
    return self._currentFOV
end

--- Add or update a camera mode
---@param modeName string Mode name
---@param modeConfig table Mode configuration { distance, offset, fov }
function ThirdPersonCameraInstance:SetModeConfig(modeName, modeConfig)
    self._modes[modeName] = modeConfig
end

--- Set transition speed
---@param speed number Transition speed (higher = faster)
function ThirdPersonCameraInstance:SetTransitionSpeed(speed)
    self._transitionSpeed = speed
end

--------------------------------------------------------------------------------
-- Internal Methods
--------------------------------------------------------------------------------

--- Count number of modes
---@return number
function ThirdPersonCameraInstance:_countModes()
    local count = 0
    for _ in pairs(self._modes) do
        count = count + 1
    end
    return count
end

return ThirdPersonCamera
