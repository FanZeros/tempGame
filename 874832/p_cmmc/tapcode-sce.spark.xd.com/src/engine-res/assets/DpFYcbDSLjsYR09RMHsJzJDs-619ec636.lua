--[[
================================================================================
  GameHUD.lua - Game HUD Library (based on VirtualControls)
================================================================================

A high-level HUD library that provides common game UI components:
- Joystick: virtual joystick for movement
- Jump button: jump action
- Run button: sprint/run toggle
- Shooter system: arm, shoot, reload buttons + crosshair
- Touch look: swipe on empty screen area to rotate camera (mobile)

This library wraps VirtualControls and provides a simple unified API.

Usage:
    require "urhox-libs.UI.GameHUD"

    function Start()
        GameHUD.Initialize()
        GameHUD.SetControls(character_.controls)

        -- Minimal (joystick only, e.g. top-down shooter, strategy)
        GameHUD.Create()

        -- Platformer game (joystick + jump)
        GameHUD.Create({ enableJump = true })

        -- 3D character game (joystick + jump + run + touch look)
        GameHUD.Create({ enableJump = true, enableRun = true })
        GameHUD.EnableTouchLook({ camera = cameraNode })

        -- TPS shooter game (full controls)
        GameHUD.Create({
            enableJump = true,
            enableRun = true,
            enableShooter = true,
            onArm = function(isArmed) ... end,
            onShoot = function() ... end,
            onReload = function() ... end,
            onAimChange = function(isAiming) ... end,
        })
        GameHUD.EnableTouchLook({ camera = cameraNode })

        -- First-person game with custom yaw/pitch (e.g. Minecraft)
        GameHUD.EnableTouchLook({
            camera = cameraNode,
            onLook = function(deltaYaw, deltaPitch)
                playerYaw_ = playerYaw_ + deltaYaw
                playerPitch_ = Clamp(playerPitch_ + deltaPitch, -89, 89)
            end
        })
    end

    -- Switch character
    function SwitchCharacter(newCharacter)
        character_ = newCharacter
        GameHUD.SetControls(character_.controls)
    end

Configuration options (GameHUD.Create):
    enableJump      (bool)     Enable jump button (default: false)
    enableRun       (bool)     Enable run button (default: false)
    enableShooter   (bool)     Enable shooter system (default: false)
    onJump          (function) Jump callback
    onRunChange     (function) Run state change callback (isRunning)
    onArm           (function) Arm state change callback (isArmed)
    onShoot         (function) Shoot callback
    onReload        (function) Reload callback
    onAimChange     (function) Aim state change callback (isAiming)

IMPORTANT - Joystick Input Guidelines:
================================================================================
The joystick (hud.joystick) provides UNIFIED INPUT for both PC and mobile:
  - PC: Automatically responds to WASD keys via keyBinding="WASD"
  - Mobile: Responds to touch on virtual joystick

⚠️ DO NOT mix keyboard detection with joystick values! Choose ONE approach:
  ✅ RECOMMENDED: Only read joystick.x and joystick.y
  ❌ WRONG: Also use input:GetKeyDown(KEY_W/A/S/D) - causes double input!

Joystick Axis Convention (Screen Coordinate System):
  joystick.x: Left/Right  → x < 0 = Left,  x > 0 = Right
  joystick.y: Up/Down     → y < 0 = Up,    y > 0 = Down  (screen coords!)

For 3D games (where forward = Z+), you need to INVERT the Y axis:
  moveDir.x = joystick.x           -- Left/Right direct mapping
  moveDir.z = -joystick.y          -- Up(y<0) → Forward(z>0), Down(y>0) → Back(z<0)

Example (correct 3D first-person movement):
    if joystick_ then
        local deadZone = 0.1
        if math.abs(joystick_.x) > deadZone then
            moveDir.x = joystick_.x
        end
        if math.abs(joystick_.y) > deadZone then
            moveDir.z = -joystick_.y  -- INVERT Y for 3D forward/back!
        end
    end
================================================================================

Configuration options (GameHUD.EnableTouchLook):
    camera          (Node)     Camera node (required, for FOV-based sensitivity)
    sensitivity     (number)   Touch sensitivity (default: 2.0)
    invertY         (bool)     Invert Y axis (default: false)
    onLook          (function) Callback (deltaYaw, deltaPitch), optional

================================================================================
--]]

