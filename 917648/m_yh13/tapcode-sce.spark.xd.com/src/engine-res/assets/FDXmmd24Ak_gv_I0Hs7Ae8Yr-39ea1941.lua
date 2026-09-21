-- ============================================================================
-- UrhoX Lua Script Template
-- ============================================================================
-- This is a simple template to help you get started with UrhoX Lua scripting.
--
-- HOW TO USE:
-- 1. Copy this file and rename it to your project name (e.g., MyGame.lua)
-- 2. Fill in the Start() function with your initialization code
-- 3. Add event handlers and custom functions as needed
-- 4. Run with: Urho3DPlayer Scripts=LuaScripts/YourScript.lua
-- ============================================================================

-- Import the Sample utility module (provides common functions like scene setup)
require "LuaScripts/Utilities/Sample"

-- ============================================================================
-- GLOBAL VARIABLES
-- ============================================================================
-- Define your global variables here
local instructionText = nil
local modelScene = nil
local modelCameraNode = nil
local boxNode = nil
local boxRotation = 0

-- ============================================================================
-- ENTRY POINT: Start()
-- ============================================================================
-- This function is called when the script starts
-- Put your initialization code here
function Start()
    -- Initialize the sample framework
    SampleStart()

    -- Create 3D scene for model display
    CreateModelScene()

    -- Create the user interface
    CreateUI()

    -- Setup viewport for model display
    SetupModelViewport()

    -- Set mouse mode (MM_FREE, MM_RELATIVE, MM_WRAP)
    SampleInitMouseMode(MM_FREE)

    -- Subscribe to events
    SubscribeToEvents()
end

-- ============================================================================
-- 3D MODEL SCENE
-- ============================================================================
function CreateModelScene()
    -- Create a separate scene for the 3D model
    modelScene = Scene()
    modelScene:CreateComponent("Octree")

    -- 使用 LightGroup 加载预设光照环境
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = modelScene:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    -- 修改 Zone 的背景颜色为黑色
    local zone = lightGroup:GetComponent("Zone")
    if zone then
        zone.fogColor = Color(0.0, 0.0, 0.0, 1.0)  -- 黑色背景
    end

    -- Create the SM_BOX model node
    boxNode = modelScene:CreateChild("SM_BOX")
    boxNode.position = Vector3(0.0, 1.0, 0.0)  -- 往上移动
    boxNode.scale = Vector3(0.013, 0.013, 0.013)  -- 缩小模型到 2%

    -- Create StaticModel component and load the model
    local boxModel = boxNode:CreateComponent("StaticModel")
    boxModel.model = cache:GetResource("Model", "StaticMeshes/BeveledCube/BeveledCube.mdl")
    boxModel.material = cache:GetResource("Material", "Materials/HammeredSilver.material")

    -- Create camera for viewing the model
    modelCameraNode = modelScene:CreateChild("Camera")
    modelCameraNode.position = Vector3(0.0, 2.0, -5.0)  -- 合理的相机距离
    modelCameraNode:LookAt(Vector3(0.0, 1.0, 0.0))
    local camera = modelCameraNode:CreateComponent("Camera")
    camera.farClip = 100.0
    camera.fov = 45.0
end

function SetupModelViewport()
    renderer.numViewports = 1
    
    -- 按原来的百分比计算viewport区域（右侧大片区域）
    local left = math.floor(graphics.width * 0.55)
    local top = math.floor(graphics.height * 0.27)
    local right = math.floor(graphics.width * 0.87)
    local bottom = math.floor(graphics.height * 0.78)
    
    -- 最小安全尺寸保护（避免纹理创建失败）
    local minSafeSize = 64
    local width = right - left
    local height = bottom - top
    
    if width < minSafeSize then
        width = minSafeSize
        right = left + width
    end
    if height < minSafeSize then
        height = minSafeSize
        bottom = top + height
    end
    
    -- 创建viewport
    local modelViewport = Viewport:new(modelScene, modelCameraNode:GetComponent("Camera"),
        IntRect(left, top, right, bottom))
    renderer:SetViewport(0, modelViewport)
end

