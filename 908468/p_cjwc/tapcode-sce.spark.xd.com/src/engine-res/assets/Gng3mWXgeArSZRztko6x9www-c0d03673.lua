-- ScenePreview.lua
-- Preview script for loading and viewing scene.xml files (including WorldPartition scenes).
-- Provides a text field to enter the path and a Load button.
-- Uses UrhoX UI (Yoga + NanoVG) and freelook camera.
--
-- Usage:
--   UrhoXRuntime ScenePreview.lua -p <UrhoXRes path>

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")

-- Runtime state
local pathField = nil
local statusLabel = nil
local modeLabel = nil
local DEFAULT_PATH = "scene.xml"
local hismCullEnabled = true
local fogToggleBtn = nil

-- Loading overlay state
local loadingOverlay = nil
local loadingLabel = nil
local loadingBarFill = nil
local loadingToggleBtn = nil
local loadingVisible = false
local wpComponent = nil

function Start()
    SampleStart()
    CreateScene()
    CreateUI()
    SetupViewport()
    SampleInitMouseMode(MM_ABSOLUTE)
    SubscribeToEvents()
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    SetupLighting()
    SetupCamera()
end

function CreateUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/Anonymous Pro.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- Top bar
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                padding = 10,
                gap = 10,
                backgroundColor = { 30, 30, 30, 200 },
                flexWrap = "wrap",
                children = {
                    UI.Label {
                        text = "Path:",
                        fontSize = 14,
                        color = { 255, 255, 255, 255 },
                    },
                    UI.TextField {
                        value = DEFAULT_PATH,
                        width = 550,
                        fontSize = 13,
                        placeholder = "scene.xml ...",
                        ref = function(self)
                            pathField = self
                        end,
                        onSubmit = function(self, value)
                            LoadScene(value)
                        end,
                    },
                    UI.Button {
                        text = "Load",
                        fontSize = 13,
                        paddingLeft = 16,
                        paddingRight = 16,
                        onClick = function(self)
                            if pathField then
                                LoadScene(pathField.props.value or "")
                            end
                        end,
                    },
                    UI.Button {
                        text = "Fog: ON",
                        fontSize = 13,
                        paddingLeft = 16,
                        paddingRight = 16,
                        ref = function(self)
                            fogToggleBtn = self
                        end,
                        onClick = function(self)
                            ToggleFog()
                        end,
                    },
                    UI.Label {
                        text = "",
                        fontSize = 12,
                        color = { 180, 255, 180, 255 },
                        ref = function(self)
                            statusLabel = self
                        end,
                    },
                    UI.Button {
                        text = "Loading: OFF",
                        fontSize = 13,
                        paddingLeft = 16,
                        paddingRight = 16,
                        ref = function(self)
                            loadingToggleBtn = self
                        end,
                        onClick = function(self)
                            ToggleLoadingOverlay()
                        end,
                    },
                    UI.Label {
                        text = "RMB+WASD | Shift=fast | Q/E=up/down",
                        fontSize = 11,
                        color = { 140, 140, 140, 255 },
                        marginLeft = 10,
                    },
                },
            },
        },
    }

    -- Loading overlay (initially hidden)
    loadingOverlay = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        children = {
            UI.Panel {
                alignItems = "center",
                gap = 12,
                children = {
                    UI.Label {
                        text = "Loading...",
                        fontSize = 22,
                        color = { 255, 255, 255, 255 },
                        ref = function(self)
                            loadingLabel = self
                        end,
                    },
                    -- Progress bar background
                    UI.Panel {
                        width = 300,
                        height = 8,
                        backgroundColor = { 60, 60, 60, 255 },
                        borderRadius = 4,
                        children = {
                            UI.Panel {
                                width = 0,
                                height = "100%",
                                backgroundColor = { 80, 200, 120, 255 },
                                borderRadius = 4,
                                ref = function(self)
                                    loadingBarFill = self
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    root:AddChild(loadingOverlay)

    UI.SetRoot(root)
end

function SetStatus(text)
    if statusLabel then
        statusLabel.text = text
    end
    print("[ScenePreview] " .. text)
end

function LoadScene(path)
    if not path or path == "" then
        SetStatus("Error: empty path")
        return
    end

    -- Save camera transform
    local camPos = cameraNode.position
    local camRot = cameraNode.rotation

    -- Load scene XML — this handles both regular scenes and WorldPartition scenes
    -- (WorldPartitionComponent auto-loads via its "World Data Path" attribute on deserialization)
    if not scene_:LoadXML(path) then
        SetStatus("Error: failed to load " .. path)
        scene_:CreateComponent("Octree")
        SetupLighting()
        SetupCamera(camPos, camRot)
        SetupViewport()
        return
    end

    -- Scene loaded — ensure environment is set up
    EnsureLighting()
    EnsureFog()
    SetupCamera(camPos, camRot)
    SetupViewport()

    -- Add DebugRenderer if not present
    if not scene_:GetComponent("DebugRenderer") then
        scene_:CreateComponent("DebugRenderer")
    end

    local count = scene_:GetNumChildren(true)
    SetStatus("Loaded: " .. count .. " nodes")

    -- Check for WorldPartitionComponent and show loading overlay
    wpComponent = scene_:GetComponent("WorldPartitionComponent")
    if wpComponent and not wpComponent.initialLoadComplete then
        ShowLoadingOverlay(true)
    end
end

function ToggleFog()
    hismCullEnabled = not hismCullEnabled

    local zone = scene_:GetComponent("Zone", true)
    if zone then
        if hismCullEnabled then
            zone.fogStart = 420.0
            zone.fogEnd = 500.0
        else
            zone.fogStart = 1000.0
            zone.fogEnd = 2000.0
        end
    end

    if fogToggleBtn then
        fogToggleBtn.text = hismCullEnabled and "Fog: ON" or "Fog: OFF"
    end

    SetStatus("Fog: " .. (hismCullEnabled and "ON" or "OFF"))
end

function EnsureLighting()
    -- If the loaded scene already has a LightGroup or directional light, skip
    local existingLight = scene_:GetComponent("Light", true)
    if existingLight then return end

    SetupLighting()
end

function EnsureFog()
    local zone = scene_:GetComponent("Zone", true)
    if zone then
        zone.fogStart = hismCullEnabled and 420.0 or 1000.0
        zone.fogEnd = hismCullEnabled and 500.0 or 2000.0
    end
end

function SetupLighting()
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    if lightGroupFile then
        local lightGroup = scene_:CreateChild("LightGroup")
        lightGroup:LoadXML(lightGroupFile:GetRoot())
    else
        -- Fallback: simple lighting if LightGroup not available
        local zoneNode = scene_:CreateChild("Zone")
        local zone = zoneNode:CreateComponent("Zone")
        zone.boundingBox = BoundingBox(-1000, 1000)
        zone.ambientColor = Color(0.3, 0.3, 0.3)

        local lightNode = scene_:CreateChild("DirectionalLight")
        lightNode.direction = Vector3(0.5, -1.0, 0.7)
        local light = lightNode:CreateComponent("Light")
        light.lightType = LIGHT_DIRECTIONAL
        light.color = Color(0.9, 0.9, 0.85)
        light.specularIntensity = 0.5
    end
end

function SetupCamera(pos, rot)
    cameraNode = scene_:CreateChild("Camera")
    local cam = cameraNode:CreateComponent("Camera")
    cam.farClip = 5000.0
    cameraNode.position = pos or Vector3(20, 15, -10)
    cameraNode.rotation = rot or Quaternion(35, 0, 0)
end

function SetupViewport()
    local viewport = Viewport:new(scene_, cameraNode:GetComponent("Camera"))
    renderer:SetViewport(0, viewport)
end

function MoveCamera(timeStep)
    if not input:GetMouseButtonDown(MOUSEB_RIGHT) then return end

    local MOVE_SPEED = 10.0
    local MOUSE_SENSITIVITY = 0.1

    if input:GetKeyDown(KEY_SHIFT) then
        MOVE_SPEED = MOVE_SPEED * 3
    end
    if input:GetKeyDown(KEY_CTRL) then
        MOVE_SPEED = MOVE_SPEED * 0.2
    end

    local mouseMove = input.mouseMove
    yaw = yaw + MOUSE_SENSITIVITY * mouseMove.x
    pitch = pitch + MOUSE_SENSITIVITY * mouseMove.y
    pitch = Clamp(pitch, -89.0, 89.0)

    cameraNode.rotation = Quaternion(pitch, yaw, 0.0)

    if input:GetKeyDown(KEY_W) then
        cameraNode:Translate(Vector3(0, 0, 1) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_S) then
        cameraNode:Translate(Vector3(0, 0, -1) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_A) then
        cameraNode:Translate(Vector3(-1, 0, 0) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_D) then
        cameraNode:Translate(Vector3(1, 0, 0) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_Q) then
        cameraNode:Translate(Vector3(0, -1, 0) * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_E) then
        cameraNode:Translate(Vector3(0, 1, 0) * MOVE_SPEED * timeStep)
    end
end

function ShowLoadingOverlay(show)
    loadingVisible = show
    if loadingOverlay then
        loadingOverlay.visible = show
    end
    if loadingToggleBtn then
        loadingToggleBtn.text = show and "Loading: ON" or "Loading: OFF"
    end
end

function ToggleLoadingOverlay()
    ShowLoadingOverlay(not loadingVisible)
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("WorldPartitionReady", "HandleWorldPartitionReady")
end

function HandleWorldPartitionReady(eventType, eventData)
    ShowLoadingOverlay(false)
    SetStatus("WorldPartition ready")
end

function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()
    MoveCamera(timeStep)

    -- Update loading progress
    if loadingVisible and wpComponent and not wpComponent.initialLoadComplete then
        local pct = math.floor(wpComponent.loadingProgress * 100)
        local activated = wpComponent.activatedCellsInRange
        local total = wpComponent.totalCellsInRange
        if loadingLabel then
            loadingLabel.text = string.format("Loading %d%%  (%d/%d)", pct, activated, total)
        end
        if loadingBarFill then
            loadingBarFill.width = math.floor(300 * wpComponent.loadingProgress)
        end
    end
end