require "urhox-libs.UI.VirtualControls"
local InputManager = require("urhox-libs.Platform.InputManager")

-- Default touch sensitivity for camera look
local TOUCH_SENSITIVITY = 2.0

--------------------------------------------------------------------------------
-- Module Definition
--------------------------------------------------------------------------------

---@class GameHUD
GameHUD = {}

-- Internal state
local _initialized = false
local _controls = nil
local _nvgContext = nil
local _hudNode = nil

-- HUD components
local _joystick = nil
local _jumpButton = nil
local _runButton = nil
local _crouchButton = nil
local _armButton = nil
local _reloadButton = nil
local _shootButton = nil

-- Shooter state
local _isArmed = false
local _isAiming = false
local _wasAiming = false  -- For detecting aim state change
local _shooterEnabled = false

-- Touch look state (now uses VirtualControls.CreateTouchLookArea internally)
local _touchLookArea = nil  -- TouchLookArea instance
local _touchLookCamera = nil
local _touchLookSensitivity = 2.0
local _touchLookInvertY = false

-- Callbacks
local _callbacks = {
    onJump = nil,
    onRunChange = nil,
    onCrouch = nil,
    onArm = nil,
    onShoot = nil,
    onReload = nil,
    onAimChange = nil,
    onLook = nil,  -- Touch look callback (deltaYaw, deltaPitch)
    onTap = nil,   -- Touch tap callback (for Minecraft-style attack)
}

-- Crosshair config
local _crosshairConfig = {
    size = 12,
    thickness = 2,
    gap = 4,
    dotRadius = 2,
    normalColor = { 255, 255, 255, 200 },
    aimingColor = { 255, 50, 50, 255 },
    aimingScale = 0.7,
}

-- Layout config (design resolution 1920x1080)
local _layoutConfig = {
    -- Joystick (bottom-left)
    joystick = {
        position = Vector2(260, -260),
        alignment = {HA_LEFT, VA_BOTTOM},
        baseRadius = 150,
        knobRadius = 60,
        moveRadius = 110,
        deadZone = 0.15,
        opacity = 0.5,
        activeOpacity = 0.85,
        isPressCenter = true,
        pressRegionRadius = 250,
        alwaysShow = true,
    },
    -- Button common settings
    buttonRadius = 60,
    buttonPosOffset = 150,
    buttonSpacing = 150,
    buttonRowSpacing = 150,
}

--------------------------------------------------------------------------------
-- Internal Functions
--------------------------------------------------------------------------------

--- Check if on mobile platform
local function _isMobile()
    local platform = GetNativePlatform()
    return (platform == "Android" or platform == "iOS" or platform == "HarmonyOS")
end

--- Draw crosshair using NanoVG
---@param ctx NVGContextWrapper NanoVG context
---@param cx number Center X
---@param cy number Center Y
local function _drawCrosshair(ctx, cx, cy)
    local cfg = _crosshairConfig
    local color = _isAiming and cfg.aimingColor or cfg.normalColor
    local scale = _isAiming and cfg.aimingScale or 1.0

    local size = cfg.size * scale
    local gap = cfg.gap * scale
    local thickness = cfg.thickness

    nvgStrokeColor(ctx, nvgRGBA(color[1], color[2], color[3], color[4]))
    nvgStrokeWidth(ctx, thickness)
    nvgFillColor(ctx, nvgRGBA(color[1], color[2], color[3], color[4]))

    nvgBeginPath(ctx)

    -- Top line
    nvgMoveTo(ctx, cx, cy - gap - size)
    nvgLineTo(ctx, cx, cy - gap)

    -- Bottom line
    nvgMoveTo(ctx, cx, cy + gap)
    nvgLineTo(ctx, cx, cy + gap + size)

    -- Left line
    nvgMoveTo(ctx, cx - gap - size, cy)
    nvgLineTo(ctx, cx - gap, cy)

    -- Right line
    nvgMoveTo(ctx, cx + gap, cy)
    nvgLineTo(ctx, cx + gap + size, cy)

    nvgStroke(ctx)

    -- Center dot
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, cfg.dotRadius * scale)
    nvgFill(ctx)
