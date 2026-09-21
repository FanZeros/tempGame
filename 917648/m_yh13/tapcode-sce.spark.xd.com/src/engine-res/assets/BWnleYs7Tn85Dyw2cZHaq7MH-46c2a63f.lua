-- EditorDebug.lua
-- Entry point script for editor debugging mode
-- This script loads the scene saved by UrhoXEditor when clicking the Play button
--
-- Note: User resource directories and UUID mappings are loaded by C++ layer
-- (UrhoXRuntime::SetupEditorDebugMode) before this script runs.
--
-- Reads scene path from EditorDebug/debug_config.json:
-- {
--     "scenePath": "path/to/scene.xml"
-- }

require "LuaScripts/Utilities/Sample"

-- Configuration from debug_config.json
local configPath_ = nil
local scenePath_ = nil

function Start()
    -- Load debug configuration (scene path)
    LoadDebugConfig()

    -- Execute the common startup for samples
    SampleStart()

    -- Load scene from file or create empty scene
    if scenePath_ and scenePath_ ~= "" then
        LoadSceneFromFile(scenePath_)
    else
        CreateEmptyScene()
        log:Write(LOG_WARNING, "[EditorDebug] No scene path in config, created empty scene")
    end

    -- Setup viewport
    SetupViewport()

    -- Set the mouse mode (free cursor for debugging)
    SampleInitMouseMode(MM_FREE)

    -- Subscribe to events
    SubscribeToEvents()

    log:Write(LOG_INFO, "[EditorDebug] Runtime started successfully")
end

function Stop()
    log:Write(LOG_INFO, "[EditorDebug] Runtime stopped")
end

function LoadDebugConfig()
    -- Config file is in EditorDebug directory relative to executable
    local programDir = fileSystem:GetProgramDir()
    configPath_ = programDir .. "EditorDebug/debug_config.json"

    log:Write(LOG_INFO, "[EditorDebug] Loading config from: " .. configPath_)

    -- Read and parse JSON config
    local configFile = cache:GetResource("JSONFile", configPath_)
    if configFile == nil then
        -- Try loading directly from file system
        local file = File(configPath_, FILE_READ)
        if file:IsOpen() then
            configFile = JSONFile()
            if not configFile:Load(file) then
                log:Write(LOG_ERROR, "[EditorDebug] Failed to parse config file: " .. configPath_)
                file:Close()
                return
            end
            file:Close()
        else
            log:Write(LOG_ERROR, "[EditorDebug] Config file not found: " .. configPath_)
            return
        end
    end

    local root = configFile:GetRoot()

    -- Get scene path
    if root:Contains("scenePath") then
        scenePath_ = root:Get("scenePath"):GetString()
        log:Write(LOG_INFO, "[EditorDebug] Scene path: " .. scenePath_)
    end
end

function LoadSceneFromFile(path)
    scene_ = Scene()

    -- Load scene from XML file
    local file = File(path, FILE_READ)
    if file:IsOpen() then
        if scene_:LoadXML(file) then
            log:Write(LOG_INFO, "[EditorDebug] Loaded scene from: " .. path)
        else
            log:Write(LOG_ERROR, "[EditorDebug] Failed to parse scene: " .. path)
            CreateEmptyScene()
        end
        file:Close()
    else
        log:Write(LOG_ERROR, "[EditorDebug] Failed to open scene file: " .. path)
        CreateEmptyScene()
    end

    -- Find or create camera
    SetupCamera()
end

function CreateEmptyScene()
    scene_ = Scene()

    -- Create essential components
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- Create a Zone for ambient lighting
    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(-1000.0, 1000.0)
    zone.ambientColor = Color(0.15, 0.15, 0.15)
    zone.fogColor = Color(0.5, 0.5, 0.7)
    zone.fogStart = 100.0
    zone.fogEnd = 300.0

    -- Create a directional light
    local lightNode = scene_:CreateChild("DirectionalLight")
    lightNode.direction = Vector3(0.6, -1.0, 0.8)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL

    -- Setup camera
    SetupCamera()
end

function SetupCamera()
    -- Try to find existing camera in scene
    cameraNode = scene_:GetChild("Camera", true)

    if cameraNode == nil then
        -- Create new camera
        cameraNode = scene_:CreateChild("Camera")
        cameraNode.position = Vector3(0.0, 5.0, -15.0)
        cameraNode:LookAt(Vector3(0.0, 0.0, 0.0))
        log:Write(LOG_INFO, "[EditorDebug] Created new camera")
    else
        log:Write(LOG_INFO, "[EditorDebug] Using existing camera from scene")
    end

    local camera = cameraNode:GetComponent("Camera")
    if camera == nil then
        camera = cameraNode:CreateComponent("Camera")
    end
    camera.farClip = 500.0

    -- Initialize yaw and pitch from camera rotation
    local rotation = cameraNode.rotation
    yaw = rotation.yaw
    pitch = rotation.pitch
end

function SetupViewport()
    local camera = cameraNode:GetComponent("Camera")
    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("PostRenderUpdate", "HandlePostRenderUpdate")
end

function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()

    -- Camera movement
    MoveCamera(timeStep)
end

function MoveCamera(timeStep)
    -- Movement speed
    local MOVE_SPEED = 20.0
    local MOUSE_SENSITIVITY = 0.1

    -- Speed boost with Shift
    if input:GetKeyDown(KEY_SHIFT) then
        MOVE_SPEED = 60.0
    end

    -- Mouse look (right mouse button)
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local mouseMove = input.mouseMove
        yaw = yaw + MOUSE_SENSITIVITY * mouseMove.x
        pitch = pitch + MOUSE_SENSITIVITY * mouseMove.y
        pitch = Clamp(pitch, -90.0, 90.0)
        cameraNode.rotation = Quaternion(pitch, yaw, 0.0)
    end

    -- Keyboard movement (WASD)
    if input:GetKeyDown(KEY_W) then
        cameraNode:Translate(Vector3(0.0, 0.0, 1.0) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_S) then
        cameraNode:Translate(Vector3(0.0, 0.0, -1.0) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_A) then
        cameraNode:Translate(Vector3(-1.0, 0.0, 0.0) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_D) then
        cameraNode:Translate(Vector3(1.0, 0.0, 0.0) * MOVE_SPEED * timeStep)
    end

    -- Vertical movement (Q/E)
    if input:GetKeyDown(KEY_Q) then
        cameraNode:Translate(Vector3(0.0, -1.0, 0.0) * MOVE_SPEED * timeStep, TS_WORLD)
    end
    if input:GetKeyDown(KEY_E) then
        cameraNode:Translate(Vector3(0.0, 1.0, 0.0) * MOVE_SPEED * timeStep, TS_WORLD)
    end
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- Close on ESC
    if key == KEY_ESCAPE then
        engine:Exit()
    end

    -- Toggle debug geometry on F1
    if key == KEY_F1 then
        drawDebug = not drawDebug
    end

    -- Reload scene on F5
    if key == KEY_F5 then
        if scenePath_ and scenePath_ ~= "" then
            log:Write(LOG_INFO, "[EditorDebug] Reloading scene...")
            LoadSceneFromFile(scenePath_)
            SetupViewport()
        end
    end
end

function HandlePostRenderUpdate(eventType, eventData)
    -- Draw debug geometry if enabled
    if drawDebug then
        local debugRenderer = scene_:GetComponent("DebugRenderer")
        if debugRenderer then
            -- Draw physics debug
            local physicsWorld = scene_:GetComponent("PhysicsWorld")
            if physicsWorld then
                physicsWorld:DrawDebugGeometry(debugRenderer, true)
            end
        end
    end
end
