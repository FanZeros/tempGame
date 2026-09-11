-- ============================================================================
-- VideoScreen3D Example - IMAX 视频屏幕示例
-- ============================================================================
-- 演示如何在 3D 场景中创建视频屏幕
--
-- 功能:
--   - 在 3D 世界中显示视频
--   - 正确的 UV 映射（无颠倒/镜像）
--   - 无光照材质（视频颜色不变暗）
--   - 可选边框
--   - 播放控制
--
-- 控制:
--   WASD: 移动
--   鼠标: 旋转视角
--   空格: 播放/暂停
--   R: 重新播放
--   M: 静音切换
--   ESC: 退出
-- ============================================================================

-- 引入输入扩展（处理 Web 平台鼠标模式）
require("urhox-libs/Engine/InputExtensions")

-- 引入 VideoScreen3D 模块
local VideoScreen3D = require("urhox-libs/Video/VideoScreen3D")
local UI = require("urhox-libs/UI")

-- 全局变量
local scene_ = nil
local cameraNode = nil
local videoScreen = nil

-- 相机控制变量
local yaw = 0.0
local pitch = 0.0

function Start()
    -- 创建场景
    CreateScene()

    -- 创建视频屏幕
    CreateVideoScreen()

    -- 创建 UI 说明
    CreateInstructions()

    -- 设置视口
    SetupViewport()

    -- 订阅事件
    SubscribeToEvents()

    -- 设置鼠标模式（相对模式，隐藏鼠标用于 FPS 控制）
    input:SetMouseMode(MM_RELATIVE)
    input.mouseVisible = false

    print("=== VideoScreen3D Example ===")
    print("Controls: WASD=Move, Mouse=Look, Space=Play/Pause, R=Restart, M=Mute")
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function CreateScene()
    scene_ = Scene:new()

    -- 创建场景组件
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- 创建 Zone（环境光 + 雾）
    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-1000, -1000, -1000), Vector3(1000, 1000, 1000))
    zone.ambientColor = Color(0.2, 0.2, 0.2)
    zone.fogColor = Color(0.1, 0.1, 0.15)
    zone.fogStart = 50.0
    zone.fogEnd = 200.0

    -- 创建定向光
    local lightNode = scene_:CreateChild("DirectionalLight")
    lightNode.direction = Vector3(0.5, -1.0, 0.5)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(0.6, 0.6, 0.6)
    light.castShadows = true

    -- 创建地板
    local floorNode = scene_:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.5, 0)
    floorNode.scale = Vector3(100, 1, 100)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    floorModel:SetMaterial(cache:GetResource("Material", "Materials/Stone.xml"))

    -- 创建相机
    cameraNode = scene_:CreateChild("Camera")
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 300.0
    camera.nearClip = 0.1
    cameraNode.position = Vector3(0, 2, -10)  -- 站在屏幕前方

    print("[Example] Scene created")
end

-- ============================================================================
-- 视频屏幕创建
-- ============================================================================

function CreateVideoScreen()
    -- 方式 1: 最简创建（使用默认 720p 分辨率）
    -- ⚠️ 注意: videoWidth/videoHeight 必须指定！不支持自动检测！
    -- 如果不传，默认使用 1280x720 (720p)
    -- 如果视频不是 720p，必须手动指定正确的分辨率！
    --[[
    videoScreen = VideoScreen3D.Create(scene_, {
        -- videoUrl: virtual path ("videos/intro.mp4"), uuid ("uuid://xxx"), or https URL
        videoUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        videoWidth = 1280,   -- ⚠️ 必须指定！720p
        videoHeight = 720,   -- ⚠️ 必须指定！
        autoPlay = true,
        loop = true,
    })
    ]]

    -- 方式 2: 完整配置（手动指定视频尺寸）
    videoScreen = VideoScreen3D.Create(scene_, {
        -- videoUrl: virtual path ("videos/intro.mp4"), uuid ("uuid://xxx"), or https URL
        videoUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",

        -- 屏幕位置和大小
        position = Vector3(0, 6, 25),  -- 前方 25 米，高度 6 米
        width = 16,                     -- 屏幕宽度（米）
        height = 9,                     -- 屏幕高度（米）

        -- ⚠️ 视频分辨率（必须指定！不支持自动检测）
        -- BigBuckBunny 是 1280x720 (720p)
        -- 常见分辨率: 720p=1280x720, 1080p=1920x1080, 4K=3840x2160
        videoWidth = 1280,
        videoHeight = 720,

        -- 自动调整屏幕大小以匹配视频宽高比
        autoResizeToVideo = true,

        -- 播放设置
        autoPlay = true,
        loop = true,
        volume = 1.0,
        muted = false,

        -- 边框设置
        showFrame = true,
        frameWidth = 0.4,
        frameColor = Color(0.05, 0.05, 0.05, 1.0),

        -- 双面渲染（悬浮屏幕，玩家可绕到背后观看）
        doubleSided = true,

        -- 调试模式（打印尺寸检测信息）
        debug = true,
    })

    -- 让屏幕面向玩家位置
    videoScreen:LookAt(Vector3(0, 2, -10))

    print("[Example] Video screen created")