end

--- Handle crosshair render event (global function for event subscription)
function _GameHUD_HandleCrosshairRender(eventType, eventData)
    if not _isArmed or _nvgContext == nil then
        return
    end

    local gfx = GetGraphics()
    local width = gfx:GetWidth()
    local height = gfx:GetHeight()

    nvgBeginFrame(_nvgContext, width, height, 1.0)
    _drawCrosshair(_nvgContext, width / 2, height / 2)
    nvgEndFrame(_nvgContext)
end

--- Create joystick
local function _createJoystick()
    local isMobile = _isMobile()
    local joystickConfig = {}
    for k, v in pairs(_layoutConfig.joystick) do
        joystickConfig[k] = v
    end
    joystickConfig.keyBinding = isMobile and nil or "WASD"
    joystickConfig.showKeyHints = not isMobile

    _joystick = VirtualControls.CreateJoystick(joystickConfig)
    return _joystick
end

--- Create jump button
local function _createJumpButton()
    local layout = _layoutConfig
    _jumpButton = VirtualControls.CreateButton({
        position = Vector2(-layout.buttonPosOffset, -layout.buttonPosOffset),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = layout.buttonRadius,
        label = "Jump",
        keyBinding = "SPACE",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {100, 200, 255},
        pressedColor = {150, 230, 255},
        on_press = function()
            if _callbacks.onJump then
                _callbacks.onJump()
            end
        end,
    })
    return _jumpButton
end

--- Create run button
local function _createRunButton()
    local layout = _layoutConfig
    _runButton = VirtualControls.CreateButton({
        position = Vector2(-layout.buttonPosOffset - layout.buttonSpacing, -layout.buttonPosOffset),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = layout.buttonRadius,
        label = "Run",
        keyBinding = "SHIFT",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {255, 180, 100},
        pressedColor = {255, 220, 150},
        on_press = function()
            if _callbacks.onRunChange then
                _callbacks.onRunChange(true)
            end
        end,
        on_release = function()
            if _callbacks.onRunChange then
                _callbacks.onRunChange(false)
            end
        end,
    })
    return _runButton
end

--- Create crouch button
local function _createCrouchButton()
    local layout = _layoutConfig
    _crouchButton = VirtualControls.CreateButton({
        position = Vector2(-layout.buttonPosOffset - layout.buttonSpacing, -layout.buttonPosOffset - layout.buttonRowSpacing),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = layout.buttonRadius,
        label = "Crouch",
        keyBinding = "C",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {200, 150, 100},
        pressedColor = {240, 190, 140},
        on_press = function()
            if _callbacks.onCrouch then
                _callbacks.onCrouch(true)
            end
        end,
    })
    return _crouchButton
end

--- Create shooter buttons (arm, shoot, reload)
local function _createShooterButtons()
    local layout = _layoutConfig
    local btnRadius = layout.buttonRadius
    local btnPosOffset = layout.buttonPosOffset
    local btnSpacing = layout.buttonSpacing
    local btnRowSpacing = layout.buttonRowSpacing

    -- Shoot button (left of run button)
    _shootButton = VirtualControls.CreateButton({
        position = Vector2(-btnPosOffset - btnSpacing * 2, -btnPosOffset),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = btnRadius,
        label = "Fire",
        mouseBinding = "LMB",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {255, 100, 100},
        pressedColor = {255, 150, 150},
        on_press = function()
            if _isArmed and _callbacks.onShoot then
                _callbacks.onShoot()
            end
        end,
    })

    -- Arm button (above jump)
    _armButton = VirtualControls.CreateButton({
        position = Vector2(-btnPosOffset, -btnPosOffset - btnRowSpacing),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = btnRadius,
        label = "Arm",
        keyBinding = "Q",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {180, 180, 180},
        pressedColor = {220, 220, 220},
        on_press = function()
            _isArmed = not _isArmed

            -- Reset aim state when disarming
            if not _isArmed then
                _isAiming = false
                _wasAiming = false
            end

            if _callbacks.onArm then
                _callbacks.onArm(_isArmed)
            end
        end,
    })

    -- Reload button (above shoot)
    _reloadButton = VirtualControls.CreateButton({
        position = Vector2(-btnPosOffset - btnSpacing * 2, -btnPosOffset - btnRowSpacing),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = btnRadius,
        label = "Reload",
        keyBinding = "R",
        opacity = 0.5,
        activeOpacity = 0.9,
        alwaysShow = true,
        color = {100, 255, 100},
        pressedColor = {150, 255, 150},
        on_press = function()
            if _isArmed and _callbacks.onReload then
                _callbacks.onReload()
            end
        end,
    })

    return {
        armButton = _armButton,
        shootButton = _shootButton,
        reloadButton = _reloadButton,
    }
