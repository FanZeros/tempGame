-- TileSetPreview.lua
-- Standalone preview script for TileSet tiles.
-- Loads a TileSet JSON, instantiates all tile prefabs in a grid,
-- and provides a freelook camera to inspect them.
-- Uses UrhoX UI (Yoga + NanoVG) for the TileSet selector dropdown.
--
-- Usage:
--   UrhoXRuntime TileSetPreview.lua -p <UrhoXRes path>

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")

-- ============================================================
-- Configuration
-- ============================================================
local TILESET_DIR  = "TileSets"
local DEFAULT_NAME = "me_tiles_field"
local SPACING      = 0.5

-- Runtime state
local previewNode = nil
local previewObj  = nil
local tileSetList = {}       -- { "me_tiles_field", "me_tiles_hope", ... }
local currentName = ""

function Start()
    SampleStart()
    CreateScene()
    ScanTileSets()
    CreateUI()
    SetupViewport()
    SampleInitMouseMode(MM_ABSOLUTE)
    SubscribeToEvents()
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- Zone (ambient light)
    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(-1000, 1000)
    zone.ambientColor = Color(0.3, 0.3, 0.3)

    -- Directional light
    local lightNode = scene_:CreateChild("DirectionalLight")
    lightNode.direction = Vector3(0.5, -1.0, 0.7)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(0.9, 0.9, 0.85)
    light.specularIntensity = 0.5

    -- Ground plane
    local groundNode = scene_:CreateChild("Ground")
    groundNode.scale = Vector3(200, 1, 200)
    groundNode.position = Vector3(0, -3.0, 0)
    local groundModel = groundNode:CreateComponent("StaticModel")
    groundModel.model = cache:GetResource("Model", "Models/Plane.mdl")
    groundModel.material = cache:GetResource("Material", "Materials/StoneTiled.xml")

    -- TileSet preview node
    previewNode = scene_:CreateChild("TileSetPreview")
    previewObj = previewNode:CreateScriptObject("Scripts/TileSetPreview.lua", "TileSetPreview")
    previewObj.spacing = SPACING

    -- Camera
    cameraNode = scene_:CreateChild("Camera")
    cameraNode:CreateComponent("Camera")
    cameraNode.position = Vector3(0, 15, -20)
    cameraNode.rotation = Quaternion(35, 0, 0)
end

function ScanTileSets()
    tileSetList = {
        "me_tiles_field",
    }
    print("[TileSetPreview] TileSets: " .. table.concat(tileSetList, ", "))
end

function CreateUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/Anonymous Pro.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- Build dropdown options from scanned tilesets
    local options = {}
    local defaultValue = nil
    for i, name in ipairs(tileSetList) do
        table.insert(options, { value = name, label = name })
        if name == DEFAULT_NAME then
            defaultValue = name
        end
    end
    -- Fallback to first if default not found
    if defaultValue == nil and #tileSetList > 0 then
        defaultValue = tileSetList[1]
    end

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
                children = {
                    UI.Label {
                        text = "TileSet:",
                        fontSize = 14,
                        color = { 255, 255, 255, 255 },
                    },
                    UI.Dropdown {
                        options = options,
                        value = defaultValue,
                        width = 250,
                        placeholder = "Select TileSet...",
                        onChange = function(self, value, option)
                            LoadTileSet(value)
                        end,
                    },
                    UI.Label {
                        text = "RMB + WASD to move | Shift=fast | Q/E=up/down",
                        fontSize = 11,
                        color = { 180, 180, 180, 255 },
                        marginLeft = 20,
                    },
                },
            },
        },
    }

    UI.SetRoot(root)

    -- Load default tileset
    if defaultValue then
        LoadTileSet(defaultValue)
    end
end

function LoadTileSet(name)
    if name == currentName then return end
    currentName = name

    local jsonPath = TILESET_DIR .. "/" .. name .. ".json"
    print("[TileSetPreview] Switching to: " .. jsonPath)

    previewObj:ClearTiles()
    previewObj.tileSetJsonPath = jsonPath
    previewObj.loaded = false
    previewObj:LoadTileSet()
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

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()
    MoveCamera(timeStep)
end