end

-- ============================================================================
-- UI 创建
-- ============================================================================

function CreateInstructions()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 多行内容拆成多个 Label + flexDirection="column" (recipes/ui.md §11 模式 A)
    -- 单 Label 多行 \n 行为不可靠, 见 scaffold-3d-scene 与 PhysicsCollision3D 的范式
    UI.SetRoot(UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        paddingTop = 10,
        alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "column",
                alignItems = "center",
                children = {
                    UI.Label { text = "WASD: Move | Mouse: Look", fontSize = 15, fontColor = { 255, 255, 255, 255 } },
                    UI.Label { text = "Space: Play/Pause | R: Restart | M: Mute", fontSize = 15, fontColor = { 255, 255, 255, 255 } },
                    UI.Label { text = "(Video playback only works on WASM)", fontSize = 15, fontColor = { 255, 255, 255, 255 } },
                },
            },
        }
    })
end

-- ============================================================================
-- 视口设置
-- ============================================================================

function SetupViewport()
    local viewport = Viewport:new(scene_, cameraNode:GetComponent("Camera"))
    renderer:SetViewport(0, viewport)
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()

    -- 更新视频（必须每帧调用！）
    if videoScreen then
        videoScreen:Update()
    end

    -- 相机控制
    MoveCamera(timeStep)

    -- 播放控制
    HandlePlaybackInput()
end

-- ============================================================================
-- 相机移动
-- ============================================================================

function MoveCamera(timeStep)
    if ui.focusElement ~= nil then return end

    local MOVE_SPEED = 10.0
    local MOUSE_SENSITIVITY = 0.1

    -- 鼠标旋转
    local mouseMove = input.mouseMove
    yaw = yaw + MOUSE_SENSITIVITY * mouseMove.x
    pitch = pitch + MOUSE_SENSITIVITY * mouseMove.y
    pitch = Clamp(pitch, -89.0, 89.0)

    cameraNode.rotation = Quaternion(pitch, yaw, 0.0)

    -- WASD 移动
    if input:GetKeyDown(KEY_W) then
        cameraNode:Translate(Vector3.FORWARD * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_S) then
        cameraNode:Translate(Vector3.BACK * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_A) then
        cameraNode:Translate(Vector3.LEFT * MOVE_SPEED * timeStep)
    end
    if input:GetKeyDown(KEY_D) then
        cameraNode:Translate(Vector3.RIGHT * MOVE_SPEED * timeStep)
    end
end

-- ============================================================================
-- 播放控制输入
-- ============================================================================

function HandlePlaybackInput()
    if not videoScreen then return end

    -- 空格: 播放/暂停
    if input:GetKeyPress(KEY_SPACE) then
        if videoScreen:IsPlaying() then
            videoScreen:Pause()
            print("[Example] Paused")
        else
            videoScreen:Play()
            print("[Example] Playing")
        end
    end

    -- R: 重新播放
    if input:GetKeyPress(KEY_R) then
        videoScreen:Seek(0)
        videoScreen:Play()
        print("[Example] Restarted")
    end

    -- M: 静音切换
    if input:GetKeyPress(KEY_M) then
        local isMuted = videoScreen:IsMuted()
        videoScreen:SetMuted(not isMuted)
        print("[Example] Muted: " .. tostring(not isMuted))
    end
end

-- ============================================================================
-- 清理
-- ============================================================================

function Stop()
    UI.Shutdown()
    if videoScreen then
        videoScreen:Destroy()
        videoScreen = nil
    end
end