end

--------------------------------------------------------------------------------
-- ScriptObject for Update event
--------------------------------------------------------------------------------

_GameHUDUpdater = ScriptObject()

function _GameHUDUpdater:Start()
    -- Subscribe to Update event on this object (not global)
    self:SubscribeToEvent("Update", "_GameHUDUpdater:HandleUpdate")
end

function _GameHUDUpdater:HandleUpdate(eventType, eventData)
    -- Button controls (require _controls)
    if _controls then
        -- Set CTRL_JUMP (both true and false)
        if _jumpButton then
            _controls:Set(CTRL_JUMP, _jumpButton.isPressed)
        end

        -- Set CTRL_RUN (both true and false)
        if _runButton then
            _controls:Set(CTRL_RUN, _runButton.isPressed)
        end
    end

    -- Detect RMB aim state change (only when armed and shooter enabled)
    if _shooterEnabled and _isArmed then
        local currentAiming = input:GetMouseButtonDown(MOUSEB_RIGHT)
        if currentAiming ~= _wasAiming then
            _isAiming = currentAiming
            _wasAiming = currentAiming
            if _callbacks.onAimChange then
                _callbacks.onAimChange(_isAiming)
            end
        end
    else
        if _isAiming then
            _isAiming = false
            _wasAiming = false
            if _callbacks.onAimChange then
                _callbacks.onAimChange(false)
            end
        end
    end

    -- Touch look control is now handled by VirtualControls.TouchLookArea
    -- (created in GameHUD.EnableTouchLook, automatically processed by VirtualControls.Update)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Initialize GameHUD
---@return boolean success
function GameHUD.Initialize()
    if _initialized then
        return true
    end

    -- Initialize VirtualControls
    VirtualControls.Initialize()

    -- Create detached node for ScriptObject (not attached to any scene)
    _hudNode = Node()
    _hudNode:CreateScriptObject("_GameHUDUpdater")

    -- Create NanoVG context for crosshair
    _nvgContext = nvgCreate(1)
    if _nvgContext == nil then
        print("WARNING: GameHUD - Failed to create NanoVG context for crosshair")
    else
        -- Subscribe crosshair render event to nvgContext (object-based, not global)
        SubscribeToEvent(_nvgContext, "NanoVGRender", "_GameHUD_HandleCrosshairRender")
    end

    _initialized = true
    print("[GameHUD] Initialized")
    return true
end

--- Set controls target (supports character switching)
---@param controls userdata Urho3D Controls object
function GameHUD.SetControls(controls)
    _controls = controls
    VirtualControls.SetControls(controls)
end