-- ============================================================================
-- USER INTERFACE
-- ============================================================================
function CreateUI()
    -- Create a title text
    local titleText = Text:new()
    titleText.text = "Welcome to UrhoX!"
    titleText:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), 40)
    titleText.color = Color(0.0, 1.0, 1.0)  -- Cyan color
    titleText.horizontalAlignment = HA_CENTER
    titleText.verticalAlignment = VA_TOP
    titleText:SetPosition(0, 50)
    ui.root:AddChild(titleText)

    -- Create instruction text
    instructionText = Text:new()
    instructionText.text =
        "This is a template script. Edit this file to create your own game!\n\n" ..
        "Quick Start Guide:\n" ..
        "  1. Modify the Start() function to initialize your game\n" ..
        "  2. Add your game logic in HandleUpdate()\n" ..
        "  3. Handle input in HandleKeyDown() and HandleKeyUp()\n\n" ..
        "Useful Resources:\n" ..
        "  - Check other samples in LuaScripts/ folder\n" ..
        "  - UrhoX documentation: https://xxx/\n" ..
        "  - Sample.lua provides helper functions\n\n" ..
        "Press ESC to exit"

    instructionText:SetFont(cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), 16)
    instructionText.color = Color(1.0, 1.0, 1.0)  -- White color
    instructionText.horizontalAlignment = HA_LEFT
    instructionText.verticalAlignment = VA_CENTER
    instructionText:SetPosition(50, 0)
    instructionText.textAlignment = HA_LEFT
    ui.root:AddChild(instructionText)
end

-- ============================================================================
-- EVENT SUBSCRIPTION
-- ============================================================================
function SubscribeToEvents()
    -- Subscribe to the frame update event
    SubscribeToEvent("Update", "HandleUpdate")

    -- Subscribe to keyboard events
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    
    -- Subscribe to window resize event
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Called every frame
-- timeStep: Frame duration in seconds
function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()

    -- Rotate the box model for display
    if boxNode then
        boxRotation = boxRotation + timeStep * 30.0  -- 30 degrees per second
        if boxRotation >= 360.0 then
            boxRotation = boxRotation - 360.0
        end
        -- 先设置 Pitch 45 度和 Roll 45 度的基础姿态，再绕 Y 轴旋转
        -- Quaternion(pitch, yaw, roll) 顺序
        boxNode.rotation = Quaternion(45.0, boxRotation, 45.0)
    end
end

-- Called when a key is pressed
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- Handle ESC key to exit
    if key == KEY_ESCAPE then
        engine:Exit()
    end

    -- TODO: Add your key handling here
    -- Examples:
    --   if key == KEY_W then
    --       -- Move forward
    --   elseif key == KEY_SPACE then
    --       -- Jump
    --   end
end

-- Called when a key is released
function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- TODO: Add your key release handling here
end

-- Called when screen mode changes (window resize, fullscreen toggle, etc.)
function HandleScreenMode(eventType, eventData)
    -- Recalculate viewport when window size changes
    SetupModelViewport()
end

-- ============================================================================
-- EXAMPLE: CREATE A 3D SCENE (Commented out by default)
-- ============================================================================
--[[
function CreateScene()
    -- Create the scene
    scene_ = Scene()

    -- Create octree for spatial indexing
    scene_:CreateComponent("Octree")

    -- Create a Zone component for ambient lighting
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
    light.color = Color(0.4, 0.4, 0.4)
    light.castShadows = true

    -- Create a camera
    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0.0, 5.0, -10.0)
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 300.0

    -- Setup viewport
    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end
--]]

-- ============================================================================
-- EXAMPLE: CREATE A SPRITE (Commented out by default)
-- ============================================================================
--[[
function CreateSprite()
    -- Load texture
    local spriteTexture = cache:GetResource("Texture2D", "Urho2D/Aster.png")

    -- Create sprite
    local sprite = ui.root:CreateChild("Sprite")
    sprite:SetTexture(spriteTexture)
    sprite:SetFullImageRect()
    sprite:SetSize(128, 128)
    sprite.position = Vector2(graphics.width / 2, graphics.height / 2)
    sprite.hotSpot = IntVector2(64, 64)

    return sprite
end
--]]

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Add your utility functions here
-- Examples:
--   - function SpawnEnemy(position)
--   - function UpdateScore(points)
--   - function PlaySound(soundFile)

-- ============================================================================
-- MOBILE/TOUCH SUPPORT (Optional)
-- ============================================================================

-- Define screen joystick layout
function GetScreenJoystickPatchString()
    return
        "<patch>" ..
        "    <add sel=\"/element/element[./attribute[@name='Name' and @value='Hat0']]\">" ..
        "        <attribute name=\"Is Visible\" value=\"false\" />" ..
        "    </add>" ..
        "</patch>"
end

-- ============================================================================
-- END OF TEMPLATE
-- ============================================================================
-- Happy coding! For more examples, check the other sample scripts:
--   - 01_HelloWorld.lua - Basic text display
--   - 03_Sprites.lua - Moving sprites
--   - 04_StaticScene.lua - 3D scene setup
--   - 11_Physics.lua - Physics simulation
--   - And many more in the LuaScripts/ folder!
-- ============================================================================