--- Create game HUD with unified configuration
---@param config table|nil Configuration options:
---  - enableJump (bool): Enable jump button (default: false)
---  - enableRun (bool): Enable run button (default: false)
---  - enableShooter (bool): Enable shooter system (default: false)
---  - onJump (function): Jump callback
---  - onRunChange (function): Run state change callback (isRunning: bool)
---  - onArm (function): Arm state change callback (isArmed: bool)
---  - onShoot (function): Shoot callback
---  - onReload (function): Reload callback
---  - onAimChange (function): Aim state change callback (isAiming: bool)
---@return table HUD components { joystick, jumpButton, runButton, armButton, shootButton, reloadButton }
function GameHUD.Create(config)
    config = config or {}

    -- Store callbacks
    _callbacks.onJump = config.onJump
    _callbacks.onRunChange = config.onRunChange
    _callbacks.onCrouch = config.onCrouch
    _callbacks.onArm = config.onArm
    _callbacks.onShoot = config.onShoot
    _callbacks.onReload = config.onReload
    _callbacks.onAimChange = config.onAimChange

    -- Parse options (with defaults)
    -- All buttons are disabled by default, only joystick is always created
    local enableJump = config.enableJump == true
    local enableRun = config.enableRun == true
    local enableCrouch = config.enableCrouch == true
    local enableShooter = config.enableShooter == true
    _shooterEnabled = enableShooter

    -- Always create joystick (the only required component)
    _createJoystick()

    -- Optionally create jump button
    if enableJump then
        _createJumpButton()
    end

    -- Optionally create run button
    if enableRun then
        _createRunButton()
    end

    -- Optionally create crouch button
    if enableCrouch then
        _createCrouchButton()
    end

    -- Optionally create shooter buttons
    if enableShooter then
        _createShooterButtons()
    end

    return {
        joystick = _joystick,
        jumpButton = _jumpButton,
        runButton = _runButton,
        crouchButton = _crouchButton,
        armButton = _armButton,
        shootButton = _shootButton,
        reloadButton = _reloadButton,
    }
end

--- Set aiming state (controls crosshair style)
---@param isAiming boolean
function GameHUD.SetAiming(isAiming)
    _isAiming = isAiming
end

--- Get current armed state
---@return boolean
function GameHUD.IsArmed()
    return _isArmed
end

--- Get current aiming state
---@return boolean
function GameHUD.IsAiming()
    return _isAiming
end

--- Set armed state programmatically
---@param isArmed boolean
function GameHUD.SetArmed(isArmed)
    if _isArmed ~= isArmed then
        _isArmed = isArmed

        if not _isArmed then
            _isAiming = false
            _wasAiming = false
        end

        if _callbacks.onArm then
            _callbacks.onArm(_isArmed)
        end
    end
end

--- Configure crosshair appearance
---@param config table Crosshair configuration
function GameHUD.SetCrosshairConfig(config)
    for k, v in pairs(config) do
        _crosshairConfig[k] = v
    end
end

--- Check if a touch is occupied by virtual controls
---@param touchId number Touch ID
---@return boolean
function GameHUD.IsTouchOccupied(touchId)
    return VirtualControls.IsTouchOccupied(touchId)
end

--------------------------------------------------------------------------------
-- Touch Look Control API
--------------------------------------------------------------------------------

--- Enable touch look control (for rotating camera by swiping on empty screen area)
--- This is automatically enabled on mobile platforms when a camera is set.
--- Internally uses VirtualControls.CreateTouchLookArea for unified touch handling.
---
--- Usage examples:
---   -- Method 1: Use with controls (recommended for character games)
---   GameHUD.SetControls(character_.controls)
---   GameHUD.EnableTouchLook({ camera = cameraNode })
---
---   -- Method 2: Use with callback (for first-person or custom camera)
---   GameHUD.EnableTouchLook({
---       camera = cameraNode,
---       onLook = function(deltaYaw, deltaPitch)
---           playerYaw_ = playerYaw_ + deltaYaw
---           playerPitch_ = Clamp(playerPitch_ + deltaPitch, -89, 89)
---       end
---   })
---
---   -- Method 3: With tap callback (for Minecraft-style games)
---   GameHUD.EnableTouchLook({
---       camera = cameraNode,
---       onLook = function(deltaYaw, deltaPitch) ... end,
---       onTap = function()
---           blockInteraction_:onLeftClick()  -- Attack/interact
---       end
---   })
---
---@param config table Configuration options:
---  - camera (Node): Camera node (required, used to get FOV for sensitivity scaling)
---  - sensitivity (number): Touch sensitivity (default: TOUCH_SENSITIVITY or 2.0)
---  - invertY (bool): Invert Y axis (default: false)
---  - onLook (function): Optional callback (deltaYaw, deltaPitch), if not provided uses controls.yaw/pitch
---  - onTap (function): Optional callback for short tap (e.g., attack in Minecraft-style games)
---  - regionPreset (string): "full_screen" | "right_half" | "left_half" (default: "full_screen")
function GameHUD.EnableTouchLook(config)
    config = config or {}

    if not config.camera then
        print("WARNING: GameHUD.EnableTouchLook - camera is required")
        return
    end

    -- Store config for later use
    _touchLookCamera = config.camera
    _touchLookSensitivity = config.sensitivity or TOUCH_SENSITIVITY or 2.0
    _touchLookInvertY = config.invertY == true
    _callbacks.onLook = config.onLook
    _callbacks.onTap = config.onTap

    -- Create TouchLookArea using VirtualControls
    -- This integrates with VirtualControls' touch priority system
    local camera = _touchLookCamera:GetComponent("Camera")
    local fov = camera and camera.fov or 45.0

    _touchLookArea = VirtualControls.CreateTouchLookArea({
        regionPreset = config.regionPreset or "full_screen",
        sensitivity = _touchLookSensitivity * fov / 1080,  -- Normalize sensitivity with FOV
        invertY = _touchLookInvertY,
        on_look = function(deltaYaw, deltaPitch)
            -- Apply via callback or controls
            if _callbacks.onLook then
                _callbacks.onLook(deltaYaw, deltaPitch)
            elseif _controls then
                _controls.yaw = _controls.yaw + deltaYaw
                _controls.pitch = _controls.pitch + deltaPitch
            end
        end,
        on_tap = _callbacks.onTap,  -- Pass through tap callback (nil is fine)
    })

    print("[GameHUD] Touch look enabled (sensitivity: " .. _touchLookSensitivity .. ", tap: " .. tostring(_callbacks.onTap ~= nil) .. ")")
end

--- Disable touch look control
function GameHUD.DisableTouchLook()
    if _touchLookArea then
        -- Remove from VirtualControls (will be recreated on next EnableTouchLook)
        VirtualControls.RemoveTouchLookArea(_touchLookArea)
        _touchLookArea = nil
    end
    _touchLookCamera = nil
    _callbacks.onLook = nil
    _callbacks.onTap = nil
    print("[GameHUD] Touch look disabled")
end

--- Check if touch look is enabled
---@return boolean
function GameHUD.IsTouchLookEnabled()
    return _touchLookArea ~= nil
end

--- Set touch look sensitivity
---@param sensitivity number
function GameHUD.SetTouchLookSensitivity(sensitivity)
    _touchLookSensitivity = sensitivity
    if _touchLookArea and _touchLookCamera then
        local camera = _touchLookCamera:GetComponent("Camera")
        local fov = camera and camera.fov or 45.0
        _touchLookArea.sensitivity = sensitivity * fov / 1080
    end
end

--- Set touch look Y axis inversion
---@param invert boolean
function GameHUD.SetTouchLookInvertY(invert)
    _touchLookInvertY = invert
    if _touchLookArea then
        _touchLookArea.invertY = invert
    end
end

--- Shutdown GameHUD
function GameHUD.Shutdown()
    VirtualControls.Clear()

    if _nvgContext then
        nvgDelete(_nvgContext)
        _nvgContext = nil
    end

    _joystick = nil
    _jumpButton = nil
    _runButton = nil
    _crouchButton = nil
    _armButton = nil
    _reloadButton = nil
    _shootButton = nil

    _controls = nil
    _isArmed = false
    _isAiming = false
    _wasAiming = false
    _shooterEnabled = false

    -- Reset touch look state (TouchLookArea is cleared by VirtualControls.Clear above)
    _touchLookArea = nil
    _touchLookCamera = nil
    _touchLookSensitivity = 2.0
    _touchLookInvertY = false

    _callbacks = {}

    _initialized = false
end


return GameHUD
